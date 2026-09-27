--!strict
-- 🛍️ Robux shop: cash packs, boosts and game passes.
-- Items with a real ID use Roblox's purchase prompt. Items whose ID is still 0
-- can be test-bought for free in Studio (the server double-checks it's Studio).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Monetization = require(Shared:WaitForChild("Monetization"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local SoundPlayer = require(script.Parent.SoundPlayer)
local State = require(script.Parent.State)
local UIKit = require(script.Parent.UIKit)
local Window = require(script.Parent.Window)

local Colors = UIKit.Colors
local player = Players.LocalPlayer

local ShopPanel = {}

type Card = {
	Frame: Frame,
	Amount: TextLabel?,
	Buy: UIKit.Chunky,
	Price: UIKit.RobuxPrice,
	Tag: Frame,
	Kind: string,
	Key: string,
}

local window: Window.Window
local body: Frame
local pages: { [string]: ScrollingFrame } = {}
local cards: { Card } = {}
local prices: { [number]: number } = {}

local TABS: { Window.Tab } = {
	{ Key = "Cash", Text = "💰 CASH", Color = Colors.Green },
	{ Key = "Boosts", Text = "⚡ BOOSTS", Color = Colors.Orange },
	{ Key = "Passes", Text = "👑 PASSES", Color = Colors.Purple },
}

local function isStudio(): boolean
	local data = State.Data
	return data ~= nil and data.IsStudio == true
end

-- The Roblox ID for a shop item (0 until it's set up in Shared/Monetization).
local function itemId(kind: string, key: string): number
	if kind == "Pass" then
		return Monetization.Passes[key].Id
	end
	return Monetization.Products[key].Id
end

-- The real Robux price once it has been fetched, else the catalogue's number.
local function priceOf(id: number, fallback: number): number
	return prices[id] or fallback
end

-- Fetch real prices for configured items (once).
local function loadPrices()
	for _, product in Monetization.Products do
		if product.Id ~= 0 and not prices[product.Id] then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(product.Id, Enum.InfoType.Product)
				end)
				if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
					prices[product.Id] = info.PriceInRobux
				end
			end)
		end
	end
	for _, pass in Monetization.Passes do
		if pass.Id ~= 0 and not prices[pass.Id] then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(pass.Id, Enum.InfoType.GamePass)
				end)
				if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
					prices[pass.Id] = info.PriceInRobux
				end
			end)
		end
	end
end

local function purchase(kind: string, key: string)
	SoundPlayer.play("Click")
	local id = itemId(kind, key)
	if id ~= 0 then
		if kind == "Pass" then
			MarketplaceService:PromptGamePassPurchase(player, id)
		else
			MarketplaceService:PromptProductPurchase(player, id)
		end
		return
	end
	if not isStudio() then
		window.Subtitle.Text = "This item isn't for sale yet"
		return
	end
	local ok, success, message = pcall(function()
		return Remotes.func("TestPurchase"):InvokeServer(kind, key)
	end)
	if ok and success then
		SoundPlayer.play("Purchase")
		window.Subtitle.Text = "✅ " .. tostring(message)
	else
		SoundPlayer.play("Error")
		window.Subtitle.Text = "⚠️ " .. tostring(if ok then message else success)
	end
end

