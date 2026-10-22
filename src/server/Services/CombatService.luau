-- Runs attacks, blocks and dodges, and resolves every hit in the game (basic
-- attacks, abilities, projectiles, zones, burns). Clients only *ask* (through
-- Remotes.CombatRequest); the server checks every request against the
-- fighter's state, times the attack itself, finds who it hits, and decides the
-- outcome. Clients are told what happened so they can show it.
--
-- Fighting System v2 lives here too: the server reads the fighter's situation
-- to pick the move (aerials, sprint strikes, the Launcher, charged heavies),
-- runs grabs, throws and techs, sweeps and knockdowns, tech rolls and
-- breakfalls, clashes, perfect dodges, wall splats, carried props and taunts.
-- The rules themselves are pure functions in FighterState and HitResolver;
-- this file does the physical side (positions, pushes, props) and the events.
--
-- Each fighter fights with its own combat numbers (fighter.combat): the shared
-- Config/Combat with its power's, degree's and form's changes.

local CollectionService = game:GetService("CollectionService")
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

-- Other services can listen to every resolved hit (progression, replays)
local hitListeners: { (attacker: any, target: any, outcome: any, opts: any) -> () } = {}

-- Small delay added to scheduled steps so they never run a hair early
local SCHEDULE_SLACK = 0.005
-- A held opponent (or a prop set down) sits this far in front of the holder
local HOLD_OFFSET = 2.6
-- Grabs and drops keep this far inside the arena's walls
local ARENA_MARGIN_STUDS = 3
-- The copy of a carried prop that rides in the fighter's hands
local CARRY_NAME = "SNCarriedProp"
-- Moving at least this fast (or asking to) counts as running for sprint strikes
local RUNNING_SPEED = 8

-- Releasing a held button has its own rate budget, so attack spam can never
-- leave a fighter stuck sprinting or charging (both also end on their own)
local HOLD_ACTIONS = {
	[Action.SprintStart] = true,
	[Action.SprintEnd] = true,
	[Action.HeavyRelease] = true,
}
-- Letting go of something never tells the client it was refused
local RELEASE_ACTIONS = {
	[Action.BlockEnd] = true,
	[Action.SprintEnd] = true,
	[Action.HeavyRelease] = true,
}

-- Basic grabs in progress: holder id -> the hold, and victim id -> holder id
local holds: { [string]: { victimId: string, at: number, back: boolean } } = {}
local heldBy: { [string]: string } = {}
-- Props being carried: fighter id -> the arena prop, the copy in hand, a token
local carried: { [string]: { prop: BasePart, copy: BasePart?, token: number } } = {}
local carryTokens = 0
-- Per-fighter bookkeeping for announcements and held buttons
local marks: { [string]: { blockHeld: boolean, gotUpFrom: number, landing: boolean } } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function after(time: number, callback: () -> ())
	task.delay(math.max(0, time - now()) + SCHEDULE_SLACK, callback)
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

local function hasTag(tags: { string }?, name: string): boolean
	return tags ~= nil and table.find(tags, name) ~= nil
end

local function flatLook(fighter): Vector3
	return Hitbox.flatDirection(fighter.root.CFrame.LookVector) or Vector3.new(0, 0, -1)
end

-- Is the movement intent pointing away from where the fighter faces?
local function isBack(look: Vector3, intent: Vector3?): boolean
	if intent == nil or intent.Magnitude < 0.3 then
		return false
	end
	local facing = Hitbox.flatDirection(look)
	return facing ~= nil and intent.Unit:Dot(facing) < -0.5
end

local function markOf(fighter)
	local mark = marks[fighter.id]
	if not mark then
		mark = { blockHeld = false, gotUpFrom = -math.huge, landing = false }
		marks[fighter.id] = mark
	end
	return mark
end

-- Tells every client about a fighter's movement-like moment (see Protocol.CombatEvent.Motion)
local function motion(fighter, name: string, extra: { [string]: any }?)
	local data: { [string]: any } = { fighter = fighter.model, motion = name }
	if extra then
		for key, value in extra do
			data[key] = value
		end
	end
	CombatEvent:FireAllClients(Event.Motion, data)
end

-- Puts a hidden arena prop back where it lives (an arena torn down meanwhile
-- takes its props with it: nothing to do)
local function returnProp(prop: BasePart)
	if not prop.Parent then
		return
	end
	local home = prop:GetAttribute("HomeCFrame")
	if typeof(home) == "CFrame" then
		prop.CFrame = home
	end
	local saved = prop:GetAttribute("SavedTransparency")
	prop.Transparency = if typeof(saved) == "number" then saved else 0
	prop.CanCollide = true
	prop.CanQuery = true
	prop:SetAttribute("Held", nil)
end

export type HitOptions = {
	-- "Light" | "Heavy" | "Ability" | "Projectile" | "Zone" | "Status" | "Grab"
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
	-- Fighting System v2: a close-range strike (counter hits, punishes and perfect
	-- dodges apply; abilities tagged "Melee" count too), a basic attack (combo
	-- scaling applies), a riposte, and the move's name for clients
	melee: boolean?,
	basic: boolean?,
	riposte: boolean?,
	move: string?,
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
		local channel = if action == Action.BlockEnd then "BlockRelease" elseif HOLD_ACTIONS[action] then "CombatHold" else "Combat"
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
		local quiet = action == Action.BlockStart or RELEASE_ACTIONS[action] == true
		if not ok and reason and reason ~= "buffered" and not quiet then
			CombatEvent:FireClient(player, Event.Rejected, { action = action, reason = reason })
		end
	end)

	-- Grabs, carried props and held buttons never outlive the fighter's state
	self.characters:onKnockout(function(fighter)
		self:resetFighter(fighter)
	end)
	self.characters:onRestored(function(fighter)
		self:resetFighter(fighter)
	end)
	self.characters:onUnregistered(function(fighter)
		self:resetFighter(fighter)
		marks[fighter.id] = nil
	end)
	self.characters:onProfileChanged(function(fighter)
		self:resetFighter(fighter)
	end)
	self.characters:onStamina(function(fighter, change)
		-- "Winded" or "Recovered"
		motion(fighter, change)
	end)
