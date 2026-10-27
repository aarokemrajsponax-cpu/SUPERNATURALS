-- The Nexus: THE GARDEN of Meridian Station, the lobby everyone spawns into.
-- One enormous indoor habitat hall: four layered walls (concrete plinth,
-- ribbed panels, a service catwalk, a glass observation gallery) under a
-- steel truss vault glazed with glass, and inside it the valley the Meridian
-- Institute grew to keep its volunteers calm: grass, groves, a pond with
-- reeds. The Lantern floats in its containment ring at the centre, the eight
-- programme exhibits stand in an arc to the north, and five bulkhead gates
-- lead off to the station's wings. Around the hall: the Training Wing (a
-- walled building round the training ground ArenaService builds at
-- (-90, 0, 0)), the Lounge on the north wall with the Archive on its lectern
-- and Dr. Varga's study behind a bookshelf, the Calibration Chamber where
-- powers are chosen, the Enhancement Bay by the Commissary, the scorched
-- corner where Door 09 stays shut (its antechamber is reached by a
-- maintenance crawlspace), and ten recovered files hidden for explorers.
-- Holiday decorations and the luxury car use spots on the plaza
-- (SeasonalDecor/Build.luau KEEP_CLEAR), so those stay open, and everything
-- overhead ignores raycasts so decorations still land on the floor.

local CollectionService = game:GetService("CollectionService")

local Nexus = {}

local rgb = Color3.fromRGB
local M = Enum.Material

-- Palette: warm concrete and off-white painted steel (dominant), graphite
-- steel and the valley's greens (secondary), the Lantern's teal and warm
-- lamp amber as the only accents. The Lounge adds oak, leather and linen.
local CONCRETE = rgb(164, 160, 152)
local CONCRETE_DARK = rgb(124, 121, 115)
local PANEL = rgb(200, 201, 196)
local PANEL_SHADE = rgb(180, 183, 180)
local PAVING = rgb(172, 168, 160)
local PAVING_DARK = rgb(104, 104, 102)
local PAVING_LIGHT = rgb(198, 194, 186)
local STEEL = rgb(84, 90, 95)
local STEEL_DARK = rgb(50, 54, 58)
local STEEL_LIGHT = rgb(150, 156, 160)
local GLASS = rgb(170, 196, 200)
local AMBER = rgb(226, 166, 64)
local TEAL = rgb(126, 220, 208)
local SCREEN = rgb(14, 26, 30)
local SCREEN_TEXT = rgb(172, 226, 214)
local SIGN_TEXT = rgb(226, 230, 226)
local LAMP = rgb(255, 196, 140)
local DAYLIGHT = rgb(255, 238, 214)
local WOOD = rgb(128, 90, 60)
local WOOD_DARK = rgb(78, 56, 40)
local WOOD_FLOOR = rgb(146, 104, 70)
local LEATHER = rgb(140, 86, 52)
local VELVET = rgb(58, 84, 70)
local LINEN = rgb(214, 202, 180)
local RUST = rgb(168, 86, 58)
local MUSTARD = rgb(198, 160, 82)
local PLASTER = rgb(198, 186, 168)
local STONE = rgb(122, 118, 112)
local BARK = rgb(86, 68, 52)
local MOSS = rgb(88, 104, 56)
local LEAVES = { rgb(70, 98, 50), rgb(84, 110, 56), rgb(62, 86, 46) }
local AUTUMN = { rgb(150, 100, 56), rgb(132, 84, 48), rgb(160, 124, 66) }
local NEEDLES = { rgb(46, 70, 52), rgb(54, 78, 56), rgb(42, 62, 48) }

local FONT_SANS = "rbxasset://fonts/families/BuilderSans.json"
local FONT_TECH = "rbxasset://fonts/families/Michroma.json"
local FONT_MONO = "rbxasset://fonts/families/RobotoMono.json"

-- Small decoration: no shadow. Foliage and glow: no shadow or collision either.
-- Overhead: no collision and invisible to raycasts (decorations drop onto the floor).
local SMALL = { CastShadow = false }
local GHOST = { CastShadow = false, CanCollide = false }
local LEAFY = { CanCollide = false }
local OVERHEAD = { CanCollide = false, CanQuery = false }
local OVERHEAD_SMALL = { CanCollide = false, CanQuery = false, CastShadow = false }

Nexus.Radius = 44

