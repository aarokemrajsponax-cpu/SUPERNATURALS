-- Jeffery's practice fights in the Training Studio. A player starts a round from the console, from
-- Jeffery's platform or from How to Play; the server moves them to a free sparring floor, applies the
-- chosen environment theme and spawns Jeffery as a CPU sparring unit (DummyService "Cpu", his look,
-- a CpuService behaviour profile). Rounds are about practice only:
--   * nothing is saved, paid or ranked, and no progress is touched (training rules);
--   * every power and phase stays a free trial (the studio is inside Selection.TrainingZone);
--   * damage is allowed only inside the pair (player and their own Jeffery), through
--     MatchService.practiceRule; a round ends when either side is down to Practice.EndHealthShare,
--     so nobody is knocked out;
--   * two players use separate floors and never touch each other's round.
-- Stats come only from server combat events. After the round the numbers go through
-- Config/Practice feedback rules to pick Jeffery's lines (spoken on the client by DialoguePanel).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Powers = require(ReplicatedStorage.Shared.Powers)
local Community = require(ReplicatedStorage.Shared.Config.Community)
local Practice = require(ReplicatedStorage.Shared.Config.Practice)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Selection = require(ReplicatedStorage.Shared.Config.Selection)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ProgressRequest = Remotes:WaitForChild("ProgressRequest") :: RemoteEvent
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local PracticeService = {}

local Action = Protocol.ProgressAction

export type Stats = {
	mode: string,
	outcome: string,
	seconds: number,
	hitsLanded: number,
	hitsTaken: number,
	blocks: number,
	perfectDefences: number,
	grabsSuffered: number,
	maxCombo: number,
	abilitiesUsed: number,
	abilitiesOutOfRange: number,
	damageDealt: number,
	damageTaken: number,
	abilitiesOn: boolean,
}

type Session = {
	player: Player,
	fighter: any,
	mode: string,
	options: { [string]: any },
	floor: any,
	unit: any?,
	startedAt: number,
	liveAt: number,
	endsAt: number,
	finished: boolean,
	stats: Stats,
	combo: number,
	comboAt: number,
	lastGrab: number,
	styleIndex: number,
	nextStyleAt: number,
	hintsSent: { [string]: boolean },
	hintCount: number,
	lastHintAt: number,
}

local sessions: { [Player]: Session } = {}
local floorOwner: { [number]: Session } = {}
-- Jeffery's unit id (the dummy and its fighter share it) -> the round it belongs to
local unitSession: { [string]: Session } = {}
local previousStats: { [Player]: Stats } = {}
local lastRequest: { [Player]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

function PracticeService:Init(services)
	self.services = services
	self.characters = services.CharacterService
	self.dummies = services.DummyService
	self.arenas = services.ArenaService
	self.antiExploit = services.AntiExploitService
end

-- Messages ------------------------------------------------------------------------------------

function PracticeService:_send(player: Player, payload: { [string]: any })
	if player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Practice, payload)
	end
end

function PracticeService:_sendState(session: Session?, player: Player)
	if not session then
		self:_send(player, { kind = "State", active = false })
		return
	end
	self:_send(player, {
		kind = "State", active = true, mode = session.mode, theme = session.options.theme, hints = session.options.hints,
		endsAt = session.endsAt, duration = session.options.duration, floor = session.floor.index,
	})
end

function PracticeService:_refuse(player: Player, reason: string, text: string)
	self:_send(player, { kind = "Refused", reason = reason, text = text })
end

-- A short in-round line from Jeffery: once per id, never closer than Practice.HintGap, at most Practice.MaxHints
function PracticeService:_hint(session: Session, id: string, text: string, face: string?)
	if not session.options.hints or session.finished or session.hintsSent[id] then
		return
	end
	local time = now()
	if session.hintCount >= Practice.MaxHints or time - session.lastHintAt < Practice.HintGap then
		return
	end
	session.hintsSent[id] = true
	session.hintCount += 1
	session.lastHintAt = time
	self:_send(session.player, { kind = "Line", id = id, text = text, face = face or "thinking" })
end

-- Rounds ------------------------------------------------------------------------------------------

