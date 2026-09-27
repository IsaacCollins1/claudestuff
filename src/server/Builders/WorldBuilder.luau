--!strict
-- Builds the shared world: ground, road, pavements, decoration and the six
-- empty plots. Stores themselves are built per player by StoreBuilder.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Build = require(Shared.Build)
local LowPoly = require(Shared.LowPoly)
local Config = require(Shared.Config)
local StoreLevels = require(Shared.StoreLevels)

local PropBuilder = require(script.Parent.PropBuilder)

local WorldBuilder = {}

WorldBuilder.PlotY = 0.3 -- world height of the plot surface

WorldBuilder.PlotAccents = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(64, 156, 255),
	Color3.fromRGB(70, 200, 110),
	Color3.fromRGB(255, 160, 50),
	Color3.fromRGB(170, 100, 255),
	Color3.fromRGB(255, 110, 190),
}

local GRASS = Color3.fromRGB(110, 196, 84)
local PLOT_GRASS = Color3.fromRGB(128, 212, 98)
local ROAD = Color3.fromRGB(62, 66, 78)
local PAVEMENT = Color3.fromRGB(214, 216, 222)
local PAD_YELLOW = Color3.fromRGB(255, 214, 80)
local HILLS = { Color3.fromRGB(104, 188, 82), Color3.fromRGB(92, 176, 78), Color3.fromRGB(118, 198, 90) }
local ROCK = Color3.fromRGB(150, 154, 166)

export type PlotInfo = {
	Index: number,
	CFrame: CFrame,
	Model: Model,
	Accent: Color3,
	VacantSign: Model,
}

-- World CFrame of every plot. Local -Z (LookVector) faces the road.
function WorldBuilder.plotCFrames(): { CFrame }
	local cframes = {}
	local perSide = math.ceil(Config.PlotCount / 2)
	local zOffset = Config.RoadWidth / 2 + Config.SidewalkWidth + Config.PlotDepth / 2
	for index = 1, Config.PlotCount do
		local side = if index <= perSide then -1 else 1
		local column = (index - 1) % perSide
		local x = (column - (perSide - 1) / 2) * Config.PlotSpacing
		local position = Vector3.new(x, WorldBuilder.PlotY, side * zOffset)
		cframes[index] = CFrame.lookAt(position, Vector3.new(x, WorldBuilder.PlotY, 0))
	end
	return cframes
end

local CAR_COLORS = {
	Color3.fromRGB(80, 150, 255),
	Color3.fromRGB(255, 205, 60),
	Color3.fromRGB(240, 240, 245),
	Color3.fromRGB(255, 110, 90),
	Color3.fromRGB(120, 220, 140),
	Color3.fromRGB(190, 130, 255),
}

