--!strict
-- Always-visible HUD: cash, delivery timer, UPGRADES / STOCK buttons and the
-- short objective hint at the bottom of the screen.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Signal = require(Shared:WaitForChild("Signal"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))

local State = require(script.Parent.State)
local UIKit = require(script.Parent.UIKit)
local Window = require(script.Parent.Window)

local Colors = UIKit.Colors
local player = Players.LocalPlayer

local HUD = {}

HUD.UpgradesPressed = Signal.new() :: Signal.Signal<>
HUD.StockPressed = Signal.new() :: Signal.Signal<>

local cashPill: Frame
local cashLabel: TextLabel
local deliveryLabel: TextLabel
local deliveryPill: Frame
local hintPill: Frame
local hintLabel: TextLabel
local stockBadge: Frame
local stockBadgeLabel: TextLabel
local upgradesAlert: Frame
local upgradesButton: TextButton

local displayedCash = 0
local targetCash = 0
local currentHint: string? = nil

local function bigButton(parent: Instance, icon: string, text: string, color: Color3, dark: Color3, onClick: () -> ()): TextButton
	local button = UIKit.button(parent, {
		Name = text,
		Size = UDim2.fromOffset(92, 92),
		BackgroundColor3 = color,
		Text = "",
	}, onClick)
	UIKit.stroke(button, dark, 4)
	UIKit.gradient(button, Color3.fromRGB(255, 255, 255), Color3.fromRGB(215, 215, 215))
	UIKit.label(button, icon, { Size = UDim2.new(1, 0, 0.55, 0), Position = UDim2.fromScale(0, 0.06) })
	local label = UIKit.label(button, text, { Size = UDim2.new(0.9, 0, 0.26, 0), Position = UDim2.fromScale(0.05, 0.64) })
	UIKit.textStroke(label, dark, 2)
	return button
end

local function badge(parent: Instance, color: Color3): (Frame, TextLabel)
	local frame = UIKit.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = color,
		Visible = false,
		ZIndex = 5,
	}, parent)
	UIKit.corner(frame, UDim.new(1, 0))
	UIKit.stroke(frame, Colors.White, 2)
	local label = UIKit.label(frame, "", { ZIndex = 6 })
	UIKit.padding(label, 4)
	return frame, label
end

function HUD.init(screen: ScreenGui)
	-- Cash (top centre)
	cashPill = UIKit.new("Frame", {
		Name = "Cash",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(260, 62),
		BackgroundColor3 = Colors.Dark,
		BackgroundTransparency = 0.1,
	}, screen)
	UIKit.corner(cashPill, UDim.new(1, 0))
	UIKit.stroke(cashPill, Colors.Gold, 3)
	local coin = UIKit.new("Frame", {
		Size = UDim2.fromOffset(50, 50),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Colors.Gold,
	}, cashPill)
	UIKit.corner(coin, UDim.new(1, 0))
	UIKit.stroke(coin, Color3.fromRGB(255, 240, 170), 3)
	UIKit.label(coin, "£", { TextColor3 = Color3.fromRGB(140, 90, 0), Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1) })
	cashLabel = UIKit.label(cashPill, "£0", {
		Name = "Amount",
		Position = UDim2.fromOffset(64, 9),
		Size = UDim2.new(1, -80, 1, -18),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	UIKit.textStroke(cashLabel, Color3.fromRGB(80, 60, 0), 2)

	-- Delivery timer / boxes waiting
	deliveryPill = UIKit.new("Frame", {
		Name = "Delivery",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 74),
		Size = UDim2.fromOffset(250, 34),
		BackgroundColor3 = Colors.Dark,
		BackgroundTransparency = 0.25,
	}, screen)
	UIKit.corner(deliveryPill, UDim.new(1, 0))
	deliveryLabel = UIKit.label(deliveryPill, "🚚 Delivery on the way!", {
		Size = UDim2.new(1, -20, 1, -8),
		Position = UDim2.fromOffset(10, 4),
	})

	-- Big buttons on the left
	local column = UIKit.new("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.45, 0),
		Size = UDim2.fromOffset(96, 210),
		BackgroundTransparency = 1,
	}, screen)
	UIKit.new("UIListLayout", {
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, column)
	upgradesButton = bigButton(column, "⬆️", "UPGRADES", Colors.Green, Colors.GreenDark, function()
		HUD.UpgradesPressed:Fire()
	end)
	upgradesButton.LayoutOrder = 1
	local stockButton = bigButton(column, "📦", "STOCK", Colors.Blue, Colors.BlueDark, function()
		HUD.StockPressed:Fire()
	end)
	stockButton.LayoutOrder = 2
	stockBadge, stockBadgeLabel = badge(stockButton, Colors.Red)
	upgradesAlert = badge(upgradesButton, Colors.Yellow)
	local alertLabel = upgradesAlert:FindFirstChildOfClass("TextLabel")
	if alertLabel then
		alertLabel.Text = "!"
		alertLabel.TextColor3 = Colors.Dark
	end

	-- Objective hint (bottom centre)
	hintPill = UIKit.new("Frame", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(380, 50),
		BackgroundColor3 = Colors.Dark,
		BackgroundTransparency = 0.15,
		Visible = false,
	}, screen)
	UIKit.corner(hintPill, UDim.new(1, 0))
	UIKit.stroke(hintPill, Colors.Yellow, 3)
	hintLabel = UIKit.label(hintPill, "", { Size = UDim2.new(1, -28, 1, -12), Position = UDim2.fromOffset(14, 6) })

	State.Changed:Connect(function(data, previous)
		targetCash = data.Cash
		if previous == nil then
			displayedCash = data.Cash
		elseif data.Cash > previous.Cash then
			HUD.floatCash(data.Cash - previous.Cash)
		end
		HUD.refreshBadges()
	end)
	if State.Data then
		targetCash = State.Data.Cash
		displayedCash = targetCash
	end

	-- Smooth count-up for cash.
	RunService.RenderStepped:Connect(function(dt: number)
		if math.abs(targetCash - displayedCash) < 0.5 then
			displayedCash = targetCash
		else
			displayedCash += (targetCash - displayedCash) * math.min(1, dt * 9)
		end
		cashLabel.Text = Format.money(math.floor(displayedCash + 0.5))
	end)

	-- Delivery pill refresh.
	task.spawn(function()
		while true do
			HUD.refreshDelivery()
			task.wait(0.25)
		end
	end)
