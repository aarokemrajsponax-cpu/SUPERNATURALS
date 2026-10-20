-- Builds a luxury car in front of the spawn point when the game starts.

local CAR_POSITION = CFrame.new(0, 0, -25)

local BODY_COLOR = Color3.fromRGB(15, 15, 20)
local GOLD = Color3.fromRGB(212, 175, 55)
local CHROME = Color3.fromRGB(200, 200, 210)
local TIRE = Color3.fromRGB(25, 25, 25)

local old = workspace:FindFirstChild("LuxuryCar")
if old then
	old:Destroy()
end

local car = Instance.new("Model")
car.Name = "LuxuryCar"

local function makePart(name, size, offset, props)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		part[key] = value
	end
	-- Size and position go last so setting Shape can't change them
	part.Size = size
	part.CFrame = CAR_POSITION * offset
	part.Parent = car
	return part
end

local paint = {
	Color = BODY_COLOR,
	Material = Enum.Material.SmoothPlastic,
	Reflectance = 0.25,
}

-- Body
makePart("Body", Vector3.new(16, 1.6, 7), CFrame.new(0, 1.8, 0), paint)
makePart("Hood", Vector3.new(4, 0.4, 6.6), CFrame.new(5.5, 2.75, 0), paint)
makePart("Trunk", Vector3.new(3, 0.4, 6.6), CFrame.new(-6, 2.75, 0), paint)
makePart("GoldStripe", Vector3.new(16.1, 0.15, 7.1), CFrame.new(0, 2.2, 0), {
	Color = GOLD,
	Material = Enum.Material.Metal,
	Reflectance = 0.3,
})

-- Cabin (walk through the glass to reach the seats)
makePart("Glass", Vector3.new(7, 1.8, 6.4), CFrame.new(-0.5, 3.5, 0), {
	Color = Color3.fromRGB(40, 60, 80),
	Material = Enum.Material.Glass,
	Transparency = 0.4,
	CanCollide = false,
})
makePart("Roof", Vector3.new(5.5, 0.3, 6.4), CFrame.new(-0.8, 4.55, 0), paint)

-- Seats face the front of the car (+X)
local seatFacing = CFrame.Angles(0, math.rad(-90), 0)
for i, z in { 1.5, -1.5 } do
	local seat = Instance.new("Seat")
	seat.Name = i == 1 and "DriverSeat" or "PassengerSeat"
	seat.Size = Vector3.new(2, 0.5, 2)
	seat.CFrame = CAR_POSITION * CFrame.new(-0.5, 2.85, z) * seatFacing
	seat.Anchored = true
	seat.Color = Color3.fromRGB(120, 70, 40)
	seat.Material = Enum.Material.Leather
	seat.Parent = car
end

-- Wheels with chrome rims
local wheelTurn = CFrame.Angles(0, math.rad(90), 0)
for _, x in { 5, -5 } do
	for _, z in { 3.3, -3.3 } do
		makePart("Wheel", Vector3.new(1, 3, 3), CFrame.new(x, 1.5, z) * wheelTurn, {
			Shape = Enum.PartType.Cylinder,
			Color = TIRE,
			Material = Enum.Material.Rubber,
		})
		makePart("Rim", Vector3.new(1.1, 2, 2), CFrame.new(x, 1.5, z) * wheelTurn, {
			Shape = Enum.PartType.Cylinder,
			Color = CHROME,
			Material = Enum.Material.Metal,
			Reflectance = 0.5,
		})
	end
end

-- Front: gold grille and headlights
makePart("Grille", Vector3.new(0.2, 0.8, 3), CFrame.new(8.05, 1.7, 0), {
	Color = GOLD,
	Material = Enum.Material.Metal,
	Reflectance = 0.4,
})
for _, z in { 2.4, -2.4 } do
	local headlight = makePart("Headlight", Vector3.new(0.2, 0.5, 1.4), CFrame.new(8.05, 2.1, z), {
		Color = Color3.fromRGB(255, 255, 240),
		Material = Enum.Material.Neon,
	})
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Right
	light.Range = 30
	light.Brightness = 3
	light.Parent = headlight
end

-- Back: taillights and spoiler
for _, z in { 2.4, -2.4 } do
	makePart("Taillight", Vector3.new(0.2, 0.5, 1.4), CFrame.new(-8.05, 2.1, z), {
		Color = Color3.fromRGB(255, 20, 20),
		Material = Enum.Material.Neon,
	})
end
for _, z in { 2.5, -2.5 } do
	makePart("SpoilerStand", Vector3.new(0.3, 0.6, 0.3), CFrame.new(-7.2, 3.25, z), paint)
end
makePart("Spoiler", Vector3.new(1.2, 0.2, 6.6), CFrame.new(-7.2, 3.65, 0), {
	Color = GOLD,
	Material = Enum.Material.Metal,
	Reflectance = 0.3,
})

car.PrimaryPart = car:FindFirstChild("Body")
car.Parent = workspace
