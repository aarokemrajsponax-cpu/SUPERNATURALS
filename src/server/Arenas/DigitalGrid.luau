-- Digital Grid: Syntax's dimension. A dark platform of floor panels on a
-- glowing grid, raised over an endless grid plain where server towers stand in
-- rows into the distance. Hologram pillars in the corners, data cubes held up
-- on beams from their emitters, a scan-line screen with the arena's name, and a
-- few panels that glitched out of place.
-- Palette: deep navy and blue-grey panels (dominant), steel blue and tinted
-- glass (secondary), cyan and a little white light (small accents).

local Common = require(script.Parent.Common)

local DigitalGrid = {}

local M = Common.M
local rgb = Common.rgb
local block, cylinder, disc = Common.block, Common.cylinder, Common.disc
local vary = Common.vary
local SMALL, GHOST = Common.SMALL, Common.GHOST

local BASE = rgb(28, 36, 48)
local PANELS = { rgb(46, 58, 74), rgb(51, 63, 80), rgb(42, 54, 69) }
local STEEL = rgb(58, 72, 90)
local STEEL_PALE = rgb(86, 102, 120)
local TRACE = rgb(34, 98, 108)
local GLASS = rgb(110, 196, 210)
local CYAN = rgb(70, 220, 230)
local WHITE = rgb(214, 240, 244)

-- Where the plain lies below the platform's floor
local PLAIN_DROP = 7

-- Floor ---------------------------------------------------------------------------------------

local function floor(ctx: Common.Context)
	local top = ctx.top
	local random = ctx.random
	Common.floor(ctx, BASE, M.SmoothPlastic)
	-- Five by five panels; one sticks up out of place, one is open to the data layer
	for i = -2, 2 do
		for j = -2, 2 do
			local center = top + Vector3.new(i * 22, -0.09, j * 22)
			if i == -1 and j == 1 then
				block(ctx.model, "DataLayer", Vector3.new(21.4, 0.3, 21.4), CFrame.new(center), rgb(44, 100, 112), M.Glass, { Transparency = 0.2, CastShadow = false, CanCollide = false, CanQuery = false, CanTouch = false })
			elseif not (i == 0 and j == 0) then
				local frame = CFrame.new(center)
				if i == 1 and j == -1 then
					frame = CFrame.new(center + Vector3.new(0.6, 0.22, -0.4)) * CFrame.Angles(0.01, 0.03, -0.008)
				end
				block(ctx.model, "Panel", Vector3.new(21.4, 0.3, 21.4), frame, vary(PANELS[(i + j) % 3 + 1], random, 0.03), M.SmoothPlastic, GHOST)
			end
		end
	end
	-- The middle panel is the core: a raised disc with a broken ring and the Node
	block(ctx.model, "Panel", Vector3.new(21.4, 0.3, 21.4), CFrame.new(top + Vector3.new(0, -0.1, 0)), vary(PANELS[2], random, 0.02), M.SmoothPlastic, GHOST)
	disc(ctx.model, "Core", top + Vector3.new(0, 0.2, 0), 17, 0.3, vary(STEEL, random, 0.02), M.SmoothPlastic, GHOST)
	Common.ring(ctx, top, 7.6, 16, 0.22, CYAN, M.Neon, 0.22, { 4, 5, 12 })
	local node = disc(ctx.model, "Node", top + Vector3.new(0, 0.3, 0), 4.4, 0.3, vary(BASE, random, 0.02), M.SmoothPlastic, { CastShadow = false, CanCollide = false })
	Common.interactive(node, "Node")
	disc(ctx.model, "NodeCore", top + Vector3.new(0, 0.34, 0), 1.4, 0.1, WHITE, M.Neon, GHOST)
	-- Grid: bright seams between panels, dim teal lines through their middles
	for _, offset in { -33, -11, 11, 33 } do
		block(ctx.model, "GridLine", Vector3.new(0.22, 0.1, 110), CFrame.new(top + Vector3.new(offset, 0.04, 0)), CYAN, M.Neon, GHOST)
		block(ctx.model, "GridLine", Vector3.new(110, 0.1, 0.22), CFrame.new(top + Vector3.new(0, 0.045, offset)), CYAN, M.Neon, GHOST)
	end
	for _, offset in { -44, -22, 22, 44 } do
		block(ctx.model, "SubLine", Vector3.new(0.14, 0.08, 110), CFrame.new(top + Vector3.new(offset, 0.08, 0)), TRACE, M.SmoothPlastic, GHOST)
		block(ctx.model, "SubLine", Vector3.new(110, 0.08, 0.14), CFrame.new(top + Vector3.new(0, 0.085, offset)), TRACE, M.SmoothPlastic, GHOST)
	end
	-- Circuit traces running from the core out to each spawn, with a bend
	for _, corner in { { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } } do
		local bendAt = random:NextNumber(18, 24)
		local a = top + Vector3.new(corner[1] * 9, 0.12, 0)
		local b = top + Vector3.new(corner[1] * bendAt, 0.12, 0)
		local c = top + Vector3.new(corner[1] * bendAt, 0.12, corner[2] * 30)
		Common.strut(ctx.model, "Trace", a, b, 0.35, 0.06, TRACE, M.SmoothPlastic, GHOST)
		Common.strut(ctx.model, "Trace", b, c, 0.35, 0.06, TRACE, M.SmoothPlastic, GHOST)
		disc(ctx.model, "TraceEnd", c + Vector3.new(0, 0.04, 0), 1.2, 0.08, CYAN, M.Neon, GHOST)
	end
