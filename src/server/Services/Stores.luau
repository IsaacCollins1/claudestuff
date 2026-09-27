--!strict
-- Plots and stores: assigns each player a plot, builds their shop for the
-- current store level, and rebuilds it when they expand.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local StoreLevels = require(Shared.StoreLevels)
local Upgrades = require(Shared.Upgrades)

local StoreBuilder = require(script.Parent.Parent.Builders.StoreBuilder)
local WorldBuilder = require(script.Parent.Parent.Builders.WorldBuilder)
local Boxes = require(script.Parent.Boxes)
local Customers = require(script.Parent.Customers)
local PlayerData = require(script.Parent.PlayerData)
local Registry = require(script.Parent.Registry)
local Shelves = require(script.Parent.Shelves)
local Workers = require(script.Parent.Workers)

type Session = Registry.Session
type Store = Registry.Store

local Stores = {}

local plots: { WorldBuilder.PlotInfo } = {}
local owners: { [number]: Player } = {}

function Stores.init()
	plots = WorldBuilder.build()

	-- Shelf contents are saved with the player's data and count towards store value.
	PlayerData.BeforeSave = function(player: Player, data: PlayerData.Data)
		local store = Registry.store(player)
		if store and store.Alive then
			data.Shelves = Shelves.serialize(store)
		end
	end
	PlayerData.ExtraValue = function(player: Player): number
		local store = Registry.store(player)
		return if store then Shelves.stockValue(store) else 0
	end

	-- Keep every sign's "Value: £..." up to date.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, session in Registry.Sessions do
				local store = session.Store
				if store and store.Alive then
					Stores.updateSign(store)
				end
			end
		end
	end)
end

function Stores.updateSign(store: Store)
	local value = PlayerData.storeValue(store.Owner)
	if value ~= store.LastValue then
		store.LastValue = value
		store.SignValue.Text = "Value: " .. Format.money(value)
	end
end

-- Gives the player a free plot. Returns nil if the server's plots are all taken.
function Stores.claim(player: Player): Session?
	for index, plot in plots do
		if not owners[index] then
			owners[index] = player
			plot.VacantSign.Parent = nil
			local session: Session = {
				Player = player,
				PlotIndex = index,
				PlotCFrame = plot.CFrame,
				PlotModel = plot.Model,
				Accent = plot.Accent,
				Store = nil,
				Boxes = {},
				Carried = nil,
				Alive = true,
				NextBoxId = 0,
			}
			Registry.Sessions[player] = session
			plot.Model:SetAttribute("OwnerUserId", player.UserId)
			player:SetAttribute("PlotIndex", index)
			return session
		end
	end
	return nil
end

-- Builds the store for the player's current level and starts its systems.
function Stores.open(session: Session): Store?
	local player = session.Player
	local data = PlayerData.get(player)
	if not data then
		return nil
	end
	local level = math.clamp(data.Upgrades.StoreSize, 1, StoreLevels.MaxLevel)
	local built = StoreBuilder.build(session.PlotCFrame, level, session.Accent, player.Name, player.UserId, session.PlotModel)
	local store: Store = {
		Session = session,
		Owner = player,
		Level = level,
		Layout = StoreLevels.getLayout(level),
		Model = built.Model,
		Shelves = {},
		Register = built.Register,
		SignName = built.SignName,
		SignValue = built.SignValue,
		Customers = {},
		CustomerCount = 0,
		Queue = {},
		Workers = {},
		Alive = true,
		LastValue = -1,
	}
	session.Store = store
	Shelves.setup(store, built, Upgrades.shelfCapacity(data.Upgrades.ShelfCapacity))
	Shelves.restore(store, data.Shelves)
	Customers.start(store)
	Workers.refresh(store)
	Stores.updateSign(store)
	player:SetAttribute("StoreLevel", level)
	return store
end

-- Tears the store down, remembering what was on the shelves.
function Stores.close(session: Session)
	local store = session.Store
	if not store then
		return
	end
	local data = PlayerData.get(session.Player)
	if data then
		data.Shelves = Shelves.serialize(store)
	end
	store.Alive = false
	Customers.clear(store)
	Workers.clear(store)
	store.Model:Destroy()
	session.Store = nil
end

-- Store expansion: rebuild at the new level, shelves keep their products.
function Stores.rebuild(player: Player): Store?
	local session = Registry.session(player)
	if not session then
		return nil
	end
	Stores.close(session)
	return Stores.open(session)
end

-- Player left: free the plot for someone else.
function Stores.release(player: Player)
	local session = Registry.session(player)
	if not session then
		return
	end
	session.Alive = false
	Stores.close(session)
	Boxes.clear(session)
	local plot = plots[session.PlotIndex]
	for _, child in plot.Model:GetChildren() do
		if child.Name == "DeliveryVan" then
			child:Destroy()
		end
	end
	plot.Model:SetAttribute("OwnerUserId", nil)
	plot.VacantSign.Parent = plot.Model
	owners[session.PlotIndex] = nil
	Registry.Sessions[player] = nil
end

-- Where the player should appear when they spawn.
function Stores.spawnCFrame(player: Player): CFrame?
	local session = Registry.session(player)
	local store = session and session.Store
	if not session or not store then
		return nil
	end
	return session.PlotCFrame * store.Layout.OwnerSpawn
end

return Stores
