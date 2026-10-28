-- Building blocks shared by every holiday's decorations.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Seasons = require(ReplicatedStorage.Shared.Seasons)

local Build = {}

Build.Tags = Seasons.Tags

-- Decorations are arranged around the spawn point
Build.CENTER = Vector3.new(0, 0, 0)

-- Spots decorations stay away from
Build.KEEP_CLEAR = {
	{ position = Vector3.new(0, 0, 0), radius = 13 }, -- spawn dais
	{ position = Vector3.new(0, 0, -25), radius = 13 }, -- luxury car
	{ position = Vector3.new(0, 0, 40), radius = 18 }, -- each holiday's main display (see featureSpot)
}

local SKIP = { ClassName = true, Size = true, CFrame = true }

function Build.part(parent: Instance, props: { [string]: any }): BasePart
	local part = Instance.new(props.ClassName or "Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		if not SKIP[key] then
			part[key] = value
		end
	end
	-- Size and position go last so setting Shape can't change them
	if props.Size then
		part.Size = props.Size
	end
	if props.CFrame then
		part.CFrame = props.CFrame
	end
	part.Parent = parent
	return part
end

local function withShape(props, extra)
	local merged = table.clone(props or {})
	for key, value in extra do
		merged[key] = value
	end
	return merged
end

function Build.ball(parent, diameter: number, cframe: CFrame, props)
	return Build.part(parent, withShape(props, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		CFrame = cframe,
	}))
end

-- A standing cylinder centered on cframe
function Build.cylinder(parent, height: number, diameter: number, cframe: CFrame, props)
	return Build.part(parent, withShape(props, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = cframe * CFrame.Angles(0, 0, math.rad(90)),
	}))
end

-- A smooth stretched sphere (eggs, pumpkins, balloons...)
function Build.ellipsoid(parent, size: Vector3, cframe: CFrame, props)
	local part = Build.part(parent, withShape(props, { Size = size, CFrame = cframe }))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- A thin rod from one point to another (strings, branches)
function Build.rod(parent, from: Vector3, to: Vector3, thickness: number, props)
	local length = (to - from).Magnitude
	return Build.part(parent, withShape(props, {
		Size = Vector3.new(thickness, thickness, length),
		CFrame = CFrame.lookAt((from + to) / 2, to),
	}))
end

function Build.light(part: Instance, color: Color3, range: number, brightness: number, flicker: boolean?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
	if flicker then
		CollectionService:AddTag(light, Build.Tags.Flicker)
	end
	return light
end

function Build.model(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

function Build.tag(instance: Instance, tag: string)
	CollectionService:AddTag(instance, tag)
	-- Animated models must arrive on the client all at once, or pieces get left behind
	if instance:IsA("Model") then
		instance.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end
	return instance
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- Height of the floor at (x, z), so decorations sit on whatever ground the place has
function Build.groundY(x: number, z: number): number
	local ignore = {}
	for _, name in { "SeasonalDecor", "LuxuryCar" } do
		local thing = workspace:FindFirstChild(name)
		if thing then
			table.insert(ignore, thing)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore

	local result = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), rayParams)
	return if result then result.Position.Y else 0
end

-- A spot on the ground at (x, z) that faces the center
function Build.spot(x: number, z: number): CFrame
	local position = Vector3.new(x, Build.groundY(x, z), z)
	local target = Vector3.new(Build.CENTER.X, position.Y, Build.CENTER.Z)
	if (target - position).Magnitude < 0.01 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, target)
end

-- The main display for each holiday sits here, across from the car
function Build.featureSpot(): CFrame
	return Build.spot(Build.CENTER.X, Build.CENTER.Z + 40)
end

function Build.isClear(x: number, z: number, margin: number?): boolean
	for _, zone in Build.KEEP_CLEAR do
		local distance = (Vector2.new(x, z) - Vector2.new(zone.position.X, zone.position.Z)).Magnitude
		if distance < zone.radius + (margin or 0) then
			return false
		end
	end
	return true
end

-- Evenly spaced spots on a circle around the center, skipping blocked ones
function Build.ring(count: number, radius: number, angleOffset: number?, margin: number?): { CFrame }
	local spots = {}
	for i = 0, count - 1 do
		local angle = (angleOffset or 0) + i / count * math.pi * 2
		local x = Build.CENTER.X + math.cos(angle) * radius
		local z = Build.CENTER.Z + math.sin(angle) * radius
		if Build.isClear(x, z, margin) then
			table.insert(spots, Build.spot(x, z))
		end
	end
	return spots
