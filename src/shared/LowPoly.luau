--!strict
-- Low-poly shapes made from ordinary Parts, for a faceted, flat-shaded look:
--
--   hexPrism   six-sided "cylinder" (3 overlapping blocks) — trunks, poles, cans, wheels
--   triangle   any 3D triangle (2 thin WedgeParts, the classic part-triangle trick)
--   solid      a closed faceted shape from vertices + triangle faces
--   gem        jittered icosahedron / octahedron — foliage, bushes, rounded bits
--   pyramid    n-sided pyramid — pine tree tiers, parasols
--   bevelBox   box with chamfered top edges — hedges
--   diamond    a single block turned on its corner — tiny round things (bulbs, berries)
--
-- Roblox lights every facet separately, which gives the flat-shaded low-poly look.

local Build = require(script.Parent.Build)

local LowPoly = {}

LowPoly.FacetThickness = 0.08

-- Six-sided prism standing along cframe's Y axis. `width` is measured across the corners.
function LowPoly.hexPrism(
	parent: Instance?,
	name: string,
	height: number,
	width: number,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): { BasePart }
	local radius = width / 2
	local apothem = radius * math.sqrt(3) / 2
	local parts: { BasePart } = {}
	for index = 0, 2 do
		local part = Build.part(parent, name, Vector3.new(radius, height, apothem * 2), cframe * CFrame.Angles(0, math.rad(60 * index), 0), color, material)
		table.insert(parts, part)
	end
	return parts
end

-- Six-sided prism lying along cframe's X axis (wheels, rolls on their side).
function LowPoly.sideHexPrism(
	parent: Instance?,
	name: string,
	length: number,
	width: number,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): { BasePart }
	return LowPoly.hexPrism(parent, name, length, width, cframe * CFrame.Angles(0, 0, math.pi / 2), color, material)
end

