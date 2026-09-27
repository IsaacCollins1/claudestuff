--!strict
-- Shelves: stocking from the player's inventory, the visible product rows,
-- and handing products to customers.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local BoxVisual = require(Shared.BoxVisual)
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local ProductVisuals = require(Shared.ProductVisuals)
local StoreLevels = require(Shared.StoreLevels)

local Boxes = require(script.Parent.Boxes)
local Events = require(script.Parent.Events)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)
local Registry = require(script.Parent.Registry)
local StoreBuilder = require(script.Parent.Parent.Builders.StoreBuilder)

type Shelf = Registry.Shelf
type Store = Registry.Store

local Shelves = {}

Shelves.PromptTag = "OwnedPrompt"

local TIER_HEIGHTS = { 0.5, 2.4, 4.3 }
local rng = Random.new()

local GREEN = Color3.fromRGB(90, 220, 100)
local YELLOW = Color3.fromRGB(255, 200, 50)
local RED = Color3.fromRGB(255, 80, 80)

function Shelves.count(shelf: Shelf): number
	local count = 0
	for index = 1, shelf.Capacity do
		if shelf.Slots[index] then
			count += 1
		end
	end
	return count
end

function Shelves.free(shelf: Shelf): number
	return shelf.Capacity - Shelves.count(shelf)
end

function Shelves.available(store: Store): number
	local total = 0
	for _, shelf in store.Shelves do
		total += math.max(0, Shelves.count(shelf) - shelf.Reserved)
	end
	return total
end

function Shelves.stockValue(store: Store): number
	local value = 0
	for _, shelf in store.Shelves do
		for index = 1, shelf.Capacity do
			local key = shelf.Slots[index]
			if key then
				value += Items.value(key)
			end
		end
	end
	return value
end

