-- The Nexus: the lobby everyone spawns into. An old stone plaza on a gentle
-- rise in a green valley: weathered paving with thin inlaid rune rings, a
-- crystal held in a carved stone cradle at the centre, statues of the seven
-- powers, five stone gateways (Battle Gate, Training Hall, Homes, Market and
-- Arena View), lanterns, benches, banners and market clutter, and around it
-- terrain hills, cliffs, a pond, worn dirt paths and natural trees.
-- Holiday decorations and the luxury car sit in the plaza too, so the spots
-- they use (SeasonalDecor/Build.luau KEEP_CLEAR) are left open. The terrain
-- stays clear of the arena slots (x >= 330) and the base plots (z < -480).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Powers = require(ReplicatedStorage.Shared.Powers)

local Nexus = {}

local rgb = Color3.fromRGB
local M = Enum.Material

-- Palette: warm stone and timber against the cool green valley, with aged
-- bronze and one soft teal glow (the crystal and its runes) as the accents
local STONE = rgb(162, 148, 128)
local STONE_PALE = rgb(176, 164, 144)
local STONE_GREY = rgb(136, 128, 118)
local STONE_DARK = rgb(110, 101, 90)
local WOOD = rgb(112, 82, 58)
local WOOD_DARK = rgb(74, 55, 40)
local IRON = rgb(58, 56, 54)
local BRONZE = rgb(172, 134, 74)
local GLOW = rgb(128, 212, 202)
local CLOTH = rgb(48, 74, 84)
local LAMP = rgb(255, 184, 118)
local MOSS = rgb(88, 104, 56)
local BARK = rgb(86, 68, 52)
local LEAVES = { rgb(70, 98, 50), rgb(84, 110, 56), rgb(62, 86, 46) }
local AUTUMN = { rgb(150, 100, 56), rgb(132, 84, 48), rgb(160, 124, 66) }
local NEEDLES = { rgb(46, 70, 52), rgb(54, 78, 56), rgb(42, 62, 48) }

-- Small decoration: no shadow. Foliage and glow: no shadow or collision either
local SMALL = { CastShadow = false }
local GHOST = { CastShadow = false, CanCollide = false }
local LEAFY = { CanCollide = false }

Nexus.Radius = 62

-- The gateways: where they stand (angle in degrees from +X, toward +Z), what
-- they do, and their colour. The statues stand on the north side behind the car.
Nexus.Gates = {
	{ id = "Battle", name = "Battle Gate", angle = 0, color = rgb(160, 92, 74), action = "Window:Play", prompt = "Find a fight" },
	{ id = "Training", name = "Training Hall", angle = 180, color = rgb(92, 148, 158), action = "Travel:Training", prompt = "Go to training" },
	{ id = "Homes", name = "Homes", angle = 45, color = rgb(200, 146, 86), action = "Base:Home", prompt = "Go to your base" },
	{ id = "Market", name = "Market", angle = 135, color = rgb(186, 158, 90), action = "Window:Shop", prompt = "Open the shop" },
	{ id = "Watch", name = "Arena View", angle = 90, color = rgb(120, 112, 164), action = "Window:Watch", prompt = "Watch a match" },
}

-- Building blocks ------------------------------------------------------------------------

local function part(parent: Instance, props: { [string]: any }): BasePart
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

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local props = if extra then table.clone(extra) else {}
	props.Name = name
	props.Size = size
	props.CFrame = cframe
	props.Color = color
	props.Material = material
	return part(parent, props)
end

