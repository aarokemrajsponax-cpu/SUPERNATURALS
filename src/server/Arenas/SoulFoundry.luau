-- Soul Foundry: the casting floor of a foundry that burns souls for power.
-- Diamond-plate decking with a few rusted plates, a cooling grate in the
-- middle, vents of blue soul fire framed in warning stripes, railings round the
-- edge, crates and machines as cover, and outside: the furnace with its
-- stacks, pipe runs, tanks and a gantry crane over the floor.
-- Palette: gunmetal and steel (dominant), rust and concrete (secondary),
-- hazard yellow and soul blue (small accents).

local Common = require(script.Parent.Common)

local SoulFoundry = {}

local M = Common.M
local rgb = Common.rgb
local block, cylinder, disc = Common.block, Common.cylinder, Common.disc
local vary, pick = Common.vary, Common.pick
local SMALL, GHOST = Common.SMALL, Common.GHOST

local PLATES = { rgb(104, 108, 112), rgb(96, 100, 106), rgb(110, 112, 114) }
local SEAM = rgb(46, 48, 52)
local GUNMETAL = rgb(70, 74, 80)
local STEEL = rgb(122, 126, 130)
local DARK = rgb(48, 50, 54)
local RUST = rgb(124, 82, 56)
local CONCRETE = rgb(122, 118, 110)
local WOOD = rgb(110, 84, 58)
local HAZARD = rgb(212, 168, 50)
local SOUL = rgb(92, 152, 255)
local SOUL_PALE = rgb(196, 222, 255)

-- Terrain ------------------------------------------------------------------------------------

local function terrain(ctx: Common.Context)
	local c = ctx.center
	Common.terrainColor(ctx, M.Asphalt, rgb(70, 70, 72))
	Common.terrainColor(ctx, M.Concrete, rgb(120, 116, 110))
	Common.fill(ctx, "FillBlock", CFrame.new(c + Vector3.new(68, -6.75, 0)), Vector3.new(260, 14.5, 212), M.Asphalt)
	-- Raised concrete pads the furnace and tanks stand on
	Common.fill(ctx, "FillBlock", CFrame.new(c + Vector3.new(104, 0.5, 0)), Vector3.new(50, 3, 70), M.Concrete)
	Common.fill(ctx, "FillBlock", CFrame.new(c + Vector3.new(30, 0.3, 84)), Vector3.new(70, 2, 24), M.Concrete)
	Common.fill(ctx, "FillBlock", CFrame.new(c + Vector3.new(30, 0.3, -84)), Vector3.new(70, 2, 24), M.Concrete)
	-- The quarry walls the foundry was cut into
	for _, wall in { { 176, 0, 30, 60, 200, 0.06 }, { 60, -100, 220, 50, 12, 0.04 }, { 60, 100, 220, 46, 12, -0.04 } } do
		Common.fill(ctx, "FillBlock", CFrame.new(c + Vector3.new(wall[1], wall[4] / 2 - 8, wall[2])) * CFrame.Angles(wall[6], 0, wall[6]), Vector3.new(wall[3], wall[4], wall[5]), M.Slate)
	end
	-- Spurs of rock left standing where the cutting stopped
	for _, spot in { { 154, -66, 16, 0.3 }, { 160, 52, 20, -0.4 }, { -40, 92, 12, 0.2 }, { -30, -92, 14, -0.3 }, { 110, 92, 14, 0.5 } } do
		Common.fill(ctx, "FillBlock", CFrame.new(c + Vector3.new(spot[1], spot[3] / 2 - 2, spot[2])) * CFrame.Angles(spot[4] * 0.3, spot[4], spot[4] * 0.2), Vector3.new(spot[3] * 1.4, spot[3] + 4, spot[3]), M.Slate)
	end
end

-- Floor --------------------------------------------------------------------------------------

