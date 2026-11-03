-- Animated trails behind participants as they move.
local Visual = require(script.Parent.Parent.Visual)
local styles = { "energy", "particles", "ribbon", "comet", "footprints", "pixels" }
return Visual.module({
	channels = { "trail" },
	group = "player",
	cost = 8,
	params = {
		style = { type = "enum", values = styles, default = "energy" },
		length = { type = "number", min = 0.3, max = 3, default = 1, scales = true },
		color = { type = "color", default = { 120, 220, 255 } },
	},
}, "Trail")
