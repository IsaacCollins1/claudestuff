--!strict
-- The always-on simulator HUD:
--   * top-left: cash (with a "+" to buy more), store value and level / XP
--   * left: big chunky SHOP / UPGRADE / STOCK / TOP / ITEMS / REBIRTH buttons
--   * top-centre: delivery timer with a progress bar
--   * top-right: active boosts and owned passes
--   * bottom: a short hint when there's something to do
-- Coins fly from sales in the world straight into the cash counter.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Monetization = require(Shared:WaitForChild("Monetization"))
local Progression = require(Shared:WaitForChild("Progression"))
local Signal = require(Shared:WaitForChild("Signal"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))

local SoundPlayer = require(script.Parent.SoundPlayer)
local State = require(script.Parent.State)
local UIKit = require(script.Parent.UIKit)
local Window = require(script.Parent.Window)

local Colors = UIKit.Colors
local player = Players.LocalPlayer

local HUD = {}

HUD.UpgradesPressed = Signal.new() :: Signal.Signal<>
HUD.StockPressed = Signal.new() :: Signal.Signal<>
HUD.ShopPressed = Signal.new() :: Signal.Signal<string?>
HUD.LeadersPressed = Signal.new() :: Signal.Signal<>
HUD.UnlocksPressed = Signal.new() :: Signal.Signal<>
HUD.RebirthPressed = Signal.new() :: Signal.Signal<>

local screen: ScreenGui
local cashPill: Frame
local cashCoin: Frame
local cashLabel: TextLabel
local valueLabel: TextLabel
local deliveryPill: Frame
local deliveryLabel: TextLabel
local deliveryBar: Frame
local hintPill: Frame
local hintLabel: TextLabel
local stockBadge: Frame
local stockBadgeLabel: TextLabel
local upgradesAlert: Frame
local rebirthAlert: Frame
local levelPill: Frame
local levelBadgeLabel: TextLabel
local levelFill: Frame
local levelText: TextLabel
local shownLevel = 0
local boostsColumn: Frame
local buttons: { [string]: UIKit.Chunky } = {}

local displayedCash = 0
local targetCash = 0
local currentHint: string? = nil
local tutorialActive = false
local lastDeliveryInterval = Config.DeliveryIntervalMax

local CASH_ICON_CENTER = Vector2.new(14 + 30, 10 + 30)

-- Cash + value ------------------------------------------------------------------

local function buildCurrency()
	cashPill = UIKit.pill(screen, {
		Name = "Cash",
		Position = UDim2.fromOffset(40, 16),
		Size = UDim2.fromOffset(250, 52),
	})
	cashLabel = UIKit.title(cashPill, "£0", {
		Name = "Amount",
		Position = UDim2.fromOffset(34, 7),
		Size = UDim2.new(1, -94, 1, -14),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Colors.Outline, 3)
	cashCoin = UIKit.coin(screen, 60, { Position = UDim2.fromOffset(14, 10), ZIndex = 3 })
	local plus = UIKit.chunky(cashPill, {
		Name = "BuyCash",
		Size = UDim2.fromOffset(46, 46),
		Position = UDim2.new(1, -52, 0, 2),
		Color = Colors.Green,
		Text = "+",
		Depth = 5,
		ZIndex = 4,
	}, function()
		SoundPlayer.play("Click")
		HUD.ShopPressed:Fire("Cash")
	end)
	plus.Button.Name = "BuyCash"

	local valuePill = UIKit.pill(screen, {
		Name = "Value",
		Position = UDim2.fromOffset(40, 76),
		Size = UDim2.fromOffset(200, 36),
		BackgroundTransparency = 0.3,
	})
	valueLabel = UIKit.title(valuePill, "⭐ £0", {
		Position = UDim2.fromOffset(16, 5),
		Size = UDim2.new(1, -28, 1, -10),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 225, 120),
	}, Colors.Outline, 2)
end

-- Level / XP bar ------------------------------------------------------------------

