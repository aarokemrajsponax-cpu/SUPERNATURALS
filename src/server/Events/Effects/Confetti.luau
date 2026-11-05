-- Confetti falling around each player.
local Visual = require(script.Parent.Parent.Visual)
local shapes = { "squares", "streamers", "stars", "petals" }
return Visual.module({
	channels = { "confetti" },
	group = "spectacle",
	cost = 12,
	params = {
		shape = { type = "enum", values = shapes, default = "squares" },
		rate = { type = "number", min = 5, max = 80, default = 30, scales = true },
		color = { type = "color", default = { 255, 120, 180 } },
	},
}, "Confetti")
