-- Matchmaking and match flow. Players queue for a mode; when enough are
-- waiting, they're moved into an arena, counted down, and fight until time runs
-- out. Knockouts score (+1 for the fighter who earned it, -1 for the one knocked
-- out). The rules live in Shared/Match/MatchFlow; this service connects them
-- to players, arenas and the network.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local MatchConfig = require(ReplicatedStorage.Shared.Config.Match)
local MatchFlow = require(ReplicatedStorage.Shared.Match.MatchFlow)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchRequest = Remotes:WaitForChild("MatchRequest") :: RemoteEvent
local MatchEvent = Remotes:WaitForChild("MatchEvent") :: RemoteEvent

local Action = Protocol.MatchAction
local Event = Protocol.MatchEvent

local MatchService = {}

local UPDATE_INTERVAL = 0.1

type Participant = {
	id: string,
	name: string,
	player: Player?,
	dummy: any?,
	-- Set when the player went back to the lobby early from the results screen
	returned: boolean,
	-- Where this participant was last placed (held there during the countdown)
	spawn: CFrame?,
}

type Match = {
	id: string,
	modeName: string,
	mode: any,
	flow: MatchFlow.Flow,
	arena: any,
	participants: { Participant },
	byId: { [string]: Participant },
	-- When the fight itself began (after the countdown)
	fightStartedAt: number?,
	-- The CPU opponent's settings, for CPU practice (and rematches of it)
	cpu: any?,
	-- Players watching, their free predictions, and rematch votes
	spectators: { [Player]: boolean },
	predictions: { [Player]: string },
	rematch: { [Player]: boolean },
}

local queues: { [string]: { Player } } = {}
local queueFilledAt: { [string]: number? } = {}
local matches: { [string]: Match } = {}
local matchOfFighter: { [string]: Match } = {}

local startedListeners: { (Match) -> () } = {}
local finishedListeners: { (Match, any) -> () } = {}

-- Predictions are only taken before the fight is this many seconds old
local PREDICTION_WINDOW = 20

local function now(): number
	return workspace:GetServerTimeNow()
end

local function playerId(player: Player): string
	return "Player:" .. player.UserId
end

function MatchService:Init(services)
	self.services = services
	self.characters = services.CharacterService
	self.arenas = services.ArenaService
	self.dummies = services.DummyService
	self.antiExploit = services.AntiExploitService
	for modeName in MatchConfig.Modes do
		queues[modeName] = {}
	end
end

function MatchService:Start()
	MatchRequest.OnServerEvent:Connect(function(player, action, argument, options)
		if not self.antiExploit:allow(player, "Match") then
			return
		end
		if typeof(action) ~= "string" then
			return
		end
		self:_onRequest(player, action, argument, options)
	end)

	self.characters:setSpawnResolver(function(player)
		local match = matchOfFighter[playerId(player)]
		local participant = match and match.byId[playerId(player)]
		if match and participant and match.flow.phase ~= "Ended" and not participant.returned then
			local destination = self:_spawnFor(match, playerId(player))
			participant.spawn = destination
			return destination
		end
		return nil
	end)

	self.characters:onSpawned(function(fighter)
		local match = matchOfFighter[fighter.id]
		if not match or match.byId[fighter.id].returned then
			return
		end
		self.characters:restore(fighter, Combat.SpawnProtection)
		if match.flow.phase == "Countdown" or match.flow.phase == "Results" then
			self.characters:setFrozen(fighter, true)
		end
	end)

	self.characters:onKnockout(function(victim, credited)
		self:_onKnockout(victim, credited)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_leaveQueues(player)
		for _, match in matches do
			match.spectators[player] = nil
			match.predictions[player] = nil
			match.rematch[player] = nil
		end
		local match = matchOfFighter[playerId(player)]
		if match then
			self:_participantLeft(match, playerId(player))
		end
	end)

	task.spawn(function()
		while true do
			task.wait(UPDATE_INTERVAL)
			self:_update()
		end
	end)
end

-- Rules other services ask about -------------------------------------------------

function MatchService:getMatchOf(fighter): Match?
	return matchOfFighter[fighter.id]
end

-- Can this fighter use combat actions right now?
function MatchService:isCombatAllowed(fighter): boolean
	local match = matchOfFighter[fighter.id]
	if match then
		return MatchFlow.isFighting(match.flow)
	end
	-- Outside matches you can practise on training dummies
	return true
end

