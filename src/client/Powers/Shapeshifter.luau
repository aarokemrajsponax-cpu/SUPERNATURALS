-- How the Animal Shapeshifter looks. Each form is a real animal body built from
-- parts (body, head, snout or beak, ears, legs, tail, wings) on a small skeleton
-- of joints welded to the character's root, with the human body hidden while
-- it's worn. The skeleton breathes, looks around, trots, gallops, glides and
-- strikes on its own every frame. Degrees change the look: a spectral wolf, a
-- storm eagle crackling with lightning, a mythic bear with burning runes, the
-- phoenix's fire. Transformations are a short burst of fur or feathers while
-- the new body grows in. The power's own colours are primal amber and bark.
--
-- Transparency belongs to other systems too (the Ghost's Concealed veil, the
-- owner's invisibility): the human body's own values are saved under this
-- power's attribute, server changes made while hidden are kept, and the animal
-- fades whenever the body would.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Shape = {}
local fx = {}
Shape.fx = fx

local rgb = Color3.fromRGB
local AMBER = rgb(222, 158, 74)
local BARK = rgb(86, 64, 44)
local BONE = rgb(240, 222, 178)
local DUST = rgb(150, 136, 116)
local STORM = rgb(160, 205, 255)
local FLAME = rgb(255, 150, 50)
local EMBER = rgb(255, 96, 36)

local POWER = "Shapeshifter"
local SAVED = "SNShapeSaved"
-- Set by the owner panel's invisibility on every part it hides (server side)
local OWNER_HIDDEN = "SNVisibleTransparency"
local ANIMAL_NAME = "SNShapeAnimal"
local LOOK_NAME = "SNShapeLook"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local function now(): number
	return workspace:GetServerTimeNow()
end

local function num(value: any, default: number): number
	return if typeof(value) == "number" and value == value and math.abs(value) < 1e6 then value else default
end

local function vec(value: any): Vector3?
	if typeof(value) == "Vector3" and value.Magnitude == value.Magnitude and value.Magnitude < 1e6 then
		return value
	end
	return nil
end

local function flat(value: any): Vector3?
	local v = vec(value)
	if not v then
		return nil
	end
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else nil
end

local function ang(p: number?, y: number?, r: number?): CFrame
	return CFrame.Angles(math.rad(p or 0), math.rad(y or 0), math.rad(r or 0))
end

local function at(x: number, y: number, z: number, p: number?, yw: number?, r: number?): CFrame
	return CFrame.new(x, y, z) * ang(p, yw, r)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Smooth approach that doesn't depend on frame rate
local function approach(current: number, target: number, rate: number, dt: number): number
	return target + (current - target) * math.exp(-rate * dt)
end

-- A strike's shape over its length: quick in, slower out
local function strikeCurve(u: number): number
	if u <= 0 or u >= 1 then
		return 0
	end
	if u < 0.3 then
		local k = u / 0.3
		return k * k * (3 - 2 * k)
	end
	local k = (u - 0.3) / 0.7
	return (1 - k) * (1 - k)
end

-- Holds for most of the length, eases at both ends
local function holdCurve(u: number): number
	if u <= 0 or u >= 1 then
		return 0
	end
	return math.min(1, u / 0.18, (1 - u) / 0.22)
end

local function scaleCFrame(frame: CFrame, scale: number): CFrame
	return frame - frame.Position + frame.Position * scale
end

-- Palettes ----------------------------------------------------------------------------------
-- Two or three tones per animal (base, dark, light) plus small details. A seeded
-- jitter per piece keeps fur from looking like flat paint, the same on every screen.

local FUR = Enum.Material.Fabric
local SMOOTH = Enum.Material.SmoothPlastic

local PALETTES: { [string]: { [string]: any } } = {
	Wolf = { base = rgb(112, 104, 94), dark = rgb(64, 58, 52), light = rgb(198, 188, 170), eye = rgb(214, 160, 62), nose = rgb(30, 27, 26), claw = rgb(58, 52, 46), material = FUR },
	SpectralWolf = {
		base = rgb(128, 166, 212), dark = rgb(74, 100, 156), light = rgb(204, 224, 246), eye = rgb(206, 240, 255), nose = rgb(60, 80, 130), claw = rgb(170, 200, 236),
		material = SMOOTH, see = 0.2, glowEyes = true,
	},
	Hawk = { base = rgb(128, 86, 52), dark = rgb(70, 46, 30), light = rgb(226, 208, 176), beak = rgb(96, 90, 84), cere = rgb(228, 186, 72), eye = rgb(32, 24, 20), feet = rgb(222, 184, 80), claw = rgb(36, 32, 30), material = FUR },
	Eagle = { base = rgb(84, 58, 38), dark = rgb(52, 36, 24), light = rgb(236, 232, 222), beak = rgb(232, 180, 58), cere = rgb(232, 190, 70), eye = rgb(40, 30, 18), feet = rgb(232, 186, 66), claw = rgb(34, 30, 28), material = FUR, whiteHead = true },
	StormEagle = { base = rgb(62, 70, 88), dark = rgb(36, 40, 52), light = rgb(198, 208, 224), beak = rgb(172, 178, 190), cere = rgb(150, 160, 178), eye = rgb(170, 214, 255), feet = rgb(150, 156, 168), claw = rgb(30, 32, 38), glow = STORM, material = FUR, whiteHead = true, glowEyes = true },
	Phoenix = { base = rgb(206, 78, 32), dark = rgb(136, 36, 22), light = rgb(255, 184, 84), beak = rgb(255, 214, 150), cere = rgb(255, 200, 110), eye = rgb(255, 236, 170), feet = rgb(150, 50, 26), claw = rgb(60, 24, 18), glow = FLAME, material = SMOOTH, glowEyes = true },
	Bear = { base = rgb(96, 68, 44), dark = rgb(58, 40, 26), light = rgb(150, 116, 84), eye = rgb(24, 18, 14), nose = rgb(26, 22, 20), claw = rgb(206, 196, 176), material = FUR },
	DireBear = { base = rgb(82, 66, 52), dark = rgb(44, 34, 27), light = rgb(170, 154, 134), eye = rgb(30, 20, 14), nose = rgb(24, 20, 18), claw = rgb(222, 212, 192), material = FUR, grizzled = true },
	MythicBear = { base = rgb(58, 46, 38), dark = rgb(32, 26, 22), light = rgb(116, 94, 74), eye = rgb(255, 190, 100), nose = rgb(22, 18, 16), claw = rgb(230, 214, 180), glow = AMBER, material = FUR, glowEyes = true, grizzled = true },
	Cheetah = { base = rgb(206, 162, 94), dark = rgb(42, 34, 28), light = rgb(238, 224, 194), eye = rgb(214, 166, 60), nose = rgb(44, 32, 28), claw = rgb(70, 60, 50), material = FUR, spots = true },
	Panther = { base = rgb(36, 35, 40), dark = rgb(22, 22, 25), light = rgb(64, 62, 68), eye = rgb(196, 206, 74), nose = rgb(20, 20, 22), claw = rgb(60, 58, 60), material = FUR, rosettes = true },
	Crocodile = { base = rgb(80, 90, 54), dark = rgb(48, 56, 34), light = rgb(180, 168, 116), eye = rgb(206, 190, 76), teeth = rgb(228, 222, 200), nose = rgb(40, 46, 30), claw = rgb(44, 48, 34), material = Enum.Material.Slate },
}

-- Body plan, size and how it moves
local ANIMALS: { [string]: { [string]: any } } = {
	Wolf = { family = "Quad", scale = 1, stride = 4.2, gallopAt = 1.25, offsets = { 0, math.pi, math.pi + 0.15, 0.15 } },
	SpectralWolf = { family = "Quad", scale = 1.05, stride = 4.4, gallopAt = 1.25, offsets = { 0, math.pi, math.pi + 0.15, 0.15 } },
	Hawk = { family = "Bird", scale = 1 },
	Eagle = { family = "Bird", scale = 1.15 },
	StormEagle = { family = "Bird", scale = 1.2 },
	Phoenix = { family = "Bird", scale = 1.2 },
	Bear = { family = "Quad", scale = 1, stride = 4.6, heavy = true, offsets = { 0, math.pi, math.pi * 0.5, math.pi * 1.5 } },
	DireBear = { family = "Quad", scale = 1.12, stride = 4.8, heavy = true, offsets = { 0, math.pi, math.pi * 0.5, math.pi * 1.5 } },
	MythicBear = { family = "Quad", scale = 1.22, stride = 5, heavy = true, offsets = { 0, math.pi, math.pi * 0.5, math.pi * 1.5 } },
	Cheetah = { family = "Quad", scale = 1, stride = 5, gallopAt = 1.05, cat = true, offsets = { 0, math.pi, math.pi + 0.15, 0.15 } },
	Panther = { family = "Quad", scale = 1.12, stride = 5, gallopAt = 1.15, cat = true, offsets = { 0, math.pi, math.pi + 0.15, 0.15 } },
	Crocodile = { family = "Croc", scale = 1, stride = 3 },
}
Shape.Animals = ANIMALS

-- The skeleton ---------------------------------------------------------------------------------
-- Bones are small invisible parts; pieces weld to bones; bones weld to their parent
-- bone (the first to the character's root). Posing a bone is a change to its weld's
-- C0, which Roblox applies to everything hanging from it. Free-standing spirits
-- (and previews) are anchored instead and placed bone by bone.

local Rig = {}
Rig.__index = Rig

local function newPart(shape: string, size: Vector3): BasePart
	local part: BasePart
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	elseif shape == "Corner" then
		part = Instance.new("CornerWedgePart")
	else
		local plain = Instance.new("Part")
		if shape == "Ball" then
			plain.Shape = Enum.PartType.Ball
		elseif shape == "Cylinder" then
			plain.Shape = Enum.PartType.Cylinder
		end
		part = plain
	end
	part.Size = size
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- opts: { mode = "Weld" | "Anchored", root = BasePart?, ground = number?, frame = CFrame?,
--         parent = Instance, ghost = Color3?, ghostSee = number?, scale = number? }
function Rig.new(animalId: string, opts: { [string]: any })
	local spec = ANIMALS[animalId] or ANIMALS.Wolf
	local self = setmetatable({}, Rig)
	self.id = animalId
	self.spec = spec
	self.palette = PALETTES[animalId] or PALETTES.Wolf
	self.mode = opts.mode or "Anchored"
	self.root = opts.root
	self.ground = opts.ground or 3
	self.frame = opts.frame or CFrame.new()
	self.size = (opts.scale or 1) * spec.scale
	self.grow = 1
	self.fade = 0
	self.ghost = opts.ghost
	self.ghostSee = opts.ghostSee or 0.45
	self.bones = {}
	self.order = {}
	self.pieces = {}
	self.glows = {}
	self.random = Random.new(#animalId * 7919)
	self.anim = { t = 0, phase = 0, gait = 0, air = 0, vy = 0, lookYaw = 0, lookPitch = 0, lookAt = 0, nextLook = 0, flap = 0, fold = 1, twitch = 0 }
	local model = Instance.new("Model")
	model.Name = ANIMAL_NAME
	self.model = model
	self.alive = true
	return self
end

function Rig:bone(name: string, parentName: string?, rest: CFrame)
	local part = newPart("Block", Vector3.one * 0.2)
	part.Name = "Bone" .. name
	part.Transparency = 1
	part.CastShadow = false
	local bone = { name = name, parent = parentName, rest = rest, pose = CFrame.identity, part = part, weld = nil :: Weld?, world = CFrame.identity }
	self.bones[name] = bone
	table.insert(self.order, bone)
	return bone
end

-- tone: a palette key ("base", "dark", "light", ...) or a Color3
function Rig:piece(boneName: string, shape: string, size: Vector3, offset: CFrame, tone: any, opts: { [string]: any }?)
	local options = opts or {}
	local palette = self.palette
	local color: Color3 = if typeof(tone) == "Color3" then tone else (palette[tone] or palette.base)
	-- Seeded jitter: never two pieces of fur exactly the same colour
	if not options.exact then
		local h, s, v = color:ToHSV()
		local r = self.random
		color = Color3.fromHSV((h + (r:NextNumber() - 0.5) * 0.012) % 1, math.clamp(s * (1 + (r:NextNumber() - 0.5) * 0.08), 0, 1), math.clamp(v * (1 + (r:NextNumber() - 0.5) * 0.09), 0, 1))
	end
	local part = newPart(shape, size)
	part.Name = options.name or "Piece"
	local glowing = options.glow == true
	local see = options.see or 0
	if self.ghost then
		part.Color = if glowing then Color3.new(1, 1, 1):Lerp(self.ghost, 0.5) else self.ghost:Lerp(color, 0.25)
		part.Material = if glowing then Enum.Material.Neon else Enum.Material.Glass
		see = math.max(see, if glowing then 0.1 else self.ghostSee)
		part.CastShadow = false
	else
		part.Color = color
		part.Material = if glowing then Enum.Material.Neon else (options.material or palette.material or FUR)
		see = math.max(see, if glowing then 0 else (palette.see or 0))
		if size.Magnitude < 0.6 then
			part.CastShadow = false
		end
	end
	part.Transparency = see
	local entry = { part = part, bone = boneName, offset = offset, size = size, see = see, glow = glowing }
	table.insert(self.pieces, entry)
	if glowing then
		table.insert(self.glows, entry)
	end
	return entry
end

-- Mirror helper: the same piece on both sides (x and the side-dependent angles flip)
function Rig:pair(boneName: string, shape: string, size: Vector3, x: number, y: number, z: number, p: number?, yw: number?, r: number?, tone: any, opts: { [string]: any }?)
	self:piece(boneName, shape, size, at(-x, y, z, p, yw, r), tone, opts)
	self:piece(boneName, shape, size, at(x, y, z, p, -(yw or 0), -(r or 0)), tone, opts)
end

local function boneLocal(self, bone): CFrame
	local scale = self.size * self.grow
	local rest = scaleCFrame(bone.rest, scale)
	local pose = scaleCFrame(bone.pose, scale)
	if not bone.parent then
		return CFrame.new(0, -self.ground, 0) * rest * pose
	end
	return rest * pose
end

-- Puts every part in place (first time) and makes the welds
function Rig:assemble(parent: Instance)
	local model = self.model
	local anchored = self.mode ~= "Weld"
	local scale = self.size * self.grow
	for _, bone in self.order do
		local parentFrame = if bone.parent then self.bones[bone.parent].world else (if anchored then self.frame else (self.root :: BasePart).CFrame)
		bone.world = parentFrame * boneLocal(self, bone)
		bone.part.CFrame = bone.world
		bone.part.Anchored = anchored
		bone.part.Parent = model
	end
	for _, entry in self.pieces do
		local bone = self.bones[entry.bone]
		entry.part.Size = entry.size * scale
		entry.part.CFrame = bone.world * scaleCFrame(entry.offset, scale)
		entry.part.Anchored = anchored
		entry.part.Parent = model
	end
	if not anchored then
		for _, bone in self.order do
			local weld = Instance.new("Weld")
			weld.Name = "Joint"
			weld.Part0 = if bone.parent then self.bones[bone.parent].part else self.root
			weld.Part1 = bone.part
			weld.C0 = boneLocal(self, bone)
			weld.Parent = bone.part
			bone.weld = weld
		end
		for _, entry in self.pieces do
			local weld = Instance.new("Weld")
			weld.Name = "Joint"
			weld.Part0 = self.bones[entry.bone].part
			weld.Part1 = entry.part
			weld.C0 = scaleCFrame(entry.offset, scale)
			weld.Parent = entry.part
			entry.weld = weld
		end
	end
	model.Parent = parent
end

-- Moving many anchored parts at once (nil until we know the engine has it)
local canBulkMove: boolean? = nil

-- Pushes the current poses (and size, while growing) to the parts
function Rig:apply(resized: boolean?)
	local scale = self.size * self.grow
	if self.mode == "Weld" then
		for _, bone in self.order do
			if bone.weld then
				bone.weld.C0 = boneLocal(self, bone)
			end
		end
		if resized then
			for _, entry in self.pieces do
				entry.part.Size = entry.size * scale
				if entry.weld then
					entry.weld.C0 = scaleCFrame(entry.offset, scale)
				end
			end
		end
		return
	end
	for _, bone in self.order do
		local parentFrame = if bone.parent then self.bones[bone.parent].world else self.frame
		bone.world = parentFrame * boneLocal(self, bone)
	end
	local parts, frames = {}, {}
	for _, entry in self.pieces do
		local bone = self.bones[entry.bone]
		if resized then
			entry.part.Size = entry.size * scale
		end
		table.insert(parts, entry.part)
		table.insert(frames, bone.world * scaleCFrame(entry.offset, scale))
	end
	if canBulkMove ~= false then
		local ok = pcall(function()
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		canBulkMove = ok
		if ok then
			return
		end
	end
	for index, part in parts do
		part.CFrame = frames[index]
	end
end

-- Fades the whole body (Concealed veil, owner invisibility, spirits dissolving)
function Rig:setFade(amount: number)
	if math.abs(amount - self.fade) < 1e-3 then
		return
	end
	self.fade = amount
	for _, entry in self.pieces do
		entry.part.Transparency = math.max(entry.see, amount)
	end
end

function Rig:act(name: string, length: number, data: { [string]: any }?)
	self.action = { name = name, start = os.clock(), length = math.max(0.05, length), data = data or {} }
end

function Rig:destroy()
	self.alive = false
	self.model:Destroy()
end

-- Body builders --------------------------------------------------------------------------------

-- Fur tufts: thin wedges that break up a smooth outline
local function tuft(rig, boneName: string, x: number, y: number, z: number, p: number, yw: number, r: number, length: number, tone: any)
	rig:piece(boneName, "Wedge", Vector3.new(0.12, length * 0.5, length), at(x, y, z, p, yw, r), tone)
end

-- A triangular ear seen from the front: two wedges back to back
local function ear(rig, boneName: string, x: number, y: number, z: number, height: number, width: number, tilt: number, tone: any, inner: any)
	local side = if x < 0 then -1 else 1
	local frame = at(x, y, z, -8, 0, -tilt * side)
	rig:piece(boneName, "Wedge", Vector3.new(0.14, height, width / 2), frame * at(0, 0, 0, 0, 90, 0) * CFrame.new(0, 0, width / 4), tone)
	rig:piece(boneName, "Wedge", Vector3.new(0.14, height, width / 2), frame * at(0, 0, 0, 0, -90, 0) * CFrame.new(0, 0, width / 4), tone)
	if inner then
		rig:piece(boneName, "Wedge", Vector3.new(0.06, height * 0.7, width * 0.3), frame * CFrame.new(0, -height * 0.1, -0.06) * at(0, 0, 0, 0, 90, 0) * CFrame.new(0, 0, width * 0.15), inner)
		rig:piece(boneName, "Wedge", Vector3.new(0.06, height * 0.7, width * 0.3), frame * CFrame.new(0, -height * 0.1, -0.06) * at(0, 0, 0, 0, -90, 0) * CFrame.new(0, 0, width * 0.15), inner)
	end
end

local function cylinderY(length: number, diameter: number): Vector3
	return Vector3.new(length, diameter, diameter)
end

-- A leg: shoulder or thigh, upper bone, lower bone, paw with toes and claws
local function leg(rig, name: string, parentName: string, position: Vector3, d: { [string]: any })
	rig:bone(name, parentName, CFrame.new(position))
	local tone, low = d.tone or "base", d.low or d.tone or "base"
	if d.top then
		rig:piece(name, "Ball", Vector3.one * d.top, at(0, d.topY or 0, d.topZ or 0), tone)
	end
	rig:piece(name, "Cylinder", cylinderY(d.upper, d.upperD), at(0, -d.upper / 2, d.upperZ or 0, d.upperPitch or 0, 0, 90), tone)
	rig:bone(name .. "2", name, CFrame.new(0, -d.knee, d.kneeZ or 0))
	rig:piece(name .. "2", "Ball", Vector3.one * d.lowerD * 1.12, CFrame.new(), low)
	rig:piece(name .. "2", "Cylinder", cylinderY(d.lower, d.lowerD), at(0, -d.lower / 2, d.lowerZ or 0, d.lowerPitch or 0, 0, 90), low)
	local paw = d.paw
	local pawY = -d.ankle
	rig:piece(name .. "2", "Block", paw, at(0, pawY, -paw.Z * 0.2), d.pawTone or low)
	-- Toes round off the front of the paw
	local toes = d.toes or 3
	for index = 1, toes do
		local x = (index - (toes + 1) / 2) * paw.X / toes * 0.95
		rig:piece(name .. "2", "Ball", Vector3.one * math.min(paw.Y * 1.05, paw.X / toes * 1.25), at(x, pawY - paw.Y * 0.05, -paw.Z * 0.62), d.pawTone or low)
		if d.claws then
			rig:piece(name .. "2", "Wedge", Vector3.new(0.07, paw.Y * 0.55, d.claws), at(x, pawY - paw.Y * 0.18, -paw.Z * 0.75 - d.claws * 0.4, 0, 180, 0), "claw", { material = SMOOTH })
		end
	end
	if d.tuft then
		tuft(rig, name, 0, -d.upper * 0.75, d.upperD * 0.45, -160, 0, 0, d.tuft, d.tuftTone or tone)
	end
end

-- A tail of chained bones; `pitch` bends each joint (positive = down)
local function tail(rig, parentName: string, position: Vector3, segments: { { [string]: any } })
	local parent = parentName
	local offset = CFrame.new(position)
	for index, segment in segments do
		local name = "Tail" .. index
		rig:bone(name, parent, offset * ang(segment.pitch or 0, 0, 0))
		local length = segment.length
		local steps = segment.balls or 2
		for step = 1, steps do
			local k = (step - 0.5) / steps
			local diameter = lerp(segment.from, segment.to, k)
			rig:piece(name, "Ball", Vector3.one * diameter, CFrame.new(0, 0, length * k), segment.tone or "base")
		end
		if segment.ring then
			rig:piece(name, "Cylinder", Vector3.new(0.12, segment.to * 1.04, segment.to * 1.04), at(0, 0, length * 0.8, 0, 90, 0), segment.ring)
		end
		parent = name
		offset = CFrame.new(0, 0, length)
	end
end

-- Spots on a sphere's upper half (cheetah spots, panther rosettes)
local function spots(rig, boneName: string, center: Vector3, radius: number, count: number, tone: any, size: number)
	local random = rig.random
	for _ = 1, count do
		local direction = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-0.25, 1), random:NextNumber(-1, 1))
		if direction.Magnitude > 0.05 then
			direction = direction.Unit
			local diameter = size * random:NextNumber(0.75, 1.2)
			rig:piece(boneName, "Ball", Vector3.one * diameter, CFrame.new(center + direction * (radius - diameter * 0.32)), tone, { exact = true })
		end
	end
end

-- A glowing rune laid flat on a sphere's surface: a few short strokes
local RUNES = {
	{ { 0, 0, 0.5, 0 }, { 0.12, 0.14, 0.32, 40 }, { 0.12, -0.08, 0.3, -40 } },
	{ { -0.1, 0, 0.5, 0 }, { 0.1, 0, 0.5, 0 }, { 0, 0.05, 0.3, 90 } },
	{ { 0, 0, 0.55, 0 }, { 0, 0.1, 0.34, 55 }, { 0, -0.1, 0.34, -55 } },
}
local function rune(rig, boneName: string, center: Vector3, radius: number, direction: Vector3, glyph: number, size: number)
	local normal = direction.Unit
	local point = center + normal * radius
	local up = if math.abs(normal.Y) > 0.9 then Vector3.zAxis else Vector3.yAxis
	local frame = CFrame.lookAt(point, point + normal, up)
	for _, stroke in RUNES[(glyph - 1) % #RUNES + 1] do
		rig:piece(boneName, "Block", Vector3.new(0.07, stroke[3], 0.05) * size, frame * at(stroke[1] * size, stroke[2] * size, 0, 0, 0, stroke[4]), "glow", { glow = true, name = "Rune" })
	end
end

local function buildWolf(rig)
	local spectral = rig.id == "SpectralWolf"
	rig:bone("Body", nil, CFrame.new(0, 2.2, 0))
	rig:piece("Body", "Ball", Vector3.one * 1.95, CFrame.new(0, 0.12, -0.85), "base")
	rig:piece("Body", "Ball", Vector3.one * 1.7, CFrame.new(0, 0.04, 0.15), "base")
	rig:piece("Body", "Ball", Vector3.one * 1.55, CFrame.new(0, 0.14, 1.05), "base")
	-- The darker saddle along the back
	rig:piece("Body", "Ball", Vector3.one * 1.5, CFrame.new(0, 0.32, -0.5), "dark")
	rig:piece("Body", "Ball", Vector3.one * 1.32, CFrame.new(0, 0.33, 0.45), "dark")
	rig:piece("Body", "Ball", Vector3.one * 1.7, CFrame.new(0, -0.02, -0.4), "base")
	-- Pale chest ruff and belly
	rig:piece("Body", "Ball", Vector3.one * 1.35, CFrame.new(0, -0.3, -1.25), "light")
	rig:piece("Body", "Ball", Vector3.one * 1.15, CFrame.new(0, -0.42, -0.25), "light")
	rig:piece("Body", "Ball", Vector3.one * 1.3, CFrame.new(0, 0.6, -1.4), "base")
	for index, x in { -0.32, 0, 0.32 } do
		tuft(rig, "Body", x, -0.95, -1.35 + math.abs(x) * 0.3, -150 + index * 3, x * 20, 0, 0.7, "light")
	end
	for _, side in { -1, 1 } do
		tuft(rig, "Body", 0.62 * side, 0.65, -1.3, 20, 25 * side, -35 * side, 0.6, "base")
		tuft(rig, "Body", 0.5 * side, 0.95, -1.05, 30, 15 * side, -25 * side, 0.55, "dark")
	end
	tuft(rig, "Body", 0, 1.12, -0.95, 25, 0, 0, 0.6, "dark")

	rig:bone("Head", "Body", at(0, 0.95, -1.9, -6))
	rig:piece("Head", "Ball", Vector3.one * 1.12, CFrame.new(), "base")
	rig:pair("Head", "Ball", Vector3.one * 0.62, 0.34, -0.2, -0.18, 0, 0, 0, "light")
	rig:piece("Head", "Block", Vector3.new(0.52, 0.32, 0.8), at(0, 0.0, -0.75, -4), "base")
	rig:piece("Head", "Block", Vector3.new(0.48, 0.22, 0.72), CFrame.new(0, -0.2, -0.72), "light")
	rig:piece("Head", "Block", Vector3.new(0.3, 0.2, 0.2), CFrame.new(0, 0.03, -1.15), "nose", { material = SMOOTH })
	rig:piece("Head", "Block", Vector3.new(0.78, 0.14, 0.26), at(0, 0.3, -0.36, -12), "dark")
	rig:pair("Head", "Ball", Vector3.one * 0.17, 0.26, 0.14, -0.43, 0, 0, 0, "eye", { material = SMOOTH, glow = rig.palette.glowEyes })
	ear(rig, "Head", -0.32, 0.62, 0.06, 0.55, 0.42, 14, "base", "dark")
	ear(rig, "Head", 0.32, 0.62, 0.06, 0.55, 0.42, 14, "base", "dark")
	rig:pair("Head", "Wedge", Vector3.new(0.1, 0.3, 0.42), 0.5, -0.12, 0.12, 0, 0, -20, "light")
	rig:bone("Jaw", "Head", CFrame.new(0, -0.3, -0.36))
	rig:piece("Jaw", "Block", Vector3.new(0.42, 0.16, 0.66), CFrame.new(0, -0.02, -0.36), "light")
	rig:piece("Jaw", "Block", Vector3.new(0.3, 0.06, 0.5), CFrame.new(0, 0.07, -0.4), rgb(150, 70, 66), { material = SMOOTH })

	local front = { top = 0.78, topY = 0.05, upper = 1.05, upperD = 0.46, knee = 1.0, lower = 0.85, lowerD = 0.32, ankle = 0.86, paw = Vector3.new(0.4, 0.2, 0.5), toes = 3, tuft = 0.5, low = "base", pawTone = "dark" }
	leg(rig, "LegFL", "Body", Vector3.new(-0.5, -0.25, -0.95), front)
	leg(rig, "LegFR", "Body", Vector3.new(0.5, -0.25, -0.95), front)
	local back = { top = 1.0, topY = -0.18, upper = 1.3, upperD = 0.52, upperZ = 0.12, upperPitch = -14, knee = 1.3, kneeZ = 0.3, lower = 0.8, lowerD = 0.3, lowerPitch = 12, ankle = 0.76, paw = Vector3.new(0.38, 0.2, 0.48), toes = 3, low = "base", pawTone = "dark" }
	leg(rig, "LegBL", "Body", Vector3.new(-0.5, -0.05, 1.1), back)
	leg(rig, "LegBR", "Body", Vector3.new(0.5, -0.05, 1.1), back)
	tail(rig, "Body", Vector3.new(0, 0.45, 1.7), {
		{ pitch = 32, length = 0.9, from = 0.5, to = 0.62 },
		{ pitch = 14, length = 0.9, from = 0.64, to = 0.56 },
		{ pitch = 6, length = 0.55, from = 0.48, to = 0.34, tone = if spectral then "light" else "dark" },
	})
end

local function buildBear(rig)
	local mythic = rig.id == "MythicBear"
	local grizzled = rig.palette.grizzled
	rig:bone("Body", nil, CFrame.new(0, 2.75, 0))
	rig:piece("Body", "Ball", Vector3.one * 2.9, CFrame.new(0, 0.25, -0.85), "base")
	rig:piece("Body", "Ball", Vector3.one * 2.7, CFrame.new(0, -0.1, 0.25), "base")
	rig:piece("Body", "Ball", Vector3.one * 2.55, CFrame.new(0, 0.05, 1.3), "base")
	rig:piece("Body", "Ball", Vector3.one * 2.0, CFrame.new(0, -0.45, -1.35), "base")
	-- The shoulder hump: the bear's silhouette
	rig:piece("Body", "Ball", Vector3.one * 2.1, CFrame.new(0, 0.78, -0.9), if grizzled then "light" else "base")
	rig:piece("Body", "Ball", Vector3.one * 1.9, CFrame.new(0, 0.55, 0.35), "base")
	rig:piece("Body", "Ball", Vector3.one * 1.65, CFrame.new(0, 0.55, -2.0), "base")
	rig:piece("Body", "Ball", Vector3.one * 0.6, CFrame.new(0, 0.5, 2.55), "dark")
	local tip = if grizzled then "light" else "dark"
	for index = -2, 2 do
		tuft(rig, "Body", index * 0.32, 1.85 - math.abs(index) * 0.12, -0.95 + math.abs(index) * 0.08, 20, index * 10, -index * 12, 0.75, if index % 2 == 0 then tip else "dark")
	end
	for _, side in { -1, 1 } do
		tuft(rig, "Body", 1.25 * side, 0.4, -1.0, 0, 12 * side, -70 * side, 0.7, "base")
		tuft(rig, "Body", 1.1 * side, -0.55, 0.2, -110, 0, -30 * side, 0.7, "base")
		tuft(rig, "Body", 1.0 * side, -0.4, 1.4, -120, 0, -25 * side, 0.6, "dark")
	end

	rig:bone("Head", "Body", at(0, 0.55, -2.65, -8))
	rig:piece("Head", "Ball", Vector3.one * 1.55, CFrame.new(), "base")
	rig:pair("Head", "Ball", Vector3.one * 0.95, 0.45, -0.18, -0.12, 0, 0, 0, "base")
	rig:piece("Head", "Block", Vector3.new(0.82, 0.62, 0.8), CFrame.new(0, -0.25, -0.82), "light")
	rig:piece("Head", "Ball", Vector3.one * 0.8, CFrame.new(0, -0.2, -1.0), "light")
	rig:piece("Head", "Block", Vector3.new(0.44, 0.28, 0.22), CFrame.new(0, -0.02, -1.36), "nose", { material = SMOOTH })
	rig:piece("Head", "Block", Vector3.new(1.0, 0.18, 0.34), at(0, 0.38, -0.5, -10), "dark")
	rig:pair("Head", "Ball", Vector3.one * 0.52, 0.55, 0.62, 0.14, 0, 0, 0, "base")
	rig:pair("Head", "Ball", Vector3.one * 0.32, 0.56, 0.6, 0.0, 0, 0, 0, "dark")
	rig:pair("Head", "Ball", Vector3.one * 0.16, 0.38, 0.18, -0.62, 0, 0, 0, "eye", { material = SMOOTH, glow = rig.palette.glowEyes })
	rig:pair("Head", "Wedge", Vector3.new(0.12, 0.4, 0.5), 0.7, -0.25, 0.25, -20, 0, -25, "base")
	if grizzled then
		-- Old scars across the muzzle
		rig:piece("Head", "Block", Vector3.new(0.05, 0.42, 0.04), at(0.2, 0.05, -0.8, -40, 0, 25), "light", { material = SMOOTH })
		rig:piece("Head", "Block", Vector3.new(0.05, 0.34, 0.04), at(0.3, 0.02, -0.74, -40, 0, 25), "light", { material = SMOOTH })
	end
	rig:bone("Jaw", "Head", CFrame.new(0, -0.55, -0.4))
	rig:piece("Jaw", "Block", Vector3.new(0.7, 0.26, 0.82), CFrame.new(0, 0, -0.45), "light")
	rig:piece("Jaw", "Block", Vector3.new(0.5, 0.06, 0.6), CFrame.new(0, 0.14, -0.5), rgb(140, 64, 60), { material = SMOOTH })

	local claws = if rig.id == "Bear" then 0.3 else 0.42
	local front = { top = 1.3, topY = 0.1, upper = 1.3, upperD = 0.98, knee = 1.25, lower = 0.8, lowerD = 0.85, ankle = 0.78, paw = Vector3.new(0.98, 0.38, 1.15), toes = 4, claws = claws, low = "dark", pawTone = "dark" }
	leg(rig, "LegFL", "Body", Vector3.new(-0.9, -0.55, -1.3), front)
	leg(rig, "LegFR", "Body", Vector3.new(0.9, -0.55, -1.3), front)
	local back = { top = 1.6, topY = -0.1, topZ = 0.1, upper = 1.45, upperD = 0.98, upperZ = 0.08, knee = 1.45, kneeZ = 0.12, lower = 0.8, lowerD = 0.82, ankle = 0.78, paw = Vector3.new(0.95, 0.38, 1.2), toes = 4, claws = claws * 0.7, low = "dark", pawTone = "dark" }
	leg(rig, "LegBL", "Body", Vector3.new(-0.95, -0.35, 1.45), back)
	leg(rig, "LegBR", "Body", Vector3.new(0.95, -0.35, 1.45), back)

	if mythic then
		local hump = Vector3.new(0, 0.25, -0.85)
		rune(rig, "Body", hump, 1.45, Vector3.new(-0.75, 0.55, -0.2), 1, 1.3)
		rune(rig, "Body", hump, 1.45, Vector3.new(0.75, 0.55, -0.2), 3, 1.3)
		rune(rig, "Body", Vector3.new(0, 0.05, 1.3), 1.27, Vector3.new(-0.8, 0.35, 0.3), 2, 1.1)
		rune(rig, "Body", Vector3.new(0, 0.05, 1.3), 1.27, Vector3.new(0.8, 0.35, 0.3), 1, 1.1)
		rune(rig, "Head", Vector3.zero, 0.77, Vector3.new(0, 0.75, -0.6), 2, 0.8)
		rune(rig, "LegFL", Vector3.new(0, -0.6, 0), 0.49, Vector3.new(-1, 0, -0.4), 3, 0.9)
		rune(rig, "LegFR", Vector3.new(0, -0.6, 0), 0.49, Vector3.new(1, 0, -0.4), 1, 0.9)
	end
end

local function buildCat(rig)
	local panther = rig.id == "Panther"
	local k = if panther then 1.1 else 1
	rig:bone("Body", nil, CFrame.new(0, 2.2, 0))
	rig:piece("Body", "Ball", Vector3.one * 1.55 * k, CFrame.new(0, 0.05, -0.95), "base")
	rig:piece("Body", "Ball", Vector3.one * 1.42 * k, CFrame.new(0, 0.04, -0.2), "base")
	rig:piece("Body", "Ball", Vector3.one * 1.1 * k, CFrame.new(0, 0.14, 0.55), "base")
	rig:piece("Body", "Ball", Vector3.one * 1.28 * k, CFrame.new(0, 0.18, 1.2), "base")
	rig:piece("Body", "Ball", Vector3.one * 1.08 * k, CFrame.new(0, -0.32, -0.78), "light")
	rig:piece("Body", "Ball", Vector3.one * 0.95 * k, CFrame.new(0, 0.52, -1.52), "base")
	rig:piece("Body", "Ball", Vector3.one * 0.8 * k, CFrame.new(0, 0.36, -1.66), "light")
	if rig.palette.spots then
		spots(rig, "Body", Vector3.new(0, 0.05, -0.95), 0.775, 9, "dark", 0.2)
		spots(rig, "Body", Vector3.new(0, 0.04, -0.2), 0.71, 9, "dark", 0.21)
		spots(rig, "Body", Vector3.new(0, 0.14, 0.55), 0.55, 6, "dark", 0.18)
		spots(rig, "Body", Vector3.new(0, 0.18, 1.2), 0.64, 8, "dark", 0.2)
		spots(rig, "Body", Vector3.new(0, 0.52, -1.52), 0.475, 4, "dark", 0.16)
	elseif rig.palette.rosettes then
		spots(rig, "Body", Vector3.new(0, 0.04, -0.2), 0.78, 7, "dark", 0.3)
		spots(rig, "Body", Vector3.new(0, 0.18, 1.2), 0.7, 6, "dark", 0.3)
	end
	tuft(rig, "Body", 0, -0.8, -1.05, -150, 0, 0, 0.45, "light")

	rig:bone("Head", "Body", at(0, 0.82, -1.98, -4))
	rig:piece("Head", "Ball", Vector3.one * 0.92 * k, CFrame.new(), "base")
	rig:piece("Head", "Ball", Vector3.one * 0.62 * k, CFrame.new(0, -0.12, -0.3), "light")
	rig:piece("Head", "Block", Vector3.new(0.44, 0.26, 0.36) * k, CFrame.new(0, -0.17, -0.44), "light")
	rig:piece("Head", "Block", Vector3.new(0.38, 0.14, 0.3) * k, at(0, 0.0, -0.42, -18), "base")
	rig:piece("Head", "Block", Vector3.new(0.2, 0.14, 0.12) * k, CFrame.new(0, -0.05, -0.62 * k), "nose", { material = SMOOTH })
	rig:pair("Head", "Ball", Vector3.one * 0.15, 0.22 * k, 0.1, -0.35 * k, 0, 0, 0, "eye", { material = SMOOTH })
	rig:pair("Head", "Ball", Vector3.one * 0.32 * k, 0.33 * k, 0.38 * k, 0.06, 0, 0, 0, "base")
	rig:pair("Head", "Ball", Vector3.one * 0.2 * k, 0.34 * k, 0.38 * k, -0.04, 0, 0, 0, "dark")
	if rig.palette.spots then
		-- Tear marks from the eyes down to the mouth
		rig:pair("Head", "Block", Vector3.new(0.05, 0.36, 0.05), 0.2, -0.1, -0.44, -25, 0, -8, "dark", { material = SMOOTH, exact = true })
	end
	rig:pair("Head", "Wedge", Vector3.new(0.08, 0.22, 0.34), 0.42 * k, -0.1, 0.05, 0, 0, -25, "light")
	rig:bone("Jaw", "Head", CFrame.new(0, -0.28, -0.3))
	rig:piece("Jaw", "Block", Vector3.new(0.36, 0.12, 0.38) * k, CFrame.new(0, -0.02, -0.2), "light")

	local front = { top = 0.62 * k, upper = 1.0, upperD = 0.36 * k, knee = 1.0, lower = 0.82, lowerD = 0.26 * k, ankle = 0.86, paw = Vector3.new(0.32, 0.18, 0.42) * k, toes = 3, low = "base" }
	leg(rig, "LegFL", "Body", Vector3.new(-0.38, -0.25, -1.0), front)
	leg(rig, "LegFR", "Body", Vector3.new(0.38, -0.25, -1.0), front)
	local back = { top = 0.82 * k, topY = -0.15, upper = 1.3, upperD = 0.44 * k, upperZ = 0.12, upperPitch = -12, knee = 1.3, kneeZ = 0.3, lower = 0.82, lowerD = 0.24 * k, lowerPitch = 10, ankle = 0.8, paw = Vector3.new(0.3, 0.18, 0.42) * k, toes = 3, low = "base" }
	leg(rig, "LegBL", "Body", Vector3.new(-0.4, 0, 1.25), back)
	leg(rig, "LegBR", "Body", Vector3.new(0.4, 0, 1.25), back)
	local ring = if rig.palette.spots then "dark" else nil
	tail(rig, "Body", Vector3.new(0, 0.38, 1.82), {
		{ pitch = 58, length = 0.95, from = 0.36 * k, to = 0.33 * k, balls = 5 },
		{ pitch = -12, length = 0.95, from = 0.32 * k, to = 0.3 * k, balls = 5, ring = ring },
		{ pitch = -38, length = 0.75, from = 0.29 * k, to = 0.26 * k, balls = 4, ring = ring, tone = if rig.palette.spots then "light" else "base" },
	})
end

local function buildCroc(rig)
	rig:bone("Body", nil, CFrame.new(0, 0.78, 0))
	rig:piece("Body", "Block", Vector3.new(1.4, 0.82, 3.0), CFrame.new(), "base")
	rig:pair("Body", "Cylinder", Vector3.new(3.0, 0.8, 0.8), 0.68, -0.04, 0, 0, 90, 0, "base")
	rig:piece("Body", "Block", Vector3.new(1.5, 0.24, 2.8), CFrame.new(0, -0.32, 0), "light", { material = SMOOTH })
	rig:piece("Body", "Block", Vector3.new(1.3, 0.16, 2.9), CFrame.new(0, 0.42, 0), "dark")
	for row = 0, 5 do
		local z = -1.25 + row * 0.5
		rig:pair("Body", "Wedge", Vector3.new(0.2, 0.2, 0.34), 0.28, 0.58, z, 0, 0, 0, "dark")
		rig:pair("Body", "Wedge", Vector3.new(0.16, 0.14, 0.28), 0.6, 0.5, z + 0.12, 0, 0, -20, "dark")
	end
	rig:piece("Body", "Block", Vector3.new(1.2, 0.68, 1.0), CFrame.new(0, 0.0, -1.9), "base")
	rig:pair("Body", "Cylinder", Vector3.new(1.0, 0.66, 0.66), 0.5, -0.04, -1.9, 0, 90, 0, "base")
	rig:piece("Body", "Block", Vector3.new(1.25, 0.2, 0.9), CFrame.new(0, -0.3, -1.9), "light", { material = SMOOTH })

	rig:bone("Head", "Body", CFrame.new(0, 0.06, -2.4))
	rig:piece("Head", "Block", Vector3.new(1.05, 0.52, 0.9), CFrame.new(0, 0.06, -0.35), "base")
	rig:pair("Head", "Ball", Vector3.one * 0.36, 0.32, 0.34, -0.42, 0, 0, 0, "base")
	rig:pair("Head", "Ball", Vector3.one * 0.17, 0.36, 0.44, -0.5, 0, 0, 0, "eye", { material = SMOOTH })
	rig:piece("Head", "Block", Vector3.new(0.8, 0.3, 1.05), CFrame.new(0, 0.0, -1.3), "base")
	rig:piece("Head", "Block", Vector3.new(0.62, 0.26, 0.85), CFrame.new(0, -0.01, -2.2), "base")
	rig:piece("Head", "Wedge", Vector3.new(0.6, 0.12, 1.6), at(0, 0.21, -1.6, 0, 180, 0), "dark")
	rig:piece("Head", "Ball", Vector3.one * 0.28, CFrame.new(0, 0.1, -2.5), "dark")
	for index = 0, 5 do
		local z = -0.85 - index * 0.28
		local x = if z < -1.85 then 0.27 else 0.36
		rig:pair("Head", "Wedge", Vector3.new(0.07, 0.15, 0.08), x, -0.2, z, 180, 0, 0, "teeth", { material = SMOOTH, exact = true })
	end
	rig:bone("Jaw", "Head", CFrame.new(0, -0.2, -0.55))
	rig:piece("Jaw", "Block", Vector3.new(0.74, 0.2, 1.4), CFrame.new(0, -0.04, -0.75), "light", { material = SMOOTH })
	rig:piece("Jaw", "Block", Vector3.new(0.56, 0.18, 0.75), CFrame.new(0, -0.04, -1.8), "light", { material = SMOOTH })
	rig:pair("Jaw", "Block", Vector3.new(0.08, 0.2, 1.4), 0.36, -0.02, -0.75, 0, 0, 0, "base")
	for index = 0, 4 do
		rig:pair("Jaw", "Wedge", Vector3.new(0.06, 0.13, 0.07), 0.28, 0.11, -0.45 - index * 0.32, 0, 0, 0, "teeth", { material = SMOOTH, exact = true })
	end

	-- Short legs splayed out to the side
	for _, spec in { { "LegFL", -1, -1.1 }, { "LegFR", 1, -1.1 }, { "LegBL", -1, 1.05 }, { "LegBR", 1, 1.05 } } do
		local name, side, z = spec[1], spec[2], spec[3]
		local hind = z > 0
		rig:bone(name, "Body", CFrame.new(0.82 * side, -0.12, z))
		rig:piece(name, "Ball", Vector3.one * (if hind then 0.6 else 0.5), CFrame.new(), "base")
		rig:piece(name, "Cylinder", Vector3.new(0.7, if hind then 0.4 else 0.34, if hind then 0.4 else 0.34), at(0.3 * side, -0.08, 0, 0, 0, 15 * side), "base")
		rig:bone(name .. "2", name, CFrame.new(0.62 * side, -0.14, 0))
		rig:piece(name .. "2", "Cylinder", Vector3.new(0.48, 0.28, 0.28), at(0, -0.22, 0, 0, 0, 90), "base")
		rig:piece(name .. "2", "Block", Vector3.new(0.5, 0.1, 0.55), CFrame.new(0.05 * side, -0.45, -0.12), "dark")
		for toe = -1, 1 do
			rig:piece(name .. "2", "Wedge", Vector3.new(0.1, 0.08, 0.22), at(0.05 * side + toe * 0.16, -0.46, -0.48, 0, 180 + toe * 12, 0), "claw", { material = SMOOTH })
		end
	end

	-- A long tail with a ridge of scutes
	local parent = "Body"
	local offset = CFrame.new(0, 0.04, 1.5)
	local sections = { { 1.25, 0.7, 1.3 }, { 0.95, 0.58, 1.3 }, { 0.62, 0.46, 1.3 }, { 0.36, 0.32, 1.1 } }
	for index, section in sections do
		local name = "Tail" .. index
		rig:bone(name, parent, offset)
		local width, height, length = section[1], section[2], section[3]
		rig:piece(name, "Block", Vector3.new(width, height, length), CFrame.new(0, -0.02 * index, length / 2), "base")
		rig:piece(name, "Block", Vector3.new(width * 0.9, 0.16, length), CFrame.new(0, -height / 2 - 0.02 * index + 0.06, length / 2), "light", { material = SMOOTH })
		for step = 0, 2 do
			local z = length * (0.2 + step * 0.3)
			if index <= 2 then
				rig:pair(name, "Wedge", Vector3.new(0.1, 0.24, 0.3), width * 0.24, height / 2 + 0.08, z, 0, 0, 0, "dark")
			else
				rig:piece(name, "Wedge", Vector3.new(0.1, 0.26, 0.3), CFrame.new(0, height / 2 + 0.08, z), "dark")
			end
		end
		parent = name
		offset = CFrame.new(0, 0, length)
	end
end

local function buildBird(rig)
	local id = rig.id
	local palette = rig.palette
	local phoenix = id == "Phoenix"
	local storm = id == "StormEagle"
	local headTone = if palette.whiteHead then "light" else "base"
	rig:bone("Body", nil, at(0, 1.78, 0.1, 32))
	rig:piece("Body", "Ball", Vector3.one * 1.35, CFrame.new(0, 0.12, -0.22), if phoenix then "light" else (if palette.whiteHead then "base" else "light"))
	rig:piece("Body", "Ball", Vector3.one * 1.3, CFrame.new(0, 0.22, 0.2), "base")
	rig:piece("Body", "Ball", Vector3.one * 1.2, CFrame.new(0, -0.12, 0.2), if palette.whiteHead then "dark" else "light")
	rig:piece("Body", "Ball", Vector3.one * 0.95, CFrame.new(0, -0.05, 0.72), "base")
	rig:piece("Body", "Ball", Vector3.one * 0.85, CFrame.new(0, 0.7, -0.35), headTone)
	if not palette.whiteHead and not phoenix then
		-- A band of dark streaks across the belly
		local center = Vector3.new(0, 0.12, -0.22)
		for index = 0, 6 do
			local angle = math.rad(-60 + index * 20)
			local normal = Vector3.new(math.sin(angle), -0.45 + (index % 2) * 0.12, -math.cos(angle)).Unit
			local point = center + normal * 0.66
			rig:piece("Body", "Block", Vector3.new(0.05, 0.16, 0.05), CFrame.lookAt(point, point + normal), "dark", { exact = true })
		end
	end
	for index = -1, 1 do
		tuft(rig, "Body", index * 0.3, -0.5, -0.55, -140, index * 15, 0, 0.5, if phoenix then "light" else "base")
	end

	rig:bone("Head", "Body", at(0, 0.98, -0.42, -32))
	rig:piece("Head", "Ball", Vector3.one * 0.9, CFrame.new(), headTone)
	rig:piece("Head", "Ball", Vector3.one * 0.66, CFrame.new(0, -0.14, -0.16), headTone)
	rig:piece("Head", "Block", Vector3.new(0.72, 0.12, 0.3), at(0, 0.22, -0.24, -14), if palette.whiteHead then "light" else "dark")
	rig:piece("Head", "Block", Vector3.new(0.28, 0.2, 0.2), CFrame.new(0, 0.02, -0.44), "cere", { material = SMOOTH })
	rig:piece("Head", "Wedge", Vector3.new(0.18, 0.24, 0.36), CFrame.new(0, -0.02, -0.66), "beak", { material = SMOOTH })
	rig:piece("Head", "Wedge", Vector3.new(0.14, 0.18, 0.12), at(0, -0.18, -0.82, 180, 0, 0), "beak", { material = SMOOTH })
	rig:pair("Head", "Wedge", Vector3.new(0.05, 0.1, 0.3), 0.08, -0.13, -0.6, 0, 0, 0, "dark", { material = SMOOTH })
	rig:pair("Head", "Ball", Vector3.one * 0.24, 0.29, 0.06, -0.26, 0, 0, 0, "cere", { material = SMOOTH })
	rig:pair("Head", "Ball", Vector3.one * 0.17, 0.31, 0.06, -0.29, 0, 0, 0, "eye", { material = SMOOTH, glow = palette.glowEyes })
	if phoenix then
		-- A swept crest of flame-tipped feathers
		for index = 0, 2 do
			rig:piece("Head", "Wedge", Vector3.new(0.08, 0.5 - index * 0.08, 0.5), at(0, 0.38 - index * 0.04, 0.2 + index * 0.16, 30 + index * 12, 0, 0), "light")
			rig:piece("Head", "Block", Vector3.new(0.05, 0.05, 0.22), at(0, 0.62 - index * 0.1, 0.36 + index * 0.2, 30 + index * 12, 0, 0), "glow", { glow = true })
		end
	end

	-- Wings: an inner arm and an outer hand with fanned primaries
	local span = if phoenix then 1.12 else 1
	for _, side in { -1, 1 } do
		local wing = if side < 0 then "WingL" else "WingR"
		rig:bone(wing, "Body", CFrame.new(0.6 * side, 0.38, -0.05))
		rig:piece(wing, "Block", Vector3.new(1.45 * span, 0.16, 0.95), CFrame.new(0.72 * side * span, 0, 0.12), "base")
		rig:piece(wing, "Block", Vector3.new(1.3 * span, 0.1, 0.42), CFrame.new(0.66 * side * span, 0.06, -0.2), if palette.whiteHead then "base" else "light")
		for index = 0, 4 do
			rig:piece(wing, "Block", Vector3.new(0.28, 0.07, 0.62), at((0.2 + index * 0.27) * side * span, -0.03, 0.78, 0, -6 * side, 0), "dark")
		end
		local hand = wing .. "2"
		rig:bone(hand, wing, CFrame.new(1.42 * side * span, 0, 0))
		rig:piece(hand, "Block", Vector3.new(1.0 * span, 0.14, 0.78), CFrame.new(0.48 * side * span, 0, 0.12), "base")
		for index = 0, 5 do
			local yaw = (-8 + index * 9) * side
			local frame = CFrame.new(0.82 * side * span, 0, 0.1 + (index - 2.5) * 0.12) * ang(0, yaw, 0)
			rig:piece(hand, "Block", Vector3.new(1.4 * span, 0.06, 0.24), frame * CFrame.new(0.62 * side * span, 0, 0), "base")
			rig:piece(hand, "Block", Vector3.new(0.5, 0.065, 0.22), frame * CFrame.new(1.12 * side * span, 0, 0), if phoenix or storm then "glow" else "dark", { glow = phoenix or storm })
		end
	end

	-- Tail fan with dark bands
	rig:bone("Tail", "Body", at(0, -0.15, 0.95, 18))
	local tailLength = if phoenix then 1.3 else 1.15
	for index = -2, 2 do
		local frame = ang(0, index * 9, 0) * CFrame.new(0, 0, tailLength / 2)
		rig:piece("Tail", "Block", Vector3.new(0.27, 0.06, tailLength), frame, if palette.whiteHead then "light" else "base")
		rig:piece("Tail", "Block", Vector3.new(0.28, 0.065, 0.12), frame * CFrame.new(0, 0, tailLength * 0.25), "dark", { exact = palette.whiteHead == nil })
		if not palette.whiteHead then
			rig:piece("Tail", "Block", Vector3.new(0.28, 0.065, 0.16), frame * CFrame.new(0, 0, tailLength * 0.44), "dark")
		end
	end
	if phoenix then
		-- Long trailing plumes that curl at the ends
		for index = -1, 1 do
			local frame = ang(-6, index * 14, 0) * CFrame.new(0, 0, tailLength)
			for step = 0, 2 do
				frame = frame * ang(-10 - step * 6, 0, 0)
				rig:piece("Tail", "Block", Vector3.new(0.2 - step * 0.03, 0.05, 0.95), frame * CFrame.new(0, 0, 0.45), if step == 2 then "glow" else "light", { glow = step == 2 })
				frame = frame * CFrame.new(0, 0, 0.9)
			end
		end
	end

	-- Feathered thighs, scaled legs and talons
	for _, side in { -1, 1 } do
		local name = if side < 0 then "LegL" else "LegR"
		rig:bone(name, "Body", at(0.3 * side, -0.55, 0.08, -32))
		rig:piece(name, "Ball", Vector3.one * 0.58, CFrame.new(0, -0.05, 0), if palette.whiteHead then "dark" else "light")
		rig:piece(name, "Cylinder", Vector3.new(0.8, 0.17, 0.17), at(0, -0.62, 0, 0, 0, 90), "feet", { material = SMOOTH })
		for toe = -1, 1 do
			local frame = CFrame.new(0, -1.0, -0.05) * ang(0, toe * 22, 0)
			rig:piece(name, "Block", Vector3.new(0.09, 0.09, 0.42), frame * CFrame.new(0, 0, -0.2), "feet", { material = SMOOTH })
			rig:piece(name, "Wedge", Vector3.new(0.07, 0.12, 0.14), frame * at(0, -0.02, -0.44, 180, 0, 0), "claw", { material = SMOOTH })
		end
		rig:piece(name, "Block", Vector3.new(0.08, 0.08, 0.3), CFrame.new(0, -1.0, 0.16), "feet", { material = SMOOTH })
	end
end

local BUILDERS = {
	Quad = function(rig)
		local id = rig.id
		if id == "Bear" or id == "DireBear" or id == "MythicBear" then
			buildBear(rig)
		elseif id == "Cheetah" or id == "Panther" then
			buildCat(rig)
		else
			buildWolf(rig)
		end
	end,
	Bird = buildBird,
	Croc = buildCroc,
}

-- Builds an animal. Returns the rig (see Rig.new for opts).
function Shape.build(animalId: string, opts: { [string]: any })
	local rig = Rig.new(animalId, opts)
	BUILDERS[rig.spec.family](rig)
	rig:assemble(opts.parent or workspace)
	return rig
end

-- Movement ----------------------------------------------------------------------------------------

local function legSwing(rig, poses, name: string, phase: number, swing: number, lift: number, front: boolean)
	local s = math.sin(phase)
	local raise = math.max(0, math.cos(phase))
	poses[name] = ang(swing * s, 0, 0)
	poses[name .. "2"] = ang(if front then -lift * raise else lift * raise * 0.7, 0, 0)
end

local function actionOf(rig): (string?, number, { [string]: any })
	local action = rig.action
	if not action then
		return nil, 0, {}
	end
	local u = (os.clock() - action.start) / action.length
	if u >= 1 then
		rig.action = nil
		return nil, 0, {}
	end
	return action.name, u, action.data
end

local function idleLook(anim, dt: number, snappy: boolean)
	if anim.t >= anim.nextLook then
		anim.lookAt = (math.random() - 0.5) * (if snappy then 80 else 50)
		anim.lookPitchAt = (math.random() - 0.5) * 16
		anim.nextLook = anim.t + (if snappy then 0.6 + math.random() * 1.4 else 1.8 + math.random() * 2.6)
	end
	local rate = if snappy then 16 else 2.2
	anim.lookYaw = approach(anim.lookYaw, anim.lookAt, rate, dt)
	anim.lookPitch = approach(anim.lookPitch, anim.lookPitchAt or 0, rate, dt)
end

local function poseQuad(rig, dt: number)
	local anim, spec = rig.anim, rig.spec
	local poses = {}
	local gait = anim.gait
	local moving = math.min(gait, 1.6)
	local heavy = spec.heavy == true
	local gallop = spec.gallopAt ~= nil and gait > spec.gallopAt
	local offsets = spec.offsets
	local p = anim.phase
	local swing = if heavy then 26 else (if gallop then 46 else 34)
	local lift = if heavy then 30 else 48
	local legPhase = if gallop then { 0, 0.35, math.pi, math.pi + 0.35 } else offsets
	legSwing(rig, poses, "LegFL", p + legPhase[1], swing * moving, lift * math.min(1, moving), true)
	legSwing(rig, poses, "LegFR", p + legPhase[2], swing * moving, lift * math.min(1, moving), true)
	legSwing(rig, poses, "LegBL", p + legPhase[3], swing * moving, lift * math.min(1, moving), false)
	legSwing(rig, poses, "LegBR", p + legPhase[4], swing * moving, lift * math.min(1, moving), false)

	local breathe = math.sin(anim.t * 1.7) * 0.03
	local bob = (if gallop then 0.16 else 0.08) * math.abs(math.sin(p)) * math.min(1, moving)
	local bodyPitch = if gallop then math.sin(p * 2) * 4 else 0
	local bodyRoll = if heavy then math.sin(p) * 3 * math.min(1, moving) else 0
	local bodyY = breathe + bob
	idleLook(anim, dt, false)
	local look = 1 - math.min(1, moving)
	local headYaw = anim.lookYaw * look
	local headPitch = anim.lookPitch * look - 6 * math.min(1, moving) + math.sin(p * 2) * 3 * math.min(1, moving)
	local jaw = if spec.cat or heavy then 0 else math.max(0, math.sin(anim.t * 9)) * 7 * math.min(1, moving)
	local tailYaw = math.sin(anim.t * (if spec.cat then 2.2 else 1.4)) * (14 * look + 4)
	local tailPitch = -24 * math.min(1, moving)

	-- In the air: legs reach, body follows the arc
	local air = anim.air
	if air > 0.01 then
		bodyPitch += math.clamp(anim.vy * 0.6, -14, 14) * air
		for _, name in { "LegFL", "LegFR" } do
			poses[name] = poses[name]:Lerp(ang(42, 0, 0), air)
			poses[name .. "2"] = poses[name .. "2"]:Lerp(ang(-20, 0, 0), air)
		end
		for _, name in { "LegBL", "LegBR" } do
			poses[name] = poses[name]:Lerp(ang(-40, 0, 0), air)
			poses[name .. "2"] = poses[name .. "2"]:Lerp(ang(25, 0, 0), air)
		end
		tailPitch -= 18 * air
	end

	local bodyZ = 0
	local name, u, data = actionOf(rig)
	if name then
		local e = strikeCurve(u)
		local h = holdCurve(u)
		if name == "Bite" or name == "Snap" then
			headPitch += lerp(14, -10, math.min(1, u * 2.5)) * h
			jaw = math.max(jaw, (if u < 0.35 then 38 * (u / 0.35) else 38 * math.max(0, 1 - (u - 0.35) * 5)))
			bodyZ -= 0.35 * e
			bodyPitch -= 5 * e
		elseif name == "Maul" or name == "Swipe" then
			local legName = if (data.side or 1) > 0 then "LegFR" else "LegFL"
			poses[legName] = ang(lerp(95, 30, math.min(1, u * 1.6)) * h, 0, (data.side or 1) * -25 * e)
			poses[legName .. "2"] = ang(-35 * h, 0, 0)
			bodyPitch += 8 * h
			bodyZ -= 0.25 * e
			headPitch -= 8 * e
		elseif name == "Crouch" then
			bodyY -= 0.35 * h
			bodyPitch -= 6 * h
			headPitch -= 10 * h
			for _, legName in { "LegFL", "LegFR", "LegBL", "LegBR" } do
				local front = string.sub(legName, 4, 4) == "F"
				poses[legName] = ang(if front then 18 * h else -26 * h, 0, 0)
				poses[legName .. "2"] = ang(if front then -30 * h else 40 * h, 0, 0)
			end
			tailPitch += 10 * h
		elseif name == "Leap" then
			bodyPitch += 6 * h
			for _, legName in { "LegFL", "LegFR" } do
				poses[legName] = ang(60 * h, 0, 0)
			end
			for _, legName in { "LegBL", "LegBR" } do
				poses[legName] = ang(-55 * h, 0, 0)
				poses[legName .. "2"] = ang(30 * h, 0, 0)
			end
			tailPitch -= 20 * h
		elseif name == "Rear" then
			bodyPitch += 42 * h
			bodyY += 0.75 * h
			bodyZ += 0.7 * h
			for _, legName in { "LegFL", "LegFR" } do
				poses[legName] = ang(70 * h, 0, if legName == "LegFL" then 12 * h else -12 * h)
				poses[legName .. "2"] = ang(-40 * h, 0, 0)
			end
			for _, legName in { "LegBL", "LegBR" } do
				poses[legName] = ang(-36 * h, 0, 0)
			end
			headPitch += 10 * h
			jaw = math.max(jaw, 24 * h)
		elseif name == "Slam" then
			local k = 1 - u
			bodyPitch -= 14 * k
			bodyY -= 0.3 * k
			for _, legName in { "LegFL", "LegFR" } do
				poses[legName] = ang(32 * k, 0, 0)
				poses[legName .. "2"] = ang(-10 * k, 0, 0)
			end
			headPitch -= 6 * k
			jaw = math.max(jaw, 20 * k)
		elseif name == "Roll" then
			bodyRoll += u * 720
		elseif name == "Flinch" then
			bodyZ += 0.25 * e
			headPitch += 16 * e
			bodyPitch += 4 * e
		elseif name == "Howl" then
			headPitch += 48 * h
			bodyPitch += 10 * h
			jaw = math.max(jaw, 28 * h)
			tailPitch += 10 * h
		elseif name == "Gape" then
			jaw = math.max(jaw, 42 * h)
			headPitch += 8 * h
		end
	end

	poses.Body = CFrame.new(0, bodyY, bodyZ) * ang(bodyPitch, 0, bodyRoll)
	poses.Head = ang(headPitch, headYaw, 0)
	poses.Jaw = ang(jaw, 0, 0)
	poses.Tail1 = ang(tailPitch * 0.5, tailYaw * 0.5, 0)
	poses.Tail2 = ang(tailPitch * 0.3, tailYaw * 0.7, 0)
	poses.Tail3 = ang(tailPitch * 0.2, tailYaw, 0)
	return poses
end

local function poseCroc(rig, dt: number)
	local anim = rig.anim
	local poses = {}
	local moving = math.min(anim.gait, 1.6)
	local p = anim.phase
	local sway = math.sin(p) * 7 * math.min(1, moving)
	for index, entry in { { "LegFL", 0 }, { "LegFR", math.pi }, { "LegBL", math.pi }, { "LegBR", 0 } } do
		local side = if index % 2 == 1 then -1 else 1
		local s = math.sin(p + entry[2])
		poses[entry[1]] = ang(0, s * 30 * moving * side, -math.max(0, math.cos(p + entry[2])) * 20 * math.min(1, moving) * side)
		poses[entry[1] .. "2"] = CFrame.identity
	end
	idleLook(anim, dt, false)
	local look = 1 - math.min(1, moving)
	local jaw = 0
	-- Now and then an idle gape
	anim.gapeAt = anim.gapeAt or (anim.t + 6)
	if anim.t > anim.gapeAt then
		local u = (anim.t - anim.gapeAt) / 2.2
		if u >= 1 then
			anim.gapeAt = anim.t + 7 + math.random() * 6
		else
			jaw = holdCurve(u) * 30 * look
		end
	end
	local bodyRoll, bodyY, bodyZ = 0, math.sin(anim.t * 1.2) * 0.02, 0
	local headPitch, headYaw = anim.lookPitch * 0.4 * look, anim.lookYaw * 0.5 * look - sway
	local name, u = actionOf(rig)
	if name then
		local e, h = strikeCurve(u), holdCurve(u)
		if name == "Snap" or name == "Bite" then
			jaw = math.max(jaw, if u < 0.4 then 44 * u / 0.4 else 44 * math.max(0, 1 - (u - 0.4) * 5))
			headPitch += 10 * h
			bodyZ -= 0.4 * e
		elseif name == "Gape" then
			jaw = math.max(jaw, 46 * h)
			headPitch += 12 * h
		elseif name == "Roll" then
			bodyRoll = u * 720
			bodyY += 0.2 * h
		elseif name == "Flinch" then
			bodyZ += 0.2 * e
			headPitch += 10 * e
		elseif name == "Crouch" or name == "Howl" then
			headPitch += 18 * h
			jaw = math.max(jaw, 30 * h)
		end
	end
	if anim.air > 0.01 then
		headPitch += 6 * anim.air
	end
	poses.Body = CFrame.new(0, bodyY, bodyZ) * ang(0, sway, bodyRoll)
	poses.Head = ang(headPitch, headYaw, 0)
	poses.Jaw = ang(jaw, 0, 0)
	local tailWave = anim.t * 2.2 + p
	for index = 1, 4 do
		poses["Tail" .. index] = ang(0, math.sin(tailWave - index * 0.8) * (4 + 8 * math.min(1, moving)) * (0.6 + index * 0.25) - sway * 0.6, 0)
	end
	return poses
end

local function poseBird(rig, dt: number)
	local anim = rig.anim
	local poses = {}
	local air = anim.air
	local moving = math.min(anim.gait, 1.4)
	-- Rising: flap hard. Falling slowly: glide with small corrections.
	local flapping = air > 0.5 and anim.vy > -6
	anim.flap = approach(anim.flap, if flapping then 1 else 0, 6, dt)
	anim.fold = approach(anim.fold, if air > 0.5 then 0 else 1, 7, dt)
	local fold = anim.fold
	anim.wingPhase = (anim.wingPhase or 0) + dt * lerp(2.5, 14, anim.flap)
	local beat = math.sin(anim.wingPhase) * lerp(4, 38, anim.flap) * (1 - fold)
	local bodyPitch = lerp(-6, 0, fold)
	local bodyY = (1 - fold) * 0.4 + math.sin(anim.t * 2) * 0.02
	local bodyZ = 0
	idleLook(anim, dt, true)
	local headYaw = anim.lookYaw * fold
	local headPitch = anim.lookPitch * fold - bodyPitch
	local tailPitch = lerp(-14, 0, fold)
	local legPitch = lerp(-70, 0, fold)
	-- Walking: a slight hop from foot to foot
	local walk = math.sin(anim.phase) * 22 * moving * fold
	local spread = 1 - fold
	local wingYaw = lerp(0, 82, fold)
	local wingTilt = lerp(0, 72, fold)
	local handYaw = lerp(0, 14, fold)
	local dihedral = 6 * spread
	local name, u = actionOf(rig)
	if name then
		local e, h = strikeCurve(u), holdCurve(u)
		if name == "Talon" or name == "Bite" then
			legPitch = lerp(legPitch, 70, h)
			wingYaw = lerp(wingYaw, 10, h)
			wingTilt = lerp(wingTilt, 0, h)
			dihedral += 30 * h
			bodyPitch += 18 * h
			headPitch -= 10 * e
		elseif name == "Crouch" then
			wingYaw = lerp(wingYaw, 30, h)
			wingTilt = lerp(wingTilt, 20, h)
			dihedral += 25 * h
			bodyY -= 0.25 * h
			headPitch -= 12 * h
		elseif name == "Dive" then
			wingYaw = lerp(wingYaw, 55, h)
			wingTilt = lerp(wingTilt, 10, h)
			dihedral = lerp(dihedral, 12, h)
			beat *= 1 - h
			bodyPitch = lerp(bodyPitch, -38, h)
			headPitch = lerp(headPitch, 30, h)
			legPitch = lerp(legPitch, 40, h)
		elseif name == "Rise" or name == "Nova" or name == "Howl" then
			wingYaw = lerp(wingYaw, -10, h)
			wingTilt = lerp(wingTilt, 0, h)
			dihedral += 45 * h
			beat *= 1 - h
			bodyPitch += 30 * h
			headPitch += 20 * h
		elseif name == "Flinch" then
			bodyZ += 0.2 * e
			headPitch += 15 * e
			dihedral += 20 * e
		end
	end
	poses.Body = CFrame.new(0, bodyY, bodyZ) * ang(bodyPitch, 0, 0)
	poses.Head = ang(headPitch, headYaw, 0)
	poses.WingL = ang(0, wingYaw, 0) * ang(wingTilt, 0, 0) * ang(0, 0, -(dihedral + beat))
	poses.WingR = ang(0, -wingYaw, 0) * ang(wingTilt, 0, 0) * ang(0, 0, dihedral + beat)
	poses.WingL2 = ang(0, handYaw, 0) * ang(0, 0, beat * 0.5)
	poses.WingR2 = ang(0, -handYaw, 0) * ang(0, 0, -beat * 0.5)
	poses.Tail = ang(tailPitch, 0, 0)
	poses.LegL = ang(legPitch + walk, 0, 0)
	poses.LegR = ang(legPitch - walk, 0, 0)
	return poses
end

local POSERS = { Quad = poseQuad, Bird = poseBird, Croc = poseCroc }

-- One animation step. speed: studs per second over the ground; vy: vertical speed
function Rig:step(dt: number, speed: number, airborne: boolean, vy: number)
	local anim = self.anim
	anim.t += dt
	local spec = self.spec
	local reference = (spec.stride or 3.5) * self.size
	anim.gait = approach(anim.gait, speed / 10, 8, dt)
	anim.phase = (anim.phase + dt * (speed / reference) * math.pi * 2) % (math.pi * 2)
	anim.air = approach(anim.air, if airborne then 1 else 0, 10, dt)
	anim.vy = vy
	local poses = POSERS[spec.family](self, dt)
	for name, pose in poses do
		local bone = self.bones[name]
		if bone then
			bone.pose = pose
		end
	end
	local resized = false
	local grow = self.growing
	if grow then
		local u = math.clamp((os.clock() - grow.start) / grow.length, 0, 1)
		-- Ease out with a small overshoot, so the new body lands with weight
		local c = 1.4
		local k = u - 1
		self.grow = lerp(grow.from, 1, 1 + (c + 1) * k * k * k + c * k * k)
		resized = true
		if u >= 1 then
			self.grow = 1
			self.growing = nil
		end
	end
	-- Glowing parts breathe (runes, flame tips, spectral eyes)
	if #self.glows > 0 then
		local pulse = 0.12 + 0.12 * math.sin(anim.t * 2.4)
		for _, entry in self.glows do
			entry.part.Transparency = math.max(entry.see + pulse, self.fade)
		end
	end
	self:apply(resized)
end

function Rig:growIn(from: number, length: number)
	self.grow = from
	self.growing = { from = from, start = os.clock(), length = length }
	self:apply(true)
end

-- Poses a free-standing rig for a still frame (previews): pose name and how far into it
function Shape.still(rig, poseName: string?, progress: number?, speed: number?, airborne: boolean?)
	if poseName then
		rig.action = { name = poseName, start = os.clock() - (progress or 0.5) * 1, length = 1, data = {} }
	end
	rig.anim.t = 3
	rig.anim.phase = 1.1
	for _ = 1, 30 do
		rig.anim.t += 1 / 30
		if poseName then
			rig.action.start = os.clock() - (progress or 0.5)
		end
		rig.anim.gait = (speed or 0) / 10
		rig.anim.air = if airborne then 1 else 0
		rig.anim.fold = if airborne then 0 else 1
		rig.anim.flap = if airborne then 0.6 else 0
		rig.anim.lookYaw, rig.anim.lookAt = 8, 8
		rig.anim.lookPitch, rig.anim.lookPitchAt = 0, 0
		rig.anim.nextLook = math.huge
		local poses = POSERS[rig.spec.family](rig, 1 / 30)
		for name, pose in poses do
			if rig.bones[name] then
				rig.bones[name].pose = pose
			end
		end
	end
	rig:apply(true)
end

-- Hiding the human -----------------------------------------------------------------------------

-- The parts that make up the human look: body parts, accessories, the face
local function humanParts(model: Model): { Instance }
	local list = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			if item.Name ~= "HumanoidRootPart" and (item.Parent == model or item:FindFirstAncestorWhichIsA("Accessory") ~= nil) then
				table.insert(list, item)
			end
		elseif item:IsA("Decal") and item.Parent and item.Parent.Name == "Head" and item.Parent.Parent == model then
			table.insert(list, item)
		end
	end
	return list
end

-- What the server wants this part to look like right now (behind our local hiding)
local function serverValue(item: Instance): number
	if item:GetAttribute(OWNER_HIDDEN) ~= nil then
		return 1
	end
	local saved = item:GetAttribute(SAVED)
	return if typeof(saved) == "number" then saved else 0
end

-- Hides the human body on this screen. Returns (restore, howHidden): howHidden()
-- is how see-through the body would be without us (the animal follows it).
local function hideHuman(model: Model, onChange: () -> ())
	local parts = humanParts(model)
	local connections = {}
	local writing = false
	for _, item in parts do
		local target = item :: any
		if target:GetAttribute(SAVED) == nil then
			target:SetAttribute(SAVED, target.Transparency)
		end
		writing = true
		target.Transparency = 1
		writing = false
		-- Someone else (the server's veil, a cosmetic) changed it while we hide it:
		-- remember their value and keep it hidden
		table.insert(connections, target:GetPropertyChangedSignal("Transparency"):Connect(function()
			if writing or target.Transparency >= 1 then
				return
			end
			target:SetAttribute(SAVED, target.Transparency)
			writing = true
			target.Transparency = 1
			writing = false
			onChange()
		end))
		table.insert(connections, target:GetAttributeChangedSignal(OWNER_HIDDEN):Connect(onChange))
	end
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	local function howHidden(): number
		return if torso then serverValue(torso) else 0
	end
	local function restore()
		for _, connection in connections do
			connection:Disconnect()
		end
		for _, item in parts do
			local target = item :: any
			if target.Parent then
				local value = serverValue(target)
				target:SetAttribute(SAVED, nil)
				target.Transparency = value
			end
		end
	end
	return restore, howHidden
end
Shape.hideHuman = hideHuman

-- Persistent looks ----------------------------------------------------------------------------------

local function firstPart(model: Model, names: { string }): BasePart?
	for _, name in names do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function attach(part: BasePart, to: BasePart, offset: CFrame, parent: Instance)
	part.CFrame = to.CFrame * offset
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Anchored = false
	local weld = Instance.new("Weld")
	weld.Part0 = to
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	part.Parent = parent
end

-- Human form: a wolf-pelt mantle over the shoulders, a claw necklace from Degree 2,
-- and amber marks along the forearms at Degree 3
local function humanLook(kit)
	local model = kit.model :: Model
	local torso = firstPart(model, { "UpperTorso", "Torso" })
	if not torso then
		return nil
	end
	local folder = Instance.new("Model")
	folder.Name = LOOK_NAME
	local palette = PALETTES.Wolf
	local top = torso.Size.Y / 2
	local width = torso.Size.X / 2
	local function piece(shape: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, glow: boolean?)
		local part = newPart(shape, size)
		part.Color = color
		part.Material = if glow then Enum.Material.Neon else (material or FUR)
		part.CastShadow = size.Magnitude > 0.8
		attach(part, torso, offset, folder)
		return part
	end
	for _, side in { -1, 1 } do
		piece("Ball", Vector3.one * 1.0, CFrame.new(width * 0.62 * side, top - 0.05, 0.08), palette.base)
		piece("Ball", Vector3.one * 0.75, CFrame.new(width * 0.95 * side, top - 0.22, 0.05), palette.dark)
		piece("Wedge", Vector3.new(0.14, 0.4, 0.55), at(width * 1.1 * side, top - 0.6, 0.05, -170, 0, 15 * side), palette.light)
	end
	piece("Ball", Vector3.one * 0.95, CFrame.new(0, top - 0.02, 0.32), palette.dark)
	piece("Wedge", Vector3.new(0.9, 0.5, 0.5), at(0, top - 0.55, 0.42, 180, 0, 0), palette.base)
	if kit.degree >= 2 then
		for index = -2, 2 do
			local x = index * 0.2
			piece("Wedge", Vector3.new(0.08, 0.24, 0.1), at(x, top - 0.38 - (2 - math.abs(index)) * 0.05, -torso.Size.Z / 2 - 0.04, 180, 0, index * 8), BONE, SMOOTH)
		end
		piece("Ball", Vector3.one * 0.16, CFrame.new(0, top - 0.6, -torso.Size.Z / 2 - 0.05), AMBER, SMOOTH)
	end
	if kit.degree >= 3 then
		for _, name in { "LeftLowerArm", "RightLowerArm", "Left Arm", "Right Arm" } do
			local arm = model:FindFirstChild(name)
			if arm and arm:IsA("BasePart") then
				for index = 0, 2 do
					local part = newPart("Block", Vector3.new(0.05, 0.22, 0.05))
					part.Color = AMBER
					part.Material = Enum.Material.Neon
					part.CastShadow = false
					attach(part, arm, at(0, 0.25 - index * 0.2, -arm.Size.Z / 2 - 0.01, 0, 0, 30 * (if index % 2 == 0 then 1 else -1)), folder)
				end
			end
		end
	end
	folder.Parent = model
	-- Hidden whenever the body is (concealment, invisibility)
	local base: { [BasePart]: number } = {}
	for _, item in folder:GetDescendants() do
		if item:IsA("BasePart") then
			base[item] = item.Transparency
		end
	end
	local function follow()
		for part, transparency in base do
			part.Transparency = math.max(transparency, torso.Transparency)
		end
	end
	local connection = torso:GetPropertyChangedSignal("Transparency"):Connect(follow)
	follow()
	return function()
		connection:Disconnect()
		folder:Destroy()
	end
end

-- Lights and particles that make some animals what they are
local function animalExtras(rig, reduced: boolean)
	local palette = rig.palette
	local body = rig.bones.Body.part
	local id = rig.id
	local function emitter(parent: Instance, props: { [string]: any })
		local particles = Instance.new("ParticleEmitter")
		particles.LightInfluence = 0
		particles.Rotation = NumberRange.new(0, 360)
		particles.RotSpeed = NumberRange.new(-40, 40)
		for key, value in props do
			(particles :: any)[key] = value
		end
		if reduced then
			particles.Rate *= 0.4
		end
		particles.Parent = parent
		return particles
	end
	if id == "SpectralWolf" then
		emitter(body, {
			Texture = SMOKE, Color = ColorSequence.new(palette.light, palette.base), LightEmission = 0.4,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.75), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.8, 1.4), Rate = 7, Speed = NumberRange.new(0.3, 1), Drag = 2, SpreadAngle = Vector2.new(180, 180),
		})
		local light = Instance.new("PointLight")
		light.Color = palette.light
		light.Brightness = 0.7
		light.Range = 9
		light.Parent = body
	elseif id == "Phoenix" then
		for _, name in { "Body", "WingL2", "WingR2", "Tail" } do
			local bone = rig.bones[name]
			if bone then
				emitter(bone.part, {
					Texture = FIRE, Color = ColorSequence.new(rgb(255, 210, 120), EMBER), LightEmission = 1,
					Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, if name == "Body" then 1.1 else 0.6), NumberSequenceKeypoint.new(1, 0) }),
					Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
					Lifetime = NumberRange.new(0.35, 0.7), Rate = if name == "Body" then 14 else 7, Speed = NumberRange.new(1, 3),
					Acceleration = Vector3.new(0, 6, 0), Drag = 1, SpreadAngle = Vector2.new(40, 40),
				})
			end
		end
		local light = Instance.new("PointLight")
		light.Color = FLAME
		light.Brightness = 1.3
		light.Range = 12
		light.Parent = body
	elseif id == "MythicBear" then
		emitter(body, {
			Texture = SPARK, Color = ColorSequence.new(AMBER), LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new(0.2, 1),
			Lifetime = NumberRange.new(1, 1.8), Rate = 4, Speed = NumberRange.new(0.5, 1.5), Acceleration = Vector3.new(0, 2, 0), SpreadAngle = Vector2.new(180, 180),
		})
		local light = Instance.new("PointLight")
		light.Color = AMBER
		light.Brightness = 0.6
		light.Range = 10
		light.Parent = body
	end
