-- THE HUB: the facility's central atrium and the lobby everyone spawns into
-- (docs/ArtDirection.md, "The Facility"; DECISIONS.md 5-8). An enclosed octagonal
-- hall, no terrain and no grass anywhere. Plan, from the middle outward:
--   dais        three stepped ivory octagons carrying the Lantern in its bronze ring
--   plaza       dark slate tiles with seams, inlaid steel and light strips; the eight
--               statue spots ring the dais (corners of the octagon, facing the Lantern)
--   gallery     darker basalt with a brushed-steel band, running to the walls
--   walls       eight ceramic-and-navy sides, each with a lit portal alcove and a sign
--   ceiling     a layered octagonal ring with ribs and light panels, a glazed drum above
--               it and a glass roof over the Lantern
-- Angles are degrees from +X towards +Z (Nexus convention). The eight portals sit on the
-- side centres (multiples of 45), the statues on the corners (22.5 + 45 k).
--
-- Portals (Hub.Gates, mirrored as Nexus.Gates): each is a Model "Portal_<id>" holding the
-- lit frame, the sign (room name, wayfinding mark, subtitle) and a PortalSurface with a
-- ProximityPrompt whose attribute "Action" the client reads (WorldFxController):
--   Entrance         Travel:Lobby      Test Chambers    Travel:Concourse
--   Training Studio  Travel:Training   Jeffery's Base   Window:Learn (falls back to Play)
--   Spectating       Window:Watch      Master Shop      Window:Market
--   Player Base St.  Base:Street      Calibration      Window:Powers (+ CFrameValue "PreviewCamera")
-- The Archive stand (Window:Archive) is a ninth entry, flagged `stand`, near the spawn.
-- Wings behind the portals are built later; the prompts already route to what exists.
--
-- Folder "Guides" (for onboarding): one Folder per destination id, holding invisible
-- anchored Parts named "1", "2", ... in walking order from the spawn to the portal front.
-- Attributes: Label (destination name). The tutorial walks a player through them.
--
-- Everything overhead ignores raycasts so decorations still land on the floor. Parts that
-- the client animates carry the attributes Crystal / Pulse (see WorldFxController).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Powers = require(ReplicatedStorage.Shared.Powers)

local Hub = {}

local rgb = Color3.fromRGB
local M = Enum.Material

-- Geometry -----------------------------------------------------------------------------------
local R = 88 -- apothem: centre of the hub to the middle of each wall
local WALL = 8 -- wall thickness
local H = 48 -- wall height; the ring ceiling sits on it
local DRUM_R = 52 -- apothem of the glazed drum
local DRUM_TOP = 72
local STATUE_R = 42
local TAN = math.tan(math.rad(22.5))
local CRYSTAL_HEIGHT = 15

Hub.Radius = R
Hub.TrainingCenter = Vector3.new(-236, 0, 0)

-- Palette (ArtDirection section 2)
local NAVY = rgb(14, 22, 36)
local CHARCOAL = rgb(30, 33, 38)
local GRAPHITE = rgb(35, 39, 46)
local TILE = rgb(40, 43, 49)
local TILE_DARK = rgb(27, 29, 33)
local SEAM = rgb(12, 13, 16)
local STEEL = rgb(138, 146, 156)
local CERAMIC = rgb(158, 164, 172)
local IVORY = rgb(222, 214, 198)
local AMBER = rgb(232, 162, 74)
local COPPER = rgb(184, 115, 63)
local CYAN = rgb(63, 214, 232)
local WARM = rgb(255, 214, 166)
local COOL = rgb(200, 224, 255)
local TEXT = rgb(232, 238, 244)
local MUTED = rgb(150, 160, 172)

local FONT_SANS = "rbxasset://fonts/families/BuilderSans.json"
local FONT_DISPLAY = "rbxasset://fonts/families/Michroma.json"

local SMALL = { CastShadow = false }
local GHOST = { CastShadow = false, CanCollide = false }
local OVERHEAD = { CanCollide = false, CanQuery = false }

-- Destinations ---------------------------------------------------------------------------------
-- `position` is the floor point in front of the portal, `facing` points into the hub.
local function polar(angle: number, radius: number, y: number?): Vector3
	local radians = math.rad(angle)
	return Vector3.new(math.cos(radians) * radius, y or 0, math.sin(radians) * radius)
end

local function gate(id, name, subtitle, angle, color, action, prompt, extra)
	local entry = {
		id = id,
		name = name,
		sector = subtitle,
		subtitle = subtitle,
		angle = angle,
		color = color,
		action = action,
		prompt = prompt,
		position = polar(angle, R - 4),
		facing = -polar(angle, 1),
	}
	for key, value in extra or {} do
		entry[key] = value
	end
	return entry
end

