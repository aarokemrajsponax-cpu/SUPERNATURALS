-- Runs the real server services with simulated players, end to end:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/integration.luau build/game.rbxl
-- Two players queue for a duel, fight with real combat requests, knock each
-- other out, respawn, and finish with correct scores; plus a forfeit, a
-- practice match against a dummy, junk requests, and the owner panel.
-- Timings are shortened so it runs in seconds.

local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local Engine = require("./smoke/Engine")

local world = Engine.load(process.args[1] or "build/game.rbxl")
local task = Engine.task
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local passed, failed = 0, 0
local function check(name: string, fn: () -> ())
	local before = #Engine.errors
	local ok, err = pcall(fn)
	if ok and #Engine.errors > before then
		ok, err = false, "errors were thrown inside the game code (see above)"
	end
	if ok then
		passed += 1
		print("ok   " .. name)
	else
		failed += 1
		print("FAIL " .. name)
		print("     " .. tostring(err))
	end
end

local function find(path)
	return world.find(path)
end

-- Shorten every wait so the whole test takes seconds -----------------------------------
local Combat = world.require(find("ReplicatedStorage.Shared.Config.Combat"))
local MatchConfig = world.require(find("ReplicatedStorage.Shared.Config.Match"))
Combat.RespawnTime = 0.3
Combat.SpawnProtection = 0.1
Combat.Heavy.Cooldown = 0.2
for _, mode in MatchConfig.Modes do
	mode.Countdown = 0.3
	mode.Duration = 10
	mode.ResultsDuration = 0.4
	mode.SuddenDeathDuration = 0.6
	mode.QueueFillDelay = 0.3
end
-- The sparring dummy blocks at random, so give practice time to land a knockout
MatchConfig.Modes.Practice.Duration = 40

-- Start the services exactly like Bootstrap does -----------------------------------------
-- (the same list Bootstrap uses, read from its source so they never drift apart)
local ORDER = {}
local bootstrapSource = find("ServerScriptService.Server.Bootstrap").Source
for name in string.gmatch(string.match(bootstrapSource, "local ORDER = (%b{})") or "", '"([%w_]+)"') do
	table.insert(ORDER, name)
end
local services = {}
for _, name in ORDER do
	services[name] = world.require(find("ServerScriptService.Server.Services." .. name))
end
for _, name in ORDER do
	if services[name].Init then
		services[name]:Init(services)
	end
end
for _, name in ORDER do
	if services[name].Start then
		Engine.gameTask.spawn(services[name].Start, services[name])
	end
end
task.wait(0.2)

local Characters = services.CharacterService
local Players = world.services.Players
local remotes = find("ReplicatedStorage.Remotes")
local function request(remote: string, player, ...)
	Engine.signalOf(remotes:FindFirstChild(remote), "OnServerEvent"):Fire(player, ...)
end
-- Owner requests are rate limited (8 a second), like a person clicking fast
local function ownerRequest(player, ...)
	request("AdminRequest", player, ...)
	task.wait(0.13)
end

-- The engine's job between frames: notice deaths, respawn players
local respawnQueue = {}
local function spawnCharacter(player)
	local character = Engine.character(player.Name)
	local spawnLocation = world.Instance.new("SpawnLocation")
	local _ = spawnLocation
	character.HumanoidRootPart.CFrame = CFrame.new(0, 4, 0)
	player.Character = character
	character.Parent = world.workspace
	Engine.signalOf(player, "CharacterAdded"):Fire(character)
	return character
end
local alive = true
task.spawn(function()
	while alive do
		Engine.syncPositions(world.workspace)
		Engine.checkDeaths(world.workspace)
		for _, player in Engine.players do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health <= 0 and not respawnQueue[player.Name] then
				respawnQueue[player.Name] = true
				task.delay(Combat.RespawnTime, function()
					respawnQueue[player.Name] = nil
					if table.find(Engine.players, player) then
						character:Destroy()
						spawnCharacter(player)
					end
				end)
			end
		end
		task.wait(0.03)
	end
end)

local nextId = 100
local function join(name: string)
	nextId += 1
	local player = world.Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = nextId
	player.Parent = world.game:GetService("Players")
	table.insert(Engine.players, player)
	Players.PlayerAdded:Fire(player)
	spawnCharacter(player)
	task.wait(0.1)
	return player
end
local function leave(player)
	local index = table.find(Engine.players, player)
	if index then
		table.remove(Engine.players, index)
	end
	Players.PlayerRemoving:Fire(player)
	if player.Character then
		player.Character:Destroy()
	end
	player.Parent = nil
end

local function fighterOf(player)
	return Characters:getByPlayer(player)
end

