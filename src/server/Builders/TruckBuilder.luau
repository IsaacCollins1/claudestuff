--!strict
-- The delivery van. Built facing -Z (Roblox forward). Only the chassis is
-- anchored; everything else is welded to it, so tweening the chassis CFrame
-- moves the whole van. A mesh van in ReplicatedStorage.CustomModels.Props
-- ("DeliveryVan") replaces the Part version.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)
local LowPoly = require(ReplicatedStorage.Shared.LowPoly)
local ModelLibrary = require(ReplicatedStorage.Shared.ModelLibrary)

local TruckBuilder = {}

-- Height of the chassis centre above the road surface.
TruckBuilder.RideHeight = 2.1

local WHITE = Color3.fromRGB(250, 250, 252)
local DARK = Color3.fromRGB(35, 38, 48)

export type Truck = {
	Model: Model,
	Root: BasePart,
}

local GLASS = Color3.fromRGB(150, 210, 255)
local CHROME = Color3.fromRGB(205, 208, 215)

local function buildParts(model: Model, root: BasePart, accent: Color3)
	local origin = root.CFrame
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end

	-- Cargo box at the back, cab at the front (-Z).
	local cargo = Build.part(model, "Cargo", Vector3.new(6, 6.4, 9.5), at(0, 3.7, 2.4), WHITE)
	Build.part(model, "CargoStripe", Vector3.new(6.1, 1.1, 9.6), at(0, 2.2, 2.4), accent)
	Build.part(model, "CargoRoof", Vector3.new(6.15, 0.35, 9.65), at(0, 7.05, 2.4), accent)
	for _, side in { -1, 1 } do
		Build.part(model, "RearDoor", Vector3.new(2.9, 5.6, 0.1), at(side * 1.48, 3.9, 7.2), Color3.fromRGB(238, 238, 242))
		Build.part(model, "DoorHandle", Vector3.new(0.15, 0.9, 0.12), at(side * 0.35, 3.6, 7.28), CHROME)
	end

	Build.part(model, "CabLower", Vector3.new(5.8, 2.8, 4.8), at(0, 2, -4.95), accent)
	Build.part(model, "CabUpper", Vector3.new(5.8, 2.4, 2.6), at(0, 4.6, -3.85), accent)
	Build.part(model, "CabRoof", Vector3.new(5.9, 0.3, 4.4), at(0, 5.95, -4.75), WHITE)
	local windscreen = Build.wedge(model, "Windscreen", Vector3.new(5.6, 2.4, 1.8), at(0, 4.6, -6.05), GLASS, Enum.Material.Glass)
	windscreen.Transparency = 0.15
	local sideWindows = Build.part(model, "SideWindows", Vector3.new(5.9, 1.5, 1.9), at(0, 4.7, -3.9), GLASS, Enum.Material.Glass)
	sideWindows.Transparency = 0.15
	Build.part(model, "Grille", Vector3.new(3, 1, 0.1), at(0, 1.9, -7.4), DARK)
	for _, y in { 1.65, 2.15 } do
		Build.part(model, "GrilleBar", Vector3.new(2.8, 0.12, 0.12), at(0, y, -7.45), CHROME)
	end
	Build.part(model, "Bumper", Vector3.new(6.1, 0.7, 0.6), at(0, 0.7, -7.6), Color3.fromRGB(190, 190, 198))
	Build.part(model, "Plate", Vector3.new(1.6, 0.5, 0.05), at(0, 0.7, -7.93), Color3.fromRGB(255, 220, 60))
	Build.part(model, "RearBumper", Vector3.new(6.1, 0.6, 0.5), at(0, 0.6, 7.35), Color3.fromRGB(190, 190, 198))
	LowPoly.each(LowPoly.hexPrism(model, "Beacon", 0.45, 0.8, at(0, 6.3, -4.4), Color3.fromRGB(255, 170, 40), Enum.Material.Neon), function(part)
		part.CastShadow = false
	end)

	for _, side in { -1, 1 } do
		local light = Build.part(model, "Headlight", Vector3.new(1, 0.6, 0.2), at(side * 2.1, 2.5, -7.4), Color3.fromRGB(255, 245, 200), Enum.Material.Neon)
		light.CastShadow = false
		local tail = Build.part(model, "Taillight", Vector3.new(0.6, 1.2, 0.2), at(side * 2.7, 1.8, 7.2), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
		tail.CastShadow = false
		Build.part(model, "MirrorArm", Vector3.new(0.5, 0.12, 0.12), at(side * 3.1, 4.3, -5.4), DARK)
		Build.part(model, "Mirror", Vector3.new(0.25, 0.9, 0.55), at(side * 3.4, 4.3, -5.4), DARK)
		Build.part(model, "Step", Vector3.new(0.5, 0.25, 1.8), at(side * 3.05, 0.45, -4.4), DARK)
		Build.part(model, "DoorLine", Vector3.new(0.05, 3.8, 0.1), at(side * 2.92, 3.1, -2.8), accent:Lerp(Color3.new(0, 0, 0), 0.35))
	end

	-- Wheels: cylinders lying along X.
	for _, z in { -4.8, 4.5 } do
		for _, side in { -1, 1 } do
			LowPoly.sideHexPrism(model, "Wheel", 1, 2.7, at(side * 2.8, -0.8, z), Color3.fromRGB(30, 30, 34))
			LowPoly.sideHexPrism(model, "Hub", 1.05, 1.35, at(side * 2.8, -0.8, z), CHROME)
			LowPoly.sideHexPrism(model, "HubCap", 1.1, 0.55, at(side * 2.8, -0.8, z), accent)
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
end

function TruckBuilder.build(accent: Color3): Truck
	local model = Instance.new("Model")
	model.Name = "DeliveryVan"

	local root = Build.part(model, "Chassis", Vector3.new(5.6, 1, 15), CFrame.new(), DARK)
	local template = ModelLibrary.template("Props", "DeliveryVan")
	local custom: Model? = nil
	if template then
		-- A custom van mesh sits on the road below the (now invisible) chassis.
		local ok, result = pcall(ModelLibrary.fitted, template, Vector3.new(6.4, 8.6, 16), CFrame.new(0, -TruckBuilder.RideHeight, 0))
		if ok then
			custom = result
			result.Parent = model
			root.Transparency = 1
		else
			warn("[FillTheStore] Couldn't use CustomModels.Props.DeliveryVan: " .. tostring(result))
		end
	end
	if not custom then
		buildParts(model, root, accent)
		LowPoly.sideHexPrism(model, "ExhaustPipe", 0.5, 0.35, CFrame.new(2, -0.55, 7.45) * CFrame.Angles(0, math.pi / 2, 0), DARK)
	end

	-- Little puffs from the exhaust while the van is around (a built-in client texture).
	local exhaust = Instance.new("Attachment")
	exhaust.Name = "Exhaust"
	exhaust.Position = Vector3.new(2, -0.55, 7.7)
	exhaust.Parent = root
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "ExhaustSmoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(205, 205, 212))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1.8) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(0.6, 1)
	smoke.Rate = 8
	smoke.Speed = NumberRange.new(1.5, 3)
	smoke.SpreadAngle = Vector2.new(15, 15)
	smoke.EmissionDirection = Enum.NormalId.Back
	smoke.Acceleration = Vector3.new(0, 2, 0)
	smoke.Drag = 2
	smoke.Parent = exhaust

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
	Build.weldAll(model, root)
	root.Anchored = true
	model.PrimaryPart = root
	return { Model = model, Root = root }
end

return TruckBuilder
