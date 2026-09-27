--!strict
-- Building blocks for the chunky, bouncy "simulator" style UI.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UIKit = {}

UIKit.Font = Enum.Font.FredokaOne -- body text
UIKit.Title = Enum.Font.LuckiestGuy -- big numbers, buttons, headings
-- The Robux logo. It ships inside every Roblox client, so it needs no upload.
UIKit.RobuxImage = "rbxasset://textures/ui/common/robux.png"

UIKit.Colors = {
	Dark = Color3.fromRGB(26, 28, 42),
	Outline = Color3.fromRGB(20, 20, 32),
	Panel = Color3.fromRGB(40, 43, 64),
	PanelLight = Color3.fromRGB(58, 62, 92),
	White = Color3.fromRGB(255, 255, 255),
	Green = Color3.fromRGB(80, 220, 90),
	GreenDark = Color3.fromRGB(30, 140, 50),
	Blue = Color3.fromRGB(70, 160, 255),
	BlueDark = Color3.fromRGB(25, 90, 200),
	Yellow = Color3.fromRGB(255, 210, 50),
	Gold = Color3.fromRGB(255, 196, 37),
	GoldDark = Color3.fromRGB(190, 120, 0),
	Orange = Color3.fromRGB(255, 150, 40),
	Red = Color3.fromRGB(255, 75, 85),
	RedDark = Color3.fromRGB(170, 25, 40),
	Pink = Color3.fromRGB(255, 90, 170),
	Purple = Color3.fromRGB(160, 95, 255),
	PurpleDark = Color3.fromRGB(90, 40, 180),
	Grey = Color3.fromRGB(130, 134, 150),
	GreyDark = Color3.fromRGB(80, 84, 100),
}

function UIKit.darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

function UIKit.lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

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

-- Big outlined heading text (LuckiestGuy with a dark stroke).
function UIKit.title(parent: Instance?, text: string, props: { [string]: any }?, strokeColor: Color3?, strokeThickness: number?): TextLabel
	local label = UIKit.label(parent, text, props)
	label.Font = UIKit.Title
	UIKit.textStroke(label, strokeColor or UIKit.Colors.Outline, strokeThickness or 3)
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

-- Appear with a bounce from nothing.
function UIKit.popIn(object: GuiObject, time: number?)
	local scale = UIKit.scaleOf(object)
	scale.Scale = 0.2
	UIKit.tween(scale, time or 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
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

-- A shiny highlight band that sweeps across a (rounded) GuiObject now and then.
function UIKit.shine(object: GuiObject, radius: UDim?, interval: number?)
	local shine = UIKit.new("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UIKit.Colors.White,
		BorderSizePixel = 0,
		ZIndex = object.ZIndex + 2,
	}, object)
	UIKit.corner(shine, radius)
	local gradient = UIKit.new("UIGradient", {
		Rotation = 20,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1, 0),
	}, shine)
	task.spawn(function()
		while shine.Parent do
			gradient.Offset = Vector2.new(-1, 0)
			UIKit.tween(gradient, 0.7, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.wait(interval or 3)
		end
	end)
end

-- Gentle idle bob so important buttons feel alive.
function UIKit.wobble(object: GuiObject, degrees: number?)
	local amount = degrees or 4
	local offset = math.random() * 10
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not object.Parent then
			connection:Disconnect()
			return
		end
		object.Rotation = math.sin(os.clock() * 2.2 + offset) * amount
	end)
end

-- Gold "£" coin icon.
function UIKit.coin(parent: Instance?, size: number, props: { [string]: any }?): Frame
	local coin = UIKit.new("Frame", {
		Name = "Coin",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = UIKit.Colors.Gold,
	}, nil)
	UIKit.corner(coin, UDim.new(1, 0))
	UIKit.stroke(coin, UIKit.Colors.GoldDark, math.max(2, size / 16))
	UIKit.gradient(coin, Color3.fromRGB(255, 255, 255), Color3.fromRGB(230, 200, 150))
	UIKit.title(coin, "£", {
		Size = UDim2.fromScale(0.7, 0.7),
		Position = UDim2.fromScale(0.15, 0.17),
		TextColor3 = Color3.fromRGB(255, 250, 220),
	}, UIKit.Colors.GoldDark, math.max(1.5, size / 22))
	if props then
		for key, value in props do
			(coin :: any)[key] = value
		end
	end
	coin.Parent = parent
	return coin
