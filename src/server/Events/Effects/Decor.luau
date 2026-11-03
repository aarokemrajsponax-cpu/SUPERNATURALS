-- Switches the seasonal decoration set (the SeasonalDecor system listens to the override).
-- Restores the previous override, so the calendar takes over again after the event.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Seasons = require(ReplicatedStorage.Shared.Seasons)
local ids = {}
for id in Seasons.Themes do
	table.insert(ids, id)
end
table.sort(ids)

return {
	id = "Decor",
	channels = { "season" },
	group = "environment",
	cost = 10,
	gameplay = false,
	ownerOnly = false,
	params = {
		season = { type = "enum", values = ids, default = ids[1] },
	},
	start = function(ctx, p)
		local holder = ctx.replicated
		local before = holder:GetAttribute("SeasonOverride")
		holder:SetAttribute("SeasonOverride", p.season)
		return function()
			holder:SetAttribute("SeasonOverride", before)
		end
	end,
}
