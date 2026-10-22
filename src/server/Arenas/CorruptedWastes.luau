-- Corrupted Wastes: land the void broke through. Black basalt plates split by
-- violet cracks, a wound in the middle where the ground burst open, basalt
-- columns as cover and as the rim, void crystals growing out of the rock, and
-- shards of rock held up in the air by strands of void energy. A rift spire
-- with a floating monolith stands behind the arena's name stone.
-- Palette: near-black warm basalt (dominant), ash grey and dull plum stone
-- (secondary), violet void light (small accents).

local Common = require(script.Parent.Common)

local CorruptedWastes = {}

local M = Common.M
local rgb = Common.rgb
local block, disc, wedge = Common.block, Common.disc, Common.wedge
local vary, pick = Common.vary, Common.pick
local SMALL, GHOST = Common.SMALL, Common.GHOST

local BASALT = { rgb(96, 90, 92), rgb(88, 84, 87), rgb(104, 97, 96), rgb(82, 78, 84) }
local SEAM = rgb(86, 58, 114)
local ASH = rgb(124, 117, 116)
local PLUM = rgb(78, 66, 86)
local CRYSTAL = rgb(130, 86, 196)
local VOID = rgb(160, 108, 232)
local PALE = rgb(220, 198, 255)

-- Terrain ------------------------------------------------------------------------------------

local function terrain(ctx: Common.Context)
	local c = ctx.center
	local random = ctx.random
	Common.terrainColor(ctx, M.Basalt, rgb(80, 74, 78))
	Common.terrainColor(ctx, M.CrackedLava, rgb(92, 60, 128))
	Common.fill(ctx, "FillBlock", CFrame.new(c + Vector3.new(68, -6.75, 0)), Vector3.new(260, 14.5, 212), M.Basalt)
	-- Cracks in the ground running away from the arena
	for _, crack in { { 70, 20, 0.3, 50 }, { 64, -30, -0.5, 40 }, { -20, 70, 1.4, 36 }, { 30, -72, 1.8, 44 }, { -50, -64, 1.2, 24 }, { 100, 60, 0.9, 50 } } do
		local frame = CFrame.new(c + Vector3.new(crack[1], 0.2, crack[2])) * CFrame.Angles(0, crack[3], 0)
		Common.fill(ctx, "FillBlock", frame, Vector3.new(crack[4], 1, random:NextNumber(1.6, 2.6)), M.CrackedLava)
	end
	-- Broken ridges and cliffs all round, highest behind the rift
	-- Plates of ground shoved up and tilted where the void broke through:
	-- { x, z, length, height, depth, yaw, tilt }
	for _, plate in {
		{ 150, -40, 60, 26, 30, 0.3, 0.32 }, { 162, 30, 64, 34, 34, -0.2, -0.3 }, { 126, 72, 40, 18, 22, 0.8, 0.28 },
		{ 124, -78, 40, 16, 24, -0.6, -0.26 }, { -36, 92, 34, 14, 18, 0.2, 0.3 }, { 14, 94, 30, 18, 16, -0.1, -0.24 },
		{ 62, 92, 40, 16, 20, 0.15, 0.34 }, { -30, -92, 34, 16, 18, -0.2, -0.3 }, { 24, -94, 30, 14, 16, 0.3, 0.26 },
		{ 68, -92, 40, 18, 20, -0.1, -0.32 }, { 172, -4, 50, 46, 30, 1.5, 0.2 },
	} do
		local frame = CFrame.new(c + Vector3.new(plate[1], plate[4] * 0.2, plate[2])) * CFrame.Angles(0, plate[6], 0) * CFrame.Angles(plate[7], 0, plate[7] * 0.4)
		Common.fill(ctx, "FillBlock", frame, Vector3.new(plate[3], plate[4], plate[5]), M.Basalt)
	end
	-- Crags of bare rock sticking up out of the slopes
	for _, spot in { { 132, -20, 16 }, { 128, 30, 20 }, { 92, 84, 12 }, { -48, 84, 10 }, { 40, -86, 14 }, { 100, -70, 12 } } do
		local frame = CFrame.new(c + Vector3.new(spot[1], spot[3] / 2, spot[2])) * CFrame.Angles(random:NextNumber(-0.25, 0.25), random:NextNumber(0, 3), random:NextNumber(-0.25, 0.25))
		Common.fill(ctx, "FillBlock", frame, Vector3.new(random:NextNumber(6, 10), spot[3] + 4, random:NextNumber(6, 10)), M.Slate)
	end