-- Wayfinding colours (ArtDirection section 2)
local COMBAT = rgb(224, 122, 58)
local TRAINING = rgb(63, 214, 232)
local SOCIAL = rgb(242, 230, 208)
local PERSONAL = rgb(95, 196, 138)
local SPECIAL = rgb(142, 123, 224)
local EXPANSION = rgb(224, 106, 106)

Hub.Gates = {
	gate("Entrance", "ENTRANCE", "Spawn and arrivals", 90, SOCIAL, "Travel:Lobby", "Return to spawn", { open = true }),
	gate("Battle", "TEST CHAMBERS", "Battleground concourse", 0, COMBAT, "Travel:Concourse", "Enter the concourse"),
	gate("Training", "TRAINING STUDIO", "Practise on dummies", 180, TRAINING, "Travel:Training", "Go to training", { open = true }),
	gate("Learn", "JEFFERY'S BASE", "How to play", -135, SOCIAL, "Window:Learn", "Learn to play"),
	gate("Watch", "SPECTATING LOUNGE", "Watch live matches", 45, SOCIAL, "Window:Watch", "Watch a match"),
	gate("Market", "MASTER SHOP", "Powers, cosmetics, passes", 135, EXPANSION, "Window:Market", "Open the shop"),
	gate("Homes", "PLAYER BASE STREET", "Your base and friends' bases", -90, PERSONAL, "Base:Street", "Enter the street"),
	gate("Calibration", "CALIBRATION CHAMBER", "Meet the eight fighters", -45, SPECIAL, "Window:Powers", "View fighters"),
	-- The Archive book stand has no portal: it stands between the dais and the spawn
	{
		id = "Archive",
		name = "THE ARCHIVE",
		sector = "Lore book",
		subtitle = "Lore book",
		angle = 67.5,
		color = SOCIAL,
		action = "Window:Archive",
		prompt = "Read",
		position = polar(67.5, 24),
		facing = -polar(67.5, 1),
		stand = true,
	},
}

-- Building blocks ------------------------------------------------------------------------------

local function make(parent: Instance, props: { [string]: any }): BasePart
	local instance = Instance.new(props.ClassName or "Part") :: BasePart
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	instance.Material = M.SmoothPlastic
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

-- Local frame at distance `r` from the middle along `angle`: -Z points to the Lantern, +Z out
-- to the wall, +X to the right as you face the Lantern.
local function frameAt(angle: number, r: number): CFrame
	local radians = math.rad(angle)
	local c, s = math.cos(radians), math.sin(radians)
	return CFrame.fromMatrix(Vector3.new(c * r, 0, s * r), Vector3.new(s, 0, -c), Vector3.new(0, 1, 0), Vector3.new(c, 0, s))
end

-- A box in the local coordinates of `f`, given by its extents
local function bx(parent: Instance, name: string, f: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local props = if extra then table.clone(extra) else {}
	props.Name = name
	props.Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0)
	props.CFrame = f * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	props.Color = color
	props.Material = material
	return make(parent, props)
end

