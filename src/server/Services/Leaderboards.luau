--!strict
-- Global leaderboards (OrderedDataStores) shown on big boards in the middle
-- of the street and in the 🏆 menu. If DataStores aren't available (Studio
-- without API access) they rank the players in this server instead.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local LeaderboardBuilder = require(script.Parent.Parent.Builders.LeaderboardBuilder)
local PlayerData = require(script.Parent.PlayerData)

export type Entry = { UserId: number, Name: string, Value: number }

type BoardDef = {
	Key: string,
	Title: string,
	Icon: string,
	Color: Color3,
	StoreName: string,
	Money: boolean,
	Get: (player: Player) -> number,
}

local Leaderboards = {}

Leaderboards.Boards = {
	{
		Key = "Value",
		Title = "TOP STORES",
		Icon = "🏪",
		Color = Color3.fromRGB(255, 90, 120),
		StoreName = "FillTheStore_TopValue_v1",
		Money = true,
		Get = function(player: Player): number
			return PlayerData.storeValue(player)
		end,
	},
	{
		Key = "Earned",
		Title = "TOP EARNERS",
		Icon = "💷",
		Color = Color3.fromRGB(70, 200, 100),
		StoreName = "FillTheStore_TopEarned_v1",
		Money = true,
		Get = function(player: Player): number
			local data = PlayerData.get(player)
			return if data then data.TotalEarned else 0
		end,
	},
	{
		Key = "Sold",
		Title = "MOST SOLD",
		Icon = "🛒",
		Color = Color3.fromRGB(60, 150, 255),
		StoreName = "FillTheStore_TopSold_v1",
		Money = false,
		Get = function(player: Player): number
			local data = PlayerData.get(player)
			return if data then data.Stats.ItemsSold else 0
		end,
	},
} :: { BoardDef }

local stores: { [string]: OrderedDataStore } = {}
local latest: { [string]: { Entry } } = {}
local isGlobal = false
local nameCache: { [number]: string } = {}
local signs: { [string]: LeaderboardBuilder.Board } = {}

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.Name
		return player.Name
	end
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = if ok and type(name) == "string" then name else "Player " .. userId
	nameCache[userId] = resolved
	return resolved
end

local function localRanking(board: BoardDef): { Entry }
	local entries = {}
	for _, player in Players:GetPlayers() do
		if PlayerData.get(player) then
			table.insert(entries, { UserId = player.UserId, Name = player.Name, Value = math.floor(board.Get(player)) })
		end
	end
	table.sort(entries, function(a, b)
		return a.Value > b.Value
	end)
	while #entries > LeaderboardBuilder.Rows do
		table.remove(entries)
	end
	return entries
end

local function globalRanking(board: BoardDef): { Entry }?
	local store = stores[board.Key]
	if not store then
		return nil
	end
	for _, player in Players:GetPlayers() do
		if PlayerData.get(player) then
			local value = math.floor(board.Get(player))
			pcall(function()
				store:SetAsync(tostring(player.UserId), value)
			end)
		end
	end
	local ok, page = pcall(function()
		return store:GetSortedAsync(false, LeaderboardBuilder.Rows):GetCurrentPage()
	end)
	if not ok or type(page) ~= "table" then
		-- DataStores unavailable (e.g. Studio without API access): use this server.
		stores[board.Key] = nil
		return nil
	end
	local entries = {}
	for _, item in page :: { any } do
		local userId = tonumber(item.key)
		if userId then
			table.insert(entries, { UserId = userId, Name = nameOf(userId), Value = item.value })
		end
	end
	return entries
end

local function formatValue(board: BoardDef, value: number): string
	return if board.Money then Format.shortMoney(value) else Format.short(value)
end

local function updateSign(board: BoardDef, entries: { Entry })
	local sign = signs[board.Key]
	if not sign then
		return
	end
	for _, boardFace in sign.Faces do
		for index, row in boardFace.Rows do
			local entry = entries[index]
			row.Frame.Visible = entry ~= nil
			if entry then
				row.Name.Text = entry.Name
				row.Value.Text = formatValue(board, entry.Value)
				row.Avatar.Image = `rbxthumb://type=AvatarHeadShot&id={entry.UserId}&w=48&h=48`
			end
		end
		boardFace.Footer.Text = if isGlobal then "🌍 All servers · updates every minute" else "🏠 This server"
	end
end

function Leaderboards.refresh()
	local anyGlobal = false
	for _, board in Leaderboards.Boards do
		local entries = globalRanking(board)
		if entries then
			anyGlobal = true
			latest[board.Key] = entries
		else
			latest[board.Key] = localRanking(board)
		end
	end
	isGlobal = anyGlobal
	for _, board in Leaderboards.Boards do
		updateSign(board, latest[board.Key])
	end
	Remotes.event("Leaderboards"):FireAllClients(Leaderboards.snapshot())
end

function Leaderboards.snapshot(): { [string]: any }
	local boards = {}
	for _, board in Leaderboards.Boards do
		table.insert(boards, {
			Key = board.Key,
			Title = board.Title,
			Icon = board.Icon,
			Money = board.Money,
			Entries = latest[board.Key] or {},
		})
	end
	return { Global = isGlobal, Boards = boards }
end

-- Signs stand on the central reservation of the road.
function Leaderboards.buildSigns(parent: Instance, cframes: { CFrame })
	for index, board in Leaderboards.Boards do
		local cframe = cframes[index]
		if cframe then
			signs[board.Key] = LeaderboardBuilder.build(parent, cframe, board.Title, board.Icon, board.Color)
		end
	end
end

function Leaderboards.init()
	if game.PlaceId ~= 0 then
		for _, board in Leaderboards.Boards do
			local ok, store = pcall(function()
				return DataStoreService:GetOrderedDataStore(board.StoreName)
			end)
			if ok then
				stores[board.Key] = store
			end
		end
	end
	Remotes.func("GetLeaderboards").OnServerInvoke = function()
		return Leaderboards.snapshot()
	end
	task.spawn(function()
		task.wait(3)
		while true do
			local ok, err = pcall(function()
				Leaderboards.refresh()
			end)
			if not ok then
				warn("[FillTheStore] Leaderboard refresh failed: " .. tostring(err))
			end
			-- Global boards refresh slowly (DataStore limits); local ones can be snappy.
			task.wait(if isGlobal then Config.LeaderboardRefresh else 10)
		end
	end)
end

return Leaderboards
