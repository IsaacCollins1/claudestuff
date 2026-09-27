--!strict
-- NPC customers: walk in, pick products off stocked shelves, queue at the
-- checkout, pay the store owner and leave.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Progression = require(Shared.Progression)
local StoreLevels = require(Shared.StoreLevels)
local Upgrades = require(Shared.Upgrades)

local NpcBuilder = require(script.Parent.Parent.Builders.NpcBuilder)
local Events = require(script.Parent.Events)
local Net = require(script.Parent.Net)
local NpcMotion = require(script.Parent.NpcMotion)
local Perks = require(script.Parent.Perks)
local PlayerData = require(script.Parent.PlayerData)
local Registry = require(script.Parent.Registry)
local Shelves = require(script.Parent.Shelves)

type Store = Registry.Store
type Shelf = Registry.Shelf

type Customer = {
	Store: Store,
	Npc: NpcBuilder.Npc,
	Walker: NpcMotion.Walker,
	Basket: BasePart,
	Items: { string },
	Models: { Model },
	ReservedShelf: Shelf?,
	Node: string,
	Alive: boolean,
	Run: number, -- the owner's rebirth count when this customer arrived
}

local Customers = {}

local rng = Random.new()

local BASKET_COLORS = {
	Color3.fromRGB(230, 60, 60),
	Color3.fromRGB(60, 140, 240),
	Color3.fromRGB(60, 190, 90),
}

-- Where products sit inside a basket (up to 4 visible).
local BASKET_SLOTS = {
	Vector3.new(-0.28, 0.06, -0.18),
	Vector3.new(0.28, 0.06, -0.18),
	Vector3.new(-0.28, 0.06, 0.2),
	Vector3.new(0.28, 0.06, 0.2),
}

local function customersFolder(store: Store): Instance
	local folder = store.Model:FindFirstChild("Customers")
	if folder then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "Customers"
	newFolder.Parent = store.Model
	return newFolder
end

