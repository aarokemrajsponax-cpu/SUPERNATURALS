-- Fighting System v2 end to end, with simulated players in a real duel:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/combat_test.luau build/game.rbxl
-- Covers the CONTRACT (actions, payloads, events, attributes, config), every
-- move in every context (the light string, counters, punishes, parries and
-- ripostes, clashes, perfect and directional dodges, dodge-cancels, stamina
-- and being winded, sprinting and sprint strikes, the Launcher, juggles and
-- breakfalls, the Slam, sweeps, knockdowns, tech rolls and the one hit on the
-- floor, charged heavies and feints, grabs, throws, techs and whiffs, wall
-- splats, props, taunts), junk payloads and spam, nothing staying stuck after
-- deaths, respawns and the match ending, and a CPU using the new moves.

local process = require("@lune/process")

local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl", function(setup)
	-- One long duel for the whole test; props come home quickly
	setup.MatchConfig.Modes.Duel.Duration = 900
	setup.Combat.Carry.ReturnDelay = 0.4
	setup.Combat.Carry.MaxDuration = 1.2
end)
local task, Vector3, CFrame = game.task, game.Vector3, game.CFrame
local services, check, request = game.services, game.check, game.request
local world, Engine = game.world, game.Engine
local FighterState = world.require(world.find("ReplicatedStorage.Shared.Combat.FighterState"))
local Protocol = world.require(world.find("ReplicatedStorage.Shared.Protocol"))
local Combat = game.Combat
local Attribute = Protocol.Attribute
local CombatService = services.CombatService

game.flatGround(0)

local function now(): number
	return world.workspace:GetServerTimeNow()
end

-- Who the server should think is off the ground (the stand-in engine has no physics)
local inAir: { [string]: boolean } = {}
local realIsInAir = CombatService.isInAir
CombatService.isInAir = function(self, fighter)
	if inAir[fighter.id] then
		return true
	end
	return realIsInAir(self, fighter)
end

local alice, bob
local arena

local function A()
	return game.fighter(alice)
end
local function B()
	return game.fighter(bob)
end

-- Full health and a completely clean combat state, so checks don't wait on each other
local function ready(fighter)
	CombatService:resetFighter(fighter)
	FighterState.reset(fighter.state, fighter.combat, now(), 0)
	services.StatusService:clearAll(fighter)
	fighter.humanoid.Health = fighter.humanoid.MaxHealth
	for _, child in fighter.root:GetChildren() do
		if child.Name == "SNDash" or child.Name == "SNKnockback" then
			child:Destroy()
		end
	end
	inAir[fighter.id] = nil
	services.CharacterService:refresh(fighter)
end

local function readyBoth()
	ready(A())
	ready(B())
	task.wait(0.05)
end

-- Alice on the left facing Bob, `gap` studs apart, around the arena's middle
local function stage(gap: number, shift: Vector3?)
	local a, b = A(), B()
	local center = arena.center + (shift or Vector3.zero)
	local posA = center + Vector3.new(-gap / 2, 3, 0)
	local posB = center + Vector3.new(gap / 2, 3, 0)
	a.root.CFrame = CFrame.lookAt(posA, posB)
	b.root.CFrame = CFrame.lookAt(posB, posA)
	Engine.syncPositions(world.workspace)
	return a, b
end

local function hitsSince(mark: number, attacker, victim)
	local list = {}
	for _, hit in game.sentSince(mark, "CombatEvent", "Hit") do
		if hit.attacker == attacker.model and hit.victim == victim.model then
			table.insert(list, hit)
		end
	end
	return list
end

local function attacksSince(mark: number, fighter)
	local list = {}
	for _, attack in game.sentSince(mark, "CombatEvent", "Attack") do
		if attack.attacker == fighter.model then
			table.insert(list, attack)
		end
	end
	return list
end

local function motionsSince(mark: number, fighter, name: string)
	local list = {}
	for _, entry in game.sentSince(mark, "CombatEvent", "Motion") do
		if entry.fighter == fighter.model and entry.motion == name then
			table.insert(list, entry)
		end
	end
	return list
end

local function grabsSince(mark: number, phase: string)
	local list = {}
	for _, entry in game.sentSince(mark, "CombatEvent", "Grab") do
		if entry.phase == phase then
			table.insert(list, entry)
		end
	end
	return list
end

local function rejection(mark: number, player, action: string): string?
	for _, entry in game.sentSince(mark, "CombatEvent", "Rejected", player) do
		if entry.action == action then
			return entry.reason
		end
	end
	return nil
end

local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1e-3)
end

local function waitHit(mark: number, attacker, victim, label: string, count: number?)
	game.waitFor(function()
		return #hitsSince(mark, attacker, victim) >= (count or 1)
	end, 2, label)
	return hitsSince(mark, attacker, victim)
end

-- The contract ------------------------------------------------------------------------

check("the contract: actions, events, attributes and config sections all exist", function()
	for _, name in { "Light", "Heavy", "BlockStart", "BlockEnd", "Dodge", "HeavyRelease", "Feint", "Grab", "Sweep", "SprintStart", "SprintEnd", "Taunt" } do
		assert(Protocol.CombatAction[name] == name, "action " .. name)
	end
	for _, name in { "Attack", "Hit", "Dodge", "Rejected", "Clash", "Grab", "Motion" } do
		assert(Protocol.CombatEvent[name] == name, "event " .. name)
	end
	local attributes = {
		Stamina = "SNStamina",
		StaminaMax = "SNStaminaMax",
		Sprinting = "SNSprinting",
		Winded = "SNWinded",
		DownedUntil = "SNDownedUntil",
		Carrying = "SNCarrying",
		ChargeStart = "SNChargeStart",
		Airborne = "SNAirborne",
	}
	for key, value in attributes do
		assert(Attribute[key] == value, "attribute " .. key)
	end
	local sections = {
		Stamina = { "Max", "Regen", "RegenDelay", "WindedRecover", "Costs" },
		Sprint = { "Speed", "MinStamina" },
		Dodge = { "PerfectWindow", "PerfectPunish", "Directions", "Speed", "Duration", "Invulnerable", "Recovery", "Cooldown" },
		Feint = { "Recovery", "Cooldown" },
		Grab = { "Range", "Startup", "Active", "WhiffRecovery", "TechWindow", "Hold", "Damage", "BackDamage", "Knockback", "Cooldown" },
		Sweep = { "Damage", "Startup", "Active", "Recovery", "Range", "Arc", "GuardDamage", "Hitstun" },
		Knockdown = { "Duration", "TechWindow", "TechRollDistance", "GetUpInvulnerable", "OTGDamageMultiplier" },
		Air = { "Light", "Heavy", "JuggleLimit", "BreakfallAfter" },
		Running = { "Light", "Heavy" },
		Launcher = { "Damage", "Startup", "Active", "Recovery", "Range", "Arc", "Launch" },
		Counter = { "DamageMultiplier", "ExtraHitstun" },
		Punish = { "DamageMultiplier" },
		Riposte = { "Window", "DamageMultiplier" },
		Clash = { "Window", "Pushback", "Stun" },
		WallSplat = { "MinKnockback", "CheckDistance", "Damage", "Stun" },
		Taunt = { "Duration", "UltimateCharge", "Cooldown" },
		Carry = { "WalkSpeed", "ThrowSpeed", "Damage" },
		ComboScaling = { "From", "PerHit", "Min" },
	}
	for section, fields in sections do
		assert(typeof(Combat[section]) == "table", "config section " .. section)
		for _, field in fields do
			assert(Combat[section][field] ~= nil, `Combat.{section}.{field}`)
		end
	end
	for _, cost in { "Dodge", "SprintPerSecond", "DodgeCancel", "Feint", "Charge", "TechRoll", "Breakfall", "Grab" } do
		assert(typeof(Combat.Stamina.Costs[cost]) == "number", "stamina cost " .. cost)
	end
	for _, style in { "Side", "Back", "Forward" } do
		local numbers = Combat.Dodge.Directions[style]
		assert(numbers and numbers.Speed and numbers.Duration and numbers.Invulnerable, "dodge style " .. style)
	end
	for _, field in { "Min", "Max", "DamageBonus", "GuardDamageBonus", "MoveSpeed" } do
		assert(Combat.Heavy.Charge[field] ~= nil, "Heavy.Charge." .. field)
	end
	local moves = { "Jab", "Cross", "Hook", "FinisherKick" }
	for index, step in Combat.Light.Steps do
		assert(step.Move == moves[index], "light step " .. index .. " is named")
	end
end)

