-- The Ghost's abilities on the server: the instant katana draw (kept in the
-- Phase attribute so clients show or hide the blade), Phantom Veil, spectral
-- dashes and teleports, the spectral counter, energy slashes, the slash
-- flurry, Follow Through, the Converging Grid and Spectral Severance.
-- Numbers come from Shared/Powers/Ghost.luau (scaled by degree).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Ghost = {}
local abilities = {}
Ghost.abilities = abilities

local PHASE = Protocol.Attribute.Phase
-- Used when the definition doesn't say (it always should)
local DEFAULT_SHEATHE = 3
local DEFAULT_FOLLOW_WINDOW = 1.2
-- How often a moving strike checks what's in front of it
local SCAN_STEP = 0.03
-- Tags of the small cuts that aren't the ability's main hit
local CUT_TAGS = { "Melee", "Small" }

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- The floor under a point (fighters are left out); falls back to the caster's feet height
local function groundAt(ctx, point: Vector3): Vector3
	local ignore: { Instance } = { ctx.fighter.model }
	for _, enemy in ctx:enemies() do
		table.insert(ignore, enemy.model)
	end
	groundParams.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(point + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), groundParams)
	return if result then result.Position else Vector3.new(point.X, ctx:origin().Y - 3, point.Z)
end

-- Katana ---------------------------------------------------------------------------

local function setPhase(fighter, value: number)
	local model = fighter.model
	if model.Parent and model:GetAttribute(PHASE) ~= value then
		model:SetAttribute(PHASE, value)
	end
end

-- Instant Draw: the katana is in his hand the moment he attacks, and stays
-- drawn until he's been idle for a few seconds
local function draw(fighter, runtime)
	local katana = runtime.def.katana
	runtime.data.drawnUntil = now() + (if katana then katana.sheatheAfter else DEFAULT_SHEATHE)
	setPhase(fighter, 1)
end

-- Phantom Veil -----------------------------------------------------------------------

-- Attacking or being hit brings him back into view. Returns whether he was veiled.
local function reveal(ctx): boolean
	local me = ctx.fighter
	if not ctx:hasStatus(me, "Concealed") then
		return false
	end
	ctx:clearStatus(me, "Concealed")
	if ctx.data.veilHaste then
		ctx.data.veilHaste = nil
		ctx:clearStatus(me, "Haste")
	end
	ctx:fx("VeilBreak", {})
	return true
end

-- Every katana attack: out of the veil, blade in hand
local function unsheathe(ctx): boolean
	local wasVeiled = reveal(ctx)
	draw(ctx.fighter, ctx.runtime)
	return wasVeiled
end

-- Momentum Continuation -------------------------------------------------------------
-- A slash projectile or flurry opens a short window for Follow Through, which
-- dashes along the slash's path. One follow per slash.

local function openFollow(ctx, from: Vector3, direction: Vector3, length: number)
	local follow = Powers.abilityFor(ctx.power, "FollowThrough", ctx.degree)
	local record = {
		untilAt = ctx:now() + (if follow then follow.window else DEFAULT_FOLLOW_WINDOW),
		direction = direction,
		to = from + direction * length,
		target = nil :: any,
		projectile = nil :: any,
	}
	ctx.data.follow = record
	return record
end

-- Hooks --------------------------------------------------------------------------------

function Ghost.canUse(_, runtime, def)
	if def.id == "FollowThrough" then
		local follow = runtime.data.follow
		if not follow or now() > follow.untilAt then
			return false, "No slash to follow"
		end
	end
	return true
end

function Ghost.tick(fighter, runtime, _, ctx)
	local time = now()
	local attack = fighter.state.attack
	-- Basic katana swings draw the blade (and attacking ends the veil)
	if attack and time < attack.recoveryEnd and (attack.kind == "Light" or attack.kind == "Heavy") then
		unsheathe(ctx)
	end
	local drawnUntil = runtime.data.drawnUntil
	if drawnUntil and time >= drawnUntil then
		runtime.data.drawnUntil = nil
		setPhase(fighter, 0)
	end
