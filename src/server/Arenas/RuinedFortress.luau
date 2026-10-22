-- Ruined Fortress: the courtyard of a castle that fell a long time ago. Worn
-- flagstones with a crest in the middle, curtain walls standing at every height
-- from full battlements to rubble, round towers in the corners (one still
-- whole, one a stump), a gatehouse with a half-raised portcullis and the
-- arena's name, and the broken keep on the crag behind it. Inside: a broken
-- arch, a well, a tipped cart and a stretch of wall as cover.
-- Palette: warm grey stone (dominant), oak and ivy (secondary), red cloth and
-- warm fire (small accents). No glow beyond the fire.

local Common = require(script.Parent.Common)

local RuinedFortress = {}

local M = Common.M
local rgb = Common.rgb
local block, cylinder, disc, wedge = Common.block, Common.cylinder, Common.disc, Common.wedge
local vary, pick = Common.vary, Common.pick
local SMALL, GHOST = Common.SMALL, Common.GHOST

local FLAGS = { rgb(138, 130, 116), rgb(128, 122, 110), rgb(146, 136, 120), rgb(122, 116, 106) }
local JOINT = rgb(88, 80, 70)
local STONE = rgb(128, 121, 109)
local STONE_PALE = rgb(150, 142, 127)
local STONE_DARK = rgb(102, 96, 88)
local EARTH = rgb(104, 88, 68)
local MOSS = rgb(82, 96, 52)
local IVY = { rgb(60, 82, 42), rgb(54, 74, 40), rgb(70, 88, 46) }
local OAK = rgb(104, 76, 52)
local OAK_DARK = rgb(76, 56, 40)
local IRON = rgb(54, 52, 50)
local CLOTH = rgb(120, 36, 32)
local OCHRE = rgb(178, 140, 74)
local WATER = rgb(36, 50, 48)
local FLAME = rgb(255, 160, 84)
local NEEDLES = { rgb(46, 68, 50), rgb(52, 74, 52) }
local BARK = rgb(78, 60, 46)

-- Centre line and thickness of the curtain walls (inner face just past the barrier)
local WALL_OUT = 58
local THICK = 3.6

-- Each side's walls between the corner towers (along runs -52 to 52):
-- { length, height, kind }; "gate" leaves room for the gatehouse
local SIDES = {
	{ normal = Vector3.new(1, 0, 0), runs = { { 24, 13, "full" }, { 16, 9, "broken" }, { 24, 0, "gate" }, { 16, 7, "broken" }, { 24, 12, "full" } } },
	{ normal = Vector3.new(0, 0, 1), runs = { { 18, 6, "broken" }, { 14, 1.5, "breach" }, { 22, 4, "broken" }, { 20, 9, "broken" }, { 12, 2, "breach" }, { 18, 5, "broken" } } },
	{ normal = Vector3.new(0, 0, -1), runs = { { 30, 15, "full" }, { 18, 10, "broken" }, { 26, 15, "full" }, { 14, 6, "broken" }, { 16, 12, "full" } } },
	{ normal = Vector3.new(-1, 0, 0), runs = { { 22, 10, "full" }, { 16, 2.5, "breach" }, { 28, 9, "broken" }, { 38, 11, "full" } } },
}

-- A frame on a side, `along` the wall and `out` from the centre, at floor
-- height, whose front (-Z) faces outward
local function sideFrame(ctx: Common.Context, normal: Vector3, along: number, out: number): CFrame
	local tangent = Vector3.new(normal.Z, 0, -normal.X)
	local position = ctx.top + normal * out + tangent * along
	return Common.lookAt(position, position + normal)
end

-- Terrain ------------------------------------------------------------------------------------

