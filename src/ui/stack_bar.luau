--!optimize 2
local vide = require("../../vide")

local create = vide.create
local indexes = vide.indexes
local derive = vide.derive

type stack_bar = {
	values: () -> { { Name: string, Color: Color3, Size: UDim2, Duration: number } },
	selected: (index: number) -> (),
}

return function(props: stack_bar)
	local total: () -> number = derive(function()
		local total: number = 0
		for _, value in props.values() do
			total += value.Duration
		end
		return total
	end)
	return create("Frame")({
		Name = "Graph",
		Size = UDim2.new(1, 0, 0, 32),
		indexes(props.values, function(value, index)
			local data = value()
			return create("Frame")({
				Size = function()
					return UDim2.fromScale(data.Duration / total(), 1)
				end,
				BackgroundColor3 = data.Color,
				MouseEnter = function()
					props.selected(index)
				end,
			})
		end),
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
		}),
	})
end
