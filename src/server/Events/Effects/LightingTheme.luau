-- Changes the whole world's lighting mood. Touches only the properties listed in PROPS, and
-- puts every one back exactly on stop.
local Env = require(script.Parent.Parent.Env)
local rgb = Env.rgb

local PROPS = { "Ambient", "OutdoorAmbient", "Brightness", "ColorShift_Top", "ColorShift_Bottom", "ExposureCompensation" }

-- ambient, outdoor, brightness, shiftTop, shiftBottom, exposure
local THEMES = {
	golden = { rgb(120, 90, 40), rgb(200, 150, 70), 3, rgb(255, 200, 100), rgb(120, 70, 20), 0.3 },
	neon = { rgb(40, 20, 90), rgb(60, 40, 140), 2, rgb(0, 255, 220), rgb(255, 0, 200), 0.1 },
	cosmic = { rgb(25, 15, 60), rgb(40, 30, 90), 1, rgb(140, 90, 255), rgb(20, 20, 70), -0.2 },
	dark_facility = { rgb(15, 18, 24), rgb(25, 30, 40), 0.6, rgb(0, 0, 0), rgb(10, 20, 30), -0.6 },
	holo = { rgb(30, 60, 90), rgb(50, 110, 150), 2, rgb(80, 220, 255), rgb(0, 60, 100), 0.2 },
	rainbow = { rgb(90, 80, 110), rgb(150, 140, 170), 2.5, rgb(255, 120, 200), rgb(80, 200, 255), 0.2 },
	mono = { rgb(90, 90, 90), rgb(130, 130, 130), 2, rgb(200, 200, 200), rgb(60, 60, 60), 0 },
	ethereal = { rgb(120, 130, 160), rgb(180, 190, 220), 2, rgb(230, 235, 255), rgb(150, 160, 200), 0.4 },
	autumn = { rgb(110, 60, 30), rgb(190, 110, 50), 2.5, rgb(255, 160, 70), rgb(110, 50, 20), 0.2 },
	frost = { rgb(90, 120, 160), rgb(150, 190, 230), 2.2, rgb(200, 235, 255), rgb(90, 130, 190), 0.3 },
	festive = { rgb(90, 40, 40), rgb(60, 110, 70), 2, rgb(255, 220, 160), rgb(160, 30, 40), 0.1 },
	crimson = { rgb(80, 15, 20), rgb(130, 25, 30), 1.2, rgb(255, 60, 40), rgb(60, 0, 10), -0.1 },
	spectral = { rgb(40, 70, 60), rgb(70, 120, 100), 1, rgb(120, 255, 190), rgb(20, 50, 50), -0.3 },
	aurora = { rgb(30, 70, 80), rgb(50, 120, 110), 1.6, rgb(90, 255, 170), rgb(70, 60, 180), 0 },
	ember = { rgb(100, 40, 15), rgb(170, 70, 25), 1.8, rgb(255, 120, 40), rgb(90, 20, 10), 0.1 },
	rose = { rgb(120, 60, 80), rgb(190, 100, 130), 2.2, rgb(255, 170, 200), rgb(140, 40, 80), 0.2 },
	sunburst = { rgb(130, 120, 70), rgb(220, 200, 120), 3.5, rgb(255, 245, 190), rgb(180, 140, 60), 0.5 },
	stadium = { rgb(60, 60, 70), rgb(90, 90, 110), 4, rgb(255, 255, 255), rgb(120, 130, 170), 0.6 },
}
local ids = {}
for id in THEMES do
	table.insert(ids, id)
end
table.sort(ids)

return {
	id = "LightingTheme",
	channels = { "lighting" },
	group = "environment",
	cost = 5,
	gameplay = false,
	ownerOnly = false,
	themes = ids,
	params = {
		theme = { type = "enum", values = ids, default = "golden" },
		intensity = { type = "number", min = 0.25, max = 2, default = 1, scales = true },
	},
	start = function(ctx, p)
		local lighting = ctx.lighting
		local restore = Env.capture(lighting, PROPS)
		local theme = THEMES[p.theme]
		local t = math.clamp(p.intensity, 0, 1)
		lighting.Ambient = Env.lerpColor(lighting.Ambient, theme[1], t)
		lighting.OutdoorAmbient = Env.lerpColor(lighting.OutdoorAmbient, theme[2], t)
		lighting.Brightness = math.clamp(Env.lerp(lighting.Brightness, theme[3] * p.intensity, t), 0, 8)
		lighting.ColorShift_Top = Env.lerpColor(lighting.ColorShift_Top, theme[4], t)
		lighting.ColorShift_Bottom = Env.lerpColor(lighting.ColorShift_Bottom, theme[5], t)
		lighting.ExposureCompensation = math.clamp(Env.lerp(lighting.ExposureCompensation, theme[6], t), -3, 3)
		return restore
	end,
}
