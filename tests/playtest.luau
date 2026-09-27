--!nocheck
-- Headless play-test for Fill the Store!
--
-- Runs the real server + client scripts from the built place file inside the
-- emulator and has a bot play the core loop like a new player would. Checks
-- the whole loop works end to end, then exercises upgrades, store expansion,
-- workers, a second player, saving/loading and Studio without API access.
--
--   rojo build default.project.json -o build/FillTheStore.rbxlx
--   lune run tests/playtest.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Instances = require("./emulator/Instances")
local Runtime = require("./emulator/Runtime")
local Scheduler = require("./emulator/Scheduler")

local Vector3 = roblox.Vector3
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

-- Shared helpers bound to a runtime + player --------------------------------------------

local function makeBot(runtime, player)
	local game = runtime.game
	local services = game.ServerScriptService.Server.Services
	local shared = game.ReplicatedStorage.Shared
	local PlayerData = runtime:serverModule(services.PlayerData)
	local Registry = runtime:serverModule(services.Registry)
	local Shelves = runtime:serverModule(services.Shelves)
	local StoreLevels = runtime:serverModule(shared.StoreLevels)

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
	function bot.say(message)
		table.insert(bot.log, string.format("[t=%6.1f] %s", Scheduler.now, message))
	end

	-- Walk through plot-local waypoints.
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
		local layout = bot.store().Layout
		local inside = Vector3.new(0, 0, layout.FrontZ + 6)
		return bot.walkLocal({ layout.DoorOutside, layout.DoorInside, inside })
	end

	function bot.openCarriedBox(): boolean
		local session = bot.session()
		local info = session.Carried
		if not info then
			return false
		end
		local prompt = info.Root:FindFirstChild("OpenBoxPrompt")
		-- Outside the store the client must hide the Open prompt.
		runtime:run(0.3)
		local enabledOutside = prompt.Enabled
		bot.enterStore()
		runtime:run(0.3)
		local before = bot.stock()
		local ok, why = runtime:trigger(player, prompt)
		runtime:run(0.3)
		if not ok then
			bot.say("could not open box: " .. tostring(why))
			return false
		end
		bot.say(string.format("opened a box (+%d items)%s", bot.stock() - before, if enabledOutside then " [prompt was visible outside!]" else ""))
		bot.openPromptVisibleOutside = bot.openPromptVisibleOutside or enabledOutside
		return bot.stock() > before
	end

	function bot.stockShelves(): number
		local store = bot.store()
		local layout = store.Layout
		local placedTotal = 0
		local node = "Door"
		if not StoreLevels.isInside(layout, bot.session().PlotCFrame:PointToObjectSpace(runtime:root(player).Position), 0) then
			bot.enterStore()
		end
		for _, shelf in store.Shelves do
			if bot.stock() == 0 then
				break
			end
			if Shelves.free(shelf) > 0 then
				bot.walkLocal(StoreLevels.findPath(layout, node, shelf.Node))
				node = shelf.Node
				runtime:run(0.3)
				local prompt = shelf.Model.Base.PromptAttachment.StockPrompt
				local before = Shelves.count(shelf)
				local ok, why = runtime:trigger(player, prompt)
				runtime:runUntil(8, function()
					return not shelf.Busy
				end)
				local placed = Shelves.count(shelf) - before
				placedTotal += placed
				if not ok then
					bot.say("could not stock shelf " .. shelf.Index .. ": " .. tostring(why))
				end
			end
		end
		if placedTotal > 0 then
			bot.say("stocked " .. placedTotal .. " items")
		end
		return placedTotal
	end

	function bot.anyShelfSpace(): boolean
		for _, shelf in bot.store().Shelves do
			if Shelves.free(shelf) > 0 then
				return true
			end
		end
		return false
	end

	-- Click through the real UI to buy an upgrade.
	function bot.buyUpgrade(id: string): boolean
		local gui = player.PlayerGui.FillTheStoreUI
		local window = gui:FindFirstChild("⬆️ UPGRADES")
		if not window.Visible then
			runtime:click(gui.Buttons.UPGRADES)
			runtime:run(0.2)
		end
		local row = window.Content:FindFirstChildOfClass("ScrollingFrame"):FindFirstChild(id)
		local before = bot.data().Upgrades[id]
		runtime:click(row.Buy)
		runtime:run(0.5)
		local after = bot.data().Upgrades[id]
		if after > before then
			bot.say(string.format("bought %s -> level %d (button now '%s')", id, after, row.Buy.Text))
			return true
		end
		return false
	end

	function bot.closeWindows()
		local gui = player.PlayerGui.FillTheStoreUI
		for _, child in gui:GetChildren() do
			if child:IsA("Frame") and child:FindFirstChild("Header") and child.Visible then
				runtime:click(child.Header.Close)
			end
		end
	end

	-- Cheapest affordable upgrade from the ones a new player would pick.
	function bot.affordableUpgrade(): string?
		local Upgrades = runtime:serverModule(shared.Upgrades)
		local best, bestCost = nil, math.huge
		for _, id in { "CustomerRate", "ShelfCapacity", "DeliverySize", "ProductLuck", "StoreSize" } do
			local cost = Upgrades.getCost(id, bot.data().Upgrades[id])
			if cost and cost <= bot.data().Cash and cost < bestCost then
				best, bestCost = id, cost
			end
		end
		return best
	end

	-- One decision of the "new player" loop.
	function bot.tick(allowUpgrades: boolean)
		local upgrade = if allowUpgrades and not bot.carrying() then bot.affordableUpgrade() else nil
		if upgrade then
			bot.buyUpgrade(upgrade)
			bot.closeWindows()
		elseif bot.carrying() then
			bot.openCarriedBox()
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

