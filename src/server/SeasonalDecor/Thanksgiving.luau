-- Thanksgiving: a candle-lit harvest table, autumn trees, hay bales and a pumpkin patch.

local rgb = Color3.fromRGB

local WOOD = rgb(140, 90, 50)
local LEAF_COLORS = { rgb(214, 92, 31), rgb(232, 140, 35), rgb(190, 50, 35), rgb(240, 190, 60), rgb(160, 60, 30) }
local PUMPKIN_COLORS = { rgb(235, 115, 20), rgb(210, 90, 20), rgb(240, 225, 190), rgb(225, 140, 40) }

local function autumnTree(folder, Build, base: CFrame, rng: Random)
	local model = Build.model(folder, "AutumnTree")
	local trunkHeight = rng:NextNumber(7, 9)
	Build.cylinder(model, trunkHeight, 1.3, base * CFrame.new(0, trunkHeight / 2, 0), {
		Color = rgb(95, 65, 45),
		Material = Enum.Material.Wood,
	})
	local top = base * CFrame.new(0, trunkHeight, 0)
	local clumps = {
		{ 0, 1, 0, 7 },
		{ 2.4, -0.4, 1, 5 },
		{ -2.4, -0.2, -0.8, 5.2 },
		{ 0.8, -0.6, -2.3, 4.6 },
		{ -0.9, -0.8, 2.3, 4.6 },
		{ 0.3, 2.6, 0.2, 4.4 },
	}
	for _, clump in clumps do
		Build.ball(model, clump[4] * rng:NextNumber(0.9, 1.1), top * CFrame.new(clump[1], clump[2], clump[3]), {
			Color = LEAF_COLORS[rng:NextInteger(1, #LEAF_COLORS)],
			Material = Enum.Material.Grass,
		})
	end
	-- Fallen leaves around the trunk
	Build.cylinder(model, 0.1, 8, base * CFrame.new(0, 0.05, 0), {
		Color = LEAF_COLORS[rng:NextInteger(1, #LEAF_COLORS)],
		Material = Enum.Material.Grass,
		CanCollide = false,
	})
end

local function hayBale(folder, Build, center: CFrame)
	local model = Build.model(folder, "HayBale")
	Build.part(model, {
		Size = Vector3.new(4, 2.2, 2.4),
		CFrame = center,
		Color = rgb(222, 190, 110),
		Material = Enum.Material.Fabric,
	})
	for _, x in { -1, 1 } do
		Build.part(model, {
			Size = Vector3.new(0.2, 2.25, 2.45),
			CFrame = center * CFrame.new(x, 0, 0),
			Color = rgb(150, 105, 55),
			Material = Enum.Material.Fabric,
		})
	end
end

local function candle(folder, Build, base: CFrame)
	Build.cylinder(folder, 0.9, 0.3, base * CFrame.new(0, 0.45, 0), { Color = rgb(250, 240, 220) })
	local flame = Build.ellipsoid(folder, Vector3.new(0.18, 0.35, 0.18), base * CFrame.new(0, 1.05, 0), {
		Color = rgb(255, 180, 60),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	Build.light(flame, rgb(255, 170, 80), 10, 1.5, true)
end

local function harvestTable(folder, Build, base: CFrame, rng: Random)
	local model = Build.model(folder, "HarvestTable")
	local wood = { Color = WOOD, Material = Enum.Material.WoodPlanks }
	local topY = 3
	Build.part(model, Build.withShape(wood, { Size = Vector3.new(12, 0.4, 4), CFrame = base * CFrame.new(0, topY, 0) }))
	for _, x in { -5.5, 5.5 } do
		for _, z in { -1.6, 1.6 } do
			Build.part(model, Build.withShape(wood, { Size = Vector3.new(0.4, topY, 0.4), CFrame = base * CFrame.new(x, topY / 2, z) }))
		end
	end
	-- Benches on both sides
	for _, z in { -3, 3 } do
		Build.part(model, Build.withShape(wood, { Size = Vector3.new(11, 0.35, 1.2), CFrame = base * CFrame.new(0, 1.8, z) }))
		for _, x in { -5, 5 } do
			Build.part(model, Build.withShape(wood, { Size = Vector3.new(0.35, 1.8, 0.35), CFrame = base * CFrame.new(x, 0.9, z) }))
		end
	end
	Build.part(model, {
		Size = Vector3.new(12.05, 0.05, 1.5),
		CFrame = base * CFrame.new(0, topY + 0.22, 0),
		Color = rgb(200, 90, 30),
		Material = Enum.Material.Fabric,
	})

	local onTable = base * CFrame.new(0, topY + 0.25, 0)
	-- Pies
	for _, x in { -4, 0.5, 4.5 } do
		Build.cylinder(model, 0.45, 1.9, onTable * CFrame.new(x, 0.22, 0), { Color = rgb(205, 145, 75) })
		Build.cylinder(model, 0.05, 1.5, onTable * CFrame.new(x, 0.46, 0), { Color = rgb(185, 85, 30) })
	end
	-- A bowl of apples
	Build.cylinder(model, 0.4, 1.8, onTable * CFrame.new(-1.8, 0.2, 0.2), { Color = rgb(110, 70, 40), Material = Enum.Material.Wood })
	for i = 1, 5 do
		local angle = i / 5 * math.pi * 2
		Build.ball(model, 0.55, onTable * CFrame.new(-1.8 + math.cos(angle) * 0.45, 0.55, 0.2 + math.sin(angle) * 0.45), {
			Color = if i % 2 == 0 then rgb(200, 30, 30) else rgb(230, 60, 40),
			Reflectance = 0.15,
		})
	end
	-- Corn
	for _, x in { 2.4, 2.9 } do
		Build.ellipsoid(model, Vector3.new(0.45, 0.45, 1.4), onTable * CFrame.new(x, 0.25, -0.8) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0), {
			Color = rgb(245, 200, 60),
			Material = Enum.Material.Pebble,
		})
	end
	for _, x in { -3, 2.5 } do
		candle(model, Build, onTable * CFrame.new(x, 0, 0.9))
	end
end

return function(folder: Folder, Build)
	local rng = Random.new(1126)
	local feature = Build.featureSpot()

	harvestTable(folder, Build, feature, rng)
	for _, side in { -1, 1 } do
		autumnTree(folder, Build, feature * CFrame.new(side * 14, 0, 6), rng)
	end

	-- Pumpkin patch in front of the table
	for i = 1, 9 do
		local offset = Vector3.new(rng:NextNumber(-10, 10), 0, rng:NextNumber(-8, -4))
		Build.pumpkin(folder, feature * CFrame.new(offset) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng:NextNumber(0.5, 1.1), {
			color = PUMPKIN_COLORS[rng:NextInteger(1, #PUMPKIN_COLORS)],
		})
	end

	-- Hay bales stacked around the edge, with a pumpkin on top
	for _, spot in Build.ring(8, 30, math.pi / 8, 3) do
		hayBale(folder, Build, spot * CFrame.new(0, 1.1, 0))
		hayBale(folder, Build, spot * CFrame.new(0, 1.1, -2.5))
		hayBale(folder, Build, spot * CFrame.new(0, 3.3, -1.25))
		Build.pumpkin(folder, spot * CFrame.new(0, 4.4, -1.25), 0.7, { color = PUMPKIN_COLORS[rng:NextInteger(1, #PUMPKIN_COLORS)] })
	end

	for _, spot in Build.ring(7, 50, 0.3, 4) do
		autumnTree(folder, Build, spot, rng)
	end
end
