--!strict
-- Fill the Store! — server entry point.
-- Wires together the services in ./Services; each one owns one system.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local Services = script.Parent.Services
local Boxes = require(Services.Boxes)
local Deliveries = require(Services.Deliveries)
local Leaderboards = require(Services.Leaderboards)
local MonetizationService = require(Services.MonetizationService)
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local Stores = require(Services.Stores)
local TutorialService = require(Services.TutorialService)
local UpgradeService = require(Services.UpgradeService)
local WorldBuilder = require(script.Parent.Builders.WorldBuilder)

-- Collision groups: NPCs never block players or each other.
local function setupCollisionGroups()
	for _, name in { "Players", "NPC" } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable("NPC", "NPC", false)
	PhysicsService:CollisionGroupSetCollidable("NPC", "Players", false)
end

local function setPlayerCollisionGroup(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end)
end

local function sendHome(player: Player)
	local character = player.Character
	local spawnCFrame = Stores.spawnCFrame(player)
	if character and spawnCFrame then
		character:PivotTo(spawnCFrame)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	setPlayerCollisionGroup(character)
	task.spawn(function()
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root then
			return
		end
		task.wait() -- let the default spawn position settle first
		if player.Character == character then
			sendHome(player)
		end
	end)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			Boxes.dropCarried(player)
		end)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		Boxes.dropCarried(player)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end

	PlayerData.load(player)
	if player.Parent ~= Players then
		PlayerData.release(player)
		return
	end
	MonetizationService.playerJoined(player)

	local session = Stores.claim(player)
	if session then
		Stores.open(session)
		Deliveries.start(session)
		sendHome(player)
	else
		Net.notify(player, "Info", "All 6 shops on this server are taken — go visit them!")
	end
	PlayerData.markDirty(player)
end

local function onPlayerRemoving(player: Player)
	Boxes.dropCarried(player)
	local ok, err = pcall(function()
		Stores.release(player)
	end)
	if not ok then
		warn("[FillTheStore] Failed to release store: " .. tostring(err))
	end
	PlayerData.release(player)
	MonetizationService.playerLeft(player)
end

Net.init()
setupCollisionGroups()
PlayerData.init()
Stores.init()
Leaderboards.buildSigns(workspace:WaitForChild("World"), WorldBuilder.leaderboardCFrames())
Leaderboards.init()
UpgradeService.init()
TutorialService.init()
MonetizationService.init()

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

game:BindToClose(function()
	PlayerData.saveAll()
end)
