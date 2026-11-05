-- Builds the Nexus lobby when the server starts (see Server/World/Nexus.luau)
-- and retires the template's grey baseplate and spawn, at runtime only: the
-- place file in Studio is never changed. It also sets the look of the land
-- everywhere: terrain colours, water, grass blades and the cloud layer.
-- The gateways' prompts are handled by each player's client, which sends the
-- same requests the menus do (the server checks those as usual).

local Nexus = require(script.Parent.Parent.World.Nexus)

local WorldService = {}

local rgb = Color3.fromRGB

-- The template baseplate is a huge flat part; anything this wide called Baseplate is it
local BASEPLATE_MIN_WIDTH = 400

-- A natural palette for the valley: warm grass, deeper leafy grass, cool grey rock
local TERRAIN_COLORS = {
	Grass = rgb(90, 108, 58),
	LeafyGrass = rgb(72, 94, 48),
	Ground = rgb(122, 104, 80),
	Mud = rgb(100, 86, 68),
	Rock = rgb(120, 118, 112),
	Slate = rgb(100, 102, 100),
	Sand = rgb(182, 166, 128),
}

-- Calm water with reflections, a deep teal
local WATER = {
	WaterColor = rgb(26, 78, 82),
	WaterTransparency = 0.4,
	WaterReflectance = 1,
	WaterWaveSize = 0.15,
	WaterWaveSpeed = 10,
}

-- A broken layer of warm white afternoon cloud
local CLOUDS = { Cover = 0.52, Density = 0.7, Color = rgb(255, 248, 238) }

function WorldService:Init(services)
	self.services = services
end

function WorldService:_dressTerrain()
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return
	end
	for name, color in TERRAIN_COLORS do
		pcall(function()
			terrain:SetMaterialColor((Enum.Material :: any)[name], color)
		end)
	end
	for key, value in WATER do
		pcall(function()
			(terrain :: any)[key] = value
		end)
	end
	-- Animated grass blades on Grass terrain
	pcall(function()
		(terrain :: any).Decoration = true
	end)
	pcall(function()
		local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
		clouds.Name = "Clouds"
		for key, value in CLOUDS do
			(clouds :: any)[key] = value
		end
		clouds.Parent = terrain
	end)
end

function WorldService:Start()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") and baseplate.Size.X >= BASEPLATE_MIN_WIDTH then
		baseplate:Destroy()
	end

	self:_dressTerrain()

	local folder = Instance.new("Folder")
	folder.Name = "Nexus"
	local ok, result = pcall(Nexus.build, folder)
	if not ok then
		warn("[World] The lobby didn't finish building: " .. tostring(result))
	end
	folder.Parent = workspace

	-- Any other spawn point in the place now leads to the Nexus spawn too
	local spawn = folder:FindFirstChild("NexusSpawn")
	for _, item in workspace:GetDescendants() do
		if item:IsA("SpawnLocation") and item ~= spawn then
			item.Enabled = false
			item.Transparency = 1
			item.CanCollide = false
			if spawn and spawn:IsA("BasePart") then
				item.CFrame = spawn.CFrame
			end
		end
	end
end

return WorldService
