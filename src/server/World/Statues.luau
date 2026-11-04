-- THE EIGHT: the statues in the Hall of the Eight (docs/ArtDirection.md sections 5 and 6).
-- Eight proportioned human figures carved in warm ivory marble, about 30 studs tall (an
-- eight-head canon), each on a dark-stone plinth with a brushed-steel band, a thin light ring
-- in the power's colour and an engraved plate, lit by one warm spotlight from above and a cool
-- rim light. Each figure carries one attribute that names its power: StrongDude gauntlets,
-- Ghost katana, Shapeshifter wolf pelt, MachineMaster machine arm, Corruption cracked mask,
-- Syntax transform-handle frame, Admin command staff, Grandmaster martial robe.
--
-- API
--   Statues.build(powerId, base, opts?) -> Model
--     powerId  one of Statues.Order (the eight ids in src/shared/Powers). Never errors for
--              them: every stage is guarded, and a figure that fails to carve is replaced by
--              a plain robed figure (Model attribute Fallback = true, plus a warning), so a
--              pedestal is never left bare. An unknown id gets the same fallback figure.
--     base     the FLOOR POINT UNDER THE PLINTH. base.Position is the middle of the plinth's
--              bottom face, where it meets the floor; base's LookVector (-Z) is the way the
--              statue faces, toward the people looking at it; +Y is up. Only turning about Y
--              is expected. The plinth is 9 studs tall and the figure stands on top of it, so
--              the statue is about 39 studs high (a few more for a staff or a frame) and its
--              footprint is 13.6 studs square. model.WorldPivot is `base`.
--     opts.height      figure height in studs, sole to crown (default 30); the plinth and the
--                      lights scale with it.
--     opts.shadows     false turns off the shadows of the warm key light (default true).
--     opts.heroShadows list of power ids whose key light casts shadows (when given, the others
--                      do not).
--   Statues.Order    the eight power ids, in hall order.
--   Statues.Designs  per power: codename, title, colour, attribute (plate text and colours).
--
-- The Model "Statue_<PowerId>" holds: Pedestal (the plinth, the only parts that collide),
-- Figure, and Lights (invisible light carriers and the faint motes). Attributes: PowerId,
-- Codename, Parts, HeadAt (world position of the head, for cameras and tests), Sculpted,
-- Fallback. A Model or MeshPart at ReplicatedStorage.Assets.Statues.<PowerId> replaces the
-- carved figure on the same plinth (scaled to the figure height, standing on the plinth).
--
-- Carving: every figure is built from an armature (one head is height / 8). Inside a figure,
-- positions are in heads: x is the figure's right, y is up from the soles, and the figure
-- faces -z (the base's LookVector). The pose is authored as joint positions; elbows and knees
-- are solved from them, and every limb, plane and fold is a part spanning two points, so the
-- gesture comes first and the detail follows it. 120 to 220 parts per statue, small parts do
-- not cast shadows, nothing in the figure collides.

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
local FONT_DISPLAY = "rbxasset://fonts/families/Michroma.json"
local FONT_MONO = "rbxasset://fonts/families/RobotoMono.json"
local KEY_COLOR = rgb(255, 206, 152)
local RIM_COLOR = rgb(140, 184, 255)
local TEXT_COLOR = rgb(236, 236, 230)
local SUBTEXT_COLOR = rgb(176, 184, 192)

-- Bone lengths in heads (the classical eight-head canon)
local UPPER_ARM, FOREARM = 1.45, 1.22
local THIGH, SHIN = 2.05, 1.75

-- { colour, material, MaterialVariant (optional owner add-on), colour spread, reflectance }
local FINISH = {
	marble = { rgb(234, 226, 211), M.Marble, "SN_IvoryMarble", 0.03, 0 },
	shade = { rgb(206, 197, 180), M.Marble, "SN_IvoryMarble", 0.02, 0 }, -- marble deep in a hood or fold
	basalt = { rgb(40, 40, 43), M.Basalt, "SN_DarkStone", 0.04, 0 },
	stone = { rgb(58, 57, 58), M.Slate, "SN_DarkStone", 0.03, 0 },
	steel = { rgb(160, 166, 174), M.Metal, "SN_BrushedSteel", 0.02, 0.1 },
	graphite = { rgb(36, 40, 46), M.Metal, "SN_BrushedSteel", 0.01, 0.05 },
	iron = { rgb(78, 84, 94), M.Metal, "SN_BrushedSteel", 0.03, 0.08 }, -- dark machine steel
	bronze = { rgb(140, 106, 63), M.Metal, "SN_Bronze", 0.04, 0.05 },
	bright = { rgb(181, 139, 79), M.Metal, "SN_Bronze", 0.03, 0.08 }, -- polished bronze where hands wore it
	gold = { rgb(217, 178, 95), M.Foil, "SN_GoldLeaf", 0.01, 0 },
	cloth = { rgb(46, 47, 52), M.Fabric, nil, 0.02, 0 }, -- deep charcoal fabric of the veil
	copper = { rgb(176, 108, 66), M.Metal, "SN_Bronze", 0.03, 0.06 },
	glow = { rgb(126, 200, 255), M.Neon, nil, 0, 0 }, -- takes the power's colour
}

local CLASSES = { Block = "Part", Ball = "Part", Cylinder = "Part", Wedge = "WedgePart", Corner = "CornerWedgePart" }
local SHAPES = { Ball = Enum.PartType.Ball, Cylinder = Enum.PartType.Cylinder }
local SIDES = { 1, -1 }
local NONE = {}
local FRONT = V(0, 0, -1)
local UP = V(0, 1, 0)

-- Joints the poses asked for beyond what a limb can reach (they are stretched to meet; the
-- tests expect none)
local stretched = 0

-- Pieces -----------------------------------------------------------------------------------

-- Marble is never one flat colour: nudge each piece's value and warmth (seeded, so builds repeat)
local function vary(color: Color3, random: any, spread: number): Color3
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

local function finite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e5 and math.abs(v.Y) < 1e5 and math.abs(v.Z) < 1e5
end

-- One piece in world space (studs). o.solid makes it collide (the plinth only), o.shadow forces
-- shadows on or off, o.color overrides the finish colour.
local function stone(c, kind: string, name: string, size: Vector3, cframe: CFrame, finish: string, o: any?): BasePart
	local spec = FINISH[finish] or FINISH.marble
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
	part.Color = if o and o.color then o.color elseif finish == "glow" and c.color then c.color else vary(spec[1], c.random, spec[4])
	part.Reflectance = spec[5]
	part.CastShadow = if o and o.shadow ~= nil then o.shadow else math.max(size.X, size.Y, size.Z) >= SMALL * c.h
	local solid = o ~= nil and o.solid == true
	part.CanCollide = solid
	part.CanQuery = solid
	-- A bad pose must never poison the model with NaN: park the piece and count it
	if not (finite(size) and finite(cframe.Position) and finite(cframe.LookVector) and finite(cframe.UpVector)) then
		c.bad += 1
		size, cframe = V(0.05, 0.05, 0.05), CFrame.new(c.origin.Position)
	end
	-- Size and position go last so setting Shape can't change them
	part.Size = V(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	part.CFrame = cframe
	part.Parent = c.parent
	c.count += 1
	return part
end

-- One piece in figure space (heads)
local function place(c, kind: string, name: string, size: Vector3, cf: CFrame, finish: string, o: any?): BasePart
	local world = c.origin * CFrame.new(cf.Position * c.h) * (cf - cf.Position)
	return stone(c, kind, name, size * c.h, world, finish, o)
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

-- A round bar from `a` to `b`, `d` across (a limb, a staff, a rod, a fold)
local function rod(c, name: string, a: Vector3, b: Vector3, d: number, finish: string, o: any?): BasePart
	o = o or NONE
	local axis = b - a
	local ext = o.ext or 0.02
	local cf = along((a + b) / 2, axis, o.front) * CFrame.Angles(0, 0, rad(90))
	if o.shift then
		cf *= CFrame.new(o.shift)
	end
	return place(c, "Cylinder", name, V(axis.Magnitude + ext * 2, d, d), cf, finish, o)
end

-- A ball of diameter `d` at `at`
local function blob(c, name: string, at: Vector3, d: number, finish: string, o: any?): BasePart
	return place(c, "Ball", name, V(d, d, d), CFrame.new(at), finish, o)
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

-- A thin round disc whose rim shows as a band round whatever it passes through (belts, cuffs, rings)
local function disc(c, name: string, center: Vector3, normal: Vector3, diameter: number, thick: number, finish: string, o: any?): BasePart
	return place(c, "Cylinder", name, V(thick, diameter, diameter), along(center, normal) * CFrame.Angles(0, 0, rad(90)), finish, o)
end

-- Where the elbow or knee of a two-bone limb from `a` to `b` sits, bent toward `pole`
local function solve(a: Vector3, b: Vector3, l1: number, l2: number, pole: Vector3): Vector3
	local axis = b - a
	if axis.Magnitude > l1 + l2 + 0.02 then
		stretched += 1
	end
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

-- A ring of short bars (halo, frame, crown band); o.skip leaves gaps where it broke
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
			seg(c, name, p0, p1, width, thick, finish, { front = n, ext = width * 0.3, shadow = o.shadow, color = o.color })
		end
	end
end

-- Anatomy ----------------------------------------------------------------------------------

-- The heroic trunk between two frames: the pelvis (at the hip joints) and the chest (the
-- ribcage centre, about nipple height), tilted against each other for contrapposto. Round
-- masses (pectorals, lats, obliques) sit on a slab so the front reads as a V that narrows to the
-- waist. o.build widens or narrows everything, o.bare = false skips the front planes (armour or
-- cloth covers them), o.hips = false skips the pelvis (a skirt covers it), o.finish recolours.
-- Returns the joints the limbs and head hang from.
local function trunk(c, pelvis: CFrame, chest: CFrame, o: any?)
	o = o or NONE
	local f = o.finish or "marble"
	local b = o.build or 1
	local waist = pelvis:Lerp(chest, 0.5)
	place(c, "Block", "Ribcage", V(1.3 * b, 1.2, 0.78 * b), chest * CFrame.new(0, 0.04, 0.03), f)
	place(c, "Block", "Waist", V(0.94 * b, 1.0, 0.62 * b), waist * CFrame.new(0, 0.02, 0.02), f)
	for _, side in SIDES do
		-- the latissimus, from under the arm to the waist, so the flank slopes in
		rod(c, "Flank", chest * V(side * 0.64 * b, 0.34, 0.1), waist * V(side * 0.45 * b, -0.18, 0.03), 0.36, f)
		-- the trapezius slopes from the neck to the shoulder
		rod(c, "Trapezius", chest * V(side * 0.14, 0.66, 0.1), chest * V(side * 0.78 * b, 0.5, 0.06), 0.34, f)
	end
	if o.bare ~= false then
		for _, side in SIDES do
			if o.cover ~= (if side == 1 then "right" else "left") then
				blob(c, "Pectoral", (chest * CFrame.new(side * 0.33 * b, 0.2, -0.27 * b)).Position, 0.64 * b, f)
			end
			rod(c, "Oblique", waist * V(side * 0.4 * b, 0.28, -0.04), waist * V(side * 0.42 * b, -0.34, -0.02), 0.3, f)
		end
		place(c, "Block", "Abdomen", V(0.46 * b, 0.9, 0.14), waist * CFrame.new(0, 0.04, -0.3 * b) * turn(0, 4, 0), f)
	end
	if o.hips ~= false then
		place(c, "Block", "Pelvis", V(1.2 * b, 0.68, 0.76 * b), pelvis * CFrame.new(0, 0.12, 0.02), f)
		for _, side in SIDES do
			blob(c, "Hip", (pelvis * CFrame.new(side * 0.46 * b, -0.04, 0)).Position, 0.52, f)
		end
	end
	return {
		shoulder = { [1] = chest * V(0.9 * b, 0.5, 0.04), [-1] = chest * V(-0.9 * b, 0.5, 0.04) },
		hip = { [1] = pelvis * V(0.43 * b, -0.06, 0), [-1] = pelvis * V(-0.43 * b, -0.06, 0) },
		neck = chest * V(0, 0.68, 0.1),
	}
end

-- The head: a rounded skull and the planes of a classical face, cut like stone. `cf` is the head's
-- centre, its front -Z, one head from chin to crown. The face is a smooth egg of balls with the
-- brow ridge, nose, lips, chin and cheekbones laid on it; the shadow under the brow is the eye.
-- o.hair: "curls", "crop", "waves", "long", "hood" (a cowl) or "bald"; o.beard: "short" or "long";
-- o.finish recolours; o.stern lowers the brow, o.soft gives a younger, gentler face.
local function head(c, cf: CFrame, o: any?)
	o = o or NONE
	local f = o.finish or "marble"
	local hair = o.hair or "crop"
	blob(c, "Cranium", (cf * CFrame.new(0, 0.11, 0.07)).Position, 0.76, f)
	blob(c, "Face", (cf * CFrame.new(0, -0.12, -0.07)).Position, 0.6, f)
	blob(c, "Chin", (cf * CFrame.new(0, -0.4, -0.26)).Position, 0.18, f, { shadow = true })
	for _, side in SIDES do
		blob(c, "Cheekbone", (cf * CFrame.new(side * 0.19, -0.13, -0.27)).Position, 0.16, f, { shadow = false })
		-- the brow ridge: a round bar over the eye, lit above and shadowed below
		local lift = if o.stern then 0.012 else 0
		local tilt = if o.stern then 8 else -4 -- stern: inner ends lower; calm: outer ends a touch lower
		place(c, "Cylinder", "Brow", V(0.28, 0.085, 0.085), cf * CFrame.new(side * 0.135, 0.06 - lift, -0.335) * turn(-side * 14, 0, side * tilt), f, { shadow = true })
		blob(c, "Eye", (cf * CFrame.new(side * 0.125, -0.012, -0.326)).Position, 0.075, f, { shadow = false })
		place(c, "Cylinder", "Ear", V(0.035, 0.17, 0.17), cf * CFrame.new(side * 0.36, -0.05, 0.08), f, { shadow = false })
	end
	place(c, "Wedge", "Nose", V(0.075, 0.27, 0.15), cf * CFrame.new(0, -0.1, -0.345), f, { shadow = true })
	blob(c, "NoseTip", (cf * CFrame.new(0, -0.215, -0.395)).Position, 0.095, f, { shadow = false })
	place(c, "Cylinder", "UpperLip", V(0.19, 0.045, 0.045), cf * CFrame.new(0, -0.29, -0.352), f, { shadow = false })
	place(c, "Cylinder", "LowerLip", V(0.16, 0.05, 0.05), cf * CFrame.new(0, -0.328, -0.347), f, { shadow = false })
	if o.beard then
		place(c, "Block", "Beard", V(0.42, 0.26, 0.38), cf * CFrame.new(0, -0.38, -0.12) * turn(0, -6, 0), f)
		if o.beard == "long" then
			seg(c, "BeardFall", cf * V(0, -0.5, -0.28), cf * V(0, -1.0, -0.24), 0.34, 0.2, f, { roll = 45 })
		end
	end
	if hair == "curls" then
		blob(c, "Hair", (cf * CFrame.new(0, 0.15, 0.1)).Position, 0.8, f)
		for i = -2, 2 do
			blob(c, "Curl", (cf * CFrame.new(i * 0.115, 0.3 - math.abs(i) * 0.03, -0.27 + math.abs(i) * 0.045)).Position, 0.15, f, { shadow = false })
		end
		for _, side in SIDES do
			blob(c, "Curl", (cf * CFrame.new(side * 0.33, 0.12, -0.08)).Position, 0.15, f, { shadow = false })
		end
	elseif hair == "crop" then
		blob(c, "Hair", (cf * CFrame.new(0, 0.14, 0.09)).Position, 0.79, f)
		place(c, "Block", "Fringe", V(0.42, 0.07, 0.1), cf * CFrame.new(0, 0.29, -0.28) * turn(0, 14, 0), f, { shadow = false })
	elseif hair == "long" then
		blob(c, "Hair", (cf * CFrame.new(0, 0.14, 0.1)).Position, 0.8, f)
		for _, side in SIDES do
			seg(c, "Lock", cf * V(side * 0.34, 0.1, 0.1), cf * V(side * 0.36, -0.7, 0.2), 0.2, 0.3, f, { roll = 20 })
		end
		place(c, "Block", "Fringe", V(0.4, 0.06, 0.1), cf * CFrame.new(0, 0.3, -0.27) * turn(0, 14, 0), f, { shadow = false })
	elseif hair == "hood" then
		blob(c, "Hood", (cf * CFrame.new(0, 0.1, 0.14)).Position, 0.98, "marble")
		for _, side in SIDES do
			rod(c, "HoodEdge", cf * V(side * 0.36, 0.3, -0.18), cf * V(side * 0.4, -0.34, -0.02), 0.17, "marble")
		end
		rod(c, "HoodBrim", cf * V(-0.34, 0.33, -0.2), cf * V(0.34, 0.33, -0.2), 0.16, "marble")
	elseif hair == "waves" then
		blob(c, "Hair", (cf * CFrame.new(0, 0.14, 0.1)).Position, 0.8, f)
		for _, side in SIDES do
			place(c, "Block", "Waves", V(0.2, 0.42, 0.52), cf * CFrame.new(side * 0.33, 0.02, 0.06) * turn(0, 0, side * 10), f)
		end
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
	place(c, "Block", "Thumb", V(0.11, 0.3, 0.12) * s, frame * CFrame.new(-side * 0.16 * s, 0.1 * s, -0.05 * s) * CFrame.Angles(rad(-20 - curl * 40), 0, rad(side * 35)) * CFrame.new(0, 0.13 * s, 0), f, { shadow = false })
end

-- An arm from the shoulder joint: the elbow is solved toward `pole`, then the hand follows. A
-- rounded deltoid caps the shoulder so the silhouette turns the corner like muscle. Returns the elbow.
local function arm(c, side: number, shoulder: Vector3, wrist: Vector3, pole: Vector3, o: any?): Vector3
	o = o or NONE
	local f = o.finish or "marble"
	local s = o.scale or 1
	local elbow = o.elbow or solve(shoulder, wrist, UPPER_ARM, FOREARM, pole)
	if o.upper ~= false then
		blob(c, "Deltoid", shoulder:Lerp(elbow, 0.08), 0.68 * s, f)
		rod(c, "UpperArm", shoulder, elbow, 0.5 * s, f)
		rod(c, "Biceps", shoulder:Lerp(elbow, 0.22), shoulder:Lerp(elbow, 0.78), 0.6 * s, f)
		blob(c, "Elbow", elbow, 0.44 * s, f)
	end
	local fs = o.forearmScale or s
	local ff = o.forearmFinish or f
	if o.lower ~= false then
		rod(c, "Forearm", elbow, wrist, 0.38 * fs, ff)
		rod(c, "ForearmMass", elbow:Lerp(wrist, -0.04), elbow:Lerp(wrist, 0.5), 0.5 * fs, ff)
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
		rod(c, "Thigh", hip, knee, 0.8 * s, f, { ext = 0.1 })
		rod(c, "Quadriceps", hip:Lerp(knee, 0.14), hip:Lerp(knee, 0.8), 0.9 * s, f, { shift = V(0, 0, 0) })
		blob(c, "Knee", knee, 0.5 * s, f)
	end
	if o.shin ~= false then
		rod(c, "Shin", knee, ankle, 0.5 * s, f, { ext = 0.06 })
		rod(c, "Calf", knee:Lerp(ankle, 0.06), knee:Lerp(ankle, 0.58), 0.62 * s, f)
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
		seg(c, "Foot", heel + lift * 0.1, tip + lift * 0.1, 0.4 * fs, 0.2, o.footFinish or f, { front = lift, ext = 0.02 })
		tri(c, "Instep", heel + lift * 0.18 + sole * 0.12, ankle, tip + lift * 0.16 - sole * 0.12, 0.36 * fs, o.footFinish or f)
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

-- A point on a sphere: `dir` from its centre, pushed out by `out`
local function onSphere(center: Vector3, radius: number, dir: Vector3, out: number?): Vector3
	return center + dir.Unit * (radius + (out or 0))
end

-- The figures -----------------------------------------------------------------------------

local carve = {}

-- ATLAS, programme I (Strong Dude): a wide, easy stance, the right fist on the hip and the left
-- arm raised in a flex; bronze gauntlets to the elbow, a bare chest and a pleated kilt.
function carve.StrongDude(c)
	local pelvis = CFrame.new(0, 3.98, 0.02) * turn(-8, 0, -4)
	local chest = CFrame.new(0, 5.82, 0.08) * turn(8, 3, 5)
	local j = trunk(c, pelvis, chest, { build = 1.1, hips = false })
	local hc = CFrame.new(0.02, 7.5, 0.02) * turn(-14, -4, -3)
	rod(c, "Neck", j.neck, hc * V(0, -0.36, 0.06), 0.46, "marble")
	head(c, hc, { hair = "curls", beard = "short", stern = true })
	-- weight on the left leg, the right leg stepped wide
	leg(c, -1, j.hip[-1], V(-0.62, 0.3, -0.06), V(-0.78, 0.04, -0.88))
	leg(c, 1, j.hip[1], V(1.18, 0.3, -0.2), V(1.55, 0.04, -0.84), { pole = V(0.6, 0, -1) })
	-- left arm raised, fist beside the head
	local lw = V(-1.6, 7.3, -0.15)
	local le = arm(c, -1, j.shoulder[-1], lw, V(-1, -0.3, 0.2), { scale = 1.1, forearmFinish = "bronze", hand = { dir = V(0, 1, 0), palm = V(1, 0, 0), curl = 1, scale = 1.25, finish = "bronze", fingers = 1 } })
	-- right fist on the hip
	local rw = V(0.78, 3.9, -0.32)
	local re = arm(c, 1, j.shoulder[1], rw, V(1, -0.1, 0.35), { scale = 1.1, forearmFinish = "bronze", hand = { dir = V(-0.7, -0.2, -0.3), palm = V(0, 1, 0), curl = 1, scale = 1.25, finish = "bronze", fingers = 1 } })
	place(c, "Block", "Belt", V(1.22, 0.16, 0.9), pelvis * CFrame.new(0, 0.72, 0.03), "bronze")
	drape(c, "Kilt", {
		center = V(0, 0, 0.04), rx = 0.62, rz = 0.46, top = 4.5, flare = 0.3, count = 12, from = -170, to = 170, zig = 14, depth = 0.16,
		hem = function()
			return 3.0
		end,
	})
	drape(c, "KiltUnder", { center = V(0, 0, 0.04), rx = 0.66, rz = 0.5, top = 4.3, flare = 0.4, count = 16, from = -170, to = 170, zig = 9, depth = 0.14, hem = 3.2, finish = "shade" })
	ring(c, "BeltStuds", pelvis * V(0, 0.72, 0), UP, 0.62, 14, 0.12, 0.1, "bright", { shadow = false })
	for _, side in SIDES do
		for k = 1, 3 do
			disc(c, "GauntletBand", (if side == 1 then re else le):Lerp(if side == 1 then rw else lw, 0.1 + k * 0.22), (if side == 1 then rw - re else lw - le), 0.58, 0.1, "bright", { shadow = false })
		end
		for k = 1, 4 do
			blob(c, "Strap", V(side * (0.62 + k * 0.01), 0.35 + k * 0.5, -0.06), 0.14, "bronze", { shadow = false })
		end
	end
	return { aim = V(0, 6.2, 0) }
end

-- The body every figure shares: trunk, neck, head and both legs, from authored joints.
-- o.pelvis, o.chest, o.head are frames; o.legL and o.legR are { ankle, toe, options? };
-- o.trunk and o.face are the options passed to trunk() and head().
local function figure(c, o)
	local j = trunk(c, o.pelvis, o.chest, o.trunk)
	rod(c, "Neck", j.neck, o.head * V(0, -0.36, 0.06), 0.46, "marble")
	head(c, o.head, o.face)
	leg(c, -1, j.hip[-1], o.legL[1], o.legL[2], o.legL[3])
	leg(c, 1, j.hip[1], o.legR[1], o.legR[2], o.legR[3])
	return j
end

-- A hanging sleeve: a wide flap from the elbow down
local function sleeve(c, side: number, elbow: Vector3, drop: number, wide: number, finish: string?)
	for k = 0, 2 do
		local x = side * (0.12 + k * 0.16)
		seg(c, "Sleeve", elbow + V(x * 0.3, 0.1, 0.0), elbow + V(x * 0.9, -drop + k * 0.1, 0.0), wide * (0.7 - k * 0.1), 0.34, finish or "marble", { roll = 20 * (k - 1), ext = 0.04 })
	end
end

-- VEIL, programme II (Ghost): a quiet, upright stance in a layered robe and hakama, both hands
-- folded on the pommel of a katana whose point rests on the slab before him.
function carve.Ghost(c)
	local pelvis = CFrame.new(0, 3.98, 0.02) * turn(4, 0, 0)
	local chest = CFrame.new(0, 5.82, 0.04) * turn(-4, 2, 0)
	local hc = CFrame.new(0, 7.5, 0.0) * turn(6, -3, 0)
	local j = figure(c, { pelvis = pelvis, chest = chest, head = hc, trunk = { bare = false, hips = false },
		face = { hair = "crop" }, legL = { V(-0.5, 0.3, -0.05), V(-0.6, 0.04, -0.85) }, legR = { V(0.52, 0.3, 0.1), V(0.62, 0.04, -0.7), { pole = V(0.1, 0, -1) } } })
	place(c, "Block", "RobeChest", V(1.4, 1.3, 0.86), chest * CFrame.new(0, 0.04, 0.03), "marble")
	place(c, "Block", "RobeWaist", V(1.04, 1.0, 0.7), pelvis:Lerp(chest, 0.5) * CFrame.new(0, 0.02, 0.02), "marble")
	for _, side in SIDES do
		seg(c, "Lapel", chest * V(side * 0.22, 0.64, -0.38), pelvis * V(-side * 0.34, 0.3, -0.42), 0.26, 0.12, "marble", { roll = side * 10 })
		seg(c, "LapelEdge", chest * V(side * 0.3, 0.6, -0.36), pelvis * V(-side * 0.26, 0.3, -0.4), 0.08, 0.15, "shade", { shadow = false })
	end
	rod(c, "Obi", pelvis * V(-0.7, 0.3, 0), pelvis * V(0.7, 0.3, 0), 0.56, "shade", { shadow = false })
	place(c, "Block", "ObiKnot", V(0.3, 0.3, 0.14), pelvis * CFrame.new(0.2, 0.3, -0.4), "shade", { shadow = false })
	drape(c, "Hakama", { center = V(0, 0, 0.04), rx = 0.62, rz = 0.5, top = 4.5, flare = 0.4, count = 22, from = -175, to = 175, zig = 10, depth = 0.14, hem = 0.12 })
	drape(c, "Overrobe", { center = V(0, 0, 0.04), rx = 0.7, rz = 0.54, top = 4.3, flare = 0.5, count = 12, from = 40, to = 320, zig = 8, depth = 0.12, hem = 1.5, finish = "shade" })
	-- topknot and scarf
	blob(c, "Topknot", hc * V(0, 0.52, 0.12), 0.3, "marble", { shadow = false })
	rod(c, "KnotTie", hc * V(-0.12, 0.38, 0.1), hc * V(0.12, 0.38, 0.1), 0.1, "shade", { shadow = false })
	for k = 0, 3 do
		seg(c, "Scarf", chest * V(0.1 + k * 0.05, 0.62 - k * 0.7, 0.4), chest * V(0.1 + k * 0.1, -0.05 - k * 0.7, 0.45), 0.34, 0.08, "shade", { shadow = false })
	end
	-- the katana
	local grip = V(0.02, 4.95, -0.8)
	local ghostR = arm(c, 1, j.shoulder[1], grip + V(0.04, 0, 0), V(1, -0.2, 0.3), { hand = { dir = V(0, -1, 0), palm = V(-1, 0, 0), curl = 1, fingers = 1, scale = 1.1 } })
	local ghostL = arm(c, -1, j.shoulder[-1], grip + V(-0.02, -0.5, 0), V(-1, -0.2, 0.3), { hand = { dir = V(0, 1, 0), palm = V(1, 0, 0), curl = 1, fingers = 1, scale = 1.1 } })
	rod(c, "Grip", V(0.02, 5.4, -0.8), V(0.02, 4.1, -0.8), 0.17, "graphite")
	for k = 0, 5 do
		rod(c, "GripWrap", V(0.02, 5.25 - k * 0.2, -0.8), V(0.02, 5.17 - k * 0.2, -0.8), 0.2, "iron", { shadow = false })
	end
	blob(c, "Pommel", V(0.02, 5.46, -0.8), 0.24, "gold", { shadow = false })
	disc(c, "Tsuba", V(0.02, 4.0, -0.8), UP, 0.62, 0.06, "gold", { shadow = false })
	seg(c, "Blade", V(0.02, 3.96, -0.8), V(0.02, 0.1, -0.8), 0.2, 0.05, "steel", { ext = 0.01 })
	seg(c, "BladeRidge", V(0.02, 3.9, -0.8), V(0.02, 0.4, -0.8), 0.05, 0.08, "steel", { shadow = false, front = V(1, 0, 0) })
	tri(c, "BladeTip", V(0.12, 0.4, -0.8), V(0.12, 0.05, -0.8), V(0.02, 0.05, -0.8), 0.05, "steel", { shadow = false })
	sleeve(c, 1, ghostR, 1.3, 0.8)
	sleeve(c, -1, ghostL, 1.3, 0.8)
	return { aim = V(0, 5.6, 0) }
end

-- CHIMERA, programme III (Shapeshifter): mid-stride, a wolf pelt over the shoulders with the
-- wolf's head resting on the right one, the left hand gathering the pelt at the chest.
function carve.Shapeshifter(c)
	local pelvis = CFrame.new(0, 3.95, 0.02) * turn(-10, 0, 3)
	local chest = CFrame.new(0, 5.8, 0.02) * turn(10, 4, -3)
	local hc = CFrame.new(-0.05, 7.5, -0.02) * turn(18, -6, 3)
	local j = figure(c, { pelvis = pelvis, chest = chest, head = hc, trunk = { build = 1.0, hips = false },
		face = { hair = "waves", beard = "short" }, legL = { V(-0.55, 0.3, 0.55), V(-0.62, 0.04, -0.2), { pole = V(0, 0, -1) } }, legR = { V(0.62, 0.3, -1.0), V(0.7, 0.04, -1.7), { pole = V(0.2, 0, -1) } } })
	place(c, "Block", "Belt", V(1.2, 0.18, 0.84), pelvis * CFrame.new(0, 0.6, 0.02), "bronze")
	disc(c, "BeltDisc", pelvis * V(0, 0.6, -0.44), FRONT, 0.3, 0.06, "bright", { shadow = false })
	drape(c, "Kilt", { center = V(0, 0, 0.04), rx = 0.58, rz = 0.44, top = 4.5, flare = 0.3, count = 12, from = -170, to = 170, zig = 14, depth = 0.16, hem = function(_, t) return 2.9 + 0.2 * math.sin(t * 20) end })
	-- the pelt: a cape of tufted fur across the back and shoulders, ragged at the hem
	drape(c, "Pelt", { center = V(0, 0, 0.12), rx = 1.0, rz = 0.52, top = 6.85, flare = 0.3, count = 26, from = 38, to = 322, zig = 16, depth = 0.2, finish = "shade", hem = function(_, t) return 3.3 + 0.55 * math.abs(math.sin(t * 38)) end })
	for _, side in SIDES do
		blob(c, "PeltShoulder", j.shoulder[side] + V(side * 0.06, 0.22, 0.05), 0.82, "shade")
		seg(c, "PeltEdge", chest * V(side * 0.3, 0.7, -0.4), chest * V(side * 0.58, -0.7, -0.38), 0.24, 0.16, "shade", { roll = side * 25 })
	end
	-- the wolf's head on the right shoulder
	local sk = j.shoulder[1] + V(0.18, 0.55, -0.32)
	blob(c, "WolfSkull", sk, 0.66, "shade")
	seg(c, "WolfSnout", sk + V(0.0, -0.02, -0.2), sk + V(0.12, -0.3, -0.78), 0.28, 0.24, "shade", { roll = 0 })
	blob(c, "WolfNose", sk + V(0.14, -0.33, -0.84), 0.16, "graphite", { shadow = false })
	seg(c, "WolfJaw", sk + V(0.02, -0.2, -0.2), sk + V(0.14, -0.46, -0.66), 0.2, 0.14, "shade", { shadow = false })
	for _, d in { -1, 1 } do
		tri(c, "WolfEar", sk + V(d * 0.2, 0.22, 0.04), sk + V(d * 0.24, 0.6, 0.1), sk + V(d * 0.02, 0.26, 0.08), 0.07, "shade", { shadow = false })
		blob(c, "WolfEye", sk + V(d * 0.15, 0.08, -0.28), 0.07, "graphite", { shadow = false })
		for k = 0, 2 do
			seg(c, "Ruff", sk + V(d * 0.3, -0.1 - k * 0.12, 0.0), sk + V(d * (0.4 + k * 0.05), -0.5 - k * 0.12, 0.1), 0.2, 0.12, "shade", { shadow = false, roll = d * 20 })
		end
	end
	-- left hand gathers the pelt at the chest, right hand open and low
	arm(c, -1, j.shoulder[-1], V(-0.3, 5.7, -0.78), V(-1, -0.3, 0.2), { hand = { dir = V(1, 0, 0), palm = V(0, 0, 1), curl = 0.9, fingers = 1 } })
	arm(c, 1, j.shoulder[1], V(1.55, 4.3, -0.5), V(1, -0.2, 0.3), { hand = { dir = V(0.3, -1, -0.3), palm = V(-1, 0, 0), curl = 0.15 } })
	for _, side in SIDES do
		disc(c, "Bracer", (j.shoulder[side] + V(side * 0.4, -2.3, -0.1)), V(side, -1, 0), 0.5, 0.2, "bronze", { shadow = false })
	end
	ring(c, "Claws", j.neck + V(0, 0.02, -0.04), UP, 0.46, 9, 0.12, 0.1, "bright", { shadow = false })
	return { aim = V(0, 6.2, 0) }
end

-- Held back for a later update (Powers.Unreleased): a tall shrouded form in charcoal cloth with
-- soft folds, tied with a thin copper cord. It stands where the statue will be.
function carve.Veiled(c)
	drape(c, "Veil", { center = V(0, 0, 0), rx = 0.42, rz = 0.36, top = 6.9, flare = 0.55, count = 16, from = -180, to = 180, zig = 14, depth = 0.2, finish = "cloth", hem = 0.06, ragged = 0.08 })
	drape(c, "VeilCape", { center = V(0, 0, 0), rx = 0.62, rz = 0.5, top = 6.3, flare = 0.3, count = 12, from = -180, to = 180, zig = 18, depth = 0.18, finish = "cloth", hem = function(_, t) return 3.3 + 0.35 * math.sin(t * 24) end })
	blob(c, "Cranium", V(0, 7.15, 0), 1.0, "cloth", { shadow = false })
	blob(c, "VeilShoulders", V(0, 6.2, 0), 1.35, "cloth")
	ring(c, "Cord", V(0, 4.3, 0), UP, 0.82, 14, 0.07, 0.07, "copper", { shadow = false })
	seg(c, "CordEnd", V(0.8, 4.3, -0.2), V(0.9, 2.7, -0.3), 0.05, 0.05, "copper", { shadow = false })
	return { aim = V(0, 5.2, 0) }
end

-- FURNACE, programme IV (Machine Master): the right arm is a machine of iron, pistons, gears and a
-- glowing seam, raised and open; the left hand rests on a forge hammer. Goggles on the brow.
function carve.MachineMaster(c)
	local pelvis = CFrame.new(0, 3.98, 0.02) * turn(6, 0, 2)
	local chest = CFrame.new(0, 5.82, 0.04) * turn(-8, 2, -3)
	local hc = CFrame.new(0.0, 7.5, 0.0) * turn(-8, -4, 0)
	local j = figure(c, { pelvis = pelvis, chest = chest, head = hc, trunk = { build = 1.12, hips = false },
		face = { hair = "crop", stern = true }, legL = { V(-0.6, 0.3, 0.05), V(-0.72, 0.04, -0.8) }, legR = { V(0.7, 0.3, -0.35), V(0.84, 0.04, -1.05), { pole = V(0.2, 0, -1) } } })
	-- apron and belt
	place(c, "Block", "Bib", V(0.96, 1.25, 0.1), chest * CFrame.new(0, -0.18, -0.42), "shade")
	place(c, "Block", "Belt", V(1.3, 0.2, 0.92), pelvis * CFrame.new(0, 0.58, 0.02), "iron")
	for k = -2, 2 do
		blob(c, "BeltRivet", pelvis * V(k * 0.22, 0.58, -0.47), 0.1, "bright", { shadow = false })
	end
	drape(c, "Apron", { center = V(0, 0, 0.04), rx = 0.62, rz = 0.46, top = 4.5, flare = 0.3, count = 26, from = -172, to = 172, zig = 12, depth = 0.16, hem = 2.7 })
	place(c, "Block", "ApronFront", V(1.0, 1.5, 0.1), pelvis * CFrame.new(0, -0.7, -0.56), "shade")
	-- goggles on the brow
	for _, side in SIDES do
		disc(c, "Goggle", hc * V(side * 0.15, 0.34, -0.26), FRONT, 0.3, 0.1, "bronze", { shadow = false })
		disc(c, "Lens", hc * V(side * 0.15, 0.34, -0.31), FRONT, 0.2, 0.04, "glow", { shadow = false })
	end
	rod(c, "GoggleStrap", hc * V(-0.4, 0.34, 0.04), hc * V(0.4, 0.34, 0.04), 0.08, "iron", { shadow = false })
	-- the machine arm
	local sh = j.shoulder[1]
	local wrist = V(1.55, 5.7, -1.7)
	local elbow = solve(sh, wrist, UPPER_ARM, FOREARM, V(1, -0.6, 0.3))
	blob(c, "Pauldron", sh + V(0.08, 0.14, 0), 1.0, "iron")
	disc(c, "PauldronRim", sh + V(0.08, -0.14, 0), UP, 1.0, 0.1, "bright", { shadow = false })
	rod(c, "ArmUpper", sh, elbow, 0.62, "iron")
	rod(c, "ArmForearm", elbow, wrist, 0.58, "iron")
	rod(c, "ArmPistonA", sh:Lerp(elbow, 0.1) + V(0.28, 0.2, 0), elbow + V(0.22, 0.2, 0), 0.16, "steel", { shadow = false })
	rod(c, "ArmPistonB", elbow + V(0, 0.3, 0.24), wrist + V(0, 0.28, 0.2), 0.16, "steel", { shadow = false })
	seg(c, "ArmSeam", elbow + V(0, 0.1, -0.24), wrist + V(0, 0.1, -0.2), 0.08, 0.06, "glow", { shadow = false })
	blob(c, "ArmElbow", elbow, 0.7, "iron")
	disc(c, "ElbowGear", elbow + V(0.34, 0, 0), V(1, 0, 0), 0.9, 0.1, "bright")
	ring(c, "GearTeeth", elbow + V(0.4, 0, 0), V(1, 0, 0), 0.48, 10, 0.12, 0.1, "bright", { shadow = false })
	disc(c, "ShoulderGear", sh + V(0.5, -0.12, 0), V(1, 0, 0), 0.7, 0.1, "bright", { shadow = false })
	for k = 0, 2 do
		disc(c, "ForearmBand", elbow:Lerp(wrist, 0.3 + k * 0.25), wrist - elbow, 0.72, 0.1, "bright", { shadow = false })
	end
	-- a three-fingered iron hand, open
	local fw = (wrist - elbow).Unit
	place(c, "Block", "Palm", V(0.5, 0.45, 0.3), along(wrist + fw * 0.2, fw, UP), "iron")
	for k = -1, 1 do
		local base0 = wrist + fw * 0.45 + V(k * 0.17, k * 0.0, 0)
		rod(c, "Finger", base0, base0 + fw * 0.55 + V(k * 0.12, 0.15, 0), 0.14, "steel", { shadow = false })
	end
	-- left arm on the hammer
	arm(c, -1, j.shoulder[-1], V(-1.0, 4.0, -0.6), V(-1, -0.2, 0.3), { hand = { dir = V(0.3, -1, 0), palm = V(1, 0, 0), curl = 1, fingers = 1 } })
	rod(c, "HammerShaft", V(-1.0, 4.3, -0.6), V(-1.15, 0.1, -0.6), 0.18, "bronze")
	place(c, "Block", "HammerHead", V(0.9, 0.55, 0.55), CFrame.new(-1.0, 4.4, -0.6) * turn(0, 0, -4), "iron")
	place(c, "Block", "HammerFace", V(0.12, 0.7, 0.62), CFrame.new(-0.52, 4.4, -0.6), "steel", { shadow = false })
	return { aim = V(0, 6.0, 0) }
end

-- ECLIPSE, programme V (Corruption): a hooded, tattered figure in a dark cracked mask with a
-- seam of light along the fracture; the right hand lifts open and shards hang about it.
function carve.Corruption(c)
	local pelvis = CFrame.new(0, 3.98, 0.02) * turn(-6, 0, 0)
	local chest = CFrame.new(0, 5.82, 0.04) * turn(6, -2, 0)
	local hc = CFrame.new(0, 7.5, 0.02) * turn(10, 5, -4)
	local j = figure(c, { pelvis = pelvis, chest = chest, head = hc, trunk = { bare = false, hips = false },
		face = { hair = "hood" }, legL = { V(-0.5, 0.3, 0.0), V(-0.6, 0.04, -0.8) }, legR = { V(0.5, 0.3, 0.0), V(0.6, 0.04, -0.8) } })
	place(c, "Block", "RobeChest", V(1.42, 1.3, 0.86), chest * CFrame.new(0, 0.04, 0.03), "marble")
	drape(c, "Robe", { center = V(0, 0, 0.04), rx = 0.66, rz = 0.5, top = 4.5, flare = 0.55, count = 26, from = -178, to = 178, zig = 12, depth = 0.15, ragged = 0.28, hem = 0.1 })
	drape(c, "Cloak", { center = V(0, 0, 0.12), rx = 1.05, rz = 0.6, top = 6.9, flare = 0.5, count = 18, from = 60, to = 300, zig = 14, depth = 0.18, ragged = 0.4, finish = "shade", hem = 0.4 })
	-- the mask: dark, with a fracture of light and two eye slits
	place(c, "Ball", "Mask", V(0.64, 0.84, 0.3), hc * CFrame.new(0, -0.06, -0.26), "graphite")
	place(c, "Block", "MaskBrow", V(0.5, 0.08, 0.1), hc * CFrame.new(0, 0.1, -0.4), "graphite", { shadow = false })
	for _, side in SIDES do
		seg(c, "EyeSlit", hc * V(side * 0.14, 0.02, -0.4), hc * V(side * 0.2, 0.0, -0.4), 0.05, 0.03, "glow", { shadow = false, roll = side * 20 })
		seg(c, "MaskCheek", hc * V(side * 0.22, -0.2, -0.32), hc * V(side * 0.12, -0.4, -0.34), 0.1, 0.06, "graphite", { shadow = false })
	end
	local crack = { V(0.06, 0.36, -0.34), V(0.02, 0.2, -0.4), V(0.1, 0.06, -0.41), V(0.04, -0.08, -0.42), V(-0.06, -0.2, -0.41), V(-0.02, -0.34, -0.37) }
	for k = 1, #crack - 1 do
		seg(c, "Crack", hc * crack[k], hc * crack[k + 1], 0.035, 0.03, "glow", { shadow = false })
	end
	seg(c, "CrackBranch", hc * crack[3], hc * V(0.26, -0.04, -0.34), 0.03, 0.03, "glow", { shadow = false })
	seg(c, "CrackBranch", hc * crack[5], hc * V(-0.22, -0.3, -0.34), 0.03, 0.03, "glow", { shadow = false })
	-- right hand open, shards hanging around it
	local palm = V(1.5, 5.9, -1.35)
	local corR = arm(c, 1, j.shoulder[1], palm, V(1, -0.4, 0.3), { hand = { dir = V(0, 1, -0.3), palm = V(0, 1, 0), curl = 0.1 } })
	local corL = arm(c, -1, j.shoulder[-1], V(-0.85, 4.4, -0.5), V(-1, -0.2, 0.3), { hand = { dir = V(0.2, -1, -0.2), palm = V(1, 0, 0), curl = 0.3 } })
	sleeve(c, 1, corR, 1.0, 0.8)
	sleeve(c, -1, corL, 1.4, 0.8)
	local shards = { V(1.1, 7.0, -1.5), V(1.9, 7.4, -1.2), V(1.6, 6.5, -1.9), V(2.2, 6.7, -1.0), V(1.2, 7.8, -1.1), V(2.0, 6.0, -1.7), V(0.7, 6.9, -1.9), V(2.4, 7.5, -1.5) }
	for k, p in shards do
		facet(c, "Shard", p, p + V(0.28, 0.1, 0.05), p + V(0.05, 0.42 + (k % 3) * 0.1, -0.1), 0.06, if k % 2 == 0 then "glow" else "graphite", { shadow = false })
	end
	return { aim = V(0, 6.4, 0) }
end

-- LATTICE, programme VI (Syntax): a figure in a long tunic with a floating wire-cube of steel
-- in front of his raised hand, three axis handles through its centre, the left hand drawing one out.
function carve.Syntax(c)
	local pelvis = CFrame.new(0, 3.98, 0.02) * turn(-5, 0, 2)
	local chest = CFrame.new(0, 5.82, 0.04) * turn(8, 2, -2)
	local hc = CFrame.new(0, 7.5, 0.02) * turn(-10, -2, 0)
	local j = figure(c, { pelvis = pelvis, chest = chest, head = hc, trunk = { bare = false, hips = false },
		face = { hair = "waves" }, legL = { V(-0.5, 0.3, 0.1), V(-0.6, 0.04, -0.7) }, legR = { V(0.55, 0.3, -0.25), V(0.65, 0.04, -0.95), { pole = V(0, 0, -1) } } })
	place(c, "Block", "TunicChest", V(1.4, 1.3, 0.86), chest * CFrame.new(0, 0.04, 0.03), "marble")
	place(c, "Block", "Collar", V(0.62, 0.2, 0.5), chest * CFrame.new(0, 0.7, 0.04), "shade", { shadow = false })
	rod(c, "Belt", pelvis * V(-0.66, 0.5, 0), pelvis * V(0.66, 0.5, 0), 0.4, "steel", { shadow = false })
	drape(c, "Tunic", { center = V(0, 0, 0.04), rx = 0.6, rz = 0.46, top = 4.5, flare = 0.32, count = 28, from = -172, to = 172, zig = 12, depth = 0.15, hem = 1.9 })
	-- the frame
	local mid = V(0.55, 6.6, -2.2)
	local h = 0.8
	local pts = {}
	for ix = -1, 1, 2 do
		for iy = -1, 1, 2 do
			for iz = -1, 1, 2 do
				pts[#pts + 1] = mid + V(ix * h, iy * h, iz * h)
				blob(c, "FrameCorner", mid + V(ix * h, iy * h, iz * h), 0.2, "gold", { shadow = false })
			end
		end
	end
	for a = 1, 8 do
		for b = a + 1, 8 do
			local d = pts[a] - pts[b]
			local diff = (math.abs(d.X) > 0.1 and 1 or 0) + (math.abs(d.Y) > 0.1 and 1 or 0) + (math.abs(d.Z) > 0.1 and 1 or 0)
			if diff == 1 then
				rod(c, "FrameEdge", pts[a], pts[b], 0.09, "steel", { shadow = false, ext = 0 })
			end
		end
	end
	for _, axis in { V(1, 0, 0), V(0, 1, 0), V(0, 0, -1) } do
		rod(c, "Handle", mid - axis * 0.2, mid + axis * 1.6, 0.07, "gold", { shadow = false })
		blob(c, "HandleTip", mid + axis * 1.75, 0.22, "glow", { shadow = false })
	end
	blob(c, "FrameCore", mid, 0.26, "glow", { shadow = false })
	-- hands: right bears the frame from below, left draws the sideways handle
	local synR = arm(c, 1, j.shoulder[1], V(1.0, 5.55, -1.6), V(1, -0.5, 0.3), { hand = { dir = V(-0.2, 0.5, -1), palm = V(0, 1, 0), curl = 0.2 } })
	local synL = arm(c, -1, j.shoulder[-1], V(-0.5, 6.35, -1.7), V(-1, -0.3, 0.2), { hand = { dir = V(1, 0.1, -0.5), palm = V(0, 1, 0), curl = 0.55 } })
	sleeve(c, 1, synR, 0.8, 0.7)
	sleeve(c, -1, synL, 0.8, 0.7)
	return { aim = V(0, 6.4, -0.5) }
end

-- WARDEN, programme VII (Admin): a robed figure with a tall command staff in the right hand,
-- the left palm raised, a diadem, a sash and mantle. The staff is topped by a ring and a stone.
function carve.Admin(c)
	local pelvis = CFrame.new(0, 3.98, 0.02) * turn(-4, 0, 0)
	local chest = CFrame.new(0, 5.82, 0.04) * turn(6, 0, -2)
	local hc = CFrame.new(0, 7.5, 0.0) * turn(-6, 3, 0)
	local j = figure(c, { pelvis = pelvis, chest = chest, head = hc, trunk = { bare = false, hips = false },
		face = { hair = "long", beard = "short", stern = true }, legL = { V(-0.5, 0.3, 0.0), V(-0.6, 0.04, -0.8) }, legR = { V(0.55, 0.3, -0.15), V(0.65, 0.04, -0.9) } })
	place(c, "Block", "RobeChest", V(1.42, 1.3, 0.86), chest * CFrame.new(0, 0.04, 0.03), "marble")
	drape(c, "Robe", { center = V(0, 0, 0.04), rx = 0.66, rz = 0.5, top = 4.5, flare = 0.5, count = 24, from = -178, to = 178, zig = 10, depth = 0.15, hem = 0.1 })
	drape(c, "Mantle", { center = V(0, 0, 0.1), rx = 1.0, rz = 0.56, top = 6.8, flare = 0.3, count = 16, from = 70, to = 290, zig = 12, depth = 0.18, finish = "shade", hem = 3.3 })
	seg(c, "Sash", chest * V(-0.6, 0.55, -0.4), pelvis * V(0.5, 0.1, -0.44), 0.3, 0.12, "shade", { roll = 8 })
	for _, side in SIDES do
		blob(c, "Epaulette", j.shoulder[side] + V(side * 0.1, 0.2, 0), 0.86, "gold", { shadow = false })
	end
	ring(c, "Diadem", hc * V(0, 0.3, 0.02), hc:VectorToWorldSpace(UP) , 0.4, 14, 0.1, 0.07, "gold", { shadow = false })
	blob(c, "DiademStone", hc * V(0, 0.34, -0.42), 0.12, "glow", { shadow = false })
	-- the staff
	local sx, sz = 1.6, -0.7
	rod(c, "Staff", V(sx, 0.05, sz), V(sx, 9.4, sz), 0.2, "bronze")
	for _, y in { 2.0, 4.6, 8.6 } do
		disc(c, "StaffBand", V(sx, y, sz), UP, 0.34, 0.1, "gold", { shadow = false })
	end
	disc(c, "StaffFoot", V(sx, 0.08, sz), UP, 0.4, 0.1, "gold", { shadow = false })
	ring(c, "StaffRing", V(sx, 9.9, sz), FRONT, 0.55, 16, 0.12, 0.12, "gold")
	blob(c, "StaffStone", V(sx, 9.9, sz), 0.36, "glow", { shadow = false })
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		rod(c, "StaffProng", V(sx, 9.4, sz), V(sx + math.cos(a) * 0.4, 9.7, sz + math.sin(a) * 0.4), 0.08, "gold", { shadow = false })
	end
	local admR = arm(c, 1, j.shoulder[1], V(sx - 0.05, 5.0, sz), V(1, -0.3, 0.3), { hand = { dir = V(0, -1, 0), palm = V(-1, 0, 0), curl = 1, fingers = 1 } })
	local admL = arm(c, -1, j.shoulder[-1], V(-1.2, 5.6, -1.2), V(-1, -0.3, 0.2), { hand = { dir = V(-0.2, 0.7, -1), palm = V(0, 0, 1), curl = 0.05 } })
	sleeve(c, 1, admR, 1.1, 0.8)
	sleeve(c, -1, admL, 1.1, 0.8)
	return { aim = V(0, 6.6, 0) }
end

-- THE EIGHTH (Grandmaster): a wide horse stance in a martial robe with great sleeves and a
-- knotted sash; the right fist is pressed into the open left palm at the chest, in salute.
function carve.Grandmaster(c)
	local pelvis = CFrame.new(0, 3.7, 0.02)
	local chest = CFrame.new(0, 5.55, 0.04) * turn(0, 2, 0)
	local hc = CFrame.new(0, 7.22, 0.0) * turn(0, -4, 0)
	local j = figure(c, { pelvis = pelvis, chest = chest, head = hc, trunk = { bare = false, hips = false },
		face = { hair = "bald", beard = "long" }, legL = { V(-1.35, 0.3, -0.1), V(-1.7, 0.04, -0.7), { pole = V(-1, 0, -0.4) } }, legR = { V(1.35, 0.3, -0.1), V(1.7, 0.04, -0.7), { pole = V(1, 0, -0.4) } } })
	place(c, "Block", "RobeChest", V(1.44, 1.3, 0.88), chest * CFrame.new(0, 0.04, 0.03), "marble")
	for _, side in SIDES do
		seg(c, "Lapel", chest * V(side * 0.2, 0.66, -0.4), pelvis * V(-side * 0.3, 0.3, -0.44), 0.26, 0.12, "marble", { roll = side * 10 })
	end
	rod(c, "Sash", pelvis * V(-0.7, 0.34, 0), pelvis * V(0.7, 0.34, 0), 0.5, "shade", { shadow = false })
	place(c, "Block", "SashKnot", V(0.34, 0.34, 0.16), pelvis * CFrame.new(0, 0.34, -0.42), "shade", { shadow = false })
	for _, side in SIDES do
		seg(c, "SashTail", pelvis * V(side * 0.1, 0.2, -0.46), pelvis * V(side * 0.3, -1.1, -0.44), 0.24, 0.06, "shade", { shadow = false, roll = side * 6 })
	end
	drape(c, "Skirt", { center = V(0, 0, 0.04), rx = 0.8, rz = 0.5, top = 4.2, flare = 0.5, count = 30, from = -172, to = 172, zig = 10, depth = 0.15, hem = 1.1 })
	drape(c, "Train", { center = V(0, 0, 0.1), rx = 0.82, rz = 0.54, top = 6.6, flare = 0.4, count = 18, from = 90, to = 270, zig = 10, depth = 0.16, finish = "shade", hem = 1.0 })
	for k = 0, 3 do
		seg(c, "BeardFall", hc * V(0, -0.5 - k * 0.12, -0.26), hc * V(0, -0.9 - k * 0.2, -0.22 - k * 0.04), 0.32 - k * 0.05, 0.12, "marble", { shadow = false, roll = 45 })
	end
	-- salute: right fist into left palm
	local rw, lw = V(0.35, 5.8, -1.0), V(-0.15, 5.85, -1.0)
	local re = arm(c, 1, j.shoulder[1], rw, V(1, -0.5, 0.2), { hand = { dir = V(-1, 0, 0), palm = V(0, 0, 1), curl = 1, fingers = 1 } })
	local le = arm(c, -1, j.shoulder[-1], lw, V(-1, -0.5, 0.2), { hand = { dir = V(1, 0.2, 0), palm = V(0, 0, 1), curl = 0.05 } })
	sleeve(c, 1, re, 1.5, 1.1)
	sleeve(c, -1, le, 1.5, 1.1)
	return { aim = V(0, 6.0, 0) }
end

-- Pedestal, light and inscription --------------------------------------------------------------

-- Tiers from the floor up: { half width, top height, finish } in studs at the default height
local TIERS = {
	{ 6.8, 0.7, "basalt" }, -- footing
	{ 6.3, 1.5, "stone" }, -- second step
	{ 5.5, 7.2, "stone" }, -- the die
	{ 6.0, 8.2, "stone" }, -- cap, overhanging so nobody climbs it
	{ 5.4, 9.0, "marble" }, -- the figure's own slab, cut from the same block as the figure
}

-- The inscription is laid out like a museum plaque on a 415 x 130 px canvas (8.3 x 2.6 studs at 50
-- pixels a stud): the codename in small spaced capitals between two fine rules in the power's
-- colour, an optional small first word ("THE", "ANIMAL"), then the name, engraved (a dark copy
-- two pixels down and right), and a rivet in each corner. Every line is centred as one block.
local PLATE_PX = Vector2.new(415, 130)
-- First words set small above the name, so long names keep a readable size
local KICKERS = { THE = true, ANIMAL = true }
-- RobotoMono's advance is 0.6 of its size; used to place the rules beside the codename
local MONO_ADVANCE = 0.6

local function splitTitle(title: string): (string?, string)
	local upper = string.upper(title)
	local first, rest = string.match(upper, "^(%S+)%s+(.+)$")
	if first and KICKERS[first] then
		return first, rest
	end
	return nil, upper
end

-- "THE EIGHTH" -> "T H E   E I G H T H" (letters spaced, words further apart)
local function spaced(text: string): string
	local words = {}
	for word in string.gmatch(text, "%S+") do
		local letters = {}
		for _, code in utf8.codes(word) do
			table.insert(letters, utf8.char(code))
		end
		table.insert(words, table.concat(letters, " "))
	end
	return table.concat(words, "   ")
end

local function plate(c, base: CFrame, s: number, design)
	local y = 4.3 * s
	stone(c, "Block", "PlateBezel", V(8.8, 3.1, 0.16) * s, base * CFrame.new(0, y, -5.56 * s), "steel", { solid = true })
	local plateBlock = stone(c, "Block", "Plate", V(8.3, 2.6, 0.12) * s, base * CFrame.new(0, y, -5.64 * s), "graphite", { solid = true })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Inscription"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50 / s
	gui.LightInfluence = 0.6
	gui.Parent = plateBlock
	local W, H = PLATE_PX.X, PLATE_PX.Y
	local function box(item: GuiObject, x: number, top: number, w: number, h: number)
		item.Position = UDim2.fromScale(x / W, top / H)
		item.Size = UDim2.fromScale(w / W, h / H)
	end
	local function text(name: string, value: string, font: string, color: Color3, size: number?, maxSize: number?, z: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Text = value
		label.FontFace = Font.new(font)
		label.TextColor3 = color
		label.TextWrapped = false
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.ZIndex = z
		if size then
			label.TextSize = size
		else
			label.TextScaled = true
			local cap = Instance.new("UITextSizeConstraint")
			cap.MaxTextSize = maxSize or 40
			cap.Parent = label
		end
		label.Parent = gui
		return label
	end
	local function rule(name: string, x: number, top: number, w: number)
		local line = Instance.new("Frame")
		line.Name = name
		line.BorderSizePixel = 0
		line.BackgroundColor3 = design.color
		line.BackgroundTransparency = 0.15
		box(line, x, top, w, 2)
		line.Parent = gui
	end

	local kicker, name = splitTitle(design.title)
	local codename = spaced(design.codename)
	local CODE, KICK, NAME = 18, 16, 44
	local total = CODE + (if kicker then 7 + KICK + 3 else 9) + NAME
	local top = (H - total) / 2

	-- Codename between two rules
	local codeLabel = text("Codename", codename, FONT_MONO, design.color, 16, nil, 2)
	box(codeLabel, 0, top, W, CODE)
	local half = (utf8.len(codename) or #codename) * 16 * MONO_ADVANCE / 2
	local ruleLength = 40
	rule("RuleLeft", W / 2 - half - 12 - ruleLength, top + CODE / 2 - 1, ruleLength)
	rule("RuleRight", W / 2 + half + 12, top + CODE / 2 - 1, ruleLength)
	top += CODE

	if kicker then
		top += 7
		local kick = text("Kicker", kicker, FONT_DISPLAY, SUBTEXT_COLOR, 14, nil, 2)
		box(kick, 0, top, W, KICK)
		top += KICK + 3
	else
		top += 9
	end

	-- The name, engraved: a dark copy behind, two pixels down and to the right
	local shadow = text("TitleShadow", name, FONT_DISPLAY, Color3.fromRGB(6, 8, 12), nil, 40, 1)
	shadow.TextTransparency = 0.3
	box(shadow, 0.06 * W + 2, top + 2, 0.88 * W, NAME)
	local title = text("Title", name, FONT_DISPLAY, TEXT_COLOR, nil, 40, 2)
	box(title, 0.06 * W, top, 0.88 * W, NAME)

	-- A rivet in each corner
	for _, corner in { { 12, 12 }, { W - 20, 12 }, { 12, H - 20 }, { W - 20, H - 20 } } do
		local rivet = Instance.new("Frame")
		rivet.Name = "Rivet"
		rivet.BorderSizePixel = 0
		rivet.BackgroundColor3 = Color3.fromRGB(92, 98, 108)
		box(rivet, corner[1], corner[2], 8, 8)
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = rivet
		rivet.Parent = gui
	end
end

local function pedestal(c, base: CFrame, s: number, design)
	local bottom = 0
	for index, tier in TIERS do
		local half, top = tier[1] * s, tier[2] * s
		stone(c, "Block", if index == #TIERS then "Plinth" else "Pedestal", V(half * 2, top - bottom, half * 2), base * CFrame.new(0, (bottom + top) / 2, 0), tier[3], { solid = true })
		bottom = top
	end
	-- the brushed-steel band under the cap
	stone(c, "Block", "SteelBand", V(11.24, 0.9, 11.24) * s, base * CFrame.new(0, 6.75 * s, 0), "steel", { solid = true })
	-- the thin light ring in the power's colour, set into the foot of the die
	local glow = { solid = true, shadow = false, color = design.color }
	local half = 5.6 * s
	for _, side in SIDES do
		stone(c, "Block", "LightRing", V(11.4, 0.2, 0.2) * s, base * CFrame.new(0, 1.7 * s, side * half), "glow", glow)
		stone(c, "Block", "LightRing", V(0.2, 0.2, 11.0) * s, base * CFrame.new(side * half, 1.7 * s, 0), "glow", glow)
	end
	plate(c, base, s, design)
end

-- Light carriers are invisible parts that only hold a light or an emitter
local function carrier(c, name: string, cf: CFrame, size: Vector3?): BasePart
	local part = stone(c, "Block", name, size or V(0.4, 0.4, 0.4), cf, "steel", { shadow = false })
	part.Transparency = 1
	return part
end

-- One warm spotlight from above and in front, a cool rim light from behind, and the only effect:
-- a few slow, faint motes in the power's colour rising from the plinth.
local function lights(c, base: CFrame, s: number, design, aim: Vector3, shadows: boolean)
	local target = (base * CFrame.new(0, PEDESTAL_HEIGHT * s, 0)).Position + aim
	local keyAt = (base * CFrame.new(1.5 * s, (PEDESTAL_HEIGHT + 36) * s, -15 * s)).Position
	local key = carrier(c, "KeyLight", CFrame.lookAt(keyAt, target))
	local spot = Instance.new("SpotLight")
	spot.Name = "KeyLight"
	spot.Face = Enum.NormalId.Front
	spot.Color = KEY_COLOR
	local dim = design.dim or 1
	spot.Brightness = 2.6 * dim
	spot.Range = math.min(70 * s, 90)
	spot.Angle = 70
	spot.Shadows = shadows
	spot.Parent = key
	local rimAt = (base * CFrame.new(-7 * s, (PEDESTAL_HEIGHT + 30) * s, 9 * s)).Position
	local rim = carrier(c, "RimLight", CFrame.lookAt(rimAt, target))
	local cool = Instance.new("SpotLight")
	cool.Name = "RimLight"
	cool.Face = Enum.NormalId.Front
	cool.Color = RIM_COLOR
	cool.Brightness = 1.8 * dim
	cool.Range = math.min(48 * s, 70)
	cool.Angle = 80
	cool.Shadows = false
	cool.Parent = rim
	local mote = carrier(c, "Motes", base * CFrame.new(0, (PEDESTAL_HEIGHT + 0.1) * s, 0), V(9, 0.1, 9) * s)
	pcall(function()
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Motes"
		emitter.Color = ColorSequence.new(design.color)
		emitter.LightEmission = 0.8
		emitter.Rate = 3
		emitter.Lifetime = NumberRange.new(7, 11)
		emitter.Speed = NumberRange.new(0.5, 1)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0.08) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.55), NumberSequenceKeypoint.new(1, 1) })
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Acceleration = V(0, 0.05, 0)
		emitter.Drag = 0.4
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.Parent = mote
	end)
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
		part.CanCollide = false
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

-- Plate text and colours. `title` and `color` are only the fallback for when the power's
-- definition (src/shared/Powers) can't be read: the plate shows the definition's own name and
-- the ring takes its colour.
Statues.Designs = {
	StrongDude = { codename = "ATLAS", title = "Strong Dude", color = rgb(255, 140, 50), attribute = "gauntlets" },
	Ghost = { codename = "VEIL", title = "The Ghost", color = rgb(140, 230, 255), attribute = "katana" },
	Shapeshifter = { codename = "CHIMERA", title = "Animal Shapeshifter", color = rgb(222, 158, 74), attribute = "wolf pelt" },
	MachineMaster = { codename = "FURNACE", title = "Machine Master", color = rgb(70, 185, 255), attribute = "machine arm" },
	Corruption = { codename = "ECLIPSE", title = "Corruption", color = rgb(150, 112, 255), attribute = "cracked mask" },
	Syntax = { codename = "LATTICE", title = "Syntax", color = rgb(38, 226, 168), attribute = "transform-handle frame" },
	Admin = { codename = "WARDEN", title = "Admin Powers", color = rgb(236, 188, 86), attribute = "command staff" },
	Grandmaster = { codename = "THE EIGHTH", title = "The Grandmaster", color = rgb(86, 186, 148), attribute = "martial robe" },
}
local GENERIC = { codename = "UNNAMED", title = "Unknown", color = rgb(190, 190, 190), attribute = "none" }

-- A plain robed figure, so a pedestal is never bare: used only if a carving fails or the id is unknown
function carve.fallback(c)
	local pelvis = CFrame.new(0, 4.0, 0.02)
	local chest = CFrame.new(0, 5.85, 0.06)
	local j = trunk(c, pelvis, chest, { hips = false })
	local hc = CFrame.new(0, 7.5, 0.02)
	rod(c, "Neck", j.neck, hc * V(0, -0.36, 0.06), 0.46, "marble")
	head(c, hc, { hair = "crop" })
	for _, side in SIDES do
		arm(c, side, j.shoulder[side], V(side * 1.15, 4.2, -0.3), V(side, -0.2, 0.3))
	end
	drape(c, "Robe", { center = V(0, 0, 0.02), rx = 0.8, rz = 0.55, top = 4.6, flare = 0.4, count = 14, from = -175, to = 175, hem = 0.1 })
	return { aim = V(0, 6.2, 0) }
end

-- Reads a power's display name and colour from its definition, with the design's own as a fallback
local function describe(powerId: string, design)
	local title, color = design.title, design.color
	local ok, Powers = pcall(function()
		return require((ReplicatedStorage :: any).Shared.Powers)
	end)
	if ok and type(Powers) == "table" and type(Powers.get) == "function" then
		local found, def = pcall(Powers.get, powerId)
		if found and type(def) == "table" then
			if type(def.name) == "string" and def.name ~= "" then
				title = def.name
			end
			local colors = def.colors
			if type(colors) == "table" then
				-- a nearly white primary (the Ghost) would read as plain white light: use the accent
				local primary = colors.primary
				if typeof(primary) == "Color3" then
					local pale = math.min(primary.R, primary.G, primary.B) > 0.8
					color = if pale and typeof(colors.accent) == "Color3" then colors.accent else primary
				end
			end
		end
	end
	return { codename = design.codename, title = title, color = color, attribute = design.attribute }
end

-- Builds one statue (see the header)
function Statues.build(powerId: string, base: CFrame, opts: { height: number?, shadows: boolean?, heroShadows: { string }? }?): Model
	if typeof(base) ~= "CFrame" then
		base = CFrame.new()
	end
	local base0 = Statues.Designs[powerId]
	local design = describe(powerId, base0 or GENERIC)
	-- A fighter held for a later update keeps its plinth but stands veiled (Powers.Unreleased)
	local veiled = false
	do
		local ok, Powers = pcall(function()
			return require((ReplicatedStorage :: any).Shared.Powers)
		end)
		if ok and type(Powers) == "table" and type(Powers.Unreleased) == "table" and Powers.Unreleased[powerId] then
			veiled = true
			design.codename = "CLASSIFIED"
			design.title = "TO BE REVEALED"
			design.attribute = "veiled"
			design.dim = 0.55
		end
	end
	if not base0 then
		design.codename = string.upper(tostring(powerId))
		design.title = tostring(powerId)
		warn("[Statues] no design for " .. tostring(powerId) .. ": building the plain fallback figure")
	end
	local height = math.clamp(opts and tonumber(opts.height) or FIGURE_HEIGHT, 4, 150)
	local s = height / FIGURE_HEIGHT
	local model = Instance.new("Model")
	model.Name = "Statue_" .. tostring(powerId)
	model:SetAttribute("PowerId", tostring(powerId))
	model:SetAttribute("Codename", design.codename)
	if veiled then
		model:SetAttribute("Veiled", true)
	end
	local seed = (table.find(Statues.Order, powerId) or 9) * 7919 + 17
	local c = { color = design.color, parent = model, random = Random.new(seed), count = 0, bad = 0, h = height / 8, origin = base }
	stretched = 0

	local function guarded(stage: string, fn: () -> ()): boolean
		local ok, err = pcall(fn)
		if not ok then
			warn(`[Statues] {powerId} {stage} failed: {err}`)
		end
		return ok
	end

	local plinth = Instance.new("Model")
	plinth.Name = "Pedestal"
	plinth.Parent = model
	guarded("plinth", function()
		c.parent = plinth
		pedestal(c, base, s, design)
	end)

	local ground = base * CFrame.new(0, PEDESTAL_HEIGHT * s, 0)
	local aim = V(0, 6.5, 0)
	local figure = Instance.new("Model")
	figure.Name = "Figure"
	figure.Parent = model
	local source = if veiled then nil else sculpted(powerId)
	local seated = false
	if source then
		seated = guarded("sculpted figure", function()
			local clone = seat(source, ground, height)
			for _, item in clone:GetChildren() do
				item.Parent = figure
			end
			clone:Destroy()
			if #figure:GetChildren() == 0 then
				error("the imported figure has no parts")
			end
		end)
		if seated then
			model:SetAttribute("Sculpted", true)
		else
			figure:ClearAllChildren()
		end
	end
	if not seated then
		c.parent = figure
		c.origin = ground
		local maker = if veiled then carve.Veiled else carve[powerId]
		local result = nil
		local ok = maker ~= nil
			and guarded("figure", function()
				result = maker(c)
			end)
		if not ok then
			-- start the figure over with the plain robed one
			figure:ClearAllChildren()
			c.count = 0
			c.bad = 0
			c.origin = ground
			c.random = Random.new(seed)
			guarded("fallback figure", function()
				result = carve.fallback(c)
			end)
			model:SetAttribute("Fallback", true)
		end
		aim = result and result.aim or aim
	end
	-- last resort: a figure that is somehow still empty becomes a simple robed column, never nothing
	if #figure:GetDescendants() == 0 then
		pcall(function()
			c.parent = figure
			c.origin = ground
			local h = c.h
			stone(c, "Cylinder", "Robe", V(5.2 * h, 2.2 * h, 2.2 * h), ground * CFrame.new(0, 2.6 * h, 0) * CFrame.Angles(0, 0, math.rad(90)), "marble")
			stone(c, "Ball", "Cranium", V(0.8 * h, 0.8 * h, 0.8 * h), ground * CFrame.new(0, 7.4 * h, 0), "marble")
		end)
		model:SetAttribute("Fallback", true)
	end
	local headPart = figure:FindFirstChild("Cranium", true)
	if headPart and headPart:IsA("BasePart") then
		model:SetAttribute("HeadAt", headPart.Position)
	end

	local lightModel = Instance.new("Model")
	lightModel.Name = "Lights"
	lightModel.Parent = model
	c.parent = lightModel
	c.origin = ground
	local shadows = not (opts ~= nil and opts.shadows == false)
	if opts ~= nil and opts.heroShadows ~= nil then
		shadows = table.find(opts.heroShadows, powerId) ~= nil
	end
	guarded("lights", function()
		lights(c, base, s, design, aim * c.h, shadows)
	end)

	local parts = 0
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			parts += 1
		end
	end
	model:SetAttribute("Parts", parts)
	model:SetAttribute("Stretched", stretched)
	model:SetAttribute("BadParts", c.bad)
	if parts > PART_BUDGET then
		warn(`[Statues] {powerId} uses {parts} parts (budget {PART_BUDGET})`)
	end
	pcall(function()
		model.WorldPivot = base
	end)
	return model
end

return Statues