local function terrain(ctx: Common.Context)
	local c = ctx.center
	local random = ctx.random
	-- Grass all round, trodden earth where the castle stands
	Common.fill(ctx, "FillBlock", CFrame.new(c + Vector3.new(68, -6.75, 0)), Vector3.new(260, 14.5, 212), M.Grass)
	Common.fill(ctx, "FillBlock", CFrame.new(c + Vector3.new(2, -0.5, 0)), Vector3.new(132, 2, 134), M.Ground)
	for _, spot in { { -40, 72, 7 }, { 64, -46, 8 }, { 20, 66, 10 }, { -30, -66, 7 }, { 74, 18, 6 } } do
		Common.fill(ctx, "FillCylinder", CFrame.new(c + Vector3.new(spot[1], 0.1, spot[2])), 1.2, spot[3], M.Mud)
	end
	-- The crag the keep stands on, with grassy shoulders
	Common.fill(ctx, "FillBall", c + Vector3.new(142, -16, -4), 32, M.Rock)
	Common.fill(ctx, "FillBall", c + Vector3.new(124, -14, 18), 18, M.Rock)
	Common.fill(ctx, "FillBall", c + Vector3.new(160, -22, 40), 34, M.Grass)
	Common.fill(ctx, "FillBall", c + Vector3.new(158, -24, -48), 36, M.Grass)
	Common.fill(ctx, "FillBall", c + Vector3.new(118, -10, -30), 16, M.Grass)
	-- Hills on both sides, hiding the next slots
	for _, hill in { { -40, -8, 90, 17 }, { 6, -6, 92, 15 }, { 50, -10, 89, 18 }, { 96, -12, 86, 21 }, { -34, -10, -90, 17 }, { 14, -6, -92, 15 }, { 60, -8, -89, 18 }, { 104, -14, -86, 21 } } do
		Common.fill(ctx, "FillBall", c + Vector3.new(hill[1], hill[2], hill[3]), hill[4], M.Grass)
	end
	-- Rock showing through the slopes
	for _, spot in { { 104, 30 }, { 96, -38 }, { 40, 84 }, { -20, -86 }, { 118, -16 } } do
		local frame = CFrame.new(c + Vector3.new(spot[1], 2, spot[2])) * CFrame.Angles(random:NextNumber(-0.4, 0.4), random:NextNumber(0, 3), random:NextNumber(-0.3, 0.3))
		Common.fill(ctx, "FillBlock", frame, Vector3.new(random:NextNumber(8, 12), random:NextNumber(5, 8), random:NextNumber(7, 10)), M.Rock)
	end
	-- The old road out of the gate
	Common.fill(ctx, "FillBlock", CFrame.new(c + Vector3.new(84, 0.1, 0)) * CFrame.Angles(0, 0.06, 0), Vector3.new(40, 1.2, 9), M.Ground)
end

-- Floor --------------------------------------------------------------------------------------

-- Patches where flagstones are long gone and the earth shows: { u, v, radius }
local HOLES = { { -0.42, 0.66, 5 }, { 0.72, -0.2, 4 }, { 0.12, -0.36, 3 }, { -0.75, -0.1, 3.5 } }

local function floor(ctx: Common.Context)
	local top = ctx.top
	local random = ctx.random
	Common.floor(ctx, JOINT, M.Slate)
	Common.flagstones(ctx, {
		colors = FLAGS,
		material = M.Slate,
		rowMin = 10,
		rowMax = 15,
		lengthMin = 12,
		lengthMax = 20,
		gap = 0.4,
		jitter = 0.045,
		skip = function(position: Vector3, size: Vector3)
			local offset = position - top
			if Vector3.new(offset.X, 0, offset.Z).Magnitude < 10.5 then
				return true
			end
			for _, hole in HOLES do
				if (Vector3.new(offset.X, 0, offset.Z) - Vector3.new(hole[1] * 55, 0, hole[2] * 55)).Magnitude < hole[3] + 2 then
					-- Earth where the stone was, a little sunk
					block(ctx.model, "Earth", size - Vector3.new(0, 0.1, 0), CFrame.new(position - Vector3.new(0, 0.08, 0)), vary(EARTH, random, 0.05), M.Ground, GHOST)
					return true
				end
			end
			return false
		end,
	})
	for _, hole in HOLES do
		Common.rubble(ctx, Common.at(ctx, hole[1], 0, hole[2]), hole[3], 2, { STONE, STONE_DARK }, M.Slate, 0.45)
	end
	-- Moss in the joints by the walls
	for _, spot in { { -50, 28 }, { 48, 46 }, { 12, 52 }, { -20, -52 } } do
		block(ctx.model, "Moss", Vector3.new(random:NextNumber(3, 6), 0.12, random:NextNumber(1, 2)), CFrame.new(top + Vector3.new(spot[1], 0.16, spot[2])) * CFrame.Angles(0, random:NextNumber(0, 3), 0), vary(MOSS, random, 0.06), M.Grass, GHOST)
	end

	-- The crest: a round of old cobbles, an iron band and the ward stone (a Node)
	disc(ctx.model, "Crest", top + Vector3.new(0, 0.1, 0), 21, 0.3, vary(STONE_DARK, random, 0.03), M.Cobblestone, GHOST)
	Common.ring(ctx, top, 10.2, 12, 0.5, vary(STONE_PALE, random, 0.03), M.Slate, 0.16)
	Common.ring(ctx, top, 6.4, 10, 0.25, IRON, M.Metal, 0.17, { 4 })
	for index = 0, 3 do
		local angle = index * math.pi / 2 + math.pi / 4
		local position = top + Vector3.new(math.cos(angle) * 8.2, 0.17, math.sin(angle) * 8.2)
		block(ctx.model, "CrestSpoke", Vector3.new(3, 0.12, 0.7), CFrame.new(position) * CFrame.Angles(0, -angle, 0), rgb(122, 72, 56), M.Brick, GHOST)
	end
	local ward = disc(ctx.model, "WardStone", top + Vector3.new(0, 0.26, 0), 5, 0.4, vary(STONE_PALE, random, 0.02), M.Slate, { CastShadow = false, CanCollide = false })
	Common.interactive(ward, "Node")
	disc(ctx.model, "WardBand", top + Vector3.new(0, 0.3, 0), 2.2, 0.1, OCHRE, M.Metal, GHOST)

	-- A drain gutter between the floor and the walls
	for _, side in SIDES do
		local frame = sideFrame(ctx, side.normal, 0, 55.7)
		block(ctx.model, "Gutter", Vector3.new(116, 0.6, 1.4), frame * CFrame.new(0, -0.35, 0), vary(STONE_DARK, random, 0.03), M.Slate, GHOST)
	end
