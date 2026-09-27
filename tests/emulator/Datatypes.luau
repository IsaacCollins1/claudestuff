--!nocheck
-- Roblox datatypes for the emulator. Lune provides these, but its
-- CFrame.lookAt (v0.8.9) flips the Z axis, so we supply a correct one.

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local LuneCFrame = roblox.CFrame

local function lookAt(at, target, up)
	up = up or Vector3.new(0, 1, 0)
	local look = (target - at).Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(Vector3.new(0, 0, -1))
	end
	right = right.Unit
	local upVector = right:Cross(look).Unit
	return LuneCFrame.fromMatrix(at, right, upVector, -look)
end

local CFrame = table.clone(LuneCFrame)
CFrame.lookAt = lookAt
CFrame.new = function(...)
	if select("#", ...) == 2 and typeof((select(1, ...))) == "Vector3" then
		-- Deprecated CFrame.new(position, lookAt) form.
		return lookAt(...)
	end
	return LuneCFrame.new(...)
end

return {
	CFrame = CFrame,
	lookAt = lookAt,
}
