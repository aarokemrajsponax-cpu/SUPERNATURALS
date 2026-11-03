-- Player bases: tuning and catalogues (balance and layout numbers live here, not in code).
-- See src/server/Services/BaseService.luau for the rules and World/BaseStreet.luau,
-- World/BaseHome.luau for the geometry.
local rgb = Color3.fromRGB

local Homes = {}

-- Far from every other build (hub at 0,0,0; training at -236; concourse at x 560;
-- arena slots along z 0). The street runs along +X; bases sit in a row to the south.
Homes.StreetCenter = Vector3.new(3600, 0, 2800)
Homes.BaseOrigin = Vector3.new(3000, 0, 3400) -- slot 1; each later slot is +SlotSpacing in X
Homes.SlotSpacing = 90
Homes.Slots = 24 -- a base exists only for a player who is present; more players than this get no base
Homes.VaultDrop = 40 -- the vault floor sits this far below the home floor

-- Part budgets (enforced by tests/base_test.luau)
Homes.StreetPartBudget = 560
Homes.HomePartBudget = 430
Homes.VaultPartBudget = 330

-- Friend checks are cached so door presses never spam Roblox
Homes.FriendCacheSeconds = 300
-- Door, lift and tablet presses must come from near the prompt
Homes.PromptReach = 16

-- Decor themes. Each is a full palette; changing theme recolours the same parts.
Homes.DefaultTheme = "Walnut"
Homes.ThemeOrder = { "Walnut", "Linen", "Midnight" }
Homes.Themes = {
	Walnut = {
		name = "Walnut",
		blurb = "Warm wood, cognac leather, amber light",
		floor = { rgb(96, 62, 38), Enum.Material.WoodPlanks },
		wall = { rgb(214, 204, 188), Enum.Material.SmoothPlastic },
		panel = { rgb(70, 46, 30), Enum.Material.Wood },
		trim = { rgb(156, 122, 78), Enum.Material.Metal },
		sofa = { rgb(150, 82, 44), Enum.Material.Fabric },
		rug = { rgb(46, 52, 62), Enum.Material.Fabric },
		rugBorder = { rgb(224, 160, 74), Enum.Material.Fabric },
		lamp = rgb(255, 196, 120),
	},
	Linen = {
		name = "Linen",
		blurb = "Pale oak, sage fabric, soft daylight",
		floor = { rgb(176, 146, 108), Enum.Material.WoodPlanks },
		wall = { rgb(232, 230, 222), Enum.Material.SmoothPlastic },
		panel = { rgb(150, 124, 92), Enum.Material.Wood },
		trim = { rgb(138, 146, 156), Enum.Material.Metal },
		sofa = { rgb(118, 140, 120), Enum.Material.Fabric },
		rug = { rgb(214, 206, 188), Enum.Material.Fabric },
		rugBorder = { rgb(118, 140, 120), Enum.Material.Fabric },
		lamp = rgb(255, 226, 176),
	},
	Midnight = {
		name = "Midnight",
		blurb = "Slate, navy fabric, copper and a cool glow",
		floor = { rgb(46, 49, 56), Enum.Material.Slate },
		wall = { rgb(40, 52, 72), Enum.Material.SmoothPlastic },
		panel = { rgb(28, 34, 46), Enum.Material.Metal },
		trim = { rgb(184, 115, 63), Enum.Material.Metal },
		sofa = { rgb(44, 66, 104), Enum.Material.Fabric },
		rug = { rgb(24, 30, 42), Enum.Material.Fabric },
		rugBorder = { rgb(184, 115, 63), Enum.Material.Fabric },
		lamp = rgb(255, 178, 110),
	},
}

-- Display toggles (what the wall and vault show to visitors and to you)
Homes.ToggleOrder = { "mastery", "cosmetics", "premium" }
Homes.Toggles = {
	mastery = { label = "Mastery board", default = true },
	cosmetics = { label = "Cosmetics shelf", default = true },
	premium = { label = "Premium fighters", default = true },
}

-- Win milestones shown as trophies in the vault
Homes.WinMilestones = { 1, 10, 25, 50, 100, 250 }

-- Title ids to words (anything else is made readable from its id)
Homes.TitleNames = {
	title_recruit = "Recruit",
}

function Homes.titleName(id: string): string
	local known = Homes.TitleNames[id]
	if known then
		return known
	end
	local words = string.gsub(string.gsub(id, "^title_", ""), "_", " ")
	return (string.gsub(words, "(%a)(%w*)", function(first, rest)
		return string.upper(first) .. rest
	end))
end

return Homes
