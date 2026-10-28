-- The training hall beside the lobby: an open timber hall on a stone plinth
-- where players try their powers on the practice dummies. Plank floor with a
-- sparring mat under each dummy, a pergola of beams and rafters, weapon racks
-- along the back wall, target boards with scorch marks, hanging lanterns,
-- banners in the Training Hall's teal, and a few things to practise throwing.
-- Palette: oak and grey stone (dominant), teal cloth and straw (secondary),
-- warm lantern light (small accents).

local Common = require(script.Parent.Common)

local TrainingHall = {}

local M = Common.M
local rgb = Common.rgb
local block, cylinder, disc = Common.block, Common.cylinder, Common.disc
local vary = Common.vary
local SMALL, GHOST = Common.SMALL, Common.GHOST

local STONE = rgb(128, 124, 116)
local STONE_PALE = rgb(150, 145, 134)
local PLANKS = rgb(132, 100, 70)
local OAK = rgb(104, 76, 52)
local OAK_DARK = rgb(78, 58, 42)
local IRON = rgb(56, 54, 52)
local MAT = rgb(58, 92, 100)
local MAT_EDGE = rgb(176, 160, 120)
local TEAL = rgb(64, 110, 118)
local STRAW = rgb(186, 160, 96)
local RED = rgb(150, 56, 46)
local FLAME = rgb(255, 184, 110)

-- Half the plinth's size (it fills the space the lobby keeps clear)
local HALF_X, HALF_Z = 17, 22
local POSTS_X = { -16, -5.5, 5.5, 16 }
local BEAM_Y = 13

local function shell(ctx: Common.Context)
	local top = ctx.top
	local random = ctx.random
	block(ctx.model, "Floor", Vector3.new(HALF_X * 2, 1.6, HALF_Z * 2), CFrame.new(top - Vector3.new(0, 0.8, 0)), vary(STONE, random, 0.03), M.Slate)
	block(ctx.model, "Planks", Vector3.new(HALF_X * 2 - 2.4, 0.1, HALF_Z * 2 - 2.4), CFrame.new(top + Vector3.new(0, 0.05, 0)), PLANKS, M.WoodPlanks, GHOST)
	-- Stone kerb round the planks
	for _, side in { -1, 1 } do
		block(ctx.model, "Kerb", Vector3.new(HALF_X * 2, 0.3, 1.2), CFrame.new(top + Vector3.new(0, 0.15, side * (HALF_Z - 0.6))), vary(STONE_PALE, random, 0.03), M.Slate, GHOST)
		block(ctx.model, "Kerb", Vector3.new(1.2, 0.3, HALF_Z * 2 - 2.4), CFrame.new(top + Vector3.new(side * (HALF_X - 0.6), 0.15, 0)), vary(STONE_PALE, random, 0.03), M.Slate, GHOST)
	end
	-- Posts on footings, beams along the sides, crossbeams and rafters
	for _, x in POSTS_X do
		for _, side in { -1, 1 } do
			local base = top + Vector3.new(x, 0, side * (HALF_Z - 1))
			block(ctx.model, "Footing", Vector3.new(2, 1, 2), CFrame.new(base + Vector3.new(0, 0.5, 0)), vary(STONE_PALE, random, 0.04), M.Slate, SMALL)
			block(ctx.model, "Post", Vector3.new(1.2, BEAM_Y - 0.5, 1.2), CFrame.new(base + Vector3.new(0, (BEAM_Y - 0.5) / 2 + 0.5, 0)) * CFrame.Angles(random:NextNumber(-0.01, 0.01), 0, random:NextNumber(-0.01, 0.01)), vary(OAK, random, 0.05), M.Wood)
			-- Knee braces under the beam
			Common.strut(ctx.model, "Brace", base + Vector3.new(if x > 0 then -2.4 else 2.4, BEAM_Y - 0.4, 0), base + Vector3.new(0, BEAM_Y - 3, 0), 0.5, 0.5, vary(OAK_DARK, random, 0.05), M.Wood, SMALL)
		end
		block(ctx.model, "CrossBeam", Vector3.new(1, 1, HALF_Z * 2 + 0.4), CFrame.new(top + Vector3.new(x, BEAM_Y + 1.1, 0)), vary(OAK_DARK, random, 0.04), M.Wood, SMALL)
	end
	for _, side in { -1, 1 } do
		block(ctx.model, "Beam", Vector3.new(HALF_X * 2 + 1, 1.2, 1.4), CFrame.new(top + Vector3.new(0, BEAM_Y + 0.1, side * (HALF_Z - 1))), vary(OAK_DARK, random, 0.04), M.Wood)
	end
	for x = -13, 13, 4.33 do
		block(ctx.model, "Rafter", Vector3.new(0.5, 0.6, HALF_Z * 2 + 1), CFrame.new(top + Vector3.new(x, BEAM_Y + 1.9, 0)), vary(OAK, random, 0.05), M.Wood, SMALL)
	end
	-- The back wall: stone up to the waist, a timber rail on top
	block(ctx.model, "BackWall", Vector3.new(1.6, 3.4, HALF_Z * 2 - 3), CFrame.new(top + Vector3.new(-HALF_X + 0.8, 1.7, 0)), vary(STONE, random, 0.04), M.Slate)
	block(ctx.model, "BackRail", Vector3.new(2, 0.5, HALF_Z * 2 - 2.6), CFrame.new(top + Vector3.new(-HALF_X + 0.8, 3.6, 0)), vary(OAK_DARK, random, 0.04), M.Wood, SMALL)
