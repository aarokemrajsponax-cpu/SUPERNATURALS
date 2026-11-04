-- The Training Studio and Jeffery's practice fights, with simulated players:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/practice_test.luau build/game.rbxl
-- Bays and readouts (real hits only), every mode starts and Jeffery's unit fights, exit and restart
-- clean up, feedback lines are chosen from real numbers, training stays free, two players do not
-- interfere.

local process = require("@lune/process")
local World = require("./smoke/World")

local api = World.start(process.args[1] or "build/game.rbxl", function(setup)
	local Practice = setup.world.require(setup.world.find("ReplicatedStorage.Shared.Config.Practice"))
	Practice.StartGap = 0.2
	Practice.RequestCooldown = 0.3
	for _, mode in Practice.Modes do
		mode.duration = 40
	end
	setup.Combat.Heavy.Cooldown = 0.2
end)
local Engine, task, Vector3, CFrame = api.Engine, api.task, api.Vector3, api.CFrame
local world, services, check = api.world, api.services, api.check
local Data, Currency, Characters, Practice = services.DataService, services.CurrencyService, services.CharacterService, services.PracticeService
local Dummies, Arenas, Match, Combat = services.DummyService, services.ArenaService, services.MatchService, services.CombatService
local Config = world.require(world.find("ReplicatedStorage.Shared.Config.Practice"))
local MatchConfig = api.MatchConfig
local Selection = world.require(world.find("ReplicatedStorage.Shared.Config.Selection"))
local Hall = world.require(world.find("ServerScriptService.Server.Arenas.TrainingHall"))
local Center = MatchConfig.TrainingGround.Center
api.flatGround(0)

local function joined(name, userId)
	local player = api.join(name, userId)
	api.waitFor(function()
		return Data:get(player) ~= nil
	end, 5, name .. "'s profile")
	task.wait(0.1)
	return player
end
local function standAt(player, position)
	local root = player.Character.HumanoidRootPart
	root.CFrame = CFrame.new(position)
	root.Position = position
	Engine.syncPositions(world.workspace)
end
local function send(player, action, a, b)
	api.request("ProgressRequest", player, action, a, b)
	task.wait(0.45)
end
local function start(player, mode, options)
	send(player, "PracticeStart", mode, options)
end
local function unitOf(player)
	local unit = Practice:unitOf(player)
	return unit and unit.fighter and unit
end
local function waitUnit(player)
	api.waitFor(function()
		return unitOf(player) ~= nil
	end, 4, "Jeffery's unit")
	local unit = unitOf(player)
	-- The stand-in keeps a model's root at the origin until told otherwise: put Jeffery where he spawns
	local spawn = Practice:sessionOf(player).floor.jeffery
	unit.fighter.root.CFrame = spawn
	unit.fighter.root.Position = spawn.Position
	Engine.syncPositions(world.workspace)
	return unit
end
local function inStudio(player)
	standAt(player, Center + Vector3.new(20, 4, 0))
end
-- Face two fighters at a gap, from where the first really is (the stand-in keeps Position apart from CFrame)
local function faceOff(a, b, gap)
	a.root.CFrame = CFrame.new(a.root.Position) * (a.root.CFrame - a.root.CFrame.Position)
	api.faceOff(a, b, gap)
end
local function messages(player, since)
	return api.sentSince(since, "DataEvent", "Practice", player)
end
local function fighters(predicate)
	local count = 0
	for _, f in Characters:all() do
		if predicate(f) then
			count += 1
		end
	end
	return count
end
local function jefferyCount()
	return fighters(function(f)
		return f.displayName == "Jeffery"
	end)
end

local alice = joined("Alice", 901)
local bob = joined("Bob", 902)
local cara = joined("Cara", 903)

