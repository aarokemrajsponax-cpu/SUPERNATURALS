-- The battleground chamber shell. ArenaService builds one chamber per reserved slot:
-- a theme builder (ProvingGrounds, RuinedFortress, ...) lays the fighting floor, cover,
-- landmarks, throwables and spawns; this module then makes the room around it a sealed,
-- lit chamber (DECISIONS.md 8, MASTER_REQUIREMENTS.md 7, ArtDirection sections 3, 4, 6):
--   prune     drops any open-air scenery a builder put outside the walls or above the roof
--   walls     four solid walls 4 studs thick (inner face 12 studs beyond the floor edge, so the
--             theme's rim landmarks stand inside), pilasters, a
--             steel skirting, an accent light cove under the ceiling, a name plate
--   ceiling   a concrete slab at Arena.WallHeight with five ribs, four light panels (one
--             SurfaceLight each) and a perimeter cove: the chamber's only light besides
--             the theme's own braziers and crystals
--   ledges    two raised side platforms (6 studs) with two steps at each end, for elevation
--   gallery   on the +Z side a raised, glass-fronted spectator room: deck, side and back
--             walls, roof, two rows of seating, a spawn point and a "Return to concourse"
--             terminal with a ProximityPrompt (ArenaService wires Triggered)
-- All structure collides; decoration (pilasters, ribs, panels) never does, so it cannot
-- block a raycast or a fighter. Nothing here moves and nothing is scripted.
-- Part budget: shell about 110 parts; a whole chamber (theme + shell) stays within
-- ArenaService.Chambers.PartBudget (700). Nothing loops on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchConfig = require(ReplicatedStorage.Shared.Config.Match)
local Common = require(script.Parent.Common)

local Chamber = {}

local M = Common.M
local rgb = Common.rgb
local ARENA = MatchConfig.Arena

local WALL = 4 -- wall thickness
-- Walls stand this far beyond the fighting floor's edge: the ring holds the theme's rim
-- landmarks (bastions, wall runs, crystals) and the invisible barrier keeps fighters off it
local RIM = 12
local GALLERY_WIDTH = 30 -- half width of the gallery room and its window
local GALLERY_DEPTH = 18
local GALLERY_BASE = 14 -- the gallery deck sits this high above the fighting floor
local GALLERY_HEIGHT = 12

export type Style = {
	wall: Color3,
	wallMaterial: Enum.Material,
	trim: Color3,
	trimMaterial: Enum.Material,
	ceiling: Color3,
	accent: Color3,
	light: Color3,
}

-- One style per theme: the wall treatment keeps the theme's identity, the accent is the
-- theme colour from Config/Match.
Chamber.Styles = {
	ProvingGrounds = {
		wall = rgb(112, 112, 108), wallMaterial = M.Slate, trim = rgb(150, 145, 134), trimMaterial = M.Concrete,
		ceiling = rgb(84, 86, 90), accent = rgb(96, 188, 204), light = rgb(236, 238, 232),
	},
	RuinedFortress = {
		wall = rgb(150, 126, 98), wallMaterial = M.Brick, trim = rgb(96, 84, 72), trimMaterial = M.Cobblestone,
		ceiling = rgb(70, 60, 54), accent = rgb(214, 142, 76), light = rgb(255, 226, 190),
	},
	DigitalGrid = {
		wall = rgb(30, 38, 52), wallMaterial = M.Metal, trim = rgb(150, 162, 176), trimMaterial = M.SmoothPlastic,
		ceiling = rgb(24, 30, 42), accent = rgb(64, 214, 222), light = rgb(214, 244, 250),
	},
	CorruptedWastes = {
		wall = rgb(34, 28, 42), wallMaterial = M.Basalt, trim = rgb(64, 52, 78), trimMaterial = M.Slate,
		ceiling = rgb(24, 20, 30), accent = rgb(152, 102, 222), light = rgb(226, 210, 255),
	},
	SoulFoundry = {
		wall = rgb(58, 52, 50), wallMaterial = M.DiamondPlate, trim = rgb(110, 98, 90), trimMaterial = M.Metal,
		ceiling = rgb(40, 36, 36), accent = rgb(238, 120, 56), light = rgb(255, 226, 196),
	},
}

local DECOR = Common.GHOST

local function block(ctx: Common.Context, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	return Common.block(ctx.model, name, size, CFrame.new(position), color, material, extra)
end

-- Open-air scenery is not wanted inside a sealed room: drop parts that stand beyond the
-- walls or above the roof line, and anything sunk well under the floor.
function Chamber.prune(ctx: Common.Context)
	local outX, outZ = ctx.half.X + RIM + 1, ctx.half.Z + RIM + 1
	for _, item in ctx.model:GetDescendants() do
		if item:IsA("BasePart") and item.Name ~= "Floor" and item.Name ~= "Barrier" then
			local offset = item.CFrame.Position - ctx.top
			if math.abs(offset.X) > outX or math.abs(offset.Z) > outZ or offset.Y > ARENA.WallHeight - 1 or offset.Y < -8 then
				item:Destroy()
			end
		end
	end
end

local function shell(ctx: Common.Context, style: Style)
	local hx, hz, ft, c = ctx.half.X + RIM, ctx.half.Z + RIM, ctx.floorY, ctx.top
	local height = ARENA.WallHeight
	local function wall(name: string, size: Vector3, position: Vector3)
		block(ctx, name, size, position, style.wall, style.wallMaterial)
	end
	-- The ring between the fighting floor and the walls (the barrier keeps fighters off it)
	block(ctx, "RimFloor", Vector3.new(hx * 2, 4, hz * 2), c + Vector3.new(0, -2.06, 0), style.ceiling, M.Slate)
	-- East and west walls run the full depth including both corners
	for _, sign in { 1, -1 } do
		wall("ShellWall", Vector3.new(WALL, height + 4, hz * 2 + WALL * 2), c + Vector3.new(sign * (hx + WALL / 2), height / 2 - 2, 0))
	end
	-- North wall: solid
	wall("ShellWall", Vector3.new(hx * 2, height + 4, WALL), c + Vector3.new(0, height / 2 - 2, -(hz + WALL / 2)))
	-- South wall (the gallery side): a window opening between the gallery deck and roof
	local zWall = hz + WALL / 2
	local lowTop, highBottom = GALLERY_BASE, GALLERY_BASE + GALLERY_HEIGHT
	wall("ShellWall", Vector3.new(hx * 2, lowTop + 4, WALL), c + Vector3.new(0, (lowTop - 4) / 2, zWall))
	wall("ShellWall", Vector3.new(hx * 2, height - highBottom, WALL), c + Vector3.new(0, (highBottom + height) / 2, zWall))
	local sideWidth = hx - GALLERY_WIDTH
	for _, sign in { 1, -1 } do
		wall("ShellWall", Vector3.new(sideWidth, GALLERY_HEIGHT, WALL), c + Vector3.new(sign * (GALLERY_WIDTH + sideWidth / 2), lowTop + GALLERY_HEIGHT / 2, zWall))
	end

	-- Skirting: a brushed-steel band along the foot of every wall
	for _, sign in { 1, -1 } do
		block(ctx, "Skirting", Vector3.new(0.6, 1.6, hz * 2), c + Vector3.new(sign * (hx - 0.3), 0.8, 0), style.trim, style.trimMaterial, DECOR)
		block(ctx, "Skirting", Vector3.new(hx * 2, 1.6, 0.6), c + Vector3.new(0, 0.8, -(hz - 0.3)), style.trim, style.trimMaterial, DECOR)
	end
	block(ctx, "Skirting", Vector3.new(hx * 2, 1.6, 0.6), c + Vector3.new(0, 0.8, hz - 0.3), style.trim, style.trimMaterial, DECOR)

	-- Pilasters: structural rhythm on the inner faces (skipping the gallery window)
	for _, along in { -44, -22, 0, 22, 44 } do
		for _, sign in { 1, -1 } do
			block(ctx, "Pilaster", Vector3.new(1.4, height - 4, 3), c + Vector3.new(sign * (hx - 0.7), height / 2, along), style.trim, style.trimMaterial, DECOR)
		end
		block(ctx, "Pilaster", Vector3.new(3, height - 4, 1.4), c + Vector3.new(along, height / 2, -(hz - 0.7)), style.trim, style.trimMaterial, DECOR)
		if math.abs(along) > GALLERY_WIDTH then
			block(ctx, "Pilaster", Vector3.new(3, GALLERY_BASE - 2, 1.4), c + Vector3.new(along, (GALLERY_BASE - 2) / 2 + 1.6, hz - 0.7), style.trim, style.trimMaterial, DECOR)
		end
	end

	-- Ceiling slab, ribs, light panels and the cove under the roof edge
	block(ctx, "Ceiling", Vector3.new(hx * 2 + WALL * 2, 2, hz * 2 + WALL * 2), c + Vector3.new(0, height + 1, 0), style.ceiling, M.Concrete)
	for _, z in { -44, -22, 0, 22, 44 } do
		block(ctx, "Rib", Vector3.new(hx * 2, 1.8, 2.4), c + Vector3.new(0, height - 0.9, z), style.trim, style.trimMaterial, DECOR)
	end
	for _, z in { -33, -11, 11, 33 } do
		local panel = block(ctx, "LightPanel", Vector3.new(hx * 1.6, 0.3, 6), c + Vector3.new(0, height - 0.25, z), style.light, M.SmoothPlastic, DECOR)
		panel.Material = M.Neon
		panel.Color = style.light
		Common.surfaceLight(panel, Enum.NormalId.Bottom, style.light, 90, 0.7, 150)
	end
	local cove = style.accent
	block(ctx, "Cove", Vector3.new(hx * 2 - 1, 0.4, 0.3), c + Vector3.new(0, height - 2.2, -(hz - 0.5)), cove, M.Neon, DECOR)
	block(ctx, "Cove", Vector3.new(hx * 2 - 1, 0.4, 0.3), c + Vector3.new(0, height - 2.2, hz - 0.5), cove, M.Neon, DECOR)
	for _, sign in { 1, -1 } do
		block(ctx, "Cove", Vector3.new(0.3, 0.4, hz * 2 - 1), c + Vector3.new(sign * (hx - 0.5), height - 2.2, 0), cove, M.Neon, DECOR)
	end

	-- Name plate on the north wall, facing the room
	local plateAt = c + Vector3.new(0, 38, -(hz - 0.4))
	local plate = Common.block(ctx.model, "NamePlate", Vector3.new(34, 6, 0.5), CFrame.lookAt(plateAt, plateAt + Vector3.new(0, 0, 1)), rgb(20, 22, 26), M.SmoothPlastic, DECOR)
	Common.sign(plate, Enum.NormalId.Front, "", style.accent, 24, 0)
	return plate
end

-- Two raised side platforms with steps at both ends: elevation without cover that
-- blocks the middle. They stand clear of the corner spawns.
local function ledges(ctx: Common.Context, style: Style)
	local c = ctx.top
	for _, sign in { 1, -1 } do
		local x = sign * (ctx.half.X - 6)
		block(ctx, "Ledge", Vector3.new(10, 6, 40), c + Vector3.new(x, 3, 0), style.wall, style.wallMaterial)
		block(ctx, "LedgeInlay", Vector3.new(0.4, 0.2, 38), c + Vector3.new(x - sign * 4.6, 6.1, 0), style.accent, M.Neon, DECOR)
		for _, end_ in { 1, -1 } do
			block(ctx, "LedgeStep", Vector3.new(10, 4, 5), c + Vector3.new(x, 2, end_ * 22.5), style.wall, style.wallMaterial)
			block(ctx, "LedgeStep", Vector3.new(10, 2, 5), c + Vector3.new(x, 1, end_ * 27.5), style.wall, style.wallMaterial)
		end
	end
end

-- The spectator gallery behind the south window
local function gallery(ctx: Common.Context, style: Style, number: number): (CFrame, ProximityPrompt)
	local c, ft = ctx.top, ctx.floorY
	local z0 = ctx.half.Z + RIM + WALL -- the gallery's front edge (outer face of the window wall)
	local width = GALLERY_WIDTH
	local deckTop = ft + GALLERY_BASE
	local function at(x: number, y: number, z: number): Vector3
		return Vector3.new(c.X + x, y, c.Z + z0 + z)
	end
	local trim, trimMaterial = style.trim, style.trimMaterial

	-- Deck: a solid block from below the floor to the deck level
	local depthTotal = GALLERY_DEPTH + 2
	block(ctx, "GalleryDeck", Vector3.new(width * 2 + 4, deckTop - (ft - 4), depthTotal), at(0, (deckTop + ft - 4) / 2, depthTotal / 2), rgb(44, 46, 50), M.Slate)
	local carpet = block(ctx, "GalleryCarpet", Vector3.new(width * 2, 0.2, GALLERY_DEPTH), at(0, deckTop + 0.1, GALLERY_DEPTH / 2), rgb(34, 44, 62), M.Fabric, DECOR)
	carpet.CanCollide = false
	-- Side walls, back wall, roof
	for _, sign in { 1, -1 } do
		block(ctx, "GalleryWall", Vector3.new(2, GALLERY_HEIGHT, depthTotal), at(sign * (width + 1), deckTop + GALLERY_HEIGHT / 2, depthTotal / 2), style.wall, style.wallMaterial)
	end
	block(ctx, "GalleryWall", Vector3.new(width * 2 + 4, GALLERY_HEIGHT, 2), at(0, deckTop + GALLERY_HEIGHT / 2, GALLERY_DEPTH + 1), style.wall, style.wallMaterial)
	block(ctx, "GalleryRoof", Vector3.new(width * 2 + 4, 2, depthTotal + 1), at(0, deckTop + GALLERY_HEIGHT + 1, depthTotal / 2), style.ceiling, M.Concrete)

	-- The window: a pane with steel mullions, sill and header (the pane collides, so
	-- nothing flies through and nothing falls out)
	local glassAt = c + Vector3.new(0, deckTop + GALLERY_HEIGHT / 2 - c.Y, ctx.half.Z + RIM + WALL / 2)
	block(ctx, "GalleryGlass", Vector3.new(width * 2, GALLERY_HEIGHT, 0.5), glassAt, rgb(190, 214, 224), M.Glass, { Transparency = 0.78, Reflectance = 0.08, CastShadow = false })
	for step = -3, 3 do
		block(ctx, "Mullion", Vector3.new(0.8, GALLERY_HEIGHT, 1.2), glassAt + Vector3.new(step * (width / 3), 0, 0), trim, trimMaterial, DECOR)
	end
	block(ctx, "Sill", Vector3.new(width * 2 + 1, 0.7, 1.8), glassAt + Vector3.new(0, -GALLERY_HEIGHT / 2, 0), trim, trimMaterial, DECOR)
	block(ctx, "Header", Vector3.new(width * 2 + 1, 0.7, 1.8), glassAt + Vector3.new(0, GALLERY_HEIGHT / 2, 0), trim, trimMaterial, DECOR)

	-- Seating: a front bench and a raised back row, both facing the glass
	local function bench(row: string, y: number, z: number)
		for _, side in { -1, 1 } do
			block(ctx, row .. "Seat", Vector3.new(24, 1.4, 2.2), at(side * 14, y + 0.7, z), rgb(30, 42, 66), M.Fabric)
			block(ctx, row .. "Back", Vector3.new(24, 2.6, 0.5), at(side * 14, y + 2.1, z + 1.3), rgb(30, 42, 66), M.Fabric, DECOR)
		end
	end
	bench("Front", deckTop, 4.5)
	block(ctx, "Riser", Vector3.new(width * 2 - 4, 1.5, 6), at(0, deckTop + 0.75, 13), rgb(54, 56, 62), M.Slate)
	bench("Rear", deckTop + 1.5, 13)

	-- Light and signs
	local strip = block(ctx, "GalleryLight", Vector3.new(width * 1.4, 0.3, 3), at(0, deckTop + GALLERY_HEIGHT - 0.2, 9), style.light, M.Neon, DECOR)
	Common.surfaceLight(strip, Enum.NormalId.Bottom, rgb(255, 236, 206), 40, 0.8, 140)
	local nameAt = at(-18, deckTop + 8.5, GALLERY_DEPTH - 0.3)
	local name = Common.block(ctx.model, "GalleryPlate", Vector3.new(18, 3, 0.4), CFrame.lookAt(nameAt, nameAt + Vector3.new(0, 0, -1)), rgb(20, 22, 26), M.SmoothPlastic, DECOR)
	Common.sign(name, Enum.NormalId.Front, string.format("GALLERY %02d", number), style.accent, 24, 0)

	-- Return terminal
	local terminalAt = at(24, deckTop + 3.5, GALLERY_DEPTH - 0.6)
	local terminal = Common.block(ctx.model, "ReturnTerminal", Vector3.new(7, 4.4, 0.8), CFrame.lookAt(terminalAt, terminalAt + Vector3.new(0, 0, -1)), rgb(24, 28, 34), M.Metal, DECOR)
	Common.sign(terminal, Enum.NormalId.Front, "RETURN TO CONCOURSE", rgb(240, 236, 226), 24, 0)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ReturnPrompt"
	prompt.ActionText = "Return to concourse"
	prompt.ObjectText = string.format("Gallery %02d", number)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.T
	prompt.GamepadKeyCode = Enum.KeyCode.DPadRight
	prompt.Parent = terminal

	-- Spawn point between the benches, facing the floor
	local spawnAt = at(0, deckTop + 3, 8.5)
	Common.block(ctx.model, "GallerySpawn", Vector3.new(6, 1, 4), CFrame.new(spawnAt - Vector3.new(0, 2.5, 0)), rgb(30, 30, 30), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	return Common.lookAt(spawnAt, Vector3.new(c.X, spawnAt.Y, c.Z)), prompt
end

-- Builds the shell round a finished theme. Returns the gallery spawn and its return prompt.
function Chamber.build(ctx: Common.Context, theme: string, number: number, displayName: string): (CFrame, ProximityPrompt)
	local style = Chamber.Styles[theme] or Chamber.Styles.ProvingGrounds
	Chamber.prune(ctx)
	local plate = shell(ctx, style)
	local gui = plate:FindFirstChildOfClass("SurfaceGui")
	local label = gui and gui:FindFirstChildOfClass("TextLabel")
	if label then
		label.Text = string.format("CHAMBER %02d  %s", number, string.upper(displayName))
	end
	ledges(ctx, style)
	return gallery(ctx, style, number)
end

return Chamber
