-- Runs abilities. A player asks (Remotes.AbilityRequest: ability id + where
-- they're aiming); the server checks everything before anything happens:
-- the ability belongs to the fighter's power, is equipped (or is their
-- degree's ultimate), the degree allows it, combat is allowed, they aren't
-- stunned, busy, sealed or frozen, the cooldown is over, and they can pay its
-- cost (resource, or a full ultimate bar). Only then is the cost taken and the
-- power's handler run with an AbilityKit context.
-- CPU opponents call AbilityService:use directly, through the same checks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local FighterState = require(ReplicatedStorage.Shared.Combat.FighterState)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local AbilityKit = require(script.Parent.Parent.Combat.AbilityKit)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AbilityRequest = Remotes:WaitForChild("AbilityRequest") :: RemoteEvent
local AbilityEvent = Remotes:WaitForChild("AbilityEvent") :: RemoteEvent

local Event = Protocol.AbilityEvent
local ABILITIES = Combat.Abilities
local ULTIMATE = Combat.Ultimate

local AbilityService = {}

-- callback(fighter, abilityId, def, basic) after an ability starts
local usedListeners: { (any, string, any, string?) -> () } = {}

function AbilityService:onUsed(callback: (any, string, any, string?) -> ())
	table.insert(usedListeners, callback)
end

-- Small delay added to scheduled steps so they never run a hair early
local SCHEDULE_SLACK = 0.005

local function now(): number
	return workspace:GetServerTimeNow()
end

local function finiteVector(value: any): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	if value.X ~= value.X or value.Y ~= value.Y or value.Z ~= value.Z then
		return nil
	end
	if math.abs(value.X) > 1e6 or math.abs(value.Y) > 1e6 or math.abs(value.Z) > 1e6 then
		return nil
	end
	return value
end

function AbilityService:Init(services)
	self.services = services
	self.characters = services.CharacterService
	self.antiExploit = services.AntiExploitService
end

function AbilityService:Start()
	AbilityRequest.OnServerEvent:Connect(function(player, abilityId, aim)
		if not self.antiExploit:allow(player, "Ability") then
			return
		end
		if typeof(abilityId) ~= "string" or #abilityId > 40 then
			self.antiExploit:flag(player, "junk ability request")
			return
		end
		local fighter = self.characters:getByPlayer(player)
		if not fighter or not self.characters:isAlive(fighter) then
			return
		end
		local ok, reason = self:use(fighter, abilityId, aim)
		if not ok and reason then
			AbilityEvent:FireClient(player, Event.Rejected, { ability = abilityId, reason = reason })
		end
	end)
end

-- Turns whatever the client sent as its aim into safe values: a flat unit
-- direction (defaults to where the character faces), a 3D look direction, and
-- an optional target point no farther than the ability can reach.
function AbilityService:_aim(fighter, def, aim: any)
	local root = fighter.root
	local facing = Hitbox.flatDirection(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	local result = { direction = facing, look = root.CFrame.LookVector, point = nil :: Vector3? }
	if typeof(aim) ~= "table" then
		return result
	end
	local direction = finiteVector(aim.direction)
	if direction and direction.Magnitude > 0.01 then
		result.look = direction.Unit
		result.direction = Hitbox.flatDirection(direction) or facing
	end
	local point = finiteVector(aim.point)
	if point then
		local reach = (def.range or def.reach or 40) + ABILITIES.AimSlack
		local offset = point - root.Position
		if offset.Magnitude > reach then
			point = root.Position + offset.Unit * reach
		end
		result.point = point
	end
	return result
end

-- Is this ability usable by this fighter right now? Returns (def, reason).
-- `basic` is set when it stands in for the Light or Heavy attack.
-- What this use costs: the definition's cost, unless the power module says
-- otherwise with costFor (Shapeshifter: changing back from a form is free)
local function costOf(fighter, runtime, def): number
	local module = runtime.module
	if module and module.costFor then
		local ok, cost = pcall(module.costFor, fighter, runtime, def)
		if ok and typeof(cost) == "number" and cost == cost and cost >= 0 then
			return cost
		end
	end
	return def.cost or 0
end

function AbilityService:_validate(fighter, abilityId: string, basic: string?)
	local runtime = fighter.power
	if not runtime then
		return nil, "no power"
	end
	local def = Powers.abilityFor(runtime.id, abilityId, runtime.degree)
	if not def then
		self:_flag(fighter, "ability from another power")
		return nil, "unknown"
	end
	local isUltimate = abilityId == runtime.ultimate
	if basic then
		if Powers.basicFor(runtime.id, runtime.degree, runtime.form, basic) ~= abilityId then
			return nil, "not equipped"
		end
	elseif def.basicOnly or (not isUltimate and not table.find(runtime.loadout, abilityId)) then
		return nil, "not equipped"
	end
	if (def.minDegree or 1) > runtime.degree then
		return nil, "degree"
	end
	local ok, reason = self.services.CombatService:canAct(fighter)
	if not ok then
		return nil, reason
	end
	local statuses = self.services.StatusService
	if statuses:has(fighter, "Sealed") then
		return nil, "sealed"
	end
	local readyAt = runtime.cooldowns[abilityId] or 0
	if now() + ABILITIES.CooldownLeeway < readyAt then
		return nil, "cooldown"
	end
	if isUltimate and not basic then
		if runtime.ult + 1e-6 < ULTIMATE.Max then
			return nil, "charge"
		end
	elseif runtime.resource + 1e-6 < costOf(fighter, runtime, def) then
		return nil, "resource"
	end
	return def, nil
end

function AbilityService:_flag(fighter, reason: string)
	if fighter.player then
		self.antiExploit:flag(fighter.player, reason)
	end
end

-- Uses an ability. Returns (ok, reason). opts.basic = "Light" | "Heavy" when
-- it's the power's replacement for a basic attack.
function AbilityService:use(fighter, abilityId: string, aim: any?, opts: { basic: string? }?): (boolean, string?)
	local basic = opts and opts.basic
	local def, reason = self:_validate(fighter, abilityId, basic)
	if not def then
		return false, reason
	end
	local runtime = fighter.power
	local module = runtime.module
	local handler = module and module.abilities and module.abilities[abilityId]
	if not handler then
		return false, "unavailable"
	end
	local aimData = self:_aim(fighter, def, aim)

	-- Power-specific gates (e.g. a form that has to be active, a prop nearby)
	if module.canUse then
		local allowed, why = module.canUse(fighter, runtime, def, aimData)
		if not allowed then
			return false, why or "unavailable"
		end
	end

	local time = now()
	local attack = nil
	if not def.instant then
		local timing = {
			Startup = def.startup or 0,
			Active = def.active or 0,
			Recovery = def.recovery or 0,
			MoveSpeed = if def.moveSpeed ~= nil then def.moveSpeed else ABILITIES.MoveSpeed,
			AutoRotate = def.autoRotate,
			Armor = def.armor,
		}
		local started, why = FighterState.startAbility(fighter.state, timing, time)
		if not started then
			return false, why
		end
		attack = started
		-- NPCs are turned to face their aim here; players already turned on their
		-- own screen (and abilities use the validated aim, not the facing)
		if fighter.npc then
			local root = fighter.root
			root.CFrame = CFrame.lookAt(root.Position, root.Position + aimData.direction)
		end
	end

	-- Pay
	if abilityId == runtime.ultimate and not basic then
		runtime.ult = 0
	else
		local cost = costOf(fighter, runtime, def)
		if cost > 0 then
			self.services.PowerService:spend(fighter, cost)
		end
	end
	self.services.PowerService:setCooldown(fighter, abilityId, time + self.services.PowerService:cooldownFor(fighter, def))
	FighterState.dropProtection(fighter.state, time)
	self.characters:refresh(fighter)

	AbilityEvent:FireAllClients(Event.Cast, {
		fighter = fighter.model,
		power = runtime.id,
		ability = abilityId,
		startup = def.startup or 0,
		active = def.active or 0,
		direction = aimData.direction,
		basic = basic,
	})

	for _, listener in usedListeners do
		task.spawn(listener, fighter, abilityId, def, basic)
	end

	local ctx = AbilityKit.new(fighter, runtime, def, aimData, attack)
	task.spawn(function()
		local ok, err = pcall(handler, ctx)
		if not ok then
			warn(`[Abilities] {runtime.id}.{abilityId} failed: {err}`)
			if attack and FighterState.isCurrent(fighter.state, attack.token) then
				FighterState.cancelAttack(fighter.state)
				self.characters:refresh(fighter)
			end
		end
		ctx:_runCleanups()
	end)

	if attack then
		self:_scheduleFinish(fighter, attack)
	end
	return true, nil
end

-- Clears the cast from the fighter's state once its recovery is over (the
-- handler may have ended it early or lengthened it)
function AbilityService:_scheduleFinish(fighter, attack)
	local function check()
		if not FighterState.isCurrent(fighter.state, attack.token) then
			return
		end
		local remaining = attack.recoveryEnd - now()
		if remaining > 0 then
			task.delay(remaining + SCHEDULE_SLACK, check)
			return
		end
		FighterState.finishAttack(fighter.state, now())
		self.characters:refresh(fighter)
	end
	task.delay(math.max(0, attack.recoveryEnd - now()) + SCHEDULE_SLACK, check)
end

return AbilityService
