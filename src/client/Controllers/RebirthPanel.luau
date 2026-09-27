--!strict
-- 🔁 REBIRTH menu.
--   * Rebirth tab: what you have, what the next rebirth gives, how close you
--     are, what you keep and what resets, and a REBIRTH button that asks you
--     to tap again to confirm.
--   * Perks tab: spend Rebirth Tokens (🔷) on permanent perks.
-- The server does the actual rebirth; this also plays the celebration.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Progression = require(Shared:WaitForChild("Progression"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Effects = require(script.Parent.Effects)
local SoundPlayer = require(script.Parent.SoundPlayer)
local State = require(script.Parent.State)
local UIKit = require(script.Parent.UIKit)
local Window = require(script.Parent.Window)

local Colors = UIKit.Colors
local TOKEN = "🔷"

local RebirthPanel = {}

type StatCard = { Frame: Frame, Value: TextLabel }
type PerkRow = {
	Frame: Frame,
	Level: TextLabel,
	Effect: TextLabel,
	Pips: { Frame },
	Buy: UIKit.Chunky,
	Color: Color3,
}

local screen: ScreenGui
local window: Window.Window
local pages: { [string]: GuiObject } = {}
local rebirthsCard: StatCard
local bonusCard: StatCard
local tokensCard: StatCard
local progressFill: Frame
local progressLabel: TextLabel
local rebirthButton: UIKit.Chunky
local perkRows: { [string]: PerkRow } = {}
local confirming = false
local confirmToken = 0
local busy = false

local TABS: { Window.Tab } = {
	{ Key = "Rebirth", Text = "🔁 REBIRTH", Color = Colors.Pink },
	{ Key = "Perks", Text = TOKEN .. " PERKS", Color = Colors.Blue },
}

local function statCard(parent: Instance, name: string, title: string, color: Color3, x: number): StatCard
	local frame = UIKit.new("Frame", {
		Name = name,
		Position = UDim2.new(x, 6, 0, 0),
		Size = UDim2.new(1 / 3, -12, 0, 92),
		BackgroundColor3 = color,
		ZIndex = 23,
	}, parent)
	UIKit.corner(frame, UDim.new(0, 18))
	UIKit.stroke(frame, Colors.Outline, 3)
	UIKit.gradient(frame, Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 185))
	UIKit.title(frame, title, {
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 8),
		ZIndex = 24,
	}, UIKit.darken(color, 0.55), 2)
	local value = UIKit.title(frame, "0", {
		Name = "Value",
		Size = UDim2.new(1, -16, 0, 46),
		Position = UDim2.fromOffset(8, 36),
		ZIndex = 24,
	}, Colors.Outline, 3)
	return { Frame = frame, Value = value }
end

local function listBox(parent: Instance, title: string, lines: { string }, color: Color3, x: number)
	local frame = UIKit.new("Frame", {
		Position = UDim2.new(x, 6, 0, 150),
		Size = UDim2.new(0.5, -12, 0, 104),
		BackgroundColor3 = UIKit.darken(color, 0.55),
		BackgroundTransparency = 0.2,
		ZIndex = 23,
	}, parent)
	UIKit.corner(frame, UDim.new(0, 14))
	UIKit.stroke(frame, color, 2)
	UIKit.title(frame, title, {
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 6),
		TextColor3 = color,
		ZIndex = 24,
	}, Colors.Outline, 2)
	UIKit.label(frame, table.concat(lines, "\n"), {
		Size = UDim2.new(1, -20, 1, -36),
		Position = UDim2.fromOffset(10, 30),
		TextColor3 = Colors.White,
		TextWrapped = true,
		ZIndex = 24,
	})
end

local function resetConfirm()
	confirming = false
	confirmToken += 1
end

