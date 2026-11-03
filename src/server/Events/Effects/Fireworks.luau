-- Fireworks bursts above the lobby, drawn on each client.
local Visual = require(script.Parent.Parent.Visual)
local patterns = { "peony", "ring", "willow", "heart", "star", "spiral", "crossette", "finale" }
return Visual.module({
	channels = { "fireworks" },
	group = "spectacle",
	cost = 15,
	params = {
		pattern = { type = "enum", values = patterns, default = "peony" },
		interval = { type = "number", min = 0.5, max = 10, default = 2 },
		size = { type = "number", min = 0.5, max = 3, default = 1, scales = true },
		color = { type = "color", default = { 255, 190, 80 } },
	},
}, "Fireworks")
