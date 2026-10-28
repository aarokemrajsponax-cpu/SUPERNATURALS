-- Syntax's abilities on the server: precision basics (Keystroke packets that
-- hit harder the farther they fly, a Strikethrough line that deletes whoever
-- stays on it), Target Lock, homing Code Bolts, the Holo Barrier, Packet
-- Reroute (her redirect counter), Interface and Object Override (taking over
-- the arena's tagged pylons, nodes and vents), Command Zones with a countdown,
-- the Confinement Field, Execute Chain, and at Degree 3 Rule Rewrite, Move
-- Override, Reconstruct and the System Override ultimate.
-- Numbers come from Shared/Powers/Syntax.luau (scaled by degree). Everything she
-- changes is bounded: fields and constructs end on their own and with her, and
-- nothing outside the fight's fictional domain is ever touched.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local AbilityKit = require(script.Parent.Parent.Combat.AbilityKit)

local Syntax = {}
local abilities = {}
Syntax.abilities = abilities

-- Server services (PowerService hands them over when it loads this module)
local services: any = nil

function Syntax.init(allServices)
	services = allServices
end

local EMERALD = Color3.fromRGB(38, 226, 168)
-- Movers Move Override puts on the opponents in its lane
local DRIFT_NAME = "SNSyntaxDrift"
-- Where her bolts leave from, in her root's space (her right hand, held forward)
local MUZZLE = Vector3.new(1.1, 0.7, -1.6)
-- Most a shot can aim up or down (degrees)
local MAX_PITCH = 35
-- How often the passive checks her locked targets for concealment
local REVEAL_EVERY = 0.2
-- Kinds of hits that count as "up close" for her weakness
local CLOSE_KINDS = { Light = true, Heavy = true, Grab = true }

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

local function now(): number
	return workspace:GetServerTimeNow()
end

local function hasTag(tags: { string }?, tag: string): boolean
	return tags ~= nil and table.find(tags, tag) ~= nil
end

-- Geometry -------------------------------------------------------------------------------

-- Fighters and effects (and constructs, unless `solidConstructs`) are see-through
local function ignoreList(solidConstructs: boolean?): { Instance }
	local ignore: { Instance } = {}
	for _, fighter in services.CharacterService:all() do
		table.insert(ignore, fighter.model)
	end
	local folders = { "SNEffects", "SNLocalDebris" }
	if not solidConstructs then
		table.insert(folders, "SNConstructs")
	end
	for _, name in folders do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	return ignore
end

-- The floor under a point (fields and constructs sit on it)
local function groundAt(point: Vector3): Vector3
	groundParams.FilterDescendantsInstances = ignoreList()
	local result = workspace:Raycast(point + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), groundParams)
	return if result then result.Position else point - Vector3.new(0, 3, 0)
end

-- Keeps a placed thing inside the caster's arena (in a match)
local function inside(ctx, point: Vector3, margin: number): Vector3
	local match = services.MatchService:getMatchOf(ctx.fighter)
	if match and match.arena then
		return services.ArenaService:clampInside(match.arena, point, margin)
	end
	return point
end

-- Where an aimed ability lands: the validated aim point, or `fallback` studs ahead
local function aimedGround(ctx, fallback: number, margin: number?): Vector3
	local point = ctx.point or (ctx:origin() + ctx.direction * fallback)
	return groundAt(inside(ctx, point, margin or 4))
end

-- How far a straight line from `origin` gets before a wall (barriers stop it too)
local function clearLength(origin: Vector3, direction: Vector3, length: number): number
	groundParams.FilterDescendantsInstances = ignoreList(true)
	local result = workspace:Raycast(origin, direction * length, groundParams)
	return if result then (result.Position - origin).Magnitude else length
end

local function muzzle(ctx): Vector3
	return (ctx.fighter.root.CFrame * CFrame.new(MUZZLE)).Position
end

-- A direction toward `target` (or the aim), pitched no more than MAX_PITCH
local function aimFrom(ctx, from: Vector3, target): Vector3
	local wanted
	if target then
		wanted = target.root.Position - from
	elseif ctx.point then
		wanted = ctx.point - from
	else
		wanted = ctx.look or ctx.direction
	end
	if wanted.Magnitude < 0.1 then
		return ctx.direction
	end
	local unit = wanted.Unit
	local flat = Hitbox.flatDirection(unit) or ctx.direction
	local pitch = math.clamp(math.asin(math.clamp(unit.Y, -1, 1)), -math.rad(MAX_PITCH), math.rad(MAX_PITCH))
	return (flat * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)).Unit
end

-- Targets ------------------------------------------------------------------------------

