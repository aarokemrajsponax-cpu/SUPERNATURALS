-- Records the end of every running match so its players (and anyone watching)
-- can rewatch the final moments, and keeps the real numbers the results screen
-- shows: damage, hits, combos, blocks, parries, perfect defenses, grabs,
-- knockouts and ultimates. Fighter positions are sampled at Config/Replay.Rate
-- into a ring buffer that only holds the last few seconds; key events (hits,
-- knockouts, abilities, defenses) are kept alongside with server times. When a
-- match finishes it sends MatchEvent.Highlight once and frees the recording.
-- Nothing a spectator shouldn't see is ever sent: while a fighter is concealed
-- or invisible its samples repeat the last spot where it could be seen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local MatchFlow = require(ReplicatedStorage.Shared.Match.MatchFlow)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local ReplayConfig = require(ReplicatedStorage.Shared.Config.Replay)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchEvent = Remotes:WaitForChild("MatchEvent") :: RemoteEvent
local ProgressRequest = Remotes:WaitForChild("ProgressRequest") :: RemoteEvent

local Attribute = Protocol.Attribute
local Flags = ReplayConfig.Flags

local ReplayService = {}

-- Numbers per sample: x, y, z, yaw, flags
local STRIDE = 5
local NEUTRAL = Color3.fromRGB(201, 164, 92)
-- Events that stay when the event list is over its cap
local KEEP = { Knockout = true, Ultimate = true }

export type Stats = {
	damageDealt: number,
	damageTaken: number,
	hitsLanded: number,
	hitsTaken: number,
	longestCombo: number,
	blocks: number,
	parries: number,
	perfects: number,
	goods: number,
	escapes: number,
	timingBars: number,
	timingPerfect: number,
	guardBreaks: number,
	grabsLanded: number,
	grabsSuffered: number,
	grabDamageTaken: number,
	knockouts: number,
	deaths: number,
	ultimates: number,
	ultimateReady: boolean,
}

type Track = {
	index: number,
	id: string,
	name: string,
	userId: number?,
	npc: boolean,
	power: string?,
	color: Color3,
	stats: Stats,
	-- The ring buffer: STRIDE numbers per slot
	data: { number },
	lastVisible: CFrame?,
	-- victim id -> the combo this fighter is building on them
	combos: { [string]: { count: number, at: number } },
}

type Event = { [string]: any }

type Recording = {
	matchId: string,
	match: any,
	startedAt: number,
	tracks: { Track },
	byId: { [string]: Track },
	times: { number },
	head: number,
	count: number,
	capacity: number,
	events: { Event },
	summary: { Event },
	phase: string,
	firstHit: boolean,
	finishedAt: number?,
	result: any?,
	recipients: { Player }?,
}

-- matchId -> its recording (only running matches)
local recordings: { [string]: Recording } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function round(value: number, step: number): number
	return math.floor(value / step + 0.5) * step
end

local function hasTag(tags: any, tag: string): boolean
	if typeof(tags) ~= "table" then
		return false
	end
	return table.find(tags, tag) ~= nil or tags[tag] == true
end

local function newStats(): Stats
	return {
		damageDealt = 0,
		damageTaken = 0,
		hitsLanded = 0,
		hitsTaken = 0,
		longestCombo = 0,
		blocks = 0,
		parries = 0,
		perfects = 0,
		goods = 0,
		escapes = 0,
		timingBars = 0,
		timingPerfect = 0,
		guardBreaks = 0,
		grabsLanded = 0,
		grabsSuffered = 0,
		grabDamageTaken = 0,
		knockouts = 0,
		deaths = 0,
		ultimates = 0,
		ultimateReady = false,
	}
end

