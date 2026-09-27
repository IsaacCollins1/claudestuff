--!strict
-- 🏆 menu: the same global leaderboards as the big signs in the street.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local UIKit = require(script.Parent.UIKit)
local Window = require(script.Parent.Window)

local Colors = UIKit.Colors
local player = Players.LocalPlayer

local LeaderboardPanel = {}

type Entry = { UserId: number, Name: string, Value: number }
type BoardData = { Key: string, Title: string, Icon: string, Money: boolean, Entries: { Entry } }
type Snapshot = { Global: boolean, Boards: { BoardData } }

local window: Window.Window
local list: ScrollingFrame
local current = "Value"
local latest: Snapshot? = nil

local MEDALS = { "🥇", "🥈", "🥉" }
local TABS: { Window.Tab } = {
	{ Key = "Value", Text = "🏪 STORES", Color = Colors.Pink },
	{ Key = "Earned", Text = "💷 EARNERS", Color = Colors.Green },
	{ Key = "Sold", Text = "🛒 SOLD", Color = Colors.Blue },
}

local function render()
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local snapshot = latest
	if not snapshot then
		window.Subtitle.Text = "Loading…"
		return
	end
	local board: BoardData? = nil
	for _, candidate in snapshot.Boards do
		if candidate.Key == current then
			board = candidate
		end
	end
	if not board then
		return
	end
	window.Subtitle.Text = if snapshot.Global then "🌍 Top players in every server" else "🏠 Players in this server"
	for rank, entry in board.Entries do
		local mine = entry.UserId == player.UserId
		local row = UIKit.new("Frame", {
			Name = "Row" .. rank,
			Size = UDim2.new(1, -12, 0, 58),
			BackgroundColor3 = if mine then UIKit.darken(Colors.Green, 0.2) else Colors.PanelLight,
			LayoutOrder = rank,
			ZIndex = 22,
		}, list)
		UIKit.corner(row, UDim.new(0, 16))
		UIKit.stroke(row, if mine then Colors.Yellow else Colors.Outline, 3)
		UIKit.title(row, MEDALS[rank] or ("#" .. rank), {
			Size = UDim2.fromOffset(56, 40),
			Position = UDim2.fromOffset(8, 9),
			ZIndex = 23,
		}, Colors.Outline, 2)
		local avatar = UIKit.new("ImageLabel", {
			Size = UDim2.fromOffset(46, 46),
			Position = UDim2.fromOffset(68, 6),
			BackgroundColor3 = Colors.Panel,
			Image = `rbxthumb://type=AvatarHeadShot&id={entry.UserId}&w=48&h=48`,
			ZIndex = 23,
		}, row)
		UIKit.corner(avatar, UDim.new(1, 0))
		UIKit.title(row, entry.Name, {
			Size = UDim2.new(1, -330, 0, 30),
			Position = UDim2.fromOffset(126, 14),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 23,
		}, Colors.Outline, 2)
		UIKit.title(row, if board.Money then Format.money(entry.Value) else Format.commas(entry.Value), {
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(190, 30),
			Position = UDim2.new(1, -16, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Colors.Yellow,
			ZIndex = 23,
		}, Colors.Outline, 2)
	end
end

function LeaderboardPanel.init(screen: ScreenGui)
	window = Window.new(screen, { Title = "LEADERBOARD", Icon = "🏆", Color = Colors.Purple })
	local body = Window.tabs(window, TABS, function(key: string)
		current = key
		render()
	end)
	list = UIKit.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Colors.Grey,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 22,
	}, body)
	UIKit.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	UIKit.padding(list, 6)

	Remotes.event("Leaderboards").OnClientEvent:Connect(function(snapshot: Snapshot)
		latest = snapshot
		if window:IsOpen() then
			render()
		end
	end)
	window.OnOpen = function()
		render()
		task.spawn(function()
			local ok, snapshot = pcall(function()
				return Remotes.func("GetLeaderboards"):InvokeServer()
			end)
			if ok and type(snapshot) == "table" then
				latest = snapshot
				render()
			end
		end)
	end
	local select = window.SelectTab
	if select then
		select("Value")
	end
end

function LeaderboardPanel.toggle()
	Window.toggle(window)
end

return LeaderboardPanel
