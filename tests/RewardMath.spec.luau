-- What matches, challenges and login streaks pay (Shared/Progression/RewardMath)

local RewardMath = Harness.load("Shared/Progression/RewardMath")
local Rewards = Harness.load("Shared/Config/Rewards")

local NOW = 1_800_000_000

local function input(overrides)
	local base = {
		mode = "Duel",
		won = false,
		draw = false,
		knockouts = 0,
		damage = 120,
		actions = 20,
		fightSeconds = 90,
		cpuDifficulty = nil,
		rewardLog = {},
		now = NOW,
		sameOpponent = 0,
		firstWinToday = false,
		forfeitEarly = false,
	}
	for key, value in overrides or {} do
		base[key] = value
	end
	return base
end

local function sumLines(reward, field)
	local total = 0
	for _, line in reward.lines do
		total += line[field] or 0
	end
	return total
end

return function(t)
	t.test("losing still pays for taking part, winning pays more", function()
		local lost = RewardMath.matchReward(input())
		local won = RewardMath.matchReward(input({ won = true }))
		t.truthy(lost.paid, "the loser is paid")
		t.equal(lost.money, Rewards.Match.Participation.money, "participation money")
		t.truthy(won.money > lost.money, "the winner earns more")
		t.truthy(won.xp > lost.xp, "and more mastery XP")
		t.equal(won.gems, 0, "no gems without the first win of the day")
	end)

	t.test("the breakdown lines add up to the totals", function()
		local reward = RewardMath.matchReward(input({ won = true, knockouts = 3, damage = 340, firstWinToday = true }))
		t.equal(sumLines(reward, "money"), reward.money, "money lines")
		t.equal(sumLines(reward, "xp"), reward.xp, "xp lines")
		t.equal(sumLines(reward, "gems"), reward.gems, "gem lines")
		t.equal(reward.gems, Rewards.Match.FirstWinOfDayGems, "first win of the day pays gems")
	end)

	t.test("knockouts and damage XP are capped", function()
		local many = RewardMath.matchReward(input({ knockouts = 500, damage = 1e6 }))
		local capped = RewardMath.matchReward(input({ knockouts = Rewards.Match.MaxKnockouts, damage = Rewards.Match.MaxDamageXp * Rewards.Match.DamagePerXp }))
		t.equal(many.money, capped.money, "knockout money stops at the cap")
		t.equal(many.xp, capped.xp, "xp stops at the caps")
		local negative = RewardMath.matchReward(input({ knockouts = -4 }))
		t.equal(negative.money, Rewards.Match.Participation.money, "negative knockouts count as none")
	end)

	t.test("short, forfeited-early and idle matches pay nothing", function()
		local short = RewardMath.matchReward(input({ won = true, fightSeconds = Rewards.Limits.MinFightSeconds - 1 }))
		t.equal(short.paid, false, "too short")
		t.equal(short.money + short.xp + short.gems, 0, "nothing paid")
		t.truthy(short.note ~= nil, "and the player is told why")
		local forfeit = RewardMath.matchReward(input({ won = true, forfeitEarly = true }))
		t.equal(forfeit.paid, false, "opponent left straight away")
		local idle = RewardMath.matchReward(input({ damage = 0, actions = 0 }))
		t.equal(idle.paid, false, "standing still")
		local busyButHarmless = RewardMath.matchReward(input({ damage = 0, actions = Rewards.Limits.MinActions }))
		t.truthy(busyButHarmless.paid, "trying counts even without landing damage")
	end)

	t.test("too many matches in an hour pay a reduced share", function()
		local log = {}
		for index = 1, Rewards.Limits.HourlyFullRewards do
			table.insert(log, NOW - index * 60)
		end
		local full = RewardMath.matchReward(input({ won = true }))
		local reduced = RewardMath.matchReward(input({ won = true, rewardLog = log }))
		t.truthy(reduced.paid, "still paid")
		t.near(reduced.money, math.floor(full.money * Rewards.Limits.ReducedShare + 0.5), 1, "reduced money")
		t.truthy(reduced.note ~= nil, "with a note")
		-- Matches older than an hour don't count
		local old = {}
		for index = 1, 30 do
			table.insert(old, NOW - 3600 - index)
		end
		t.equal(RewardMath.matchReward(input({ won = true, rewardLog = old })).money, full.money, "old matches don't reduce")
	end)

	t.test("the same opponent again and again pays less", function()
		local full = RewardMath.matchReward(input({ won = true }))
		local repeated = RewardMath.matchReward(input({ won = true, sameOpponent = Rewards.Limits.SameOpponentLimit }))
		t.near(repeated.money, math.floor(full.money * Rewards.Limits.SameOpponentShare + 0.5), 1, "half money")
		local fine = RewardMath.matchReward(input({ won = true, sameOpponent = Rewards.Limits.SameOpponentLimit - 1 }))
		t.equal(fine.money, full.money, "below the limit pays in full")
	end)

	t.test("modes and CPU difficulty scale the pay", function()
		local duel = RewardMath.matchReward(input({ won = true }))
		local easy = RewardMath.matchReward(input({ won = true, mode = "Practice", cpuDifficulty = "Easy" }))
		local hard = RewardMath.matchReward(input({ won = true, mode = "Practice", cpuDifficulty = "Hard" }))
		t.truthy(easy.money < hard.money, "hard CPUs pay more than easy ones")
		t.truthy(hard.money < duel.money, "practice pays less than a real duel")
		local practiceFirst = RewardMath.matchReward(input({ won = true, mode = "Practice", cpuDifficulty = "Hard", firstWinToday = true }))
		t.equal(practiceFirst.gems, 0, "the first-win gems need a real opponent")
	end)

	t.test("daily challenges: three a day, the same for everyone, varying by day", function()
		local today = RewardMath.dailyFor(20000)
		t.equal(#today, Rewards.DailyCount, "three challenges")
		local again = RewardMath.dailyFor(20000)
		for index, challenge in today do
			t.equal(again[index].id, challenge.id, "same day, same challenges")
		end
		local seen = {}
		for _, challenge in today do
			t.truthy(not seen[challenge.id], "no duplicates in a day")
			seen[challenge.id] = true
		end
		local differs = false
		for day = 20001, 20010 do
			if RewardMath.dailyFor(day)[1].id ~= today[1].id then
				differs = true
			end
		end
		t.truthy(differs, "the challenges change from day to day")
		t.equal(RewardMath.dayNumber(86400 * 3 + 5), 3, "day numbers count whole UTC days")
	end)

	t.test("login streak money grows, caps, and every 7th day gives gems", function()
		local money = Rewards.LoginStreak.Money
		t.equal(RewardMath.loginReward(1).money, money[1], "day 1")
		t.truthy(RewardMath.loginReward(3).money > RewardMath.loginReward(2).money, "grows")
		t.equal(RewardMath.loginReward(40).money, money[#money], "caps at the last value")
		t.equal(RewardMath.loginReward(6).gems, 0, "no gems on day 6")
		t.equal(RewardMath.loginReward(7).gems, Rewards.LoginStreak.WeeklyGems, "gems on day 7")
		t.equal(RewardMath.loginReward(14).gems, Rewards.LoginStreak.WeeklyGems, "and day 14")
		t.equal(RewardMath.loginReward(0).money, money[1], "a zero streak is treated as day 1")
	end)
end