end

-- Walls --------------------------------------------------------------------------------------

local function torch(ctx: Common.Context, frame: CFrame, shadows: boolean)
	-- `frame` sits on the wall's inner face, front facing out of the wall
	local random = ctx.random
	block(ctx.model, "TorchBracket", Vector3.new(0.4, 0.4, 1.6), frame * CFrame.new(0, 0.1, 0.8) * CFrame.Angles(0.25, 0, 0), vary(IRON, random, 0.05), M.Metal, SMALL)
	local head = block(ctx.model, "Torch", Vector3.new(0.7, 1.2, 0.7), frame * CFrame.new(0, 0.7, 1.5) * CFrame.Angles(-0.2, 0, 0), vary(OAK_DARK, random, 0.05), M.Wood, SMALL)
	local fire = Instance.new("Fire")
	fire.Size = 1.6
	fire.Heat = 5
	fire.Color = FLAME
	fire.SecondaryColor = rgb(200, 90, 40)
	fire.Parent = head
	Common.light(head, FLAME, 18, 1.3, shadows).Name = "Glow"
end

local function ivy(ctx: Common.Context, frame: CFrame, height: number, length: number)
	-- Strands hanging down the inner face from the top of the wall
	local random = ctx.random
	local x = random:NextNumber(-length / 2 + 2, length / 2 - 4)
	for _ = 1, 2 do
		local drop = random:NextNumber(height * 0.35, height * 0.8)
		local width = random:NextNumber(1.2, 2.6)
		block(ctx.model, "Ivy", Vector3.new(width, drop, 0.3), frame * CFrame.new(x, height - drop / 2 + 0.2, THICK / 2 + 0.12), vary(pick(IVY, random), random, 0.05), M.LeafyGrass, GHOST)
		x += width * random:NextNumber(0.6, 0.95)
	end
	block(ctx.model, "IvyTop", Vector3.new(4, 0.9, 1.4), frame * CFrame.new(x - 2, height + 0.2, THICK / 2 - 0.3), vary(pick(IVY, random), random, 0.05), M.LeafyGrass, GHOST)
end

local function banner(ctx: Common.Context, frame: CFrame, height: number, torn: boolean)
	local random = ctx.random
	local face = frame * CFrame.new(0, height, THICK / 2 + 0.35)
	block(ctx.model, "BannerRod", Vector3.new(4.2, 0.3, 0.3), face, IRON, M.Metal, SMALL)
	local long = if torn then 5 else 7.5
	block(ctx.model, "Banner", Vector3.new(3.4, long, 0.14), face * CFrame.new(0, -long / 2 - 0.1, 0.05) * CFrame.Angles(random:NextNumber(-0.02, 0.02), 0, random:NextNumber(-0.02, 0.02)), vary(CLOTH, random, 0.05), M.Fabric, SMALL)
	block(ctx.model, "BannerTrim", Vector3.new(3.4, 0.45, 0.16), face * CFrame.new(0, -long + 0.4, 0.05), OCHRE, M.Fabric, SMALL)
end

