--!strict
-- Player data: loading, saving (DataStoreService), cash and inventory.
-- All money and inventory changes happen here on the server; the client only
-- ever receives read-only snapshots.
--
-- Studio-safe: if DataStores aren't available (unpublished place or "Enable
-- Studio Access to API Services" turned off) the game still runs, it just
-- doesn't save, and prints a single warning.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Upgrades = require(Shared.Upgrades)

export type Stats = {
	ItemsSold: number,
	BoxesOpened: number,
	RaresFound: number,
	Deliveries: number,
}

export type TutorialState = {
	Step: number,
	Done: boolean,
}

export type Data = {
	Version: number,
	Cash: number,
	TotalEarned: number,
	Upgrades: { [string]: number },
	Inventory: { [string]: number },
	Shelves: { { string } },
	SelectedProduct: string?,
	Stats: Stats,
	Tutorial: TutorialState,
	Boosts: { [string]: number }, -- boost key -> os.time() it ends
	Receipts: { string }, -- recent Robux purchase ids (so a purchase is never granted twice)
}

type Profile = {
	Data: Data,
	CanSave: boolean,
	Dirty: boolean,
	Saving: boolean,
}

local DATA_VERSION = 1

local PlayerData = {}

-- Fired whenever the snapshot sent to the client should refresh.
PlayerData.Changed = Signal.new() :: Signal.Signal<Player>

-- Hooks set by other services (avoids circular requires).
PlayerData.BeforeSave = nil :: ((player: Player, data: Data) -> ())?
PlayerData.ExtraValue = nil :: ((player: Player) -> number)?
PlayerData.SnapshotExtras = {} :: { (player: Player, snapshot: { [string]: any }) -> () }

local profiles: { [Player]: Profile } = {}
local dirty: { [Player]: boolean } = {}
local dataStore: DataStore? = nil
local dataStoreWarned = false
local activeSaves = 0

local function warnDataStore(message: string)
	if not dataStoreWarned then
		dataStoreWarned = true
		warn(`[FillTheStore] {message} Progress will NOT be saved this session.`)
	end
end

local function disableDataStore(reason: string)
	dataStore = nil
	warnDataStore(reason)
end

local function isAccessError(message: string): boolean
	local lower = string.lower(message)
	return string.find(lower, "studio", 1, true) ~= nil
		or string.find(lower, "publish", 1, true) ~= nil
		or string.find(lower, "403", 1, true) ~= nil
		or string.find(lower, "api services", 1, true) ~= nil
		or string.find(lower, "not allowed", 1, true) ~= nil
end

local function defaultData(): Data
	return {
		Version = DATA_VERSION,
		Cash = Config.StartingCash,
		TotalEarned = 0,
		Upgrades = Upgrades.defaultLevels(),
		Inventory = {},
		Shelves = {},
		SelectedProduct = nil,
		Stats = { ItemsSold = 0, BoxesOpened = 0, RaresFound = 0, Deliveries = 0 },
		Tutorial = { Step = 1, Done = false },
		Boosts = {},
		Receipts = {},
	}
end

local function cleanNumber(value: unknown, default: number, minimum: number, maximum: number): number
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.clamp(math.floor(value), minimum, maximum)
end

-- Turn whatever came out of the DataStore into a valid Data table.
local function reconcile(raw: unknown): Data
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end
	local source = raw :: { [string]: any }

	data.Cash = cleanNumber(source.Cash, data.Cash, 0, 1e15)
	data.TotalEarned = cleanNumber(source.TotalEarned, 0, 0, 1e15)

	if type(source.Upgrades) == "table" then
		for id, def in Upgrades.Defs do
			data.Upgrades[id] = cleanNumber(source.Upgrades[id], def.StartLevel, def.StartLevel, def.MaxLevel)
		end
	end

	if type(source.Inventory) == "table" then
		for key, count in source.Inventory do
			if Items.isValid(key) and type(count) == "number" and count > 0 then
				data.Inventory[key] = math.floor(count)
			end
		end
	end

	if type(source.Shelves) == "table" then
		for index, shelf in source.Shelves do
			if type(index) == "number" and type(shelf) == "table" then
				local keys = {}
				for _, key in shelf do
					if Items.isValid(key) then
						table.insert(keys, key)
					end
				end
				data.Shelves[index] = keys
			end
		end
	end

	if type(source.SelectedProduct) == "string" and Items.isValid(source.SelectedProduct) then
		data.SelectedProduct = source.SelectedProduct
	end

	if type(source.Stats) == "table" then
		for stat, _ in data.Stats do
			(data.Stats :: any)[stat] = cleanNumber(source.Stats[stat], 0, 0, 1e15)
		end
	end

	if type(source.Tutorial) == "table" then
		data.Tutorial.Step = cleanNumber(source.Tutorial.Step, 1, 1, 99)
		data.Tutorial.Done = source.Tutorial.Done == true
	elseif data.Stats.ItemsSold > 0 then
		-- Saves from before the tutorial existed: they already know how to play.
		data.Tutorial.Done = true
	end

	if type(source.Boosts) == "table" then
		for key, expiry in source.Boosts do
			if type(key) == "string" and type(expiry) == "number" and expiry > os.time() then
				data.Boosts[key] = math.floor(expiry)
			end
		end
	end

	if type(source.Receipts) == "table" then
		for _, receipt in source.Receipts do
			if type(receipt) == "string" and #data.Receipts < 100 then
				table.insert(data.Receipts, receipt)
			end
		end
	end
	return data
