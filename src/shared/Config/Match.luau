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
}

-- The practice dummies area near spawn
Match.TrainingGround = {
	Center = Vector3.new(-90, 0, 0),
}

return Match