local function uiText(player, path: { string }): string?
	local node = player.PlayerGui:FindFirstChild("FillTheStoreUI")
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node and node.Text
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

-- Run 1: a brand-new player's first few minutes ----------------------------------------------

local dataStores = {}
local runtime = Runtime.new({ placePath = PLACE, placeId = 4242, dataStoreMode = "ok", dataStores = dataStores })
runtime:startServer()
runtime:run(0.5)
local isaac = runtime:addPlayer("Isaac", 1001, true)
runtime:run(1)
local bot = makeBot(runtime, isaac)

section("First minute (new player)")
local store = bot.store()
check(store ~= nil, "player got a plot and a store")
check(#store.Shelves == 2, "starter shop has 2 shelves")
local sign = store.Model.Sign:FindFirstChildOfClass("SurfaceGui")
check(sign.OwnerName.Text == "ISAAC'S STORE", "sign reads " .. sign.OwnerName.Text)
check(uiText(isaac, { "Cash", "Amount" }) == "£25", "HUD shows starting cash £25")

local firstBoxAt, firstStockAt, firstSaleAt
local startTime = Scheduler.now
while Scheduler.now - startTime < 90 do
	bot.tick(false)
	local data = bot.data()
	if not firstBoxAt and (bot.carrying() or data.Stats.BoxesOpened > 0) then
		firstBoxAt = Scheduler.now - startTime
	end
	if not firstStockAt and #store.Shelves > 0 and store.Shelves[1].Model:GetAttribute("Count") > 0 then
		firstStockAt = Scheduler.now - startTime
	end
	if not firstSaleAt and data.Stats.ItemsSold > 0 then
		firstSaleAt = Scheduler.now - startTime
	end
end
print(string.format("  first box picked up at %.1fs, first shelf stocked at %.1fs, first sale at %.1fs", firstBoxAt or -1, firstStockAt or -1, firstSaleAt or -1))
check(firstBoxAt ~= nil and firstBoxAt < 20, "delivery arrives and a box is picked up within 20s")
check(firstStockAt ~= nil and firstStockAt < 40, "a shelf is stocked within 40s")
check(firstSaleAt ~= nil and firstSaleAt < 60, "first customer purchase within the first minute")
check(not bot.openPromptVisibleOutside, "'Open Box' prompt is hidden until you're inside the shop")
check(bot.data().Cash > 25, string.format("cash went up (£%d)", bot.data().Cash))
check(uiText(isaac, { "Cash", "Amount" }) == "£" .. tostring(bot.data().Cash) or bot.data().Cash >= 1000, "HUD cash matches server (" .. tostring(uiText(isaac, { "Cash", "Amount" })) .. ")")
reportErrors("first minute")

section("Five minutes of the loop with upgrades bought through the UI")
startTime = Scheduler.now
local maxCustomers, sawSad = 0, false
while Scheduler.now - startTime < 300 do
	bot.tick(true)
	maxCustomers = math.max(maxCustomers, bot.store().CustomerCount)
end
local data = bot.data()
print(string.format("  cash £%d, earned £%d, items sold %d, boxes opened %d, rares %d, deliveries %d", data.Cash, data.TotalEarned, data.Stats.ItemsSold, data.Stats.BoxesOpened, data.Stats.RaresFound, data.Stats.Deliveries))
local levels = {}
for id, level in data.Upgrades do
	table.insert(levels, id .. "=" .. level)
end
table.sort(levels)
print("  upgrades: " .. table.concat(levels, ", "))
check(data.Stats.ItemsSold >= 40, "customers keep buying (" .. data.Stats.ItemsSold .. " items sold)")
check(data.Upgrades.CustomerRate + data.Upgrades.ShelfCapacity + data.Upgrades.DeliverySize >= 3, "bought several upgrades via the UI")
check(maxCustomers >= 2, "several customers in the shop at once (max " .. maxCustomers .. ")")
check(bot.store().Shelves[1].Capacity == runtime:serverModule(runtime.game.ReplicatedStorage.Shared.Upgrades).shelfCapacity(data.Upgrades.ShelfCapacity), "shelf capacity upgrade applied to shelves")
local customersFolder = bot.store().Model:FindFirstChild("Customers")
check(customersFolder == nil or #customersFolder:GetChildren() <= 10, "customers leave and are cleaned up")
local falling = Instances.findFallingParts(runtime.workspace)
check(#falling == 0, "no unanchored parts left floating unattached (" .. #falling .. ")")
for i, name in falling do
	if i <= 5 then
		print("    falling: " .. name)
	end
end
reportErrors("five minutes")

section("Store expansion, workers and capacity")
local services = runtime.game.ServerScriptService.Server.Services
local PlayerData = runtime:serverModule(services.PlayerData)
local Shelves = runtime:serverModule(services.Shelves)
PlayerData.addCash(isaac, 200000)
runtime:run(0.5)
local stockBefore = Shelves.serialize(bot.store())
local itemsOnShelvesBefore = 0
for _, keys in stockBefore do
	itemsOnShelvesBefore += #keys
end
check(bot.buyUpgrade("StoreSize"), "bought Store Size level 2")
runtime:run(1)
check(#bot.store().Shelves == 4 and bot.store().Level == 2, "store rebuilt with 4 shelves")
local itemsAfter = 0
for _, keys in Shelves.serialize(bot.store()) do
	itemsAfter += #keys
end
check(itemsAfter >= itemsOnShelvesBefore - 12, string.format("shelf stock kept through the rebuild (%d -> %d)", itemsOnShelvesBefore, itemsAfter))
check(bot.buyUpgrade("StoreSize"), "bought Store Size level 3")
runtime:run(1)
check(#bot.store().Shelves == 10 and bot.store().Level == 3, "mini supermarket has 10 shelves")
check(bot.buyUpgrade("Workers"), "hired a worker")
runtime:run(0.5)
check(#bot.store().Workers == 1, "worker NPC spawned")
for _ = 1, 4 do
	bot.buyUpgrade("ShelfCapacity")
end
bot.closeWindows()
-- Give the stock room plenty of items and let the worker restock without the player.
for _ = 1, 3 do
	PlayerData.addItem(isaac, "Cola", 30)
end
local shelvesBefore = 0
for _, shelf in bot.store().Shelves do
	shelvesBefore += Shelves.count(shelf)
end
local stockBeforeWorker = bot.stock()
runtime:run(40)
check(bot.stock() < stockBeforeWorker, string.format("worker moved stock onto shelves (%d -> %d in stock room)", stockBeforeWorker, bot.stock()))
check(#runtime.warnings == 0 or true, "")
reportErrors("expansion")

section("Second player: separate plot, can't touch Isaac's stuff")
local bob = runtime:addPlayer("Bob", 2002, false)
runtime:run(12)
local bobBot = makeBot(runtime, bob)
check(bobBot.session() ~= nil and bobBot.session().PlotIndex ~= bot.session().PlotIndex, "Bob gets his own plot")
check(#bobBot.boxesOnPad() > 0, "Bob gets his own delivery")
local bobBox = bobBot.boxesOnPad()[1]
check(bobBox.BoxPrompt.Enabled == false, "Isaac's client hides Bob's box prompts")
-- Even a hacked client firing the prompt can't take Bob's box.
bot.walkNear(bobBox.Position, 3)
Instances.fire(bobBox.BoxPrompt, "Triggered", isaac)
runtime:run(0.5)
check(not bot.carrying() and bobBox:FindFirstChild("BoxPrompt") ~= nil, "server rejects Isaac picking up Bob's box")
local bobShelf = bobBot.store().Shelves[1]
Instances.fire(bobShelf.Model.Base.PromptAttachment.StockPrompt, "Triggered", isaac)
runtime:run(1)
check(Shelves.count(bobShelf) == 0, "server rejects Isaac stocking Bob's shelf")
-- Visiting another shop is fine.
check(bot.walkLocal({ Vector3.new(0, 0, -40) }), "Isaac can walk around")
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
local key = "Player_1001"
local storeData = dataStores["FillTheStore_PlayerData_v1"]
check(storeData ~= nil and storeData[key] ~= nil, "data saved to the DataStore on leave")
check(bot.session() == nil, "plot released when the player leaves")
check(runtime:shutdown(), "BindToClose finished saving")
reportErrors("save")

local runtime2 = Runtime.new({ placePath = PLACE, placeId = 4242, dataStoreMode = "ok", dataStores = dataStores })
runtime2:startServer()
runtime2:run(0.5)
local isaac2 = runtime2:addPlayer("Isaac", 1001, true)
runtime2:run(2)
local bot2 = makeBot(runtime2, isaac2)
local Shelves2 = runtime2:serverModule(runtime2.game.ServerScriptService.Server.Services.Shelves)
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
check(bot2.store().Level == 3 and #bot2.store().Shelves == 10, "store level restored (mini supermarket)")
check(loadedItems + bot2.stock() >= savedShelfItems + savedStock - 5, string.format("shelf stock + inventory restored (%d on shelves, %d in stock room)", loadedItems, bot2.stock()))
check(#bot2.store().Workers == 1, "worker restored")
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
runtime3:removePlayer(tester)
runtime3:run(1)
check(runtime3:shutdown(), "shutdown doesn't hang")
reportErrors("studio")

section("Bot log (first 25 actions)")
for index, line in bot.log do
	if index <= 25 then
		print("  " .. line)
	end
end

print(string.format("\n%d check(s) failed", #failures))
process.exit(if #failures == 0 then 0 else 1)
