-- Layered signature effects for the launch fighters. Every fighter has its own
-- palette and shape language, and each effect is built from the same layers:
-- a bright core, a soft glow, a shaped burst, a ground shockwave, a short point
-- light and (for heavy hits) a camera shake and a brief screen flash.
--
--   Strong Dude   blocky radial dust spikes, cracked ground, rock, ember sparks
--   Ghost         thin white-blue crossing slash lines, shadow slivers
--   Machine Master hexagon shockwaves, molten fire, blue blaster sparks
--   Grandmaster   staggered jade and gold rings, flowing spiral ribbons, petals
--   Corruption    implosion into a void burst, glitch shards, dark smoke
--   Syntax        wireframe cubes, holographic panels, falling code pixels
--   Admin         gold pillar, rising bar cage, gavel double ring, crimson sparks
--
-- Safeguards: parts and particle emitters are pooled and reused, the number of
-- live parts and the particles per half second are capped, decorative layers
-- are dropped when busy, and counts shrink on touch devices and with Reduced
-- effects (Vfx.scale). Everything fades within about a second.

local TweenService = game:GetService("TweenService")

local Vfx = require(script.Parent.Vfx)

local Signature = {}

local rgb = Color3.fromRGB

export type Palette = { core: Color3, glow: Color3, accent: Color3, dark: Color3, extra: Color3, style: string }

local PALETTES: { [string]: Palette } = {
	StrongDude = { style = "kinetic", core = rgb(255, 226, 160), glow = rgb(255, 140, 50), accent = rgb(255, 90, 30), dark = rgb(120, 100, 84), extra = rgb(190, 165, 135) },
	Ghost = { style = "slash", core = rgb(246, 250, 255), glow = rgb(140, 230, 255), accent = rgb(110, 150, 255), dark = rgb(14, 14, 24), extra = rgb(200, 215, 255) },
	MachineMaster = { style = "tech", core = rgb(255, 238, 180), glow = rgb(255, 128, 28), accent = rgb(70, 185, 255), dark = rgb(62, 68, 80), extra = rgb(255, 200, 70) },
	Grandmaster = { style = "chi", core = rgb(250, 232, 186), glow = rgb(86, 186, 148), accent = rgb(240, 196, 84), dark = rgb(44, 54, 52), extra = rgb(150, 235, 200) },
	Corruption = { style = "void", core = rgb(222, 200, 255), glow = rgb(150, 112, 255), accent = rgb(255, 70, 215), dark = rgb(14, 11, 20), extra = rgb(80, 255, 230) },
	Syntax = { style = "code", core = rgb(232, 255, 246), glow = rgb(38, 226, 168), accent = rgb(80, 215, 255), dark = rgb(24, 52, 56), extra = rgb(150, 255, 200) },
	Admin = { style = "command", core = rgb(250, 243, 228), glow = rgb(236, 188, 86), accent = rgb(190, 40, 56), dark = rgb(60, 20, 26), extra = rgb(255, 220, 130) },
}

function Signature.palette(powerId: string?): Palette?
	return if powerId then PALETTES[powerId] else nil
end

-- Pools and caps ----------------------------------------------------------------------

local SOFT_CAP, HARD_CAP = 70, 110
local live = 0
local freeParts: { [string]: { BasePart } } = {}
local freeEmitters: { { anchor: BasePart, emitter: ParticleEmitter } } = {}
local windowStart, windowCount = 0, 0
local lights = 0

function Signature.liveParts(): number
	return live
end

-- A decorative layer is skipped when many effects are already running
local function room(decorative: boolean): boolean
	return live < (if decorative then SOFT_CAP * Vfx.scale() + 10 else HARD_CAP)
end

-- A pooled instance can be destroyed from outside (the camera folder being cleared)
local function alive(instance: Instance): boolean
	return (pcall(function()
		return instance.Parent
	end))
end

local function release(part: BasePart)
	live = math.max(0, live - 1)
	if not alive(part) then
		return
	end
	part.Parent = nil
	local list = freeParts[part.Name]
	if not list then
		list = {}
		freeParts[part.Name] = list
	end
	if #list < 40 then
		table.insert(list, part)
	else
		part:Destroy()
	end
end

local function acquire(shape: Enum.PartType, props: { [string]: any }): BasePart
	local key = shape.Name
	local list = freeParts[key]
	local part = if list then table.remove(list) else nil
	if part and not alive(part) then
		part = nil
	end
	if not part then
		part = Instance.new("Part")
		part.Name = key
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Shape = shape
	end
	part.Material = props.Material or Enum.Material.Neon
	part.Color = props.Color or Color3.new(1, 1, 1)
	part.Transparency = props.Transparency or 0
	part.Size = props.Size or Vector3.one
	part.CFrame = props.CFrame or CFrame.new()
	part.Parent = Vfx.container()
	live += 1
	return part
end