local function card(parent: Instance, kind: string, key: string, order: number, icon: string, name: string, description: string, color: Color3): Card
	local frame = UIKit.new("Frame", {
		Name = key,
		BackgroundColor3 = color,
		LayoutOrder = order,
		ZIndex = 22,
	}, parent)
	UIKit.corner(frame, UDim.new(0, 20))
	UIKit.stroke(frame, Colors.Outline, 4)
	UIKit.gradient(frame, Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 165))
	local glow = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 52),
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = Colors.White,
		BackgroundTransparency = 0.6,
		ZIndex = 23,
	}, frame)
	UIKit.corner(glow, UDim.new(1, 0))
	local iconLabel = UIKit.label(glow, icon, { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), ZIndex = 24 })
	UIKit.wobble(iconLabel, 6)
	UIKit.title(frame, string.upper(name), {
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, 98),
		ZIndex = 23,
	}, UIKit.darken(color, 0.6), 2.5)
	local amount: TextLabel? = nil
	if kind == "Product" and Monetization.Products[key].Kind == "Cash" then
		amount = UIKit.title(frame, "+£0", {
			Size = UDim2.new(1, -16, 0, 26),
			Position = UDim2.fromOffset(8, 126),
			TextColor3 = Colors.Yellow,
			ZIndex = 23,
		}, Colors.Outline, 2.5)
	else
		local about = UIKit.label(frame, description, {
			Size = UDim2.new(1, -20, 0, 34),
			Position = UDim2.fromOffset(10, 125),
			TextColor3 = Colors.White,
			TextWrapped = true,
			ZIndex = 23,
		})
		UIKit.textStroke(about, UIKit.darken(color, 0.6), 1.5)
	end
	local buy = UIKit.chunky(frame, {
		Name = "Buy",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -24, 0, 50),
		Color = Colors.Green,
		ZIndex = 24,
	}, function()
		purchase(kind, key)
	end)
	-- Robux logo + price on the button.
	local price = UIKit.robuxPrice(buy.Face, 26, Colors.Outline, 28)
	-- "TEST" sticker for items without a real ID yet (only shown in Studio).
	local tag = UIKit.new("Frame", {
		Name = "TestTag",
		Position = UDim2.fromOffset(-6, -8),
		Size = UDim2.fromOffset(64, 24),
		BackgroundColor3 = Colors.Red,
		Rotation = -12,
		Visible = false,
		ZIndex = 26,
	}, frame)
	UIKit.corner(tag, UDim.new(1, 0))
	UIKit.stroke(tag, Colors.Outline, 2)
	UIKit.title(tag, "TEST", { Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), ZIndex = 27 }, Colors.Outline, 1.5)
	return { Frame = frame, Amount = amount, Buy = buy, Price = price, Tag = tag, Kind = kind, Key = key }
end

local function page(name: string): ScrollingFrame
	local scroll = UIKit.new("ScrollingFrame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Colors.Grey,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
		ZIndex = 22,
	}, body)
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(176, 216),
		CellPadding = UDim2.fromOffset(14, 14),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, scroll)
	UIKit.padding(scroll, 10)
	pages[name] = scroll
	return scroll
end

local function refresh()
	local data = State.Data
	local studio = isStudio()
	for _, entry in cards do
		local id = itemId(entry.Kind, entry.Key)
		entry.Tag.Visible = studio and id == 0
		if id == 0 and not studio then
			-- Not set up for real purchases yet.
			entry.Buy.SetColor(Colors.GreyDark)
			entry.Price.Set(nil, "SOON")
		elseif entry.Kind == "Pass" then
			local pass = Monetization.Passes[entry.Key]
			if State.hasPass(entry.Key) then
				entry.Buy.SetColor(Colors.GreyDark)
				entry.Price.Set(nil, "OWNED ✔")
			else
				entry.Buy.SetColor(Colors.Green)
				entry.Price.Set(priceOf(pass.Id, pass.Robux))
			end
		else
			local product = Monetization.Products[entry.Key]
			entry.Price.Set(priceOf(product.Id, product.Robux))
			if entry.Amount and data then
				entry.Amount.Text = "+" .. Format.money(Monetization.cashAmount(product, data.TotalEarned))
			end
		end
	end
	if window.Subtitle.Text == "" then
		window.Subtitle.Text = if isStudio() then "Studio: TEST items are free to try" else "Thanks for supporting the game!"
	end
end

function ShopPanel.init(screen: ScreenGui)
	-- Wide enough for four cards in a row (all the passes on one screen).
	window = Window.new(screen, { Title = "SHOP", Icon = "🛍️", Color = Colors.Gold, Width = 820, Height = 500 })
	body = Window.tabs(window, TABS, function(key: string)
		for name, scroll in pages do
			scroll.Visible = name == key
		end
	end)
	local cashPage = page("Cash")
	local boostPage = page("Boosts")
	local passPage = page("Passes")
	for order, key in Monetization.ProductOrder do
		local product = Monetization.Products[key]
		local parent = if product.Kind == "Cash" then cashPage else boostPage
		table.insert(cards, card(parent, "Product", key, order, product.Icon, product.Name, product.Description, product.Color))
	end
	for order, key in Monetization.PassOrder do
		local pass = Monetization.Passes[key]
		table.insert(cards, card(passPage, "Pass", key, order, pass.Icon, pass.Name, pass.Description, pass.Color))
	end
	window.OnOpen = function()
		window.Subtitle.Text = ""
		loadPrices()
		refresh()
	end
	State.Changed:Connect(function()
		if window:IsOpen() then
			refresh()
		end
	end)
	local select = window.SelectTab
	if select then
		select("Cash")
	end
end

function ShopPanel.open(tab: string?)
	if not window:IsOpen() then
		window:Open()
	end
	local select = window.SelectTab
	if tab and select then
		select(tab)
	end
end

function ShopPanel.toggle()
	Window.toggle(window)
end

return ShopPanel