end

-- callback(attacker, target, outcome, opts) after every resolved hit
function CombatService:onHit(callback: (any, any, any, any) -> ())
	table.insert(hitListeners, callback)
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

-- A client's movement intent from a combat payload: { dir = Vector3 } (also
-- { direction = Vector3 }, or a bare Vector3 from older clients). Flat, at most
-- 1 long; junk gives nil.
function CombatService:intentOf(payload: any): Vector3?
	if typeof(payload) == "Vector3" then
		return self.antiExploit.intent(payload)
	elseif typeof(payload) == "table" then
		local dir = rawget(payload, "dir")
		if dir == nil then
			dir = rawget(payload, "direction")
		end
		return self.antiExploit.intent(dir)
	end
	return nil
end

-- Off the ground (jumping or falling)? The server's own view of the humanoid,
-- never the client's word. Tests replace this to put fighters in the air.
function CombatService:isInAir(fighter): boolean
	local humanoid = fighter.humanoid
	local ok, inAir = pcall(function()
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
			return true
		end
		return humanoid.FloorMaterial == Enum.Material.Air and math.abs(fighter.root.AssemblyLinearVelocity.Y) > 4
	end)
	return ok and inAir == true
end

-- A spot inside the fighter's arena (unchanged outside matches)
function CombatService:keepInside(fighter, position: Vector3): Vector3
	local match = self.services.MatchService:getMatchOf(fighter)
	local arenas = self.services.ArenaService
	if match and match.arena and arenas and arenas.clampInside then
		return arenas:clampInside(match.arena, position, ARENA_MARGIN_STUDS)
	end
	return position
end

-- The one entry point for every basic combat action, used by players and NPCs
-- alike. Returns whether it happened, and why not.
function CombatService:perform(fighter, action: string, payload: any?): (boolean, string?)
	if not RELEASE_ACTIONS[action] then
		local ok, reason = self:canAct(fighter)
		if not ok then
			return false, reason
		end
	end
	local state = fighter.state
	local config = fighter.combat
	local time = now()
	-- Settle stamina before anything changes, so a sprint costs exactly what it ran
	FighterState.settleStamina(state, config, time)
	local intent = self:intentOf(payload)

	-- What the button means depends on the situation: breaking a throw, or a prop in hand
	if action == Action.Light or action == Action.Grab then
		if FighterState.canTech(state, config, time) then
			return self:_tech(fighter)
		elseif state.carrying ~= nil then
			if action == Action.Light then
				return self:_throwProp(fighter, payload)
			end
			return self:_dropProp(fighter, "Drop"), nil
		end
	end

	-- Powers that replace the basic attacks (blasters, animal bites) use an
	-- ability instead, for every variant of the button
	if action == Action.Light or action == Action.Heavy then
		local powers = self.services.PowerService
		local override = powers and powers:basicOverride(fighter, action)
		if override then
			return self.services.AbilityService:use(fighter, override, payload, { basic = action })
		end
	end

	if action == Action.Light then
		return self:_light(fighter, intent)
	elseif action == Action.Heavy then
		local charge = typeof(payload) == "table" and rawget(payload, "charge") == true
		return self:_heavy(fighter, intent, charge)
	elseif action == Action.HeavyRelease then
		return self:_releaseCharge(fighter)
	elseif action == Action.Feint then
		return self:_feint(fighter, false)
	elseif action == Action.BlockStart then
		markOf(fighter).blockHeld = true
		-- Block during your own heavy's wind-up or charge cancels it: a feint
		if self:_canFeint(state, time) then
			return self:_feint(fighter, true)
		end
		-- "Held" means the button never came up (re-raised after a stun): no parry
		local ok, reason = FighterState.startBlock(state, time, payload ~= "Held")
		self.characters:refresh(fighter)
		return ok, reason
	elseif action == Action.BlockEnd then
		markOf(fighter).blockHeld = false
		local ok = FighterState.endBlock(state, config, time)
		if ok then
			self.characters:refresh(fighter)
		end
		return ok, nil
	elseif action == Action.Dodge then
		return self:_dodge(fighter, intent)
	elseif action == Action.Grab then
		return self:_grab(fighter, intent)
	elseif action == Action.Sweep then
		return self:_sweepKick(fighter)
	elseif action == Action.SprintStart then
		local ok, reason = FighterState.startSprint(state, config, time)
		if ok then
			self.characters:refresh(fighter)
			motion(fighter, "SprintStart")
		end
		return ok, reason
	elseif action == Action.SprintEnd then
		local ok = FighterState.endSprint(state, config, time)
		if ok then
			self.characters:refresh(fighter)
			motion(fighter, "SprintEnd")
		end
		return ok, nil
	elseif action == Action.Taunt then
		return self:_taunt(fighter)
	end
	return false, "unknown"
end

-- Strikes ------------------------------------------------------------------------

-- Running for sprint strikes: sprinting and actually moving (or asking to)
function CombatService:_running(fighter, intent: Vector3?, time: number): boolean
	if not FighterState.isSprinting(fighter.state, time) then
		return false
	end
	local velocity = fighter.root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude >= RUNNING_SPEED or (intent ~= nil and intent.Magnitude >= 0.5)
end

function CombatService:_light(fighter, intent: Vector3?): (boolean, string?)
	local state = fighter.state
	local config = fighter.combat
	local time = now()
	local _, def = FighterState.chooseMove(config, "Light", {
		air = self:isInAir(fighter),
		sprinting = self:_running(fighter, intent, time),
	})
	local attack, reason
	if def then
		attack, reason = FighterState.startVariant(state, config, "Light", def, time)
	else
		attack, reason = FighterState.startLight(state, config, time)
	end
	if not attack then
		return false, reason
	end
	FighterState.dropProtection(state, time)
	self:_runAttack(fighter, attack)
	return true, nil
end

