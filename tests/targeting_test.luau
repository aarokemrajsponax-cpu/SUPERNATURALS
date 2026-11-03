-- Targeted abilities and the energy rebalance, end to end with simulated players:
--   rojo build default.project.json -o $S/build_<you>.rbxl
--   lune run tests/targeting_test.luau $S/build_<you>.rbxl
-- Covers: every targeted ability really receives the (validated) point or direction,
-- points beyond range are clamped, absurd and non-finite aims are refused, directions are
-- normalised, a teleport into a wall or a blocked landing never moves anyone, untargeted
-- Strong Dude is unchanged, the client's pure aiming rules, and the cost and regen scale.

local process = require("@lune/process")

local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl", function(setup)
	setup.MatchConfig.Modes.Duel.Duration = 900
end)
local task, Vector3, CFrame = game.task, game.Vector3, game.CFrame
local services, check, request = game.services, game.check, game.request
local world, Engine = game.world, game.Engine
local Powers = world.require(world.find("ReplicatedStorage.Shared.Powers"))
local Combat = world.require(world.find("ReplicatedStorage.Shared.Config.Combat"))
local Protocol = world.require(world.find("ReplicatedStorage.Shared.Protocol"))
local Attribute = Protocol.Attribute

game.flatGround(0)

local function now(): number
	return world.workspace:GetServerTimeNow()
end

local alice, bob, arena
local function A()
	return game.fighter(alice)
end
local function B()
	return game.fighter(bob)
end

local function flatDistance(a, b): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function ready(fighter)
	local runtime = fighter.power
	runtime.resource = runtime.resourceMax
	runtime.ult = Combat.Ultimate.Max
	table.clear(runtime.cooldowns)
	local state = fighter.state
	state.attack = nil
	state.stunUntil = -math.huge
	state.comboCount = 0
	state.lightReadyAt = -math.huge
	state.heavyReadyAt = -math.huge
	state.invulnerableUntil = -math.huge
	state.protectedUntil = -math.huge
	services.StatusService:clearAll(fighter)
	fighter.humanoid.Health = fighter.humanoid.MaxHealth
	services.CharacterService:refresh(fighter)
end

local function equip(fighter, powerId: string, degree: number)
	services.PowerService:equip(fighter, powerId, degree, Powers.defaultLoadout(powerId, degree))
	ready(fighter)
end

-- Alice at the middle of the arena facing +Z, Bob far off to the side
local function stage()
	local a, b = A(), B()
	a.root.CFrame = CFrame.lookAt(arena.center + Vector3.new(0, 3, 0), arena.center + Vector3.new(0, 3, 10))
	b.root.CFrame = CFrame.lookAt(arena.center + Vector3.new(30, 3, 0), arena.center + Vector3.new(0, 3, 0))
	Engine.syncPositions(world.workspace)
	return a, b
end

-- Replaces a power's handler with a spy that records the aim it was given
local function spy(fighter, abilityId: string)
	local runtime = fighter.power
	local original = runtime.module.abilities[abilityId]
	local seen = nil
	runtime.module.abilities[abilityId] = function(ctx)
		seen = { point = ctx.point, direction = ctx.direction, look = ctx.look }
	end
	return function()
		runtime.module.abilities[abilityId] = original
		return seen
	end
end

