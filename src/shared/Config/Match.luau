-- Match rules for each mode. Times are in seconds.

local Match = {}

Match.Modes = {
	Duel = {
		DisplayName = "Duel",
		Description = "1v1. Most knockouts when time runs out wins.",
		MinPlayers = 2,
		MaxPlayers = 2,
		Countdown = 10,
		Duration = 180,
		-- "SuddenDeath": next knockout that breaks the tie wins. "Draw": ties end as a draw.
		TieRule = "SuddenDeath",
		SuddenDeathDuration = 60,
		-- Lowest a score can drop (nil = no limit)
		ScoreFloor = nil :: number?,
		ResultsDuration = 10,
	},
	FreeForAll = {
		DisplayName = "Free-for-All",
		Description = "3 or 4 fighters. Everyone for themselves.",
		MinPlayers = 3,
		MaxPlayers = 4,
		-- Once enough players are queued, wait this long for more before starting
		QueueFillDelay = 15,
		Countdown = 10,
		Duration = 240,
		TieRule = "SuddenDeath",
		SuddenDeathDuration = 60,
		ScoreFloor = nil :: number?,
		ResultsDuration = 10,
	},
	Practice = {
		DisplayName = "CPU Practice",
		Description = "Fight a CPU opponent with a power of your choice.",
		MinPlayers = 1,
		MaxPlayers = 1,
		-- Starts straight away for one player (no queue)
		Solo = true,
		-- Practice adds a CPU opponent so the player has someone to fight
		Dummies = 1,
		Countdown = 5,
		Duration = 120,
		TieRule = "Draw",
		SuddenDeathDuration = 0,
		ScoreFloor = nil :: number?,
		ResultsDuration = 8,
	},
}

-- Order modes appear in menus
Match.ModeOrder = { "Duel", "FreeForAll", "Practice" }

-- Arenas are built side by side so several matches can run at once
Match.Arena = {
	FirstCenter = Vector3.new(400, 0, 0),
	Spacing = 220,
	MaxSimultaneous = 6,
	Size = Vector3.new(110, 0, 110),
	WallHeight = 60,
	-- Falling this far below the floor is a knockout
	FallDepth = 25,
	-- Spawns stand this far in from each corner of the floor
	SpawnInset = 16,
	-- Scenery (terrain and props) stays inside this box around each arena's
	-- centre, so neighbouring slots never overlap and the lobby (x < 330) stays
	-- clear. Nothing else is built beyond the arenas on +X, so it can go far there.
	SceneryMin = Vector3.new(-64, -100, -108),
	SceneryMax = Vector3.new(200, 120, 108),
	-- Most parts one arena may use (the smoke test checks it)
	PartBudget = 450,
}

-- The arena themes players can pick, in menu order. "Random" picks one of these.
Match.ArenaOrder = { "ProvingGrounds", "RuinedFortress", "DigitalGrid", "CorruptedWastes", "SoulFoundry" }

Match.Arenas = {
	ProvingGrounds = {
		name = "Proving Grounds",
		description = "An old rune ring on a hilltop where new powers get tested.",
		color = Color3.fromRGB(96, 188, 204),
	},
	RuinedFortress = {
		name = "Ruined Fortress",
		description = "A castle courtyard with broken walls, rubble and braziers.",
		color = Color3.fromRGB(214, 142, 76),
	},
	DigitalGrid = {
		name = "Digital Grid",
		description = "Syntax's dimension. Glass floor, data cubes, hologram pillars.",
		color = Color3.fromRGB(64, 214, 222),
	},
	CorruptedWastes = {
		name = "Corrupted Wastes",
		description = "Black cracked earth, void crystals and shards hanging in the air.",
		color = Color3.fromRGB(152, 102, 222),
	},
	SoulFoundry = {
		name = "Soul Foundry",
		description = "Steel plates and catwalks around vents of blue soul fire.",
		color = Color3.fromRGB(92, 152, 255),
	},
}

-- The practice dummies area near spawn
Match.TrainingGround = {
	Center = Vector3.new(-90, 0, 0),
}

return Match
