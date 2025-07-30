--!optimize 2
--!strict
--@EternityDev
--Server
local Remotes = {}

if not script.Parent.Parent.Parent:FindFirstChild("Remotes") then
	Instance.new("Folder", script.Parent.Parent.Parent).Name = "Remotes"
end
local RemotesDir = script.Parent.Parent.Parent:WaitForChild("Remotes")

local Function = require("./Function")

function Remotes.fromEvent(remoteName: string): RemoteEvent
	if not RemotesDir:FindFirstChild(`Remote_{remoteName}`) then
		Instance.new("RemoteEvent", RemotesDir).Name = `Remote_{remoteName}`
	end
	return RemotesDir[`Remote_{remoteName}`]
end

function Remotes.fromFunction(remoteName: string)
	if not RemotesDir:FindFirstChild(`Remote_{remoteName}`) then
		Instance.new("RemoteFunction", RemotesDir).Name = `Remote_{remoteName}`
	end
	return Function.new(RemotesDir[`Remote_{remoteName}`])
end

Remotes.buffer = require("../../util/bufferencoder")

return Remotes