local function floor(ctx: Common.Context)
	local top = ctx.top
	local random = ctx.random
	Common.floor(ctx, SEAM, M.Metal)
	-- A six by six deck of plates; a few rusted through, one replaced and newer
	local size = 110 / 6
	for i = 0, 5 do
		for j = 0, 5 do
			local x, z = -55 + size * (i + 0.5), -55 + size * (j + 0.5)
			do
				local rusted = (i * 7 + j * 3) % 11 == 4
				local color = if rusted then vary(RUST, random, 0.05) else vary(pick(PLATES, random), random, 0.03)
				block(ctx.model, "Plate", Vector3.new(size - 0.35, 0.3, size - 0.35), CFrame.new(top + Vector3.new(x, -0.09 + (i + j) % 2 * 0.01, z)), color, if rusted then M.CorrodedMetal else M.DiamondPlate, GHOST)
			end
		end
	end
	-- The cooling grate in the middle: a dark ring of bars over blue light
	disc(ctx.model, "GrateRim", top + Vector3.new(0, 0.08, 0), 22, 0.3, vary(GUNMETAL, random, 0.03), M.Metal, GHOST)
	disc(ctx.model, "GrateGlow", top + Vector3.new(0, 0.1, 0), 16, 0.2, rgb(40, 70, 120), M.Neon, GHOST)
	for index = 0, 7 do
		local x = -7 + index * 2
		local half = math.sqrt(math.max(0, 64 - x * x))
		block(ctx.model, "GrateBar", Vector3.new(0.9, 0.24, half * 2), CFrame.new(top + Vector3.new(x + 1, 0.2, 0)), DARK, M.Metal, GHOST)
	end
	local hub = disc(ctx.model, "GrateHub", top + Vector3.new(0, 0.28, 0), 4.6, 0.3, vary(STEEL, random, 0.03), M.Metal, { CastShadow = false, CanCollide = false })
	Common.light(hub, SOUL, 18, 0.8)
	Common.motes(hub, SOUL_PALE, 2, { texture = Common.SMOKE, size = 3, alpha = 0.85, lightEmission = 0.3, minSpeed = 1, maxSpeed = 2 })
	-- Hazard band round the deck edge, with oil stains and scuffs
	for _, normal in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local mid = top + normal * 53.8
		block(ctx.model, "HazardBand", Vector3.new(107.6, 0.12, 1.2), Common.lookAt(mid, mid + normal) * CFrame.new(0, 0.1, 0), HAZARD, M.SmoothPlastic, GHOST)
	end
	for _, spot in { { -20, 30, 6 }, { 34, -16, 4 }, { -38, -26, 5 } } do
		disc(ctx.model, "OilStain", top + Vector3.new(spot[1], 0.08 + spot[3] * 0.003, spot[2]), spot[3], 0.1, rgb(58, 58, 60), M.Metal, GHOST)
	end
end

-- Soul-fire vents by the north and south edges, framed in warning stripes
local function vents(ctx: Common.Context)
	local random = ctx.random
	for _, v in { -0.78, 0.78 } do
		local at = Common.at(ctx, random:NextNumber(-0.08, 0.08), 0, v)
		local frame = CFrame.new(at)
		local grate = block(ctx.model, "VentGrate", Vector3.new(8, 0.3, 4), frame * CFrame.new(0, 0.05, 0), DARK, M.Metal, { CastShadow = false, CanCollide = false })
		block(ctx.model, "VentGlow", Vector3.new(7, 0.2, 3), frame * CFrame.new(0, 0.08, 0), SOUL, M.Neon, GHOST)
		for index = -3, 3 do
			block(ctx.model, "VentBar", Vector3.new(0.4, 0.2, 3.8), frame * CFrame.new(index * 1.05, 0.22, 0), GUNMETAL, M.Metal, GHOST)
		end
		-- Striped frame: yellow with dark diagonal bands on the long sides
		for _, side in { -1, 1 } do
			block(ctx.model, "VentFrame", Vector3.new(10, 0.16, 1), frame * CFrame.new(0, 0.12, side * 2.6), HAZARD, M.SmoothPlastic, GHOST)
			for stripe = -2, 2 do
				block(ctx.model, "VentStripe", Vector3.new(0.5, 0.18, 1.3), frame * CFrame.new(stripe * 2, 0.13, side * 2.6) * CFrame.Angles(0, math.rad(40), 0), DARK, M.SmoothPlastic, GHOST)
			end
		end
		local fire = Instance.new("Fire")
		fire.Size = 4
		fire.Heat = 9
		fire.Color = SOUL
		fire.SecondaryColor = SOUL_PALE
		fire.Parent = grate
		Common.light(grate, SOUL, 20, 1.3, true)
		Common.motes(grate, rgb(170, 180, 196), 3, { texture = Common.SMOKE, size = 3.5, alpha = 0.8, lightEmission = 0, minSpeed = 2, maxSpeed = 4, minLife = 3, maxLife = 5, acceleration = Vector3.new(0, 1, 0) })
		Common.interactive(grate, "Vent")
	end
