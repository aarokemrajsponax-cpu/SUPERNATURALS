-- How Machine Master looks: industrial gunmetal machinery with cold cyan-blue
-- energy and supernatural BLUE soul fire (never orange). A blaster arm at every
-- degree, a shoulder missile pod and rail guides at Degree 2, and at Degree 3
-- the back-mounted fuel cell whose reinforced conduits feed four nozzles. Its
-- window shows the fuel left; the barrel and nozzles glow with heat (Phase).
-- Also: bolts, pellets, rail beams, missiles, shields, sweeping soul-fire
-- streams with burning patches on the floor, fireballs, pulse mines and the
-- Blue Inferno ultimate. Everything is parts, particles and lights.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Poser = require(script.Parent.Parent.Effects.Poser)

local Attribute = Protocol.Attribute

local Machine = {}

local rgb = Color3.fromRGB
local GUNMETAL = rgb(62, 68, 80)
local STEEL = rgb(118, 126, 140)
local DARK = rgb(26, 29, 36)
local CYAN = rgb(70, 185, 255)
local ICE = rgb(170, 235, 255)
local WHITE = rgb(235, 248, 255)
-- Soul fire: a deep supernatural blue with a pale core
local SOUL = rgb(40, 105, 255)
local SOUL_CORE = rgb(150, 205, 255)
local SMOKE = rgb(150, 160, 175)

local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local GEAR = "SNMachineGear"
local ROLL = CFrame.Angles(0, 0, math.rad(90))
local FORWARD = CFrame.Angles(0, math.rad(90), 0)

-- Where shots leave the gear when it isn't drawn (same offsets as the server)
local MUZZLE = Vector3.new(0.9, 0.5, -1.6)
local NOZZLES = {
	Vector3.new(-1.5, 2.1, -0.4),
	Vector3.new(1.5, 2.1, -0.4),
	Vector3.new(-1.9, 0.4, -0.6),
	Vector3.new(1.9, 0.4, -0.6),
}

Poser.register("MMBrace", { LeftShoulder = { 95, 0, 25 }, LeftElbow = { 60, 0, 0 }, RightShoulder = { 70, 0, -10 }, Torso = { 6, -10, 0 } })
Poser.register("MMRail", { RightShoulder = { 90, 0, 5 }, LeftShoulder = { 85, 0, 40 }, LeftElbow = { 40, 0, 0 }, Torso = { 0, 25, 0 }, Neck = { 0, -15, 0 } })
Poser.register("MMStream", {
	RightShoulder = { 75, 0, -5 },
	LeftShoulder = { 75, 0, 5 },
	RightElbow = { 20, 0, 0 },
	LeftElbow = { 20, 0, 0 },
	Torso = { 10, 0, 0 },
	RightHip = { 15, 0, 8 },
	LeftHip = { -10, 0, -8 },
})
Poser.register("MMBurst", { RightShoulder = { 95, 0, -15 }, LeftShoulder = { 95, 0, 15 }, Torso = { -14, 0, 0 }, Neck = { -10, 0, 0 } })
Poser.register("MMInferno", { RightShoulder = { 140, 0, -35 }, LeftShoulder = { 140, 0, 35 }, Torso = { -16, 0, 0 }, Neck = { -20, 0, 0 } })
-- Anticipation and follow-through keys. The blaster is heavy: he sets his feet
-- before big shots, the kick rocks his shoulders back, and he settles after.
Poser.register("MMSetFeet", { RightShoulder = { 80, 0, 0 }, LeftShoulder = { 70, 0, 40 }, LeftElbow = { 45, 0, 0 }, Torso = { 8, 15, 0 }, RightHip = { 12, 0, 6 }, LeftHip = { -14, 0, -6 } })
Poser.register("MMKick", { RightShoulder = { 115, 0, 5 }, LeftShoulder = { 85, 0, 30 }, Torso = { -10, 18, 0 }, Neck = { -8, 0, 0 } })
Poser.register("MMRailKick", { RightShoulder = { 120, 0, 10 }, LeftShoulder = { 100, 0, 35 }, LeftElbow = { 25, 0, 0 }, Torso = { -18, 22, 0 }, Neck = { -12, -10, 0 }, RightHip = { -8, 0, 0 }, LeftHip = { 10, 0, 0 } })
Poser.register("MMSettle", { RightShoulder = { 60, 0, 0 }, LeftShoulder = { 35, 0, 20 }, Torso = { 4, 10, 0 } })
Poser.register("MMCoil", { RightShoulder = { 30, 0, -20 }, LeftShoulder = { 30, 0, 20 }, RightElbow = { 70, 0, 0 }, LeftElbow = { 70, 0, 0 }, Torso = { 22, 0, 0 }, RightHip = { 25, 0, 0 }, LeftHip = { -15, 0, 0 } })
Poser.register("MMFling", { RightShoulder = { 60, 0, -70 }, LeftShoulder = { 60, 0, 70 }, Torso = { -10, 0, 0 }, Neck = { -12, 0, 0 } })
Poser.register("MMBurstLoad", { RightShoulder = { 70, 0, -5 }, LeftShoulder = { 70, 0, 5 }, RightElbow = { 55, 0, 0 }, LeftElbow = { 55, 0, 0 }, Torso = { 18, 0, 0 }, RightHip = { 20, 0, 5 }, LeftHip = { -20, 0, -5 } })
Poser.register("MMBurstRecoil", { RightShoulder = { 110, 0, -20 }, LeftShoulder = { 110, 0, 20 }, Torso = { -24, 0, 0 }, Neck = { -14, 0, 0 }, RightHip = { -15, 0, 0 }, LeftHip = { 18, 0, 0 } })
Poser.register("MMPlant", { RightShoulder = { 100, 0, 10 }, LeftShoulder = { 30, 0, 20 }, Torso = { 12, -8, 0 }, RightHip = { 10, 0, 0 } })
Poser.register("MMRise", { RightShoulder = { 25, 0, 10 }, LeftShoulder = { 20, 0, -10 }, Torso = { 6, 0, 0 } })
Poser.register("MMSlam", { RightShoulder = { 70, 0, -25 }, LeftShoulder = { 70, 0, 25 }, Torso = { 26, 0, 0 }, Neck = { 15, 0, 0 }, RightHip = { 30, 0, 0 }, LeftHip = { -20, 0, 0 } })
-- The upper body swings with the soul-fire sweep (the streams' angle, scaled down:
-- the hips stay planted and the nozzles carry the rest)
Poser.register("MMSweepLeft", { RightShoulder = { 80, 0, 10 }, LeftShoulder = { 80, 0, 0 }, Torso = { 8, 34, 0 }, Neck = { 0, -12, 0 }, RightHip = { 10, 0, 8 }, LeftHip = { -10, 0, -8 } })
Poser.register("MMSweepRight", { RightShoulder = { 80, 0, 0 }, LeftShoulder = { 80, 0, -10 }, Torso = { 8, -34, 0 }, Neck = { 0, 12, 0 }, RightHip = { 10, 0, 8 }, LeftHip = { -10, 0, -8 } })

local function num(value: any, default: number): number
	return if typeof(value) == "number" and value == value then value else default
end

local function flat(vector: Vector3): Vector3
	local flattened = Vector3.new(vector.X, 0, vector.Z)
	return if flattened.Magnitude > 1e-3 then flattened.Unit else Vector3.new(0, 0, -1)
end

local function turned(direction: Vector3, angle: number): Vector3
	return CFrame.Angles(0, angle, 0):VectorToWorldSpace(direction)
end

local function feet(kit): Vector3
	return if kit.root then kit.root.Position - Vector3.new(0, 2.9, 0) else Vector3.zero
end

local function vector(value: any): Vector3?
	return if typeof(value) == "Vector3" then value else nil
end

-- Gear positions ----------------------------------------------------------------------

-- Effects outlive characters (a wind-up still running when he dies or
-- respawns), so everything here checks the model is still in the world
local function gearPiece(kit, name: string): BasePart?
	local model = kit.model
	local gear = model and model.Parent and model:FindFirstChild(GEAR)
	local piece = gear and gear.Parent and gear:FindFirstChild(name, true)
	return if piece and piece:IsA("BasePart") then piece else nil
end

local function fromRoot(kit, offset: Vector3): Vector3
	local root = kit.root
	return if root and root.Parent then (root.CFrame * CFrame.new(offset)).Position else Vector3.zero
end

local function muzzlePosition(kit): Vector3
	local piece = gearPiece(kit, "SNMuzzle")
	return if piece then piece.Position else fromRoot(kit, MUZZLE)
