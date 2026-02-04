--!optimize 2
--!native
local Profiler = {}
Profiler.isRunning = false

local IsServer: boolean = game:GetService("RunService"):IsServer()
local vide = require("../vide")
local convert_scale = require("./util/convert_scale")
local Signal = require("./util/limesignal")

local socket_changed_signal = Signal.Signal.new()
local lastUpdated: number, profiler_state: boolean = os.clock(), IsServer

type socket_array_map = {
	memory: number,
	heartbeat_time: number,
	frames_time: number,
	render_gpu_time: number,
	render_cpu_time: number,
}
type socket_transcript_type_inner = {
	id: number,
	host: string,
	memory: string,
	cpu: string,
	frames: string,
	gpu: string,
	cpuRender: string,
}
type socket_transcript_type = { socket_transcript_type_inner }

type TimerInfo = {
	name: string,
	startTime: number,
	deductedTime: number,
}

local activeTimers: { [thread]: { TimerInfo } } = {}
local frameSystems: { { Name: string, Duration: number, Color: Color3 } } = {}
local colorCache: { [string]: Color3 } = {}
local sockets: { [Player | string]: socket_array_map } = {}
local stores: { [string]: any } = {}

local timerPool: { TimerInfo } = {}

local function allocTimer(name: string, startTime: number): TimerInfo
	local t = table.remove(timerPool)
	if t then
		t.name = name
		t.startTime = startTime
		t.deductedTime = 0
		return t
	end
	return {
		name = name,
		startTime = startTime,
		deductedTime = 0,
	}
end

local function freeTimer(t: TimerInfo)
	table.insert(timerPool, t)
end

local state: (any) -> { any } = vide.source({})

local function generateColor(str: string): Color3
	if colorCache[str] then
		return colorCache[str]
	end
	local hash: number = 0
	for i: number = 1, #str do
		local char: number = string.byte(str, i)
		hash = (bit32.lshift(hash, 5) - hash) + char
		hash = bit32.band(hash, hash) -- Convert to 32bit integer
	end
	local hue: number = (hash % 360) / 360
	local color: Color3 = Color3.fromHSV(hue, 0.8, 0.95)
	colorCache[str] = color
	return color
end

Profiler.reset = function()
	Profiler.isRunning = false
	table.clear(activeTimers)
	table.clear(frameSystems)
	Profiler.isRunning = true
end

-- Sockets

Profiler.all_sockets = function(): { [Player | string]: socket_array_map? }
	return sockets
end

Profiler.socket_assign = function(host: Player | string, new_map: socket_array_map)
	sockets[host] = new_map
	socket_changed_signal:fire()
end

Profiler.getSocket = function(host: Player | string): socket_array_map?
	return sockets[host]
end

-- { id = 1, host = "server", memory = "0.00GB", cpu = "0.0us", gpu = "0.0us", cpuRender = "0.00ms" },
Profiler.sockets_transcript = function(): socket_transcript_type
	local idx: number, transcript: socket_transcript_type = 1, {}
	for host: Player | string, map: socket_array_map in sockets do
		local frame_time: number = 1 / (map.frames_time or 1)
		if frame_time ~= frame_time or frame_time == math.huge then
			frame_time = 0
		end
		table.insert(transcript, {
			id = idx,
			host = type(host) == "string" and host or (host :: Player).Name,
			memory = convert_scale("B", map.memory),
			cpu = convert_scale("s", map.heartbeat_time or 0),
			frames = string.format("%.2f", frame_time),
			gpu = convert_scale("s", map.render_gpu_time or 0),
			cpuRender = convert_scale("s", map.render_cpu_time or 0),
		})
		idx += 1
	end
	table.sort(transcript, function(a: socket_transcript_type_inner, b: socket_transcript_type_inner): boolean
		return a.id ~= 1 and true or a.host < b.host
	end)
	return transcript
end

Profiler.onSocketChanged = socket_changed_signal

-- Profilers

