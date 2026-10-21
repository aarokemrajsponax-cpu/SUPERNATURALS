-- Builds the Nexus lobby when the server starts (see Server/World/Nexus.luau)
-- and retires the template's grey baseplate and spawn, at runtime only: the
-- place file in Studio is never changed. The gateways' prompts are handled by
-- each player's client, which sends the same requests the menus do (the
-- server checks those as usual).

local Nexus = require(script.Parent.Parent.World.Nexus)

local WorldService = {}

-- The template baseplate is a huge flat part; anything this wide called Baseplate is it
local BASEPLATE_MIN_WIDTH = 400

function WorldService:Init(services)
	self.services = services
end

function WorldService:Start()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") and baseplate.Size.X >= BASEPLATE_MIN_WIDTH then
		baseplate:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "Nexus"
	local ok, result = pcall(Nexus.build, folder)
	if not ok then
		warn("[World] The lobby didn't finish building: " .. tostring(result))
	end
	folder.Parent = workspace

	-- Any other spawn point in the place now leads to the Nexus dais too
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