end

-- Where soul fire comes out: the four nozzles at Degree 3, else the blaster
local function sources(kit, count: number): { Vector3 }
	local list = {}
	for index = 1, count do
		if kit.degree >= 3 then
			local piece = gearPiece(kit, "SNNozzle" .. index)
			table.insert(list, if piece then piece.Position else fromRoot(kit, NOZZLES[index]))
		else
			table.insert(list, muzzlePosition(kit))
		end
	end
	return list
end

-- Small shared looks ---------------------------------------------------------------------

local function pose(kit, name: string, inTime: number, hold: number, outTime: number)
	local model = kit.model
	if model and model.Parent then
		kit.Poser.play(model, name, inTime, hold, outTime)
	end
end

-- Plays poses one after another: { pose, startsAt, inTime, hold, outTime } each.
-- A later key takes over the joints it shares with the one before; the others
-- ease back on their own, so the body moves in overlapping waves, not as one block.
local function sequence(kit, keys: { { any } })
	for _, key in keys do
		if key[2] <= 0 then
			pose(kit, key[1], key[3], key[4], key[5])
		else
			task.delay(key[2], pose, kit, key[1], key[3], key[4], key[5])
		end
	end
end

-- The torso follows a sweep of soul fire: `swings` is a list of { at, side, time }
-- (side 1 = his left, -1 = his right), each easing into that side over `time`
local function sway(kit, swings: { { number } }, outTime: number)
	for index, swing in swings do
		local name = if swing[2] > 0 then "MMSweepLeft" else "MMSweepRight"
		local hold = if index == #swings then 0.05 else 0.5
		task.delay(swing[1], pose, kit, name, swing[3], hold, outTime)
	end
end

local function muzzleFlash(kit, position: Vector3, size: number)
	kit.Vfx.orb(position, ICE, size * 0.4, size, 0.12)
	kit.Vfx.sparks(position, CYAN, math.ceil(size * 4), 18)
	kit.Vfx.glow(position, CYAN, 8 * size, 2, 0.15)
end

local function soulBurst(kit, position: Vector3, radius: number, count: number)
	kit.Vfx.burst(position, {
		colors = ColorSequence.new(SOUL_CORE, SOUL),
		texture = FIRE_TEXTURE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, radius * 0.35), NumberSequenceKeypoint.new(1, 0) }),
		speed = NumberRange.new(radius * 2, radius * 4),
		lifetime = NumberRange.new(0.35, 0.7),
		acceleration = Vector3.new(0, 10, 0),
		drag = 4,
		count = count,
	})
end

local function steam(kit, position: Vector3, count: number)
	kit.Vfx.burst(position, {
		color = SMOKE,
		lightEmission = 0,
		texture = SMOKE_TEXTURE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.2) }),
		transparency = NumberSequence.new(0.4, 1),
		speed = NumberRange.new(3, 7),
		lifetime = NumberRange.new(0.5, 0.9),
		acceleration = Vector3.new(0, 6, 0),
		count = count,
	})
end

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local function key(time: number, value: number)
	return NumberSequenceKeypoint.new(time, value)
end

-- Dissipation: slow blue embers that drift up, flicker and die out
local function embers(kit, position: Vector3, spread: number, count: number)
	kit.Vfx.burst(position, {
		colors = ColorSequence.new(SOUL_CORE, SOUL),
		texture = SPARK_TEXTURE,
		size = NumberSequence.new({ key(0, 0.22), key(0.6, 0.14), key(1, 0) }),
		transparency = NumberSequence.new({ key(0, 0), key(0.5, 0.25), key(1, 1) }),
		speed = NumberRange.new(spread * 0.4, spread * 1.1),
		lifetime = NumberRange.new(0.9, 1.9),
		acceleration = Vector3.new(0, 2.5, 0),
		drag = 2.5,
		count = count,
	})
end

-- Dissipation: a soft grey-blue haze that spreads, rises and thins out slowly
local function haze(kit, position: Vector3, size: number, count: number)
	kit.Vfx.burst(position, {
		color = SMOKE,
		lightEmission = 0,
		texture = SMOKE_TEXTURE,
		size = NumberSequence.new({ key(0, size * 0.5), key(1, size * 1.7) }),
		transparency = NumberSequence.new({ key(0, 0.55), key(0.4, 0.7), key(1, 1) }),
		speed = NumberRange.new(size * 0.6, size * 1.4),
		lifetime = NumberRange.new(1.2, 2.2),
		acceleration = Vector3.new(0, 1.2, 0),
		drag = 2,
		count = count,
	})
end

-- A short-lived patch of blue flame on the floor
local function surfaceFlame(kit, position: Vector3, size: number)
	local patch = kit.Vfx.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.08, size, size),
		CFrame = CFrame.new(position + Vector3.new(0, 0.06, 0)) * ROLL,
		Color = SOUL,
		Transparency = 0.25,
	})
	kit.Vfx.fade(patch, 1.2, { Transparency = 1, Size = Vector3.new(0.08, size * 1.3, size * 1.3) })
	kit.Vfx.burst(position + Vector3.new(0, 0.4, 0), {
		colors = ColorSequence.new(SOUL_CORE, SOUL),
		texture = FIRE_TEXTURE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.3), NumberSequenceKeypoint.new(1, 0) }),
		speed = NumberRange.new(2, 5),
		spread = Vector2.new(20, 20),
		lifetime = NumberRange.new(0.4, 0.8),
		acceleration = Vector3.new(0, 8, 0),
		count = 5,
	})
end

local function explosion(kit, position: Vector3, radius: number, color: Color3, big: boolean)
	local Vfx = kit.Vfx
	Vfx.orb(position, SOUL_CORE, 1, radius * 1.6, 0.3)
	Vfx.shockwave(position, color, 1, radius * 2.2, 0.35)
	Vfx.groundRing(Vector3.new(position.X, position.Y - 0.4, position.Z), color, 1, radius * 2.4, 0.4)
	soulBurst(kit, position, radius, if big then 30 else 14)
	Vfx.glow(position, color, radius * 4, 3, 0.18)
	-- Fast in, slow out: embers and haze hang around after the flash
	embers(kit, position, radius, if big then 18 else 8)
	haze(kit, position, radius * 0.6, if big then 8 else 4)
	Vfx.sound("HeavyHit", position)
	kit.shake(if big then 2.6 else 1.2, if big then 0.4 else 0.25, position)
end

-- A soul-fire stream from a nozzle: one continuous tongue of flame (overlapping
-- tapered sections, a hot pale core near the nozzle that cools to deep blue and
-- thins out toward its reach) plus a jet of flame particles.
-- update(from, look) each frame; destroy() at the end.
local function newStream(kit, length: number, width: number, lit: boolean)
	local Vfx = kit.Vfx
	local sections: { { part: BasePart, share: number, size: number, piece: number } } = {}
	local count = if Vfx.reduced() then 3 else 4
	local piece = length * 0.95 / count
	for index = 1, count do
		local share = index / count
		local size = 0.35 + share * width
		table.insert(sections, {
			part = Vfx.part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(piece * 1.45, size, size),
				Color = SOUL_CORE:Lerp(SOUL, share),
				Transparency = 0.3 + 0.55 * share,
			}),
			share = share,
			size = size,
			piece = piece,
		})
	end
	-- The white-hot core of the first half
	local core = Vfx.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(length * 0.45, 0.25, 0.25), Color = WHITE, Transparency = 0.25 })
	-- A soft rounded flame front where the stream breaks up
	local front = Vfx.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * (0.35 + width), Color = SOUL, Transparency = 0.75 })
	local carrier = Vfx.part({ Transparency = 1, Size = Vector3.one * 0.2 })
	local jet = Instance.new("ParticleEmitter")
	jet.Texture = FIRE_TEXTURE
	jet.Color = ColorSequence.new(SOUL_CORE, SOUL)
	jet.LightEmission = 1
	jet.LightInfluence = 0
	jet.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.6, width * 0.8), NumberSequenceKeypoint.new(1, 0) })
	jet.Transparency = NumberSequence.new(0.1, 1)
	jet.Lifetime = NumberRange.new(0.3, 0.4)
	jet.Speed = NumberRange.new(length / 0.4, length / 0.32)
	jet.SpreadAngle = Vector2.new(8, 4)
	jet.EmissionDirection = Enum.NormalId.Front
	jet.Drag = 1
	jet.Acceleration = Vector3.new(0, 4, 0)
	jet.Rate = if Vfx.reduced() then 15 else 45
	jet.Parent = carrier
	if lit then
		local light = Instance.new("PointLight")
		light.Color = SOUL
		light.Range = length
		light.Brightness = 1.6
		light.Shadows = false
		light.Parent = carrier
	end
	return {
		update = function(from: Vector3, look: Vector3)
			carrier.CFrame = CFrame.lookAt(from, from + look)
			for _, section in sections do
				-- Each section ends at its share of the reach and overlaps the one before
				local mid = from + look * (length * 0.95 * section.share - section.piece * 0.5)
				local flicker = 0.92 + math.random() * 0.16
				section.part.Size = Vector3.new(section.piece * 1.45, section.size * flicker, section.size * flicker)
				section.part.CFrame = CFrame.lookAt(mid, mid + look) * FORWARD
			end
			local coreMid = from + look * (length * 0.225)
			core.CFrame = CFrame.lookAt(coreMid, coreMid + look) * FORWARD
			front.CFrame = CFrame.new(from + look * length * 0.97)
		end,
		destroy = function()
			for _, section in sections do
				section.part:Destroy()
			end
			core:Destroy()
			front:Destroy()
			carrier:Destroy()
		end,
	}
