-- A banner and chime-free announcement shown to every player (preset text only).
local Visual = require(script.Parent.Parent.Visual)
local styles = { "plain", "gold", "frost", "alert" }
return Visual.module({
	channels = { "banner" },
	group = "spectacle",
	cost = 1,
	params = {
		text = { type = "string", maxLen = 60, default = "A special event has begun" },
		style = { type = "enum", values = styles, default = "plain" },
	},
}, "Banner")