end

-- The platform's edge: a raised lip with a light strip, then a lower step
local function rim(ctx: Common.Context)
	local random = ctx.random
	for _, normal in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local mid = ctx.top + normal * 56.5
		local frame = Common.lookAt(mid, mid + normal)
		block(ctx.model, "Rim", Vector3.new(116, PLAIN_DROP + 0.7, 3), frame * CFrame.new(0, (0.7 - PLAIN_DROP) / 2, 0), vary(STEEL, random, 0.03), M.SmoothPlastic)
		block(ctx.model, "RimStrip", Vector3.new(110, 0.12, 0.3), frame * CFrame.new(0, 0.76, 1.2), CYAN, M.Neon, GHOST)
		block(ctx.model, "RimStep", Vector3.new(124, 3, 6), frame * CFrame.new(0, 1.5 - PLAIN_DROP, -2), vary(BASE, random, 0.03), M.SmoothPlastic)
		block(ctx.model, "RimBand", Vector3.new(124.2, 0.3, 0.2), frame * CFrame.new(0, 2.4 - PLAIN_DROP, -5.05), TRACE, M.SmoothPlastic, GHOST)
	end
end

-- Hologram pillars in the corners; two of them are Pylons powers can take over
local function pillars(ctx: Common.Context)
	local random = ctx.random
	for index, corner in { { 1, -1 }, { -1, 1 }, { 1, 1 }, { -1, -1 } } do
		local base = ctx.top + Vector3.new(corner[1] * 58.5, 0.7, corner[2] * 58.5)
		block(ctx.model, "PillarBase", Vector3.new(7, 2.4, 7), CFrame.new(base + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, math.rad(45), 0), vary(STEEL, random, 0.03), M.SmoothPlastic)
		block(ctx.model, "PillarFoot", Vector3.new(4.6, 1, 4.6), CFrame.new(base + Vector3.new(0, 2.9, 0)), vary(BASE, random, 0.03), M.SmoothPlastic, SMALL)
		local tall = 15 + index
		local glass = cylinder(ctx.model, "HoloPillar", CFrame.new(base + Vector3.new(0, 3.4 + tall / 2, 0)), tall, 3.4, GLASS, M.Glass, { Transparency = 0.55, CastShadow = false })
		cylinder(ctx.model, "HoloCore", CFrame.new(base + Vector3.new(0, 3.4 + tall / 2, 0)), tall - 0.6, 0.6, CYAN, M.Neon, GHOST)
		for _, share in { 0.33, 0.7 } do
			cylinder(ctx.model, "PillarBand", CFrame.new(base + Vector3.new(0, 3.4 + tall * share, 0)), 0.5, 3.9, vary(STEEL_PALE, random, 0.03), M.SmoothPlastic, SMALL)
		end
		block(ctx.model, "PillarCap", Vector3.new(4.6, 1, 4.6), CFrame.new(base + Vector3.new(0, 3.9 + tall, 0)), vary(BASE, random, 0.03), M.SmoothPlastic, SMALL)
		Common.light(glass, CYAN, 20, 1.1, index <= 2)
		Common.motes(glass, CYAN, 2, { size = 0.2, minLife = 3, maxLife = 6 })
		if index <= 2 then
			Common.interactive(glass, "Pylon")
		end
	end