end

-- Draws streams that follow `angleAt(elapsed)` around `direction` until the
-- effect ends (its duration passes or the server stops it)
local function runStreams(kit, count: number, width: number, angleAt: (number) -> number)
	local root = kit.root
	local data = kit.data
	local direction = vector(data.direction)
	local startedAt = data.startedAt
	if not root or not direction or typeof(startedAt) ~= "number" then
		return
	end
	local center = flat(direction)
	local range = num(data.range, 16)
	local duration = num(data.duration, 2)
	local streams = {}
	-- Two lights are enough to throw the cold glow on the floor, however many streams
	for index = 1, count do
		table.insert(streams, newStream(kit, range, width, index <= 2))
	end
	local running = true
	kit.keep(function()
		running = false
	end)
	local patchEvery = if kit.Vfx.reduced() then 0.3 else 0.15
	task.spawn(function()
		local nextPatch = 0
		while running and root.Parent and kit.now() - startedAt < duration + 0.05 do
			local look = turned(center, angleAt(math.max(0, kit.now() - startedAt)))
			local from = sources(kit, count)
			for index, stream in streams do
				stream.update(from[index], look)
			end
			if os.clock() >= nextPatch then
				nextPatch = os.clock() + patchEvery
				surfaceFlame(kit, feet(kit) + look * range * 0.9, width)
			end
			task.wait()
		end
		for _, stream in streams do
			stream.destroy()
		end
	end)
end

-- Wind-ups (shown the moment the local player presses, and for everyone on cast) --------

local windups = {}

function windups.BlasterShot(kit)
	local startup = num(kit.data.startup, 0.06)
	sequence(kit, {
		{ "Aim", 0, 0.03, startup, 0.15 },
		{ "MMKick", startup, 0.03, 0.04, 0.2 },
	})
end

function windups.ChargedShot(kit)
	local root = kit.root
	if not root then
		return
	end
	local startup = num(kit.data.startup, 0.45)
	-- Feet set while it charges, a hard kick on release, then he settles
	sequence(kit, {
		{ "MMSetFeet", 0, 0.1, startup, 0.2 },
		{ "MMKick", startup, 0.04, 0.1, 0.3 },
		{ "MMSettle", startup + 0.16, 0.12, 0.08, 0.35 },
	})
	kit.Vfx.telegraph(root, CYAN, startup)
	-- Energy gathers at the barrel
	local orb = kit.Vfx.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.3, CFrame = CFrame.new(muzzlePosition(kit)), Color = ICE, Transparency = 0.1 })
	kit.Vfx.fade(orb, startup, { Size = Vector3.one * 1.6 })
	task.spawn(function()
		local started = os.clock()
		while orb.Parent and root.Parent and os.clock() - started < startup do
			orb.CFrame = CFrame.new(muzzlePosition(kit))
			task.wait()
		end
	end)
	kit.Vfx.glow(root, CYAN, 10, 2, startup)
end

function windups.ScatterBlast(kit)
	pose(kit, "MMSetFeet", 0.06, num(kit.data.startup, 0.2) + 0.05, 0.2)
	kit.Vfx.sparks(muzzlePosition(kit), CYAN, 6, 8)
	kit.Vfx.sound("Block", muzzlePosition(kit))
end

function windups.ShockPulse(kit)
	local root = kit.root
	if not root then
		return
	end
	-- Coils in, then flings his arms out as the charge lets go
	local startup = num(kit.data.startup, 0.12)
	sequence(kit, {
		{ "MMCoil", 0, 0.06, startup, 0.15 },
		{ "MMFling", startup, 0.04, 0.12, 0.3 },
	})
	for _ = 1, if kit.Vfx.reduced() then 1 else 3 do
		local side = Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5).Unit * 2.5
		kit.Vfx.lightning(root.Position, root.Position + side, ICE, 4, 0.12)
	end
end

function windups.DeflectorShield(kit)
	local startup = num(kit.data.startup, 0.12)
	sequence(kit, {
		{ "MMBrace", 0, 0.06, startup, 0.2 },
		{ "MMPlant", startup, 0.06, 0.25, 0.3 },
	})
end

function windups.Intercept(kit)
	pose(kit, "Aim", 0.02, 0.3, 0.15)
	kit.Vfx.ring(CFrame.new(muzzlePosition(kit)), 0.6, ICE, 0.06, 0.25, 1.4)
end

function windups.RailShot(kit)
	pose(kit, "MMRail", 0.12, num(kit.data.startup, 0.7) + 0.05, 0.25)
end

function windups.MissileVolley(kit)
	pose(kit, "MMSetFeet", 0.08, num(kit.data.startup, 0.3) + 0.4, 0.25)
	local pod = gearPiece(kit, "SNPod")
	if pod then
		kit.Vfx.glow(pod, CYAN, 8, 2, num(kit.data.startup, 0.3) + 0.3)
	end
end

function windups.BarrierProjector(kit)
	local startup = num(kit.data.startup, 0.3)
	sequence(kit, {
		{ "MMCoil", 0, 0.08, startup, 0.15 },
		{ "CastBoth", startup, 0.05, 0.3, 0.3 },
	})
	kit.Vfx.groundRing(feet(kit) + Vector3.new(0, 0.1, 0), CYAN, 1, 6, num(kit.data.startup, 0.3))
end

function windups.SweepingStreams(kit)
	pose(kit, "MMStream", 0.1, num(kit.data.startup, 0.3) + 0.1, 0.2)
end

function windups.PressurizedBurst(kit)
	-- Loads up low and forward; the Burst effect plays the release and recoil
	pose(kit, "MMBurstLoad", 0.05, num(kit.data.startup, 0.15) + 0.05, 0.2)
	for _, position in sources(kit, if kit.degree >= 3 then 4 else 1) do
		kit.Vfx.orb(position, SOUL_CORE, 0.3, 1, num(kit.data.startup, 0.15))
	end
end

function windups.SoulFireballs(kit)
	local startup = num(kit.data.startup, 0.4)
	-- Hunches as the cell pressurises, then opens up to let the nozzles fire
	sequence(kit, {
		{ "MMCoil", 0, 0.1, startup * 0.5, 0.2 },
		{ "Spread", startup * 0.6, 0.12, startup * 0.4 + 0.35, 0.3 },
	})
	-- Each nozzle compresses its fire into a ball
	for _, position in sources(kit, 4) do
		local orb = kit.Vfx.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.3, CFrame = CFrame.new(position), Color = SOUL_CORE, Transparency = 0.15 })
		kit.Vfx.fade(orb, startup, { Size = Vector3.one * 1.4 })
	end
	if kit.root then
		kit.Vfx.glow(kit.root, SOUL, 12, 2, startup)
	end
end

function windups.SoulforgeDevice(kit)
	local startup = num(kit.data.startup, 0.3)
	sequence(kit, {
		{ "Kneel", 0, 0.1, startup, 0.2 },
		{ "MMPlant", startup, 0.06, 0.08, 0.2 },
		{ "MMRise", startup + 0.16, 0.15, 0.05, 0.3 },
	})
end

function windups.BlueInferno(kit)
	pose(kit, "MMInferno", 0.2, num(kit.data.startup, 0.9) + 0.3, 0.3)
end

Machine.predict = windups

