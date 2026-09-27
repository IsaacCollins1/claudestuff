--!strict
-- Server-side gameplay events. Systems like the tutorial, leaderboards and
-- stats listen here instead of being wired into every gameplay service.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

local Events = {
	-- (player)
	BoxPickedUp = Signal.new() :: Signal.Signal<Player>,
	-- (player, units in the box)
	BoxOpened = Signal.new() :: Signal.Signal<Player, number>,
	-- (player, items placed) — only when the player stocks, not workers
	ShelfStocked = Signal.new() :: Signal.Signal<Player, number>,
	-- (shop owner, cash earned, items sold)
	Sale = Signal.new() :: Signal.Signal<Player, number, number>,
	-- (player, upgrade id, new level)
	UpgradeBought = Signal.new() :: Signal.Signal<Player, string, number>,
}

return Events
