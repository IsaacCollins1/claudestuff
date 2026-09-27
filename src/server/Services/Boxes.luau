--!strict
-- Delivery boxes: landing on the loading bay, being picked up and carried,
-- and being opened inside the store (which adds the products to inventory).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local BoxVisual = require(Shared.BoxVisual)
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Products = require(Shared.Products)
local StoreLevels = require(Shared.StoreLevels)
local Upgrades = require(Shared.Upgrades)
local Variants = require(Shared.Variants)

local Events = require(script.Parent.Events)
local Net = require(script.Parent.Net)
local Perks = require(script.Parent.Perks)
local PlayerData = require(script.Parent.PlayerData)
local Registry = require(script.Parent.Registry)

type Session = Registry.Session
type BoxInfo = Registry.BoxInfo

local Boxes = {}

Boxes.Tag = "DeliveryBox"
Boxes.PromptTag = "OwnedPrompt"

local rng = Random.new()
local SPOTS = StoreLevels.boxSpots()

-- Carry pose: remember original shoulder C0s so we can restore them.
local originalC0: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local function setCarryPose(character: Model?, enabled: boolean)
	if not character then
		return
	end
	for _, name in { "RightShoulder", "LeftShoulder", "Right Shoulder", "Left Shoulder" } do
		local motor = character:FindFirstChild(name, true)
		if motor and motor:IsA("Motor6D") then
			if enabled then
				local original = originalC0[motor] or motor.C0
				originalC0[motor] = original
				-- Swing the arms forward (rotate about the torso's X axis at the shoulder).
				motor.C0 = CFrame.new(original.Position) * CFrame.Angles(math.rad(80), 0, 0) * original.Rotation
			else
				local original = originalC0[motor]
				if original then
					motor.C0 = original
					originalC0[motor] = nil
				end
			end
		end
	end
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function boxesFolder(session: Session): Instance
	local folder = session.PlotModel:FindFirstChild("Boxes")
	if folder then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "Boxes"
	newFolder.Parent = session.PlotModel
	return newFolder
end

local function makePrompt(info: BoxInfo, kind: string, actionText: string, hold: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = kind .. "Prompt"
	prompt.ActionText = actionText
	prompt.ObjectText = "📦 Delivery Box"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OwnerUserId", info.Session.Player.UserId)
	prompt:SetAttribute("Kind", kind)
	CollectionService:AddTag(prompt, Boxes.PromptTag)
	prompt.Parent = info.Root
	return prompt
end

local function spotCFrame(session: Session, spot: number): CFrame
	local position = SPOTS[spot]
	return session.PlotCFrame
		* CFrame.new(position + Vector3.new(0, BoxVisual.Size.Y / 2 + 0.12, 0))
		* CFrame.Angles(0, rng:NextNumber(-0.35, 0.35), 0)
end

function Boxes.freeSpots(session: Session): { number }
	local used = {}
	for _, info in session.Boxes do
		if info.Spot then
			used[info.Spot] = true
		end
	end
	local free = {}
	for spot = 1, math.min(Config.MaxBoxesOnPad, #SPOTS) do
		if not used[spot] then
			table.insert(free, spot)
		end
	end
	return free
end

-- Throw a part along an arc (server-side, replicated).
local function flyArc(part: BasePart, from: CFrame, to: CFrame, height: number, duration: number)
	local start = os.clock()
	while part.Parent do
		local t = math.min((os.clock() - start) / duration, 1)
		local position = from.Position:Lerp(to.Position, t) + Vector3.new(0, height * 4 * t * (1 - t), 0)
		local rotation = from.Rotation:Lerp(to.Rotation, t) * CFrame.Angles(0, t * math.pi * 2, 0)
		part.CFrame = CFrame.new(position) * rotation
		if t >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
end

local function placeOnSpot(info: BoxInfo, spot: number)
	local session = info.Session
	info.Spot = spot
	info.Carried = false
	info.Root.Anchored = true
	info.Root.CFrame = spotCFrame(session, spot)
	for _, part in info.Model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = part == info.Root
			part.CanQuery = true
		end
	end
	if info.Prompt then
		info.Prompt:Destroy()
	end
	info.Prompt = makePrompt(info, "Box", "Pick Up Box", 0)
	local prompt = info.Prompt :: ProximityPrompt
	prompt.Triggered:Connect(function(player: Player)
		Boxes.pickup(player, info)
	end)
end

-- The most valuable product deliveries can currently contain.
local function bestProduct(level: number): Products.Product
	local best = Products.List[1]
	for _, product in Products.poolForLevel(level) do
		if product.SellPrice > best.SellPrice then
			best = product
		end
	end
	return best
end

-- What's inside a new box: product and number of units.
local function rollBox(player: Player, special: string?): (Products.Product?, number)
	local data = PlayerData.get(player)
	if not data then
		return nil, 0
	end
	-- Deliveries only contain products the player's level has unlocked.
	local product = if special == "Golden" then bestProduct(data.Level) else Products.rollForBox(rng, data.Level)
	local multiplier = Upgrades.quantityMultiplier(data.Upgrades.DeliverySize) * Perks.deliveryQuantityMultiplier(player)
	local quantity = math.max(1, math.floor(rng:NextInteger(product.BoxMin, product.BoxMax) * multiplier + 0.5))
	return product, quantity
end

-- Creates a box that flies from `from` (the van) onto a loading bay spot.
-- `special` = "Golden" makes a Golden Crate (Robux shop).
function Boxes.spawn(session: Session, spot: number, from: CFrame, special: string?)
	local player = session.Player
	local product, quantity = rollBox(player, special)
	if not product then
		return
	end

	local tape = if special == "Golden" then Variants.GoldColor else Products.Rarities[product.Rarity].Color
	local box = BoxVisual.build(tape, false, special == "Golden")
	session.NextBoxId += 1
	box.Model.Name = "DeliveryBox" .. session.NextBoxId
	box.Model:SetAttribute("OwnerUserId", player.UserId)
	CollectionService:AddTag(box.Model, Boxes.Tag)

	local info: BoxInfo = {
		Id = session.NextBoxId,
		Session = session,
		Model = box.Model,
		Root = box.Root,
		ProductId = product.Id,
		Quantity = quantity,
		Spot = spot, -- reserved while flying
		Carried = false,
		Opened = false,
		Prompt = nil,
		Special = special,
	}
	session.Boxes[box.Model] = info

	box.Root.CFrame = from
	box.Model.Parent = boxesFolder(session)
	task.spawn(function()
		local target = spotCFrame(session, spot)
		flyArc(box.Root, from, target, 8, 0.8)
		if not session.Alive or info.Carried or info.Opened or box.Model.Parent == nil then
			return
		end
		Net.effectAll("BoxLand", { Position = target.Position, OwnerId = player.UserId })
		placeOnSpot(info, spot)
	end)
end

function Boxes.pickup(player: Player, info: BoxInfo)
	local session = info.Session
	if player ~= session.Player or info.Carried or info.Opened or not session.Alive or not info.Prompt then
		return
	end
	if session.Carried then
		Net.notify(player, "Info", "📦 You're already carrying a box!")
		return
	end
	local root = getRoot(player)
	if not root or (root.Position - info.Root.Position).Magnitude > 16 then
		return
	end

	info.Spot = nil
	info.Carried = true
	session.Carried = info
	if info.Prompt then
		info.Prompt:Destroy()
		info.Prompt = nil
	end
	for _, part in info.Model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.Massless = true
		end
	end
	info.Root.CFrame = root.CFrame * CFrame.new(0, 0.5, -2.3)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = root
	weld.Part1 = info.Root
	weld.Parent = info.Root
	info.Root.Anchored = false
	setCarryPose(player.Character, true)
	player:SetAttribute("CarryingBox", true)

	info.Prompt = makePrompt(info, "OpenBox", "Open Box", 0.2)
	local prompt = info.Prompt :: ProximityPrompt
	prompt.Triggered:Connect(function(triggeringPlayer: Player)
		Boxes.open(triggeringPlayer, info)
	end)
	Net.effectTo(player, "Pickup", {})
	Events.BoxPickedUp:Fire(player)
end

local function detach(info: BoxInfo)
	local session = info.Session
	if session.Carried == info then
		session.Carried = nil
	end
	info.Carried = false
	local player = session.Player
	player:SetAttribute("CarryingBox", false)
	setCarryPose(player.Character, false)
	local weld = info.Root:FindFirstChild("CarryWeld")
	if weld then
		weld:Destroy()
	end
end

-- Roll the variants for every unit and add them to the inventory.
local function rollContents(player: Player, info: BoxInfo): { { Key: string, Count: number } }
	local data = PlayerData.get(player)
	local luck = if data then Upgrades.luckMultiplier(data.Upgrades.ProductLuck) else 1
	luck *= Perks.luckMultiplier(player)
	local counts: { [string]: number } = {}
	for unit = 1, info.Quantity do
		local variant = Variants.roll(rng, luck)
		if info.Special == "Golden" then
			-- Golden Crate: everything is at least Golden, and one is Rainbow.
			variant = if unit == 1 then "Rainbow" else Variants.roll(rng, luck * 20)
			if variant == "Normal" then
				variant = "Golden"
			end
		end
		local key = Items.key(info.ProductId, variant)
		counts[key] = (counts[key] or 0) + 1
	end
	local contents = {}
	for key, count in counts do
		PlayerData.addItem(player, key, count)
		table.insert(contents, { Key = key, Count = count })
	end
	table.sort(contents, function(a, b)
		return Items.compare(a.Key, b.Key)
	end)
	return contents
end

-- Opens a carried box: adds its products to the stock room and plays the
-- opening animation at `openCFrame`. `flyTo` is where the products fly
-- (a shelf when unpacking), otherwise they fly to the player.
local function openAt(player: Player, info: BoxInfo, openCFrame: CFrame, flyTo: Vector3?): { { Key: string, Count: number } }
	local session = info.Session
	info.Opened = true
	detach(info)
	session.Boxes[info.Model] = nil
	info.Model:Destroy()

	local contents = rollContents(player, info)
	local data = PlayerData.get(player)
	if data then
		data.Stats.BoxesOpened += 1
	end
	Events.BoxOpened:Fire(player, info.Quantity)

	Net.effectAll("BoxOpen", {
		CFrame = openCFrame,
		Contents = contents,
		OwnerId = player.UserId,
		TapeColor = if info.Special == "Golden"
			then Variants.GoldColor
			else Products.Rarities[Items.product(contents[1].Key).Rarity].Color,
		FlyTo = flyTo,
		Special = info.Special,
	})

	for _, entry in contents do
		if Items.isRare(entry.Key) then
			if data then
				data.Stats.RaresFound += entry.Count
			end
			Net.notify(player, "Rare", "✨ " .. string.upper(Items.displayName(entry.Key)) .. "!")
		end
	end
	return contents
end

-- "Open Box" prompt: opens on the floor in front of the player (inside the shop only).
function Boxes.open(player: Player, info: BoxInfo)
	local session = info.Session
	if player ~= session.Player or not info.Carried or info.Opened then
		return
	end
	local store = session.Store
	local root = getRoot(player)
	if not store or not root then
		return
	end
	local localPosition = session.PlotCFrame:PointToObjectSpace(root.Position)
	if not StoreLevels.isInside(store.Layout, localPosition, 2) then
		Net.notify(player, "Info", "🏪 Carry the box inside your shop first!")
		return
	end
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = if flatLook.Magnitude > 0.01 then flatLook.Unit else Vector3.new(0, 0, -1)
	local floorY = session.PlotCFrame:PointToWorldSpace(Vector3.new(0, StoreLevels.FloorY, 0)).Y
	local position = root.Position + flatLook * 3.4
	position = Vector3.new(position.X, floorY + BoxVisual.Size.Y / 2, position.Z)
	openAt(player, info, CFrame.lookAt(position, Vector3.new(root.Position.X, position.Y, root.Position.Z)), nil)
end

-- Unpack the carried box at a shelf. Returns the contents and the box's
-- product id, or nil if the player isn't carrying anything.
function Boxes.unpackCarried(player: Player, openCFrame: CFrame, flyTo: Vector3): ({ { Key: string, Count: number } }?, string?)
	local session = Registry.session(player)
	local info = session and session.Carried
	if not info or info.Opened or not getRoot(player) then
		return nil, nil
	end
	return openAt(player, info, openCFrame, flyTo), info.ProductId
end

-- Called when the player dies/respawns/leaves while carrying: put the box
-- back on the loading bay (or straight into stock if the bay is full).
function Boxes.dropCarried(player: Player)
	local session = Registry.session(player)
	local info = session and session.Carried
	if not session or not info then
		return
	end
	detach(info)
	if not session.Alive or player.Parent ~= Players then
		info.Model:Destroy()
		session.Boxes[info.Model] = nil
		return
	end
	local free = Boxes.freeSpots(session)
	if #free > 0 then
		info.Model.Parent = boxesFolder(session)
		placeOnSpot(info, free[1])
	else
		info.Opened = true
		session.Boxes[info.Model] = nil
		info.Model:Destroy()
		rollContents(player, info)
	end
end

-- A box's contents straight into the stock room (used when the bay is full
-- but a purchased delivery must still arrive).
function Boxes.grantBox(session: Session, special: string?): { { Key: string, Count: number } }
	local player = session.Player
	local product, quantity = rollBox(player, special)
	if not product then
		return {}
	end
	local info = { ProductId = product.Id, Quantity = quantity, Special = special } :: any
	local contents = rollContents(player, info)
	for _, entry in contents do
		if Items.isRare(entry.Key) then
			Net.notify(player, "Rare", "✨ " .. string.upper(Items.displayName(entry.Key)) .. "!")
		end
	end
	return contents
end

-- Golden Crate: drops from the sky onto the loading bay (or straight into
-- the stock room if the bay is full).
function Boxes.dropCrate(session: Session)
	local free = Boxes.freeSpots(session)
	if #free == 0 then
		Boxes.grantBox(session, "Golden")
		Net.notify(session.Player, "Info", "🎁 Bay full — your Golden Crate went to your stock room!")
		return
	end
	local spot = free[1]
	Boxes.spawn(session, spot, spotCFrame(session, spot) + Vector3.new(0, 70, 0), "Golden")
end

function Boxes.clear(session: Session)
	if session.Carried then
		detach(session.Carried)
	end
	for model in session.Boxes do
		model:Destroy()
	end
	table.clear(session.Boxes)
	session.Carried = nil
	local folder = session.PlotModel:FindFirstChild("Boxes")
	if folder then
		folder:Destroy()
	end
end

return Boxes
