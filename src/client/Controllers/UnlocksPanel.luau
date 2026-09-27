--!strict
-- 📖 ITEMS: every product in the game. Unlocked ones spin in 3D with their
-- stars (sell more to earn stars, each +10% price); locked ones are dark
-- silhouettes showing the level that unlocks them. Also shows the big
-- "LEVEL UP!" popup when you reach a new level.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local ProductVisuals = require(Shared:WaitForChild("ProductVisuals"))
local Products = require(Shared:WaitForChild("Products"))
local Progression = require(Shared:WaitForChild("Progression"))

local Effects = require(script.Parent.Effects)
local SoundPlayer = require(script.Parent.SoundPlayer)
local State = require(script.Parent.State)
local UIKit = require(script.Parent.UIKit)
local Window = require(script.Parent.Window)

local Colors = UIKit.Colors

local UnlocksPanel = {}

type Card = {
	Frame: Frame,
	Viewport: ViewportFrame,
	Model: Model,
	Spin: number,
	Lock: Frame,
	LockLabel: TextLabel,
	Price: TextLabel,
	Stars: TextLabel,
	Track: Frame,
	Fill: Frame,
	Progress: TextLabel,
}

local screen: ScreenGui
local window: Window.Window
local cards: { [string]: Card } = {}

local function preview(parent: Instance, productId: string): (ViewportFrame, Model)
	local viewport = UIKit.new("ViewportFrame", {
		Name = "Preview",
		Size = UDim2.new(1, -16, 0, 84),
		Position = UDim2.fromOffset(8, 8),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(190, 190, 200),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
		ZIndex = 24,
	}, parent)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local model = ProductVisuals.build(productId)
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	local center, size = model:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z) * 0.62
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2))
	camera.CFrame = CFrame.lookAt(center.Position + Vector3.new(0, radius * 0.45, -distance), center.Position)
	return viewport, model
end

local function makeCard(parent: Instance, product: Products.Product, order: number): Card
	local rarity = Products.Rarities[product.Rarity]
	local frame = UIKit.new("Frame", {
		Name = product.Id,
		BackgroundColor3 = Colors.PanelLight,
		LayoutOrder = order,
		ZIndex = 22,
	}, parent)
	UIKit.corner(frame, UDim.new(0, 16))
	UIKit.stroke(frame, rarity.Color, 3)
	UIKit.gradient(frame, Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 210))
	local viewport, model = preview(frame, product.Id)
	UIKit.title(frame, product.Name, {
		Name = "ProductName",
		Size = UDim2.new(1, -12, 0, 20),
		Position = UDim2.fromOffset(6, 94),
		ZIndex = 29, -- stays readable over the lock
	}, Colors.Outline, 2)
	local price = UIKit.title(frame, "£0", {
		Name = "Price",
		Size = UDim2.new(1, -12, 0, 18),
		Position = UDim2.fromOffset(6, 115),
		TextColor3 = Colors.Green,
		ZIndex = 24,
	}, Colors.Outline, 2)
	local stars = UIKit.title(frame, "☆☆☆☆☆", {
		Name = "Stars",
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.fromOffset(10, 135),
		TextColor3 = Colors.Yellow,
		ZIndex = 24,
	}, Colors.Outline, 1.5)
	local track = UIKit.new("Frame", {
		Name = "Track",
		Size = UDim2.new(1, -20, 0, 16),
		Position = UDim2.fromOffset(10, 158),
		BackgroundColor3 = Colors.Dark,
		ZIndex = 24,
	}, frame)
	UIKit.corner(track, UDim.new(1, 0))
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Yellow,
		ZIndex = 25,
	}, track)
	UIKit.corner(fill, UDim.new(1, 0))
	local progress = UIKit.title(track, "0/20", {
		Name = "Progress",
		Size = UDim2.new(1, -6, 1, -2),
		Position = UDim2.fromOffset(3, 1),
		ZIndex = 26,
	}, Colors.Outline, 1.5)

	-- Locked overlay: dark glass with a padlock over the silhouette and the
	-- unlock level where the price and stars go.
	local lock = UIKit.new("Frame", {
		Name = "Lock",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Dark,
		BackgroundTransparency = 0.25,
		Visible = false,
		ZIndex = 27,
	}, frame)
	UIKit.corner(lock, UDim.new(0, 16))
	UIKit.label(lock, "🔒", {
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.new(0.5, -22, 0, 26),
		ZIndex = 28,
	})
	local lockLabel = UIKit.title(lock, "LV 10", {
		Name = "Needs",
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.fromOffset(8, 126),
		TextColor3 = Colors.Yellow,
		ZIndex = 28,
	}, Colors.Outline, 2)

	return {
		Frame = frame,
		Viewport = viewport,
		Model = model,
		Spin = math.random() * 6,
		Lock = lock,
		LockLabel = lockLabel,
		Price = price,
		Stars = stars,
		Track = track,
		Fill = fill,
		Progress = progress,
	}
end

local function starText(stars: number): string
	return string.rep("★", stars) .. string.rep("☆", Progression.MaxStars - stars)
end