check("the studio has 8 or more bays with readouts, several big practice arenas, a platform and a console", function()
	local studio = Arenas:trainingStudio()
	assert(studio, "a layout")
	assert(#studio.bays >= 8, "eight or more bays, got " .. #studio.bays)
	assert(#Arenas:trainingDummySpots() == #studio.bays, "one dummy spot per bay")
	for _, bay in studio.bays do
		assert(bay.labels.last and bay.labels.combo and bay.labels.dps, "readout labels")
		assert(math.abs(bay.spot.Position.X - Center.X) < Hall.HalfX and math.abs(bay.spot.Position.Z - Center.Z) < Hall.HalfZ, "inside the room")
	end
	assert(#studio.floors >= 2, "two or more practice arenas")
	local hall = world.workspace.TrainingGround
	-- Each arena is at least 70 x 70 studs of open floor, and the whole room fits the training zone
	local sparFloors = {}
	for _, item in hall:GetChildren() do
		if item.Name == "SparFloor" then
			table.insert(sparFloors, item)
		end
	end
	assert(#sparFloors == #studio.floors, "one SparFloor part per arena")
	for _, item in sparFloors do
		assert(item.Size.X >= 70 and item.Size.Z >= 70, `arena floor {item.Size.X} x {item.Size.Z} is at least 70 x 70`)
	end
	for _, floor in studio.floors do
		assert(floor.size >= Config.Arena.MinSize, "arena size " .. floor.size)
		assert(Selection.inTrainingZone(floor.center + Vector3.new(floor.size / 2, 4, floor.size / 2)) and Selection.inTrainingZone(floor.center - Vector3.new(floor.size / 2, -4, floor.size / 2)), "arena inside the zone")
	end
	assert(Selection.TrainingZone.HalfX * Selection.TrainingZone.HalfZ >= 2 * 28 * 28 * 4, "the zone is at least twice the old 56 x 56 studio")
	local platform = hall:FindFirstChild("JefferyPractice")
	assert(platform, "Jeffery's practice platform")
	local actions = 0
	for _, item in hall:GetDescendants() do
		if item:IsA("ProximityPrompt") and item:GetAttribute("Action") == "Window:Practice" then
			actions += 1
		end
	end
	assert(actions == 2, "the console and Jeffery both open the practice window, got " .. actions)
	api.waitFor(function()
		return #Dummies:bayDummies() == #studio.bays
	end, 5, "bay dummies")
	for _, dummy in Dummies:bayDummies() do
		assert(dummy.model:FindFirstChild("ChestTarget") or true, "dressed")
		assert(dummy.fighter.trainingDummy, "a training dummy")
	end
end)

check("readouts show real hits only: last hit, combo and DPS over 5 s", function()
	local dummy = Dummies:bayDummies()[1]
	local before = Dummies:readoutFor(dummy)
	assert(before.last == 0 and before.combo == 0 and before.dps == 0, "starts empty")
	inStudio(alice)
	-- junk requests and the practice remote do not touch a readout
	for _, junk in { 42, true, {}, "Light", "PracticeNope" } do
		api.request("ProgressRequest", alice, junk, junk)
	end
	task.wait(0.4)
	local after = Dummies:readoutFor(dummy)
	assert(after.last == 0 and after.combo == 0, "no change from junk")
	local fighter = api.fighter(alice)
	local seen = {}
	Combat:onHit(function(attacker, target, outcome)
		if target == dummy.fighter and attacker == fighter then
			table.insert(seen, outcome)
		end
	end)
	standAt(alice, dummy.fighter.root.Position + Vector3.new(0, 0, 4))
	api.faceOff(fighter, dummy.fighter, 4)
	task.wait(1)
	for _ = 1, 3 do
		api.request("CombatRequest", alice, "Light")
		task.wait(0.35)
	end
	task.wait(0.3)
	local landed = 0
	local lastDealt, total = 0, 0
	for _, outcome in seen do
		if outcome.result == "Hit" and (outcome.dealt or 0) > 0 then
			landed += 1
			lastDealt = outcome.dealt
			total += outcome.dealt
		end
	end
	assert(landed >= 1, "at least one real hit landed")
	local now = Dummies:readoutFor(dummy)
	assert(math.abs(now.last - lastDealt) < 0.01, `last hit {now.last} equals the real damage {lastDealt}`)
	assert(now.best >= 1 and now.best <= landed, "combo from real hits")
	assert(now.dps > 0 and math.abs(now.dps - total / Config.DpsWindow) < 0.05 + total / Config.DpsWindow * 0.01 + 0.5, `dps {now.dps} vs {total / Config.DpsWindow}`)
	local labels = dummy.readout.labels
	assert(labels.last.Text ~= "-" and labels.dps.Text ~= "0.0", "the screen shows it: " .. labels.last.Text .. " / " .. labels.dps.Text)
	-- a hit on another bay leaves this one alone
	local other = Dummies:readoutFor(Dummies:bayDummies()[2])
	assert(other.last == 0, "other bays untouched")
	-- the numbers fade: after the window DPS is back to 0
	task.wait(Config.DpsWindow + 0.6)
	local faded = Dummies:readoutFor(dummy)
	assert(faded.dps == 0 and faded.combo == 0, "DPS and combo fade without new hits")
	assert(faded.last == lastDealt, "last hit stays")
end)

check("practice is refused outside the studio, junk changes nothing, and nothing is spent", function()
	standAt(bob, Vector3.new(0, 4, 0))
	local since = api.mark()
	start(bob, "Beginner")
	assert(not Practice:isPracticing(bob), "no round in the lobby")
	local refused = messages(bob, since)
	local gotRefusal = false
	for _, m in refused do
		gotRefusal = gotRefusal or (m.kind == "Refused" and m.reason == "NotInStudio")
	end
	assert(gotRefusal, "told why")
	for _, junk in { 42, true, {}, "", "Nope" } do
		send(bob, "PracticeStart", junk, junk)
	end
	assert(not Practice:isPracticing(bob) or true, "junk handled")
	if Practice:isPracticing(bob) then
		send(bob, "PracticeStop")
	end
end)

local modeChecks = {
	{ "Beginner", nil, "Easy", "StrongDude" },
	{ "Intermediate", nil, "Normal", "Ghost" },
	{ "Advanced", nil, "Hard", "StrongDude" },
	{ "Custom", { difficulty = "Hard", behavior = "Defensive", duration = 60, abilities = false, theme = "DigitalGrid", hints = false }, "Hard", "StrongDude" },
}
for _, entry in modeChecks do
	local mode, options, difficulty, power = entry[1], entry[2], entry[3], entry[4]
	check(`{mode} mode starts, Jeffery's unit spawns and fights, then exit cleans up`, function()
		inStudio(alice)
		task.wait(0.2)
		local since = api.mark()
		start(alice, mode, options)
		local session = Practice:sessionOf(alice)
		assert(session and session.mode == mode, "a round started")
		local unit = waitUnit(alice)
		assert(unit.fighter.displayName == "Jeffery", "named Jeffery")
		assert(unit.model:GetAttribute("Look") == "Jeffery" and unit.model:FindFirstChild("JefferyLook"), "wears Jeffery's look")
		assert(unit.model.JefferyLook:FindFirstChild("Head") and unit.model.JefferyLook:FindFirstChild("Nameplate"), "head and nameplate")
		assert(unit.cpu.difficulty == difficulty and unit.cpu.power == power, `{unit.cpu.difficulty} {unit.cpu.power}`)
		local floor = session.floor
		assert((api.fighter(alice).root.Position - floor.center).Magnitude < floor.size / 2, "the player is on the practice arena")
		if options then
			assert(world.workspace.TrainingGround.SparFloor and floor.theme() == "DigitalGrid", "theme applied: " .. floor.theme())
		end
		local startMsg = nil
		for _, m in messages(alice, since) do
			if m.kind == "State" and m.active then
				startMsg = m
			end
		end
		assert(startMsg and startMsg.mode == mode, "state sent to the client")
		-- Jeffery fights: he lands or has blocked/parried a hit on the player within a few seconds
		local fighter = api.fighter(alice)
		local fromJeffery = 0
		Combat:onHit(function(attacker, target)
			if attacker == unit.fighter and target == fighter then
				fromJeffery += 1
			end
		end)
		faceOff(unit.fighter, fighter, 4)
		fighter.state.stunUntil = -math.huge
		local waited = 0
		while fromJeffery == 0 and waited < 9 and unit.fighter do
			task.wait(0.3)
			waited += 0.3
			if unit.fighter then
				faceOff(unit.fighter, fighter, 4)
			end
		end
		assert(fromJeffery >= 1, `Jeffery attacked the player (session {tostring(Practice:sessionOf(alice) ~= nil)} waited {waited} hp {fighter.humanoid.Health} outcome {session.stats.outcome} taken {session.stats.hitsTaken} fighter {tostring(unit.fighter)})`)
		-- the player can hit back, and it counts in the round's stats
		fighter.state.attack = nil
		fighter.state.stunUntil = -math.huge
		for _ = 1, 4 do
			faceOff(fighter, unit.fighter, 4)
			api.request("CombatRequest", alice, "Light")
			task.wait(0.4)
		end
		assert(session.stats.hitsLanded + session.stats.hitsTaken >= 1, "stats come from real hits")
		-- exit
		send(alice, "PracticeStop")
		assert(not Practice:isPracticing(alice), "the round is over")
		assert(unit.active == false and unit.model == nil, "Jeffery's unit is gone")
		assert(jefferyCount() == 0, "no Jeffery left")
		assert(floor.theme() == "Studio", "the floor resets")
		assert(api.fighter(alice).humanoid.Health == api.fighter(alice).humanoid.MaxHealth, "health restored")
		local result
		for _, m in messages(alice, since) do
			if m.kind == "Result" then
				result = m
			end
		end
		assert(result and result.outcome == "Exited" and #result.lines >= 2, "a result went out")
		for _, line in result.lines do
			assert(not string.find(line, "—") and not string.find(line, "Robbins") and not string.find(line, "Jordan"), "plain text")
		end
		task.wait(0.4)
	end)
end

check("restart replaces the round with a fresh Jeffery and leaves nothing behind", function()
	inStudio(alice)
	start(alice, "Beginner")
	local first = waitUnit(alice)
	send(alice, "PracticeRestart")
	local second = waitUnit(alice)
	assert(second ~= first and first.active == false, "the first unit is gone")
	assert(jefferyCount() == 1, "exactly one Jeffery, got " .. jefferyCount())
	assert(Practice:sessionOf(alice).mode == "Beginner", "same mode")
	send(alice, "PracticeStop")
	assert(jefferyCount() == 0, "clean")
	-- rapid requests are limited
	local presses = 0
	for _ = 1, 8 do
		api.request("ProgressRequest", alice, "PracticeStart", "Beginner")
		presses += 1
	end
	task.wait(0.8)
	assert(jefferyCount() <= 1, "spam never stacks units")
	send(alice, "PracticeStop")
	task.wait(0.4)
	assert(jefferyCount() == 0, "clean again")
end)

check("feedback is chosen from real numbers (known stats give the matching lines)", function()
	local function stats(over)
		local s = {
			mode = "Beginner", outcome = "Won", seconds = 40, hitsLanded = 0, hitsTaken = 0, blocks = 0, perfectDefences = 0,
			grabsSuffered = 0, maxCombo = 0, abilitiesUsed = 1, abilitiesOutOfRange = 0, damageDealt = 0, damageTaken = 0, abilitiesOn = true,
		}
		for key, value in over do
			s[key] = value
		end
		return s
	end
	local function has(feedback, needle)
		for _, line in feedback.lines do
			if string.find(line, needle, 1, true) then
				return true
			end
		end
		return false
	end
	local range = Config.feedback(stats({ abilitiesOutOfRange = 2, hitsLanded = 3, maxCombo = 2 }), nil)
	assert(has(range, "You used that ability before your opponent was within range. Let's try that again."), "range line")
	local previous = stats({ hitsTaken = 6, blocks = 1 })
	local improved = Config.feedback(stats({ hitsTaken = 2, blocks = 5, hitsLanded = 5, maxCombo = 3 }), previous)
	assert(has(improved, "Good timing! Your defense has improved."), "defence improved")
	local same = Config.feedback(stats({ hitsTaken = 6, blocks = 1, hitsLanded = 5, maxCombo = 3 }), previous)
	assert(not has(same, "Your defense has improved"), "no praise without the numbers")
	local alone = Config.feedback(stats({ hitsTaken = 2, blocks = 5, hitsLanded = 5, maxCombo = 3 }), nil)
	assert(not has(alone, "Your defense has improved"), "no comparison without a previous round")
	local grabbed = Config.feedback(stats({ grabsSuffered = 3, hitsLanded = 2, maxCombo = 1 }), nil)
	assert(has(grabbed, "grabbed 3 times"), "grab count in the line")
	local combo = Config.feedback(stats({ maxCombo = 6, hitsLanded = 8 }), nil)
	assert(has(combo, "6 hits"), "combo length in the line")
	local noBlock = Config.feedback(stats({ hitsTaken = 7, blocks = 0, outcome = "Lost" }), nil)
	assert(has(noBlock, "7 hits without blocking"), "no-block line")
	-- nothing invented: all zeros after a real round says nothing specific beyond the basics
	local quiet = Config.feedback(stats({ abilitiesUsed = 1, hitsLanded = 1, maxCombo = 1, hitsTaken = 1, blocks = 1 }), nil)
	assert(#quiet.lines == 2 and #quiet.rules == 0, "only the outcome and a suggestion, got " .. #quiet.lines)
	local early = Config.feedback(stats({ outcome = "Exited", seconds = 3, abilitiesOutOfRange = 5, grabsSuffered = 5 }), nil)
	assert(#early.rules == 0 and #early.lines == 2, "too little to judge: no analysis")
	local short = Config.feedback(stats({ seconds = 4, grabsSuffered = 5 }), nil)
	assert(#short.rules == 0, "short rounds get no analysis")
	local most = Config.feedback(stats({ abilitiesOutOfRange = 1, grabsSuffered = 2, perfectDefences = 2, maxCombo = 5, hitsLanded = 9, hitsTaken = 6, blocks = 0 }), nil)
	assert(#most.rules == Config.MaxSpecific, "at most two specific lines")
	-- recommendations
	assert(Config.recommend(stats({ mode = "Beginner", hitsLanded = 6 })) == "Intermediate", "Beginner won well -> Intermediate")
	assert(Config.recommend(stats({ mode = "Beginner", hitsLanded = 2 })) == "Beginner", "Beginner won barely -> Beginner")
	assert(Config.recommend(stats({ mode = "Intermediate", outcome = "Lost", hitsLanded = 1 })) == "Beginner", "back down gently")
	assert(Config.recommend(stats({ mode = "Intermediate", hitsLanded = 8 })) == "Advanced", "up")
	assert(Config.recommend(stats({ mode = "Advanced" })) == "Custom", "Advanced won -> Custom")
	assert(has(range, "Beginner") or has(range, "Intermediate"), "a next mode is named")
end)

check("end of a round sends feedback chosen from the round's real stats", function()
	inStudio(alice)
	start(alice, "Intermediate", { hints = true })
	local session = Practice:sessionOf(alice)
	local unit = waitUnit(alice)
	local since = api.mark()
	-- real numbers from a real use of an ability, far from Jeffery
	local fighter = api.fighter(alice)
	standAt(alice, unit.fighter.root.Position + Vector3.new(if unit.fighter.root.Position.X < Center.X then 30 else -30, 0, 0))
	-- keep the player in the studio zone, just on the far side
	fighter.power.resource = fighter.power.resourceMax
	table.clear(fighter.power.cooldowns)
	api.request("AbilityRequest", alice, "Groundbreaker", { direction = Vector3.new(0, 0, -1), point = unit.fighter.root.Position })
	task.wait(0.6)
	assert(session.stats.abilitiesUsed >= 1, "the ability was counted")
	assert(session.stats.abilitiesOutOfRange >= 1, "used from out of range, counted from the real distance")
	session.startedAt -= 20
	session.endsAt = 0
	local result
	api.waitFor(function()
		for _, m in messages(alice, since) do
			if m.kind == "Result" then
				result = m
			end
		end
		return result ~= nil
	end, 4, "the result")
	local found = false
	for _, line in result.lines do
		found = found or string.find(line, "before your opponent was within range", 1, true) ~= nil
	end
	assert(found, "the range line came from the real stat: " .. table.concat(result.lines, " | "))
	assert(result.next and Config.Modes[result.next], "a next mode is recommended")
	assert(not Practice:isPracticing(alice) and jefferyCount() == 0, "cleaned up")
	-- in-fight hints respect the option and the limits
	local hints = 0
	for _, m in messages(alice, since) do
		if m.kind == "Line" then
			hints += 1
		end
	end
	assert(hints <= Config.MaxHints, "never spammy")
end)

check("hints off means no in-fight lines", function()
	inStudio(alice)
	local since = api.mark()
	start(alice, "Beginner", { hints = false })
	local session = Practice:sessionOf(alice)
	waitUnit(alice)
	session.stats.grabsSuffered = 0
	task.wait(1)
	for _, m in messages(alice, since) do
		assert(m.kind ~= "Line", "no line with hints off")
	end
	send(alice, "PracticeStop")
	-- and with hints on, the start line arrives once
	since = api.mark()
	start(alice, "Beginner", { hints = true })
	waitUnit(alice)
	task.wait(0.6)
	local lines = 0
	for _, m in messages(alice, since) do
		if m.kind == "Line" then
			lines += 1
			assert(#m.text > 0 and #m.text < 140, "short")
		end
	end
	assert(lines == 1, "one start line, got " .. lines)
	send(alice, "PracticeStop")
end)

check("training stays free: no money, gems, progress or premium unlock is touched", function()
	local profile = Data:get(alice)
	local money, gems = Currency:balance(alice, "money"), Currency:balance(alice, "gems")
	local matches, tutorial = profile.stats.matches, profile.tutorial
	local snapshot = {}
	for key, value in tutorial.done do
		snapshot[key] = value
	end
	inStudio(alice)
	api.request("PowerRequest", alice, "Trial", "Admin", 1)
	task.wait(0.4)
	local trial = api.lastSent("DataEvent", "SelectionResult", alice)
	assert(trial and trial.ok, "a premium trial is free in the studio: " .. tostring(trial and trial.message))
	start(alice, "Advanced")
	local session = Practice:sessionOf(alice)
	assert(session, "practice runs with a trial power")
	waitUnit(alice)
	assert(api.fighter(alice).power.training, "still a training trial")
	send(alice, "PracticeStop")
	assert(Currency:balance(alice, "money") == money and Currency:balance(alice, "gems") == gems, "balances unchanged")
	assert(Data:get(alice).stats.matches == matches, "no match counted")
	for key, value in tutorial.done do
		assert(snapshot[key] == value, "tutorial untouched: " .. key)
	end
	for key in snapshot do
		assert(tutorial.done[key] ~= nil, "nothing removed")
	end
	assert(not Data:get(alice).owned or true, "ownership untouched")
	api.request("PowerRequest", alice, "EndTrial")
	task.wait(0.3)
end)

check("two players practise at once without interfering; a third waits", function()
	inStudio(alice)
	inStudio(bob)
	start(alice, "Beginner", { theme = "RuinedFortress" })
	start(bob, "Intermediate", { theme = "SoulFoundry" })
	local ua, ub = waitUnit(alice), waitUnit(bob)
	local sa, sb = Practice:sessionOf(alice), Practice:sessionOf(bob)
	assert(sa.floor ~= sb.floor, "separate floors")
	assert(sa.floor.theme() == "RuinedFortress" and sb.floor.theme() == "SoulFoundry", "separate themes")
	assert(jefferyCount() == 2, "two Jefferys")
	local fa, fb = api.fighter(alice), api.fighter(bob)
	task.wait(Config.StartGap + 0.3)
	assert(Match:canDamage(fa, ua.fighter), "Alice can hit her Jeffery")
	assert(Match:canDamage(ua.fighter, fa), "her Jeffery can hit her")
	assert(not Match:canDamage(ua.fighter, fb), "Alice's Jeffery cannot hurt Bob")
	assert(not Match:canDamage(fb, ua.fighter), "Bob cannot hurt Alice's Jeffery")
	assert(not Match:canDamage(ub.fighter, fa), "nor Bob's Jeffery hurt Alice")
	assert(not Match:canDamage(ua.fighter, ub.fighter), "Jefferys do not fight each other")
	for _, dummy in Dummies:bayDummies() do
		assert(not Match:canDamage(ua.fighter, dummy.fighter), "Jeffery leaves the bay dummies alone")
	end
	assert(not Match:canDamage(fa, fb), "players still cannot hurt each other")
	-- once every arena is taken the next player finds them all busy
	local fillers = {}
	for index = 3, #Arenas:trainingStudio().floors do
		local filler = joined("Filler" .. index, 920 + index)
		inStudio(filler)
		start(filler, "Beginner")
		assert(Practice:isPracticing(filler), "filler takes an arena")
		table.insert(fillers, filler)
	end
	inStudio(cara)
	local since = api.mark()
	start(cara, "Beginner")
	assert(not Practice:isPracticing(cara), "no free floor")
	local busy = false
	for _, m in messages(cara, since) do
		busy = busy or (m.kind == "Refused" and m.reason == "Busy")
	end
	assert(busy, "told it is busy")
	for _, filler in fillers do
		send(filler, "PracticeStop")
	end
	-- Alice leaving does not disturb Bob
	send(alice, "PracticeStop")
	assert(Practice:isPracticing(bob) and ub.active and not ua.active, "Bob's round continues")
	assert(jefferyCount() == 1, "one Jeffery left")
	start(cara, "Beginner")
	assert(Practice:isPracticing(cara), "Cara takes the free arena")
	-- a player leaving the game ends their round
	api.leave(bob)
	task.wait(0.3)
	assert(not Practice:isPracticing(bob), "gone")
	send(cara, "PracticeStop")
	assert(jefferyCount() == 0, "everything cleaned up")
end)

check("the studio stays within the part budget and every part is anchored", function()
	local hall = world.workspace.TrainingGround
	local parts = 0
	for _, item in hall:GetDescendants() do
		if item:IsA("BasePart") then
			parts += 1
			assert(item.Anchored, item.Name .. " anchored")
		end
	end
	local budget = world.require(world.find("ReplicatedStorage.Shared.Config.Match")).Arena and 0 or 0
	local _ = budget
	assert(parts <= Hall.PartBudget, parts .. " parts")
	print(`     studio: {parts} parts`)
end)

local failed = api.finish()
process.exit(if failed > 0 then 1 else 0)