-- One of the eight trapezoids of an octagonal ring between apothems rIn and rOut. Rectangles
-- sized for the outer edge overlap their neighbours in the corners, so `nudge` lifts each a hair.
local function slab(parent: Instance, name: string, side: number, rIn: number, rOut: number, y0: number, y1: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local half = rOut * TAN + 0.1
	return bx(parent, name, frameAt(side * 45, 0), -half, half, y0 + side * 0.004, y1 + side * 0.004, rIn, rOut, color, material, extra)
end

local function ring(parent: Instance, name: string, rIn: number, rOut: number, y0: number, y1: number, color: Color3, material: Enum.Material, extra: { [string]: any }?)
	for side = 0, 7 do
		slab(parent, name, side, rIn, rOut, y0, y1, color, material, extra)
	end
end

local function disc(parent: Instance, name: string, center: Vector3, diameter: number, thickness: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local props = if extra then table.clone(extra) else {}
	props.Name = name
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(thickness, diameter, diameter)
	props.CFrame = CFrame.new(center.X, center.Y - thickness / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90))
	props.Color = color
	props.Material = material
	return make(parent, props)
end

local function lamp(parent: Instance, position: Vector3, color: Color3, range: number, brightness: number, shadows: boolean?): PointLight
	local holder = make(parent, { Name = "Lamp", Size = Vector3.new(0.4, 0.4, 0.4), CFrame = CFrame.new(position), Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local point = Instance.new("PointLight")
	point.Color = color
	point.Range = range
	point.Brightness = brightness
	point.Shadows = shadows == true
	point.Parent = holder
	return point
end

local function surface(target: BasePart, face: Enum.NormalId, pixelsPerStud: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.Parent = target
	return gui
end

local function label(gui: Instance, text: string, area: { number }, color: Color3, font: string, maxSize: number, align: Enum.TextXAlignment?): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Position = UDim2.fromScale(area[1], area[2])
	item.Size = UDim2.fromScale(area[3], area[4])
	item.Text = text
	item.FontFace = Font.new(font, Enum.FontWeight.Regular)
	item.TextColor3 = color
	item.TextScaled = true
	item.TextWrapped = true
	item.TextXAlignment = align or Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = maxSize
	cap.Parent = item
	item.Parent = gui
	return item
end

local function swatch(gui: Instance, area: { number }, color: Color3)
	local item = Instance.new("Frame")
	item.BorderSizePixel = 0
	item.BackgroundColor3 = color
	item.Position = UDim2.fromScale(area[1], area[2])
	item.Size = UDim2.fromScale(area[3], area[4])
	item.Parent = gui
end

local function prompt(parent: Instance, actionText: string, objectText: string, action: string, distance: number): ProximityPrompt
	local proximity = Instance.new("ProximityPrompt")
	proximity.ActionText = actionText
	proximity.ObjectText = objectText
	proximity.HoldDuration = 0
	proximity.MaxActivationDistance = distance
	proximity.RequiresLineOfSight = false
	-- E, F, Q and the gamepad face buttons are combat keys, so the world uses T / D-pad right
	proximity.KeyboardKeyCode = Enum.KeyCode.T
	proximity.GamepadKeyCode = Enum.KeyCode.DPadRight
	proximity:SetAttribute("Action", action)
	proximity.Parent = parent
	return proximity
end

-- Structure ------------------------------------------------------------------------------------

local function buildFloor(folder: Instance)
	local model = Instance.new("Model")
	model.Name = "Floor"
	-- Foundation: one dark slab under everything (its corners lie outside the walls)
	bx(model, "Foundation", CFrame.new(), -(R + WALL) * 1.1, (R + WALL) * 1.1, -8, -0.3, -(R + WALL) * 1.1, (R + WALL) * 1.1, TILE_DARK, M.Concrete)

	-- Dais: three stepped ivory octagons
	ring(model, "DaisStep", 0, 17, -0.3, 1.0, IVORY, M.Marble)
	ring(model, "DaisStep", 0, 14, 0.9, 2.0, IVORY, M.Marble)
	ring(model, "DaisStep", 0, 11, 1.9, 3.0, IVORY, M.Marble)
	ring(model, "DaisRing", 10.2, 10.8, 2.98, 3.06, COPPER, M.Metal, SMALL)
	-- Plaza: dark slate tiles; gallery: darker basalt
	ring(model, "PlazaTile", 17, 58, -0.3, 0, TILE, M.Slate, { Reflectance = 0.06 })
	ring(model, "GalleryTile", 58, R, -0.3, 0, TILE_DARK, M.Basalt, { Reflectance = 0.08 })
	-- Seams: radial joints in the plaza, concentric joints in both zones
	for side = 0, 7 do
		local f = frameAt(side * 45, 0)
		for _, x in { -22, -11, 0, 11, 22 } do
			bx(model, "Seam", f, x - 0.075, x + 0.075, 0, 0.03, 17.6, 57.6, SEAM, M.SmoothPlastic, GHOST)
		end
	end
	for _, r in { 27, 36, 50 } do
		ring(model, "Seam", r, r + 0.15, 0, 0.03, SEAM, M.SmoothPlastic, GHOST)
	end
	for _, r in { 66, 76 } do
		ring(model, "Seam", r, r + 0.15, 0, 0.03, SEAM, M.SmoothPlastic, GHOST)
	end
	-- Inlays: brushed steel bands, one cyan hairline (the single cold accent), an amber ring round the dais
	ring(model, "SteelInlay", 57, 58, 0, 0.06, STEEL, M.Metal, SMALL)
	ring(model, "SteelInlay", 17, 17.5, 0, 0.06, STEEL, M.Metal, SMALL)
	ring(model, "AmberInlay", 18.2, 18.5, 0, 0.07, AMBER, M.Neon, GHOST)
	ring(model, "CyanInlay", 56.2, 56.45, 0, 0.07, CYAN, M.Neon, GHOST)
	-- Wayfinding inlays run from the dais to each portal, in the destination's colour
	for _, entry in Hub.Gates do
		if not entry.stand then
			local f = frameAt(entry.angle, 0)
			local strip = bx(model, "Wayfinding_" .. entry.id, f, -0.3, 0.3, 0, 0.08, 19, R - 7.5, entry.color, M.Neon, GHOST)
			strip.Transparency = 0.15
			strip:SetAttribute("Pulse", 0)
			bx(model, "WayfindingEdge", f, -0.75, 0.75, 0, 0.05, 19, R - 7.5, STEEL, M.Metal, GHOST)
		end
	end
	-- Statue spots: a dark steel disc with a thin ring
	for index = 1, 8 do
		local at = polar(22.5 + (index - 1) * 45, STATUE_R)
		disc(model, "StatueSpot", Vector3.new(at.X, 0.12, at.Z), 19, 0.12, GRAPHITE, M.Metal)
		disc(model, "StatueSpotRing", Vector3.new(at.X, 0.14, at.Z), 17.2, 0.04, STEEL, M.Metal, GHOST)
	end
	model.Parent = folder
end

local function buildWalls(folder: Instance)
	local model = Instance.new("Model")
	model.Name = "Walls"
	for side = 0, 7 do
		local f = frameAt(side * 45, R)
		local half = (R + WALL) * TAN + 0.5
		local gate = nil
		for _, entry in Hub.Gates do
			if not entry.stand and entry.angle % 360 == side * 45 % 360 then
				gate = entry
			end
		end
		-- Structure: two piers, a lintel above the alcove, a back panel at the far side of the alcove
		bx(model, "Pier", f, -half, -7.5, 0, H, 0, WALL - 2, NAVY, M.Concrete)
		bx(model, "Pier", f, 7.5, half, 0, H, 0, WALL - 2, NAVY, M.Concrete)
		bx(model, "Lintel", f, -7.5, 7.5, 23, H, 0, WALL - 2, NAVY, M.Concrete)
		bx(model, "AlcoveBack", f, -7.5, 7.5, 0, 23, WALL - 3, WALL - 2, GRAPHITE, M.Metal)
		bx(model, "WallShell", f, -half, half, 0, H, WALL - 2, WALL, CHARCOAL, M.Concrete)
		-- Cladding: ceramic panels with reveals on the piers, a steel skirting along the foot
		local reach = R * TAN - 0.5
		for _, span in { { -reach, -7.9 }, { 7.9, reach } } do
			local width = (span[2] - span[1]) / 2
			for part = 0, 1 do
				local x0 = span[1] + part * width + 0.15
				bx(model, "Cladding", f, x0, x0 + width - 0.3, 1.5, 36, -0.5, 0, CERAMIC, M.SmoothPlastic, SMALL)
			end
		end
		bx(model, "Skirting", f, -reach, reach, 0, 1.5, -0.7, 0, STEEL, M.Metal, SMALL)
		-- Light cove: a steel ledge with a thin warm strip under it, above the cladding
		for _, span in { { -reach, -8 }, { 8, reach } } do
			bx(model, "CoveLedge", f, span[1], span[2], 36.4, 37.4, -1.4, 0, STEEL, M.Metal, SMALL)
			local strip = bx(model, "CoveLight", f, span[1], span[2], 36.1, 36.3, -0.6, -0.4, AMBER, M.Neon, GHOST)
			strip.Transparency = 0.1
		end
		-- Upper wall: a band of dark glazing with mullions under the ceiling
		bx(model, "UpperBand", f, -reach, reach, 38, H - 1, -0.4, 0, GRAPHITE, M.Metal, SMALL)
		for k = -4, 4 do
			bx(model, "Mullion", f, k * 6.3 - 0.2, k * 6.3 + 0.2, 38, H - 1, -0.9, -0.3, STEEL, M.Metal, SMALL)
		end
		if gate then
			-- Alcove reveals and lit frame
			bx(model, "Reveal", f, -8.2, -7.5, 0, 23.8, -1.6, WALL - 3, STEEL, M.Metal)
			bx(model, "Reveal", f, 7.5, 8.2, 0, 23.8, -1.6, WALL - 3, STEEL, M.Metal)
			bx(model, "Reveal", f, -8.2, 8.2, 23, 23.8, -1.6, WALL - 3, STEEL, M.Metal)
		end
	end
	-- Corner posts at the eight vertices, chamfered by a second rotated box
	for corner = 0, 7 do
		local f = frameAt(corner * 45 + 22.5, R / math.cos(math.rad(22.5)))
		bx(model, "CornerPost", f, -1.8, 1.8, 0, H, -2, 1.6, STEEL, M.Metal)
		bx(model, "CornerCore", f, -0.4, 0.4, 0, H, -2.2, -2, AMBER, M.Neon, GHOST)
	end
	model.Parent = folder
end

local function buildCeiling(folder: Instance)
	local model = Instance.new("Model")
	model.Name = "Ceiling"
	-- Ring ceiling over the gallery and plaza, with a step up to the drum
	ring(model, "CeilingPlate", DRUM_R, R + WALL, H, H + 2, CHARCOAL, M.Metal, OVERHEAD)
	ring(model, "CeilingSoffit", DRUM_R, R, H - 1, H, GRAPHITE, M.Metal, OVERHEAD)
	-- Ribs: radial beams on every side centre and corner, two ring beams between them
	for index = 0, 15 do
		local f = frameAt(index * 22.5, 0)
		bx(model, "Rib", f, -0.9, 0.9, H - 3.5, H - 1, DRUM_R, R, STEEL, M.Metal, OVERHEAD)
	end
	for _, r in { 62, 74 } do
		ring(model, "RingBeam", r, r + 1.6, H - 3, H - 1, STEEL, M.Metal, OVERHEAD)
	end
	-- Light panels recessed between the ribs (warm key, soft)
	for index = 0, 7 do
		local f = frameAt(index * 45 + 11.25, 0)
		local panel = bx(model, "LightPanel", f, -2.5, 2.5, H - 1.15, H - 1, 64, 72, WARM, M.Neon, OVERHEAD)
		panel.Transparency = 0.25
		lamp(model, polar(index * 45 + 11.25, 68, H - 5), WARM, 52, 0.9, false)
	end
	-- Glazed drum above the ceiling: solid kerb, glass between mullions, a cap beam
	for side = 0, 7 do
		local f = frameAt(side * 45, DRUM_R)
		local half = DRUM_R * TAN + 0.4
		bx(model, "DrumKerb", f, -half, half, H, H + 5, -0.6, 0.6, NAVY, M.Metal, OVERHEAD)
		local glass = bx(model, "DrumGlass", f, -half + 1, half - 1, H + 5, DRUM_TOP - 2, -0.15, 0.15, rgb(190, 214, 224), M.Glass, OVERHEAD)
		glass.Transparency = 0.72
		glass.Reflectance = 0.12
		for k = -2, 2 do
			bx(model, "DrumMullion", f, k * 7 - 0.3, k * 7 + 0.3, H + 5, DRUM_TOP - 2, -0.5, 0.5, STEEL, M.Metal, OVERHEAD)
		end
		bx(model, "DrumCap", f, -half, half, DRUM_TOP - 2, DRUM_TOP, -0.9, 0.9, STEEL, M.Metal, OVERHEAD)
		-- Glass roof: eight panes sloping nowhere, with a ring of ribs under them
		local pane = slab(model, "RoofGlass", side, 0, DRUM_R, DRUM_TOP, DRUM_TOP + 0.5, rgb(200, 220, 230), M.Glass, OVERHEAD)
		pane.Transparency = 0.7
		pane.Reflectance = 0.15
		bx(model, "RoofRib", frameAt(side * 45 + 22.5, 0), -0.5, 0.5, DRUM_TOP - 1.5, DRUM_TOP, 0, DRUM_R + 2, STEEL, M.Metal, OVERHEAD)
		bx(model, "RoofRib", frameAt(side * 45, 0), -0.4, 0.4, DRUM_TOP - 1, DRUM_TOP, 0, DRUM_R, STEEL, M.Metal, OVERHEAD)
	end
	ring(model, "RoofRing", 22, 23.2, DRUM_TOP - 1.6, DRUM_TOP, STEEL, M.Metal, OVERHEAD)
	-- Daylight: one warm shadowed key from under the glass, cool fill from the Lantern side
	lamp(model, Vector3.new(0, DRUM_TOP - 6, 0), WARM, 120, 1.1, true)
	lamp(model, Vector3.new(0, 30, 0), COOL, 90, 0.5, false)
	model.Parent = folder
end

-- The Lantern ---------------------------------------------------------------------------------------

local function buildLantern(folder: Instance)
	local model = Instance.new("Model")
	model.Name = "Lantern"
	local function post(a: Vector3, b: Vector3, width: number)
		local look = (b - a)
		local mid = (a + b) / 2
		local forward = look.Unit
		local up = if math.abs(forward.Y) > 0.99 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
		local right = forward:Cross(up).Unit
		make(model, { Name = "Arm", Size = Vector3.new(width, width, look.Magnitude), CFrame = CFrame.fromMatrix(mid, right, right:Cross(forward), -forward), Color = COPPER, Material = M.Metal, CastShadow = false })
	end
	-- Containment: four bronze arms from the dais hold a ring round the crystal
	for index = 0, 3 do
		local angle = math.rad(45 + index * 90)
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local foot = out * 8 + Vector3.new(0, 3.06, 0)
		local knee = out * 7.6 + Vector3.new(0, 11.5, 0)
		local hand = out * 6.4 + Vector3.new(0, CRYSTAL_HEIGHT - 0.4, 0)
		post(foot, knee, 0.9)
		post(knee, hand, 0.8)
	end
	for index = 1, 16 do
		local a, b = (index - 1) / 16 * math.pi * 2, index / 16 * math.pi * 2
		post(Vector3.new(math.cos(a) * 6.4, CRYSTAL_HEIGHT - 0.4, math.sin(a) * 6.4), Vector3.new(math.cos(b) * 6.4, CRYSTAL_HEIGHT - 0.4, math.sin(b) * 6.4), 0.9)
	end
	-- The crystal: a glassy bipyramid with a bright heart (WorldFxController floats and turns it)
	local home = CFrame.new(0, CRYSTAL_HEIGHT, 0) * CFrame.Angles(0, math.rad(45), math.rad(4))
	local glass = { CanCollide = false, CastShadow = false, Transparency = 0.18, Reflectance = 0.12 }
	local crystalColor = rgb(206, 224, 236)
	local pieces = {}
	local crystal = make(model, { Name = "NexusCrystal", Size = Vector3.new(3.2, 6.0, 3.2), CFrame = home, Color = crystalColor, Material = M.Glass, CanCollide = false, CastShadow = false, Transparency = 0.18, Reflectance = 0.12 })
	table.insert(pieces, crystal)
	for _, y in { 1, -1 } do
		local flip = if y > 0 then CFrame.new() else CFrame.Angles(0, 0, math.pi)
		for _, z in { -0.8, 0.8 } do
			local turn = if z > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new()
			local tip = Instance.new("WedgePart")
			tip.Name = "CrystalTip"
			tip.Anchored = true
			tip.Color = crystalColor
			tip.Material = M.Glass
			for key, value in glass do
				(tip :: any)[key] = value
			end
			tip.Size = Vector3.new(3.2, 2.6, 1.6)
			tip.CFrame = home * CFrame.new(0, y * 4.3, z) * turn * flip
			tip.Parent = model
			table.insert(pieces, tip)
		end
	end
	local core = make(model, { Name = "NexusCore", Size = Vector3.new(1.3, 5.2, 1.3), CFrame = home, Color = rgb(221, 235, 255), Material = M.Neon, CanCollide = false, CastShadow = false, Transparency = 0.08 })
	table.insert(pieces, core)
	for _, piece in pieces do
		piece:SetAttribute("Crystal", true)
	end
	local point = Instance.new("PointLight")
	point.Color = rgb(208, 226, 255)
	point.Range = 44
	point.Brightness = 2.2
	point.Shadows = true
	point.Parent = core
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(rgb(226, 238, 255))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.26), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new(0.25, 1)
	sparks.Lifetime = NumberRange.new(3, 5)
	sparks.Speed = NumberRange.new(0.3, 0.8)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 3
	sparks.Parent = core
	model.Parent = folder
end

-- Statues ------------------------------------------------------------------------------------------------

local statuesModule = script.Parent:FindFirstChild("Statues")

local function fallbackPlinth(id: string, base: CFrame): Model
	local model = Instance.new("Model")
	bx(model, "Plinth", base, -5, 5, 0, 9, -5, 5, TILE_DARK, M.Slate)
	bx(model, "Band", base, -5.2, 5.2, 4, 5, -5.2, 5.2, STEEL, M.Metal)
	return model
end

local function buildStatues(folder: Instance)
	local Statues = nil
	if statuesModule then
		local ok, result = pcall(require, statuesModule)
		if ok then
			Statues = result
		else
			warn("[World] Statues didn't load: " .. tostring(result))
		end
	end
	for index, id in Powers.Order do
		-- The floor point under the plinth, facing the Lantern
		local base = frameAt(22.5 + (index - 1) * 45, STATUE_R)
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
			statue = fallbackPlinth(id, base)
		end
		statue.Name = "Statue_" .. id
		statue.Parent = folder
	end
end

-- Portals ------------------------------------------------------------------------------------------------

local function buildPortal(folder: Instance, entry)
	local model = Instance.new("Model")
	model.Name = "Portal_" .. entry.id
	local f = frameAt(entry.angle, R)
	local color: Color3 = entry.color
	-- Lit frame: neon strips up the jambs and along the lintel, a threshold strip on the floor
	for _, x in { -7.5, 7.2 } do
		local strip = bx(model, "FrameLight", f, x, x + 0.3, 0.2, 22.8, -1.7, -1.3, color, M.Neon, GHOST)
		strip.Transparency = 0.1
	end
	local top = bx(model, "FrameLight", f, -7.5, 7.5, 22.5, 22.8, -1.7, -1.3, color, M.Neon, GHOST)
	top.Transparency = 0.1
	local threshold = bx(model, "Threshold", f, -7.5, 7.5, 0, 0.1, -1.6, 0.4, color, M.Neon, GHOST)
	threshold.Transparency = 0.3
	bx(model, "ThresholdPlate", f, -8.2, 8.2, 0, 0.07, -2.4, -1.6, STEEL, M.Metal, GHOST)

	-- The doorway itself: tinted glass over a dark panel, so it reads as a lit screen
	local back = bx(model, "PortalSurface", f, -7.2, 7.2, 0.2, 22.5, WALL - 3.4, WALL - 3.3, color:Lerp(NAVY, 0.7), M.Glass, { CanCollide = false, CastShadow = false, Transparency = 0.25, Reflectance = 0.05 })
	prompt(back, entry.prompt, entry.name, entry.action, 14)
	lamp(model, polar(entry.angle, R + 3, 14), COOL, 20, 0.7, false)

	-- Sign: dark plate above the lintel with the wayfinding mark, the room name and a subtitle
	local plate = bx(model, "Sign", f, -15, 15, 26, 36, -1.8, -0.4, NAVY, M.SmoothPlastic, SMALL)
	local gui = surface(plate, Enum.NormalId.Front, 24)
	swatch(gui, { 0.03, 0.12, 0.016, 0.76 }, color)
	swatch(gui, { 0.05, 0.9, 0.92, 0.012 }, color)
	label(gui, entry.name, { 0.08, 0.1, 0.9, 0.5 }, TEXT, FONT_DISPLAY, 48)
	label(gui, entry.subtitle, { 0.08, 0.58, 0.9, 0.28 }, MUTED, FONT_SANS, 30)
	bx(model, "SignFrame", f, -15.4, 15.4, 25.7, 26, -1.9, -0.3, STEEL, M.Metal, GHOST)
	bx(model, "SignFrame", f, -15.4, 15.4, 36, 36.3, -1.9, -0.3, STEEL, M.Metal, GHOST)

	if entry.id == "Calibration" then
		-- The fighter showcase: the client's Powers window frames its preview from this camera
		local cam = Instance.new("CFrameValue")
		cam.Name = "PreviewCamera"
		local eye = polar(entry.angle, R - 10, 14)
		local target = Vector3.new(0, 16, 0)
		local look = (target - eye).Unit
		local right = look:Cross(Vector3.new(0, 1, 0)).Unit
		cam.Value = CFrame.fromMatrix(eye, right, right:Cross(look), -look)
		cam.Parent = model
	end
	model.Parent = folder
end

-- Archive stand: a lectern with a lit book, reachable between the spawn and the dais
local function buildArchive(folder: Instance, entry)
	local model = Instance.new("Model")
	model.Name = "ArchiveStand"
	local f = frameAt(entry.angle, 24)
	bx(model, "StandFoot", f, -1.6, 1.6, 0, 0.5, -1.6, 1.6, GRAPHITE, M.Metal)
	bx(model, "StandPost", f, -0.5, 0.5, 0.5, 3.4, -0.5, 0.5, STEEL, M.Metal)
	local top = bx(model, "StandTop", f * CFrame.new(0, 3.7, 0) * CFrame.Angles(math.rad(25), 0, 0), -2, 2, -0.2, 0.2, -1.4, 1.4, COPPER, M.Metal)
	local book = bx(model, "Book", f * CFrame.new(0, 3.85, 0) * CFrame.Angles(math.rad(25), 0, 0), -1.5, 1.5, 0, 0.3, -1.1, 1.1, rgb(112, 74, 48), M.Fabric, SMALL)
	local gui = surface(book, Enum.NormalId.Top, 50)
	label(gui, "THE MERIDIAN ARCHIVE", { 0.1, 0.35, 0.8, 0.3 }, rgb(232, 210, 168), FONT_DISPLAY, 30, Enum.TextXAlignment.Center)
	prompt(top, entry.prompt, "The Meridian Archive", entry.action, 10)
	lamp(model, polar(entry.angle, 24, 7), WARM, 14, 0.8, false)
	model.Parent = folder
end

-- Guides: ordered waypoints from the spawn to each portal, round the plaza edge ---------------------------

local SPAWN_ANGLE, SPAWN_R = 90, 66

local function buildGuides(folder: Instance)
	local guides = Instance.new("Folder")
	guides.Name = "Guides"
	for _, entry in Hub.Gates do
		if entry.id ~= "Entrance" then
			local list = Instance.new("Folder")
			list.Name = entry.id
			list:SetAttribute("Label", entry.name)
			local points = {}
			if entry.stand then
				table.insert(points, entry.position + entry.facing * -3)
			else
				-- Walk the gallery circle (clear of the statues) to the portal's angle, then straight in
				local delta = ((entry.angle - SPAWN_ANGLE + 180) % 360) - 180
				local steps = math.max(1, math.ceil(math.abs(delta) / 30))
				for step = 1, steps do
					table.insert(points, polar(SPAWN_ANGLE + delta * step / steps, 62, 0))
				end
				table.insert(points, polar(entry.angle, 72, 0))
				table.insert(points, entry.position)
			end
			for index, at in points do
				make(list, { Name = tostring(index), Size = Vector3.new(2, 0.2, 2), CFrame = CFrame.new(at.X, 0.2, at.Z), Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
			end
			list.Parent = guides
		end
	end
	guides.Parent = folder
end

-- Recovered files ------------------------------------------------------------------------------------------
-- The Meridian Archive's ten hidden files (Content/Archive.Files), each placed where its hint
-- points. A file is a small data slate tagged SNLoreTerminal with a LoreId attribute
-- (LoreService checks the player is within reach) and a prompt whose Action "Lore:<id>" the
-- client sends as ProgressAction.FindLore. Two details exist for the hints: scorched panels by
-- the Test Chambers and Door 09, the sealed door on the Training Studio wall.

local CollectionService = game:GetService("CollectionService")

local function slate(folder: Instance, id: string, f: CFrame)
	local model = Instance.new("Model")
	model.Name = "RecoveredFile_" .. id
	local body = bx(model, "Slate", f, -0.6, 0.6, 0, 0.12, -0.45, 0.45, GRAPHITE, M.Metal, SMALL)
	bx(model, "Screen", f, -0.5, 0.5, 0.12, 0.15, -0.35, 0.3, rgb(18, 34, 44), M.Glass, SMALL)
	bx(model, "Status", f, -0.5, -0.32, 0.15, 0.17, 0.32, 0.38, CYAN, M.Neon, SMALL)
	-- A faint glow so a curious player can spot it; never a beacon
	local glow = Instance.new("PointLight")
	glow.Color = CYAN
	glow.Range = 5
	glow.Brightness = 0.35
	glow.Shadows = false
	glow.Parent = body
	CollectionService:AddTag(body, "SNLoreTerminal")
	body:SetAttribute("LoreId", id)
	local proximity = prompt(body, "Read", "Recovered file", "Lore:" .. id, 8)
	proximity.Name = "LorePrompt"
	model.Parent = folder
end

local function statueAngle(powerId: string): number
	for index, id in Powers.Order do
		if id == powerId then
			return 22.5 + (index - 1) * 45
		end
	end
	return 112.5
end

local function buildLoreFiles(folder: Instance)
	local files = Instance.new("Folder")
	files.Name = "RecoveredFiles"
	local function at(angle: number, r: number, turn: number?): CFrame
		return frameAt(angle, r) * CFrame.Angles(0, math.rad(turn or 0), 0)
	end
	local wolf = statueAngle("Shapeshifter")
	slate(files, "ajkr_first_entry", at(98, 19, 20)) -- near the Lantern, where every visitor stops first
	slate(files, "lantern_field_note", at(wolf + 180, STATUE_R + 7, -15)) -- behind a statue, under the glass roof
	slate(files, "procurement_memo", at(144, R - 6, 10)) -- beside the Master Shop door, where supplies came in
	slate(files, "garden_irrigation", at(81, R - 6, -10)) -- beside the way you came in
	slate(files, "night_shift_07", at(54, R - 6, 5)) -- beside the Spectating Lounge door
	slate(files, "badge_okafor", at(wolf, STATUE_R + 7, 30)) -- behind the wolf
	slate(files, "varga_tape_12", at(61.5, 22, 0)) -- by the Archive book
	slate(files, "warden_boot", at(-126, R - 6, -5)) -- beside the door to Jeffery's Base
	slate(files, "eclipse_cleanup", at(-9, R - 6, 15)) -- by the Test Chambers, under the scorched panels
	-- Scorched panels on the Test Chambers wall, left of the door
	local wall = frameAt(0, R)
	for _, x in { -18, -13 } do
		bx(files, "ScorchedPanel", wall, x - 2.2, x + 2.2, 3, 14, -1.1, -0.35, rgb(30, 26, 24), M.Slate, SMALL)
		bx(files, "ScorchMark", wall, x - 1.4, x + 1.1, 6, 11, -1.18, -1.1, rgb(16, 13, 12), M.Slate, SMALL)
	end
	-- Door 09: a sealed steel door on the Training Studio wall, its status light dark red
	local door = frameAt(180, R) * CFrame.new(24, 0, 0)
	bx(files, "Door09Frame", door, -3.6, 3.6, 0, 10.6, -1.2, -0.3, STEEL, M.Metal, SMALL)
	local leaf = bx(files, "Door09Leaf", door, -3, 3, 0, 10, -1.35, -1.2, GRAPHITE, M.DiamondPlate, SMALL)
	bx(files, "Door09Lamp", door, -0.4, 0.4, 10.9, 11.3, -1.3, -1.2, rgb(150, 30, 30), M.Neon, SMALL)
	local plate = surface(leaf, Enum.NormalId.Front, 30)
	label(plate, "09", { 0.25, 0.08, 0.5, 0.14 }, rgb(205, 196, 180), FONT_DISPLAY, 60, Enum.TextXAlignment.Center)
	slate(files, "door_09_note", door * CFrame.new(0, 0, -3) * CFrame.Angles(0, math.rad(8), 0)) -- at the foot of the door that never opens
	files.Parent = folder
end

-- Builds the whole hub into `folder`. Returns the spawn location.
function Hub.build(folder: Instance): SpawnLocation
	buildFloor(folder)
	buildWalls(folder)
	buildCeiling(folder)
	buildLantern(folder)
	buildStatues(folder)
	for _, entry in Hub.Gates do
		if entry.stand then
			buildArchive(folder, entry)
		else
			buildPortal(folder, entry)
		end
	end
	buildGuides(folder)
	buildLoreFiles(folder)
	require(script.Parent.Jeffery).build(folder)

	-- Spawn on the plaza south of the dais, facing the Lantern, the entrance behind
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "NexusSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.2, 6)
	spawn.CFrame = CFrame.new(0, 0.3, SPAWN_R)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = folder
	return spawn
end

return Hub
