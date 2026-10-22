-- The physical side of getting hit: losing health and being knocked back.
-- Knockback uses a short-lived LinearVelocity on the victim's root part. The
-- server creates it, it replicates to whoever simulates the character (the
-- player's own client, or the server for NPCs), and it removes itself.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)

local DamageService = {}

local KNOCKBACK_NAME = "SNKnockback"

function DamageService:Init(services)
	self.characters = services.CharacterService
end

function DamageService:damage(victim, amount: number)
	if amount <= 0 then
		return
	end
	local humanoid = victim.humanoid
	if humanoid.Health <= 0 then
		return
	end
	humanoid.Health = math.max(0, humanoid.Health - amount)
end

-- Push along a flat unit `direction` with `horizontal` speed, plus `vertical` lift
function DamageService:push(fighter, direction: Vector3, horizontal: number, vertical: number, duration: number?)
	self:setVelocity(fighter, direction * horizontal + Vector3.new(0, vertical, 0), duration)
end

-- Holds a fighter at `velocity` for a moment (knockback, dodges, event pulls)
function DamageService:setVelocity(fighter, velocity: Vector3, duration: number?)
	local root = fighter.root
	if not root or root.Parent == nil or root.Anchored then
		return
	end
	if velocity.Magnitude < 1 then
		return
	end

	-- Only one push at a time; a newer hit replaces the old push
	for _, child in root:GetChildren() do
		if child.Name == KNOCKBACK_NAME then
			child:Destroy()
		end
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = KNOCKBACK_NAME
	attachment.Parent = root

	local mover = Instance.new("LinearVelocity")
	mover.Name = KNOCKBACK_NAME
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.VectorVelocity = velocity
	mover.MaxForce = math.huge
	mover.Parent = root

	local lifetime = duration or Combat.KnockbackDuration
	Debris:AddItem(mover, lifetime)
	Debris:AddItem(attachment, lifetime)
end

return DamageService
