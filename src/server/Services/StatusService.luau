-- Status effects on fighters: slows, roots, freezes, marks, burns, shields,
-- armor, concealment, distortion, traps, gravity changes and more. Every status
-- has a hard maximum length (Config/Combat Statuses), ends on its own, and is
-- cleared when its fighter is knocked out, respawns, leaves or a match resets
-- them. Clients see them as "SNS_<id>" attributes (the time they end).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local FighterState = require(ReplicatedStorage.Shared.Combat.FighterState)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local StatusService = {}

local PREFIX = Protocol.Attribute.StatusPrefix
local LIMITS = Combat.Statuses
-- Saved part transparency while concealed (separate from the owner panel's invisibility)
local CONCEAL_SAVED = "SNConcealSaved"
local GRAVITY_NAME = "SNStatusGravity"

export type Status = {
	id: string,
	endsAt: number,
	-- Who caused it (for burn credit and marks); nil for self-applied buffs
	sourceId: string?,
	-- Strength: slow/haste speed multiplier, burn damage per tick, shield amount,
	-- armor's damage reduction, gravity share...
	magnitude: number,
	data: { [string]: any },
	token: number,
}

local function now(): number
	return workspace:GetServerTimeNow()
end

function StatusService:Init(services)
	self.services = services
	self.characters = services.CharacterService
end

function StatusService:Start()
	self.characters:onKnockout(function(victim)
		self:clearAll(victim)
	end)
	self.characters:onRestored(function(fighter)
		self:clearAll(fighter)
	end)
	self.characters:onUnregistered(function(fighter)
		self:clearAll(fighter)
	end)
end

local function list(fighter): { [string]: Status }
	local statuses = fighter.statuses
	if not statuses then
		statuses = {}
		fighter.statuses = statuses
	end
	return statuses
end

-- Starts (or extends) a status. The duration is capped at the status's maximum,
-- counted from now, so stacking can never make it last forever.
-- opts: { source = fighter?, magnitude = number?, data = table? }
function StatusService:apply(fighter, statusId: string, duration: number, opts: { source: any?, magnitude: number?, data: { [string]: any }? }?): Status?
	local limit = LIMITS[statusId]
	if not limit or duration <= 0 or not self.characters:isAlive(fighter) then
		return nil
	end
	local options = opts or {}
	local time = now()
	local statuses = list(fighter)
	local endsAt = time + math.min(duration, limit.max)
	local existing = statuses[statusId]
	local status: Status
	if existing then
		existing.endsAt = math.min(math.max(existing.endsAt, endsAt), time + limit.max)
		existing.magnitude = options.magnitude or existing.magnitude
		existing.sourceId = if options.source then options.source.id else existing.sourceId
		if options.data then
			for key, value in options.data do
				existing.data[key] = value
			end
		end
		existing.token += 1
		status = existing
	else
		status = {
			id = statusId,
			endsAt = endsAt,
			sourceId = if options.source then options.source.id else nil,
			magnitude = options.magnitude or 1,
			data = options.data or {},
			token = 1,
		}
		statuses[statusId] = status
		self:_begin(fighter, status)
	end
	fighter.model:SetAttribute(PREFIX .. statusId, status.endsAt)
	self:_applyMovement(fighter)
	if statusId == "Freeze" then
		FighterState.applyStun(fighter.state, status.endsAt - time, time)
		self.characters:refresh(fighter)
	end

	local token = status.token
	task.delay(status.endsAt - time + 0.02, function()
		local current = list(fighter)[statusId]
		if current == status and current.token == token then
			self:remove(fighter, statusId)
		end
	end)
	return status
end

function StatusService:remove(fighter, statusId: string)
	local statuses = list(fighter)
	local status = statuses[statusId]
	if not status then
		return
	end
	statuses[statusId] = nil
	status.token += 1
	self:_finish(fighter, status)
	if fighter.model.Parent then
		fighter.model:SetAttribute(PREFIX .. statusId, nil)
	end
	self:_applyMovement(fighter)
end

function StatusService:clearAll(fighter)
	local statuses = fighter.statuses
	if not statuses then
		return
	end
	for statusId in table.clone(statuses) do
		self:remove(fighter, statusId)
	end
end

function StatusService:has(fighter, statusId: string): boolean
	local status = fighter.statuses and fighter.statuses[statusId]
	return status ~= nil and now() < status.endsAt
end

function StatusService:get(fighter, statusId: string): Status?
	local status = fighter.statuses and fighter.statuses[statusId]
	if status and now() < status.endsAt then
		return status
	end
	return nil
end

-- Damage taken is multiplied by this (exposed takes more, armored less)
function StatusService:damageTakenMultiplier(fighter): number
	local multiplier = 1
	local vulnerable = self:get(fighter, "Vulnerable")
	if vulnerable then
		multiplier *= 1 + math.clamp(vulnerable.magnitude, 0, 0.5)
	end
	local armor = self:get(fighter, "Armor")
	if armor then
		multiplier *= 1 - math.clamp(armor.magnitude, 0, 0.7)
	end
	return multiplier
end

-- A shield soaks up damage first; returns what gets through
function StatusService:absorb(fighter, amount: number): number
	local shield = self:get(fighter, "Shield")
	if not shield or amount <= 0 then
		return amount
	end
	local soaked = math.min(shield.magnitude, amount)
	shield.magnitude -= soaked
	if shield.magnitude <= 0.01 then
		self:remove(fighter, "Shield")
	end
	return amount - soaked
end

-- Movement ------------------------------------------------------------------------

function StatusService:_applyMovement(fighter)
	local speed = 1
	local slow = self:get(fighter, "Slow")
	if slow then
		speed *= math.clamp(slow.magnitude, 0.3, 1)
	end
	local haste = self:get(fighter, "Haste")
	if haste then
		speed *= math.clamp(haste.magnitude, 1, 1.8)
	end
	if self:get(fighter, "Distort") then
		speed *= 0.85
	end
	local rooted = self:get(fighter, "Root") ~= nil or self:get(fighter, "Grabbed") ~= nil
	if fighter.statusSpeed ~= speed or fighter.rooted ~= rooted then
		fighter.statusSpeed = speed
		fighter.rooted = rooted
		self.characters:refresh(fighter)
	end
end

-- Effects that need something done when they start or end --------------------------

function StatusService:_begin(fighter, status: Status)
	local id = status.id
	if id == "Burn" then
		task.spawn(self._burn, self, fighter, status)
	elseif id == "Concealed" then
		self:_setConcealed(fighter, status.magnitude)
	elseif id == "Gravity" then
		self:_setGravity(fighter, status)
	elseif id == "Trapped" then
		task.spawn(self._holdInTrap, self, fighter, status)
	end
end

function StatusService:_finish(fighter, status: Status)
	local id = status.id
	if id == "Concealed" then
		self:_setConcealed(fighter, nil)
	elseif id == "Gravity" then
		local root = fighter.root
		for _, name in { GRAVITY_NAME, GRAVITY_NAME .. "Force" } do
			local item = root:FindFirstChild(name)
			if item then
				item:Destroy()
			end
		end
	end
	local onEnd = status.data.onEnd
	if typeof(onEnd) == "function" then
		task.spawn(onEnd, fighter, status)
	end
end

-- Damage over time, credited to whoever applied it
function StatusService:_burn(fighter, status: Status)
	local interval = LIMITS.Burn.tick or 0.5
	while true do
		task.wait(interval)
		local current = fighter.statuses and fighter.statuses.Burn
		if current ~= status or not self.characters:isAlive(fighter) or now() >= status.endsAt then
			return
		end
		local source = if status.sourceId then self.characters:getById(status.sourceId) else nil
		local hit = { Damage = status.magnitude, Hitstun = 0, Knockback = 0, Launch = 0, GuardDamage = 0, Blockable = false, Parryable = false }
		if source and self.services.MatchService:canDamage(source, fighter) then
			self.services.CombatService:applyHit(source, fighter, hit, {
				kind = "Status",
				power = status.data.power,
				ability = status.data.ability,
				noDefense = true,
			})
		else
			-- The burner is gone: the burn still hurts, but nobody gets credit
			self.services.DamageService:damage(fighter, math.min(status.magnitude, fighter.humanoid.Health - 1))
		end
	end
end

-- Mostly see-through for everyone; magnitude is how transparent (0..1)
function StatusService:_setConcealed(fighter, transparency: number?)
	for _, item in fighter.model:GetDescendants() do
		if (item:IsA("BasePart") or item:IsA("Decal")) and item.Name ~= "HumanoidRootPart" then
			local saved = item:GetAttribute(CONCEAL_SAVED)
			if transparency then
				if saved == nil then
					item:SetAttribute(CONCEAL_SAVED, item.Transparency)
					saved = item.Transparency
				end
				item.Transparency = math.max(saved :: number, transparency)
			elseif typeof(saved) == "number" then
				item.Transparency = saved
				item:SetAttribute(CONCEAL_SAVED, nil)
			end
		end
	end
end

-- Gravity: magnitude is the share of normal gravity felt (0.3 floaty, 1.8 heavy)
function StatusService:_setGravity(fighter, status: Status)
	local root = fighter.root
	local attachment = Instance.new("Attachment")
	attachment.Name = GRAVITY_NAME
	attachment.Parent = root
	local force = Instance.new("VectorForce")
	force.Name = GRAVITY_NAME .. "Force"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	local mass = root.AssemblyMass
	local share = math.clamp(status.magnitude, 0.2, 2)
	local lift = if mass ~= mass or mass == math.huge then 0 else mass * workspace.Gravity * (1 - share)
	force.Force = Vector3.new(0, lift, 0)
	force.Parent = root
end

-- Trapped: kept inside data.center/data.radius until the trap ends
function StatusService:_holdInTrap(fighter, status: Status)
	local center = status.data.center
	local radius = status.data.radius
	if typeof(center) ~= "Vector3" or typeof(radius) ~= "number" then
		return
	end
	while fighter.statuses and fighter.statuses.Trapped == status and now() < status.endsAt do
		local offset = fighter.root.Position - center
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude > radius + 1 and self.characters:isAlive(fighter) then
			local back = center + (if flat.Magnitude > 0.01 then flat.Unit else Vector3.zero) * (radius * 0.6)
			self.characters:teleport(fighter, CFrame.new(Vector3.new(back.X, fighter.root.Position.Y, back.Z)) * fighter.root.CFrame.Rotation)
		end
		task.wait(0.1)
	end
end

return StatusService