-- A cylinder standing along the Y axis of `cframe` (Roblox cylinders run along X)
local function cylinder(parent: Instance, name: string, cframe: CFrame, height: number, diameter: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local props = if extra then table.clone(extra) else {}
	props.Shape = Enum.PartType.Cylinder
	return block(parent, name, Vector3.new(height, diameter, diameter), cframe * CFrame.Angles(0, 0, math.rad(90)), color, material, props)
end

-- A round slab whose top is at `top`
local function disc(parent: Instance, name: string, top: Vector3, diameter: number, thickness: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	return cylinder(parent, name, CFrame.new(top - Vector3.new(0, thickness / 2, 0)), thickness, diameter, color, material, extra)
end

local function ball(parent: Instance, name: string, center: Vector3, diameter: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local props = if extra then table.clone(extra) else {}
	props.Shape = Enum.PartType.Ball
	return block(parent, name, Vector3.one * diameter, CFrame.new(center), color, material, props)
end

-- Wedges: full back (+Z) face, sloping down to the front (-Z)
local function wedge(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local props = if extra then table.clone(extra) else {}
	props.ClassName = "WedgePart"
	return block(parent, name, size, cframe, color, material, props)
end

-- Corner wedges: the high point sits over the +X/-Z corner
local function cornerWedge(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local props = if extra then table.clone(extra) else {}
	props.ClassName = "CornerWedgePart"
	return block(parent, name, size, cframe, color, material, props)
end

-- No two stones the same: nudge the value and warmth a little (seeded, so builds repeat)
local function vary(color: Color3, random: Random, amount: number?): Color3
	local spread = amount or 0.05
	local value = 1 + random:NextNumber(-spread, spread)
	local warmth = random:NextNumber(-0.012, 0.012)
	return Color3.new(
		math.clamp(color.R * value + warmth, 0, 1),
		math.clamp(color.G * value, 0, 1),
		math.clamp(color.B * value - warmth, 0, 1)
	)
end

local function pick(list: { Color3 }, random: Random): Color3
	return list[random:NextInteger(1, #list)]
end

local function light(parent: Instance, color: Color3, range: number, brightness: number, shadows: boolean?)
	local point = Instance.new("PointLight")
	point.Color = color
	point.Range = range
	point.Brightness = brightness
	point.Shadows = shadows == true
	point.Parent = parent
	return point
end

-- Text on a part face, in Builder Sans, kept off the edges by padding
local function sign(parent: BasePart, face: Enum.NormalId, text: string, color: Color3, pixelsPerStud: number, lightInfluence: number?)
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
	label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = color
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.2, 0)
	padding.PaddingBottom = UDim.new(0.2, 0)
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.Parent = label
	gui.Parent = parent
	return gui
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local particles = Instance.new("ParticleEmitter")
	for key, value in props do
		(particles :: any)[key] = value
	end
	particles.Parent = parent
	return particles
end

-- Same as CFrame.lookAt, built from axes (the test engine's CFrame.lookAt mirrors Z)
local function lookAt(at: Vector3, target: Vector3): CFrame
	local look = (target - at).Unit
	local up = if math.abs(look.Y) > 0.99 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
	local right = look:Cross(up).Unit
	return CFrame.fromMatrix(at, right, right:Cross(look), -look)
end

local function polar(angle: number, radius: number, y: number?): Vector3
	local radians = math.rad(angle)
	return Vector3.new(math.cos(radians) * radius, y or 0, math.sin(radians) * radius)
end

-- A frame at `position` whose front (-Z) faces the plaza centre
local function facingCentre(position: Vector3): CFrame
	return lookAt(position, Vector3.new(0, position.Y, 0))
end

-- Terrain ---------------------------------------------------------------------------------

local GROUND_Y = -1

-- Rolling hills, laid as ridges: { x1, z1, x2, z2, radius, height }. Each
-- ridge is a chain of wide, low, overlapping caps of slightly different
-- sizes, so the land reads as long folds rather than single domes.
local RIDGES = {
	-- North, behind the statues (the view from the spawn)
	{ -260, -250, -60, -230, 110, 14 },
	{ -20, -270, 200, -250, 120, 16 },
	{ -300, -340, 200, -345, 120, 28 },
	-- West, behind the training ground
	{ -290, -200, -300, 160, 120, 24 },
	{ -230, 220, -250, 330, 100, 18 },
	-- South, beyond the pond
	{ -180, 330, 180, 320, 120, 18 },
	{ -120, 400, 150, 410, 120, 26 },
	-- East, either side of the road to the arenas
	{ 170, 90, 230, 200, 90, 13 },
	{ 170, -90, 220, -180, 90, 12 },
	-- Low folds closer in
	{ -40, -150, 110, -175, 80, 6 },
	{ -215, -120, -200, -45, 70, 6 },
	{ 40, 215, 90, 240, 80, 7 },
	{ -60, 250, -150, 235, 80, 7 },
}

-- Every cap of every ridge: { x, z, radius, height }
local HILLS = {}
do
	local random = Random.new(31)
	for _, ridge in RIDGES do
		local from, to = Vector2.new(ridge[1], ridge[2]), Vector2.new(ridge[3], ridge[4])
		local count = math.max(2, math.floor((to - from).Magnitude / (ridge[5] * 0.45)) + 1)
		for index = 0, count - 1 do
			local point = from:Lerp(to, index / (count - 1))
			local side = random:NextNumber(-0.12, 0.12) * ridge[5]
			table.insert(HILLS, { point.X + side, point.Y + side * 0.5, ridge[5] * random:NextNumber(0.85, 1.05), ridge[6] * random:NextNumber(0.7, 1.15) })
		end
	end
end

-- Mountains behind the hills (north, west and south; the east stays open toward
-- the arenas): steeper, with cliff faces toward the valley and rocky crowns
local MOUNTAINS = {
	{ -390, -390, 85, 64 },
	{ -300, -385, 90, 60 },
	{ -190, -390, 85, 72 },
	{ -90, -380, 95, 58 },
	{ 20, -392, 83, 78 },
	{ 120, -383, 92, 62 },
	{ 220, -390, 85, 55 },
	{ -430, -260, 110, 70 },
	{ -440, -120, 100, 85 },
	{ -425, 20, 110, 66 },
	{ -440, 160, 105, 80 },
	{ -420, 300, 115, 62 },
	{ -300, 470, 120, 58 },
	{ -130, 495, 120, 70 },
	{ 40, 485, 115, 56 },
	{ 190, 470, 110, 50 },
}

-- The pond south-west of the plaza: an ellipse inside a rectangular basin
local POND = { x = -62, z = 140, a = 27, b = 19, level = -1.8 }

-- Worn dirt paths: { width, points (x, z) }. They lead out from each gateway.
local PATHS = {
	{ 11, { { 66, 0 }, { 108, 4 }, { 165, -3 }, { 230, 2 }, { 318, 0 } } }, -- Battle: the road to the arenas
	{ 8, { { 47, 47 }, { 74, 77 }, { 98, 110 }, { 116, 158 }, { 136, 214 } } }, -- Homes
	{ 8, { { 0, 66 }, { 4, 100 }, { -4, 128 }, { -12, 170 }, { -8, 220 }, { 6, 280 } } }, -- Arena View
	{ 5, { { -3, 124 }, { -20, 134 }, { -31, 140 } } }, -- down to the jetty
	{ 8, { { -47, 47 }, { -74, 71 }, { -108, 90 }, { -148, 118 }, { -196, 168 } } }, -- Market
	{ 10, { { -66, 0 }, { -76, 0 } } }, -- Training Hall: straight onto the training ground
	{ 8, { { -106, 0 }, { -150, -6 }, { -205, 4 }, { -262, -8 } } }, -- past the training ground
	{ 5, { { -32, -56 }, { -44, -80 }, { -52, -112 }, { -70, -150 } } }, -- north footpaths
	{ 5, { { 32, -56 }, { 46, -82 }, { 50, -115 }, { 72, -150 } } },
}

local function hillTop(hill, x: number, z: number): number?
	local dx, dz = x - hill[1], z - hill[2]
	local radius = hill[3]
	local d2 = dx * dx + dz * dz
	if d2 >= radius * radius then
		return nil
	end
	return GROUND_Y + hill[4] - radius + math.sqrt(radius * radius - d2)
end

-- Height of the land at (x, z), so trees and rocks sit on the hills
local function groundAt(x: number, z: number): number
	local y = GROUND_Y
	for _, list in { HILLS, MOUNTAINS } do
		for _, hill in list do
			local top = hillTop(hill, x, z)
			if top and top > y then
				y = top
			end
		end
	end
	return y
end

local function distanceToSegment(px: number, pz: number, a, b): number
	local abx, abz = b[1] - a[1], b[2] - a[2]
	local t = math.clamp(((px - a[1]) * abx + (pz - a[2]) * abz) / (abx * abx + abz * abz), 0, 1)
	local cx, cz = a[1] + abx * t, a[2] + abz * t
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

-- True when (x, z) is on or next to a path, in the pond, or on the training ground
local function blocked(x: number, z: number, margin: number): boolean
	for _, path in PATHS do
		local points = path[2]
		for index = 1, #points - 1 do
			if distanceToSegment(x, z, points[index], points[index + 1]) < path[1] / 2 + margin then
				return true
			end
		end
	end
	if math.abs(x - POND.x) < 30 + margin and math.abs(z - POND.z) < 22 + margin then
		return true
	end
	if x > -107 - margin and x < -73 + margin and math.abs(z) < 22 + margin then
		return true
	end
	return math.sqrt(x * x + z * z) < 64 + margin
end

local function fillPath(terrain: Terrain, width: number, points, random: Random)
	for index = 1, #points - 1 do
		local a = Vector3.new(points[index][1], 0, points[index][2])
		local b = Vector3.new(points[index + 1][1], 0, points[index + 1][2])
		local middle = (a + b) / 2
		local length = (b - a).Magnitude + width * 0.6
		local top = groundAt(middle.X, middle.Z)
		local frame = lookAt(middle, b)
		-- Packed earth, with a darker trodden line down the middle
		terrain:FillBlock(frame + Vector3.new(0, top - 1.85, 0), Vector3.new(width, 4, length), M.Ground)
		if index > 1 then
			terrain:FillCylinder(CFrame.new(a.X, groundAt(a.X, a.Z) - 1.85, a.Z), 4, width / 2, M.Ground)
		end
		-- Muddy, well-trodden patches here and there
		for _ = 1, math.floor(length / 26) do
			if random:NextNumber() < 0.6 then
				local spot = frame * CFrame.new(random:NextNumber(-0.25, 0.25) * width, 0, random:NextNumber(-0.45, 0.45) * length)
				for blob = 1, 2 do
					local offset = Vector3.new(random:NextNumber(-1.5, 1.5), top - 1.8, random:NextNumber(-2.5, 2.5) * blob)
					terrain:FillCylinder(CFrame.new(spot.Position + offset), 4, width * random:NextNumber(0.14, 0.26), M.Mud)
				end
			end
		end
	end
end

local function buildTerrain(): boolean
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return false
	end
	local ok, err = pcall(function()
		local random = Random.new(23)
		-- The valley floor, in tiles around the pond's basin (x from -380 to 320, z from -470 to 470)
		local floorY = GROUND_Y - 6.5
		local function floor(x0: number, x1: number, z0: number, z1: number)
			local columns, rows = math.ceil((x1 - x0) / 100), math.ceil((z1 - z0) / 100)
			local width, depth = (x1 - x0) / columns, (z1 - z0) / rows
			for column = 0, columns - 1 do
				for row = 0, rows - 1 do
					terrain:FillBlock(CFrame.new(x0 + width * (column + 0.5), floorY, z0 + depth * (row + 0.5)), Vector3.new(width, 13, depth), M.Grass)
				end
			end
		end
		floor(-380, 320, -470, 118)
		floor(-380, 320, 162, 470)
		floor(-380, POND.x - 30, 118, 162)
		floor(POND.x + 30, 320, 118, 162)

		-- Pond: a muddy basin, water, then banks that shape the water into an oval
		terrain:FillBlock(CFrame.new(POND.x, -9.5, POND.z), Vector3.new(60, 9, 44), M.Mud)
		-- Water fills the oval itself (three overlapping round pools), not the whole basin
		for _, offset in { 0, -10, 10 } do
			terrain:FillCylinder(CFrame.new(POND.x + offset, (POND.level - 5) / 2, POND.z), POND.level + 5, if offset == 0 then 18.5 else 15, M.Water)
		end
		for index = 0, 7 do
			local t = index / 8 * math.pi * 2
			local edge = Vector3.new(POND.x + math.cos(t) * POND.a, floorY, POND.z + math.sin(t) * POND.b)
			local normal = Vector3.new(math.cos(t) / POND.a, 0, math.sin(t) / POND.b).Unit
			local center = edge + normal * 12
			terrain:FillBlock(lookAt(center, center + normal) - Vector3.new(0, 0.06, 0), Vector3.new(34, 13, 24), M.Grass)
		end
		-- Low sandy and muddy margins round the water
		for index = 0, 27 do
			local t = index / 28 * math.pi * 2
			local scale = random:NextNumber(1.0, 1.06)
			local center = Vector3.new(POND.x + math.cos(t) * POND.a * scale, GROUND_Y - 0.6, POND.z + math.sin(t) * POND.b * scale)
			terrain:FillCylinder(CFrame.new(center), 1, random:NextNumber(2.4, 3.4), if index % 6 == 0 then M.Ground else M.Sand)
		end
		-- A little sandy landing by the jetty
		terrain:FillBlock(CFrame.new(-31, GROUND_Y - 1.85, 140) * CFrame.Angles(0, 0.3, 0), Vector3.new(9, 4, 12), M.Sand)

		-- Hills, with leafier grass on their crowns
		for _, hill in HILLS do
			local radius, height = hill[3], hill[4]
			local center = Vector3.new(hill[1], GROUND_Y + height - radius, hill[2])
			terrain:FillBall(center, radius, M.Grass)
			if height >= 12 and random:NextNumber() < 0.5 then
				terrain:FillBall(center + Vector3.new(random:NextNumber(-8, 8), 0.5, random:NextNumber(-8, 8)), radius * 0.97, M.LeafyGrass)
			end
		end

		-- Rock outcrops on the bigger hills, bedded in a skirt of bare ground
		for _, hill in HILLS do
			if hill[4] >= 16 and random:NextNumber() < 0.5 then
				for _ = 1, 1 do
					local angle = random:NextNumber(0, math.pi * 2)
					local distance = random:NextNumber(0.15, 0.45) * math.sqrt(hill[3] ^ 2 - (hill[3] - hill[4]) ^ 2)
					local x, z = hill[1] + math.cos(angle) * distance, hill[2] + math.sin(angle) * distance
					if x < 315 and z > -460 then
						local y = groundAt(x, z)
						local size = Vector3.new(random:NextNumber(10, 22), random:NextNumber(8, 15), random:NextNumber(9, 18))
						terrain:FillBall(Vector3.new(x, y - 6, z), size.X * 0.55, M.Ground)
						terrain:FillBlock(
							CFrame.new(x, y + size.Y * 0.15, z) * CFrame.Angles(random:NextNumber(-0.3, 0.3), random:NextNumber(0, 3), random:NextNumber(-0.3, 0.3)),
							size,
							M.Rock
						)
					end
				end
			end
		end
		-- A few weathered outcrops closer in, where players can see them up close
		for _, spot in { { -110, -96 }, { 96, -82 }, { -142, 44 }, { 62, 150 }, { -172, -62 } } do
			local x, z = spot[1], spot[2]
			local y = groundAt(x, z)
			terrain:FillBall(Vector3.new(x, y - 4, z), 7, M.Ground)
			terrain:FillBlock(CFrame.new(x, y + 1.5, z) * CFrame.Angles(random:NextNumber(-0.25, 0.25), random:NextNumber(0, 3), random:NextNumber(-0.25, 0.25)), Vector3.new(random:NextNumber(7, 11), random:NextNumber(5, 8), random:NextNumber(6, 9)), M.Rock)
			terrain:FillBlock(CFrame.new(x + 5, y + 0.5, z + 3) * CFrame.Angles(random:NextNumber(-0.3, 0.3), random:NextNumber(0, 3), random:NextNumber(-0.3, 0.3)), Vector3.new(random:NextNumber(3, 5), random:NextNumber(2.5, 4), random:NextNumber(3, 5)), M.Rock)
		end

		-- Mountains: a grass shoulder, a rocky crown, and a cliff band facing the valley
		for _, mountain in MOUNTAINS do
			local x, z, radius, height = mountain[1], mountain[2], mountain[3], mountain[4]
			local summit = GROUND_Y + height
			terrain:FillBall(Vector3.new(x, summit - radius, z), radius, M.Grass)
			-- One weathered crag breaking the crown
			local crag = Vector3.new(x + random:NextNumber(-0.25, 0.25) * radius, summit - 3, z + random:NextNumber(-0.25, 0.25) * radius)
			terrain:FillBlock(CFrame.new(crag) * CFrame.Angles(random:NextNumber(-0.35, 0.35), random:NextNumber(0, 3), random:NextNumber(-0.35, 0.35)), Vector3.new(radius * 0.3, radius * 0.12, radius * 0.24), M.Slate)
			-- Bare rock on the steep side facing the valley: plates lying along the slope
			local centre = Vector3.new(x, summit - radius, z)
			local toValley = Vector3.new(-x, 0, -z).Unit
			for _ = 1, 3 do
				local spread = random:NextNumber(-0.5, 0.5)
				local out = (toValley + Vector3.new(-toValley.Z, 0, toValley.X) * spread).Unit
				local lift = random:NextNumber(0.35, 0.7)
				local normal = (out * math.sqrt(1 - lift * lift) + Vector3.new(0, lift, 0)).Unit
				if (centre + normal * radius).Y > GROUND_Y + 6 then
					local surface = centre + normal * (radius + 0.8)
					local plate = lookAt(surface, surface + normal) * CFrame.Angles(0, 0, random:NextNumber(0, math.pi))
					terrain:FillBlock(plate, Vector3.new(radius * random:NextNumber(0.4, 0.6), radius * random:NextNumber(0.25, 0.4), 5), if random:NextNumber() < 0.5 then M.Rock else M.Slate)
				end
			end
		end

		-- Paths, then worn and scorched ground in front of the Battle Gate
		for _, path in PATHS do
			fillPath(terrain, path[1], path[2], random)
		end
		for _ = 1, 4 do
			local x, z = random:NextNumber(68, 84), random:NextNumber(-10, 10)
			terrain:FillCylinder(CFrame.new(x, GROUND_Y - 1.85, z), 4, random:NextNumber(2.5, 4.5), M.Mud)
		end
	end)
	if not ok then
		warn("[World] Terrain didn't finish: " .. tostring(err))
	end
	return ok
end

-- Plaza ---------------------------------------------------------------------------------

-- Paving bands from the outside in: { outer radius, colour, material }
local BANDS = {
	{ 58, STONE, M.Pavement },
	{ 52, STONE_DARK, M.Cobblestone },
	{ 46, STONE, M.Pavement },
	{ 40, STONE_PALE, M.Pavement },
	{ 34, STONE_GREY, M.Cobblestone },
	{ 28, STONE, M.Pavement },
	{ 22, STONE_PALE, M.Pavement },
}
local BAND_STEP = 0.02

local function paveTop(radius: number): number
	local top = 0
	for index, band in BANDS do
		if band[1] > radius then
			top = index * BAND_STEP
		end
	end
	return top
end

local function nearGate(angle: number, within: number): boolean
	for _, gate in Nexus.Gates do
		if math.abs(((angle - gate.angle + 180) % 360) - 180) < within then
			return true
		end
	end
	return false
end

-- A ring of short glowing inlays (runes) at `radius`; WorldFx makes them breathe
local function runeRing(folder: Instance, radius: number, count: number, fill: number, top: number, width: number)
	for index = 1, count do
		local angle = (index - 0.5) / count * math.pi * 2
		local length = 2 * math.pi * radius / count * (if index % 4 == 0 then fill * 0.35 else fill)
		local rune = block(
			folder,
			"Rune",
			Vector3.new(width, 0.05, length),
			CFrame.new(math.cos(angle) * radius, top + 0.02, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0),
			GLOW,
			M.Neon,
			{ CastShadow = false, CanCollide = false, Transparency = 0.45 }
		)
		rune:SetAttribute("Pulse", index * 0.4)
	end
end

local function buildPlaza(folder: Instance)
	local random = Random.new(7)
	-- Foundation: the plaza stands a step above the meadow
	disc(folder, "Foundation", Vector3.new(0, -0.05, 0), 125, 3, STONE_DARK, M.Slate)
	for index, band in BANDS do
		disc(folder, "Paving", Vector3.new(0, index * BAND_STEP, 0), band[1] * 2, 0.5, vary(band[2], random, 0.03), band[3])
	end
	-- Radial joints in the two inner rings, offset from each other like laid stone
	for ring, spec in { { 12.4, 22, 20, 0 } } do
		local inner, outer, count, offset = spec[1], spec[2], spec[3], spec[4]
		local top = paveTop((inner + outer) / 2)
		for index = 1, count do
			local angle = (index + offset) / count * math.pi * 2 + ring * 0.05
			local middle = (inner + outer) / 2
			block(
				folder,
				"Joint",
				Vector3.new(outer - inner - 0.3, 0.04, 0.16),
				CFrame.new(math.cos(angle) * middle, top + 0.01, math.sin(angle) * middle) * CFrame.Angles(0, -angle, 0),
				rgb(150, 140, 124),
				M.Slate,
				GHOST
			)
		end
	end
	-- Curb stones round the edge (the gateways' thresholds take their place)
	for index = 1, 40 do
		local angle = (index - 0.5) / 40 * 360
		if not nearGate(angle, 11) then
			local radians = math.rad(angle)
			block(
				folder,
				"Curb",
				Vector3.new(4.5, 0.9, 9.32),
				CFrame.new(math.cos(radians) * 60.25, -0.29 + (index % 2) * 0.04 + random:NextNumber(0, 0.03), math.sin(radians) * 60.25) * CFrame.Angles(0, -radians, 0),
				vary(rgb(150, 138, 120), random, 0.05),
				M.Slate
			)
		end
	end
	-- Thin rune rings: one round the monument, one halfway out
	runeRing(folder, 12.3, 24, 0.62, paveTop(12.3), 0.2)
	runeRing(folder, 34.45, 24, 0.7, paveTop(34.45), 0.24)
	-- History: replaced slabs (some newer and paler, some darker) and a few cracks
	for _ = 1, 20 do
		local radius = random:NextNumber(14, 56)
		local angle = random:NextNumber(0, math.pi * 2)
		local position = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		if (position - Vector3.new(0, 0, -25)).Magnitude > 8 and math.abs(radius - 34.45) > 2 and math.abs(radius - 12.3) > 1.5 then
			local tone = if random:NextNumber() < 0.5 then STONE_PALE else STONE_GREY
			block(
				folder,
				"Slab",
				Vector3.new(random:NextNumber(2.4, 4), 0.06, random:NextNumber(2, 3.4)),
				CFrame.new(position.X, paveTop(radius) + 0.02, position.Z) * CFrame.Angles(0, -angle + random:NextNumber(-0.1, 0.1), 0),
				vary(tone, random, 0.06),
				M.Slate,
				GHOST
			)
		end
	end
	for _ = 1, 8 do
		local radius = random:NextNumber(15, 57)
		local angle = random:NextNumber(0, math.pi * 2)
		block(
			folder,
			"Crack",
			Vector3.new(0.12, 0.03, random:NextNumber(1.5, 3.5)),
			CFrame.new(math.cos(angle) * radius, paveTop(radius) + 0.012, math.sin(angle) * radius) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0),
			rgb(96, 88, 78),
			M.Slate,
			GHOST
		)
	end
	-- Scuffed, darker stone where fighters gather by the Battle Gate
	for _ = 1, 6 do
		local position = Vector3.new(random:NextNumber(48, 57), 0, random:NextNumber(-7, 7))
		block(folder, "Scuff", Vector3.new(random:NextNumber(2, 4), 0.04, random:NextNumber(1.5, 3)), CFrame.new(position.X, paveTop(position.Magnitude) + 0.016, position.Z) * CFrame.Angles(0, random:NextNumber(0, 3), 0), rgb(110, 98, 86), M.Slate, GHOST)
	end
	-- Low steps down onto the north footpaths
	for _, angle in { -120, -60 } do
		local frame = facingCentre(polar(angle, 64))
		block(folder, "Step", Vector3.new(5, 0.6, 2.6), frame * CFrame.new(0, -0.75, 0), vary(STONE_DARK, random), M.Slate)
	end
end

-- Low walls with caps on the plaza's rim, between the gateways
local WALLS = {
	{ 10.5, 34.5 },
	{ 55.5, 79.5 },
	{ 100.5, 124.5 },
	{ 145.5, 169.5 },
	{ -169.5, -124 },
	{ -116, -64 },
	{ -56, -10.5 },
}

local function buildWalls(folder: Instance)
	local random = Random.new(19)
	local radius = 60.8
	local count = 0
	for _, arc in WALLS do
		local from, to = math.rad(arc[1]), math.rad(arc[2])
		local segments = math.max(1, math.floor(math.abs(to - from) * radius / 9 + 0.5))
		local step = (to - from) / segments
		for index = 1, segments do
			count += 1
			local angle = from + step * (index - 0.5)
			local chord = 2 * radius * math.sin(math.abs(step) / 2) + 0.05
			local frame = CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius) * CFrame.Angles(0, -angle + math.pi / 2, 0)
			-- One stretch was knocked down and never rebuilt, one was patched in brick
			local broken = count == 9
			local repaired = count == 20
			local height = (if broken then 1.1 else 2.1) + (index % 2) * 0.06 + random:NextNumber(0, 0.05)
			block(folder, "Wall", Vector3.new(chord, height, 1.6), frame * CFrame.new(0, height / 2 + 0.1, 0), vary(if repaired then rgb(150, 112, 88) else STONE_GREY, random, 0.05), if repaired then M.Brick else M.Cobblestone)
			if broken then
				for _ = 1, 3 do
					local size = Vector3.new(random:NextNumber(0.8, 1.6), random:NextNumber(0.6, 1), random:NextNumber(0.8, 1.4))
					block(folder, "Rubble", size, frame * CFrame.new(random:NextNumber(-3, 3), size.Y / 2 - 0.1, random:NextNumber(-2.4, -1.2)) * CFrame.Angles(random:NextNumber(-0.4, 0.4), random:NextNumber(0, 3), random:NextNumber(-0.4, 0.4)), vary(STONE_GREY, random), M.Cobblestone, SMALL)
				end
			else
				block(folder, "WallCap", Vector3.new(chord + 0.02, 0.4, 2.05), frame * CFrame.new(0, height + 0.3, 0), vary(STONE_PALE, random, 0.04), M.Limestone)
			end
		end
		-- A squared pier at each end of the run
		for _, angle in { from, to } do
			local frame = CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius) * CFrame.Angles(0, -angle + math.pi / 2, 0)
			block(folder, "WallPier", Vector3.new(2.4, 3.0, 2.4), frame * CFrame.new(0, 1.6, 0), vary(STONE, random, 0.04), M.Limestone)
			block(folder, "WallPierCap", Vector3.new(2.8, 0.45, 2.8), frame * CFrame.new(0, 3.32, 0), vary(STONE_PALE, random, 0.03), M.Limestone)
		end
	end
end

-- The monument: a crystal held in a carved stone cradle ------------------------------------

local CRYSTAL_HEIGHT = 14.2

local function buildMonument(folder: Instance)
	local random = Random.new(3)
	disc(folder, "DaisStep", Vector3.new(0, 0.95, 0), 23, 1.1, vary(STONE_GREY, random, 0.03), M.Limestone)
	disc(folder, "DaisStep", Vector3.new(0, 1.85, 0), 18, 1.1, vary(STONE, random, 0.03), M.Limestone)
	runeRing(folder, 8.3, 12, 0.5, 1.85, 0.24)
	-- Pedestal: a moulded foot, an eight-sided body with bronze bands and carved panels, a cap
	disc(folder, "PedestalFoot", Vector3.new(0, 2.95, 0), 9.8, 1.1, vary(STONE_DARK, random, 0.03), M.Slate)
	for index = 0, 1 do
		local turn = CFrame.Angles(0, index * math.pi / 4, 0)
		block(folder, "Pedestal", Vector3.new(6.6, 5.0, 6.6), CFrame.new(0, 5.45, 0) * turn, vary(STONE, random, 0.02), M.Limestone)
		for _, y in { 3.6, 7.45 } do
			block(folder, "Band", Vector3.new(6.82, 0.32, 6.82), CFrame.new(0, y, 0) * turn, BRONZE, M.Metal, SMALL)
		end
	end
	for index = 0, 3 do
		local turn = CFrame.Angles(0, index * math.pi / 2, 0)
		block(folder, "Panel", Vector3.new(2.4, 2.6, 0.12), turn * CFrame.new(0, 5.5, -3.33), vary(STONE_DARK, random, 0.03), M.Slate, SMALL)
	end
	disc(folder, "PedestalCap", Vector3.new(0, 8.85, 0), 8.6, 0.9, vary(STONE_PALE, random, 0.02), M.Limestone)
	runeRing(folder, 2.5, 8, 0.55, 8.85, 0.22)
	-- Four carved claws rise from the cap and lean in to hold the crystal
	for index = 0, 3 do
		local angle = math.rad(45 + index * 90)
		local base = CFrame.Angles(0, -angle, 0) * CFrame.new(3.25, 8.85, 0)
		local lower = base * CFrame.Angles(0, 0, math.rad(-12))
		block(folder, "Claw", Vector3.new(0.8, 3.2, 1.05), lower * CFrame.new(0, 1.6, 0), vary(STONE_GREY, random, 0.03), M.Limestone)
		local knee = lower * CFrame.new(0, 3.2, 0)
		block(folder, "ClawBand", Vector3.new(0.9, 0.34, 1.15), knee, BRONZE, M.Metal, SMALL)
		local upper = knee * CFrame.Angles(0, 0, math.rad(40))
		block(folder, "Claw", Vector3.new(0.62, 3.0, 0.9), upper * CFrame.new(0, 1.45, 0), vary(STONE_GREY, random, 0.03), M.Limestone)
		block(folder, "ClawTip", Vector3.new(0.72, 0.45, 0.98), upper * CFrame.new(0, 3.05, 0), BRONZE, M.Metal, SMALL)
	end
	-- The crystal: a glassy prism with cut ends and a glowing heart, hovering in the claws
	local home = CFrame.new(0, CRYSTAL_HEIGHT, 0) * CFrame.Angles(0, math.rad(45), math.rad(5))
	local glass = { CanCollide = false, CastShadow = false, Transparency = 0.22, Reflectance = 0.1 }
	local crystalColor = rgb(118, 204, 198)
	local crystal = block(folder, "NexusCrystal", Vector3.new(2.6, 5.6, 2.6), home, crystalColor, M.Glass, glass)
	local pieces = { crystal }
	for _, y in { 1, -1 } do
		local flip = if y > 0 then CFrame.new() else CFrame.Angles(0, 0, math.pi)
		table.insert(pieces, wedge(folder, "CrystalTip", Vector3.new(2.6, 2.0, 1.3), home * CFrame.new(0, y * 3.8, -0.65) * flip, crystalColor, M.Glass, glass))
		table.insert(pieces, wedge(folder, "CrystalTip", Vector3.new(2.6, 2.0, 1.3), home * CFrame.new(0, y * 3.8, 0.65) * CFrame.Angles(0, math.pi, 0) * flip, crystalColor, M.Glass, glass))
	end
	local core = block(folder, "NexusCore", Vector3.new(1.1, 4.8, 1.1), home, rgb(176, 240, 228), M.Neon, { CanCollide = false, CastShadow = false, Transparency = 0.15 })
	table.insert(pieces, core)
	for _, piece in pieces do
		piece:SetAttribute("Crystal", true)
	end
	light(core, GLOW, 28, 1.7, true)
	-- A few slow motes drifting off it
	emitter(core, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(rgb(200, 250, 240)),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.28), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.25, 1),
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(0.3, 0.8),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 0.25, 0),
		Drag = 0.6,
		Rate = 3,
	})
	-- Spawn on the plaza just south of the monument, facing it
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "NexusSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.2, 6)
	spawn.CFrame = CFrame.new(0, 0.25, 17)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = folder
	return spawn
end

-- Lanterns ---------------------------------------------------------------------------------

-- A hanging lantern: iron cap, glass body, a small flame and a warm light. `top` is where it hangs.
local function lantern(parent: Instance, top: Vector3, random: Random, shadows: boolean?): BasePart
	local turn = CFrame.new(top) * CFrame.Angles(0, random:NextNumber(0, math.pi / 2), 0)
	block(parent, "LanternCap", Vector3.new(1.2, 0.3, 1.2), turn * CFrame.new(0, -0.15, 0), IRON, M.Metal, SMALL)
	block(parent, "LanternGlass", Vector3.new(0.9, 1.2, 0.9), turn * CFrame.new(0, -0.9, 0), rgb(255, 222, 172), M.Glass, { CastShadow = false, Transparency = 0.45 })
	local flame = block(parent, "LanternFlame", Vector3.new(0.3, 0.5, 0.3), turn * CFrame.new(0, -0.95, 0), rgb(255, 178, 98), M.Neon, GHOST)
	block(parent, "LanternBase", Vector3.new(1.05, 0.25, 1.05), turn * CFrame.new(0, -1.62, 0), IRON, M.Metal, SMALL)
	light(flame, LAMP, 18, 1.25, shadows)
	return flame
end

local function lampPost(folder: Instance, position: Vector3, random: Random, shadows: boolean?)
	local model = Instance.new("Model")
	model.Name = "LampPost"
	local frame = facingCentre(position) * CFrame.Angles(random:NextNumber(-0.02, 0.02), 0, random:NextNumber(-0.02, 0.02))
	block(model, "Footing", Vector3.new(1.6, 0.9, 1.6), frame * CFrame.new(0, 0.45, 0), vary(STONE_DARK, random), M.Slate)
	cylinder(model, "Post", frame * CFrame.new(0, 4.7, 0), 7.6, 0.45, IRON, M.Metal)
	block(model, "Arm", Vector3.new(0.22, 0.22, 1.9), frame * CFrame.new(0, 8.25, -0.85), IRON, M.Metal, SMALL)
	lantern(model, (frame * CFrame.new(0, 8.12, -1.6)).Position, random, shadows)
	model.Parent = folder
end

-- Gateways ---------------------------------------------------------------------------------

local GATE_RADIUS = 61
local GATE_OPENING = 12
local SPRING = 13.65 -- where the arch springs from the piers

local function buildGate(folder: Instance, gate)
	local random = Random.new(100 + gate.angle)
	local model = Instance.new("Model")
	model.Name = "Gate_" .. gate.id
	-- -Z faces the plaza
	local frame = facingCentre(polar(gate.angle, GATE_RADIUS, 0))
	local half = GATE_OPENING / 2
	local pierX = half + 1.8

	block(model, "Threshold", Vector3.new(GATE_OPENING + 11, 1.2, 6), frame * CFrame.new(0, -0.45, 0), vary(STONE_DARK, random, 0.03), M.Slate)
	block(model, "Step", Vector3.new(GATE_OPENING + 4, 0.6, 3.2), frame * CFrame.new(0, -0.75, 4.6), vary(STONE_DARK, random), M.Slate)

	-- Piers: moulded base, shaft with a bronze band, capital, and a lantern on a bracket
	for _, side in { -1, 1 } do
		local x = side * pierX
		block(model, "PierBase", Vector3.new(4.6, 1.4, 4.6), frame * CFrame.new(x, 0.85, 0), vary(STONE_DARK, random, 0.04), M.Slate)
		block(model, "Pier", Vector3.new(3.6, 11.2, 3.6), frame * CFrame.new(x, 7.15, 0), vary(STONE, random, 0.03), M.Limestone)
		block(model, "PierBand", Vector3.new(3.75, 0.35, 3.75), frame * CFrame.new(x, 3.2, 0), BRONZE, M.Metal, SMALL)
		block(model, "Capital", Vector3.new(4.4, 0.9, 4.4), frame * CFrame.new(x, SPRING - 0.45, 0), vary(STONE_PALE, random, 0.03), M.Limestone)
		block(model, "LanternArm", Vector3.new(0.24, 0.24, 1.7), frame * CFrame.new(x, 8.6, -2.65), IRON, M.Metal, SMALL)
		lantern(model, (frame * CFrame.new(x, 8.48, -3.3)).Position, random, false)
	end

	-- A true arch of nine voussoirs with a proud keystone
	local springCentre = frame * CFrame.new(0, SPRING, 0)
	local thickness = 2.6
	for index = 1, 9 do
		local theta = math.pi * (index - 0.5) / 9
		local key = index == 5
		local radial = if key then thickness + 0.6 else thickness
		local tangential = 2 * (half + thickness) * math.sin(math.pi / 18) - 0.08
		local stone = block(
			model,
			if key then "Keystone" else "Voussoir",
			Vector3.new(radial, tangential + (if key then 0.4 else 0), if key then 3.9 else 3.6),
			springCentre * CFrame.Angles(0, 0, theta) * CFrame.new(half + radial / 2, 0, 0),
			vary(if key then STONE_PALE else STONE, random, 0.05),
			M.Limestone
		)
		if key then
			block(model, "KeyPlate", Vector3.new(1.6, 1.0, 0.1), stone.CFrame * CFrame.new(0, 0, -2.0), BRONZE, M.Metal, SMALL)
		end
	end
	-- Timber lintel bound in iron, and a dark stone tympanum filling the arch above it
	block(model, "Lintel", Vector3.new(GATE_OPENING + 0.4, 1.1, 1.6), frame * CFrame.new(0, SPRING - 0.55, 0.2), vary(WOOD, random, 0.04), M.Wood)
	for _, x in { -3.6, 3.6 } do
		block(model, "Strap", Vector3.new(0.35, 1.2, 1.7), frame * CFrame.new(x, SPRING - 0.55, 0.2), IRON, M.Metal, SMALL)
	end
	for row = 0, 3 do
		local bottom = row * 1.5
		local width = 2 * math.sqrt(half * half - bottom * bottom) + 0.3
		local piece = block(model, "Tympanum", Vector3.new(width, 1.5, 1.0), frame * CFrame.new(0, SPRING + bottom + 0.75, 0.2), vary(STONE_DARK, random, 0.03), M.Slate)
		if row == 1 then
			-- Cut into the stone on the outside, for anyone walking back in
			sign(piece, Enum.NormalId.Back, string.upper(gate.name), rgb(206, 188, 150), 36, 1)
		end
	end
	-- Framed sign facing the plaza
	local board = block(model, "SignBoard", Vector3.new(7.4, 1.7, 0.25), frame * CFrame.new(0, SPRING + 2.3, -0.42), vary(WOOD_DARK, random, 0.03), M.WoodPlanks)
	sign(board, Enum.NormalId.Front, string.upper(gate.name), rgb(234, 218, 184), 40, 0.5)
	for _, y in { 0.96, -0.96 } do
		block(model, "SignFrame", Vector3.new(7.8, 0.22, 0.34), frame * CFrame.new(0, SPRING + 2.3 + y, -0.42), BRONZE, M.Metal, SMALL)
	end

	-- The portal: a tinted veil with a faint glow behind it and slow wisps in front
	local tint = gate.color:Lerp(rgb(36, 46, 52), 0.45)
	local portalHeight = SPRING - 1.25
	local portalCentre = frame * CFrame.new(0, 0.15 + portalHeight / 2, 0)
	local portal = block(model, "PortalSurface", Vector3.new(GATE_OPENING - 0.05, portalHeight, 0.2), portalCentre * CFrame.new(0, 0, 0.3), tint, M.Glass, { Transparency = 0.64, CanCollide = false, CastShadow = false })
	local glow = block(model, "PortalGlow", Vector3.new(GATE_OPENING - 0.8, portalHeight - 0.6, 0.05), portalCentre * CFrame.new(0, 0, 0.46), gate.color, M.Neon, { Transparency = 0.93, CanCollide = false, CastShadow = false })
	glow:SetAttribute("Glow", 0.93)
	for index = 1, 3 do
		local angle = index / 3 * math.pi * 2 + random:NextNumber(-0.3, 0.3)
		local wisp = block(
			model,
			"Wisp",
			Vector3.new(0.16, random:NextNumber(1.6, 2.6), 0.05),
			portalCentre * CFrame.new(0, 0, 0.15) * CFrame.Angles(0, 0, angle) * CFrame.new(random:NextNumber(2, 4.4), 0, 0),
			gate.color:Lerp(Color3.new(1, 1, 1), 0.35),
			M.Neon,
			{ Transparency = 0.55, CanCollide = false, CastShadow = false }
		)
		wisp:SetAttribute("Swirl", random:NextNumber(0.35, 0.6))
	end
	emitter(portal, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(gate.color:Lerp(Color3.new(1, 1, 1), 0.45)),
		LightEmission = 0.8,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(0.4, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.3, 1),
		Lifetime = NumberRange.new(2, 3.5),
		Speed = NumberRange.new(0.3, 0.8),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 0.4, 0),
		Rate = 3,
	})
	light(portal, gate.color, 14, 0.8)

	-- What the gate does (WorldService and the client react to the prompt)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GatePrompt"
	prompt.ActionText = gate.prompt
	prompt.ObjectText = gate.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	-- E, F, Q and the gamepad face buttons are combat keys, so the gates use T / D-pad right
	prompt.KeyboardKeyCode = Enum.KeyCode.T
	prompt.GamepadKeyCode = Enum.KeyCode.DPadRight
	prompt:SetAttribute("Action", gate.action)
	prompt.Parent = portal
	model.Parent = folder
	return model
