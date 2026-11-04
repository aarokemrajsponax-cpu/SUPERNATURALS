-- Jeffery's tour and hints on the server (TutorialService), with simulated players:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/tutorial_test.luau build/game.rbxl
-- The tour waits for the client (TutorialReady); a step is only watched after the client says
-- Jeffery finished its lines (TutorialLine) or after the arm timeout; steps advance only on real
-- events (movement, the camera report, entering the Studio, a hit on a dummy, block, dodge, an
-- ability), measured from that moment; junk and forged requests change nothing; the welcome gift
-- (title Recruit and Money, plus Founding Recruit in the payload when owned) is paid exactly
-- once; veterans skip; exiting is clean and a replay pays nothing; two players do not interfere;
-- hints are once only, respect the Hints setting, and wait for the tour to finish.

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
local function joined(name, userId, skipReady)
	local player = api.join(name, userId)
	api.waitFor(function()
		return Data:get(player) ~= nil
	end, 5, name .. "'s profile")
	task.wait(0.1)
	if not skipReady then
		-- The client's handshake: its controller runs and Jeffery is in the world
		api.request("ProgressRequest", player, "TutorialReady")
		task.wait(0.3)
	end
	return player
end
-- The client says Jeffery finished the current step's lines
local function line(player)
	api.request("ProgressRequest", player, "TutorialLine", Tut:currentStep(player))
	task.wait(0.7)
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

check("the tour waits for the client: nothing starts, and no hint fires, before TutorialReady", function()
	local early = joined("Early", 899, true)
	assert(Tut:currentStep(early) == nil, "no run yet")
	assert(Tut:isBusy(early) and not Tut:isActive(early), "pending counts as busy")
	assert(api.lastSent("DataEvent", "Tutorial", early) == nil, "no state sent to a client that may not be listening")
	api.request("ProgressRequest", early, "HintWindow", "Market")
	task.wait(0.7)
	assert(not done(early).hint_shop, "no hint while the tour is pending")
	api.request("ProgressRequest", early, "TutorialReady")
	task.wait(0.4)
	assert(step(early) == "welcome", "started on ready")
	local last = api.lastSent("DataEvent", "Tutorial", early)
	assert(last.event == "start" and last.step == "welcome", "start payload")
	api.leave(early)
end)

check("without a ready the tour still starts after the client wait", function()
	local old = Tutorial.ClientWait
	Tutorial.ClientWait = 0.6
	local late = joined("Late", 898, true)
	task.wait(1.0)
	Tutorial.ClientWait = old
	assert(step(late) == "welcome", "started by itself")
	api.leave(late)
end)

