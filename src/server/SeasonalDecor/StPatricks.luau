-- St. Patrick's Day: a glowing rainbow with a pot of gold at each end,
-- a giant leprechaun hat and spinning four-leaf clovers.

local rgb = Color3.fromRGB

local GOLD = rgb(255, 200, 50)
local CLOVER = rgb(40, 170, 70)
local RAINBOW = {
	rgb(255, 60, 60),
	rgb(255, 150, 40),
	rgb(255, 230, 60),
	rgb(70, 220, 90),
	rgb(60, 160, 255),
	rgb(90, 80, 230),
	rgb(170, 80, 230),
}

local function rainbow(folder, Build, base: CFrame)
	local model = Build.model(folder, "Rainbow")
	local outerRadius = 16
	local bandWidth = 1.1
	local segments = 28
	for band, color in RAINBOW do
		local radius = outerRadius - (band - 1) * bandWidth
		local length = radius * math.pi / segments * 1.08
		for s = 0, segments - 1 do
			local angle = (s + 0.5) / segments * math.pi
			Build.part(model, {
				Size = Vector3.new(bandWidth, length, 1.6),
				CFrame = base * CFrame.Angles(0, 0, angle) * CFrame.new(radius, 0, 0),
				Color = color,
				Material = Enum.Material.Neon,
				Transparency = 0.1,
				CanCollide = false,
				CastShadow = false,
			})
		end
	end
end

local function potOfGold(folder, Build, base: CFrame, rng: Random)
	local model = Build.model(folder, "PotOfGold")
	local iron = { Color = rgb(20, 20, 25), Reflectance = 0.2 }
	local gold = { Color = GOLD, Material = Enum.Material.Metal, Reflectance = 0.5 }
	Build.ellipsoid(model, Vector3.new(3.6, 3, 3.6), base * CFrame.new(0, 1.6, 0), iron)
	Build.cylinder(model, 0.35, 3.3, base * CFrame.new(0, 2.85, 0), iron)
	local pile = Build.cylinder(model, 0.3, 3, base * CFrame.new(0, 2.95, 0), gold)
	for _ = 1, 14 do
		local offset = Vector3.new(rng:NextNumber(-1.1, 1.1), rng:NextNumber(3.05, 3.5), rng:NextNumber(-1.1, 1.1))
		Build.cylinder(model, 0.12, 0.6, base * CFrame.new(offset) * CFrame.Angles(rng:NextNumber(-0.6, 0.6), 0, rng:NextNumber(-0.6, 0.6)), gold)
	end
	-- Spilled coins on the ground
	for _ = 1, 8 do
		local offset = Vector3.new(rng:NextNumber(-3, 3), 0.06, rng:NextNumber(-3.5, -1.8))
		Build.cylinder(model, 0.12, 0.6, base * CFrame.new(offset), gold)
	end
	Build.light(pile, GOLD, 16, 2)

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(GOLD)
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new(0.3, 0)
	sparkle.Rate = 8
	sparkle.Lifetime = NumberRange.new(1, 2)
	sparkle.Speed = NumberRange.new(1, 3)
	sparkle.SpreadAngle = Vector2.new(30, 30)
	sparkle.Parent = pile
end

local function leprechaunHat(folder, Build, base: CFrame)
	local model = Build.model(folder, "LeprechaunHat")
	local felt = { Color = rgb(20, 120, 50), Material = Enum.Material.Fabric }
	Build.cylinder(model, 0.4, 7, base * CFrame.new(0, 0.2, 0), felt)
	Build.cylinder(model, 4.5, 4.6, base * CFrame.new(0, 2.65, 0), felt)
	Build.cylinder(model, 0.8, 4.66, base * CFrame.new(0, 1.2, 0), { Color = rgb(20, 20, 25) })
	-- Gold buckle on the band
	local buckle = base * CFrame.new(0, 1.2, -2.34)
	local gold = { Color = GOLD, Material = Enum.Material.Metal, Reflectance = 0.5 }
	for _, y in { -0.5, 0.5 } do
		Build.part(model, Build.withShape(gold, { Size = Vector3.new(1.2, 0.2, 0.1), CFrame = buckle * CFrame.new(0, y, 0) }))
	end
	for _, x in { -0.5, 0.5 } do
		Build.part(model, Build.withShape(gold, { Size = Vector3.new(0.2, 1.2, 0.1), CFrame = buckle * CFrame.new(x, 0, 0) }))
	end
end

local function clover(folder, Build, base: CFrame)
	local model = Build.model(folder, "Clover")
	local stemHeight = 3.5
	Build.cylinder(model, stemHeight, 0.25, base * CFrame.new(0, stemHeight / 2, 0), { Color = rgb(30, 120, 50) })

	local leaves = Build.model(model, "Leaves")
	local center = base * CFrame.new(0, stemHeight + 1.6, 0)
	local size = 1.4
	for k = 0, 3 do
		local leaf = center * CFrame.Angles(0, 0, math.rad(k * 90 + 45)) * CFrame.new(0, Build.heartDrop(size), 0)
		Build.heart(leaves, leaf, size, { Color = CLOVER, CanCollide = false })
	end
	leaves.WorldPivot = center
	Build.tag(leaves, Build.Tags.Spin)
end

return function(folder: Folder, Build)
	local rng = Random.new(317)
	local feature = Build.featureSpot()

	rainbow(folder, Build, feature)
	for _, side in { -1, 1 } do
		potOfGold(folder, Build, feature * CFrame.new(side * 12.7, 0, 0), rng)
	end
	leprechaunHat(folder, Build, feature)

	for _, spot in Build.ring(10, 30, 0, 3) do
		clover(folder, Build, spot)
	end
end
