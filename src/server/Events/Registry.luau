-- The central registry of effect modules. Every ModuleScript in Effects/ registers itself by
-- name; presets (shared/Config/EventPresets) refer to effects by that name.
local Registry = {}

Registry.effects = {} :: { [string]: any }
for _, module in script.Parent.Effects:GetChildren() do
	if module:IsA("ModuleScript") then
		Registry.effects[module.Name] = require(module)
	end
end

-- One line per effect module, for the custom event creator (a module may carry its own `description`)
Registry.descriptions = {
	Arrival = "A one-shot entrance burst when the event starts and when a player spawns.",
	Atmosphere = "Fog, haze and glow over the whole place.",
	Aura = "A glowing aura around players, in different silhouettes.",
	Banner = "A banner announcement shown to every player.",
	Companion = "A floating visual companion that follows each player.",
	Confetti = "Confetti falling around each player.",
	Decor = "Switches the seasonal decoration set.",
	Fireworks = "Fireworks bursts above the lobby.",
	Gravity = "Changes world gravity (event mode only, never during a match).",
	Halo = "Halos, orbiting rings and floating symbols over players.",
	Hologram = "Giant translucent holograms and emblems.",
	LightingTheme = "Changes the lighting mood of the whole world.",
	OwnerShowcase = "Owner-only flight, immunity and crown showcase.",
	SkyTheme = "Sky and time of day: stars, sun and moon.",
	Speed = "A walk speed multiplier for players outside a match (event mode only).",
	Structure = "Floating and standing glowing installations, never replacing map geometry.",
	Title = "Overhead title text over players.",
	Trail = "Animated trails behind players as they move.",
	Weather = "Falling or drifting particles such as snow, leaves or embers.",
}

function Registry.describe(id: string): string
	local effect = Registry.effects[id]
	return (effect and effect.description) or Registry.descriptions[id] or id
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
