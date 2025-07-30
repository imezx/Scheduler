--!strict
--!optimize 2
--!native
local Profiler = {}

local IsServer: boolean = game:GetService("RunService"):IsServer()
local vide = require("../vide")
local convert_scale = require("./util/convert_scale")
local Signal = require("./util/limesignal")

local socket_changed_signal = Signal.Signal.new()
local lastUpdated: number, profiler_state: boolean = os.clock(), IsServer

type socket_array_map = {
	memory: number,
	heartbeat_time: number,
	render_gpu_time: number,
	render_cpu_time: number,
}
type socket_transcript_type_inner = {
	id: number,
	host: string,
	memory: string,
	cpu: string,
	gpu: string,
	cpuRender: string,
}
type socket_transcript_type = { socket_transcript_type_inner }

local activeTimers: { [string]: { number } } = {}
local frameSystems: { { Name: string, Duration: number, Color: Color3 } } = {}
local isPaused = false
local colorCache: { [string]: Color3 } = {}
local sockets: { [Player | string]: socket_array_map } = {}
local stores: { [string]: any } = {}

local state = vide.source({})

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
	isPaused = true
	table.clear(activeTimers)
	table.clear(frameSystems)
	isPaused = false
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
		table.insert(transcript, {
			id = idx,
			host = type(host) == "string" and host or (host :: Player).Name,
			memory = convert_scale("B", map.memory),
			cpu = convert_scale("s", map.heartbeat_time or 0),
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
	for _, system in merged do
		system.Duration /= system.Count
	end
	if update_state == nil or update_state then
		state(merged)
	end
	table.clear(frameSystems)
	return merged
end

Profiler.Begin = function(name: string)
	if isPaused or not profiler_state then
		return
	end
	if not activeTimers[name] then
		activeTimers[name] = {}
	end

	table.insert(activeTimers[name], os.clock())
end

Profiler.End = function(name: string)
	local endTime: number = os.clock()
	if isPaused or not profiler_state then
		return
	end
	local timerStack: { number } = activeTimers[name]
	if not timerStack or not next(timerStack) then
		return
	end
	local startTime: number = table.remove(timerStack, 1) :: number
	table.insert(frameSystems, {
		Name = name,
		Duration = (endTime - startTime),
		Color = generateColor(name),
	})
	if (endTime - lastUpdated) >= 1 then
		lastUpdated = os.clock()
		Profiler.merge(nil, true)
	end
end

Profiler.Pause = function()
	isPaused = true
end

Profiler.Resume = function()
	isPaused = false
end

Profiler.dump_state = function()
	return state
end

Profiler.dump_frames = function(): { { Name: string, Duration: number, Color: Color3 } }
	if isPaused then
		return frameSystems
	end
	local exported = table.clone(frameSystems)
	table.clear(frameSystems)
	return exported
end

-- Misc

Profiler.store = function(key: string, value: any)
	stores[key] = value
end

Profiler.get_stored = function(key: string, value: any): any?
	return stores[key]
end

if not IsServer then
	script:GetAttributeChangedSignal("__state__"):Connect(function()
		profiler_state = script:GetAttribute("__state__")
	end)
	profiler_state = script:GetAttribute("__state__")
end

return Profiler :: typeof(Profiler)
