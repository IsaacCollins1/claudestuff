--!nocheck
-- Headless play-test for Fill the Store!
--
-- Runs the real server + client scripts from the built place file inside the
-- emulator and has a bot play like a brand-new player, following the
-- tutorial. Then it checks upgrades, expansion, workers, the Robux shop,
-- leaderboards, a second player, saving/loading and Studio without API access.
--
--   rojo build default.project.json -o build/FillTheStore.rbxlx
--   lune run tests/playtest.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Instances = require("./emulator/Instances")
local Runtime = require("./emulator/Runtime")
local Scheduler = require("./emulator/Scheduler")

local Vector3 = roblox.Vector3
local Enum = roblox.Enum
local PLACE = process.args[1] or "build/FillTheStore.rbxlx"

local failures = {}
local function check(condition: boolean, message: string)
	if condition then
		print("  \27[32m✔\27[0m " .. message)
	else
		print("  \27[31m✘ " .. message .. "\27[0m")
		table.insert(failures, message)
	end
end

local function section(title: string)
	print("\n\27[1m== " .. title .. " ==\27[0m")
end

-- A bot that plays through the real prompts and UI ------------------------------------

local function makeBot(runtime, player)
	local game = runtime.game
	local services = game.ServerScriptService.Server.Services
	local shared = game.ReplicatedStorage.Shared
	local PlayerData = runtime:serverModule(services.PlayerData)
	local Registry = runtime:serverModule(services.Registry)
	local Shelves = runtime:serverModule(services.Shelves)
	local StoreLevels = runtime:serverModule(shared.StoreLevels)
	local Upgrades = runtime:serverModule(shared.Upgrades)

	local bot = { runtime = runtime, player = player, log = {} }

	function bot.data()
		return PlayerData.get(player)
	end
	function bot.session()
		return Registry.session(player)
	end
	function bot.store()
		local session = Registry.session(player)
		return session and session.Store
	end
	function bot.stock(): number
		return PlayerData.inventoryTotal(player)
	end
	function bot.carrying(): boolean
		return player:GetAttribute("CarryingBox") == true
	end
	function bot.world(localPoint)
		return bot.session().PlotCFrame:PointToWorldSpace(localPoint)
	end
	function bot.gui()
		return player.PlayerGui.FillTheStoreUI
	end
	function bot.say(message)
		table.insert(bot.log, string.format("[t=%6.1f] %s", Scheduler.now, message))
	end

	function bot.walkLocal(points)
		for _, point in points do
			if not runtime:walkTo(player, bot.world(point), 15) then
				return false
			end
		end
		return true
	end

	function bot.walkNear(position: Vector3, distance: number)
		local root = runtime:root(player)
		local offset = root.Position - position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local target = if flat.Magnitude > 0.1 then position + flat.Unit * distance else position
		return runtime:walkTo(player, Vector3.new(target.X, position.Y, target.Z), 20)
	end

	function bot.isInside(): boolean
		local root = runtime:root(player)
		return StoreLevels.isInside(bot.store().Layout, bot.session().PlotCFrame:PointToObjectSpace(root.Position), 0)
	end

	function bot.boxesOnPad()
		local folder = bot.session().PlotModel:FindFirstChild("Boxes")
		local result = {}
		if folder then
			for _, model in folder:GetChildren() do
				local root = model:FindFirstChild("Box")
				if root and root:FindFirstChild("BoxPrompt") then
					table.insert(result, root)
				end
			end
		end
		return result
	end

	function bot.pickUpBox(): boolean
		local boxes = bot.boxesOnPad()
		if #boxes == 0 then
			return false
		end
		if bot.isInside() then
			bot.walkLocal({ bot.store().Layout.DoorInside, bot.store().Layout.DoorOutside })
		end
		local root = runtime:root(player)
		table.sort(boxes, function(a, b)
			return (a.Position - root.Position).Magnitude < (b.Position - root.Position).Magnitude
		end)
		local box = boxes[1]
		bot.walkNear(box.Position, 3)
		local ok, why = runtime:trigger(player, box.BoxPrompt)
		runtime:run(0.2)
		if not ok or not bot.carrying() then
			bot.say("could not pick up box: " .. tostring(why))
			return false
		end
		bot.say("picked up a box")
		return true
	end

	function bot.enterStore()
		if bot.isInside() then
			return true
		end
		local layout = bot.store().Layout
		return bot.walkLocal({ layout.DoorOutside, layout.DoorInside })
	end

	function bot.emptiestShelf()
		local best, ratio = nil, math.huge
		for _, shelf in bot.store().Shelves do
			local r = Shelves.count(shelf) / shelf.Capacity
			if Shelves.free(shelf) > 0 and r < ratio then
				best, ratio = shelf, r
			end
		end
		return best
	end

	-- Walk to a shelf's customer spot (via the centre aisle).
	function bot.goToShelf(shelf)
		local layout = bot.store().Layout
		bot.enterStore()
		bot.walkLocal(StoreLevels.findPath(layout, "Door", shelf.Node))
		runtime:run(0.25) -- let the client update prompts
	end

	-- The new core action: carry a box to a shelf and press E to unpack it there.
	function bot.unpackAtShelf(): boolean
		local shelf = bot.emptiestShelf()
		local before = bot.data().Stats.BoxesOpened
		if shelf then
			bot.goToShelf(shelf)
			local prompt = shelf.Model.Base.PromptAttachment.StockPrompt
			bot.lastPromptText = prompt.ActionText
			local placedBefore = Shelves.count(shelf)
			local ok, why = runtime:trigger(player, prompt)
			runtime:runUntil(10, function()
				return not shelf.Busy and bot.data().Stats.BoxesOpened > before
			end)
			runtime:run(0.2)
			if not ok then
				bot.say("could not unpack at shelf: " .. tostring(why))
				return false
			end
			bot.say(string.format("unpacked a box onto shelf %d (+%d on shelf)", shelf.Index, Shelves.count(shelf) - placedBefore))
		else
			bot.enterStore()
			runtime:run(0.3)
			local info = bot.session().Carried
			local ok = info and runtime:trigger(player, info.Root.OpenBoxPrompt)
			runtime:run(0.3)
			bot.say("opened a box into the stock room" .. (if ok then "" else " (failed)"))
		end
		return bot.data().Stats.BoxesOpened > before
	end

	function bot.stockShelves(): number
		local total = 0
		for _, shelf in bot.store().Shelves do
			if bot.stock() == 0 then
				break
			end
			if Shelves.free(shelf) > 0 then
				bot.goToShelf(shelf)
				local before = Shelves.count(shelf)
				runtime:trigger(player, shelf.Model.Base.PromptAttachment.StockPrompt)
				runtime:runUntil(8, function()
					return not shelf.Busy
				end)
				total += Shelves.count(shelf) - before
			end
		end
		if total > 0 then
			bot.say("stocked " .. total .. " items from the stock room")
		end
		return total
	end

	function bot.anyShelfSpace(): boolean
		return bot.emptiestShelf() ~= nil
	end

	function bot.window(title: string)
		return bot.gui():FindFirstChild(title)
	end

	function bot.closeWindows()
		for _, child in bot.gui():GetChildren() do
			if child:IsA("Frame") and child.Visible and child:FindFirstChild("Header") and child:FindFirstChild("Close") then
				runtime:click(child.Close)
			end
		end
	end

	-- Click through the real UI to buy an upgrade.
	function bot.buyUpgrade(id: string): boolean
		local window = bot.window("UPGRADES")
		if not window.Visible then
			runtime:click(bot.gui().Upgrades)
			runtime:run(0.2)
		end
		local row = window.Content:FindFirstChildOfClass("ScrollingFrame"):FindFirstChild(id)
		local before = bot.data().Upgrades[id]
		runtime:click(row.Buy)
		runtime:run(0.5)
		local after = bot.data().Upgrades[id]
		if after > before then
			bot.say(string.format("bought %s -> level %d", id, after))
			return true
		end
		return false
	end

	-- Click a card's buy button in the Robux shop.
	function bot.shopBuy(tab: string, key: string)
		local window = bot.window("SHOP")
		if not window.Visible then
			runtime:click(bot.gui().Shop)
			runtime:run(0.2)
		end
		runtime:click(window.Content.Tabs[tab])
		runtime:run(0.1)
		local card = window.Content.Body[tab]:FindFirstChild(key)
		runtime:click(card.Buy)
		runtime:run(1)
		return window.Subtitle.Text
	end

	function bot.affordableUpgrade(): string?
		local best, bestCost = nil, math.huge
		for _, id in { "CustomerRate", "ShelfCapacity", "DeliverySize", "ProductLuck", "StoreSize" } do
			local cost = Upgrades.getCost(id, bot.data().Upgrades[id])
			if cost and cost <= bot.data().Cash and cost < bestCost then
				best, bestCost = id, cost
			end
		end
		return best
	end

	-- One decision of the player's loop.
	function bot.tick(allowUpgrades: boolean)
		local upgrade = if allowUpgrades and not bot.carrying() then bot.affordableUpgrade() else nil
		if upgrade then
			bot.buyUpgrade(upgrade)
			bot.closeWindows()
		elseif bot.carrying() then
			bot.unpackAtShelf()
		elseif bot.stock() > 0 and bot.anyShelfSpace() then
			bot.stockShelves()
		elseif #bot.boxesOnPad() > 0 and bot.stock() < 60 then
			bot.pickUpBox()
		else
			runtime:run(1)
		end
	end

	return bot
