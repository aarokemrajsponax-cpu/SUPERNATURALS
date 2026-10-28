-- How Corruption looks (PROGRAMME ECLIPSE). Not shadow magic: black glass
-- that reflects nothing in the room, hairline fractures with ultraviolet light
-- leaking out of them, space that pops inside out, static that eats things,
-- floors that come apart into tilting plates. One signature pair (void black
-- and ultraviolet) with the cold silver of a reflection that has no source.
--
-- The persistent look is the visual overwrite: the server's Phase attribute
-- (degree plus meter, 1 in the final form) decides how much of the body is
-- fractured, patched, shelled and silhouetted. Degree 1 is mostly the original
-- body with fine cracks and dark eyes; Degree 2 spreads glossy black patches and
-- a distortion field; Degree 3 is nearly opaque with orbiting fragments and dark
-- flames; the final form is a featureless silhouette with two points of light.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Attribute = Protocol.Attribute
local DEF = Powers.get("Corruption")
local FORM_ATTRIBUTE = DEF.attributes.form
local LOCK_ATTRIBUTE = DEF.attributes.lock
local MARK_ATTRIBUTE = Attribute.StatusPrefix .. "Mark"

local Corruption = {}
local fx = {}
Corruption.fx = fx
Corruption.projectiles = {}
Corruption.predict = {}

local rgb = Color3.fromRGB
-- The black (never pure black: it has to catch reflections)
local VOID = rgb(12, 10, 17)
-- Black where light grazes it
local INK = rgb(34, 28, 46)
-- Ultraviolet: light leaking out of the fractures
local GLINT = rgb(150, 112, 255)
-- The reflection with no source
local PALE = rgb(222, 218, 240)
-- Neutral static
local STATIC = rgb(112, 108, 124)

local GLASS = Enum.Material.Glass
local NEON = Enum.Material.Neon
local PLASTIC = Enum.Material.SmoothPlastic
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local UP = Vector3.new(0, 1, 0)

local random = Random.new()

-- Small helpers ------------------------------------------------------------------------------

local function num(value: any, fallback: number): number
	return if typeof(value) == "number" and value == value and math.abs(value) < 1e6 then value else fallback
end

local function vec(value: any): Vector3?
	if typeof(value) == "Vector3" and value.X == value.X and value.Y == value.Y and value.Z == value.Z and value.Magnitude < 1e6 then
		return value
	end
	return nil
end

local function flatUnit(value: any, fallback: Vector3): Vector3
	local v = vec(value)
	if v then
		local f = Vector3.new(v.X, 0, v.Z)
		if f.Magnitude > 0.01 then
			return f.Unit
		end
	end
	return fallback
end

local function asModel(value: any): Model?
	return if typeof(value) == "Instance" and value:IsA("Model") and value.Parent ~= nil then value else nil
end

local function jitter(range: number): number
	return (random:NextNumber() * 2 - 1) * range
end

local function turned(direction: Vector3, degrees: number): Vector3
	return CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(direction)
end

local function findPart(model: Model, names: { string }): BasePart?
	for _, name in names do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function feet(kit): Vector3?
	return if kit.root then kit.root.Position - Vector3.new(0, 2.9, 0) else nil
end

local function facing(kit): Vector3
	return if kit.root then flatUnit(kit.root.CFrame.LookVector, Vector3.new(0, 0, -1)) else Vector3.new(0, 0, -1)
end

local function hand(model: Model?, left: boolean?): BasePart?
	if not model then
		return nil
	end
	if left then
		return findPart(model, { "LeftHand", "LeftLowerArm", "Left Arm", "UpperTorso", "Torso" })
	end
	return findPart(model, { "RightHand", "RightLowerArm", "Right Arm", "UpperTorso", "Torso" })
end

-- Effect parts live in their own folder under the camera (local, never replicated)
local folder: Folder? = nil
local function container(): Instance
	if folder and folder.Parent then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "SNCorruptionFx"
	made.Parent = workspace.CurrentCamera or workspace
	folder = made
	return made
end

local function piece(className: string, props: { [string]: any }): BasePart
	local part = Instance.new(className) :: BasePart
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = props.Material or GLASS
	part.Color = props.Color or VOID
	part.Reflectance = props.Reflectance or 0
	part.Transparency = props.Transparency or 0
	if props.Shape and part:IsA("Part") then
		part.Shape = props.Shape
	end
	part.Size = props.Size or Vector3.one
	part.CFrame = props.CFrame or CFrame.new()
	part.Parent = container()
	Debris:AddItem(part, props.Life or 6)
	return part
end

