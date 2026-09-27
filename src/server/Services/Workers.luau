--!strict
-- Staff NPCs bought with the Workers upgrade. They slowly walk to the
-- emptiest shelf and restock it from the owner's inventory.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local StoreLevels = require(Shared.StoreLevels)
local Upgrades = require(Shared.Upgrades)

local NpcBuilder = require(script.Parent.Parent.Builders.NpcBuilder)
local NpcMotion = require(script.Parent.NpcMotion)
local Perks = require(script.Parent.Perks)
local PlayerData = require(script.Parent.PlayerData)
local Registry = require(script.Parent.Registry)
local Shelves = require(script.Parent.Shelves)

type Store = Registry.Store

type Worker = {
	Npc: NpcBuilder.Npc,
	Walker: NpcMotion.Walker,
	Home: Vector3,
	Node: string,
	Alive: boolean,
}

local Workers = {}

local STAFF_STYLE: NpcBuilder.Style = {
	Shirt = Color3.fromRGB(60, 190, 90),
	Pants = Color3.fromRGB(40, 44, 60),
	Skin = Color3.fromRGB(240, 190, 145),
	Hat = Color3.fromRGB(255, 255, 255),
}

local function run(store: Store, worker: Worker)
	local layout = store.Layout
	local plotCFrame = store.Session.PlotCFrame
	local owner = store.Owner
	local homeWorld = plotCFrame:PointToWorldSpace(worker.Home)

	while worker.Alive and store.Alive do
		local shelf = if PlayerData.inventoryTotal(owner) > 0 then Shelves.pickForRestock(store) else nil
		if shelf then
			shelf.WorkerAssigned = true
			local ok, err = pcall(function()
				NpcMotion.walkPath(worker.Walker, plotCFrame, StoreLevels.findPath(layout, worker.Node, shelf.Node))
				worker.Node = shelf.Node
				NpcMotion.face(worker.Npc, shelf.CFrame.Position)
				NpcMotion.emote(worker.Npc, "📦", 1)
				Shelves.stockFromInventory(owner, shelf, Config.WorkerItemsPerTrip, Config.WorkerStockDelay)
			end)
			shelf.WorkerAssigned = false
			if not ok then
				if err ~= NpcMotion.Abort then
					warn("[FillTheStore] Worker error: " .. tostring(err))
				end
				break
			end
		else
			if worker.Node ~= "WorkerHome" then
				local ok = pcall(function()
					NpcMotion.walkPath(worker.Walker, plotCFrame, StoreLevels.findPath(layout, worker.Node, "WorkerHome"))
					NpcMotion.walkTo(worker.Walker, homeWorld)
				end)
				if not ok then
					break
				end
				worker.Node = "WorkerHome"
				NpcMotion.face(worker.Npc, plotCFrame:PointToWorldSpace(Vector3.new(0, 0, layout.BackZ)))
			end
			task.wait(1.5)
		end
		task.wait(0.4)
	end
	worker.Alive = false
	worker.Npc.Model:Destroy()
end

local function spawnWorker(store: Store, index: number)
	local layout = store.Layout
	local plotCFrame = store.Session.PlotCFrame
	local home = layout.WorkerHome + Vector3.new(-(index - 1) * 2.6, 0, 0)
	local npc = NpcBuilder.build(plotCFrame * CFrame.new(home) * CFrame.Angles(0, math.pi, 0), STAFF_STYLE, Config.WorkerWalkSpeed)
	npc.Model.Name = "Worker"
	NpcBuilder.nameTag(npc, "STAFF", Color3.fromRGB(120, 255, 140))
	NpcMotion.setCollisionGroup(npc.Model, "NPC")

	local folder = store.Model:FindFirstChild("Workers")
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Workers"
		newFolder.Parent = store.Model
		folder = newFolder
	end
	npc.Model.Parent = folder
	pcall(function()
		npc.Root:SetNetworkOwner(nil)
	end)
	NpcBuilder.animate(npc)

	local worker: Worker
	worker = {
		Npc = npc,
		Walker = {
			Npc = npc,
			IsAlive = function()
				return worker.Alive and store.Alive
			end,
		},
		Home = home,
		Node = "WorkerHome",
		Alive = true,
	}
	table.insert(store.Workers, worker)
	task.spawn(run, store, worker)
end

-- Make sure the store has as many workers as the upgrade level says.
function Workers.refresh(store: Store)
	local data = PlayerData.get(store.Owner)
	if not data or not store.Alive then
		return
	end
	local wanted = Upgrades.workerCount(data.Upgrades.Workers) + Perks.extraWorkers(store.Owner)
	while #store.Workers < wanted do
		spawnWorker(store, #store.Workers + 1)
	end
end

function Workers.clear(store: Store)
	for _, worker in store.Workers do
		(worker :: Worker).Alive = false
	end
	table.clear(store.Workers)
end

return Workers
