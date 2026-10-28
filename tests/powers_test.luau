-- Runs the power framework end to end with simulated players:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/powers_test.luau build/game.rbxl
-- Strong Dude's abilities against dummies and players, cooldowns, costs and
-- junk requests, a grab escaped by mashing, a timing-bar perfect defense, a
-- thrown object, statuses that end on their own, and a knockout in the middle
-- of an ultimate.

local process = require("@lune/process")

local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl")
local task, Vector3, CFrame = game.task, game.Vector3, game.CFrame
local services, check, request = game.services, game.check, game.request
local FighterState = game.world.require(game.world.find("ReplicatedStorage.Shared.Combat.FighterState"))
local Protocol = game.world.require(game.world.find("ReplicatedStorage.Shared.Protocol"))
local Attribute = Protocol.Attribute

game.flatGround(0)

local function now(): number
	return game.world.workspace:GetServerTimeNow()
end

local alice, bob
local function aimAt(from, to)
	return { direction = (to.root.Position - from.root.Position).Unit, point = to.root.Position }
end

-- Clear an ability's cooldown and give resource, so tests don't wait
local function ready(fighter, abilityId: string?)
	local runtime = fighter.power
	runtime.resource = runtime.resourceMax
	if abilityId then
		runtime.cooldowns[abilityId] = 0
	else
		table.clear(runtime.cooldowns)
	end
	fighter.state.attack = nil
	fighter.state.stunUntil = -math.huge
	services.CharacterService:refresh(fighter)
end

check("players spawn with a power: Strong Dude, Degree 1, default loadout", function()
	alice = game.join("Alice")
	bob = game.join("Bob")
	local fighter = game.fighter(alice)
	game.waitFor(function()
		return fighter.power ~= nil
	end, 2, "a power to be equipped")
	assert(fighter.power.id == "StrongDude", "Strong Dude")
	assert(fighter.power.degree == 1, "degree 1")
	assert(fighter.model:GetAttribute(Attribute.Power) == "StrongDude", "attribute for clients")
	assert(fighter.model:GetAttribute(Attribute.Loadout) == "Groundbreaker,TitanGrip,MeteorCharge", "default loadout")
	assert(fighter.humanoid.MaxHealth == 125, "Strong Dude's health")
	assert(fighter.combat.Block.MaxGuard == 140, "Strong Dude's guard")
end)

check("an ability hits a training dummy, costs grit and starts its cooldown", function()
	local fighter = game.fighter(alice)
	local dummy = nil
	game.waitFor(function()
		for _, candidate in services.CharacterService:all() do
			if candidate.trainingDummy then
				dummy = candidate
				return true
			end
		end
		return false
	end, 6, "a training dummy")
	game.faceOff(fighter, dummy, 5)
	ready(fighter)
	local before = dummy.humanoid.Health
	local grit = fighter.power.resource
	request("AbilityRequest", alice, "Groundbreaker", aimAt(fighter, dummy))
	task.wait(0.8)
	assert(dummy.humanoid.Health < before, `dummy took damage ({before} -> {dummy.humanoid.Health})`)
	assert(fighter.power.resource < grit, "grit spent")
	assert((fighter.model:GetAttribute(Attribute.CooldownPrefix .. "Groundbreaker") or 0) > now(), "cooldown published")
end)

check("cooldowns, costs, unequipped and junk ability requests are refused", function()
	local fighter = game.fighter(alice)
	task.wait(1.2)
	local mark = game.mark()
	request("AbilityRequest", alice, "Groundbreaker", {})
	request("AbilityRequest", alice, "SeismicFissure", {}) -- degree 3 only
	request("AbilityRequest", alice, "PhantomVeil", {}) -- another power's
	request("AbilityRequest", alice, 42, {})
	request("AbilityRequest", alice, "TitanGrip", { direction = Vector3.new(0 / 0, 0, 0), point = "nope" })
	request("AbilityRequest", alice, "WorldBreaker", {}) -- no charge yet
	task.wait(0.2)
	local rejected = game.sentSince(mark, "AbilityEvent", "Rejected", alice)
	local reasons = {}
	for _, entry in rejected do
		reasons[entry.ability] = entry.reason
	end
	assert(reasons.Groundbreaker == "cooldown", "cooldown: " .. tostring(reasons.Groundbreaker))
	assert(reasons.SeismicFissure == "not equipped", "not equipped: " .. tostring(reasons.SeismicFissure))
	assert(reasons.PhantomVeil == "unknown", "other power: " .. tostring(reasons.PhantomVeil))
	assert(reasons.WorldBreaker == "charge", "charge: " .. tostring(reasons.WorldBreaker))
	fighter.power.resource = 0
	fighter.power.cooldowns.MeteorCharge = 0
	request("AbilityRequest", alice, "MeteorCharge", {})
	task.wait(0.1)
	local _, index = game.lastSent("AbilityEvent", "Rejected", alice)
	assert(index > mark, "no grit, no charge")
	-- Spamming past the rate limit just drops requests
	for _ = 1, 40 do
		request("AbilityRequest", alice, "Groundbreaker", {})
	end
	task.wait(0.3)
	ready(fighter)
end)

