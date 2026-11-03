-- Fog, haze and glow. Edits the place's Atmosphere when there is one (restoring it), else
-- adds one and removes it on stop.
local Env = require(script.Parent.Parent.Env)
local rgb = Env.rgb
local MOODS = {
	clear = { rgb(190, 205, 225), rgb(160, 175, 200), 0.1, 0 },
	hazy = { rgb(200, 195, 190), rgb(180, 175, 170), 0.35, 1.2 },
	dense_fog = { rgb(200, 205, 210), rgb(190, 195, 200), 0.6, 2.2 },
	glow = { rgb(255, 230, 190), rgb(255, 200, 140), 0.3, 3 },
	dusty_gold = { rgb(255, 205, 130), rgb(210, 160, 90), 0.4, 1.6 },
	icy = { rgb(200, 230, 255), rgb(170, 210, 245), 0.38, 1.4 },
	void = { rgb(15, 10, 30), rgb(25, 15, 50), 0.55, 0.4 },
	neon_haze = { rgb(255, 90, 220), rgb(60, 220, 255), 0.42, 2.6 },
	ember_smoke = { rgb(120, 60, 40), rgb(80, 40, 30), 0.5, 1.8 },
}
local ids = {}
for id in MOODS do
	table.insert(ids, id)
end
table.sort(ids)
local PROPS = { "Color", "Decay", "Density", "Haze", "Glare", "Offset" }

return {
	id = "Atmosphere",
	channels = { "atmosphere" },
	group = "environment",
	cost = 5,
	gameplay = false,
	ownerOnly = false,
	moods = ids,
	params = {
		mood = { type = "enum", values = ids, default = "hazy" },
		density = { type = "number", min = 0, max = 0.8, default = 0.3, scales = true },
	},
	start = function(ctx, p)
		local lighting = ctx.lighting
		local atmosphere = lighting:FindFirstChildOfClass("Atmosphere")
		local created = false
		local restore
		if atmosphere then
			restore = Env.capture(atmosphere, PROPS)
		else
			atmosphere = Instance.new("Atmosphere")
			atmosphere.Name = "OverlordAtmosphere"
			atmosphere.Parent = lighting
			created = true
		end
		local mood = MOODS[p.mood]
		atmosphere.Color = mood[1]
		atmosphere.Decay = mood[2]
		atmosphere.Density = math.clamp(p.density * (0.5 + mood[3]), 0, 0.8)
		atmosphere.Haze = mood[4]
		atmosphere.Glare = if mood[4] > 2 then 0.6 else 0
		return function()
			if created then
				atmosphere:Destroy()
			elseif restore then
				restore()
			end
		end
	end,
}