-- Tweens a pooled part and returns it to the pool afterwards
local function play(part: BasePart, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(part, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	task.delay(duration + 0.05, release, part)
end

local function block(cframe: CFrame, size: Vector3, color: Color3, duration: number, goal: { [string]: any }?, material: Enum.Material?, transparency: number?, decorative: boolean?)
	if not room(decorative == true) then
		return nil
	end
	local part = acquire(Enum.PartType.Block, { CFrame = cframe, Size = size, Color = color, Material = material, Transparency = transparency or 0.05 })
	local target = goal or {}
	if target.Transparency == nil then
		target.Transparency = 1
	end
	play(part, duration, target)
	return part
end

local function ball(position: Vector3, color: Color3, from: number, to: number, duration: number, material: Enum.Material?, transparency: number?, decorative: boolean?)
	if not room(decorative == true) then
		return nil
	end
	local part = acquire(Enum.PartType.Ball, { CFrame = CFrame.new(position), Size = Vector3.one * from, Color = color, Material = material, Transparency = transparency or 0.05 })
	play(part, duration, { Size = Vector3.one * to, Transparency = 1 })
	return part
end

-- A flat disc lying on the ground that spreads out and fades
local function disc(position: Vector3, color: Color3, from: number, to: number, duration: number, transparency: number?, decorative: boolean?)
	if not room(decorative == true) then
		return nil
	end
	local part = acquire(Enum.PartType.Cylinder, {
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Size = Vector3.new(0.12, from, from),
		Color = color,
		Transparency = transparency or 0.25,
	})
	play(part, duration, { Size = Vector3.new(0.12, to, to), Transparency = 1 })
	return part
end

-- Bar-built outline of a regular polygon lying flat (sides 4, 6, 18...)
local function outline(position: Vector3, sides: number, radius: number, thickness: number, color: Color3, duration: number, grow: number?, spin: number?, transparency: number?)
	local count = math.max(3, math.ceil(sides * (0.5 + 0.5 * Vfx.scale())))
	local length = 2 * radius * math.tan(math.pi / count) * 1.08
	for index = 0, count - 1 do
		local angle = index / count * math.pi * 2 + (spin or 0)
		local from = CFrame.new(position) * CFrame.Angles(0, -angle, 0) * CFrame.new(0, 0, -radius) * CFrame.Angles(0, math.rad(90), 0)
		local goal: { [string]: any } = { Transparency = 1 }
		if grow then
			local scale = grow / radius
			goal.CFrame = CFrame.new(position) * CFrame.Angles(0, -angle, 0) * CFrame.new(0, 0, -grow) * CFrame.Angles(0, math.rad(90), 0)
			goal.Size = Vector3.new(length * scale, thickness, thickness)
		end
		block(from, Vector3.new(length, thickness, thickness), color, duration, goal, nil, transparency or 0.1, true)
	end
end

local function light(position: Vector3, color: Color3, range: number, brightness: number, duration: number)
	if lights >= 6 then
		return
	end
	lights += 1
	Vfx.glow(position, color, range, brightness, duration)
	task.delay(duration + 0.1, function()
		lights = math.max(0, lights - 1)
	end)
end

-- Particle burst from a pooled emitter. cfg: colors/color, size, lifetime, speed,
-- spread, drag, accel, count, texture, emission, transparency, shape, inward
local function emit(position: Vector3, cfg: { [string]: any })
	local clock = os.clock()
	if clock - windowStart > 0.5 then
		windowStart, windowCount = clock, 0
	end
	local count = math.max(1, math.floor((cfg.count or 16) * Vfx.scale() + 0.5))
	if windowCount > 260 then
		count = math.max(1, math.floor(count * 0.3))
	end
	windowCount += count
	count = math.min(count, 60)

	local entry = table.remove(freeEmitters)
	if entry and not alive(entry.anchor) then
		entry = nil
	end
	if not entry then
		local anchor = Instance.new("Part")
		anchor.Name = "SNEmit"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 0
		emitter.LightInfluence = 0
		emitter.Parent = anchor
		entry = { anchor = anchor, emitter = emitter }
	end
	local emitter = entry.emitter
	emitter.Color = cfg.colors or ColorSequence.new(cfg.color or Color3.new(1, 1, 1))
	emitter.LightEmission = cfg.emission or 1
	emitter.Size = cfg.size or NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = cfg.transparency or NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = cfg.lifetime or NumberRange.new(0.3, 0.6)
	emitter.Speed = cfg.speed or NumberRange.new(10, 24)
	emitter.SpreadAngle = cfg.spread or Vector2.new(180, 180)
	emitter.Drag = cfg.drag or 4
	emitter.Acceleration = cfg.accel or Vector3.zero
	emitter.RotSpeed = NumberRange.new(-200, 200)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Texture = cfg.texture or "rbxasset://textures/particles/sparkles_main.dds"
	pcall(function()
		emitter.Shape = cfg.shape or Enum.ParticleEmitterShape.Box
		emitter.ShapeInOut = if cfg.inward then Enum.ParticleEmitterShapeInOut.Inward else Enum.ParticleEmitterShapeInOut.Outward
	end)
	entry.anchor.CFrame = CFrame.new(position)
	entry.anchor.Parent = Vfx.container()
	emitter:Emit(count)
	local life = (cfg.lifetime or NumberRange.new(0.3, 0.6)).Max + 0.15
	task.delay(life, function()
		if not alive(entry.anchor) then
			return
		end
		entry.anchor.Parent = nil
		if #freeEmitters < 24 then
			table.insert(freeEmitters, entry)
		else
			entry.anchor:Destroy()
		end
	end)
end

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local function sparkBurst(position: Vector3, palette: Palette, count: number, speed: number, length: number?)
	emit(position, {
		colors = ColorSequence.new(palette.core, palette.glow),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, length or 0.5), NumberSequenceKeypoint.new(1, 0) }),
		lifetime = NumberRange.new(0.2, 0.45),
		speed = NumberRange.new(speed * 0.6, speed * 1.3),
		drag = 5,
		count = count,
	})