local function emptyStats(mode: string, abilitiesOn: boolean): Stats
	return {
		mode = mode, outcome = "Time", seconds = 0, hitsLanded = 0, hitsTaken = 0, blocks = 0, perfectDefences = 0,
		grabsSuffered = 0, maxCombo = 0, abilitiesUsed = 0, abilitiesOutOfRange = 0, damageDealt = 0, damageTaken = 0,
		abilitiesOn = abilitiesOn,
	}
end

function PracticeService:sessionOf(player: Player): Session?
	return sessions[player]
end

function PracticeService:isPracticing(player: Player): boolean
	return sessions[player] ~= nil
end

-- Jeffery's unit for a player's round (a Dummy), once spawned
function PracticeService:unitOf(player: Player): any?
	local session = sessions[player]
	return session and session.unit
end

function PracticeService:_spawnUnit(session: Session)
	if session.finished or session.unit then
		return
	end
	local options = session.options
	local power = options.styles[session.styleIndex]
	local floor = session.floor
	local dummy = self.dummies:spawn("Cpu", {
		spawnAt = function()
			return floor.jeffery
		end,
		training = true,
		cpu = {
			power = power, degree = 1, difficulty = options.difficulty, profile = options.profile,
			abilities = options.abilities, look = "Jeffery",
		},
	})
	session.unit = dummy
	unitSession[dummy.id] = session
	self:_hint(session, "start_" .. session.mode, Practice.Hints["start_" .. session.mode], "happy")
end

-- Starts a round (replacing any the player already has). Returns true when it started.
function PracticeService:start(player: Player, modeId: any, rawOptions: any): (boolean, string?)
	local fighter = self.characters:getByPlayer(player)
	if not fighter or not self.characters:isAlive(fighter) then
		return false, "Not ready"
	end
	if not Selection.inTrainingZone(fighter.root.Position) then
		self:_refuse(player, "NotInStudio", "Practice fights run in the Training Studio. Use the Training door in the hub.")
		return false, "NotInStudio"
	end
	local existing = sessions[player]
	if existing then
		self:_finish(existing, "Exited", true)
	end
	local floorIndex
	local studio = self.arenas:trainingStudio()
	if not studio then
		self:_refuse(player, "NoStudio", "The Training Studio is not available right now.")
		return false, "NoStudio"
	end
	for index in studio.floors do
		if not floorOwner[index] then
			floorIndex = index
			break
		end
	end
	if not floorIndex then
		self:_refuse(player, "Busy", "Both sparring floors are in use. Try again in a moment.")
		return false, "Busy"
	end
	local floor = studio.floors[floorIndex]
	local id, options = Practice.resolve(modeId, rawOptions)
	local time = now()
	local session: Session = {
		player = player, fighter = fighter, mode = id, options = options, floor = floor, unit = nil,
		startedAt = time, liveAt = time + Practice.StartGap, endsAt = time + options.duration, finished = false,
		stats = emptyStats(id, options.abilities), combo = 0, comboAt = -math.huge,
		lastGrab = fighter.state.grabbedAt, styleIndex = 1, nextStyleAt = time + Practice.StyleSeconds,
		hintsSent = {}, hintCount = 0, lastHintAt = -math.huge,
	}
	sessions[player] = session
	floorOwner[floorIndex] = session
	floor.setTheme(options.theme)
	fighter.humanoid.Health = fighter.humanoid.MaxHealth
	self.characters:teleport(fighter, floor.player)
	self:_sendState(session, player)
	task.delay(Practice.StartGap, function()
		self:_spawnUnit(session)
	end)
	return true, nil
end

function PracticeService:_cleanup(session: Session)
	if sessions[session.player] == session then
		sessions[session.player] = nil
	end
	if floorOwner[session.floor.index] == session then
		floorOwner[session.floor.index] = nil
		session.floor.setTheme("Studio")
	end
	local unit = session.unit
	if unit then
		unitSession[unit.id] = nil
		self.dummies:despawn(unit)
		session.unit = nil
	end
end

