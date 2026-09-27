--!strict
-- Every product the store can sell.
-- To add a product: add an entry to `List` (give it a unique Id) and, if it needs a
-- new look, add a shape builder in ProductVisuals.

export type Rarity = {
	Id: string,
	Name: string,
	Weight: number, -- relative chance of a delivery box containing a product of this rarity
	Color: Color3,
}

export type Product = {
	Id: string,
	Name: string,
	Icon: string, -- emoji used in the UI and notifications
	Category: string,
	Rarity: string,
	BuyPrice: number, -- wholesale value (used for store value)
	SellPrice: number, -- what a customer pays
	UnlockLevel: number, -- store level needed before deliveries contain it
	BoxMin: number, -- units per delivery box
	BoxMax: number,
	Shape: string, -- visual builder in ProductVisuals
	Color: Color3,
	Accent: Color3,
}

local Products = {}

Products.Rarities = {
	Common = { Id = "Common", Name = "Common", Weight = 100, Color = Color3.fromRGB(196, 150, 96) },
	Uncommon = { Id = "Uncommon", Name = "Uncommon", Weight = 55, Color = Color3.fromRGB(88, 201, 91) },
	Rare = { Id = "Rare", Name = "Rare", Weight = 28, Color = Color3.fromRGB(64, 156, 255) },
	Epic = { Id = "Epic", Name = "Epic", Weight = 11, Color = Color3.fromRGB(176, 92, 255) },
	Legendary = { Id = "Legendary", Name = "Legendary", Weight = 4, Color = Color3.fromRGB(255, 190, 40) },
} :: { [string]: Rarity }

local rgb = Color3.fromRGB

