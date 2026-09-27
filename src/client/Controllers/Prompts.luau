--!strict
-- ProximityPrompts on stores are only shown to their owner, and only when
-- they can actually be used (e.g. "Stock Shelf" needs stock and free space,
-- "Open Box" needs you to be inside your shop). The server re-checks everything.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local State = require(script.Parent.State)
local StoreQuery = require(script.Parent.StoreQuery)

local player = Players.LocalPlayer

local Prompts = {}

local TAG = "OwnedPrompt"
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

local function shouldEnable(prompt: ProximityPrompt, carrying: boolean, stock: number, inside: boolean): boolean
	local kind = prompt:GetAttribute("Kind")
	if kind == "Shelf" then
		local shelf = prompt:FindFirstAncestorOfClass("Model")
		local count = shelf and shelf:GetAttribute("Count")
		local capacity = shelf and shelf:GetAttribute("Capacity")
		local hasSpace = type(count) == "number" and type(capacity) == "number" and count < capacity
		return not carrying and stock > 0 and hasSpace
	elseif kind == "Box" then
		return not carrying
	elseif kind == "OpenBox" then
		return inside
	end
	return true
end

function Prompts.update()
	local carrying = player:GetAttribute("CarryingBox") == true
	local stock = State.inventoryTotal()
	local root = StoreQuery.rootPart()
	local inside = root ~= nil and StoreQuery.isInside(root.Position)
	for prompt in owned do
		if not prompt:IsDescendantOf(workspace) then
			owned[prompt] = nil
		else
			local enabled = shouldEnable(prompt, carrying, stock, inside)
			if prompt.Enabled ~= enabled then
				prompt.Enabled = enabled
			end
		end
	end
end

function Prompts.init()
	for _, prompt in CollectionService:GetTagged(TAG) do
		register(prompt)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(register)
	task.spawn(function()
		while true do
			Prompts.update()
			task.wait(0.12)
		end
	end)
end

return Prompts
