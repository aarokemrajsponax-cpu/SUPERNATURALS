-- The arithmetic behind rewards: what a match pays, which daily challenges
-- are live today, and login streak money. Pure functions with explicit inputs
-- (times are os.time() seconds), so the rules are tested outside Roblox.

local Rewards = require(script.Parent.Parent.Config.Rewards)

local RewardMath = {}

local DAY = 86400

function RewardMath.dayNumber(unixTime: number): number
	return math.floor(unixTime / DAY)
end

-- Today's challenges: the same three for everyone on a given day
function RewardMath.dailyFor(day: number): { any }
	local pool = table.clone(Rewards.DailyPool)
	-- A small deterministic shuffle seeded by the day
	local seed = (day * 9301 + 49297) % 233280
	for index = #pool, 2, -1 do
		seed = (seed * 9301 + 49297) % 233280
		local swap = seed % index + 1
		pool[index], pool[swap] = pool[swap], pool[index]
	end
	local picked = {}
	for index = 1, math.min(Rewards.DailyCount, #pool) do
		table.insert(picked, pool[index])
	end
	return picked
end

-- Money for logging in on the `streak`-th day in a row (and Gems every 7th day)
function RewardMath.loginReward(streak: number): { money: number, gems: number }
	local table_ = Rewards.LoginStreak.Money
	local money = table_[math.clamp(streak, 1, #table_)]
	local gems = if streak > 0 and streak % 7 == 0 then Rewards.LoginStreak.WeeklyGems else 0
	return { money = money, gems = gems }
end

export type MatchInput = {
	mode: string,
	won: boolean,
	draw: boolean,
	knockouts: number,
	damage: number,
	actions: number,
	fightSeconds: number,
	cpuDifficulty: string?,
	-- os.time() of earlier rewarded matches
	rewardLog: { number },
	now: number,
	-- How many times this player recently fought the same opponent (duels)
	sameOpponent: number,
	firstWinToday: boolean,
	-- True when the opponent left before the fight really happened
	forfeitEarly: boolean?,
}

export type Line = { label: string, money: number?, gems: number?, xp: number? }
export type Reward = { money: number, gems: number, xp: number, lines: { Line }, note: string?, paid: boolean }

-- What a match pays one player
function RewardMath.matchReward(input: MatchInput): Reward
	local match = Rewards.Match
	local limits = Rewards.Limits
	local reward: Reward = { money = 0, gems = 0, xp = 0, lines = {}, note = nil, paid = false }

	if input.fightSeconds < limits.MinFightSeconds or input.forfeitEarly then
		reward.note = "The match was too short to pay out."
		return reward
	end
	if input.damage < limits.MinDamage and input.actions < limits.MinActions then
		reward.note = "No rewards for standing still. Get stuck in next time!"
		return reward
	end

	local money, xp = 0, 0
	local function add(label: string, addMoney: number, addXp: number)
		money += addMoney
		xp += addXp
		table.insert(reward.lines, { label = label, money = addMoney, xp = addXp })
	end
	add("Took part", match.Participation.money, match.Participation.xp)
	if input.won then
		add("Victory", match.Win.money, match.Win.xp)
	elseif input.draw then
		add("Draw", match.Draw.money, match.Draw.xp)
	end
	local knockouts = math.clamp(math.floor(input.knockouts), 0, match.MaxKnockouts)
	if knockouts > 0 then
		add(`{knockouts} knockout{if knockouts == 1 then "" else "s"}`, knockouts * match.PerKnockout.money, knockouts * match.PerKnockout.xp)
	end
	local damageXp = math.clamp(math.floor(input.damage / match.DamagePerXp), 0, match.MaxDamageXp)
	if damageXp > 0 then
		add(`{math.floor(input.damage)} damage dealt`, 0, damageXp)
	end

	-- Mode and difficulty
	local share = match.ModeShare[input.mode] or 1
	if input.mode == "Practice" and input.cpuDifficulty then
		share *= match.CpuShare[input.cpuDifficulty] or 1
	end
	-- Anti-farming: lots of matches in an hour, or the same opponent again and again
	local recent = 0
	for _, time in input.rewardLog do
		if input.now - time < 3600 then
			recent += 1
		end
	end
	if recent >= limits.HourlyFullRewards then
		share *= limits.ReducedShare
		reward.note = "You've played a lot this hour, so rewards are lower for a while."
	elseif input.sameOpponent >= limits.SameOpponentLimit then
		share *= limits.SameOpponentShare
		reward.note = "Rematching the same opponent pays less. Try someone new!"
	end
	if math.abs(share - 1) > 1e-6 then
		for _, line in reward.lines do
			line.money = math.floor((line.money or 0) * share + 0.5)
			line.xp = math.floor((line.xp or 0) * share + 0.5)
		end
		money = math.floor(money * share + 0.5)
		xp = math.floor(xp * share + 0.5)
	end
	reward.money = money
	reward.xp = xp
	if input.won and input.firstWinToday and input.mode ~= "Practice" then
		reward.gems += match.FirstWinOfDayGems
		table.insert(reward.lines, { label = "First win of the day", gems = match.FirstWinOfDayGems })
	end
	reward.paid = true
	return reward
end

return RewardMath