end

local function dataKey(player: Player): string
	return "Player_" .. player.UserId
end

function PlayerData.init()
	if game.PlaceId == 0 then
		warnDataStore("DataStores need a published place (PlaceId is 0).")
	else
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(Config.DataStoreName)
		end)
		if ok then
			dataStore = result
		else
			disableDataStore(`DataStore unavailable ({result}).`)
		end
	end

	-- Push UI snapshots at most ~10 times a second.
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		accumulator = 0
		for player in dirty do
			dirty[player] = nil
			PlayerData.sendSnapshot(player)
		end
	end)

	Remotes.func("GetData").OnServerInvoke = function(player: Player)
		return PlayerData.snapshot(player)
	end

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in profiles do
				task.spawn(PlayerData.save, player)
			end
		end
	end)
end

-- Loads (or creates) the player's data. Yields while talking to the DataStore.
function PlayerData.load(player: Player): Data
	local data: Data? = nil
	local canSave = dataStore ~= nil

	for attempt = 1, Config.LoadRetries do
		local store = dataStore
		if not store then
			break
		end
		local ok, result = pcall(function()
			return store:GetAsync(dataKey(player))
		end)
		if ok then
			data = reconcile(result)
			break
		end
		local message = tostring(result)
		warn(`[FillTheStore] Load attempt {attempt} failed for {player.Name}: {message}`)
		if isAccessError(message) then
			disableDataStore("DataStore access denied (turn on 'Enable Studio Access to API Services').")
			canSave = false
			break
		end
		if attempt == Config.LoadRetries then
			-- Don't overwrite a real save with fresh data if loading keeps failing.
			canSave = false
		else
			task.wait(1.5)
		end
	end

	local profile: Profile = {
		Data = data or defaultData(),
		CanSave = canSave,
		Dirty = false,
		Saving = false,
	}
	profiles[player] = profile
	PlayerData.updateLeaderstats(player)
	return profile.Data
end

function PlayerData.get(player: Player): Data?
	local profile = profiles[player]
	return profile and profile.Data
end

function PlayerData.save(player: Player): boolean
	local profile = profiles[player]
	local store = dataStore
	if not profile or not profile.CanSave or not store or profile.Saving then
		return false
	end
	profile.Saving = true
	local beforeSave = PlayerData.BeforeSave
	if beforeSave then
		local ok, err = pcall(function()
			beforeSave(player, profile.Data)
		end)
		if not ok then
			warn("[FillTheStore] BeforeSave failed: " .. tostring(err))
		end
	end
	local payload = table.clone(profile.Data) :: any
	payload.Version = DATA_VERSION
	activeSaves += 1
	local ok, err = pcall(function()
		store:UpdateAsync(dataKey(player), function()
			return payload
		end)
	end)
	activeSaves -= 1
	profile.Saving = false
	if not ok then
		warn(`[FillTheStore] Save failed for {player.Name}: {err}`)
		if isAccessError(tostring(err)) then
			disableDataStore("DataStore access denied while saving.")
		end
	end
	return ok
end

-- Final save + forget the player.
function PlayerData.release(player: Player)
	PlayerData.save(player)
	profiles[player] = nil
	dirty[player] = nil
end

-- Used by BindToClose: save everyone and wait for every in-flight save
-- (including ones started by players leaving) to finish.
function PlayerData.saveAll()
	for player in profiles do
		task.spawn(PlayerData.save, player)
	end
	task.wait()
	local deadline = os.clock() + 25
	while activeSaves > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

function PlayerData.canSave(): boolean
	return dataStore ~= nil
end

-- Money -----------------------------------------------------------------------

