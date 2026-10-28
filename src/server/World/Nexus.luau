-- The Nexus: the HALL OF THE EIGHT, the lobby everyone spawns into (the look is
-- set by docs/ArtDirection.md). A colossal ancient hall under Kestrel Valley:
-- walls of warm travertine with a colonnade of fluted ivory columns along the
-- north and south sides, high clerestory windows, and a broken stone vault the
-- Meridian Institute roofed in steel and glass. The Lantern rests in a bronze
-- ring on the central dais, inside a ring of eight statue bays where The Eight
-- stand (Statues.luau carves the figures), and bronze meridian lines run out
-- through the gaps between the bays to every door. The Institute planted the
-- court around them as the Garden: grass, groves and a pond. Off the hall: the
-- Lounge behind the north colonnade (Dr. Varga's study hides behind its
-- library), the Calibration Chamber, the Enhancement Bay and the Commissary's
-- stores, the Training Wing beyond the west portal, and the sealed Door 09,
-- whose antechamber is reached through a maintenance crawlspace. Ten recovered
-- files are hidden around it all. Holiday decorations and the luxury car use
-- spots in the court (SeasonalDecor/Build.luau KEEP_CLEAR), and everything
-- overhead ignores raycasts so decorations still land on the floor.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Powers = require(ReplicatedStorage.Shared.Powers)

local Nexus = {}

local rgb = Color3.fromRGB
local M = Enum.Material

-- Materials (docs/ArtDirection.md section 3): { colour, material, MaterialVariant, colour spread }.
-- About 85% is the ancient layer (stone, bronze, a little gold); the Meridian
-- layer is brass, glass and thin cool light.
local KINDS = {
	marble = { rgb(232, 225, 211), M.Marble, "SN_IvoryMarble", 0.03 },
	travertine = { rgb(203, 187, 160), M.Limestone, "SN_Travertine", 0.025 },
	recess = { rgb(172, 157, 134), M.Limestone, "SN_Travertine", 0.02 },
	dark = { rgb(78, 74, 69), M.Slate, "SN_DarkStone", 0.04 },
	darker = { rgb(61, 59, 58), M.Basalt, "SN_DarkStone", 0.03 },
	bronze = { rgb(140, 106, 63), M.Metal, "SN_Bronze", 0.02 },
	bronzeLight = { rgb(181, 139, 79), M.Metal, "SN_Bronze", 0.02 },
	gold = { rgb(217, 178, 95), M.Foil, "SN_GoldLeaf", 0 },
	brass = { rgb(168, 138, 85), M.Metal, nil, 0.02 },
	steel = { rgb(72, 70, 66), M.Metal, nil, 0.02 },
	lapis = { rgb(31, 43, 74), M.Fabric, nil, 0.03 },
	wood = { rgb(118, 84, 58), M.Wood, nil, 0.05 },
	woodDark = { rgb(74, 54, 40), M.Wood, nil, 0.04 },
}

local MARBLE = KINDS.marble[1]
local BRONZE = KINDS.bronze[1]
local BRASS = KINDS.brass[1]
local LAPIS = KINDS.lapis[1]
local GLASS = rgb(196, 210, 214)
local HOLO = rgb(221, 235, 255)
local IVORY_TEXT = rgb(237, 230, 214)
local CARVED = rgb(112, 92, 66)
local LAMP = rgb(255, 202, 150)
local WARM_SPOT = rgb(255, 214, 166)
local WOOD = KINDS.wood[1]
local WOOD_DARK = KINDS.woodDark[1]
local WOOD_FLOOR = rgb(140, 100, 68)
local LEATHER = rgb(128, 76, 46)
local LINEN = rgb(214, 202, 180)
local RUST = rgb(150, 72, 50)
local MUSTARD = rgb(186, 148, 76)
local SCREEN = rgb(21, 20, 16)
local BARK = rgb(86, 68, 52)
local MOSS = rgb(88, 104, 56)
local LEAVES = { rgb(70, 98, 50), rgb(84, 110, 56), rgb(62, 86, 46) }
local AUTUMN = { rgb(150, 100, 56), rgb(132, 84, 48), rgb(160, 124, 66) }
local NEEDLES = { rgb(46, 70, 52), rgb(54, 78, 56), rgb(42, 62, 48) }

local FONT_SANS = "rbxasset://fonts/families/BuilderSans.json"
local FONT_DISPLAY = "rbxasset://fonts/families/AccanthisADFStd.json"
local FONT_CARVED = "rbxasset://fonts/families/RomanAntique.json"
local FONT_MONO = "rbxasset://fonts/families/RobotoMono.json"

-- Small decoration: no shadow. Foliage and glow: no shadow or collision either.
-- Overhead: no collision and invisible to raycasts (decorations drop onto the floor).
local SMALL = { CastShadow = false }
local GHOST = { CastShadow = false, CanCollide = false }
local LEAFY = { CanCollide = false }
local OVERHEAD = { CanCollide = false, CanQuery = false }

-- The hall: inner faces of the walls at +-HALF; the vault springs from VAULT_SPRING
local HALF = 180
local VAULT_SPRING = 84.5
local VAULT_CROWN = 120
-- Columns (and the vault's stone ribs) stand on these lines; windows and doors sit between them
local COLUMN_XS = { -140, -100, -60, -20, 20, 60, 100, 140 }
local BAY_XS = { -160, -120, -80, -40, 0, 40, 80, 120, 160 }
-- The colonnade stands this far in front of the north and south walls
local COLONNADE = 16
local SHAFT = 7
-- The paved sanctum round the dais, and the ring of statue bays at its edge
local SANCTUM = 78
local BAY_RADIUS = 88
local BAY_ANGLES = {
	StrongDude = -112.5,
	Ghost = -67.5,
	Shapeshifter = -22.5,
	MachineMaster = 22.5,
	Syntax = 67.5,
	Corruption = 112.5,
	Admin = 157.5,
	Grandmaster = -157.5,
}
local CODENAMES = {
	StrongDude = { "ATLAS", "Strong Dude", "I" },
	Ghost = { "VEIL", "The Ghost", "II" },
	Shapeshifter = { "CHIMERA", "Animal Shapeshifter", "III" },
	MachineMaster = { "FURNACE", "Machine Master", "IV" },
	Syntax = { "LATTICE", "Syntax", "V" },
	Corruption = { "ECLIPSE", "Corruption", "VI" },
	Admin = { "WARDEN", "Admin Powers", "VII" },
	Grandmaster = { "THE EIGHTH", "The Grandmaster", "VIII" },
}
-- Programme colours, for the holograms and the mastery wall (the only place they appear in the world)
local PROGRAMME_COLORS = {
	{ "ATLAS", rgb(255, 150, 72) },
	{ "VEIL", rgb(150, 226, 255) },
	{ "CHIMERA", rgb(156, 212, 112) },
	{ "FURNACE", rgb(92, 182, 255) },
	{ "LATTICE", rgb(112, 230, 172) },
	{ "ECLIPSE", rgb(178, 98, 222) },
	{ "WARDEN", rgb(236, 204, 122) },
	{ "EIGHTH", rgb(200, 190, 170) },
}

Nexus.Radius = SANCTUM

-- Where the Training Wing stands, beyond the west portal (Config Match.TrainingGround.Center must match)
Nexus.TrainingCenter = Vector3.new(-236, 0, 0)

-- The gateways: bronze doors in the walls. `position` is the middle of the
-- doorway at floor level and `facing` points into the hall; `angle` is the
-- direction of its meridian line from the Lantern.
Nexus.Gates = {
	{ id = "Battle", name = "Test Chambers", sector = "Sector 3", angle = 0, color = rgb(196, 112, 84), action = "Window:Play", prompt = "Find a fight", position = Vector3.new(HALF, 0, 0), facing = Vector3.new(-1, 0, 0) },
	{ id = "Training", name = "Training Wing", sector = "Sector 2", angle = 180, color = rgb(112, 168, 170), action = "Travel:Training", prompt = "Go to training", position = Vector3.new(-HALF, 0, 0), facing = Vector3.new(1, 0, 0), open = true },
	{ id = "Homes", name = "Residential Wing", sector = "Sector 6", angle = -90, color = rgb(214, 170, 104), action = "Base:Home", prompt = "Go to your base", position = Vector3.new(0, 0, -HALF), facing = Vector3.new(0, 0, 1) },
	{ id = "Market", name = "Commissary", sector = "Sector 5", angle = 90, color = rgb(150, 182, 120), action = "Window:Shop", prompt = "Open the shop", position = Vector3.new(0, 0, HALF), facing = Vector3.new(0, 0, -1) },
	{ id = "Watch", name = "Observation Deck", sector = "Sector 4", angle = 45, color = rgb(146, 150, 210), action = "Window:Watch", prompt = "Watch a match", position = Vector3.new(120, 0, HALF), facing = Vector3.new(0, 0, -1) },
}

-- The rooms the other meridian lines lead to
local LOUNGE_DOOR = Vector3.new(-120, 0, -HALF)
local CALIBRATION_DOOR = Vector3.new(120, 0, -HALF)
local DOOR_09 = Vector3.new(-120, 0, HALF)
local ENHANCEMENT_DOOR = Vector3.new(40, 0, HALF)
local STORES_DOOR = Vector3.new(-40, 0, HALF)
local CRAWLSPACE = Vector3.new(-80, 0, HALF)

-- Building blocks ------------------------------------------------------------------------

-- Every stone part varies a little in tone; seeded at the start of each build so builds repeat
local tone = Random.new(17)

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

-- No two pieces the same: nudge the value and warmth a little
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

-- Gives a part one of the hall's materials (colour, material, variant, bronze's faint sheen)
local function dress(made: BasePart, kind: string): BasePart
	local spec = KINDS[kind]
	made.Color = if spec[4] > 0 then vary(spec[1], tone, spec[4]) else spec[1]
	made.Material = spec[2]
	if spec[3] then
		made.MaterialVariant = spec[3]
	end
	if spec[2] == M.Metal then
		made.Reflectance = 0.05
	end
	return made
end

local function stone(parent: Instance, name: string, kind: string, size: Vector3, cframe: CFrame, extra: { [string]: any }?): BasePart
	return dress(block(parent, name, size, cframe, MARBLE, M.Marble, extra), kind)
end

-- An axis-aligned box in `f`'s space, given by its extents
local function box(parent: Instance, name: string, kind: string, f: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, extra: { [string]: any }?): BasePart
	return stone(parent, name, kind, Vector3.new(x1 - x0, y1 - y0, z1 - z0), f * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), extra)
end

-- A cylinder standing along the Y axis of `cframe` (Roblox cylinders run along X)
local function cylinder(parent: Instance, name: string, kind: string, cframe: CFrame, height: number, diameter: number, extra: { [string]: any }?): BasePart
	local props = if extra then table.clone(extra) else {}
	props.Shape = Enum.PartType.Cylinder
	return stone(parent, name, kind, Vector3.new(height, diameter, diameter), cframe * CFrame.Angles(0, 0, math.rad(90)), props)
end

-- A round slab whose top is at `top`
local function disc(parent: Instance, name: string, kind: string, top: Vector3, diameter: number, thickness: number, extra: { [string]: any }?): BasePart
	return cylinder(parent, name, kind, CFrame.new(top - Vector3.new(0, thickness / 2, 0)), thickness, diameter, extra)
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
local function strut(parent: Instance, name: string, kind: string, a: Vector3, b: Vector3, width: number, height: number, extra: { [string]: any }?): BasePart
	return stone(parent, name, kind, Vector3.new(width, height, (b - a).Magnitude), lookAt((a + b) / 2, b), extra)
end

-- Text on a part face. `glow` makes it self-lit (screens and the Meridian displays).
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