end

-- Shared look of a transformation burst: fur tufts or feathers in the animal's colours
local function furBurst(kit, position: Vector3, animalId: string?, scale: number)
	local palette = PALETTES[animalId or ""] or PALETTES.Wolf
	local spec = ANIMALS[animalId or ""]
	local Vfx = kit.Vfx
	Vfx.burst(position, {
		colors = ColorSequence.new(palette.base, palette.light),
		lightEmission = 0,
		texture = SMOKE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * scale), NumberSequenceKeypoint.new(0.4, 0.35 * scale), NumberSequenceKeypoint.new(1, 0) }),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		lifetime = NumberRange.new(0.5, 1.0),
		speed = NumberRange.new(8 * scale, 16 * scale),
		drag = 5,
		acceleration = Vector3.new(0, -4, 0),
		count = 34,
	})
	Vfx.burst(position, {
		color = DUST,
		lightEmission = 0,
		texture = SMOKE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5 * scale), NumberSequenceKeypoint.new(1, 4 * scale) }),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		lifetime = NumberRange.new(0.6, 1.1),
		speed = NumberRange.new(4, 9),
		drag = 4,
		count = 12,
	})
	-- Birds shed a few real feathers that drift down
	if spec and spec.family == "Bird" then
		local count = if Vfx.reduced and Vfx.reduced() then 3 else 8
		for _ = 1, count do
			local feather = Vfx.part({
				Size = Vector3.new(0.14, 0.04, 0.5) * scale,
				CFrame = CFrame.new(position + Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5) * 2) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
				Color = if math.random() < 0.5 then palette.base else palette.light,
				Material = SMOOTH,
				Transparency = 0,
			})
			local drift = Vector3.new(math.random() - 0.5, -0.4 - math.random() * 0.6, math.random() - 0.5) * 5
			TweenService:Create(feather, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				CFrame = feather.CFrame * CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3) + drift,
			}):Play()
			Vfx.fade(feather, 1.6, { Transparency = 1 })
		end
	end
	Vfx.groundRing(position - Vector3.new(0, 2.6, 0), DUST, 2, 9 * scale, 0.5)