local function tween(instance: Instance, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	TweenService:Create(instance, TweenInfo.new(math.max(0.01, duration), style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal):Play()
end

-- Shows a part after `delay`, holds it, then lets it go slowly (fast in, slow out)
local function stage(part: BasePart, delay: number, shown: number, hold: number, out: number, goal: { [string]: any }?)
	Debris:AddItem(part, delay + hold + out + 0.3)
	task.delay(delay, function()
		if not part.Parent then
			return
		end
		part.Transparency = shown
		task.delay(hold, function()
			if part.Parent then
				tween(part, out, goal or { Transparency = 1 })
			end
		end)
	end)
end

local function reduced(kit): boolean
	return kit.Vfx.reduced()
end

local function scaled(kit, count: number): number
	return if reduced(kit) then math.max(1, math.ceil(count / 3)) else count
end

-- Building blocks ----------------------------------------------------------------------------

-- A jagged fracture racing across the floor: black glass seams, tapering, with
-- ultraviolet light leaking from the first segments. Sometimes it forks.
local function crack(kit, from: Vector3, direction: Vector3, length: number, life: number, opts: { [string]: any }?)
	local options = opts or {}
	local segments = math.clamp(math.floor(length / 1.6) + 1, 2, 6)
	local width = options.width or 0.22
	local speed = options.speed or 60
	local point = from + Vector3.new(0, 0.035 + random:NextNumber() * 0.012, 0)
	local heading = direction
	local travelled = 0
	for index = 1, segments do
		local step = length / segments * (0.75 + random:NextNumber() * 0.5)
		heading = turned(heading, jitter(30))
		local nextPoint = point + heading * step
		local mid = (point + nextPoint) / 2
		local taper = 1 - (index - 1) / segments * 0.65
		local delay = (options.delay or 0) + travelled / speed
		local seam = piece("Part", {
			Size = Vector3.new(width * taper, 0.05, step + 0.1),
			CFrame = CFrame.lookAt(mid, mid + heading),
			Color = options.color or VOID,
			Reflectance = 0.25,
			Transparency = 1,
		})
		stage(seam, delay, 0, life, 0.7)
		if options.glow ~= false and index <= 2 then
			local core = piece("Part", {
				Size = Vector3.new(width * taper * 0.3, 0.06, step),
				CFrame = CFrame.lookAt(mid, mid + heading) + Vector3.new(0, 0.012, 0),
				Color = GLINT,
				Material = NEON,
				Transparency = 1,
			})
			stage(core, delay, 0.2, life * 0.5, 0.5)
		end
		if options.fork ~= false and index == 2 and random:NextNumber() < 0.45 then
			crack(kit, nextPoint, turned(heading, if random:NextBoolean() then 40 else -40), length * 0.3, life * 0.8, {
				width = width * 0.6,
				speed = speed,
				delay = delay,
				glow = false,
				fork = false,
				color = options.color,
			})
		end
		travelled += step
		point = nextPoint
	end
end

-- Fractures radiating from a point
local function fractures(kit, center: Vector3, radius: number, count: number, life: number, opts: { [string]: any }?)
	local total = scaled(kit, count)
	local offset = random:NextNumber() * 360
	for index = 1, total do
		local angle = offset + index / total * 360 + jitter(14)
		local direction = turned(Vector3.new(0, 0, -1), angle)
		crack(kit, center + direction * 0.35, direction, radius * (0.6 + random:NextNumber() * 0.4), life, opts)
	end
end

-- A blade of black glass jutting out of the floor (two wedges back to back),
-- leaning `outward`. Rises fast, holds, sinks back slowly.
local function spike(kit, base: Vector3, outward: Vector3, height: number, delay: number, hold: number)
	local width = height * (0.32 + random:NextNumber() * 0.2)
	local depth = height * (0.5 + random:NextNumber() * 0.25)
	local tilt = math.rad(14 + random:NextNumber() * 26)
	local axis = (UP * math.cos(tilt) + outward * math.sin(tilt)).Unit
	local frame = CFrame.lookAt(base, base + outward) * CFrame.fromAxisAngle(Vector3.new(1, 0, 0), -tilt) * CFrame.Angles(0, math.rad(jitter(25)), 0)
	local raised = frame * CFrame.new(0, height / 2 - 0.25, 0)
	local sunk = raised - axis * (height + 0.2)
	for side = -1, 1, 2 do
		local local_ = CFrame.new(0, 0, side * depth / 4) * (if side > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
		local wedge = piece("WedgePart", {
			Size = Vector3.new(width * 0.5, height, depth / 2),
			CFrame = sunk * local_,
			Color = if side > 0 then VOID else INK,
			Reflectance = 0.4,
			Transparency = 1,
		})
		Debris:AddItem(wedge, delay + hold + 1.2)
		task.delay(delay, function()
			if not wedge.Parent then
				return
			end
			wedge.Transparency = 0
			tween(wedge, 0.08, { CFrame = raised * local_ }, Enum.EasingStyle.Back)
			task.delay(0.08 + hold, function()
				if wedge.Parent then
					tween(wedge, 0.7, { CFrame = sunk * local_, Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
			end)
		end)
	end
end

-- A ring of spikes around a point
local function spikeRing(kit, center: Vector3, radius: number, count: number, height: number, delay: number, hold: number)
	local total = scaled(kit, count)
	local offset = random:NextNumber() * 360
	for index = 1, total do
		local outward = turned(Vector3.new(0, 0, -1), offset + index / total * 360 + jitter(8))
		local at = center + outward * (radius * (0.9 + random:NextNumber() * 0.2))
		spike(kit, at, outward, height * (0.7 + random:NextNumber() * 0.5), delay + random:NextNumber() * 0.04, hold)
	end
end

-- Static: tiny squares that snap about (digital, never smooth) and blink out
local function static(kit, center: Vector3, count: number, spread: number, life: number, rise: number?)
	local total = scaled(kit, count)
	local cubes = {}
	for _ = 1, total do
		local roll = random:NextNumber()
		local size = 0.1 + random:NextNumber() * 0.22
		local cube = piece("Part", {
			Size = Vector3.one * size,
			CFrame = CFrame.new(center + Vector3.new(jitter(spread), jitter(spread * 0.7), jitter(spread))),
			Color = if roll < 0.7 then VOID elseif roll < 0.9 then STATIC else PALE,
			Material = if roll < 0.9 then PLASTIC else NEON,
		})
		table.insert(cubes, cube)
	end
	task.spawn(function()
		local steps = 3
		for step = 1, steps do
			task.wait(life / (steps + 1))
			for _, cube in cubes do
				if cube.Parent then
					if random:NextNumber() < 0.3 * step then
						cube:Destroy()
					else
						cube.CFrame = cube.CFrame + Vector3.new(jitter(0.5), (rise or 0.6) * random:NextNumber(), jitter(0.5))
					end
				end
			end
		end
		task.wait(life / (steps + 1))
		for _, cube in cubes do
			if cube.Parent then
				cube:Destroy()
			end
		end
	end)
end

-- Space popping inside out: a black glass core swells and collapses while an
-- ultraviolet skin flinches outward
local function invert(kit, position: Vector3, size: number, duration: number)
	local core = piece("Part", { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.2, CFrame = CFrame.new(position), Reflectance = 0.5 })
	tween(core, duration * 0.3, { Size = Vector3.one * size }, Enum.EasingStyle.Quint)
	task.delay(duration * 0.3, function()
		if core.Parent then
			tween(core, duration * 0.7, { Size = Vector3.one * 0.05, Transparency = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
	Debris:AddItem(core, duration + 0.1)
	local skin = piece("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * size * 0.8,
		CFrame = CFrame.new(position),
		Color = GLINT,
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
	})
	kit.Vfx.fade(skin, duration * 1.2, { Size = Vector3.one * size * 1.8, Transparency = 1 })
end

-- A tear in the picture: two slivers of a mirror slide past each other, flicker, gone
local function tear(kit, position: Vector3, width: number, height: number)
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else position + Vector3.new(0, 0, 10)
	local flatEye = Vector3.new(eye.X, position.Y, eye.Z)
	local frame = if (flatEye - position).Magnitude > 0.1 then CFrame.lookAt(position, flatEye) else CFrame.new(position)
	local slivers = {}
	for index = 1, 2 do
		local sliver = piece("Part", {
			Size = Vector3.new(width, height / 2, 0.05),
			CFrame = frame * CFrame.new(0, (index - 1.5) * height / 2, 0),
			Color = if index == 1 then PALE else STATIC,
			Reflectance = 0.6,
			Transparency = 0.4,
			Life = 1,
		})
		table.insert(slivers, sliver)
	end
	local seam = piece("Part", { Size = Vector3.new(width * 1.2, 0.06, 0.06), CFrame = frame, Color = VOID, Material = PLASTIC, Life = 1 })
	task.spawn(function()
		for step = 1, 3 do
			local shift = width * (0.15 + random:NextNumber() * 0.25) * (if step % 2 == 0 then -1 else 1)
			for index, sliver in slivers do
				if sliver.Parent then
					sliver.CFrame = frame * CFrame.new((if index == 1 then shift else -shift), (index - 1.5) * height / 2, 0)
				end
			end
			task.wait(0.045)
		end
		for _, item in { slivers[1], slivers[2], seam } do
			if item.Parent then
				item:Destroy()
			end
		end
	end)
end

-- A vertical slit in space: black glass edged with ultraviolet, facing the viewer
local function slit(kit, position: Vector3, height: number, life: number): { BasePart }
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else position + Vector3.new(0, 0, 10)
	local flatEye = Vector3.new(eye.X, position.Y, eye.Z)
	local frame = if (flatEye - position).Magnitude > 0.1 then CFrame.lookAt(position, flatEye) else CFrame.new(position)
	local body = piece("Part", { Size = Vector3.new(0.15, height, 0.08), CFrame = frame, Reflectance = 0.6, Life = life + 1 })
	tween(body, 0.1, { Size = Vector3.new(0.9, height, 0.08) }, Enum.EasingStyle.Back)
	local edge = piece("Part", { Size = Vector3.new(1.05, height * 1.04, 0.04), CFrame = frame * CFrame.new(0, 0, 0.05), Color = GLINT, Material = NEON, Transparency = 0.35, Life = life + 1 })
	stage(body, 0, 0, life, 0.35, { Transparency = 1, Size = Vector3.new(0.05, height * 0.6, 0.08) })
	stage(edge, 0, 0.35, life * 0.8, 0.3)
	return { body, edge }
end

-- Glass flakes thrown out, falling (physical debris)
local function shatter(kit, position: Vector3, count: number, speed: number)
	kit.Vfx.debris(position, count, VOID, GLASS, speed)
end

local function smoke(kit, position: Vector3, radius: number, count: number)
	kit.Vfx.burst(position + Vector3.new(0, 0.6, 0), {
		color = INK,
		lightEmission = 0,
		texture = SMOKE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) }),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		lifetime = NumberRange.new(0.8, 1.6),
		speed = NumberRange.new(radius * 0.6, radius * 1.2),
		spread = Vector2.new(10, 180),
		drag = 5,
		acceleration = Vector3.new(0, 1.5, 0),
		count = count,
	})
end

-- Motes of black that dissolve as they rise
local function motes(kit, position: Vector3, count: number, speed: number)
	kit.Vfx.burst(position, {
		colors = ColorSequence.new(VOID, STATIC),
		lightEmission = 0,
		texture = SPARKLE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) }),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		lifetime = NumberRange.new(0.5, 1.1),
		speed = NumberRange.new(speed * 0.4, speed),
		drag = 4,
		acceleration = Vector3.new(0, 3, 0),
		count = count,
	})
end

-- A thin warning circle on the floor (readable hazards)
local function warningRing(kit, center: Vector3, radius: number, duration: number)
	local ring = piece("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.06, radius * 2, radius * 2),
		CFrame = CFrame.new(center + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = GLINT,
		Material = Enum.Material.ForceField,
		Transparency = 0.3,
		Life = duration + 0.5,
	})
	stage(ring, 0, 0.3, duration, 0.2)
	return ring
end

-- A reflection of a character: their body in polished black glass, nothing else
local function reflection(model: Model, material: Enum.Material?): (Model?, { { part: BasePart, offset: CFrame } })
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil, {}
	end
	local copy = Instance.new("Model")
	copy.Name = "SNReflection"
	local parts = {}
	for _, limb in model:GetChildren() do
		if limb:IsA("BasePart") and limb.Name ~= "HumanoidRootPart" then
			local clone = limb:Clone()
			clone:ClearAllChildren()
			clone.Name = "SNMirror"
			clone.Anchored = true
			clone.CanCollide = false
			clone.CanQuery = false
			clone.CanTouch = false
			clone.CastShadow = false
			clone.Massless = true
			clone.Material = material or GLASS
			clone.Color = VOID
			clone.Reflectance = 0.5
			clone.Transparency = 0.05
			if clone:IsA("MeshPart") then
				clone.TextureID = ""
			end
			clone.Parent = copy
			table.insert(parts, { part = clone, offset = root.CFrame:ToObjectSpace(limb.CFrame) })
		end
	end
	copy.Parent = container()
	Debris:AddItem(copy, 8)
	return copy, parts
end

-- Poses -------------------------------------------------------------------------------------------

local Poser = require(script.Parent.Parent.Effects.Poser)

local REST = {}
-- Each move: the keys (anticipation, strike, follow-through) and the strike pose
-- used if keyframed sequences aren't available
local MOVES = {
	-- A palm driven forward low; the fracture leaves from the hand
	CorruptLance = {
		info = { startup = 0.22, active = 0.1, recovery = 0.3, upper = true },
		keys = {
			{ 0.14, { Root = { 0, 18, 0, 0, -0.12, 0 }, Torso = { 6, 26, 0 }, Neck = { 0, -20, 0 }, RightShoulder = { 22, 0, 34 }, RightElbow = { 80, 0, 0 }, LeftShoulder = { 40, 0, -18 }, LeftElbow = { 64, 0, 0 } } },
			{ 0.22, { Root = { 0, -20, 0, 0, -0.22, 0 }, Torso = { -10, -26, 0 }, Neck = { -6, 24, 0 }, RightShoulder = { 86, 0, -6 }, RightElbow = { 6, 0, 0 }, LeftShoulder = { -18, 0, -16 }, LeftElbow = { 20, 0, 0 }, RightHip = { 26, 0, 4 }, RightKnee = { -30, 0, 0 }, LeftHip = { -16, 0, -4 }, LeftKnee = { -14, 0, 0 } }, "Snap" },
			{ 0.34, { Root = { 0, -22, 0, 0, -0.22, 0 }, Torso = { -12, -28, 0 }, RightShoulder = { 90, 0, -4 }, RightElbow = { 2, 0, 0 }, LeftShoulder = { -16, 0, -16 }, RightHip = { 26, 0, 4 }, RightKnee = { -30, 0, 0 } }, "Out" },
			{ 0.62, REST },
		},
	},
	-- A sidearm flick: the shard leaves the fingertips
	CorruptThrow = {
		info = { startup = 0.18, active = 0.05, recovery = 0.25, upper = true },
		keys = {
			{ 0.12, { Torso = { 4, 26, 0 }, Neck = { 0, -22, 0 }, RightShoulder = { 120, 0, 40 }, RightElbow = { 96, 0, 0 }, LeftShoulder = { 60, 0, -10 }, LeftElbow = { 40, 0, 0 } } },
			{ 0.18, { Torso = { -12, -26, 0 }, Neck = { -4, 22, 0 }, RightShoulder = { 82, 0, -14 }, RightElbow = { 8, 0, 0 }, LeftShoulder = { 20, 0, -8 }, LeftElbow = { 50, 0, 0 } }, "Snap" },
			{ 0.26, { Torso = { -14, -30, 0 }, RightShoulder = { 70, 0, -24 }, RightElbow = { 14, 0, 0 } }, "Out" },
			{ 0.48, REST },
		},
	},
	-- Pulled in tight, then flung wide: everything around is pushed away
	CorruptBurst = {
		info = { startup = 0.12, active = 0.1, recovery = 0.3 },
		keys = {
			{ 0.1, { Root = { 0, 0, 0, 0, -0.3, 0 }, Torso = { -18, 0, 0 }, Neck = { -14, 0, 0 }, RightShoulder = { 64, 0, -38 }, LeftShoulder = { 64, 0, 38 }, RightElbow = { 112, 0, 0 }, LeftElbow = { 112, 0, 0 }, RightHip = { 20, 0, 6 }, LeftHip = { 20, 0, -6 }, RightKnee = { -34, 0, 0 }, LeftKnee = { -34, 0, 0 } } },
			{ 0.14, { Root = { 0, 0, 0, 0, -0.1, 0 }, Torso = { 10, 0, 0 }, Neck = { 12, 0, 0 }, RightShoulder = { 70, 0, 72 }, LeftShoulder = { 70, 0, -72 }, RightElbow = { 8, 0, 0 }, LeftElbow = { 8, 0, 0 } }, "Snap" },
			{ 0.26, { Torso = { 12, 0, 0 }, Neck = { 14, 0, 0 }, RightShoulder = { 64, 0, 80 }, LeftShoulder = { 64, 0, -80 } }, "Out" },
			{ 0.52, REST },
		},
	},
	-- One hand reaches toward the spot, then presses it down; the other stays at the chest
	CorruptCast = {
		info = { startup = 0.35, active = 0.05, recovery = 0.35, upper = true },
		keys = {
			{ 0.25, { Torso = { -6, -12, 0 }, Neck = { -4, 10, 0 }, RightShoulder = { 104, 0, -6 }, RightElbow = { 24, 0, 0 }, LeftShoulder = { 52, 0, -22 }, LeftElbow = { 104, 0, 0 } } },
			{ 0.35, { Root = { 0, 0, 0, 0, -0.15, 0 }, Torso = { -12, -14, 0 }, Neck = { -10, 10, 0 }, RightShoulder = { 70, 0, -6 }, RightElbow = { 6, 0, 0 }, LeftShoulder = { 46, 0, -22 }, LeftElbow = { 108, 0, 0 } }, "Snap" },
			{ 0.45, { Root = { 0, 0, 0, 0, -0.16, 0 }, Torso = { -12, -14, 0 }, RightShoulder = { 66, 0, -6 }, RightElbow = { 4, 0, 0 } }, "Out" },
			{ 0.75, REST },
		},
	},
	-- Folded low and trembling, then thrown open: the long tell of the big moves
	CorruptRise = {
		info = { startup = 0.75, active = 0.15, recovery = 0.8, tremble = 2.5, trembleRamp = 0.7 },
		keys = {
			{ 0.5, { Root = { 0, 0, 0, 0, -0.6, 0 }, Torso = { -24, 0, 0 }, Neck = { -18, 0, 0 }, RightShoulder = { 34, 0, -34 }, LeftShoulder = { 34, 0, 34 }, RightElbow = { 96, 0, 0 }, LeftElbow = { 96, 0, 0 }, RightHip = { 42, 0, 8 }, LeftHip = { 42, 0, -8 }, RightKnee = { -72, 0, 0 }, LeftKnee = { -72, 0, 0 } } },
			{ 0.72, { Root = { 0, 0, 0, 0, -0.66, 0 }, Torso = { -28, 0, 0 }, Neck = { -20, 0, 0 }, RightShoulder = { 30, 0, -40 }, LeftShoulder = { 30, 0, 40 }, RightElbow = { 104, 0, 0 }, LeftElbow = { 104, 0, 0 }, RightHip = { 46, 0, 8 }, LeftHip = { 46, 0, -8 }, RightKnee = { -78, 0, 0 }, LeftKnee = { -78, 0, 0 } } },
			{ 0.78, { Root = { 0, 0, 0, 0, 0.1, 0 }, Torso = { 16, 0, 0 }, Neck = { 22, 0, 0 }, RightShoulder = { 150, 0, 46 }, LeftShoulder = { 150, 0, -46 }, RightElbow = { 4, 0, 0 }, LeftElbow = { 4, 0, 0 } }, "Snap" },
			{ 1.0, { Root = { 0, 0, 0, 0, 0.08, 0 }, Torso = { 14, 0, 0 }, Neck = { 18, 0, 0 }, RightShoulder = { 144, 0, 50 }, LeftShoulder = { 144, 0, -50 } }, "Out" },
			{ 1.7, REST },
		},
	},
	-- A flinch into static, then upright where they land
	CorruptBlink = {
		info = { startup = 0.12, active = 0.05, recovery = 0.25 },
		keys = {
			{ 0.1, { Root = { 0, 0, 0, 0, -0.25, 0 }, Torso = { -22, 0, 0 }, Neck = { -12, 0, 0 }, RightShoulder = { 30, 0, -20 }, LeftShoulder = { 30, 0, 20 }, RightElbow = { 70, 0, 0 }, LeftElbow = { 70, 0, 0 } } },
			{ 0.17, { Torso = { 4, 0, 0 }, RightShoulder = { 10, 0, 24 }, LeftShoulder = { 10, 0, -24 } }, "Snap" },
			{ 0.42, REST },
		},
	},
	-- Arms opened wide: the reflections step out of either side
	CorruptSplit = {
		info = { startup = 0.15, active = 0.05, recovery = 0.2 },
		keys = {
			{ 0.15, { Torso = { 6, 0, 0 }, Neck = { 6, 0, 0 }, RightShoulder = { 22, 0, 82 }, LeftShoulder = { 22, 0, -82 }, RightElbow = { 10, 0, 0 }, LeftElbow = { 10, 0, 0 } }, "Snap" },
			{ 0.25, { Torso = { 8, 0, 0 }, RightShoulder = { 18, 0, 86 }, LeftShoulder = { 18, 0, -86 } }, "Out" },
			{ 0.4, REST },
		},
	},
}
-- The final form ending: the body sags as the shell falls off
local SLUMP = { Root = { 0, 0, 0, 0, -0.3, 0 }, Torso = { -26, 0, 0 }, Neck = { -22, 0, 0 }, RightShoulder = { -6, 0, 10 }, LeftShoulder = { -6, 0, -10 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -24, 0, 0 }, RightHip = { 14, 0, 0 }, LeftHip = { 14, 0, 0 } }

local SEQUENCES = Poser.registerSequence ~= nil and Poser.sequence ~= nil
for name, move in MOVES do
	if SEQUENCES then
		Poser.registerSequence(name, move.keys, move.info)
	end
	-- The strike key doubles as a plain pose
	local strike = move.keys[2] or move.keys[1]
	Poser.register(name, strike[2])
end
Poser.register("CorruptSlump", SLUMP)

local MOVE_FOR = {
	VoidStrike = "CorruptLance",
	CorruptBolt = "CorruptThrow",
	StaticBurst = "CorruptBurst",
	RiftBlink = "CorruptBlink",
	UnstableGround = "CorruptCast",
	DistortionPulse = "CorruptBurst",
	Unravel = "CorruptCast",
	DistortionZone = "CorruptCast",
	Phantasm = "CorruptSplit",
	Cataclysm = "CorruptRise",
	TotalSystemCorruption = "CorruptRise",
}

local function animate(kit, abilityId: string)
	local model = kit.model
	local name = MOVE_FOR[abilityId]
	if not model or not name then
		return
	end
	local def = kit.ability(abilityId)
	local startup = num(kit.data.startup, if def then def.startup or 0.2 else 0.2)
	local active = num(kit.data.active, if def then def.active or 0.1 else 0.1)
	local recovery = if def then def.recovery or 0.3 else 0.3
	if SEQUENCES then
		Poser.sequence(model, name, 1, { timing = { startup = startup, active = active, recovery = recovery } })
	else
		Poser.play(model, name, math.max(0.05, startup * 0.8), active + 0.1, math.max(0.15, recovery))
	end
end

-- The overwrite flares while it works (casts, swings, dodges)
local surges: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

local function surge(model: Model?, seconds: number)
	if model then
		surges[model] = math.max(surges[model] or 0, os.clock() + seconds)
	end
end

local function castLook(kit)
	local abilityId = kit.data.ability
	if typeof(abilityId) ~= "string" then
		return
	end
	animate(kit, abilityId)
	surge(kit.model, 0.8)
	local palm = hand(kit.model)
	if palm then
		kit.Vfx.glow(palm, GLINT, 6, 1.2, math.max(0.2, num(kit.data.startup, 0.2)))
		motes(kit, palm.Position, 6, 4)
	end
end

function Corruption.onCast(kit)
	castLook(kit)
end

for abilityId in DEF.abilities do
	Corruption.predict[abilityId] = castLook
end

-- Degree 1 effects ----------------------------------------------------------------------------------

function fx.VoidStrikeWindup(kit)
	local palm = hand(kit.model)
	local duration = math.clamp(num(kit.data.duration, 0.2), 0.05, 1)
	if palm then
		-- Static drawn into the hand
		static(kit, palm.Position, 8, 1.6, duration)
		kit.Vfx.glow(palm, GLINT, 5, 1, duration)
	end
	local base = feet(kit)
	if base then
		crack(kit, base, facing(kit), 2.5, duration + 0.2, { width = 0.12, glow = false, fork = false })
	end
end

function fx.VoidStrike(kit)
	local origin = vec(kit.data.origin) or feet(kit)
	if not origin then
		return
	end
	local direction = flatUnit(kit.data.direction, facing(kit))
	local length = math.clamp(num(kit.data.length, 9), 1, 30)
	local width = math.clamp(num(kit.data.width, 3), 0.5, 10)
	local side = turned(direction, 90)
	-- Blades erupt along the line, taller toward the tip
	local count = scaled(kit, math.floor(length / 1.3))
	for index = 1, count do
		local along = index / count * length
		local at = origin + direction * along + side * jitter(width * 0.3)
		spike(kit, at, (direction + side * jitter(0.4)).Unit, 1 + along / length * 1.8, along / 90, 0.16)
	end
	crack(kit, origin, direction, length, 0.5, { width = 0.3, speed = 90 })
	local tip = origin + direction * length + UP * 2.4
	tear(kit, tip, 2.2, 1.4)
	task.delay(0.25, function()
		static(kit, origin + direction * length * 0.6 + UP * 1.2, 10, length * 0.3, 0.5, 1.2)
	end)
	kit.Vfx.glow(origin + direction * length * 0.5 + UP, GLINT, 10, 1.4, 0.18)
	kit.Vfx.sound("HeavySwing", origin)
	kit.shake(0.6, 0.15, origin)
end

-- Corruption Marks: the ECLIPSE sigil (a ring with its inside filled) over the
-- target, one notch lit per stack, plus black motes leaking off them. One sigil
-- per target, refreshed by new marks, gone when the mark is.
local sigils: { [Model]: { gui: BillboardGui, pips: { Frame }, emitter: ParticleEmitter?, until_: number } } = {}

local function sigilFor(target: Model): any
	local existing = sigils[target]
	if existing and existing.gui.Parent then
		return existing
	end
	local head = findPart(target, { "Head", "UpperTorso", "Torso", "HumanoidRootPart" })
	if not head then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "SNCorruptionMark"
	gui.Size = UDim2.fromScale(1.5, 1.9)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Adornee = head
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0)
	disc.Position = UDim2.fromScale(0.5, 0)
	disc.Size = UDim2.fromScale(0.78, 0.6)
	disc.BackgroundColor3 = VOID
	disc.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = disc
	local stroke = Instance.new("UIStroke")
	stroke.Color = GLINT
	stroke.Thickness = 2
	stroke.Transparency = 0.1
	stroke.Parent = disc
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = disc
	disc.Parent = gui
	local pips = {}
	for index = 1, 3 do
		local pip = Instance.new("Frame")
		pip.Name = "Notch" .. index
		pip.AnchorPoint = Vector2.new(0.5, 0)
		pip.Position = UDim2.fromScale(0.5 + (index - 2) * 0.22, 0.74)
		pip.Size = UDim2.fromScale(0.14, 0.1)
		pip.BackgroundColor3 = PALE
		pip.BackgroundTransparency = 0.85
		pip.BorderSizePixel = 0
		pip.Parent = gui
		table.insert(pips, pip)
	end
	gui.Parent = container()
	local torso = findPart(target, { "UpperTorso", "Torso", "HumanoidRootPart" })
	local emitter = nil
	if torso then
		local made = Instance.new("ParticleEmitter")
		made.Name = "SNCorruptionMarkMotes"
		made.Texture = SPARKLE
		made.Color = ColorSequence.new(VOID, STATIC)
		made.LightEmission = 0
		made.LightInfluence = 0
		made.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		made.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		made.Lifetime = NumberRange.new(0.5, 0.9)
		made.Speed = NumberRange.new(0.5, 1.5)
		made.SpreadAngle = Vector2.new(180, 180)
		made.Acceleration = Vector3.new(0, 2, 0)
		made.Rate = 5
		made.Parent = torso
		emitter = made
	end
	local entry = { gui = gui, pips = pips, emitter = emitter, until_ = 0 }
	sigils[target] = entry
	-- Watch until the mark fades or is cleared (Unravel, a reset)
	task.spawn(function()
		while gui.Parent and target.Parent do
			local endsAt = target:GetAttribute(MARK_ATTRIBUTE)
			local now = workspace:GetServerTimeNow()
			if (typeof(endsAt) ~= "number" or endsAt <= now) and now > entry.until_ then
				break
			end
			task.wait(0.15)
		end
		gui:Destroy()
		if emitter then
			emitter:Destroy()
		end
		if sigils[target] == entry then
			sigils[target] = nil
		end
	end)
	return entry
