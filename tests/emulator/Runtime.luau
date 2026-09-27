--!nocheck
-- Loads the built place file and runs its server + client scripts inside the
-- emulator, with a virtual clock, services, remotes and simulated players.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instances = require("./Instances")
local Scheduler = require("./Scheduler")
local Signal = require("./Signal")

local Enum = roblox.Enum
local CFrame = require("./Datatypes").CFrame
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2

local Runtime = {}
Runtime.__index = Runtime

local current = nil -- the active runtime (one at a time)
local EPOCH = 1_750_000_000

-- Datatypes the Roblox engine provides but Lune doesn't -----------------------------

local seedCounter = 0
local RandomMeta = {}
RandomMeta.__index = RandomMeta
local RandomLib = {}
function RandomLib.new(seed)
	seedCounter += 1
	local state = math.floor(seed or (seedCounter * 7919 + 12345)) % 2147483646 + 1
	return setmetatable({ _state = state }, RandomMeta)
end
function RandomMeta:_next()
	self._state = (self._state * 48271) % 2147483647
	return self._state / 2147483647
end
function RandomMeta:NextNumber(min, max)
	local r = self:_next()
	if min == nil then
		return r
	end
	return min + (max - min) * r
end
function RandomMeta:NextInteger(min, max)
	assert(type(min) == "number" and type(max) == "number", "NextInteger expects two numbers")
	assert(min <= max, "NextInteger: min > max")
	return math.min(max, min + math.floor(self:_next() * (max - min + 1)))
end

local TweenInfoLib = {}
function TweenInfoLib.new(time, style, direction, repeatCount, reverses, delayTime)
	return {
		__rbxType = "TweenInfo",
		Time = time or 1,
		EasingStyle = style or Enum.EasingStyle.Quad,
		EasingDirection = direction or Enum.EasingDirection.Out,
		RepeatCount = repeatCount or 0,
		Reverses = reverses or false,
		DelayTime = delayTime or 0,
	}
end

local luneTypeof = typeof
local function rbxTypeof(value)
	if Instances.isInstance(value) then
		return "Instance"
	end
	if type(value) == "table" then
		if getmetatable(value) == RandomMeta then
			return "Random"
		end
		if rawget(value, "__rbxType") then
			return value.__rbxType
		end
		if getmetatable(value) == Signal then
			return "RBXScriptSignal"
		end
	end
	return luneTypeof(value)
end

-- Values sent through remotes are copied like the real network does.
local function copyForNetwork(value, depth)
	depth = depth or 0
	if depth > 50 then
		error("Remote payload nested too deeply")
	end
	local kind = type(value)
	if kind == "function" or kind == "thread" then
		error("Cannot send " .. kind .. " through a remote")
	end
	if kind ~= "table" or Instances.isInstance(value) or rawget(value, "__rbxType") then
		return value
	end
	local copy = {}
	local hasString, hasNumber = false, false
	for key, item in value do
		local keyType = type(key)
		if keyType == "string" then
			hasString = true
		elseif keyType == "number" then
			hasNumber = true
		else
			error("Remote table keys must be strings or numbers, got " .. keyType)
		end
		copy[key] = copyForNetwork(item, depth + 1)
	end
	if hasString and hasNumber then
		error("Mixed tables (string + number keys) don't survive remotes")
	end
	return copy
end

local function copyArgs(...)
	local args = table.pack(...)
	for i = 1, args.n do
		args[i] = copyForNetwork(args[i])
	end
	return args
end

-- Service implementations -------------------------------------------------------------

