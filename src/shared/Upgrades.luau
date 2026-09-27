--!strict
-- Upgrade definitions and the formulas behind them.
-- Server code uses these to apply effects; the client uses them to draw the menu.

export type UpgradeDef = {
	Id: string,
	Name: string,
	Icon: string,
	Color: Color3,
	Description: string,
	StartLevel: number,
	MaxLevel: number,
	-- Either a growth formula (BaseCost * Growth^purchases) or a fixed list of costs.
	BaseCost: number?,
	Growth: number?,
	Costs: { number }?,
	-- Human readable effect at a level, e.g. "15 per shelf".
	Effect: (level: number) -> string,
}

local Upgrades = {}

-- 1.5 -> "1.5", 2 -> "2", 1.25 -> "1.25"
local function num(n: number): string
	local text = string.format("%.2f", n)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

local SHELF_CAPACITY = { 12, 15, 18, 21, 24, 30, 36, 42, 48 }

function Upgrades.shelfCapacity(level: number): number
	return SHELF_CAPACITY[math.clamp(level + 1, 1, #SHELF_CAPACITY)]
end

function Upgrades.boxesPerDelivery(level: number): number
	return 3 + math.ceil(level / 2)
end

function Upgrades.quantityMultiplier(level: number): number
	return 1 + 0.15 * level
end

function Upgrades.customerInterval(level: number): number
	return 4.5 * 0.87 ^ level
end

-- Customers take ~20s to walk in, shop and leave, so the shop needs room for
-- several at once for sales to keep up with deliveries.
function Upgrades.maxCustomers(level: number, storeLevel: number): number
	return 3 + storeLevel * 2 + math.floor(level / 2)
end

function Upgrades.luckMultiplier(level: number): number
	return 1 + 0.25 * level
end

function Upgrades.workerCount(level: number): number
	return level
end

local STORE_NAMES = { "Corner Shop", "Local Store", "Mini Supermarket" }
local STORE_SHELVES = { 2, 4, 10 }

Upgrades.Order = { "ShelfCapacity", "DeliverySize", "CustomerRate", "ProductLuck", "StoreSize", "Workers" }

Upgrades.Defs = {
	ShelfCapacity = {
		Id = "ShelfCapacity",
		Name = "Shelf Capacity",
		Icon = "🗄️",
		Color = Color3.fromRGB(64, 156, 255),
		Description = "Shelves hold more products",
		StartLevel = 0,
		MaxLevel = #SHELF_CAPACITY - 1,
		BaseCost = 80,
		Growth = 1.75,
		Effect = function(level: number): string
			return `{Upgrades.shelfCapacity(level)} per shelf`
		end,
	},
	DeliverySize = {
		Id = "DeliverySize",
		Name = "Delivery Size",
		Icon = "🚚",
		Color = Color3.fromRGB(255, 150, 40),
		Description = "More boxes and bigger boxes",
		StartLevel = 0,
		MaxLevel = 6,
		BaseCost = 120,
		Growth = 1.9,
		Effect = function(level: number): string
			return `{Upgrades.boxesPerDelivery(level)} boxes, x{num(Upgrades.quantityMultiplier(level))} items`
		end,
	},
	CustomerRate = {
		Id = "CustomerRate",
		Name = "Customer Rate",
		Icon = "🧍",
		Color = Color3.fromRGB(88, 201, 91),
		Description = "Customers arrive more often",
		StartLevel = 0,
		MaxLevel = 8,
		BaseCost = 100,
		Growth = 1.8,
		Effect = function(level: number): string
			return `1 every {num(Upgrades.customerInterval(level))}s`
		end,
	},
	ProductLuck = {
		Id = "ProductLuck",
		Name = "Product Luck",
		Icon = "🍀",
		Color = Color3.fromRGB(176, 92, 255),
		Description = "Better odds of Golden, Rainbow & Giant items",
		StartLevel = 0,
		MaxLevel = 8,
		BaseCost = 250,
		Growth = 2,
		Effect = function(level: number): string
			return `x{num(Upgrades.luckMultiplier(level))} rare chance`
		end,
	},
	StoreSize = {
		Id = "StoreSize",
		Name = "Store Size",
		Icon = "🏪",
		Color = Color3.fromRGB(255, 90, 120),
		Description = "Expand your shop with more shelves",
		StartLevel = 1,
		MaxLevel = #STORE_NAMES,
		Costs = { 900, 6000 },
		Effect = function(level: number): string
			local index = math.clamp(level, 1, #STORE_NAMES)
			return `{STORE_NAMES[index]} ({STORE_SHELVES[index]} shelves)`
		end,
	},
	Workers = {
		Id = "Workers",
		Name = "Workers",
		Icon = "👷",
		Color = Color3.fromRGB(255, 200, 40),
		Description = "Staff who restock shelves for you",
		StartLevel = 0,
		MaxLevel = 3,
		Costs = { 1500, 7500, 25000 },
		Effect = function(level: number): string
			if level == 0 then
				return "No staff yet"
			end
			return `{level} worker{if level == 1 then "" else "s"}`
		end,
	},
} :: { [string]: UpgradeDef }

-- Cost to buy the next level from `currentLevel`, or nil if maxed out.
function Upgrades.getCost(id: string, currentLevel: number): number?
	local def = Upgrades.Defs[id]
	if not def or currentLevel >= def.MaxLevel then
		return nil
	end
	local purchases = currentLevel - def.StartLevel
	if def.Costs then
		return def.Costs[purchases + 1]
	end
	local base = def.BaseCost or 100
	local growth = def.Growth or 2
	return math.floor(base * growth ^ purchases + 0.5)
end

-- Total money spent reaching the given levels (used for store value).
function Upgrades.totalSpent(levels: { [string]: number }): number
	local total = 0
	for id, def in Upgrades.Defs do
		local level = levels[id] or def.StartLevel
		for l = def.StartLevel, level - 1 do
			total += Upgrades.getCost(id, l) or 0
		end
	end
	return total
end

function Upgrades.defaultLevels(): { [string]: number }
	local levels = {}
	for id, def in Upgrades.Defs do
		levels[id] = def.StartLevel
	end
	return levels
end

return Upgrades
