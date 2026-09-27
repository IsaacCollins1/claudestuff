--!strict
local Config = require(script.Parent.Config)

local Format = {}

function Format.commas(n: number): string
	local negative = n < 0
	local digits = tostring(math.floor(math.abs(n)))
	local formatted = digits
	while true do
		local replaced, count = string.gsub(formatted, "^(%d+)(%d%d%d)", "%1,%2")
		formatted = replaced
		if count == 0 then
			break
		end
	end
	return (if negative then "-" else "") .. formatted
end

local SUFFIXES = {
	{ Size = 1e12, Letter = "T" },
	{ Size = 1e9, Letter = "B" },
	{ Size = 1e6, Letter = "M" },
	{ Size = 1e3, Letter = "K" },
}

-- £1,250 up to a million, then £1.25M
function Format.money(n: number): string
	if math.abs(n) >= 1e6 then
		return Config.Currency .. Format.short(n)
	end
	return Config.Currency .. Format.commas(n)
end

-- 1.2K / 3.4M style numbers
function Format.short(n: number): string
	local absolute = math.abs(n)
	for _, suffix in SUFFIXES do
		if absolute >= suffix.Size then
			local value = n / suffix.Size
			local text = if math.abs(value) >= 100
				then string.format("%d", math.floor(value))
				else string.format("%.3g", value)
			return text .. suffix.Letter
		end
	end
	return tostring(math.floor(n))
end

function Format.shortMoney(n: number): string
	return Config.Currency .. Format.short(n)
end

return Format