-- The one tip the results screen shows for these numbers, or nil when no rule
-- fits. Rules only say what the numbers show (Config/Replay.Tips).
function ReplayService.tipFor(stats: Stats?): string?
	if typeof(stats) ~= "table" then
		return nil
	end
	local rules = ReplayConfig.Tips
	local checks = {
		Grabs = function(rule)
			return stats.grabsSuffered >= rule.minGrabs
				and stats.damageTaken > 0
				and stats.grabDamageTaken / stats.damageTaken >= rule.damageShare
		end,
		Timing = function(rule)
			return stats.timingBars >= rule.minBars and stats.timingPerfect / stats.timingBars < rule.perfectShare
		end,
		GuardBreaks = function(rule)
			return stats.guardBreaks >= rule.minBreaks
		end,
		NoBlocks = function(rule)
			return stats.hitsTaken >= rule.minHitsTaken and stats.blocks + stats.parries == 0
		end,
		UnusedUltimate = function()
			return stats.ultimateReady and stats.ultimates == 0
		end,
		NoCombos = function(rule)
			return stats.hitsLanded >= rule.minHits and stats.longestCombo <= 1
		end,
	}
	for _, name in ReplayConfig.TipOrder do
		local rule, check = rules[name], checks[name]
		if rule and check and check(rule) then
			return rule.text
		end
	end
	return nil
end

function ReplayService:Init(services)
	self.services = services
	self.characters = services.CharacterService
	self.statuses = services.StatusService
	self.data = services.DataService
	self.antiExploit = services.AntiExploitService
end

function ReplayService:Start()
	local matchService = self.services.MatchService
	self.matches = matchService
	matchService:onStarted(function(match)
		self:_begin(match)
	end)
	matchService:onFinished(function(match, result)
		self:_finish(match, result)
	end)

	self.services.CombatService:onHit(function(attacker, target, outcome, opts)
		self:_onHit(attacker, target, outcome, opts or {})
	end)
	self.services.AbilityService:onUsed(function(fighter, abilityId, def, basic)
		self:_onAbility(fighter, abilityId, def, basic)
	end)
	self.services.DefenseService:onResult(function(fighter, kind, result)
		self:_onDefense(fighter, kind, result)
	end)
	self.characters:onKnockout(function(victim, credited)
		self:_onKnockout(victim, credited)
	end)

	-- The one-time "watch the final moments" hint, remembered with the profile
	ProgressRequest.OnServerEvent:Connect(function(player, action, argument)
		if action ~= Protocol.ProgressAction.SeenHint or typeof(argument) ~= "string" then
			return
		end
		if not self.antiExploit:allow(player, "Progress") or not table.find(self:_hintIds(), argument) then
			return
		end
		self.data:update(player, function(profile)
			profile.tutorial.done[argument] = true
		end)
	end)

	task.spawn(function()
		local interval = 1 / ReplayConfig.Rate
		while true do
			task.wait(interval)
			self:_tick()
		end
	end)
end

-- Public helpers ------------------------------------------------------------------------

-- The live numbers for a fighter in a running match (nil when not recorded)
function ReplayService:statsOf(fighterId: string): Stats?
	for _, recording in recordings do
		local track = recording.byId[fighterId]
		if track then
			return track.stats
		end
	end
	return nil
end

-- How many matches are being recorded right now (tests check nothing leaks)
function ReplayService:recordingCount(): number
	local count = 0
	for _ in recordings do
		count += 1
	end
	return count
end

function ReplayService:_hintIds(): { string }
	local list = {}
	for _, id in ReplayConfig.Hints do
		table.insert(list, id)
	end
	return list
end

-- Recording -------------------------------------------------------------------------------

