--!strict
-- The first-time tutorial. Each step is completed by the server when the
-- matching gameplay event happens, and pays a small cash reward.

export type Step = {
	Id: string,
	Icon: string,
	Title: string,
	Text: string,
	TouchText: string, -- same instruction for phones/tablets
	Reward: number,
}

local Tutorial = {}

Tutorial.Steps = {
	{
		Id = "Grab",
		Icon = "📦",
		Title = "GRAB A BOX!",
		Text = "Walk to the yellow loading bay and press E on a box",
		TouchText = "Walk to the yellow loading bay and tap a box",
		Reward = 25,
	},
	{
		Id = "Unpack",
		Icon = "🛒",
		Title = "FILL A SHELF!",
		Text = "Carry it into your shop and press E at a shelf",
		TouchText = "Carry it into your shop and tap a shelf",
		Reward = 50,
	},
	{
		Id = "Sell",
		Icon = "💷",
		Title = "MAKE A SALE!",
		Text = "Customers are on their way — watch them buy your stuff!",
		TouchText = "Customers are on their way — watch them buy your stuff!",
		Reward = 75,
	},
	{
		Id = "Upgrade",
		Icon = "⬆️",
		Title = "UPGRADE YOUR SHOP!",
		Text = "Press the green UPGRADES button and buy any upgrade",
		TouchText = "Tap the green UPGRADES button and buy any upgrade",
		Reward = 100,
	},
} :: { Step }

Tutorial.FinishReward = 250

function Tutorial.step(index: number): Step?
	return Tutorial.Steps[index]
end

return Tutorial
