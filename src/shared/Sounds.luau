--!strict
-- Every sound effect in one place so they're easy to swap.
-- These use sounds that ship with the Roblox client (rbxasset://), so they work
-- without any uploads. Replace `Id` with any "rbxassetid://123" from the
-- Creator Store to change a sound.

export type SoundDef = {
	Id: string,
	Volume: number,
	Speed: number,
}

local Sounds: { [string]: SoundDef } = {
	-- Product popping onto a shelf (pitch rises as the shelf fills)
	Stock = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.28, Speed = 1.2 },
	-- Customer paying at the till
	Cash = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.55, Speed = 1.8 },
	CashLow = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.4, Speed = 1.35 },
	-- Picking up / putting down boxes
	Pickup = { Id = "rbxasset://sounds/snap.wav", Volume = 0.6, Speed = 1 },
	Thud = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.7, Speed = 0.8 },
	-- Box opening
	BoxShake = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5, Speed = 0.8 },
	BoxOpen = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.6, Speed = 1.1 },
	ItemPop = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Speed = 1.5 },
	-- UI
	Click = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5, Speed = 1 },
	Error = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5, Speed = 0.55 },
	Upgrade = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Speed = 0.9 },
	-- Big moments
	Delivery = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Speed = 0.7 },
	Rare = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Speed = 2.2 },
	Sad = { Id = "rbxasset://sounds/action_get_up.mp3", Volume = 0.35, Speed = 0.7 },
}

return Sounds
