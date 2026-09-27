--!strict
-- Builds the little 3D product models seen on shelves, in customers' baskets
-- and popping out of opened boxes. Everything is made from normal Parts.
--
-- Models are built around the origin with their base at Y = 0 and their
-- "front" facing -Z, so `model:PivotTo(slotCFrame)` places them on a shelf.

local CollectionService = game:GetService("CollectionService")

local Build = require(script.Parent.Build)
local Items = require(script.Parent.Items)
local Products = require(script.Parent.Products)
local Variants = require(script.Parent.Variants)

local ProductVisuals = {}

ProductVisuals.RainbowTag = "RainbowItem"

local SILVER = Color3.fromRGB(205, 208, 215)
local DARK = Color3.fromRGB(30, 30, 36)

type Adder = (name: string, size: Vector3, cframe: CFrame, color: Color3, kind: string?) -> Part

local shapes: { [string]: (add: Adder, product: Products.Product) -> () } = {}

shapes.Bottle = function(add, p)
	local body = add("Body", Vector3.new(0.95, 0.5, 0.5), CFrame.new(0, 0.475, 0), p.Color, "cylinder")
	body.Transparency = 0.15
	add("Label", Vector3.new(0.3, 0.52, 0.52), CFrame.new(0, 0.45, 0), p.Accent, "cylinder")
	add("Neck", Vector3.new(0.18, 0.26, 0.26), CFrame.new(0, 1.03, 0), p.Color, "cylinder")
	add("Cap", Vector3.new(0.1, 0.3, 0.3), CFrame.new(0, 1.16, 0), p.Accent, "cylinder")
end

shapes.Can = function(add, p)
	add("Body", Vector3.new(0.85, 0.5, 0.5), CFrame.new(0, 0.425, 0), p.Color, "cylinder")
	add("Band", Vector3.new(0.25, 0.52, 0.52), CFrame.new(0, 0.45, 0), p.Accent, "cylinder")
	add("Top", Vector3.new(0.05, 0.44, 0.44), CFrame.new(0, 0.87, 0), SILVER, "cylinder")
end

shapes.Bag = function(add, p)
	add("Body", Vector3.new(0.7, 0.9, 0.32), CFrame.new(0, 0.45, 0), p.Color)
	add("Band", Vector3.new(0.72, 0.28, 0.34), CFrame.new(0, 0.42, 0), p.Accent)
	add("Crimp", Vector3.new(0.74, 0.08, 0.2), CFrame.new(0, 0.93, 0), p.Accent)
end

shapes.Bar = function(add, p)
	add("Body", Vector3.new(0.8, 0.2, 0.42), CFrame.new(0, 0.1, 0), p.Color)
	add("Wrapper", Vector3.new(0.36, 0.22, 0.44), CFrame.new(0, 0.1, 0), p.Accent)
	add("Body2", Vector3.new(0.8, 0.2, 0.42), CFrame.new(0, 0.31, 0) * CFrame.Angles(0, math.rad(8), 0), p.Color)
	add("Wrapper2", Vector3.new(0.36, 0.22, 0.44), CFrame.new(0, 0.31, 0) * CFrame.Angles(0, math.rad(8), 0), p.Accent)
end

shapes.Cereal = function(add, p)
	add("Body", Vector3.new(0.72, 1.1, 0.3), CFrame.new(0, 0.55, 0), p.Color)
	add("Panel", Vector3.new(0.5, 0.5, 0.02), CFrame.new(0, 0.55, -0.16), p.Accent)
	add("Stripe", Vector3.new(0.73, 0.14, 0.31), CFrame.new(0, 0.96, 0), Color3.fromRGB(230, 60, 50))
end

shapes.Roll = function(add, p)
	for index, offset in { Vector2.new(-0.18, 0.2), Vector2.new(0.18, 0.2), Vector2.new(-0.18, 0.6), Vector2.new(0.18, 0.6) } do
		add("Roll" .. index, Vector3.new(0.4, 0.34, 0.34), CFrame.new(offset.X, offset.Y, 0), p.Color, "cylinder")
	end
	local wrap = add("Wrap", Vector3.new(0.74, 0.12, 0.37), CFrame.new(0, 0.42, 0), p.Accent)
	wrap.Transparency = 0.2
end

shapes.Pizza = function(add, p)
	add("Box1", Vector3.new(0.85, 0.16, 0.85), CFrame.new(0, 0.08, 0), p.Color)
	add("Box2", Vector3.new(0.85, 0.16, 0.85), CFrame.new(0, 0.25, 0) * CFrame.Angles(0, math.rad(6), 0), p.Color)
	add("Logo", Vector3.new(0.02, 0.55, 0.55), CFrame.new(0, 0.34, 0), p.Accent, "cylinder")
end

shapes.Spray = function(add, p)
	add("Body", Vector3.new(0.75, 0.42, 0.42), CFrame.new(0, 0.375, 0), p.Color, "cylinder")
	add("Label", Vector3.new(0.25, 0.44, 0.44), CFrame.new(0, 0.35, 0), p.Accent, "cylinder")
	add("Head", Vector3.new(0.22, 0.2, 0.34), CFrame.new(0, 0.85, -0.05), p.Accent)
	add("Nozzle", Vector3.new(0.08, 0.08, 0.12), CFrame.new(0, 0.87, -0.26), DARK)
