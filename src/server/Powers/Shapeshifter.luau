-- Animal Shapeshifter on the server: changing form (a short transition that a
-- hit can interrupt), Primal draining while transformed and the forced change
-- back at 0, the shared switch cooldown, each animal's Light and Heavy, and
-- Primal Ascendancy. Form stats (speed, health, armour, dodge, guard, target
-- size) come from the definition through PowerService:setForm and the combat
-- profile; this file only decides when the form changes.
-- Numbers come from Shared/Powers/Shapeshifter.luau (scaled by degree).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FighterState = require(ReplicatedStorage.Shared.Combat.FighterState)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Powers = require(ReplicatedStorage.Shared.Powers)

local Shapeshifter = {}
local abilities = {}
Shapeshifter.abilities = abilities

local POWER = "Shapeshifter"
local DEF = Powers.get(POWER)
local SHIFT = DEF.shifting
-- Statuses a form keeps on its owner while it lasts (refreshed before they run out)
local TRANSFORMED_REFRESH = 5
local GRAVITY_REFRESH = 2

local services: any = nil

function Shapeshifter.init(allServices)
	services = allServices
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function formAt(runtime, formId: string)
	local ability = Powers.abilityFor(POWER, formId, runtime.degree)
	return if ability and ability.kind == "Form" then ability else nil
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

-- The floor under a fighter, and how high above it they are
local function groundBelow(fighter): (Vector3, number)
	local root = fighter.root
	groundParams.FilterDescendantsInstances = { fighter.model }
	local result = workspace:Raycast(root.Position, Vector3.new(0, -40, 0), groundParams)
	if result then
		return result.Position, root.Position.Y - result.Position.Y
	end
	return root.Position - Vector3.new(0, 3, 0), 3
end

-- Every form waits for the same switch, so nobody flips form every frame
local function shareCooldown(fighter, runtime, readyAt: number)
	for _, abilityId in runtime.loadout do
		local ability = DEF.abilities[abilityId]
		if ability and ability.kind == "Form" and (runtime.cooldowns[abilityId] or 0) < readyAt then
			services.PowerService:setCooldown(fighter, abilityId, readyAt)
		end
	end
end

