-- Roblox analytics (AnalyticsService) behind one safe door. Every call is wrapped in pcall and
-- rate limited per player, so a failing or missing analytics service never breaks a game action.
--
--   funnel(player, key)         onboarding funnel steps (stable step numbers below), once per session
--   economy(player, ...)        Money and Gems sources and sinks (called by CurrencyService)
--   progression(player, ...)    mastery level-ups
--   custom(player, name, ...)   match results and other events
-- Only UserIds and game facts are sent; no personal data.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RateLimiter = require(ReplicatedStorage.Shared.Utility.RateLimiter)

local AnalyticsLog = {}

-- Stable onboarding step numbers. Never renumber: add new steps with new numbers.
AnalyticsLog.Steps = {
	joined = { 1, "Joined" },
	tour_started = { 2, "Tour started" },
	tour_welcome = { 10, "Tour: welcome" },
	tour_move = { 11, "Tour: move" },
	tour_jump = { 12, "Tour: jump" },
	tour_sprint = { 13, "Tour: sprint" },
	tour_camera = { 14, "Tour: camera" },
	tour_training = { 15, "Tour: training" },
	tour_attack = { 16, "Tour: attack" },
	tour_block = { 17, "Tour: block" },
	tour_dodge = { 18, "Tour: dodge" },
	tour_ability = { 19, "Tour: ability" },
	tour_evolve = { 20, "Tour: evolve" },
	tour_showcase = { 21, "Tour: showcase" },
	tour_win = { 22, "Tour: practice fight" },
	tour_finished = { 30, "Tour finished" },
	first_training = { 31, "First training round" },
	first_match = { 32, "First match" },
	first_win = { 33, "First win" },
}

local limiter = RateLimiter.new(3, 30)
local sent: { [Player]: { [string]: boolean } } = {}

function AnalyticsLog:Init(services)
	self.services = services
	self.data = services.DataService
end

function AnalyticsLog:Start()
	self.data:onLoaded(function(player, profile)
		if profile.meta.sessions <= 1 then
			self:funnel(player, "joined")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		sent[player] = nil
		RateLimiter.forget(limiter, player)
	end)
	local progression = self.services.ProgressionService
	if progression then
		progression:onMatchResult(function(player, result)
			self:_matchResult(player, result)
		end)
	end
end

-- Runs fn(AnalyticsService) safely. Returns true when it ran without an error.
function AnalyticsLog:_call(player: Player, fn: (any) -> ()): boolean
	if not player or not player.Parent then
		return false
	end
	if not RateLimiter.allow(limiter, player, os.clock()) then
		return false
	end
	local ok, err = pcall(fn, AnalyticsService)
	if not ok then
		warn("[Analytics] a call failed: " .. tostring(err))
	end
	return ok
end

-- An onboarding funnel step, at most once per player per session
function AnalyticsLog:funnel(player: Player, key: string): boolean
	local step = AnalyticsLog.Steps[key]
	if not step then
		return false
	end
	local done = sent[player]
	if not done then
		done = {}
		sent[player] = done
	end
	if done[key] then
		return false
	end
	-- Steps can arrive before the join step (other services start first): keep the order right
	if key ~= "joined" and not done.joined then
		local profile = self.data:get(player)
		if profile and profile.meta.sessions <= 1 then
			self:funnel(player, "joined")
		end
	end
	done[key] = true
	return self:_call(player, function(service)
		service:LogOnboardingFunnelStepEvent(player, step[1], step[2])
	end)
end

-- A tour step was completed (id from Config/Tutorial)
function AnalyticsLog:tourStep(player: Player, stepId: string)
	self:funnel(player, "tour_" .. stepId)
end

local function skuOf(reason: any): string
	local text = if typeof(reason) == "string" then reason else ""
	local word = string.match(string.lower(text), "^[%a_]+") or "other"
	return string.sub(word, 1, 40)
end

-- Money or Gems moved: flow "Source" (earned) or "Sink" (spent)
function AnalyticsLog:economy(player: Player, flow: string, currency: string, amount: number, endingBalance: number, reason: any)
	if typeof(amount) ~= "number" or amount <= 0 then
		return
	end
	local sku = skuOf(reason)
	local transaction = if sku == "robux" then "IAP" elseif flow == "Sink" then "Shop" else "Gameplay"
	self:_call(player, function(service)
		local flowType = if flow == "Sink" then Enum.AnalyticsEconomyFlowType.Sink else Enum.AnalyticsEconomyFlowType.Source
		service:LogEconomyEvent(player, flowType, currency, amount, endingBalance, transaction, sku)
	end)
end

function AnalyticsLog:progression(player: Player, path: string, level: number, levelName: string)
	self:_call(player, function(service)
		service:LogProgressionEvent(player, path, Enum.AnalyticsProgressionType.Complete, level, levelName)
	end)
end

function AnalyticsLog:custom(player: Player, name: string, value: number?, fields: { [string]: any }?)
	self:_call(player, function(service)
		service:LogCustomEvent(player, name, value, fields)
	end)
end

function AnalyticsLog:_matchResult(player: Player, result)
	self:custom(player, "MatchResult", if result.won then 1 else 0, {
		mode = tostring(result.mode),
		power = tostring(result.power),
		knockouts = result.knockouts or 0,
		cpu = result.cpu == true,
	})
	if typeof(result.masteryAfter) == "number" and typeof(result.masteryBefore) == "number" and result.masteryAfter > result.masteryBefore then
		self:progression(player, "Mastery_" .. tostring(result.power), result.masteryAfter, "Level " .. result.masteryAfter)
	end
	local profile = self.data:get(player)
	if profile then
		if profile.stats.matches == 1 then
			self:funnel(player, "first_match")
		end
		if result.won and profile.stats.wins == 1 then
			self:funnel(player, "first_win")
		end
	end
end

return AnalyticsLog
