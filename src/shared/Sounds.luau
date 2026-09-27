--!strict
-- Every sound effect in one place so they're easy to swap.
-- These use sounds that ship with the Roblox client (rbxasset://), so they work
-- without any uploads. Replace `Id` with any "rbxassetid://123" from the
-- Creator Store to change a sound.
--
-- `Fallback` is used automatically if `Id` fails to load on a client; the
-- fallbacks are the default character sounds, which every client has.

export type SoundDef = {
	Id: string,
	Volume: number,
	Speed: number,
	Fallback: string?,
}

local JUMP = "rbxasset://sounds/action_jump.mp3"
local LAND = "rbxasset://sounds/action_jump_land.mp3"
local GET_UP = "rbxasset://sounds/action_get_up.mp3"

local Sounds: { [string]: SoundDef } = {
	-- Product popping onto a shelf (pitch rises as the shelf fills)
	Stock = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.28, Speed = 1.2, Fallback = JUMP },
	-- Customer paying at the till
	Cash = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.55, Speed = 1.8, Fallback = JUMP },
	CashLow = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.4, Speed = 1.35, Fallback = JUMP },
	-- Picking up / putting down boxes
	Pickup = { Id = "rbxasset://sounds/snap.wav", Volume = 0.6, Speed = 1, Fallback = LAND },
	Thud = { Id = LAND, Volume = 0.7, Speed = 0.8 },
	-- Box opening
	BoxShake = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5, Speed = 0.8, Fallback = LAND },
	BoxOpen = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.6, Speed = 1.1, Fallback = JUMP },
	ItemPop = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Speed = 1.5, Fallback = JUMP },
	-- UI
	Click = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5, Speed = 1, Fallback = LAND },
	Error = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5, Speed = 0.55, Fallback = GET_UP },
	Upgrade = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Speed = 0.9, Fallback = JUMP },
	-- Big moments
	Delivery = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Speed = 0.7, Fallback = JUMP },
	Rare = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Speed = 2.2, Fallback = JUMP },
	Sad = { Id = GET_UP, Volume = 0.35, Speed = 0.7 },
	-- Simulator UI
	Coin = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.25, Speed = 2.4, Fallback = JUMP },
	Purchase = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Speed = 1.25, Fallback = JUMP },
	StepDone = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Speed = 1.6, Fallback = JUMP },
	Whoosh = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.4, Speed = 1.3, Fallback = JUMP },
	Pop = { Id = "rbxasset://sounds/snap.wav", Volume = 0.7, Speed = 0.7, Fallback = LAND }, -- firework bursts
}

return Sounds
