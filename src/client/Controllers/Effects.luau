--!strict
-- World-space feedback: box opening animation, money popups, products
-- popping onto shelves, rainbow items, confetti, sounds. Particles come from
-- the pooled, budgeted effects in Particles.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoxVisual = require(Shared:WaitForChild("BoxVisual"))
local Format = require(Shared:WaitForChild("Format"))
local Items = require(Shared:WaitForChild("Items"))
local ProductVisuals = require(Shared:WaitForChild("ProductVisuals"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local HUD = require(script.Parent.HUD)
local Notifications = require(script.Parent.Notifications)
local Particles = require(script.Parent.Particles)
local SoundPlayer = require(script.Parent.SoundPlayer)
local UIKit = require(script.Parent.UIKit)

local Colors = UIKit.Colors
local player = Players.LocalPlayer
local rng = Random.new()

local Effects = {}

local screen: ScreenGui? = nil
local extraHandlers: { [string]: { (payload: { [string]: any }) -> () } } = {}

-- Other controllers can listen to server effects too (e.g. the tutorial).
function Effects.on(name: string, handler: (payload: { [string]: any }) -> ())
	extraHandlers[name] = extraHandlers[name] or {}
	table.insert(extraHandlers[name], handler)
end

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 80, 90),
	Color3.fromRGB(255, 205, 50),
	Color3.fromRGB(90, 220, 100),
	Color3.fromRGB(70, 160, 255),
	Color3.fromRGB(170, 100, 255),
	Color3.fromRGB(255, 120, 200),
}