-- Put two players face to face, `gap` studs apart, inside their arena
local function faceOff(a, b, gap: number)
	local fa, fb = fighterOf(a), fighterOf(b)
	local base = fa.root.CFrame.Position
	local posA = base
	local posB = base + Vector3.new(gap, 0, 0)
	fa.root.CFrame = CFrame.lookAt(posA, posB)
	fb.root.CFrame = CFrame.lookAt(posB, posA)
	Engine.syncPositions(world.workspace)
end

local function lastSent(player, kind: string)
	for index = #Engine.sent, 1, -1 do
		local entry = Engine.sent[index]
		if entry.remote == "MatchEvent" and entry.kind == "FireClient" and entry.args[1] == player and entry.args[2] == kind then
			return entry.args[3]
		end
	end
	return nil
end

local function waitFor(condition: () -> boolean, timeout: number, label: string)
	local started = os.clock()
	while not condition() do
		if os.clock() - started > timeout then
			error("timed out waiting for " .. label)
		end
		task.wait(0.05)
	end
end

-- Tests ----------------------------------------------------------------------------------

local alice, bob

check("players join and become fighters with full health", function()
	alice = join("Alice")
	bob = join("Bob")
	assert(fighterOf(alice) and fighterOf(bob), "both registered")
	-- Everyone starts as Strong Dude, with his own health and speed
	waitFor(function()
		return fighterOf(alice).power ~= nil and fighterOf(bob).power ~= nil
	end, 3, "powers to be equipped")
	local fighter = fighterOf(alice)
	assert(fighter.humanoid.Health == fighter.combat.MaxHealth, "full health")
	assert(fighter.humanoid.WalkSpeed == fighter.combat.Movement.WalkSpeed, "normal speed")
end)

check("players can't hurt each other in the lobby", function()
	faceOff(alice, bob, 3)
	local before = fighterOf(bob).humanoid.Health
	request("CombatRequest", alice, "Light")
	task.wait(0.4)
	assert(fighterOf(bob).humanoid.Health == before, "no lobby damage")
end)

check("junk requests are ignored without errors", function()
	request("CombatRequest", alice, 12345)
	request("CombatRequest", alice, "Explode")
	request("CombatRequest", alice, "Dodge", "not a vector")
	request("CombatRequest", alice, "Dodge", Vector3.new(0 / 0, 0, 0))
	request("MatchRequest", alice, "Queue", "NotAMode")
	request("MatchRequest", alice, {})
	request("AdminRequest", alice, "StartEvent", "MeteorShower") -- Alice isn't the owner
	task.wait(0.3)
	assert(world.game:GetService("ReplicatedStorage"):GetAttribute("AdminEvent") == "", "non-owners can't start events")
end)

local duelResults
check("a full duel: queue, countdown, fight, knockout, respawn, results, back to lobby", function()
	request("MatchRequest", alice, "Queue", "Duel")
	task.wait(0.05)
	local queue = lastSent(alice, "Queue")
	assert(queue and queue.queued == 1, "Alice is queued")
	request("MatchRequest", bob, "Queue", "Duel")
	waitFor(function()
		return services.MatchService:getMatchOf(fighterOf(alice)) ~= nil
	end, 2, "the duel to start")
	assert(fighterOf(alice).humanoid.WalkSpeed == 0, "frozen during the countdown")
	request("CombatRequest", alice, "Light")
	waitFor(function()
		local state = lastSent(alice, "State")
		return state and state.phase == "Active"
	end, 3, "the fight to begin")
	assert(fighterOf(alice).humanoid.WalkSpeed > 0, "unfrozen when the fight begins")

	-- Alice beats Bob down with light chains and heavies until he's knocked out
	local bobFirst = fighterOf(bob)
	local swings = 0
	while bobFirst.humanoid.Health > 0 and swings < 80 do
		if fighterOf(bob) == bobFirst then
			faceOff(alice, bob, 3)
		end
		request("CombatRequest", alice, if swings % 5 == 4 then "Heavy" else "Light")
		swings += 1
		task.wait(0.15)
	end
	assert(bobFirst.humanoid.Health <= 0, `Bob should be knocked out (health {bobFirst.humanoid.Health} after {swings} swings)`)
	-- Stop attacking so nothing else happens before time runs out
	waitFor(function()
		local state = lastSent(alice, "State")
		if not state then
			return false
		end
		for _, entry in state.participants do
			if entry.name == "Alice" and entry.score == 1 then
				return true
			end
		end
		return false
	end, 2, "the knockout to be scored")

	-- Bob respawns inside the arena, protected and frozen? No: the fight is on, so he can move
	waitFor(function()
		return fighterOf(bob) ~= nil and fighterOf(bob) ~= bobFirst
	end, 2, "Bob to respawn")
	task.wait(0.1)
	assert(services.MatchService:getMatchOf(fighterOf(bob)) ~= nil, "Bob is still in the match after respawning")
	assert(fighterOf(bob).humanoid.WalkSpeed > 0, "Bob can move after respawning")

	waitFor(function()
		return lastSent(alice, "Results") ~= nil
	end, 6, "the results")
	duelResults = lastSent(alice, "Results")
	waitFor(function()
		return lastSent(alice, "Ended") ~= nil or alice:GetAttribute("MatchId") == nil
	end, 3, "the match to end")
	task.wait(0.2)
end)