local function wallRun(ctx: Common.Context, normal: Vector3, from: number, length: number, height: number, kind: string, sideIndex: number, runIndex: number)
	local random = ctx.random
	local frame = sideFrame(ctx, normal, from + length / 2, WALL_OUT)
	local color = vary(STONE, random, 0.05)
	-- Footing course: wider, darker, a little sunk
	block(ctx.model, "WallFooting", Vector3.new(length + 0.2, 2.4, THICK + 1.2), frame * CFrame.new(0, -0.5, -0.3), vary(STONE_DARK, random, 0.04), M.Slate)
	if kind == "breach" then
		-- Only stumps left, and the stones that fell out of the gap
		for _, share in { -0.32, 0.3 } do
			local stump = random:NextNumber(1, height + 1)
			block(ctx.model, "Wall", Vector3.new(length * 0.3, stump + 1, THICK), frame * CFrame.new(share * length, stump / 2 - 0.5, 0) * CFrame.Angles(0, 0, random:NextNumber(-0.04, 0.04)), color, M.Cobblestone)
		end
		Common.rubble(ctx, (frame * CFrame.new(0, 0, -1)).Position, length * 0.32, 3, { STONE, STONE_PALE, STONE_DARK }, M.Slate, 1.2)
		return
	end
	block(ctx.model, "Wall", Vector3.new(length - 0.1, height + 1, THICK), frame * CFrame.new(0, (height - 1) / 2, 0), color, M.Cobblestone)
	if kind == "full" then
		-- Wall walk and battlements on the outer edge, a few merlons knocked off
		block(ctx.model, "WallCap", Vector3.new(length + 0.2, 0.6, THICK + 0.5), frame * CFrame.new(0, height + 0.3, 0), vary(STONE_PALE, random, 0.04), M.Slate)
		local count = math.floor(length / 4.6)
		local spacing = length / count
		for index = 0, count - 1 do
			if random:NextNumber() > 0.25 then
				local lost = random:NextNumber() < 0.15
				block(ctx.model, "Merlon", Vector3.new(spacing * 0.55, if lost then 1.2 else 2.6, 1.3), frame * CFrame.new(-length / 2 + spacing * (index + 0.5), height + 0.6 + (if lost then 0.6 else 1.3), -(THICK / 2) + 0.7), vary(STONE, random, 0.05), M.Cobblestone, SMALL)
			end
		end
		-- A torch on the courtyard face, banners on the tall south wall
		local alongTorch = random:NextNumber(-length * 0.25, length * 0.25)
		torch(ctx, frame * CFrame.new(alongTorch, 7.5, THICK / 2), runIndex == 1 and sideIndex <= 2)
		if sideIndex == 3 then
			banner(ctx, frame * CFrame.new(alongTorch + (if alongTorch > 0 then -6 else 6), 0, 0), height - 1, runIndex == 3)
		end
	else
		-- Broken: a stepped, jagged top falling away to one side
		local flip = if random:NextNumber() < 0.5 then 1 else -1
		local stepLength = length * random:NextNumber(0.3, 0.5)
		local rise = random:NextNumber(2, 4)
		local shift = flip * (length - stepLength) / 2
		block(ctx.model, "Wall", Vector3.new(stepLength, rise, THICK - 0.2), frame * CFrame.new(shift, height + rise / 2, 0), color, M.Cobblestone)
		local slope = math.min(length - stepLength, rise * 2.2)
		wedge(ctx.model, "WallBreak", Vector3.new(THICK - 0.2, rise, slope), frame * CFrame.new(shift - flip * (stepLength / 2 + slope / 2), height + rise / 2, 0) * CFrame.Angles(0, flip * math.pi / 2, 0), color, M.Cobblestone)
		if runIndex % 2 == 0 then
			Common.rubble(ctx, (frame * CFrame.new(-shift * 0.6, 0, -THICK)).Position, 3, 2, { STONE, STONE_DARK }, M.Slate, 0.9)
		end
	end
	if (sideIndex + runIndex) % 2 == 0 and height > 5 then
		ivy(ctx, frame, height, length)
	end
end

local function roundTower(ctx: Common.Context, corner: { number }, height: number, whole: boolean)
	local random = ctx.random
	local base = ctx.top + Vector3.new(corner[1] * 59, 0, corner[2] * 59)
	local root = CFrame.new(base)
	cylinder(ctx.model, "TowerFooting", root * CFrame.new(0, -0.2, 0), 3, 16, vary(STONE_DARK, random, 0.04), M.Slate)
	cylinder(ctx.model, "Tower", root * CFrame.new(0, height / 2, 0), height + 1, 13.6, vary(STONE, random, 0.05), M.Cobblestone)
	cylinder(ctx.model, "TowerCourse", root * CFrame.new(0, height * 0.55, 0), 0.7, 14.2, vary(STONE_PALE, random, 0.04), M.Slate, SMALL)
	local inward = Vector3.new(-corner[1], 0, -corner[2]).Unit
	-- Arrow slits on the courtyard side
	for _, y in { height * 0.35, height * 0.75 } do
		local at = base + inward * 6.75 + Vector3.new(0, y, 0)
		block(ctx.model, "Slit", Vector3.new(0.5, 2.6, 0.4), Common.lookAt(at, at + inward), rgb(34, 30, 28), M.Slate, SMALL)
	end
	if whole then
		cylinder(ctx.model, "Corbel", root * CFrame.new(0, height + 0.6, 0), 1.2, 15.2, vary(STONE_PALE, random, 0.04), M.Slate)
		for index = 0, 9 do
			if index ~= 6 then
				local angle = index / 10 * math.pi * 2
				local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
				local at = base + out * 6.8 + Vector3.new(0, height + 2.4, 0)
				block(ctx.model, "Merlon", Vector3.new(2.6, 2.4, 1.4), Common.lookAt(at, at + out), vary(STONE, random, 0.05), M.Cobblestone, SMALL)
			end
		end
		-- A flag on a pole at the top, seen from across the courtyard
		local pole = base + Vector3.new(0, height + 1.2, 0)
		cylinder(ctx.model, "FlagPole", CFrame.new(pole + Vector3.new(0, 5, 0)), 10, 0.4, OAK_DARK, M.Wood, SMALL)
		block(ctx.model, "Flag", Vector3.new(0.12, 3, 5), CFrame.new(pole + Vector3.new(0, 8.4, 0)) * CFrame.Angles(0, math.rad(35), 0) * CFrame.new(0, 0, 2.6), vary(CLOTH, random, 0.04), M.Fabric, SMALL)
	else
		-- Broken off: a sloping stub of wall on one side and the fall below
		local outward = -inward
		local at = base + outward * 3 + Vector3.new(0, height + 1.6, 0)
		wedge(ctx.model, "TowerBreak", Vector3.new(7, 4, 6), Common.lookAt(at, at + inward) * CFrame.Angles(0, math.pi, 0), vary(STONE, random, 0.05), M.Cobblestone)
		Common.rubble(ctx, base + outward * 10, 5, 4, { STONE, STONE_PALE, STONE_DARK }, M.Slate, 1.3)
	end