-- Casts one ability with a spy in its place and returns (accepted, seen)
local function probe(fighter, abilityId: string, aim: any)
	ready(fighter)
	fighter.power.loadout = { abilityId }
	local read = spy(fighter, abilityId)
	-- Basic-attack replacements (a power's Light or Heavy) are used as basics
	local opts = nil
	local runtime = fighter.power
	for _, kind in { "Light", "Heavy" } do
		if Powers.basicFor(runtime.id, runtime.degree, runtime.form, kind) == abilityId then
			opts = { basic = kind }
		end
	end
	local ok, reason = services.AbilityService:use(fighter, abilityId, aim, opts)
	task.wait(0.05)
	local seen = read()
	-- Let any state clear so the next probe starts clean
	fighter.state.attack = nil
	return ok, seen, reason
end

check("two players start a duel", function()
	alice = game.join("Alice")
	bob = game.join("Bob")
	game.waitFor(function()
		return A() ~= nil and A().power ~= nil and B() ~= nil and B().power ~= nil
	end, 2, "powers to be equipped")
	request("MatchRequest", alice, "Queue", "Duel")
	request("MatchRequest", bob, "Queue", "Duel")
	local match
	game.waitFor(function()
		match = services.MatchService:getMatchOf(A())
		return match ~= nil and match.flow.phase == "Active"
	end, 4, "the duel to begin")
	arena = match.arena
	task.wait(0.2)
end)

local EXPECTED = {
	Corruption = { point = { "RiftBlink", "UnstableGround", "DistortionZone" }, direction = { "CorruptBolt" } },
	Syntax = {
		point = { "Strikethrough", "TargetLock", "Interface", "CommandZone", "ConfinementField", "ObjectOverride", "RuleRewrite", "Reconstruct", "SystemOverride", "HoloBarrier" },
		direction = { "Keystroke", "CodeBolt", "ExecuteChain", "MovementOverride" },
	},
	Admin = { point = { "Teleport", "FreezeCommand", "GravityCommand", "Jail", "Barrier", "GravityField", "BanHammer" } },
	MachineMaster = { direction = { "BlasterShot", "ChargedShot", "ScatterBlast", "RailShot", "MissileVolley", "SoulFireballs" }, point = { "SoulforgeDevice" } },
	Ghost = { teleport = { "ShadowStep" }, direction = { "InstantDraw", "SpectralDash", "SlashWave", "SlashFlurry", "FollowThrough" }, point = { "ConvergingGrid" } },
}

check("definitions: each power carries the planned targeting modes; Strong Dude, Grandmaster and Shapeshifter have none", function()
	for powerId, modes in EXPECTED do
		for mode, ids in modes do
			for _, id in ids do
				local def = Powers.abilityFor(powerId, id, 3)
				assert(def and def.targeting == mode, `{powerId}.{id} should target by {mode}, has {def and def.targeting}`)
			end
		end
	end
	for _, powerId in { "StrongDude", "Grandmaster", "Shapeshifter" } do
		for id in Powers.get(powerId).abilities do
			assert(Powers.abilityFor(powerId, id, 3).targeting == nil, `{powerId}.{id} keeps facing and lock-on`)
		end
	end
end)

check("every targeted ability receives the validated point or normalised direction", function()
	local a = stage()
	local count = 0
	for powerId, modes in EXPECTED do
		equip(a, powerId, 3)
		for mode, ids in modes do
			for _, id in ids do
				local def = Powers.abilityFor(powerId, id, 3)
				local range = def.range or Combat.Targeting.DefaultRange
				local at = a.root.Position
				-- A point well inside the reach, off to one side, with an unnormalised direction
				local inside = at + Vector3.new(3, 0, 0.4 * math.min(range, 20))
				local ok, seen, why = probe(a, id, { direction = Vector3.new(0, 0, 7), point = inside })
				if id == "FollowThrough" then
					-- Gated on a slash in flight (checked in the Ghost test); the aim itself is not refused
					assert(ok or why == "No slash to follow", "FollowThrough aim accepted")
					continue
				end
				assert(ok, `{powerId}.{id} refused: {why}`)
				assert(seen, `{powerId}.{id} handler never ran`)
				assert(seen.point and (seen.point - inside).Magnitude < 4.5, `{powerId}.{id} point used: {tostring(seen.point)}`)
				assert(math.abs(seen.direction.Magnitude - 1) < 1e-3 and seen.direction.Z > 0.99, `{powerId}.{id} direction normalised`)
				-- A different point gives a different result: it is not a constant
				local other = at + Vector3.new(-4, 0, 0.3 * math.min(range, 20))
				local _, again = probe(a, id, { direction = Vector3.new(-1, 0, 0), point = other })
				assert(again and again.point and (again.point - other).Magnitude < 4.5 and (again.point - seen.point).Magnitude > 1, `{powerId}.{id} follows the point`)
				assert(again.direction.X < -0.99, `{powerId}.{id} follows the direction`)
				count += 1
			end
		end
	end
	assert(count >= 30, "checked the targeted abilities: " .. count)
end)

check("points beyond range are clamped with a little tolerance", function()
	local a = stage()
	equip(a, "Syntax", 3)
	local def = Powers.abilityFor("Syntax", "CommandZone", 3)
	local reach = def.range + Combat.Abilities.AimSlack
	local far = a.root.Position + Vector3.new(0, 0, def.range + 20)
	local ok, seen = probe(a, "CommandZone", { direction = Vector3.new(0, 0, 1), point = far })
	assert(ok and seen.point, "accepted")
	local distance = (seen.point - a.root.Position).Magnitude
	assert(distance <= reach + 1e-3 and distance >= def.range, "clamped to range plus slack: " .. distance)
	-- Within the slack is left alone
	local near = a.root.Position + Vector3.new(0, 0, def.range + 2)
	local _, kept = probe(a, "CommandZone", { direction = Vector3.new(0, 0, 1), point = near })
	assert((kept.point - near).Magnitude < 1e-3, "inside the tolerance: unchanged")
end)

check("absurd, non-finite and junk aims are refused for targeted abilities", function()
	local a = stage()
	equip(a, "Syntax", 3)
	local hostile = {
		{ direction = Vector3.new(0, 0, 1), point = Vector3.new(0 / 0, 0, 0) },
		{ direction = Vector3.new(0, 0, 1), point = Vector3.new(math.huge, 0, 0) },
		{ direction = Vector3.new(0 / 0, 0, 1), point = a.root.Position },
		{ direction = Vector3.new(0, 0, 1), point = a.root.Position + Vector3.new(0, 0, 5000) },
		{ direction = Vector3.new(0, 0, 1), point = Vector3.new(1e9, 1e9, 1e9) },
		{ direction = Vector3.new(0, 0, 1), point = "over there" },
		{ direction = 5, point = a.root.Position },
	}
	for index, aim in hostile do
		local ok, seen = probe(a, "CommandZone", aim)
		assert(not ok and seen == nil, `hostile aim {index} was refused`)
		assert(a.power.resource == a.power.resourceMax, `hostile aim {index} cost nothing`)
	end
	-- A missing aim and a zero direction fall back to the fighter's facing
	local ok, seen = probe(a, "CommandZone", nil)
	assert(ok and seen.direction.Z > 0.99, "no aim: faces forward")
	local ok2, zero = probe(a, "CommandZone", { direction = Vector3.zero })
	assert(ok2 and zero.direction.Z > 0.99, "zero direction: faces forward")
end)

check("Ghost teleport: walls shorten the jump, and a blocked landing moves nobody", function()
	local a = stage()
	equip(a, "Ghost", 3)
	local start = a.root.Position
	local target = start + Vector3.new(0, 0, 16)
	-- Open floor: lands on the spot
	a.power.loadout = { "ShadowStep" }
	request("AbilityRequest", alice, "ShadowStep", { direction = Vector3.new(0, 0, 1), point = target })
	task.wait(0.4)
	Engine.syncPositions(world.workspace)
	assert(flatDistance(a.root.Position, target) < 1.5, "landed on the aimed spot: " .. tostring(a.root.Position))
	-- Solid ground everywhere blocked: nobody moves and the energy comes back
	ready(a)
	a.root.CFrame = CFrame.new(start)
	Engine.syncPositions(world.workspace)
	local blocker = world.Instance.new("Part")
	Engine.partsInBox = function()
		return { blocker }
	end
	request("AbilityRequest", alice, "ShadowStep", { direction = Vector3.new(0, 0, 1), point = target })
	task.wait(0.4)
	Engine.partsInBox = nil
	Engine.syncPositions(world.workspace)
	assert(flatDistance(a.root.Position, start) < 0.05, "did not move into the wall")
	assert(a.power.resource >= a.power.resourceMax - 1, "refunded")
	-- A wall in the way: the aim is cut short of it before the power sees it
	ready(a)
	a.root.CFrame = CFrame.new(start)
	Engine.syncPositions(world.workspace)
	local previous = Engine.raycast
	Engine.raycast = function(origin, direction)
		if direction.Y == 0 and direction.Z > 0 then
			return { Position = Vector3.new(origin.X, origin.Y, origin.Z + 6), Instance = blocker, Normal = Vector3.new(0, 0, -1) }
		end
		if previous then
			return previous(origin, direction)
		end
		return { Position = Vector3.new(origin.X, 0, origin.Z), Instance = blocker, Normal = Vector3.new(0, 1, 0) }
	end
	local ok, seen = probe(a, "ShadowStep", { direction = Vector3.new(0, 0, 1), point = target })
	Engine.raycast = previous
	assert(ok and seen.point, "accepted")
	assert(seen.point.Z - start.Z < 6 - Combat.Targeting.WallMargin + 0.1, "stopped short of the wall: " .. (seen.point.Z - start.Z))
end)

check("Machine Master fires where it is told; Ghost slashes follow the direction", function()
	local a = stage()
	equip(a, "MachineMaster", 3)
	a.power.loadout = { "ScatterBlast" }
	local mark = game.mark()
	request("AbilityRequest", alice, "ScatterBlast", { direction = Vector3.new(1, 0, 0), point = a.root.Position + Vector3.new(30, 0, 0) })
	task.wait(0.6)
	local fired = nil
	for _, entry in game.sentSince(mark, "AbilityEvent", "ProjectileSpawn") do
		if entry.owner == a.model then
			fired = entry
		end
	end
	assert(fired and fired.velocity.X > 0.9 * fired.velocity.Magnitude, "the shot flew along +X though Alice faced +Z")
	equip(a, "Ghost", 3)
	a.power.loadout = { "SlashWave" }
	mark = game.mark()
	request("AbilityRequest", alice, "SlashWave", { direction = Vector3.new(-1, 0, 0), point = a.root.Position + Vector3.new(-30, 0, 0) })
	task.wait(0.6)
	fired = nil
	for _, entry in game.sentSince(mark, "AbilityEvent", "ProjectileSpawn") do
		if entry.owner == a.model then
			fired = entry
		end
	end
	assert(fired and fired.velocity.X < -0.5 * fired.velocity.Magnitude, "the slash flew along -X")
end)

check("Strong Dude is unchanged: no targeting, point clamp as before, facing aim still works", function()
	local a = stage()
	equip(a, "StrongDude", 3)
	local ids = 0
	for id in Powers.get("StrongDude").abilities do
		local def = Powers.abilityFor("StrongDude", id, 3)
		assert(def.targeting == nil, id .. " untargeted")
		ids += 1
	end
	assert(ids > 3, "has abilities")
	local id = Powers.defaultLoadout("StrongDude", 3)[1]
	local def = Powers.abilityFor("StrongDude", id, 3)
	-- Junk points are clamped quietly (legacy rule), never an error
	local ok, seen = probe(a, id, { direction = Vector3.new(0, 0, 1), point = a.root.Position + Vector3.new(0, 0, 900) })
	assert(ok and seen, "still casts")
	assert((seen.point - a.root.Position).Magnitude <= (def.range or def.reach or 40) + Combat.Abilities.AimSlack + 1e-3, "clamped")
end)

check("energy rebalance: costs halved, regeneration faster, read from config", function()
	assert(Combat.ResourceCostScale > 0 and Combat.ResourceCostScale <= 0.6, "costs about half")
	assert(Combat.ResourceRegenScale >= 1.5, "regeneration about 1.7 times")
	for powerId in { StrongDude = 1, Ghost = 1, Syntax = 1, Admin = 1, MachineMaster = 1, Corruption = 1, Grandmaster = 1, Shapeshifter = 1 } do
		local def = Powers.get(powerId)
		local tune = Combat.ResourceTuning[powerId] or {}
		for id, ability in def.abilities do
			if (ability.cost or 0) > 0 then
				local scaled = Powers.abilityFor(powerId, id, 3).cost
				local expected = math.max(1, math.floor(ability.cost * Combat.ResourceCostScale * (tune.cost or 1) + 0.5))
				assert(scaled == expected, `{powerId}.{id}: authored {ability.cost} scales to {expected}, got {scaled}`)
				assert(scaled < ability.cost, `{powerId}.{id} costs less than before`)
			end
		end
	end
	-- The tick really regenerates at the scaled rate
	local a = stage()
	equip(a, "Ghost", 3)
	a.power.resource = 10
	local before = now()
	task.wait(1)
	local gained = a.power.resource - 10
	local elapsed = now() - before
	local rate = Powers.scaledRegen("Ghost", Powers.get("Ghost").resource.regen)
	assert(rate > Powers.get("Ghost").resource.regen * 1.5, "faster than authored")
	assert(gained > rate * elapsed * 0.6 and gained < rate * elapsed * 1.5 + 2, `regen about {rate}/s: gained {gained} in {elapsed}`)
end)

check("client aiming rules: range clamp and shapes", function()
	local Targeting = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Controllers.TargetingController"))
	local origin = Vector3.new(0, 3, 0)
	local p, snapped = Targeting.clampToRange(origin, Vector3.new(0, 0, 50), 20)
	assert(snapped and math.abs(p.Z - 20) < 1e-3, "pulled back to the range edge")
	local q, kept = Targeting.clampToRange(origin, Vector3.new(5, 0, 5), 20)
	assert(not kept and q == Vector3.new(5, 0, 5), "inside range untouched")
	local range, radius = Targeting.shapeOf(Powers.abilityFor("Syntax", "CommandZone", 3))
	local zone = Powers.abilityFor("Syntax", "CommandZone", 3)
	assert(range == zone.range and radius == zone.radius, `range and area radius shown: {range}, {radius}`)
	local _, teleportRadius = Targeting.shapeOf(Powers.abilityFor("Ghost", "ShadowStep", 3))
	assert(teleportRadius == 3, "landing marker")
end)

process.exit(if game.finish() == 0 then 0 else 1)
