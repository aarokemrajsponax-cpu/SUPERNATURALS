-- Owner-only showcase state: flight, immunity and the crown, through the same attributes the
-- owner panel uses (so the rest of the game already understands them). Restores the owner's
-- previous values on stop. Touches no inventory, ownership or progression.
local ATTRS = { fly = "SNCanFly", immune = "SNImmune", crown = "SNCrown" }

return {
	id = "OwnerShowcase",
	channels = { "ownerpower" },
	group = "player",
	cost = 2,
	gameplay = false,
	ownerOnly = true,
	params = {
		fly = { type = "bool", default = false },
		immune = { type = "bool", default = false },
		crown = { type = "bool", default = true },
	},
	start = function(ctx, p)
		local saved = {}
		for _, player in ctx.owners() do
			for key, attribute in ATTRS do
				saved[player] = saved[player] or {}
				saved[player][attribute] = player:GetAttribute(attribute)
				if p[key] then
					player:SetAttribute(attribute, true)
				end
			end
		end
		return function()
			for player, values in saved do
				for attribute, value in values do
					pcall(function()
						player:SetAttribute(attribute, value)
					end)
				end
			end
		end
	end,
}
