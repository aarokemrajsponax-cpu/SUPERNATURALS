-- A floating visual companion that follows each participant.
local Visual = require(script.Parent.Parent.Visual)
local kinds = { "orb", "drone", "lantern", "snowflake", "leaf", "spark" }
return Visual.module({
	channels = { "companion" },
	group = "player",
	cost = 8,
	params = {
		kind = { type = "enum", values = kinds, default = "orb" },
		color = { type = "color", default = { 140, 230, 255 } },
	},
}, "Companion")
