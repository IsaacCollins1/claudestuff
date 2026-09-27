--!strict
-- Thin wrapper over the shared remotes for server code.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Net = {}

local notifyRemote: RemoteEvent
local effectRemote: RemoteEvent

function Net.init()
	Remotes.setup()
	notifyRemote = Remotes.event("Notify")
	effectRemote = Remotes.event("Effect")
end

-- kind: "Delivery" | "Rare" | "Upgrade" | "Info" | "Error" | "Expand"
function Net.notify(player: Player, kind: string, text: string)
	if player.Parent == Players then
		notifyRemote:FireClient(player, kind, text)
	end
end

-- Effect for one player.
function Net.effectTo(player: Player, name: string, payload: { [string]: any })
	if player.Parent == Players then
		effectRemote:FireClient(player, name, payload)
	end
end

-- Effect for everyone (clients decide if they're close enough to care).
function Net.effectAll(name: string, payload: { [string]: any })
	effectRemote:FireAllClients(name, payload)
end

return Net
