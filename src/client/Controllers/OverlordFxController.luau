-- Watches ReplicatedStorage.OverlordFx and draws every effect record the server publishes
-- (see src/server/Events). Players who join mid-event get the existing records at once.
-- Records that disappear are cleaned up here, so nothing outlives its event.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Visuals = require(script.Parent.Parent.Overlord.Visuals)

local OverlordFxController = {}

function OverlordFxController:Init(_controllers)
	self.cleanups = {} :: { [Instance]: () -> () }
end

function OverlordFxController:Start()
	local root = ReplicatedStorage:WaitForChild("OverlordFx")
	local function add(record: Instance)
		if self.cleanups[record] then
			return
		end
		local cleanup = Visuals.render(record)
		self.cleanups[record] = cleanup or function() end
	end
	root.ChildAdded:Connect(add)
	root.ChildRemoved:Connect(function(record)
		local cleanup = self.cleanups[record]
		self.cleanups[record] = nil
		if cleanup then
			cleanup()
		end
	end)
	for _, record in root:GetChildren() do
		add(record)
	end
end

return OverlordFxController
