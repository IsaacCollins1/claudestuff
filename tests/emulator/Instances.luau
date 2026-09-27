--!nocheck
-- A small pure-Luau emulation of Roblox Instances for headless play-testing.
--
-- * Every property read/write is validated against Roblox's reflection
--   database (via Lune), so typos and wrong value types raise errors just
--   like they would in Studio.
-- * Hierarchy events (ChildAdded, AncestryChanged, CollectionService tags...)
--   fire like the real engine.
-- * "Physics-lite": parts joined by welds/motors move together when a part's
--   CFrame is set, Humanoid:MoveTo walks characters over time, and
--   unanchored parts that aren't attached to anything are reported (they
--   would fall through the world in the real game).

local roblox = require("@lune/roblox")
local Scheduler = require("./Scheduler")
local Signal = require("./Signal")

local db = roblox.getReflectionDatabase()
local CFrame = require("./Datatypes").CFrame
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local Color3 = roblox.Color3
local UDim = roblox.UDim
local UDim2 = roblox.UDim2
local NumberRange = roblox.NumberRange

local Instances = {}

local NIL = table.freeze({})
Instances.NIL = NIL

local states = setmetatable({}, { __mode = "k" })
local InstanceMeta = {}
Instances.states = states

local dataModel = nil
local jointsByPart = setmetatable({}, { __mode = "k" })
local tagAdded: { [string]: any } = {}
local tagRemoved: { [string]: any } = {}
local movingHumanoids = {}
Instances.created = 0

function Instances.isInstance(value: any): boolean
	return type(value) == "table" and states[value] ~= nil
end
local isInstance = Instances.isInstance

-- Class metadata ----------------------------------------------------------------

local classCache = {}

local function getClass(className: string)
	local cached = classCache[className]
	if cached then
		return cached
	end
	local class = db:GetClass(className)
	if not class then
		return nil
	end
	local info = { Name = className, Chain = {}, IsA = {}, Props = {}, Defaults = {}, Tags = {} }
	for _, tag in class.Tags do
		info.Tags[tag] = true
	end
	local current = class
	while current do
		table.insert(info.Chain, current.Name)
		info.IsA[current.Name] = true
		for name, prop in current.Properties do
			if info.Props[name] == nil then
				info.Props[name] = prop
			end
		end
		for name, value in current.DefaultProperties do
			if info.Defaults[name] == nil then
				info.Defaults[name] = value
			end
		end
		current = if current.Superclass then db:GetClass(current.Superclass) else nil
	end
	classCache[className] = info
	return info
end
Instances.getClass = getClass

local methods: { [string]: { [string]: any } } = {}
local events: { [string]: { [string]: boolean } } = {}
local getters: { [string]: { [string]: any } } = {}
local setters: { [string]: { [string]: any } } = {}
local callbacks: { [string]: { [string]: boolean } } = {}

local function register(tbl, className, name, value)
	tbl[className] = tbl[className] or {}
	tbl[className][name] = value
end

function Instances.method(className: string, name: string, fn)
	register(methods, className, name, fn)
end
function Instances.getter(className: string, name: string, fn)
	register(getters, className, name, fn)
end
function Instances.setter(className: string, name: string, fn)
	register(setters, className, name, fn)
end
function Instances.events(className: string, names: { string })
	for _, name in names do
		register(events, className, name, true)
	end
end
function Instances.callbacks(className: string, names: { string })
	for _, name in names do
		register(callbacks, className, name, true)
	end
end

local function lookup(tbl, info, name)
	for _, className in info.Chain do
		local entries = tbl[className]
		if entries and entries[name] ~= nil then
			return entries[name]
		end
	end
	return nil
end

-- Defaults when the reflection database doesn't provide one.
local NAME_DEFAULTS = {
	Health = 100,
	MaxHealth = 100,
	Visible = true,
	Enabled = true,
	Archivable = true,
	WalkSpeed = 16,
	Transparency = 0,
	Size = Vector3.new(4, 1, 2),
	CFrame = CFrame.new(),
	Color = Color3.fromRGB(163, 162, 165),
	BackgroundTransparency = 0,
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	AnchorPoint = Vector2.new(0, 0),
	TextTransparency = 0,
	Anchored = false,
	CanCollide = true,
	CanQuery = true,
	CanTouch = true,
	Massless = false,
	CastShadow = true,
	CollisionGroup = "Default",
	IgnoreGuiInset = false,
	Looped = false,
	Material = roblox.Enum.Material.Plastic,
	Font = roblox.Enum.Font.Legacy,
}