end

local function corners(ctx: Common.Context)
	local random = ctx.random
	-- Far corner from the first spawn: the tower that still stands whole
	roundTower(ctx, { 1, 1 }, 24, true)
	roundTower(ctx, { -1, 1 }, 13, false)
	-- A square bastion, and a collapsed corner by the first spawn
	local bastion = ctx.top + Vector3.new(59, 0, -59)
	block(ctx.model, "BastionFooting", Vector3.new(15, 2.4, 15), CFrame.new(bastion + Vector3.new(0, -0.5, 0)), vary(STONE_DARK, random, 0.04), M.Slate)
	block(ctx.model, "Bastion", Vector3.new(13, 19, 13), CFrame.new(bastion + Vector3.new(0, 9, 0)), vary(STONE, random, 0.05), M.Cobblestone)
	block(ctx.model, "BastionCap", Vector3.new(14, 0.8, 14), CFrame.new(bastion + Vector3.new(0, 18.8, 0)), vary(STONE_PALE, random, 0.04), M.Slate)
	for _, offset in { { 1, 1 }, { 1, -1 }, { -1, -1 } } do
		block(ctx.model, "Merlon", Vector3.new(2.8, 2.6, 2.8), CFrame.new(bastion + Vector3.new(offset[1] * 5.6, 20.5, offset[2] * 5.6)), vary(STONE, random, 0.05), M.Cobblestone, SMALL)
	end
	local stump = ctx.top + Vector3.new(-59, 0, -59)
	cylinder(ctx.model, "TowerFooting", CFrame.new(stump + Vector3.new(0, -0.2, 0)), 3, 16, vary(STONE_DARK, random, 0.04), M.Slate)
	cylinder(ctx.model, "Tower", CFrame.new(stump + Vector3.new(0, 2.2, 0)), 5.4, 13.6, vary(STONE, random, 0.05), M.Cobblestone)
	wedge(ctx.model, "TowerBreak", Vector3.new(6, 3, 5), CFrame.new(stump + Vector3.new(-3, 6.4, -2)) * CFrame.Angles(0, math.rad(225), 0), vary(STONE, random, 0.05), M.Cobblestone)
	Common.rubble(ctx, stump + Vector3.new(-6, 0, -9), 6, 4, { STONE, STONE_PALE, STONE_DARK }, M.Slate, 1.4)
end

-- The gatehouse in the middle of the east wall, with the arena's name over the arch
local function gatehouse(ctx: Common.Context)
	local random = ctx.random
	local frame = sideFrame(ctx, Vector3.new(1, 0, 0), 0, 60.5)
	for _, side in { -1, 1 } do
		local tower = frame * CFrame.new(side * 9, 0, 0)
		block(ctx.model, "GateFooting", Vector3.new(7.4, 2.4, 11.4), tower * CFrame.new(0, -0.5, 0), vary(STONE_DARK, random, 0.04), M.Slate)
		block(ctx.model, "GateTower", Vector3.new(6.4, 22, 10), tower * CFrame.new(0, 10.5, 0), vary(STONE, random, 0.05), M.Cobblestone)
		block(ctx.model, "GateCap", Vector3.new(7, 0.6, 10.6), tower * CFrame.new(0, 21.8, 0), vary(STONE_PALE, random, 0.04), M.Slate)
		for _, z in { -3.6, 0, 3.6 } do
			block(ctx.model, "Merlon", Vector3.new(1.4, 2.4, 2), tower * CFrame.new(side * 2.4, 23.3, z), vary(STONE, random, 0.05), M.Cobblestone, SMALL)
		end
		torch(ctx, frame * CFrame.new(side * 9, 8, 5), side == 1)
	end
	-- Over the passage: the arch block with chamfered corners, then the plaque
	block(ctx.model, "GateArch", Vector3.new(11.8, 9, 10), frame * CFrame.new(0, 16.5, 0), vary(STONE, random, 0.05), M.Cobblestone)
	for _, side in { -1, 1 } do
		wedge(ctx.model, "ArchCorner", Vector3.new(9, 2.4, 2.4), frame * CFrame.new(side * 4.7, 10.8, 0) * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi), vary(STONE, random, 0.05), M.Cobblestone)
	end
	block(ctx.model, "Keystone", Vector3.new(2, 2.6, 10.4), frame * CFrame.new(0, 12.9, 0), vary(STONE_PALE, random, 0.04), M.Slate, SMALL)
	-- The portcullis, stuck half raised; the barrier behind it keeps fighters in
	for index = -2, 2 do
		block(ctx.model, "PortcullisBar", Vector3.new(0.4, 8, 0.4), frame * CFrame.new(index * 2.2, 8.2, -1), IRON, M.Metal, SMALL)
	end
	for _, y in { 5.6, 9.4 } do
		block(ctx.model, "PortcullisBar", Vector3.new(11.4, 0.4, 0.4), frame * CFrame.new(0, y, -1), IRON, M.Metal, SMALL)
	end
	local plaque = block(ctx.model, "NamePlaque", Vector3.new(11, 2.4, 0.4), frame * CFrame.new(0, 16.2, 5.2) * CFrame.Angles(0, math.pi, 0), vary(OAK_DARK, random, 0.04), M.Wood, SMALL)
	Common.sign(plaque, Enum.NormalId.Front, "RUINED FORTRESS", rgb(232, 210, 168), 24, 0.6)
