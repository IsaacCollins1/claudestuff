--!strict
-- Teaches the loop without text walls: a short hint at the bottom of the
-- screen, a bouncing arrow over the next thing to do, and (for new players)
-- a glowing line from the character to it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))

local HUD = require(script.Parent.HUD)
local State = require(script.Parent.State)
local StoreQuery = require(script.Parent.StoreQuery)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local Guide = {}

local holder: Part
local marker: BillboardGui
local targetAttachment: Attachment
local beam: Beam
local characterAttachment: Attachment? = nil
local lastUpgradePulse = 0

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

type Objective = { Hint: string?, Target: BasePart? }

local function nearest(parts: { BasePart }, from: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, part in parts do
		local distance = (part.Position - from).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			best = part
		end
	end
	return best
end

local function cheapestUpgrade(): number?
	local data = State.Data
	if not data then
		return nil
	end
	local cheapest: number? = nil
	for id, def in Upgrades.Defs do
		local cost = Upgrades.getCost(id, data.Upgrades[id] or def.StartLevel)
		if cost and (cheapest == nil or cost < cheapest) then
			cheapest = cost
		end
	end
	return cheapest
end

local function currentObjective(root: BasePart): Objective
	local store = StoreQuery.store()
	if not store then
		return { Hint = nil, Target = nil }
	end
	local press = if isTouch() then "Tap" else "Press E to"

	if player:GetAttribute("CarryingBox") == true then
		if StoreQuery.isInside(root.Position) then
			return { Hint = `📦 {press} open the box!`, Target = nil }
		end
		return { Hint = "🏪 Carry the box into your shop!", Target = StoreQuery.part(store, "DoorMat") }
	end

	local stock = State.inventoryTotal()
	local shelves = StoreQuery.shelves()
	if stock > 0 then
		local emptiest = nil
		local lowest = math.huge
		for _, shelf in shelves do
			if shelf.Capacity > 0 and shelf.Count < shelf.Capacity then
				local ratio = shelf.Count / shelf.Capacity
				if ratio < lowest then
					lowest = ratio
					emptiest = shelf
				end
			end
		end
		if emptiest then
			return { Hint = `🛒 {press} stock your shelves!`, Target = emptiest.Target }
		end
	end

	local boxes = StoreQuery.boxesOnPad()
	if #boxes > 0 then
		return { Hint = "📦 Grab a delivery box!", Target = nearest(boxes, root.Position) }
	end

	local data = State.Data
	local cheapest = cheapestUpgrade()
	if data and cheapest and data.Cash >= cheapest then
		if os.clock() - lastUpgradePulse > 3 then
			lastUpgradePulse = os.clock()
			HUD.pulseUpgrades()
		end
		return { Hint = "⬆️ Spend your cash on UPGRADES!", Target = nil }
	end

	local onShelves = 0
	for _, shelf in shelves do
		onShelves += shelf.Count
	end
	if stock == 0 and onShelves == 0 then
		return { Hint = "🚚 A delivery is coming — watch the loading bay!", Target = StoreQuery.part(StoreQuery.plot(), "LoadingBay") }
	end
	return { Hint = nil, Target = nil }
end

local function attachToCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root and root:IsA("BasePart") then
		local attachment = Instance.new("Attachment")
		attachment.Name = "GuideAttachment"
		attachment.Parent = root
		characterAttachment = attachment
		beam.Attachment0 = attachment
	end
end

local function update()
	local root = StoreQuery.rootPart()
	if not root then
		HUD.setHint(nil)
		marker.Enabled = false
		beam.Enabled = false
		return
	end
	local objective = currentObjective(root)
	HUD.setHint(objective.Hint)

	local target = objective.Target
	if target then
		local top = target.Position + Vector3.new(0, target.Size.Y / 2 + 1, 0)
		holder.CFrame = CFrame.new(top)
		local distance = (top - root.Position).Magnitude
		marker.Enabled = distance > 6
		local data = State.Data
		local learning = data == nil or data.ItemsSold < Config.GuideItemsSoldThreshold
		beam.Enabled = learning and distance > 10 and characterAttachment ~= nil
	else
		marker.Enabled = false
		beam.Enabled = false
	end
end

function Guide.init()
	holder = Instance.new("Part")
	holder.Name = "GuideTarget"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Parent = workspace

	targetAttachment = Instance.new("Attachment")
	targetAttachment.Parent = holder

	marker = Instance.new("BillboardGui")
	marker.Name = "GuideArrow"
	marker.Size = UDim2.fromScale(3, 3)
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.Enabled = false
	marker.Parent = holder
	local arrow = UIKit.label(marker, "⬇️")
	UIKit.textStroke(arrow, UIKit.Colors.Dark, 2)

	beam = Instance.new("Beam")
	beam.Attachment1 = targetAttachment
	beam.Color = ColorSequence.new(UIKit.Colors.Yellow, Color3.fromRGB(255, 255, 255))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	beam.Width0 = 0.25
	beam.Width1 = 0.45
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Segments = 12
	beam.Enabled = false
	beam.Parent = holder

	if player.Character then
		task.spawn(attachToCharacter, player.Character)
	end
	player.CharacterAdded:Connect(attachToCharacter)

	-- Bounce the arrow.
	RunService.RenderStepped:Connect(function()
		marker.StudsOffsetWorldSpace = Vector3.new(0, 1.5 + math.abs(math.sin(os.clock() * 4)) * 1.2, 0)
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				update()
			end)
			if not ok then
				warn("[FillTheStore] Guide error: " .. tostring(err))
			end
			task.wait(0.2)
		end
	end)
end

return Guide
