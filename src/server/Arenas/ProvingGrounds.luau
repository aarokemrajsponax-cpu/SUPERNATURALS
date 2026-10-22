-- Proving Grounds: the first arena. An old rune ring on a grassy hilltop where
-- fighters come to test new powers. Blue-grey flagstones with a worn bronze
-- inlay and a faint cyan sigil, a low stone parapet with corner obelisks that
-- hold rune crystals, a henge of standing stones outside the ring, a trilithon
-- gate with the arena's name, braziers, and pines on the hills around.
-- Palette: blue-grey slate and weathered grey stone (dominant), moss and bronze
-- (secondary), cyan rune light and warm fire (small accents).

local Common = require(script.Parent.Common)

local ProvingGrounds = {}

local M = Common.M
local rgb = Common.rgb
local block, cylinder, disc, wedge = Common.block, Common.cylinder, Common.disc, Common.wedge
local vary, pick = Common.vary, Common.pick
local SMALL, GHOST = Common.SMALL, Common.GHOST

local SLATE = { rgb(142, 138, 128), rgb(134, 132, 126), rgb(146, 140, 128) }
local JOINT = rgb(100, 95, 86)
local SIGIL = rgb(110, 112, 114)
local STONE = rgb(128, 124, 116)
local STONE_PALE = rgb(150, 145, 134)
local STONE_DARK = rgb(102, 100, 96)
local MOSS = rgb(86, 102, 56)
local BRONZE = rgb(164, 126, 72)
local IRON = rgb(56, 54, 52)
local WOOD = rgb(112, 82, 58)
local CLOTH = rgb(46, 80, 88)
local RUNE = rgb(120, 222, 236)
local RUNE_GLASS = rgb(150, 220, 230)
local FLAME = rgb(255, 168, 96)
local NEEDLES = { rgb(46, 70, 52), rgb(54, 78, 56), rgb(42, 62, 48) }
local BARK = rgb(78, 60, 46)

-- Scenery: the hilltop, a ridge behind the gate (+X) and hills to the sides
-- hiding the next slots. Hills are { x, y, z, radius } from the slot centre.
local HILLS = {
	-- The ridge behind the gate: broad, overlapping swells
	{ 140, -26, -58, 50 },
	{ 150, -16, 6, 48 },
	{ 132, -30, 54, 52 },
	{ 112, -12, -24, 20 },
	{ 108, -14, 30, 22 },
	-- Lumps along the side banks
	{ -40, -6, 92, 15 },
	{ -8, -4, 94, 13 },
	{ 30, -8, 90, 17 },
	{ 70, -6, 92, 15 },
	{ -36, -8, -90, 17 },
	{ 0, -5, -94, 13 },
	{ 38, -6, -92, 15 },
	{ 74, -9, -90, 17 },
}
-- Banks rising from the apron toward each side: { z from, z to, height }
local BANKS = { { 62, 106, 9 }, { -62, -106, 9 } }
local PLATEAU = 0.5

-- Height of the ground at (x, z) from the slot centre
local function groundAt(x: number, z: number): number
	local y = PLATEAU
	for _, bank in BANKS do
		local share = (z - bank[1]) / (bank[2] - bank[1])
		if share > 0 and share <= 1 and x > -62 and x < 104 then
			y = math.max(y, PLATEAU + share * bank[3])
		end
	end
	for _, hill in HILLS do
		local d2 = (x - hill[1]) ^ 2 + (z - hill[3]) ^ 2
		if d2 < hill[4] ^ 2 then
			y = math.max(y, hill[2] + math.sqrt(hill[4] ^ 2 - d2))
		end
	end
	return y
end

