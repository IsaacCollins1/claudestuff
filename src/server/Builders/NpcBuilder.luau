--!strict
-- Blocky R6 characters built from Parts for customers, workers and the cashier.
-- Uses Roblox's own public R6 walk/idle animations so NPCs animate properly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)

local NpcBuilder = {}

NpcBuilder.WalkAnimation = "rbxassetid://180426354" -- Roblox R6 walk
NpcBuilder.IdleAnimation = "rbxassetid://180435571" -- Roblox R6 idle

export type Style = {
	Shirt: Color3,
	Pants: Color3,
	Skin: Color3,
	Hat: Color3?,
	Hair: Color3?,
}

export type Npc = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	RightArm: BasePart,
	Head: BasePart,
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
local HAIRS = {
	Color3.fromRGB(60, 40, 30),
	Color3.fromRGB(20, 20, 25),
	Color3.fromRGB(230, 190, 90),
	Color3.fromRGB(170, 70, 40),
}

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

function NpcBuilder.randomStyle(rng: Random): Style
	return {
		Shirt = pick(rng, SHIRTS),
		Pants = pick(rng, PANTS),
		Skin = pick(rng, SKINS),
		Hat = if rng:NextNumber() < 0.35 then pick(rng, SHIRTS) else nil,
		Hair = if rng:NextNumber() < 0.6 then pick(rng, HAIRS) else nil,
	}
end

-- R6 joint layout (the standard Roblox values).
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

	-- Short sleeves in the shirt colour.
	for _, armName in { "Right Arm", "Left Arm" } do
		local arm = parts[armName]
		local sleeve = Build.part(model, "Sleeve", Vector3.new(1.05, 0.8, 1.05), arm.CFrame * CFrame.new(0, 0.6, 0), style.Shirt)
		if withHumanoid then
			attach(sleeve, arm)
		else
			Build.decor(sleeve)
		end
	end

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head

	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	if style.Hair then
		local hair = Build.part(model, "Hair", Vector3.new(2.1, 0.5, 1.15), head.CFrame * CFrame.new(0, 0.55, 0.05), style.Hair)
		if withHumanoid then
			attach(hair, head)
		else
			Build.decor(hair)
		end
	end
	if style.Hat then
		local crown = Build.cylinder(model, "Cap", 0.6, 1.35, head.CFrame * CFrame.new(0, 0.75, 0), style.Hat)
		local brim = Build.part(model, "Brim", Vector3.new(1.2, 0.12, 0.8), head.CFrame * CFrame.new(0, 0.5, -0.75), style.Hat)
		for _, part in { crown, brim } do
			if withHumanoid then
				attach(part, head)
			else
				Build.decor(part)
			end
		end
	end

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

-- A walking NPC with a Humanoid. Parent it to the workspace, then call `NpcBuilder.animate`.
function NpcBuilder.build(cframe: CFrame, style: Style, walkSpeed: number): Npc
	local model, parts = buildRig(cframe, style, true)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.WalkSpeed = walkSpeed
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	humanoid.Parent = model

	return {
		Model = model,
		Humanoid = humanoid,
		Root = parts.HumanoidRootPart,
		RightArm = parts["Right Arm"],
		Head = parts.Head,
	}
end

-- Decorative, anchored character (e.g. the cashier).
function NpcBuilder.buildStatic(cframe: CFrame, style: Style): Model
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

-- Plays walk/idle animations based on movement. Call after parenting to the workspace.
function NpcBuilder.animate(npc: Npc)
	local animator = npc.Humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local ok, tracks = pcall(function()
		local walk = Instance.new("Animation")
		walk.AnimationId = NpcBuilder.WalkAnimation
		local idle = Instance.new("Animation")
		idle.AnimationId = NpcBuilder.IdleAnimation
		return { animator:LoadAnimation(walk), animator:LoadAnimation(idle) }
	end)
	if not ok or not tracks then
		return
	end
	local walkTrack, idleTrack = tracks[1], tracks[2]
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
				walkTrack:AdjustSpeed(npc.Humanoid.WalkSpeed / 14)
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
	local arm = npc.RightArm
	local basketCFrame = arm.CFrame * CFrame.new(0, -1.25, -0.35)
	local basket = Build.part(npc.Model, "Basket", Vector3.new(1.3, 0.12, 1), basketCFrame * CFrame.new(0, -0.3, 0), color)
	attach(basket, arm)
	local walls: { { Size: Vector3, Offset: CFrame } } = {
		{ Size = Vector3.new(1.3, 0.55, 0.08), Offset = CFrame.new(0, 0, -0.46) },
		{ Size = Vector3.new(1.3, 0.55, 0.08), Offset = CFrame.new(0, 0, 0.46) },
		{ Size = Vector3.new(0.08, 0.55, 1), Offset = CFrame.new(-0.61, 0, 0) },
		{ Size = Vector3.new(0.08, 0.55, 1), Offset = CFrame.new(0.61, 0, 0) },
	}
	for _, wall in walls do
		local part = Build.part(npc.Model, "BasketSide", wall.Size, basketCFrame * wall.Offset, color)
		attach(part, arm)
	end
	local handle = Build.part(npc.Model, "BasketHandle", Vector3.new(0.1, 0.1, 1), basketCFrame * CFrame.new(0, 0.55, 0), color)
	attach(handle, arm)
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