end

-- The catwalk edge: a steel kerb with railing posts and rails painted yellow
local function railing(ctx: Common.Context)
	local random = ctx.random
	for _, normal in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local mid = ctx.top + normal * 56.6
		local frame = Common.lookAt(mid, mid + normal)
		block(ctx.model, "Kerb", Vector3.new(116, 3.2, 3.2), frame * CFrame.new(0, -1, 0), vary(GUNMETAL, random, 0.03), M.Metal)
		block(ctx.model, "KerbCap", Vector3.new(116.4, 0.4, 3.6), frame * CFrame.new(0, 0.8, 0), vary(STEEL, random, 0.03), M.DiamondPlate, SMALL)
		for _, y in { 2.4, 4.2 } do
			block(ctx.model, "Rail", Vector3.new(114, 0.3, 0.3), frame * CFrame.new(0, y, 0.6), HAZARD, M.Metal, SMALL)
		end
		for index = -4, 4 do
			block(ctx.model, "RailPost", Vector3.new(0.4, 3.6, 0.4), frame * CFrame.new(index * 13 + random:NextNumber(-0.3, 0.3), 2.6, 0.6), vary(DARK, random, 0.05), M.Metal, SMALL)
		end
	end
end

-- Cover: a crate stack, a generator, a pipe bundle and a cargo container
local function coverAt(ctx: Common.Context, degrees: number): CFrame
	local angle = math.rad(degrees + ctx.random:NextNumber(-6, 6))
	local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local base = ctx.top + out * 29
	return Common.lookAt(base, base + out)
end

local function crate(ctx: Common.Context, frame: CFrame, size: number)
	local random = ctx.random
	block(ctx.model, "Crate", Vector3.one * size, frame, vary(WOOD, random, 0.06), M.WoodPlanks)
	block(ctx.model, "CrateBand", Vector3.new(size + 0.12, 0.4, size + 0.12), frame, vary(DARK, random, 0.05), M.Metal, SMALL)
end

local function cover(ctx: Common.Context)
	local random = ctx.random
	-- Crates, big-medium-small
	local stack = coverAt(ctx, 0)
	crate(ctx, stack * CFrame.new(-2, 2, 0) * CFrame.Angles(0, 0.1, 0), 4)
	crate(ctx, stack * CFrame.new(2.4, 1.5, 0.4) * CFrame.Angles(0, -0.25, 0), 3)
	crate(ctx, stack * CFrame.new(-1.6, 5.25, 0.2) * CFrame.Angles(0, 0.4, 0), 2.5)
	-- A generator: housing, tank and a stub of pipe
	local gen = coverAt(ctx, 90)
	block(ctx.model, "GenBase", Vector3.new(10, 0.6, 4.6), gen * CFrame.new(0, 0.3, 0), vary(DARK, random, 0.04), M.Metal)
	block(ctx.model, "Generator", Vector3.new(5, 4.4, 3.8), gen * CFrame.new(-2.2, 2.8, 0), vary(GUNMETAL, random, 0.04), M.Metal)
	cylinder(ctx.model, "GenTank", gen * CFrame.new(2.8, 2.2, 0) * CFrame.Angles(0, 0, math.pi / 2), 4.4, 3.4, vary(RUST, random, 0.05), M.CorrodedMetal)
	block(ctx.model, "GenStripe", Vector3.new(5.04, 0.6, 3.84), gen * CFrame.new(-2.2, 4.4, 0), HAZARD, M.SmoothPlastic, SMALL)
	local gauge = block(ctx.model, "GenGauge", Vector3.new(1.2, 0.8, 0.2), gen * CFrame.new(-2.2, 3, 2), SOUL, M.Neon, GHOST)
	Common.surfaceLight(gauge, Enum.NormalId.Back, SOUL, 6, 0.6)
	-- Three big pipes on saddles
	local pipes = coverAt(ctx, 180)
	for index, spec in { { -1.7, 1.8, 3.4 }, { 1.7, 1.8, 3.4 }, { 0, 4.6, 2.8 } } do
		cylinder(ctx.model, "Pipe", pipes * CFrame.new(0, spec[2], spec[1]) * CFrame.Angles(0, 0, math.pi / 2), 12, spec[3], if index == 3 then vary(RUST, random, 0.05) else vary(STEEL, random, 0.04), if index == 3 then M.CorrodedMetal else M.Metal)
	end
	for _, side in { -1, 1 } do
		block(ctx.model, "Saddle", Vector3.new(1, 1.4, 7), pipes * CFrame.new(side * 4.4, 0.7, 0), vary(DARK, random, 0.04), M.Metal, SMALL)
	end
	-- A cargo container, dented and rusting
	local box = coverAt(ctx, 270)
	block(ctx.model, "Container", Vector3.new(12, 5.6, 4.4), box * CFrame.new(0, 2.8, 0) * CFrame.Angles(0, 0.05, 0), vary(rgb(76, 92, 104), random, 0.04), M.CorrodedMetal)
	for _, x in { -6.1, 6.1 } do
		block(ctx.model, "ContainerFrame", Vector3.new(0.5, 5.8, 4.6), box * CFrame.new(x, 2.9, 0) * CFrame.Angles(0, 0.05, 0), vary(DARK, random, 0.04), M.Metal, SMALL)
	end
	block(ctx.model, "ContainerStripe", Vector3.new(11.8, 0.5, 4.5), box * CFrame.new(0, 4.6, 0) * CFrame.Angles(0, 0.05, 0), HAZARD, M.SmoothPlastic, SMALL)