end

-- Data streams: cubes of three sizes held up along one beam from an emitter
-- dais on the plain, so nothing floats without its source
local function dataCubes(ctx: Common.Context)
	local random = ctx.random
	local spots = { { 70, -34, 16 }, { 68, 30, 20 }, { -30, 68, 15 }, { 26, 70, 19 }, { -34, -69, 17 }, { 24, -71, 14 }, { -69, 6, 16 } }
	for _, spot in spots do
		local ground = ctx.top + Vector3.new(spot[1], -PLAIN_DROP, spot[2])
		local yaw = random:NextNumber(0, 1.5)
		block(ctx.model, "Dais", Vector3.new(6, 1.4, 6), CFrame.new(ground + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, yaw, 0), vary(BASE, random, 0.04), M.SmoothPlastic)
		block(ctx.model, "Emitter", Vector3.new(3.2, 2.4, 3.2), CFrame.new(ground + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, yaw + 0.785, 0), vary(STEEL, random, 0.04), M.SmoothPlastic)
		disc(ctx.model, "EmitterLens", ground + Vector3.new(0, 3.9, 0), 1.6, 0.2, CYAN, M.Neon, GHOST)
		local height = PLAIN_DROP + spot[3]
		block(ctx.model, "Beam", Vector3.new(0.14, height - 3.8, 0.14), CFrame.new(ground + Vector3.new(0, 3.8 + (height - 3.8) / 2, 0)), CYAN, M.Neon, GHOST)
		for index, share in { 0.45, 0.72, 1 } do
			local size = ({ 3.8, 2.6, 1.6 })[index] * random:NextNumber(0.85, 1.15)
			local frame = CFrame.new(ground + Vector3.new(0, 3.8 + (height - 3.8) * share, 0)) * CFrame.Angles(random:NextNumber(0, 1), random:NextNumber(0, 3), random:NextNumber(0, 1))
			local cube = block(ctx.model, "DataCube", Vector3.one * size, frame, GLASS, M.Glass, { Transparency = 0.4, CastShadow = false, CanCollide = false })
			if index == 1 then
				block(ctx.model, "DataCore", Vector3.one * size * 0.45, frame, WHITE, M.Neon, GHOST)
				Common.light(cube, CYAN, 14, 0.8)
			end
		end
	end
end

-- The name screen behind the east edge: a glass panel with scan lines
local function screen(ctx: Common.Context)
	local random = ctx.random
	local ground = ctx.top + Vector3.new(66, -PLAIN_DROP, 0)
	local face = Common.lookAt(ground, ground - Vector3.new(1, 0, 0))
	for _, side in { -1, 1 } do
		block(ctx.model, "ScreenPost", Vector3.new(1.4, 22, 1.4), face * CFrame.new(side * 14, 11, 0), vary(STEEL, random, 0.03), M.SmoothPlastic)
		block(ctx.model, "ScreenFoot", Vector3.new(3, 1.6, 3.4), face * CFrame.new(side * 14, 0.8, 0), vary(BASE, random, 0.03), M.SmoothPlastic, SMALL)
	end
	for _, y in { 10.4, 21.4 } do
		block(ctx.model, "ScreenBar", Vector3.new(29.4, 0.8, 1), face * CFrame.new(0, y, 0), vary(STEEL_PALE, random, 0.03), M.SmoothPlastic, SMALL)
	end
	local glass = block(ctx.model, "Screen", Vector3.new(26.6, 10.2, 0.2), face * CFrame.new(0, 15.9, 0), rgb(40, 96, 110), M.Glass, { Transparency = 0.35, CastShadow = false })
	Common.sign(glass, Enum.NormalId.Front, "DIGITAL GRID", WHITE, 24, 0)
	Common.surfaceLight(glass, Enum.NormalId.Front, CYAN, 18, 0.8, 70)
	for index = 1, 4 do
		block(ctx.model, "ScanLine", Vector3.new(26.4, 0.1, 0.1), face * CFrame.new(0, 11.4 + index * 2, -0.16), GLASS, M.SmoothPlastic, { Transparency = 0.5, CastShadow = false, CanCollide = false, CanQuery = false })
	end