check("a new player starts at the welcome step; the state reaches the client", function()
	assert(step(alice) == "welcome" and step(bob) == "welcome", "both start at welcome")
	local last = api.lastSent("DataEvent", "Tutorial", alice)
	assert(last and last.active and last.step == "welcome" and last.total == #Tutorial.Steps, "state payload")
	assert(not done(alice).tut_complete, "not complete")
	assert(#Tutorial.Steps == 8 and Tutorial.Steps[8].id == "ability", "the short tour has eight steps")
end)

check("junk and forged requests change nothing", function()
	local startMoney = Currency:balance(alice, "money")
	for _, junk in { 42, true, { "welcome" }, "attack", "move", "win", "", "nope" } do
		send(alice, "TutorialAck", junk)
		send(alice, "TutorialLine", junk)
	end
	send(alice, "TutorialAck")
	send(alice, "TutorialLine")
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
	-- a repeated ready only repeats the current step to the client
	local mark = api.mark()
	send(alice, "TutorialReady")
	local again = api.sentSince(mark, "DataEvent", "Tutorial", alice)
	assert(#again == 1 and again[1].event == "start" and again[1].step == "welcome", "ready repeats the current step")
end)

check("CONTINUE advances only the current welcome step; Bob is untouched", function()
	send(alice, "TutorialAck", "welcome")
	assert(step(alice) == "move", "move next, got " .. tostring(step(alice)))
	assert(done(alice).tut_step_welcome, "remembered in the profile")
	assert(step(bob) == "welcome", "Bob did not move")
	send(alice, "TutorialAck", "welcome") -- again: ignored
	assert(step(alice) == "move", "a stale CONTINUE does nothing")
end)

check("a step is not watched while Jeffery is still talking; movement counts from the end of the lines", function()
	local root = api.fighter(alice).root
	local start = root.Position
	-- The player runs off while the line is still being typed: it must not count
	standAt(alice, start + Vector3.new(16, 0, 0))
	task.wait(0.8)
	assert(step(alice) == "move" and not Tut:isArmed(alice), "unarmed step does not advance")
	-- A line report for another step changes nothing
	send(alice, "TutorialLine", "camera")
	assert(not Tut:isArmed(alice), "a wrong step id does not arm")
	line(alice)
	assert(Tut:isArmed(alice) and step(alice) == "move", "armed now, and 16 studs earlier does not count")
	standAt(alice, api.fighter(alice).root.Position + Vector3.new(3, 0, 0))
	task.wait(0.6)
	assert(step(alice) == "move", "3 studs after the lines is not enough")
	standAt(alice, api.fighter(alice).root.Position + Vector3.new(14, 0, 0))
	waitStep(alice, "camera")
	assert(not Tut:isArmed(alice), "the next step starts unarmed")
	assert(step(bob) == "welcome", "Bob did not move")
end)

check("the camera step needs the lines to end first, then the client's camera report", function()
	send(alice, "TutorialAck", "camera")
	assert(step(alice) == "camera", "a camera report before the lines end is ignored")
	line(alice)
	send(alice, "TutorialAck", "welcome") -- wrong step id
	assert(step(alice) == "camera", "wrong id ignored")
	send(alice, "TutorialAck", "camera")
	waitStep(alice, "training")
end)

check("the Studio step waits for the lines, then needs the player inside the Studio", function()
	local fighter = api.fighter(alice)
	line(alice)
	assert(step(alice) == "training", "still waiting in the lobby")
	standAt(alice, Match.TrainingGround.Center + Vector3.new(0, 4, 0))
	waitStep(alice, "attack")
	assert(fighter.root.Position.Y > 0, "in the Studio")
end)

check("attack, block, dodge and ability run on real events, after each step's lines", function()
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
	api.faceOff(fighter, dummy, 4)
	fighter.power.resource = fighter.power.resourceMax
	table.clear(fighter.power.cooldowns)
	-- A hit while Jeffery is still talking does not count
	api.request("CombatRequest", alice, "Light")
	task.wait(0.8)
	assert(step(alice) == "attack", "an early hit does not count")
	line(alice)
	for _ = 1, 4 do
		api.request("CombatRequest", alice, "Light")
		task.wait(0.3)
	end
	waitStep(alice, "block", "a landed hit")
	task.wait(1.2)
	fighter.state.attack = nil
	fighter.state.stunUntil = -math.huge
	-- Block held through the lines must be released and pressed again
	api.request("CombatRequest", alice, "BlockStart")
	task.wait(0.5)
	line(alice)
	task.wait(0.6)
	assert(step(alice) == "block", "a block held since before the lines does not count")
	api.request("CombatRequest", alice, "BlockEnd")
	task.wait(0.6)
	api.request("CombatRequest", alice, "BlockStart")
	waitStep(alice, "dodge")
	api.request("CombatRequest", alice, "BlockEnd")
	task.wait(0.4)
	line(alice)
	task.wait(0.3)
	api.request("CombatRequest", alice, "Dodge", { dir = Vector3.new(1, 0, 0) })
	waitStep(alice, "ability")
	task.wait(1)
	fighter.power.resource = fighter.power.resourceMax
	table.clear(fighter.power.cooldowns)
	api.request("AbilityRequest", alice, "Groundbreaker", { direction = Vector3.new(1, 0, 0), point = dummy.root.Position })
	task.wait(0.8)
	assert(step(alice) == "ability", "an ability used before the lines ended does not count")
	line(alice)
	task.wait(1.2)
	fighter.power.resource = fighter.power.resourceMax
	table.clear(fighter.power.cooldowns)
	api.request("AbilityRequest", alice, "Groundbreaker", { direction = Vector3.new(1, 0, 0), point = dummy.root.Position })
	api.waitFor(function()
		return done(alice).tut_complete == true
	end, 10, "the tour to finish")
	assert(step(bob) == "welcome", "Bob did not move")
end)

check("finishing pays the welcome gift exactly once and lists it in the payload", function()
	local reward = Tutorial.Reward
	local profile = Data:get(alice)
	assert(profile.cosmetics.owned[reward.titleId], "title owned")
	assert(profile.cosmetics.equipped.title ~= nil, "a title is worn")
	assert(done(alice).tut_reward, "reward flag")
	assert(Tut:isActive(alice) == false, "run ended")
	local complete = api.lastSent("DataEvent", "Tutorial", alice)
	assert(complete.event == "complete" and complete.rewarded == true, "complete payload")
	assert(complete.gift and complete.gift.money == reward.money and complete.gift.title == reward.title, "gift lists the Recruit title and the Money")
	assert(complete.gift.founding == (profile.cosmetics.owned[reward.foundingId] == true), "gift says whether Founding Recruit is owned")
	-- Never tied to liking the game: nothing in the payload or the config asks for it
	for key in complete do
		assert(not string.find(string.lower(tostring(key)), "like") and not string.find(string.lower(tostring(key)), "favou?rite"), "no like condition: " .. key)
	end
	assert(string.find(Tutorial.Gift.like, "a like on the game page helps us grow", 1, true), "the voluntary line")
	-- A second finish (replay, forged or repeated) pays nothing
	local after = Currency:balance(alice, "money")
	Tut:_finish(alice, { index = 9, replay = false, finished = true })
	Tut:_finish(alice, { index = 9, replay = true, finished = true })
	assert(Currency:balance(alice, "money") == after, "paid once")
	assert(step(bob) == "welcome", "Bob never advanced")
	assert(not done(bob).tut_complete and not done(bob).tut_reward, "Bob got nothing")
end)

check("the money is paid on finish (balance rose by the reward)", function()
	local carolMoney = Currency:balance(bob, "money")
	local paidBefore = done(bob).tut_reward
	assert(not paidBefore, "Bob unpaid")
	Tut:_finish(bob, { index = 9, replay = false, finished = true })
	task.wait(0.4)
	assert(Currency:balance(bob, "money") == carolMoney + Tutorial.Reward.money, "250 Money")
	assert(done(bob).tut_reward and Data:get(bob).cosmetics.owned.title_recruit, "gift and title")
	-- put Bob back on a live run for the later interference check
end)

check("a client that never reports the end of the lines is not left stuck (arm timeout)", function()
	local old = Tutorial.ArmTimeout
	Tutorial.ArmTimeout = 0.8
	local fay = joined("Fay", 806)
	send(fay, "TutorialAck", "welcome")
	assert(step(fay) == "move" and not Tut:isArmed(fay), "unarmed")
	task.wait(1.6)
	Tutorial.ArmTimeout = old
	assert(Tut:isArmed(fay), "armed by the server's timeout")
	send(fay, "TutorialExit")
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
	assert(api.lastSent("DataEvent", "Tutorial", carol).replay == true, "client told it is a replay")
	send(carol, "TutorialAck", "welcome")
	assert(step(carol) == "move", "replay advances")
	assert(not done(carol).tut_step_welcome, "replay does not record steps")
	Tut:_finish(carol, { index = 9, replay = true, finished = true })
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
	api.leave(bob)
	assert(Tut:currentStep(bob) == nil, "Bob's run is gone")
	assert(Tut:currentStep(alice) == nil, "Alice stays finished")
end)

process.exit(if api.finish() == 0 then 0 else 1)