-- A Meridian display: warm graphite with a bronze hairline, a title in the
-- display face and rows of cool readout that scroll slowly upward (WorldFx
-- moves the rows; they loop because they are written twice). `size` is the
-- face's size in studs, so the type stays the same on every screen.
local function readout(screen: BasePart, face: Enum.NormalId, size: Vector2, title: string, rows: { string })
	local pixelsPerStud = 40
	local gui = surface(screen, face, pixelsPerStud, true)
	frame(gui, { 0, 0, 1, 1 }, SCREEN)
	local border = Instance.new("UIStroke")
	border.Color = BRONZE
	border.Transparency = 0.4
	border.Thickness = 2
	border.Parent = frame(gui, { 0.03, 0.04, 0.94, 0.92 }, SCREEN, 1)
	line(gui, title, { 0.07, 0.07, 0.86, 0.17 }, IVORY_TEXT, FONT_DISPLAY, Enum.FontWeight.Regular, 40)
	local clip = frame(gui, { 0.07, 0.3, 0.86, 0.6 }, SCREEN, 1)
	clip.ClipsDescendants = true
	-- Five rows show at once
	local rowHeight = math.floor(size.Y * pixelsPerStud * 0.6 / 5)
	local list = Instance.new("Frame")
	list.Name = "Readout"
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, 0, 0, rowHeight * #rows * 2)
	list:SetAttribute("Scroll", rowHeight * #rows)
	for index = 0, #rows * 2 - 1 do
		local row = Instance.new("TextLabel")
		row.BackgroundTransparency = 1
		row.Position = UDim2.new(0, 0, 0, index * rowHeight)
		row.Size = UDim2.new(1, 0, 0, rowHeight)
		row.Text = rows[index % #rows + 1]
		row.FontFace = Font.new(FONT_MONO, Enum.FontWeight.Regular)
		row.TextSize = math.floor(rowHeight * 0.6)
		row.TextColor3 = HOLO
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextTruncate = Enum.TextTruncate.AtEnd
		row.Parent = list
	end
	list.Parent = clip
	return gui
end

-- An inscription cut into stone: Roman Antique capitals, shadowed into the face
local function carve(target: BasePart, face: Enum.NormalId, text: string, pixelsPerStud: number, color: Color3?)
	local gui = surface(target, face, pixelsPerStud, false)
	line(gui, text, { 0.03, 0.14, 0.94, 0.72 }, color or CARVED, FONT_CARVED, Enum.FontWeight.Regular, 400, Enum.TextXAlignment.Center)
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

-- A recovered file: tagged for LoreService, with a prompt that picks it up
local function loreFile(target: BasePart, fileId: string, objectText: string): ProximityPrompt
	CollectionService:AddTag(target, "SNLoreTerminal")
	target:SetAttribute("LoreId", fileId)
	local proximity = prompt(target, "Read", objectText, "Lore:" .. fileId, 0.4, 8)
	proximity.Name = "LorePrompt"
	return proximity
end

-- The Lantern star: two squares at 45 degrees. `cf`'s Y axis is the face it lies on.
local function lanternStar(parent: Instance, cf: CFrame, size: number, thickness: number, kind: string)
	stone(parent, "Star", kind, Vector3.new(size, thickness, size), cf, SMALL)
	stone(parent, "Star", kind, Vector3.new(size, thickness, size), cf * CFrame.Angles(0, math.pi / 4, 0), SMALL)
end

-- The Meridian order: a dark square plinth, a chamfered base with a bronze
-- ring, a fluted shaft (twelve fillets set proud), and a capital of ring, disc
-- and abacus. `base` is the floor point; `height` is the top of the abacus.
local function column(parent: Instance, base: CFrame, height: number)
	local half = SHAFT / 2
	box(parent, "ColumnPlinth", "dark", base, -half - 1.2, half + 1.2, 0, 1.6, -half - 1.2, half + 1.2)
	disc(parent, "ColumnBase", "marble", (base * CFrame.new(0, 2.8, 0)).Position, SHAFT + 1.6, 1.2)
	disc(parent, "ColumnRing", "bronze", (base * CFrame.new(0, 3.2, 0)).Position, SHAFT + 0.5, 0.4, SMALL)
	local shaftTop = height - 3.4
	local shaftHeight = shaftTop - 3.2
	cylinder(parent, "ColumnShaft", "marble", base * CFrame.new(0, 3.2 + shaftHeight / 2, 0), shaftHeight, SHAFT)
	for index = 1, 12 do
		local angle = (index - 0.5) / 12 * math.pi * 2
		stone(parent, "Flute", "marble", Vector3.new(0.3, shaftHeight - 1.4, 0.6), base * CFrame.new(math.cos(angle) * (half + 0.02), 3.2 + shaftHeight / 2, math.sin(angle) * (half + 0.02)) * CFrame.Angles(0, -angle, 0), SMALL)
	end
	disc(parent, "ColumnRing", "bronze", (base * CFrame.new(0, shaftTop + 0.4, 0)).Position, SHAFT + 0.5, 0.4, SMALL)
	disc(parent, "Capital", "marble", (base * CFrame.new(0, shaftTop + 1.9, 0)).Position, SHAFT + 1.9, 1.5)
	box(parent, "Abacus", "marble", base, -half - 1.4, half + 1.4, shaftTop + 1.9, height, -half - 1.4, half + 1.4)
end

-- Architrave, frieze and cornice from x0 to x1 in `f` (front -Z), starting at `y`.
-- Returns the frieze, for an inscription.
local function entablature(parent: Instance, f: CFrame, x0: number, x1: number, y: number, zFront: number, zBack: number): BasePart
	box(parent, "Architrave", "marble", f, x0, x1, y, y + 3, zFront + 0.5, zBack)
	local frieze = box(parent, "Frieze", "travertine", f, x0, x1, y + 3, y + 7.2, zFront + 0.9, zBack)
	box(parent, "Cornice", "marble", f, x0 - 1.4, x1 + 1.4, y + 7.2, y + 9.2, zFront - 0.8, zBack)
	return frieze
end

-- A brass wall lamp: a bracket and a warm glass shade, lighting a pool of the wall
local function sconce(parent: Instance, f: CFrame, x: number, y: number)
	box(parent, "SconceBracket", "brass", f, x - 0.3, x + 0.3, y - 1.4, y, -1.2, 0, SMALL)
	local shade = block(parent, "SconceShade", Vector3.new(1.1, 1.5, 1.1), f * CFrame.new(x, y + 0.5, -1.2), rgb(255, 226, 182), M.Glass, { CastShadow = false, CanCollide = false, Transparency = 0.3 })
	light(shade, LAMP, 22, 1.1)
end

-- Terrain ---------------------------------------------------------------------------------

local GROUND_Y = -1
-- Terrain stays inside this square, clear of the walls
local INNER = 178

-- Gentle mounds in the Garden, between the routes and behind the statue bays: { x, z, radius, height }
local MOUNDS = {}
for index = 0, 7 do
	local angle = 22.5 + index * 45
	if index ~= 3 then
		local spot = polar(angle, 132)
		table.insert(MOUNDS, { spot.X, spot.Z, 26 + (index % 3) * 3, 3 + (index % 2) * 1.5 })
	end
end

-- The pond in the west-south-west of the Garden
local POND = { x = -136, z = 64, a = 24, b = 15, level = -1.8 }

-- Worn garden footpaths: { width, points (x, z) }
local FOOTPATHS = {
	{ 4, { { -96, 40 }, { -110, 58 }, { -114, 80 }, { -136, 86 }, { -158, 78 }, { -162, 58 } } }, -- round the pond
	{ 4, { { 92, -30 }, { 108, -46 }, { 112, -60 } } }, -- into the grove behind CHIMERA
	{ 4, { { -86, -98 }, { -104, -112 } } },
}

local function hillTop(hill, x: number, z: number): number?
	local dx, dz = x - hill[1], z - hill[2]
	local radius = hill[3]
	local d2 = dx * dx + dz * dz
	if d2 >= radius * radius then
		return nil
	end
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

local function buildTerrain(): boolean
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return false
	end
	local ok, err = pcall(function()
		local random = Random.new(23)
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
		local px0, px1, pz0, pz1 = POND.x - 28, POND.x + 28, POND.z - 19, POND.z + 19
		floor(-INNER, INNER, -INNER, pz0)
		floor(-INNER, INNER, pz1, INNER)
		floor(-INNER, px0, pz0, pz1)
		floor(px1, INNER, pz0, pz1)

		-- Pond: a muddy basin, water in an oval, banks shaping it, a sandy margin
		terrain:FillBlock(CFrame.new(POND.x, -9.5, POND.z), Vector3.new(56, 9, 38), M.Mud)
		for _, offset in { 0, -9, 9 } do
			terrain:FillCylinder(CFrame.new(POND.x + offset, (POND.level - 5) / 2, POND.z), POND.level + 5, if offset == 0 then 15 else 12.5, M.Water)
		end
		for index = 0, 7 do
			local t = index / 8 * math.pi * 2
			local edge = Vector3.new(POND.x + math.cos(t) * POND.a, floorY, POND.z + math.sin(t) * POND.b)
			local normal = Vector3.new(math.cos(t) / POND.a, 0, math.sin(t) / POND.b).Unit
			local center = edge + normal * 12
			terrain:FillBlock(lookAt(center, center + normal) - Vector3.new(0, 0.06, 0), Vector3.new(32, 13, 24), M.Grass)
		end
		for index = 0, 21 do
			local t = index / 22 * math.pi * 2
			local scale = random:NextNumber(1.0, 1.06)
			local center = Vector3.new(POND.x + math.cos(t) * POND.a * scale, GROUND_Y - 0.6, POND.z + math.sin(t) * POND.b * scale)
			terrain:FillCylinder(CFrame.new(center), 1, random:NextNumber(2.2, 3.2), if index % 5 == 0 then M.Ground else M.Sand)
		end

		-- Mounds: stacked low discs following a smooth bump, leafier grass on the crowns
		for _, hill in MOUNDS do
			local x, z, radius, height = hill[1], hill[2], hill[3], hill[4]
			for step = 1, 4 do
				local share = step / 4
				local ring = radius * math.acos(2 * share - 1) / math.pi
				terrain:FillCylinder(CFrame.new(x, GROUND_Y + height * share - 2, z), 4, ring, if step == 4 then M.LeafyGrass else M.Grass)
			end
		end
		for _, path in FOOTPATHS do
			local width, points = path[1], path[2]
			for index = 1, #points - 1 do
				local a = Vector3.new(points[index][1], 0, points[index][2])
				local b = Vector3.new(points[index + 1][1], 0, points[index + 1][2])
				local top = math.max(groundAt(a.X, a.Z), groundAt(b.X, b.Z))
				terrain:FillBlock(lookAt((a + b) / 2, b) + Vector3.new(0, top - 1.9, 0), Vector3.new(width, 4, (b - a).Magnitude + width * 0.4), M.Ground)
			end
		end
		-- Moss gathers in the damp at the foot of the colonnades
		for x = -150, 150, 50 do
			for _, z in { -156, 156 } do
				terrain:FillCylinder(CFrame.new(x + random:NextNumber(-10, 10), GROUND_Y - 1.95, z), 4, random:NextNumber(6, 10), M.LeafyGrass)
			end
		end
	end)
	if not ok then
		warn("[World] Terrain didn't finish: " .. tostring(err))
	end
	return ok
end

-- The hall: walls, colonnades, clerestory and vault -------------------------------------

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

-- Openings cut into the walls: { side, at (world position), width, sill, top }
local OPENINGS = {
	{ side = "North", at = LOUNGE_DOOR, width = 14, sill = -7, top = 22 },
	{ side = "North", at = Vector3.new(-160, 0, -HALF), width = 14, sill = 4, top = 20 }, -- the Lounge's windows
	{ side = "North", at = Vector3.new(-80, 0, -HALF), width = 14, sill = 4, top = 20 },
	{ side = "North", at = CALIBRATION_DOOR, width = 14, sill = -7, top = 22 },
	{ side = "South", at = DOOR_09, width = 14, sill = -7, top = 22 },
	{ side = "South", at = ENHANCEMENT_DOOR, width = 14, sill = -7, top = 22 },
	{ side = "South", at = STORES_DOOR, width = 8, sill = -7, top = 13 },
	{ side = "South", at = CRAWLSPACE, width = 5, sill = -7, top = 6 },
}
for _, gate in Nexus.Gates do
	local side = if gate.facing.X < 0 then "East" elseif gate.facing.X > 0 then "West" elseif gate.facing.Z > 0 then "North" else "South"
	table.insert(OPENINGS, { side = side, at = gate.position, width = 14, sill = -7, top = 22 })
end

-- Stretches of the wall between openings: an opening reaching above `y0` and below `y1` cuts it
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

local function buildWall(folder: Instance, side: string)
	local model = Instance.new("Model")
	model.Name = "Wall" .. side
	local f = wallFrame(side)
	local colonnade = side == "North" or side == "South"
	local openings = {}
	for _, opening in OPENINGS do
		if opening.side == side then
			table.insert(openings, { x = f:PointToObjectSpace(opening.at).X, width = opening.width, sill = opening.sill, top = opening.top })
		end
	end
	local function nearOpening(x: number, margin: number): boolean
		for _, opening in openings do
			if math.abs(x - opening.x) < opening.width / 2 + margin then
				return true
			end
		end
		return false
	end

	-- Dark skirting, the travertine wall (cut by the doors below 30), and lintels and sills round the openings
	for _, run in wallRuns(openings, -1, 3) do
		box(model, "Skirting", "dark", f, run[1], run[2], -1, 3, -0.6, 3)
	end
	for _, run in wallRuns(openings, 3, 30) do
		box(model, "Wall", "travertine", f, run[1], run[2], 3, 30, 0, 3)
	end
	box(model, "Wall", "travertine", f, -HALF, HALF, 30, 60, 0, 3)
	for _, opening in openings do
		local x0, x1 = opening.x - opening.width / 2, opening.x + opening.width / 2
		if opening.top < 30 then
			box(model, "Lintel", "travertine", f, x0, x1, opening.top, 30, 0, 3)
		end
		if opening.sill > 3 then
			box(model, "Sill", "travertine", f, x0, x1, 3, opening.sill, 0, 3)
			box(model, "SillStone", "marble", f, x0 - 0.6, x1 + 0.6, opening.sill - 0.5, opening.sill, -0.8, 3)
		end
	end

	if colonnade then
		-- The colonnade: eight fluted columns carrying an entablature over a deep ambulatory
		for _, x in COLUMN_XS do
			column(model, f * CFrame.new(x, 0, -COLONNADE), 46.5)
		end
		box(model, "Architrave", "marble", f, -176, 176, 46.5, 49.5, -20.3, -11.7)
		box(model, "Frieze", "travertine", f, -176, 176, 49.5, 53.7, -19.9, -12.1)
		box(model, "Cornice", "marble", f, -177, 177, 53.7, 55.7, -21.4, 0)
		box(model, "AmbulatoryCeiling", "recess", f, -176, 176, 47, 48.4, -12.1, 0, SMALL)
		box(model, "AmbulatoryFloor", "dark", f, -176, 176, -0.6, 0.05, -21.2, 0)
		for _, x in { -150, -90, -30, 30, 90, 150 } do
			sconce(model, f, x, 13)
		end
	else
		-- Giant pilasters and the entablature on the wall face, with darker recessed bays between
		for _, x in COLUMN_XS do
			if not nearOpening(x, 4) then
				box(model, "PilasterBase", "dark", f, x - 3.9, x + 3.9, -1, 3.2, -2.2, 0)
				box(model, "Pilaster", "marble", f, x - 3, x + 3, 3.2, 44.6, -1.5, 0)
				box(model, "PilasterCapital", "marble", f, x - 3.9, x + 3.9, 44.6, 46.5, -2.4, 0)
			end
		end
		entablature(model, f, -177, 177, 46.5, -2.2, 0)
		for index, x in BAY_XS do
			if index % 2 == 0 and not nearOpening(x, 2) then
				box(model, "RecessPanel", "recess", f, x - 12, x + 12, 6, 40, -0.15, 0, SMALL)
				sconce(model, f, x, 16)
			end
		end
	end

	-- The clerestory: tall windows between the column lines, a bronze mullion in each
	box(model, "ClerestorySill", "marble", f, -HALF, HALF, 60, 62, -0.8, 3)
	box(model, "ClerestoryHead", "marble", f, -HALF, HALF, 80, 82, -0.6, 3)
	local at = -HALF
	for _, x in BAY_XS do
		box(model, "ClerestoryPier", "travertine", f, at, x - 7, 62, 80, 0, 3)
		box(model, "ClerestoryGlass", "marble", f, x - 7, x + 7, 62, 80, 1.6, 1.9, { CastShadow = false, Transparency = 0.6 }).Material = M.Glass
		box(model, "ClerestoryMullion", "bronze", f, x - 0.3, x + 0.3, 62, 80, 1.1, 1.6, SMALL)
		at = x + 7
	end
	box(model, "ClerestoryPier", "travertine", f, at, HALF, 62, 80, 0, 3)
	box(model, "Springing", "marble", f, -HALF - 3, HALF + 3, 82, VAULT_SPRING, -2, 3)
	model.Parent = folder
	return model
end

-- The vault: a segmental barrel springing from the north and south walls. The
-- ancient stone ribs are broken in places; the Institute's steel purlins and
-- glass span everything, and a stone oculus rings the crown over the Lantern.
local VAULT_R = (HALF * HALF + (VAULT_CROWN - VAULT_SPRING) ^ 2) / (2 * (VAULT_CROWN - VAULT_SPRING))
local VAULT_CY = VAULT_CROWN - VAULT_R
local VAULT_MAX = math.asin(HALF / VAULT_R)
local VAULT_SEGMENTS = 12
local RIB_DEPTH = 5
-- Rib stones that fell long ago: { rib x, first missing segment, last }
local RIB_BREAKS = { [-60] = { 6, 7 }, [100] = { 5, 7 }, [-140] = { 8, 8 } }

local function arcPoint(x: number, theta: number, out: number?): Vector3
	local r = VAULT_R + (out or 0)
	return Vector3.new(x, VAULT_CY + r * math.sin(math.pi / 2 - math.abs(theta)), r * math.sin(theta))
end

-- Height of the vault's underside above (z)
local function vaultUnderside(z: number): number
	return VAULT_CY + math.sqrt(VAULT_R * VAULT_R - z * z)
end

local function buildVault(folder: Instance)
	local model = Instance.new("Model")
	model.Name = "Vault"
	local step = 2 * VAULT_MAX / VAULT_SEGMENTS
	for _, x in COLUMN_XS do
		local broken = RIB_BREAKS[x]
		for index = 1, VAULT_SEGMENTS do
			local a, b = -VAULT_MAX + (index - 1) * step, -VAULT_MAX + index * step
			if broken and index >= broken[1] and index <= broken[2] then
				-- Where the stone fell, a steel tie and two clamps carry the line across
				if index == broken[1] then
					local far = -VAULT_MAX + broken[2] * step
					strut(model, "RibTie", "steel", arcPoint(x, a, 2.5), arcPoint(x, far, 2.5), 1.2, 1.2, OVERHEAD)
					box(model, "RibClamp", "steel", CFrame.new(arcPoint(x, a, 2.5)), -2.6, 2.6, -1.6, 1.6, -0.8, 0.8, OVERHEAD)
					box(model, "RibClamp", "steel", CFrame.new(arcPoint(x, far, 2.5)), -2.6, 2.6, -1.6, 1.6, -0.8, 0.8, OVERHEAD)
				end
			else
				strut(model, "Rib", "travertine", arcPoint(x, a, RIB_DEPTH / 2), arcPoint(x, b, RIB_DEPTH / 2), 4.6, RIB_DEPTH, OVERHEAD)
			end
		end
	end
	-- Steel purlins at every joint and glazing bars between them, then the glass
	for index = 0, 2 * VAULT_SEGMENTS do
		local theta = -VAULT_MAX + index * step / 2
		local joint = index % 2 == 0
		local size = if joint then 1.0 else 0.5
		stone(model, if joint then "Purlin" else "GlazingBar", "steel", Vector3.new(2 * HALF, size, size), CFrame.new(arcPoint(0, theta, RIB_DEPTH + 0.5)) * CFrame.Angles(theta, 0, 0), OVERHEAD)
	end
	for index = 0, VAULT_SEGMENTS - 1 do
		local theta = -VAULT_MAX + (index + 0.5) * step
		local chord = 2 * (VAULT_R + RIB_DEPTH + 1.1) * math.sin(step / 2) + 0.2
		local pane = block(model, "RoofGlass", Vector3.new(2 * HALF, 0.25, chord), CFrame.new(arcPoint(0, theta, RIB_DEPTH + 1.1)) * CFrame.Angles(theta, 0, 0), GLASS, M.Glass, { CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.62 })
		pane.Name = "RoofGlass"
	end
	-- The oculus: a ring of stone at the crown, right over the Lantern
	for index = 1, 16 do
		local a, b = (index - 1) / 16 * math.pi * 2, index / 16 * math.pi * 2
		local y = VAULT_CROWN + RIB_DEPTH + 0.2
		strut(model, "Oculus", "travertine", Vector3.new(math.cos(a) * 15, y, math.sin(a) * 15), Vector3.new(math.cos(b) * 15, y, math.sin(b) * 15), 3.2, 2.6, OVERHEAD)
	end
	-- The lunettes over the east and west walls: a great thermal window between stone
	for _, x in { -HALF - 1.5, HALF + 1.5 } do
		for z = -80, 80, 40 do
			local height = vaultUnderside(math.max(math.abs(z) - 20, 0)) + RIB_DEPTH + 1.2 - VAULT_SPRING
			block(model, "LunetteGlass", Vector3.new(0.3, height, 40), CFrame.new(x, VAULT_SPRING + height / 2, z), GLASS, M.Glass, { CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.55 })
		end
		for _, z in { -60, -20, 20, 60 } do
			local height = vaultUnderside(math.abs(z)) + RIB_DEPTH - VAULT_SPRING
			box(model, "LunetteMullion", "bronze", CFrame.new(x, VAULT_SPRING + height / 2, z), -0.6, 0.6, -height / 2, height / 2, -0.8, 0.8, OVERHEAD)
		end
		for _, edge in { { 100, 140 }, { 140, 180 }, { -140, -100 }, { -180, -140 } } do
			local inner = math.min(math.abs(edge[1]), math.abs(edge[2]))
			local height = vaultUnderside(inner) + RIB_DEPTH + 1.2 - VAULT_SPRING
			box(model, "LunetteStone", "travertine", CFrame.new(x, VAULT_SPRING, 0), -1.5, 1.5, 0, height, edge[1], edge[2], OVERHEAD)
		end
	end
	model.Parent = folder
end

local function buildHall(folder: Instance)
	for _, side in { "North", "East", "South", "West" } do
		buildWall(folder, side)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			stone(folder, "CornerPier", "travertine", Vector3.new(7, 86, 7), CFrame.new(sx * (HALF - 3.5), 42, sz * (HALF - 3.5)))
		end
	end
	buildVault(folder)
end

-- The sanctum: floor, dais and the Lantern --------------------------------------------------

-- The meridian lines: from the dais out through the gaps between the statue bays
local ROUTE_ANGLES = { 0, 45, 90, 135, 180, -135, -90, -45 }

local CRYSTAL_HEIGHT = 15

local function buildSanctum(folder: Instance)
	local model = Instance.new("Model")
	model.Name = "Sanctum"
	-- Concentric dark stone and ivory bands, the Lantern star inlaid at the centre
	disc(model, "SanctumFloor", "dark", Vector3.new(0, 0.04, 0), SANCTUM * 2, 1.4)
	disc(model, "SanctumBand", "marble", Vector3.new(0, 0.06, 0), 122, 0.3)
	disc(model, "SanctumFloor", "dark", Vector3.new(0, 0.08, 0), 116, 0.3)
	disc(model, "SanctumBand", "marble", Vector3.new(0, 0.1, 0), 68, 0.3)
	disc(model, "SanctumCourt", "darker", Vector3.new(0, 0.12, 0), 63, 0.3)
	lanternStar(model, CFrame.new(0, 0.07, 0), 36, 0.14, "marble")
	for _, angle in ROUTE_ANGLES do
		local radians = math.rad(angle)
		local length = SANCTUM - 15.5
		stone(model, "MeridianLine", "bronzeLight", Vector3.new(0.6, 0.06, length), CFrame.new(math.cos(radians) * (15.5 + length / 2), 0.17, math.sin(radians) * (15.5 + length / 2)) * CFrame.Angles(0, -radians + math.pi / 2, 0), GHOST)
	end
	-- The dais: three ivory steps, a ring of gold leaf on the top one
	disc(model, "Dais", "marble", Vector3.new(0, 1, 0), 31, 1.2)
	disc(model, "Dais", "marble", Vector3.new(0, 2, 0), 25.5, 1.0)
	disc(model, "Dais", "marble", Vector3.new(0, 3, 0), 20, 1.0)
	disc(model, "DaisRing", "gold", Vector3.new(0, 3.03, 0), 20.6, 0.1, SMALL)
	disc(model, "DaisTop", "marble", Vector3.new(0, 3.06, 0), 19.2, 0.1, SMALL)

	-- The containment: four bronze arms rise from the dais to hold a ring of bronze round the crystal
	for index = 0, 3 do
		local angle = math.rad(45 + index * 90)
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local foot = out * 8.4 + Vector3.new(0, 3.06, 0)
		local knee = out * 8.0 + Vector3.new(0, 11.5, 0)
		local hand = out * 6.6 + Vector3.new(0, CRYSTAL_HEIGHT - 0.4, 0)
		box(model, "ArmShoe", "bronze", CFrame.new(foot) * CFrame.Angles(0, -angle, 0), -1.2, 1.2, 0, 0.9, -0.9, 0.9)
		strut(model, "Arm", "bronze", foot + Vector3.new(0, 0.8, 0), knee, 0.9, 0.9)
		strut(model, "Arm", "bronze", knee, hand, 0.8, 0.8)
		-- A brass emitter on each arm draws a hairline of light to the crystal
		local emitterAt = out * 7.9 + Vector3.new(0, 10.6, 0)
		cylinder(model, "Emitter", "brass", lookAt(emitterAt, Vector3.new(0, CRYSTAL_HEIGHT, 0)) * CFrame.Angles(math.rad(90), 0, 0), 1.2, 0.7, SMALL)
		local thread = strut(model, "Hairline", "marble", emitterAt, Vector3.new(0, CRYSTAL_HEIGHT, 0), 0.07, 0.07, GHOST)
		thread.Color = HOLO
		thread.Material = M.Neon
		thread.Transparency = 0.45
		thread:SetAttribute("Pulse", index * 1.3)
	end
	for index = 1, 16 do
		local a, b = (index - 1) / 16 * math.pi * 2, index / 16 * math.pi * 2
		strut(model, "ContainmentRing", "bronzeLight", Vector3.new(math.cos(a) * 6.6, CRYSTAL_HEIGHT - 0.4, math.sin(a) * 6.6), Vector3.new(math.cos(b) * 6.6, CRYSTAL_HEIGHT - 0.4, math.sin(b) * 6.6), 0.9, 1.1, SMALL)
	end
	-- An inner ring turns slowly round the crystal, like an instrument still taking readings
	for index = 1, 12 do
		local a, b = (index - 1) / 12 * math.pi * 2, index / 12 * math.pi * 2
		local tilt = CFrame.new(0, CRYSTAL_HEIGHT, 0) * CFrame.Angles(0, 0, math.rad(70))
		local piece = strut(model, "Gyro", "bronze", (tilt * CFrame.new(math.cos(a) * 4.6, 0, math.sin(a) * 4.6)).Position, (tilt * CFrame.new(math.cos(b) * 4.6, 0, math.sin(b) * 4.6)).Position, 0.4, 0.4, GHOST)
		piece:SetAttribute("Spin", 0.22)
		piece:SetAttribute("SpinPivot", Vector3.new(0, CRYSTAL_HEIGHT, 0))
	end
	-- The Lantern: a cool, glassy bipyramid with a bright heart, floating free inside the ring
	local home = CFrame.new(0, CRYSTAL_HEIGHT, 0) * CFrame.Angles(0, math.rad(45), math.rad(4))
	local glass = { CanCollide = false, CastShadow = false, Transparency = 0.18, Reflectance = 0.12 }
	local crystalColor = rgb(206, 224, 236)
	local crystal = block(model, "NexusCrystal", Vector3.new(3.2, 6.0, 3.2), home, crystalColor, M.Glass, glass)
	local pieces = { crystal }
	for _, y in { 1, -1 } do
		local flip = if y > 0 then CFrame.new() else CFrame.Angles(0, 0, math.pi)
		table.insert(pieces, wedge(model, "CrystalTip", Vector3.new(3.2, 2.6, 1.6), home * CFrame.new(0, y * 4.3, -0.8) * flip, crystalColor, M.Glass, glass))
		table.insert(pieces, wedge(model, "CrystalTip", Vector3.new(3.2, 2.6, 1.6), home * CFrame.new(0, y * 4.3, 0.8) * CFrame.Angles(0, math.pi, 0) * flip, crystalColor, M.Glass, glass))
	end
	local core = block(model, "NexusCore", Vector3.new(1.3, 5.2, 1.3), home, HOLO, M.Neon, { CanCollide = false, CastShadow = false, Transparency = 0.08 })
	table.insert(pieces, core)
	for _, piece in pieces do
		piece:SetAttribute("Crystal", true)
	end
	light(core, rgb(208, 226, 255), 44, 2.4, true)
	emitter(core, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(rgb(226, 238, 255)),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.26), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.25, 1),
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(0.3, 0.8),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 0.25, 0),
		Drag = 0.6,
		Rate = 3,
	})

	-- A brass instrument on the spawn side tells visitors what they are looking at;
	-- the first recovered file waits on it
	local consoleAt = polar(62, 19.5, 0)
	local console = lookAt(consoleAt, Vector3.zero)
	cylinder(model, "ConsolePost", "brass", console * CFrame.new(0, 1.7, 0), 3.4, 0.9)
	disc(model, "ConsoleFoot", "dark", (console * CFrame.new(0, 0.5, 0)).Position, 2.6, 0.4)
	-- Front (-Z) to the Lantern: a surface on its top face reads for someone standing at its back
	local plate = stone(model, "ConsolePlate", "brass", Vector3.new(3.4, 0.2, 2.2), console * CFrame.new(0, 3.6, 0.1) * CFrame.Angles(math.rad(35), 0, 0), SMALL)
	local gui = surface(plate, Enum.NormalId.Top, 60, true)
	frame(gui, { 0, 0, 1, 1 }, SCREEN)
	line(gui, "THE LANTERN", { 0.07, 0.06, 0.86, 0.24 }, IVORY_TEXT, FONT_DISPLAY, nil, 44)
	line(gui, "It did not fall. It came home. Every power in this hall began in its light.", { 0.07, 0.34, 0.86, 0.4 }, rgb(185, 176, 160), FONT_SANS, Enum.FontWeight.Medium, 28)
	line(gui, "Meridian Institute, restored", { 0.07, 0.78, 0.86, 0.14 }, HOLO, FONT_SANS, nil, 22)
	local recorder = stone(model, "VoiceRecorder", "steel", Vector3.new(0.7, 0.25, 1.1), console * CFrame.new(0.9, 0.35, 0.9) * CFrame.Angles(0, math.rad(20), 0), GHOST)
	loreFile(recorder, "ajkr_first_entry", "Voice memo")
	-- On the dais's lowest step, round the far side where people rarely look: a torn page
	local page = block(model, "TornPage", Vector3.new(0.9, 0.04, 1.2), CFrame.new(polar(-118, 14, 1.03)) * CFrame.Angles(0, 0.7, 0), rgb(226, 218, 196), M.SmoothPlastic, GHOST)
	loreFile(page, "lantern_field_note", "A torn page")
	-- Motes drifting in the light over the sanctum
	local motes = block(model, "Motes", Vector3.new(90, 30, 90), CFrame.new(0, 30, 0), Color3.new(1, 1, 1), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	emitter(motes, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(rgb(255, 240, 214)),
		LightEmission = 0.6,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.12), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.4, 1),
		Lifetime = NumberRange.new(8, 12),
		Speed = NumberRange.new(0.1, 0.3),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 1,
		Rate = 6,
	})
	model.Parent = folder

	-- Spawn in the sanctum south of the dais, facing the Lantern, ATLAS and VEIL beyond it
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "NexusSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.2, 6)
	spawn.CFrame = CFrame.new(0, 0.3, 30)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = folder
	return spawn
