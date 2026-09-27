--!strict
-- NPC characters: customers, workers and the cashier.
--
-- They are standard Roblox R15 characters, made by Roblox itself with
-- Players:CreateHumanoidModelFromDescription (default body and face, with
-- shirt/trouser/skin colours) and animated with Roblox's default R15 walk and
-- idle animations. Each look is made once and then cloned.
--
-- If Roblox can't make them (e.g. character assets fail to load), simple
-- Part-built R6 characters are used instead so the shop never stops.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)

local NpcBuilder = {}

-- Roblox's own public default animations. `Pace` is the walk speed each walk cycle is made for.
NpcBuilder.Animations = {
	R15 = { Walk = "rbxassetid://507777826", Idle = "rbxassetid://507766666", Pace = 16 },
	R6 = { Walk = "rbxassetid://180426354", Idle = "rbxassetid://180435571", Pace = 14 },
}

export type Style = {
	Id: string, -- which look ("Staff", "Crowd3", ...); each gets one Roblox character
	Shirt: Color3,
	Pants: Color3,
	Skin: Color3,
}

export type Npc = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Head: BasePart,
	Hand: BasePart, -- right hand (R15) or right arm (R6 fallback)
	HandGrip: CFrame, -- where a carried basket sits, relative to Hand
	RootHeight: number, -- height of the root part's centre above the feet
}

local SHIRTS = {
	Color3.fromRGB(255, 99, 99),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(255, 190, 60),
	Color3.fromRGB(150, 110, 255),
	Color3.fromRGB(90, 210, 150),
	Color3.fromRGB(255, 130, 200),
	Color3.fromRGB(60, 200, 220),
	Color3.fromRGB(250, 250, 250),
}
local PANTS = {
	Color3.fromRGB(50, 70, 120),
	Color3.fromRGB(40, 40, 50),
	Color3.fromRGB(110, 80, 60),
	Color3.fromRGB(80, 90, 100),
	Color3.fromRGB(30, 110, 90),
}
local SKINS = {
	Color3.fromRGB(255, 220, 185),
	Color3.fromRGB(240, 190, 145),
	Color3.fromRGB(200, 145, 100),
	Color3.fromRGB(150, 100, 70),
	Color3.fromRGB(100, 70, 50),
	Color3.fromRGB(255, 205, 160),
}

-- Shop staff (workers and the cashier) wear green.
NpcBuilder.StaffStyle = {
	Id = "Staff",
	Shirt = Color3.fromRGB(60, 190, 90),
	Pants = Color3.fromRGB(40, 44, 60),
	Skin = Color3.fromRGB(240, 190, 145),
} :: Style

