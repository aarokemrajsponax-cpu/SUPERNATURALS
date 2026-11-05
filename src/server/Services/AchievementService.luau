-- Achievements and server-wide moments. Counts progress from real events (match results from
-- ProgressionService, practice rounds, watched matches, base visits, recovered Archive files,
-- mastery) and saves it in profile.achievements = { done, progress }. A finished achievement is
-- marked done in one profile update; only then its title is given through CosmeticService and
-- the player told. Config: Shared/Config/Achievements.
--
--   AchievementService:count(player, key, amount?)   add to a counter (progress[key])
--   AchievementService:evaluate(player, quiet?)      finish whatever is now reached
--   AchievementService:announce(player, line, headline?, sub?): boolean
--       one short line in everyone's chat (display names only, no free text), at most one every
--       MomentGap seconds; extra lines wait in a short queue and are dropped past QueueMax
--
-- Moments are earned status only: achievements marked notable, mastery 10 and 20, win streaks
-- of 5, 10 and 15. Nothing here is ever for sale or rolled.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage.Shared.Config.Achievements)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Seasons = require(ReplicatedStorage.Shared.Seasons)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent
local StatusEvent = Remotes:WaitForChild("StatusEvent") :: RemoteEvent

local AchievementService = {}

AchievementService.MomentGap = 8
AchievementService.QueueMax = 3
-- Streak lengths that get a server line
AchievementService.StreakMoments = { [5] = true, [10] = true, [15] = true }

local MAX_LINE = 140
local EVALUATE_DELAY = 0.5

local queue: { string } = {}
local lastLine = -math.huge
local pumping = false
local pendingEvaluate: { [Player]: boolean } = {}
local seenMatches: { [Player]: { [string]: boolean } } = {}
local visitedBases: { [Player]: { [number]: boolean } } = {}

function AchievementService:Init(services)
	self.services = services
	self.data = services.DataService
	self.cosmetics = services.CosmeticService
end

function AchievementService:Start()
	local services = self.services

	if services.ProgressionService and services.ProgressionService.onMatchResult then
		services.ProgressionService:onMatchResult(function(player, result)
			self:_onMatchResult(player, result)
		end)
	end

	self.data:onChanged(function(player)
		self:_schedule(player)
	end)
	self.data:onLoaded(function(player)
		self:_watchSpectating(player)
		self:evaluate(player, true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		pendingEvaluate[player] = nil
		seenMatches[player] = nil
		visitedBases[player] = nil
	end)
	self:_hookBases()
	self:_hookPractice()
end

-- Progress ---------------------------------------------------------------------------------------

function AchievementService:count(player: Player, key: string, amount: number?): boolean
	local n = amount or 1
	if typeof(key) ~= "string" or #key > 64 or typeof(n) ~= "number" or n ~= n or n <= 0 then
		return false
	end
	return self.data:update(player, function(profile)
		local progress = profile.achievements.progress
		progress[key] = math.min(1e9, (progress[key] or 0) + math.floor(n))
	end)
end

function AchievementService:_schedule(player: Player)
	if pendingEvaluate[player] then
		return
	end
	pendingEvaluate[player] = true
	task.delay(EVALUATE_DELAY, function()
		pendingEvaluate[player] = nil
		if player.Parent then
			self:evaluate(player, false)
		end
	end)
end

-- Finishes every achievement whose goal is now reached. `quiet` skips the server-wide line
-- (used when a profile loads, so old progress is not announced as news).
function AchievementService:evaluate(player: Player, quiet: boolean?): { string }
	local finished = {}
	local profile = self.data:get(player)
	if not profile then
		return finished
	end
	for _, def in Achievements.List do
		if not Achievements.isDone(def, profile) and Achievements.valueOf(def, profile) >= def.goal then
			if self:_complete(player, def, quiet == true) then
				table.insert(finished, def.id)
			end
		end
	end
	self:_submitBoards(player)
	return finished
end

function AchievementService:_complete(player: Player, def, quiet: boolean): boolean
	local newly = false
	local ok = self.data:update(player, function(profile)
		if profile.achievements.done[def.id] == true then
			return
		end
		profile.achievements.done[def.id] = true
		newly = true
	end)
	if not (ok and newly) then
		return false
	end
	-- The title comes only after the achievement is recorded as done
	if def.title and self.cosmetics then
		self.cosmetics:grant(player, def.title, "achievement")
	end
	if player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Toast, { text = `Achievement: {def.name}`, kind = "success" })
		StatusEvent:FireClient(player, Protocol.StatusEvent.Earned, { headline = def.name, sub = def.desc })
	end
	if def.notable and not quiet then
		self:announce(player, `{self:_nameOf(player)} earned the achievement {def.name}.`)
	end
	return true
end

-- Server-wide lines --------------------------------------------------------------------------------

function AchievementService:_nameOf(player: Player): string
	local name = player.DisplayName
	if typeof(name) ~= "string" or name == "" then
		name = player.Name
	end
	return string.sub(name, 1, 40)
end