end

local function smokeBurst(position: Vector3, color: Color3, count: number, size: number, speed: number)
	emit(position, {
		color = color,
		texture = SMOKE,
		emission = 0,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.4), NumberSequenceKeypoint.new(1, size) }),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		lifetime = NumberRange.new(0.5, 0.9),
		speed = NumberRange.new(speed * 0.5, speed),
		spread = Vector2.new(30, 180),
		drag = 3,
		count = count,
	})
end

-- Context: where, how big, who is watching ----------------------------------------------

local function shakeAndFlash(ctx, position: Vector3, size: number, palette: Palette)
	if size < 1.5 then
		return
	end
	local strength = (if size >= 3 then 3.2 else 1.8)
	if ctx and ctx.shake then
		ctx.shake(strength, if size >= 3 then 0.45 else 0.25, position)
	end
	if not ctx or ctx.near == nil or ctx.near then
		-- Vfx.screenFlash does nothing unless Intense flashes are on
		Vfx.screenFlash(palette.glow, if size >= 3 then 0.3 else 0.14, if size >= 3 then 0.3 else 0.18)
	end
end

local function lerpUp(position: Vector3, height: number): Vector3
	return position + Vector3.new(0, height, 0)
end

-- Style shapes: impact ------------------------------------------------------------------
-- `g` is a point on the ground; `s` is the size class: 1 small, 2 heavy, 3 ultimate.

local impacts: { [string]: (Vector3, number, Palette) -> () } = {}

function impacts.kinetic(g, s, p)
	local count = 5 + s * 2
	for index = 1, count do
		local angle = index / count * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local start = g + direction * 1.5
		local length = 2 + s * 1.6
		block(CFrame.lookAt(start + Vector3.new(0, 0.6, 0), start + direction + Vector3.new(0, 0.6, 0)), Vector3.new(0.9, 0.9, length), if index % 2 == 0 then p.glow else p.accent, 0.45, {
			CFrame = CFrame.lookAt(g + direction * (3 + s * 3.5) + Vector3.new(0, 0.9, 0), g + direction * (4 + s * 3.5) + Vector3.new(0, 0.9, 0)),
			Size = Vector3.new(0.3, 0.3, length * 1.6),
		}, Enum.Material.Neon, 0.1, true)
	end
	disc(g + Vector3.new(0, 0.1, 0), p.extra, 2, 8 + s * 6, 0.6, 0.35)
	disc(g + Vector3.new(0, 0.14, 0), p.accent, 1, 6 + s * 5, 0.35, 0.15)
	Vfx.cracks(g, 3.5 + s * 2.5, p.accent, 4 + s * 2, 1.4 + s * 0.6)
	if s >= 2 then
		Vfx.debris(g, 3 + s * 3, p.dark, Enum.Material.Slate, 30 + s * 8)
	end
	smokeBurst(g + Vector3.new(0, 0.6, 0), p.extra, 8 + s * 5, 4 + s, 8 + s * 4)
	sparkBurst(lerpUp(g, 1.2), p, 8 + s * 5, 30 + s * 6, 0.6)
end

