-- Strong Dude's abilities on the server: shockwaves, grabs, a committed
-- charge, an uppercut launcher, a stomp, throwing arena objects, the Iron Body
-- counter stance, a travelling fissure and the World Breaker ultimate.
-- Numbers come from Shared/Powers/StrongDude.luau (scaled by degree).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FighterState = require(ReplicatedStorage.Shared.Combat.FighterState)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local StrongDude = {}
local abilities = {}
StrongDude.abilities = abilities

-- How long a thrown arena object takes to come back
local PROP_RETURN = 8
-- Most a throw can aim up or down (degrees), and how fast thrown things drop
local THROW_PITCH = { min = -15, max = 25 }
local THROW_GRAVITY = 28

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

-- The floor under the fighter (for shockwaves); falls back to just below their feet
local function groundBelow(ctx): Vector3
	local root = ctx.fighter.root
	groundParams.FilterDescendantsInstances = { ctx.fighter.model }
	local result = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), groundParams)
	return if result then result.Position else root.Position - Vector3.new(0, 3, 0)
end

local function awayFrom(center: Vector3, target): Vector3?
	return Hitbox.flatDirection(target.root.Position - center)
end

-- Groundbreaker / Quake Stomp: a ring around the fighter; jumping clears it
local function shockwave(ctx, windupFx: string, impactFx: string, telegraph: boolean)
	local def = ctx.def
	if telegraph then
		ctx:telegraph(ctx:inSphere(ctx:origin(), def.radius + 4, def.jumpClearance), ctx:activeAt())
	end
	ctx:fx(windupFx, { duration = def.startup, radius = def.radius })
	if not ctx:waitActive() then
		return
	end
	local center = groundBelow(ctx)
	ctx:fx(impactFx, { position = center, radius = def.radius })
	for _, target in ctx:inSphere(center, def.radius, def.jumpClearance) do
		ctx:hit(target, nil, { direction = awayFrom(center, target) })
	end
end

function abilities.Groundbreaker(ctx)
	shockwave(ctx, "GroundbreakerWindup", "GroundbreakerImpact", true)
end

function abilities.QuakeStomp(ctx)
	shockwave(ctx, "StompWindup", "StompImpact", false)
end

