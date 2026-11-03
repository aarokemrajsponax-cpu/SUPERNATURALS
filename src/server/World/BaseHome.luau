-- PERSONAL BASE: a second home (MASTER_REQUIREMENTS 6 and P.S. 19.0 point 4; DECISIONS.md 8, 9;
-- ArtDirection sections 2, 3, 6). One is built per player present, far off-map (Homes.BaseOrigin
-- plus slot * SlotSpacing), by BaseService, and destroyed when the player leaves.
--
-- HOME (48 x 36 studs inside, 14 high; origin = middle of the floor; +Z is the entrance side)
--   north  window wall: a 36 x 9 glazed opening onto a lit alcove with a holographic skyline
--   centre living area: sofa, rug, glass coffee table, two floor lamps, side tables and a lamp
--   west   quiet corner: bookshelf, armchair, round rug, reading lamp, plant, a framed note
--   east   display wall: RECORD board (wins, matches, streak, title), MASTERY board (a bar per
--          fighter), COLLECTION board (titles, cosmetics, premium fighters), and under it a low
--          cabinet with four control pads (decor theme and three display toggles)
--   south  entrance door (back to the street) and the low-key luxury lift (bronze doors) down
--   ceiling warm coves, light panels, three timber beams; warm and dim, per ArtDirection 6
-- Themes recolour the same parts by role (Config/Homes.Themes), nothing is rebuilt.
--
-- VAULT (below the home by Homes.VaultDrop; 48 x 36, 12 high), reached only by the owner's lift
--   west wall   trophy cases: win milestone trophies (lit once earned) and the titles board
--   east wall   cosmetics tiles (one per owned cosmetic) and a RESERVED wall section (see below)
--   centre      eight mastery pedestals, one per fighter: orb size and glow follow the level
--   north wall  premium fighter alcoves: a figure for each premium fighter the player owns
--   south-west  the secret Archive alcove behind a sealed panel; it opens only when LoreService
--               counts every Archive file (BaseHome.setAlcove). Closed it is a plain wall.
--   north-east  AJKR's command console, built ONLY in the owner's base (BaseService passes
--               ownerBase after OwnerService:isOwner). Its prompt asks BaseService, which
--               re-checks isOwner on the server and only then tells the client to open the
--               existing owner panel; the panel's own server checks stay the authority.
--
-- MEME VAULT SPOT (for a later agent): the east wall at z +8 .. +16 is a plain, reserved wall
-- section 8 wide and 9 high, with a conduit run above it for a future door. An Attachment named
-- "MemeVaultDoorAnchor" in the model "Reserved" marks the door's centre on the floor and faces
-- into the vault (attribute Purpose documents it). There is deliberately NO door, button or
-- prompt there yet: add the archive door at the anchor, in the lift's style.
--
-- Updates are events (a profile change calls render; a theme or toggle press recolours). Only
-- changed text is written, and the vault's dynamic folder is rebuilt only when its signature
-- changes. No per-frame code.
-- Part budgets: Homes.HomePartBudget (430), Homes.VaultPartBudget (330); about 280 and 260 in
-- practice, plus up to about 60 dynamic parts in the vault.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.Parent.Arenas.Common)
local BaseStreet = require(script.Parent.BaseStreet)
local Homes = require(ReplicatedStorage.Shared.Config.Homes)

local BaseHome = {}

BaseHome.HomePartBudget = Homes.HomePartBudget
BaseHome.VaultPartBudget = Homes.VaultPartBudget

local M = Common.M
local rgb = Common.rgb
local DECOR = Common.GHOST

local STEEL = rgb(150, 156, 164)
local BRONZE = rgb(184, 115, 63)
local DARK = rgb(26, 28, 34)
local SCREEN = rgb(14, 22, 36)
local TEXT = rgb(232, 238, 244)
local AMBER = rgb(232, 162, 74)
local GOLD = rgb(236, 196, 92)
local FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local FONT_REG = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium)

export type Built = {
	model: Model,
	home: Model,
	vault: Model,
	entry: CFrame,
	vaultEntry: CFrame,
	prompts: { [string]: ProximityPrompt },
	alcovePanel: BasePart,
	console: BasePart?,
	applyTheme: (themeId: string) -> (),
	render: (view: any) -> (),
	setAlcove: (open: boolean, found: number, total: number) -> (),
	setPad: (key: string, text: string) -> (),
}

-- Text -------------------------------------------------------------------------------------------

local function gui(part: BasePart, face: Enum.NormalId, pixelsPerStud: number): SurfaceGui
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Board"
	surface.Face = face
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = pixelsPerStud
	surface.LightInfluence = 0
	surface.Parent = part
	return surface
end

local function label(parent: Instance, text: string, x: number, y: number, w: number, h: number, size: number, color: Color3, align: Enum.TextXAlignment?, bold: boolean?): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Position = UDim2.fromScale(x, y)
	item.Size = UDim2.fromScale(w, h)
	item.Text = text
	item.TextSize = size
	item.TextColor3 = color
	item.FontFace = if bold == false then FONT_REG else FONT
	item.TextXAlignment = align or Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.Parent = parent
	return item
end

local function setText(item: TextLabel, text: string)
	if item.Text ~= text then
		item.Text = text
	end
end

