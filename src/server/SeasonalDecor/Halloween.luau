-- Halloween: a giant jack-o'-lantern, a little graveyard, dead trees,
-- glowing pumpkins, purple lanterns and floating ghosts.

local rgb = Color3.fromRGB

local BARK = rgb(45, 35, 40)
local STONE = rgb(110, 110, 120)
local LANTERN_GLOW = rgb(160, 70, 255)

local function spookyTree(folder, Build, base: CFrame, rng: Random)
	local model = Build.model(folder, "SpookyTree")
	local bark = { Color = BARK, Material = Enum.Material.Wood }
	local height = rng:NextNumber(9, 11)
	Build.cylinder(model, height, 1.4, base * CFrame.new(0, height / 2, 0), bark)
	Build.cylinder(model, 0.6, 2.6, base * CFrame.new(0, 0.3, 0), bark)

	local branches = {
		{ y = 0.55, yaw = 0, tilt = 50, length = 4.5 },
		{ y = 0.65, yaw = 140, tilt = 45, length = 4 },
		{ y = 0.78, yaw = 250, tilt = 40, length = 3.6 },
		{ y = 0.88, yaw = 60, tilt = 30, length = 3 },
		{ y = 0.95, yaw = 200, tilt = 25, length = 2.6 },
	}
	for _, branch in branches do
		local start = base * CFrame.new(0, height * branch.y, 0) * CFrame.Angles(0, math.rad(branch.yaw), 0)
		local angled = start * CFrame.Angles(0, 0, math.rad(-branch.tilt))
		local tip = angled * CFrame.new(0, branch.length, 0)
		Build.rod(model, start.Position, tip.Position, 0.45, bark)
		-- A crooked twig off the end of each branch
		local twig = tip * CFrame.Angles(0, 0, math.rad(35)) * CFrame.new(0, branch.length * 0.45, 0)
		Build.rod(model, tip.Position, twig.Position, 0.25, bark)
	end
end

local function tombstone(folder, Build, base: CFrame, rng: Random)
	local model = Build.model(folder, "Tombstone")
	local tilted = base * CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), 0, math.rad(rng:NextNumber(-8, 8)))
	local stone = { Color = STONE, Material = Enum.Material.Slate }
	local slab = Build.part(model, Build.withShape(stone, {
		Size = Vector3.new(2.4, 2.4, 0.5),
		CFrame = tilted * CFrame.new(0, 1.2, 0),
	}))
	-- Rounded top
	Build.part(model, Build.withShape(stone, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 2.4, 2.4),
		CFrame = tilted * CFrame.new(0, 2.4, 0) * CFrame.Angles(0, math.rad(90), 0),
	}))
	-- Fresh dirt in front
	Build.ellipsoid(model, Vector3.new(2.6, 0.6, 3.6), base * CFrame.new(0, 0, -2.1), {
		Color = rgb(70, 50, 40),
		Material = Enum.Material.Ground,
	})

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 1
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.6)
	label.Position = UDim2.fromScale(0, 0.15)
	label.Text = "R.I.P."
	label.Font = Enum.Font.Fantasy
	label.TextScaled = true
	label.TextColor3 = rgb(40, 40, 50)
	label.Parent = gui
	gui.Parent = slab
end

local function lantern(folder, Build, base: CFrame)
	local model = Build.model(folder, "Lantern")
	local iron = { Color = rgb(25, 25, 30), Material = Enum.Material.Metal }
	Build.cylinder(model, 0.4, 1.4, base * CFrame.new(0, 0.2, 0), iron)
	Build.cylinder(model, 7, 0.3, base * CFrame.new(0, 3.5, 0), iron)
	Build.part(model, Build.withShape(iron, { Size = Vector3.new(1.4, 0.2, 1.4), CFrame = base * CFrame.new(0, 7.1, 0) }))
	Build.part(model, Build.withShape(iron, { Size = Vector3.new(0.9, 0.35, 0.9), CFrame = base * CFrame.new(0, 8.75, 0) }))
	local glass = Build.part(model, {
		Size = Vector3.new(1, 1.4, 1),
		CFrame = base * CFrame.new(0, 7.9, 0),
		Color = LANTERN_GLOW,
		Material = Enum.Material.Neon,
		Transparency = 0.1,
	})
	Build.light(glass, LANTERN_GLOW, 18, 1.5, true)
end

local function ghost(folder, Build, base: CFrame)
	local model = Build.model(folder, "Ghost")
	local sheet = {
		Color = rgb(245, 245, 255),
		Transparency = 0.15,
		CanCollide = false,
	}
	local body = Build.ellipsoid(model, Vector3.new(2.6, 3.2, 2.6), base, sheet)
	Build.ellipsoid(model, Vector3.new(2.3, 1.8, 2.3), base * CFrame.new(0, -1.5, 0), Build.withShape(sheet, { Transparency = 0.35 }))
	local face = { Color = rgb(20, 20, 30), CanCollide = false }
	for _, side in { -1, 1 } do
		Build.ellipsoid(model, Vector3.new(0.35, 0.6, 0.2), base * CFrame.new(side * 0.45, 0.4, -1.2), face)
	end
	Build.ellipsoid(model, Vector3.new(0.5, 0.55, 0.2), base * CFrame.new(0, -0.3, -1.25), face)
	Build.light(body, rgb(190, 210, 255), 10, 1)
	Build.tag(model, Build.Tags.Bob)
end

return function(folder: Folder, Build)
	local rng = Random.new(1031)
	local feature = Build.featureSpot()

	-- The giant jack-o'-lantern
	Build.pumpkin(folder, feature, 3.2, { carved = true })
	for _, offset in { Vector3.new(-6.5, 0, -2.5), Vector3.new(6.8, 0, -2), Vector3.new(-4.5, 0, -5.5) } do
		Build.pumpkin(folder, feature * CFrame.new(offset), rng:NextNumber(0.8, 1.1), { carved = true })
	end

	for _, side in { -1, 1 } do
		spookyTree(folder, Build, feature * CFrame.new(side * 17, 0, 3), rng)
	end
	for _, offset in { Vector3.new(-9, 0, 0), Vector3.new(9, 0, 0), Vector3.new(-12, 0, 5), Vector3.new(12, 0, 5), Vector3.new(-6, 0, 6), Vector3.new(6, 0, 6) } do
		tombstone(folder, Build, feature * CFrame.new(offset), rng)
	end

	-- Glowing pumpkins all the way around
	for _, spot in Build.ring(14, 28, 0, 3) do
		Build.pumpkin(folder, spot, rng:NextNumber(0.8, 1.3), { carved = true })
	end
	for _, spot in Build.ring(10, 44, math.pi / 10, 3) do
		lantern(folder, Build, spot)
	end
	for _, spot in Build.ring(5, 20, 0.4, 2) do
		ghost(folder, Build, spot * CFrame.new(0, rng:NextNumber(6, 8), 0))
	end
end
