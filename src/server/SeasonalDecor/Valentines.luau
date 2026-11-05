-- Valentine's Day: a giant glowing heart, spinning hearts on posts,
-- heart balloons and rose bushes.

local rgb = Color3.fromRGB

local RED = rgb(225, 30, 80)
local PINK = rgb(255, 130, 175)
local MARBLE = rgb(245, 240, 240)

local function roseBush(folder, Build, base: CFrame, rng: Random)
	local model = Build.model(folder, "RoseBush")
	local bush = base * CFrame.new(0, 1.4, 0)
	Build.ball(model, 3.2, bush, { Color = rgb(40, 110, 50), Material = Enum.Material.Grass })
	for _ = 1, 9 do
		local direction = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0, 1), rng:NextNumber(-1, 1)).Unit
		Build.ball(model, 0.65, bush * CFrame.new(direction * 1.55), {
			Color = if rng:NextNumber() < 0.7 then rgb(200, 20, 45) else PINK,
		})
	end
end

local function heartPost(folder, Build, base: CFrame, color: Color3)
	local model = Build.model(folder, "HeartPost")
	Build.cylinder(model, 0.4, 1.4, base * CFrame.new(0, 0.2, 0), { Color = MARBLE, Material = Enum.Material.Marble })
	Build.cylinder(model, 4, 0.4, base * CFrame.new(0, 2, 0), { Color = MARBLE, Material = Enum.Material.Marble })
	local size = 1.6
	local heart = Build.heart(model, base * CFrame.new(0, 4.1 + Build.heartDrop(size), 0), size, {
		Color = color,
		Reflectance = 0.25,
		CanCollide = false,
	})
	Build.light(heart:FindFirstChildWhichIsA("BasePart"), color, 12, 1.5)
	Build.tag(heart, Build.Tags.Spin)
end

local function heartBalloons(folder, Build, base: CFrame, rng: Random)
	local bunch = Build.model(folder, "HeartBalloons")
	for i = 1, 3 do
		local angle = i / 3 * math.pi * 2
		local size = 1.5
		local center = base * CFrame.new(math.cos(angle) * 1.2, rng:NextNumber(7, 8.5), math.sin(angle) * 1.2)
		Build.heart(bunch, center, size, {
			Color = if i == 2 then PINK else RED,
			Reflectance = 0.35,
			CanCollide = false,
		})
		Build.rod(bunch, base.Position, (center * CFrame.new(0, -Build.heartDrop(size), 0)).Position, 0.05, {
			Color = rgb(250, 250, 250),
			CanCollide = false,
		})
	end
	Build.tag(bunch, Build.Tags.Bob)
end

return function(folder: Folder, Build)
	local rng = Random.new(214)
	local feature = Build.featureSpot()

	-- The giant heart on a marble stand
	Build.cylinder(folder, 1.5, 9, feature * CFrame.new(0, 0.75, 0), { Color = MARBLE, Material = Enum.Material.Marble })
	Build.cylinder(folder, 0.3, 9.6, feature * CFrame.new(0, 0.15, 0), { Color = PINK })
	local size = 8
	local bigHeart = Build.heart(folder, feature * CFrame.new(0, 1.8 + Build.heartDrop(size), 0), size, {
		Color = RED,
		Reflectance = 0.25,
	})
	Build.light(bigHeart:FindFirstChildWhichIsA("BasePart"), rgb(255, 90, 140), 30, 2.5)

	for _, side in { -1, 1 } do
		roseBush(folder, Build, feature * CFrame.new(side * 9, 0, -1), rng)
		roseBush(folder, Build, feature * CFrame.new(side * 13, 0, 2), rng)
	end

	for i, spot in Build.ring(10, 30, 0, 3) do
		heartPost(folder, Build, spot, if i % 2 == 0 then PINK else RED)
	end
	for _, spot in Build.ring(6, 44, math.pi / 6, 3) do
		heartBalloons(folder, Build, spot, rng)
	end
	for _, spot in Build.ring(12, 52, 0.2, 4) do
		roseBush(folder, Build, spot, rng)
	end
end
