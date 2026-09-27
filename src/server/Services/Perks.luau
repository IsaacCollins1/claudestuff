--!strict
-- Game pass ownership and timed boosts (from the Robux shop), plus the
-- gameplay multipliers they give. Gameplay code only reads from here; the
-- Monetization service writes to it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Monetization)

local PlayerData = require(script.Parent.PlayerData)

local Perks = {}

local owned: { [Player]: { [string]: boolean } } = {}

function Perks.setOwned(player: Player, passKey: string, value: boolean)
	owned[player] = owned[player] or {}
	owned[player][passKey] = value
	PlayerData.markDirty(player)
end

function Perks.has(player: Player, passKey: string): boolean
	local passes = owned[player]
	return passes ~= nil and passes[passKey] == true
end

function Perks.ownedList(player: Player): { [string]: boolean }
	return table.clone(owned[player] or {})
end

function Perks.clear(player: Player)
	owned[player] = nil
end

-- Timed boosts are stored as expiry timestamps in the save, so they keep
-- ticking between sessions.
function Perks.boostRemaining(player: Player, boostKey: string): number
	local data = PlayerData.get(player)
	local expiry = data and data.Boosts[boostKey]
	return if expiry then math.max(0, expiry - os.time()) else 0
end

function Perks.boostActive(player: Player, boostKey: string): boolean
	return Perks.boostRemaining(player, boostKey) > 0
end

function Perks.addBoost(player: Player, boostKey: string, seconds: number)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	local now = os.time()
	data.Boosts[boostKey] = math.max(data.Boosts[boostKey] or now, now) + seconds
	PlayerData.markDirty(player)
end

-- Multipliers -------------------------------------------------------------------

local passes = Monetization.Passes

function Perks.cashMultiplier(player: Player): number
	return if Perks.has(player, "DoubleCash") then passes.DoubleCash.Multiplier or 2 else 1
end

function Perks.luckMultiplier(player: Player): number
	return if Perks.has(player, "LuckyCharm") then passes.LuckyCharm.Multiplier or 2 else 1
end

function Perks.extraBoxes(player: Player): number
	return if Perks.has(player, "BigDeliveries") then 2 else 0
end

function Perks.deliveryQuantityMultiplier(player: Player): number
	return if Perks.has(player, "BigDeliveries") then 1.25 else 1
end

function Perks.extraWorkers(player: Player): number
	return if Perks.has(player, "VIP") then 1 else 0
end

-- Customer Rush: customers arrive 3x as often and more fit in the shop.
function Perks.customerIntervalMultiplier(player: Player): number
	return if Perks.boostActive(player, "CustomerRush") then 1 / 3 else 1
end

function Perks.extraCustomers(player: Player): number
	return if Perks.boostActive(player, "CustomerRush") then 4 else 0
end

return Perks
