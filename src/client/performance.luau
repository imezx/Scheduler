--!optimize 2
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local vide = require("../../vide")
local remotes = require("./remotes/Remotes")

local get_performance_socket = remotes.fromFunction("scheduler.get_performance_socket")
local communicate_frame_time = remotes.fromEvent("scheduler.communicate_frame_time")
local server_frame_time = remotes.fromEvent("scheduler.server_frame_time")
local communicate_run_time = remotes.fromEvent("scheduler.communicate_run_time")

local root, source, cleanup = vide.root, vide.source, vide.cleanup
local open_connections: { [Player | string]: RBXScriptConnection } = {}

local Buffer = remotes.buffer
local localUser: Player = Players.LocalPlayer
local average_heartbeat: number = 0
local average_frames: number = 0
local render_gpu_frame_time: number = 0
local render_cpu_frame_time: number = 0
local counter: number = 0
local acccumulate: number = 0
local UPDATE_EVERY: number = 1

local scope_value = source("")
local store = source({})
local localSocketId = source("")

local memory_usage = source({} :: { number })
local heartbeat_time = source({} :: { number })
local frames_time = source({} :: { number })
local render_gpu_time = source({} :: { number })
local render_cpu_time = source({} :: { number })

local function performance(Profiler)
	cleanup(function()
		for host: Player | string, socket: RBXScriptConnection in open_connections do
			socket:Disconnect()
		end
		table.clear(open_connections)
	end)

	local function obtain_store_data(host: Player | string)
		local data = host and get_performance_socket:Invoke(3, { to = host, id = 0 }, nil)
		if not data or not data.socket then
			return
		end
		localSocketId(data.socket)
		local memory = source(0)
		local heartbeat_time = source(0)
		local frames_time = source(0)
		local render_gpu_time = source(0)
		local render_cpu_time = source(0)

		store()[host] = {
			memory = memory,
			heartbeat_time = heartbeat_time,
			frames_time = frames_time,
			render_gpu_time = render_gpu_time,
			render_cpu_time = render_cpu_time,
		}
		store(store())
		local socket: RBXScriptConnection
		socket = communicate_frame_time.OnClientEvent:Connect(function(_host: Player | string, packet: buffer)
			if _host ~= host or type(packet) ~= "buffer" then
				return
			end
			-- socket:Disconnect()
			local packet_heartbeat_time: number, packet_frames_time: number, packet_render_gpu_time: number, packet_render_cpu_time: number, packet_memory: number =
				buffer.readf64(packet, 0),
				buffer.readf64(packet, 8),
				buffer.readf64(packet, 16),
				buffer.readf64(packet, 24),
				buffer.readf64(packet, 32)
			heartbeat_time(packet_heartbeat_time)
			frames_time(packet_frames_time)
			render_gpu_time(packet_render_gpu_time)
			render_cpu_time(packet_render_cpu_time)
			memory(packet_memory)
			Profiler.socket_assign(host, {
				memory = packet_memory,
				heartbeat_time = packet_heartbeat_time,
				frames_time = packet_frames_time,
				render_cpu_time = packet_render_cpu_time,
				render_gpu_time = packet_render_gpu_time,
			})
		end)
		open_connections[host] = socket
		if host == localUser then
			communicate_run_time.OnClientEvent:Connect(function(packet: buffer)
				if type(packet) ~= "buffer" then
					return
				end
				local parsed_runTime: string = buffer.tostring(packet)
				scope_value(parsed_runTime)
				local scope_value = Profiler.get_stored("server_runtime")
				if not scope_value then
					Profiler.store("server_runtime", scope_value)
				end
			end)
		end
	end

	obtain_store_data("server")
	for _, player: Player in Players:GetPlayers() do
		obtain_store_data(player)
	end

	cleanup(Players.PlayerAdded:Connect(obtain_store_data))
	cleanup(Players.PlayerRemoving:Connect(function(Player: Player)
		if open_connections[Player] then
			open_connections[Player]:Disconnect()
			open_connections[Player] = nil
		end
	end))
	cleanup(RunService.Heartbeat:Connect(function()
		for host: Player | string, socket: RBXScriptConnection in open_connections do
			if socket and socket.Connected then
				continue
			end
			store()[host] = nil
			store(store())
		end
	end))

	local server_frame_value = Profiler.get_stored("server_frame_value")

	cleanup(RunService.Heartbeat:Connect(function(dt: number)
		counter += 1
		acccumulate += dt

		average_heartbeat += Stats.HeartbeatTime
		average_frames += Stats.FrameTime
		render_gpu_frame_time += Stats.RenderGPUFrameTime
		render_cpu_frame_time += Stats.RenderCPUFrameTime

		if acccumulate > UPDATE_EVERY then
			if next(open_connections) then
				local b: buffer = buffer.create(40)
				local data_memory: number, data_heartbeat_time: number, data_frames_time: number, data_render_cpu_frame_time: number, data_render_gpu_frame_time: number =
					Stats:GetTotalMemoryUsageMb() * 1e3 * 1e3,
					average_heartbeat / counter,
					average_frames / counter,
					render_cpu_frame_time / counter,
					render_gpu_frame_time / counter

				buffer.writef64(b, 0, data_heartbeat_time)
				buffer.writef64(b, 8, data_frames_time)
				buffer.writef64(b, 16, data_render_gpu_frame_time)
				buffer.writef64(b, 24, data_render_cpu_frame_time)
				buffer.writef64(b, 32, data_memory)

				memory_usage()[localUser] = data_memory
				heartbeat_time()[localUser] = data_heartbeat_time
				frames_time()[localUser] = data_frames_time
				render_gpu_time()[localUser] = data_render_cpu_frame_time
				render_cpu_time()[localUser] = data_render_gpu_frame_time

				communicate_frame_time:FireServer(localSocketId(), b)

				Profiler.socket_assign(localUser, {
					memory = data_memory,
					heartbeat_time = data_heartbeat_time,
					frames_time = data_frames_time,
					render_cpu_time = data_render_cpu_frame_time,
					render_gpu_time = data_render_gpu_frame_time,
				})
			end

			average_heartbeat = 0
			average_frames = 0
			render_gpu_frame_time = 0
			render_cpu_frame_time = 0
			acccumulate -= UPDATE_EVERY
			counter = 0
		end
	end))

	cleanup(server_frame_time.OnClientEvent:Connect(function(packet: buffer)
		if type(packet) ~= "buffer" then
			return
		end
		local raw_exported_server_frames = Buffer.read(packet)
		if not raw_exported_server_frames then
			return
		end
		server_frame_value(Profiler.merge(raw_exported_server_frames, false))
	end))
end

return {
	run = function(Profiler)
		return root(function()
			performance(Profiler)
		end)
	end,
}