end

-- Outside: furnace, stacks, pipe runs, tanks and the gantry crane
local function furnace(ctx: Common.Context)
	local random = ctx.random
	local c = ctx.center
	local base = c + Vector3.new(104, 2, 0)
	local root = CFrame.new(base)
	cylinder(ctx.model, "FurnacePlinth", root * CFrame.new(0, 1, 0), 2, 34, vary(CONCRETE, random, 0.03), M.Concrete)
	cylinder(ctx.model, "Furnace", root * CFrame.new(0, 16, 0), 28, 28, vary(GUNMETAL, random, 0.04), M.Metal)
	cylinder(ctx.model, "FurnaceSkirt", root * CFrame.new(0, 5, 0), 8, 29, vary(RUST, random, 0.04), M.CorrodedMetal)
	for _, y in { 9.4, 20, 29.4 } do
		cylinder(ctx.model, "FurnaceBand", root * CFrame.new(0, y, 0), 1.2, 29, vary(DARK, random, 0.04), M.Metal, SMALL)
	end
	cylinder(ctx.model, "FurnaceTop", root * CFrame.new(0, 31.5, 0), 3, 22, vary(STEEL, random, 0.04), M.Metal)
	cylinder(ctx.model, "FurnaceTop", root * CFrame.new(0, 34.2, 0), 2.4, 15, vary(GUNMETAL, random, 0.04), M.Metal)
	for _, offset in { { -4, 3, 52 }, { 5, -5, 44 } } do
		cylinder(ctx.model, "Stack", root * CFrame.new(offset[1], 33 + offset[3] / 2, offset[2]), offset[3], 4.6, vary(GUNMETAL, random, 0.05), M.Metal)
		cylinder(ctx.model, "StackBand", root * CFrame.new(offset[1], 33 + offset[3] * 0.8, offset[2]), 1, 5.2, HAZARD, M.SmoothPlastic, SMALL)
	end
	-- The mouth, facing the arena, glowing with soul fire
	local face = Common.lookAt(base, base - Vector3.new(1, 0, 0))
	local mouth = block(ctx.model, "FurnaceMouth", Vector3.new(10, 8, 1), face * CFrame.new(0, 7, -13.8), SOUL, M.Neon, { CastShadow = false })
	Common.surfaceLight(mouth, Enum.NormalId.Front, SOUL, 24, 1.4, 80)
	block(ctx.model, "MouthFrame", Vector3.new(12, 1.2, 2), face * CFrame.new(0, 11.6, -14), vary(DARK, random, 0.04), M.Metal, SMALL)
	block(ctx.model, "MouthSill", Vector3.new(12, 1, 2.4), face * CFrame.new(0, 2.6, -14), vary(DARK, random, 0.04), M.Metal, SMALL)
	Common.motes(mouth, SOUL_PALE, 4, { minSpeed = 2, maxSpeed = 5, size = 0.2, acceleration = Vector3.new(0, 2, 0), lightEmission = 1 })
	-- The name plate on a frame in front of the furnace
	local plateAt = c + Vector3.new(66, 0.5, 0)
	local plateFace = Common.lookAt(plateAt, plateAt - Vector3.new(1, 0, 0))
	for _, side in { -1, 1 } do
		block(ctx.model, "SignPost", Vector3.new(1, 12, 1), plateFace * CFrame.new(side * 11, 6, 0), vary(DARK, random, 0.04), M.Metal)
	end
	local plate = block(ctx.model, "NamePlate", Vector3.new(21, 4, 0.5), plateFace * CFrame.new(0, 9.4, 0), vary(GUNMETAL, random, 0.03), M.Metal)
	Common.sign(plate, Enum.NormalId.Front, "SOUL FOUNDRY", SOUL_PALE, 24, 0.4)
	block(ctx.model, "NameStripe", Vector3.new(21, 0.6, 0.55), plateFace * CFrame.new(0, 7.1, 0), HAZARD, M.SmoothPlastic, SMALL)
	-- The capacitor beside the plate: the Pylon
	local capacitor = c + Vector3.new(64, 0.5, -24)
	block(ctx.model, "CapacitorBase", Vector3.new(6, 1.6, 6), CFrame.new(capacitor + Vector3.new(0, 0.8, 0)), vary(DARK, random, 0.04), M.Metal)
	local coil = cylinder(ctx.model, "Capacitor", CFrame.new(capacitor + Vector3.new(0, 7.6, 0)), 12, 3.6, vary(GUNMETAL, random, 0.04), M.Metal)
	for _, y in { 4, 7, 10 } do
		cylinder(ctx.model, "CapacitorRing", CFrame.new(capacitor + Vector3.new(0, y, 0)), 0.5, 4.4, SOUL, M.Neon, GHOST)
	end
	cylinder(ctx.model, "CapacitorCap", CFrame.new(capacitor + Vector3.new(0, 14.1, 0)), 1, 5, vary(STEEL, random, 0.04), M.Metal, SMALL)
	Common.light(coil, SOUL, 18, 1)
	Common.interactive(coil, "Pylon")
