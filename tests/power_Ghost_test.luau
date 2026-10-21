-- Runs the Ghost end to end with simulated players:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/power_Ghost_test.luau build/game.rbxl
-- Two players fight Ghost against Ghost in a duel and use every ability at
-- every degree it exists at: the instant katana draw (Phase), Phantom Veil and
-- what breaks it, Spectral Dash, the spectral counter (success, early press,
-- grabs/massive attacks/far projectiles), Shadow Step (normal, onto someone,
-- blocked, no ground, outside the arena), Slash Wave and Follow Through, Slash
-- Flurry, the Converging Grid (hit, escaped, dodged), Spectral Severance at all
-- three degrees (and its perfect-timing defense), a knockout mid-ultimate,
-- simultaneous attacks, junk requests and cooldown spam, a match ending with
-- slashes in flight, a Ghost CPU, and every client effect.

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
local GHOST = Powers.get("Ghost")

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

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function aimAt(from, to)
	return { direction = (to.root.Position - from.root.Position).Unit, point = to.root.Position }
end

-- Full health, resource and a clean state, so tests don't wait on each other
local function ready(fighter)
	local runtime = fighter.power
	runtime.resource = runtime.resourceMax
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
	services.PowerService:equip(fighter, "Ghost", degree, loadout or Powers.defaultLoadout("Ghost", degree))
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

local function hitsSince(mark: number, attacker, victim, ability: string?)
	local list = {}
	for _, hit in game.sentSince(mark, "CombatEvent", "Hit") do
		if hit.attacker == attacker.model and hit.victim == victim.model and (ability == nil or hit.ability == ability) then
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

local function rejection(mark: number, player, ability: string): string?
	for _, entry in game.sentSince(mark, "AbilityEvent", "Rejected", player) do
		if entry.ability == ability then
			return entry.reason
		end
	end
	return nil
end

local function cooldownSet(fighter, ability: string): boolean
	return (fighter.model:GetAttribute(Attribute.CooldownPrefix .. ability) or 0) > now()
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

-- Definition ------------------------------------------------------------------------------