end

-- Statues of the eight powers ------------------------------------------------------------

-- The side of the plaza without gates, 20 degrees apart and clear of the Battle and Training gates
local STATUE_ANGLES = { -160, -140, -120, -100, -80, -60, -40, -20 }

-- A stylised standing figure in the power's colours, toned down toward stone
local function figure(model: Model, base: CFrame, def)
	-- Larger than life: everything below is in a 5-stud figure's units, scaled up
	local k = 1.3
	local function at(offset: CFrame): CFrame
		return base * (CFrame.new(offset.Position * k) * offset.Rotation)
	end
	local body = def.colors.primary:Lerp(rgb(176, 166, 150), 0.5)
	local dark = def.colors.secondary:Lerp(rgb(84, 78, 72), 0.35)
	local accent = def.colors.accent or def.colors.primary
	local glow = { CanCollide = false, CastShadow = false }
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?): BasePart
		return block(model, name, size * k, at(offset), color, material or M.Marble, extra)
	end
	local id = def.id
	piece("Leg", Vector3.new(0.85, 2.7, 0.95), CFrame.new(-0.62, 1.35, 0) * CFrame.Angles(0, 0, math.rad(-5)), dark)
	piece("Leg", Vector3.new(0.85, 2.7, 0.95), CFrame.new(0.62, 1.35, 0) * CFrame.Angles(0, 0, math.rad(5)), dark)
	piece("Hips", Vector3.new(2.0, 0.8, 1.1), CFrame.new(0, 2.95, 0), dark)
	piece("Torso", Vector3.new(1.9, 1.6, 1.05), CFrame.new(0, 4.1, 0), body)
	piece("Chest", Vector3.new(2.5, 1.0, 1.25), CFrame.new(0, 5.15, 0), body)
	ball(model, "Head", at(CFrame.new(0, 6.45, 0)).Position, 1.25 * k, body, M.Marble)
	-- Arms: how far out they swing and whether the forearm comes up, per power
	local pose = {
		StrongDude = { 18, 75 },
		Ghost = { 10, 30 },
		Shapeshifter = { 22, 15 },
		MachineMaster = { 12, 80 },
		Corruption = { 28, 10 },
		Syntax = { 14, 60 },
		Admin = { 8, 45 },
	}
	local swing, raise = 10, 20
	if pose[id] then
		swing, raise = pose[id][1], pose[id][2]
	end
	local hands = {}
	for _, side in { -1, 1 } do
		local shoulder = CFrame.new(side * 1.55, 5.5, 0) * CFrame.Angles(0, 0, math.rad(side * swing))
		piece("Arm", Vector3.new(0.7, 1.6, 0.72), shoulder * CFrame.new(0, -0.8, 0), body)
		local elbow = shoulder * CFrame.new(0, -1.55, 0) * CFrame.Angles(math.rad(if side > 0 then raise else raise * 0.5), 0, math.rad(-side * swing * 0.6))
		piece("Forearm", Vector3.new(0.62, 1.5, 0.66), elbow * CFrame.new(0, -0.72, 0), body)
		hands[side] = elbow * CFrame.new(0, -1.55, 0)
	end
	if id == "StrongDude" then
		for _, side in { -1, 1 } do
			ball(model, "Fist", at(hands[side]).Position, 0.85 * k, accent, M.Neon, glow)
		end
		piece("Belt", Vector3.new(2.1, 0.35, 1.2), CFrame.new(0, 3.42, 0), dark, M.Fabric)
	elseif id == "Ghost" then
		piece("Cloak", Vector3.new(2.6, 4.6, 0.2), CFrame.new(0, 3.9, 0.75) * CFrame.Angles(math.rad(-6), 0, 0), dark, M.Fabric)
		ball(model, "Hood", at(CFrame.new(0, 6.55, 0.22)).Position, 1.5 * k, dark, M.Fabric)
		piece("Blade", Vector3.new(0.14, 3.0, 0.4), hands[1] * CFrame.new(0, -1.2, 0), accent, M.Neon, glow)
	elseif id == "Shapeshifter" then
		for _, side in { -1, 1 } do
			wedge(model, "Ear", Vector3.new(0.3, 0.75, 0.45) * k, at(CFrame.new(side * 0.42, 7.15, 0.1) * CFrame.Angles(0, math.pi, math.rad(side * -12))), dark, M.Marble)
		end
		piece("Muzzle", Vector3.new(0.7, 0.55, 0.7), CFrame.new(0, 6.3, -0.75), body)
		wedge(model, "Tail", Vector3.new(0.4, 0.5, 2.2) * k, at(CFrame.new(0, 2.8, 1.5) * CFrame.Angles(math.rad(-25), 0, 0)), dark, M.Marble)
	elseif id == "MachineMaster" then
		piece("Pack", Vector3.new(1.9, 2.4, 0.9), CFrame.new(0, 4.6, 1.0), dark, M.DiamondPlate)
		piece("Cannon", Vector3.new(0.9, 0.9, 2.2), hands[1] * CFrame.new(0, 0.3, -0.6), dark, M.Metal)
		ball(model, "Lens", at(hands[1] * CFrame.new(0, 0.3, -1.75)).Position, 0.55 * k, accent, M.Neon, glow)
	elseif id == "Corruption" then
		for index = 1, 5 do
			local angle = index / 5 * math.pi * 2
			piece("Shard", Vector3.new(0.22, 0.75, 0.22), CFrame.new(math.cos(angle) * 1.05, 7.3 + math.sin(angle * 2) * 0.15, math.sin(angle) * 1.05) * CFrame.Angles(0, -angle, math.rad(18)), accent, M.Neon, glow)
		end
	elseif id == "Syntax" then
		piece("Pane", Vector3.new(1.8, 1.3, 0.06), hands[1] * CFrame.new(0, -0.2, -1.1) * CFrame.Angles(math.rad(-20), 0, 0), accent, M.Neon, { CanCollide = false, CastShadow = false, Transparency = 0.5 })
		piece("Visor", Vector3.new(1.1, 0.28, 0.2), CFrame.new(0, 6.5, -0.58), accent, M.Neon, glow)
	elseif id == "Admin" then
		for index = 1, 5 do
			local angle = index / 5 * math.pi * 2
			piece("Crown", Vector3.new(0.22, 0.55, 0.22), CFrame.new(math.cos(angle) * 0.5, 7.2, math.sin(angle) * 0.5), BRONZE, M.Metal)
		end
		piece("Staff", Vector3.new(0.26, 6.2, 0.26), CFrame.new(1.95, 3.1, -0.5), BRONZE, M.Metal)
	end