-- A block balanced on its corner: reads as a little faceted gem.
function LowPoly.diamond(parent: Instance?, name: string, size: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	return Build.part(parent, name, Vector3.new(size, size, size) * 0.72, cframe * CFrame.Angles(math.rad(45), 0, math.rad(35.26)), color, material)
end

-- Triangle a-b-c made of two thin wedges. If `inside` is given, the facet is
-- nudged towards it so its outer face sits exactly on the triangle.
function LowPoly.triangle(
	parent: Instance?,
	name: string,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	color: Color3,
	inside: Vector3?,
	material: Enum.Material?
): { BasePart }
	-- Make bc the longest edge, so the foot of the height from `a` lands on it.
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local normal = ac:Cross(ab)
	if normal.Magnitude < 1e-6 then
		return {} -- degenerate (flat) triangle
	end
	local right = normal.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local thickness = LowPoly.FacetThickness
	local offset = Vector3.zero
	if inside then
		offset = (if (inside - a):Dot(right) > 0 then right else -right) * (thickness / 2)
	end
	local first = Build.wedge(
		parent,
		name,
		Vector3.new(thickness, height, math.abs(ab:Dot(back))),
		CFrame.fromMatrix((a + b) / 2 + offset, right, up, back),
		color,
		material
	)
	local second = Build.wedge(
		parent,
		name,
		Vector3.new(thickness, height, math.abs(ac:Dot(back))),
		CFrame.fromMatrix((a + c) / 2 + offset, -right, up, -back),
		color,
		material
	)
	return { first, second }
end

-- A closed faceted shape. `vertices` are in cframe's local space; each face is
-- three vertex indices. `faceColors` (optional) cycles colours face by face.
function LowPoly.solid(
	parent: Instance?,
	name: string,
	vertices: { Vector3 },
	faces: { { number } },
	cframe: CFrame,
	color: Color3,
	faceColors: { Color3 }?,
	material: Enum.Material?
): { BasePart }
	local world = {}
	local center = Vector3.zero
	for index, vertex in vertices do
		world[index] = cframe:PointToWorldSpace(vertex)
		center += world[index]
	end
	center /= #vertices
	local parts: { BasePart } = {}
	for index, face in faces do
		local faceColor = if faceColors then faceColors[(index - 1) % #faceColors + 1] else color
		for _, part in LowPoly.triangle(parent, name, world[face[1]], world[face[2]], world[face[3]], faceColor, center, material) do
			table.insert(parts, part)
		end
	end
	return parts
end

-- Faces of a convex point set whose edges all have length `edge`.
local function facesWithEdge(vertices: { Vector3 }, edge: number): { { number } }
	local faces = {}
	local function isEdge(i: number, j: number): boolean
		return math.abs((vertices[i] - vertices[j]).Magnitude - edge) < 1e-3
	end
	for i = 1, #vertices do
		for j = i + 1, #vertices do
			for k = j + 1, #vertices do
				if isEdge(i, j) and isEdge(j, k) and isEdge(i, k) then
					table.insert(faces, { i, j, k })
				end
			end
		end
	end
	return faces
end

local ICOSAHEDRON: { Vector3 } = {}
local ICOSAHEDRON_FACES: { { number } }
do
	local phi = (1 + math.sqrt(5)) / 2
	for _, s1 in { -1, 1 } do
		for _, s2 in { -1, 1 } do
			table.insert(ICOSAHEDRON, Vector3.new(0, s1, s2 * phi))
			table.insert(ICOSAHEDRON, Vector3.new(s1, s2 * phi, 0))
			table.insert(ICOSAHEDRON, Vector3.new(s2 * phi, 0, s1))
		end
	end
	ICOSAHEDRON_FACES = facesWithEdge(ICOSAHEDRON, 2)
	local radius = ICOSAHEDRON[1].Magnitude
	for index, vertex in ICOSAHEDRON do
		ICOSAHEDRON[index] = vertex / radius
	end
end

local OCTAHEDRON: { Vector3 } = {
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 1, 0),
	Vector3.new(0, -1, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
}
local OCTAHEDRON_FACES = facesWithEdge(OCTAHEDRON, math.sqrt(2))

-- A lumpy faceted blob filling roughly `size`: an icosahedron (20 facets), or
-- an octahedron (8 facets) when `simple` is true. `seed` varies the lumps and
-- shades so no two look the same.
function LowPoly.gem(
	parent: Instance?,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	seed: number,
	simple: boolean?,
	material: Enum.Material?
): { BasePart }
	local rng = Random.new(seed)
	local base: { Vector3 } = if simple then OCTAHEDRON else ICOSAHEDRON
	local faces: { { number } } = if simple then OCTAHEDRON_FACES else ICOSAHEDRON_FACES
	local half = size / 2
	local vertices = {}
	for index, vertex in base do
		local lump = rng:NextNumber(0.86, 1.1)
		vertices[index] = Vector3.new(vertex.X * half.X, vertex.Y * half.Y, vertex.Z * half.Z) * lump
	end
	-- Slightly different shades per facet, for that hand-painted low-poly look.
	local shades = {}
	for index = 1, #faces do
		local amount = rng:NextNumber(-0.08, 0.08)
		shades[index] = if amount > 0 then color:Lerp(Color3.new(1, 1, 1), amount) else color:Lerp(Color3.new(0, 0, 0), -amount)
	end
	-- Turn it randomly so lumps don't line up between neighbours.
	local turned = cframe * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	return LowPoly.solid(parent, name, vertices, faces, turned, color, shades, material)
end

-- n-sided pyramid standing on cframe (base at cframe.Y, apex `height` above).
-- `width` is across the corners. `faceColors` can stripe it (parasols).
function LowPoly.pyramid(
	parent: Instance?,
	name: string,
	sides: number,
	width: number,
	height: number,
	cframe: CFrame,
	color: Color3,
	faceColors: { Color3 }?,
	withBase: boolean?,
	material: Enum.Material?
): { BasePart }
	local radius = width / 2
	local vertices = { Vector3.new(0, height, 0) }
	local faces = {}
	for index = 0, sides - 1 do
		local angle = index / sides * math.pi * 2
		table.insert(vertices, Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
		table.insert(faces, { 1, 2 + index, 2 + (index + 1) % sides })
	end
	local parts: { BasePart } = {}
	-- (The centre point used to push facets inwards sits inside the pyramid.)
	local facets = LowPoly.solid(parent, name, vertices, faces, cframe, color, faceColors, material)
	for _, part in facets do
		table.insert(parts, part)
	end
	if withBase then
		local bottom = Vector3.new(0, 0, 0)
		for index = 0, sides - 1 do
			local a = cframe:PointToWorldSpace(vertices[2 + index])
			local b = cframe:PointToWorldSpace(vertices[2 + (index + 1) % sides])
			for _, part in LowPoly.triangle(parent, name, cframe:PointToWorldSpace(bottom), a, b, color, cframe:PointToWorldSpace(Vector3.new(0, height / 3, 0)), material) do
				table.insert(parts, part)
			end
		end
	end
	return parts
end

-- Box with its two long top edges chamfered (runs along X).
function LowPoly.bevelBox(parent: Instance?, name: string, size: Vector3, cframe: CFrame, color: Color3, bevel: number, material: Enum.Material?): { BasePart }
	local parts: { BasePart } = {}
	local bodyHeight = size.Y - bevel
	table.insert(parts, Build.part(parent, name, Vector3.new(size.X, bodyHeight, size.Z), cframe * CFrame.new(0, -bevel / 2, 0), color, material))
	local topY = size.Y / 2 - bevel / 2
	table.insert(parts, Build.part(parent, name, Vector3.new(size.X, bevel, size.Z - bevel * 2), cframe * CFrame.new(0, topY, 0), color, material))
	for _, side in { -1, 1 } do
		-- Wedge slopes fall towards their local -Z, so turn the back one round.
		local turn = if side < 0 then CFrame.new() else CFrame.Angles(0, math.pi, 0)
		local wedgeCFrame = cframe * CFrame.new(0, topY, side * (size.Z / 2 - bevel / 2)) * turn
		table.insert(parts, Build.wedge(parent, name, Vector3.new(size.X, bevel, bevel), wedgeCFrame, color:Lerp(Color3.new(1, 1, 1), 0.06), material))
	end
	return parts
end

-- Apply the same property to a list of parts (e.g. everything from hexPrism).
function LowPoly.each(parts: { BasePart }, apply: (part: BasePart) -> ())
	for _, part in parts do
		apply(part)
	end
end

return LowPoly