local function buildLevel()
	levelPill = UIKit.pill(screen, {
		Name = "Level",
		Position = UDim2.fromOffset(40, 118),
		Size = UDim2.fromOffset(200, 30),
		BackgroundTransparency = 0.2,
	})
	local track = UIKit.new("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(26, 7),
		Size = UDim2.new(1, -36, 1, -14),
		BackgroundColor3 = Colors.Dark,
		ZIndex = 2,
	}, levelPill)
	UIKit.corner(track, UDim.new(1, 0))
	levelFill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Purple,
		ZIndex = 3,
	}, track)
	UIKit.corner(levelFill, UDim.new(1, 0))
	UIKit.gradient(levelFill, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 170, 255))
	levelText = UIKit.title(levelPill, "0 / 30 XP", {
		Name = "Xp",
		Position = UDim2.fromOffset(26, 3),
		Size = UDim2.new(1, -36, 1, -6),
		ZIndex = 4,
	}, Colors.Outline, 2)
	-- Round level badge on the left, like the cash coin.
	local badge = UIKit.new("Frame", {
		Name = "LevelBadge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(40, 133),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = Colors.Purple,
		ZIndex = 5,
	}, screen)
	UIKit.corner(badge, UDim.new(1, 0))
	UIKit.stroke(badge, Colors.Outline, 3)
	UIKit.gradient(badge, Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 160, 240))
	UIKit.title(badge, "LV", {
		Position = UDim2.fromOffset(6, 3),
		Size = UDim2.new(1, -12, 0, 12),
		ZIndex = 6,
	}, Colors.PurpleDark, 1.5)
	levelBadgeLabel = UIKit.title(badge, "1", {
		Name = "Number",
		Position = UDim2.fromOffset(4, 14),
		Size = UDim2.new(1, -8, 0, 24),
		ZIndex = 6,
	}, Colors.PurpleDark, 2)
	-- Tap the bar to see what unlocks next.
	local hit = UIKit.new("TextButton", {
		Name = "Open",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 7,
	}, levelPill)
	hit.Activated:Connect(function()
		SoundPlayer.play("Click")
		HUD.UnlocksPressed:Fire()
	end)
end

local function refreshLevel()
	local data = State.Data
	if not data or not data.Level then
		return
	end
	local needed = Progression.xpToNext(data.Level)
	local fraction = if data.Level >= Progression.MaxLevel then 1 else math.clamp(data.Xp / needed, 0, 1)
	UIKit.tween(levelFill, 0.3, { Size = UDim2.fromScale(fraction, 1) })
	levelText.Text = if data.Level >= Progression.MaxLevel then "MAX LEVEL" else `{Format.commas(data.Xp)} / {Format.commas(needed)} XP`
	levelBadgeLabel.Text = tostring(data.Level)
	if shownLevel ~= 0 and data.Level > shownLevel then
		UIKit.pop(levelPill, 0.2)
	end
	shownLevel = data.Level
end

-- Button grid -------------------------------------------------------------------

local function bigButton(name: string, icon: string, text: string, color: Color3, order: number, onClick: () -> ()): UIKit.Chunky
	local column = (order - 1) % 2
	local row = math.floor((order - 1) / 2)
	local chunky = UIKit.chunky(screen, {
		Name = name,
		Size = UDim2.fromOffset(92, 92),
		-- From the top (not the middle) so it never slides under the level bar on phones.
		Position = UDim2.fromOffset(14 + column * 104, 168 + row * 108),
		Color = color,
		Icon = icon,
		Text = text,
		Radius = UDim.new(0, 18),
		Depth = 8,
	}, function()
		SoundPlayer.play("Click")
		onClick()
	end)
	buttons[name] = chunky
	return chunky
end

