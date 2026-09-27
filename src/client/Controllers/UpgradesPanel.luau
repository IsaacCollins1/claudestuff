--!strict
-- The upgrade menu. Purchases are validated by the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tutorial = require(Shared:WaitForChild("Tutorial"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))

local SoundPlayer = require(script.Parent.SoundPlayer)
local State = require(script.Parent.State)
local UIKit = require(script.Parent.UIKit)
local Window = require(script.Parent.Window)

local Colors = UIKit.Colors

local UpgradesPanel = {}

type Row = {
	Frame: Frame,
	Level: TextLabel,
	Effect: TextLabel,
	Pips: { Frame },
	Buy: UIKit.Chunky,
	Glow: UIStroke,
	Color: Color3,
}

local window: Window.Window
local rows: { [string]: Row } = {}
local buying = false

local function tutorialWantsUpgrade(): boolean
	local step = State.tutorialStep()
	local def = step and Tutorial.step(step)
	return def ~= nil and def.Id == "Upgrade"
end

local function refresh()
	local data = State.Data
	if not data then
		return
	end
	local highlight = tutorialWantsUpgrade()
	for id, row in rows do
		local def = Upgrades.Defs[id]
		local level = data.Upgrades[id] or def.StartLevel
		local cost = Upgrades.getCost(id, level)
		local shownLevel = level - def.StartLevel
		row.Level.Text = `LV {shownLevel}/{def.MaxLevel - def.StartLevel}`
		for index, pip in row.Pips do
			pip.BackgroundColor3 = if index <= shownLevel then row.Color else Color3.fromRGB(30, 32, 48)
		end
		local label = row.Buy.Text
		if cost then
			row.Effect.Text = `{def.Effect(level)}  ➜  {def.Effect(level + 1)}`
			local affordable = data.Cash >= cost
			if label then
				label.Text = Format.money(cost)
			end
			row.Buy.SetColor(if affordable then Colors.Green else Colors.GreyDark)
			row.Glow.Enabled = highlight and affordable
		else
			row.Effect.Text = def.Effect(level)
			if label then
				label.Text = "MAX"
			end
			row.Buy.SetColor(Colors.Gold)
			row.Glow.Enabled = false
		end
	end
	window.Subtitle.Text = `You have {Format.money(data.Cash)}`
end

local function celebrate(row: Row)
	UIKit.pop(row.Frame, 0.06)
	local flash = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.White,
		BackgroundTransparency = 0.2,
		ZIndex = 40,
	}, row.Frame)
	UIKit.corner(flash, UDim.new(0, 18))
	UIKit.tween(flash, 0.45, { BackgroundTransparency = 1 })
	local plus = UIKit.title(row.Frame, "LEVEL UP!", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.45, 0.5),
		Size = UDim2.fromOffset(220, 44),
		TextColor3 = Colors.Yellow,
		ZIndex = 41,
	}, Colors.Outline, 3)
	UIKit.popIn(plus)
	UIKit.tween(plus, 0.9, { Position = UDim2.fromScale(0.45, -0.1), TextTransparency = 1 })
	task.delay(0.95, function()
		flash:Destroy()
		plus:Destroy()
	end)
end

local function buy(id: string, row: Row)
	if buying then
		return
	end
	buying = true
	local ok, success, message = pcall(function()
		return Remotes.func("BuyUpgrade"):InvokeServer(id)
	end)
	buying = false
	if ok and success then
		SoundPlayer.play("Upgrade")
		SoundPlayer.play("Purchase", 1.1)
		celebrate(row)
	else
		SoundPlayer.play("Error")
		UIKit.shake(row.Buy.Button)
		if ok and type(message) == "string" then
			window.Subtitle.Text = "⚠️ " .. message
		end
	end
end

