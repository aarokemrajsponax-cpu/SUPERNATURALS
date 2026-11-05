-- The Training Studio: a large training facility for many players at once (ArtDirection sections
-- 3, 4, 6). Warm and bright rather than cold: ceramic and plaster cladding over walnut wainscot,
-- walnut ceiling beams with warm light panels, an oak decking walkway, fabric acoustic panels and
-- planters, with the facility's brushed steel and a little training cyan kept for wayfinding.
--
-- Plan, 168 x 238 studs inside (x east, z south; the entrance is on the east wall):
--   north strip   eight practice bays, each 18 wide and 38 deep: a dummy (DummyService) on a round
--                 target pad with room to move round it, glass dividers, a firing line 14 studs
--                 out, a floor plate, a name board and a big readout screen (last hit, combo, DPS)
--   middle band   the plaza, 28 deep: oak decking, Jeffery's platform (west), the practice console
--                 (east), benches and planters; the entrance from the hub opens onto it
--   south part    four practice arenas in two rows, each 72 x 72 of open floor with a low rail,
--                 cover walls and pillars, two raised platforms with ramps and a low dais, and a
--                 theme (Config/Practice Themes) that changes its floor, light and props. An aisle
--                 between the columns and a cross aisle between the rows keep every walkway open.
--
-- The room stays inside Selection.TrainingZone (so every power and phase is a free trial here).
-- Built from parts only; no asset ids.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.Common)
local Practice = require(ReplicatedStorage.Shared.Config.Practice)

local TrainingHall = {}

local M = Common.M
local rgb = Common.rgb
local block, cylinder = Common.block, Common.cylinder
local vary = Common.vary
local SMALL, GHOST = Common.SMALL, Common.GHOST

local NAVY = rgb(14, 22, 36)
local CHARCOAL = rgb(34, 33, 34)
local GRAPHITE = rgb(40, 40, 43)
local FLOORTONE = rgb(78, 74, 70)
local DECKSLATE = rgb(96, 92, 88)
local CEILING = rgb(84, 74, 66)
local STEEL = rgb(138, 146, 156)
local PLASTER = rgb(234, 228, 216)
local COOL = rgb(240, 242, 245)
local WARM = rgb(255, 238, 212)
local AMBER = rgb(232, 162, 74)
local CYAN = rgb(63, 214, 232)
local COPPER = rgb(184, 115, 63)
local BRASS = rgb(176, 138, 82)
local WALNUT = rgb(98, 66, 44)
local OAK = rgb(166, 124, 82)
local FABRIC = rgb(128, 116, 100)
local LEAF = rgb(70, 118, 68)
local LEAF_LIGHT = rgb(92, 140, 80)
local SOIL = rgb(48, 38, 30)

local SANS = "rbxasset://fonts/families/BuilderSans.json"
local MONO = "rbxasset://fonts/families/RobotoMono.json"
local DISPLAY = "rbxasset://fonts/families/Michroma.json"

local HX, HZ = 84, 119 -- half the room inside
local HEIGHT = 30
local BAY_COUNT = 8
local BAY_PITCH = 18
local BAY_Z = -106 -- dummy pad centre
local FIRING_Z = -92
local PLAZA_Z = -67 -- middle of the plaza band, also the entrance
local ARENA_SIZE = 72
local ARENA_CENTERS = { Vector3.new(-40, 0, -9), Vector3.new(40, 0, -9), Vector3.new(-40, 0, 71), Vector3.new(40, 0, 71) }
local BAY_NAMES = { "PUNCHING BAG", "GUARD DUMMY", "SPARRING DUMMY", "PUNCHING BAG", "GUARD DUMMY", "SPARRING DUMMY", "PUNCHING BAG", "GUARD DUMMY" }

export type Bay = { labels: { last: TextLabel, combo: TextLabel, dps: TextLabel, note: TextLabel }, spot: CFrame, name: string }
export type SparFloor = { index: number, center: Vector3, size: number, player: CFrame, jeffery: CFrame, setTheme: (string) -> (), theme: () -> string }
export type Layout = { bays: { Bay }, floors: { SparFloor }, platform: CFrame, console: BasePart, jeffery: Model }

local function at(ctx: Common.Context, x: number, y: number, z: number): Vector3
	return ctx.top + Vector3.new(x, y, z)
end

local function bayX(index: number): number
	return -(BAY_COUNT - 1) * BAY_PITCH / 2 + (index - 1) * BAY_PITCH
end

-- Text -------------------------------------------------------------------------------------------
-- World text is bold and large: Builder Sans Bold or ExtraBold for words, RobotoMono Bold for
-- numbers, Michroma only for the one big engraved room name. Labels scale to fill their board.

local function font(family: string, weight: Enum.FontWeight): Font
	return Font.new(family, weight)
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.TextWrapped = true
	text.FontFace = props.Font or font(SANS, Enum.FontWeight.Bold)
	text.TextColor3 = props.Color or COOL
	text.Text = props.Text or ""
	text.Position = props.Position or UDim2.fromScale(0, 0)
	text.Size = props.Size or UDim2.fromScale(1, 1)
	text.TextXAlignment = props.Align or Enum.TextXAlignment.Center
	if props.Max then
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = props.Max
		limit.Parent = text
	end
	text.Name = props.Name or "Text"
	text.Parent = parent
	return text
end

