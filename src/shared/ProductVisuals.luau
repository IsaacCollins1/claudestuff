--!strict
-- Builds the little 3D product models seen on shelves, in customers' baskets
-- and popping out of opened boxes. Built from Parts in a low-poly style (round
-- things are six-sided prisms, see LowPoly); a mesh model put in
-- ReplicatedStorage.CustomModels.Products replaces the Part version (see ModelLibrary).
--
-- Models are built around the origin with their base at Y = 0 and their
-- "front" facing -Z, so `model:PivotTo(slotCFrame)` places them on a shelf.

local CollectionService = game:GetService("CollectionService")

local Build = require(script.Parent.Build)
local Items = require(script.Parent.Items)
local LowPoly = require(script.Parent.LowPoly)
local ModelLibrary = require(script.Parent.ModelLibrary)
local Products = require(script.Parent.Products)
local Variants = require(script.Parent.Variants)

local ProductVisuals = {}

ProductVisuals.RainbowTag = "RainbowItem"

local SILVER = Color3.fromRGB(205, 208, 215)
local DARK = Color3.fromRGB(30, 30, 36)

-- kind: nil = block, "hex" = upright six-sided prism (size is height, width, width).
-- `props` are applied to every part made (e.g. Transparency, Material).
type Adder = (name: string, size: Vector3, cframe: CFrame, color: Color3, kind: string?, props: { [string]: any }?) -> ()

local shapes: { [string]: (add: Adder, product: Products.Product) -> () } = {}

local GLASSY = { Transparency = 0.15 }
local GLOW = { Material = Enum.Material.Neon }

shapes.Bottle = function(add, p)
	add("Body", Vector3.new(0.72, 0.5, 0.5), CFrame.new(0, 0.36, 0), p.Color, "hex", GLASSY)
	add("Label", Vector3.new(0.3, 0.54, 0.54), CFrame.new(0, 0.38, 0), p.Accent, "hex")
	add("Shoulder", Vector3.new(0.24, 0.36, 0.36), CFrame.new(0, 0.84, 0), p.Color, "hex", GLASSY)
	add("Neck", Vector3.new(0.16, 0.2, 0.16), CFrame.new(0, 1.03, 0), p.Color, nil, GLASSY)
	add("Cap", Vector3.new(0.22, 0.14, 0.22), CFrame.new(0, 1.17, 0) * CFrame.Angles(0, math.rad(45), 0), p.Accent)
end

shapes.Can = function(add, p)
	add("Body", Vector3.new(0.8, 0.5, 0.5), CFrame.new(0, 0.4, 0), p.Color, "hex")
	add("Band", Vector3.new(0.25, 0.53, 0.53), CFrame.new(0, 0.44, 0), p.Accent, "hex")
	add("Top", Vector3.new(0.06, 0.44, 0.44), CFrame.new(0, 0.82, 0), SILVER, "hex")
end

shapes.Bag = function(add, p)
	-- A puffy crisp packet: a faceted pillow with crimped ends.
	add("Body", Vector3.new(0.7, 0.84, 0.16), CFrame.new(0, 0.48, 0), p.Color)
	add("Puff", Vector3.new(0.66, 0.3, 0.3), CFrame.new(0, 0.48, 0) * CFrame.Angles(math.rad(45), 0, 0), p.Color)
	add("Band", Vector3.new(0.5, 0.26, 0.05), CFrame.new(0, 0.46, -0.22), p.Accent)
	add("CrimpTop", Vector3.new(0.74, 0.08, 0.12), CFrame.new(0, 0.93, 0), p.Accent)
	add("CrimpBottom", Vector3.new(0.74, 0.08, 0.12), CFrame.new(0, 0.04, 0), p.Accent)
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
		add("Roll" .. index, Vector3.new(0.4, 0.36, 0.36), CFrame.new(offset.X, offset.Y, 0), p.Color, "hex")
	end
	add("Wrap", Vector3.new(0.74, 0.12, 0.37), CFrame.new(0, 0.42, 0), p.Accent, nil, { Transparency = 0.2 })
end

shapes.Pizza = function(add, p)
	add("Box1", Vector3.new(0.85, 0.16, 0.85), CFrame.new(0, 0.08, 0), p.Color)
	add("Box2", Vector3.new(0.85, 0.16, 0.85), CFrame.new(0, 0.25, 0) * CFrame.Angles(0, math.rad(6), 0), p.Color)
	add("Logo", Vector3.new(0.02, 0.55, 0.55), CFrame.new(0, 0.34, 0) * CFrame.Angles(0, math.rad(6), 0), p.Accent, "hex")
end

shapes.Spray = function(add, p)
	add("Body", Vector3.new(0.75, 0.42, 0.42), CFrame.new(0, 0.375, 0), p.Color, "hex")
	add("Label", Vector3.new(0.25, 0.45, 0.45), CFrame.new(0, 0.35, 0), p.Accent, "hex")
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
	add("Screen", Vector3.new(0.36, 0.68, 0.02), CFrame.new(0, 0.48, -0.04), p.Accent, nil, GLOW)
end