function impacts.slash(g, s, p)
	local center = lerpUp(g, 1.6)
	local length = 5 + s * 3.5
	for index, angle in { 35, -35, if s >= 2 then 90 else nil } do
		local frame = CFrame.new(center) * CFrame.Angles(0, math.rad(index * 25), math.rad(angle))
		block(frame, Vector3.new(length, 0.12, 0.12), p.core, 0.22, { Size = Vector3.new(length * 1.5, 0.02, 0.02) }, Enum.Material.Neon, 0, false)
		block(frame, Vector3.new(length * 0.8, 0.5, 0.5), p.glow, 0.28, { Size = Vector3.new(length * 1.3, 0.05, 0.05) }, Enum.Material.Neon, 0.55, true)
	end
	ball(center, p.core, 0.8 * s, 3 + s * 1.5, 0.15, Enum.Material.Neon, 0.1)
	outline(g + Vector3.new(0, 0.12, 0), 18, 1.5, 0.12, p.glow, 0.3, 4 + s * 3.5, 0, 0.1)
	for _ = 1, s + 1 do
		local sliver = CFrame.new(g + Vector3.new((math.random() - 0.5) * 5, 0.2, (math.random() - 0.5) * 5)) * CFrame.Angles(0, math.random() * 6, 0)
		block(sliver, Vector3.new(0.15, 0.08, 1), p.dark, 0.5, { Size = Vector3.new(0.1, 6, 0.1), CFrame = sliver + Vector3.new(0, 3, 0) }, Enum.Material.Neon, 0.15, true)
	end
	sparkBurst(center, p, 10 + s * 5, 38 + s * 6, 0.9)
end

function impacts.tech(g, s, p)
	local center = lerpUp(g, 1.4)
	outline(g + Vector3.new(0, 0.14, 0), 6, 1.5, 0.35, p.glow, 0.4, 5 + s * 4, math.pi / 6, 0.05)
	outline(g + Vector3.new(0, 0.2, 0), 6, 1, 0.25, p.accent, 0.3, 3 + s * 2.5, 0, 0.1)
	disc(g + Vector3.new(0, 0.1, 0), p.glow, 1, 6 + s * 5, 0.5, 0.45)
	ball(center, p.core, 1 + s, 3.5 + s * 2.5, 0.2, Enum.Material.Neon, 0.05)
	ball(center, p.glow, 2 + s, 6 + s * 3.5, 0.4, Enum.Material.ForceField, 0.1, true)
	for index = 1, 4 + s do
		local angle = index / (4 + s) * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0.2, math.sin(angle))
		Vfx.beam(center + direction * 1.2, center + direction * (4 + s * 2.5), p.accent, 0.22, 0.2)
	end
	emit(center, {
		colors = ColorSequence.new(p.core, p.glow, p.dark),
		texture = FIRE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2 + s * 0.5), NumberSequenceKeypoint.new(1, 0) }),
		lifetime = NumberRange.new(0.4, 0.8),
		speed = NumberRange.new(4, 10 + s * 3),
		accel = Vector3.new(0, 8, 0),
		count = 10 + s * 5,
	})
	sparkBurst(center, { core = p.core, glow = p.extra } :: any, 10 + s * 5, 34 + s * 6, 0.5)
	smokeBurst(center, p.dark, 5 + s * 3, 3 + s, 6)
end

function impacts.chi(g, s, p)
	local center = lerpUp(g, 1.4)
	for index = 0, 2 + (if s >= 2 then 1 else 0) do
		task.delay(index * 0.07, function()
			local color = if index % 2 == 0 then p.glow else p.accent
			disc(g + Vector3.new(0, 0.1 + index * 0.03, 0), color, 1.5, 7 + s * 5 - index, 0.5, 0.3)
			outline(g + Vector3.new(0, 0.2, 0), 18, 1.2, 0.22, if index % 2 == 0 then p.core else p.accent, 0.45, 6 + s * 4.5 - index, index * 0.2, 0.05)
		end)
	end
	-- Two flowing ribbons spiral up and out from the strike
	for ribbon = 0, 1 do
		for step = 0, 6 do
			local t = step / 6
			local angle = t * math.pi * 1.6 + ribbon * math.pi
			local radius = 1 + t * (2.5 + s)
			local position = g + Vector3.new(math.cos(angle) * radius, 0.6 + t * (1.5 + s), math.sin(angle) * radius)
			ball(position, if ribbon == 0 then p.glow else p.accent, 0.7 - t * 0.4, 0.15, 0.25 + t * 0.2, Enum.Material.Neon, 0.1, true)
		end
	end
	ball(center, p.core, 1 + s * 0.5, 3.5 + s * 1.8, 0.2, Enum.Material.Neon, 0.1)
	ball(center, p.glow, 2, 5 + s * 2.5, 0.35, Enum.Material.ForceField, 0.15, true)
	emit(center, {
		colors = ColorSequence.new(p.accent, p.glow),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0) }),
		lifetime = NumberRange.new(0.6, 1.1),
		speed = NumberRange.new(4, 12),
		accel = Vector3.new(0, 5, 0),
		drag = 2,
		count = 10 + s * 5,
	})
end

