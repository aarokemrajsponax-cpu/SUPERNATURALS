-- Runs Corruption (PROGRAMME ECLIPSE) end to end with simulated players:
--   rojo build default.project.json -o build/corruption.rbxl
--   lune run tests/power_Corruption_test.luau build/corruption.rbxl
-- Two players fight Corruption against Corruption in a duel and use every
-- ability at every degree it exists at: the Corruption meter (fills from hits
-- and casts, never by itself, drains out of combat, exposes the fighter when
-- high) and the overwrite it drives (Phase), Corruption Marks stacking per
-- degree and Unravel detonating them, projectiles unmade by static and zones
-- (never massive ones), Rift Blink (and a blocked landing that refunds),
-- Unstable Ground arming then slowing, Distortion Pulse and Cataclysm prompts,
-- the Distortion Zone, Phantasm's walking reflections, and Total System
-- Corruption at all three degrees (the meter gate, the timing bar, the final
-- form's empowered kit and the collapse after). Also the §38 cases: the form
-- expiring during a hit reaction, a knockout mid-ultimate, simultaneous
-- attacks, junk requests and cooldown spam, a power change refused mid-fight,
-- the premium trial rules, a match ending with everything out, a CPU
-- Corruption, and every client effect at every degree.

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
local Monetization = world.require(world.find("ReplicatedStorage.Shared.Config.Monetization"))
local ServerCorruption = world.require(world.find("ServerScriptService.Server.Powers.Corruption"))
local Attribute = Protocol.Attribute
local DEF = Powers.get("Corruption")
local FORM = DEF.attributes.form
local LOCK = DEF.attributes.lock
local ULT = "TotalSystemCorruption"

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
	return Powers.abilityFor("Corruption", id, degree)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function aimAt(from, to)
	return { direction = (to.root.Position - from.root.Position).Unit, point = to.root.Position }
end

local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1e-3)
end

-- A clean slate: the power reset (zones, forms, marks, meter), full health,
-- no statuses, no cooldowns, an idle fighter
local function ready(fighter, meter: number?)
	services.PowerService:resetFighter(fighter)
	local runtime = fighter.power
	runtime.resource = meter or 0
	runtime.data.activeAt = now()
	table.clear(runtime.cooldowns)
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
	services.PowerService:equip(fighter, "Corruption", degree, loadout or Powers.defaultLoadout("Corruption", degree))
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

local function cuesFor(mark: number, player, kind: string)
	local list = {}
	for _, cue in game.sentSince(mark, "DefenseEvent", "Cue", player) do
		if cue.kind == kind then
			table.insert(list, cue)
		end
	end
	return list
end

local function cooldownLeft(fighter, abilityId: string): number
	return (fighter.model:GetAttribute(Attribute.CooldownPrefix .. abilityId) or 0) - now()
end

local function has(fighter, statusId: string): boolean
	return services.StatusService:has(fighter, statusId)
end

local function phase(fighter): number
	return fighter.model:GetAttribute(Attribute.Phase) or -1
end

-- Uses an ability as Alice and waits for it to play out
local function cast(abilityId: string, aim: any?, wait: number?)
	request("AbilityRequest", alice, abilityId, aim or aimAt(A(), B()))
	if wait then
		task.wait(wait)
	end
end

-- A projectile owned by `owner` (to test what Corruption can unmake)
local function enemyShot(owner, origin: Vector3, direction: Vector3, tags: { string }, extra: { [string]: any }?)
	local spec = {
		power = "Corruption",
		ability = "TestShot",
		visual = "VoidShard",
		origin = origin,
		direction = direction,
		speed = 6,
		radius = 0.5,
		lifetime = 4,
		range = 120,
		hit = { Damage = 5, Hitstun = 0.2, Knockback = 5, GuardDamage = 5 },
		tags = tags,
	}
	for key, value in extra or {} do
		spec[key] = value
	end
	return services.ProjectileService:spawn(owner, spec)
end

local D2_KIT = { "RiftBlink", "UnstableGround", "DistortionPulse", "Unravel" }
local D3_KIT = { "DistortionZone", "Phantasm", "Cataclysm", "Unravel", "VoidStrike" }

-- Definition ------------------------------------------------------------------------------