end

-- Floor --------------------------------------------------------------------------------------

local function floor(ctx: Common.Context)
	local top = ctx.top
	local random = ctx.random
	Common.floor(ctx, SEAM, M.CrackedLava)
	Common.flagstones(ctx, {
		colors = BASALT,
		material = M.Basalt,
		rowMin = 9,
		rowMax = 16,
		lengthMin = 9,
		lengthMax = 19,
		gap = 0.6,
		jitter = 0.06,
		skip = function(position: Vector3)
			local offset = position - top
			return Vector3.new(offset.X, 0, offset.Z).Magnitude < 9
		end,
	})
	-- Glowing cracks: jagged lines leaving the wound
	for index = 0, 4 do
		local angle = index / 5 * math.pi * 2 + random:NextNumber(-0.3, 0.3)
		local point = top + Vector3.new(math.cos(angle) * 7, 0.08, math.sin(angle) * 7)
		for _ = 1, 3 do
			angle += random:NextNumber(-0.5, 0.5)
			local length = random:NextNumber(4, 7)
			local next = point + Vector3.new(math.cos(angle) * length, 0, math.sin(angle) * length)
			Common.strut(ctx.model, "Crack", point, next, 0.22, 0.1, VOID, M.Neon, GHOST)
			point = next
		end
	end
	-- The wound: a dark round where the plates lifted, edged with broken slabs
	disc(ctx.model, "Wound", top + Vector3.new(0, 0.04, 0), 18, 0.2, rgb(40, 34, 46), M.Basalt, GHOST)
	for index = 0, 6 do
		local angle = index / 7 * math.pi * 2 + random:NextNumber(-0.15, 0.15)
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local at = top + out * random:NextNumber(7, 8.5) + Vector3.new(0, 0.25, 0)
		block(ctx.model, "LiftedSlab", Vector3.new(random:NextNumber(3, 5), 0.6, random:NextNumber(2.2, 3.4)), Common.lookAt(at, at + out) * CFrame.Angles(random:NextNumber(0.15, 0.3), random:NextNumber(-0.3, 0.3), 0), vary(pick(BASALT, random), random, 0.05), M.Basalt, GHOST)
	end
	local node = disc(ctx.model, "Node", top + Vector3.new(0, 0.12, 0), 5, 0.2, rgb(52, 40, 66), M.CrackedLava, { CastShadow = false, CanCollide = false })
	disc(ctx.model, "NodeCore", top + Vector3.new(0, 0.16, 0), 2, 0.1, VOID, M.Neon, GHOST)
	Common.light(node, VOID, 16, 0.9)
	Common.motes(node, ASH, 2, { texture = Common.SMOKE, size = 3, alpha = 0.8, minSpeed = 0.3, maxSpeed = 0.8, lightEmission = 0, minLife = 5, maxLife = 8 })
	-- Ash drifted against the edges
	for _, spot in { { -48, 20 }, { 44, 48 }, { 50, -30 }, { -20, -50 }, { 12, 50 } } do
		block(ctx.model, "Ash", Vector3.new(random:NextNumber(5, 9), 0.14, random:NextNumber(1.6, 3)), CFrame.new(top + Vector3.new(spot[1], 0.1, spot[2])) * CFrame.Angles(0, random:NextNumber(0, 3), 0), vary(ASH, random, 0.05), M.Slate, GHOST)
	end
end