function ReplayService:_begin(match)
	if recordings[match.id] then
		return
	end
	local capacity = math.ceil((ReplayConfig.Seconds + ReplayConfig.TailSeconds) * ReplayConfig.Rate) + 1
	local recording: Recording = {
		matchId = match.id,
		match = match,
		startedAt = match.fightStartedAt or now(),
		tracks = {},
		byId = {},
		times = table.create(capacity, 0),
		head = 1,
		count = 0,
		capacity = capacity,
		events = {},
		summary = {},
		phase = match.flow.phase,
		firstHit = false,
	}
	for _, participant in match.participants do
		if not participant.returned and #recording.tracks < ReplayConfig.MaxFighters then
			local fighter = self.characters:getById(participant.id)
			local powerId = (fighter and fighter.power and fighter.power.id) or (participant.dummy and match.cpu and match.cpu.power) or nil
			local def = powerId and Powers.get(powerId)
			local track: Track = {
				index = #recording.tracks + 1,
				id = participant.id,
				name = participant.name,
				userId = if participant.player then participant.player.UserId else nil,
				npc = participant.player == nil,
				power = powerId,
				color = if def and def.colors then def.colors.primary else NEUTRAL,
				stats = newStats(),
				data = table.create(capacity * STRIDE, 0),
				lastVisible = nil,
				combos = {},
			}
			table.insert(recording.tracks, track)
			recording.byId[participant.id] = track
		end
	end
	recordings[match.id] = recording
	self:_sample(recording, now())
end

-- Where a fighter is and what it's doing, for one slot of the ring buffer
function ReplayService:_sampleTrack(recording: Recording, track: Track, slot: number, time: number)
	local fighter = self.characters:getById(track.id)
	local flags = 0
	local cframe: CFrame? = nil
	local present = fighter ~= nil and fighter.root ~= nil and fighter.root.Parent ~= nil and fighter.model.Parent ~= nil
	if present and not self.characters:isAlive(fighter) then
		-- Knocked out: the body stays where it fell until the respawn
		flags += Flags.Out
	end
	if present then
		local model = fighter.model
		local hidden = self.statuses ~= nil and self.statuses:has(fighter, "Concealed")
		if fighter.player and fighter.player:GetAttribute(Attribute.Invisible) == true then
			hidden = true
		end
		if hidden then
			flags += Flags.Hidden
			cframe = track.lastVisible
		else
			cframe = fighter.root.CFrame
			track.lastVisible = cframe
		end
		if model:GetAttribute(Attribute.Blocking) == true then
			flags += Flags.Blocking
		end
		if (model:GetAttribute(Attribute.DownedUntil) or 0) > time then
			flags += Flags.Downed
		end
		if model:GetAttribute(Attribute.Airborne) == true then
			flags += Flags.Airborne
		end
		if (model:GetAttribute(Attribute.BusyUntil) or 0) > time then
			flags += Flags.Attacking
		end
		if (model:GetAttribute(Attribute.Ultimate) or 0) >= 100 then
			track.stats.ultimateReady = true
		end
	end
	if not cframe then
		-- Respawning, or never seen: hold the last visible spot, not drawn
		flags = bit32.bor(flags, Flags.Absent)
		cframe = track.lastVisible or CFrame.new()
	end
	local position = (cframe :: CFrame).Position
	local look = (cframe :: CFrame).LookVector
	local base = (slot - 1) * STRIDE
	local data = track.data
	local step = ReplayConfig.Precision
	data[base + 1] = round(position.X, step)
	data[base + 2] = round(position.Y, step)
	data[base + 3] = round(position.Z, step)
	data[base + 4] = round(math.atan2(-look.X, -look.Z), 0.001)
	data[base + 5] = flags
	local _ = recording
end

function ReplayService:_sample(recording: Recording, time: number)
	local slot = recording.head
	recording.times[slot] = time
	for _, track in recording.tracks do
		self:_sampleTrack(recording, track, slot, time)
	end
	recording.head = slot % recording.capacity + 1
	recording.count = math.min(recording.count + 1, recording.capacity)
end

function ReplayService:_tick()
	local time = now()
	for matchId, recording in recordings do
		local live = self.matches:getMatch(matchId)
		if recording.finishedAt then
			-- Keep the tail, then send once; a match cleaned up early sends straight away
			if not live or time >= recording.finishedAt + ReplayConfig.TailSeconds then
				self:_send(recording)
				self:_free(matchId)
				continue
			end
		elseif not live then
			-- Ended without results (aborted): nothing to show
			self:_free(matchId)
			continue
		end
		self:_sample(recording, time)
		local phase = recording.match.flow.phase
		if phase ~= recording.phase then
			recording.phase = phase
			if phase == "SuddenDeath" then
				self:_summarize(recording, "SuddenDeath", "Sudden death. The next knockout wins.", time)
			end
		end
	end