end

local function buildStatues(folder: Instance)
	local random = Random.new(41)
	for index, powerId in Powers.Order do
		local def = Powers.get(powerId)
		local angle = STATUE_ANGLES[index]
		if angle then
			local model = Instance.new("Model")
			model.Name = "Statue_" .. powerId
			local base = facingCentre(polar(angle, 45, 0))
			block(model, "Base", Vector3.new(5.6, 0.7, 5.6), base * CFrame.new(0, 0.35, 0), vary(STONE_DARK, random, 0.03), M.Slate)
			block(model, "Plinth", Vector3.new(4.4, 2.6, 4.4), base * CFrame.new(0, 2.0, 0), vary(STONE, random, 0.04), M.Limestone)
			block(model, "PlinthCap", Vector3.new(5.0, 0.5, 5.0), base * CFrame.new(0, 3.55, 0), vary(STONE_PALE, random, 0.03), M.Limestone)
			local plaque = block(model, "Plaque", Vector3.new(3.4, 0.95, 0.12), base * CFrame.new(0, 2.15, -2.26), BRONZE, M.Metal, SMALL)
			-- A power still being made gets a plain bronze-and-stone figure under its name
			local look = def or { id = powerId, name = (string.gsub(powerId, "(%l)(%u)", "%1 %2")), colors = { primary = rgb(150, 132, 104), secondary = rgb(96, 88, 78) } }
			sign(plaque, Enum.NormalId.Front, string.upper(look.name), rgb(54, 40, 26), 60, 1)
			figure(model, base * CFrame.new(0, 3.8, 0), look)
			model.Parent = folder
		end
	end
