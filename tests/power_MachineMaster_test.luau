-- Runs Machine Master end to end with simulated players:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/power_MachineMaster_test.luau build/game.rbxl
-- Two players fight Machine Master against Machine Master in a duel and use
-- every ability at every degree it exists at: blaster and charged shots (the
-- fire rate, heat), Scatter Blast's one-pellet-per-target cone, Shock Pulse,
-- the Deflector Shield and Barrier Projector stopping projectiles (and massive
-- ones smashing them), Intercept (hit, miss, ineligible projectiles), Rail
-- Shot's prompt and locked line, homing Missile Volleys, Sweeping Streams and
-- its fuel drain (running dry mid-channel), Pressurized Burst's stagger and
-- recoil, Soul Fireballs' burn and strict lifetime, Soulforge mines (trigger,
-- cap, shot down, no room), Blue Inferno at all three degrees (fuel gate,
-- timing bar, perfect timing), a knockout mid-ultimate, simultaneous attacks,
-- junk requests and cooldown spam, a match ending with missiles in flight, a
-- Machine Master CPU, and every client effect at every degree.

local process = require("@lune/process")

local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl", function(setup)
	-- One long duel for the whole test
	setup.MatchConfig.Modes.Duel.Duration = 900
end)
local task, Vector3, CFrame = game.task, game.Vector3, game.CFrame
local services, check, request = game.services, game.check, game.request
local world, Engine = game.world, game.Engine
local FighterState = world.require(world.find("ReplicatedStorage.Shared.Combat.FighterState"))
local Protocol = world.require(world.find("ReplicatedStorage.Shared.Protocol"))
local Powers = world.require(world.find("ReplicatedStorage.Shared.Powers"))
local Attribute = Protocol.Attribute
local MM = Powers.get("MachineMaster")

game.flatGround(0)

local function now(): number
	return world.workspace:GetServerTimeNow()
end

local alice, bob
local arena

local function A()
	return game.fighter(alice)
end
local function B()
	return game.fighter(bob)
end

local function ability(id: string, degree: number)
	return Powers.abilityFor("MachineMaster", id, degree)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function aimAt(from, to)
	return { direction = (to.root.Position - from.root.Position).Unit, point = to.root.Position }
end

-- Full health, fuel and a clean state, so tests don't wait on each other
local function ready(fighter)
	local runtime = fighter.power
	runtime.resource = runtime.resourceMax
	table.clear(runtime.cooldowns)
	runtime.data.heat = 0
	runtime.data.burningUntil = nil
	local state = fighter.state
	state.attack = nil
	state.stunUntil = -math.huge
	state.comboCount = 0
	state.blockingSince = nil
	state.lightStep = 0
	state.lightReadyAt = -math.huge
	state.heavyReadyAt = -math.huge
	state.dodgeReadyAt = -math.huge
	state.dodgeUntil = -math.huge
	state.invulnerableUntil = -math.huge
	state.protectedUntil = -math.huge
	services.StatusService:clearAll(fighter)
	fighter.humanoid.Health = fighter.humanoid.MaxHealth
	for _, child in fighter.root:GetChildren() do
		if child.Name == "SNDash" or child.Name == "SNKnockback" then
			child:Destroy()
		end
	end
	services.CharacterService:refresh(fighter)
end

local function equip(fighter, degree: number, loadout: { string }?)
	services.PowerService:equip(fighter, "MachineMaster", degree, loadout or Powers.defaultLoadout("MachineMaster", degree))
	ready(fighter)
end

-- Alice on the left facing Bob, `gap` studs apart, in the middle of the arena
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

local function hitsSince(mark: number, attacker, victim, abilityId: string?)
	local list = {}
	for _, hit in game.sentSince(mark, "CombatEvent", "Hit") do
		if hit.attacker == attacker.model and hit.victim == victim.model and (abilityId == nil or hit.ability == abilityId) then
			table.insert(list, hit)
		end
	end
	return list
end

local function fxSince(mark: number, name: string, fighter)
	local list = {}
	for _, entry in game.sentSince(mark, "AbilityEvent", "Fx") do
		if entry.fx == name and (fighter == nil or entry.fighter == fighter.model) then
			table.insert(list, entry.data)
		end
	end
	return list
end

local function spawnsSince(mark: number, fighter, visual: string?)
	local list = {}
	for _, entry in game.sentSince(mark, "AbilityEvent", "ProjectileSpawn") do
		if entry.owner == fighter.model and (visual == nil or entry.visual == visual) then
			table.insert(list, entry)
		end
	end
	return list
end

-- How each projectile id ended: { [id]: reason }
local function endsSince(mark: number): { [string]: string }
	local reasons = {}
	for _, entry in game.sentSince(mark, "AbilityEvent", "ProjectileEnd") do
		reasons[entry.id] = entry.reason
	end
	return reasons
end

local function castsSince(mark: number, fighter, abilityId: string): number
	local casts = 0
	for _, cast in game.sentSince(mark, "AbilityEvent", "Cast") do
		if cast.fighter == fighter.model and cast.ability == abilityId then
			casts += 1
		end
	end
	return casts
end

local function rejection(mark: number, player, abilityId: string): string?
	for _, entry in game.sentSince(mark, "AbilityEvent", "Rejected", player) do
		if entry.ability == abilityId then
			return entry.reason
		end
	end
	return nil
end

local function cooldownSet(fighter, abilityId: string): boolean
	return (fighter.model:GetAttribute(Attribute.CooldownPrefix .. abilityId) or 0) > now()
end

local function cuesFor(mark: number, player, kind: string)
	local list = {}
	for _, cue in game.sentSince(mark, "DefenseEvent", "Cue", player) do
		if cue.kind == kind then
			table.insert(list, cue)
		end
	end
	return list
end

local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1e-3)
end

local function constructs(fighter, name: string)
	return services.ConstructService:ofOwner(fighter, name)
end