check("duel results: Alice wins 1 to -1", function()
	assert(duelResults, "no results")
	assert(duelResults.reason == "TimeUp", "reason " .. tostring(duelResults.reason))
	assert(duelResults.draw == false, "not a draw")
	assert(duelResults.winners[1] == "Alice", "winner " .. tostring(duelResults.winners[1]))
	assert(duelResults.ranking[1].name == "Alice" and duelResults.ranking[1].score == 1, "Alice +1")
	assert(duelResults.ranking[2].name == "Bob" and duelResults.ranking[2].score == -1, "Bob -1")
	assert(duelResults.ranking[1].knockouts == 1 and duelResults.ranking[2].deaths == 1, "one knockout")
end)

check("after the match nobody is stuck: lobby, unfrozen, full health, arena free", function()
	for _, player in { alice, bob } do
		local fighter = fighterOf(player)
		assert(fighter, player.Name .. " has a fighter")
		assert(services.MatchService:getMatchOf(fighter) == nil, player.Name .. " left the match")
		assert(player:GetAttribute("MatchId") == nil, player.Name .. " MatchId cleared")
		assert(fighter.humanoid.WalkSpeed == fighter.combat.Movement.WalkSpeed, `{player.Name} walk speed {fighter.humanoid.WalkSpeed}`)
		assert(fighter.humanoid.Health == fighter.humanoid.MaxHealth, player.Name .. " healed")
		assert(not fighter.root.Anchored, player.Name .. " not anchored")
	end
	local arena = services.ArenaService:reserve()
	assert(arena and arena.id == 1, "the first arena is free again")
	services.ArenaService:release(arena)
end)

check("a player leaving mid-duel gives the other a forfeit win", function()
	request("MatchRequest", alice, "Queue", "Duel")
	request("MatchRequest", bob, "Queue", "Duel")
	waitFor(function()
		local state = lastSent(alice, "State")
		return state and state.phase == "Active" and services.MatchService:getMatchOf(fighterOf(alice)) ~= nil
	end, 3, "the second duel to begin")
	local before = #Engine.sent
	leave(bob)
	waitFor(function()
		for index = before + 1, #Engine.sent do
			local entry = Engine.sent[index]
			if entry.args[1] == alice and entry.args[2] == "Results" then
				return true
			end
		end
		return false
	end, 2, "forfeit results")
	local results = lastSent(alice, "Results")
	assert(results.reason == "Forfeit" and results.winners[1] == "Alice", "Alice wins by forfeit")
	waitFor(function()
		return alice:GetAttribute("MatchId") == nil
	end, 2, "Alice to return")
	bob = join("Bob")
end)