end

local function yard(ctx: Common.Context)
	local random = ctx.random
	local c = ctx.center
	-- Pipe runs from the furnace along both sides, on stands, with sight glasses
	for _, z in { -66, 66 } do
		-- Straight along the side, then a bend in to the furnace
		local from = c + Vector3.new(-60, 6, z)
		local to = c + Vector3.new(84, 6, z)
		local feed = c + Vector3.new(100, 6, z * 0.21)
		cylinder(ctx.model, "PipeRun", CFrame.new((from + to) / 2) * CFrame.Angles(0, 0, math.pi / 2), (to - from).Magnitude, 3.6, vary(STEEL, random, 0.04), M.Metal)
		cylinder(ctx.model, "PipeRun", Common.lookAt((to + feed) / 2, feed) * CFrame.Angles(math.pi / 2, 0, 0), (feed - to).Magnitude, 3.6, vary(STEEL, random, 0.04), M.Metal)
		Common.ball(ctx.model, "PipeElbow", to, 4.2, vary(GUNMETAL, random, 0.04), M.Metal, SMALL)
		for share = 0.08, 0.95, 0.17 do
			local at = from:Lerp(to, share)
			block(ctx.model, "PipeStand", Vector3.new(1, at.Y - c.Y, 4.6), CFrame.new(Vector3.new(at.X, c.Y + (at.Y - c.Y) / 2, at.Z)), vary(DARK, random, 0.04), M.Metal, SMALL)
		end
		local glass = cylinder(ctx.model, "SightGlass", Common.lookAt(from:Lerp(to, 0.5), to) * CFrame.Angles(math.pi / 2, 0, 0), 2.4, 3.9, SOUL, M.Neon, GHOST)
		Common.light(glass, SOUL, 12, 0.7)
	end
	-- Tanks on the concrete pads
	for _, spot in { { 10, 84, 14, 16 }, { 34, 86, 10, 22 }, { 56, 82, 12, 14 }, { 16, -84, 12, 20 }, { 44, -86, 15, 15 } } do
		local base = c + Vector3.new(spot[1], 1.3, spot[2])
		cylinder(ctx.model, "Tank", CFrame.new(base + Vector3.new(0, spot[4] / 2, 0)), spot[4], spot[3], vary(pick({ GUNMETAL, STEEL, RUST }, random), random, 0.04), if random:NextNumber() < 0.4 then M.CorrodedMetal else M.Metal)
		cylinder(ctx.model, "TankCap", CFrame.new(base + Vector3.new(0, spot[4] + 0.5, 0)), 1, spot[3] * 0.8, vary(DARK, random, 0.04), M.Metal, SMALL)
		cylinder(ctx.model, "TankBand", CFrame.new(base + Vector3.new(0, spot[4] * 0.3, 0)), 0.8, spot[3] + 0.3, HAZARD, M.SmoothPlastic, SMALL)
	end
	-- The gantry crane straddling the floor, its hook hanging on a chain
	local x = c.X + 30
	for _, z in { -64, 64 } do
		local foot = Vector3.new(x, c.Y + 0.5, c.Z + z)
		block(ctx.model, "GantryFoot", Vector3.new(6, 1.4, 4), CFrame.new(foot + Vector3.new(0, 0.7, 0)), vary(CONCRETE, random, 0.03), M.Concrete)
		for _, side in { -1, 1 } do
			block(ctx.model, "GantryLeg", Vector3.new(1.4, 34, 1.4), CFrame.new(foot + Vector3.new(side * 2, 18.4, 0)) * CFrame.Angles(0, 0, -side * 0.04), vary(GUNMETAL, random, 0.04), M.Metal)
		end
		block(ctx.model, "GantryBand", Vector3.new(6, 1.2, 1.8), CFrame.new(foot + Vector3.new(0, 4, 0)), HAZARD, M.SmoothPlastic, SMALL)
	end
	block(ctx.model, "GantryBeam", Vector3.new(3, 3, 134), CFrame.new(Vector3.new(x, c.Y + 36, c.Z)), vary(GUNMETAL, random, 0.04), M.Metal)
	block(ctx.model, "GantryStripe", Vector3.new(3.1, 0.7, 134.1), CFrame.new(Vector3.new(x, c.Y + 36.6, c.Z)), HAZARD, M.SmoothPlastic, SMALL)
	block(ctx.model, "GantryBeam", Vector3.new(3.2, 0.6, 134.4), CFrame.new(Vector3.new(x, c.Y + 34.2, c.Z)), vary(DARK, random, 0.04), M.Metal, SMALL)
	-- Floodlight masts at the deck corners, aimed down at the floor
	for index, corner in { { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } } do
		local foot = c + Vector3.new(corner[1] * 62, 0.5, corner[2] * 62)
		block(ctx.model, "MastFoot", Vector3.new(3, 1, 3), CFrame.new(foot + Vector3.new(0, 0.5, 0)), vary(CONCRETE, random, 0.03), M.Concrete, SMALL)
		cylinder(ctx.model, "Mast", CFrame.new(foot + Vector3.new(0, 11, 0)), 21, 0.9, vary(GUNMETAL, random, 0.04), M.Metal)
		local aim = Vector3.new(c.X, foot.Y, c.Z) - foot
		local head = block(ctx.model, "Floodlight", Vector3.new(3.2, 1.6, 1.2), Common.lookAt(foot + Vector3.new(0, 21.6, 0), foot + Vector3.new(0, 21.6, 0) + aim.Unit * 3 - Vector3.new(0, 1.4, 0)), vary(DARK, random, 0.04), M.Metal, SMALL)
		Common.spotLight(head, Enum.NormalId.Front, rgb(236, 240, 255), 60, 1.1, 50, index <= 2)
	end
	-- A catwalk over the south pipe run, on posts, with a ladder down
	local walk = c + Vector3.new(10, 11, -72)
	block(ctx.model, "Catwalk", Vector3.new(60, 0.5, 4), CFrame.new(walk), vary(STEEL, random, 0.03), M.DiamondPlate)
	for _, side in { -1, 1 } do
		block(ctx.model, "CatwalkRail", Vector3.new(60, 0.3, 0.3), CFrame.new(walk + Vector3.new(0, 3.2, side * 1.9)), HAZARD, M.Metal, SMALL)
	end
	for post = -28, 28, 14 do
		block(ctx.model, "CatwalkPost", Vector3.new(0.8, 10.5, 0.8), CFrame.new(walk + Vector3.new(post, -5.4, 0)), vary(DARK, random, 0.04), M.Metal, SMALL)
	end
	block(ctx.model, "Ladder", Vector3.new(2, 11, 0.3), CFrame.new(walk + Vector3.new(-30.4, -5.5, 0)) * CFrame.Angles(0, math.pi / 2, 0.08), vary(DARK, random, 0.04), M.Metal, SMALL)
	-- Ingots stacked by the furnace, waiting to be moved
	for index = 0, 2 do
		block(ctx.model, "IngotStack", Vector3.new(6, 1.4, 3), CFrame.new(c + Vector3.new(80, 4.2 + index * 1.4, 34)) * CFrame.Angles(0, index * 0.5, 0), vary(STEEL, random, 0.05), M.Metal, SMALL)
	end
	local trolley = Vector3.new(x, c.Y + 33, c.Z + 18)
	block(ctx.model, "Trolley", Vector3.new(4, 2.4, 5), CFrame.new(trolley), vary(GUNMETAL, random, 0.04), M.Metal, SMALL)
	block(ctx.model, "Chain", Vector3.new(0.3, 12, 0.3), CFrame.new(trolley + Vector3.new(0, -7.2, 0)), DARK, M.Metal, GHOST)
	block(ctx.model, "Hook", Vector3.new(1.2, 2.2, 0.5), CFrame.new(trolley + Vector3.new(0, -14, 0)) * CFrame.Angles(0, 0.3, 0), vary(DARK, random, 0.04), M.Metal, GHOST)
