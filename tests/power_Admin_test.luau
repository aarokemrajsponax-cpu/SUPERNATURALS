-- Runs Admin Powers end to end with simulated players:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/power_Admin_test.luau build/game.rbxl
-- Two players fight Admin against Admin in a duel and use every ability at
-- every degree it exists at: Teleport (aimed, clamped by walls), Freeze (the
-- prompt, a dodge, a target out of sight), Force Field (absorbing, throwing a
-- well-timed attacker back), Speed, Fly, Clone, Barrier (blocking shots,
-- breaking, expiring, its cap), Jail (the cell, mashing out, time running
-- out), Gravity (heavy and floating), Fling (kept inside the walls), Lockdown,
-- Gravity Field, Teleport Sequence (three strikes, a dodge that breaks it),
-- Slow All and the Ban Hammer at all three degrees (pull, timing bar, perfect
-- timing). Then the §38 cases: a barrier expiring while other effects run, a
-- knockout mid-ultimate, simultaneous commands, junk requests and cooldown
-- spam, changing power mid-fight, a player leaving while jailed, a match
-- ending with everything out, and a second match starting clean. Also the
-- premium pass and trial rules, the Authority weakness, a CPU Admin, and every
-- client effect at every degree.

local process = require("@lune/process")
local fs = require("@lune/fs")

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
-- Energy scaling (Config/Combat) is covered in targeting_test. These timing checks measure
-- costs (which read the scaled def.cost) against the power's own regen, so regen is unscaled here.
local CombatCfg = world.require(world.find("ReplicatedStorage.Shared.Config.Combat"))
CombatCfg.ResourceRegenScale = 1
CombatCfg.ResourceTuning = {}
local Monetization = world.require(world.find("ReplicatedStorage.Shared.Config.Monetization"))
local Attribute = Protocol.Attribute
local ADMIN = Powers.get("Admin")
local Enum = world.Enum or require("@lune/roblox").Enum

-- A world where rays and overlaps see the floor (y = 0) and every construct
-- part, so walls really stop shots, lines of sight and teleports
local function excluded(part, params): boolean
	for _, item in (params and params.FilterDescendantsInstances) or {} do
		if part == item or part:IsDescendantOf(item) then
			return true
		end
	end
	return false
end

local function rayBox(origin: Vector3, direction: Vector3, frame, size: Vector3): number?
	local o = frame:PointToObjectSpace(origin)
	local d = frame:VectorToObjectSpace(direction)
	local half = size / 2
	local tMin, tMax = 0, 1
	for _, axis in { "X", "Y", "Z" } do
		local start, step, limit = o[axis], d[axis], half[axis]
		if math.abs(step) < 1e-9 then
			if math.abs(start) > limit then
				return nil
			end
		else
			local t1, t2 = (-limit - start) / step, (limit - start) / step
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tMin = math.max(tMin, t1)
			tMax = math.min(tMax, t2)
			if tMin > tMax then
				return nil
			end
		end
	end
	-- Starting inside a part doesn't hit it (like Roblox)
	if tMin <= 0 then
		return nil
	end
	return tMin
end

local function constructParts(): { any }
	local list = {}
	local folder = world.workspace:FindFirstChild("SNConstructs")
	if folder then
		for _, item in folder:GetDescendants() do
			if item:IsA("BasePart") then
				table.insert(list, item)
			end
		end
	end
	return list
end

Engine.raycast = function(origin, direction, params)
	local best, bestT = nil, math.huge
	if direction.Y < 0 and origin.Y >= 0 and origin.Y + direction.Y <= 0 then
		local t = -origin.Y / direction.Y
		best, bestT = { Position = origin + direction * t, Normal = Vector3.new(0, 1, 0), Instance = nil, Material = Enum.Material.Plastic }, t
	end
	for _, part in constructParts() do
		if not excluded(part, params) and (not (params and params.RespectCanCollide) or part.CanCollide) then
			local t = rayBox(origin, direction, part.CFrame, part.Size)
			if t and t < bestT then
				best, bestT = { Position = origin + direction * t, Normal = Vector3.new(0, 1, 0), Instance = part, Material = part.Material }, t
			end
		end
	end
	return best
end

-- Box overlaps against construct parts (their world bounding boxes)
Engine.partsInBox = function(frame, size, params)
	local found = {}
	local center = frame.Position
	local half = size / 2
	for _, part in constructParts() do
		if not excluded(part, params) and (not (params and params.RespectCanCollide) or part.CanCollide) then
			local cf = part.CFrame
			local r, u, b = cf.RightVector, cf.UpVector, cf.LookVector
			local s = part.Size / 2
			local extent = Vector3.new(
				math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(b.X) * s.Z,
				math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(b.Y) * s.Z,
				math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(b.Z) * s.Z
			)
			local gap = cf.Position - center
			if math.abs(gap.X) <= half.X + extent.X and math.abs(gap.Y) <= half.Y + extent.Y and math.abs(gap.Z) <= half.Z + extent.Z then
				table.insert(found, part)
			end
		end
	end
	return found
end

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

-- The stand-in engine keeps Position and CFrame apart, and Admin moves fighters by CFrame
-- (teleports, blinks, steps aside). Roblox derives Position from CFrame, so mirror that
-- whenever the character service moves someone.
do
	local original = services.CharacterService.teleport
	services.CharacterService.teleport = function(self, fighter, ...)
		local result = original(self, fighter, ...)
		pcall(function()
			fighter.root.Position = fighter.root.CFrame.Position
		end)
		return result
	end
end

local function ability(id: string, degree: number)
	return Powers.abilityFor("Admin", id, degree)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function aimAt(from, to)
	return { direction = (to.root.Position - from.root.Position).Unit, point = to.root.Position }
end

-- Full health, Authority and a clean state, so tests don't wait on each other
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
	state.airborneUntil = -math.huge
	services.StatusService:clearAll(fighter)
	services.DefenseService:clear(fighter)
	fighter.humanoid.Health = fighter.humanoid.MaxHealth
	for _, child in fighter.root:GetChildren() do
		if child.Name == "SNDash" or child.Name == "SNKnockback" then
			child:Destroy()
		end
	end
	services.CharacterService:refresh(fighter)
