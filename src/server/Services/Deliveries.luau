--!strict
-- Every 20-30 seconds a van drives up to each store's loading bay, throws
-- out a few boxes and drives off again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local StoreLevels = require(Shared.StoreLevels)
local Upgrades = require(Shared.Upgrades)

local TruckBuilder = require(script.Parent.Parent.Builders.TruckBuilder)
local WorldBuilder = require(script.Parent.Parent.Builders.WorldBuilder)
local Boxes = require(script.Parent.Boxes)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)
local Registry = require(script.Parent.Registry)

type Session = Registry.Session

local Deliveries = {}

local rng = Random.new()
local DRIVE_DISTANCE = 170

local function tweenTo(part: BasePart, target: CFrame, duration: number, direction: Enum.EasingDirection)
	local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, direction), { CFrame = target })
	tween:Play()
	task.wait(duration)
end

function Deliveries.deliver(session: Session)
	local player = session.Player
	local data = PlayerData.get(player)
	if not data or not session.Alive then
		return
	end
	local wanted = Upgrades.boxesPerDelivery(data.Upgrades.DeliverySize)
	if #Boxes.freeSpots(session) == 0 then
		Net.notify(player, "Info", "📦 Loading bay full! Grab your boxes")
		return
	end

	-- Road surface is slightly lower than the plot surface.
	local roadY = 0.2 - WorldBuilder.PlotY
	local stop = StoreLevels.TruckStop
	local stopLocal = CFrame.lookAt(stop, stop + Vector3.new(1, 0, 0)) * CFrame.new(0, roadY + TruckBuilder.RideHeight, 0)
	local stopCFrame = session.PlotCFrame * stopLocal

	local truck = TruckBuilder.build(session.Accent)
	truck.Root.CFrame = stopCFrame * CFrame.new(0, 0, DRIVE_DISTANCE)
	truck.Model.Parent = session.PlotModel
	tweenTo(truck.Root, stopCFrame, Config.TruckTravelTime, Enum.EasingDirection.Out)
	if not session.Alive then
		truck.Model:Destroy()
		return
	end

	data.Stats.Deliveries += 1
	Net.notify(player, "Delivery", "🚚 DELIVERY ARRIVED!")
	Net.effectTo(player, "Delivery", { Position = stopCFrame.Position })

	local free = Boxes.freeSpots(session)
	for index = 1, math.min(wanted, #free) do
		if not session.Alive then
			break
		end
		-- Out of the side door facing the plot.
		Boxes.spawn(session, free[index], stopCFrame * CFrame.new(3.4, 2.5, 1 - index * 0.4))
		task.wait(0.22)
	end

	task.wait(0.9)
	tweenTo(truck.Root, stopCFrame * CFrame.new(0, 0, -DRIVE_DISTANCE), Config.TruckTravelTime, Enum.EasingDirection.In)
	truck.Model:Destroy()
end

function Deliveries.start(session: Session)
	local player = session.Player
	task.spawn(function()
		player:SetAttribute("NextDeliveryAt", workspace:GetServerTimeNow() + Config.FirstDeliveryDelay)
		task.wait(Config.FirstDeliveryDelay)
		while session.Alive do
			local interval = rng:NextNumber(Config.DeliveryIntervalMin, Config.DeliveryIntervalMax)
			player:SetAttribute("NextDeliveryAt", workspace:GetServerTimeNow() + interval)
			task.spawn(function()
				local ok, err = pcall(function()
					Deliveries.deliver(session)
				end)
				if not ok then
					warn("[FillTheStore] Delivery failed: " .. tostring(err))
				end
			end)
			task.wait(interval)
		end
	end)
end

return Deliveries
