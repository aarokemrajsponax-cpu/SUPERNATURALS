-- Runs attacks, blocks and dodges. Clients only *ask* (through
-- Remotes.CombatRequest); the server checks every request against the
-- fighter's state, times the attack itself, finds who it hits, and decides the
-- outcome. Clients are told what happened so they can show it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local FighterState = require(ReplicatedStorage.Shared.Combat.FighterState)
local HitResolver = require(ReplicatedStorage.Shared.Combat.HitResolver)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CombatRequest = Remotes:WaitForChild("CombatRequest") :: RemoteEvent
local CombatEvent = Remotes:WaitForChild("CombatEvent") :: RemoteEvent

local Action = Protocol.CombatAction
local Event = Protocol.CombatEvent

local CombatService = {}

-- Small delay added to scheduled steps so they never run a hair early
local SCHEDULE_SLACK = 0.005

local function now(): number
	return workspace:GetServerTimeNow()
end

local function reachOf(def)
	return {
		range = def.Range,
		arc = def.Arc,
		verticalReach = Combat.VerticalReach,
		targetRadius = Combat.TargetRadius,
		pointBlank = Combat.PointBlankRange,
	}
end

local function sideOf(fighter)
	return {
		id = fighter.id,
		state = fighter.state,
		position = fighter.root.Position,
		look = fighter.root.CFrame.LookVector,
	}
end

function CombatService:Init(services)
	self.services = services
	self.characters = services.CharacterService
	self.damageService = services.DamageService
	self.antiExploit = services.AntiExploitService
	self.lineOfSight = RaycastParams.new()
	self.lineOfSight.FilterType = Enum.RaycastFilterType.Exclude
	-- Only solid things (walls, pillars) block a hit; glowing decorations don't
	self.lineOfSight.RespectCanCollide = true
end

function CombatService:Start()
	CombatRequest.OnServerEvent:Connect(function(player, action, payload)
		-- Releasing block has its own budget, so a burst of attacks can never
		-- use it up and leave the player stuck blocking
		local channel = if action == Action.BlockEnd then "BlockRelease" else "Combat"
		if not self.antiExploit:allow(player, channel) then
			return
		end
		if typeof(action) ~= "string" or Action[action] == nil then
			self.antiExploit:flag(player, "unknown combat action")
			return
		end
		local fighter = self.characters:getByPlayer(player)
		if not fighter or not self.characters:isAlive(fighter) then
			return
		end
		local ok, reason = self:perform(fighter, action, payload)
		local blockAction = action == Action.BlockStart or action == Action.BlockEnd
		if not ok and reason and reason ~= "buffered" and not blockAction then
			CombatEvent:FireClient(player, Event.Rejected, { action = action, reason = reason })
		end
	end)
end

-- The one entry point for every combat action, used by players and NPCs alike.
-- Returns whether it happened, and why not.
function CombatService:perform(fighter, action: string, payload: any?): (boolean, string?)
	local matchService = self.services.MatchService
	if action ~= Action.BlockEnd and not matchService:isCombatAllowed(fighter) then
		return false, "unavailable"
	end
	-- Frozen in ice (owner panel or Ice Age): no fighting until thawed
	if action ~= Action.BlockEnd and (fighter.root.Anchored or fighter.model:GetAttribute(Protocol.Attribute.Iced) == true) then
		return false, "frozen"
	end
	local state = fighter.state
	local time = now()

	if action == Action.Light then
		local attack, reason = FighterState.startLight(state, Combat, time)
		if not attack then
			return false, reason
		end
		FighterState.dropProtection(state, time)
		self:_runAttack(fighter, attack)
		return true, nil
	elseif action == Action.Heavy then
		local attack, reason = FighterState.startHeavy(state, Combat, time)
		if not attack then
			return false, reason
		end
		FighterState.dropProtection(state, time)
		self:_runAttack(fighter, attack)
		return true, nil
	elseif action == Action.BlockStart then
		-- "Held" means the button never came up (re-raised after a stun): no parry
		local ok, reason = FighterState.startBlock(state, time, payload ~= "Held")
		self.characters:refresh(fighter)
		return ok, reason
	elseif action == Action.BlockEnd then
		local ok = FighterState.endBlock(state, Combat, time)
		if ok then
			self.characters:refresh(fighter)
		end
		return ok, nil
	elseif action == Action.Dodge then
		return self:_dodge(fighter, payload)
	end
	return false, "unknown"
end

function CombatService:_dodge(fighter, payload: any?): (boolean, string?)
	local ok, reason = FighterState.startDodge(fighter.state, Combat, now())
	if not ok then
		return false, reason
	end
	FighterState.dropProtection(fighter.state, now())
	local direction = self.antiExploit.direction(payload)
		or Hitbox.flatDirection(-fighter.root.CFrame.LookVector)
		or Vector3.new(0, 0, 1)
	-- Players move their own character instantly on their client (so the dodge
	-- feels immediate); the server moves NPCs itself
	if fighter.npc then
		self.damageService:push(fighter, direction, Combat.Dodge.Speed, 0, Combat.Dodge.Duration)
	end
	self.characters:refresh(fighter)
	CombatEvent:FireAllClients(Event.Dodge, { fighter = fighter.model, direction = direction })
	return true, nil
end