function Machine.onCast(kit)
	local windup = windups[kit.data.ability]
	if windup then
		windup(kit)
	end
end

-- Effects the server announces -------------------------------------------------------------

local fx = {}
Machine.fx = fx

function fx.ScatterFire(kit)
	local origin, direction = vector(kit.data.origin), vector(kit.data.direction)
	if not origin or not direction then
		return
	end
	sequence(kit, {
		{ "MMKick", 0, 0.03, 0.08, 0.25 },
		{ "MMSettle", 0.12, 0.12, 0.06, 0.3 },
	})
	local spread = num(kit.data.spread, 36)
	kit.Vfx.cone(CFrame.lookAt(origin, origin + direction), 4, spread + 10, ICE, 0.12)
	muzzleFlash(kit, origin, 2.2)
	steam(kit, origin, 4)
	kit.Vfx.sound("Block", origin)
	kit.shake(0.8, 0.12, origin)
end

function fx.ShockPulse(kit)
	local position = vector(kit.data.position)
	if not position then
		return
	end
	local radius = num(kit.data.radius, 7.5)
	kit.Vfx.shockwave(position, CYAN, 2, radius * 2, 0.3)
	kit.Vfx.groundRing(Vector3.new(position.X, position.Y - 2.8, position.Z), CYAN, 2, radius * 2.2, 0.35)
	for index = 1, if kit.Vfx.reduced() then 3 else 6 do
		local angle = index / 6 * math.pi * 2 + math.random() * 0.5
		local reach = Vector3.new(math.cos(angle), (math.random() - 0.5) * 0.4, math.sin(angle)) * radius
		kit.Vfx.lightning(position, position + reach, ICE, 5, 0.15)
	end
	kit.Vfx.glow(position, CYAN, radius * 3, 3, 0.15)
	-- Static that hangs around and fizzles out
	task.delay(0.12, function()
		kit.Vfx.sparks(position, ICE, if kit.Vfx.reduced() then 3 else 8, 4)
		haze(kit, Vector3.new(position.X, position.Y - 2.4, position.Z), 1, 4)
	end)
	kit.Vfx.sound("Parry", position)
	kit.shake(1.2, 0.2, position)
end

function fx.ShieldUp(kit)
	local position = vector(kit.data.position)
	if not position then
		return
	end
	kit.Vfx.sparks(position, CYAN, 14, 14)
	kit.Vfx.glow(position, CYAN, 12, 2, 0.4)
	kit.Vfx.sound("Block", position)
end

function fx.ShieldBlock(kit)
	local position = vector(kit.data.position)
	if not position then
		return
	end
	kit.Vfx.sparks(position, ICE, 14, 22)
	kit.Vfx.shockwave(position, CYAN, 0.5, 3, 0.2)
	kit.Vfx.sound("Block", position)
	if kit.data.broken then
		fx.ShieldShatter(kit)
	end
end

function fx.ShieldShatter(kit)
	local position = vector(kit.data.position)
	if not position then
		return
	end
	kit.Vfx.debris(position, 10, CYAN, Enum.Material.ForceField, 30)
	kit.Vfx.shockwave(position, ICE, 1, 7, 0.3)
	kit.Vfx.popup(position, "SHIELD BROKEN", ICE, 0.9)
	kit.Vfx.sound("GuardBreak", position)
end

function fx.ShieldEnd(kit)
	local position = vector(kit.data.position)
	if position and kit.data.reason ~= "Broken" then
		kit.Vfx.sparks(position, CYAN, 8, 8)
	end
end

function fx.ProjectorUp(kit)
	local position = vector(kit.data.position)
	if not position then
		return
	end
	local radius = num(kit.data.radius, 8)
	kit.Vfx.groundRing(position + Vector3.new(0, 0.1, 0), CYAN, 2, radius * 2, 0.4)
	kit.Vfx.shockwave(position, ICE, 1, radius * 2, 0.35)
	kit.Vfx.ring(CFrame.lookAt(position + Vector3.new(0, 0.5, 0), position + Vector3.new(0, 2, 0)), radius * 0.4, CYAN, 0.12, 0.4, radius)
	kit.Vfx.sound("Parry", position)
end

function fx.InterceptShot(kit)
	local from, to = vector(kit.data.from), vector(kit.data.to)
	if not from or not to then
		return
	end
	pose(kit, "MMKick", 0.02, 0.08, 0.25)
	kit.Vfx.beam(from, to, WHITE, 0.16, 0.15)
	kit.Vfx.beam(from, to, CYAN, 0.45, 0.25, Enum.Material.ForceField)
	kit.Vfx.sparks(to, ICE, 16, 24)
	kit.Vfx.shockwave(to, CYAN, 0.4, 3, 0.2)
	kit.Vfx.popup(to, "INTERCEPTED", ICE, 0.9)
	kit.Vfx.sound("Parry", to)
end

function fx.InterceptMiss(kit)
	kit.Vfx.sparks(muzzlePosition(kit), SMOKE, 6, 6)
end

-- Rail Shot's laser sight (one per caster, so a cancelled charge can clear it)
local lasers: { [Instance]: BasePart } = setmetatable({}, { __mode = "k" }) :: any

local function clearLaser(model: Instance?)
	local laser = model and lasers[model]
	if model and laser then
		lasers[model] = nil
		laser:Destroy()
	end
end

function fx.RailCharge(kit)
	local origin, direction = vector(kit.data.origin), vector(kit.data.direction)
	if not origin or not direction or not kit.model then
		return
	end
	local length = num(kit.data.length, 70)
	local duration = num(kit.data.duration, 0.7)
	clearLaser(kit.model)
	-- A thin sight line along the exact path the beam will take
	local laser = kit.Vfx.part({
		Size = Vector3.new(0.08, 0.08, length),
		CFrame = CFrame.lookAt(origin + direction * length / 2, origin + direction * length),
		Color = ICE,
		Transparency = 0.3,
	})
	lasers[kit.model] = laser
	kit.Vfx.fade(laser, duration, { Size = Vector3.new(0.22, 0.22, length), Transparency = 0.05 })
	kit.Vfx.orb(muzzlePosition(kit), ICE, 2.5, 0.4, duration)
	if kit.root then
		kit.Vfx.telegraph(kit.root, CYAN, duration)
	end
	kit.Vfx.sound("Parry", origin)
end

function fx.RailFizzle(kit)
	clearLaser(kit.model)
	steam(kit, muzzlePosition(kit), 4)
end

function fx.RailFire(kit)
	local origin, direction = vector(kit.data.origin), vector(kit.data.direction)
	if not origin or not direction then
		return
	end
	clearLaser(kit.model)
	local length = num(kit.data.length, 70)
	local width = num(kit.data.width, 3)
	local finish = origin + direction * length
	sequence(kit, {
		{ "MMRailKick", 0, 0.03, 0.14, 0.3 },
		{ "MMSettle", 0.2, 0.18, 0.1, 0.4 },
	})
	kit.Vfx.beam(origin, finish, WHITE, width * 0.3, 0.25)
	kit.Vfx.beam(origin, finish, CYAN, width * 0.9, 0.4, Enum.Material.ForceField)
	local step = if kit.Vfx.reduced() then 12 else 6
	for distance = 3, length, step do
		local point = origin + direction * distance
		kit.Vfx.ring(CFrame.lookAt(point, point + direction), width * 0.4, CYAN, 0.12, 0.35, width)
	end
	kit.Vfx.shockwave(origin, ICE, 1, 4, 0.2)
	kit.Vfx.sparks(finish, ICE, 18, 26)
	-- The air it burned through stays hazy for a moment
	local puffs = if kit.Vfx.reduced() then 2 else 5
	for index = 1, puffs do
		haze(kit, origin + direction * (length * index / (puffs + 1)), 0.7, 2)
	end
	steam(kit, origin, 4)
	kit.Vfx.sound("GuardBreak", origin)
	kit.shake(1.5, 0.25, origin)
end

function fx.StreamsIgnite(kit)
	local direction = vector(kit.data.direction)
	if not direction or not kit.root then
		return
	end
	local duration = num(kit.data.duration, 0.3)
	local range = num(kit.data.range, 16)
	pose(kit, "MMStream", 0.1, duration + 0.1, 0.2)
	-- The whole area the flames will sweep, drawn on the floor first
	local base = feet(kit) + Vector3.new(0, 0.12, 0)
	kit.Vfx.cone(CFrame.lookAt(base, base + flat(direction)), range, num(kit.data.sweep, 155), SOUL, duration + 0.5)
	for _, position in sources(kit, if kit.degree >= 3 then 4 else 1) do
		kit.Vfx.orb(position, SOUL_CORE, 0.4, 1.4, duration)
	end
	kit.Vfx.telegraph(kit.root, SOUL, duration)
