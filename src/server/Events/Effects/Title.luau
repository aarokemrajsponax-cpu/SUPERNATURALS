-- Overhead title text over participants, from preset text only.
local Visual = require(script.Parent.Parent.Visual)
local styles = { "plain", "gold", "frost", "neon", "royal" }
return Visual.module({
	channels = { "title" },
	group = "player",
	cost = 3,
	params = {
		text = { type = "string", maxLen = 28, default = "Guest of Honor" },
		style = { type = "enum", values = styles, default = "plain" },
		color = { type = "color", default = { 255, 255, 255 } },
	},
}, "Title")
