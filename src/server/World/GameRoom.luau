-- GAME ROOM: a warm, lived-in room joined to the south wall of a personal base (ArtDirection 2, 3, 6;
-- DECISIONS 62). Built by BaseHome.build as part of the base model. Origin = middle of the home
-- floor; the room's inside runs x -17..17, z 20..46, 11 high, entered through a doorway in the
-- home's south wall at x 0.
--
--   west     fireplace (ember effect is a Base Effects Pack look), sofa, rug, beanbags, game shelf
--   south    Power Meter (strength tester), Reflex cabinet, jukebox, high score board
--   east     dance floor with a little light rig and speakers, a bench along the wall
--   ceiling  timber beams, string lights, pendant lamps
-- Everything that scores or rewards is server code (Services/GameRoomService); this module only
-- builds parts and exposes small setters for text and colour. No per-frame code.
-- Part budget: Homes.GameRoomPartBudget (350); effect parts are built on demand in "Effects".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.Parent.Arenas.Common)
local BaseStreet = require(script.Parent.BaseStreet)
local Homes = require(ReplicatedStorage.Shared.Config.Homes)

local GameRoom = {}

local M = Common.M
local rgb = Common.rgb
local DECOR = Common.GHOST

local STEEL = rgb(150, 156, 164)
local BRONZE = rgb(184, 115, 63)
local DARK = rgb(26, 28, 34)
local SCREEN = rgb(14, 22, 36)
local TEXT = rgb(238, 232, 220)
local AMBER = rgb(232, 162, 74)
local WOOD = rgb(110, 72, 44)
local WOOD_DARK = rgb(70, 46, 30)
local PLASTER = rgb(206, 190, 166)
local BRICK = rgb(142, 82, 62)
local FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

export type Built = {
	model: Model,
	prompts: { [string]: ProximityPrompt },
	seats: { BasePart },
	setEffect: (key: string, on: boolean) -> (),
	setParty: (on: boolean) -> (),
	animate: (hue: number) -> (),
	setJukebox: (text: string) -> (),
	setMeter: (score: number?, text: string) -> (),
	setReflex: (state: string, text: string) -> (),
	setBoard: (rows: { { name: string, power: string, reflex: string } }) -> (),
	partyParts: { BasePart },
}

local function surface(part: BasePart, face: Enum.NormalId, pixelsPerStud: number): SurfaceGui
	local item = Instance.new("SurfaceGui")
	item.Name = "Board"
	item.Face = face
	item.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	item.PixelsPerStud = pixelsPerStud
	item.LightInfluence = 0
	item.Parent = part
	return item
end

local function label(parent: Instance, text: string, x: number, y: number, w: number, h: number, size: number, color: Color3, align: Enum.TextXAlignment?): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Position = UDim2.fromScale(x, y)
	item.Size = UDim2.fromScale(w, h)
	item.Text = text
	item.TextSize = size
	item.TextColor3 = color
	item.FontFace = FONT
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

