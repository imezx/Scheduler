--!optimize 2
--!strict
local scheduler = {}

local profiler = require("@self/profiler")
local client = nil

scheduler.profiler = profiler

scheduler.server = function()
	local server = require("@self/server")
	return server
end

scheduler.client = function()
	if client then
		return client
	end
	client = require("@self/client")
	client.assign_ver("0.1.3")
	return client
end

return scheduler :: typeof(scheduler)