end

-- The statue bays ---------------------------------------------------------------------------

local statuesModule = script.Parent:FindFirstChild("Statues")

-- A stepped pedestal in dark stone with a bronze inscription band, for a bay whose statue isn't carved yet
local function emptyPedestal(model: Model, base: CFrame, id: string)
	local names = CODENAMES[id] or { string.upper(id), id }
	box(model, "PedestalFoot", "dark", base, -6.5, 6.5, 0, 1.2, -6.5, 6.5)
	box(model, "Pedestal", "dark", base, -5.4, 5.4, 1.2, 8, -5.4, 5.4)
	local band = box(model, "PedestalBand", "bronze", base, -5.6, 5.6, 4.6, 6.6, -5.6, 5.6)
	local gui = surface(band, Enum.NormalId.Front, 40, false)
	line(gui, names[1], { 0.05, 0.06, 0.9, 0.56 }, rgb(232, 210, 168), FONT_CARVED, nil, 60, Enum.TextXAlignment.Center)
	line(gui, names[2], { 0.05, 0.62, 0.9, 0.32 }, rgb(214, 190, 150), FONT_SANS, Enum.FontWeight.SemiBold, 30, Enum.TextXAlignment.Center)
	box(model, "PedestalCap", "marble", base, -6, 6, 8, 9, -6, 6)
