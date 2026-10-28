-- How Strong Dude looks: heavy, physical, earthy. Dust and rock, cracked
-- ground, shockwaves, a glow in his fists that grows with each degree, and the
-- huge orange-gold wind-up of World Breaker.

local Strong = {}

local rgb = Color3.fromRGB
local EMBER = rgb(255, 150, 60)
local GOLD = rgb(255, 210, 120)
local DUST = rgb(170, 150, 125)
local ROCK = rgb(90, 80, 72)
local LAVA = rgb(255, 90, 30)

local function hands(model: Model): { BasePart }
	local list = {}
	for _, name in { "RightHand", "LeftHand", "Right Arm", "Left Arm" } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(list, part)
		end
	end
	return list
end

local function feet(kit): Vector3
	return if kit.root then kit.root.Position - Vector3.new(0, 2.9, 0) else Vector3.zero
end

local function dustRing(kit, position: Vector3, radius: number)
	kit.Vfx.burst(position + Vector3.new(0, 0.5, 0), {
		color = DUST,
		lightEmission = 0,
		texture = "rbxasset://textures/particles/smoke_main.dds",
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) }),
		transparency = NumberSequence.new(0.3, 1),
		lifetime = NumberRange.new(0.6, 1.1),
		speed = NumberRange.new(radius * 1.2, radius * 2),
		spread = Vector2.new(5, 180),
		drag = 4,
		count = 26,
	})
end

-- A shockwave across the ground: ring, cracks, dust, rocks and a thump
local function groundImpact(kit, position: Vector3, radius: number, big: boolean)
	local Vfx = kit.Vfx
	Vfx.groundRing(position + Vector3.new(0, 0.1, 0), EMBER, 2, radius * 2.2, 0.45)
	Vfx.groundRing(position + Vector3.new(0, 0.15, 0), DUST, 2, radius * 1.6, 0.6)
	Vfx.shockwave(position + Vector3.new(0, 1, 0), EMBER, 3, radius * 1.4, 0.35)
	Vfx.cracks(position, radius * 0.9, LAVA, if big then 12 else 7, if big then 3.5 else 2.2)
	Vfx.debris(position, if big then 14 else 7, ROCK, Enum.Material.Slate, if big then 55 else 38)
	dustRing(kit, position, radius)
	Vfx.glow(position + Vector3.new(0, 2, 0), EMBER, radius * 2, 3, 0.4)
	Vfx.sound("HeavyHit", position)
	kit.shake(if big then 3 else 1.8, if big then 0.45 else 0.3, position)
end

-- Wind-ups -------------------------------------------------------------------------

local function windup(kit, pose: string, duration: number)
	if not kit.model then
		return
	end
	kit.Poser.play(kit.model, pose, math.min(0.15, duration * 0.5), math.max(0.05, duration * 0.6), 0.15)
	for _, hand in hands(kit.model) do
		kit.Vfx.glow(hand, EMBER, 8, 2, duration + 0.1)
	end
end

Strong.predict = {
	Groundbreaker = function(kit)
		windup(kit, "SlamWindup", kit.data.startup)
	end,
	TitanGrip = function(kit)
		windup(kit, "Reach", kit.data.startup)
	end,
	MeteorCharge = function(kit)
		windup(kit, "Charge", kit.data.startup)
	end,
	CrushingUppercut = function(kit)
		windup(kit, "UppercutWindup", kit.data.startup)
	end,
	QuakeStomp = function(kit)
		windup(kit, "Stomp", kit.data.startup)
	end,
	Heave = function(kit)
		windup(kit, "Lift", kit.data.startup)
	end,
	IronBody = function(kit)
		windup(kit, "Brace", 0.2)
	end,
	SeismicFissure = function(kit)
		windup(kit, "SlamWindup", kit.data.startup)
	end,
	WorldBreaker = function(kit)
		windup(kit, "PowerWindup", kit.data.startup)
	end,
}