-- Can `attacker` hurt `target`? Only opponents in the same running match, or
-- training dummies while you're not in a match.
function MatchService:canDamage(attacker, target): boolean
	local attackerMatch = matchOfFighter[attacker.id]
	local targetMatch = matchOfFighter[target.id]
	if attackerMatch or targetMatch then
		return attackerMatch == targetMatch and MatchFlow.isFighting(attackerMatch.flow)
	end
	return target.trainingDummy
end

-- callback(match) when a match's fight begins (after the countdown)
function MatchService:onStarted(callback: (Match) -> ())
	table.insert(startedListeners, callback)
end

-- callback(match, result) when a match finishes (results are shown)
function MatchService:onFinished(callback: (Match, any) -> ())
	table.insert(finishedListeners, callback)
end

function MatchService:getMatch(matchId: string): Match?
	return matches[matchId]
end

-- Ends every running match at once (owner panel)
function MatchService:endAll()
	for _, match in matches do
		self:_handle(match, MatchFlow.abort(match.flow))
	end
end

-- Requests -------------------------------------------------------------------------

function MatchService:_onRequest(player: Player, action: string, argument: any, options: any)
	local inMatch = matchOfFighter[playerId(player)]
	if action == Action.Queue then
		if typeof(argument) ~= "string" or MatchConfig.Modes[argument] == nil then
			return
		end
		if inMatch then
			self:_notice(player, "You're already in a match.")
			return
		end
		self:_stopSpectating(player)
		-- Premium powers being tried out can't go into PvP queues
		local powers = self.services.PowerService
		if powers then
			local allowed, reason = powers:queueCheck(player, argument)
			if not allowed then
				self:_notice(player, reason or "You can't queue with that power.")
				return
			end
		end
		if MatchConfig.Modes[argument].Solo then
			self:_leaveQueues(player)
			if not self:_startMatch(argument, { player }, self:_cpuOptions(options)) then
				self:_notice(player, "All arenas are busy. Try again in a moment.")
			end
		else
			self:_joinQueue(player, argument)
		end
	elseif action == Action.LeaveQueue then
		self:_leaveQueues(player)
	elseif action == Action.Travel then
		if inMatch then
			return
		end
		local fighter = self.characters:getByPlayer(player)
		if not fighter or not self.characters:isAlive(fighter) then
			return
		end
		if argument == "Lobby" then
			self.characters:teleport(fighter, self.arenas:lobbySpawn())
		elseif argument == "Training" then
			self.characters:teleport(fighter, self.arenas:trainingSpawn())
		end
	elseif action == Action.ReturnToLobby then
		if inMatch and inMatch.flow.phase == "Results" then
			self:_sendHome(inMatch, inMatch.byId[playerId(player)])
		end
	elseif action == Action.Rematch then
		if inMatch and inMatch.flow.phase == "Results" and inMatch.byId[playerId(player)] then
			inMatch.rematch[player] = true
			local votes, needed = self:_rematchCount(inMatch)
			self:_broadcast(inMatch, Event.Rematch, { votes = votes, needed = needed })
		end
	elseif action == Action.ListMatches then
		MatchEvent:FireClient(player, Event.Matches, self:_watchable())
	elseif action == Action.Spectate then
		if inMatch then
			self:_notice(player, "You can't watch while you're in a match.")
			return
		end
		local match = if typeof(argument) == "string" then matches[argument] else nil
		if not match or match.flow.phase == "Ended" then
			self:_notice(player, "That match has already ended.")
			return
		end
		self:_stopSpectating(player)
		match.spectators[player] = true
		player:SetAttribute(Protocol.Attribute.Spectating, match.id)
		local fighters = {}
		for _, participant in match.participants do
			local fighter = self.characters:getById(participant.id)
			if fighter and not participant.returned then
				table.insert(fighters, fighter.model)
			end
		end
		MatchEvent:FireClient(player, Event.Spectating, { matchId = match.id, fighters = fighters, mode = match.mode.DisplayName })
		self:_broadcastState(match)
	elseif action == Action.StopSpectating then
		self:_stopSpectating(player)
	elseif action == Action.Predict then
		-- A free guess at the winner: no stakes, a small reward if right
		local match = if typeof(argument) == "string" then matches[argument] else nil
		if not match or not match.spectators[player] or match.predictions[player] or typeof(options) ~= "string" or not match.byId[options] then
			return
		end
		local early = match.flow.phase == "Countdown" or (match.fightStartedAt ~= nil and now() - match.fightStartedAt <= PREDICTION_WINDOW and match.flow.phase == "Active")
		if early then
			match.predictions[player] = options
			self:_notice(player, `Prediction locked in: {self:_nameOf(match, options)}.`)
		else
			self:_notice(player, "Predictions close early in the fight.")
		end
	end
