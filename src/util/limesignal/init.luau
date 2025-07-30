--!optimize 2
--!strict
--!native

--$Packages
local ThreadPool = require("@self/threadpool")

--$Types
export type Connection<T...> = {
	disconnect: (self: Connection<T...>) -> (),
	reconnect: (self: Connection<T...>) -> (),
	connected: boolean,
}

export type Event<T...> = {
	connect: (self: Event<T...>, fn: (T...) -> ()) -> Connection<T...>,
	connectOnce: (self: Event<T...>, fn: (T...) -> ()) -> Connection<T...>,
	disconnectAll: (self: Event<T...>) -> (),
	wait: (self: Event<T...>) -> T...,
	from: (emitter: (event: Event<T...>, T...) -> ()) -> Event<T...>,
}

export type Bindable<T...> = {
	new: () -> Bindable<T...>,
	wrap: (signal: RBXScriptSignal<T...>) -> Bindable<T...>,
	fire: (self: Bindable<T...>, T...) -> (),
	Destroy: (self: Bindable<T...>) -> (), -- why PascalCase? because it does call Destroy method on RBXScriptConnection if it exists
	RBXScriptConnection: RBXScriptConnection?,
	event: Event<T...>,
}

export type Signal<T...> = {
	new: () -> Signal<T...>,
	wrap: (signal: RBXScriptSignal<T...>) -> Signal<T...>,
	connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection<T...>,
	connectOnce: (self: Signal<T...>, fn: (T...) -> ()) -> Connection<T...>,
	disconnectAll: (self: Signal<T...>) -> (),
	wait: (self: Signal<T...>) -> T...,
	fire: (self: Signal<T...>, T...) -> (),
	Destroy: (self: Signal<T...>) -> (),
	RBXScriptConnection: RBXScriptConnection?,
}

local Connection = {} :: Connection<...any>
(Connection :: any).__index = Connection

local function disconnect(self)
	if not self.connected then
		return
	end
	self.connected = false

	local next = (self :: any)._next
	local prev = (self :: any)._prev

	if next then
		next._prev = prev
	end
	if prev then
		prev._next = next
	end

	local signal = (self :: any)._signal
	if signal._head == self then
		signal._head = next
	end
end
Connection.disconnect = disconnect -- i know this is annoying but this is only for micro optimization

function reconnect(self)
	if self.connected then
		return
	end
	self.connected = true

	local signal = (self :: any)._signal
	local head = signal._head
	if head then
		head._prev = self
	end
	signal._head = self;
	(self :: any)._next = head;
	(self :: any)._prev = false
end
Connection.reconnect = reconnect

--$Lime
local Bindable = {} :: Bindable<...any>
(Bindable :: any).__index = Bindable

local Event = {} :: Event<...any>
(Event :: any).__index = Event

local Signal = {} :: Signal<...any>
(Signal :: any).__index = Signal

local rbxConnect, rbxDisconnect
do
	local bindable = Instance.new("BindableEvent")
	rbxConnect = bindable.Event.Connect
	rbxDisconnect = bindable.Event:Connect(function() end).Disconnect
	bindable:Destroy()
end

local function connect<T...>(self, fn)
	local head = (self :: any)._head
	local cn = setmetatable({
		connected = true,
		_signal = self,
		_fn = fn,
		_next = head,
		_prev = false,
	}, Connection)

	if head then
		head._prev = cn
	end
	(self :: any)._head = cn :: any

	return cn :: any
end
Signal.connect = connect
Event.connect = connect :: any

local function once<T...>(self, fn)
	local cn
	cn = connect(self, function(...: any)
		disconnect(cn)
		fn(...)
	end)
	return cn
end
Signal.connectOnce = once
Event.connectOnce = once :: any

local function wait<T...>(self): T...
	local thread = coroutine.running()
	local cn
	cn = connect(self, function(...)
		disconnect(cn)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end
Signal.wait = wait
Event.wait = wait :: any

local function fire<T...>(self, ...)
	local event = (self :: any).event or self
	local cn = event._head
	while cn do
		-- local thread
		-- if #freeThreads > 0 then
		-- 	thread = freeThreads[#freeThreads]
		-- 	freeThreads[#freeThreads] = nil
		-- else
		-- 	thread = coroutine.create(yielder)
		-- 	coroutine.resume(thread)
		-- end

		-- task.spawn(thread, cn._fn, thread, ...)

		-- now we spawn in shared threadpool!

		ThreadPool.spawn(cn._fn, ...)
		cn = cn._next
	end
end
Signal.fire = fire
Bindable.fire = fire :: any

local function disconnectAll<T...>(self)
	local cn = (self :: any)._head
	while cn do
		disconnect(cn)
		cn = cn._next
	end
end
Event.disconnectAll = disconnectAll
Signal.disconnectAll = disconnectAll

local function Destroy<T...>(self)
	disconnectAll((self :: any).event or self)
	local cn = self.RBXScriptConnection
	if cn then
		rbxDisconnect(cn)
		self.RBXScriptConnection = nil :: any
	end
end
Signal.Destroy = Destroy
Bindable.Destroy = Destroy :: any

function Event.from(emitter)
	return setmetatable({ _emitter = emitter, _head = false }, Event) :: any
end

function Bindable.new()
	local event = setmetatable({ _head = false }, Event)
	return setmetatable({ event = event }, Bindable) :: any
end

function Bindable.wrap(signal)
	local wrapper = Bindable.new()
	wrapper.RBXScriptConnection = rbxConnect(signal, function(...)
		fire(wrapper :: any, ...)
	end)
	return wrapper
end

function Signal.new()
	return setmetatable({ _head = false }, Signal) :: any
end

function Signal.wrap(signal)
	local wrapper = Signal.new()
	wrapper.RBXScriptConnection = rbxConnect(signal, function(...)
		fire(wrapper, ...)
	end)
	return wrapper
end

local function createEmitter(): <T...>(event: Event<T...>, T...) -> ()
	local function emitter(event, ...)
		if not event._emitter or event._emitter ~= emitter then
			error("Emitted an invalid event")
		end
		fire(event, ...)
	end
	return emitter :: any
end

return {
	Signal = Signal,
	Event = Event,
	Bindable = Bindable,
	createEmitter = createEmitter,
}
