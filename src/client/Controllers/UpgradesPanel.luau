--!strict
-- The single upgrade menu. Purchases are validated by the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))
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
	Buy: TextButton,
	BuyStroke: UIStroke,
}

local window: Window.Window
local rows: { [string]: Row } = {}
local buying = false

local function refresh()
	local data = State.Data
	if not data then
		return
	end
	for id, row in rows do
		local def = Upgrades.Defs[id]
		local level = data.Upgrades[id] or def.StartLevel
		local cost = Upgrades.getCost(id, level)
		local shownLevel = level - def.StartLevel
		local maxShown = def.MaxLevel - def.StartLevel
		row.Level.Text = `Lv {shownLevel}/{maxShown}`
		if cost then
			row.Effect.Text = `{def.Effect(level)}  →  {def.Effect(level + 1)}`
			row.Buy.Text = Format.money(cost)
			local affordable = data.Cash >= cost
			row.Buy.BackgroundColor3 = if affordable then Colors.Green else Colors.Grey
			row.BuyStroke.Color = if affordable then Colors.GreenDark else Color3.fromRGB(80, 84, 100)
		else
			row.Effect.Text = def.Effect(level)
			row.Buy.Text = "MAX"
			row.Buy.BackgroundColor3 = Colors.Gold
			row.BuyStroke.Color = Color3.fromRGB(160, 110, 0)
		end
	end
	window.Subtitle.Text = `💷 You have {Format.money(data.Cash)}`
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
		SoundPlayer.play("Cash", 1.2)
		UIKit.pop(row.Frame, 0.08)
		local flash = UIKit.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Colors.White,
			BackgroundTransparency = 0.3,
			ZIndex = 30,
		}, row.Frame)
		UIKit.corner(flash, UDim.new(0, 16))
		UIKit.tween(flash, 0.4, { BackgroundTransparency = 1 })
		task.delay(0.45, function()
			flash:Destroy()
		end)
	else
		SoundPlayer.play("Error")
		UIKit.shake(row.Buy)
		if ok and type(message) == "string" then
			window.Subtitle.Text = "⚠️ " .. message
		end
	end
end

local function makeRow(parent: Instance, id: string, order: number): Row
	local def = Upgrades.Defs[id]
	local frame = UIKit.new("Frame", {
		Name = id,
		Size = UDim2.new(1, -10, 0, 82),
		BackgroundColor3 = Colors.PanelLight,
		LayoutOrder = order,
		ZIndex = 22,
	}, parent)
	UIKit.corner(frame, UDim.new(0, 16))

	local icon = UIKit.new("Frame", {
		Size = UDim2.fromOffset(62, 62),
		Position = UDim2.fromOffset(10, 10),
		BackgroundColor3 = def.Color,
		ZIndex = 23,
	}, frame)
	UIKit.corner(icon, UDim.new(0, 14))
	UIKit.stroke(icon, def.Color:Lerp(Color3.new(0, 0, 0), 0.35), 3)
	UIKit.label(icon, def.Icon, { Size = UDim2.fromScale(0.75, 0.75), Position = UDim2.fromScale(0.125, 0.125), ZIndex = 24 })

	local name = UIKit.label(frame, def.Name, {
		Size = UDim2.new(1, -250, 0, 28),
		Position = UDim2.fromOffset(84, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
	})
	UIKit.textStroke(name, Colors.Dark, 2)
	local level = UIKit.label(frame, "Lv 0", {
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(70, 22),
		Position = UDim2.new(1, -150, 0, 11),
		TextColor3 = Colors.Yellow,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 23,
	})
	local effect = UIKit.label(frame, def.Description, {
		Size = UDim2.new(1, -240, 0, 22),
		Position = UDim2.fromOffset(84, 38),
		TextColor3 = Color3.fromRGB(210, 215, 235),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
	})
	UIKit.label(frame, def.Description, {
		Size = UDim2.new(1, -240, 0, 16),
		Position = UDim2.fromOffset(84, 60),
		TextColor3 = Color3.fromRGB(150, 155, 180),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
	})

	local row: Row
	local buyButton = UIKit.button(frame, {
		Name = "Buy",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(130, 56),
		BackgroundColor3 = Colors.Green,
		Text = "",
		ZIndex = 23,
	}, function()
		buy(id, row)
	end)
	UIKit.padding(buyButton, 10)
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 30 }, buyButton)
	row = {
		Frame = frame,
		Level = level,
		Effect = effect,
		Buy = buyButton,
		BuyStroke = UIKit.stroke(buyButton, Colors.GreenDark, 3),
	}
	return row
end

function UpgradesPanel.init(screen: ScreenGui)
	window = Window.new(screen, "⬆️ UPGRADES", Colors.Green, Colors.GreenDark)
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
	for order, id in Upgrades.Order do
		rows[id] = makeRow(list, id, order)
	end
	window.OnOpen = refresh
	State.Changed:Connect(function()
		if window:IsOpen() then
			refresh()
		end
	end)
end

function UpgradesPanel.toggle()
	Window.toggle(window)
end

return UpgradesPanel
