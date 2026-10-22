-- Progression: what playing earns. After every match each player is paid
-- Money, maybe Gems, and mastery XP for the power they used (see
-- Config/Rewards and Shared/Progression/RewardMath), their stats are updated,
-- and daily challenges and login streaks tick forward. Anti-farming rules
-- (too short, idle, too many matches, same opponent again and again) cut the
-- pay. Everything is decided and granted on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Rewards = require(ReplicatedStorage.Shared.Config.Rewards)
local RewardMath = require(ReplicatedStorage.Shared.Progression.RewardMath)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ProgressRequest = Remotes:WaitForChild("ProgressRequest") :: RemoteEvent
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local Action = Protocol.ProgressAction

local ProgressionService = {}

type Tracked = { damage: number, hits: number, actions: number, matchId: string }

-- fighter id -> what they did in their current match
local tracked: { [string]: Tracked } = {}
-- userId -> recent duel opponents { { id, time } } (this server only)
local recentOpponents: { [number]: { { id: number, time: number } } } = {}

local function toast(player: Player, text: string, kind: string?)
	if player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Toast, { text = text, kind = kind or "info" })
	end
end

function ProgressionService:Init(services)
	self.services = services
	self.data = services.DataService
	self.currency = services.CurrencyService
	self.antiExploit = services.AntiExploitService
end

function ProgressionService:Start()
	local matchService = self.services.MatchService
	matchService:onStarted(function(match)
		for _, participant in match.participants do
			tracked[participant.id] = { damage = 0, hits = 0, actions = 0, matchId = match.id }
		end
	end)
	matchService:onFinished(function(match, result)
		self:_payMatch(match, result)
	end)

	self.services.CombatService:onHit(function(attacker, target, outcome)
		local record = tracked[attacker.id]
		local landed = outcome.result == "Hit" or outcome.result == "Blocked" or outcome.result == "GuardBreak"
		if record and landed and matchService:getMatchOf(attacker) then
			record.damage += outcome.dealt or 0
			record.hits += 1
			record.actions += 1
			if attacker.player then
				self:_progress(attacker.player, "hits", 1)
				self:_progress(attacker.player, "damage", math.floor(outcome.dealt or 0))
			end
		end
		local _ = target
	end)
	self.services.AbilityService:onUsed(function(fighter, _, def, basic)
		local record = tracked[fighter.id]
		if record and matchService:getMatchOf(fighter) then
			record.actions += 1
			if fighter.player and not basic then
				self:_progress(fighter.player, "abilities", 1)
				if def.kind == "Ultimate" then
					self:_progress(fighter.player, "ultimates", 1)
				end
			end
		end
	end)
	self.services.DefenseService:onResult(function(fighter, kind, result)
		if not fighter.player or not matchService:getMatchOf(fighter) then
			return
		end
		if result == "Perfect" then
			self:_progress(fighter.player, "perfects", 1)
		elseif result == "Escaped" and kind == "Mash" then
			self:_progress(fighter.player, "escapes", 1)
		end
	end)

	-- New day: reset challenges and pay the login streak
	self.data:onLoaded(function(player)
		self:_rollDay(player, true)
	end)

	ProgressRequest.OnServerEvent:Connect(function(player, action, argument)
		if not self.antiExploit:allow(player, "Progress") or typeof(action) ~= "string" then
			return
		end
		if action == Action.ClaimChallenge and typeof(argument) == "string" then
			self:_claim(player, argument)
		elseif action == Action.Welcome then
			self.data:update(player, function(profile)
				profile.tutorial.welcomed = true
			end)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		recentOpponents[player.UserId] = nil
		tracked["Player:" .. player.UserId] = nil
	end)
end

-- Today's challenges (the same for everyone)
function ProgressionService:today(): { any }
	return RewardMath.dailyFor(RewardMath.dayNumber(os.time()))
end