local function terrain(ctx: Common.Context)
	local c = ctx.center
	Common.fill(ctx, "FillBlock", CFrame.new(c + Vector3.new(68, -6.75, 0)), Vector3.new(262, 14.5, 214), M.Grass)
	for _, bank in BANKS do
		-- A wedge whose slope climbs from the apron toward the slot's edge
		local length = math.abs(bank[2] - bank[1])
		local mid = c + Vector3.new(21, PLATEAU + bank[3] / 2, (bank[1] + bank[2]) / 2)
		local facing = if bank[2] > 0 then 0 else math.pi
		Common.fill(ctx, "FillWedge", CFrame.new(mid) * CFrame.Angles(0, facing, 0), Vector3.new(166, bank[3], length), M.Grass)
	end
	for _, hill in HILLS do
		Common.fill(ctx, "FillBall", c + Vector3.new(hill[1], hill[2], hill[3]), hill[4], M.Grass)
	end
	-- Rock showing through the slopes
	local random = ctx.random
	for _, spot in { { 112, -36 }, { 118, 14 }, { 104, 44 }, { 126, -8 }, { -24, 88 }, { 22, -90 }, { 52, 86 } } do
		local y = groundAt(spot[1], spot[2]) - 1
		local frame = CFrame.new(c + Vector3.new(spot[1], y, spot[2])) * CFrame.Angles(random:NextNumber(-0.4, 0.4), random:NextNumber(0, 3), random:NextNumber(-0.3, 0.3))
		Common.fill(ctx, "FillBlock", frame, Vector3.new(random:NextNumber(8, 13), random:NextNumber(5, 8), random:NextNumber(7, 11)), M.Rock)
	end
	-- Worn earth where people walk up to the gate and round the ring
	for _, spot in { { 64, -14, 4 }, { 64, 12, 3.5 }, { 74, 0, 4 }, { -61, 30, 2.5 }, { -61, -18, 3 } } do
		Common.fill(ctx, "FillCylinder", CFrame.new(c + Vector3.new(spot[1], 0.2, spot[2])), 1, spot[3], M.Ground)
	end
end

-- The floor: blue-grey flagstones with a pale sigil disc in the middle
local function floor(ctx: Common.Context)
	local top = ctx.top
	Common.floor(ctx, JOINT, M.Slate)
	Common.flagstones(ctx, {
		colors = SLATE,
		material = M.Slate,
		rowMin = 9,
		rowMax = 14,
		lengthMin = 10,
		lengthMax = 19,
		gap = 0.35,
		jitter = 0.035,
		skip = function(position: Vector3)
			local offset = position - top
			return Vector3.new(offset.X, 0, offset.Z).Magnitude < 12
		end,
	})
	-- Moss creeping into the joints near the parapet
	local random = ctx.random
	for _, spot in { { -50, -20 }, { -48, 34 }, { 46, 50 }, { 51, -42 }, { 20, -51 } } do
		block(ctx.model, "Moss", Vector3.new(random:NextNumber(3, 6), 0.12, random:NextNumber(1, 2)), CFrame.new(top + Vector3.new(spot[1], 0.14, spot[2])) * CFrame.Angles(0, random:NextNumber(0, 3), 0), vary(MOSS, random, 0.06), M.Grass, GHOST)
	end

	-- Sigil: pale disc, bronze ring, a broken cyan rune ring and the Node at its heart
	disc(ctx.model, "Sigil", top + Vector3.new(0, 0.12, 0), 25, 0.3, vary(SIGIL, random, 0.02), M.Slate, GHOST)
	Common.ring(ctx, top, 11.8, 14, 0.3, BRONZE, M.Metal, 0.18)
	Common.ring(ctx, top, 8, 12, 0.2, RUNE, M.Neon, 0.17, { 3, 8 })
	local node = disc(ctx.model, "Node", top + Vector3.new(0, 0.2, 0), 4.6, 0.3, vary(STONE_DARK, random, 0.02), M.Slate, { CastShadow = false, CanCollide = false })
	Common.interactive(node, "Node")
	disc(ctx.model, "NodeCore", top + Vector3.new(0, 0.24, 0), 1.6, 0.1, RUNE, M.Neon, GHOST)

	-- The outer bronze ring, worn through in two places, with rune marks
	Common.ring(ctx, top, 35, 24, 0.3, BRONZE, M.Metal, 0.14, { 5, 15 })
	for index = 0, 7 do
		local angle = (index + 0.5) / 8 * math.pi * 2
		local position = top + Vector3.new(math.cos(angle) * 37.2, 0.14, math.sin(angle) * 37.2)
		block(ctx.model, "Rune", Vector3.new(2.2, 0.12, 0.3), CFrame.new(position) * CFrame.Angles(0, -angle, 0), RUNE, M.Neon, GHOST)
	end
	-- Scorch marks from powers tested here
	for _, spot in { { -17, 9, 7 }, { 14, -19, 5 }, { 24, 15, 4 } } do
		disc(ctx.model, "Scorch", top + Vector3.new(spot[1], 0.15 + spot[3] * 0.002, spot[2]), spot[3], 0.1, rgb(108, 102, 94), M.Slate, GHOST)
	end
end