shapes.Console = function(add, p)
	add("Body", Vector3.new(0.9, 0.28, 0.6), CFrame.new(0, 0.14, 0), p.Color)
	add("Stripe", Vector3.new(0.91, 0.04, 0.61), CFrame.new(0, 0.2, 0), p.Accent, nil, GLOW)
	add("Pad", Vector3.new(0.36, 0.1, 0.22), CFrame.new(0.15, 0.33, -0.1), DARK)
end

shapes.Laptop = function(add, p)
	add("Base", Vector3.new(0.85, 0.06, 0.6), CFrame.new(0, 0.03, 0), p.Color)
	local hinge = CFrame.new(0, 0.06, 0.28) * CFrame.Angles(math.rad(15), 0, 0)
	add("Lid", Vector3.new(0.85, 0.55, 0.05), hinge * CFrame.new(0, 0.275, 0), p.Color)
	add("Screen", Vector3.new(0.75, 0.45, 0.01), hinge * CFrame.new(0, 0.275, -0.03), p.Accent, nil, GLOW)
end

shapes.TV = function(add, p)
	add("Foot", Vector3.new(0.4, 0.04, 0.25), CFrame.new(0, 0.02, 0), SILVER)
	add("Neck", Vector3.new(0.1, 0.18, 0.08), CFrame.new(0, 0.12, 0), SILVER)
	add("Frame", Vector3.new(1, 0.62, 0.08), CFrame.new(0, 0.52, 0), p.Color)
	add("Screen", Vector3.new(0.9, 0.52, 0.02), CFrame.new(0, 0.52, -0.05), p.Accent, nil, GLOW)
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

local warned: { [string]: boolean } = {}

-- Parts you can see (custom models often carry invisible hitboxes).
local function visibleParts(model: Model): { BasePart }
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 0.99 then
			table.insert(parts, descendant)
		end
	end
	return parts
end

-- Golden/Rainbow items are recoloured, so drop textures that would hide it.
local function stripTextures(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("SurfaceAppearance") or descendant:IsA("Decal") then
			descendant:Destroy()
		elseif descendant:IsA("MeshPart") then
			local meshPart = descendant
			pcall(function()
				meshPart.TextureID = ""
			end)
		elseif descendant:IsA("SpecialMesh") then
			descendant.TextureId = ""
		end
	end
end

-- Build the model for an item key (e.g. "Cola" or "Cola:Rainbow").
function ProductVisuals.build(key: string, extraScale: number?): Model
	local product = Items.product(key)
	local variant = Items.variant(key)
	local scale = variant.Scale * (extraScale or 1)

	local model = Instance.new("Model")
	model.Name = key
	model:SetAttribute("ItemKey", key)

	local parts: { BasePart } = {}
	local function add(name: string, size: Vector3, cframe: CFrame, color: Color3, kind: string?, props: { [string]: any }?)
		local scaledCFrame = CFrame.new(cframe.Position * scale) * cframe.Rotation
		local made: { BasePart }
		if kind == "hex" then
			-- Sizes for hex prisms are given as (height, width, width) standing upright.
			made = LowPoly.hexPrism(nil, name, size.X * scale, size.Y * scale, scaledCFrame, color)
		else
			made = { Build.part(nil, name, size * scale, scaledCFrame, color) }
		end
		for _, part in made do
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Massless = true
			if props then
				for key, value in props do
					(part :: any)[key] = value
				end
			end
			part.Parent = model
			table.insert(parts, part)
		end
	end

	local builder = shapes[product.Shape] or shapes.Cereal
	builder(add, product)

	-- Swap in a custom mesh model if the developer added one.
	local template = ModelLibrary.template("Products", product.Id)
	if template then
		local ok, custom = pcall(function(): Model
			return ModelLibrary.fitted(template, model:GetExtentsSize())
		end)
		if ok then
			model:Destroy()
			model = custom
			model.Name = key
			model:SetAttribute("ItemKey", key)
			ModelLibrary.makeDecor(model)
			parts = visibleParts(model)
			if variant.Id == "Golden" or variant.Id == "Rainbow" then
				stripTextures(model)
			end
		elseif not warned[product.Id] then
			warned[product.Id] = true
			warn(`[FillTheStore] Couldn't use CustomModels.Products.{product.Id}: {custom}`)
		end
	end
	if #parts == 0 then
		model.WorldPivot = CFrame.new()
		return model
	end

	-- Pieces of one prism share a name, so colour by name to keep them matching.
	local nameIndex: { [string]: number } = {}
	local nextIndex = 0
	local function pieceIndex(part: BasePart): number
		local index = nameIndex[part.Name]
		if not index then
			nextIndex += 1
			index = nextIndex
			nameIndex[part.Name] = index
		end
		return index
	end
	if variant.Id == "Golden" then
		for _, part in parts do
			part.Color = if pieceIndex(part) % 2 == 0 then Color3.fromRGB(255, 225, 110) else Variants.GoldColor
			part.Material = Enum.Material.SmoothPlastic
			part.Reflectance = 0.25
			part.Transparency = 0
		end
		addSparkles(parts[1], Color3.fromRGB(255, 230, 120), 3)
	elseif variant.Id == "Rainbow" then
		for _, part in parts do
			part.Color = Color3.fromHSV((pieceIndex(part) * 0.17) % 1, 0.75, 1)
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