end

function fx.MarkApplied(kit)
	local target = asModel(kit.data.target)
	if not target then
		return
	end
	local entry = sigilFor(target)
	if not entry then
		return
	end
	local stacks = math.clamp(math.floor(num(kit.data.stacks, 1)), 1, 3)
	-- Don't wait on the replicated status the first moment
	entry.until_ = os.clock() + 0.5 > 0 and workspace:GetServerTimeNow() + 0.6 or 0
	for index, pip in entry.pips do
		pip.BackgroundTransparency = if index <= stacks then 0.05 else 0.85
		pip.BackgroundColor3 = if index <= stacks then GLINT else PALE
	end
	local torso = findPart(target, { "UpperTorso", "Torso", "HumanoidRootPart" })
	if torso then
		static(kit, torso.Position, 6 + stacks * 2, 1.2, 0.35)
		kit.Vfx.flash(target, VOID, 0.2)
	end
end

function fx.ShardWindup(kit)
	local palm = hand(kit.model)
	if not palm then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 0.18), 0.05, 0.6)
	-- The shard grows out of the fingertips
	local shard = piece("Part", { Size = Vector3.new(0.12, 0.12, 0.4), CFrame = palm.CFrame, Reflectance = 0.45, Life = duration + 0.2 })
	tween(shard, duration, { Size = Vector3.new(0.3, 0.3, 1.3) })
	task.spawn(function()
		local started = os.clock()
		while shard.Parent and palm.Parent and os.clock() - started < duration do
			shard.CFrame = palm.CFrame * CFrame.new(0, -0.6, 0) * CFrame.Angles(math.rad(90), 0, math.rad(45))
			task.wait()
		end
		if shard.Parent then
			shard:Destroy()
		end
	end)
	kit.Vfx.glow(palm, GLINT, 5, 1, duration)
