--!nocheck
-- Geometry checks for every store level, using the real StoreBuilder output:
--   * customer/worker waypoint routes never pass through walls, shelves or the till
--   * shelves/counter don't overlap each other or the walls
--   * the owner spawn, loading bay and delivery van lane are clear of the shop
--   * props around the plot don't block the walk from the loading bay to the door
--   * drop-in mesh models (ReplicatedStorage.CustomModels) are scaled and placed correctly
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
local plotDecor = runtime.workspace.World.Plots.Plot1.Decor

-- Solid parts an NPC could bump into (ignores floor tiles and decorations).
local function solids(model)
	local list = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide and (part.Transparency < 1 or part.Name == "Collider") then
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
	-- Odd levels get the VIP look so both variants are checked.
	local vip = level % 2 == 1
	local built = StoreBuilder.build(plotCFrame, level, roblox.Color3.new(1, 0.4, 0.4), 1, folder, vip)
	local layout = StoreLevels.getLayout(level)
	local parts = solids(built.Model)
	check(#parts > 10, #parts .. " solid parts found" .. (if vip then " (VIP look)" else ""))
	-- Props around the plot (cars, benches, pallets...) count as obstacles too.
	local decorParts = solids(plotDecor)
	for _, part in decorParts do
		table.insert(parts, part)
	end

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

	-- Worker homes (up to 3 hired workers + 1 from VIP).
	local workerBlocked = 0
	for index = 1, 4 do
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

	-- The walk from every loading bay spot to the shop door is clear of props.
	local walkBlocked = {}
	local door = plotCFrame:PointToWorldSpace(layout.DoorOutside)
	for index, spot in StoreLevels.boxSpots() do
		local from = plotCFrame:PointToWorldSpace(spot)
		local steps = math.ceil((door - from).Magnitude / 0.5)
		for i = 0, steps do
			local hit = blockedBy(decorParts, from:Lerp(door, i / steps), 1.2)
			if hit then
				table.insert(walkBlocked, "spot " .. index .. " hits " .. hit:GetFullName())
				break
			end
		end
	end
	check(#decorParts >= 8, #decorParts .. " solid props around the plot")
	check(#walkBlocked == 0, "walk from the loading bay to the door is clear (" .. #walkBlocked .. " blocked)")
	for i, message in walkBlocked do
		if i <= 4 then
			print("      " .. message)
		end
	end
	local Config = runtime:serverModule(shared.Config)
	check(StoreLevels.TruckStop.Z < -Config.PlotDepth / 2 - Config.SidewalkWidth, "delivery van stops in the road, off the plot")
	check(StoreLevels.CustomerSpawn.Z > -Config.PlotDepth / 2 and layout.BackZ < Config.PlotDepth / 2 - 2, "shop and customer spawn fit inside the plot")

	-- Sign faces the road: its front face normal should point towards local -Z.
	local signLook = plotCFrame:VectorToObjectSpace(built.Model.Sign.CFrame.LookVector)
	check(signLook.Z < -0.99, "store sign faces the road")

	folder:Destroy()
end

print("\n\27[1m== Drop-in mesh models (ReplicatedStorage.CustomModels) ==\27[0m")
do
	local CFrame = require("./emulator/Datatypes").CFrame
	local ProductVisuals = runtime:serverModule(shared.ProductVisuals)
	local TruckBuilder = runtime:serverModule(server.Builders.TruckBuilder)
	local Variants = runtime:serverModule(shared.Variants)
	local custom = runtime.game.ReplicatedStorage.CustomModels
	check(custom:FindFirstChild("Products") ~= nil and custom:FindFirstChild("Props") ~= nil, "CustomModels/Products and CustomModels/Props folders exist")
	local builtInSize = ProductVisuals.build("Cola"):GetExtentsSize()

	-- Stand-in for an imported mesh: far too big, off-centre, with an invisible hitbox.
	local function standIn(name)
		local template = Instances.new("Model", true)
		template.Name = name
		local body = Instances.new("Part", true)
		body.Name = "MeshBody"
		body.Size = Vector3.new(5, 12, 5)
		body.CFrame = CFrame.new(40, 26, 7)
		body.Parent = template
		local hitbox = Instances.new("Part", true)
		hitbox.Name = "Hitbox"
		hitbox.Size = Vector3.new(5, 12, 5)
		hitbox.CFrame = CFrame.new(40, 26, 7)
		hitbox.Transparency = 1
		hitbox.Parent = template
		local script = Instances.new("Script", true)
		script.Parent = body
		return template
	end

	local colaTemplate = standIn("Cola")
	colaTemplate.Parent = custom.Products
	local cola = ProductVisuals.build("Cola")
	check(cola:FindFirstChild("MeshBody") ~= nil, "custom product model replaces the Part version")
	local box, size = cola:GetBoundingBox()
	local fits = size.X <= builtInSize.X + 0.01 and size.Y <= builtInSize.Y + 0.01 and size.Z <= builtInSize.Z + 0.01
	local fills = math.abs(size.X - builtInSize.X) < 0.01 or math.abs(size.Y - builtInSize.Y) < 0.01 or math.abs(size.Z - builtInSize.Z) < 0.01
	check(fits and fills, string.format("scaled to the shelf slot (%.2f x %.2f x %.2f)", size.X, size.Y, size.Z))
	check(math.abs(box.Position.Y - size.Y / 2) < 0.01 and math.abs(box.Position.X) < 0.01, "stands on its base at the origin")
	check(cola.MeshBody.Anchored and not cola.MeshBody.CanCollide, "custom parts are anchored and non-colliding")
	check(cola.MeshBody:FindFirstChildOfClass("Script") == nil, "scripts inside free models are removed")
	local golden = ProductVisuals.build("Cola:Golden")
	check(golden.MeshBody.Color == Variants.GoldColor and golden.Hitbox.Transparency == 1, "Golden variant recolours the mesh, hitbox stays invisible")
	local giant = ProductVisuals.build("Cola:Giant")
	check(math.abs(giant:GetExtentsSize().Y - size.Y * Variants.ById.Giant.Scale) < 0.02, "Giant variant is scaled up like the Part version")
	colaTemplate:Destroy()
	check(ProductVisuals.build("Cola"):FindFirstChild("MeshBody") == nil, "removing it brings back the Part version")

	local vanTemplate = standIn("DeliveryVan")
	vanTemplate.Parent = custom.Props
	local truck = TruckBuilder.build(roblox.Color3.new(1, 0, 0))
	local vanModel = truck.Model:FindFirstChild("DeliveryVan")
	local welded = vanModel ~= nil and not vanModel.MeshBody.Anchored and vanModel.MeshBody:FindFirstChildOfClass("WeldConstraint") ~= nil
	check(welded and truck.Root.Transparency == 1, "custom van mesh is welded to the (hidden) chassis")
	local _, vanSize = vanModel:GetBoundingBox()
	check(vanSize.Y <= 8.61 and vanSize.Z <= 16.01, "van mesh scaled to the road lane")
	vanTemplate:Destroy()
end

check(#Scheduler.errors == 0, "no script errors")
print(string.format("\n%d check(s) failed", failures))
process.exit(if failures == 0 then 0 else 1)
