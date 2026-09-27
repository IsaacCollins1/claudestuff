--!strict
-- Client-side copy of the player's data (read-only; the server is authoritative).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))

export type Snapshot = {
	Cash: number,
	TotalEarned: number,
	Upgrades: { [string]: number },
	Inventory: { [string]: number },
	SelectedProduct: string?,
	StoreValue: number,
	ItemsSold: number,
	Saving: boolean,
}

local State = {}

State.Data = nil :: Snapshot?
State.Changed = Signal.new() :: Signal.Signal<Snapshot, Snapshot?>

local function apply(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	local previous = State.Data
	State.Data = snapshot
	State.Changed:Fire(snapshot, previous)
end

function State.init()
	Remotes.event("DataUpdate").OnClientEvent:Connect(apply)
	task.spawn(function()
		-- The server may still be loading our save; keep asking until it answers.
		for _ = 1, 20 do
			if State.Data then
				return
			end
			local ok, snapshot = pcall(function()
				return Remotes.func("GetData"):InvokeServer()
			end)
			if ok and snapshot then
				if not State.Data then
					apply(snapshot)
				end
				return
			end
			task.wait(1)
		end
	end)
end

function State.inventoryTotal(): number
	local data = State.Data
	if not data then
		return 0
	end
	local total = 0
	for _, count in data.Inventory do
		total += count
	end
	return total
end

return State