end

-- A shard of void glass: diamond section, ultraviolet core, a short tapering
-- trail, spinning, shedding static
function Corruption.projectiles.VoidShard(kit)
	local size = math.clamp(num(kit.data.radius, 0.8), 0.3, 2)
	local strong = kit.data.empowered == true
	local body = piece("Part", { Size = Vector3.new(size * 0.45, size * 0.45, size * 2.2), Reflectance = 0.45, Life = 4 })
	local core = piece("Part", { Size = Vector3.new(size * 0.14, size * 0.14, size * 1.7), Color = if strong then PALE else GLINT, Material = NEON, Transparency = 0.15, Life = 4 })
	local back = Instance.new("Attachment")
	back.Position = Vector3.new(0, 0, size * 1.1)
	back.Parent = body
	local tip = Instance.new("Attachment")
	tip.Position = Vector3.new(0, 0, size * 0.4)
	tip.Parent = body
	local trail = Instance.new("Trail")
	trail.Attachment0 = tip
	trail.Attachment1 = back
	trail.Color = ColorSequence.new(GLINT, VOID)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	trail.Lifetime = 0.16
	trail.LightEmission = 0.4
	trail.FaceCamera = true
	trail.Parent = body
	local light = Instance.new("PointLight")
	light.Color = GLINT
	light.Range = 7
	light.Brightness = 1.1
	light.Parent = body
	local spin = random:NextNumber() * math.pi
	local shed = 0
	local last = nil :: Vector3?
	return {
		update = function(position: Vector3, velocity: Vector3, dt: number)
			if not body.Parent then
				return
			end
			local direction = if velocity.Magnitude > 0.1 then velocity.Unit else Vector3.new(0, 0, -1)
			spin += dt * 14
			local frame = CFrame.lookAt(position, position + direction) * CFrame.Angles(0, 0, spin + math.rad(45))
			body.CFrame = frame
			if core.Parent then
				core.CFrame = frame
			end
			shed += dt
			if shed > 0.07 and last and not reduced(kit) then
				shed = 0
				static(kit, last, 2, 0.3, 0.25, 0.2)
			end
			last = position
		end,
		finish = function(position: Vector3, reason: string)
			for _, item in { body, core } do
				if item.Parent then
					item:Destroy()
				end
			end
			if reason == "Expired" or reason == "Range" then
				static(kit, position, 6, 0.6, 0.3)
				return
			end
			-- Breaks into flakes and a star of hairline cracks in the air
			shatter(kit, position, if reason == "Hit" then 6 else 4, 26)
			invert(kit, position, size * 2.2, 0.22)
			static(kit, position, 8, 0.9, 0.35)
			if reason == "Intercepted" or reason == "Destroyed" then
				kit.Vfx.sparks(position, PALE, 8, 16)
			else
				kit.Vfx.glow(position, GLINT, 8, 1.4, 0.15)
				kit.Vfx.sound("Hit", position)
			end
		end,
	}
end

function fx.StaticGather(kit)
	local root = kit.root
	if not root then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 0.12), 0.05, 0.5)
	for _ = 1, scaled(kit, 3) do
		local from = root.Position + Vector3.new(jitter(1.6), jitter(1.8), jitter(1.6))
		kit.Vfx.lightning(from, root.Position + Vector3.new(jitter(0.6), jitter(0.8), jitter(0.6)), GLINT, 3, duration)
	end
	static(kit, root.Position, 10, 2.2, duration)
end

function fx.StaticBurst(kit)
	local position = vec(kit.data.position) or feet(kit)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 8), 1, 30)
	local Vfx = kit.Vfx
	Vfx.shockwave(position + UP * 2.5, VOID, 2, radius * 2, 0.28)
	Vfx.groundRing(position + UP * 0.08, PALE, 1, radius * 2, 0.32)
	invert(kit, position + UP * 2.5, 3.2, 0.25)
	fractures(kit, position, radius * 0.55, 6, 0.7, { width = 0.16 })
	-- Static thrown along the floor to the edge
	local cubes = scaled(kit, 22)
	for index = 1, cubes do
		local direction = turned(Vector3.new(0, 0, -1), index / cubes * 360 + jitter(10))
		local cube = piece("Part", {
			Size = Vector3.one * (0.14 + random:NextNumber() * 0.2),
			CFrame = CFrame.new(position + UP * (0.4 + random:NextNumber() * 2) + direction * 0.8),
			Color = if index % 5 == 0 then PALE else VOID,
			Material = if index % 5 == 0 then NEON else PLASTIC,
			Life = 1,
		})
		tween(cube, 0.22 + random:NextNumber() * 0.1, { CFrame = CFrame.new(cube.Position + direction * radius * (0.8 + random:NextNumber() * 0.3)) }, Enum.EasingStyle.Quint)
		task.delay(0.3 + random:NextNumber() * 0.25, function()
			if cube.Parent then
				cube:Destroy()
			end
		end)
	end
	motes(kit, position + UP * 1.5, 14, radius)
	Vfx.glow(position + UP * 2, GLINT, radius * 1.6, 2, 0.14)
	Vfx.sound("Parry", position)
	kit.shake(0.9, 0.2, position)
end

function fx.ShotsUnmade(kit)
	local positions = kit.data.positions
	if typeof(positions) ~= "table" then
		return
	end
	for index, value in positions do
		local position = vec(value)
		if position and index <= 8 then
			invert(kit, position, 1.6, 0.2)
			static(kit, position, 6, 0.7, 0.3)
			kit.Vfx.sparks(position, PALE, 6, 12)
		end
	end
end

-- Degree 2 effects -----------------------------------------------------------------------------------

function fx.RiftDissolve(kit)
	local model, root = kit.model, kit.root
	if not model or not root then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 0.12), 0.05, 0.5)
	kit.Vfx.flash(model, VOID, duration + 0.1)
	static(kit, root.Position, 18, 1.4, duration + 0.15, 1.6)
	tear(kit, root.Position + UP * 0.5, 2.4, 1.2)
end

function fx.RiftArrive(kit)
	local from = vec(kit.data.from)
	local to = vec(kit.data.to)
	if not from or not to then
		return
	end
	local model = kit.model
	if model then
		-- What's left where they stood: a black reflection that splinters
		kit.Vfx.ghostAt(model, CFrame.new(from) * (if kit.root then kit.root.CFrame.Rotation else CFrame.identity), VOID, 0.45, GLASS)
		kit.Vfx.flash(model, PALE, 0.15)
	end
	-- Static strung out along the path, as if it was the same picture torn
	local path = to - from
	local steps = scaled(kit, math.clamp(math.floor(path.Magnitude / 2), 2, 10))
	for index = 1, steps do
		local at = from + path * (index / (steps + 1))
		task.delay(index * 0.012, function()
			static(kit, at, 2, 0.6, 0.3)
		end)
	end
	static(kit, to, 12, 1.2, 0.3)
	invert(kit, to, 3, 0.22)
	kit.Vfx.sound("Dodge", to)
end

function fx.RiftOpen(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 5), 1, 20)
	local fuse = math.clamp(num(kit.data.fuse, 0.45), 0.1, 2)
	slit(kit, position + UP * 2.4, 4.2, fuse)
	warningRing(kit, position, radius, fuse)
	fractures(kit, position, radius * 0.7, 5, fuse + 0.3, { width = 0.14 })
	kit.Vfx.glow(position + UP * 2, GLINT, 8, 1, fuse)
end

function fx.RiftBurst(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 5), 1, 20)
	invert(kit, position + UP * 2, radius * 0.9, 0.3)
	spikeRing(kit, position, radius * 0.45, 6, 1.6, 0, 0.15)
	shatter(kit, position + UP, 6, 30)
	kit.Vfx.groundRing(position + UP * 0.08, VOID, 1, radius * 2, 0.35)
	static(kit, position + UP * 2, 12, radius * 0.5, 0.5, 1)
	kit.Vfx.glow(position + UP * 2, GLINT, radius * 2, 1.8, 0.15)
	kit.Vfx.sound("HeavyHit", position)
	kit.shake(0.9, 0.2, position)
end

function fx.RiftBlinkFail(kit)
	local position = vec(kit.data.position) or (if kit.root then kit.root.Position else nil)
	if not position then
		return
	end
	static(kit, position, 10, 1, 0.3)
	if kit.model then
		kit.Vfx.flash(kit.model, STATIC, 0.2)
	end
	kit.Vfx.sound("Block", position)
end

function fx.GroundCrack(kit)
	local target = vec(kit.data.target)
	local start = feet(kit)
	if not target then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 0.35), 0.05, 1.5)
	local radius = math.clamp(num(kit.data.radius, 9), 1, 30)
	if start then
		-- The fracture races from the caster's feet to the spot
		local path = Vector3.new(target.X - start.X, 0, target.Z - start.Z)
		if path.Magnitude > 1 then
			crack(kit, start, path.Unit, path.Magnitude, duration + 0.5, { width = 0.18, speed = path.Magnitude / math.max(0.05, duration) })
		end
	end
	warningRing(kit, target, radius, duration + 0.6)
end

