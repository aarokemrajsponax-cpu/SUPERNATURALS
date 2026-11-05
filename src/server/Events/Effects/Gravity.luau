-- Changes world gravity. Gameplay-changing: only in event mode and never while a match is
-- running. Restores the exact previous gravity on stop.
return {
	id = "Gravity",
	channels = { "gravity" },
	group = "gameplay",
	cost = 3,
	gameplay = true,
	ownerOnly = false,
	params = {
		-- fraction of the normal 196.2
		scale = { type = "number", min = 0.05, max = 1.5, default = 0.4 },
	},
	start = function(ctx, p)
		local ws = ctx.workspace
		local before = ws.Gravity
		ws.Gravity = before * p.scale
		return function()
			ws.Gravity = before
		end
	end,
}