local function gui(part: BasePart, face: Enum.NormalId, pixelsPerStud: number): SurfaceGui
	local item = Instance.new("SurfaceGui")
	item.Name = "Sign"
	item.Face = face
	item.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	item.PixelsPerStud = pixelsPerStud
	item.LightInfluence = 0
	item.Parent = part
	return item
end

-- One board, one text: fills the board with a small margin
local function sign(part: BasePart, face: Enum.NormalId, text: string, color: Color3, props: { [string]: any }?): SurfaceGui
	local surface = gui(part, face, if props and props.Pixels then props.Pixels else 40)
	label(surface, {
		Text = text, Color = color,
		Font = if props and props.Font then props.Font else font(SANS, Enum.FontWeight.ExtraBold),
		Position = UDim2.fromScale(0.04, 0.08), Size = UDim2.fromScale(0.92, 0.84),
	})
	return surface
end

-- The readout screen of one bay: three numbers and a note line
local function readoutScreen(ctx: Common.Context, x: number, title: string): { last: TextLabel, combo: TextLabel, dps: TextLabel, note: TextLabel }
	local screen = block(ctx.model, "Readout", Vector3.new(15, 7.6, 0.3), CFrame.new(at(ctx, x, 12.6, -HZ + 0.35)), NAVY, M.SmoothPlastic, SMALL)
	block(ctx.model, "ReadoutFrame", Vector3.new(15.6, 8.2, 0.2), CFrame.new(at(ctx, x, 12.6, -HZ + 0.2)), BRASS, M.Metal, SMALL)
	local surface = gui(screen, Enum.NormalId.Back, 60)
	label(surface, { Name = "Title", Text = title, Position = UDim2.fromScale(0.04, 0.03), Size = UDim2.fromScale(0.92, 0.2), Color = WARM, Max = 90, Font = font(SANS, Enum.FontWeight.ExtraBold) })
	local made = {}
	local columns = { { "last", "LAST HIT" }, { "combo", "COMBO" }, { "dps", "DPS (5 S)" } }
	for index, column in columns do
		local left = 0.03 + (index - 1) * 0.323
		label(surface, { Name = column[1] .. "Name", Text = column[2], Position = UDim2.fromScale(left, 0.25), Size = UDim2.fromScale(0.31, 0.12), Color = rgb(210, 216, 224), Max = 60 })
		made[column[1]] = label(surface, {
			Name = column[1], Text = if column[1] == "combo" then "0" elseif column[1] == "dps" then "0.0" else "-",
			Position = UDim2.fromScale(left, 0.38), Size = UDim2.fromScale(0.31, 0.36),
			Color = if column[1] == "dps" then AMBER else COOL, Max = 120, Font = font(MONO, Enum.FontWeight.Bold),
		})
	end
	made.note = label(surface, { Name = "note", Text = "Hit the dummy to start", Position = UDim2.fromScale(0.04, 0.77), Size = UDim2.fromScale(0.92, 0.18), Color = rgb(214, 220, 228), Max = 60 })
	return made
end

-- Dressing ---------------------------------------------------------------------------------------

-- A planter: walnut box, dark soil and three soft leaf masses (no terrain, no grass material)
local function planter(ctx: Common.Context, x: number, z: number, size: number?)
	local s = size or 1
	local model = ctx.model
	block(model, "PlanterBox", Vector3.new(3.6 * s, 2.2, 3.6 * s), CFrame.new(at(ctx, x, 1.1, z)), WALNUT, M.WoodPlanks, SMALL)
	block(model, "PlanterRim", Vector3.new(3.9 * s, 0.2, 3.9 * s), CFrame.new(at(ctx, x, 2.25, z)), BRASS, M.Metal, GHOST)
	Common.ball(model, "Leaves", at(ctx, x, 3.7 * s, z), 3.4 * s, LEAF, M.Fabric, GHOST)
	Common.ball(model, "Leaves", at(ctx, x + 0.9 * s, 4.5 * s, z - 0.5 * s), 2.4 * s, LEAF_LIGHT, M.Fabric, GHOST)
end

-- A bench: oak seat on two steel legs, facing north
local function bench(ctx: Common.Context, x: number, z: number)
	local model = ctx.model
	block(model, "BenchSeat", Vector3.new(9, 0.5, 2.4), CFrame.new(at(ctx, x, 1.9, z)), OAK, M.WoodPlanks, SMALL)
	block(model, "BenchBack", Vector3.new(9, 1.6, 0.4), CFrame.new(at(ctx, x, 3.1, z + 1.1)), OAK, M.WoodPlanks, GHOST)
	for _, side in { -1, 1 } do
		block(model, "BenchLeg", Vector3.new(0.5, 1.7, 2.2), CFrame.new(at(ctx, x + side * 3.8, 0.85, z)), STEEL, M.Metal, SMALL)
	end
end

-- Shell -----------------------------------------------------------------------------------------