-- Rim: a low wall of basalt columns, uneven, with taller clusters at the corners
local function rim(ctx: Common.Context)
	local random = ctx.random
	for _, normal in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local tangent = Vector3.new(normal.Z, 0, -normal.X)
		local along = -55
		while along < 55 - 0.01 do
			local length = math.min(random:NextNumber(7, 12), 55 - along)
			if 55 - (along + length) < 4 then
				length = 55 - along
			end
			local height = random:NextNumber(1.6, 3.4)
			local mid = ctx.top + normal * random:NextNumber(57, 57.8) + tangent * (along + length / 2)
			local frame = Common.lookAt(mid, mid + normal) * CFrame.Angles(0, random:NextNumber(-0.04, 0.04), 0)
			block(ctx.model, "RimColumn", Vector3.new(length - 0.3, height + 2, random:NextNumber(3.4, 4.4)), frame * CFrame.new(0, height / 2 - 1, 0), vary(pick(BASALT, random), random, 0.05), M.Basalt)
			along += length
		end
	end
	for index, corner in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
		local base = ctx.top + Vector3.new(corner[1] * 59, -0.5, corner[2] * 59)
		for column = 1, 4 do
			local tall = ({ 13, 9, 6, 4 })[column] * random:NextNumber(0.8, 1.2) * (if index == 1 then 1.3 else 1)
			local width = random:NextNumber(3, 4.2)
			local offset = Vector3.new(random:NextNumber(-3.5, 3.5), 0, random:NextNumber(-3.5, 3.5))
			block(ctx.model, "Column", Vector3.new(width, tall, width * random:NextNumber(0.85, 1.1)), CFrame.new(base + offset + Vector3.new(0, tall / 2, 0)) * CFrame.Angles(random:NextNumber(-0.04, 0.04), random:NextNumber(0, 1), random:NextNumber(-0.04, 0.04)), vary(pick(BASALT, random), random, 0.05), M.Basalt)
		end
	end
end

-- A void crystal: a long glass prism around a glowing core, with a pointed tip
local function spike(ctx: Common.Context, base: Vector3, length: number, width: number, tilt: CFrame, lit: boolean?): BasePart
	local frame = CFrame.new(base) * tilt
	local glass = block(ctx.model, "VoidCrystal", Vector3.new(width, length, width), frame * CFrame.new(0, length / 2, 0), CRYSTAL, M.Glass, { Transparency = 0.3, Reflectance = 0.1, CastShadow = false })
	block(ctx.model, "VoidCore", Vector3.new(width * 0.4, length * 0.85, width * 0.4), frame * CFrame.new(0, length / 2, 0), VOID, M.Neon, GHOST)
	local tip = width * 1.1
	for _, turn in { 0, math.pi } do
		wedge(ctx.model, "VoidCrystal", Vector3.new(width, tip, width / 2), frame * CFrame.new(0, length + tip / 2, 0) * CFrame.Angles(0, turn, 0) * CFrame.new(0, 0, width / 4) * CFrame.Angles(0, math.pi, 0), CRYSTAL, M.Glass, { Transparency = 0.3, CastShadow = false, CanCollide = false })
	end
	if lit then
		Common.light(glass, VOID, 18, 1.2)
	end
	return glass
end

local function crystals(ctx: Common.Context)
	local random = ctx.random
	-- Clusters just outside the rim, odd numbers, big-medium-small
	local clusters = { { -0.6, 1.16 }, { 0.5, -1.16 }, { 1.16, 0.62 }, { -1.16, -0.3 }, { 0.12, 1.2 } }
	for index, spot in clusters do
		local base = Common.at(ctx, spot[1], -0.5, spot[2])
		for piece = 1, 3 do
			local length = ({ 8, 5, 3 })[piece] * random:NextNumber(0.8, 1.2)
			local tilt = CFrame.Angles(random:NextNumber(-0.45, 0.45), random:NextNumber(0, 3), random:NextNumber(-0.45, 0.45))
			spike(ctx, base + Vector3.new(random:NextNumber(-2, 2), 0, random:NextNumber(-2, 2)), length, ({ 1.8, 1.3, 0.9 })[piece], tilt, piece == 1 and index <= 4)
		end
	end
	-- The great crystal by the far corner: the Pylon
	local base = ctx.top + Vector3.new(66, -0.5, -64)
	local pylon = spike(ctx, base, 16, 3.4, CFrame.Angles(0.08, 0.4, -0.1), true)
	Common.interactive(pylon, "Pylon")
	spike(ctx, base + Vector3.new(3, 0, 2), 9, 2.2, CFrame.Angles(-0.3, 1.2, 0.35), false)
	spike(ctx, base + Vector3.new(-2.5, 0, 3), 6, 1.6, CFrame.Angles(0.4, 2, -0.2), false)
	Common.motes(pylon, VOID, 3, { size = 0.3 })