end

local function buildStatueBays(folder: Instance)
	local Statues = nil
	if statuesModule then
		local ok, result = pcall(require, statuesModule)
		if ok then
			Statues = result
		else
			warn("[World] Statues didn't load: " .. tostring(result))
		end
	end
	for _, id in Powers.Order do
		local angle = BAY_ANGLES[id]
		if angle then
			local bay = Instance.new("Model")
			bay.Name = "Bay_" .. id
			local b = facingCentre(polar(angle, BAY_RADIUS, 0))
			-- A stepped stone floor, two columns, the niche with a darker recess, and the entablature
			box(bay, "BayFloor", "dark", b, -14, 14, -1, 1.2, -11, 15)
			box(bay, "BayStep", "marble", b, -12.2, 12.2, 1.2, 2, -9, 13)
			for _, x in { -12, 12 } do
				column(bay, b * CFrame.new(x, 2, -7), 46.5)
			end
			box(bay, "NicheWall", "travertine", b, -15.5, 15.5, 2, 48.5, 13, 15.5)
			box(bay, "NicheRecess", "recess", b, -8.6, 8.6, 2.6, 46, 12.6, 13, SMALL)
			for _, x in { -14.75, 14.75 } do
				box(bay, "NicheSide", "travertine", b, x - 0.75, x + 0.75, 2, 48.5, -3, 13)
			end
			local frieze = entablature(bay, b, -16.5, 16.5, 48.5, -11.2, 15.5)
			local names = CODENAMES[id] or { string.upper(id), id, "" }
			carve(frieze, Enum.NormalId.Front, names[3], 12)
			lanternStar(bay, b * CFrame.new(0, 42.5, 12.45) * CFrame.Angles(math.rad(-90), 0, 0), 3.6, 0.2, "bronze")

			-- The statue itself (or, until it is carved, its pedestal) faces the Lantern
			local base = b * CFrame.new(0, 2, 0)
			local statue = nil
			if Statues then
				local ok, result = pcall(Statues.build, id, base)
				if ok and typeof(result) == "Instance" then
					statue = result
				elseif not ok then
					warn("[World] Statue " .. id .. " didn't build: " .. tostring(result))
				end
			end
			if not statue then
				statue = Instance.new("Model")
				emptyPedestal(statue, base, id)
			end
			statue.Name = "Statue_" .. id
			-- Two warm uplights in bronze floor cups, off-axis, unless the statue brought its own
			if not statue:FindFirstChildWhichIsA("SpotLight", true) then
				for _, side in { -1, 1 } do
					local cup = stone(bay, "Uplight", "bronze", Vector3.new(1.2, 0.5, 1.2), b * CFrame.new(side * 6.6, 2.25, -8.4) * CFrame.Angles(math.rad(32), 0, math.rad(-side * 12)), SMALL)
					spotLight(cup, Enum.NormalId.Top, WARM_SPOT, 44, 2.2, 42)
				end
			end
			statue.Parent = folder
			bay.Parent = folder
		end
	end
	-- A small brass notice at the Grandmaster's bay
	local b = facingCentre(polar(BAY_ANGLES.Grandmaster, BAY_RADIUS, 0))
	local notice = box(folder, "Notice", "brass", b, 8.6, 11.6, 2.4, 4.2, -9.6, -9.4, SMALL)
	line(surface(notice, Enum.NormalId.Front, 60, false), "Please do not climb the statues. They remember.", { 0.06, 0.1, 0.88, 0.8 }, rgb(60, 44, 28), FONT_SANS, Enum.FontWeight.SemiBold, 22, Enum.TextXAlignment.Center)
end

-- Portals and doors -------------------------------------------------------------------------

-- A Meridian label beside a door: graphite with a bronze hairline, cool text
local function doorPlate(parent: Instance, f: CFrame, title: string, subline: string, chip: Color3?)
	local plate = box(parent, "DoorPlate", "brass", f, 11.4, 15.6, 7, 11.6, -0.3, 0, SMALL)
	local gui = surface(plate, Enum.NormalId.Front, 50, true)
	frame(gui, { 0, 0, 1, 1 }, SCREEN)
	local border = Instance.new("UIStroke")
	border.Color = BRONZE
	border.Transparency = 0.4
	border.Thickness = 2
	border.Parent = frame(gui, { 0.05, 0.05, 0.9, 0.9 }, SCREEN, 1)
	if chip then
		frame(gui, { 0.1, 0.2, 0.025, 0.34 }, chip)
	end
	line(gui, title, { 0.16, 0.14, 0.76, 0.44 }, IVORY_TEXT, FONT_DISPLAY, nil, 40)
	line(gui, subline, { 0.16, 0.6, 0.76, 0.24 }, HOLO, FONT_SANS, Enum.FontWeight.Medium, 26)
end

-- A monumental doorway: marble surround, a carved frieze, a cornice with a warm
-- downlight, the Lantern star above, and two bronze leaves (or none, if open).
-- `f` looks into the hall (-Z) with the wall's face at z = 0.
local function portal(parent: Instance, f: CFrame, inscription: string, closed: boolean): BasePart
	box(parent, "Threshold", "dark", f, -9, 9, -0.6, 0.25, -4, 3)
	box(parent, "Jamb", "marble", f, -10.5, -7, 0, 25.5, -1.6, 0.6)
	box(parent, "Jamb", "marble", f, 7, 10.5, 0, 25.5, -1.6, 0.6)
	box(parent, "Lintel", "marble", f, -10.5, 10.5, 22, 25.5, -1.6, 0.6)
	local frieze = box(parent, "PortalFrieze", "travertine", f, -12, 12, 26, 30, -1.2, 0)
	carve(frieze, Enum.NormalId.Front, inscription, 30)
	local cornice = box(parent, "PortalCornice", "marble", f, -13.6, 13.6, 30, 31.8, -3, 0)
	spotLight(cornice, Enum.NormalId.Bottom, WARM_SPOT, 30, 1.3, 70)
	lanternStar(parent, f * CFrame.new(0, 35, -0.15) * CFrame.Angles(math.rad(-90), 0, 0), 3.4, 0.3, "bronze")
	if closed then
		local leaf = box(parent, "PortalSurface", "bronze", f, -7, 0, 0.25, 22, 0.6, 1.8)
		box(parent, "DoorLeaf", "bronze", f, 0, 7, 0.25, 22, 0.6, 1.8)
		for _, x in { -3.5, 3.5 } do
			stone(parent, "Facet", "bronzeLight", Vector3.new(2.6, 2.6, 0.2), f * CFrame.new(x, 12, 0.5) * CFrame.Angles(0, 0, math.pi / 4), SMALL)
		end
		return leaf
	end
	return frieze
end

local function buildGate(folder: Instance, gate)
	local model = Instance.new("Model")
	model.Name = "Gate_" .. gate.id
	local f = lookAt(gate.position, gate.position + gate.facing)
	local surfacePart = portal(model, f, string.upper(gate.name), not gate.open)
	doorPlate(model, f, string.upper(gate.name), gate.sector .. "  ·  " .. gate.prompt, gate.color)
	local promptPart = surfacePart
	if gate.open then
		-- The Training Wing's leaves stand open against the reveal; walk straight through
		box(model, "DoorLeaf", "bronze", f, -7, -6.2, 0.25, 22, 1, 8.5)
		box(model, "DoorLeaf", "bronze", f, 6.2, 7, 0.25, 22, 1, 8.5)
		promptPart = box(model, "PortalSurface", "dark", f, -6, 6, 0.25, 0.3, -1, 1, GHOST)
		promptPart.Transparency = 1
	end
	local proximity = prompt(promptPart, gate.prompt, gate.name, gate.action, 0, 14)
	proximity.Name = "GatePrompt"
	model.Parent = folder
	return model
end

