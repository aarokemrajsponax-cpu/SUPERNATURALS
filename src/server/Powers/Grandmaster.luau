-- The Grandmaster on the server: the Iron Fist chain's extras (Twin Dragon
-- Fists' second impact, the finisher's hit-stop cue, the dodge-to-counter
-- palm), Dragon's Step, Tiger Claw, Crane's Reversal, Iron Mountain, Sweeping
-- Dragon, Hundred Fists, the Focus State, Dragon's Answer, the Heaven-Splitting
-- Dragon ultimate, and the Focus / Perfect Form meters.
-- Numbers come from Shared/Powers/Grandmaster.luau (scaled by degree). Every
-- strike goes through ctx:hit (CombatService.applyHit), so blocks, parries,
-- dodges, armor and the combo limit all apply.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FighterState = require(ReplicatedStorage.Shared.Combat.FighterState)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local AbilityKit = require(script.Parent.Parent.Combat.AbilityKit)

local Attribute = Protocol.Attribute

local Grandmaster = {}
local abilities = {}
Grandmaster.abilities = abilities

local POWER_ID = "Grandmaster"
local DEF = Powers.get(POWER_ID)
local METERS = DEF.meters
local IRON_FIST = DEF.ironFist
local RESOURCE = DEF.resource

-- Strikes that belong to the basic chain but are dealt here (they must not
-- trigger the chain's own extras again)
local CHAIN_EXTRAS = { TwinDragonFists = true, CounterPalm = true }

local services: any = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

local function groundBelow(fighter): Vector3
	local root = fighter.root
	groundParams.FilterDescendantsInstances = { fighter.model }
	local result = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), groundParams)
	return if result then result.Position else root.Position - Vector3.new(0, 3, 0)
end

local function isAlive(fighter): boolean
	return services ~= nil and services.CharacterService:isAlive(fighter)
end

local function mine(runtime): boolean
	return runtime ~= nil and runtime.id == POWER_ID
end

-- Meters -------------------------------------------------------------------------------

local function publishMeters(fighter, runtime)
	local data = runtime.data
	local model = fighter.model
	local focus = if runtime.degree >= METERS.Focus.minDegree then math.floor((data.focus or 0) + 0.5) else nil
	local form = if runtime.degree >= METERS.PerfectForm.minDegree then math.floor((data.form or 0) + 0.5) else nil
	if data.shownFocus ~= focus then
		data.shownFocus = focus
		model:SetAttribute(Attribute.Focus, focus)
	end
	if data.shownForm ~= form then
		data.shownForm = form
		model:SetAttribute(Attribute.PerfectForm, form)
	end
end

-- Adds to (or takes from) one meter, only at the degrees that have it
local function addMeter(fighter, runtime, meter: string, amount: number)
	local spec = METERS[meter]
	if runtime.degree < spec.minDegree or amount == 0 then
		return
	end
	local data = runtime.data
	local key = if meter == "Focus" then "focus" else "form"
	data[key] = math.clamp((data[key] or 0) + amount, 0, spec.max)
	publishMeters(fighter, runtime)
end

-- Something precise happened (a landed hit or a good defense): momentum holds
local function momentum(runtime)
	runtime.data.lastActionAt = now()
end

-- Damage multiplier from Perfect Form (Degree IV): up to +12% at a full meter
local function formScale(runtime): number
	if runtime.degree < METERS.PerfectForm.minDegree then
		return 1
	end
	return 1 + (runtime.data.form or 0) / METERS.PerfectForm.max * METERS.PerfectForm.damageBonus
end

-- A copy of a strike's numbers with Perfect Form applied
local function scaled(ctx, spec: { [string]: any }): { [string]: any }
	local copy = table.clone(spec)
	copy.damage = (spec.damage or 0) * formScale(ctx.runtime)
	return copy
end