local function datatypeDefault(datatype: string): any
	if datatype == "Bool" then
		return false
	elseif datatype == "Float32" or datatype == "Float64" or datatype == "Int32" or datatype == "Int64" then
		return 0
	elseif datatype == "String" or datatype == "Content" or datatype == "BinaryString" then
		return ""
	elseif datatype == "Vector3" then
		return Vector3.zero
	elseif datatype == "Vector2" then
		return Vector2.zero
	elseif datatype == "CFrame" then
		return CFrame.new()
	elseif datatype == "Color3" then
		return Color3.new(1, 1, 1)
	elseif datatype == "UDim2" then
		return UDim2.new()
	elseif datatype == "UDim" then
		return UDim.new()
	elseif datatype == "NumberRange" then
		return NumberRange.new(0)
	end
	return nil
end

-- Value type checking against the reflection database's datatype names.
local function typeMatches(datatype: string, value: any): boolean
	if datatype == "Ref" then
		return value == nil or isInstance(value)
	elseif datatype == "OptionalCFrame" then
		return value == nil or typeof(value) == "CFrame"
	elseif value == nil then
		return false
	elseif datatype == "Bool" then
		return type(value) == "boolean"
	elseif datatype == "Float32" or datatype == "Float64" or datatype == "Int32" or datatype == "Int64" then
		return type(value) == "number"
	elseif datatype == "String" or datatype == "Content" or datatype == "BinaryString" or datatype == "SharedString" then
		return type(value) == "string"
	elseif datatype == "Color3uint8" then
		return typeof(value) == "Color3"
	elseif string.sub(datatype, 1, 5) == "Enum." then
		if typeof(value) ~= "EnumItem" then
			return false
		end
		return string.match(tostring(value.EnumType), "Enum%.([%w_]+)") == string.sub(datatype, 6)
	end
	return typeof(value) == datatype
end

-- Instance core -----------------------------------------------------------------

local function newState(info)
	return {
		class = info,
		className = info.Name,
		name = info.Name,
		parent = nil,
		children = {},
		props = {},
		attributes = {},
		attributeOrder = {},
		tags = {},
		signals = {},
		destroyed = false,
		inGame = false,
	}
end

function Instances.new(className: string, internal: boolean?)
	if type(className) ~= "string" then
		error("Instance.new expects a class name string", 2)
	end
	local info = getClass(className)
	if not info then
		error(string.format('Unable to create an Instance of type "%s"', className), 2)
	end
	if not internal and (info.Tags.NotCreatable or info.Tags.Service) then
		error(string.format('Unable to create an Instance of type "%s"', className), 2)
	end
	local proxy = setmetatable({}, InstanceMeta)
	states[proxy] = newState(info)
	Instances.created += 1
	return proxy
end

function Instances.setDataModel(dm)
	dataModel = dm
	states[dm].inGame = true
end

local function getSignal(proxy, name)
	local st = states[proxy]
	local signal = st.signals[name]
	if not signal then
		signal = Signal.new(name)
		st.signals[name] = signal
	end
	return signal
end
Instances.signal = getSignal

local function fire(proxy, name, ...)
	local signal = states[proxy].signals[name]
	if signal then
		signal:Fire(...)
	end
end
Instances.fire = fire

local function fullName(proxy): string
	local parts = {}
	local current = proxy
	while current and current ~= dataModel do
		table.insert(parts, 1, states[current].name)
		current = states[current].parent
	end
	return table.concat(parts, ".")
end
Instances.fullName = fullName

local function descendants(proxy, out)
	out = out or {}
	for _, child in states[proxy].children do
		table.insert(out, child)
		descendants(child, out)
	end
	return out
end
Instances.descendants = descendants

local function isAncestorOf(ancestor, descendant): boolean
	local current = states[descendant].parent
	while current do
		if current == ancestor then
			return true
		end
		current = states[current].parent
	end
	return false
end

