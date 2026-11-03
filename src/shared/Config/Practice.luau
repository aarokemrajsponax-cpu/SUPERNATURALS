-- Jeffery's practice fights in the Training Studio: the modes, the environment themes, the
-- limits, and the rules that turn a fight's real numbers into his feedback. Pure data and
-- pure functions (no Roblox services), so tests can feed numbers and read the lines back.
-- Balance and wording changes go here, not in PracticeService.

local Practice = {}

Practice.ModeOrder = { "Beginner", "Intermediate", "Advanced", "Custom" }

-- style = the powers Jeffery plays (Advanced rotates through them every StyleSeconds)
-- profile = the CpuService behaviour profile; difficulty = a CpuService difficulty
Practice.Modes = {
	Beginner = {
		label = "Beginner",
		summary = "Slow and predictable. Jeffery shows the basics: attacks, then a gap for you to answer.",
		difficulty = "Easy", profile = "Beginner", duration = 60, styles = { "StrongDude" }, abilities = false, hints = true,
	},
	Intermediate = {
		label = "Intermediate",
		summary = "Varied movement and timing. Jeffery circles, feints a little and uses cues you can read.",
		difficulty = "Normal", profile = "Intermediate", duration = 90, styles = { "Ghost" }, abilities = true, hints = true,
	},
	Advanced = {
		label = "Advanced",
		summary = "Combinations, defensive timing and several fighting styles in one round.",
		difficulty = "Hard", profile = "Advanced", duration = 120, styles = { "StrongDude", "Ghost", "Shapeshifter", "MachineMaster" },
		abilities = true, hints = false,
	},
	Custom = {
		label = "Custom",
		summary = "Pick the difficulty, behaviour, length, abilities, environment and hints yourself.",
		difficulty = "Normal", profile = "Balanced", duration = 90, styles = { "StrongDude" }, abilities = true, hints = true,
	},
}

Practice.CustomChoices = {
	difficulty = { "Easy", "Normal", "Hard" },
	behavior = { "Balanced", "Aggressive", "Defensive", "Evasive" },
	duration = { 30, 60, 90, 120, 180 },
}

-- Rules of a round
Practice.StyleSeconds = 30 -- Advanced: Jeffery changes style this often
Practice.EndHealthShare = 0.15 -- a round ends when either side is down to this share of health
Practice.StartGap = 1.2 -- seconds of calm before Jeffery moves
Practice.MaxPerFloor = 1
Practice.RequestCooldown = 0.5 -- per player, between start/stop requests
Practice.Version = 1

-- A used ability counts as "too far" when Jeffery was further than its range by this many studs
Practice.RangeSlack = 4
-- A combo continues while hits land within this many seconds of each other
Practice.ComboGap = 1.6
-- DPS is the damage dealt in this many seconds, divided by it
Practice.DpsWindow = 5
-- Below this many seconds there is not enough to judge, so no analysis is given
Practice.MinAnalysisSeconds = 10

-- In-fight hints: short, each at most once per round, never closer together than HintGap
Practice.HintGap = 12
Practice.MaxHints = 5
Practice.Hints = {
	start_Beginner = "Hit me with basic attacks. I am slow on purpose. Block when I raise my arm.",
	start_Intermediate = "I will move around and change my timing. Watch my feet before you strike.",
	start_Advanced = "No more warm-ups. I chain attacks and switch styles. Defend first.",
	start_Custom = "Your rules. Press Restart or Exit whenever you like.",
	idle = "No hits yet. Close the distance and use basic attacks first.",
	grabbed = "That was a grab. Blocking does not stop it, so dodge or keep out of arm's reach.",
	low = "Your health is low. Block, or back away and reset.",
	no_block = "You are taking hits without blocking. Hold block when I wind up.",
}

