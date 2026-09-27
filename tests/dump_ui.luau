--!nocheck
-- Plays the game in the emulator and dumps the player's ScreenGui layout
-- (absolute rectangles, colours, text) at interesting moments, so the UI can
-- be rendered and eyeballed outside Studio.
--
--   lune run tests/dump_ui.luau <outDir>

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instances = require("./emulator/Instances")
local Runtime = require("./emulator/Runtime")

local Vector2 = roblox.Vector2
local OUT = process.args[1] or "build/ui"
local PLACE = process.args[2] or "build/FillTheStore.rbxlx"
fs.writeDir(OUT)

local TOP_INSET = 58

local function rgb(c)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local function resolve(udim2, size)
	return Vector2.new(udim2.X.Scale * size.X + udim2.X.Offset, udim2.Y.Scale * size.Y + udim2.Y.Offset)
end

local function constrain(object, size)
	local constraint = object:FindFirstChildOfClass("UISizeConstraint")
	if constraint then
		local min, max = constraint.MinSize, constraint.MaxSize
		return Vector2.new(math.clamp(size.X, min.X, max.X), math.clamp(size.Y, min.Y, max.Y))
	end
	return size
end

local function sorted(children, byOrder)
	local list = {}
	for _, child in children do
		if child:IsA("GuiObject") and child.Visible then
			table.insert(list, child)
		end
	end
	if byOrder then
		table.sort(list, function(a, b)
			if a.LayoutOrder == b.LayoutOrder then
				return a.Name < b.Name
			end
			return a.LayoutOrder < b.LayoutOrder
		end)
	end
	return list
end

local serialize

-- Lay out children of `parent` inside a content box of size `box` (relative coords).
local function layoutChildren(parent, box, originX, originY)
	local nodes = {}
	local list = parent:FindFirstChildOfClass("UIListLayout")
	local grid = parent:FindFirstChildOfClass("UIGridLayout")
	local children = sorted(parent:GetChildren(), list ~= nil or grid ~= nil)
	if grid then
		local cell = resolve(grid.CellSize, box)
		local pad = resolve(grid.CellPadding, box)
		local perRow = math.max(1, math.floor((box.X + pad.X) / (cell.X + pad.X)))
		for index, child in children do
			local column = (index - 1) % perRow
			local row = math.floor((index - 1) / perRow)
			table.insert(nodes, serialize(child, originX + column * (cell.X + pad.X), originY + row * (cell.Y + pad.Y), cell))
		end
	elseif list then
		local padding = list.Padding.Scale * (if list.FillDirection == roblox.Enum.FillDirection.Horizontal then box.X else box.Y) + list.Padding.Offset
		local cursor = 0
		for _, child in children do
			local size = constrain(child, resolve(child.Size, box))
			local x, y
			if list.FillDirection == roblox.Enum.FillDirection.Horizontal then
				x, y = cursor, 0
				cursor += size.X + padding
			else
				x, y = 0, cursor
				cursor += size.Y + padding
				if list.HorizontalAlignment == roblox.Enum.HorizontalAlignment.Center then
					x = (box.X - size.X) / 2
				elseif list.HorizontalAlignment == roblox.Enum.HorizontalAlignment.Right then
					x = box.X - size.X
				end
			end
			table.insert(nodes, serialize(child, originX + x, originY + y, size))
		end
	else
		for _, child in children do
			local size = constrain(child, resolve(child.Size, box))
			local position = resolve(child.Position, box) - Vector2.new(child.AnchorPoint.X * size.X, child.AnchorPoint.Y * size.Y)
			table.insert(nodes, serialize(child, originX + position.X, originY + position.Y, size))
		end
	end
	return nodes
end

function serialize(object, x, y, size)
	local node = {
		class = object.ClassName,
		name = object.Name,
		x = x, y = y, w = size.X, h = size.Y,
		z = object.ZIndex,
		bg = rgb(object.BackgroundColor3),
		bgT = object.BackgroundTransparency,
		clip = object.ClipsDescendants or object:IsA("ScrollingFrame"),
	}
	local corner = object:FindFirstChildOfClass("UICorner")
	if corner then
		node.radius = corner.CornerRadius.Scale * math.min(size.X, size.Y) + corner.CornerRadius.Offset
	end
	for _, child in object:GetChildren() do
		if child:IsA("UIStroke") and child.Enabled then
			local stroke = { color = rgb(child.Color), thickness = child.Thickness, transparency = child.Transparency }
			if child.ApplyStrokeMode == roblox.Enum.ApplyStrokeMode.Border then
				node.border = stroke
			else
				node.textStroke = stroke
			end
		elseif child:IsA("UIGradient") and child.Enabled then
			local stops = {}
			for _, key in child.Color.Keypoints do
				table.insert(stops, { t = key.Time, c = rgb(key.Value) })
			end
			node.gradient = { stops = stops, rotation = child.Rotation }
		end
	end
	if object:IsA("TextLabel") or object:IsA("TextButton") then
		node.text = object.Text
		node.textColor = rgb(object.TextColor3)
		node.textT = object.TextTransparency
		node.scaled = object.TextScaled
		node.textSize = object.TextSize
		node.align = object.TextXAlignment.Name
	end
	local padding = object:FindFirstChildOfClass("UIPadding")
	local box = size
	local ox, oy = 0, 0
	if padding then
		local left = padding.PaddingLeft.Scale * size.X + padding.PaddingLeft.Offset
		local right = padding.PaddingRight.Scale * size.X + padding.PaddingRight.Offset
		local top = padding.PaddingTop.Scale * size.Y + padding.PaddingTop.Offset
		local bottom = padding.PaddingBottom.Scale * size.Y + padding.PaddingBottom.Offset
		box = Vector2.new(size.X - left - right, size.Y - top - bottom)
		ox, oy = left, top
		node.pad = { left, top, right, bottom }
	end
	node.children = layoutChildren(object, box, ox, oy)
	return node
