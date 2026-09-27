--!strict
-- Shared pop-up window frame used by the Upgrades and Stock menus.
-- Only one window is open at a time.

local UIKit = require(script.Parent.UIKit)
local SoundPlayer = require(script.Parent.SoundPlayer)

local Colors = UIKit.Colors

export type Window = {
	Frame: Frame,
	Content: Frame,
	Subtitle: TextLabel,
	Open: (self: Window) -> (),
	Close: (self: Window) -> (),
	IsOpen: (self: Window) -> boolean,
	OnOpen: (() -> ())?,
}

local Window = {}

local openWindow: Window? = nil

function Window.new(screen: ScreenGui, title: string, color: Color3, dark: Color3): Window
	local frame = UIKit.new("Frame", {
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(560, 440),
		BackgroundColor3 = Colors.Panel,
		Visible = false,
		ZIndex = 20,
	}, screen)
	UIKit.corner(frame, UDim.new(0, 24))
	UIKit.stroke(frame, dark, 5)
	UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(560, 440) }, frame)

	local header = UIKit.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = color,
		ZIndex = 21,
	}, frame)
	UIKit.corner(header, UDim.new(0, 24))
	-- Square off the header's bottom corners.
	UIKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 1, -24),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 21,
	}, header)
	local titleLabel = UIKit.label(header, title, {
		Size = UDim2.new(1, -120, 0, 44),
		Position = UDim2.fromOffset(20, 10),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
	})
	UIKit.textStroke(titleLabel, dark, 3)

	local subtitle = UIKit.label(frame, "", {
		Name = "Subtitle",
		Size = UDim2.new(1, -40, 0, 26),
		Position = UDim2.fromOffset(20, 72),
		TextColor3 = Color3.fromRGB(200, 205, 225),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
	})

	local content = UIKit.new("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -28, 1, -118),
		Position = UDim2.fromOffset(14, 104),
		BackgroundTransparency = 1,
		ZIndex = 21,
	}, frame)

	local self: Window
	self = {
		Frame = frame,
		Content = content,
		Subtitle = subtitle,
		OnOpen = nil,
		Open = function(window: Window)
			if openWindow and openWindow ~= window then
				openWindow:Close()
			end
			openWindow = window
			frame.Visible = true
			local scale = UIKit.scaleOf(frame)
			scale.Scale = 0.6
			UIKit.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			SoundPlayer.play("Click")
			if window.OnOpen then
				window.OnOpen()
			end
		end,
		Close = function(window: Window)
			if openWindow == window then
				openWindow = nil
			end
			frame.Visible = false
		end,
		IsOpen = function(_window: Window): boolean
			return frame.Visible
		end,
	}

	local close = UIKit.button(header, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = Colors.Red,
		Text = "✕",
		ZIndex = 23,
	}, function()
		SoundPlayer.play("Click")
		self:Close()
	end)
	UIKit.stroke(close, Color3.fromRGB(150, 30, 30), 3)
	UIKit.padding(close, 8)

	return self
end

function Window.isAnyOpen(): boolean
	return openWindow ~= nil
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
