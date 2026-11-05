-- The cosmetic season pass (Config/SeasonPass). Points come from paid matches, finished
-- practice rounds and claimed daily challenges, and nothing else. The free track pays small
-- Money amounts and cosmetics, the premium track (a developer product, handled by
-- PurchaseService) pays one cosmetic per tier. Claims are checked here: the tier must be
-- reached, the reward not yet claimed, and the premium track unlocked for this season.
-- Nothing on the pass changes a stat, and nothing on it is random.
--
--   SeasonPassService:snapshot(player)                the player's pass, season rolled over
--   SeasonPassService:claim(player, key): (boolean, string?)   key like "f3" or "p12"
--   SeasonPassService:addPoints(player, amount, reason): number   points really added
--   SeasonPassService:onTrainingRound(player, seconds)            (PracticeService)
--   SeasonPassService:onDailyChallenge(player)                    (ProgressionService)
--   SeasonPassService:canSellPremium(player) / canSellSkip(player): (boolean, string?)
--   SeasonPassService.applyPurchase(profile, kind, now)           inside a DataService update

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local SeasonPass = require(ReplicatedStorage.Shared.Config.SeasonPass)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local SeasonPassService = {}

-- Practice rounds that paid points today (UTC day), by player; resets with the server
local trainingToday: { [number]: { day: number, count: number } } = {}

local function toast(player: Player, text: string, kind: string)
	if player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Toast, { text = text, kind = kind })
	end
end

local function utcDay(now: number): number
	return math.floor(now / 86400)
end

function SeasonPassService:Init(services)
	self.services = services
	self.data = services.DataService
	self.currency = services.CurrencyService
	self.antiExploit = services.AntiExploitService
end

function SeasonPassService:Start()
	local progression = self.services.ProgressionService
	if progression and progression.onMatchResult then
		progression:onMatchResult(function(player, result)
			self:_onMatchResult(player, result)
		end)
	end
	self.data:onLoaded(function(player)
		self:_roll(player)
	end)
	local request = Remotes:FindFirstChild("ShopRequest")
	if request then
		request.OnServerEvent:Connect(function(player, action, key)
			if action ~= Protocol.ShopAction.ClaimTier then
				return
			end
			if typeof(key) ~= "string" or #key > 8 then
				return
			end
			if self.antiExploit and not self.antiExploit:allow(player, "Shop") then
				return
			end
			local ok, reason = self:claim(player, key)
			if not ok and reason then
				toast(player, reason, "error")
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		trainingToday[player.UserId] = nil
	end)
end

-- Season state of a profile ------------------------------------------------------------------

-- Starts a fresh pass when the running season is not the one the profile holds. Returns true
-- when it changed the profile. Between seasons the old pass stays as it was.
function SeasonPassService.rollProfile(profile, now: number): boolean
	local running = SeasonPass.current(now)
	if not running or profile.pass.season == running.id then
		return false
	end
	profile.pass = { season = running.id, points = 0, premium = false, claimed = {} }
	return true
end

-- Applies a purchased product to a profile (inside a DataService update, so it must not wait).
-- "premium" unlocks the premium track of the season the pass belongs to; "skip" adds one tier of
-- points, capped at the last tier. A purchase made while no season runs lands on the latest
-- season, so Robux are never taken for nothing.
function SeasonPassService.applyPurchase(profile, kind: string, now: number)
	SeasonPassService.rollProfile(profile, now)
	if profile.pass.season == "" then
		profile.pass.season = SeasonPass.shown(now).id
	end
	if kind == "premium" then
		profile.pass.premium = true
	elseif kind == "skip" then
		profile.pass.points = math.min(SeasonPass.maxPoints(), profile.pass.points + SeasonPass.PointsPerTier)
	end
end

function SeasonPassService:_roll(player: Player)
	local changed = false
	self.data:update(player, function(profile)
		changed = SeasonPassService.rollProfile(profile, os.time())
	end)
	return changed
end

function SeasonPassService:snapshot(player: Player): { [string]: any }?
	if not self.data:get(player) then
		return nil
	end
	self:_roll(player)
	local profile = self.data:get(player)
	local pass = profile.pass
	return {
		season = pass.season,
		points = pass.points,
		tier = SeasonPass.tierOf(pass.points),
		premium = pass.premium,
		claimed = pass.claimed,
	}
end

-- Whether the shop may open a Robux window for these (the season must be running)
function SeasonPassService:canSellPremium(player: Player): (boolean, string?)
	if not SeasonPass.current(os.time()) then
		return false, "No season is running right now."
	end
	local pass = self:snapshot(player)
	if not pass then
		return false, "Your data is still loading."
	end
	if pass.premium then
		return false, "You already have this season's premium track."
	end
	return true
