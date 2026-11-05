-- Corruption's abilities on the server (PROGRAMME ECLIPSE): void strikes and
-- shards that leave Corruption Marks, static that distorts and breaks small
-- projectiles, rift blinks, unstable floors and distortion zones at range,
-- reflections that walk off and burst, Unravel (detonates the marks), the
-- Cataclysm ring, and Total System Corruption, a timed final form that ends
-- in a collapse.
--
-- The Corruption meter (0-100) grows from landing hits and using abilities,
-- never from moving, and drains out of combat. It drives the visual overwrite:
-- the Phase attribute (0..1) is published from the degree and the meter, and is
-- 1 during the final form. A high meter leaves the fighter exposed (Vulnerable).
-- Numbers come from Shared/Powers/Corruption.luau (scaled by degree).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local AbilityKit = require(script.Parent.Parent.Combat.AbilityKit)

local Attribute = Protocol.Attribute

local POWER_ID = "Corruption"
local DEF = Powers.get(POWER_ID)
local METER = DEF.resource
local OVERWRITE = DEF.overwrite
local MARK = DEF.mark
local FORM_ATTRIBUTE = DEF.attributes.form
local LOCK_ATTRIBUTE = DEF.attributes.lock
local ULTIMATE = "TotalSystemCorruption"

-- How often the exposure status is refreshed while it applies, and for how long
local EXPOSURE_REFRESH = 0.4
local EXPOSURE_LENGTH = 0.6
-- How often a lasting zone's statuses are refreshed on someone inside, and for how long
local ZONE_STATUS = 0.5
-- Warn those near a reflection this long before it bursts
local PHANTASM_WARNING = 0.7
-- Most a thrown shard can aim up or down (degrees)
local MAX_PITCH = 20

local Corruption = {}
local abilities = {}
Corruption.abilities = abilities

local services: any = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

function Corruption.init(allServices)
	services = allServices
end

-- World queries ---------------------------------------------------------------------------

local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude
worldParams.RespectCanCollide = true

local function ignoreFighters()
	local ignore = {}
	for _, fighter in services.CharacterService:all() do
		table.insert(ignore, fighter.model)
	end
	for _, name in { "SNEffects", "SNLocalDebris" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	worldParams.FilterDescendantsInstances = ignore
end

-- How far something can travel from `from` along `direction` before a wall
local function clearLength(from: Vector3, direction: Vector3, length: number): number
	ignoreFighters()
	local result = workspace:Raycast(from, direction * length, worldParams)
	return if result then math.max(0, (result.Position - from).Magnitude - 1.5) else length
end

-- The floor under a point (or the point itself, lowered to foot height)
local function groundAt(point: Vector3): Vector3
	ignoreFighters()
	local result = workspace:Raycast(point + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), worldParams)
	return if result then result.Position else point - Vector3.new(0, 3, 0)
end

local function groundBelow(ctx): Vector3
	return groundAt(ctx:origin())
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function turned(direction: Vector3, degrees: number): Vector3
	return CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(direction)
end

local function awayFrom(center: Vector3, target): Vector3?
	return Hitbox.flatDirection(target.root.Position - center)
end

-- Where a placed zone goes: the aim point (within range, on this side of any
-- wall), or straight ahead
local function placeAt(ctx, range: number, fallback: number): Vector3
	local origin = ctx:origin()
	local offset = if ctx.point then flat(ctx.point - origin) else ctx.direction * fallback
	if offset.Magnitude > range then
		offset = offset.Unit * range
	end
	if offset.Magnitude > 0.5 then
		offset = offset.Unit * clearLength(origin, offset.Unit, offset.Magnitude)
	end
	local spot = origin + offset
	local match = services.MatchService:getMatchOf(ctx.fighter)
	if match and match.arena then
		spot = services.ArenaService:clampInside(match.arena, spot, 2)
	end
	return groundAt(spot)
end

-- Where a shard flies: at the aim point if there is one, within a sensible pitch
local function aimFrom(ctx, from: Vector3): Vector3
	local flatDirection = ctx.direction
	local target = ctx.point
	if not target then
		return flatDirection
	end
	local toPoint = target - from
	local horizontal = flat(toPoint).Magnitude
	if horizontal < 1 then
		return flatDirection
	end
	local pitch = math.clamp(math.deg(math.atan2(toPoint.Y, horizontal)), -MAX_PITCH, MAX_PITCH)
	local along = Hitbox.flatDirection(toPoint) or flatDirection
	return (along * math.cos(math.rad(pitch)) + Vector3.new(0, math.sin(math.rad(pitch)), 0)).Unit