function impacts.void(g, s, p)
	local center = lerpUp(g, 1.5)
	-- Implosion first, then the burst
	ball(center, p.dark, 5 + s * 2, 0.5, 0.16, Enum.Material.Neon, 0.05)
	ball(center, p.glow, 5 + s * 2.5, 1, 0.2, Enum.Material.ForceField, 0.2, true)
	task.delay(0.15, function()
		ball(center, p.dark, 1, 4 + s * 3, 0.3, Enum.Material.Neon, 0.35)
		ball(center, p.glow, 2, 7 + s * 4, 0.4, Enum.Material.ForceField, 0.5)
		disc(g + Vector3.new(0, 0.1, 0), p.dark, 2, 9 + s * 6, 0.55, 0.1)
		outline(g + Vector3.new(0, 0.2, 0), 14, 2, 0.3, p.glow, 0.45, 7 + s * 5.5, 0.3, 0.05)
		local shards = 4 + s * 3
		for index = 1, shards do
			local angle = math.random() * math.pi * 2
			local height = math.random() * 3
			local position = center + Vector3.new(math.cos(angle) * (2 + math.random() * (2 + s * 2)), height - 1, math.sin(angle) * (2 + math.random() * (2 + s * 2)))
			local color = if index % 3 == 0 then p.accent elseif index % 3 == 1 then p.extra else p.glow
			block(CFrame.new(position) * CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3), Vector3.new(0.25, 0.25 + math.random() * 1.4, 0.25 + math.random() * 1.8), color, 0.35 + math.random() * 0.2, nil, nil, 0, true)
		end
		smokeBurst(center, p.dark, 8 + s * 4, 4 + s * 1.5, 10)
		sparkBurst(center, { core = p.accent, glow = p.glow } :: any, 8 + s * 4, 30, 0.45)
	end)
end

function impacts.code(g, s, p)
	local center = lerpUp(g, 1.8)
	-- A wireframe cube that unfolds outward
	local edge = 2 + s * 1.4
	local grown = edge * 2.2
	local cubeFrame = CFrame.new(center) * CFrame.Angles(0.6, 0.8, 0)
	for _, axis in { 0, 1, 2 } do
		for _, a in { -1, 1 } do
			for _, b in { -1, 1 } do
				local offset = if axis == 0 then Vector3.new(0, a, b) elseif axis == 1 then Vector3.new(a, 0, b) else Vector3.new(a, b, 0)
				local size = if axis == 0 then Vector3.new(edge, 0.12, 0.12) elseif axis == 1 then Vector3.new(0.12, edge, 0.12) else Vector3.new(0.12, 0.12, edge)
				local far = if axis == 0 then Vector3.new(grown, 0.05, 0.05) elseif axis == 1 then Vector3.new(0.05, grown, 0.05) else Vector3.new(0.05, 0.05, grown)
				block(cubeFrame * CFrame.new(offset * edge / 2), size, if axis == 0 then p.core else p.glow, 0.45, {
					CFrame = cubeFrame * CFrame.Angles(0, 0.5, 0) * CFrame.new(offset * grown / 2),
					Size = far,
				}, Enum.Material.Neon, 0, true)
			end
		end
	end
	disc(g + Vector3.new(0, 0.1, 0), p.dark, 2, 8 + s * 5, 0.5, 0.2)
	outline(g + Vector3.new(0, 0.18, 0), 4, 1.5, 0.15, p.glow, 0.45, 6 + s * 4, math.pi / 4, 0.05)
	-- Holographic panels
	for index = 1, 1 + s do
		local angle = index / (1 + s) * math.pi * 2 + math.random()
		local position = center + Vector3.new(math.cos(angle) * 3, 0.5 + math.random(), math.sin(angle) * 3)
		block(CFrame.lookAt(position, center), Vector3.new(3, 2, 0.08), p.accent, 0.5, { Transparency = 1, CFrame = CFrame.lookAt(position + Vector3.new(0, 1.5, 0), center) * CFrame.Angles(0, 0.4, 0) }, Enum.Material.Neon, 0.5, true)
	end
	ball(center, p.core, 1, 3 + s, 0.15, Enum.Material.Neon, 0.1)
	emit(center, {
		colors = ColorSequence.new(p.core, p.glow),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0.1) }),
		lifetime = NumberRange.new(0.5, 0.9),
		speed = NumberRange.new(6, 18),
		accel = Vector3.new(0, -14, 0),
		drag = 1,
		count = 12 + s * 6,
	})
	if s >= 2 and not Vfx.reduced() then
		Vfx.text3d(center + Vector3.new(0, 2, 0), if s >= 3 then "{ EXEC }" else "01 1 0", p.glow, 1.2, 0.8)
	end
end