-- A successful defense: Chi, Focus and Form all reward it
local function defended(fighter, runtime)
	if not mine(runtime) then
		return
	end
	services.PowerService:gain(fighter, RESOURCE.gainOnDefense)
	addMeter(fighter, runtime, "Focus", METERS.Focus.onDefense)
	addMeter(fighter, runtime, "PerfectForm", METERS.PerfectForm.onDefense)
	momentum(runtime)
end

-- A committed technique hit nothing: more recovery, and Perfect Form drops
local function whiff(ctx)
	local def = ctx.def
	if def.whiffRecovery then
		ctx:extendRecovery(def.whiffRecovery)
	end
	addMeter(ctx.fighter, ctx.runtime, "PerfectForm", METERS.PerfectForm.onWhiff)
end

-- Dragon's Answer can follow a successful Crane's Reversal or a perfect step (Degree IV)
local function openAnswer(fighter, runtime, attacker)
	local answer = Powers.abilityFor(POWER_ID, "DragonsAnswer", runtime.degree)
	if answer and runtime.degree >= answer.minDegree then
		runtime.data.answerUntil = now() + answer.window
		runtime.data.answerTarget = attacker
	end
end

-- A perfect Dragon's Step: slipped an incoming attack at the right moment
local function perfectStep(fighter, runtime, attacker)
	local data = runtime.data
	if data.stepRead then
		return
	end
	data.stepRead = true
	local step = Powers.abilityFor(POWER_ID, "DragonsStep", runtime.degree)
	data.openingUntil = now() + (if step then step.opening else 1.2)
	defended(fighter, runtime)
	openAnswer(fighter, runtime, attacker)
	AbilityKit.forFighter(fighter):fx("StepRead", { target = if attacker then attacker.model else nil })
end

-- Focus State combat profile (quicker string recovery), cached per degree
local focusedProfiles: { [number]: any } = {}

local function focusedProfile(runtime): any
	local cached = focusedProfiles[runtime.degree]
	if cached then
		return cached
	end
	local focus = Powers.abilityFor(POWER_ID, "FocusState", runtime.degree)
	local profile = Powers.deepCopy(Powers.combatProfile(POWER_ID, runtime.degree))
	for _, step in profile.Light.Steps do
		step.Recovery *= focus.lightRecovery
	end
	profile.Light.ChainWindow += focus.chainWindowBonus
	profile.Light.ChainCooldown *= focus.lightRecovery
	focusedProfiles[runtime.degree] = profile
	return profile
end

local function restoreProfile(fighter, runtime)
	if fighter.power == runtime then
		services.CharacterService:setCombatProfile(fighter, Powers.combatProfile(runtime.id, runtime.degree, if runtime.form ~= "" then runtime.form else nil))
	end
end

-- Targets ------------------------------------------------------------------------------