end

-- Plaza furniture and the life around the gates -------------------------------------------

local function bench(folder: Instance, frame: CFrame, random: Random)
	for _, x in { -2.1, 2.1 } do
		block(folder, "BenchLeg", Vector3.new(0.7, 1.45, 1.5), frame * CFrame.new(x, 0.75, 0), vary(STONE, random, 0.04), M.Limestone, SMALL)
	end
	for _, z in { -0.42, 0.42 } do
		block(folder, "BenchPlank", Vector3.new(5.6, 0.22, 0.78), frame * CFrame.new(0, 1.58, z) * CFrame.Angles(0, random:NextNumber(-0.012, 0.012), 0), vary(WOOD, random, 0.07), M.WoodPlanks, SMALL)
	end
end

local function planter(folder: Instance, frame: CFrame, random: Random)
	block(folder, "Planter", Vector3.new(4.4, 1.3, 2.3), frame * CFrame.new(0, 0.7, 0), vary(rgb(146, 108, 86), random, 0.04), M.Brick)
	block(folder, "Soil", Vector3.new(4.0, 0.2, 1.9), frame * CFrame.new(0, 1.3, 0), rgb(72, 56, 42), M.Ground, SMALL)
	for index = -1, 1 do
		ball(folder, "Shrub", (frame * CFrame.new(index * 1.25 + random:NextNumber(-0.2, 0.2), 1.75 + random:NextNumber(0, 0.25), random:NextNumber(-0.2, 0.2))).Position, random:NextNumber(1.4, 1.9), vary(pick(LEAVES, random), random, 0.06), M.LeafyGrass, GHOST)
	end
	for _ = 1, 2 do
		ball(folder, "Flowers", (frame * CFrame.new(random:NextNumber(-1.6, 1.6), 2.3, random:NextNumber(-0.6, 0.6))).Position, 0.55, vary(if random:NextNumber() < 0.5 then rgb(196, 122, 74) else rgb(222, 206, 170), random, 0.05), M.Fabric, GHOST)
	end
