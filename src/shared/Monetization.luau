--!strict
-- Robux shop catalogue.
--
-- To sell these for real: create a Developer Product (for `Products`) or a
-- Game Pass (for `Passes`) on the Creator Dashboard and paste its ID into `Id`.
-- The shop shows the real Robux price once an ID is set.
--
-- While an `Id` is 0 the item is in TEST MODE: buying it in Studio gives it
-- to you for free so you can try it; in a live game the button is disabled.

export type ShopProduct = {
	Key: string,
	Name: string,
	Icon: string,
	Description: string,
	Id: number,
	Robux: number, -- display price until the real price is fetched
	Kind: string, -- "Cash" | "Boost" | "Delivery" | "Crate"
	Color: Color3,
	Base: number?, -- Cash: minimum amount
	EarnedShare: number?, -- Cash: fraction of lifetime earnings (keeps packs useful later on)
	Seconds: number?, -- Boost: duration
}

export type ShopPass = {
	Key: string,
	Name: string,
	Icon: string,
	Description: string,
	Id: number,
	Robux: number,
	Color: Color3,
	Multiplier: number?,
}

local Monetization = {}

local rgb = Color3.fromRGB

Monetization.Products = {
	CashSmall = {
		Key = "CashSmall", Name = "Pocket Money", Icon = "💵", Description = "A quick cash boost",
		Id = 0, Robux = 25, Kind = "Cash", Color = rgb(90, 210, 90), Base = 1500, EarnedShare = 0.1,
	},
	CashMedium = {
		Key = "CashMedium", Name = "Cash Stack", Icon = "💰", Description = "A big pile of cash",
		Id = 0, Robux = 99, Kind = "Cash", Color = rgb(60, 190, 110), Base = 10000, EarnedShare = 0.5,
	},
	CashLarge = {
		Key = "CashLarge", Name = "Money Vault", Icon = "🏦", Description = "A whole vault of cash!",
		Id = 0, Robux = 349, Kind = "Cash", Color = rgb(40, 170, 120), Base = 75000, EarnedShare = 2,
	},
	CustomerRush = {
		Key = "CustomerRush", Name = "Customer Rush", Icon = "🏃", Description = "3x customers for 15 minutes",
		Id = 0, Robux = 49, Kind = "Boost", Color = rgb(255, 150, 40), Seconds = 15 * 60,
	},
	InstantDelivery = {
		Key = "InstantDelivery", Name = "Instant Delivery", Icon = "🚚", Description = "A van full of boxes, right now",
		Id = 0, Robux = 19, Kind = "Delivery", Color = rgb(60, 150, 255),
	},
	GoldenCrate = {
		Key = "GoldenCrate", Name = "Golden Crate", Icon = "🎁", Description = "Your best product, all Golden + a Rainbow!",
		Id = 0, Robux = 79, Kind = "Crate", Color = rgb(255, 196, 37),
	},
} :: { [string]: ShopProduct }

Monetization.Passes = {
	DoubleCash = {
		Key = "DoubleCash", Name = "2x Cash", Icon = "💸", Description = "Every sale pays double. Forever!",
		Id = 0, Robux = 249, Color = rgb(90, 210, 90), Multiplier = 2,
	},
	LuckyCharm = {
		Key = "LuckyCharm", Name = "Lucky Charm", Icon = "🍀", Description = "2x chance of Golden, Rainbow & Giant items",
		Id = 0, Robux = 199, Color = rgb(150, 90, 255), Multiplier = 2,
	},
	BigDeliveries = {
		Key = "BigDeliveries", Name = "Big Deliveries", Icon = "📦", Description = "+2 boxes every delivery, and fuller boxes",
		Id = 0, Robux = 149, Color = rgb(255, 150, 40),
	},
	VIP = {
		Key = "VIP", Name = "VIP Shop", Icon = "👑", Description = "Golden shop, VIP tag and a free extra worker",
		Id = 0, Robux = 299, Color = rgb(255, 196, 37),
	},
} :: { [string]: ShopPass }

Monetization.ProductOrder = { "CashSmall", "CashMedium", "CashLarge", "CustomerRush", "InstantDelivery", "GoldenCrate" }
Monetization.PassOrder = { "DoubleCash", "LuckyCharm", "BigDeliveries", "VIP" }

-- How much a cash pack gives, based on how far the player has got.
function Monetization.cashAmount(product: ShopProduct, totalEarned: number): number
	local base = product.Base or 1000
	local share = product.EarnedShare or 0
	return math.max(base, math.floor(totalEarned * share / 100) * 100)
end

function Monetization.productById(id: number): ShopProduct?
	if id == 0 then
		return nil
	end
	for _, product in Monetization.Products do
		if product.Id == id then
			return product
		end
	end
	return nil
end

function Monetization.passById(id: number): ShopPass?
	if id == 0 then
		return nil
	end
	for _, pass in Monetization.Passes do
		if pass.Id == id then
			return pass
		end
	end
	return nil
end

return Monetization