Products.List = {
	{
		Id = "Water", Name = "Water", Icon = "💧", Category = "Drinks", Rarity = "Common",
		BuyPrice = 1, SellPrice = 3, UnlockLevel = 1, BoxMin = 9, BoxMax = 13,
		Shape = "Bottle", Color = rgb(120, 200, 255), Accent = rgb(30, 110, 230),
	},
	{
		Id = "Crisps", Name = "Crisps", Icon = "🥔", Category = "Snacks", Rarity = "Common",
		BuyPrice = 2, SellPrice = 5, UnlockLevel = 1, BoxMin = 8, BoxMax = 12,
		Shape = "Bag", Color = rgb(255, 214, 60), Accent = rgb(230, 60, 50),
	},
	{
		Id = "Chocolate", Name = "Chocolate", Icon = "🍫", Category = "Snacks", Rarity = "Common",
		BuyPrice = 2, SellPrice = 6, UnlockLevel = 1, BoxMin = 8, BoxMax = 12,
		Shape = "Bar", Color = rgb(110, 62, 36), Accent = rgb(120, 60, 200),
	},
	{
		Id = "Cola", Name = "Cola", Icon = "🥤", Category = "Drinks", Rarity = "Common",
		BuyPrice = 3, SellPrice = 8, UnlockLevel = 1, BoxMin = 8, BoxMax = 12,
		Shape = "Can", Color = rgb(225, 30, 40), Accent = rgb(245, 245, 245),
	},
	{
		Id = "EnergyDrink", Name = "Energy Drink", Icon = "⚡", Category = "Drinks", Rarity = "Uncommon",
		BuyPrice = 5, SellPrice = 12, UnlockLevel = 1, BoxMin = 6, BoxMax = 10,
		Shape = "Can", Color = rgb(40, 40, 50), Accent = rgb(120, 255, 60),
	},
	{
		Id = "Cereal", Name = "Cereal", Icon = "🥣", Category = "Groceries", Rarity = "Uncommon",
		BuyPrice = 6, SellPrice = 15, UnlockLevel = 1, BoxMin = 5, BoxMax = 8,
		Shape = "Cereal", Color = rgb(255, 140, 30), Accent = rgb(255, 255, 255),
	},
	{
		Id = "ToiletRoll", Name = "Toilet Roll", Icon = "🧻", Category = "Household", Rarity = "Uncommon",
		BuyPrice = 7, SellPrice = 18, UnlockLevel = 2, BoxMin = 5, BoxMax = 8,
		Shape = "Roll", Color = rgb(250, 250, 250), Accent = rgb(140, 200, 255),
	},
	{
		Id = "Pizza", Name = "Pizza", Icon = "🍕", Category = "Frozen", Rarity = "Rare",
		BuyPrice = 9, SellPrice = 22, UnlockLevel = 2, BoxMin = 4, BoxMax = 7,
		Shape = "Pizza", Color = rgb(245, 235, 215), Accent = rgb(220, 50, 40),
	},
	{
		Id = "Cleaning", Name = "Cleaning Spray", Icon = "🧴", Category = "Household", Rarity = "Rare",
		BuyPrice = 12, SellPrice = 30, UnlockLevel = 2, BoxMin = 4, BoxMax = 6,
		Shape = "Spray", Color = rgb(90, 220, 200), Accent = rgb(255, 255, 255),
	},
	{
		Id = "Headphones", Name = "Headphones", Icon = "🎧", Category = "Electronics", Rarity = "Rare",
		BuyPrice = 25, SellPrice = 60, UnlockLevel = 2, BoxMin = 2, BoxMax = 4,
		Shape = "Headphones", Color = rgb(35, 35, 45), Accent = rgb(255, 80, 160),
	},
	{
		Id = "Smartphone", Name = "Smartphone", Icon = "📱", Category = "Electronics", Rarity = "Epic",
		BuyPrice = 60, SellPrice = 150, UnlockLevel = 3, BoxMin = 2, BoxMax = 3,
		Shape = "Phone", Color = rgb(30, 30, 38), Accent = rgb(80, 180, 255),
	},
	{
		Id = "Console", Name = "Games Console", Icon = "🎮", Category = "Electronics", Rarity = "Epic",
		BuyPrice = 100, SellPrice = 250, UnlockLevel = 3, BoxMin = 1, BoxMax = 3,
		Shape = "Console", Color = rgb(245, 245, 250), Accent = rgb(60, 110, 255),
	},
	{
		Id = "Laptop", Name = "Laptop", Icon = "💻", Category = "Electronics", Rarity = "Epic",
		BuyPrice = 180, SellPrice = 450, UnlockLevel = 3, BoxMin = 1, BoxMax = 2,
		Shape = "Laptop", Color = rgb(190, 195, 205), Accent = rgb(90, 200, 255),
	},
	{
		Id = "Television", Name = "Television", Icon = "📺", Category = "Electronics", Rarity = "Legendary",
		BuyPrice = 280, SellPrice = 700, UnlockLevel = 3, BoxMin = 1, BoxMax = 2,
		Shape = "TV", Color = rgb(25, 25, 30), Accent = rgb(90, 160, 255),
	},
} :: { Product }

Products.ById = {} :: { [string]: Product }
Products.Index = {} :: { [string]: number } -- display order
for index, product in Products.List do
	Products.ById[product.Id] = product
	Products.Index[product.Id] = index
end

-- Products that deliveries can contain at a given store level.
function Products.poolForLevel(storeLevel: number): { Product }
	local pool = {}
	for _, product in Products.List do
		if product.UnlockLevel <= storeLevel then
			table.insert(pool, product)
		end
	end
	return pool
end

-- Weighted random product for a delivery box.
function Products.rollForBox(rng: Random, storeLevel: number): Product
	local pool = Products.poolForLevel(storeLevel)
	local total = 0
	for _, product in pool do
		total += Products.Rarities[product.Rarity].Weight
	end
	local roll = rng:NextNumber() * total
	for _, product in pool do
		roll -= Products.Rarities[product.Rarity].Weight
		if roll <= 0 then
			return product
		end
	end
	return pool[#pool]
end

return Products
