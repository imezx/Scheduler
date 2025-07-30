--!optimize 2
local vide = require("../../Packages/vide")
local pebble = require("../../Packages/pebble")
local stack_bar = require("./stack_bar")

type SchedulerProps = {
	env: string,
	Position: UDim2,
	ProfilerState: () -> { any },
	Runtime: string?,

	Pause: () -> (),
	Resume: () -> (),
	onClose: () -> (),
}

local create = vide.create
local source = vide.source
local derive = vide.derive
local values = vide.values
local action = vide.action
local cleanup = vide.cleanup

local function changed(property: string, fn: (...any) -> ())
	return action(function(instance)
		local cn = instance:GetPropertyChangedSignal(property):Connect(function()
			fn(instance[property])
		end)
		cleanup(function()
			cn:Disconnect()
		end)
	end)
end

local sort_by_options = {
	"Name",
	"Frame Time",
}

local function to_computeTime(time: number): string
	if type(time) ~= "number" then
		return "unknown"
	end
	if time >= 1 then
		return string.format("%.2fs", time)
	elseif time >= 0.001 then
		local ms: number = time * 1e3
		local formattedMs: number = math.floor(ms * 1e2) / 1e2
		return `{formattedMs}ms`
	elseif time >= 0.000001 then
		local us: number = time * 1e6
		local formattedUs: number = math.floor(us * 1e2) / 1e2
		return `{formattedUs}µs`
	end
	local ns: number = time * 1e9
	local formattedNs: number = math.floor(ns * 1e2) / 1e2
	return `{formattedNs}ns`
end

return function(props: SchedulerProps)
	local selected = source(0)
	local sort_by = source(2)

	local max_frametime = derive(function()
		local max: number = 0
		for _, system in props.ProfilerState() do
			max = math.max(max, system.Duration)
		end
		return max
	end)

	-- Derived state for total runtime
	local totalRuntime = derive(function()
		local total: number = 0
		for _, system in props.ProfilerState() do
			total += system.Duration
		end
		return total
	end)

	-- Derived state for the timeline segments
	local timelineSegments = derive(function()
		local total = totalRuntime()
		if total == 0 then
			return {}
		end
		local segments = {}
		for _, system in props.ProfilerState() do
			table.insert(segments, {
				Name = system.Name,
				Color = system.Color,
				Size = UDim2.fromScale(system.Duration / total, 1),
				Duration = system.Duration,
			})
		end
		return segments
	end)

	local function assign_frame(data: { Name: string, Color: Color3, Size: UDim2, Duration: number })
		local gui_state = source(Enum.GuiState.Idle)
		local b = create("ImageButton")({
			Name = data.Name,
			Size = UDim2.new(1, 0, 0, 32),
			LayoutOrder = function()
				return if sort_by() == 3 then 1e9 - data.Duration * 1e8 else 1
			end,
			BackgroundColor3 = function()
				return if gui_state() == Enum.GuiState.Press
					then pebble.theme.bg[-1]()
					elseif gui_state() == Enum.GuiState.Hover then pebble.theme.bg[6]()
					else pebble.theme.bg[3]()
			end,
			Visible = true,
			changed("GuiState", gui_state),
			MouseButton2Click = function()
				props.Pause()
			end,

			create("Folder")({
				create("Frame")({
					Position = UDim2.new(0, 0, 1, 4),
					AnchorPoint = Vector2.new(0, 1),
					Size = function()
						return UDim2.new(data.Duration / max_frametime(), 0, 0, 1)
					end,
					BackgroundColor3 = pebble.theme.fg_on_bg_high[0],
				}),
			}),

			create("UIStroke")({
				Color = pebble.theme.bg[-3],
			}),

			create("UICorner")({
				CornerRadius = UDim.new(0, 4),
			}),

			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				HorizontalFlex = Enum.UIFlexAlignment.SpaceEvenly,
				Padding = UDim.new(0, 8),
			}),

			pebble.padding({
				x = UDim.new(0, 8),
			}),

			create("Frame")({
				Size = UDim2.fromOffset(16, 16),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = data.Color,
				create("UICorner")({
					CornerRadius = UDim.new(1, 0),
				}),
			}),

			pebble.typography({
				automaticsize = Enum.AutomaticSize.None,
				text = data.Name,

				truncate = Enum.TextTruncate.SplitWord,
				xalignment = Enum.TextXAlignment.Left,
				disabled = false,

				create("UIFlexItem")({
					FlexMode = Enum.UIFlexMode.Fill,
					GrowRatio = 1,
					ShrinkRatio = 1,
				}),
			}),

			pebble.typography({
				automaticsize = Enum.AutomaticSize.XY,
				text = to_computeTime(data.Duration),
				xalignment = Enum.TextXAlignment.Right,
				disabled = true,
			}),
		})
		cleanup(b)
		return b
	end

	return pebble.widget({
		title = "Scheduler",
		subtitle = `host: {props.env}`,

		min_size = Vector2.new(200, 300),

		bind_to_close = props.onClose,

		create("Frame")({
			Name = "Elements",
			Size = UDim2.fromScale(1, 1),
			AutomaticSize = Enum.AutomaticSize.Y,

			BackgroundTransparency = 1,

			create("UIListLayout")({
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				FillDirection = Enum.FillDirection.Vertical,
				VerticalFlex = Enum.UIFlexAlignment.SpaceBetween,
				Padding = UDim.new(0, 8),
			}),

			create("Frame")({
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,

				BackgroundTransparency = 1,

				pebble.pane({
					name = "Overview",
					size = UDim2.fromScale(1, 0),

					create("UIListLayout")({
						FillDirection = Enum.FillDirection.Vertical,
					}),

					pebble.typography({
						text = props.Runtime and function()
							return `Runtime: {props.Runtime}`
						end or function()
							local time: number = totalRuntime()
							return `Run time: {to_computeTime(time)}`
						end,
					}),

					stack_bar({
						values = timelineSegments,
						selected = selected,
					}),

					pebble.row({
						justifycontent = Enum.UIFlexAlignment.Fill,
						pebble.button({
							text = "Pause all",
							activated = props.Pause,
						}),

						pebble.button({
							text = "Resume all",
							activated = props.Resume,
						}),
					}),
				}),
			}),

			pebble.select({
				size = UDim2.new(1, 0, 0, 30),

				options = sort_by_options,
				selected = sort_by,
				update_selected = function(new)
					sort_by(new)
				end,
			}),

			create("ScrollingFrame")({
				Name = "Systems",

				Size = UDim2.fromScale(1, 0),
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,

				BackgroundTransparency = 1,

				ScrollBarThickness = 6,
				VerticalScrollBarInset = Enum.ScrollBarInset.Always,
				ScrollBarImageColor3 = pebble.theme.fg_on_bg_low[3],

				create("UIFlexItem")({
					FlexMode = Enum.UIFlexMode.Fill,
				}),

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, 8),

					SortOrder = function()
						return if sort_by() == 1 then Enum.SortOrder.Name else Enum.SortOrder.LayoutOrder
					end,
				}),

				pebble.padding({
					y = UDim.new(0, 1),
					x = UDim.new(0, 1),
				}),

				values(props.ProfilerState, assign_frame),
			}),
		}),
	})
end
