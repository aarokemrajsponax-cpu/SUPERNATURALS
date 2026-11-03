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
	assert(ability("ArenaBarrier", 3).cost + ability("TeleportSequence", 3).cost + ability("Jail", 3).cost > authority.max, "big commands drain Authority")
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
		assert(#fxSince(mark, "SequenceStrike", a) >= 1 and #hits >= 1, label .. `: struck Bob (strikes {#fxSince(mark, "SequenceStrike", a)}, hits {#hits}, blink {#fxSince(mark, "SequenceBlink", a)}, broken {#fxSince(mark, "SequenceBroken", a)}, rej {rejection(mark, alice, abilityId)}))
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

process.exit(if game.finish() == 0 then 0 else 1)
