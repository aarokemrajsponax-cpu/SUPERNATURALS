-- Jeffery's tutorial and hints on the server (TutorialService), with simulated players:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/tutorial_test.luau build/game.rbxl
-- Steps advance only on real events (movement, a hit on a dummy, block, dodge, an ability,
-- an evolve, opening fighter selection, winning a duel); junk and forged requests change
-- nothing; the reward (title Recruit and Money) is paid exactly once; veterans skip; exiting
-- is clean and a replay pays nothing; two players do not interfere; hints are once only,
-- respect the Hints setting, and wait for the tutorial to finish.

local process = require("@lune/process")
local World = require("./smoke/World")

local api = World.start(process.args[1] or "build/game.rbxl", function(setup)
	for _, mode in setup.MatchConfig.Modes do
		mode.Countdown = 0.3
		mode.Duration = 18
		mode.ResultsDuration = 0.4
		mode.SuddenDeathDuration = 0.6
		mode.QueueFillDelay = 0.3
	end
	setup.Combat.RespawnTime = 0.3
	setup.Combat.SpawnProtection = 0.1
	setup.Combat.Heavy.Cooldown = 0.2
end)
local Engine, task, Vector3, CFrame = api.Engine, api.task, api.Vector3, api.CFrame
local world, services, check = api.world, api.services, api.check
local Data, Currency, Tut, Characters = services.DataService, services.CurrencyService, services.TutorialService, services.CharacterService
local Tutorial = world.require(world.find("ReplicatedStorage.Shared.Config.Tutorial"))
local Selection = world.require(world.find("ReplicatedStorage.Shared.Config.Selection"))
local Match = world.require(world.find("ReplicatedStorage.Shared.Config.Match"))
api.flatGround(0)

local function send(player, action, argument)
	api.request("ProgressRequest", player, action, argument)
	task.wait(0.7)
end
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
local function step(player)
	return Tut:currentStep(player)
end
local function waitStep(player, id, label)
	api.waitFor(function()
		return step(player) == id
	end, 4, (label or ("step " .. id)) .. ` (at {tostring(step(player))}, y {api.fighter(player).root.Position})`)
end
local function done(player)
	return Data:get(player).tutorial.done
end
local function states(player, since)
	return api.sentSince(since, "DataEvent", "Tutorial", player)
end

local alice = joined("Alice", 801)
local bob = joined("Bob", 802)