-- Every cast's generic look is covered by the effects below
function Strong.onCast() end

local fx = {}
Strong.fx = fx

function fx.GroundbreakerWindup(kit)
	windup(kit, "SlamWindup", kit.data.duration)
	if kit.root then
		kit.Vfx.telegraph(kit.root, EMBER, kit.data.duration)
	end
end

function fx.GroundbreakerImpact(kit)
	if kit.model then
		kit.Poser.play(kit.model, "Slam", 0.05, 0.25, 0.3)
	end
	groundImpact(kit, kit.data.position, kit.data.radius, false)
end

function fx.StompWindup(kit)
	windup(kit, "Stomp", kit.data.duration)
end

function fx.StompImpact(kit)
	local position = kit.data.position
	kit.Vfx.groundRing(position + Vector3.new(0, 0.1, 0), DUST, 1, kit.data.radius * 2, 0.35)
	kit.Vfx.cracks(position, kit.data.radius * 0.6, EMBER, 5, 1.4)
	dustRing(kit, position, kit.data.radius * 0.7)
	kit.Vfx.sound("Hit", position)
	kit.shake(1, 0.2, position)
end

function fx.GripReach(kit)
	windup(kit, "Reach", kit.data.duration)
end

function fx.GripWhiff(kit)
	if kit.model then
		kit.Poser.play(kit.model, "Reach", 0.05, 0.15, 0.3)
	end
end

function fx.GripCatch(kit)
	local target = kit.data.target
	if typeof(target) == "Instance" and target:IsA("Model") then
		kit.Vfx.flash(target, EMBER, 0.25)
		local root = target:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			kit.Vfx.sparks(root.Position, GOLD, 18, 18)
			kit.Vfx.sound("Block", root)
		end
		kit.Poser.play(target, "Stagger", 0.05, kit.data.hold or 1, 0.2)
	end
	if kit.model then
		kit.Poser.play(kit.model, "Lift", 0.1, kit.data.hold or 1, 0.2)
	end
end

function fx.GripBroken(kit)
	local target = kit.data.target
	local root = typeof(target) == "Instance" and target:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		kit.Vfx.shockwave(root.Position, rgb(120, 220, 255), 2, 9, 0.3)
		kit.Vfx.popup(root.Position, "BROKE FREE!", rgb(120, 220, 255), 1.3)
	end
end

function fx.GripSlam(kit)
	if kit.model then
		kit.Poser.play(kit.model, if kit.data.hurl then "Throw" else "Slam", 0.06, 0.25, 0.3)
	end
	local target = kit.data.target
	local root = typeof(target) == "Instance" and target:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		groundImpact(kit, root.Position - Vector3.new(0, 2.5, 0), if kit.data.hurl then 9 else 6, kit.data.hurl == true)
	end
end

function fx.ChargeWindup(kit)
	windup(kit, "Charge", kit.data.duration)
	if kit.root then
		kit.Vfx.telegraph(kit.root, EMBER, kit.data.duration)
	end
end

function fx.ChargeRun(kit)
	local model, root = kit.model, kit.root
	if not model or not root then
		return
	end
	kit.Poser.play(model, "Charge", 0.05, kit.data.duration, 0.2)
	local running = true
	kit.keep(function()
		running = false
	end)
	task.spawn(function()
		local started = os.clock()
		while running and root.Parent and os.clock() - started < kit.data.duration + 0.1 do
			kit.Vfx.ghostAt(model, nil, EMBER, 0.3, Enum.Material.Neon)
			dustRing(kit, root.Position - Vector3.new(0, 2.8, 0), 2)
			task.wait(0.08)
		end
	end)
end

function fx.ChargeImpact(kit)
	local position = kit.data.position
	kit.Vfx.shockwave(position, EMBER, 3, 14, 0.35)
	kit.Vfx.sparks(position, GOLD, 30, 34)
	kit.Vfx.debris(position - Vector3.new(0, 2, 0), 6, ROCK, Enum.Material.Slate, 40)
	kit.Vfx.sound("HeavyHit", position)
	kit.shake(2.2, 0.3, position)
