-- Jeffery's first-time tutorial and contextual hints (server side).
--
-- The tutorial is a path of steps (Config/Tutorial.Steps). A step completes only on a REAL
-- event the server sees: a hit landed (CombatService), an ability used (AbilityService), a
-- transformation (PowerService), a win (MatchService), or the fighter's own state (moving,
-- jumping, sprinting, blocking, dodging, standing in the training hall). Note-only steps
-- (welcome, camera) take a CONTINUE from the player, but only for the current step. Nothing
-- else the client sends can complete a step.
--
-- Progress lives in profile.tutorial.done (keys in Config/Tutorial). Players with 3 or more
-- matches are skipped automatically. The welcome reward (title "Recruit" and some Money) is
-- granted once, by this service. Exiting is always possible and never blocks play.
--
-- Hints are one-line tips from Jeffery, each shown once per account (remembered here), skipped
-- while the player has hints off (profile.settings.hints) or while the tutorial is running.
-- The client holds each hint until combat is quiet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FighterState = require(ReplicatedStorage.Shared.Combat.FighterState)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Selection = require(ReplicatedStorage.Shared.Config.Selection)
local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ProgressRequest = Remotes:WaitForChild("ProgressRequest") :: RemoteEvent
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local Action = Protocol.ProgressAction

local TutorialService = {}

type Run = {
	index: number,
	replay: boolean,
	startPosition: Vector3?,
	finished: boolean,
}

local runs: { [Player]: Run } = {}
local seenZone: { [Player]: string } = {}
local POLL = 0.25
local PREMIUM_HINTS = { Corruption = "power_Corruption", Syntax = "power_Syntax", Admin = "power_Admin" }

local function now(): number
	return workspace:GetServerTimeNow()
end

function TutorialService:Init(services)
	self.services = services
	self.data = services.DataService
	self.characters = services.CharacterService
	self.antiExploit = services.AntiExploitService
end

-- Profile helpers -------------------------------------------------------------------------

function TutorialService:_done(player: Player): { [string]: boolean }?
	local profile = self.data:get(player)
	return profile and profile.tutorial.done
end

function TutorialService:_mark(player: Player, key: string): boolean
	return self.data:update(player, function(profile)
		profile.tutorial.done[key] = true
	end)
end

-- Sends the current state to the player's client
function TutorialService:_send(player: Player, extra: { [string]: any }?)
	if not player.Parent then
		return
	end
	local run = runs[player]
	local done = self:_done(player) or {}
	local payload: { [string]: any } = {
		active = run ~= nil and not run.finished,
		replay = run ~= nil and run.replay,
		total = #Tutorial.Steps,
		complete = done.tut_complete == true,
		done = {},
	}
	for _, step in Tutorial.Steps do
		if done["tut_step_" .. step.id] then
			table.insert(payload.done, step.id)
		end
	end
	if run and not run.finished then
		local step = Tutorial.Steps[run.index]
		payload.index = run.index
		payload.step = step.id
	end
	for key, value in extra or {} do
		payload[key] = value
	end
	DataEvent:FireClient(player, Protocol.DataEvent.Tutorial, payload)
end

-- Starts (or resumes) the path for a player. replay = true goes through every step again.
function TutorialService:_begin(player: Player, replay: boolean)
	local done = self:_done(player)
	if not done then
		return
	end
	local index = 1
	if not replay then
		while index <= #Tutorial.Steps and done["tut_step_" .. Tutorial.Steps[index].id] do
			index += 1
		end
		if index > #Tutorial.Steps then
			return
		end
	end
	local fighter = self.characters:getByPlayer(player)
	runs[player] = {
		index = index,
		replay = replay,
		startPosition = fighter and fighter.root.Position or nil,
		finished = false,
	}
	if not replay and self.services.AnalyticsLog then
		self.services.AnalyticsLog:funnel(player, "tour_started")
	end
	self:_send(player, { event = "start" })
end

function TutorialService:isActive(player: Player): boolean
	local run = runs[player]
	return run ~= nil and not run.finished
end

function TutorialService:currentStep(player: Player): string?
	local run = runs[player]
	if run and not run.finished then
		return Tutorial.Steps[run.index].id
	end
	return nil
end

-- Events ----------------------------------------------------------------------------------

