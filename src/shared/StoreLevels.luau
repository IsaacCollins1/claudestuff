--!strict
-- Store expansion levels and the geometry/navigation layout for each one.
--
-- Everything here is in PLOT-LOCAL coordinates:
--   * X runs along the road, Y is up (0 = top of the plot pad)
--   * -Z is the front of the plot (towards the road), +Z is the back
--   * the plot spans Z = -40 (pavement) .. 40 (back fence)
-- The shop front stays in the same place at every level; expanding the shop
-- makes it wider and deeper towards the back, so walks never get longer.
-- The server converts to world space with `plotCFrame * localCFrame`.
--
-- Shelves are listed per level. Customers and workers move along a small
-- waypoint graph (door -> central aisle "spine" -> shelf/checkout), which keeps
-- NPC movement predictable without runtime pathfinding.

local StoreLevels = {}

-- Shared dimensions ---------------------------------------------------------
StoreLevels.FrontZ = -4 -- inner face of the front wall (same for every level)
StoreLevels.FloorY = 0.2 -- top of the store floor
StoreLevels.WallHeight = 10
StoreLevels.WallThickness = 1
StoreLevels.DoorWidth = 8
StoreLevels.DoorHeight = 8

StoreLevels.ShelfLength = 8
StoreLevels.ShelfDepth = 2.4
StoreLevels.ShelfHeight = 6.2
StoreLevels.ShelfAccessGap = 2.6 -- how far in front of a shelf NPCs stand

StoreLevels.CounterSize = Vector3.new(2.5, 3.2, 7)

-- Plot features that don't change with store level
StoreLevels.LoadingPadCenter = Vector3.new(27, 0, -26)
StoreLevels.LoadingPadSize = Vector2.new(26, 20)
StoreLevels.TruckStop = Vector3.new(27, 0, -55) -- in the road lane in front of the plot
StoreLevels.CustomerSpawn = Vector3.new(-3, 0, -38)

-- FromBack = distance from the back wall's inner face to the shelf centre.
export type ShelfSpec = { X: number, FromBack: number }

export type LevelSpec = {
	Level: number,
	Name: string,
	Width: number,
	Depth: number,
	MaxItemsPerCustomer: number,
	Shelves: { ShelfSpec },
}

local BACK_ROW = StoreLevels.ShelfDepth / 2 + 0.2 -- shelves against the back wall

StoreLevels.Levels = {
	{
		Level = 1,
		Name = "Corner Shop",
		Width = 30,
		Depth = 24,
		MaxItemsPerCustomer = 2,
		Shelves = {
			{ X = -6.5, FromBack = BACK_ROW },
			{ X = 6.5, FromBack = BACK_ROW },
		},
	},
	{
		Level = 2,
		Name = "Local Store",
		Width = 42,
		Depth = 32,
		MaxItemsPerCustomer = 3,
		Shelves = {
			{ X = -9, FromBack = BACK_ROW },
			{ X = 9, FromBack = BACK_ROW },
			{ X = -10, FromBack = 15 },
			{ X = 10, FromBack = 15 },
		},
	},
	{
		Level = 3,
		Name = "Mini Supermarket",
		Width = 56,
		Depth = 40,
		MaxItemsPerCustomer = 4,
		Shelves = {
			{ X = -18, FromBack = BACK_ROW },
			{ X = -6, FromBack = BACK_ROW },
			{ X = 6, FromBack = BACK_ROW },
			{ X = 18, FromBack = BACK_ROW },
			{ X = -20, FromBack = 14 },
			{ X = -10, FromBack = 14 },
			{ X = 10, FromBack = 14 },
			{ X = 20, FromBack = 14 },
			{ X = -10, FromBack = 26 },
			{ X = 10, FromBack = 26 },
		},
	},
} :: { LevelSpec }

StoreLevels.MaxLevel = #StoreLevels.Levels

export type NavNode = {
	Name: string,
	Position: Vector3,
	Links: { string },
}

