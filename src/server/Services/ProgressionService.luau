--!strict
-- Levels, product stars, rebirths and rebirth perks (rules in Shared/Progression).
--
--   * XP comes from selling (pricier products give more) and unpacking boxes.
--     Levelling up unlocks products for deliveries and pays a cash reward.
--   * Every unit sold counts towards that product's stars (+10% price each).
--   * Rebirth resets the run (cash, upgrades, shop size, stock) for a
--     permanent cash bonus and Rebirth Tokens, which buy perks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Items = require(Shared.Items)
local Products = require(Shared.Products)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Upgrades = require(Shared.Upgrades)

local Boxes = require(script.Parent.Boxes)
local Events = require(script.Parent.Events)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)
local Registry = require(script.Parent.Registry)
local Stores = require(script.Parent.Stores)

local ProgressionService = {}

local lastRebirth: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

function ProgressionService.addXp(player: Player, amount: number)
	local data = PlayerData.get(player)
	if not data or amount <= 0 then
		return
	end
	data.Xp += math.floor(amount)
	while data.Level < Progression.MaxLevel and data.Xp >= Progression.xpToNext(data.Level) do
		data.Xp -= Progression.xpToNext(data.Level)
		data.Level += 1
		local reward = Progression.levelReward(data.Level)
		PlayerData.giveCash(player, reward)
		local unlocked = {}
		for _, product in Progression.unlocksAt(data.Level) do
			table.insert(unlocked, product.Id)
		end
		Net.effectTo(player, "LevelUp", { Level = data.Level, Reward = reward, Unlocked = unlocked })
		Events.LevelUp:Fire(player, data.Level)
	end
	if data.Level >= Progression.MaxLevel then
		data.Xp = 0
	end
	PlayerData.markDirty(player)
end

-- XP and stars for everything a customer bought.
local function recordSale(player: Player, keys: { string })
	local data = PlayerData.get(player)
	if not data then
		return
	end
	local xp = 0
	local starsBefore: { [string]: number } = {}
	for _, key in keys do
		local product = Items.product(key)
		local sold = data.Sold[product.Id] or 0
		if starsBefore[product.Id] == nil then
			starsBefore[product.Id] = Progression.stars(sold)
		end
		data.Sold[product.Id] = sold + 1
		xp += Progression.xpForSale(product)
	end
	for id, before in starsBefore do
		local after = Progression.stars(data.Sold[id])
		if after > before then
			local product = Products.ById[id]
			Net.effectTo(player, "Star", { Product = id, Stars = after })
			Net.notify(
				player,
				"Rare",
				`{product.Icon} {string.upper(product.Name)} {string.rep("⭐", after)}  sells for +{math.floor(after * Progression.StarBonus * 100 + 0.5)}%!`
			)
		end
	end
	ProgressionService.addXp(player, xp)
end

-- Rebirth -----------------------------------------------------------------------------

function ProgressionService.rebirth(player: Player): (boolean, string)
	local data = PlayerData.get(player)
	local session = Registry.session(player)
	if not data or not session then
		return false, "Try again in a moment"
	end
	local now = os.clock()
	if lastRebirth[player] and now - lastRebirth[player] < 3 then
		return false, "Slow down!"
	end
	local cost = Progression.rebirthCost(data.Rebirths)
	if data.Cash < cost then
		return false, `You need {Format.money(cost)} to rebirth`
	end
	lastRebirth[player] = now

	-- Tear down the shop first (it remembers shelf stock), then reset the run.
	Boxes.clear(session)
	Stores.close(session)
	data.Rebirths += 1
	local tokens = Progression.tokensFor(data.Rebirths)
	data.RebirthTokens += tokens
	data.Cash = Config.StartingCash + Progression.headStartCash(data.RebirthPerks.HeadStart or 0)
	data.Upgrades = Upgrades.defaultLevels()
	data.Inventory = {}
	data.Shelves = {}
	data.SelectedProduct = nil
	PlayerData.markDirty(player)

	local store = Stores.open(session)
	local multiplier = Progression.rebirthMultiplier(data.Rebirths)
	local signPosition = if store then (session.PlotCFrame * store.Layout.SignCFrame).Position else session.PlotCFrame.Position
	Net.effectAll("Rebirth", {
		OwnerId = player.UserId,
		Rebirths = data.Rebirths,
		Multiplier = multiplier,
		Tokens = tokens,
		Position = signPosition,
	})
	-- (The owner's client shows its own big celebration popup.)
	Events.Rebirth:Fire(player, data.Rebirths)
	-- Back to the front of the (new) shop.
	local character = player.Character
	local spawn = Stores.spawnCFrame(player)
	if character and spawn then
		character:PivotTo(spawn)
	end
	return true, `Rebirth {data.Rebirths}! Cash x{multiplier}`
end

function ProgressionService.buyPerk(player: Player, id: unknown): (boolean, string)
	local data = PlayerData.get(player)
	if not data or type(id) ~= "string" or not Progression.Perks[id] then
		return false, "Unknown perk"
	end
	local level = data.RebirthPerks[id] or 0
	local cost = Progression.perkCost(id, level)
	if not cost then
		return false, "Already maxed!"
	end
	if data.RebirthTokens < cost then
		return false, `You need {cost} Rebirth Token{if cost == 1 then "" else "s"}`
	end
	data.RebirthTokens -= cost
	data.RebirthPerks[id] = level + 1
	PlayerData.markDirty(player)
	Net.effectTo(player, "PerkBought", { Id = id, Level = level + 1 })
	return true, `{Progression.Perks[id].Name} level {level + 1}!`
end

function ProgressionService.init()
	Events.Sale:Connect(function(player: Player, _cash: number, keys: { string })
		recordSale(player, keys)
	end)
	Events.BoxOpened:Connect(function(player: Player)
		ProgressionService.addXp(player, Progression.XpPerBox)
	end)

	Remotes.func("Rebirth").OnServerInvoke = function(player: Player)
		local ok, success, message = pcall(ProgressionService.rebirth, player)
		if not ok then
			warn("[FillTheStore] Rebirth failed: " .. tostring(success))
			return false, "Something went wrong"
		end
		return success, message
	end
	Remotes.func("BuyRebirthPerk").OnServerInvoke = function(player: Player, id: unknown)
		local ok, success, message = pcall(ProgressionService.buyPerk, player, id)
		if not ok then
			warn("[FillTheStore] Perk purchase failed: " .. tostring(success))
			return false, "Something went wrong"
		end
		return success, message
	end
end

return ProgressionService
