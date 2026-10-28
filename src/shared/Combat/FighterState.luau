-- One fighter's combat state: attacking, blocking, dodging, stunned, knocked out.
-- Pure logic with explicit timestamps, so the server can run it and tests can
-- replay any situation exactly. Every timed state ends on its own: nothing here
-- can leave a fighter stuck.

local FighterState = {}

export type Attack = {
	kind: string,
	step: number,
	def: any,
	token: number,
	startedAt: number,
	activeAt: number,
	activeEnd: number,
	recoveryEnd: number,
	landed: boolean,
	-- The move's name (Jab, Cross, Hook, FinisherKick, Heavy, ChargedHeavy, ...)
	move: string,
	-- How full a charged heavy was (0..1)
	charge: number?,
	-- A light attack made inside the riposte window after a parry
	riposte: boolean,
	-- The active window has closed (so a miss can be punished)
	ended: boolean,
}

export type State = {
	id: string,
	attack: Attack?,
	nextToken: number,
	lightStep: number,
	lightChainUntil: number,
	lightReadyAt: number,
	heavyReadyAt: number,
	bufferedLight: boolean,
	stunUntil: number,
	blockingSince: number?,
	-- False when the block was re-raised automatically (held through a stun): no parry
	blockCanParry: boolean,
	blockReadyAt: number,
	guard: number,
	guardChangedAt: number,
	dodgeUntil: number,
	invulnerableUntil: number,
	dodgeReadyAt: number,
	protectedUntil: number,
	comboCount: number,
	lastHitAt: number,
	lastAttackerId: string?,
	lastAttackerAt: number,
	knockedOut: boolean,
	frozen: boolean,
	-- Super armor: hits absorbed without flinching until armorUntil
	armorHits: number,
	armorUntil: number,
	-- Fighting System v2 ------------------------------------------------------
	-- Stamina is settled lazily: `stamina` was the value at `staminaSettledAt`
	stamina: number,
	staminaSettledAt: number,
	staminaSpentAt: number,
	winded: boolean,
	-- The sprint button is held (sprinting only while free to move)
	sprintHeld: boolean,
	-- When the current heavy charge began
	chargeStart: number?,
	feintReadyAt: number,
	sweepReadyAt: number,
	grabReadyAt: number,
	tauntReadyAt: number,
	-- Busy after a feint (can walk, can't act)
	recoverUntil: number,
	-- After a parry: the next light attack before this is a riposte
	riposteUntil: number,
	dodgeStartedAt: number,
	-- A dodge can earn one perfect dodge at most
	perfectUsed: boolean,
	downedAt: number,
	downedUntil: number,
	-- Invulnerable from getting up until this
	getUpUntil: number,
	-- A downed fighter can take one hit at most (no ground loops)
	otgUsed: boolean,
	-- Launched (juggle state)
	airborneSince: number,
	airborneUntil: number,
	juggleCount: number,
	-- Basic grab: who holds this fighter, since when, until when; whom this fighter holds
	grabbedById: string?,
	grabbedAt: number,
	grabUntil: number,
	holdingId: string?,
	-- A hold ends by itself here even if the throw never comes
	holdUntil: number,
	-- Name of the prop being carried
	carrying: string?,
}

local NEVER = -math.huge

-- Names for light steps that don't name themselves (a power's own chain);
-- a chain's finisher is always the kick
local LIGHT_MOVES = { "Jab", "Cross", "Hook", "FinisherKick" }

function FighterState.new(id: string, config, now: number): State
	local state = {} :: State
	state.id = id
	state.nextToken = 0
	FighterState.reset(state, config, now, 0)
	return state
end

-- Back to a clean slate (used on spawn and respawn)
function FighterState.reset(state: State, config, now: number, protection: number?)
	state.attack = nil
	state.lightStep = 0
	state.lightChainUntil = NEVER
	state.lightReadyAt = NEVER
	state.heavyReadyAt = NEVER
	state.bufferedLight = false
	state.stunUntil = NEVER
	state.blockingSince = nil
	state.blockCanParry = true
	state.blockReadyAt = NEVER
	state.guard = config.Block.MaxGuard
	state.guardChangedAt = NEVER
	state.dodgeUntil = NEVER
	state.invulnerableUntil = NEVER
	state.dodgeReadyAt = NEVER
	state.protectedUntil = now + (protection or 0)
	state.comboCount = 0
	state.lastHitAt = NEVER
	state.lastAttackerId = nil
	state.lastAttackerAt = NEVER
	state.knockedOut = false
	state.frozen = false
	state.armorHits = 0
	state.armorUntil = NEVER
	state.stamina = config.Stamina.Max
	state.staminaSettledAt = now
	state.staminaSpentAt = NEVER
	state.winded = false
	state.sprintHeld = false
	state.chargeStart = nil
	state.feintReadyAt = NEVER
	state.sweepReadyAt = NEVER
	state.grabReadyAt = NEVER
	state.tauntReadyAt = NEVER
	state.recoverUntil = NEVER
	state.riposteUntil = NEVER
	state.dodgeStartedAt = NEVER
	state.perfectUsed = false
	state.downedAt = NEVER
	state.downedUntil = NEVER
	state.getUpUntil = NEVER
	state.otgUsed = false
	state.airborneSince = NEVER
	state.airborneUntil = NEVER
	state.juggleCount = 0
	state.grabbedById = nil
	state.grabbedAt = NEVER
	state.grabUntil = NEVER
	state.holdingId = nil
	state.holdUntil = NEVER
	state.carrying = nil