-- The hall: inner faces of the walls at +-HALF, the vault springing from WALL_TOP
local HALF = 180
local WALL_TOP = 84
-- Columns (and the vault's ribs) stand at these offsets along every wall
local COLUMNS = { -140, -100, -60, -20, 20, 60, 100, 140 }

-- The gateways: bulkhead doors in the walls (the Training Wing's is in its own
-- building). `position` is the middle of the doorway at floor level and
-- `facing` points into the hall; `angle` is the direction from the Lantern.
Nexus.Gates = {
	{ id = "Battle", name = "Test Chambers", sector = "Sector 3", angle = 0, color = rgb(214, 104, 78), action = "Window:Play", prompt = "Find a fight", position = Vector3.new(HALF, 0, 0), facing = Vector3.new(-1, 0, 0) },
	{ id = "Training", name = "Training Wing", sector = "Sector 2", angle = 180, color = rgb(86, 182, 190), action = "Travel:Training", prompt = "Go to training", position = Vector3.new(-60, 0, 0), facing = Vector3.new(1, 0, 0), open = true },
	{ id = "Homes", name = "Residential Wing", sector = "Sector 6", angle = -90, color = rgb(228, 172, 96), action = "Base:Home", prompt = "Go to your base", position = Vector3.new(0, 0, -HALF), facing = Vector3.new(0, 0, 1) },
	{ id = "Market", name = "Commissary", sector = "Sector 5", angle = 66, color = rgb(136, 190, 118), action = "Window:Shop", prompt = "Open the shop", position = Vector3.new(80, 0, HALF), facing = Vector3.new(0, 0, -1) },
	{ id = "Watch", name = "Observation Deck", sector = "Sector 4", angle = 24, color = rgb(136, 146, 226), action = "Window:Watch", prompt = "Watch a match", position = Vector3.new(HALF, 0, 80), facing = Vector3.new(-1, 0, 0) },
}

-- The eight programmes, in the order they began (the exhibits stand west to east in it)
local PROGRAMMES = {
	{ id = "StrongDude", codename = "ATLAS", name = "Strong Dude", note = "Subject T. Reyne. Strength scaling without limit.", color = rgb(255, 150, 72) },
	{ id = "Ghost", codename = "VEIL", name = "The Ghost", note = "Subject R. Takeda. Unseen when watched. Short displacement.", color = rgb(150, 226, 255) },
	{ id = "Shapeshifter", codename = "CHIMERA", name = "Animal Shapeshifter", note = "Subject Dr. N. Okafor. Wolf, hawk, bear. A fourth, once.", color = rgb(156, 212, 112) },
	{ id = "MachineMaster", codename = "FURNACE", name = "Machine Master", note = "Subject D. Malhotra. Cold blue flame. Machines build themselves.", color = rgb(92, 182, 255) },
	{ id = "Syntax", codename = "LATTICE", name = "Syntax", note = "Subject P. Lind. Reads the station as text, and edits it.", color = rgb(112, 230, 172) },
	{ id = "Corruption", codename = "ECLIPSE", name = "Corruption", note = "Subject record redacted. Test halted. See Door 09.", color = rgb(178, 98, 222) },
	{ id = "Admin", codename = "WARDEN", name = "Admin Powers", note = "Not a subject. The station's own command protocol.", color = rgb(236, 204, 122) },
	{ id = "Grandmaster", name = "The Grandmaster", note = "Groundskeeper. Declined. Do not ask again.", color = rgb(150, 172, 160) },
}
Nexus.Programmes = PROGRAMMES

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
	-- Size and position go last so setting Shape can't change them
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

-- Wedges: full back (+Z) and bottom faces, sloping down to the front (-Z)
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

-- No two pieces the same: nudge the value and warmth a little (seeded, so builds repeat)
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

local function light(parent: Instance, color: Color3, range: number, brightness: number, shadows: boolean?): PointLight
	local point = Instance.new("PointLight")
	point.Color = color
	point.Range = range
	point.Brightness = brightness
	point.Shadows = shadows == true
	point.Parent = parent
	return point
end

local function spotLight(parent: Instance, face: Enum.NormalId, color: Color3, range: number, brightness: number, angle: number, shadows: boolean?): SpotLight
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

local function surfaceLight(parent: Instance, face: Enum.NormalId, color: Color3, range: number, brightness: number, angle: number?): SurfaceLight
	local glow = Instance.new("SurfaceLight")
	glow.Face = face
	glow.Color = color
	glow.Range = range
	glow.Brightness = brightness
	glow.Angle = angle or 90
	glow.Parent = parent
	return glow
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

-- A frame at `position` whose front (-Z) faces the Lantern
local function facingCentre(position: Vector3): CFrame
	return lookAt(position, Vector3.new(0, position.Y, 0))
end

-- A beam from `a` to `b` (its length along local Z)
local function strut(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, height: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	return block(parent, name, Vector3.new(width, height, (b - a).Magnitude), lookAt((a + b) / 2, b), color, material, extra)
end

-- A round pipe or cable from `a` to `b`
local function pipe(parent: Instance, name: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local props = if extra then table.clone(extra) else {}
	props.Shape = Enum.PartType.Cylinder
	return block(parent, name, Vector3.new((b - a).Magnitude, diameter, diameter), lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0), color, material, props)
end

-- An axis-aligned box in `frame`'s space, given by its extents
local function box(parent: Instance, name: string, frame: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	return block(parent, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, extra)
end

-- Text on a part face. `glow` makes it self-lit (screens and backlit signs).
local function surface(target: BasePart, face: Enum.NormalId, pixelsPerStud: number, glow: boolean?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = if glow then 0 else 1
	gui.Parent = target
	return gui
end

-- One line of text in a box given as fractions of the face { x, y, width, height }.
-- The size cap keeps every sign in a set at the same type size.
local function line(gui: Instance, text: string, area: { number }, color: Color3, font: string, weight: Enum.FontWeight?, maxSize: number, align: Enum.TextXAlignment?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(area[1], area[2])
	label.Size = UDim2.fromScale(area[3], area[4])
	label.Text = text
	label.FontFace = Font.new(font, weight or Enum.FontWeight.Regular)
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = true
	label.TextXAlignment = align or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = maxSize
	cap.Parent = label
	label.Parent = gui
	return label
end

local function frame(gui: Instance, area: { number }, color: Color3, transparency: number?): Frame
	local panel = Instance.new("Frame")
	panel.BorderSizePixel = 0
	panel.Position = UDim2.fromScale(area[1], area[2])
	panel.Size = UDim2.fromScale(area[3], area[4])
	panel.BackgroundColor3 = color
	panel.BackgroundTransparency = transparency or 0
	panel.Parent = gui
	return panel
end

-- A status screen: a title over lines of readout that scroll slowly upward
-- (WorldFx moves the label; it loops because the lines are written twice).
-- `size` is the face's size in studs, so the type stays the same on every screen.
local function readout(screen: BasePart, face: Enum.NormalId, size: Vector2, title: string, lines: { string }, accent: Color3)
	local pixelsPerStud = 40
	local gui = surface(screen, face, pixelsPerStud, true)
	frame(gui, { 0, 0, 1, 1 }, SCREEN)
	frame(gui, { 0.06, 0.08, 0.012, 0.13 }, accent)
	line(gui, title, { 0.1, 0.06, 0.84, 0.17 }, accent, FONT_TECH, Enum.FontWeight.Regular, 30)
	local clip = frame(gui, { 0.06, 0.3, 0.88, 0.62 }, SCREEN, 1)
	clip.ClipsDescendants = true
	-- Five rows show at once; the rows are written twice so the scroll loops cleanly
	local rowHeight = math.floor(size.Y * pixelsPerStud * 0.62 / 5)
	local rows = Instance.new("Frame")
	rows.Name = "Readout"
	rows.BackgroundTransparency = 1
	rows.Size = UDim2.new(1, 0, 0, rowHeight * #lines * 2)
	rows:SetAttribute("Scroll", rowHeight * #lines)
	for index = 0, #lines * 2 - 1 do
		local row = Instance.new("TextLabel")
		row.BackgroundTransparency = 1
		row.Position = UDim2.new(0, 0, 0, index * rowHeight)
		row.Size = UDim2.new(1, 0, 0, rowHeight)
		row.Text = lines[index % #lines + 1]
		row.FontFace = Font.new(FONT_MONO, Enum.FontWeight.Regular)
		row.TextSize = math.floor(rowHeight * 0.62)
		row.TextColor3 = SCREEN_TEXT
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextTruncate = Enum.TextTruncate.AtEnd
		row.Parent = rows
	end
	rows.Parent = clip
	return gui
end

local function prompt(parent: Instance, actionText: string, objectText: string, action: string, hold: number?, distance: number?): ProximityPrompt
	local proximity = Instance.new("ProximityPrompt")
	proximity.ActionText = actionText
	proximity.ObjectText = objectText
	proximity.HoldDuration = hold or 0
	proximity.MaxActivationDistance = distance or 10
	proximity.RequiresLineOfSight = false
	-- E, F, Q and the gamepad face buttons are combat keys, so everything here uses T / D-pad right
	proximity.KeyboardKeyCode = Enum.KeyCode.T
	proximity.GamepadKeyCode = Enum.KeyCode.DPadRight
	proximity:SetAttribute("Action", action)
	proximity.Parent = parent
	return proximity
end

-- A recovered file: tagged for LoreService, with a prompt that picks it up and a faint blink
local function loreFile(target: BasePart, fileId: string, objectText: string)
	CollectionService:AddTag(target, "SNLoreTerminal")
	target:SetAttribute("LoreId", fileId)
	local proximity = prompt(target, "Read", objectText, "Lore:" .. fileId, 0.4, 8)
	proximity.Name = "LorePrompt"
	return proximity
end

-- Terrain ---------------------------------------------------------------------------------

local GROUND_Y = -1
-- Terrain stays inside this square, clear of the wall plinths
local INNER = 178

-- Gentle mounds: { x, z, radius, height }. Wide and low, so they read as a
-- landscaped valley floor under the roof, never as balls.
local MOUNDS = {
	{ -150, -96, 40, 5 },
	{ -96, -100, 34, 3 },
	{ 124, -100, 42, 5 },
	{ 34, -140, 28, 3 },
	{ 128, 116, 40, 4.5 },
	{ 36, 128, 28, 3 },
	{ -144, 74, 36, 4 },
	{ -24, 152, 30, 3 },
	{ -158, -8, 26, 3 },
}

-- The pond south-west of the plaza: an ellipse inside a rectangular basin
local POND = { x = -72, z = 112, a = 26, b = 17, level = -1.8 }

-- Worn footpaths through the planted areas: { width, points (x, z) }
local FOOTPATHS = {
	{ 6, { { -37, -45 }, { -52, -76 }, { -66, -104 }, { -73, -124 }, { -73, -135 } } }, -- the exhibit walk up to the Lounge stairs
	{ 5, { { -40, 38 }, { -44, 70 }, { -40, 92 }, { -36, 118 } } }, -- plaza down to the pond
	{ 4, { { -38, 120 }, { -52, 136 }, { -76, 138 }, { -100, 132 }, { -112, 116 } } }, -- round the pond's south bank
	{ 4, { { -112, 116 }, { -136, 104 }, { -150, 64 }, { -152, 30 } } }, -- toward the back of the Training Wing
	{ 4, { { -152, 30 }, { -154, -40 }, { -146, -70 } } },
	{ 5, { { 48, -38 }, { 96, -46 }, { 130, -82 }, { 146, -128 }, { 150, -164 } } }, -- out to the scorched corner
	{ 4, { { 118, -150 }, { 122, -172 } } }, -- the crawlspace's grate
}

local function hillTop(hill, x: number, z: number): number?
	local dx, dz = x - hill[1], z - hill[2]
	local radius = hill[3]
	local d2 = dx * dx + dz * dz
	if d2 >= radius * radius then
		return nil
	end
	-- A smooth bump (cosine falloff) rather than a spherical cap
	return GROUND_Y + hill[4] * (0.5 + 0.5 * math.cos(math.pi * math.sqrt(d2) / radius))
end

-- Height of the land at (x, z), so trees and rocks sit on the mounds
local function groundAt(x: number, z: number): number
	local y = GROUND_Y
	for _, hill in MOUNDS do
		local top = hillTop(hill, x, z)
		if top and top > y then
			y = top
		end
	end
	return y
end

local function fillPath(terrain: Terrain, width: number, points)
	for index = 1, #points - 1 do
		local a = Vector3.new(points[index][1], 0, points[index][2])
		local b = Vector3.new(points[index + 1][1], 0, points[index + 1][2])
		local middle = (a + b) / 2
		local length = (b - a).Magnitude + width * 0.4
		local top = math.max(groundAt(a.X, a.Z), groundAt(middle.X, middle.Z), groundAt(b.X, b.Z))
		terrain:FillBlock(lookAt(middle, b) + Vector3.new(0, top - 1.9, 0), Vector3.new(width, 4, length), M.Ground)
		terrain:FillCylinder(CFrame.new(b.X, groundAt(b.X, b.Z) - 1.9, b.Z), 4, width / 2, M.Ground)
	end
end

local function buildTerrain(): boolean
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return false
	end
	local ok, err = pcall(function()
		local random = Random.new(23)
		-- The valley floor, in tiles around the pond's basin
		local floorY = GROUND_Y - 6.5
		local function floor(x0: number, x1: number, z0: number, z1: number)
			local columns, rows = math.ceil((x1 - x0) / 90), math.ceil((z1 - z0) / 90)
			local width, depth = (x1 - x0) / columns, (z1 - z0) / rows
			for column = 0, columns - 1 do
				for row = 0, rows - 1 do
					terrain:FillBlock(CFrame.new(x0 + width * (column + 0.5), floorY, z0 + depth * (row + 0.5)), Vector3.new(width, 13, depth), M.Grass)
				end
			end
		end
		local px0, px1, pz0, pz1 = POND.x - 30, POND.x + 30, POND.z - 21, POND.z + 21
		floor(-INNER, INNER, -INNER, pz0)
		floor(-INNER, INNER, pz1, INNER)
		floor(-INNER, px0, pz0, pz1)
		floor(px1, INNER, pz0, pz1)

		-- Pond: a muddy basin, water in an oval, banks shaping it
		terrain:FillBlock(CFrame.new(POND.x, -9.5, POND.z), Vector3.new(60, 9, 42), M.Mud)
		for _, offset in { 0, -10, 10 } do
			terrain:FillCylinder(CFrame.new(POND.x + offset, (POND.level - 5) / 2, POND.z), POND.level + 5, if offset == 0 then 17 else 14, M.Water)
		end
		for index = 0, 7 do
			local t = index / 8 * math.pi * 2
			local edge = Vector3.new(POND.x + math.cos(t) * POND.a, floorY, POND.z + math.sin(t) * POND.b)
			local normal = Vector3.new(math.cos(t) / POND.a, 0, math.sin(t) / POND.b).Unit
			local center = edge + normal * 12
			terrain:FillBlock(lookAt(center, center + normal) - Vector3.new(0, 0.06, 0), Vector3.new(34, 13, 24), M.Grass)
		end
		for index = 0, 23 do
			local t = index / 24 * math.pi * 2
			local scale = random:NextNumber(1.0, 1.06)
			local center = Vector3.new(POND.x + math.cos(t) * POND.a * scale, GROUND_Y - 0.6, POND.z + math.sin(t) * POND.b * scale)
			terrain:FillCylinder(CFrame.new(center), 1, random:NextNumber(2.4, 3.4), if index % 6 == 0 then M.Ground else M.Sand)
		end

		-- Mounds: stacked low discs following the bump, leafier grass on the crowns
		for _, hill in MOUNDS do
			local x, z, radius, height = hill[1], hill[2], hill[3], hill[4]
			for step = 1, 4 do
				local share = step / 4
				local ring = radius * math.acos(2 * share - 1) / math.pi
				local top = GROUND_Y + height * share
				terrain:FillCylinder(CFrame.new(x, top - 2, z), 4, ring, if step == 4 and height >= 4 then M.LeafyGrass else M.Grass)
			end
		end

		for _, path in FOOTPATHS do
			fillPath(terrain, path[1], path[2])
		end
		-- Leafy, flowering patches where the planting is thickest
		for _, spot in { { -120, -70 }, { 96, -150 }, { 150, 60 }, { -120, 150 }, { 20, 100 }, { -150, 120 } } do
			terrain:FillCylinder(CFrame.new(spot[1], groundAt(spot[1], spot[2]) - 1.95, spot[2]), 4, random:NextNumber(9, 14), M.LeafyGrass)
		end
	end)
	if not ok then
		warn("[World] Terrain didn't finish: " .. tostring(err))
	end
	return ok
end

-- The hall: walls, roof and the light rigs -----------------------------------------------

-- Each wall's frame: its middle on the inner face at floor level, -Z into the hall, X along it
local WALL_CENTRES = {
	North = Vector3.new(0, 0, -HALF),
	South = Vector3.new(0, 0, HALF),
	East = Vector3.new(HALF, 0, 0),
	West = Vector3.new(-HALF, 0, 0),
}

local function wallFrame(side: string): CFrame
	return lookAt(WALL_CENTRES[side], Vector3.zero)
end

-- Openings cut into the walls: { side, at (world position), width, sill, top }.
-- Gates take a 20-wide slot; the study door and the crawlspace are smaller.
local OPENINGS = {
	{ side = "North", at = Vector3.new(-114, 0, -HALF), width = 8, sill = 8, top = 20 }, -- Varga's study, behind the Lounge's bookshelf
	{ side = "North", at = Vector3.new(160, 0, -HALF), width = 20, sill = -7, top = 20 }, -- Door 09
	{ side = "North", at = Vector3.new(120, 0, -HALF), width = 5, sill = -7, top = 6.5 }, -- the maintenance crawlspace
}
for _, gate in Nexus.Gates do
	if not gate.open then
		local side = if gate.facing.X < 0 then "East" elseif gate.facing.X > 0 then "West" elseif gate.facing.Z > 0 then "North" else "South"
		table.insert(OPENINGS, { side = side, at = gate.position, width = 20, sill = -7, top = 20 })
	end
end

-- Stretches of the wall between openings: those that reach above `y0` and below `y1` cut it
local function wallRuns(openings, y0: number, y1: number): { { number } }
	local cuts = {}
	for _, opening in openings do
		if opening.top > y0 and opening.sill < y1 then
			table.insert(cuts, { opening.x - opening.width / 2, opening.x + opening.width / 2 })
		end
	end
	table.sort(cuts, function(a, b)
		return a[1] < b[1]
	end)
	local result, at = {}, -HALF
	for _, cut in cuts do
		if cut[1] > at + 0.5 then
			table.insert(result, { at, cut[1] })
		end
		at = math.max(at, cut[2])
	end
	if HALF > at + 0.5 then
		table.insert(result, { at, HALF })
	end
	return result
end

-- Lengths of wall the Lounge covers (no column footings poke into it)
local function insideLounge(side: string, x: number): boolean
	return side == "North" and x > -130 and x < -50
end

local function buildWall(folder: Instance, side: string, random: Random)
	local model = Instance.new("Model")
	model.Name = "Wall" .. side
	local f = wallFrame(side)
	local openings = {}
	for _, opening in OPENINGS do
		if opening.side == side then
			local x = f:PointToObjectSpace(opening.at).X
			table.insert(openings, { x = x, width = opening.width, sill = opening.sill, top = opening.top })
		end
	end
	local function inOpening(x: number, y: number, margin: number): boolean
		for _, opening in openings do
			if math.abs(x - opening.x) < opening.width / 2 + margin and y > opening.sill and y < opening.top then
				return true
			end
		end
		return false
	end

	-- Concrete plinth, a step proud of the panels, with a chamfered top
	for _, run in wallRuns(openings, -7, 8) do
		box(model, "Plinth", f, run[1], run[2], -7, 8, -1, 4, vary(CONCRETE, random, 0.02), M.Concrete)
		wedge(model, "PlinthChamfer", Vector3.new(run[2] - run[1], 0.8, 1), f * CFrame.new((run[1] + run[2]) / 2, 8.4, -0.5), vary(CONCRETE, random, 0.02), M.Concrete, SMALL)
	end
	-- Lintels over the small openings that don't reach the panels
	for _, opening in openings do
		if opening.top < 8 then
			box(model, "Plinth", f, opening.x - opening.width / 2, opening.x + opening.width / 2, opening.top, 8, -1, 4, vary(CONCRETE, random, 0.02), M.Concrete)
		end
	end
	-- Lower panel field in two courses (the doorways cut the first), with ribs
	for _, run in wallRuns(openings, 8, 20) do
		box(model, "Panel", f, run[1], run[2], 8, 20, 0, 2, vary(PANEL, random, 0.015), M.Metal)
	end
	box(model, "Panel", f, -HALF, HALF, 20, 33, 0, 2, vary(PANEL, random, 0.015), M.Metal)
	for index, column in { -HALF, table.unpack(COLUMNS) } do
		for _, step in { 10, 20, 30 } do
			local x = column + step
			if not inOpening(x, 10, 1) and not (index == 1 and step == 10) then
				box(model, "Rib", f, x - 0.4, x + 0.4, 8.6, 32.6, -0.4, 0, PANEL_SHADE, M.Metal, SMALL)
			end
		end
	end

	-- The service catwalk: plate deck, fascia, railing, and brackets at each column
	box(model, "Catwalk", f, -173, 173, 33, 33.6, -6, 0, STEEL, M.DiamondPlate)
	box(model, "CatwalkFascia", f, -173, 173, 32.2, 33.6, -6.3, -5.7, STEEL_DARK, M.Metal, SMALL)
	box(model, "Handrail", f, -173, 173, 36.9, 37.2, -5.95, -5.65, STEEL_LIGHT, M.Metal, SMALL)
	box(model, "MidRail", f, -173, 173, 35.1, 35.3, -5.92, -5.68, STEEL_LIGHT, M.Metal, SMALL)
	for x = -170, 170, 20 do
		box(model, "RailPost", f, x - 0.15, x + 0.15, 33.6, 37.2, -5.95, -5.65, STEEL_LIGHT, M.Metal, SMALL)
	end
	-- Service runs under the catwalk: a big pale water main, a teal coolant line and a cable tray
	local round = { CastShadow = false, Shape = Enum.PartType.Cylinder }
	block(model, "Pipe", Vector3.new(2 * HALF - 14, 1.6, 1.6), f * CFrame.new(0, 30.8, -1.4), STEEL_LIGHT, M.Metal, round)
	block(model, "Pipe", Vector3.new(2 * HALF - 14, 1.0, 1.0), f * CFrame.new(0, 31.4, -3.1), rgb(72, 112, 106), M.Metal, round)
	box(model, "CableTray", f, -173, 173, 29.2, 29.6, -5.4, -3.8, STEEL_DARK, M.Metal, SMALL)

	-- Above the catwalk: a course of panels, then the glazed observation gallery
	box(model, "Panel", f, -HALF, HALF, 33.6, 44, 0, 2, vary(PANEL_SHADE, random, 0.015), M.Metal)
	box(model, "GallerySill", f, -HALF, HALF, 44, 45, -1, 2, CONCRETE, M.Concrete)
	box(model, "GalleryGlass", f, -HALF, HALF, 45, 54, 1.4, 1.7, GLASS, M.Glass, { Transparency = 0.45, CastShadow = false })
	box(model, "GalleryHead", f, -HALF, HALF, 54, 55.2, -1, 10.6, STEEL_DARK, M.Metal)
	box(model, "GalleryBack", f, -HALF, HALF, 44, 54, 10, 10.6, rgb(150, 140, 126), M.Plaster, SMALL)
	box(model, "GalleryFloor", f, -HALF, HALF, 43.4, 44.4, 1.7, 10, rgb(96, 90, 84), M.WoodPlanks, SMALL)
	local strip = box(model, "GalleryLight", f, -HALF, HALF, 53.4, 53.8, 9.6, 10, LAMP, M.Neon, GHOST)
	strip.Transparency = 0.2
	for _, x in { -120, 0, 120 } do
		local fixture = box(model, "GalleryLamp", f, x - 0.5, x + 0.5, 53.2, 53.8, 9.2, 9.8, LAMP, M.Neon, GHOST)
		light(fixture, LAMP, 22, 1.1)
	end
	for _, column in { -HALF, table.unpack(COLUMNS) } do
		local x = column + 20
		box(model, "Mullion", f, x - 0.3, x + 0.3, 45, 54, 0.9, 1.4, STEEL_DARK, M.Metal, SMALL)
	end
	-- Upper panels up to the crown girder the vault springs from
	box(model, "Panel", f, -HALF, HALF, 55.2, 80, 0, 2, vary(PANEL, random, 0.015), M.Metal)
	box(model, "PanelSeam", f, -HALF, HALF, 67.4, 67.8, -0.2, 0, STEEL, M.Metal, SMALL)
	box(model, "CrownGirder", f, -HALF - 3, HALF + 3, 80, 84, -2, 3, STEEL_DARK, M.Metal)

	-- Columns: a concrete footing and a steel I-section with a cap under the girder
	for _, x in COLUMNS do
		if not inOpening(x, 10, 2) then
			if not insideLounge(side, x) then
				box(model, "Footing", f, x - 2.5, x + 2.5, -1, 9, -4.5, -1, vary(CONCRETE_DARK, random, 0.02), M.Concrete)
			end
			local base = if insideLounge(side, x) then 24 else 9
			box(model, "ColumnFlange", f, x - 1.7, x + 1.7, base, 80, -3.2, -2.4, STEEL, M.Metal)
			box(model, "ColumnWeb", f, x - 0.45, x + 0.45, base, 80, -2.4, 0, STEEL, M.Metal, SMALL)
			box(model, "ColumnCap", f, x - 2.2, x + 2.2, 78.8, 80, -4.4, 0, STEEL_DARK, M.Metal, SMALL)
			wedge(model, "Bracket", Vector3.new(0.7, 3, 2.8), f * CFrame.new(x, 31.5, -4.6) * CFrame.Angles(0, 0, math.pi), STEEL_DARK, M.Metal, SMALL)
		end
	end
	model.Parent = folder
	return model
end

-- The vault: a shallow segmental arch springing from the north and south walls
local VAULT_RISE = 46
local VAULT_R = (HALF * HALF + VAULT_RISE * VAULT_RISE) / (2 * VAULT_RISE)
local VAULT_CY = WALL_TOP + VAULT_RISE - VAULT_R
local VAULT_MAX = math.asin(HALF / VAULT_R)
local VAULT_SEGMENTS = 10
local VAULT_DEPTH = 5

local function arcPoint(x: number, theta: number, out: number?): Vector3
	local r = VAULT_R + (out or 0)
	return Vector3.new(x, VAULT_CY + r * math.cos(theta), r * math.sin(theta))
end

-- Height of the vault's underside above (z)
local function vaultUnderside(z: number): number
	return VAULT_CY + math.sqrt(VAULT_R * VAULT_R - z * z)
end

local function buildRoof(folder: Instance)
	local model = Instance.new("Model")
	model.Name = "Vault"
	local step = 2 * VAULT_MAX / VAULT_SEGMENTS
	-- Trussed ribs over every column line: two chords and a zigzag web
	for _, x in COLUMNS do
		for index = 0, VAULT_SEGMENTS - 1 do
			local a, b = -VAULT_MAX + index * step, -VAULT_MAX + (index + 1) * step
			strut(model, "RibChord", arcPoint(x, a), arcPoint(x, b), 1.4, 1.8, STEEL, M.Metal, OVERHEAD)
			strut(model, "RibChord", arcPoint(x, a, VAULT_DEPTH), arcPoint(x, b, VAULT_DEPTH), 1.0, 1.2, STEEL, M.Metal, OVERHEAD)
			local low, high = 0.9, VAULT_DEPTH - 0.6
			if index % 2 == 0 then
				strut(model, "RibWeb", arcPoint(x, a, low), arcPoint(x, b, high), 0.5, 0.5, STEEL, M.Metal, OVERHEAD)
			else
				strut(model, "RibWeb", arcPoint(x, a, high), arcPoint(x, b, low), 0.5, 0.5, STEEL, M.Metal, OVERHEAD)
			end
		end
	end
	-- Plain arches over the end walls
	for _, x in { -HALF, HALF } do
		for index = 0, VAULT_SEGMENTS - 1 do
			local a, b = -VAULT_MAX + index * step, -VAULT_MAX + (index + 1) * step
			strut(model, "EndArch", arcPoint(x, a, 1), arcPoint(x, b, 1), 2.4, 2.4, STEEL_DARK, M.Metal, OVERHEAD)
		end
	end
	-- Purlins at every joint and glazing bars between them; together with the
	-- ribs they throw the lattice of shadows across the valley floor
	for index = 0, 2 * VAULT_SEGMENTS do
		local theta = -VAULT_MAX + index * step / 2
		local joint = index % 2 == 0
		local size = if joint then 0.9 else 0.45
		block(model, if joint then "Purlin" else "GlazingBar", Vector3.new(2 * HALF, size, size), CFrame.new(arcPoint(0, theta, VAULT_DEPTH + 0.6)) * CFrame.Angles(theta, 0, 0), STEEL, M.Metal, OVERHEAD)
	end
	for index = 0, VAULT_SEGMENTS - 1 do
		local theta = -VAULT_MAX + (index + 0.5) * step
		local radius = VAULT_R + VAULT_DEPTH + 1.2
		local chord = 2 * radius * math.sin(step / 2) + 0.2
		block(model, "RoofGlass", Vector3.new(2 * HALF, 0.25, chord), CFrame.new(arcPoint(0, theta, VAULT_DEPTH + 1.2)) * CFrame.Angles(theta, 0, 0), GLASS, M.Glass, { CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.6 })
	end
	-- Glazed lunettes closing the vault over the east and west walls
	for _, x in { -HALF - 1, HALF + 1 } do
		for z = -160, 160, 40 do
			local height = vaultUnderside(math.abs(z) + 8) + VAULT_DEPTH - WALL_TOP
			block(model, "LunetteGlass", Vector3.new(0.3, height, 40), CFrame.new(x, WALL_TOP + height / 2, z), GLASS, M.Glass, { CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.6 })
			if z < 160 then
				local mullion = vaultUnderside(z + 20) + VAULT_DEPTH - WALL_TOP
				block(model, "LunetteMullion", Vector3.new(0.8, mullion, 0.8), CFrame.new(x, WALL_TOP + mullion / 2, z + 20), STEEL_DARK, M.Metal, OVERHEAD)
			end
		end
	end
	model.Parent = folder
end

-- Light rigs hung from the ribs over the plaza: a truss with three lamp heads
local function buildRigs(folder: Instance)
	for _, spot in { { 40, -40 }, { -40, -40 }, { 40, 44 }, { -40, 44 } } do
		local model = Instance.new("Model")
		model.Name = "LightRig"
		local x, z = spot[1], spot[2]
		local y = 54
		block(model, "RigChord", Vector3.new(42, 0.8, 0.8), CFrame.new(x, y, z), STEEL_DARK, M.Metal, OVERHEAD)
		block(model, "RigChord", Vector3.new(42, 0.5, 0.5), CFrame.new(x, y - 1.6, z), STEEL_DARK, M.Metal, OVERHEAD_SMALL)
		for _, cx in { x - 20, x + 20 } do
			local top = vaultUnderside(z)
			block(model, "RigCable", Vector3.new(0.15, top - y, 0.15), CFrame.new(cx, (top + y) / 2, z), STEEL_DARK, M.Metal, OVERHEAD_SMALL)
		end
		for _, dx in { -12, 0, 12 } do
			local head = block(model, "RigLamp", Vector3.new(1.6, 1.4, 1.6), CFrame.new(x + dx, y - 2.6, z), STEEL, M.Metal, OVERHEAD_SMALL)
			block(model, "RigLens", Vector3.new(1.2, 0.1, 1.2), CFrame.new(x + dx, y - 3.33, z), DAYLIGHT, M.Neon, OVERHEAD_SMALL)
			spotLight(head, Enum.NormalId.Bottom, DAYLIGHT, 60, 1.1, 70)
		end
		model.Parent = folder
	end
end

local function buildEnvelope(folder: Instance)
	local random = Random.new(11)
	for _, side in { "North", "East", "South", "West" } do
		buildWall(folder, side, random)
	end
	-- Concrete piers in the four corners
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			block(folder, "CornerPier", Vector3.new(7, 85, 7), CFrame.new(sx * (HALF - 3.5), 41.5, sz * (HALF - 3.5)), vary(CONCRETE, random, 0.02), M.Concrete)
		end
	end
	buildRoof(folder)
	buildRigs(folder)
end

-- The plaza and the Lantern ----------------------------------------------------------------

-- A ring of short glowing inlays at `radius`; WorldFx makes them breathe
local function inlayRing(folder: Instance, radius: number, count: number, fill: number, top: number, width: number, color: Color3)
	for index = 1, count do
		local angle = (index - 0.5) / count * math.pi * 2
		local length = 2 * math.pi * radius / count * fill
		local inlay = block(folder, "Inlay", Vector3.new(width, 0.05, length), CFrame.new(math.cos(angle) * radius, top + 0.02, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0), color, M.Neon, { CastShadow = false, CanCollide = false, Transparency = 0.5 })
		inlay:SetAttribute("Pulse", index * 0.4)
	end
end

local function bench(folder: Instance, frame: CFrame, random: Random)
	block(folder, "BenchBase", Vector3.new(5.6, 1.3, 1.6), frame * CFrame.new(0, 0.65, 0), vary(CONCRETE, random, 0.03), M.Concrete)
	block(folder, "BenchSeat", Vector3.new(6.0, 0.3, 2.0), frame * CFrame.new(0, 1.45, 0), vary(WOOD, random, 0.05), M.WoodPlanks, SMALL)
end

local function planter(folder: Instance, centre: Vector3, random: Random)
	disc(folder, "Planter", centre + Vector3.new(0, 1.6, 0), 6, 1.8, vary(CONCRETE_DARK, random, 0.03), M.Concrete)
	disc(folder, "Soil", centre + Vector3.new(0, 1.7, 0), 5.2, 0.2, rgb(72, 56, 42), M.Ground, SMALL)
	for index = 1, 3 do
		local angle = index / 3 * math.pi * 2 + random:NextNumber(-0.4, 0.4)
		ball(folder, "Shrub", centre + Vector3.new(math.cos(angle) * 1.1, 2.4 + random:NextNumber(0, 0.4), math.sin(angle) * 1.1), random:NextNumber(2.2, 2.8), vary(pick(LEAVES, random), random, 0.06), M.LeafyGrass, GHOST)
	end
end

-- A slim light column: a footing, a post and a warm glowing panel near the top
local function lightPost(folder: Instance, position: Vector3, random: Random)
	local f = facingCentre(position)
	block(folder, "PostFooting", Vector3.new(1.4, 0.5, 1.4), f * CFrame.new(0, 0.25, 0), CONCRETE_DARK, M.Concrete, SMALL)
	block(folder, "LightPost", Vector3.new(0.7, 9, 0.7), f * CFrame.new(0, 4.75, 0), vary(STEEL, random, 0.03), M.Metal)
	local panel = block(folder, "PostLamp", Vector3.new(0.4, 2.6, 0.8), f * CFrame.new(0, 8.2, -0.35), LAMP, M.Neon, GHOST)
	light(panel, LAMP, 18, 0.9)
end

local function buildPlaza(folder: Instance)
	local random = Random.new(7)
	disc(folder, "PlazaRim", Vector3.new(0, 0.02, 0), (Nexus.Radius + 0.8) * 2, 2.4, STEEL_DARK, M.Metal)
	disc(folder, "Plaza", Vector3.new(0, 0.08, 0), Nexus.Radius * 2, 1, PAVING, M.Pavement)
	disc(folder, "PlazaBand", Vector3.new(0, 0.12, 0), 60, 0.4, PAVING_DARK, M.Slate)
	disc(folder, "PlazaInner", Vector3.new(0, 0.16, 0), 48, 0.4, PAVING_LIGHT, M.Granite)
	inlayRing(folder, 27, 24, 0.72, 0.12, 0.24, TEAL)
	-- Radial joints in the inner disc
	for index = 1, 12 do
		local angle = (index + 0.5) / 12 * math.pi * 2
		block(folder, "Joint", Vector3.new(11.2, 0.03, 0.14), CFrame.new(math.cos(angle) * 18.2, 0.17, math.sin(angle) * 18.2) * CFrame.Angles(0, -angle, 0), rgb(160, 156, 148), M.Slate, GHOST)
	end
	for _, angle in { 140, -140, -42, 45 } do
		bench(folder, facingCentre(polar(angle, 38.5, 0.08)), random)
	end
	for _, angle in { 160, -160, -62 } do
		planter(folder, polar(angle, 37.5, 0.08), random)
	end
	for _, angle in { 12, 54, 126, 168, -168, -126, -54, -12 } do
		lightPost(folder, polar(angle, 42.4, 0.08), random)
	end
end

local CRYSTAL_HEIGHT = 13

local function buildLantern(folder: Instance)
	local random = Random.new(3)
	local model = Instance.new("Model")
	model.Name = "LanternContainment"
	-- Dais: a graphite deck with hazard marks round its edge, then a raised steel ring
	disc(model, "Dais", Vector3.new(0, 0.6, 0), 22.8, 0.8, STEEL_DARK, M.DiamondPlate)
	for index = 1, 16 do
		local angle = (index - 0.5) / 16 * math.pi * 2
		block(model, "HazardMark", Vector3.new(0.9, 0.05, 2.0), CFrame.new(math.cos(angle) * 10.8, 0.62, math.sin(angle) * 10.8) * CFrame.Angles(0, -angle + math.rad(35), 0), AMBER, M.SmoothPlastic, GHOST)
	end
	disc(model, "DaisRing", Vector3.new(0, 1.2, 0), 17.2, 0.6, STEEL, M.Metal)
	-- A glass-panelled railing round the dais
	for index = 1, 12 do
		local a, b = (index - 1) / 12 * math.pi * 2, index / 12 * math.pi * 2
		local pa, pb = Vector3.new(math.cos(a) * 11.0, 0, math.sin(a) * 11.0), Vector3.new(math.cos(b) * 11.0, 0, math.sin(b) * 11.0)
		block(model, "RailPost", Vector3.new(0.35, 3.6, 0.35), CFrame.new(pa + Vector3.new(0, 2.8, 0)), STEEL_LIGHT, M.Metal, SMALL)
		strut(model, "Rail", pa + Vector3.new(0, 4.6, 0), pb + Vector3.new(0, 4.6, 0), 0.3, 0.3, STEEL_LIGHT, M.Metal, SMALL)
		strut(model, "RailGlass", pa + Vector3.new(0, 2.85, 0), pb + Vector3.new(0, 2.85, 0), 0.12, 3.1, GLASS, M.Glass, { CastShadow = false, Transparency = 0.6 })
	end
	-- The lower emitter: an eight-sided pedestal with a glowing aperture
	for turn = 0, 1 do
		block(model, "Emitter", Vector3.new(3.8, 2.4, 3.8), CFrame.new(0, 2.4, 0) * CFrame.Angles(0, turn * math.pi / 4, 0), STEEL, M.Metal)
	end
	disc(model, "EmitterCap", Vector3.new(0, 3.9, 0), 4.4, 0.3, STEEL_LIGHT, M.Metal)
	local aperture = disc(model, "Aperture", Vector3.new(0, 3.98, 0), 2.6, 0.1, TEAL, M.Neon, GHOST)
	aperture:SetAttribute("Glow", 0.1)
	-- Four pylons lean in to hold the containment ring and the upper emitter
	local tops = {}
	for index = 0, 3 do
		local angle = math.rad(45 + index * 90)
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local foot = out * 7.4 + Vector3.new(0, 1.2, 0)
		local knee = out * 6.4 + Vector3.new(0, 13, 0)
		local top = out * 5.4 + Vector3.new(0, 23.5, 0)
		tops[index + 1] = top
		block(model, "PylonFoot", Vector3.new(3, 1.4, 3), CFrame.new(foot + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, -angle, 0), STEEL_DARK, M.Metal)
		strut(model, "Pylon", foot + Vector3.new(0, 1.2, 0), knee, 2.0, 2.0, vary(STEEL_LIGHT, random, 0.02), M.Metal)
		strut(model, "Pylon", knee, top, 1.4, 1.4, vary(STEEL_LIGHT, random, 0.02), M.Metal)
		-- Clamp on the ring, with an emitter head aimed at the crystal
		local clamp = lookAt(knee, Vector3.new(0, CRYSTAL_HEIGHT, 0))
		block(model, "Clamp", Vector3.new(2.6, 2.0, 2.6), clamp, STEEL_DARK, M.Metal)
		pipe(model, "EmitterHead", (clamp * CFrame.new(0, 0, -1.3)).Position, (clamp * CFrame.new(0, 0, -2.5)).Position, 1.1, STEEL, M.Metal, SMALL)
		disc(model, "EmitterLens", Vector3.zero, 0.8, 0.12, TEAL, M.Neon, GHOST).CFrame = clamp * CFrame.new(0, 0, -2.58) * CFrame.Angles(0, math.rad(90), 0)
		-- Cables from the foot down to a port at the edge of the dais
		local port = out * 9.6
		block(model, "CablePort", Vector3.new(1.4, 0.5, 1.2), CFrame.new(port + Vector3.new(0, 0.85, 0)) * CFrame.Angles(0, -angle, 0), STEEL, M.Metal, SMALL)
		pipe(model, "Cable", foot + Vector3.new(0, 0.3, 0) + out * 1.4, port + Vector3.new(0, 1.0, 0), 0.5, rgb(30, 32, 34), M.Rubber, SMALL)
		block(model, "PortLight", Vector3.new(0.3, 0.1, 0.3), CFrame.new(port + Vector3.new(0, 1.12, 0)), AMBER, M.Neon, GHOST):SetAttribute("Blink", 1.6 + index * 0.3)
	end
	-- The containment ring (sixteen pieces) at the crystal's height
	for index = 1, 16 do
		local a, b = (index - 1) / 16 * math.pi * 2, index / 16 * math.pi * 2
		strut(model, "ContainmentRing", Vector3.new(math.cos(a) * 6.2, CRYSTAL_HEIGHT, math.sin(a) * 6.2), Vector3.new(math.cos(b) * 6.2, CRYSTAL_HEIGHT, math.sin(b) * 6.2), 1.3, 0.9, STEEL, M.Metal, SMALL)
	end
	-- Crown: beams joining the pylon tops, crossed by the frame of the upper emitter
	for index = 1, 4 do
		strut(model, "Crown", tops[index], tops[index % 4 + 1], 1.2, 1.2, STEEL_DARK, M.Metal)
	end
	strut(model, "CrownCross", tops[1], tops[3], 0.8, 0.8, STEEL_DARK, M.Metal, SMALL)
	strut(model, "CrownCross", tops[2], tops[4], 0.8, 0.8, STEEL_DARK, M.Metal, SMALL)
	cylinder(model, "UpperEmitter", CFrame.new(0, 22.4, 0), 2.2, 2.6, STEEL, M.Metal, SMALL)
	disc(model, "UpperAperture", Vector3.new(0, 21.25, 0), 1.8, 0.1, TEAL, M.Neon, GHOST)
	-- A brass gyroscope ring turns slowly round the crystal
	for index = 1, 12 do
		local a, b = (index - 1) / 12 * math.pi * 2, index / 12 * math.pi * 2
		local tilt = CFrame.new(0, CRYSTAL_HEIGHT, 0) * CFrame.Angles(0, 0, math.rad(68))
		local piece = strut(model, "Gyro", (tilt * CFrame.new(math.cos(a) * 4.3, 0, math.sin(a) * 4.3)).Position, (tilt * CFrame.new(math.cos(b) * 4.3, 0, math.sin(b) * 4.3)).Position, 0.45, 0.45, rgb(178, 148, 98), M.Metal, GHOST)
		piece:SetAttribute("Spin", 0.25)
		piece:SetAttribute("SpinPivot", Vector3.new(0, CRYSTAL_HEIGHT, 0))
	end
	-- The Lantern: a glassy bipyramid with a bright heart, floating free
	local home = CFrame.new(0, CRYSTAL_HEIGHT, 0) * CFrame.Angles(0, math.rad(45), math.rad(4))
	local glass = { CanCollide = false, CastShadow = false, Transparency = 0.2, Reflectance = 0.1 }
	local crystalColor = rgb(132, 214, 206)
	local crystal = block(model, "NexusCrystal", Vector3.new(3.0, 5.4, 3.0), home, crystalColor, M.Glass, glass)
	local pieces = { crystal }
	for _, y in { 1, -1 } do
		local flip = if y > 0 then CFrame.new() else CFrame.Angles(0, 0, math.pi)
		table.insert(pieces, wedge(model, "CrystalTip", Vector3.new(3.0, 2.2, 1.5), home * CFrame.new(0, y * 3.8, -0.75) * flip, crystalColor, M.Glass, glass))
		table.insert(pieces, wedge(model, "CrystalTip", Vector3.new(3.0, 2.2, 1.5), home * CFrame.new(0, y * 3.8, 0.75) * CFrame.Angles(0, math.pi, 0) * flip, crystalColor, M.Glass, glass))
	end
	local core = block(model, "NexusCore", Vector3.new(1.2, 4.6, 1.2), home, rgb(196, 246, 236), M.Neon, { CanCollide = false, CastShadow = false, Transparency = 0.1 })
	table.insert(pieces, core)
	for _, piece in pieces do
		piece:SetAttribute("Crystal", true)
	end
	light(core, rgb(160, 236, 224), 34, 2.2, true)
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
	-- The visitor console on the spawn side, and the first recovered file beside it
	local consoleAt = polar(66, 14.2, 0)
	-- Front (-Z) to the Lantern: a surface on the top face reads for someone standing at its back
	local console = lookAt(consoleAt, Vector3.zero)
	block(model, "ConsoleBase", Vector3.new(3.6, 2.8, 1.6), console * CFrame.new(0, 1.4, -0.3), STEEL, M.Metal)
	local screen = block(model, "ConsoleScreen", Vector3.new(3.6, 0.25, 2.2), console * CFrame.new(0, 3.1, 0.1) * CFrame.Angles(math.rad(35), 0, 0), STEEL_DARK, M.Metal, SMALL)
	local gui = surface(screen, Enum.NormalId.Top, 60, true)
	frame(gui, { 0, 0, 1, 1 }, SCREEN)
	line(gui, "THE LANTERN", { 0.07, 0.08, 0.86, 0.22 }, TEAL, FONT_TECH, nil, 40)
	line(gui, "Found in this valley in 1981. Every power here began in its light.", { 0.07, 0.34, 0.86, 0.36 }, SIGN_TEXT, FONT_SANS, Enum.FontWeight.Medium, 30)
	line(gui, "Containment stable. Please stay behind the rail.", { 0.07, 0.74, 0.86, 0.18 }, rgb(150, 170, 166), FONT_SANS, nil, 24)
	local recorder = block(model, "VoiceRecorder", Vector3.new(0.7, 0.25, 1.1), console * CFrame.new(-1.2, 2.93, -0.75) * CFrame.Angles(0, math.rad(20), 0), rgb(40, 42, 44), M.SmoothPlastic, GHOST)
	block(model, "RecorderLight", Vector3.new(0.12, 0.05, 0.12), recorder.CFrame * CFrame.new(0.2, 0.15, -0.35), rgb(220, 70, 50), M.Neon, GHOST):SetAttribute("Blink", 2.2)
	loreFile(recorder, "ajkr_first_entry", "Voice memo")
	-- Behind a pylon on the far side, where the light reaches but nobody looks: a torn page
	local page = block(model, "TornPage", Vector3.new(0.9, 0.04, 1.2), CFrame.new(polar(-112, 9.9, 0.64)) * CFrame.Angles(0, 0.7, 0.04), rgb(226, 218, 196), M.SmoothPlastic, GHOST)
	loreFile(page, "lantern_field_note", "A torn page")
	model.Parent = folder

	-- Spawn on the plaza south of the Lantern, facing it (the Lounge's warm windows to the left)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "NexusSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.2, 6)
	spawn.CFrame = CFrame.new(0, 0.3, 21)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = folder
	return spawn
end

-- Gates: bulkhead doors -------------------------------------------------------------------

-- A backlit sign: a colour chip, the name in the station's display face, and a subline
local function gateSign(target: BasePart, face: Enum.NormalId, title: string, subline: string, color: Color3)
	local gui = surface(target, face, 40, true)
	frame(gui, { 0, 0, 1, 1 }, rgb(24, 28, 31))
	frame(gui, { 0.05, 0.2, 0.012, 0.6 }, color)
	line(gui, string.upper(title), { 0.09, 0.14, 0.86, 0.44 }, SIGN_TEXT, FONT_TECH, nil, 44)
	line(gui, subline, { 0.09, 0.6, 0.86, 0.26 }, color:Lerp(SIGN_TEXT, 0.35), FONT_SANS, Enum.FontWeight.Medium, 26)
	return gui
end

-- A strip of hazard paint: amber with dark diagonal bands drawn on top
local function hazardStrip(parent: Instance, size: Vector3, cframe: CFrame)
	local strip = block(parent, "HazardStrip", size, cframe, AMBER, M.SmoothPlastic, GHOST)
	local gui = surface(strip, Enum.NormalId.Top, 20, false)
	local count = math.floor(size.X / 1.6)
	for index = 0, count do
		local band = frame(gui, { index / count - 0.02, -0.5, 0.35 / count, 2 }, rgb(36, 36, 36))
		band.Rotation = 35
	end
	return strip
end

local function buildGate(folder: Instance, gate)
	local random = Random.new(#gate.id * 17)
	local model = Instance.new("Model")
	model.Name = "Gate_" .. gate.id
	-- -Z looks into the hall; the wall's face is z = 0
	local f = lookAt(gate.position, gate.position + gate.facing)
	local tint = gate.color
	box(model, "Threshold", f, -8, 8, -0.4, 0.2, -5, 1.5, STEEL, M.DiamondPlate)
	box(model, "Recess", f, -7, 7, 0, 15, 2.6, 3.6, STEEL_DARK, M.Metal, SMALL)
	-- Heavy steel surround with chamfered upper corners
	box(model, "Jamb", f, -10, -6.4, -0.4, 20, -2.4, 1.6, vary(STEEL, random, 0.03), M.Metal)
	box(model, "Jamb", f, 6.4, 10, -0.4, 20, -2.4, 1.6, vary(STEEL, random, 0.03), M.Metal)
	box(model, "Header", f, -6.4, 6.4, 14.4, 20, -2.4, 1.6, vary(STEEL, random, 0.03), M.Metal)
	for _, side in { -1, 1 } do
		wedge(model, "Chamfer", Vector3.new(1.6, 1.6, 0.9), f * CFrame.new(side * 5.6, 13.6, -1.0) * CFrame.Angles(0, if side > 0 then math.pi / 2 else -math.pi / 2, math.pi), STEEL, M.Metal, SMALL)
	end
	-- Status bar under the header, lighting the doorway in the gate's colour
	local status = box(model, "StatusLight", f, -5.6, 5.6, 14.0, 14.4, -2.5, -2.1, tint, M.Neon, GHOST)
	status:SetAttribute("Glow", 0)
	spotLight(status, Enum.NormalId.Bottom, tint:Lerp(DAYLIGHT, 0.4), 18, 1.4, 80)
	local door
	if gate.open then
		-- The Training Wing's bulkhead stands open: an air curtain you walk through
		door = box(model, "PortalSurface", f, -6.4, 6.4, 0.2, 14, 0.8, 1.0, tint, M.Glass, { Transparency = 0.82, CanCollide = false, CastShadow = false })
		box(model, "DoorLeaf", f, -9.6, -6.6, 0.2, 14, 0.4, 1.4, STEEL_LIGHT, M.Metal, SMALL)
		box(model, "DoorLeaf", f, 6.6, 9.6, 0.2, 14, 0.4, 1.4, STEEL_LIGHT, M.Metal, SMALL)
		local sill = box(model, "SillLight", f, -6, 6, 0.2, 0.3, -0.6, -0.2, tint, M.Neon, GHOST)
		sill.Transparency = 0.3
	else
		-- Two closed leaves with a lit seam, hazard paint and narrow windows
		door = box(model, "PortalSurface", f, -6.4, 0, 0.2, 14.0, 0.6, 1.6, vary(PANEL_SHADE, random, 0.02), M.Metal)
		box(model, "DoorLeaf", f, 0, 6.4, 0.2, 14.0, 0.6, 1.6, vary(PANEL_SHADE, random, 0.02), M.Metal)
		hazardStrip(model, Vector3.new(12.6, 0.1, 1.6), f * CFrame.new(0, 1.4, 0.55) * CFrame.Angles(math.rad(-90), 0, 0))
		for _, x in { -3.2, 3.2 } do
			box(model, "DoorWindow", f, x - 0.5, x + 0.5, 8, 11.5, 0.5, 0.6, rgb(40, 52, 58), M.Glass, { Transparency = 0.3, CastShadow = false })
		end
		local seam = box(model, "Seam", f, -0.12, 0.12, 0.4, 13.8, 0.45, 0.55, tint, M.Neon, GHOST)
		seam.Transparency = 0.3
		seam:SetAttribute("Glow", 0.3)
	end
	-- The sign over the door, and a status screen beside it
	local sign = box(model, "GateSign", f, -8, 8, 21, 24.4, -0.8, 0, rgb(24, 28, 31), M.SmoothPlastic, SMALL)
	gateSign(sign, Enum.NormalId.Front, gate.name, gate.sector .. "  ·  " .. gate.prompt, tint)
	local screen = box(model, "StatusScreen", f, -14.2, -11.2, 4, 8, -0.4, 0, STEEL_DARK, M.Metal, SMALL)
	readout(screen, Enum.NormalId.Front, Vector2.new(3, 4), string.upper(gate.sector), {
		"LINK  OK",
		"SEAL  NOMINAL",
		"AIR   21.4 C",
		"LOAD  " .. tostring(random:NextInteger(12, 64)) .. "%",
		"WARDEN  ACK",
		"CYCLE " .. tostring(random:NextInteger(1000, 9999)),
	}, tint)
	hazardStrip(model, Vector3.new(14, 0.06, 1.0), f * CFrame.new(0, 0.05, -6))

	local proximity = prompt(door, gate.prompt, gate.name, gate.action, 0, 14)
	proximity.Name = "GatePrompt"
	model.Parent = folder
	return model
end

-- The programme exhibits -------------------------------------------------------------------

-- The north arc, 20 degrees apart; the Residential Wing's avenue runs between the middle two
local EXHIBIT_ANGLES = { -160, -140, -120, -100, -80, -60, -40, -20 }
local EXHIBIT_RADIUS = 62

-- A stylised standing figure (about 6.5 studs), built from `base` upward
local function figure(model: Model, base: CFrame, id: string, color: Color3, material: Enum.Material, extra: { [string]: any })
	local k = 1.1
	local function at(offset: CFrame): CFrame
		return base * (CFrame.new(offset.Position * k) * offset.Rotation)
	end
	local function piece(name: string, size: Vector3, offset: CFrame, tone: Color3?): BasePart
		local made = block(model, name, size * k, at(offset), tone or color, material, extra)
		made:SetAttribute("Holo", true)
		return made
	end
	local calm = id == "Grandmaster"
	piece("Leg", Vector3.new(0.8, 2.7, 0.9), CFrame.new(-0.55, 1.35, 0) * CFrame.Angles(0, 0, math.rad(if calm then -2 else -5)))
	piece("Leg", Vector3.new(0.8, 2.7, 0.9), CFrame.new(0.55, 1.35, 0) * CFrame.Angles(0, 0, math.rad(if calm then 2 else 5)))
	piece("Torso", Vector3.new(1.9, 2.4, 1.0), CFrame.new(0, 3.9, 0))
	local chest = piece("Chest", Vector3.new(2.4, 0.9, 1.15), CFrame.new(0, 5.2, 0))
	piece("Head", Vector3.new(1.05, 1.15, 1.05), CFrame.new(0, 6.35, 0))
	-- Arms: how far out they swing and whether the forearm comes up, per power
	local pose = {
		StrongDude = { 18, 75 },
		Ghost = { 10, 30 },
		Shapeshifter = { 22, 15 },
		MachineMaster = { 12, 80 },
		Corruption = { 28, 10 },
		Syntax = { 14, 60 },
		Admin = { 8, 45 },
		Grandmaster = { 4, 70 },
	}
	local swing, raise = table.unpack(pose[id] or { 10, 20 })
	local hands = {}
	for _, side in { -1, 1 } do
		local shoulder = CFrame.new(side * 1.5, 5.4, 0) * CFrame.Angles(0, 0, math.rad(side * swing))
		piece("Arm", Vector3.new(0.65, 1.6, 0.68), shoulder * CFrame.new(0, -0.8, 0))
		-- The groundskeeper's hands meet in front of him; everyone else's are ready
		local bend = if calm then CFrame.Angles(math.rad(raise), 0, math.rad(side * 38)) else CFrame.Angles(math.rad(if side > 0 then raise else raise * 0.5), 0, math.rad(-side * swing * 0.6))
		local elbow = shoulder * CFrame.new(0, -1.55, 0) * bend
		piece("Forearm", Vector3.new(0.58, 1.4, 0.62), elbow * CFrame.new(0, -0.68, 0))
		hands[side] = elbow * CFrame.new(0, -1.45, 0)
	end
	if id == "StrongDude" then
		for _, side in { -1, 1 } do
			piece("Fist", Vector3.new(0.9, 0.9, 0.9), hands[side])
		end
	elseif id == "Ghost" then
		piece("Hood", Vector3.new(1.4, 1.3, 1.3), CFrame.new(0, 6.45, 0.15))
		piece("Blade", Vector3.new(0.12, 3.0, 0.36), hands[1] * CFrame.new(0, -1.2, 0))
	elseif id == "Shapeshifter" then
		for _, side in { -1, 1 } do
			piece("Ear", Vector3.new(0.3, 0.7, 0.3), CFrame.new(side * 0.38, 7.1, 0) * CFrame.Angles(0, 0, math.rad(side * -14)))
		end
		piece("Tail", Vector3.new(0.4, 0.4, 2.0), CFrame.new(0, 2.8, 1.3) * CFrame.Angles(math.rad(-25), 0, 0))
	elseif id == "MachineMaster" then
		piece("Pack", Vector3.new(1.8, 2.2, 0.8), CFrame.new(0, 4.5, 0.9))
		piece("Cannon", Vector3.new(0.8, 0.8, 2.0), hands[1] * CFrame.new(0, 0.3, -0.6))
	elseif id == "Corruption" then
		for index = 1, 3 do
			local angle = index / 3 * math.pi * 2
			piece("Shard", Vector3.new(0.22, 0.75, 0.22), CFrame.new(math.cos(angle) * 0.9, 7.3, math.sin(angle) * 0.9) * CFrame.Angles(0, -angle, math.rad(18)))
		end
	elseif id == "Syntax" then
		piece("Pane", Vector3.new(1.7, 1.2, 0.06), hands[1] * CFrame.new(0, -0.2, -1.0) * CFrame.Angles(math.rad(-20), 0, 0))
	elseif id == "Admin" then
		piece("Staff", Vector3.new(0.24, 6.0, 0.24), CFrame.new(1.9, 3.0, -0.4))
	elseif id == "Grandmaster" then
		-- A plain robe over the legs, and a cloth band tied at the brow
		piece("Robe", Vector3.new(2.2, 2.4, 1.3), CFrame.new(0, 1.9, 0), color:Lerp(rgb(70, 66, 60), 0.3))
		piece("Band", Vector3.new(1.12, 0.22, 1.12), CFrame.new(0, 6.6, 0), LINEN)
	end
	return chest
end

-- A plaque on a post: codename large, the power's name smaller, one line of the registry
local function plaque(model: Model, base: CFrame, title: string, name: string, note: string, color: Color3, random: Random)
	block(model, "PlaquePost", Vector3.new(0.5, 2.9, 0.5), base * CFrame.new(0, 1.45, 0), STEEL, M.Metal, SMALL)
	-- Turned so its top face reads for someone standing on the Lantern's side
	local board = block(model, "Plaque", Vector3.new(4.4, 0.22, 2.4), base * CFrame.new(0, 3.1, 0) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(math.rad(38), 0, 0), vary(rgb(30, 34, 37), random, 0.03), M.Metal, SMALL)
	local gui = surface(board, Enum.NormalId.Top, 60, true)
	frame(gui, { 0, 0, 1, 1 }, rgb(26, 30, 33))
	frame(gui, { 0.06, 0.12, 0.012, 0.3 }, color)
	line(gui, title, { 0.1, 0.08, 0.84, 0.36 }, SIGN_TEXT, FONT_TECH, nil, 30)
	line(gui, name, { 0.1, 0.46, 0.84, 0.2 }, color:Lerp(SIGN_TEXT, 0.4), FONT_SANS, Enum.FontWeight.SemiBold, 26)
	line(gui, note, { 0.1, 0.68, 0.84, 0.22 }, rgb(150, 160, 160), FONT_SANS, nil, 19)
end

local function buildExhibits(folder: Instance)
	local random = Random.new(41)
	local holo = { CanCollide = false, CastShadow = false, Transparency = 0.5 }
	for index, programme in PROGRAMMES do
		local angle = EXHIBIT_ANGLES[index]
		local model = Instance.new("Model")
		model.Name = "Statue_" .. programme.id
		local base = facingCentre(polar(angle, EXHIBIT_RADIUS, 0))
		local empty = programme.id == "Grandmaster"
		block(model, "Pad", Vector3.new(if empty then 15 else 9, 0.4, 11), base * CFrame.new(if empty then 2.8 else 0, -0.05, -1.5), vary(PAVING, random, 0.02), M.Pavement)
		disc(model, "PodBase", (base * CFrame.new(0, 1.3, 0)).Position, 7.2, 1.15, STEEL_DARK, M.Metal)
		local ring = disc(model, "PodRing", (base * CFrame.new(0, 1.45, 0)).Position, 6.3, 0.15, if empty then STEEL else programme.color, if empty then M.Metal else M.Neon, GHOST)
		if not empty then
			ring.Transparency = 0.35
		end
		disc(model, "PodGlass", (base * CFrame.new(0, 10.45, 0)).Position, 5.6, 9, if empty then rgb(176, 178, 168) else GLASS, M.Glass, { CastShadow = false, Transparency = if empty then 0.5 else 0.66 })
		disc(model, "PodCap", (base * CFrame.new(0, 11.8, 0)).Position, 7.2, 1.35, STEEL, M.Metal)
		for rib = 0, 2 do
			local turn = math.rad(90 + rib * 120)
			block(model, "PodRib", Vector3.new(0.4, 9, 0.5), base * CFrame.new(math.cos(turn) * 2.9, 5.95, math.sin(turn) * 2.9) * CFrame.Angles(0, -turn, 0), STEEL_LIGHT, M.Metal, SMALL)
		end
		if empty then
			-- The groundskeeper's pod: unlit, with his worn training wraps left on the floor
			for wrap = -1, 1, 2 do
				cylinder(model, "TrainingWrap", base * CFrame.new(wrap * 0.7, 1.75, 0.3) * CFrame.Angles(math.rad(90), math.rad(wrap * 20), 0), 1.1, 0.7, vary(LINEN, random, 0.04), M.Fabric, GHOST)
			end
			block(model, "TrainingWrap", Vector3.new(0.5, 0.06, 2.2), base * CFrame.new(0.2, 1.48, -0.8) * CFrame.Angles(0, 0.5, 0), vary(LINEN, random, 0.04), M.Fabric, GHOST)
			plaque(model, base * CFrame.new(0, 0, -5.6), "NOT A SUBJECT", programme.name, programme.note, programme.color, random)
			-- He stands outside it, at ease, looking toward the Lantern he refused
			local stand = base * CFrame.new(5.6, 0, -1.2)
			disc(model, "FigureBase", (stand * CFrame.new(0, 0.3, 0)).Position, 2.6, 0.4, STEEL_DARK, M.Metal)
			figure(model, stand * CFrame.new(0, 0.3, 0), programme.id, rgb(118, 134, 122), M.Slate, { CastShadow = true })
		else
			disc(model, "Emitter", (base * CFrame.new(0, 10.45, 0)).Position, 3, 0.15, programme.color, M.Neon, GHOST)
			local chest = figure(model, base * CFrame.new(0, 1.5, 0), programme.id, programme.color, M.Neon, holo)
			light(chest, programme.color, 12, 0.9)
			local scan = disc(model, "ScanRing", (base * CFrame.new(0, 5, 0)).Position, 5.2, 0.08, programme.color, M.Neon, holo)
			scan.Transparency = 0.6
			scan:SetAttribute("Scan", random:NextNumber(0, 6))
			plaque(model, base * CFrame.new(0, 0, -5.6), "PROGRAMME " .. programme.codename, programme.name, programme.note, programme.color, random)
		end
		model.Parent = folder
	end
end

-- Builds the whole lobby into `folder`. Returns the spawn location.
function Nexus.build(folder: Instance): SpawnLocation
	if not buildTerrain() then
		-- No terrain (or it failed): a plain grass slab instead
		block(folder, "Ground", Vector3.new(2 * INNER, 2, 2 * INNER), CFrame.new(0, GROUND_Y - 1, 0), rgb(98, 122, 62), M.Grass)
	end
	buildEnvelope(folder)
	buildPlaza(folder)
	local spawn = buildLantern(folder)
	for _, gate in Nexus.Gates do
		buildGate(folder, gate)
	end
	buildExhibits(folder)
	return spawn :: SpawnLocation
end

return Nexus