end

-- White Robux logo with a dark drop shadow so it reads on any colour.
function UIKit.robuxIcon(parent: Instance?, size: number, props: { [string]: any }?): Frame
	local holder = UIKit.new("Frame", {
		Name = "RobuxIcon",
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	}, nil)
	if props then
		for key, value in props do
			(holder :: any)[key] = value
		end
	end
	local shadowOffset = math.max(1, math.floor(size / 12))
	UIKit.new("ImageLabel", {
		Name = "Shadow",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(shadowOffset, shadowOffset),
		BackgroundTransparency = 1,
		Image = UIKit.RobuxImage,
		ImageColor3 = UIKit.Colors.Outline,
		ImageTransparency = 0.3,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = holder.ZIndex,
	}, holder)
	UIKit.new("ImageLabel", {
		Name = "Logo",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = UIKit.RobuxImage,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = holder.ZIndex + 1,
	}, holder)
	holder.Parent = parent
	return holder
end

export type RobuxPrice = {
	Frame: Frame,
	Icon: Frame,
	Amount: TextLabel,
	-- Show a Robux price, or plain text (e.g. "OWNED ✔") without the logo.
	Set: (amount: number?, text: string?) -> (),
}

-- "[R$ logo] 249" centred inside `parent` (e.g. a chunky button's face).
function UIKit.robuxPrice(parent: Instance, textSize: number, strokeColor: Color3, zIndex: number): RobuxPrice
	local row = UIKit.new("Frame", {
		Name = "Price",
		Size = UDim2.new(1, -12, 0.8, 0),
		Position = UDim2.new(0, 6, 0.1, 0),
		BackgroundTransparency = 1,
		ZIndex = zIndex,
	}, parent)
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, math.floor(textSize / 5)),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local icon = UIKit.robuxIcon(row, textSize, { LayoutOrder = 1, ZIndex = zIndex })
	local amount = UIKit.title(row, "0", {
		Name = "Amount",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, textSize + 4),
		TextScaled = false,
		TextSize = textSize,
		LayoutOrder = 2,
		ZIndex = zIndex,
	}, strokeColor, 2.5)
	return {
		Frame = row,
		Icon = icon,
		Amount = amount,
		Set = function(price: number?, text: string?)
			icon.Visible = price ~= nil
			amount.Text = if price then tostring(price) else (text or "")
		end,
	}
end

function UIKit.badge(parent: Instance, color: Color3, text: string): (Frame, TextLabel)
	local frame = UIKit.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = color,
		Visible = false,
		ZIndex = 20,
	}, parent)
	UIKit.corner(frame, UDim.new(1, 0))
	UIKit.stroke(frame, UIKit.Colors.White, 3)
	local label = UIKit.title(frame, text, {
		Size = UDim2.fromScale(0.78, 0.78),
		Position = UDim2.fromScale(0.11, 0.13),
		ZIndex = 21,
	}, UIKit.darken(color, 0.5), 1.5)
	return frame, label
end

export type Chunky = {
	Button: TextButton,
	Face: Frame,
	Base: Frame,
	Icon: TextLabel?,
	Text: TextLabel?,
	SetColor: (color: Color3) -> (),
}

