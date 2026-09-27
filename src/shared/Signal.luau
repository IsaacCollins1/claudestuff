--!strict
-- Minimal signal used for in-process events (server services / client controllers).

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local listeners: { (T...) -> () } = {}

	local self = {}

	function self.Connect(_: any, callback: (T...) -> ()): Connection
		table.insert(listeners, callback)
		local connection = { Connected = true }
		function connection.Disconnect(conn: any)
			if not conn.Connected then
				return
			end
			conn.Connected = false
			local index = table.find(listeners, callback)
			if index then
				table.remove(listeners, index)
			end
		end
		return connection :: any
	end

	function self.Fire(_: any, ...: T...)
		for _, callback in table.clone(listeners) do
			task.spawn(callback, ...)
		end
	end

	return self :: any
end

return Signal