end

-- Appearance ----------------------------------------------------------------------------------------

-- The model's animal rig (so effects can make it bite, rear up, roll)
local rigs: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any
Shape.rigs = rigs

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

function Shape.appearance(kit)
	local model, root = kit.model, kit.root
	if not model or not root then
		return nil
	end
	local formId = kit.form
	if formId == "" then
		return humanLook(kit)
	end
	local form = Powers.abilityFor(POWER, formId, kit.degree)
	if not form or not form.form then
		return humanLook(kit)
	end
	local animalId = form.form.animal
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid then num((humanoid :: any).HipHeight, 0) else 0
	local ground = if hip > 0.1 then hip + root.Size.Y / 2 else 3
	local rig = Shape.build(animalId, { mode = "Weld", root = root, ground = ground, parent = model })
	rigs[model] = rig
	local reduced = kit.Vfx.reduced and kit.Vfx.reduced() or false
	animalExtras(rig, reduced)
	-- A fresh transformation grows in; a body that was already there (joining mid-match) doesn't
	local recent = os.clock() - (Shape.shiftedAt[model] or -math.huge) < 1
	if recent then
		rig:growIn(0.45, 0.32)
	end

	-- The animal fades whenever the body would (the veil, owner invisibility)
	local howHidden: () -> number = function()
		return 0
	end
	local function follow()
		if rig.alive then
			rig:setFade(howHidden())
		end
	end
	local restore
	restore, howHidden = hideHuman(model, follow)
	follow()

	-- Storm Eagle: lightning flickers between wingtips and body now and then
	local nextBolt = os.clock() + 1
	local groundCheck = 0
	local airborne = false
	local lastRoot = root.Position
	local connection = RunService.Heartbeat:Connect(function(dt)
		if not rig.alive or not root.Parent then
			return
		end
		local camera = workspace.CurrentCamera
		local far = camera ~= nil and (camera.CFrame.Position - root.Position).Magnitude > 160
		if far and math.random() > 0.2 then
			return
		end
		-- Velocity from movement (works the same for every character on this screen)
		local position = root.Position
		local velocity = if dt > 0 then (position - lastRoot) / dt else Vector3.zero
		lastRoot = position
		if velocity.Magnitude > 200 then
			velocity = Vector3.zero
		end
		groundCheck -= dt
		if groundCheck <= 0 then
			groundCheck = 0.08
			groundParams.FilterDescendantsInstances = { model }
			local hit = workspace:Raycast(position, Vector3.new(0, -(ground + 1.4), 0), groundParams)
			airborne = hit == nil
		end
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		rig:step(math.min(dt, 0.1), speed, airborne, velocity.Y)
		if animalId == "StormEagle" and os.clock() > nextBolt and kit.near(position, 90) then
			nextBolt = os.clock() + 0.9 + math.random() * 1.6
			local wing = rig.bones[if math.random() < 0.5 then "WingL2" else "WingR2"]
			if wing and rig.fade < 0.5 then
				kit.Vfx.lightning(wing.part.Position, position + Vector3.new(0, 0.3, 0), STORM, 4, 0.12)
			end
		end
	end)

	return function()
		connection:Disconnect()
		restore()
		if rigs[model] == rig then
			rigs[model] = nil
		end
		-- Shrink away under the burst instead of vanishing
		if model.Parent and rig.alive then
			local shrink = rig
			shrink.growing = { from = 1, start = os.clock(), length = 0.01 }
			task.spawn(function()
				local started = os.clock()
				while shrink.alive and os.clock() - started < 0.18 do
					shrink.grow = lerp(1, 0.35, (os.clock() - started) / 0.18)
					shrink:setFade(math.max(shrink.fade, (os.clock() - started) / 0.18))
					shrink:apply(true)
					task.wait()
				end
				shrink:destroy()
			end)
		else
			rig:destroy()
		end
	end
