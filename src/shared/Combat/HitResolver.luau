-- Decides what happens when an attack reaches a fighter: a clean hit, a block,
-- a guard break, a parry, or nothing (invulnerable). resolve() only looks;
-- apply() changes the fighters' states. The server does the physical side
-- (health, knockback) using the outcome.

local FighterState = require(script.Parent.FighterState)
local Hitbox = require(script.Parent.Hitbox)

local HitResolver = {}

export type Outcome = {
	result: string, -- "Hit" | "Blocked" | "GuardBreak" | "Parried" | "Invulnerable"
	damage: number,
	hitstun: number,
	knockback: number,
	launch: number,
	guardDamage: number,
	attackerStun: number,
	comboCapped: boolean,
	-- Absorbed by super armor: damage still lands, but no flinch
	armored: boolean,
	-- Fighting System v2: counter, punish, riposte, wallSplat, knockdown, launch,
	-- airborne, otg (true when they apply; absent otherwise)
	tags: { [string]: boolean },
	-- Hit a juggled fighter past the juggle limit: no stun, no launch
	juggleCapped: boolean,
}

-- What the server knows about the hit that the attack fields don't say
export type Context = {
	-- A close-range strike (counter hits and punishes apply)
	melee: boolean?,
	-- A basic attack (combo scaling applies)
	basic: boolean?,
	-- A light attack made inside the riposte window
	riposte: boolean?,
}

export type Side = {
	id: string,
	state: FighterState.State,
	position: Vector3,
	look: Vector3,
}

local function outcome(result: string): Outcome
	return {
		result = result,
		damage = 0,
		hitstun = 0,
		knockback = 0,
		launch = 0,
		guardDamage = 0,
		attackerStun = 0,
		comboCapped = false,
		armored = false,
		tags = {},
		juggleCapped = false,
	}
end

-- Damage multiplier for the `combo`-th hit of a combo
function HitResolver.comboScale(config, combo: number): number
	local scaling = config.ComboScaling
	if not scaling or combo <= scaling.From then
		return 1
	end
	return math.max(scaling.Min, 1 - scaling.PerHit * (combo - scaling.From))
end

-- Do two melee attacks meet? `other` is the defender's own attack: it clashes
-- when it is about to connect or connecting right now (the server checks it
-- is aimed at the attacker).
function HitResolver.clashes(other, config, now: number): boolean
	if other == nil or (other.kind ~= "Light" and other.kind ~= "Heavy") or other.def.Low then
		return false
	end
	return now >= other.activeAt - config.Clash.Window and now <= other.activeEnd
end