local function shell(ctx: Common.Context)
	local model = ctx.model
	-- Floor: DiamondPlate service floor, slate walkways, an oak deck through the plaza
	block(model, "Floor", Vector3.new(HX * 2 + 2.4, 1.6, HZ * 2 + 2.4), CFrame.new(at(ctx, 0, -0.8, 0)), FLOORTONE, M.DiamondPlate)
	block(model, "Walkway", Vector3.new(HX * 2 - 2, 0.1, 28), CFrame.new(at(ctx, 0, 0.05, PLAZA_Z)), DECKSLATE, M.Slate, GHOST)
	block(model, "OakDeck", Vector3.new(HX * 2 - 4, 0.08, 8), CFrame.new(at(ctx, 0, 0.12, PLAZA_Z)), OAK, M.WoodPlanks, GHOST)
	block(model, "AisleNS", Vector3.new(10, 0.1, 162), CFrame.new(at(ctx, 0, 0.05, 28)), DECKSLATE, M.Slate, GHOST)
	block(model, "AisleEW", Vector3.new(HX * 2 - 2, 0.1, 10), CFrame.new(at(ctx, 0, 0.05, 31)), DECKSLATE, M.Slate, GHOST)
	block(model, "FiringLine", Vector3.new(HX * 2 - 8, 0.06, 0.3), CFrame.new(at(ctx, 0, 0.1, FIRING_Z)), CYAN, M.Neon, { CastShadow = false, CanCollide = false, Transparency = 0.65 })
	block(model, "SafetyEdgeN", Vector3.new(HX * 2, 0.06, 0.5), CFrame.new(at(ctx, 0, 0.08, -HZ + 0.9)), AMBER, M.SmoothPlastic, GHOST)

	-- Walls: walnut wainscot with a brass cap, plaster cladding above
	local function wall(name: string, size: Vector3, centre: Vector3)
		block(model, name .. "Base", Vector3.new(size.X, 4, size.Z), CFrame.new(centre + Vector3.new(0, 2, 0)), WALNUT, M.WoodPlanks)
		block(model, name .. "Cap", Vector3.new(size.X + 0.2, 0.3, size.Z + 0.2), CFrame.new(centre + Vector3.new(0, 4.15, 0)), BRASS, M.Metal, GHOST)
		block(model, name, Vector3.new(size.X, HEIGHT - 4, size.Z), CFrame.new(centre + Vector3.new(0, 4 + (HEIGHT - 4) / 2, 0)), PLASTER, M.SmoothPlastic)
	end
	wall("WallN", Vector3.new(HX * 2 + 2.4, 0, 1.2), at(ctx, 0, 0, -HZ - 0.6))
	wall("WallS", Vector3.new(HX * 2 + 2.4, 0, 1.2), at(ctx, 0, 0, HZ + 0.6))
	wall("WallW", Vector3.new(1.2, 0, HZ * 2), at(ctx, -HX - 0.6, 0, 0))
	-- East wall with the entrance: two leaves and a lintel over a 14 stud opening
	local north = (PLAZA_Z - 7) + HZ
	local south = HZ - (PLAZA_Z + 7)
	wall("WallEA", Vector3.new(1.2, 0, north), at(ctx, HX + 0.6, 0, -HZ + north / 2))
	wall("WallEB", Vector3.new(1.2, 0, south), at(ctx, HX + 0.6, 0, HZ - south / 2))
	block(model, "Lintel", Vector3.new(1.2, HEIGHT - 15, 14), CFrame.new(at(ctx, HX + 0.6, 15 + (HEIGHT - 15) / 2, PLAZA_Z)), PLASTER, M.SmoothPlastic)
	-- Portal frame: steel posts, walnut head beam, one thin cyan strip
	for _, side in { -1, 1 } do
		block(model, "PortalPost", Vector3.new(1.8, 15, 1), CFrame.new(at(ctx, HX - 0.1, 7.5, PLAZA_Z + side * 7.5)), STEEL, M.Metal, SMALL)
	end
	block(model, "PortalBeam", Vector3.new(1.8, 1, 16), CFrame.new(at(ctx, HX - 0.1, 15.1, PLAZA_Z)), WALNUT, M.WoodPlanks, SMALL)
	block(model, "PortalStripTop", Vector3.new(0.12, 0.12, 14), CFrame.new(at(ctx, HX - 0.8, 14.4, PLAZA_Z)), CYAN, M.Neon, GHOST)
	local nameBoard = block(model, "RoomSign", Vector3.new(26, 5, 0.4), CFrame.lookAt(at(ctx, HX - 0.9, 20, PLAZA_Z), at(ctx, 0, 20, PLAZA_Z)), NAVY, M.SmoothPlastic, SMALL)
	sign(nameBoard, Enum.NormalId.Front, "TRAINING STUDIO", COOL, { Font = font(DISPLAY, Enum.FontWeight.Regular), Pixels = 30 })
	local subBoard = block(model, "RoomSubtitle", Vector3.new(26, 2.8, 0.4), CFrame.lookAt(at(ctx, HX - 0.9, 16.8, PLAZA_Z), at(ctx, 0, 16.8, PLAZA_Z)), NAVY, M.SmoothPlastic, SMALL)
	sign(subBoard, Enum.NormalId.Front, "Practice bays and arenas with Jeffery", rgb(222, 214, 198), { Pixels = 30 })

	-- Ribs along the walls, fabric acoustic panels between them
	local ribX = { -70, -42, -14, 14, 42, 70 }
	for _, x in ribX do
		block(model, "RibN", Vector3.new(1.2, HEIGHT - 4, 0.8), CFrame.new(at(ctx, x, 4 + (HEIGHT - 4) / 2, -HZ + 0.4)), STEEL, M.Metal, SMALL)
		block(model, "RibS", Vector3.new(1.2, HEIGHT - 4, 0.8), CFrame.new(at(ctx, x, 4 + (HEIGHT - 4) / 2, HZ - 0.4)), STEEL, M.Metal, SMALL)
	end
	for index = 1, #ribX - 1 do
		local x = (ribX[index] + ribX[index + 1]) / 2
		if index % 2 == 0 then
			block(model, "FabricPanel", Vector3.new(20, 8, 0.4), CFrame.new(at(ctx, x, 21, HZ - 0.2)), FABRIC, M.Fabric, SMALL)
		end
	end
	for _, z in { -102, -68, -34, 0, 34, 68, 102 } do
		block(model, "RibW", Vector3.new(0.8, HEIGHT - 4, 1.2), CFrame.new(at(ctx, -HX + 0.4, 4 + (HEIGHT - 4) / 2, z)), STEEL, M.Metal, SMALL)
	end
	for _, z in { -85, -17, 51, 85 } do
		block(model, "FabricPanel", Vector3.new(0.4, 8, 20), CFrame.new(at(ctx, -HX + 0.2, 21, z)), FABRIC, M.Fabric, SMALL)
	end

	-- Ceiling: warm walnut beams over a dark slab, light panels in the coffers
	block(model, "Ceiling", Vector3.new(HX * 2 + 2.4, 1, HZ * 2 + 2.4), CFrame.new(at(ctx, 0, HEIGHT + 0.5, 0)), CEILING, M.Metal)
	for _, x in { -56, -28, 0, 28, 56 } do
		block(model, "CeilingBeamZ", Vector3.new(1.6, 1.8, HZ * 2), CFrame.new(at(ctx, x, HEIGHT - 0.9, 0)), WALNUT, M.WoodPlanks, SMALL)
	end
	for _, z in { -102, -68, -34, 0, 34, 68, 102 } do
		block(model, "CeilingBeamX", Vector3.new(HX * 2, 1.4, 1.6), CFrame.new(at(ctx, 0, HEIGHT - 0.7, z)), WALNUT, M.WoodPlanks, SMALL)
	end
	local lamps = 0
	for _, x in { -42, -14, 14, 42 } do
		for _, z in { -85, -51, -17, 17, 51, 85 } do
			local panel = block(model, "LightPanel", Vector3.new(10, 0.2, 5), CFrame.new(at(ctx, x, HEIGHT - 0.1, z)), WARM, M.Neon, GHOST)
			lamps += 1
			if lamps % 2 == 1 then
				Common.surfaceLight(panel, Enum.NormalId.Bottom, WARM, 60, 1.5, 120)
			end
		end
	end

	-- Directory over the aisle, a status board in the plaza, benches and planters
	for _, side in { -1, 1 } do
		block(model, "DirectoryPost", Vector3.new(0.9, 13, 0.9), CFrame.new(at(ctx, side * 11.5, 6.5, -52)), WALNUT, M.WoodPlanks, SMALL)
	end
	local directory = block(model, "Directory", Vector3.new(24, 6, 0.5), CFrame.new(at(ctx, 0, 11, -52)), NAVY, M.SmoothPlastic, SMALL)
	block(model, "DirectoryTrim", Vector3.new(24.6, 0.4, 0.7), CFrame.new(at(ctx, 0, 14.2, -52)), BRASS, M.Metal, GHOST)
	local board = gui(directory, Enum.NormalId.Front, 40)
	label(board, { Name = "Title", Text = "PRACTICE ARENAS", Position = UDim2.fromScale(0.04, 0.06), Size = UDim2.fromScale(0.92, 0.46), Color = WARM, Font = font(SANS, Enum.FontWeight.ExtraBold) })
	label(board, { Name = "Where", Text = "1 and 3 west      2 and 4 east", Position = UDim2.fromScale(0.04, 0.56), Size = UDim2.fromScale(0.92, 0.34), Color = rgb(222, 228, 236) })
	local status = block(model, "StatusBoard", Vector3.new(0.4, 5, 16), CFrame.lookAt(at(ctx, -HX + 0.5, 9, -64), at(ctx, 0, 9, -64)), NAVY, M.SmoothPlastic, SMALL)
	sign(status, Enum.NormalId.Front, "ALL POWERS ARE FREE HERE\nNOTHING IS AT STAKE", CYAN, { Pixels = 40 })
	bench(ctx, -52, -57)
	bench(ctx, 52, -57)
	for _, spot in { { 80, -77 }, { 80, -57 }, { -80, -77 }, { -80, -57 }, { 80, 20 }, { -80, 20 }, { 80, 113 }, { -80, 113 } } do
		planter(ctx, spot[1], spot[2])
	end
	local _ = ctx.random