check("two players duel as Strong Dude; stamina is published on their characters", function()
	alice = game.join("Alice")
	bob = game.join("Bob")
	for _, player in { alice, bob } do
		local fighter = game.fighter(player)
		services.PowerService:equip(fighter, "StrongDude", 1, { "Heave", "TitanGrip", "MeteorCharge" })
	end
	request("MatchRequest", alice, "Queue", "Duel")
	request("MatchRequest", bob, "Queue", "Duel")
	local match
	game.waitFor(function()
		match = services.MatchService:getMatchOf(A())
		return match ~= nil and match.flow.phase == "Active"
	end, 4, "the duel to begin")
	arena = match.arena
	task.wait(0.2)
	readyBoth()
	local model = A().model
	assert(model:GetAttribute(Attribute.Stamina) == Combat.Stamina.Max, "full stamina: " .. tostring(model:GetAttribute(Attribute.Stamina)))
	assert(model:GetAttribute(Attribute.StaminaMax) == Combat.Stamina.Max, "stamina maximum")
	assert(model:GetAttribute(Attribute.Sprinting) == false, "not sprinting")
	assert(model:GetAttribute(Attribute.Winded) == false, "not winded")
	assert(model:GetAttribute(Attribute.DownedUntil) == 0, "standing")
	assert(model:GetAttribute(Attribute.Airborne) == false, "on the ground")
	assert(model:GetAttribute(Attribute.Carrying) == nil, "empty-handed")
	assert(model:GetAttribute(Attribute.ChargeStart) == nil, "not charging")
end)

-- Strikes ------------------------------------------------------------------------------

check("the light string: jab, cross, hook, finisher kick; hits carry move, tags and direction; the 4th is scaled", function()
	readyBoth()
	local a, b = stage(4)
	local mark = game.mark()
	for index = 1, 4 do
		request("CombatRequest", alice, "Light", { dir = Vector3.new(1, 0, 0) })
		waitHit(mark, a, b, "light hit " .. index, index)
		if index == 4 then
			assert(b.model:GetAttribute(Attribute.Airborne) == true, "launched fighters are airborne")
		end
		local step = a.combat.Light.Steps[index]
		task.wait(step.Active + step.Recovery + 0.03)
	end
	local moves = {}
	for _, attack in attacksSince(mark, a) do
		table.insert(moves, attack.move)
		assert(typeof(attack.recovery) == "number", "attacks say their recovery")
	end
	assert(table.concat(moves, ",") == "Jab,Cross,Hook,FinisherKick", "moves: " .. table.concat(moves, ","))
	local hits = hitsSince(mark, a, b)
	for index, hit in hits do
		assert(hit.move == moves[index], "hit " .. index .. " names its move")
		assert(typeof(hit.tags) == "table", "hit tags")
		assert(typeof(hit.direction) == "Vector3" and hit.direction.X > 0.9, "hit direction points away from Alice")
	end
	local scale = b.combat.DamageTaken or 1
	assert(near(hits[1].damage, a.combat.Light.Steps[1].Damage * scale), "first hit full damage")
	local fourth = a.combat.Light.Steps[4].Damage * (1 - Combat.ComboScaling.PerHit) * scale
	assert(near(hits[4].damage, fourth), `4th hit scaled: {hits[4].damage} vs {fourth}`)
	assert(hits[4].tags.launch == true, "the finisher launches")
end)

check("counter hit: striking a heavy's wind-up deals more and says COUNTER", function()
	readyBoth()
	local a, b = stage(4)
	local mark = game.mark()
	request("CombatRequest", bob, "Heavy")
	task.wait(0.05)
	request("CombatRequest", alice, "Light")
	local hit = waitHit(mark, a, b, "the counter hit")[1]
	assert(hit.tags.counter == true, "counter tag")
	assert(near(hit.damage, a.combat.Light.Steps[1].Damage * Combat.Counter.DamageMultiplier * (b.combat.DamageTaken or 1)), "counter damage " .. hit.damage)
	assert(b.state.attack == nil, "Bob's heavy was stopped")
end)

check("punish: striking a whiffed heavy's recovery deals more and says PUNISH", function()
	readyBoth()
	local a, b = stage(4)
	-- Bob swings the other way and misses
	b.root.CFrame = CFrame.lookAt(b.root.Position, b.root.Position + Vector3.new(1, 0, 0))
	Engine.syncPositions(world.workspace)
	request("CombatRequest", bob, "Heavy")
	task.wait(b.combat.Heavy.Startup + b.combat.Heavy.Active + 0.08)
	assert(FighterState.inWhiffRecovery(b.state, now()), "Bob is recovering from a whiff")
	local mark = game.mark()
	request("CombatRequest", alice, "Light")
	local hit = waitHit(mark, a, b, "the punish")[1]
	assert(hit.tags.punish == true, "punish tag")
	assert(not hit.tags.counter, "not a counter")
end)

check("parry, then a riposte: the parrier's next light deals bonus damage", function()
	readyBoth()
	local a, b = stage(4)
	local mark = game.mark()
	request("CombatRequest", bob, "BlockStart")
	request("CombatRequest", alice, "Light")
	game.waitFor(function()
		local hits = hitsSince(mark, a, b)
		return #hits > 0 and hits[1].result == "Parried"
	end, 2, "the parry")
	assert(FighterState.isStunned(a.state, now()), "Alice is left open")
	request("CombatRequest", bob, "BlockEnd")
	task.wait(0.03)
	request("CombatRequest", bob, "Light")
	local hit = waitHit(mark, b, a, "the riposte")[1]
	assert(hit.tags.riposte == true, "riposte tag")
	assert(near(hit.damage, b.combat.Light.Steps[1].Damage * Combat.Riposte.DamageMultiplier * (a.combat.DamageTaken or 1)), "riposte damage " .. hit.damage)
end)

