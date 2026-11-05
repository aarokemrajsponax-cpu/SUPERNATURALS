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
Homes.GameRoomPartBudget = 350

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

-- Hosting (BaseService; DECISIONS 62) -----------------------------------------------------------
-- Who may come in. "Friends" is the default and is what every old profile reads.
Homes.AccessOrder = { "Friends", "Everyone", "Nobody" }
Homes.AccessModes = {
	Friends = { label = "Friends", blurb = "Your Roblox friends can come in." },
	Everyone = { label = "Open house", blurb = "Anyone on this server can come in." },
	Nobody = { label = "Just me", blurb = "The door stays shut to everyone else." },
}
Homes.VisitorsKept = 8 -- the board shows the last 8 visitors
Homes.AskLeaveCooldown = 3 -- seconds between "ask to leave" requests from one owner
Homes.AskLeaveBar = 120 -- seconds a visitor who was asked to leave cannot come back in
-- Host bonus: the first time each UTC day that a Roblox friend stays this long, the owner gets Money
Homes.HostBonusSeconds = 60
Homes.HostBonusMoney = 25
Homes.PresenceTick = 2 -- seconds between the server's presence checks

-- Game room activities --------------------------------------------------------------------------
-- Rewards are small and only for the first valid play of each activity per UTC day
Homes.ActivityOrder = { "PowerMeter", "Reflex" }
Homes.Activities = {
	PowerMeter = { label = "Power Meter", dailyMoney = 10 },
	Reflex = { label = "Reflex Cabinet", dailyMoney = 10 },
}
-- Power Meter: the needle rises and falls in a triangle wave; one full up and down is `period`
-- seconds. The server starts the run on the first press and scores the second press from its
-- own clock: score = round(100 * triangle(elapsed / period)). A run left alone ends after `timeout`.
Homes.PowerMeter = { period = 1.6, timeout = 6, startupGrace = 0 }
-- Reflex cabinet: a random wait before "go". The reaction is measured on the server from the
-- moment "go" was sent to the moment the press arrived, minus the player's round-trip ping
-- (capped at latencyCapMs so a bad connection cannot hide a slow reaction), never below minMs.
Homes.Reflex = { waitMin = 1.5, waitMax = 4, latencyCapMs = 150, minMs = 120, timeout = 6 }

function Homes.powerMeterScore(elapsed: number, period: number): number
	local phase = (elapsed / period) % 1
	local height = if phase < 0.5 then phase * 2 else (1 - phase) * 2
	return math.clamp(math.floor(height * 100 + 0.5), 0, 100)
end

-- The jukebox: the base owner picks one AudioLibrary category for the whole base
Homes.MusicStyles = { "Chill", "Pop", "Electronic", "Classical", "Phonk", "Rock", "Funny", "SciFi" }
Homes.DefaultMusic = "Chill"

-- Party mode (free): the room lights and dance floor run a slow colour cycle
Homes.PartyStep = 0.02 -- hue step per tick
Homes.PartyTick = 0.3 -- seconds

-- Cosmetic base effects, unlocked by the Base Effects Pack pass (Monetization.Passes.BaseEffectsPack).
-- Looks only: no stats, nothing random, no timers. Each one is switched on or off by the owner.
Homes.EffectsPass = "BaseEffectsPack"
Homes.EffectOrder = { "Aurora", "Snowfall", "Fireplace", "LightShow", "Fireflies" }
Homes.Effects = {
	Aurora = { label = "Aurora", blurb = "Soft green and violet ribbons drift across the home ceiling." },
	Snowfall = { label = "Indoor snowfall", blurb = "Gentle snow falls by the big window." },
	Fireplace = { label = "Ember fireplace", blurb = "A crackling fire with rising embers in the game room." },
	LightShow = { label = "Dance floor light show", blurb = "Coloured beams sweep over the game room dance floor." },
	Fireflies = { label = "Fireflies", blurb = "Warm lights drift through the home." },
}

-- Fireworks Show (developer product, Monetization.Products.FireworksShow): each purchase saves one
-- charge; the owner launches a show from the base panel whenever they like.
Homes.FireworksSeconds = 45
Homes.FireworksMaxCharges = 20
Homes.FireworksShotEvery = 1.1

-- The game room is joined to the south wall of the home; these bounds say who is "in the base"
Homes.InsideX = 30
Homes.InsideZMin = -34
Homes.InsideZMax = 52

return Homes
