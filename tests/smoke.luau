--!nocheck
-- Quick smoke test: boot the server, join one player, wait for the first delivery.
local process = require("@lune/process")

local Runtime = require("./emulator/Runtime")
local Scheduler = require("./emulator/Scheduler")
local Instances = require("./emulator/Instances")

local placePath = process.args[1] or "build/FillTheStore.rbxlx"
local runtime = Runtime.new({ placePath = placePath, placeId = 0 })
runtime:startServer()
runtime:run(1)
local player = runtime:addPlayer("Isaac", 1001, true)
runtime:run(12)

local world = runtime.workspace:FindFirstChild("World")
print("World built:", world ~= nil, "instances created:", Instances.created)
local plot = world.Plots:FindFirstChild("Plot" .. tostring(player:GetAttribute("PlotIndex")))
print("PlotIndex:", player:GetAttribute("PlotIndex"), "StoreLevel:", player:GetAttribute("StoreLevel"), "NextDeliveryAt:", player:GetAttribute("NextDeliveryAt"))
local store = plot and plot:FindFirstChild("Store")
print("Store:", store and store:GetFullName())
if store then
	print("  shelves:", #store.Shelves:GetChildren(), "sign:", store.Sign:FindFirstChildOfClass("SurfaceGui").OwnerName.Text, "|", store.Sign:FindFirstChildOfClass("SurfaceGui").Value.Text)
end
local boxes = plot:FindFirstChild("Boxes")
print("Boxes:", boxes and #boxes:GetChildren())
if boxes then
	for _, box in boxes:GetChildren() do
		print("  ", box.Name, box.Box.Position, box.Box:FindFirstChild("BoxPrompt") ~= nil)
	end
end
print("Character:", player.Character and player.Character.HumanoidRootPart.Position)
local gui = player.PlayerGui:FindFirstChild("FillTheStoreUI")
print("UI:", gui ~= nil, gui and #gui:GetDescendants())
if gui then
	print("  cash:", gui.Cash.Amount.Text, "delivery:", gui.Delivery:FindFirstChildOfClass("TextLabel").Text, "hint:", gui.Hint.Visible, gui.Hint:FindFirstChildOfClass("TextLabel").Text)
	for _, banner in gui.Notifications:GetChildren() do
		if banner:IsA("Frame") then print("  banner:", banner:FindFirstChildOfClass("TextLabel").Text) end
	end
end
print("Remote log:")
for k, v in runtime.remoteLog do print("  ", k, v) end
print("Sounds:")
for k, v in runtime.soundLog do print("  ", k, v) end
print("Warnings:", #runtime.warnings)
for _, w in runtime.warnings do
	print("  ", w)
end
print("Falling parts:", #Instances.findFallingParts(runtime.workspace))
for i, name in Instances.findFallingParts(runtime.workspace) do if i <= 10 then print("  ", name) end end
print("Errors:", #Scheduler.errors)
process.exit(if #Scheduler.errors == 0 then 0 else 1)
