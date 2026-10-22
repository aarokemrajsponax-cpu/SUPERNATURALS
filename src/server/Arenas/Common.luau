-- Shared building blocks for the arena builders (one module per theme in this
-- folder). Two kinds of helpers live here: plain shapes (blocks, cylinders,
-- wedges, lights, signs, particles) with seeded colour variation, and the
-- gameplay structure every arena must have in the same way: the flat fighting
-- floor, invisible boundary walls, corner spawns, throwables and interaction
-- points. Keeping the structure here means MatchService and the powers see the
-- same contract whichever theme is built.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchConfig = require(ReplicatedStorage.Shared.Config.Match)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Common = {}

local ARENA = MatchConfig.Arena

Common.M = Enum.Material
Common.rgb = Color3.fromRGB

-- Small decoration: no shadow. Glow and dressing: no shadow, collision or queries
-- (so it never blocks line of sight or a raycast)
Common.SMALL = { CastShadow = false }
Common.GHOST = { CastShadow = false, CanCollide = false, CanQuery = false, CanTouch = false }

export type Context = {
	id: string,
	model: Model,
	-- Middle of the slot at ground level
	center: Vector3,
	-- Middle of the fighting floor's top surface
	top: Vector3,
	floorY: number,
	-- Half the floor's size (X and Z)
	half: Vector3,
	random: Random,
	spawns: { CFrame },
	terrain: Terrain?,
}

-- Shapes ---------------------------------------------------------------------------------

function Common.part(parent: Instance, props: { [string]: any }): BasePart
	local instance = Instance.new(props.ClassName or "Part") :: BasePart
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	instance.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		if key ~= "ClassName" and key ~= "Size" and key ~= "CFrame" then
			(instance :: any)[key] = value
		end
	end
	instance.Size = props.Size
	instance.CFrame = props.CFrame
	instance.Parent = parent
	return instance
end

function Common.block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local props = if extra then table.clone(extra) else {}
	props.Name = name
	props.Size = size
	props.CFrame = cframe
	props.Color = color
	props.Material = material
	return Common.part(parent, props)
end

