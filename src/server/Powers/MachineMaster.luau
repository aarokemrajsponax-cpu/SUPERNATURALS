-- Machine Master's abilities on the server: blaster bolts, a pellet cone, a
-- shock pulse, a deflector panel and a barrier dome that stop projectiles,
-- shooting projectiles down, a rail beam and homing missiles, and at Degree 3
-- the soul-fire arsenal (sweeping streams, a pressurized burst, fireballs,
-- pulse mines) plus the Blue Inferno ultimate.
-- Numbers come from Shared/Powers/MachineMaster.luau (scaled by degree).
--
-- Fuel: abilities pay their cost up front (AbilityService); soul-fire channels
-- also drain it every tick and stop when it runs dry, and the reservoir doesn't
-- refill while soul fire is flowing. "Heat" (the Phase attribute, 0..1) rises
-- with every shot and cools on its own; clients use it to make the barrel and
-- nozzles glow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local AbilityKit = require(script.Parent.Parent.Combat.AbilityKit)
local CharacterService = require(script.Parent.Parent.Services.CharacterService)
local ConstructService = require(script.Parent.Parent.Services.ConstructService)
local ProjectileService = require(script.Parent.Parent.Services.ProjectileService)

local Attribute = Protocol.Attribute

local MachineMaster = {}
local abilities = {}
MachineMaster.abilities = abilities

-- Most a shot can aim up or down (degrees)
local MAX_PITCH = math.rad(30)
-- Heat lost per second, how long the barrel stays hot after the last shot
-- before it starts cooling, and the step it's published in (fewer attribute updates)
local COOL_RATE = 0.35
local COOL_DELAY = 0.5
local HEAT_STEP = 0.05
-- Shields look this many frames ahead for projectiles about to cross them
local SHIELD_LOOKAHEAD = 2.5
-- Where shots and soul fire leave his gear, relative to his root (x right, y up, -z forward)
local MUZZLE = Vector3.new(0.9, 0.5, -1.6)
local MISSILE_POD = Vector3.new(-1.1, 2.3, 0.2)
local NOZZLES = {
	Vector3.new(-1.5, 2.1, -0.4),
	Vector3.new(1.5, 2.1, -0.4),
	Vector3.new(-1.9, 0.4, -0.6),
	Vector3.new(1.9, 0.4, -0.6),
}
local UP = Vector3.new(0, 1, 0)

local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude
worldParams.RespectCanCollide = true

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Rays ignore fighters and drawn effects: only walls, floors and barriers count
local function rayParams(): RaycastParams
	local ignore: { Instance } = {}
	for _, fighter in CharacterService:all() do
		table.insert(ignore, fighter.model)
	end
	local effects = workspace:FindFirstChild("SNEffects")
	if effects then
		table.insert(ignore, effects)
	end
	worldParams.FilterDescendantsInstances = ignore
	return worldParams
end

-- The floor under the fighter; falls back to just below their feet
local function groundBelow(ctx): Vector3
	local root = ctx.fighter.root
	local result = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), rayParams())
	return if result then result.Position else root.Position - Vector3.new(0, 3, 0)
end

-- How far a straight line can go before something solid stops it
local function clearLength(ctx, from: Vector3, direction: Vector3, length: number): number
	local result = workspace:Raycast(from, direction * length, rayParams())
	return if result then (result.Position - from).Magnitude else length
end

-- A point relative to the fighter, facing their aim
local function fromBody(ctx, offset: Vector3): Vector3
	local root = ctx.fighter.root
	return (CFrame.lookAt(root.Position, root.Position + ctx.direction) * CFrame.new(offset)).Position
end

local function muzzle(ctx): Vector3
	return fromBody(ctx, MUZZLE)
end

-- Turns a flat direction by `angle` radians around the vertical axis
local function turned(direction: Vector3, angle: number): Vector3
	return CFrame.Angles(0, angle, 0):VectorToWorldSpace(direction)
end

-- A flat direction tilted up (or down) by `pitch` radians
local function pitched(flat: Vector3, pitch: number): Vector3
	return (flat * math.cos(pitch) + UP * math.sin(pitch)).Unit
end

-- Which way a shot from `from` should fly: at the point under the cursor when
-- there is one (not too close), otherwise along the camera's look; never too steep
local function aimFrom(ctx, from: Vector3): Vector3
	local wanted = ctx.look
	if ctx.point and (ctx.point - from).Magnitude > 4 then
		wanted = ctx.point - from
	end
	local flat = Hitbox.flatDirection(wanted) or ctx.direction
	local pitch = math.asin(math.clamp(wanted.Unit.Y, -1, 1))
	return pitched(flat, math.clamp(pitch, -MAX_PITCH, MAX_PITCH))
