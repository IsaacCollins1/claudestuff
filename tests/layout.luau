--!nocheck
-- Geometry checks for every store level, using the real StoreBuilder output:
--   * customer/worker waypoint routes never pass through walls, shelves or the till
--   * shelves/counter don't overlap each other or the walls
--   * the owner spawn, loading bay and delivery van lane are clear of the shop
--
--   lune run tests/layout.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Instances = require("./emulator/Instances")
local Runtime = require("./emulator/Runtime")
local Scheduler = require("./emulator/Scheduler")

local Vector3 = roblox.Vector3
local PLACE = process.args[1] or "build/FillTheStore.rbxlx"
local NPC_RADIUS = 1.1 -- R6 torso is 2 studs wide

local failures = 0
local function check(condition, message)
	print((if condition then "  \27[32m✔\27[0m " else "  \27[31m✘ ") .. message .. (if condition then "" else "\27[0m"))
	if not condition then
		failures += 1
	end
end

local runtime = Runtime.new({ placePath = PLACE, placeId = 0 })
runtime:startServer()
runtime:run(0.5)

local server = runtime.game.ServerScriptService.Server
local shared = runtime.game.ReplicatedStorage.Shared
local StoreBuilder = runtime:serverModule(server.Builders.StoreBuilder)
local WorldBuilder = runtime:serverModule(server.Builders.WorldBuilder)
local StoreLevels = runtime:serverModule(shared.StoreLevels)

local plotCFrame = WorldBuilder.plotCFrames()[1]

-- Solid parts an NPC could bump into (ignores floor tiles and decorations).
local function solids(model)
	local list = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide and part.Transparency < 1 then
			local top = part.Position.Y + part.Size.Y / 2
			if top > plotCFrame.Position.Y + StoreLevels.FloorY + 0.35 then
				table.insert(list, part)
			end
		end
	end
	return list
end

local function blockedBy(parts, worldPoint: Vector3, radius: number)
	for _, part in parts do
		for _, height in { 0.6, 2.5, 4.5 } do
			local probe = worldPoint + Vector3.new(0, height, 0)
			local relative = part.CFrame:PointToObjectSpace(probe)
			local half = part.Size / 2
			if math.abs(relative.X) < half.X + radius and math.abs(relative.Z) < half.Z + radius and math.abs(relative.Y) < half.Y then
				return part
			end
		end
	end
	return nil
end

for level = 1, StoreLevels.MaxLevel do
	print(string.format("\n\27[1m== Store level %d: %s ==\27[0m", level, StoreLevels.getSpec(level).Name))
	local folder = Instances.new("Folder", true)
	folder.Parent = runtime.workspace
	local built = StoreBuilder.build(plotCFrame, level, roblox.Color3.new(1, 0.4, 0.4), "Tester", 1, folder)
	local layout = StoreLevels.getLayout(level)
	local parts = solids(built.Model)
	check(#parts > 10, #parts .. " solid parts found")

	-- Every waypoint link, sampled every half stud.
	local bad = {}
	local checked = {}
	for name, node in layout.Nodes do
		for _, linked in node.Links do
			local key = if name < linked then name .. "|" .. linked else linked .. "|" .. name
			if not checked[key] then
				checked[key] = true
				local a = plotCFrame:PointToWorldSpace(node.Position)
				local b = plotCFrame:PointToWorldSpace(layout.Nodes[linked].Position)
				local steps = math.max(1, math.ceil((b - a).Magnitude / 0.5))
				for i = 0, steps do
					local hit = blockedBy(parts, a:Lerp(b, i / steps), NPC_RADIUS)
					if hit then
						table.insert(bad, string.format("%s -> %s hits %s", name, linked, hit:GetFullName()))
						break
					end
				end
			end
		end
	end
	check(#bad == 0, "all NPC routes are clear (" .. #bad .. " blocked)")
	for i, message in bad do
		if i <= 6 then
			print("      " .. message)
		end
	end

	-- Queue spots at the checkout.
	local queueBlocked = 0
	for index = 1, layout.QueueLength do
		if blockedBy(parts, plotCFrame:PointToWorldSpace(StoreLevels.queuePosition(layout, index)), NPC_RADIUS) then
			queueBlocked += 1
		end
	end
	check(queueBlocked == 0, "checkout queue spots are clear (" .. layout.QueueLength .. " spots)")

	-- Worker homes (up to 3 workers).
	local workerBlocked = 0
	for index = 1, 3 do
		local home = layout.WorkerHome + Vector3.new(-(index - 1) * 2.6, 0, 0)
		if blockedBy(parts, plotCFrame:PointToWorldSpace(home), NPC_RADIUS) then
			workerBlocked += 1
		end
	end
	check(workerBlocked == 0, "worker standing spots are clear")

	-- Shelves shouldn't overlap each other, walls or the till (axis-aligned footprints).
	local shelfModels = built.Model.Shelves:GetChildren()
	local overlaps = 0
	for _, shelf in shelfModels do
		local base = shelf.Base
		local footprint = Vector3.new(StoreLevels.ShelfLength, 0, StoreLevels.ShelfDepth)
		for _, part in parts do
			if not part:IsDescendantOf(shelf) and part.Position.Y - part.Size.Y / 2 < base.Position.Y + StoreLevels.ShelfHeight then
				local relative = base.CFrame:PointToObjectSpace(part.Position)
				local half = (footprint + part.Size) / 2
				if math.abs(relative.X) < half.X - 0.05 and math.abs(relative.Z) < half.Z - 0.05 then
					overlaps += 1
					print("      overlap: " .. shelf.Name .. " with " .. part:GetFullName())
				end
			end
		end
	end
	check(overlaps == 0, "shelves don't overlap anything")

	-- Owner spawn and loading bay are outside the shop and not blocked.
	local spawnWorld = (plotCFrame * layout.OwnerSpawn).Position - Vector3.new(0, 3, 0)
	check(not blockedBy(parts, spawnWorld, 1.5), "owner spawn point is clear")
	local spotsBlocked = 0
	for _, spot in StoreLevels.boxSpots() do
		if blockedBy(parts, plotCFrame:PointToWorldSpace(spot), 1.5) or StoreLevels.isInside(layout, spot, 2) then
			spotsBlocked += 1
		end
	end
	check(spotsBlocked == 0, "loading bay spots are clear of the shop")
	local Config = runtime:serverModule(shared.Config)
	check(StoreLevels.TruckStop.Z < -Config.PlotDepth / 2 - Config.SidewalkWidth, "delivery van stops in the road, off the plot")
	check(StoreLevels.CustomerSpawn.Z > -Config.PlotDepth / 2 and layout.BackZ < Config.PlotDepth / 2 - 2, "shop and customer spawn fit inside the plot")

	-- Sign faces the road: its front face normal should point towards local -Z.
	local signLook = plotCFrame:VectorToObjectSpace(built.Model.Sign.CFrame.LookVector)
	check(signLook.Z < -0.99, "store sign faces the road")

	folder:Destroy()
end

check(#Scheduler.errors == 0, "no script errors")
print(string.format("\n%d check(s) failed", failures))
process.exit(if failures == 0 then 0 else 1)