end

-- When this client last saw each model change form (so its new body grows in)
Shape.shiftedAt = setmetatable({}, { __mode = "k" }) :: any

-- Casts: the animal moves the moment an attack starts -----------------------------------------------

-- ability -> rig action and which phase lengths it spans
local ACTIONS: { [string]: { string } } = {
	WolfBite = { "Bite", "strike" },
	WolfPounce = { "Crouch", "startup" },
	HawkTalon = { "Talon", "strike" },
	HawkDive = { "Crouch", "startup" },
	BearMaul = { "Maul", "strike" },
	BearSlam = { "Rear", "startup" },
	CheetahSwipe = { "Swipe", "strike" },
	CheetahBurst = { "Crouch", "startup" },
	CrocSnap = { "Snap", "strike" },
	DeathRoll = { "Gape", "startup" },
	CinderRake = { "Talon", "strike" },
	PhoenixNova = { "Rise", "startup" },
	PrimalAscendancy = { "Howl", "startup" },
}

-- The human's crouch before a transformation, and the call of Primal Ascendancy
local registered = false
local function registerPoses(Poser)
	if registered then
		return
	end
	registered = true
	if Poser.registerSequence then
		Poser.registerSequence("ShiftCrouch", {
			{ t = 0, pose = { Torso = { 0, 0, 0 } } },
			{ t = 0.25, pose = { Torso = { 28, 0, 0 }, Neck = { 18, 0, 0 }, RightShoulder = { 40, 0, 30 }, LeftShoulder = { 40, 0, -30 }, RightElbow = { 60, 0, 0 }, LeftElbow = { 60, 0, 0 }, RightHip = { 45, 0, 0 }, LeftHip = { 20, 0, 0 } }, easing = "Out" },
			{ t = 0.4, pose = { Torso = { 34, 0, 0 }, Neck = { -10, 0, 0 }, RightShoulder = { 20, 0, 50 }, LeftShoulder = { 20, 0, -50 }, RightHip = { 50, 0, 0 }, LeftHip = { 25, 0, 0 } }, easing = "In" },
		}, { startup = 0.4 })
	end
	Poser.register("ShiftHunch", { Torso = { 30, 0, 0 }, Neck = { 18, 0, 0 }, RightShoulder = { 40, 0, 30 }, LeftShoulder = { 40, 0, -30 }, RightElbow = { 60, 0, 0 }, LeftElbow = { 60, 0, 0 } })
	Poser.register("PrimalCall", { Torso = { -14, 0, 0 }, Neck = { -35, 0, 0 }, RightShoulder = { 150, 0, -40 }, LeftShoulder = { 150, 0, 40 }, RightElbow = { 25, 0, 0 }, LeftElbow = { 25, 0, 0 } })
