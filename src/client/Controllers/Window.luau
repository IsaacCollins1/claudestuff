--!strict
-- Pop-up menu window: dimmed backdrop, coloured ribbon header, big red X,
-- optional tabs. Only one window is open at a time.

local SoundPlayer = require(script.Parent.SoundPlayer)
local UIKit = require(script.Parent.UIKit)

local Colors = UIKit.Colors

export type Window = {
	Frame: Frame,
	Content: Frame,
	Subtitle: TextLabel,
	Open: (self: Window) -> (),
	Close: (self: Window) -> (),
	IsOpen: (self: Window) -> boolean,
	OnOpen: (() -> ())?,
	SelectTab: ((key: string) -> ())?,
}

export type Options = {
	Title: string,
	Icon: string,
	Color: Color3,
	Width: number?,
	Height: number?,
}

export type Tab = { Key: string, Text: string, Color: Color3 }

local Window = {}

local openWindow: Window? = nil
local backdrop: TextButton? = nil

local function ensureBackdrop(screen: ScreenGui): TextButton
	if backdrop then
		return backdrop
	end
	local dim = UIKit.new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.new(1, 0, 1, 200),
		Position = UDim2.fromOffset(0, -100),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 18,
	}, screen)
	dim.Activated:Connect(function()
		if openWindow then
			openWindow:Close()
		end
	end)
	backdrop = dim
	return dim
end

function Window.new(screen: ScreenGui, options: Options): Window
	local width = options.Width or 620
	local height = options.Height or 460
	local color = options.Color
	local dim = ensureBackdrop(screen)

	local frame = UIKit.new("Frame", {
		Name = options.Title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 18),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Colors.Panel,
		Visible = false,
		ZIndex = 20,
	}, screen)
	UIKit.corner(frame, UDim.new(0, 26))
	UIKit.stroke(frame, Colors.Outline, 5)
	UIKit.gradient(frame, Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 195, 215))

	-- Ribbon header sitting on the top edge.
	local ribbon = UIKit.new("Frame", {
		Name = "Header",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0.62, 0, 0, 62),
		BackgroundColor3 = color,
		ZIndex = 23,
	}, frame)
	UIKit.corner(ribbon, UDim.new(0, 20))
	UIKit.stroke(ribbon, Colors.Outline, 4)
	UIKit.gradient(ribbon, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200))
	UIKit.title(ribbon, `{options.Icon} {options.Title}`, {
		Size = UDim2.new(1, -30, 1, -16),
		Position = UDim2.fromOffset(15, 8),
		ZIndex = 24,
	}, UIKit.darken(color, 0.55), 3)

	local subtitle = UIKit.label(frame, "", {
		Name = "Subtitle",
		Size = UDim2.new(1, -60, 0, 24),
		Position = UDim2.fromOffset(30, 42),
		TextColor3 = Color3.fromRGB(215, 220, 240),
		ZIndex = 21,
	})

	local content = UIKit.new("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -36, 1, -86),
		Position = UDim2.fromOffset(18, 72),
		BackgroundTransparency = 1,
		ZIndex = 21,
	}, frame)

	local self: Window
	self = {
		Frame = frame,
		Content = content,
		Subtitle = subtitle,
		OnOpen = nil,
		SelectTab = nil,
		Open = function(window: Window)
			if openWindow and openWindow ~= window then
				openWindow:Close()
			end
			openWindow = window
			frame.Visible = true
			dim.Visible = true
			UIKit.popIn(frame, 0.32)
			SoundPlayer.play("Whoosh")
			if window.OnOpen then
				window.OnOpen()
			end
		end,
		Close = function(window: Window)
			if openWindow == window then
				openWindow = nil
				dim.Visible = false
			end
			frame.Visible = false
		end,
		IsOpen = function(_window: Window): boolean
			return frame.Visible
		end,
	}

	local close = UIKit.chunky(frame, {
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(56, 56),
		Color = Colors.Red,
		Text = "X",
		Depth = 6,
		ZIndex = 25,
		Radius = UDim.new(0, 16),
	}, function()
		SoundPlayer.play("Click")
		self:Close()
	end)
	close.Button.Name = "Close"
	return self
end

-- Adds a row of tabs at the top of the content area. Returns the area below them.
function Window.tabs(window: Window, tabs: { Tab }, onSelect: (key: string) -> ()): Frame
	local content = window.Content
	local bar = UIKit.new("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundTransparency = 1,
		ZIndex = 22,
	}, content)
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, bar)
	local body = UIKit.new("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -60),
		Position = UDim2.fromOffset(0, 60),
		BackgroundTransparency = 1,
		ZIndex = 22,
	}, content)
	local chunkies: { [string]: UIKit.Chunky } = {}
	local function select(key: string)
		for _, tab in tabs do
			chunkies[tab.Key].SetColor(if tab.Key == key then tab.Color else Colors.GreyDark)
		end
		onSelect(key)
	end
	for order, tab in tabs do
		chunkies[tab.Key] = UIKit.chunky(bar, {
			Name = tab.Key,
			Size = UDim2.fromOffset(170, 46),
			Color = tab.Color,
			Text = tab.Text,
			Depth = 5,
			LayoutOrder = order,
			ZIndex = 23,
			MaxTextSize = 24,
		}, function()
			SoundPlayer.play("Click")
			select(tab.Key)
		end)
	end
	window.SelectTab = select
	return body
end

function Window.isAnyOpen(): boolean
	return openWindow ~= nil
end

function Window.closeAll()
	if openWindow then
		openWindow:Close()
	end
end

-- Toggle helper for HUD buttons.
function Window.toggle(window: Window)
	if window:IsOpen() then
		window:Close()
	else
		window:Open()
	end
end

return Window
