-- The toolkit every power's abilities are written with. An ability handler
-- gets a `ctx` for its cast: who's casting, the ability's numbers at the
-- caster's degree, where they're aiming, and safe helpers for finding targets,
-- hitting them, moving, teleporting, firing projectiles, placing zones and
-- constructs, applying statuses, telegraphing defenses, and drawing effects.
--
-- Every helper validates on the server (targets must be real, hittable
-- opponents; teleports must land somewhere safe; everything temporary ends on
-- its own) so ability code can stay short and readable.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FighterState = require(ReplicatedStorage.Shared.Combat.FighterState)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AbilityEvent = Remotes:WaitForChild("AbilityEvent") :: RemoteEvent

local Event = Protocol.AbilityEvent

local AbilityKit = {}
AbilityKit.__index = AbilityKit

local services: any = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

function AbilityKit.init(allServices)
	services = allServices
end

-- Turns an ability's lowercase numbers into the attack fields HitResolver uses
function AbilityKit.hitFrom(spec: { [string]: any }): { [string]: any }
	return {
		Damage = spec.damage or 0,
		Hitstun = spec.hitstun or 0,
		Knockback = spec.knockback or 0,
		Launch = spec.launch or 0,
		GuardDamage = spec.guardDamage or 0,
		Blockable = spec.blockable,
		Parryable = spec.parryable,
		Finisher = spec.finisher,
	}
end

-- A context for one cast (AbilityService makes these). Outside casts (passives,
-- hooks) use AbilityKit.forFighter, which has the same helpers.
function AbilityKit.new(fighter, runtime, def, aim, attack)
	local self = setmetatable({}, AbilityKit)
	self.fighter = fighter
	self.runtime = runtime
	self.def = def
	self.degree = runtime.degree
	self.power = runtime.id
	self.data = runtime.data
	self.attack = attack
	self.token = if attack then attack.token else nil
	self.cleanups = {}
	-- Aim: a flat unit direction and an optional point, both already validated
	self.direction = aim.direction
	self.point = aim.point
	self.look = aim.look
	self.startedAt = now()
	return self
end

function AbilityKit.forFighter(fighter)
	local runtime = fighter.power
	local self = setmetatable({}, AbilityKit)
	self.fighter = fighter
	self.runtime = runtime
	self.def = nil
	self.degree = if runtime then runtime.degree else 1
	self.power = if runtime then runtime.id else nil
	self.data = if runtime then runtime.data else {}
	self.cleanups = {}
	local look = fighter.root.CFrame.LookVector
	self.direction = Hitbox.flatDirection(look) or Vector3.new(0, 0, -1)
	self.look = look
	self.startedAt = now()
	return self
end

-- Time and lifetime -----------------------------------------------------------------

function AbilityKit:now(): number
	return now()
end

-- Is the cast still going? False once the caster is stunned out of it, knocked
-- out, removed, or their match stopped allowing combat.
function AbilityKit:alive(): boolean
	local fighter = self.fighter
	if not services.CharacterService:isAlive(fighter) then
		return false
	end
	if self.token and not FighterState.isCurrent(fighter.state, self.token) then
		return false
	end
	return services.MatchService:isCombatAllowed(fighter)
end

-- Waits until a server time; returns whether the cast is still going
function AbilityKit:waitUntil(time: number): boolean
	local remaining = time - now()
	if remaining > 0 then
		task.wait(remaining + 0.005)
	end
	return self:alive()
end

function AbilityKit:wait(seconds: number): boolean
	return self:waitUntil(now() + seconds)
end

-- When the cast's startup ends (the moment it should hit)
function AbilityKit:activeAt(): number
	return if self.attack then self.attack.activeAt else now()
end

function AbilityKit:waitActive(): boolean
	return self:waitUntil(self:activeAt())
end

-- Ends the cast now (recovery starts). For channels that stop early.
function AbilityKit:finish()
	if self.token then
		FighterState.finishAbility(self.fighter.state, self.token, now())
		services.CharacterService:refresh(self.fighter)
	end
end