-- Unstable ground: a disc of floor broken into black glass plates that tilt and
-- bob; a fracture web with light leaking up; a low fence of jagged shards marks the edge
function fx.UnstableGround(kit)
	local floor = vec(kit.data.floor) or vec(kit.data.center)
	if not floor then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 9), 1, 30)
	local duration = math.clamp(num(kit.data.duration, 5), 0.1, 15)
	local arm = math.clamp(num(kit.data.arm, 0.6), 0, 3)
	local created: { Instance } = {}
	local running = true
	kit.keep(function()
		running = false
		for _, item in created do
			if item.Parent then
				kit.Vfx.fade(item, 0.5, { Transparency = 1 })
			end
		end
	end)
	fractures(kit, floor, radius, 10, duration, { width = 0.2 })
	-- The plates
	local plates = {}
	local count = scaled(kit, 9)
	for index = 1, count do
		local angle = index / count * 360 + jitter(15)
		local distance = radius * (0.25 + random:NextNumber() * 0.6)
		local at = floor + turned(Vector3.new(0, 0, -1), angle) * distance
		local size = Vector3.new(1.6 + random:NextNumber() * 1.6, 0.25, 1.4 + random:NextNumber() * 1.4)
		local plate = piece("Part", {
			Size = size,
			CFrame = CFrame.new(at + UP * 0.02) * CFrame.Angles(0, math.rad(random:NextNumber() * 180), 0),
			Color = if index % 3 == 0 then INK else VOID,
			Reflectance = 0.35,
			Life = duration + 2,
		})
		table.insert(created, plate)
		table.insert(plates, { part = plate, base = plate.CFrame, phase = random:NextNumber() * 6, tilt = 6 + random:NextNumber() * 10 })
	end
	-- The edge, so nobody wanders in by accident
	local fence = scaled(kit, 14)
	for index = 1, fence do
		local outward = turned(Vector3.new(0, 0, -1), index / fence * 360 + jitter(6))
		local height = 0.5 + random:NextNumber() * 0.8
		local shard = piece("WedgePart", {
			Size = Vector3.new(0.25, height, 0.6),
			CFrame = CFrame.lookAt(floor + outward * radius, floor + outward * (radius + 1)) * CFrame.new(0, height / 2 - 0.1, 0) * CFrame.Angles(math.rad(jitter(12)), 0, math.rad(jitter(12))),
			Color = VOID,
			Reflectance = 0.4,
			Life = duration + 2,
		})
		table.insert(created, shard)
	end
	local seep = piece("Part", {
		Size = Vector3.new(radius * 1.6, 0.2, radius * 1.6),
		CFrame = CFrame.new(floor + UP * 0.15),
		Transparency = 1,
		Life = duration + 2,
	})
	table.insert(created, seep)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = ColorSequence.new(GLINT, VOID)
	emitter.LightEmission = 0.3
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, 1.2, 0)
	emitter.Rate = if reduced(kit) then 3 else 10
	emitter.Parent = seep
	local light = Instance.new("PointLight")
	light.Color = GLINT
	light.Range = radius * 1.4
	light.Brightness = 0.6
	light.Parent = seep
	-- Settles while arming, then shifts underfoot
	task.spawn(function()
		local started = os.clock()
		while running and os.clock() - started < duration + 0.2 do
			local t = os.clock() - started
			local unsettled = math.clamp((t - arm) / 0.3, 0, 1)
			for _, plate in plates do
				if plate.part.Parent then
					local wobble = math.sin(t * 5 + plate.phase)
					plate.part.CFrame = plate.base
						* CFrame.new(0, 0.12 + unsettled * (0.18 + 0.12 * wobble), 0)
						* CFrame.Angles(math.rad(plate.tilt * unsettled * wobble), 0, math.rad(plate.tilt * 0.6 * unsettled * math.cos(t * 4 + plate.phase)))
				end
			end
			task.wait(1 / 30)
		end
	end)
	kit.Vfx.sound("HeavyHit", floor)
	kit.shake(0.5, 0.2, floor)
end

function fx.PulseWindup(kit)
	local root = kit.root
	local base = feet(kit)
	if not root or not base then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 0.4), 0.05, 1.5)
	local radius = math.clamp(num(kit.data.radius, 13), 1, 40)
	-- Space inhales: the edge of the pulse draws in toward them
	local shell = piece("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * radius * 2,
		CFrame = CFrame.new(base + UP * 2),
		Color = GLINT,
		Material = Enum.Material.ForceField,
		Transparency = 0.7,
		Life = duration + 0.3,
	})
	tween(shell, duration, { Size = Vector3.one * 3, Transparency = 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	warningRing(kit, base, radius, duration)
	static(kit, root.Position, 10, 2, duration)
	kit.Vfx.glow(root, GLINT, 10, 1.2, duration)
end

function fx.DistortionPulse(kit)
	local position = vec(kit.data.position) or feet(kit)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 13), 1, 40)
	local Vfx = kit.Vfx
	-- A wave of inverted space: a refracting glass shell racing out over a black ring
	local wave = piece("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2,
		CFrame = CFrame.new(position + UP * 1.5),
		Color = PALE,
		Reflectance = 0.2,
		Transparency = 0.55,
		Life = 1,
	})
	tween(wave, 0.32, { Size = Vector3.one * radius * 2.1, Transparency = 1 }, Enum.EasingStyle.Quint)
	Vfx.groundRing(position + UP * 0.08, VOID, 2, radius * 2.1, 0.4)
	Vfx.ring(CFrame.new(position + UP * 0.3) * CFrame.Angles(math.rad(90), 0, 0), 1.5, GLINT, 0.25, 0.32, radius)
	fractures(kit, position, radius * 0.85, 12, 0.9)
	spikeRing(kit, position, radius * 0.92, 12, 1.2, 0.22, 0.12)
	invert(kit, position + UP * 2.5, 4, 0.3)
	smoke(kit, position, radius, 10)
	Vfx.glow(position + UP * 2, GLINT, radius * 1.5, 2.2, 0.18)
	Vfx.sound("HeavyHit", position)
	kit.shake(1.4, 0.3, position)
end

function fx.UnravelWindup(kit)
	local targets = kit.data.targets
	local palm = hand(kit.model)
	local duration = math.clamp(num(kit.data.duration, 0.45), 0.05, 1.5)
	if palm then
		kit.Vfx.glow(palm, GLINT, 6, 1.4, duration)
	end
	if typeof(targets) ~= "table" or not palm then
		return
	end
	-- Black threads drawn taut between the hand and every mark
	for index, value in targets do
		local target = asModel(value)
		local torso = target and findPart(target, { "UpperTorso", "Torso", "HumanoidRootPart" })
		if torso and index <= 6 then
			task.spawn(function()
				local started = os.clock()
				while os.clock() - started < duration and palm.Parent and torso.Parent do
					kit.Vfx.beam(palm.Position, torso.Position, VOID, 0.06 + (os.clock() - started) / duration * 0.08, 0.06, GLASS)
					task.wait(0.05)
				end
			end)
			local entry = sigils[target :: Model]
			if entry then
				kit.Vfx.flash(target :: Model, GLINT, duration)
			end
		end
	end
end

function fx.UnravelDetonate(kit)
	local target = asModel(kit.data.target)
	local torso = target and findPart(target, { "UpperTorso", "Torso", "HumanoidRootPart" })
	if not torso then
		return
	end
	local stacks = math.clamp(math.floor(num(kit.data.stacks, 1)), 1, 3)
	local position = torso.Position
	invert(kit, position, 2 + stacks, 0.3)
	shatter(kit, position, 3 + stacks * 3, 24 + stacks * 6)
	static(kit, position, 8 + stacks * 4, 1.4, 0.45, 1)
	fractures(kit, position - UP * 2.9, 2 + stacks * 1.5, 4 + stacks, 0.8, { width = 0.14 })
	kit.Vfx.flash(target :: Model, PALE, 0.12)
	kit.Vfx.glow(position, GLINT, 8 + stacks * 3, 1.6 + stacks * 0.3, 0.15)
	kit.Vfx.sound(if stacks >= 2 then "HeavyHit" else "Hit", position)
	kit.shake(0.6 + stacks * 0.4, 0.2, position)
end

function fx.UnravelFizzle(kit)
	local palm = hand(kit.model)
	if palm then
		static(kit, palm.Position, 6, 0.6, 0.3)
	end
end

-- Degree 3 effects ------------------------------------------------------------------------------------

function fx.ZoneFold(kit)
	local target = vec(kit.data.target)
	if not target then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 0.5), 0.05, 1.5)
	local radius = math.clamp(num(kit.data.radius, 11), 1, 30)
	-- Space folds in on the spot before it opens
	local fold = piece("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * radius * 2.4,
		CFrame = CFrame.new(target + UP * 3),
		Color = GLINT,
		Material = Enum.Material.ForceField,
		Transparency = 0.8,
		Life = duration + 0.3,
	})
	tween(fold, duration, { Size = Vector3.one * radius * 1.6, Transparency = 0.45 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	warningRing(kit, target, radius, duration + 0.2)
	fractures(kit, target, radius * 0.5, 6, duration + 0.4, { width = 0.14 })
end

-- The distortion zone: a sphere of refracting black glass where the room looks
-- wrong, fragments tumbling upside down inside, a stain on the floor and a lit rim
function fx.DistortionZone(kit)
	local center = vec(kit.data.center)
	local floor = vec(kit.data.floor) or (if center then center - UP * 3 else nil)
	if not center or not floor then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 11), 1, 30)
	local duration = math.clamp(num(kit.data.duration, 4.5), 0.1, 15)
	local created: { Instance } = {}
	local running = true
	kit.keep(function()
		running = false
		for _, item in created do
			if item.Parent then
				kit.Vfx.fade(item, 0.4, { Transparency = 1 })
			end
		end
		if center then
			invert(kit, center, 4, 0.3)
		end
	end)
	local sphere = piece("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.5,
		CFrame = CFrame.new(center),
		Color = INK,
		Reflectance = 0.25,
		Transparency = 0.72,
		Life = duration + 2,
	})
	tween(sphere, 0.25, { Size = Vector3.one * radius * 2 }, Enum.EasingStyle.Back)
	table.insert(created, sphere)
	local skin = piece("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * radius * 2.06,
		CFrame = CFrame.new(center),
		Color = GLINT,
		Material = Enum.Material.ForceField,
		Transparency = 0.82,
		Life = duration + 2,
	})
	table.insert(created, skin)
	local stain = piece("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.05, radius * 2, radius * 2),
		CFrame = CFrame.new(floor + UP * 0.03) * CFrame.Angles(0, 0, math.rad(90)),
		Material = PLASTIC,
		Transparency = 0.35,
		Life = duration + 2,
	})
	table.insert(created, stain)
	local rim = piece("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.07, radius * 2 + 0.3, radius * 2 + 0.3),
		CFrame = CFrame.new(floor + UP * 0.02) * CFrame.Angles(0, 0, math.rad(90)),
		Color = GLINT,
		Material = NEON,
		Transparency = 0.55,
		Life = duration + 2,
	})
	table.insert(created, rim)
	local light = Instance.new("PointLight")
	light.Color = GLINT
	light.Range = radius * 1.6
	light.Brightness = 0.8
	light.Parent = sphere
	fractures(kit, floor, radius, 12, duration, { width = 0.18 })
	local fragments = {}
	for index = 1, scaled(kit, 9) do
		local shard = piece("WedgePart", {
			Size = Vector3.new(0.2, 0.6 + random:NextNumber() * 0.9, 0.5 + random:NextNumber() * 0.6),
			CFrame = CFrame.new(center),
			Color = if index % 4 == 0 then PALE else VOID,
			Reflectance = 0.5,
			Life = duration + 2,
		})
		table.insert(created, shard)
		table.insert(fragments, {
			part = shard,
			angle = random:NextNumber() * math.pi * 2,
			radius = radius * (0.3 + random:NextNumber() * 0.5),
			height = jitter(radius * 0.4),
			speed = 0.3 + random:NextNumber() * 0.5,
			tumble = 1 + random:NextNumber() * 2,
		})
	end
	task.spawn(function()
		local started = os.clock()
		while running and os.clock() - started < duration + 0.2 do
			local t = os.clock() - started
			for _, fragment in fragments do
				if fragment.part.Parent then
					local angle = fragment.angle + t * fragment.speed
					local at = center + Vector3.new(math.cos(angle) * fragment.radius, fragment.height + math.sin(t * 1.3 + angle) * 0.5, math.sin(angle) * fragment.radius)
					-- Upside down and turning: nothing in here is the right way up
					fragment.part.CFrame = CFrame.new(at) * CFrame.Angles(math.pi + t * fragment.tumble, angle, t * fragment.tumble * 0.5)
				end
			end
			task.wait(1 / 30)
		end
	end)
	kit.Vfx.sound("HeavySwing", center)
