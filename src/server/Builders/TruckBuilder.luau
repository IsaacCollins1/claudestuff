--!strict
-- The delivery van. Built facing -Z (Roblox forward). Only the chassis is
-- anchored; everything else is welded to it, so tweening the chassis CFrame
-- moves the whole van.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)

local TruckBuilder = {}

-- Height of the chassis centre above the road surface.
TruckBuilder.RideHeight = 2.1

local WHITE = Color3.fromRGB(250, 250, 252)
local DARK = Color3.fromRGB(35, 38, 48)

export type Truck = {
	Model: Model,
	Root: BasePart,
}

function TruckBuilder.build(accent: Color3): Truck
	local model = Instance.new("Model")
	model.Name = "DeliveryVan"
	local origin = CFrame.new()

	local root = Build.part(model, "Chassis", Vector3.new(5.6, 1, 15), origin, DARK)
	-- Cargo box at the back, cab at the front (-Z).
	local cargo = Build.part(model, "Cargo", Vector3.new(6, 6.4, 9.5), origin * CFrame.new(0, 3.7, 2.4), WHITE)
	Build.part(model, "CargoStripe", Vector3.new(6.1, 1.1, 9.6), origin * CFrame.new(0, 2.2, 2.4), accent)
	Build.part(model, "Cab", Vector3.new(5.8, 4.6, 5), origin * CFrame.new(0, 2.8, -4.9), accent)
	Build.part(model, "CabRoof", Vector3.new(5.6, 0.4, 4.2), origin * CFrame.new(0, 5.3, -4.6), WHITE)
	local windscreen = Build.part(model, "Windscreen", Vector3.new(5.2, 2, 0.2), origin * CFrame.new(0, 3.9, -7.45), Color3.fromRGB(150, 210, 255), Enum.Material.Glass)
	windscreen.Transparency = 0.3
	for _, side in { -1, 1 } do
		local window = Build.part(model, "SideWindow", Vector3.new(0.2, 1.8, 2.4), origin * CFrame.new(side * 2.95, 3.9, -5.6), Color3.fromRGB(150, 210, 255), Enum.Material.Glass)
		window.Transparency = 0.3
		local light = Build.part(model, "Headlight", Vector3.new(1, 0.6, 0.2), origin * CFrame.new(side * 2, 1.6, -7.45), Color3.fromRGB(255, 245, 200), Enum.Material.Neon)
		Build.decor(light)
		local tail = Build.part(model, "Taillight", Vector3.new(0.8, 0.8, 0.2), origin * CFrame.new(side * 2.4, 1.6, 7.2), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
		Build.decor(tail)
	end
	Build.part(model, "Bumper", Vector3.new(6, 0.8, 0.6), origin * CFrame.new(0, 0.6, -7.6), Color3.fromRGB(200, 200, 205))

	-- Wheels: cylinders lying along X.
	for _, z in { -4.8, 4.5 } do
		for _, side in { -1, 1 } do
			local wheel = Build.sideCylinder(model, "Wheel", 1, 2.6, origin * CFrame.new(side * 2.8, -0.8, z), Color3.fromRGB(30, 30, 34))
			Build.decor(wheel)
			local hub = Build.sideCylinder(model, "Hub", 1.05, 1.2, origin * CFrame.new(side * 2.8, -0.8, z), Color3.fromRGB(200, 200, 205))
			Build.decor(hub)
		end
	end

	-- "FRESH DELIVERIES" on both sides of the cargo box.
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.Parent = cargo
		local label = Build.textLabel(gui, "🚚 FRESH DELIVERIES", accent)
		label.Size = UDim2.fromScale(0.9, 0.3)
		label.Position = UDim2.fromScale(0.05, 0.15)
		Build.stroke(label, DARK, 2)
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	Build.weldAll(model, root)
	root.Anchored = true
	model.PrimaryPart = root
	return { Model = model, Root = root }
end

return TruckBuilder
