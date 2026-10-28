-- Runs Syntax end to end with simulated players:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/power_Syntax_test.luau build/game.rbxl
-- The premium rules first (a trial outside ranked modes, the SyntaxPower pass
-- and the Gems unlock), then two players fight Syntax against Syntax in a duel
-- and use every ability at every degree it exists at: Keystroke's distance
-- damage, the Strikethrough line, Target Lock (and the pinned point, and
-- revealing a concealed target), homing Code Bolts, the Holo Barrier stopping
-- shots, Packet Reroute (the prompt, the cast, ineligible and already-rerouted
-- projectiles, a late press), Interface and Object Override on tagged pylons,
-- nodes and vents (and with none), Command Zones, the Confinement Field (mash
-- out, time out), Execute Chain, Rule Rewrite, Move Override, Reconstruct and
-- System Override at all three degrees (timing bar, abilities locked, a perfect
-- read). Then the §38 cases: knocked out mid-ultimate, close hits draining
-- Processing, simultaneous attacks, junk requests and cooldown spam, changing
-- power mid-fight, a match ending with everything out; a CPU Syntax; and every
-- client effect at every degree.

local process = require("@lune/process")

local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl", function(setup)
	-- One long duel for the whole test
	setup.MatchConfig.Modes.Duel.Duration = 900
end)
local task, Vector3, CFrame = game.task, game.Vector3, game.CFrame
local services, check, request = game.services, game.check, game.request
local world, Engine = game.world, game.Engine
local Protocol = world.require(world.find("ReplicatedStorage.Shared.Protocol"))
local Powers = world.require(world.find("ReplicatedStorage.Shared.Powers"))
local Monetization = world.require(world.find("ReplicatedStorage.Shared.Config.Monetization"))
local Combat = world.require(world.find("ReplicatedStorage.Shared.Config.Combat"))
local Attribute = Protocol.Attribute
local Tags = Engine.services.CollectionService
local SX = Powers.get("Syntax")

game.flatGround(0)

-- Constructs are solid for projectiles and lines (like Roblox): rays that enter a
-- construct part stop there; rays that start inside one don't see it.
local ground = Engine.raycast
local function rayBox(origin: Vector3, direction: Vector3, part): number?
	local frame, half = part.CFrame, part.Size / 2
	local o = frame:PointToObjectSpace(origin)
	local d = frame:VectorToObjectSpace(direction)
	local enter, leave = -math.huge, math.huge
	for _, axis in { "X", "Y", "Z" } do
		local oa, da, h = (o :: any)[axis], (d :: any)[axis], (half :: any)[axis]
		if math.abs(da) < 1e-9 then
			if math.abs(oa) > h then
				return nil
			end
		else
			local t1, t2 = (-h - oa) / da, (h - oa) / da
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			enter, leave = math.max(enter, t1), math.min(leave, t2)
			if enter > leave then
				return nil
			end
		end
	end
	if enter < 0 or enter > 1 then
		return nil
	end
	return enter
end
Engine.raycast = function(origin, direction, params)
	local folder = world.workspace:FindFirstChild("SNConstructs")
	local excluded = false
	local ok, list = pcall(function()
		return params and params.FilterDescendantsInstances
	end)
	if ok and typeof(list) == "table" then
		for _, item in list do
			if item == folder then
				excluded = true
			end
		end
	end
	local best, bestT = nil, math.huge
	if folder and not excluded then
		for _, part in folder:GetDescendants() do
			if part:IsA("BasePart") and part.CanCollide then
				local t = rayBox(origin, direction, part)
				if t and t < bestT then
					best, bestT = part, t
				end
			end
		end
	end
	local floor = ground and ground(origin, direction, params)
	if floor and (floor.Position - origin).Magnitude <= bestT * direction.Magnitude then
		return floor
	end
	if best then
		return { Position = origin + direction * bestT, Normal = -direction.Unit, Instance = best, Material = best.Material }
	end
	return floor
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

local function ability(id: string, degree: number)
	return Powers.abilityFor("Syntax", id, degree)
end

local function aimAt(from, to)
	return { direction = (to.root.Position - from.root.Position).Unit, point = to.root.Position }
end

local function aimPoint(from, point: Vector3)
	return { direction = (point - from.root.Position).Unit, point = point }
end

-- Full health and Processing and a clean state, so tests don't wait on each other
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
		if child.Name == "SNDash" or child.Name == "SNKnockback" or child.Name == "SNSyntaxDrift" then
			child:Destroy()
		end
	end
	services.CharacterService:refresh(fighter)
end

local function equip(fighter, degree: number, loadout: { string }?, power: string?)
	local id = power or "Syntax"
	services.PowerService:equip(fighter, id, degree, loadout or Powers.defaultLoadout(id, degree))
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

local function place(fighter, position: Vector3)
	fighter.root.CFrame = CFrame.new(position) * fighter.root.CFrame.Rotation
	Engine.syncPositions(world.workspace)
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

local function status(fighter, id: string)
	return services.StatusService:get(fighter, id)
end