end
local function humanPose(kit, name: string, duration: number)
	local Poser = kit.Poser
	registerPoses(Poser)
	if name == "ShiftHunch" and Poser.sequence and Poser.Sequences and Poser.Sequences.ShiftCrouch then
		Poser.sequence(kit.model, "ShiftCrouch", 0.4 / math.max(0.1, duration))
		return
	end
	Poser.play(kit.model, name, math.min(0.12, duration * 0.4), math.max(0.05, duration * 0.6), 0.15)
end

local function castAction(kit)
	local model = kit.model
	if not model then
		return
	end
	local abilityId = kit.data.ability
	if typeof(abilityId) ~= "string" then
		return
	end
	local def = kit.ability(abilityId)
	local rig = rigs[model]
	local startup = num(kit.data.startup, def and def.startup or 0.2)
	if def and def.kind == "Form" then
		-- Changing back is instant; changing into something shows the crouch
		if kit.form ~= abilityId then
			if rig then
				rig:act("Crouch", startup + 0.1)
			else
				humanPose(kit, "ShiftHunch", startup)
			end
		end
		return
	end
	local entry = ACTIONS[abilityId]
	if rig and entry then
		local length = if entry[2] == "startup" then startup + 0.05 else startup + num(kit.data.active, def and def.active or 0.1) + 0.18
		local side = if abilityId == "BearMaul" then (if os.clock() % 2 < 1 then 1 else -1) else 1
		rig:act(entry[1], length, { side = side })
	elseif abilityId == "PrimalAscendancy" then
		humanPose(kit, "PrimalCall", startup)
	end
