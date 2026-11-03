-- Every achievement: plain goals, earned by playing. Nothing here is bought, rolled or timed.
-- AchievementService counts progress and saves it in profile.achievements ({ done, progress });
-- the Locker window shows the same numbers through Achievements.valueOf.
--
-- Fields: id, name, desc (one plain sentence), group (shown in the Locker), goal, kind and key
-- (where the number comes from, see valueOf), title (optional Cosmetics id given when it is
-- done) and notable (also announced to the whole server).
--
--   kind "stat"     profile.stats[key]                     (wins, matches, knockouts, bestStreak...)
--   kind "counter"  profile.achievements.progress[key]     (counted by AchievementService)
--   kind "mastery"  the highest mastery level of any fighter
--   kind "fighters" how many different fighters were used in a match
--   kind "lore"     how many Archive files were recovered

local Archive = require(script.Parent.Parent.Content.Archive)
local Powers = require(script.Parent.Parent.Powers)

local Achievements = {}

Achievements.Groups = { "Combat", "Mastery", "Training", "Exploration", "Social", "Seasonal" }

local archiveCount = 0
for _ in Archive.Files do
	archiveCount += 1
end

Achievements.List = {
	-- Combat
	{ id = "win_1", name = "First Win", desc = "Win a match.", group = "Combat", kind = "stat", key = "wins", goal = 1 },
	{ id = "win_10", name = "Ten Wins", desc = "Win 10 matches.", group = "Combat", kind = "stat", key = "wins", goal = 10 },
	{ id = "win_50", name = "Fifty Wins", desc = "Win 50 matches.", group = "Combat", kind = "stat", key = "wins", goal = 50, title = "title_veteran" },
	{ id = "win_250", name = "Two Hundred Fifty Wins", desc = "Win 250 matches.", group = "Combat", kind = "stat", key = "wins", goal = 250, title = "title_champion", notable = true },
	{ id = "match_25", name = "Regular", desc = "Play 25 matches.", group = "Combat", kind = "stat", key = "matches", goal = 25 },
	{ id = "match_100", name = "Seasoned", desc = "Play 100 matches.", group = "Combat", kind = "stat", key = "matches", goal = 100 },
	{ id = "ko_25", name = "Twenty-Five Knockouts", desc = "Knock out 25 fighters.", group = "Combat", kind = "stat", key = "knockouts", goal = 25 },
	{ id = "ko_250", name = "Two Hundred Fifty Knockouts", desc = "Knock out 250 fighters.", group = "Combat", kind = "stat", key = "knockouts", goal = 250, title = "title_breaker" },
	{ id = "streak_3", name = "Three in a Row", desc = "Win 3 matches in a row.", group = "Combat", kind = "stat", key = "bestStreak", goal = 3 },
	{ id = "streak_5", name = "Five in a Row", desc = "Win 5 matches in a row.", group = "Combat", kind = "stat", key = "bestStreak", goal = 5, title = "title_streak" },
	{ id = "streak_10", name = "Ten in a Row", desc = "Win 10 matches in a row.", group = "Combat", kind = "stat", key = "bestStreak", goal = 10, title = "title_unbroken" },
	{ id = "clean_1", name = "Untouched", desc = "Win a match without being knocked out.", group = "Combat", kind = "counter", key = "cleanWins", goal = 1 },
	{ id = "clean_10", name = "Ten Clean Wins", desc = "Win 10 matches without being knocked out.", group = "Combat", kind = "counter", key = "cleanWins", goal = 10, title = "title_precise" },
	{ id = "duel_5", name = "Duelist", desc = "Win 5 duels against other players.", group = "Combat", kind = "counter", key = "duelWins", goal = 5, title = "title_duelist" },
	{ id = "ffa_3", name = "Last One Standing", desc = "Win 3 free-for-all matches against other players.", group = "Combat", kind = "counter", key = "ffaWins", goal = 3 },

	-- Mastery
	{ id = "mastery_5", name = "Getting Serious", desc = "Reach mastery level 5 with any fighter.", group = "Mastery", kind = "mastery", goal = 5 },
	{ id = "mastery_10", name = "Double Digits", desc = "Reach mastery level 10 with any fighter.", group = "Mastery", kind = "mastery", goal = 10, title = "title_adept", notable = true },
	{ id = "mastery_20", name = "Fully Mastered", desc = "Reach mastery level 20 with any fighter.", group = "Mastery", kind = "mastery", goal = 20, title = "title_master", notable = true },
	{ id = "fighters_3", name = "Three Fighters", desc = "Fight a match with 3 different fighters.", group = "Mastery", kind = "fighters", goal = 3 },
	{ id = "fighters_all", name = "Every Fighter", desc = "Fight a match with all eight fighters.", group = "Mastery", kind = "fighters", goal = #Powers.Order, title = "title_all_rounder" },

	-- Training
	{ id = "practice_1", name = "First Practice", desc = "Finish a practice round with Jeffery.", group = "Training", kind = "counter", key = "practiceRounds", goal = 1 },
	{ id = "practice_10", name = "Ten Practice Rounds", desc = "Finish 10 practice rounds with Jeffery.", group = "Training", kind = "counter", key = "practiceRounds", goal = 10, title = "title_trainee" },
	{ id = "practice_win_5", name = "Practice Pays Off", desc = "Win 5 practice rounds.", group = "Training", kind = "counter", key = "practiceWins", goal = 5 },
	{ id = "cpu_win_5", name = "Beat the Machines", desc = "Win 5 matches against the computer.", group = "Training", kind = "counter", key = "cpuWins", goal = 5 },

	-- Exploration
	{ id = "lore_1", name = "First File", desc = "Recover an Archive file.", group = "Exploration", kind = "lore", goal = 1 },
	{ id = "lore_10", name = "Ten Files", desc = "Recover 10 Archive files.", group = "Exploration", kind = "lore", goal = math.min(10, archiveCount) },
	{ id = "lore_all", name = "The Whole Archive", desc = "Recover every Archive file.", group = "Exploration", kind = "lore", goal = archiveCount, title = "title_archivist", notable = true },
	{ id = "hour_1", name = "An Hour Inside", desc = "Spend an hour in the facility.", group = "Exploration", kind = "stat", key = "playSeconds", goal = 3600, unit = "seconds" },

	-- Social
	{ id = "watch_1", name = "In the Stands", desc = "Watch a match from the Spectating Lounge.", group = "Social", kind = "counter", key = "watched", goal = 1 },
	{ id = "watch_10", name = "Regular Spectator", desc = "Watch 10 matches from the Spectating Lounge.", group = "Social", kind = "counter", key = "watched", goal = 10, title = "title_spectator" },
	{ id = "base_1", name = "Guest", desc = "Visit another player's base.", group = "Social", kind = "counter", key = "baseVisits", goal = 1 },
	{ id = "base_5", name = "Good Neighbour", desc = "Visit 5 bases of other players.", group = "Social", kind = "counter", key = "baseVisits", goal = 5, title = "title_neighbour" },
	{ id = "predict_1", name = "Called It", desc = "Predict the winner of a match you watched.", group = "Social", kind = "stat", key = "predictionsCorrect", goal = 1 },
	{ id = "predict_10", name = "Good Eye", desc = "Predict the winner 10 times.", group = "Social", kind = "stat", key = "predictionsCorrect", goal = 10 },

	-- Seasonal
	{ id = "season_1", name = "In Season", desc = "Play a match while a seasonal decoration is up in the facility.", group = "Seasonal", kind = "counter", key = "seasonMatches", goal = 1 },
	{ id = "season_5", name = "Seasonal Regular", desc = "Play 5 matches during seasonal decorations.", group = "Seasonal", kind = "counter", key = "seasonMatches", goal = 5, title = "title_seasonal" },
}

Achievements.ById = {} :: { [string]: { [string]: any } }
for _, def in Achievements.List do
	assert(Achievements.ById[def.id] == nil, "duplicate achievement " .. def.id)
	assert(def.goal >= 1, def.id .. " needs a goal")
	Achievements.ById[def.id] = def
end

function Achievements.get(id: any): { [string]: any }?
	return if typeof(id) == "string" then Achievements.ById[id] else nil
end

-- The counters AchievementService keeps (progress keys)
Achievements.Counters = { "cleanWins", "duelWins", "ffaWins", "cpuWins", "practiceRounds", "practiceWins", "watched", "baseVisits", "seasonMatches" }

local function count(set: any): number
	local n = 0
	if typeof(set) == "table" then
		for _ in set do
			n += 1
		end
	end
	return n
end

-- The current number toward an achievement's goal, read from a profile (or the client's copy)
function Achievements.valueOf(def: { [string]: any }, profile: { [string]: any }): number
	local kind = def.kind
	local value = 0
	if kind == "stat" then
		value = (profile.stats and profile.stats[def.key]) or 0
	elseif kind == "counter" then
		value = (profile.achievements and profile.achievements.progress and profile.achievements.progress[def.key]) or 0
	elseif kind == "mastery" then
		for _, entry in profile.powers or {} do
			value = math.max(value, Powers.masteryLevel(entry and entry.xp))
		end
	elseif kind == "fighters" then
		local progress = profile.achievements and profile.achievements.progress or {}
		for _, id in Powers.Order do
			if (progress["used_" .. id] or 0) > 0 then
				value += 1
			end
		end
	elseif kind == "lore" then
		value = count(profile.lore and profile.lore.found)
	end
	if typeof(value) ~= "number" or value ~= value then
		return 0
	end
	return math.max(0, value)
end

function Achievements.isDone(def: { [string]: any }, profile: { [string]: any }): boolean
	return (profile.achievements and profile.achievements.done and profile.achievements.done[def.id] == true) or false
end

-- Numbers shown in lists: seconds become minutes or hours
function Achievements.format(def: { [string]: any }, value: number): string
	if def.unit == "seconds" then
		return string.format("%d min", math.floor(value / 60))
	end
	return tostring(math.floor(value))
end

return Achievements
