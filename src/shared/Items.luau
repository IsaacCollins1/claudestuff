--!strict
-- An "item key" identifies one stockable thing: a product plus its variant.
--   "Cola"          -> normal Cola
--   "Cola:Golden"   -> Golden Cola
-- Inventory, shelves and saves all use these keys.

local Products = require(script.Parent.Products)
local Variants = require(script.Parent.Variants)

local Items = {}

function Items.key(productId: string, variantId: string?): string
	if variantId == nil or variantId == "Normal" then
		return productId
	end
	return productId .. ":" .. variantId
end

-- Returns productId, variantId (or nil, nil for malformed keys).
function Items.parse(key: string): (string?, string?)
	local productId, variantId = string.match(key, "^([%w_]+):([%w_]+)$")
	if productId and variantId then
		return productId, variantId
	end
	if string.match(key, "^[%w_]+$") then
		return key, "Normal"
	end
	return nil, nil
end

function Items.isValid(key: unknown): boolean
	if type(key) ~= "string" or #key > 40 then
		return false
	end
	local productId, variantId = Items.parse(key)
	return productId ~= nil
		and variantId ~= nil
		and Products.ById[productId] ~= nil
		and Variants.ById[variantId] ~= nil
end

function Items.product(key: string): Products.Product
	local productId = Items.parse(key)
	local product = productId and Products.ById[productId]
	assert(product, "Unknown item key " .. key)
	return product
end

function Items.variant(key: string): Variants.Variant
	local _, variantId = Items.parse(key)
	return (variantId and Variants.ById[variantId]) or Variants.ById.Normal
end

function Items.sellPrice(key: string): number
	return Items.product(key).SellPrice * Items.variant(key).Multiplier
end

function Items.value(key: string): number
	return Items.product(key).BuyPrice * Items.variant(key).Multiplier
end

function Items.displayName(key: string): string
	return Items.variant(key).Prefix .. Items.product(key).Name
end

function Items.icon(key: string): string
	return Items.product(key).Icon
end

function Items.isRare(key: string): boolean
	return Items.variant(key).Id ~= "Normal"
end

-- Sort helper: by product order, then variant order.
function Items.compare(a: string, b: string): boolean
	local pa, pb = Items.product(a), Items.product(b)
	if pa ~= pb then
		return Products.Index[pa.Id] < Products.Index[pb.Id]
	end
	return Variants.Index[Items.variant(a).Id] < Variants.Index[Items.variant(b).Id]
end

return Items