end

function Shape.onCast(kit)
	castAction(kit)
end

Shape.predict = {}
for abilityId, ability in Powers.get(POWER).abilities do
	if not ability.basicOnly then
		Shape.predict[abilityId] = castAction
	end
end

-- Effects -----------------------------------------------------------------------------------------

local function chestOf(kit): Vector3?
	local rig = kit.model and rigs[kit.model]
	if rig then
		return rig.bones.Body.part.Position
	end
	return if kit.root then kit.root.Position else nil
end

local function headOf(kit): Vector3?
	local rig = kit.model and rigs[kit.model]
	if rig and rig.bones.Head then
		return rig.bones.Head.part.Position
	end
	return if kit.root then kit.root.Position + Vector3.new(0, 1.5, 0) else nil
end

local function feet(kit): Vector3
	return if kit.root then kit.root.Position - Vector3.new(0, 2.9, 0) else Vector3.zero
end

local function facing(kit): Vector3
	local direction = flat(kit.data.direction)
	if direction then
		return direction
	end
	return if kit.root then (flat(kit.root.CFrame.LookVector) or Vector3.new(0, 0, -1)) else Vector3.new(0, 0, -1)
end

local function targetRoot(value: any): BasePart?
	if typeof(value) == "Instance" and value:IsA("Model") then
		local root = value:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root
		end
	end
	return nil
