-- The Eight: the colossal statues in the Hall of the Eight (ArtDirection section 5).
-- Eight faceted classical figures, about 30 studs tall, each on a stepped
-- dark-stone pedestal with a bronze inscription band and two warm uplights.
-- Every figure is carved from a proportioned armature (one head is height / 8):
-- the pose is authored as joint positions, elbows and knees are solved from
-- them, and every limb, plane and fold is a part spanning two points. So the
-- gesture comes first and the detail follows it. Ivory marble throughout, one
-- bronze attribute and one gold-leaf detail per figure. If the owner imports a
-- sculpted model to ReplicatedStorage.Assets.Statues.<PowerId>, it replaces
-- the carved figure on the same pedestal.
--
-- Inside a figure, positions are in heads: x is the figure's right, y is up
-- from the soles, and the figure faces -z (the base's LookVector).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Statues = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local V = Vector3.new
local rad = math.rad

local FIGURE_HEIGHT = 30 -- studs, sole to crown, standing
local PEDESTAL_HEIGHT = 9 -- studs at the default figure height
local PART_BUDGET = 220
local SMALL = 0.42 -- heads: pieces smaller than this cast no shadow
local SOLID_BELOW = 2.4 -- heads: only figure parts lower than this collide, so nobody climbs to the heads
local FONT_CARVED = "rbxasset://fonts/families/RomanAntique.json"
local LAMP_COLOR = rgb(255, 206, 152)
local LAMP_RANGE = 46
local LAMP_BRIGHTNESS = 2.4
local LAMP_ANGLE = 58
local LETTER_COLOR = rgb(242, 224, 182)
local SUBLINE_COLOR = rgb(228, 206, 162)

-- Bone lengths in heads (the classical eight-head canon)
local UPPER_ARM, FOREARM = 1.45, 1.22
local THIGH, SHIN = 2.05, 1.75

-- { colour, material, MaterialVariant, colour spread, reflectance }
local FINISH = {
	marble = { rgb(232, 225, 211), M.Marble, "SN_IvoryMarble", 0.03, 0 },
	shade = { rgb(206, 197, 180), M.Marble, "SN_IvoryMarble", 0.02, 0 }, -- marble deep in a hood or fold
	core = { rgb(52, 50, 51), M.Basalt, "SN_DarkStone", 0.05, 0 },
	dark = { rgb(72, 68, 64), M.Slate, "SN_DarkStone", 0.03, 0 },
	darker = { rgb(62, 60, 58), M.Slate, "SN_DarkStone", 0.02, 0 },
	bronze = { rgb(140, 106, 63), M.Metal, "SN_Bronze", 0.04, 0.05 },
	bright = { rgb(181, 139, 79), M.Metal, "SN_Bronze", 0.03, 0.05 }, -- polished bronze where hands wore it
	gold = { rgb(217, 178, 95), M.Foil, "SN_GoldLeaf", 0.01, 0 },
	flame = { rgb(126, 200, 255), M.Neon, nil, 0, 0 },
}

local CLASSES = { Block = "Part", Ball = "Part", Cylinder = "Part", Wedge = "WedgePart", Corner = "CornerWedgePart" }
local SHAPES = { Ball = Enum.PartType.Ball, Cylinder = Enum.PartType.Cylinder }
local SIDES = { 1, -1 }
local NONE = {}
local FRONT = V(0, 0, -1)
local UP = V(0, 1, 0)

-- Pieces -----------------------------------------------------------------------------------

-- Marble is never one flat colour: nudge each piece's value and warmth (seeded, so builds repeat)
local function vary(color: Color3, random: Random, spread: number): Color3
	if spread <= 0 then
		return color
	end
	local value = 1 + random:NextNumber(-spread, spread)
	local warmth = random:NextNumber(-0.006, 0.006)
	return Color3.new(
		math.clamp(color.R * value + warmth, 0, 1),
		math.clamp(color.G * value, 0, 1),
		math.clamp(color.B * value - warmth, 0, 1)
	)
end

-- One piece in world space (studs)
local function stone(c, kind: string, name: string, size: Vector3, cframe: CFrame, finish: string, o: any?): BasePart
	local spec = FINISH[finish]
	local part = Instance.new(CLASSES[kind] or "Part") :: BasePart
	if SHAPES[kind] then
		(part :: any).Shape = SHAPES[kind]
	end
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = spec[2]
	if spec[3] then
		part.MaterialVariant = spec[3]
	end
	part.Color = vary(spec[1], c.random, spec[4])
	part.Reflectance = spec[5]
	part.CastShadow = if o and o.shadow ~= nil then o.shadow else math.max(size.X, size.Y, size.Z) >= SMALL * c.h
	part.CanCollide = o ~= nil and o.solid == true
	-- Size and position go last so setting Shape can't change them
	part.Size = size
	part.CFrame = cframe
	part.Parent = c.parent
	c.count += 1
	return part
end

-- One piece in figure space (heads)
local function place(c, kind: string, name: string, size: Vector3, cf: CFrame, finish: string, o: any?): BasePart
	local world = c.origin * CFrame.new(cf.Position * c.h) * (cf - cf.Position)
	local opts = o
	if not (o and o.solid ~= nil) then
		opts = { solid = cf.Position.Y < SOLID_BELOW, shadow = o and o.shadow }
	end
	return stone(c, kind, name, size * c.h, world, finish, opts)
end

-- Euler turn in degrees: yaw turns the front toward the figure's left, pitch leans the top
-- back, roll lifts the right side
local function turn(yaw: number?, pitch: number?, roll: number?): CFrame
	return CFrame.fromEulerAnglesYXZ(rad(pitch or 0), rad(yaw or 0), rad(roll or 0))
end

-- A frame at `at` whose Y runs along `axis`, its front (-Z) as close to `front` as it can be
local function along(at: Vector3, axis: Vector3, front: Vector3?): CFrame
	local y = axis.Unit
	local x = y:Cross(-(front or FRONT))
	if x.Magnitude < 1e-3 then
		x = y:Cross(V(0, 0, 1))
		if x.Magnitude < 1e-3 then
			x = V(1, 0, 0)
		end
	end
	x = x.Unit
	return CFrame.fromMatrix(at, x, y, x:Cross(y))
end

-- A block spanning two points: `w` across, `d` front to back, overlapping each end a little
-- so joints meet cleanly. o.roll turns it about its own axis (45 shows a ridge, a facet).
local function seg(c, name: string, a: Vector3, b: Vector3, w: number, d: number, finish: string, o: any?): BasePart
	o = o or NONE
	local axis = b - a
	local ext = o.ext or math.min(w, d) * 0.25
	local cf = along((a + b) / 2, axis, o.front)
	if o.roll then
		cf *= CFrame.Angles(0, rad(o.roll), 0)
	end
	if o.shift then
		cf *= CFrame.new(o.shift)
	end
	return place(c, o.kind or "Block", name, V(w, axis.Magnitude + ext * 2, d), cf, finish, o)
end

-- A right-angled wedge: its square corner at p0, one leg to p1, the slope down to p2, `t` thick
local function tri(c, name: string, p0: Vector3, p1: Vector3, p2: Vector3, t: number, finish: string, o: any?): BasePart
	local up = p1 - p0
	local y = up.Unit
	local run = (p2 - p0) - y * (p2 - p0):Dot(y)
	local z = -run.Unit
	local x = y:Cross(z)
	return place(c, "Wedge", name, V(t, up.Magnitude, run.Magnitude), CFrame.fromMatrix(p0 + up / 2 + run / 2, x, y, z), finish, o)
end

-- Any flat triangle (two wedges), `t` thick: facets, shards, crown points
local function facet(c, name: string, a: Vector3, b: Vector3, p: Vector3, t: number, finish: string, o: any?)
	local ab, bp, pa = (b - a).Magnitude, (p - b).Magnitude, (a - p).Magnitude
	if bp >= ab and bp >= pa then
		a, b, p = b, p, a
	elseif pa >= ab and pa >= bp then
		a, b, p = p, a, b
	end
	local dir = (b - a).Unit
	local foot = a + dir * (p - a):Dot(dir)
	if (foot - a).Magnitude > 0.02 then
		tri(c, name, foot, p, a, t, finish, o)
	end
	if (b - foot).Magnitude > 0.02 then
		tri(c, name, foot, p, b, t, finish, o)
	end
end

-- Where the elbow or knee of a two-bone limb from `a` to `b` sits, bent toward `pole`
local function solve(a: Vector3, b: Vector3, l1: number, l2: number, pole: Vector3): Vector3
	local axis = b - a
	local d = math.clamp(axis.Magnitude, 0.05, l1 + l2 - 0.001)
	local u = axis.Unit
	local reach = (d * d + l1 * l1 - l2 * l2) / (2 * d)
	local r = math.sqrt(math.max(l1 * l1 - reach * reach, 0))
	local n = pole - u * pole:Dot(u)
	if n.Magnitude < 1e-4 then
		n = FRONT - u * FRONT:Dot(u)
	end
	return a + u * reach + n.Unit * r
end

-- A ring of short bars (halo, armillary, crown band); `skip` leaves gaps where it broke
local function ring(c, name: string, center: Vector3, normal: Vector3, radius: number, count: number, width: number, thick: number, finish: string, o: any?)
	o = o or NONE
	local n = normal.Unit
	local u = n:Cross(if math.abs(n.Y) > 0.9 then V(1, 0, 0) else UP).Unit
	local v = n:Cross(u)
	local phase = rad(o.phase or 0)
	for i = 0, count - 1 do
		if not (o.skip and o.skip[i]) then
			local a0 = phase + i / count * math.pi * 2
			local a1 = phase + (i + 1) / count * math.pi * 2
			local p0 = center + (u * math.cos(a0) + v * math.sin(a0)) * radius
			local p1 = center + (u * math.cos(a1) + v * math.sin(a1)) * radius
			seg(c, name, p0, p1, width, thick, finish, { front = n, ext = width * 0.3, shadow = o.shadow })
		end
	end
end

-- Anatomy ----------------------------------------------------------------------------------

-- The trunk between two frames, the pelvis (at the hip joints) and the chest (the ribcage
-- centre), tilted against each other for contrapposto. Returns the joints the limbs hang from.
local function trunk(c, pelvis: CFrame, chest: CFrame, o: any?)
	o = o or NONE
	local f = o.finish or "marble"
	local b = o.build or 1
	local bare = o.bare ~= false
	place(c, "Block", "Ribcage", V(1.46 * b, 1.22, 0.9 * b), chest * CFrame.new(0, 0.08, 0.02), f)
	place(c, "Block", "ShoulderGirdle", V(1.84 * b, 0.36, 0.7 * b), chest * CFrame.new(0, 0.54, 0.08), f)
	if bare then
		for _, side in SIDES do
			place(c, "Wedge", "Pectoral", V(0.64 * b, 0.5, 0.2), chest * CFrame.new(side * 0.35 * b, 0.22, -0.43 * b - 0.1) * CFrame.Angles(0, rad(-side * 14), 0), f)
		end
	end
	local waist = pelvis:Lerp(chest, 0.47)
	place(c, "Block", "Waist", V(1.14 * b, 1.04, 0.8 * b), waist, f)
	if bare then
		place(c, "Block", "Abdominals", V(0.5 * b, 0.86, 0.1), waist * CFrame.new(0, -0.02, -0.4 * b - 0.04), f)
		for _, side in SIDES do
			-- the obliques swing out over the hip, the plane the light rakes across
			place(c, "Block", "Oblique", V(0.3, 0.62, 0.62 * b), waist * CFrame.new(side * 0.52 * b, -0.22, -0.02) * CFrame.Angles(0, 0, rad(side * 14)), f)
		end
	end
	place(c, "Block", "Pelvis", V(1.36 * b, 0.82, 0.86 * b), pelvis * CFrame.new(0, 0.14, 0.02), f)
	if o.glutes ~= false then
		for _, side in SIDES do
			place(c, "Block", "Gluteus", V(0.6 * b, 0.64, 0.3), pelvis * CFrame.new(side * 0.3 * b, -0.04, 0.4 * b) * CFrame.Angles(rad(-12), 0, 0), f)
		end
	end
	for _, side in SIDES do
		tri(c, "Trapezius", chest * V(side * 0.18, 0.7, 0.12), chest * V(side * 0.18, 0.98, 0.12), chest * V(side * 0.84 * b, 0.7, 0.12), 0.48 * b, f)
	end
	return {
		shoulder = { [1] = chest * V(0.9 * b, 0.5, 0.06), [-1] = chest * V(-0.9 * b, 0.5, 0.06) },
		hip = { [1] = pelvis * V(0.45 * b, -0.06, 0), [-1] = pelvis * V(-0.45 * b, -0.06, 0) },
		neck = chest * V(0, 0.72, 0.1),
	}
end

-- The head: planes for brow, nose, cheekbones, lip and jaw; the eyes are the shadow under the brow
local function head(c, cf: CFrame, neck: Vector3, o: any?)
	o = o or NONE
	local f = o.finish or "marble"
	local face = o.faceFinish or f
	if neck then
		seg(c, "Neck", neck, cf * V(0, -0.32, 0.06), 0.42 * (o.neck or 1), 0.44 * (o.neck or 1), f, { ext = 0.05 })
	end
	place(c, "Block", "Cranium", V(0.7, 0.66, 0.82), cf * CFrame.new(0, 0.14, 0.06), f)
	place(c, "Block", "Face", V(0.56, 0.56, 0.4), cf * CFrame.new(0, -0.12, -0.2), face)
	place(c, "Block", "Jaw", V(0.5, 0.24, 0.5), cf * CFrame.new(0, -0.36, -0.1), face)
	place(c, "Block", "Brow", V(0.6, 0.1, 0.12), cf * CFrame.new(0, 0.04, -0.42), face)
	place(c, "Wedge", "Nose", V(0.12, 0.27, 0.12), cf * CFrame.new(0, -0.13, -0.46), face)
	for _, side in SIDES do
		place(c, "Block", "Cheekbone", V(0.17, 0.12, 0.1), cf * CFrame.new(side * 0.19, -0.1, -0.41) * CFrame.Angles(0, rad(side * 28), 0), face)
	end
	place(c, "Block", "Lip", V(0.2, 0.05, 0.06), cf * CFrame.new(0, -0.31, -0.42), face)
	place(c, "Block", "Chin", V(0.22, 0.14, 0.1), cf * CFrame.new(0, -0.42, -0.36), face)
	if o.ears ~= false then
		for _, side in SIDES do
			place(c, "Block", "Ear", V(0.07, 0.21, 0.14), cf * CFrame.new(side * 0.37, -0.06, 0.05), f)
		end
	end
	if o.hair == "cap" or o.hair == "curls" then
		place(c, "Block", "Hair", V(0.78, 0.34, 0.9), cf * CFrame.new(0, 0.37, 0.07), f)
		place(c, "Block", "HairBack", V(0.76, 0.54, 0.24), cf * CFrame.new(0, 0.12, 0.4), f)
		if o.hair == "curls" then
			-- a row of short carved locks along the brow line
			for i = -2, 2 do
				place(c, "Block", "Lock", V(0.16, 0.13, 0.14), cf * CFrame.new(i * 0.135, 0.3, -0.36) * CFrame.Angles(rad(20), rad(i * 9), rad(45)), f, { shadow = false })
			end
		end
	end
	if o.beard then
		place(c, "Block", "Beard", V(0.54, 0.3, 0.36), cf * CFrame.new(0, -0.42, -0.2), f)
		tri(c, "BeardPoint", cf * V(0, -0.57, -0.38), cf * V(0, -0.57, -0.04), cf * V(0, -0.78, -0.3), 0.4, f)
	end
end

-- A hand: fingers along `dir`, palm toward `palm`, `curl` from 0 (open) to 1 (fist). Side 1 is right.
local function hand(c, side: number, wrist: Vector3, dir: Vector3, palm: Vector3, curl: number, o: any?)
	o = o or NONE
	local f = o.finish or "marble"
	local s = o.scale or 1
	local frame = along(wrist, dir, palm)
	place(c, "Block", "Palm", V(0.34, 0.42, 0.16) * s, frame * CFrame.new(0, 0.2 * s, 0), f)
	local knuckles = frame * CFrame.new(0, 0.38 * s, -0.01 * s) * CFrame.Angles(rad(-curl * 95), 0, 0)
	if o.fingers == 1 then
		place(c, "Block", "Fingers", V(0.33, 0.36, 0.13) * s, knuckles * CFrame.new(0, 0.17 * s, 0), f)
	else
		-- the outer pair curls a little further than the index pair
		place(c, "Block", "Fingers", V(0.17, 0.38, 0.13) * s, knuckles * CFrame.new(-side * 0.085 * s, 0.18 * s, 0), f)
		place(c, "Block", "Fingers", V(0.16, 0.33, 0.12) * s, knuckles * CFrame.Angles(rad(-curl * 12), 0, 0) * CFrame.new(side * 0.085 * s, 0.15 * s, 0), f)
	end
	place(c, "Block", "Thumb", V(0.11, 0.3, 0.12) * s, frame * CFrame.new(-side * 0.16 * s, 0.1 * s, -0.05 * s) * CFrame.Angles(rad(-20 - curl * 40), 0, rad(side * 35)) * CFrame.new(0, 0.13 * s, 0), f)
end

-- An arm from the shoulder joint: the elbow is solved toward `pole`, then the hand follows
local function arm(c, side: number, shoulder: Vector3, wrist: Vector3, pole: Vector3, o: any?): Vector3
	o = o or NONE
	local f = o.finish or "marble"
	local s = o.scale or 1
	local elbow = o.elbow or solve(shoulder, wrist, UPPER_ARM, FOREARM, pole)
	if o.upper ~= false then
		seg(c, "Deltoid", shoulder + (shoulder - elbow).Unit * 0.14, shoulder:Lerp(elbow, 0.42), 0.56 * s, 0.56 * s, f, { roll = 45 })
		seg(c, "UpperArm", shoulder, elbow, 0.42 * s, 0.45 * s, f)
		seg(c, "Biceps", shoulder:Lerp(elbow, 0.3), shoulder:Lerp(elbow, 0.86), 0.42 * s, 0.46 * s, f, { roll = 45 })
	end
	local fs = o.forearmScale or s
	local ff = o.forearmFinish or f
	if o.lower ~= false then
		seg(c, "Forearm", elbow, wrist, 0.36 * fs, 0.3 * fs, ff)
		seg(c, "ForearmMass", elbow:Lerp(wrist, -0.04), elbow:Lerp(wrist, 0.56), 0.44 * fs, 0.4 * fs, ff, { roll = 45 })
	end
	if o.hand ~= false then
		local h = o.hand or NONE
		hand(c, side, wrist, h.dir or (wrist - elbow), h.palm or V(-side, 0, 0), h.curl or 0.3, { finish = h.finish or ff, scale = h.scale or fs, fingers = h.fingers })
	end
	return elbow
end

-- A leg from the hip joint to the ankle; the knee is solved toward `pole` (default: over the toes)
local function leg(c, side: number, hip: Vector3, ankle: Vector3, toe: Vector3, o: any?): Vector3
	o = o or NONE
	local f = o.finish or "marble"
	local s = o.scale or 1
	local flat = V(toe.X - ankle.X, 0, toe.Z - ankle.Z).Unit
	local knee = o.knee or solve(hip, ankle, THIGH, SHIN, o.pole or flat)
	if o.thigh ~= false then
		seg(c, "Thigh", hip, knee, 0.66 * s, 0.7 * s, f, { front = flat, ext = 0.14 })
		seg(c, "Quadriceps", hip:Lerp(knee, 0.1), hip:Lerp(knee, 0.8), 0.6 * s, 0.6 * s, f, { front = flat, roll = 45, shift = V(side * 0.03, 0, -0.07) })
		local kneeFront = ((knee - hip).Unit + (ankle - knee).Unit).Unit
		place(c, "Block", "Kneecap", V(0.3, 0.3, 0.18) * s, along(knee, kneeFront, flat) * CFrame.new(0, 0, -0.2 * s), f)
	end
	if o.shin ~= false then
		seg(c, "Shin", knee, ankle, 0.42 * s, 0.45 * s, f, { front = flat, ext = 0.1 })
		seg(c, "Calf", knee:Lerp(ankle, 0.04), knee:Lerp(ankle, 0.58), 0.46 * s, 0.46 * s, f, { front = flat, roll = 45, shift = V(0, 0, 0.08) })
	end
	if o.foot ~= false then
		local fs = o.footScale or 1
		local heel = V(ankle.X, math.max(ankle.Y - 0.3, 0.02), ankle.Z) - flat * 0.22
		local tip = V(toe.X, math.max(toe.Y, 0.02), toe.Z)
		local sole = (tip - heel).Unit
		local lift = sole:Cross(flat:Cross(UP)).Unit
		if lift.Y < 0 then
			lift = -lift
		end
		seg(c, "Foot", heel + lift * 0.1, tip + lift * 0.1, 0.36 * fs, 0.2, o.footFinish or f, { front = lift, ext = 0.02 })
		tri(c, "Instep", heel + lift * 0.18 + sole * 0.12, ankle, tip + lift * 0.16 - sole * 0.12, 0.32 * fs, o.footFinish or f)
	end
	return knee
end

-- Pleated drapery: `count` folds hung on an ellipse (rx by rz heads) around `center`, from
-- angle `from` to `to` in degrees (0 is the front, 90 the figure's right). Each fold runs
-- from its top height down to its hem, spreading by `flare`, and alternate folds turn by
-- `zig` degrees so the light picks out every other one.
local function drape(c, name: string, o: any)
	local count = o.count
	local span = rad(o.to - o.from)
	local width = math.abs(span) * ((o.rx + o.rz) / 2 + (o.flare or 0) * 0.6) / count * (o.overlap or 1.3)
	for i = 0, count - 1 do
		local t = (i + 0.5) / count
		local angle = rad(o.from) + span * t
		local dir = V(math.sin(angle), 0, -math.cos(angle))
		local topY = if type(o.top) == "function" then o.top(angle, t) else o.top
		local hemY = (if type(o.hem) == "function" then o.hem(angle, t) else o.hem) + c.random:NextNumber(-1, 1) * (o.ragged or 0.04)
		local flare = o.flare or 0
		local top = o.center + V(dir.X * o.rx, topY, dir.Z * o.rz)
		local bottom = o.center + V(dir.X * (o.rx + flare), hemY, dir.Z * (o.rz + flare))
		if o.sweep then
			bottom += o.sweep * (if o.sweepAt then o.sweepAt(angle, t) else 1)
		end
		local zig = (if i % 2 == 0 then 1 else -1) * (o.zig or 12) + c.random:NextNumber(-3, 3)
		seg(c, name, bottom, top, width * c.random:NextNumber(0.9, 1.1), o.depth or 0.16, o.finish or "marble", { front = dir, roll = zig, ext = 0.02 })
	end
end

-- The figures -----------------------------------------------------------------------------

local carve = {}

-- ATLAS: braced in a lunge, the left knee driving forward, both arms pressing a fractured
-- stone sphere up over his bowed head; a short tunic knotted on the left shoulder
function carve.StrongDude(c)
	local pelvis = CFrame.new(0, 3.95, 0.1) * turn(-8, -3, 3)
	local chest = CFrame.new(0, 5.78, 0.24) * turn(4, 9, -2)
	local j = trunk(c, pelvis, chest, { build = 1.08 })
	head(c, CFrame.new(0, 7.15, 0.14) * turn(0, -12, 0), j.neck, { hair = "curls", beard = true, neck = 1.15 })
	leg(c, -1, j.hip[-1], V(-0.58, 0.36, -0.42), V(-0.7, 0.04, -1.25), { pole = V(-0.05, 0, -1) })
	leg(c, 1, j.hip[1], V(0.6, 0.36, 1.02), V(1.0, 0.04, 0.34), { pole = V(0.1, 0, -1) })
	local sphere = V(0, 8.94, 0.12)
	for _, side in SIDES do
		local wrist = V(side * 0.98, 7.96, 0.12)
		arm(c, side, j.shoulder[side], wrist, V(side, 0.15, 0.1), {
			scale = 1.08,
			hand = { dir = V(-side * 0.9, 0.38, 0), palm = V(-side * 0.25, 1, 0), curl = 0.25 },
		})
	end
	-- the stone: dark, banded in bronze, split by a gold-leaf seam with a shard lifting away
	place(c, "Ball", "Sphere", V(1.64, 1.64, 1.64), CFrame.new(sphere), "dark")
	place(c, "Cylinder", "SphereBand", V(0.12, 1.7, 1.7), CFrame.new(sphere) * CFrame.Angles(0, rad(20), rad(72)), "bronze")
	local seam = { V(-0.42, 0.62, -0.38), V(-0.12, 0.3, -0.72), V(0.18, 0.44, -0.66), V(0.46, 0.08, -0.62) }
	for i = 1, #seam - 1 do
		seg(c, "GoldSeam", sphere + seam[i] * 1.04, sphere + seam[i + 1] * 1.04, 0.07, 0.07, "gold", { ext = 0.03 })
	end
	facet(c, "Shard", sphere + V(0.2, 0.74, -0.42), sphere + V(0.62, 0.52, -0.38), sphere + V(0.42, 0.86, 0.08), 0.22, "dark")
	-- the tunic: belted, short, its hem cut on the diagonal, knotted on the left shoulder
	place(c, "Block", "Belt", V(1.3, 0.17, 0.98), pelvis * CFrame.new(0, 0.62, 0.02), "marble")
	drape(c, "Tunic", {
		center = V(0, 0, 0.12), rx = 0.7, rz = 0.5, top = 4.6, flare = 0.26, count = 12, from = -168, to = 168, zig = 14, depth = 0.15,
		hem = function(angle)
			return 3.05 + 0.32 * math.cos(angle - rad(150))
		end,
	})
	local knot = chest * V(-0.62, 0.62, -0.05)
	seg(c, "TunicFront", knot, pelvis * V(0.55, 0.62, -0.46), 0.5, 0.12, "marble", { front = chest.LookVector })
	seg(c, "TunicBack", knot + V(0, 0, 0.3), pelvis * V(0.55, 0.62, 0.48), 0.56, 0.12, "marble", { front = -chest.LookVector })
	place(c, "Block", "TunicKnot", V(0.3, 0.24, 0.3), CFrame.new(knot) * CFrame.Angles(0.4, 0.5, 0.3), "marble")
	for i = 1, 3 do
		local y = 6.25 - i * 0.32
		seg(c, "TunicFold", chest * V(-0.66, y - 5.78 + 0.08, -0.52), chest * V(-0.1 + i * 0.06, y - 5.78 - 0.3, -0.52), 0.1, 0.1, "marble", { roll = 45 })
	end
	return { aim = V(0, 6.6, 0.1) }
end

-- Pedestal, light and inscription --------------------------------------------------------------

-- Tiers from the floor up: { half width, top height, finish } in studs at the default height
local TIERS = {
	{ 6.8, 0.9, "darker" }, -- footing step
	{ 6.3, 1.7, "dark" }, -- second step
	{ 5.85, 2.25, "darker" }, -- base moulding
	{ 5.55, 2.6, "dark" }, -- torus
	{ 5.2, 6.85, "dark" }, -- the die
	{ 5.55, 7.25, "dark" }, -- bed moulding
	{ 6.0, 7.9, "darker" }, -- corona
	{ 5.65, 8.4, "dark" }, -- cap
	{ 5.35, 9.0, "marble" }, -- the figure's own plinth, cut from the same block
}

local function inscription(c, base: CFrame, s: number, design)
	local y = 4.75 * s
	local plate = stone(c, "Block", "InscriptionBand", V(8.6, 2.3, 0.16) * s, base * CFrame.new(0, y, -5.28 * s), "bronze", { solid = true })
	for _, dy in { -1.27, 1.27 } do
		stone(c, "Block", "InscriptionFillet", V(9.0, 0.12, 0.12) * s, base * CFrame.new(0, y + dy * s, -5.26 * s), "bright", { solid = true, shadow = false })
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Inscription"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 1
	gui.Parent = plate
	local function line(text: string, top: number, height: number, maxSize: number, color: Color3)
		local label = Instance.new("TextLabel")
		label.Name = "Line"
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.05, top)
		label.Size = UDim2.fromScale(0.9, height)
		label.Text = text
		label.FontFace = Font.new(FONT_CARVED)
		label.TextColor3 = color
		label.TextScaled = true
		label.TextWrapped = false
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = maxSize
		cap.Parent = label
		label.Parent = gui
		return label
	end
	line(design.codename, 0.06, 0.58, 72, LETTER_COLOR)
	line(design.title, 0.64, 0.28, 30, SUBLINE_COLOR)
end

local function pedestal(c, base: CFrame, s: number, design)
	local bottom = 0
	for index, tier in TIERS do
		local half, top = tier[1] * s, tier[2] * s
		stone(c, "Block", if index == #TIERS then "Plinth" else "Pedestal", V(half * 2, top - bottom, half * 2), base * CFrame.new(0, (bottom + top) / 2, 0), tier[3], { solid = true })
		bottom = top
	end
	-- the meridian line: a thin bronze inlay round the die, just under the bed moulding
	stone(c, "Block", "MeridianBand", V(10.5, 0.14, 10.5) * s, base * CFrame.new(0, 6.6 * s, 0), "bronze", { solid = true, shadow = false })
	inscription(c, base, s, design)
end

-- Two warm spotlights in bronze cups on brackets at the corona's front corners, off-axis,
-- aimed up at the chest and face so the shadows carve the form
local function uplights(c, base: CFrame, s: number, target: Vector3, shadows: boolean)
	for _, side in SIDES do
		stone(c, "Block", "UplightBracket", V(0.4, 0.55, 0.7) * s, base * CFrame.new(side * 4.3 * s, 7.7 * s, -6.25 * s), "bronze", { solid = true, shadow = false })
		local at = (base * CFrame.new(side * 4.3 * s, 8.2 * s, -6.5 * s)).Position
		local cup = stone(c, "Cylinder", "UplightCup", V(0.7, 1.0, 1.0) * s, along(at, target - at) * CFrame.Angles(0, 0, rad(90)), "bronze", { solid = true, shadow = false })
		local spot = Instance.new("SpotLight")
		spot.Name = "Uplight"
		spot.Face = Enum.NormalId.Right
		spot.Color = LAMP_COLOR
		spot.Range = math.min(LAMP_RANGE * s, 60)
		spot.Brightness = LAMP_BRIGHTNESS
		spot.Angle = LAMP_ANGLE
		spot.Shadows = shadows
		spot.Parent = cup
	end
end

-- The sculpted-mesh upgrade path ------------------------------------------------------------

local CORNERS = { V(1, 1, 1), V(1, 1, -1), V(1, -1, 1), V(1, -1, -1), V(-1, 1, 1), V(-1, 1, -1), V(-1, -1, 1), V(-1, -1, -1) }

local function sculpted(powerId: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Statues")
	local source = folder and folder:FindFirstChild(powerId)
	if source and (source:IsA("Model") or source:IsA("BasePart")) then
		return source
	end
	return nil
end

-- Clones an imported figure, scales it to `height` and stands it on `ground`, facing its front.
-- Measured part by part, so it behaves the same in Studio and in tests.
local function seat(source: Instance, ground: CFrame, height: number): Model
	local figure: Model
	local clone = source:Clone()
	if clone:IsA("Model") then
		figure = clone
	else
		figure = Instance.new("Model")
		clone.Parent = figure
	end
	local parts = {}
	for _, item in figure:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(parts, item)
		end
	end
	if #parts == 0 then
		return figure
	end
	local pivot = if clone:IsA("Model") then clone:GetPivot() else (clone :: BasePart).CFrame
	local frame = pivot - pivot.Position
	local lo = V(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, part in parts do
		local cf = frame:ToObjectSpace(part.CFrame)
		for _, corner in CORNERS do
			local p = cf * (part.Size / 2 * corner)
			lo = V(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
			hi = V(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
		end
	end
	local scale = height / math.max(hi.Y - lo.Y, 0.01)
	local anchor = V((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	for _, part in parts do
		local rel = frame:ToObjectSpace(part.CFrame)
		part.Size *= scale
		part.CFrame = ground * CFrame.new((rel.Position - anchor) * scale) * (rel - rel.Position)
		part.Anchored = true
		part.CanTouch = false
		part.CanCollide = rel.Position.Y - lo.Y < (hi.Y - lo.Y) * 0.3
		for _, child in part:GetChildren() do
			if child:IsA("SpecialMesh") then
				child.Scale *= scale
			elseif child:IsA("Attachment") then
				child.Position *= scale
			end
		end
	end
	return figure
end

-- The Eight ---------------------------------------------------------------------------------

Statues.Order = { "StrongDude", "Ghost", "Shapeshifter", "MachineMaster", "Corruption", "Syntax", "Admin", "Grandmaster" }

-- Plaque text and what each figure carries
Statues.Designs = {
	StrongDude = { codename = "ATLAS", title = "Strong Dude", attribute = "the fractured stone sphere, banded in bronze", gold = "the seam in the stone" },
}

-- Builds one statue. `base` is the centre of the pedestal's bottom on the floor; the statue
-- faces the base's LookVector. opts.height is the figure's standing height in studs (30);
-- opts.heroShadows lists the power ids whose uplights cast shadows.
function Statues.build(powerId: string, base: CFrame, opts: { height: number?, heroShadows: { string }? }?): Model
	local design = Statues.Designs[powerId]
	assert(design, "no statue design for " .. tostring(powerId))
	local height = opts and opts.height or FIGURE_HEIGHT
	local s = height / FIGURE_HEIGHT
	local model = Instance.new("Model")
	model.Name = "Statue_" .. powerId
	model:SetAttribute("PowerId", powerId)
	model:SetAttribute("Codename", design.codename)
	local seed = (table.find(Statues.Order, powerId) or 0) * 7919 + 17
	local c = { parent = model, random = Random.new(seed), count = 0, h = height / 8, origin = base }

	local plinth = Instance.new("Model")
	plinth.Name = "Pedestal"
	plinth.Parent = model
	c.parent = plinth
	pedestal(c, base, s, design)

	local ground = base * CFrame.new(0, PEDESTAL_HEIGHT * s, 0)
	local aim = V(0, 6.5, 0)
	local source = sculpted(powerId)
	if source then
		local figure = seat(source, ground, height)
		figure.Name = "Figure"
		figure.Parent = model
		model:SetAttribute("Sculpted", true)
	else
		local figure = Instance.new("Model")
		figure.Name = "Figure"
		figure.Parent = model
		c.parent = figure
		c.origin = ground * turn(design.turn or 0)
		local result = carve[powerId](c)
		aim = result and result.aim or aim
	end

	local lights = Instance.new("Model")
	lights.Name = "Uplights"
	lights.Parent = model
	c.parent = lights
	local shadows = opts ~= nil and opts.heroShadows ~= nil and table.find(opts.heroShadows, powerId) ~= nil
	uplights(c, base, s, (ground * turn(design.turn or 0)) * (aim * c.h), shadows)
	model:SetAttribute("Parts", c.count)
	if c.count > PART_BUDGET then
		warn(`[Statues] {powerId} uses {c.count} parts (budget {PART_BUDGET})`)
	end
	pcall(function()
		model.WorldPivot = base
	end)
	return model
end

return Statues