end

function fx.PhantasmSplit(kit)
	local model, root = kit.model, kit.root
	if not model or not root then
		return
	end
	for side = -1, 1, 2 do
		kit.Vfx.ghostAt(model, root.CFrame * CFrame.new(side * 0.7, 0, 0), VOID, 0.3, GLASS)
	end
	static(kit, root.Position, 10, 1.4, 0.3)
end

-- Phantasm: reflections walk out of the caster. They flicker with static (the
-- tell), crack with ultraviolet light just before they burst
function fx.Phantasm(kit)
	local model = kit.model
	local copies = kit.data.copies
	if not model or typeof(copies) ~= "table" then
		return
	end
	local fuse = math.clamp(num(kit.data.fuse, 1.6), 0.2, 4)
	local walkers = {}
	local running = true
	kit.keep(function()
		running = false
		for _, walker in walkers do
			if walker.model.Parent then
				walker.model:Destroy()
			end
		end
	end)
	for index, copy in copies do
		local from = if typeof(copy) == "table" then vec(copy.from) else nil
		local to = if typeof(copy) == "table" then vec(copy.to) else nil
		if from and to and index <= 4 then
			local mirror, parts = reflection(model)
			if mirror then
				table.insert(walkers, { model = mirror, parts = parts, from = from, to = to })
			end
		end
	end
	task.spawn(function()
		local started = os.clock()
		local nextFlicker = 0.25
		while running and os.clock() - started < fuse + 0.1 do
			local t = os.clock() - started
			local share = math.clamp(t / fuse, 0, 1)
			local flicker = false
			if t >= nextFlicker then
				nextFlicker = t + 0.22 + random:NextNumber() * 0.12
				flicker = true
			end
			for _, walker in walkers do
				local path = walker.to - walker.from
				local heading = if Vector3.new(path.X, 0, path.Z).Magnitude > 0.1 then Vector3.new(path.X, 0, path.Z).Unit else Vector3.new(0, 0, -1)
				local at = walker.from + path * share + UP * math.abs(math.sin(t * 9)) * 0.15
				local frame = CFrame.lookAt(at, at + heading)
				local shaking = share > 0.65
				for _, entry in walker.parts do
					if entry.part.Parent then
						entry.part.CFrame = frame * entry.offset * (if shaking then CFrame.new(jitter(0.06), jitter(0.06), jitter(0.06)) else CFrame.identity)
						entry.part.Transparency = if flicker then 0.6 else 0.05
						if shaking and entry.part.Color ~= GLINT and random:NextNumber() < 0.03 then
							entry.part.Color = INK
						end
					end
				end
				if flicker then
					static(kit, at, 4, 0.9, 0.2)
				end
			end
			task.wait(1 / 30)
		end
	end)
end

function fx.PhantasmBurst(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 6), 1, 20)
	invert(kit, position + UP * 2.5, radius * 0.9, 0.3)
	shatter(kit, position + UP * 2.5, 10, 32)
	spikeRing(kit, position, radius * 0.5, 7, 1.3, 0, 0.12)
	kit.Vfx.groundRing(position + UP * 0.08, PALE, 1, radius * 2, 0.35)
	static(kit, position + UP * 2.5, 12, radius * 0.4, 0.45, 1)
	kit.Vfx.glow(position + UP * 2.5, GLINT, radius * 2, 1.8, 0.15)
	kit.Vfx.sound("GuardBreak", position)
	kit.shake(0.8, 0.2, position)
end

function fx.CataclysmWindup(kit)
	local root = kit.root
	local base = feet(kit)
	if not root or not base then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 0.75), 0.05, 2)
	local radius = math.clamp(num(kit.data.radius, 16), 1, 40)
	-- The floor fractures outward in rings all through the wind-up
	for ring = 1, 3 do
		task.delay(duration * (ring - 1) / 3, function()
			fractures(kit, base, radius * ring / 3, 4 + ring * 2, duration * (1 - (ring - 1) / 3) + 0.5, { width = 0.2 })
		end)
	end
	warningRing(kit, base, radius, duration)
	-- Dark flames climbing off the body
	kit.Vfx.burst(root.Position, {
		colors = ColorSequence.new(VOID, INK),
		lightEmission = 0,
		texture = FIRE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0.2) }),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		lifetime = NumberRange.new(0.5, 0.9),
		speed = NumberRange.new(3, 6),
		spread = Vector2.new(25, 25),
		acceleration = Vector3.new(0, 8, 0),
		count = 26,
	})
	local light = kit.Vfx.glow(root, GLINT, 12, 0.6, duration + 0.1)
	if light and light.Parent then
		tween(light, duration, { Brightness = 2.4 })
	end
	static(kit, root.Position, 14, 2.6, duration)
	kit.Vfx.sound("HeavySwing", root)
end

function fx.Cataclysm(kit)
	local position = vec(kit.data.position) or feet(kit)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 16), 1, 40)
	local Vfx = kit.Vfx
	-- The ground inverts: rings of glass blades erupt one after another
	spikeRing(kit, position, radius * 0.35, 8, 2.2, 0, 0.35)
	spikeRing(kit, position, radius * 0.65, 12, 2.8, 0.06, 0.3)
	spikeRing(kit, position, radius * 0.95, 16, 2.2, 0.12, 0.25)
	-- Slabs of floor flip over and show their black undersides
	local slabs = scaled(kit, 6)
	for index = 1, slabs do
		local outward = turned(Vector3.new(0, 0, -1), index / slabs * 360 + jitter(20))
		local at = position + outward * radius * (0.45 + random:NextNumber() * 0.3) + UP * 0.1
		local slab = piece("Part", {
			Size = Vector3.new(2.6, 0.3, 2.2),
			CFrame = CFrame.lookAt(at, at + outward),
			Color = STATIC,
			Material = Enum.Material.Concrete,
			Life = 3,
		})
		local under = piece("Part", { Size = Vector3.new(2.62, 0.05, 2.22), CFrame = slab.CFrame * CFrame.new(0, -0.18, 0), Reflectance = 0.4, Life = 3 })
		local flipped = slab.CFrame * CFrame.new(0, 0.6, 0) * CFrame.Angles(math.pi, 0, 0)
		tween(slab, 0.25, { CFrame = flipped }, Enum.EasingStyle.Back)
		tween(under, 0.25, { CFrame = flipped * CFrame.new(0, -0.18, 0) }, Enum.EasingStyle.Back)
		stage(slab, 0, 0, 0.9, 0.8)
		stage(under, 0, 0, 0.9, 0.8)
	end
	fractures(kit, position, radius, 14, 1.4)
	Vfx.shockwave(position + UP * 2, VOID, 3, radius * 2.2, 0.4)
	Vfx.groundRing(position + UP * 0.08, PALE, 2, radius * 2.2, 0.45)
	invert(kit, position + UP * 3, 6, 0.4)
	shatter(kit, position + UP, 12, 48)
	smoke(kit, position, radius, 18)
	Vfx.glow(position + UP * 3, GLINT, radius * 2, 3, 0.2)
	if Vfx.intense() and kit.near(position, radius + 10) then
		Vfx.screenFlash(VOID, 0.35, 0.25)
	end
	Vfx.sound("HeavyHit", position)
	kit.shake(2.6, 0.45, position)
end

function fx.CataclysmFizzle(kit)
	local root = kit.root
	if root then
		static(kit, root.Position, 12, 1.6, 0.4)
		smoke(kit, root.Position - UP * 2.5, 4, 6)
	end
end

-- Ultimate ----------------------------------------------------------------------------------------------

function fx.SystemBreakWindup(kit)
	local root = kit.root
	local base = feet(kit)
	if not root or not base then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 1.1), 0.05, 3)
	local radius = math.clamp(num(kit.data.radius, 14), 1, 40)
	-- The room starts to come apart: fractures race past the edge
	fractures(kit, base, radius * 1.3, 16, duration + 0.6, { width = 0.26, speed = radius * 1.3 / math.max(0.1, duration) })
	warningRing(kit, base, radius, duration)
	-- Mirror panels with no source hang around them, facing in, then break on impact
	local panels = scaled(kit, 6)
	for index = 1, panels do
		local outward = turned(Vector3.new(0, 0, -1), index / panels * 360 + jitter(12))
		local at = base + outward * radius * 0.6 + UP * (2.5 + jitter(0.8))
		local panel = piece("Part", {
			Size = Vector3.new(0.05, 1.5, 0.05),
			CFrame = CFrame.lookAt(at, base + UP * 2.5),
			Color = PALE,
			Reflectance = 0.8,
			Transparency = 0.15,
			Life = duration + 1,
		})
		tween(panel, duration * 0.6, { Size = Vector3.new(2.2, 3, 0.05) }, Enum.EasingStyle.Quad)
		task.delay(duration, function()
			if panel.Parent then
				shatter(kit, panel.Position, 3, 22)
				panel:Destroy()
			end
		end)
	end
	-- Inverted space collapsing onto the body
	local shell = piece("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * radius * 1.6,
		CFrame = CFrame.new(root.Position),
		Color = INK,
		Reflectance = 0.3,
		Transparency = 0.85,
		Life = duration + 0.5,
	})
	tween(shell, duration, { Size = Vector3.one * 3.5, Transparency = 0.25 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local light = kit.Vfx.glow(root, GLINT, 14, 0.5, duration + 0.1)
	if light and light.Parent then
		tween(light, duration, { Brightness = 3 })
	end
	static(kit, root.Position, 20, 3, duration, 2)
	kit.Vfx.sound("HeavySwing", root)
	kit.shake(0.8, duration, root.Position)
end

function fx.SystemBreak(kit)
	local position = vec(kit.data.position) or feet(kit)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 14), 1, 40)
	local Vfx = kit.Vfx
	local wave = piece("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 3,
		CFrame = CFrame.new(position + UP * 2.5),
		Color = PALE,
		Reflectance = 0.3,
		Transparency = 0.4,
		Life = 1.2,
	})
	tween(wave, 0.4, { Size = Vector3.one * radius * 2.3, Transparency = 1 }, Enum.EasingStyle.Quint)
	Vfx.shockwave(position + UP * 2.5, VOID, 4, radius * 2.4, 0.45)
	Vfx.groundRing(position + UP * 0.08, GLINT, 2, radius * 2.2, 0.5)
	spikeRing(kit, position, radius * 0.5, 10, 2.6, 0, 0.4)
	spikeRing(kit, position, radius * 0.85, 14, 2, 0.08, 0.3)
	fractures(kit, position, radius * 1.2, 16, 1.8)
	invert(kit, position + UP * 3, 7, 0.45)
	shatter(kit, position + UP * 2, 14, 50)
	smoke(kit, position, radius, 20)
	Vfx.glow(position + UP * 3, GLINT, radius * 2.2, 3.5, 0.22)
	if Vfx.intense() and kit.near(position, radius + 20) then
		Vfx.screenFlash(VOID, 0.5, 0.35)
	end
	Vfx.sound("HeavyHit", position)
	Vfx.sound("GuardBreak", position)
	kit.shake(3.2, 0.55, position)