local function refresh()
	local data = State.Data
	if not data or not data.Level then
		return
	end
	for id, card in cards do
		local product = Products.ById[id]
		local unlocked = Progression.isUnlocked(product, data.Level)
		local sold = data.Sold[id] or 0
		local stars = Progression.stars(sold)
		card.Lock.Visible = not unlocked
		card.LockLabel.Text = `LEVEL {product.UnlockLevel}`
		card.Price.Visible = unlocked
		card.Stars.Visible = unlocked
		card.Track.Visible = unlocked
		-- Locked products are black silhouettes.
		card.Viewport.ImageColor3 = if unlocked then Colors.White else Color3.new(0, 0, 0)
		card.Viewport.ImageTransparency = if unlocked then 0 else 0.35
		card.Price.Text = Format.money(product.SellPrice) .. (if stars > 0 then ` +{math.floor(stars * Progression.StarBonus * 100 + 0.5)}%` else " each")
		card.Stars.Text = starText(stars)
		local nextAt = Progression.nextStarAt(sold)
		if nextAt then
			local previous = if stars > 0 then Progression.StarThresholds[stars] else 0
			card.Fill.Size = UDim2.fromScale(math.clamp((sold - previous) / (nextAt - previous), 0, 1), 1)
			card.Progress.Text = `{Format.commas(sold)}/{Format.commas(nextAt)} sold`
		else
			card.Fill.Size = UDim2.fromScale(1, 1)
			card.Progress.Text = "MAX ★"
		end
	end
	local nextProduct = Progression.nextUnlock(data.Level)
	window.Subtitle.Text = if nextProduct
		then `Level {data.Level} · next: {nextProduct.Icon} {nextProduct.Name} at level {nextProduct.UnlockLevel}`
		else `Level {data.Level} · everything unlocked!`
end

-- "LEVEL UP!" popup with anything that just unlocked.
local function levelUp(payload: { [string]: any })
	local level = if type(payload.Level) == "number" then payload.Level else 0
	local unlocked = if type(payload.Unlocked) == "table" then payload.Unlocked else {}
	local reward = if type(payload.Reward) == "number" then payload.Reward else 0
	local popup = UIKit.new("Frame", {
		Name = "LevelUp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(380, if #unlocked > 0 then 170 else 120),
		BackgroundColor3 = Colors.Purple,
		ZIndex = 55,
	}, screen)
	UIKit.corner(popup, UDim.new(0, 24))
	UIKit.stroke(popup, Colors.Outline, 4)
	UIKit.gradient(popup, Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 130, 230))
	UIKit.shine(popup, UDim.new(0, 24), 1)
	UIKit.title(popup, `LEVEL {level}!`, {
		Size = UDim2.new(1, -30, 0, 50),
		Position = UDim2.fromOffset(15, 12),
		ZIndex = 56,
	}, Colors.PurpleDark, 4)
	UIKit.title(popup, "+" .. Format.money(reward), {
		Size = UDim2.new(1, -30, 0, 30),
		Position = UDim2.fromOffset(15, 66),
		TextColor3 = Color3.fromRGB(140, 255, 140),
		ZIndex = 56,
	}, Colors.Outline, 3)
	if #unlocked > 0 then
		local names = {}
		for _, id in unlocked do
			local product = Products.ById[id]
			if product then
				table.insert(names, `{product.Icon} {product.Name}`)
			end
		end
		UIKit.title(popup, "NEW: " .. table.concat(names, ", "), {
			Size = UDim2.new(1, -30, 0, 34),
			Position = UDim2.fromOffset(15, 108),
			TextColor3 = Colors.Yellow,
			ZIndex = 56,
		}, Colors.Outline, 3)
	end
	UIKit.popIn(popup, 0.45)
	SoundPlayer.play("StepDone", 1.1)
	Effects.confetti(if #unlocked > 0 then 45 else 25)
	task.delay(if #unlocked > 0 then 3.2 else 2.2, function()
		UIKit.tween(UIKit.scaleOf(popup), 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.27)
		popup:Destroy()
	end)
	if window:IsOpen() then
		refresh()
	end
end

function UnlocksPanel.init(gui: ScreenGui)
	screen = gui
	window = Window.new(screen, { Title = "ITEMS", Icon = "📖", Color = Colors.Blue:Lerp(Colors.Purple, 0.5), Width = 800, Height = 520 })
	local grid = UIKit.new("ScrollingFrame", {
		Name = "Grid",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Colors.Grey,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 22,
	}, window.Content)
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(134, 184),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, grid)
	UIKit.padding(grid, 8)
	for order, product in Products.List do
		cards[product.Id] = makeCard(grid, product, order)
	end
	window.OnOpen = refresh
	State.Changed:Connect(function()
		if window:IsOpen() then
			refresh()
		end
	end)
	Effects.on("LevelUp", levelUp)
	Effects.on("Star", function()
		if window:IsOpen() then
			refresh()
		end
	end)
	-- Unlocked products spin slowly while the menu is open.
	RunService.RenderStepped:Connect(function(dt: number)
		if not window:IsOpen() then
			return
		end
		for _, card in cards do
			if not card.Lock.Visible then
				card.Spin += dt * 1.2
				card.Model:PivotTo(CFrame.Angles(0, card.Spin, 0))
			end
		end
	end)
end

function UnlocksPanel.toggle()
	Window.toggle(window)
end

function UnlocksPanel.isOpen(): boolean
	return window:IsOpen()
end

return UnlocksPanel