-- The one door every real event goes through
function TutorialService:_event(player: Player?, kind: string)
	local run = player and runs[player]
	if not run or run.finished or not player then
		return
	end
	local step = Tutorial.Steps[run.index]
	if step.event ~= kind then
		return
	end
	if not run.replay then
		if not self:_mark(player, "tut_step_" .. step.id) then
			return
		end
	end
	run.index += 1
	if not run.replay and self.services.AnalyticsLog then
		self.services.AnalyticsLog:tourStep(player, step.id)
	end
	local fighter = self.characters:getByPlayer(player)
	run.startPosition = fighter and fighter.root.Position or run.startPosition
	if run.index > #Tutorial.Steps then
		run.finished = true
		self:_finish(player, run)
	else
		local nextStep = Tutorial.Steps[run.index]
		-- A moment later: saving the step re-equips the saved power, which would end the trial
		task.delay(0.6, function()
			if runs[player] == run and Tutorial.Steps[run.index] == nextStep then
				self:_prepare(player, nextStep)
			end
		end)
		self:_send(player, { event = "step", completed = step.id })
	end
end

-- Before a step that needs it: evolving in training needs a Trial, so start one on the
-- player's own power (free and never saved, the usual Training rules)
function TutorialService:_prepare(player: Player, step)
	if step.id ~= "evolve" then
		return
	end
	local fighter = self.characters:getByPlayer(player)
	local runtime = fighter and fighter.power
	if runtime and not runtime.training and Selection.inTrainingZone(fighter.root.Position) then
		pcall(self.services.PowerService.trial, self.services.PowerService, player, runtime.id, 1)
	end
end

function TutorialService:_finish(player: Player, run: Run)
	local rewarded = false
	if not run.replay then
		local done = self:_done(player)
		if done and not done.tut_reward then
			local reward = Tutorial.Reward
			-- The flag, the title and the Money go in one profile update; the grant is only
			-- announced after it saved. A second finish finds the flag and pays nothing.
			local ok = self.data:update(player, function(profile)
				profile.tutorial.done.tut_complete = true
				profile.tutorial.done.tut_reward = true
				profile.cosmetics.owned[reward.titleId] = true
				if not profile.cosmetics.equipped.title then
					profile.cosmetics.equipped.title = reward.titleId
				end
			end)
			if ok then
				rewarded = true
				self.services.CurrencyService:add(player, { money = reward.money }, "tutorial")
			end
		end
	end
	if not run.replay then
		-- Tell the growth services (analytics funnel, referral milestone); both are optional
		if self.services.AnalyticsLog then
			self.services.AnalyticsLog:funnel(player, "tour_finished")
		end
		if self.services.CommunityService then
			self.services.CommunityService:onTourFinished(player)
		end
	end
	self:_send(player, { event = "complete", rewarded = rewarded, reward = Tutorial.Reward })
	runs[player] = nil
end

function TutorialService:_exit(player: Player)
	local run = runs[player]
	if not run then
		return
	end
	runs[player] = nil
	if not run.replay then
		self:_mark(player, "tut_exited")
	end
	self:_send(player, { event = "exit" })
end

-- Hints -----------------------------------------------------------------------------------

function TutorialService:_hint(player: Player, id: string)
	local hint = Tutorial.Hints[id]
	local profile = self.data:get(player)
	if not hint or not profile or not player.Parent then
		return
	end
	if profile.tutorial.done["hint_" .. id] or profile.settings.hints == false or self:isActive(player) then
		return
	end
	if not self:_mark(player, "hint_" .. id) then
		return
	end
	DataEvent:FireClient(player, Protocol.DataEvent.Hint, { id = id, text = hint.text, face = hint.face })
end

-- Polled facts about each player's fighter (movement, state, area, power)
function TutorialService:_poll()
	for _, player in Players:GetPlayers() do
		local fighter = self.characters:getByPlayer(player)
		if fighter and self.characters:isAlive(fighter) and self.data:get(player) then
			local position = fighter.root.Position
			local training = Selection.inTrainingZone(position)
			local zone = if training then "training" else "lobby"
			local match = self.services.MatchService:getMatchOf(fighter)
			if not match and seenZone[player] ~= zone then
				seenZone[player] = zone
				self:_hint(player, zone)
			end
			local run = runs[player]
			if run and not run.finished then
				self:_pollSteps(player, fighter, run, position, training)
			end
			local runtime = fighter.power
			if runtime then
				local hintId = PREMIUM_HINTS[runtime.id]
				if hintId then
					self:_hint(player, hintId)
				end
				if runtime.meter and runtime.meter >= Selection.Phase.MeterMax and not training then
					self:_hint(player, "evolve_ready")
				end
			end
		end
	end
end