-- Slot positions: 3 tiers; each tier gets 1 or 2 rows depending on capacity.
local function computeSlots(shelf: Shelf)
	local capacity = shelf.Capacity
	local perTier = math.ceil(capacity / #TIER_HEIGHTS)
	local rows = if perTier <= 8 then 1 else 2
	local columns = math.ceil(perTier / rows)
	local usable = StoreLevels.ShelfLength - 0.8
	local spacing = usable / columns
	shelf.ItemScale = math.clamp(spacing / 0.95, 1, 1.25)
	local slots = {}
	for _, tierY in TIER_HEIGHTS do
		for row = 1, rows do
			local z = if rows == 1 then -0.3 elseif row == 1 then -0.55 else 0.45
			for column = 1, columns do
				if #slots < capacity then
					local x = -usable / 2 + spacing * (column - 0.5)
					table.insert(slots, shelf.CFrame * CFrame.new(x, tierY, z))
				end
			end
		end
	end
	shelf.SlotCFrames = slots
end

function Shelves.refresh(shelf: Shelf)
	local count = Shelves.count(shelf)
	local ratio = if shelf.Capacity > 0 then count / shelf.Capacity else 0
	shelf.Model:SetAttribute("Count", count)
	shelf.Model:SetAttribute("Capacity", shelf.Capacity)
	shelf.BarFill.Size = UDim2.fromScale(ratio, 1)
	shelf.BarFill.Visible = count > 0
	shelf.BarFill.BackgroundColor3 = if ratio > 0.5 then GREEN elseif ratio > 0.2 then YELLOW else RED
	if count == 0 then
		shelf.CountLabel.Text = "EMPTY!"
		shelf.CountLabel.TextColor3 = RED
	elseif count >= shelf.Capacity then
		shelf.CountLabel.Text = "FULL ✔"
		shelf.CountLabel.TextColor3 = GREEN
	else
		shelf.CountLabel.Text = `{count}/{shelf.Capacity}`
		shelf.CountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
	PlayerData.markDirty(shelf.Store.Owner)
end

-- Put one product model into the first empty slot.
function Shelves.placeItem(shelf: Shelf, key: string, pop: boolean): boolean
	local slot: number? = nil
	for index = 1, shelf.Capacity do
		if not shelf.Slots[index] then
			slot = index
			break
		end
	end
	if not slot then
		return false
	end
	local model = ProductVisuals.build(key, shelf.ItemScale)
	model:PivotTo(shelf.SlotCFrames[slot] * CFrame.Angles(0, rng:NextNumber(-0.12, 0.12), 0))
	model:SetAttribute("Slot", slot)
	if pop then
		-- Clients animate items with this attribute popping onto the shelf.
		model:SetAttribute("Pop", true)
		model:SetAttribute("Fill", (Shelves.count(shelf) + 1) / shelf.Capacity)
	end
	model.Parent = shelf.ItemsFolder
	shelf.Slots[slot] = key
	shelf.SlotModels[slot] = model
	Shelves.refresh(shelf)
	return true
end

-- Which item to put on the shelf next. Sticks with the current product so
-- rows look neat, prefers the box just unpacked, then the player's selected
-- product, then whatever the shelf already holds, then whatever they have most of.
local function nextKey(player: Player, shelf: Shelf, current: string?, prefer: string?): string?
	local data = PlayerData.get(player)
	if not data then
		return nil
	end
	if current and (data.Inventory[current] or 0) > 0 then
		return current
	end
	local onShelf: { [string]: boolean } = {}
	for index = 1, shelf.Capacity do
		local key = shelf.Slots[index]
		if key then
			onShelf[Items.product(key).Id] = true
		end
	end
	local currentProduct = if current then Items.product(current).Id else nil
	local bestKey: string? = nil
	local bestScore = -math.huge
	for key, count in data.Inventory do
		if count > 0 then
			local productId = Items.product(key).Id
			local score = count
			if productId == prefer then
				score += 1e10
			end
			if productId == data.SelectedProduct then
				score += 1e9
			end
			if productId == currentProduct then
				score += 1e8
			end
			if onShelf[productId] then
				score += 1e6
			end
			if score > bestScore or (score == bestScore and bestKey ~= nil and key < bestKey) then
				bestScore = score
				bestKey = key
			end
		end
	end
	return bestKey
end

-- Moves up to `maxItems` products from the player's inventory onto the shelf,
-- one at a time with a short delay so it visibly fills up. Returns how many.
function Shelves.stockFromInventory(player: Player, shelf: Shelf, maxItems: number, delay: number, prefer: string?): number
	if shelf.Busy then
		return 0
	end
	shelf.Busy = true
	local placed = 0
	local current: string? = nil
	local ok, err = pcall(function()
		while placed < maxItems and shelf.Store.Alive and Shelves.free(shelf) > 0 do
			local key = nextKey(player, shelf, current, prefer)
			if not key or not PlayerData.takeItem(player, key, 1) then
				break
			end
			current = key
			if not Shelves.placeItem(shelf, key, true) then
				PlayerData.addItem(player, key, 1)
				break
			end
			placed += 1
			if delay > 0 then
				task.wait(delay)
			end
		end
	end)
	shelf.Busy = false
	if not ok then
		warn("[FillTheStore] Stocking failed: " .. tostring(err))
	end
	return placed
end

local function onStockPrompt(player: Player, shelf: Shelf)
	local store = shelf.Store
	if player ~= store.Owner or not store.Alive or shelf.Busy then
		return
	end
	local prefer: string? = nil
	local session = Registry.session(player)
	if session and session.Carried then
		-- Carrying a box: unpack it right here, products fly onto the shelf.
		local unpackCFrame = shelf.CFrame
			* CFrame.new(0, BoxVisual.Size.Y / 2, -(StoreLevels.ShelfDepth / 2 + 2.4))
			* CFrame.Angles(0, math.pi, 0)
		local shelfMiddle = (shelf.CFrame * CFrame.new(0, 2.5, 0)).Position
		local contents, productId = Boxes.unpackCarried(player, unpackCFrame, shelfMiddle)
		if not contents then
			return
		end
		prefer = productId
		if Shelves.free(shelf) == 0 then
			Net.notify(player, "Info", "📦 Shelf full — the rest went to your stock room")
			return
		end
		shelf.Busy = true
		task.wait(0.6) -- let the box burst open first
		shelf.Busy = false
		if not store.Alive then
			return
		end
	elseif PlayerData.inventoryTotal(player) == 0 then
		Net.notify(player, "Info", "📦 No stock! Grab a delivery box")
		return
	elseif Shelves.free(shelf) == 0 then
		Net.notify(player, "Info", "✔ This shelf is already full!")
		return
	end
	local placed = Shelves.stockFromInventory(player, shelf, math.huge, Config.StockItemDelay, prefer)
	if placed > 0 then
		Events.ShelfStocked:Fire(player, placed)
		Net.effectTo(player, "Stocked", {
			Position = (shelf.CFrame * CFrame.new(0, StoreLevels.ShelfHeight + 2, 0)).Position,
			Count = placed,
			Full = Shelves.free(shelf) == 0,
			Shelf = shelf.Model,
		})
	end
end

-- Creates shelf state for a freshly built store.
function Shelves.setup(store: Store, built: StoreBuilder.Built, capacity: number)
	for index, builtShelf in built.Shelves do
		local shelf: Shelf = {
			Index = index,
			Store = store,
			Model = builtShelf.Model,
			CFrame = builtShelf.CFrame,
			ItemsFolder = builtShelf.ItemsFolder,
			Node = store.Layout.ShelfNodes[index],
			Capacity = capacity,
			ItemScale = 1,
			SlotCFrames = {},
			Slots = {},
			SlotModels = {},
			Reserved = 0,
			Busy = false,
			WorkerAssigned = false,
			BarFill = builtShelf.BarFill,
			CountLabel = builtShelf.CountLabel,
		}
		computeSlots(shelf)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StockPrompt"
		prompt.ActionText = "Stock Shelf"
		prompt.ObjectText = "🛒 Shelf " .. index
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("OwnerUserId", store.Owner.UserId)
		prompt:SetAttribute("Kind", "Shelf")
		CollectionService:AddTag(prompt, Shelves.PromptTag)
		prompt.Parent = builtShelf.PromptAttachment
		prompt.Triggered:Connect(function(player: Player)
			onStockPrompt(player, shelf)
		end)

		table.insert(store.Shelves, shelf)
		Shelves.refresh(shelf)
	end
end

-- Contents of every shelf, in slot order (for saving / rebuilding).
function Shelves.serialize(store: Store): { { string } }
	local result = {}
	for index, shelf in store.Shelves do
		local keys = {}
		for slot = 1, shelf.Capacity do
			local key = shelf.Slots[slot]
			if key then
				table.insert(keys, key)
			end
		end
		result[index] = keys
	end
	return result
end

-- Put saved items back on the shelves (no animation). Anything that doesn't
-- fit goes back into the player's inventory.
function Shelves.restore(store: Store, saved: { { string } })
	local owner = store.Owner
	for index, keys in saved do
		local shelf = store.Shelves[index]
		for _, key in keys do
			if not (shelf and Items.isValid(key) and Shelves.placeItem(shelf, key, false)) then
				PlayerData.addItem(owner, key, 1)
			end
		end
	end
end

-- Capacity upgrade: re-lay the existing products into the new slot grid.
function Shelves.setCapacity(store: Store, capacity: number)
	for _, shelf in store.Shelves do
		local keys = {}
		for slot = 1, shelf.Capacity do
			local key = shelf.Slots[slot]
			if key then
				table.insert(keys, key)
			end
		end
		for _, model in shelf.SlotModels do
			model:Destroy()
		end
		shelf.Slots = {}
		shelf.SlotModels = {}
		shelf.Capacity = capacity
		computeSlots(shelf)
		for _, key in keys do
			if not Shelves.placeItem(shelf, key, false) then
				PlayerData.addItem(store.Owner, key, 1)
			end
		end
		Shelves.refresh(shelf)
	end
end

-- Customers: reserve one product on a random stocked shelf.
function Shelves.reserve(store: Store): Shelf?
	local total = 0
	local weights = {}
	for index, shelf in store.Shelves do
		local available = math.max(0, Shelves.count(shelf) - shelf.Reserved)
		weights[index] = available
		total += available
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for index, shelf in store.Shelves do
		roll -= weights[index]
		if roll <= 0 and weights[index] > 0 then
			shelf.Reserved += 1
			return shelf
		end
	end
	return nil
end

function Shelves.release(shelf: Shelf)
	shelf.Reserved = math.max(0, shelf.Reserved - 1)
end

-- Removes a random product from the shelf and returns its key and model.
function Shelves.take(shelf: Shelf): (string?, Model?)
	Shelves.release(shelf)
	local occupied = {}
	for index = 1, shelf.Capacity do
		if shelf.Slots[index] then
			table.insert(occupied, index)
		end
	end
	if #occupied == 0 then
		return nil, nil
	end
	local slot = occupied[rng:NextInteger(1, #occupied)]
	local key = shelf.Slots[slot]
	local model = shelf.SlotModels[slot]
	shelf.Slots[slot] = nil
	shelf.SlotModels[slot] = nil
	Shelves.refresh(shelf)
	return key, model
end

-- Workers: the emptiest shelf nobody else is restocking.
function Shelves.pickForRestock(store: Store): Shelf?
	local best: Shelf? = nil
	local bestRatio = math.huge
	for _, shelf in store.Shelves do
		if not shelf.Busy and not shelf.WorkerAssigned and Shelves.free(shelf) > 0 then
			local ratio = Shelves.count(shelf) / shelf.Capacity
			if ratio < bestRatio then
				bestRatio = ratio
				best = shelf
			end
		end
	end
	return best
end

return Shelves