end

-- Cover --------------------------------------------------------------------------------------

local function coverAt(ctx: Common.Context, degrees: number): CFrame
	local angle = math.rad(degrees)
	local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local base = ctx.top + out * 29
	return Common.lookAt(base, base + out)
end

local function brokenArch(ctx: Common.Context, frame: CFrame)
	local random = ctx.random
	for _, side in { -1, 1 } do
		local tall = if side < 0 then 11 else 6.5
		block(ctx.model, "ArchPlinth", Vector3.new(3.8, 1.2, 3.8), frame * CFrame.new(side * 5, 0.4, 0), vary(STONE_DARK, random, 0.04), M.Slate)
		block(ctx.model, "ArchPier", Vector3.new(3, tall, 3), frame * CFrame.new(side * 5, tall / 2 + 0.9, 0) * CFrame.Angles(0, 0, side * random:NextNumber(0, 0.015)), vary(STONE, random, 0.05), M.Cobblestone)
	end
	-- The arch springs from the tall pier and stops in mid air where it broke
	wedge(ctx.model, "ArchSpring", Vector3.new(3, 2.6, 4), frame * CFrame.new(-1.6, 10.6, 0) * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi), vary(STONE, random, 0.05), M.Cobblestone)
	block(ctx.model, "ArchCap", Vector3.new(3.6, 0.6, 3.6), frame * CFrame.new(-5, 12.2, 0), vary(STONE_PALE, random, 0.04), M.Slate, SMALL)
	block(ctx.model, "ArchStone", Vector3.new(3.2, 2.2, 2.8), frame * CFrame.new(1.4, 1, -2.4) * CFrame.Angles(0.1, 0.5, 0.2), vary(STONE, random, 0.05), M.Cobblestone)
	block(ctx.model, "ArchStone", Vector3.new(2.6, 2, 2.6), frame * CFrame.new(2.6, 0.8, 2.6) * CFrame.Angles(-0.2, 1.2, 0.1), vary(STONE_PALE, random, 0.05), M.Cobblestone, SMALL)
end

local function wallStub(ctx: Common.Context, frame: CFrame)
	local random = ctx.random
	local color = vary(STONE, random, 0.05)
	block(ctx.model, "CoverFooting", Vector3.new(14, 1.2, 3.8), frame * CFrame.new(0, 0.4, 0), vary(STONE_DARK, random, 0.04), M.Slate)
	block(ctx.model, "CoverWall", Vector3.new(13, 4.6, 2.8), frame * CFrame.new(0, 3.2, 0), color, M.Cobblestone)
	block(ctx.model, "CoverWall", Vector3.new(5, 2, 2.6), frame * CFrame.new(-4, 6.5, 0), color, M.Cobblestone)
	wedge(ctx.model, "CoverBreak", Vector3.new(2.6, 2, 3.4), frame * CFrame.new(-0.2, 6.5, 0) * CFrame.Angles(0, math.pi / 2, 0), color, M.Cobblestone)
	block(ctx.model, "Ivy", Vector3.new(2.4, 3.6, 0.3), frame * CFrame.new(3.6, 3.8, 1.5), vary(pick(IVY, random), random, 0.05), M.LeafyGrass, GHOST)
	block(ctx.model, "Ivy", Vector3.new(1.6, 2.4, 0.3), frame * CFrame.new(5.2, 4.4, 1.5), vary(pick(IVY, random), random, 0.05), M.LeafyGrass, GHOST)
	Common.rubble(ctx, (frame * CFrame.new(5, 0, -3)).Position, 2.4, 3, { STONE, STONE_PALE }, M.Slate, 0.8)
end

