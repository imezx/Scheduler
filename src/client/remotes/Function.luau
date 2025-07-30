--!optimize 2
--!strict
--@EternityDev
local Function = {}
Function.__index = Function

local RunService = game:GetService("RunService")

function Function.new(remote: RemoteFunction)
	local meta = setmetatable({
		remote = remote,
	}, Function)
	remote.Destroying:Once(function()
		if not meta then return end
		Function.Remove(meta)
	end)
	return meta
end

function Function:Invoke(expireTime: number, ...: any): (...any?)
	if not RunService:IsClient() then
		return error("Cannot execute InvokeServer on the server.", 2)
	end
	if not expireTime then return end
	local timer, session
	local obj = { ... }
	local thread: thread = coroutine.running()
	timer = task.delay(expireTime or 3, function()
		task.cancel(session)
		task.spawn(thread, nil)
	end)
	session = task.spawn(function()
		local obj = self.remote:InvokeServer(table.unpack(obj))
		task.cancel(timer)
		task.spawn(thread, obj)
	end)
	return coroutine.yield()
end

function Function:Remove()
	setmetatable(self, nil)
end

function Function:Destroy()
	self.remote:Destroy()
end

return Function