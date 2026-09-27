--!strict
-- Decorative props built from Parts: benches, planters, bins, shopping carts,
-- parked cars, pallets, a forklift, picnic tables, fences, hedges and trees.
-- Everything is low-poly: round things are six-sided prisms or faceted
-- gems made of wedge triangles (see Shared/LowPoly).
--
-- Every prop is built around `cframe`: its base sits on the ground and its
-- front faces -Z. The detail parts are walk-through; props you'd expect to
-- bump into get one invisible "Collider" box. The bigger props can be
-- swapped for meshes through ReplicatedStorage.CustomModels.Props (see
-- Shared/ModelLibrary).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Build = require(Shared.Build)
local LowPoly = require(Shared.LowPoly)
local ModelLibrary = require(Shared.ModelLibrary)

local PropBuilder = {}

local WOOD = Color3.fromRGB(186, 128, 78)
local WOOD_DARK = Color3.fromRGB(132, 88, 54)
local METAL = Color3.fromRGB(72, 76, 90)
local CHROME = Color3.fromRGB(210, 214, 222)
local TYRE = Color3.fromRGB(34, 34, 40)
local GLASS = Color3.fromRGB(150, 205, 245)
local SOIL = Color3.fromRGB(110, 76, 52)
local CARDBOARD = Color3.fromRGB(205, 150, 95)
local LEAVES = {
	Color3.fromRGB(76, 180, 80),
	Color3.fromRGB(96, 198, 92),
	Color3.fromRGB(62, 160, 74),
}
local PINES = {
	Color3.fromRGB(46, 140, 80),
	Color3.fromRGB(56, 156, 88),
	Color3.fromRGB(70, 172, 96),
}
local FLOWERS = {
	Color3.fromRGB(255, 95, 120),
	Color3.fromRGB(255, 210, 70),
	Color3.fromRGB(180, 120, 255),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 150, 60),
}

-- Every part walk-through and ignored by raycasts, plus an optional solid box.
local function finish(model: Model, parent: Instance, cframe: CFrame, collider: Vector3?): Model
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			Build.decor(descendant)
		end
	end
	if collider then
		local box = Build.part(model, "Collider", collider, cframe * CFrame.new(0, collider.Y / 2, 0), Build.White)
		box.Transparency = 1
		box.CanQuery = false
		box.CanTouch = false
		box.CastShadow = false
	end
	model.WorldPivot = cframe
	model.Parent = parent
	return model
end

-- A prop that can be replaced by a mesh model from CustomModels.Props.
local function swappable(name: string, fit: Vector3, parent: Instance, cframe: CFrame, build: () -> Model): Model
	local model = ModelLibrary.prop(name, fit, cframe, build)
	model.Parent = parent
	return model
end

