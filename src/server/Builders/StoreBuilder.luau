--!strict
-- Builds a player's shop for a given store level out of plain Parts:
-- floor, walls with windows and a door, sign, awning, checkout and shelves.
-- VIP owners get a golden trim, a crown on the sign and a red carpet.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local StoreLevels = require(Shared.StoreLevels)

local NpcBuilder = require(script.Parent.NpcBuilder)
local PropBuilder = require(script.Parent.PropBuilder)

local StoreBuilder = {}

StoreBuilder.ShelfTag = "Shelf"
-- GUIs only the shop's owner should see (the client enables them).
StoreBuilder.OwnerOnlyTag = "OwnerOnlyGui"

export type BuiltShelf = {
	Model: Model,
	CFrame: CFrame,
	ItemsFolder: Folder,
	PromptAttachment: Attachment,
	BarFill: Frame,
	CountLabel: TextLabel,
}

export type Built = {
	Model: Model,
	Shelves: { BuiltShelf },
	Register: BasePart,
	SignName: TextLabel,
	SignValue: TextLabel,
	Interior: BasePart,
}

local WHITE = Color3.fromRGB(255, 255, 255)
local WALL = Color3.fromRGB(250, 246, 238)
local GLASS = Color3.fromRGB(170, 220, 255)
local DARK = Color3.fromRGB(45, 48, 60)
local GOLD = Color3.fromRGB(255, 196, 45)

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(WHITE, amount)
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local function buildShelf(parent: Instance, index: number, worldCFrame: CFrame, accent: Color3, ownerUserId: number): BuiltShelf
	local model = Instance.new("Model")
	model.Name = "Shelf" .. index
	model:SetAttribute("OwnerUserId", ownerUserId)
	model:SetAttribute("ShelfIndex", index)
	model:SetAttribute("Count", 0)
	model:SetAttribute("Capacity", 0)

	local length, depth, height = StoreLevels.ShelfLength, StoreLevels.ShelfDepth, StoreLevels.ShelfHeight
	local function at(x: number, y: number, z: number): CFrame
		return worldCFrame * CFrame.new(x, y, z)
	end

	local base = Build.part(model, "Base", Vector3.new(length, 0.5, depth), at(0, 0.25, 0), darken(accent, 0.15))
	Build.part(model, "Back", Vector3.new(length, height - 0.5, 0.2), at(0, 0.5 + (height - 0.5) / 2, depth / 2 - 0.1), lighten(accent, 0.75))
	Build.part(model, "SideL", Vector3.new(0.2, height, depth), at(-length / 2 + 0.1, height / 2, 0), WHITE)
	Build.part(model, "SideR", Vector3.new(0.2, height, depth), at(length / 2 - 0.1, height / 2, 0), WHITE)
	for tier, top in { 2.4, 4.3 } do
		Build.part(model, "Tier" .. tier, Vector3.new(length - 0.4, 0.15, depth - 0.2), at(0, top - 0.075, 0.05), WHITE)
	end
	Build.part(model, "Top", Vector3.new(length + 0.3, 0.3, depth + 0.2), at(0, height + 0.15, 0), accent)
	-- Coloured price strips along the front of each tier.
	for tier, top in { 0.5, 2.4, 4.3 } do
		local strip = Build.part(model, "Strip" .. tier, Vector3.new(length - 0.4, 0.2, 0.06), at(0, top - 0.12, -depth / 2 - 0.02), lighten(accent, 0.3))
		Build.decor(strip)
	end

	local items = Instance.new("Folder")
	items.Name = "Items"
	items.Parent = model

	local promptAttachment = Instance.new("Attachment")
	promptAttachment.Name = "PromptAttachment"
	promptAttachment.Position = Vector3.new(0, 2.3, -depth / 2 - 0.3)
	promptAttachment.Parent = base

	-- Stock bar above the shelf: shows at a glance which shelves need restocking.
	local barAttachment = Instance.new("Attachment")
	barAttachment.Name = "BarAttachment"
	barAttachment.Position = Vector3.new(0, height + 1.2, 0)
	barAttachment.Parent = base
	local billboard = Build.billboard(barAttachment, UDim2.fromScale(6.5, 1.8), Vector3.zero, 90)
	billboard.Name = "StockBar"
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 0.55)
	frame.Position = UDim2.fromScale(0, 0.45)
	frame.BackgroundColor3 = DARK
	frame.BackgroundTransparency = 0.15
	frame.Parent = billboard
	Build.corner(frame, UDim.new(0.5, 0))
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 100)
	fill.Parent = frame
	Build.corner(fill, UDim.new(0.5, 0))
	local label = Build.textLabel(billboard, "EMPTY")
	label.Name = "Count"
	label.Size = UDim2.fromScale(1, 0.5)
	Build.stroke(label, DARK, 2)

	CollectionService:AddTag(model, StoreBuilder.ShelfTag)
	model.Parent = parent

	return {
		Model = model,
		CFrame = worldCFrame,
		ItemsFolder = items,
		PromptAttachment = promptAttachment,
		BarFill = fill,
		CountLabel = label,
	}