function impacts.command(g, s, p)
	local center = lerpUp(g, 1.5)
	-- Pillar of authority
	block(CFrame.new(g + Vector3.new(0, 5 + s * 3, 0)), Vector3.new(1.2 + s * 0.4, 10 + s * 6, 1.2 + s * 0.4), p.extra, 0.3, { Size = Vector3.new(0.2, 12 + s * 6, 0.2) }, Enum.Material.Neon, 0.05)
	block(CFrame.new(g + Vector3.new(0, 5 + s * 3, 0)), Vector3.new(3 + s, 10 + s * 6, 3 + s), p.glow, 0.4, { Size = Vector3.new(0.6, 12 + s * 6, 0.6) }, Enum.Material.ForceField, 0.3, true)
	-- Cage bars rise around the strike
	local bars = 6 + s * 2
	for index = 1, bars do
		local angle = index / bars * math.pi * 2
		local base = g + Vector3.new(math.cos(angle) * (3 + s), 0, math.sin(angle) * (3 + s))
		block(CFrame.new(base + Vector3.new(0, 0.2, 0)), Vector3.new(0.3, 0.4, 0.3), p.accent, 0.5, {
			Size = Vector3.new(0.3, 7, 0.3),
			CFrame = CFrame.new(base + Vector3.new(0, 3.5, 0)),
		}, Enum.Material.Neon, 0.1, true)
	end
	-- Gavel double ring
	disc(g + Vector3.new(0, 0.1, 0), p.glow, 2, 8 + s * 5, 0.45, 0.25)
	task.delay(0.1, function()
		outline(g + Vector3.new(0, 0.2, 0), 18, 1.5, 0.25, p.core, 0.4, 7 + s * 4.5, 0, 0.05)
		disc(g + Vector3.new(0, 0.14, 0), p.accent, 2, 6 + s * 4, 0.35, 0.3)
	end)
	Vfx.cracks(g, 3 + s * 2, p.glow, 4 + s * 2, 1.4)
	ball(center, p.core, 1 + s, 4 + s * 2, 0.2, Enum.Material.Neon, 0.05)
	sparkBurst(center, p, 10 + s * 5, 30 + s * 6, 0.6)
	sparkBurst(center, { core = p.accent, glow = p.dark } :: any, 4 + s * 2, 22, 0.5)
end

local IMPACT_SOUND = { kinetic = "GroundSlam", slash = "HeavyHit", tech = "Fire", chi = "HeavyHit", void = "Magic", code = "Glitch", command = "Gavel" }

-- The shared top layers of an impact: core flash, glow, light, shake -----------------------

function Signature.impact(ctx, powerId: string, ground: Vector3, size: number?)
	local palette = PALETTES[powerId]
	if not palette then
		return
	end
	local s = math.clamp(size or 1, 1, 3)
	local center = lerpUp(ground, 1.5)
	ball(center, palette.core, 0.8, 2.5 + s * 1.5, 0.12, Enum.Material.Neon, 0)
	light(center, palette.glow, 12 + s * 8, 3 + s, 0.25)
	local shape = impacts[palette.style]
	if shape then
		shape(ground, s, palette)
	end
	if s >= 2 then
		-- Each fighter has its own sound family (missing names are ignored)
		local sound = IMPACT_SOUND[palette.style]
		Vfx.sound(if s >= 3 and palette.style ~= "slash" then "Explosion" else sound, center)
	end
	shakeAndFlash(ctx, ground, s, palette)
end

-- Wind-ups and telegraphs ------------------------------------------------------------------

local TELEGRAPH_SIDES = { kinetic = 8, slash = 18, tech = 6, chi = 18, void = 12, code = 4, command = 18 }

-- Marks the ground where an attack will land, in the attacker's colour. The
-- fill stays faint so the opponent is never hidden.
function Signature.telegraph(powerId: string, ground: Vector3, radius: number, duration: number)
	local palette = PALETTES[powerId]
	if not palette then
		return
	end
	radius = math.clamp(radius, 2, 40)
	if room(true) then
		local fill = acquire(Enum.PartType.Cylinder, {
			CFrame = CFrame.new(ground + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Size = Vector3.new(0.1, radius * 2, radius * 2),
			Color = palette.glow,
			Transparency = 0.92,
		})
		play(fill, duration, { Transparency = 0.6 }, Enum.EasingStyle.Linear)
	end
	local sides = TELEGRAPH_SIDES[palette.style] or 12
	local spin = if palette.style == "code" then math.pi / 4 else 0
	outline(ground + Vector3.new(0, 0.2, 0), sides, radius, if palette.style == "kinetic" then 0.45 else 0.25, palette.core, duration, nil, spin, 0.05)
	outline(ground + Vector3.new(0, 0.18, 0), sides, radius * 0.5, 0.15, palette.accent, duration, radius * 0.95, spin, 0.2)
	-- A mark in the middle: cross hair lines
	block(CFrame.new(ground + Vector3.new(0, 0.22, 0)), Vector3.new(radius * 0.8, 0.1, 0.18), palette.accent, duration, nil, nil, 0.2, true)
	block(CFrame.new(ground + Vector3.new(0, 0.22, 0)), Vector3.new(0.18, 0.1, radius * 0.8), palette.accent, duration, nil, nil, 0.2, true)
end

-- Light gathers into a bright core while an attack winds up
function Signature.charge(ctx, powerId: string, center: Vector3, radius: number, duration: number)
	local palette = PALETTES[powerId]
	if not palette then
		return
	end
	duration = math.clamp(duration, 0.1, 1.5)
	local core = ball(center, palette.core, 0.4, 0.4 + radius * 0.35, duration, Enum.Material.Neon, 0.1)
	ball(center, palette.glow, radius * 0.6, radius * 0.2, duration, Enum.Material.ForceField, 0.35, true)
	light(center, palette.glow, 8 + radius, 2.5, duration)
	for wave = 0, 2 do
		task.delay(duration * wave / 3, function()
			emit(center, {
				colors = ColorSequence.new(palette.core, palette.glow),
				size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.4, 0.5), NumberSequenceKeypoint.new(1, 0.05) }),
				lifetime = NumberRange.new(duration / 3, duration / 3 + 0.1),
				speed = NumberRange.new(radius / (duration / 3 + 0.1) * 0.9, radius / (duration / 3 + 0.1) * 1.2),
				drag = 0,
				shape = Enum.ParticleEmitterShape.Sphere,
				inward = true,
				count = 10 + radius,
			})
		end)
	end
	return core
