-- Falling or drifting particles drawn by each client around the player (capped by the client).
local Visual = require(script.Parent.Parent.Visual)
local kinds = { "leaves", "snow", "rain", "petals", "sparkles", "meteors", "embers", "ash", "data", "bubbles" }
return Visual.module({
	channels = { "weather" },
	group = "environment",
	cost = 12,
	params = {
		kind = { type = "enum", values = kinds, default = "snow" },
		rate = { type = "number", min = 1, max = 100, default = 30, scales = true },
		wind = { type = "number", min = -20, max = 20, default = 0 },
		size = { type = "number", min = 0.1, max = 3, default = 0.4 },
		color = { type = "color", default = { 255, 255, 255 } },
	},
}, "Weather")