-- Screen confetti raining down.
function Effects.confetti(count: number?)
	local gui = screen
	if not gui then
		return
	end
	for _ = 1, count or 60 do
		local piece = UIKit.new("Frame", {
			Name = "Confetti",
			Size = UDim2.fromOffset(rng:NextInteger(8, 14), rng:NextInteger(12, 20)),
			Position = UDim2.new(rng:NextNumber(0.05, 0.95), 0, 0, rng:NextInteger(-80, -10)),
			BackgroundColor3 = CONFETTI_COLORS[rng:NextInteger(1, #CONFETTI_COLORS)],
			Rotation = rng:NextInteger(0, 360),
			BorderSizePixel = 0,
			ZIndex = 80,
		}, gui)
		local duration = rng:NextNumber(1.4, 2.4)
		UIKit.tween(piece, duration, {
			Position = piece.Position + UDim2.new(rng:NextNumber(-0.12, 0.12), 0, 1.05, 0),
			Rotation = piece.Rotation + rng:NextInteger(-540, 540),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(duration, function()
			piece:Destroy()
		end)
	end
end

local function cameraPosition(): Vector3
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else Vector3.zero
end

local function near(position: Vector3, distance: number): boolean
	return (cameraPosition() - position).Magnitude <= distance
end

-- Invisible anchored part used to hold billboards/particles/sounds.
local function anchorAt(position: Vector3, lifetime: number): Part
	local part = Instance.new("Part")
	part.Name = "EffectAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = position
	part.Parent = workspace
	Debris:AddItem(part, lifetime)
	return part
end

-- Floating text that rises and fades ("+£24").
local function floatText(position: Vector3, text: string, color: Color3, size: number, rainbow: boolean?)
	local anchor = anchorAt(position, 2)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(size * 3.2, size)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Parent = anchor
	local label = UIKit.label(gui, text, { TextColor3 = color })
	UIKit.textStroke(label, Colors.Dark, 3)
	if rainbow then
		label.TextColor3 = Colors.White
		UIKit.new("UIGradient", { Color = UIKit.rainbow() }, label)
	end
	local scale = UIKit.scaleOf(label)
	scale.Scale = 0.3
	UIKit.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	UIKit.tween(gui, 1.4, { StudsOffsetWorldSpace = Vector3.new(0, 4, 0) })
	task.delay(0.9, function()
		UIKit.tween(label, 0.5, { TextTransparency = 1 })
	end)
end

-- The local player's root part and the ground under their feet.
local function playerSpot(): (BasePart?, Vector3?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil, nil
	end
	-- Feet = the bottom of the lowest body part (where the character touches the ground).
	local lowest = root.Position.Y - root.Size.Y / 2
	for _, part in (character :: Model):GetChildren() do
		if part:IsA("BasePart") and part ~= root then
			lowest = math.min(lowest, part.Position.Y - part.Size.Y / 2)
		end
	end
	return root, Vector3.new(root.Position.X, lowest + 0.08, root.Position.Z)
end

-- Beam colour for the rarest thing in a box.
local function rareBeamColor(contents: { { Key: string, Count: number } }): Color3?
	local best: string? = nil
	local rank = { Golden = 1, Rainbow = 2, Giant = 3 }
	for _, entry in contents do
		local id = Items.variant(entry.Key).Id
		if rank[id] and (not best or rank[id] > rank[best]) then
			best = id
		end
	end
	if best == "Giant" then
		return Color3.fromRGB(90, 255, 170)
	elseif best == "Rainbow" then
		return Color3.fromRGB(255, 120, 230)
	elseif best == "Golden" then
		return Particles.Colors.Gold
	end
	return nil
end

-- Animate a value from 0 to 1 over `duration`, calling `step(alpha)` each frame.
local function animate(duration: number, step: (alpha: number) -> ())
	local start = os.clock()
	while true do
		local alpha = math.min((os.clock() - start) / duration, 1)
		step(alpha)
		if alpha >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

local function ease(alpha: number, style: Enum.EasingStyle, direction: Enum.EasingDirection): number
	return TweenService:GetValue(alpha, style, direction)
end

-- Box opening -------------------------------------------------------------------

local function boxOpen(payload: { [string]: any })
	local cframe = payload.CFrame :: CFrame
	local contents = payload.Contents :: { { Key: string, Count: number } }
	local mine = payload.OwnerId == player.UserId
	if typeof(cframe) ~= "CFrame" or type(contents) ~= "table" or #contents == 0 then
		return
	end
	if not mine and not near(cframe.Position, 90) then
		return
	end

	local tape = if typeof(payload.TapeColor) == "Color3" then payload.TapeColor else Color3.fromRGB(196, 150, 96)
	local box = BoxVisual.build(tape, true)
	box.Model:PivotTo(cframe)
	box.Model.Parent = workspace
	local size = BoxVisual.Size

	-- 1) Shake
	SoundPlayer.play("BoxShake", 1, cframe.Position)
	for i = 1, 6 do
		local tilt = if i % 2 == 0 then 1 else -1
		box.Model:PivotTo(cframe * CFrame.new(0, 0.1 * (i % 2), 0) * CFrame.Angles(math.rad(3 * tilt), 0, math.rad(7 * tilt)))
		task.wait(0.05)
	end
	box.Model:PivotTo(cframe)

	-- 2) Flaps swing open
	SoundPlayer.play("BoxOpen", 1, cframe.Position)
	local left, right = box.FlapLeft, box.FlapRight
	local hingeY = size.Y / 2 + 0.04
	animate(0.18, function(alpha)
		local angle = math.rad(115) * ease(alpha, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if left then
			left.CFrame = cframe * CFrame.new(-size.X / 2, hingeY, 0) * CFrame.Angles(0, 0, angle) * CFrame.new(size.X / 4, 0, 0)
		end
		if right then
			right.CFrame = cframe * CFrame.new(size.X / 2, hingeY, 0) * CFrame.Angles(0, 0, -angle) * CFrame.new(-size.X / 4, 0, 0)
		end
	end)

	-- Puff of dust and a burst of confetti as the box pops open.
	local lid = cframe.Position + Vector3.new(0, size.Y / 2, 0)
	Particles.emit("Glow", lid, 1, tape)
	Particles.emit("Confetti", lid, 10, { tape, Particles.Colors.White })
	Particles.dustAround(cframe.Position - Vector3.new(0, size.Y / 2, 0), size.X, 8)

	-- 3) Products pop out (rare ones first), then fly towards the player.
	local keys = {}
	local rare = false
	for index = #contents, 1, -1 do
		local entry = contents[index]
		rare = rare or Items.isRare(entry.Key)
		for _ = 1, math.min(entry.Count, 8 - #keys) do
			table.insert(keys, entry.Key)
		end
	end
	if mine then
		Notifications.boxOpened(contents)
	end
	local top = cframe.Position + Vector3.new(0, size.Y / 2, 0)
	local total = 0
	for _, entry in contents do
		total += entry.Count
	end
	local firstKey = contents[1].Key
	floatText(top + Vector3.new(0, 3.5, 0), `{Items.icon(firstKey)} {Items.product(firstKey).Name} x{total}`, Colors.White, 1.6)
	if rare then
		-- Loot-drop beam in the colour of the rarest item.
		local beamColor = rareBeamColor(contents)
		if beamColor then
			Particles.beam(cframe.Position - Vector3.new(0, size.Y / 2, 0), beamColor)
		end
		Particles.emit("Sparkle", top, 24, Particles.Rainbow)
		SoundPlayer.play("Rare", 1, top)
	end

	for index, key in keys do
		task.spawn(function()
			local item = ProductVisuals.build(key)
			local angle = (index / #keys) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local peak = top + Vector3.new(math.cos(angle) * 2.4, 3.2 + rng:NextNumber(0, 1.2), math.sin(angle) * 2.4)
			item:ScaleTo(0.2)
			item:PivotTo(CFrame.new(top))
			item.Parent = workspace
			SoundPlayer.play("ItemPop", 1 + index * 0.06, top, 0.04)
			animate(0.35, function(alpha)
				local e = ease(alpha, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				item:ScaleTo(0.2 + 1.1 * e)
				item:PivotTo(CFrame.new(top:Lerp(peak, e)) * CFrame.Angles(0, alpha * math.pi * 2, 0))
			end)
			task.wait(0.35)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local destination = if typeof(payload.FlyTo) == "Vector3"
				then payload.FlyTo
				elseif mine and root and root:IsA("BasePart") then root.Position
				else peak + Vector3.new(0, 2, 0)
			local from = item:GetPivot().Position
			animate(0.3, function(alpha)
				local e = ease(alpha, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				item:ScaleTo(math.max(0.05, 1.3 * (1 - e)))
				item:PivotTo(CFrame.new(from:Lerp(destination, e)))
			end)
			item:Destroy()
		end)
		task.wait(0.05)
	end

	-- 4) Empty box shrinks away
	task.wait(0.5)
	animate(0.25, function(alpha)
		box.Model:ScaleTo(math.max(0.05, 1 - ease(alpha, Enum.EasingStyle.Back, Enum.EasingDirection.In)))
	end)
	box.Model:Destroy()
end

-- Handlers ------------------------------------------------------------------------

local handlers: { [string]: (payload: { [string]: any }) -> () } = {}

handlers.BoxOpen = boxOpen

-- Chunky gold coins that pop out of the till.
local function coinBurst(position: Vector3, count: number)
	for _ = 1, count do
		-- A flat gold diamond: a low-poly coin in one part.
		local coin = Instance.new("Part")
		coin.Name = "Coin"
		coin.Size = Vector3.new(0.18, 0.62, 0.62)
		coin.Color = Colors.Gold
		coin.Material = Enum.Material.Metal
		coin.Reflectance = 0.2
		coin.Anchored = true
		coin.CanCollide = false
		coin.CanQuery = false
		coin.CanTouch = false
		coin.CastShadow = false
		coin.CFrame = CFrame.new(position)
		coin.Parent = workspace
		local velocity = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(9, 14), rng:NextNumber(-4, 4))
		local spin = rng:NextNumber(8, 16)
		task.spawn(function()
			animate(0.8, function(alpha)
				local t = alpha * 0.8
				local offset = velocity * t + Vector3.new(0, -26 * t * t, 0)
				-- Square face turned 45° (a diamond), flipping like a tossed coin.
				coin.CFrame = CFrame.new(position + offset) * CFrame.Angles(0, t * spin, 0) * CFrame.Angles(math.rad(45), 0, 0)
				coin.Transparency = math.max(0, alpha - 0.6) * 2.5
			end)
			coin:Destroy()
		end)
	end
end

handlers.Sale = function(payload)
	local position = payload.Position
	if typeof(position) ~= "Vector3" or not near(position, 140) then
		return
	end
	local amount = if type(payload.Amount) == "number" then payload.Amount else 0
	local mine = payload.OwnerId == player.UserId
	coinBurst(position, if payload.Rare then 8 else 4)
	Particles.emit("Sparkle", position, 3, Particles.Colors.Gold)
	if mine then
		HUD.flyCoins(position, amount)
	end
	if type(payload.Multiplier) == "number" and payload.Multiplier > 1 then
		floatText(position + Vector3.new(0, 2, 0), `x{payload.Multiplier} CASH!`, Colors.Yellow, 0.9)
	end
	if payload.Rare then
		floatText(position, "+" .. Format.money(amount), Colors.Gold, 2.2, true)
		Particles.pop(position, Particles.Colors.Gold, 12)
		Particles.emit("Confetti", position, 14, { Particles.Colors.Gold, Particles.Colors.White })
		SoundPlayer.play("Rare", 1, position)
	else
		floatText(position, "+" .. Format.money(amount), Colors.Green, if mine then 1.4 else 1.1)
	end
	SoundPlayer.play(if mine then "Cash" else "CashLow", rng:NextNumber(0.95, 1.1), position)
end

handlers.Stocked = function(payload)
	local position = payload.Position
	if typeof(position) ~= "Vector3" then
		return
	end
	if payload.Full then
		floatText(position, "FULL! ✔", Colors.Green, 1.3)
		SoundPlayer.play("Upgrade", 1.5, position)
		-- The whole shelf glows green for a moment.
		local shelf = payload.Shelf
		if typeof(shelf) == "Instance" then
			Particles.flash(shelf, Particles.Colors.Green)
		end
		Particles.emit("Sparkle", position, 12, { Particles.Colors.Green, Particles.Colors.White })
	else
		floatText(position, `+{payload.Count} 📦`, Colors.Blue, 1.2)
	end
end

handlers.Pickup = function()
	SoundPlayer.play("Pickup")
	local root, feet = playerSpot()
	if root and feet then
		Particles.ring(feet, Particles.Colors.White)
		Particles.emit("Sparkle", root.Position + root.CFrame.LookVector * 1.8 + Vector3.new(0, 0.5, 0), 6, Particles.Colors.White)
	end
end

handlers.BoxLand = function(payload)
	local position = payload.Position
	if typeof(position) == "Vector3" and near(position, 120) then
		SoundPlayer.play("Thud", rng:NextNumber(0.9, 1.1), position, 0.05)
		local ground = position - Vector3.new(0, 1, 0)
		Particles.dustAround(ground, BoxVisual.Size.X, 12)
		Particles.ring(ground, Particles.Colors.White)
	end
end

-- Level-up: a ring at your feet and a column of rising stars.
handlers.Upgrade = function()
	local root, feet = playerSpot()
	if root and feet then
		Particles.ring(feet, Particles.Colors.Green)
		Particles.emit("Rise", feet, 22, { Particles.Colors.Green, Particles.Colors.Gold, Particles.Colors.White })
		Particles.cameraPunch(2)
	end
end

handlers.StoreExpanded = function(payload)
	local position = payload.Position
	if typeof(position) ~= "Vector3" or not near(position, 250) then
		return
	end
	-- Fireworks from the new sign.
	SoundPlayer.play("Upgrade", 1, position)
	for index = 1, 3 do
		task.delay((index - 1) * 0.35, function()
			SoundPlayer.play("Whoosh", 0.8 + index * 0.1, position)
			Particles.firework(position + Vector3.new((index - 2) * 6, 2, 0), Particles.Rainbow[(index * 2) % #Particles.Rainbow + 1], function()
				SoundPlayer.play("Pop", 0.9 + index * 0.1, position)
			end)
		end)
	end
	Particles.emit("Confetti", position, 30, Particles.Rainbow)
	if payload.OwnerId == player.UserId then
		Particles.cameraPunch(4)
	end
end

handlers.Sad = function(payload)
	local position = payload.Position
	if payload.OwnerId == player.UserId and typeof(position) == "Vector3" and near(position, 80) then
		SoundPlayer.play("Sad", 1, position, 0.5)
	end
end

handlers.Delivery = function()
	-- The banner already plays a sound; nothing extra needed.
end

handlers.Purchase = function()
	SoundPlayer.play("Purchase")
	Effects.confetti(50)
	local root, feet = playerSpot()
	if root and feet then
		Particles.emit("Glow", root.Position, 1, Particles.Colors.Gold)
		Particles.ring(feet, Particles.Colors.Gold)
		Particles.emit("Rise", feet, 28, { Particles.Colors.Gold, Particles.Colors.White, Particles.Colors.Green })
		Particles.cameraPunch(3)
	end
end

-- Tutorial step done: a little column of stars (the card handles the rest).
handlers.TutorialStep = function()
	local _, feet = playerSpot()
	if feet then
		Particles.emit("Rise", feet, 14, { Particles.Colors.Gold, Particles.Colors.Green })
	end
end

-- Products popping onto shelves --------------------------------------------------------

local function animateStock(item: Instance)
	if not item:IsA("Model") or not item:GetAttribute("Pop") then
		return
	end
	local pivot = item:GetPivot()
	if not near(pivot.Position, 80) then
		return
	end
	local fill = item:GetAttribute("Fill")
	SoundPlayer.play("Stock", 0.85 + (if type(fill) == "number" then fill else 0.5) * 0.9, pivot.Position, 0.025)
	-- A single twinkle as each product lands.
	Particles.emit("Sparkle", pivot.Position + Vector3.new(0, 0.6, 0), 1, Particles.Colors.White)
	task.spawn(function()
		item:ScaleTo(0.05)
		animate(0.22, function(alpha)
			if item.Parent == nil then
				return
			end
			local e = ease(alpha, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			item:ScaleTo(math.max(0.05, e))
			item:PivotTo(pivot * CFrame.new(0, (1 - alpha) * 0.9, 0))
		end)
		if item.Parent then
			item:ScaleTo(1)
			item:PivotTo(pivot)
		end
	end)
end

local function watchShelf(shelf: Instance)
	task.spawn(function()
		local items = shelf:WaitForChild("Items", 10)
		if items then
			items.ChildAdded:Connect(animateStock)
		end
	end)
end

-- Rainbow items cycle through colours ------------------------------------------------------

local function updateRainbows()
	local t = os.clock()
	for _, model in CollectionService:GetTagged(ProductVisuals.RainbowTag) do
		if model:IsA("Model") and model:IsDescendantOf(workspace) and near(model:GetPivot().Position, 100) then
			-- Pieces of one low-poly prism share a name, so colour by name.
			local count = 0
			local byName: { [string]: number } = {}
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and part.Transparency < 1 then
					local index = byName[part.Name]
					if not index then
						count += 1
						index = count
						byName[part.Name] = index
					end
					part.Color = Color3.fromHSV((t * 0.45 + index * 0.17) % 1, 0.75, 1)
				end
			end
		end
	end
end

function Effects.init(gui: ScreenGui)
	screen = gui
	Particles.init()
	Remotes.event("Effect").OnClientEvent:Connect(function(name: string, payload: { [string]: any })
		if type(payload) ~= "table" then
			return
		end
		local handler = handlers[name]
		if handler then
			task.spawn(handler, payload)
		end
		local extras = extraHandlers[name]
		if extras then
			for _, extra in extras do
				task.spawn(extra, payload)
			end
		end
	end)

	for _, shelf in CollectionService:GetTagged("Shelf") do
		watchShelf(shelf)
	end
	CollectionService:GetInstanceAddedSignal("Shelf"):Connect(watchShelf)

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.05 then
			accumulator = 0
			updateRainbows()
		end
	end)
end

return Effects