-- A low stone parapet in uneven blocks, with pale caps; one stretch repaired
-- in darker stone, one block cracked down
local function parapet(ctx: Common.Context)
	local random = ctx.random
	local top = ctx.top
	local height = 2.6
	for side = 1, 4 do
		local normal = ({ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) })[side]
		local along = Vector3.new(normal.Z, 0, -normal.X)
		local x = -55
		local index = 0
		while x < 55 - 0.01 do
			index += 1
			local length = math.min(random:NextNumber(17, 26), 55 - x)
			if 55 - (x + length) < 10 then
				length = 55 - x
			end
			local repaired = side == 2 and index == 2
			local cracked = side == 3 and index == 3
			local h = height + random:NextNumber(-0.15, 0.15) - (if cracked then 0.9 else 0)
			local mid = top + normal * 56.2 + along * (x + length / 2)
			local frame = Common.lookAt(mid, mid + normal)
			local color = if repaired then vary(STONE_DARK, random, 0.03) else vary(STONE, random, 0.05)
			block(ctx.model, "Parapet", Vector3.new(length - 0.15, h + 2, 2.4), frame * CFrame.new(0, h / 2 - 1, 0), color, M.Slate)
			if not cracked then
				block(ctx.model, "ParapetCap", Vector3.new(length + 0.1, 0.5, 3), frame * CFrame.new(0, h + 0.2, 0), vary(STONE_PALE, random, 0.04), M.Slate)
			else
				Common.rubble(ctx, mid + normal * 2.6 + Vector3.new(0, -0.4, 0), 2.4, 4, { STONE, STONE_PALE }, M.Slate)
			end
			x += length
			-- A pier where two stretches meet, a little taller, with its own cap
			if x < 55 - 0.01 then
				local joint = top + normal * 56.4 + along * x
				local pier = Common.lookAt(joint, joint + normal)
				block(ctx.model, "Pier", Vector3.new(2.6, height + 3, 3.2), pier * CFrame.new(0, (height + 3) / 2 - 1.6, 0), vary(STONE_DARK, random, 0.04), M.Slate)
				block(ctx.model, "PierCap", Vector3.new(3.2, 0.6, 3.8), pier * CFrame.new(0, height + 1.65, 0), vary(STONE_PALE, random, 0.04), M.Slate, SMALL)
				-- Banners on the side walls, hung from the outer face of a pier
				if side >= 3 and index % 2 == 1 then
					local mount = pier * CFrame.new(0, 0, -1.9)
					cylinder(ctx.model, "BannerPole", mount * CFrame.new(0, height + 4.6, 0), 9, 0.36, IRON, M.Metal, SMALL)
					block(ctx.model, "BannerBar", Vector3.new(3.4, 0.24, 0.24), mount * CFrame.new(0, height + 8.4, -0.1), IRON, M.Metal, SMALL)
					block(ctx.model, "Banner", Vector3.new(2.8, 6.2, 0.12), mount * CFrame.new(0, height + 5.2, -0.3) * CFrame.Angles(random:NextNumber(-0.03, 0.03), 0, 0), vary(CLOTH, random, 0.05), M.Fabric, SMALL)
					block(ctx.model, "BannerTrim", Vector3.new(2.8, 0.4, 0.14), mount * CFrame.new(0, height + 2.3, -0.3), BRONZE, M.Fabric, SMALL)
				end
			end
		end
		-- A kerb of long stones where the floor meets the wall
		local kerb = top + normal * 54.3
		block(ctx.model, "Kerb", Vector3.new(110, 0.5, 1.6), Common.lookAt(kerb, kerb + normal) * CFrame.new(0, 0.1, 0), vary(STONE_DARK, random, 0.03), M.Slate, GHOST)
	end
end

