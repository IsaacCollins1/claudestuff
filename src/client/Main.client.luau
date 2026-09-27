--!strict
-- Fill the Store! — client entry point. Builds the UI and starts the
-- client-side controllers in ./Controllers.

local Players = game:GetService("Players")

local Controllers = script.Parent.Controllers
local Effects = require(Controllers.Effects)
local Guide = require(Controllers.Guide)
local HUD = require(Controllers.HUD)
local LeaderboardPanel = require(Controllers.LeaderboardPanel)
local RebirthPanel = require(Controllers.RebirthPanel)
local UnlocksPanel = require(Controllers.UnlocksPanel)
local Notifications = require(Controllers.Notifications)
local Prompts = require(Controllers.Prompts)
local ShopPanel = require(Controllers.ShopPanel)
local SoundPlayer = require(Controllers.SoundPlayer)
local State = require(Controllers.State)
local StockPanel = require(Controllers.StockPanel)
local TutorialUI = require(Controllers.TutorialUI)
local UpgradesPanel = require(Controllers.UpgradesPanel)

local player = Players.LocalPlayer

local screen = Instance.new("ScreenGui")
screen.Name = "FillTheStoreUI"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.IgnoreGuiInset = false

-- Scale the whole UI down on small (mobile) screens.
local uiScale = Instance.new("UIScale")
uiScale.Parent = screen
local function updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		local size = camera.ViewportSize
		uiScale.Scale = math.clamp(math.min(size.X / 1150, size.Y / 720), 0.55, 1.15)
	end
end
updateScale()
local function watchCamera()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		updateScale()
	end
end
watchCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)

screen.Parent = player:WaitForChild("PlayerGui")

SoundPlayer.init()
State.init()
HUD.init(screen)
Notifications.init(screen)
UpgradesPanel.init(screen)
StockPanel.init(screen)
ShopPanel.init(screen)
LeaderboardPanel.init(screen)
UnlocksPanel.init(screen)
RebirthPanel.init(screen)
Effects.init(screen)
Prompts.init()
Guide.init()
TutorialUI.init(screen)

HUD.UpgradesPressed:Connect(UpgradesPanel.toggle)
HUD.StockPressed:Connect(StockPanel.toggle)
HUD.LeadersPressed:Connect(LeaderboardPanel.toggle)
HUD.UnlocksPressed:Connect(UnlocksPanel.toggle)
HUD.RebirthPressed:Connect(RebirthPanel.toggle)
HUD.ShopPressed:Connect(function(tab: string?)
	if tab then
		ShopPanel.open(tab)
	else
		ShopPanel.toggle()
	end
end)