end

local function banner(folder: Instance, frame: CFrame, random: Random)
	block(folder, "BannerFoot", Vector3.new(1.5, 0.8, 1.5), frame * CFrame.new(0, 0.4, 0), vary(STONE_DARK, random), M.Slate)
	cylinder(folder, "BannerPole", frame * CFrame.new(0, 6.4, 0), 11.2, 0.38, vary(WOOD_DARK, random), M.Wood)
	ball(folder, "Finial", (frame * CFrame.new(0, 12.15, 0)).Position, 0.55, BRONZE, M.Metal, SMALL)
	block(folder, "BannerBar", Vector3.new(3.1, 0.22, 0.22), frame * CFrame.new(0, 11.3, -0.3), vary(WOOD_DARK, random), M.Wood, SMALL)
	local cloth = block(folder, "Banner", Vector3.new(2.7, 5.6, 0.08), frame * CFrame.new(0, 8.4, -0.3) * CFrame.Angles(math.rad(random:NextNumber(-2, 2)), 0, 0), vary(CLOTH, random, 0.03), M.Fabric, SMALL)
	-- The Nexus crest: a bronze lozenge (the crystal) over a bronze band
	block(folder, "Crest", Vector3.new(0.95, 0.95, 0.05), cloth.CFrame * CFrame.new(0, 0.9, -0.065) * CFrame.Angles(0, 0, math.rad(45)), BRONZE, M.Metal, GHOST)
	block(folder, "BannerBand", Vector3.new(2.7, 0.28, 0.05), cloth.CFrame * CFrame.new(0, -2.1, -0.065), BRONZE:Lerp(CLOTH, 0.25), M.Fabric, GHOST)
end

local function noticeBoard(folder: Instance, frame: CFrame, random: Random)
	for _, x in { -2.3, 2.3 } do
		block(folder, "BoardPost", Vector3.new(0.45, 5.9, 0.45), frame * CFrame.new(x, 2.95, 0), vary(WOOD_DARK, random), M.Wood)
	end
	block(folder, "NoticeBoard", Vector3.new(4.8, 3.0, 0.25), frame * CFrame.new(0, 3.6, 0), vary(WOOD, random), M.WoodPlanks)
	block(folder, "BoardRoof", Vector3.new(5.8, 0.7, 0.8), frame * CFrame.new(0, 5.5, -0.4), vary(WOOD_DARK, random), M.WoodPlanks, SMALL)
	block(folder, "BoardRoof", Vector3.new(5.8, 0.7, 0.8), frame * CFrame.new(0, 5.5, 0.4) * CFrame.Angles(0, math.pi, 0), vary(WOOD_DARK, random), M.WoodPlanks, SMALL)
	local notes = { "Duels every night at the Battle Gate", "Lost: one training sword. Ask at the Market", "" }
	for index, text in notes do
		local note = block(
			folder,
			"Notice",
			Vector3.new(random:NextNumber(1.1, 1.4), random:NextNumber(1.3, 1.6), 0.04),
			frame * CFrame.new(-1.5 + (index - 1) * 1.5, 3.6 + random:NextNumber(-0.4, 0.4), -0.15) * CFrame.Angles(0, 0, random:NextNumber(-0.08, 0.08)),
			vary(rgb(226, 214, 188), random, 0.04),
			M.SmoothPlastic,
			GHOST
		)
		if text ~= "" then
			sign(note, Enum.NormalId.Front, text, rgb(58, 46, 36), 50, 1)
		end
	end
end

local function crate(folder: Instance, frame: CFrame, size: number, random: Random)
	block(folder, "Crate", Vector3.one * size, frame * CFrame.new(0, size / 2, 0), vary(WOOD, random, 0.08), M.WoodPlanks)
end

local function barrel(folder: Instance, frame: CFrame, random: Random)
	local color = vary(WOOD, random, 0.06)
	cylinder(folder, "Barrel", frame, 2.6, 1.9, color, M.Wood)
	for _, y in { -0.85, 0.85 } do
		cylinder(folder, "Hoop", frame * CFrame.new(0, y, 0), 0.22, 1.98, IRON, M.Metal, SMALL)
	end
end

