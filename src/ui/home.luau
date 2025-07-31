--!optimize 2
local pebble = require("../../pebble")
local vide = require("../../vide")

local spawn_app = require("./spawn_app")
local scheduler_app = require("./scheduler")
local performance_app = require("./performance")

type HomeProps = {
	env: string,
	Profiler: any,
	profiler_state: RemoteEvent,
	version: string,

	onClose: () -> (),
	onDestroy: () -> (),
}

local create = vide.create
local source = vide.source
local values = vide.values
local cleanup = vide.cleanup

local env_apps = source({
	{
		env = "Server",
		Position = UDim2.fromScale(0.25, 0.5),
		menus = source({
			scheduler = scheduler_app,
		}),
	},
	{
		env = "Client",
		Position = UDim2.fromScale(0.5, 0.5),
		menus = source({
			scheduler = scheduler_app,
			performance = performance_app,
		}),
	},
})

local home_app_ui, performance_app_ui, server_app_ui, client_app_ui

return function(props: HomeProps)
	home_app_ui = pebble.widget({
		title = "Home",
		subtitle = `v{props.version}`,
		min_size = Vector2.new(230, 200),
		bind_to_close = props.onClose,

		pebble.container({
			create("UIListLayout")({
				Padding = UDim.new(0, 2),
				VerticalFlex = Enum.UIFlexAlignment.SpaceEvenly,
				HorizontalFlex = Enum.UIFlexAlignment.Fill,
			}),

			create("ScrollingFrame")({
				-- Size = UDim2.fromScale(1, 1),
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				ScrollBarThickness = 6,
				HorizontalScrollBarInset = Enum.ScrollBarInset.Always,

				create("UIFlexItem")({
					FlexMode = Enum.UIFlexMode.Fill,
				}),

				pebble.padding({
					x = UDim.new(0, 1),
					right = UDim.new(0, 8),
				}),

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalFlex = Enum.UIFlexAlignment.Fill,
					Padding = UDim.new(0, 8),
					Wraps = true,
				}),

				values(env_apps, function(value, key)
					return pebble.pane({
						name = "",
						size = UDim2.fromOffset(200, 0),
						automaticsize = Enum.AutomaticSize.Y,

						create("UIListLayout")({
							Padding = UDim.new(0, 8),
						}),

						pebble.typography({
							text = value.env,
							wrapped = true,
						}),

						values(value.menus, function(app_constructor, i)
							local menu: string = i()
							return pebble.button({
								size = UDim2.new(1, 0, 0, 30),
								text = menu,
								activated = function()
									local app = menu == "scheduler"
										and spawn_app.spawn_app(app_constructor, {
											env = value.env,
											Position = value.Position,
											ProfilerState = value.env == "Server" and props.Profiler.get_stored(
												"server_frame_value"
											) or props.Profiler.dump_state(),
											Runtime = value.env == "Server"
												and props.Profiler.get_stored("server_runtime"),
											Pause = function()
												if value.env == "Server" then
													props.profiler_state:FireServer(false)
													return
												end
												props.Profiler.Pause()
											end,
											Resume = function()
												if value.env == "Server" then
													props.profiler_state:FireServer(true)
													return
												end
												props.Profiler.Resume()
											end,
											onClose = function()
												if value.env == "Client" and client_app_ui then
													pcall(client_app_ui)
													client_app_ui = nil
												elseif server_app_ui then
													pcall(server_app_ui)
													server_app_ui = nil
												end
												if
													not client_app_ui
													and not server_app_ui
													and not performance_app_ui
													and not home_app_ui
												then
													spawn_app.unmount_all()
													props.onDestroy()
												end
											end,
										})
									if value.env == "Client" then
										if app then
											client_app_ui = app
										end
										if menu == "performance" then
											if performance_app_ui then
												pcall(performance_app_ui)
												performance_app_ui = nil
											end
											performance_app_ui = spawn_app.spawn_app(app_constructor, {
												performanceData = props.Profiler.sockets_transcript(),
												IsVisible = true,
												onClose = function()
													if performance_app_ui then
														pcall(performance_app_ui)
														performance_app_ui = nil
													end
													if
														not client_app_ui
														and not server_app_ui
														and not performance_app_ui
														and not home_app_ui
													then
														spawn_app.unmount_all()
														props.onDestroy()
													end
												end,
											})
										end
									else
										if app then
											server_app_ui = app
										end
									end
								end,
							})
						end),
					})
				end),
			}),
		}),
	})
	cleanup(home_app_ui)
	return home_app_ui
end