local function fireTag(tag, added, proxy)
	local signal = if added then tagAdded[tag] else tagRemoved[tag]
	if signal then
		signal:Fire(proxy)
	end
end

local function fireChanged(proxy, property)
	local st = states[proxy]
	local signal = st.signals["Changed"]
	if signal then
		signal:Fire(property)
	end
	local specific = st.signals["Prop:" .. property]
	if specific then
		specific:Fire()
	end
end
Instances.fireChanged = fireChanged

local function setParent(child, newParent)
	local st = states[child]
	if st.destroyed then
		error(string.format("The Parent property of %s is locked, current parent: NULL, new parent %s", st.name, if newParent then states[newParent].name else "NULL"), 3)
	end
	if newParent ~= nil and not isInstance(newParent) then
		error("Parent must be an Instance or nil (got " .. typeof(newParent) .. ")", 3)
	end
	if newParent == child or (newParent and isAncestorOf(child, newParent)) then
		error(string.format("Attempt to set parent of %s to %s would result in circular reference", fullName(child), fullName(newParent)), 3)
	end
	local oldParent = st.parent
	if oldParent == newParent then
		return
	end
	local wasInGame = st.inGame
	local subtree = { child }
	descendants(child, subtree)

	if oldParent then
		local oldState = states[oldParent]
		local index = table.find(oldState.children, child)
		if index then
			table.remove(oldState.children, index)
		end
		fire(oldParent, "ChildRemoved", child)
		local ancestor = oldParent
		while ancestor do
			if states[ancestor].signals["DescendantRemoving"] then
				for _, inst in subtree do
					fire(ancestor, "DescendantRemoving", inst)
				end
			end
			ancestor = states[ancestor].parent
		end
	end

	st.parent = newParent
	local nowInGame = newParent ~= nil and states[newParent].inGame
	for _, inst in subtree do
		states[inst].inGame = nowInGame
	end
	if newParent then
		table.insert(states[newParent].children, child)
		fire(newParent, "ChildAdded", child)
		local ancestor = newParent
		while ancestor do
			if states[ancestor].signals["DescendantAdded"] then
				for _, inst in subtree do
					fire(ancestor, "DescendantAdded", inst)
				end
			end
			ancestor = states[ancestor].parent
		end
	end
	for _, inst in subtree do
		fire(inst, "AncestryChanged", child, newParent)
	end
	fireChanged(child, "Parent")

	if nowInGame ~= wasInGame then
		for _, inst in subtree do
			for tag in states[inst].tags do
				fireTag(tag, nowInGame, inst)
			end
		end
	end
end
Instances.setParent = setParent

local function destroy(proxy)
	local st = states[proxy]
	if st.destroyed then
		return
	end
	fire(proxy, "Destroying")
	for _, child in table.clone(st.children) do
		destroy(child)
	end
	if st.parent then
		setParent(proxy, nil)
	end
	st.destroyed = true
	movingHumanoids[proxy] = nil
	-- Let queued Destroying/Removed handlers run, then drop connections.
	Scheduler.defer(function()
		for _, signal in st.signals do
			signal:DisconnectAll()
		end
	end)
end
Instances.destroy = destroy

-- Joints / assemblies -------------------------------------------------------------

local function isJoint(proxy): boolean
	local info = states[proxy].class
	return info.IsA.WeldConstraint or info.IsA.JointInstance
end

local function trackJoint(joint, oldPart, newPart)
	if oldPart and oldPart ~= NIL and jointsByPart[oldPart] then
		jointsByPart[oldPart][joint] = nil
	end
	if newPart and newPart ~= NIL then
		jointsByPart[newPart] = jointsByPart[newPart] or setmetatable({}, { __mode = "k" })
		jointsByPart[newPart][joint] = true
	end
end

local function jointActive(joint): boolean
	local st = states[joint]
	if st.destroyed or st.parent == nil then
		return false
	end
	local enabled = st.props.Enabled
	return enabled ~= false
end

