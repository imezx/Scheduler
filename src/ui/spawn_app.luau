-- by jabby
--!strict
--!optimize 2
local Players = game:GetService("Players")

local vide = require("../../vide")

local destroy_fn: { [() -> ()]: boolean } = {}

local function unmount_all()
	for destroy in destroy_fn do
		destroy()
	end
	table.clear(destroy_fn)
end

local function spawn_app<T>(app, props: T): () -> ()
	return vide.root(function(destroy)
		local destroy = function()
			destroy_fn[destroy] = nil
			pcall(destroy)
		end

		local application = app(props)
		application.Parent = Players.LocalPlayer.PlayerGui

		vide.cleanup(application)
		destroy_fn[destroy] = true

		return destroy
	end)
end

return {
	unmount_all = unmount_all,
	spawn_app = spawn_app,
}