-- Environment themes for the sparring floor. "Studio" is the clean default. The others borrow the
-- look of the matching battleground chamber (Config/Match Arenas ids).
Practice.ThemeOrder = { "Studio", "ProvingGrounds", "RuinedFortress", "DigitalGrid", "CorruptedWastes", "SoulFoundry" }
Practice.Themes = {
	Studio = { name = "Studio", floor = Color3.fromRGB(46, 50, 58), material = Enum.Material.DiamondPlate, accent = Color3.fromRGB(63, 214, 232), light = Color3.fromRGB(232, 240, 250) },
	ProvingGrounds = { name = "Proving Grounds", floor = Color3.fromRGB(138, 134, 124), material = Enum.Material.Slate, accent = Color3.fromRGB(120, 222, 236), light = Color3.fromRGB(255, 244, 222) },
	RuinedFortress = { name = "Ruined Fortress", floor = Color3.fromRGB(108, 100, 92), material = Enum.Material.Cobblestone, accent = Color3.fromRGB(255, 160, 80), light = Color3.fromRGB(255, 190, 120) },
	DigitalGrid = { name = "Digital Grid", floor = Color3.fromRGB(30, 44, 58), material = Enum.Material.Glass, accent = Color3.fromRGB(70, 220, 230), light = Color3.fromRGB(150, 235, 245) },
	CorruptedWastes = { name = "Corrupted Wastes", floor = Color3.fromRGB(34, 28, 40), material = Enum.Material.Basalt, accent = Color3.fromRGB(152, 102, 222), light = Color3.fromRGB(190, 150, 255) },
	SoulFoundry = { name = "Soul Foundry", floor = Color3.fromRGB(100, 104, 108), material = Enum.Material.CorrodedMetal, accent = Color3.fromRGB(92, 152, 255), light = Color3.fromRGB(200, 224, 255) },
}

function Practice.isTheme(id: any): boolean
	return typeof(id) == "string" and Practice.Themes[id] ~= nil
end