check("CPU practice: a CPU opponent joins, can be knocked out, and is removed after", function()
	request("MatchRequest", alice, "Queue", "Practice", { cpuPower = "StrongDude", cpuDifficulty = "Easy" })
	waitFor(function()
		local state = lastSent(alice, "State")
		return state and state.mode == "Practice" and state.phase == "Active"
	end, 3, "practice to begin")
	local state = lastSent(alice, "State")
	assert(#state.participants == 2 and state.participants[2].npc, "a dummy opponent")
	local dummy = nil
	waitFor(function()
		dummy = Characters:getById(state.participants[2].id)
		return dummy ~= nil
	end, 3, "the CPU fighter")
	-- Speed things up: the CPU starts nearly beaten
	dummy.humanoid.Health = 20
	local swings = 0
	local function dummyUp()
		return dummy.model.Parent ~= nil and dummy.humanoid.Health > 0
	end
	while dummyUp() and swings < 200 do
		local fa = fighterOf(alice)
		local position = fa.root.CFrame.Position
		dummy.root.CFrame = CFrame.lookAt(position + Vector3.new(3, 0, 0), position)
		fa.root.CFrame = CFrame.lookAt(position, position + Vector3.new(3, 0, 0))
		Engine.syncPositions(world.workspace)
		request("CombatRequest", alice, "Light")
		swings += 1
		task.wait(0.2)
	end
	assert(not dummyUp(), "dummy knocked out")
	waitFor(function()
		local latest = lastSent(alice, "State")
		return latest and latest.participants[1].score == 1
	end, 2, "the practice knockout to score")
	-- End it early the way the owner panel does, which must clean up the same way
	services.MatchService:endAll()
	waitFor(function()
		return alice:GetAttribute("MatchId") == nil
	end, 3, "practice to finish")
	assert(Characters:getById(state.participants[2].id) == nil or not Characters:isAlive(Characters:getById(state.participants[2].id)), "the dummy is gone")
end)

check("training dummies exist in the lobby and can be hit there", function()
	local dummyFighter
	for _, fighter in Characters:all() do
		if fighter.trainingDummy then
			dummyFighter = fighter
		end
	end
	assert(dummyFighter, "a training dummy exists")
	local fa = fighterOf(alice)
	local position = dummyFighter.root.CFrame.Position
	fa.root.CFrame = CFrame.lookAt(position + Vector3.new(-3, 0, 0), position)
	Engine.syncPositions(world.workspace)
	local before = dummyFighter.humanoid.Health
	request("CombatRequest", alice, "Light")
	task.wait(0.4)
	assert(dummyFighter.humanoid.Health < before, "the dummy took damage")
end)

check("dodge and block requests work and expire", function()
	local fa = fighterOf(alice)
	-- Let the last swing (Strong Dude recovers slowly) finish first
	task.wait(0.5)
	request("CombatRequest", alice, "BlockStart")
	task.wait(0.05)
	assert(fa.model:GetAttribute("Blocking") == true, "blocking")
	assert(fa.humanoid.WalkSpeed == fa.combat.Movement.BlockingSpeed, "slowed while blocking")
	request("CombatRequest", alice, "BlockEnd")
	task.wait(0.05)
	assert(fa.model:GetAttribute("Blocking") == false, "not blocking")
	request("CombatRequest", alice, "Dodge", Vector3.new(1, 0, 0))
	task.wait(0.05)
	assert(fa.model:GetAttribute("DodgeReadyAt") > 0, "dodge on cooldown")
	task.wait(0.5)
	assert(fa.humanoid.WalkSpeed == fa.combat.Movement.WalkSpeed, "back to normal after the dodge")
end)

check("owner panel: the owner can run events, actions and announcements", function()
	local owner = join("XxxXxxX_77797")
	task.wait(0.1)
	assert(owner:GetAttribute("SNIsOwner") == true, "the owner is recognised")
	local replicated = world.game:GetService("ReplicatedStorage")
	for _, id in { "MeteorShower", "BlackHole", "Thunderstorm", "IceAge", "LowGravity", "GiantParty", "Galaxy" } do
		ownerRequest(owner, "StartEvent", id)
		assert(replicated:GetAttribute("AdminEvent") == id, id .. " is running")
	end
	ownerRequest(owner, "StopEvent")
	assert(replicated:GetAttribute("AdminEvent") == "", "stopped")
	for _, action in { "Heal", "Fling", "Freeze", "Bring", "Giant", "Speed", "AuraGold", "AuraNone", "NormalSize" } do
		ownerRequest(owner, "PlayerAction", "Others", action)
	end
	ownerRequest(owner, "PlayerAction", alice.UserId, "GoTo")
	ownerRequest(owner, "SelfToggle", "Fly", true)
	ownerRequest(owner, "SelfToggle", "Invisible", true)
	ownerRequest(owner, "SelfToggle", "Invisible", false)
	ownerRequest(owner, "SetTime", "Night")
	ownerRequest(owner, "SetSeason", "Christmas")
	ownerRequest(owner, "SetSeason", "Auto")
	ownerRequest(owner, "EndMatches")
	task.wait(0.2)
	assert(owner:GetAttribute("SNCanFly") == true, "fly enabled")
	assert(world.game:GetService("Lighting"):GetAttribute("SNOwnerClockTime") == 0, "time set to night")
	assert(fighterOf(alice).root.Anchored == true, "Alice is frozen by the owner")
end)

check("timed owner effects wear off (freeze)", function()
	local AdminEvents = world.require(find("ReplicatedStorage.Shared.Config.AdminEvents"))
	AdminEvents.ActionSettings.FreezeTime = 0.8
	local owner = Players:GetPlayers()[#Players:GetPlayers()]
	ownerRequest(owner, "PlayerAction", bob.UserId, "Freeze")
	assert(fighterOf(bob).root.Anchored, "frozen")
	assert(fighterOf(bob).model:GetAttribute("SNIced") == true, "in ice")
	task.wait(1)
	assert(not fighterOf(bob).root.Anchored, "thawed")
	assert(fighterOf(bob).model:GetAttribute("SNIced") == nil, "ice gone")
end)

alive = false
print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