local function registerApi()
	Instances.method("ServiceProvider", "GetService", function(self, name)
		local existing = self:FindFirstChildOfClass(name)
		if existing then
			return existing
		end
		local service = Instances.new(name, true)
		service.Name = name
		service.Parent = self
		return service
	end)
	Instances.method("ServiceProvider", "FindService", function(self, name)
		return self:FindFirstChildOfClass(name)
	end)
	Instances.method("DataModel", "BindToClose", function(_, callback)
		table.insert(current.closeCallbacks, callback)
	end)
	Instances.method("DataModel", "IsLoaded", function()
		return true
	end)
	Instances.getter("DataModel", "Workspace", function(self)
		return self:GetService("Workspace")
	end)

	Instances.method("Workspace", "GetServerTimeNow", function()
		return EPOCH + Scheduler.now
	end)

	Instances.events("Players", { "PlayerAdded", "PlayerRemoving" })
	Instances.method("Players", "GetPlayers", function(self)
		local list = {}
		for _, child in self:GetChildren() do
			if child:IsA("Player") then
				table.insert(list, child)
			end
		end
		return list
	end)
	Instances.method("Players", "GetPlayerFromCharacter", function(self, character)
		for _, player in self:GetPlayers() do
			if player.Character == character then
				return player
			end
		end
		return nil
	end)
	Instances.method("Players", "GetPlayerByUserId", function(self, userId)
		for _, player in self:GetPlayers() do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end)
	Instances.getter("Players", "LocalPlayer", function()
		return current.localPlayer
	end)

	Instances.events("Player", { "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "Chatted" })
	Instances.method("Player", "Kick", function(self)
		current:removePlayer(self)
	end)
	Instances.method("Player", "LoadCharacter", function(self)
		current:spawnCharacter(self)
	end)

	Instances.events("RunService", { "Heartbeat", "RenderStepped", "Stepped", "PreSimulation", "PostSimulation", "PreRender", "PreAnimation" })
	Instances.method("RunService", "IsServer", function()
		return true
	end)
	Instances.method("RunService", "IsClient", function()
		return true
	end)
	Instances.method("RunService", "IsStudio", function()
		return true
	end)
	Instances.method("RunService", "IsRunning", function()
		return true
	end)

	-- TweenService: interpolates over virtual time (linear easing is enough here).
	Instances.events("TweenBase", { "Completed" })
	Instances.method("TweenService", "Create", function(_, instance, info, goals)
		assert(Instances.isInstance(instance), "TweenService:Create expects an Instance")
		assert(type(info) == "table" and info.__rbxType == "TweenInfo", "TweenService:Create expects a TweenInfo")
		for key in goals do
			local ok, err = pcall(function()
				return instance[key]
			end)
			if not ok then
				error("TweenService:Create no property named '" .. tostring(key) .. "' for object '" .. instance.Name .. "': " .. tostring(err), 2)
			end
		end
		local tween = Instances.new("Tween", true)
		local st = Instances.states[tween]
		st.tweenTarget = instance
		st.tweenInfo = info
		st.tweenGoals = goals
		return tween
	end)
	Instances.method("TweenService", "GetValue", function(_, alpha)
		return alpha
	end)
	Instances.method("TweenBase", "Play", function(self)
		local st = Instances.states[self]
		st.tweenPlaying = (st.tweenPlaying or 0) + 1
		local token = st.tweenPlaying
		local target, info, goals = st.tweenTarget, st.tweenInfo, st.tweenGoals
		local starts = {}
		for key in goals do
			starts[key] = target[key]
		end
		Scheduler.spawn(function()
			local elapsed = 0
			while true do
				local dt = Scheduler.wait(0)
				if st.tweenPlaying ~= token or Instances.states[target].destroyed then
					return
				end
				elapsed += dt
				local alpha = math.min(elapsed / math.max(info.Time, 1e-6), 1)
				for key, goal in goals do
					local from = starts[key]
					local value
					if type(goal) == "number" then
						value = from + (goal - from) * alpha
					elseif alpha >= 1 then
						value = goal
					elseif type(from) == "userdata" and pcall(function()
						return from.Lerp
					end) and from.Lerp then
						value = from:Lerp(goal, alpha)
					else
						value = if alpha >= 1 then goal else from
					end
					target[key] = value
				end
				if alpha >= 1 then
					Instances.fire(self, "Completed", Enum.PlaybackState.Completed)
					return
				end
			end
		end)
	end)
	Instances.method("TweenBase", "Cancel", function(self)
		local st = Instances.states[self]
		st.tweenPlaying = (st.tweenPlaying or 0) + 1
		Instances.fire(self, "Completed", Enum.PlaybackState.Cancelled)
	end)
	Instances.method("TweenBase", "Pause", function(self)
		local st = Instances.states[self]
		st.tweenPlaying = (st.tweenPlaying or 0) + 1
	end)

	Instances.method("CollectionService", "GetTagged", function(_, tag)
		return Instances.tagged(tag)
	end)
	Instances.method("CollectionService", "AddTag", function(_, instance, tag)
		instance:AddTag(tag)
	end)
	Instances.method("CollectionService", "RemoveTag", function(_, instance, tag)
		instance:RemoveTag(tag)
	end)
	Instances.method("CollectionService", "HasTag", function(_, instance, tag)
		return instance:HasTag(tag)
	end)
	Instances.method("CollectionService", "GetTags", function(_, instance)
		return instance:GetTags()
	end)
	Instances.method("CollectionService", "GetInstanceAddedSignal", function(_, tag)
		return Instances.tagSignal(tag, true)
	end)
	Instances.method("CollectionService", "GetInstanceRemovedSignal", function(_, tag)
		return Instances.tagSignal(tag, false)
	end)

	Instances.method("PhysicsService", "RegisterCollisionGroup", function(_, name)
		current.collisionGroups[name] = current.collisionGroups[name] or {}
	end)
	Instances.method("PhysicsService", "IsCollisionGroupRegistered", function(_, name)
		return name == "Default" or current.collisionGroups[name] ~= nil
	end)
	Instances.method("PhysicsService", "CollisionGroupSetCollidable", function(_, a, b, collidable)
		for _, name in { a, b } do
			if name ~= "Default" and not current.collisionGroups[name] then
				error("Collision group '" .. tostring(name) .. "' is not registered", 2)
			end
		end
		assert(type(collidable) == "boolean", "collidable must be a boolean")
	end)

	Instances.method("Debris", "AddItem", function(_, instance, lifetime)
		Scheduler.delay(lifetime or 10, function()
			if not Instances.states[instance].destroyed then
				instance:Destroy()
			end
		end)
	end)

	Instances.method("DataStoreService", "GetDataStore", function(_, name)
		return current:getDataStore(name)
	end)

	Instances.method("ContentProvider", "PreloadAsync", function(_, list, callback)
		assert(type(list) == "table", "PreloadAsync expects an array")
		for _, item in list do
			local id = if type(item) == "string" then item else item.SoundId
			assert(type(id) == "string" and string.match(id, "^rbxasset"), "unexpected content id " .. tostring(id))
			Scheduler.wait(0.01)
			if callback then
				callback(id, Enum.AssetFetchStatus.Success)
			end
		end
	end)
	Instances.method("SoundService", "PlayLocalSound", function(_, sound)
		current:recordSound(sound)
	end)
	Instances.events("Sound", { "Ended", "Played", "Loaded" })
	Instances.method("Sound", "Play", function(self)
		current:recordSound(self)
	end)
	Instances.method("Sound", "Stop", function() end)
	Instances.method("ParticleEmitter", "Emit", function(_, count)
		assert(count == nil or type(count) == "number", "Emit expects a number")
	end)
	Instances.method("ParticleEmitter", "Clear", function() end)

	local function loadAnimation(_, animation)
		assert(Instances.isInstance(animation) and animation:IsA("Animation"), "LoadAnimation expects an Animation")
		assert(string.match(animation.AnimationId, "^rbxassetid://%d+$"), "Bad AnimationId " .. animation.AnimationId)
		local track = Instances.new("AnimationTrack", true)
		track.Name = animation.Name
		return track
	end
	Instances.method("Animator", "LoadAnimation", loadAnimation)
	Instances.method("Humanoid", "LoadAnimation", loadAnimation)
	Instances.events("AnimationTrack", { "Stopped", "Ended", "DidLoop", "KeyframeReached" })
	Instances.method("AnimationTrack", "Play", function(self)
		Instances.states[self].playing = true
	end)
	Instances.method("AnimationTrack", "Stop", function(self)
		Instances.states[self].playing = false
	end)
	Instances.method("AnimationTrack", "AdjustSpeed", function(_, speed)
		assert(type(speed) == "number", "AdjustSpeed expects a number")
	end)
	Instances.method("AnimationTrack", "AdjustWeight", function() end)

	-- Remotes
	Instances.events("RemoteEvent", { "OnServerEvent", "OnClientEvent" })
	Instances.method("RemoteEvent", "FireServer", function(self, ...)
		local args = copyArgs(...)
		Instances.signal(self, "OnServerEvent"):Fire(current.localPlayer, table.unpack(args, 1, args.n))
	end)
	Instances.method("RemoteEvent", "FireClient", function(self, player, ...)
		assert(Instances.isInstance(player) and player:IsA("Player"), "FireClient: argument 1 must be a Player")
		local args = copyArgs(...)
		current.remoteLog[self.Name] = (current.remoteLog[self.Name] or 0) + 1
		if player == current.localPlayer then
			Instances.signal(self, "OnClientEvent"):Fire(table.unpack(args, 1, args.n))
		end
	end)
	Instances.method("RemoteEvent", "FireAllClients", function(self, ...)
		local args = copyArgs(...)
		current.remoteLog[self.Name] = (current.remoteLog[self.Name] or 0) + 1
		if current.localPlayer then
			Instances.signal(self, "OnClientEvent"):Fire(table.unpack(args, 1, args.n))
		end
	end)
	Instances.callbacks("RemoteFunction", { "OnServerInvoke", "OnClientInvoke" })
	Instances.method("RemoteFunction", "InvokeServer", function(self, ...)
		local args = copyArgs(...)
		local waited = 0
		while not self.OnServerInvoke do
			waited += Scheduler.wait(0.1)
			if waited > 30 then
				error("InvokeServer: no OnServerInvoke for " .. self.Name)
			end
		end
		Scheduler.wait(0.03) -- network latency
		local results = table.pack(self.OnServerInvoke(current.localPlayer, table.unpack(args, 1, args.n)))
		for i = 1, results.n do
			results[i] = copyForNetwork(results[i])
		end
		return table.unpack(results, 1, results.n)
	end)

	Instances.events("ProximityPrompt", { "Triggered", "TriggerEnded", "PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded" })
	Instances.events("ProximityPromptService", { "PromptTriggered", "PromptShown", "PromptHidden" })
	Instances.events("GuiButton", { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click" })
	Instances.events("GuiObject", { "InputBegan", "InputEnded", "InputChanged", "MouseEnter", "MouseLeave", "MouseMoved" })
	Instances.events("UserInputService", { "InputBegan", "InputEnded", "InputChanged", "TouchStarted", "TouchEnded", "LastInputTypeChanged" })
	Instances.events("BindableEvent", { "Event" })
end

local apiRegistered = false

-- Construction ------------------------------------------------------------------------

export type Options = {
	placePath: string,
	placeId: number?,
	dataStoreMode: string?, -- "ok" | "denied"
	dataStores: { [string]: { [string]: string } }?, -- persisted JSON between runs
}

function Runtime.new(options: Options)
	if not apiRegistered then
		registerApi()
		apiRegistered = true
	end
	local self = setmetatable({}, Runtime)
	current = self
	self.options = options
	self.closeCallbacks = {}
	self.collisionGroups = {}
	self.remoteLog = {}
	self.soundLog = {}
	self.warnings = {}
	self.prints = {}
	self.moduleCache = { server = {}, client = {} }
	self.localPlayer = nil
	self.dataStores = options.dataStores or {}

	local game = Instances.new("DataModel", true)
	game.Name = "Game"
	Instances.setDataModel(game)
	Instances.setInternal(game, "PlaceId", options.placeId or 0)
	Instances.setInternal(game, "JobId", "emulator")
	self.game = game
	self.workspace = game:GetService("Workspace")
	self.players = game:GetService("Players")
	self.runService = game:GetService("RunService")
	local uis = game:GetService("UserInputService")
	Instances.setInternal(uis, "TouchEnabled", false)
	Instances.setInternal(uis, "KeyboardEnabled", true)
	local camera = Instances.new("Camera", true)
	camera.Name = "Camera"
	Instances.setInternal(camera, "ViewportSize", Vector2.new(1280, 720))
	camera.Parent = self.workspace
	Instances.setInternal(self.workspace, "CurrentCamera", camera)
	self.camera = camera

	self:loadPlace(options.placePath)
	return self
end

-- Copy scripts/folders from the built .rbxlx into the emulated DataModel.
function Runtime:loadPlace(path: string)
	local place = roblox.deserializePlace(fs.readFile(path))
	local function convert(source, parent)
		local className = source.ClassName
		local copy = Instances.new(className, true)
		copy.Name = source.Name
		if className == "Script" or className == "LocalScript" or className == "ModuleScript" then
			Instances.states[copy].props.Source = source.Source
		end
		for _, child in source:GetChildren() do
			convert(child, copy)
		end
		copy.Parent = parent
		return copy
	end
	for _, serviceName in { "ReplicatedStorage", "ServerScriptService", "StarterPlayer", "StarterGui", "Lighting" } do
		local source = place:GetService(serviceName)
		local service = self.game:GetService(serviceName)
		for _, child in source:GetChildren() do
			convert(child, service)
		end
	end
end

-- Script environments ---------------------------------------------------------------

local function baseLibraries()
	return {
		math = math, string = string, table = table, coroutine = coroutine, bit32 = bit32, utf8 = utf8,
		buffer = buffer, debug = debug, print = print, error = error, assert = assert, pcall = pcall,
		xpcall = xpcall, select = select, type = type, tostring = tostring, tonumber = tonumber,
		pairs = pairs, ipairs = ipairs, next = next, rawget = rawget, rawset = rawset, rawequal = rawequal,
		rawlen = rawlen, setmetatable = setmetatable, getmetatable = getmetatable, unpack = table.unpack,
	}
end

function Runtime:makeEnvironment(context: string, scriptInstance)
	local runtime = self
	local base = self["base_" .. context]
	if not base then
		base = baseLibraries()
		base.game = self.game
		base.workspace = self.workspace
		base.Workspace = self.workspace
		base.typeof = rbxTypeof
		base.Instance = {
			new = function(className, parent)
				local instance = Instances.new(className)
				if parent then
					instance.Parent = parent
				end
				return instance
			end,
		}
		for _, name in {
			"Vector3", "Vector2", "CFrame", "Color3", "UDim", "UDim2", "NumberSequence", "NumberSequenceKeypoint",
			"ColorSequence", "ColorSequenceKeypoint", "NumberRange", "BrickColor", "Rect", "Faces", "Axes",
			"PhysicalProperties", "Font", "Ray", "Region3",
		} do
			base[name] = roblox[name]
		end
		base.CFrame = CFrame
		base.Enum = roblox.Enum
		base.Random = RandomLib
		base.TweenInfo = TweenInfoLib
		base.task = {
			spawn = Scheduler.spawn,
			defer = Scheduler.defer,
			delay = Scheduler.delay,
			wait = Scheduler.wait,
			cancel = Scheduler.cancel,
		}
		base.wait = Scheduler.wait
		base.tick = function()
			return EPOCH + Scheduler.now
		end
		base.time = function()
			return Scheduler.now
		end
		base.os = table.clone(os)
		base.os.clock = function()
			return Scheduler.now
		end
		base.os.time = function()
			return EPOCH + math.floor(Scheduler.now)
		end
		base.warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				table.insert(parts, tostring((select(i, ...))))
			end
			local message = table.concat(parts, " ")
			table.insert(runtime.warnings, message)
			print("\27[33m[WARN]\27[0m " .. message)
		end
		base.print = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				table.insert(parts, tostring((select(i, ...))))
			end
			table.insert(runtime.prints, table.concat(parts, " "))
		end
		base.shared = {}
		base._G = {}
		self["base_" .. context] = base
	end
	local env = setmetatable({}, { __index = base })
	env.script = scriptInstance
	env.require = function(module)
		return runtime:require(context, module)
	end
	return env
end

function Runtime:compile(context: string, scriptInstance)
	local source = Instances.states[scriptInstance].props.Source
	assert(type(source) == "string", "Script has no source: " .. Instances.fullName(scriptInstance))
	return luau.load(source, {
		debugName = Instances.fullName(scriptInstance),
		environment = self:makeEnvironment(context, scriptInstance),
		injectGlobals = false,
	})
end

function Runtime:require(context: string, module)
	if not Instances.isInstance(module) or not module:IsA("ModuleScript") then
		error("Attempted to call require with invalid argument(s).", 2)
	end
	local cache = self.moduleCache[context]
	local entry = cache[module]
	if entry then
		if entry.loading then
			error("Requested module was required recursively: " .. Instances.fullName(module), 2)
		end
		return entry.value
	end
	entry = { loading = true }
	cache[module] = entry
	local chunk = self:compile(context, module)
	local results = table.pack(chunk())
	if results.n ~= 1 then
		error("Module code did not return exactly one value: " .. Instances.fullName(module), 2)
	end
	entry.value = results[1]
	entry.loading = false
	return entry.value
end

function Runtime:runScript(context: string, scriptInstance)
	local chunk = self:compile(context, scriptInstance)
	Scheduler.spawn(chunk)
end

function Runtime:startServer()
	for _, descendant in self.game:GetService("ServerScriptService"):GetDescendants() do
		if descendant.ClassName == "Script" then
			self:runScript("server", descendant)
		end
	end
	Scheduler.flushDeferred()
end

-- Access to the server's copy of a module (same instance the game uses).
function Runtime:serverModule(module)
	return self:require("server", module)
end

-- DataStores ------------------------------------------------------------------------------

function Runtime:getDataStore(name: string)
	local mode = self.options.dataStoreMode or "ok"
	if mode == "unpublished" then
		error("You must publish this place to the web to access DataStore.")
	end
	local storage = self.dataStores[name]
	if not storage then
		storage = {}
		self.dataStores[name] = storage
	end
	local function check()
		Scheduler.wait(0.05)
		if mode == "denied" then
			error("502: API Services rejected request with error. HTTP 403 (Forbidden) StudioAccessToApisNotAllowed")
		end
	end
	local store = {}
	function store:GetAsync(key)
		check()
		local json = storage[key]
		return if json then serde.decode("json", json) else nil
	end
	function store:SetAsync(key, value)
		check()
		storage[key] = serde.encode("json", value)
	end
	function store:UpdateAsync(key, transform)
		check()
		local old = if storage[key] then serde.decode("json", storage[key]) else nil
		local new = transform(old)
		if new ~= nil then
			storage[key] = serde.encode("json", new)
		end
		return new
	end
	return store
end

function Runtime:recordSound(sound)
	local id = sound.SoundId
	if id == "" then
		error("Playing a Sound with no SoundId")
	end
	self.soundLog[id] = (self.soundLog[id] or 0) + 1
end

-- Players ----------------------------------------------------------------------------------

local function characterPart(model, name, size, cframe)
	local part = Instances.new("Part", true)
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = false
	part.Parent = model
	return part
end

local function motor(name, part0, part1, c0, c1)
	local joint = Instances.new("Motor6D", true)
	joint.Name = name
	joint.Part0 = part0
	joint.Part1 = part1
	joint.C0 = c0
	joint.C1 = c1
	joint.Parent = part1
	return joint
end

function Runtime:spawnCharacter(player)
	local old = player.Character
	if old then
		Instances.fire(player, "CharacterRemoving", old)
		Scheduler.flushDeferred()
		old:Destroy()
	end
	local spawnPosition = Vector3.new(0, 3, 0)
	for _, descendant in self.workspace:GetDescendants() do
		if descendant.ClassName == "SpawnLocation" then
			spawnPosition = descendant.Position + Vector3.new(0, 3, 0)
			break
		end
	end
	local model = Instances.new("Model", true)
	model.Name = player.Name
	local base = CFrame.new(spawnPosition)
	local root = characterPart(model, "HumanoidRootPart", Vector3.new(2, 2, 1), base)
	root.Transparency = 1
	local torso = characterPart(model, "UpperTorso", Vector3.new(2, 1.6, 1), base * CFrame.new(0, 0.2, 0))
	local head = characterPart(model, "Head", Vector3.new(1.2, 1.2, 1.2), base * CFrame.new(0, 1.6, 0))
	local rightArm = characterPart(model, "RightUpperArm", Vector3.new(1, 1.2, 1), base * CFrame.new(1.5, 0.4, 0))
	local leftArm = characterPart(model, "LeftUpperArm", Vector3.new(1, 1.2, 1), base * CFrame.new(-1.5, 0.4, 0))
	characterPart(model, "LeftFoot", Vector3.new(1, 0.4, 1), base * CFrame.new(-0.5, -2.8, 0))
	motor("Root", root, torso, CFrame.new(0, 0.2, 0), CFrame.new())
	motor("Neck", torso, head, CFrame.new(0, 0.8, 0), CFrame.new(0, -0.6, 0))
	motor("RightShoulder", torso, rightArm, CFrame.new(1, 0.56, 0), CFrame.new(-0.5, 0.36, 0))
	motor("LeftShoulder", torso, leftArm, CFrame.new(-1, 0.56, 0), CFrame.new(0.5, 0.36, 0))
	local foot = model:FindFirstChild("LeftFoot")
	local hip = Instances.new("WeldConstraint", true)
	hip.Part0 = root
	hip.Part1 = foot
	hip.Parent = foot
	local humanoid = Instances.new("Humanoid", true)
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2
	humanoid.WalkSpeed = 20
	humanoid.Parent = model
	Instances.new("Animator", true).Parent = humanoid
	model.PrimaryPart = root
	player.Character = model
	model.Parent = self.workspace
	Instances.fire(player, "CharacterAdded", model)
	Scheduler.flushDeferred()
	return model
end

function Runtime:addPlayer(name: string, userId: number, withClient: boolean)
	local player = Instances.new("Player", true)
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	for _, className in { "PlayerGui", "PlayerScripts", "Backpack" } do
		local child = Instances.new(className, true)
		child.Name = className
		child.Parent = player
	end
	if withClient then
		self.localPlayer = player
	end
	player.Parent = self.players
	Instances.fire(self.players, "PlayerAdded", player)
	Scheduler.flushDeferred()
	if withClient then
		local starter = self.game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
		local playerScripts = player:FindFirstChild("PlayerScripts")
		for _, child in starter:GetChildren() do
			child:Clone().Parent = playerScripts
		end
		for _, descendant in playerScripts:GetDescendants() do
			if descendant.ClassName == "LocalScript" then
				self:runScript("client", descendant)
			end
		end
	end
	Scheduler.delay(0.4, function()
		if player.Parent then
			self:spawnCharacter(player)
		end
	end)
	return player
end

function Runtime:removePlayer(player)
	Instances.fire(self.players, "PlayerRemoving", player)
	Scheduler.flushDeferred()
	local character = player.Character
	if character then
		Instances.fire(player, "CharacterRemoving", character)
		Scheduler.flushDeferred()
		character:Destroy()
	end
	player:Destroy()
	if player == self.localPlayer then
		self.localPlayer = nil
	end
	Scheduler.flushDeferred()
end

function Runtime:shutdown()
	for _, player in self.players:GetPlayers() do
		self:removePlayer(player)
	end
	local pending = 0
	for _, callback in self.closeCallbacks do
		pending += 1
		Scheduler.spawn(function()
			callback()
			pending -= 1
		end)
	end
	local elapsed = 0
	while pending > 0 and elapsed < 30 do
		self:step(1 / 30)
		elapsed += 1 / 30
	end
	return pending == 0
end

-- Simulation -------------------------------------------------------------------------------

Runtime.dt = 1 / 30

function Runtime:step(dt: number?)
	local delta = dt or Runtime.dt
	Scheduler.step(delta, function(frameDt)
		Instances.stepHumanoids(frameDt)
		Instances.fire(self.runService, "Stepped", Scheduler.now, frameDt)
		Instances.fire(self.runService, "RenderStepped", frameDt)
		Instances.fire(self.runService, "Heartbeat", frameDt)
	end)
end

function Runtime:run(seconds: number, onStep: (() -> ())?)
	local elapsed = 0
	while elapsed < seconds do
		self:step()
		elapsed += Runtime.dt
		if onStep then
			onStep()
		end
	end
end

function Runtime:runUntil(timeout: number, predicate: () -> boolean): boolean
	local elapsed = 0
	while elapsed < timeout do
		if predicate() then
			return true
		end
		self:step()
		elapsed += Runtime.dt
	end
	return predicate()
end

function Runtime:root(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

function Runtime:walkTo(player, position: Vector3, timeout: number?): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if not humanoid then
		return false
	end
	humanoid:MoveTo(position)
	return self:runUntil(timeout or 20, function()
		local root = self:root(player)
		if not root then
			return false
		end
		local p = root.Position
		return Vector3.new(p.X - position.X, 0, p.Z - position.Z).Magnitude < 1
	end)
end

function Runtime:promptPosition(prompt): Vector3
	local parent = prompt.Parent
	if parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return parent.Position
end

-- Simulates the player pressing E on a prompt (respecting what the client allows).
function Runtime:trigger(player, prompt): (boolean, string?)
	if not prompt:IsDescendantOf(self.workspace) then
		return false, "prompt is not in the workspace"
	end
	if not prompt.Enabled then
		return false, "prompt is disabled on the client"
	end
	local root = self:root(player)
	if not root then
		return false, "no character"
	end
	local distance = (self:promptPosition(prompt) - root.Position).Magnitude
	if distance > prompt.MaxActivationDistance then
		return false, string.format("too far away (%.1f > %.1f)", distance, prompt.MaxActivationDistance)
	end
	if prompt.HoldDuration > 0 then
		self:run(prompt.HoldDuration)
	end
	Instances.fire(prompt, "Triggered", player)
	self:step()
	return true
end

function Runtime:click(button)
	for _, name in { "MouseButton1Down", "MouseButton1Up", "Activated", "MouseButton1Click" } do
		Instances.fire(button, name)
	end
	self:step()
end

return Runtime