end

-- Firewall blocks as cover: big, medium and small, with a light seam
local function cover(ctx: Common.Context)
	local random = ctx.random
	for index, degrees in { 0, 90, 180, 270 } do
		local angle = math.rad(degrees + random:NextNumber(-8, 8))
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local base = ctx.top + out * 29
		local frame = Common.lookAt(base, base + out)
		local flip = if index % 2 == 0 then 1 else -1
		block(ctx.model, "CoverPlate", Vector3.new(11, 0.3, 4.6), frame * CFrame.new(0, 0.15, 0), vary(BASE, random, 0.03), M.SmoothPlastic, GHOST)
		block(ctx.model, "Firewall", Vector3.new(6.4, 5.2, 3.4), frame * CFrame.new(-flip * 1.6, 2.6, 0), vary(STEEL, random, 0.04), M.SmoothPlastic)
		block(ctx.model, "Firewall", Vector3.new(3.6, 3.4, 3), frame * CFrame.new(flip * 3.6, 1.7, 0.5) * CFrame.Angles(0, flip * 0.12, 0), vary(PANELS[1], random, 0.04), M.SmoothPlastic)
		block(ctx.model, "Firewall", Vector3.new(3, 2, 2.8), frame * CFrame.new(-flip * 2.6, 6.2, -0.2) * CFrame.Angles(0, flip * 0.2, 0), vary(STEEL_PALE, random, 0.04), M.SmoothPlastic)
		block(ctx.model, "Seam", Vector3.new(6.42, 0.18, 0.12), frame * CFrame.new(-flip * 1.6, 4.1, 1.72), CYAN, M.Neon, GHOST)
	end
end

-- Two consoles on the west edge, screens lit
local function terminals(ctx: Common.Context)
	local random = ctx.random
	for _, v in { -0.4, 0.4 } do
		local base = Common.at(ctx, -0.9, 0, v)
		local frame = Common.lookAt(base, base + Vector3.new(-1, 0, 0)) * CFrame.Angles(0, math.pi, 0)
		block(ctx.model, "Console", Vector3.new(3.2, 3, 1.8), frame * CFrame.new(0, 1.5, 0), vary(STEEL, random, 0.04), M.SmoothPlastic)
		local panel = block(ctx.model, "ConsoleScreen", Vector3.new(3, 1.8, 0.2), frame * CFrame.new(0, 3.5, -0.3) * CFrame.Angles(math.rad(-30), 0, 0), rgb(40, 110, 124), M.SmoothPlastic, SMALL)
		Common.surfaceLight(panel, Enum.NormalId.Back, CYAN, 8, 0.7, 60)
	end
end