end

local function mats(ctx: Common.Context, spots: { CFrame })
	local random = ctx.random
	for _, spot in spots do
		local base = Vector3.new(spot.Position.X, ctx.floorY, spot.Position.Z)
		block(ctx.model, "MatEdge", Vector3.new(9.6, 0.14, 9.6), CFrame.new(base + Vector3.new(0, 0.17, 0)), vary(MAT_EDGE, random, 0.03), M.Fabric, GHOST)
		block(ctx.model, "Mat", Vector3.new(8.8, 0.16, 8.8), CFrame.new(base + Vector3.new(0, 0.2, 0)), vary(MAT, random, 0.04), M.Fabric, GHOST)
	end
end

local function rack(ctx: Common.Context, z: number)
	local random = ctx.random
	local base = ctx.top + Vector3.new(-HALF_X + 2.4, 0, z)
	for _, side in { -1, 1 } do
		block(ctx.model, "RackPost", Vector3.new(0.5, 5.4, 0.5), CFrame.new(base + Vector3.new(0, 2.7, side * 3)), vary(OAK, random, 0.05), M.Wood, SMALL)
	end
	for _, y in { 1.2, 4.6 } do
		block(ctx.model, "RackBar", Vector3.new(0.4, 0.4, 6.6), CFrame.new(base + Vector3.new(0, y, 0)), vary(OAK_DARK, random, 0.05), M.Wood, SMALL)
	end
	-- Practice staves and a wooden sword leaning in it
	for index = 1, 4 do
		local foot = base + Vector3.new(0.5, 0.2, -2.4 + index * 1.1)
		local head = foot + Vector3.new(-0.9, 5.6, random:NextNumber(-0.3, 0.3))
		Common.strut(ctx.model, if index == 3 then "PracticeSword" else "Staff", foot, head, 0.32, if index == 3 then 0.12 else 0.32, vary(if index == 3 then PLANKS else OAK, random, 0.06), M.Wood, GHOST)
	end
end

