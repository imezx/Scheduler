--!optimize 2
local vide = require("../../Packages/vide")

local create = vide.create
local indexes = vide.indexes

type stack_bar = {
	values: () -> { { Name: string, Color: Color3, Size: UDim2, Duration: number } },
	selected: (index: number) -> (),
}

return function(props: stack_bar)
	return create("Frame")({
		Name = "Graph",
		Size = UDim2.new(1, 0, 0, 32),

		indexes(props.values, function(value, index)
			local data = value()
			return create("Frame")({
				Size = data.Size,
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