local function throwables(ctx: Common.Context)
	local random = ctx.random
	local function ground(u: number, v: number): Vector3
		return Common.at(ctx, u, 0, v)
	end
	Common.throwable(ctx, "DataBlock", 1, Vector3.new(3, 3, 3), CFrame.new(ground(-0.58, 0.32) + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0.5, 0), vary(PANELS[1], random, 0.04), M.SmoothPlastic)
	Common.throwable(ctx, "Drive", 1, Vector3.new(3.6, 1.6, 2.4), CFrame.new(ground(-0.26, -0.64) + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 1.1, 0), vary(STEEL_PALE, random, 0.04), M.SmoothPlastic)
	Common.uprightThrowable(ctx, "Capacitor", 1, ground(0.62, 0.42), 3.2, 2.4, 0, vary(STEEL, random, 0.04), M.Metal)
	Common.throwable(ctx, "ServerBlock", 2, Vector3.new(4.4, 4, 4), CFrame.new(ground(0.52, -0.3) + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0.7, 0), vary(STEEL, random, 0.04), M.SmoothPlastic)
	Common.throwable(ctx, "ServerBlock", 2, Vector3.new(4, 4.4, 4), CFrame.new(ground(-0.62, -0.38) + Vector3.new(0, 2.2, 0)) * CFrame.Angles(0, 2.1, 0), vary(PANELS[3], random, 0.04), M.SmoothPlastic)
	Common.throwable(ctx, "Monolith", 3, Vector3.new(4.6, 7, 4.6), CFrame.new(ground(0.24, 0.64) + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0.3, 0), vary(BASE, random, 0.03), M.SmoothPlastic)
end

local function spawnPads(ctx: Common.Context)
	for _, spawn in Common.spawns(ctx) do
		local base = Common.spawnBase(spawn, ctx.floorY)
		disc(ctx.model, "SpawnRing", base + Vector3.new(0, 0.14, 0), 9, 0.2, TRACE, M.SmoothPlastic, GHOST)
		disc(ctx.model, "SpawnPad", base + Vector3.new(0, 0.18, 0), 8.4, 0.2, vary(STEEL, ctx.random, 0.02), M.SmoothPlastic, GHOST)
		disc(ctx.model, "SpawnMark", base + Vector3.new(0, 0.21, 0), 1.4, 0.1, CYAN, M.Neon, GHOST)
	end
end