-- Is `target` locked by this Syntax (her Mark, not someone else's)?
local function lockedBy(ctx, target): boolean
	local mark = services.StatusService:get(target, "Mark")
	return mark ~= nil and mark.sourceId == ctx.fighter.id
end

-- The closest opponent she has locked, in range and in sight
local function lockedTarget(ctx, range: number)
	local best, bestDistance = nil, math.huge
	local origin = ctx:origin()
	for _, enemy in ctx:enemies() do
		local distance = (enemy.root.Position - origin).Magnitude
		if distance <= range and distance < bestDistance and lockedBy(ctx, enemy) and ctx:lineOfSight(origin, enemy.root.Position) then
			best, bestDistance = enemy, distance
		end
	end
	return best
end

-- The opponent an aimed ability means: nearest the aimed point (within `search`),
-- else a locked target in front, else the nearest one in a narrow cone. In range
-- and in sight either way.
local function pickTarget(ctx, range: number, search: number)
	local origin = ctx:origin()
	local function usable(enemy): boolean
		return (enemy.root.Position - origin).Magnitude <= range and ctx:lineOfSight(origin, enemy.root.Position)
	end
	if ctx.point then
		local best, bestDistance = nil, search
		for _, enemy in ctx:enemies() do
			local distance = (enemy.root.Position - ctx.point).Magnitude
			if distance <= bestDistance and usable(enemy) then
				best, bestDistance = enemy, distance
			end
		end
		if best then
			return best
		end
	end
	local locked = lockedTarget(ctx, range)
	if locked then
		local flat = Hitbox.flatDirection(locked.root.Position - origin)
		if flat and flat:Dot(ctx.direction) > 0.5 then
			return locked
		end
	end
	local nearest = ctx:nearestEnemy(range, 40)
	if nearest and usable(nearest) then
		return nearest
	end
	return nil
end

-- Locks a target: marked for her bolts, and pulled out of concealment
local function lock(ctx, target, duration: number)
	ctx:status(target, "Mark", duration)
	if services.StatusService:has(target, "Concealed") then
		ctx:clearStatus(target, "Concealed")
		ctx:fx("Reveal", { target = target.model })
	end
end

-- Arena objects ---------------------------------------------------------------------------

local function objectPosition(object: Instance): Vector3?
	if object:IsA("BasePart") then
		return object.CFrame.Position
	elseif object:IsA("Model") then
		return object:GetPivot().Position
	end
	return nil
end

-- How wide an object is across the ground (so things placed by it stand clear)
local function objectRadius(object: Instance): number
	local size = if object:IsA("BasePart") then object.Size elseif object:IsA("Model") then object:GetExtentsSize() else Vector3.one
	return math.min(math.max(size.X, size.Z) / 2, 6)
end

-- The tagged arena object (Pylon, Node or Vent) nearest the aimed point, within
-- `search` of it and within reach of the caster. Returns (object, kind, position).
local function findInteractive(ctx, search: number, reach: number)
	local origin = ctx:origin()
	local around = ctx.point or (origin + ctx.direction * math.min(reach, 30))
	local best, bestKind, bestPosition, bestDistance = nil, nil, nil, search
	for _, object in CollectionService:GetTagged(Protocol.Tag.Interactive) do
		local kind = object:GetAttribute("Interaction")
		local position = objectPosition(object)
		if position and (kind == "Pylon" or kind == "Node" or kind == "Vent") and object:IsDescendantOf(workspace) then
			local distance = (position - around).Magnitude
			if distance <= bestDistance and (position - origin).Magnitude <= reach + search then
				best, bestKind, bestPosition, bestDistance = object, kind, position, distance
			end
		end
	end
	return best, bestKind, bestPosition
end

-- Lasting fields ------------------------------------------------------------------------------

-- A field that lasts `duration`: onTick(stop) every `tick`, then onEnd(reason)
-- once ("Expired" when it runs out, "Reset" or "Owner" when its caster is gone,
-- or whatever reason onTick passes to stop). Ends with its owner. Returns stop().
local function field(ctx, spec: { duration: number, tick: number?, fx: string?, fxData: { [string]: any }?, onTick: ((reason: string?) -> ()) -> (), onEnd: ((string) -> ())? }): (reason: string?) -> ()
	local running = true
	local stopFx = if spec.fx then ctx:lastingFx(spec.fx, spec.duration, spec.fxData or {}) else nil
	local function stop(reason: string?)
		if not running then
			return
		end
		running = false
		if stopFx then
			stopFx()
		end
		if spec.onEnd then
			local ok, err = pcall(spec.onEnd, reason or "Stopped")
			if not ok then
				warn("[Syntax] field end failed: " .. tostring(err))
			end
		end
	end
	ctx:own(function()
		stop("Reset")
	end)
	local endsAt = now() + spec.duration
	task.spawn(function()
		while running and now() < endsAt do
			if not services.CharacterService:isAlive(ctx.fighter) or not services.MatchService:isCombatAllowed(ctx.fighter) then
				stop("Owner")
				return
			end
			local ok, err = pcall(spec.onTick, stop)
			if not ok then
				warn("[Syntax] field tick failed: " .. tostring(err))
			end
			task.wait(spec.tick or 0.2)
		end
		stop("Expired")
	end)
	return stop
end

-- Snapshots (what Reconstruct restores) --------------------------------------------------------

local function remember(ctx, snapshot: { [string]: any })
	local data = ctx.runtime and ctx.runtime.data
	if not data then
		return
	end
	data.snapshots = data.snapshots or {}
	snapshot.endedAt = now()
	table.insert(data.snapshots, snapshot)
	-- Only the last few matter
	while #data.snapshots > 4 do
		table.remove(data.snapshots, 1)
	end
end

-- Constructs ----------------------------------------------------------------------------------

-- One holographic slab: the real part that blocks bodies and projectiles. Clients
-- draw the frame, the grid and the labels around it.
local function slab(model: Model, name: string, frame: CFrame, size: Vector3, transparency: number)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = frame
	part.Color = EMERALD
	part.Material = Enum.Material.ForceField
	part.Transparency = transparency
	part.CanCollide = true
	part.Parent = model
	return part
end

-- A barrier wall standing on `base`, facing `facing`. kind: "HoloBarrier" | "Wall"
local function barrier(ctx, kind: string, base: Vector3, facing: Vector3, width: number, height: number, duration: number, health: number, restored: boolean)
	local frame = CFrame.lookAt(base, base + facing) * CFrame.new(0, height / 2, 0)
	local stopFx: (() -> ())? = nil
	local construct = ctx:construct({
		name = kind,
		duration = duration,
		health = health,
		limit = 1,
		build = function(model)
			slab(model, "Body", frame, Vector3.new(width, height, 0.6), 0.55)
		end,
		onEnd = function(_, reason)
			if stopFx then
				stopFx()
			end
			ctx:fx("BarrierEnd", { position = frame.Position, width = width, height = height, reason = reason })
			if not restored and reason ~= "OwnerGone" and reason ~= "Replaced" then
				remember(ctx, { kind = kind, base = base, facing = facing, width = width, height = height, duration = duration, health = health })
			end
		end,
	})
	if construct then
		stopFx = ctx:lastingFx("Barrier", duration, { cframe = frame, width = width, height = height, wall = kind == "Wall", restored = restored })
	end
	return construct
end

-- A sentry: a small hologram turret that fires at the nearest opponent in sight.
-- `shot` is the sentry's numbers (Object Override's at this degree).
local function sentry(ctx, head: Vector3, link: Vector3?, shot: any, every: number, duration: number, health: number, restored: boolean)
	local stopFx: (() -> ())? = nil
	local construct
	construct = ctx:construct({
		name = "Sentry",
		duration = duration,
		health = health,
		limit = 1,
		build = function(model)
			slab(model, "Head", CFrame.new(head), Vector3.new(2.2, 2.2, 2.2), 0.45)
			-- A built sentry (nothing to take over) stands on its own post
			if not link then
				local floor = groundAt(head)
				local height = math.max(0.5, head.Y - 1.1 - floor.Y)
				slab(model, "Post", CFrame.new(Vector3.new(head.X, floor.Y + height / 2, head.Z)), Vector3.new(0.7, height, 0.7), 0.5)
			end
		end,
		onEnd = function(_, reason)
			if stopFx then
				stopFx()
			end
			ctx:fx("SentryEnd", { position = head, reason = reason })
			if not restored and reason ~= "OwnerGone" and reason ~= "Replaced" then
				remember(ctx, { kind = "Sentry", head = head, link = link, every = every, duration = duration, health = health })
			end
		end,
	})
	if not construct then
		return nil
	end
	stopFx = ctx:lastingFx("Sentry", duration, { position = head, link = link, every = every, restored = restored })
	local hit = AbilityKit.hitFrom(shot)
	task.spawn(function()
		task.wait(0.35)
		while construct.alive and services.CharacterService:isAlive(ctx.fighter) and services.MatchService:isCombatAllowed(ctx.fighter) do
			local best, bestDistance = nil, shot.sightRange
			for _, enemy in ctx:enemies() do
				local distance = (enemy.root.Position - head).Magnitude
				if distance <= bestDistance and ctx:lineOfSight(head, enemy.root.Position) then
					best, bestDistance = enemy, distance
				end
			end
			if best then
				local direction = (best.root.Position - head).Unit
				ctx:projectile({
					ability = "ObjectOverride",
					label = shot.name,
					visual = "SentryBolt",
					-- Leaves from just outside the head, so it doesn't hit it
					origin = head + direction * 1.9,
					direction = direction,
					speed = shot.speed,
					radius = 0.45,
					lifetime = 1.2,
					range = shot.sightRange + 6,
					hit = table.clone(hit),
					tags = { "Projectile", "Small" },
					interceptable = true,
				})
			end
			task.wait(every)
		end
	end)
	return construct