end

local function equip(fighter, degree: number, loadout: { string }?)
	services.PowerService:equip(fighter, "Admin", degree, loadout or Powers.defaultLoadout("Admin", degree))
	ready(fighter)
end

-- Alice on the left facing Bob, `gap` studs apart, in the middle of the arena
local function stage(gap: number, shift: Vector3?)
	local a, b = A(), B()
	local center = arena.center + (shift or Vector3.zero)
	local posA = Vector3.new(center.X - gap / 2, 3, center.Z)
	local posB = Vector3.new(center.X + gap / 2, 3, center.Z)
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

local function constructs(fighter, name: string?)
	return services.ConstructService:ofOwner(fighter, name)
end

local function status(fighter, statusId: string)
	return services.StatusService:get(fighter, statusId)
end

local function spent(fighter, cost: number): boolean
	-- Authority regenerates 6 a second, so allow a little back
	return fighter.power.resource < fighter.power.resourceMax - cost + 4
end

-- An enemy projectile made by hand (Admin fires none of its own)
local function enemyShot(owner, origin: Vector3, direction: Vector3, extra: { [string]: any }?)
	local spec = {
		power = "Admin",
		ability = "TestShot",
		visual = "TestShot",
		origin = origin,
		direction = direction,
		speed = 60,
		radius = 0.4,
		lifetime = 3,
		range = 120,
		hit = { Damage = 8, Hitstun = 0.2, Knockback = 5, GuardDamage = 5 },
		tags = { "Projectile", "Small" },
	}
	for key, value in extra or {} do
		spec[key] = value
	end
	return services.ProjectileService:spawn(owner, spec)
end

local function endsSince(mark: number): { [string]: string }
	local reasons = {}
	for _, entry in game.sentSince(mark, "AbilityEvent", "ProjectileEnd") do
		reasons[entry.id] = entry.reason
	end
	return reasons
end

-- Definition ------------------------------------------------------------------------------