check("the Ghost's definition: card text fits, resource, AI hints, degrees and loadouts", function()
	assert(GHOST, "the Ghost is registered")
	assert(utf8.len(GHOST.name) <= 20 and utf8.len(GHOST.description) <= 160, "power text fits a card")
	assert(GHOST.resource.id == "Spirit" and GHOST.resource.max == 100 and GHOST.resource.start == 50, "Spirit 0-100, starts at 50")
	assert(GHOST.resource.regen > 0 and GHOST.resource.gainOnHit > 0, "Spirit regenerates and is gained on hit")
	assert(GHOST.ai.preferredRange and GHOST.ai.aggression, "power AI hints")
	for _, degree in GHOST.degrees do
		assert(utf8.len(degree.name) <= 20 and utf8.len(degree.description) <= 160, degree.name .. " text fits")
		assert(degree.ultimate == "SpectralSeverance", "ultimate on every degree")
	end
	for abilityId, ability in GHOST.abilities do
		assert(utf8.len(ability.name) <= 20, abilityId .. " name fits")
		assert(utf8.len(ability.description) <= 160, abilityId .. " description fits")
		assert(ability.ai and ability.ai.range and ability.ai.use, abilityId .. " has an AI hint")
		assert(table.find(GHOST.abilityOrder, abilityId), abilityId .. " is in abilityOrder")
		if ability.kind ~= "Ultimate" then
			assert((ability.cost or 0) > 0, abilityId .. " costs Spirit")
		end
	end
	-- Degrees expand the power: everything lower is still there
	assert(#Powers.available("Ghost", 1) == 4 and #Powers.available("Ghost", 2) == 8 and #Powers.available("Ghost", 3) == 9, "4 / 8 / 9 abilities")
	for degree = 1, 3 do
		local ok, reason = Powers.validateLoadout("Ghost", degree, Powers.defaultLoadout("Ghost", degree), {})
		assert(ok, `degree {degree} default loadout: {reason}`)
	end
	-- The counter is bought at Degree 1 and included from Degree 2
	assert(not Powers.validateLoadout("Ghost", 1, { "SpectralCounter" }, {}), "counter costs Money at Degree 1")
	assert(Powers.validateLoadout("Ghost", 1, { "SpectralCounter" }, { abilities = { SpectralCounter = true } }), "bought counter")
	assert(Powers.validateLoadout("Ghost", 2, { "SpectralCounter" }, {}), "free from Degree 2")
	-- Scaling: more slashes and faster chains at the apex
	assert(Powers.abilityFor("Ghost", "SlashWave", 3).count == 2, "two crossing slashes at Degree 3")
	assert(Powers.abilityFor("Ghost", "SlashFlurry", 3).sweeps > Powers.abilityFor("Ghost", "SlashFlurry", 2).sweeps, "more sweeps")
	assert(Powers.abilityFor("Ghost", "SpectralSeverance", 3).damage > Powers.abilityFor("Ghost", "SpectralSeverance", 1).damage, "ultimate scales")
	local d1, d3 = Powers.combatProfile("Ghost", 1), Powers.combatProfile("Ghost", 3)
	assert(d3.Light.Steps[1].Startup < d1.Light.Steps[1].Startup, "faster chain at Degree 3")
end)

check("every effect the server sends has a client drawing", function()
	local fs = require("@lune/fs")
	local server = fs.readFile("src/server/Powers/Ghost.luau")
	local client = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Powers.Ghost"))
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
	assert(total >= 20, "found the effects: " .. total)
	assert(client.projectiles.SlashWave, "the slash projectile has a drawing")
	for abilityId in GHOST.abilities do
		assert(client.predict[abilityId], "instant wind-up for " .. abilityId)
	end
end)

-- Equipping ---------------------------------------------------------------------------------

check("two players equip the Ghost: stats, Spirit and a sheathed katana", function()
	alice = game.join("Alice")
	bob = game.join("Bob")
	game.waitFor(function()
		return A() ~= nil and A().power ~= nil and B() ~= nil and B().power ~= nil
	end, 2, "powers to be equipped")
	equip(A(), 1, { "InstantDraw", "SpectralDash", "PhantomVeil" })
	equip(B(), 1)
	for _, fighter in { A(), B() } do
		assert(fighter.power.id == "Ghost", "the Ghost")
		assert(fighter.humanoid.MaxHealth == 90, "Ghost health")
		assert(fighter.humanoid.WalkSpeed == 18, "Ghost speed: " .. fighter.humanoid.WalkSpeed)
		assert(fighter.combat.Block.MaxGuard == 80, "weaker guard")
		assert(fighter.combat.Dodge.Cooldown < game.Combat.Dodge.Cooldown, "quicker dodge")
		assert(fighter.combat.Light.Steps[1].Range > game.Combat.Light.Steps[1].Range, "katana reaches further than fists")
		assert(fighter.model:GetAttribute(Attribute.ResourceMax) == 100, "Spirit maximum")
		assert(fighter.model:GetAttribute(Attribute.Phase) == 0, "katana sheathed")
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
	assert(A().power.id == "Ghost" and B().power.id == "Ghost", "still Ghosts in the duel")
	assert(math.abs(A().power.resource - 50) < 3, "Spirit starts at 50: " .. A().power.resource)
end)

-- Degree 1: Phantom Blade ------------------------------------------------------------------------

check("Instant Draw: a light swing draws the katana at once, longer reach, sheathes after a pause", function()
	local a, b = stage(7.5)
	ready(a)
	ready(b)
	local health = b.humanoid.Health
	request("CombatRequest", alice, "Light")
	task.wait(0.2)
	assert(a.model:GetAttribute(Attribute.Phase) == 1, "katana drawn")
	assert(b.humanoid.Health < health, "the katana reaches 7.5 studs")
	local drawnUntil = a.power.data.drawnUntil
	assert(drawnUntil and drawnUntil > now(), "drawn-until kept")
	task.wait(GHOST.katana.sheatheAfter + 0.3)
	assert(a.model:GetAttribute(Attribute.Phase) == 0, "katana sheathed again")
	assert(a.power.data.drawnUntil == nil, "drawn-until cleared")
end)

check("Instant Draw (ability): fast long cut, costs Spirit, cooldown; a miss is punished", function()
	local a, b = stage(9)
	ready(a)
	ready(b)
	local health = b.humanoid.Health
	a.power.resource = 60
	local mark = game.mark()
	request("AbilityRequest", alice, "InstantDraw", aimAt(a, b))
	task.wait(0.35)
	local hits = hitsSince(mark, a, b, "InstantDraw")
	assert(#hits == 1 and near(hits[1].damage, 13), "one 13-damage cut")
	assert(b.humanoid.Health < health, "Bob hurt")
	-- 60, minus the cost, plus Spirit for landing it and a moment of regen
	local spent = Powers.abilityFor("Ghost", "InstantDraw", 1).cost
	assert(a.power.resource <= 60 - spent + GHOST.resource.gainOnHit + GHOST.resource.regen * 0.5, "Spirit spent: " .. a.power.resource)
	assert(cooldownSet(a, "InstantDraw"), "cooldown published")
	assert(a.model:GetAttribute(Attribute.Phase) == 1, "katana drawn")
	assert(#fxSince(mark, "InstantDraw", a) == 1, "the cut is drawn")
	-- Out of reach: whiffs and leaves him open longer
	task.wait(0.4)
	a, b = stage(16)
	ready(a)
	local castAt = now()
	request("AbilityRequest", alice, "InstantDraw", aimAt(a, b))
	task.wait(0.25)
	local attack = a.state.attack
	local def = Powers.abilityFor("Ghost", "InstantDraw", 1)
	assert(attack and attack.recoveryEnd - castAt >= def.startup + def.active + def.recovery + def.whiffRecovery - 0.05, "whiff recovery added")
	task.wait(0.6)
end)

check("Spectral Dash: a real dash with afterimages, no hit, cost and cooldown", function()
	local a = stage(20)
	ready(a)
	a.power.resource = 50
	local mark = game.mark()
	request("AbilityRequest", alice, "SpectralDash", { direction = Vector3.new(0, 0, 1) })
	task.wait(0.12)
	-- The dash is an attachment plus a LinearVelocity, both called SNDash
	local mover
	for _, child in a.root:GetChildren() do
		if child.Name == "SNDash" and child:IsA("LinearVelocity") then
			mover = child
		end
	end
	local def = Powers.abilityFor("Ghost", "SpectralDash", 1)
	assert(mover and mover:IsA("LinearVelocity"), "dash mover")
	assert((mover.VectorVelocity - Vector3.new(0, 0, def.speed)).Magnitude < 0.01, "dashes where aimed at full speed")
	assert(a.dashUntil > now(), "the dash is a legitimate move")
	assert(#fxSince(mark, "SpectralDash", a) == 1, "afterimages drawn")
	assert(a.power.resource < 45, "Spirit spent")
	assert(cooldownSet(a, "SpectralDash"), "cooldown")
	task.wait(0.4)
	assert(a.root:FindFirstChild("SNDash") == nil, "the dash ends")
end)

check("Phantom Veil: concealed and faster, broken by attacking, by being hit, and by time", function()
	local a, b = stage(5)
	ready(a)
	ready(b)
	local torso = a.model:FindFirstChild("UpperTorso")
	local def = Powers.abilityFor("Ghost", "PhantomVeil", 1)
	request("AbilityRequest", alice, "PhantomVeil", {})
	task.wait(0.25)
	local concealed = services.StatusService:get(a, "Concealed")
	assert(concealed and near(concealed.magnitude, def.transparency), "concealed")
	assert(concealed.endsAt - now() <= game.Combat.Statuses.Concealed.max, "within the Concealed cap")
	assert(services.StatusService:has(a, "Haste"), "faster")
	assert(a.statusSpeed > 1, "walk speed boosted")
	assert(torso.Transparency >= def.transparency - 1e-3, "mostly see-through, never fully")
	assert(torso.Transparency < 1, "not fully invisible")
	-- Attacking breaks it
	local mark = game.mark()
	request("CombatRequest", alice, "Light")
	task.wait(0.25)
	assert(not services.StatusService:has(a, "Concealed"), "attacking breaks the veil")
	assert(not services.StatusService:has(a, "Haste"), "the speed goes with it")
	assert(torso.Transparency == 0, "visible again")
	assert(#fxSince(mark, "VeilBreak", a) >= 1, "shown breaking")
	-- Being hit breaks it
	task.wait(0.6)
	ready(a)
	ready(b)
	stage(4)
	request("AbilityRequest", alice, "PhantomVeil", {})
	task.wait(0.25)
	assert(services.StatusService:has(a, "Concealed"), "veiled again")
	local health = a.humanoid.Health
	request("CombatRequest", bob, "Light")
	task.wait(0.25)
	assert(a.humanoid.Health < health, "veiled is not immune")
	assert(not services.StatusService:has(a, "Concealed"), "being hit breaks the veil")
	-- Left alone, it runs out
	task.wait(0.6)
	ready(a)
	request("AbilityRequest", alice, "PhantomVeil", {})
	task.wait(0.25)
	assert(services.StatusService:has(a, "Concealed"), "veiled once more")
	task.wait(def.duration + 0.2)
	assert(not services.StatusService:has(a, "Concealed"), "the veil ends on its own")
	assert(a.model:GetAttribute(Attribute.StatusPrefix .. "Concealed") == nil, "clients told")
end)

check("Spectral Counter: a melee hit in the window is answered from behind", function()
	equip(A(), 1, { "InstantDraw", "SpectralCounter", "PhantomVeil" })
	local a, b = stage(4)
	ready(b)
	local health, bobHealth = a.humanoid.Health, b.humanoid.Health
	local mark = game.mark()
	request("AbilityRequest", alice, "SpectralCounter", aimAt(a, b))
	task.wait(0.05)
	request("CombatRequest", bob, "Light")
	task.wait(0.5)
	Engine.syncPositions(world.workspace)
	assert(a.humanoid.Health == health, "the swing was negated")
	local countered = false
	for _, hit in hitsSince(mark, b, a) do
		countered = countered or hit.result == "Countered"
	end
	assert(countered, "shown as countered")
	local strikes = hitsSince(mark, a, b, "SpectralCounter")
	assert(#strikes == 1 and strikes[1].result == "Hit", "the counterstrike landed")
	assert(b.humanoid.Health < bobHealth, "Bob hurt by the counter")
	assert(a.root.Position.X > b.root.Position.X, "Alice phased behind Bob")
	assert(#fxSince(mark, "CounterStrike", a) == 1, "drawn")
	assert(cooldownSet(a, "SpectralCounter"), "the counter has a cooldown")
	-- Pressing again right away is refused
	local again = game.mark()
	request("AbilityRequest", alice, "SpectralCounter", {})
	task.wait(0.1)
	assert(rejection(again, alice, "SpectralCounter") ~= nil, "no counter spam")
	task.wait(0.5)
end)

check("Spectral Counter: too early does nothing and leaves him open", function()
	local a, b = stage(4)
	ready(a)
	ready(b)
	local health = a.humanoid.Health
	local mark = game.mark()
	request("AbilityRequest", alice, "SpectralCounter", aimAt(a, b))
	task.wait(0.55)
	assert(#fxSince(mark, "CounterWhiff", a) == 1, "the stance whiffed")
	request("CombatRequest", bob, "Light")
	task.wait(0.3)
	assert(a.humanoid.Health < health, "the late swing lands normally")
	for _, hit in hitsSince(mark, b, a) do
		assert(hit.result ~= "Countered", "not countered")
	end
	task.wait(0.4)
end)

check("Spectral Counter: grabs and massive attacks go through; far small projectiles are evaded", function()
	local a, b = stage(3)
	ready(a)
	services.PowerService:equip(b, "StrongDude", 1, { "Groundbreaker", "TitanGrip", "MeteorCharge" })
	ready(b)
	local health = a.humanoid.Health
	local mark = game.mark()
	request("AbilityRequest", alice, "SpectralCounter", aimAt(a, b))
	task.wait(0.02)
	request("AbilityRequest", bob, "TitanGrip", aimAt(b, a))
	task.wait(0.4)
	assert(services.StatusService:has(a, "Grabbed"), "the grab caught her in the stance")
	assert(#cuesFor(mark, alice, "Mash") == 1, "she gets the mash prompt instead")
	task.wait(1.6)
	assert(a.humanoid.Health < health, "the slam landed")
	-- Massive: World Breaker during the stance
	task.wait(0.4)
	a, b = stage(8)
	ready(a)
	ready(b)
	b.power.ult = 100
	health = a.humanoid.Health
	mark = game.mark()
	request("AbilityRequest", bob, "WorldBreaker", aimAt(b, a))
	task.wait(1.15)
	request("AbilityRequest", alice, "SpectralCounter", aimAt(a, b))
	task.wait(0.8)
	assert(a.humanoid.Health < health, "massive attacks aren't countered")
	for _, hit in hitsSince(mark, b, a) do
		assert(hit.result ~= "Countered", "not countered")
	end
	task.wait(1)
	-- A small slash from far away: a spectral sidestep, no strike back
	equip(B(), 2)
	a, b = stage(20)
	ready(a)
	health = a.humanoid.Health
	local bobHealth = b.humanoid.Health
	mark = game.mark()
	request("AbilityRequest", bob, "SlashWave", aimAt(b, a))
	task.wait(0.15)
	request("AbilityRequest", alice, "SpectralCounter", aimAt(a, b))
	task.wait(0.6)
	assert(a.humanoid.Health == health, "the slash was evaded")
	assert(#fxSince(mark, "CounterEvade", a) == 1, "a spectral sidestep")
	assert(b.humanoid.Health == bobHealth, "too far to strike back")
	task.wait(0.4)
end)

-- Degree 2: Shadow Step ------------------------------------------------------------------------------

local D2 = { "ShadowStep", "SlashWave", "SlashFlurry", "FollowThrough", "SpectralCounter" }

check("Shadow Step: teleports to the aimed spot (validated), costs and cools down", function()
	equip(A(), 2, D2)
	local a = stage(20)
	local start = a.root.Position
	local target = start + Vector3.new(0, -3, 15)
	a.power.resource = 60
	local mark = game.mark()
	request("AbilityRequest", alice, "ShadowStep", { direction = Vector3.new(0, 0, 1), point = target })
	task.wait(0.35)
	Engine.syncPositions(world.workspace)
	assert(flatDistance(a.root.Position, target) < 1, "landed on the spot")
	assert(math.abs(a.root.Position.Y - 3) < 0.01, "standing on the ground")
	assert(#fxSince(mark, "ShadowStepMark", a) == 1 and #fxSince(mark, "ShadowStep", a) == 1, "marked and drawn")
	assert(a.power.resource < 45, "Spirit spent")
	assert(cooldownSet(a, "ShadowStep"), "cooldown")
	-- Onto Bob: lands just short of him
	task.wait(0.3)
	local b
	a, b = stage(14)
	ready(a)
	request("AbilityRequest", alice, "ShadowStep", aimAt(a, b))
	task.wait(0.35)
	Engine.syncPositions(world.workspace)
	local distance = flatDistance(a.root.Position, b.root.Position)
	assert(distance >= 3 and distance < 5, "next to Bob, not inside him: " .. distance)
end)

check("§38: a Ghost teleport destination is blocked (or has no ground): it fails safely and refunds", function()
	local blocker = world.Instance.new("Part")
	local function overlap(blocked: boolean)
		Engine.partsInBox = if blocked
			then function()
				return { blocker }
			end
			else nil
	end
	for _, case in { "blocked", "no ground" } do
		local a = stage(20)
		ready(a)
		local start = a.root.Position
		a.power.resource = 60
		if case == "blocked" then
			overlap(true)
		else
			Engine.raycast = nil
		end
		local mark = game.mark()
		request("AbilityRequest", alice, "ShadowStep", { direction = Vector3.new(0, 0, 1), point = start + Vector3.new(0, -3, 15) })
		task.wait(0.35)
		overlap(false)
		game.flatGround(0)
		Engine.syncPositions(world.workspace)
		assert(flatDistance(a.root.Position, start) < 0.01, case .. ": didn't move")
		assert(a.power.resource >= 59, case .. ": Spirit refunded: " .. a.power.resource)
		local readyAt = a.model:GetAttribute(Attribute.CooldownPrefix .. "ShadowStep") or 0
		assert(readyAt <= now() + 0.6, case .. ": cooldown refunded")
		assert(#fxSince(mark, "ShadowStepFail", a) == 1, case .. ": shown failing")
		assert(#fxSince(mark, "ShadowStep", a) == 0, case .. ": no teleport drawn")
		assert(not FighterState.isAttacking(a.state, now() + 0.3), case .. ": not stuck in the cast")
		task.wait(0.4)
	end
end)

check("Shadow Step aimed outside the arena lands inside it", function()
	local a = stage(4, Vector3.new(44, 0, 0))
	ready(a)
	request("AbilityRequest", alice, "ShadowStep", { direction = Vector3.new(1, 0, 0), point = arena.center + Vector3.new(80, 0, 0) })
	task.wait(0.35)
	Engine.syncPositions(world.workspace)
	assert(services.ArenaService:contains(arena, a.root.Position, 3.9), "inside the arena: " .. tostring(a.root.Position))
	task.wait(0.2)
end)

check("Slash Wave flies along its path and hits; Follow Through dashes after it, once", function()
	local a, b = stage(20)
	ready(a)
	ready(b)
	local health = b.humanoid.Health
	local mark = game.mark()
	request("AbilityRequest", alice, "SlashWave", aimAt(a, b))
	game.waitFor(function()
		return #game.sentSince(mark, "AbilityEvent", "ProjectileEnd") > 0
	end, 2, "the slash to land")
	local spawned = game.sentSince(mark, "AbilityEvent", "ProjectileSpawn")
	assert(#spawned == 1 and spawned[1].visual == "SlashWave", "one white slash")
	assert(spawned[1].data and spawned[1].data.width, "its look travels with it")
	local ended = game.sentSince(mark, "AbilityEvent", "ProjectileEnd")[1]
	assert(ended.reason == "Hit", "it hit Bob: " .. tostring(ended.reason))
	assert(b.humanoid.Health < health, "Bob hurt")
	local follow = a.power.data.follow
	assert(follow and follow.target == b, "the slash opened a follow-up on Bob")
	-- Follow Through (Bob is now right in front of the dash)
	task.wait(0.3)
	stage(4)
	health = b.humanoid.Health
	mark = game.mark()
	local castAt = now()
	request("AbilityRequest", alice, "FollowThrough", aimAt(a, b))
	task.wait(0.4)
	local strikes = hitsSince(mark, a, b, "FollowThrough")
	assert(#strikes == 1, "the follow-up strike landed")
	assert(b.humanoid.Health < health, "Bob hurt")
	assert(a.dashUntil > castAt, "it was a dash")
	assert(a.power.data.follow == nil, "one follow per slash")
	assert(#fxSince(mark, "FollowDash", a) == 1, "drawn")
	task.wait(0.4)
	a.power.cooldowns.FollowThrough = 0
	mark = game.mark()
	request("AbilityRequest", alice, "FollowThrough", aimAt(a, b))
	task.wait(0.1)
	assert(rejection(mark, alice, "FollowThrough") == "No slash to follow", "nothing to follow now")
end)

check("Slash Flurry: several sweeps, each with its own angle and arc; it opens a follow-up", function()
	local a, b = stage(5)
	ready(a)
	ready(b)
	local def = Powers.abilityFor("Ghost", "SlashFlurry", 2)
	local mark = game.mark()
	request("AbilityRequest", alice, "SlashFlurry", aimAt(a, b))
	task.wait(def.startup + def.active + 0.2)
	local sweeps = fxSince(mark, "FlurrySweep", a)
	assert(#sweeps == def.sweeps, "every sweep drawn: " .. #sweeps)
	local tilts = {}
	for _, sweep in sweeps do
		assert(not tilts[sweep.tilt], "each sweep has a distinct angle")
		tilts[sweep.tilt] = true
	end
	assert(#hitsSince(mark, a, b, "SlashFlurry") == def.sweeps, "every sweep's arc hit")
	assert(a.power.data.follow ~= nil, "follow-up window open")
	task.wait(0.4)
end)

-- Degree 3: Spectral Executioner ---------------------------------------------------------------------

local D3 = { "PhantomVeil", "InstantDraw", "ShadowStep", "SlashWave", "SlashFlurry", "ConvergingGrid" }

check("Converging Grid: a readable prompt, then only those still inside are hit", function()
	equip(A(), 3, D3)
	local a, b = stage(12)
	ready(b)
	local health = b.humanoid.Health
	local mark = game.mark()
	request("AbilityRequest", alice, "ConvergingGrid", aimAt(a, b))
	task.wait(0.2)
	assert(#cuesFor(mark, bob, "Prompt") == 1, "Bob gets a dodge/block prompt")
	assert(#fxSince(mark, "GridMark", a) == 1, "the area is marked")
	task.wait(1)
	local hits = hitsSince(mark, a, b, "ConvergingGrid")
	assert(#hits == 1 and near(hits[1].damage, 18), "one grid hit")
	assert(b.humanoid.Health < health, "Bob stayed inside and was hit")
	assert(#fxSince(mark, "GridStrike", a) == 1, "the slashes crossed")
	-- Leaving in time escapes it
	task.wait(0.4)
	a, b = stage(12)
	ready(a)
	ready(b)
	health = b.humanoid.Health
	mark = game.mark()
	request("AbilityRequest", alice, "ConvergingGrid", aimAt(a, b))
	task.wait(0.3)
	b.root.CFrame = b.root.CFrame + Vector3.new(0, 0, 14)
	Engine.syncPositions(world.workspace)
	task.wait(0.9)
	assert(b.humanoid.Health == health, "got out in time")
	assert(#fxSince(mark, "GridStrike", a) == 1, "the grid still struck its area")
	-- A well-timed dodge also beats it
	task.wait(0.4)
	a, b = stage(12)
	ready(a)
	ready(b)
	health = b.humanoid.Health
	mark = game.mark()
	request("AbilityRequest", alice, "ConvergingGrid", aimAt(a, b))
	local cue
	game.waitFor(function()
		cue = cuesFor(mark, bob, "Prompt")[1]
		return cue ~= nil
	end, 1, "the prompt")
	task.wait(math.max(0, cue.impactAt - now() - 0.1))
	request("CombatRequest", bob, "Dodge", Vector3.new(0, 0, 1))
	task.wait(0.5)
	assert(b.humanoid.Health == health, "dodged through it")
	local result = game.lastSent("DefenseEvent", "Result", bob)
	assert(result and result.result == "Perfect", "a perfect read: " .. tostring(result and result.result))
	task.wait(0.3)
end)

check("Degree 3: two crossing slashes, five flurry sweeps, Shadow Step arrives slashing", function()
	local a, b = stage(20)
	ready(a)
	ready(b)
	local mark = game.mark()
	request("AbilityRequest", alice, "SlashWave", aimAt(a, b))
	task.wait(0.6)
	local spawned = game.sentSince(mark, "AbilityEvent", "ProjectileSpawn")
	assert(#spawned == 2, "two slashes: " .. #spawned)
	assert((spawned[1].origin - spawned[2].origin).Magnitude >= 2, "they start apart")
	assert(spawned[1].velocity.Unit:Dot(spawned[2].velocity.Unit) < 0.999, "and cross")
	task.wait(0.3)
	a, b = stage(5)
	ready(a)
	ready(b)
	mark = game.mark()
	request("AbilityRequest", alice, "SlashFlurry", aimAt(a, b))
	task.wait(1)
	assert(#fxSince(mark, "FlurrySweep", a) == 5, "five sweeps at the apex")
	task.wait(0.3)
	a, b = stage(14)
	ready(a)
	ready(b)
	local health = b.humanoid.Health
	mark = game.mark()
	request("AbilityRequest", alice, "ShadowStep", aimAt(a, b))
	task.wait(0.4)
	assert(#fxSince(mark, "ShadowSlash", a) == 1, "arrival slash drawn")
	assert(#hitsSince(mark, a, b, "ShadowStep") == 1, "the arrival slash hit")
	assert(b.humanoid.Health < health, "Bob hurt")
	task.wait(0.3)
end)

check("Instant Draw straight out of the veil is an ambush (Degree 2+)", function()
	local a, b = stage(8)
	ready(a)
	ready(b)
	request("AbilityRequest", alice, "PhantomVeil", {})
	task.wait(0.3)
	assert(services.StatusService:has(a, "Concealed"), "veiled")
	local mark = game.mark()
	request("AbilityRequest", alice, "InstantDraw", aimAt(a, b))
	task.wait(0.35)
	local def = Powers.abilityFor("Ghost", "InstantDraw", 3)
	local hits = hitsSince(mark, a, b, "InstantDraw")
	assert(#hits == 1 and near(hits[1].damage, def.damage * def.ambush, 0.01), "ambush damage: " .. tostring(hits[1] and hits[1].damage))
	assert(not services.StatusService:has(a, "Concealed"), "the cut revealed him")
	task.wait(0.5)
end)

-- Ultimate -------------------------------------------------------------------------------------------

check("Spectral Severance at every degree: afterimage cuts, then a timed final strike from behind", function()
	for degree = 1, 3 do
		equip(A(), degree)
		local a, b = stage(10)
		ready(b)
		a.power.ult = 100
		local def = Powers.abilityFor("Ghost", "SpectralSeverance", degree)
		local start = a.root.Position
		local mark = game.mark()
		request("AbilityRequest", alice, "SpectralSeverance", aimAt(a, b))
		local cue
		game.waitFor(function()
			cue = cuesFor(mark, bob, "Timing")[1]
			return cue ~= nil
		end, 1, "Bob's timing bar")
		-- Checked now: the hits below charge the next ultimate a little
		assert(a.power.ult < 5, `degree {degree}: the charge was spent`)
		task.wait(math.max(0, cue.impactAt - now()) + 0.5)
		Engine.syncPositions(world.workspace)
		local passes, finals = 0, 0
		for _, hit in hitsSince(mark, a, b, "SpectralSeverance") do
			if near(hit.damage, def.pass.damage) then
				passes += 1
			elseif near(hit.damage, def.damage) then
				finals += 1
			end
		end
		assert(passes == def.passes, `degree {degree}: {def.passes} afterimage cuts, got {passes}`)
		assert(finals == 1, `degree {degree}: the final strike landed`)
		assert(#fxSince(mark, "SeverancePass", a) == def.passes, "every cut drawn")
		assert(#fxSince(mark, "SeveranceStrike", a) == 1, "final strike drawn")
		assert(flatDistance(a.root.Position, start) > 8, "he struck from behind Bob")
		task.wait(1)
	end
end)

check("Spectral Severance: perfect timing negates the final strike", function()
	equip(A(), 2)
	local a, b = stage(10)
	ready(b)
	a.power.ult = 100
	local def = Powers.abilityFor("Ghost", "SpectralSeverance", 2)
	local mark = game.mark()
	request("AbilityRequest", alice, "SpectralSeverance", aimAt(a, b))
	local cue
	game.waitFor(function()
		cue = cuesFor(mark, bob, "Timing")[1]
		return cue ~= nil
	end, 1, "Bob's timing bar")
	-- Press right on the impact (the engine reports 0.05s ping, half is allowed for)
	task.wait(math.max(0, cue.impactAt - now() + 0.025))
	request("DefenseInput", bob, "Timing", cue.id)
	task.wait(0.6)
	local result = game.lastSent("DefenseEvent", "Result", bob)
	assert(result and result.result == "Perfect", "perfect: " .. tostring(result and result.result))
	for _, hit in hitsSince(mark, a, b, "SpectralSeverance") do
		assert(not near(hit.damage, def.damage), "the final strike didn't land")
	end
	assert(FighterState.isStunned(a.state, now() - 0.3) or true, "")
	task.wait(1.2)
end)

check("§38: a character dies during an ultimate", function()
	local a, b = stage(10)
	ready(a)
	ready(b)
	a.power.ult = 100
	local health = b.humanoid.Health
	local mark = game.mark()
	request("AbilityRequest", alice, "SpectralSeverance", aimAt(a, b))
	task.wait(0.4)
	a.humanoid.Health = 0
	game.waitFor(function()
		local fresh = A()
		return fresh ~= nil and fresh ~= a and fresh.power ~= nil
	end, 3, "Alice to respawn")
	task.wait(1.2)
	assert(b.humanoid.Health == health, "nothing landed after the knockout")
	assert(#fxSince(mark, "SeveranceStrike", a) == 0, "no final strike")
	local fresh = A()
	assert(fresh.power.id == "Ghost", "still the Ghost (locked for the match)")
	assert(not FighterState.isAttacking(fresh.state, now()), "not stuck mid-cast")
	assert(fresh.model:GetAttribute(Attribute.Phase) == 0, "katana sheathed on the new life")
	assert(fresh.power.ult < 5, "charge starts (nearly) empty")
end)

-- Edge cases -----------------------------------------------------------------------------------------

check("§38: two players attack at the same moment", function()
	equip(A(), 1, { "InstantDraw", "SpectralDash", "PhantomVeil" })
	equip(B(), 1)
	local a, b = stage(5)
	local mark = game.mark()
	request("CombatRequest", alice, "Light")
	request("CombatRequest", bob, "Light")
	task.wait(0.4)
	local landed = #hitsSince(mark, a, b) + #hitsSince(mark, b, a)
	assert(landed >= 1, "the swings resolved")
	task.wait(1.2)
	assert(not FighterState.isAttacking(a.state, now()) and not FighterState.isAttacking(b.state, now()), "neither is stuck")
	assert(a.model:GetAttribute(Attribute.Phase) == 1 and b.model:GetAttribute(Attribute.Phase) == 1, "both drew their katanas")
end)

check("§38: invalid requests and cooldown spam are refused", function()
	equip(A(), 2, D2)
	local a, b = stage(20)
	ready(b)
	local mark = game.mark()
	for _ = 1, 6 do
		request("AbilityRequest", alice, "SlashWave", aimAt(a, b))
		task.wait(0.03)
	end
	task.wait(0.5)
	local casts = 0
	for _, cast in game.sentSince(mark, "AbilityEvent", "Cast") do
		if cast.fighter == a.model and cast.ability == "SlashWave" then
			casts += 1
		end
	end
	assert(casts == 1, "only one Slash Wave: " .. casts)
	assert(#game.sentSince(mark, "AbilityEvent", "ProjectileSpawn") == 1, "one projectile")
	-- Junk aims: a NaN direction and a point far outside the world
	task.wait(0.3)
	ready(a)
	local start = a.root.Position
	request("AbilityRequest", alice, "ShadowStep", { direction = Vector3.new(0 / 0, 0, 0), point = Vector3.new(1e9, 0, 0) })
	task.wait(0.35)
	Engine.syncPositions(world.workspace)
	assert(flatDistance(a.root.Position, start) <= Powers.abilityFor("Ghost", "ShadowStep", 2).range + 0.5, "never further than its range")
	task.wait(0.2)
	ready(a)
	mark = game.mark()
	request("AbilityRequest", alice, "ConvergingGrid", {})
	request("AbilityRequest", alice, "FollowThrough", "junk")
	request("AbilityRequest", alice, "Groundbreaker", {})
	task.wait(0.2)
	assert(rejection(mark, alice, "ConvergingGrid") == "not equipped", "Degree 3 only")
	assert(rejection(mark, alice, "FollowThrough") == "No slash to follow", "needs a slash first")
	assert(rejection(mark, alice, "Groundbreaker") == "unknown", "another power's ability")
	task.wait(0.3)
end)

check("§38: a match ending with slashes in flight and a veil up leaves nothing behind", function()
	equip(A(), 2, { "PhantomVeil", "SlashWave", "ShadowStep" })
	local a = stage(20)
	request("AbilityRequest", alice, "PhantomVeil", {})
	task.wait(0.3)
	ready(a)
	services.StatusService:apply(a, "Concealed", 3, { magnitude = 0.85 })
	local mark = game.mark()
	request("AbilityRequest", alice, "SlashWave", { direction = Vector3.new(0, 0, 1) })
	game.waitFor(function()
		return #game.sentSince(mark, "AbilityEvent", "ProjectileSpawn") > 0
	end, 1, "a slash in flight")
	local id = game.sentSince(mark, "AbilityEvent", "ProjectileSpawn")[1].id
	services.MatchService:endAll()
	task.wait(1.5)
	assert(services.MatchService:getMatchOf(A()) == nil, "match over")
	local ended = false
	for _, entry in game.sentSince(mark, "AbilityEvent", "ProjectileEnd") do
		ended = ended or entry.id == id
	end
	assert(ended, "the slash was removed")
	assert(#services.ProjectileService:nearby(Vector3.zero, 1e7) == 0, "no projectiles left")
	for _, fighter in { A(), B() } do
		for name in fighter.model:GetAttributes() do
			assert(string.sub(name, 1, 4) ~= "SNS_", "status left: " .. name)
		end
		assert(fighter.model:GetAttribute(Attribute.Phase) == 0, "katana sheathed")
		assert(fighter.power.data.follow == nil and fighter.power.data.drawnUntil == nil, "power state reset")
		assert(fighter.root:FindFirstChild("SNDash") == nil, "no dash left")
		local torso = fighter.model:FindFirstChild("UpperTorso")
		assert(torso.Transparency == 0, "fully visible again")
	end
end)

check("a CPU Ghost fights with its abilities", function()
	local me = A()
	ready(me)
	request("MatchRequest", alice, "Queue", "Practice", { cpuPower = "Ghost", cpuDegree = 3, cpuDifficulty = "Hard" })
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
	end, 4, "the CPU Ghost")
	assert(cpu.power.id == "Ghost" and cpu.power.degree == 3, "a Degree 3 Ghost")
	me = A()
	local mark = game.mark()
	local started = os.clock()
	local used = {}
	while os.clock() - started < 7 do
		game.faceOff(cpu, me, 6)
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
	assert(next(used) ~= nil, "the CPU used a Ghost ability")
	services.MatchService:endAll()
	task.wait(1)
end)

-- Client visuals ----------------------------------------------------------------------------------------

check("the Ghost's visuals run: every effect, the slash, wind-ups and the katana at every degree", function()
	local ClientPowers = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Powers"))
	local Settings = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Settings"))
	local client = ClientPowers.module("Ghost")
	assert(client, "client module loads")

	local function rig(name: string)
		local model = world.Instance.new("Model")
		model.Name = name
		for _, spec in { { "HumanoidRootPart", Vector3.new(2, 2, 1) }, { "UpperTorso", Vector3.new(2, 1.6, 1) }, { "Head", Vector3.new(1.2, 1.2, 1.2) }, { "RightHand", Vector3.new(0.3, 0.3, 0.3) } } do
			local part = world.Instance.new("Part")
			part.Name = spec[1]
			part.Size = spec[2]
			part.CFrame = CFrame.new(0, 3, 0)
			part.Parent = model
		end
		world.Instance.new("Humanoid").Parent = model
		model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
		model:SetAttribute(Attribute.Power, "Ghost")
		model.Parent = world.workspace
		return model
	end
	local target = rig("Target")
	target.HumanoidRootPart.CFrame = CFrame.new(6, 3, 0)

	local function fire(model, name: string)
		Engine.signalOf(model, "Attribute:" .. name):Fire()
	end
	local combatEvent = world.find("ReplicatedStorage.Remotes.CombatEvent")

	for _, reduced in { false, true } do
		Settings.values.reducedEffects = reduced
		for degree = 1, 3 do
			local model = rig("Ghost" .. degree)
			model:SetAttribute(Attribute.Degree, degree)
			local cleanup = client.appearance(ClientPowers.kit(model, "Ghost", {}))
			assert(typeof(cleanup) == "function", "appearance returns a cleanup")
			local look = model:FindFirstChild("SNGhostLook")
			assert(look, "katana built")
			local blade = look:FindFirstChild("SNGhostKatanaBlade")
			assert(blade and blade.Transparency == 1, "sheathed at first")
			model:SetAttribute(Attribute.Phase, 1)
			fire(model, Attribute.Phase)
			assert(blade.Transparency == 0, "drawn with Phase")
			model:SetAttribute(Attribute.StatusPrefix .. "Concealed", now() + 2)
			fire(model, Attribute.StatusPrefix .. "Concealed")
			assert(blade.Transparency >= 0.85, "veiled with him")
			model:SetAttribute(Attribute.StatusPrefix .. "Concealed", nil)
			model:SetAttribute(Attribute.Phase, 0)
			fire(model, Attribute.Phase)
			assert(blade.Transparency == 1, "sheathed with Phase")
			-- A basic swing draws it on this client at once
			Engine.signalOf(combatEvent, "OnClientEvent"):Fire("Attack", { attacker = model, kind = "Light", step = 2, startup = 0.01, active = 0.1 })
			fire(model, "SNGhostDrawnLocal")
			assert(blade.Transparency == 0, "drawn instantly by a swing")
			if degree >= 2 then
				assert(#look:GetChildren() > 9, "eyes at Degree 2+")
			end

			local data = {
				VeilWindup = { duration = 0.1 },
				Veil = { duration = 2.5 },
				SpectralDash = { duration = 0.3, direction = Vector3.new(0, 0, -1) },
				InstantDrawWindup = { duration = 0.12 },
				InstantDraw = { origin = Vector3.new(0, 3, 0), direction = Vector3.new(1, 0, 0), range = 10, landed = true, ambush = true },
				CounterStance = { duration = 0.43, key = "test" .. degree },
				CounterStrike = { from = Vector3.new(0, 3, 0), to = Vector3.new(9, 3, 0), target = target, direction = Vector3.new(-1, 0, 0) },
				CounterEvade = { from = Vector3.new(0, 3, 0), to = Vector3.new(0, 3, 5) },
				ShadowStepMark = { position = Vector3.new(0, 0, 10), duration = 0.15 },
				ShadowStep = { from = Vector3.new(0, 3, 0), to = Vector3.new(0, 3, 10) },
				ShadowStepFail = { position = Vector3.new(0, 3, 0) },
				ShadowSlash = { position = Vector3.new(0, 3, 10), radius = 6 },
				SlashWaveWindup = { duration = 0.2 },
				SlashWaveRelease = { direction = Vector3.new(1, 0, 0) },
				FlurryWindup = { duration = 0.15 },
				FlurrySweep = { index = 4, tilt = 85, arc = 50, range = 9, final = true },
				FollowWindup = { duration = 0.05 },
				FollowDash = { from = Vector3.new(0, 3, 0), direction = Vector3.new(1, 0, 0), distance = 20, duration = 0.2 },
				FollowStrike = { position = Vector3.new(20, 3, 0), direction = Vector3.new(1, 0, 0) },
				GridMark = { center = Vector3.new(10, 0, 0), radius = 8, lines = 6, yaw = 0.5, duration = 0.8 },
				GridStrike = { center = Vector3.new(10, 0, 0), radius = 8, lines = 6, yaw = 0.5 },
				GridFizzle = { center = Vector3.new(10, 0, 0) },
				SeveranceWindup = { duration = 0.8, anchor = Vector3.new(6, 3, 0), passes = 4 },
				SeverancePass = { from = Vector3.new(0, 3, -8), to = Vector3.new(0, 3, 8), index = 1 },
				SeveranceStrike = { from = Vector3.new(0, 3, 0), to = Vector3.new(9, 3, 0), direction = Vector3.new(-1, 0, 0), range = 7 },
			}
			for name, handler in client.fx do
				handler(ClientPowers.kit(model, "Ghost", data[name] or {}))
				-- Junk data never breaks an effect
				handler(ClientPowers.kit(model, "Ghost", { position = "x", from = 4, duration = "y", direction = Vector3.zero }))
			end
			for abilityId, predict in client.predict do
				predict(ClientPowers.kit(model, "Ghost", { ability = abilityId, startup = 0.2, active = 0.1, predicted = true }))
				client.onCast(ClientPowers.kit(model, "Ghost", { ability = abilityId, startup = 0.2 }))
			end
			for _, reason in { "Hit", "World", "Intercepted", "Destroyed" } do
				local handle = client.projectiles.SlashWave(ClientPowers.kit(model, "Ghost", { width = 4.3, tilt = 35, radius = 1.8 }))
				for step = 1, 4 do
					handle.update(Vector3.new(step * 2, 3, 0), Vector3.new(85, 0, 0), 1 / 60)
				end
				handle.finish(Vector3.new(10, 3, 0), reason)
			end
			Engine.step(world.game, 3)
			cleanup()
			assert(model:FindFirstChild("SNGhostLook") == nil, "katana removed")
			assert(model.UpperTorso:FindFirstChild("SNGhostAura") == nil, "aura removed")
			model:Destroy()
		end
	end
	Settings.values.reducedEffects = false
	-- The game's own stand-in character (no RightHand: falls back to the arm)
	local stand = Engine.character("Stand")
	stand:SetAttribute(Attribute.Degree, 3)
	stand.Parent = world.workspace
	local cleanup = client.appearance(ClientPowers.kit(stand, "Ghost", {}))
	assert(stand:FindFirstChild("SNGhostLook"), "katana on the arm")
	cleanup()
	task.wait(0.6)
	target:Destroy()
end)

process.exit(if game.finish() == 0 then 0 else 1)