export type Layout = {
	Spec: LevelSpec,
	Level: number,
	Width: number,
	Depth: number,
	FrontZ: number,
	BackZ: number,
	InteriorCenter: Vector3,
	InteriorSize: Vector3,
	ShelfCFrames: { CFrame },
	ShelfNodes: { string },
	CounterCFrame: CFrame,
	CheckoutPoint: Vector3,
	CheckoutNode: string,
	QueueStep: Vector3,
	QueueLength: number,
	DoorInside: Vector3,
	DoorOutside: Vector3,
	WorkerHome: Vector3,
	OwnerSpawn: CFrame,
	SignCFrame: CFrame,
	Nodes: { [string]: NavNode },
}

local layoutCache: { [number]: Layout } = {}

local function addNode(nodes: { [string]: NavNode }, name: string, position: Vector3)
	if not nodes[name] then
		nodes[name] = { Name = name, Position = position, Links = {} }
	end
end

local function link(nodes: { [string]: NavNode }, a: string, b: string)
	table.insert(nodes[a].Links, b)
	table.insert(nodes[b].Links, a)
end

local function spineName(z: number): string
	return string.format("Spine%.2f", z)
end

function StoreLevels.getSpec(level: number): LevelSpec
	return StoreLevels.Levels[math.clamp(level, 1, #StoreLevels.Levels)]
end

function StoreLevels.getLayout(level: number): Layout
	local spec = StoreLevels.getSpec(level)
	local cached = layoutCache[spec.Level]
	if cached then
		return cached
	end

	local frontZ = StoreLevels.FrontZ
	local backZ = frontZ + spec.Depth
	local halfWidth = spec.Width / 2
	local floorY = StoreLevels.FloorY

	local nodes: { [string]: NavNode } = {}
	local spineZs: { number } = {}
	local function addSpine(z: number)
		if not table.find(spineZs, z) then
			table.insert(spineZs, z)
		end
	end

	-- Shelves: all face the front of the store (-Z) so they read clearly from the door.
	local shelfCFrames = {}
	local shelfNodes = {}
	local function shelfZ(shelf: ShelfSpec): number
		return backZ - shelf.FromBack
	end
	for index, shelf in spec.Shelves do
		table.insert(shelfCFrames, CFrame.new(shelf.X, floorY, shelfZ(shelf)))
		local accessZ = shelfZ(shelf) - StoreLevels.ShelfDepth / 2 - StoreLevels.ShelfAccessGap
		local name = "Shelf" .. index
		addNode(nodes, name, Vector3.new(shelf.X, floorY, accessZ))
		addSpine(accessZ)
		table.insert(shelfNodes, name)
	end

	-- Checkout counter on the front-left, customers queue towards the centre aisle.
	local counterZ = frontZ + 7
	local counterX = -halfWidth + 4
	local counterCFrame = CFrame.new(counterX, floorY, counterZ)
	local checkoutX = counterX + StoreLevels.CounterSize.X / 2 + 2
	local checkoutPoint = Vector3.new(checkoutX, floorY, counterZ)
	addNode(nodes, "Checkout", checkoutPoint)
	addSpine(counterZ)
	local queueStep = Vector3.new(2.6, 0, 0)
	local queueLength = math.max(1, math.floor((-checkoutX - 1.5) / queueStep.X) + 1)

	-- Door, outside and the customer spawn on the pavement.
	local doorInside = Vector3.new(0, floorY, frontZ + 2.5)
	local doorOutside = Vector3.new(0, 0, frontZ - 4)
	addNode(nodes, "Door", doorInside)
	addNode(nodes, "Outside", doorOutside)
	addNode(nodes, "Spawn", StoreLevels.CustomerSpawn)
	link(nodes, "Spawn", "Outside")
	link(nodes, "Outside", "Door")

	-- Central aisle ("spine") from the door to the back of the shop.
	table.sort(spineZs)
	local previous = "Door"
	for _, z in spineZs do
		local name = spineName(z)
		addNode(nodes, name, Vector3.new(0, floorY, z))
		link(nodes, previous, name)
		previous = name
	end
	for index, shelf in spec.Shelves do
		local accessZ = shelfZ(shelf) - StoreLevels.ShelfDepth / 2 - StoreLevels.ShelfAccessGap
		link(nodes, spineName(accessZ), "Shelf" .. index)
	end
	link(nodes, spineName(counterZ), "Checkout")

	-- Workers wait in the front-right corner.
	local workerHome = Vector3.new(halfWidth - 4, floorY, frontZ + 4)
	addNode(nodes, "WorkerHome", workerHome)
	link(nodes, "WorkerHome", "Door")

	local padCenter = StoreLevels.LoadingPadCenter
	local ownerSpawnPosition = Vector3.new(5, 3, frontZ - 12)
	local ownerSpawn = CFrame.lookAt(ownerSpawnPosition, Vector3.new(padCenter.X, 3, padCenter.Z))

	local layout: Layout = {
		Spec = spec,
		Level = spec.Level,
		Width = spec.Width,
		Depth = spec.Depth,
		FrontZ = frontZ,
		BackZ = backZ,
		InteriorCenter = Vector3.new(0, StoreLevels.WallHeight / 2, frontZ + spec.Depth / 2),
		InteriorSize = Vector3.new(spec.Width, StoreLevels.WallHeight, spec.Depth),
		ShelfCFrames = shelfCFrames,
		ShelfNodes = shelfNodes,
		CounterCFrame = counterCFrame,
		CheckoutPoint = checkoutPoint,
		CheckoutNode = "Checkout",
		QueueStep = queueStep,
		QueueLength = queueLength,
		DoorInside = doorInside,
		DoorOutside = doorOutside,
		WorkerHome = workerHome,
		OwnerSpawn = ownerSpawn,
		SignCFrame = CFrame.new(0, StoreLevels.WallHeight + 2.8, frontZ - 0.6),
		Nodes = nodes,
	}
	layoutCache[spec.Level] = layout
	return layout
end

-- Shortest route between two waypoint nodes (Dijkstra; graphs are tiny).
-- Returns the list of positions to walk through, excluding the start node.
function StoreLevels.findPath(layout: Layout, from: string, to: string): { Vector3 }
	local nodes = layout.Nodes
	assert(nodes[from] and nodes[to], `Unknown nav node {from} -> {to}`)

	local dist: { [string]: number } = { [from] = 0 }
	local previous: { [string]: string } = {}
	local visited: { [string]: boolean } = {}

	while true do
		local current: string? = nil
		local best = math.huge
		for name, d in dist do
			if not visited[name] and d < best then
				best = d
				current = name
			end
		end
		if current == nil or current == to then
			break
		end
		visited[current] = true
		local node = nodes[current]
		for _, neighbour in node.Links do
			local candidate = best + (nodes[neighbour].Position - node.Position).Magnitude
			if candidate < (dist[neighbour] or math.huge) then
				dist[neighbour] = candidate
				previous[neighbour] = current
			end
		end
	end

	local path = {}
	local step: string? = to
	while step and step ~= from do
		table.insert(path, 1, nodes[step].Position)
		step = previous[step]
	end
	if step ~= from then
		return { nodes[to].Position } -- disconnected; walk straight there
	end
	return path
end

-- Position of the Nth customer in the checkout queue (1 = at the till).
function StoreLevels.queuePosition(layout: Layout, index: number): Vector3
	local clamped = math.clamp(index, 1, layout.QueueLength)
	return layout.CheckoutPoint + layout.QueueStep * (clamped - 1)
end

-- Is a plot-local point inside the store walls?
function StoreLevels.isInside(layout: Layout, localPoint: Vector3, margin: number?): boolean
	local m = margin or 0
	local half = layout.Width / 2 + m
	return math.abs(localPoint.X) <= half
		and localPoint.Z >= layout.FrontZ - m
		and localPoint.Z <= layout.BackZ + m
		and localPoint.Y > -5
		and localPoint.Y < StoreLevels.WallHeight + 10
end

-- The 12 spots on the loading pad where delivery boxes land.
function StoreLevels.boxSpots(): { Vector3 }
	local spots = {}
	local center = StoreLevels.LoadingPadCenter
	for row = 0, 2 do
		for column = 0, 3 do
			table.insert(spots, center + Vector3.new(-7.5 + column * 5, 0, -6 + row * 6))
		end
	end
	return spots
end

return StoreLevels
