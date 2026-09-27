--!strict
-- Read-only helpers for finding things in the local player's own store.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local StoreQuery = {}

function StoreQuery.plot(): Model?
	local index = player:GetAttribute("PlotIndex")
	local world = workspace:FindFirstChild("World")
	local plots = world and world:FindFirstChild("Plots")
	local plot = plots and index and plots:FindFirstChild("Plot" .. tostring(index))
	if plot and plot:IsA("Model") then
		return plot
	end
	return nil
end

function StoreQuery.store(): Model?
	local plot = StoreQuery.plot()
	local store = plot and plot:FindFirstChild("Store")
	if store and store:IsA("Model") then
		return store
	end
	return nil
end

function StoreQuery.part(parent: Instance?, name: string): BasePart?
	local part = parent and parent:FindFirstChild(name)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

-- Slightly stricter than the server check so a visible prompt always works.
function StoreQuery.isInside(position: Vector3): boolean
	local interior = StoreQuery.part(StoreQuery.store(), "Interior")
	if not interior then
		return false
	end
	local relative = interior.CFrame:PointToObjectSpace(position)
	local size = interior.Size
	return math.abs(relative.X) <= size.X / 2 + 1.5
		and math.abs(relative.Z) <= size.Z / 2 + 1.5
		and math.abs(relative.Y) <= size.Y
end

function StoreQuery.rootPart(): BasePart?
	local character = player.Character
	return StoreQuery.part(character, "HumanoidRootPart")
end

-- Own shelves with their fill state.
function StoreQuery.shelves(): { { Model: Model, Count: number, Capacity: number, Target: BasePart? } }
	local result = {}
	for _, shelf in CollectionService:GetTagged("Shelf") do
		if shelf:IsA("Model") and shelf:GetAttribute("OwnerUserId") == player.UserId then
			local count = shelf:GetAttribute("Count")
			local capacity = shelf:GetAttribute("Capacity")
			table.insert(result, {
				Model = shelf,
				Count = if type(count) == "number" then count else 0,
				Capacity = if type(capacity) == "number" then capacity else 0,
				Target = StoreQuery.part(shelf, "Base"),
			})
		end
	end
	return result
end

-- Own boxes that have landed on the loading bay and can be picked up.
function StoreQuery.boxesOnPad(): { BasePart }
	local result = {}
	for _, box in CollectionService:GetTagged("DeliveryBox") do
		local root = StoreQuery.part(box, "Box")
		if box:GetAttribute("OwnerUserId") == player.UserId and root and root:FindFirstChild("BoxPrompt") then
			table.insert(result, root)
		end
	end
	return result
end

return StoreQuery