end

-- Fissures by the north and south edges breathe void dust: the two Vents
local function vents(ctx: Common.Context)
	local random = ctx.random
	for _, v in { -0.8, 0.8 } do
		local at = Common.at(ctx, random:NextNumber(-0.15, 0.15), 0.1, v)
		local frame = CFrame.new(at) * CFrame.Angles(0, random:NextNumber(-0.3, 0.3), 0)
		local fissure = block(ctx.model, "Fissure", Vector3.new(9, 0.2, 2.2), frame, rgb(36, 30, 44), M.CrackedLava, { CastShadow = false, CanCollide = false })
		block(ctx.model, "FissureGlow", Vector3.new(7.6, 0.12, 0.5), frame * CFrame.new(0, 0.08, 0), VOID, M.Neon, GHOST)
		for _, side in { -1, 1 } do
			block(ctx.model, "FissureLip", Vector3.new(8, 0.7, 1.4), frame * CFrame.new(random:NextNumber(-0.6, 0.6), 0.15, side * 1.6) * CFrame.Angles(side * 0.2, 0, 0), vary(pick(BASALT, random), random, 0.05), M.Basalt, GHOST)
		end
		Common.interactive(fissure, "Vent")
		Common.light(fissure, VOID, 14, 0.9)
		Common.motes(fissure, rgb(120, 104, 140), 3, { texture = Common.SMOKE, size = 4, alpha = 0.75, minSpeed = 0.5, maxSpeed = 1.2, lightEmission = 0.1, minLife = 4, maxLife = 7, acceleration = Vector3.new(0, 0.4, 0) })
	end
end

-- Basalt column clusters as cover, crystals growing at the foot of some
local function cover(ctx: Common.Context)
	local random = ctx.random
	for index, degrees in { 0, 90, 180, 270 } do
		local angle = math.rad(degrees + random:NextNumber(-7, 7))
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local base = ctx.top + out * 29
		local frame = Common.lookAt(base, base + out)
		local flip = if index % 2 == 0 then 1 else -1
		for column, spec in { { -2, 7.5, 3.6 }, { 1.6, 5.4, 3.2 }, { 4.6, 3.2, 2.8 }, { -5, 4, 2.6 } } do
			local tall = spec[2] * random:NextNumber(0.9, 1.1)
			block(ctx.model, "Column", Vector3.new(spec[3], tall + 0.5, spec[3] * 1.1), frame * CFrame.new(flip * spec[1], tall / 2 - 0.25, random:NextNumber(-0.5, 0.5)) * CFrame.Angles(random:NextNumber(-0.03, 0.03), random:NextNumber(-0.3, 0.3), random:NextNumber(-0.03, 0.03)), vary(pick(BASALT, random), random, 0.05), M.Basalt)
			if column == 1 then
				block(ctx.model, "ColumnCap", Vector3.new(spec[3] + 0.2, 0.4, spec[3] * 1.1 + 0.2), frame * CFrame.new(flip * spec[1], tall + 0.1, 0) * CFrame.Angles(0.06, 0, -0.05), vary(ASH, random, 0.05), M.Slate, SMALL)
			end
		end
		if index % 2 == 1 then
			spike(ctx, (frame * CFrame.new(flip * 3.6, 0, 2.2)).Position, 2.6, 0.9, CFrame.Angles(0.5, 0, 0.2), false)
		end
	end