end

-- Queries -------------------------------------------------------------------

function FighterState.isStunned(state: State, now: number): boolean
	return now < state.stunUntil
end

function FighterState.isAttacking(state: State, now: number): boolean
	local attack = state.attack
	return attack ~= nil and now < attack.recoveryEnd
end

function FighterState.isDodging(state: State, now: number): boolean
	return now < state.dodgeUntil
end

function FighterState.isBlocking(state: State): boolean
	return state.blockingSince ~= nil
end

function FighterState.isInvulnerable(state: State, now: number): boolean
	return state.knockedOut
		or now < state.invulnerableUntil
		or now < state.protectedUntil
		-- Getting up, or already hit once on the floor
		or (now >= state.downedUntil and now < state.getUpUntil)
		or (now < state.downedUntil and state.otgUsed)
end

function FighterState.isDowned(state: State, now: number): boolean
	return now < state.downedUntil
end

-- Launched and not landed yet (juggle state)
function FighterState.isAirborne(state: State, now: number): boolean
	return now < state.airborneUntil
end

function FighterState.isGrabbed(state: State, now: number): boolean
	return state.grabbedById ~= nil and now < state.grabUntil
end

-- Holding someone in a basic grab (`now` omitted: whether anyone is held at all)
function FighterState.isHolding(state: State, now: number?): boolean
	return state.holdingId ~= nil and (now == nil or now < state.holdUntil)
end

function FighterState.isCharging(state: State, now: number): boolean
	local attack = state.attack
	return attack ~= nil and attack.kind == "Charge" and now < attack.recoveryEnd
end

function FighterState.isTaunting(state: State, now: number): boolean
	local attack = state.attack
	return attack ~= nil and attack.kind == "Taunt" and now < attack.recoveryEnd
end

-- Winding up a basic move (or charging, or taunting): hits now are counter hits.
-- Abilities have their own rules (armor, counters), so they don't count.
function FighterState.inWindup(state: State, now: number): boolean
	local attack = state.attack
	return attack ~= nil and attack.kind ~= "Ability" and now < attack.activeAt and now < attack.recoveryEnd
end

-- Recovering from a basic move that hit nothing: hits now are punishes
function FighterState.inWhiffRecovery(state: State, now: number): boolean
	local attack = state.attack
	return attack ~= nil
		and attack.kind ~= "Ability"
		and attack.ended
		and not attack.landed
		and now >= attack.activeEnd
		and now < attack.recoveryEnd
end

function FighterState.inParryWindow(state: State, config, now: number): boolean
	local since = state.blockingSince
	if since == nil or not state.blockCanParry then
		return false
	end
	return now - since <= config.Block.ParryWindow + config.Block.LatencyAllowance
end

-- Is this attack still the one in progress? (Scheduled hit checks use this to
-- notice the attack was cancelled by a stun, a knockout or a respawn.)
function FighterState.isCurrent(state: State, token: number): boolean
	local attack = state.attack
	return attack ~= nil and attack.token == token
end

function FighterState.guardAt(state: State, config, now: number): number
	local block = config.Block
	local regenTime = now - state.guardChangedAt - block.GuardRegenDelay
	if regenTime <= 0 then
		return state.guard
	end
	return math.min(block.MaxGuard, state.guard + regenTime * block.GuardRegenRate)
end

-- Walk speed, jump height and whether the character turns to face its movement
function FighterState.movement(state: State, config, now: number): (number, number, boolean)
	local move = config.Movement
	if
		state.knockedOut
		or FighterState.isStunned(state, now)
		or FighterState.isDowned(state, now)
		or FighterState.isGrabbed(state, now)
		or FighterState.isHolding(state, now)
	then
		return 0, 0, false
	elseif state.frozen then
		return 0, 0, true
	elseif FighterState.isAttacking(state, now) then
		-- Attacks keep the facing they started with, so a strafing player still
		-- hits where they aimed. Abilities can set their own speed (0 = rooted).
		local def = (state.attack :: Attack).def
		if def.MoveSpeed ~= nil then
			return def.MoveSpeed, 0, def.AutoRotate == true
		end
		return move.AttackingSpeed, 0, false
	elseif FighterState.isBlocking(state) then
		return move.BlockingSpeed, 0, true
	elseif state.carrying ~= nil then
		return config.Carry.WalkSpeed, move.JumpHeight, true
	elseif FighterState.isSprinting(state, now) then
		return config.Sprint.Speed, move.JumpHeight, true
	end
	return move.WalkSpeed, move.JumpHeight, true
end

-- The next moment movement() could return something different, or nil
function FighterState.nextMovementChange(state: State, now: number): number?
	local soonest: number? = nil
	local function consider(time: number)
		if time > now and (soonest == nil or time < soonest) then
			soonest = time
		end
	end
	consider(state.stunUntil)
	consider(state.dodgeUntil)
	consider(state.downedUntil)
	consider(state.getUpUntil)
	consider(state.grabUntil)
	consider(state.airborneUntil)
	consider(state.recoverUntil)
	consider(state.holdUntil)
	local attack = state.attack
	if attack then
		consider(attack.recoveryEnd)
	end
	return soonest
