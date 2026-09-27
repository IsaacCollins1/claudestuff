--!strict
-- ProximityPrompts on stores are only shown to their owner, and only when
-- they can actually be used:
--   * "Pick Up Box"   — when your hands are free
--   * shelf prompts   — "Unpack Here" on the nearest shelf while carrying a
--                       box, otherwise "Stock Shelf" when you have stock
--   * "Open Box"      — inside your shop when no shelf is in reach
-- The server re-checks everything. Owner-only GUIs (the floating
-- "YOUR SHOP" marker) are switched on here too.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local State = require(script.Parent.State)
local StoreQuery = require(script.Parent.StoreQuery)

local player = Players.LocalPlayer

local Prompts = {}

local TAG = "OwnedPrompt"
local OWNER_ONLY_GUI_TAG = "OwnerOnlyGui" -- StoreBuilder.OwnerOnlyTag
local owned: { [ProximityPrompt]: boolean } = {}

local function register(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		return
	end
	if instance:GetAttribute("OwnerUserId") ~= player.UserId then
		instance.Enabled = false
		return
	end
	owned[instance] = true
end

local function promptPosition(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("BasePart") then
		return parent.Position
	end
	return nil
end

local function shelfHasSpace(prompt: ProximityPrompt): boolean
	local shelf = prompt:FindFirstAncestorOfClass("Model")
	local count = shelf and shelf:GetAttribute("Count")
	local capacity = shelf and shelf:GetAttribute("Capacity")
	return type(count) == "number" and type(capacity) == "number" and count < capacity
end

-- The shelf prompt a carried box would be unpacked at (nearest in reach with space).
local function unpackTarget(root: BasePart): ProximityPrompt?
	local best: ProximityPrompt? = nil
	local bestDistance = math.huge
	for prompt in owned do
		if prompt:GetAttribute("Kind") == "Shelf" and shelfHasSpace(prompt) then
			local position = promptPosition(prompt)
			local distance = if position then (position - root.Position).Magnitude else math.huge
			if distance <= prompt.MaxActivationDistance and distance < bestDistance then
				bestDistance = distance
				best = prompt
			end
		end
	end
	return best
end

function Prompts.update()
	local carrying = player:GetAttribute("CarryingBox") == true
	local stock = State.inventoryTotal()
	local root = StoreQuery.rootPart()
	local inside = root ~= nil and StoreQuery.isInside(root.Position)
	local target = if carrying and root and inside then unpackTarget(root) else nil

	for prompt in owned do
		if not prompt:IsDescendantOf(workspace) then
			owned[prompt] = nil
			continue
		end
		local kind = prompt:GetAttribute("Kind")
		local enabled = true
		if kind == "Shelf" then
			if carrying then
				enabled = prompt == target
				prompt.ActionText = "Unpack Here"
			else
				enabled = stock > 0 and shelfHasSpace(prompt)
				prompt.ActionText = "Stock Shelf"
			end
		elseif kind == "Box" then
			enabled = not carrying
		elseif kind == "OpenBox" then
			enabled = inside and target == nil
		end
		if prompt.Enabled ~= enabled then
			prompt.Enabled = enabled
		end
	end
end

local function registerOwnerGui(instance: Instance)
	if instance:IsA("LayerCollector") then
		instance.Enabled = instance:GetAttribute("OwnerUserId") == player.UserId
	end
end

function Prompts.init()
	for _, prompt in CollectionService:GetTagged(TAG) do
		register(prompt)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(register)
	for _, gui in CollectionService:GetTagged(OWNER_ONLY_GUI_TAG) do
		registerOwnerGui(gui)
	end
	CollectionService:GetInstanceAddedSignal(OWNER_ONLY_GUI_TAG):Connect(registerOwnerGui)
	task.spawn(function()
		while true do
			Prompts.update()
			task.wait(0.1)
		end
	end)
end

return Prompts