end

-- Shapes used by more than one holiday ------------------------------------

-- base is a spot on the ground; the face (if carved) points along base.LookVector
function Build.pumpkin(parent, base: CFrame, scale: number, options: { carved: boolean?, color: Color3? }?)
	local carved = options and options.carved
	local color = options and options.color or Color3.fromRGB(235, 115, 20)
	local model = Build.model(parent, "Pumpkin")
	local height = 2.4 * scale
	local center = base * CFrame.new(0, height / 2, 0)

	-- Four overlapping ovals make the ribbed shape
	for i = 0, 3 do
		Build.ellipsoid(model, Vector3.new(3 * scale, height, 1.9 * scale), center * CFrame.Angles(0, math.rad(i * 45), 0), {
			Color = color,
			Reflectance = 0.05,
		})
	end
	Build.cylinder(model, 0.7 * scale, 0.35 * scale, center * CFrame.new(0, height / 2 + 0.2 * scale, 0) * CFrame.Angles(0.2, 0, 0.15), {
		Color = Color3.fromRGB(90, 105, 45),
		Material = Enum.Material.Wood,
	})

	if carved then
		local glow = {
			Color = Color3.fromRGB(255, 190, 60),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		}
		local eyeSize = Vector3.new(0.45, 0.45, 0.35) * scale
		for _, side in { -1, 1 } do
			Build.part(model, withShape(glow, {
				Size = eyeSize,
				CFrame = center * CFrame.new(side * 0.55 * scale, 0.35 * scale, -1.38 * scale) * CFrame.Angles(0, 0, math.rad(45)),
			}))
		end
		-- Three pieces make a grin that curves up at the ends
		local grin = Build.part(model, withShape(glow, {
			Size = Vector3.new(0.6, 0.3, 0.35) * scale,
			CFrame = center * CFrame.new(0, -0.48 * scale, -1.36 * scale),
		}))
		for _, side in { -1, 1 } do
			Build.part(model, withShape(glow, {
				Size = Vector3.new(0.6, 0.3, 0.35) * scale,
				CFrame = center * CFrame.new(side * 0.5 * scale, -0.38 * scale, -1.3 * scale) * CFrame.Angles(0, 0, side * math.rad(18)),
			}))
		end
		Build.light(grin, Color3.fromRGB(255, 140, 40), 10 + 4 * scale, 2, true)
	end
	return model
end

-- A puffy heart standing upright, centered on center, facing center.LookVector
function Build.heart(parent, center: CFrame, size: number, props)
	local model = Build.model(parent, "Heart")
	local depth = size * 0.7
	Build.part(model, withShape(props, {
		Size = Vector3.new(size, size, depth),
		CFrame = center * CFrame.Angles(0, 0, math.rad(45)),
	}))
	local offset = size / (2 * math.sqrt(2))
	for _, side in { -1, 1 } do
		Build.ellipsoid(model, Vector3.new(size, size, depth), center * CFrame.new(side * offset, offset, 0), props)
	end
	-- Set once the parts are in, so spinning turns it around its middle
	model.WorldPivot = center
	return model
end

-- How far below its center a heart's point reaches
function Build.heartDrop(size: number): number
	return size / math.sqrt(2)
end

function Build.present(parent, base: CFrame, size: Vector3, boxColor: Color3, ribbonColor: Color3)
	local model = Build.model(parent, "Present")
	local center = base * CFrame.new(0, size.Y / 2, 0)
	Build.part(model, { Size = size, CFrame = center, Color = boxColor, Reflectance = 0.1 })
	local ribbon = { Color = ribbonColor, Reflectance = 0.25 }
	Build.part(model, withShape(ribbon, {
		Size = Vector3.new(size.X + 0.05, size.Y + 0.05, size.Z * 0.18),
		CFrame = center,
	}))
	Build.part(model, withShape(ribbon, {
		Size = Vector3.new(size.X * 0.18, size.Y + 0.05, size.Z + 0.05),
		CFrame = center,
	}))
	local loop = Vector3.new(size.X * 0.4, size.Y * 0.3, size.Z * 0.2)
	for _, side in { -1, 1 } do
		Build.ellipsoid(model, loop, center * CFrame.new(side * size.X * 0.17, size.Y / 2 + loop.Y * 0.3, 0) * CFrame.Angles(0, 0, side * -0.5), ribbon)
	end
	return model
end

Build.withShape = withShape

return Build