function CombatService:_heavy(fighter, intent: Vector3?, charge: boolean): (boolean, string?)
	local state = fighter.state
	local config = fighter.combat
	local time = now()
	local _, def = FighterState.chooseMove(config, "Heavy", {
		air = self:isInAir(fighter),
		sprinting = self:_running(fighter, intent, time),
		back = isBack(fighter.root.CFrame.LookVector, intent),
	})
	local attack, reason
	if def then
		attack, reason = FighterState.startVariant(state, config, "Heavy", def, time)
	elseif charge then
		return self:_startCharge(fighter)
	else
		attack, reason = FighterState.startHeavy(state, config, time)
	end
	if not attack then
		return false, reason
	end
	FighterState.dropProtection(state, time)
	self:_runAttack(fighter, attack)
	return true, nil
end

-- Hold Heavy: charge until released (HeavyRelease) or full, then swing
function CombatService:_startCharge(fighter): (boolean, string?)
	local state = fighter.state
	local config = fighter.combat
	local time = now()
	local attack, reason = FighterState.startCharge(state, config, time)
	if not attack then
		return false, reason
	end
	FighterState.dropProtection(state, time)
	self.characters:refresh(fighter)
	motion(fighter, "Charge", { duration = config.Heavy.Charge.Max })
	local token = attack.token
	-- A full charge swings by itself
	after(attack.activeAt, function()
		if FighterState.isCurrent(state, token) and self.characters:isAlive(fighter) then
			self:_releaseCharge(fighter)
		end
	end)
	return true, nil
end

function CombatService:_releaseCharge(fighter): (boolean, string?)
	local state = fighter.state
	local time = now()
	if not self:canAct(fighter) then
		-- The fight stopped (or the fighter froze) mid-charge: just let it go
		if FighterState.isCharging(state, time) then
			FighterState.cancelAttack(state)
			self.characters:refresh(fighter)
		end
		return false, "unavailable"
	end
	local attack, reason = FighterState.releaseCharge(state, fighter.combat, time)
	if not attack then
		return false, reason
	end
	self:_runAttack(fighter, attack)
	return true, nil
end

function CombatService:_canFeint(state, time: number): boolean
	local attack = state.attack
	return attack ~= nil and ((attack.kind == "Heavy" and time < attack.activeAt) or FighterState.isCharging(state, time))
end

-- Cancels a heavy's wind-up or charge. From the Block button, the guard comes
-- up by itself once the feint's short recovery is over (if Block is still held).
function CombatService:_feint(fighter, fromBlock: boolean): (boolean, string?)
	local state = fighter.state
	local config = fighter.combat
	local ok, reason = FighterState.feint(state, config, now())
	if not ok then
		return false, reason
	end
	self.characters:refresh(fighter)
	motion(fighter, "Feint", { duration = config.Feint.Recovery })
	if fromBlock then
		after(state.recoverUntil, function()
			if markOf(fighter).blockHeld and self.characters:isAlive(fighter) and not FighterState.isBlocking(state) then
				FighterState.startBlock(state, now(), false)
				self.characters:refresh(fighter)
			end
		end)
	end
	return true, nil
end

function CombatService:_sweepKick(fighter): (boolean, string?)
	local state = fighter.state
	local time = now()
	local attack, reason = FighterState.startSweep(state, fighter.combat, time)
	if not attack then
		return false, reason
	end
	FighterState.dropProtection(state, time)
	self:_runAttack(fighter, attack)
	return true, nil
end

function CombatService:_taunt(fighter): (boolean, string?)
	local state = fighter.state
	local config = fighter.combat
	local time = now()
	local attack, reason = FighterState.startTaunt(state, config, time)
	if not attack then
		return false, reason
	end
	FighterState.dropProtection(state, time)
	self.characters:refresh(fighter)
	motion(fighter, "Taunt", { duration = config.Taunt.Duration })
	local token = attack.token
	-- Finishing unhit earns a little ultimate charge (a hit cancels the taunt)
	after(attack.recoveryEnd, function()
		if not FighterState.isCurrent(state, token) then
			return
		end
		FighterState.finishAttack(state, now())
		self.characters:refresh(fighter)
		if not self.characters:isAlive(fighter) then
			return
		end
		motion(fighter, "TauntDone")
		local powers = self.services.PowerService
		if powers then
			powers:addUltimate(fighter, config.Taunt.UltimateCharge)
		end
	end)
	return true, nil
end

-- Dodges ----------------------------------------------------------------------------

function CombatService:_dodge(fighter, intent: Vector3?): (boolean, string?)
	local state = fighter.state
	local config = fighter.combat
	local time = now()
	-- On the floor, Dodge is a tech roll; launched, it's a breakfall
	if FighterState.isDowned(state, time) then
		return self:_techRoll(fighter, intent)
	elseif FighterState.isAirborne(state, time) then
		return self:_breakfall(fighter, intent)
	end
	local look = flatLook(fighter)
	local style = FighterState.dodgeStyle(look, intent)
	local ok, reason, numbers = FighterState.startDodge(state, config, time, style)
	if not ok then
		return false, reason
	end
	FighterState.dropProtection(state, time)
	local direction
	if style == "Back" then
		direction = if intent and isBack(look, intent) then intent.Unit else -look
	else
		direction = (intent :: Vector3).Unit
	end
	-- Players move their own character instantly on their client (so the dodge
	-- feels immediate); the server moves NPCs itself
	if fighter.npc then
		self.damageService:push(fighter, direction, numbers.speed, 0, numbers.duration)
	end
	self.characters:refresh(fighter)
	if numbers.cancel then
		motion(fighter, "DodgeCancel", { direction = direction })
	end
	CombatEvent:FireAllClients(Event.Dodge, {
		fighter = fighter.model,
		direction = direction,
		style = numbers.style,
		speed = numbers.speed,
		duration = numbers.duration,
		invulnerable = numbers.invulnerable,
	})
	local powers = self.services.PowerService
	if powers then
		powers:onDodged(fighter)
	end
	return true, nil
end

