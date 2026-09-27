--!strict
-- Central tuning values for Fill the Store!
-- Most balancing can be done from this file without touching any systems.

local Config = {
	Currency = "£",

	StartingCash = 25,

	-- World / plots -------------------------------------------------------
	PlotCount = 6, -- 3 plots each side of the main road
	PlotWidth = 90, -- studs along the road (plot local X)
	PlotDepth = 80, -- studs away from the road (plot local Z)
	PlotSpacing = 110, -- distance between plot centres along the road
	RoadWidth = 36,
	SidewalkWidth = 6,

	-- Deliveries ------------------------------------------------------------
	FirstDeliveryDelay = 4, -- a new player sees their first truck almost straight away
	DeliveryIntervalMin = 20,
	DeliveryIntervalMax = 28,
	MaxBoxesOnPad = 12, -- deliveries skip boxes when the loading bay is full
	TruckTravelTime = 2.6,

	-- Customers -------------------------------------------------------------
	CustomerWalkSpeed = 14,
	CustomerBrowseTime = 0.7, -- seconds spent "choosing" at a shelf
	CheckoutTime = 0.8, -- seconds spent paying at the till
	CustomerMaxLifetime = 150, -- safety net: stuck customers are cleaned up after this

	-- Stocking --------------------------------------------------------------
	StockItemDelay = 0.055, -- delay between each product popping onto a shelf
	WorkerStockDelay = 0.5,
	WorkerItemsPerTrip = 6,
	WorkerWalkSpeed = 9,

	-- Saving ----------------------------------------------------------------
	DataStoreName = "FillTheStore_PlayerData_v1",
	AutosaveInterval = 60,
	LoadRetries = 3,

	-- Onboarding ------------------------------------------------------------
	-- The guide arrow/beam is shown until the player has sold this many items.
	GuideItemsSoldThreshold = 60,
}

return Config