-- A fixed crowd of customer looks (a new Roblox character is made for each).
local CROWD: { Style } = {}
do
	local rng = Random.new(2024)
	for index = 1, 12 do
		table.insert(CROWD, {
			Id = "Crowd" .. index,
			Shirt = SHIRTS[(index - 1) % #SHIRTS + 1],
			Pants = PANTS[rng:NextInteger(1, #PANTS)],
			Skin = SKINS[rng:NextInteger(1, #SKINS)],
		})
	end
end

function NpcBuilder.randomStyle(rng: Random): Style
	return CROWD[rng:NextInteger(1, #CROWD)]
end

-- Roblox characters ------------------------------------------------------------------

local templates: { [string]: Model } = {}
local robloxRefused = false -- stop asking after the first failure

local function describe(style: Style): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = style.Skin
	description.LeftArmColor = style.Skin
	description.RightArmColor = style.Skin
	description.TorsoColor = style.Shirt
	description.LeftLegColor = style.Pants
	description.RightLegColor = style.Pants
	return description
end

local function makeTemplate(style: Style): Model?
	if robloxRefused then
		return nil
	end
	local ok, result = pcall(function(): Model
		return Players:CreateHumanoidModelFromDescription(describe(style), Enum.HumanoidRigType.R15)
	end)
	local model = if ok then result else nil
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not model or not humanoid or not root or not root:IsA("BasePart") or not model:FindFirstChild("RightHand") then
		robloxRefused = true
		warn("[FillTheStore] Couldn't create Roblox characters for NPCs, using simple ones instead: " .. tostring(if ok then "incomplete character" else result))
		if model then
			model:Destroy()
		end
		return nil
	end
	-- NPCs are driven by the server, so drop any scripts a character comes with.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
	model.Name = "NPC"
	model.PrimaryPart = root
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	if not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoid
	end
	templates[style.Id] = model
	return model
end

-- Make the characters up front: the staff look right away (the first shop's
-- cashier needs it), the customer crowd in the background.
function NpcBuilder.preload()
	makeTemplate(NpcBuilder.StaffStyle)
	task.spawn(function()
		for _, style in CROWD do
			if robloxRefused then
				break
			end
			makeTemplate(style)
		end
	end)
end

local function prepareHumanoid(humanoid: Humanoid, walkSpeed: number)
	humanoid.WalkSpeed = walkSpeed
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
end

-- A clone of the Roblox character for `style`, standing at `cframe`.
local function fromTemplate(cframe: CFrame, style: Style): Npc?
	local template = templates[style.Id]
	if not template then
		return nil
	end
	local model = template:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	model.PrimaryPart = root
	local rootHeight = humanoid.HipHeight + root.Size.Y / 2
	model:PivotTo(cframe * CFrame.new(0, rootHeight, 0))
	return {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Head = model:FindFirstChild("Head") :: BasePart,
		Hand = model:FindFirstChild("RightHand") :: BasePart,
		HandGrip = CFrame.new(0, -0.45, -0.35),
		RootHeight = rootHeight,
	}
end

-- Fallback: simple R6 characters built from Parts ------------------------------------

local R = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
local RIGHT = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local LEFT = CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
local JOINTS: { { Name: string, Part: string, C0: CFrame, C1: CFrame } } = {
	{ Name = "Neck", Part = "Head", C0 = CFrame.new(0, 1, 0) * R, C1 = CFrame.new(0, -0.5, 0) * R },
	{ Name = "Right Shoulder", Part = "Right Arm", C0 = CFrame.new(1, 0.5, 0) * RIGHT, C1 = CFrame.new(-0.5, 0.5, 0) * RIGHT },
	{ Name = "Left Shoulder", Part = "Left Arm", C0 = CFrame.new(-1, 0.5, 0) * LEFT, C1 = CFrame.new(0.5, 0.5, 0) * LEFT },
	{ Name = "Right Hip", Part = "Right Leg", C0 = CFrame.new(1, -1, 0) * RIGHT, C1 = CFrame.new(0.5, 1, 0) * RIGHT },
	{ Name = "Left Hip", Part = "Left Leg", C0 = CFrame.new(-1, -1, 0) * LEFT, C1 = CFrame.new(-0.5, 1, 0) * LEFT },
}

local function attach(part: BasePart, to: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = part
	weld.Parent = part
end

-- Builds the rig standing at `cframe` (feet on the ground at cframe.Y).
local function buildRig(cframe: CFrame, style: Style, withHumanoid: boolean): (Model, { [string]: BasePart })
	local model = Instance.new("Model")
	model.Name = "NPC"
	local base = cframe * CFrame.new(0, 3, 0) -- torso centre is 3 studs above the feet

	local parts: { [string]: BasePart } = {}
	local function limb(name: string, size: Vector3, offset: Vector3, color: Color3): Part
		local part = Build.part(model, name, size, base * CFrame.new(offset), color)
		part.Anchored = not withHumanoid
		part.CanCollide = false
		part.CastShadow = true
		parts[name] = part
		return part
	end

	local root = limb("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.zero, style.Shirt)
	root.Transparency = 1
	local torso = limb("Torso", Vector3.new(2, 2, 1), Vector3.zero, style.Shirt)
	torso.CanCollide = true
	local head = limb("Head", Vector3.new(2, 1, 1), Vector3.new(0, 1.5, 0), style.Skin)
	head.CanCollide = true
	limb("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0), style.Skin)
	limb("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0), style.Skin)
	limb("Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0), style.Pants)
	limb("Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0), style.Pants)

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head

	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	if withHumanoid then
		local rootJoint = Instance.new("Motor6D")
		rootJoint.Name = "RootJoint"
		rootJoint.Part0 = root
		rootJoint.Part1 = torso
		rootJoint.C0 = R
		rootJoint.C1 = R
		rootJoint.Parent = root
		for _, joint in JOINTS do
			local motor = Instance.new("Motor6D")
			motor.Name = joint.Name
			motor.Part0 = torso
			motor.Part1 = parts[joint.Part]
			motor.C0 = joint.C0
			motor.C1 = joint.C1
			motor.Parent = torso
		end
	end

	model.PrimaryPart = root
	return model, parts
end

local function buildFallback(cframe: CFrame, style: Style): Npc
	local model, parts = buildRig(cframe, style, true)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	humanoid.Parent = model
	return {
		Model = model,
		Humanoid = humanoid,
		Root = parts.HumanoidRootPart,
		Head = parts.Head,
		Hand = parts["Right Arm"],
		HandGrip = CFrame.new(0, -1.25, -0.35),
		RootHeight = 3,
	}
end

-- Public API ---------------------------------------------------------------------------

-- A walking NPC with a Humanoid, feet on the ground at `cframe`.
-- Parent it to the workspace, then call `NpcBuilder.animate`.
function NpcBuilder.build(cframe: CFrame, style: Style, walkSpeed: number): Npc
	local npc = fromTemplate(cframe, style) or buildFallback(cframe, style)
	prepareHumanoid(npc.Humanoid, walkSpeed)
	return npc
end

-- A character that stands still behind the counter (the cashier).
-- Call `NpcBuilder.playIdle` once it's in the workspace.
function NpcBuilder.buildStatic(cframe: CFrame, style: Style): Model
	local npc = fromTemplate(cframe, style)
	if npc then
		for _, part in npc.Model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end
		-- Only the root is anchored, so the idle animation can still move the body.
		npc.Root.Anchored = true
		return npc.Model
	end
	local model, parts = buildRig(cframe, style, false)
	parts.HumanoidRootPart:Destroy()
	model.PrimaryPart = parts.Torso
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	return model
end

local function loadTracks(humanoid: Humanoid): (AnimationTrack?, AnimationTrack?)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil, nil
	end
	local ids = if humanoid.RigType == Enum.HumanoidRigType.R15 then NpcBuilder.Animations.R15 else NpcBuilder.Animations.R6
	local ok, walk, idle = pcall(function()
		local walkAnimation = Instance.new("Animation")
		walkAnimation.AnimationId = ids.Walk
		local idleAnimation = Instance.new("Animation")
		idleAnimation.AnimationId = ids.Idle
		return animator:LoadAnimation(walkAnimation), animator:LoadAnimation(idleAnimation)
	end)
	if not ok then
		return nil, nil
	end
	return walk, idle
end

-- Idle animation for a standing character (no-op for the simple Part version).
function NpcBuilder.playIdle(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local _, idle = loadTracks(humanoid)
	if idle then
		idle.Looped = true
		idle:Play()
	end
end

-- Plays walk/idle animations based on movement. Call after parenting to the workspace.
function NpcBuilder.animate(npc: Npc)
	local walkTrack, idleTrack = loadTracks(npc.Humanoid)
	if not walkTrack or not idleTrack then
		return
	end
	local pace = if npc.Humanoid.RigType == Enum.HumanoidRigType.R15 then NpcBuilder.Animations.R15.Pace else NpcBuilder.Animations.R6.Pace
	walkTrack.Looped = true
	idleTrack.Looped = true
	idleTrack:Play()
	local walking = false
	npc.Humanoid.Running:Connect(function(speed: number)
		local nowWalking = speed > 0.5
		if nowWalking ~= walking then
			walking = nowWalking
			if walking then
				walkTrack:Play(0.15)
				walkTrack:AdjustSpeed(npc.Humanoid.WalkSpeed / pace)
				idleTrack:Stop(0.15)
			else
				walkTrack:Stop(0.15)
				idleTrack:Play(0.15)
			end
		end
	end)
end

-- Basket carried in the NPC's right hand; products bought get welded into it.
function NpcBuilder.addBasket(npc: Npc, color: Color3): BasePart
	local hand = npc.Hand
	local basketCFrame = hand.CFrame * npc.HandGrip
	local basket = Build.part(npc.Model, "Basket", Vector3.new(1.3, 0.12, 1), basketCFrame * CFrame.new(0, -0.3, 0), color)
	attach(basket, hand)
	local walls: { { Size: Vector3, Offset: CFrame } } = {
		{ Size = Vector3.new(1.3, 0.55, 0.08), Offset = CFrame.new(0, 0, -0.46) },
		{ Size = Vector3.new(1.3, 0.55, 0.08), Offset = CFrame.new(0, 0, 0.46) },
		{ Size = Vector3.new(0.08, 0.55, 1), Offset = CFrame.new(-0.61, 0, 0) },
		{ Size = Vector3.new(0.08, 0.55, 1), Offset = CFrame.new(0.61, 0, 0) },
	}
	for _, wall in walls do
		local part = Build.part(npc.Model, "BasketSide", wall.Size, basketCFrame * wall.Offset, color)
		attach(part, hand)
	end
	local handle = Build.part(npc.Model, "BasketHandle", Vector3.new(0.1, 0.1, 1), basketCFrame * CFrame.new(0, 0.55, 0), color)
	attach(handle, hand)
	return basket
end

-- Floating label (e.g. "STAFF") over an NPC's head.
function NpcBuilder.nameTag(npc: Npc, text: string, color: Color3)
	local gui = Build.billboard(npc.Head, UDim2.fromScale(4, 1), Vector3.new(0, 2.2, 0), 60)
	gui.Name = "NameTag"
	local label = Build.textLabel(gui, text, color)
	Build.stroke(label, Color3.fromRGB(30, 30, 40), 2)
end

return NpcBuilder