local function refreshRebirth()
	local data = State.Data
	if not data or data.Rebirths == nil then
		return
	end
	local cost = Progression.rebirthCost(data.Rebirths)
	local now = Progression.rebirthMultiplier(data.Rebirths)
	local after = Progression.rebirthMultiplier(data.Rebirths + 1)
	rebirthsCard.Value.Text = `🔁 {data.Rebirths}`
	bonusCard.Value.Text = `x{now} ➜ x{after}`
	tokensCard.Value.Text = `{TOKEN} {data.RebirthTokens}`
	local fraction = math.clamp(data.Cash / cost, 0, 1)
	UIKit.tween(progressFill, 0.3, { Size = UDim2.fromScale(fraction, 1) })
	progressLabel.Text = `{Format.money(data.Cash)} / {Format.money(cost)}`
	local label = rebirthButton.Text
	local affordable = data.Cash >= cost
	local tokens = Progression.tokensFor(data.Rebirths + 1)
	if not affordable then
		resetConfirm()
		rebirthButton.SetColor(Colors.GreyDark)
		if label then
			label.Text = `NEED {Format.money(cost)}`
		end
	elseif confirming then
		rebirthButton.SetColor(Colors.Red)
		if label then
			label.Text = "TAP AGAIN TO CONFIRM!"
		end
	else
		rebirthButton.SetColor(Colors.Pink)
		if label then
			label.Text = `REBIRTH!  +{tokens} {TOKEN}`
		end
	end
end

local function refreshPerks()
	local data = State.Data
	if not data or data.RebirthPerks == nil then
		return
	end
	for id, row in perkRows do
		local def = Progression.Perks[id]
		local level = data.RebirthPerks[id] or 0
		local maxLevel = #def.Costs
		local cost = Progression.perkCost(id, level)
		row.Level.Text = `LV {level}/{maxLevel}`
		for index, pip in row.Pips do
			pip.BackgroundColor3 = if index <= level then row.Color else Color3.fromRGB(30, 32, 48)
		end
		local label = row.Buy.Text
		if cost then
			row.Effect.Text = if level == 0 then `➜ {def.Effect(1)}` else `{def.Effect(level)}  ➜  {def.Effect(level + 1)}`
			row.Buy.SetColor(if data.RebirthTokens >= cost then Colors.Blue else Colors.GreyDark)
			if label then
				label.Text = `{TOKEN} {cost}`
			end
		else
			row.Effect.Text = def.Effect(level)
			row.Buy.SetColor(Colors.Gold)
			if label then
				label.Text = "MAX"
			end
		end
	end
end

local function refresh()
	local data = State.Data
	if not data or data.Rebirths == nil then
		return
	end
	refreshRebirth()
	refreshPerks()
	if window.Subtitle.Text == "" or string.find(window.Subtitle.Text, TOKEN, 1, true) then
		window.Subtitle.Text = `You have {data.RebirthTokens} {TOKEN} Rebirth Token{if data.RebirthTokens == 1 then "" else "s"}`
	end
end

local function doRebirth()
	local data = State.Data
	if busy or not data or data.Cash < Progression.rebirthCost(data.Rebirths) then
		SoundPlayer.play("Error")
		UIKit.shake(rebirthButton.Button)
		return
	end
	if not confirming then
		-- First tap: ask to confirm (and cancel by itself after a few seconds).
		confirming = true
		confirmToken += 1
		local token = confirmToken
		SoundPlayer.play("Click", 0.8)
		refreshRebirth()
		task.delay(4, function()
			if confirmToken == token then
				resetConfirm()
				refreshRebirth()
			end
		end)
		return
	end
	resetConfirm()
	busy = true
	local ok, success, message = pcall(function()
		return Remotes.func("Rebirth"):InvokeServer()
	end)
	busy = false
	if ok and success then
		window:Close()
	else
		SoundPlayer.play("Error")
		window.Subtitle.Text = "⚠️ " .. tostring(if ok then message else success)
		refreshRebirth()
	end
end

local function buildRebirthPage(page: Frame)
	rebirthsCard = statCard(page, "Rebirths", "REBIRTHS", Colors.Pink, 0)
	bonusCard = statCard(page, "Bonus", "CASH BONUS", Colors.Green, 1 / 3)
	tokensCard = statCard(page, "Tokens", "TOKENS", Colors.Blue, 2 / 3)

	local track = UIKit.new("Frame", {
		Name = "Progress",
		Position = UDim2.new(0, 6, 0, 104),
		Size = UDim2.new(1, -12, 0, 34),
		BackgroundColor3 = Colors.Dark,
		ZIndex = 23,
	}, page)
	UIKit.corner(track, UDim.new(1, 0))
	UIKit.stroke(track, Colors.Outline, 3)
	progressFill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Pink,
		ZIndex = 24,
	}, track)
	UIKit.corner(progressFill, UDim.new(1, 0))
	UIKit.gradient(progressFill, Color3.fromRGB(255, 255, 255), Color3.fromRGB(230, 170, 200))
	progressLabel = UIKit.title(track, "£0 / £0", {
		Name = "Amount",
		Size = UDim2.new(1, -20, 1, -8),
		Position = UDim2.fromOffset(10, 4),
		ZIndex = 25,
	}, Colors.Outline, 2.5)

	listBox(page, "✔ YOU KEEP", { "Level & unlocked items", "⭐ Product stars", "🔷 Tokens & perks", "Game passes" }, Colors.Green, 0)
	listBox(page, "✖ RESETS", { "Cash", "Upgrades", "Shop size", "Stock & shelves" }, Colors.Red, 0.5)

	rebirthButton = UIKit.chunky(page, {
		Name = "RebirthButton",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 266),
		Size = UDim2.fromOffset(400, 66),
		Color = Colors.Pink,
		Text = "REBIRTH!",
		ZIndex = 24,
		MaxTextSize = 34,
	}, doRebirth)
	UIKit.shine(rebirthButton.Face, UDim.new(0, 14), 2.5)
