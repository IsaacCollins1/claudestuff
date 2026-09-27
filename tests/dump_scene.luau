--!nocheck
-- Plays the game in the emulator and dumps the 3D scene (parts, surface text,
-- billboards) to JSON so it can be rendered for a visual check outside Studio.
--
--   lune run tests/dump_scene.luau <outDir>

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instances = require("./emulator/Instances")
local Runtime = require("./emulator/Runtime")

local Vector3 = roblox.Vector3
local OUT = process.args[1] or "build/scenes"
local PLACE = process.args[2] or "build/FillTheStore.rbxlx"
fs.writeDir(OUT)

local function color(c)
	return { c.R, c.G, c.B }
end

local function labelsIn(gui)
	local labels = {}
	for _, d in gui:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and d.Visible then
			-- Resolve scale-only position relative to the gui (good enough for signs).
			local x, y, w, h = 0, 0, 1, 1
			local chain = {}
			local node = d
			while node and node ~= gui do
				table.insert(chain, 1, node)
				node = node.Parent
			end
			for _, n in chain do
				if n:IsA("GuiObject") then
					local px, py = n.Position.X.Scale, n.Position.Y.Scale
					local sx, sy = n.Size.X.Scale, n.Size.Y.Scale
					x, y = x + px * w - n.AnchorPoint.X * sx * w, y + py * h - n.AnchorPoint.Y * sy * h
					w, h = sx * w, sy * h
				end
			end
			local stroke = d:FindFirstChildOfClass("UIStroke")
			table.insert(labels, {
				text = d.Text,
				x = x, y = y, w = w, h = h,
				color = color(d.TextColor3),
				stroke = if stroke then color(stroke.Color) else nil,
			})
		end
	end
	return labels
end

