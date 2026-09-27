--!strict
-- Long-term progression, shared by the server (rules) and client (menus):
--
--   * Level      XP from selling and unpacking. Every product has an unlock
--                level (Products.UnlockLevel); levelling up also pays a cash
--                reward.
--   * Stars      Selling a product earns stars (mastery); each star makes that
--                product sell for 10% more.
--   * Rebirth    Trade a pile of cash for a permanent cash bonus and Rebirth
--                Tokens. Cash, upgrades, shop size and stock reset; levels,
--                unlocks, stars, perks and game passes are kept.
--   * Perks      Permanent upgrades bought with Rebirth Tokens.

local Format = require(script.Parent.Format)
local Products = require(script.Parent.Products)

local Progression = {}

-- Level -------------------------------------------------------------------------

Progression.MaxLevel = 100
Progression.XpPerBox = 2

function Progression.xpToNext(level: number): number
	return math.floor(30 * level ^ 1.5)
end

-- XP for selling one unit: pricier products are worth more.
function Progression.xpForSale(product: Products.Product): number
	return math.max(1, math.floor(math.sqrt(product.SellPrice) + 0.5))
end

function Progression.levelReward(level: number): number
	return 25 * level
end

function Progression.isUnlocked(product: Products.Product, level: number): boolean
	return product.UnlockLevel <= level
end

-- Products that unlock exactly at `level`.
function Progression.unlocksAt(level: number): { Products.Product }
	local list = {}
	for _, product in Products.List do
		if product.UnlockLevel == level then
			table.insert(list, product)
		end
	end
	return list
end

-- The next product still to unlock after `level`.
function Progression.nextUnlock(level: number): Products.Product?
	local best: Products.Product? = nil
	for _, product in Products.List do
		if product.UnlockLevel > level and (not best or product.UnlockLevel < best.UnlockLevel) then
			best = product
		end
	end
	return best
end

-- Stars (product mastery) ---------------------------------------------------------

Progression.StarThresholds = { 20, 75, 200, 500, 1200 } -- units sold for each star
Progression.StarBonus = 0.1 -- +10% sell price per star
Progression.MaxStars = #Progression.StarThresholds

function Progression.stars(sold: number): number
	local stars = 0
	for index, threshold in Progression.StarThresholds do
		if sold >= threshold then
			stars = index
		end
	end
	return stars
end

function Progression.starMultiplier(sold: number): number
	return 1 + Progression.StarBonus * Progression.stars(sold)
end

-- Units needed for the next star (nil when maxed).
function Progression.nextStarAt(sold: number): number?
	for _, threshold in Progression.StarThresholds do
		if sold < threshold then
			return threshold
		end
	end
	return nil
end

-- Rebirth -------------------------------------------------------------------------

Progression.RebirthBaseCost = 50000
Progression.RebirthCostGrowth = 2.5
Progression.RebirthCashBonus = 0.5 -- +50% cash from sales per rebirth

function Progression.rebirthCost(rebirths: number): number
	return math.floor(Progression.RebirthBaseCost * Progression.RebirthCostGrowth ^ rebirths)
end

function Progression.rebirthMultiplier(rebirths: number): number
	return 1 + Progression.RebirthCashBonus * rebirths
end

-- Tokens earned for reaching rebirth number `rebirths` (every 5th is a bonus).
function Progression.tokensFor(rebirths: number): number
	return if rebirths % 5 == 0 then 2 else 1
end

-- Rebirth perks -------------------------------------------------------------------

export type PerkDef = {
	Id: string,
	Name: string,
	Icon: string,
	Color: Color3,
	Description: string,
	Costs: { number }, -- tokens for each level
	Effect: (level: number) -> string,
}

local rgb = Color3.fromRGB

Progression.PerkOrder = { "HeadStart", "ExpressVans", "LuckyBoxes", "BusyStreet", "BulkBoxes" }

Progression.Perks = {
	HeadStart = {
		Id = "HeadStart",
		Name = "Head Start",
		Icon = "💰",
		Color = rgb(90, 210, 90),
		Description = "Start every rebirth with cash",
		Costs = { 1, 1, 2, 2, 3 },
		Effect = function(level: number): string
			return `{Format.money(1000 * level)} to start`
		end,
	},
	ExpressVans = {
		Id = "ExpressVans",
		Name = "Express Vans",
		Icon = "🚚",
		Color = rgb(60, 150, 255),
		Description = "Deliveries arrive sooner",
		Costs = { 1, 1, 2, 2, 3 },
		Effect = function(level: number): string
			return `{math.floor((1 - 0.92 ^ level) * 100 + 0.5)}% shorter wait`
		end,
	},
	LuckyBoxes = {
		Id = "LuckyBoxes",
		Name = "Lucky Boxes",
		Icon = "🍀",
		Color = rgb(150, 90, 255),
		Description = "More Golden, Rainbow & Giant items",
		Costs = { 1, 2, 2, 3, 3 },
		Effect = function(level: number): string
			return `+{10 * level}% luck`
		end,
	},
	BusyStreet = {
		Id = "BusyStreet",
		Name = "Busy Street",
		Icon = "🏃",
		Color = rgb(255, 150, 40),
		Description = "Customers come more often",
		Costs = { 1, 1, 2, 2, 3 },
		Effect = function(level: number): string
			return `+{8 * level}% customers`
		end,
	},
	BulkBoxes = {
		Id = "BulkBoxes",
		Name = "Bulk Boxes",
		Icon = "📦",
		Color = rgb(205, 150, 95),
		Description = "More items in every delivery box",
		Costs = { 1, 2, 2, 3, 3 },
		Effect = function(level: number): string
			return `+{10 * level}% items`
		end,
	},
} :: { [string]: PerkDef }

function Progression.perkMaxLevel(id: string): number
	local def = Progression.Perks[id]
	return if def then #def.Costs else 0
end

-- Token cost of the next level of a perk (nil when maxed or unknown).
function Progression.perkCost(id: string, level: number): number?
	local def = Progression.Perks[id]
	return def and def.Costs[level + 1]
end

function Progression.headStartCash(level: number): number
	return 1000 * level
end

function Progression.deliveryIntervalMultiplier(level: number): number
	return 0.92 ^ level
end

function Progression.luckMultiplier(level: number): number
	return 1 + 0.1 * level
end

function Progression.customerIntervalMultiplier(level: number): number
	return 1 / (1 + 0.08 * level)
end

function Progression.boxQuantityMultiplier(level: number): number
	return 1 + 0.1 * level
end

return Progression
