--!optimize 2
local vide = require("../../Packages/vide")
local pebble = require("../../Packages/pebble")
local Profiler = require("../profiler")

local create = vide.create
local source = vide.source
local values = vide.values
local cleanup = vide.cleanup

local function parse(data)
	local columnDefinitions = {
		{ key = "host", displayName = "Host" },
		{ key = "memory", displayName = "Memory Usage" },
		{ key = "cpu", displayName = "CPU" },
		{ key = "gpu", displayName = "GPU" },
		{ key = "cpuRender", displayName = "CPU Render" },
	}
	local resultTable = {}
	local columnMap = {}
	for i, def in columnDefinitions do
		resultTable[i] = { def.displayName }
		columnMap[def.key] = i
	end
	for _, record in data do
		for _, def in columnDefinitions do
			local key: string = def.key
			local value = record[key]
			local columnIndex: number = columnMap[key]
			if columnIndex and value ~= nil then
				table.insert(resultTable[columnIndex], value)
			end
		end
	end
	return resultTable
end

return function(props)
	local performanceData = source(parse(props.performanceData))

	Profiler.onSocketChanged:disconnectAll()
	Profiler.onSocketChanged:connect(function()
		local parse = parse(Profiler.sockets_transcript())
		performanceData(parse)
	end)

	return pebble.widget({
		title = "Performance",
		min_size = Vector2.new(450, 250),
		size = Vector2.new(550, 250),

		bind_to_close = props.onClose,

		pebble.container({
			Size = UDim2.fromScale(1, 1),

			create("UIFlexItem")({
				FlexMode = Enum.UIFlexMode.Fill,
			}),

			pebble.tablesheet({
				size = UDim2.fromScale(1, 1),
				column_sizes = source({ 100, 80, 100, 200 }),
				read_value = function(column, row)
					local value = performanceData()[column][row]
					return value and value or ""
				end,
				on_click = function() end,
				on_click2 = function() end,
				columns = performanceData,
			}),
		}),
	})
end