local function target(ctx: Common.Context, at: Vector3, facing: Vector3)
	local random = ctx.random
	local frame = Common.lookAt(at, at + facing)
	for _, side in { -1, 1 } do
		block(ctx.model, "EaselLeg", Vector3.new(0.4, 6.4, 0.4), frame * CFrame.new(side * 1.6, 3, 0.3) * CFrame.Angles(0.12, 0, side * 0.1), vary(OAK, random, 0.05), M.Wood, SMALL)
	end
	block(ctx.model, "EaselLeg", Vector3.new(0.4, 6, 0.4), frame * CFrame.new(0, 2.8, 1.8) * CFrame.Angles(-0.35, 0, 0), vary(OAK_DARK, random, 0.05), M.Wood, SMALL)
	local face = frame * CFrame.new(0, 4.2, -0.1) * CFrame.Angles(0.12, 0, 0)
	cylinder(ctx.model, "Target", face * CFrame.Angles(math.pi / 2, 0, 0), 0.6, 4.8, vary(STRAW, random, 0.04), M.Fabric)
	cylinder(ctx.model, "TargetRing", face * CFrame.new(0, 0, -0.32) * CFrame.Angles(math.pi / 2, 0, 0), 0.06, 3.2, RED, M.Fabric, GHOST)
	cylinder(ctx.model, "TargetRing", face * CFrame.new(0, 0, -0.36) * CFrame.Angles(math.pi / 2, 0, 0), 0.06, 2.4, vary(STRAW, random, 0.04), M.Fabric, GHOST)
	cylinder(ctx.model, "TargetRing", face * CFrame.new(0, 0, -0.4) * CFrame.Angles(math.pi / 2, 0, 0), 0.06, 1, RED, M.Fabric, GHOST)
	-- Scorch on the planks in front, from powers that missed
	disc(ctx.model, "Scorch", (frame * CFrame.new(random:NextNumber(-1, 1), 0.13, -4)).Position, random:NextNumber(3, 4.4), 0.06, rgb(70, 58, 48), M.Wood, GHOST)
end

local function lantern(ctx: Common.Context, at: Vector3, shadows: boolean)
	local random = ctx.random
	block(ctx.model, "LanternChain", Vector3.new(0.15, 2.2, 0.15), CFrame.new(at + Vector3.new(0, 1.1, 0)), IRON, M.Metal, GHOST)
	block(ctx.model, "LanternCap", Vector3.new(1.2, 0.4, 1.2), CFrame.new(at - Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, random:NextNumber(0, 1), 0), IRON, M.Metal, SMALL)
	local glass = block(ctx.model, "Lantern", Vector3.new(0.9, 1.3, 0.9), CFrame.new(at - Vector3.new(0, 1.05, 0)), rgb(255, 214, 150), M.Glass, { Transparency = 0.3, CastShadow = false, CanCollide = false })
	Common.light(glass, FLAME, 20, 1.3, shadows).Name = "Glow"
end

local function banner(ctx: Common.Context, at: Vector3, facing: Vector3, long: number)
	local random = ctx.random
	local frame = Common.lookAt(at, at + facing)
	block(ctx.model, "BannerRod", Vector3.new(4.2, 0.3, 0.3), frame, IRON, M.Metal, SMALL)
	block(ctx.model, "Banner", Vector3.new(3.4, long, 0.14), frame * CFrame.new(0, -long / 2 - 0.1, 0) * CFrame.Angles(random:NextNumber(-0.02, 0.02), 0, 0), vary(TEAL, random, 0.04), M.Fabric, SMALL)
	block(ctx.model, "BannerTrim", Vector3.new(3.4, 0.45, 0.16), frame * CFrame.new(0, -long + 0.4, 0), MAT_EDGE, M.Fabric, SMALL)
	block(ctx.model, "BannerMark", Vector3.new(1.2, 1.2, 0.16), frame * CFrame.new(0, -2.4, 0) * CFrame.Angles(0, 0, math.rad(45)), MAT_EDGE, M.Fabric, SMALL)
end