-- Dodge just after hitting the floor: roll away (the server moves everyone)
function CombatService:_techRoll(fighter, intent: Vector3?): (boolean, string?)
	local state = fighter.state
	local config = fighter.combat
	local time = now()
	local ok, reason = FighterState.techRoll(state, config, time)
	if not ok then
		return false, reason
	end
	markOf(fighter).gotUpFrom = state.downedAt
	local knockdown = config.Knockdown
	local direction = if intent then intent.Unit else -flatLook(fighter)
	fighter.dashUntil = math.max(fighter.dashUntil, time + knockdown.TechRollDuration + 0.2)
	self.damageService:push(fighter, direction, knockdown.TechRollDistance / knockdown.TechRollDuration, 0, knockdown.TechRollDuration)
	self.characters:refresh(fighter)
	motion(fighter, "TechRoll", { direction = direction, duration = knockdown.TechRollDuration })
	return true, nil
end

-- Dodge while launched: recover in the air and escape the juggle
function CombatService:_breakfall(fighter, intent: Vector3?): (boolean, string?)
	local state = fighter.state
	local time = now()
	local ok, reason = FighterState.breakfall(state, fighter.combat, time)
	if not ok then
		return false, reason
	end
	local direction = if intent then intent.Unit else -flatLook(fighter)
	fighter.dashUntil = math.max(fighter.dashUntil, time + 0.4)
	self.damageService:push(fighter, direction, 22, 8, 0.15)
	self.characters:refresh(fighter)
	motion(fighter, "Breakfall", { direction = direction, duration = 0.2 })
	return true, nil
end

-- Attacks ---------------------------------------------------------------------------

function CombatService:_runAttack(fighter, attack)
	local state = fighter.state
	local token = attack.token
	local def = attack.def
	local alreadyHit: { [string]: boolean } = {}
	local landed = false
	-- Where the swing started: an attacker can only drift so far during it
	local origin = fighter.root.Position

	self.characters:refresh(fighter)
	CombatEvent:FireAllClients(Event.Attack, {
		attacker = fighter.model,
		kind = attack.kind,
		step = attack.step,
		startup = def.Startup,
		active = def.Active,
		recovery = def.Recovery,
		move = attack.move,
		charge = attack.charge,
	})

	-- Sprint strikes lunge and the Slam dives: the server moves the attacker
	-- (players included), and the movement is excused from the drift check
	local look = flatLook(fighter)
	if def.Lunge then
		fighter.dashUntil = math.max(fighter.dashUntil, attack.recoveryEnd)
		self.damageService:push(fighter, look, def.Lunge, 0, def.Startup)
	elseif def.Dive then
		fighter.dashUntil = math.max(fighter.dashUntil, attack.recoveryEnd)
		self.damageService:setVelocity(fighter, look * 12 + Vector3.new(0, -def.Dive, 0), def.Startup + def.Active)
	end

	local function stillGoing(): boolean
		return FighterState.isCurrent(state, token) and self.characters:isAlive(fighter)
	end

	local function finish()
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
	end

	-- Moves without a hitbox (a prop throw: the prop itself flies) just play out
	if def.Range == nil then
		after(attack.activeEnd, function()
			if stillGoing() then
				FighterState.endActive(state, fighter.combat, token, true)
				finish()
			end
		end)
		return
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
			finish()
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

-- Do these two strikes meet? (Both basic melee swings, theirs aimed at us.)
function CombatService:_clashes(attacker, attack, target, time: number): boolean
	if attack.def.Low or (attack.kind ~= "Light" and attack.kind ~= "Heavy") then
		return false
	end
	local theirs = target.state.attack
	if not theirs or theirs.def.Range == nil or not HitResolver.clashes(theirs, target.combat, time) then
		return false
	end
	return Hitbox.inArc(target.root.Position, target.root.CFrame.LookVector, attacker.root.Position, reachOf(theirs.def, target.combat))
		and self.services.MatchService:canDamage(target, attacker)
end

-- Two strikes met: nobody is hurt, both are pushed apart and briefly stunned
function CombatService:_clash(a, b)
	local time = now()
	-- (what each was swinging, before the stun cancels it)
	local swings = { [a] = a.state.attack, [b] = b.state.attack }
	FighterState.applyStun(a.state, a.combat.Clash.Stun, time)
	FighterState.applyStun(b.state, b.combat.Clash.Stun, time)
	local away = Hitbox.flatDirection(b.root.Position - a.root.Position) or flatLook(a)
	self.damageService:push(a, -away, a.combat.Clash.Pushback, 0)
	self.damageService:push(b, away, b.combat.Clash.Pushback, 0)
	self.characters:refresh(a)
	self.characters:refresh(b)
	CombatEvent:FireAllClients(Event.Clash, {
		a = a.model,
		b = b.model,
		position = (a.root.Position + b.root.Position) / 2,
	})
	-- Like a parry or a dodge, the exchange is also reported as a (harmless) Hit
	-- each way, so anything counting exchanges sees it; clients draw the Clash
	for _, pair in { { a, b }, { b, a } } do
		local attacker, victim = pair[1], pair[2]
		local swing = swings[attacker]
		CombatEvent:FireAllClients(Event.Hit, {
			attacker = attacker.model,
			victim = victim.model,
			result = "Clash",
			damage = 0,
			position = victim.root.Position,
			kind = if swing then swing.kind else "Light",
			move = if swing then swing.move else nil,
			tags = {},
			direction = Hitbox.flatDirection(victim.root.Position - attacker.root.Position) or flatLook(attacker),
		})
	end
end

