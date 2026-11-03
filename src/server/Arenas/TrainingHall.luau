-- The Training Studio: an enclosed training facility room (ArtDirection sections 3, 4, 6).
-- Training reads as "clean cool white": ceramic cladding over a navy wainscot, brushed-steel
-- ribs, DiamondPlate service floor, a coffered ceiling with light panels, cyan wayfinding
-- inlays (the training colour, used sparingly).
--
--   north side   five practice bays: a characterful dummy (DummyService) on a round target pad,
--                glass dividers, and a readout screen on the wall (last hit, combo, DPS over 5 s)
--   south side   two sparring floors, each with a theme (Config/Practice Themes) that changes its
--                floor, backdrop, light and props, for Jeffery's practice fights (PracticeService)
--   middle       Jeffery's platform and the practice console (both open Window:Practice)
--   east wall    the entrance from the hub, with the room sign
--
-- The room is 56 x 56 studs inside, which keeps it inside Selection.TrainingZone (so every power
-- and phase is a free trial here). Built from parts only; no asset ids.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.Common)
local Practice = require(ReplicatedStorage.Shared.Config.Practice)

local TrainingHall = {}

local M = Common.M
local rgb = Common.rgb
local block, cylinder, disc = Common.block, Common.cylinder, Common.disc
local vary = Common.vary
local SMALL, GHOST = Common.SMALL, Common.GHOST

local NAVY = rgb(14, 22, 36)
local CHARCOAL = rgb(30, 33, 38)
local GRAPHITE = rgb(35, 39, 46)
local STEEL = rgb(138, 146, 156)
local CERAMIC = rgb(230, 232, 234)
local COOL = rgb(232, 238, 244)
local AMBER = rgb(232, 162, 74)
local CYAN = rgb(63, 214, 232)
local COPPER = rgb(184, 115, 63)
local RED = rgb(206, 72, 58)

local HALF = 28 -- half the room inside, X and Z
local HEIGHT = 22
local BAY_X = { -20, -10, 0, 10, 20 }
local BAY_Z = -21 -- dummy pad centre
local BAY_NAMES = { "PUNCHING BAG", "GUARD DUMMY", "SPARRING DUMMY", "PUNCHING BAG", "GUARD DUMMY" }
local FLOOR_CENTERS = { Vector3.new(-16, 0, 14), Vector3.new(16, 0, 14) }
local FLOOR_RADIUS = 10

export type Bay = { labels: { last: TextLabel, combo: TextLabel, dps: TextLabel, note: TextLabel }, spot: CFrame, name: string }
export type SparFloor = { index: number, center: Vector3, player: CFrame, jeffery: CFrame, setTheme: (string) -> (), theme: () -> string }
export type Layout = { bays: { Bay }, floors: { SparFloor }, platform: CFrame, console: BasePart, jeffery: Model }

local function at(ctx: Common.Context, x: number, y: number, z: number): Vector3
	return ctx.top + Vector3.new(x, y, z)
end

-- Screens ---------------------------------------------------------------------------------------

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", props.Weight or Enum.FontWeight.Bold)
	text.TextColor3 = props.Color or COOL
	text.Text = props.Text or ""
	text.Position = props.Position
	text.Size = props.Size
	text.TextXAlignment = props.Align or Enum.TextXAlignment.Center
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = props.Max or 60
	limit.Parent = text
	text.Name = props.Name or "Text"
	text.Parent = parent
	return text
end