-- A plainer opening for a room off the hall: surround, lintel and a carved name
local function roomArch(parent: Instance, f: CFrame, width: number, height: number, inscription: string)
	local half = width / 2
	box(parent, "Jamb", "marble", f, -half - 2.6, -half, 0, height + 2.4, -1.2, 0.6)
	box(parent, "Jamb", "marble", f, half, half + 2.6, 0, height + 2.4, -1.2, 0.6)
	box(parent, "Lintel", "marble", f, -half - 2.6, half + 2.6, height, height + 2.4, -1.2, 0.6)
	local frieze = box(parent, "ArchFrieze", "travertine", f, -half - 3.2, half + 3.2, height + 2.8, height + 5.8, -0.9, 0)
	carve(frieze, Enum.NormalId.Front, inscription, 30)
	box(parent, "Threshold", "dark", f, -half, half, -0.6, 0.25, -3, 3)
end

-- Meridian routes ---------------------------------------------------------------------------

-- A paved walk through the Garden with the bronze line down its middle and the
-- destination carved on a plate where it leaves the sanctum. The walk stops at
-- the colonnade; the line runs on across the ambulatory to the threshold.
local function route(folder: Instance, angle: number, walkTo: Vector3, lineTo: Vector3, label: string)
	local model = Instance.new("Model")
	model.Name = "Route"
	local from = polar(angle, SANCTUM - 0.5)
	local a, b = Vector3.new(from.X, 0, from.Z), Vector3.new(walkTo.X, 0, walkTo.Z)
	local length = (b - a).Magnitude
	-- -Z runs toward the destination
	local f = lookAt((a + b) / 2, b)
	box(model, "Walk", "dark", f, -5, 5, -1.2, 0.06, -length / 2, length / 2)
	for _, side in { -1, 1 } do
		box(model, "Kerb", "marble", f, side * 5, side * 5.7, -1.2, 0.18, -length / 2, length / 2, SMALL)
	end
	local c = Vector3.new(lineTo.X, 0, lineTo.Z)
	local full = (c - a).Magnitude
	stone(model, "MeridianLine", "bronzeLight", Vector3.new(0.6, 0.06, full - 4.2), lookAt((a + c) / 2, c) * CFrame.new(0, 0.1, -2.1), GHOST)
	local plaque = box(model, "RoutePlate", "bronze", f, -3.8, 3.8, 0.06, 0.12, length / 2 - 3.6, length / 2 - 1.2, GHOST)
	carve(plaque, Enum.NormalId.Top, label, 50, rgb(236, 214, 170))
	model.Parent = folder
end

-- Where a route meets the colonnade on the north or south side, or the wall on the east or west
local function walkEnd(door: Vector3): Vector3
	if math.abs(door.Z) >= HALF - 1 then
		return Vector3.new(door.X, 0, math.sign(door.Z) * (HALF - 21.2))
	end
	return Vector3.new(math.sign(door.X) * (HALF - 4), 0, door.Z)
end

local function buildRoutes(folder: Instance)
	local destinations = {}
	for _, gate in Nexus.Gates do
		table.insert(destinations, { gate.angle, gate.position, string.upper(gate.name) })
	end
	table.insert(destinations, { -135, LOUNGE_DOOR, "THE LOUNGE" })
	table.insert(destinations, { -45, CALIBRATION_DOOR, "CALIBRATION" })
	table.insert(destinations, { 135, DOOR_09, "DOOR IX" })
	for _, destination in destinations do
		local door = destination[2]
		local inward = if math.abs(door.Z) >= HALF - 1 then Vector3.new(0, 0, -math.sign(door.Z)) else Vector3.new(-math.sign(door.X), 0, 0)
		route(folder, destination[1], walkEnd(door), door + inward * 3.5, destination[3])
	end
end

-- The Training Wing, beyond the west portal ----------------------------------------------

-- A long stone room round the training ground (ArenaService builds the timber
-- hall in it at Nexus.TrainingCenter), lit from above through the Institute's glass
local function buildTrainingWing(folder: Instance)
	local model = Instance.new("Model")
	model.Name = "TrainingWing"
	local o = CFrame.new()
	local x0, x1, z0, z1, top = Nexus.TrainingCenter.X - 43, -HALF - 3, -44, 44, 34
	box(model, "WingFloor", "dark", o, x0, x1, -1.4, -0.4, z0, z1)
	box(model, "WingWall", "travertine", o, x0 - 2.4, x1, -1, top, z0 - 2.4, z0)
	box(model, "WingWall", "travertine", o, x0 - 2.4, x1, -1, top, z1, z1 + 2.4)
	box(model, "WingWall", "travertine", o, x0 - 2.4, x0, -1, top, z0, z1)
	for _, z in { z0, z1 } do
		local inward = if z == z0 then 1 else -1
		box(model, "WingSkirting", "dark", o, x0, x1, -0.4, 2.6, math.min(z, z + inward * 0.6), math.max(z, z + inward * 0.6), SMALL)
		for x = x0 + 14, x1 - 10, 22 do
			box(model, "WingPilaster", "marble", o, x - 2.5, x + 2.5, -0.4, top - 4, math.min(z, z + inward * 1.2), math.max(z, z + inward * 1.2))
		end
	end
	box(model, "WingRoof", "travertine", o, x0 - 2.4, x1, top, top + 2, z0 - 2.4, z0 + 14)
	box(model, "WingRoof", "travertine", o, x0 - 2.4, x1, top, top + 2, z1 - 14, z1 + 2.4)
	block(model, "WingGlass", Vector3.new(x1 - x0, 0.3, z1 - z0 - 28), CFrame.new((x0 + x1) / 2, top + 1, 0), GLASS, M.Glass, { CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.6 })
	for x = x0 + 12, x1 - 8, 18 do
		box(model, "WingBeam", "steel", o, x - 0.6, x + 0.6, top - 0.6, top + 0.8, z0 + 14, z1 - 14, OVERHEAD)
	end
	model.Parent = folder
end

-- The Lounge ------------------------------------------------------------------------------

-- Behind the north colonnade: a long warm room in four parts, west to east the
-- hearth and library, the atrium with the leaderboard and the holotable, the
-- coffee bar with the window chairs, and the showcase with the jukebox.
local LOUNGE = { x0 = -176, x1 = -56, front = -183, back = -217.6, floor = 0.6, ceiling = 20 }
-- The library on the back wall: uprights, shelf heights, and the bay that slides away
local SHELF_UPRIGHTS = { -167, -160, -153, -146 }
local SHELF_LEVELS = { 1.2, 3.9, 6.6, 9.3, 12.0, 14.7, 17.4, 19.6 }
local SHELF_FRONT = -213.4
local SECRET = { x0 = -160, x1 = -153, top = 12.6, slideBack = Vector3.new(0, 0, -2.4), slideSide = Vector3.new(-7, 0, 0) }
local BOOK_COLORS = { rgb(112, 46, 40), rgb(38, 52, 84), rgb(52, 80, 60), rgb(176, 136, 70), rgb(214, 200, 170), rgb(64, 60, 58), rgb(150, 104, 70), rgb(92, 60, 84) }