end

local function dumpGui(runtime, player, name, viewport)
	viewport = viewport or Vector2.new(1280, 720)
	Instances.setInternal(runtime.camera, "ViewportSize", viewport)
	Instances.fire(runtime.camera, "Prop:ViewportSize")
	runtime:run(0.1)
	local gui = player.PlayerGui.FillTheStoreUI
	local scale = gui:FindFirstChildOfClass("UIScale")
	local s = if scale then scale.Scale else 1
	local area = Vector2.new(viewport.X / s, (viewport.Y - TOP_INSET) / s)
	local tree = {
		viewport = { viewport.X, viewport.Y },
		inset = TOP_INSET,
		scale = s,
		children = layoutChildren(gui, area, 0, 0),
	}
	fs.writeFile(OUT .. "/" .. name .. ".json", serde.encode("json", tree))
	print("dumped " .. name .. string.format(" (scale %.2f)", s))
end

-- Play -----------------------------------------------------------------------------------

local runtime = Runtime.new({ placePath = PLACE, placeId = 0 })
runtime:startServer()
runtime:run(0.5)
local player = runtime:addPlayer("Isaac", 1001, true)
runtime:run(2.5)
dumpGui(runtime, player, "1-join")

local services = runtime.game.ServerScriptService.Server.Services
local PlayerData = runtime:serverModule(services.PlayerData)
local Registry = runtime:serverModule(services.Registry)

-- Delivery arrives (banner) — capture while the banner is on screen.
runtime:runUntil(15, function()
	local notifications = player.PlayerGui.FillTheStoreUI.Notifications
	for _, child in notifications:GetChildren() do
		if child:IsA("Frame") then
			return true
		end
	end
	return false
end)
runtime:run(0.5)
local session = Registry.session(player)
local shared = runtime.game.ReplicatedStorage.Shared
local Remotes = runtime:serverModule(shared.Remotes)
Remotes.event("Notify"):FireClient(player, "Rare", "✨ RAINBOW COLA!")
runtime:run(0.5)
dumpGui(runtime, player, "2-delivery-banners")

-- Grab a box, carry it in, open it (card).
runtime:run(3)
local box
for _, model in session.PlotModel.Boxes:GetChildren() do
	if model.Box:FindFirstChild("BoxPrompt") then
		box = model.Box
		break
	end
end
runtime:walkTo(player, box.Position + roblox.Vector3.new(0, 0, 2.5), 20)
runtime:trigger(player, box.BoxPrompt)
runtime:run(0.3)
dumpGui(runtime, player, "3-carrying")
local layout = session.Store.Layout
for _, p in { layout.DoorOutside, layout.DoorInside, roblox.Vector3.new(0, 0, layout.FrontZ + 6) } do
	runtime:walkTo(player, session.PlotCFrame:PointToWorldSpace(p), 15)
end
runtime:run(0.3)
runtime:trigger(player, session.Carried.Root.OpenBoxPrompt)
runtime:run(1.2)
dumpGui(runtime, player, "4-box-opened")

-- Give some variety, open the stock menu.
PlayerData.addCash(player, 1234)
for _, key in { "Cola:Golden", "Water:Rainbow", "Chocolate:Giant", "Crisps", "Cereal", "EnergyDrink" } do
	PlayerData.addItem(player, key, 5)
end
runtime:run(3)
local gui = player.PlayerGui.FillTheStoreUI
runtime:click(gui.Buttons.STOCK)
runtime:run(0.6)
dumpGui(runtime, player, "5-stock-menu")
runtime:click(gui.Buttons.UPGRADES)
runtime:run(0.6)
dumpGui(runtime, player, "6-upgrades-menu")
dumpGui(runtime, player, "7-upgrades-phone", Vector2.new(844, 390))
runtime:click(gui:FindFirstChild("⬆️ UPGRADES").Header.Close)
runtime:run(0.5)
dumpGui(runtime, player, "8-hud-phone", Vector2.new(844, 390))
