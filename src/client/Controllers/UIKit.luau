--!strict
-- Tiny helpers for building the rounded, colourful UI in code.

local TweenService = game:GetService("TweenService")

local UIKit = {}

UIKit.Font = Enum.Font.FredokaOne

UIKit.Colors = {
	Dark = Color3.fromRGB(26, 28, 42),
	Panel = Color3.fromRGB(38, 41, 60),
	PanelLight = Color3.fromRGB(54, 58, 84),
	White = Color3.fromRGB(255, 255, 255),
	Green = Color3.fromRGB(70, 210, 90),
	GreenDark = Color3.fromRGB(35, 140, 60),
	Blue = Color3.fromRGB(60, 150, 255),
	BlueDark = Color3.fromRGB(30, 90, 200),
	Yellow = Color3.fromRGB(255, 205, 50),
	Orange = Color3.fromRGB(255, 150, 40),
	Red = Color3.fromRGB(255, 80, 80),
	Pink = Color3.fromRGB(255, 90, 170),
	Purple = Color3.fromRGB(150, 90, 255),
	Grey = Color3.fromRGB(120, 124, 140),
	Gold = Color3.fromRGB(255, 196, 37),
}

-- Create an instance, set properties, parent it last.
function UIKit.new(className: string, props: { [string]: any }?, parent: Instance?): any
	local instance = Instance.new(className :: any)
	if props then
		for key, value in props do
			(instance :: any)[key] = value
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UIKit.corner(parent: Instance, radius: UDim?): UICorner
	return UIKit.new("UICorner", { CornerRadius = radius or UDim.new(0, 14) }, parent)
end

function UIKit.stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	return UIKit.new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

function UIKit.textStroke(parent: Instance, color: Color3, thickness: number): UIStroke
	return UIKit.new("UIStroke", {
		Color = color,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

function UIKit.padding(parent: Instance, pixels: number): UIPadding
	local p = UDim.new(0, pixels)
	return UIKit.new("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p }, parent)
end

function UIKit.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	return UIKit.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	}, parent)
end

function UIKit.rainbow(): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 190, 60)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(110, 230, 90)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 190, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(160, 100, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 190)),
	})
end

function UIKit.label(parent: Instance?, text: string, props: { [string]: any }?): TextLabel
	local label = UIKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = UIKit.Font,
		Text = text,
		TextColor3 = UIKit.Colors.White,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
	}, nil)
	if props then
		for key, value in props do
			(label :: any)[key] = value
		end
	end
	label.Parent = parent
	return label
end

function UIKit.tween(instance: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

-- Every GuiObject that wants pop/press animations gets a UIScale.
function UIKit.scaleOf(object: GuiObject): UIScale
	local existing = object:FindFirstChild("PopScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	return UIKit.new("UIScale", { Name = "PopScale" }, object)
end

-- Quick "boing" pop.
function UIKit.pop(object: GuiObject, amount: number?)
	local scale = UIKit.scaleOf(object)
	scale.Scale = 1 + (amount or 0.15)
	UIKit.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

-- Horizontal shake for "can't afford" feedback.
function UIKit.shake(object: GuiObject)
	local origin = object.Position
	task.spawn(function()
		for _, dx in { -8, 8, -6, 6, -3, 0 } do
			object.Position = origin + UDim2.fromOffset(dx, 0)
			task.wait(0.03)
		end
		object.Position = origin
	end)
end

-- Chunky button with a press animation.
function UIKit.button(parent: Instance, props: { [string]: any }, onClick: () -> ()): TextButton
	local button = UIKit.new("TextButton", {
		AutoButtonColor = false,
		Font = UIKit.Font,
		TextColor3 = UIKit.Colors.White,
		TextScaled = true,
		BorderSizePixel = 0,
	}, nil)
	for key, value in props do
		(button :: any)[key] = value
	end
	UIKit.corner(button)
	local scale = UIKit.scaleOf(button)
	button.MouseButton1Down:Connect(function()
		UIKit.tween(scale, 0.08, { Scale = 0.92 })
	end)
	button.MouseButton1Up:Connect(function()
		UIKit.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		UIKit.tween(scale, 0.2, { Scale = 1 })
	end)
	button.Activated:Connect(onClick)
	button.Parent = parent
	return button
end

return UIKit