-- Books along a shelf from x0 to x1 standing on `y`, spines toward +Z: a run or
-- two with a leaning book, and now and then a keepsake instead
local function shelfBooks(parent: Instance, x0: number, x1: number, y: number, z: number, room: number, random: Random)
	local x = x0 + random:NextNumber(0.05, 0.9)
	local ornament = random:NextNumber() < 0.3
	while x < x1 - 0.6 do
		if ornament and x > x0 + 2 then
			ornament = false
			if random:NextNumber() < 0.5 then
				block(parent, "Vase", Vector3.new(1.1, 0.7, 0.7), CFrame.new(x + 0.4, y + 0.55, z) * CFrame.Angles(0, 0, math.rad(90)), vary(rgb(70, 92, 110), random, 0.08), M.Glass, { CastShadow = false, CanCollide = false, Shape = Enum.PartType.Cylinder })
			else
				block(parent, "Keepsake", Vector3.new(1.0, 0.6, 0.9), CFrame.new(x + 0.5, y + 0.3, z) * CFrame.Angles(0, random:NextNumber(-0.3, 0.3), 0), vary(BRASS, random, 0.08), M.Metal, GHOST)
			end
			x += 1.6
		else
			local width = random:NextNumber(0.3, 0.6)
			local height = math.min(room - 0.15, random:NextNumber(1.5, 2.3))
			local lean = if x + width > x1 - 1 and random:NextNumber() < 0.5 then 0.22 else 0
			block(parent, "Book", Vector3.new(width, height, random:NextNumber(1.0, 1.3)), CFrame.new(x + width / 2, y + height / 2 - lean * 0.4, z) * CFrame.Angles(0, 0, -lean), vary(BOOK_COLORS[random:NextInteger(1, #BOOK_COLORS)], random, 0.06), M.Fabric, GHOST)
			x += width + (if random:NextNumber() < 0.15 then random:NextNumber(0.6, 1.4) else 0.02)
		end
	end
end

-- A deep sofa or armchair; `f` looks the way the seat faces (-Z)
local function sofa(parent: Instance, f: CFrame, seats: number, fabric: Color3, material: Enum.Material, accent: Color3, random: Random)
	local half = (seats * 3.1 + 1.8) / 2
	local function piece(name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, extra)
		return block(parent, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), f * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, extra)
	end
	block(parent, "SofaPlinth", Vector3.new(half * 2 - 0.4, 0.5, 3), f * CFrame.new(0, 0.25, 0), WOOD_DARK, M.Wood, SMALL)
	piece("SofaBody", -half, half, 0.5, 1.6, -1.7, 1.7, fabric)
	piece("SofaBack", -half, half, 1.6, 4.3, 0.9, 1.7, fabric)
	for _, side in { -1, 1 } do
		piece("SofaArm", side * half - 0.45, side * half + 0.45, 1.6, 3.1, -1.7, 1.7, vary(fabric, random, 0.02))
	end
	for index = 1, seats do
		local x = -half + 0.9 + (index - 0.5) * 3.1
		piece("SeatCushion", x - 1.5, x + 1.5, 1.6, 2.35, -1.7, 0.9, vary(fabric, random, 0.03), SMALL)
		block(parent, "BackCushion", Vector3.new(2.9, 1.9, 0.7), f * CFrame.new(x, 3.2, 0.5) * CFrame.Angles(math.rad(12), 0, 0), vary(fabric, random, 0.03), material, SMALL)
	end
	block(parent, "Pillow", Vector3.new(1.5, 1.5, 0.5), f * CFrame.new(half - 1.6, 3.0, 0.1) * CFrame.Angles(math.rad(14), 0.3, math.rad(8)), vary(accent, random, 0.04), M.Fabric, GHOST)
end

local function pottedPlant(parent: Instance, base: Vector3, height: number, random: Random)
	cylinder(parent, "Pot", "travertine", CFrame.new(base + Vector3.new(0, 0.9, 0)), 1.8, 2.0, SMALL)
	for index = 1, 3 do
		local angle = index / 3 * math.pi * 2 + random:NextNumber(-0.5, 0.5)
		ball(parent, "Foliage", base + Vector3.new(math.cos(angle) * 0.7, height * (0.55 + index * 0.13), math.sin(angle) * 0.7), height * random:NextNumber(0.45, 0.6), vary(pick(LEAVES, random), random, 0.06), M.LeafyGrass, GHOST)
	end
end

-- A lamp shade with a warm light inside it
local function shade(parent: Instance, position: Vector3, diameter: number, height: number, range: number, shadows: boolean): BasePart
	local made = block(parent, "LampShade", Vector3.new(height, diameter, diameter), CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)), rgb(232, 214, 182), M.Fabric, { CastShadow = false, CanCollide = false, Shape = Enum.PartType.Cylinder, Transparency = 0.15 })
	light(made, LAMP, range, 1.1, shadows)
	return made
end

local function buildLibrary(model: Model, random: Random)
	local o = CFrame.new()
	local back = SHELF_FRONT - 1.6
	for index, x in SHELF_UPRIGHTS do
		local deep = index == 1 or index == #SHELF_UPRIGHTS
		box(model, "ShelfUpright", "woodDark", o, x - 0.2, x + 0.2, LOUNGE.floor, LOUNGE.ceiling, if deep then LOUNGE.back else back - 0.3, SHELF_FRONT)
	end
	box(model, "ShelfBack", "woodDark", o, -166.8, SECRET.x0 - 0.2, LOUNGE.floor, LOUNGE.ceiling, back - 0.3, back, SMALL)
	box(model, "ShelfBack", "woodDark", o, SECRET.x1 + 0.2, -146.2, LOUNGE.floor, LOUNGE.ceiling, back - 0.3, back, SMALL)
	box(model, "ShelfBack", "woodDark", o, SECRET.x0 + 0.2, SECRET.x1 - 0.2, SECRET.top, LOUNGE.ceiling, back - 0.3, back, SMALL)
	for index, y in SHELF_LEVELS do
		local thickness = if index == 1 then 0.6 else 0.25
		for _, bay in { { -166.8, SECRET.x0 - 0.2 }, { SECRET.x1 + 0.2, -146.2 } } do
			box(model, "Shelf", "wood", o, bay[1], bay[2], y - thickness, y, back, SHELF_FRONT, SMALL)
		end
		if y > SECRET.top then
			box(model, "Shelf", "wood", o, SECRET.x0 + 0.2, SECRET.x1 - 0.2, y - thickness, y, back, SHELF_FRONT, SMALL)
		end
		local nextY = SHELF_LEVELS[index + 1]
		if nextY then
			local room = nextY - y - 0.25
			for _, bay in { { -166.8, SECRET.x0 - 0.2 }, { SECRET.x1 + 0.2, -146.2 } } do
				shelfBooks(model, bay[1], bay[2], y, back + 0.85, room, random)
			end
			if y >= SECRET.top then
				shelfBooks(model, SECRET.x0 + 0.2, SECRET.x1 - 0.2, y, back + 0.85, room, random)
			end
		end
	end

	-- The sliding bay: its own back, shelves and books, and one book that doesn't belong
	local unit = Instance.new("Model")
	unit.Name = "SecretShelf"
	unit:SetAttribute("SlideBack", SECRET.slideBack)
	unit:SetAttribute("SlideSide", SECRET.slideSide)
	box(unit, "ShelfBack", "woodDark", o, SECRET.x0 + 0.2, SECRET.x1 - 0.2, LOUNGE.floor, SECRET.top, back, back + 0.3)
	for index, y in SHELF_LEVELS do
		if y < SECRET.top then
			box(unit, "Shelf", "wood", o, SECRET.x0 + 0.2, SECRET.x1 - 0.2, y - (if index == 1 then 0.6 else 0.25), y, back + 0.3, SHELF_FRONT, SMALL)
			local nextY = math.min(SHELF_LEVELS[index + 1], SECRET.top)
			shelfBooks(unit, SECRET.x0 + 0.2, SECRET.x1 - 2.2, y, back + 0.95, nextY - y - 0.25, random)
		end
	end
	box(unit, "Shelf", "wood", o, SECRET.x0 + 0.2, SECRET.x1 - 0.2, SECRET.top - 0.25, SECRET.top, back + 0.3, SHELF_FRONT, SMALL)
	local loose = block(unit, "LooseBook", Vector3.new(0.55, 2.1, 1.2), CFrame.new(SECRET.x1 - 1.2, SHELF_LEVELS[3] + 1.05, back + 1.25), rgb(128, 34, 30), M.Fabric, GHOST)
	local pull = prompt(loose, "Pull", "A loose book", "Secret:VargaStudy", 0.5, 6)
	pull.Name = "SecretPrompt"
	unit.Parent = model
	box(model, "ShelfCrown", "woodDark", o, -167.6, -145.4, LOUNGE.ceiling - 0.6, LOUNGE.ceiling, back - 0.3, SHELF_FRONT + 0.4, SMALL)
end

local function buildLounge(folder: Instance)
	local random = Random.new(57)
	local model = Instance.new("Model")
	model.Name = "Lounge"
	local o = CFrame.new()
	local x0, x1, front, back, fl, ceil = LOUNGE.x0, LOUNGE.x1, LOUNGE.front, LOUNGE.back, LOUNGE.floor, LOUNGE.ceiling

	-- Shell: oak floor, panelled back wall (open behind the sliding bay), side walls, a beamed ceiling
	block(model, "LoungeFloor", Vector3.new(x1 - x0, fl + 0.6, front - back + 1.2), CFrame.new((x0 + x1) / 2, (fl - 0.6) / 2, (front + back) / 2), WOOD_FLOOR, M.WoodPlanks)
	block(model, "BackWall", Vector3.new(SECRET.x0 - x0 + 1.2, ceil - fl, 1.2), CFrame.new((x0 - 1.2 + SECRET.x0) / 2, (fl + ceil) / 2, back - 0.6), WOOD, M.WoodPlanks)
	block(model, "BackWall", Vector3.new(x1 + 1.2 - SECRET.x1, ceil - fl, 1.2), CFrame.new((SECRET.x1 + x1 + 1.2) / 2, (fl + ceil) / 2, back - 0.6), WOOD, M.WoodPlanks)
	block(model, "BackWall", Vector3.new(SECRET.x1 - SECRET.x0, ceil - SECRET.top, 1.2), CFrame.new((SECRET.x0 + SECRET.x1) / 2, (SECRET.top + ceil) / 2, back - 0.6), WOOD, M.WoodPlanks)
	box(model, "SideWall", "travertine", o, x0 - 1.2, x0, 0, ceil + 1.6, back - 1.2, front)
	box(model, "SideWall", "travertine", o, x1, x1 + 1.2, 0, ceil + 1.6, back - 1.2, front)
	box(model, "LoungeCeiling", "travertine", o, x0 - 1.2, x1 + 1.2, ceil, ceil + 1.6, back - 1.2, front)
	for x = -166, -56, 20 do
		box(model, "CeilingBeam", "woodDark", o, x - 0.7, x + 0.7, ceil - 1.2, ceil, back, front, SMALL)
	end
	roomArch(model, lookAt(LOUNGE_DOOR, LOUNGE_DOOR + Vector3.new(0, 0, 1)), 14, 22, "THE LOUNGE")

	-- The hearth: an ivory marble chimney breast, a long low fire, a mantel and a painting
	local hz = -199
	box(model, "Chimney", "marble", o, x0, x0 + 2.8, fl, ceil, hz - 8, hz + 8)
	box(model, "Firebox", "darker", o, x0 + 2.6, x0 + 3.0, fl + 0.6, fl + 4.2, hz - 4, hz + 4, SMALL)
	local firebed = box(model, "Firebed", "darker", o, x0 + 2.8, x0 + 4.0, fl + 0.6, fl + 1.1, hz - 3.4, hz + 3.4, SMALL)
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 4
	fire.Color = rgb(255, 150, 70)
	fire.SecondaryColor = rgb(200, 70, 30)
	fire.Parent = firebed
	light(firebed, rgb(255, 160, 90), 26, 1.8, true)
	box(model, "Hearthstone", "dark", o, x0 + 2.8, x0 + 6.4, fl, fl + 0.5, hz - 6, hz + 6)
	box(model, "Mantel", "marble", o, x0 + 2.8, x0 + 4.4, fl + 5.8, fl + 6.4, hz - 8.6, hz + 8.6)
	box(model, "PaintingFrame", "bronze", o, x0 + 2.8, x0 + 3.1, fl + 8.6, fl + 14.6, hz - 5, hz + 5, SMALL)
	local canvas = box(model, "Painting", "darker", o, x0 + 3.1, x0 + 3.2, fl + 9, fl + 14.2, hz - 4.6, hz + 4.6, SMALL)
	-- The night it came home: a dark valley, a ridge, and one bright streak
	local art = surface(canvas, Enum.NormalId.Right, 24, false)
	frame(art, { 0, 0, 1, 1 }, rgb(34, 44, 66))
	frame(art, { 0, 0.62, 1, 0.38 }, rgb(46, 58, 48))
	frame(art, { -0.1, 0.52, 0.7, 0.3 }, rgb(38, 48, 44)).Rotation = -8
	frame(art, { 0.45, 0.48, 0.8, 0.3 }, rgb(30, 40, 38)).Rotation = 6
	frame(art, { 0.56, 0.18, 0.26, 0.02 }, rgb(220, 232, 255)).Rotation = 32
	frame(art, { 0.74, 0.34, 0.03, 0.05 }, rgb(220, 232, 255))
	for index, z in { hz - 7.2, hz - 6.4 } do
		block(model, "Candle", Vector3.new(1.1 - index * 0.3, 0.35, 0.35), CFrame.new(x0 + 3.6, fl + 6.9 - index * 0.15, z) * CFrame.Angles(0, 0, math.rad(90)), LINEN, M.SmoothPlastic, { CastShadow = false, CanCollide = false, Shape = Enum.PartType.Cylinder })
	end
	box(model, "MantelClock", "bronze", o, x0 + 3.2, x0 + 4.0, fl + 6.4, fl + 7.6, hz + 5.6, hz + 7, GHOST)
	-- Biscuit, asleep on the warm stone
	local cat = CFrame.new(x0 + 5.0, fl + 0.5, hz + 3.6) * CFrame.Angles(0, 0.6, 0)
	block(model, "Cat", Vector3.new(1.3, 1.1, 1.1), cat * CFrame.new(0, 0.5, 0), rgb(196, 130, 70), M.Fabric, { CastShadow = false, CanCollide = false, Shape = Enum.PartType.Cylinder })
	ball(model, "CatHead", (cat * CFrame.new(0.75, 0.55, -0.35)).Position, 0.75, rgb(204, 140, 80), M.Fabric, GHOST)
	for _, side in { -1, 1 } do
		wedge(model, "CatEar", Vector3.new(0.12, 0.3, 0.25), cat * CFrame.new(0.75 + side * 0.18, 0.98, -0.35), rgb(190, 124, 66), M.Fabric, GHOST)
	end
	block(model, "CatTail", Vector3.new(0.22, 0.22, 1.1), cat * CFrame.new(-0.2, 0.14, 0.55) * CFrame.Angles(0, 0.9, 0), rgb(190, 124, 66), M.Fabric, GHOST)
	local tag = box(model, "CatTag", "brass", o, x0 + 5.6, x0 + 6.3, fl + 0.5, fl + 0.55, hz - 2.2, hz - 0.6, GHOST)
	line(surface(tag, Enum.NormalId.Top, 60, false), "This is Biscuit. Biscuit is not an experiment.", { 0.05, 0.1, 0.9, 0.8 }, rgb(60, 44, 28), FONT_SANS, Enum.FontWeight.SemiBold, 20, Enum.TextXAlignment.Center)

	-- The reading room: a rug, a lapis velvet sofa facing the fire, two leather armchairs
	box(model, "RugBorder", "wood", o, -170, -147, fl, fl + 0.06, hz - 9, hz + 9, GHOST).Color = RUST
	block(model, "Rug", Vector3.new(21.4, 0.09, 16.4), CFrame.new(-158.5, fl + 0.045, hz), rgb(196, 170, 132), M.Fabric, GHOST)
	sofa(model, CFrame.new(-150.5, fl, hz) * CFrame.Angles(0, math.rad(90), 0), 3, LAPIS, M.Fabric, MUSTARD, random)
	block(model, "Throw", Vector3.new(1.2, 0.16, 3.2), CFrame.new(-150.2, fl + 3.3, hz - 5.1) * CFrame.Angles(0, 0, math.rad(70)), LINEN, M.Fabric, GHOST)
	for _, z in { hz - 8.5, hz + 8.5 } do
		sofa(model, lookAt(Vector3.new(-163.5, fl, z), Vector3.new(-171, fl, hz)), 1, LEATHER, M.Leather, if z < hz then RUST else MUSTARD, random)
	end
	box(model, "CoffeeTable", "woodDark", o, -162, -156, fl + 1.5, fl + 1.85, hz - 2.4, hz + 2.4)
	box(model, "CoffeeTableBase", "darker", o, -161.4, -156.6, fl, fl + 1.5, hz - 1.8, hz + 1.8, SMALL)
	block(model, "TableBook", Vector3.new(1.6, 0.25, 2.2), CFrame.new(-160, fl + 1.98, hz - 0.8) * CFrame.Angles(0, 0.3, 0), rgb(38, 52, 84), M.Fabric, GHOST)
	block(model, "TableBook", Vector3.new(1.4, 0.22, 1.9), CFrame.new(-160, fl + 2.21, hz - 0.8) * CFrame.Angles(0, 0.1, 0), rgb(176, 136, 70), M.Fabric, GHOST)
	block(model, "Mug", Vector3.new(0.9, 0.7, 0.7), CFrame.new(-157.4, fl + 2.3, hz + 1.0) * CFrame.Angles(0, 0, math.rad(90)), rgb(226, 220, 208), M.SmoothPlastic, { CastShadow = false, CanCollide = false, Shape = Enum.PartType.Cylinder })
	-- Lamps: a standing lamp at the sofa's end and a table lamp beside it
	disc(model, "LampFoot", "bronze", Vector3.new(-149.5, fl + 0.2, hz + 8.4), 1.4, 0.2, SMALL)
	box(model, "LampPole", "bronze", o, -149.6, -149.4, fl + 0.2, fl + 6.2, hz + 8.3, hz + 8.5, SMALL)
	shade(model, Vector3.new(-149.5, fl + 6.8, hz + 8.4), 1.8, 1.4, 16, false)
	cylinder(model, "SideTable", "woodDark", CFrame.new(-150.5, fl + 1.2, hz - 8.6), 2.4, 1.8, SMALL)
	shade(model, Vector3.new(-150.5, fl + 3.3, hz - 8.6), 1.3, 1.0, 12, false)

	-- The Archive, open on its lectern by the hearth, under a soft spotlight
	local lectern = lookAt(Vector3.new(-172, fl, front - 4.5), Vector3.new(-160, fl, front - 4.5))
	box(model, "LecternFoot", "dark", lectern, -1.1, 1.1, 0, 0.4, -1.1, 1.1)
	box(model, "LecternColumn", "woodDark", lectern, -0.4, 0.4, 0.4, 4.0, -0.4, 0.4)
	local desk = stone(model, "LecternTop", "wood", Vector3.new(2.8, 0.3, 2.2), lectern * CFrame.new(0, 4.1, 0) * CFrame.Angles(math.rad(-20), 0, 0))
	local cover = block(model, "ArchiveBook", Vector3.new(2.6, 0.12, 1.9), desk.CFrame * CFrame.new(0, 0.21, 0), rgb(96, 54, 34), M.Leather, SMALL)
	for _, side in { -1, 1 } do
		block(model, "ArchivePages", Vector3.new(1.2, 0.18, 1.7), cover.CFrame * CFrame.new(side * 0.62, 0.15, 0) * CFrame.Angles(0, 0, math.rad(side * -6)), rgb(232, 222, 196), M.SmoothPlastic, GHOST)
	end
	block(model, "Ribbon", Vector3.new(0.12, 0.03, 1.4), cover.CFrame * CFrame.new(0.1, 0.27, 0.6), rgb(150, 36, 34), M.Fabric, GHOST)
	local read = prompt(cover, "Read", "The Meridian Archive", "Window:Archive", 0, 9)
	read.Name = "ArchivePrompt"
	local readingSpot = cylinder(model, "ReadingSpot", "bronze", CFrame.new(-172, ceil - 0.6, front - 4.5), 1.0, 1.2, SMALL)
	spotLight(readingSpot, Enum.NormalId.Bottom, WARM_SPOT, 22, 2.4, 36, true)

	-- A window seat in the west window, off the main path, and lapis drapes at both windows
	box(model, "WindowSeat", "wood", o, -166.5, -153.5, fl, 3.0, front - 3.2, front)
	box(model, "SeatCushion", "lapis", o, -166.2, -153.8, 3.0, 3.6, front - 3.0, front, SMALL)
	for _, x in { -165, -155.6 } do
		block(model, "Pillow", Vector3.new(1.4, 1.4, 0.45), CFrame.new(x, 4.3, front - 0.6) * CFrame.Angles(math.rad(-10), random:NextNumber(-0.3, 0.3), 0), vary(if x < -160 then MUSTARD else RUST, random, 0.04), M.Fabric, GHOST)
	end
	block(model, "Blanket", Vector3.new(3, 0.15, 2), CFrame.new(-160.5, 3.68, front - 1.6), LINEN, M.Fabric, GHOST)
	for _, x in { -160, -80 } do
		for _, side in { -1, 1 } do
			box(model, "Drape", "lapis", o, x + side * 7.2, x + side * 9.0, 1, ceil - 0.4, front - 0.5, front - 0.1, GHOST)
		end
	end

	-- A mobile of eight glass shards, one per programme, turning slowly over the reading room
	local hub = Vector3.new(-158, ceil - 5, hz)
	block(model, "MobileCord", Vector3.new(0.06, 4.8, 0.06), CFrame.new(hub + Vector3.new(0, 2.4, 0)), BRASS, M.Metal, GHOST)
	for index, programme in PROGRAMME_COLORS do
		local angle = index / #PROGRAMME_COLORS * math.pi * 2
		local radius = if index % 2 == 0 then 2.2 else 3.4
		local shard = block(model, "MobileShard", Vector3.new(0.35, 1.3, 0.35), CFrame.new(hub + Vector3.new(math.cos(angle) * radius, -(index % 3) * 0.7, math.sin(angle) * radius)) * CFrame.Angles(0, angle, math.rad(10)), programme[2]:Lerp(GLASS, 0.35), M.Glass, { CanCollide = false, CastShadow = false, Transparency = 0.25 })
		shard:SetAttribute("Spin", 0.12)
		shard:SetAttribute("SpinPivot", hub)
	end

	buildLibrary(model, random)

	-- The atrium: the leaderboard faces the door, with the echo library and the Archive's tally beside it
	local boardFrame = box(model, "LeaderboardFrame", "bronze", o, -133, -107, fl + 3.6, fl + 15.2, back, back + 0.6)
	local board = box(model, "Leaderboard", "darker", o, -132.4, -107.6, fl + 4.2, fl + 14.6, back + 0.6, back + 0.8, SMALL)
	board.Color = SCREEN
	local boardGui = surface(board, Enum.NormalId.Back, 30, true)
	boardGui.Name = "Leaderboard"
	CollectionService:AddTag(boardGui, "SNLeaderboard")
	frame(boardGui, { 0, 0, 1, 1 }, SCREEN)
	local border = Instance.new("UIStroke")
	border.Color = BRONZE
	border.Transparency = 0.4
	border.Thickness = 2
	border.Parent = frame(boardGui, { 0.02, 0.03, 0.96, 0.94 }, SCREEN, 1)
	line(boardGui, "TOP FIGHTERS", { 0.06, 0.06, 0.6, 0.16 }, IVORY_TEXT, FONT_DISPLAY, nil, 56)
	line(boardGui, "This week in the Test Chambers", { 0.06, 0.22, 0.6, 0.08 }, rgb(185, 176, 160), FONT_SANS, Enum.FontWeight.Medium, 28)
	local rows = frame(boardGui, { 0.06, 0.36, 0.88, 0.56 }, SCREEN, 1)
	rows.Name = "Rows"
	line(rows, "Results appear here after the first matches.", { 0, 0, 1, 0.16 }, rgb(142, 134, 118), FONT_SANS, nil, 26).Name = "Waiting"
	boardFrame:SetAttribute("Leaderboard", true)
	local echo = box(model, "EchoBoard", "darker", o, -141, -135, fl + 5, fl + 13, back, back + 0.3, SMALL)
	readout(echo, Enum.NormalId.Back, Vector2.new(6, 8), "ECHO LIBRARY", {
		"ATLAS    ready",
		"VEIL     ready",
		"CHIMERA  ready",
		"FURNACE  ready",
		"LATTICE  ready",
		"ECLIPSE  ready",
		"WARDEN   ready",
		"EIGHTH   declined",
	})
	local tally = box(model, "ArchiveBoard", "darker", o, -105, -99, fl + 5, fl + 13, back, back + 0.3, SMALL)
	readout(tally, Enum.NormalId.Back, Vector2.new(6, 8), "THE ARCHIVE", {
		"10 files hidden",
		"in this hall.",
		"Read them in the",
		"Archive by the fire.",
		"Tape 12: missing",
		"Door 09: sealed",
	})
	-- The holotable on the entrance axis: a slowly turning map of the hall; press to browse the programmes
	local tableAt = Vector3.new(-120, fl, -200)
	disc(model, "AtriumRug", "lapis", tableAt + Vector3.new(0, 0.06, 0), 18, 0.06, GHOST)
	disc(model, "AtriumRugBorder", "bronze", tableAt + Vector3.new(0, 0.04, 0), 19.2, 0.04, GHOST)
	cylinder(model, "HolotableBase", "bronze", CFrame.new(tableAt + Vector3.new(0, 1.4, 0)), 2.8, 2.4)
	disc(model, "Holotable", "brass", tableAt + Vector3.new(0, 3.0, 0), 6, 0.3)
	local map = block(model, "HoloMap", Vector3.new(0.05, 4.4, 4.4), CFrame.new(tableAt + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), HOLO, M.Neon, { CanCollide = false, CastShadow = false, Transparency = 0.82, Shape = Enum.PartType.Cylinder })
	local mini = block(model, "HoloLantern", Vector3.new(0.5, 1.1, 0.5), CFrame.new(tableAt + Vector3.new(0, 4.6, 0)) * CFrame.Angles(0, 0, math.rad(45)), HOLO, M.Neon, { CanCollide = false, CastShadow = false, Transparency = 0.3 })
	for _, piece in { map, mini } do
		piece:SetAttribute("Holo", true)
	end
	mini:SetAttribute("Spin", 0.5)
	mini:SetAttribute("SpinPivot", tableAt + Vector3.new(0, 4.6, 0))
	light(map, HOLO, 10, 0.7)
	local browse = prompt(map, "Browse", "Hall holotable", "Display:Holotable", 0, 8)
	browse.Name = "HolotablePrompt"
	for _, x in { -131, -109 } do
		local bench = lookAt(Vector3.new(x, fl, -191), Vector3.new(-120, fl, -214))
		box(model, "Bench", "marble", bench, -3, 3, 0, 1.6, -0.9, 0.9)
		box(model, "BenchCushion", "lapis", bench, -2.8, 2.8, 1.6, 1.9, -0.8, 0.8, SMALL)
	end

	-- The coffee bar: counter, brass machine, mugs, a menu, stools and pendants
	box(model, "BarCabinet", "woodDark", o, -96, -76, fl, fl + 3.4, back, back + 2.6)
	box(model, "BarTop", "marble", o, -96.2, -75.8, fl + 3.4, fl + 3.7, back, back + 2.9)
	box(model, "Espresso", "brass", o, -88, -85.4, fl + 3.7, fl + 5.8, back + 0.3, back + 1.9)
	box(model, "EspressoTop", "bronze", o, -88.1, -85.3, fl + 5.8, fl + 6.0, back + 0.2, back + 2.0, SMALL)
	local spout = box(model, "EspressoHead", "steel", o, -87.1, -86.3, fl + 4.6, fl + 5.0, back + 1.9, back + 2.5, GHOST)
	emitter(spout, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(rgb(240, 236, 230)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1.0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.8), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(0.4, 0.8),
		SpreadAngle = Vector2.new(10, 10),
		Rate = 1.2,
	})
	box(model, "Grinder", "steel", o, -90.2, -89.0, fl + 3.7, fl + 5.4, back + 0.6, back + 1.8, SMALL)
	for index, x in { -82.5, -81.4, -80.3 } do
		block(model, "Mug", Vector3.new(0.8, 0.65, 0.65), CFrame.new(x, fl + 4.1, back + 1.6) * CFrame.Angles(0, 0, math.rad(90)), if index == 2 then RUST else rgb(226, 220, 208), M.SmoothPlastic, { CastShadow = false, CanCollide = false, Shape = Enum.PartType.Cylinder })
	end
	box(model, "BarShelf", "wood", o, -95, -77, fl + 7.4, fl + 7.65, back, back + 1.2, SMALL)
	for index, x in { -93, -91.6, -90.2, -79, -77.6 } do
		block(model, "Jar", Vector3.new(1.2, 0.8, 0.8), CFrame.new(x, fl + 8.25, back + 0.6) * CFrame.Angles(0, 0, math.rad(90)), rgb(200, 214, 210), M.Glass, { CanCollide = false, CastShadow = false, Transparency = 0.35 + index * 0.02, Shape = Enum.PartType.Cylinder })
	end
	local menu = box(model, "MenuBoard", "darker", o, -91, -81, fl + 9, fl + 14, back, back + 0.2, SMALL)
	local menuGui = surface(menu, Enum.NormalId.Back, 40, false)
	line(menuGui, "COFFEE  ·  TEA  ·  COCOA", { 0.06, 0.08, 0.88, 0.24 }, rgb(232, 226, 210), FONT_DISPLAY, nil, 40, Enum.TextXAlignment.Center)
	line(menuGui, "Brewed fresh. Decaf is a rumour.", { 0.06, 0.4, 0.88, 0.18 }, rgb(210, 204, 190), FONT_SANS, Enum.FontWeight.Medium, 26, Enum.TextXAlignment.Center)
	line(menuGui, "Please do not warm your mug on the Lantern.", { 0.06, 0.64, 0.88, 0.18 }, rgb(196, 160, 110), FONT_SANS, Enum.FontWeight.Medium, 24, Enum.TextXAlignment.Center)
	local suggestions = box(model, "SuggestionBox", "brass", o, -95.6, -93.8, fl + 3.7, fl + 5.1, back + 1.0, back + 2.4, GHOST)
	line(surface(suggestions, Enum.NormalId.Back, 80, false), "WARDEN SUGGESTIONS. Read so far: 0", { 0.06, 0.15, 0.88, 0.7 }, rgb(40, 34, 26), FONT_SANS, Enum.FontWeight.Bold, 18, Enum.TextXAlignment.Center)
	for _, x in { -92, -86, -80 } do
		cylinder(model, "StoolPost", "bronze", CFrame.new(x, fl + 1.4, back + 4.6), 2.8, 0.3, SMALL)
		block(model, "StoolSeat", Vector3.new(0.35, 1.6, 1.6), CFrame.new(x, fl + 2.95, back + 4.6) * CFrame.Angles(0, 0, math.rad(90)), LEATHER, M.Leather, { CastShadow = false, Shape = Enum.PartType.Cylinder })
		box(model, "PendantCord", "brass", o, x - 0.03, x + 0.03, ceil - 3.6, ceil, back + 1.97, back + 2.03, GHOST)
		local pendant = cylinder(model, "Pendant", "brass", CFrame.new(x, ceil - 4.0, back + 2.0), 0.9, 1.3, GHOST)
		light(pendant, LAMP, 12, 0.9)
	end
	-- The window chairs, turned to the view of the Garden
	for _, x in { -84, -76 } do
		sofa(model, lookAt(Vector3.new(x, fl, front - 5), Vector3.new(x + (if x < -80 then 2 else -2), fl, front + 20)), 1, LEATHER, M.Leather, LINEN, random)
	end
	cylinder(model, "SideTable", "woodDark", CFrame.new(-80, fl + 0.9, front - 4.4), 1.8, 1.6, SMALL)
	for _, spot in { { -97.5, front - 2.4 }, { -58.4, front - 2.4 } } do
		pottedPlant(model, Vector3.new(spot[1], fl, spot[2]), 6.5, random)
	end

	-- The showcase: a lit stage to stand on and show off, the jukebox and its dance floor
	local stageAt = Vector3.new(-66, fl, -200)
	local stage = disc(model, "ShowcaseStage", "dark", stageAt + Vector3.new(0, 0.6, 0), 9, 0.6)
	stage:SetAttribute("EmoteSpot", true)
	stage:SetAttribute("Showcase", true)
	disc(model, "StageRing", "bronzeLight", stageAt + Vector3.new(0, 0.63, 0), 8.2, 0.04, GHOST)
	disc(model, "StageTop", "dark", stageAt + Vector3.new(0, 0.65, 0), 7.6, 0.04, GHOST)
	local stageSpot = cylinder(model, "StageSpot", "bronze", CFrame.new(stageAt + Vector3.new(0, ceil - fl - 0.6, 0)), 1.0, 1.2, SMALL)
	spotLight(stageSpot, Enum.NormalId.Bottom, rgb(255, 236, 214), 24, 2.6, 34, true)
	local showcase = box(model, "ShowcasePlate", "brass", o, -70, -62, fl + 0.6, fl + 1.2, -205.2, -205, SMALL)
	line(surface(showcase, Enum.NormalId.Back, 50, false), "SHOWCASE", { 0.05, 0.1, 0.9, 0.8 }, rgb(60, 44, 28), FONT_DISPLAY, nil, 24, Enum.TextXAlignment.Center)
	local juke = lookAt(Vector3.new(x1 - 2.6, fl, back + 3.4), Vector3.new(-70, fl, -204))
	block(model, "Jukebox", Vector3.new(3.0, 4.6, 2.0), juke * CFrame.new(0, 2.3, 0), WOOD_DARK, M.Wood)
	block(model, "JukeboxCrown", Vector3.new(2.0, 3.0, 3.0), juke * CFrame.new(0, 4.6, 0) * CFrame.Angles(0, math.rad(90), 0), WOOD_DARK, M.Wood, { Shape = Enum.PartType.Cylinder })
	local glow = block(model, "JukeboxGlow", Vector3.new(2.4, 2.2, 0.1), juke * CFrame.new(0, 3.3, -1.02), rgb(255, 196, 128), M.Glass, { CastShadow = false, CanCollide = false, Transparency = 0.2 })
	light(glow, rgb(255, 170, 100), 10, 0.9)
	stone(model, "JukeboxGrille", "brass", Vector3.new(2.2, 1.4, 0.1), juke * CFrame.new(0, 1.2, -1.02), GHOST)
	local juking = prompt(glow, "Choose a song", "Jukebox", "Jukebox", 0, 8)
	juking.Name = "JukeboxPrompt"
	local dance = box(model, "DanceFloor", "darker", o, -74, -62, fl, fl + 0.08, back + 1.2, back + 9.2, GHOST)
	dance:SetAttribute("EmoteSpot", true)
	local tiles = surface(dance, Enum.NormalId.Top, 10, false)
	for row = 0, 3 do
		for column = 0, 5 do
			local cell = frame(tiles, { column / 6 + 0.005, row / 4 + 0.01, 1 / 6 - 0.01, 1 / 4 - 0.02 }, if (row + column) % 2 == 0 then rgb(214, 206, 190) else rgb(60, 56, 52))
			cell:SetAttribute("Disco", row * 6 + column)
		end
	end
	-- A little maintenance drone hovers by the coffee bar, waiting for crumbs
	local drone = Vector3.new(-78, fl + 9, back + 5)
	for _, piece in {
		stone(model, "DroneBody", "brass", Vector3.new(1.2, 0.5, 1.2), CFrame.new(drone), GHOST),
		block(model, "DroneEye", Vector3.new(0.4, 0.12, 0.08), CFrame.new(drone + Vector3.new(0, 0, 0.62)), HOLO, M.Neon, GHOST),
		stone(model, "DroneRotor", "steel", Vector3.new(2.2, 0.06, 0.2), CFrame.new(drone + Vector3.new(0, 0.32, 0)) * CFrame.Angles(0, 0.8, 0), GHOST),
	} do
		piece:SetAttribute("Bob", 0.4)
	end
	model.Parent = folder