end

function fx.UppercutWindup(kit)
	windup(kit, "UppercutWindup", kit.data.duration)
end

function fx.Uppercut(kit)
	local model, root = kit.model, kit.root
	if not model or not root then
		return
	end
	kit.Poser.play(model, "Uppercut", 0.05, 0.2, 0.3)
	kit.Vfx.slash(root.CFrame * CFrame.new(0, 1, -1), EMBER, 4, 90, 0.25)
	if kit.data.landed then
		kit.Vfx.sparks(root.Position + root.CFrame.LookVector * 3 + Vector3.new(0, 2, 0), GOLD, 22, 30)
	end
	kit.Vfx.sound("HeavySwing", root)
end

-- Heave: the object hangs over his head during the lift (drawn here; the real
-- one is hidden on the server until it comes back)
local function buildLook(look): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.Size = if typeof(look.size) == "Vector3" then look.size else Vector3.new(3, 3, 3)
	part.Color = if typeof(look.color) == "Color3" then look.color else ROCK
	local material = Enum.Material[look.material or "Slate"]
	part.Material = if material then material else Enum.Material.Slate
	if look.shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	elseif look.shape == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
	end
	return part
end

function fx.HeaveLift(kit)
	local model, root = kit.model, kit.root
	local look = kit.data.look
	if not model or not root or typeof(look) ~= "table" then
		return
	end
	kit.Poser.play(model, "Lift", 0.15, kit.data.duration, 0.1)
	local held = buildLook(look)
	held.Parent = workspace.CurrentCamera
	if look.ripped then
		groundImpact(kit, root.Position + root.CFrame.LookVector * 3 - Vector3.new(0, 2.8, 0), 5, false)
	end
	local alive = true
	task.spawn(function()
		local started = os.clock()
		while alive and root.Parent and os.clock() - started < kit.data.duration + 0.15 do
			local rise = math.min(1, (os.clock() - started) / math.max(0.1, kit.data.duration))
			held.CFrame = root.CFrame * CFrame.new(0, 2 + rise * (2.5 + held.Size.Y / 2), 0)
			task.wait()
		end
		held:Destroy()
	end)
	kit.keep(function()
		alive = false
	end)
end

Strong.projectiles = {}

function Strong.projectiles.Prop(kit)
	local look = kit.data
	local part = buildLook(look)
	part.Parent = workspace.CurrentCamera
	local spin = CFrame.Angles(math.random() * 2, math.random() * 2, 0)
	local rotation = CFrame.identity
	local trail = Instance.new("Attachment")
	trail.Parent = part
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(DUST)
	dust.LightInfluence = 1
	dust.Size = NumberSequence.new(1, 3)
	dust.Transparency = NumberSequence.new(0.5, 1)
	dust.Lifetime = NumberRange.new(0.3, 0.5)
	dust.Rate = if kit.Vfx.reduced() then 10 else 30
	dust.Speed = NumberRange.new(0.5, 1)
	dust.Parent = trail
	if kit.model then
		kit.Poser.play(kit.model, "Throw", 0.05, 0.2, 0.3)
	end
	return {
		update = function(position: Vector3, _, dt: number)
			rotation = rotation * CFrame.Angles(spin.X * dt * 4, spin.Y * dt * 4, 0)
			part.CFrame = CFrame.new(position) * rotation
		end,
		finish = function(position: Vector3, reason: string)
			part:Destroy()
			if reason == "Destroyed" then
				return
			end
			local size = part.Size.Magnitude
			kit.Vfx.debris(position, if size > 8 then 12 else 7, part.Color, part.Material, 35)
			kit.Vfx.shockwave(position, DUST, 2, size * 1.4, 0.35)
			dustRing(kit, position, size * 0.6)
			kit.Vfx.sound("HeavyHit", position)
			kit.shake(if size > 8 then 2.4 else 1.2, 0.3, position)
		end,
	}
