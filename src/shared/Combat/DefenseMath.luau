-- The rules that judge interactive defenses: timing bars, grab escapes and
-- dodge/block prompts. Pure functions with explicit times, so they're tested
-- outside Roblox and the server never relies on a time the client claims.

local DefenseMath = {}

-- When the player most likely pressed, given when the server received it and
-- their measured ping (round trip, seconds). Only half the ping is one-way, and
-- the allowance is capped so a laggy connection can't buy extra time.
function DefenseMath.estimatePressTime(receivedAt: number, ping: number?, cap: number): number
	local oneWay = if ping and ping == ping and ping > 0 then ping * 0.5 else 0
	return receivedAt - math.clamp(oneWay, 0, cap)
end

-- Timing bar: how close to the moment of impact the press landed
function DefenseMath.gradeTiming(pressAt: number, impactAt: number, perfectWindow: number, goodWindow: number): string
	local error = math.abs(pressAt - impactAt)
	if error <= perfectWindow then
		return "Perfect"
	elseif error <= goodWindow then
		return "Good"
	end
	return "Failed"
end

-- Grab escapes: presses count only if they're far enough apart (no macro spam)
-- and arrive before the deadline
export type Mash = { required: number, count: number, lastAt: number, deadline: number, minInterval: number }

function DefenseMath.newMash(required: number, deadline: number, minInterval: number): Mash
	return { required = math.max(1, required), count = 0, lastAt = -math.huge, deadline = deadline, minInterval = minInterval }
end

function DefenseMath.press(mash: Mash, at: number): boolean
	if at > mash.deadline or at - mash.lastAt < mash.minInterval then
		return false
	end
	mash.lastAt = at
	mash.count += 1
	return true
end

function DefenseMath.escaped(mash: Mash): boolean
	return mash.count >= mash.required
end

-- Dodge/block prompt: a defense that started while the prompt was showing (a
-- little latency allowance either side) is a perfect read
function DefenseMath.inPromptWindow(startedAt: number?, opensAt: number, closesAt: number, allowance: number): boolean
	if not startedAt then
		return false
	end
	return startedAt >= opensAt - allowance and startedAt <= closesAt + allowance
end

return DefenseMath