end

-- Dr. Varga's study, behind the sliding bay of the library ---------------------------------

local function buildStudy(folder: Instance)
	local random = Random.new(63)
	local model = Instance.new("Model")
	model.Name = "VargaStudy"
	local o = CFrame.new()
	local fl, top = LOUNGE.floor, 13.6
	local x0, x1, z0, z1 = -167, -146, -234, LOUNGE.back - 1.2
	box(model, "StudyFloor", "woodDark", o, x0, x1, fl - 1, fl, z0, z1)
	box(model, "StudyWall", "travertine", o, x0 - 1.2, x0, 0, top, z0 - 1.2, z1)
	box(model, "StudyWall", "travertine", o, x1, x1 + 1.2, 0, top, z0 - 1.2, z1)
	box(model, "StudyWall", "wood", o, x0, x1, fl, top, z0 - 1.2, z0)
	box(model, "StudyCeiling", "woodDark", o, x0 - 1.2, x1 + 1.2, top, top + 1, z0 - 1.2, z1)
	block(model, "StudyRug", Vector3.new(12, 0.06, 8), CFrame.new(-156.5, fl + 0.03, -226), rgb(120, 52, 40), M.Fabric, GHOST)
	-- Her desk against the far wall, the green lamp still on
	box(model, "Desk", "wood", o, -160.5, -152.5, fl + 2.8, fl + 3.1, z0 + 0.4, z0 + 3.2)
	for _, x in { -159.5, -153.5 } do
		box(model, "DeskPedestal", "woodDark", o, x - 1, x + 1, fl, fl + 2.8, z0 + 0.6, z0 + 3.0, SMALL)
	end
	box(model, "DeskChair", "woodDark", o, -157.5, -155.5, fl + 1.6, fl + 1.9, z0 + 3.6, z0 + 5.6, SMALL).Color = LEATHER
	box(model, "DeskChairBack", "woodDark", o, -157.5, -155.5, fl + 1.9, fl + 4.2, z0 + 5.4, z0 + 5.7, SMALL).Color = LEATHER
	box(model, "DeskChairPost", "bronze", o, -156.7, -156.3, fl, fl + 1.6, z0 + 4.4, z0 + 4.8, SMALL)
	box(model, "LampStem", "brass", o, -154.2, -153.9, fl + 3.1, fl + 4.2, z0 + 1.0, z0 + 1.3, GHOST)
	local lampShade = block(model, "BankersLamp", Vector3.new(1.8, 0.5, 0.8), CFrame.new(-154.0, fl + 4.4, z0 + 1.4) * CFrame.Angles(math.rad(-10), 0, 0), rgb(40, 110, 70), M.Glass, { CanCollide = false, CastShadow = false, Transparency = 0.2 })
	light(lampShade, rgb(255, 210, 150), 16, 1.3)
	-- Tape 12, still in the machine
	local recorder = box(model, "TapeRecorder", "steel", o, -159.9, -157.5, fl + 3.1, fl + 3.6, z0 + 1.0, z0 + 2.4, GHOST)
	for _, x in { -159.3, -158.1 } do
		block(model, "TapeReel", Vector3.new(0.06, 0.8, 0.8), CFrame.new(x, fl + 3.66, z0 + 1.7) * CFrame.Angles(0, 0, math.rad(90)), rgb(30, 30, 30), M.SmoothPlastic, { CastShadow = false, CanCollide = false, Shape = Enum.PartType.Cylinder })
	end
	loreFile(recorder, "varga_tape_12", "Tape 12")
	-- Chalkboard: her working, and the question she kept coming back to
	local chalk = box(model, "Chalkboard", "darker", o, x0, x0 + 0.2, fl + 3, fl + 10, z0 + 2, z0 + 12, SMALL)
	local board = surface(chalk, Enum.NormalId.Right, 30, false)
	line(board, "WHY DOES IT HUM?", { 0.06, 0.06, 0.88, 0.16 }, rgb(226, 226, 214), FONT_SANS, Enum.FontWeight.Bold, 40)
	line(board, "output(t) ~ 1 / distance to someone it knows", { 0.06, 0.3, 0.88, 0.12 }, rgb(200, 204, 194), FONT_MONO, nil, 24)
	line(board, "8 lines in the registry. 7 programmes. 1 refusal.", { 0.06, 0.48, 0.88, 0.12 }, rgb(200, 204, 194), FONT_MONO, nil, 24)
	line(board, "Ask G. again?  NO.", { 0.06, 0.68, 0.88, 0.12 }, rgb(226, 190, 150), FONT_SANS, Enum.FontWeight.SemiBold, 28)
	-- A pinboard map of the hall: ten pins where things were left behind
	local cork = box(model, "Pinboard", "wood", o, x1 - 0.2, x1, fl + 3.5, fl + 9.5, z0 + 4, z0 + 12, SMALL)
	cork.Color = rgb(176, 140, 96)
	local pins = surface(cork, Enum.NormalId.Left, 30, false)
	frame(pins, { 0.1, 0.1, 0.8, 0.72 }, rgb(226, 216, 190))
	line(pins, "Things they left behind", { 0.1, 0.84, 0.8, 0.12 }, rgb(70, 50, 34), FONT_SANS, Enum.FontWeight.SemiBold, 26, Enum.TextXAlignment.Center)
	for index, spot in { { 0.52, 0.47 }, { 0.48, 0.52 }, { 0.5, 0.97 }, { 0.12, 0.66 }, { 0.84, 0.95 }, { 0.8, 0.2 }, { 0.06, 0.02 }, { 0.38, 0.97 }, { 0.2, 0.97 }, { 0.22, 0.02 } } do
		frame(pins, { 0.1 + spot[1] * 0.76, 0.1 + spot[2] * 0.66, 0.03, 0.04 }, if index % 3 == 0 then rgb(170, 50, 40) else rgb(40, 90, 150)).Rotation = 45
	end
	-- Her own shelf, and the reward for finding the room: a fragment of the Lantern under glass
	box(model, "StudyShelf", "woodDark", o, x0 + 1, x0 + 4.6, fl, fl + 7, z0, z0 + 1.3)
	for _, y in { fl + 2.4, fl + 4.8 } do
		shelfBooks(model, x0 + 1.2, x0 + 4.4, y - 0.1, z0 + 0.65, 2.2, random)
	end
	local stand = Vector3.new(x1 - 2.6, fl, z0 + 2.4)
	cylinder(model, "FragmentPlinth", "marble", CFrame.new(stand + Vector3.new(0, 1.6, 0)), 3.2, 1.6)
	local fragment = block(model, "LanternFragment", Vector3.new(0.4, 0.9, 0.4), CFrame.new(stand + Vector3.new(0, 4.0, 0)) * CFrame.Angles(0, 0.6, math.rad(20)), HOLO, M.Neon, { CanCollide = false, CastShadow = false, Transparency = 0.15 })
	fragment:SetAttribute("Spin", 0.35)
	fragment:SetAttribute("SpinPivot", stand + Vector3.new(0, 4.0, 0))
	light(fragment, rgb(208, 226, 255), 12, 1.2)
	ball(model, "Dome", stand + Vector3.new(0, 4.0, 0), 2.2, GLASS, M.Glass, { CanCollide = false, CastShadow = false, Transparency = 0.6 })
	emitter(fragment, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(rgb(226, 238, 255)),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.5, 0.14), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.3, 1),
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(0.1, 0.3),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 1.5,
	})
	local card = block(model, "FragmentCard", Vector3.new(1.8, 0.05, 0.9), CFrame.new(stand + Vector3.new(0, 3.24, 0.6)) * CFrame.Angles(math.rad(15), 0, 0), rgb(226, 216, 190), M.SmoothPlastic, GHOST)
	line(surface(card, Enum.NormalId.Top, 80, false), "Fragment 3. It hums when someone it knows is near.", { 0.05, 0.1, 0.9, 0.8 }, rgb(60, 44, 28), FONT_SANS, Enum.FontWeight.Medium, 16, Enum.TextXAlignment.Center)
	local certificate = box(model, "Certificate", "marble", o, -162.5, -158.5, fl + 6.5, fl + 9.5, z0, z0 + 0.1, GHOST)
	local certificateGui = surface(certificate, Enum.NormalId.Back, 60, false)
	line(certificateGui, "EMPLOYEE OF THE MONTH", { 0.06, 0.1, 0.88, 0.25 }, rgb(120, 90, 40), FONT_DISPLAY, nil, 24, Enum.TextXAlignment.Center)
	line(certificateGui, "The Lantern (again)", { 0.06, 0.45, 0.88, 0.3 }, rgb(60, 44, 28), FONT_SANS, Enum.FontWeight.SemiBold, 28, Enum.TextXAlignment.Center)
	-- A brass lever by the doorway works the shelf from this side
	local lever = box(model, "StudyLever", "brass", o, SECRET.x0 - 1.6, SECRET.x0 - 1.0, fl + 4.5, fl + 6.0, z1 - 0.6, z1, GHOST)
	local use = prompt(lever, "Pull", "Shelf lever", "Secret:VargaStudy", 0.3, 6)
	use.Name = "SecretPrompt"
	model.Parent = folder
end

-- Builds the whole lobby into `folder`. Returns the spawn location.
function Nexus.build(folder: Instance): SpawnLocation
	tone = Random.new(17)
	if not buildTerrain() then
		-- No terrain (or it failed): a plain grass slab instead
		block(folder, "Ground", Vector3.new(2 * INNER, 2, 2 * INNER), CFrame.new(0, GROUND_Y - 1, 0), rgb(98, 122, 62), M.Grass)
	end
	buildHall(folder)
	local spawn = buildSanctum(folder)
	buildStatueBays(folder)
	for _, gate in Nexus.Gates do
		buildGate(folder, gate)
	end
	buildRoutes(folder)
	buildTrainingWing(folder)
	buildLounge(folder)
	buildStudy(folder)
	return spawn :: SpawnLocation
end

return Nexus