local function buildButtons()
	local shop = bigButton("Shop", "🛍️", "SHOP", Colors.Gold, 1, function()
		HUD.ShopPressed:Fire(nil)
	end)
	UIKit.shine(shop.Face, UDim.new(0, 18), 2.5)
	UIKit.wobble(shop.Button, 3)
	-- Robux logo badge: the shop is where Robux purchases live.
	local robuxBadge = UIKit.new("Frame", {
		Name = "RobuxBadge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = Colors.Green,
		ZIndex = 20,
	}, shop.Button)
	UIKit.corner(robuxBadge, UDim.new(1, 0))
	UIKit.stroke(robuxBadge, Colors.White, 3)
	UIKit.robuxIcon(robuxBadge, 22, { Position = UDim2.fromOffset(5, 5), ZIndex = 21 })
	local upgrades = bigButton("Upgrades", "⬆️", "UPGRADE", Colors.Green, 2, function()
		HUD.UpgradesPressed:Fire()
	end)
	local stock = bigButton("Stock", "📦", "STOCK", Colors.Blue, 3, function()
		HUD.StockPressed:Fire()
	end)
	bigButton("Leaders", "🏆", "TOP", Colors.Purple, 4, function()
		HUD.LeadersPressed:Fire()
	end)
	bigButton("Unlocks", "📖", "ITEMS", Colors.Blue:Lerp(Colors.Purple, 0.5), 5, function()
		HUD.UnlocksPressed:Fire()
	end)
	local rebirth = bigButton("Rebirth", "🔁", "REBIRTH", Colors.Pink, 6, function()
		HUD.RebirthPressed:Fire()
	end)
	stockBadge, stockBadgeLabel = UIKit.badge(stock.Button, Colors.Red, "0")
	upgradesAlert = UIKit.badge(upgrades.Button, Colors.Yellow, "!")
	rebirthAlert = UIKit.badge(rebirth.Button, Colors.Yellow, "!")
end

-- Delivery timer -------------------------------------------------------------------

local function buildDelivery()
	deliveryPill = UIKit.pill(screen, {
		Name = "Delivery",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(290, 46),
	})
	deliveryLabel = UIKit.title(deliveryPill, "🚚 DELIVERY SOON", {
		Size = UDim2.new(1, -30, 0, 26),
		Position = UDim2.fromOffset(15, 5),
	}, Colors.Outline, 2)
	local track = UIKit.new("Frame", {
		Size = UDim2.new(1, -40, 0, 7),
		Position = UDim2.new(0, 20, 1, -12),
		BackgroundColor3 = Color3.fromRGB(12, 12, 20),
	}, deliveryPill)
	UIKit.corner(track, UDim.new(1, 0))
	deliveryBar = UIKit.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Orange,
	}, track)
	UIKit.corner(deliveryBar, UDim.new(1, 0))
end

function HUD.refreshDelivery()
	local menuOpen = Window.isAnyOpen()
	deliveryPill.Visible = not menuOpen
	hintPill.Visible = currentHint ~= nil and not menuOpen and not tutorialActive

	local waiting = 0
	for _, box in CollectionService:GetTagged("DeliveryBox") do
		local root = box:FindFirstChild("Box")
		if box:GetAttribute("OwnerUserId") == player.UserId and root and root:FindFirstChild("BoxPrompt") then
			waiting += 1
		end
	end
	local nextAt = player:GetAttribute("NextDeliveryAt")
	local remaining = if type(nextAt) == "number" then math.max(0, nextAt - workspace:GetServerTimeNow()) else 0
	if remaining > lastDeliveryInterval then
		lastDeliveryInterval = remaining
	end
	deliveryBar.Size = UDim2.fromScale(1 - remaining / math.max(lastDeliveryInterval, 1), 1)
	if waiting > 0 then
		deliveryLabel.Text = `📦 {waiting} BOX{if waiting == 1 then "" else "ES"} WAITING!`
		deliveryLabel.TextColor3 = Colors.Yellow
	elseif remaining > 0.5 then
		deliveryLabel.Text = `🚚 NEXT DELIVERY {math.ceil(remaining)}s`
		deliveryLabel.TextColor3 = Colors.White
	else
		deliveryLabel.Text = "🚚 DELIVERY ARRIVING!"
		deliveryLabel.TextColor3 = Colors.Orange
		lastDeliveryInterval = Config.DeliveryIntervalMin
	end
