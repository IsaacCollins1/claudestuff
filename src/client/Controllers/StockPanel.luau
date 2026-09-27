--!strict
-- PRODUCTS / STOCK menu: what's in the stock room. Tapping a product makes
-- it the first thing put on shelves.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Items = require(Shared:WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Products = require(Shared:WaitForChild("Products"))

local SoundPlayer = require(script.Parent.SoundPlayer)
local State = require(script.Parent.State)
local UIKit = require(script.Parent.UIKit)
local Window = require(script.Parent.Window)

local Colors = UIKit.Colors

local StockPanel = {}

local window: Window.Window
local grid: ScrollingFrame
local emptyLabel: TextLabel

local VARIANT_BACKGROUNDS: { [string]: Color3 } = {
	Normal = Color3.fromRGB(58, 62, 90),
	Golden = Color3.fromRGB(255, 196, 37),
	Rainbow = Color3.fromRGB(255, 255, 255),
	Giant = Color3.fromRGB(60, 200, 140),
}

local function select(productId: string)
	local data = State.Data
	local current = data and data.SelectedProduct
	Remotes.event("SelectProduct"):FireServer(if current == productId then nil else productId)
	SoundPlayer.play("Click")
end

local function tile(key: string, count: number, selected: boolean, order: number)
	local product = Items.product(key)
	local variant = Items.variant(key)
	local button = UIKit.button(grid, {
		Name = key,
		BackgroundColor3 = VARIANT_BACKGROUNDS[variant.Id] or VARIANT_BACKGROUNDS.Normal,
		Text = "",
		LayoutOrder = order,
		ZIndex = 22,
	}, function()
		select(product.Id)
	end)
	if variant.Id == "Rainbow" then
		UIKit.new("UIGradient", { Color = UIKit.rainbow(), Rotation = 45 }, button)
	end
	local rarityColor = Products.Rarities[product.Rarity].Color
	UIKit.stroke(button, if selected then Colors.Yellow else rarityColor, if selected then 5 else 3)
	UIKit.label(button, product.Icon, { Size = UDim2.new(1, 0, 0.46, 0), Position = UDim2.fromScale(0, 0.06), ZIndex = 23 })
	local name = UIKit.label(button, Items.displayName(key), {
		Size = UDim2.new(0.92, 0, 0.18, 0),
		Position = UDim2.fromScale(0.04, 0.54),
		ZIndex = 23,
	})
	UIKit.textStroke(name, Colors.Dark, 2)
	local amount = UIKit.label(button, "x" .. count, {
		Size = UDim2.new(0.9, 0, 0.2, 0),
		Position = UDim2.fromScale(0.05, 0.75),
		TextColor3 = Colors.Yellow,
		ZIndex = 23,
	})
	UIKit.textStroke(amount, Colors.Dark, 2)
	if selected then
		UIKit.label(button, "⭐", {
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.fromOffset(4, 4),
			ZIndex = 24,
		})
	end
end

local function refresh()
	local data = State.Data
	if not data then
		return
	end
	for _, child in grid:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local keys = {}
	local total = 0
	local value = 0
	for key, count in data.Inventory do
		if Items.isValid(key) and count > 0 then
			table.insert(keys, key)
			total += count
			value += Items.sellPrice(key) * count
		end
	end
	table.sort(keys, Items.compare)
	for order, key in keys do
		local productId = Items.product(key).Id
		tile(key, data.Inventory[key], productId == data.SelectedProduct, order)
	end
	emptyLabel.Visible = #keys == 0
	window.Subtitle.Text = if #keys == 0
		then "Your stock room is empty"
		else `{total} items · worth {Format.money(value)} · tap one to stock it first`
end

function StockPanel.init(screen: ScreenGui)
	window = Window.new(screen, "📦 STOCK", Colors.Blue, Colors.BlueDark)
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
		CellSize = UDim2.fromOffset(118, 122),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	UIKit.padding(grid, 6)
	emptyLabel = UIKit.label(window.Content, "No stock yet!\n📦 Grab a delivery box and open it inside your shop.", {
		Size = UDim2.new(1, -40, 0, 90),
		Position = UDim2.fromOffset(20, 60),
		TextColor3 = Color3.fromRGB(200, 205, 225),
		ZIndex = 23,
		Visible = false,
	})
	window.OnOpen = refresh
	State.Changed:Connect(function()
		if window:IsOpen() then
			refresh()
		end
	end)
end

function StockPanel.toggle()
	Window.toggle(window)
end

return StockPanel