end

function fx.IronBody(kit)
	local model = kit.model
	if not model then
		return
	end
	kit.Poser.play(model, "Brace", 0.06, kit.data.duration, 0.2)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = rgb(170, 175, 190)
	highlight.FillTransparency = 0.45
	highlight.OutlineColor = GOLD
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = workspace.CurrentCamera
	kit.keep(function()
		highlight:Destroy()
	end)
end

function fx.IronBodyCounter(kit)
	local target = kit.data.target
	local root = typeof(target) == "Instance" and target:FindFirstChild("HumanoidRootPart")
	if kit.model then
		kit.Poser.play(kit.model, "Throw", 0.05, 0.25, 0.3)
	end
	if root and root:IsA("BasePart") then
		kit.Vfx.popup(root.Position, "COUNTER!", GOLD, 1.3)
		groundImpact(kit, root.Position - Vector3.new(0, 2.5, 0), 6, false)
	end
end

function fx.FissureWindup(kit)
	windup(kit, "SlamWindup", kit.data.duration)
	if kit.root then
		kit.Vfx.telegraph(kit.root, LAVA, kit.data.duration)
	end
end

function fx.Fissure(kit)
	if kit.model then
		kit.Poser.play(kit.model, "Slam", 0.05, 0.4, 0.3)
	end
	local origin, direction = kit.data.origin, kit.data.direction
	local length, speed, width = kit.data.length, kit.data.speed, kit.data.width
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	task.spawn(function()
		local step = 3
		local distance = 0
		while distance <= length do
			local point = origin + direction * distance
			kit.Vfx.cracks(point, width * 0.6, LAVA, 3, 2.5)
			kit.Vfx.burst(point + Vector3.new(0, 1, 0), {
				colors = ColorSequence.new(LAVA, EMBER),
				size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }),
				speed = NumberRange.new(18, 30),
				spread = Vector2.new(25, 25),
				lifetime = NumberRange.new(0.4, 0.7),
				acceleration = Vector3.new(0, -40, 0),
				count = 10,
			})
			if math.floor(distance / step) % 3 == 0 then
				kit.Vfx.debris(point, 3, ROCK, Enum.Material.Slate, 30)
				kit.shake(0.8, 0.12, point)
			end
			distance += step
			task.wait(step / speed)
		end
	end)
	kit.Vfx.sound("HeavyHit", origin)
end

function fx.WorldBreakerWindup(kit)
	local model, root = kit.model, kit.root
	if not model or not root then
		return
	end
	local duration = kit.data.duration
	kit.Poser.play(model, "PowerWindup", 0.3, duration, 0.05)
	kit.Vfx.telegraph(root, LAVA, duration)
	local hand = hands(model)[1]
	-- Energy gathers into his fist
	local alive = true
	kit.keep(function()
		alive = false
	end)
	task.spawn(function()
		local started = os.clock()
		while alive and root.Parent and os.clock() - started < duration do
			local at = if hand then hand.Position else root.Position
			local offset = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit * (6 + math.random() * 4)
			kit.Vfx.beam(at + offset, at, if math.random() < 0.5 then GOLD else EMBER, 0.15, 0.2)
			task.wait(0.05)
		end
	end)
	if hand then
		local orb = kit.Vfx.orb(hand.Position, GOLD, 0.5, 3.5, duration)
		local follow = true
		task.spawn(function()
			while follow and orb.Parent and hand.Parent do
				orb.Position = hand.Position
				task.wait()
			end
		end)
		kit.keep(function()
			follow = false
		end)
	end
	kit.Vfx.glow(root, EMBER, 30, 4, duration)
	kit.shake(0.6, duration, root.Position)
end

function fx.WorldBreakerFizzle(kit)
	if kit.root then
		kit.Vfx.sparks(kit.root.Position, DUST, 12, 12)
	end
end