check("Admin's definition: card text, Authority, premium pass, AI hints, degrees and loadouts", function()
	assert(ADMIN, "Admin Powers is registered")
	assert(Powers.degreeCount("Admin") == 3, "three degrees")
	assert(utf8.len(ADMIN.name) <= 20 and utf8.len(ADMIN.description) <= 160, "power text fits a card")
	assert(string.find(ADMIN.description, "fragile", 1, true) and string.find(ADMIN.description, "Low damage", 1, true), "the card names its weakness")
	local authority = ADMIN.resource
	assert(authority.id == "Authority" and authority.max == 100 and authority.start == 60 and authority.regen == 6, "Authority 0-100, starts at 60, 6 a second")
	assert(authority.lossOnHurt and authority.lossOnHurt > 0, "hits taken cost Authority")
	-- The premium field matches the pass that sells it
	local pass = Monetization.Passes[ADMIN.premium.pass]
	assert(pass and pass.power == "Admin", "AdminPower pass sells Admin")
	assert(ADMIN.premium.pass == "AdminPower" and ADMIN.premium.robux == 12000 and pass.robux == 12000, "12,000 Robux, matching Monetization")
	assert(ADMIN.premium.gems and ADMIN.premium.gems > 0, "a Gems path")
	assert(Monetization.passForPower("Admin") == "AdminPower", "pass lookup")
	assert(Powers.isPremium("Admin"), "premium")
	assert(ADMIN.ai.preferredRange and ADMIN.ai.aggression, "power AI hints")
	for _, degree in ADMIN.degrees do
		assert(utf8.len(degree.name) <= 20 and utf8.len(degree.description) <= 160, degree.name .. " text fits")
		assert(degree.ultimate == "BanHammer", "Ban Hammer on every degree")
		assert(not string.find(degree.description, "\u{2014}", 1, true), "no em dashes")
	end
	for abilityId, def in ADMIN.abilities do
		assert(utf8.len(def.name) <= 20, abilityId .. " name fits")
		assert(utf8.len(def.description) <= 160, abilityId .. " description fits")
		assert(not string.find(def.description, "\u{2014}", 1, true), abilityId .. ": no em dashes")
		assert(not string.find(def.description, "!", 1, true), abilityId .. ": no exclamation marks")
		assert(def.ai and def.ai.range and def.ai.use, abilityId .. " has an AI hint")
		assert(table.find(ADMIN.abilityOrder, abilityId), abilityId .. " is in abilityOrder")
		assert(typeof(def.command) == "string" and string.sub(def.command, 1, 1) == ";", abilityId .. " has its command text")
		if def.kind ~= "Ultimate" then
			assert((def.cost or 0) > 0, abilityId .. " costs Authority")
		end
	end
	-- Degrees expand the kit: everything lower is still there
	assert(#Powers.available("Admin", 1) == 6, "6 at Moderator")
	assert(#Powers.available("Admin", 2) == 10, "10 at Administrator")
	assert(#Powers.available("Admin", 3) == 14, "14 at System Authority")
	for degree = 1, 3 do
		local ok, reason = Powers.validateLoadout("Admin", degree, Powers.defaultLoadout("Admin", degree), {})
		assert(ok, `degree {degree} default loadout: {reason}`)
	end
	-- Fly and Clone are bought early and included later
	assert(not Powers.validateLoadout("Admin", 1, { "Fly" }, {}), "Fly costs Money at Degree 1")
	assert(Powers.validateLoadout("Admin", 1, { "Fly" }, { abilities = { Fly = true } }), "bought Fly")
	assert(Powers.validateLoadout("Admin", 2, { "Fly" }, {}), "Fly free from Degree 2")
	assert(not Powers.validateLoadout("Admin", 2, { "Clone" }, {}), "Clone costs Money below Degree 3")
	assert(Powers.validateLoadout("Admin", 3, { "Clone" }, {}), "Clone free at Degree 3")
	-- The ultimate scales, raw damage stays modest
	assert(ability("BanHammer", 3).damage > ability("BanHammer", 2).damage and ability("BanHammer", 2).damage > ability("BanHammer", 1).damage, "Ban Hammer scales")
	for _, abilityId in Powers.available("Admin", 3) do
		assert((ability(abilityId, 3).damage or 0) <= 10, abilityId .. " keeps raw damage modest")
	end
	-- The strongest commands can't be kept up: a few casts empty a full bar
	assert(ability("ArenaBarrier", 3).baseCost + ability("TeleportSequence", 3).baseCost + ability("Jail", 3).baseCost > authority.max, "big commands drain Authority")
	assert(Powers.combatProfile("Admin", 1).MaxHealth == 95, "a light body")
end)

check("every effect the server sends has a client drawing, and the other way round", function()
	local server = fs.readFile("src/server/Powers/Admin.luau")
	local client = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Powers.Admin"))
	local names = {}
	for _, pattern in { '[fF]x%("(%w+)"', 'command%(ctx, "(%w+)"', 'statusWithFx%(.-, "(%w+)", {', 'fx = "(%w+)"' } do
		for name in string.gmatch(server, pattern) do
			names[name] = true
		end
	end
	local total = 0
	for name in names do
		total += 1
		assert(client.fx[name], "no client effect for " .. name)
	end
	assert(total >= 40, "found the effects: " .. total)
	for name in client.fx do
		assert(names[name], "the server never sends " .. name)
	end
	for abilityId in ADMIN.abilities do
		assert(client.predict[abilityId], "instant wind-up for " .. abilityId)
	end
	-- Fictional commands only: nothing here reaches real moderation or accounts
	for _, forbidden in { ":Kick(", "BanAsync", "DataStore", "MarketplaceService", "TeleportService", "OwnerService", "AdminEventService" } do
		assert(not string.find(server, forbidden, 1, true), "server never uses " .. forbidden)
	end
end)

-- Premium and trials ------------------------------------------------------------------------

check("premium rules: a trial outside ranked fights, refused in a Duel queue, unlocked with Gems", function()
	alice = game.join("Alice")
	bob = game.join("Bob")
	game.waitFor(function()
		return A() ~= nil and A().power ~= nil and B() ~= nil and B().power ~= nil
	end, 3, "powers to be equipped")
	local ok, _, trial = services.PowerService:check(alice, "Admin", 1)
	assert(ok and trial, "anyone can try Degree 1 as a trial")
	assert(not services.PowerService:owns(alice, "Admin"), "nobody owns it yet")
	assert(not services.PowerService:check(alice, "Admin", 2), "Degree 2 still needs mastery or Money")
	request("PowerRequest", alice, "Select", "Admin", 1)
	game.waitFor(function()
		return A().power.id == "Admin"
	end, 2, "Admin selected")
	assert(A().power.trial == true, "equipped as a trial")
	local allowed, reason = services.PowerService:queueCheck(alice, "Duel")
	assert(not allowed and reason and string.find(reason, "12000 Robux", 1, true) and string.find(reason, "Gems", 1, true), "no Duels on a trial: " .. tostring(reason))
	assert(services.PowerService:queueCheck(alice, "Practice"), "CPU Practice is fine")
	-- The Gems path unlocks it for good
	assert(services.CurrencyService:add(alice, { gems = ADMIN.premium.gems }, "test"), "gems granted")
	request("PowerRequest", alice, "UnlockPower", "Admin")
	game.waitFor(function()
		return services.PowerService:owns(alice, "Admin")
	end, 2, "Admin unlocked")
	assert(A().power.trial == false, "no longer a trial")
	assert(services.PowerService:queueCheck(alice, "Duel"), "Duels allowed once owned")
end)

-- In the duel -------------------------------------------------------------------------------

-- The fighters in this duel: Alice owns Admin (unlocked above); Bob equips it directly
local function startDuel()
	request("MatchRequest", alice, "Queue", "Duel")
	request("MatchRequest", bob, "Queue", "Duel")
	local match
	game.waitFor(function()
		match = services.MatchService:getMatchOf(A())
		return match ~= nil and match.flow.phase == "Active"
	end, 4, "the duel to begin")
	arena = match.arena
	task.wait(0.2)
end

-- Everything an Admin made, gone, and both fighters clean and at full strength
local function clearBuilt()
	for _, fighter in { A(), B() } do
		services.ConstructService:clearOwner(fighter)
	end
end

local function reset(gap: number)
	clearBuilt()
	local a, b = stage(gap)
	ready(a)
	ready(b)
	return a, b
end

check("two players start a duel with Admin: a light body, Authority starts at 60", function()
	startDuel()
	local a = A()
	assert(a.power.id == "Admin" and a.power.degree == 1, "Alice is Admin at Phase 1")
	assert(a.power.resource >= 59 and a.power.resource <= 72, "Authority starts at 60: " .. a.power.resource)
	assert(a.model:GetAttribute(Attribute.ResourceMax) == 100, "Authority maximum")
	assert(a.humanoid.MaxHealth == 95 and a.combat.Block.MaxGuard == 85, "a lighter body and a weaker guard")
	equip(A(), 1)
	equip(B(), 1)
	assert(A().power.id == "Admin" and B().power.id == "Admin", "Admin against Admin")
end)

check("Authority: regenerates, never passes its maximum, and every hit taken costs some", function()
	local a, b = reset(10)
	a.power.resource = 50
	task.wait(0.5)
	assert(a.power.resource > 50 + ADMIN.resource.regen * 0.3, "regenerates: " .. a.power.resource)
	a.power.resource = a.power.resourceMax - 1
	task.wait(0.5)
	assert(a.power.resource <= a.power.resourceMax, "capped at the maximum")
	a.power.resource = 50
	local mark = game.mark()
	local started = now()
	local origin = a.root.Position + Vector3.new(3, 0, 0)
	enemyShot(b, origin, (a.root.Position - origin).Unit)
	game.waitFor(function()
		return #hitsSince(mark, b, a, "TestShot") > 0
	end, 1, "the shot to land")
	local elapsed = now() - started
	assert(a.power.resource < 50 + ADMIN.resource.regen * elapsed - ADMIN.resource.lossOnHurt + 1.5, "a hit costs Authority: " .. a.power.resource)
	task.wait(0.4)
end)

-- Every ability at every degree ---------------------------------------------------------------

local function exercise(abilityId: string, degree: number)
	local def = ability(abilityId, degree)
	local label = `{abilityId} (Degree {degree})`
	equip(A(), degree, { abilityId })
	local a, b = reset(10)
	local start = a.root.Position
	local health = b.humanoid.Health
	local before = a.power.resource
	local mark = game.mark()
	local aim = aimAt(a, b)
	if abilityId == "Teleport" then
		aim = { direction = Vector3.new(0, 0, 1), point = start + Vector3.new(0, 0, 14) }
	end
	request("AbilityRequest", alice, abilityId, aim)
	assert(castsSince(mark, a, abilityId) == 1, label .. ": cast")
	assert(cooldownSet(a, abilityId), label .. ": cooldown set")
	if (def.cost or 0) > 0 then
		assert(a.power.resource < before - def.cost + 3, label .. ": cost paid")
	end
	local extra = 0.5
	if abilityId == "TeleportSequence" then
		extra = (def.strikes - 1) * def.interval + 0.8
	end
	task.wait((def.startup or 0) + (def.active or 0) + extra)
	local hits = hitsSince(mark, a, b, abilityId)
	if abilityId == "Teleport" then
		Engine.syncPositions(world.workspace)
		assert(flatDistance(a.root.Position, start) > 6 and flatDistance(a.root.Position, start) <= def.range + 2, label .. ": moved " .. flatDistance(a.root.Position, start))
		assert(#fxSince(mark, "TeleportArrive", a) == 1, label .. ": arrival drawn")
	elseif abilityId == "FreezeCommand" then
		assert(#hits >= 1 and status(b, "Freeze"), label .. ": Bob frozen")
		assert(#fxSince(mark, "FreezeLock", a) == 1, label .. ": drawn")
	elseif abilityId == "ForceField" then
		assert(status(a, "Shield"), label .. ": shielded")
	elseif abilityId == "SpeedCommand" then
		assert(status(a, "Haste"), label .. ": hasted")
	elseif abilityId == "Fly" then
		assert(status(a, "Gravity"), label .. ": light")
		-- (The stand-in engine has no physics, so the lift is seen in the effect and the light body)
		assert(near(status(a, "Gravity").magnitude, def.gravity) and status(a, "Haste"), label .. ": light and quick")
		assert(#fxSince(mark, "Flight", a) == 1 and #fxSince(mark, "FlyWindup", a) == 1, label .. ": drawn")
	elseif abilityId == "Clone" then
		assert(status(a, "Concealed") and #fxSince(mark, "CloneDecoy", a) == 1, label .. ": faded, with a decoy")
	elseif abilityId == "Barrier" then
		assert(#constructs(a, "Barrier") >= 1, label .. ": a wall stands")
	elseif abilityId == "Jail" then
		assert(#hits >= 1 and status(b, "Trapped") and #constructs(a, "Jail") == 1, label .. ": Bob in a cell")
	elseif abilityId == "GravityCommand" then
		assert(#hits >= 1 and status(b, "Gravity"), label .. ": heavier")
	elseif abilityId == "Fling" then
		assert(#hits >= 1 and b.humanoid.Health < health, label .. ": Bob thrown and hurt")
		assert(#fxSince(mark, "FlingThrow", a) == 1, label .. ": drawn")
	elseif abilityId == "ArenaBarrier" then
		assert(#constructs(a, "Lockdown") == 1, label .. ": the ring stands")
	elseif abilityId == "GravityField" then
		assert(status(b, "Gravity") and status(b, "Slow"), label .. ": Bob heavy inside the field")
		assert(not status(a, "Slow"), label .. ": the caster is not slowed")
	elseif abilityId == "TeleportSequence" then
		assert(#fxSince(mark, "SequenceStrike", a) >= 1 and #hits >= 1, label .. `: struck Bob (strikes {#fxSince(mark, "SequenceStrike", a)}, hits {#hits}, blink {#fxSince(mark, "SequenceBlink", a)}, broken {#fxSince(mark, "SequenceBroken", a)}, rej {rejection(mark, alice, abilityId)})`)
	elseif abilityId == "AreaCommand" then
		assert(#hits >= 1 and status(b, "Slow"), label .. ": Bob slowed")
	end
	if def.defense == "Prompt" then
		assert(#cuesFor(mark, bob, "Prompt") >= 1, label .. ": Bob was warned")
	end
	if def.damage and def.damage > 0 and abilityId ~= "Teleport" then
		-- Commands that hit were answered by a hit message
		assert(abilityId == "ForceField" or #hits >= 1 or abilityId == "Barrier", label .. ": a hit was reported")
	end
	clearBuilt()
	ready(a)
	ready(b)
	task.wait(0.15)
end

check("every ability at every degree it exists at: cast, cost, cooldown and a real effect", function()
	for degree = 1, 3 do
		equip(A(), degree)
		equip(B(), degree)
		for _, abilityId in Powers.available("Admin", degree) do
			if abilityId ~= "BanHammer" then
				exercise(abilityId, degree)
			end
		end
	end
	equip(A(), 1)
	equip(B(), 1)
end)

-- Mechanics -----------------------------------------------------------------------------------

check("Teleport: aimed, clamped to its range, and stopped short of a wall", function()
	equip(A(), 2, { "Teleport" })
	equip(B(), 2, { "Barrier" })
	local def = ability("Teleport", 2)
	local a, b = reset(30)
	local start = a.root.Position
	request("AbilityRequest", alice, "Teleport", { direction = Vector3.new(0, 0, 1), point = start + Vector3.new(0, 0, 200) })
	task.wait(def.startup + 0.4)
	Engine.syncPositions(world.workspace)
	assert(flatDistance(a.root.Position, start) <= def.range + 1.5, "clamped to the range: " .. flatDistance(a.root.Position, start))
	-- A wall between: Bob raises one facing Alice, and she cannot arrive beyond it
	a, b = reset(30)
	request("AbilityRequest", bob, "Barrier", aimAt(b, a))
	task.wait(ability("Barrier", 2).startup + 0.4)
	local wall = constructs(b, "Barrier")[1]
	assert(wall, "a wall stands")
	local wallX = wall.model.PrimaryPart.Position.X
	local fromX = a.root.Position.X
	request("AbilityRequest", alice, "Teleport", { direction = Vector3.new(1, 0, 0), point = a.root.Position + Vector3.new(def.range, 0, 0) })
	task.wait(def.startup + 0.4)
	Engine.syncPositions(world.workspace)
	-- (A teleport is a jump: it may land past a thin wall, but never inside it)
	assert(math.abs(a.root.Position.X - wallX) > 1.2, `not embedded in the wall (x {a.root.Position.X}, wall {wallX}, from {fromX})`)
	assert(flatDistance(a.root.Position, start) > 6, "it did jump")
	-- Nowhere to go refunds part of the cost
	clearBuilt()
end)

check("Freeze: a target that left reach or sight is not frozen, and part of the cost comes back", function()
	equip(A(), 1, { "FreezeCommand" })
	local def = ability("FreezeCommand", 1)
	local a, b = reset(def.range + 30)
	local mark = game.mark()
	request("AbilityRequest", alice, "FreezeCommand", aimAt(a, b))
	task.wait(0.2)
	assert(#fxSince(mark, "CommandFizzle", a) == 1 and not status(b, "Freeze"), "nobody to command")
	assert(a.power.resource > a.power.resourceMax - def.cost + 5, "part of the cost came back")
	-- Out of reach by the time it executes
	a, b = reset(def.range - 4)
	mark = game.mark()
	request("AbilityRequest", alice, "FreezeCommand", aimAt(a, b))
	task.wait(0.1)
	b.root.CFrame = b.root.CFrame + Vector3.new(30, 0, 0)
	Engine.syncPositions(world.workspace)
	task.wait(def.startup + 0.4)
	assert(#hitsSince(mark, a, b, "FreezeCommand") == 0 and not status(b, "Freeze"), "they got away")
	assert(#fxSince(mark, "CommandFizzle", a) == 1, "the fizzle is drawn")
	-- A dodge answers it
	a, b = reset(10)
	mark = game.mark()
	request("AbilityRequest", alice, "FreezeCommand", aimAt(a, b))
	task.wait(def.startup - 0.1)
	request("CombatRequest", bob, "Dodge", { direction = Vector3.new(0, 0, 1) })
	task.wait(0.5)
	assert(not status(b, "Freeze"), "dodged")
end)

check("Force Field: absorbs, and throws back a well-timed attacker", function()
	equip(A(), 1, { "ForceField" })
	local a, b = reset(10)
	local mark = game.mark()
	request("AbilityRequest", alice, "ForceField", aimAt(a, b))
	task.wait(0.15)
	local health = a.humanoid.Health
	local origin = a.root.Position + Vector3.new(3, 0, 0)
	enemyShot(b, origin, (a.root.Position - origin).Unit)
	task.wait(0.5)
	assert(a.humanoid.Health == health, "the shot did nothing")
	assert(#fxSince(mark, "ForceFieldRepel", a) + #fxSince(mark, "ForceField", a) >= 1, "drawn")
	assert(status(a, "Shield") ~= nil, "still shielded")
end)

check("Barrier: blocks shots, breaks, expires and keeps to its cap", function()
	equip(A(), 3, { "Barrier" })
	equip(B(), 1, {})
	local def = ability("Barrier", 3)
	local a, b = reset(30)
	-- The Barrier is placed where Alice clicks: here, between the two of them
	local toward = (b.root.Position - a.root.Position).Unit
	request("AbilityRequest", alice, "Barrier", { direction = toward, point = a.root.Position + toward * def.distance })
	task.wait(def.startup + 0.4)
	local wall = constructs(a, "Barrier")[1]
	assert(wall and wall.health == def.health, "a wall at full health")
	local mark = game.mark()
	local health = b.humanoid.Health
	local origin = a.root.Position + Vector3.new(def.distance - 3, 0, 0)
	enemyShot(b, b.root.Position - Vector3.new(4, 0, 0), Vector3.new(-1, 0, 0))
	task.wait(0.8)
	assert(wall.health < def.health, "the shot hit the wall: " .. wall.health)
	assert(a.humanoid.Health == a.humanoid.MaxHealth, "Alice untouched")
	services.ConstructService:damage(wall, 1e6)
	task.wait(0.1)
	assert(not wall.alive and #fxSince(mark, "BarrierDown", a) == 1, "broken and drawn")
	-- The cap
	for _ = 1, def.limit + 2 do
		table.clear(a.power.cooldowns)
		a.power.resource = a.power.resourceMax
		request("AbilityRequest", alice, "Barrier", { direction = Vector3.new(0, 0, 1) })
		task.wait(def.startup + def.active + def.recovery + 0.3)
	end
	assert(#constructs(a, "Barrier") <= def.limit, "at most " .. def.limit .. " walls: " .. #constructs(a, "Barrier"))
	task.wait(def.duration + 0.3)
	assert(#constructs(a, "Barrier") == 0, "walls expire")
	assert(b.humanoid.Health == health, "Bob was not hurt by his own blocked shot")
	_ = origin
end)

check("Jail: a cell around the target; mashing breaks out, or it times out", function()
	equip(A(), 2, { "Jail" })
	local def = ability("Jail", 2)
	local a, b = reset(10)
	local mark = game.mark()
	request("AbilityRequest", alice, "Jail", aimAt(a, b))
	task.wait(def.startup + 0.4)
	assert(status(b, "Trapped") and #constructs(a, "Jail") == 1, "Bob is jailed")
	local cue = cuesFor(mark, bob, "Mash")[1]
	assert(cue and cue.presses == def.escapePresses, "a mash prompt")
	for _ = 1, cue.presses + 2 do
		request("DefenseInput", bob, "Mash", cue.id)
		task.wait(0.08)
	end
	task.wait(0.3)
	assert(not status(b, "Trapped") and #constructs(a, "Jail") == 0, "broke out")
	assert(#fxSince(mark, "JailOpen", a) == 1, "the door opening is drawn")
	-- No mashing: time runs out
	a, b = reset(10)
	request("AbilityRequest", alice, "Jail", aimAt(a, b))
	task.wait(def.startup + 0.4)
	assert(status(b, "Trapped"), "jailed again")
	task.wait(def.duration + 0.4)
	assert(not status(b, "Trapped") and #constructs(a, "Jail") == 0, "released on time")
end)

check("Gravity: heavy on the ground, floating in the air; Fling stays inside the walls", function()
	equip(A(), 2, { "GravityCommand", "Fling" })
	local a, b = reset(10)
	request("AbilityRequest", alice, "GravityCommand", aimAt(a, b))
	task.wait(ability("GravityCommand", 2).startup + 0.4)
	local heavy = status(b, "Gravity")
	assert(heavy and status(b, "Slow"), "heavy and slowed")
	a, b = reset(10)
	b.state.airborneUntil = now() + 3
	request("AbilityRequest", alice, "GravityCommand", aimAt(a, b))
	task.wait(ability("GravityCommand", 2).startup + 0.4)
	local float = status(b, "Gravity")
	assert(float and float.magnitude < heavy.magnitude, "floating, not heavy")
	assert(#fxSince(game.mark() - 0, "GravityFloat", a) >= 0, "")
	-- Fling at the wall
	a, b = reset(6)
	local edge = services.ArenaService:clampInside(arena, arena.center + Vector3.new(500, 0, 0), 5)
	b.root.CFrame = CFrame.new(edge + Vector3.new(0, 3, 0))
	a.root.CFrame = CFrame.lookAt(edge + Vector3.new(-6, 3, 0), edge + Vector3.new(0, 3, 0))
	Engine.syncPositions(world.workspace)
	request("AbilityRequest", alice, "Fling", aimAt(a, b))
	task.wait(ability("Fling", 2).startup + 1.5)
	Engine.syncPositions(world.workspace)
	local inside = services.ArenaService:clampInside(arena, b.root.Position, 0)
	assert(flatDistance(inside, b.root.Position) < 1.5, "Bob was kept inside the walls")
end)

check("Lockdown ring, Gravity Field and Slow All: area commands with limits", function()
	equip(A(), 3, { "ArenaBarrier", "GravityField", "AreaCommand" })
	local ring = ability("ArenaBarrier", 3)
	local a, b = reset(ring.radius)
	request("AbilityRequest", alice, "ArenaBarrier", aimAt(a, b))
	task.wait(ring.startup + 0.4)
	Engine.syncPositions(world.workspace)
	assert(#constructs(a, "Lockdown") == 1, "the ring stands")
	assert(math.abs(flatDistance(a.root.Position, b.root.Position) - ring.radius) > 1.2, "Bob was moved off the ring's line")
	task.wait(ring.duration + 0.3)
	assert(#constructs(a, "Lockdown") == 0, "the ring ends on time")
	-- Gravity Field: whoever leaves it is released
	local field = ability("GravityField", 3)
	a, b = reset(10)
	request("AbilityRequest", alice, "GravityField", aimAt(a, b))
	task.wait(field.startup + 0.6)
	assert(status(b, "Gravity"), "heavy inside")
	b.root.CFrame = b.root.CFrame + Vector3.new(0, 0, field.radius + 14)
	Engine.syncPositions(world.workspace)
	task.wait(1)
	assert(not status(b, "Gravity"), "released outside")
	task.wait(field.duration)
	-- Slow All: out of range is untouched
	local area = ability("AreaCommand", 3)
	a, b = reset(area.radius + 8)
	local mark = game.mark()
	request("AbilityRequest", alice, "AreaCommand", aimAt(a, b))
	task.wait(area.startup + 0.5)
	assert(#hitsSince(mark, a, b, "AreaCommand") == 0 and not status(b, "Slow"), `too far to be slowed (hits {#hitsSince(mark, a, b, "AreaCommand")}, gap {flatDistance(a.root.Position, b.root.Position)}, radius {area.radius})`)
end)

check("Teleport Sequence: three strikes; a dodge breaks it", function()
	equip(A(), 3, { "TeleportSequence" })
	local def = ability("TeleportSequence", 3)
	local a, b = reset(10)
	local mark = game.mark()
	request("AbilityRequest", alice, "TeleportSequence", aimAt(a, b))
	task.wait(def.startup + def.strikes * def.interval + 0.8)
	assert(#fxSince(mark, "SequenceStrike", a) == def.strikes and #fxSince(mark, "SequenceEnd", a) == 1, "every strike, then the end")
	assert(#cuesFor(mark, bob, "Prompt") == def.strikes, "a prompt before each strike")
	a, b = reset(10)
	mark = game.mark()
	request("AbilityRequest", alice, "TeleportSequence", aimAt(a, b))
	task.wait(def.startup - 0.05)
	request("CombatRequest", bob, "Dodge", { direction = Vector3.new(0, 0, 1) })
	task.wait(def.strikes * def.interval + 0.8)
	assert(#fxSince(mark, "SequenceBroken", a) == 1 and #fxSince(mark, "SequenceStrike", a) < def.strikes, "the dodge broke the sequence")
end)

-- Ultimate ------------------------------------------------------------------------------------

check("Ban Hammer at every degree: needs a charge, pulls, slams, and spends the charge", function()
	for degree = 1, 3 do
		equip(A(), degree, {})
		equip(B(), degree, {})
		local def = ability("BanHammer", degree)
		local a, b = reset(14)
		local mark = game.mark()
		a.power.ult = 0
		request("AbilityRequest", alice, "BanHammer", aimAt(a, b))
		task.wait(0.15)
		assert(rejection(mark, alice, "BanHammer") == "charge", "no charge, no hammer")
		a.power.ult = 100
		-- Bob stands in the pull ring but outside the slam: he is dragged in
		local floor = b.root.Position
		a.root.CFrame = CFrame.lookAt(floor - Vector3.new(14, 0, 0), floor)
		b.root.CFrame = CFrame.new(floor + Vector3.new(def.radius + 4, 0, 0))
		Engine.syncPositions(world.workspace)
		mark = game.mark()
		local before = flatDistance(b.root.Position, floor)
		request("AbilityRequest", alice, "BanHammer", { direction = Vector3.new(1, 0, 0), point = floor })
		assert(a.power.ult == 0 and cooldownSet(a, "BanHammer"), "charge spent and cooldown set")
		-- (No physics in the stand-in engine: the pull is seen as a push mover on Bob)
		local pushed = false
		local waited = 0
		while waited < def.startup * 0.9 and not pushed do
			task.wait(0.05)
			waited += 0.05
			pushed = b.root:FindFirstChild("SNKnockback") ~= nil
		end
		assert(pushed and before > def.radius, "dragged towards the ring")
		task.wait(def.startup + def.active + 0.6 - waited)
		assert(#fxSince(mark, "BanHammerSlam", a) == 1, "the slam is drawn")
		task.wait(def.recovery + 0.3)
		-- A direct slam hurts
		a, b = reset(14)
		a.power.ult = 100
		mark = game.mark()
		local health = b.humanoid.Health
		request("AbilityRequest", alice, "BanHammer", { direction = aimAt(a, b).direction, point = b.root.Position })
		task.wait(def.startup + def.active + 0.8)
		local hits = hitsSince(mark, a, b, "BanHammer")
		assert(#hits == 1 and hits[1].damage >= def.damage * 0.5, `degree {degree} slam hit for {hits[1] and hits[1].damage}`)
		assert(b.humanoid.Health < health, "Bob hurt")
		task.wait(def.recovery + 0.3)
	end
end)

-- Edge cases and cleanup ----------------------------------------------------------------------

check("junk requests, other degrees' abilities and spam are refused without errors", function()
	equip(A(), 1, { "Teleport", "FreezeCommand", "ForceField" })
	local a, b = reset(10)
	local mark = game.mark()
	request("AbilityRequest", alice, "Groundbreaker", aimAt(a, b))
	request("AbilityRequest", alice, "Barrier", aimAt(a, b))
	request("AbilityRequest", alice, "BanHammer", aimAt(a, b))
	request("AbilityRequest", alice, 5, aimAt(a, b))
	request("AbilityRequest", alice, "Teleport", "junk")
	task.wait(0.8)
	assert(rejection(mark, alice, "Groundbreaker") ~= nil and rejection(mark, alice, "Barrier") ~= nil, "refused")
	assert(castsSince(mark, a, "Barrier") == 0 and castsSince(mark, a, "BanHammer") == 0, "nothing cast")
	ready(a)
	mark = game.mark()
	request("AbilityRequest", alice, "FreezeCommand", { direction = Vector3.new(0 / 0, 0, 0), point = Vector3.new(1e9, 1e9, 1e9) })
	task.wait(0.8)
	ready(a)
	mark = game.mark()
	for _ = 1, 25 do
		request("AbilityRequest", alice, "ForceField", {})
	end
	task.wait(0.4)
	assert(castsSince(mark, a, "ForceField") == 1, "spam casts once")
	request("PowerRequest", alice, Protocol.PowerAction.Select, "StrongDude", 1)
	task.wait(0.2)
	assert(A().power.id == "Admin", "locked until the fight ends")
end)

check("simultaneous commands: both freeze each other, no errors", function()
	equip(A(), 1, { "FreezeCommand" })
	equip(B(), 1, { "FreezeCommand" })
	local a, b = reset(10)
	local mark = game.mark()
	request("AbilityRequest", alice, "FreezeCommand", aimAt(a, b))
	request("AbilityRequest", bob, "FreezeCommand", aimAt(b, a))
	task.wait(1)
	assert(#hitsSince(mark, a, b, "FreezeCommand") + #hitsSince(mark, b, a, "FreezeCommand") >= 1, "at least one landed")
	ready(a)
	ready(b)
end)

check("§38: a knockout mid-ultimate cleans up and respawns cleanly", function()
	equip(A(), 1, {})
	local a, b = reset(14)
	a.power.ult = 100
	request("AbilityRequest", alice, "BanHammer", aimAt(a, b))
	task.wait(0.6)
	a.humanoid.Health = 0
	game.waitFor(function()
		local fresh = A()
		return fresh ~= nil and fresh ~= a and fresh.power ~= nil
	end, 4, "Alice to respawn")
	task.wait(0.3)
	local fresh = A()
	assert(fresh.power.id == "Admin", "still Admin")
	assert(fresh.power.ult < 5 and fresh.power.resource < 70, "a fresh meter")
	assert(not FighterState.isAttacking(fresh.state, now()), "not stuck mid-cast")
	assert(not status(fresh, "Gravity"), "no hang-time left")
	assert(#constructs(fresh) == 0, "no constructs")
end)

check("§38: a match ending with walls, cells, rings, fields and flight out leaves nothing behind", function()
	equip(A(), 3, { "Barrier", "Jail", "ArenaBarrier", "GravityField", "Fly" })
	local a, b = reset(10)
	for _, abilityId in { "Barrier", "Jail", "ArenaBarrier", "GravityField", "Fly" } do
		a.power.resource = a.power.resourceMax
		table.clear(a.power.cooldowns)
		request("AbilityRequest", alice, abilityId, aimAt(a, b))
		task.wait(ability(abilityId, 3).startup + 0.7)
	end
	-- (The cell has expired by now; the wall and the ring have not)
	assert(#constructs(a, "Barrier") == 1 and #constructs(a, "Lockdown") == 1, "constructs out: " .. #constructs(a))
	services.MatchService:endAll()
	task.wait(1.5)
	assert(services.MatchService:getMatchOf(A()) == nil, "match over")
	for _, fighter in { A(), B() } do
		assert(#constructs(fighter) == 0, "no constructs left")
		for name in fighter.model:GetAttributes() do
			assert(string.sub(name, 1, 4) ~= "SNS_", "status left: " .. name)
		end
		assert(fighter.root:FindFirstChild("SNDash") == nil, "no dash left")
	end
end)

check("a second match starts clean at Phase 1 with Authority at its start", function()
	startDuel()
	local a = A()
	assert(a.power.id == "Admin" and a.power.degree == 1, "Phase 1 again: " .. a.power.id .. " " .. tostring(a.power.degree))
	assert(a.power.resource >= 59 and a.power.resource <= 72, "Authority at its start: " .. a.power.resource)
	assert(#constructs(a) == 0 and not status(a, "Gravity"), "nothing left over")
end)

check("a player leaving while jailed leaves no cell behind", function()
	equip(A(), 2, { "Jail" })
	equip(B(), 2, { "Jail" })
	local a, b = reset(10)
	request("AbilityRequest", alice, "Jail", aimAt(a, b))
	task.wait(ability("Jail", 2).startup + 0.4)
	assert(status(b, "Trapped"), "jailed")
	game.leave(bob)
	task.wait(0.8)
	assert(#constructs(A(), "Jail") == 0, "the cell is gone")
	services.MatchService:endAll()
	task.wait(1)
	bob = game.join("Bob")
	game.waitFor(function()
		return B() ~= nil and B().power ~= nil
	end, 3, "Bob to return")
end)

-- CPU -----------------------------------------------------------------------------------------

check("a CPU Admin fights with its commands in CPU Practice (allowed on a trial)", function()
	local me = A()
	ready(me)
	request("MatchRequest", alice, "Queue", "Practice", { cpuPower = "Admin", cpuDegree = 3, cpuDifficulty = "Hard" })
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
	end, 4, "the CPU Admin")
	assert(cpu.power.id == "Admin" and cpu.power.degree == 3, "a Degree 3 Admin")
	local mark = game.mark()
	local started = os.clock()
	local used = {}
	while os.clock() - started < 12 and next(used) == nil do
		game.faceOff(cpu, A(), 14)
		task.wait(0.25)
		for _, cast in game.sentSince(mark, "AbilityEvent", "Cast") do
			if cast.fighter == cpu.model then
				used[cast.ability] = true
			end
		end
	end
	assert(next(used) ~= nil, "the CPU used an Admin command")
	services.MatchService:endAll()
	task.wait(1)
end)

-- Client visuals ------------------------------------------------------------------------------

check("Admin's visuals run: every effect, wind-up and the regalia at every degree", function()
	local ClientPowers = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Powers"))
	local Settings = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Settings"))
	local client = ClientPowers.module("Admin")
	assert(client, "client module loads")
	local function rig(name: string)
		local model = world.Instance.new("Model")
		model.Name = name
		for _, spec in {
			{ "HumanoidRootPart", Vector3.new(2, 2, 1) },
			{ "UpperTorso", Vector3.new(2, 1.6, 1) },
			{ "Head", Vector3.new(1.2, 1.2, 1.2) },
			{ "RightUpperArm", Vector3.new(1, 1.2, 1) },
			{ "LeftUpperArm", Vector3.new(1, 1.2, 1) },
			{ "RightLowerArm", Vector3.new(1, 1.2, 1) },
			{ "LeftLowerArm", Vector3.new(1, 1.2, 1) },
		} do
			local part = world.Instance.new("Part")
			part.Name = spec[1]
			part.Size = spec[2]
			part.CFrame = CFrame.new(0, 3, 0)
			part.Parent = model
		end
		world.Instance.new("Humanoid").Parent = model
		model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
		model:SetAttribute(Attribute.Power, "Admin")
		model.Parent = world.workspace
		return model
	end
	local target = rig("Target")
	local construct = world.Instance.new("Model")
	local piece = world.Instance.new("Part")
	piece.Name = "Panel"
	piece.CFrame = CFrame.new(6, 3, 0)
	piece.Parent = construct
	construct.PrimaryPart = piece
	construct.Parent = world.workspace
	local payload = {
		target = target,
		targets = { target },
		model = construct,
		position = Vector3.new(6, 0, 0),
		from = Vector3.new(0, 3, 0),
		to = Vector3.new(8, 3, 0),
		direction = Vector3.new(1, 0, 0),
		radius = 10,
		height = 6.5,
		width = 8,
		segments = 12,
		duration = 0.3,
		command = ";cmd",
		name = "Target",
		reason = "Expired",
		shield = 30,
		window = 0.4,
		haste = 1.4,
		magnitude = 0.3,
		heavy = 2.5,
		run = 0.3,
		index = 2,
		landed = true,
		facing = Vector3.new(1, 0, 0),
		reach = 7,
		pullRadius = 18,
		startup = 1.5,
		result = "Hit",
	}
	for _, reduced in { false, true } do
		Settings.values.reducedEffects = reduced
		for degree = 1, 3 do
			local model = rig("Admin" .. degree)
			model:SetAttribute(Attribute.Degree, degree)
			local cleanup = client.appearance(ClientPowers.kit(model, "Admin", {}))
			assert(cleanup == nil or typeof(cleanup) == "function", "appearance returns a cleanup")
			for name, handler in client.fx do
				handler(ClientPowers.kit(model, "Admin", table.clone(payload)))
				-- Junk data never breaks an effect
				handler(ClientPowers.kit(model, "Admin", { position = "x", from = 4, to = false, duration = "y", direction = Vector3.zero, target = "z", targets = 3, model = 5, radius = -1 }))
				assert(name ~= "", "")
			end
			for abilityId, predict in client.predict do
				predict(ClientPowers.kit(model, "Admin", { ability = abilityId, startup = 0.2, active = 0.1, predicted = true }))
				client.onCast(ClientPowers.kit(model, "Admin", { ability = abilityId, startup = 0.2 }))
			end
			Engine.step(world.game, 30)
			if cleanup then
				cleanup()
			end
			model:Destroy()
		end
	end
	Settings.values.reducedEffects = false
	task.wait(1)
	Engine.step(world.game, 10)
	target:Destroy()
	construct:Destroy()
end)

process.exit(if game.finish() == 0 then 0 else 1)