function GameRoom.build(root: Model, origin: Vector3, slot: number): Built
	local room = Instance.new("Model")
	room.Name = "GameRoom"
	room.Parent = root
	local effects = Instance.new("Folder")
	effects.Name = "Effects"
	effects.Parent = room

	local prompts: { [string]: ProximityPrompt } = {}
	local seats: { BasePart } = {}
	local partyParts: { BasePart } = {}
	local original: { [BasePart]: Color3 } = {}
	local hueParts: { BasePart } = {}
	local frame = CFrame.new(origin)

	local function put(name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
		return Common.block(room, name, Vector3.new(sx, sy, sz), frame * CFrame.new(x, y, z), color, material, extra)
	end
	local function cyl(name: string, height: number, diameter: number, x: number, y: number, z: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
		return Common.cylinder(room, name, frame * CFrame.new(x, y, z), height, diameter, color, material, extra)
	end
	local function ball(name: string, diameter: number, x: number, y: number, z: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
		return Common.ball(room, name, origin + Vector3.new(x, y, z), diameter, color, material, extra)
	end
	local function seat(name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: Color3, yaw: number?): BasePart
		local part = Common.block(room, name, Vector3.new(sx, sy, sz), frame * CFrame.new(x, y, z) * CFrame.Angles(0, yaw or 0, 0), color, M.Fabric, { ClassName = "Seat" })
		table.insert(seats, part)
		return part
	end
	local function prompt(key: string, part: BasePart, action: string, object: string, distance: number?): ProximityPrompt
		local item = BaseStreet.prompt(part, action, object, distance or 8)
		item.Name = key
		prompts[key] = item
		return item
	end
	local function party(part: BasePart)
		original[part] = part.Color
		table.insert(partyParts, part)
	end

	-- Shell: floor, ceiling, walls, wainscot, beams ------------------------------------------------
	put("RoomFloor", 40, 2, 30, 0, -1, 33, rgb(120, 80, 50), M.WoodPlanks)
	put("RoomCeiling", 40, 1.5, 30, 0, 11.75, 33, rgb(214, 204, 188), M.SmoothPlastic)
	put("RoomWallWest", 2, 11, 30, -18, 5.5, 33, PLASTER, M.SmoothPlastic)
	put("RoomWallEast", 2, 11, 30, 18, 5.5, 33, PLASTER, M.SmoothPlastic)
	put("RoomWallSouth", 38, 11, 2, 0, 5.5, 47, PLASTER, M.SmoothPlastic)
	put("WainscotEast", 0.3, 3.4, 26, 16.85, 1.7, 33, WOOD_DARK, M.Wood)
	put("WainscotSouth", 34, 3.4, 0.3, 0, 1.7, 45.85, WOOD_DARK, M.Wood)
	put("RailEast", 0.5, 0.3, 26, 16.8, 3.5, 33, BRONZE, M.Metal, DECOR)
	put("RailSouth", 34, 0.3, 0.5, 0, 3.5, 45.8, BRONZE, M.Metal, DECOR)
	for _, x in { -16.8, 16.8 } do
		put("Crown", 0.4, 0.4, 26, x, 10.8, 33, WOOD_DARK, M.Wood, DECOR)
	end
	put("CrownSouth", 34, 0.4, 0.4, 0, 10.8, 45.8, WOOD_DARK, M.Wood, DECOR)
	for _, z in { 24, 29, 34, 39, 44 } do
		put("Beam", 34, 0.9, 0.9, 0, 11, z, WOOD_DARK, M.Wood)
	end
	-- Doorway frame on the room side of the home's south wall
	put("DoorPostL", 0.7, 10, 0.5, -4.35, 5, 20.3, WOOD_DARK, M.Wood)
	put("DoorPostR", 0.7, 10, 0.5, 4.35, 5, 20.3, WOOD_DARK, M.Wood)
	put("DoorHead", 9.4, 0.8, 0.5, 0, 10.4, 20.3, WOOD_DARK, M.Wood)
	local sign = put("RoomSign", 6, 1.2, 0.2, 0, 9.4, 20.5, DARK, M.SmoothPlastic, DECOR)
	label(surface(sign, Enum.NormalId.Back, 40), "GAME ROOM", 0, 0, 1, 1, 22, AMBER, Enum.TextXAlignment.Center)

	-- Lights: string lights, pendants -----------------------------------------------------------------
	for _, side in { -1, 1 } do
		for i = 0, 5 do
			local z = 22.5 + i * 4.2
			local sag = 0.5 * math.sin(i / 5 * math.pi)
			local bulb = ball("StringBulb", 0.55, side * 16.3, 9.6 - sag, z, rgb(255, 214, 140), M.Neon, DECOR)
			if i % 2 == 0 then
				Common.light(bulb, rgb(255, 196, 120), 14, 0.5, false)
			end
		end
		put("StringWire", 0.08, 0.08, 25, side * 16.3, 9.9, 33.5, DARK, M.Metal, DECOR)
	end
	for _, spot in { { -9, 25 }, { -9, 40 }, { 0, 33 } } do
		cyl("PendantCord", 2, 0.1, spot[1], 10.2, spot[2], DARK, M.Metal, DECOR)
		local shade = cyl("PendantShade", 1.1, 2.4, spot[1], 8.7, spot[2], rgb(255, 200, 130), M.Neon, { Transparency = 0.2, CastShadow = false })
		Common.light(shade, rgb(255, 190, 120), 26, 1.0, false)
		party(shade)
	end

	-- West: fireplace, sofa, rug, beanbags, game shelf -----------------------------------------------
	put("ChimneyBreast", 2, 11, 9, -16, 5.5, 27, BRICK, M.Brick)
	put("HearthSlab", 2.6, 0.3, 9.6, -14.9, 0.15, 27, rgb(88, 84, 80), M.Slate)
	put("Mantel", 2.6, 0.5, 9.8, -15.2, 5.4, 27, WOOD, M.Wood)
	put("FireOpening", 0.3, 3.8, 4.8, -14.85, 2.2, 27, rgb(18, 14, 12), M.SmoothPlastic)
	put("FireLintel", 0.5, 0.6, 5.4, -14.8, 4.3, 27, STEEL, M.Metal, DECOR)
	for i, dz in { -1.1, 0, 1.1 } do
		cyl("Log", 3.6, 0.7, -15.3, 0.6 + (i % 2) * 0.35, 27 + dz, rgb(78, 52, 34), M.Wood)
	end
	cyl("MantelVase", 1.4, 0.7, -15.2, 6.35, 25.2, rgb(70, 110, 120), M.Glass)
	local clockFace = put("MantelClock", 0.3, 1.8, 1.8, -15.4, 6.5, 28.8, rgb(232, 224, 206), M.SmoothPlastic, DECOR)
	label(surface(clockFace, Enum.NormalId.Right, 30), "7:30", 0, 0, 1, 1, 14, DARK, Enum.TextXAlignment.Center)
	put("Rug", 11, 0.12, 12, -10.5, 0.06, 27, rgb(96, 54, 46), M.Fabric)
	put("RugBorder", 11.6, 0.1, 12.6, -10.5, 0.05, 27, AMBER, M.Fabric, DECOR)
	-- Sofa facing the fire (three seats)
	put("SofaBase", 3.6, 1, 8.4, -8.2, 1, 27, rgb(98, 70, 52), M.Fabric)
	put("SofaBack", 0.9, 3, 8.4, -6.6, 2.4, 27, rgb(88, 62, 46), M.Fabric)
	for _, z in { 22.9, 31.1 } do
		put("SofaArm", 3.6, 1.8, 0.9, -8.2, 1.6, z, rgb(88, 62, 46), M.Fabric)
	end
	for i = -1, 1 do
		seat("SofaSeat", 2.8, 0.7, 2.4, -8.6, 1.75, 27 + i * 2.6, rgb(116, 84, 62), math.rad(90))
	end
	put("CoffeeTable", 2.4, 0.3, 4, -11.6, 1.4, 27, WOOD, M.Wood)
	for _, z in { 25.4, 28.6 } do
		put("TableLeg", 2, 1.3, 0.3, -11.6, 0.65, z, WOOD_DARK, M.Wood)
	end
	cyl("Mug", 0.5, 0.5, -11.8, 1.8, 26.4, rgb(224, 214, 196), M.SmoothPlastic)
	cyl("Mug", 0.5, 0.5, -11.4, 1.8, 28, rgb(180, 70, 52), M.SmoothPlastic)
	-- Beanbags
	for _, z in { 21.6, 32.4 } do
		local bag = Common.block(room, "Beanbag", Vector3.new(3.4, 1.9, 3.4), frame * CFrame.new(-12.8, 0.95, z), rgb(70, 110, 120), M.Fabric, { ClassName = "Seat", Shape = Enum.PartType.Ball })
		table.insert(seats, bag)
	end
	-- Game shelf with boxed games, a lamp and a plant
	put("ShelfBack", 0.4, 6, 8, -16.6, 3, 40, WOOD_DARK, M.Wood)
	for i = 0, 3 do
		put("ShelfBoard", 1.4, 0.3, 8, -16, 0.4 + i * 1.7, 40, WOOD, M.Wood)
	end
	local boxColors = { rgb(170, 60, 50), rgb(60, 100, 150), rgb(210, 170, 70), rgb(80, 130, 90), rgb(130, 80, 140) }
	for level = 0, 2 do
		for i = 0, 3 do
			put("GameBox", 1, 1.3, 1.5, -16.1, 1.2 + level * 1.7, 37.4 + i * 1.7, boxColors[(level * 4 + i) % #boxColors + 1], M.SmoothPlastic, DECOR)
		end
	end
	cyl("Pot", 1.6, 2, -15.4, 0.8, 44.2, rgb(35, 39, 46), M.Metal)
	for _, offset in { { 0, 3, 0, 3 }, { 0.6, 4.2, 0.4, 2.1 }, { -0.6, 3.8, -0.4, 1.9 } } do
		ball("Leaves", offset[4], -15.4 + offset[1], offset[2], 44.2 + offset[3], rgb(70, 124, 72), M.Grass, DECOR)
	end

	-- East: bench, posters, plant ---------------------------------------------------------------------
	put("BenchBase", 2.4, 1, 9, 15.4, 1, 40.5, rgb(98, 70, 52), M.Fabric)
	put("BenchBack", 0.7, 2.4, 9, 16.4, 2.4, 40.5, rgb(88, 62, 46), M.Fabric)
	for i = -1, 1, 2 do
		seat("BenchSeat", 2, 0.6, 3.6, 15, 1.75, 40.5 + i * 2.2, rgb(116, 84, 62), math.rad(-90))
	end
	local posterTexts = { "ARCADE NIGHT", "TRY YOUR LUCK", "FRIENDS WELCOME" }
	for i, z in { 26, 33, 40 } do
		put("PosterFrame", 0.3, 4.6, 3.4, 16.7, 6.4, z, BRONZE, M.Metal, DECOR)
		local poster = put("Poster", 0.2, 4, 2.8, 16.55, 6.4, z, rgb(36, 52, 70), M.SmoothPlastic, DECOR)
		local text = label(surface(poster, Enum.NormalId.Left, 40), posterTexts[i], 0.05, 0.1, 0.9, 0.8, 16, TEXT, Enum.TextXAlignment.Center)
		text.TextWrapped = true
		text.TextTruncate = Enum.TextTruncate.None
	end
	cyl("Pot", 1.6, 2, 15.6, 0.8, 22.4, rgb(35, 39, 46), M.Metal)
	for _, offset in { { 0, 3, 0, 3 }, { 0.5, 4.2, 0.3, 2.1 }, { -0.5, 3.8, -0.3, 1.9 } } do
		ball("Leaves", offset[4], 15.6 + offset[1], offset[2], 22.4 + offset[3], rgb(78, 134, 80), M.Grass, DECOR)
	end

	-- Dance floor with a light rig and speakers -----------------------------------------------------
	for ix = 0, 2 do
		for iz = 0, 2 do
			local tile = put("DanceTile", 3.9, 0.15, 3.9, 5 + ix * 4, 0.075, 23 + iz * 4, if (ix + iz) % 2 == 0 then rgb(52, 46, 70) else rgb(36, 32, 52), M.Neon, DECOR)
			party(tile)
		end
	end
	put("DanceEdge", 12.4, 0.2, 0.3, 9, 0.1, 20.9, BRONZE, M.Metal, DECOR)
	put("DanceEdge", 12.4, 0.2, 0.3, 9, 0.1, 33.1, BRONZE, M.Metal, DECOR)
	put("DanceEdgeSide", 0.3, 0.2, 12.4, 2.9, 0.1, 27, BRONZE, M.Metal, DECOR)
	put("DanceEdgeSide", 0.3, 0.2, 12.4, 15.1, 0.1, 27, BRONZE, M.Metal, DECOR)
	put("RigBar", 13, 0.4, 0.4, 9, 10.2, 24.5, DARK, M.Metal)
	put("RigBar", 13, 0.4, 0.4, 9, 10.2, 29.5, DARK, M.Metal)
	for i = 0, 3 do
		local lamp = put("RigLamp", 0.9, 0.7, 0.9, 4 + i * 4, 9.7, 24.5 + (i % 2) * 5, rgb(255, 230, 190), M.Neon, DECOR)
		party(lamp)
		Common.spotLight(lamp, Enum.NormalId.Bottom, rgb(255, 214, 160), 20, 1.2, 50, false)
	end
	local discoBall = ball("MirrorBall", 2, 9, 8.6, 27, rgb(214, 220, 230), M.Metal, { Reflectance = 0.5 })
	cyl("MirrorCord", 1.4, 0.1, 9, 9.7, 27, DARK, M.Metal, DECOR)
	Common.light(discoBall, rgb(255, 230, 200), 22, 0.6, false)
	for _, z in { 21.5, 32.5 } do
		put("Speaker", 2, 4, 1.8, 16.4, 2, z, DARK, M.Metal)
		cyl("SpeakerCone", 0.3, 1.4, 15.3, 1.2, z, rgb(60, 62, 70), M.SmoothPlastic)
	end

	-- South wall: Power Meter, Reflex cabinet, jukebox, high scores --------------------------------------
	-- Power Meter
	put("MeterBase", 4.4, 3, 3, -13, 1.5, 44.2, rgb(150, 40, 36), M.Metal)
	put("MeterColumn", 2.4, 7, 1.6, -13, 6.5, 45.4, rgb(36, 40, 50), M.Metal)
	local meterSegments: { BasePart } = {}
	for i = 1, 10 do
		meterSegments[i] = put("MeterSegment", 1.5, 0.4, 0.2, -13, 3.3 + i * 0.6, 44.5, rgb(40, 44, 54), M.Neon, DECOR)
	end
	local meterBell = ball("MeterBell", 1.8, -13, 10.1, 45.4, rgb(232, 196, 92), M.Metal)
	local meterScreen = put("MeterScreen", 3.6, 1.6, 0.2, -13, 8.4, 44.3, SCREEN, M.SmoothPlastic, DECOR)
	local meterGui = surface(meterScreen, Enum.NormalId.Back, 50)
	label(meterGui, "POWER METER", 0, 0, 1, 0.5, 16, AMBER, Enum.TextXAlignment.Center)
	local meterText = label(meterGui, "Ready", 0, 0.5, 1, 0.5, 18, TEXT, Enum.TextXAlignment.Center)
	local striker = put("MeterStriker", 3.4, 0.5, 3.2, -13, 0.25, 41, rgb(60, 62, 70), M.Metal)
	put("MeterStrikerPlate", 2.6, 0.12, 2.4, -13, 0.56, 41, rgb(232, 196, 92), M.Metal, DECOR)
	put("MeterMalletHandle", 0.3, 0.3, 3.2, -11.2, 0.9, 42.4, WOOD, M.Wood)
	cyl("MeterMalletHead", 1.8, 1.2, -11.2, 1.1, 40.6, WOOD_DARK, M.Wood)
	prompt("PowerMeter", striker, "Start the needle", "Power Meter", 7)

	-- Reflex cabinet
	put("ReflexBody", 3.4, 4.2, 3, -5.5, 2.1, 44.2, rgb(34, 72, 120), M.Metal)
	put("ReflexDeck", 3.4, 0.5, 2.2, -5.5, 4.4, 43.2, rgb(28, 58, 100), M.Metal)
	put("ReflexBack", 3.2, 4.6, 1.6, -5.5, 6.9, 45.6, rgb(34, 72, 120), M.Metal)
	local reflexScreen = put("ReflexScreen", 2.8, 2.2, 0.2, -5.5, 6.6, 44.7, SCREEN, M.SmoothPlastic, DECOR)
	local reflexGui = surface(reflexScreen, Enum.NormalId.Back, 50)
	label(reflexGui, "REFLEX", 0, 0.02, 1, 0.3, 16, AMBER, Enum.TextXAlignment.Center)
	local reflexText = label(reflexGui, "Press to start", 0, 0.32, 1, 0.66, 18, TEXT, Enum.TextXAlignment.Center)
	reflexText.TextWrapped = true
	reflexText.TextTruncate = Enum.TextTruncate.None
	put("ReflexMarquee", 3.4, 0.9, 2, -5.5, 9.6, 45.2, rgb(232, 196, 92), M.Neon, DECOR)
	local reflexButton = cyl("ReflexButton", 0.5, 1.5, -5.5, 4.95, 43, rgb(210, 50, 44), M.Neon)
	for _, x in { -6.6, -4.4 } do
		cyl("ReflexKnob", 0.3, 0.5, x, 4.75, 43.4, rgb(232, 224, 206), M.SmoothPlastic)
	end
	prompt("Reflex", reflexButton, "Start the Reflex game", "Reflex cabinet", 7)

	-- Jukebox
	put("JukeboxBody", 4, 6, 2.4, 1, 3, 44.6, rgb(120, 70, 44), M.Wood)
	ball("JukeboxTop", 4, 1, 6, 44.6, rgb(120, 70, 44), M.Wood)
	put("JukeboxGrille", 3, 1.8, 0.2, 1, 1.6, 43.3, DARK, M.Metal)
	local jukeboxScreen = put("JukeboxScreen", 2.8, 1.4, 0.2, 1, 3.6, 43.3, SCREEN, M.SmoothPlastic, DECOR)
	local jukeboxText = label(surface(jukeboxScreen, Enum.NormalId.Back, 50), "", 0, 0, 1, 1, 16, TEXT, Enum.TextXAlignment.Center)
	jukeboxText.TextWrapped = true
	jukeboxText.TextTruncate = Enum.TextTruncate.None
	for _, x in { -0.9, 2.9 } do
		put("JukeboxNeon", 0.2, 5.4, 0.2, x, 3, 43.3, rgb(255, 150, 80), M.Neon, DECOR)
	end
	local jukeboxPad = put("JukeboxPad", 2, 0.5, 0.5, 1, 5.2, 43.3, DARK, M.SmoothPlastic, DECOR)
	prompt("Jukebox", jukeboxPad, "Change the music style", "Jukebox", 7)

	-- High scores
	local boardPart = put("ScoreBoard", 11, 5.4, 0.3, 9.5, 6.4, 45.7, SCREEN, M.SmoothPlastic, DECOR)
	put("ScoreFrame", 11.8, 6.2, 0.2, 9.5, 6.4, 45.8, BRONZE, M.Metal, DECOR)
	local boardGui = surface(boardPart, Enum.NormalId.Back, 50)
	label(boardGui, "HIGH SCORES", 0.04, 0.02, 0.6, 0.14, 16, AMBER)
	label(boardGui, "Meter", 0.56, 0.02, 0.2, 0.14, 15, AMBER, Enum.TextXAlignment.Right)
	label(boardGui, "Reflex", 0.78, 0.02, 0.2, 0.14, 15, AMBER, Enum.TextXAlignment.Right)
	local boardRows = {}
	for i = 1, 5 do
		local y = 0.18 + (i - 1) * 0.16
		boardRows[i] = {
			name = label(boardGui, "", 0.04, y, 0.52, 0.15, 16, TEXT),
			power = label(boardGui, "", 0.56, y, 0.2, 0.15, 16, TEXT, Enum.TextXAlignment.Right),
			reflex = label(boardGui, "", 0.78, y, 0.2, 0.15, 16, TEXT, Enum.TextXAlignment.Right),
		}
	end

	-- Setters ------------------------------------------------------------------------------------------
	local function setMeter(score: number?, text: string)
		local lit = if score then math.floor(score / 10 + 0.5) else 0
		for i, segment in meterSegments do
			if i <= lit then
				segment.Color = if i <= 4 then rgb(95, 196, 138) elseif i <= 7 then rgb(232, 196, 92) else rgb(220, 70, 60)
			else
				segment.Color = rgb(40, 44, 54)
			end
		end
		meterBell.Color = if score and score >= 95 then rgb(255, 236, 140) else rgb(232, 196, 92)
		setText(meterText, text)
		room:SetAttribute("MeterScore", score or -1)
	end
	local function setReflex(state: string, text: string)
		reflexScreen.Color = if state == "go" then rgb(30, 110, 60) elseif state == "wait" then rgb(90, 60, 20) elseif state == "false" then rgb(110, 30, 30) else SCREEN
		setText(reflexText, text)
		room:SetAttribute("ReflexState", state)
	end
	local function setBoard(rows)
		for i, row in boardRows do
			local entry = rows[i]
			setText(row.name, if entry then entry.name else "")
			setText(row.power, if entry then entry.power else "")
			setText(row.reflex, if entry then entry.reflex else "")
		end
	end
	setMeter(nil, "Ready")
	setReflex("idle", "Press to start")
	setBoard({})

	-- Effects built on demand (Base Effects Pack) -----------------------------------------------------
	local function clearEffect(key: string)
		local folder = effects:FindFirstChild(key)
		if folder then
			folder:Destroy()
		end
		for i = #hueParts, 1, -1 do
			if hueParts[i].Parent == nil then
				table.remove(hueParts, i)
			end
		end
	end
	local function setEffect(key: string, on: boolean)
		clearEffect(key)
		if not on then
			return
		end
		local folder = Instance.new("Folder")
		folder.Name = key
		folder.Parent = effects
		if key == "Fireplace" then
			local glow = Common.block(folder, "FireGlow", Vector3.new(0.4, 2.2, 3.4), frame * CFrame.new(-15.2, 1.5, 27), rgb(255, 140, 50), M.Neon, DECOR)
			Common.light(glow, rgb(255, 150, 70), 30, 2.2, false)
			Common.emitter(glow, {
				Texture = Common.FIRE, Color = ColorSequence.new(rgb(255, 170, 70), rgb(220, 60, 20)), LightEmission = 0.8, Rate = 24,
				Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(2, 4), SpreadAngle = Vector2.new(15, 15),
				Acceleration = Vector3.new(0, 3, 0),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			})
			local embers = Common.block(folder, "Embers", Vector3.new(0.4, 0.4, 3), frame * CFrame.new(-15.2, 2.8, 27), rgb(255, 200, 120), M.Neon, DECOR)
			Common.motes(embers, rgb(255, 170, 80), 10, { size = 0.18, minLife = 1.5, maxLife = 3, minSpeed = 2, maxSpeed = 4, spread = 20, acceleration = Vector3.new(0, 2, 0), alpha = 0.1 })
		elseif key == "LightShow" then
			for i = 0, 3 do
				local beam = Common.block(folder, "ShowBeam", Vector3.new(0.5, 11, 0.5), frame * CFrame.new(4 + i * 4, 5, 25 + (i % 2) * 4) * CFrame.Angles(math.rad(((i % 2) * 2 - 1) * 12), 0, math.rad((i - 1.5) * 8)), rgb(255, 80, 160), M.Neon, { Transparency = 0.7, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
				beam:SetAttribute("HueOffset", i * 0.25)
				table.insert(hueParts, beam)
			end
		end
	end
	local partyOn = false
	local function setParty(on: boolean)
		partyOn = on
		if not on then
			for part, color in original do
				if part.Parent then
					part.Color = color
				end
			end
		end
	end
	local function animate(hue: number)
		if partyOn then
			for i, part in partyParts do
				if part.Parent then
					part.Color = Color3.fromHSV((hue + i * 0.07) % 1, 0.65, 1)
				end
			end
		end
		for _, part in hueParts do
			if part.Parent then
				local offset = part:GetAttribute("HueOffset")
				part.Color = Color3.fromHSV((hue + (if typeof(offset) == "number" then offset else 0)) % 1, 0.8, 1)
			end
		end
	end

	return {
		model = room,
		prompts = prompts,
		seats = seats,
		setEffect = setEffect,
		setParty = setParty,
		animate = animate,
		setJukebox = function(text: string)
			setText(jukeboxText, text)
		end,
		setMeter = setMeter,
		setReflex = setReflex,
		setBoard = setBoard,
		partyParts = partyParts,
	} :: Built
end

return GameRoom
