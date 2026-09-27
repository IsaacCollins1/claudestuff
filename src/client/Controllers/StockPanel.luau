--!strict
-- STOCK menu: everything in your stock room, shown as spinning 3D products.
-- Tapping a product makes it the first thing put on shelves.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Items = require(Shared:WaitForChild("Items"))
local ProductVisuals = require(Shared:WaitForChild("ProductVisuals"))
local Products = require(Shared:WaitForChild("Products"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local SoundPlayer = require(script.Parent.SoundPlayer)
local State = require(script.Parent.State)
local UIKit = require(script.Parent.UIKit)
local Window = require(script.Parent.Window)

local Colors = UIKit.Colors

local StockPanel = {}

type Tile = {
	Button: TextButton,
	Count: TextLabel,
	Stroke: UIStroke,
	Star: TextLabel,
	Model: Model,
	Spin: number,
}

local window: Window.Window
local grid: ScrollingFrame
local emptyLabel: TextLabel
local tiles: { [string]: Tile } = {}

local VARIANT_STYLE: { [string]: { Color: Color3, Tag: string? } } = {
	Normal = { Color = Color3.fromRGB(62, 67, 100), Tag = nil },
	Golden = { Color = Color3.fromRGB(255, 196, 37), Tag = "GOLDEN" },
	Rainbow = { Color = Color3.fromRGB(255, 255, 255), Tag = "RAINBOW" },
	Giant = { Color = Color3.fromRGB(60, 200, 140), Tag = "GIANT" },
}

local function select(productId: string)
	local data = State.Data
	local current = data and data.SelectedProduct
	Remotes.event("SelectProduct"):FireServer(if current == productId then nil else productId)
	SoundPlayer.play("Click")
end

-- A small 3D preview of the product in a ViewportFrame.
local function preview(parent: Instance, key: string): Model
	local viewport = UIKit.new("ViewportFrame", {
		Name = "Preview",
		Size = UDim2.new(1, -16, 0.6, 0),
		Position = UDim2.fromOffset(8, 6),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(190, 190, 200),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
		ZIndex = 24,
	}, parent)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local model = ProductVisuals.build(key)
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	local center, size = model:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z) * 0.62
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2))
	local target = center.Position
	camera.CFrame = CFrame.lookAt(target + Vector3.new(0, radius * 0.45, -distance), target)
	return model
end

local function makeTile(key: string): Tile
	local product = Items.product(key)
	local variant = Items.variant(key)
	local style = VARIANT_STYLE[variant.Id] or VARIANT_STYLE.Normal
	local button = UIKit.new("TextButton", {
		Name = key,
		BackgroundColor3 = style.Color,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 22,
	}, grid)
	UIKit.corner(button, UDim.new(0, 18))
	if variant.Id == "Rainbow" then
		UIKit.new("UIGradient", { Color = UIKit.rainbow(), Rotation = 45 }, button)
	else
		UIKit.gradient(button, Color3.fromRGB(255, 255, 255), Color3.fromRGB(185, 185, 200))
	end
	local stroke = UIKit.stroke(button, Products.Rarities[product.Rarity].Color, 3)
	local model = preview(button, key)
	UIKit.title(button, Items.displayName(key), {
		Size = UDim2.new(0.9, 0, 0, 22),
		Position = UDim2.new(0.05, 0, 0.64, 0),
		ZIndex = 24,
	}, Colors.Outline, 2)
	local count = UIKit.title(button, "x0", {
		Size = UDim2.new(0.9, 0, 0, 26),
		Position = UDim2.new(0.05, 0, 0.8, 0),
		TextColor3 = Colors.Yellow,
		ZIndex = 24,
	}, Colors.Outline, 2)
	if style.Tag then
		local tag = UIKit.new("Frame", {
			Size = UDim2.fromOffset(80, 22),
			Position = UDim2.new(1, -84, 0, 6),
			BackgroundColor3 = UIKit.darken(style.Color, 0.35),
			ZIndex = 25,
		}, button)
		UIKit.corner(tag, UDim.new(1, 0))
		UIKit.title(tag, style.Tag, { Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), ZIndex = 26 }, Colors.Outline, 1.5)
	end
	local star = UIKit.label(button, "⭐", {
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(6, 6),
		ZIndex = 26,
		Visible = false,
	})
	local scale = UIKit.scaleOf(button)
	button.MouseEnter:Connect(function()
		UIKit.tween(scale, 0.15, { Scale = 1.05 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		UIKit.tween(scale, 0.15, { Scale = 1 })
	end)
	button.Activated:Connect(function()
		UIKit.pop(button, 0.08)
		select(product.Id)
	end)
	return { Button = button, Count = count, Stroke = stroke, Star = star, Model = model, Spin = math.random() * 6 }
end

local function refresh()
	local data = State.Data
	if not data then
		return
	end
	local keys = {}
	local total, value = 0, 0
	for key, count in data.Inventory do
		if Items.isValid(key) and count > 0 then
			table.insert(keys, key)
			total += count
			value += Items.sellPrice(key) * count
		end
	end
	table.sort(keys, Items.compare)
	local present: { [string]: boolean } = {}
	for order, key in keys do
		present[key] = true
		local existing = tiles[key]
		local tile: Tile
		if existing then
			tile = existing
		else
			tile = makeTile(key)
			tiles[key] = tile
			UIKit.popIn(tile.Button)
		end
		tile.Button.LayoutOrder = order
		tile.Count.Text = "x" .. Format.commas(data.Inventory[key])
		local selected = Items.product(key).Id == data.SelectedProduct
		tile.Star.Visible = selected
		tile.Stroke.Color = if selected then Colors.Yellow else Products.Rarities[Items.product(key).Rarity].Color
		tile.Stroke.Thickness = if selected then 5 else 3
	end
	for key, tile in tiles do
		if not present[key] then
			tile.Button:Destroy()
			tiles[key] = nil
		end
	end
	emptyLabel.Visible = #keys == 0
	window.Subtitle.Text = if #keys == 0
		then "Your stock room is empty"
		else `{Format.commas(total)} items · worth {Format.money(value)} · tap one to shelve it first`
end

function StockPanel.init(screen: ScreenGui)
	window = Window.new(screen, { Title = "STOCK", Icon = "📦", Color = Colors.Blue })
	grid = UIKit.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Colors.Grey,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 22,
	}, window.Content)
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(132, 150),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, grid)
	UIKit.padding(grid, 8)
	emptyLabel = UIKit.title(window.Content, "NO STOCK YET!\n📦 Grab a box from the loading bay", {
		Size = UDim2.new(1, -60, 0, 110),
		Position = UDim2.fromOffset(30, 90),
		TextColor3 = Color3.fromRGB(220, 225, 245),
		ZIndex = 23,
		Visible = false,
	}, Colors.Outline, 2)
	window.OnOpen = refresh
	State.Changed:Connect(function()
		if window:IsOpen() then
			refresh()
		end
	end)
	-- Slowly spin the products while the menu is open.
	RunService.RenderStepped:Connect(function(dt: number)
		if not window:IsOpen() then
			return
		end
		for _, tile in tiles do
			tile.Spin += dt * 1.2
			tile.Model:PivotTo(CFrame.Angles(0, tile.Spin, 0))
		end
	end)
end

function StockPanel.toggle()
	Window.toggle(window)
end

return StockPanel
