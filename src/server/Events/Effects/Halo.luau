-- Halos, orbiting rings and floating symbols over participants.
local Visual = require(script.Parent.Parent.Visual)
local styles = { "halo", "orbit_rings", "symbols", "crown", "antlers", "star" }
return Visual.module({
	channels = { "halo" },
	group = "player",
	cost = 5,
	params = {
		style = { type = "enum", values = styles, default = "halo" },
		color = { type = "color", default = { 255, 240, 170 } },
	},
}, "Halo")
