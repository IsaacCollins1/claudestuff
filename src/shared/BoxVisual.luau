--!strict
-- Cardboard delivery box. The server uses it for boxes on the loading bay and
-- being carried; the client builds one with flaps for the opening animation.
-- The tape colour hints at the rarity of what's inside.

local Build = require(script.Parent.Build)

local BoxVisual = {}

BoxVisual.Size = Vector3.new(2.6, 2.1, 2.6)
BoxVisual.Cardboard = Color3.fromRGB(205, 150, 95)

export type Box = {
	Model: Model,
	Root: BasePart,
	FlapLeft: BasePart?,
	FlapRight: BasePart?,
}

function BoxVisual.build(tapeColor: Color3, withFlaps: boolean?, golden: boolean?): Box
	local size = BoxVisual.Size
	local model = Instance.new("Model")
	model.Name = "DeliveryBox"
	local origin = CFrame.new()

	local bodyColor = if golden then Color3.fromRGB(255, 205, 60) else BoxVisual.Cardboard
	local root = Build.part(model, "Box", size, origin, bodyColor)
	if golden then
		root.Reflectance = 0.2
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "Sparkles"
		sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150))
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		sparkles.Lifetime = NumberRange.new(0.6, 1.1)
		sparkles.Rate = 8
		sparkles.Speed = NumberRange.new(1, 3)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Parent = root
	end
	local darker = bodyColor:Lerp(Color3.new(0, 0, 0), 0.12)

	-- Tape across the top and down the front/back, plus a "fragile" style label.
	Build.part(model, "TapeTop", Vector3.new(0.55, 0.06, size.Z + 0.02), origin * CFrame.new(0, size.Y / 2 + 0.02, 0), tapeColor)
	Build.part(model, "TapeFront", Vector3.new(0.55, 0.7, 0.06), origin * CFrame.new(0, size.Y / 2 - 0.35, -size.Z / 2 - 0.02), tapeColor)
	Build.part(model, "TapeBack", Vector3.new(0.55, 0.7, 0.06), origin * CFrame.new(0, size.Y / 2 - 0.35, size.Z / 2 + 0.02), tapeColor)
	Build.part(model, "Label", Vector3.new(0.9, 0.6, 0.05), origin * CFrame.new(0.7, -0.3, -size.Z / 2 - 0.02), Color3.fromRGB(250, 250, 245))
	Build.part(model, "Edge", Vector3.new(size.X + 0.04, 0.12, size.Z + 0.04), origin * CFrame.new(0, -size.Y / 2 + 0.06, 0), darker)

	local flapLeft: BasePart? = nil
	local flapRight: BasePart? = nil
	if withFlaps then
		-- Separate top flaps hinged on the left/right edges for the opening animation.
		local left = Build.part(model, "FlapLeft", Vector3.new(size.X / 2, 0.08, size.Z), origin * CFrame.new(-size.X / 4, size.Y / 2 + 0.04, 0), darker)
		local right = Build.part(model, "FlapRight", Vector3.new(size.X / 2, 0.08, size.Z), origin * CFrame.new(size.X / 4, size.Y / 2 + 0.04, 0), darker)
		flapLeft, flapRight = left, right
		local tape = model:FindFirstChild("TapeTop")
		if tape then
			tape:Destroy()
		end
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = descendant == root
			descendant.CanTouch = false
			descendant.CastShadow = true
		end
	end
	if not withFlaps then
		-- Welded so the server can carry/tween the whole box by its root.
		Build.weldAll(model, root)
	end
	-- (The client's flapped version stays fully anchored and is animated with PivotTo.)
	root.Anchored = true
	model.PrimaryPart = root
	return { Model = model, Root = root, FlapLeft = flapLeft, FlapRight = flapRight }
end

return BoxVisual