-- The readout screen of one bay: three numbers and a note line
local function readoutScreen(ctx: Common.Context, x: number, name: string): { last: TextLabel, combo: TextLabel, dps: TextLabel, note: TextLabel }
	local screen = block(ctx.model, "Readout", Vector3.new(8, 4.6, 0.3), CFrame.new(at(ctx, x, 12.5, -HALF + 0.35)), NAVY, M.SmoothPlastic, SMALL)
	block(ctx.model, "ReadoutFrame", Vector3.new(8.5, 5.1, 0.2), CFrame.new(at(ctx, x, 12.5, -HALF + 0.2)), STEEL, M.Metal, SMALL)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ReadoutGui"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = screen
	label(gui, { Name = "Title", Text = name, Position = UDim2.fromScale(0.04, 0.04), Size = UDim2.fromScale(0.92, 0.16), Color = CYAN, Max = 26 })
	local made = {}
	local columns = { { "last", "LAST HIT" }, { "combo", "COMBO" }, { "dps", "DPS (5 S)" } }
	for index, column in columns do
		local left = 0.04 + (index - 1) * 0.32
		label(gui, { Name = column[1] .. "Name", Text = column[2], Position = UDim2.fromScale(left, 0.24), Size = UDim2.fromScale(0.3, 0.12), Color = STEEL, Max = 20 })
		made[column[1]] = label(gui, { Name = column[1], Text = if column[1] == "combo" then "0" elseif column[1] == "dps" then "0.0" else "-", Position = UDim2.fromScale(left, 0.36), Size = UDim2.fromScale(0.3, 0.34), Color = if column[1] == "dps" then AMBER else COOL, Max = 64 })
	end
	made.note = label(gui, { Name = "note", Text = "Hit the dummy to start", Position = UDim2.fromScale(0.04, 0.76), Size = UDim2.fromScale(0.92, 0.14), Color = STEEL, Max = 20, Weight = Enum.FontWeight.Medium })
	return made
end

-- Shell -----------------------------------------------------------------------------------------

