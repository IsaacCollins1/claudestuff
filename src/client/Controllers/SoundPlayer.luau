--!strict
-- Plays the sound effects defined in Shared/Sounds, optionally at a 3D position.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sounds"))

local SoundPlayer = {}

local templates: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}

local function template(name: string): Sound?
	local existing = templates[name]
	if existing then
		return existing
	end
	local def = Sounds[name]
	if not def then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "SFX_" .. name
	sound.SoundId = def.Id
	sound.Volume = def.Volume
	sound.PlaybackSpeed = def.Speed
	sound.Parent = SoundService
	templates[name] = sound
	return sound
end

-- `pitch` multiplies the sound's speed. `position` makes it a 3D sound.
function SoundPlayer.play(name: string, pitch: number?, position: Vector3?, minGap: number?)
	local now = os.clock()
	if minGap and now - (lastPlayed[name] or 0) < minGap then
		return
	end
	lastPlayed[name] = now
	local base = template(name)
	if not base then
		return
	end
	local sound = base:Clone()
	sound.PlaybackSpeed = base.PlaybackSpeed * (pitch or 1)
	if position then
		local holder = Instance.new("Part")
		holder.Name = "SoundHolder"
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.Position = position
		holder.Parent = workspace
		sound.RollOffMaxDistance = 90
		sound.RollOffMinDistance = 12
		sound.Parent = holder
		sound:Play()
		Debris:AddItem(holder, 4)
	else
		sound.Parent = SoundService
		sound:Play()
		Debris:AddItem(sound, 4)
	end
end

return SoundPlayer
