-- Brings the Nexus lobby to life on this client: the crystal turns and
-- floats, portal surfaces swirl, runes pulse and spirit fruit bob (only while
-- the camera is nearby, to save work). Also answers the gateway prompts by
-- sending the same requests the menus send, or opening the matching window.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Shell = require(script.Parent.Parent.UI.Shell)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchRequest = Remotes:WaitForChild("MatchRequest") :: RemoteEvent
local BaseRequest = Remotes:WaitForChild("BaseRequest") :: RemoteEvent

local WorldFxController = {}

-- Animate only while the camera is this close to the plaza
local ANIMATE_RANGE = 320
local FRAME_STEP = 1 / 30

local WINDOW_NAMES = { Play = "Play", Shop = "Shop", Watch = "Watch" }

function WorldFxController:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local action = prompt:GetAttribute("Action")
		if typeof(action) ~= "string" then
			return
		end
		local kind, argument = string.match(action, "^(%w+):(%w+)$")
		if kind == "Window" then
			local id = WINDOW_NAMES[argument]
			if id and Shell.hasWindow(id) then
				Shell.open(id)
			elseif id then
				Shell.toast("That opens soon.", "info")
			end
		elseif kind == "Travel" then
			MatchRequest:FireServer(Protocol.MatchAction.Travel, argument)
		elseif kind == "Base" and argument == "Home" then
			BaseRequest:FireServer(Protocol.BaseAction.Home)
		end
	end)

	task.spawn(function()
		local nexus = workspace:WaitForChild("Nexus", 30)
		if nexus then
			self:_animate(nexus)
		end
	end)
end

function WorldFxController:_animate(nexus: Instance)
	local crystal = nexus:FindFirstChild("NexusCrystal")
	local core = nexus:FindFirstChild("NexusCore")
	local crystalHome = if crystal and crystal:IsA("BasePart") then crystal.CFrame else nil
	local spinners, runes, fruit = {}, {}, {}
	for _, item in nexus:GetDescendants() do
		if item:IsA("BasePart") then
			if item:GetAttribute("Spin") then
				table.insert(spinners, { part = item, home = item.CFrame })
			elseif item:GetAttribute("Pulse") then
				table.insert(runes, { part = item, phase = item:GetAttribute("Pulse") :: number })
			elseif item:GetAttribute("Bob") then
				table.insert(fruit, { part = item, home = item.CFrame, phase = math.random() * 6 })
			end
		end
	end
	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if elapsed < FRAME_STEP then
			return
		end
		elapsed = 0
		local camera = workspace.CurrentCamera
		if camera.CFrame.Position.Magnitude > ANIMATE_RANGE then
			return
		end
		local time = os.clock()
		if crystalHome and crystal and core and crystal:IsA("BasePart") and core:IsA("BasePart") then
			local frame = CFrame.new(crystalHome.Position + Vector3.new(0, math.sin(time * 1.1) * 0.8, 0))
				* CFrame.Angles(0, time * 0.6, 0)
				* (CFrame.new(crystalHome.Position):Inverse() * crystalHome)
			crystal.CFrame = frame
			core.CFrame = frame
		end
		for _, spinner in spinners do
			spinner.part.CFrame = spinner.home * CFrame.Angles(time * 0.8, 0, 0)
		end
		for _, rune in runes do
			rune.part.Transparency = 0.2 + 0.45 * (math.sin(time * 1.6 + rune.phase) + 1) / 2
		end
		for _, item in fruit do
			item.part.CFrame = item.home + Vector3.new(0, math.sin(time * 1.4 + item.phase) * 0.3, 0)
		end
	end)
end

return WorldFxController