local function shell(ctx: Common.Context)
	local model, random = ctx.model, ctx.random
	-- Floor: DiamondPlate service floor, a slate walkway down the middle, cyan inlays
	block(model, "Floor", Vector3.new(HALF * 2 + 2.4, 1.6, HALF * 2 + 2.4), CFrame.new(at(ctx, 0, -0.8, 0)), CHARCOAL, M.DiamondPlate)
	block(model, "Walkway", Vector3.new(HALF * 2 - 2, 0.1, 9), CFrame.new(at(ctx, 0, 0.05, -3.5)), GRAPHITE, M.Slate, GHOST)
	block(model, "FiringLine", Vector3.new(HALF * 2 - 6, 0.06, 0.35), CFrame.new(at(ctx, 0, 0.1, -11.4)), CYAN, M.Neon, GHOST)
	block(model, "SafetyEdgeN", Vector3.new(HALF * 2, 0.06, 0.5), CFrame.new(at(ctx, 0, 0.08, -HALF + 0.9)), AMBER, M.SmoothPlastic, GHOST)
	block(model, "SafetyEdgeS", Vector3.new(HALF * 2, 0.06, 0.5), CFrame.new(at(ctx, 0, 0.08, HALF - 0.9)), AMBER, M.SmoothPlastic, GHOST)
	for index = -3, 3 do
		block(model, "Seam", Vector3.new(0.15, 0.04, 9), CFrame.new(at(ctx, index * 8, 0.11, -3.5)), rgb(12, 13, 16), M.SmoothPlastic, GHOST)
	end

	-- Walls: navy wainscot, ceramic cladding above, steel ribs, a cyan reveal at the join
	local function wall(name: string, size: Vector3, centre: Vector3)
		block(model, name .. "Base", Vector3.new(size.X, 3.4, size.Z), CFrame.new(centre + Vector3.new(0, 1.7, 0)), NAVY, M.Slate)
		block(model, name, Vector3.new(size.X, HEIGHT - 3.4, size.Z), CFrame.new(centre + Vector3.new(0, 3.4 + (HEIGHT - 3.4) / 2, 0)), CERAMIC, M.SmoothPlastic)
	end
	wall("WallN", Vector3.new(HALF * 2 + 2.4, 0, 1.2), at(ctx, 0, 0, -HALF - 0.6))
	wall("WallS", Vector3.new(HALF * 2 + 2.4, 0, 1.2), at(ctx, 0, 0, HALF + 0.6))
	wall("WallW", Vector3.new(1.2, 0, HALF * 2), at(ctx, -HALF - 0.6, 0, 0))
	-- East wall with the entrance: two leaves and a lintel over a 12 stud opening
	for _, side in { -1, 1 } do
		local length = HALF - 6
		wall("WallE" .. (if side < 0 then "A" else "B"), Vector3.new(1.2, 0, length), at(ctx, HALF + 0.6, 0, side * (6 + length / 2)))
	end
	block(model, "Lintel", Vector3.new(1.2, HEIGHT - 11, 12), CFrame.new(at(ctx, HALF + 0.6, 11 + (HEIGHT - 11) / 2, 0)), CERAMIC, M.SmoothPlastic)
	-- Portal frame, lit with a thin training-cyan strip
	for _, side in { -1, 1 } do
		block(model, "PortalPost", Vector3.new(1.8, 11, 0.9), CFrame.new(at(ctx, HALF - 0.1, 5.5, side * 6.3)), STEEL, M.Metal, SMALL)
		block(model, "PortalStrip", Vector3.new(0.12, 10.4, 0.12), CFrame.new(at(ctx, HALF - 0.7, 5.5, side * 5.7)), CYAN, M.Neon, GHOST)
	end
	block(model, "PortalBeam", Vector3.new(1.8, 0.9, 13.8), CFrame.new(at(ctx, HALF - 0.1, 11.2, 0)), STEEL, M.Metal, SMALL)
	block(model, "PortalStripTop", Vector3.new(0.12, 0.12, 11.4), CFrame.new(at(ctx, HALF - 0.7, 10.6, 0)), CYAN, M.Neon, GHOST)
	local sign = block(model, "RoomSign", Vector3.new(14, 2.6, 0.3), CFrame.lookAt(at(ctx, HALF - 0.9, 15.8, 0), at(ctx, 0, 15.8, 0)), NAVY, M.SmoothPlastic, SMALL)
	Common.sign(sign, Enum.NormalId.Front, "TRAINING STUDIO", COOL, 28, 0)
	local sub = block(model, "RoomSubtitle", Vector3.new(14, 1.1, 0.3), CFrame.lookAt(at(ctx, HALF - 0.9, 13.6, 0), at(ctx, 0, 13.6, 0)), NAVY, M.SmoothPlastic, SMALL)
	Common.sign(sub, Enum.NormalId.Front, "Practice bays, sparring floors, Jeffery", STEEL, 30, 0, Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium))

	-- Ribs along the walls and the coffered ceiling
	for _, x in { -21, -7, 7, 21 } do
		block(model, "RibN", Vector3.new(1.1, HEIGHT - 3, 0.7), CFrame.new(at(ctx, x, 3 + (HEIGHT - 3) / 2, -HALF + 0.35)), STEEL, M.Metal, SMALL)
		block(model, "RibS", Vector3.new(1.1, HEIGHT - 3, 0.7), CFrame.new(at(ctx, x, 3 + (HEIGHT - 3) / 2, HALF - 0.35)), STEEL, M.Metal, SMALL)
	end
	block(model, "Ceiling", Vector3.new(HALF * 2 + 2.4, 1, HALF * 2 + 2.4), CFrame.new(at(ctx, 0, HEIGHT + 0.5, 0)), GRAPHITE, M.Metal)
	for _, x in { -18, -6, 6, 18 } do
		block(model, "CeilingBeamZ", Vector3.new(1.4, 1.6, HALF * 2), CFrame.new(at(ctx, x, HEIGHT - 0.8, 0)), STEEL, M.Metal, SMALL)
	end
	for _, z in { -18, 0, 18 } do
		block(model, "CeilingBeamX", Vector3.new(HALF * 2, 1.2, 1.4), CFrame.new(at(ctx, 0, HEIGHT - 0.6, z)), STEEL, M.Metal, SMALL)
	end
	-- Light panels in the coffers, with a few real lights (clean cool white)
	local lamps = 0
	for _, x in { -12, 0, 12 } do
		for _, z in { -24, -9, 6, 21 } do
			local panel = block(model, "LightPanel", Vector3.new(6, 0.2, 3), CFrame.new(at(ctx, x, HEIGHT - 0.1, z)), COOL, M.Neon, GHOST)
			lamps += 1
			if (lamps % 2 == 1) then
				Common.surfaceLight(panel, Enum.NormalId.Bottom, COOL, 34, 0.9, 120)
			end
		end
	end
	-- A conduit channel and a wall terminal for dressing (ArtDirection: no decoration without a reason)
	block(model, "Conduit", Vector3.new(0.4, 0.4, HALF * 2 - 2), CFrame.new(at(ctx, -HALF + 0.6, 6, 0)), STEEL, M.Metal, SMALL)
	local terminal = block(model, "StatusTerminal", Vector3.new(0.4, 3, 5), CFrame.lookAt(at(ctx, -HALF + 0.5, 5.5, 4), at(ctx, 0, 5.5, 4)), NAVY, M.SmoothPlastic, SMALL)
	Common.sign(terminal, Enum.NormalId.Front, "ALL POWERS FREE HERE\nNOTHING IS AT STAKE", CYAN, 22, 0)
	local _ = random