local function connectedParts(part)
	local visited = { [part] = true }
	local queue = { part }
	local result = {}
	while #queue > 0 do
		local current = table.remove(queue)
		local joints = jointsByPart[current]
		if joints then
			for joint in joints do
				if jointActive(joint) then
					local jst = states[joint]
					local other = if jst.props.Part0 == current then jst.props.Part1 else jst.props.Part0
					if other and other ~= NIL and not visited[other] and not states[other].destroyed then
						visited[other] = true
						table.insert(queue, other)
						table.insert(result, other)
					end
				end
			end
		end
	end
	return result
end
Instances.connectedParts = connectedParts

local function rawCFrame(part)
	local value = states[part].props.CFrame
	return if value == nil or value == NIL then CFrame.new() else value
end
Instances.rawCFrame = rawCFrame

local function checkFinite(cf, proxy)
	local p = cf.Position
	if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z or math.abs(p.X) == math.huge or math.abs(p.Y) == math.huge then
		error("Invalid CFrame (NaN/inf) assigned to " .. fullName(proxy), 4)
	end
end

-- Set a part's CFrame and move everything welded to it.
local function setPartCFrame(part, cf, propagate)
	checkFinite(cf, part)
	local old = rawCFrame(part)
	states[part].props.CFrame = cf
	if propagate then
		local delta = cf * old:Inverse()
		for _, other in connectedParts(part) do
			states[other].props.CFrame = delta * rawCFrame(other)
		end
	end
end
Instances.setPartCFrame = setPartCFrame

-- Metatable -----------------------------------------------------------------------

InstanceMeta.__index = function(self, key)
	local st = states[self]
	if st == nil then
		error("attempt to index a non-instance", 2)
	end
	local method = lookup(methods, st.class, key)
	if method then
		return method
	end
	if key == "Parent" then
		return st.parent
	elseif key == "Name" then
		return st.name
	elseif key == "ClassName" then
		return st.className
	end
	if lookup(events, st.class, key) then
		return getSignal(self, key)
	end
	local getter = lookup(getters, st.class, key)
	if getter then
		return getter(self, st)
	end
	local stored = st.props[key]
	if stored ~= nil then
		return if stored == NIL then nil else stored
	end
	local prop = st.class.Props[key]
	if prop and prop.Scriptability ~= "None" then
		local default = st.class.Defaults[key]
		if default == nil then
			default = NAME_DEFAULTS[key]
		end
		if default == nil then
			default = datatypeDefault(prop.Datatype)
		end
		return default
	end
	if lookup(callbacks, st.class, key) then
		return nil
	end
	for _, child in st.children do
		if states[child].name == key then
			return child
		end
	end
	error(string.format('%s is not a valid member of %s "%s"', tostring(key), st.className, fullName(self)), 2)
end

InstanceMeta.__newindex = function(self, key, value)
	local st = states[self]
	if key == "Parent" then
		setParent(self, value)
		return
	elseif key == "Name" then
		if type(value) ~= "string" and type(value) ~= "number" then
			error("Name must be a string", 2)
		end
		st.name = tostring(value)
		fireChanged(self, "Name")
		return
	end
	if lookup(callbacks, st.class, key) then
		if value ~= nil and type(value) ~= "function" then
			error(key .. " must be a function", 2)
		end
		st.props[key] = if value == nil then NIL else value
		return
	end
	local setter = lookup(setters, st.class, key)
	if setter then
		setter(self, st, value)
		fireChanged(self, key)
		return
	end
	local prop = st.class.Props[key]
	if not prop or prop.Scriptability == "None" then
		error(string.format('%s is not a valid member of %s "%s"', tostring(key), st.className, fullName(self)), 2)
	end
	if prop.Scriptability == "Read" then
		error(string.format("Unable to assign property %s. Property is read only", key), 2)
	end
	if not typeMatches(prop.Datatype, value) then
		error(string.format("Unable to assign property %s of %s. %s expected, got %s", key, st.className, prop.Datatype, typeof(value)), 2)
	end
	local old = st.props[key]
	st.props[key] = if value == nil then NIL else value
	if prop.Datatype == "Ref" and (key == "Part0" or key == "Part1") and isJoint(self) then
		trackJoint(self, old, value)
	end
	fireChanged(self, key)
end

InstanceMeta.__tostring = function(self)
	return states[self].name
end

-- Internal property set that skips read-only checks (harness use).
function Instances.setInternal(proxy, key, value)
	states[proxy].props[key] = if value == nil then NIL else value
	fireChanged(proxy, key)