function CombatService:_runAttack(fighter, attack)
	local state = fighter.state
	local token = attack.token
	local alreadyHit: { [string]: boolean } = {}
	local landed = false
	-- Where the swing started: an attacker can only drift so far during it
	local origin = fighter.root.Position

	self.characters:refresh(fighter)
	CombatEvent:FireAllClients(Event.Attack, {
		attacker = fighter.model,
		kind = attack.kind,
		step = attack.step,
		startup = attack.def.Startup,
		active = attack.def.Active,
	})

	local function stillGoing(): boolean
		return FighterState.isCurrent(state, token) and self.characters:isAlive(fighter)
	end

	local function after(time: number, callback: () -> ())
		task.delay(math.max(0, time - now()) + SCHEDULE_SLACK, callback)
	end

	-- Check for hits when the active window opens and again when it closes,
	-- so targets that step in mid-swing are still caught (each is hit once)
	after(attack.activeAt, function()
		if not stillGoing() then
			return
		end
		landed = self:_sweep(fighter, attack, alreadyHit, origin) or landed
		after(attack.activeEnd, function()
			if not stillGoing() then
				return
			end
			landed = self:_sweep(fighter, attack, alreadyHit, origin) or landed
			FighterState.endActive(state, Combat, token, landed)
			self.characters:refresh(fighter)
			-- endActive may have lengthened recovery (a missed heavy)
			after(attack.recoveryEnd, function()
				if not FighterState.isCurrent(state, token) then
					return
				end
				local buffered = FighterState.finishAttack(state, now())
				self.characters:refresh(fighter)
				if buffered and self.characters:isAlive(fighter) then
					self:perform(fighter, Action.Light)
				end
			end)
		end)
	end)
end

function CombatService:_hasLineOfSight(attacker, target): boolean
	local ignore = {}
	for _, fighter in self.characters:all() do
		table.insert(ignore, fighter.model)
	end
	self.lineOfSight.FilterDescendantsInstances = ignore
	local origin = attacker.root.Position
	local result = workspace:Raycast(origin, target.root.Position - origin, self.lineOfSight)
	return result == nil
end

-- Movement allowed during a swing beyond walking at attack speed (covers network delay)
local DRIFT_SLACK = 4

-- Hits every valid target inside the attack's reach; returns whether any connected
function CombatService:_sweep(attacker, attack, alreadyHit: { [string]: boolean }, startedAt: Vector3): boolean
	local matchService = self.services.MatchService
	local origin = attacker.root.Position
	-- Characters move on their own client, so check the attacker didn't teleport
	-- somewhere mid-swing to land an impossible hit. Only sideways movement
	-- counts (jumps and falls are fine), at full walking speed (the slow-down
	-- reaches their client a moment late), and pushes or teleports are excused.
	local drift = origin - startedAt
	local sideways = Vector3.new(drift.X, 0, drift.Z).Magnitude
	local allowed = Combat.Movement.WalkSpeed * attacker.moveBoost * (now() - attack.startedAt) + DRIFT_SLACK
	local excused = attacker.root:FindFirstChild("SNKnockback") ~= nil
		or attacker.root:FindFirstChild("SNPull") ~= nil
		or attacker.teleportedAt >= attack.startedAt
	if sideways > allowed and not excused then
		if attacker.player then
			self.antiExploit:flag(attacker.player, "moved too far during an attack")
		end
		return false
	end
	local look = attacker.root.CFrame.LookVector
	local reach = reachOf(attack.def)
	local landed = false
	for _, target in self.characters:all() do
		if
			target ~= attacker
			and not alreadyHit[target.id]
			and self.characters:isAlive(target)
			and matchService:canDamage(attacker, target)
			and Hitbox.inArc(origin, look, target.root.Position, reach)
			and self:_hasLineOfSight(attacker, target)
		then
			alreadyHit[target.id] = true
			if self:_strike(attacker, target, attack) then
				landed = true
			end
			-- A parry stops the attack: nothing else gets hit
			if not FighterState.isCurrent(attacker.state, attack.token) then
				break
			end
		end
	end
	return landed
end

-- Resolves one attack against one target and applies the result.
-- Returns true if the attack connected (hit, blocked or guard-broken).
function CombatService:_strike(attacker, target, attack): boolean
	local time = now()
	local attackerSide = sideOf(attacker)
	local targetSide = sideOf(target)
	local outcome = HitResolver.resolve(attack.def, Combat, attackerSide, targetSide, time)
	HitResolver.apply(outcome, Combat, attackerSide, targetSide, time)

	local dealt = HitResolver.damageToDeal(outcome, target.humanoid.Health)
	self.damageService:damage(target, dealt)

	local direction = Hitbox.flatDirection(target.root.Position - attacker.root.Position)
		or Hitbox.flatDirection(attacker.root.CFrame.LookVector)
		or Vector3.new(0, 0, -1)
	if outcome.knockback > 0 or outcome.launch > 0 then
		self.damageService:push(target, direction, outcome.knockback, outcome.launch)
	end

	self.characters:refresh(target)
	if outcome.result == "Parried" then
		self.characters:refresh(attacker)
	end

	CombatEvent:FireAllClients(Event.Hit, {
		attacker = attacker.model,
		victim = target.model,
		result = outcome.result,
		damage = dealt,
		position = target.root.Position,
		heavy = attack.kind == "Heavy",
		finisher = attack.def.Finisher == true,
		comboCapped = outcome.comboCapped,
	})

	return outcome.result == "Hit" or outcome.result == "Blocked" or outcome.result == "GuardBreak"
end

return CombatService