end

function fx.Streams(kit)
	local sweep = num(kit.data.sweep, 120)
	local period = math.max(0.2, num(kit.data.period, 1.6))
	local duration = num(kit.data.duration, 2.4)
	pose(kit, "MMStream", 0.1, duration, 0.25)
	-- The swing peaks on his left a quarter period in, then alternates every half
	local swings = { { 0, 1, period / 4 } }
	local at, side = period / 4, -1
	while at < duration - 0.1 and #swings < 12 do
		table.insert(swings, { at, side, math.min(period / 2, duration - at) })
		at += period / 2
		side = -side
	end
	sway(kit, swings, 0.3)
	-- Same swing as the server: side, back, other side, back, once per period
	-- All four nozzles pour into one wide band of flame
	runStreams(kit, if kit.degree >= 3 then 4 else 1, if kit.degree >= 3 then 1.8 else 3, function(elapsed)
		return math.rad(sweep / 2) * math.sin(2 * math.pi * elapsed / period)
	end)
	if kit.root then
		kit.Vfx.sound("HeavySwing", kit.root)
	end
end

function fx.StreamsEnd(kit)
	local root = kit.root
	if not root then
		return
	end
	for _, position in sources(kit, if kit.degree >= 3 then 4 else 1) do
		steam(kit, position, 5)
	end
	if kit.data.reason == "Fuel" then
		kit.Vfx.popup(root.Position + Vector3.new(0, 1, 0), "OUT OF FUEL", SOUL_CORE, 0.9)
		kit.Vfx.sparks(muzzlePosition(kit), SOUL, 10, 10)
	end
end

function fx.Burst(kit)
	local origin, direction = vector(kit.data.origin), vector(kit.data.direction)
	if not origin or not direction then
		return
	end
	local range = num(kit.data.range, 9)
	local arc = num(kit.data.arc, 70)
	-- The release, then the recoil rocks him back on his heels
	sequence(kit, {
		{ "MMBurst", 0, 0.03, 0.05, 0.2 },
		{ "MMBurstRecoil", 0.06, 0.06, 0.14, 0.4 },
	})
	local base = origin - Vector3.new(0, 1.5, 0)
	local frame = CFrame.lookAt(base, base + flat(direction))
	for _, nozzle in sources(kit, if kit.degree >= 3 then 4 else 1) do
		kit.Vfx.orb(nozzle, SOUL_CORE, 0.5, 1.6, 0.12)
	end
	kit.Vfx.cone(frame, range, arc, SOUL_CORE, 0.25)
	kit.Vfx.cone(frame + Vector3.new(0, 0.6, 0), range * 0.8, arc * 0.7, WHITE, 0.15)
	kit.Vfx.shockwave(origin + direction * 3, SOUL, 1, range * 1.2, 0.3)
	kit.Vfx.burst(origin + direction * 2, {
		colors = ColorSequence.new(SOUL_CORE, SOUL),
		texture = FIRE_TEXTURE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }),
		speed = NumberRange.new(range * 2.5, range * 3.5),
		spread = Vector2.new(arc / 2, 15),
		lifetime = NumberRange.new(0.2, 0.35),
		count = 24,
	})
	-- Dissipation: the cone's embers and haze hang in the air; his boots skid
	embers(kit, origin + direction * range * 0.5, range * 0.3, 10)
	haze(kit, origin + direction * range * 0.4, 1.4, 5)
	if kit.root then
		haze(kit, feet(kit) + Vector3.new(0, 0.3, 0), 0.8, 4)
	end
	kit.Vfx.sound("HeavyHit", origin)
	kit.shake(1.6, 0.25, origin)
end

-- Small enemy shots the burst burned out of the air
function fx.BurnAway(kit)
	local positions = kit.data.positions
	if typeof(positions) ~= "table" then
		return
	end
	for index, position in positions do
		if index > 6 then
			break
		end
		if typeof(position) == "Vector3" then
			kit.Vfx.orb(position, SOUL_CORE, 0.4, 1.6, 0.15)
			embers(kit, position, 2, 4)
			haze(kit, position, 0.6, 2)
		end
	end
end

-- A missile leaves the shoulder pod: hatch flash, a puff of exhaust, a shrug
function fx.MissileLaunch(kit)
	local position = vector(kit.data.position)
	if not position then
		return
	end
	kit.Vfx.orb(position, ICE, 0.3, 1.2, 0.1)
	steam(kit, position, 2)
	if num(kit.data.index, 1) == 1 then
		pose(kit, "MMKick", 0.03, 0.06, 0.25)
	end
	kit.Vfx.sound("Dodge", position)
end

function fx.DevicePlaced(kit)
	local position = vector(kit.data.position)
	if not position then
		return
	end
	local trigger = num(kit.data.trigger, 6)
	-- Lands with a clunk, sparks and a little dust; it isn't live yet
	kit.Vfx.sparks(position + Vector3.new(0, 0.5, 0), CYAN, 10, 10)
	haze(kit, position + Vector3.new(0, 0.2, 0), 0.6, 3)
	kit.Vfx.groundRing(position + Vector3.new(0, 0.1, 0), SMOKE, 0.5, math.min(trigger, 3), 0.3)
	kit.Vfx.sound("Block", position)
end

-- Armed: a pulse sweeps out across the area that sets it off
function fx.DeviceArmed(kit)
	local position = vector(kit.data.position)
	if not position then
		return
	end
	local trigger = num(kit.data.trigger, 6)
	kit.Vfx.groundRing(position + Vector3.new(0, 0.1, 0), SOUL, 1, trigger * 2, 0.4)
	kit.Vfx.glow(position + Vector3.new(0, 1, 0), SOUL, 8, 2, 0.2)
	kit.Vfx.sound("Block", position)
end

function fx.DeviceTrigger(kit)
	local position = vector(kit.data.position)
	if not position then
		return
	end
	local radius = num(kit.data.radius, 8)
	local fuse = num(kit.data.fuse, 0.45)
	-- Shrinking warning ring and a fast blinking core
	kit.Vfx.groundRing(position + Vector3.new(0, 0.12, 0), SOUL_CORE, radius * 2, 1, fuse)
	for blink = 0, 2 do
		task.delay(blink * fuse / 3, function()
			kit.Vfx.glow(position + Vector3.new(0, 1, 0), SOUL_CORE, 10, 4, fuse / 4)
			kit.Vfx.sound("Block", position)
		end)
	end
	kit.Vfx.popup(position + Vector3.new(0, 1, 0), "!", SOUL_CORE, 1.2)
end

function fx.DevicePulse(kit)
	local position = vector(kit.data.position)
	if not position then
		return
	end
	local radius = num(kit.data.radius, 8)
	kit.Vfx.groundRing(position + Vector3.new(0, 0.1, 0), SOUL, 1, radius * 2.2, 0.4)
	kit.Vfx.cracks(position, radius * 0.5, SOUL, if kit.Vfx.reduced() then 4 else 7, 1.6)
	explosion(kit, position + Vector3.new(0, 1, 0), radius * 0.6, SOUL, false)
end

function fx.DeviceEnd(kit)
	local position = vector(kit.data.position)
	if not position or kit.data.reason == "Detonated" then
		return
	end
	if kit.data.reason == "Broken" then
		kit.Vfx.debris(position, 6, GUNMETAL, Enum.Material.Metal, 25)
		kit.Vfx.sparks(position + Vector3.new(0, 0.5, 0), CYAN, 12, 16)
	else
		steam(kit, position + Vector3.new(0, 0.5, 0), 3)
	end
end

function fx.DeviceFail(kit)
	if kit.root and kit.isLocal then
		kit.Vfx.popup(kit.root.Position, "NO ROOM", SMOKE, 0.8)
	end
end

