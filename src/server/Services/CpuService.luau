-- CPU opponents: NPC fighters that play a power the way its definition says
-- (preferred range, aggression, each ability's `ai` hint). They move, chain
-- basic attacks, use abilities and ultimates, block and dodge telegraphed
-- attacks, and answer interactive defenses (prompts, timing bars, grab escapes)
-- through exactly the same server rules as players. They also use every
-- universal move: sprinting in, grabbing blockers, sweeps, charged heavies and
-- feints, punishing whiffs, timed parries and perfect dodges, teching throws,
-- tech rolls and breakfalls. Difficulty changes how fast they react and how
-- often they pick (and get right) each option, never the rules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FighterState = require(ReplicatedStorage.Shared.Combat.FighterState)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Action = Protocol.CombatAction

local CpuService = {}

-- Chances are per decision: reactions (techs, parries, punishes, grabbing a
-- blocker) per situation, free choices (sweeps, launchers, sprints, taunts)
-- per second. Easy stays beatable: slow, and it rarely techs, parries or
-- punishes; Hard reads you.
CpuService.Difficulties = {
	Easy = {
		label = "Easy", reaction = 0.55, blockChance = 0.2, dodgeChance = 0.1, abilityRate = 0.2, timingError = 0.22, mashRate = 5, think = 0.3, promptChance = 0.3,
		grabChance = 0.12, sweepChance = 0.04, chargeChance = 0.1, feintChance = 0, techChance = 0.1, techRollChance = 0.1, breakfallChance = 0.1,
		punishChance = 0.15, parryChance = 0, perfectChance = 0, sprintChance = 0.15, launcherChance = 0, tauntChance = 0.04,
	},
	Normal = {
		label = "Normal", reaction = 0.32, blockChance = 0.45, dodgeChance = 0.25, abilityRate = 0.4, timingError = 0.1, mashRate = 8, think = 0.2, promptChance = 0.6,
		grabChance = 0.3, sweepChance = 0.1, chargeChance = 0.3, feintChance = 0.05, techChance = 0.4, techRollChance = 0.4, breakfallChance = 0.4,
		punishChance = 0.5, parryChance = 0.2, perfectChance = 0.15, sprintChance = 0.45, launcherChance = 0.08, tauntChance = 0.02,
	},
	Hard = {
		label = "Hard", reaction = 0.18, blockChance = 0.7, dodgeChance = 0.4, abilityRate = 0.65, timingError = 0.05, mashRate = 12, think = 0.14, promptChance = 0.85,
		grabChance = 0.55, sweepChance = 0.16, chargeChance = 0.55, feintChance = 0.3, techChance = 0.75, techRollChance = 0.7, breakfallChance = 0.7,
		punishChance = 0.85, parryChance = 0.45, perfectChance = 0.35, sprintChance = 0.75, launcherChance = 0.15, tauntChance = 0.01,
	},
}
CpuService.DifficultyOrder = { "Easy", "Normal", "Hard" }

local MELEE_RANGE = 5.5

-- fighter id -> the brain's settings
local brains: { [string]: any } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

function CpuService:Init(services)
	self.services = services
	self.characters = services.CharacterService
end

function CpuService:Start()
	self.services.DefenseService.cpuResponder = function(fighter, cue, data)
		self:_respond(fighter, cue, data)
	end
end

-- Starts the brain for a CPU fighter (DummyService calls this when it builds one)
function CpuService:run(fighter, difficultyName: string?)
	local difficulty = CpuService.Difficulties[difficultyName or "Normal"] or CpuService.Difficulties.Normal
	local brain = {
		difficulty = difficulty,
		reactedTo = 0,
		blockingUntil = 0,
		strafe = if math.random() < 0.5 then 1 else -1,
		strafeUntil = 0,
		-- The grab, knockdown and launch each recovery decision was made for
		techFor = -1,
		rollFor = -1,
		breakfallFor = -1,
	}
	brains[fighter.id] = brain
	task.spawn(function()
		while self.characters:isAlive(fighter) and brains[fighter.id] == brain do
			local ok, err = pcall(self._think, self, fighter, brain)
			if not ok then
				warn("[CPU] " .. tostring(err))
			end
			task.wait(difficulty.think * (0.8 + math.random() * 0.4))
		end
		if brains[fighter.id] == brain then
			brains[fighter.id] = nil
		end
	end)
end

function CpuService:stop(fighter)
	brains[fighter.id] = nil
end

function CpuService:_target(fighter)
	local best, bestDistance = nil, math.huge
	local matchService = self.services.MatchService
	for _, other in self.characters:all() do
		if other ~= fighter and self.characters:isAlive(other) and matchService:canDamage(fighter, other) then
			local distance = (other.root.Position - fighter.root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	return best, bestDistance
end

local function aimAt(fighter, target)
	local lead = target.root.AssemblyLinearVelocity * 0.15
	local point = target.root.Position + Vector3.new(lead.X, 0, lead.Z)
	local direction = point - fighter.root.Position
	return { direction = if direction.Magnitude > 0.01 then direction.Unit else fighter.root.CFrame.LookVector, point = point }
end

-- Gets back up the way a player would: tech a throw, tech roll a knockdown,
-- breakfall out of a juggle. Returns true while the CPU can't do anything else.
function CpuService:_recover(fighter, brain, target, time: number): boolean
	local combat = self.services.CombatService
	local state = fighter.state
	local config = fighter.combat
	local difficulty = brain.difficulty
	local away = Hitbox.flatDirection(fighter.root.Position - target.root.Position) or -fighter.root.CFrame.LookVector
	if FighterState.isGrabbed(state, time) then
		if brain.techFor ~= state.grabbedAt then
			brain.techFor = state.grabbedAt
			if math.random() < difficulty.techChance then
				local window = config.Grab.TechWindow
				local delay = math.min(difficulty.reaction, window) * (0.3 + math.random() * 0.6) - (time - state.grabbedAt)
				task.delay(math.max(0, delay), function()
					combat:perform(fighter, Action.Grab)
				end)
			end
		end
		return true
	elseif FighterState.isDowned(state, time) then
		if brain.rollFor ~= state.downedAt then
			brain.rollFor = state.downedAt
			if math.random() < difficulty.techRollChance then
				local delay = math.random() * config.Knockdown.TechWindow * 0.8 - (time - state.downedAt)
				task.delay(math.max(0, delay), function()
					combat:perform(fighter, Action.Dodge, { dir = away })
				end)
			end
		end
		return true
	elseif FighterState.isAirborne(state, time) then
		if brain.breakfallFor ~= state.airborneSince then
			brain.breakfallFor = state.airborneSince
			if math.random() < difficulty.breakfallChance then
				local at = state.airborneSince + config.Air.BreakfallAfter + math.random() * 0.3
				task.delay(math.max(0, at - time), function()
					combat:perform(fighter, Action.Dodge, { dir = away })
				end)
			end
		end
		return true
	end
	return FighterState.isStunned(state, time)
end

-- Reacts to an attack the target just started: block, parry, dodge (perfectly
-- on a good day), or hit them out of a grab or a charge
function CpuService:_defend(fighter, brain, target, attack, distance: number)
	local combat = self.services.CombatService
	local difficulty = brain.difficulty
	local config = fighter.combat
	local kind = attack.kind
	task.delay(difficulty.reaction, function()
		if not self.characters:isAlive(fighter) or not FighterState.isCurrent(target.state, attack.token) then
			return
		end
		-- Mid-swing it's committed (Block now would feint its own heavy)
		if FighterState.isAttacking(fighter.state, now()) then
			return
		end
		local away = Hitbox.flatDirection(fighter.root.Position - target.root.Position) or Vector3.new(1, 0, 0)
		local side = Vector3.new(-away.Z, 0, away.X) * brain.strafe
		local roll = math.random()
		if kind == "Grab" or kind == "Charge" or kind == "Taunt" then
			-- Blocking loses to grabs and a full charge breaks guard: strike them
			-- out of it (a counter hit), or step away
			if distance <= MELEE_RANGE + 1 and roll < difficulty.punishChance then
				combat:perform(fighter, Action.Light, aimAt(fighter, target))
			elseif kind ~= "Taunt" and roll < difficulty.punishChance + difficulty.dodgeChance then
				combat:perform(fighter, Action.Dodge, { dir = away })
			end
			return
		end
		if (kind == "Heavy" or kind == "Ability") and roll < difficulty.dodgeChance then
			-- Timed right before it lands, it's a perfect dodge
			local dodgeAt = now()
			if math.random() < difficulty.perfectChance then
				dodgeAt = math.max(dodgeAt, attack.activeAt - 0.06)
			end
			task.delay(math.max(0, dodgeAt - now()), function()
				combat:perform(fighter, Action.Dodge, { dir = (away + side).Unit })
			end)
		elseif roll < difficulty.blockChance then
			-- Raised right before the hit, the block is a parry
			local blockAt = now()
			if math.random() < difficulty.parryChance then
				blockAt = math.max(blockAt, attack.activeAt - config.Block.ParryWindow * 0.5)
			end
			task.delay(math.max(0, blockAt - now()), function()
				combat:perform(fighter, Action.BlockStart)
				brain.blockingUntil = now() + 0.7
			end)
		end
	end)
end

-- Holds a charged heavy for a while, then lets go (Hard sometimes feints instead)
function CpuService:_chargeHeavy(fighter, brain)
	local combat = self.services.CombatService
	local charge = fighter.combat.Heavy.Charge
	if not combat:perform(fighter, Action.Heavy, { charge = true }) then
		return false
	end
	local feint = math.random() < brain.difficulty.feintChance
	local hold = if feint then charge.Min * 0.8 else charge.Min + math.random() * (charge.Max - charge.Min)
	task.delay(hold, function()
		if self.characters:isAlive(fighter) then
			combat:perform(fighter, if feint then Action.Feint else Action.HeavyRelease)
		end
	end)
	return true
end

-- The universal moves every fighter has (grabs, sweeps, sprint strikes,
-- charges, launchers, punishes). Returns true when it did something.
function CpuService:_universal(fighter, brain, target, distance: number, time: number): boolean
	local combat = self.services.CombatService
	local difficulty = brain.difficulty
	local config = fighter.combat
	local state = fighter.state
	local them = target.state
	local aim = aimAt(fighter, target)
	local toward = Hitbox.flatDirection(target.root.Position - fighter.root.Position) or fighter.root.CFrame.LookVector
	-- Free choices are rolled every think, so their chances are per second
	local function perSecond(chance: number): boolean
		return math.random() < chance * difficulty.think
	end

	-- Sprint in from afar; strike out of the run or stop when close
	if FighterState.isSprinting(state, time) then
		if distance <= config.Running.Light.Range + 1.5 then
			local roll = math.random()
			combat:perform(fighter, Action.SprintEnd)
			if roll < 0.35 then
				combat:perform(fighter, Action.Light, { dir = toward })
				return true
			elseif roll < 0.55 then
				combat:perform(fighter, Action.Heavy, { dir = toward })
				return true
			end
		elseif FighterState.staminaAt(state, config, time) < 25 then
			combat:perform(fighter, Action.SprintEnd)
		end
	elseif distance > 14 and FighterState.staminaAt(state, config, time) > 45 and perSecond(difficulty.sprintChance * 2) then
		combat:perform(fighter, Action.SprintStart)
	end

	-- Taunt from a safe distance while they're on the floor
	if FighterState.isDowned(them, time) and distance > 10 and perSecond(difficulty.tauntChance * 4) then
		return combat:perform(fighter, Action.Taunt)
	end
	if distance > MELEE_RANGE + 1 then
		return false
	end
	-- Punish a whiffed move: they can't do anything about it
	if FighterState.inWhiffRecovery(them, time) and math.random() < difficulty.punishChance then
		return combat:perform(fighter, if math.random() < 0.5 then Action.Heavy else Action.Light, aim)
	end
	-- Stuck in a long stun, getting up or winded: charge something big
	local slow = them.stunUntil - time > config.Heavy.Charge.Min + config.Heavy.Charge.ReleaseStartup or FighterState.isWinded(them, target.combat, time)
	if slow and math.random() < difficulty.chargeChance then
		return self:_chargeHeavy(fighter, brain)
	end
	-- A blocker gets grabbed
	if FighterState.isBlocking(them) and distance <= config.Grab.Range + 0.5 and math.random() < difficulty.grabChance then
		return combat:perform(fighter, Action.Grab, { dir = if math.random() < 0.3 then -toward else toward })
	end
	if distance <= config.Sweep.Range and perSecond(difficulty.sweepChance) then
		return combat:perform(fighter, Action.Sweep)
	end
	if perSecond(difficulty.launcherChance) then
		return combat:perform(fighter, Action.Heavy, { dir = -toward })
	end
	return false
end

function CpuService:_think(fighter, brain)
	local combat = self.services.CombatService
	local abilities = self.services.AbilityService
	local state = fighter.state
	local time = now()
	local target, distance = self:_target(fighter)
	local humanoid = fighter.humanoid

	if not target or not combat:canAct(fighter) then
		humanoid:MoveTo(fighter.root.Position)
		if FighterState.isBlocking(state) then
			combat:perform(fighter, Action.BlockEnd)
		end
		if FighterState.isSprinting(state, time) then
			combat:perform(fighter, Action.SprintEnd)
		end
		return
	end
	local difficulty = brain.difficulty
	local runtime = fighter.power
	local powerAi = runtime and runtime.def.ai or { preferredRange = 6, aggression = 0.6 }

	-- Recover first: techs, tech rolls and breakfalls
	if self:_recover(fighter, brain, target, time) then
		return
	end

	-- Defend: react once to each attack the target starts near us
	local attack = target.state.attack
	if attack and attack.token ~= brain.reactedTo and time < attack.activeAt and distance < 14 then
		brain.reactedTo = attack.token
		self:_defend(fighter, brain, target, attack, distance)
	end
	if FighterState.isBlocking(state) and time >= brain.blockingUntil then
		combat:perform(fighter, Action.BlockEnd)
	end
	if FighterState.isBlocking(state) or FighterState.isAttacking(state, time) then
		return
	end

	-- Move: close in to the power's favourite range, back off if too close, strafe around it
	local toTarget = target.root.Position - fighter.root.Position
	local flat = Hitbox.flatDirection(toTarget) or Vector3.new(0, 0, -1)
	local preferred = powerAi.preferredRange or 6
	if time >= brain.strafeUntil then
		brain.strafe = -brain.strafe
		brain.strafeUntil = time + 1 + math.random() * 1.5
	end
	local side = Vector3.new(-flat.Z, 0, flat.X) * brain.strafe
	local destination
	if distance > preferred + 2 then
		destination = target.root.Position - flat * preferred
	elseif distance < preferred - 3 and preferred > 8 then
		destination = fighter.root.Position - flat * 8 + side * 4
	else
		destination = fighter.root.Position + side * 5
	end
	humanoid:MoveTo(destination)
	fighter.root.CFrame = CFrame.lookAt(fighter.root.Position, fighter.root.Position + flat)

	-- Universal moves (grabs, sweeps, charges, sprint strikes) come first now and then
	if self:_universal(fighter, brain, target, distance, time) then
		return
	end

	-- Attack: ultimate when it's charged and in reach, then abilities, then basics
	if not runtime then
		if distance <= MELEE_RANGE then
			combat:perform(fighter, Action.Light)
		end
		return
	end
	local aim = aimAt(fighter, target)
	local degree = runtime.degree
	if runtime.ultimate and runtime.ult >= 100 then
		local def = Powers.abilityFor(runtime.id, runtime.ultimate, degree)
		if def and distance <= ((def.ai and def.ai.range) or 12) and math.random() < difficulty.abilityRate then
			if abilities:use(fighter, runtime.ultimate, aim) then
				return
			end
		end
	end
	local aggression = powerAi.aggression or 0.6
	if math.random() < difficulty.abilityRate * aggression then
		local healthShare = humanoid.Health / math.max(1, humanoid.MaxHealth)
		for _, abilityId in runtime.loadout do
			local def = Powers.abilityFor(runtime.id, abilityId, degree)
			local hint = def and def.ai
			if def and hint and time >= (runtime.cooldowns[abilityId] or 0) and runtime.resource >= (def.cost or 0) then
				local wanted = (hint.use == "Escape" and healthShare < 0.4 and distance < 8)
					or (hint.use == "Defend" and distance < (hint.range or 6) and target.state.attack ~= nil)
					or ((hint.use == "Engage" or hint.use == "Poke" or hint.use == "Finisher") and distance <= (hint.range or 10))
				if wanted and abilities:use(fighter, abilityId, aim) then
					return
				end
			end
		end
	end
	-- Basic attacks (blasters and other replacements reach further)
	local lightOverride = Powers.basicFor(runtime.id, degree, runtime.form, "Light")
	local reach = if lightOverride then 40 else MELEE_RANGE
	if distance <= reach then
		local heavy = math.random() < 0.18
		combat:perform(fighter, if heavy then Action.Heavy else Action.Light, aim)
	end
end

-- Interactive defenses: the CPU presses through the same rules as a player
function CpuService:_respond(fighter, cue, data)
	local brain = brains[fighter.id]
	if not brain then
		return
	end
	local difficulty = brain.difficulty
	local defense = self.services.DefenseService
	if cue.kind == "Timing" then
		-- Aim for the centre, with an error that depends on difficulty
		local error = (math.random() + math.random() + math.random() - 1.5) * difficulty.timingError * 1.4
		local pressAt = cue.impactAt + error
		task.delay(math.max(0, pressAt - now()), function()
			defense:cpuPress(fighter, cue.id, Protocol.DefenseInput.Timing)
		end)
	elseif cue.kind == "Mash" then
		task.spawn(function()
			while now() < cue.closesAt and self.characters:isAlive(fighter) do
				defense:cpuPress(fighter, cue.id, Protocol.DefenseInput.Mash)
				task.wait(1 / difficulty.mashRate)
			end
		end)
	elseif cue.kind == "Prompt" then
		if math.random() < difficulty.promptChance then
			local reactAt = math.max(cue.opensAt, now() + difficulty.reaction)
			task.delay(math.max(0, reactAt - now()), function()
				local combat = self.services.CombatService
				if math.random() < 0.5 then
					local away = Hitbox.flatDirection(fighter.root.CFrame.LookVector) or Vector3.new(0, 0, 1)
					combat:perform(fighter, Action.Dodge, { dir = -away })
				else
					combat:perform(fighter, Action.BlockStart)
					brain.blockingUntil = now() + 0.8
				end
			end)
		end
	elseif cue.kind == "Redirect" then
		if math.random() < difficulty.promptChance then
			task.delay(math.min(difficulty.reaction, math.max(0, cue.closesAt - now() - 0.05)), function()
				defense:cpuPress(fighter, cue.id, Protocol.DefenseInput.Redirect)
			end)
		end
	end
	local _ = data
end

return CpuService