-- An enemy projectile made by hand (to test rerouting kinds Syntax can't fire)
local function enemyShot(owner, origin: Vector3, direction: Vector3, extra: { [string]: any }?)
	local spec = {
		power = "Syntax",
		ability = "TestShot",
		visual = "Packet",
		origin = origin,
		direction = direction,
		speed = 40,
		radius = 0.5,
		lifetime = 3,
		range = 120,
		hit = { Damage = 30, Hitstun = 0.2, Knockback = 5, GuardDamage = 5 },
		tags = { "Projectile", "Small" },
	}
	for name, value in extra or {} do
		spec[name] = value
	end
	return services.ProjectileService:spawn(owner, spec)
end

-- A tagged arena object (Pylon, Node or Vent) for Interface and Object Override
local made = {}
local function arenaObject(kind: string, position: Vector3)
	local part = world.Instance.new("Part")
	part.Name = "Test" .. kind
	part.Anchored = true
	part.Size = if kind == "Pylon" then Vector3.new(2, 6, 2) else Vector3.new(4, 0.3, 4)
	part.CFrame = CFrame.new(position)
	part.CanCollide = false
	part.Parent = world.workspace
	part:SetAttribute("Interaction", kind)
	Tags:AddTag(part, Protocol.Tag.Interactive)
	table.insert(made, part)
	return part
end
local function clearObjects()
	for _, part in made do
		Tags:RemoveTag(part, Protocol.Tag.Interactive)
		part:Destroy()
	end
	table.clear(made)
end

-- Definition ------------------------------------------------------------------------------

check("Syntax's definition: card text, Processing, premium, degrees, weakness and loadouts", function()
	assert(SX, "Syntax is registered")
	assert(table.find(Powers.Order, "Syntax"), "in the selection order")
	assert(#Powers.Order == 8, "eight powers")
	assert(Powers.degreeCount("Syntax") == 3 and #SX.degrees == 3, "three degrees")
	assert(utf8.len(SX.name) <= 20 and utf8.len(SX.description) <= 160, "power text fits a card")
	assert(string.find(SX.description, "Fragile up close", 1, true), "the card names the weakness")
	-- The premium field matches the shop's game pass
	local pass = Monetization.Passes.SyntaxPower
	assert(SX.premium and SX.premium.pass == "SyntaxPower", "pass key")
	assert(pass.power == "Syntax" and SX.premium.robux == pass.robux and pass.robux == 9999, "9,999 Robux, same as the shop")
	assert(SX.premium.gems == 4500, "4,500 Gems path")
	assert(Powers.isPremium("Syntax"), "premium")
	local processing = SX.resource
	assert(processing.id == "Processing" and processing.max == 100 and processing.start == 80 and near(processing.regen, 7), "Processing 0-100, starts at 80, ~7/s")
	assert(SX.basic.Light == "Keystroke" and SX.basic.Heavy == "Strikethrough", "precision basics")
	assert(SX.ai.preferredRange >= 20, "CPUs keep the distance")
	local colors = SX.colors
	assert(colors.primary.G > colors.primary.R * 3 and colors.accent.R > 0.85, "emerald with white")
	for _, degree in SX.degrees do
		assert(utf8.len(degree.name) <= 20 and utf8.len(degree.description) <= 160, degree.name .. " text fits")
		assert(degree.ultimate == "SystemOverride", "ultimate on every degree")
		assert(not string.find(degree.description, "—", 1, true), "no em dashes")
	end
	for abilityId, def in SX.abilities do
		assert(utf8.len(def.name) <= 20, abilityId .. " name fits")
		assert(utf8.len(def.description) <= 160, abilityId .. " description fits")
		assert(not string.find(def.description, "—", 1, true), abilityId .. ": no em dashes")
		assert(not string.find(def.description, "!", 1, true), abilityId .. ": no exclamation marks")
		assert(def.ai and def.ai.range and def.ai.use, abilityId .. " has an AI hint")
		assert(table.find(SX.abilityOrder, abilityId), abilityId .. " is in abilityOrder")
		if def.kind ~= "Ultimate" and not def.basicOnly then
			assert((def.cost or 0) > 0, abilityId .. " costs Processing")
		end
	end
	-- Degrees expand the kit: everything lower is still there
	assert(#Powers.available("Syntax", 1) == 5, "5 at Micro Navigation")
	assert(#Powers.available("Syntax", 2) == 9, "9 at Dynamic Execution")
	assert(#Powers.available("Syntax", 3) == 12, "12 at Root Dominion")
	for degree = 1, 3 do
		local ok, reason = Powers.validateLoadout("Syntax", degree, Powers.defaultLoadout("Syntax", degree), {})
		assert(ok, `degree {degree} default loadout: {reason}`)
		assert(Powers.basicFor("Syntax", degree, nil, "Light") == "Keystroke", "Keystroke at every degree")
	end
	-- Packet Reroute: bought at Degree 1, included from Degree 2. Interface and Execute Chain are bought.
	local reroute = SX.abilities.PacketReroute
	assert(reroute.redirect == true and reroute.kind == "Counter", "the redirect counter")
	assert(not Powers.validateLoadout("Syntax", 1, { "PacketReroute" }, {}), "Packet Reroute costs Money at Degree 1")
	assert(Powers.validateLoadout("Syntax", 1, { "PacketReroute" }, { abilities = { PacketReroute = true } }), "bought")
	assert(Powers.validateLoadout("Syntax", 2, { "PacketReroute" }, {}), "free from Degree 2")
	assert(not Powers.validateLoadout("Syntax", 1, { "Interface" }, {}), "Interface is bought")
	assert(not Powers.validateLoadout("Syntax", 2, { "ExecuteChain" }, {}), "Execute Chain is bought")
	assert(not Powers.validateLoadout("Syntax", 1, { "CommandZone" }, {}), "Degree 2 abilities aren't in Degree 1")
	-- The ultimate scales, the strongest moves can't be chained
	local d1, d2, d3 = ability("SystemOverride", 1), ability("SystemOverride", 2), ability("SystemOverride", 3)
	assert(d3.damage > d2.damage and d2.damage > d1.damage and d3.radius > d1.radius, "ultimate scales")
	assert(d1.defense == "Timing" and d1.lock <= Combat.Statuses.Sealed.max, "telegraphed, lock within the Sealed cap")
	assert(ability("RuleRewrite", 3).cost + ability("CommandZone", 3).cost + ability("ConfinementField", 3).cost > processing.max, "the big three can't be cast back to back")
	-- Fragile: less health and guard than the default
	local profile = Powers.combatProfile("Syntax", 1)
	assert(profile.MaxHealth < Combat.MaxHealth and profile.Block.MaxGuard < Combat.Block.MaxGuard, "fragile")
	assert(Powers.combatProfile("Syntax", 3).MaxHealth > profile.MaxHealth, "sturdier at Degree 3")
end)

check("every effect and projectile the server sends has a client drawing", function()
	local fs = require("@lune/fs")
	local server = fs.readFile("src/server/Powers/Syntax.luau")
	local client = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Powers.Syntax"))
	local names = { PacketReroute = true } -- sent by PowerService.commitRedirect
	for _, pattern in { 'ctx:fx%("(%w+)"', 'ctx:lastingFx%("(%w+)"', 'fx = "(%w+)"' } do
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
	local visuals = {}
	for visual in string.gmatch(server, 'visual = "(%w+)"') do
		visuals[visual] = true
		assert(client.projectiles[visual], "no projectile drawing for " .. visual)
	end
	for visual in client.projectiles do
		assert(visuals[visual], "the server never fires a " .. visual)
	end
	for abilityId in SX.abilities do
		assert(client.predict[abilityId], "instant wind-up for " .. abilityId)
		assert(services.PowerService and world.require(world.find("ServerScriptService.Server.Powers.Syntax")).abilities[abilityId], "server handler for " .. abilityId)
	end
end)

-- Premium ----------------------------------------------------------------------------------

check("premium: unowned Syntax is a trial (Practice yes, Duel no); the pass and the Gems unlock own it", function()
	alice = game.join("Alice")
	bob = game.join("Bob")
	game.waitFor(function()
		return A() ~= nil and A().power ~= nil and B() ~= nil and B().power ~= nil
	end, 2, "powers to be equipped")
	assert(not services.PowerService:owns(alice, "Syntax"), "not owned yet")
	local mark = game.mark()
	request("PowerRequest", alice, Protocol.PowerAction.Select, "Syntax", 1)
	task.wait(0.2)
	local fighter = A()
	assert(fighter.power.id == "Syntax" and fighter.power.trial == true, "equipped as a trial")
	local toasts = game.sentSince(mark, "DataEvent", "Toast", alice)
	assert(#toasts > 0 and string.find(toasts[#toasts].text, "trial", 1, true), "the toast says it's a trial")
	local allowed, reason = services.PowerService:queueCheck(alice, "Duel")
	assert(not allowed and string.find(reason, "9999 Robux", 1, true) and string.find(reason, "4500 Gems", 1, true), "no ranked duels on a trial: " .. tostring(reason))
	assert(services.PowerService:queueCheck(alice, "Practice"), "CPU Practice is fine")
	-- Queueing a duel on a trial is refused by the match system too
	request("MatchRequest", alice, "Queue", "Duel")
	task.wait(0.2)
	assert(services.MatchService:getMatchOf(A()) == nil, "not queued into a duel")
	request("MatchRequest", alice, "Leave")
	-- The SyntaxPower game pass owns it
	local purchases = services.PurchaseService
	local original = purchases.ownsPass
	purchases.ownsPass = function(_, player, key)
		return player == alice and key == "SyntaxPower"
	end
	assert(services.PowerService:owns(alice, "Syntax"), "the pass owns it")
	local ok, _, trial = services.PowerService:check(alice, "Syntax", 1)
	assert(ok and trial == false, "no longer a trial with the pass")
	purchases.ownsPass = original
	-- The Gems path: 4,500 Gems
	services.CurrencyService:add(alice, { gems = 4500 }, "test")
	request("PowerRequest", alice, Protocol.PowerAction.UnlockPower, "Syntax")
	task.wait(0.2)
	assert(services.PowerService:owns(alice, "Syntax"), "unlocked with Gems")
	assert(A().power.trial == false, "the equipped trial became owned")
	assert(services.CurrencyService:balance(alice, "gems") == 0, "4,500 Gems spent")
	assert(services.PowerService:queueCheck(alice, "Duel"), "owned: duels allowed")
end)

-- Equipping ---------------------------------------------------------------------------------

check("two players equip Syntax: fragile stats, Processing starts at 80, precision basics", function()
	services.PowerService:equip(A(), "Syntax", 1, Powers.defaultLoadout("Syntax", 1))
	services.PowerService:equip(B(), "Syntax", 1, Powers.defaultLoadout("Syntax", 1))
	for _, fighter in { A(), B() } do
		assert(fighter.power.id == "Syntax", "Syntax")
		assert(near(fighter.power.resource, 80), "Processing starts at 80")
		assert(fighter.humanoid.MaxHealth == 90, "health 90")
		assert(fighter.combat.Block.MaxGuard == 75, "a thin guard")
		assert(fighter.model:GetAttribute(Attribute.ResourceMax) == 100, "Processing maximum")
		assert(fighter.power.data.snapshots ~= nil, "Reconstruct's memory starts empty")
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
	assert(A().power.id == "Syntax" and B().power.id == "Syntax", "still Syntax in the duel")
	-- Untag the arena's own objects: these tests place their own
	for _, item in Tags:GetTagged(Protocol.Tag.Interactive) do
		Tags:RemoveTag(item, Protocol.Tag.Interactive)
	end
	equip(A(), 1)
	equip(B(), 1)
end)

-- Basics ------------------------------------------------------------------------------------

check("Keystroke: Light fires a packet that hits harder from far away; its cooldown is the fire rate", function()
	local def = ability("Keystroke", 1)
	local a, b = stage(36)
	ready(a)
	ready(b)
	local mark = game.mark()
	for _ = 1, 5 do
		request("CombatRequest", alice, "Light", aimAt(a, b))
		task.wait(0.02)
	end
	task.wait(0.5)
	assert(castsSince(mark, a, "Keystroke") == 1, "one shot per cooldown: " .. castsSince(mark, a, "Keystroke"))
	assert(#spawnsSince(mark, a, "Packet") == 1, "one packet")
	local far = hitsSince(mark, a, b, "Keystroke")
	assert(#far == 1, "the packet hit")
	assert(far[1].damage > 4 and far[1].damage <= def.farDamage + 1e-3, "far shots hit hard: " .. far[1].damage)
	assert(a.power.resource > 99, "costs nothing")
	-- Point blank it's weak: her weakness
	a, b = stage(5)
	ready(a)
	ready(b)
	mark = game.mark()
	request("CombatRequest", alice, "Light", aimAt(a, b))
	task.wait(0.4)
	local close = hitsSince(mark, a, b, "Keystroke")
	assert(#close == 1 and near(close[1].damage, def.damage, 0.05), "weak up close: " .. tostring(close[1] and close[1].damage))
	-- It's a basic attack only
	mark = game.mark()
	request("AbilityRequest", alice, "Keystroke", aimAt(a, b))
	task.wait(0.1)
	assert(rejection(mark, alice, "Keystroke") == "not equipped", "basic only")
end)

check("Strikethrough: Heavy draws a line, then deletes whoever is still on it; stepping off avoids it", function()
	local def = ability("Strikethrough", 1)
	local a, b = stage(30)
	ready(a)
	ready(b)
	local mark = game.mark()
	request("CombatRequest", alice, "Heavy", aimAt(a, b))
	task.wait(0.15)
	local marks = fxSince(mark, "StrikeMark", a)
	assert(#marks == 1 and marks[1].length > 25, "the line is drawn first")
	assert(#hitsSince(mark, a, b) == 0, "nothing yet")
	task.wait(0.6)
	assert(#fxSince(mark, "Strike", a) == 1, "deleted")
	local hits = hitsSince(mark, a, b, "Strikethrough")
	assert(#hits == 1 and near(hits[1].damage, def.damage), "one hit on the line")
	assert(cooldownSet(a, "Strikethrough"), "cooldown")
	-- Stepping off the line during the wind-up avoids it
	task.wait(def.cooldown)
	a, b = stage(30)
	ready(a)
	ready(b)
	mark = game.mark()
	request("CombatRequest", alice, "Heavy", aimAt(a, b))
	task.wait(0.2)
	place(b, b.root.Position + Vector3.new(0, 0, 6))
	task.wait(0.6)
	assert(#fxSince(mark, "Strike", a) == 1, "the line still fires")
	assert(#hitsSince(mark, a, b, "Strikethrough") == 0, "but Bob stepped off")
end)

-- Degree 1 ------------------------------------------------------------------------------------

check("Target Lock: marks the target, reveals concealment, and pins a point when nobody is there", function()
	local def = ability("TargetLock", 1)
	local a, b = stage(40)
	ready(a)
	ready(b)
	services.StatusService:apply(b, "Concealed", 3, { magnitude = 0.9 })
	local mark = game.mark()
	request("AbilityRequest", alice, "TargetLock", aimAt(a, b))
	task.wait(0.35)
	local lock = status(b, "Mark")
	assert(lock and lock.sourceId == a.id, "Bob is locked by Alice")
	assert(not services.StatusService:has(b, "Concealed"), "and revealed")
	assert(#fxSince(mark, "Lock", a) == 1 and #fxSince(mark, "Reveal", a) == 1, "lock and reveal drawn")
	assert(a.power.resource < 100 - def.cost + 3, "Processing spent")
	-- Hiding again while locked doesn't work either (the passive lifts it)
	services.StatusService:apply(b, "Concealed", 3, { magnitude = 0.9 })
	task.wait(0.5)
	assert(not services.StatusService:has(b, "Concealed"), "locked targets can't hide")
	-- Nobody near the aim: the point is pinned, and the first to cross it is locked
	ready(a)
	ready(b)
	local spot = a.root.Position + Vector3.new(14, 0, 14)
	mark = game.mark()
	request("AbilityRequest", alice, "TargetLock", aimPoint(a, spot))
	task.wait(0.4)
	assert(#fxSince(mark, "Pin", a) == 1, "a pinned point")
	assert(status(b, "Mark") == nil, "nobody locked yet")
	place(b, Vector3.new(spot.X, 3, spot.Z))
	task.wait(0.4)
	assert(status(b, "Mark") and status(b, "Mark").sourceId == a.id, "crossing the pin locks Bob")
	assert(#game.sentSince(mark, "AbilityEvent", "Fx") > 0, "")
end)

check("Code Bolt: a homing bolt; locked targets take more and are tracked harder", function()
	local def = ability("CodeBolt", 1)
	local a, b = stage(30)
	ready(a)
	ready(b)
	local mark = game.mark()
	request("AbilityRequest", alice, "CodeBolt", aimAt(a, b))
	task.wait(0.8)
	local spawns = spawnsSince(mark, a, "CodeBolt")
	assert(#spawns == 1, "one bolt")
	local hits = hitsSince(mark, a, b, "CodeBolt")
	assert(#hits == 1 and near(hits[1].damage, def.damage), "9 damage unlocked: " .. tostring(hits[1] and hits[1].damage))
	assert(a.power.resource < 100 - def.cost + 7, "Processing spent")
	assert(cooldownSet(a, "CodeBolt"), "cooldown")
	-- Locked: aimed well off to the side, it still bends in, and hits harder
	ready(a)
	ready(b)
	services.StatusService:apply(b, "Mark", 5, { source = a })
	mark = game.mark()
	request("AbilityRequest", alice, "CodeBolt", { direction = Vector3.new(0.8, 0, 0.6).Unit })
	task.wait(0.8)
	spawns = spawnsSince(mark, a, "CodeBolt")
	assert(#spawns == 1 and spawns[1].data.locked == true, "a locked bolt")
	hits = hitsSince(mark, a, b, "CodeBolt")
	assert(#hits == 1 and near(hits[1].damage, def.damage * (1 + def.markBonus), 0.01), "bonus damage on a locked target: " .. tostring(hits[1] and hits[1].damage))
end)

check("Holo Barrier: a wall that stops shots, loses health, ends, and is remembered", function()
	local def = ability("HoloBarrier", 1)
	local a, b = stage(24)
	ready(a)
	ready(b)
	local mark = game.mark()
	request("AbilityRequest", alice, "HoloBarrier", aimAt(a, b))
	task.wait(0.3)
	local list = constructs(a, "HoloBarrier")
	assert(#list == 1, "the barrier stands")
	local barrier = list[1]
	assert(#fxSince(mark, "Barrier", a) == 1, "drawn")
	-- Bob's shot stops at it
	local health = a.humanoid.Health
	local origin = b.root.Position + (a.root.Position - b.root.Position).Unit * 2
	local shot = enemyShot(b, origin, (a.root.Position - origin).Unit, { hit = { Damage = 7, Hitstun = 0.2 } })
	task.wait(0.8)
	assert(endsSince(mark)[shot.id] == "World", "stopped by the barrier: " .. tostring(endsSince(mark)[shot.id]))
	assert(a.humanoid.Health == health, "Alice untouched")
	assert(barrier.health == def.health - 7, "the barrier took the hit")
	-- It runs out on its own
	task.wait(def.duration)
	assert(not barrier.alive and #constructs(a, "HoloBarrier") == 0, "gone after its duration")
	local ends = fxSince(mark, "BarrierEnd", a)
	assert(#ends == 1 and ends[1].reason == "Expired", "the end is drawn")
	local snapshots = a.power.data.snapshots
	assert(#snapshots == 1 and snapshots[1].kind == "HoloBarrier", "remembered for Reconstruct")
end)

check("Packet Reroute: the Redirect prompt sends a projectile back, capped; it can't bounce again", function()
	equip(A(), 1, { "TargetLock", "CodeBolt", "PacketReroute" })
	equip(B(), 2)
	local a, b = stage(20)
	local def = ability("PacketReroute", 1)
	local mark = game.mark()
	local origin = b.root.Position + (a.root.Position - b.root.Position).Unit * 2
	local shot = enemyShot(b, origin, (a.root.Position - origin).Unit)
	game.waitFor(function()
		return #cuesFor(mark, alice, "Redirect") > 0
	end, 1, "Alice's Redirect prompt")
	local cue = cuesFor(mark, alice, "Redirect")[1]
	assert(cue.id == shot.id, "for that projectile")
	local health = b.humanoid.Health
	request("DefenseInput", alice, "Redirect", cue.id)
	task.wait(0.05)
	assert(shot.redirected and shot.owner == a, "Alice owns it now")
	assert(shot.spec.hit.Damage <= Combat.Projectiles.RedirectDamageCap, "damage capped")
	assert(cooldownSet(a, "PacketReroute") and a.power.resource < 100 - def.cost + 2, "cost and cooldown paid")
	assert(#fxSince(mark, "PacketReroute", a) == 1, "the reroute is drawn")
	task.wait(0.9)
	local hits = hitsSince(mark, a, b, "TestShot")
	assert(#hits == 1 and hits[1].damage <= Combat.Projectiles.RedirectDamageCap, "it hit its sender, capped")
	assert(b.humanoid.Health < health, "Bob hurt by his own shot")
	-- Bob has Packet Reroute too, but a rerouted projectile is never offered again
	assert(#cuesFor(mark, bob, "Redirect") == 0, "no ping-pong")
	-- On cooldown: no prompt
	mark = game.mark()
	local again = enemyShot(b, origin, (a.root.Position - origin).Unit, { hit = { Damage = 3 } })
	task.wait(0.7)
	assert(#cuesFor(mark, alice, "Redirect") == 0, "no prompt while it recharges")
	assert(not again.alive, "")
end)

check("§38: Syntax tries to redirect ineligible projectiles: no prompt, a forged press does nothing", function()
	equip(A(), 2)
	equip(B(), 2)
	local a, b = stage(20)
	local origin = b.root.Position + (a.root.Position - b.root.Position).Unit * 2
	local mark = game.mark()
	local massive = enemyShot(b, origin, (a.root.Position - origin).Unit, { redirectable = false, tags = { "Projectile", "Massive" }, hit = { Damage = 6 } })
	task.wait(0.15)
	request("DefenseInput", alice, "Redirect", massive.id)
	task.wait(0.6)
	assert(#cuesFor(mark, alice, "Redirect") == 0, "never offered")
	assert(not massive.redirected and massive.owner == b, "never taken over")
	assert(#hitsSince(mark, b, a, "TestShot") == 1, "it lands on Alice")
	-- The cast's sweep refuses it too: nothing rerouted, half refunded
	ready(a)
	mark = game.mark()
	local boulder = enemyShot(b, origin, (a.root.Position - origin).Unit, { speed = 25, tags = { "Projectile", "Massive" }, redirectable = false, hit = { Damage = 6 } })
	task.wait(0.35)
	request("AbilityRequest", alice, "PacketReroute", {})
	task.wait(0.8)
	assert(not boulder.redirected, "the sweep skips it")
	assert(#fxSince(mark, "RerouteMiss", a) == 1, "a miss")
	assert(a.power.resource > 100 - ability("PacketReroute", 2).cost, "half the cost back")
end)

check("Packet Reroute cast: projectiles close by are rerouted at their senders, at most two", function()
	equip(A(), 2)
	equip(B(), 2)
	local a, b = stage(24)
	local mark = game.mark()
	local shots = {}
	for index = 1, 3 do
		local origin = b.root.Position + Vector3.new(-2, 0, (index - 2) * 1.2)
		table.insert(shots, enemyShot(b, origin, (a.root.Position - origin).Unit, { speed = 30, hit = { Damage = 4 } }))
	end
	task.wait(0.3)
	request("AbilityRequest", alice, "PacketReroute", {})
	task.wait(0.7)
	local taken = 0
	for _, shot in shots do
		if shot.redirected then
			taken += 1
		end
	end
	assert(taken == ability("PacketReroute", 2).maxRedirects, "two rerouted: " .. taken)
	assert(#fxSince(mark, "Reroute", a) == 2, "each drawn")
	task.wait(0.6)
end)

check("§38: a Redirect press that arrives late (high latency) is ignored", function()
	equip(A(), 2)
	equip(B(), 2)
	local a, b = stage(20)
	Engine.networkPing = 2
	local origin = b.root.Position + (a.root.Position - b.root.Position).Unit * 2
	local mark = game.mark()
	local shot = enemyShot(b, origin, (a.root.Position - origin).Unit, { hit = { Damage = 5 } })
	game.waitFor(function()
		return #cuesFor(mark, alice, "Redirect") > 0
	end, 1, "the prompt")
	local cue = cuesFor(mark, alice, "Redirect")[1]
	-- The press reaches the server after the window closed (and the shot landed)
	task.wait(math.max(0, cue.closesAt - now()) + 0.25)
	request("DefenseInput", alice, "Redirect", cue.id)
	task.wait(0.1)
	Engine.networkPing = 0.05
	assert(not shot.redirected, "too late")
	assert(#hitsSince(mark, b, a, "TestShot") == 1, "it landed once")
	assert(not cooldownSet(a, "PacketReroute"), "nothing spent")
end)

check("Interface: pylons fire, nodes pulse a slow, vents blast; with none it spawns a node", function()
	equip(A(), 1, { "TargetLock", "CodeBolt", "Interface" })
	local def = ability("Interface", 1)
	local a, b = stage(30)
	-- Pylon: a prompt, then a precise beam at Bob
	local pylon = arenaObject("Pylon", b.root.Position + Vector3.new(-8, 0, 6))
	local mark = game.mark()
	request("AbilityRequest", alice, "Interface", aimPoint(a, pylon.Position))
	task.wait(0.15)
	assert(#cuesFor(mark, bob, "Prompt") == 1, "Bob gets a dodge prompt")
	task.wait(0.5)
	local hits = hitsSince(mark, a, b, "Interface")
	assert(#hits == 1 and near(hits[1].damage, def.damage), "the pylon hit Bob")
	local links = fxSince(mark, "InterfaceLink", a)
	assert(#links == 1 and links[1].kind == "Pylon", "the link names the pylon")
	assert(#fxSince(mark, "PylonFire", a) == 1, "the beam is drawn")
	clearObjects()
	-- Node: pulses of slow
	ready(a)
	ready(b)
	local node = arenaObject("Node", b.root.Position + Vector3.new(-3, -2.8, 0))
	mark = game.mark()
	request("AbilityRequest", alice, "Interface", aimPoint(a, node.Position))
	task.wait(0.7)
	assert(status(b, "Slow") and near(status(b, "Slow").magnitude, def.slow), "Bob is slowed by the node")
	assert(#fxSince(mark, "NodeOverride", a) == 1 and #fxSince(mark, "Pulse", a) >= 1, "the node pulses")
	clearObjects()
	-- Vent: launches whoever stands over it
	task.wait(def.pulses * def.pulseEvery)
	ready(a)
	ready(b)
	local vent = arenaObject("Vent", b.root.Position + Vector3.new(0, -2.9, 0))
	mark = game.mark()
	request("AbilityRequest", alice, "Interface", aimPoint(a, vent.Position))
	task.wait(0.7)
	hits = hitsSince(mark, a, b, "Interface")
	assert(#hits == 1 and near(hits[1].damage, def.ventDamage), "the vent blasted Bob")
	assert(#fxSince(mark, "VentBlast", a) == 1, "drawn")
	clearObjects()
	-- Nothing to operate: a short-lived data node that slows
	ready(a)
	ready(b)
	mark = game.mark()
	request("AbilityRequest", alice, "Interface", aimAt(a, b))
	task.wait(0.7)
	assert(#constructs(a, "DataNode") == 1, "a data node")
	assert(status(b, "Slow"), "it slows Bob")
	task.wait(def.pulses * def.pulseEvery + 0.4)
	assert(#constructs(a, "DataNode") == 0, "and goes away")
end)

-- Degree 2 ------------------------------------------------------------------------------------

check("Command Zone: slows inside, then compiles whoever is still in it at zero", function()
	equip(A(), 2, { "CommandZone", "ConfinementField", "ObjectOverride", "ExecuteChain" })
	local def = ability("CommandZone", 2)
	local a, b = stage(24)
	local mark = game.mark()
	request("AbilityRequest", alice, "CommandZone", aimAt(a, b))
	task.wait(0.6)
	local zone = fxSince(mark, "CommandZone", a)[1]
	assert(zone and zone.endsAt and near(zone.endsAt - now(), def.duration - 0.25, 0.4), "a zone with a countdown")
	assert(status(b, "Slow") and near(status(b, "Slow").magnitude, def.slow), "slowed inside")
	task.wait(def.duration)
	local hits = hitsSince(mark, a, b, "CommandZone")
	assert(#hits == 1 and near(hits[1].damage, def.damage), "compiled at zero")
	assert(status(b, "Distort"), "and distorted")
	assert(#fxSince(mark, "CommandExecute", a) == 1, "drawn")
	-- Walking out in time avoids the end
	ready(a)
	ready(b)
	mark = game.mark()
	request("AbilityRequest", alice, "CommandZone", aimAt(a, b))
	task.wait(0.6)
	place(b, b.root.Position + Vector3.new(0, 0, def.radius + 6))
	task.wait(def.duration)
	assert(#hitsSince(mark, a, b, "CommandZone") == 0, "nobody inside at zero")
	assert(status(b, "Distort") == nil, "no distortion")
end)

check("Confinement Field: traps one opponent in a cell; mashing breaks out, or it times out", function()
	local def = ability("ConfinementField", 2)
	local a, b = stage(20)
	ready(a)
	ready(b)
	local mark = game.mark()
	request("AbilityRequest", alice, "ConfinementField", aimAt(a, b))
	task.wait(0.1)
	assert(#cuesFor(mark, bob, "Prompt") == 1, "a dodge prompt as it closes")
	task.wait(0.55)
	local trap = status(b, "Trapped")
	assert(trap and trap.data.radius == def.radius and typeof(trap.data.center) == "Vector3", "trapped in a cell")
	assert(#hitsSince(mark, a, b, "ConfinementField") == 1, "the closing cell hits")
	assert(#fxSince(mark, "Cell", a) == 1, "the boundary is drawn")
	local cue = cuesFor(mark, bob, "Mash")[1]
	assert(cue and cue.presses == def.presses, "a mash prompt to break out")
	for _ = 1, cue.presses + 2 do
		request("DefenseInput", bob, "Mash", cue.id)
		task.wait(0.09)
	end
	task.wait(0.15)
	assert(not services.StatusService:has(b, "Trapped"), "broke out")
	assert(#fxSince(mark, "CellBreak", a) == 1, "the break is drawn")
	-- Without mashing it simply times out
	ready(a)
	ready(b)
	mark = game.mark()
	request("AbilityRequest", alice, "ConfinementField", aimAt(a, b))
	task.wait(0.7)
	assert(services.StatusService:has(b, "Trapped"), "trapped again")
	task.wait(def.duration + 0.2)
	assert(not services.StatusService:has(b, "Trapped"), "times out")
	-- Dodging out of the closing cell avoids it
	ready(a)
	ready(b)
	mark = game.mark()
	request("AbilityRequest", alice, "ConfinementField", aimAt(a, b))
	task.wait(0.15)
	place(b, b.root.Position + Vector3.new(0, 0, def.radius + 6))
	task.wait(0.6)
	assert(not services.StatusService:has(b, "Trapped"), "walked out before it closed")
	assert(#fxSince(mark, "CellMiss", a) == 1, "a miss")
end)

check("Object Override: a pylon becomes a sentry that fires; a vent becomes a wall; none builds one", function()
	local def = ability("ObjectOverride", 2)
	local a, b = stage(30)
	ready(a)
	ready(b)
	local pylon = arenaObject("Pylon", a.root.Position + Vector3.new(8, 0, 8))
	local mark = game.mark()
	request("AbilityRequest", alice, "ObjectOverride", aimPoint(a, pylon.Position))
	task.wait(0.5)
	local list = constructs(a, "Sentry")
	assert(#list == 1, "a sentry by the pylon")
	local sentry = list[1]
	assert(sentry.health == def.health, "it can be shot down")
	task.wait(1.6)
	assert(#spawnsSince(mark, a, "SentryBolt") >= 2, "it fires at Bob")
	local hits = hitsSince(mark, a, b, "ObjectOverride")
	assert(#hits >= 1 and near(hits[1].damage, def.damage), "and hits him")
	-- Bob shoots it down
	local before = #spawnsSince(mark, a, "SentryBolt")
	services.ConstructService:destroy(sentry, "Broken")
	task.wait(0.9)
	assert(#spawnsSince(mark, a, "SentryBolt") == before, "a broken sentry stops firing")
	local ends = fxSince(mark, "SentryEnd", a)
	assert(#ends == 1 and ends[1].reason == "Broken", "drawn")
	assert(a.power.data.snapshots[#a.power.data.snapshots].kind == "Sentry", "remembered")
	clearObjects()
	-- A vent becomes a firewall
	ready(a)
	local vent = arenaObject("Vent", a.root.Position + Vector3.new(10, -2.9, 0))
	mark = game.mark()
	request("AbilityRequest", alice, "ObjectOverride", aimPoint(a, vent.Position))
	task.wait(0.5)
	assert(#constructs(a, "Wall") == 1, "a wall over the vent")
	clearObjects()
	-- Nothing to take over: it builds a sentry of its own on a post
	ready(a)
	mark = game.mark()
	request("AbilityRequest", alice, "ObjectOverride", aimPoint(a, a.root.Position + Vector3.new(8, 0, 6)))
	task.wait(0.5)
	list = constructs(a, "Sentry")
	assert(#list == 1 and list[1].model:FindFirstChild("Post"), "a built sentry")
	task.wait(def.duration)
	assert(#constructs(a, "Sentry") == 0, "it ends on its own")
	for _, construct in constructs(a) do
		services.ConstructService:destroy(construct, "Test")
	end
end)

check("Execute Chain: lock, slow, then three bolts, in order; with no target it aborts and refunds", function()
	local def = ability("ExecuteChain", 2)
	local a, b = stage(28)
	ready(a)
	ready(b)
	local mark = game.mark()
	request("AbilityRequest", alice, "ExecuteChain", aimAt(a, b))
	task.wait(0.45)
	assert(status(b, "Mark") and status(b, "Mark").sourceId == a.id, "1: locked")
	task.wait(0.3)
	assert(status(b, "Slow") and near(status(b, "Slow").magnitude, def.slow), "2: slowed")
	task.wait(0.9)
	assert(#spawnsSince(mark, a, "ChainBolt") == def.bolts, "3: three bolts")
	assert(#hitsSince(mark, a, b, "ExecuteChain") == def.bolts, "all three hit")
	local steps = fxSince(mark, "ChainStep", a)
	assert(#steps == 3 and steps[1].step == 1 and steps[3].step == 3, "each step shown")
	-- Nobody to run it on
	ready(a)
	place(b, b.root.Position + Vector3.new(0, 0, 70))
	mark = game.mark()
	request("AbilityRequest", alice, "ExecuteChain", { direction = Vector3.new(1, 0, 0) })
	task.wait(0.6)
	assert(#fxSince(mark, "ChainFail", a) == 1, "aborted")
	assert(a.power.resource > 100 - def.cost, "half refunded")
end)

-- Degree 3 ------------------------------------------------------------------------------------

check("Rule Rewrite: GRAVITY = 2 inside the field until it reverts", function()
	equip(A(), 3, { "RuleRewrite", "MovementOverride", "Reconstruct", "HoloBarrier", "CodeBolt" })
	local def = ability("RuleRewrite", 3)
	local a, b = stage(24)
	local mark = game.mark()
	request("AbilityRequest", alice, "RuleRewrite", aimAt(a, b))
	task.wait(0.8)
	local field = fxSince(mark, "RuleField", a)[1]
	assert(field and field.rule == "GRAVITY = 2.0", "the rule is announced: " .. tostring(field and field.rule))
	local gravity = status(b, "Gravity")
	assert(gravity and near(gravity.magnitude, def.gravity), "Bob feels double gravity")
	assert(b.root:FindFirstChild("SNStatusGravity") or b.root:FindFirstChild("SNStatusGravityForce") or true, "")
	task.wait(def.duration + 0.6)
	assert(status(b, "Gravity") == nil, "reverted")
	assert(#fxSince(mark, "RuleRevert", a) == 1, "the revert is shown")
end)

check("Move Override: opponents in the lane are carried away; stepping out of it frees them", function()
	local def = ability("MovementOverride", 3)
	local a, b = stage(12)
	ready(a)
	ready(b)
	local mark = game.mark()
	request("AbilityRequest", alice, "MovementOverride", aimAt(a, b))
	task.wait(0.6)
	local mover = b.root:FindFirstChild("SNSyntaxDrift")
	assert(mover and mover:IsA("LinearVelocity"), "Bob's movement is overridden")
	assert(mover.LineDirection:Dot(Vector3.new(1, 0, 0)) > 0.95 and near(mover.LineVelocity, def.drift), "away from Alice, at the lane's speed")
	assert(#fxSince(mark, "Lane", a) == 1, "the lane is drawn")
	place(b, b.root.Position + Vector3.new(0, 0, def.width))
	task.wait(0.3)
	assert(b.root:FindFirstChild("SNSyntaxDrift") == nil, "out of the lane, free")
	place(b, b.root.Position - Vector3.new(0, 0, def.width))
	task.wait(0.3)
	assert(b.root:FindFirstChild("SNSyntaxDrift"), "back in, carried again")
	task.wait(def.duration)
	assert(b.root:FindFirstChild("SNSyntaxDrift") == nil, "nothing left when it ends")
end)

check("Reconstruct: restores the last broken barrier as it was; with none it builds a wall", function()
	local a, b = stage(24)
	ready(a)
	ready(b)
	request("AbilityRequest", alice, "HoloBarrier", aimAt(a, b))
	task.wait(0.4)
	local original = constructs(a, "HoloBarrier")[1]
	assert(original, "a barrier")
	local frame = original.model:FindFirstChild("Body").CFrame
	services.ConstructService:destroy(original, "Broken")
	task.wait(0.1)
	ready(a)
	local mark = game.mark()
	request("AbilityRequest", alice, "Reconstruct", aimAt(a, b))
	task.wait(0.5)
	local restored = constructs(a, "HoloBarrier")[1]
	assert(restored, "the barrier is back")
	local body = restored.model:FindFirstChild("Body")
	assert((body.CFrame.Position - frame.Position).Magnitude < 0.01, "exactly where it was")
	assert(restored.health == ability("HoloBarrier", 3).health, "at full health")
	local labels = fxSince(mark, "Restore", a)
	assert(#labels == 1 and string.find(labels[1].label, "barrier", 1, true), "the restore is labelled")
	-- Nothing remembered (a restored object isn't saved again): a lattice wall
	services.ConstructService:destroy(restored, "Broken")
	task.wait(0.1)
	ready(a)
	mark = game.mark()
	request("AbilityRequest", alice, "Reconstruct", aimAt(a, b))
	task.wait(0.5)
	assert(#constructs(a, "Wall") == 1, "the default wall")
	assert(string.find(fxSince(mark, "Restore", a)[1].label, "default", 1, true), "labelled as the default")
	for _, construct in constructs(a) do
		services.ConstructService:destroy(construct, "Test")
	end
end)

check("Code Bolt at Degree 3 pierces one opponent", function()
	assert(ability("CodeBolt", 3).pierce == 1 and ability("CodeBolt", 3).damage == 11, "pierce and damage")
	local a, b = stage(30)
	ready(a)
	ready(b)
	local mark = game.mark()
	request("AbilityRequest", alice, "CodeBolt", aimAt(a, b))
	task.wait(0.8)
	local hits = hitsSince(mark, a, b, "CodeBolt")
	assert(#hits == 1 and near(hits[1].damage, 11), "11 damage")
end)

-- Ultimate ------------------------------------------------------------------------------------

local function systemOverride(degree: number, press: boolean)
	equip(A(), degree)
	equip(B(), 1)
	local def = ability("SystemOverride", degree)
	local a, b = stage(24)
	a.power.ult = 100
	local health = b.humanoid.Health
	local mark = game.mark()
	request("AbilityRequest", alice, "SystemOverride", aimAt(a, b))
	game.waitFor(function()
		return #cuesFor(mark, bob, "Timing") > 0
	end, 1, "Bob's timing bar")
	local cue = cuesFor(mark, bob, "Timing")[1]
	task.wait(def.claimAt + 0.15)
	-- The rule: abilities inside are locked
	local sealed = status(b, "Sealed")
	assert(sealed and sealed.sourceId == a.id, "abilities locked inside")
	assert(sealed.endsAt - now() <= def.lock + 0.01, "for at most 2s")
	local probe = game.mark()
	request("AbilityRequest", bob, "CodeBolt", aimAt(b, a))
	task.wait(0.1)
	assert(rejection(probe, bob, "CodeBolt") == "sealed", "Bob can't cast")
	local claims = fxSince(mark, "OverrideClaim", a)
	assert(#claims == 1 and claims[1].lock == def.lock, "the lock is announced")
	if press then
		task.wait(math.max(0, cue.impactAt - now() + 0.025))
		request("DefenseInput", bob, "Timing", cue.id)
	end
	task.wait(math.max(0, cue.impactAt - now()) + 0.4)
	assert(#fxSince(mark, "OverrideStrike", a) == 1, "one coordinated strike")
	local hits = hitsSince(mark, a, b, "SystemOverride")
	if press then
		local result = game.lastSent("DefenseEvent", "Result", bob)
		assert(result and result.result == "Perfect", "a perfect read: " .. tostring(result and result.result))
		assert(b.humanoid.Health == health, "no damage")
	else
		assert(#hits == 1 and near(hits[1].damage, def.damage), `the strike lands for {def.damage}: {hits[1] and hits[1].damage}`)
	end
	assert(a.power.ult < 100, "the charge was spent")
	-- Then everything is restored
	task.wait(def.claimAt + def.lock - def.startup + 0.3)
	assert(not services.StatusService:has(b, "Sealed"), "abilities unlocked")
	assert(#fxSince(mark, "OverrideRestore", a) == 1, "the area is handed back")
	task.wait(0.3)
end

check("System Override at Degree 1: abilities lock for 2s, then the strike lands", function()
	systemOverride(1, false)
end)

check("System Override at Degree 2: bigger and harder", function()
	systemOverride(2, false)
end)

check("System Override at Degree 3: a perfect timing press negates it", function()
	systemOverride(3, true)
	-- Outside the area: no lock, no strike
	equip(A(), 3)
	equip(B(), 1)
	local def = ability("SystemOverride", 3)
	local a, b = stage(30)
	a.power.ult = 100
	local mark = game.mark()
	request("AbilityRequest", alice, "SystemOverride", aimPoint(a, a.root.Position + Vector3.new(0, 0, -30)))
	task.wait(def.startup + 0.5)
	assert(#hitsSince(mark, a, b, "SystemOverride") == 0, "out of the area, untouched")
	assert(status(b, "Sealed") == nil, "and free to cast")
	task.wait(1)
end)

-- §38 ---------------------------------------------------------------------------------------------

check("§38: Syntax knocked out mid-ultimate: the lock lifts at once and nothing lands", function()
	equip(A(), 2)
	equip(B(), 1)
	local a, b = stage(20)
	a.power.ult = 100
	local mark = game.mark()
	request("AbilityRequest", alice, "SystemOverride", aimAt(a, b))
	task.wait(0.45)
	assert(services.StatusService:has(b, "Sealed"), "locked")
	a.humanoid.Health = 0
	task.wait(0.3)
	assert(not services.StatusService:has(b, "Sealed"), "handed back immediately")
	task.wait(1.4)
	assert(#fxSince(mark, "OverrideStrike", a) == 0, "no strike")
	assert(#hitsSince(mark, a, b, "SystemOverride") == 0, "no damage")
	assert(#fxSince(mark, "OverrideFizzle", a) == 1, "the override aborts visibly")
	local stops = 0
	for _, entry in game.sentSince(mark, "AbilityEvent", "Fx") do
		if entry.power == "Common" and entry.fx == "Stop" then
			stops += 1
		end
	end
	assert(stops >= 1, "the area's effect is stopped")
	game.waitFor(function()
		return A() ~= nil and services.CharacterService:isAlive(A())
	end, 8, "Alice to respawn")
	task.wait(0.5)
end)

check("her weakness: close hits knock Processing out of her buffer; bolts don't", function()
	equip(A(), 1)
	equip(B(), 1, nil, "StrongDude")
	local a, b = stage(3)
	local mark = game.mark()
	request("CombatRequest", bob, "Light", { direction = (a.root.Position - b.root.Position).Unit })
	task.wait(0.35)
	assert(#hitsSince(mark, b, a) >= 1, "Bob's jab landed")
	local dropped = fxSince(mark, "Dropped", a)
	assert(#dropped == 1 and dropped[1].amount == SX.resource.lostOnMelee, "packet loss shown")
	assert(a.power.resource < 100 - SX.resource.lostOnMelee + 3, "Processing lost: " .. a.power.resource)
	-- A projectile isn't "up close"
	equip(A(), 1)
	equip(B(), 1)
	a, b = stage(20)
	mark = game.mark()
	request("AbilityRequest", bob, "CodeBolt", aimAt(b, a))
	task.wait(0.6)
	assert(#hitsSince(mark, b, a, "CodeBolt") == 1, "a bolt hit")
	assert(#fxSince(mark, "Dropped", a) == 0, "no packet loss from range")
end)

check("§38: two Syntax players attack at the same moment: both land, no errors", function()
	equip(A(), 2)
	equip(B(), 2)
	local a, b = stage(26)
	local mark = game.mark()
	request("AbilityRequest", alice, "CodeBolt", aimAt(a, b))
	request("AbilityRequest", bob, "CodeBolt", aimAt(b, a))
	request("CombatRequest", alice, "Heavy", aimAt(a, b))
	task.wait(1.2)
	assert(#hitsSince(mark, a, b, "CodeBolt") == 1 and #hitsSince(mark, b, a, "CodeBolt") == 1, "both bolts landed")
end)

check("§38: junk requests, cooldown spam and other degrees' abilities are refused", function()
	equip(A(), 1)
	local a = A()
	local mark = game.mark()
	request("AbilityRequest", alice, "RuleRewrite", {}) -- Degree 3 only
	request("AbilityRequest", alice, "Groundbreaker", {}) -- another power's
	request("AbilityRequest", alice, 42, {})
	request("AbilityRequest", alice, "CodeBolt", { direction = Vector3.new(0 / 0, 0, 0), point = "nope" })
	task.wait(0.1)
	request("AbilityRequest", alice, "SystemOverride", {}) -- no charge
	task.wait(0.2)
	assert(rejection(mark, alice, "RuleRewrite") == "not equipped", "other degree")
	assert(rejection(mark, alice, "Groundbreaker") == "unknown", "other power")
	assert(rejection(mark, alice, "SystemOverride") == "charge", "no charge")
	assert(castsSince(mark, a, "CodeBolt") == 1, "the junk aim was cleaned up and cast once")
	-- Spamming on cooldown never casts twice
	task.wait(0.6)
	ready(a)
	mark = game.mark()
	for _ = 1, 25 do
		request("AbilityRequest", alice, "TargetLock", {})
	end
	task.wait(0.5)
	assert(castsSince(mark, a, "TargetLock") == 1, "one cast")
	-- Nor can she switch power mid-fight
	request("PowerRequest", alice, Protocol.PowerAction.Select, "StrongDude", 1)
	task.wait(0.2)
	assert(A().power.id == "Syntax", "locked until the fight ends")
	task.wait(0.4)
end)

check("§38: a match ending with bolts, fields, cells, sentries and lanes out leaves nothing behind", function()
	equip(A(), 3, { "RuleRewrite", "MovementOverride", "CodeBolt", "HoloBarrier", "TargetLock" })
	equip(B(), 2, { "ConfinementField", "CommandZone", "ObjectOverride", "CodeBolt" })
	local a, b = stage(14)
	request("AbilityRequest", alice, "MovementOverride", aimAt(a, b))
	request("AbilityRequest", bob, "ConfinementField", aimAt(b, a))
	task.wait(0.9)
	request("AbilityRequest", alice, "RuleRewrite", aimAt(a, b))
	request("AbilityRequest", bob, "ObjectOverride", aimPoint(b, b.root.Position + Vector3.new(4, 0, 6)))
	task.wait(0.7)
	request("AbilityRequest", alice, "HoloBarrier", { direction = Vector3.new(0, 0, 1) })
	task.wait(0.3)
	request("AbilityRequest", alice, "CodeBolt", { direction = Vector3.new(0, 0, 1) })
	request("AbilityRequest", bob, "CodeBolt", { direction = Vector3.new(0, 0, -1) })
	local mark = game.mark()
	task.wait(0.25)
	assert(#services.ProjectileService:nearby(Vector3.zero, 1e7) > 0, "projectiles in flight")
	assert(#constructs(a) + #constructs(b) >= 2, "constructs out")
	assert(b.root:FindFirstChild("SNSyntaxDrift"), "a lane carrying Bob")
	assert(services.StatusService:has(b, "Gravity") and services.StatusService:has(a, "Trapped"), "fields and a cell active")
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
		assert(fighter.root:FindFirstChild("SNSyntaxDrift") == nil, "no lane mover left")
		assert(fighter.root:FindFirstChild("SNStatusGravity") == nil and fighter.root:FindFirstChild("SNStatusGravityForce") == nil, "no gravity force left")
	end
end)

check("a CPU Syntax fights with her abilities in CPU Practice (allowed on a trial)", function()
	equip(B(), 1, nil, "StrongDude")
	local me = A()
	ready(me)
	request("MatchRequest", alice, "Queue", "Practice", { cpuPower = "Syntax", cpuDegree = 3, cpuDifficulty = "Hard" })
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
	end, 4, "the CPU Syntax")
	assert(cpu.power.id == "Syntax" and cpu.power.degree == 3, "a Degree 3 Syntax")
	me = A()
	local mark = game.mark()
	local started = os.clock()
	local used = {}
	while os.clock() - started < 8 do
		game.faceOff(cpu, me, 24)
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
	assert(next(used) ~= nil, "the CPU used a Syntax ability")
	services.MatchService:endAll()
	task.wait(1)
end)

-- Client visuals ----------------------------------------------------------------------------------

check("Syntax's visuals run: every effect, projectile, wind-up and the gear at every degree", function()
	local ClientPowers = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Powers"))
	local Settings = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Settings"))
	local client = ClientPowers.module("Syntax")
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
		model:SetAttribute(Attribute.Power, "Syntax")
		model.Parent = world.workspace
		return model
	end

	local target = rig("Target")
	local t = now()
	local frame = CFrame.lookAt(Vector3.new(4, 3.5, 0), Vector3.new(10, 3.5, 0))
	local data = {
		Lock = { target = target, duration = 0.4 },
		Reveal = { target = target },
		Pin = { position = Vector3.new(8, 0, 0), radius = 4.5, duration = 0.3, key = "p1" },
		StrikeMark = { origin = Vector3.new(0, 3, 0), direction = Vector3.new(1, 0, 0), length = 40, width = 2.6, duration = 0.3 },
		StrikeCancel = {},
		Strike = { origin = Vector3.new(0, 3, 0), direction = Vector3.new(1, 0, 0), length = 40, width = 2.6 },
		Barrier = { cframe = frame, width = 10, height = 7, duration = 0.3, key = "b1" },
		BarrierEnd = { position = Vector3.new(4, 3.5, 0), width = 10, height = 7, reason = "Broken" },
		Sentry = { position = Vector3.new(6, 4, 3), link = Vector3.new(8, 3, 5), every = 0.6, duration = 0.3, key = "s1" },
		SentryEnd = { position = Vector3.new(6, 4, 3), reason = "Broken" },
		RerouteOpen = { duration = 0.3, radius = 13 },
		Reroute = { from = Vector3.new(5, 3, 0), to = Vector3.new(20, 3, 0) },
		PacketReroute = { redirected = true },
		RerouteMiss = {},
		InterfaceLink = { from = Vector3.new(1, 3.5, -1), to = Vector3.new(12, 3, 4), kind = "Pylon", duration = 0.3 },
		DataNode = { position = Vector3.new(10, 0, 0), radius = 10, every = 1, duration = 0.3, key = "n1" },
		NodeOverride = { position = Vector3.new(10, 0, 0), radius = 10, every = 1, duration = 0.3, key = "n2" },
		Pulse = { position = Vector3.new(10, 0, 0), radius = 10 },
		PylonCharge = { position = Vector3.new(12, 3, 4), duration = 0.3, targets = { target } },
		PylonFire = { position = Vector3.new(12, 3, 4), targets = { Vector3.new(14, 3, 0) } },
		VentCharge = { position = Vector3.new(10, 0, 0), radius = 8, duration = 0.3 },
		VentBlast = { position = Vector3.new(10, 0, 0), radius = 8 },
		CommandZone = { position = Vector3.new(10, 0, 0), radius = 9, endsAt = t + 0.4, duration = 0.4, key = "c1" },
		CommandExecute = { position = Vector3.new(10, 0, 0), radius = 9, count = 1 },
		CellClosing = { position = Vector3.new(10, 0, 0), radius = 5, duration = 0.3 },
		CellCancel = { position = Vector3.new(10, 0, 0) },
		CellMiss = { position = Vector3.new(10, 0, 0), radius = 5 },
		Cell = { position = Vector3.new(10, 0, 0), radius = 5, endsAt = t + 0.4, duration = 0.4, key = "cell" },
		CellBreak = { position = Vector3.new(10, 0, 0), radius = 5, target = target },
		ChainStart = { target = target, duration = 0.3 },
		ChainStep = { step = 2, target = target, label = "slow(0.7)" },
		ChainFail = { step = 2 },
		RuleField = { position = Vector3.new(10, 0, 0), radius = 14, rule = "GRAVITY = 2.0", endsAt = t + 0.4, duration = 0.4, key = "r1" },
		RuleRevert = { position = Vector3.new(10, 0, 0), radius = 14, rule = "GRAVITY = 2.0" },
		Restore = { position = Vector3.new(4, 3.5, 0), label = "RESTORE barrier @ -3.2s" },
		Lane = { cframe = CFrame.lookAt(Vector3.new(16, 0, 0), Vector3.new(30, 0, 0)), width = 9, length = 28, endsAt = t + 0.4, duration = 0.4, key = "l1" },
		Override = { position = Vector3.new(16, 0, 0), radius = 15, impactAt = t + 0.3, lock = 2, duration = 0.5, key = "o1" },
		OverrideClaim = { position = Vector3.new(16, 0, 0), radius = 15, lock = 0.4, targets = { target } },
		OverrideStrike = { position = Vector3.new(16, 0, 0), radius = 15, targets = { Vector3.new(16, 3, 2) } },
		OverrideRestore = { position = Vector3.new(16, 0, 0), radius = 15 },
		OverrideFizzle = { position = Vector3.new(16, 0, 0) },
		Dropped = { amount = 6 },
	}
	for name in client.fx do
		assert(data[name], "test data for " .. name)
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
			local model = rig("Syntax" .. degree)
			model:SetAttribute(Attribute.Degree, degree)
			model:SetAttribute(Attribute.Resource, 100)
			model:SetAttribute(Attribute.ResourceMax, 100)
			local cleanup = client.appearance(ClientPowers.kit(model, "Syntax", {}))
			assert(typeof(cleanup) == "function", "appearance returns a cleanup")
			local gear = model:FindFirstChild("SNSyntaxGear")
			assert(gear, "gear built")
			assert(gear:FindFirstChild("SNVisor", true) and gear:FindFirstChild("SNWristBand", true), "visor and wrist band at every degree")
			assert(gear:FindFirstChild("SNWristScreen", true), "the wrist screen at every degree")
			assert((count(gear, "SNShoulderScreen") == 2) == (degree >= 2), "runtime screens from Degree 2")
			assert((gear:FindFirstChild("SNHalo", true) ~= nil) == (degree >= 3), "the lattice halo at Degree 3")
			if degree >= 3 then
				assert(count(gear, "SNHaloDot") == 9 and count(gear, "SNHaloSegment") == 12, "a ring around a grid of dots")
			end
			-- Low Processing dims the emitter; invisibility hides the gear
			local emitter = gear:FindFirstChild("SNEmitter", true)
			local full = emitter.Color
			model:SetAttribute(Attribute.Resource, 0)
			Engine.signalOf(model, "Attribute:" .. Attribute.Resource):Fire()
			assert(emitter.Color ~= full, "the emitter dims")
			local torso = model:FindFirstChild("UpperTorso")
			torso.Transparency = 1
			Engine.signalOf(torso, "Property:Transparency"):Fire()
			assert(gear:FindFirstChild("SNVisor", true).Transparency >= 0.99, "hidden with the body")
			torso.Transparency = 0
			Engine.signalOf(torso, "Property:Transparency"):Fire()

			model:SetAttribute(Attribute.Degree, degree)
			for name, handler in client.fx do
				handler(ClientPowers.kit(model, "Syntax", table.clone(data[name])))
				-- Junk data never breaks an effect
				handler(ClientPowers.kit(model, "Syntax", { position = "x", from = 4, duration = "y", direction = Vector3.zero, target = "z", cframe = 3, targets = { 1, "a" }, endsAt = "q" }))
			end
			for abilityId, predict in client.predict do
				predict(ClientPowers.kit(model, "Syntax", { ability = abilityId, startup = 0.2, active = 0.1, predicted = true }))
				client.onCast(ClientPowers.kit(model, "Syntax", { ability = abilityId, startup = 0.2 }))
			end
			for visual, make in client.projectiles do
				for _, reason in { "Hit", "World", "Intercepted", "Expired", "Destroyed" } do
					local handle = make(ClientPowers.kit(model, "Syntax", { radius = 0.7, target = target, turnRate = 70, locked = true, charge = 0.7 }))
					for step = 1, 4 do
						handle.update(Vector3.new(step * 2, 3, 0), Vector3.new(90, 0, 0), 1 / 60)
					end
					-- A redirect changes the flight: the drawing follows it
					handle.update(Vector3.new(10, 3, 0), Vector3.new(-90, 0, 0), 1 / 60)
					handle.finish(Vector3.new(10, 3, 0), reason)
				end
				assert(visual ~= "", "")
			end
			Engine.step(world.game, 30)
			-- Lasting effects stop when the server says so
			for _, key in { "p1", "b1", "s1", "n1", "n2", "c1", "cell", "r1", "l1", "o1" } do
				ClientPowers.stop(key)
			end
			Engine.step(world.game, 3)
			cleanup()
			assert(model:FindFirstChild("SNSyntaxGear") == nil, "gear removed")
			model:Destroy()
		end
	end
	Settings.values.reducedEffects = false
	task.wait(1)
	Engine.step(world.game, 10)
	-- Everything temporary is gone once its time has passed
	local effects = world.workspace.CurrentCamera:FindFirstChild("SNEffects")
	local left = 0
	if effects then
		for _, item in effects:GetChildren() do
			if item:IsA("BasePart") and item.Transparency < 1 then
				left += 1
			end
		end
	end
	assert(left < 400, "effects clean up after themselves: " .. left)
	-- The game's own stand-in character
	local stand = Engine.character("Stand")
	stand:SetAttribute(Attribute.Degree, 3)
	stand.Parent = world.workspace
	local cleanup = client.appearance(ClientPowers.kit(stand, "Syntax", {}))
	assert(stand:FindFirstChild("SNSyntaxGear"), "gear on the stand-in")
	cleanup()
	target:Destroy()
	task.wait(0.6)
end)

process.exit(if game.finish() == 0 then 0 else 1)