end

function fx.SystemBreakFizzle(kit)
	local root = kit.root
	if root then
		static(kit, root.Position, 16, 2, 0.5)
		invert(kit, root.Position, 3, 0.3)
	end
end

-- While the final form lasts, the room around them can't hold its shape:
-- fractures open underfoot and the picture tears near them. For the fighter
-- themselves the world drains slightly of colour (only with intense effects on).
function fx.FinalForm(kit)
	local model, root = kit.model, kit.root
	if not model or not root then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 5), 0.1, 15)
	local running = true
	local grade: ColorCorrectionEffect? = nil
	if kit.isLocal and kit.Vfx.intense() and workspace.CurrentCamera then
		local made = Instance.new("ColorCorrectionEffect")
		made.Name = "SNCorruptionGrade"
		made.Saturation = 0
		made.Contrast = 0
		made.TintColor = Color3.new(1, 1, 1)
		made.Parent = workspace.CurrentCamera
		tween(made, 0.4, { Saturation = -0.3, Contrast = 0.12, TintColor = rgb(236, 232, 255) })
		grade = made
	end
	kit.keep(function()
		running = false
		if grade and grade.Parent then
			tween(grade, 0.6, { Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) })
			Debris:AddItem(grade, 0.7)
		end
	end)
	task.spawn(function()
		local started = os.clock()
		while running and root.Parent and os.clock() - started < duration + 0.1 do
			local base = root.Position - UP * 2.9
			fractures(kit, base, 4 + random:NextNumber() * 3, 3, 1.2, { width = 0.16 })
			if random:NextNumber() < 0.5 then
				tear(kit, root.Position + Vector3.new(jitter(4), 1 + jitter(1.5), jitter(4)), 1.6, 0.8)
			end
			task.wait(if reduced(kit) then 1 else 0.55)
		end
	end)
end

