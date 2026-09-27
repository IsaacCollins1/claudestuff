--!strict
-- Small helpers for building things out of plain Parts.
-- Used by the server (stores, trucks, NPCs) and the client (effects).
-- Round shapes are built low-poly style in LowPoly.

local Build = {}

Build.Font = Enum.Font.FredokaOne
Build.White = Color3.fromRGB(255, 255, 255)
Build.Dark = Color3.fromRGB(35, 38, 48)

function Build.part(
	parent: Instance?,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Wedge: the slope runs from the bottom front (-Z) up to the top back (+Z).
function Build.wedge(parent: Instance?, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): WedgePart
	local part = Instance.new("WedgePart")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Purely visual: players and NPCs walk through it, raycasts ignore it.
function Build.decor(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

-- Weld every BasePart in `model` to `root` so the whole thing moves when `root` moves.
function Build.weldAll(model: Instance, root: BasePart)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = descendant
			weld.Parent = descendant
			descendant.Anchored = false
		end
	end
end

function Build.textLabel(parent: Instance?, text: string, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Build.Font
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color or Build.White
	label.Parent = parent
	return label
end

function Build.stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

function Build.corner(parent: Instance, radius: UDim?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, 12)
	corner.Parent = parent
	return corner
end

-- A SurfaceGui with one big line of text on a face of `part`.
function Build.surfaceText(part: BasePart, face: Enum.NormalId, text: string, color: Color3?): (SurfaceGui, TextLabel)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text" .. face.Name
	gui.Face = face
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = part
	local label = Build.textLabel(gui, text, color)
	Build.stroke(label, Build.Dark, 3)
	return gui, label
end

function Build.billboard(parent: Instance, size: UDim2, offset: Vector3, maxDistance: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = parent
	return gui
end

return Build
