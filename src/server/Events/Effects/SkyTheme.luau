-- Sky and time of day: clock time, stars, sun and moon size. Uses the place's Sky object when
-- it has one (restoring its values), otherwise adds one and removes it on stop.
local THEMES = {
	starfield = { clock = 0, stars = 5000, sun = 5, moon = 14, bodies = true },
	celestial = { clock = 19, stars = 3000, sun = 12, moon = 32, bodies = true },
	golden = { clock = 17, stars = 0, sun = 38, moon = 6, bodies = true },
	aurora = { clock = 1, stars = 4000, sun = 5, moon = 12, bodies = true },
	cosmic = { clock = 2, stars = 5000, sun = 3, moon = 48, bodies = true },
	dusk = { clock = 18.3, stars = 800, sun = 24, moon = 10, bodies = true },
	dawn = { clock = 5.8, stars = 500, sun = 28, moon = 8, bodies = true },
	eclipse = { clock = 13.5, stars = 2500, sun = 6, moon = 44, bodies = true },
	midnight = { clock = 0, stars = 2000, sun = 3, moon = 20, bodies = false },
	noon = { clock = 12, stars = 0, sun = 21, moon = 6, bodies = true },
}
local ids = {}
for id in THEMES do
	table.insert(ids, id)
end
table.sort(ids)

local SKY_PROPS = { "StarCount", "SunAngularSize", "MoonAngularSize", "CelestialBodiesShown" }

return {
	id = "SkyTheme",
	channels = { "sky" },
	group = "environment",
	cost = 5,
	gameplay = false,
	ownerOnly = false,
	themes = ids,
	params = {
		sky = { type = "enum", values = ids, default = "starfield" },
		-- -1 keeps the theme's own time of day
		clockTime = { type = "number", min = -1, max = 24, default = -1 },
	},
	start = function(ctx, p)
		local lighting = ctx.lighting
		local theme = THEMES[p.sky]
		local clockBefore = lighting.ClockTime
		local sky = lighting:FindFirstChildOfClass("Sky")
		local created = false
		local savedSky = {}
		if sky then
			for _, name in SKY_PROPS do
				savedSky[name] = (sky :: any)[name]
			end
		else
			sky = Instance.new("Sky")
			sky.Name = "OverlordSky"
			sky.Parent = lighting
			created = true
		end
		sky.StarCount = theme.stars
		sky.SunAngularSize = theme.sun
		sky.MoonAngularSize = theme.moon
		sky.CelestialBodiesShown = theme.bodies
		lighting.ClockTime = if p.clockTime >= 0 then p.clockTime else theme.clock
		return function()
			lighting.ClockTime = clockBefore
			if created then
				sky:Destroy()
			else
				for name, value in savedSky do
					(sky :: any)[name] = value
				end
			end
		end
	end,
}
