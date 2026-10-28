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
	return spawn :: SpawnLocation
end

return Nexus
