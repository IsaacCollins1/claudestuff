--!strict
-- Pooled particle effects that make actions feel good without cluttering the
-- screen.
--
-- Each effect ("Sparkle", "Dust", "Ring"...) has one invisible anchor part and
-- one ParticleEmitter per colour. Playing an effect moves the anchor and calls
-- Emit, so a hundred effects still cost one part each. Every effect also has a
-- per-second particle budget and is skipped far from the camera, and counts
-- are halved on low graphics settings.
--
-- The textures are the particle images built into every Roblox client.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LowPoly = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LowPoly"))

local Particles = {}

local TEXTURES = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Puff = "rbxasset://textures/particles/smoke_main.dds",
	Ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	Glow = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	Square = "rbxasset://textures/particles/SquareParticle.png",
}
Particles.Textures = TEXTURES

local MAX_DISTANCE = 150

type Preset = {
	Texture: string,
	Size: NumberSequence,
	Transparency: NumberSequence,
	Lifetime: NumberRange,
	Speed: NumberRange,
	Spread: Vector2,
	Acceleration: Vector3?,
	Drag: number?,
	LightEmission: number?,
	Rotation: NumberRange?,
	RotSpeed: NumberRange?,
	Flat: boolean?, -- lies flat on the ground (rings)
	ZOffset: number?,
	Budget: number, -- most particles per second
}

local function sequence(points: { { number } }): NumberSequence
	local keypoints = {}
	for _, point in points do
		table.insert(keypoints, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keypoints)
end