check("a new player starts at the welcome step; the state reaches the client", function()
	assert(step(alice) == "welcome" and step(bob) == "welcome", "both start at welcome")
	local last = api.lastSent("DataEvent", "Tutorial", alice)
	assert(last and last.active and last.step == "welcome" and last.total == #Tutorial.Steps, "state payload")
	assert(not done(alice).tut_complete, "not complete")
end)

check("junk and forged requests change nothing", function()
	local startMoney = Currency:balance(alice, "money")
	for _, junk in { 42, true, { "welcome" }, "attack", "move", "win", "", "nope" } do
		send(alice, "TutorialAck", junk)
	end
	send(alice, "TutorialAck")
	send(alice, "TutorialReplay") -- already active
	send(alice, "HintWindow", "Settings")
	send(alice, 42, "welcome")
	assert(step(alice) == "welcome", "still at welcome, got " .. tostring(step(alice)))
	assert(next(done(alice)) == nil or not done(alice).tut_step_welcome, "nothing recorded")
	assert(Currency:balance(alice, "money") == startMoney, "nothing paid")
	-- combat in the lobby does not count either
	api.request("CombatRequest", alice, "Light")
	api.request("CombatRequest", alice, "BlockStart")
	task.wait(0.6)
	assert(step(alice) == "welcome", "lobby combat does nothing")
end)

check("CONTINUE advances only the current note step; Bob is untouched", function()
	send(alice, "TutorialAck", "welcome")
	assert(step(alice) == "move", "move next, got " .. tostring(step(alice)))
	assert(done(alice).tut_step_welcome, "remembered in the profile")
	assert(step(bob) == "welcome", "Bob did not move")
	send(alice, "TutorialAck", "welcome") -- again: ignored
	assert(step(alice) == "move", "a stale CONTINUE does nothing")
end)

check("move needs real distance, jump needs a real jump, sprint needs the sprint state", function()
	local root = api.fighter(alice).root
	local start = root.Position
	standAt(alice, start + Vector3.new(3, 0, 0))
	task.wait(0.6)
	assert(step(alice) == "move", "3 studs is not enough")
	standAt(alice, start + Vector3.new(16, 0, 0))
	waitStep(alice, "jump")
	task.wait(0.6)
	assert(step(alice) == "jump", "standing still is not a jump")
	api.fighter(alice).root.AssemblyLinearVelocity = Vector3.new(0, 40, 0)
	waitStep(alice, "sprint")
	api.request("CombatRequest", alice, "SprintStart")
	waitStep(alice, "camera")
	api.request("CombatRequest", alice, "SprintEnd")
	assert(step(bob) == "welcome", "Bob did not move")
end)

check("training, attack, block, dodge, ability, evolve, showcase run on real events", function()
	send(alice, "TutorialAck", "camera")
	waitStep(alice, "training")
	local fighter = api.fighter(alice)
	local dummy
	api.waitFor(function()
		for _, candidate in Characters:all() do
			if candidate.trainingDummy then
				dummy = candidate
				return true
			end
		end
		return false
	end, 6, "a training dummy")
	assert(step(alice) == "training", "still waiting in the lobby")
	standAt(alice, Match.TrainingGround.Center + Vector3.new(0, 4, 0))
	waitStep(alice, "attack")
	api.faceOff(fighter, dummy, 4)
	fighter.power.resource = fighter.power.resourceMax
	table.clear(fighter.power.cooldowns)
	for _ = 1, 4 do
		api.request("CombatRequest", alice, "Light")
		task.wait(0.3)
	end
	waitStep(alice, "block", "a landed hit")
	task.wait(1.2)
	fighter.state.attack = nil
	fighter.state.stunUntil = -math.huge
	api.request("CombatRequest", alice, "BlockStart")
	task.wait(0.5)
	waitStep(alice, "dodge")
	api.request("CombatRequest", alice, "BlockEnd")
	task.wait(0.4)
	api.request("CombatRequest", alice, "Dodge", { dir = Vector3.new(1, 0, 0) })
	waitStep(alice, "ability")
	task.wait(1)
	fighter.power.resource = fighter.power.resourceMax
	table.clear(fighter.power.cooldowns)
	api.request("AbilityRequest", alice, "Groundbreaker", { direction = Vector3.new(1, 0, 0), point = dummy.root.Position })
	waitStep(alice, "evolve")
	task.wait(1.2)
	local trial = api.lastSent("DataEvent", "SelectionResult", alice)
	assert(trial and trial.action == "Trial" and trial.ok, "a trial was started for the evolve step: " .. tostring(trial and trial.action) .. " " .. tostring(trial and trial.message) .. " training=" .. tostring(fighter.power.training))
	api.request("PowerRequest", alice, "Evolve")
	task.wait(0.5)
	local res = api.lastSent("DataEvent", "SelectionResult", alice)
	assert(res and res.ok, "evolve refused: " .. tostring(res and res.message))
	waitStep(alice, "showcase")
	assert(fighter.power.degree == 2, "evolved")
	assert(step(bob) == "welcome", "Bob did not move")
end)

check("winning a duel finishes the path and pays the reward exactly once", function()
	local moneyBefore = Currency:balance(alice, "money")
	api.request("PowerRequest", alice, "State")
	waitStep(alice, "win")
	api.request("MatchRequest", alice, "Queue", "Duel")
	api.request("MatchRequest", bob, "Queue", "Duel")
	api.waitFor(function()
		return services.MatchService:getMatchOf(api.fighter(alice)) ~= nil
	end, 3, "the duel")
	api.waitFor(function()
		return api.fighter(alice).humanoid.WalkSpeed > 0
	end, 3, "the fight to begin")
	local target = api.fighter(bob)
	local swings = 0
	while target.humanoid.Health > 0 and swings < 90 do
		if api.fighter(bob) == target then
			api.faceOff(alice, bob, 3)
		end
		api.request("CombatRequest", alice, if swings % 5 == 4 then "Heavy" else "Light")
		swings += 1
		task.wait(0.15)
	end
	assert(target.humanoid.Health <= 0, "Bob was knocked out")
	api.waitFor(function()
		return done(alice).tut_complete == true
	end, 30, "the tutorial to finish")
	local reward = Tutorial.Reward
	assert(Currency:balance(alice, "money") >= moneyBefore + reward.money, "Money paid")
	local profile = Data:get(alice)
	assert(profile.cosmetics.owned[reward.titleId], "title owned")
	assert(profile.cosmetics.equipped.title == reward.titleId, "title equipped")
	assert(done(alice).tut_reward, "reward flag")
	assert(Tut:isActive(alice) == false, "run ended")
	local complete = api.lastSent("DataEvent", "Tutorial", alice)
	assert(complete.event == "complete" and complete.rewarded == true, "complete payload")
	-- A second finish (replay, forged or repeated) pays nothing
	local after = Currency:balance(alice, "money")
	Tut:_finish(alice, { index = 14, replay = false, finished = true })
	Tut:_finish(alice, { index = 14, replay = true, finished = true })
	assert(Currency:balance(alice, "money") == after, "paid once")
	assert(step(bob) == "welcome", "Bob never advanced")
	assert(not done(bob).tut_complete and not done(bob).tut_reward, "Bob got nothing")
end)

check("exiting is clean, stays exited, and a replay can start but never pays", function()
	local carol = joined("Carol", 803)
	assert(step(carol) == "welcome", "Carol starts")
	send(carol, "TutorialExit")
	assert(not Tut:isActive(carol), "run gone")
	assert(done(carol).tut_exited, "exit remembered")
	local last = api.lastSent("DataEvent", "Tutorial", carol)
	assert(last.event == "exit" and last.active == false, "client told")
	send(carol, "TutorialAck", "welcome")
	assert(not done(carol).tut_step_welcome, "no step progress after exit")
	local money = Currency:balance(carol, "money")
	send(carol, "TutorialReplay")
	assert(step(carol) == "welcome" and Tut:isActive(carol), "replay starts at welcome")
	send(carol, "TutorialAck", "welcome")
	assert(step(carol) == "move", "replay advances")
	assert(not done(carol).tut_step_welcome, "replay does not record steps")
	Tut:_finish(carol, { index = 14, replay = true, finished = true })
	assert(Currency:balance(carol, "money") == money and not done(carol).tut_reward, "replay pays nothing")
	send(carol, "TutorialExit")
	api.leave(carol)
	local again = joined("Carol", 803)
	assert(not Tut:isActive(again), "exited players are not restarted on rejoin")
end)

check("players with 3 or more matches skip the tutorial automatically", function()
	local dave = joined("Dave", 804)
	Data:update(dave, function(profile)
		profile.stats.matches = Tutorial.VeteranMatches
	end)
	Data:saveNow(dave)
	api.leave(dave)
	local back = joined("Dave", 804)
	assert(not Tut:isActive(back), "no tutorial for a veteran")
	assert(done(back).tut_veteran, "marked as a veteran")
	local last = api.lastSent("DataEvent", "Tutorial", back)
	assert(last and last.active == false, "client told it is off")
	send(back, "TutorialReplay")
	assert(Tut:isActive(back), "Replay still works for a veteran")
	send(back, "TutorialExit")
end)

check("hints: once each, remembered, off with the Hints setting, held during the tutorial", function()
	local erin = joined("Erin", 805)
	local mark = api.mark()
	send(erin, "HintWindow", "Market")
	assert(#api.sentSince(mark, "DataEvent", "Hint", erin) == 0, "no hint while the tutorial runs")
	assert(not done(erin).hint_shop, "and it is not used up")
	send(erin, "TutorialExit")
	send(erin, "HintWindow", "Market")
	local hints = api.sentSince(mark, "DataEvent", "Hint", erin)
	assert(#hints == 1 and hints[1].id == "shop" and hints[1].text == Tutorial.Hints.shop.text, "shop hint once")
	assert(done(erin).hint_shop, "remembered by the server")
	send(erin, "HintWindow", "Market")
	assert(#api.sentSince(mark, "DataEvent", "Hint", erin) == 1, "never twice")
	Data:update(erin, function(profile)
		profile.settings.hints = false
	end)
	send(erin, "HintWindow", "Powers")
	assert(#api.sentSince(mark, "DataEvent", "Hint", erin) == 1, "nothing with hints off")
	assert(not done(erin).hint_selection, "and not used up")
	Data:update(erin, function(profile)
		profile.settings.hints = true
	end)
	-- Entering training shows the training hint, once
	standAt(erin, Match.TrainingGround.Center + Vector3.new(0, 4, 0))
	api.waitFor(function()
		return done(erin).hint_training == true
	end, 4, "the training hint")
end)

check("two players do not interfere and leaving cleans up", function()
	local before = Tut:isActive(bob)
	api.leave(bob)
	assert(Tut:currentStep(bob) == nil, "Bob's run is gone")
	assert(before == true, "Bob had a run")
	assert(Tut:currentStep(alice) == nil, "Alice stays finished")
end)

api.finish()