function fx.InfernoIgnite(kit)
	local root = kit.root
	local direction = vector(kit.data.direction)
	if not root or not direction then
		return
	end
	local duration = num(kit.data.duration, 0.9)
	local range = num(kit.data.range, 20)
	pose(kit, "MMInferno", 0.2, duration + 0.2, 0.3)
	kit.Vfx.telegraph(root, SOUL, duration)
	kit.Vfx.popup(root.Position + Vector3.new(0, 2, 0), "BLUE INFERNO", SOUL_CORE, 1.5)
	-- The fuel system ignites: every outlet flares, blue fire rises around him
	for _, position in sources(kit, if kit.degree >= 3 then 4 else 1) do
		kit.Vfx.orb(position, SOUL_CORE, 0.5, 2.2, duration)
	end
	soulBurst(kit, root.Position - Vector3.new(0, 2, 0), 3, 20)
	kit.Vfx.glow(root, SOUL, 30, 4, duration + 0.3)
	kit.Vfx.screenFlash(SOUL, 0.25, 0.35)
	-- The fan it will sweep and the spot the blast will hit, both on the floor
	local base = feet(kit) + Vector3.new(0, 0.12, 0)
	kit.Vfx.cone(CFrame.lookAt(base, base + flat(direction)), range, num(kit.data.sweep, 190), SOUL, duration + 1.5)
	local blast = vector(kit.data.blast)
	if blast then
		local radius = num(kit.data.blastRadius, 8)
		local marker = kit.Vfx.part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, radius * 2, radius * 2),
			CFrame = CFrame.new(blast + Vector3.new(0, 0.1, 0)) * ROLL,
			Color = SOUL_CORE,
			Transparency = 0.75,
		})
		kit.Vfx.fade(marker, duration + 2.3, { Transparency = 0.5 })
	end
	kit.Vfx.sound("HeavySwing", root)
	kit.shake(0.8, duration, root.Position)
end

function fx.InfernoSweep(kit)
	local sweep = num(kit.data.sweep, 150)
	local sweepTime = math.max(0.2, num(kit.data.sweepTime, 1.5))
	pose(kit, "MMStream", 0.1, sweepTime, 0.2)
	sway(kit, { { 0, 1, 0.15 }, { 0.15, -1, sweepTime - 0.15 } }, 0.3)
	-- One pass from left to right, like the server
	runStreams(kit, if kit.degree >= 3 then 4 else 1, if kit.degree >= 3 then 2.6 else 4.5, function(elapsed)
		return math.rad(sweep / 2 - sweep * math.clamp(elapsed / sweepTime, 0, 1))
	end)
	if kit.root then
		kit.Vfx.sound("HeavySwing", kit.root)
	end
end

function fx.InfernoCharge(kit)
	local position = vector(kit.data.position)
	if not position then
		return
	end
	local radius = num(kit.data.radius, 8)
	local duration = num(kit.data.duration, 0.7)
	-- Soul fire compresses into the blast point; a ring shows exactly how far it reaches
	local core = position + Vector3.new(0, 1.5, 0)
	pose(kit, "MMInferno", 0.15, duration, 0.1)
	local orb = kit.Vfx.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * radius * 2, CFrame = CFrame.new(core), Color = SOUL, Material = Enum.Material.ForceField, Transparency = 0.6 })
	kit.Vfx.fade(orb, duration, { Size = Vector3.one * 1.5, Transparency = 0.1 })
	kit.Vfx.groundRing(position + Vector3.new(0, 0.15, 0), SOUL_CORE, radius * 2, radius * 2, duration)
	for _, from in sources(kit, if kit.degree >= 3 then 4 else 1) do
		kit.Vfx.lightning(from, core, SOUL_CORE, 6, duration * 0.6)
	end
	kit.shake(1, duration, position)
end

function fx.InfernoBlast(kit)
	local position = vector(kit.data.position)
	if not position then
		return
	end
	local radius = num(kit.data.radius, 8)
	local core = position + Vector3.new(0, 1.5, 0)
	-- Brings both arms down with the blast, then straightens up spent
	sequence(kit, {
		{ "MMSlam", 0, 0.05, 0.25, 0.3 },
		{ "MMSettle", 0.32, 0.25, 0.2, 0.5 },
	})
	explosion(kit, core, radius, SOUL, true)
	kit.Vfx.orb(core, WHITE, 2, radius * 1.2, 0.25)
	kit.Vfx.cracks(position, radius * 0.8, SOUL, if kit.Vfx.reduced() then 5 else 10, 2.5)
	kit.Vfx.debris(position, 10, DARK, Enum.Material.Slate, 45)
	for _ = 1, if kit.Vfx.reduced() then 3 else 6 do
		local angle = math.random() * math.pi * 2
		local spot = position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * (0.4 + math.random() * 0.5)
		surfaceFlame(kit, spot, 3.5)
	end
	kit.Vfx.screenFlash(SOUL_CORE, 0.4, 0.45)
	kit.shake(3.5, 0.5, position)
end

function fx.InfernoFizzle(kit)
	if kit.root then
		steam(kit, kit.root.Position, 6)
	end
end

function fx.InfernoEnd(kit)
	for _, position in sources(kit, if kit.degree >= 3 then 4 else 1) do
		steam(kit, position, 6)
	end
end

-- Projectiles ----------------------------------------------------------------------------

Machine.projectiles = {}

local function trail(kit, part: BasePart, color: Color3, width: number, lifetime: number)
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, width / 2, 0)
	top.Parent = part
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -width / 2, 0)
	bottom.Parent = part
	local streak = Instance.new("Trail")
	streak.Attachment0 = top
	streak.Attachment1 = bottom
	streak.Color = ColorSequence.new(color)
	streak.LightEmission = 1
	streak.Lifetime = if kit.Vfx.reduced() then lifetime * 0.5 else lifetime
	streak.Transparency = NumberSequence.new(0.1, 1)
	streak.WidthScale = NumberSequence.new({ key(0, 1), key(1, 0.15) })
	streak.Parent = part
end

local function pointLight(parent: Instance, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = parent
end

-- Cyan energy bolt
function Machine.projectiles.Bolt(kit)
	local core = kit.Vfx.part({ Size = Vector3.new(0.26, 0.26, 2.2), Color = WHITE, Transparency = 0 })
	local glow = kit.Vfx.part({ Size = Vector3.new(0.6, 0.6, 2.8), Color = CYAN, Material = Enum.Material.ForceField, Transparency = 0.2 })
	pointLight(core, CYAN, 8, 1.5)
	trail(kit, core, CYAN, 0.3, 0.12)
	local first = true
	return {
		update = function(position: Vector3, velocity: Vector3)
			local frame = if velocity.Magnitude > 0.1 then CFrame.lookAt(position, position + velocity) else CFrame.new(position)
			core.CFrame = frame
			glow.CFrame = frame
			if first then
				first = false
				muzzleFlash(kit, position, 1.2)
				kit.Vfx.sound("Dodge", position)
			end
		end,
		finish = function(position: Vector3, reason: string)
			core:Destroy()
			glow:Destroy()
			if reason == "Destroyed" then
				return
			end
			kit.Vfx.sparks(position, CYAN, 10, 18)
			kit.Vfx.shockwave(position, ICE, 0.4, 2.4, 0.15)
		end,
	}
end

-- One small pellet of Scatter Blast (no light of its own: there are several)
function Machine.projectiles.Pellet(kit)
	local pellet = kit.Vfx.part({ Size = Vector3.new(0.18, 0.18, 1.1), Color = ICE, Transparency = 0 })
	return {
		update = function(position: Vector3, velocity: Vector3)
			pellet.CFrame = if velocity.Magnitude > 0.1 then CFrame.lookAt(position, position + velocity) else CFrame.new(position)
		end,
		finish = function(position: Vector3, reason: string)
			pellet:Destroy()
			if reason == "Hit" or reason == "World" or reason == "Intercepted" then
				kit.Vfx.sparks(position, CYAN, 4, 12)
			end
		end,
	}
end

-- A heavy bolt: bright core, shimmering shell, a ring around it
function Machine.projectiles.HeavyBolt(kit)
	local radius = num(kit.data.radius, 1.2)
	local core = kit.Vfx.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * radius * 1.2, Color = WHITE, Transparency = 0 })
	local shell = kit.Vfx.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * radius * 2, Color = CYAN, Material = Enum.Material.ForceField, Transparency = 0.1 })
	local ring = kit.Vfx.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, radius * 2.6, radius * 2.6), Color = CYAN, Transparency = 0.2 })
	pointLight(core, CYAN, 14, 2)
	trail(kit, core, CYAN, radius, 0.2)
	local spin = 0
	local first = true
	return {
		update = function(position: Vector3, velocity: Vector3, dt: number)
			spin += (dt or 0) * 10
			local frame = if velocity.Magnitude > 0.1 then CFrame.lookAt(position, position + velocity) else CFrame.new(position)
			core.CFrame = frame
			shell.CFrame = frame
			ring.CFrame = frame * FORWARD * CFrame.Angles(spin, 0, 0)
			if first then
				first = false
				muzzleFlash(kit, position, 2.4)
				kit.Vfx.sound("HeavySwing", position)
			end
		end,
		finish = function(position: Vector3, reason: string)
			core:Destroy()
			shell:Destroy()
			ring:Destroy()
			if reason == "Destroyed" then
				return
			end
			local splash = num(kit.data.splash, 3.5)
			kit.Vfx.shockwave(position, CYAN, 1, splash * 2.2, 0.3)
			kit.Vfx.sparks(position, ICE, 20, 28)
			kit.Vfx.glow(position, CYAN, splash * 4, 3, 0.15)
			haze(kit, position, splash * 0.4, 4)
			kit.Vfx.sound("HeavyHit", position)
			kit.shake(1, 0.2, position)
		end,
	}