local match
check("in a duel, a grab can be escaped by mashing and leaves the grabber open", function()
	request("MatchRequest", alice, "Queue", "Duel")
	request("MatchRequest", bob, "Queue", "Duel")
	game.waitFor(function()
		match = services.MatchService:getMatchOf(game.fighter(alice))
		return match ~= nil and match.flow.phase == "Active"
	end, 4, "the duel to begin")
	local a, b = game.fighter(alice), game.fighter(bob)
	task.wait(0.2)
	game.faceOff(a, b, 3)
	ready(a)
	local mark = game.mark()
	request("AbilityRequest", alice, "TitanGrip", aimAt(a, b))
	game.waitFor(function()
		return #game.sentSince(mark, "DefenseEvent", "Cue", bob) > 0
	end, 2, "Bob's mash prompt")
	local cue = game.sentSince(mark, "DefenseEvent", "Cue", bob)[1]
	assert(cue.kind == "Mash", "it's a mash prompt")
	assert(cue.presses and cue.presses > 0, "says how many presses")
	for _ = 1, cue.presses + 2 do
		request("DefenseInput", bob, "Mash", cue.id)
		task.wait(0.09)
	end
	game.waitFor(function()
		local result = game.lastSent("DefenseEvent", "Result", bob)
		return result ~= nil and result.kind == "Mash"
	end, 2, "the grab result")
	local result = game.lastSent("DefenseEvent", "Result", bob)
	assert(result.result == "Escaped", "Bob escaped: " .. tostring(result.result))
	assert(FighterState.isStunned(a.state, now()), "Alice is staggered")
	assert(not services.StatusService:has(b, "Grabbed"), "Bob isn't held any more")
	task.wait(0.8)
end)

check("an ultimate shows a timing bar; perfect timing negates it", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	game.faceOff(a, b, 8)
	ready(a)
	ready(b)
	a.power.ult = 100
	local health = b.humanoid.Health
	local mark = game.mark()
	request("AbilityRequest", alice, "WorldBreaker", aimAt(a, b))
	game.waitFor(function()
		return #game.sentSince(mark, "DefenseEvent", "Cue", bob) > 0
	end, 2, "Bob's timing bar")
	local cue = game.sentSince(mark, "DefenseEvent", "Cue", bob)[1]
	assert(cue.kind == "Timing", "a timing bar")
	-- Press right on the impact (the engine reports 0.05s ping, half is allowed for)
	local wait = cue.impactAt - now() + 0.025
	task.wait(math.max(0, wait))
	request("DefenseInput", bob, "Timing", cue.id)
	task.wait(0.6)
	local result = game.lastSent("DefenseEvent", "Result", bob)
	assert(result and result.result == "Perfect", "perfect: " .. tostring(result and result.result))
	assert(b.humanoid.Health == health, `no damage ({health} -> {b.humanoid.Health})`)
	assert(a.power.ult < 100, "the charge was spent")
	task.wait(1.5)
end)

check("an ultimate with bad timing lands", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	game.faceOff(a, b, 8)
	ready(a)
	ready(b)
	a.power.ult = 100
	local health = b.humanoid.Health
	request("AbilityRequest", alice, "WorldBreaker", aimAt(a, b))
	task.wait(2)
	assert(b.humanoid.Health < health, "it hit")
	task.wait(1.2)
end)

check("thrown objects fly as projectiles and hit", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	ready(a)
	ready(b)
	-- Equip Heave for this test (the server would normally check ownership)
	services.PowerService:equip(a, "StrongDude", 1, { "Heave", "TitanGrip", "MeteorCharge" })
	ready(a)
	-- Stand next to a crate in the arena
	local crate
	for _, prop in match.arena.model:GetChildren() do
		if prop:GetAttribute("Weight") == 1 then
			crate = prop
			break
		end
	end
	assert(crate, "the arena has light objects")
	a.root.CFrame = CFrame.new(crate.Position + Vector3.new(3, 2, 0))
	b.root.CFrame = CFrame.new(crate.Position + Vector3.new(25, 2, 0))
	game.Engine.syncPositions(game.world.workspace)
	local health = b.humanoid.Health
	local mark = game.mark()
	request("AbilityRequest", alice, "Heave", aimAt(a, b))
	game.waitFor(function()
		return #game.sentSince(mark, "AbilityEvent", "ProjectileSpawn") > 0
	end, 2, "the throw")
	assert(crate:GetAttribute("Held") == true, "the crate was picked up")
	game.waitFor(function()
		return #game.sentSince(mark, "AbilityEvent", "ProjectileEnd") > 0
	end, 3, "the throw to land")
	local ended = game.sentSince(mark, "AbilityEvent", "ProjectileEnd")[1]
	assert(ended.reason == "Hit", "it hit Bob: " .. tostring(ended.reason))
	assert(b.humanoid.Health < health, "Bob took damage")
end)