local function well(ctx: Common.Context, frame: CFrame)
	local random = ctx.random
	cylinder(ctx.model, "Well", frame * CFrame.new(0, 1.5, 0), 3, 7, vary(STONE, random, 0.05), M.Cobblestone)
	cylinder(ctx.model, "WellRim", frame * CFrame.new(0, 3.2, 0), 0.5, 7.6, vary(STONE_PALE, random, 0.04), M.Slate)
	disc(ctx.model, "WellWater", (frame * CFrame.new(0, 3.5, 0)).Position, 5.2, 0.1, WATER, M.Slate, GHOST)
	for _, side in { -1, 1 } do
		block(ctx.model, "WellPost", Vector3.new(0.8, 7.4, 0.8), frame * CFrame.new(side * 3.4, 3.7, 0) * CFrame.Angles(0, 0, side * 0.03), vary(OAK, random, 0.05), M.Wood)
	end
	block(ctx.model, "WellBeam", Vector3.new(8.4, 0.7, 0.7), frame * CFrame.new(0, 7.2, 0), vary(OAK_DARK, random, 0.05), M.Wood, SMALL)
	for _, side in { -1, 1 } do
		wedge(ctx.model, "WellRoof", Vector3.new(9, 1.4, 2.4), frame * CFrame.new(0, 8.2, side * 1.2) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0), vary(OAK, random, 0.05), M.WoodPlanks, SMALL)
	end
	block(ctx.model, "Rope", Vector3.new(0.15, 2.6, 0.15), frame * CFrame.new(0.4, 5.6, 0), rgb(150, 128, 92), M.Fabric, GHOST)
	cylinder(ctx.model, "Bucket", frame * CFrame.new(0.4, 3.9, 0), 1, 1, vary(OAK, random, 0.05), M.Wood, SMALL)
end

local function cart(ctx: Common.Context, frame: CFrame)
	local random = ctx.random
	local tipped = frame * CFrame.Angles(0, 0, -0.12)
	block(ctx.model, "CartBed", Vector3.new(9, 0.7, 4.6), tipped * CFrame.new(0, 2.4, 0), vary(OAK, random, 0.05), M.WoodPlanks)
	for _, side in { -1, 1 } do
		block(ctx.model, "CartSide", Vector3.new(9, 1.6, 0.4), tipped * CFrame.new(0, 3.5, side * 2.1), vary(OAK, random, 0.05), M.WoodPlanks, SMALL)
		cylinder(ctx.model, "CartWheel", tipped * CFrame.new(-1.2, 1.8, side * 2.7) * CFrame.Angles(math.pi / 2, 0, 0), 0.5, 3.8, vary(OAK_DARK, random, 0.05), M.Wood, SMALL)
	end
	-- One wheel came off and the shafts rest on the ground
	block(ctx.model, "CartShaft", Vector3.new(6, 0.4, 0.4), tipped * CFrame.new(6.6, 1.6, 1.4) * CFrame.Angles(0, 0, -0.3), vary(OAK_DARK, random, 0.05), M.Wood, SMALL)
	block(ctx.model, "CartShaft", Vector3.new(6, 0.4, 0.4), tipped * CFrame.new(6.6, 1.6, -1.4) * CFrame.Angles(0, 0, -0.3), vary(OAK_DARK, random, 0.05), M.Wood, SMALL)
	block(ctx.model, "Crate", Vector3.new(2.8, 2.8, 2.8), frame * CFrame.new(-6.6, 1.4, 1.2) * CFrame.Angles(0, 0.3, 0), vary(OAK, random, 0.06), M.WoodPlanks)
	block(ctx.model, "Crate", Vector3.new(2.2, 2.2, 2.2), frame * CFrame.new(-6.4, 3.9, 1) * CFrame.Angles(0, -0.4, 0), vary(OAK, random, 0.06), M.WoodPlanks, SMALL)
	block(ctx.model, "Sack", Vector3.new(2, 1.2, 1.4), frame * CFrame.new(-3.5, 0.6, -2.8) * CFrame.Angles(0, 0.7, 0.1), rgb(150, 128, 96), M.Fabric, SMALL)
end

local function cover(ctx: Common.Context)
	brokenArch(ctx, coverAt(ctx, 0))
	wallStub(ctx, coverAt(ctx, 90))
	well(ctx, coverAt(ctx, 180))
	cart(ctx, coverAt(ctx, 270))
end

-- Great braziers by the north and south walls: the two Pylons
local function braziers(ctx: Common.Context)
	local random = ctx.random
	for index, v in { -0.9, 0.9 } do
		local base = Common.at(ctx, random:NextNumber(-0.1, 0.1), 0, v)
		block(ctx.model, "BrazierStep", Vector3.new(4.6, 0.8, 4.6), CFrame.new(base + Vector3.new(0, 0.4, 0)), vary(STONE_DARK, random, 0.04), M.Slate)
		local pedestal = block(ctx.model, "Pedestal", Vector3.new(3.2, 3.4, 3.2), CFrame.new(base + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, random:NextNumber(-0.2, 0.2), 0), vary(STONE, random, 0.05), M.Cobblestone)
		Common.fireBowl(ctx, base + Vector3.new(0, 5.2, 0), 3.4, vary(IRON, random, 0.05), FLAME, 22, 1.4, index == 1)
		Common.interactive(pedestal, "Pylon")
	end
end