local function dressing(ctx: Common.Context)
	local random = ctx.random
	local top = ctx.top
	rack(ctx, -9)
	rack(ctx, 9)
	target(ctx, top + Vector3.new(-10, 0, -18.4), Vector3.new(0, 0, -1))
	target(ctx, top + Vector3.new(-10, 0, 18.4), Vector3.new(0, 0, 1))
	for index, spot in { { -10.75, -12 }, { -10.75, 12 }, { 10.75, -12 }, { 10.75, 12 } } do
		lantern(ctx, top + Vector3.new(spot[1], BEAM_Y + 0.1 - 2.2, spot[2]), index <= 2)
	end
	banner(ctx, top + Vector3.new(-HALF_X + 1.4, BEAM_Y - 0.6, 0), Vector3.new(-1, 0, 0), 7)
	for _, side in { -1, 1 } do
		banner(ctx, top + Vector3.new(0, BEAM_Y - 0.7, side * (HALF_Z - 0.2)), Vector3.new(0, 0, side), 5)
	end
	-- The name board hangs from the front crossbeam, facing the way in
	local board = top + Vector3.new(16, BEAM_Y - 2.4, 0)
	local face = Common.lookAt(board, board + Vector3.new(1, 0, 0))
	for _, side in { -1, 1 } do
		block(ctx.model, "SignChain", Vector3.new(0.15, 2, 0.15), face * CFrame.new(side * 4.6, 2.2, 0), IRON, M.Metal, GHOST)
	end
	local plate = block(ctx.model, "NameBoard", Vector3.new(11, 2.4, 0.3), face, vary(OAK_DARK, random, 0.04), M.Wood, SMALL)
	Common.sign(plate, Enum.NormalId.Front, "TRAINING HALL", rgb(236, 220, 186), 24, 0.6)
	-- A bench, straw bales and a water bucket in the corners
	local bench = top + Vector3.new(8, 0, -19.6)
	block(ctx.model, "BenchSeat", Vector3.new(7, 0.4, 1.6), CFrame.new(bench + Vector3.new(0, 1.9, 0)), vary(OAK, random, 0.05), M.WoodPlanks, SMALL)
	for _, side in { -1, 1 } do
		block(ctx.model, "BenchLeg", Vector3.new(0.5, 1.7, 1.4), CFrame.new(bench + Vector3.new(side * 2.8, 0.85, 0)), vary(OAK_DARK, random, 0.05), M.Wood, SMALL)
	end
	for _, spot in { { -13.4, -18.6, 0.1 }, { -13.6, 18.4, -0.2 }, { -10.6, 19.4, 0.4 } } do
		block(ctx.model, "StrawBale", Vector3.new(3.4, 2, 2.2), CFrame.new(top + Vector3.new(spot[1], 1, spot[2])) * CFrame.Angles(0, spot[3], 0), vary(STRAW, random, 0.05), M.Grass, SMALL)
	end
	cylinder(ctx.model, "Bucket", CFrame.new(top + Vector3.new(12.6, 0.8, -19.4)), 1.6, 1.6, vary(OAK, random, 0.05), M.Wood, SMALL)
end

local function throwables(ctx: Common.Context)
	local random = ctx.random
	local top = ctx.top
	Common.throwable(ctx, "Crate", 1, Vector3.new(3, 3, 3), CFrame.new(top + Vector3.new(10, 1.5, -15)) * CFrame.Angles(0, 0.3, 0), vary(PLANKS, random, 0.05), M.WoodPlanks)
	Common.uprightThrowable(ctx, "Barrel", 1, top + Vector3.new(12, 0, 15), 3.2, 2.4, 0, vary(OAK, random, 0.04), M.Wood)
	Common.throwable(ctx, "Boulder", 2, Vector3.new(4.6, 3.8, 4.2), CFrame.new(top + Vector3.new(4, 1.7, -16.6)) * CFrame.Angles(0.06, 0.6, -0.04), vary(STONE, random, 0.05), M.Slate)
end

-- Builds the hall around `center` (its floor's middle at ground level) and
-- returns it with the three spots the practice dummies stand on
function TrainingHall.build(center: Vector3): (Model, { CFrame })
	local ctx = Common.context("TrainingGround", center - Vector3.new(0, 0.5, 0), 4211)
	local spots = {}
	for _, z in { -12, 0, 12 } do
		local position = ctx.top + Vector3.new(-4, 3, z)
		table.insert(spots, Common.lookAt(position, position + Vector3.new(1, 0, 0)))
	end
	shell(ctx)
	mats(ctx, spots)
	dressing(ctx)
	throwables(ctx)
	return ctx.model, spots
end

return TrainingHall
