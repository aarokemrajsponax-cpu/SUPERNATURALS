-- Runs attacks, blocks and dodges, and resolves every hit in the game (basic
-- attacks, abilities, projectiles, zones, burns). Clients only *ask* (through
-- Remotes.CombatRequest); the server checks every request against the
-- fighter's state, times the attack itself, finds who it hits, and decides the
-- outcome. Clients are told what happened so they can show it.
--
-- Each fighter fights with its own combat numbers (fighter.combat): the shared
-- Config/Combat with its power's, degree's and form's changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local function reachOf(def, config)
	return {
		range = def.Range,
		arc = def.Arc,
		verticalReach = config.VerticalReach,
		targetRadius = config.TargetRadius,
		pointBlank = config.PointBlankRange,
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

export type HitOptions = {
	-- "Light" | "Heavy" | "Ability" | "Projectile" | "Zone" | "Status"
	kind: string,
	power: string?,
	ability: string?,
	-- What counters can answer it (Melee, Small, Heavy, Area, Grab, Projectile, Massive)
	tags: { string }?,
	-- Where the hit comes from (a projectile's position); defaults to the attacker
	origin: Vector3?,
	-- Push direction; defaults to away from the origin
	direction: Vector3?,
	-- Skip counters and interactive defenses (burn ticks, a counter's own strike)
	noDefense: boolean?,
	-- The timing cue this hit belongs to, if it was telegraphed with one
	cueId: string?,
	projectile: any?,
}

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

-- Can this fighter act at all right now? (Shared by basic attacks and abilities.)
function CombatService:canAct(fighter): (boolean, string?)
	if not self.services.MatchService:isCombatAllowed(fighter) then
		return false, "unavailable"
	end
	-- Frozen in ice (owner panel or Ice Age): no fighting until thawed
	if fighter.root.Anchored or fighter.model:GetAttribute(Protocol.Attribute.Iced) == true then
		return false, "frozen"
	end
	return true, nil
end

-- The one entry point for every basic combat action, used by players and NPCs
-- alike. Returns whether it happened, and why not.
function CombatService:perform(fighter, action: string, payload: any?): (boolean, string?)
	if action ~= Action.BlockEnd then
		local ok, reason = self:canAct(fighter)
		if not ok then
			return false, reason
		end
	end
	local state = fighter.state
	local config = fighter.combat
	local time = now()

	-- Powers that replace the basic attacks (blasters, animal bites) use an ability instead
	if action == Action.Light or action == Action.Heavy then
		local powers = self.services.PowerService
		local override = powers and powers:basicOverride(fighter, action)
		if override then
			return self.services.AbilityService:use(fighter, override, payload, { basic = action })
		end
	end

	if action == Action.Light then
		local attack, reason = FighterState.startLight(state, config, time)
		if not attack then
			return false, reason
		end
		FighterState.dropProtection(state, time)
		self:_runAttack(fighter, attack)
		return true, nil
	elseif action == Action.Heavy then
		local attack, reason = FighterState.startHeavy(state, config, time)
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
		local ok = FighterState.endBlock(state, config, time)
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
	local config = fighter.combat
	local ok, reason = FighterState.startDodge(fighter.state, config, now())
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
		self.damageService:push(fighter, direction, config.Dodge.Speed, 0, config.Dodge.Duration)
	end
	self.characters:refresh(fighter)
	CombatEvent:FireAllClients(Event.Dodge, { fighter = fighter.model, direction = direction })
	local powers = self.services.PowerService
	if powers then
		powers:onDodged(fighter)
	end
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
			FighterState.endActive(state, fighter.combat, token, landed)
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

-- Is there nothing solid between two points? (Characters never block.)
function CombatService:hasLineOfSight(from: Vector3, to: Vector3): boolean
	local ignore = {}
	for _, fighter in self.characters:all() do
		table.insert(ignore, fighter.model)
	end
	self.lineOfSight.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(from, to - from, self.lineOfSight)
	return result == nil
end

-- Movement allowed during a swing beyond walking at attack speed (covers network delay)
local DRIFT_SLACK = 4

-- Was the fighter moved by something legitimate since `since` (knockback, a pull,
-- its own dash, a teleport)?
function CombatService:movedLegitimately(fighter, since: number): boolean
	local root = fighter.root
	return root:FindFirstChild("SNKnockback") ~= nil
		or root:FindFirstChild("SNPull") ~= nil
		or root:FindFirstChild("SNDash") ~= nil
		or fighter.dashUntil >= since
		or fighter.teleportedAt >= since
end

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
	local walkSpeed = attacker.combat.Movement.WalkSpeed * attacker.moveBoost * math.max(1, attacker.statusSpeed)
	local allowed = walkSpeed * (now() - attack.startedAt) + DRIFT_SLACK
	if sideways > allowed and not self:movedLegitimately(attacker, attack.startedAt) then
		if attacker.player then
			self.antiExploit:flag(attacker.player, "moved too far during an attack")
		end
		return false
	end
	local look = attacker.root.CFrame.LookVector
	local reach = reachOf(attack.def, attacker.combat)
	local landed = false
	local tags = if attack.kind == "Heavy" then { "Melee", "Heavy" } else { "Melee", "Small" }
	for _, target in self.characters:all() do
		if
			target ~= attacker
			and not alreadyHit[target.id]
			and self.characters:isAlive(target)
			and matchService:canDamage(attacker, target)
			and Hitbox.inArc(origin, look, target.root.Position, reach)
			and self:hasLineOfSight(origin, target.root.Position)
		then
			alreadyHit[target.id] = true
			local outcome = self:applyHit(attacker, target, attack.def, {
				kind = attack.kind,
				power = attacker.power and attacker.power.id,
				tags = tags,
			})
			if outcome and (outcome.result == "Hit" or outcome.result == "Blocked" or outcome.result == "GuardBreak") then
				landed = true
			end
			-- A parry or counter stops the attack: nothing else gets hit
			if not FighterState.isCurrent(attacker.state, attack.token) then
				break
			end
		end
	end
	return landed
end

-- Resolves one hit against one target and applies it: counters and
-- interactive defenses, blocks and parries, super armor, damage, knockback,
-- knockout credit, ultimate charge. Every damaging thing in the game comes
-- through here. `hit` uses attack fields (Damage, Hitstun, Knockback, Launch,
-- GuardDamage, Blockable, Parryable, Finisher). Returns the outcome (with
-- `dealt`), or nil if the target couldn't be hit.
function CombatService:applyHit(attacker, target, hit, opts: HitOptions)
	if not self.characters:isAlive(target) then
		return nil
	end
	local time = now()
	local origin = opts.origin or attacker.root.Position
	local powers = self.services.PowerService
	local defense = self.services.DefenseService
	local statuses = self.services.StatusService

	-- Counters, perfect timing and redirects get the first say
	local verdict = if defense and not opts.noDefense then defense:intercept(attacker, target, hit, opts) else nil
	if verdict and verdict.negate then
		self.characters:refresh(target)
		self.characters:refresh(attacker)
		CombatEvent:FireAllClients(Event.Hit, {
			attacker = attacker.model,
			victim = target.model,
			result = verdict.result,
			damage = 0,
			position = target.root.Position,
			kind = opts.kind,
			power = opts.power,
			ability = opts.ability,
		})
		return { result = verdict.result, damage = 0, dealt = 0, hitstun = 0, knockback = 0, launch = 0 }
	end

	local attackerSide = {
		id = attacker.id,
		state = attacker.state,
		position = origin,
		look = attacker.root.CFrame.LookVector,
	}
	local targetSide = sideOf(target)
	-- Only something swinging at you up close can be parried (and stunned for it);
	-- projectiles, zones and burns are blocked normally instead
	local closeRange = opts.kind == "Light" or opts.kind == "Heavy" or opts.kind == "Ability"
	local resolveDef = hit
	if not closeRange and hit.Parryable ~= false then
		resolveDef = table.clone(hit)
		resolveDef.Parryable = false
	end
	local outcome = HitResolver.resolve(resolveDef, target.combat, attackerSide, targetSide, time)

	local scale = target.combat.DamageTaken or 1
	if verdict and verdict.damageScale then
		scale *= verdict.damageScale
	end
	if statuses then
		scale *= statuses:damageTakenMultiplier(target)
	end
	outcome.damage *= scale
	if verdict and verdict.noFlinch then
		outcome.hitstun = 0
		outcome.knockback = 0
		outcome.launch = 0
	end
	if powers then
		-- Passives like Iron Body change what actually lands
		powers:modifyIncoming(target, attacker, outcome, opts)
	end

	HitResolver.apply(outcome, target.combat, attackerSide, targetSide, time)
	local dealt = HitResolver.damageToDeal(outcome, target.humanoid.Health)
	if statuses then
		dealt = statuses:absorb(target, dealt)
	end
	self.damageService:damage(target, dealt)
	outcome.dealt = dealt

	local direction = opts.direction
		or Hitbox.flatDirection(target.root.Position - origin)
		or Hitbox.flatDirection(attacker.root.CFrame.LookVector)
		or Vector3.new(0, 0, -1)
	local knockScale = target.combat.KnockbackTaken or 1
	if outcome.knockback > 0 or outcome.launch > 0 then
		self.damageService:push(target, direction, outcome.knockback * knockScale, outcome.launch * knockScale)
	end

	self.characters:refresh(target)
	if outcome.result == "Parried" then
		self.characters:refresh(attacker)
	end
	if powers then
		powers:onHitResolved(attacker, target, outcome, opts)
	end

	CombatEvent:FireAllClients(Event.Hit, {
		attacker = attacker.model,
		victim = target.model,
		result = outcome.result,
		damage = dealt,
		position = target.root.Position,
		heavy = opts.kind == "Heavy" or (opts.tags ~= nil and table.find(opts.tags, "Heavy") ~= nil),
		finisher = hit.Finisher == true,
		comboCapped = outcome.comboCapped,
		armored = outcome.armored,
		kind = opts.kind,
		power = opts.power,
		ability = opts.ability,
	})
	return outcome
end

return CombatService