-- Clean, validated options for a round from a request (anything wrong falls back to the mode's own)
function Practice.resolve(modeId: any, options: any): (string, { [string]: any })
	local id = if typeof(modeId) == "string" and Practice.Modes[modeId] then modeId else "Beginner"
	local mode = Practice.Modes[id]
	local resolved = {
		mode = id,
		difficulty = mode.difficulty,
		profile = mode.profile,
		duration = mode.duration,
		styles = mode.styles,
		abilities = mode.abilities,
		hints = mode.hints,
		theme = "Studio",
	}
	if typeof(options) == "table" then
		if Practice.isTheme(options.theme) then
			resolved.theme = options.theme
		end
		if typeof(options.hints) == "boolean" then
			resolved.hints = options.hints
		end
		if id == "Custom" then
			if table.find(Practice.CustomChoices.difficulty, options.difficulty) then
				resolved.difficulty = options.difficulty
			end
			if table.find(Practice.CustomChoices.behavior, options.behavior) then
				resolved.profile = options.behavior
			end
			if table.find(Practice.CustomChoices.duration, options.duration) then
				resolved.duration = options.duration
			end
			if typeof(options.abilities) == "boolean" then
				resolved.abilities = options.abilities
			end
		end
	end
	return id, resolved
end

-- Feedback ------------------------------------------------------------------------------------
-- stats = { mode, outcome = "Won" | "Lost" | "Time" | "Exited", seconds, hitsLanded, hitsTaken,
--   blocks, perfectDefences, grabsSuffered, maxCombo, abilitiesUsed, abilitiesOutOfRange,
--   damageDealt, damageTaken, abilitiesOn }; previous = the same for the player's last round
-- Each rule only fires on the numbers it names. Higher priority first; at most MaxSpecific are said.

Practice.MaxSpecific = 2

local function defenceRate(stats): number
	local faced = stats.hitsTaken + stats.blocks + stats.perfectDefences
	if faced <= 0 then
		return 0
	end
	return (stats.blocks + stats.perfectDefences) / faced
end

Practice.Rules = {
	{ id = "range", priority = 90, test = function(s) return s.abilitiesOutOfRange >= 1 end,
		line = function(_s) return "You used that ability before your opponent was within range. Let's try that again." end },
	{ id = "defence_improved", priority = 85, test = function(s, p)
			return p ~= nil and p.seconds >= Practice.MinAnalysisSeconds and (s.blocks + s.perfectDefences) >= 2 and defenceRate(s) >= defenceRate(p) + 0.1
		end,
		line = function(_s) return "Good timing! Your defense has improved." end },
	{ id = "perfect", priority = 80, test = function(s) return s.perfectDefences >= 1 end,
		line = function(s) return `You pulled off {s.perfectDefences} perfect defence{if s.perfectDefences == 1 then "" else "s"}. That is the hardest timing in the game.` end },
	{ id = "grabbed", priority = 75, test = function(s) return s.grabsSuffered >= 1 end,
		line = function(s) return `You were grabbed {if s.grabsSuffered == 1 then "once" else s.grabsSuffered .. " times"}. Blocking does not stop a grab, so dodge or stay out of arm's reach.` end },
	{ id = "no_block", priority = 70, test = function(s) return s.blocks == 0 and s.perfectDefences == 0 and s.hitsTaken >= 5 end,
		line = function(s) return `You took {s.hitsTaken} hits without blocking once. Hold block when Jeffery winds up.` end },
	{ id = "combo", priority = 60, test = function(s) return s.maxCombo >= 4 end,
		line = function(s) return `Your longest combo was {s.maxCombo} hits. That is solid.` end },
	{ id = "single_hits", priority = 55, test = function(s) return s.maxCombo <= 1 and s.hitsLanded >= 3 end,
		line = function(_s) return "Your hits landed one at a time. Try chaining the next attack before the stun ends." end },
	{ id = "no_hits", priority = 65, test = function(s) return s.hitsLanded == 0 and s.seconds >= 20 end,
		line = function(_s) return "No hits landed this round. Close the distance and start with basic attacks." end },
	{ id = "untouched", priority = 50, test = function(s) return s.hitsTaken == 0 and s.hitsLanded >= 1 and s.seconds >= 20 end,
		line = function(_s) return "Jeffery did not land a single hit on you. Nicely kept distance." end },
	{ id = "no_ability", priority = 40, test = function(s) return s.abilitiesUsed == 0 and s.seconds >= 20 and s.abilitiesOn end,
		line = function(_s) return "You did not use an ability this round. Try one from your ability bar next time." end },
}

local OUTCOME_LINES = {
	Won = "You won that round. Nothing was at stake, but the technique was real.",
	Lost = "Jeffery landed more this time. That is what practice is for, so let us look at the numbers.",
	Time = "Time ran out with both of us still standing.",
	Exited = "Ending early is fine. Nothing here counts against you.",
}

-- The mode to recommend next, by rule
function Practice.recommend(stats): string
	local mode = stats.mode
	local won = stats.outcome == "Won"
	if mode == "Beginner" then
		if won and stats.hitsLanded >= 5 then
			return "Intermediate"
		end
		return "Beginner"
	elseif mode == "Intermediate" then
		if won and stats.hitsLanded >= 6 then
			return "Advanced"
		end
		if stats.outcome == "Lost" and stats.hitsLanded < 3 then
			return "Beginner"
		end
		return "Intermediate"
	elseif mode == "Advanced" then
		if won then
			return "Custom"
		end
		if stats.outcome == "Lost" and stats.hitsLanded < 3 then
			return "Intermediate"
		end
		return "Advanced"
	end
	return "Custom"
end

-- Returns { lines = { string }, face = string, next = string, rules = { id } }
function Practice.feedback(stats, previous)
	local lines = { OUTCOME_LINES[stats.outcome] or OUTCOME_LINES.Time }
	local rules = {}
	local nextMode = Practice.recommend(stats)
	if stats.outcome ~= "Exited" and stats.seconds >= Practice.MinAnalysisSeconds then
		local matched = {}
		for _, rule in Practice.Rules do
			if rule.test(stats, previous) then
				table.insert(matched, rule)
			end
		end
		table.sort(matched, function(a, b)
			return a.priority > b.priority
		end)
		for index = 1, math.min(#matched, Practice.MaxSpecific) do
			table.insert(lines, matched[index].line(stats))
			table.insert(rules, matched[index].id)
		end
	end
	local label = Practice.Modes[nextMode].label
	if stats.outcome == "Exited" then
		table.insert(lines, `Whenever you are ready, {label} mode is waiting.`)
	elseif nextMode == stats.mode then
		table.insert(lines, `My suggestion: run {label} again and watch for the points above.`)
	else
		table.insert(lines, `My suggestion for next time: {label} mode.`)
	end
	local face = if stats.outcome == "Won" then "proud" else "thinking"
	return { lines = lines, face = face, next = nextMode, rules = rules }
end

return Practice