end

-- Practice bays ---------------------------------------------------------------------------------

local function bays(ctx: Common.Context): { Bay }
	local model = ctx.model
	local made = {}
	for index = 1, BAY_COUNT do
		local x = bayX(index)
		-- The round target pad: a low drum, a cyan ring, a plate, a white inner ring and an amber centre
		cylinder(model, "PadBase", CFrame.new(at(ctx, x, 0.2, BAY_Z)), 0.4, 9, GRAPHITE, M.Metal, SMALL)
		cylinder(model, "PadRing", CFrame.new(at(ctx, x, 0.43, BAY_Z)), 0.06, 8.4, CYAN, M.Neon, { CastShadow = false, CanCollide = false, Transparency = 0.4 })
		cylinder(model, "PadPlate", CFrame.new(at(ctx, x, 0.46, BAY_Z)), 0.06, 7.6, CHARCOAL, M.DiamondPlate, GHOST)
		cylinder(model, "PadInner", CFrame.new(at(ctx, x, 0.5, BAY_Z)), 0.06, 4.4, COOL, M.SmoothPlastic, GHOST)
		cylinder(model, "PadCentre", CFrame.new(at(ctx, x, 0.54, BAY_Z)), 0.06, 1.6, AMBER, M.SmoothPlastic, GHOST)
		-- Floor plate at the firing line and the name board on the wall
		local plate = block(model, "BayPlate", Vector3.new(9, 0.08, 3.4), CFrame.new(at(ctx, x, 0.1, FIRING_Z + 3.6)) * CFrame.Angles(0, math.pi, 0), NAVY, M.SmoothPlastic, GHOST)
		local plateGui = gui(plate, Enum.NormalId.Top, 40)
		label(plateGui, { Name = "Number", Text = `BAY {index}`, Position = UDim2.fromScale(0.05, 0.06), Size = UDim2.fromScale(0.9, 0.88), Color = COOL, Font = font(MONO, Enum.FontWeight.Bold) })
		local name = block(model, "BayName", Vector3.new(15, 3, 0.3), CFrame.new(at(ctx, x, 18.9, -HZ + 0.35)), WALNUT, M.WoodPlanks, SMALL)
		local nameGui = sign(name, Enum.NormalId.Back, BAY_NAMES[index], WARM, { Pixels = 40 })
		nameGui.Name = "BayNameSign"
		local labels = readoutScreen(ctx, x, `BAY {index}`)
		table.insert(made, {
			labels = labels,
			spot = Common.lookAt(at(ctx, x, 3, BAY_Z), at(ctx, x, 3, BAY_Z + 1)),
			name = BAY_NAMES[index],
		})
	end
	-- Dividers: a steel post and a glass panel between neighbouring bays (never a flat clear sheet)
	for index = 0, BAY_COUNT do
		local x = bayX(1) - BAY_PITCH / 2 + index * BAY_PITCH
		block(model, "DividerPost", Vector3.new(0.8, 10, 0.8), CFrame.new(at(ctx, x, 5, -90)), STEEL, M.Metal, SMALL)
		if index > 0 and index < BAY_COUNT then
			block(model, "DividerGlass", Vector3.new(0.2, 8, 28), CFrame.new(at(ctx, x, 5.6, -104.4)), rgb(150, 190, 210), M.Glass, { Transparency = 0.7, Reflectance = 0.15, CastShadow = false })
			block(model, "DividerRail", Vector3.new(0.5, 0.3, 29), CFrame.new(at(ctx, x, 9.7, -104.5)), BRASS, M.Metal, SMALL)
			block(model, "DividerFoot", Vector3.new(0.5, 0.3, 29), CFrame.new(at(ctx, x, 1.6, -104.5)), STEEL, M.Metal, SMALL)
		end
	end
	return made
