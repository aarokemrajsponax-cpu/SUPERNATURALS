-- Easter: giant painted eggs on a grassy hill, bunny statues,
-- flower beds and little eggs hidden all over the map.

local rgb = Color3.fromRGB

local PASTELS = {
	rgb(255, 180, 210),
	rgb(180, 210, 255),
	rgb(200, 240, 200),
	rgb(255, 240, 170),
	rgb(215, 190, 255),
	rgb(255, 205, 170),
}

local function pastel(rng: Random, except: Color3?): Color3
	local color = PASTELS[rng:NextInteger(1, #PASTELS)]
	while color == except do
		color = PASTELS[rng:NextInteger(1, #PASTELS)]
	end
	return color
end

-- An egg with painted stripes, standing on base
local function egg(folder, Build, base: CFrame, width: number, height: number, rng: Random)
	local model = Build.model(folder, "Egg")
	local shell = pastel(rng)
	local stripe = pastel(rng, shell)
	local center = base * CFrame.new(0, height / 2, 0)
	Build.ellipsoid(model, Vector3.new(width, height, width), center, { Color = shell, Reflectance = 0.1 })
	-- Stripes hug the shell: narrower the further they are from the middle
	for _, offset in { -0.22, 0, 0.22 } do
		local y = offset * height
		local diameter = width * math.sqrt(1 - (2 * y / height) ^ 2) + 0.06
		Build.cylinder(model, height * 0.06, diameter, center * CFrame.new(0, y, 0), {
			Color = if offset == 0 then stripe else Color3.new(1, 1, 1):Lerp(stripe, 0.5),
		})
	end
	return model
end

local function bunny(folder, Build, base: CFrame, fur: Color3)
	local model = Build.model(folder, "Bunny")
	local coat = { Color = fur }
	local pink = { Color = rgb(255, 170, 190) }
	local dark = { Color = rgb(30, 25, 30) }

	Build.ellipsoid(model, Vector3.new(2.8, 3.2, 2.6), base * CFrame.new(0, 1.6, 0), coat)
	Build.ball(model, 0.9, base * CFrame.new(0, 1.1, 1.3), { Color = Color3.new(1, 1, 1) })
	for _, side in { -1, 1 } do
		Build.ellipsoid(model, Vector3.new(0.9, 0.5, 1.6), base * CFrame.new(side * 0.7, 0.25, -0.8), coat)
	end

	local head = base * CFrame.new(0, 3.6, -0.5)
	Build.ball(model, 2.1, head, coat)
	for _, side in { -1, 1 } do
		local ear = head * CFrame.new(side * 0.45, 1.6, 0.1) * CFrame.Angles(0, 0, side * -0.15)
		Build.ellipsoid(model, Vector3.new(0.55, 2.2, 0.3), ear, coat)
		Build.ellipsoid(model, Vector3.new(0.3, 1.6, 0.1), ear * CFrame.new(0, 0, -0.14), pink)
		Build.ball(model, 0.3, head * CFrame.new(side * 0.4, 0.2, -0.92), dark)
	end
	Build.ball(model, 0.3, head * CFrame.new(0, -0.15, -1.02), pink)
end

local function flowerBed(folder, Build, base: CFrame, rng: Random)
	local model = Build.model(folder, "FlowerBed")
	Build.cylinder(model, 0.3, 5, base * CFrame.new(0, 0.15, 0), { Color = rgb(90, 60, 40), Material = Enum.Material.Ground })
	for i = 1, 7 do
		local angle = i / 7 * math.pi * 2
		local radius = if i == 7 then 0 else 1.6
		local stemHeight = rng:NextNumber(1.2, 1.8)
		local stand = base * CFrame.new(math.cos(angle) * radius, 0.3, math.sin(angle) * radius)
		Build.cylinder(model, stemHeight, 0.12, stand * CFrame.new(0, stemHeight / 2, 0), { Color = rgb(60, 150, 60), CanCollide = false })
		local top = stand * CFrame.new(0, stemHeight, 0)
		Build.ball(model, 0.45, top, { Color = rgb(255, 215, 60), CanCollide = false })
		local petals = pastel(rng)
		for p = 0, 5 do
			Build.ellipsoid(model, Vector3.new(0.6, 0.15, 0.32), top * CFrame.Angles(0, math.rad(p * 60), 0) * CFrame.new(0.4, 0, 0), {
				Color = petals,
				CanCollide = false,
			})
		end
	end
end

return function(folder: Folder, Build)
	local rng = Random.new(405)
	local feature = Build.featureSpot()

	-- A grassy hill with giant eggs
	Build.ellipsoid(folder, Vector3.new(20, 1.6, 15), feature * CFrame.new(0, 0, 0), { Color = rgb(110, 190, 90), Material = Enum.Material.Grass })
	local giantEggs = {
		{ 0, 0, 5, 6.8 },
		{ -4.4, 1, 3.6, 4.8 },
		{ 4.2, 0.8, 3.8, 5 },
		{ -2.2, -3.2, 2.6, 3.4 },
		{ 2.6, -3.4, 2.4, 3.2 },
	}
	for _, info in giantEggs do
		local tilt = CFrame.Angles(rng:NextNumber(-0.08, 0.08), rng:NextNumber(0, math.pi), rng:NextNumber(-0.08, 0.08))
		egg(folder, Build, feature * CFrame.new(info[1], 0.4, info[2]) * tilt, info[3], info[4], rng)
	end

	for _, side in { -1, 1 } do
		bunny(folder, Build, feature * CFrame.new(side * 12, 0, -2), if side < 0 then rgb(250, 248, 245) else rgb(215, 185, 150))
	end
	for _, spot in Build.ring(8, 30, math.pi / 8, 4) do
		flowerBed(folder, Build, spot, rng)
	end

	-- Little eggs hidden around the map
	local hidden = 0
	local tries = 0
	while hidden < 24 and tries < 200 do
		tries += 1
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(12, 55)
		local x = Build.CENTER.X + math.cos(angle) * radius
		local z = Build.CENTER.Z + math.sin(angle) * radius
		if Build.isClear(x, z, 1) and (Vector3.new(x, 0, z) - feature.Position * Vector3.new(1, 0, 1)).Magnitude > 13 then
			hidden += 1
			egg(folder, Build, Build.spot(x, z) * CFrame.Angles(0, 0, rng:NextNumber(-0.3, 0.3)), 0.8, 1.1, rng)
		end
	end
end
