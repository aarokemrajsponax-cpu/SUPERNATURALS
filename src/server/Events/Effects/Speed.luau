-- Walk speed multiplier for event-mode participants. Skips players inside a match. Restores
-- each humanoid's own value (and ignores later respawns once stopped).
return {
	id = "Speed",
	channels = { "speed" },
	group = "gameplay",
	cost = 3,
	gameplay = true,
	ownerOnly = false,
	params = {
		multiplier = { type = "number", min = 0.4, max = 2.5, default = 1.5 },
	},
	start = function(ctx, p)
		local saved: { [any]: number } = {}
		local function apply(player)
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and saved[humanoid] == nil and not ctx.inMatch(player) then
				saved[humanoid] = humanoid.WalkSpeed
				humanoid.WalkSpeed = humanoid.WalkSpeed * p.multiplier
			end
		end
		for _, player in ctx.players() do
			apply(player)
		end
		local connection = ctx.onCharacter(function(player)
			apply(player)
		end)
		return function()
			if connection then
				connection:Disconnect()
			end
			for humanoid, speed in saved do
				pcall(function()
					humanoid.WalkSpeed = speed
				end)
			end
			table.clear(saved)
		end
	end,
}