local function buildFurniture(folder: Instance)
	local random = Random.new(61)
	-- Each stretch of wall between two gates: a planter, a bench and a lamp
	for _, arc in { { 22.5, 30.5 }, { 67.5, 75.5 }, { 112.5, 121 }, { 157.5, 150 } } do
		planter(folder, facingCentre(polar(arc[1], 57.8, 0)), random)
		bench(folder, facingCentre(polar(arc[1], 54, 0.05)), random)
		lampPost(folder, polar(arc[2], 56.5, 0), random, arc[1] == 112.5)
	end
	lampPost(folder, polar(-165, 56, 0), random, false)
	lampPost(folder, polar(-15, 56, 0), random, true)
	-- Two benches by the monument, facing the crystal
	for _, angle in { -40, -140 } do
		bench(folder, facingCentre(polar(angle, 21, 0.14)), random)
	end
	-- Banners flank the two north footpaths
	for _, angle in { -126, -114, -66, -54 } do
		banner(folder, facingCentre(polar(angle, 58.3, 0)), random)
	end
	noticeBoard(folder, facingCentre(polar(104, 55, 0)), random)

	-- Battle Gate: a rack of wooden practice swords
	local rack = facingCentre(polar(12, 52.5, 0))
	for _, x in { -2, 2 } do
		block(folder, "RackPost", Vector3.new(0.4, 3.4, 0.4), rack * CFrame.new(x, 1.7, 0), vary(WOOD_DARK, random), M.Wood, SMALL)
	end
	block(folder, "RackRail", Vector3.new(4.5, 0.3, 0.3), rack * CFrame.new(0, 2.9, 0), vary(WOOD_DARK, random), M.Wood, SMALL)
	for index = -1, 1 do
		local tilt = rack * CFrame.new(index * 1.2, 1.55, -0.3) * CFrame.Angles(math.rad(-8), 0, math.rad(random:NextNumber(-5, 5)))
		block(folder, "PracticeSword", Vector3.new(0.18, 2.9, 0.42), tilt, vary(WOOD, random, 0.08), M.Wood, SMALL)
		block(folder, "SwordGuard", Vector3.new(0.9, 0.16, 0.22), tilt * CFrame.new(0, 0.85, 0), IRON, M.Metal, SMALL)
	end

	-- Arena View: a brass telescope on a tripod, pointed out over the valley
	local scope = facingCentre(polar(81, 52, 0))
	for index = 0, 2 do
		local angle = index / 3 * math.pi * 2
		block(folder, "TripodLeg", Vector3.new(0.14, 3.3, 0.14), scope * CFrame.new(math.cos(angle) * 0.55, 1.6, math.sin(angle) * 0.55) * CFrame.Angles(math.sin(angle) * 0.3, 0, -math.cos(angle) * 0.3), WOOD_DARK, M.Wood, SMALL)
	end
	local tube = scope * CFrame.new(0, 3.3, 0) * CFrame.Angles(math.rad(-70), 0, 0)
	cylinder(folder, "Telescope", tube, 2.6, 0.42, BRONZE, M.Metal, SMALL)
	cylinder(folder, "Eyepiece", tube * CFrame.new(0, -1.45, 0), 0.4, 0.24, IRON, M.Metal, SMALL)

	-- Market: crates (one cracked open) and barrels
	local stock = facingCentre(polar(127, 54.5, 0))
	crate(folder, stock * CFrame.new(-1.4, 0, 0) * CFrame.Angles(0, 0.1, 0), 2.4, random)
	crate(folder, stock * CFrame.new(1.2, 0, 0.3) * CFrame.Angles(0, -0.2, 0), 2.2, random)
	crate(folder, stock * CFrame.new(-1.2, 2.4, 0.1) * CFrame.Angles(0, 0.5, 0), 1.8, random)
	block(folder, "BrokenCrate", Vector3.new(2.2, 1.1, 2.2), stock * CFrame.new(0.4, 0.55, -2.6) * CFrame.Angles(0, 0.7, 0), vary(WOOD, random, 0.08), M.WoodPlanks, SMALL)
	block(folder, "LoosePlank", Vector3.new(0.6, 0.15, 2.4), stock * CFrame.new(2.3, 0.35, -2.4) * CFrame.Angles(0.25, 0.3, 0.1), vary(WOOD, random, 0.08), M.WoodPlanks, SMALL)
	local cellar = facingCentre(polar(143, 55, 0))
	barrel(folder, cellar * CFrame.new(-1.1, 1.3, 0), random)
	barrel(folder, cellar * CFrame.new(1.1, 1.3, 0.3), random)
	barrel(folder, cellar * CFrame.new(0.2, 0.95, -2.2) * CFrame.Angles(0, 0.4, math.rad(90)), random)

	-- Training Hall: a straw dummy that has seen better days
	local dummy = facingCentre(polar(170, 52, 0)) * CFrame.Angles(0, 0, math.rad(4))
	cylinder(folder, "DummyPost", dummy * CFrame.new(0, 2.6, 0), 5.2, 0.45, vary(WOOD_DARK, random), M.Wood)
	cylinder(folder, "DummyBody", dummy * CFrame.new(0, 3.3, 0), 2.4, 1.6, rgb(190, 164, 110), M.Fabric)
	ball(folder, "DummyHead", (dummy * CFrame.new(0, 5.2, 0)).Position, 1.25, rgb(184, 158, 106), M.Fabric)
	block(folder, "DummyArms", Vector3.new(3.4, 0.32, 0.32), dummy * CFrame.new(0, 4.1, 0) * CFrame.Angles(0, 0, 0.12), vary(WOOD_DARK, random), M.Wood, SMALL)
end

-- Vegetation and rocks ----------------------------------------------------------------------

-- A broadleaf tree: root flare, a trunk in three tapering bent pieces, two branches, a leafy crown
local function tree(folder: Instance, base: Vector3, height: number, random: Random, autumn: boolean?)
	local model = Instance.new("Model")
	model.Name = "Tree"
	local bark = vary(BARK, random, 0.08)
	local trunk = height * 0.12
	cylinder(model, "RootFlare", CFrame.new(base + Vector3.new(0, 0.5, 0)), 1.4, trunk * 1.5, bark, M.Wood)
	for index = 1, 3 do
		local angle = index / 3 * math.pi * 2 + random:NextNumber(-0.4, 0.4)
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local length = trunk * random:NextNumber(1.1, 1.5)
		local rise = trunk * 0.8
		local centre = base + out * (trunk * 0.45 + length / 2) + Vector3.new(0, rise / 2 - 0.25, 0)
		wedge(model, "Root", Vector3.new(trunk * 0.45, rise, length), lookAt(centre, centre + out), bark, M.Wood, SMALL)
	end
	local frame = CFrame.new(base) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0) * CFrame.Angles(random:NextNumber(-0.05, 0.05), 0, random:NextNumber(-0.05, 0.05))
	local joints = {}
	for index, share in { 0.3, 0.24, 0.18 } do
		local length = height * share
		cylinder(model, "Trunk", frame * CFrame.new(0, length / 2, 0), length + 0.4, trunk * (1.12 - index * 0.2), bark, M.Wood)
		frame = frame * CFrame.new(0, length, 0) * CFrame.Angles(random:NextNumber(-0.14, 0.14), 0, random:NextNumber(-0.14, 0.14))
		table.insert(joints, frame)
	end
	local palette = if autumn then AUTUMN else LEAVES
	local function leaves(centre: Vector3, size: number)
		ball(model, "Leaves", centre, size, vary(pick(palette, random), random, 0.06), M.LeafyGrass, LEAFY)
	end
	for index = 1, 2 do
		local length = height * random:NextNumber(0.22, 0.3)
		local branch = joints[index] * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0) * CFrame.Angles(0, 0, math.rad(random:NextNumber(48, 62)))
		cylinder(model, "Branch", branch * CFrame.new(0, length / 2, 0), length, trunk * 0.34, bark, M.Wood, SMALL)
		leaves((branch * CFrame.new(0, length, 0)).Position + Vector3.new(0, height * 0.05, 0), height * random:NextNumber(0.26, 0.32))
	end
	local crown = joints[3].Position + Vector3.new(0, height * 0.06, 0)
	leaves(crown, height * 0.42)
	for index = 1, 4 do
		local angle = index / 4 * math.pi * 2 + random:NextNumber(-0.5, 0.5)
		local reach = height * random:NextNumber(0.14, 0.22)
		leaves(crown + Vector3.new(math.cos(angle) * reach, height * random:NextNumber(-0.08, 0.1), math.sin(angle) * reach), height * random:NextNumber(0.26, 0.36))
	end
	model.Parent = folder
end

-- A pine: a straight trunk under three stacked pyramids of needles
local function pine(folder: Instance, base: Vector3, height: number, random: Random, tiers: number?)
	local model = Instance.new("Model")
	model.Name = "Pine"
	cylinder(model, "Trunk", CFrame.new(base + Vector3.new(0, height * 0.22, 0)), height * 0.45, height * 0.06, vary(rgb(78, 60, 46), random, 0.06), M.Wood)
	local color = vary(pick(NEEDLES, random), random, 0.05)
	for tier = 0, (tiers or 3) - 1 do
		local width = height * (0.5 - tier * 0.12) * random:NextNumber(0.92, 1.08)
		local tall = height * (0.42 - tier * 0.07)
		local centre = CFrame.new(base + Vector3.new(0, height * (0.16 + tier * 0.22) + tall / 2, 0)) * CFrame.Angles(0, random:NextNumber(0, math.pi / 2), 0)
		local shade = vary(color, random, 0.04)
		for quarter = 0, 3 do
			cornerWedge(model, "Needles", Vector3.new(width / 2, tall, width / 2), centre * CFrame.Angles(0, quarter * math.pi / 2, 0) * CFrame.new(-width / 4, 0, width / 4), shade, M.LeafyGrass, LEAFY)
		end
	end
	model.Parent = folder
end

-- A simpler tree for the far hills, where nobody sees the detail
local function farTree(folder: Instance, base: Vector3, height: number, random: Random, autumn: boolean)
	local model = Instance.new("Model")
	model.Name = "FarTree"
	cylinder(model, "Trunk", CFrame.new(base + Vector3.new(0, height * 0.3, 0)), height * 0.6, height * 0.1, vary(BARK, random, 0.06), M.Wood, SMALL)
	local palette = if autumn then AUTUMN else LEAVES
	for index = 1, 2 do
		local offset = Vector3.new(random:NextNumber(-0.15, 0.15) * height, height * (0.6 + index * 0.1), random:NextNumber(-0.15, 0.15) * height)
		ball(model, "Leaves", base + offset, height * random:NextNumber(0.4, 0.52), vary(pick(palette, random), random, 0.05), M.LeafyGrass, LEAFY)
	end
	model.Parent = folder
end

local function rock(folder: Instance, position: Vector3, size: Vector3, random: Random, mossy: boolean)
	local frame = CFrame.new(position) * CFrame.Angles(random:NextNumber(-0.3, 0.3), random:NextNumber(0, math.pi), random:NextNumber(-0.3, 0.3))
	block(folder, "Rock", size, frame, vary(rgb(104, 101, 95), random, 0.07), M.Slate)
	if mossy then
		block(folder, "Moss", Vector3.new(size.X * 0.75, 0.3, size.Z * 0.7), CFrame.new(position + Vector3.new(0, size.Y * 0.42, 0)) * CFrame.Angles(random:NextNumber(-0.1, 0.1), random:NextNumber(0, 3), random:NextNumber(-0.1, 0.1)), vary(MOSS, random, 0.06), M.Grass, GHOST)
	end
end

-- Big, medium and small together, in odd numbers
local function rockCluster(folder: Instance, centre: Vector3, scale: number, random: Random)
	for index, share in { 1, 0.62, 0.38 } do
		local offset = if index == 1 then Vector3.zero else Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)).Unit * scale * random:NextNumber(1.6, 2.2)
		local size = Vector3.new(random:NextNumber(2.6, 3.6), random:NextNumber(1.8, 2.6), random:NextNumber(2.4, 3.2)) * scale * share
		local spot = centre + offset
		rock(folder, Vector3.new(spot.X, groundAt(spot.X, spot.Z) + size.Y * 0.18, spot.Z), size, random, index < 3)
	end
end

local function bush(folder: Instance, position: Vector3, scale: number, random: Random)
	for index = 1, random:NextInteger(2, 3) do
		local offset = Vector3.new(random:NextNumber(-1, 1) * scale, random:NextNumber(0, 0.3) * scale, random:NextNumber(-1, 1) * scale)
		ball(folder, "Bush", position + offset + Vector3.new(0, scale * 0.6, 0), scale * random:NextNumber(1.8, 2.6) / (1 + index * 0.15), vary(pick(LEAVES, random), random, 0.07), M.LeafyGrass, GHOST)
	end
end

