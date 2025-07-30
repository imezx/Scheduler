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
		if not meta then
			return
		end
		Function.Remove(meta)
	end)
	return meta
end

function Function:Invoke(expireTime: number, player: Player, ...: any): ...any?
	if not RunService:IsServer() then
		return error("Cannot execute InvokeClient on the Client.", 2)
	end
	if not expireTime then
		return
	end
	local timer, session
	local obj = { ... }
	local thread: thread = coroutine.running()
	timer = task.delay(expireTime or 3, function()
		task.cancel(session)
		task.spawn(thread, nil)
	end)
	session = task.spawn(function()
		if not player or not player.Parent then
			task.cancel(timer)
			task.spawn(thread, nil)
			return
		end
		local response = self.remote:InvokeClient(player, table.unpack(obj))
		task.cancel(timer)
		task.spawn(thread, response)
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