-- Hits every valid target inside the attack's reach; returns whether any connected
function CombatService:_sweep(attacker, attack, alreadyHit: { [string]: boolean }, startedAt: Vector3): boolean
	local matchService = self.services.MatchService
	local origin = attacker.root.Position
	local time = now()
	-- Characters move on their own client, so check the attacker didn't teleport
	-- somewhere mid-swing to land an impossible hit. Only sideways movement
	-- counts (jumps and falls are fine), at full walking speed (the slow-down
	-- reaches their client a moment late), and pushes or teleports are excused.
	local drift = origin - startedAt
	local sideways = Vector3.new(drift.X, 0, drift.Z).Magnitude
	-- (A sprinting fighter carries a sprint's speed into the swing)
	local baseSpeed = if attacker.state.sprintHeld then attacker.combat.Sprint.Speed else attacker.combat.Movement.WalkSpeed
	local walkSpeed = baseSpeed * attacker.moveBoost * math.max(1, attacker.statusSpeed)
	local allowed = walkSpeed * (time - attack.startedAt) + DRIFT_SLACK
	if sideways > allowed and not self:movedLegitimately(attacker, attack.startedAt) then
		if attacker.player then
			self.antiExploit:flag(attacker.player, "moved too far during an attack")
		end
		return false
	end
	local def = attack.def
	local look = attacker.root.CFrame.LookVector
	local reach = reachOf(def, attacker.combat)
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
			-- Low attacks (the sweep) pass under anyone off the ground
			if def.Low and (self:isInAir(target) or FighterState.isAirborne(target.state, time)) then
				continue
			end
			alreadyHit[target.id] = true
			if self:_clashes(attacker, attack, target, time) then
				self:_clash(attacker, target)
				return true
			end
			local outcome = self:applyHit(attacker, target, def, {
				kind = attack.kind,
				power = attacker.power and attacker.power.id,
				tags = tags,
				melee = true,
				basic = true,
				riposte = attack.riposte,
				move = attack.move,
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

-- Is there a wall (anchored, solid, not a character, not the floor) within
-- `distance` of the target along `direction`?
function CombatService:_wallBehind(target, direction: Vector3, distance: number): boolean
	local ignore = {}
	for _, fighter in self.characters:all() do
		table.insert(ignore, fighter.model)
	end
	local effects = workspace:FindFirstChild("SNEffects")
	if effects then
		table.insert(ignore, effects)
	end
	self.lineOfSight.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(target.root.Position, direction * distance, self.lineOfSight)
	if not result then
		return false
	end
	local part = result.Instance
	return part ~= nil
		and part:IsA("BasePart")
		and part.Anchored
		and part.CanCollide
		and math.abs(result.Normal.Y) < 0.6
end

-- Resolves one hit against one target and applies it: counters and
-- interactive defenses, blocks and parries, super armor, counter hits,
-- punishes, ripostes, perfect dodges, wall splats, knockdowns, damage,
-- knockback, knockout credit, ultimate charge. Every damaging thing in the game
-- comes through here. `hit` uses attack fields (Damage, Hitstun, Knockback,
-- Launch, GuardDamage, Blockable, Parryable, Finisher, Knockdown, GuardBreak).
-- Returns the outcome (with `dealt`), or nil if the target couldn't be hit.
function CombatService:applyHit(attacker, target, hit, opts: HitOptions)
	if not self.characters:isAlive(target) then
		return nil
	end
	local time = now()
	local origin = opts.origin or attacker.root.Position
	local powers = self.services.PowerService
	local defense = self.services.DefenseService
	local statuses = self.services.StatusService
	local move = opts.move or hit.Move

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
			move = move,
			tags = {},
			direction = Hitbox.flatDirection(target.root.Position - origin) or flatLook(attacker),
		})
		return { result = verdict.result, damage = 0, dealt = 0, hitstun = 0, knockback = 0, launch = 0, tags = {} }
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
	-- Counter hits, punishes and perfect dodges are about reading a strike up close
	local melee = opts.melee == true or (opts.kind ~= "Projectile" and hasTag(opts.tags, "Melee"))
	local outcome = HitResolver.resolve(resolveDef, target.combat, attackerSide, targetSide, time, {
		melee = melee,
		basic = opts.basic,
		riposte = opts.riposte,
	})
	local tags = outcome.tags

	-- Dodged a basic strike just as it would land: a perfect dodge leaves the
	-- attacker open (abilities have their own perfect defenses in DefenseService)
	if outcome.result == "Invulnerable" and opts.basic and attacker ~= target and FighterState.claimPerfectDodge(target.state, target.combat, time) then
		FighterState.applyStun(attacker.state, target.combat.Dodge.PerfectPunish, time)
		self.characters:refresh(attacker)
		motion(target, "PerfectDodge", { attacker = attacker.model, duration = target.combat.Dodge.PerfectPunish })
	end

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

	local direction = opts.direction
		or Hitbox.flatDirection(target.root.Position - origin)
		or Hitbox.flatDirection(attacker.root.CFrame.LookVector)
		or Vector3.new(0, 0, -1)
	local knockScale = target.combat.KnockbackTaken or 1

	-- Knocked into a wall hard enough: bounce off it, extra damage and stun
	local splat = target.combat.WallSplat
	if
		splat
		and outcome.result == "Hit"
		and not outcome.armored
		and not tags.otg
		and outcome.knockback * knockScale >= splat.MinKnockback
		and self:_wallBehind(target, direction, splat.CheckDistance)
	then
		tags.wallSplat = true
		outcome.damage += splat.Damage * scale
		outcome.hitstun = math.max(outcome.hitstun, splat.Stun)
		outcome.knockback = splat.Bounce
		outcome.launch = math.min(outcome.launch, splat.Bounce)
		direction = -direction
	end

	HitResolver.apply(outcome, target.combat, attackerSide, targetSide, time)
	local dealt = HitResolver.damageToDeal(outcome, target.humanoid.Health)
	if statuses then
		dealt = statuses:absorb(target, dealt)
	end
	self.damageService:damage(target, dealt)
	outcome.dealt = dealt

	if outcome.knockback > 0 or outcome.launch > 0 then
		self.damageService:push(target, direction, outcome.knockback * knockScale, outcome.launch * knockScale)
	end

	-- A real hit knocks a carried prop out of your hands
	if carried[target.id] and outcome.result == "Hit" and (outcome.hitstun > 0 or tags.knockdown) then
		self:_dropProp(target, "Drop")
	end
	if tags.knockdown and FighterState.isDowned(target.state, time) then
		motion(target, "Knockdown", { direction = direction, duration = target.state.downedUntil - time })
		self:_watchDowned(target)
	elseif tags.otg then
		self:_watchDowned(target)
	end
	if FighterState.isAirborne(target.state, time) then
		self:_watchLanding(target)
	end

	self.characters:refresh(target)
	if outcome.result == "Parried" then
		self.characters:refresh(attacker)
	end
	if powers then
		powers:onHitResolved(attacker, target, outcome, opts)
	end
	for _, listener in hitListeners do
		task.spawn(listener, attacker, target, outcome, opts)
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
		move = move,
		tags = tags,
		direction = direction,
	})
	return outcome