end

function ReplayService:_free(matchId: string)
	local recording = recordings[matchId]
	if not recording then
		return
	end
	recordings[matchId] = nil
	for _, track in recording.tracks do
		table.clear(track.data)
		table.clear(track.combos)
	end
	table.clear(recording.tracks)
	table.clear(recording.byId)
	table.clear(recording.events)
	table.clear(recording.summary)
	recording.recipients = nil
	recording.match = nil
end

-- Events --------------------------------------------------------------------------------

-- Is this recording still taking events? During the fight, and for a moment
-- after the finish so the deciding blow is never lost
local function accepting(recording: Recording, time: number): boolean
	if recording.finishedAt then
		return time - recording.finishedAt <= ReplayConfig.FinishGrace
	end
	return MatchFlow.isFighting(recording.match.flow)
end

-- The recording and both tracks when both fighters are in the same recorded match
function ReplayService:_pair(a, b): (Recording?, Track?, Track?)
	local match = a and self.matches:getMatchOf(a)
	local recording = match and recordings[match.id]
	if not recording or not accepting(recording, now()) then
		return nil, nil, nil
	end
	local first = recording.byId[a.id]
	local second = if b then recording.byId[b.id] else nil
	return recording, first, second
end

function ReplayService:_push(recording: Recording, event: Event)
	local events = recording.events
	table.insert(events, event)
	-- Older than the ring buffer: it could never be shown
	local oldest = event.t - recording.capacity / ReplayConfig.Rate
	while #events > 0 and events[1].t < oldest do
		table.remove(events, 1)
	end
	if #events > ReplayConfig.MaxEvents then
		for index, existing in events do
			if not KEEP[existing.kind] then
				table.remove(events, index)
				return
			end
		end
		table.remove(events, 1)
	end
end

function ReplayService:_summarize(recording: Recording, kind: string, text: string, time: number)
	local summary = recording.summary
	table.insert(summary, { t = math.max(0, time - recording.startedAt), kind = kind, text = text })
	if #summary > ReplayConfig.MaxSummary then
		for index, entry in summary do
			if entry.kind ~= "Knockout" then
				table.remove(summary, index)
				return
			end
		end
		table.remove(summary, 1)
	end
end

function ReplayService:_onHit(attacker, target, outcome, opts)
	if attacker == target then
		return
	end
	local recording, from, to = self:_pair(attacker, target)
	if not recording or not from or not to then
		return
	end
	local time = now()
	local result = outcome.result
	local dealt = math.max(0, tonumber(outcome.dealt) or 0)
	local grab = opts.kind == "Grab" or hasTag(opts.tags, "Grab")
	local landed = result == "Hit" or result == "GuardBreak"

	from.stats.damageDealt += dealt
	to.stats.damageTaken += dealt
	if landed then
		from.stats.hitsLanded += 1
		to.stats.hitsTaken += 1
	end
	if result == "Blocked" then
		to.stats.blocks += 1
	elseif result == "Parried" then
		to.stats.parries += 1
	elseif result == "GuardBreak" then
		to.stats.guardBreaks += 1
	end
	if grab and landed then
		from.stats.grabsLanded += 1
		to.stats.grabsSuffered += 1
		to.stats.grabDamageTaken += dealt
	end
	-- A combo: clean hits on one opponent with no gap longer than the combo window
	if result == "Hit" then
		local combo = from.combos[to.id]
		if combo and time - combo.at <= Combat.ComboResetTime then
			combo.count += 1
			combo.at = time
		else
			combo = { count = 1, at = time }
			from.combos[to.id] = combo
		end
		from.stats.longestCombo = math.max(from.stats.longestCombo, combo.count)
	end

	if result ~= "Hit" and result ~= "Blocked" and result ~= "GuardBreak" and result ~= "Parried" and result ~= "Clash" then
		return
	end
	local heavy = opts.kind == "Heavy" or hasTag(opts.tags, "Heavy")
	self:_push(recording, {
		t = time,
		kind = "Hit",
		a = from.index,
		b = to.index,
		result = result,
		damage = math.floor(dealt + 0.5),
		big = dealt >= ReplayConfig.BigHitDamage or (heavy and landed),
		grab = grab,
	})
	if landed and dealt > 0 and not recording.firstHit then
		recording.firstHit = true
		self:_summarize(recording, "FirstHit", `{from.name} landed the first hit`, time)
	end