local function bar(parent: Instance, x: number, y: number, w: number, h: number, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(w, h)
	frame.Parent = parent
	return frame
end

-- Build ------------------------------------------------------------------------------------------

function BaseHome.build(parent: Instance, origin: Vector3, owner: { name: string, userId: number, slot: number }, ownerBase: boolean): Built
	local root = Instance.new("Model")
	root.Name = "Base_" .. owner.slot
	root:SetAttribute("OwnerUserId", owner.userId)
	root:SetAttribute("Slot", owner.slot)
	local home = Instance.new("Model")
	home.Name = "Home"
	home.Parent = root
	local vault = Instance.new("Model")
	vault.Name = "Vault"
	vault.Parent = root

	local prompts: { [string]: ProximityPrompt } = {}
	local roles: { [string]: { BasePart } } = {}
	local lamps: { Light } = {}
	local pads: { [string]: TextLabel } = {}

	local function piece(group: Instance, frame: CFrame)
		return function(name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: Color3, material: Enum.Material, extra: { [string]: any }?, roleName: string?): BasePart
			local part = Common.block(group, name, Vector3.new(sx, sy, sz), frame * CFrame.new(x, y, z), color, material, extra)
			if roleName then
				roles[roleName] = roles[roleName] or {}
				table.insert(roles[roleName], part)
			end
			return part
		end
	end
	local function round(group: Instance, frame: CFrame)
		return function(name: string, height: number, diameter: number, x: number, y: number, z: number, color: Color3, material: Enum.Material, extra: { [string]: any }?, roleName: string?): BasePart
			local part = Common.cylinder(group, name, frame * CFrame.new(x, y, z), height, diameter, color, material, extra)
			if roleName then
				roles[roleName] = roles[roleName] or {}
				table.insert(roles[roleName], part)
			end
			return part
		end
	end
	local function lamp(parentPart: BasePart, range: number, brightness: number)
		local light = Common.light(parentPart, rgb(255, 196, 120), range, brightness, false)
		table.insert(lamps, light)
		return light
	end
	local function prompt(key: string, parentPart: BasePart, action: string, object: string, distance: number?)
		local item = BaseStreet.prompt(parentPart, action, object, distance or 10)
		item.Name = key
		prompts[key] = item
		return item
	end

	-- ============================== HOME ==============================
	local H = CFrame.new(origin)
	local put, cyl = piece(home, H), round(home, H)
	local DECOR_ = DECOR

	put("Floor", 52, 2, 40, 0, -1, 0, rgb(96, 62, 38), M.WoodPlanks, nil, "floor")
	put("Ceiling", 52, 1.5, 40, 0, 14.75, 0, rgb(222, 218, 208), M.SmoothPlastic)
	-- Walls: north has the window opening
	put("WallSouth", 52, 14, 2, 0, 7, 19, rgb(214, 204, 188), M.SmoothPlastic, nil, "wall")
	put("WallWest", 2, 14, 40, -25, 7, 0, rgb(214, 204, 188), M.SmoothPlastic, nil, "wall")
	put("DisplayWall", 2, 14, 40, 25, 7, 0, rgb(70, 46, 30), M.Wood, nil, "panel")
	put("WallNorthL", 8, 14, 2, -22, 7, -19, rgb(214, 204, 188), M.SmoothPlastic, nil, "wall")
	put("WallNorthR", 8, 14, 2, 22, 7, -19, rgb(214, 204, 188), M.SmoothPlastic, nil, "wall")
	put("WallNorthLow", 36, 2.2, 2, 0, 1.1, -19, rgb(70, 46, 30), M.Wood, nil, "panel")
	put("WallNorthHigh", 36, 3, 2, 0, 12.5, -19, rgb(214, 204, 188), M.SmoothPlastic, nil, "wall")
	-- Trim: skirting and crown on every wall, in the theme's metal
	for _, z in { -17.6, 17.6 } do
		put("Skirting", 48, 0.5, 0.4, 0, 0.25, z, BRONZE, M.Metal, DECOR_, "trim")
		put("Crown", 48, 0.4, 0.4, 0, 13.7, z, BRONZE, M.Metal, DECOR_, "trim")
	end
	for _, x in { -23.6, 23.6 } do
		put("Skirting", 0.4, 0.5, 35, x, 0.25, 0, BRONZE, M.Metal, DECOR_, "trim")
		put("Crown", 0.4, 0.4, 35, x, 13.7, 0, BRONZE, M.Metal, DECOR_, "trim")
	end
	-- Ceiling: three timber beams, warm coves, light panels
	for _, x in { -14, 0, 14 } do
		put("Beam", 1.2, 0.9, 36, x, 13.4, 0, rgb(70, 46, 30), M.Wood, nil, "panel")
		local panel = put("LightPanel", 3.4, 0.2, 5, x, 13.85, -2, rgb(255, 232, 196), M.Neon, DECOR_)
		lamp(panel, 34, 0.9)
	end
	for _, z in { -17.4, 17.4 } do
		put("Cove", 44, 0.2, 0.4, 0, 13.3, z, AMBER, M.Neon, DECOR_)
	end

	-- Window wall: glass, mullions, sill, and the lit alcove with the holographic skyline
	put("Glass", 36, 8.8, 0.2, 0, 6.6, -19, rgb(170, 200, 220), M.Glass, { Transparency = 0.7, Reflectance = 0.15, CanCollide = true })
	for i = 0, 6 do
		put("Mullion", 0.3, 8.8, 0.4, -18 + i * 6, 6.6, -18.9, STEEL, M.Metal, DECOR_)
	end
	put("Sill", 37, 0.3, 1.4, 0, 2.3, -18.3, BRONZE, M.Metal, DECOR_, "trim")
	put("AlcoveBack", 52, 16, 1, 0, 7, -31, SCREEN, M.SmoothPlastic)
	put("AlcoveFloor", 40, 1, 12, 0, 0.5, -25, rgb(18, 24, 34), M.SmoothPlastic)
	put("AlcoveRoof", 40, 1, 12, 0, 13.5, -25, rgb(18, 24, 34), M.SmoothPlastic)
	for _, x in { -20.5, 20.5 } do
		put("AlcoveSide", 1, 14, 12, x, 7, -25, rgb(18, 24, 34), M.SmoothPlastic)
	end
	put("Horizon", 40, 0.3, 0.3, 0, 1.2, -30.4, AMBER, M.Neon, DECOR_)
	local random = Random.new(owner.slot * 17 + 3)
	for i = 0, 10 do
		local height = 5 + random:NextInteger(0, 7)
		put("SkylineFar", 3.6, height, 0.6, -18 + i * 3.6, 1 + height / 2, -30, rgb(40, 70, 110), M.Neon, { Transparency = 0.6, CanCollide = false, CanQuery = false, CastShadow = false })
	end
	for i = 0, 8 do
		local height = 3 + random:NextInteger(0, 5)
		local accent = i == 2 or i == 6
		put("SkylineNear", 3, height, 0.8, -16 + i * 4, 1 + height / 2, -26, if accent then rgb(63, 214, 232) else rgb(150, 176, 208), M.Neon, { Transparency = if accent then 0.35 else 0.55, CanCollide = false, CanQuery = false, CastShadow = false })
	end
	local glow = put("SkylineGlow", 4, 0.4, 4, 0, 13, -24, rgb(150, 176, 208), M.Neon, DECOR_)
	Common.light(glow, rgb(150, 190, 230), 40, 0.8, false)

	-- Living area
	put("Rug", 17, 0.12, 11, 0, 0.06, 1.5, rgb(46, 52, 62), M.Fabric, DECOR_, "rug")
	put("RugEdge", 17, 0.14, 0.4, 0, 0.07, -3.6, AMBER, M.Fabric, DECOR_, "rugBorder")
	put("RugEdge", 17, 0.14, 0.4, 0, 0.07, 6.6, AMBER, M.Fabric, DECOR_, "rugBorder")
	put("RugEdge", 0.4, 0.14, 11, -8.3, 0.07, 1.5, AMBER, M.Fabric, DECOR_, "rugBorder")
	put("RugEdge", 0.4, 0.14, 11, 8.3, 0.07, 1.5, AMBER, M.Fabric, DECOR_, "rugBorder")
	local sofa = piece(home, H * CFrame.new(0, 0, 6))
	for _, x in { -5, 5 } do
		for _, z in { -1.4, 1.4 } do
			sofa("Leg", 0.5, 0.6, 0.5, x, 0.3, z, STEEL, M.Metal, DECOR_)
		end
	end
	sofa("SofaBase", 11, 0.9, 3.8, 0, 1.05, 0, rgb(150, 82, 44), M.Fabric, nil, "sofa")
	for i = -1, 1 do
		sofa("SeatCushion", 3.2, 0.8, 3.0, i * 3.3, 1.9, -0.3, rgb(160, 90, 50), M.Fabric, nil, "sofa")
		sofa("BackCushion", 3.2, 1.9, 0.8, i * 3.3, 2.9, 1.3, rgb(160, 90, 50), M.Fabric, nil, "sofa")
	end
	sofa("SofaBack", 11, 2.8, 0.8, 0, 2.5, 1.7, rgb(140, 76, 42), M.Fabric, nil, "sofa")
	for _, x in { -5.4, 5.4 } do
		sofa("SofaArm", 0.9, 2.0, 3.8, x, 1.9, 0, rgb(140, 76, 42), M.Fabric, nil, "sofa")
	end
	-- Coffee table: glass top on a bronze frame, with a warm light orb
	local table_ = piece(home, H * CFrame.new(0, 0, 0))
	table_("TableTop", 5.4, 0.3, 2.8, 0, 1.55, 0, rgb(180, 210, 220), M.Glass, { Transparency = 0.45, Reflectance = 0.1 })
	table_("TableShelf", 4.8, 0.2, 2.2, 0, 0.5, 0, rgb(70, 46, 30), M.Wood, nil, "panel")
	for _, x in { -2.5, 2.5 } do
		for _, z in { -1.2, 1.2 } do
			table_("TableLeg", 0.3, 1.5, 0.3, x, 0.75, z, BRONZE, M.Metal, DECOR_, "trim")
		end
	end
	local orb = Common.ball(home, "TableOrb", origin + Vector3.new(0, 2.3, 0), 0.8, AMBER, M.Neon, DECOR_)
	Common.light(orb, rgb(255, 190, 110), 10, 0.5, false)
	-- Floor lamps and side tables
	for _, x in { -9.5, 9.5 } do
		cyl("LampBase", 0.3, 1.6, x, 0.15, 3, STEEL, M.Metal, DECOR_)
		cyl("LampPole", 5.5, 0.25, x, 3, 3, BRONZE, M.Metal, DECOR_, "trim")
		local shade = cyl("LampShade", 1.6, 2, x, 6.2, 3, rgb(255, 196, 120), M.Neon, { Transparency = 0.15, CastShadow = false })
		lamp(shade, 24, 1.3)
	end
	for _, x in { -8, 8 } do
		cyl("SideTop", 0.2, 2.4, x, 2.3, 8.6, rgb(70, 46, 30), M.Wood, nil, "panel")
		cyl("SideStem", 2.2, 0.3, x, 1.1, 8.6, BRONZE, M.Metal, DECOR_, "trim")
		cyl("SideBase", 0.2, 1.6, x, 0.1, 8.6, BRONZE, M.Metal, DECOR_, "trim")
	end
	local small = cyl("TableLampShade", 1.1, 1.2, -8, 3.2, 8.6, rgb(255, 196, 120), M.Neon, { Transparency = 0.2, CastShadow = false })
	lamp(small, 14, 0.8)
	cyl("TableLampStem", 0.8, 0.2, -8, 2.7, 8.6, BRONZE, M.Metal, DECOR_)

	-- Quiet corner: bookshelf, armchair, round rug, reading lamp, plant, a framed note
	local shelf = piece(home, H * CFrame.new(-24, 0, -8))
	shelf("ShelfBack", 0.3, 9, 10, -0.6, 4.5, 0, rgb(70, 46, 30), M.Wood, nil, "panel")
	for _, z in { -5, 5 } do
		shelf("ShelfSide", 1.4, 9, 0.4, 0, 4.5, z, rgb(96, 62, 38), M.Wood, nil, "panel")
	end
	for i = 0, 4 do
		shelf("Shelf", 1.4, 0.3, 10, 0, 0.2 + i * 2.2, 0, rgb(96, 62, 38), M.Wood, nil, "panel")
	end
	local bookColors = { rgb(120, 40, 36), rgb(36, 60, 100), rgb(70, 110, 76), rgb(200, 170, 110), rgb(60, 54, 70), rgb(160, 96, 48) }
	for level = 0, 3 do
		local z = -4.4
		for _ = 1, 6 do
			local width = 0.5 + random:NextNumber() * 0.5
			local height = 1.3 + random:NextNumber() * 0.5
			shelf("Book", 0.9, height, width, 0.1, 0.35 + level * 2.2 + height / 2, z + width / 2, bookColors[random:NextInteger(1, #bookColors)], M.SmoothPlastic, DECOR_)
			z += width + 0.15
		end
	end
	local chair = piece(home, H * CFrame.new(-16, 0, -2) * CFrame.Angles(0, math.rad(90), 0))
	chair("ChairBase", 3.4, 1, 3.2, 0, 1, 0, rgb(150, 82, 44), M.Fabric, nil, "sofa")
	chair("ChairCushion", 2.8, 0.7, 2.6, 0, 1.75, 0.1, rgb(160, 90, 50), M.Fabric, nil, "sofa")
	chair("ChairBack", 3.4, 2.8, 0.8, 0, 2.7, 1.2, rgb(140, 76, 42), M.Fabric, nil, "sofa")
	for _, x in { -1.45, 1.45 } do
		chair("ChairArm", 0.6, 1.7, 3.2, x, 1.9, 0, rgb(140, 76, 42), M.Fabric, nil, "sofa")
	end
	for _, x in { -1.4, 1.4 } do
		for _, z in { -1.3, 1.3 } do
			chair("ChairLeg", 0.4, 0.5, 0.4, x, 0.25, z, STEEL, M.Metal, DECOR_)
		end
	end
	cyl("RoundRug", 0.12, 7, -16, 0.06, -2, rgb(46, 52, 62), M.Fabric, DECOR_, "rug")
	cyl("RoundRugEdge", 0.14, 7.6, -16, 0.04, -2, AMBER, M.Fabric, DECOR_, "rugBorder")
	cyl("ReadBase", 0.3, 1.4, -13.5, 0.15, -5, STEEL, M.Metal, DECOR_)
	cyl("ReadPole", 5, 0.2, -13.5, 2.8, -5, BRONZE, M.Metal, DECOR_, "trim")
	local reading = cyl("ReadShade", 1.2, 1.6, -13.5, 5.8, -5, rgb(255, 196, 120), M.Neon, { Transparency = 0.15, CastShadow = false })
	lamp(reading, 18, 1)
	for _, spot in { Vector3.new(-21, 0, -16), Vector3.new(21, 0, -16) } do
		cyl("Pot", 1.8, 2.2, spot.X, 0.9, spot.Z, rgb(35, 39, 46), M.Metal)
		Common.ball(home, "Leaves", origin + spot + Vector3.new(0, 3.2, 0), 3.2, rgb(70, 124, 72), M.Grass, DECOR_)
		Common.ball(home, "Leaves", origin + spot + Vector3.new(0.6, 4.4, 0.4), 2.2, rgb(88, 146, 86), M.Grass, DECOR_)
		Common.ball(home, "Leaves", origin + spot + Vector3.new(-0.7, 4.0, -0.5), 2, rgb(60, 112, 66), M.Grass, DECOR_)
	end
	put("NoteFrame", 0.3, 4.4, 6.4, -24.2, 7, 8, BRONZE, M.Metal, DECOR_, "trim")
	local noteScreen = put("NoteScreen", 0.2, 3.8, 5.8, -24.05, 7, 8, SCREEN, M.SmoothPlastic, DECOR_)
	local noteGui = gui(noteScreen, Enum.NormalId.Right, 40)
	label(noteGui, "Take a breath.", 0.05, 0.1, 0.9, 0.8, 26, rgb(242, 230, 208), Enum.TextXAlignment.Center)

	-- Display wall (east): three boards, a cabinet, control pads
	local function board(name: string, w: number, h: number, z: number, y: number): (BasePart, SurfaceGui)
		put(name .. "Frame", 0.5, h + 0.8, w + 0.8, 23.4, y, z, BRONZE, M.Metal, DECOR_, "trim")
		local screen = Common.block(home, name, Vector3.new(w, h, 0.2), CFrame.lookAt(origin + Vector3.new(23.1, y, z), origin + Vector3.new(22, y, z)), SCREEN, M.SmoothPlastic, DECOR_)
		local surface = gui(screen, Enum.NormalId.Front, 50)
		return screen, surface
	end
	local recordScreen, recordGui = board("RecordBoard", 10, 6, -11.5, 7)
	local masteryScreen, masteryGui = board("MasteryBoard", 10, 8, 0, 7.4)
	local collectionScreen, collectionGui = board("CollectionBoard", 10, 6, 11.5, 7)
	local lights = { recordScreen, masteryScreen, collectionScreen }
	for _, screen in lights do
		local spot = Common.surfaceLight(screen, Enum.NormalId.Front, rgb(200, 220, 240), 12, 0.6, 120)
		spot.Name = "ScreenGlow"
	end
	local cabinet = put("Cabinet", 1.6, 3, 36, 23.8, 1.5, 0, rgb(70, 46, 30), M.Wood, nil, "panel")
	put("CabinetTop", 1.8, 0.2, 36.4, 23.7, 3.1, 0, BRONZE, M.Metal, DECOR_, "trim")
	cabinet.Name = "Cabinet"

	-- Record board (static labels, updated text)
	label(recordGui, "RECORD", 0.06, 0.04, 0.88, 0.16, 30, AMBER)
	local recordLines = {}
	for i = 1, 4 do
		recordLines[i] = label(recordGui, "", 0.06, 0.22 + (i - 1) * 0.185, 0.88, 0.17, 26, TEXT, nil, i == 4)
	end
	-- Mastery board: one row per fighter
	local masteryTitle = label(masteryGui, "MASTERY", 0.06, 0.03, 0.88, 0.1, 30, AMBER)
	local masteryRows = {}
	for i = 1, 8 do
		local y = 0.15 + (i - 1) * 0.105
		masteryRows[i] = {
			name = label(masteryGui, "", 0.06, y, 0.5, 0.06, 20, TEXT),
			level = label(masteryGui, "", 0.6, y, 0.34, 0.06, 20, TEXT, Enum.TextXAlignment.Right),
			track = bar(masteryGui, 0.06, y + 0.062, 0.88, 0.016, rgb(40, 48, 62)),
			fill = nil,
		}
		masteryRows[i].fill = bar(masteryRows[i].track, 0, 0, 0, 1, TEXT)
	end
	-- Collection board
	label(collectionGui, "COLLECTION", 0.06, 0.04, 0.88, 0.16, 30, AMBER)
	local collectionLines = {}
	for i = 1, 4 do
		collectionLines[i] = label(collectionGui, "", 0.06, 0.22 + (i - 1) * 0.185, 0.88, 0.17, 24, TEXT, nil, false)
	end
	-- Control pads under the boards
	local padKeys = { { "Theme", -7.5 }, { "Mastery", -2.5 }, { "Cosmetics", 2.5 }, { "Premium", 7.5 } }
	for _, entry in padKeys do
		local pad = Common.block(home, "Pad" .. entry[1], Vector3.new(4.2, 1.4, 0.3), CFrame.lookAt(origin + Vector3.new(22.85, 1.7, entry[2]), origin + Vector3.new(21, 1.7, entry[2])), DARK, M.SmoothPlastic, DECOR_)
		local padGui = gui(pad, Enum.NormalId.Front, 40)
		pads[entry[1]] = label(padGui, "", 0.04, 0.05, 0.92, 0.9, 16, TEXT, Enum.TextXAlignment.Center)
		pads[entry[1]].TextWrapped = true
		prompt("Pad" .. entry[1], pad, "Change", entry[1] == "Theme" and "Decor theme" or entry[1] .. " display", 5)
	end

	-- Entrance door (back to the street) and the lift, both on the south wall
	local door = piece(home, H * CFrame.new(-14, 0, 18))
	door("DoorJambL", 0.6, 9.4, 0.8, -3.1, 4.7, 0, STEEL, M.Metal)
	door("DoorJambR", 0.6, 9.4, 0.8, 3.1, 4.7, 0, STEEL, M.Metal)
	door("DoorLintel", 6.8, 0.6, 0.8, 0, 9.4, 0, STEEL, M.Metal)
	local leaf = door("EntranceDoor", 5.6, 9, 0.5, 0, 4.5, -0.1, rgb(96, 64, 42), M.Wood, nil, "panel")
	door("DoorHandle", 0.25, 1.6, 0.25, 2.1, 4.5, -0.5, BRONZE, M.Metal, DECOR_)
	door("DoorMat", 5, 0.1, 3, 0, 0.05, -2.2, rgb(46, 52, 62), M.Fabric, DECOR_)
	prompt("Exit", leaf, "Back to the street", "Front door", 9)
	local lift = piece(home, H * CFrame.new(14, 0, 18))
	lift("LiftFrameL", 0.8, 9.6, 1, -2.7, 4.8, -0.2, BRONZE, M.Metal)
	lift("LiftFrameR", 0.8, 9.6, 1, 2.7, 4.8, -0.2, BRONZE, M.Metal)
	lift("LiftFrameTop", 6.2, 0.8, 1, 0, 9.6, -0.2, BRONZE, M.Metal)
	local liftLeaf = lift("LiftDoorL", 2.3, 9, 0.4, -1.15, 4.5, -0.2, rgb(138, 104, 70), M.Metal)
	lift("LiftDoorR", 2.3, 9, 0.4, 1.15, 4.5, -0.2, rgb(138, 104, 70), M.Metal)
	local indicator = lift("LiftIndicator", 2.4, 0.9, 0.2, 0, 10.6, -0.5, DARK, M.SmoothPlastic, DECOR_)
	label(gui(indicator, Enum.NormalId.Front, 40), "V  VAULT", 0, 0, 1, 1, 18, AMBER, Enum.TextXAlignment.Center)
	prompt("LiftDown", liftLeaf, "Go down to the Vault", "Lift", 9)
	local entry = CFrame.lookAt(origin + Vector3.new(-14, 3.2, 13.5), origin + Vector3.new(-14, 3.2, 0))

	-- ============================== VAULT ==============================
	local V0 = origin - Vector3.new(0, Homes.VaultDrop, 0)
	local V = CFrame.new(V0)
	local vput, vcyl = piece(vault, V), round(vault, V)
	local CHARCOAL = rgb(58, 62, 72)
	vput("VFloor", 52, 2, 40, 0, -1, 0, rgb(30, 30, 37), M.Basalt)
	vput("VInlay", 3, 0.12, 30, 0, 0.06, 0, STEEL, M.Metal, DECOR_)
	vput("VCeiling", 52, 1.5, 40, 0, 12.75, 0, CHARCOAL, M.Concrete)
	vput("VWallSouth", 52, 12, 2, 0, 6, 19, CHARCOAL, M.Concrete)
	vput("VWallNorth", 52, 12, 2, 0, 6, -19, CHARCOAL, M.Concrete)
	vput("VWallWest", 2, 12, 40, -25, 6, 0, CHARCOAL, M.Concrete)
	vput("VWallEast", 2, 12, 40, 25, 6, 0, CHARCOAL, M.Concrete)
	for _, x in { -16, 0, 16 } do
		vput("VRib", 1.2, 1, 36, x, 11.8, 0, STEEL, M.Metal, DECOR_)
		local panel = vput("VLight", 4, 0.2, 6, x, 12, -4, rgb(255, 224, 180), M.Neon, DECOR_)
		Common.light(panel, rgb(255, 214, 160), 44, 1.8, false)
	end
	vput("VCoveW", 0.3, 0.2, 34, -23.8, 11, 0, AMBER, M.Neon, DECOR_)
	vput("VCoveE", 0.3, 0.2, 34, 23.8, 11, 0, AMBER, M.Neon, DECOR_)

	-- Vault lift (mirrors the home lift)
	local vlift = piece(vault, V * CFrame.new(14, 0, 18))
	vlift("LiftFrameL", 0.8, 9.6, 1, -2.7, 4.8, -0.2, BRONZE, M.Metal)
	vlift("LiftFrameR", 0.8, 9.6, 1, 2.7, 4.8, -0.2, BRONZE, M.Metal)
	vlift("LiftFrameTop", 6.2, 0.8, 1, 0, 9.6, -0.2, BRONZE, M.Metal)
	local vleaf = vlift("LiftDoorL", 2.3, 9, 0.4, -1.15, 4.5, -0.2, rgb(138, 104, 70), M.Metal)
	vlift("LiftDoorR", 2.3, 9, 0.4, 1.15, 4.5, -0.2, rgb(138, 104, 70), M.Metal)
	local vind = vlift("LiftIndicator", 2.4, 0.9, 0.2, 0, 10.4, -0.5, DARK, M.SmoothPlastic, DECOR_)
	label(gui(vind, Enum.NormalId.Front, 40), "H  HOME", 0, 0, 1, 1, 18, AMBER, Enum.TextXAlignment.Center)
	prompt("LiftUp", vleaf, "Go up to your home", "Lift", 9)
	local vaultEntry = CFrame.lookAt(V0 + Vector3.new(14, 3.2, 13.5), V0 + Vector3.new(14, 3.2, 0))

	-- West wall: trophy case and the titles board
	vput("CaseWestBack", 0.5, 7, 32, -23.6, 5.2, 0, rgb(18, 22, 30), M.SmoothPlastic)
	vput("CaseWestShelf", 1.6, 0.3, 32, -22.8, 3.1, 0, STEEL, M.Metal, DECOR_)
	vput("CaseWestGlass", 0.2, 7, 32, -21.9, 5.2, 0, rgb(170, 200, 220), M.Glass, { Transparency = 0.8, CanCollide = false, CanQuery = false })
	vput("CaseWestLight", 0.3, 0.2, 30, -22.6, 8.6, 0, rgb(255, 224, 180), M.Neon, DECOR_)
	local titlesScreen = Common.block(vault, "TitlesBoard", Vector3.new(14, 3.2, 0.2), CFrame.lookAt(V0 + Vector3.new(-23.3, 9.1, 8), V0 + Vector3.new(-22, 9.1, 8)), SCREEN, M.SmoothPlastic, DECOR_)
	local titlesGui = gui(titlesScreen, Enum.NormalId.Front, 40)
	label(titlesGui, "TITLES", 0.04, 0.04, 0.4, 0.3, 24, AMBER)
	local titlesText = label(titlesGui, "", 0.04, 0.38, 0.92, 0.55, 18, TEXT, nil, false)
	titlesText.TextWrapped = true
	titlesText.TextYAlignment = Enum.TextYAlignment.Top
	titlesText.TextTruncate = Enum.TextTruncate.None

	-- Centre: eight mastery pedestals
	local pedestals = {}
	for i = 1, 8 do
		local x = -14 + (i - 1) * 4
		vcyl("PedestalBase", 2.2, 3, x, 1.1, -3, rgb(35, 39, 46), M.Metal)
		vcyl("PedestalTop", 0.3, 3.3, x, 2.35, -3, STEEL, M.Metal)
		local ring = vcyl("PedestalRing", 0.12, 2.6, x, 2.56, -3, AMBER, M.Neon, DECOR_)
		if i % 2 == 0 then
			Common.light(ring, rgb(255, 224, 180), 16, 1, false)
		end
		local orbPart = Common.ball(vault, "MasteryOrb", V0 + Vector3.new(x, 4, -3), 1.4, rgb(150, 156, 164), M.Neon, DECOR_)
		local plate = vput("PedestalPlate", 2.8, 1, 0.2, x, 1.4, -1.45, DARK, M.SmoothPlastic, DECOR_)
		local plateGui = gui(plate, Enum.NormalId.Back, 40)
		local nameLabel = label(plateGui, "", 0, 0, 1, 0.55, 16, TEXT, Enum.TextXAlignment.Center)
		local levelLabel = label(plateGui, "", 0, 0.5, 1, 0.5, 16, AMBER, Enum.TextXAlignment.Center)
		pedestals[i] = { orb = orbPart, ring = ring, name = nameLabel, level = levelLabel }
	end
	label(gui(vput("MasteryHeader", 12, 1.4, 0.2, 0, 6.6, -7.4, DARK, M.SmoothPlastic, DECOR_), Enum.NormalId.Back, 40), "FIGHTER MASTERY", 0, 0, 1, 1, 20, AMBER, Enum.TextXAlignment.Center)

	-- North wall: three premium alcoves (figures are rebuilt when ownership changes)
	for _, x in { -9, 0, 9 } do
		vput("AlcoveBack", 6.4, 8, 0.4, x, 5, -17.6, rgb(18, 22, 30), M.SmoothPlastic)
		vput("AlcoveStep", 5, 0.6, 3, x, 0.3, -15.8, STEEL, M.Metal, DECOR_)
	end

	-- East wall: cosmetics case, reserved Meme Vault section
	vput("CaseEastBack", 0.5, 7, 22, 23.6, 5.2, -6, rgb(18, 22, 30), M.SmoothPlastic)
	vput("CaseEastGlass", 0.2, 7, 22, 21.9, 5.2, -6, rgb(170, 200, 220), M.Glass, { Transparency = 0.8, CanCollide = false, CanQuery = false })
	label(gui(vput("CosmeticsHeader", 0.2, 1.2, 8, 23.2, 9.4, -6, DARK, M.SmoothPlastic, DECOR_), Enum.NormalId.Left, 40), "COSMETICS", 0, 0, 1, 1, 20, AMBER, Enum.TextXAlignment.Center)
	local reserved = Instance.new("Model")
	reserved.Name = "Reserved"
	reserved.Parent = vault
	vput("ReservedPanel", 0.4, 9, 8, 24, 4.5, 12, rgb(44, 48, 56), M.Metal, DECOR_)
	vput("ReservedConduit", 0.5, 0.5, 9, 23.6, 10.2, 12, STEEL, M.Metal, DECOR_)
	local anchorPart = vput("MemeVaultAnchorPart", 0.2, 0.2, 0.2, 23.2, 0.1, 12, STEEL, M.Metal, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	anchorPart.Parent = reserved
	local anchor = Instance.new("Attachment")
	anchor.Name = "MemeVaultDoorAnchor"
	anchor:SetAttribute("Purpose", "Reserved for the Meme Vault archive door (a later agent builds it). No door yet.")
	anchor.Parent = anchorPart

	-- South-west: the secret Archive alcove behind a sealed panel
	local alcove = Instance.new("Model")
	alcove.Name = "ArchiveAlcove"
	alcove.Parent = vault
	local al = piece(alcove, V)
	al("AlcoveFloor", 9, 0.4, 9, -19, 0.2, 13.5, rgb(46, 40, 34), M.WoodPlanks)
	al("AlcoveCeiling", 9, 0.4, 9, -19, 9.8, 13.5, CHARCOAL, M.Concrete)
	al("AlcoveWall", 0.4, 10, 9, -23.8, 5, 13.5, rgb(60, 44, 32), M.Wood)
	al("AlcoveWall", 9, 10, 0.4, -19, 5, 9.2, CHARCOAL, M.Concrete)
	al("Lectern", 2.2, 3.4, 1.6, -20.5, 1.7, 13.5, rgb(96, 62, 38), M.Wood)
	local lecternTop = al("LecternScreen", 2, 0.2, 1.4, -20.5, 3.5, 13.5, SCREEN, M.SmoothPlastic, DECOR_)
	local alcoveGui = gui(lecternTop, Enum.NormalId.Top, 60)
	local alcoveText = label(alcoveGui, "ARCHIVE COMPLETE", 0, 0, 1, 1, 14, GOLD, Enum.TextXAlignment.Center)
	alcoveText.TextWrapped = true
	local fileSlabs = {}
	for i = 1, 10 do
		local column = (i - 1) % 5
		local rowIndex = (i - 1) // 5
		fileSlabs[i] = al("ArchiveFile", 0.15, 1.1, 0.8, -23.5, 4.6 + rowIndex * 1.8, 10.7 + column * 1.2, rgb(63, 214, 232), M.Neon, DECOR_)
	end
	local alcoveLight = Common.light(fileSlabs[3], rgb(255, 214, 160), 16, 1, false)
	alcoveLight.Enabled = false
	local panel = piece(vault, V)("AlcovePanel", 0.5, 9.6, 9.2, -14.6, 4.8, 13.6, rgb(52, 56, 64), M.Metal)
	panel:SetAttribute("Sealed", true)
	local panelGui = gui(panel, Enum.NormalId.Right, 40)
	local panelText = label(panelGui, "", 0.05, 0.3, 0.9, 0.4, 18, rgb(150, 156, 164), Enum.TextXAlignment.Center)
	panelText.TextWrapped = true
	local panelClosed, panelOpen = panel.CFrame, panel.CFrame + Vector3.new(0, 10, 0)

	-- North-east: the owner's command console (owner's base only)
	local consolePart: BasePart? = nil
	if ownerBase then
		local cn = piece(vault, V * CFrame.new(18, 0, -13))
		cn("ConsoleDesk", 7, 3, 2.6, 0, 1.5, 0, rgb(35, 39, 46), M.Metal)
		cn("ConsoleTop", 7.4, 0.2, 3, 0, 3.1, 0, BRONZE, M.Metal, DECOR_)
		local screen = cn("ConsoleScreen", 5.4, 3, 0.3, 0, 5, -0.8, SCREEN, M.SmoothPlastic, DECOR_)
		cn("ConsoleArm", 0.4, 1.8, 0.4, 0, 3.9, -0.3, STEEL, M.Metal, DECOR_)
		label(gui(screen, Enum.NormalId.Back, 40), "COMMAND CONSOLE", 0, 0.15, 1, 0.7, 20, AMBER, Enum.TextXAlignment.Center)
		consolePart = cn("ConsolePad", 2, 0.3, 1, 0, 3.3, 0.9, DARK, M.SmoothPlastic, DECOR_)
		prompt("Console", consolePart :: BasePart, "Open control center", "Command console", 9)
	end

	root.Parent = parent

	-- ============================== Updates ==============================
	local function applyTheme(themeId: string)
		local theme = Homes.Themes[themeId] or Homes.Themes[Homes.DefaultTheme]
		for roleName, list in roles do
			local style = theme[roleName]
			if style then
				for _, part in list do
					part.Color = style[1]
					part.Material = style[2]
				end
			end
		end
		for _, light in lamps do
			light.Color = theme.lamp
		end
		home:SetAttribute("Theme", themeId)
	end

	local dynamic = Instance.new("Folder")
	dynamic.Name = "Dynamic"
	dynamic.Parent = vault
	local signature = ""

	local function rebuildDynamic(view: any)
		dynamic:ClearAllChildren()
		-- Win trophies: lit once earned
		for index, needed in Homes.WinMilestones do
			local z = -13 + (index - 1) * 5.2
			local earned = view.wins >= needed
			local color = if earned then GOLD else rgb(70, 76, 86)
			local material = if earned then M.Metal else M.SmoothPlastic
			local x = -22.2
			Common.block(dynamic, "TrophyBase", Vector3.new(1.6, 0.4, 1.6), CFrame.new(V0 + Vector3.new(x, 3.45, z)), rgb(35, 39, 46), M.Metal, DECOR_)
			Common.cylinder(dynamic, "TrophyStem", CFrame.new(V0 + Vector3.new(x, 4.3, z)), 1.4, 0.3, color, material, DECOR_)
			local cup = Common.cylinder(dynamic, "TrophyCup", CFrame.new(V0 + Vector3.new(x, 5.4, z)), 1.2, 1.5, color, material, DECOR_)
			if earned then
				Common.light(cup, GOLD, 8, 0.6, false)
			end
			local tag = Common.block(dynamic, "TrophyTag", Vector3.new(2.6, 0.7, 0.1), CFrame.lookAt(V0 + Vector3.new(-22.6, 2.4, z), V0 + Vector3.new(-21, 2.4, z)), DARK, M.SmoothPlastic, DECOR_)
			label(gui(tag, Enum.NormalId.Front, 50), string.format("%d WIN%s", needed, if needed == 1 then "" else "S"), 0, 0, 1, 1, 14, if earned then GOLD else rgb(110, 116, 126), Enum.TextXAlignment.Center)
		end
		-- Cosmetic tiles: one per owned cosmetic, 12 at most
		local shown = math.min(#view.cosmetics, 12)
		for i = 1, shown do
			local column, rowIndex = (i - 1) % 4, (i - 1) // 4
			local tile = Common.block(dynamic, "CosmeticTile", Vector3.new(4.2, 1.8, 0.2), CFrame.lookAt(V0 + Vector3.new(23.2, 7.0 - rowIndex * 2.2, -13 + column * 5.2 + 0.1), V0 + Vector3.new(22, 7.0 - rowIndex * 2.2, -13 + column * 5.2 + 0.1)), rgb(24, 32, 46), M.SmoothPlastic, DECOR_)
			label(gui(tile, Enum.NormalId.Front, 40), view.cosmetics[i], 0.05, 0.1, 0.9, 0.8, 14, TEXT, Enum.TextXAlignment.Center).TextWrapped = true
		end
		-- Premium fighters: a figure on each alcove
		for i, fighter in view.premiumOwned do
			if i > 3 then
				break
			end
			local x = ({ -9, 0, 9 })[i]
			local c = fighter.color
			local base = V0 + Vector3.new(x, 0.6, -15.8)
			Common.cylinder(dynamic, "FigureBase", CFrame.new(base + Vector3.new(0, 0.2, 0)), 0.4, 3, rgb(35, 39, 46), M.Metal, DECOR_)
			for _, dx in { -0.45, 0.45 } do
				Common.block(dynamic, "FigureLeg", Vector3.new(0.7, 2.6, 0.8), CFrame.new(base + Vector3.new(dx, 1.8, 0)), rgb(230, 226, 214), M.Marble, DECOR_)
			end
			Common.block(dynamic, "FigureTorso", Vector3.new(2.2, 2.4, 1.1), CFrame.new(base + Vector3.new(0, 4.3, 0)), rgb(230, 226, 214), M.Marble, DECOR_)
			Common.block(dynamic, "FigureSash", Vector3.new(2.3, 0.5, 1.2), CFrame.new(base + Vector3.new(0, 4.9, 0)), c, M.Neon, DECOR_)
			Common.ball(dynamic, "FigureHead", base + Vector3.new(0, 6.0, 0), 1.2, rgb(230, 226, 214), M.Marble, DECOR_)
			local name = Common.block(dynamic, "FigureName", Vector3.new(4.6, 0.8, 0.2), CFrame.new(base + Vector3.new(0, 0.9, 1.7)), DARK, M.SmoothPlastic, DECOR_)
			label(gui(name, Enum.NormalId.Back, 40), string.upper(fighter.name), 0, 0, 1, 1, 14, GOLD, Enum.TextXAlignment.Center)
			local spot = Common.block(dynamic, "FigureSpot", Vector3.new(0.5, 0.2, 0.5), CFrame.new(base + Vector3.new(0, 8.2, 1)), STEEL, M.Metal, DECOR_)
			Common.light(spot, rgb(255, 230, 190), 14, 1, false)
		end
	end

	local function render(view: any)
		-- Home: record, mastery, collection (a hidden toggle shows a short note instead)
		setText(recordLines[1], string.format("Wins  %d", view.wins))
		setText(recordLines[2], string.format("Matches  %d    Best streak  %d", view.matches, view.bestStreak))
		setText(recordLines[3], view.name)
		setText(recordLines[4], "Title  " .. view.title)
		setText(masteryTitle, if view.show.mastery then "MASTERY" else "MASTERY  hidden by the owner")
		for i, row in masteryRows do
			local entry = view.mastery[i]
			if entry and view.show.mastery then
				setText(row.name, entry.name)
				setText(row.level, "Lv " .. entry.level)
				row.fill.Size = UDim2.fromScale(entry.progress, 1)
				row.fill.BackgroundColor3 = entry.color
			else
				setText(row.name, "")
				setText(row.level, "")
				row.fill.Size = UDim2.fromScale(0, 1)
			end
		end
		setText(collectionLines[1], string.format("Titles  %d", #view.titles))
		setText(collectionLines[2], if view.show.cosmetics then string.format("Cosmetics  %d", #view.cosmetics) else "Cosmetics hidden")
		if not view.show.premium then
			setText(collectionLines[3], "Premium fighters hidden")
			setText(collectionLines[4], "")
		else
			local names = {}
			for _, fighter in view.premiumOwned do
				table.insert(names, fighter.name)
			end
			setText(collectionLines[3], string.format("Premium fighters  %d of %d", #names, view.premiumTotal))
			setText(collectionLines[4], if #names > 0 then table.concat(names, ", ") else "None owned yet")
		end
		for key, toggle in Homes.Toggles do
			local name = string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
			if pads[name] then
				setText(pads[name], string.format("%s: %s", string.upper(toggle.label), if view.show[key] then "SHOWN" else "HIDDEN"))
			end
		end
		setText(pads.Theme, "DECOR: " .. string.upper(view.theme))
		applyTheme(view.theme)

		-- Vault: pedestals update in place, the rest rebuilds only on a new signature
		for i, pedestal in pedestals do
			local entry = view.mastery[i]
			if entry then
				setText(pedestal.name, entry.name)
				setText(pedestal.level, "Level " .. entry.level)
				local size = 0.8 + entry.level / 20 * 1.6
				pedestal.orb.Size = Vector3.one * size
				pedestal.orb.Position = V0 + Vector3.new(-14 + (i - 1) * 4, 2.5 + size / 2 + 0.3, -3)
				pedestal.orb.Color = entry.color
				pedestal.ring.Color = entry.color
			end
		end
		setText(titlesText, if #view.titles > 0 then table.concat(view.titles, "   ") else "No titles yet")
		local parts = { tostring(view.wins), table.concat(view.cosmetics, ","), table.concat(view.titles, ",") }
		for _, fighter in view.premiumOwned do
			table.insert(parts, fighter.id)
		end
		local current = table.concat(parts, "|")
		if current ~= signature then
			signature = current
			rebuildDynamic(view)
		end
	end

	local function setAlcove(open: boolean, found: number, total: number)
		panel:SetAttribute("Sealed", not open)
		alcove:SetAttribute("Open", open)
		panel.CanCollide = not open
		panel.CFrame = if open then panelOpen else panelClosed
		alcoveLight.Enabled = open
		setText(panelText, if open then "" else string.format("SEALED\nRecover all %d Archive files\n%d of %d found", total, found, total))
		setText(alcoveText, if open then string.format("ARCHIVE COMPLETE\n%d of %d files", found, total) else "")
	end

	local built = {
		model = root,
		home = home,
		vault = vault,
		entry = entry,
		vaultEntry = vaultEntry,
		prompts = prompts,
		alcovePanel = panel,
		console = consolePart,
		applyTheme = applyTheme,
		render = render,
		setAlcove = setAlcove,
		setPad = function(key: string, text: string)
			if pads[key] then
				setText(pads[key], text)
			end
		end,
	}
	setAlcove(false, 0, 10)
	applyTheme(Homes.DefaultTheme)
	return built :: Built
end

return BaseHome
