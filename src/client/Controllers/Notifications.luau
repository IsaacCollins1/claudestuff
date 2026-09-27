--!strict
-- Banner notifications ("🚚 DELIVERY ARRIVED!", "✨ RAINBOW COLA!") and the
-- "DELIVERY OPENED!" card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local SoundPlayer = require(script.Parent.SoundPlayer)
local UIKit = require(script.Parent.UIKit)

local Colors = UIKit.Colors

local Notifications = {}

local container: Frame
local cardHolder: Frame
local activeCard: Frame? = nil

local STYLES: { [string]: { Color: Color3, Dark: Color3, Duration: number, Sound: string? } } = {
	Delivery = { Color = Colors.Orange, Dark = Color3.fromRGB(170, 80, 0), Duration = 2.6, Sound = "Delivery" },
	Rare = { Color = Colors.Purple, Dark = Color3.fromRGB(70, 30, 140), Duration = 3.5, Sound = "Rare" },
	Upgrade = { Color = Colors.Green, Dark = Colors.GreenDark, Duration = 2.2, Sound = nil },
	Expand = { Color = Colors.Pink, Dark = Color3.fromRGB(150, 30, 90), Duration = 3.5, Sound = "Upgrade" },
	Info = { Color = Colors.Panel, Dark = Colors.Dark, Duration = 2.6, Sound = nil },
	Error = { Color = Colors.Red, Dark = Color3.fromRGB(140, 30, 30), Duration = 2.2, Sound = "Error" },
}

function Notifications.init(screen: ScreenGui)
	container = UIKit.new("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 118),
		Size = UDim2.fromOffset(460, 260),
		BackgroundTransparency = 1,
	}, screen)
	UIKit.new("UIListLayout", {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, container)

	cardHolder = UIKit.new("Frame", {
		Name = "BoxCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(330, 200),
		BackgroundTransparency = 1,
	}, screen)

	Remotes.event("Notify").OnClientEvent:Connect(function(kind: string, text: string)
		Notifications.show(kind, text)
	end)
end

local order = 0

function Notifications.show(kind: string, text: string)
	local style = STYLES[kind] or STYLES.Info
	order += 1
	local banner = UIKit.new("Frame", {
		Name = "Banner",
		Size = UDim2.fromOffset(if kind == "Rare" or kind == "Expand" then 440 else 400, if kind == "Info" then 44 else 54),
		BackgroundColor3 = style.Color,
		LayoutOrder = order,
	}, nil)
	UIKit.corner(banner, UDim.new(1, 0))
	UIKit.stroke(banner, style.Dark, 3)
	local label = UIKit.label(banner, text, { Size = UDim2.new(1, -30, 1, -12), Position = UDim2.fromOffset(15, 6) })
	UIKit.textStroke(label, style.Dark, 2)

	if kind == "Rare" then
		banner.BackgroundColor3 = Colors.White
		local gradient = UIKit.new("UIGradient", { Color = UIKit.rainbow() }, banner)
		local connection
		connection = RunService.RenderStepped:Connect(function()
			if not banner.Parent then
				connection:Disconnect()
				return
			end
			gradient.Offset = Vector2.new((os.clock() * 0.6) % 2 - 1, 0)
		end)
	end

	banner.Parent = container
	-- Keep at most 4 banners on screen.
	local banners = {}
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			table.insert(banners, child)
		end
	end
	table.sort(banners, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #banners > 4 do
		local oldest = table.remove(banners, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	local scale = UIKit.scaleOf(banner)
	scale.Scale = 0.3
	UIKit.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	if style.Sound then
		SoundPlayer.play(style.Sound)
	end
	task.delay(style.Duration, function()
		if banner.Parent then
			UIKit.tween(scale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.wait(0.26)
			banner:Destroy()
		end
	end)
end

-- "DELIVERY OPENED!  🥤 Cola x10"
function Notifications.boxOpened(contents: { { Key: string, Count: number } })
	if activeCard then
		activeCard:Destroy()
	end
	local rows = math.min(#contents, 4)
	local card = UIKit.new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(320, 64 + rows * 40),
		BackgroundColor3 = Colors.Dark,
		BackgroundTransparency = 0.05,
	}, nil)
	UIKit.corner(card, UDim.new(0, 20))
	UIKit.stroke(card, Colors.Yellow, 4)
	local title = UIKit.label(card, "DELIVERY OPENED!", {
		Size = UDim2.new(1, -24, 0, 36),
		Position = UDim2.fromOffset(12, 10),
		TextColor3 = Colors.Yellow,
	})
	UIKit.textStroke(title, Color3.fromRGB(120, 80, 0), 2)
	for index = 1, rows do
		local entry = contents[index]
		local rare = Items.isRare(entry.Key)
		local variant = Items.variant(entry.Key)
		local row = UIKit.label(card, `{Items.icon(entry.Key)} {Items.displayName(entry.Key)} x{entry.Count}`, {
			Size = UDim2.new(1, -24, 0, 34),
			Position = UDim2.fromOffset(12, 50 + (index - 1) * 40),
			TextColor3 = if rare then variant.Color else Colors.White,
		})
		if rare then
			UIKit.textStroke(row, Colors.Dark, 2)
		end
	end
	card.Parent = cardHolder
	activeCard = card
	local scale = UIKit.scaleOf(card)
	scale.Scale = 0.2
	UIKit.tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.8, function()
		if card.Parent then
			UIKit.tween(scale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.wait(0.26)
			card:Destroy()
			if activeCard == card then
				activeCard = nil
			end
		end
	end)
end

return Notifications