end

-- Practice arenas ---------------------------------------------------------------------------------------

-- Theme props: no collision, only the active theme's set is in the world. They stand on a ring
-- 31 studs out from the middle, clear of the fighting lanes.
local function themeProps(centre: Vector3): { [string]: Model }
	local sets = {}
	local function set(id: string): Model
		local group = Instance.new("Model")
		group.Name = "Theme_" .. id
		sets[id] = group
		return group
	end
	local r = 31
	local function onRing(angle: number, y: number): Vector3
		return centre + Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r)
	end

	-- Studio: eight steel marker posts with soft cyan caps
	local studio = set("Studio")
	for k = 0, 7 do
		local p = onRing(math.rad(22.5 + k * 45), 0)
		block(studio, "Marker", Vector3.new(1, 3, 1), CFrame.new(p + Vector3.new(0, 1.5, 0)), STEEL, M.Metal, GHOST)
		block(studio, "MarkerCap", Vector3.new(0.7, 0.2, 0.7), CFrame.new(p + Vector3.new(0, 3.1, 0)), CYAN, M.Neon, GHOST)
	end
	-- Proving Grounds: weathered pillars with a rune glow
	local proving = set("ProvingGrounds")
	for k = 0, 5 do
		local p = onRing(math.rad(k * 60 + 20), 0)
		cylinder(proving, "Pillar", CFrame.new(p + Vector3.new(0, 3.5, 0)), 7, 2.6, rgb(150, 145, 134), M.Slate, GHOST)
		block(proving, "Rune", Vector3.new(1.4, 1.4, 0.15), CFrame.lookAt(p + Vector3.new(0, 4.2, 0), centre + Vector3.new(0, 4.2, 0)), rgb(120, 222, 236), M.Neon, GHOST)
	end
	-- Ruined Fortress: broken wall blocks and two braziers
	local fortress = set("RuinedFortress")
	for k = 0, 5 do
		local p = onRing(math.rad(k * 60 + 10), 0)
		block(fortress, "Rubble", Vector3.new(4.4, 2.6 + (k % 3) * 0.8, 2.4), CFrame.new(p + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, k, 0), rgb(120, 112, 102), M.Cobblestone, GHOST)
	end
	for _, angle in { 200, 340 } do
		local brazierAt = onRing(math.rad(angle), 0)
		cylinder(fortress, "Brazier", CFrame.new(brazierAt + Vector3.new(0, 1.6, 0)), 3.2, 2.2, rgb(56, 54, 52), M.Metal, GHOST)
		local flame = block(fortress, "Flame", Vector3.new(1.2, 1.2, 1.2), CFrame.new(brazierAt + Vector3.new(0, 3.5, 0)), rgb(255, 160, 80), M.Neon, GHOST)
		Common.light(flame, rgb(255, 170, 100), 24, 1.2, false)
	end
	-- Digital Grid: floating data cubes
	local grid = set("DigitalGrid")
	for k = 0, 5 do
		local p = onRing(math.rad(k * 60 + 40), 4 + (k % 2) * 2)
		block(grid, "DataCube", Vector3.new(2.2, 2.2, 2.2), CFrame.new(p) * CFrame.Angles(0.5, k, 0.3), rgb(70, 220, 230), M.Glass, { Transparency = 0.35, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		block(grid, "DataCore", Vector3.new(0.8, 0.8, 0.8), CFrame.new(p) * CFrame.Angles(0.5, k, 0.3), rgb(210, 250, 255), M.Neon, GHOST)
	end
	-- Corrupted Wastes: crystal shards
	local wastes = set("CorruptedWastes")
	for k = 0, 7 do
		local p = onRing(math.rad(k * 45 + 15), 0)
		block(wastes, "Shard", Vector3.new(1.4, 5 + (k % 2) * 2, 1.4), CFrame.new(p + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0.12 * (k % 4 - 2), k, 0.18), rgb(152, 102, 222), M.Neon, GHOST)
	end
	-- Soul Foundry: vent grates and blue soul-fire columns
	local foundry = set("SoulFoundry")
	for k = 0, 5 do
		local p = onRing(math.rad(k * 60 + 30), 0)
		cylinder(foundry, "Vent", CFrame.new(p + Vector3.new(0, 0.3, 0)), 0.6, 3.6, rgb(48, 50, 54), M.Metal, GHOST)
		block(foundry, "SoulFire", Vector3.new(1.4, 5, 1.4), CFrame.new(p + Vector3.new(0, 3.1, 0)), rgb(92, 152, 255), M.Neon, { Transparency = 0.35, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	end
	return sets
end

-- A low rail round the floor with a 10 stud opening in the middle of each side
local function rail(ctx: Common.Context, centre: Vector3)
	local model = ctx.model
	local half = ARENA_SIZE / 2 - 0.8
	local segment = (ARENA_SIZE - 1.6 - 10) / 2
	for side = 0, 3 do
		local turn = CFrame.Angles(0, math.rad(side * 90), 0)
		for _, sign_ in { -1, 1 } do
			local middle = sign_ * (5 + segment / 2)
			local frame = CFrame.new(centre) * turn
			block(model, "RailBar", Vector3.new(segment, 0.5, 0.4), frame * CFrame.new(middle, 2.8, half), STEEL, M.Metal, SMALL)
			for _, offset in { -segment / 2, 0, segment / 2 } do
				block(model, "RailPost", Vector3.new(0.6, 3.2, 0.6), frame * CFrame.new(middle + offset, 1.6, half), STEEL, M.Metal, SMALL)
			end
		end
	end
end

-- Cover and height: two low walls, two pillars, a central dais and two raised platforms with ramps
local function cover(ctx: Common.Context, centre: Vector3)
	local model = ctx.model
	local function wallBlock(x: number, z: number, yaw: number)
		block(model, "CoverWall", Vector3.new(8, 3.6, 1.6), CFrame.new(centre + Vector3.new(x, 1.8, z)) * CFrame.Angles(0, yaw, 0), rgb(120, 118, 114), M.Concrete, SMALL)
	end
	wallBlock(-15, 8, 0)
	wallBlock(15, -8, 0)
	for _, spot in { Vector3.new(-26, 0, 14), Vector3.new(26, 0, -14) } do
		cylinder(model, "Pillar", CFrame.new(centre + spot + Vector3.new(0, 4, 0)), 8, 3.6, rgb(150, 146, 138), M.Concrete, SMALL)
		cylinder(model, "PillarBand", CFrame.new(centre + spot + Vector3.new(0, 7.2, 0)), 0.4, 3.9, BRASS, M.Metal, GHOST)
	end
	-- Low dais in the middle: a 0.8 stud step, easy to walk up
	cylinder(model, "Dais", CFrame.new(centre + Vector3.new(0, 0.7, 0)), 0.8, 16, rgb(64, 66, 70), M.Slate)
	-- Raised platforms (3.2 studs) with a ramp on the side facing the middle
	local function platform(x: number, z: number, rampDirection: number)
		block(model, "RaisedPlatform", Vector3.new(12, 3.2, 12), CFrame.new(centre + Vector3.new(x, 1.6, z)), rgb(78, 80, 84), M.Concrete)
		block(model, "RaisedTrim", Vector3.new(12.4, 0.3, 12.4), CFrame.new(centre + Vector3.new(x, 3.35, z)), rgb(150, 150, 148), M.Metal, GHOST)
		local rampAt = centre + Vector3.new(x + rampDirection * 12.5, 1.6, z)
		Common.wedge(model, "Ramp", Vector3.new(8, 3.2, 13), Common.lookAt(rampAt, rampAt + Vector3.new(rampDirection, 0, 0)), rgb(78, 80, 84), M.Concrete)
	end
	platform(-28, -4, 1)
	platform(28, 4, -1)
end

local function sparFloor(ctx: Common.Context, index: number): SparFloor
	local model = ctx.model
	local local_ = ARENA_CENTERS[index]
	local centre = at(ctx, local_.X, 0, local_.Z)
	local size = ARENA_SIZE
	-- A 72 x 72 stage: a floor plate over the studio floor, a steel kerb, accent inlays
	local floor = block(model, "SparFloor", Vector3.new(size, 0.3, size), CFrame.new(centre + Vector3.new(0, 0.15, 0)), rgb(78, 82, 90), M.DiamondPlate)
	block(model, "SparKerb", Vector3.new(size + 3.2, 0.2, size + 3.2), CFrame.new(centre + Vector3.new(0, 0.1, 0)), STEEL, M.Metal, SMALL)
	local accents = {}
	local ringInlay = cylinder(model, "SparRing", CFrame.new(centre + Vector3.new(0, 0.33, 0)), 0.05, 18, CYAN, M.Neon, { CastShadow = false, CanCollide = false, Transparency = 0.7 })
	table.insert(accents, ringInlay)
	for side = 0, 3 do
		local frame = CFrame.new(centre) * CFrame.Angles(0, math.rad(side * 90), 0)
		local strip = block(model, "SparInlay", Vector3.new(size - 8, 0.05, 0.3), frame * CFrame.new(0, 0.33, size / 2 - 3), CYAN, M.Neon, { CastShadow = false, CanCollide = false, Transparency = 0.7 })
		table.insert(accents, strip)
	end
	rail(ctx, centre)
	cover(ctx, centre)

	-- Plaque on the south rail (clear of the opening): arena number and theme, readable from the aisle
	local plaqueAt = centre + Vector3.new(-20, 0, size / 2 - 0.8)
	local plaque = block(model, "SparBackdrop", Vector3.new(18, 5.6, 0.5), CFrame.new(plaqueAt + Vector3.new(0, 6.4, 0)), NAVY, M.SmoothPlastic, SMALL)
	for _, side in { -1, 1 } do
		block(model, "PlaquePost", Vector3.new(0.8, 6.8, 0.8), CFrame.new(plaqueAt + Vector3.new(side * 8, 3.4, 0)), WALNUT, M.WoodPlanks, SMALL)
	end
	block(model, "PlaqueTrim", Vector3.new(18.6, 0.4, 0.7), CFrame.new(plaqueAt + Vector3.new(0, 9.4, 0)), BRASS, M.Metal, GHOST)
	local plaqueGui = gui(plaque, Enum.NormalId.Back, 40)
	label(plaqueGui, { Name = "ArenaName", Text = `ARENA {index}`, Position = UDim2.fromScale(0.04, 0.05), Size = UDim2.fromScale(0.92, 0.5), Color = WARM, Font = font(SANS, Enum.FontWeight.ExtraBold) })
	local themeLabel = label(plaqueGui, { Name = "ThemeName", Text = "STUDIO", Position = UDim2.fromScale(0.04, 0.58), Size = UDim2.fromScale(0.92, 0.34), Color = CYAN })
	-- A warm key light over the floor
	local lamp = block(model, "SparLamp", Vector3.new(12, 0.4, 12), CFrame.new(centre + Vector3.new(0, HEIGHT - 1.8, 0)), WARM, M.Neon, GHOST)
	local spot = Common.spotLight(lamp, Enum.NormalId.Bottom, WARM, 60, 2.2, 90, false)
	local props = themeProps(centre)
	local current = "Studio"

	local function setTheme(id: string)
		local theme = Practice.Themes[id] or Practice.Themes.Studio
		current = if Practice.Themes[id] then id else "Studio"
		floor.Color = theme.floor
		floor.Material = theme.material
		for _, accent in accents do
			accent.Color = theme.accent
		end
		spot.Color = theme.light
		themeLabel.Text = string.upper(theme.name)
		themeLabel.TextColor3 = theme.accent
		for themeId, group in props do
			group.Parent = if themeId == current then model else nil
		end
		floor:SetAttribute("Theme", current)
	end
	setTheme("Studio")

	return {
		index = index,
		center = centre,
		size = size,
		player = Common.lookAt(centre + Vector3.new(0, 4, 20), centre + Vector3.new(0, 4, 0)),
		jeffery = Common.lookAt(centre + Vector3.new(0, 4, -20), centre + Vector3.new(0, 4, 0)),
		setTheme = setTheme,
		theme = function()
			return current
		end,
	}
end

-- Platform and console ----------------------------------------------------------------------------------

local function platform(ctx: Common.Context): (CFrame, BasePart, Model)
	local model = ctx.model
	local Jeffery = require(script.Parent.Parent.World.Jeffery)
	local base = at(ctx, -30, 0, PLAZA_Z)
	cylinder(model, "PlatformBase", CFrame.new(base + Vector3.new(0, 0.3, 0)), 0.6, 12, GRAPHITE, M.Metal)
	cylinder(model, "PlatformRing", CFrame.new(base + Vector3.new(0, 0.63, 0)), 0.05, 11.2, AMBER, M.Neon, { CastShadow = false, CanCollide = false, Transparency = 0.25 })
	cylinder(model, "PlatformTop", CFrame.new(base + Vector3.new(0, 0.62, 0)), 0.04, 10.4, CHARCOAL, M.DiamondPlate, GHOST)
	local look = Jeffery.model()
	look.Name = "JefferyPractice"
	-- Jeffery faces north (the bays), his hover disc resting on the platform
	look:PivotTo(CFrame.new(base + Vector3.new(0, 0.7 + 0.2, 0)) * CFrame.new(0, 1.4, 0))
	look.Parent = model
	local torso = look:FindFirstChild("Torso")
	if torso then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = "JEFFERY"
		prompt.ActionText = "Practice fights"
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.T
		prompt.GamepadKeyCode = Enum.KeyCode.DPadRight
		prompt:SetAttribute("Action", "Window:Practice")
		prompt.Parent = torso
	end
	local platformPlate = block(model, "PlatformPlate", Vector3.new(10, 0.08, 2.6), CFrame.new(base + Vector3.new(0, 0.66, 4.6)) * CFrame.Angles(0, math.pi, 0), NAVY, M.SmoothPlastic, GHOST)
	local plateGui = gui(platformPlate, Enum.NormalId.Top, 40)
	label(plateGui, { Name = "Text", Text = "JEFFERY PRACTICE PLATFORM", Position = UDim2.fromScale(0.04, 0.08), Size = UDim2.fromScale(0.92, 0.84), Color = WARM, Font = font(SANS, Enum.FontWeight.ExtraBold) })

	-- The console: a walnut desk with a sloped screen, on the plaza's north side
	local desk = at(ctx, 30, 0, PLAZA_Z - 8)
	block(model, "ConsoleBase", Vector3.new(10, 2.6, 3), CFrame.new(desk + Vector3.new(0, 1.3, 0)), WALNUT, M.WoodPlanks)
	block(model, "ConsoleTrim", Vector3.new(10.2, 0.15, 3.2), CFrame.new(desk + Vector3.new(0, 2.65, 0)), BRASS, M.Metal, GHOST)
	local screen = block(model, "ConsoleScreen", Vector3.new(9, 3.8, 0.25), CFrame.new(desk + Vector3.new(0, 4.3, 0.2)) * CFrame.Angles(math.rad(-35), math.rad(180), 0), NAVY, M.SmoothPlastic, SMALL)
	local screenGui = gui(screen, Enum.NormalId.Front, 50)
	label(screenGui, { Name = "Title", Text = "PRACTICE WITH JEFFERY", Position = UDim2.fromScale(0.04, 0.06), Size = UDim2.fromScale(0.92, 0.42), Color = WARM, Font = font(SANS, Enum.FontWeight.ExtraBold) })
	label(screenGui, { Name = "Modes", Text = "Beginner   Intermediate   Advanced   Custom", Position = UDim2.fromScale(0.04, 0.54), Size = UDim2.fromScale(0.92, 0.34), Color = rgb(222, 228, 236) })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "PRACTICE CONSOLE"
	prompt.ActionText = "Start a practice fight"
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.T
	prompt.GamepadKeyCode = Enum.KeyCode.DPadRight
	prompt:SetAttribute("Action", "Window:Practice")
	prompt.Parent = screen
	return CFrame.new(base), screen, look
end

local function throwables(ctx: Common.Context)
	-- A service corner by the first bay's east side: things Strong Dude can lift and throw
	Common.throwable(ctx, "Crate", 1, Vector3.new(3, 3, 3), CFrame.new(at(ctx, 78, 1.5, -88)) * CFrame.Angles(0, 0.3, 0), vary(GRAPHITE, ctx.random, 0.05), M.Metal)
	Common.uprightThrowable(ctx, "Barrel", 1, at(ctx, 80, 0, -96), 3.2, 2.4, 0, vary(COPPER, ctx.random, 0.04), M.Metal)
	Common.throwable(ctx, "Boulder", 2, Vector3.new(4.4, 3.6, 4), CFrame.new(at(ctx, 79, 1.8, -105)) * CFrame.Angles(0.04, 0.6, -0.03), vary(rgb(120, 118, 114), ctx.random, 0.05), M.Concrete)
end

-- Builds the studio around `center` (its floor's middle at ground level). Returns the model, the
-- bay dummy spots (one per bay) and the layout (readout labels, practice arenas, platform).
function TrainingHall.build(center: Vector3): (Model, { CFrame }, Layout)
	local ctx = Common.context("TrainingGround", center - Vector3.new(0, 0.5, 0), 4211)
	shell(ctx)
	local bayList = bays(ctx)
	local floors = {}
	for index = 1, #ARENA_CENTERS do
		floors[index] = sparFloor(ctx, index)
	end
	local platformFrame, console, jeffery = platform(ctx)
	throwables(ctx)
	local spots = {}
	for _, bay in bayList do
		table.insert(spots, bay.spot)
	end
	return ctx.model, spots, { bays = bayList, floors = floors, platform = platformFrame, console = console, jeffery = jeffery }
end

TrainingHall.Names = BAY_NAMES
TrainingHall.HalfX = HX
TrainingHall.HalfZ = HZ
TrainingHall.Half = HX
TrainingHall.ArenaSize = ARENA_SIZE
TrainingHall.PartBudget = 900
-- Where arrivals from the hub stand: just inside the entrance, looking into the plaza
TrainingHall.EntranceOffset = Vector3.new(HX - 12, 4, PLAZA_Z)

return TrainingHall