end

function StoreBuilder.build(plotCFrame: CFrame, level: number, accent: Color3, ownerUserId: number, parent: Instance, vip: boolean?): Built
	local layout = StoreLevels.getLayout(level)
	local model = Instance.new("Model")
	model.Name = "Store"
	model:SetAttribute("OwnerUserId", ownerUserId)
	model:SetAttribute("Level", level)
	model:SetAttribute("Vip", vip == true)
	local trim = if vip then GOLD else accent

	local function at(x: number, y: number, z: number): CFrame
		return plotCFrame * CFrame.new(x, y, z)
	end

	local w, d = layout.Width, layout.Depth
	local halfW = w / 2
	local frontZ, backZ = layout.FrontZ, layout.BackZ
	local wallH = StoreLevels.WallHeight
	local floorY = StoreLevels.FloorY
	local doorW, doorH = StoreLevels.DoorWidth, StoreLevels.DoorHeight

	-- Floor: chunky checkerboard tiles.
	local floor = Instance.new("Model")
	floor.Name = "Floor"
	local columns = math.max(2, math.floor(w / 6 + 0.5))
	local rows = math.max(2, math.floor(d / 6 + 0.5))
	local tileW, tileD = w / columns, d / rows
	local tileA, tileB = Color3.fromRGB(250, 250, 252), lighten(accent, 0.72)
	for column = 0, columns - 1 do
		for row = 0, rows - 1 do
			local x = -halfW + tileW * (column + 0.5)
			local z = frontZ + tileD * (row + 0.5)
			Build.part(floor, "Tile", Vector3.new(tileW, floorY, tileD), at(x, floorY / 2, z), if (column + row) % 2 == 0 then tileA else tileB)
		end
	end
	floor.Parent = model

	-- Walls
	local walls = Instance.new("Model")
	walls.Name = "Walls"
	local t = StoreLevels.WallThickness
	Build.part(walls, "Back", Vector3.new(w + 2 * t, wallH, t), at(0, wallH / 2, backZ + t / 2), WALL)
	Build.part(walls, "Left", Vector3.new(t, wallH, d + 2 * t), at(-halfW - t / 2, wallH / 2, frontZ + d / 2), WALL)
	Build.part(walls, "Right", Vector3.new(t, wallH, d + 2 * t), at(halfW + t / 2, wallH / 2, frontZ + d / 2), WALL)

	-- Front wall: two segments with big shop windows either side of the door.
	local frontCenterZ = frontZ - t / 2
	for _, side in { -1, 1 } do
		local outer = halfW + t
		local inner = doorW / 2
		local segLength = outer - inner
		local centerX = side * (outer + inner) / 2
		Build.part(walls, "FrontLow", Vector3.new(segLength, 2.5, t), at(centerX, 1.25, frontCenterZ), WALL)
		Build.part(walls, "FrontHigh", Vector3.new(segLength, wallH - 7.5, t), at(centerX, 7.5 + (wallH - 7.5) / 2, frontCenterZ), WALL)
		Build.part(walls, "PillarOuter", Vector3.new(1.2, 5, t), at(side * (outer - 0.6), 5, frontCenterZ), WALL)
		Build.part(walls, "PillarInner", Vector3.new(1.2, 5, t), at(side * (inner + 0.6), 5, frontCenterZ), WALL)
		local glass = Build.part(walls, "Window", Vector3.new(segLength - 2.4, 5, 0.3), at(centerX, 5, frontCenterZ), GLASS, Enum.Material.Glass)
		glass.Transparency = 0.55
	end
	Build.part(walls, "DoorHeader", Vector3.new(doorW, wallH - doorH, t), at(0, doorH + (wallH - doorH) / 2, frontCenterZ), WALL)

	-- Accent trim along the top of every wall.
	local trimY = wallH + 0.4
	for _, part in {
		Build.part(walls, "TrimBack", Vector3.new(w + 2.6, 0.8, 1.6), at(0, trimY, backZ + t / 2), trim),
		Build.part(walls, "TrimFront", Vector3.new(w + 2.6, 0.8, 1.6), at(0, trimY, frontCenterZ), trim),
		Build.part(walls, "TrimLeft", Vector3.new(1.6, 0.8, d + 2.6), at(-halfW - t / 2, trimY, frontZ + d / 2), trim),
		Build.part(walls, "TrimRight", Vector3.new(1.6, 0.8, d + 2.6), at(halfW + t / 2, trimY, frontZ + d / 2), trim),
	} do
		part.Reflectance = if vip then 0.2 else 0
	end
	-- Corner posts and a skirting stripe give the walls some shape.
	-- (Flush with the inside of the walls, sticking out a little on the outside.)
	for _, sideX in { -1, 1 } do
		for _, corner in { { frontCenterZ, -1 }, { backZ + t / 2, 1 } } do
			local x = sideX * (halfW + t / 2 + 0.25)
			Build.part(walls, "CornerPost", Vector3.new(t + 0.5, wallH, t + 0.5), at(x, wallH / 2, corner[1] + corner[2] * 0.25), lighten(trim, 0.35))
		end
	end
	Build.decor(Build.part(walls, "SkirtBack", Vector3.new(w + 2 * t + 0.1, 1, t + 0.1), at(0, 0.5, backZ + t / 2), darken(accent, 0.1)))
	for _, side in { -1, 1 } do
		Build.decor(Build.part(walls, "Skirt", Vector3.new(t + 0.1, 1, d + 2 * t + 0.1), at(side * (halfW + t / 2), 0.5, frontZ + d / 2), darken(accent, 0.1)))
	end
	walls.Parent = model

	-- Striped awning above the windows.
	local awning = Instance.new("Model")
	awning.Name = "Awning"
	local stripeWidth = 2
	local stripes = math.floor((w + 2) / stripeWidth)
	local startX = -stripes * stripeWidth / 2
	for i = 0, stripes - 1 do
		local stripe = Build.part(
			awning,
			"Stripe",
			Vector3.new(stripeWidth, 0.25, 3),
			at(startX + stripeWidth * (i + 0.5), 8.3, frontZ - t - 1.35) * CFrame.Angles(math.rad(-20), 0, 0),
			if i % 2 == 0 then accent else WHITE
		)
		Build.decor(stripe)
	end
	awning.Parent = model

	-- Big sign on top of the front wall: "CORNER SHOP / Value: £1,250".
	-- (Player names are deliberately never shown on shops.)
	local signCFrame = plotCFrame * layout.SignCFrame
	local signWidth = math.min(w - 4, 24)
	local signBack = Build.part(model, "SignBack", Vector3.new(signWidth + 0.8, 5.3, 0.6), signCFrame * CFrame.new(0, 0, 0.35), trim)
	signBack.CastShadow = false
	signBack.Reflectance = if vip then 0.2 else 0
	-- Marquee light bulbs around the sign.
	local bulbs = Instance.new("Model")
	bulbs.Name = "SignLights"
	local bulbColors = { Color3.fromRGB(255, 244, 200), Color3.fromRGB(255, 215, 90) }
	local count = math.floor((signWidth + 0.4) / 1.3)
	for index = 0, count do
		local x = -signWidth / 2 - 0.2 + index * (signWidth + 0.4) / count
		for _, y in { -2.45, 2.45 } do
			local bulb = Build.ball(bulbs, "Bulb", 0.34, signCFrame * CFrame.new(x, y, -0.02), bulbColors[index % 2 + 1], Enum.Material.Neon)
			Build.decor(bulb)
			bulb.CastShadow = false
		end
	end
	for _, x in { -signWidth / 2 - 0.2, signWidth / 2 + 0.2 } do
		for y = -1.2, 1.21, 1.2 do
			local bulb = Build.ball(bulbs, "Bulb", 0.34, signCFrame * CFrame.new(x, y, -0.02), bulbColors[1], Enum.Material.Neon)
			Build.decor(bulb)
			bulb.CastShadow = false
		end
	end
	bulbs.Parent = model
	if vip then
		-- A golden crown on top of the sign.
		local crown = Instance.new("Model")
		crown.Name = "VipCrown"
		local crownBase = signCFrame * CFrame.new(0, 3.3, 0.35)
		Build.part(crown, "Band", Vector3.new(3.6, 0.8, 0.8), crownBase, GOLD)
		for _, x in { -1.4, 0, 1.4 } do
			local spike = Build.part(crown, "Spike", Vector3.new(0.8, 0.8, 0.5), crownBase * CFrame.new(x, 0.75, 0) * CFrame.Angles(0, 0, math.rad(45)), GOLD)
			spike.Reflectance = 0.3
			Build.ball(crown, "Gem", 0.45, crownBase * CFrame.new(x, 1.35, 0), Color3.fromRGB(255, 60, 90), Enum.Material.Neon)
		end
		for _, part in crown:GetDescendants() do
			if part:IsA("BasePart") then
				Build.decor(part)
				part.Reflectance = math.max(part.Reflectance, 0.2)
			end
		end
		crown.Parent = model
	end
	local sign = Build.part(model, "Sign", Vector3.new(signWidth, 4.5, 0.4), signCFrame, WHITE)
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.LightInfluence = 0
	signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	signGui.PixelsPerStud = 40
	signGui.Parent = sign
	local nameLabel = Build.textLabel(signGui, string.upper(layout.Spec.Name), darken(accent, 0.25))
	nameLabel.Name = "ShopName"
	nameLabel.Size = UDim2.fromScale(0.94, 0.58)
	nameLabel.Position = UDim2.fromScale(0.03, 0.04)
	local valueLabel = Build.textLabel(signGui, "Value: £0", DARK)
	valueLabel.Name = "Value"
	valueLabel.Size = UDim2.fromScale(0.8, 0.32)
	valueLabel.Position = UDim2.fromScale(0.1, 0.62)

	-- Floating "YOUR SHOP" marker so owners can spot their shop from far away.
	-- Only the owner's client turns it on.
	local marker = Build.billboard(sign, UDim2.fromScale(20, 3), Vector3.new(0, 5.5, 0), 350)
	marker.Name = "YourShopMarker"
	marker.Enabled = false
	marker:SetAttribute("OwnerUserId", ownerUserId)
	CollectionService:AddTag(marker, StoreBuilder.OwnerOnlyTag)
	local floating = Build.textLabel(marker, (if vip then "👑 " else "⭐ ") .. "YOUR SHOP", if vip then GOLD else WHITE)
	Build.stroke(floating, darken(trim, 0.45), 3)

	-- Inside: door mat, plants, "OPEN" sign.
	Build.decor(Build.part(model, "DoorMat", Vector3.new(doorW - 1, 0.05, 3), at(0, floorY + 0.025, frontZ + 1.6), darken(accent, 0.2)))
	for _, side in { -1, 1 } do
		local plantCFrame = at(side * (doorW / 2 + 1.6), floorY, frontZ + 1.3)
		local pot = Build.cylinder(model, "Pot", 1.4, 1.5, plantCFrame * CFrame.new(0, 0.7, 0), Color3.fromRGB(215, 120, 80))
		local leaves = Build.ball(model, "Plant", 2.4, plantCFrame * CFrame.new(0, 2.2, 0), Color3.fromRGB(80, 190, 90))
		Build.decor(pot)
		Build.decor(leaves)
	end
	local openSign = Build.part(model, "OpenSign", Vector3.new(3, 1.2, 0.1), at(halfW / 2 + 2, 6, frontZ + 0.1), Color3.fromRGB(255, 60, 80), Enum.Material.Neon)
	Build.decor(openSign)
	Build.surfaceText(openSign, Enum.NormalId.Front, "OPEN", WHITE)

	-- Outside the front windows: a gumball machine and an ice-cream freezer.
	local frontProps = Instance.new("Model")
	frontProps.Name = "FrontProps"
	PropBuilder.gumballMachine(frontProps, at(doorW / 2 + 2.8, 0, frontZ - 2.3), accent)
	PropBuilder.freezer(frontProps, at(-doorW / 2 - 3.6, 0, frontZ - 2.1))
	frontProps.Parent = model

	-- Checkout counter + till
	local counterCFrame = plotCFrame * layout.CounterCFrame
	local counterSize = StoreLevels.CounterSize
	local checkout = Instance.new("Model")
	checkout.Name = "Checkout"
	Build.part(checkout, "Counter", counterSize, counterCFrame * CFrame.new(0, counterSize.Y / 2, 0), accent)
	Build.part(checkout, "CounterTop", Vector3.new(counterSize.X + 0.4, 0.2, counterSize.Z + 0.4), counterCFrame * CFrame.new(0, counterSize.Y + 0.1, 0), WHITE)
	Build.part(checkout, "Belt", Vector3.new(1.2, 0.06, 4), counterCFrame * CFrame.new(0.3, counterSize.Y + 0.23, 1.1), DARK)
	local register = Build.part(checkout, "Register", Vector3.new(1.3, 0.7, 1.2), counterCFrame * CFrame.new(-0.2, counterSize.Y + 0.55, -2.2), Color3.fromRGB(70, 74, 88))
	local screen = Build.part(
		checkout,
		"Screen",
		Vector3.new(0.12, 0.75, 1),
		counterCFrame * CFrame.new(0.25, counterSize.Y + 1.25, -2.2) * CFrame.Angles(0, 0, math.rad(-15)),
		Color3.fromRGB(90, 255, 140),
		Enum.Material.Neon
	)
	Build.decor(screen)
	local checkoutBoard = Build.billboard(register, UDim2.fromScale(6, 1.4), Vector3.new(0, 4.2, 0), 90)
	checkoutBoard.Name = "CheckoutLabel"
	local checkoutLabel = Build.textLabel(checkoutBoard, "💷 CHECKOUT", WHITE)
	Build.stroke(checkoutLabel, darken(accent, 0.35), 2)
	checkout.Parent = model

	-- A friendly (decorative) cashier behind the till.
	local cashierCFrame = counterCFrame * CFrame.new(-counterSize.X / 2 - 1.3, 0, 0) * CFrame.Angles(0, math.rad(-90), 0)
	local cashier = NpcBuilder.buildStatic(cashierCFrame, NpcBuilder.StaffStyle)
	cashier.Name = "Cashier"
	cashier.Parent = model

	-- Shelves
	local shelvesFolder = Instance.new("Folder")
	shelvesFolder.Name = "Shelves"
	shelvesFolder.Parent = model
	local shelves = {}
	for index, localCFrame in layout.ShelfCFrames do
		shelves[index] = buildShelf(shelvesFolder, index, plotCFrame * localCFrame, accent, ownerUserId)
	end

	-- Path from the pavement to the door.
	local walkLength = frontZ + Config.PlotDepth / 2 -- from the plot's front edge to the door
	Build.decor(Build.part(model, "Path", Vector3.new(doorW, 0.1, walkLength), at(0, 0.05, frontZ - walkLength / 2), Color3.fromRGB(230, 226, 214)))
	if vip then
		-- Red carpet with gold edging and rope posts up to the door.
		local carpetLength = walkLength - 6
		local carpetCFrame = at(0, 0.12, frontZ - carpetLength / 2)
		Build.decor(Build.part(model, "RedCarpet", Vector3.new(doorW - 2, 0.05, carpetLength), carpetCFrame, Color3.fromRGB(200, 30, 50), Enum.Material.Fabric))
		for _, side in { -1, 1 } do
			Build.decor(Build.part(model, "CarpetEdge", Vector3.new(0.3, 0.06, carpetLength), carpetCFrame * CFrame.new(side * (doorW / 2 - 0.85), 0.01, 0), GOLD))
		end
		PropBuilder.stanchions(model, at(-doorW / 2 - 0.6, 0, frontZ - 14), 4, 3)
		PropBuilder.stanchions(model, at(doorW / 2 + 0.6, 0, frontZ - 5), 2, 3)
	end

	-- Invisible volume used for "is the player inside the shop?" checks.
	local interior = Build.part(model, "Interior", layout.InteriorSize, plotCFrame * CFrame.new(layout.InteriorCenter), WHITE)
	interior.Transparency = 1
	Build.decor(interior)

	model.Parent = parent
	NpcBuilder.playIdle(cashier)
	return {
		Model = model,
		Shelves = shelves,
		Register = register,
		SignName = nameLabel,
		SignValue = valueLabel,
		Interior = interior,
	}
end

return StoreBuilder
