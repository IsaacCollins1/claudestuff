--!strict
-- Shared server state (sessions, stores, shelves, boxes). Holding the types and
-- tables here lets services talk to each other without circular requires.

local StoreLevels = require(game:GetService("ReplicatedStorage").Shared.StoreLevels)

export type BoxInfo = {
	Id: number,
	Session: Session,
	Model: Model,
	Root: BasePart,
	ProductId: string,
	Quantity: number,
	Spot: number?, -- index of the loading bay spot it sits on (nil while carried)
	Carried: boolean,
	Opened: boolean,
	Prompt: ProximityPrompt?,
	Special: string?, -- "Golden" for Golden Crates
}

export type Shelf = {
	Index: number,
	Store: Store,
	Model: Model,
	CFrame: CFrame, -- world CFrame of the shelf base (LookVector = product side)
	ItemsFolder: Folder,
	Node: string, -- nav node customers/workers stand at
	Capacity: number,
	ItemScale: number, -- products are drawn bigger when a shelf has fewer, wider slots
	SlotCFrames: { CFrame },
	Slots: { [number]: string }, -- slot index -> item key (nil = empty)
	SlotModels: { [number]: Model },
	Reserved: number, -- items promised to customers walking over
	Busy: boolean, -- someone is stocking it right now
	WorkerAssigned: boolean,
	BarFill: Frame,
	CountLabel: TextLabel,
}

export type Store = {
	Session: Session,
	Owner: Player,
	Level: number,
	Layout: StoreLevels.Layout,
	Model: Model,
	Shelves: { Shelf },
	Register: BasePart,
	SignName: TextLabel,
	SignValue: TextLabel,
	Customers: { [any]: boolean },
	CustomerCount: number,
	Queue: { any },
	Workers: { any },
	Alive: boolean,
	LastValue: number,
}

export type Session = {
	Player: Player,
	PlotIndex: number,
	PlotCFrame: CFrame,
	PlotModel: Model,
	Accent: Color3,
	Store: Store?,
	Boxes: { [Model]: BoxInfo },
	Carried: BoxInfo?,
	Alive: boolean,
	NextBoxId: number,
}

local Registry = {}

Registry.Sessions = {} :: { [Player]: Session }

function Registry.session(player: Player): Session?
	return Registry.Sessions[player]
end

function Registry.store(player: Player): Store?
	local session = Registry.Sessions[player]
	return session and session.Store
end

return Registry