end

-- A mini-missile: metal body, glowing nose, blue exhaust and a smoke trail
function Machine.projectiles.Missile(kit)
	local body = kit.Vfx.part({ Size = Vector3.new(0.35, 0.35, 1.3), Color = GUNMETAL, Material = Enum.Material.Metal, Transparency = 0 })
	local nose = kit.Vfx.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.38, Color = ICE, Transparency = 0 })
	local exhaust = kit.Vfx.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.45, Color = SOUL_CORE, Transparency = 0.2 })
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEXTURE
	smoke.Color = ColorSequence.new(SMOKE)
	smoke.LightInfluence = 1
	smoke.Size = NumberSequence.new(0.4, 1.4)
	smoke.Transparency = NumberSequence.new(0.5, 1)
	smoke.Lifetime = NumberRange.new(0.4, 0.6)
	smoke.Speed = NumberRange.new(0.5, 1)
	smoke.Rate = if kit.Vfx.reduced() then 8 else 25
	smoke.Parent = exhaust
	trail(kit, body, CYAN, 0.2, 0.15)
	pointLight(exhaust, SOUL, 6, 1.5)
	local first = true
	return {
		update = function(position: Vector3, velocity: Vector3)
			local frame = if velocity.Magnitude > 0.1 then CFrame.lookAt(position, position + velocity) else CFrame.new(position)
			body.CFrame = frame
			nose.CFrame = frame * CFrame.new(0, 0, -0.7)
			exhaust.CFrame = frame * CFrame.new(0, 0, 0.75)
			if first then
				first = false
				steam(kit, position, 3)
				kit.Vfx.sound("Dodge", position)
			end
		end,
		finish = function(position: Vector3, reason: string)
			body:Destroy()
			nose:Destroy()
			exhaust:Destroy()
			if reason == "Destroyed" then
				return
			end
			kit.Vfx.orb(position, ICE, 0.8, 5, 0.25)
			kit.Vfx.sparks(position, CYAN, 14, 24)
			steam(kit, position, 4)
			kit.Vfx.sound("Hit", position)
			kit.shake(0.7, 0.15, position)
		end,
	}
end

-- A compressed ball of soul fire
function Machine.projectiles.Fireball(kit)
	local radius = num(kit.data.radius, 1.1)
	local core = kit.Vfx.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * radius * 1.3, Color = SOUL_CORE, Transparency = 0 })
	local shell = kit.Vfx.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * radius * 2.3, Color = SOUL, Material = Enum.Material.ForceField, Transparency = 0.1 })
	local flames = Instance.new("ParticleEmitter")
	flames.Texture = FIRE_TEXTURE
	flames.Color = ColorSequence.new(SOUL_CORE, SOUL)
	flames.LightEmission = 1
	flames.LightInfluence = 0
	flames.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, radius * 1.4), NumberSequenceKeypoint.new(1, 0) })
	flames.Transparency = NumberSequence.new(0.1, 1)
	flames.Lifetime = NumberRange.new(0.25, 0.4)
	flames.Speed = NumberRange.new(0.5, 2)
	flames.SpreadAngle = Vector2.new(180, 180)
	flames.Rate = if kit.Vfx.reduced() then 10 else 30
	flames.Parent = core
	trail(kit, core, SOUL, radius * 1.2, 0.18)
	pointLight(core, SOUL, 14, 2.5)
	local first = true
	return {
		update = function(position: Vector3)
			core.CFrame = CFrame.new(position)
			shell.CFrame = CFrame.new(position)
			if first then
				first = false
				soulBurst(kit, position, 1, 6)
				kit.Vfx.sound("HeavySwing", position)
			end
		end,
		finish = function(position: Vector3, reason: string)
			core:Destroy()
			shell:Destroy()
			if reason == "Destroyed" then
				return
			end
			if reason == "Hit" or reason == "World" then
				local splash = num(kit.data.splash, 5)
				explosion(kit, position, splash, SOUL, false)
				kit.Vfx.cracks(Vector3.new(position.X, position.Y - 0.5, position.Z), splash * 0.4, SOUL, 4, 1.4)
				surfaceFlame(kit, Vector3.new(position.X, position.Y - 0.8, position.Z), splash * 0.6)
			else
				-- Faded out or shot down: it just puffs away
				soulBurst(kit, position, 0.8, 6)
				steam(kit, position, 3)
			end
		end,
	}
end

-- Persistent look ---------------------------------------------------------------------------

local function firstPart(model: Model, names: { string }): BasePart?
	for _, name in names do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