local function newModel(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	return model
end

function PropBuilder.bench(parent: Instance, cframe: CFrame, color: Color3): Model
	local model = newModel("Bench")
	local function at(x: number, y: number, z: number): CFrame
		return cframe * CFrame.new(x, y, z)
	end
	for _, x in { -2.3, 2.3 } do
		Build.part(model, "Leg", Vector3.new(0.3, 1.5, 1.8), at(x, 0.75, 0), METAL)
		Build.part(model, "BackPost", Vector3.new(0.3, 1.9, 0.25), at(x, 2.4, 0.85), METAL)
	end
	for _, z in { -0.55, 0, 0.55 } do
		Build.part(model, "Seat", Vector3.new(6, 0.18, 0.45), at(0, 1.6, z), color)
	end
	for _, y in { 2.3, 2.95 } do
		Build.part(model, "Backrest", Vector3.new(6, 0.4, 0.15), at(0, y, 0.95), color)
	end
	return finish(model, parent, cframe, Vector3.new(6, 3.3, 2.2))
end

function PropBuilder.bin(parent: Instance, cframe: CFrame, color: Color3): Model
	local model = newModel("Bin")
	LowPoly.hexPrism(model, "Body", 2.6, 1.9, cframe * CFrame.new(0, 1.3, 0), color)
	LowPoly.hexPrism(model, "Band", 0.3, 1.98, cframe * CFrame.new(0, 2.1, 0), Build.White)
	LowPoly.hexPrism(model, "Lid", 0.3, 2.15, cframe * CFrame.new(0, 2.75, 0), color:Lerp(Color3.new(0, 0, 0), 0.25))
	LowPoly.diamond(model, "Knob", 0.5, cframe * CFrame.new(0, 3, 0), color:Lerp(Color3.new(0, 0, 0), 0.25))
	return finish(model, parent, cframe, Vector3.new(1.9, 3, 1.9))
end

-- Long wooden planter full of bushes and flowers (runs along X).
function PropBuilder.planter(parent: Instance, cframe: CFrame, length: number, seed: number): Model
	local model = newModel("Planter")
	local rng = Random.new(seed)
	Build.part(model, "Box", Vector3.new(length, 1.4, 2.2), cframe * CFrame.new(0, 0.7, 0), WOOD)
	Build.part(model, "Rim", Vector3.new(length + 0.3, 0.2, 2.5), cframe * CFrame.new(0, 1.45, 0), WOOD_DARK)
	Build.part(model, "Soil", Vector3.new(length - 0.4, 0.1, 1.8), cframe * CFrame.new(0, 1.5, 0), SOIL)
	local count = math.max(1, math.floor(length / 2))
	for index = 1, count do
		local x = -length / 2 + (index - 0.5) * (length / count)
		LowPoly.gem(model, "Bush", Vector3.new(2.3, 1.7, 2), cframe * CFrame.new(x, 2.2, 0), LEAVES[rng:NextInteger(1, #LEAVES)], rng:NextInteger(1, 1e6), true)
		for _ = 1, 2 do
			local flower = cframe * CFrame.new(x + rng:NextNumber(-0.7, 0.7), 2.85, rng:NextNumber(-0.5, 0.5))
			LowPoly.diamond(model, "Flower", 0.6, flower, FLOWERS[rng:NextInteger(1, #FLOWERS)])
		end
	end
	return finish(model, parent, cframe, nil)
end

-- Flower bed flat on the grass.
function PropBuilder.flowerBed(parent: Instance, cframe: CFrame, size: Vector2, seed: number): Model
	local model = newModel("FlowerBed")
	local rng = Random.new(seed)
	Build.part(model, "Edge", Vector3.new(size.X + 0.6, 0.4, size.Y + 0.6), cframe * CFrame.new(0, 0.2, 0), Color3.fromRGB(200, 200, 205))
	Build.part(model, "Soil", Vector3.new(size.X, 0.45, size.Y), cframe * CFrame.new(0, 0.22, 0), SOIL)
	for x = -size.X / 2 + 1, size.X / 2 - 0.9, 1.5 do
		for z = -size.Y / 2 + 1, size.Y / 2 - 0.9, 1.5 do
			local base = cframe * CFrame.new(x + rng:NextNumber(-0.3, 0.3), 0, z + rng:NextNumber(-0.3, 0.3))
			Build.part(model, "Stem", Vector3.new(0.15, 1, 0.15), base * CFrame.new(0, 0.9, 0), LEAVES[3])
			LowPoly.diamond(model, "Flower", 0.8, base * CFrame.new(0, 1.5, 0), FLOWERS[rng:NextInteger(1, #FLOWERS)])
		end
	end
	return finish(model, parent, cframe, nil)
end

-- A chunky low-poly hedge (runs along X): bevelled blocks of slightly different heights.
function PropBuilder.hedge(parent: Instance, cframe: CFrame, length: number, seed: number): Model
	local model = newModel("Hedge")
	local rng = Random.new(seed)
	local count = math.max(1, math.floor(length / 3))
	local step = length / count
	for index = 1, count do
		local x = -length / 2 + (index - 0.5) * step
		local height = rng:NextNumber(2.3, 3.1)
		local depth = rng:NextNumber(2.5, 2.9)
		LowPoly.bevelBox(model, "Bush", Vector3.new(step + 0.1, height, depth), cframe * CFrame.new(x, height / 2, 0), LEAVES[rng:NextInteger(1, #LEAVES)], 0.7)
	end
	return finish(model, parent, cframe, nil)
end

-- Wooden fence (runs along X).
function PropBuilder.fence(parent: Instance, cframe: CFrame, length: number): Model
	local model = newModel("Fence")
	local posts = math.max(1, math.floor(length / 4))
	for index = 0, posts do
		local x = -length / 2 + index * (length / posts)
		Build.part(model, "Post", Vector3.new(0.5, 3.4, 0.5), cframe * CFrame.new(x, 1.7, 0), WOOD_DARK)
		Build.part(model, "Cap", Vector3.new(0.7, 0.2, 0.7), cframe * CFrame.new(x, 3.5, 0), WOOD)
	end
	for _, y in { 1.2, 2.6 } do
		Build.part(model, "Rail", Vector3.new(length, 0.35, 0.25), cframe * CFrame.new(0, y, 0), WOOD)
	end
	return finish(model, parent, cframe, nil)
end

-- Low-poly tree: a lumpy faceted crown on a six-sided trunk, or (every third
-- seed) a pine made of three stacked six-sided cones.
function PropBuilder.tree(parent: Instance, cframe: CFrame, scale: number, seed: number): Model
	return swappable("Tree", Vector3.new(14, 16, 14) * scale, parent, cframe, function()
		local model = newModel("Tree")
		local rng = Random.new(seed)
		local bark = Color3.fromRGB(130, 88, 55)
		if seed % 3 == 0 then
			LowPoly.hexPrism(model, "Trunk", 6 * scale, 1.3 * scale, cframe * CFrame.new(0, 3 * scale, 0), bark)
			for tier = 1, 3 do
				local width = (9.6 - tier * 2.2) * scale
				local baseY = (3 + tier * 2.7) * scale
				local turn = CFrame.Angles(0, tier * 0.55 + rng:NextNumber(0, 0.3), 0)
				LowPoly.pyramid(model, "Needles", 6, width, 4.8 * scale, cframe * CFrame.new(0, baseY, 0) * turn, PINES[tier])
			end
		else
			LowPoly.hexPrism(model, "Trunk", 7 * scale, 1.5 * scale, cframe * CFrame.new(0, 3.5 * scale, 0), bark)
			LowPoly.hexPrism(model, "Branch", 3 * scale, 0.6 * scale, cframe * CFrame.new(1 * scale, 7 * scale, 0) * CFrame.Angles(0, 0, math.rad(-35)), bark)
			local leaves = LEAVES[rng:NextInteger(1, #LEAVES)]
			LowPoly.gem(model, "Leaves", Vector3.new(9, 7.6, 9) * scale, cframe * CFrame.new(0, 9.8 * scale, 0), leaves, seed)
			-- A few apples for fun.
			for _ = 1, 3 do
				local angle = rng:NextNumber(0, math.pi * 2)
				local offset = Vector3.new(math.cos(angle) * 3.9, rng:NextNumber(7.8, 10), math.sin(angle) * 3.9)
				LowPoly.diamond(model, "Apple", 0.8 * scale, cframe * CFrame.new(offset * scale), Color3.fromRGB(235, 60, 60))
			end
		end
		return finish(model, parent, cframe, Vector3.new(1.6, 7, 1.6) * scale)
	end)
end

-- Shopping cart, handle at the back (+Z).
function PropBuilder.cart(parent: Instance, cframe: CFrame, color: Color3): Model
	local model = newModel("ShoppingCart")
	local function at(x: number, y: number, z: number): CFrame
		return cframe * CFrame.new(x, y, z)
	end
	Build.part(model, "Floor", Vector3.new(2, 0.1, 3), at(0, 1.55, 0), CHROME)
	for _, x in { -1, 1 } do
		local side = Build.part(model, "Side", Vector3.new(0.08, 1.3, 3), at(x, 2.2, 0), CHROME)
		side.Transparency = 0.35
		Build.part(model, "RimSide", Vector3.new(0.14, 0.14, 3.1), at(x, 2.9, 0), color)
		Build.part(model, "Rail", Vector3.new(0.14, 0.14, 3), at(x * 0.8, 0.5, 0), CHROME)
		Build.part(model, "Upright", Vector3.new(0.14, 1.2, 0.14), at(x * 0.85, 1, 1.35), CHROME)
		Build.part(model, "HandlePost", Vector3.new(0.12, 0.7, 0.12), at(x, 3.1, 1.75), CHROME)
		for _, z in { -1.2, 1.2 } do
			Build.part(model, "Wheel", Vector3.new(0.25, 0.5, 0.5), at(x * 0.8, 0.28, z) * CFrame.Angles(math.rad(45), 0, 0), TYRE)
		end
	end
	for _, z in { -1.5, 1.5 } do
		local panel = Build.part(model, "End", Vector3.new(2, 1.3, 0.08), at(0, 2.2, z), CHROME)
		panel.Transparency = 0.35
		Build.part(model, "RimEnd", Vector3.new(2.1, 0.14, 0.14), at(0, 2.9, z), color)
	end
	Build.part(model, "Handle", Vector3.new(2.3, 0.22, 0.22), at(0, 3.45, 1.85), color)
	return finish(model, parent, cframe, nil)
end

-- Rail with a row of nested carts and a little sign.
function PropBuilder.cartCorral(parent: Instance, cframe: CFrame, accent: Color3): Model
	local model = newModel("CartCorral")
	for _, x in { -1.6, 1.6 } do
		for _, z in { -3.4, 3.4 } do
			LowPoly.hexPrism(model, "Post", 2.4, 0.34, cframe * CFrame.new(x, 1.2, z), METAL)
		end
		Build.part(model, "Rail", Vector3.new(0.25, 0.25, 7), cframe * CFrame.new(x, 2.3, 0), accent)
	end
	for _, z in { -2.2, -0.9, 0.4, 1.7 } do
		PropBuilder.cart(model, cframe * CFrame.new(0, 0, z), accent)
	end
	local sign = Build.part(model, "Sign", Vector3.new(3.4, 1.3, 0.2), cframe * CFrame.new(0, 3.3, -3.4), Build.White)
	Build.surfaceText(sign, Enum.NormalId.Front, "🛒 CARTS", accent)
	return finish(model, parent, cframe, nil)
end

-- Parked hatchback.
function PropBuilder.car(parent: Instance, cframe: CFrame, color: Color3): Model
	return swappable("Car", Vector3.new(5.2, 4.4, 10.4), parent, cframe, function()
		local model = newModel("Car")
		local function at(x: number, y: number, z: number): CFrame
			return cframe * CFrame.new(x, y, z)
		end
		local trim = color:Lerp(Color3.new(0, 0, 0), 0.3)
		Build.part(model, "Body", Vector3.new(5, 1.6, 10), at(0, 1.5, 0), color)
		Build.part(model, "Hood", Vector3.new(4.8, 0.3, 3), at(0, 2.4, -3.4), color)
		Build.part(model, "Cabin", Vector3.new(4.6, 1.5, 4.6), at(0, 3.05, 0.9), color)
		Build.part(model, "Windows", Vector3.new(4.7, 1.0, 4.2), at(0, 3.1, 0.9), GLASS, Enum.Material.Glass)
		Build.wedge(model, "Windscreen", Vector3.new(4.6, 1.5, 1.6), at(0, 3.05, -2.2), GLASS, Enum.Material.Glass)
		Build.wedge(model, "RearWindow", Vector3.new(4.6, 1.5, 0.8), at(0, 3.05, 3.6) * CFrame.Angles(0, math.pi, 0), GLASS, Enum.Material.Glass)
		Build.part(model, "Roof", Vector3.new(4.5, 0.2, 4.4), at(0, 3.9, 0.9), color)
		for _, z in { -5.1, 5.1 } do
			Build.part(model, "Bumper", Vector3.new(5.1, 0.5, 0.4), at(0, 0.95, z), trim)
		end
		Build.part(model, "Grille", Vector3.new(2, 0.5, 0.1), at(0, 1.55, -5.05), TYRE)
		for _, x in { -1, 1 } do
			local head = Build.part(model, "Headlight", Vector3.new(1.1, 0.5, 0.1), at(x * 1.7, 1.9, -5.03), Color3.fromRGB(255, 250, 220), Enum.Material.Neon)
			head.CastShadow = false
			local tail = Build.part(model, "Taillight", Vector3.new(0.9, 0.5, 0.1), at(x * 1.8, 1.9, 5.03), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
			tail.CastShadow = false
			Build.part(model, "Mirror", Vector3.new(0.5, 0.35, 0.3), at(x * 2.6, 2.6, -1.6), trim)
			Build.part(model, "Handle", Vector3.new(0.08, 0.15, 0.5), at(x * 2.53, 2.05, 0.2), CHROME)
			for _, z in { -3.2, 3.2 } do
				LowPoly.sideHexPrism(model, "Tyre", 0.8, 2.1, at(x * 2.3, 1, z), TYRE)
				LowPoly.sideHexPrism(model, "Hubcap", 0.86, 0.9, at(x * 2.3, 1, z), CHROME)
			end
		end
		return finish(model, parent, cframe, Vector3.new(5.2, 4.2, 10.4))
	end)
end

-- Painted parking bays (lines run along Z), `bays` wide along X.
function PropBuilder.parking(parent: Instance, cframe: CFrame, bays: number, bayWidth: number, length: number): Model
	local model = newModel("Parking")
	Build.part(model, "Tarmac", Vector3.new(bays * bayWidth + 2, 0.08, length + 2), cframe * CFrame.new(0, 0.04, 0), Color3.fromRGB(88, 92, 104))
	for index = 0, bays do
		local x = -bays * bayWidth / 2 + index * bayWidth
		Build.part(model, "Line", Vector3.new(0.3, 0.02, length), cframe * CFrame.new(x, 0.09, 0), Build.White)
	end
	Build.part(model, "Kerb", Vector3.new(bays * bayWidth + 2, 0.3, 0.6), cframe * CFrame.new(0, 0.15, length / 2 + 0.7), Color3.fromRGB(235, 235, 240))
	local signX = -bays * bayWidth / 2 - 1.8
	LowPoly.hexPrism(model, "SignPost", 5, 0.34, cframe * CFrame.new(signX, 2.5, length / 2), METAL)
	local sign = Build.part(model, "Sign", Vector3.new(1.8, 1.8, 0.2), cframe * CFrame.new(signX, 5.3, length / 2 - 0.2), Color3.fromRGB(40, 110, 230))
	Build.surfaceText(sign, Enum.NormalId.Front, "P", Build.White)
	return finish(model, parent, cframe, nil)
end

-- Cardboard box stack on a wooden pallet, shrink-wrapped.
function PropBuilder.pallet(parent: Instance, cframe: CFrame, layers: number, tape: Color3): Model
	local model = newModel("Pallet")
	for _, z in { -1.7, 0, 1.7 } do
		Build.part(model, "Block", Vector3.new(4, 0.35, 0.6), cframe * CFrame.new(0, 0.18, z), WOOD_DARK)
	end
	for x = -1.6, 1.61, 0.8 do
		Build.part(model, "Slat", Vector3.new(0.6, 0.15, 4), cframe * CFrame.new(x, 0.43, 0), WOOD)
	end
	local boxSize = 1.9
	for layer = 1, layers do
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				local center = cframe * CFrame.new(x * boxSize / 2, 0.5 + (layer - 0.5) * boxSize, z * boxSize / 2)
				Build.part(model, "Box", Vector3.new(boxSize - 0.05, boxSize - 0.05, boxSize - 0.05), center, CARDBOARD)
				Build.part(model, "Tape", Vector3.new(0.4, 0.04, boxSize), center * CFrame.new(0, boxSize / 2 - 0.01, 0), tape)
			end
		end
	end
	local wrap = Build.part(model, "Wrap", Vector3.new(4.05, layers * boxSize, 4.05), cframe * CFrame.new(0, 0.5 + layers * boxSize / 2, 0), Build.White)
	wrap.Transparency = 0.75
	wrap.CastShadow = false
	return finish(model, parent, cframe, Vector3.new(4, 0.5 + layers * boxSize, 4))
end

-- Little forklift, forks at the front (-Z).
function PropBuilder.forklift(parent: Instance, cframe: CFrame, color: Color3): Model
	return swappable("Forklift", Vector3.new(3.8, 6, 8.2), parent, cframe, function()
		local model = newModel("Forklift")
		local function at(x: number, y: number, z: number): CFrame
			return cframe * CFrame.new(x, y, z)
		end
		Build.part(model, "Body", Vector3.new(3.6, 1.8, 4.6), at(0, 1.5, 0.6), color)
		Build.part(model, "Counterweight", Vector3.new(3.6, 1.8, 1.2), at(0, 1.6, 3.4), METAL)
		Build.part(model, "Seat", Vector3.new(1.6, 0.5, 1.4), at(0, 2.65, 1.3), TYRE)
		Build.part(model, "SeatBack", Vector3.new(1.6, 1.3, 0.3), at(0, 3.3, 2.05), TYRE)
		LowPoly.hexPrism(model, "Steering", 0.12, 0.9, at(0, 3.2, -0.5) * CFrame.Angles(math.rad(-30), 0, 0), TYRE)
		for _, x in { -1.6, 1.6 } do
			for _, z in { -1.3, 2.9 } do
				Build.part(model, "GuardPost", Vector3.new(0.2, 3.2, 0.2), at(x, 4, z), METAL)
			end
			Build.part(model, "Mast", Vector3.new(0.3, 5.2, 0.3), at(x * 0.55, 2.9, -2), METAL)
			LowPoly.sideHexPrism(model, "FrontWheel", 0.7, 1.7, at(x * 1.19, 0.8, -1.1), TYRE)
			LowPoly.sideHexPrism(model, "RearWheel", 0.7, 1.4, at(x * 1.19, 0.65, 2.9), TYRE)
		end
		Build.part(model, "Roof", Vector3.new(3.6, 0.2, 4.6), at(0, 5.7, 0.8), METAL)
		Build.part(model, "Crossbar", Vector3.new(2, 0.3, 0.3), at(0, 5.4, -2), METAL)
		Build.part(model, "Backrest", Vector3.new(2.4, 1.3, 0.15), at(0, 1.1, -2.3), METAL)
		for _, x in { -0.7, 0.7 } do
			Build.part(model, "Fork", Vector3.new(0.4, 0.15, 3), at(x, 0.45, -3.8), CHROME)
		end
		local beacon = LowPoly.diamond(model, "Beacon", 0.7, at(0, 6, 1.6), Color3.fromRGB(255, 160, 30), Enum.Material.Neon)
		beacon.CastShadow = false
		return finish(model, parent, cframe, Vector3.new(3.8, 6, 5.4))
	end)
end

-- Picnic table with a striped parasol.
function PropBuilder.picnicTable(parent: Instance, cframe: CFrame, parasol: Color3): Model
	local model = newModel("PicnicTable")
	local function at(x: number, y: number, z: number): CFrame
		return cframe * CFrame.new(x, y, z)
	end
	Build.part(model, "Top", Vector3.new(6, 0.25, 3), at(0, 2.6, 0), WOOD)
	for _, z in { -2.2, 2.2 } do
		Build.part(model, "Seat", Vector3.new(6, 0.22, 1), at(0, 1.5, z), WOOD)
	end
	for _, x in { -2.3, 2.3 } do
		Build.part(model, "Leg", Vector3.new(0.3, 2.5, 0.3), at(x, 1.25, 0), WOOD_DARK)
		Build.part(model, "Brace", Vector3.new(0.3, 0.3, 5.4), at(x, 1.3, 0), WOOD_DARK)
	end
	LowPoly.hexPrism(model, "Pole", 5.6, 0.26, at(0, 3.3, 0), Build.White)
	-- Eight-sided striped canopy.
	LowPoly.pyramid(model, "Canopy", 8, 7.4, 1.7, at(0, 5.6, 0), parasol, { parasol, Build.White }, true)
	LowPoly.diamond(model, "Knob", 0.5, at(0, 7.4, 0), parasol)
	return finish(model, parent, cframe, Vector3.new(6, 2.8, 5.4))
end

function PropBuilder.dumpster(parent: Instance, cframe: CFrame, color: Color3): Model
	local model = newModel("Dumpster")
	Build.part(model, "Body", Vector3.new(6, 3.4, 3.4), cframe * CFrame.new(0, 2.1, 0), color)
	Build.part(model, "Band", Vector3.new(6.1, 0.3, 3.5), cframe * CFrame.new(0, 3.2, 0), color:Lerp(Color3.new(0, 0, 0), 0.3))
	Build.part(model, "Lid", Vector3.new(6.2, 0.3, 3.7), cframe * CFrame.new(0, 3.95, 0.1) * CFrame.Angles(math.rad(6), 0, 0), METAL)
	for _, x in { -2.4, 2.4 } do
		for _, z in { -1.2, 1.2 } do
			LowPoly.sideHexPrism(model, "Wheel", 0.4, 0.85, cframe * CFrame.new(x, 0.4, z), TYRE)
		end
	end
	return finish(model, parent, cframe, Vector3.new(6, 4, 3.6))
end

-- Retro gumball machine for the shop front.
function PropBuilder.gumballMachine(parent: Instance, cframe: CFrame, color: Color3): Model
	local model = newModel("GumballMachine")
	LowPoly.hexPrism(model, "Stand", 2.2, 0.55, cframe * CFrame.new(0, 1.1, 0), color)
	Build.part(model, "Base", Vector3.new(1.4, 1.1, 1.4), cframe * CFrame.new(0, 2.6, 0), color)
	Build.part(model, "Slot", Vector3.new(0.4, 0.4, 0.1), cframe * CFrame.new(0, 2.6, -0.72), CHROME)
	LowPoly.each(LowPoly.gem(model, "Globe", Vector3.new(2, 2, 2), cframe * CFrame.new(0, 3.95, 0), GLASS, 11, true, Enum.Material.Glass), function(part)
		part.Transparency = 0.55
	end)
	local rng = Random.new(7)
	for _ = 1, 10 do
		local offset = Vector3.new(rng:NextNumber(-0.45, 0.45), rng:NextNumber(-0.55, 0.1), rng:NextNumber(-0.45, 0.45))
		LowPoly.diamond(model, "Gum", 0.45, cframe * CFrame.new(Vector3.new(0, 3.95, 0) + offset), FLOWERS[rng:NextInteger(1, #FLOWERS)])
	end
	LowPoly.hexPrism(model, "Cap", 0.3, 0.9, cframe * CFrame.new(0, 4.95, 0), color)
	return finish(model, parent, cframe, nil)
end

-- Ice-cream freezer chest.
function PropBuilder.freezer(parent: Instance, cframe: CFrame): Model
	local model = newModel("Freezer")
	local body = Build.part(model, "Body", Vector3.new(4, 2.6, 2), cframe * CFrame.new(0, 1.3, 0), Build.White)
	local lid = Build.part(model, "Lid", Vector3.new(3.8, 0.12, 1.8), cframe * CFrame.new(0, 2.66, 0), GLASS, Enum.Material.Glass)
	lid.Transparency = 0.4
	for index, x in { -1.2, -0.4, 0.4, 1.2 } do
		Build.part(model, "Tub", Vector3.new(0.7, 0.5, 1.4), cframe * CFrame.new(x, 2.35, 0), FLOWERS[index])
	end
	Build.part(model, "Stripe", Vector3.new(4.02, 0.5, 2.02), cframe * CFrame.new(0, 0.5, 0), Color3.fromRGB(70, 150, 255))
	Build.surfaceText(body, Enum.NormalId.Front, "🍦 ICE CREAM", Color3.fromRGB(70, 150, 255))
	return finish(model, parent, cframe, Vector3.new(4, 2.7, 2))
end

-- Brass post and red rope, for the VIP carpet.
function PropBuilder.stanchions(parent: Instance, from: CFrame, count: number, spacing: number): Model
	local model = newModel("Stanchions")
	local gold = Color3.fromRGB(255, 200, 60)
	for index = 0, count - 1 do
		local base = from * CFrame.new(0, 0, index * spacing)
		LowPoly.hexPrism(model, "Foot", 0.2, 1.05, base * CFrame.new(0, 0.1, 0), gold)
		LowPoly.hexPrism(model, "Post", 2.6, 0.3, base * CFrame.new(0, 1.3, 0), gold)
		local top = LowPoly.diamond(model, "Top", 0.5, base * CFrame.new(0, 2.72, 0), gold)
		top.Reflectance = 0.3
		if index < count - 1 then
			Build.part(model, "Rope", Vector3.new(0.18, 0.18, spacing), base * CFrame.new(0, 2.3, spacing / 2), Color3.fromRGB(200, 30, 50))
		end
	end
	return finish(model, parent, from, nil)
end

return PropBuilder