-- Chunky 3D button: a coloured face sitting on a darker base; it presses
-- down when clicked and grows a little on hover.
function UIKit.chunky(parent: Instance?, props: { [string]: any }, onClick: () -> ()): Chunky
	local color: Color3 = props.Color or UIKit.Colors.Green
	local depth = props.Depth or 6
	local button = UIKit.new("TextButton", {
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(160, 56),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
	}, nil)
	local z = button.ZIndex
	local base = UIKit.new("Frame", {
		Name = "Base",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UIKit.darken(color, 0.35),
		ZIndex = z,
	}, button)
	local radius = props.Radius or UDim.new(0, 14)
	UIKit.corner(base, radius)
	UIKit.stroke(base, UIKit.Colors.Outline, props.StrokeThickness or 3)
	local face = UIKit.new("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -depth),
		BackgroundColor3 = color,
		ZIndex = z + 1,
	}, button)
	UIKit.corner(face, radius)
	UIKit.gradient(face, Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 205, 205))
	-- Glossy highlight on the top half.
	local gloss = UIKit.new("Frame", {
		Name = "Gloss",
		Size = UDim2.new(1, -8, 0.42, 0),
		Position = UDim2.fromOffset(4, 3),
		BackgroundColor3 = UIKit.Colors.White,
		BackgroundTransparency = 0.72,
		ZIndex = z + 2,
	}, face)
	UIKit.corner(gloss, radius)

	local icon: TextLabel? = nil
	local text: TextLabel? = nil
	if props.Icon and props.Text then
		icon = UIKit.label(face, props.Icon, {
			Name = "Icon",
			Size = UDim2.fromScale(0.62, 0.56),
			Position = UDim2.fromScale(0.19, 0.06),
			ZIndex = z + 3,
		})
		text = UIKit.title(face, props.Text, {
			Name = "Label",
			Size = UDim2.fromScale(0.9, 0.3),
			Position = UDim2.fromScale(0.05, 0.64),
			ZIndex = z + 3,
		}, UIKit.darken(color, 0.55), 2)
	elseif props.Icon then
		icon = UIKit.label(face, props.Icon, {
			Name = "Icon",
			Size = UDim2.fromScale(0.72, 0.72),
			Position = UDim2.fromScale(0.14, 0.14),
			ZIndex = z + 3,
		})
	elseif props.Text then
		text = UIKit.title(face, props.Text, {
			Name = "Label",
			Size = UDim2.new(1, -16, 0.72, 0),
			Position = UDim2.new(0, 8, 0.14, 0),
			ZIndex = z + 3,
		}, UIKit.darken(color, 0.55), props.TextStroke or 2.5)
		if props.MaxTextSize then
			UIKit.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize }, text)
		end
	end

	local scale = UIKit.scaleOf(button)
	local function press()
		UIKit.tween(face, 0.06, { Position = UDim2.fromOffset(0, depth - 2) })
	end
	local function release()
		UIKit.tween(face, 0.12, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
	end
	button.MouseButton1Down:Connect(press)
	button.MouseButton1Up:Connect(release)
	button.MouseEnter:Connect(function()
		UIKit.tween(scale, 0.15, { Scale = 1.06 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		release()
		UIKit.tween(scale, 0.15, { Scale = 1 })
	end)
	button.Activated:Connect(onClick)
	button.Parent = parent

	local chunky: Chunky = {
		Button = button,
		Face = face,
		Base = base,
		Icon = icon,
		Text = text,
		SetColor = function(newColor: Color3)
			face.BackgroundColor3 = newColor
			base.BackgroundColor3 = UIKit.darken(newColor, 0.35)
			if text then
				local stroke = text:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = UIKit.darken(newColor, 0.55)
				end
			end
		end,
	}
	return chunky
end

-- Dark translucent rounded "pill" panel.
function UIKit.pill(parent: Instance?, props: { [string]: any }): Frame
	local frame = UIKit.new("Frame", {
		BackgroundColor3 = UIKit.Colors.Dark,
		BackgroundTransparency = 0.15,
	}, nil)
	for key, value in props do
		(frame :: any)[key] = value
	end
	UIKit.corner(frame, UDim.new(1, 0))
	UIKit.stroke(frame, UIKit.Colors.Outline, 3)
	frame.Parent = parent
	return frame
end

return UIKit