check("Corruption's definition: card text, the meter, premium pass, AI hints, degrees and loadouts", function()
	assert(DEF, "Corruption is registered")
	assert(Powers.degreeCount("Corruption") == 3, "three degrees")
	assert(utf8.len(DEF.name) <= 20 and utf8.len(DEF.description) <= 160, "power text fits a card")
	assert(string.find(DEF.description, "Fragile", 1, true), "the card names its weakness")
	-- Premium: the definition and Config/Monetization agree
	local pass = Monetization.Passes[DEF.premium.pass]
	assert(pass and pass.power == "Corruption", "the CorruptionPower pass unlocks Corruption")
	assert(DEF.premium.robux == pass.robux and pass.robux == 6666, "6,666 Robux both places")
	assert(DEF.premium.gems and DEF.premium.gems > 0, "a Gems path")
	assert(Powers.isPremium("Corruption"), "premium")
	local meter = DEF.resource
	assert(meter.id == "Corruption" and meter.max == 100 and meter.start == 0 and meter.regen == 0, "Corruption 0-100, starts empty, never refills by itself")
	assert(meter.decay > 0 and meter.hitGain > 0 and meter.exposedAt < meter.max, "drains out of combat, fills from hits, exposes when high")
	assert(DEF.ai.preferredRange >= 10 and DEF.ai.preferredRange <= 18, "a mid-range fighter")
	for _, degree in DEF.degrees do
		assert(utf8.len(degree.name) <= 20 and utf8.len(degree.description) <= 160, degree.name .. " text fits")
		assert(degree.ultimate == ULT, "ultimate on every degree")
		assert(not string.find(degree.description, "\u{2014}", 1, true), "no em dashes")
	end
	local builders = 0
	for abilityId, def in DEF.abilities do
		assert(utf8.len(def.name) <= 20, abilityId .. " name fits")
		assert(utf8.len(def.description) <= 160, abilityId .. " description fits")
		assert(not string.find(def.description, "\u{2014}", 1, true), abilityId .. ": no em dashes")
		assert(def.ai and def.ai.range and def.ai.use, abilityId .. " has an AI hint")
		assert(table.find(DEF.abilityOrder, abilityId), abilityId .. " is in abilityOrder")
		if def.kind ~= "Ultimate" then
			-- Every ability either builds the meter or spends it
			assert((def.cost or 0) > 0 or (def.charge or 0) > 0, abilityId .. " builds or spends Corruption")
			if (def.charge or 0) > 0 then
				builders += 1
			end
		end
	end
	assert(builders == 2, "two builders (the strike and the shard); everything else spends")
	-- Degrees expand the kit: everything lower is still there
	assert(#Powers.available("Corruption", 1) == 3, "3 at Awakening: " .. #Powers.available("Corruption", 1))
	assert(#Powers.available("Corruption", 2) == 7, "7 at Corruption")
	assert(#Powers.available("Corruption", 3) == 10, "10 at Absolute Corruption")
	for degree = 1, 3 do
		local ok, reason = Powers.validateLoadout("Corruption", degree, Powers.defaultLoadout("Corruption", degree), {})
		assert(ok, `degree {degree} default loadout: {reason}`)
		assert(Powers.ultimateOf("Corruption", degree) == ULT, "the ultimate")
	end
	assert(not Powers.validateLoadout("Corruption", 2, { "Unravel" }, {}), "Unravel costs Money at Degree 2")
	assert(Powers.validateLoadout("Corruption", 3, { "Unravel", "DistortionPulse" }, {}), "free from Degree 3")
	assert(not Powers.validateLoadout("Corruption", 3, { "Phantasm" }, {}), "Phantasm is bought")
	-- Scaling
	local form = { ability(ULT, 1).formDuration, ability(ULT, 2).formDuration, ability(ULT, 3).formDuration }
	assert(form[1] == 5 and form[2] == 7 and form[3] == 10, "the final form lasts 5/7/10 s")
	assert(ability(ULT, 3).damage > ability(ULT, 2).damage and ability(ULT, 2).damage > ability(ULT, 1).damage, "ultimate scales")
	assert(ability("VoidStrike", 3).damage > ability("VoidStrike", 1).damage, "Void Strike scales")
	assert(DEF.mark.maxStacks[1] == 1 and DEF.mark.maxStacks[3] == 3, "marks stack deeper each degree")
	-- The strongest moves can't be kept up: one Cataclysm costs nearly half the meter
	assert(ability("Cataclysm", 3).cost >= 40 and ability("DistortionZone", 3).cost >= 40, "the big moves cost a lot")
	-- Weak point: fragile and a soft guard
	local profile = Powers.combatProfile("Corruption", 1)
	assert(profile.MaxHealth < 100 and profile.Block.MaxGuard < 100, "fragile with a soft guard")
	-- The overwrite: each degree starts further along; the final form is all the way
	assert(ServerCorruption.phaseFor(1, 0, 100, false) == 0.05, "Degree 1 barely touched")
	assert(near(ServerCorruption.phaseFor(1, 100, 100, false), 0.35), "Degree 1 at a full meter")
	assert(near(ServerCorruption.phaseFor(2, 0, 100, false), 0.35), "Degree 2 starts where 1 ends")
	assert(near(ServerCorruption.phaseFor(3, 100, 100, false), 0.95), "Degree 3 nearly gone")
	assert(ServerCorruption.phaseFor(1, 0, 100, true) == 1, "the final form is total")
end)

check("every effect and projectile the server sends has a client drawing", function()
	local fs = require("@lune/fs")
	local server = fs.readFile("src/server/Powers/Corruption.luau")
	local client = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Powers.Corruption"))
	local names = {}
	for name in string.gmatch(server, 'fx%("(%w+)"') do
		names[name] = true
	end
	for name in string.gmatch(server, 'lastingFx%("(%w+)"') do
		names[name] = true
	end
	for name in string.gmatch(server, 'fx = "(%w+)"') do
		names[name] = true
	end
	local total = 0
	for name in names do
		total += 1
		assert(client.fx[name], "no client effect for " .. name)
	end
	assert(total >= 30, "found the effects: " .. total)
	for name in client.fx do
		assert(names[name], "the server never sends " .. name)
	end
	for visual in string.gmatch(server, 'visual = "(%w+)"') do
		assert(client.projectiles[visual], "no projectile drawing for " .. visual)
	end
	assert(client.projectiles.VoidShard, "the shard is drawn")
	for abilityId in DEF.abilities do
		assert(client.predict[abilityId], "instant wind-up for " .. abilityId)
	end
end)

-- Equipping ---------------------------------------------------------------------------------

check("two players equip Corruption and start a duel: stats, an empty meter, the first overwrite", function()
	alice = game.join("Alice")
	bob = game.join("Bob")
	game.waitFor(function()
		return A() ~= nil and A().power ~= nil and B() ~= nil and B().power ~= nil
	end, 2, "powers to be equipped")
	equip(A(), 1)
	equip(B(), 1)
	for _, fighter in { A(), B() } do
		assert(fighter.power.id == "Corruption", "Corruption")
		assert(fighter.humanoid.MaxHealth == 92, "fragile: 92 health")
		assert(fighter.combat.Block.MaxGuard == 80, "a soft guard")
		assert(fighter.model:GetAttribute(Attribute.ResourceMax) == 100, "meter maximum")
		assert(phase(fighter) == 0.05, "Degree 1 overwrite: " .. phase(fighter))
	end
	request("MatchRequest", alice, "Queue", "Duel")
	request("MatchRequest", bob, "Queue", "Duel")
	local match
	game.waitFor(function()
		match = services.MatchService:getMatchOf(A())
		return match ~= nil and match.flow.phase == "Active"
	end, 4, "the duel to begin")
	arena = match.arena
	-- Ground at the arena's floor, for teleports and zones
	game.flatGround(arena.center.Y)
	task.wait(0.2)
	assert(A().power.id == "Corruption" and B().power.id == "Corruption", "still Corruption in the duel")
	assert(A().power.resource < 1, "the meter starts empty: " .. A().power.resource)
	assert(Powers.combatProfile("Corruption", 3).MaxHealth == 98, "a little sturdier at Degree 3")
end)

-- The meter -----------------------------------------------------------------------------------

check("the meter fills from casts and hits (never by itself), drains out of combat, and exposes when high", function()
	equip(A(), 1)
	equip(B(), 1)
	local a, b = stage(6)
	-- Standing still fills nothing
	task.wait(0.5)
	assert(a.power.resource == 0, "no regeneration")
	local mark = game.mark()
	cast("VoidStrike", nil, 0.6)
	assert(#hitsSince(mark, a, b, "VoidStrike") == 1, "the strike landed")
	local def = ability("VoidStrike", 1)
	-- The cast's charge plus the hit's gain
	assert(near(a.power.resource, def.charge + DEF.resource.hitGain, 0.5), "meter after a landed strike: " .. a.power.resource)
	assert(phase(a) > 0.05, "the overwrite grows with the meter: " .. phase(a))
	-- Out of combat it drains
	a.power.data.activeAt = now() - DEF.resource.decayAfter - 1
	local before = a.power.resource
	task.wait(0.5)
	assert(a.power.resource < before - 1, "drains out of combat: " .. a.power.resource)
	-- High meter: exposed (takes more damage) and the overwrite shows it
	ready(a, 90)
	task.wait(0.3)
	assert(has(a, "Vulnerable"), "exposed at 90")
	assert(near(phase(a), 0.3, 0.051), "a deep Degree 1 overwrite: " .. phase(a))
	ready(a, 40)
	task.wait(0.8)
	assert(not has(a, "Vulnerable"), "not exposed at 40")
end)

-- Every ability at every degree ---------------------------------------------------------------

-- Casts one ability as Alice against Bob and checks it really did something
local function exercise(abilityId: string, degree: number)
	local def = ability(abilityId, degree)
	local label = `{abilityId} at Degree {degree}`
	local a, b
	if abilityId == "RiftBlink" then
		a, b = stage(2)
	elseif abilityId == "CorruptBolt" or abilityId == "UnstableGround" or abilityId == "DistortionZone" or abilityId == "Unravel" then
		a, b = stage(12)
	else
		a, b = stage(5)
	end
	ready(a, 100)
	ready(b)
	if abilityId == "Unravel" then
		-- Something to unravel first
		local strike = ability("VoidStrike", degree)
		a.power.loadout = { "VoidStrike", "Unravel" }
		a, b = stage(6)
		cast("VoidStrike", nil, strike.startup + strike.active + 0.3)
		assert(has(b, "Mark"), label .. ": marked first")
		ready(b)
		services.StatusService:apply(b, "Mark", 4, { source = a })
	end
	a.power.loadout = { abilityId, "VoidStrike" }
	local health = b.humanoid.Health
	local start = a.root.Position
	local meter = a.power.resource
	local mark = game.mark()
	local aim = aimAt(a, b)
	if abilityId == "RiftBlink" then
		aim = { direction = Vector3.new(-1, 0, 0), point = start + Vector3.new(-14, 0, 0) }
	end
	cast(abilityId, aim, 0.05)
	assert(castsSince(mark, a, abilityId) == 1, label .. ": cast")
	assert(cooldownLeft(a, abilityId) > 0, label .. ": cooldown set")
	if (def.cost or 0) > 0 then
		assert(a.power.resource < meter, label .. ": cost paid")
	end
	if abilityId == "Phantasm" then
		task.wait(def.startup + def.active + 0.1)
		assert(has(a, "Concealed") and has(a, "Haste"), label .. ": fades and quickens")
		local copies = fxSince(mark, "Phantasm", a)[1].copies
		assert(#copies == def.copies, label .. ": two reflections")
		-- Bob walks into one of them
		b.root.CFrame = CFrame.new(copies[1].to)
		Engine.syncPositions(world.workspace)
		task.wait(def.fuse + 0.2)
	elseif abilityId == "UnstableGround" or abilityId == "DistortionZone" then
		task.wait(def.startup + (def.arm or 0) + 1.3)
	elseif abilityId == "RiftBlink" then
		task.wait(def.startup + def.active + def.fuse + 0.25)
		Engine.syncPositions(world.workspace)
		assert(flatDistance(a.root.Position, start) > 8, label .. ": blinked " .. flatDistance(a.root.Position, start))
	elseif abilityId == ULT then
		task.wait(def.startup + def.active + 0.4)
	else
		task.wait(def.startup + def.active + 0.35)
	end
	local hits = hitsSince(mark, a, b, abilityId)
	assert(#hits >= 1, label .. ": landed on Bob")
	assert(b.humanoid.Health < health, label .. ": dealt damage")
	if def.distort then
		assert(has(b, "Distort"), label .. ": distorted")
	end
	if def.markStacks then
		assert(has(b, "Mark"), label .. ": marked")
	end
	if abilityId == "UnstableGround" then
		assert(has(b, "Slow"), label .. ": slowed")
	elseif abilityId == "DistortionZone" then
		assert(has(b, "Vulnerable"), label .. ": exposed inside")
	elseif abilityId == "CorruptBolt" then
		assert(#spawnsSince(mark, a, "VoidShard") == 1, label .. ": one shard")
	elseif abilityId == "Unravel" then
		assert(not has(b, "Mark"), label .. ": the mark is spent")
	end
	if def.defense == "Prompt" then
		assert(#cuesFor(mark, bob, "Prompt") >= 1, label .. ": Bob was warned")
	end
	-- Let lasting things end before the next one
	ready(a)
	ready(b)
	task.wait(0.15)
end

check("every ability at every degree it exists at: cast, cost, cooldown and a real effect", function()
	for degree = 1, 3 do
		equip(A(), degree)
		equip(B(), degree)
		for _, abilityId in Powers.available("Corruption", degree) do
			exercise(abilityId, degree)
		end
	end
end)

-- Marks and Unravel ---------------------------------------------------------------------------

local function strikeOnce()
	table.clear(A().power.cooldowns)
	local def = ability("VoidStrike", A().power.degree)
	cast("VoidStrike", nil, def.startup + def.active + def.recovery + 0.1)
end

check("Corruption Marks stack to the degree's limit, and Unravel detonates them (base + per stack)", function()
	for degree = 1, 3 do
		equip(A(), degree, { "VoidStrike", "Unravel" })
		equip(B(), degree)
		local a, b = stage(6)
		ready(a, 100)
		for _ = 1, 4 do
			strikeOnce()
		end
		local entry = a.power.data.marks[b.id]
		assert(entry and entry.stacks == DEF.mark.maxStacks[degree], `Degree {degree}: {DEF.mark.maxStacks[degree]} stacks at most, got {entry and entry.stacks}`)
		assert(has(b, "Mark"), "Bob carries the mark")
		if degree >= 2 then
			-- A fresh combo, so the detonation's damage is exact
			task.wait(1.3)
			b.state.comboCount = 0
			table.clear(a.power.cooldowns)
			local def = ability("Unravel", degree)
			local mark = game.mark()
			cast("Unravel", nil, def.startup + def.active + 0.3)
			local hits = hitsSince(mark, a, b, "Unravel")
			assert(#hits == 1, "one detonation")
			local expected = def.damage + def.perStack * entry.stacks
			assert(near(hits[1].damage, expected, 0.6), `Unravel dealt {hits[1].damage}, expected {expected}`)
			assert(not has(b, "Mark") and a.power.data.marks[b.id] == nil, "marks spent")
			assert(#cuesFor(mark, bob, "Prompt") == 1, "Bob saw it coming")
			assert(#fxSince(mark, "UnravelDetonate", a) == 1, "drawn")
		end
	end
end)

check("Unravel with nothing to unravel (or marks that faded) refunds half; marks fade on their own", function()
	equip(A(), 3, { "VoidStrike", "Unravel" })
	equip(B(), 3)
	local a, b = stage(6)
	ready(a, 100)
	strikeOnce()
	assert(a.power.data.marks[b.id], "marked")
	-- The mark runs out
	a.power.data.marks[b.id].expiresAt = now() - 0.1
	table.clear(a.power.cooldowns)
	a.power.resource = 60
	local mark = game.mark()
	cast("Unravel", nil, 0.3)
	local def = ability("Unravel", 3)
	assert(near(a.power.resource, 60 - def.cost / 2, 0.6), "half back: " .. a.power.resource)
	assert(cooldownLeft(a, "Unravel") < def.cooldown * 0.6, "half the cooldown back")
	assert(#fxSince(mark, "UnravelFizzle", a) == 1, "a fizzle")
	assert(#hitsSince(mark, a, b, "Unravel") == 0, "nothing hit")
	assert(#cuesFor(mark, bob, "Prompt") == 0, "nobody warned for nothing")
	-- And the status itself has a strict maximum
	services.StatusService:apply(b, "Mark", 60, { source = a })
	local endsAt = b.model:GetAttribute(Attribute.StatusPrefix .. "Mark")
	assert(endsAt - now() <= 8.01, "marks can't last past the status cap")
	task.wait(0.4)
end)

-- Destabilising projectiles (Corruption's defense) --------------------------------------------

check("Static Burst, Distortion Pulse and Distortion Zone unmake small enemy projectiles, never massive ones", function()
	equip(A(), 3, { "StaticBurst", "DistortionPulse", "DistortionZone" })
	equip(B(), 3)
	for _, abilityId in { "StaticBurst", "DistortionPulse", "DistortionZone" } do
		local a, b = stage(30)
		ready(a, 100)
		ready(b)
		local def = ability(abilityId, 3)
		local mark = game.mark()
		local here = a.root.Position
		local aim = { direction = Vector3.new(1, 0, 0), point = here + Vector3.new(4, 0, 0) }
		cast(abilityId, aim, 0.02)
		-- Fired in at Alice just as the cast happens; the zone eats ones that come in later
		local small = enemyShot(b, here + Vector3.new(4, 1, 2), Vector3.new(0, 0, 1), { "Projectile", "Small" })
		local massive = enemyShot(b, here + Vector3.new(4, 1, -2), Vector3.new(0, 0, -1), { "Projectile", "Massive" })
		local sealed = enemyShot(b, here + Vector3.new(3, 1, 0), Vector3.new(0, 1, 0), { "Projectile", "Small" }, { interceptable = false })
		local own = services.ProjectileService:spawn(a, {
			power = "Corruption", ability = "TestShot", visual = "VoidShard", origin = here + Vector3.new(2, 1, 0),
			direction = Vector3.new(0, 1, 0), speed = 4, radius = 0.5, lifetime = 4, range = 50,
			hit = { Damage = 1 }, tags = { "Projectile", "Small" },
		})
		task.wait(def.startup + def.active + 0.4)
		local reasons = endsSince(mark)
		assert(small and reasons[small.id] == "Intercepted", abilityId .. ": the small shot was unmade")
		assert(massive and massive.alive, abilityId .. ": a massive one flies on")
		assert(sealed and sealed.alive, abilityId .. ": interceptable = false is respected")
		assert(own and own.alive, abilityId .. ": its own shots are left alone")
		assert(#fxSince(mark, "ShotsUnmade", a) >= 1, abilityId .. ": drawn")
		for _, projectile in { massive, sealed, own } do
			if projectile and projectile.alive then
				services.ProjectileService:finish(projectile, "Destroyed")
			end
		end
		ready(a)
		task.wait(0.1)
	end
end)

-- Rift Blink ----------------------------------------------------------------------------------

check("§38-style: Rift Blink to a blocked spot (or no ground) fails safely and refunds", function()
	equip(A(), 2, D2_KIT)
	equip(B(), 2)
	local blocker = world.Instance.new("Part")
	for _, case in { "blocked", "no ground" } do
		local a = stage(20)
		ready(a, 50)
		local start = a.root.Position
		if case == "blocked" then
			Engine.partsInBox = function()
				return { blocker }
			end
		else
			Engine.raycast = nil
		end
		local mark = game.mark()
		cast("RiftBlink", { direction = Vector3.new(0, 0, 1), point = start + Vector3.new(0, 0, 14) }, 0.35)
		Engine.partsInBox = nil
		game.flatGround(arena.center.Y)
		Engine.syncPositions(world.workspace)
		assert(flatDistance(a.root.Position, start) < 0.01, case .. ": didn't move")
		assert(a.power.resource >= 49, case .. ": refunded: " .. a.power.resource)
		assert(cooldownLeft(a, "RiftBlink") <= 0.6, case .. ": cooldown refunded")
		assert(#fxSince(mark, "RiftBlinkFail", a) == 1, case .. ": shown failing")
		assert(#fxSince(mark, "RiftArrive", a) == 0, case .. ": no arrival drawn")
		assert(not FighterState.isAttacking(a.state, now() + 0.3), case .. ": not stuck in the cast")
		task.wait(0.3)
	end
	-- Aimed far outside the arena: lands inside it
	local a = stage(4, Vector3.new(30, 0, 0))
	ready(a, 50)
	cast("RiftBlink", { direction = Vector3.new(1, 0, 0), point = arena.center + Vector3.new(200, 0, 0) }, 0.35)
	Engine.syncPositions(world.workspace)
	assert(services.ArenaService:contains(arena, a.root.Position, 3.9), "inside the arena: " .. tostring(a.root.Position))
	task.wait(0.6)
end)

-- Unstable Ground --------------------------------------------------------------------------------

check("Unstable Ground settles first, then slows and chips; a new one replaces the old", function()
	equip(A(), 2, D2_KIT)
	equip(B(), 2)
	local a, b = stage(14)
	ready(a, 100)
	local def = ability("UnstableGround", 2)
	local mark = game.mark()
	cast("UnstableGround", aimAt(a, b), def.startup + def.arm * 0.5)
	-- Still settling: readable, harmless
	assert(not has(b, "Slow"), "no slow while it settles")
	assert(#hitsSince(mark, a, b, "UnstableGround") == 0, "no hits while it settles")
	task.wait(def.arm + 0.4)
	assert(has(b, "Slow"), "slowed once it bites")
	assert(#hitsSince(mark, a, b, "UnstableGround") == 1, "one chip per second")
	local first = fxSince(mark, "UnstableGround", a)[1]
	assert(first and first.key, "the floor is drawn")
	-- Stepping off ends it
	b.root.CFrame = b.root.CFrame + Vector3.new(0, 0, def.radius + 6)
	Engine.syncPositions(world.workspace)
	task.wait(0.9)
	assert(not has(b, "Slow"), "stepping off ends the slow")
	-- One floor at a time
	table.clear(a.power.cooldowns)
	a.power.resource = 100
	cast("UnstableGround", { direction = Vector3.new(1, 0, 0), point = a.root.Position + Vector3.new(10, 0, 0) }, def.startup + 0.1)
	local stopped = false
	for _, entry in game.sentSince(mark, "AbilityEvent", "Fx") do
		if entry.fx == "Stop" and entry.data.key == first.key then
			stopped = true
		end
	end
	assert(stopped, "the first floor was replaced")
	ready(a)
	ready(b)
end)

-- Phantasm and Cataclysm ----------------------------------------------------------------------------

check("Phantasm's reflections only hurt those near them, and only after a prompt", function()
	equip(A(), 3, D3_KIT)
	equip(B(), 3)
	local a, b = stage(10)
	ready(a, 100)
	local def = ability("Phantasm", 3)
	local health = b.humanoid.Health
	local mark = game.mark()
	cast("Phantasm", aimAt(a, b), def.startup + def.active + def.fuse + 0.3)
	assert(#fxSince(mark, "PhantasmBurst", a) == def.copies, "both reflections burst")
	assert(#cuesFor(mark, bob, "Prompt") == 0, "Bob, far from them, wasn't threatened")
	assert(b.humanoid.Health == health, "and wasn't hurt")
	task.wait(def.fadeTime)
	assert(not has(a, "Concealed"), "the fade ends")
	ready(a)
end)

check("Cataclysm: a long tell, shrugs off one hit while winding up, then a long recovery", function()
	equip(A(), 3, D3_KIT)
	equip(B(), 3)
	local a, b = stage(8)
	ready(a, 100)
	local def = ability("Cataclysm", 3)
	local mark = game.mark()
	cast("Cataclysm", nil, 0.3)
	assert(#cuesFor(mark, bob, "Prompt") == 1, "a dodge prompt")
	-- Bob jabs into the wind-up: armor takes it
	services.CombatService:applyHit(b, a, { Damage = 3, Hitstun = 0.4, Knockback = 4, GuardDamage = 2 }, { kind = "Light", direction = Vector3.new(-1, 0, 0) })
	task.wait(def.startup + def.active - 0.3 + 0.2)
	local hits = hitsSince(mark, a, b, "Cataclysm")
	assert(#hits == 1, "the eruption landed through the jab")
	assert(has(b, "Distort"), "and distorts")
	assert(FighterState.isAttacking(a.state, now()), "still recovering: a punish window")
	task.wait(def.recovery)
	ready(a)
	ready(b)
end)

-- Total System Corruption ---------------------------------------------------------------------------

-- Starts the final form as Alice (full charge, enough meter) and waits for the burst
local function ascend(degree: number, b)
	local a = A()
	a.power.ult = 100
	a.power.resource = 60
	local def = ability(ULT, degree)
	local mark = game.mark()
	cast(ULT, aimAt(a, b), def.startup + def.active + 0.5)
	return mark, def
end

check("Total System Corruption needs a full charge and 50 Corruption", function()
	equip(A(), 1)
	equip(B(), 1)
	local a = stage(8)
	ready(a, 80)
	local mark = game.mark()
	cast(ULT, nil, 0.2)
	assert(rejection(mark, alice, ULT) == "charge", "needs a full charge")
	a.power.ult = 100
	a.power.resource = 20
	mark = game.mark()
	cast(ULT, nil, 0.2)
	assert(rejection(mark, alice, ULT) == "Needs 50 Corruption", "needs the meter: " .. tostring(rejection(mark, alice, ULT)))
	assert(a.power.ult == 100, "the charge is kept")
	assert(a.model:GetAttribute(FORM) == nil, "no form")
end)

check("Total System Corruption at every degree: a timing bar, the burst, then an empowered final form", function()
	for degree = 1, 3 do
		equip(A(), degree, { "VoidStrike", "CorruptBolt", "StaticBurst" })
		equip(B(), degree)
		local a, b = stage(8)
		ready(a)
		ready(b)
		local health = b.humanoid.Health
		local mark, def = ascend(degree, b)
		assert(#cuesFor(mark, bob, "Timing") == 1, `Degree {degree}: a timing bar for Bob`)
		local hits = hitsSince(mark, a, b, ULT)
		assert(#hits == 1 and b.humanoid.Health < health, `Degree {degree}: the burst landed`)
		assert(near(hits[1].damage, def.damage, 0.6), `Degree {degree}: burst damage {hits[1].damage} vs {def.damage}`)
		-- The form
		local endsAt = a.model:GetAttribute(FORM)
		assert(typeof(endsAt) == "number", "the form is on")
		local left = endsAt - now()
		assert(left > def.formDuration - def.active - 0.9 and left <= def.formDuration, `Degree {degree}: lasts {def.formDuration}s (left {left})`)
		assert(phase(a) == 1, "total overwrite")
		task.wait(0.15)
		assert(a.power.resource == 100, "the meter runs at full")
		assert(has(a, "Vulnerable"), "and fully exposed")
		local walk = Powers.combatProfile("Corruption", degree).Movement.WalkSpeed
		assert(a.combat.Movement.WalkSpeed == walk + def.walkBonus, "quicker on its feet")
		assert(ServerCorruption.costFor(a, a.power, ability("StaticBurst", degree)) == 0, "abilities are free")
		-- Stronger and faster
		ready(b)
		task.wait(1.3)
		b.state.comboCount = 0
		mark = game.mark()
		local strike = ability("VoidStrike", degree)
		cast("VoidStrike", aimAt(a, b), 0.05)
		local cooldown = cooldownLeft(a, "VoidStrike")
		assert(cooldown <= strike.cooldown * def.cooldownScale + 0.1, `faster cooldown: {cooldown}`)
		task.wait(strike.startup + strike.active + 0.3)
		hits = hitsSince(mark, a, b, "VoidStrike")
		assert(#hits == 1 and near(hits[1].damage, strike.damage * def.damageScale, 0.6), `stronger strike: {hits[1] and hits[1].damage}`)
		task.wait(strike.recovery)
		mark = game.mark()
		cast("CorruptBolt", aimAt(a, b), 0.4)
		assert(#spawnsSince(mark, a, "VoidShard") == ability("CorruptBolt", degree).formShards, "a fan of shards")
		-- Can't stack the form on itself
		a.power.ult = 100
		mark = game.mark()
		task.wait(0.3)
		cast(ULT, nil, 0.2)
		assert(rejection(mark, alice, ULT) == "Already in the final form", "no second form: " .. tostring(rejection(mark, alice, ULT)))
		-- A reset ends it without the collapse
		ready(a)
		assert(a.model:GetAttribute(FORM) == nil and a.model:GetAttribute(LOCK) == nil, "reset clears the form")
		assert(a.combat.Movement.WalkSpeed == walk, "normal speed again")
		assert(near(phase(a), DEF.overwrite.base[degree]), "back to the degree's overwrite")
		ready(b)
		task.wait(0.2)
	end
end)

check("§38: a Corruption transformation expires during a hit reaction, then collapses cleanly", function()
	equip(A(), 1)
	equip(B(), 1)
	local a, b = stage(8)
	ready(a)
	ready(b)
	local mark, def = ascend(1, b)
	local endsAt = a.model:GetAttribute(FORM)
	assert(typeof(endsAt) == "number", "in the final form")
	-- Bob catches her with a heavy hit just before it runs out
	task.wait(math.max(0, endsAt - now() - 0.35))
	ready(b)
	local outcome = services.CombatService:applyHit(b, a, { Damage = 6, Hitstun = 1, Knockback = 20, GuardDamage = 10 }, { kind = "Heavy", direction = Vector3.new(-1, 0, 0) })
	assert(outcome and outcome.result == "Hit", "the hit landed")
	assert(a.state.stunUntil > endsAt, "still reeling when the form ends")
	task.wait(endsAt - now() + 0.35)
	-- The collapse: the form is over, the meter empties and locks, and she staggers out
	assert(a.model:GetAttribute(FORM) == nil, "the form ended")
	assert(#fxSince(mark, "FormCollapse", a) == 1, "the collapse is shown")
	local lockUntil = a.model:GetAttribute(LOCK)
	assert(typeof(lockUntil) == "number" and near(lockUntil - now(), def.lockTime - 0.35, 0.3), "the meter locks")
	assert(a.power.resource == 0, "and empties")
	assert(has(a, "Slow"), "she staggers out slowed")
	assert(phase(a) == 0.05, "back to Awakening's overwrite: " .. phase(a))
	assert(a.combat.Movement.WalkSpeed == 16, "normal speed")
	assert(a.humanoid.Health > 0, "alive")
	-- The hit reaction runs its course and she can act again
	task.wait(math.max(0, a.state.stunUntil - now()) + 0.1)
	mark = game.mark()
	table.clear(a.power.cooldowns)
	cast("VoidStrike", aimAt(a, b), 0.6)
	assert(castsSince(mark, a, "VoidStrike") == 1, "acts normally after the stagger")
	assert(#hitsSince(mark, a, b, "VoidStrike") == 1, "and lands")
	assert(a.power.resource == 0, "but the locked meter doesn't fill")
	-- The lock ends on its own
	task.wait(math.max(0, lockUntil - now()) + 0.3)
	assert(a.model:GetAttribute(LOCK) == nil, "unlocked")
	table.clear(a.power.cooldowns)
	a.state.attack = nil
	cast("VoidStrike", aimAt(a, b), 0.6)
	assert(a.power.resource > 0, "fills again")
end)

check("§38: a character dies during an ultimate", function()
	equip(A(), 3, D3_KIT)
	equip(B(), 3)
	local a, b = stage(8)
	ready(a)
	ready(b)
	ascend(3, b)
	assert(typeof(a.model:GetAttribute(FORM)) == "number", "in the final form")
	a.humanoid.Health = 0
	game.waitFor(function()
		local fresh = A()
		return fresh ~= nil and fresh ~= a and fresh.power ~= nil
	end, 3, "Alice to respawn")
	task.wait(0.3)
	local fresh = A()
	assert(fresh.power.id == "Corruption" and fresh.power.degree == 3, "still Corruption (locked for the match)")
	assert(fresh.model:GetAttribute(FORM) == nil and fresh.model:GetAttribute(LOCK) == nil, "no form or lock on the new life")
	assert(near(phase(fresh), 0.65), "a fresh Degree 3 overwrite: " .. phase(fresh))
	assert(fresh.power.resource < 1, "an empty meter")
	assert(not FighterState.isAttacking(fresh.state, now()), "not stuck mid-cast")
	assert(fresh.combat.Movement.WalkSpeed == Powers.combatProfile("Corruption", 3).Movement.WalkSpeed, "normal speed")
	assert(not services.StatusService:has(fresh, "Vulnerable"), "not exposed")
end)

process.exit(if game.finish() == 0 then 0 else 1)
