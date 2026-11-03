-- The central registry of effect modules. Every ModuleScript in Effects/ registers itself by
-- name; presets (shared/Config/EventPresets) refer to effects by that name.
local Registry = {}

Registry.effects = {} :: { [string]: any }
for _, module in script.Parent.Effects:GetChildren() do
	if module:IsA("ModuleScript") then
		Registry.effects[module.Name] = require(module)
	end
end

function Registry.channelsOf(effect, params): { string }
	local channels = effect.channels
	if type(channels) == "function" then
		return channels(params)
	end
	return channels
end

function Registry.costOf(effect, params): number
	local cost = effect.cost
	if type(cost) == "function" then
		return cost(params)
	end
	return cost
end

return Registry