local PRESETS: { [string]: Preset } = {
	-- Twinkling stars that burst out and fall gently.
	Sparkle = {
		Texture = TEXTURES.Sparkle,
		Size = sequence({ { 0, 0 }, { 0.15, 0.6 }, { 1, 0 } }),
		Transparency = sequence({ { 0, 0 }, { 0.7, 0.1 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.45, 0.8),
		Speed = NumberRange.new(4, 8),
		Spread = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -8, 0),
		Drag = 3,
		LightEmission = 1,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		Budget = 120,
	},
	-- Stars rising in a column (level ups).
	Rise = {
		Texture = TEXTURES.Sparkle,
		Size = sequence({ { 0, 0.2 }, { 0.3, 0.75 }, { 1, 0 } }),
		Transparency = sequence({ { 0, 0 }, { 0.8, 0.1 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.8, 1.3),
		Speed = NumberRange.new(9, 15),
		Spread = Vector2.new(22, 22),
		Acceleration = Vector3.new(0, -5, 0),
		Drag = 1.5,
		LightEmission = 1,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
		Budget = 80,
	},
	-- Soft cardboard-coloured puffs that roll out from under a box.
	Dust = {
		Texture = TEXTURES.Puff,
		Size = sequence({ { 0, 1.4 }, { 1, 3.6 } }),
		Transparency = sequence({ { 0, 0.1 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(9, 13),
		Spread = Vector2.new(85, 85),
		Acceleration = Vector3.new(0, 1.5, 0),
		Drag = 5,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
		Budget = 60,
	},
	-- Flat shockwave ring on the ground (not glowing, so it shows on bright floors).
	Ring = {
		Texture = TEXTURES.Ring,
		Size = sequence({ { 0, 3.5 }, { 1, 9 } }),
		Transparency = sequence({ { 0, 0 }, { 0.5, 0.15 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.55, 0.55),
		Speed = NumberRange.new(0.01, 0.01),
		Spread = Vector2.zero,
		Flat = true,
		Budget = 30,
	},
	-- Big star burst for fireworks.
	Burst = {
		Texture = TEXTURES.Sparkle,
		Size = sequence({ { 0, 0.4 }, { 0.2, 1.3 }, { 1, 0 } }),
		Transparency = sequence({ { 0, 0 }, { 0.75, 0.1 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.8, 1.2),
		Speed = NumberRange.new(16, 24),
		Spread = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -6, 0),
		Drag = 2.5,
		LightEmission = 1,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
		Budget = 150,
	},
	-- Ring facing the camera (fireworks in the air).
	Shockwave = {
		Texture = TEXTURES.Ring,
		Size = sequence({ { 0, 1 }, { 1, 12 } }),
		Transparency = sequence({ { 0, 0.1 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.5, 0.5),
		Speed = NumberRange.new(0, 0),
		Spread = Vector2.zero,
		LightEmission = 1,
		Budget = 8,
	},
	-- Quick bright flash.
	Glow = {
		Texture = TEXTURES.Glow,
		Size = sequence({ { 0, 1 }, { 0.3, 4.5 }, { 1, 5.5 } }),
		Transparency = sequence({ { 0, 0.25 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.35, 0.35),
		Speed = NumberRange.new(0, 0),
		Spread = Vector2.zero,
		LightEmission = 1,
		ZOffset = 1,
		Budget = 12,
	},
	-- Chunky square confetti that tumbles down (low-poly style).
	Confetti = {
		Texture = TEXTURES.Square,
		Size = sequence({ { 0, 0.32 }, { 1, 0.26 } }),
		Transparency = sequence({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.1, 1.7),
		Speed = NumberRange.new(12, 20),
		Spread = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, -32, 0),
		Drag = 1.4,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-400, 400),
		Budget = 150,
	},
}

Particles.Colors = {
	White = Color3.fromRGB(255, 255, 255),
	Gold = Color3.fromRGB(255, 205, 60),
	Green = Color3.fromRGB(110, 240, 110),
	Dust = Color3.fromRGB(215, 198, 170),
}
Particles.Rainbow = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(110, 230, 90),
	Color3.fromRGB(70, 190, 255),
	Color3.fromRGB(180, 110, 255),
}

local folder: Folder? = nil
local anchors: { [string]: Part } = {}
local emitters: { [string]: ParticleEmitter } = {}
local tokens: { [string]: number } = {}
local lastRefill = os.clock()
local qualityScale = 1

local function effectsFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "ClientEffects"
	created.Parent = workspace
	folder = created
	return created
end

local function invisiblePart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Parent = effectsFolder()
	return part
end

local function applyPreset(emitter: ParticleEmitter, preset: Preset, color: Color3)
	emitter.Texture = preset.Texture
	emitter.Color = ColorSequence.new(color)
	emitter.Size = preset.Size
	emitter.Transparency = preset.Transparency
	emitter.Lifetime = preset.Lifetime
	emitter.Speed = preset.Speed
	emitter.SpreadAngle = preset.Spread
	emitter.Acceleration = preset.Acceleration or Vector3.zero
	emitter.Drag = preset.Drag or 0
	emitter.LightEmission = preset.LightEmission or 0
	emitter.Rotation = preset.Rotation or NumberRange.new(0, 0)
	emitter.RotSpeed = preset.RotSpeed or NumberRange.new(0, 0)
	emitter.ZOffset = preset.ZOffset or 0
	emitter.EmissionDirection = Enum.NormalId.Top
	if preset.Flat then
		emitter.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	end
end

local function emitterFor(name: string, color: Color3): ParticleEmitter?
	local preset = PRESETS[name]
	if not preset then
		return nil
	end
	local existing = anchors[name]
	local anchor: Part
	if existing and existing.Parent then
		anchor = existing
	else
		anchor = invisiblePart("Effect_" .. name)
		anchors[name] = anchor
	end
	local key = name .. "|" .. color:ToHex()
	local emitter = emitters[key]
	if not emitter or emitter.Parent ~= anchor then
		local created = Instance.new("ParticleEmitter")
		created.Name = key
		created.Rate = 0
		applyPreset(created, preset, color)
		created.Parent = anchor
		emitters[key] = created
		emitter = created
	end
	return emitter
end

local function cameraPosition(): Vector3?
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position
end

-- Is `position` close enough to the camera to be worth drawing?
function Particles.near(position: Vector3, distance: number?): boolean
	local camera = cameraPosition()
	return camera ~= nil and (camera - position).Magnitude <= (distance or MAX_DISTANCE)
end

-- Emit `count` particles of effect `name` at `position`. `colors` can be one
-- colour or a list (the particles are shared between them).
function Particles.emit(name: string, position: Vector3, count: number, colors: (Color3 | { Color3 })?)
	local preset = PRESETS[name]
	if not preset or not Particles.near(position) then
		return
	end
	-- Budget: tokens refill at `Budget` per second.
	local now = os.clock()
	local elapsed = now - lastRefill
	lastRefill = now
	for key, value in tokens do
		local budget = PRESETS[key].Budget
		tokens[key] = math.min(budget, value + elapsed * budget)
	end
	local available = tokens[name] or preset.Budget
	local wanted = math.max(1, math.floor(count * qualityScale + 0.5))
	local amount = math.min(wanted, math.floor(available))
	if amount <= 0 then
		return
	end
	tokens[name] = available - amount

	local list: { Color3 }
	if typeof(colors) == "Color3" then
		list = { colors }
	elseif type(colors) == "table" and #colors > 0 then
		list = colors
	else
		list = { Particles.Colors.White }
	end
	local chosen: { ParticleEmitter } = {}
	for _, color in list do
		local emitter = emitterFor(name, color)
		if emitter then
			table.insert(chosen, emitter)
		end
	end
	local anchor = anchors[name]
	if not anchor or #chosen == 0 then
		return
	end
	anchor.CFrame = CFrame.new(position)
	-- Share the particles out between the colours.
	for index, emitter in chosen do
		local share = math.floor(amount / #chosen) + (if index <= amount % #chosen then 1 else 0)
		if share > 0 then
			emitter:Emit(share)
		end
	end
end

-- Ground ring. The built-in ring texture is faint on its own (about a third
-- opaque), so three perfectly stacked particles make one clear ring.
function Particles.ring(position: Vector3, color: Color3)
	Particles.emit("Ring", position, 3, color)
end

-- Dust rolling out from under something `width` studs wide (e.g. a box that just landed).
function Particles.dustAround(ground: Vector3, width: number, count: number)
	local half = width / 2
	local perCorner = math.max(1, math.floor(count / 4))
	for _, corner in { Vector3.new(half, 0, half), Vector3.new(-half, 0, half), Vector3.new(half, 0, -half), Vector3.new(-half, 0, -half) } do
		Particles.emit("Dust", ground + corner, perCorner, Particles.Colors.Dust)
	end
end

-- A quick "pop": flash + ring + sparkles, the building block of most effects.
function Particles.pop(position: Vector3, color: Color3, sparkles: number?)
	Particles.emit("Glow", position, 1, color)
	Particles.emit("Sparkle", position, sparkles or 8, { color, Particles.Colors.White })
end

-- Glowing outline flash on a model (e.g. a shelf when it's full).
function Particles.flash(model: Instance, color: Color3, duration: number?)
	if not model:IsA("Model") or not Particles.near(model:GetPivot().Position) then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "EffectFlash"
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.45
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = effectsFolder()
	local time = duration or 0.6
	TweenService:Create(highlight, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FillTransparency = 1,
		OutlineTransparency = 1,
	}):Play()
	task.delay(time + 0.05, function()
		highlight:Destroy()
	end)
end

-- Tall glowing light beam, like a loot drop (rare boxes).
function Particles.beam(position: Vector3, color: Color3, height: number?)
	if not Particles.near(position) then
		return
	end
	local tall = height or 22
	local pieces = LowPoly.hexPrism(effectsFolder(), "LootBeam", tall, 2.4, CFrame.new(position + Vector3.new(0, tall / 2, 0)), color, Enum.Material.Neon)
	for _, piece in pieces do
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.CastShadow = false
		piece.Transparency = 0.35
		piece.Size = Vector3.new(piece.Size.X * 0.2, piece.Size.Y, piece.Size.Z * 0.2)
		local grow = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(piece, grow, { Size = Vector3.new(piece.Size.X * 5, piece.Size.Y, piece.Size.Z * 5) }):Play()
	end
	task.delay(0.9, function()
		for _, piece in pieces do
			TweenService:Create(piece, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
		task.wait(0.65)
		for _, piece in pieces do
			piece:Destroy()
		end
	end)
end

-- A small firework: a glowing rocket with a sparkly trail that bursts in the air.
function Particles.firework(from: Vector3, color: Color3, onBurst: (() -> ())?)
	if not Particles.near(from, 250) then
		return
	end
	task.spawn(function()
		local rocket = LowPoly.diamond(effectsFolder(), "Rocket", 0.7, CFrame.new(from), color, Enum.Material.Neon)
		rocket.CanCollide = false
		rocket.CanQuery = false
		rocket.CanTouch = false
		local trail = Instance.new("ParticleEmitter")
		applyPreset(trail, PRESETS.Sparkle, color)
		trail.Speed = NumberRange.new(0.5, 1.5)
		trail.Lifetime = NumberRange.new(0.3, 0.5)
		trail.Rate = 40
		trail.Parent = rocket
		local drift = Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
		local apex = from + Vector3.new(0, math.random(20, 26), 0) + drift
		local start = os.clock()
		local duration = 0.75
		while true do
			local alpha = math.min((os.clock() - start) / duration, 1)
			local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			rocket.CFrame = CFrame.new(from:Lerp(apex, eased)) * CFrame.Angles(0, alpha * 12, 0)
			if alpha >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		trail.Enabled = false
		rocket.Transparency = 1
		Particles.emit("Glow", apex, 1, color)
		Particles.emit("Shockwave", apex, 2, color)
		Particles.emit("Burst", apex, 40, { color, Particles.Colors.White })
		Particles.emit("Confetti", apex, 18, { color, Particles.Colors.Gold })
		if onBurst then
			onBurst()
		end
		task.wait(0.6)
		rocket:Destroy()
	end)
end

-- Tiny camera "punch" for big moments: widen the view for a beat and settle back.
local punching = false
function Particles.cameraPunch(amount: number?)
	local camera = workspace.CurrentCamera
	if not camera or punching then
		return
	end
	punching = true
	local base = camera.FieldOfView
	local punch = amount or 3
	local out = TweenService:Create(camera, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base + punch })
	out:Play()
	task.delay(0.12, function()
		TweenService:Create(camera, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { FieldOfView = base }):Play()
		task.delay(0.36, function()
			punching = false
		end)
	end)
end

function Particles.init()
	-- Fewer particles on low graphics settings.
	pcall(function()
		local settings = UserSettings():GetService("UserGameSettings")
		local level = settings.SavedQualityLevel.Value
		qualityScale = if level > 0 and level <= 3 then 0.5 else 1
	end)
	effectsFolder()
end

return Particles