end

local function awayFrom(center: Vector3, target): Vector3?
	return Hitbox.flatDirection(target.root.Position - center)
end

-- Heat and fuel --------------------------------------------------------------------------

local function publishHeat(fighter, data)
	local shown = math.floor((data.heat or 0) / HEAT_STEP + 0.5) * HEAT_STEP
	if shown ~= data.shownHeat and fighter.model.Parent then
		data.shownHeat = shown
		fighter.model:SetAttribute(Attribute.Phase, shown)
	end
end

-- A cast that outlives a reset (match end, respawn) holds the old life's
-- data; it mustn't heat the new barrel or stop the new reservoir refilling
local function stillCurrent(ctx): boolean
	local runtime = ctx.runtime
	return runtime ~= nil and ctx.fighter.power == runtime and runtime.data == ctx.data
end

local function heat(ctx, amount: number)
	if not stillCurrent(ctx) then
		return
	end
	local data = ctx.data
	data.heat = math.clamp((data.heat or 0) + amount, 0, 1)
	data.heatedAt = now()
	publishHeat(ctx.fighter, data)
end

-- Marks soul fire as flowing for a moment (the reservoir doesn't refill meanwhile)
local function burning(ctx, seconds: number)
	if stillCurrent(ctx) then
		ctx.data.burningUntil = now() + seconds
	end
end

-- Takes up to `amount` fuel; returns how much there was to take
local function drain(ctx, amount: number): number
	local taken = math.min(amount, math.max(0, ctx:resource()))
	if taken > 0 then
		ctx:spend(taken)
	end
	return taken
end

function MachineMaster.tick(fighter, runtime, dt: number)
	local data = runtime.data
	local resourceDef = runtime.def.resource
	if (data.burningUntil or 0) > now() and resourceDef and resourceDef.regen then
		-- Undo this tick's regeneration: soul fire is pouring out
		runtime.resource = math.max(0, runtime.resource - resourceDef.regen * dt)
	end
	local current = data.heat or 0
	if current > 0 and now() - (data.heatedAt or 0) >= COOL_DELAY then
		data.heat = math.max(0, current - COOL_RATE * dt)
		publishHeat(fighter, data)
	end
end

-- The ultimate needs fuel on top of a full charge
function MachineMaster.canUse(_fighter, runtime, def)
	if def.fuelCost and runtime.resource + 1e-6 < def.fuelCost then
		return false, `Needs {def.fuelCost} fuel`
	end
	return true
end

-- Projectile helpers -----------------------------------------------------------------------

local function hasTag(projectile, tag: string): boolean
	local tags = projectile.spec.tags
	return tags ~= nil and table.find(tags, tag) ~= nil
end

-- Can his gadgets shoot this down? Small projectiles (or ones marked
-- interceptable) only; never massive ones or ones marked interceptable = false.
local function shootable(projectile): boolean
	local spec = projectile.spec
	if spec.interceptable == false or hasTag(projectile, "Massive") then
		return false
	end
	return spec.interceptable == true or hasTag(projectile, "Small")
end

local function enemyProjectile(ctx, projectile): boolean
	return projectile.alive and projectile.ownerId ~= ctx.fighter.id and ctx:isEnemy(projectile.owner)
end

local function landed(outcome): boolean
	return outcome ~= nil and outcome.result == "Hit"
end

-- Shields -------------------------------------------------------------------------------
-- Shield parts don't collide, so his own shots pass through them; enemy
-- projectiles about to cross a shield's surface are stopped there instead
-- (each costs the shield that much health). Massive ones smash the shield and fly on.

-- Where a path from→to enters a flat panel from its front side (nil if it doesn't)
local function panelCrossing(frame: CFrame, halfWidth: number, halfHeight: number)
	return function(from: Vector3, to: Vector3, radius: number): Vector3?
		local a = frame:PointToObjectSpace(from)
		local b = frame:PointToObjectSpace(to)
		-- The front is -Z (the way the panel faces). Only paths heading into it count.
		if a.Z > 0.3 or b.Z <= a.Z or b.Z < -radius then
			return nil
		end
		local t = if a.Z < -radius then (-radius - a.Z) / (b.Z - a.Z) else 0
		local point = a:Lerp(b, math.clamp(t, 0, 1))
		if math.abs(point.X) > halfWidth + radius or math.abs(point.Y) > halfHeight + radius then
			return nil
		end
		return frame:PointToWorldSpace(Vector3.new(point.X, point.Y, 0))
	end
end

-- Where a path from→to enters a dome from outside (nil if it doesn't)
local function domeCrossing(center: Vector3, domeRadius: number)
	return function(from: Vector3, to: Vector3, radius: number): Vector3?
		local outer = domeRadius + radius
		local start = from - center
		-- Fired from inside: the dome doesn't stop it
		if start.Magnitude < domeRadius - 0.5 then
			return nil
		end
		local path = to - from
		local a = path:Dot(path)
		if a < 1e-6 then
			return nil
		end
		local b = 2 * start:Dot(path)
		local c = start:Dot(start) - outer * outer
		local discriminant = b * b - 4 * a * c
		if discriminant < 0 then
			return nil
		end
		local t = (-b - math.sqrt(discriminant)) / (2 * a)
		if t < 0 then
			-- Already touching the surface: stop it if it's heading in
			return if c <= 0 and start:Dot(path) < 0 then from else nil
		end
		return if t <= 1 then from + path * t else nil
	end
end

-- Watches for enemy projectiles while the shield stands. Returns stop().
local function guardShield(ctx, construct, center: Vector3, reach: number, crossing)
	local connection: RBXScriptConnection? = nil
	local function stop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end
	local function enemy(projectile): boolean
		return enemyProjectile(ctx, projectile)
	end
	connection = RunService.Heartbeat:Connect(function(dt: number)
		if not construct.alive then
			stop()
			return
		end
		local ahead = math.max(math.min(dt, 0.1), 1 / 60) * SHIELD_LOOKAHEAD
		for _, projectile in ProjectileService:nearby(center, reach, enemy) do
			local from = projectile.position
			local point = crossing(from, from + projectile.velocity * ahead, projectile.radius)
			if point then
				if hasTag(projectile, "Massive") then
					ctx:fx("ShieldShatter", { position = point })
					ConstructService:destroy(construct, "Broken")
					stop()
					return
				end
				ConstructService:damage(construct, projectile.spec.hit.Damage or 0)
				ProjectileService:finish(projectile, "Intercepted", point)
				ctx:fx("ShieldBlock", { position = point, broken = not construct.alive })
				if not construct.alive then
					stop()
					return
				end
			end
		end
	end)
	ctx:own(stop)
	return stop
end

local function shieldPart(model: Model, name: string, cframe: CFrame, size: Vector3, color: Color3, material: Enum.Material, transparency: number): Part
	local part = Instance.new("Part")
	part.Name = name
	part.CFrame = cframe
	part.Size = size
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	part.CanCollide = false
	part.Parent = model
	return part
end

local GUNMETAL = Color3.fromRGB(62, 68, 80)
local CYAN = Color3.fromRGB(70, 185, 255)
local SOUL = Color3.fromRGB(40, 110, 255)

-- A slightly curved energy panel on an emitter bar, with posts at the sides
local function buildPanel(model: Model, frame: CFrame, width: number, height: number)
	local segment = width / 3
	for index = -1, 1 do
		local yaw = math.rad(-14 * index)
		local piece = frame * CFrame.new(index * segment * 0.97, 0.2, math.abs(index) * 0.35) * CFrame.Angles(0, yaw, 0)
		shieldPart(model, "Panel", piece, Vector3.new(segment + 0.1, height - 0.6, 0.25), CYAN, Enum.Material.ForceField, 0.15)
	end
	-- The emitter bar is the model's pivot (anything asking where the shield is gets its base)
	model.PrimaryPart = shieldPart(model, "Emitter", frame * CFrame.new(0, -height / 2 + 0.25, 0.2), Vector3.new(width, 0.5, 0.8), GUNMETAL, Enum.Material.Metal, 0)
	shieldPart(model, "EmitterGlow", frame * CFrame.new(0, -height / 2 + 0.52, 0.2), Vector3.new(width - 0.4, 0.08, 0.3), CYAN, Enum.Material.Neon, 0)
	for _, side in { -1, 1 } do
		shieldPart(model, "Post", frame * CFrame.new(side * (width / 2 + 0.1), 0, 0.5), Vector3.new(0.35, height, 0.5), GUNMETAL, Enum.Material.Metal, 0)
	end
	local light = Instance.new("PointLight")
	light.Color = CYAN
	light.Range = 10
	light.Brightness = 1.2
	light.Parent = model:FindFirstChild("EmitterGlow")
end

-- A hemisphere of force over a projector disc
local function buildDome(model: Model, center: Vector3, radius: number)
	local dome = shieldPart(model, "Dome", CFrame.new(center), Vector3.one * radius * 2, CYAN, Enum.Material.ForceField, 0.35)
	dome.Shape = Enum.PartType.Ball
	local base = shieldPart(model, "Projector", CFrame.new(center + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.4, 2.4, 2.4), GUNMETAL, Enum.Material.Metal, 0)
	base.Shape = Enum.PartType.Cylinder
	model.PrimaryPart = base
	local ring = shieldPart(model, "ProjectorRing", CFrame.new(center + Vector3.new(0, 0.45, 0)) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.1, 1.6, 1.6), CYAN, Enum.Material.Neon, 0)
	ring.Shape = Enum.PartType.Cylinder
	local light = Instance.new("PointLight")
	light.Color = CYAN
	light.Range = radius * 1.5
	light.Brightness = 1
	light.Parent = ring
end

-- A squat pulse mine: metal base, glowing soul-fire core, fins, and a faint
-- ring on the floor showing how close is too close
local function buildDevice(model: Model, at: Vector3, trigger: number)
	local base = shieldPart(model, "Base", CFrame.new(at + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.5, 1.8, 1.8), GUNMETAL, Enum.Material.Metal, 0)
	base.Shape = Enum.PartType.Cylinder
	base.CanCollide = true
	model.PrimaryPart = base
	local core = shieldPart(model, "Core", CFrame.new(at + Vector3.new(0, 0.7, 0)), Vector3.one * 0.9, SOUL, Enum.Material.Neon, 0)
	core.Shape = Enum.PartType.Ball
	core.CanCollide = true
	for index = 0, 3 do
		local angle = index * math.pi / 2
		shieldPart(model, "Fin", CFrame.new(at + Vector3.new(0, 0.55, 0)) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -0.85), Vector3.new(0.15, 0.5, 0.5), GUNMETAL, Enum.Material.Metal, 0)
	end
	local zone = shieldPart(model, "TriggerRing", CFrame.new(at + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.05, trigger * 2, trigger * 2), SOUL, Enum.Material.Neon, 0.88)
	zone.Shape = Enum.PartType.Cylinder
	local light = Instance.new("PointLight")
	light.Color = SOUL
	light.Range = 8
	light.Brightness = 1.5
	light.Parent = core
end

-- Basic attacks ---------------------------------------------------------------------------

function abilities.BlasterShot(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local from = muzzle(ctx)
	ctx:projectile({
		visual = "Bolt",
		origin = from,
		direction = aimFrom(ctx, from),
		speed = def.speed,
		radius = def.radius,
		lifetime = def.lifetime,
		range = def.range,
		interceptable = true,
	})
	heat(ctx, 0.04)
end

function abilities.ChargedShot(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local from = muzzle(ctx)
	ctx:projectile({
		visual = "HeavyBolt",
		origin = from,
		direction = aimFrom(ctx, from),
		speed = def.speed,
		radius = def.radius,
		lifetime = def.lifetime,
		range = def.range,
		-- Too heavy to shoot down
		interceptable = false,
		explode = { radius = def.splash.radius, hit = AbilityKit.hitFrom(def.splash) },
		data = { splash = def.splash.radius },
	})
	heat(ctx, 0.12)
end

-- Degree 1 -------------------------------------------------------------------------------

function abilities.ScatterBlast(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local from = muzzle(ctx)
	local center = aimFrom(ctx, from)
	local flat = Hitbox.flatDirection(center) or ctx.direction
	local pitch = math.asin(math.clamp(center.Y, -1, 1))
	-- Every pellet shares who's been hit: one pellet per target
	local pellets = {}
	local function shareHit(_projectile, target)
		for _, pellet in pellets do
			pellet.hitIds[target.id] = true
		end
	end
	for index = 1, def.pellets do
		local alpha = if def.pellets > 1 then (index - 1) / (def.pellets - 1) - 0.5 else 0
		-- A fixed fan (readable, no luck), every other pellet a little higher
		local lift = pitch + math.rad(if index % 2 == 0 then 3 else -2)
		local pellet = ctx:projectile({
			visual = "Pellet",
			origin = from,
			direction = pitched(turned(flat, math.rad(def.spread * alpha)), lift),
			speed = def.speed,
			radius = def.radius,
			lifetime = def.lifetime,
			range = def.range,
			interceptable = false,
			onHit = shareHit,
		})
		if pellet then
			table.insert(pellets, pellet)
		end
	end
	ctx:fx("ScatterFire", { origin = from, direction = center, spread = def.spread })
	heat(ctx, 0.12)
end

function abilities.ShockPulse(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local center = ctx:origin()
	ctx:fx("ShockPulse", { position = center, radius = def.radius })
	for _, target in ctx:inSphere(center, def.radius) do
		if ctx:lineOfSight(center, target.root.Position) then
			ctx:hit(target, nil, { direction = awayFrom(center, target) })
		end
	end
	heat(ctx, 0.1)
end

function abilities.DeflectorShield(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local facing = ctx.direction
	local center = groundBelow(ctx) + facing * def.distance + Vector3.new(0, def.height / 2, 0)
	local frame = CFrame.lookAt(center, center + facing)
	local stopGuard: (() -> ())? = nil
	local construct = ctx:construct({
		name = "DeflectorShield",
		duration = def.duration,
		health = def.health,
		limit = 1,
		collides = false,
		build = function(model)
			buildPanel(model, frame, def.width, def.height)
		end,
		onEnd = function(_, reason)
			if stopGuard then
				stopGuard()
			end
			ctx:fx("ShieldEnd", { position = center, reason = reason })
		end,
	})
	ctx:fx("ShieldUp", { position = center, width = def.width, height = def.height })
	stopGuard = guardShield(ctx, construct, center, math.max(def.width, def.height) + 40, panelCrossing(frame, def.width / 2, def.height / 2))
end

-- The closest enemy projectile he can shoot down and has a clear shot at
local function nearestShootable(ctx, range: number)
	local from = muzzle(ctx)
	local best, bestDistance = nil, math.huge
	local candidates = ProjectileService:nearby(ctx:origin(), range, function(projectile)
		return enemyProjectile(ctx, projectile) and shootable(projectile)
	end)
	for _, projectile in candidates do
		local distance = (projectile.position - from).Magnitude
		if distance < bestDistance and ctx:lineOfSight(from, projectile.position) then
			best, bestDistance = projectile, distance
		end
	end
	return best
end

-- Watches a moment for something to shoot; one projectile per use
function abilities.Intercept(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local endsAt = ctx:now() + def.active
	while true do
		local projectile = nearestShootable(ctx, def.range)
		if projectile then
			local from = muzzle(ctx)
			local at = projectile.position
			ProjectileService:finish(projectile, "Intercepted", at)
			ctx:fx("InterceptShot", { from = from, to = at })
			heat(ctx, 0.08)
			return
		end
		if ctx:now() >= endsAt or not ctx:wait(0.03) then
			break
		end
	end
	ctx:fx("InterceptMiss", {})
	ctx:refund(0.5)
end

-- Degree 2 -------------------------------------------------------------------------------

function abilities.RailShot(ctx)
	local def = ctx.def
	-- The direction is locked when the charge starts, so the prompt is honest
	local direction = ctx.direction
	local function beamStart(): Vector3
		return ctx:origin() + Vector3.new(0, 0.5, 0) + direction * 1.5
	end
	local start = beamStart()
	local length = clearLength(ctx, start, direction, def.range)
	ctx:telegraph(ctx:alongLine(start, direction, length, def.width + 2), ctx:activeAt())
	ctx:fx("RailCharge", { origin = start, direction = direction, length = length, duration = def.startup })
	if not ctx:waitActive() then
		ctx:fx("RailFizzle", {})
		return
	end
	start = beamStart()
	length = clearLength(ctx, start, direction, def.range)
	ctx:fx("RailFire", { origin = start, direction = direction, length = length, width = def.width })
	for _, target in ctx:alongLine(start, direction, length, def.width) do
		if ctx:lineOfSight(start, target.root.Position) then
			ctx:hit(target, nil, { direction = direction, origin = start })
		end
	end
	heat(ctx, 0.3)
end

-- Who the missiles chase: the enemy nearest the aimed point, else the nearest in front
local function missileTarget(ctx, range: number)
	if ctx.point then
		local best, bestDistance = nil, 14
		for _, enemy in ctx:enemies() do
			local distance = (enemy.root.Position - ctx.point).Magnitude
			if distance < bestDistance and (enemy.root.Position - ctx:origin()).Magnitude <= range then
				best, bestDistance = enemy, distance
			end
		end
		if best then
			return best
		end
	end
	return ctx:nearestEnemy(range, 120)
end

function abilities.MissileVolley(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local target = missileTarget(ctx, def.range * 0.7)
	for index = 1, def.missiles do
		if index > 1 and not ctx:wait(def.interval) then
			return
		end
		local from = fromBody(ctx, MISSILE_POD)
		local side = index - (def.missiles + 1) / 2
		ctx:fx("MissileLaunch", { position = from, index = index })
		local direction
		if target then
			-- Up and out of the pod, then the homing brings them round
			local root = ctx.fighter.root
			local frame = CFrame.lookAt(root.Position, root.Position + ctx.direction)
			direction = (frame.LookVector + frame.UpVector * 0.3 + frame.RightVector * side * 0.35).Unit
		else
			-- Nobody to chase: a tight spread along the aim
			local aim = aimFrom(ctx, from)
			local flat = Hitbox.flatDirection(aim) or ctx.direction
			direction = pitched(turned(flat, math.rad(side * 6)), math.asin(math.clamp(aim.Y, -1, 1)))
		end
		ctx:projectile({
			visual = "Missile",
			origin = from,
			direction = direction,
			speed = def.speed,
			radius = def.radius,
			lifetime = def.lifetime,
			range = def.range,
			homing = if target then { target = target, turnRate = def.turnRate } else nil,
			interceptable = true,
			explode = { radius = def.splash.radius, hit = AbilityKit.hitFrom(def.splash) },
		})
	end
	heat(ctx, 0.15)
end

function abilities.BarrierProjector(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local center = groundBelow(ctx)
	local stopGuard: (() -> ())? = nil
	local construct = ctx:construct({
		name = "BarrierProjector",
		duration = def.duration,
		health = def.health,
		limit = 1,
		collides = false,
		build = function(model)
			buildDome(model, center, def.radius)
		end,
		onEnd = function(_, reason)
			if stopGuard then
				stopGuard()
			end
			ctx:fx("ShieldEnd", { position = center + Vector3.new(0, 2, 0), reason = reason })
		end,
	})
	ctx:fx("ProjectorUp", { position = center, radius = def.radius })
	stopGuard = guardShield(ctx, construct, center, def.radius + 40, domeCrossing(center, def.radius))
end

-- Degree 3: soul fire --------------------------------------------------------------------

-- Where a sweeping stream points `elapsed` seconds in: it swings to one side,
-- back, to the other side and back once per period (clients draw the same curve)
local function streamAngle(def, elapsed: number): number
	return math.rad(def.sweep / 2) * math.sin(2 * math.pi * elapsed / def.period)
end

function abilities.SweepingStreams(ctx)
	local def = ctx.def
	local center = ctx.direction
	ctx:fx("StreamsIgnite", { duration = def.startup, direction = center, range = def.range, sweep = def.sweep + def.arc })
	if not ctx:waitActive() then
		return
	end
	local startedAt = ctx:now()
	local stopFx = ctx:lastingFx("Streams", def.active, {
		startedAt = startedAt,
		direction = center,
		range = def.range,
		arc = def.arc,
		sweep = def.sweep,
		period = def.period,
	})
	ctx:onCleanup(stopFx)
	local lastHit: { [string]: number } = {}
	local reason = "Done"
	while ctx:now() - startedAt < def.active do
		if not ctx:alive() then
			reason = "Interrupted"
			break
		end
		local wanted = def.drain * def.tick
		local paid = drain(ctx, wanted)
		if paid <= 0.01 then
			reason = "Fuel"
			break
		end
		burning(ctx, def.tick + 0.15)
		local look = turned(center, streamAngle(def, ctx:now() - startedAt))
		for _, target in ctx:inArc(def.range, def.arc, ctx:origin(), look) do
			if ctx:now() - (lastHit[target.id] or -math.huge) >= def.hitEvery then
				lastHit[target.id] = ctx:now()
				ctx:hit(target, nil, { kind = "Zone", direction = look })
			end
		end
		heat(ctx, 0.5 * def.tick)
		if paid < wanted - 1e-6 then
			-- That was the last of the fuel
			reason = "Fuel"
			break
		end
		task.wait(def.tick)
	end
	stopFx()
	ctx:fx("StreamsEnd", { reason = reason })
	if reason ~= "Interrupted" then
		ctx:finish()
	end
end

function abilities.PressurizedBurst(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local origin = ctx:origin()
	local direction = ctx.direction
	ctx:fx("Burst", { origin = origin, direction = direction, range = def.range, arc = def.arc })
	-- The blast burns away a few small projectiles inside its cone (not everything)
	local burned = 0
	local burnedAt: { Vector3 } = {}
	local cosine = math.cos(math.rad(def.arc / 2))
	local nearby = ProjectileService:nearby(origin, def.range + 2, function(projectile)
		return enemyProjectile(ctx, projectile) and shootable(projectile)
	end)
	for _, projectile in nearby do
		local flat = Hitbox.flatDirection(projectile.position - origin)
		if burned < def.burnsAway and (flat == nil or flat:Dot(direction) >= cosine) then
			burned += 1
			table.insert(burnedAt, projectile.position)
			ProjectileService:finish(projectile, "Intercepted", projectile.position)
		end
	end
	if #burnedAt > 0 then
		ctx:fx("BurnAway", { positions = burnedAt })
	end
	for _, target in ctx:inArc(def.range, def.arc) do
		ctx:hit(target, nil, { direction = direction })
	end
	-- Recoil: the burst shoves him backwards
	ctx:dash(-direction * def.recoil, def.recoilTime)
	heat(ctx, 0.25)
end

-- A soul-fire explosion that hurts everyone close by (except `skip`, already hit directly)
local function soulBlast(ctx, position: Vector3, splash, skip: { [string]: boolean })
	for _, target in ctx:inSphere(position, splash.radius) do
		if not skip[target.id] and ctx:lineOfSight(position, target.root.Position) then
			ctx:hit(target, splash, { kind = "Projectile", origin = position, direction = awayFrom(position, target) })
		end
	end
end

function abilities.SoulFireballs(ctx)
	local def = ctx.def
	local me = ctx.fighter
	if not ctx:waitActive() then
		return
	end
	local function burnOnHit(projectile, victim, outcome)
		if projectile.ownerId == me.id and landed(outcome) then
			ctx:status(victim, "Burn", def.burn.duration, { magnitude = def.burn.damage, data = { power = ctx.power, ability = def.id } })
		end
	end
	local function explodeOnEnd(projectile, position: Vector3, reason: string)
		-- Explodes against targets and surfaces only; a fireball that fades just fizzles.
		-- A fireball someone took over (Syntax) only does its own capped hit.
		if (reason ~= "Hit" and reason ~= "World") or projectile.redirected or projectile.ownerId ~= me.id then
			return
		end
		local back = if projectile.velocity.Magnitude > 0.1 then projectile.velocity.Unit * 0.6 else Vector3.zero
		soulBlast(ctx, position - back, def.splash, projectile.hitIds)
	end
	for index = 1, def.count do
		if index > 1 and not ctx:wait(def.interval) then
			return
		end
		local from = fromBody(ctx, NOZZLES[(index - 1) % #NOZZLES + 1]) + ctx.direction * 1.2
		-- Converge on the aimed point, lifted a little for the drop
		local target = if ctx.point then ctx.point else ctx:origin() + ctx.direction * 40
		local toTarget = target - from
		local travel = toTarget.Magnitude / def.speed
		local lifted = toTarget + Vector3.new(0, 0.5 * def.gravity * travel * travel, 0)
		local flat = Hitbox.flatDirection(lifted) or ctx.direction
		local pitch = math.clamp(math.asin(math.clamp(lifted.Unit.Y, -1, 1)), -MAX_PITCH, MAX_PITCH)
		ctx:projectile({
			visual = "Fireball",
			origin = from,
			direction = pitched(flat, pitch),
			speed = def.speed,
			gravity = def.gravity,
			radius = def.radius,
			lifetime = def.lifetime,
			range = def.range,
			interceptable = true,
			onHit = burnOnHit,
			onEnd = explodeOnEnd,
			data = { splash = def.splash.radius },
		})
	end
	burning(ctx, 0.4)
	heat(ctx, 0.3)
end

-- Where a device lands: the aimed spot (within range, in sight), on the floor
local function deviceSpot(ctx, range: number): Vector3?
	local origin = ctx:origin()
	local wanted = ctx.point or (origin + ctx.direction * 6)
	local offset = Vector3.new(wanted.X - origin.X, 0, wanted.Z - origin.Z)
	if offset.Magnitude > range then
		offset = offset.Unit * range
	elseif offset.Magnitude < 2 then
		offset = ctx.direction * 3
	end
	local above = origin + offset + Vector3.new(0, 3, 0)
	if not ctx:lineOfSight(origin, above) then
		return nil
	end
	local ground = workspace:Raycast(above, Vector3.new(0, -14, 0), rayParams())
	return if ground then ground.Position else nil
end

function abilities.SoulforgeDevice(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local spot = deviceSpot(ctx, def.range)
	if not spot then
		ctx:fx("DeviceFail", {})
		ctx:refund(1)
		return
	end
	local at: Vector3 = spot
	local running = true
	local construct = ctx:construct({
		name = "SoulforgeDevice",
		duration = def.duration,
		health = def.health,
		limit = def.limit,
		build = function(model)
			buildDevice(model, at, def.trigger)
		end,
		onEnd = function(_, reason)
			running = false
			ctx:fx("DeviceEnd", { position = at, reason = reason })
		end,
	})
	ctx:own(function()
		running = false
	end)
	ctx:fx("DevicePlaced", { position = at, armTime = def.armTime, trigger = def.trigger })
	local core = at + Vector3.new(0, 0.8, 0)
	task.spawn(function()
		task.wait(def.armTime)
		if running and construct.alive then
			ctx:fx("DeviceArmed", { position = at, trigger = def.trigger })
		end
		while running and construct.alive do
			if #ctx:inSphere(at, def.trigger) > 0 then
				-- Beep, then burst: everyone close gets a dodge/block prompt
				local impactAt = ctx:now() + def.fuse
				ctx:telegraph(ctx:inSphere(at, def.radius + 2), impactAt)
				ctx:fx("DeviceTrigger", { position = at, radius = def.radius, fuse = def.fuse })
				task.wait(def.fuse)
				-- It can still be shot to pieces during the beep
				if not running or not construct.alive then
					return
				end
				ctx:fx("DevicePulse", { position = at, radius = def.radius })
				for _, target in ctx:inSphere(at, def.radius) do
					if ctx:lineOfSight(core, target.root.Position) then
						local outcome = ctx:hit(target, nil, { kind = "Zone", origin = at, direction = awayFrom(at, target) })
						if landed(outcome) then
							ctx:status(target, "Slow", def.slow.duration, { magnitude = def.slow.magnitude })
						end
					end
				end
				ConstructService:destroy(construct, "Detonated")
				return
			end
			task.wait(0.1)
		end
	end)
end

-- Ultimate --------------------------------------------------------------------------------

-- Blue Inferno's sweep: one pass from left to right across the fan
local function infernoAngle(def, elapsed: number): number
	local share = math.clamp(elapsed / def.sweepTime, 0, 1)
	return math.rad(def.sweep / 2 - def.sweep * share)
end

-- The blast lands at the aimed point (or straight ahead), within reach and in sight
local function blastPoint(ctx, def): Vector3
	local origin = ctx:origin()
	local wanted = ctx.point or (origin + ctx.direction * def.blastDistance)
	local offset = Vector3.new(wanted.X - origin.X, 0, wanted.Z - origin.Z)
	local direction = Hitbox.flatDirection(offset) or ctx.direction
	local distance = math.clamp(offset.Magnitude, 4, def.blastDistance)
	distance = math.min(distance, math.max(2, clearLength(ctx, origin, direction, distance) - 1.5))
	return groundBelow(ctx) + direction * distance
end

function abilities.BlueInferno(ctx)
	local def = ctx.def
	local center = ctx.direction
	ctx:spend(def.fuelCost)
	burning(ctx, def.startup + 0.2)
	local blast = blastPoint(ctx, def)
	ctx:fx("InfernoIgnite", { duration = def.startup, direction = center, range = def.range, sweep = def.sweep + def.arc, blast = blast, blastRadius = def.blastRadius })
	if not ctx:waitActive() then
		ctx:fx("InfernoFizzle", {})
		return
	end

	-- The sweep
	local startedAt = ctx:now()
	local stopFx = ctx:lastingFx("InfernoSweep", def.sweepTime, {
		startedAt = startedAt,
		direction = center,
		range = def.range,
		arc = def.arc,
		sweep = def.sweep,
		sweepTime = def.sweepTime,
	})
	ctx:onCleanup(stopFx)
	local lastHit: { [string]: number } = {}
	while ctx:now() - startedAt < def.sweepTime do
		if not ctx:alive() then
			ctx:fx("InfernoFizzle", {})
			return
		end
		burning(ctx, def.tick + 0.15)
		local look = turned(center, infernoAngle(def, ctx:now() - startedAt))
		for _, target in ctx:inArc(def.range, def.arc, ctx:origin(), look) do
			if ctx:now() - (lastHit[target.id] or -math.huge) >= def.hitEvery then
				lastHit[target.id] = ctx:now()
				ctx:hit(target, def.sweepHit, { kind = "Zone", direction = look })
			end
		end
		heat(ctx, def.tick)
		task.wait(def.tick)
	end
	stopFx()

	-- The blast: a timing bar for everyone near where it will land
	local impactAt = ctx:now() + def.blastCharge
	ctx:telegraph(ctx:inSphere(blast, def.blastRadius + 6), impactAt)
	ctx:fx("InfernoCharge", { position = blast, radius = def.blastRadius, duration = def.blastCharge })
	if not ctx:waitUntil(impactAt) then
		ctx:fx("InfernoFizzle", {})
		return
	end
	ctx:fx("InfernoBlast", { position = blast, radius = def.blastRadius })
	local core = blast + Vector3.new(0, 1.5, 0)
	for _, target in ctx:inSphere(blast, def.blastRadius) do
		if ctx:lineOfSight(core, target.root.Position) then
			ctx:hit(target, nil, { origin = blast, direction = awayFrom(blast, target) })
		end
	end
	ctx:fx("InfernoEnd", {})
end

return MachineMaster