end

function SeasonPassService:canSellSkip(player: Player): (boolean, string?)
	if not SeasonPass.current(os.time()) then
		return false, "No season is running right now."
	end
	local pass = self:snapshot(player)
	if not pass then
		return false, "Your data is still loading."
	end
	if pass.points >= SeasonPass.maxPoints() then
		return false, "You have already reached the last tier."
	end
	return true
end

-- Points -----------------------------------------------------------------------------------------

-- Adds points (only while a season is running). Returns the points really added.
function SeasonPassService:addPoints(player: Player, amount: number, reason: string?): number
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0
	end
	local now = os.time()
	if not SeasonPass.current(now) then
		return 0
	end
	local added, before, after = 0, 0, 0
	local ok = self.data:update(player, function(profile)
		SeasonPassService.rollProfile(profile, now)
		before = profile.pass.points
		after = math.min(SeasonPass.maxPoints(), before + math.floor(amount))
		profile.pass.points = after
		added = after - before
	end)
	if not ok or added <= 0 then
		return 0
	end
	local tierBefore, tierAfter = SeasonPass.tierOf(before), SeasonPass.tierOf(after)
	if tierAfter > tierBefore then
		toast(player, `Season pass: tier {tierAfter} reached. Open the pass to claim your rewards.`, "reward")
	end
	return added
end

function SeasonPassService:_onMatchResult(player: Player, result)
	if typeof(result) ~= "table" or result.paid ~= true then
		return
	end
	local points = SeasonPass.Points.Match
	if result.won == true and result.draw ~= true then
		points += SeasonPass.Points.Win
	end
	self:addPoints(player, points, "match")
end

function SeasonPassService:onTrainingRound(player: Player, seconds: number)
	if typeof(seconds) ~= "number" or seconds < SeasonPass.MinTrainingSeconds then
		return
	end
	local day = utcDay(os.time())
	local entry = trainingToday[player.UserId]
	if not entry or entry.day ~= day then
		entry = { day = day, count = 0 }
		trainingToday[player.UserId] = entry
	end
	if entry.count >= SeasonPass.TrainingPerDay then
		return
	end
	entry.count += 1
	self:addPoints(player, SeasonPass.Points.Training, "training")
end

function SeasonPassService:onDailyChallenge(player: Player)
	self:addPoints(player, SeasonPass.Points.Daily, "daily")
end

-- Claims ------------------------------------------------------------------------------------------

-- Returns (true) or (false, plain reason). Safe to call with any value.
function SeasonPassService:claim(player: Player, key: any): (boolean, string?)
	if typeof(key) ~= "string" then
		return false, nil
	end
	local trackCode, tierText = string.match(key, "^([fp])(%d+)$")
	local tier = tonumber(tierText)
	if not trackCode or not tier or tier < 1 or tier > SeasonPass.TierCount or tier ~= math.floor(tier) then
		return false, nil
	end
	local track = if trackCode == "p" then "premium" else "free"
	local pass = self:snapshot(player)
	if not pass then
		return false, "Your data is still loading."
	end
	if tier > pass.tier then
		return false, "You have not reached that tier yet."
	end
	if track == "premium" and not pass.premium then
		return false, "The premium track is not unlocked for this season."
	end
	local cosmeticService = self.services.CosmeticService
	local reward = if track == "free" then SeasonPass.Free[tier] else { cosmetic = SeasonPass.Premium[tier] }
	if reward.cosmetic and not cosmeticService then
		return false, "Cosmetics are not available yet. Try again in a moment."
	end
	local claimKey = SeasonPass.claimKey(track, tier)
	local first = false
	self.data:update(player, function(profile)
		if profile.pass.claimed[claimKey] ~= true then
			profile.pass.claimed[claimKey] = true
			first = true
		end
	end)
	if not first then
		return false, "You already claimed that reward."
	end
	local given = true
	if reward.money then
		given = self.currency:add(player, { money = reward.money }, "season pass tier " .. tier)
		if given then
			toast(player, `Tier {tier}: +{reward.money} Money`, "reward")
		end
	elseif reward.cosmetic then
		local item = Cosmetics.get(reward.cosmetic)
		-- grant returns false when the player already owns it; the claim still counts
		cosmeticService:grant(player, reward.cosmetic, "season")
		if item == nil then
			given = false
		end
	end
	if not given then
		self.data:update(player, function(profile)
			profile.pass.claimed[claimKey] = nil
		end)
		return false, "That reward could not be given. Please try again."
	end
	return true
end

return SeasonPassService