function PlayerData.addCash(player: Player, amount: number)
	local data = PlayerData.get(player)
	if not data or amount <= 0 then
		return
	end
	data.Cash += math.floor(amount)
	data.TotalEarned += math.floor(amount)
	PlayerData.markDirty(player)
end

-- Cash that isn't earned from sales (tutorial rewards, Robux packs):
-- doesn't count towards the "Total Earned" leaderboard.
function PlayerData.giveCash(player: Player, amount: number)
	local data = PlayerData.get(player)
	if not data or amount <= 0 then
		return
	end
	data.Cash += math.floor(amount)
	PlayerData.markDirty(player)
end

-- Returns true and deducts if the player can afford it.
function PlayerData.spend(player: Player, amount: number): boolean
	local data = PlayerData.get(player)
	if not data or amount < 0 or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	PlayerData.markDirty(player)
	return true
end

-- Inventory -------------------------------------------------------------------

function PlayerData.addItem(player: Player, key: string, count: number)
	local data = PlayerData.get(player)
	if not data or count <= 0 or not Items.isValid(key) then
		return
	end
	data.Inventory[key] = (data.Inventory[key] or 0) + count
	PlayerData.markDirty(player)
end

function PlayerData.takeItem(player: Player, key: string, count: number): boolean
	local data = PlayerData.get(player)
	if not data then
		return false
	end
	local have = data.Inventory[key] or 0
	if have < count then
		return false
	end
	local left = have - count
	if left > 0 then
		data.Inventory[key] = left
	else
		data.Inventory[key] = nil
	end
	PlayerData.markDirty(player)
	return true
end

function PlayerData.inventoryTotal(player: Player): number
	local data = PlayerData.get(player)
	if not data then
		return 0
	end
	local total = 0
	for _, count in data.Inventory do
		total += count
	end
	return total
end

-- Snapshots for the client ---------------------------------------------------

function PlayerData.storeValue(player: Player): number
	local data = PlayerData.get(player)
	if not data then
		return 0
	end
	local value = Upgrades.totalSpent(data.Upgrades)
	for key, count in data.Inventory do
		value += Items.value(key) * count
	end
	if PlayerData.ExtraValue then
		value += PlayerData.ExtraValue(player)
	end
	return value
end

function PlayerData.snapshot(player: Player): { [string]: any }?
	local data = PlayerData.get(player)
	if not data then
		return nil
	end
	local boostEnds = {}
	local serverNow = workspace:GetServerTimeNow()
	for key, expiry in data.Boosts do
		local remaining = expiry - os.time()
		if remaining > 0 then
			boostEnds[key] = serverNow + remaining
		end
	end
	local snapshot: { [string]: any } = {
		Cash = data.Cash,
		TotalEarned = data.TotalEarned,
		Upgrades = table.clone(data.Upgrades),
		Inventory = table.clone(data.Inventory),
		SelectedProduct = data.SelectedProduct,
		StoreValue = PlayerData.storeValue(player),
		ItemsSold = data.Stats.ItemsSold,
		Saving = PlayerData.canSave(),
		Tutorial = { Step = data.Tutorial.Step, Done = data.Tutorial.Done },
		BoostEnds = boostEnds,
	}
	for _, extra in PlayerData.SnapshotExtras do
		extra(player, snapshot)
	end
	return snapshot
end

function PlayerData.updateLeaderstats(player: Player)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	-- Player list: the first stat ("Value") is what the list sorts by.
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		local folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		for _, name in { "Value", "Cash", "Sold" } do
			local stat = Instance.new("IntValue")
			stat.Name = name
			stat.Parent = folder
		end
		folder.Parent = player
		leaderstats = folder
	end
	local values: { [string]: number } = {
		Value = math.floor(PlayerData.storeValue(player)),
		Cash = data.Cash,
		Sold = data.Stats.ItemsSold,
	}
	for name, value in values do
		local stat = (leaderstats :: Instance):FindFirstChild(name)
		if stat and stat:IsA("IntValue") and stat.Value ~= value then
			stat.Value = value
		end
	end
end

function PlayerData.sendSnapshot(player: Player)
	if player.Parent ~= Players then
		return
	end
	local snapshot = PlayerData.snapshot(player)
	if snapshot then
		Remotes.event("DataUpdate"):FireClient(player, snapshot)
		PlayerData.updateLeaderstats(player)
		PlayerData.Changed:Fire(player)
	end
end

function PlayerData.markDirty(player: Player)
	if profiles[player] then
		dirty[player] = true
	end
end

return PlayerData