end

function ReplayService:_onAbility(fighter, _abilityId: string, def, basic)
	if basic or typeof(def) ~= "table" then
		return
	end
	local recording, track = self:_pair(fighter, nil)
	if not recording or not track then
		return
	end
	local time = now()
	local name = if typeof(def.name) == "string" then def.name else "an ability"
	if def.kind == "Ultimate" then
		track.stats.ultimates += 1
		self:_push(recording, { t = time, kind = "Ultimate", a = track.index, text = name })
		self:_summarize(recording, "Ultimate", `{track.name} used {name}`, time)
	else
		self:_push(recording, { t = time, kind = "Ability", a = track.index, text = name })
	end
end

local DEFENSE_SHOWN = { Perfect = true, Good = true, Escaped = true, Countered = true }

function ReplayService:_onDefense(fighter, kind: string, result: string)
	local recording, track = self:_pair(fighter, nil)
	if not recording or not track then
		return
	end
	local stats = track.stats
	if kind == "Timing" then
		stats.timingBars += 1
		if result == "Perfect" then
			stats.timingPerfect += 1
		end
	end
	if result == "Perfect" then
		stats.perfects += 1
	elseif result == "Good" then
		stats.goods += 1
	elseif result == "Escaped" then
		stats.escapes += 1
	end
	if DEFENSE_SHOWN[result] then
		self:_push(recording, { t = now(), kind = "Defense", a = track.index, text = result })
	end
end

function ReplayService:_onKnockout(victim, credited)
	-- The knockout that ends a match is reported just after the finish
	local recording = self:_pair(victim, nil)
	if not recording then
		return
	end
	local victimTrack = recording.byId[victim.id]
	if not victimTrack then
		return
	end
	local creditedTrack = if credited and credited ~= victim then recording.byId[credited.id] else nil
	local time = now()
	victimTrack.stats.deaths += 1
	if creditedTrack then
		creditedTrack.stats.knockouts += 1
	end
	-- Scores after this knockout (MatchService has already counted it)
	local scores = {}
	local board = recording.match.flow.board
	for index, track in recording.tracks do
		local entry = board and board.entries[track.id]
		scores[index] = if entry then entry.score else 0
	end
	local text = if creditedTrack
		then `{creditedTrack.name} knocked out {victimTrack.name}`
		else `{victimTrack.name} was knocked out`
	self:_push(recording, {
		t = time,
		kind = "Knockout",
		a = if creditedTrack then creditedTrack.index else nil,
		b = victimTrack.index,
		text = text,
		scores = scores,
	})
	if #recording.tracks == 2 then
		text ..= ` ({scores[1]} to {scores[2]})`
	end
	self:_summarize(recording, "Knockout", text, time)
end

-- Sending ---------------------------------------------------------------------------------

local REASONS = {
	TimeUp = "Time ran out",
	SuddenDeath = "Decided in sudden death",
	Draw = "Nobody could break the tie",
	Forfeit = "A fighter left the match",
}

function ReplayService:_finish(match, result)
	local recording = recordings[match.id]
	if not recording or recording.finishedAt then
		return
	end
	local time = now()
	recording.finishedAt = time
	recording.result = result
	local reason = result and REASONS[result.reason]
	if reason then
		self:_summarize(recording, "Finish", reason, time)
	end
	-- Who receives it: the fighters and whoever is watching right now
	local recipients = {}
	for _, participant in match.participants do
		if participant.player then
			table.insert(recipients, participant.player)
		end
	end
	for player in match.spectators do
		if not table.find(recipients, player) then
			table.insert(recipients, player)
		end
	end
	recording.recipients = recipients
	-- The knockout that decided it is reported just after this; sample right away too
	task.defer(function()
		if recordings[match.id] == recording then
			self:_sample(recording, now())
		end
	end)