local function putInBasket(customer: Customer, model: Model)
	local count = #customer.Models + 1
	local slot = BASKET_SLOTS[(count - 1) % #BASKET_SLOTS + 1]
	local stackHeight = math.floor((count - 1) / #BASKET_SLOTS) * 0.5
	model:ScaleTo(0.7)
	model:PivotTo(customer.Basket.CFrame * CFrame.new(slot + Vector3.new(0, stackHeight, 0)))
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = customer.Basket
			weld.Part1 = part
			weld.Parent = part
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
		end
	end
	model:SetAttribute("Pop", nil)
	model.Parent = customer.Npc.Model
	table.insert(customer.Models, model)
end

local function checkout(customer: Customer)
	local store = customer.Store
	local layout = store.Layout
	local plotCFrame = store.Session.PlotCFrame
	table.insert(store.Queue, customer)

	-- Walk to the aisle next to the till, then join the queue.
	local path = StoreLevels.findPath(layout, customer.Node, layout.CheckoutNode)
	table.remove(path)
	NpcMotion.walkPath(customer.Walker, plotCFrame, path)
	while true do
		NpcMotion.check(customer.Walker)
		local index = table.find(store.Queue, customer) or 1
		local spot = plotCFrame:PointToWorldSpace(StoreLevels.queuePosition(layout, index))
		NpcMotion.walkTo(customer.Walker, spot)
		if index == 1 then
			break
		end
		task.wait(0.3)
	end
	customer.Node = layout.CheckoutNode

	NpcMotion.face(customer.Npc, store.Register.Position)
	task.wait(Config.CheckoutTime)
	NpcMotion.check(customer.Walker)

	-- Pay! Products with stars sell for more; rebirths and 2x Cash multiply it all.
	local owner = store.Owner
	local data = PlayerData.get(owner)
	local total = 0
	local rare = false
	for _, key in customer.Items do
		local sold = if data then data.Sold[Items.product(key).Id] or 0 else 0
		total += Items.sellPrice(key) * Progression.starMultiplier(sold)
		rare = rare or Items.isRare(key)
	end
	local multiplier = Perks.cashMultiplier(owner)
	total = math.floor(total * multiplier)
	if data then
		data.Stats.ItemsSold += #customer.Items
		PlayerData.addCash(owner, total)
		Events.Sale:Fire(owner, total, table.clone(customer.Items))
	end
	Net.effectAll("Sale", {
		Position = store.Register.Position + Vector3.new(0, 2.2, 0),
		Amount = total,
		Rare = rare,
		Multiplier = multiplier,
		OwnerId = owner.UserId,
	})
	for _, model in customer.Models do
		model:Destroy()
	end
	table.clear(customer.Models)
	table.clear(customer.Items)
	NpcMotion.emote(customer.Npc, if rare then "🤩" else "😊")

	local queueIndex = table.find(store.Queue, customer)
	if queueIndex then
		table.remove(store.Queue, queueIndex)
	end
end

local function behave(customer: Customer)
	local store = customer.Store
	local layout = store.Layout
	local plotCFrame = store.Session.PlotCFrame

	NpcMotion.walkPath(customer.Walker, plotCFrame, StoreLevels.findPath(layout, "Spawn", "Door"))
	customer.Node = "Door"

	local wants = rng:NextInteger(1, layout.Spec.MaxItemsPerCustomer)
	for _ = 1, wants do
		local shelf = Shelves.reserve(store)
		if not shelf then
			break
		end
		customer.ReservedShelf = shelf
		NpcMotion.walkPath(customer.Walker, plotCFrame, StoreLevels.findPath(layout, customer.Node, shelf.Node))
		customer.Node = shelf.Node
		NpcMotion.face(customer.Npc, shelf.CFrame.Position)
		task.wait(Config.CustomerBrowseTime * rng:NextNumber(0.8, 1.4))
		NpcMotion.check(customer.Walker)
		customer.ReservedShelf = nil
		local key, model = Shelves.take(shelf)
		if key and model then
			table.insert(customer.Items, key)
			putInBasket(customer, model)
			if Items.isRare(key) then
				NpcMotion.emote(customer.Npc, "🤩")
			end
		end
	end

	if #customer.Items > 0 then
		checkout(customer)
	else
		NpcMotion.emote(customer.Npc, "😞", 2)
		Net.effectAll("Sad", { Position = customer.Npc.Head.Position, OwnerId = store.Owner.UserId })
		task.wait(0.6)
	end

	NpcMotion.walkPath(customer.Walker, plotCFrame, StoreLevels.findPath(layout, customer.Node, "Spawn"))
end

local function cleanup(customer: Customer)
	customer.Alive = false
	local store = customer.Store
	if customer.ReservedShelf then
		Shelves.release(customer.ReservedShelf)
		customer.ReservedShelf = nil
	end
	local queueIndex = table.find(store.Queue, customer)
	if queueIndex then
		table.remove(store.Queue, queueIndex)
	end
	-- Anything still in the basket goes back into the owner's stock
	-- (unless the owner has rebirthed since: that stock belonged to the old run).
	local data = PlayerData.get(store.Owner)
	if data and data.Rebirths == customer.Run then
		for _, key in customer.Items do
			PlayerData.addItem(store.Owner, key, 1)
		end
	end
	table.clear(customer.Items)
	if store.Customers[customer] then
		store.Customers[customer] = nil
		store.CustomerCount -= 1
	end
	customer.Npc.Model:Destroy()
end

function Customers.spawn(store: Store)
	local session = store.Session
	local spawnPoint = StoreLevels.CustomerSpawn + Vector3.new(rng:NextNumber(-2.5, 2.5), 0, 0)
	-- Face into the plot (+Z local).
	local spawnCFrame = session.PlotCFrame * CFrame.new(spawnPoint) * CFrame.Angles(0, math.pi, 0)
	local npc = NpcBuilder.build(spawnCFrame, NpcBuilder.randomStyle(rng), Config.CustomerWalkSpeed * rng:NextNumber(0.9, 1.15))
	npc.Model.Name = "Customer"
	local basket = NpcBuilder.addBasket(npc, BASKET_COLORS[rng:NextInteger(1, #BASKET_COLORS)])
	NpcMotion.setCollisionGroup(npc.Model, "NPC")
	npc.Model.Parent = customersFolder(store)
	pcall(function()
		npc.Root:SetNetworkOwner(nil)
	end)
	NpcBuilder.animate(npc)

	local customer: Customer
	customer = {
		Store = store,
		Npc = npc,
		Walker = {
			Npc = npc,
			IsAlive = function()
				return customer.Alive and store.Alive
			end,
		},
		Basket = basket,
		Items = {},
		Models = {},
		ReservedShelf = nil,
		Node = "Spawn",
		Alive = true,
		Run = (PlayerData.get(store.Owner) or { Rebirths = 0 }).Rebirths,
	}
	store.Customers[customer] = true
	store.CustomerCount += 1

	-- Safety net for anything unexpected.
	task.delay(Config.CustomerMaxLifetime, function()
		customer.Alive = false
	end)

	task.spawn(function()
		local ok, err = pcall(function()
			behave(customer)
		end)
		if not ok and err ~= NpcMotion.Abort then
			warn("[FillTheStore] Customer error: " .. tostring(err))
		end
		cleanup(customer)
	end)
end

-- Spawns customers for as long as the store exists.
function Customers.start(store: Store)
	task.spawn(function()
		task.wait(1.5)
		while store.Alive do
			local data = PlayerData.get(store.Owner)
			local rateLevel = if data then data.Upgrades.CustomerRate else 0
			local maxCustomers = Upgrades.maxCustomers(rateLevel, store.Level) + Perks.extraCustomers(store.Owner)
			if store.CustomerCount < maxCustomers and Shelves.available(store) > 0 then
				Customers.spawn(store)
			end
			local interval = Upgrades.customerInterval(rateLevel) * Perks.customerIntervalMultiplier(store.Owner)
			task.wait(interval * rng:NextNumber(0.75, 1.25))
		end
	end)
end

-- Removes every customer (store closing or being rebuilt).
function Customers.clear(store: Store)
	for customer in store.Customers do
		(customer :: Customer).Alive = false
	end
end

return Customers
