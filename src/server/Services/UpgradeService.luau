--!strict
-- Handles upgrade purchases (server-authoritative) and applies their effects.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Products = require(Shared.Products)
local Remotes = require(Shared.Remotes)
local StoreLevels = require(Shared.StoreLevels)
local Upgrades = require(Shared.Upgrades)

local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)
local Registry = require(script.Parent.Registry)
local Shelves = require(script.Parent.Shelves)
local Stores = require(script.Parent.Stores)
local Workers = require(script.Parent.Workers)

local UpgradeService = {}

local lastPurchase: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local function apply(player: Player, id: string, level: number)
	local store = Registry.store(player)
	if id == "ShelfCapacity" then
		if store then
			Shelves.setCapacity(store, Upgrades.shelfCapacity(level))
		end
	elseif id == "StoreSize" then
		local newStore = Stores.rebuild(player)
		if newStore then
			local session = newStore.Session
			local signPosition = (session.PlotCFrame * newStore.Layout.SignCFrame).Position
			Net.effectAll("StoreExpanded", { Position = signPosition, OwnerId = player.UserId })
			Net.notify(player, "Expand", "🏪 STORE EXPANDED! " .. string.upper(StoreLevels.getSpec(level).Name))
			local unlocked = {}
			for _, product in Products.List do
				if product.UnlockLevel == level then
					table.insert(unlocked, product.Icon)
				end
			end
			if #unlocked > 0 then
				Net.notify(player, "Info", "New products in deliveries: " .. table.concat(unlocked, " "))
			end
		end
	elseif id == "Workers" then
		if store then
			Workers.refresh(store)
		end
	end
end

function UpgradeService.buy(player: Player, id: unknown): (boolean, string)
	if type(id) ~= "string" then
		return false, "Unknown upgrade"
	end
	local def = Upgrades.Defs[id]
	local data = PlayerData.get(player)
	if not def or not data then
		return false, "Unknown upgrade"
	end
	local now = os.clock()
	if now - (lastPurchase[player] or 0) < 0.2 then
		return false, "Slow down!"
	end
	lastPurchase[player] = now

	local level = data.Upgrades[id] or def.StartLevel
	local cost = Upgrades.getCost(id, level)
	if not cost then
		return false, "Already maxed out!"
	end
	if not PlayerData.spend(player, cost) then
		return false, "Not enough cash!"
	end
	data.Upgrades[id] = level + 1
	apply(player, id, level + 1)
	PlayerData.markDirty(player)
	Net.effectTo(player, "Upgrade", { Id = id, Level = level + 1 })
	return true, `{def.Name} upgraded!`
end

function UpgradeService.init()
	Remotes.func("BuyUpgrade").OnServerInvoke = function(player: Player, id: unknown)
		local ok, result, message = pcall(UpgradeService.buy, player, id)
		if not ok then
			warn("[FillTheStore] Upgrade failed: " .. tostring(result))
			return false, "Something went wrong"
		end
		return result, message
	end

	Remotes.event("SelectProduct").OnServerEvent:Connect(function(player: Player, productId: unknown)
		local data = PlayerData.get(player)
		if not data then
			return
		end
		if productId == nil then
			data.SelectedProduct = nil
		elseif type(productId) == "string" and Products.ById[productId] then
			data.SelectedProduct = productId
		else
			return
		end
		PlayerData.markDirty(player)
	end)
end

return UpgradeService