end

local function act(kit, name: string, length: number, data: { [string]: any }?)
	local rig = kit.model and rigs[kit.model]
	if rig then
		rig:act(name, length, data)
	end
end

-- Gathering motes drawn in toward the body (the anticipation of every change)
local function gather(kit, center: Vector3, color: Color3, duration: number, count: number)
	local Vfx = kit.Vfx
	local total = if Vfx.reduced and Vfx.reduced() then math.ceil(count / 3) else count
	for _ = 1, total do
		local offset = Vector3.new(math.random() - 0.5, math.random() * 0.8 - 0.2, math.random() - 0.5).Unit * (2.5 + math.random() * 2)
		local mote = Vfx.part({ Size = Vector3.one * 0.14, CFrame = CFrame.new(center + offset), Color = color, Transparency = 0.6 })
		TweenService:Create(mote, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(center), Transparency = 0.05, Size = Vector3.one * 0.08 }):Play()
		task.delay(duration, function()
			mote:Destroy()
		end)
	end
end

function fx.ShiftBegin(kit)
	local center = chestOf(kit)
	if not center then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 0.4), 0.05, 1.5)
	gather(kit, center, AMBER, duration, 14)
	kit.Vfx.groundRing(feet(kit) + Vector3.new(0, 0.08, 0), AMBER, 8, 2.5, duration)
	kit.Vfx.glow(center, AMBER, 8, 1, duration)
	if not rigs[kit.model] then
		humanPose(kit, "ShiftHunch", duration)
	end
end

function fx.Shift(kit)
	local model = kit.model
	if not model then
		return
	end
	Shape.shiftedAt[model] = os.clock()
	local center = chestOf(kit)
	if not center then
		return
	end
	local animalId = if typeof(kit.data.animal) == "string" then kit.data.animal else nil
	local spec = ANIMALS[animalId or ""]
	local big = spec ~= nil and (spec.heavy == true or spec.family == "Croc")
	furBurst(kit, center, animalId, if big then 1.3 else 1)
	kit.Vfx.glow(center, AMBER, 12, 2, 0.18)
	kit.Vfx.sound(if big then "HeavyHit" else "Dodge", center)
	kit.shake(if big then 1.4 else 0.7, 0.2, center)
	-- The new body arrives a frame later (the form attribute): make sure it grows in
	task.defer(function()
		local rig = rigs[model]
		if rig and not rig.growing and rig.grow == 1 and rig.anim.t < 0.2 then
			rig:growIn(0.45, 0.32)
		end
	end)
end

function fx.ShiftBroken(kit)
	local center = chestOf(kit)
	if not center then
		return
	end
	kit.Vfx.burst(center, {
		color = AMBER, lightEmission = 0.3, texture = SMOKE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2) }),
		transparency = NumberSequence.new(0.5, 1), lifetime = NumberRange.new(0.4, 0.8), speed = NumberRange.new(2, 5), drag = 3, count = 10,
	})
	kit.Vfx.sparks(center, AMBER, 6, 10)
end

function fx.Unshift(kit)
	local center = chestOf(kit)
	if not center then
		return
	end
	local animalId = if typeof(kit.data.animal) == "string" then kit.data.animal else nil
	furBurst(kit, center, animalId, 0.9)
	if kit.data.reason == "Exhausted" then
		-- Spent: a grey sigh of smoke instead of an amber flash
		kit.Vfx.burst(center + Vector3.new(0, 1, 0), {
			color = rgb(120, 116, 110), lightEmission = 0, texture = SMOKE,
			size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) }),
			transparency = NumberSequence.new(0.4, 1), lifetime = NumberRange.new(0.8, 1.4), speed = NumberRange.new(1, 3),
			acceleration = Vector3.new(0, 3, 0), drag = 2, count = 10,
		})
		if kit.model then
			humanPose(kit, "ShiftHunch", 0.5)
		end
	else
		kit.Vfx.glow(center, AMBER, 10, 1.4, 0.15)
	end
	kit.Vfx.sound("Dodge", center)
end

-- A quick bite or claw arc in front of the head
local function slashAt(kit, color: Color3, radius: number, tilt: number, delay: number, heavy: boolean?)
	task.delay(delay, function()
		local head = headOf(kit)
		if not head or not kit.root then
			return
		end
		local forward = facing(kit)
		local origin = CFrame.lookAt(head, head + forward)
		kit.Vfx.slash(origin * CFrame.new(0, 0, radius * 0.25), color, radius, tilt, if heavy then 0.25 else 0.16)
		kit.Vfx.sound(if heavy then "HeavySwing" else "LightSwing", head)
	end)
end

function fx.Bite(kit)
	local duration = num(kit.data.duration, 0.11)
	local finisher = kit.data.finisher == true
	slashAt(kit, if kit.degree >= 3 then PALETTES.SpectralWolf.light else BONE, if finisher then 2.6 else 1.9, 90, duration, finisher)
	if finisher then
		task.delay(duration, function()
			local head = headOf(kit)
			if head then
				kit.Vfx.sparks(head + facing(kit) * 1.5, BONE, 8, 14)
			end
		end)
	end
end

function fx.PounceCrouch(kit)
	local duration = num(kit.data.duration, 0.28)
	act(kit, "Crouch", duration + 0.03)
	kit.Vfx.groundRing(feet(kit) + Vector3.new(0, 0.08, 0), DUST, 1, 4, duration)
end

local function dustKick(kit, scale: number)
	local position = feet(kit) + Vector3.new(0, 0.4, 0)
	kit.Vfx.burst(position, {
		color = DUST, lightEmission = 0, texture = SMOKE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 * scale), NumberSequenceKeypoint.new(1, 2.6 * scale) }),
		transparency = NumberSequence.new(0.45, 1), lifetime = NumberRange.new(0.5, 0.9), speed = NumberRange.new(3, 7),
		spread = Vector2.new(30, 180), drag = 4, count = 10,
	})
end

function fx.Pounce(kit)
	local duration = num(kit.data.duration, 0.22)
	act(kit, "Leap", duration + 0.1)
	dustKick(kit, 1)
	if kit.model then
		kit.Vfx.afterimage(kit.model, if kit.degree >= 3 then PALETTES.SpectralWolf.base else DUST)
	end
end

function fx.PounceBite(kit)
	act(kit, "Bite", 0.3)
	local target = targetRoot(kit.data.target)
	local head = headOf(kit)
	if head then
		slashAt(kit, if kit.data.spirit then PALETTES.SpectralWolf.light else BONE, 2.6, 80, 0, true)
	end
	if target then
		kit.Vfx.sparks(target.Position, BONE, 10, 18)
		kit.shake(1, 0.15, target.Position)
	end
end

-- Spectral Wolf: a spirit wolf runs at the marked target's side until the mark ends
function fx.SpiritWolf(kit)
	local target = targetRoot(kit.data.target)
	if not target then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 4), 0.2, 8)
	local side = if math.random() < 0.5 then -1 else 1
	local spirit = Shape.build("SpectralWolf", { mode = "Anchored", frame = target.CFrame * CFrame.new(3.2 * side, -3, 1.5), ghost = PALETTES.SpectralWolf.light, ghostSee = 0.5, parent = workspace.CurrentCamera, scale = 0.85 })
	spirit:growIn(0.3, 0.3)
	local last = target.Position
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not target.Parent or not spirit.alive then
			return
		end
		local position = target.Position
		local speed = if dt > 0 then Vector3.new(position.X - last.X, 0, position.Z - last.Z).Magnitude / dt else 0
		last = position
		local look = flat(target.CFrame.LookVector) or Vector3.new(0, 0, -1)
		local goal = CFrame.lookAt(position, position + look) * CFrame.new(3.2 * side, -3, 1.5 + math.sin(os.clock() * 2) * 0.3)
		spirit.frame = spirit.frame:Lerp(goal, math.min(1, dt * 8))
		local age = os.clock() - started
		spirit:setFade(math.max(0.5, if age > duration - 0.4 then 0.5 + (age - (duration - 0.4)) / 0.4 * 0.5 else 0.5))
		spirit:step(math.min(dt, 0.1), math.max(speed, 3), false, 0)
	end)
	kit.Vfx.sound("Parry", target)
	kit.keep(function()
		connection:Disconnect()
		if spirit.alive then
			kit.Vfx.burst(spirit.bones.Body.part.Position, {
				color = PALETTES.SpectralWolf.light, lightEmission = 0.6, texture = SMOKE,
				size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2) }),
				transparency = NumberSequence.new(0.5, 1), lifetime = NumberRange.new(0.5, 0.9), speed = NumberRange.new(1, 3), drag = 2, count = 10,
			})
			spirit:destroy()
		end
	end)
end

function fx.Talon(kit)
	local duration = num(kit.data.duration, 0.1)
	slashAt(kit, if kit.degree >= 3 then STORM else BONE, 2.2, -60, duration)
end

function fx.DiveWindup(kit)
	local duration = num(kit.data.duration, 0.25)
	act(kit, "Crouch", duration + 0.03)
	local center = chestOf(kit)
	if center and kit.data.lightning == true then
		gather(kit, center, STORM, duration, 10)
		kit.Vfx.glow(center, STORM, 10, 1.2, duration)
	end
end

function fx.Dive(kit)
	local duration = num(kit.data.duration, 0.3)
	act(kit, "Dive", duration + 0.1)
	if kit.model then
		kit.Vfx.afterimage(kit.model, if kit.data.lightning == true then STORM else DUST)
	end
	local center = chestOf(kit)
	if center and kit.data.lightning == true then
		kit.Vfx.lightning(center + Vector3.new(0, 14, 0), center, STORM, 6, 0.18)
	end
end

function fx.DiveImpact(kit)
	local position = vec(kit.data.position) or feet(kit)
	local radius = math.clamp(num(kit.data.radius, 5), 1, 20)
	local storm = kit.data.lightning == true
	act(kit, "Talon", 0.3)
	kit.Vfx.groundRing(position + Vector3.new(0, 0.1, 0), if storm then STORM else DUST, 2, radius * 2, 0.4)
	dustKick(kit, 1.2)
	if storm then
		for _ = 1, 3 do
			local offset = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * radius * 1.4
			kit.Vfx.lightning(position + offset + Vector3.new(0, 18, 0), position + offset, STORM, 7, 0.2)
		end
		kit.Vfx.cracks(position, radius * 0.8, STORM, 6, 1.2)
		kit.Vfx.glow(position + Vector3.new(0, 2, 0), STORM, radius * 3, 3, 0.18)
		if kit.Vfx.intense() and kit.near(position, 40) then
			kit.Vfx.screenFlash(STORM, 0.15, 0.15)
		end
	end
	kit.Vfx.sound("HeavyHit", position)
	kit.shake(if storm then 2 else 1.2, 0.25, position)
end

function fx.Maul(kit)
	local duration = num(kit.data.duration, 0.18)
	local side = num(kit.data.side, 1)
	act(kit, "Maul", duration + 0.26, { side = side })
	slashAt(kit, BONE, 3, if side > 0 then 30 else -30, duration, true)
end