-- Ends a round: the unit goes, health is restored, and the feedback is chosen from the numbers.
-- silent = true skips the result (a restart or a new round replacing this one).
function PracticeService:_finish(session: Session, outcome: string, silent: boolean?)
	if session.finished then
		return
	end
	session.finished = true
	local stats = session.stats
	stats.outcome = outcome
	stats.seconds = math.clamp(now() - session.startedAt, 0, session.options.duration)
	self:_cleanup(session)
	local fighter = session.fighter
	if self.characters:isAlive(fighter) then
		fighter.humanoid.Health = fighter.humanoid.MaxHealth
	end
	if silent then
		return
	end
	-- A finished round counts toward the referral milestone and the first-training funnel step
	if stats.seconds >= Community.Referral.MinPracticeSeconds then
		if self.services.CommunityService then
			self.services.CommunityService:onPracticeRound(session.player, stats.seconds)
		end
		if self.services.AnalyticsLog then
			self.services.AnalyticsLog:funnel(session.player, "first_training")
		end
	end
	if self.services.SeasonPassService then
		self.services.SeasonPassService:onTrainingRound(session.player, stats.seconds)
	end
	local feedback = Practice.feedback(stats, previousStats[session.player])
	previousStats[session.player] = stats
	self:_send(session.player, {
		kind = "Result", mode = session.mode, outcome = outcome, stats = stats,
		lines = feedback.lines, face = feedback.face, next = feedback.next, rules = feedback.rules,
	})
	self:_send(session.player, { kind = "State", active = false })
end

-- Exit: the player is moved off the floor to the platform side of the studio
function PracticeService:stop(player: Player)
	local session = sessions[player]
	if not session then
		self:_sendState(nil, player)
		return
	end
	local studio = self.arenas:trainingStudio()
	self:_finish(session, "Exited")
	if studio and self.characters:isAlive(session.fighter) then
		self.characters:teleport(session.fighter, CFrame.lookAt(studio.platform.Position + Vector3.new(0, 4, -8), studio.platform.Position + Vector3.new(0, 4, 4)))
	end
end

