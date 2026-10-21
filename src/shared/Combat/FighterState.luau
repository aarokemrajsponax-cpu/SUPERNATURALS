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
}

local NEVER = -math.huge

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
	return state.knockedOut or now < state.invulnerableUntil or now < state.protectedUntil
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
	if state.knockedOut or FighterState.isStunned(state, now) then
		return 0, 0, false
	elseif state.frozen then
		return 0, 0, true
	elseif FighterState.isAttacking(state, now) then
		-- Attacks keep the facing they started with, so a strafing player still
		-- hits where they aimed
		return move.AttackingSpeed, 0, false
	elseif FighterState.isBlocking(state) then
		return move.BlockingSpeed, 0, true
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
	return math.max(attackEnd, state.dodgeUntil)
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
	elseif FighterState.isDodging(state, now) then
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
	}
	state.attack = attack
	state.bufferedLight = false
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

-- Called when the attack's active window closes. A heavy that hit nothing
-- leaves the attacker open for longer.
function FighterState.endActive(state: State, config, token: number, landed: boolean)
	local attack = state.attack
	if not attack or attack.token ~= token then
		return
	end
	attack.landed = landed
	if attack.kind == "Heavy" and not landed then
		attack.recoveryEnd = attack.activeEnd + config.Heavy.WhiffRecovery
		state.heavyReadyAt = math.max(state.heavyReadyAt, attack.recoveryEnd)
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
	state.bufferedLight = false
	state.lightStep = 0
	state.lightChainUntil = NEVER
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

function FighterState.startDodge(state: State, config, now: number): (boolean, string?)
	local blocked = unavailable(state, now)
	if blocked then
		return false, blocked
	end
	if FighterState.isAttacking(state, now) then
		return false, "busy"
	end
	if now < state.dodgeReadyAt then
		return false, "cooldown"
	end
	FighterState.endBlock(state, config, now)
	local dodge = config.Dodge
	state.dodgeUntil = now + dodge.Duration + dodge.Recovery
	state.invulnerableUntil = now + dodge.Invulnerable
	state.dodgeReadyAt = now + dodge.Cooldown
	return true, nil
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
	return credited
end

function FighterState.setFrozen(state: State, frozen: boolean, config, now: number)
	state.frozen = frozen
	if frozen then
		FighterState.cancelAttack(state)
		FighterState.endBlock(state, config, now)
	end
end

return FighterState
