-- Floating and standing installations built from a bounded number of anchored, non-colliding
-- neon parts inside one folder; stopping destroys the folder. Never replaces map geometry.
local Params = require(script.Parent.Parent.Params)

local MAX_PARTS = 120

local function part(folder, shape, size, cframe, color, material, transparency)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = folder
	return p
end
local Ball, Block, Cyl = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder

-- Each builder: (folder, centre CFrame, scale, count, colour); returns nothing
local BUILD = {}
function BUILD.tree(f, c, s, n, col)
	local tiers = math.clamp(n, 3, 9)
	for i = 1, tiers do
		local w = (tiers - i + 2) * 3 * s
		part(f, Cyl, Vector3.new(0.6 * s, w, w), c * CFrame.new(0, (i - 1) * 2.4 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), col, Enum.Material.Neon, 0.35)
		for k = 1, 4 do
			local a = k / 4 * math.pi * 2 + i
			part(f, Ball, Vector3.new(0.8, 0.8, 0.8) * s, c * CFrame.new(math.cos(a) * w * 0.4, (i - 1) * 2.4 * s + 0.6, math.sin(a) * w * 0.4), Color3.fromRGB(255, 240, 200))
		end
	end
	part(f, Ball, Vector3.new(3, 3, 3) * s, c * CFrame.new(0, tiers * 2.4 * s + 1, 0), Color3.fromRGB(255, 250, 220))
end
function BUILD.snowflake(f, c, s, n, col)
	for i = 0, math.clamp(n, 3, 8) - 1 do
		part(f, Block, Vector3.new(0.7, 0.7, 26) * s, c * CFrame.Angles(0, 0, math.rad(i * 180 / math.clamp(n, 3, 8))), col, Enum.Material.Neon, 0.3)
	end
end
function BUILD.islands(f, c, s, n, col)
	for i = 1, math.clamp(n, 2, 12) do
		local a, r = i * 2.4, 18 + i * 5
		local at = c * CFrame.new(math.cos(a) * r * s, math.sin(i) * 8 * s, math.sin(a) * r * s)
		part(f, Cyl, Vector3.new(2, 10, 10) * s, at * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 80, 95), Enum.Material.Metal)
		part(f, Cyl, Vector3.new(0.4, 9, 9) * s, at * CFrame.new(0, 1.1 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), col)
	end
end
function BUILD.pillars(f, c, s, n, col)
	for i = 1, math.clamp(n, 2, 16) do
		local a = i / n * math.pi * 2
		part(f, Cyl, Vector3.new(30, 1.6, 1.6) * s, c * CFrame.new(math.cos(a) * 24 * s, 15 * s, math.sin(a) * 24 * s) * CFrame.Angles(0, 0, math.rad(90)), col, Enum.Material.Neon, 0.2)
	end
end
function BUILD.spires(f, c, s, n, col)
	for i = 1, math.clamp(n, 2, 14) do
		local a = i * 1.9
		local h = (8 + (i % 4) * 5) * s
		part(f, Block, Vector3.new(2, h, 2) * 1, c * CFrame.new(math.cos(a) * (10 + i * 2) * s, h / 2, math.sin(a) * (10 + i * 2) * s) * CFrame.Angles(0, a, math.rad(6)), col, Enum.Material.Glass, 0.25)
	end
end
function BUILD.arch(f, c, s, n, col)
	local segs = math.clamp(n, 6, 24)
	for i = 0, segs do
		local a = i / segs * math.pi
		part(f, Ball, Vector3.new(2.4, 2.4, 2.4) * s, c * CFrame.new(math.cos(a) * 20 * s, math.sin(a) * 20 * s, 0), col)
	end
end
function BUILD.ring(f, c, s, n, col)
	local beads = math.clamp(n, 8, 48)
	for i = 1, beads do
		local a = i / beads * math.pi * 2
		part(f, Ball, Vector3.new(1.6, 1.6, 1.6) * s, c * CFrame.new(math.cos(a) * 22 * s, 0, math.sin(a) * 22 * s), col)
	end