end

-- Ultimates: a build-up that finishes inside 1.5 s, then a large release ------------------

function Signature.ultimateWindup(ctx, powerId: string, ground: Vector3, radius: number, duration: number)
	Vfx.sound("EnergyCharge", lerpUp(ground, 2))
	Signature.telegraph(powerId, ground, radius, math.min(duration, 1.5))
	Signature.charge(ctx, powerId, lerpUp(ground, 3), 8, math.min(duration, 1.5))
end

function Signature.ultimate(ctx, powerId: string, ground: Vector3, radius: number)
	local palette = PALETTES[powerId]
	if not palette then
		return
	end
	Signature.impact(ctx, powerId, ground, 3)
	disc(ground + Vector3.new(0, 0.1, 0), palette.core, 3, radius * 2, 0.7, 0.3)
	outline(ground + Vector3.new(0, 0.3, 0), 18, 3, 0.5, palette.glow, 0.8, radius, 0, 0.05)
	ball(lerpUp(ground, 2), palette.glow, 4, radius * 1.1, 0.6, Enum.Material.ForceField, 0.2)
	-- Lingering embers or glyphs
	emit(lerpUp(ground, 1), {
		colors = ColorSequence.new(palette.core, palette.glow, palette.accent),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		lifetime = NumberRange.new(0.9, 1.5),
		speed = NumberRange.new(3, 12),
		accel = Vector3.new(0, 6, 0),
		spread = Vector2.new(180, 180),
		drag = 2,
		count = 30,
	})
end

-- Movement: a bright ribbon from one point to another --------------------------------------

function Signature.trail(powerId: string, from: Vector3, to: Vector3, width: number?)
	local palette = PALETTES[powerId]
	if not palette or (to - from).Magnitude < 0.5 then
		return
	end
	local w = width or 0.5
	local beam = Vfx.beam(from, to, palette.core, w * 0.5, 0.25)
	if beam then
		beam.Transparency = 0
	end
	Vfx.beam(from, to, palette.glow, w * 2.2, 0.4, Enum.Material.ForceField)
	if palette.style == "chi" or palette.style == "void" then
		local mid = (from + to) / 2 + Vector3.new(0, 1.5, 0)
		Vfx.beam(from, mid, palette.accent, w * 0.5, 0.35)
		Vfx.beam(mid, to, palette.accent, w * 0.5, 0.35)
	end
	sparkBurst(to, palette, 6, 16, 0.4)
end

-- Hit feedback on the target: a crisp spark in the attacker's colours and a brief highlight -

function Signature.hit(powerId: string?, position: Vector3, victim: Model?, size: number?)
	local palette = if powerId then PALETTES[powerId] else nil
	if not palette then
		return false
	end
	local s = math.clamp(size or 1, 1, 3)
	sparkBurst(position, palette, 8 + s * 4, 26 + s * 6, 0.55)
	ball(position, palette.core, 0.5, 2 + s, 0.1, Enum.Material.Neon, 0)
	-- A short star of lines whose angles suit the fighter
	local lines = if palette.style == "slash" then 2 elseif palette.style == "code" then 4 else 3
	for index = 1, lines do
		local roll = (index / lines) * math.pi + (if palette.style == "code" then math.pi / 4 else 0)
		block(CFrame.new(position) * CFrame.Angles(0, math.random() * 0.5, roll), Vector3.new(1.4 + s, 0.1, 0.1), palette.core, 0.15, { Size = Vector3.new(2.6 + s * 1.5, 0.02, 0.02) }, Enum.Material.Neon, 0, true)
	end
	if s >= 2 then
		disc(position - Vector3.new(0, 1.2, 0), palette.glow, 1, 5 + s * 2, 0.3, 0.3, true)
	end
	if victim then
		Vfx.flash(victim, palette.glow, 0.12)
	end
	return true