end

-- Rock shards held in the air by strands of void, each over its own crystal
local function shards(ctx: Common.Context)
	local random = ctx.random
	local c = ctx.center
	local function shard(ground: Vector3, height: number, size: number)
		local frame = CFrame.new(ground + Vector3.new(0, height, 0)) * CFrame.Angles(random:NextNumber(-0.2, 0.2), random:NextNumber(0, 3), random:NextNumber(-0.2, 0.2))
		local color = vary(pick(BASALT, random), random, 0.05)
		block(ctx.model, "Shard", Vector3.new(size, size * 0.4, size), frame, color, M.Basalt)
		-- An upside-down pyramid of four corner wedges under the slab
		local point = frame * CFrame.new(0, -size * 0.95, 0) * CFrame.Angles(math.pi, 0, 0)
		for quarter = 0, 3 do
			Common.cornerWedge(ctx.model, "Shard", Vector3.new(size / 2, size * 1.5, size / 2), point * CFrame.Angles(0, quarter * math.pi / 2, 0) * CFrame.new(-size / 4, 0, size / 4), color, M.Basalt)
		end
		block(ctx.model, "ShardTop", Vector3.new(size * 0.8, 0.3, size * 0.7), frame * CFrame.new(0, size * 0.2 + 0.1, 0) * CFrame.Angles(0, 0.3, 0), vary(ASH, random, 0.05), M.Slate, GHOST)
		local bottom = (frame * CFrame.new(0, -size * 1.7, 0)).Position
		Common.strut(ctx.model, "Strand", ground + Vector3.new(0, 1.5, 0), bottom, 0.18, 0.18, VOID, M.Neon, GHOST)
		disc(ctx.model, "Rune", ground + Vector3.new(0, 0.6, 0), 3, 0.2, VOID, M.Neon, GHOST)
		spike(ctx, ground, 2.4, 1, CFrame.Angles(0.2, 0, -0.15), false)
	end
	for _, spot in { { 74, -26, 18, 6 }, { 70, 34, 14, 5 }, { -12, 74, 16, 5.5 }, { 30, -76, 20, 7 }, { -40, -72, 12, 4.5 } } do
		shard(c + Vector3.new(spot[1], 0.5, spot[2]), spot[3], spot[4])
	end
end

-- The rift behind the east edge: a spire of crystal, a monolith hanging over
-- it on four strands, and the name stone in front
local function rift(ctx: Common.Context)
	local random = ctx.random
	local ground = ctx.center + Vector3.new(104, 0.5, 4)
	spike(ctx, ground, 30, 5, CFrame.Angles(0.05, 0.3, -0.06), true)
	spike(ctx, ground + Vector3.new(5, 0, -4), 18, 3.4, CFrame.Angles(-0.3, 1, 0.25), false)
	spike(ctx, ground + Vector3.new(-4, 0, 5), 13, 2.8, CFrame.Angles(0.35, 2, -0.2), true)
	local monolith = CFrame.new(ground + Vector3.new(0, 52, 0)) * CFrame.Angles(0.12, 0.5, 0.2)
	block(ctx.model, "Monolith", Vector3.new(12, 18, 7), monolith, vary(BASALT[3], random, 0.04), M.Basalt)
	wedge(ctx.model, "Monolith", Vector3.new(12, 6, 7), monolith * CFrame.new(0, -12, 0) * CFrame.Angles(math.pi, 0, 0), vary(BASALT[3], random, 0.04), M.Basalt)
	for _, corner in { { -5, -3 }, { 5, 3 }, { 5, -3 }, { -5, 3 } } do
		local from = (monolith * CFrame.new(corner[1], -9, corner[2])).Position
		local to = ground + Vector3.new(corner[1] * 3.6, 0.6, corner[2] * 5)
		Common.strut(ctx.model, "Strand", to, from, 0.25, 0.25, VOID, M.Neon, GHOST)
	end
	-- The name stone, cracked and leaning a little
	local stoneAt = ctx.center + Vector3.new(64, 0.5, 0)
	local face = Common.lookAt(stoneAt, stoneAt - Vector3.new(1, 0, 0)) * CFrame.Angles(0, 0, 0.03)
	block(ctx.model, "NameBase", Vector3.new(24, 2, 5), face * CFrame.new(0, 0.5, 0), vary(BASALT[2], random, 0.04), M.Basalt)
	local slab = block(ctx.model, "NameStone", Vector3.new(21, 6.5, 2.4), face * CFrame.new(0, 4.6, 0), vary(BASALT[1], random, 0.04), M.Basalt)
	wedge(ctx.model, "NameStone", Vector3.new(2.4, 2.4, 8), face * CFrame.new(6, 9, 0) * CFrame.Angles(0, -math.pi / 2, 0), slab.Color, M.Basalt)
	Common.sign(slab, Enum.NormalId.Front, "CORRUPTED WASTES", PALE, 24, 0.3)
	block(ctx.model, "NameCrack", Vector3.new(0.25, 5, 0.12), face * CFrame.new(-7, 4.4, -1.22) * CFrame.Angles(0, 0, 0.25), VOID, M.Neon, GHOST)