end

-- The meter and the overwrite -----------------------------------------------------------------

-- A cast that outlives a reset (match end, respawn) holds the old life's data;
-- it mustn't fill the new meter or touch the new form
local function stillCurrent(ctx): boolean
	local runtime = ctx.runtime
	return runtime ~= nil and ctx.fighter.power == runtime and runtime.data == ctx.data
end

local function formActive(data): boolean
	return (data.formUntil or 0) > now()
end

local function locked(data): boolean
	return (data.lockedUntil or 0) > now()
end

local function ultimateOf(runtime)
	return Powers.abilityFor(POWER_ID, ULTIMATE, runtime.degree)
end

-- The overwrite this fighter shows: their degree's start plus the meter's share
-- of the span above it (stepped, so the attribute doesn't change every tick)
function Corruption.phaseFor(degree: number, meter: number, maxMeter: number, inForm: boolean): number
	if inForm then
		return 1
	end
	local base = OVERWRITE.base[math.clamp(degree, 1, #OVERWRITE.base)]
	local share = if maxMeter > 0 then math.clamp(meter / maxMeter, 0, 1) else 0
	local value = base + OVERWRITE.span * share
	return math.clamp(math.floor(value / OVERWRITE.step + 0.5) * OVERWRITE.step, 0, 1)
end

local function publish(fighter, runtime)
	local data = runtime.data
	local shown = Corruption.phaseFor(runtime.degree, runtime.resource, runtime.resourceMax, formActive(data))
	if shown ~= data.shownPhase and fighter.model.Parent then
		data.shownPhase = shown
		fighter.model:SetAttribute(Attribute.Phase, shown)
	end
end

-- Adds Corruption (not while the final form pins it, nor while it's locked after)
local function fill(fighter, runtime, amount: number)
	local data = runtime.data
	data.activeAt = now()
	if amount <= 0 or formActive(data) or locked(data) then
		return
	end
	services.PowerService:gain(fighter, amount)
	publish(fighter, runtime)
end

-- Every cast: the meter grows (for the abilities that build it), the
-- out-of-combat clock restarts, and in the final form the ability recharges faster
local function begin(ctx)
	if not stillCurrent(ctx) then
		return
	end
	local def = ctx.def
	fill(ctx.fighter, ctx.runtime, def.charge or 0)
	if formActive(ctx.data) and def.kind ~= "Ultimate" then
		local form = ultimateOf(ctx.runtime)
		local length = services.PowerService:cooldownFor(ctx.fighter, def) * form.cooldownScale
		services.PowerService:setCooldown(ctx.fighter, def.id, now() + length)
	end
	publish(ctx.fighter, ctx.runtime)
end

local function empowered(ctx): boolean
	return stillCurrent(ctx) and formActive(ctx.data)
end

-- The numbers to hit with: stronger in the final form
local function strength(ctx, source: { [string]: any }?): { [string]: any }
	local spec = source or ctx.def
	if not empowered(ctx) then
		return spec
	end
	local copy = table.clone(spec)
	copy.damage = (copy.damage or 0) * ultimateOf(ctx.runtime).damageScale
	return copy
end

local function landed(outcome): boolean
	return outcome ~= nil and (outcome.result == "Hit" or outcome.result == "GuardBreak")
end

-- Marks and distortion --------------------------------------------------------------------------

-- Puts Corruption Marks on a target (they stack up to the degree's limit and
-- fade on their own; Unravel detonates them)
local function mark(ctx, target, stacks: number?)
	if not stillCurrent(ctx) or not services.CharacterService:isAlive(target) then
		return
	end
	local data = ctx.data
	data.marks = data.marks or {}
	local limit = MARK.maxStacks[math.clamp(ctx.degree, 1, #MARK.maxStacks)]
	local time = now()
	local entry = data.marks[target.id]
	if not entry or entry.expiresAt <= time or entry.target ~= target then
		entry = { target = target, stacks = 0, expiresAt = 0 }
	end
	entry.stacks = math.min(limit, entry.stacks + (stacks or 1))
	entry.expiresAt = time + MARK.duration
	data.marks[target.id] = entry
	ctx:status(target, "Mark", MARK.duration, { magnitude = entry.stacks, data = { power = POWER_ID, stacks = entry.stacks } })
	ctx:fx("MarkApplied", { target = target.model, stacks = entry.stacks, duration = MARK.duration })
end

local function distort(ctx, target, seconds: number?)
	if seconds and seconds > 0 then
		ctx:status(target, "Distort", seconds)
	end
end

-- Hits, then marks and distorts if it connected
local function strike(ctx, target, spec: { [string]: any }?, extra: { [string]: any }?)
	local source = spec or ctx.def
	local outcome = ctx:hit(target, strength(ctx, source), extra)
	if landed(outcome) then
		if source.markStacks then
			mark(ctx, target, source.markStacks)
		end
		distort(ctx, target, source.distort)
	end
	return outcome
end

-- Can corruption unmake this projectile? Small enemy ones only: never massive
-- ones or ones marked interceptable = false
local function unmakeable(ctx, projectile): boolean
	if not projectile.alive or projectile.ownerId == ctx.fighter.id or not ctx:isEnemy(projectile.owner) then
		return false
	end
	local spec = projectile.spec
	local tags = spec.tags
	if spec.interceptable == false or (tags ~= nil and table.find(tags, "Massive") ~= nil) then
		return false
	end
	return spec.interceptable == true or (tags ~= nil and table.find(tags, "Small") ~= nil)
end

-- Breaks up to `most` small enemy projectiles near `center`; returns how many
local function destabilize(ctx, center: Vector3, radius: number, most: number): number
	local found = services.ProjectileService:nearby(center, radius, function(projectile)
		return unmakeable(ctx, projectile)
	end)
	table.sort(found, function(a, b)
		return (a.position - center).Magnitude < (b.position - center).Magnitude
	end)
	local positions = {}
	for index, projectile in found do
		if index > most then
			break
		end
		table.insert(positions, projectile.position)
		services.ProjectileService:finish(projectile, "Intercepted")
	end
	if #positions > 0 then
		ctx:fx("ShotsUnmade", { positions = positions })
	end
	return #positions
end

-- Hooks ------------------------------------------------------------------------------------------

local function fresh(fighter, runtime)
	local data = runtime.data
	data.activeAt = now()
	data.formUntil = nil
	data.lockedUntil = nil
	data.marks = {}
	data.shownPhase = nil
	if fighter.model.Parent then
		fighter.model:SetAttribute(FORM_ATTRIBUTE, nil)
		fighter.model:SetAttribute(LOCK_ATTRIBUTE, nil)
	end
	publish(fighter, runtime)
end

function Corruption.onEquip(fighter, runtime)
	fresh(fighter, runtime)
end

function Corruption.onReset(fighter, runtime)
	fresh(fighter, runtime)
end

function Corruption.tick(fighter, runtime, dt: number)
	local data = runtime.data
	local time = now()
	if formActive(data) then
		-- The final form runs at full output
		runtime.resource = runtime.resourceMax
	elseif locked(data) then
		runtime.resource = 0
	elseif runtime.resource > 0 and time - (data.activeAt or time) >= METER.decayAfter then
		runtime.resource = math.max(0, runtime.resource - METER.decay * dt)
	end
	-- Fully overwritten is fully exposed: everyone can see it, and it takes more damage
	if (formActive(data) or runtime.resource >= METER.exposedAt) and (data.exposedRefresh or 0) <= time then
		data.exposedRefresh = time + EXPOSURE_REFRESH
		services.StatusService:apply(fighter, "Vulnerable", EXPOSURE_LENGTH, { magnitude = METER.exposure, source = fighter })
	end
	publish(fighter, runtime)
end

-- Landing hits feeds the meter (lasting zones' ticks don't)
function Corruption.onHit(attacker, _target, _outcome, opts, runtime)
	if opts.kind == "Zone" then
		return
	end
	fill(attacker, runtime, METER.hitGain)
end

-- The final form makes every ability free
function Corruption.costFor(_fighter, runtime, def): number
	if def.kind ~= "Ultimate" and formActive(runtime.data) then
		return 0
	end
	return def.cost or 0
end

-- The ultimate needs Corruption on top of a full charge, and can't stack on itself
function Corruption.canUse(_fighter, runtime, def)
	if def.kind == "Ultimate" then
		if formActive(runtime.data) then
			return false, "Already in the final form"
		end
		if def.meterNeeded and runtime.resource + 1e-6 < def.meterNeeded then
			return false, `Needs {def.meterNeeded} Corruption`
		end
	end
	return true
end

-- Degree 1: Awakening ---------------------------------------------------------------------------

function abilities.VoidStrike(ctx)
	local def = ctx.def
	begin(ctx)
	ctx:fx("VoidStrikeWindup", { duration = def.startup, range = def.range })
	if not ctx:waitActive() then
		return
	end
	local origin = ctx:origin()
	local length = math.min(def.range, clearLength(origin, ctx.direction, def.range) + 1)
	ctx:fx("VoidStrike", { origin = groundBelow(ctx), direction = ctx.direction, length = length, width = def.width })
	for _, target in ctx:alongLine(origin, ctx.direction, length, def.width) do
		strike(ctx, target, nil, { direction = ctx.direction })
	end
end

local function throwShard(ctx, from: Vector3, direction: Vector3)
	local def = ctx.def
	local hitSpec = strength(ctx)
	ctx:projectile({
		visual = "VoidShard",
		origin = from,
		direction = direction,
		speed = def.speed,
		radius = def.radius,
		lifetime = def.lifetime,
		range = def.range,
		hit = AbilityKit.hitFrom(hitSpec),
		interceptable = true,
		data = { empowered = empowered(ctx) },
		onHit = function(_, target, outcome)
			if landed(outcome) then
				mark(ctx, target, def.markStacks)
			end
		end,
	})
end

function abilities.CorruptBolt(ctx)
	local def = ctx.def
	begin(ctx)
	ctx:fx("ShardWindup", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local from = ctx:origin() + Vector3.new(0, 1.2, 0) + ctx.direction * 1.5
	local direction = aimFrom(ctx, from)
	if empowered(ctx) then
		-- The final form throws a fan of shards
		local shards = math.max(1, def.formShards)
		for index = 1, shards do
			local angle = (index - (shards + 1) / 2) * def.formSpread
			throwShard(ctx, from, turned(direction, angle))
		end
	else
		throwShard(ctx, from, direction)
	end
end

function abilities.StaticBurst(ctx)
	local def = ctx.def
	begin(ctx)
	ctx:fx("StaticGather", { duration = def.startup, radius = def.radius })
	if not ctx:waitActive() then
		return
	end
	local center = ctx:origin()
	ctx:fx("StaticBurst", { position = groundBelow(ctx), radius = def.radius })
	destabilize(ctx, center, def.destabilize, def.breaks)
	for _, target in ctx:inSphere(center, def.radius) do
		strike(ctx, target, nil, { direction = awayFrom(center, target), origin = center })
	end
end

-- Degree 2: Corruption ---------------------------------------------------------------------------

function abilities.RiftBlink(ctx)
	local def = ctx.def
	begin(ctx)
	local from = ctx:origin()
	local direction = ctx.direction
	-- CPU opponents blink out of trouble (away from who they're facing)
	if ctx.fighter.npc then
		direction = turned(-direction, if math.random() < 0.5 then 35 else -35)
	end
	local desired = if ctx.point and not ctx.fighter.npc then ctx.point else from + direction * def.distance
	ctx:fx("RiftDissolve", { duration = def.startup, position = from })
	if not ctx:waitActive() then
		return
	end
	local ok, where = ctx:teleport(desired, { maxDistance = def.distance, facing = direction })
	if not ok or not where then
		-- Nowhere safe to land: the static settles back and nothing is spent
		ctx:fx("RiftBlinkFail", { position = from })
		ctx:refund(1)
		return
	end
	ctx:fx("RiftArrive", { from = from, to = where })
	-- The rift left where they stood bursts a moment later
	local rift = groundAt(from)
	ctx:fx("RiftOpen", { position = rift, radius = def.radius, fuse = def.fuse })
	task.delay(def.fuse, function()
		if not stillCurrent(ctx) or not services.CharacterService:isAlive(ctx.fighter) then
			return
		end
		ctx:fx("RiftBurst", { position = rift, radius = def.radius })
		for _, target in ctx:inSphere(from, def.radius) do
			strike(ctx, target, nil, { direction = awayFrom(from, target), origin = from })
		end
	end)
end

function abilities.UnstableGround(ctx)
	local def = ctx.def
	begin(ctx)
	local center = placeAt(ctx, def.range, math.min(def.range, 14))
	ctx:fx("GroundCrack", { duration = def.startup, target = center, radius = def.radius })
	if not ctx:waitActive() then
		return
	end
	-- One unstable floor at a time: a new one replaces the old
	local data = ctx.data
	if data.groundStop then
		data.groundStop()
	end
	local armedAt = now() + def.arm
	local lastHit: { [string]: number } = {}
	local lastSlow: { [string]: number } = {}
	local spec = strength(ctx)
	-- Measured from the floor: a jump clears it for a moment
	local stop = ctx:zone({
		center = center,
		radius = def.radius,
		duration = def.duration,
		tick = def.tick,
		clearance = 2,
		fx = "UnstableGround",
		fxData = { arm = def.arm, floor = center },
		onTick = function(targets)
			local time = now()
			if time < armedAt then
				return
			end
			for _, target in targets do
				if time - (lastSlow[target.id] or -math.huge) >= ZONE_STATUS then
					lastSlow[target.id] = time
					ctx:status(target, "Slow", ZONE_STATUS + 0.25, { magnitude = def.slow })
				end
				if time - (lastHit[target.id] or -math.huge) >= def.hitEvery then
					lastHit[target.id] = time
					ctx:hit(target, spec, { kind = "Zone", origin = center })
				end
			end
		end,
	})
	data.groundStop = function()
		data.groundStop = nil
		stop()
	end
end

function abilities.DistortionPulse(ctx)
	local def = ctx.def
	begin(ctx)
	ctx:telegraph(ctx:inSphere(groundBelow(ctx), def.radius + 4, def.jumpClearance), ctx:activeAt())
	ctx:fx("PulseWindup", { duration = def.startup, radius = def.radius })
	if not ctx:waitActive() then
		return
	end
	-- A ground wave: measured from the floor, so a well-timed jump clears it
	local center = groundBelow(ctx)
	ctx:fx("DistortionPulse", { position = center, radius = def.radius })
	destabilize(ctx, ctx:origin(), def.destabilize, def.breaks)
	for _, target in ctx:inSphere(center, def.radius, def.jumpClearance) do
		strike(ctx, target, nil, { direction = awayFrom(center, target), origin = center })
	end
end

-- Marked opponents Unravel can reach: alive, in range and in sight
local function markedTargets(ctx, range: number): { { target: any, stacks: number } }
	local list = {}
	local marks = ctx.data.marks
	if not marks then
		return list
	end
	local time = now()
	local eye = ctx:origin() + Vector3.new(0, 1.5, 0)
	for id, entry in marks do
		local target = entry.target
		if entry.expiresAt <= time or not ctx:isEnemy(target) or not ctx:hasStatus(target, "Mark") then
			marks[id] = nil
		elseif (target.root.Position - ctx:origin()).Magnitude <= range and ctx:lineOfSight(eye, target.root.Position) then
			table.insert(list, { target = target, stacks = entry.stacks })
		end
	end
	return list
end

function abilities.Unravel(ctx)
	local def = ctx.def
	begin(ctx)
	local marked = markedTargets(ctx, def.range)
	if #marked == 0 then
		-- Nothing to unravel: half back
		ctx:fx("UnravelFizzle", {})
		ctx:refund(0.5)
		return
	end
	local threatened = {}
	local models = {}
	for _, entry in marked do
		table.insert(threatened, entry.target)
		table.insert(models, entry.target.model)
	end
	ctx:telegraph(threatened, ctx:activeAt())
	ctx:fx("UnravelWindup", { duration = def.startup, targets = models })
	if not ctx:waitActive() then
		return
	end
	-- Marks are read again at the moment of detonation (they may have faded or been cleared)
	local center = ctx:origin()
	for _, entry in markedTargets(ctx, def.range + 4) do
		local target = entry.target
		local spec = table.clone(def)
		spec.damage = def.damage + def.perStack * entry.stacks
		ctx:fx("UnravelDetonate", { target = target.model, stacks = entry.stacks, from = center })
		ctx.data.marks[target.id] = nil
		ctx:clearStatus(target, "Mark")
		ctx:hit(target, strength(ctx, spec), { direction = awayFrom(center, target), origin = target.root.Position })
	end
end

-- Degree 3: Absolute Corruption ------------------------------------------------------------------

function abilities.DistortionZone(ctx)
	local def = ctx.def
	begin(ctx)
	local floor = placeAt(ctx, def.range, math.min(def.range, 12))
	ctx:fx("ZoneFold", { duration = def.startup, target = floor, radius = def.radius })
	if not ctx:waitActive() then
		return
	end
	local data = ctx.data
	if data.zoneStop then
		data.zoneStop()
	end
	local center = floor + Vector3.new(0, 3, 0)
	local lastHit: { [string]: number } = {}
	local lastStatus: { [string]: number } = {}
	local spec = strength(ctx)
	local stop = ctx:zone({
		center = center,
		radius = def.radius,
		duration = def.duration,
		tick = def.tick,
		fx = "DistortionZone",
		fxData = { floor = floor },
		onTick = function(targets)
			local time = now()
			destabilize(ctx, center, def.destabilize, def.breaks)
			for _, target in targets do
				if time - (lastStatus[target.id] or -math.huge) >= ZONE_STATUS then
					lastStatus[target.id] = time
					ctx:status(target, "Distort", def.distort + ZONE_STATUS)
					ctx:status(target, "Vulnerable", def.distort + ZONE_STATUS, { magnitude = def.exposure })
				end
				if time - (lastHit[target.id] or -math.huge) >= def.hitEvery then
					lastHit[target.id] = time
					ctx:hit(target, spec, { kind = "Zone", origin = center })
				end
			end
		end,
	})
	data.zoneStop = function()
		data.zoneStop = nil
		stop()
	end
end

function abilities.Phantasm(ctx)
	local def = ctx.def
	begin(ctx)
	ctx:fx("PhantasmSplit", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local me = ctx.fighter
	local origin = ctx:origin()
	-- The real one fades and quickens while the reflections walk away
	ctx:status(me, "Concealed", def.fadeTime, { magnitude = def.fade })
	ctx:status(me, "Haste", def.fadeTime, { magnitude = def.haste })
	local copies = {}
	for index = 1, def.copies do
		local side = if index % 2 == 1 then 1 else -1
		local direction = turned(ctx.direction, side * def.spread * math.ceil(index / 2))
		local length = clearLength(origin, direction, def.walkSpeed * def.fuse)
		table.insert(copies, { from = origin, to = origin + direction * length })
	end
	local startedAt = now()
	local burstAt = startedAt + def.fuse
	ctx:lastingFx("Phantasm", def.fuse + 0.1, { origin = origin, copies = copies, startedAt = startedAt, fuse = def.fuse })
	task.spawn(function()
		task.wait(math.max(0, burstAt - PHANTASM_WARNING - now()))
		if not stillCurrent(ctx) or not services.CharacterService:isAlive(me) then
			return
		end
		-- Everyone near where a reflection will burst gets a dodge prompt (once)
		local warned = {}
		local threatened = {}
		for _, copy in copies do
			for _, target in ctx:inSphere(copy.to, def.radius + 3) do
				if not warned[target.id] then
					warned[target.id] = true
					table.insert(threatened, target)
				end
			end
		end
		ctx:telegraph(threatened, burstAt)
		task.wait(math.max(0, burstAt - now()))
		if not stillCurrent(ctx) or not services.CharacterService:isAlive(me) then
			return
		end
		local struck = {}
		for _, copy in copies do
			ctx:fx("PhantasmBurst", { position = groundAt(copy.to), radius = def.radius })
			for _, target in ctx:inSphere(copy.to, def.radius) do
				if not struck[target.id] then
					struck[target.id] = true
					strike(ctx, target, nil, { direction = awayFrom(copy.to, target), origin = copy.to })
				end
			end
		end
	end)
end

function abilities.Cataclysm(ctx)
	local def = ctx.def
	begin(ctx)
	ctx:telegraph(ctx:inSphere(groundBelow(ctx), def.radius + 4, def.jumpClearance), ctx:activeAt())
	ctx:fx("CataclysmWindup", { duration = def.startup, radius = def.radius })
	if not ctx:waitActive() then
		ctx:fx("CataclysmFizzle", {})
		return
	end
	local center = groundBelow(ctx)
	ctx:fx("Cataclysm", { position = center, radius = def.radius })
	for _, target in ctx:inSphere(center, def.radius, def.jumpClearance) do
		strike(ctx, target, nil, { direction = awayFrom(center, target), origin = center })
	end
end

-- Ultimate: Total System Corruption -----------------------------------------------------------------

local formProfiles: { [number]: any } = {}

local function formProfile(runtime, def): any
	local cached = formProfiles[runtime.degree]
	if cached then
		return cached
	end
	local profile = Powers.deepCopy(Powers.combatProfile(POWER_ID, runtime.degree))
	profile.Movement.WalkSpeed += def.walkBonus
	formProfiles[runtime.degree] = profile
	return profile
end

local function restoreProfile(fighter, runtime)
	if fighter.power == runtime then
		services.CharacterService:setCombatProfile(fighter, Powers.combatProfile(POWER_ID, runtime.degree))
	end
end

-- The form ends. "Expired": its time ran out, and the collapse follows (the
-- meter empties and stays locked, and they stagger out slowed). "Stopped": the
-- fighter was knocked out or reset, so only the form itself is undone.
local function endForm(fighter, runtime, data, token: number, reason: string)
	if data.formToken ~= token then
		return
	end
	data.formUntil = nil
	data.formToken = token + 1
	if fighter.model.Parent then
		fighter.model:SetAttribute(FORM_ATTRIBUTE, nil)
	end
	if fighter.power ~= runtime or runtime.data ~= data then
		return
	end
	restoreProfile(fighter, runtime)
	if reason == "Expired" and services.CharacterService:isAlive(fighter) then
		local def = ultimateOf(runtime)
		runtime.resource = 0
		data.lockedUntil = now() + def.lockTime
		if fighter.model.Parent then
			fighter.model:SetAttribute(LOCK_ATTRIBUTE, data.lockedUntil)
		end
		services.StatusService:apply(fighter, "Slow", def.collapseTime, { magnitude = def.collapseSlow, source = fighter })
		AbilityKit.forFighter(fighter):fx("FormCollapse", { lock = def.lockTime })
		task.delay(def.lockTime + 0.05, function()
			if fighter.power == runtime and runtime.data == data and not locked(data) and fighter.model.Parent then
				fighter.model:SetAttribute(LOCK_ATTRIBUTE, nil)
			end
		end)
	end
	publish(fighter, runtime)
end

local function beginForm(ctx)
	local def = ctx.def
	local fighter, runtime, data = ctx.fighter, ctx.runtime, ctx.data
	local endsAt = now() + def.formDuration
	data.formToken = (data.formToken or 0) + 1
	local token = data.formToken
	data.formUntil = endsAt
	data.lockedUntil = nil
	runtime.resource = runtime.resourceMax
	fighter.model:SetAttribute(FORM_ATTRIBUTE, endsAt)
	fighter.model:SetAttribute(LOCK_ATTRIBUTE, nil)
	services.CharacterService:setCombatProfile(fighter, formProfile(runtime, def))
	publish(fighter, runtime)
	local stopFx = ctx:lastingFx("FinalForm", def.formDuration, { endsAt = endsAt })
	local ended = false
	local function finish(reason: string)
		if ended then
			return
		end
		ended = true
		stopFx()
		endForm(fighter, runtime, data, token, reason)
	end
	ctx:own(function()
		finish("Stopped")
	end)
	task.spawn(function()
		while not ended and now() < endsAt do
			if not services.CharacterService:isAlive(fighter) or fighter.power ~= runtime or runtime.data ~= data then
				finish("Stopped")
				return
			end
			task.wait(0.1)
		end
		finish("Expired")
	end)
end

function abilities.TotalSystemCorruption(ctx)
	local def = ctx.def
	begin(ctx)
	-- Everyone close enough gets the timing bar
	ctx:telegraph(ctx:inSphere(ctx:origin(), def.radius + 4), ctx:activeAt())
	ctx:fx("SystemBreakWindup", { duration = def.startup, radius = def.radius })
	if not ctx:waitActive() then
		ctx:fx("SystemBreakFizzle", {})
		return
	end
	if not stillCurrent(ctx) then
		return
	end
	local center = ctx:origin()
	ctx:fx("SystemBreak", { position = groundBelow(ctx), radius = def.radius })
	beginForm(ctx)
	for _, target in ctx:inSphere(center, def.radius) do
		ctx:hit(target, nil, { direction = awayFrom(center, target), origin = center })
	end
end

return Corruption