-- The grid plain below and the server towers standing on it
local function plain(ctx: Common.Context)
	local random = ctx.random
	local c = ctx.center
	local y = ctx.floorY - PLAIN_DROP
	block(ctx.model, "Plain", Vector3.new(264, 2, 216), CFrame.new(Vector3.new(c.X + 68, y - 1, c.Z)), vary(BASE, random, 0.02), M.SmoothPlastic)
	for x = -48, 192, 24 do
		block(ctx.model, "PlainLine", Vector3.new(0.4, 0.1, 216), CFrame.new(Vector3.new(c.X + x, y + 0.05, c.Z)), TRACE, M.SmoothPlastic, GHOST)
	end
	for z = -96, 96, 24 do
		block(ctx.model, "PlainLine", Vector3.new(264, 0.1, 0.4), CFrame.new(Vector3.new(c.X + 68, y + 0.06, c.Z + z)), TRACE, M.SmoothPlastic, GHOST)
	end
	local TOWERS = {
		{ 96, -66, 34 }, { 112, -24, 22 }, { 100, 34, 44 }, { 124, 74, 30 }, { 150, -52, 52 }, { 164, 12, 38 },
		{ 182, 58, 58 }, { 186, -92, 40 }, { 138, 30, 26 }, { -44, 92, 26 }, { 12, 98, 36 }, { 58, 90, 22 },
		{ -32, -94, 30 }, { 22, -98, 22 }, { 64, -92, 40 },
	}
	for _, tower in TOWERS do
		local width, depth = random:NextNumber(8, 15), random:NextNumber(8, 15)
		local base = Vector3.new(c.X + tower[1], y, c.Z + tower[2])
		-- Front (-Z) toward the arena, a little off square
		local frame = Common.lookAt(base, Vector3.new(c.X, y, c.Z)) * CFrame.Angles(0, random:NextNumber(-0.12, 0.12), 0)
		local tall = tower[3]
		block(ctx.model, "Tower", Vector3.new(width, tall, depth), frame * CFrame.new(0, tall / 2, 0), vary(PANELS[random:NextInteger(1, 3)], random, 0.04), M.SmoothPlastic)
		block(ctx.model, "TowerCap", Vector3.new(width + 1, 1.2, depth + 1), frame * CFrame.new(0, tall + 0.6, 0), vary(STEEL, random, 0.04), M.SmoothPlastic, SMALL)
		block(ctx.model, "TowerStrip", Vector3.new(0.4, tall * random:NextNumber(0.5, 0.8), 0.2), frame * CFrame.new(random:NextNumber(-width / 4, width / 4), tall * 0.45, -depth / 2 - 0.05), CYAN, M.Neon, GHOST)
		if tall > 30 then
			block(ctx.model, "TowerBand", Vector3.new(width + 0.2, 0.5, depth + 0.2), frame * CFrame.new(0, tall * 0.62, 0), TRACE, M.SmoothPlastic, GHOST)
			-- A setback on top of the tall ones
			local upper = tall * random:NextNumber(0.2, 0.35)
			block(ctx.model, "Tower", Vector3.new(width * 0.6, upper, depth * 0.6), frame * CFrame.new(random:NextNumber(-1, 1), tall + 1.2 + upper / 2, random:NextNumber(-1, 1)), vary(PANELS[random:NextInteger(1, 3)], random, 0.04), M.SmoothPlastic)
		end
	end
	-- The core spire far behind the screen, a beacon at its tip
	local spire = CFrame.new(Vector3.new(c.X + 150, y, c.Z + 8)) * CFrame.Angles(0, 0.3, 0)
	block(ctx.model, "SpireBase", Vector3.new(26, 10, 26), spire * CFrame.new(0, 5, 0), vary(STEEL, random, 0.03), M.SmoothPlastic)
	block(ctx.model, "Spire", Vector3.new(17, 46, 17), spire * CFrame.new(0, 33, 0), vary(PANELS[2], random, 0.03), M.SmoothPlastic)
	block(ctx.model, "SpireBand", Vector3.new(18, 1.2, 18), spire * CFrame.new(0, 56.6, 0), vary(STEEL_PALE, random, 0.03), M.SmoothPlastic, SMALL)
	block(ctx.model, "Spire", Vector3.new(10, 30, 10), spire * CFrame.new(0, 72, 0), vary(PANELS[1], random, 0.03), M.SmoothPlastic)
	for _, side in { -1, 1 } do
		block(ctx.model, "SpireStrip", Vector3.new(0.5, 40, 0.3), spire * CFrame.new(side * 4, 33, -8.6), CYAN, M.Neon, GHOST)
	end
	cylinder(ctx.model, "Antenna", spire * CFrame.new(0, 93, 0), 12, 0.7, STEEL_PALE, M.Metal, SMALL)
	local beacon = block(ctx.model, "Beacon", Vector3.new(1.4, 1.4, 1.4), spire * CFrame.new(0, 99.4, 0), WHITE, M.Neon, GHOST)
	Common.light(beacon, CYAN, 24, 1.2)
	-- Hologram curtains between the towers, with scan lines
	for _, spot in { { 86, -48, 0.5 }, { 92, 56, -0.4 }, { -40, 80, 1.4 } } do
		local frame = CFrame.new(Vector3.new(c.X + spot[1], y, c.Z + spot[2])) * CFrame.Angles(0, spot[3], 0)
		block(ctx.model, "Curtain", Vector3.new(22, 14, 0.2), frame * CFrame.new(0, 9, 0), GLASS, M.Glass, { Transparency = 0.7, CastShadow = false, CanCollide = false, CanQuery = false })
		block(ctx.model, "CurtainRail", Vector3.new(23, 0.8, 1), frame * CFrame.new(0, 1.6, 0), vary(STEEL, random, 0.03), M.SmoothPlastic, SMALL)
		for index = 1, 3 do
			block(ctx.model, "ScanLine", Vector3.new(22, 0.12, 0.1), frame * CFrame.new(0, 4 + index * 3.4, 0.15), CYAN, M.Neon, GHOST)
		end
	end
end

function DigitalGrid.build(ctx: Common.Context)
	floor(ctx)
	rim(ctx)
	Common.barriers(ctx)
	pillars(ctx)
	dataCubes(ctx)
	screen(ctx)
	cover(ctx)
	terminals(ctx)
	throwables(ctx)
	spawnPads(ctx)
	plain(ctx)
end

return DigitalGrid
