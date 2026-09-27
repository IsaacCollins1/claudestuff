--!nocheck
-- Virtual-time task scheduler used by the headless play-test.
-- Game code's `task.*`, `os.clock()`, `tick()` and Heartbeat all run on this
-- clock, so minutes of gameplay can be simulated in seconds.

local Scheduler = {}

Scheduler.now = 0
Scheduler.errors = {} :: { string }
Scheduler.frame = 0

type Timer = { time: number, seq: number, thread: thread, start: number, args: { any }? }

local timers: { Timer } = {}
local deferred: { { thread: thread, args: { any } } } = {}
local seq = 0

function Scheduler.report(message: string)
	table.insert(Scheduler.errors, message)
	print("\27[31m[SCRIPT ERROR]\27[0m " .. message)
end

local function resume(thread: thread, ...)
	if coroutine.status(thread) ~= "suspended" then
		return
	end
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		Scheduler.report(debug.traceback(thread, tostring(err)))
	end
end
Scheduler.resume = resume

local function toThread(callback: any): thread
	if type(callback) == "thread" then
		return callback
	end
	return coroutine.create(callback)
end

function Scheduler.spawn(callback: any, ...): thread
	local thread = toThread(callback)
	resume(thread, ...)
	return thread
end

function Scheduler.defer(callback: any, ...): thread
	local thread = toThread(callback)
	table.insert(deferred, { thread = thread, args = table.pack(...) })
	return thread
end

function Scheduler.delay(duration: number?, callback: any, ...): thread
	local thread = toThread(callback)
	seq += 1
	table.insert(timers, {
		time = Scheduler.now + math.max(duration or 0, 0),
		seq = seq,
		thread = thread,
		start = Scheduler.now,
		args = table.pack(...),
	})
	return thread
end

function Scheduler.wait(duration: number?): number
	local thread = coroutine.running()
	seq += 1
	table.insert(timers, {
		time = Scheduler.now + math.max(duration or 0, 0),
		seq = seq,
		thread = thread,
		start = Scheduler.now,
		args = nil,
	})
	return coroutine.yield()
end

function Scheduler.cancel(thread: thread)
	for index = #timers, 1, -1 do
		if timers[index].thread == thread then
			table.remove(timers, index)
		end
	end
	for index = #deferred, 1, -1 do
		if deferred[index].thread == thread then
			table.remove(deferred, index)
		end
	end
	if coroutine.status(thread) == "suspended" then
		coroutine.close(thread)
	end
end

function Scheduler.flushDeferred()
	local rounds = 0
	while #deferred > 0 do
		rounds += 1
		if rounds > 10000 then
			Scheduler.report("Deferred event loop exceeded 10000 rounds")
			table.clear(deferred)
			return
		end
		local batch = deferred
		deferred = {}
		for _, entry in batch do
			resume(entry.thread, table.unpack(entry.args, 1, entry.args.n))
		end
	end
end

-- Advance virtual time by dt. `onFrame(dt)` fires the RunService events.
function Scheduler.step(dt: number, onFrame: (dt: number) -> ())
	Scheduler.now += dt
	Scheduler.frame += 1
	onFrame(dt)
	Scheduler.flushDeferred()

	local due = {}
	local remaining = {}
	for _, timer in timers do
		if timer.time <= Scheduler.now then
			table.insert(due, timer)
		else
			table.insert(remaining, timer)
		end
	end
	timers = remaining
	table.sort(due, function(a, b)
		if a.time == b.time then
			return a.seq < b.seq
		end
		return a.time < b.time
	end)
	for _, timer in due do
		if timer.args then
			resume(timer.thread, table.unpack(timer.args, 1, timer.args.n))
		else
			resume(timer.thread, Scheduler.now - timer.start)
		end
		Scheduler.flushDeferred()
	end
end

function Scheduler.pendingCount(): number
	return #timers
end

return Scheduler
