--!strict
-- Movement helpers shared by customers and workers. NPCs walk between the
-- store's waypoints with Humanoid:MoveTo; if one ever gets stuck it is
-- snapped to its target so the shop never jams.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Build = require(Shared.Build)

local NpcBuilder = require(script.Parent.Parent.Builders.NpcBuilder)

local NpcMotion = {}

NpcMotion.Abort = "__npc_abort__"

export type Walker = {
	Npc: NpcBuilder.Npc,
	IsAlive: () -> boolean,
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Raises NpcMotion.Abort if the NPC was removed; callers wrap behaviour in pcall.
function NpcMotion.check(walker: Walker)
	if not walker.IsAlive() or walker.Npc.Model.Parent == nil then
		error(NpcMotion.Abort, 0)
	end
end

function NpcMotion.walkTo(walker: Walker, target: Vector3)
	local npc = walker.Npc
	local humanoid = npc.Humanoid
	local root = npc.Root
	local distance = (flat(target) - flat(root.Position)).Magnitude
	if distance < 1 then
		return
	end
	local speed = math.max(humanoid.WalkSpeed, 1)
	local deadline = os.clock() + distance / speed + 2.5
	local lastIssued = os.clock()
	humanoid:MoveTo(target)
	while true do
		NpcMotion.check(walker)
		local remaining = (flat(target) - flat(root.Position)).Magnitude
		if remaining < 1.2 then
			return
		end
		local now = os.clock()
		if now > deadline then
			-- Stuck (or pushed): pop them to the target.
			root.CFrame = CFrame.new(target + Vector3.new(0, npc.RootHeight, 0)) * root.CFrame.Rotation
			humanoid:MoveTo(target)
			return
		end
		if now - lastIssued > 4 then
			-- MoveTo gives up after 8 seconds; keep it going on long walks.
			humanoid:MoveTo(target)
			lastIssued = now
		end
		task.wait(0.1)
	end
end

-- Walk through plot-local waypoints.
function NpcMotion.walkPath(walker: Walker, plotCFrame: CFrame, localPoints: { Vector3 })
	for _, point in localPoints do
		NpcMotion.walkTo(walker, plotCFrame:PointToWorldSpace(point))
	end
end

function NpcMotion.face(npc: NpcBuilder.Npc, worldPoint: Vector3)
	local root = npc.Root
	local position = root.Position
	local target = Vector3.new(worldPoint.X, position.Y, worldPoint.Z)
	if (target - position).Magnitude > 0.05 then
		root.CFrame = CFrame.lookAt(position, target)
	end
end

-- Emoji bubble above the head for a moment.
function NpcMotion.emote(npc: NpcBuilder.Npc, text: string, duration: number?)
	local existing = npc.Head:FindFirstChild("Emote")
	if existing then
		existing:Destroy()
	end
	local gui = Build.billboard(npc.Head, UDim2.fromScale(2.2, 2.2), Vector3.new(0, 2.6, 0), 70)
	gui.Name = "Emote"
	Build.textLabel(gui, text)
	task.delay(duration or 1.6, function()
		if gui.Parent then
			gui:Destroy()
		end
	end)
end

function NpcMotion.setCollisionGroup(model: Model, group: string)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

return NpcMotion