function TutorialService:_pollSteps(player: Player, fighter, run: Run, position: Vector3, training: boolean)
	local step = Tutorial.Steps[run.index]
	local time = now()
	local state = fighter.state
	local event = step.event
	if event == "move" then
		local start = run.startPosition
		if not start then
			run.startPosition = position
		elseif (position - start).Magnitude >= Tutorial.MoveDistance then
			self:_event(player, "move")
		end
	elseif event == "jump" then
		local velocity = fighter.root.AssemblyLinearVelocity
		if velocity.Y >= Tutorial.JumpSpeed then
			self:_event(player, "jump")
		end
	elseif event == "sprint" then
		if FighterState.isSprinting(state, time) then
			self:_event(player, "sprint")
		end
	elseif event == "training" then
		if training then
			self:_event(player, "training")
		end
	elseif event == "block" then
		if training and FighterState.isBlocking(state) then
			self:_event(player, "block")
		end
	elseif event == "dodge" then
		if training and FighterState.isDodging(state, time) then
			self:_event(player, "dodge")
		end
	end
end

-- Start --------------------------------------------------------------------------------------

function TutorialService:Start()
	local services = self.services

	services.CombatService:onHit(function(attacker, _target, outcome)
		if attacker and attacker.player and outcome and (outcome.dealt or 0) > 0 then
			self:_event(attacker.player, "attack")
		end
	end)
	services.AbilityService:onUsed(function(fighter, _id, _def, basic)
		if fighter.player and not basic then
			self:_event(fighter.player, "ability")
		end
	end)
	services.DefenseService:onResult(function(fighter, kind, _result)
		if not fighter.player then
			return
		end
		if kind == "Mash" then
			self:_hint(fighter.player, "grab_suffered")
		elseif kind == "Timing" then
			self:_hint(fighter.player, "timing_bar")
		end
	end)
	self.characters:onStamina(function(fighter, change)
		if change == "Winded" and fighter.player then
			self:_hint(fighter.player, "stamina_out")
		end
	end)
	services.MatchService:onFinished(function(_match, result)
		for _, id in result.winners or {} do
			local userId = tonumber(string.match(tostring(id), "^Player:(%d+)$"))
			local player = userId and Players:GetPlayerByUserId(userId)
			if player then
				self:_event(player, "win")
			end
		end
	end)

	-- Evolving and opening fighter selection have no listener of their own: wrap the two entry
	-- points. The originals run first and unchanged; we only look at what happened.
	local powers = services.PowerService
	local transform = powers._transform
	powers._transform = function(service, fighter, newDegree, ...)
		local before = fighter.power and fighter.power.degree
		local results = table.pack(transform(service, fighter, newDegree, ...))
		if fighter.player and before and fighter.power and fighter.power.degree > before then
			self:_event(fighter.player, "evolve")
		end
		return table.unpack(results, 1, results.n)
	end
	local onRequest = powers._onRequest
	powers._onRequest = function(service, player, action, ...)
		local results = table.pack(onRequest(service, player, action, ...))
		if action == Protocol.PowerAction.State or action == Protocol.PowerAction.Quote then
			self:_event(player, "showcase")
		end
		return table.unpack(results, 1, results.n)
	end

	self.data:onLoaded(function(player, profile)
		local done = profile.tutorial.done
		if done.tut_complete or done.tut_exited or done.tut_veteran then
			self:_send(player, { event = "state" })
			return
		end
		if (profile.stats.matches or 0) >= Tutorial.VeteranMatches then
			self:_mark(player, "tut_veteran")
			self:_send(player, { event = "state" })
			return
		end
		self:_begin(player, false)
	end)

	ProgressRequest.OnServerEvent:Connect(function(player, action, argument)
		if typeof(action) ~= "string" then
			return
		end
		if action == Action.TutorialAck then
			if typeof(argument) ~= "string" or not self.antiExploit:allow(player, "Progress") then
				return
			end
			local run = runs[player]
			if run and not run.finished then
				local step = Tutorial.Steps[run.index]
				if step.id == argument and step.event == "ack" then
					self:_event(player, "ack")
				end
			end
		elseif action == Action.TutorialExit then
			if self.antiExploit:allow(player, "Progress") then
				self:_exit(player)
			end
		elseif action == Action.TutorialReplay then
			if self.antiExploit:allow(player, "Progress") and not self:isActive(player) then
				self:_begin(player, true)
			end
		elseif action == Action.HintWindow then
			if typeof(argument) ~= "string" or not self.antiExploit:allow(player, "Progress") then
				return
			end
			local hintId = Tutorial.WindowHints[argument]
			if hintId and not self:isActive(player) then
				self:_hint(player, hintId)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		runs[player] = nil
		seenZone[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(POLL)
			self:_poll()
		end
	end)
end

return TutorialService
