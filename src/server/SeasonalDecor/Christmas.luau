-- Christmas: snow on the ground, a decorated tree with twinkling lights and a
-- spinning star, presents, snowmen and candy cane lamp posts.

local rgb = Color3.fromRGB

local SNOW = rgb(245, 250, 255)
local ORNAMENTS = { rgb(200, 30, 45), rgb(255, 200, 70), rgb(40, 90, 200), rgb(220, 220, 235), rgb(160, 40, 160) }
local FAIRY_LIGHTS = { rgb(255, 230, 170), rgb(255, 80, 80), rgb(80, 200, 255), rgb(120, 255, 120), rgb(255, 210, 60) }
local PRESENTS = {
	{ rgb(200, 30, 45), rgb(255, 215, 120) },
	{ rgb(20, 110, 60), rgb(240, 240, 240) },
	{ rgb(40, 80, 180), rgb(220, 220, 235) },
	{ rgb(245, 245, 245), rgb(200, 30, 45) },
	{ rgb(130, 40, 150), rgb(255, 215, 120) },
}

local function christmasTree(folder, Build, base: CFrame, rng: Random)
	local model = Build.model(folder, "ChristmasTree")
	Build.cylinder(model, 3, 2, base * CFrame.new(0, 1.5, 0), { Color = rgb(90, 60, 40), Material = Enum.Material.Wood })

	-- Stacked layers of branches, each dusted with snow and hung with ornaments
	local tiers = {}
	local y = 2.5
	local count = 6
	for i = 1, count do
		local diameter = 16 - (i - 1) / (count - 1) * 12
		local height = 2.6
		Build.cylinder(model, height, diameter, base * CFrame.new(0, y + height / 2, 0), {
			Color = rgb(25, 95 + i * 5, 50),
			Material = Enum.Material.Grass,
		})
		Build.cylinder(model, 0.15, diameter * 0.9, base * CFrame.new(0, y + height + 0.05, 0), {
			Color = SNOW,
			Material = Enum.Material.Snow,
		})
		local ornaments = math.floor(diameter * 1.1)
		for k = 1, ornaments do
			local angle = k / ornaments * math.pi * 2 + i
			local radius = diameter / 2
			Build.ball(model, 0.8, base * CFrame.new(math.cos(angle) * radius, y + 0.4, math.sin(angle) * radius), {
				Color = ORNAMENTS[rng:NextInteger(1, #ORNAMENTS)],
				Reflectance = 0.35,
				CanCollide = false,
			})
		end
		table.insert(tiers, { bottom = y, top = y + height, radius = diameter / 2 })
		y += height * 0.75
	end
	local treeTop = tiers[#tiers].top

	-- Fairy lights spiralling up the tree
	local lights = 70
	for j = 0, lights - 1 do
		local f = j / lights
		local lightY = 3 + f * (treeTop - 3.5)
		local radius = 1
		for _, tier in tiers do
			if lightY >= tier.bottom and lightY <= tier.top then
				radius = tier.radius
			end
		end
		local angle = f * math.pi * 2 * 5
		local bulb = Build.ball(model, 0.35, base * CFrame.new(math.cos(angle) * (radius + 0.1), lightY, math.sin(angle) * (radius + 0.1)), {
			Color = FAIRY_LIGHTS[j % #FAIRY_LIGHTS + 1],
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
		Build.tag(bulb, Build.Tags.Twinkle)
	end

	-- The star on top
	local starCenter = base * CFrame.new(0, treeTop + 1.3, 0)
	local star = Build.model(model, "Star")
	local gold = { Color = rgb(255, 215, 80), Material = Enum.Material.Neon, CanCollide = false }
	local first = Build.part(star, Build.withShape(gold, { Size = Vector3.new(2.2, 2.2, 0.45), CFrame = starCenter }))
	Build.part(star, Build.withShape(gold, { Size = Vector3.new(2.2, 2.2, 0.45), CFrame = starCenter * CFrame.Angles(0, 0, math.rad(45)) }))
	Build.light(first, rgb(255, 220, 120), 24, 3)
	star.WorldPivot = starCenter
	Build.tag(star, Build.Tags.Spin)

	-- Presents under the tree
	for i = 1, 10 do
		local angle = i / 10 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local radius = rng:NextNumber(8.6, 10)
		local colors = PRESENTS[rng:NextInteger(1, #PRESENTS)]
		local size = Vector3.new(rng:NextNumber(1.4, 2.6), rng:NextNumber(1.2, 2.4), rng:NextNumber(1.4, 2.6))
		local spot = base * CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		Build.present(folder, spot, size, colors[1], colors[2])
	end
end

local function snowman(folder, Build, base: CFrame)
	local model = Build.model(folder, "Snowman")
	local snow = { Color = SNOW, Material = Enum.Material.Snow }
	local coal = { Color = rgb(25, 25, 30), CanCollide = false }
	Build.ball(model, 3.4, base * CFrame.new(0, 1.6, 0), snow)
	Build.ball(model, 2.5, base * CFrame.new(0, 3.8, 0), snow)
	local head = base * CFrame.new(0, 5.5, 0)
	Build.ball(model, 1.8, head, snow)

	for _, side in { -1, 1 } do
		Build.ball(model, 0.25, head * CFrame.new(side * 0.35, 0.2, -0.8), coal)
	end
	for _, y in { 3.4, 3.9, 4.4 } do
		Build.ball(model, 0.28, base * CFrame.new(0, y, -1.2), coal)
	end
	-- Carrot nose
	Build.part(model, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.9, 0.25, 0.25),
		CFrame = head * CFrame.new(0, 0, -1.2) * CFrame.Angles(0, math.rad(90), 0),
		Color = rgb(240, 120, 30),
		CanCollide = false,
	})
	-- Scarf and hat
	Build.cylinder(model, 0.4, 1.9, base * CFrame.new(0, 4.75, 0), { Color = rgb(200, 30, 45), Material = Enum.Material.Fabric })
	Build.part(model, {
		Size = Vector3.new(0.5, 1.4, 0.15),
		CFrame = base * CFrame.new(0.5, 4.1, -1.2) * CFrame.Angles(0.3, 0, 0.1),
		Color = rgb(200, 30, 45),
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})
	local hat = { Color = rgb(20, 20, 25) }
	Build.cylinder(model, 0.15, 1.8, head * CFrame.new(0, 0.75, 0), hat)
	Build.cylinder(model, 1.2, 1.15, head * CFrame.new(0, 1.4, 0), hat)
	Build.cylinder(model, 0.25, 1.17, head * CFrame.new(0, 1, 0), { Color = rgb(200, 30, 45) })
	-- Stick arms
	local stick = { Color = rgb(90, 60, 40), Material = Enum.Material.Wood, CanCollide = false }
	for _, side in { -1, 1 } do
		local shoulder = base * CFrame.new(side * 1, 4, 0)
		Build.rod(model, shoulder.Position, (base * CFrame.new(side * 2.8, 5, 0)).Position, 0.15, stick)
	end
end

local function candyCaneLamp(folder, Build, base: CFrame)
	local model = Build.model(folder, "CandyCaneLamp")
	for s = 0, 9 do
		Build.cylinder(model, 0.8, 0.5, base * CFrame.new(0, s * 0.8 + 0.4, 0), {
			Color = if s % 2 == 0 then rgb(210, 30, 40) else rgb(250, 250, 250),
		})
	end
	local bulb = Build.ball(model, 1.2, base * CFrame.new(0, 8.5, 0), {
		Color = rgb(255, 230, 180),
		Material = Enum.Material.Neon,
	})
	Build.light(bulb, rgb(255, 210, 150), 16, 1.5)
	-- A little holly sprig
	for _, side in { -1, 1 } do
		Build.ellipsoid(model, Vector3.new(0.7, 0.2, 0.35), base * CFrame.new(side * 0.4, 7.7, -0.3) * CFrame.Angles(0, 0, side * 0.4), {
			Color = rgb(20, 110, 50),
		})
	end
	Build.ball(model, 0.25, base * CFrame.new(0, 7.75, -0.35), { Color = rgb(220, 20, 30) })
end

return function(folder: Folder, Build)
	local rng = Random.new(1225)
	local feature = Build.featureSpot()

	-- A blanket of snow around spawn (thin and walk-through, so feet sink in a little)
	local groundY = Build.groundY(Build.CENTER.X + 15, Build.CENTER.Z + 15)
	Build.cylinder(folder, 0.2, 150, CFrame.new(Build.CENTER.X, groundY + 0.1, Build.CENTER.Z), {
		Color = SNOW,
		Material = Enum.Material.Snow,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})

	christmasTree(folder, Build, feature, rng)
	for _, side in { -1, 1 } do
		snowman(folder, Build, feature * CFrame.new(side * 14, 0, -4))
	end
	for _, spot in Build.ring(10, 36, 0, 3) do
		candyCaneLamp(folder, Build, spot)
	end
end