-- The distinct end: the black shell cracks and falls off in flakes, the halo
-- drops, and what's left stands there drained
function fx.FormCollapse(kit)
	local model, root = kit.model, kit.root
	if not model or not root then
		return
	end
	Poser.play(model, "CorruptSlump", 0.15, 0.7, 0.5)
	kit.Vfx.flash(model, PALE, 0.3)
	for _, limb in model:GetChildren() do
		if limb:IsA("BasePart") and limb.Name ~= "HumanoidRootPart" and not reduced(kit) then
			local flake = piece("Part", {
				Size = Vector3.new(limb.Size.X * 0.7, limb.Size.Y * 0.5, 0.06),
				CFrame = limb.CFrame * CFrame.new(0, 0, -limb.Size.Z / 2 - 0.04),
				Reflectance = 0.4,
				Life = 2,
			})
			tween(flake, 0.9, { CFrame = flake.CFrame * CFrame.new(jitter(0.6), -2.5, jitter(0.6)) * CFrame.Angles(jitter(1.5), jitter(1.5), jitter(1.5)), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end
	shatter(kit, root.Position + UP, 8, 14)
	static(kit, root.Position, 16, 1.6, 0.6, 1.4)
	smoke(kit, root.Position - UP * 2.5, 3, 8)
	kit.Vfx.sound("GuardBreak", root)
end

-- The persistent look ------------------------------------------------------------------------------------

-- Faces of a limb that cracks and patches can sit on: offset frame and half extents (u, v)
local function faces(size: Vector3): { { frame: CFrame, u: number, v: number } }
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	return {
		{ frame = CFrame.new(0, 0, -hz - 0.012), u = hx, v = hy },
		{ frame = CFrame.new(0, 0, hz + 0.012) * CFrame.Angles(0, math.pi, 0), u = hx, v = hy },
		{ frame = CFrame.new(hx + 0.012, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), u = hz, v = hy },
		{ frame = CFrame.new(-hx - 0.012, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), u = hz, v = hy },
	}
end

local function welded(look: Instance, limb: BasePart, props: { [string]: any }): BasePart
	local part = Instance.new(props.ClassName or "Part") :: BasePart
	part.Name = props.Name or "SNCorruptPiece"
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = props.Material or GLASS
	part.Color = props.Color or VOID
	part.Reflectance = props.Reflectance or 0
	part.Transparency = 1
	if props.Shape and part:IsA("Part") then
		part.Shape = props.Shape
	end
	part.Size = props.Size
	part.CFrame = limb.CFrame * props.Offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = limb
	weld.Part1 = part
	weld.Parent = part
	part.Parent = look
	return part
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local made = Instance.new("ParticleEmitter")
	made.Name = props.Name or "SNCorruptEmitter"
	made.Texture = props.Texture
	made.Color = props.Color
	made.LightEmission = props.LightEmission or 0
	made.LightInfluence = 0
	made.Size = props.Size
	made.Transparency = props.Transparency
	made.Lifetime = props.Lifetime
	made.Speed = props.Speed
	made.SpreadAngle = props.SpreadAngle or Vector2.new(180, 180)
	made.Acceleration = props.Acceleration or Vector3.zero
	made.Drag = props.Drag or 0
	made.RotSpeed = NumberRange.new(-90, 90)
	made.Rotation = NumberRange.new(0, 360)
	made.Rate = 0
	if props.EmissionDirection then
		made.EmissionDirection = props.EmissionDirection
	end
	made.Parent = parent
	return made
end

function Corruption.appearance(kit)
	local model = kit.model
	local root = kit.root
	if not model then
		return nil
	end
	local degree = kit.degree
	local alive = true
	local isReduced = reduced(kit)
	local seed = 0
	for index = 1, #model.Name do
		seed += string.byte(model.Name, index) * index
	end
	-- Seeded per character, so the same fighter always cracks the same way
	local rng = Random.new(seed * 31 + degree)
	local look = Instance.new("Model")
	look.Name = "SNCorruptionLook"
	look.Parent = model
	local connections: { RBXScriptConnection } = {}
	local loose: { Instance } = {}
	-- Every part with the transparency its overwrite level wants (before any veil)
	local pieces: { { part: BasePart, threshold: number, shown: number } } = {}

	local limbs: { BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
			table.insert(limbs, child)
		end
	end
	local torso = findPart(model, { "UpperTorso", "Torso" }) or root
	local head = findPart(model, { "Head" })

	-- Fractures over the body: more appear the further the overwrite goes
	local crackBudget = if isReduced then 18 else 34
	local made = 0
	local attempts = 0
	while #limbs > 0 and made < crackBudget and attempts < crackBudget * 3 do
		attempts += 1
		local limb = limbs[rng:NextInteger(1, #limbs)]
		local options = faces(limb.Size)
		local face = options[rng:NextInteger(1, #options)]
		local u, v = rng:NextNumber(-0.6, 0.6) * face.u, rng:NextNumber(-0.7, 0.7) * face.v
		local angle = rng:NextNumber(0, math.pi * 2)
		local threshold = 0.02 + made / crackBudget * 0.62
		for segment = 1, rng:NextInteger(2, 3) do
			local length = rng:NextNumber(0.18, 0.42) * math.min(1.5, limb.Size.Y)
			local nextU = u + math.cos(angle) * length
			local nextV = v + math.sin(angle) * length
			if math.abs(nextU) > face.u or math.abs(nextV) > face.v then
				break
			end
			local midU, midV = (u + nextU) / 2, (v + nextV) / 2
			local seam = welded(look, limb, {
				Size = Vector3.new(0.05, length + 0.04, 0.025),
				Offset = face.frame * CFrame.new(midU, midV, 0) * CFrame.Angles(0, 0, angle - math.pi / 2),
				Color = VOID,
				Material = PLASTIC,
			})
			table.insert(pieces, { part = seam, threshold = threshold, shown = 0 })
			-- Light leaks out of some of them
			if segment == 1 and rng:NextNumber() < 0.35 then
				local glow = welded(look, limb, {
					Size = Vector3.new(0.02, length * 0.8, 0.03),
					Offset = face.frame * CFrame.new(midU, midV, 0.004) * CFrame.Angles(0, 0, angle - math.pi / 2),
					Color = GLINT,
					Material = NEON,
				})
				table.insert(pieces, { part = glow, threshold = threshold + 0.05, shown = 0.15 })
			end
			u, v = nextU, nextV
			angle += rng:NextNumber(-0.7, 0.7)
		end
		made += 1
	end

	-- Degree 2 on: glossy black patches spread irregularly over the body
	if degree >= 2 then
		local patchBudget = if isReduced then 10 else 22
		for index = 1, patchBudget do
			if #limbs == 0 then
				break
			end
			local limb = limbs[rng:NextInteger(1, #limbs)]
			local options = faces(limb.Size)
			local face = options[rng:NextInteger(1, #options)]
			local width = face.u * 2 * rng:NextNumber(0.4, 0.95)
			local height = face.v * 2 * rng:NextNumber(0.3, 0.8)
			local u = rng:NextNumber(-1, 1) * (face.u - width / 2)
			local v = rng:NextNumber(-1, 1) * math.max(0, face.v - height / 2)
			local patch = welded(look, limb, {
				Size = Vector3.new(width, height, 0.03),
				Offset = face.frame * CFrame.new(u, v, 0.006 + index * 0.0004) * CFrame.Angles(0, 0, rng:NextNumber(-0.5, 0.5)),
				Color = if index % 4 == 0 then INK else VOID,
				Reflectance = 0.3,
			})
			table.insert(pieces, { part = patch, threshold = 0.3 + index / patchBudget * 0.45, shown = 0 })
		end
	end

	-- Degree 3: a black glass shell over the whole form (opacity follows the overwrite)
	local shells: { BasePart } = {}
	if degree >= 3 then
		for _, limb in limbs do
			local shell = limb:Clone()
			shell:ClearAllChildren()
			shell.Name = "SNShell"
			shell.Anchored = false
			shell.Massless = true
			shell.CanCollide = false
			shell.CanQuery = false
			shell.CanTouch = false
			shell.CastShadow = false
			shell.Material = GLASS
			shell.Color = VOID
			shell.Reflectance = 0.35
			shell.Transparency = 1
			if shell:IsA("MeshPart") then
				shell.TextureID = ""
			end
			shell.Size = limb.Size * 1.03
			shell.CFrame = limb.CFrame
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = limb
			weld.Part1 = shell
			weld.Parent = shell
			shell.Parent = look
			table.insert(shells, shell)
		end
	end

	-- Eyes: darkened at Degree 1, black with lit slits at 2, two points of light at 3
	local eyes: { BasePart } = {}
	if head then
		local scale = head.Size.Y / 1.2
		for side = -1, 1, 2 do
			local offset = CFrame.new(side * 0.19 * scale, 0.12 * scale, -head.Size.Z / 2 - 0.01)
			local socket = welded(look, head, {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.03, (if degree >= 2 then 0.26 else 0.17) * scale, (if degree >= 2 then 0.2 else 0.15) * scale),
				Offset = offset * CFrame.Angles(0, math.rad(90), 0),
				Color = VOID,
				Material = PLASTIC,
			})
			table.insert(pieces, { part = socket, threshold = 0, shown = 0 })
			local light = welded(look, head, {
				Size = if degree >= 3 then Vector3.new(0.08, 0.08, 0.04) * scale elseif degree == 2 then Vector3.new(0.035, 0.16, 0.03) * scale else Vector3.new(0.04, 0.04, 0.02) * scale,
				Offset = offset * CFrame.new(0, 0, -0.012),
				Color = if degree == 2 then GLINT else PALE,
				Material = NEON,
			})
			table.insert(eyes, light)
			table.insert(pieces, { part = light, threshold = 0, shown = if degree >= 3 then 0 else 0.25 })
		end
	end

	-- Particles: black motes always; a distortion haze from Degree 2; dark flames at 3
	local moteEmitter, flames, haze = nil, nil, nil
	if torso then
		moteEmitter = emitter(torso, {
			Name = "SNCorruptMotes",
			Texture = SPARKLE,
			Color = ColorSequence.new(VOID, STATIC),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.6, 1.2),
			Speed = NumberRange.new(0.4, 1.4),
			Acceleration = Vector3.new(0, 1.5, 0),
			Drag = 1,
		})
		table.insert(loose, moteEmitter)
		if degree >= 2 then
			haze = emitter(torso, {
				Name = "SNCorruptHaze",
				Texture = SMOKE,
				Color = ColorSequence.new(INK, VOID),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 3.4) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(1, 1) }),
				Lifetime = NumberRange.new(0.8, 1.3),
				Speed = NumberRange.new(0.2, 0.6),
				Drag = 2,
			})
			table.insert(loose, haze)
		end
		if degree >= 3 then
			flames = emitter(torso, {
				Name = "SNCorruptFlames",
				Texture = FIRE,
				Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, VOID), ColorSequenceKeypoint.new(0.75, INK), ColorSequenceKeypoint.new(1, GLINT) }),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.3), NumberSequenceKeypoint.new(1, 0.15) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
				Lifetime = NumberRange.new(0.5, 0.9),
				Speed = NumberRange.new(2, 4),
				SpreadAngle = Vector2.new(20, 20),
				Acceleration = Vector3.new(0, 6, 0),
				EmissionDirection = Enum.NormalId.Top,
			})
			table.insert(loose, flames)
		end
	end

	-- The silhouette: a flat black fill over everything (accessories too)
	local silhouette = Instance.new("Highlight")
	silhouette.Name = "SNCorruptSilhouette"
	silhouette.FillColor = VOID
	silhouette.OutlineColor = GLINT
	silhouette.FillTransparency = 1
	silhouette.OutlineTransparency = 1
	silhouette.DepthMode = Enum.HighlightDepthMode.Occluded
	silhouette.Enabled = false
	silhouette.Adornee = model
	silhouette.Parent = look

	-- Orbiting fragments (Degree 3 and the final form's halo); local anchored parts
	local orbiters: { { part: BasePart, radius: number, height: number, speed: number, angle: number, tumble: number, halo: boolean } } = {}
	if degree >= 3 or true then
		local total = if isReduced then 6 else 12
		for index = 1, total do
			local halo = index > 5
			local shard = piece("WedgePart", {
				Size = Vector3.new(0.12, rng:NextNumber(0.4, 0.9), rng:NextNumber(0.3, 0.6)),
				CFrame = if root then root.CFrame else CFrame.new(),
				Color = if index % 5 == 0 then GLINT else VOID,
				Material = if index % 5 == 0 then NEON else GLASS,
				Reflectance = 0.45,
				Transparency = 1,
				Life = 1e6,
			})
			table.insert(loose, shard)
			table.insert(orbiters, {
				part = shard,
				radius = if halo then rng:NextNumber(1.3, 1.7) else rng:NextNumber(2.4, 3.2),
				height = if halo then rng:NextNumber(2.1, 2.5) else rng:NextNumber(-1, 1.6),
				speed = (if halo then 1.6 else rng:NextNumber(0.6, 1.1)) * (if rng:NextBoolean() then 1 else -1),
				angle = index / total * math.pi * 2,
				tumble = rng:NextNumber(0.8, 2.4),
				halo = halo,
			})
		end
	end

	-- Overwrite level ------------------------------------------------------------------
	local level = 0
	local inForm = false
	local drained = false
	local veil = 0

	local function serverNow(): number
		return workspace:GetServerTimeNow()
	end

	local function apply()
		for _, entry in pieces do
			local want = if level >= entry.threshold then entry.shown else 1
			if drained and entry.part.Material == NEON then
				want = 1
			end
			local final = 1 - (1 - want) * (1 - veil)
			if entry.part.Transparency ~= final then
				entry.part.Transparency = final
			end
		end
		local shellAlpha = if inForm then 0 else math.clamp(1 - (level - 0.55) / 0.4, 0.05, 1)
		for _, shell in shells do
			shell.Transparency = 1 - (1 - shellAlpha) * (1 - veil)
		end
		for _, eye in eyes do
			eye.Color = if inForm or degree >= 3 then PALE elseif degree == 2 then GLINT else PALE
		end
		local fill = if inForm then 0.03 elseif level < 0.3 then 1 else math.clamp(1 - (level - 0.3) * 1.25, 0.15, 1)
		silhouette.Enabled = fill < 0.99 and veil < 0.5
		silhouette.FillTransparency = fill
		silhouette.OutlineTransparency = if inForm then 0.35 elseif degree >= 3 then 0.8 else 1
		local rateScale = if isReduced then 0.35 else 1
		if moteEmitter then
			moteEmitter.Rate = if drained then 0 else (2 + level * 16) * rateScale
		end
		if haze then
			haze.Rate = if drained then 0 else (if inForm then 10 else level * 8) * rateScale
		end
		if flames then
			flames.Rate = if drained then 0 elseif inForm then 36 * rateScale else math.max(0, (level - 0.55) * 60) * rateScale
		end
	end

	local function refresh()
		if not alive then
			return
		end
		local phase = model:GetAttribute(Attribute.Phase)
		local base = DEF.overwrite.base[math.clamp(degree, 1, #DEF.overwrite.base)]
		level = if typeof(phase) == "number" then math.clamp(phase, 0, 1) else base
		local formUntil = model:GetAttribute(FORM_ATTRIBUTE)
		inForm = typeof(formUntil) == "number" and formUntil > serverNow()
		local lockUntil = model:GetAttribute(LOCK_ATTRIBUTE)
		drained = not inForm and typeof(lockUntil) == "number" and lockUntil > serverNow()
		if inForm then
			level = 1
		elseif (surges[model] or 0) > os.clock() and not drained then
			level = math.min(1, level + 0.12)
		end
		apply()
	end

	for _, name in { Attribute.Phase, FORM_ATTRIBUTE, LOCK_ATTRIBUTE } do
		table.insert(connections, model:GetAttributeChangedSignal(name):Connect(refresh))
	end

	-- Swings and dodges make the overwrite flare (it responds to effort)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local combatEvent = remotes and remotes:FindFirstChild("CombatEvent")
	if combatEvent and combatEvent:IsA("RemoteEvent") then
		table.insert(connections, combatEvent.OnClientEvent:Connect(function(kind, data)
			if typeof(data) ~= "table" then
				return
			end
			if (kind == Protocol.CombatEvent.Attack and data.attacker == model) or (kind == Protocol.CombatEvent.Dodge and data.fighter == model) then
				surge(model, 0.6)
				refresh()
			end
		end))
	end

	-- Per frame: fragments orbit, fast movement leaves afterimages, the final form
	-- doubles its outline, Degree 3 leaves fractures where it walks
	local lastEcho, lastDouble, lastStep, lastSurgeCheck = 0, 0, 0, 0
	local wasSurging = false
	table.insert(connections, RunService.Heartbeat:Connect(function(dt)
		if not alive or not root or not root.Parent then
			return
		end
		local clock = os.clock()
		-- Concealed (Phantasm's fade) hides the look with the body
		local reference = torso or root
		local currentVeil = if reference and reference ~= root then reference.Transparency else 0
		if math.abs(currentVeil - veil) > 0.01 then
			veil = currentVeil
			apply()
		end
		-- Surges and timed states end on their own
		if clock - lastSurgeCheck > 0.15 then
			lastSurgeCheck = clock
			local surging = (surges[model] or 0) > clock
			local formUntil = model:GetAttribute(FORM_ATTRIBUTE)
			local lockUntil = model:GetAttribute(LOCK_ATTRIBUTE)
			local nowForm = typeof(formUntil) == "number" and formUntil > serverNow()
			local nowDrained = not nowForm and typeof(lockUntil) == "number" and lockUntil > serverNow()
			if surging ~= wasSurging or nowForm ~= inForm or nowDrained ~= drained then
				wasSurging = surging
				refresh()
			end
		end
		-- Fragments
		local orbitCount = if inForm then #orbiters elseif degree >= 3 then (if level > 0.85 then 8 else 5) else 0
		for index, orbiter in orbiters do
			local part = orbiter.part
			if not part.Parent then
				continue
			end
			local active = index <= orbitCount and (not orbiter.halo or inForm or index <= orbitCount)
			if not active then
				if part.Transparency < 1 then
					part.Transparency = 1
				end
				continue
			end
			orbiter.angle += orbiter.speed * dt * (if inForm then 1.6 else 1)
			local tilt = if orbiter.halo then 0.35 else 0
			local offset = Vector3.new(math.cos(orbiter.angle) * orbiter.radius, orbiter.height + math.sin(orbiter.angle * 2 + index) * (0.25 + tilt), math.sin(orbiter.angle) * orbiter.radius)
			part.CFrame = CFrame.new(root.Position + offset) * CFrame.Angles(clock * orbiter.tumble, orbiter.angle, clock * orbiter.tumble * 0.6)
			part.Transparency = 1 - (1 - (if part.Material == NEON then 0.2 else 0.05)) * (1 - veil)
		end
		if veil > 0.5 then
			return
		end
		-- Afterimages when moving fast: thin at Degree 1, darker at 2, frozen at 3
		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local interval = if degree >= 3 then 0.08 elseif degree == 2 then 0.1 else 0.14
		if speed > 23 and clock - lastEcho > interval and not isReduced then
			lastEcho = clock
			if degree >= 3 or inForm then
				kit.Vfx.ghostAt(model, nil, VOID, 0.6, GLASS)
			elseif degree == 2 then
				kit.Vfx.ghostAt(model, nil, INK, 0.4, GLASS)
			else
				kit.Vfx.afterimage(model, GLINT)
			end
		end
		-- The final form's outline won't stay in one place
		if inForm and clock - lastDouble > 0.3 and not isReduced then
			lastDouble = clock + random:NextNumber() * 0.15
			kit.Vfx.ghostAt(model, root.CFrame * CFrame.new(jitter(0.5), jitter(0.15), jitter(0.3)), VOID, 0.6, GLASS)
		end
		-- Degree 3: the floor fractures where it walks
		if (degree >= 3 or inForm) and speed > 6 and clock - lastStep > (if inForm then 0.45 else 0.9) then
			lastStep = clock
			fractures(kit, root.Position - UP * 2.9, 2.5, 3, 1.4, { width = 0.12, glow = inForm })
		end
	end))

	refresh()

	return function()
		alive = false
		for _, connection in connections do
			connection:Disconnect()
		end
		for _, item in loose do
			if item.Parent then
				item:Destroy()
			end
		end
		look:Destroy()
		surges[model] = nil
	end
end

return Corruption
