--!strict
-- The first-time tutorial card: "STEP 1 OF 4 — GRAB A BOX!". Steps are
-- completed by the server; this shows them, celebrates each one with coins
-- and confetti, and points at the UPGRADE button for the last step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tutorial = require(Shared:WaitForChild("Tutorial"))

local Effects = require(script.Parent.Effects)
local HUD = require(script.Parent.HUD)
local Notifications = require(script.Parent.Notifications)
local SoundPlayer = require(script.Parent.SoundPlayer)
local State = require(script.Parent.State)
local UIKit = require(script.Parent.UIKit)
local Window = require(script.Parent.Window)

local Colors = UIKit.Colors

local TutorialUI = {}

local screen: ScreenGui
local card: Frame
local cardStroke: UIStroke
local iconLabel: TextLabel
local stepLabel: TextLabel
local titleLabel: TextLabel
local textLabel: TextLabel
local segments: { Frame } = {}
local pointer: TextLabel
local shownStep: number? = nil
local celebrating = false
local cardWanted = false -- the card hides while a menu is open

local CARD_POSITION = UDim2.new(0.5, 0, 0, 68)

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function build()
	card = UIKit.new("Frame", {
		Name = "Tutorial",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = CARD_POSITION,
		Size = UDim2.fromOffset(500, 124),
		BackgroundColor3 = Colors.Panel,
		Visible = false,
		ZIndex = 40,
	}, screen)
	UIKit.corner(card, UDim.new(0, 22))
	cardStroke = UIKit.stroke(card, Colors.Yellow, 4)
	UIKit.gradient(card, Color3.fromRGB(255, 255, 255), Color3.fromRGB(185, 190, 215))

	local iconCircle = UIKit.new("Frame", {
		Size = UDim2.fromOffset(88, 88),
		Position = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Colors.Yellow,
		ZIndex = 41,
	}, card)
	UIKit.corner(iconCircle, UDim.new(1, 0))
	UIKit.stroke(iconCircle, Colors.Outline, 3)
	UIKit.gradient(iconCircle, Color3.fromRGB(255, 255, 255), Color3.fromRGB(215, 200, 170))
	iconLabel = UIKit.label(iconCircle, "📦", { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.15, 0.15), ZIndex = 42 })
	UIKit.wobble(iconLabel, 8)

	stepLabel = UIKit.title(card, "STEP 1 OF 4", {
		Size = UDim2.fromOffset(200, 20),
		Position = UDim2.fromOffset(116, 10),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Yellow,
		ZIndex = 41,
	}, Colors.Outline, 2)
	titleLabel = UIKit.title(card, "", {
		Size = UDim2.new(1, -206, 0, 34), -- leaves room for the SKIP button
		Position = UDim2.fromOffset(116, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 41,
	}, Colors.Outline, 3)
	textLabel = UIKit.label(card, "", {
		Size = UDim2.new(1, -130, 0, 26),
		Position = UDim2.fromOffset(116, 66),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(230, 235, 255),
		ZIndex = 41,
	})
	UIKit.textStroke(textLabel, Colors.Outline, 1.5)

	local bar = UIKit.new("Frame", {
		Size = UDim2.new(1, -130, 0, 10),
		Position = UDim2.fromOffset(116, 100),
		BackgroundTransparency = 1,
		ZIndex = 41,
	}, card)
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, bar)
	for index = 1, #Tutorial.Steps do
		local segment = UIKit.new("Frame", {
			Size = UDim2.new(1 / #Tutorial.Steps, -6, 1, 0),
			BackgroundColor3 = Colors.Dark,
			LayoutOrder = index,
			ZIndex = 42,
		}, bar)
		UIKit.corner(segment, UDim.new(1, 0))
		UIKit.stroke(segment, Colors.Outline, 1.5)
		segments[index] = segment
	end

	local skip = UIKit.chunky(card, {
		Name = "Skip",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(74, 30),
		Color = Colors.GreyDark,
		Text = "SKIP",
		Depth = 4,
		ZIndex = 43,
		Radius = UDim.new(0, 10),
	}, function()
		SoundPlayer.play("Click")
		Remotes.event("SkipTutorial"):FireServer()
		cardWanted = false
	end)
	skip.Button.Name = "Skip"

	-- Bouncing hand pointing at the UPGRADE button during the last step.
	pointer = UIKit.title(screen, "👈 CLICK!", {
		Name = "TutorialPointer",
		Size = UDim2.fromOffset(150, 44),
		Position = UDim2.new(0, 224, 0.5, -84),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Colors.Yellow,
		Visible = false,
		ZIndex = 30,
	}, Colors.Outline, 3)
end

local function show(index: number)
	local step = Tutorial.step(index)
	if not step then
		return
	end
	shownStep = index
	iconLabel.Text = step.Icon
	stepLabel.Text = `STEP {index} OF {#Tutorial.Steps}`
	titleLabel.Text = step.Title
	textLabel.Text = if isTouch() then step.TouchText else step.Text
	for i, segment in segments do
		segment.BackgroundColor3 = if i < index then Colors.Green elseif i == index then Colors.Yellow else Colors.Dark
	end
	card.BackgroundColor3 = Colors.Panel
	cardStroke.Color = Colors.Yellow
	cardWanted = true
	card.Position = CARD_POSITION - UDim2.fromOffset(0, 160)
	UIKit.tween(card, 0.45, { Position = CARD_POSITION }, Enum.EasingStyle.Back)
	SoundPlayer.play("Whoosh")
end

local function update()
	local index = State.tutorialStep()
	HUD.setTutorialActive(index ~= nil)
	if celebrating then
		return
	end
	if not index then
		cardWanted = false
		pointer.Visible = false
		shownStep = nil
		return
	end
	if index ~= shownStep then
		show(index)
	end
end

-- Big "YOU'RE A SHOPKEEPER!" finale.
local function finale(reward: number)
	local popup = UIKit.new("Frame", {
		Name = "TutorialDone",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(520, 220),
		BackgroundColor3 = Colors.Gold,
		ZIndex = 60,
	}, screen)
	UIKit.corner(popup, UDim.new(0, 28))
	UIKit.stroke(popup, Colors.Outline, 5)
	UIKit.gradient(popup, Color3.fromRGB(255, 255, 255), Color3.fromRGB(230, 170, 60))
	UIKit.shine(popup, UDim.new(0, 28), 1.2)
	UIKit.title(popup, "🎉 YOU'RE A SHOPKEEPER! 🎉", {
		Size = UDim2.new(1, -40, 0, 56),
		Position = UDim2.fromOffset(20, 26),
		ZIndex = 61,
	}, UIKit.darken(Colors.Gold, 0.6), 4)
	UIKit.title(popup, "BONUS +" .. Format.money(reward), {
		Size = UDim2.new(1, -40, 0, 50),
		Position = UDim2.fromOffset(20, 92),
		TextColor3 = Color3.fromRGB(120, 255, 130),
		ZIndex = 61,
	}, Colors.Outline, 4)
	UIKit.label(popup, "Keep filling your shelves and upgrading your shop!", {
		Size = UDim2.new(1, -60, 0, 28),
		Position = UDim2.fromOffset(30, 158),
		ZIndex = 61,
	})
	UIKit.popIn(popup, 0.5)
	Effects.confetti(90)
	SoundPlayer.play("Rare")
	HUD.flyCoinsFrom(Vector2.new(popup.AbsolutePosition.X + 260, popup.AbsolutePosition.Y + 117), reward)
	task.delay(4, function()
		UIKit.tween(UIKit.scaleOf(popup), 0.3, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.32)
		popup:Destroy()
	end)
end

local function celebrate(payload: { [string]: any })
	celebrating = true
	pointer.Visible = false
	local reward = if type(payload.Reward) == "number" then payload.Reward else 0
	cardWanted = true
	card.Visible = true
	card.BackgroundColor3 = UIKit.darken(Colors.Green, 0.25)
	cardStroke.Color = Colors.Green
	iconLabel.Text = "✅"
	stepLabel.Text = "STEP COMPLETE"
	titleLabel.Text = "NICE WORK!"
	textLabel.Text = "+" .. Format.money(reward) .. " reward"
	if shownStep and segments[shownStep] then
		segments[shownStep].BackgroundColor3 = Colors.Green
	end
	UIKit.pop(card, 0.12)
	SoundPlayer.play("StepDone")
	Effects.confetti(40)
	local center = card.AbsolutePosition + card.AbsoluteSize / 2
	local scale = screen:FindFirstChildOfClass("UIScale")
	local s = if scale then scale.Scale else 1
	HUD.flyCoinsFrom(Vector2.new(center.X / s, center.Y / s), reward)
	task.delay(1.7, function()
		celebrating = false
		if payload.Finished then
			cardWanted = false
			shownStep = nil
			finale(if type(payload.FinishReward) == "number" then payload.FinishReward else 0)
		end
		update()
	end)
end

function TutorialUI.init(gui: ScreenGui)
	screen = gui
	build()
	State.Changed:Connect(update)
	Effects.on("TutorialStep", celebrate)
	update()
	RunService.RenderStepped:Connect(function()
		local index = State.tutorialStep()
		local step = index and Tutorial.step(index)
		local wantsUpgrade = step ~= nil and step.Id == "Upgrade" and not celebrating
		pointer.Visible = wantsUpgrade and not Window.isAnyOpen()
		if pointer.Visible then
			pointer.Position = UDim2.new(0, 224 + math.abs(math.sin(os.clock() * 5)) * 16, 0.5, -84)
		end
		card.Visible = cardWanted and (celebrating or not Window.isAnyOpen())
		Notifications.setTopOffset(if card.Visible then 132 else 0)
	end)
end

return TutorialUI