-- Near trees: { angle, distance, height, autumn }
local NEAR_TREES = {
	-- Pairs framing the Battle Gate, Homes and Market roads
	{ -12, 76, 14 },
	{ 12, 77, 13 },
	{ 33, 76, 12 },
	{ 57, 77, 14 },
	{ 123, 76, 13, true },
	{ 147, 77, 12 },
	-- Groves
	{ -148, 84, 21 },
	{ -139, 94, 14, true },
	{ -156, 97, 11 },
	{ -144, 104, 9 },
	{ -99, 87, 19 },
	{ -87, 96, 12 },
	{ -92, 106, 9 },
	{ -40, 85, 20 },
	{ -29, 95, 13, true },
	{ -48, 98, 10 },
	{ 22, 90, 18, true },
	{ 31, 99, 11 },
	{ 66, 85, 17 },
	{ 75, 95, 11 },
	{ 108, 84, 15 },
	{ 160, 93, 18 },
	{ 152, 103, 11 },
}

-- Pines a little further out: { angle, distance, height }
local PINES = {
	{ -125, 135, 22 },
	{ -118, 146, 17 },
	{ -131, 151, 13 },
	{ -70, 140, 20 },
	{ -64, 153, 15 },
	{ -170, 150, 20 },
	{ -163, 162, 15 },
	{ -20, 150, 19 },
	{ -12, 162, 14 },
	{ 30, 160, 18 },
	{ 80, 175, 17 },
	{ 145, 168, 19 },
}

local function buildNature(folder: Instance)
	local random = Random.new(73)
	-- Fallen leaves (it's late October): under the turning trees, and blown against the plaza walls
	local function leaf(position: Vector3)
		block(folder, "FallenLeaf", Vector3.new(0.6, 0.04, 0.45), CFrame.new(position) * CFrame.Angles(random:NextNumber(-0.15, 0.15), random:NextNumber(0, math.pi), random:NextNumber(-0.15, 0.15)), vary(pick(AUTUMN, random), random, 0.08), M.Fabric, GHOST)
	end
	for _, spec in NEAR_TREES do
		local spot = polar(spec[1] + random:NextNumber(-2, 2), spec[2])
		tree(folder, Vector3.new(spot.X, groundAt(spot.X, spot.Z) - 0.3, spot.Z), spec[3] * random:NextNumber(0.92, 1.08), random, spec[4] == true)
		if spec[4] then
			for _ = 1, 5 do
				local angle, reach = random:NextNumber(0, math.pi * 2), random:NextNumber(1.5, spec[3] * 0.3)
				leaf(Vector3.new(spot.X + math.cos(angle) * reach, groundAt(spot.X, spot.Z) + 0.05, spot.Z + math.sin(angle) * reach))
			end
		end
	end
	for _ = 1, 10 do
		local angle = random:NextNumber(-170, -10)
		local radius = random:NextNumber(57.2, 59.4)
		if math.abs(angle + 120) > 6 and math.abs(angle + 60) > 6 then
			leaf(polar(angle, radius, paveTop(radius) + 0.04))
		end
	end
	for _, spec in PINES do
		local spot = polar(spec[1] + random:NextNumber(-2, 2), spec[2])
		pine(folder, Vector3.new(spot.X, groundAt(spot.X, spot.Z) - 0.4, spot.Z), spec[3], random)
	end
	-- Woods on the far hills: a few trees on each, kept off the paths and the arena side
	local placed = 0
	for _, hill in HILLS do
		if hill[4] >= 12 then
			local capRadius = math.sqrt(hill[3] ^ 2 - (hill[3] - hill[4]) ^ 2)
			for _ = 1, 3 do
				local angle = random:NextNumber(0, math.pi * 2)
				local distance = random:NextNumber(0.1, 0.75) * capRadius
				local x, z = hill[1] + math.cos(angle) * distance, hill[2] + math.sin(angle) * distance
				if placed < 16 and x < 300 and z > -455 and not blocked(x, z, 6) then
					placed += 1
					local base = Vector3.new(x, groundAt(x, z) - 0.5, z)
					if placed % 3 == 0 then
						pine(folder, base, random:NextNumber(18, 26), random, 2)
					else
						farTree(folder, base, random:NextNumber(14, 20), random, random:NextNumber() < 0.18)
					end
				end
			end
		end
	end
	-- Bushes along the outside of the walls and at the foot of trees
	for _ = 1, 22 do
		local angle = random:NextNumber(-180, 180)
		if not nearGate(angle, 16) and math.abs(angle + 120) > 8 and math.abs(angle + 60) > 8 then
			local spot = polar(angle, random:NextNumber(64.5, 69))
			bush(folder, Vector3.new(spot.X, GROUND_Y - 0.4, spot.Z), random:NextNumber(0.9, 1.4), random)
		end
	end
	-- Rocks with moss caps
	for _, spec in { { -152, 80 }, { -75, 78 }, { -24, 82 }, { 55, 75 }, { 100, 76 }, { 125, 84 }, { -105, 118 } } do
		rockCluster(folder, polar(spec[1], spec[2]), random:NextNumber(0.8, 1.2), random)
	end
end

-- The pond's edge, the wire with the birds, fireflies and mist -----------------------------

local function buildPondside(folder: Instance)
	local random = Random.new(89)
	-- A small jetty on the east bank
	local jetty = CFrame.new(-40, GROUND_Y + 0.05, 140)
	block(folder, "Jetty", Vector3.new(12, 0.3, 3.2), jetty, vary(WOOD, random, 0.05), M.WoodPlanks)
	for _, x in { -5.4, -1, 3.4 } do
		for _, z in { -1.45, 1.45 } do
			block(folder, "JettyPost", Vector3.new(0.4, 3, 0.4), jetty * CFrame.new(x, -1.3, z), vary(WOOD_DARK, random), M.Wood, SMALL)
		end
	end
	cylinder(folder, "Mooring", jetty * CFrame.new(-5.6, 0.8, 1.45), 1.6, 0.5, vary(WOOD_DARK, random), M.Wood, SMALL)
	-- Reeds in clumps along the west and north banks
	for _, spot in { { -86, 134 }, { -83, 149 }, { -56, 122.5 }, { -71, 157 }, { -77, 126 } } do
		for _ = 1, 3 do
			local base = Vector3.new(spot[1] + random:NextNumber(-1.2, 1.2), POND.level, spot[2] + random:NextNumber(-1.2, 1.2))
			local tall = random:NextNumber(2.4, 3.6)
			cylinder(folder, "Reed", CFrame.new(base) * CFrame.Angles(random:NextNumber(-0.15, 0.15), 0, random:NextNumber(-0.15, 0.15)) * CFrame.new(0, tall / 2, 0), tall, 0.16, vary(rgb(122, 128, 72), random, 0.08), M.Grass, GHOST)
		end
	end
	-- Bank stones
	for index = 1, 6 do
		local t = index / 6 * math.pi * 2 + 0.3
		local spot = Vector3.new(POND.x + math.cos(t) * (POND.a + 2.5), GROUND_Y + 0.2, POND.z + math.sin(t) * (POND.b + 2.5))
		if math.abs(spot.X + 36) > 6 or math.abs(spot.Z - 140) > 6 then
			rock(folder, spot, Vector3.new(random:NextNumber(1.6, 2.8), random:NextNumber(1, 1.6), random:NextNumber(1.4, 2.4)), random, index % 2 == 0)
		end
	end
	-- Mist lying on the water, and fireflies over the banks
	local mist = block(folder, "PondMist", Vector3.new(44, 0.2, 30), CFrame.new(POND.x, POND.level + 0.4, POND.z), Color3.new(1, 1, 1), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	emitter(mist, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(rgb(214, 224, 226)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 10) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.86), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(9, 13),
		Speed = NumberRange.new(0.2, 0.5),
		SpreadAngle = Vector2.new(60, 60),
		RotSpeed = NumberRange.new(-6, 6),
		Rate = 1.5,
	})
	for _, spot in { Vector3.new(POND.x, 1.5, POND.z), Vector3.new(-80, 2, -70), Vector3.new(70, 2, 75) } do
		local zone = block(folder, "Fireflies", Vector3.new(30, 3, 24), CFrame.new(spot), Color3.new(1, 1, 1), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
		emitter(zone, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(rgb(226, 236, 150)),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.2), NumberSequenceKeypoint.new(0.7, 0.16), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new(0.1, 1),
			Lifetime = NumberRange.new(4, 7),
			Speed = NumberRange.new(0.2, 0.6),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, 0.1, 0),
			Drag = 1,
			Rate = 2,
		})
	end
	-- A wire on leaning posts along the Arena View path, with a few birds on it
	local posts = { Vector3.new(14, 0, 80), Vector3.new(16, 0, 98), Vector3.new(15, 0, 116), Vector3.new(17, 0, 134) }
	local tops = {}
	for index, base in posts do
		local frame = CFrame.new(base.X, GROUND_Y - 0.5, base.Z) * CFrame.Angles(random:NextNumber(-0.05, 0.05), 0, random:NextNumber(-0.05, 0.05))
		block(folder, "WirePost", Vector3.new(0.45, 6, 0.45), frame * CFrame.new(0, 3, 0), vary(WOOD_DARK, random), M.Wood)
		tops[index] = (frame * CFrame.new(0, 5.6, 0)).Position
	end
	for index = 1, #tops - 1 do
		local a, b = tops[index], tops[index + 1]
		block(folder, "Wire", Vector3.new(0.06, 0.06, (b - a).Magnitude), lookAt((a + b) / 2, b), IRON, M.Metal, GHOST)
	end
	for _, share in { 0.32, 0.4, 0.71 } do
		local spot = tops[2]:Lerp(tops[3], share)
		local facing = CFrame.new(spot) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
		ball(folder, "Bird", (facing * CFrame.new(0, 0.28, 0)).Position, 0.5, vary(rgb(70, 64, 58), random, 0.1), M.SmoothPlastic, GHOST)
		ball(folder, "BirdHead", (facing * CFrame.new(0, 0.6, -0.18)).Position, 0.3, vary(rgb(70, 64, 58), random, 0.1), M.SmoothPlastic, GHOST)
	end
end

-- Builds the whole lobby into `folder`. Returns the spawn location.
function Nexus.build(folder: Instance): SpawnLocation
	if not buildTerrain() then
		-- No terrain (or it failed): a plain grass slab instead
		block(folder, "Ground", Vector3.new(700, 2, 880), CFrame.new(-30, GROUND_Y - 1, 0), rgb(98, 122, 62), M.Grass)
	end
	buildPlaza(folder)
	buildWalls(folder)
	local spawn = buildMonument(folder)
	for _, gate in Nexus.Gates do
		buildGate(folder, gate)
	end
	buildStatues(folder)
	buildFurniture(folder)
	buildNature(folder)
	buildPondside(folder)
	return spawn :: SpawnLocation
end

return Nexus