-- Props around the shop, kept clear of the paths players and customers walk:
-- a car park and seating on the left, pallets and a forklift by the loading
-- bay, and a fence, hedges and a picnic spot around the back and sides.
local function decoratePlot(parent: Instance, index: number, plotCFrame: CFrame, accent: Color3)
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	local function at(x: number, z: number, yaw: number?): CFrame
		return plotCFrame * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
	end
	local seed = index * 100

	-- Front left: car park with two parked cars.
	PropBuilder.parking(decor, at(-31, -32.5), 3, 7, 11)
	PropBuilder.car(decor, at(-38, -32.5, 180), CAR_COLORS[(index - 1) % #CAR_COLORS + 1])
	PropBuilder.car(decor, at(-24, -32, 180), CAR_COLORS[(index + 2) % #CAR_COLORS + 1])

	-- Along the path: planters, a bench and a bin facing the path, trolleys by the door.
	PropBuilder.planter(decor, at(-8.5, -34, 90), 6, seed + 1)
	PropBuilder.planter(decor, at(8.5, -34, 90), 6, seed + 2)
	PropBuilder.bench(decor, at(-9.5, -22, -90), accent)
	PropBuilder.bin(decor, at(-9.5, -17.5), Color3.fromRGB(60, 150, 90))
	PropBuilder.cartCorral(decor, at(-13, -10), accent)

	-- Loading bay: pallets of stock waiting to go in and a forklift.
	PropBuilder.pallet(decor, at(32, -11), 2, accent)
	PropBuilder.pallet(decor, at(37, -11, 8), 1, Color3.fromRGB(255, 200, 60))
	PropBuilder.forklift(decor, at(41.5, -3.5), Color3.fromRGB(255, 190, 40))

	-- Sides and back.
	PropBuilder.picnicTable(decor, at(-37, 8), accent)
	PropBuilder.flowerBed(decor, at(-37, 24), Vector2.new(8, 6), seed + 3)
	PropBuilder.hedge(decor, at(-43, 18, 90), 36, seed + 4)
	PropBuilder.hedge(decor, at(43, 22, 90), 28, seed + 5)
	PropBuilder.pallet(decor, at(37, 17, -12), 1, accent)
	PropBuilder.dumpster(decor, at(37, 31), Color3.fromRGB(60, 150, 90))
	PropBuilder.fence(decor, at(0, Config.PlotDepth / 2 - 1), Config.PlotWidth - 4)

	decor.Parent = parent
end

local function lamp(parent: Instance, position: Vector3)
	local model = Instance.new("Model")
	model.Name = "StreetLamp"
	local metal = Color3.fromRGB(60, 64, 76)
	LowPoly.hexPrism(model, "Pole", 12, 0.55, CFrame.new(position + Vector3.new(0, 6, 0)), metal)
	LowPoly.hexPrism(model, "Base", 0.8, 1.1, CFrame.new(position + Vector3.new(0, 0.4, 0)), metal)
	-- Six-sided lantern with a pointed cap.
	local lantern = LowPoly.hexPrism(model, "Head", 0.8, 1.5, CFrame.new(position + Vector3.new(0, 12.4, 0)), Color3.fromRGB(255, 240, 190), Enum.Material.Neon)
	local cap = LowPoly.pyramid(model, "Cap", 6, 1.9, 0.7, CFrame.new(position + Vector3.new(0, 12.8, 0)), metal)
	LowPoly.each(lantern, Build.decor)
	LowPoly.each(cap, Build.decor)
	model.Parent = parent
end

local function buildPlot(parent: Instance, index: number, plotCFrame: CFrame): PlotInfo
	local accent = WorldBuilder.PlotAccents[(index - 1) % #WorldBuilder.PlotAccents + 1]
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)

	local function at(x: number, y: number, z: number): CFrame
		return plotCFrame * CFrame.new(x, y, z)
	end

	local w, d = Config.PlotWidth, Config.PlotDepth
	Build.part(model, "Pad", Vector3.new(w, 0.3, d), at(0, -0.15, 0), PLOT_GRASS)

	-- Coloured kerb around the plot so it's clear where each shop starts.
	for _, edge in { { 0, -d / 2, w, 0.8 }, { 0, d / 2, w, 0.8 }, { -w / 2, 0, 0.8, d }, { w / 2, 0, 0.8, d } } do
		local border = Build.part(model, "Border", Vector3.new(edge[3], 0.25, edge[4]), at(edge[1], 0.1, edge[2]), accent)
		Build.decor(border)
	end

	-- Loading bay: yellow pad, dark frame and a painted spot for every box.
	local padCenter = StoreLevels.LoadingPadCenter
	local padSize = StoreLevels.LoadingPadSize
	Build.part(model, "LoadingBay", Vector3.new(padSize.X, 0.1, padSize.Y), at(padCenter.X, 0.05, padCenter.Z), PAD_YELLOW)
	local frameColor = Color3.fromRGB(45, 45, 55)
	for _, edge in {
		{ 0, -padSize.Y / 2, padSize.X + 1, 1 },
		{ 0, padSize.Y / 2, padSize.X + 1, 1 },
		{ -padSize.X / 2, 0, 1, padSize.Y },
		{ padSize.X / 2, 0, 1, padSize.Y },
	} do
		local frame = Build.part(model, "BayFrame", Vector3.new(edge[3], 0.14, edge[4]), at(padCenter.X + edge[1], 0.07, padCenter.Z + edge[2]), frameColor)
		Build.decor(frame)
	end
	for spotIndex, spot in StoreLevels.boxSpots() do
		local marker = Build.part(model, "Spot" .. spotIndex, Vector3.new(3.4, 0.12, 3.4), at(spot.X, 0.06, spot.Z), Color3.fromRGB(255, 236, 150))
		Build.decor(marker)
	end
	-- Standing sign on the far side of the bay, facing the shop and the path.
	local baySignCFrame = at(padCenter.X + padSize.X / 2 + 1.5, 0, padCenter.Z) * CFrame.Angles(0, math.rad(90), 0)
	for _, dx in { -4.5, 4.5 } do
		LowPoly.hexPrism(model, "BaySignPost", 6.5, 0.55, baySignCFrame * CFrame.new(dx, 3.25, 0), frameColor)
	end
	local baySign = Build.part(model, "BaySign", Vector3.new(11, 3, 0.4), baySignCFrame * CFrame.new(0, 5.2, 0), PAD_YELLOW)
	local _, bayLabel = Build.surfaceText(baySign, Enum.NormalId.Front, "📦 DELIVERIES", frameColor)
	local stroke = bayLabel:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		stroke.Color = Color3.fromRGB(255, 255, 255)
	end

	-- "Free plot" sign, hidden once somebody owns the plot.
	local vacant = Instance.new("Model")
	vacant.Name = "VacantSign"
	local signCFrame = at(0, 0, -20)
	LowPoly.hexPrism(vacant, "PostL", 6, 0.55, signCFrame * CFrame.new(-4, 3, 0), Color3.fromRGB(120, 85, 60))
	LowPoly.hexPrism(vacant, "PostR", 6, 0.55, signCFrame * CFrame.new(4, 3, 0), Color3.fromRGB(120, 85, 60))
	local board = Build.part(vacant, "Board", Vector3.new(10, 3.4, 0.4), signCFrame * CFrame.new(0, 5.5, 0), Color3.fromRGB(255, 255, 255))
	Build.surfaceText(board, Enum.NormalId.Front, "🏪 FREE PLOT", accent)
	vacant.Parent = model

	decoratePlot(model, index, plotCFrame, accent)

	model.Parent = parent
	return {
		Index = index,
		CFrame = plotCFrame,
		Model = model,
		Accent = accent,
		VacantSign = vacant,
	}
end

-- Where the three leaderboard signs stand (on the central reservation).
function WorldBuilder.leaderboardCFrames(): { CFrame }
	local gap = Config.PlotSpacing / 2
	return {
		CFrame.new(-gap, 0.5, 0),
		CFrame.new(0, 0.5, 0),
		CFrame.new(gap, 0.5, 0),
	}
end

-- Builds everything and returns the plot list.
function WorldBuilder.build(): { PlotInfo }
	local world = Instance.new("Folder")
	world.Name = "World"

	local plotCFrames = WorldBuilder.plotCFrames()
	local perSide = math.ceil(Config.PlotCount / 2)
	local length = perSide * Config.PlotSpacing + 220
	local depth = 2 * (Config.RoadWidth / 2 + Config.SidewalkWidth + Config.PlotDepth) + 120

	Build.part(world, "Ground", Vector3.new(length, 2, depth), CFrame.new(0, -1, 0), GRASS)
	Build.part(world, "Road", Vector3.new(length, 0.2, Config.RoadWidth), CFrame.new(0, 0.1, 0), ROAD)
	-- Grassy central reservation (the leaderboards stand on it), dashed lines either side of the ends.
	local medianLength = perSide * Config.PlotSpacing
	Build.part(world, "Median", Vector3.new(medianLength, 0.5, 4), CFrame.new(0, 0.25, 0), PLOT_GRASS)
	for _, side in { -1, 1 } do
		local kerb = Build.part(world, "MedianKerb", Vector3.new(medianLength, 0.55, 0.4), CFrame.new(0, 0.275, side * 2.1), Color3.fromRGB(235, 235, 240))
		Build.decor(kerb)
	end
	for x = -length / 2 + 6, length / 2 - 6, 14 do
		if math.abs(x) > medianLength / 2 + 4 then
			local dash = Build.part(world, "LaneDash", Vector3.new(7, 0.05, 0.6), CFrame.new(x, 0.22, 0), Color3.fromRGB(255, 255, 255))
			Build.decor(dash)
		end
	end
	local pavementZ = Config.RoadWidth / 2 + Config.SidewalkWidth / 2
	for _, side in { -1, 1 } do
		Build.part(world, "Pavement", Vector3.new(length, 0.5, Config.SidewalkWidth), CFrame.new(0, 0.25, side * pavementZ), PAVEMENT)
		local kerb = Build.part(world, "Kerb", Vector3.new(length, 0.55, 0.5), CFrame.new(0, 0.275, side * (Config.RoadWidth / 2 + 0.25)), Color3.fromRGB(170, 172, 180))
		Build.decor(kerb)
		for column = 0, perSide do
			local x = (column - perSide / 2) * Config.PlotSpacing
			lamp(world, Vector3.new(x, 0.5, side * (pavementZ + 1.5)))
		end
	end

	-- Trees in the gaps between plots and along the back.
	local zOffset = Config.RoadWidth / 2 + Config.SidewalkWidth + Config.PlotDepth / 2
	for column = 0, perSide do
		local x = (column - perSide / 2) * Config.PlotSpacing
		for _, side in { -1, 1 } do
			for _, dz in { -22, 6, 32 } do
				PropBuilder.tree(world, CFrame.new(x, 0, side * (zOffset + dz)), 0.9 + ((column + dz) % 3) * 0.12, column * 7 + dz)
			end
		end
	end

	-- Low-poly scenery: rolling hills behind the plots and rocks between them.
	-- Purely visual (walk-through).
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	local rng = Random.new(77)
	local hillBand = zOffset + Config.PlotDepth / 2 + 30
	for index = 0, 4 do
		local x = (index - 2) * (length - 120) / 4
		for _, side in { -1, 1 } do
			local size = Vector3.new(rng:NextNumber(44, 60), rng:NextNumber(16, 24), rng:NextNumber(26, 34))
			local color = HILLS[rng:NextInteger(1, #HILLS)]
			local hill = LowPoly.gem(scenery, "Hill", size, CFrame.new(x + rng:NextNumber(-12, 12), 0, side * (hillBand + rng:NextNumber(-4, 4))), color, rng:NextInteger(1, 1e6))
			LowPoly.each(hill, Build.decor)
		end
	end
	for column = 0, perSide do
		local x = (column - perSide / 2) * Config.PlotSpacing
		for _, side in { -1, 1 } do
			local size = Vector3.new(rng:NextNumber(2.4, 3.6), rng:NextNumber(1.6, 2.4), rng:NextNumber(2.2, 3.2))
			local rock = LowPoly.gem(scenery, "Rock", size, CFrame.new(x + 3.5, size.Y * 0.3, side * (zOffset - 12)), ROCK, rng:NextInteger(1, 1e6), true)
			LowPoly.each(rock, Build.decor)
		end
	end
	scenery.Parent = world

	-- Fallback spawn in the middle of the road (players are moved to their plot).
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.4, 10)
	spawn.CFrame = CFrame.new(0, 0.3, 0)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = world

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = world

	local plots = {}
	for index, plotCFrame in plotCFrames do
		plots[index] = buildPlot(plotsFolder, index, plotCFrame)
	end

	world.Parent = workspace
	return plots
end

return WorldBuilder