function fx.WorldBreakerImpact(kit)
	local model = kit.model
	local origin, direction = kit.data.origin, kit.data.direction
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	if model then
		kit.Poser.play(model, "PowerPunch", 0.04, 0.5, 0.4)
	end
	local range, arc = kit.data.range or 22, kit.data.arc or 70
	local frame = CFrame.lookAt(origin + Vector3.new(0, 0.2, 0), origin + Vector3.new(0, 0.2, 0) + direction)
	kit.Vfx.cone(frame, range, arc, EMBER, 0.6)
	kit.Vfx.cone(frame + Vector3.new(0, 0.1, 0), range * 0.8, arc * 0.8, GOLD, 0.45)
	-- The floor shatters in a wave away from him
	task.spawn(function()
		for distance = 3, range, 3.5 do
			local spread = math.tan(math.rad(arc / 2)) * distance
			for _ = 1, 2 do
				local sideways = frame.RightVector * (math.random() - 0.5) * spread * 1.6
				local point = origin + direction * distance + sideways
				kit.Vfx.cracks(point, 4, LAVA, 4, 4)
				kit.Vfx.debris(point, 4, ROCK, Enum.Material.Slate, 55)
			end
			task.wait(0.03)
		end
	end)
	kit.Vfx.shockwave(origin + direction * 4 + Vector3.new(0, 2, 0), GOLD, 4, range * 1.2, 0.5)
	kit.Vfx.glow(origin + direction * 6, EMBER, range * 2, 6, 0.6)
	kit.Vfx.screenFlash(EMBER, 0.35, 0.4)
	kit.Vfx.sound("HeavyHit", origin)
	kit.shake(4, 0.6, origin)
end

-- Persistent look: a glow in his fists (embers at Degree 2, molten veins at Earthshaker)
function Strong.appearance(kit)
	local model = kit.model
	if not model or kit.degree < 2 then
		return nil
	end
	local created = {}
	for _, hand in hands(model) do
		local attachment = Instance.new("Attachment")
		attachment.Name = "SNStrongGlow"
		attachment.Parent = hand
		table.insert(created, attachment)
		local embers = Instance.new("ParticleEmitter")
		embers.Color = ColorSequence.new(GOLD, LAVA)
		embers.LightEmission = 1
		embers.LightInfluence = 0
		embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
		embers.Transparency = NumberSequence.new(0.1, 1)
		embers.Lifetime = NumberRange.new(0.5, 0.9)
		embers.Speed = NumberRange.new(1, 2.5)
		embers.Acceleration = Vector3.new(0, 4, 0)
		embers.Rate = if kit.Vfx.reduced() then 3 else (if kit.degree >= 3 then 14 else 7)
		embers.Parent = attachment
		local light = Instance.new("PointLight")
		light.Color = EMBER
		light.Range = if kit.degree >= 3 then 7 else 4
		light.Brightness = 1
		light.Parent = attachment
	end
	if kit.degree >= 3 then
		-- Molten veins down the arms
		for _, name in { "RightLowerArm", "LeftLowerArm", "RightUpperArm", "LeftUpperArm", "Right Arm", "Left Arm" } do
			local limb = model:FindFirstChild(name)
			if limb and limb:IsA("BasePart") then
				local vein = Instance.new("Part")
				vein.Name = "SNVein"
				vein.Size = Vector3.new(0.12, limb.Size.Y * 0.85, 0.12)
				vein.Material = Enum.Material.Neon
				vein.Color = LAVA
				vein.CanCollide = false
				vein.CanQuery = false
				vein.CanTouch = false
				vein.Massless = true
				vein.CastShadow = false
				vein.CFrame = limb.CFrame * CFrame.new(0, 0, -limb.Size.Z / 2 - 0.02)
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = limb
				weld.Part1 = vein
				weld.Parent = vein
				vein.Parent = model
				table.insert(created, vein)
			end
		end
	end
	return function()
		for _, item in created do
			item:Destroy()
		end
	end
end

return Strong