end

-- Boosts / passes -----------------------------------------------------------------

local function buildBoosts()
	boostsColumn = UIKit.new("Frame", {
		Name = "Boosts",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(210, 260),
		BackgroundTransparency = 1,
	}, screen)
	UIKit.new("UIListLayout", {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, boostsColumn)
end

local function refreshBoosts()
	for _, child in boostsColumn:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local order = 0
	for _, key in Monetization.ProductOrder do
		local product = Monetization.Products[key]
		local remaining = State.boostRemaining(key)
		if product.Kind == "Boost" and remaining > 0 then
			order += 1
			local chip = UIKit.pill(boostsColumn, {
				Name = key,
				Size = UDim2.fromOffset(200, 40),
				BackgroundColor3 = UIKit.darken(product.Color, 0.35),
				LayoutOrder = order,
			})
			local minutes = math.floor(remaining / 60)
			UIKit.title(chip, `{product.Icon} {minutes}:{string.format("%02d", math.floor(remaining % 60))}`, {
				Size = UDim2.new(1, -20, 1, -10),
				Position = UDim2.fromOffset(10, 5),
			}, Colors.Outline, 2)
		end
	end
	local owned = {}
	for _, key in Monetization.PassOrder do
		if State.hasPass(key) then
			table.insert(owned, Monetization.Passes[key].Icon)
		end
	end
	if #owned > 0 then
		order += 1
		local chip = UIKit.pill(boostsColumn, {
			Name = "Passes",
			Size = UDim2.fromOffset(40 + #owned * 34, 40),
			LayoutOrder = order,
		})
		UIKit.label(chip, table.concat(owned, " "), {
			Size = UDim2.new(1, -16, 1, -10),
			Position = UDim2.fromOffset(8, 5),
		})
	end
end

-- Hint -----------------------------------------------------------------------------

local function buildHint()
	hintPill = UIKit.pill(screen, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(460, 56),
		Visible = false,
	})
	UIKit.stroke(hintPill, Colors.Yellow, 3)
	hintLabel = UIKit.title(hintPill, "", {
		Size = UDim2.new(1, -36, 1, -16),
		Position = UDim2.fromOffset(18, 8),
	}, Colors.Outline, 2)
end

function HUD.setHint(text: string?)
	if text == currentHint then
		return
	end
	currentHint = text
	if text then
		hintLabel.Text = text
		hintPill.Visible = not Window.isAnyOpen() and not tutorialActive
		UIKit.pop(hintPill, 0.12)
	else
		hintPill.Visible = false
	end
end

function HUD.setTutorialActive(active: boolean)
	tutorialActive = active
end

-- Badges -----------------------------------------------------------------------------

function HUD.refreshBadges()
	local total = State.inventoryTotal()
	stockBadge.Visible = total > 0
	stockBadgeLabel.Text = if total > 999 then "999+" else tostring(total)

	local data = State.Data
	local affordable = false
	if data then
		for id, def in Upgrades.Defs do
			local cost = Upgrades.getCost(id, data.Upgrades[id] or def.StartLevel)
			if cost and cost <= data.Cash then
				affordable = true
				break
			end
		end
		valueLabel.Text = "⭐ " .. Format.money(data.StoreValue)
	end
	if affordable and not upgradesAlert.Visible then
		UIKit.pop(buttons.Upgrades.Button, 0.2)
	end
	upgradesAlert.Visible = affordable

	local canRebirth = data ~= nil and data.Rebirths ~= nil and data.Cash >= Progression.rebirthCost(data.Rebirths)
	if canRebirth and not rebirthAlert.Visible then
		UIKit.pop(buttons.Rebirth.Button, 0.25)
	end
	rebirthAlert.Visible = canRebirth
	refreshLevel()
end

function HUD.pulseUpgrades()
	UIKit.pop(buttons.Upgrades.Button, 0.18)
end

function HUD.button(name: string): GuiButton?
	local chunky = buttons[name]
	return chunky and chunky.Button
end

-- Coins flying into the counter ------------------------------------------------------------

local function uiScale(): number
	local scale = screen:FindFirstChildOfClass("UIScale")
	return if scale then scale.Scale else 1
end

-- World position -> position in the (unscaled) HUD coordinate space.
function HUD.worldToGui(position: Vector3): Vector2?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local point, onScreen = camera:WorldToViewportPoint(position)
	if not onScreen then
		return nil
	end
	local inset = GuiService:GetGuiInset()
	local s = uiScale()
	return Vector2.new(point.X / s, (point.Y - inset.Y) / s)
end

function HUD.flyCoinsFrom(start: Vector2, amount: number)
	local count = math.clamp(math.floor(math.log10(math.max(amount, 1)) * 2) + 2, 3, 10)
	for index = 1, count do
		task.delay((index - 1) * 0.05, function()
			local coin = UIKit.coin(screen, 30, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(start.X, start.Y),
				ZIndex = 50,
			})
			local scatter = start + Vector2.new(math.random(-60, 60), math.random(-70, -20))
			UIKit.tween(coin, 0.25, { Position = UDim2.fromOffset(scatter.X, scatter.Y) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.wait(0.25)
			UIKit.tween(coin, 0.45, {
				Position = UDim2.fromOffset(CASH_ICON_CENTER.X, CASH_ICON_CENTER.Y),
				Size = UDim2.fromOffset(20, 20),
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(0.45)
			coin:Destroy()
			UIKit.pop(cashCoin, 0.25)
			SoundPlayer.play("Coin", 1 + index * 0.05, nil, 0.03)
		end)
	end
end

function HUD.flyCoins(worldPosition: Vector3, amount: number)
	local start = HUD.worldToGui(worldPosition)
	if start then
		HUD.flyCoinsFrom(start, amount)
	end
end

-- "+£24" next to the counter.
local function floatCash(amount: number)
	UIKit.pop(cashPill, 0.06)
	local label = UIKit.title(screen, "+" .. Format.money(amount), {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(300, 42),
		Size = UDim2.fromOffset(170, 34),
		TextColor3 = Colors.Green,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 30,
	}, Colors.Outline, 3)
	UIKit.tween(label, 1, { Position = UDim2.fromOffset(300, 8), TextTransparency = 1 })
	task.delay(1.05, function()
		label:Destroy()
	end)
end

-- Init -------------------------------------------------------------------------------

function HUD.init(gui: ScreenGui)
	screen = gui
	buildCurrency()
	buildLevel()
	buildButtons()
	buildDelivery()
	buildBoosts()
	buildHint()

	State.Changed:Connect(function(data, previous)
		targetCash = data.Cash
		if previous == nil then
			displayedCash = data.Cash
		elseif data.Cash > previous.Cash then
			floatCash(data.Cash - previous.Cash)
		end
		HUD.refreshBadges()
		refreshBoosts()
	end)
	if State.Data then
		targetCash = State.Data.Cash
		displayedCash = targetCash
	end

	RunService.RenderStepped:Connect(function(dt: number)
		if math.abs(targetCash - displayedCash) < 0.5 then
			displayedCash = targetCash
		else
			displayedCash += (targetCash - displayedCash) * math.min(1, dt * 8)
		end
		cashLabel.Text = Format.money(math.floor(displayedCash + 0.5))
	end)

	task.spawn(function()
		local ticks = 0
		while true do
			HUD.refreshDelivery()
			ticks += 1
			if ticks % 4 == 0 then
				refreshBoosts()
			end
			task.wait(0.25)
		end
	end)
end

return HUD