-- Builds one welded, massless, non-colliding piece of gear on `base`
local function mount(folder: Instance, base: BasePart, offset: CFrame, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Material = Enum.Material.Metal
	for key, value in props do
		if key ~= "Size" then
			(part :: any)[key] = value
		end
	end
	part.Size = props.Size or Vector3.one
	part.CFrame = base.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Name = "SNGearWeld"
	weld.Part0 = base
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	part.Parent = folder
	return part
end

-- A cylinder between two points in `base`'s space
local function conduit(folder: Instance, base: BasePart, from: Vector3, to: Vector3, thickness: number, props: { [string]: any }): Part
	local length = (to - from).Magnitude
	local frame = CFrame.lookAt((from + to) / 2, to) * FORWARD
	local merged = table.clone(props)
	merged.Shape = Enum.PartType.Cylinder
	merged.Size = Vector3.new(length, thickness, thickness)
	return mount(folder, base, frame, merged)
end

-- Blaster arm: armoured housing, barrel with energy coils, a glowing muzzle
local function buildBlaster(kit, folder: Instance, glowing: { BasePart })
	local arm = firstPart(kit.model, { "RightLowerArm", "Right Arm", "RightUpperArm" })
	if not arm then
		return
	end
	local size = arm.Size
	local tip = -size.Y / 2
	mount(folder, arm, CFrame.new(0, -0.05 * size.Y, 0), { Name = "SNHousing", Size = Vector3.new(size.X + 0.3, size.Y * 0.9, size.Z + 0.3), Color = GUNMETAL })
	table.insert(glowing, mount(folder, arm, CFrame.new(size.X / 2 + 0.16, 0, 0), { Name = "SNStripe", Size = Vector3.new(0.1, size.Y * 0.7, size.Z * 0.6), Color = CYAN, Material = Enum.Material.Neon }))
	mount(folder, arm, CFrame.new(0, tip - 0.35, 0), { Name = "SNShroud", Size = Vector3.new(0.8, 1.2, 0.8), Color = GUNMETAL })
	mount(folder, arm, CFrame.new(0, tip - 0.8, 0) * ROLL, { Name = "SNBarrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 0.62, 0.62), Color = DARK })
	for index, depth in { 0.9, 1.35 } do
		table.insert(glowing, mount(folder, arm, CFrame.new(0, tip - depth, 0) * ROLL, {
			Name = "SNCoil" .. index,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.14, 0.82, 0.82),
			Color = CYAN,
			Material = Enum.Material.Neon,
		}))
	end
	if kit.degree >= 2 then
		-- Rail guides along the barrel for the charged beam
		for _, side in { -1, 1 } do
			table.insert(glowing, mount(folder, arm, CFrame.new(side * 0.36, tip - 1, 0), { Name = "SNRail", Size = Vector3.new(0.08, 1.6, 0.12), Color = ICE, Material = Enum.Material.Neon }))
		end
	end
	local muzzle = mount(folder, arm, CFrame.new(0, tip - 1.85, 0), { Name = "SNMuzzle", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.45, Color = ICE, Material = Enum.Material.Neon })
	pointLight(muzzle, CYAN, 6, 1)
end

-- Degree 2: a missile pod on the left shoulder
local function buildPod(kit, folder: Instance)
	local torso = firstPart(kit.model, { "UpperTorso", "Torso", "HumanoidRootPart" })
	if not torso then
		return
	end
	local size = torso.Size
	local at = CFrame.new(-size.X / 2 + 0.15, size.Y / 2 + 0.45, 0.15)
	mount(folder, torso, at, { Name = "SNPod", Size = Vector3.new(1, 0.75, 1.4), Color = GUNMETAL })
	mount(folder, torso, at * CFrame.new(0, -0.5, 0.2), { Name = "SNPodMount", Size = Vector3.new(0.3, 0.4, 0.3), Color = STEEL })
	for index = -1, 1 do
		local hole = at * CFrame.new(index * 0.28, 0.08, -0.7) * FORWARD
		mount(folder, torso, hole, { Name = "SNPodTube", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.26, 0.26), Color = DARK })
		mount(folder, torso, at * CFrame.new(index * 0.28, 0.08, -0.74), { Name = "SNPodTip", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.16, Color = ICE, Material = Enum.Material.Neon })
	end
end

-- Degree 3: the heavy fuel cell on his back, reinforced conduits and four nozzles
local function buildFuelCell(kit, folder: Instance, glowing: { BasePart }, pilots: { ParticleEmitter }): (number) -> ()
	local torso = firstPart(kit.model, { "UpperTorso", "Torso", "HumanoidRootPart" })
	if not torso then
		return function() end
	end
	local size = torso.Size
	local back = size.Z / 2 + 0.72
	local cellHeight = 2.4
	mount(folder, torso, CFrame.new(0, 0.05, back) * ROLL, { Name = "SNFuelCell", Shape = Enum.PartType.Cylinder, Size = Vector3.new(cellHeight, 1.3, 1.3), Color = GUNMETAL })
	for _, y in { -1, 1 } do
		mount(folder, torso, CFrame.new(0, 0.05 + y * cellHeight / 2, back) * ROLL, { Name = "SNCellCap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.22, 1.5, 1.5), Color = STEEL })
		table.insert(glowing, mount(folder, torso, CFrame.new(0, 0.05 + y * 0.6, back) * ROLL, {
			Name = "SNCellBand",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.08, 1.36, 1.36),
			Color = CYAN,
			Material = Enum.Material.Neon,
		}))
	end
	-- The window shows how much fuel is left
	local windowHeight = 1.8
	mount(folder, torso, CFrame.new(0, 0.05, back + 0.66), { Name = "SNCellWindow", Size = Vector3.new(0.6, windowHeight + 0.1, 0.1), Color = DARK })
	local level = mount(folder, torso, CFrame.new(0, 0.05, back + 0.7), { Name = "SNFuelLevel", Size = Vector3.new(0.42, windowHeight, 0.12), Color = SOUL, Material = Enum.Material.Neon })
	pointLight(level, SOUL, 8, 1)
	local levelWeld = level:FindFirstChild("SNGearWeld") :: Weld

	-- Four nozzles: two over the shoulders, two at the hips
	local spots = {
		Vector3.new(-size.X / 2 - 0.35, size.Y / 2 + 0.15, 0.35),
		Vector3.new(size.X / 2 + 0.35, size.Y / 2 + 0.15, 0.35),
		Vector3.new(-size.X / 2 - 0.45, -size.Y / 2 + 0.2, 0.3),
		Vector3.new(size.X / 2 + 0.45, -size.Y / 2 + 0.2, 0.3),
	}
	for index, spot in spots do
		mount(folder, torso, CFrame.new(spot) * FORWARD, { Name = "SNNozzleBody", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.75, 0.48, 0.48), Color = STEEL })
		local tip = mount(folder, torso, CFrame.new(spot + Vector3.new(0, 0, -0.38)) * FORWARD, {
			Name = "SNNozzle" .. index,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 0.56, 0.56),
			Color = SOUL,
			Material = Enum.Material.Neon,
		})
		table.insert(glowing, tip)
		-- A pilot flame that burns brighter as the system heats up
		local pilot = Instance.new("ParticleEmitter")
		pilot.Texture = FIRE_TEXTURE
		pilot.Color = ColorSequence.new(SOUL_CORE, SOUL)
		pilot.LightEmission = 1
		pilot.LightInfluence = 0
		pilot.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		pilot.Transparency = NumberSequence.new(0.2, 1)
		pilot.Lifetime = NumberRange.new(0.25, 0.4)
		pilot.Speed = NumberRange.new(1.5, 3)
		pilot.SpreadAngle = Vector2.new(10, 10)
		pilot.EmissionDirection = Enum.NormalId.Right
		pilot.Acceleration = Vector3.new(0, 3, 0)
		pilot.Rate = 3
		pilot.Parent = tip
		table.insert(pilots, pilot)
		-- Reinforced pressure line from the cell to the nozzle
		local from = Vector3.new(if spot.X < 0 then -0.45 else 0.45, if spot.Y > 0 then 1 else -0.9, back)
		local to = spot + Vector3.new(0, 0, 0.4)
		conduit(folder, torso, from, to, 0.22, { Name = "SNConduit", Color = DARK })
		table.insert(glowing, conduit(folder, torso, from:Lerp(to, 0.45), from:Lerp(to, 0.55), 0.28, { Name = "SNConduitBand", Color = CYAN, Material = Enum.Material.Neon }))
	end

	return function(share: number)
		local height = math.max(0.05, windowHeight * math.clamp(share, 0, 1))
		level.Size = Vector3.new(0.42, height, 0.12)
		if levelWeld then
			levelWeld.C0 = CFrame.new(0, 0.05 - windowHeight / 2 + height / 2, back + 0.7)
		end
		level.Color = if share < 0.25 then SOUL_CORE else SOUL
	end
end

function Machine.appearance(kit)
	local model = kit.model
	if not model then
		return nil
	end
	local old = model:FindFirstChild(GEAR)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = GEAR
	folder.Parent = model
	local glowing: { BasePart } = {}
	local pilots: { ParticleEmitter } = {}
	local connections: { RBXScriptConnection } = {}
	buildBlaster(kit, folder, glowing)
	if kit.degree >= 2 then
		buildPod(kit, folder)
	end
	local setFuel: ((number) -> ())? = nil
	if kit.degree >= 3 then
		setFuel = buildFuelCell(kit, folder, glowing, pilots)
	end

	-- Fuel shown in the cell's window
	local function refreshFuel()
		if setFuel then
			local fuel = num(kit.attribute(Attribute.Resource), 100)
			local max = math.max(1, num(kit.attribute(Attribute.ResourceMax), 100))
			setFuel(fuel / max)
		end
	end
	-- Heat: coils and nozzles brighten, pilot flames grow
	local muzzle = folder:FindFirstChild("SNMuzzle", true)
	local muzzleLight = muzzle and muzzle:FindFirstChildOfClass("PointLight")
	local function refreshHeat()
		local phase = math.clamp(num(kit.attribute(Attribute.Phase), 0), 0, 1)
		for _, part in glowing do
			if part.Name == "SNNozzle1" or part.Name == "SNNozzle2" or part.Name == "SNNozzle3" or part.Name == "SNNozzle4" then
				part.Color = SOUL:Lerp(SOUL_CORE, phase)
			elseif part.Name ~= "SNConduitBand" then
				part.Color = CYAN:Lerp(WHITE, phase * 0.7)
			end
		end
		if muzzleLight then
			muzzleLight.Brightness = 1 + phase * 3
		end
		local rate = if kit.Vfx.reduced() then 1 + phase * 5 else 3 + phase * 22
		for _, pilot in pilots do
			pilot.Rate = rate
		end
	end
	refreshFuel()
	refreshHeat()
	table.insert(connections, model:GetAttributeChangedSignal(Attribute.Resource):Connect(refreshFuel))
	table.insert(connections, model:GetAttributeChangedSignal(Attribute.Phase):Connect(refreshHeat))

	-- Hidden whenever the body is (invisibility, concealment)
	local body = firstPart(model, { "UpperTorso", "Torso" })
	if body then
		local base: { [BasePart]: number } = {}
		for _, item in folder:GetDescendants() do
			if item:IsA("BasePart") then
				base[item] = item.Transparency
			end
		end
		local bodyPart: BasePart = body
		table.insert(connections, bodyPart:GetPropertyChangedSignal("Transparency"):Connect(function()
			for part, transparency in base do
				part.Transparency = math.max(transparency, bodyPart.Transparency)
			end
		end))
	end

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		folder:Destroy()
	end
end

return Machine