local function dump(runtime, name: string, cameras)
	local parts, surfaces, billboards = {}, {}, {}
	for _, d in runtime.workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.98 then
			local shape = "Block"
			if d.ClassName == "Part" or d.ClassName == "SpawnLocation" then
				shape = d.Shape.Name
			elseif d.ClassName == "WedgePart" then
				shape = "Wedge"
			end
			local mesh = d:FindFirstChildOfClass("SpecialMesh")
			if mesh and mesh.MeshType == roblox.Enum.MeshType.Head then
				shape = "Head"
			end
			local size = d.Size
			table.insert(parts, {
				n = d.Name,
				s = shape,
				sz = { size.X, size.Y, size.Z },
				cf = { d.CFrame:GetComponents() },
				c = color(d.Color),
				t = d.Transparency,
				m = d.Material.Name,
				r = d.Reflectance,
				face = d:FindFirstChild("face") ~= nil,
			})
			for _, child in d:GetChildren() do
				if child:IsA("SurfaceGui") and child.Enabled then
					table.insert(surfaces, { p = #parts - 1, face = child.Face.Name, labels = labelsIn(child) })
				end
			end
		elseif d:IsA("BillboardGui") and d.Enabled then
			local adornee = d.Adornee or d.Parent
			local position
			if adornee and adornee:IsA("BasePart") then
				position = adornee.Position
			elseif adornee and adornee:IsA("Attachment") then
				position = adornee.WorldPosition
			end
			if position then
				position += d.StudsOffsetWorldSpace
				table.insert(billboards, {
					pos = { position.X, position.Y, position.Z },
					w = d.Size.X.Scale,
					h = d.Size.Y.Scale,
					labels = labelsIn(d),
				})
			end
		end
	end
	local cameraList = {}
	for cameraName, camera in cameras do
		table.insert(cameraList, {
			name = cameraName,
			pos = { camera[1].X, camera[1].Y, camera[1].Z },
			target = { camera[2].X, camera[2].Y, camera[2].Z },
			fov = camera[3] or 60,
		})
	end
	fs.writeFile(OUT .. "/" .. name .. ".json", serde.encode("json", {
		parts = parts,
		surfaces = surfaces,
		billboards = billboards,
		cameras = cameraList,
	}))
	print(string.format("%s: %d parts, %d surface guis, %d billboards", name, #parts, #surfaces, #billboards))
end

-- Play ---------------------------------------------------------------------------------

local runtime = Runtime.new({ placePath = PLACE, placeId = 0 })
runtime:startServer()
runtime:run(0.5)
local player = runtime:addPlayer("Isaac", 1001, true)
runtime:run(1)

local services = runtime.game.ServerScriptService.Server.Services
local PlayerData = runtime:serverModule(services.PlayerData)
local Registry = runtime:serverModule(services.Registry)
local Shelves = runtime:serverModule(services.Shelves)
local StoreLevels = runtime:serverModule(runtime.game.ReplicatedStorage.Shared.StoreLevels)
local UpgradeService = runtime:serverModule(services.UpgradeService)

local function session()
	return Registry.session(player)
end
local function toWorld(v)
	return session().PlotCFrame:PointToWorldSpace(v)
end

-- Carry the first box inside and open it, then stock both shelves.
local function playLoop(seconds)
	local start = runtime.game.Workspace:GetServerTimeNow()
	while runtime.game.Workspace:GetServerTimeNow() - start < seconds do
		local s = session()
		local layout = s.Store.Layout
		if player:GetAttribute("CarryingBox") then
			for _, p in { layout.DoorOutside, layout.DoorInside, Vector3.new(0, 0, layout.FrontZ + 6) } do
				runtime:walkTo(player, toWorld(p), 15)
			end
			runtime:run(0.3)
			runtime:trigger(player, s.Carried.Root.OpenBoxPrompt)
		elseif PlayerData.inventoryTotal(player) > 0 then
			local node = "Door"
			for _, shelf in s.Store.Shelves do
				if Shelves.free(shelf) > 0 and PlayerData.inventoryTotal(player) > 0 then
					for _, p in StoreLevels.findPath(layout, node, shelf.Node) do
						runtime:walkTo(player, toWorld(p), 15)
					end
					node = shelf.Node
					runtime:run(0.3)
					runtime:trigger(player, shelf.Model.Base.PromptAttachment.StockPrompt)
					runtime:runUntil(6, function()
						return not shelf.Busy
					end)
				end
			end
			runtime:run(1)
		else
			local boxes = s.PlotModel:FindFirstChild("Boxes")
			local picked = false
			for _, box in if boxes then boxes:GetChildren() else {} do
				if box.Box:FindFirstChild("BoxPrompt") then
					runtime:walkTo(player, box.Box.Position + Vector3.new(0, 0, 2.5), 20)
					runtime:trigger(player, box.Box.BoxPrompt)
					picked = true
					break
				end
			end
			if not picked then
				runtime:run(1)
			end
		end
	end
end

local function cameras()
	local s = session()
	local layout = s.Store.Layout
	local depth = layout.Depth
	return {
		overview = { toWorld(Vector3.new(-30, 55, -60)), toWorld(Vector3.new(8, 0, layout.FrontZ + 4)), 55 },
		front = { toWorld(Vector3.new(10, 9, layout.FrontZ - 26)), toWorld(Vector3.new(0, 5, layout.FrontZ + depth / 2)), 60 },
		inside = { toWorld(Vector3.new(layout.Width / 2 - 2, 14, layout.FrontZ + 1)), toWorld(Vector3.new(-4, 1, layout.BackZ - 4)), 70 },
		bay = { toWorld(Vector3.new(0, 16, -58)), toWorld(Vector3.new(24, 0, -38)), 60 },
		street = { Vector3.new(-60, 30, -10), Vector3.new(60, 0, 30), 65 },
	}
end

-- Scene 1: first minute, starter shop, van arriving.
playLoop(45)
runtime:runUntil(30, function()
	local van = session().PlotModel:FindFirstChild("DeliveryVan")
	return van ~= nil and (van.Chassis.Position - toWorld(StoreLevels.TruckStop)).Magnitude < 3
end)
runtime:run(0.5)
dump(runtime, "level1", cameras())

-- Scene 2: expanded to a Local Store with more shelf capacity.
PlayerData.addCash(player, 20000)
for _, id in { "StoreSize", "ShelfCapacity", "ShelfCapacity", "ShelfCapacity", "CustomerRate", "CustomerRate" } do
	UpgradeService.buy(player, id)
	runtime:run(0.3)
end
for _, key in { "Cola", "Water", "Crisps", "Cereal", "Pizza", "Headphones", "Cola:Golden", "Water:Rainbow", "Chocolate:Giant" } do
	PlayerData.addItem(player, key, if string.find(key, ":") then 2 else 20)
end
playLoop(40)
dump(runtime, "level2", cameras())

-- Scene 3: mini supermarket with workers and a neighbour.
PlayerData.addCash(player, 100000)
for _, id in { "StoreSize", "Workers", "Workers", "ShelfCapacity", "ShelfCapacity", "CustomerRate", "CustomerRate" } do
	UpgradeService.buy(player, id)
	runtime:run(0.3)
end
for _, key in { "Smartphone", "Console", "Laptop", "Television", "ToiletRoll", "Cleaning", "EnergyDrink", "Chocolate", "Television:Golden", "Laptop:Rainbow" } do
	PlayerData.addItem(player, key, if string.find(key, ":") then 2 else 25)
end
runtime:addPlayer("Bob", 2002, false)
playLoop(60)
dump(runtime, "level3", cameras())
print("parts created:", Instances.created)
