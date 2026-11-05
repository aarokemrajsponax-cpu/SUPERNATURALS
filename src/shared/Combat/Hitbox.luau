-- Attack geometry: who an attack can reach, and which way a fighter is facing.
-- Pure math on Vector3s, so it behaves the same on the server and in tests.

local Hitbox = {}

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- A flat unit direction, or nil when the vector is (nearly) vertical or zero
function Hitbox.flatDirection(vector: Vector3): Vector3?
	local flattened = flat(vector)
	if flattened.Magnitude < 1e-4 then
		return nil
	end
	return flattened.Unit
end

export type Reach = {
	range: number,
	arc: number,
	verticalReach: number,
	targetRadius: number,
	pointBlank: number,
}

-- Is the target inside the attack's cone in front of the attacker?
function Hitbox.inArc(origin: Vector3, look: Vector3, target: Vector3, reach: Reach): boolean
	local offset = target - origin
	if math.abs(offset.Y) > reach.verticalReach then
		return false
	end
	local distance = flat(offset).Magnitude
	if distance > reach.range + reach.targetRadius then
		return false
	end
	if distance <= reach.pointBlank then
		return true
	end
	local facing = Hitbox.flatDirection(look)
	local toTarget = Hitbox.flatDirection(offset)
	if not facing or not toTarget then
		return true
	end
	return facing:Dot(toTarget) >= math.cos(math.rad(reach.arc / 2))
end

-- Is `from` within the front arc of a fighter at `position` looking along `look`?
function Hitbox.isInFront(position: Vector3, look: Vector3, from: Vector3, arc: number): boolean
	local facing = Hitbox.flatDirection(look)
	local toSource = Hitbox.flatDirection(from - position)
	if not facing or not toSource then
		-- Directly on top of each other: treat as in front
		return true
	end
	return facing:Dot(toSource) >= math.cos(math.rad(arc / 2))
end

return Hitbox
