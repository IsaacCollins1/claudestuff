--!strict
-- Builds a player's shop for a given store level out of plain Parts:
-- floor, walls with windows and a door, sign, awning, checkout and shelves.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local StoreLevels = require(Shared.StoreLevels)

local NpcBuilder = require(script.Parent.NpcBuilder)

local StoreBuilder = {}

StoreBuilder.ShelfTag = "Shelf"

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

function StoreBuilder.build(plotCFrame: CFrame, level: number, accent: Color3, ownerName: string, ownerUserId: number, parent: Instance): Built
	local layout = StoreLevels.getLayout(level)
	local model = Instance.new("Model")
	model.Name = "Store"
	model:SetAttribute("OwnerUserId", ownerUserId)
	model:SetAttribute("Level", level)

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
	Build.part(walls, "TrimBack", Vector3.new(w + 2.6, 0.8, 1.6), at(0, trimY, backZ + t / 2), accent)
	Build.part(walls, "TrimFront", Vector3.new(w + 2.6, 0.8, 1.6), at(0, trimY, frontCenterZ), accent)
	Build.part(walls, "TrimLeft", Vector3.new(1.6, 0.8, d + 2.6), at(-halfW - t / 2, trimY, frontZ + d / 2), accent)
	Build.part(walls, "TrimRight", Vector3.new(1.6, 0.8, d + 2.6), at(halfW + t / 2, trimY, frontZ + d / 2), accent)
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

	-- Big sign on top of the front wall: "ISAAC'S STORE / Value: £1,250"
	local signCFrame = plotCFrame * layout.SignCFrame
	local signWidth = math.min(w - 4, 24)
	local signBack = Build.part(model, "SignBack", Vector3.new(signWidth + 0.8, 5.3, 0.6), signCFrame * CFrame.new(0, 0, 0.35), accent)
	signBack.CastShadow = false
	local sign = Build.part(model, "Sign", Vector3.new(signWidth, 4.5, 0.4), signCFrame, WHITE)
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.LightInfluence = 0
	signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	signGui.PixelsPerStud = 40
	signGui.Parent = sign
	local nameLabel = Build.textLabel(signGui, string.upper(ownerName) .. "'S STORE", darken(accent, 0.25))
	nameLabel.Name = "OwnerName"
	nameLabel.Size = UDim2.fromScale(0.94, 0.58)
	nameLabel.Position = UDim2.fromScale(0.03, 0.04)
	local valueLabel = Build.textLabel(signGui, "Value: £0", DARK)
	valueLabel.Name = "Value"
	valueLabel.Size = UDim2.fromScale(0.8, 0.32)
	valueLabel.Position = UDim2.fromScale(0.1, 0.62)

	-- Floating name above the shop so it can be read from far away.
	local nameBoard = Build.billboard(sign, UDim2.fromScale(20, 3), Vector3.new(0, 5.5, 0), 350)
	nameBoard.Name = "OwnerBillboard"
	local floating = Build.textLabel(nameBoard, "🏪 " .. ownerName, WHITE)
	Build.stroke(floating, darken(accent, 0.35), 3)

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
	local cashier = NpcBuilder.buildStatic(cashierCFrame, {
		Shirt = accent,
		Pants = DARK,
		Skin = Color3.fromRGB(255, 205, 160),
		Hat = WHITE,
	})
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

	-- Invisible volume used for "is the player inside the shop?" checks.
	local interior = Build.part(model, "Interior", layout.InteriorSize, plotCFrame * CFrame.new(layout.InteriorCenter), WHITE)
	interior.Transparency = 1
	Build.decor(interior)

	model.Parent = parent
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