end

local function buyPerk(id: string, row: PerkRow)
	if busy then
		return
	end
	busy = true
	local ok, success, message = pcall(function()
		return Remotes.func("BuyRebirthPerk"):InvokeServer(id)
	end)
	busy = false
	if ok and success then
		SoundPlayer.play("Upgrade")
		UIKit.pop(row.Frame, 0.08)
		window.Subtitle.Text = "✅ " .. tostring(message)
	else
		SoundPlayer.play("Error")
		UIKit.shake(row.Buy.Button)
		window.Subtitle.Text = "⚠️ " .. tostring(if ok then message else success)
	end
end

local function perkRow(parent: Instance, id: string, order: number): PerkRow
	local def = Progression.Perks[id]
	local frame = UIKit.new("Frame", {
		Name = id,
		Size = UDim2.new(1, -12, 0, 92),
		BackgroundColor3 = Colors.PanelLight,
		LayoutOrder = order,
		ZIndex = 22,
	}, parent)
	UIKit.corner(frame, UDim.new(0, 18))
	UIKit.stroke(frame, Colors.Outline, 3)
	local tile = UIKit.new("Frame", {
		Size = UDim2.fromOffset(72, 72),
		Position = UDim2.fromOffset(10, 8),
		BackgroundColor3 = def.Color,
		ZIndex = 23,
	}, frame)
	UIKit.corner(tile, UDim.new(0, 16))
	UIKit.stroke(tile, UIKit.darken(def.Color, 0.45), 3)
	UIKit.gradient(tile, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200))
	UIKit.label(tile, def.Icon, { Size = UDim2.fromScale(0.72, 0.72), Position = UDim2.fromScale(0.14, 0.14), ZIndex = 24 })
	local levelPill = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(66, 20),
		BackgroundColor3 = Colors.Outline,
		ZIndex = 25,
	}, tile)
	UIKit.corner(levelPill, UDim.new(1, 0))
	local level = UIKit.title(levelPill, "LV 0", {
		Size = UDim2.new(1, -10, 1, -6),
		Position = UDim2.fromOffset(5, 3),
		TextColor3 = Colors.Yellow,
		ZIndex = 26,
	}, Colors.Outline, 1.5)
	UIKit.title(frame, string.upper(def.Name), {
		Size = UDim2.new(1, -270, 0, 28),
		Position = UDim2.fromOffset(96, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
	}, Colors.Outline, 2.5)
	local pipBar = UIKit.new("Frame", {
		Size = UDim2.new(1, -270, 0, 10),
		Position = UDim2.fromOffset(96, 40),
		BackgroundTransparency = 1,
		ZIndex = 23,
	}, frame)
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pipBar)
	local pips = {}
	for index = 1, #def.Costs do
		local pip = UIKit.new("Frame", {
			Size = UDim2.new(1 / #def.Costs, -4, 1, 0),
			BackgroundColor3 = Color3.fromRGB(30, 32, 48),
			LayoutOrder = index,
			ZIndex = 24,
		}, pipBar)
		UIKit.corner(pip, UDim.new(1, 0))
		pips[index] = pip
	end
	local effect = UIKit.label(frame, def.Description, {
		Size = UDim2.new(1, -270, 0, 24),
		Position = UDim2.fromOffset(96, 56),
		TextColor3 = Color3.fromRGB(220, 225, 245),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
	})
	local row: PerkRow
	local buy = UIKit.chunky(frame, {
		Name = "Buy",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(150, 60),
		Color = Colors.Blue,
		Text = TOKEN .. " 1",
		ZIndex = 24,
		MaxTextSize = 28,
	}, function()
		buyPerk(id, row)
	end)
	row = { Frame = frame, Level = level, Effect = effect, Pips = pips, Buy = buy, Color = def.Color }
	return row
end

local function buildPerksPage(page: ScrollingFrame)
	UIKit.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, page)
	UIKit.padding(page, 6)
	for order, id in Progression.PerkOrder do
		perkRows[id] = perkRow(page, id, order)
	end