end
function BUILD.lanterns(f, c, s, n, col)
	for i = 1, math.clamp(n, 3, 24) do
		local a, r = i * 2.4, 12 + (i % 5) * 6
		local lamp = part(f, Ball, Vector3.new(2, 2.6, 2) * s, c * CFrame.new(math.cos(a) * r * s, (6 + (i % 4) * 4) * s, math.sin(a) * r * s), col, Enum.Material.Neon, 0.1)
		local light = Instance.new("PointLight")
		light.Color = col
		light.Range = 14
		light.Brightness = 1
		light.Parent = lamp
	end
end
function BUILD.pumpkins(f, c, s, n, col)
	for i = 1, math.clamp(n, 3, 18) do
		local a, r = i * 2.1, 10 + (i % 3) * 7
		local at = c * CFrame.new(math.cos(a) * r * s, 2 * s, math.sin(a) * r * s)
		part(f, Ball, Vector3.new(4, 3.4, 4) * s, at, col, Enum.Material.Neon, 0.15)
		part(f, Block, Vector3.new(0.4, 1, 0.4) * s, at * CFrame.new(0, 2 * s, 0), Color3.fromRGB(60, 90, 50), Enum.Material.Metal)
	end
end
function BUILD.obelisk(f, c, s, n, col)
	part(f, Block, Vector3.new(4, 36, 4) * s, c * CFrame.new(0, 18 * s, 0), Color3.fromRGB(35, 40, 55), Enum.Material.Metal)
	for i = 1, math.clamp(n, 1, 6) do
		part(f, Ball, Vector3.new(3, 3, 3) * s, c * CFrame.new(0, (8 + i * 5) * s, 0), col)
	end
end
function BUILD.orbit(f, c, s, n, col)
	for i = 1, math.clamp(n, 3, 20) do
		local a = i / n * math.pi * 2
		part(f, Ball, Vector3.new(2.5, 2.5, 2.5) * s, c * CFrame.new(math.cos(a) * 16 * s, 8 * s + math.sin(a * 3) * 4 * s, math.sin(a) * 16 * s), col)
	end
end
function BUILD.lattice(f, c, s, n, col)
	local g = math.clamp(n, 2, 5)
	for x = 1, g do
		for z = 1, g do
			part(f, Block, Vector3.new(0.5, 14, 0.5) * s, c * CFrame.new((x - g / 2 - 0.5) * 8 * s, 7 * s, (z - g / 2 - 0.5) * 8 * s), col, Enum.Material.Neon, 0.3)
		end
	end
end
function BUILD.ice(f, c, s, n, col)
	for i = 1, math.clamp(n, 3, 16) do
		local a = i * 2.4
		local h = (6 + (i % 5) * 4) * s
		part(f, Block, Vector3.new(3, h, 3), c * CFrame.new(math.cos(a) * (8 + i) * s, h / 2, math.sin(a) * (8 + i) * s) * CFrame.Angles(math.rad(8), a, math.rad(8)), col, Enum.Material.Ice, 0.15)
	end
end

local kinds = {}
for id in BUILD do
	table.insert(kinds, id)
end
table.sort(kinds)

return {
	id = "Structure",
	channels = function(p)
		return { "structure:" .. p.kind }
	end,
	group = "structure",
	cost = function(p)
		return 6 + math.floor(p.count * p.scale / 2)
	end,
	gameplay = false,
	ownerOnly = false,
	kinds = kinds,
	params = {
		kind = { type = "enum", values = kinds, default = "ring" },
		count = { type = "number", min = 1, max = 24, default = 8, scales = true },
		scale = { type = "number", min = 0.4, max = 3, default = 1 },
		height = { type = "number", min = 0, max = 80, default = 30 },
		color = { type = "color", default = { 255, 200, 90 } },
	},
	start = function(ctx, p)
		local folder = Instance.new("Folder")
		folder.Name = "Structure_" .. p.kind
		folder.Parent = ctx.worldRoot
		local centre = CFrame.new(ctx.center() + Vector3.new(0, p.height, 0))
		BUILD[p.kind](folder, centre, p.scale, math.floor(p.count), Params.color3(p.color))
		-- hard cap, whatever a builder made
		local parts = folder:GetDescendants()
		for i = MAX_PARTS + 1, #parts do
			parts[i]:Destroy()
		end
		return function()
			folder:Destroy()
		end
	end,
}