end

-- Basics -------------------------------------------------------------------------------------

-- Keystroke: the farther the opponent it's meant for, the harder it hits
function abilities.Keystroke(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local from = muzzle(ctx)
	local locked = lockedTarget(ctx, def.range)
	local intended = locked or ctx:nearestEnemy(def.range, 30)
	local hit = AbilityKit.hitFrom(def)
	local distance = if intended then (intended.root.Position - from).Magnitude elseif ctx.point then (ctx.point - from).Magnitude else def.falloff.far
	local share = math.clamp((distance - def.falloff.near) / (def.falloff.far - def.falloff.near), 0, 1)
	hit.Damage = def.damage + (def.farDamage - def.damage) * share
	if locked then
		hit.Damage *= 1 + def.markBonus
	end
	ctx:projectile({
		visual = "Packet",
		origin = from,
		direction = aimFrom(ctx, from, intended),
		speed = def.speed,
		radius = def.radius,
		lifetime = def.lifetime,
		range = def.range,
		hit = hit,
		homing = if locked then { target = locked, turnRate = def.lockedTurnRate } else nil,
		interceptable = true,
		data = { target = if locked then locked.model else nil, turnRate = def.lockedTurnRate, charge = share },
	})
end

-- Strikethrough: the line is fixed when it's drawn; whoever is still on it is deleted
function abilities.Strikethrough(ctx)
	local def = ctx.def
	local origin = ctx:origin()
	local direction = ctx.direction
	if ctx.point then
		direction = Hitbox.flatDirection(ctx.point - origin) or direction
	end
	local length = clearLength(origin, direction, def.range)
	ctx:fx("StrikeMark", { origin = origin, direction = direction, length = length, width = def.width, duration = def.startup })
	if not ctx:waitActive() then
		ctx:fx("StrikeCancel", { origin = origin, direction = direction, length = length })
		return
	end
	ctx:fx("Strike", { origin = origin, direction = direction, length = length, width = def.width })
	for _, target in ctx:alongLine(origin, direction, length, def.width) do
		if ctx:lineOfSight(origin, target.root.Position) then
			ctx:hit(target, nil, { direction = direction, origin = origin })
		end
	end
end

-- Degree 1 ------------------------------------------------------------------------------------

function abilities.TargetLock(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local target = pickTarget(ctx, def.range, def.search)
	if target then
		lock(ctx, target, def.duration)
		ctx:fx("Lock", { target = target.model, duration = def.duration })
		return
	end
	-- Nobody there: pin the point. The first opponent to cross it is locked.
	local point = aimedGround(ctx, 30)
	field(ctx, {
		duration = def.pinDuration,
		tick = 0.1,
		fx = "Pin",
		fxData = { position = point, radius = def.pinRadius },
		onTick = function(stop)
			local caught = ctx:inSphere(point, def.pinRadius, 4)[1]
			if caught then
				lock(ctx, caught, def.duration)
				ctx:fx("Lock", { target = caught.model, duration = def.duration, from = point })
				stop("Caught")
			end
		end,
	})
end

function abilities.CodeBolt(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local from = muzzle(ctx)
	local locked = lockedTarget(ctx, def.range)
	local target = locked or ctx:nearestEnemy(def.range, 30)
	local hit = AbilityKit.hitFrom(def)
	if locked then
		hit.Damage *= 1 + def.markBonus
	end
	local turnRate = if locked then def.lockedTurnRate else def.turnRate
	ctx:projectile({
		visual = "CodeBolt",
		origin = from,
		direction = aimFrom(ctx, from, target),
		speed = def.speed,
		radius = def.radius,
		lifetime = def.lifetime,
		range = def.range,
		hit = hit,
		pierce = def.pierce,
		homing = if target then { target = target, turnRate = turnRate } else nil,
		interceptable = true,
		data = { target = if target then target.model else nil, turnRate = turnRate, locked = locked ~= nil },
	})
end

function abilities.HoloBarrier(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local direction = ctx.direction
	local base = groundAt(inside(ctx, ctx:origin() + direction * def.range, 3))
	barrier(ctx, "HoloBarrier", base, direction, def.width, def.height, def.duration, def.health, false)
end

-- Projectiles Packet Reroute may take over: an opponent's, not already redirected,
-- and not one that's too powerful to move (massive or marked unredirectable)
local function reroutable(ctx, projectile): boolean
	return projectile.alive
		and not projectile.redirected
		and projectile.ownerId ~= ctx.fighter.id
		and projectile.spec.redirectable ~= false
		and not hasTag(projectile.spec.tags, "Massive")
		and ctx:isEnemy(projectile.owner)
end

-- Cast: takes over eligible projectiles near her during the window and sends them
-- back at whoever fired them. (While it's ready, DefenseService also offers the
-- Redirect prompt for single projectiles; see PowerService.readyRedirect.)
function abilities.PacketReroute(ctx)
	local def = ctx.def
	ctx:fx("RerouteOpen", { duration = def.startup + def.active, radius = def.radius })
	local taken = 0
	local endsAt = ctx:activeAt() + def.active
	while now() < endsAt and taken < def.maxRedirects and ctx:alive() do
		local found = services.ProjectileService:nearby(ctx:origin(), def.radius, function(projectile)
			return reroutable(ctx, projectile)
		end)
		for _, projectile in found do
			local original = projectile.owner
			local aimAt = if services.CharacterService:isAlive(original) then original.root.Position else projectile.position - projectile.velocity
			local from = projectile.position
			if services.ProjectileService:redirect(projectile, ctx.fighter, aimAt - from) then
				taken += 1
				ctx:fx("Reroute", { from = from, to = aimAt })
				if taken >= def.maxRedirects then
					break
				end
			end
		end
		task.wait(0.05)
	end
	if taken == 0 then
		-- Nothing came: half back, and the passive is ready again sooner
		ctx:refund(0.5)
		ctx:fx("RerouteMiss", {})
	end
end

-- Interface: operate the arena object nearest the aim
function abilities.Interface(ctx)
	local def = ctx.def
	local object, kind, position = findInteractive(ctx, def.search, def.range)
	local hand = muzzle(ctx)
	if not object or not position then
		-- No object in reach: compile a short-lived data node that pulses a slow
		local center = aimedGround(ctx, 20)
		ctx:fx("InterfaceLink", { from = hand, to = center + Vector3.new(0, 1.5, 0), kind = "Spawn", duration = def.startup })
		if not ctx:waitActive() then
			return
		end
		local duration = def.pulses * def.pulseEvery + 0.2
		local node = ctx:construct({
			name = "DataNode",
			duration = duration,
			health = 20,
			limit = 1,
			collides = true,
			build = function(model)
				slab(model, "Core", CFrame.new(center + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(1.4, 1.4, 1.4), 0.4)
			end,
		})
		if not node then
			return
		end
		field(ctx, {
			duration = duration,
			tick = def.pulseEvery,
			fx = "DataNode",
			fxData = { position = center, radius = def.radius, every = def.pulseEvery },
			onTick = function(stop)
				-- Shot down: the node stops pulsing
				if not node.alive then
					stop("Broken")
					return
				end
				ctx:fx("Pulse", { position = center, radius = def.radius })
				for _, target in ctx:inSphere(center, def.radius, 6) do
					ctx:status(target, "Slow", def.pulseEvery + 0.3, { magnitude = def.slow })
				end
			end,
		})
		return
	end

	ctx:fx("InterfaceLink", { from = hand, to = position, kind = kind, duration = def.startup })
	if kind == "Pylon" then
		-- The pylon fires a precise beam at each opponent near it
		local near = {}
		for _, enemy in ctx:enemies() do
			local distance = (enemy.root.Position - position).Magnitude
			if distance <= def.beamRange then
				table.insert(near, { enemy = enemy, distance = distance })
			end
		end
		table.sort(near, function(a, b)
			return a.distance < b.distance
		end)
		local targets = {}
		for index = 1, math.min(#near, def.beamTargets) do
			table.insert(targets, near[index].enemy)
		end
		ctx:telegraph(targets, ctx:activeAt())
		local models = {}
		for _, target in targets do
			table.insert(models, target.model)
		end
		ctx:fx("PylonCharge", { position = position, duration = def.startup, targets = models })
		if not ctx:waitActive() then
			return
		end
		local struck = {}
		for _, target in targets do
			if services.CharacterService:isAlive(target) and ctx:lineOfSight(position, target.root.Position) then
				table.insert(struck, target.root.Position)
				ctx:hit(target, nil, { origin = position, direction = Hitbox.flatDirection(target.root.Position - position) })
			end
		end
		ctx:fx("PylonFire", { position = position, targets = struck })
	elseif kind == "Vent" then
		-- The vent blasts everyone standing over it up into the air
		local floor = groundAt(position)
		ctx:telegraph(ctx:inSphere(floor, def.ventRadius + 2, 6), ctx:activeAt())
		ctx:fx("VentCharge", { position = floor, radius = def.ventRadius, duration = def.startup })
		if not ctx:waitActive() then
			return
		end
		ctx:fx("VentBlast", { position = floor, radius = def.ventRadius })
		local blast = { damage = def.ventDamage, hitstun = 0.55, knockback = 6, launch = def.ventLaunch, guardDamage = 12, tags = { "Area" } }
		for _, target in ctx:inSphere(floor, def.ventRadius, 6) do
			ctx:hit(target, blast, { origin = floor, direction = Hitbox.flatDirection(target.root.Position - floor) })
		end
	else
		-- A node pulses a slow around itself
		if not ctx:waitActive() then
			return
		end
		local center = groundAt(position)
		field(ctx, {
			duration = def.pulses * def.pulseEvery,
			tick = def.pulseEvery,
			fx = "NodeOverride",
			fxData = { position = center, radius = def.radius, every = def.pulseEvery },
			onTick = function()
				ctx:fx("Pulse", { position = center, radius = def.radius })
				for _, target in ctx:inSphere(center, def.radius, 6) do
					ctx:status(target, "Slow", def.pulseEvery + 0.3, { magnitude = def.slow })
				end
			end,
		})
	end
end

-- Degree 2 ------------------------------------------------------------------------------------

function abilities.CommandZone(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local center = aimedGround(ctx, 22, def.radius * 0.5)
	local endsAt = now() + def.duration
	field(ctx, {
		duration = def.duration,
		tick = 0.25,
		fx = "CommandZone",
		fxData = { position = center, radius = def.radius, endsAt = endsAt },
		onTick = function()
			for _, target in ctx:inSphere(center, def.radius, 6) do
				ctx:status(target, "Slow", 0.5, { magnitude = def.slow })
			end
		end,
		onEnd = function(reason)
			if reason ~= "Expired" then
				return
			end
			-- Zero: whoever is still inside is compiled
			local caught = ctx:inSphere(center, def.radius, 6)
			ctx:fx("CommandExecute", { position = center, radius = def.radius, count = #caught })
			for _, target in caught do
				local outcome = ctx:hit(target, nil, { kind = "Zone", origin = center })
				if outcome and outcome.result == "Hit" then
					ctx:status(target, "Distort", def.distort)
				end
			end
		end,
	})
end

function abilities.ConfinementField(ctx)
	local def = ctx.def
	local target = pickTarget(ctx, def.range, def.search)
	-- The cell closes where the target stood when it was cast (or the aimed spot)
	local center = if target then groundAt(target.root.Position) else aimedGround(ctx, 18)
	ctx:telegraph(ctx:inSphere(center, def.radius + 3, 6), ctx:activeAt())
	ctx:fx("CellClosing", { position = center, radius = def.radius, duration = def.startup })
	if not ctx:waitActive() then
		ctx:fx("CellCancel", { position = center })
		return
	end
	local trapped = {}
	for _, victim in ctx:inSphere(center, def.radius, 6) do
		local outcome = ctx:hit(victim, nil, { origin = center })
		if outcome and (outcome.result == "Hit" or outcome.result == "GuardBreak") then
			ctx:status(victim, "Trapped", def.duration, { data = { center = center, radius = def.radius } })
			table.insert(trapped, victim)
		end
	end
	if #trapped == 0 then
		ctx:fx("CellMiss", { position = center, radius = def.radius })
		return
	end
	local stopFx = ctx:lastingFx("Cell", def.duration, { position = center, radius = def.radius, endsAt = now() + def.duration })
	-- The cell lets go if she's knocked out or reset
	local function release()
		stopFx()
		for _, victim in trapped do
			local status = services.StatusService:get(victim, "Trapped")
			if status and status.sourceId == ctx.fighter.id then
				services.StatusService:remove(victim, "Trapped")
			end
		end
	end
	ctx:own(release)
	for _, victim in trapped do
		-- Mashing breaks out early
		task.spawn(function()
			local result = services.DefenseService:grab(victim, ctx.fighter, {
				hold = def.duration,
				presses = def.presses,
				ability = def.id,
				power = ctx.power,
				label = def.name,
				holding = function()
					return services.StatusService:has(victim, "Trapped")
				end,
			})
			if result == "Escaped" then
				services.StatusService:remove(victim, "Trapped")
				ctx:fx("CellBreak", { position = center, radius = def.radius, target = victim.model })
			end
		end)
	end
	task.delay(def.duration, stopFx)
end

function abilities.ObjectOverride(ctx)
	local def = ctx.def
	local object, kind, position = findInteractive(ctx, def.search, def.range)
	local hand = muzzle(ctx)
	local target = if object and position then position else aimedGround(ctx, 18) + Vector3.new(0, 1, 0)
	ctx:fx("InterfaceLink", { from = hand, to = target, kind = kind or "Spawn", duration = def.startup, override = true })
	if not ctx:waitActive() then
		return
	end
	if object and position and kind == "Vent" then
		-- A vent becomes a firewall standing across it
		local floor = groundAt(position)
		local facing = Hitbox.flatDirection(floor - ctx:origin()) or ctx.direction
		barrier(ctx, "Wall", floor, facing, def.wallWidth, def.wallHeight, def.duration, def.health, false)
		return
	end
	local head, link
	if object and position then
		-- Next to the object, on her side of it, at chest height
		local floor = groundAt(position)
		local toward = Hitbox.flatDirection(ctx:origin() - floor) or -ctx.direction
		local beside = floor + toward * (objectRadius(object) + 2)
		head = Vector3.new(beside.X, floor.Y + 4, beside.Z)
		link = position
	else
		head = target + Vector3.new(0, 3, 0)
	end
	local every = if kind == "Pylon" then def.pylonShotEvery else def.shotEvery
	sentry(ctx, head, link, def, every, def.duration, def.health, false)
end

function abilities.ExecuteChain(ctx)
	local def = ctx.def
	local target = pickTarget(ctx, def.range, def.search)
	ctx:fx("ChainStart", { target = if target then target.model else nil, duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local function valid(): boolean
		return target ~= nil and ctx:alive() and services.CharacterService:isAlive(target) and ctx:lineOfSight(ctx:origin(), target.root.Position)
	end
	if not valid() then
		ctx:fx("ChainFail", { step = 0 })
		ctx:refund(0.5)
		return
	end
	-- 1. lock()
	lock(ctx, target, def.markDuration)
	ctx:fx("ChainStep", { step = 1, target = target.model, label = "lock()" })
	if not ctx:wait(0.25) or not valid() then
		ctx:fx("ChainFail", { step = 1 })
		return
	end
	-- 2. slow()
	ctx:status(target, "Slow", def.slowDuration, { magnitude = def.slow })
	ctx:fx("ChainStep", { step = 2, target = target.model, label = `slow({def.slow})` })
	if not ctx:wait(0.25) or not valid() then
		ctx:fx("ChainFail", { step = 2 })
		return
	end
	-- 3. bolt() x3
	ctx:fx("ChainStep", { step = 3, target = target.model, label = `bolt() x{def.bolts}` })
	for index = 1, def.bolts do
		if index > 1 and not ctx:wait(def.interval) then
			return
		end
		local from = muzzle(ctx)
		ctx:projectile({
			visual = "ChainBolt",
			origin = from,
			direction = aimFrom(ctx, from, target),
			speed = def.speed,
			radius = def.radius,
			lifetime = def.lifetime,
			range = def.range + 10,
			homing = if services.CharacterService:isAlive(target) then { target = target, turnRate = def.turnRate } else nil,
			interceptable = true,
			data = { target = target.model, turnRate = def.turnRate, index = index },
		})
	end
end

-- Degree 3 ------------------------------------------------------------------------------------

function abilities.RuleRewrite(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local center = aimedGround(ctx, 22, def.radius * 0.5)
	local rule = string.format("GRAVITY = %.1f", def.gravity)
	field(ctx, {
		duration = def.duration,
		tick = 0.25,
		fx = "RuleField",
		fxData = { position = center, radius = def.radius, rule = rule, endsAt = now() + def.duration },
		onTick = function()
			for _, target in ctx:inSphere(center, def.radius, 14) do
				ctx:status(target, "Gravity", 0.5, { magnitude = def.gravity })
				ctx:status(target, "Slow", 0.5, { magnitude = def.slow })
			end
		end,
		onEnd = function()
			ctx:fx("RuleRevert", { position = center, radius = def.radius, rule = rule })
		end,
	})
end

-- The most recent snapshot still remembered, and not too far from her
local function lastSnapshot(ctx, memory: number, reach: number)
	local data = ctx.runtime and ctx.runtime.data
	local list = data and data.snapshots
	if not list then
		return nil
	end
	local origin = ctx:origin()
	for index = #list, 1, -1 do
		local snapshot = list[index]
		local where = snapshot.base or snapshot.head
		if now() - snapshot.endedAt <= memory and where and (where - origin).Magnitude <= reach then
			table.remove(list, index)
			return snapshot
		end
	end
	return nil
end

function abilities.Reconstruct(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local snapshot = lastSnapshot(ctx, def.memory, def.range + 20)
	if snapshot then
		local ago = now() - snapshot.endedAt
		if snapshot.kind == "Sentry" then
			sentry(ctx, snapshot.head, snapshot.link, Powers.abilityFor("Syntax", "ObjectOverride", ctx.degree), snapshot.every, snapshot.duration, snapshot.health, true)
			ctx:fx("Restore", { position = snapshot.head, label = string.format("RESTORE sentry @ -%.1fs", ago) })
		else
			barrier(ctx, snapshot.kind, snapshot.base, snapshot.facing, snapshot.width, snapshot.height, snapshot.duration, snapshot.health, true)
			ctx:fx("Restore", { position = snapshot.base + Vector3.new(0, snapshot.height / 2, 0), label = string.format("RESTORE %s @ -%.1fs", if snapshot.kind == "Wall" then "wall" else "barrier", ago) })
		end
		return
	end
	-- Nothing saved: build the known default, a lattice wall where she aims
	local base = aimedGround(ctx, 10, 3)
	local facing = Hitbox.flatDirection(base - ctx:origin()) or ctx.direction
	barrier(ctx, "Wall", base, facing, def.width, def.height, def.duration, def.health, true)
	ctx:fx("Restore", { position = base + Vector3.new(0, def.height / 2, 0), label = "RESTORE wall @ default" })
end

-- Removes the lane's mover from a fighter
local function clearDrift(fighter)
	local root = fighter and fighter.root
	if not root then
		return
	end
	for _, child in root:GetChildren() do
		if child.Name == DRIFT_NAME then
			child:Destroy()
		end
	end
end

-- Inside the lane, a fighter's speed along it is overridden; sideways stays theirs
local function addDrift(fighter, direction: Vector3, speed: number, force: number, bound: number)
	local root = fighter.root
	if root:FindFirstChild(DRIFT_NAME) then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = DRIFT_NAME
	attachment.Parent = root
	local mover = Instance.new("LinearVelocity")
	mover.Name = DRIFT_NAME
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	mover.LineDirection = direction
	mover.LineVelocity = speed
	mover.MaxForce = force
	mover.Parent = root
	-- Never outlives the lane, whatever happens
	Debris:AddItem(mover, bound)
	Debris:AddItem(attachment, bound)
end

function abilities.MovementOverride(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local direction = ctx.direction
	local floor = groundAt(ctx:origin())
	local center = floor + direction * (def.length / 2 + 1.5) + Vector3.new(0, 4, 0)
	local frame = CFrame.lookAt(center, center + direction)
	local size = Vector3.new(def.width, 9, def.length)
	local carried: { [string]: any } = {}
	field(ctx, {
		duration = def.duration,
		tick = 0.1,
		fx = "Lane",
		fxData = { cframe = CFrame.lookAt(Vector3.new(center.X, floor.Y, center.Z), Vector3.new(center.X, floor.Y, center.Z) + direction), width = def.width, length = def.length, endsAt = now() + def.duration },
		onTick = function()
			local present = {}
			for _, target in ctx:inBox(frame, size) do
				present[target.id] = true
				if not carried[target.id] then
					carried[target.id] = target
					addDrift(target, direction, def.drift, def.force, def.duration + 0.3)
				end
			end
			for id, target in carried do
				if not present[id] then
					carried[id] = nil
					clearDrift(target)
				end
			end
		end,
		onEnd = function()
			for id, target in carried do
				carried[id] = nil
				clearDrift(target)
			end
		end,
	})
end

-- Ultimate --------------------------------------------------------------------------------------

function abilities.SystemOverride(ctx)
	local def = ctx.def
	local center = aimedGround(ctx, 18, def.radius * 0.4)
	local impactAt = ctx:activeAt()
	local total = def.startup + def.active + def.recovery + 0.4
	local stopFx = ctx:lastingFx("Override", total, { position = center, radius = def.radius, impactAt = impactAt, lock = def.lock })
	ctx:telegraph(ctx:inSphere(center, def.radius + 4, 14), impactAt)
	local sealed = {}
	local struck = false
	-- If she's knocked out of it (or the match ends), the area is handed back at once
	local function handBack()
		if struck then
			return
		end
		struck = true
		stopFx()
		for _, target in sealed do
			local status = services.StatusService:get(target, "Sealed")
			if status and status.sourceId == ctx.fighter.id then
				services.StatusService:remove(target, "Sealed")
			end
		end
	end
	ctx:own(handBack)
	ctx:onCleanup(handBack)
	if not ctx:wait(def.claimAt) then
		ctx:fx("OverrideFizzle", { position = center })
		return
	end
	-- The rule it changes: abilities inside are locked for 2 seconds
	local models = {}
	for _, target in ctx:inSphere(center, def.radius, 14) do
		ctx:status(target, "Sealed", def.lock)
		table.insert(sealed, target)
		table.insert(models, target.model)
	end
	ctx:fx("OverrideClaim", { position = center, radius = def.radius, lock = def.lock, targets = models })
	if not ctx:waitActive() or struck then
		ctx:fx("OverrideFizzle", { position = center })
		return
	end
	struck = true
	-- One coordinated strike on everyone still inside
	local positions = {}
	local victims = ctx:inSphere(center, def.radius, 14)
	for _, target in victims do
		table.insert(positions, target.root.Position)
	end
	ctx:fx("OverrideStrike", { position = center, radius = def.radius, targets = positions })
	for _, target in victims do
		ctx:hit(target, nil, { origin = center, direction = Hitbox.flatDirection(target.root.Position - center) })
	end
	-- Then everything is restored: the lock runs out on its own (2s after the claim)
	-- and the area is handed back
	task.delay(math.max(0.1, def.claimAt + def.lock - def.startup), function()
		ctx:fx("OverrideRestore", { position = center, radius = def.radius })
	end)
end

-- Hooks ------------------------------------------------------------------------------------------

function Syntax.onEquip(_, runtime)
	runtime.data.snapshots = {}
end

function Syntax.onReset(_, runtime)
	runtime.data.snapshots = {}
end

-- Locked opponents can't hide from her: concealment on them is lifted
function Syntax.tick(_, runtime, _, ctx)
	local data = runtime.data
	local time = now()
	if (data.nextReveal or 0) > time then
		return
	end
	data.nextReveal = time + REVEAL_EVERY
	for _, enemy in ctx:enemies() do
		if services.StatusService:has(enemy, "Concealed") and lockedBy(ctx, enemy) then
			services.StatusService:remove(enemy, "Concealed")
			ctx:fx("Reveal", { target = enemy.model })
		end
	end
end

-- Her weakness: hits up close knock Processing out of her buffer
function Syntax.onHurt(target, _, outcome, opts, runtime, ctx)
	if outcome.result ~= "Hit" then
		return
	end
	local close = CLOSE_KINDS[opts.kind] == true
		or (opts.kind ~= "Projectile" and (hasTag(opts.tags, "Melee") or hasTag(opts.tags, "Grab")))
	if not close then
		return
	end
	local lost = math.min(runtime.def.resource.lostOnMelee or 0, runtime.resource)
	if lost > 0 and services.PowerService:spend(target, lost) then
		ctx:fx("Dropped", { amount = lost })
	end
end

return Syntax