local function pump()
	if pumping then
		return
	end
	pumping = true
	task.spawn(function()
		while #queue > 0 do
			local wait = lastLine + AchievementService.MomentGap - os.clock()
			if wait > 0 then
				task.wait(wait)
			end
			local text = table.remove(queue, 1)
			lastLine = os.clock()
			StatusEvent:FireAllClients(Protocol.StatusEvent.Moment, { text = text })
		end
		pumping = false
	end)
end

-- One short line to everyone. Returns false when it was dropped (queue full).
-- headline/sub also show the earner a short on-screen moment.
function AchievementService:announce(player: Player, line: string, headline: string?, sub: string?): boolean
	if typeof(line) ~= "string" or line == "" then
		return false
	end
	if headline and player.Parent then
		StatusEvent:FireClient(player, Protocol.StatusEvent.Earned, { headline = headline, sub = sub })
	end
	if #queue >= AchievementService.QueueMax then
		return false
	end
	table.insert(queue, string.sub(line, 1, MAX_LINE))
	pump()
	return true
end

-- Events -----------------------------------------------------------------------------------------

function AchievementService:_onMatchResult(player: Player, result)
	if typeof(result) ~= "table" then
		return
	end
	local won = result.won == true and result.draw ~= true
	local bumps: { [string]: number } = {}
	if result.paid then
		if typeof(result.power) == "string" then
			bumps["used_" .. result.power] = 1
		end
		if won then
			if (result.deaths or 0) == 0 then
				bumps.cleanWins = 1
			end
			if result.cpu then
				bumps.cpuWins = 1
			elseif result.mode == "Duel" then
				bumps.duelWins = 1
			elseif result.mode == "FreeForAll" then
				bumps.ffaWins = 1
			end
		end
		local okSeason, active = pcall(Seasons.getActiveId)
		if okSeason and active then
			bumps.seasonMatches = 1
		end
	end
	if next(bumps) then
		self.data:update(player, function(profile)
			local progress = profile.achievements.progress
			for key, amount in bumps do
				progress[key] = math.min(1e9, (progress[key] or 0) + amount)
			end
		end)
	end
	self:evaluate(player, false)

	-- Win streaks of 5, 10 and 15 (counted by ProgressionService, only for paid wins)
	if won and result.paid and AchievementService.StreakMoments[result.streak] then
		local name = self:_nameOf(player)
		local streak = result.streak
		if streak >= 15 then
			self:announce(player, `{name} has won {streak} matches in a row.`, `{streak} in a row`, "Your best run so far.")
		else
			self:announce(player, `{name} has won {streak} matches in a row.`)
		end
	end
end

-- A match watched from the Lounge or anywhere else counts once per match
function AchievementService:_watchSpectating(player: Player)
	local function check()
		local id = player:GetAttribute(Protocol.Attribute.Spectating)
		if typeof(id) ~= "string" or id == "" then
			return
		end
		local seen = seenMatches[player] or {}
		seenMatches[player] = seen
		if not seen[id] then
			seen[id] = true
			self:count(player, "watched", 1)
		end
	end
	player:GetAttributeChangedSignal(Protocol.Attribute.Spectating):Connect(check)
	check()
end

-- Visiting another player's base counts once per owner per visit session
function AchievementService:_hookBases()
	local bases = self.services.BaseService
	if not bases or typeof(bases.enter) ~= "function" then
		return
	end
	local original = bases.enter
	local achievements = self
	bases.enter = function(service, player, owner)
		local ok = original(service, player, owner)
		if ok and owner and owner ~= player and typeof(owner) == "Instance" then
			local visited = visitedBases[player] or {}
			visitedBases[player] = visited
			if not visited[owner.UserId] then
				visited[owner.UserId] = true
				achievements:count(player, "baseVisits", 1)
			end
		end
		return ok
	end
end

-- A practice round that ran at least this long counts (quitting at once does not)
local MIN_PRACTICE_SECONDS = 15

function AchievementService:_hookPractice()
	local practice = self.services.PracticeService
	if not practice or typeof(practice._finish) ~= "function" then
		return
	end
	local original = practice._finish
	local achievements = self
	practice._finish = function(service, session, outcome, silent)
		local was = session and session.finished
		local result = original(service, session, outcome, silent)
		if session and not was and session.finished and not silent and session.player and session.stats then
			local seconds = session.stats.seconds or 0
			if seconds >= MIN_PRACTICE_SECONDS then
				achievements:count(session.player, "practiceRounds", 1)
				if outcome == "Won" then
					achievements:count(session.player, "practiceWins", 1)
				end
			end
		end
		return result
	end
end

-- Leaderboards: the board module throttles to one write per minute per player
function AchievementService:_submitBoards(player: Player)
	local profile = self.data:get(player)
	local ok, boards = pcall(function()
		return require(script.Parent.Parent.World.Leaderboards)
	end)
	if profile and ok and boards and boards.submit then
		pcall(boards.submit, player.UserId, profile.stats.wins, profile.stats.bestStreak, self.data:isPersistent(player))
	end
end

-- Used by the Locker: the number a player has toward an achievement
function AchievementService:progressOf(player: Player, id: string): number
	local def = Achievements.get(id)
	local profile = self.data:get(player)
	return if def and profile then Achievements.valueOf(def, profile) else 0
end

return AchievementService