end

local function throwables(ctx: Common.Context)
	local random = ctx.random
	local function ground(u: number, v: number): Vector3
		return Common.at(ctx, u, 0, v)
	end
	Common.throwable(ctx, "AshRock", 1, Vector3.new(3, 2.6, 3), CFrame.new(ground(-0.58, 0.32) + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0.1, 0.5, 0), vary(ASH, random, 0.05), M.Slate)
	Common.throwable(ctx, "Geode", 1, Vector3.new(2.6, 2.6, 2.6), CFrame.new(ground(-0.26, -0.64) + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 1.1, 0.2), vary(PLUM, random, 0.05), M.Basalt)
	Common.throwable(ctx, "Shardling", 1, Vector3.new(2.4, 3.4, 2.4), CFrame.new(ground(0.62, 0.42) + Vector3.new(0, 1.7, 0)) * CFrame.Angles(0, 0.4, 0), CRYSTAL, M.Glass)
	Common.throwable(ctx, "BasaltBlock", 2, Vector3.new(4.4, 3.6, 4.2), CFrame.new(ground(0.52, -0.3) + Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, 0.7, 0), vary(BASALT[1], random, 0.05), M.Basalt)
	Common.throwable(ctx, "Boulder", 2, Vector3.new(4.6, 3.6, 4.2), CFrame.new(ground(-0.62, -0.38) + Vector3.new(0, 1.6, 0)) * CFrame.Angles(-0.06, 2.1, 0.1), vary(BASALT[3], random, 0.05), M.Basalt)
	Common.throwable(ctx, "FallenColumn", 3, Vector3.new(4.6, 7, 4.6), CFrame.new(ground(0.24, 0.64) + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0.5, 0), vary(BASALT[2], random, 0.04), M.Basalt)
end

local function spawnPads(ctx: Common.Context)
	for _, spawn in Common.spawns(ctx) do
		local base = Common.spawnBase(spawn, ctx.floorY)
		disc(ctx.model, "SpawnRing", base + Vector3.new(0, 0.14, 0), 9, 0.2, PLUM, M.Slate, GHOST)
		disc(ctx.model, "SpawnPad", base + Vector3.new(0, 0.18, 0), 8.2, 0.2, vary(BASALT[3], ctx.random, 0.02), M.Basalt, GHOST)
		disc(ctx.model, "SpawnMark", base + Vector3.new(0, 0.21, 0), 1.4, 0.1, VOID, M.Neon, GHOST)
	end
end

function CorruptedWastes.build(ctx: Common.Context)
	terrain(ctx)
	floor(ctx)
	rim(ctx)
	Common.barriers(ctx)
	crystals(ctx)
	vents(ctx)
	cover(ctx)
	shards(ctx)
	rift(ctx)
	throwables(ctx)
	spawnPads(ctx)
end

return CorruptedWastes