-- A cylinder standing along the Y axis of `cframe` (Roblox cylinders run along X)
function Common.cylinder(parent: Instance, name: string, cframe: CFrame, height: number, diameter: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local props = if extra then table.clone(extra) else {}
	props.Shape = Enum.PartType.Cylinder
	return Common.block(parent, name, Vector3.new(height, diameter, diameter), cframe * CFrame.Angles(0, 0, math.rad(90)), color, material, props)
end

-- A round slab whose top is at `top`
function Common.disc(parent: Instance, name: string, top: Vector3, diameter: number, thickness: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	return Common.cylinder(parent, name, CFrame.new(top - Vector3.new(0, thickness / 2, 0)), thickness, diameter, color, material, extra)
end

function Common.ball(parent: Instance, name: string, center: Vector3, diameter: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local props = if extra then table.clone(extra) else {}
	props.Shape = Enum.PartType.Ball
	return Common.block(parent, name, Vector3.one * diameter, CFrame.new(center), color, material, props)
end

-- Wedges: full back (+Z) face, sloping down to the front (-Z)
function Common.wedge(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local props = if extra then table.clone(extra) else {}
	props.ClassName = "WedgePart"
	return Common.block(parent, name, size, cframe, color, material, props)
end

-- Corner wedges: the high point sits over the +X/-Z corner
function Common.cornerWedge(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local props = if extra then table.clone(extra) else {}
	props.ClassName = "CornerWedgePart"
	return Common.block(parent, name, size, cframe, color, material, props)
end

-- A beam-like bar between two points (`width` across, `depth` deep)
function Common.strut(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, depth: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local length = (b - a).Magnitude
	return Common.block(parent, name, Vector3.new(width, depth, length), Common.lookAt((a + b) / 2, b), color, material, extra)
end

-- No two stones the same: nudge the value and warmth a little (seeded, so builds repeat)
function Common.vary(color: Color3, random: Random, amount: number?): Color3
	local spread = amount or 0.05
	local value = 1 + random:NextNumber(-spread, spread)
	local warmth = random:NextNumber(-0.012, 0.012)
	return Color3.new(
		math.clamp(color.R * value + warmth, 0, 1),
		math.clamp(color.G * value, 0, 1),
		math.clamp(color.B * value - warmth, 0, 1)
	)
end

function Common.pick<T>(list: { T }, random: Random): T
	return list[random:NextInteger(1, #list)]
end

-- A frame at `at` whose front (-Z) faces `target` (built from axes so it is
-- right in the test engine as well as in Roblox)
function Common.lookAt(at: Vector3, target: Vector3): CFrame
	local look = (target - at).Unit
	local up = if math.abs(look.Y) > 0.99 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
	local right = look:Cross(up).Unit
	return CFrame.fromMatrix(at, right, right:Cross(look), -look)
end

-- Lights and effects ----------------------------------------------------------------------

function Common.light(parent: Instance, color: Color3, range: number, brightness: number, shadows: boolean?): PointLight
	local point = Instance.new("PointLight")
	point.Color = color
	point.Range = range
	point.Brightness = brightness
	point.Shadows = shadows == true
	point.Parent = parent
	return point
end

function Common.spotLight(parent: Instance, face: Enum.NormalId, color: Color3, range: number, brightness: number, angle: number, shadows: boolean?): SpotLight
	local spot = Instance.new("SpotLight")
	spot.Face = face
	spot.Color = color
	spot.Range = range
	spot.Brightness = brightness
	spot.Angle = angle
	spot.Shadows = shadows == true
	spot.Parent = parent
	return spot
end

function Common.surfaceLight(parent: Instance, face: Enum.NormalId, color: Color3, range: number, brightness: number, angle: number?): SurfaceLight
	local surface = Instance.new("SurfaceLight")
	surface.Face = face
	surface.Color = color
	surface.Range = range
	surface.Brightness = brightness
	surface.Angle = angle or 90
	surface.Parent = parent
	return surface
end

function Common.emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local particles = Instance.new("ParticleEmitter")
	for key, value in props do
		(particles :: any)[key] = value
	end
	particles.Parent = parent
	return particles
end

-- Built-in particle textures (the art direction allows only these)
Common.SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
Common.SMOKE = "rbxasset://textures/particles/smoke_main.dds"
Common.FIRE = "rbxasset://textures/particles/fire_main.dds"

-- Slow, sparse motes that drift up from a part (dust, embers, data, void ash)
function Common.motes(parent: BasePart, color: Color3, rate: number, opts: { [string]: any }?)
	local o = opts or {}
	return Common.emitter(parent, {
		Texture = o.texture or Common.SPARKLES,
		Color = ColorSequence.new(color),
		LightEmission = o.lightEmission or 0.6,
		Rate = rate,
		Lifetime = NumberRange.new(o.minLife or 3, o.maxLife or 6),
		Speed = NumberRange.new(o.minSpeed or 0.4, o.maxSpeed or 1.4),
		SpreadAngle = Vector2.new(o.spread or 40, o.spread or 40),
		Acceleration = o.acceleration or Vector3.new(0, 0.3, 0),
		Drag = o.drag or 0.6,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, o.size or 0.25), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, o.alpha or 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		LockedToPart = false,
	})
end

-- Text on a part face, in Builder Sans, kept off the edges by padding
function Common.sign(parent: BasePart, face: Enum.NormalId, text: string, color: Color3, pixelsPerStud: number, lightInfluence: number?, font: Font?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = lightInfluence or 1
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.FontFace = font or Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = color
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.18, 0)
	padding.PaddingBottom = UDim.new(0.18, 0)
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.Parent = label
	gui.Parent = parent
	return gui
end

-- Gameplay structure ------------------------------------------------------------------------

function Common.context(id: string, center: Vector3, seed: number): Context
	local model = Instance.new("Model")
	model.Name = id
	local floorY = center.Y + 1
	return {
		id = id,
		model = model,
		center = center,
		top = Vector3.new(center.X, floorY, center.Z),
		floorY = floorY,
		half = Vector3.new(ARENA.Size.X / 2, 0, ARENA.Size.Z / 2),
		random = Random.new(seed),
		spawns = {},
		terrain = workspace:FindFirstChildOfClass("Terrain"),
	}
end

-- A point on the floor from shares of the half size: (-1..1, height, -1..1)
function Common.at(ctx: Context, u: number, y: number, v: number): Vector3
	return ctx.top + Vector3.new(u * ctx.half.X, y, v * ctx.half.Z)
end

-- The collision floor: one slab whose top is exactly floorY. Themes lay their
-- visible surface (tiles, plates, glass) on top as non-colliding dressing.
function Common.floor(ctx: Context, color: Color3, material: Enum.Material): BasePart
	return Common.block(ctx.model, "Floor", Vector3.new(ARENA.Size.X, 4, ARENA.Size.Z), CFrame.new(ctx.top - Vector3.new(0, 2, 0)), color, material)
end

-- Invisible walls that keep fighters in. They stay collidable and anchored so
-- knockback can splat a fighter against them.
function Common.barriers(ctx: Context)
	local height = ARENA.WallHeight
	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local alongX = side[2] ~= 0
		local length = if alongX then ARENA.Size.X else ARENA.Size.Z
		local offset = Vector3.new(side[1] * (ctx.half.X + 1.5), height / 2, side[2] * (ctx.half.Z + 1.5))
		local size = if alongX then Vector3.new(length + 8, height, 3) else Vector3.new(3, height, length + 8)
		Common.block(ctx.model, "Barrier", size, CFrame.new(ctx.top + offset), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, {
			Transparency = 1,
			CastShadow = false,
		})
	end
end

-- Four spawns in the corners facing the centre, opposite corners first so a
-- duel starts across the arena. Returns them (also kept on ctx.spawns).
function Common.spawns(ctx: Context, inset: number?): { CFrame }
	local gap = inset or ARENA.SpawnInset
	local corners = { { -1, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 } }
	ctx.spawns = {}
	for _, corner in corners do
		local position = ctx.top + Vector3.new(corner[1] * (ctx.half.X - gap), 3, corner[2] * (ctx.half.Z - gap))
		table.insert(ctx.spawns, Common.lookAt(position, Vector3.new(ctx.top.X, position.Y, ctx.top.Z)))
	end
	return ctx.spawns
end

-- Where each spawn's pad sits on the floor
function Common.spawnBase(spawn: CFrame, floorY: number): Vector3
	return Vector3.new(spawn.Position.X, floorY, spawn.Position.Z)
end

-- Something Strong Dude can lift and throw: one anchored part tagged Throwable,
-- with its Weight (1 light, 2 heavy, 3 enormous) and the spot it returns to.
-- Throwables carry no children (lights or emitters would stay behind when thrown).
function Common.throwable(ctx: Context, name: string, weight: number, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): BasePart
	local prop = Common.block(ctx.model, name, size, cframe, color, material, { Shape = shape or Enum.PartType.Block })
	prop:SetAttribute("Weight", weight)
	prop:SetAttribute("HomeCFrame", prop.CFrame)
	CollectionService:AddTag(prop, Protocol.Tag.Throwable)
	return prop
end

-- Upright cylinder throwable (barrels, drums, pillar sections) standing on `base`
function Common.uprightThrowable(ctx: Context, name: string, weight: number, base: Vector3, height: number, diameter: number, yaw: number, color: Color3, material: Enum.Material): BasePart
	local frame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, yaw, math.rad(90))
	return Common.throwable(ctx, name, weight, Vector3.new(height, diameter, diameter), frame, color, material, Enum.PartType.Cylinder)
end

-- An arena object powers like Syntax can take over. `kind` is "Pylon", "Node" or "Vent".
function Common.interactive(target: Instance, kind: string)
	target:SetAttribute("Interaction", kind)
	CollectionService:AddTag(target, Protocol.Tag.Interactive)
end

-- Terrain ------------------------------------------------------------------------------------

-- The box around a slot that its scenery (and terrain) stays inside
function Common.sceneryRegion(center: Vector3): (CFrame, Vector3)
	local low, high = center + ARENA.SceneryMin, center + ARENA.SceneryMax
	return CFrame.new((low + high) / 2), high - low
end

-- Clear any terrain a previous theme left in this slot
function Common.clearTerrain(center: Vector3)
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local frame, size = Common.sceneryRegion(center)
		pcall(function()
			terrain:FillBlock(frame, size, Enum.Material.Air)
		end)
	end
end

-- Terrain calls never break a build (a missing or odd Terrain just means no scenery)
function Common.fill(ctx: Context, kind: string, ...)
	local terrain = ctx.terrain
	if not terrain then
		return
	end
	local args = table.pack(...)
	pcall(function()
		(terrain :: any)[kind](terrain, table.unpack(args, 1, args.n))
	end)
end

-- Colour of a terrain material that only arenas use (shared materials keep the lobby's)
function Common.terrainColor(ctx: Context, material: Enum.Material, color: Color3)
	local terrain = ctx.terrain
	if terrain then
		pcall(function()
			terrain:SetMaterialColor(material, color)
		end)
	end
end

-- Common props ---------------------------------------------------------------------------------

-- A spread of small chunks around `center` (big-medium-small, rotated, half sunk)
function Common.rubble(ctx: Context, center: Vector3, radius: number, count: number, colors: { Color3 }, material: Enum.Material, scale: number?)
	local random = ctx.random
	local s = scale or 1
	for index = 1, count do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = radius * math.sqrt(random:NextNumber()) * (if index == 1 then 0.2 else 1)
		local size = (if index == 1 then 2.2 elseif index <= 3 then 1.5 else random:NextNumber(0.6, 1.1)) * s
		local chunk = Vector3.new(size * random:NextNumber(0.8, 1.4), size * random:NextNumber(0.5, 0.9), size * random:NextNumber(0.8, 1.3))
		local position = center + Vector3.new(math.cos(angle) * distance, chunk.Y * 0.3, math.sin(angle) * distance)
		local frame = CFrame.new(position) * CFrame.Angles(random:NextNumber(-0.4, 0.4), random:NextNumber(0, 6.28), random:NextNumber(-0.4, 0.4))
		Common.block(ctx.model, "Rubble", chunk, frame, Common.vary(Common.pick(colors, random), random, 0.06), material, Common.SMALL)
	end
end

-- A rough rock: a rotated block with a smaller cap, sunk into the ground
function Common.rock(ctx: Context, base: Vector3, size: Vector3, color: Color3, material: Enum.Material, cap: Color3?): BasePart
	local random = ctx.random
	local frame = CFrame.new(base + Vector3.new(0, size.Y * 0.35, 0)) * CFrame.Angles(random:NextNumber(-0.18, 0.18), random:NextNumber(0, 6.28), random:NextNumber(-0.18, 0.18))
	local body = Common.block(ctx.model, "Rock", size, frame, Common.vary(color, random, 0.06), material)
	if cap then
		local capSize = Vector3.new(size.X * 0.8, 0.5, size.Z * 0.75)
		Common.block(ctx.model, "RockCap", capSize, frame * CFrame.new(random:NextNumber(-0.4, 0.4), size.Y / 2 + 0.05, random:NextNumber(-0.4, 0.4)) * CFrame.Angles(0, random:NextNumber(-0.4, 0.4), 0), Common.vary(cap, random, 0.06), material, Common.SMALL)
	end
	return body
end

-- Rows of stones laid over the floor as dressing (the Floor slab underneath
-- carries collision, its colour shows in the joints). `skip(position)` leaves a
-- stone out (for inlays, holes, worn patches). Returns how many were laid.
export type StoneOptions = {
	colors: { Color3 },
	material: Enum.Material,
	rowMin: number,
	rowMax: number,
	lengthMin: number,
	lengthMax: number,
	gap: number,
	jitter: number?,
	raise: number?,
	skip: ((Vector3, Vector3) -> boolean)?,
}

function Common.flagstones(ctx: Context, o: StoneOptions): number
	local random = ctx.random
	local raise = o.raise or 0.06
	local count = 0
	local z = -ctx.half.Z
	while z < ctx.half.Z - 0.01 do
		local depth = math.min(random:NextNumber(o.rowMin, o.rowMax), ctx.half.Z - z)
		if ctx.half.Z - (z + depth) < o.rowMin * 0.6 then
			depth = ctx.half.Z - z
		end
		local x = -ctx.half.X
		while x < ctx.half.X - 0.01 do
			local length = math.min(random:NextNumber(o.lengthMin, o.lengthMax), ctx.half.X - x)
			if ctx.half.X - (x + length) < o.lengthMin * 0.6 then
				length = ctx.half.X - x
			end
			local size = Vector3.new(length - o.gap, 0.3, depth - o.gap)
			local position = ctx.top + Vector3.new(x + length / 2, raise - 0.15, z + depth / 2)
			if not (o.skip and o.skip(position, size)) then
				count += 1
				-- Neighbours alternate a hair in height so no two tops are coplanar
				local lift = (count % 3) * 0.012
				Common.block(ctx.model, "Stone", size, CFrame.new(position + Vector3.new(0, lift, 0)), Common.vary(Common.pick(o.colors, random), random, o.jitter or 0.04), o.material, Common.GHOST)
			end
			x += length
		end
		z += depth
	end
	return count
end

-- A thin inlaid ring of `count` straight segments lying on the floor at `y`
-- above it. `gaps` lists segment numbers left out (worn away).
function Common.ring(ctx: Context, center: Vector3, radius: number, count: number, width: number, color: Color3, material: Enum.Material, y: number, gaps: { number }?)
	local length = 2 * radius * math.tan(math.pi / count) + width * 0.5
	for index = 1, count do
		if not (gaps and table.find(gaps, index)) then
			local angle = (index - 0.5) / count * math.pi * 2
			local position = center + Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
			Common.block(ctx.model, "Inlay", Vector3.new(width, 0.12, length), CFrame.new(position) * CFrame.Angles(0, -angle, 0), color, material, Common.GHOST)
		end
	end
end

-- A gem standing on one point: a glass shell around a glowing core
function Common.crystal(ctx: Context, center: Vector3, size: number, shell: Color3, core: Color3, yaw: number?): BasePart
	local frame = CFrame.new(center) * CFrame.Angles(0, yaw or 0, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.26))
	local glass = Common.block(ctx.model, "Crystal", Vector3.one * size, frame, shell, Enum.Material.Glass, { Transparency = 0.35, CastShadow = false, Reflectance = 0.1 })
	Common.block(ctx.model, "CrystalCore", Vector3.one * size * 0.5, frame, core, Enum.Material.Neon, Common.GHOST)
	return glass
end

-- A pine: a straight trunk under stacked pyramids of needles
function Common.pine(ctx: Context, base: Vector3, height: number, needles: Color3, bark: Color3, tiers: number?)
	local random = ctx.random
	Common.cylinder(ctx.model, "Trunk", CFrame.new(base + Vector3.new(0, height * 0.22, 0)), height * 0.45, height * 0.06, Common.vary(bark, random, 0.06), Enum.Material.Wood, Common.SMALL)
	local color = Common.vary(needles, random, 0.05)
	local count = tiers or 3
	for tier = 0, count - 1 do
		local width = height * (0.5 - tier * 0.12) * random:NextNumber(0.92, 1.08)
		local tall = height * (0.42 - tier * 0.07)
		local centre = CFrame.new(base + Vector3.new(0, height * (0.16 + tier * 0.22) + tall / 2, 0)) * CFrame.Angles(0, random:NextNumber(0, math.pi / 2), 0)
		local shade = Common.vary(color, random, 0.04)
		for quarter = 0, 3 do
			Common.cornerWedge(ctx.model, "Needles", Vector3.new(width / 2, tall, width / 2), centre * CFrame.Angles(0, quarter * math.pi / 2, 0) * CFrame.new(-width / 4, 0, width / 4), shade, Enum.Material.LeafyGrass, { CanCollide = false })
		end
	end
end

-- Fire in a bowl: warm light, flames and a few embers. Returns the bowl.
function Common.fireBowl(ctx: Context, top: Vector3, diameter: number, metal: Color3, flame: Color3, range: number, brightness: number, shadows: boolean?): BasePart
	local bowl = Common.cylinder(ctx.model, "Bowl", CFrame.new(top - Vector3.new(0, 0.5, 0)), 1, diameter, metal, Enum.Material.CorrodedMetal)
	Common.disc(ctx.model, "Coals", top - Vector3.new(0, 0.12, 0), diameter * 0.82, 0.2, Common.rgb(70, 40, 30), Enum.Material.CrackedLava, Common.GHOST)
	local fire = Instance.new("Fire")
	fire.Size = diameter * 1.1
	fire.Heat = 6
	fire.Color = flame
	fire.SecondaryColor = Color3.new(flame.R * 0.8, flame.G * 0.45, flame.B * 0.3)
	fire.Parent = bowl
	Common.light(bowl, flame, range, brightness, shadows).Name = "Glow"
	Common.motes(bowl, flame, 3, { texture = Common.SPARKLES, minSpeed = 2, maxSpeed = 4, acceleration = Vector3.new(0, 1.5, 0), size = 0.18, minLife = 1.5, maxLife = 3, lightEmission = 1 })
	return bowl
end

return Common