function fx.SlamRear(kit)
	local duration = num(kit.data.duration, 0.55)
	act(kit, "Rear", duration + 0.02)
	local center = chestOf(kit)
	if center and kit.data.runes == true then
		gather(kit, center, AMBER, duration, 12)
		kit.Vfx.glow(center, AMBER, 12, 1.5, duration)
	end
end

function fx.Slam(kit)
	local position = vec(kit.data.position) or feet(kit)
	local radius = math.clamp(num(kit.data.radius, 7), 1, 20)
	local wave = kit.data.shockwave
	act(kit, "Slam", 0.5)
	local Vfx = kit.Vfx
	Vfx.groundRing(position + Vector3.new(0, 0.1, 0), DUST, 2, radius * 2.1, 0.45)
	Vfx.shockwave(position + Vector3.new(0, 0.8, 0), DUST, 2, radius * 1.4, 0.3)
	Vfx.cracks(position, radius * 0.8, if wave then AMBER else BARK, if wave then 10 else 6, 1.4)
	Vfx.debris(position, if wave then 10 else 6, rgb(92, 84, 74), Enum.Material.Slate, 38)
	dustKick(kit, 1.6)
	Vfx.sound("HeavyHit", position)
	kit.shake(2.2, 0.35, position)
	if typeof(wave) == "number" then
		local reach = math.clamp(wave, 2, 30)
		task.delay(0.12, function()
			Vfx.groundRing(position + Vector3.new(0, 0.15, 0), AMBER, radius * 1.5, reach * 2.1, 0.5)
			Vfx.ring(CFrame.new(position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(math.rad(90), 0, 0), radius, AMBER, 0.35, 0.45, reach)
			Vfx.glow(position + Vector3.new(0, 1, 0), AMBER, reach * 1.5, 2, 0.2)
		end)
	end
end

function fx.Swipe(kit)
	local duration = num(kit.data.duration, 0.08)
	slashAt(kit, BONE, 2, if math.random() < 0.5 then 40 else -40, duration)
end

function fx.BurstCrouch(kit)
	local duration = num(kit.data.duration, 0.14)
	act(kit, "Crouch", duration + 0.03)
end

function fx.Burst(kit)
	local duration = num(kit.data.duration, 0.32)
	act(kit, "Leap", duration + 0.1)
	dustKick(kit, 1)
	local model = kit.model
	if model then
		-- A few afterimages along the sprint
		for index = 0, 2 do
			task.delay(index * duration / 3, function()
				if model.Parent then
					kit.Vfx.afterimage(model, if kit.data.pounce == true then rgb(70, 66, 80) else DUST)
				end
			end)
		end
	end
end

function fx.BurstHit(kit)
	act(kit, "Bite", 0.3)
	local target = targetRoot(kit.data.target)
	if target then
		kit.Vfx.sparks(target.Position, BONE, 10, 18)
		kit.Vfx.sound("Hit", target.Position)
		kit.shake(1, 0.15, target.Position)
	end
end

function fx.Snap(kit)
	local duration = num(kit.data.duration, 0.2)
	slashAt(kit, rgb(228, 222, 200), 2.2, 0, duration, true)
end

function fx.JawsOpen(kit)
	local duration = num(kit.data.duration, 0.28)
	act(kit, "Gape", duration + 0.1)
end

function fx.JawsWhiff(kit)
	act(kit, "Snap", 0.3)
end

function fx.RollCatch(kit)
	local hold = math.clamp(num(kit.data.hold, 1.5), 0.1, 3)
	act(kit, "Roll", hold)
	local target = targetRoot(kit.data.target)
	if target then
		kit.Vfx.sound("HeavyHit", target.Position)
		kit.Vfx.sparks(target.Position, rgb(228, 222, 200), 8, 12)
		if kit.data.target:IsA("Model") then
			kit.Poser.play(kit.data.target, "Stagger", 0.05, hold, 0.2)
		end
	end
	dustKick(kit, 1.3)
end

function fx.RollBroken(kit)
	act(kit, "Flinch", 0.4)
	local target = targetRoot(kit.data.target)
	if target then
		kit.Vfx.shockwave(target.Position, BONE, 1, 6, 0.25)
	end
end

function fx.RollFinish(kit)
	act(kit, "Snap", 0.35)
	local target = targetRoot(kit.data.target)
	if target then
		kit.Vfx.groundRing(target.Position - Vector3.new(0, 2.8, 0), DUST, 2, 8, 0.4)
		kit.Vfx.debris(target.Position - Vector3.new(0, 2.5, 0), 5, rgb(92, 84, 74), Enum.Material.Ground, 25)
		kit.Vfx.sound("HeavyHit", target.Position)
		kit.shake(1.6, 0.25, target.Position)
	end
end

function fx.Cinder(kit)
	local duration = num(kit.data.duration, 0.1)
	slashAt(kit, FLAME, 2.2, -50, duration)
	task.delay(duration, function()
		local head = headOf(kit)
		if head then
			kit.Vfx.burst(head + facing(kit) * 2, {
				texture = FIRE, colors = ColorSequence.new(rgb(255, 210, 120), EMBER), lightEmission = 1,
				size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
				lifetime = NumberRange.new(0.25, 0.5), speed = NumberRange.new(4, 9), drag = 4, count = 10,
			})
		end
	end)
end

function fx.NovaRise(kit)
	local duration = num(kit.data.duration, 0.4)
	act(kit, "Rise", duration + 0.15)
	local center = chestOf(kit)
	if center then
		gather(kit, center, FLAME, duration, 14)
		kit.Vfx.groundRing(feet(kit) + Vector3.new(0, 0.1, 0), FLAME, 2, 6, duration)
		kit.Vfx.glow(center, FLAME, 14, 2, duration)
	end
end

function fx.Nova(kit)
	local position = vec(kit.data.position) or chestOf(kit)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 10), 1, 25)
	local Vfx = kit.Vfx
	act(kit, "Nova", 0.5)
	Vfx.orb(position, rgb(255, 214, 140), 2, radius * 0.9, 0.22)
	Vfx.ring(CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0), 1.5, FLAME, 0.5, 0.45, radius)
	Vfx.shockwave(position, EMBER, 2, radius * 2, 0.35)
	Vfx.burst(position, {
		texture = FIRE, colors = ColorSequence.new(rgb(255, 220, 140), EMBER), lightEmission = 1,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) }),
		transparency = NumberSequence.new(0.1, 1), lifetime = NumberRange.new(0.4, 0.9), speed = NumberRange.new(radius * 1.2, radius * 2), drag = 4, count = 40,
	})
	Vfx.burst(position, {
		texture = SMOKE, color = rgb(70, 52, 44), lightEmission = 0,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) }),
		transparency = NumberSequence.new(0.55, 1), lifetime = NumberRange.new(1, 1.6), speed = NumberRange.new(2, 6), acceleration = Vector3.new(0, 3, 0), drag = 2, count = 12,
	})
	Vfx.glow(position, FLAME, radius * 2.5, 3, 0.2)
	if Vfx.intense() and kit.near(position, 40) then
		Vfx.screenFlash(FLAME, 0.12, 0.15)
	end
	Vfx.sound("HeavyHit", position)
	kit.shake(1.8, 0.3, position)
end

-- Primal Ascendancy ------------------------------------------------------------------------------------

local function spiritRise(kit, animalId: string, frame: CFrame, scale: number, life: number, color: Color3)
	local spirit = Shape.build(animalId, { mode = "Anchored", frame = frame, ghost = color, ghostSee = 0.45, parent = workspace.CurrentCamera, scale = scale })
	spirit:growIn(0.2, 0.35)
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not spirit.alive then
			connection:Disconnect()
			return
		end
		local age = os.clock() - started
		spirit:setFade(if age > life - 0.25 then math.min(1, 0.45 + (age - (life - 0.25)) / 0.25 * 0.55) else 0.45)
		spirit:step(math.min(dt, 0.1), 0, spirit.spec.family == "Bird", 0)
		if age >= life then
			connection:Disconnect()
			spirit:destroy()
		end
	end)
	return spirit
end

function fx.AscendWindup(kit)
	local root = kit.root
	if not root then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 1.25), 0.2, 3)
	local spirits = if typeof(kit.data.spirits) == "table" then kit.data.spirits else { "Wolf", "Hawk", "Bear" }
	local apex = if typeof(kit.data.apex) == "string" and ANIMALS[kit.data.apex] then kit.data.apex else "Bear"
	local forward = facing(kit)
	local base = CFrame.lookAt(feet(kit) + Vector3.new(0, 3, 0), feet(kit) + Vector3.new(0, 3, 0) + forward)
	local reduced = kit.Vfx.reduced and kit.Vfx.reduced()
	act(kit, "Howl", duration)
	kit.Vfx.cone(CFrame.lookAt(feet(kit) + Vector3.new(0, 0.1, 0), feet(kit) + Vector3.new(0, 0.1, 0) + forward), math.clamp(num(kit.data.range, 16), 4, 30), 90, AMBER, duration)
	-- Wolf, hawk and bear spirits rise around the caster one after another
	if not reduced then
		local spots = { CFrame.new(-4, 0, 1.5) * ang(0, -25, 0), CFrame.new(4, 1.5, 1.5) * ang(0, 25, 0), CFrame.new(0, 0, 4) }
		for index, animalId in spirits do
			if typeof(animalId) == "string" and ANIMALS[animalId] and index <= 3 then
				task.delay((index - 1) * duration * 0.2, function()
					if root.Parent then
						local spirit = spiritRise(kit, animalId, base * spots[index], 0.8, duration * 0.75 - (index - 1) * duration * 0.2, AMBER)
						spirit:act(if spirit.spec.family == "Bird" then "Rise" else "Howl", 2)
						kit.Vfx.sound("Parry", root)
					end
				end)
			end
		end
	end
	-- Then the apex beast towers up behind
	task.delay(duration * 0.45, function()
		if not root.Parent then
			return
		end
		local frame = base * CFrame.new(0, 0, 3.5)
		local beast = spiritRise(kit, apex, frame, 2.3, duration * 0.55 + 0.6, AMBER)
		beast:act("Rear", duration * 0.55 + 0.05)
		Shape.apexOf[kit.model or root] = { rig = beast, frame = frame, forward = forward }
		kit.Vfx.glow(root.Position + Vector3.new(0, 5, 0), AMBER, 20, 1.5, duration * 0.55)
	end)
	gather(kit, root.Position, AMBER, duration, 18)
end
Shape.apexOf = setmetatable({}, { __mode = "k" }) :: any

function fx.AscendFizzle(kit)
	local key = kit.model or kit.root
	local apex = key and Shape.apexOf[key]
	if apex and apex.rig.alive then
		apex.rig:setFade(0.9)
	end
	local center = chestOf(kit)
	if center then
		kit.Vfx.burst(center, {
			color = AMBER, lightEmission = 0.3, texture = SMOKE,
			size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) }),
			transparency = NumberSequence.new(0.5, 1), lifetime = NumberRange.new(0.5, 1), speed = NumberRange.new(2, 5), drag = 3, count = 14,
		})
	end
end

function fx.AscendStrike(kit)
	local origin = vec(kit.data.origin) or feet(kit)
	local direction = flat(kit.data.direction) or facing(kit)
	local range = math.clamp(num(kit.data.range, 16), 2, 40)
	local arc = math.clamp(num(kit.data.arc, 100), 10, 180)
	local Vfx = kit.Vfx
	local key = kit.model or kit.root
	local apex = key and Shape.apexOf[key]
	if apex and apex.rig.alive then
		-- The beast crashes down onto the ground in front
		local rig = apex.rig
		rig:act("Slam", 0.6)
		local from = rig.frame
		local to = from + direction * (range * 0.45)
		local started = os.clock()
		task.spawn(function()
			while rig.alive and os.clock() - started < 0.16 do
				local u = (os.clock() - started) / 0.16
				rig.frame = from:Lerp(to, u * u)
				task.wait()
			end
			if rig.alive then
				rig.frame = to
			end
		end)
	end
	local center = origin + direction * range * 0.55
	Vfx.cone(CFrame.lookAt(origin + Vector3.new(0, 0.15, 0), origin + Vector3.new(0, 0.15, 0) + direction), range, arc, AMBER, 0.5)
	Vfx.cracks(center, range * 0.5, AMBER, 14, 2)
	Vfx.groundRing(center + Vector3.new(0, 0.1, 0), AMBER, 3, range * 1.6, 0.5)
	Vfx.shockwave(center + Vector3.new(0, 1, 0), DUST, 3, range * 1.2, 0.4)
	Vfx.debris(center, 14, rgb(92, 84, 74), Enum.Material.Slate, 55)
	Vfx.burst(center, {
		color = DUST, lightEmission = 0, texture = SMOKE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 6) }),
		transparency = NumberSequence.new(0.35, 1), lifetime = NumberRange.new(0.9, 1.5), speed = NumberRange.new(range * 0.8, range * 1.4), drag = 4, count = 26,
	})
	if kit.data.fire == true then
		Vfx.ring(CFrame.new(center + Vector3.new(0, 0.6, 0)) * CFrame.Angles(math.rad(90), 0, 0), 2, FLAME, 0.6, 0.6, range * 0.7)
		Vfx.burst(center, {
			texture = FIRE, colors = ColorSequence.new(rgb(255, 220, 140), EMBER), lightEmission = 1,
			size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 0) }),
			lifetime = NumberRange.new(0.4, 0.9), speed = NumberRange.new(range, range * 1.6), drag = 4, count = 34,
		})
	end
	Vfx.glow(center + Vector3.new(0, 3, 0), AMBER, range * 2, 3, 0.2)
	if Vfx.intense() and kit.near(center, 60) then
		Vfx.screenFlash(AMBER, 0.2, 0.2)
	end
	Vfx.sound("HeavyHit", center)
	Vfx.sound("GuardBreak", center)
	kit.shake(3.2, 0.5, center)
	act(kit, "Bite", 0.4)
end

-- Fighting System v2 moves and getting hit: the animal reacts too --------------------------------------

local watching = false
local function watchCombat()
	if watching then
		return
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("CombatEvent")
	if not event or not event:IsA("RemoteEvent") then
		return
	end
	watching = true
	event.OnClientEvent:Connect(function(kind, data)
		if typeof(data) ~= "table" then
			return
		end
		if kind == Protocol.CombatEvent.Hit then
			local rig = rigs[data.victim]
			if rig and data.result == "Hit" then
				rig:act("Flinch", 0.3)
			end
		elseif kind == Protocol.CombatEvent.Attack then
			local rig = rigs[data.attacker]
			if rig then
				local startup = num(data.startup, 0.15)
				local bird = rig.spec.family == "Bird"
				rig:act(if bird then "Talon" else "Bite", startup + num(data.active, 0.1) + 0.15)
			end
		elseif kind == Protocol.CombatEvent.Dodge then
			local rig = rigs[data.fighter]
			if rig then
				rig:act(if rig.spec.family == "Bird" then "Crouch" else "Leap", num(data.duration, 0.2) + 0.1)
			end
		end
	end)
end

local baseAppearance = Shape.appearance
Shape.appearance = function(kit)
	watchCombat()
	return baseAppearance(kit)
end

return Shape