function PracticeService:restart(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local mode, options = session.mode, table.clone(session.options)
	-- Resolved options go back through Practice.resolve in the shape start expects
	self:start(player, mode, {
		theme = options.theme, hints = options.hints, difficulty = options.difficulty, behavior = options.profile,
		duration = options.duration, abilities = options.abilities,
	})
end

-- Who may hurt whom (MatchService.practiceRule): only a player and their own Jeffery, while the
-- round is live and the target is above the end-of-round health share. nil = not a practice pair.
function PracticeService:_rule(attacker, target): boolean?
	local session = unitSession[attacker.id]
	local fromUnit = session ~= nil
	if not session then
		session = unitSession[target.id]
	end
	if not session then
		return nil
	end
	if session.finished or now() < session.liveAt then
		return false
	end
	local mine = session.fighter
	local unit = session.unit and session.unit.fighter
	local pair = if fromUnit then (target == mine and attacker == unit) else (attacker == mine and target == unit)
	if not pair then
		return false
	end
	local humanoid = target.humanoid
	return humanoid.Health > humanoid.MaxHealth * Practice.EndHealthShare
end

function PracticeService:_onHit(attacker, target, outcome)
	local session = unitSession[attacker.id] or unitSession[target.id]
	if not session or session.finished or not outcome then
		return
	end
	local stats = session.stats
	local dealt = outcome.dealt or 0
	local time = now()
	if attacker == session.fighter then
		if outcome.result == "Hit" and dealt > 0 then
			stats.hitsLanded += 1
			stats.damageDealt += dealt
			session.combo = if time - session.comboAt <= Practice.ComboGap then session.combo + 1 else 1
			session.comboAt = time
			stats.maxCombo = math.max(stats.maxCombo, session.combo)
		end
	elseif target == session.fighter then
		if outcome.result == "Hit" and dealt > 0 then
			stats.hitsTaken += 1
			stats.damageTaken += dealt
			session.combo = 0
		elseif outcome.result == "Blocked" or outcome.result == "GuardBreak" then
			stats.blocks += 1
		elseif outcome.result == "Parried" then
			stats.perfectDefences += 1
		end
	end
	-- A round ends when either side is down to the end share of health
	local unit = session.unit and session.unit.fighter
	if unit then
		local limit = Practice.EndHealthShare
		if unit.humanoid.Health <= unit.humanoid.MaxHealth * limit then
			self:_finish(session, "Won")
		elseif session.fighter.humanoid.Health <= session.fighter.humanoid.MaxHealth * limit then
			self:_finish(session, "Lost")
		end
	end
end

function PracticeService:_tick(session: Session)
	local time = now()
	local fighter = session.fighter
	-- The player left, died, respawned or walked out of the studio: the round simply ends
	if not session.player.Parent or self.characters:getByPlayer(session.player) ~= fighter or not self.characters:isAlive(fighter)
		or not Selection.inTrainingZone(fighter.root.Position) then
		self:_finish(session, "Exited", true)
		return
	end
	if time >= session.endsAt then
		local stats = session.stats
		local outcome = if stats.damageDealt > stats.damageTaken then "Won" elseif stats.damageDealt < stats.damageTaken then "Lost" else "Time"
		self:_finish(session, outcome)
		return
	end
	-- Grabs suffered: each new grab on the player (only Jeffery can grab them here)
	local grabbedAt = fighter.state.grabbedAt
	if grabbedAt ~= session.lastGrab then
		session.lastGrab = grabbedAt
		if grabbedAt > 0 and session.unit then
			session.stats.grabsSuffered += 1
			self:_hint(session, "grabbed", Practice.Hints.grabbed, "warning")
		end
	end
	if not session.unit then
		return
	end
	-- Advanced rotates Jeffery through his styles
	local styles = session.options.styles
	if #styles > 1 and time >= session.nextStyleAt then
		session.nextStyleAt = time + Practice.StyleSeconds
		session.styleIndex = session.styleIndex % #styles + 1
		local unit = session.unit
		local power = styles[session.styleIndex]
		if unit.fighter and unit.cpu then
			unit.cpu.power = power
			self.services.PowerService:equip(unit.fighter, power, 1, Powers.defaultLoadout(power, 1))
			self:_hint(session, "style_" .. session.styleIndex, `I am switching style to {Powers.get(power).name}.`, "excited")
		end
	end
	local stats = session.stats
	local elapsed = time - session.liveAt
	if stats.hitsLanded == 0 and elapsed >= 15 then
		self:_hint(session, "idle", Practice.Hints.idle, "thinking")
	end
	if stats.hitsTaken >= 4 and stats.blocks == 0 then
		self:_hint(session, "no_block", Practice.Hints.no_block, "warning")
	end
	if fighter.humanoid.Health <= fighter.humanoid.MaxHealth * 0.35 then
		self:_hint(session, "low", Practice.Hints.low, "warning")
	end
end

function PracticeService:Start()
	local services = self.services
	services.MatchService.practiceRule = function(attacker, target)
		return self:_rule(attacker, target)
	end
	services.CombatService:onHit(function(attacker, target, outcome)
		if attacker and target then
			self:_onHit(attacker, target, outcome)
		end
	end)
	services.AbilityService:onUsed(function(fighter, _id, def, basic)
		local session = fighter.player and sessions[fighter.player]
		if not session or session.finished or basic or session.fighter ~= fighter or not session.unit then
			return
		end
		local stats = session.stats
		stats.abilitiesUsed += 1
		local range = def and ((def.ai and def.ai.range) or def.range)
		local unit = session.unit.fighter
		if range and unit and (unit.root.Position - fighter.root.Position).Magnitude > range + Practice.RangeSlack then
			stats.abilitiesOutOfRange += 1
		end
	end)
	services.DefenseService:onResult(function(fighter, _kind, result)
		local session = fighter.player and sessions[fighter.player]
		if session and not session.finished and session.fighter == fighter and result == "Perfect" then
			session.stats.perfectDefences += 1
		end
	end)

	ProgressRequest.OnServerEvent:Connect(function(player, action, argument, options)
		if typeof(action) ~= "string" then
			return
		end
		if action ~= Action.PracticeStart and action ~= Action.PracticeRestart and action ~= Action.PracticeStop then
			return
		end
		if not self.antiExploit:allow(player, "Progress") then
			return
		end
		local time = os.clock()
		if time - (lastRequest[player] or -math.huge) < Practice.RequestCooldown then
			return
		end
		lastRequest[player] = time
		if action == Action.PracticeStart then
			self:start(player, argument, options)
		elseif action == Action.PracticeRestart then
			self:restart(player)
		else
			self:stop(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			self:_finish(session, "Exited", true)
		end
		previousStats[player] = nil
		lastRequest[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, session in table.clone(sessions) do
				if not session.finished then
					local ok, err = pcall(self._tick, self, session)
					if not ok then
						warn("[Practice] " .. tostring(err))
					end
				end
			end
		end
	end)
end

return PracticeService