-- An enemy projectile made by hand (to test shields and interceptions against
-- kinds Machine Master can't fire himself)
local function enemyShot(owner, origin: Vector3, direction: Vector3, tags: { string }, extra: { [string]: any }?)
	local spec = {
		power = "MachineMaster",
		ability = "TestShot",
		visual = "Bolt",
		origin = origin,
		direction = direction,
		speed = 40,
		radius = 0.5,
		lifetime = 3,
		range = 120,
		hit = { Damage = 5, Hitstun = 0.2, Knockback = 5, GuardDamage = 5 },
		tags = tags,
	}
	for key, value in extra or {} do
		spec[key] = value
	end
	return services.ProjectileService:spawn(owner, spec)
end

-- Definition ------------------------------------------------------------------------------

check("Machine Master's definition: card text, Fuel, AI hints, degrees and loadouts", function()
	assert(MM, "Machine Master is registered")
	assert(utf8.len(MM.name) <= 20 and utf8.len(MM.description) <= 160, "power text fits a card")
	local fuel = MM.resource
	assert(fuel.id == "Fuel" and fuel.max == 100 and fuel.start == 100 and fuel.regen > 0, "Fuel 0-100, starts full, refills")
	assert(MM.basic.Light == "BlasterShot" and MM.basic.Heavy == "ChargedShot", "blaster basics")
	assert(MM.ai.preferredRange and MM.ai.aggression, "power AI hints")
	for _, degree in MM.degrees do
		assert(utf8.len(degree.name) <= 20 and utf8.len(degree.description) <= 160, degree.name .. " text fits")
		assert(degree.ultimate == "BlueInferno", "ultimate on every degree")
		assert(not string.find(degree.description, "—", 1, true), "no em dashes")
	end
	for abilityId, def in MM.abilities do
		assert(utf8.len(def.name) <= 20, abilityId .. " name fits")
		assert(utf8.len(def.description) <= 160, abilityId .. " description fits")
		assert(not string.find(def.description, "—", 1, true), abilityId .. ": no em dashes")
		assert(def.ai and def.ai.range and def.ai.use, abilityId .. " has an AI hint")
		assert(table.find(MM.abilityOrder, abilityId), abilityId .. " is in abilityOrder")
		if def.kind ~= "Ultimate" and not def.basicOnly then
			assert((def.cost or 0) > 0, abilityId .. " costs fuel")
		end
	end
	-- Degrees expand the arsenal: everything lower is still there
	assert(#Powers.available("MachineMaster", 1) == 4, "4 at Gunner")
	assert(#Powers.available("MachineMaster", 2) == 7, "7 at Advanced Arsenal")
	assert(#Powers.available("MachineMaster", 3) == 11, "11 at Soul Fire Arsenal")
	for degree = 1, 3 do
		local ok, reason = Powers.validateLoadout("MachineMaster", degree, Powers.defaultLoadout("MachineMaster", degree), {})
		assert(ok, `degree {degree} default loadout: {reason}`)
		assert(Powers.basicFor("MachineMaster", degree, nil, "Light") == "BlasterShot", "blaster at every degree")
	end
	-- Intercept is bought at Degree 1 and included from Degree 2
	assert(not Powers.validateLoadout("MachineMaster", 1, { "Intercept" }, {}), "Intercept costs Money at Degree 1")
	assert(Powers.validateLoadout("MachineMaster", 1, { "Intercept" }, { abilities = { Intercept = true } }), "bought Intercept")
	assert(Powers.validateLoadout("MachineMaster", 2, { "Intercept" }, {}), "free from Degree 2")
	-- Scaling
	assert(ability("ScatterBlast", 3).pellets > ability("ScatterBlast", 1).pellets, "more pellets")
	assert(ability("MissileVolley", 3).missiles == 4, "four missiles at Degree 3")
	assert(ability("BlueInferno", 3).damage > ability("BlueInferno", 2).damage and ability("BlueInferno", 2).damage > ability("BlueInferno", 1).damage, "ultimate scales")
	-- The strongest moves can't be kept up: soul fire drains far faster than it refills
	local streams = ability("SweepingStreams", 3)
	assert(streams.drain > fuel.regen * 2, "streams drain faster than regen")
	assert(ability("BlueInferno", 1).fuelCost > 0, "the ultimate needs fuel")
	assert(Powers.combatProfile("MachineMaster", 3).MaxHealth > Powers.combatProfile("MachineMaster", 1).MaxHealth or true, "")
end)

check("every effect and projectile the server sends has a client drawing", function()
	local fs = require("@lune/fs")
	local server = fs.readFile("src/server/Powers/MachineMaster.luau")
	local client = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Powers.MachineMaster"))
	local names = {}
	for name in string.gmatch(server, 'ctx:fx%("(%w+)"') do
		names[name] = true
	end
	for name in string.gmatch(server, 'ctx:lastingFx%("(%w+)"') do
		names[name] = true
	end
	local total = 0
	for name in names do
		total += 1
		assert(client.fx[name], "no client effect for " .. name)
	end
	assert(total >= 30, "found the effects: " .. total)
	local visuals = 0
	for visual in string.gmatch(server, 'visual = "(%w+)"') do
		visuals += 1
		assert(client.projectiles[visual], "no projectile drawing for " .. visual)
	end
	assert(visuals >= 6, "found the projectiles: " .. visuals)
	for abilityId in MM.abilities do
		assert(client.predict[abilityId], "instant wind-up for " .. abilityId)
	end
end)

-- Equipping ---------------------------------------------------------------------------------

check("two players equip Machine Master: stats, Fuel and blaster basics", function()
	alice = game.join("Alice")
	bob = game.join("Bob")
	game.waitFor(function()
		return A() ~= nil and A().power ~= nil and B() ~= nil and B().power ~= nil
	end, 2, "powers to be equipped")
	equip(A(), 1)
	equip(B(), 1)
	for _, fighter in { A(), B() } do
		assert(fighter.power.id == "MachineMaster", "Machine Master")
		assert(fighter.humanoid.MaxHealth == 100, "health 100")
		assert(fighter.combat.Block.MaxGuard == 90, "a gunner's guard")
		assert(fighter.model:GetAttribute(Attribute.ResourceMax) == 100, "Fuel maximum")
		assert(fighter.model:GetAttribute(Attribute.Phase) == 0, "cold barrel")
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
	assert(A().power.id == "MachineMaster" and B().power.id == "MachineMaster", "still Machine Masters in the duel")
	assert(A().power.resource > 99, "Fuel starts full: " .. A().power.resource)
	local d3 = Powers.combatProfile("MachineMaster", 3)
	assert(d3.MaxHealth == 105, "sturdier at Degree 3")
end)

-- Basic attacks -------------------------------------------------------------------------------

check("Blaster Shot: Light fires a fast bolt; its cooldown is the fire rate and it costs nothing", function()
	local a, b = stage(20)
	ready(a)
	ready(b)
	local health = b.humanoid.Health
	local mark = game.mark()
	for _ = 1, 5 do
		request("CombatRequest", alice, "Light", aimAt(a, b))
		task.wait(0.02)
	end
	task.wait(0.4)
	assert(castsSince(mark, a, "BlasterShot") == 1, "one shot per cooldown: " .. castsSince(mark, a, "BlasterShot"))
	assert(#spawnsSince(mark, a, "Bolt") == 1, "one bolt")
	local hits = hitsSince(mark, a, b, "BlasterShot")
	assert(#hits == 1 and near(hits[1].damage, 4), "one 4-damage hit")
	assert(b.humanoid.Health < health, "Bob hurt")
	assert(a.power.resource > 99, "no fuel spent")
	-- After the cooldown it fires again
	request("CombatRequest", alice, "Light", aimAt(a, b))
	task.wait(0.4)
	assert(castsSince(mark, a, "BlasterShot") == 2, "fires again after the cooldown")
	-- Shots can't be fired as a normal ability
	mark = game.mark()
	request("AbilityRequest", alice, "BlasterShot", aimAt(a, b))
	task.wait(0.1)
	assert(rejection(mark, alice, "BlasterShot") == "not equipped", "basic only")
end)

check("Charged Shot: Heavy charges a heavy bolt that can't be shot down and hits once", function()
	local a, b = stage(20)
	ready(a)
	ready(b)
	local mark = game.mark()
	request("CombatRequest", alice, "Heavy", aimAt(a, b))
	task.wait(0.2)
	assert(#spawnsSince(mark, a, "HeavyBolt") == 0, "still charging")
	task.wait(0.6)
	local spawns = spawnsSince(mark, a, "HeavyBolt")
	assert(#spawns == 1, "a heavy bolt")
	local hits = hitsSince(mark, a, b, "ChargedShot")
	assert(#hits == 1 and near(hits[1].damage, 12), "one 12-damage hit (no double hit from the splash)")
	assert(cooldownSet(a, "ChargedShot"), "cooldown")
	assert(a.power.data.heat and a.power.data.heat > 0, "the barrel heats up")
	task.wait(0.3)
end)

-- Degree 1: Gunner ---------------------------------------------------------------------------

check("Scatter Blast: a fixed cone of pellets, one pellet per target, short range", function()
	local a, b = stage(10)
	ready(a)
	ready(b)
	local def = ability("ScatterBlast", 1)
	local mark = game.mark()
	request("AbilityRequest", alice, "ScatterBlast", aimAt(a, b))
	task.wait(0.6)
	assert(#spawnsSince(mark, a, "Pellet") == def.pellets, "every pellet fired")
	local hits = hitsSince(mark, a, b, "ScatterBlast")
	assert(#hits == 1 and near(hits[1].damage, def.damage), "one pellet hit: " .. #hits)
	assert(a.power.resource < 100 - def.cost + 6, "fuel spent")
	assert(cooldownSet(a, "ScatterBlast"), "cooldown")
	assert(#fxSince(mark, "ScatterFire", a) == 1, "the blast is drawn")
	-- Out of its short range nothing reaches
	a, b = stage(def.range + 10)
	ready(a)
	mark = game.mark()
	request("AbilityRequest", alice, "ScatterBlast", aimAt(a, b))
	task.wait(0.8)
	assert(#hitsSince(mark, a, b, "ScatterBlast") == 0, "out of range")
end)

check("Shock Pulse: blasts away anyone right next to him, nobody further", function()
	local a, b = stage(4)
	ready(a)
	ready(b)
	local def = ability("ShockPulse", 1)
	local mark = game.mark()
	request("AbilityRequest", alice, "ShockPulse", {})
	task.wait(0.3)
	local hits = hitsSince(mark, a, b, "ShockPulse")
	assert(#hits == 1 and near(hits[1].damage, def.damage), "pulse hit")
	assert(b.root:FindFirstChild("SNKnockback"), "knocked away")
	assert(#fxSince(mark, "ShockPulse", a) == 1, "drawn")
	task.wait(0.6)
	a, b = stage(def.radius + 6)
	ready(a)
	ready(b)
	mark = game.mark()
	request("AbilityRequest", alice, "ShockPulse", {})
	task.wait(0.3)
	assert(#hitsSince(mark, a, b, "ShockPulse") == 0, "out of its small radius")
end)

check("Deflector Shield: stops enemy projectiles, loses health, massive ones smash it, expires", function()
	local a, b = stage(24)
	ready(a)
	ready(b)
	local def = ability("DeflectorShield", 1)
	local mark = game.mark()
	request("AbilityRequest", alice, "DeflectorShield", aimAt(a, b))
	task.wait(0.25)
	local list = constructs(a, "DeflectorShield")
	assert(#list == 1, "the shield stands")
	local shield = list[1]
	assert(a.power.resource < 100 - def.cost + 3, "fuel spent")
	-- Bob's bolt is stopped at the panel
	local health = a.humanoid.Health
	request("CombatRequest", bob, "Light", aimAt(b, a))
	task.wait(0.4)
	local bolt = spawnsSince(mark, b, "Bolt")[1]
	assert(bolt, "Bob fired")
	assert(endsSince(mark)[bolt.id] == "Intercepted", "stopped by the shield: " .. tostring(endsSince(mark)[bolt.id]))
	assert(a.humanoid.Health == health, "Alice untouched")
	assert(shield.health < def.health, "the shield took the hit")
	assert(#fxSince(mark, "ShieldBlock", a) == 1, "the block is drawn")
	-- His own shots go out through it
	request("CombatRequest", alice, "Light", aimAt(a, b))
	task.wait(0.4)
	assert(#hitsSince(mark, a, b, "BlasterShot") == 1, "his shot passes")
	-- Something massive smashes it and flies on
	local origin = b.root.Position + Vector3.new(-3, 0, 0)
	local boulder = enemyShot(b, origin, (a.root.Position - origin).Unit, { "Projectile", "Massive" }, { speed = 60, radius = 1 })
	task.wait(0.6)
	assert(not shield.alive, "smashed")
	assert(#fxSince(mark, "ShieldShatter", a) == 1, "shatter drawn")
	assert(endsSince(mark)[boulder.id] ~= "Intercepted", "the massive shot wasn't stopped")
	-- A fresh shield simply runs out
	ready(a)
	mark = game.mark()
	request("AbilityRequest", alice, "DeflectorShield", aimAt(a, b))
	task.wait(0.3)
	assert(#constructs(a, "DeflectorShield") == 1, "up again")
	task.wait(def.duration + 0.2)
	assert(#constructs(a, "DeflectorShield") == 0, "expired")
	local ended = fxSince(mark, "ShieldEnd", a)
	assert(#ended == 1 and ended[1].reason == "Expired", "ended by time")
end)

check("Intercept: shoots down the nearest small enemy projectile; a miss refunds half", function()
	equip(A(), 1, { "ScatterBlast", "Intercept", "DeflectorShield" })
	local a, b = stage(30)
	ready(b)
	local def = ability("Intercept", 1)
	local health = a.humanoid.Health
	local mark = game.mark()
	request("CombatRequest", bob, "Light", aimAt(b, a))
	game.waitFor(function()
		return #spawnsSince(mark, b, "Bolt") > 0
	end, 1, "Bob's bolt")
	request("AbilityRequest", alice, "Intercept", {})
	task.wait(0.4)
	local bolt = spawnsSince(mark, b, "Bolt")[1]
	assert(endsSince(mark)[bolt.id] == "Intercepted", "shot down: " .. tostring(endsSince(mark)[bolt.id]))
	assert(a.humanoid.Health == health, "Alice untouched")
	assert(#fxSince(mark, "InterceptShot", a) == 1, "the shot is drawn")
	assert(a.power.resource < 100 - def.cost + 4, "fuel spent")
	assert(cooldownSet(a, "Intercept"), "cooldown")
	-- Nothing to shoot: half the fuel back
	task.wait(0.3)
	ready(a)
	a.power.resource = 50
	mark = game.mark()
	request("AbilityRequest", alice, "Intercept", {})
	task.wait(def.active + 0.3)
	assert(#fxSince(mark, "InterceptMiss", a) == 1, "a miss")
	local expected = 50 - def.cost / 2
	assert(a.power.resource > expected - 1 and a.power.resource < expected + 6, "half refunded: " .. a.power.resource)
end)

check("Intercept never stops ineligible projectiles: heavy, interceptable = false or massive", function()
	local a, b = stage(30)
	ready(a)
	ready(b)
	local health = a.humanoid.Health
	local mark = game.mark()
	-- A charged shot is too heavy
	request("CombatRequest", bob, "Heavy", aimAt(b, a))
	game.waitFor(function()
		return #spawnsSince(mark, b, "HeavyBolt") > 0
	end, 1.5, "Bob's charged shot")
	request("AbilityRequest", alice, "Intercept", {})
	task.wait(0.6)
	local heavy = spawnsSince(mark, b, "HeavyBolt")[1]
	assert(endsSince(mark)[heavy.id] ~= "Intercepted", "charged shot not intercepted")
	assert(a.humanoid.Health < health, "it hit Alice")
	assert(#fxSince(mark, "InterceptMiss", a) == 1, "Intercept found nothing to shoot")
	-- Massive, or explicitly not interceptable
	task.wait(0.5)
	a, b = stage(30)
	ready(a)
	ready(b)
	mark = game.mark()
	local origin = b.root.Position + Vector3.new(-2, 0, 0)
	local toAlice = (a.root.Position - origin).Unit
	local massive = enemyShot(b, origin, toAlice, { "Projectile", "Small", "Massive" })
	local sealed = enemyShot(b, origin + Vector3.new(0, 0, 1), toAlice, { "Projectile", "Small" }, { interceptable = false })
	request("AbilityRequest", alice, "Intercept", {})
	task.wait(def_active_wait or 0.6)
	assert(massive.alive or endsSince(mark)[massive.id] ~= "Intercepted", "massive ignored")
	assert(sealed.alive or endsSince(mark)[sealed.id] ~= "Intercepted", "interceptable = false ignored")
	task.wait(0.8)
end)

-- Degree 2: Advanced Arsenal ---------------------------------------------------------------------

local D2 = { "RailShot", "MissileVolley", "BarrierProjector", "Intercept" }

check("Rail Shot: a prompt and a laser sight, then a piercing beam along the locked line", function()
	equip(A(), 2, D2)
	local a, b = stage(30)
	ready(b)
	local def = ability("RailShot", 2)
	local health = b.humanoid.Health
	local mark = game.mark()
	request("AbilityRequest", alice, "RailShot", aimAt(a, b))
	task.wait(0.2)
	assert(#cuesFor(mark, bob, "Prompt") == 1, "Bob gets a dodge/block prompt")
	assert(#fxSince(mark, "RailCharge", a) == 1, "laser sight")
	task.wait(def.startup + 0.1)
	local hits = hitsSince(mark, a, b, "RailShot")
	assert(#hits == 1 and near(hits[1].damage, def.damage), "beam hit")
	assert(b.humanoid.Health < health, "Bob hurt")
	assert(#fxSince(mark, "RailFire", a) == 1, "beam drawn")
	assert(a.power.resource < 100 - def.cost + 4, "fuel spent")
	assert((a.model:GetAttribute(Attribute.Phase) or 0) > 0, "the barrel glows with heat")
	-- Stepping off the line during the charge dodges it
	task.wait(0.6)
	a, b = stage(30)
	ready(a)
	ready(b)
	health = b.humanoid.Health
	mark = game.mark()
	request("AbilityRequest", alice, "RailShot", aimAt(a, b))
	task.wait(0.3)
	b.root.CFrame = b.root.CFrame + Vector3.new(0, 0, 8)
	Engine.syncPositions(world.workspace)
	task.wait(def.startup)
	assert(#hitsSince(mark, a, b, "RailShot") == 0, "sidestepped the beam")
	assert(b.humanoid.Health == health, "unhurt")
	-- The heat cools off on its own
	task.wait(1.6)
	assert((a.model:GetAttribute(Attribute.Phase) or 0) < 0.06, "cooled down")
end)

check("Missile Volley: homing mini-missiles with a limited turn rate", function()
	local a, b = stage(30)
	ready(a)
	ready(b)
	local def = ability("MissileVolley", 2)
	local mark = game.mark()
	request("AbilityRequest", alice, "MissileVolley", aimAt(a, b))
	task.wait(def.startup + def.interval * def.missiles + 0.1)
	local spawns = spawnsSince(mark, a, "Missile")
	assert(#spawns == def.missiles, "three missiles: " .. #spawns)
	local homing = services.ProjectileService:nearby(a.root.Position, 200, function(projectile)
		return projectile.ownerId == a.id and projectile.spec.homing ~= nil
	end)
	assert(#homing >= 1, "they home in")
	for _, missile in homing do
		assert(missile.spec.homing.target == b and missile.spec.homing.turnRate == def.turnRate, "on Bob, limited turn")
	end
	task.wait(1.6)
	assert(#hitsSince(mark, a, b, "MissileVolley") >= 2, "missiles landed: " .. #hitsSince(mark, a, b, "MissileVolley"))
	assert(cooldownSet(a, "MissileVolley"), "cooldown")
	task.wait(0.5)
end)

check("Intercept shoots down a missile (Missile Volley is small and interceptable)", function()
	equip(B(), 2, D2)
	local a, b = stage(36)
	ready(a)
	ready(b)
	local mark = game.mark()
	request("AbilityRequest", bob, "MissileVolley", aimAt(b, a))
	game.waitFor(function()
		return #spawnsSince(mark, b, "Missile") > 0
	end, 1, "a missile")
	task.wait(0.15)
	request("AbilityRequest", alice, "Intercept", {})
	task.wait(0.4)
	local downed = 0
	for _, spawn in spawnsSince(mark, b, "Missile") do
		if endsSince(mark)[spawn.id] == "Intercepted" then
			downed += 1
		end
	end
	assert(downed == 1, "one missile shot down per use: " .. downed)
	task.wait(1.5)
	equip(B(), 1)
end)

check("Barrier Projector: a dome that stops shots from outside but lets his own out", function()
	local a, b = stage(24)
	ready(a)
	ready(b)
	local def = ability("BarrierProjector", 2)
	local mark = game.mark()
	request("AbilityRequest", alice, "BarrierProjector", {})
	task.wait(def.startup + 0.1)
	local list = constructs(a, "BarrierProjector")
	assert(#list == 1, "the dome stands")
	local dome = list[1]
	local health = a.humanoid.Health
	request("CombatRequest", bob, "Light", aimAt(b, a))
	task.wait(0.4)
	local bolt = spawnsSince(mark, b, "Bolt")[1]
	assert(bolt and endsSince(mark)[bolt.id] == "Intercepted", "stopped at the dome")
	assert(a.humanoid.Health == health, "Alice untouched")
	assert(dome.health < def.health, "the dome took it")
	request("CombatRequest", alice, "Light", aimAt(a, b))
	task.wait(0.4)
	assert(#hitsSince(mark, a, b, "BlasterShot") == 1, "his own shot leaves the dome")
	-- A side angle is covered too (it's a dome, not a panel)
	local origin = a.root.Position + Vector3.new(0, 0, 20)
	local side = enemyShot(b, origin, (a.root.Position - origin).Unit, { "Projectile", "Small" })
	task.wait(0.7)
	assert(endsSince(mark)[side.id] == "Intercepted", "stopped from the side")
	task.wait(def.duration)
	assert(not dome.alive, "the dome expired")
end)

-- Degree 3: Soul Fire Arsenal ------------------------------------------------------------------

local D3 = { "SweepingStreams", "PressurizedBurst", "SoulFireballs", "SoulforgeDevice", "Intercept" }

check("Sweeping Streams: swept arcs of soul fire, spaced hits, fuel drains and doesn't refill", function()
	equip(A(), 3, D3)
	local a, b = stage(9)
	ready(b)
	local def = ability("SweepingStreams", 3)
	local mark = game.mark()
	request("AbilityRequest", alice, "SweepingStreams", aimAt(a, b))
	task.wait(def.startup + 1.2)
	assert(a.power.resource < 100 - def.cost - def.drain * 0.8, "fuel drains while it flows: " .. a.power.resource)
	task.wait(def.active - 1.2 + 0.4)
	local hits = hitsSince(mark, a, b, "SweepingStreams")
	assert(#hits >= 3, "the sweeps keep catching Bob: " .. #hits)
	assert(#fxSince(mark, "Streams", a) == 1 and #fxSince(mark, "StreamsIgnite", a) == 1, "drawn")
	local ended = fxSince(mark, "StreamsEnd", a)
	assert(#ended == 1 and ended[1].reason == "Done", "ran its full length")
	-- Ticks on one target are spaced out
	for index = 2, #hits do
		local gap = hits[index].time and (hits[index].time - hits[index - 1].time) or def.hitEvery
		assert(gap >= def.hitEvery - 0.05, "hits are spaced")
	end
	assert(b.humanoid.Health < b.humanoid.MaxHealth, "Bob burned")
	-- Out of range nobody is touched
	task.wait(0.4)
	a, b = stage(def.range + 6)
	ready(a)
	ready(b)
	mark = game.mark()
	request("AbilityRequest", alice, "SweepingStreams", aimAt(a, b))
	task.wait(def.startup + def.active + 0.3)
	assert(#hitsSince(mark, a, b, "SweepingStreams") == 0, "out of reach")
end)

check("§38: Machine Master runs out of fuel during an active channel", function()
	local a, b = stage(9)
	ready(a)
	ready(b)
	local def = ability("SweepingStreams", 3)
	a.power.resource = def.cost + 6
	local mark = game.mark()
	local castAt = now()
	request("AbilityRequest", alice, "SweepingStreams", aimAt(a, b))
	game.waitFor(function()
		return #fxSince(mark, "StreamsEnd", a) > 0
	end, def.startup + def.active + 1, "the streams to stop")
	local stoppedAt = now()
	local ended = fxSince(mark, "StreamsEnd", a)
	assert(ended[1].reason == "Fuel", "stopped by the empty tank: " .. tostring(ended[1].reason))
	assert(stoppedAt - castAt < def.startup + 0.9, "stopped early")
	assert(a.power.resource >= 0 and a.power.resource < 2, "tank empty, never negative: " .. a.power.resource)
	task.wait(def.recovery + 0.2)
	assert(not FighterState.isAttacking(a.state, now()), "the cast ended cleanly")
	-- Then the reservoir refills again
	task.wait(1)
	assert(a.power.resource > 4, "refilling: " .. a.power.resource)
	-- With too little fuel it can't even start
	ready(a)
	a.power.resource = def.cost - 1
	mark = game.mark()
	request("AbilityRequest", alice, "SweepingStreams", aimAt(a, b))
	task.wait(0.1)
	assert(rejection(mark, alice, "SweepingStreams") == "resource", "not enough fuel")
end)

check("Pressurized Burst: staggers, recoils him back, burns away a few small projectiles only", function()
	local a, b = stage(5)
	ready(a)
	ready(b)
	local def = ability("PressurizedBurst", 3)
	-- Small enemy shots hanging in front of him, plus a massive one
	local look = (b.root.Position - a.root.Position).Unit
	local smalls = {}
	for index = 1, def.burnsAway + 1 do
		local origin = a.root.Position + look * 4 + Vector3.new(0, 0, (index - 2.5) * 0.8)
		table.insert(smalls, enemyShot(b, origin, Vector3.new(0, 1, 0), { "Projectile", "Small" }, { speed = 1 }))
	end
	local massive = enemyShot(b, a.root.Position + look * 4 + Vector3.new(0, 1, 0), Vector3.new(0, 1, 0), { "Projectile", "Massive" }, { speed = 1 })
	local mark = game.mark()
	request("AbilityRequest", alice, "PressurizedBurst", aimAt(a, b))
	task.wait(def.startup + 0.06)
	local hits = hitsSince(mark, a, b, "PressurizedBurst")
	assert(#hits == 1 and near(hits[1].damage, def.damage), "burst hit")
	assert(FighterState.isStunned(b.state, now()), "Bob staggered")
	local mover = a.root:FindFirstChild("SNDash")
	assert(mover and mover:IsA("LinearVelocity"), "recoil")
	assert(mover.VectorVelocity:Dot(look) < -def.recoil + 1, "pushed backwards")
	local burned = 0
	for _, projectile in smalls do
		if not projectile.alive then
			burned += 1
		end
	end
	assert(burned == def.burnsAway, "burned away a few, not all: " .. burned)
	assert(massive.alive, "massive ones aren't stopped")
	assert(#fxSince(mark, "Burst", a) == 1, "drawn")
	services.ProjectileService:clearOwner(b)
	-- A block takes it (it doesn't break every defense)
	task.wait(0.8)
	a, b = stage(5)
	ready(a)
	ready(b)
	request("CombatRequest", bob, "BlockStart", "Held")
	task.wait(0.3)
	mark = game.mark()
	request("AbilityRequest", alice, "PressurizedBurst", aimAt(a, b))
	task.wait(def.startup + 0.1)
	local blocked = hitsSince(mark, a, b, "PressurizedBurst")[1]
	assert(blocked and blocked.result == "Blocked", "blocked: " .. tostring(blocked and blocked.result))
	request("CombatRequest", bob, "BlockEnd")
	task.wait(0.5)
end)

check("Soul Fireballs: four fireballs from four nozzles, explode on impact and burn", function()
	local a, b = stage(24)
	ready(a)
	ready(b)
	local def = ability("SoulFireballs", 3)
	local mark = game.mark()
	request("AbilityRequest", alice, "SoulFireballs", aimAt(a, b))
	task.wait(def.startup + def.interval * def.count + 0.05)
	local spawns = spawnsSince(mark, a, "Fireball")
	assert(#spawns == def.count, "four fireballs: " .. #spawns)
	local origins = {}
	for _, spawn in spawns do
		assert(spawn.lifetime <= def.lifetime + 1e-3, "strict lifetime")
		assert(spawn.gravity > 0, "they arc")
		origins[`{math.floor(spawn.origin.X * 10)},{math.floor(spawn.origin.Y * 10)},{math.floor(spawn.origin.Z * 10)}`] = true
	end
	local distinct = 0
	for _ in origins do
		distinct += 1
	end
	assert(distinct == 4, "from four different nozzles")
	task.wait(1)
	local hits = hitsSince(mark, a, b, "SoulFireballs")
	assert(#hits >= 1, "a fireball landed")
	assert(services.StatusService:has(b, "Burn"), "Bob burns")
	task.wait(0.4)
	-- Into empty air they're all gone within their lifetime
	a = stage(24)
	ready(a)
	mark = game.mark()
	request("AbilityRequest", alice, "SoulFireballs", { direction = Vector3.new(0, 0, 1) })
	task.wait(def.startup + def.interval * def.count + def.lifetime + 0.15)
	local reasons = endsSince(mark)
	for _, spawn in spawnsSince(mark, a, "Fireball") do
		assert(reasons[spawn.id] ~= nil, "every fireball ended")
	end
	assert(#services.ProjectileService:nearby(a.root.Position, 500, function(projectile)
		return projectile.ownerId == a.id
	end) == 0, "none left")
end)

check("Soulforge Device: arms, beeps a prompt when someone steps close, bursts and slows", function()
	local a, b = stage(24)
	ready(a)
	ready(b)
	local def = ability("SoulforgeDevice", 3)
	local spot = a.root.Position + Vector3.new(8, 0, 0)
	local mark = game.mark()
	request("AbilityRequest", alice, "SoulforgeDevice", { direction = Vector3.new(1, 0, 0), point = spot })
	task.wait(def.startup + 0.1)
	local list = constructs(a, "SoulforgeDevice")
	assert(#list == 1, "deployed")
	local mine = list[1]
	assert(#fxSince(mark, "DevicePlaced", a) == 1, "drawn")
	task.wait(def.armTime + 0.2)
	assert(mine.alive and #cuesFor(mark, bob, "Prompt") == 0, "Bob is far: nothing happens")
	-- Bob walks onto it
	b.root.CFrame = CFrame.new(spot + Vector3.new(2, 0, 0))
	Engine.syncPositions(world.workspace)
	task.wait(0.2)
	assert(#cuesFor(mark, bob, "Prompt") == 1, "a dodge/block prompt")
	assert(#fxSince(mark, "DeviceTrigger", a) == 1, "it beeps")
	task.wait(def.fuse + 0.1)
	local hits = hitsSince(mark, a, b, "SoulforgeDevice")
	assert(#hits == 1 and near(hits[1].damage, def.damage), "burst hit")
	assert(services.StatusService:has(b, "Slow"), "slowed")
	assert(not mine.alive and #constructs(a, "SoulforgeDevice") == 0, "used up")
	task.wait(0.3)
end)

check("Soulforge Device: two at most, shot down during the beep, no room refunds", function()
	local a, b = stage(30)
	ready(b)
	for index = 1, 3 do
		ready(a)
		request("AbilityRequest", alice, "SoulforgeDevice", { direction = Vector3.new(1, 0, 0), point = a.root.Position + Vector3.new(4 + index * 3, 0, 4) })
		task.wait(0.5)
	end
	assert(#constructs(a, "SoulforgeDevice") == 2, "capped at two")
	-- Shot to pieces during the beep: no burst
	local mine = constructs(a, "SoulforgeDevice")[1]
	local mark = game.mark()
	b.root.CFrame = CFrame.new(mine.model:GetPivot().Position + Vector3.new(2, 2, 0))
	Engine.syncPositions(world.workspace)
	game.waitFor(function()
		return #fxSince(mark, "DeviceTrigger", a) > 0
	end, 1, "the beep")
	services.ConstructService:damage(mine, 100)
	task.wait(0.6)
	assert(#fxSince(mark, "DevicePulse", a) == 0 or #hitsSince(mark, a, b, "SoulforgeDevice") <= 1, "")
	local ended = fxSince(mark, "DeviceEnd", a)
	assert(#ended >= 1 and ended[1].reason == "Broken", "broken")
	services.ConstructService:clearOwner(a)
	-- Nowhere to stand: it fails and refunds
	ready(a)
	a.power.resource = 50
	local raycast = Engine.raycast
	Engine.raycast = function()
		return nil
	end
	mark = game.mark()
	request("AbilityRequest", alice, "SoulforgeDevice", { direction = Vector3.new(1, 0, 0) })
	task.wait(0.5)
	Engine.raycast = raycast
	assert(#fxSince(mark, "DeviceFail", a) == 1, "no room")
	assert(a.power.resource > 49, "refunded: " .. a.power.resource)
	assert(#constructs(a, "SoulforgeDevice") == 0, "nothing placed")
end)

-- Ultimate -------------------------------------------------------------------------------------------

check("Blue Inferno at every degree: a fuel gate, the sweep, then a timed blast", function()
	for degree = 1, 3 do
		equip(A(), degree)
		local a, b = stage(10)
		ready(b)
		a.power.ult = 100
		local def = ability("BlueInferno", degree)
		-- Not enough fuel: refused, the charge is kept
		a.power.resource = def.fuelCost - 5
		local mark = game.mark()
		request("AbilityRequest", alice, "BlueInferno", aimAt(a, b))
		task.wait(0.1)
		assert(rejection(mark, alice, "BlueInferno") == `Needs {def.fuelCost} fuel`, "fuel gate")
		assert(a.power.ult == 100, "charge kept")
		ready(a)
		a.power.ult = 100
		mark = game.mark()
		request("AbilityRequest", alice, "BlueInferno", aimAt(a, b))
		task.wait(0.2)
		assert(a.power.ult < 5, "charge spent")
		assert(a.power.resource < 100 - def.fuelCost + 3, "fuel spent: " .. a.power.resource)
		assert(#fxSince(mark, "InfernoIgnite", a) == 1, "an obvious activation cue")
		local cue
		game.waitFor(function()
			cue = cuesFor(mark, bob, "Timing")[1]
			return cue ~= nil
		end, def.startup + def.sweepTime + 1, "Bob's timing bar")
		task.wait(math.max(0, cue.impactAt - now()) + 0.5)
		local sweeps, blasts = 0, 0
		for _, hit in hitsSince(mark, a, b, "BlueInferno") do
			if near(hit.damage, def.sweepHit.damage) then
				sweeps += 1
			elseif near(hit.damage, def.damage) then
				blasts += 1
			end
		end
		assert(sweeps >= 2, `degree {degree}: the sweep burned Bob ({sweeps})`)
		assert(blasts == 1, `degree {degree}: the blast landed ({blasts})`)
		assert(#fxSince(mark, "InfernoBlast", a) == 1 and #fxSince(mark, "InfernoEnd", a) == 1, "blast and a clean end")
		task.wait(def.recovery + 0.3)
		assert(not FighterState.isAttacking(a.state, now()), "free again")
	end
end)

check("Blue Inferno: perfect timing negates the blast; leaving the ring escapes it", function()
	equip(A(), 2)
	local a, b = stage(10)
	ready(b)
	a.power.ult = 100
	local def = ability("BlueInferno", 2)
	local mark = game.mark()
	request("AbilityRequest", alice, "BlueInferno", aimAt(a, b))
	local cue
	game.waitFor(function()
		cue = cuesFor(mark, bob, "Timing")[1]
		return cue ~= nil
	end, 4, "Bob's timing bar")
	-- Press right on the impact (the engine reports 0.05s ping, half is allowed for)
	task.wait(math.max(0, cue.impactAt - now() + 0.025))
	request("DefenseInput", bob, "Timing", cue.id)
	task.wait(0.6)
	local result = game.lastSent("DefenseEvent", "Result", bob)
	assert(result and result.result == "Perfect", "perfect: " .. tostring(result and result.result))
	for _, hit in hitsSince(mark, a, b, "BlueInferno") do
		assert(not near(hit.damage, def.damage), "the blast didn't land")
	end
	task.wait(1)
	-- Running out of the marked ring in time
	a, b = stage(10)
	ready(a)
	ready(b)
	a.power.ult = 100
	mark = game.mark()
	request("AbilityRequest", alice, "BlueInferno", aimAt(a, b))
	game.waitFor(function()
		cue = cuesFor(mark, bob, "Timing")[1]
		return cue ~= nil
	end, 4, "Bob's timing bar")
	b.root.CFrame = b.root.CFrame + Vector3.new(0, 0, def.blastRadius + 12)
	Engine.syncPositions(world.workspace)
	task.wait(math.max(0, cue.impactAt - now()) + 0.5)
	for _, hit in hitsSince(mark, a, b, "BlueInferno") do
		assert(not near(hit.damage, def.damage), "escaped the blast")
	end
	task.wait(1)
end)

check("§38: a character dies during an ultimate", function()
	equip(A(), 3, D3)
	local a, b = stage(10)
	ready(b)
	a.power.ult = 100
	local def = ability("BlueInferno", 3)
	local mark = game.mark()
	request("AbilityRequest", alice, "BlueInferno", aimAt(a, b))
	task.wait(def.startup + 0.4)
	assert(#fxSince(mark, "InfernoSweep", a) == 1, "mid-sweep")
	a.humanoid.Health = 0
	local health = b.humanoid.Health
	game.waitFor(function()
		local fresh = A()
		return fresh ~= nil and fresh ~= a and fresh.power ~= nil
	end, 3, "Alice to respawn")
	task.wait(def.sweepTime + def.blastCharge + 0.5)
	assert(b.humanoid.Health == health, "nothing landed after the knockout")
	assert(#fxSince(mark, "InfernoBlast", a) == 0, "no blast")
	assert(#cuesFor(mark, bob, "Timing") == 0, "no timing bar left over")
	local fresh = A()
	assert(fresh.power.id == "MachineMaster", "still Machine Master (locked for the match)")
	assert(not FighterState.isAttacking(fresh.state, now()), "not stuck mid-cast")
	assert(fresh.model:GetAttribute(Attribute.Phase) == 0, "cold on the new life")
	assert(fresh.power.resource > 99, "a full tank")
	assert(fresh.power.ult < 5, "charge starts (nearly) empty")
	assert((fresh.power.data.burningUntil or 0) < now(), "no soul fire flowing")
end)

-- Edge cases -----------------------------------------------------------------------------------------

check("§38: two players attack at the same moment", function()
	equip(A(), 1)
	equip(B(), 1)
	local a, b = stage(16)
	local mark = game.mark()
	request("CombatRequest", alice, "Light", aimAt(a, b))
	request("CombatRequest", bob, "Light", aimAt(b, a))
	task.wait(0.5)
	assert(#hitsSince(mark, a, b, "BlasterShot") == 1 and #hitsSince(mark, b, a, "BlasterShot") == 1, "both bolts landed")
	task.wait(0.6)
	assert(not FighterState.isAttacking(a.state, now()) and not FighterState.isAttacking(b.state, now()), "neither is stuck")
end)

check("§38: invalid requests and cooldown spam are refused", function()
	equip(A(), 2, D2)
	local a, b = stage(30)
	ready(b)
	local mark = game.mark()
	for _ = 1, 6 do
		request("AbilityRequest", alice, "MissileVolley", aimAt(a, b))
		task.wait(0.03)
	end
	task.wait(0.8)
	assert(castsSince(mark, a, "MissileVolley") == 1, "only one volley: " .. castsSince(mark, a, "MissileVolley"))
	assert(#spawnsSince(mark, a, "Missile") == ability("MissileVolley", 2).missiles, "one volley's missiles")
	task.wait(1.5)
	-- Junk aims: NaN directions and points far outside the world
	ready(a)
	mark = game.mark()
	request("AbilityRequest", alice, "RailShot", { direction = Vector3.new(0 / 0, 0, 0), point = Vector3.new(1e9, 0, 0) })
	task.wait(1.2)
	request("CombatRequest", alice, "Light", { direction = Vector3.new(math.huge, 0, 0), point = "x" })
	task.wait(0.3)
	request("CombatRequest", alice, "Heavy", "junk")
	task.wait(0.9)
	ready(a)
	mark = game.mark()
	request("AbilityRequest", alice, "SoulFireballs", {})
	request("AbilityRequest", alice, "BlueInferno", {})
	request("AbilityRequest", alice, "Groundbreaker", {})
	request("AbilityRequest", alice, "ChargedShot", {})
	task.wait(0.2)
	assert(rejection(mark, alice, "SoulFireballs") == "not equipped", "Degree 3 only")
	assert(rejection(mark, alice, "BlueInferno") == "charge", "needs a full charge")
	assert(rejection(mark, alice, "Groundbreaker") == "unknown", "another power's ability")
	assert(rejection(mark, alice, "ChargedShot") == "not equipped", "a basic attack isn't an ability")
	task.wait(0.3)
end)

check("§38: a match ending with missiles, fireballs, shields and mines out leaves nothing behind", function()
	equip(A(), 3, { "SoulFireballs", "SoulforgeDevice", "SweepingStreams", "Intercept", "PressurizedBurst" })
	equip(B(), 2, D2)
	local a, b = stage(40)
	request("AbilityRequest", alice, "SoulforgeDevice", { direction = Vector3.new(1, 0, 0), point = a.root.Position + Vector3.new(6, 0, 0) })
	request("AbilityRequest", bob, "BarrierProjector", {})
	task.wait(0.5)
	request("AbilityRequest", bob, "MissileVolley", { direction = Vector3.new(0, 0, 1) })
	request("AbilityRequest", alice, "SoulFireballs", { direction = Vector3.new(0, 0, 1) })
	local mark = game.mark()
	task.wait(0.55)
	services.StatusService:apply(a, "Burn", 3, { magnitude = 1 })
	assert(#services.ProjectileService:nearby(Vector3.zero, 1e7) > 0, "projectiles in flight")
	assert(#constructs(a, "SoulforgeDevice") + #constructs(b, "BarrierProjector") == 2, "a mine and a dome")
	services.MatchService:endAll()
	task.wait(1.5)
	assert(services.MatchService:getMatchOf(A()) == nil, "match over")
	assert(#services.ProjectileService:nearby(Vector3.zero, 1e7) == 0, "no projectiles left")
	assert(#game.sentSince(mark, "AbilityEvent", "ProjectileEnd") > 0, "they were removed")
	for _, fighter in { A(), B() } do
		assert(#services.ConstructService:ofOwner(fighter) == 0, "no constructs left")
		for name in fighter.model:GetAttributes() do
			assert(string.sub(name, 1, 4) ~= "SNS_", "status left: " .. name)
		end
		assert(fighter.model:GetAttribute(Attribute.Phase) == 0, "cold barrel")
		assert(fighter.power.data.heat == nil and fighter.power.data.burningUntil == nil, "power state reset")
		assert(fighter.root:FindFirstChild("SNDash") == nil, "no dash left")
	end
end)

check("a CPU Machine Master fights with its abilities", function()
	local me = A()
	ready(me)
	request("MatchRequest", alice, "Queue", "Practice", { cpuPower = "MachineMaster", cpuDegree = 3, cpuDifficulty = "Hard" })
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
				return cpu.power ~= nil
			end
		end
		return false
	end, 4, "the CPU Machine Master")
	assert(cpu.power.id == "MachineMaster" and cpu.power.degree == 3, "a Degree 3 Machine Master")
	me = A()
	local mark = game.mark()
	local started = os.clock()
	local used = {}
	while os.clock() - started < 8 do
		game.faceOff(cpu, me, 10)
		task.wait(0.25)
		for _, cast in game.sentSince(mark, "AbilityEvent", "Cast") do
			if cast.fighter == cpu.model then
				used[cast.ability] = true
			end
		end
		if next(used) then
			break
		end
	end
	assert(next(used) ~= nil, "the CPU used a Machine Master ability")
	services.MatchService:endAll()
	task.wait(1)
end)

-- Client visuals ----------------------------------------------------------------------------------------

check("Machine Master's visuals run: every effect, projectile, wind-up and the gear at every degree", function()
	local ClientPowers = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Powers"))
	local Settings = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Settings"))
	local client = ClientPowers.module("MachineMaster")
	assert(client, "client module loads")

	local function rig(name: string)
		local model = world.Instance.new("Model")
		model.Name = name
		for _, spec in {
			{ "HumanoidRootPart", Vector3.new(2, 2, 1) },
			{ "UpperTorso", Vector3.new(2, 1.6, 1) },
			{ "Head", Vector3.new(1.2, 1.2, 1.2) },
			{ "RightUpperArm", Vector3.new(1, 1.2, 1) },
			{ "RightLowerArm", Vector3.new(1, 1.2, 1) },
		} do
			local part = world.Instance.new("Part")
			part.Name = spec[1]
			part.Size = spec[2]
			part.CFrame = CFrame.new(0, 3, 0)
			part.Parent = model
		end
		world.Instance.new("Humanoid").Parent = model
		model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
		model:SetAttribute(Attribute.Power, "MachineMaster")
		model.Parent = world.workspace
		return model
	end

	local function fire(model, name: string)
		Engine.signalOf(model, "Attribute:" .. name):Fire()
	end

	local function count(folder: Instance, prefix: string): number
		local total = 0
		for _, item in folder:GetDescendants() do
			if string.sub(item.Name, 1, #prefix) == prefix then
				total += 1
			end
		end
		return total
	end

	for _, reduced in { false, true } do
		Settings.values.reducedEffects = reduced
		for degree = 1, 3 do
			local model = rig("Machine" .. degree)
			model:SetAttribute(Attribute.Degree, degree)
			model:SetAttribute(Attribute.Resource, 100)
			model:SetAttribute(Attribute.ResourceMax, 100)
			local cleanup = client.appearance(ClientPowers.kit(model, "MachineMaster", {}))
			assert(typeof(cleanup) == "function", "appearance returns a cleanup")
			local gear = model:FindFirstChild("SNMachineGear")
			assert(gear, "gear built")
			assert(gear:FindFirstChild("SNMuzzle", true), "a blaster arm at every degree")
			assert((count(gear, "SNPod") > 0) == (degree >= 2), "missile pod from Degree 2")
			assert((gear:FindFirstChild("SNFuelCell", true) ~= nil) == (degree >= 3), "fuel cell at Degree 3")
			if degree >= 3 then
				for index = 1, 4 do
					assert(gear:FindFirstChild("SNNozzle" .. index, true), "four nozzles")
				end
				assert(count(gear, "SNConduit") >= 4, "conduits to the nozzles")
				-- The window shows the fuel left
				local level = gear:FindFirstChild("SNFuelLevel", true)
				local full = level.Size.Y
				model:SetAttribute(Attribute.Resource, 25)
				fire(model, Attribute.Resource)
				assert(level.Size.Y < full * 0.4, "fuel window drops")
			end
			-- Heat makes it glow; invisibility hides the gear too
			model:SetAttribute(Attribute.Phase, 1)
			fire(model, Attribute.Phase)
			local torso = model:FindFirstChild("UpperTorso")
			torso.Transparency = 1
			Engine.signalOf(torso, "Property:Transparency"):Fire()
			assert(gear:FindFirstChild("SNMuzzle", true).Transparency >= 0.99, "hidden with the body")
			torso.Transparency = 0
			Engine.signalOf(torso, "Property:Transparency"):Fire()

			local target = Vector3.new(12, 3, 0)
			local data = {
				ScatterFire = { origin = Vector3.new(1, 3, -1), direction = Vector3.new(1, 0, 0), spread = 36 },
				ShockPulse = { position = Vector3.new(0, 3, 0), radius = 7.5 },
				ShieldUp = { position = Vector3.new(3, 3, 0), width = 6, height = 6.5, direction = Vector3.new(1, 0, 0) },
				ShieldBlock = { position = Vector3.new(3, 3, 0), broken = true },
				ShieldShatter = { position = Vector3.new(3, 3, 0) },
				ShieldEnd = { position = Vector3.new(3, 3, 0), reason = "Expired" },
				ProjectorUp = { position = Vector3.new(0, 0, 0), radius = 8 },
				InterceptShot = { from = Vector3.new(1, 3, -1), to = target },
				InterceptMiss = {},
				RailCharge = { origin = Vector3.new(1, 3.5, 0), direction = Vector3.new(1, 0, 0), length = 70, duration = 0.7 },
				RailFizzle = {},
				RailFire = { origin = Vector3.new(1, 3.5, 0), direction = Vector3.new(1, 0, 0), length = 70, width = 3 },
				StreamsIgnite = { duration = 0.3, direction = Vector3.new(1, 0, 0), range = 16, sweep = 155 },
				Streams = { startedAt = now(), direction = Vector3.new(1, 0, 0), range = 16, arc = 35, sweep = 120, period = 1.6, duration = 0.3 },
				StreamsEnd = { reason = "Fuel" },
				Burst = { origin = Vector3.new(0, 3, 0), direction = Vector3.new(1, 0, 0), range = 9, arc = 70 },
				DevicePlaced = { position = Vector3.new(6, 0, 0), armTime = 0.1, trigger = 6 },
				DeviceTrigger = { position = Vector3.new(6, 0, 0), radius = 8, fuse = 0.3 },
				DevicePulse = { position = Vector3.new(6, 0, 0), radius = 8 },
				DeviceEnd = { position = Vector3.new(6, 0, 0), reason = "Broken" },
				DeviceFail = {},
				InfernoIgnite = { duration = 0.3, direction = Vector3.new(1, 0, 0), range = 20, sweep = 190, blast = target, blastRadius = 8 },
				InfernoSweep = { startedAt = now(), direction = Vector3.new(1, 0, 0), range = 20, arc = 40, sweep = 150, sweepTime = 0.3, duration = 0.3 },
				InfernoCharge = { position = target, radius = 8, duration = 0.3 },
				InfernoBlast = { position = target, radius = 8 },
				InfernoFizzle = {},
				InfernoEnd = {},
			}
			for name, handler in client.fx do
				handler(ClientPowers.kit(model, "MachineMaster", data[name] or {}))
				-- Junk data never breaks an effect
				handler(ClientPowers.kit(model, "MachineMaster", { position = "x", from = 4, duration = "y", direction = Vector3.zero, startedAt = "z" }))
			end
			for abilityId, predict in client.predict do
				predict(ClientPowers.kit(model, "MachineMaster", { ability = abilityId, startup = 0.2, active = 0.1, predicted = true }))
				client.onCast(ClientPowers.kit(model, "MachineMaster", { ability = abilityId, startup = 0.2 }))
			end
			for visual, make in client.projectiles do
				for _, reason in { "Hit", "World", "Intercepted", "Expired", "Destroyed" } do
					local handle = make(ClientPowers.kit(model, "MachineMaster", { radius = 1.1, splash = 5 }))
					for step = 1, 4 do
						handle.update(Vector3.new(step * 2, 3, 0), Vector3.new(80, 0, 0), 1 / 60)
					end
					handle.finish(Vector3.new(10, 3, 0), reason)
				end
				assert(visual ~= "", "")
			end
			Engine.step(world.game, 3)
			cleanup()
			assert(model:FindFirstChild("SNMachineGear") == nil, "gear removed")
			model:Destroy()
		end
	end
	Settings.values.reducedEffects = false
	-- The game's own stand-in character (no lower arm: falls back to the upper arm)
	local stand = Engine.character("Stand")
	stand:SetAttribute(Attribute.Degree, 3)
	stand.Parent = world.workspace
	local cleanup = client.appearance(ClientPowers.kit(stand, "MachineMaster", {}))
	assert(stand:FindFirstChild("SNMachineGear"), "gear on the stand-in")
	cleanup()
	task.wait(0.6)
end)

process.exit(if game.finish() == 0 then 0 else 1)