end

-- Practice bays ---------------------------------------------------------------------------------

local function bays(ctx: Common.Context): { Bay }
	local model = ctx.model
	local made = {}
	for index, x in BAY_X do
		-- The round target pad: a low drum, a cyan ring, a white inner ring and an amber centre
		cylinder(model, "PadBase", CFrame.new(at(ctx, x, 0.2, BAY_Z)), 0.4, 7, GRAPHITE, M.Metal, SMALL)
		cylinder(model, "PadRing", CFrame.new(at(ctx, x, 0.43, BAY_Z)), 0.06, 6.4, CYAN, M.Neon, GHOST)
		cylinder(model, "PadPlate", CFrame.new(at(ctx, x, 0.46, BAY_Z)), 0.06, 5.6, CHARCOAL, M.DiamondPlate, GHOST)
		cylinder(model, "PadInner", CFrame.new(at(ctx, x, 0.5, BAY_Z)), 0.06, 3.2, COOL, M.SmoothPlastic, GHOST)
		cylinder(model, "PadCentre", CFrame.new(at(ctx, x, 0.54, BAY_Z)), 0.06, 1.2, AMBER, M.SmoothPlastic, GHOST)
		-- Floor bay plate and wall name plate
		local plate = block(model, "BayPlate", Vector3.new(5, 0.08, 1.4), CFrame.new(at(ctx, x, 0.1, -9.6)), NAVY, M.SmoothPlastic, GHOST)
		Common.sign(plate, Enum.NormalId.Top, `BAY {index}`, COOL, 40, 0)
		local name = block(model, "BayName", Vector3.new(6, 0.9, 0.2), CFrame.new(at(ctx, x, 8.6, -HALF + 0.3)), CHARCOAL, M.SmoothPlastic, SMALL)
		local gui = Common.sign(name, Enum.NormalId.Back, BAY_NAMES[index], STEEL, 40, 0)
		gui.Name = "BayNameSign"
		local labels = readoutScreen(ctx, x, `BAY {index}   {BAY_NAMES[index]}`)
		table.insert(made, {
			labels = labels,
			spot = Common.lookAt(at(ctx, x, 3, BAY_Z), at(ctx, x, 3, BAY_Z + 1)),
			name = BAY_NAMES[index],
		})
	end
	-- Dividers: a steel post and a glass panel between neighbouring bays (never a flat clear sheet)
	for index = 0, #BAY_X do
		local x = -25 + index * 10
		block(model, "DividerPost", Vector3.new(0.8, 10, 0.8), CFrame.new(at(ctx, x, 5, -14.4)), STEEL, M.Metal, SMALL)
		if index > 0 and index < #BAY_X then
			block(model, "DividerGlass", Vector3.new(0.2, 8, 12.6), CFrame.new(at(ctx, x, 5.6, -20.6)), rgb(150, 190, 210), M.Glass, { Transparency = 0.7, Reflectance = 0.15, CastShadow = false })
			block(model, "DividerRail", Vector3.new(0.5, 0.3, 13), CFrame.new(at(ctx, x, 9.7, -20.5)), STEEL, M.Metal, SMALL)
			block(model, "DividerFoot", Vector3.new(0.5, 0.3, 13), CFrame.new(at(ctx, x, 1.6, -20.5)), STEEL, M.Metal, SMALL)
		end
	end
	return made