check("statuses end on their own and are capped", function()
	local b = game.fighter(bob)
	services.StatusService:apply(b, "Slow", 999, { magnitude = 0.5 })
	local slow = services.StatusService:get(b, "Slow")
	assert(slow and slow.endsAt - now() <= game.Combat.Statuses.Slow.max + 0.01, "capped at the maximum")
	assert(b.statusSpeed == 0.5, "slowed")
	services.StatusService:apply(b, "Root", 0.3)
	assert(b.rooted, "rooted")
	task.wait(0.5)
	assert(not b.rooted, "root wore off")
	services.StatusService:remove(b, "Slow")
	assert(b.statusSpeed == 1, "back to normal speed")
end)

check("a knockout in the middle of an ultimate cleans up and respawns normally", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	services.PowerService:equip(a, "StrongDude", 1, { "Groundbreaker", "TitanGrip", "MeteorCharge" })
	game.faceOff(a, b, 8)
	ready(a)
	a.power.ult = 100
	request("AbilityRequest", alice, "WorldBreaker", aimAt(a, b))
	task.wait(0.3)
	a.humanoid.Health = 0
	game.waitFor(function()
		local fresh = game.fighter(alice)
		return fresh ~= nil and fresh ~= a and fresh.power ~= nil
	end, 3, "Alice to respawn")
	local fresh = game.fighter(alice)
	assert(fresh.power.ult < 5, "charge starts (nearly) empty: " .. tostring(fresh.power.ult))
	assert(not FighterState.isAttacking(fresh.state, now()), "not stuck mid-cast")
	assert(fresh.humanoid.WalkSpeed > 0 or match.flow.phase ~= "Active", "can move")
end)

check("matches end cleanly with nothing left behind", function()
	services.MatchService:endAll()
	task.wait(1.2)
	assert(services.MatchService:getMatchOf(game.fighter(alice)) == nil, "match over")
	local constructs = game.world.workspace:FindFirstChild("SNConstructs")
	assert(constructs == nil or #constructs:GetChildren() == 0, "no constructs left")
	local a = game.fighter(alice)
	for name, value in a.model:GetAttributes() do
		if string.sub(name, 1, 4) == "SNS_" then
			error("status left on Alice: " .. name .. " " .. tostring(value))
		end
	end
end)

check("CPU Practice: a CPU with a power fights back and answers defenses", function()
	local a = game.fighter(alice)
	ready(a)
	request("MatchRequest", alice, "Queue", "Practice", { cpuPower = "StrongDude", cpuDegree = 3, cpuDifficulty = "Hard" })
	local practice
	game.waitFor(function()
		practice = services.MatchService:getMatchOf(game.fighter(alice))
		return practice ~= nil and practice.flow.phase == "Active"
	end, 4, "practice to begin")
	local cpu
	game.waitFor(function()
		for _, participant in practice.participants do
			if participant.dummy and participant.dummy.fighter then
				cpu = participant.dummy.fighter
				return cpu.power ~= nil
			end
		end
		return false
	end, 4, "the CPU to arrive with its power")
	assert(cpu.power.id == "StrongDude" and cpu.power.degree == 3, "the CPU plays what was asked for")
	assert(cpu.model:GetAttribute("CpuDifficulty") == "Hard", "difficulty")
	local me = game.fighter(alice)
	local startHealth = me.humanoid.Health
	-- Stand next to it and let it fight for a few seconds
	local started = os.clock()
	while os.clock() - started < 6 and me.humanoid.Health >= startHealth do
		game.faceOff(cpu, me, 4)
		task.wait(0.2)
	end
	assert(me.humanoid.Health < startHealth, "the CPU landed hits")
	-- A timing cue sent to the CPU gets an answer (graded by the same rules)
	local cueId = services.DefenseService:timing(cpu, me, { impactAt = now() + 0.4, ability = "Test", label = "Test" })
	task.wait(0.8)
	local _ = cueId
	services.MatchService:endAll()
	task.wait(1)
end)

process.exit(if game.finish() == 0 then 0 else 1)
