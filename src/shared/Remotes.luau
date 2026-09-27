--!strict
-- All networking goes through these few remotes. The server creates them on
-- start-up; the client waits for them.
--
-- Server -> client
--   DataUpdate(snapshot)          full UI state for the owning player
--   Notify(kind, text, extra?)    banner/toast messages
--   Effect(name, payload)         visual/audio effects for everyone nearby
-- Client -> server
--   BuyUpgrade(upgradeId) -> (ok, message)
--   SelectProduct(productId?)      preferred product for stocking empty slots
--   GetData() -> snapshot

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local EVENTS = { "DataUpdate", "Notify", "Effect", "SelectProduct" }
local FUNCTIONS = { "BuyUpgrade", "GetData" }

local FOLDER_NAME = "Remotes"

function Remotes.setup()
	assert(RunService:IsServer(), "Remotes.setup must run on the server")
	if ReplicatedStorage:FindFirstChild(FOLDER_NAME) then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in EVENTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in FUNCTIONS do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local function getFolder(): Instance
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Remotes.event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

return Remotes