local function throwables(ctx: Common.Context)
	local random = ctx.random
	local function ground(u: number, v: number): Vector3
		return Common.at(ctx, u, 0, v)
	end
	Common.throwable(ctx, "Crate", 1, Vector3.new(3, 3, 3), CFrame.new(ground(-0.6, 0.32) + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0.5, 0), vary(OAK, random, 0.05), M.WoodPlanks)
	Common.throwable(ctx, "Crate", 1, Vector3.new(2.6, 2.6, 2.6), CFrame.new(ground(-0.26, -0.64) + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 1.2, 0), vary(OAK, random, 0.05), M.WoodPlanks)
	Common.uprightThrowable(ctx, "Barrel", 1, ground(0.62, 0.42), 3.2, 2.4, 0, vary(OAK_DARK, random, 0.04), M.Wood)
	Common.throwable(ctx, "FallenMerlon", 2, Vector3.new(4.4, 3, 3.2), CFrame.new(ground(0.5, -0.32) + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0.8, 0.04), vary(STONE, random, 0.05), M.Cobblestone)
	Common.throwable(ctx, "Boulder", 2, Vector3.new(4.6, 3.6, 4.2), CFrame.new(ground(-0.62, -0.36) + Vector3.new(0, 1.6, 0)) * CFrame.Angles(-0.06, 2.1, 0.1), vary(STONE_DARK, random, 0.05), M.Slate)
	Common.uprightThrowable(ctx, "ColumnDrum", 3, ground(0.24, 0.64), 4.4, 5.4, 0.3, vary(STONE_PALE, random, 0.03), M.Slate)
end

local function spawnPads(ctx: Common.Context)
	for _, spawn in Common.spawns(ctx) do
		local base = Common.spawnBase(spawn, ctx.floorY)
		disc(ctx.model, "SpawnRing", base + Vector3.new(0, 0.16, 0), 8.8, 0.2, IRON, M.Metal, GHOST)
		disc(ctx.model, "SpawnPad", base + Vector3.new(0, 0.2, 0), 8, 0.2, vary(STONE_PALE, ctx.random, 0.03), M.Slate, GHOST)
		disc(ctx.model, "SpawnMark", base + Vector3.new(0, 0.23, 0), 2, 0.1, CLOTH, M.Brick, GHOST)
	end
end

-- Outside the walls: the broken keep on the crag, pines and rocks
local function surroundings(ctx: Common.Context)
	local random = ctx.random
	local c = ctx.center
	local keep = c + Vector3.new(140, 14, -6)
	block(ctx.model, "KeepFooting", Vector3.new(20, 8, 20), CFrame.new(keep + Vector3.new(0, -3, 0)) * CFrame.Angles(0, 0.1, 0), vary(STONE_DARK, random, 0.04), M.Slate)
	local body = CFrame.new(keep) * CFrame.Angles(0, 0.1, 0)
	block(ctx.model, "Keep", Vector3.new(17, 30, 17), body * CFrame.new(0, 15, 0), vary(STONE, random, 0.05), M.Cobblestone)
	block(ctx.model, "Keep", Vector3.new(8, 8, 17), body * CFrame.new(-4.5, 34, 0), vary(STONE, random, 0.05), M.Cobblestone)
	wedge(ctx.model, "KeepBreak", Vector3.new(17, 8, 9), body * CFrame.new(4, 34, 0) * CFrame.Angles(0, math.pi / 2, 0), vary(STONE, random, 0.05), M.Cobblestone)
	block(ctx.model, "KeepCourse", Vector3.new(17.8, 0.8, 17.8), body * CFrame.new(0, 20, 0), vary(STONE_PALE, random, 0.04), M.Slate, SMALL)
	for _, y in { 10, 24 } do
		block(ctx.model, "KeepWindow", Vector3.new(0.4, 3.2, 1.4), body * CFrame.new(-8.6, y, random:NextNumber(-3, 3)), rgb(34, 30, 28), M.Slate, SMALL)
	end
	for _, spot in { { -66, 30 }, { 70, 50 }, { 30, -70 }, { 76, -30 } } do
		Common.rock(ctx, c + Vector3.new(spot[1], 0.3, spot[2]), Vector3.new(random:NextNumber(3, 5.5), random:NextNumber(2.2, 3.6), random:NextNumber(3, 5)), STONE_DARK, M.Slate, MOSS)
	end
	for _, spot in { { 98, -54, 22 }, { 108, 48, 25 }, { -40, 84, 18 } } do
		Common.pine(ctx, c + Vector3.new(spot[1], 0, spot[2]), spot[3], pick(NEEDLES, random), BARK, 2)
	end
end

function RuinedFortress.build(ctx: Common.Context)
	terrain(ctx)
	floor(ctx)
	for sideIndex, side in SIDES do
		local along = -52
		for runIndex, run in side.runs do
			if run[3] ~= "gate" then
				wallRun(ctx, side.normal, along, run[1], run[2], run[3], sideIndex, runIndex)
			end
			along += run[1]
		end
	end
	Common.barriers(ctx)
	corners(ctx)
	gatehouse(ctx)
	cover(ctx)
	braziers(ctx)
	throwables(ctx)
	spawnPads(ctx)
	surroundings(ctx)
end

return RuinedFortress