end

-- Watching ---------------------------------------------------------------------------

function MatchService:_stopSpectating(player: Player)
	for _, match in matches do
		if match.spectators[player] then
			match.spectators[player] = nil
		end
	end
	if player:GetAttribute(Protocol.Attribute.Spectating) ~= nil then
		player:SetAttribute(Protocol.Attribute.Spectating, nil)
		if player.Parent then
			MatchEvent:FireClient(player, Event.Spectating, nil)
		end
	end
end

-- Matches other players can watch (with real players in them)
function MatchService:_watchable()
	local list = {}
	for _, match in matches do
		if match.flow.phase ~= "Ended" then
			local names = {}
			local humans = 0
			for _, participant in match.participants do
				if not participant.returned then
					table.insert(names, participant.name)
					if participant.player then
						humans += 1
					end
				end
			end
			if humans > 0 then
				table.insert(list, {
					id = match.id,
					mode = match.mode.DisplayName,
					arena = match.arena.name,
					phase = match.flow.phase,
					names = names,
					watchers = (function()
						local count = 0
						for _ in match.spectators do
							count += 1
						end
						return count
					end)(),
				})
			end
		end
	end
	return list
end

-- Rematches --------------------------------------------------------------------------

-- How many players voted, and how many are needed (everyone still there)
function MatchService:_rematchCount(match: Match): (number, number)
	local votes, needed = 0, 0
	for _, participant in match.participants do
		local player = participant.player
		if player and not participant.returned and player.Parent then
			needed += 1
			if match.rematch[player] then
				votes += 1
			end
		end
	end
	return votes, needed
end

function MatchService:_notice(player: Player, text: string)
	MatchEvent:FireClient(player, Event.Notice, { text = text })
end

-- Queues ---------------------------------------------------------------------------

function MatchService:_sendQueueStatus(modeName: string)
	local mode = MatchConfig.Modes[modeName]
	local queue = queues[modeName]
	local filledAt = queueFilledAt[modeName]
	for _, player in queue do
		MatchEvent:FireClient(player, Event.Queue, {
			mode = modeName,
			displayName = mode.DisplayName,
			queued = #queue,
			needed = mode.MinPlayers,
			max = mode.MaxPlayers,
			startsAt = if filledAt and mode.QueueFillDelay then filledAt + mode.QueueFillDelay else nil,
		})
	end
end

function MatchService:_joinQueue(player: Player, modeName: string)
	local queue = queues[modeName]
	if table.find(queue, player) then
		return
	end
	self:_leaveQueues(player)
	table.insert(queue, player)
	self:_sendQueueStatus(modeName)
	self:_checkQueue(modeName)
end

function MatchService:_leaveQueues(player: Player)
	for modeName, queue in queues do
		local index = table.find(queue, player)
		if index then
			table.remove(queue, index)
			MatchEvent:FireClient(player, Event.Queue, nil)
			if #queue < MatchConfig.Modes[modeName].MinPlayers then
				queueFilledAt[modeName] = nil
			end
			self:_sendQueueStatus(modeName)
		end
	end
end

