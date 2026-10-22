-- What fighting earns: Money, Gems and mastery XP for the power you used, plus
-- daily challenges. Rewards are paid by the game (never wagered between
-- players), most of them come from taking part rather than only winning, and
-- the anti-farming rules below stop idle or repeated-match abuse.

local Rewards = {}

Rewards.Match = {
	-- Everyone who took part
	Participation = { money = 30, xp = 40 },
	Win = { money = 60, xp = 40 },
	Draw = { money = 30, xp = 20 },
	PerKnockout = { money = 10, xp = 15 },
	-- Knockouts past this many in one match don't pay more
	MaxKnockouts = 8,
	-- 1 XP per this much damage dealt, up to MaxDamageXp
	DamagePerXp = 10,
	MaxDamageXp = 60,
	-- The first win each day (UTC) also gives Gems
	FirstWinOfDayGems = 10,
	-- Each mastery level reached gives Gems
	LevelUpGems = 5,
	-- Share of the Money and XP each mode pays
	ModeShare = { Duel = 1, FreeForAll = 1.15, Practice = 0.5 },
	-- CPU practice pays more against harder CPUs
	CpuShare = { Easy = 0.5, Normal = 1, Hard = 1.4 },
	-- A correct (free) spectator prediction
	PredictionMoney = 15,
}

-- Anti-farming
Rewards.Limits = {
	-- Matches shorter than this pay nothing (e.g. an opponent leaving straight away)
	MinFightSeconds = 25,
	-- Do at least this much in a match to be paid (idle players get nothing)
	MinDamage = 8,
	MinActions = 3,
	-- After this many rewarded matches in an hour, rewards drop to ReducedShare
	HourlyFullRewards = 12,
	ReducedShare = 0.25,
	-- The same two players dueling over and over pay half after this many in the window
	SameOpponentLimit = 4,
	SameOpponentWindow = 1800,
	SameOpponentShare = 0.5,
}

-- Daily challenges: three a day from this pool, the same for everyone that day.
-- `stat` is what counts toward `goal`.
Rewards.DailyCount = 3
Rewards.DailyPool = {
	{ id = "Win2", text = "Win 2 matches", stat = "wins", goal = 2, reward = { money = 150 } },
	{ id = "Play3", text = "Play 3 matches", stat = "matches", goal = 3, reward = { money = 120 } },
	{ id = "KO5", text = "Knock out 5 fighters", stat = "knockouts", goal = 5, reward = { money = 140 } },
	{ id = "Hits60", text = "Land 60 hits", stat = "hits", goal = 60, reward = { money = 110 } },
	{ id = "Abilities20", text = "Use 20 abilities", stat = "abilities", goal = 20, reward = { money = 120 } },
	{ id = "Perfect3", text = "Get 3 perfect defenses", stat = "perfects", goal = 3, reward = { gems = 8 } },
	{ id = "Escape2", text = "Break free from 2 grabs", stat = "escapes", goal = 2, reward = { money = 100 } },
	{ id = "Ultimate2", text = "Land 2 ultimates", stat = "ultimates", goal = 2, reward = { gems = 6 } },
	{ id = "Damage1500", text = "Deal 1,500 damage", stat = "damage", goal = 1500, reward = { money = 160 } },
	{ id = "CpuHard", text = "Beat a Hard CPU", stat = "hardCpuWins", goal = 1, reward = { gems = 10 } },
}

-- Logging in on consecutive days
Rewards.LoginStreak = {
	-- Money for day 1, 2, 3... (the last value repeats)
	Money = { 50, 75, 100, 125, 150, 175, 200 },
	-- Every 7th day in a row also gives Gems
	WeeklyGems = 20,
}

return Rewards