end

-- Wrapping a power module's effects ---------------------------------------------------------
-- decorate(module, powerId, { EffectName = { kind, size?, radius? } }) adds the layered
-- signature on top of the effect the module already draws. Kinds: windup, ultwindup, impact,
-- ultimate, trail, cast.

local function groundOf(kit, position: Vector3): Vector3
	if kit.root and math.abs(position.Y - kit.root.Position.Y) < 3.6 then
		return position - Vector3.new(0, 2.9, 0)
	end
	return position
end

local function targetRoot(kit): BasePart?
	local target = kit.data.target
	if typeof(target) == "Instance" and target:IsA("Model") then
		local root = target:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root
		end
	end
	return nil
end

local function spot(kit): Vector3?
	local data = kit.data
	for _, key in { "position", "center", "to", "point", "anchor", "target" } do
		local value = data[key]
		if typeof(value) == "Vector3" then
			return value
		end
	end
	local root = targetRoot(kit)
	if root then
		return root.Position
	end
	if typeof(data.origin) == "Vector3" and typeof(data.direction) == "Vector3" and data.direction.Magnitude > 0.01 then
		local reach = if typeof(data.length) == "number" then math.min(data.length * 0.5, 14) else 8
		return data.origin + data.direction.Unit * reach
	end
	if kit.root then
		return kit.root.Position + kit.root.CFrame.LookVector * 5
	end
	return nil
end

local function context(kit, position: Vector3)
	return {
		shake = kit.shake,
		near = kit.isLocal or kit.near(position, 40),
	}
end

local function apply(kit, powerId: string, spec)
	if type(spec[1]) == "table" then
		for _, part in spec do
			apply(kit, powerId, part)
		end
		return
	end
	local kind = spec[1]
	local size = spec[2] or 1
	local radius = spec[3]
	local data = kit.data
	if kind == "windup" or kind == "ultwindup" then
		local position = spot(kit)
		if typeof(data.center) ~= "Vector3" and typeof(data.position) ~= "Vector3" and kit.root then
			position = kit.root.Position
		end
		if not position then
			return
		end
		local duration = if typeof(data.duration) == "number" then data.duration else 0.5
		local ground = groundOf(kit, position)
		local r = if typeof(data.radius) == "number" then math.min(data.radius, 30) else radius or 6
		if kind == "ultwindup" then
			Signature.ultimateWindup(context(kit, ground), powerId, ground, r, duration)
		else
			Signature.telegraph(powerId, ground, r, math.min(duration, 1.5))
			if kit.root then
				Signature.charge(context(kit, ground), powerId, kit.root.Position, 3 + size * 2, math.min(duration, 1.2))
			end
		end
	elseif kind == "impact" or kind == "ultimate" then
		local position = spot(kit)
		if not position then
			return
		end
		local ground = groundOf(kit, position)
		if kind == "ultimate" then
			Signature.ultimate(context(kit, ground), powerId, ground, if typeof(data.radius) == "number" then math.min(data.radius, 40) else radius or 20)
		else
			Signature.impact(context(kit, ground), powerId, ground, size)
		end
	elseif kind == "trail" then
		local from = data.from or data.origin
		local to = data.to
		local reach = if typeof(data.length) == "number" then data.length elseif typeof(data.range) == "number" then data.range else nil
		if typeof(from) == "Vector3" and typeof(data.direction) == "Vector3" and reach and data.direction.Magnitude > 0.01 then
			to = from + data.direction.Unit * math.min(reach, 60)
		end
		if typeof(from) == "Vector3" and typeof(to) == "Vector3" then
			Signature.trail(powerId, from, to, size)
		elseif kit.root then
			local direction = data.direction
			local look = if typeof(direction) == "Vector3" and direction.Magnitude > 0.01 then direction.Unit else kit.root.CFrame.LookVector
			Signature.trail(powerId, kit.root.Position, kit.root.Position + look * (radius or 10), size)
		end
	elseif kind == "cast" then
		if not kit.root then
			return
		end
		local palette = PALETTES[powerId]
		local at = kit.root.Position
		ball(at, palette.glow, 2, 6 + size * 2, 0.4, Enum.Material.ForceField, 0.2)
		disc(groundOf(kit, at), palette.core, 2, 8 + size * 3, 0.45, 0.3)
		light(at, palette.glow, 12, 3, 0.3)
		sparkBurst(at, palette, 8 + size * 4, 20, 0.5)
	end
end

function Signature.decorate(module, powerId: string, map: { [string]: { any } })
	for name, spec in map do
		local original = module.fx[name]
		module.fx[name] = function(kit)
			if original then
				original(kit)
			end
			local ok, err = pcall(apply, kit, powerId, spec)
			if not ok then
				warn(`[Signature] {powerId}.{name} failed: {err}`)
			end
		end
	end
end

return Signature