end

function HUD.refreshDelivery()
	-- Menus get the screen to themselves (matters on phones).
	local menuOpen = Window.isAnyOpen()
	deliveryPill.Visible = not menuOpen
	hintPill.Visible = currentHint ~= nil and not menuOpen
	local waiting = 0
	for _, box in CollectionService:GetTagged("DeliveryBox") do
		local root = box:FindFirstChild("Box")
		if box:GetAttribute("OwnerUserId") == player.UserId and root and root:FindFirstChild("BoxPrompt") then
			waiting += 1
		end
	end
	if waiting > 0 then
		deliveryLabel.Text = `📦 {waiting} box{if waiting == 1 then "" else "es"} waiting!`
		deliveryLabel.TextColor3 = Colors.Yellow
		return
	end
	deliveryLabel.TextColor3 = Colors.White
	local nextAt = player:GetAttribute("NextDeliveryAt")
	if type(nextAt) == "number" then
		local remaining = math.max(0, math.ceil(nextAt - workspace:GetServerTimeNow()))
		deliveryLabel.Text = if remaining > 0 then `🚚 Next delivery {remaining}s` else "🚚 Delivery arriving!"
	else
		deliveryLabel.Text = "🚚 Delivery on the way!"
	end
end

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
	end
	if affordable and not upgradesAlert.Visible then
		UIKit.pop(upgradesButton, 0.2)
	end
	upgradesAlert.Visible = affordable
end

-- "+£24" flying up next to the cash counter.
function HUD.floatCash(amount: number)
	UIKit.pop(cashPill, 0.08)
	local label = UIKit.label(cashPill.Parent, "+" .. Format.money(amount), {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 136, 0, 38),
		Size = UDim2.fromOffset(160, 34),
		TextColor3 = Colors.Green,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 10,
	})
	UIKit.textStroke(label, Colors.Dark, 2)
	UIKit.tween(label, 0.9, { Position = UDim2.new(0.5, 136, 0, 4), TextTransparency = 1 })
	task.delay(0.95, function()
		label:Destroy()
	end)
end

function HUD.setHint(text: string?)
	if text == currentHint then
		return
	end
	currentHint = text
	if text then
		hintLabel.Text = text
		hintPill.Visible = not Window.isAnyOpen()
		UIKit.pop(hintPill, 0.12)
	else
		hintPill.Visible = false
	end
end

function HUD.pulseUpgrades()
	UIKit.pop(upgradesButton, 0.15)
end

return HUD
