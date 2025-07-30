--!optimize 2
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local vide = require("../../Packages/vide")
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
local render_gpu_frame_time: number = 0
local render_cpu_frame_time: number = 0
local counter: number = 0
local acccumulate: number = 0
local UPDATE_EVERY: number = 1
local UPDATE_VALUE_RATE_DT: number = 0
local UPDATE_VALUE_RATE: number = 1 / 24

local scope_value = source("")
local store = source({})
local localSocketId = source("")

local hosts = source({ "Host" } :: { string })
local memory_usage = source({ "Memory Usage" } :: { number })
local heartbeat_time = source({ "CPU" } :: { number })
local render_gpu_time = source({ "GPU" } :: { number })
local render_cpu_time = source({ "CPU Render" } :: { number })

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
		local render_gpu_time = source(0)
		local render_cpu_time = source(0)

		store()[host] = {
			memory = memory,
			heartbeat_time = heartbeat_time,
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
			local packet_heartbeat_time: number, packet_render_gpu_time: number, packet_render_cpu_time: number, packet_memory: number =
				buffer.readf32(packet, 0),
				buffer.readf32(packet, 4),
				buffer.readf32(packet, 8),
				buffer.readf32(packet, 12)
			heartbeat_time(packet_heartbeat_time)
			render_gpu_time(packet_render_gpu_time)
			render_cpu_time(packet_render_cpu_time)
			memory(packet_memory)
			Profiler.socket_assign(host, {
				memory = packet_memory,
				heartbeat_time = packet_heartbeat_time,
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
		render_gpu_frame_time += Stats.RenderGPUFrameTime
		render_cpu_frame_time += Stats.RenderCPUFrameTime

		if acccumulate > UPDATE_EVERY then
			if next(open_connections) then
				local b: buffer = buffer.create(16)
				local data_memory, data_heartbeat_time, data_render_cpu_frame_time, data_render_gpu_frame_time =
					Stats:GetTotalMemoryUsageMb() * 1e3 * 1e3,
					average_heartbeat / counter,
					render_cpu_frame_time / counter,
					render_gpu_frame_time / counter

				buffer.writef32(b, 0, data_heartbeat_time)
				buffer.writef32(b, 4, data_render_gpu_frame_time)
				buffer.writef32(b, 8, data_render_cpu_frame_time)
				buffer.writef32(b, 12, data_memory)

				memory_usage()[localUser] = data_memory
				heartbeat_time()[localUser] = data_heartbeat_time
				render_gpu_time()[localUser] = data_render_cpu_frame_time
				render_cpu_time()[localUser] = data_render_gpu_frame_time

				communicate_frame_time:FireServer(localSocketId(), b)

				Profiler.socket_assign(localUser, {
					memory = data_memory,
					heartbeat_time = data_heartbeat_time,
					render_cpu_time = data_render_cpu_frame_time,
					render_gpu_time = data_render_gpu_frame_time,
				})
			end

			average_heartbeat = 0
			render_gpu_frame_time = 0
			render_cpu_frame_time = 0
			acccumulate -= UPDATE_EVERY
			counter = 0
		end
	end))

	cleanup(RunService.Heartbeat:Connect(function(dt: number)
		if UPDATE_VALUE_RATE_DT <= UPDATE_VALUE_RATE then
			UPDATE_VALUE_RATE_DT += dt
			return
		end
		UPDATE_VALUE_RATE_DT = 0

		local idx: number = 2
		for host: Player | string, data in store() do
			if host == localUser then
				continue
			end
			hosts()[idx] = tostring(host)
			local data_memory, data_heartbeat_time, data_render_cpu_frame_time, data_render_gpu_frame_time =
				data.memory(), data.heartbeat_time(), data.render_cpu_time(), data.render_gpu_time()
			-- print(data_memory, data_heartbeat_time, data_render_cpu_frame_time)
			memory_usage()[idx] = data_memory
			heartbeat_time()[idx] = data_heartbeat_time
			render_gpu_time()[idx] = data_render_cpu_frame_time
			render_cpu_time()[idx] = data_render_gpu_frame_time
			Profiler.socket_assign(host, {
				memory = data_memory,
				heartbeat_time = data_heartbeat_time,
				render_cpu_time = data_render_cpu_frame_time,
				render_gpu_time = data_render_gpu_frame_time,
			})
			idx += 1
		end

		table.move({}, #hosts(), idx, idx, hosts())
		table.move({}, #memory_usage(), idx, idx, memory_usage())
		table.move({}, #heartbeat_time(), idx, idx, heartbeat_time())
		table.move({}, #render_gpu_time(), idx, idx, render_gpu_time())
		table.move({}, #render_cpu_time(), idx, idx, render_cpu_time())

		hosts(hosts())
		memory_usage(memory_usage())
		heartbeat_time(heartbeat_time())
		render_gpu_time(render_gpu_time())
		render_cpu_time(render_cpu_time())
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
