--!strict
-- Advances the tutorial when the player does each thing for the first time
-- and pays the step rewards. Progress is saved with the player's data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Tutorial = require(Shared.Tutorial)

local Events = require(script.Parent.Events)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)

local TutorialService = {}

function TutorialService.complete(player: Player, stepId: string)
	local data = PlayerData.get(player)
	if not data or data.Tutorial.Done then
		return
	end
	local step = Tutorial.step(data.Tutorial.Step)
	if not step or step.Id ~= stepId then
		return
	end
	PlayerData.giveCash(player, step.Reward)
	data.Tutorial.Step += 1
	local finished = data.Tutorial.Step > #Tutorial.Steps
	if finished then
		data.Tutorial.Done = true
		PlayerData.giveCash(player, Tutorial.FinishReward)
	end
	Net.effectTo(player, "TutorialStep", {
		Completed = stepId,
		Reward = step.Reward,
		Finished = finished,
		FinishReward = if finished then Tutorial.FinishReward else 0,
	})
	PlayerData.markDirty(player)
end

function TutorialService.init()
	Events.BoxPickedUp:Connect(function(player)
		TutorialService.complete(player, "Grab")
	end)
	Events.ShelfStocked:Connect(function(player)
		TutorialService.complete(player, "Unpack")
	end)
	Events.Sale:Connect(function(player)
		TutorialService.complete(player, "Sell")
	end)
	Events.UpgradeBought:Connect(function(player)
		TutorialService.complete(player, "Upgrade")
	end)

	Remotes.event("SkipTutorial").OnServerEvent:Connect(function(player: Player)
		local data = PlayerData.get(player)
		if data and not data.Tutorial.Done then
			data.Tutorial.Done = true
			PlayerData.markDirty(player)
		end
	end)
end

return TutorialService
