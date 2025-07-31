--!optimize 2
local server = {}
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local CollectionService = game:GetService("CollectionService")

local convert_units = require("./util/convert_units")
local remotes = require("@self/remotes/Remotes")

local Buffer = remotes.buffer
local get_performance_socket = remotes.fromFunction("scheduler.get_performance_socket")
local unbind_performance_socket = remotes.fromEvent("scheduler.unbind_performance_socket")
local communicate_frame_time = remotes.fromEvent("scheduler.communicate_frame_time")
local server_frame_time = remotes.fromEvent("scheduler.server_frame_time")
local communicate_run_time = remotes.fromEvent("scheduler.communicate_run_time")
local profiler_state = remotes.fromEvent("scheduler.profiler_state")

local SEND_EVERY: number = 1

server.allowed = function(): { Player }
	return CollectionService:GetTagged("__allowedScheduler__")
end

server.allow = function(player: Player)
	player:AddTag("__allowedScheduler__")
end

server.disallow = function(player: Player)
	player:RemoveTag("__allowedScheduler__")
end

server.init = function(Profiler)
	if script:HasTag("__init__") then
		return
	end
	script:AddTag("__init__")
	local active_sockets = {}
	local _queue = {}

	get_performance_socket.remote.OnServerInvoke = function(sender: Player)
		local socket_id: string = HttpService:GenerateGUID(false):gsub("-", "")
		active_sockets[sender] = socket_id
		return {
			socket = socket_id,
		}
	end

	unbind_performance_socket.OnServerEvent:Connect(function(sender: Player)
		active_sockets[sender] = nil
	end)

	communicate_frame_time.OnServerEvent:Connect(function(sender: Player, socketId: string, packet: buffer)
		if
			type(socketId) ~= "string"
			or type(packet) ~= "buffer"
			or buffer.len(packet) ~= 40
			or not active_sockets[sender]
			or active_sockets[sender] ~= socketId
		then
			return
		end
		_queue[sender] = packet
	end)

	profiler_state.OnServerEvent:Connect(function(sender: Player, state: boolean)
		if not active_sockets[sender] or not sender:HasTag("__allowedScheduler__") or type(state) ~= "boolean" then
			return
		end
		Profiler.reset()
		if state == true then
			Profiler.Resume()
		else
			Profiler.Pause()
		end
	end)

	local average_heartbeat: number = 0
	local average_frames: number = 0
	local render_gpu_frame_time: number = 0
	local render_cpu_frame_time: number = 0
	local counter: number = 0
	local acccumulate: number = 0

	RunService.Heartbeat:Connect(function(dt: number)
		counter += 1
		acccumulate += dt

		average_heartbeat += Stats.HeartbeatTime
		average_frames += dt
		render_gpu_frame_time += Stats.RenderGPUFrameTime
		render_cpu_frame_time += Stats.RenderCPUFrameTime

		if acccumulate > SEND_EVERY and Profiler.isRunning then
			if next(active_sockets) then
				local runTime: string = convert_units("s", Profiler.RunTime())
				local exported_scheduler: { { Name: string, Duration: number, Color: Color3 } } = Profiler.dump_frames()
				local b: buffer = buffer.create(40)
				buffer.writef64(b, 0, average_heartbeat / counter)
				buffer.writef64(b, 8, average_frames / counter)
				buffer.writef64(b, 16, render_gpu_frame_time / counter)
				buffer.writef64(b, 24, render_cpu_frame_time / counter)
				buffer.writef64(b, 32, Stats:GetTotalMemoryUsageMb() * 1e3 * 1e3)

				for socket: Player in active_sockets do
					if not socket or not socket.Parent then
						active_sockets[socket] = nil
						continue
					end
					communicate_frame_time:FireClient(socket, "server", b)
					server_frame_time:FireClient(socket, Buffer.write(exported_scheduler))
					communicate_run_time:FireClient(socket, buffer.fromstring(runTime))
				end
			end
			if next(_queue) then
				for host: Player, packet: buffer in _queue do
					if not host or not host.Parent or buffer.len(packet) ~= 40 then
						_queue[host] = nil
						continue
					end
					for socket: Player in active_sockets do
						if not socket or not socket.Parent then
							active_sockets[socket] = nil
							continue
						end
						if socket == host then
							continue
						end
						communicate_frame_time:FireClient(socket, host, packet)
					end
					_queue[host] = nil
				end
			end

			average_heartbeat = 0
			average_frames = 0
			render_gpu_frame_time = 0
			render_cpu_frame_time = 0
			acccumulate -= SEND_EVERY
			counter = 0
		end
	end)
end

return server :: typeof(server)