Profiler.RunTime = function(): number
	local runTime: number = 0
	for _, frame: { Name: string, Duration: number, Color: Color3 } in frameSystems do
		runTime += frame.Duration
	end
	return runTime
end

Profiler.merge = function(map_value: { { Name: string, Duration: number, Color: Color3 } }?, update_state: boolean?)
	map_value = map_value or frameSystems
	local merged: { [string]: { Name: string, Duration: number, Count: number, Color: Color3 } } = {}
	for _, frameData: { Name: string, Duration: number, Color: Color3 } in map_value :: any do
		if not merged[frameData.Name] then
			merged[frameData.Name] = {
				Name = frameData.Name,
				Duration = frameData.Duration,
				Count = 1,
				Color = frameData.Color,
			}
		else
			local system = merged[frameData.Name]
			system.Duration += frameData.Duration
			system.Count += 1
		end
	end
	local sorted = {}
	for _, system in merged do
		system.Duration /= system.Count
		table.insert(sorted, system)
	end
	table.sort(sorted, function(a, b)
		return a.Name < b.Name
	end)
	if update_state == nil or update_state then
		state(sorted)
	end
	table.clear(frameSystems)
	return sorted
end

Profiler.Begin = function(name: string)
	if not Profiler.isRunning or not profiler_state then
		return
	end
	local startTime = os.clock()
	local currentThread: thread = coroutine.running()
	local threadStack = activeTimers[currentThread]
	if not threadStack then
		threadStack = {}
		activeTimers[currentThread] = threadStack
	end

	table.insert(threadStack, allocTimer(name, startTime))

	-- overhead compensation
	local endTime = os.clock()
	local overhead = endTime - startTime
	if #threadStack > 1 then
		threadStack[#threadStack - 1].deductedTime += overhead
	end
end

Profiler.End = function(name: string)
	if not Profiler.isRunning or not profiler_state then
		return
	end
	local endStart: number = os.clock()
	local currentThread: thread = coroutine.running()
	local threadTimers: { TimerInfo } = activeTimers[currentThread]
	if not threadTimers then
		return
	end

	local lastIndex = #threadTimers
	if lastIndex > 0 and threadTimers[lastIndex].name == name then
		local timer = threadTimers[lastIndex]
		table.remove(threadTimers, lastIndex)

		local duration: number = endStart - timer.startTime - timer.deductedTime
		if duration < 0 then
			duration = 0
		end

		table.insert(frameSystems, {
			Name = name,
			Duration = duration,
			Color = generateColor(name),
		})
		freeTimer(timer)
	else
		for i: number = lastIndex - 1, 1, -1 do
			local timer: TimerInfo = threadTimers[i]
			if timer.name == name then
				table.remove(threadTimers, i)

				local duration: number = endStart - timer.startTime - timer.deductedTime
				if duration < 0 then
					duration = 0
				end

				table.insert(frameSystems, {
					Name = name,
					Duration = duration,
					Color = generateColor(name),
				})
				freeTimer(timer)
				break
			end
		end
	end

	local endFinish = os.clock()
	local overhead = endFinish - endStart
	if #threadTimers > 0 then
		threadTimers[#threadTimers].deductedTime += overhead
	end

	if #threadTimers == 0 then
		activeTimers[currentThread] = nil
	end
	if endStart - lastUpdated >= 1 then
		lastUpdated = endStart
		Profiler.merge(nil, true)
	end
end

Profiler.Pause = function()
	Profiler.isRunning = false
end

Profiler.Resume = function()
	Profiler.isRunning = true
end

Profiler.dump_state = function()
	return state
end

Profiler.dump_frames = function(): { { Name: string, Duration: number, Color: Color3 } }
	return frameSystems
end

-- Misc

Profiler.store = function(key: string, value: any)
	stores[key] = value
end

Profiler.get_stored = function(key: string): any?
	return stores[key]
end

if not IsServer then
	script:GetAttributeChangedSignal("__state__"):Connect(function()
		profiler_state = script:GetAttribute("__state__")
	end)
	profiler_state = script:GetAttribute("__state__")
end

return Profiler :: typeof(Profiler)