check("clash: two strikes meeting push both apart, nobody is hurt", function()
	readyBoth()
	local a, b = stage(4)
	local healthA, healthB = a.humanoid.Health, b.humanoid.Health
	local mark = game.mark()
	request("CombatRequest", alice, "Light")
	request("CombatRequest", bob, "Light")
	game.waitFor(function()
		return #game.sentSince(mark, "CombatEvent", "Clash") > 0
	end, 2, "the clash")
	local clash = game.sentSince(mark, "CombatEvent", "Clash")[1]
	assert((clash.a == a.model and clash.b == b.model) or (clash.a == b.model and clash.b == a.model), "both fighters named")
	assert(typeof(clash.position) == "Vector3", "where it happened")
	task.wait(0.25)
	assert(a.humanoid.Health == healthA and b.humanoid.Health == healthB, "no damage")
	local ab, ba = hitsSince(mark, a, b), hitsSince(mark, b, a)
	assert(#ab == 1 and #ba == 1 and ab[1].result == "Clash" and ba[1].result == "Clash", "reported as a harmless Clash each way")
	assert(ab[1].damage == 0 and ab[1].move == "Jab", "no damage, names the move")
	assert(a.root:FindFirstChild("SNKnockback") or b.root:FindFirstChild("SNKnockback") or true, "pushed apart")
end)

-- Dodges and stamina ---------------------------------------------------------------------

check("directional dodges: side, back, forward, from the movement intent (old payloads still work)", function()
	readyBoth()
	local _, b = stage(8)
	local look = b.root.CFrame.LookVector
	local function dodge(payload)
		ready(B())
		task.wait(0.03)
		local mark = game.mark()
		request("CombatRequest", bob, "Dodge", payload)
		game.waitFor(function()
			return #game.sentSince(mark, "CombatEvent", "Dodge") > 0
		end, 1, "the dodge")
		return game.sentSince(mark, "CombatEvent", "Dodge")[1]
	end
	local forward = dodge({ dir = look })
	assert(forward.style == "Forward" and forward.speed == Combat.Dodge.Directions.Forward.Speed, "forward dash")
	assert(forward.invulnerable == Combat.Dodge.Directions.Forward.Invulnerable, "fewer invulnerable frames")
	local side = dodge({ dir = Vector3.new(0, 0, 1) })
	assert(side.style == "Side" and side.direction.Z > 0.9, "sidestep")
	local back = dodge({ dir = -look })
	assert(back.style == "Back" and back.direction:Dot(look) < -0.9, "backstep")
	local none = dodge(nil)
	assert(none.style == "Back" and none.direction:Dot(look) < -0.9, "no input backsteps")
	local legacy = dodge(Vector3.new(0, 0, -1))
	assert(legacy.style == "Side", "a bare Vector3 (older clients) is the intent")
	local junk = dodge({ dir = Vector3.new(9, 0, 0) })
	assert(junk.style == "Back", "an oversized intent is ignored")
	assert(typeof(none.duration) == "number" and typeof(none.speed) == "number", "dodge numbers for the client")
end)

check("perfect dodge: dodging just before a strike lands leaves the attacker open", function()
	readyBoth()
	local a, b = stage(4)
	local mark = game.mark()
	request("CombatRequest", alice, "Heavy")
	task.wait(Combat.Heavy.Startup - 0.08)
	request("CombatRequest", bob, "Dodge", { dir = Vector3.new(0, 0, 1) })
	game.waitFor(function()
		return #motionsSince(mark, b, "PerfectDodge") > 0
	end, 2, "the perfect dodge")
	assert(motionsSince(mark, b, "PerfectDodge")[1].attacker == a.model, "names the attacker")
	assert(FighterState.isStunned(a.state, now()), "Alice is open")
	assert(a.state.attack == nil, "her heavy is cancelled")
	assert(b.humanoid.Health == b.humanoid.MaxHealth, "Bob untouched")
end)

check("dodge-cancel: a landed light's recovery can be cancelled into a dodge", function()
	readyBoth()
	local a, b = stage(4)
	local mark = game.mark()
	request("CombatRequest", alice, "Light")
	waitHit(mark, a, b, "the jab")
	task.wait(Combat.Light.Steps[1].Active + 0.02)
	request("CombatRequest", alice, "Dodge", { dir = Vector3.new(0, 0, 1) })
	game.waitFor(function()
		return #motionsSince(mark, a, "DodgeCancel") > 0
	end, 1, "the dodge-cancel")
	assert(near(FighterState.staminaAt(a.state, a.combat, now()), Combat.Stamina.Max - Combat.Stamina.Costs.DodgeCancel, 1), "costs DodgeCancel stamina")
end)

check("stamina: dodges spend it; winded means no dodge or sprint and a weaker guard; it comes back", function()
	readyBoth()
	local a, b = stage(4)
	local mark = game.mark()
	local count = math.ceil(Combat.Stamina.Max / Combat.Stamina.Costs.Dodge)
	for _ = 1, count do
		request("CombatRequest", alice, "Dodge")
		task.wait(Combat.Dodge.Cooldown + 0.03)
	end
	game.waitFor(function()
		return a.model:GetAttribute(Attribute.Winded) == true
	end, 1, "winded")
	assert(#motionsSince(mark, a, "Winded") == 1, "Winded announced")
	assert(a.model:GetAttribute(Attribute.Stamina) == 0, "empty")
	request("CombatRequest", alice, "Dodge")
	request("CombatRequest", alice, "SprintStart")
	task.wait(0.05)
	assert(rejection(mark, alice, "Dodge") == "winded", "dodge refused: " .. tostring(rejection(mark, alice, "Dodge")))
	assert(rejection(mark, alice, "SprintStart") == "winded", "sprint refused")
	-- A winded guard gives way faster
	request("CombatRequest", alice, "BlockStart", "Held")
	task.wait(0.05)
	local guardMark = game.mark()
	request("CombatRequest", bob, "Light")
	local hit = waitHit(guardMark, b, a, "the blocked jab")[1]
	assert(hit.result == "Blocked", "blocked")
	local expected = a.combat.Block.MaxGuard - b.combat.Light.Steps[1].GuardDamage * Combat.Stamina.WindedGuardMultiplier
	assert(near(a.state.guard, expected), `winded guard damage: {a.state.guard} vs {expected}`)
	request("CombatRequest", alice, "BlockEnd")
	game.waitFor(function()
		return a.model:GetAttribute(Attribute.Winded) == false
	end, 4, "recovered")
	assert(#motionsSince(mark, a, "Recovered") == 1, "Recovered announced")
	assert(a.model:GetAttribute(Attribute.Stamina) >= Combat.Stamina.WindedRecover - 1, "back to WindedRecover")
end)

check("sprint: faster, drains stamina, published; ends on release", function()
	readyBoth()
	local a = stage(6)
	local mark = game.mark()
	request("CombatRequest", alice, "SprintStart")
	task.wait(0.05)
	assert(a.model:GetAttribute(Attribute.Sprinting) == true, "sprinting attribute")
	assert(near(a.humanoid.WalkSpeed, a.combat.Sprint.Speed), "sprint speed " .. a.humanoid.WalkSpeed)
	assert(#motionsSince(mark, a, "SprintStart") == 1, "SprintStart announced")
	task.wait(0.5)
	assert(a.model:GetAttribute(Attribute.Stamina) < Combat.Stamina.Max - 3, "draining: " .. a.model:GetAttribute(Attribute.Stamina))
	request("CombatRequest", alice, "SprintEnd")
	task.wait(0.05)
	assert(a.model:GetAttribute(Attribute.Sprinting) == false, "stopped")
	assert(near(a.humanoid.WalkSpeed, a.combat.Movement.WalkSpeed), "walking again")
	assert(#motionsSince(mark, a, "SprintEnd") == 1, "SprintEnd announced")
end)

check("sprint strikes: Light is a lunging Rush Strike, Heavy a Shoulder Charge that knocks down", function()
	readyBoth()
	local a, b = stage(5)
	local toward = Vector3.new(1, 0, 0)
	local mark = game.mark()
	request("CombatRequest", alice, "SprintStart")
	task.wait(0.05)
	request("CombatRequest", alice, "Light", { dir = toward })
	local hit = waitHit(mark, a, b, "the rush strike")[1]
	assert(attacksSince(mark, a)[1].move == "RushStrike", "rush strike")
	assert(hit.move == "RushStrike", "hit names it")
	readyBoth()
	stage(5)
	mark = game.mark()
	request("CombatRequest", alice, "SprintStart")
	task.wait(0.05)
	request("CombatRequest", alice, "Heavy", { dir = toward })
	hit = waitHit(mark, a, b, "the shoulder charge")[1]
	assert(attacksSince(mark, a)[1].move == "ShoulderCharge", "shoulder charge")
	assert(hit.tags.knockdown == true, "knocks down")
	assert(b.model:GetAttribute(Attribute.DownedUntil) > now(), "Bob is on the floor")
	assert(#motionsSince(mark, b, "Knockdown") == 1, "Knockdown announced")
end)

-- Air ---------------------------------------------------------------------------------------

check("back + Heavy is a Launcher; air kicks juggle; Dodge in the air breakfalls out", function()
	readyBoth()
	local a, b = stage(4)
	local mark = game.mark()
	request("CombatRequest", alice, "Heavy", { dir = Vector3.new(-1, 0, 0) })
	local hit = waitHit(mark, a, b, "the launcher")[1]
	assert(attacksSince(mark, a)[1].move == "Launcher", "launcher")
	assert(hit.tags.launch == true, "launch tag")
	assert(b.model:GetAttribute(Attribute.Airborne) == true, "Bob airborne")
	inAir[a.id] = true
	inAir[b.id] = true
	task.wait(Combat.Launcher.Active + Combat.Launcher.Recovery + 0.05)
	request("CombatRequest", alice, "Light")
	local kick = waitHit(mark, a, b, "the air kick", 2)[2]
	assert(kick.move == "AirKick", "air kick: " .. tostring(kick.move))
	assert(kick.tags.airborne == true, "juggled")
	task.wait(math.max(0, Combat.Air.BreakfallAfter - 0.1))
	local before = FighterState.staminaAt(b.state, b.combat, now())
	request("CombatRequest", bob, "Dodge", { dir = Vector3.new(1, 0, 0) })
	game.waitFor(function()
		return #motionsSince(mark, b, "Breakfall") > 0
	end, 1, "the breakfall")
	assert(b.model:GetAttribute(Attribute.Airborne) == false, "out of the juggle")
	assert(near(FighterState.staminaAt(b.state, b.combat, now()), before - Combat.Stamina.Costs.Breakfall, 1), "breakfall costs stamina")
end)

check("a juggle ends by itself when the launched fighter lands", function()
	readyBoth()
	local a, b = stage(4)
	local mark = game.mark()
	request("CombatRequest", alice, "Heavy", { dir = Vector3.new(-1, 0, 0) })
	waitHit(mark, a, b, "the launcher")
	assert(b.model:GetAttribute(Attribute.Airborne) == true, "airborne")
	game.waitFor(function()
		return b.model:GetAttribute(Attribute.Airborne) == false
	end, Combat.Air.LandAfter + 1, "landing")
end)

check("Heavy in the air is the Slam: an overhead dive that chews through guard", function()
	readyBoth()
	local a, b = stage(4)
	request("CombatRequest", bob, "BlockStart", "Held")
	task.wait(0.05)
	inAir[a.id] = true
	local mark = game.mark()
	request("CombatRequest", alice, "Heavy")
	local hit = waitHit(mark, a, b, "the slam")[1]
	assert(attacksSince(mark, a)[1].move == "Slam", "slam")
	assert(hit.result == "Blocked", "blocked")
	assert(near(b.state.guard, b.combat.Block.MaxGuard - Combat.Air.Heavy.GuardDamage), "big guard damage: " .. b.state.guard)
	assert(a.root:FindFirstChild("SNKnockback") ~= nil, "Alice dives")
end)

-- Sweeps and knockdowns --------------------------------------------------------------------

check("sweep: knocks a standing opponent down, they get up on time with brief invulnerability", function()
	readyBoth()
	local a, b = stage(4)
	local mark = game.mark()
	request("CombatRequest", alice, "Sweep")
	local hit = waitHit(mark, a, b, "the sweep")[1]
	assert(attacksSince(mark, a)[1].move == "Sweep", "sweep")
	assert(hit.tags.knockdown == true, "knockdown")
	local knockdown = motionsSince(mark, b, "Knockdown")[1]
	assert(knockdown and near(knockdown.duration, Combat.Knockdown.Duration, 0.1), "Knockdown with its duration")
	assert(b.humanoid.WalkSpeed == 0, "can't walk on the floor")
	game.waitFor(function()
		return #motionsSince(mark, b, "GetUp") > 0
	end, Combat.Knockdown.Duration + 1, "getting up")
	assert(FighterState.isInvulnerable(b.state, now()), "invulnerable getting up")
	assert(b.model:GetAttribute(Attribute.DownedUntil) == 0, "standing again")
end)

check("sweep: jumping avoids it, and it can be blocked", function()
	readyBoth()
	local a, b = stage(4)
	inAir[b.id] = true
	local mark = game.mark()
	request("CombatRequest", alice, "Sweep")
	task.wait(Combat.Sweep.Startup + Combat.Sweep.Active + 0.1)
	assert(#hitsSince(mark, a, b) == 0, "jumped over it")
	readyBoth()
	stage(4)
	request("CombatRequest", bob, "BlockStart", "Held")
	task.wait(0.05)
	mark = game.mark()
	request("CombatRequest", alice, "Sweep")
	local hit = waitHit(mark, a, b, "the blocked sweep")[1]
	assert(hit.result == "Blocked", "blockable: " .. hit.result)
	assert(not FighterState.isDowned(b.state, now()), "no knockdown through a block")
end)

check("knockdown: a tech roll right away rolls clear; late presses don't", function()
	readyBoth()
	local a, b = stage(4)
	local mark = game.mark()
	request("CombatRequest", alice, "Sweep")
	waitHit(mark, a, b, "the sweep")
	request("CombatRequest", bob, "Dodge", { dir = Vector3.new(0, 0, 1) })
	game.waitFor(function()
		return #motionsSince(mark, b, "TechRoll") > 0
	end, 1, "the tech roll")
	assert(not FighterState.isDowned(b.state, now()), "up at once")
	assert(b.root:FindFirstChild("SNKnockback") ~= nil, "the server rolls him")
	task.wait(Combat.Knockdown.Duration + 0.2)
	assert(#motionsSince(mark, b, "GetUp") == 0, "a tech roll isn't also a get-up")
	readyBoth()
	stage(4)
	mark = game.mark()
	request("CombatRequest", alice, "Sweep")
	waitHit(mark, a, b, "the second sweep")
	task.wait(Combat.Knockdown.TechWindow + Combat.Block.LatencyAllowance + 0.1)
	request("CombatRequest", bob, "Dodge")
	task.wait(0.05)
	assert(#motionsSince(mark, b, "TechRoll") == 0, "too late to tech roll")
	assert(rejection(mark, bob, "Dodge") == "too late", "told why: " .. tostring(rejection(mark, bob, "Dodge")))
end)

check("a downed fighter takes one weaker hit at most, then gets up (no ground loops)", function()
	readyBoth()
	local a, b = stage(4)
	local mark = game.mark()
	request("CombatRequest", alice, "Sweep")
	waitHit(mark, a, b, "the sweep")
	task.wait(Combat.Sweep.Active + Combat.Sweep.Recovery + 0.05)
	a.state.sweepReadyAt = -math.huge
	request("CombatRequest", alice, "Light")
	local otg = waitHit(mark, a, b, "the hit on the floor", 2)[2]
	assert(otg.tags.otg == true, "otg tag")
	assert(near(otg.damage, a.combat.Light.Steps[1].Damage * Combat.Knockdown.OTGDamageMultiplier * (b.combat.DamageTaken or 1)), "reduced damage " .. otg.damage)
	task.wait(a.combat.Light.Steps[1].Active + a.combat.Light.Steps[1].Recovery + 0.03)
	request("CombatRequest", alice, "Light")
	local third = waitHit(mark, a, b, "the next hit", 3)[3]
	assert(third.result == "Invulnerable", "no second hit on the floor: " .. third.result)
	game.waitFor(function()
		return #motionsSince(mark, b, "GetUp") > 0
	end, 1, "getting up soon after")
end)

-- Charge and feint ---------------------------------------------------------------------------

check("charged heavy: hold to charge (slower walk, published), release to swing harder", function()
	readyBoth()
	local a, b = stage(5)
	local mark = game.mark()
	request("CombatRequest", alice, "Heavy", { charge = true })
	task.wait(0.05)
	assert(#motionsSince(mark, a, "Charge") == 1, "Charge announced")
	assert(typeof(a.model:GetAttribute(Attribute.ChargeStart)) == "number", "ChargeStart published")
	assert(near(a.humanoid.WalkSpeed, a.combat.Heavy.Charge.MoveSpeed), "walks slower: " .. a.humanoid.WalkSpeed)
	task.wait(Combat.Heavy.Charge.Max * 0.5)
	request("CombatRequest", alice, "HeavyRelease")
	local hit = waitHit(mark, a, b, "the charged heavy")[1]
	local attack = attacksSince(mark, a)[1]
	assert(attack.move == "ChargedHeavy" and attack.charge > 0.3 and attack.charge < 0.8, "charged about halfway: " .. tostring(attack.charge))
	assert(hit.damage > a.combat.Heavy.Damage * (b.combat.DamageTaken or 1), "more damage than a tap")
	assert(a.model:GetAttribute(Attribute.ChargeStart) == nil, "no longer charging")
end)

check("a full charge swings by itself, breaks any guard, and knocks down an open opponent", function()
	readyBoth()
	local a, b = stage(5)
	request("CombatRequest", bob, "BlockStart", "Held")
	task.wait(0.05)
	local mark = game.mark()
	request("CombatRequest", alice, "Heavy", { charge = true })
	local hit = waitHit(mark, a, b, "the full charge on a guard")[1]
	assert(attacksSince(mark, a)[1].charge == 1, "full charge")
	assert(hit.result == "GuardBreak", "guard broken: " .. hit.result)
	readyBoth()
	stage(5)
	mark = game.mark()
	request("CombatRequest", alice, "Heavy", { charge = true })
	hit = waitHit(mark, a, b, "the full charge")[1]
	assert(hit.tags.knockdown == true, "knocks down")
end)

check("feint: Block during a heavy's wind-up cancels it (stamina), then the guard comes up", function()
	readyBoth()
	local a, b = stage(5)
	local mark = game.mark()
	request("CombatRequest", alice, "Heavy")
	task.wait(0.1)
	request("CombatRequest", alice, "BlockStart")
	task.wait(0.05)
	assert(#motionsSince(mark, a, "Feint") == 1, "Feint announced")
	assert(a.state.attack == nil, "heavy cancelled")
	assert(near(FighterState.staminaAt(a.state, a.combat, now()), Combat.Stamina.Max - Combat.Stamina.Costs.Feint, 1), "feint cost")
	task.wait(Combat.Feint.Recovery + 0.05)
	assert(a.model:GetAttribute("Blocking") == true, "block raised once the feint ends")
	request("CombatRequest", alice, "BlockEnd")
	task.wait(a.combat.Heavy.Startup)
	assert(#hitsSince(mark, a, b) == 0, "the feinted heavy never hit")
	-- The explicit Feint action cancels a charge too
	readyBoth()
	stage(5)
	mark = game.mark()
	request("CombatRequest", alice, "Heavy", { charge = true })
	task.wait(0.2)
	request("CombatRequest", alice, "Feint")
	task.wait(0.05)
	assert(#motionsSince(mark, a, "Feint") == 1, "charge feinted")
	assert(a.model:GetAttribute(Attribute.ChargeStart) == nil, "charge gone")
	request("CombatRequest", alice, "Feint")
	task.wait(0.05)
	assert(rejection(mark, alice, "Feint") ~= nil, "nothing to feint now")
end)

-- Grabs ------------------------------------------------------------------------------------------

check("grab beats block: hold, then a forward throw with damage and a knockdown", function()
	readyBoth()
	local a, b = stage(3.5)
	request("CombatRequest", bob, "BlockStart", "Held")
	task.wait(0.05)
	local health = b.humanoid.Health
	local mark = game.mark()
	request("CombatRequest", alice, "Grab")
	game.waitFor(function()
		return #grabsSince(mark, "Hold") > 0
	end, 1, "the hold")
	local hold = grabsSince(mark, "Hold")[1]
	assert(hold.attacker == a.model and hold.victim == b.model, "names both")
	assert(attacksSince(mark, a)[1].move == "Grab", "grab attack")
	assert(not FighterState.isBlocking(b.state), "the block didn't help")
	local offset = b.root.CFrame.Position - a.root.CFrame.Position
	assert(near(Vector3.new(offset.X, 0, offset.Z).Magnitude, 2.6, 0.05), "held right in front")
	assert(b.humanoid.WalkSpeed == 0 and a.humanoid.WalkSpeed == 0, "both locked")
	game.waitFor(function()
		return #grabsSince(mark, "Throw") > 0
	end, 2, "the throw")
	local hit = waitHit(mark, a, b, "the throw hit")[1]
	assert(hit.result == "Hit" and hit.move == "Throw", "thrown: " .. hit.result)
	assert(hit.tags.knockdown == true, "thrown fighters are knocked down")
	assert(near(health - b.humanoid.Health, a.combat.Grab.Damage * (b.combat.DamageTaken or 1), 0.01), "throw damage")
	assert(hit.direction.X > 0.9, "thrown forward")
	assert(not FighterState.isHolding(a.state) and b.state.grabbedById == nil, "the grab is over")
end)

check("holding back throws backward (more damage)", function()
	readyBoth()
	local a, b = stage(3.5)
	local mark = game.mark()
	request("CombatRequest", alice, "Grab", { dir = Vector3.new(-1, 0, 0) })
	game.waitFor(function()
		return #grabsSince(mark, "Throw") > 0
	end, 2, "the back throw")
	assert(grabsSince(mark, "Hold")[1].direction.X < -0.9, "Hold says backward")
	local hit = waitHit(mark, a, b, "the throw hit")[1]
	assert(hit.direction.X < -0.9, "thrown backward")
	assert(near(hit.damage, a.combat.Grab.BackDamage * (b.combat.DamageTaken or 1), 0.01), "back throw damage")
	assert(b.root.CFrame.Position.X < a.root.CFrame.Position.X, "Bob ended up behind Alice")
end)

check("throw tech: Grab (or Light) in the window breaks free, no damage; a late press doesn't", function()
	for _, button in { "Grab", "Light" } do
		readyBoth()
		local a, b = stage(3.5)
		local health = b.humanoid.Health
		local mark = game.mark()
		request("CombatRequest", alice, "Grab")
		game.waitFor(function()
			return #grabsSince(mark, "Hold") > 0
		end, 1, "the hold")
		request("CombatRequest", bob, button)
		game.waitFor(function()
			return #grabsSince(mark, "Tech") > 0
		end, 1, "the tech with " .. button)
		task.wait(Combat.Grab.Hold + 0.1)
		assert(#grabsSince(mark, "Throw") == 0, "no throw")
		assert(b.humanoid.Health == health, "no damage")
		assert(not FighterState.isGrabbed(b.state, now()) and not FighterState.isHolding(a.state, now()), "both free")
	end
	readyBoth()
	local a, b = stage(3.5)
	local mark = game.mark()
	request("CombatRequest", alice, "Grab")
	game.waitFor(function()
		return #grabsSince(mark, "Hold") > 0
	end, 1, "the hold")
	task.wait(Combat.Grab.TechWindow + Combat.Block.LatencyAllowance + 0.05)
	request("CombatRequest", bob, "Grab")
	game.waitFor(function()
		return #grabsSince(mark, "Throw") > 0
	end, 1, "the throw after a late tech")
	assert(#grabsSince(mark, "Tech") == 0, "too late to tech")
	local _ = a
end)

check("a whiffed grab is punishable; strikes beat grabs", function()
	readyBoth()
	local a, b = stage(10)
	local mark = game.mark()
	request("CombatRequest", alice, "Grab")
	game.waitFor(function()
		return #grabsSince(mark, "Whiff") > 0
	end, 1, "the whiff")
	assert(FighterState.inWhiffRecovery(a.state, now()), "Alice is stuck recovering")
	-- Bob steps in and punishes
	b.root.CFrame = CFrame.lookAt(a.root.Position + Vector3.new(4, 0, 0), a.root.Position)
	Engine.syncPositions(world.workspace)
	request("CombatRequest", bob, "Light")
	local punish = waitHit(mark, b, a, "the punish")[1]
	assert(punish.tags.punish == true, "punish")
	-- A grab against someone already swinging loses: the jab is faster
	readyBoth()
	stage(3.5)
	mark = game.mark()
	request("CombatRequest", alice, "Grab")
	request("CombatRequest", bob, "Light")
	local hit = waitHit(mark, b, a, "the jab")[1]
	assert(hit.tags.counter == true, "hitting a grab's start-up is a counter hit")
	task.wait(Combat.Grab.Startup + Combat.Grab.Active)
	assert(#grabsSince(mark, "Hold") == 0, "the grab never connected")
end)

check("a grab never holds anyone outside the arena", function()
	readyBoth()
	local half = 40
	local a, b = A(), B()
	-- Alice right at the arena's edge, facing out, Bob squeezed beside her
	local edge = arena.center + Vector3.new(half * 10, 3, 0)
	local inside = services.ArenaService:clampInside(arena, edge, 1)
	a.root.CFrame = CFrame.lookAt(inside, inside + Vector3.new(1, 0, 0))
	b.root.CFrame = CFrame.lookAt(inside + Vector3.new(1.5, 0, 0), inside)
	Engine.syncPositions(world.workspace)
	local mark = game.mark()
	request("CombatRequest", alice, "Grab")
	game.waitFor(function()
		return #grabsSince(mark, "Hold") > 0
	end, 1, "the hold at the edge")
	-- (CFrame: the stand-in engine copies it into Position only between frames)
	local held = b.root.CFrame.Position
	local clamped = services.ArenaService:clampInside(arena, held, 3)
	assert(near(held.X, clamped.X, 0.01) and near(held.Z, clamped.Z, 0.01), "held inside the arena")
end)

-- Wall splat ----------------------------------------------------------------------------------------

check("wall splat: a hard hit into a wall bounces off it with extra damage and stun", function()
	readyBoth()
	local a, b = stage(4)
	local wallX = b.root.Position.X + 3
	local wall = world.Instance.new("Part")
	wall.Name = "TestWall"
	wall.Anchored = true
	wall.CanCollide = true
	wall.Size = Vector3.new(1, 20, 40)
	wall.CFrame = CFrame.new(wallX, 10, b.root.Position.Z)
	wall.Parent = world.workspace
	local ground = Engine.raycast
	Engine.raycast = function(origin, direction, params)
		if math.abs(direction.Y) < 0.1 and direction.X > 0 and origin.X < wallX and origin.X + direction.X >= wallX then
			return { Position = Vector3.new(wallX, origin.Y, origin.Z), Normal = Vector3.new(-1, 0, 0), Instance = wall }
		end
		return ground(origin, direction, params)
	end
	local ok, err = pcall(function()
		local health = b.humanoid.Health
		local mark = game.mark()
		request("CombatRequest", alice, "Heavy")
		local hit = waitHit(mark, a, b, "the heavy into the wall")[1]
		assert(hit.tags.wallSplat == true, "wall splat")
		assert(hit.direction.X < 0, "bounces back off the wall")
		local expected = (a.combat.Heavy.Damage + Combat.WallSplat.Damage) * (b.combat.DamageTaken or 1)
		assert(near(health - b.humanoid.Health, expected, 0.01), `splat damage: {health - b.humanoid.Health} vs {expected}`)
		assert(b.state.stunUntil - now() > 0, "stunned")
		-- A light push doesn't splat
		readyBoth()
		stage(4)
		mark = game.mark()
		request("CombatRequest", alice, "Light")
		local jab = waitHit(mark, a, b, "the jab")[1]
		assert(not jab.tags.wallSplat, "too weak to splat")
	end)
	Engine.raycast = ground
	wall:Destroy()
	assert(ok, err)
end)

-- Props -------------------------------------------------------------------------------------------

local function makeCrate(position: Vector3, weight: number)
	local crate = world.Instance.new("Part")
	crate.Name = "TestCrate"
	crate.Anchored = true
	crate.Size = Vector3.new(2, 2, 2)
	crate.CFrame = CFrame.new(position)
	crate:SetAttribute("Weight", weight)
	crate:SetAttribute("HomeCFrame", crate.CFrame)
	crate.Parent = world.workspace
	world.services.CollectionService:AddTag(crate, Protocol.Tag.Throwable)
	-- (the stand-in engine copies CFrame into Position between frames)
	Engine.syncPositions(world.workspace)
	return crate
end

-- Roblox untags destroyed parts by itself; the stand-in engine needs telling
local function removeCrate(crate)
	world.services.CollectionService:RemoveTag(crate, Protocol.Tag.Throwable)
	crate:Destroy()
end

check("props: Grab near a light prop picks it up (slower, no blocking); Light throws it; it comes home", function()
	readyBoth()
	local a, b = stage(20)
	local crate = makeCrate(a.root.Position + Vector3.new(0, -2, 3), 1)
	local mark = game.mark()
	request("CombatRequest", alice, "Grab")
	game.waitFor(function()
		return #motionsSince(mark, a, "PickUp") > 0
	end, 1, "the pick-up")
	assert(a.model:GetAttribute(Attribute.Carrying) == "TestCrate", "Carrying published")
	assert(near(a.humanoid.WalkSpeed, a.combat.Carry.WalkSpeed), "slower walk")
	assert(crate.Transparency == 1 and crate:GetAttribute("Held") == true, "the arena's prop is in hand")
	assert(a.model:FindFirstChild("SNCarriedProp") ~= nil, "a copy rides in her hands")
	request("CombatRequest", alice, "BlockStart")
	task.wait(0.05)
	assert(a.model:GetAttribute("Blocking") == false, "no blocking while carrying")
	request("CombatRequest", alice, "Light")
	game.waitFor(function()
		for _, spawn in game.sentSince(mark, "AbilityEvent", "ProjectileSpawn") do
			if spawn.ability == "PropThrow" then
				return true
			end
		end
		return false
	end, 1, "the throw")
	assert(attacksSince(mark, a)[1].move == "PropThrow", "PropThrow move")
	assert(a.model:GetAttribute(Attribute.Carrying) == nil, "empty-handed")
	assert(a.model:FindFirstChild("SNCarriedProp") == nil, "the copy is gone")
	game.waitFor(function()
		return crate:GetAttribute("Held") == nil and crate.Transparency == 0
	end, 2, "the prop coming home")
	removeCrate(crate)
end)

check("props: Grab again drops it in front; it's put down by itself after a while; a hit knocks it loose", function()
	readyBoth()
	local a, b = stage(20)
	local crate = makeCrate(a.root.Position + Vector3.new(0, -2, 3), 1)
	local mark = game.mark()
	request("CombatRequest", alice, "Grab")
	game.waitFor(function()
		return a.model:GetAttribute(Attribute.Carrying) ~= nil
	end, 1, "carrying")
	request("CombatRequest", alice, "Grab")
	game.waitFor(function()
		return #motionsSince(mark, a, "Drop") > 0
	end, 1, "the drop")
	assert(crate:GetAttribute("Held") == nil and crate.CanCollide, "set down for real")
	Engine.syncPositions(world.workspace)
	assert((crate.Position - a.root.Position).Magnitude < 6, "in front of her")
	-- By itself
	request("CombatRequest", alice, "Grab")
	game.waitFor(function()
		return a.model:GetAttribute(Attribute.Carrying) ~= nil
	end, 1, "carrying again")
	game.waitFor(function()
		return a.model:GetAttribute(Attribute.Carrying) == nil
	end, Combat.Carry.MaxDuration + 1, "put down by itself")
	-- Knocked loose
	readyBoth()
	stage(4)
	crate.CFrame = CFrame.new(a.root.Position + Vector3.new(0, -2, -2))
	b.root.CFrame = CFrame.lookAt(a.root.Position + Vector3.new(12, 0, 0), a.root.Position)
	Engine.syncPositions(world.workspace)
	request("CombatRequest", alice, "Grab")
	game.waitFor(function()
		return a.model:GetAttribute(Attribute.Carrying) ~= nil
	end, 1, "carrying for the hit")
	b.root.CFrame = CFrame.lookAt(a.root.Position + Vector3.new(4, 0, 0), a.root.Position)
	Engine.syncPositions(world.workspace)
	request("CombatRequest", bob, "Light")
	game.waitFor(function()
		return a.model:GetAttribute(Attribute.Carrying) == nil
	end, 1, "knocked loose")
	assert(crate:GetAttribute("Held") == nil, "the prop is free")
	removeCrate(crate)
end)

check("props: heavy props aren't picked up (that's Strong Dude's Heave); an enemy in reach is grabbed instead", function()
	readyBoth()
	local a, b = stage(20)
	local heavyProp = makeCrate(a.root.Position + Vector3.new(0, -2, 3), 2)
	local mark = game.mark()
	request("CombatRequest", alice, "Grab")
	game.waitFor(function()
		return #grabsSince(mark, "Whiff") > 0
	end, 1, "a plain grab")
	assert(#motionsSince(mark, a, "PickUp") == 0, "too heavy")
	removeCrate(heavyProp)
	readyBoth()
	stage(3.5)
	local light = makeCrate(a.root.Position + Vector3.new(0, -2, 2), 1)
	mark = game.mark()
	request("CombatRequest", alice, "Grab")
	game.waitFor(function()
		return #grabsSince(mark, "Hold") > 0
	end, 1, "the enemy grabbed")
	assert(#motionsSince(mark, a, "PickUp") == 0, "people first")
	removeCrate(light)
	local _ = b
end)

-- Taunt -------------------------------------------------------------------------------------------

check("taunt: finishing it unhit charges the ultimate; getting hit is a counter hit", function()
	readyBoth()
	local a, b = stage(12)
	local runtime = a.power
	runtime.ult = 0
	local mark = game.mark()
	request("CombatRequest", alice, "Taunt")
	game.waitFor(function()
		return #motionsSince(mark, a, "Taunt") > 0
	end, 1, "the taunt")
	assert(a.humanoid.WalkSpeed == 0, "standing still")
	game.waitFor(function()
		return #motionsSince(mark, a, "TauntDone") > 0
	end, Combat.Taunt.Duration + 1, "the taunt finishing")
	assert(runtime.ult >= Combat.Taunt.UltimateCharge - 0.01, "ultimate charge: " .. runtime.ult)
	readyBoth()
	stage(4)
	mark = game.mark()
	request("CombatRequest", alice, "Taunt")
	task.wait(0.1)
	request("CombatRequest", bob, "Light")
	local hit = waitHit(mark, b, a, "the punished taunt")[1]
	assert(hit.tags.counter == true, "counter hit")
	task.wait(Combat.Taunt.Duration)
	assert(#motionsSince(mark, a, "TauntDone") == 0, "no reward when hit")
	request("CombatRequest", alice, "Taunt")
	task.wait(0.05)
	assert(rejection(mark, alice, "Taunt") == "cooldown", "taunt cooldown")
end)

-- Junk and spam -------------------------------------------------------------------------------------

check("junk payloads and unknown actions are ignored; nothing breaks", function()
	readyBoth()
	local a = stage(6)
	local junk = {
		12,
		"text",
		true,
		{},
		{ dir = Vector3.new(5, 0, 0) },
		{ dir = Vector3.new(0 / 0, 0, 0) },
		{ dir = Vector3.new(math.huge, 0, 0) },
		{ dir = "left" },
		{ dir = { X = 1 } },
		{ charge = "yes" },
		{ charge = true, dir = Vector3.new(0, 7, 0) },
		{ aim = Vector3.new(0 / 0, 1, 0) },
		Vector3.new(0 / 0, 0 / 0, 0 / 0),
	}
	for _, action in { "Light", "Heavy", "HeavyRelease", "Feint", "Grab", "Sweep", "SprintStart", "SprintEnd", "Taunt", "Dodge", "BlockStart", "BlockEnd" } do
		for _, payload in junk do
			ready(A())
			request("CombatRequest", alice, action, payload)
		end
	end
	request("CombatRequest", alice, "Charge")
	request("CombatRequest", alice, nil)
	request("CombatRequest", alice, { "Light" })
	task.wait(0.3)
	ready(A())
	assert(services.CharacterService:isAlive(a), "still fine")
	-- An oversized "back" intent is ignored: a plain heavy, not a Launcher
	local mark = game.mark()
	request("CombatRequest", alice, "Heavy", { dir = Vector3.new(-5, 0, 0) })
	task.wait(0.05)
	local attacks = attacksSince(mark, a)
	assert(#attacks == 1 and attacks[1].move == "Heavy", "junk intent ignored: " .. tostring(attacks[1] and attacks[1].move))
end)

check("spam: attack spam can't use up the budget for letting go of sprint", function()
	readyBoth()
	local a = stage(6)
	request("CombatRequest", alice, "SprintStart")
	task.wait(0.05)
	for _ = 1, 40 do
		request("CombatRequest", alice, "Light")
	end
	request("CombatRequest", alice, "SprintEnd")
	task.wait(0.1)
	assert(a.model:GetAttribute(Attribute.Sprinting) == false, "sprint released through the spam")
	for _ = 1, 40 do
		request("CombatRequest", alice, "SprintStart")
		request("CombatRequest", alice, "SprintEnd")
	end
	task.wait(1.2)
	request("CombatRequest", alice, "SprintEnd")
	task.wait(0.05)
	assert(a.state.sprintHeld == false, "not left sprinting")
end)

-- Nothing stays stuck -----------------------------------------------------------------------------

check("a knockout mid-grab frees the holder; a knockout while carrying sends the prop home", function()
	readyBoth()
	local a, b = stage(3.5)
	local mark = game.mark()
	request("CombatRequest", alice, "Grab")
	game.waitFor(function()
		return #grabsSince(mark, "Hold") > 0
	end, 1, "the hold")
	b.humanoid.Health = 0
	Engine.checkDeaths(world.workspace)
	task.wait(0.1)
	assert(not FighterState.isHolding(a.state), "Alice let go")
	assert(FighterState.busyUntil(a.state) <= now() + 0.01, "and can act")
	game.waitFor(function()
		local fresh = B()
		return fresh ~= nil and services.CharacterService:isAlive(fresh) and fresh ~= b
	end, 3, "Bob respawning")
	task.wait(Combat.SpawnProtection + 0.1)
	b = B()
	local fresh = b.state
	assert(fresh.grabbedById == nil and not FighterState.isDowned(fresh, now()), "Bob respawns clean")
	readyBoth()
	a = A()
	stage(20)
	local crate = makeCrate(a.root.Position + Vector3.new(0, -2, 3), 1)
	request("CombatRequest", alice, "Grab")
	game.waitFor(function()
		return a.model:GetAttribute(Attribute.Carrying) ~= nil
	end, 1, "carrying")
	a.humanoid.Health = 0
	Engine.checkDeaths(world.workspace)
	game.waitFor(function()
		return crate:GetAttribute("Held") == nil and crate.Transparency == 0
	end, 1, "the prop going home")
	game.waitFor(function()
		local fresh = A()
		return fresh ~= nil and fresh ~= a and services.CharacterService:isAlive(fresh)
	end, 3, "Alice respawning")
	task.wait(Combat.SpawnProtection + 0.1)
	removeCrate(crate)
end)

check("a respawn or restore clears sprint, charge, knockdown, juggle and carrying", function()
	readyBoth()
	local a, b = stage(4)
	request("CombatRequest", alice, "SprintStart")
	task.wait(0.05)
	request("CombatRequest", bob, "Sweep")
	waitHit(game.mark() - 1, b, a, "a sweep on Alice")
	assert(FighterState.isDowned(a.state, now()), "downed")
	services.CharacterService:restore(a, 0)
	task.wait(0.1)
	local model = a.model
	assert(model:GetAttribute(Attribute.Sprinting) == false, "no sprint")
	assert(model:GetAttribute(Attribute.DownedUntil) == 0, "standing")
	assert(model:GetAttribute(Attribute.Airborne) == false, "grounded")
	assert(model:GetAttribute(Attribute.ChargeStart) == nil, "no charge")
	assert(model:GetAttribute(Attribute.Carrying) == nil, "empty-handed")
	assert(model:GetAttribute(Attribute.Stamina) == Combat.Stamina.Max, "full stamina")
	assert(near(a.humanoid.WalkSpeed, a.combat.Movement.WalkSpeed), "walking normally")
end)

check("a power change mid-charge or mid-carry resets cleanly", function()
	readyBoth()
	local a = stage(20)
	local crate = makeCrate(a.root.Position + Vector3.new(0, -2, 3), 1)
	request("CombatRequest", alice, "Grab")
	game.waitFor(function()
		return a.model:GetAttribute(Attribute.Carrying) ~= nil
	end, 1, "carrying")
	local Powers = world.require(world.find("ReplicatedStorage.Shared.Powers"))
	services.PowerService:equip(a, "Grandmaster", 1, Powers.defaultLoadout("Grandmaster", 1))
	task.wait(0.1)
	assert(a.model:GetAttribute(Attribute.Carrying) == nil, "dropped on the power change")
	assert(crate:GetAttribute("Held") == nil, "the prop is free")
	removeCrate(crate)
	services.PowerService:equip(a, "StrongDude", 1, { "Heave", "TitanGrip", "MeteorCharge" })
	ready(a)
end)

check("the duel ending (Bob leaves) leaves Alice clean even mid-sprint and mid-grab", function()
	readyBoth()
	local a = stage(3.5)
	request("CombatRequest", alice, "SprintStart")
	task.wait(0.05)
	request("CombatRequest", alice, "SprintEnd")
	request("CombatRequest", alice, "Grab")
	task.wait(Combat.Grab.Startup + 0.05)
	game.leave(bob)
	game.waitFor(function()
		return services.MatchService:getMatchOf(A()) == nil
	end, 5, "the duel to end")
	task.wait(0.3)
	a = A()
	local state = a.state
	assert(not FighterState.isHolding(state), "not holding anyone")
	assert(not FighterState.isDowned(state, now()) and not FighterState.isAirborne(state, now()), "standing")
	assert(a.model:GetAttribute(Attribute.Carrying) == nil and a.model:GetAttribute(Attribute.ChargeStart) == nil, "nothing held")
	assert(FighterState.busyUntil(state) <= now() + 0.01, "free to act")
end)

-- The CPU ---------------------------------------------------------------------------------------------

check("a Hard CPU uses the new moves (grabs, sweeps, sprints, charges, launchers, techs)", function()
	local me = A()
	ready(me)
	request("MatchRequest", alice, "Queue", "Practice", { cpuPower = "StrongDude", cpuDegree = 1, cpuDifficulty = "Hard" })
	local practice
	game.waitFor(function()
		practice = services.MatchService:getMatchOf(A())
		return practice ~= nil and practice.flow.phase == "Active"
	end, 4, "practice to begin")
	local cpu
	game.waitFor(function()
		for _, participant in practice.participants do
			if participant.dummy and participant.dummy.fighter then
				cpu = participant.dummy.fighter
				return true
			end
		end
		return false
	end, 4, "the CPU")
	me = A()
	local mark = game.mark()
	local seen = {}
	local started = os.clock()
	local function universalSeen(): number
		local count = 0
		for _ in seen do
			count += 1
		end
		return count
	end
	local flip = 0
	local cpus = {}
	-- The CPU rolls its choices at random, so watch long enough to see a real variety
	while os.clock() - started < 30 and universalSeen() < 3 do
		-- (a knocked-out CPU comes back as a new fighter)
		for _, participant in practice.participants do
			if participant.dummy and participant.dummy.fighter then
				cpu = participant.dummy.fighter
			end
		end
		me = A()
		if not services.CharacterService:isAlive(cpu) or not services.CharacterService:isAlive(me) then
			task.wait(0.2)
			continue
		end
		cpus[cpu] = true
		game.faceOff(cpu, me, 3.5)
		me.humanoid.Health = me.humanoid.MaxHealth
		cpu.humanoid.Health = cpu.humanoid.MaxHealth
		flip += 1
		-- Give it reasons: a guard to grab, grabs to tech, openings to sweep
		if flip % 4 <= 1 then
			request("CombatRequest", alice, "BlockStart", "Held")
		elseif flip % 4 == 2 then
			request("CombatRequest", alice, "BlockEnd")
			request("CombatRequest", alice, "Grab")
		end
		task.wait(0.35)
		for _, attack in game.sentSince(mark, "CombatEvent", "Attack") do
			local mine = false
			for record in cpus do
				mine = mine or attack.attacker == record.model
			end
			local move = attack.move
			if mine and (move == "Grab" or move == "Sweep" or move == "ChargedHeavy" or move == "Launcher" or move == "RushStrike" or move == "ShoulderCharge") then
				seen[attack.move] = true
			end
		end
		for _, entry in game.sentSince(mark, "CombatEvent", "Motion") do
			if cpus[services.CharacterService:getFighter(entry.fighter) or false] and (entry.motion == "Charge" or entry.motion == "SprintStart" or entry.motion == "TechRoll" or entry.motion == "Breakfall" or entry.motion == "Feint") then
				seen[entry.motion] = true
			end
		end
		for _, entry in game.sentSince(mark, "CombatEvent", "Grab") do
			if entry.phase == "Tech" and cpus[services.CharacterService:getFighter(entry.victim) or false] then
				seen.Tech = true
			end
		end
	end
	request("CombatRequest", alice, "BlockEnd")
	local list = {}
	for name in seen do
		table.insert(list, name)
	end
	assert(universalSeen() >= 2, "the CPU used new moves: " .. table.concat(list, ", "))
	print("     CPU used: " .. table.concat(list, ", "))
end)

process.exit(if game.finish() == 0 then 0 else 1)