end

local function reportErrors(label: string)
	check(#Scheduler.errors == 0, label .. ": no script errors (" .. #Scheduler.errors .. ")")
	for index, err in Scheduler.errors do
		if index <= 5 then
			print(err)
		end
	end
	table.clear(Scheduler.errors)
end

-- Run 1: a brand-new player ----------------------------------------------------------------

local dataStores, orderedStores, ownedPasses = {}, {}, {}
local runtime = Runtime.new({
	placePath = PLACE,
	placeId = 4242,
	dataStoreMode = "ok",
	dataStores = dataStores,
	orderedStores = orderedStores,
	ownedPasses = ownedPasses,
})
runtime:startServer()
runtime:run(0.5)
local isaac = runtime:addPlayer("Isaac", 1001, true)
runtime:run(1)
local bot = makeBot(runtime, isaac)
local gui = bot.gui()

section("Tutorial: a brand-new player's first minute")
local store = bot.store()
check(store ~= nil and #store.Shelves == 2, "player got a starter shop with 2 shelves")
check(store.Model.Sign:FindFirstChildOfClass("SurfaceGui").OwnerName.Text == "ISAAC'S STORE", "sign reads ISAAC'S STORE")
check(gui.Cash.Amount.Text == "£25", "HUD shows starting cash £25")
check(gui.Tutorial.Visible and string.find(gui.Tutorial:FindFirstChild("TextLabel", true).Text or "", "STEP") ~= nil, "tutorial card is showing")
local function tutorialStep()
	local t = bot.data().Tutorial
	return if t.Done then 99 else t.Step
end
check(tutorialStep() == 1, "tutorial starts at step 1 (grab a box)")

local times = {}
local startTime = Scheduler.now
local startCash = bot.data().Cash
while Scheduler.now - startTime < 90 and tutorialStep() < 4 do
	bot.tick(false)
	local step = tutorialStep()
	for s = 2, step do
		times[s] = times[s] or (Scheduler.now - startTime)
	end
end
print(string.format("  step 1 (grab) done at %.1fs, step 2 (unpack at shelf) at %.1fs, step 3 (first sale) at %.1fs", times[2] or -1, times[3] or -1, times[4] or -1))
check(times[2] ~= nil and times[2] < 20, "picked up the first box within 20s")
check(times[3] ~= nil and times[3] < 35, "unpacked a box straight onto a shelf within 35s")
check(times[4] ~= nil and times[4] < 60, "first customer purchase within the first minute")
check(bot.lastPromptText == "Unpack Here", "shelf prompt says 'Unpack Here' while carrying (" .. tostring(bot.lastPromptText) .. ")")
check(bot.data().Cash >= startCash + 25 + 50 + 75, "tutorial step rewards paid (cash £" .. bot.data().Cash .. ")")
runtime:run(0.3)
check(gui.TutorialPointer.Visible, "step 4 points at the UPGRADE button")
local upgrade = bot.affordableUpgrade()
check(upgrade ~= nil, "can afford an upgrade for the last tutorial step")
local cashBefore = bot.data().Cash
bot.buyUpgrade(upgrade or "ShelfCapacity")
bot.closeWindows()
runtime:run(2.5)
check(bot.data().Tutorial.Done, "tutorial completed after buying an upgrade")
check(gui:FindFirstChild("TutorialDone") ~= nil or bot.data().Cash > cashBefore, "finale celebration + bonus")
runtime:run(5)
check(not gui.Tutorial.Visible, "tutorial card goes away when done")
reportErrors("tutorial")

section("Five minutes of the loop with upgrades bought through the UI")
startTime = Scheduler.now
local maxCustomers = 0
while Scheduler.now - startTime < 300 do
	bot.tick(true)
	maxCustomers = math.max(maxCustomers, bot.store().CustomerCount)
end
local data = bot.data()
print(string.format("  cash £%d, earned £%d, items sold %d, boxes opened %d, rares %d, deliveries %d", data.Cash, data.TotalEarned, data.Stats.ItemsSold, data.Stats.BoxesOpened, data.Stats.RaresFound, data.Stats.Deliveries))
check(data.Stats.ItemsSold >= 60, "customers keep buying (" .. data.Stats.ItemsSold .. " items sold)")
local bought = 0
for id, level in data.Upgrades do
	bought += level - runtime:serverModule(runtime.game.ReplicatedStorage.Shared.Upgrades).Defs[id].StartLevel
end
check(bought >= 4, "bought several upgrades via the UI (" .. bought .. ")")
check(maxCustomers >= 3, "several customers in the shop at once (max " .. maxCustomers .. ")")
check(#Instances.findFallingParts(runtime.workspace) == 0, "no unanchored parts left floating unattached")
check(gui.Value:FindFirstChildOfClass("TextLabel").Text ~= "⭐ £0", "store value shows in the HUD")
reportErrors("five minutes")

section("Leaderboards")
runtime:run(65)
local leaderboardsModule = runtime:serverModule(runtime.game.ServerScriptService.Server.Services.Leaderboards)
local snapshot = leaderboardsModule.snapshot()
check(snapshot.Global == true, "global leaderboards use OrderedDataStores")
local topValue = snapshot.Boards[1].Entries[1]
check(topValue ~= nil and topValue.UserId == 1001, "Isaac tops the store value board")
local sign = runtime.workspace.World:FindFirstChild("Leaderboard")
local firstRow = sign and sign.Board.BoardFront:FindFirstChild("Row1", true)
check(firstRow ~= nil and firstRow:FindFirstChild("TextLabel") ~= nil, "leaderboard sign built in the street")
local rowText = {}
for _, child in firstRow:GetChildren() do
	if child:IsA("TextLabel") then
		table.insert(rowText, child.Text)
	end
end
check(table.find(rowText, "Isaac") ~= nil, "sign shows Isaac (" .. table.concat(rowText, " | ") .. ")")
check(isaac.leaderstats.Value.Value > 0 and isaac.leaderstats.Sold.Value > 0, "player list stats (Value/Cash/Sold) update")
runtime:click(gui.Leaders)
runtime:run(1)
local leaderWindow = bot.window("LEADERBOARD")
local listRows = leaderWindow.Content.Body:FindFirstChildOfClass("ScrollingFrame")
check(leaderWindow.Visible and listRows:FindFirstChild("Row1") ~= nil, "🏆 menu lists the top players")
bot.closeWindows()
reportErrors("leaderboards")

section("Robux shop (Studio test purchases)")
local services = runtime.game.ServerScriptService.Server.Services
local PlayerData = runtime:serverModule(services.PlayerData)
local Perks = runtime:serverModule(services.Perks)
local Shelves = runtime:serverModule(services.Shelves)
cashBefore = bot.data().Cash
bot.shopBuy("Cash", "CashSmall")
check(bot.data().Cash >= cashBefore + 1500, string.format("Pocket Money pack adds cash (£%d → £%d)", cashBefore, bot.data().Cash))
bot.shopBuy("Boosts", "CustomerRush")
check(Perks.boostActive(isaac, "CustomerRush"), "Customer Rush boost is active")
runtime:run(0.5)
check(gui.Boosts:FindFirstChild("CustomerRush") ~= nil, "boost timer chip shows in the HUD")
local boxesBefore = #bot.boxesOnPad()
bot.shopBuy("Boosts", "InstantDelivery")
runtime:run(8)
check(bot.data().Stats.Deliveries >= 1 and (#bot.boxesOnPad() > boxesBefore or bot.stock() > 0), "Instant Delivery brings a van")
-- Make room on the loading bay so the crate can land there.
local BoxesService = runtime:serverModule(services.Boxes)
for _ = 1, 8 do
	if #BoxesService.freeSpots(bot.session()) > 0 then
		break
	end
	if bot.pickUpBox() then
		bot.unpackAtShelf()
	end
end
check(#BoxesService.freeSpots(bot.session()) > 0, "made room on the loading bay")
bot.shopBuy("Boosts", "GoldenCrate")
runtime:run(3)
local goldenOnPad = false
for _, box in bot.boxesOnPad() do
	if box:FindFirstChild("Sparkles") then
		goldenOnPad = true
	end
end
check(goldenOnPad, "Golden Crate lands on the loading bay")
bot.shopBuy("Passes", "DoubleCash")
check(Perks.has(isaac, "DoubleCash"), "2x Cash pass granted")
local saleSeen = false
local earnedBefore = bot.data().TotalEarned
for _ = 1, 60 do
	bot.tick(false)
	for _, entry in runtime.remoteLog do
		saleSeen = true
	end
	if bot.data().TotalEarned > earnedBefore then
		break
	end
end
check(bot.data().TotalEarned > earnedBefore, "sales continue with 2x Cash")
bot.closeWindows()
reportErrors("shop test purchases")

section("Robux shop (real product + pass IDs)")
-- Pretend the developer filled in real IDs (server and client have their own module copies).
for _, context in { "server", "client" } do
	local Monetization = runtime:require(context, runtime.game.ReplicatedStorage.Shared.Monetization)
	Monetization.Products.CashMedium.Id = 1111
	Monetization.Passes.VIP.Id = 2222
end
cashBefore = bot.data().Cash
bot.shopBuy("Cash", "CashMedium")
runtime:run(1)
check(bot.data().Cash >= cashBefore + 10000, "ProcessReceipt grants the Cash Stack")
local receipt = runtime.receiptLog[#runtime.receiptLog]
check(receipt ~= nil and receipt.Decision == Enum.ProductPurchaseDecision.PurchaseGranted, "receipt answered PurchaseGranted")
cashBefore = bot.data().Cash
local MarketplaceService = runtime.game:GetService("MarketplaceService")
local again = MarketplaceService.ProcessReceipt(table.clone(receipt.Receipt))
check(again == Enum.ProductPurchaseDecision.PurchaseGranted and bot.data().Cash == cashBefore, "the same receipt is never granted twice")
check(table.find(bot.data().Receipts, receipt.Receipt.PurchaseId) ~= nil, "receipt id stored in the save")
local workersBefore = #bot.store().Workers
bot.shopBuy("Passes", "VIP")
runtime:run(1)
check(Perks.has(isaac, "VIP"), "VIP pass granted through PromptGamePassPurchaseFinished")
check(#bot.store().Workers == workersBefore + 1, "VIP adds a free worker")
check(isaac.Character.Head:FindFirstChild("VipTag") ~= nil, "VIP tag over the player's head")
bot.closeWindows()
reportErrors("shop real purchases")

section("Store expansion, workers and capacity")
PlayerData.addCash(isaac, 300000)
runtime:run(0.5)
local itemsBefore = 0
for _, keys in Shelves.serialize(bot.store()) do
	itemsBefore += #keys
end
while bot.data().Upgrades.StoreSize < 3 do
	check(bot.buyUpgrade("StoreSize"), "bought Store Size level " .. (bot.data().Upgrades.StoreSize + 1))
	runtime:run(1)
end
check(#bot.store().Shelves == 10 and bot.store().Level == 3, "mini supermarket has 10 shelves")
local itemsAfter = 0
for _, keys in Shelves.serialize(bot.store()) do
	itemsAfter += #keys
end
check(itemsAfter >= itemsBefore - 12, string.format("shelf stock kept through rebuilds (%d -> %d)", itemsBefore, itemsAfter))
check(bot.buyUpgrade("Workers"), "hired a worker")
bot.closeWindows()
for _ = 1, 3 do
	PlayerData.addItem(isaac, "Cola", 30)
end
local stockBeforeWorker = bot.stock()
runtime:run(40)
check(bot.stock() < stockBeforeWorker, string.format("workers move stock onto shelves (%d -> %d)", stockBeforeWorker, bot.stock()))
reportErrors("expansion")

section("Second player: separate plot, can't touch Isaac's stuff")
local bob = runtime:addPlayer("Bob", 2002, false)
runtime:run(12)
local bobBot = makeBot(runtime, bob)
check(bobBot.session() ~= nil and bobBot.session().PlotIndex ~= bot.session().PlotIndex, "Bob gets his own plot")
check(#bobBot.boxesOnPad() > 0, "Bob gets his own delivery")
local bobBox = bobBot.boxesOnPad()[1]
check(bobBox.BoxPrompt.Enabled == false, "Isaac's client hides Bob's box prompts")
Instances.fire(bobBox.BoxPrompt, "Triggered", isaac)
runtime:run(0.5)
check(not bot.carrying() and bobBox:FindFirstChild("BoxPrompt") ~= nil, "server rejects Isaac picking up Bob's box")
local bobShelf = bobBot.store().Shelves[1]
Instances.fire(bobShelf.Model.Base.PromptAttachment.StockPrompt, "Triggered", isaac)
runtime:run(1)
check(Shelves.count(bobShelf) == 0, "server rejects Isaac stocking Bob's shelf")
reportErrors("multiplayer")

section("Saving and loading")
local savedCash = bot.data().Cash
local savedUpgrades = table.clone(bot.data().Upgrades)
local savedShelfItems = 0
for _, keys in Shelves.serialize(bot.store()) do
	savedShelfItems += #keys
end
local savedStock = bot.stock()
runtime:removePlayer(isaac)
runtime:run(2)
check(dataStores["FillTheStore_PlayerData_v1"]["Player_1001"] ~= nil, "data saved to the DataStore on leave")
check(runtime:shutdown(), "BindToClose finished saving")
reportErrors("save")

local runtime2 = Runtime.new({
	placePath = PLACE,
	placeId = 4242,
	dataStoreMode = "ok",
	dataStores = dataStores,
	orderedStores = orderedStores,
	ownedPasses = ownedPasses,
})
runtime2:startServer()
runtime2:run(0.5)
for _, context in { "server", "client" } do
	local Monetization = runtime2:require(context, runtime2.game.ReplicatedStorage.Shared.Monetization)
	Monetization.Passes.VIP.Id = 2222
end
local isaac2 = runtime2:addPlayer("Isaac", 1001, true)
runtime2:run(2)
local bot2 = makeBot(runtime2, isaac2)
local Shelves2 = runtime2:serverModule(runtime2.game.ServerScriptService.Server.Services.Shelves)
local Perks2 = runtime2:serverModule(runtime2.game.ServerScriptService.Server.Services.Perks)
local loadedItems = 0
for _, keys in Shelves2.serialize(bot2.store()) do
	loadedItems += #keys
end
check(bot2.data().Cash == savedCash, string.format("cash restored (£%d)", bot2.data().Cash))
local upgradesMatch = true
for id, level in savedUpgrades do
	upgradesMatch = upgradesMatch and bot2.data().Upgrades[id] == level
end
check(upgradesMatch, "upgrades restored")
check(bot2.data().Tutorial.Done, "tutorial stays finished")
check(bot2.store().Level == 3 and #bot2.store().Shelves == 10, "store level restored")
check(loadedItems + bot2.stock() >= savedShelfItems + savedStock - 5, "shelf stock + inventory restored")
check(Perks2.has(isaac2, "VIP"), "owned game pass detected on rejoin (UserOwnsGamePassAsync)")
check(Perks2.boostActive(isaac2, "CustomerRush"), "Customer Rush boost keeps running across sessions")
check(not bot2.gui().Tutorial.Visible, "no tutorial for returning players")
runtime2:run(20)
reportErrors("load")
runtime2:shutdown()

section("Studio without API access")
local runtime3 = Runtime.new({ placePath = PLACE, placeId = 4242, dataStoreMode = "denied" })
runtime3:startServer()
runtime3:run(0.5)
local tester = runtime3:addPlayer("Tester", 3003, true)
runtime3:run(15)
local bot3 = makeBot(runtime3, tester)
check(bot3.store() ~= nil, "game still starts when DataStores are blocked")
local warnedOnce = 0
for _, message in runtime3.warnings do
	if string.find(message, "NOT be saved", 1, true) then
		warnedOnce += 1
	end
end
check(warnedOnce == 1, "prints a single clear 'not saved' warning (" .. warnedOnce .. ")")
local lb = runtime3:serverModule(runtime3.game.ServerScriptService.Server.Services.Leaderboards).snapshot()
check(lb.Global == false and #lb.Boards[1].Entries == 1, "leaderboards fall back to this server")
check(bot3.data().Tutorial.Step == 1 and bot3.gui().Tutorial.Visible, "new player sees the tutorial")
runtime3:removePlayer(tester)
runtime3:run(1)
check(runtime3:shutdown(), "shutdown doesn't hang")
reportErrors("studio")

section("Bot log (first 20 actions)")
for index, line in bot.log do
	if index <= 20 then
		print("  " .. line)
	end
end

print(string.format("\n%d check(s) failed", #failures))
process.exit(if #failures == 0 then 0 else 1)