function MatchService:_checkQueue(modeName: string)
	local mode = MatchConfig.Modes[modeName]
	local queue = queues[modeName]
	-- Drop anyone who left the game
	for index = #queue, 1, -1 do
		if queue[index].Parent == nil then
			table.remove(queue, index)
		end
	end
	if #queue < mode.MinPlayers then
		queueFilledAt[modeName] = nil
		return
	end
	local ready = #queue >= mode.MaxPlayers
	if not ready then
		local filledAt = queueFilledAt[modeName]
		if not filledAt then
			queueFilledAt[modeName] = now()
			self:_sendQueueStatus(modeName)
			return
		end
		ready = now() - filledAt >= (mode.QueueFillDelay or 0)
	end
	if not ready then
		return
	end
	local players = {}
	for index = 1, math.min(#queue, mode.MaxPlayers) do
		table.insert(players, queue[index])
	end
	if self:_startMatch(modeName, players) then
		queueFilledAt[modeName] = nil
		self:_sendQueueStatus(modeName)
	end
end

-- Match lifecycle ------------------------------------------------------------------

-- What a solo player asked for in CPU Practice: which power the CPU plays, at
-- what degree and difficulty (anything unknown falls back to a sensible choice)
function MatchService:_cpuOptions(options: any)
	local cpu = { power = "Random", degree = 1, difficulty = "Normal" }
	if typeof(options) == "table" then
		if typeof(options.cpuPower) == "string" and (options.cpuPower == "Random" or Powers.get(options.cpuPower)) then
			cpu.power = options.cpuPower
		end
		if typeof(options.cpuDegree) == "number" and options.cpuDegree >= 1 and options.cpuDegree <= 3 then
			cpu.degree = math.floor(options.cpuDegree)
		end
		local difficulties = self.services.CpuService and self.services.CpuService.Difficulties
		if typeof(options.cpuDifficulty) == "string" and difficulties and difficulties[options.cpuDifficulty] then
			cpu.difficulty = options.cpuDifficulty
		end
	end
	if cpu.power == "Random" then
		local choices = {}
		for _, powerId in Powers.Order do
			if Powers.get(powerId) then
				table.insert(choices, powerId)
			end
		end
		cpu.power = choices[math.random(1, #choices)]
	end
	return cpu
end

function MatchService:_startMatch(modeName: string, players: { Player }, cpu: { power: string, degree: number, difficulty: string }?): boolean
	local mode = MatchConfig.Modes[modeName]
	local arena = self.arenas:reserve()
	if not arena then
		return false
	end

	local match: Match = {
		id = HttpService:GenerateGUID(false),
		modeName = modeName,
		mode = mode,
		flow = nil :: any,
		arena = arena,
		participants = {},
		byId = {},
		fightStartedAt = nil,
		cpu = cpu,
		spectators = {},
		predictions = {},
		rematch = {},
	}
	local function add(participant: Participant)
		table.insert(match.participants, participant)
		match.byId[participant.id] = participant
		matchOfFighter[participant.id] = match
	end

	for _, player in players do
		local queue = queues[modeName]
		local index = table.find(queue, player)
		if index then
			table.remove(queue, index)
		end
		MatchEvent:FireClient(player, Event.Queue, nil)
		player:SetAttribute(Protocol.Attribute.MatchId, match.id)
		add({ id = playerId(player), name = player.DisplayName, player = player, returned = false })
		-- Power, degree and loadout stay exactly as they are until the match ends
		if self.services.PowerService then
			self.services.PowerService:lock(player)
		end
	end

	-- Reserve dummy ids first so the match rules exist before anything can yield
	-- (creating a dummy waits on Roblox; nothing may see a match without rules)
	local dummyCount = mode.Dummies or 0
	local dummyParticipants: { Participant } = {}
	local cpuDef = cpu and Powers.get(cpu.power)
	for _ = 1, dummyCount do
		local name = if cpuDef and cpu then `{cpuDef.name} CPU ({cpu.difficulty})` else "Sparring Dummy"
		local participant: Participant = { id = self.dummies:reserveId(), name = name, returned = false }
		table.insert(dummyParticipants, participant)
		add(participant)
	end
	local ids = {}
	for _, participant in match.participants do
		table.insert(ids, participant.id)
	end
	match.flow = MatchFlow.new(mode, ids, now())
	matches[match.id] = match

	-- Bring each player in: full health, clean state, frozen until the countdown ends
	for index, participant in match.participants do
		if participant.player then
			local fighter = self.characters:getByPlayer(participant.player)
			if fighter and self.characters:isAlive(fighter) then
				participant.spawn = arena.spawns[(index - 1) % #arena.spawns + 1]
				self.characters:teleport(fighter, participant.spawn :: CFrame)
				self.characters:restore(fighter)
				self.characters:setFrozen(fighter, true)
			end
		end
	end

	self:_broadcastState(match)

	for index, participant in dummyParticipants do
		local startIndex = #players + index
		participant.dummy = self.dummies:spawn(if cpu then "Cpu" else "Sparring", {
			id = participant.id,
			spawnAt = function()
				return self:_spawnFor(match, participant.id, startIndex)
			end,
			parent = match.arena.model,
			cpu = cpu,
		})
		-- The match may have ended while the dummy was being created
		if not matches[match.id] then
			self.dummies:despawn(participant.dummy)
		end
	end
	return true
end

-- Where a participant should (re)spawn: their own corner at the start,
-- otherwise the corner farthest from everyone else
function MatchService:_spawnFor(match: Match, id: string, startIndex: number?): CFrame
	if startIndex and match.flow.phase == "Countdown" then
		return match.arena.spawns[(startIndex - 1) % #match.arena.spawns + 1]
	end
	local others = {}
	for _, participant in match.participants do
		if participant.id ~= id and not participant.returned and matchOfFighter[participant.id] == match then
			local fighter = self.characters:getById(participant.id)
			if fighter and self.characters:isAlive(fighter) then
				table.insert(others, fighter.root.Position)
			end
		end
	end
	return self.arenas:pickSpawn(match.arena, others)
end

function MatchService:_update()
	for modeName in queues do
		if #queues[modeName] > 0 then
			self:_checkQueue(modeName)
		end
	end

	local time = now()
	for _, match in matches do
		self:_handle(match, MatchFlow.tick(match.flow, time))
		if matches[match.id] and match.flow.phase == "Countdown" then
			self:_holdAtSpawns(match, time)
		end
		if matches[match.id] and MatchFlow.isFighting(match.flow) then
			-- Falling out of the arena is a knockout (credited to whoever hit you last).
			-- Skipped right after a respawn or teleport, while positions settle.
			for _, participant in match.participants do
				local fighter = self.characters:getById(participant.id)
				if
					fighter
					and not participant.returned
					and matchOfFighter[participant.id] == match
					and self.characters:isAlive(fighter)
					and time >= fighter.state.protectedUntil
					and time - fighter.teleportedAt > 1
					and self.arenas:isOutOfBounds(match.arena, fighter.root.Position)
				then
					fighter.humanoid.Health = 0
				end
			end
		end
	end
end

-- During the countdown everyone stays on their spawn. The freeze is applied on
-- each player's own client, so the server also puts back anyone who wanders off.
local HOLD_RANGE = 4

function MatchService:_holdAtSpawns(match: Match, time: number)
	for _, participant in match.participants do
		local spawn = participant.spawn
		if participant.player and spawn and not participant.returned then
			local fighter = self.characters:getById(participant.id)
			if
				fighter
				and self.characters:isAlive(fighter)
				and time - fighter.teleportedAt > 0.5
				and Vector3.new(fighter.root.Position.X - spawn.Position.X, 0, fighter.root.Position.Z - spawn.Position.Z).Magnitude > HOLD_RANGE
			then
				self.characters:teleport(fighter, spawn)
			end
		end
	end
end

function MatchService:_handle(match: Match, events: { MatchFlow.Event })
	for _, event in events do
		if event.kind == "Begin" then
			match.fightStartedAt = now()
			self:_forEachFighter(match, function(fighter)
				self.characters:setFrozen(fighter, false)
			end)
			self:_broadcastState(match)
			for _, listener in startedListeners do
				task.spawn(listener, match)
			end
		elseif event.kind == "SuddenDeath" then
			self:_broadcastState(match)
			self:_broadcast(match, Event.Notice, { text = "SUDDEN DEATH! Next knockout wins." })
		elseif event.kind == "Knockout" then
			self:_broadcast(match, Event.Knockout, {
				victim = self:_nameOf(match, event.victim),
				credited = if event.credited then self:_nameOf(match, event.credited) else nil,
			})
			self:_broadcastState(match)
		elseif event.kind == "Finish" then
			self:_forEachFighter(match, function(fighter)
				self.characters:setFrozen(fighter, true)
			end)
			self:_broadcast(match, Event.Results, self:_results(match, event.result))
			self:_broadcastState(match)
			for _, listener in finishedListeners do
				task.spawn(listener, match, event.result)
			end
		elseif event.kind == "Ended" then
			self:_cleanup(match)
		end
	end
end

function MatchService:_onKnockout(victim, credited)
	local match = matchOfFighter[victim.id]
	if not match then
		return
	end
	local creditedId = if credited and match.byId[credited.id] then credited.id else nil
	self:_handle(match, MatchFlow.knockout(match.flow, victim.id, creditedId, now()))
end

function MatchService:_participantLeft(match: Match, id: string)
	local participant = match.byId[id]
	if not participant then
		return
	end
	matchOfFighter[id] = nil
	participant.returned = true
	self:_handle(match, MatchFlow.leave(match.flow, id, now()))
	if not matches[match.id] then
		return
	end
	-- No real players left: nothing to show, so end it now
	local anyPlayers = false
	for _, other in match.participants do
		if other.player and not other.returned then
			anyPlayers = true
		end
	end
	if not anyPlayers then
		self:_handle(match, MatchFlow.abort(match.flow))
	else
		self:_broadcastState(match)
	end
end

-- Sends one participant back to the lobby and takes them out of the match
function MatchService:_sendHome(match: Match, participant: Participant?)
	if not participant or participant.returned then
		return
	end
	participant.returned = true
	matchOfFighter[participant.id] = nil
	local player = participant.player
	if not player then
		return
	end
	if self.services.PowerService then
		self.services.PowerService:unlock(player)
	end
	if player.Parent then
		player:SetAttribute(Protocol.Attribute.MatchId, nil)
		MatchEvent:FireClient(player, Event.Ended, nil)
	end
	local fighter = self.characters:getByPlayer(player)
	if fighter then
		self.characters:restore(fighter)
		if self.characters:isAlive(fighter) then
			self.characters:teleport(fighter, self.arenas:lobbySpawn())
		end
	end
end

function MatchService:_cleanup(match: Match)
	if not matches[match.id] then
		return
	end
	-- Everyone still here voted for a rematch: same mode, same players, straight away
	local votes, needed = self:_rematchCount(match)
	local again: { Player }? = nil
	if needed > 0 and votes == needed then
		again = {}
		for player in match.rematch do
			if player.Parent then
				table.insert(again :: { Player }, player)
			end
		end
	end
	for player in match.spectators do
		self:_stopSpectating(player)
	end
	matches[match.id] = nil
	for _, participant in match.participants do
		if participant.dummy then
			self.dummies:despawn(participant.dummy)
			matchOfFighter[participant.id] = nil
			participant.returned = true
		else
			self:_sendHome(match, participant)
		end
	end
	self.arenas:release(match.arena)
	if again and #again >= match.mode.MinPlayers then
		task.defer(function()
			for _, player in again :: { Player } do
				if not player.Parent or matchOfFighter[playerId(player)] then
					return
				end
			end
			self:_startMatch(match.modeName, again :: { Player }, match.cpu)
		end)
	end
end

-- Messages -------------------------------------------------------------------------

function MatchService:_forEachFighter(match: Match, callback: (any) -> ())
	for _, participant in match.participants do
		if not participant.returned then
			local fighter = self.characters:getById(participant.id)
			if fighter then
				callback(fighter)
			end
		end
	end
end

function MatchService:_nameOf(match: Match, id: string): string
	local participant = match.byId[id]
	return if participant then participant.name else "?"
end

function MatchService:_broadcast(match: Match, kind: string, data: any)
	for _, participant in match.participants do
		if participant.player and not participant.returned and participant.player.Parent then
			MatchEvent:FireClient(participant.player, kind, data)
		end
	end
	-- Watchers see the same scoreboard, feed and results (never anything a fighter can't see)
	if kind ~= Event.Rematch then
		for player in match.spectators do
			if player.Parent then
				MatchEvent:FireClient(player, kind, data)
			end
		end
	end
end

function MatchService:_results(match: Match, result: MatchFlow.Result)
	local winners = {}
	for _, id in result.winners do
		table.insert(winners, self:_nameOf(match, id))
	end
	local ranking = {}
	for _, entry in result.ranking do
		table.insert(ranking, {
			id = entry.id,
			name = self:_nameOf(match, entry.id),
			score = entry.score,
			knockouts = entry.knockouts,
			deaths = entry.deaths,
			left = entry.left,
		})
	end
	return {
		reason = result.reason,
		draw = result.draw,
		winners = winners,
		winnerIds = result.winners,
		ranking = ranking,
		returnsAt = match.flow.phaseEndsAt,
	}
end

function MatchService:_broadcastState(match: Match)
	local flow = match.flow
	local participants = {}
	for _, participant in match.participants do
		local entry = flow.board.entries[participant.id]
		table.insert(participants, {
			id = participant.id,
			name = participant.name,
			score = if entry then entry.score else 0,
			knockouts = if entry then entry.knockouts else 0,
			left = if entry then entry.left else false,
			npc = participant.dummy ~= nil,
		})
	end
	self:_broadcast(match, Event.State, {
		id = match.id,
		mode = match.modeName,
		modeName = match.mode.DisplayName,
		arena = match.arena.name,
		phase = flow.phase,
		phaseEndsAt = flow.phaseEndsAt,
		participants = participants,
	})
end

return MatchService
