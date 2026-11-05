-- Server-simulated projectiles: energy slashes, blaster bolts, soul-fire
-- fireballs, thrown boulders, code packets. The server moves every projectile,
-- checks what it touches (walls, barriers, fighters) and decides the hit;
-- clients only draw it, predicting its flight from the spawn message. Every
-- projectile has a strict lifetime and a cap per fighter, and is removed when
-- its owner leaves, is knocked out or their match ends.
--
-- Interactive defenses hook in here: massive projectiles give their targets a
-- timing bar before impact, and Syntax gets a redirect prompt for eligible ones.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AbilityEvent = Remotes:WaitForChild("AbilityEvent") :: RemoteEvent

local Event = Protocol.AbilityEvent
local LIMITS = Combat.Projectiles

local ProjectileService = {}

export type Spec = {
	power: string,
	ability: string,
	-- Which drawing the client uses (looked up in the power's client module)
	visual: string,
	origin: Vector3,
	direction: Vector3,
	speed: number,
	-- Downward pull in studs/s² (0 = flies straight)
	gravity: number?,
	radius: number,
	lifetime: number,
	-- Most distance it can travel
	range: number?,
	-- Attack fields for what it does to whoever it hits (Damage, Hitstun, Knockback...)
	hit: { [string]: any },
	tags: { string }?,
	-- How many extra fighters it can pass through
	pierce: number?,
	-- Can Syntax take it over? Can Machine Master shoot it down?
	redirectable: boolean?,
	interceptable: boolean?,
	-- "Timing" gives targets a timing bar before impact
	defense: string?,
	-- Explodes where it ends, hitting everyone within this radius
	explode: { radius: number, hit: { [string]: any } }?,
	-- Turns toward this fighter (degrees per second)
	homing: { target: any, turnRate: number }?,
	-- Extra values the client drawing uses (colour, size...)
	data: { [string]: any }?,
	onHit: ((projectile: any, target: any, outcome: any) -> ())?,
	onEnd: ((projectile: any, position: Vector3, reason: string) -> ())?,
}

local active: { [string]: any } = {}
local count = 0

local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude
worldParams.RespectCanCollide = true

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Closest distance between a point and the segment a→b, and how far along it is
local function segmentDistance(point: Vector3, a: Vector3, b: Vector3): (number, number)
	local ab = b - a
	local length = ab.Magnitude
	if length < 1e-4 then
		return (point - a).Magnitude, 0
	end
	local along = math.clamp((point - a):Dot(ab) / (length * length), 0, 1)
	return (point - (a + ab * along)).Magnitude, along
end

local function isFiniteVector(value: Vector3): boolean
	return value.X == value.X and value.Y == value.Y and value.Z == value.Z
		and math.abs(value.X) < 1e7 and math.abs(value.Y) < 1e7 and math.abs(value.Z) < 1e7
end

function ProjectileService:Init(services)
	self.services = services
	self.characters = services.CharacterService
end

function ProjectileService:Start()
	RunService.Heartbeat:Connect(function(dt)
		if count > 0 then
			self:_step(math.min(dt, 0.1))
		end
	end)
	local function clearOwner(fighter)
		self:clearOwner(fighter)
	end
	self.characters:onKnockout(clearOwner)
	self.characters:onUnregistered(clearOwner)
end

local function ownedBy(fighterId: string): number
	local total = 0
	for _, projectile in active do
		if projectile.ownerId == fighterId then
			total += 1
		end
	end
	return total
end

-- Fires a projectile owned by `owner`. Returns the projectile, or nil if the
-- owner already has too many in the air (or the spec is junk).
function ProjectileService:spawn(owner, spec: Spec)
	if count >= LIMITS.MaxTotal or ownedBy(owner.id) >= LIMITS.MaxPerFighter then
		return nil
	end
	local direction = spec.direction
	if not isFiniteVector(direction) or direction.Magnitude < 0.01 or not isFiniteVector(spec.origin) then
		return nil
	end
	direction = direction.Unit
	local time = now()
	local projectile = {
		id = HttpService:GenerateGUID(false) .. tostring(count),
		owner = owner,
		ownerId = owner.id,
		spec = spec,
		position = spec.origin,
		velocity = direction * spec.speed,
		gravity = spec.gravity or 0,
		radius = math.clamp(spec.radius, 0.2, 12),
		spawnedAt = time,
		expiresAt = time + math.min(spec.lifetime, LIMITS.MaxLifetime),
		traveled = 0,
		range = spec.range or math.huge,
		pierceLeft = spec.pierce or 0,
		hitIds = {},
		cued = {},
		redirected = false,
		alive = true,
	}
	active[projectile.id] = projectile
	count += 1
	AbilityEvent:FireAllClients(Event.ProjectileSpawn, {
		id = projectile.id,
		owner = owner.model,
		power = spec.power,
		ability = spec.ability,
		visual = spec.visual,
		origin = spec.origin,
		velocity = projectile.velocity,
		gravity = projectile.gravity,
		radius = projectile.radius,
		t0 = time,
		lifetime = projectile.expiresAt - time,
		data = spec.data,
	})
	return projectile
end

function ProjectileService:get(id: any)
	if typeof(id) ~= "string" then
		return nil
	end
	return active[id]
end

-- Removes a projectile. reason: "Hit" | "World" | "Expired" | "Destroyed" | "Intercepted" | "Range"
function ProjectileService:finish(projectile, reason: string, at: Vector3?)
	if not projectile.alive then
		return
	end
	projectile.alive = false
	active[projectile.id] = nil
	count -= 1
	local position = at or projectile.position
	local spec = projectile.spec
	-- Explosions happen wherever it ends (but not when it's shot down or removed)
	if spec.explode and reason ~= "Intercepted" and reason ~= "Destroyed" then
		self:_explode(projectile, position)
	end
	AbilityEvent:FireAllClients(Event.ProjectileEnd, { id = projectile.id, position = position, reason = reason })
	if spec.onEnd then
		task.spawn(spec.onEnd, projectile, position, reason)
	end
end

function ProjectileService:clearOwner(fighter)
	for _, projectile in table.clone(active) do
		if projectile.ownerId == fighter.id then
			self:finish(projectile, "Destroyed")
		end
	end
end

-- Projectiles near a point that `filter(projectile)` accepts (for interceptions)
function ProjectileService:nearby(position: Vector3, radius: number, filter: ((any) -> boolean)?): { any }
	local found = {}
	for _, projectile in active do
		if (projectile.position - position).Magnitude <= radius and (not filter or filter(projectile)) then
			table.insert(found, projectile)
		end
	end
	return found
end

-- Hands a projectile to a new owner flying a new way (Syntax's redirect).
-- A redirected projectile can't be redirected again, and its damage is capped.
function ProjectileService:redirect(projectile, newOwner, direction: Vector3): boolean
	if not projectile.alive or projectile.redirected or projectile.spec.redirectable == false then
		return false
	end
	if not isFiniteVector(direction) or direction.Magnitude < 0.01 then
		return false
	end
	local time = now()
	projectile.redirected = true
	projectile.owner = newOwner
	projectile.ownerId = newOwner.id
	projectile.hitIds = {}
	projectile.cued = {}
	projectile.velocity = direction.Unit * projectile.spec.speed * 1.15
	projectile.traveled = 0
	projectile.expiresAt = math.min(time + 2.5, time + LIMITS.MaxLifetime)
	local hit = table.clone(projectile.spec.hit)
	hit.Damage = math.min(hit.Damage or 0, LIMITS.RedirectDamageCap)
	local spec = table.clone(projectile.spec)
	spec.hit = hit
	-- A redirected explosion is capped the same way
	if spec.explode then
		local explode = table.clone(spec.explode)
		explode.hit = table.clone(explode.hit)
		explode.hit.Damage = math.min(explode.hit.Damage or 0, LIMITS.RedirectDamageCap)
		spec.explode = explode
	end
	spec.homing = nil
	spec.onHit = nil
	projectile.spec = spec
	AbilityEvent:FireAllClients(Event.ProjectileUpdate, {
		id = projectile.id,
		owner = newOwner.model,
		origin = projectile.position,
		velocity = projectile.velocity,
		gravity = projectile.gravity,
		t0 = time,
		lifetime = projectile.expiresAt - time,
		redirected = true,
	})
	return true
end

-- Simulation -------------------------------------------------------------------------

function ProjectileService:_ignoreList(): { Instance }
	local ignore: { Instance } = {}
	for _, fighter in self.characters:all() do
		table.insert(ignore, fighter.model)
	end
	local effects = workspace:FindFirstChild("SNEffects")
	if effects then
		table.insert(ignore, effects)
	end
	return ignore
end

function ProjectileService:_step(dt: number)
	local time = now()
	local fighters = self.characters:all()
	worldParams.FilterDescendantsInstances = self:_ignoreList()
	local defense = self.services.DefenseService
	local matchService = self.services.MatchService
	local targetRadius = Combat.TargetRadius

	for _, projectile in table.clone(active) do
		if not projectile.alive then
			continue
		end
		if time >= projectile.expiresAt then
			self:finish(projectile, "Expired")
			continue
		end
		local spec = projectile.spec
		local owner = projectile.owner

		-- Homing turns toward the target a limited amount per second
		local homing = spec.homing
		if homing and homing.target and self.characters:isAlive(homing.target) then
			local wanted = homing.target.root.Position - projectile.position
			if wanted.Magnitude > 0.5 then
				local current = projectile.velocity.Unit
				local desired = wanted.Unit
				local angle = math.acos(math.clamp(current:Dot(desired), -1, 1))
				local maxTurn = math.rad(homing.turnRate) * dt
				if angle > 1e-3 then
					local t = math.min(1, maxTurn / angle)
					projectile.velocity = current:Lerp(desired, t).Unit * projectile.velocity.Magnitude
				end
			end
		end

		local from = projectile.position
		projectile.velocity += Vector3.new(0, -projectile.gravity * dt, 0)
		local delta = projectile.velocity * dt
		local to = from + delta

		-- Walls, floors and barriers
		local result
		if projectile.radius > 0.6 then
			result = workspace:Spherecast(from, math.min(projectile.radius * 0.6, 4), delta, worldParams)
		else
			result = workspace:Raycast(from, delta, worldParams)
		end
		local wallAlong = if result then (result.Position - from).Magnitude / math.max(delta.Magnitude, 1e-4) else 2

		-- Fighters: the earliest one along the path
		local victim, victimAlong = nil, math.huge
		for _, fighter in fighters do
			if
				fighter ~= owner
				and not projectile.hitIds[fighter.id]
				and self.characters:isAlive(fighter)
				and matchService:canDamage(owner, fighter)
			then
				local center = fighter.root.Position
				local distance, along = segmentDistance(center, from, to)
				-- A little extra height: characters are taller than they are wide
				local vertical = math.abs(center.Y - (from + (to - from) * along).Y)
				if distance <= projectile.radius + targetRadius and vertical <= 3.2 + projectile.radius and along < victimAlong then
					victim, victimAlong = fighter, along
				end
				-- Interactive defenses before impact (timing bars, Syntax's redirect).
				-- DefenseService remembers in projectile.cued what it already offered.
				if defense then
					local speed = projectile.velocity.Magnitude
					local toTarget = center - from
					local closing = if speed > 1 then toTarget:Dot(projectile.velocity.Unit) else -1
					if closing > 0 then
						local miss = (toTarget - projectile.velocity.Unit * closing).Magnitude
						if miss <= projectile.radius + targetRadius + 2 then
							defense:considerProjectile(fighter, projectile, closing / speed)
						end
					end
				end
			end
		end

		if victim and victimAlong <= wallAlong and defense and defense:holdProjectile(victim, projectile) then
			-- Their timing press may still be on its way: wait here a moment
			projectile.position = from + (to - from) * math.max(0, victimAlong - 0.05)
			continue
		end
		if victim and victimAlong <= wallAlong then
			local hitAt = from + (to - from) * victimAlong
			projectile.position = hitAt
			projectile.hitIds[victim.id] = true
			local outcome = self.services.CombatService:applyHit(owner, victim, spec.hit, {
				kind = "Projectile",
				power = spec.power,
				ability = spec.ability,
				tags = spec.tags,
				origin = hitAt,
				direction = Vector3.new(projectile.velocity.X, 0, projectile.velocity.Z).Magnitude > 0.1
						and Vector3.new(projectile.velocity.X, 0, projectile.velocity.Z).Unit
					or nil,
				projectile = projectile,
			})
			if spec.onHit then
				task.spawn(spec.onHit, projectile, victim, outcome)
			end
			if not projectile.alive then
				continue
			end
			if projectile.pierceLeft > 0 then
				projectile.pierceLeft -= 1
			else
				self:finish(projectile, "Hit", hitAt)
				continue
			end
		end

		if result then
			projectile.position = result.Position
			self.services.ConstructService:projectileHit(result.Instance, projectile)
			self:finish(projectile, "World", result.Position)
			continue
		end

		projectile.position = to
		projectile.traveled += delta.Magnitude
		if projectile.traveled >= projectile.range then
			self:finish(projectile, "Range")
		end
	end
end

-- Everyone near the end point takes the explosion (not the owner)
function ProjectileService:_explode(projectile, position: Vector3)
	local explode = projectile.spec.explode
	local owner = projectile.owner
	if not explode then
		return
	end
	local matchService = self.services.MatchService
	for _, fighter in self.characters:all() do
		if
			fighter ~= owner
			and not projectile.hitIds[fighter.id]
			and self.characters:isAlive(fighter)
			and matchService:canDamage(owner, fighter)
			and (fighter.root.Position - position).Magnitude <= explode.radius + Combat.TargetRadius
		then
			self.services.CombatService:applyHit(owner, fighter, explode.hit, {
				kind = "Projectile",
				power = projectile.spec.power,
				ability = projectile.spec.ability,
				tags = projectile.spec.tags,
				origin = position,
				projectile = projectile,
			})
		end
	end
end

return ProjectileService
