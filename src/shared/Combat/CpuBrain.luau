-- The CPU's decisions as pure functions (no engine, no clocks) so they can be tested with fixed
-- seeds. CpuService feeds them the situation and does what they say through the normal combat
-- rules. Every roll goes through a Random object, so a seed makes a fight repeatable.

local CpuBrain = {}

export type Rng = { NextNumber: (Rng) -> number }

-- A seeded random source. With no seed it is seeded from the clock.
function CpuBrain.newRng(seed: number?): any
	return Random.new(seed or math.floor(os.clock() * 1000) % 2147483647)
end

-- Seconds before the CPU acts on something it saw: its difficulty's reaction time with a human
-- spread (never faster than 0.12 s, so never frame-perfect)
function CpuBrain.reactionDelay(difficulty, rng): number
	return math.max(0.12, difficulty.reaction * (0.8 + rng:NextNumber() * 0.45))
end

-- What to do about an attack just seen: "Dodge", "Block" or "None".
-- Heavies and ability wind-ups are telegraphed: a sharper CPU (`readChance`) recognises them and
-- dodges them or blocks; light jabs are only blocked.
function CpuBrain.defenseChoice(difficulty, kind: string, rng): string
	local telegraphed = kind == "Heavy" or kind == "Ability"
	local roll = rng:NextNumber()
	if telegraphed then
		local read = (difficulty.readChance or 0) > rng:NextNumber()
		if roll < difficulty.dodgeChance + (if read then difficulty.readChance * 0.5 else 0) then
			return "Dodge"
		elseif roll < difficulty.blockChance + (if read then difficulty.readChance * 0.4 else 0) then
			return "Block"
		end
		return "None"
	end
	if roll < difficulty.blockChance then
		return "Block"
	end
	return "None"
end

-- Where to stand. Melee fighters hold their reach (and give a little ground right after a
-- string); ranged fighters back off when someone is inside their comfortable range.
-- Returns "Approach", "Retreat" or "Hold".
function CpuBrain.movePlan(preferred: number, distance: number, disengaging: boolean?): string
	if distance > preferred + (if preferred > 8 then 2 else 1.5) then
		return "Approach"
	end
	if preferred > 8 then
		if distance < preferred - 3 then
			return "Retreat"
		end
	elseif disengaging and distance < preferred + 1 then
		return "Retreat"
	end
	return "Hold"
end

-- Length of the next light string (the chain's last step is the launching finisher, so 4 is the
-- full string) and the pause after it.
function CpuBrain.newCombo(difficulty, rng): (number, number)
	local low, high = difficulty.comboMin or 1, difficulty.comboMax or 2
	local length = low + math.floor(rng:NextNumber() * (high - low + 1))
	length = math.clamp(length, low, high)
	local pause = (difficulty.comboPause or 0.8) * (0.8 + rng:NextNumber() * 0.4)
	return length, pause
end

-- Should the string end in a heavy? Only worth it when it can connect: the target is in
-- hitstun (or otherwise cannot act).
function CpuBrain.wantsHeavyFinisher(difficulty, targetLocked: boolean, rng): boolean
	if targetLocked then
		return rng:NextNumber() < (difficulty.heavyFinish or 0.3)
	end
	return rng:NextNumber() < 0.05
end

-- Will this ultimate land? In range and the target cannot get out of it (stunned, knocked
-- down, in whiff recovery, committed to a swing), or the CPU is the sharper kind and the
-- target is low. Easy just fires it in range now and then.
function CpuBrain.ultimateWillLand(difficulty, ctx, rng): boolean
	if ctx.distance > ctx.range then
		return false
	end
	if ctx.targetLocked then
		return true
	end
	if (difficulty.ultSmart or 0) > 0 then
		if ctx.targetHealthShare < 0.35 and rng:NextNumber() < difficulty.ultSmart then
			return true
		end
		return false
	end
	return rng:NextNumber() < 0.25
end

-- Is this ability worth using now? ctx: distance, healthShare, targetAttacking, targetLocked.
function CpuBrain.abilityWanted(hint, ctx): boolean
	local range = hint.range or 10
	if hint.use == "Escape" then
		return ctx.healthShare < 0.4 and ctx.distance < 8
	elseif hint.use == "Defend" then
		return ctx.distance < range and ctx.targetAttacking
	elseif hint.use == "Poke" then
		-- Pokes are for keeping pressure from a distance, not point blank
		return ctx.distance <= range and ctx.distance >= math.min(6, range * 0.3)
	elseif hint.use == "Finisher" then
		return ctx.distance <= range and (ctx.targetLocked or ctx.healthShare > 0.8 or ctx.targetHealthShare < 0.5)
	end
	-- Engage
	return ctx.distance <= range
end

-- Picks one of several wanted abilities, avoiding the one used last when there is a choice.
function CpuBrain.pickAbility(options: { string }, lastUsed: string?, rng): string?
	if #options == 0 then
		return nil
	end
	local pool = options
	if #options > 1 and lastUsed then
		pool = {}
		for _, id in options do
			if id ~= lastUsed then
				table.insert(pool, id)
			end
		end
	end
	return pool[1 + math.floor(rng:NextNumber() * #pool) % #pool]
end

return CpuBrain