end

-- Generic Instance API ---------------------------------------------------------------

local function findChild(self, predicate, recursive)
	for _, child in states[self].children do
		if predicate(child) then
			return child
		end
	end
	if recursive then
		for _, child in states[self].children do
			local found = findChild(child, predicate, true)
			if found then
				return found
			end
		end
	end
	return nil
end

Instances.events("Instance", { "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "Changed", "Destroying", "AttributeChanged" })

Instances.method("Instance", "FindFirstChild", function(self, name, recursive)
	return findChild(self, function(child)
		return states[child].name == name
	end, recursive)
end)
Instances.method("Instance", "FindFirstChildOfClass", function(self, className)
	return findChild(self, function(child)
		return states[child].className == className
	end, false)
end)
Instances.method("Instance", "FindFirstChildWhichIsA", function(self, className, recursive)
	return findChild(self, function(child)
		return states[child].class.IsA[className] == true
	end, recursive)
end)
local function findAncestor(self, predicate)
	local current = states[self].parent
	while current do
		if predicate(current) then
			return current
		end
		current = states[current].parent
	end
	return nil
end
Instances.method("Instance", "FindFirstAncestor", function(self, name)
	return findAncestor(self, function(a)
		return states[a].name == name
	end)
end)
Instances.method("Instance", "FindFirstAncestorOfClass", function(self, className)
	return findAncestor(self, function(a)
		return states[a].className == className
	end)
end)
Instances.method("Instance", "FindFirstAncestorWhichIsA", function(self, className)
	return findAncestor(self, function(a)
		return states[a].class.IsA[className] == true
	end)
end)
Instances.method("Instance", "WaitForChild", function(self, name, timeout)
	local start = Scheduler.now
	local warned = false
	while true do
		local child = self:FindFirstChild(name)
		if child then
			return child
		end
		if timeout and Scheduler.now - start >= timeout then
			return nil
		end
		if not warned and Scheduler.now - start > 5 then
			warned = true
			print(string.format('\27[33m[WARN]\27[0m Infinite yield possible on %s:WaitForChild("%s")', fullName(self), name))
			table.insert(Instances.warnings, "Infinite yield on " .. fullName(self) .. ":WaitForChild(" .. name .. ")")
		end
		Scheduler.wait(0)
	end
end)
Instances.warnings = {}
Instances.method("Instance", "GetChildren", function(self)
	return table.clone(states[self].children)
end)
Instances.method("Instance", "GetDescendants", function(self)
	return descendants(self)
end)
Instances.method("Instance", "IsA", function(self, className)
	return states[self].class.IsA[className] == true
end)
Instances.method("Instance", "IsDescendantOf", function(self, ancestor)
	return ancestor ~= nil and isAncestorOf(ancestor, self)
end)
Instances.method("Instance", "IsAncestorOf", function(self, descendant)
	return descendant ~= nil and isAncestorOf(self, descendant)
end)
Instances.method("Instance", "Destroy", function(self)
	destroy(self)
end)
Instances.method("Instance", "ClearAllChildren", function(self)
	for _, child in table.clone(states[self].children) do
		destroy(child)
	end
end)
Instances.method("Instance", "GetFullName", function(self)
	return fullName(self)
end)

local ATTRIBUTE_TYPES = {
	boolean = true, number = true, string = true, UDim = true, UDim2 = true, BrickColor = true, Color3 = true,
	Vector2 = true, Vector3 = true, CFrame = true, NumberSequence = true, ColorSequence = true,
	NumberRange = true, Rect = true, Font = true, EnumItem = true,
}
Instances.method("Instance", "SetAttribute", function(self, name, value)
	if type(name) ~= "string" or #name > 100 or not string.match(name, "^[%w_]+$") then
		error("Invalid attribute name: " .. tostring(name), 2)
	end
	if value ~= nil and not ATTRIBUTE_TYPES[typeof(value)] then
		error(string.format("Cannot set attribute %s: %s is not a supported attribute type", name, typeof(value)), 2)
	end
	if value ~= value then
		error("Attribute " .. name .. " cannot be NaN", 2)
	end
	local st = states[self]
	if st.attributes[name] == value then
		return
	end
	st.attributes[name] = value
	fire(self, "AttributeChanged", name)
	local signal = st.signals["Attr:" .. name]
	if signal then
		signal:Fire()
	end
end)
Instances.method("Instance", "GetAttribute", function(self, name)
	return states[self].attributes[name]
end)
Instances.method("Instance", "GetAttributes", function(self)
	return table.clone(states[self].attributes)
end)
Instances.method("Instance", "GetAttributeChangedSignal", function(self, name)
	return getSignal(self, "Attr:" .. name)
end)
Instances.method("Instance", "GetPropertyChangedSignal", function(self, name)
	local st = states[self]
	if not st.class.Props[name] and name ~= "Parent" and name ~= "Name" and not lookup(getters, st.class, name) then
		error(string.format("%s is not a valid property name.", tostring(name)), 2)
	end
	return getSignal(self, "Prop:" .. name)
end)
Instances.method("Instance", "AddTag", function(self, tag)
	local st = states[self]
	if not st.tags[tag] then
		st.tags[tag] = true
		if st.inGame then
			fireTag(tag, true, self)
		end
	end
end)
Instances.method("Instance", "RemoveTag", function(self, tag)
	local st = states[self]
	if st.tags[tag] then
		st.tags[tag] = nil
		if st.inGame then
			fireTag(tag, false, self)
		end
	end
end)
Instances.method("Instance", "HasTag", function(self, tag)
	return states[self].tags[tag] == true
end)
Instances.method("Instance", "GetTags", function(self)
	local tags = {}
	for tag in states[self].tags do
		table.insert(tags, tag)
	end
	return tags
end)

local function clone(self, map)
	local st = states[self]
	if st.props.Archivable == false then
		return nil
	end
	local copy = Instances.new(st.className, true)
	local cst = states[copy]
	cst.name = st.name
	map[self] = copy
	for key, value in st.props do
		cst.props[key] = value
	end
	for key, value in st.attributes do
		cst.attributes[key] = value
	end
	for tag in st.tags do
		cst.tags[tag] = true
	end
	cst.scale = st.scale
	for _, child in st.children do
		local childCopy = clone(child, map)
		if childCopy then
			setParent(childCopy, copy)
		end
	end
	return copy
end
Instances.method("Instance", "Clone", function(self)
	local map = {}
	local copy = clone(self, map)
	-- Remap references inside the cloned tree.
	for original, cloned in map do
		local cst = states[cloned]
		for key, value in cst.props do
			if isInstance(value) and map[value] then
				cst.props[key] = map[value]
			end
			if (key == "Part0" or key == "Part1") and isJoint(cloned) then
				trackJoint(cloned, nil, cst.props[key])
			end
		end
	end
	return copy
end)

-- BasePart / PVInstance / Model -------------------------------------------------------------

Instances.events("BasePart", { "Touched", "TouchEnded" })

Instances.getter("BasePart", "CFrame", function(self)
	return rawCFrame(self)
end)
Instances.setter("BasePart", "CFrame", function(self, _st, value)
	if typeof(value) ~= "CFrame" then
		error("CFrame expected, got " .. typeof(value), 3)
	end
	setPartCFrame(self, value, true)
end)
Instances.getter("BasePart", "Position", function(self)
	return rawCFrame(self).Position
end)
Instances.setter("BasePart", "Position", function(self, _st, value)
	if typeof(value) ~= "Vector3" then
		error("Vector3 expected, got " .. typeof(value), 3)
	end
	setPartCFrame(self, CFrame.new(value) * rawCFrame(self).Rotation, false)
end)
Instances.getter("BasePart", "Orientation", function(self)
	local rx, ry, rz = rawCFrame(self):ToOrientation()
	return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
end)
Instances.getter("BasePart", "AssemblyRootPart", function(self)
	return self
end)

local function pivotOf(model)
	local st = states[model]
	local primary = st.props.PrimaryPart
	if primary and primary ~= NIL and not states[primary].destroyed then
		return rawCFrame(primary) * primary.PivotOffset
	end
	local stored = st.props.WorldPivot
	if stored and stored ~= NIL then
		return stored
	end
	for _, d in descendants(model) do
		if states[d].class.IsA.BasePart then
			return CFrame.new(rawCFrame(d).Position)
		end
	end
	return CFrame.new()
end
Instances.pivotOf = pivotOf

Instances.getter("Model", "WorldPivot", function(self)
	return pivotOf(self)
end)
Instances.setter("Model", "WorldPivot", function(self, st, value)
	st.props.WorldPivot = value
end)

Instances.method("PVInstance", "GetPivot", function(self)
	local st = states[self]
	if st.class.IsA.BasePart then
		return rawCFrame(self) * self.PivotOffset
	end
	return pivotOf(self)
end)
Instances.method("PVInstance", "PivotTo", function(self, target)
	if typeof(target) ~= "CFrame" then
		error("PivotTo expects a CFrame, got " .. typeof(target), 2)
	end
	checkFinite(target, self)
	local st = states[self]
	if st.class.IsA.BasePart then
		setPartCFrame(self, target * self.PivotOffset:Inverse(), true)
		return
	end
	local current = pivotOf(self)
	local delta = target * current:Inverse()
	local moved = {}
	for _, d in descendants(self) do
		if states[d].class.IsA.BasePart then
			states[d].props.CFrame = delta * rawCFrame(d)
			moved[d] = true
		end
	end
	for part in table.clone(moved) do
		for _, other in connectedParts(part) do
			if not moved[other] then
				moved[other] = true
				states[other].props.CFrame = delta * rawCFrame(other)
			end
		end
	end
	local primary = st.props.PrimaryPart
	if not (primary and primary ~= NIL) then
		st.props.WorldPivot = delta * current
	end
end)
Instances.method("Model", "GetScale", function(self)
	return states[self].scale or 1
end)
Instances.method("Model", "ScaleTo", function(self, scale)
	if type(scale) ~= "number" or scale <= 0 then
		error("ScaleTo expects a positive number", 2)
	end
	local st = states[self]
	local factor = scale / (st.scale or 1)
	local pivot = pivotOf(self)
	for _, d in descendants(self) do
		local dst = states[d]
		if dst.class.IsA.BasePart then
			local relative = pivot:ToObjectSpace(rawCFrame(d))
			dst.props.CFrame = pivot * (CFrame.new(relative.Position * factor) * relative.Rotation)
			dst.props.Size = d.Size * factor
		end
	end
	st.scale = scale
end)
Instances.method("Model", "GetBoundingBox", function(self)
	local minV, maxV = nil, nil
	for _, d in descendants(self) do
		if states[d].class.IsA.BasePart then
			local cf = rawCFrame(d)
			local half = d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						minV = if minV then minV:Min(corner) else corner
						maxV = if maxV then maxV:Max(corner) else corner
					end
				end
			end
		end
	end
	if not minV then
		return CFrame.new(), Vector3.zero
	end
	return CFrame.new((minV + maxV) / 2), maxV - minV
end)
Instances.method("Model", "GetExtentsSize", function(self)
	local _, size = self:GetBoundingBox()
	return size
end)
Instances.method("BasePart", "SetNetworkOwner", function(self, player)
	local st = states[self]
	if not st.inGame then
		error("Can only call SetNetworkOwner on parts that are descendants of Workspace", 2)
	end
	if self.Anchored then
		error("Network Ownership API cannot be called on Anchored parts or parts welded to Anchored parts", 2)
	end
end)
Instances.method("BasePart", "GetNetworkOwner", function()
	return nil
end)

Instances.getter("Attachment", "WorldCFrame", function(self, st)
	local parent = st.parent
	local base = if parent and states[parent].class.IsA.BasePart then rawCFrame(parent) else CFrame.new()
	return base * self.CFrame
end)
Instances.getter("Attachment", "WorldPosition", function(self)
	return self.WorldCFrame.Position
end)
Instances.getter("Attachment", "Position", function(self)
	return self.CFrame.Position
end)
Instances.setter("Attachment", "Position", function(self, st, value)
	local current = st.props.CFrame
	local rotation = if current and current ~= NIL then current.Rotation else CFrame.new()
	st.props.CFrame = CFrame.new(value) * rotation
end)

-- Humanoids -------------------------------------------------------------------------------

Instances.events("Humanoid", { "Running", "Died", "MoveToFinished", "StateChanged", "HealthChanged", "Jumping" })

Instances.getter("Humanoid", "RootPart", function(self, st)
	local model = st.parent
	return model and model:FindFirstChild("HumanoidRootPart")
end)
Instances.setter("Humanoid", "Health", function(self, st, value)
	if type(value) ~= "number" then
		error("Health must be a number", 3)
	end
	local maxHealth = self.MaxHealth
	local clamped = math.clamp(value, 0, maxHealth)
	local wasAlive = (st.props.Health or 100) > 0
	st.props.Health = clamped
	fire(self, "HealthChanged", clamped)
	if wasAlive and clamped <= 0 then
		fire(self, "Died")
	end
end)
Instances.getter("Humanoid", "Health", function(self, st)
	return st.props.Health or 100
end)
Instances.method("Humanoid", "MoveTo", function(self, target, part)
	if typeof(target) ~= "Vector3" then
		error("MoveTo expects a Vector3", 2)
	end
	local st = states[self]
	st.moveTarget = target
	st.moveElapsed = 0
	movingHumanoids[self] = true
end)
Instances.method("Humanoid", "SetStateEnabled", function(self, state, enabled)
	assert(typeof(state) == "EnumItem" and type(enabled) == "boolean", "SetStateEnabled(HumanoidStateType, bool)")
end)
Instances.method("Humanoid", "GetStateEnabled", function()
	return true
end)
Instances.method("Humanoid", "ChangeState", function() end)
Instances.method("Humanoid", "TakeDamage", function(self, amount)
	self.Health -= amount
end)

-- Advance all walking humanoids (called every frame).
function Instances.stepHumanoids(dt: number)
	for humanoid in table.clone(movingHumanoids) do
		local st = states[humanoid]
		local model = st.parent
		local root = model and model:FindFirstChild("HumanoidRootPart")
		if st.destroyed or not root or not st.moveTarget then
			movingHumanoids[humanoid] = nil
			continue
		end
		local position = rawCFrame(root).Position
		local target = st.moveTarget
		local offset = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
		local distance = offset.Magnitude
		st.moveElapsed += dt
		if distance < 0.1 then
			movingHumanoids[humanoid] = nil
			st.moveTarget = nil
			st.running = false
			fire(humanoid, "Running", 0)
			fire(humanoid, "MoveToFinished", true)
		elseif st.moveElapsed > 8 then
			movingHumanoids[humanoid] = nil
			st.moveTarget = nil
			st.running = false
			fire(humanoid, "Running", 0)
			fire(humanoid, "MoveToFinished", false)
		else
			local speed = humanoid.WalkSpeed
			if not st.running then
				st.running = true
				fire(humanoid, "Running", speed)
			end
			local direction = offset.Unit
			local newPosition = position + direction * math.min(distance, speed * dt)
			setPartCFrame(root, CFrame.lookAt(newPosition, newPosition + direction), true)
		end
	end
end

-- Assembly sanity: unanchored parts that aren't attached to anything anchored
-- or to a character would fall out of the world in the real engine.
function Instances.findFallingParts(root)
	local falling = {}
	local checked = {}
	for _, d in descendants(root) do
		local st = states[d]
		if st.class.IsA.BasePart and not checked[d] then
			checked[d] = true
			if st.props.Anchored ~= true then
				local assembly = connectedParts(d)
				local supported = false
				for _, part in { d, table.unpack(assembly) } do
					checked[part] = true
					local pst = states[part]
					if pst.props.Anchored == true or pst.name == "HumanoidRootPart" then
						supported = true
					end
				end
				if not supported then
					table.insert(falling, fullName(d))
				end
			end
		end
	end
	return falling
end

-- CollectionService signals ----------------------------------------------------------

function Instances.tagSignal(tag: string, added: boolean)
	local tbl = if added then tagAdded else tagRemoved
	if not tbl[tag] then
		tbl[tag] = Signal.new("Tag:" .. tag)
	end
	return tbl[tag]
end

function Instances.tagged(tag: string)
	local result = {}
	if not dataModel then
		return result
	end
	for _, d in descendants(dataModel) do
		if states[d].tags[tag] then
			table.insert(result, d)
		end
	end
	return result
end

return Instances