end

shapes.Headphones = function(add, p)
	add("Box", Vector3.new(0.75, 0.85, 0.3), CFrame.new(0, 0.425, 0), p.Color)
	add("Window", Vector3.new(0.55, 0.5, 0.02), CFrame.new(0, 0.47, -0.16), p.Accent)
	add("CupL", Vector3.new(0.18, 0.22, 0.04), CFrame.new(-0.15, 0.4, -0.18), DARK)
	add("CupR", Vector3.new(0.18, 0.22, 0.04), CFrame.new(0.15, 0.4, -0.18), DARK)
	add("Band", Vector3.new(0.42, 0.05, 0.04), CFrame.new(0, 0.58, -0.18), DARK)
end

shapes.Phone = function(add, p)
	add("Stand", Vector3.new(0.34, 0.08, 0.3), CFrame.new(0, 0.04, 0), SILVER)
	add("Body", Vector3.new(0.42, 0.8, 0.1), CFrame.new(0, 0.48, 0.02), p.Color)
	local screen = add("Screen", Vector3.new(0.36, 0.68, 0.02), CFrame.new(0, 0.48, -0.04), p.Accent)
	screen.Material = Enum.Material.Neon
end

shapes.Console = function(add, p)
	add("Body", Vector3.new(0.9, 0.28, 0.6), CFrame.new(0, 0.14, 0), p.Color)
	local stripe = add("Stripe", Vector3.new(0.91, 0.04, 0.61), CFrame.new(0, 0.2, 0), p.Accent)
	stripe.Material = Enum.Material.Neon
	add("Pad", Vector3.new(0.36, 0.1, 0.22), CFrame.new(0.15, 0.33, -0.1), DARK)
end

shapes.Laptop = function(add, p)
	add("Base", Vector3.new(0.85, 0.06, 0.6), CFrame.new(0, 0.03, 0), p.Color)
	local hinge = CFrame.new(0, 0.06, 0.28) * CFrame.Angles(math.rad(15), 0, 0)
	add("Lid", Vector3.new(0.85, 0.55, 0.05), hinge * CFrame.new(0, 0.275, 0), p.Color)
	local screen = add("Screen", Vector3.new(0.75, 0.45, 0.01), hinge * CFrame.new(0, 0.275, -0.03), p.Accent)
	screen.Material = Enum.Material.Neon
end

shapes.TV = function(add, p)
	add("Foot", Vector3.new(0.4, 0.04, 0.25), CFrame.new(0, 0.02, 0), SILVER)
	add("Neck", Vector3.new(0.1, 0.18, 0.08), CFrame.new(0, 0.12, 0), SILVER)
	add("Frame", Vector3.new(1, 0.62, 0.08), CFrame.new(0, 0.52, 0), p.Color)
	local screen = add("Screen", Vector3.new(0.9, 0.52, 0.02), CFrame.new(0, 0.52, -0.05), p.Accent)
	screen.Material = Enum.Material.Neon
end

local function addSparkles(part: BasePart, color: Color3, rate: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkles"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(0.6, 1.6)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = part
end

-- Build the model for an item key (e.g. "Cola" or "Cola:Rainbow").
function ProductVisuals.build(key: string, extraScale: number?): Model
	local product = Items.product(key)
	local variant = Items.variant(key)
	local scale = variant.Scale * (extraScale or 1)

	local model = Instance.new("Model")
	model.Name = key
	model:SetAttribute("ItemKey", key)

	local parts: { Part } = {}
	local function add(name: string, size: Vector3, cframe: CFrame, color: Color3, kind: string?): Part
		local scaledCFrame = CFrame.new(cframe.Position * scale) * cframe.Rotation
		local part
		if kind == "cylinder" then
			-- Sizes for cylinders are given as (height, diameter, diameter) standing upright.
			part = Build.cylinder(nil, name, size.X * scale, size.Y * scale, scaledCFrame, color)
		else
			part = Build.part(nil, name, size * scale, scaledCFrame, color)
		end
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Massless = true
		part.Parent = model
		table.insert(parts, part)
		return part
	end

	local builder = shapes[product.Shape] or shapes.Cereal
	builder(add, product)

	if variant.Id == "Golden" then
		for index, part in parts do
			part.Color = if index % 2 == 0 then Color3.fromRGB(255, 225, 110) else Variants.GoldColor
			part.Material = Enum.Material.SmoothPlastic
			part.Reflectance = 0.25
			part.Transparency = 0
		end
		addSparkles(parts[1], Color3.fromRGB(255, 230, 120), 3)
	elseif variant.Id == "Rainbow" then
		for index, part in parts do
			part.Color = Color3.fromHSV((index * 0.17) % 1, 0.75, 1)
			part.Material = Enum.Material.Neon
			part.Transparency = 0
		end
		CollectionService:AddTag(model, ProductVisuals.RainbowTag)
		addSparkles(parts[1], Color3.fromRGB(255, 255, 255), 5)
	elseif variant.Id == "Giant" then
		addSparkles(parts[1], Color3.fromRGB(150, 255, 200), 4)
	end

	model.WorldPivot = CFrame.new()
	return model
end

return ProductVisuals