function HitResolver.resolve(attack, config, attacker: Side, defender: Side, now: number, context: Context?): Outcome
	local state = defender.state
	if FighterState.isInvulnerable(state, now) then
		return outcome("Invulnerable")
	end
	local info: Context = context or {}

	local block = config.Block
	local guarding = attack.Blockable ~= false
		and FighterState.isBlocking(state)
		and Hitbox.isInFront(defender.position, defender.look, attacker.position, block.FrontArc)

	if guarding then
		if attack.Parryable ~= false and FighterState.inParryWindow(state, config, now) then
			local parried = outcome("Parried")
			parried.attackerStun = block.ParryStun
			return parried
		end
		local guardDamage = attack.GuardDamage or 0
		-- A winded fighter's guard gives way faster
		if config.Stamina and FighterState.isWinded(state, config, now) then
			guardDamage *= config.Stamina.WindedGuardMultiplier
		end
		local broken = attack.GuardBreak == true or FighterState.guardAt(state, config, now) - guardDamage <= 0
		local result = outcome(if broken then "GuardBreak" else "Blocked")
		result.damage = attack.Damage * block.DamageMultiplier
		result.knockback = (attack.Knockback or 0) * block.PushbackMultiplier
		result.guardDamage = guardDamage
		result.hitstun = if broken then block.GuardBreakStun else 0
		return result
	end

	local hit = outcome("Hit")
	local tags = hit.tags
	hit.damage = attack.Damage
	hit.hitstun = attack.Hitstun or 0
	hit.knockback = attack.Knockback or 0
	hit.launch = attack.Launch or 0
	if info.basic then
		hit.damage *= HitResolver.comboScale(config, FighterState.projectedCombo(state, config, now))
	end
	-- Reading the opponent: hitting a wind-up is a counter, hitting a whiff's recovery a punish
	if info.melee and config.Counter then
		if FighterState.inWindup(state, now) then
			tags.counter = true
			hit.damage *= config.Counter.DamageMultiplier
			hit.hitstun += config.Counter.ExtraHitstun
		elseif FighterState.inWhiffRecovery(state, now) then
			tags.punish = true
			hit.damage *= config.Punish.DamageMultiplier
		end
	end
	if info.riposte and config.Riposte then
		tags.riposte = true
		hit.damage *= config.Riposte.DamageMultiplier
	end
	-- On the floor: one weaker hit, no stun or push (no ground loops)
	if config.Knockdown and FighterState.isDowned(state, now) then
		tags.otg = true
		hit.damage *= config.Knockdown.OTGDamageMultiplier
		hit.hitstun = 0
		hit.knockback = 0
		hit.launch = 0
		return hit
	end
	-- Super armor (a committed charge, an ultimate's wind-up) takes the hit without flinching
	if FighterState.hasArmor(state, now) then
		hit.armored = true
		hit.hitstun = 0
		hit.knockback *= 0.15
		hit.launch = 0
		return hit
	end
	-- Past the combo limit, hits still hurt but stop stunning and push the victim clear
	if FighterState.projectedCombo(state, config, now) > config.MaxComboHits then
		hit.comboCapped = true
		hit.hitstun = 0
		hit.knockback = math.max(hit.knockback, 45)
		hit.launch = math.max(hit.launch, 12)
	end
	-- Juggles: a launched fighter can only be kept up so many times
	if config.Air and FighterState.isAirborne(state, now) then
		tags.airborne = true
		if state.juggleCount >= config.Air.JuggleLimit then
			hit.juggleCapped = true
			hit.hitstun = 0
			hit.launch = 0
		end
	end
	if attack.Knockdown and not hit.comboCapped and not hit.juggleCapped then
		tags.knockdown = true
	end
	if hit.launch > 0 then
		tags.launch = true
	end
	return hit
end

function HitResolver.apply(result: Outcome, config, attacker: Side, defender: Side, now: number)
	local kind = result.result
	if kind == "Invulnerable" then
		return
	elseif kind == "Parried" then
		FighterState.applyStun(attacker.state, result.attackerStun, now)
		-- The defender's next light attack is a riposte
		if config.Riposte then
			defender.state.riposteUntil = now + config.Riposte.Window
		end
		return
	end

	if kind == "Blocked" or kind == "GuardBreak" then
		FighterState.damageGuard(defender.state, config, result.guardDamage, now)
		FighterState.noteAttacker(defender.state, attacker.id, now)
		if kind == "GuardBreak" then
			FighterState.applyStun(defender.state, result.hitstun, now)
		end
		return
	end

	local state = defender.state
	local wasAirborne = FighterState.isAirborne(state, now)
	FighterState.registerHit(state, config, attacker.id, now)
	if result.armored then
		FighterState.useArmor(state)
		return
	end
	local tags = result.tags or {}
	if tags.otg then
		FighterState.hitWhileDowned(state, config, now)
		return
	end
	FighterState.applyStun(state, result.hitstun, now)
	if tags.knockdown and config.Knockdown then
		FighterState.knockDown(state, config, now)
	elseif config.Air then
		if wasAirborne then
			state.juggleCount += 1
		end
		if result.launch > 0 then
			FighterState.launch(state, config, now)
		end
	end
end

-- Damage actually dealt to a fighter with `health` left. Blocked damage can't knock out.
function HitResolver.damageToDeal(result: Outcome, health: number): number
	if result.result == "Blocked" or result.result == "GuardBreak" then
		return math.clamp(math.min(result.damage, health - 1), 0, math.huge)
	end
	return result.damage
end

return HitResolver
