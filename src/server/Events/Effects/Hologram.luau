-- Giant translucent holograms and emblems made of a few neon bars and rings.
local Params = require(script.Parent.Parent.Params)

local function bar(folder, size, cf, color)
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = 0.45
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Parent = folder
	return p
end
local function ring(folder, cf, radius, color, beads)
	for i = 1, beads do
		local a = i / beads * math.pi * 2
		local p = bar(folder, Vector3.new(1.4, 1.4, 1.4), cf * CFrame.new(math.cos(a) * radius, math.sin(a) * radius, 0), color)
		p.Shape = Enum.PartType.Ball
	end
end

local SHAPES = {}
function SHAPES.emblem(f, c, s, col)
	ring(f, c, 14 * s, col, 28)
	bar(f, Vector3.new(1, 24 * s, 1), c, col)
	bar(f, Vector3.new(24 * s, 1, 1), c, col)
end
function SHAPES.snowflake(f, c, s, col)
	for i = 0, 2 do
		bar(f, Vector3.new(1, 28 * s, 1), c * CFrame.Angles(0, 0, math.rad(i * 60)), col)
	end
end
function SHAPES.star(f, c, s, col)
	for i = 0, 4 do
		bar(f, Vector3.new(1, 28 * s, 1), c * CFrame.Angles(0, 0, math.rad(i * 36)), col)
	end
end
function SHAPES.globe(f, c, s, col)
	ring(f, c, 14 * s, col, 24)
	ring(f, c * CFrame.Angles(0, math.rad(60), 0), 14 * s, col, 24)
	ring(f, c * CFrame.Angles(0, math.rad(120), 0), 14 * s, col, 24)
end
function SHAPES.leaf(f, c, s, col)
	bar(f, Vector3.new(1, 30 * s, 1), c, col)
	for i = 1, 4 do
		bar(f, Vector3.new(1, 12 * s, 1), c * CFrame.new(0, (i * 5 - 10) * s, 0) * CFrame.Angles(0, 0, math.rad(55)), col)
		bar(f, Vector3.new(1, 12 * s, 1), c * CFrame.new(0, (i * 5 - 10) * s, 0) * CFrame.Angles(0, 0, math.rad(-55)), col)
	end
end
function SHAPES.heart(f, c, s, col)
	ring(f, c * CFrame.new(-6 * s, 4 * s, 0), 7 * s, col, 14)
	ring(f, c * CFrame.new(6 * s, 4 * s, 0), 7 * s, col, 14)
	bar(f, Vector3.new(1, 18 * s, 1), c * CFrame.new(-6 * s, -6 * s, 0) * CFrame.Angles(0, 0, math.rad(-35)), col)
	bar(f, Vector3.new(1, 18 * s, 1), c * CFrame.new(6 * s, -6 * s, 0) * CFrame.Angles(0, 0, math.rad(35)), col)
end
function SHAPES.tree(f, c, s, col)
	for i = 0, 4 do
		bar(f, Vector3.new((22 - i * 4) * s, 1, 1), c * CFrame.new(0, (i * 5 - 10) * s, 0), col)
	end
	bar(f, Vector3.new(1, 28 * s, 1), c, col)
end
function SHAPES.clock(f, c, s, col)
	ring(f, c, 14 * s, col, 30)
	bar(f, Vector3.new(1, 10 * s, 1), c * CFrame.new(0, 5 * s, 0), col)
	bar(f, Vector3.new(7 * s, 1, 1), c * CFrame.new(3.5 * s, 0, 0), col)
end
function SHAPES.helix(f, c, s, col)
	for i = 1, 30 do
		local a, y = i * 0.5, (i - 15) * 1.6 * s
		bar(f, Vector3.new(1.4, 1.4, 1.4), c * CFrame.new(math.cos(a) * 8 * s, y, math.sin(a) * 8 * s), col)
		bar(f, Vector3.new(1.4, 1.4, 1.4), c * CFrame.new(-math.cos(a) * 8 * s, y, -math.sin(a) * 8 * s), col)
	end
end
function SHAPES.crown(f, c, s, col)
	bar(f, Vector3.new(24 * s, 1.4, 1), c, col)
	for i = 0, 4 do
		bar(f, Vector3.new(1, 10 * s, 1), c * CFrame.new((i - 2) * 6 * s, 5 * s, 0), col)
	end
end
local shapes = {}
for id in SHAPES do
	table.insert(shapes, id)
end
table.sort(shapes)

return {
	id = "Hologram",
	channels = { "hologram" },
	group = "spectacle",
	cost = 10,
	gameplay = false,
	ownerOnly = false,
	shapes = shapes,
	params = {
		shape = { type = "enum", values = shapes, default = "emblem" },
		scale = { type = "number", min = 0.5, max = 3, default = 1.5, scales = true },
		height = { type = "number", min = 10, max = 90, default = 45 },
		color = { type = "color", default = { 90, 220, 255 } },
	},
	start = function(ctx, p)
		local folder = Instance.new("Folder")
		folder.Name = "Hologram_" .. p.shape
		folder.Parent = ctx.worldRoot
		local c = CFrame.new(ctx.center() + Vector3.new(0, p.height, 0))
		SHAPES[p.shape](folder, c, p.scale, Params.color3(p.color))
		return function()
			folder:Destroy()
		end
	end,
}