end

local function throwables(ctx: Common.Context)
	local random = ctx.random
	local function ground(u: number, v: number): Vector3
		return Common.at(ctx, u, 0, v)
	end
	Common.throwable(ctx, "Crate", 1, Vector3.new(3, 3, 3), CFrame.new(ground(-0.58, 0.32) + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0.5, 0), vary(WOOD, random, 0.05), M.WoodPlanks)
	Common.throwable(ctx, "Toolbox", 1, Vector3.new(3.4, 1.8, 2), CFrame.new(ground(-0.26, -0.64) + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, 1.1, 0), vary(rgb(150, 54, 44), random, 0.04), M.Metal)
	Common.uprightThrowable(ctx, "SoulCanister", 1, ground(0.62, 0.42), 3.2, 2.4, 0, vary(GUNMETAL, random, 0.04), M.Metal)
	Common.throwable(ctx, "Ingot", 2, Vector3.new(5, 2.6, 3), CFrame.new(ground(0.52, -0.3) + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 0.7, 0), vary(STEEL, random, 0.04), M.Metal)
	Common.throwable(ctx, "Anvil", 2, Vector3.new(4.4, 3.4, 3), CFrame.new(ground(-0.62, -0.38) + Vector3.new(0, 1.7, 0)) * CFrame.Angles(0, 2.1, 0), vary(DARK, random, 0.04), M.Metal)
	Common.uprightThrowable(ctx, "Boiler", 3, ground(0.24, 0.64), 4.8, 5.4, 0.3, vary(RUST, random, 0.04), M.CorrodedMetal)
end

local function spawnPads(ctx: Common.Context)
	for _, spawn in Common.spawns(ctx) do
		local base = Common.spawnBase(spawn, ctx.floorY)
		disc(ctx.model, "SpawnRing", base + Vector3.new(0, 0.14, 0), 9, 0.2, HAZARD, M.SmoothPlastic, GHOST)
		disc(ctx.model, "SpawnPad", base + Vector3.new(0, 0.18, 0), 8, 0.2, vary(GUNMETAL, ctx.random, 0.02), M.DiamondPlate, GHOST)
		disc(ctx.model, "SpawnMark", base + Vector3.new(0, 0.21, 0), 1.4, 0.1, SOUL, M.Neon, GHOST)
	end
end

function SoulFoundry.build(ctx: Common.Context)
	terrain(ctx)
	floor(ctx)
	vents(ctx)
	railing(ctx)
	Common.barriers(ctx)
	cover(ctx)
	furnace(ctx)
	yard(ctx)
	throwables(ctx)
	spawnPads(ctx)
end

return SoulFoundry