end

-- Sparring floors -----------------------------------------------------------------------------------

-- Theme props: small, no collision, only the active theme's set is in the world
local function themeProps(ctx: Common.Context, centre: Vector3): { [string]: Model }
	local sets = {}
	local function set(id: string): Model
		local group = Instance.new("Model")
		group.Name = "Theme_" .. id
		sets[id] = group
		return group
	end
	local r = FLOOR_RADIUS - 0.8
	local function onRing(angle: number, y: number): Vector3
		return centre + Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r)
	end

	-- Studio: four steel marker posts with cyan caps
	local studio = set("Studio")
	for k = 0, 3 do
		local p = onRing(math.rad(45 + k * 90), 0)
		block(studio, "Marker", Vector3.new(0.7, 1.6, 0.7), CFrame.new(p + Vector3.new(0, 0.8, 0)), STEEL, M.Metal, GHOST)
		block(studio, "MarkerCap", Vector3.new(0.5, 0.15, 0.5), CFrame.new(p + Vector3.new(0, 1.65, 0)), CYAN, M.Neon, GHOST)
	end
	-- Proving Grounds: weathered pillars with a rune glow
	local proving = set("ProvingGrounds")
	for k = 0, 3 do
		local p = onRing(math.rad(k * 90 + 20), 0)
		cylinder(proving, "Pillar", CFrame.new(p + Vector3.new(0, 2.2, 0)), 4.4, 1.6, rgb(150, 145, 134), M.Slate, GHOST)
		block(proving, "Rune", Vector3.new(0.9, 0.9, 0.12), CFrame.lookAt(p + Vector3.new(0, 2.6, 0), centre + Vector3.new(0, 2.6, 0)), rgb(120, 222, 236), M.Neon, GHOST)
	end
	-- Ruined Fortress: broken wall blocks and a brazier
	local fortress = set("RuinedFortress")
	for k = 0, 2 do
		local p = onRing(math.rad(k * 120 + 10), 0)
		block(fortress, "Rubble", Vector3.new(2.6, 1.8 + k * 0.5, 1.6), CFrame.new(p + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, k, 0), rgb(120, 112, 102), M.Cobblestone, GHOST)
	end
	local brazierAt = onRing(math.rad(200), 0)
	cylinder(fortress, "Brazier", CFrame.new(brazierAt + Vector3.new(0, 1.2, 0)), 2.4, 1.4, rgb(56, 54, 52), M.Metal, GHOST)
	local flame = block(fortress, "Flame", Vector3.new(0.9, 0.9, 0.9), CFrame.new(brazierAt + Vector3.new(0, 2.7, 0)), rgb(255, 160, 80), M.Neon, GHOST)
	Common.light(flame, rgb(255, 170, 100), 18, 1.2, false)
	-- Digital Grid: floating data cubes
	local grid = set("DigitalGrid")
	for k = 0, 3 do
		local p = onRing(math.rad(k * 90 + 40), 3 + (k % 2) * 1.5)
		block(grid, "DataCube", Vector3.new(1.4, 1.4, 1.4), CFrame.new(p) * CFrame.Angles(0.5, k, 0.3), rgb(70, 220, 230), M.Glass, { Transparency = 0.35, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		block(grid, "DataCore", Vector3.new(0.5, 0.5, 0.5), CFrame.new(p) * CFrame.Angles(0.5, k, 0.3), rgb(210, 250, 255), M.Neon, GHOST)
	end
	-- Corrupted Wastes: crystal shards
	local wastes = set("CorruptedWastes")
	for k = 0, 4 do
		local p = onRing(math.rad(k * 72 + 15), 0)
		block(wastes, "Shard", Vector3.new(0.9, 3.4 + (k % 2) * 1.4, 0.9), CFrame.new(p + Vector3.new(0, 1.8, 0)) * CFrame.Angles(0.12 * (k - 2), k, 0.18), rgb(152, 102, 222), M.Neon, GHOST)
	end
	-- Soul Foundry: vent grates and blue soul-fire columns
	local foundry = set("SoulFoundry")
	for k = 0, 2 do
		local p = onRing(math.rad(k * 120 + 30), 0)
		cylinder(foundry, "Vent", CFrame.new(p + Vector3.new(0, 0.3, 0)), 0.6, 2.4, rgb(48, 50, 54), M.Metal, GHOST)
		block(foundry, "SoulFire", Vector3.new(1, 3.4, 1), CFrame.new(p + Vector3.new(0, 2.3, 0)), rgb(92, 152, 255), M.Neon, { Transparency = 0.35, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	end
	local _ = ctx
	return sets
end

local function sparFloor(ctx: Common.Context, index: number): SparFloor
	local model = ctx.model
	local local_ = FLOOR_CENTERS[index]
	local centre = at(ctx, local_.X, 0, local_.Z)
	-- Rotating drum look: a raised disc, an accent ring and an outer steel kerb
	local floor = cylinder(model, "SparFloor", CFrame.new(centre + Vector3.new(0, 0.2, 0)), 0.4, FLOOR_RADIUS * 2, CHARCOAL, M.DiamondPlate)
	cylinder(model, "SparKerb", CFrame.new(centre + Vector3.new(0, 0.1, 0)), 0.2, FLOOR_RADIUS * 2 + 1.2, STEEL, M.Metal, SMALL)
	local ring = cylinder(model, "SparRing", CFrame.new(centre + Vector3.new(0, 0.42, 0)), 0.05, FLOOR_RADIUS * 2 - 0.8, CYAN, M.Neon, GHOST)
	cylinder(model, "SparInner", CFrame.new(centre + Vector3.new(0, 0.45, 0)), 0.05, FLOOR_RADIUS * 2 - 1.8, CHARCOAL, M.DiamondPlate, GHOST)
	-- Sides of the stage: a theme backdrop on the south wall, and a lamp over the floor
	local backdrop = block(model, "SparBackdrop", Vector3.new(22, 11, 0.3), CFrame.new(at(ctx, local_.X, 8.6, HALF - 0.45)), NAVY, M.SmoothPlastic, SMALL)
	local backGui = Common.sign(backdrop, Enum.NormalId.Front, "STUDIO", COOL, 14, 0)
	backGui.Face = Enum.NormalId.Front
	local lamp = block(model, "SparLamp", Vector3.new(4, 0.4, 4), CFrame.new(at(ctx, local_.X, HEIGHT - 1.8, local_.Z)), COOL, M.Neon, GHOST)
	local spot = Common.spotLight(lamp, Enum.NormalId.Bottom, COOL, 40, 1.4, 70, false)
	local props = themeProps(ctx, centre)
	local current = "Studio"

	local function setTheme(id: string)
		local theme = Practice.Themes[id] or Practice.Themes.Studio
		current = if Practice.Themes[id] then id else "Studio"
		floor.Color = theme.floor
		floor.Material = theme.material
		ring.Color = theme.accent
		backdrop.Color = theme.accent:Lerp(NAVY, 0.82)
		spot.Color = theme.light
		local gui = backdrop:FindFirstChildOfClass("SurfaceGui")
		local text = gui and gui:FindFirstChildOfClass("TextLabel")
		if text then
			text.Text = string.upper(theme.name)
			text.TextColor3 = theme.accent
		end
		for themeId, group in props do
			group.Parent = if themeId == current then model else nil
		end
		floor:SetAttribute("Theme", current)
	end
	setTheme("Studio")

	return {
		index = index,
		center = centre,
		player = Common.lookAt(centre + Vector3.new(0, 4, 6.5), centre + Vector3.new(0, 4, 0)),
		jeffery = Common.lookAt(centre + Vector3.new(0, 4, -5.5), centre + Vector3.new(0, 4, 0)),
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
	local base = at(ctx, 0, 0, 20)
	cylinder(model, "PlatformBase", CFrame.new(base + Vector3.new(0, 0.3, 0)), 0.6, 9, GRAPHITE, M.Metal)
	cylinder(model, "PlatformRing", CFrame.new(base + Vector3.new(0, 0.63, 0)), 0.05, 8.2, AMBER, M.Neon, GHOST)
	cylinder(model, "PlatformTop", CFrame.new(base + Vector3.new(0, 0.62, 0)), 0.04, 7.4, CHARCOAL, M.DiamondPlate, GHOST)
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
	local platformPlate = block(model, "PlatformPlate", Vector3.new(5, 0.08, 1.2), CFrame.new(base + Vector3.new(0, 0.66, 3.6)), NAVY, M.SmoothPlastic, GHOST)
	Common.sign(platformPlate, Enum.NormalId.Top, "JEFFERY PRACTICE PLATFORM", COOL, 30, 0)

	-- The console: a desk with a sloped screen, between the bays and the platform
	local desk = at(ctx, 0, 0, 7)
	block(model, "ConsoleBase", Vector3.new(7, 2.6, 2.6), CFrame.new(desk + Vector3.new(0, 1.3, 0)), GRAPHITE, M.Metal)
	block(model, "ConsoleTrim", Vector3.new(7.2, 0.12, 2.8), CFrame.new(desk + Vector3.new(0, 2.65, 0)), CYAN, M.Neon, GHOST)
	local screen = block(model, "ConsoleScreen", Vector3.new(6.4, 2.6, 0.25), CFrame.new(desk + Vector3.new(0, 3.5, 0.2)) * CFrame.Angles(math.rad(-35), math.rad(180), 0), NAVY, M.SmoothPlastic, SMALL)
	Common.sign(screen, Enum.NormalId.Front, "PRACTICE WITH JEFFERY\nBeginner  Intermediate\nAdvanced  Custom", COOL, 24, 0)
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
	-- A service corner by the entrance: things Strong Dude can lift and throw
	Common.throwable(ctx, "Crate", 1, Vector3.new(3, 3, 3), CFrame.new(at(ctx, 23, 1.5, -14)) * CFrame.Angles(0, 0.3, 0), vary(GRAPHITE, ctx.random, 0.05), M.Metal)
	Common.uprightThrowable(ctx, "Barrel", 1, at(ctx, 25, 0, -18), 3.2, 2.4, 0, vary(COPPER, ctx.random, 0.04), M.Metal)
	Common.throwable(ctx, "Boulder", 2, Vector3.new(4.4, 3.6, 4), CFrame.new(at(ctx, 24, 1.8, -23)) * CFrame.Angles(0.04, 0.6, -0.03), vary(rgb(120, 118, 114), ctx.random, 0.04), M.Concrete)
end

-- Builds the studio around `center` (its floor's middle at ground level). Returns the model, the
-- bay dummy spots (one per bay) and the layout (readout labels, sparring floors, platform).
function TrainingHall.build(center: Vector3): (Model, { CFrame }, Layout)
	local ctx = Common.context("TrainingGround", center - Vector3.new(0, 0.5, 0), 4211)
	shell(ctx)
	local bayList = bays(ctx)
	local floors = {}
	for index = 1, #FLOOR_CENTERS do
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
TrainingHall.Half = HALF

return TrainingHall