-- Statuses this power put on its owner for a form (someone else's Gravity well stays)
local function clearOwnStatuses(fighter)
	local statuses = services.StatusService
	for _, statusId in { "Transformed", "Gravity" } do
		local status = statuses:get(fighter, statusId)
		if status and status.sourceId == fighter.id then
			statuses:remove(fighter, statusId)
		end
	end
end

-- Keeps the form's marker and (aerial forms) its glide going
local function keepStatuses(fighter, form)
	local statuses = services.StatusService
	local time = now()
	local transformed = statuses:get(fighter, "Transformed")
	if not transformed or transformed.endsAt - time < TRANSFORMED_REFRESH then
		statuses:apply(fighter, "Transformed", 30, { source = fighter, data = { form = form.id } })
	end
	if form.form.gravity then
		local gravity = statuses:get(fighter, "Gravity")
		if not gravity then
			statuses:apply(fighter, "Gravity", 6, { source = fighter, magnitude = form.form.gravity })
		elseif gravity.sourceId == fighter.id and gravity.endsAt - time < GRAVITY_REFRESH then
			statuses:apply(fighter, "Gravity", 6, { source = fighter, magnitude = form.form.gravity })
		end
	end
end

local function enter(kit, form)
	local fighter, runtime = kit.fighter, kit.runtime
	local previous = runtime.form
	services.PowerService:setForm(fighter, form.id)
	runtime.data.formSince = now()
	runtime.data.shownForm = form.id
	-- A new animal: drop the old one's glide and marker and start its own
	clearOwnStatuses(fighter)
	keepStatuses(fighter, form)
	shareCooldown(fighter, runtime, now() + (form.cooldown or 0))
	kit:fx("Shift", { form = form.id, animal = form.form.animal, from = previous })
end

-- Back to human. reason: "Choice" | "Exhausted"
local function revert(kit, reason: string)
	local fighter, runtime = kit.fighter, kit.runtime
	local formId = runtime.form
	if formId == "" then
		return
	end
	local form = formAt(runtime, formId)
	services.PowerService:setForm(fighter, "")
	runtime.data.formSince = nil
	runtime.data.shownForm = ""
	clearOwnStatuses(fighter)
	local wait = if reason == "Exhausted" then SHIFT.exhaustedCooldown else (form and form.cooldown or 0)
	shareCooldown(fighter, runtime, now() + wait)
	kit:fx("Unshift", { form = formId, animal = form and form.form.animal, reason = reason })
end

Shapeshifter.revert = revert

-- Hooks ------------------------------------------------------------------------------------

function Shapeshifter.canUse(fighter, runtime, def)
	if def.kind ~= "Form" then
		return true
	end
	if runtime.data.transition then
		return false, "Already changing"
	end
	-- CPU opponents commit to a form for a while instead of flipping between them
	if fighter.npc then
		local since = runtime.data.formSince
		if runtime.form ~= "" and since and now() - since < SHIFT.cpuHold then
			return false, "Settled"
		end
		if runtime.form == "" and math.random() < 0.4 then
			return false, "Undecided"
		end
	end
	return true
end

-- Changing back from the form you're in is free
function Shapeshifter.costFor(_fighter, runtime, def): number
	if def.kind == "Form" and runtime.form == def.id then
		return 0
	end
	return def.cost or 0
end

function Shapeshifter.tick(fighter, runtime, dt: number, kit)
	local data = runtime.data
	local formId = runtime.form
	if data.shownForm ~= nil and data.shownForm ~= formId then
		-- Changed from outside (a knockout or a reset): drop what the old form left
		clearOwnStatuses(fighter)
		data.shownForm = formId
		data.formSince = nil
	end
	if formId == "" then
		return
	end
	local form = formAt(runtime, formId)
	if not form then
		revert(kit, "Choice")
		return
	end
	-- No regeneration while transformed: the form drains Primal instead
	local regen = DEF.resource.regen or 0
	runtime.resource = math.max(0, runtime.resource - (regen + form.form.drain) * dt)
	if runtime.resource <= 0 then
		revert(kit, "Exhausted")
		return
	end
	keepStatuses(fighter, form)
end

function Shapeshifter.onReset(fighter, runtime)
	clearOwnStatuses(fighter)
	runtime.data.shownForm = ""
end

-- The transition is a vulnerable moment
function Shapeshifter.modifyIncoming(_target, _attacker, outcome, _opts, runtime)
	if runtime.data.transition and outcome.damage then
		outcome.damage *= SHIFT.transitionDamage
	end
end

-- Forms ------------------------------------------------------------------------------------

local function shift(ctx)
	local def = ctx.def
	local fighter, runtime, data = ctx.fighter, ctx.runtime, ctx.data
	if runtime.form == def.id then
		-- Changing back is quick
		ctx:finish()
		revert(ctx, "Choice")
		return
	end
	local transition = { form = def.id }
	data.transition = transition
	ctx:onCleanup(function()
		if data.transition == transition then
			data.transition = nil
		end
	end)
	ctx:fx("ShiftBegin", { form = def.id, animal = def.form.animal, duration = def.startup })
	if not ctx:waitActive() then
		-- Hit out of it (or knocked out): the form stays as it was, part of the cost comes back
		if data.transition == transition then
			data.transition = nil
		end
		if fighter.power == runtime and services.CharacterService:isAlive(fighter) then
			ctx:gain((def.cost or 0) * SHIFT.interruptRefund)
			services.PowerService:setCooldown(fighter, def.id, now() + SHIFT.interruptCooldown)
			ctx:fx("ShiftBroken", { form = def.id })
		end
		return
	end
	data.transition = nil
	enter(ctx, def)
end

for abilityId, ability in DEF.abilities do
	if ability.kind == "Form" then
		abilities[abilityId] = shift
	end
end

-- Shared attack shapes ----------------------------------------------------------------------

local function scaled(def, scale: number, overrides: { [string]: number }?)
	local spec = {
		damage = (def.damage or 0) * scale,
		hitstun = def.hitstun,
		knockback = def.knockback,
		launch = def.launch,
		guardDamage = def.guardDamage,
		blockable = def.blockable,
		parryable = def.parryable,
	}
	for key, value in overrides or {} do
		spec[key] = if key == "damage" then value * scale else value
	end
	return spec
end

-- Spectral Wolf: bites and pounces hit harder on someone you marked
local function markScale(ctx, target): number
	if ctx.runtime.form ~= "WolfForm" then
		return 1
	end
	local pounce = Powers.abilityFor(POWER, "WolfPounce", ctx.degree)
	local mark = services.StatusService:get(target, "Mark")
	if pounce and pounce.markBonus and mark and mark.sourceId == ctx.fighter.id then
		return 1 + pounce.markBonus
	end
	return 1
end

-- A quick claw or bite in front: wind-up, then everyone in the arc
local function strike(ctx, fxName: string, data: { [string]: any }?, overrides: { [string]: number }?)
	local def = ctx.def
	local payload = data or {}
	payload.duration = def.startup
	ctx:fx(fxName, payload)
	if not ctx:waitActive() then
		return {}
	end
	local landed = {}
	for _, target in ctx:inArc(def.range, def.arc) do
		local outcome = ctx:hit(target, scaled(def, markScale(ctx, target), overrides), { direction = ctx.direction })
		if outcome and outcome.result == "Hit" then
			table.insert(landed, target)
		end
	end
	return landed
end

-- Moves the caster at `velocity` until it touches someone; returns them (or nil)
local function rush(ctx, velocity: Vector3, duration: number, width: number)
	ctx:dash(velocity, duration)
	local flat = Hitbox.flatDirection(velocity) or ctx.direction
	local endsAt = ctx:now() + duration
	local victim = nil
	while ctx:alive() do
		local found = ctx:inSphere(ctx:origin() + flat * 2, width / 2 + 0.5)
		if #found > 0 then
			victim = found[1]
			break
		end
		if ctx:now() >= endsAt then
			break
		end
		task.wait(0.03)
	end
	ctx:stopDash()
	return victim
end

-- Wolf --------------------------------------------------------------------------------------

function abilities.WolfBite(ctx)
	local def = ctx.def
	local data = ctx.data
	local chain = def.chain
	local time = ctx:now()
	local step = 1
	if time - (data.biteAt or -math.huge) <= chain.window then
		step = (data.biteStep or 0) % chain.every + 1
	end
	data.biteStep = step
	data.biteAt = time
	local finisher = step == chain.every
	strike(ctx, "Bite", { step = step, finisher = finisher }, if finisher then { damage = chain.damage, knockback = chain.knockback, hitstun = chain.hitstun } else nil)
end

function abilities.WolfPounce(ctx)
	local def = ctx.def
	ctx:fx("PounceCrouch", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local direction = ctx.direction
	ctx:fx("Pounce", { duration = def.active, direction = direction })
	local victim = rush(ctx, direction * def.speed, def.active, def.width)
	if not ctx:alive() then
		return
	end
	if not victim then
		ctx:extendRecovery(def.whiffRecovery)
		return
	end
	ctx:fx("PounceBite", { target = victim.model, spirit = def.markDuration ~= nil })
	local outcome = ctx:hit(victim, scaled(def, markScale(ctx, victim)), { direction = direction })
	if def.markDuration and outcome and (outcome.result == "Hit" or outcome.result == "Blocked") then
		ctx:status(victim, "Mark", def.markDuration)
		-- The spirit wolf that hounds them (visual; the bonus is on the wolf's own bites)
		ctx:own(ctx:lastingFx("SpiritWolf", def.markDuration, { target = victim.model }))
	end
	ctx:finish()
end

-- Hawk / Eagle / Storm Eagle ----------------------------------------------------------------

function abilities.HawkTalon(ctx)
	strike(ctx, "Talon", { airborne = select(2, groundBelow(ctx.fighter)) > 4.5 })
end

function abilities.HawkDive(ctx)
	local def = ctx.def
	local fighter = ctx.fighter
	local _, height = groundBelow(fighter)
	local airborne = height > 4.5
	local pitch = math.rad(if airborne then def.pitch else 6)
	local reach = def.speed * math.cos(pitch) * def.active
	if def.defense then
		local landing = ctx:origin() + ctx.direction * reach
		local threatened = ctx:inSphere(landing, def.radius + 3)
		for _, target in ctx:alongLine(ctx:origin(), ctx.direction, reach, def.radius) do
			if not table.find(threatened, target) then
				table.insert(threatened, target)
			end
		end
		ctx:telegraph(threatened, ctx:activeAt() + def.active * 0.6)
	end
	ctx:fx("DiveWindup", { duration = def.startup, lightning = def.lightning == true })
	if not ctx:waitActive() then
		return
	end
	local flat = ctx.direction
	-- Eagles bend the dive toward someone ahead
	if def.steer > 0 then
		local target = ctx:nearestEnemy(reach + 8, def.steer * 2)
		local toward = target and Hitbox.flatDirection(target.root.Position - ctx:origin())
		if toward then
			flat = toward
		end
	end
	local velocity = (flat * math.cos(pitch) - Vector3.yAxis * math.sin(pitch)) * def.speed
	ctx:fx("Dive", { duration = def.active, direction = flat, lightning = def.lightning == true })
	rush(ctx, velocity, def.active, def.radius)
	if not ctx:alive() then
		return
	end
	local center = groundBelow(fighter)
	ctx:fx("DiveImpact", { position = center, radius = def.radius, lightning = def.lightning == true })
	for _, target in ctx:inSphere(ctx:origin(), def.radius) do
		ctx:hit(target, nil, { direction = Hitbox.flatDirection(target.root.Position - ctx:origin()) or flat, origin = ctx:origin() })
	end
	ctx:finish()
end

-- Bear / Dire Bear / Mythic Bear --------------------------------------------------------------

function abilities.BearMaul(ctx)
	local data = ctx.data
	data.maulSide = if data.maulSide == 1 then -1 else 1
	strike(ctx, "Maul", { side = data.maulSide })
end

function abilities.BearSlam(ctx)
	local def = ctx.def
	local fighter = ctx.fighter
	local function center(): Vector3
		return groundBelow(fighter) + ctx.direction * def.reach
	end
	local wave = def.shockwave
	if def.defense then
		ctx:telegraph(ctx:inSphere(center(), (if wave then wave.radius else def.radius) + 2, def.jumpClearance), ctx:activeAt())
	end
	ctx:fx("SlamRear", { duration = def.startup, runes = wave ~= nil })
	if not ctx:waitActive() then
		return
	end
	local point = center()
	ctx:fx("Slam", { position = point, radius = def.radius, shockwave = if wave then wave.radius else nil })
	local struck = {}
	for _, target in ctx:inSphere(point, def.radius, def.jumpClearance) do
		struck[target.id] = true
		ctx:hit(target, nil, { direction = Hitbox.flatDirection(target.root.Position - point) or ctx.direction, origin = point })
	end
	if not wave then
		return
	end
	-- The shockwave rolls outward a moment later; jumping clears it
	task.wait(0.15)
	if not services.CharacterService:isAlive(fighter) then
		return
	end
	for _, target in ctx:inSphere(point, wave.radius, def.jumpClearance) do
		if not struck[target.id] then
			ctx:hit(target, wave, { direction = Hitbox.flatDirection(target.root.Position - point) or ctx.direction, origin = point })
		end
	end
end

-- Cheetah / Panther -----------------------------------------------------------------------------

function abilities.CheetahSwipe(ctx)
	strike(ctx, "Swipe", {})
end

function abilities.CheetahBurst(ctx)
	local def = ctx.def
	local target = if def.pounce then ctx:nearestEnemy(def.range, def.arc) else nil
	ctx:fx("BurstCrouch", { duration = def.startup, pounce = def.pounce == true })
	if not ctx:waitActive() then
		return
	end
	local direction = ctx.direction
	local toward = target and services.CharacterService:isAlive(target) and Hitbox.flatDirection(target.root.Position - ctx:origin())
	if toward then
		direction = toward
	end
	ctx:fx("Burst", { duration = def.active, direction = direction, pounce = def.pounce == true })
	local victim = rush(ctx, direction * def.speed, def.active, def.width)
	if not ctx:alive() then
		return
	end
	if not victim then
		ctx:extendRecovery(def.whiffRecovery)
		return
	end
	ctx:fx("BurstHit", { target = victim.model, pounce = def.pounce == true })
	local outcome = ctx:hit(victim, nil, { direction = direction })
	if outcome and outcome.result == "Hit" and def.slow then
		ctx:status(victim, "Slow", def.slowDuration, { magnitude = def.slow })
	end
	ctx:status(ctx.fighter, "Haste", def.hasteDuration, { magnitude = def.haste })
	ctx:finish()
end

-- Crocodile ----------------------------------------------------------------------------------------

function abilities.CrocSnap(ctx)
	strike(ctx, "Snap", {})
end

function abilities.DeathRoll(ctx)
	local def = ctx.def
	ctx:fx("JawsOpen", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local target, best = nil, math.huge
	for _, candidate in ctx:inArc(def.range, def.arc) do
		local distance = (candidate.root.Position - ctx:origin()).Magnitude
		if distance < best then
			target, best = candidate, distance
		end
	end
	-- Dodging (or spawn protection) slips the jaws
	if not target or FighterState.isInvulnerable(target.state, ctx:now()) then
		ctx:fx("JawsWhiff", {})
		return
	end
	ctx:fx("RollCatch", { target = target.model, hold = def.hold })
	local result = ctx:grab(target, { hold = def.hold, presses = def.escapePresses, offset = Vector3.new(0, 0.2, -3.8) })
	if result ~= "Held" or not ctx:alive() then
		if result == "Escaped" then
			ctx:fx("RollBroken", { target = target.model })
		end
		ctx:finish()
		return
	end
	ctx:fx("RollFinish", { target = target.model })
	ctx:hit(target, nil, { direction = ctx.direction, noDefense = true })
	ctx:finish()
end

-- Phoenix ------------------------------------------------------------------------------------------

local function burn(ctx, target, spec)
	if spec and services.CharacterService:isAlive(target) then
		ctx:status(target, "Burn", spec.duration, { magnitude = spec.magnitude })
	end
end

function abilities.CinderRake(ctx)
	for _, target in strike(ctx, "Cinder", {}) do
		burn(ctx, target, ctx.def.burn)
	end
end

function abilities.PhoenixNova(ctx)
	local def = ctx.def
	ctx:telegraph(ctx:inSphere(ctx:origin(), def.radius + 3), ctx:activeAt())
	ctx:fx("NovaRise", { duration = def.startup })
	ctx:dash(Vector3.new(0, def.rise, 0), def.startup * 0.6)
	if not ctx:waitActive() then
		return
	end
	local center = ctx:origin()
	ctx:fx("Nova", { position = center, radius = def.radius })
	for _, target in ctx:inSphere(center, def.radius) do
		local outcome = ctx:hit(target, nil, { direction = Hitbox.flatDirection(target.root.Position - center), origin = center })
		if outcome and outcome.result == "Hit" then
			burn(ctx, target, def.burn)
		end
	end
end

-- Ultimate -------------------------------------------------------------------------------------------

function abilities.PrimalAscendancy(ctx)
	local def = ctx.def
	-- Everyone who could be in front gets the timing bar
	ctx:telegraph(ctx:inArc(def.range + 6, def.arc + 30), ctx:activeAt())
	ctx:fx("AscendWindup", { duration = def.startup, spirits = def.spirits, apex = def.apex, range = def.range })
	if not ctx:waitActive() then
		ctx:fx("AscendFizzle", {})
		return
	end
	local origin = groundBelow(ctx.fighter)
	ctx:fx("AscendStrike", { origin = origin, direction = ctx.direction, range = def.range, arc = def.arc, apex = def.apex, fire = def.burn ~= nil })
	for _, target in ctx:inArc(def.range, def.arc) do
		local outcome = ctx:hit(target, nil, { direction = ctx.direction })
		if outcome and outcome.result == "Hit" then
			burn(ctx, target, def.burn)
		end
	end
end

return Shapeshifter
