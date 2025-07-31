--!optimize 2
local client = {}

local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local localPlayer = game:GetService("Players").LocalPlayer

local vide = require("../vide")
local Profiler = require("./profiler")
local client_performance = require("@self/performance")
local remotes = require("@self/remotes/Remotes")
local spawn_app = require("./ui/spawn_app")
local home_app = require("./ui/home")

local unbind_performance_socket = remotes.fromEvent("scheduler.unbind_performance_socket")
local profiler_state = remotes.fromEvent("scheduler.profiler_state")

local server_frame_value = vide.source({})

local version: string, rootScope, root_performance, home_app_ui
Profiler.store("server_frame_value", server_frame_value)

local function onStateChanged(instance: Instance?)
	if instance and instance ~= localPlayer then
		return
	end
	if localPlayer:HasTag("__allowedScheduler__") then
		script.Parent.profiler:SetAttribute("__state__", true)
	else
		script.Parent.profiler:SetAttribute("__state__", false)
	end
end

client.assign_ver = function(ver: string)
	version = ver
end

client.init = function()
	if script:HasTag("__init__") then
		return
	end
	script:AddTag("__init__")
	CollectionService:GetInstanceAddedSignal("__allowedScheduler__"):Connect(onStateChanged)
	CollectionService:GetInstanceRemovedSignal("__allowedScheduler__"):Connect(onStateChanged)
	task.defer(onStateChanged)
end

client.toggle_widget = function(_, state: Enum.UserInputState)
	if state and state ~= Enum.UserInputState.End then
		return
	end
	-- cleanup
	if root_performance then
		root_performance()
		root_performance = nil
	end
	if not localPlayer:HasTag("__allowedScheduler__") or rootScope then
		unbind_performance_socket:FireServer()
		profiler_state:FireServer(false)
		Profiler.Pause()
		if rootScope then
			rootScope()
			rootScope = nil
		end
		home_app_ui = nil
		Profiler.reset()
		spawn_app.unmount_all()
		return
	end
	if home_app_ui then
		return
	end
	root_performance = client_performance.run(Profiler)
	profiler_state:FireServer(true)
	Profiler.Resume()
	Profiler.reset()
	rootScope = vide.root(function()
		-- Server Scheduler
		home_app_ui = home_app({
			env = "Server",
			Profiler = Profiler,
			profiler_state = profiler_state,
			ProfilerState = Profiler.get_stored("server_frame_value"),
			Runtime = Profiler.get_stored("server_runtime"),
			version = version,

			onClose = function()
				if home_app_ui then
					home_app_ui.Enabled = false
				end
			end,
			onDestroy = function()
				profiler_state:FireServer(false)
				Profiler.Pause()
				home_app_ui = nil
				if not rootScope then
					return
				end
				rootScope()
				rootScope = nil
				spawn_app.unmount_all()
			end,
		})
		home_app_ui.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui", 9e9)
	end)
end

client.bind_to = function(key_bind: Enum.KeyCode)
	if not client then
		warn(`please use .client() first.`)
		return
	end
	ContextActionService:UnbindAction("Toggle Scheduler Widget")
	ContextActionService:BindAction("Toggle Scheduler Widget", client.toggle_widget, false, key_bind or Enum.KeyCode.F3)
end

return client :: typeof(client)