end

-- Knockdowns and juggles ------------------------------------------------------------

-- Announces getting up once the knockdown ends (a tech roll announces itself)
function CombatService:_watchDowned(fighter)
	local state = fighter.state
	local downedAt = state.downedAt
	local function check()
		if not self.characters:isAlive(fighter) or state.downedAt ~= downedAt then
			return
		end
		local time = now()
		if FighterState.isDowned(state, time) then
			after(state.downedUntil, check)
			return
		end
		local mark = markOf(fighter)
		if mark.gotUpFrom == downedAt then
			return
		end
		mark.gotUpFrom = downedAt
		self.characters:refresh(fighter)
		motion(fighter, "GetUp", { duration = math.max(0, state.getUpUntil - time) })
	end
	after(state.downedUntil, check)
end

-- Ends a juggle when the launched fighter is back on the floor
function CombatService:_watchLanding(fighter)
	local mark = markOf(fighter)
	if mark.landing then
		return
	end
	mark.landing = true
	local state = fighter.state
	local landAfter = fighter.combat.Air.LandAfter
	task.spawn(function()
		while self.characters:isAlive(fighter) and FighterState.isAirborne(state, now()) do
			task.wait(0.1)
			local time = now()
			if FighterState.isAirborne(state, time) and time - state.airborneSince >= landAfter and not self:isInAir(fighter) then
				FighterState.land(state, time)
				self.characters:refresh(fighter)
				break
			end
		end
		mark.landing = false
		if self.characters:isAlive(fighter) then
			self.characters:refresh(fighter)
		end
	end)
end

-- Grabs and throws ------------------------------------------------------------------

-- Who a grab would catch right now: the nearest opponent in reach that can be
-- held (not dodging, downed, launched, off the ground or caught by someone else)
function CombatService:_grabTarget(fighter, range: number?)
	local config = fighter.combat
	local grab = config.Grab
	local reach = reachOf({ Range = range or grab.Range, Arc = grab.Arc }, config)
	local origin = fighter.root.Position
	local look = fighter.root.CFrame.LookVector
	local statuses = self.services.StatusService
	local matchService = self.services.MatchService
	local time = now()
	local best, bestDistance = nil, math.huge
	for _, target in self.characters:all() do
		local state = target.state
		if
			target ~= fighter
			and self.characters:isAlive(target)
			and matchService:canDamage(fighter, target)
			and Hitbox.inArc(origin, look, target.root.Position, reach)
			and not FighterState.isInvulnerable(state, time)
			and not FighterState.isDowned(state, time)
			and not FighterState.isAirborne(state, time)
			and not FighterState.isGrabbed(state, time)
			and not FighterState.isHolding(state, time)
			and heldBy[target.id] == nil
			and not self:isInAir(target)
			and not (statuses and (statuses:has(target, "Grabbed") or statuses:has(target, "Sequenced")))
			and self:hasLineOfSight(origin, target.root.Position)
		then
			local distance = (target.root.Position - origin).Magnitude
			if distance < bestDistance then
				best, bestDistance = target, distance
			end
		end
	end
	return best
end

function CombatService:_grab(fighter, intent: Vector3?): (boolean, string?)
	local state = fighter.state
	local config = fighter.combat
	local time = now()
	-- Empty-handed with nobody in reach: pick up a light prop instead
	if not self:_grabTarget(fighter, config.Grab.Range + 1) then
		local prop = self:_findProp(fighter)
		if prop then
			return self:_pickUp(fighter, prop)
		end
	end
	local attack, reason = FighterState.startGrab(state, config, time)
	if not attack then
		return false, reason
	end
	FighterState.dropProtection(state, time)
	self.characters:refresh(fighter)
	CombatEvent:FireAllClients(Event.Attack, {
		attacker = fighter.model,
		kind = attack.kind,
		step = attack.step,
		startup = attack.def.Startup,
		active = attack.def.Active,
		recovery = attack.def.Recovery,
		move = "Grab",
	})
	local token = attack.token
	local function current(): boolean
		return FighterState.isCurrent(state, token) and self.characters:isAlive(fighter)
	end
	after(attack.activeAt, function()
		if not current() then
			return
		end
		local target = self:_grabTarget(fighter)
		if target then
			self:_connectGrab(fighter, target, intent)
			return
		end
		after(attack.activeEnd, function()
			if not current() then
				return
			end
			local late = self:_grabTarget(fighter)
			if late then
				self:_connectGrab(fighter, late, intent)
				return
			end
			-- Missed: the long recovery is the price
			FighterState.endActive(state, config, token, false)
			self.characters:refresh(fighter)
			CombatEvent:FireAllClients(Event.Grab, { attacker = fighter.model, phase = "Whiff" })
			after(attack.recoveryEnd, function()
				if FighterState.isCurrent(state, token) then
					FighterState.finishAttack(state, now())
					self.characters:refresh(fighter)
				end
			end)
		end)
	end)
	return true, nil
end

-- Holds `victim` right in front of (or, for a back throw, behind) the holder,
-- never outside the arena
function CombatService:_placeHeld(holder, victim, look: Vector3, behind: boolean)
	local base = holder.root.Position
	local spot = self:keepInside(holder, base + look * (if behind then -HOLD_OFFSET else HOLD_OFFSET))
	spot = Vector3.new(spot.X, base.Y, spot.Z)
	local facing = Vector3.new(base.X, spot.Y, base.Z)
	if (facing - spot).Magnitude < 0.1 then
		facing = spot - look
	end
	self.characters:teleport(victim, CFrame.lookAt(spot, facing))
end