local function makeRow(parent: Instance, id: string, order: number): Row
	local def = Upgrades.Defs[id]
	local frame = UIKit.new("Frame", {
		Name = id,
		Size = UDim2.new(1, -12, 0, 100),
		BackgroundColor3 = Colors.PanelLight,
		LayoutOrder = order,
		ZIndex = 22,
	}, parent)
	UIKit.corner(frame, UDim.new(0, 18))
	UIKit.stroke(frame, Colors.Outline, 3)

	local tile = UIKit.new("Frame", {
		Size = UDim2.fromOffset(76, 76),
		Position = UDim2.fromOffset(12, 8),
		BackgroundColor3 = def.Color,
		ZIndex = 23,
	}, frame)
	UIKit.corner(tile, UDim.new(0, 16))
	UIKit.stroke(tile, UIKit.darken(def.Color, 0.45), 3)
	UIKit.gradient(tile, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200))
	UIKit.label(tile, def.Icon, { Size = UDim2.fromScale(0.72, 0.72), Position = UDim2.fromScale(0.14, 0.14), ZIndex = 24 })

	UIKit.title(frame, string.upper(def.Name), {
		Size = UDim2.new(1, -290, 0, 30),
		Position = UDim2.fromOffset(100, 10),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
	}, Colors.Outline, 2.5)
	-- Level pill hanging off the bottom of the icon tile.
	local levelPill = UIKit.new("Frame", {
		Name = "LevelPill",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(70, 22),
		BackgroundColor3 = Colors.Outline,
		ZIndex = 25,
	}, tile)
	UIKit.corner(levelPill, UDim.new(1, 0))
	UIKit.stroke(levelPill, UIKit.darken(def.Color, 0.35), 2)
	local level = UIKit.title(levelPill, "LV 0", {
		Size = UDim2.new(1, -10, 1, -6),
		Position = UDim2.fromOffset(5, 3),
		TextColor3 = Colors.Yellow,
		ZIndex = 26,
	}, Colors.Outline, 1.5)

	-- Level pips
	local pipCount = def.MaxLevel - def.StartLevel
	local pipBar = UIKit.new("Frame", {
		Size = UDim2.new(1, -290, 0, 12),
		Position = UDim2.fromOffset(100, 45),
		BackgroundTransparency = 1,
		ZIndex = 23,
	}, frame)
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pipBar)
	local pips = {}
	for index = 1, pipCount do
		local pip = UIKit.new("Frame", {
			Size = UDim2.new(1 / pipCount, -4, 1, 0),
			BackgroundColor3 = Color3.fromRGB(30, 32, 48),
			LayoutOrder = index,
			ZIndex = 24,
		}, pipBar)
		UIKit.corner(pip, UDim.new(1, 0))
		pips[index] = pip
	end

	local effect = UIKit.label(frame, def.Description, {
		Size = UDim2.new(1, -290, 0, 24),
		Position = UDim2.fromOffset(100, 64),
		TextColor3 = Color3.fromRGB(220, 225, 245),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
	})

	local row: Row
	local buyButton = UIKit.chunky(frame, {
		Name = "Buy",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(150, 64),
		Color = Colors.Green,
		Text = "£0",
		ZIndex = 24,
		MaxTextSize = 30,
	}, function()
		buy(id, row)
	end)
	local glow = UIKit.stroke(buyButton.Base, Colors.Yellow, 5)
	glow.Enabled = false
	row = {
		Frame = frame,
		Level = level,
		Effect = effect,
		Pips = pips,
		Buy = buyButton,
		Glow = glow,
		Color = def.Color,
	}
	return row
end

function UpgradesPanel.init(screen: ScreenGui)
	window = Window.new(screen, { Title = "UPGRADES", Icon = "⬆️", Color = Colors.Green })
	local list = UIKit.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Colors.Grey,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 22,
	}, window.Content)
	UIKit.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	UIKit.padding(list, 6)
	for order, id in Upgrades.Order do
		rows[id] = makeRow(list, id, order)
	end
	window.OnOpen = refresh
	State.Changed:Connect(function()
		if window:IsOpen() then
			refresh()
		end
	end)
	-- Pulse the tutorial glow.
	RunService.RenderStepped:Connect(function()
		if not window:IsOpen() then
			return
		end
		local pulse = 3 + math.abs(math.sin(os.clock() * 5)) * 4
		for _, row in rows do
			if row.Glow.Enabled then
				row.Glow.Thickness = pulse
			end
		end
	end)
end

function UpgradesPanel.toggle()
	Window.toggle(window)
end

function UpgradesPanel.isOpen(): boolean
	return window:IsOpen()
end

return UpgradesPanel