end

function Ghost.onHit(_, _, _, _, _, ctx)
	unsheathe(ctx)
end

function Ghost.onHurt(_, _, _, _, _, ctx)
	reveal(ctx)
end

-- His dodges leave a dark afterimage
function Ghost.onDodge(_, _, ctx)
	ctx:fx("PhaseDodge", {})
end

-- Degree 1: Phantom Blade ----------------------------------------------------------------

function abilities.InstantDraw(ctx)
	local def = ctx.def
	local ambush = unsheathe(ctx) and def.ambush > 1
	ctx:fx("InstantDrawWindup", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local origin = ctx:origin()
	local direction = ctx.direction
	local targets = ctx:inArc(def.range, def.arc, origin, direction)
	ctx:dash(direction * (def.lunge / def.active), def.active)
	ctx:fx("InstantDraw", { origin = origin, direction = direction, range = def.range, landed = #targets > 0, ambush = ambush })
	local spec = def
	if ambush then
		spec = table.clone(def)
		spec.damage = def.damage * def.ambush
	end
	if ctx:hitAll(targets, spec, { direction = direction }) == 0 then
		ctx:extendRecovery(def.whiffRecovery)
	end
end

function abilities.SpectralDash(ctx)
	local def = ctx.def
	ctx:fx("SpectralDash", { duration = def.startup + def.active, direction = ctx.direction })
	if not ctx:waitActive() then
		return
	end
	ctx:dash(ctx.direction * def.speed, def.active)
	local endsAt = ctx:now() + def.active
	while ctx:now() < endsAt do
		if not ctx:alive() then
			-- Knocked out of it: stop at once so knockback isn't fought
			ctx:stopDash()
			return
		end
		task.wait(0.05)
	end
	ctx:stopDash()
end

function abilities.PhantomVeil(ctx)
	local def = ctx.def
	ctx:fx("VeilWindup", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local me = ctx.fighter
	-- Both end on their own (StatusService caps them) or the moment he attacks or is hit
	ctx:status(me, "Concealed", def.duration, { magnitude = def.transparency })
	ctx:status(me, "Haste", def.duration, { magnitude = def.haste })
	ctx.data.veilHaste = true
	ctx:fx("Veil", { duration = def.duration })
end

-- Which incoming hits the spectral counter answers: small or melee ones,
-- never grabs or massive attacks
local function counterable(opts): boolean
	local tags = opts.tags or {}
	if table.find(tags, "Grab") or table.find(tags, "Massive") then
		return false
	end
	return opts.kind == "Light" or opts.kind == "Heavy" or table.find(tags, "Small") ~= nil or table.find(tags, "Melee") ~= nil
end

function abilities.SpectralCounter(ctx)
	local def = ctx.def
	local window = def.startup + def.active
	local windowEnds = ctx:now() + window
	local stopStance = ctx:lastingFx("CounterStance", window, {})
	local attacker = nil
	ctx:openCounter(window, function(_, _, opts)
		return attacker == nil and counterable(opts)
	end, function(by)
		-- Can't yield inside a hit: the strike happens below
		attacker = by
		return { negate = true, result = "Countered" }
	end)
	while attacker == nil and ctx:now() < windowEnds do
		if not ctx:alive() then
			stopStance()
			return
		end
		task.wait(SCAN_STEP)
	end
	stopStance()
	if attacker == nil then
		-- Too early or too late: nothing happens, and the stance's recovery leaves him open
		ctx:fx("CounterWhiff", {})
		return
	end

	local from = ctx:origin()
	if not ctx:isEnemy(attacker) then
		ctx:finish()
		return
	end
	unsheathe(ctx)
	local attackerAt = attacker.root.Position
	if flat(attackerAt - from).Magnitude > def.counterRange then
		-- Too far to strike back (a small projectile): a spectral sidestep instead
		local side = Vector3.new(-ctx.direction.Z, 0, ctx.direction.X)
		local ok, where = ctx:teleport(from + side * def.evade, { maxDistance = def.evade + 1 })
		ctx:fx("CounterEvade", { from = from, to = if ok then where else from })
		ctx:finish()
		return
	end
	-- Phase behind the attacker (a validated spot) and cut
	local theirFacing = Hitbox.flatDirection(attacker.root.CFrame.LookVector) or Hitbox.flatDirection(attackerAt - from) or ctx.direction
	local behind = attackerAt - theirFacing * def.behind
	local ok, where = ctx:teleport(behind, { maxDistance = def.counterRange + def.behind + 2, facing = attackerAt - behind })
	local strikeFrom = if ok and where then where else from
	local toward = Hitbox.flatDirection(attackerAt - strikeFrom) or ctx.direction
	ctx:fx("CounterStrike", { from = from, to = strikeFrom, target = attacker.model, direction = toward })
	if (attackerAt - strikeFrom).Magnitude <= def.behind + 4 then
		ctx:hit(attacker, nil, { direction = toward, origin = strikeFrom, noDefense = true })
	end
	ctx:finish()
end

-- Degree 2: Shadow Step ----------------------------------------------------------------

function abilities.ShadowStep(ctx)
	local def = ctx.def
	local origin = ctx:origin()
	local wanted = ctx.point or (origin + ctx.direction * def.range)
	local offset = flat(wanted - origin)
	if offset.Magnitude > def.range then
		wanted = origin + offset.Unit * def.range
	end
	-- Never on top of someone: land just short of them
	for _, enemy in ctx:enemies() do
		local enemyAt = enemy.root.Position
		if flat(wanted - enemyAt).Magnitude < def.personalSpace then
			local back = Hitbox.flatDirection(origin - enemyAt) or -ctx.direction
			wanted = enemyAt + back * def.personalSpace
		end
	end
	ctx:fx("ShadowStepMark", { position = groundAt(ctx, wanted), duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local from = ctx:origin()
	local facing = Hitbox.flatDirection(wanted - from) or ctx.direction
	-- Safe ground inside the arena, nearest the aimed spot (or nothing at all)
	local ok, where = ctx:teleport(wanted, { maxDistance = def.range, facing = facing })
	if not ok or not where then
		ctx:refund(1)
		ctx:fx("ShadowStepFail", { position = from })
		ctx:finish()
		return
	end
	ctx:fx("ShadowStep", { from = from, to = where })
	local slash = def.arrivalSlash
	if slash then
		unsheathe(ctx)
		ctx:fx("ShadowSlash", { position = where, radius = slash.radius })
		for _, target in ctx:inSphere(where, slash.radius) do
			ctx:hit(target, slash, { tags = CUT_TAGS, origin = where })
		end
	end
end

function abilities.SlashWave(ctx)
	local def = ctx.def
	unsheathe(ctx)
	ctx:fx("SlashWaveWindup", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local origin = ctx:origin() + Vector3.new(0, 0.5, 0)
	local forward = ctx.direction
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local follow = openFollow(ctx, origin, forward, def.range)
	local crossing = origin + forward * def.crossAt
	for index = 1, def.count do
		local side = (index - (def.count + 1) / 2) * def.spacing
		local start = origin + forward * 1.5 + right * side
		local direction = if side == 0 then forward else (crossing - start).Unit
		local projectile = ctx:projectile({
			visual = "SlashWave",
			origin = start,
			direction = direction,
			speed = def.speed,
			radius = def.radius,
			lifetime = def.lifetime,
			range = def.range,
			redirectable = true,
			interceptable = true,
			-- Crossing slashes lean opposite ways, so their paths read as an X
			data = { tilt = if side < 0 then 35 elseif side > 0 then -35 else 0, width = def.radius * 2.4 },
			onHit = function(_, target)
				follow.target = target
				follow.to = target.root.Position
			end,
			onEnd = function(_, position)
				if not follow.target then
					follow.to = position
				end
			end,
		})
		if projectile and not follow.projectile then
			follow.projectile = projectile
		end
	end
	ctx:fx("SlashWaveRelease", { direction = forward })
end

function abilities.SlashFlurry(ctx)
	local def = ctx.def
	unsheathe(ctx)
	ctx:fx("FlurryWindup", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local finalSpec = table.clone(def)
	finalSpec.knockback = def.finalKnockback
	finalSpec.launch = def.finalLaunch
	local start = ctx:activeAt()
	local lastHit = nil
	for index = 1, def.sweeps do
		if index > 1 and not ctx:waitUntil(start + (index - 1) * def.interval) then
			return
		end
		local pattern = def.patterns[(index - 1) % #def.patterns + 1]
		local final = index == def.sweeps
		-- Each sweep's damaging region is exactly the arc drawn for it
		ctx:fx("FlurrySweep", { index = index, tilt = pattern.tilt, arc = pattern.arc, range = pattern.range, final = final })
		for _, target in ctx:inArc(pattern.range, pattern.arc) do
			local outcome = ctx:hit(target, if final then finalSpec else def, { direction = ctx.direction })
			if outcome and outcome.result == "Hit" then
				lastHit = target
			end
		end
	end
	local follow = openFollow(ctx, ctx:origin(), ctx.direction, def.patterns[1].range + 6)
	if lastHit then
		follow.target = lastHit
		follow.to = lastHit.root.Position
	end
end

function abilities.FollowThrough(ctx)
	local def = ctx.def
	local follow = ctx.data.follow
	-- One follow per slash
	ctx.data.follow = nil
	if not follow then
		ctx:refund(1)
		return
	end
	unsheathe(ctx)
	ctx:fx("FollowWindup", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	-- Behind the slash: the fighter it hit, else where it is now, else where it ended
	local origin = ctx:origin()
	local goal = follow.to
	if follow.target and ctx:isEnemy(follow.target) then
		goal = follow.target.root.Position
	elseif follow.projectile and follow.projectile.alive then
		goal = follow.projectile.position
	end
	local offset = flat(goal - origin)
	local direction = Hitbox.flatDirection(offset) or follow.direction
	local distance = math.clamp(offset.Magnitude, 4, def.range)
	local duration = math.clamp(distance / def.speed, 0.08, def.active)
	ctx:dash(direction * def.speed, duration)
	ctx:fx("FollowDash", { from = origin, direction = direction, distance = distance, duration = duration })
	-- Stop at the first opponent in the way (walls stop the dash itself)
	local endsAt = ctx:now() + duration
	local victim = nil
	while ctx:now() < endsAt and ctx:alive() do
		local found = ctx:inSphere(ctx:origin() + direction * 2, def.width / 2 + 0.5)
		if #found > 0 then
			victim = found[1]
			break
		end
		task.wait(SCAN_STEP)
	end
	ctx:stopDash()
	if not ctx:alive() then
		return
	end
	local targets = ctx:inArc(4.5, 120, nil, direction)
	if victim and not table.find(targets, victim) then
		table.insert(targets, victim)
	end
	if #targets == 0 then
		ctx:extendRecovery(def.whiffRecovery)
		return
	end
	ctx:fx("FollowStrike", { position = ctx:origin() + direction * 2, direction = direction })
	ctx:hitAll(targets, nil, { direction = direction })
	ctx:finish()
end

-- Degree 3: Spectral Executioner ----------------------------------------------------------

function abilities.ConvergingGrid(ctx)
	local def = ctx.def
	local origin = ctx:origin()
	local wanted = ctx.point or (origin + ctx.direction * 14)
	local offset = flat(wanted - origin)
	if offset.Magnitude > def.range then
		wanted = origin + offset.Unit * def.range
	end
	local center = groundAt(ctx, wanted)
	-- No grids behind walls
	if not ctx:lineOfSight(origin, center + Vector3.new(0, 3, 0)) then
		ctx:refund(1)
		ctx:fx("GridFizzle", { center = center })
		ctx:finish()
		return
	end
	unsheathe(ctx)
	local yaw = math.atan2(ctx.direction.X, ctx.direction.Z)
	-- Everyone near the area gets the dodge/block prompt
	ctx:telegraph(ctx:inSphere(center, def.radius + 3, def.clearance), ctx:activeAt())
	ctx:fx("GridMark", { center = center, radius = def.radius, lines = def.lines, yaw = yaw, duration = def.startup })
	if not ctx:waitActive() then
		ctx:fx("GridFizzle", { center = center })
		return
	end
	ctx:fx("GridStrike", { center = center, radius = def.radius, lines = def.lines, yaw = yaw })
	-- Only those still inside the circle when the slashes cross
	for _, target in ctx:inSphere(center, def.radius, def.clearance) do
		ctx:hit(target, nil, { origin = center, direction = Hitbox.flatDirection(target.root.Position - center) })
	end
end

-- Ultimate ---------------------------------------------------------------------------------

function abilities.SpectralSeverance(ctx)
	local def = ctx.def
	unsheathe(ctx)
	local origin = ctx:origin()
	local target = ctx:nearestEnemy(def.range, 120) or ctx:nearestEnemy(def.range)
	local anchor = if target then target.root.Position else origin + ctx.direction * 10
	local finalAt = ctx:activeAt() + def.passes * def.passInterval
	-- The timing bar is for the final strike; the afterimage cuts are small, blockable hits
	ctx:telegraph(ctx:inSphere(origin, def.range + 4), finalAt)
	ctx:fx("SeveranceWindup", { duration = def.startup, anchor = anchor, passes = def.passes })
	if not ctx:waitActive() then
		ctx:fx("SeveranceFizzle", {})
		return
	end
	-- The cuts cross where the target stood when the sequence began
	if target and ctx:isEnemy(target) then
		anchor = target.root.Position
	end
	local baseYaw = math.atan2(ctx.direction.X, ctx.direction.Z)
	local start = ctx:activeAt()
	for index = 1, def.passes do
		if index > 1 and not ctx:waitUntil(start + (index - 1) * def.passInterval) then
			return
		end
		local yaw = baseYaw + math.pi * (index - 0.5) / def.passes
		local along = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
		local from = anchor - along * def.passLength / 2
		ctx:fx("SeverancePass", { from = from, to = anchor + along * def.passLength / 2, index = index })
		for _, enemy in ctx:alongLine(from, along, def.passLength, def.passWidth) do
			ctx:hit(enemy, def.pass, { direction = along, origin = from, tags = CUT_TAGS, noDefense = true })
		end
	end
	if not ctx:waitUntil(finalAt) then
		return
	end

	-- Final strike: appear behind the target (a validated spot) and cut through
	local strikeFrom = ctx:origin()
	local facing = ctx.direction
	if target and ctx:isEnemy(target) then
		local targetAt = target.root.Position
		if (targetAt - strikeFrom).Magnitude <= def.range + 6 and ctx:lineOfSight(strikeFrom, targetAt) then
			local approach = Hitbox.flatDirection(targetAt - strikeFrom) or ctx.direction
			local ok, where = ctx:teleport(targetAt + approach * 3, { maxDistance = def.range + 10, facing = -approach })
			if ok and where then
				strikeFrom = where
				facing = Hitbox.flatDirection(targetAt - where) or -approach
			else
				facing = approach
			end
		end
	end
	ctx:fx("SeveranceStrike", { from = origin, to = strikeFrom, direction = facing, range = def.strikeRange })
	for _, enemy in ctx:inArc(def.strikeRange, def.strikeArc, strikeFrom, facing) do
		ctx:hit(enemy, nil, { direction = facing, origin = strikeFrom })
	end
end

return Ghost