end

-- When this fighter can next start an attack or dodge (the end of its current
-- swing, including a missed heavy's longer recovery, or of its dodge)
function FighterState.busyUntil(state: State): number
	local attack = state.attack
	local attackEnd = if attack then attack.recoveryEnd else -math.huge
	local grabEnd = if state.grabbedById then state.grabUntil else -math.huge
	local holdEnd = if state.holdingId then state.holdUntil else -math.huge
	return math.max(attackEnd, state.dodgeUntil, state.downedUntil, state.recoverUntil, grabEnd, holdEnd)
end

-- Credit for a knockout goes to whoever touched this fighter last, if recent enough
function FighterState.creditedAttacker(state: State, config, now: number): string?
	if state.lastAttackerId and now - state.lastAttackerAt <= config.KnockoutCreditWindow then
		return state.lastAttackerId
	end
	return nil
end

-- Actions -------------------------------------------------------------------

local function unavailable(state: State, now: number): string?
	if state.knockedOut or state.frozen then
		return "unavailable"
	elseif FighterState.isStunned(state, now) then
		return "stunned"
	elseif FighterState.isDowned(state, now) then
		return "downed"
	elseif FighterState.isGrabbed(state, now) then
		return "grabbed"
	elseif FighterState.isHolding(state, now) or FighterState.isDodging(state, now) or now < state.recoverUntil then
		return "busy"
	end
	return nil
end

local function begin(state: State, kind: string, step: number, def, now: number): Attack
	state.nextToken += 1
	local activeAt = now + def.Startup
	local activeEnd = activeAt + def.Active
	local attack: Attack = {
		kind = kind,
		step = step,
		def = def,
		token = state.nextToken,
		startedAt = now,
		activeAt = activeAt,
		activeEnd = activeEnd,
		recoveryEnd = activeEnd + def.Recovery,
		landed = false,
		move = def.Move or kind,
		charge = nil,
		riposte = false,
		ended = false,
	}
	state.attack = attack
	state.bufferedLight = false
	state.chargeStart = nil
	-- Attacking drops your guard
	state.blockingSince = nil
	return attack
end

function FighterState.startLight(state: State, config, now: number): (Attack?, string?)
	local blocked = unavailable(state, now)
	if blocked then
		return nil, blocked
	end
	local current = state.attack
	if current and now < current.recoveryEnd then
		if current.kind == "Light" and current.recoveryEnd - now <= config.InputBuffer then
			state.bufferedLight = true
			return nil, "buffered"
		end
		return nil, "busy"
	end
	if now < state.lightReadyAt then
		return nil, "cooldown"
	end

	local steps = config.Light.Steps
	local step = 1
	if now <= state.lightChainUntil and state.lightStep < #steps then
		step = state.lightStep + 1
	end
	local attack = begin(state, "Light", step, steps[step], now)
	if steps[step].Move == nil then
		attack.move = if steps[step].Finisher then "FinisherKick" else LIGHT_MOVES[math.min(step, #LIGHT_MOVES - 1)]
	end
	if now <= state.riposteUntil then
		attack.riposte = true
		state.riposteUntil = NEVER
	end
	if step == #steps then
		-- Chain complete: rest before starting a new one
		state.lightStep = 0
		state.lightChainUntil = NEVER
		state.lightReadyAt = attack.recoveryEnd + config.Light.ChainCooldown
	else
		state.lightStep = step
		state.lightChainUntil = attack.recoveryEnd + config.Light.ChainWindow
	end
	return attack, nil
end

function FighterState.startHeavy(state: State, config, now: number): (Attack?, string?)
	local blocked = unavailable(state, now)
	if blocked then
		return nil, blocked
	end
	if FighterState.isAttacking(state, now) then
		return nil, "busy"
	end
	if now < state.heavyReadyAt then
		return nil, "cooldown"
	end
	local attack = begin(state, "Heavy", 1, config.Heavy, now)
	state.lightStep = 0
	state.lightChainUntil = NEVER
	state.heavyReadyAt = math.max(now + config.Heavy.Cooldown, attack.recoveryEnd)
	return attack, nil
end

-- Abilities use the same timing as attacks: startup, active, recovery. `timing`
-- holds Startup, Active, Recovery and optionally MoveSpeed, AutoRotate and Armor
-- (hits shrugged off during startup).
function FighterState.startAbility(state: State, timing, now: number): (Attack?, string?)
	local blocked = unavailable(state, now)
	if blocked then
		return nil, blocked
	end
	if FighterState.isAttacking(state, now) then
		return nil, "busy"
	end
	local attack = begin(state, "Ability", 0, timing, now)
	state.lightStep = 0
	state.lightChainUntil = NEVER
	local armor = timing.Armor or 0
	if armor > 0 then
		state.armorHits = armor
		state.armorUntil = attack.activeEnd
	end
	return attack, nil
end

-- Ends an ability early (or late, for channels that ran their course): recovery
-- starts now. Returns the new end of recovery, or nil if the ability isn't current.
function FighterState.finishAbility(state: State, token: number, now: number): number?
	local attack = state.attack
	if not attack or attack.token ~= token then
		return nil
	end
	attack.activeEnd = math.min(attack.activeEnd, now)
	attack.recoveryEnd = now + attack.def.Recovery
	state.armorUntil = math.min(state.armorUntil, now)
	return attack.recoveryEnd
end

-- Adds extra recovery (a missed charge leaves you open longer)
function FighterState.extendRecovery(state: State, token: number, extra: number)
	local attack = state.attack
	if attack and attack.token == token and extra > 0 then
		attack.recoveryEnd += extra
	end
end

-- Would a hit right now be absorbed by super armor? (doesn't use it up)
function FighterState.hasArmor(state: State, now: number): boolean
	return state.armorHits > 0 and now < state.armorUntil
end

function FighterState.useArmor(state: State)
	state.armorHits = math.max(0, state.armorHits - 1)
end

-- Called when the attack's active window closes. A heavy that hit nothing
-- leaves the attacker open for longer.
function FighterState.endActive(state: State, config, token: number, landed: boolean)
	local attack = state.attack
	if not attack or attack.token ~= token then
		return
	end
	attack.landed = landed
	attack.ended = true
	if not landed then
		local whiff = attack.def.WhiffRecovery
		if whiff == nil and attack.kind == "Heavy" then
			whiff = config.Heavy.WhiffRecovery
		end
		if whiff then
			attack.recoveryEnd = math.max(attack.recoveryEnd, attack.activeEnd + whiff)
			if attack.kind == "Heavy" then
				state.heavyReadyAt = math.max(state.heavyReadyAt, attack.recoveryEnd)
			end
		end
	end
end

-- Clears a finished attack; returns true if a buffered light attack is waiting
function FighterState.finishAttack(state: State, now: number): boolean
	local attack = state.attack
	if attack and now >= attack.recoveryEnd then
		state.attack = nil
	end
	local buffered = state.bufferedLight
	state.bufferedLight = false
	return buffered and state.attack == nil
end

function FighterState.cancelAttack(state: State)
	state.attack = nil
	state.chargeStart = nil
	state.bufferedLight = false
	state.lightStep = 0
	state.lightChainUntil = NEVER
	state.armorHits = 0
	state.armorUntil = NEVER
end

-- `canParry` is false for a block that was held down through a stun and
-- re-raised automatically, so holding block never becomes a free parry
function FighterState.startBlock(state: State, now: number, canParry: boolean?): (boolean, string?)
	local blocked = unavailable(state, now)
	if blocked then
		return false, blocked
	end
	if FighterState.isAttacking(state, now) then
		return false, "busy"
	end
	if state.blockingSince ~= nil then
		return false, "already"
	end
	if state.carrying ~= nil then
		return false, "carrying"
	end
	if now < state.blockReadyAt then
		return false, "cooldown"
	end
	state.blockingSince = now
	state.blockCanParry = canParry ~= false
	return true, nil
end

function FighterState.endBlock(state: State, config, now: number): boolean
	if state.blockingSince == nil then
		return false
	end
	state.blockingSince = nil
	state.blockReadyAt = now + config.Block.Cooldown
	return true
end

-- Which way a dodge goes, from movement intent relative to facing:
-- "Side", "Back" (also no input) or "Forward"
function FighterState.dodgeStyle(look: Vector3, intent: Vector3?): string
	if intent == nil then
		return "Back"
	end
	local flatIntent = Vector3.new(intent.X, 0, intent.Z)
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatIntent.Magnitude < 0.3 or flatLook.Magnitude < 1e-4 then
		return "Back"
	end
	local along = flatIntent.Unit:Dot(flatLook.Unit)
	if along > 0.5 then
		return "Forward"
	elseif along < -0.5 then
		return "Back"
	end
	return "Side"
end

-- Starts a dodge. `style` picks the dodge's numbers from Dodge.Directions
-- (nil = the base numbers). A light attack that landed can be cancelled into a
-- dodge during its recovery. Costs stamina. Returns the dodge's numbers too.
function FighterState.startDodge(state: State, config, now: number, style: string?): (boolean, string?, any)
	local blocked = unavailable(state, now)
	if blocked then
		return false, blocked, nil
	end
	local cancel = false
	local attack = state.attack
	if FighterState.isAttacking(state, now) then
		local attackDef = attack and attack.def
		if attack and attack.kind == "Light" and attack.landed and now >= attack.activeEnd and not (attackDef and attackDef.Lunge) then
			cancel = true
		else
			return false, "busy", nil
		end
	end
	if now < state.dodgeReadyAt then
		return false, "cooldown", nil
	end
	local costs = config.Stamina.Costs
	if not FighterState.spendStamina(state, config, if cancel then costs.DodgeCancel else costs.Dodge, now) then
		return false, "winded", nil
	end
	if cancel then
		FighterState.cancelAttack(state)
	end
	FighterState.endBlock(state, config, now)
	local dodge = config.Dodge
	local numbers = style and dodge.Directions and dodge.Directions[style] or dodge
	local duration = numbers.Duration or dodge.Duration
	local invulnerable = numbers.Invulnerable or dodge.Invulnerable
	state.dodgeUntil = now + duration + dodge.Recovery
	state.invulnerableUntil = math.max(state.invulnerableUntil, now + invulnerable)
	state.dodgeReadyAt = now + dodge.Cooldown
	state.dodgeStartedAt = now
	state.perfectUsed = false
	return true, nil, {
		style = style or "Back",
		speed = numbers.Speed or dodge.Speed,
		duration = duration,
		invulnerable = invulnerable,
		cancel = cancel,
	}
end

-- Did this fighter start its dodge just before `now`? (Once per dodge.)
function FighterState.claimPerfectDodge(state: State, config, now: number): boolean
	if state.perfectUsed or not FighterState.isDodging(state, now) then
		return false
	end
	if now - state.dodgeStartedAt > config.Dodge.PerfectWindow + config.Block.LatencyAllowance then
		return false
	end
	state.perfectUsed = true
	return true
end

-- Spawn protection ends the moment the protected fighter attacks or dodges
function FighterState.dropProtection(state: State, now: number)
	state.protectedUntil = math.min(state.protectedUntil, now)
end

-- Stun interrupts whatever the fighter was doing
function FighterState.applyStun(state: State, duration: number, now: number)
	if duration <= 0 then
		return
	end
	state.stunUntil = math.max(state.stunUntil, now + duration)
	FighterState.cancelAttack(state)
	state.blockingSince = nil
	state.dodgeUntil = math.min(state.dodgeUntil, now)
	state.recoverUntil = math.min(state.recoverUntil, now)
end

-- Returns true if the guard broke
function FighterState.damageGuard(state: State, config, amount: number, now: number): boolean
	local remaining = FighterState.guardAt(state, config, now) - amount
	state.guardChangedAt = now
	if remaining <= 0 then
		state.guard = config.Block.GuardAfterBreak
		return true
	end
	state.guard = remaining
	return false
end

-- Remembers who touched this fighter (for knockout credit)
function FighterState.noteAttacker(state: State, attackerId: string, now: number)
	state.lastAttackerId = attackerId
	state.lastAttackerAt = now
end

-- Hits in quick succession build a combo; returns this hit's position in it
function FighterState.projectedCombo(state: State, config, now: number): number
	if now - state.lastHitAt > config.ComboResetTime then
		return 1
	end
	return state.comboCount + 1
end

function FighterState.registerHit(state: State, config, attackerId: string, now: number): number
	state.comboCount = FighterState.projectedCombo(state, config, now)
	state.lastHitAt = now
	FighterState.noteAttacker(state, attackerId, now)
	return state.comboCount
end

-- Returns who earned the knockout, if anyone
function FighterState.knockOut(state: State, config, now: number): string?
	local credited = FighterState.creditedAttacker(state, config, now)
	state.knockedOut = true
	FighterState.cancelAttack(state)
	state.blockingSince = nil
	state.stunUntil = NEVER
	state.dodgeUntil = NEVER
	FighterState.clearTransient(state)
	return credited
end

function FighterState.setFrozen(state: State, frozen: boolean, config, now: number)
	state.frozen = frozen
	if frozen then
		FighterState.cancelAttack(state)
		FighterState.endBlock(state, config, now)
	end
end

-- Fighting System v2 --------------------------------------------------------------

-- Stamina ------------------------------------------------------------------------

-- Sprinting means the button is held and nothing else is going on
function FighterState.isSprinting(state: State, now: number): boolean
	return state.sprintHeld
		and not state.winded
		and not state.knockedOut
		and not state.frozen
		and state.carrying == nil
		and not FighterState.isHolding(state, now)
		and state.blockingSince == nil
		and not FighterState.isAttacking(state, now)
		and not FighterState.isStunned(state, now)
		and not FighterState.isDodging(state, now)
		and not FighterState.isDowned(state, now)
		and not FighterState.isGrabbed(state, now)
end

-- Stamina at `now` (sprinting drains it, resting refills it after a delay)
local function staminaProjection(state: State, config, now: number): (number, boolean)
	local stamina = config.Stamina
	local value = state.stamina
	local from = state.staminaSettledAt
	if now <= from then
		return value, false
	end
	if FighterState.isSprinting(state, now) then
		value -= (now - from) * stamina.Costs.SprintPerSecond
		if value <= 0 then
			return 0, true
		end
		return value, false
	end
	local regenFrom = math.max(from, state.staminaSpentAt + stamina.RegenDelay)
	if now > regenFrom then
		value = math.min(stamina.Max, value + (now - regenFrom) * stamina.Regen)
	end
	return value, false
end

function FighterState.staminaAt(state: State, config, now: number): number
	local value = staminaProjection(state, config, now)
	return value
end

-- Brings stored stamina up to `now`. Returns "Winded" or "Recovered" when that
-- changed, so the server can tell clients.
function FighterState.settleStamina(state: State, config, now: number): string?
	local sprinting = FighterState.isSprinting(state, now)
	local value, ranDry = staminaProjection(state, config, now)
	state.stamina = value
	state.staminaSettledAt = math.max(state.staminaSettledAt, now)
	if sprinting then
		state.staminaSpentAt = now
	end
	if ranDry or (value <= 0 and not state.winded) then
		state.stamina = 0
		state.winded = true
		state.sprintHeld = false
		return "Winded"
	elseif state.winded and value >= config.Stamina.WindedRecover then
		state.winded = false
		return "Recovered"
	end
	return nil
end

function FighterState.isWinded(state: State, config, now: number): boolean
	if not state.winded then
		return false
	end
	return FighterState.staminaAt(state, config, now) < config.Stamina.WindedRecover
end

-- Spends stamina; anything above 0 is enough (it bottoms out at 0 and the
-- fighter is winded). Returns false when winded or empty.
function FighterState.spendStamina(state: State, config, amount: number, now: number): boolean
	FighterState.settleStamina(state, config, now)
	if state.winded or state.stamina <= 0 then
		return false
	end
	state.stamina = math.max(0, state.stamina - amount)
	state.staminaSpentAt = now
	if state.stamina <= 0 then
		state.winded = true
		state.sprintHeld = false
	end
	return true
end

-- When winded recovery happens (or the sprint runs dry), for scheduling
function FighterState.nextStaminaChange(state: State, config, now: number): number?
	local stamina = config.Stamina
	local value = FighterState.staminaAt(state, config, now)
	if FighterState.isSprinting(state, now) then
		return now + value / stamina.Costs.SprintPerSecond
	elseif state.winded then
		-- From the stored value: it refills from the later of when it was stored
		-- and the end of the regen delay (nothing drains it while winded)
		local regenFrom = math.max(state.staminaSettledAt, state.staminaSpentAt + stamina.RegenDelay)
		return regenFrom + math.max(0, stamina.WindedRecover - state.stamina) / stamina.Regen
	end
	return nil
end

function FighterState.startSprint(state: State, config, now: number): (boolean, string?)
	if state.knockedOut or state.frozen then
		return false, "unavailable"
	end
	FighterState.settleStamina(state, config, now)
	if state.winded then
		return false, "winded"
	elseif state.sprintHeld then
		return false, "already"
	elseif state.stamina < config.Sprint.MinStamina then
		return false, "stamina"
	elseif state.carrying ~= nil then
		return false, "carrying"
	end
	state.sprintHeld = true
	return true, nil
end

function FighterState.endSprint(state: State, config, now: number): boolean
	if not state.sprintHeld then
		return false
	end
	FighterState.settleStamina(state, config, now)
	state.sprintHeld = false
	return true
end

-- Move variants ------------------------------------------------------------------

-- Which basic move an action becomes, from the fighter's situation:
-- in the air -> aerials, sprinting -> sprint strikes, back + Heavy -> Launcher.
-- Returns the move's name and its attack definition.
function FighterState.chooseMove(config, action: string, context: { air: boolean?, sprinting: boolean?, back: boolean? }): (string, any?)
	if action == "Light" then
		if context.air then
			return "AirKick", config.Air.Light
		elseif context.sprinting then
			return "RushStrike", config.Running.Light
		end
		return "Light", nil
	elseif action == "Heavy" then
		if context.air then
			return "Slam", config.Air.Heavy
		elseif context.sprinting then
			return "ShoulderCharge", config.Running.Heavy
		elseif context.back then
			return "Launcher", config.Launcher
		end
		return "Heavy", nil
	end
	return action, nil
end

-- Starts a light or heavy variant (aerials, sprint strikes, Launcher). Lights
-- share the light cooldown; heavies share the heavy cooldown.
function FighterState.startVariant(state: State, config, kind: string, def, now: number): (Attack?, string?)
	local blocked = unavailable(state, now)
	if blocked then
		return nil, blocked
	end
	if FighterState.isAttacking(state, now) then
		return nil, "busy"
	end
	if state.carrying ~= nil then
		return nil, "carrying"
	end
	if kind == "Heavy" and now < state.heavyReadyAt then
		return nil, "cooldown"
	elseif kind == "Light" and now < state.lightReadyAt then
		return nil, "cooldown"
	end
	local attack = begin(state, kind, 1, def, now)
	state.lightStep = 0
	state.lightChainUntil = NEVER
	if kind == "Heavy" then
		state.heavyReadyAt = math.max(now + (def.Cooldown or config.Heavy.Cooldown), attack.recoveryEnd)
	end
	return attack, nil
end

-- Charged heavy ------------------------------------------------------------------

-- Starts charging a heavy (HeavyRelease or reaching Charge.Max swings it)
function FighterState.startCharge(state: State, config, now: number): (Attack?, string?)
	local blocked = unavailable(state, now)
	if blocked then
		return nil, blocked
	end
	if FighterState.isAttacking(state, now) then
		return nil, "busy"
	end
	if state.carrying ~= nil then
		return nil, "carrying"
	end
	if now < state.heavyReadyAt then
		return nil, "cooldown"
	end
	local charge = config.Heavy.Charge
	if not FighterState.spendStamina(state, config, config.Stamina.Costs.Charge, now) then
		return nil, "winded"
	end
	local attack = begin(state, "Charge", 1, {
		Move = "Charge",
		Startup = charge.Max,
		Active = 0,
		Recovery = 0,
		MoveSpeed = charge.MoveSpeed,
		AutoRotate = true,
	}, now)
	state.chargeStart = now
	state.lightStep = 0
	state.lightChainUntil = NEVER
	return attack, nil
end

-- How full the charge is at `now` (0..1)
function FighterState.chargeLevel(state: State, config, now: number): number
	local started = state.chargeStart
	if started == nil then
		return 0
	end
	return math.clamp((now - started) / config.Heavy.Charge.Max, 0, 1)
end

-- Lets go of a charge: a short hold is a normal heavy, a longer one hits harder,
-- a full one breaks guard and knocks down
function FighterState.releaseCharge(state: State, config, now: number): (Attack?, string?)
	-- A release arriving a moment after the charge filled still counts (network delay)
	local current = state.attack
	if current == nil or current.kind ~= "Charge" or state.chargeStart == nil or now > current.recoveryEnd + config.Block.LatencyAllowance then
		return nil, "not charging"
	end
	local charge = config.Heavy.Charge
	local held = now - (state.chargeStart :: number)
	local level = FighterState.chargeLevel(state, config, now)
	local def = table.clone(config.Heavy)
	def.Charge = nil
	local attack
	if held < charge.Min then
		def.Startup = math.max(charge.ReleaseStartup, config.Heavy.Startup - held)
		attack = begin(state, "Heavy", 1, def, now)
		attack.charge = 0
	else
		def.Move = "ChargedHeavy"
		def.Startup = charge.ReleaseStartup
		def.Damage = config.Heavy.Damage * (1 + charge.DamageBonus * level)
		def.GuardDamage = (config.Heavy.GuardDamage or 0) * (1 + charge.GuardDamageBonus * level)
		if level >= 0.999 then
			def.GuardBreak = true
			def.Knockdown = true
		end
		attack = begin(state, "Heavy", 1, def, now)
		attack.charge = level
	end
	state.heavyReadyAt = math.max(now + config.Heavy.Cooldown, attack.recoveryEnd)
	return attack, nil
end

-- Cancels a heavy's wind-up (or a charge). Costs stamina; the heavy comes back quickly.
function FighterState.feint(state: State, config, now: number): (boolean, string?)
	local attack = state.attack
	local winding = attack ~= nil
		and ((attack.kind == "Heavy" and now < attack.activeAt) or FighterState.isCharging(state, now))
	if not winding then
		return false, "nothing to feint"
	end
	if now < state.feintReadyAt then
		return false, "cooldown"
	end
	if not FighterState.spendStamina(state, config, config.Stamina.Costs.Feint, now) then
		return false, "winded"
	end
	FighterState.cancelAttack(state)
	local feint = config.Feint
	state.recoverUntil = now + feint.Recovery
	state.feintReadyAt = now + feint.Cooldown
	state.heavyReadyAt = now + feint.Recovery
	return true, nil
end

-- Sweep, grab, taunt -------------------------------------------------------------

function FighterState.startSweep(state: State, config, now: number): (Attack?, string?)
	local blocked = unavailable(state, now)
	if blocked then
		return nil, blocked
	end
	if FighterState.isAttacking(state, now) then
		return nil, "busy"
	end
	if state.carrying ~= nil then
		return nil, "carrying"
	end
	if now < state.sweepReadyAt then
		return nil, "cooldown"
	end
	local def = config.Sweep
	local attack = begin(state, "Light", 1, def, now)
	state.lightStep = 0
	state.lightChainUntil = NEVER
	state.sweepReadyAt = math.max(now + (def.Cooldown or 0), attack.recoveryEnd)
	return attack, nil
end

-- A grab attempt: startup, a short active window, then whiff recovery unless it connects
function FighterState.startGrab(state: State, config, now: number): (Attack?, string?)
	local blocked = unavailable(state, now)
	if blocked then
		return nil, blocked
	end
	if FighterState.isAttacking(state, now) then
		return nil, "busy"
	end
	if now < state.grabReadyAt then
		return nil, "cooldown"
	end
	if not FighterState.spendStamina(state, config, config.Stamina.Costs.Grab, now) then
		return nil, "winded"
	end
	local grab = config.Grab
	local attack = begin(state, "Grab", 1, {
		Move = "Grab",
		Startup = grab.Startup,
		Active = grab.Active,
		Recovery = grab.WhiffRecovery,
		Range = grab.Range,
		Arc = grab.Arc,
	}, now)
	state.lightStep = 0
	state.lightChainUntil = NEVER
	state.grabReadyAt = now + grab.Cooldown
	return attack, nil
end

-- The grab caught `victim`: both are locked together until the throw
-- (The lock lasts a little past Grab.Hold, so the throw always lands before the
-- victim is free; if the throw never comes, it still ends by itself.)
function FighterState.grabConnect(attacker: State, victim: State, config, now: number)
	local hold = config.Grab.Hold + 0.15
	FighterState.cancelAttack(victim)
	victim.blockingSince = nil
	victim.dodgeUntil = math.min(victim.dodgeUntil, now)
	victim.grabbedById = attacker.id
	victim.grabbedAt = now
	victim.grabUntil = now + hold
	victim.stunUntil = math.max(victim.stunUntil, now + hold)
	attacker.holdingId = victim.id
	attacker.holdUntil = now + hold
	local attack = attacker.attack
	if attack then
		attack.landed = true
		attack.activeEnd = math.min(attack.activeEnd, now)
		attack.recoveryEnd = now + hold
	end
end

-- Can the grabbed fighter still break out? (Network delay allowed for.)
function FighterState.canTech(victim: State, config, now: number): boolean
	return victim.grabbedById ~= nil
		and now < victim.grabUntil
		and now - victim.grabbedAt <= config.Grab.TechWindow + config.Block.LatencyAllowance
end

-- Unlocks a grab (throw, tech, or one side vanished). Either side may be nil.
function FighterState.releaseGrab(attacker: State?, victim: State?, now: number)
	if victim then
		victim.grabbedById = nil
		victim.grabUntil = math.min(victim.grabUntil, now)
		victim.stunUntil = math.min(victim.stunUntil, now)
	end
	if attacker then
		attacker.holdingId = nil
		attacker.holdUntil = math.min(attacker.holdUntil, now)
		local attack = attacker.attack
		if attack and attack.kind == "Grab" then
			attack.recoveryEnd = math.min(attack.recoveryEnd, now)
			attacker.attack = nil
		end
	end
end

function FighterState.startTaunt(state: State, config, now: number): (Attack?, string?)
	local blocked = unavailable(state, now)
	if blocked then
		return nil, blocked
	end
	if FighterState.isAttacking(state, now) or state.blockingSince ~= nil or state.carrying ~= nil then
		return nil, "busy"
	end
	if now < state.tauntReadyAt then
		return nil, "cooldown"
	end
	local taunt = config.Taunt
	local attack = begin(state, "Taunt", 0, {
		Move = "Taunt",
		Startup = taunt.Duration,
		Active = 0,
		Recovery = 0,
		MoveSpeed = 0,
	}, now)
	state.lightStep = 0
	state.lightChainUntil = NEVER
	state.tauntReadyAt = now + taunt.Cooldown
	return attack, nil
end

-- Knockdowns ---------------------------------------------------------------------

function FighterState.knockDown(state: State, config, now: number)
	local knockdown = config.Knockdown
	FighterState.cancelAttack(state)
	state.blockingSince = nil
	state.downedAt = now
	state.downedUntil = now + knockdown.Duration
	state.getUpUntil = state.downedUntil + knockdown.GetUpInvulnerable
	state.otgUsed = false
	-- A knockdown ends any juggle: the fighter is on the floor now
	state.airborneUntil = math.min(state.airborneUntil, now)
	state.juggleCount = 0
end

-- The one hit a downed fighter can take: they get up right after it
function FighterState.hitWhileDowned(state: State, config, now: number)
	state.otgUsed = true
	state.downedUntil = math.min(state.downedUntil, now + 0.3)
	state.getUpUntil = state.downedUntil + config.Knockdown.GetUpInvulnerable
end

-- Dodge right as you hit the floor: roll away instead of lying there
function FighterState.techRoll(state: State, config, now: number): (boolean, string?)
	if not FighterState.isDowned(state, now) or state.knockedOut then
		return false, "not downed"
	end
	local knockdown = config.Knockdown
	if now - state.downedAt > knockdown.TechWindow + config.Block.LatencyAllowance then
		return false, "too late"
	end
	if not FighterState.spendStamina(state, config, config.Stamina.Costs.TechRoll, now) then
		return false, "winded"
	end
	state.downedUntil = now
	state.stunUntil = math.min(state.stunUntil, now)
	state.dodgeUntil = now + knockdown.TechRollDuration
	state.getUpUntil = now + knockdown.TechRollDuration + knockdown.GetUpInvulnerable
	return true, nil
end

-- Air ----------------------------------------------------------------------------

function FighterState.launch(state: State, config, now: number)
	if not FighterState.isAirborne(state, now) then
		state.airborneSince = now
		state.juggleCount = 0
	end
	state.airborneUntil = now + config.Air.MaxAirborne
end

-- Back on the ground: the juggle is over
function FighterState.land(state: State, now: number)
	state.airborneUntil = math.min(state.airborneUntil, now)
	state.juggleCount = 0
end

-- Dodge while launched (after a moment in the air): recover and escape the juggle
function FighterState.breakfall(state: State, config, now: number): (boolean, string?)
	if not FighterState.isAirborne(state, now) or state.knockedOut then
		return false, "not airborne"
	end
	if now - state.airborneSince < config.Air.BreakfallAfter then
		return false, "too early"
	end
	if not FighterState.spendStamina(state, config, config.Stamina.Costs.Breakfall, now) then
		return false, "winded"
	end
	FighterState.land(state, now)
	state.stunUntil = math.min(state.stunUntil, now)
	state.dodgeUntil = now + 0.2
	state.invulnerableUntil = math.max(state.invulnerableUntil, now + config.Knockdown.GetUpInvulnerable)
	return true, nil
end

-- Props --------------------------------------------------------------------------

function FighterState.pickUp(state: State, name: string, now: number): (boolean, string?)
	local blocked = unavailable(state, now)
	if blocked then
		return false, blocked
	end
	if FighterState.isAttacking(state, now) then
		return false, "busy"
	end
	if state.carrying ~= nil then
		return false, "already"
	end
	state.carrying = name
	state.blockingSince = nil
	state.sprintHeld = false
	return true, nil
end

function FighterState.dropCarried(state: State): string?
	local name = state.carrying
	state.carrying = nil
	return name
end

-- Clears every v2 state that involves other fighters or props (grabs, carrying,
-- charges, juggles, knockdowns). Used on knockouts and by the server's cleanup.
function FighterState.clearTransient(state: State)
	state.chargeStart = nil
	state.sprintHeld = false
	state.carrying = nil
	state.grabbedById = nil
	state.grabUntil = NEVER
	state.holdingId = nil
	state.holdUntil = NEVER
	state.downedUntil = NEVER
	state.getUpUntil = NEVER
	state.otgUsed = false
	state.airborneUntil = NEVER
	state.juggleCount = 0
	state.recoverUntil = NEVER
	state.riposteUntil = NEVER
end

return FighterState
