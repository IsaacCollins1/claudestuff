--!strict
-- Builds the shared world: ground, road, pavements, decoration and the six
-- empty plots. Stores themselves are built per player by StoreBuilder.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local StoreLevels = require(Shared.StoreLevels)

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

local function tree(parent: Instance, position: Vector3, scale: number)
	local model = Instance.new("Model")
	model.Name = "Tree"
	Build.cylinder(model, "Trunk", 7 * scale, 1.6 * scale, CFrame.new(position + Vector3.new(0, 3.5 * scale, 0)), Color3.fromRGB(130, 88, 55))
	local leafColor = Color3.fromRGB(70, 180, 80)
	Build.ball(model, "Leaves", 8 * scale, CFrame.new(position + Vector3.new(0, 8.5 * scale, 0)), leafColor)
	Build.ball(model, "Leaves2", 5.5 * scale, CFrame.new(position + Vector3.new(1.8 * scale, 11 * scale, 0.6 * scale)), Color3.fromRGB(95, 200, 95))
	model.Parent = parent
end

local function lamp(parent: Instance, position: Vector3)
	local model = Instance.new("Model")
	model.Name = "StreetLamp"
	Build.cylinder(model, "Pole", 12, 0.5, CFrame.new(position + Vector3.new(0, 6, 0)), Color3.fromRGB(60, 64, 76))
	local head = Build.part(model, "Head", Vector3.new(1.4, 0.6, 1.4), CFrame.new(position + Vector3.new(0, 12.2, 0)), Color3.fromRGB(255, 240, 190), Enum.Material.Neon)
	Build.decor(head)
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
		Build.cylinder(model, "BaySignPost", 6.5, 0.5, baySignCFrame * CFrame.new(dx, 3.25, 0), frameColor)
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
	Build.cylinder(vacant, "PostL", 6, 0.5, signCFrame * CFrame.new(-4, 3, 0), Color3.fromRGB(120, 85, 60))
	Build.cylinder(vacant, "PostR", 6, 0.5, signCFrame * CFrame.new(4, 3, 0), Color3.fromRGB(120, 85, 60))
	local board = Build.part(vacant, "Board", Vector3.new(10, 3.4, 0.4), signCFrame * CFrame.new(0, 5.5, 0), Color3.fromRGB(255, 255, 255))
	Build.surfaceText(board, Enum.NormalId.Front, "🏪 FREE PLOT", accent)
	vacant.Parent = model

	model.Parent = parent
	return {
		Index = index,
		CFrame = plotCFrame,
		Model = model,
		Accent = accent,
		VacantSign = vacant,
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
	for x = -length / 2 + 6, length / 2 - 6, 14 do
		local dash = Build.part(world, "LaneDash", Vector3.new(7, 0.05, 0.6), CFrame.new(x, 0.22, 0), Color3.fromRGB(255, 255, 255))
		Build.decor(dash)
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
				tree(world, Vector3.new(x, 0, side * (zOffset + dz)), 0.9 + ((column + dz) % 3) * 0.12)
			end
		end
	end

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
