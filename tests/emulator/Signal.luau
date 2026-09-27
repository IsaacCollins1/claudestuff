--!nocheck
-- RBXScriptSignal emulation. Handlers run deferred (like Roblox's default
-- "Deferred" signal behaviour).

local Scheduler = require("./Scheduler")

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local handlers = self._signal._handlers
	local index = table.find(handlers, self)
	if index then
		table.remove(handlers, index)
	end
end

function Signal.new(name: string?)
	return setmetatable({ _handlers = {}, _waiting = {}, _name = name or "Signal" }, Signal)
end

function Signal:Connect(callback)
	assert(type(callback) == "function", "Attempt to connect failed: Passed value is not a function")
	local connection = setmetatable({ Connected = true, _signal = self, _callback = callback }, Connection)
	table.insert(self._handlers, connection)
	return connection
end

function Signal:Once(callback)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal:ConnectParallel(callback)
	return self:Connect(callback)
end

function Signal:Wait()
	local thread = coroutine.running()
	table.insert(self._waiting, thread)
	return coroutine.yield()
end

function Signal:Fire(...)
	for _, connection in table.clone(self._handlers) do
		if connection.Connected then
			Scheduler.defer(connection._callback, ...)
		end
	end
	local waiting = self._waiting
	self._waiting = {}
	for _, thread in waiting do
		Scheduler.defer(thread, ...)
	end
end

function Signal:HasConnections(): boolean
	return #self._handlers > 0 or #self._waiting > 0
end

function Signal:DisconnectAll()
	for _, connection in table.clone(self._handlers) do
		connection:Disconnect()
	end
end

return Signal
