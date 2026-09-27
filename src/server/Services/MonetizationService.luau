--!strict
-- Robux shop: Developer Products (via ProcessReceipt), Game Passes, and free
-- "test purchases" in Studio for items whose ID hasn't been set up yet.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local Monetization = require(Shared.Monetization)
local Remotes = require(Shared.Remotes)

local Boxes = require(script.Parent.Boxes)
local Deliveries = require(script.Parent.Deliveries)
local Net = require(script.Parent.Net)
local Perks = require(script.Parent.Perks)
local PlayerData = require(script.Parent.PlayerData)
local Registry = require(script.Parent.Registry)
local Stores = require(script.Parent.Stores)

local MonetizationService = {}

local MAX_RECEIPTS = 50

local function vipTag(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or head:FindFirstChild("VipTag") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "VipTag"
	gui.Size = UDim2.fromScale(4, 1)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Text = "👑 VIP"
	label.TextColor3 = Color3.fromRGB(255, 210, 60)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 50, 0)
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = head
end

-- One-off effects when a pass becomes active.
local function applyPass(player: Player, key: string, announce: boolean)
	if key == "VIP" then
		vipTag(player)
		-- Rebuild the shop in gold (also adds the free VIP worker).
		if Registry.store(player) then
			Stores.rebuild(player)
		end
	end
	if announce then
		local pass = Monetization.Passes[key]
		Net.notify(player, "Purchase", `{pass.Icon} {string.upper(pass.Name)} UNLOCKED!`)
		Net.effectTo(player, "Purchase", { Key = key })
	end
end

local function grantPass(player: Player, key: string, announce: boolean)
	if Perks.has(player, key) then
		return
	end
	Perks.setOwned(player, key, true)
	applyPass(player, key, announce)
end

-- Gives the player what they bought. Returns false if it can't be granted yet.
local function grantProduct(player: Player, product: Monetization.ShopProduct): boolean
	local data = PlayerData.get(player)
	local session = Registry.session(player)
	if not data then
		return false
	end
	if product.Kind == "Cash" then
		local amount = Monetization.cashAmount(product, data.TotalEarned)
		PlayerData.giveCash(player, amount)
		Net.notify(player, "Purchase", `💰 +{Format.money(amount)}!`)
	elseif product.Kind == "Boost" then
		Perks.addBoost(player, product.Key, product.Seconds or 600)
		Net.notify(player, "Purchase", `{product.Icon} {string.upper(product.Name)} ACTIVE!`)
	elseif product.Kind == "Delivery" then
		if not session then
			return false
		end
		task.spawn(Deliveries.deliver, session, true)
		Net.notify(player, "Purchase", "🚚 EXPRESS DELIVERY ON ITS WAY!")
	elseif product.Kind == "Crate" then
		if not session then
			return false
		end
		Boxes.dropCrate(session)
		Net.notify(player, "Purchase", "🎁 GOLDEN CRATE INCOMING!")
	else
		return false
	end
	Net.effectTo(player, "Purchase", { Key = product.Key })
	PlayerData.markDirty(player)
	return true
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local data = player and PlayerData.get(player)
	if not player or not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if table.find(data.Receipts, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = Monetization.productById(receipt.ProductId)
	if not product then
		warn(`[FillTheStore] Unknown developer product {receipt.ProductId} — add it to Shared/Monetization`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(grantProduct, player, product)
	if not ok or not granted then
		warn("[FillTheStore] Couldn't grant purchase: " .. tostring(granted))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(data.Receipts, purchaseId)
	while #data.Receipts > MAX_RECEIPTS do
		table.remove(data.Receipts, 1)
	end
	-- Make sure the purchase is saved before telling Roblox it's done. If the
	-- save fails, Roblox retries later; the receipt id above stops a double grant.
	if PlayerData.canSave() and not PlayerData.save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Called once the player's data has loaded.
function MonetizationService.playerJoined(player: Player)
	for key, pass in Monetization.Passes do
		if pass.Id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
			end)
			if ok and owns then
				Perks.setOwned(player, key, true)
			end
		end
	end
	if Perks.has(player, "VIP") then
		vipTag(player)
	end
	player.CharacterAdded:Connect(function()
		task.wait(1)
		if Perks.has(player, "VIP") then
			vipTag(player)
		end
	end)
end

function MonetizationService.playerLeft(player: Player)
	Perks.clear(player)
end

function MonetizationService.init()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local pass = Monetization.passById(passId)
		if purchased and pass then
			grantPass(player, pass.Key, true)
		end
	end)

	-- Studio-only: items without a real ID can be "bought" for free to test them.
	Remotes.func("TestPurchase").OnServerInvoke = function(player: Player, kind: unknown, key: unknown)
		if not RunService:IsStudio() then
			return false, "Test purchases only work in Studio"
		end
		if kind == "Product" and type(key) == "string" and Monetization.Products[key] then
			local product = Monetization.Products[key]
			if product.Id ~= 0 then
				return false, "This item has a real ID — use the purchase prompt"
			end
			local ok, granted = pcall(grantProduct, player, product)
			return ok and granted, "Test purchase (Studio only)"
		elseif kind == "Pass" and type(key) == "string" and Monetization.Passes[key] then
			if Monetization.Passes[key].Id ~= 0 then
				return false, "This pass has a real ID — use the purchase prompt"
			end
			grantPass(player, key, true)
			return true, "Test purchase (Studio only)"
		end
		return false, "Unknown item"
	end

	table.insert(PlayerData.SnapshotExtras, function(player: Player, snapshot: { [string]: any })
		snapshot.Passes = Perks.ownedList(player)
		snapshot.IsStudio = RunService:IsStudio()
	end)
end

return MonetizationService
