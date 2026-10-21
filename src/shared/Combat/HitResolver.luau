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
	}
end

function HitResolver.resolve(attack, config, attacker: Side, defender: Side, now: number): Outcome
	local state = defender.state
	if FighterState.isInvulnerable(state, now) then
		return outcome("Invulnerable")
	end

	local block = config.Block
	local guarding = FighterState.isBlocking(state)
		and Hitbox.isInFront(defender.position, defender.look, attacker.position, block.FrontArc)

	if guarding then
		if attack.Parryable ~= false and FighterState.inParryWindow(state, config, now) then
			local parried = outcome("Parried")
			parried.attackerStun = block.ParryStun
			return parried
		end
		local guardDamage = attack.GuardDamage or 0
		local broken = FighterState.guardAt(state, config, now) - guardDamage <= 0
		local result = outcome(if broken then "GuardBreak" else "Blocked")
		result.damage = attack.Damage * block.DamageMultiplier
		result.knockback = attack.Knockback * block.PushbackMultiplier
		result.guardDamage = guardDamage
		result.hitstun = if broken then block.GuardBreakStun else 0
		return result
	end

	local hit = outcome("Hit")
	hit.damage = attack.Damage
	hit.hitstun = attack.Hitstun
	hit.knockback = attack.Knockback
	hit.launch = attack.Launch or 0
	-- Past the combo limit, hits still hurt but stop stunning and push the victim clear
	if FighterState.projectedCombo(state, config, now) > config.MaxComboHits then
		hit.comboCapped = true
		hit.hitstun = 0
		hit.knockback = math.max(hit.knockback, 45)
		hit.launch = math.max(hit.launch, 12)
	end
	return hit
end

function HitResolver.apply(result: Outcome, config, attacker: Side, defender: Side, now: number)
	local kind = result.result
	if kind == "Invulnerable" then
		return
	elseif kind == "Parried" then
		FighterState.applyStun(attacker.state, result.attackerStun, now)
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

	FighterState.registerHit(defender.state, config, attacker.id, now)
	FighterState.applyStun(defender.state, result.hitstun, now)
end

-- Damage actually dealt to a fighter with `health` left. Blocked damage can't knock out.
function HitResolver.damageToDeal(result: Outcome, health: number): number
	if result.result == "Blocked" or result.result == "GuardBreak" then
		return math.clamp(math.min(result.damage, health - 1), 0, math.huge)
	end
	return result.damage
end

return HitResolver