end

-- Big "REBIRTH!" celebration for the local player.
local function celebrate(payload: { [string]: any })
	local rebirths = if type(payload.Rebirths) == "number" then payload.Rebirths else 1
	local multiplier = if type(payload.Multiplier) == "number" then payload.Multiplier else 1
	local tokens = if type(payload.Tokens) == "number" then payload.Tokens else 1
	local flash = UIKit.new("Frame", {
		Name = "RebirthFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.White,
		BackgroundTransparency = 0,
		ZIndex = 70,
	}, screen)
	UIKit.tween(flash, 0.8, { BackgroundTransparency = 1 })
	local popup = UIKit.new("Frame", {
		Name = "RebirthDone",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(520, 210),
		BackgroundColor3 = Colors.Pink,
		ZIndex = 71,
	}, screen)
	UIKit.corner(popup, UDim.new(0, 28))
	UIKit.stroke(popup, Colors.Outline, 5)
	UIKit.gradient(popup, Color3.fromRGB(255, 255, 255), Color3.fromRGB(220, 120, 190))
	UIKit.shine(popup, UDim.new(0, 28), 1)
	UIKit.title(popup, `🔁 REBIRTH {rebirths}!`, {
		Size = UDim2.new(1, -40, 0, 60),
		Position = UDim2.fromOffset(20, 16),
		ZIndex = 72,
	}, UIKit.darken(Colors.Pink, 0.6), 4)
	UIKit.title(popup, `x{multiplier} CASH FOREVER`, {
		Size = UDim2.new(1, -40, 0, 46),
		Position = UDim2.fromOffset(20, 84),
		TextColor3 = Color3.fromRGB(140, 255, 140),
		ZIndex = 72,
	}, Colors.Outline, 4)
	UIKit.title(popup, `+{tokens} {TOKEN} Rebirth Token{if tokens == 1 then "" else "s"}`, {
		Size = UDim2.new(1, -60, 0, 32),
		Position = UDim2.fromOffset(30, 140),
		TextColor3 = Color3.fromRGB(150, 210, 255),
		ZIndex = 72,
	}, Colors.Outline, 3)
	UIKit.popIn(popup, 0.5)
	SoundPlayer.play("Purchase", 0.9)
	Effects.confetti(90)
	task.delay(4, function()
		UIKit.tween(UIKit.scaleOf(popup), 0.3, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.32)
		popup:Destroy()
		flash:Destroy()
	end)
end

function RebirthPanel.init(gui: ScreenGui)
	screen = gui
	window = Window.new(screen, { Title = "REBIRTH", Icon = "🔁", Color = Colors.Pink, Width = 720, Height = 520 })
	local body = Window.tabs(window, TABS, function(key: string)
		for name, page in pages do
			page.Visible = name == key
		end
	end)
	local rebirthPage = UIKit.new("Frame", {
		Name = "Rebirth",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 22,
	}, body)
	pages.Rebirth = rebirthPage
	buildRebirthPage(rebirthPage)
	local perksPage = UIKit.new("ScrollingFrame", {
		Name = "Perks",
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
	pages.Perks = perksPage
	buildPerksPage(perksPage)

	window.OnOpen = function()
		resetConfirm()
		window.Subtitle.Text = ""
		refresh()
	end
	State.Changed:Connect(function()
		if window:IsOpen() then
			refresh()
		end
	end)
	Effects.on("Rebirth", function(payload)
		if payload.OwnerId == game:GetService("Players").LocalPlayer.UserId then
			celebrate(payload)
		end
	end)
	local select = window.SelectTab
	if select then
		select("Rebirth")
	end
end

function RebirthPanel.open(tab: string?)
	if not window:IsOpen() then
		window:Open()
	end
	local select = window.SelectTab
	if tab and select then
		select(tab)
	end
end

function RebirthPanel.toggle()
	Window.toggle(window)
end

return RebirthPanel