-- The closest opponent in front that a sequence may start on (not already in
-- another Grandmaster's sequence; for the ultimate, not ultimated recently)
local function sequenceTarget(ctx, range: number, arc: number, forUltimate: boolean)
	local best, bestDistance = nil, math.huge
	for _, target in ctx:inArc(range, arc) do
		local blocked = ctx:hasStatus(target, "Sequenced") or (forUltimate and ctx:hasStatus(target, "UltimateGuard"))
		local distance = (target.root.Position - ctx:origin()).Magnitude
		if not blocked and distance < bestDistance then
			best, bestDistance = target, distance
		end
	end
	return best
end

local function closeEnough(ctx, target, range: number): boolean
	return isAlive(target) and (target.root.Position - ctx:origin()).Magnitude <= range + 2.5
end

local function towards(ctx, target): Vector3
	return Hitbox.flatDirection(target.root.Position - ctx:origin()) or ctx.direction
end

-- Hooks --------------------------------------------------------------------------------

function Grandmaster.init(allServices)
	services = allServices
	local defense = services.DefenseService
	if defense and defense.onResult then
		-- Perfect blocks, perfect dodges and perfect timing count as well-timed defense
		defense:onResult(function(fighter, _, result)
			if (result == "Perfect" or result == "PerfectBlock") and mine(fighter.power) then
				defended(fighter, fighter.power)
			end
		end)
	end
end

local function freshData(fighter, runtime)
	runtime.data.focus = 0
	runtime.data.form = 0
	runtime.data.lastActionAt = now()
	runtime.data.openingUntil = 0
	runtime.data.answerUntil = 0
	runtime.data.focusedUntil = 0
	publishMeters(fighter, runtime)
end

function Grandmaster.onEquip(fighter, runtime)
	freshData(fighter, runtime)
end

function Grandmaster.onReset(fighter, runtime)
	freshData(fighter, runtime)
	restoreProfile(fighter, runtime)
end

function Grandmaster.tick(fighter, runtime, dt: number)
	local data = runtime.data
	local time = now()
	local idle = time - (data.lastActionAt or time)
	if idle > METERS.Focus.idleAfter then
		addMeter(fighter, runtime, "Focus", -METERS.Focus.decay * dt)
	end
	-- Losing momentum drains Perfect Form
	if idle > METERS.PerfectForm.idleAfter then
		addMeter(fighter, runtime, "PerfectForm", -METERS.PerfectForm.decay * dt)
	end
	-- Focus State: Chi flows faster
	if (data.focusedUntil or 0) > time then
		local focus = Powers.abilityFor(POWER_ID, "FocusState", runtime.degree)
		services.PowerService:gain(fighter, RESOURCE.regen * (focus.regenBoost - 1) * dt)
	end
end

-- One of the chain's extra strikes, dealt shortly after the hit that earned it
local function chainExtra(attacker, target, token, delay: number, spec, ability: string, fxName: string)
	task.delay(delay, function()
		if not isAlive(attacker) or not isAlive(target) then
			return
		end
		-- Only while the swing that earned it is still going (a parry or stun cancels it)
		if token and not FighterState.isCurrent(attacker.state, token) then
			return
		end
		if (target.root.Position - attacker.root.Position).Magnitude > 9 then
			return
		end
		local kit = AbilityKit.forFighter(attacker)
		kit:fx(fxName, { target = target.model })
		kit:hit(target, spec, {
			kind = "Ability",
			ability = ability,
			tags = { "Melee", "Small" },
			direction = Hitbox.flatDirection(target.root.Position - attacker.root.Position),
		})
	end)
end

function Grandmaster.onHit(attacker, target, outcome, opts, runtime, ctx)
	local data = runtime.data
	local isChain = opts.kind == "Light" or (opts.kind == "Ability" and CHAIN_EXTRAS[opts.ability or ""] == true)
	momentum(runtime)
	addMeter(attacker, runtime, "Focus", if isChain then METERS.Focus.onLight else METERS.Focus.onAbility)
	addMeter(attacker, runtime, "PerfectForm", METERS.PerfectForm.onHit)
	if runtime.degree >= METERS.PerfectForm.minDegree then
		services.PowerService:addUltimate(attacker, METERS.PerfectForm.ultimateBonus * (data.form or 0) / METERS.PerfectForm.max)
	end

	if opts.kind == "Light" and outcome.result == "Hit" then
		local attack = attacker.state.attack
		local step = if attack then attack.step else 1
		local token = if attack then attack.token else nil
		if step == 2 then
			-- Twin Dragon Fists: the other fist follows
			chainExtra(attacker, target, token, IRON_FIST.twinDelay, scaled(ctx, IRON_FIST.twin), "TwinDragonFists", "TwinFist")
		end
		ctx:fx("IronFistImpact", {
			target = target.model,
			step = step,
			finisher = attack ~= nil and attack.def.Finisher == true,
			hitStop = IRON_FIST.hitStop,
		})
	end

	-- The opening a perfect Dragon's Step earned: the next landed strike adds a counter palm
	if (data.openingUntil or 0) > now() and outcome.result == "Hit" and opts.ability ~= "CounterPalm" then
		data.openingUntil = 0
		chainExtra(attacker, target, nil, 0.12, scaled(ctx, IRON_FIST.counterPalm), "CounterPalm", "CounterPalm")
	end
end

function Grandmaster.onHurt(target, _, outcome, _, runtime)
	if (outcome.dealt or 0) > 0 then
		addMeter(target, runtime, "PerfectForm", METERS.PerfectForm.onDamaged)
	end
end

function Grandmaster.modifyIncoming(target, attacker, outcome, _, runtime)
	if outcome.result == "Parried" then
		defended(target, runtime)
	elseif outcome.result == "Invulnerable" and (runtime.data.stepUntil or 0) >= now() then
		-- A strike passed through Dragon's Step
		perfectStep(target, runtime, attacker)
	end
end

function Grandmaster.canUse(fighter, runtime, def)
	local data = runtime.data
	local kit = AbilityKit.forFighter(fighter)
	if def.id == "FocusState" then
		if (data.focus or 0) + 1e-6 < def.focusCost then
			return false, "Build more Focus first."
		end
	elseif def.id == "DragonsAnswer" then
		if (data.answerUntil or 0) < now() then
			return false, "Counter or perfectly step an attack first."
		end
	elseif def.id == "HeavenSplittingDragon" then
		-- A valid target within range (or the charge isn't spent)
		if not sequenceTarget(kit, def.range + 1.5, def.arc + 30, true) then
			return false, "Nobody in reach to strike."
		end
	elseif def.id == "HundredFists" then
		if not sequenceTarget(kit, def.range + 1.5, def.arc + 30, false) then
			return false, "Get closer first."
		end
	end
	return true
end

-- Abilities ----------------------------------------------------------------------------

function abilities.DragonsStep(ctx)
	local def = ctx.def
	local me = ctx.fighter
	local data = ctx.data
	-- Directional: the way they're moving, or straight ahead
	local ok, moving = pcall(function()
		return me.humanoid.MoveDirection
	end)
	local direction = if ok and typeof(moving) == "Vector3" and moving.Magnitude > 0.2 then (Hitbox.flatDirection(moving) or ctx.direction) else ctx.direction
	local time = ctx:now()
	data.stepRead = false
	data.stepUntil = time + def.startup + def.evade
	me.state.invulnerableUntil = math.max(me.state.invulnerableUntil, data.stepUntil)
	services.CharacterService:refresh(me)
	-- Someone close already swinging at him: stepping now is a perfect read
	local reader = nil
	for _, enemy in ctx:enemies() do
		local attack = enemy.state.attack
		local offset = me.root.Position - enemy.root.Position
		if attack and time < attack.activeEnd and offset.Magnitude <= def.readRange then
			local facing = Hitbox.flatDirection(enemy.root.CFrame.LookVector)
			local toMe = Hitbox.flatDirection(offset)
			if facing and toMe and facing:Dot(toMe) > 0.4 then
				reader = enemy
				break
			end
		end
	end
	ctx:fx("Step", { direction = direction, duration = def.active })
	if not ctx:waitActive() then
		return
	end
	ctx:dash(direction * def.speed, def.active)
	if reader then
		perfectStep(me, ctx.runtime, reader)
	end
	ctx:wait(def.active)
	ctx:stopDash()
end

function abilities.TigerClaw(ctx)
	local def = ctx.def
	ctx:fx("TigerWindup", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local landed = 0
	for index = 1, 2 do
		local targets = ctx:inArc(def.range, def.arc)
		ctx:fx("TigerStrike", { index = index, landed = #targets > 0 })
		landed += ctx:hitAll(targets, scaled(ctx, def.strike), { direction = ctx.direction, tags = { "Melee", "Small" } })
		if not ctx:wait(def.strikeGap) then
			return
		end
	end
	-- The palm thrust is clearly telegraphed: a prompt to block or dodge it
	ctx:telegraph(ctx:inArc(def.range + 2, def.arc + 20), ctx:now() + def.thrustTell)
	ctx:fx("TigerTell", { duration = def.thrustTell })
	if not ctx:wait(def.thrustTell) then
		return
	end
	local targets = ctx:inArc(def.range, def.arc)
	ctx:fx("TigerThrust", { landed = #targets > 0 })
	landed += ctx:hitAll(targets, scaled(ctx, def), { direction = ctx.direction })
	if landed == 0 then
		whiff(ctx)
	end
	ctx:finish()
end

function abilities.CranesReversal(ctx)
	local def = ctx.def
	local me = ctx.fighter
	local runtime = ctx.runtime
	local countered = false
	ctx:fx("CraneStance", { duration = def.startup + def.active })
	ctx:openCounter(def.startup + def.active, function(_, hit, opts)
		-- Grabs and explicitly unblockable attacks go straight through
		if hit.Blockable == false then
			return false
		end
		local tags = opts.tags or {}
		if table.find(tags, "Grab") then
			return false
		end
		return opts.kind == "Light" or opts.kind == "Heavy" or (opts.kind == "Ability" and table.find(tags, "Melee") ~= nil)
	end, function(attacker)
		countered = true
		-- Redirected: the attacker is thrown off balance
		FighterState.applyStun(attacker.state, def.stagger, ctx:now())
		services.CharacterService:refresh(attacker)
		defended(me, runtime)
		openAnswer(me, runtime, attacker)
		task.spawn(function()
			if (attacker.root.Position - me.root.Position).Magnitude <= def.counterRange and ctx:alive() then
				local direction = Hitbox.flatDirection(attacker.root.Position - me.root.Position)
				ctx:fx("CraneCounter", { target = attacker.model })
				ctx:hit(attacker, scaled(ctx, def.first), { direction = direction, noDefense = true })
				if ctx:wait(0.16) and isAlive(attacker) then
					ctx:fx("CraneFinish", { target = attacker.model })
					ctx:hit(attacker, scaled(ctx, def), { direction = direction, noDefense = true })
				end
			end
			ctx:finish()
		end)
		return { negate = true, result = "Countered" }
	end)
	ctx:waitUntil(ctx.startedAt + def.startup + def.active)
	if not countered and ctx:alive() then
		-- A read that didn't come: open for a moment
		ctx:fx("CraneMiss", {})
		whiff(ctx)
	end
end

function abilities.IronMountain(ctx)
	local def = ctx.def
	local direction = ctx.direction
	local reach = def.lunge * 0.15 + def.range
	ctx:telegraph(ctx:alongLine(ctx:origin(), direction, reach, 5), ctx:activeAt() + 0.08)
	ctx:fx("MountainWindup", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	ctx:dash(direction * def.lunge, 0.15)
	ctx:fx("MountainCheck", { direction = direction })
	local victim = nil
	local endsAt = ctx:now() + 0.15
	while ctx:now() < endsAt and ctx:alive() do
		local found = ctx:inArc(4.5, def.arc, nil, direction)
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
	if not victim then
		ctx:fx("MountainPalm", { landed = false })
		whiff(ctx)
		return
	end
	local shoulder = ctx:hit(victim, scaled(ctx, def.shoulder), { direction = direction })
	if not ctx:wait(def.palmDelay) then
		return
	end
	local targets = ctx:inArc(def.range, def.arc, nil, direction)
	ctx:fx("MountainPalm", { landed = #targets > 0 })
	local landed = ctx:hitAll(targets, scaled(ctx, def), { direction = direction })
	if landed == 0 and not (shoulder and shoulder.result == "Hit") then
		whiff(ctx)
	end
	ctx:finish()
end

function abilities.SweepingDragon(ctx)
	local def = ctx.def
	ctx:telegraph(ctx:inSphere(ctx:origin(), def.radius + 3, def.jumpClearance), ctx:activeAt())
	ctx:fx("SweepWindup", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local center = groundBelow(ctx.fighter)
	ctx:fx("Sweep", { position = center, radius = def.radius })
	local landed = 0
	for _, target in ctx:inSphere(center, def.radius, def.jumpClearance) do
		-- Diminishing returns: someone it floored recently only staggers
		local immune = ctx:hasStatus(target, "SureFooted")
		local spec = scaled(ctx, def)
		if immune then
			spec.hitstun = def.immuneHitstun
			spec.launch = 0
		end
		local outcome = ctx:hit(target, spec, { direction = Hitbox.flatDirection(target.root.Position - center) })
		if outcome and outcome.result == "Hit" then
			landed += 1
			if not immune then
				ctx:status(target, "SureFooted", def.knockdownImmunity)
				ctx:fx("Knockdown", { target = target.model, duration = def.hitstun })
			end
		elseif outcome and (outcome.result == "Blocked" or outcome.result == "GuardBreak") then
			landed += 1
		end
	end
	if landed == 0 then
		addMeter(ctx.fighter, ctx.runtime, "PerfectForm", METERS.PerfectForm.onWhiff)
	end
end

-- Hundred Fists and the ultimate: an opener, timed beats, a launching finisher.
-- Returns whether the sequence ran to the end.
local function sequence(ctx, target, fxPrefix: string, extraFx: { [string]: any }?): boolean
	local def = ctx.def
	local extras: { [string]: any } = extraFx or {}
	local direction = towards(ctx, target)
	ctx:status(target, "Sequenced", def.finishAt + 0.4)
	ctx:onCleanup(function()
		if isAlive(target) then
			ctx:clearStatus(target, "Sequenced")
		end
	end)
	local start = ctx:now()
	local info = { target = target.model, finishAt = def.finishAt, beats = #def.beats, direction = direction }
	for key, value in extras do
		info[key] = value
	end
	ctx:fx(fxPrefix .. "Flurry", info)
	for index, beat in def.beats do
		if not ctx:waitUntil(start + beat.at) then
			return false
		end
		if not closeEnough(ctx, target, def.range) then
			return false
		end
		ctx:fx(fxPrefix .. "Beat", { target = target.model, index = index, strike = beat.strike, direction = direction })
		ctx:hit(target, scaled(ctx, { damage = beat.damage, hitstun = beat.hitstun, knockback = 0, guardDamage = 6 }), {
			direction = direction,
			tags = { "Melee", "Small" },
		})
	end
	if not ctx:waitUntil(start + def.finishAt) or not closeEnough(ctx, target, def.range) then
		return false
	end
	local finish = { target = target.model, direction = direction }
	for key, value in extras do
		finish[key] = value
	end
	ctx:fx(fxPrefix .. "Finish", finish)
	ctx:hit(target, scaled(ctx, def), { direction = direction })
	return true
end

function abilities.HundredFists(ctx)
	local def = ctx.def
	ctx:fx("HundredWindup", { duration = def.startup })
	-- Hitting him before the jab lands stops the whole technique
	if not ctx:waitActive() then
		return
	end
	local target = sequenceTarget(ctx, def.range, def.arc, false)
	if not target then
		ctx:fx("HundredWhiff", {})
		whiff(ctx)
		return
	end
	ctx:fx("HundredOpener", { target = target.model })
	local outcome = ctx:hit(target, scaled(ctx, def.opener), { direction = towards(ctx, target) })
	if not outcome or outcome.result ~= "Hit" then
		-- Blocked, parried or dodged: no flurry, and he's open
		whiff(ctx)
		ctx:finish()
		return
	end
	sequence(ctx, target, "Hundred", nil)
	ctx:finish()
end

function abilities.FocusState(ctx)
	local def = ctx.def
	local me = ctx.fighter
	local runtime = ctx.runtime
	local data = ctx.data
	-- The calm stance: open to attack until it settles
	ctx:fx("FocusStance", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	if (data.focus or 0) + 1e-6 < def.focusCost then
		ctx:refund(1)
		return
	end
	addMeter(me, runtime, "Focus", -def.focusCost)
	data.focusedUntil = ctx:now() + def.duration
	services.CharacterService:setCombatProfile(me, focusedProfile(runtime))
	local stopFx = ctx:lastingFx("Focused", def.duration, {})
	local ended = false
	local function endFocus()
		if ended then
			return
		end
		ended = true
		if me.power == runtime then
			data.focusedUntil = 0
			restoreProfile(me, runtime)
		end
		stopFx()
	end
	ctx:own(endFocus)
	task.delay(def.duration, endFocus)
end

function abilities.DragonsAnswer(ctx)
	local def = ctx.def
	local data = ctx.data
	local remembered = data.answerTarget
	data.answerUntil = 0
	data.answerTarget = nil
	local target = nil
	if remembered and ctx:isEnemy(remembered) and (remembered.root.Position - ctx:origin()).Magnitude <= def.reach then
		target = remembered
	else
		target = ctx:nearestEnemy(def.reach)
	end
	local direction = if target then towards(ctx, target) else ctx.direction
	ctx:fx("AnswerWindup", { duration = def.startup, direction = direction })
	if not ctx:waitActive() then
		return
	end
	if target and isAlive(target) then
		direction = towards(ctx, target)
		local distance = (target.root.Position - ctx:origin()).Magnitude
		local travel = math.clamp((distance - 3.5) / def.lunge, 0, def.active)
		if travel > 0.02 then
			ctx:dash(direction * def.lunge, travel)
			ctx:wait(travel)
			ctx:stopDash()
			if not ctx:alive() then
				return
			end
		end
	end
	local targets = ctx:inArc(def.range, def.arc, nil, direction)
	ctx:fx("AnswerPalm", { landed = #targets > 0, direction = direction })
	if ctx:hitAll(targets, scaled(ctx, def), { direction = direction }) == 0 then
		whiff(ctx)
	end
end

function abilities.HeavenSplittingDragon(ctx)
	local def = ctx.def
	local intended = sequenceTarget(ctx, def.range + 1.5, def.arc + 30, true)
	-- The opener is telegraphed: dodge or block it and the whole sequence is gone
	ctx:telegraph(if intended then { intended } else {}, ctx:activeAt())
	ctx:fx("UltStance", { duration = def.startup, cinematic = def.cinematic })
	if not ctx:waitActive() then
		ctx:fx("UltFizzle", {})
		return
	end
	local target = sequenceTarget(ctx, def.range, def.arc, true)
	if intended and target ~= intended and table.find(ctx:inArc(def.range, def.arc), intended) and not ctx:hasStatus(intended, "UltimateGuard") then
		target = intended
	end
	if not target then
		ctx:fx("UltFizzle", {})
		ctx:refund(def.whiffRefund)
		whiff(ctx)
		ctx:finish()
		return
	end
	ctx:fx("UltOpener", { target = target.model, cinematic = def.cinematic })
	local outcome = ctx:hit(target, scaled(ctx, def.opener), { direction = towards(ctx, target) })
	if not outcome or outcome.result ~= "Hit" then
		ctx:fx("UltFizzle", {})
		ctx:refund(def.whiffRefund)
		whiff(ctx)
		ctx:finish()
		return
	end
	-- Nobody can start this ultimate on them again for a while
	ctx:status(target, "UltimateGuard", def.repeatImmunity)
	local finished = sequence(ctx, target, "Ult", { cinematic = def.cinematic })
	if finished and def.cinematic then
		-- The arena reacts (presentation only: no damage to anyone else)
		ctx:fx("UltShockwave", { position = groundBelow(ctx.fighter), direction = towards(ctx, target) })
	end
	ctx:finish()
end

return Grandmaster