-- Corner bastions, each carrying an obelisk with a rune crystal at the top.
-- Two of them (away from the spawns' diagonal) are Pylons powers can take over.
local function obelisks(ctx: Common.Context)
	local random = ctx.random
	for index, corner in { { 1, -1 }, { -1, 1 }, { 1, 1 }, { -1, -1 } } do
		local base = ctx.top + Vector3.new(corner[1] * 59, 0, corner[2] * 59)
		local face = Common.lookAt(Vector3.new(base.X, 0, base.Z), Vector3.new(ctx.top.X, 0, ctx.top.Z))
		local frame = CFrame.new(base) * face.Rotation
		block(ctx.model, "Bastion", Vector3.new(8, 6, 8), frame * CFrame.new(0, 0, 0), vary(STONE, random, 0.04), M.Slate)
		block(ctx.model, "BastionCap", Vector3.new(8.6, 0.6, 8.6), frame * CFrame.new(0, 3.2, 0), vary(STONE_PALE, random, 0.04), M.Slate)
		local lean = CFrame.Angles(random:NextNumber(-0.015, 0.015), 0, random:NextNumber(-0.015, 0.015))
		local shaft = frame * CFrame.new(0, 3.5, 0) * lean
		block(ctx.model, "Plinth", Vector3.new(4.4, 1.4, 4.4), shaft * CFrame.new(0, 0.7, 0), vary(STONE_DARK, random, 0.03), M.Slate)
		local lower = block(ctx.model, "Obelisk", Vector3.new(3.2, 9, 3.2), shaft * CFrame.new(0, 5.9, 0), vary(STONE, random, 0.05), M.Slate)
		block(ctx.model, "Band", Vector3.new(3.6, 0.6, 3.6), shaft * CFrame.new(0, 10.6, 0), vary(STONE_PALE, random, 0.04), M.Slate, SMALL)
		block(ctx.model, "Obelisk", Vector3.new(2.6, 6, 2.6), shaft * CFrame.new(0, 13.9, 0), vary(STONE, random, 0.05), M.Slate)
		cylinder(ctx.model, "Collar", shaft * CFrame.new(0, 17.2, 0), 0.8, 3.1, BRONZE, M.Metal, SMALL)
		local crystal = Common.crystal(ctx, (shaft * CFrame.new(0, 18.6, 0)).Position, 2.2, RUNE_GLASS, RUNE, random:NextNumber(0, 1))
		Common.light(crystal, RUNE, 18, 1.1, index <= 2)
		-- Rune marks cut into the two faces that look at the ring
		for _, side in { -1, 1 } do
			block(ctx.model, "RuneMark", Vector3.new(0.35, 3.4, 0.12), shaft * CFrame.new(side * 0.8, 6.2, -1.62), RUNE, M.Neon, GHOST)
		end
		if index <= 2 then
			Common.interactive(lower, "Pylon")
		end
	end
end

-- Fire on the parapet: two at the side midpoints, two flanking the gate
local function braziers(ctx: Common.Context)
	local random = ctx.random
	for index, spot in { { 0, -1 }, { 0, 1 }, { 1, -0.3 }, { 1, 0.3 } } do
		local position: Vector3
		if spot[1] == 0 then
			position = ctx.top + Vector3.new(random:NextNumber(-4, 4), 3.1, spot[2] * 56.2)
		else
			position = ctx.top + Vector3.new(56.2, 3.1, if spot[2] > 0 then 13 else -13)
		end
		block(ctx.model, "BrazierFoot", Vector3.new(2, 0.8, 2), CFrame.new(position + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, random:NextNumber(-0.3, 0.3), 0), vary(IRON, random, 0.05), M.CorrodedMetal, SMALL)
		Common.fireBowl(ctx, position + Vector3.new(0, 1.85, 0), 2.8, vary(IRON, random, 0.05), FLAME, 20, 1.3, index <= 2)
	end
end

-- Standing stones inside the ring as cover, tangent to the circle so the
-- middle stays open
local function cover(ctx: Common.Context)
	local random = ctx.random
	for index, angle in { 0, 90, 180, 270 } do
		local radians = math.rad(angle + random:NextNumber(-6, 6))
		local out = Vector3.new(math.cos(radians), 0, math.sin(radians))
		local base = ctx.top + out * 29
		local frame = Common.lookAt(base, base + out) * CFrame.Angles(random:NextNumber(-0.05, 0.05), 0, random:NextNumber(-0.05, 0.05))
		local tall = random:NextNumber(7.5, 9)
		local color = vary(STONE, random, 0.06)
		block(ctx.model, "StandingStone", Vector3.new(6.4, tall + 1, 2.4), frame * CFrame.new(0, tall / 2 - 0.5, 0), color, M.Slate)
		-- A sloping, broken top instead of a flat box
		local slope = random:NextNumber(1.2, 2.2)
		local flip = if random:NextNumber() < 0.5 then 1 else -1
		wedge(ctx.model, "StandingStone", Vector3.new(2.4, slope, 6.4), frame * CFrame.new(0, tall + slope / 2, 0) * CFrame.Angles(0, flip * math.pi / 2, 0), color, M.Slate)
		block(ctx.model, "StoneMoss", Vector3.new(2.6, 0.35, 2.5), frame * CFrame.new(-flip * 2.0, 0.1, -0.1) * CFrame.Angles(0, 0, random:NextNumber(-0.06, 0.06)), vary(MOSS, random, 0.06), M.Grass, GHOST)
		local side = if index % 2 == 0 then 1 else -1
		block(ctx.model, "StandingStone", Vector3.new(2.8, 4.8, 2.2), frame * CFrame.new(side * 5, 1.9, 0.6) * CFrame.Angles(0, side * 0.25, side * 0.08), vary(STONE_DARK, random, 0.05), M.Slate)
		Common.rubble(ctx, (frame * CFrame.new(-side * 4.4, 0, -1.4)).Position, 1.6, 2, { STONE, STONE_DARK }, M.Slate, 0.7)
	end
end

local function throwables(ctx: Common.Context)
	local random = ctx.random
	local function ground(u: number, v: number): Vector3
		return Common.at(ctx, u, 0, v)
	end
	local crate = vary(WOOD, random, 0.04)
	Common.throwable(ctx, "Crate", 1, Vector3.new(3, 3, 3), CFrame.new(ground(-0.6, 0.18) + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0.4, 0), crate, M.WoodPlanks)
	Common.throwable(ctx, "Crate", 1, Vector3.new(2.6, 2.6, 2.6), CFrame.new(ground(-0.22, -0.68) + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 1.1, 0), vary(WOOD, random, 0.05), M.WoodPlanks)
	Common.uprightThrowable(ctx, "Barrel", 1, ground(0.68, 0.4), 3.2, 2.4, 0, vary(rgb(104, 70, 48), random, 0.04), M.Wood)
	Common.throwable(ctx, "Boulder", 2, Vector3.new(5, 4, 4.6), CFrame.new(ground(0.56, -0.24) + Vector3.new(0, 1.8, 0)) * CFrame.Angles(0.1, 0.7, -0.08), vary(STONE_DARK, random, 0.05), M.Slate)
	Common.throwable(ctx, "Boulder", 2, Vector3.new(4.6, 3.6, 4.2), CFrame.new(ground(-0.6, -0.4) + Vector3.new(0, 1.6, 0)) * CFrame.Angles(-0.06, 2.1, 0.1), vary(STONE, random, 0.05), M.Slate)
	Common.uprightThrowable(ctx, "RuneDrum", 3, ground(0.26, 0.64), 4.6, 5.4, 0.3, vary(STONE_PALE, random, 0.03), M.Slate)
end

local function spawnPads(ctx: Common.Context)
	for _, spawn in Common.spawns(ctx) do
		local base = Common.spawnBase(spawn, ctx.floorY)
		disc(ctx.model, "SpawnRing", base + Vector3.new(0, 0.16, 0), 9, 0.2, BRONZE, M.Metal, GHOST)
		disc(ctx.model, "SpawnPad", base + Vector3.new(0, 0.2, 0), 8, 0.2, vary(STONE_PALE, ctx.random, 0.02), M.Slate, GHOST)
		disc(ctx.model, "SpawnRune", base + Vector3.new(0, 0.23, 0), 1.4, 0.1, RUNE, M.Neon, GHOST)
	end
end

-- The trilithon gate behind the far parapet, with the arena's name on the lintel
local function gate(ctx: Common.Context)
	local random = ctx.random
	local ground = ctx.center + Vector3.new(68, 0.5, 0)
	local face = Common.lookAt(ground, ground - Vector3.new(1, 0, 0))
	for _, side in { -1, 1 } do
		local foot = face * CFrame.new(side * 8.5, 0, 0) * CFrame.Angles(0, 0, side * 0.012)
		block(ctx.model, "GateFoot", Vector3.new(6, 2, 5.6), foot * CFrame.new(0, 0.4, 0), vary(STONE_DARK, random, 0.04), M.Slate)
		block(ctx.model, "GateStone", Vector3.new(4.6, 13, 4), foot * CFrame.new(0, 7.8, 0), vary(STONE, random, 0.05), M.Slate)
		block(ctx.model, "GateStone", Vector3.new(4.1, 6, 3.7), foot * CFrame.new(0, 17.2, 0), vary(STONE, random, 0.05), M.Slate)
	end
	local lintel = block(ctx.model, "Lintel", Vector3.new(23, 3.6, 4.6), face * CFrame.new(0.3, 21.9, 0) * CFrame.Angles(0, 0, 0.01), vary(STONE_PALE, random, 0.03), M.Slate)
	local plaque = block(ctx.model, "NamePlaque", Vector3.new(15, 2.4, 0.3), lintel.CFrame * CFrame.new(0, 0, -2.4), vary(STONE_DARK, random, 0.03), M.Slate, SMALL)
	Common.sign(plaque, Enum.NormalId.Front, "PROVING GROUNDS", rgb(206, 236, 238), 24, 0.4)
	block(ctx.model, "GateRune", Vector3.new(12, 0.18, 0.12), lintel.CFrame * CFrame.new(0, -1.5, -2.36), RUNE, M.Neon, GHOST)
	-- A second trilithon that fell long ago
	local fallen = ctx.center + Vector3.new(72, 0.5, -32)
	block(ctx.model, "GateStone", Vector3.new(4.4, 15, 3.8), CFrame.new(fallen + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0.3, 0.05), vary(STONE, random, 0.05), M.Slate)
	block(ctx.model, "Lintel", Vector3.new(19, 3.4, 4.4), CFrame.new(fallen + Vector3.new(-1, 2.2, 8)) * CFrame.Angles(0, 0.5, 0.16), vary(STONE_PALE, random, 0.04), M.Slate)
	block(ctx.model, "GateStone", Vector3.new(4.2, 13, 3.6), CFrame.new(fallen + Vector3.new(6, 1.4, 16)) * CFrame.Angles(math.rad(84), 0.7, 0), vary(STONE, random, 0.05), M.Slate)
end

-- A henge of standing stones on the apron outside the parapet, some leaning,
-- one fallen, with mossy rocks and pines further out
local function surroundings(ctx: Common.Context)
	local random = ctx.random
	local c = ctx.center
	local HENGE = { { -40, 66 }, { -22, 69 }, { -4, 67 }, { 15, 70 }, { 34, 66 }, { -36, -67 }, { -16, -70 }, { 6, -66 }, { 28, -69 }, { -63, -26 }, { -64, 12 } }
	for index, spot in HENGE do
		local base = c + Vector3.new(spot[1], math.min(groundAt(spot[1], spot[2]), 2), spot[2])
		local out = Vector3.new(spot[1], 0, spot[2]).Unit
		local frame = Common.lookAt(base, base + out) * CFrame.Angles(random:NextNumber(-0.08, 0.08), 0, random:NextNumber(-0.1, 0.1))
		local tall = random:NextNumber(5, 10)
		if index == 8 then
			block(ctx.model, "Henge", Vector3.new(3.6, 2.6, tall), frame * CFrame.new(0, 1, -tall / 2) * CFrame.Angles(0, 0.4, 0.1), vary(STONE, random, 0.06), M.Slate)
		else
			block(ctx.model, "Henge", Vector3.new(random:NextNumber(3, 4.4), tall + 1.5, random:NextNumber(2, 2.8)), frame * CFrame.new(0, tall / 2 - 0.75, 0), vary(STONE, random, 0.06), M.Slate)
		end
	end
	for _, spot in { { -62, 44 }, { -62, -48 }, { 66, 40 }, { 30, -63 }, { 46, 64 } } do
		Common.rock(ctx, c + Vector3.new(spot[1], groundAt(spot[1], spot[2]) - 0.2, spot[2]), Vector3.new(random:NextNumber(3.5, 6), random:NextNumber(2.4, 4), random:NextNumber(3, 5)), STONE_DARK, M.Slate, MOSS)
	end
	for _, spot in { { 92, -34, 22 }, { 100, 26, 26 }, { 116, -6, 19 }, { 18, 84, 17 }, { -28, -86, 20 } } do
		Common.pine(ctx, c + Vector3.new(spot[1], groundAt(spot[1], spot[2]) - 0.5, spot[2]), spot[3], pick(NEEDLES, random), BARK, if spot[3] < 20 then 2 else 3)
	end
end

function ProvingGrounds.build(ctx: Common.Context)
	terrain(ctx)
	floor(ctx)
	parapet(ctx)
	Common.barriers(ctx)
	obelisks(ctx)
	braziers(ctx)
	cover(ctx)
	throwables(ctx)
	spawnPads(ctx)
	gate(ctx)
	surroundings(ctx)
end

return ProvingGrounds