function abilities.TitanGrip(ctx)
	local def = ctx.def
	ctx:fx("GripReach", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local targets = ctx:inArc(def.range, def.arc)
	local target = targets[1]
	-- Closest one in reach
	for _, candidate in targets do
		if (candidate.root.Position - ctx:origin()).Magnitude < (target.root.Position - ctx:origin()).Magnitude then
			target = candidate
		end
	end
	-- Dodging (or spawn protection) slips the grab
	if not target or FighterState.isInvulnerable(target.state, ctx:now()) then
		ctx:fx("GripWhiff", {})
		return
	end
	ctx:fx("GripCatch", { target = target.model, hold = def.hold })
	local result = ctx:grab(target, { hold = def.hold, presses = def.escapePresses })
	if result ~= "Held" or not ctx:alive() then
		if result == "Escaped" then
			ctx:fx("GripBroken", { target = target.model })
		end
		ctx:finish()
		return
	end
	-- Slam (or, at Earthshaker, hurl them across the arena)
	ctx:fx("GripSlam", { target = target.model, hurl = ctx.degree >= 3 })
	ctx:hit(target, nil, { direction = ctx.direction, noDefense = true })
	ctx:finish()
end

function abilities.MeteorCharge(ctx)
	local def = ctx.def
	local length = def.speed * def.active
	local path = ctx:alongLine(ctx:origin(), ctx.direction, length, def.width)
	for _, target in path do
		local distance = (target.root.Position - ctx:origin()).Magnitude
		ctx:telegraph({ target }, ctx:activeAt() + distance / def.speed)
	end
	ctx:fx("ChargeWindup", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	ctx:dash(ctx.direction * def.speed, def.active)
	ctx:fx("ChargeRun", { duration = def.active, direction = ctx.direction })
	local endsAt = ctx:now() + def.active
	local victim = nil
	while ctx:now() < endsAt and ctx:alive() do
		local ahead = ctx:origin() + ctx.direction * 2
		local found = ctx:inSphere(ahead, def.width / 2 + 0.5)
		if #found > 0 then
			victim = found[1]
			break
		end
		task.wait(0.03)
	end
	ctx:stopDash()
	if not ctx:alive() then
		return
	end
	if victim then
		ctx:fx("ChargeImpact", { position = victim.root.Position })
		ctx:hit(victim, nil, { direction = ctx.direction })
		ctx:finish()
	else
		-- A missed charge leaves him wide open
		ctx:extendRecovery(def.whiffRecovery)
	end
end

function abilities.CrushingUppercut(ctx)
	local def = ctx.def
	ctx:fx("UppercutWindup", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local targets = ctx:inArc(def.range, def.arc)
	ctx:fx("Uppercut", { landed = #targets > 0 })
	for _, target in targets do
		ctx:hit(target, nil, { direction = ctx.direction })
	end
end

-- Heave ---------------------------------------------------------------------------

local function findProp(fighter, reach: number, maxWeight: number): BasePart?
	local best, bestDistance = nil, reach
	for _, prop in CollectionService:GetTagged(Protocol.Tag.Throwable) do
		if prop:IsA("BasePart") and prop:IsDescendantOf(workspace) and not prop:GetAttribute("Held") then
			local weight = prop:GetAttribute("Weight")
			local distance = (prop.Position - fighter.root.Position).Magnitude
			if typeof(weight) == "number" and weight <= maxWeight and distance <= bestDistance then
				best, bestDistance = prop, distance
			end
		end
	end
	return best
end

local function hideProp(prop: BasePart)
	prop:SetAttribute("Held", true)
	prop:SetAttribute("SavedTransparency", prop.Transparency)
	prop.Transparency = 1
	prop.CanCollide = false
	prop.CanQuery = false
end

local function returnProp(prop: BasePart)
	if not prop.Parent then
		return
	end
	local home = prop:GetAttribute("HomeCFrame")
	if typeof(home) == "CFrame" then
		prop.CFrame = home
	end
	local saved = prop:GetAttribute("SavedTransparency")
	prop.Transparency = if typeof(saved) == "number" then saved else 0
	prop.CanCollide = true
	prop.CanQuery = true
	prop:SetAttribute("Held", nil)
end

function StrongDude.canUse(fighter, runtime, def)
	if def.id == "Heave" and not def.ripDebris and not findProp(fighter, def.reach, def.maxWeight) then
		return false, "Nothing light enough to lift nearby"
	end
	return true
end

function abilities.Heave(ctx)
	local def = ctx.def
	local prop = findProp(ctx.fighter, def.reach, def.maxWeight)
	local weight, look
	if prop then
		hideProp(prop)
		weight = prop:GetAttribute("Weight") :: number
		look = {
			size = prop.Size,
			color = prop.Color,
			material = prop.Material.Name,
			shape = if prop:IsA("Part") then prop.Shape.Name else "Block",
		}
		-- Whatever happens to the throw, the object comes back home
		ctx:onCleanup(function()
			task.delay(PROP_RETURN, returnProp, prop)
		end)
	elseif def.ripDebris then
		-- Earthshaker tears a chunk out of the floor instead
		weight = 3
		look = { size = Vector3.new(5.5, 4, 5), color = Color3.fromRGB(80, 74, 70), material = "Slate", shape = "Block", ripped = true }
	else
		ctx:refund(1)
		return
	end
	ctx:fx("HeaveLift", { duration = def.startup, look = look })
	if not ctx:waitActive() then
		return
	end

	local throw = def.throws[math.clamp(weight, 1, #def.throws)]
	local flat = ctx.direction
	local origin = ctx:origin() + Vector3.new(0, 3, 0) + flat * 2
	-- Aim at the point under the cursor (lifted a little for the drop), or where
	-- the camera looks, always within a sensible pitch
	local aimed = ctx.look
	if ctx.point then
		local toPoint = ctx.point - origin
		local travel = toPoint.Magnitude / throw.speed
		local lifted = toPoint + Vector3.new(0, 0.5 * THROW_GRAVITY * travel * travel, 0)
		if lifted.Magnitude > 1 then
			aimed = lifted.Unit
		end
	end
	local pitch = math.deg(math.asin(math.clamp(aimed.Y, -1, 1)))
	pitch = math.clamp(pitch, THROW_PITCH.min, THROW_PITCH.max)
	local direction = (flat * math.cos(math.rad(pitch)) + Vector3.new(0, math.sin(math.rad(pitch)), 0)).Unit
	local massive = weight >= 3
	ctx:projectile({
		visual = "Prop",
		origin = origin,
		direction = direction,
		speed = throw.speed,
		gravity = THROW_GRAVITY,
		radius = throw.radius,
		lifetime = 3,
		range = def.range,
		hit = { Damage = throw.damage, Hitstun = 0.7, Knockback = throw.knockback, Launch = throw.launch, GuardDamage = throw.damage * 2 },
		tags = if massive then { "Projectile", "Massive" } elseif weight == 2 then { "Projectile", "Heavy" } else { "Projectile", "Small" },
		defense = if massive then "Timing" else nil,
		-- Small objects can be shot down or taken over; huge ones can't
		redirectable = not massive,
		interceptable = weight == 1,
		data = look,
	})
end

-- Iron Body: endure close-range hits and throw the attacker
function abilities.IronBody(ctx)
	local def = ctx.def
	local me = ctx.fighter
	ctx:fx("IronBody", { duration = def.startup + def.active })
	ctx:openCounter(def.startup + def.active, function(_, _, opts)
		return opts.kind == "Light" or opts.kind == "Heavy" or (opts.tags ~= nil and table.find(opts.tags, "Melee") ~= nil)
	end, function(attacker)
		task.spawn(function()
			if (attacker.root.Position - me.root.Position).Magnitude <= def.counterRange then
				ctx:fx("IronBodyCounter", { target = attacker.model })
				ctx:hit(attacker, nil, { direction = Hitbox.flatDirection(attacker.root.Position - me.root.Position), noDefense = true })
			end
			ctx:finish()
		end)
		return { damageScale = def.damageTaken, noFlinch = true, result = "Endured" }
	end)
	ctx:waitUntil(ctx:now() + def.startup + def.active)
end

function abilities.SeismicFissure(ctx)
	local def = ctx.def
	local start = groundBelow(ctx)
	local direction = ctx.direction
	for _, target in ctx:alongLine(start, direction, def.range, def.width) do
		local distance = (target.root.Position - start).Magnitude
		ctx:telegraph({ target }, ctx:activeAt() + distance / def.speed)
	end
	ctx:fx("FissureWindup", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	ctx:fx("Fissure", { origin = start, direction = direction, length = def.range, speed = def.speed, width = def.width })
	local hitIds = {}
	local step = 3
	local distance = 0
	-- The crack keeps going even if he's hit afterwards: it's already in the ground
	while distance <= def.range do
		local point = start + direction * distance
		for _, target in ctx:inSphere(point, def.width / 2 + 1, def.jumpClearance) do
			if not hitIds[target.id] then
				hitIds[target.id] = true
				ctx:hit(target, nil, { direction = direction, origin = point })
			end
		end
		distance += step
		task.wait(step / def.speed)
		if not ctx.fighter.model.Parent then
			return
		end
	end
end

function abilities.WorldBreaker(ctx)
	local def = ctx.def
	-- Everyone who could be in front gets the timing bar
	ctx:telegraph(ctx:inArc(def.range + 6, def.arc + 30), ctx:activeAt())
	ctx:fx("WorldBreakerWindup", { duration = def.startup, range = def.range })
	if not ctx:waitActive() then
		ctx:fx("WorldBreakerFizzle", {})
		return
	end
	local origin = groundBelow(ctx)
	ctx:fx("WorldBreakerImpact", { origin = origin, direction = ctx.direction, range = def.range, arc = def.arc })
	for _, target in ctx:inArc(def.range, def.arc) do
		ctx:hit(target, nil, { direction = ctx.direction })
	end
end

return StrongDude