-- Starts a new day for this player if it's a new UTC day: fresh challenges and
-- the login streak (paid when `payLogin`)
function ProgressionService:_rollDay(player: Player, payLogin: boolean)
	local profile = self.data:get(player)
	if not profile then
		return
	end
	local today = RewardMath.dayNumber(os.time())
	local daily = profile.daily
	if daily.day == today then
		return
	end
	local streak = if daily.day == today - 1 then daily.loginStreak + 1 else 1
	self.data:update(player, function(saved)
		saved.daily.day = today
		saved.daily.progress = {}
		saved.daily.claimed = {}
		saved.daily.loginStreak = streak
	end)
	if payLogin then
		local reward = RewardMath.loginReward(streak)
		self.currency:add(player, { money = reward.money, gems = reward.gems }, "login streak " .. streak)
		local gems = if reward.gems > 0 then ` and {reward.gems} Gems` else ""
		toast(player, `Day {streak} login streak: +{reward.money} Money{gems}!`, "reward")
	end
end

-- Adds to a daily challenge counter (only counts toward today's challenges)
function ProgressionService:_progress(player: Player, stat: string, amount: number)
	if amount <= 0 then
		return
	end
	local relevant = false
	for _, challenge in self:today() do
		if challenge.stat == stat then
			relevant = true
		end
	end
	if not relevant then
		return
	end
	self:_rollDay(player, false)
	self.data:update(player, function(profile)
		local progress = profile.daily.progress
		progress[stat] = math.min(1e7, (progress[stat] or 0) + math.floor(amount))
	end)
end

function ProgressionService:_claim(player: Player, challengeId: string)
	local profile = self.data:get(player)
	if not profile then
		return
	end
	self:_rollDay(player, false)
	profile = self.data:get(player)
	local challenge = nil
	for _, candidate in self:today() do
		if candidate.id == challengeId then
			challenge = candidate
		end
	end
	if not challenge then
		toast(player, "That challenge isn't available today.", "error")
		return
	end
	if profile.daily.claimed[challengeId] then
		toast(player, "You already claimed that one.")
		return
	end
	if (profile.daily.progress[challenge.stat] or 0) < challenge.goal then
		toast(player, "Not finished yet!", "error")
		return
	end
	self.data:update(player, function(saved)
		saved.daily.claimed[challengeId] = true
	end)
	self.currency:add(player, challenge.reward, "challenge " .. challengeId)
	toast(player, `Challenge complete: {challenge.text}! +{self.currency.describe(challenge.reward)}`, "reward")
end

-- Paying a finished match ---------------------------------------------------------

function ProgressionService:_payMatch(match, result)
	local now = os.time()
	local winners = {}
	for _, id in result.winners or {} do
		winners[id] = true
	end
	local fightSeconds = if match.fightStartedAt then workspace:GetServerTimeNow() - match.fightStartedAt else 0
	local humans = {}
	for _, participant in match.participants do
		if participant.player then
			table.insert(humans, participant)
		end
	end
	-- Who forfeited before the fight really started? (their opponent's win doesn't pay)
	local forfeitEarly = result.reason == "Forfeit" and fightSeconds < Rewards.Limits.MinFightSeconds

	for _, entry in result.ranking or {} do
		local participant = match.byId[entry.id]
		local player = participant and participant.player
		if player and player.Parent and not entry.left then
			self:_payPlayer(player, match, entry, winners[entry.id] == true, result.draw == true, fightSeconds, forfeitEarly, humans, now)
		end
	end

	-- Free spectator predictions: a small reward if right, nothing lost if wrong
	for player, fighterId in match.predictions do
		if player.Parent and winners[fighterId] and not result.draw then
			self.currency:add(player, { money = Rewards.Match.PredictionMoney }, "prediction")
			toast(player, `Your prediction was right! +{Rewards.Match.PredictionMoney} Money`, "reward")
		end
	end
	for _, participant in match.participants do
		tracked[participant.id] = nil
	end
end

function ProgressionService:_payPlayer(player: Player, match, entry, won: boolean, draw: boolean, fightSeconds: number, forfeitEarly: boolean, humans, now: number)
	local profile = self.data:get(player)
	if not profile then
		return
	end
	self:_rollDay(player, false)
	profile = self.data:get(player)
	local record = tracked[entry.id] or { damage = 0, hits = 0, actions = 0 }

	-- How often these two have dueled lately
	local sameOpponent = 0
	if match.modeName == "Duel" then
		local history = recentOpponents[player.UserId] or {}
		recentOpponents[player.UserId] = history
		for _, other in humans do
			if other.player and other.player ~= player then
				for _, past in history do
					if past.id == other.player.UserId and now - past.time < Rewards.Limits.SameOpponentWindow then
						sameOpponent += 1
					end
				end
				table.insert(history, { id = other.player.UserId, time = now })
			end
		end
		while #history > 20 do
			table.remove(history, 1)
		end
	end

	local reward = RewardMath.matchReward({
		mode = match.modeName,
		won = won,
		draw = draw,
		knockouts = entry.knockouts or 0,
		damage = record.damage,
		actions = record.actions,
		fightSeconds = fightSeconds,
		cpuDifficulty = match.cpu and match.cpu.difficulty,
		rewardLog = profile.rewardLog,
		now = now,
		sameOpponent = sameOpponent,
		firstWinToday = (profile.daily.progress.wins or 0) == 0,
		forfeitEarly = forfeitEarly and won,
	})

	-- The power they fought with (locked for the match) earns the mastery
	local locked = self.services.PowerService:lockedSelection(player)
	local powerId = if locked then locked.power else (profile.selected and profile.selected.power) or Powers.Default
	local before = Powers.masteryLevel((profile.powers[powerId] and profile.powers[powerId].xp) or 0)
	local levelGems = 0
	self.data:update(player, function(saved)
		local stats = saved.stats
		stats.matches += 1
		if won then
			stats.wins += 1
			stats.streak += 1
			stats.bestStreak = math.max(stats.bestStreak, stats.streak)
		elseif draw then
			stats.draws += 1
		else
			stats.losses += 1
			stats.streak = 0
		end
		stats.knockouts += entry.knockouts or 0
		stats.deaths += entry.deaths or 0
		if reward.paid then
			local powerEntry = saved.powers[powerId] or {}
			powerEntry.xp = math.min(1e7, (powerEntry.xp or 0) + reward.xp)
			saved.powers[powerId] = powerEntry
			table.insert(saved.rewardLog, now)
			while #saved.rewardLog > 50 do
				table.remove(saved.rewardLog, 1)
			end
		end
	end)
	profile = self.data:get(player)
	local after = Powers.masteryLevel((profile.powers[powerId] and profile.powers[powerId].xp) or 0)
	if after > before then
		levelGems = (after - before) * Rewards.Match.LevelUpGems
		table.insert(reward.lines, { label = `Mastery level {after}!`, gems = levelGems })
	end
	if reward.money > 0 or reward.gems + levelGems > 0 then
		self.currency:add(player, { money = reward.money, gems = reward.gems + levelGems }, "match " .. match.id)
	end

	-- Daily challenges
	self:_progress(player, "matches", 1)
	if won then
		self:_progress(player, "wins", 1)
		if match.modeName == "Practice" and match.cpu and match.cpu.difficulty == "Hard" then
			self:_progress(player, "hardCpuWins", 1)
		end
	end
	self:_progress(player, "knockouts", entry.knockouts or 0)

	local def = Powers.get(powerId)
	DataEvent:FireClient(player, Protocol.DataEvent.Reward, {
		money = reward.money,
		gems = reward.gems + levelGems,
		xp = reward.xp,
		lines = reward.lines,
		note = reward.note,
		power = powerId,
		powerName = if def then def.name else powerId,
		level = after,
		levelUp = after > before,
		won = won,
	})
end

return ProgressionService