function CombatService:_connectGrab(attacker, victim, intent: Vector3?)
	local time = now()
	local config = attacker.combat
	FighterState.grabConnect(attacker.state, victim.state, config, time)
	local look = flatLook(attacker)
	local back = isBack(look, intent)
	holds[attacker.id] = { victimId = victim.id, at = time, back = back }
	heldBy[victim.id] = attacker.id
	if carried[victim.id] then
		self:_dropProp(victim, "Drop")
	end
	self:_placeHeld(attacker, victim, look, false)
	self.characters:refresh(attacker)
	self.characters:refresh(victim)
	CombatEvent:FireAllClients(Event.Grab, {
		attacker = attacker.model,
		victim = victim.model,
		phase = "Hold",
		direction = if back then -look else look,
	})
	after(time + config.Grab.Hold, function()
		self:_throw(attacker, victim, time)
	end)
end

-- The hold is over: throw forward (or backward), unless the hold was broken
function CombatService:_throw(attacker, victim, connectedAt: number)
	local hold = holds[attacker.id]
	if not hold or hold.at ~= connectedAt or hold.victimId ~= victim.id then
		return
	end
	holds[attacker.id] = nil
	heldBy[victim.id] = nil
	local time = now()
	local intact = self.characters:isAlive(attacker)
		and self.characters:isAlive(victim)
		and attacker.state.holdingId == victim.id
		and victim.state.grabbedById == attacker.id
		-- Hit while holding someone: they slip free
		and not FighterState.isStunned(attacker.state, time)
	FighterState.releaseGrab(attacker.state, victim.state, time)
	if not intact then
		self.characters:refresh(attacker)
		self.characters:refresh(victim)
		CombatEvent:FireAllClients(Event.Grab, { attacker = attacker.model, victim = victim.model, phase = "Whiff" })
		return
	end
	local grab = attacker.combat.Grab
	local look = flatLook(attacker)
	local direction = if hold.back then -look else look
	-- Re-place the victim (their own client can't drag them anywhere meanwhile)
	self:_placeHeld(attacker, victim, look, hold.back)
	if hold.back then
		local position = attacker.root.Position
		attacker.root.CFrame = CFrame.lookAt(position, position + direction)
	end
	CombatEvent:FireAllClients(Event.Grab, {
		attacker = attacker.model,
		victim = victim.model,
		phase = "Throw",
		direction = direction,
	})
	self:applyHit(attacker, victim, {
		Move = "Throw",
		Damage = if hold.back then grab.BackDamage else grab.Damage,
		Hitstun = grab.Hitstun,
		Knockback = grab.Knockback,
		Launch = grab.Launch,
		Knockdown = true,
		Blockable = false,
		Parryable = false,
		Finisher = true,
	}, {
		kind = "Grab",
		power = attacker.power and attacker.power.id,
		tags = { "Grab" },
		direction = direction,
		noDefense = true,
		move = "Throw",
	})
	self.characters:refresh(attacker)
end

-- The grabbed fighter broke the hold in time: both break apart, no damage
function CombatService:_tech(fighter): (boolean, string?)
	local time = now()
	local holderId = fighter.state.grabbedById
	local holder = if holderId then self.characters:getById(holderId) else nil
	if holderId then
		holds[holderId] = nil
	end
	heldBy[fighter.id] = nil
	FighterState.releaseGrab(holder and holder.state, fighter.state, time)
	local pushback = fighter.combat.Grab.TechPushback
	if holder then
		local away = Hitbox.flatDirection(fighter.root.Position - holder.root.Position) or -flatLook(fighter)
		self.damageService:push(fighter, away, pushback, 0)
		self.damageService:push(holder, -away, pushback, 0)
		self.characters:refresh(holder)
	end
	self.characters:refresh(fighter)
	CombatEvent:FireAllClients(Event.Grab, {
		attacker = if holder then holder.model else nil,
		victim = fighter.model,
		phase = "Tech",
	})
	return true, nil
end

-- Props -------------------------------------------------------------------------------

-- The nearest light arena prop within reach that nobody holds
function CombatService:_findProp(fighter): BasePart?
	local reach = fighter.combat.Carry.Reach
	local best, bestDistance = nil, reach
	local origin = fighter.root.Position
	for _, prop in CollectionService:GetTagged(Protocol.Tag.Throwable) do
		-- (pcall: a prop being torn down mid-check is simply skipped)
		local ok, distance = pcall(function()
			if prop:IsA("BasePart") and prop:IsDescendantOf(workspace) and not prop:GetAttribute("Held") then
				local weight = prop:GetAttribute("Weight")
				if typeof(weight) == "number" and weight <= 1 then
					return (prop.Position - origin).Magnitude
				end
			end
			return nil
		end)
		if ok and distance and distance <= bestDistance then
			best, bestDistance = prop, distance
		end
	end
	return best
end

function CombatService:_pickUp(fighter, prop: BasePart): (boolean, string?)
	local state = fighter.state
	local ok, reason = FighterState.pickUp(state, prop.Name, now())
	if not ok then
		return false, reason
	end
	-- The arena's prop hides; a copy rides overhead in the fighter's hands
	prop:SetAttribute("Held", true)
	prop:SetAttribute("SavedTransparency", prop.Transparency)
	local visible = prop.Transparency
	prop.Transparency = 1
	prop.CanCollide = false
	prop.CanQuery = false
	local copy = prop:Clone()
	CollectionService:RemoveTag(copy, Protocol.Tag.Throwable)
	for _, name in { "Held", "SavedTransparency", "Weight", "HomeCFrame" } do
		copy:SetAttribute(name, nil)
	end
	copy.Name = CARRY_NAME
	copy.Transparency = visible
	copy.Anchored = false
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.Massless = true
	copy.CFrame = fighter.root.CFrame * CFrame.new(0, 2.6 + copy.Size.Y / 2, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = fighter.root
	weld.Part1 = copy
	weld.Parent = copy
	copy.Parent = fighter.model
	carryTokens += 1
	local token = carryTokens
	carried[fighter.id] = { prop = prop, copy = copy, token = token }
	self.characters:refresh(fighter)
	motion(fighter, "PickUp", { prop = prop.Name })
	-- Put down by itself after a while
	task.delay(fighter.combat.Carry.MaxDuration, function()
		local entry = carried[fighter.id]
		if entry and entry.token == token then
			self:_dropProp(fighter, "Drop")
		end
	end)
	return true, nil
end

-- Lets go of a carried prop. "Drop" sets it down in front, "Throw" hides it
-- (it flies as a projectile) and sends it home later, "Cleanup" sends it home now.
function CombatService:_dropProp(fighter, how: string): boolean
	local entry = carried[fighter.id]
	carried[fighter.id] = nil
	local name = FighterState.dropCarried(fighter.state)
	if not entry then
		if name ~= nil then
			self.characters:refresh(fighter)
		end
		return name ~= nil
	end
	local copy = entry.copy
	if copy then
		pcall(copy.Destroy, copy)
	end
	local prop = entry.prop
	local ok, err = pcall(self._placeProp, self, fighter, prop, how)
	if not ok then
		warn("[Combat] couldn't put a prop back: " .. tostring(err))
	end
	if self.characters:getById(fighter.id) == fighter then
		self.characters:refresh(fighter)
		if how == "Drop" then
			motion(fighter, "Drop", { prop = name })
		end
	end
	return true
end

-- Where a released prop goes: thrown ones come home later, dropped ones are
-- set down in front of the fighter, anything else goes home now
function CombatService:_placeProp(fighter, prop: BasePart, how: string)
	if how == "Throw" then
		task.delay(fighter.combat.Carry.ReturnDelay, function()
			pcall(returnProp, prop)
		end)
	elseif how == "Drop" and prop.Parent and fighter.root.Parent then
		local home = prop:GetAttribute("HomeCFrame")
		local base = fighter.root.Position
		local spot = self:keepInside(fighter, base + flatLook(fighter) * HOLD_OFFSET)
		if typeof(home) == "CFrame" then
			prop.CFrame = CFrame.new(spot.X, home.Position.Y, spot.Z) * home.Rotation
		else
			prop.CFrame = CFrame.new(spot.X, base.Y - 3 + prop.Size.Y / 2, spot.Z)
		end
		local saved = prop:GetAttribute("SavedTransparency")
		prop.Transparency = if typeof(saved) == "number" then saved else 0
		prop.CanCollide = true
		prop.CanQuery = true
		prop:SetAttribute("Held", nil)
	else
		returnProp(prop)
	end
end

-- Light while carrying: throw the prop where the fighter aims (an aim payload's
-- direction, else where they face). It flies as a server projectile.
function CombatService:_throwProp(fighter, payload: any): (boolean, string?)
	local state = fighter.state
	local config = fighter.combat
	local carry = config.Carry
	local entry = carried[fighter.id]
	-- The throw is a short move of its own (it can't start while stunned or busy)
	local name = state.carrying
	state.carrying = nil
	local attack, reason = FighterState.startVariant(state, config, "Light", carry.Throw, now())
	if not attack then
		state.carrying = name
		return false, reason
	end
	state.carrying = name
	FighterState.dropProtection(state, now())
	local aim = if typeof(payload) == "table" then self.antiExploit.direction(rawget(payload, "aim")) else nil
	local look = aim or flatLook(fighter)
	self:_dropProp(fighter, "Throw")
	local prop = entry and entry.prop
	if prop then
		local pitch = math.rad(carry.ThrowPitch)
		local largest = math.max(prop.Size.X, prop.Size.Y, prop.Size.Z)
		self.services.ProjectileService:spawn(fighter, {
			-- Drawn by Strong Dude's client "Prop" visual (it draws any thrown object)
			power = "StrongDude",
			ability = "PropThrow",
			visual = "Prop",
			origin = fighter.root.Position + Vector3.new(0, 2.5, 0) + look * 2,
			direction = look * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0),
			speed = carry.ThrowSpeed,
			gravity = carry.ThrowGravity,
			radius = math.clamp(largest / 2, 0.8, 3),
			lifetime = 2,
			range = 90,
			hit = {
				Damage = carry.Damage,
				Hitstun = 0.6,
				Knockback = carry.Knockback,
				Launch = 8,
				GuardDamage = carry.Damage * 2,
				Move = "PropThrow",
			},
			tags = { "Projectile", "Small" },
			redirectable = true,
			interceptable = true,
			data = {
				size = prop.Size,
				color = prop.Color,
				material = prop.Material.Name,
				shape = if prop:IsA("Part") then prop.Shape.Name else "Block",
			},
		})
	end
	self:_runAttack(fighter, attack)
	return true, nil
end

-- Cleanup -------------------------------------------------------------------------------

-- Lets go of everything physical a fighter is part of: a grab either way, a
-- carried prop, a charge. Runs on knockouts, respawns, match ends, leaving and
-- power changes, so nothing can outlive the fight it belongs to.
function CombatService:resetFighter(fighter)
	local id = fighter.id
	local time = now()
	local hold = holds[id]
	if hold then
		holds[id] = nil
		heldBy[hold.victimId] = nil
		local victim = self.characters:getById(hold.victimId)
		if victim and victim.state.grabbedById == id then
			FighterState.releaseGrab(nil, victim.state, time)
			self.characters:refresh(victim)
		end
	end
	local holderId = heldBy[id]
	if holderId then
		heldBy[id] = nil
		holds[holderId] = nil
		local holder = self.characters:getById(holderId)
		if holder and holder.state.holdingId == id then
			FighterState.releaseGrab(holder.state, nil, time)
			self.characters:refresh(holder)
		end
	end
	local state = fighter.state
	if state.holdingId ~= nil then
		FighterState.releaseGrab(state, nil, time)
	end
	if state.grabbedById ~= nil then
		FighterState.releaseGrab(nil, state, time)
	end
	if FighterState.isCharging(state, time) then
		FighterState.cancelAttack(state)
	end
	self:_dropProp(fighter, "Cleanup")
	local mark = marks[id]
	if mark then
		mark.blockHeld = false
	end
	if self.characters:getById(id) == fighter then
		self.characters:refresh(fighter)
	end
end

return CombatService