end

-- The Highlight payload: compact frames, the key events and the summary
function ReplayService:_build(recording: Recording)
	local count = recording.count
	local capacity = recording.capacity
	local first = if count < capacity then 1 else recording.head
	local startTime = recording.times[first]
	local times = table.create(count)
	local frames = {}
	for index in recording.tracks do
		frames[index] = table.create(count * STRIDE)
	end
	for step = 0, count - 1 do
		local slot = (first - 1 + step) % capacity + 1
		table.insert(times, round(recording.times[slot] - startTime, 0.01))
		for index, track in recording.tracks do
			local base = (slot - 1) * STRIDE
			local out = frames[index]
			for offset = 1, STRIDE do
				table.insert(out, track.data[base + offset])
			end
		end
	end
	local events = {}
	for _, event in recording.events do
		if event.t >= startTime then
			local copy = table.clone(event)
			copy.t = round(event.t - startTime, 0.01)
			table.insert(events, copy)
		end
	end
	local summary = {}
	for _, entry in recording.summary do
		table.insert(summary, { t = round(entry.t, 0.1), kind = entry.kind, text = entry.text })
	end
	local fighters = {}
	for _, track in recording.tracks do
		local fighter = self.characters:getById(track.id)
		local def = track.power and Powers.get(track.power)
		local stats = table.clone(track.stats)
		stats.damageDealt = math.floor(stats.damageDealt + 0.5)
		stats.damageTaken = math.floor(stats.damageTaken + 0.5)
		stats.grabDamageTaken = math.floor(stats.grabDamageTaken + 0.5)
		table.insert(fighters, {
			id = track.id,
			name = track.name,
			userId = track.userId,
			npc = track.npc,
			model = if fighter and fighter.model.Parent then fighter.model else nil,
			power = track.power,
			powerName = if def then def.name else nil,
			color = track.color,
			stats = stats,
			tip = ReplayService.tipFor(track.stats),
		})
	end
	local match = recording.match
	local result = recording.result or {}
	local lastTime = recording.times[(first - 1 + count - 1) % capacity + 1]
	return {
		matchId = recording.matchId,
		mode = match.mode.DisplayName,
		modeName = match.modeName,
		arena = match.arena and match.arena.name or nil,
		recordedAt = os.time(),
		fightSeconds = math.floor(((recording.finishedAt or lastTime) - recording.startedAt) + 0.5),
		duration = round(lastTime - startTime, 0.01),
		rate = ReplayConfig.Rate,
		stride = STRIDE,
		-- When the match was decided, in replay seconds
		decidedAt = if recording.finishedAt then round(recording.finishedAt - startTime, 0.01) else nil,
		fighters = fighters,
		times = times,
		frames = frames,
		events = events,
		summary = summary,
		result = { reason = result.reason, draw = result.draw == true, winnerIds = result.winners or {} },
		cpu = if match.cpu then { power = match.cpu.power, difficulty = match.cpu.difficulty, degree = match.cpu.degree } else nil,
	}
end

function ReplayService:_send(recording: Recording)
	if recording.count == 0 then
		return
	end
	local payload = self:_build(recording)
	local recipients = recording.recipients or {}
	-- Anyone who started watching during the results sees it too
	local live = self.matches:getMatch(recording.matchId)
	if live then
		for player in live.spectators do
			if not table.find(recipients, player) then
				table.insert(recipients, player)
			end
		end
	end
	for _, player in recipients do
		if player.Parent == Players then
			MatchEvent:FireClient(player, Protocol.MatchEvent.Highlight, payload)
		end
	end
end

return ReplayService
