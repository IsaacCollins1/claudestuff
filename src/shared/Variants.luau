--!strict
-- Rare product variants. Each unit that comes out of a delivery box rolls
-- for a variant independently, so a box of Cola can contain one Golden Cola.

export type Variant = {
	Id: string,
	Prefix: string, -- prepended to the product name ("Golden Cola")
	Multiplier: number, -- sell/value multiplier
	Chance: number, -- base chance per unit (before Product Luck)
	Scale: number, -- visual size on the shelf
	Color: Color3, -- UI colour
	Emoji: string,
}

local Variants = {}

-- Ordered from most common to rarest.
Variants.List = {
	{
		Id = "Normal", Prefix = "", Multiplier = 1, Chance = 0, Scale = 1,
		Color = Color3.fromRGB(255, 255, 255), Emoji = "",
	},
	{
		Id = "Golden", Prefix = "Golden ", Multiplier = 10, Chance = 0.03, Scale = 1,
		Color = Color3.fromRGB(255, 200, 40), Emoji = "✨",
	},
	{
		Id = "Rainbow", Prefix = "Rainbow ", Multiplier = 100, Chance = 0.003, Scale = 1,
		Color = Color3.fromRGB(255, 90, 200), Emoji = "🌈",
	},
	{
		Id = "Giant", Prefix = "Giant ", Multiplier = 625, Chance = 0.0004, Scale = 1.45,
		Color = Color3.fromRGB(90, 255, 170), Emoji = "🦖",
	},
} :: { Variant }

Variants.ById = {} :: { [string]: Variant }
Variants.Index = {} :: { [string]: number }
for index, variant in Variants.List do
	Variants.ById[variant.Id] = variant
	Variants.Index[variant.Id] = index
end

Variants.GoldColor = Color3.fromRGB(255, 196, 37)

function Variants.get(id: string): Variant?
	return Variants.ById[id]
end

-- Roll a variant for one unit. `luck` multiplies every rare chance.
function Variants.roll(rng: Random, luck: number): string
	local roll = rng:NextNumber()
	local threshold = 0
	-- Check the rarest first so luck can never make a rarer roll impossible.
	for index = #Variants.List, 2, -1 do
		local variant = Variants.List[index]
		threshold += variant.Chance * luck
		if roll < threshold then
			return variant.Id
		end
	end
	return "Normal"
end

return Variants
