-- A one-shot entrance burst when the event starts and when a participant spawns.
local Visual = require(script.Parent.Parent.Visual)
local styles = { "light_pillar", "shockwave", "portal", "stardust", "lightning", "golden_gate" }
return Visual.module({
	channels = { "arrival" },
	group = "player",
	cost = 4,
	params = {
		style = { type = "enum", values = styles, default = "light_pillar" },
		color = { type = "color", default = { 255, 220, 140 } },
	},
}, "Arrival")