-- More recovery (a missed charge)
function AbilityKit:extendRecovery(seconds: number)
	if self.token then
		FighterState.extendRecovery(self.fighter.state, self.token, seconds)
		services.CharacterService:refresh(self.fighter)
	end
end

-- Runs when the cast is over, however it ended
function AbilityKit:onCleanup(callback: () -> ())
	table.insert(self.cleanups, callback)
end

function AbilityKit:_runCleanups()
	for _, callback in self.cleanups do
		local ok, err = pcall(callback)
		if not ok then
			warn("[Abilities] cleanup failed: " .. tostring(err))
		end
	end
	table.clear(self.cleanups)
end

-- Something that outlives the cast but must end with its owner (zones, held props)
function AbilityKit:own(stop: () -> ())
	local handles = self.runtime and self.runtime.handles
	if handles then
		table.insert(handles, stop)
	end
end

-- Resources ----------------------------------------------------------------------------

function AbilityKit:resource(): number
	return services.PowerService:resource(self.fighter)
end

function AbilityKit:spend(amount: number): boolean
	return services.PowerService:spend(self.fighter, amount)
end

function AbilityKit:gain(amount: number)
	services.PowerService:gain(self.fighter, amount)
end

-- Gives back part of the cost and cooldown (the ability couldn't happen)
function AbilityKit:refund(share: number?)
	if self.def then
		services.PowerService:refund(self.fighter, self.def, share or 1)
	end
end

-- Effects for clients ---------------------------------------------------------------

-- Tells every client to draw `fx` (looked up in the power's client module)
function AbilityKit:fx(name: string, data: { [string]: any }?)
	AbilityEvent:FireAllClients(Event.Fx, {
		fighter = self.fighter.model,
		power = self.power,
		fx = name,
		data = data or {},
	})
end

-- Same, but for an effect that lasts: the client keeps it until `seconds` pass
-- or the returned stop() is called
function AbilityKit:lastingFx(name: string, seconds: number, data: { [string]: any }?): () -> ()
	local key = services.PowerService:nextKey()
	local payload = data or {}
	payload.key = key
	payload.duration = seconds
	self:fx(name, payload)
	local stopped = false
	return function()
		if stopped then
			return
		end
		stopped = true
		AbilityEvent:FireAllClients(Event.Fx, { fighter = self.fighter.model, power = "Common", fx = "Stop", data = { key = key } })
	end
end

-- Targets -------------------------------------------------------------------------------

local function isEnemy(self, target): boolean
	return target ~= self.fighter
		and services.CharacterService:isAlive(target)
		and services.MatchService:canDamage(self.fighter, target)
end

-- Every opponent this caster could hurt right now
function AbilityKit:enemies(): { any }
	local list = {}
	for _, target in services.CharacterService:all() do
		if isEnemy(self, target) then
			table.insert(list, target)
		end
	end
	return list
end

function AbilityKit:isEnemy(target): boolean
	return isEnemy(self, target)
end

function AbilityKit:origin(): Vector3
	return self.fighter.root.Position
end

function AbilityKit:lineOfSight(from: Vector3, to: Vector3): boolean
	return services.CombatService:hasLineOfSight(from, to)
end

-- In front within range and arc (like a punch)
function AbilityKit:inArc(range: number, arc: number, origin: Vector3?, look: Vector3?): { any }
	local from = origin or self:origin()
	local facing = look or self.direction
	local combat = self.fighter.combat
	local reach = {
		range = range,
		arc = arc,
		verticalReach = combat.VerticalReach,
		targetRadius = combat.TargetRadius,
		pointBlank = combat.PointBlankRange,
	}
	local list = {}
	for _, target in self:enemies() do
		if Hitbox.inArc(from, facing, target.root.Position, reach) and self:lineOfSight(from, target.root.Position) then
			table.insert(list, target)
		end
	end
	return list
end

-- Within a radius of a point. `clearance`: anyone this far above the centre is missed
-- (jumping over a ground shockwave).
function AbilityKit:inSphere(center: Vector3, radius: number, clearance: number?): { any }
	local list = {}
	local targetRadius = self.fighter.combat.TargetRadius
	for _, target in self:enemies() do
		local offset = target.root.Position - center
		local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
		local above = offset.Y
		local inside = if clearance then flat <= radius + targetRadius and above <= clearance + 3 and above >= -6 else offset.Magnitude <= radius + targetRadius
		if inside then
			table.insert(list, target)
		end
	end
	return list
end

-- Inside an oriented box
function AbilityKit:inBox(cframe: CFrame, size: Vector3): { any }
	local list = {}
	local half = size / 2 + Vector3.one * self.fighter.combat.TargetRadius
	for _, target in self:enemies() do
		local localPosition = cframe:PointToObjectSpace(target.root.Position)
		if math.abs(localPosition.X) <= half.X and math.abs(localPosition.Y) <= half.Y and math.abs(localPosition.Z) <= half.Z then
			table.insert(list, target)
		end
	end
	return list
end

-- Along a line (beams, charges, cracks), nearest first
function AbilityKit:alongLine(origin: Vector3, direction: Vector3, length: number, width: number): { any }
	local unit = if direction.Magnitude > 0.01 then direction.Unit else self.direction
	local found = {}
	local targetRadius = self.fighter.combat.TargetRadius
	for _, target in self:enemies() do
		local offset = target.root.Position - origin
		local along = offset:Dot(unit)
		if along >= -1 and along <= length + targetRadius then
			local sideways = (offset - unit * along)
			local flatSideways = Vector3.new(sideways.X, 0, sideways.Z).Magnitude
			if flatSideways <= width / 2 + targetRadius and math.abs(sideways.Y) <= 5 then
				table.insert(found, { target = target, along = along })
			end
		end
	end
	table.sort(found, function(a, b)
		return a.along < b.along
	end)
	local list = {}
	for _, entry in found do
		table.insert(list, entry.target)
	end
	return list
end

-- The closest opponent within range (and within `arc` degrees of the aim, if given)
function AbilityKit:nearestEnemy(range: number, arc: number?): any?
	local best, bestDistance = nil, math.huge
	local origin = self:origin()
	for _, target in self:enemies() do
		local offset = target.root.Position - origin
		local distance = offset.Magnitude
		if distance <= range and distance < bestDistance then
			local flat = Hitbox.flatDirection(offset)
			local within = arc == nil or flat == nil or math.deg(math.acos(math.clamp(flat:Dot(self.direction), -1, 1))) <= arc / 2
			if within then
				best, bestDistance = target, distance
			end
		end
	end
	return best
end

-- Hitting ------------------------------------------------------------------------------

-- Hits one target with this ability's numbers (or `spec`'s, if given). Returns
-- the outcome. `extra`: { direction, origin, tags, cueId, kind }
function AbilityKit:hit(target, spec: { [string]: any }?, extra: { [string]: any }?)
	local source = spec or self.def
	local options = extra or {}
	-- A timing-bar attack gives the target's press a moment to arrive
	if self.def and self.def.defense == "Timing" and not options.noDefense then
		services.DefenseService:awaitTiming(target, self.fighter, self.def.id)
		if not services.CharacterService:isAlive(target) then
			return nil
		end
	end
	return services.CombatService:applyHit(self.fighter, target, AbilityKit.hitFrom(source), {
		kind = options.kind or "Ability",
		power = self.power,
		ability = if self.def then self.def.id else options.ability,
		tags = options.tags or (source and source.tags) or (self.def and self.def.tags),
		origin = options.origin,
		direction = options.direction,
		cueId = options.cueId,
		noDefense = options.noDefense,
	})
end

-- Hits a list; returns how many connected (hit, blocked or guard broken)
function AbilityKit:hitAll(targets: { any }, spec: { [string]: any }?, extra: { [string]: any }?): number
	local landed = 0
	for _, target in targets do
		local outcome = self:hit(target, spec, extra)
		if outcome and (outcome.result == "Hit" or outcome.result == "Blocked" or outcome.result == "GuardBreak") then
			landed += 1
		end
	end
	return landed
end

-- Tells everyone threatened what's coming: a dodge/block prompt or a timing bar,
-- whichever the ability's definition asks for
function AbilityKit:telegraph(targets: { any }, impactAt: number)
	if self.def then
		services.DefenseService:telegraph(self.fighter, targets, self.def, impactAt)
	end
end

-- Movement ----------------------------------------------------------------------------

function AbilityKit:push(target, direction: Vector3, horizontal: number, vertical: number, duration: number?)
	local scale = target.combat.KnockbackTaken or 1
	services.DamageService:push(target, direction, horizontal * scale, vertical * scale, duration)
end

-- Moves the caster at `velocity` for `duration` (dashes, charges). The client
-- simulating the character runs it, so it's smooth for players too.
function AbilityKit:dash(velocity: Vector3, duration: number)
	local fighter = self.fighter
	local root = fighter.root
	if root.Anchored then
		return
	end
	fighter.dashUntil = now() + duration + 0.3
	for _, child in root:GetChildren() do
		if child.Name == "SNDash" then
			child:Destroy()
		end
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "SNDash"
	attachment.Parent = root
	local mover = Instance.new("LinearVelocity")
	mover.Name = "SNDash"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.VectorVelocity = velocity
	mover.MaxForce = math.huge
	mover.Parent = root
	Debris:AddItem(mover, duration)
	Debris:AddItem(attachment, duration)
end

function AbilityKit:stopDash()
	for _, child in self.fighter.root:GetChildren() do
		if child.Name == "SNDash" then
			child:Destroy()
		end
	end
end

-- Teleports the caster (or `who`) to a safe spot as close to `desired` as
-- possible. Returns (ok, where). Fails safely if nothing valid is found.
-- opts: { maxDistance: number?, who: fighter?, facing: Vector3? }
function AbilityKit:teleport(desired: Vector3, opts: { maxDistance: number?, who: any?, facing: Vector3? }?): (boolean, Vector3?)
	local options = opts or {}
	local who = options.who or self.fighter
	local destination = services.PowerService:safeSpot(who, desired, options.maxDistance)
	if not destination then
		return false, nil
	end
	local facing = options.facing or who.root.CFrame.LookVector
	local flat = Hitbox.flatDirection(facing) or Vector3.new(0, 0, -1)
	services.CharacterService:teleport(who, CFrame.lookAt(destination, destination + flat))
	return true, destination
end

-- Statuses, projectiles, zones, constructs ------------------------------------------

function AbilityKit:status(target, statusId: string, duration: number, opts: { magnitude: number?, data: { [string]: any }? }?)
	local options = opts or {}
	return services.StatusService:apply(target, statusId, duration, {
		source = self.fighter,
		magnitude = options.magnitude,
		data = options.data,
	})
end

function AbilityKit:hasStatus(target, statusId: string): boolean
	return services.StatusService:has(target, statusId)
end

function AbilityKit:clearStatus(target, statusId: string)
	services.StatusService:remove(target, statusId)
end

-- Fires a projectile (see ProjectileService.Spec). power/ability/hit/tags default
-- to this cast's.
function AbilityKit:projectile(spec: { [string]: any })
	spec.power = spec.power or self.power
	spec.ability = spec.ability or (self.def and self.def.id) or "Projectile"
	spec.hit = spec.hit or AbilityKit.hitFrom(self.def or {})
	spec.tags = spec.tags or (self.def and self.def.tags)
	spec.label = spec.label or (self.def and self.def.name)
	return services.ProjectileService:spawn(self.fighter, spec)
end

-- A lasting area: every `tick` seconds, onTick(targets inside) runs (or `hit`
-- is applied to each, at most once per `hitEvery` seconds per target). Ends after
-- `duration`, or when its owner is knocked out or reset. Returns stop().
-- spec: { center, radius, duration, tick?, hit?, hitEvery?, clearance?, onTick?, fx?, fxData? }
function AbilityKit:zone(spec: { [string]: any }): () -> ()
	local running = true
	local stopFx: (() -> ())? = nil
	if spec.fx then
		local data = spec.fxData or {}
		data.center = spec.center
		data.radius = spec.radius
		stopFx = self:lastingFx(spec.fx, spec.duration, data)
	end
	local function stop()
		if running then
			running = false
			if stopFx then
				stopFx()
			end
		end
	end
	self:own(stop)
	local endsAt = now() + spec.duration
	local lastHit: { [string]: number } = {}
	task.spawn(function()
		while running and now() < endsAt do
			if not services.CharacterService:isAlive(self.fighter) then
				break
			end
			local targets = self:inSphere(spec.center, spec.radius, spec.clearance)
			if spec.onTick then
				spec.onTick(targets)
			elseif spec.hit then
				for _, target in targets do
					local last = lastHit[target.id] or -math.huge
					if now() - last >= (spec.hitEvery or 0.5) then
						lastHit[target.id] = now()
						self:hit(target, spec.hit, { kind = "Zone", origin = spec.center })
					end
				end
			end
			task.wait(spec.tick or 0.25)
		end
		stop()
	end)
	return stop
end

-- A physical construct (see ConstructService.Spec). power/ability default to this cast's.
function AbilityKit:construct(spec: { [string]: any })
	spec.power = spec.power or self.power
	spec.ability = spec.ability or (self.def and self.def.id)
	return services.ConstructService:create(self.fighter, spec)
end

-- A counter stance: hits that `accepts` approves during the window are answered by
-- `respond` instead (see DefenseService). Closed automatically when the cast ends.
function AbilityKit:openCounter(duration: number, accepts: (attacker: any, hit: any, opts: any) -> boolean, respond: (attacker: any, hit: any, opts: any) -> any)
	local counter = { endsAt = now() + duration, accepts = accepts, respond = respond }
	services.DefenseService:openCounter(self.fighter, counter)
	local function close()
		services.DefenseService:closeCounter(self.fighter, counter)
	end
	self:onCleanup(close)
	return close
end

-- Grabs `target`: they're held in front of the caster and can mash to escape.
-- Yields; returns "Escaped" | "Held" | "Cancelled". While held, the target is
-- rooted and can't act. spec: { hold, presses, offset? }
function AbilityKit:grab(target, spec: { hold: number, presses: number, offset: Vector3? })
	local fighter = self.fighter
	local hold = spec.hold
	services.StatusService:apply(target, "Grabbed", hold + 0.2, { source = fighter })
	FighterState.applyStun(target.state, hold + 0.1, now())
	services.CharacterService:refresh(target)

	-- Keep the victim in front of the grabber
	local attachment = Instance.new("Attachment")
	attachment.Name = "SNGrabbed"
	attachment.Parent = target.root
	local holder = Instance.new("AlignPosition")
	holder.Name = "SNGrabbed"
	holder.Mode = Enum.PositionAlignmentMode.OneAttachment
	holder.Attachment0 = attachment
	holder.MaxForce = 1e6
	holder.Responsiveness = 60
	holder.Parent = target.root
	local offset = spec.offset or Vector3.new(0, 1.5, -3.2)
	local following = true
	task.spawn(function()
		while following and holder.Parent do
			if fighter.root.Parent then
				holder.Position = (fighter.root.CFrame * CFrame.new(offset)).Position
			end
			task.wait()
		end
	end)
	local function release()
		following = false
		holder:Destroy()
		attachment:Destroy()
		services.StatusService:remove(target, "Grabbed")
	end
	self:own(release)
	self:onCleanup(release)

	-- The cast has to last through the hold (and the grabber can be hit out of it)
	if self.token then
		FighterState.extendRecovery(fighter.state, self.token, hold)
		services.CharacterService:refresh(fighter)
	end
	local result = services.DefenseService:grab(target, fighter, {
		hold = hold,
		presses = spec.presses,
		ability = self.def and self.def.id,
		power = self.power,
		label = self.def and self.def.name,
		holding = function()
			return self:alive()
		end,
	})
	release()
	if result == "Escaped" then
		-- Breaking free leaves the grabber open and the victim free to act
		local time = now()
		target.state.stunUntil = math.min(target.state.stunUntil, time)
		FighterState.applyStun(fighter.state, services.PowerService.EscapeStun, time)
		services.CharacterService:refresh(target)
		services.CharacterService:refresh(fighter)
		self:push(target, -self.direction, 30, 10)
	end
	return result
end

return AbilityKit
