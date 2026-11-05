-- A glowing aura around participants; styles are different silhouettes, not recolours.
local Visual = require(script.Parent.Parent.Visual)
local styles = { "glow", "energy", "rings", "outline", "cosmic", "festive", "flame", "static" }
return Visual.module({
	channels = { "aura" },
	group = "player",
	cost = 10,
	params = {
		style = { type = "enum", values = styles, default = "glow" },
		size = { type = "number", min = 0.5, max = 3, default = 1, scales = true },
		color = { type = "color", default = { 255, 220, 120 } },
		ownerOnly = { type = "bool", default = false },
	},
}, "Aura")
