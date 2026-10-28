-- Brings the Nexus lobby to life on this client: the crystal hovers and
-- slowly turns in its cradle, the inlaid runes breathe, and the wisps in each
-- gateway's portal circle while its glow pulses (only while the camera is
-- nearby, to save work). Also answers the gateway prompts by sending the same
-- requests the menus send, or opening the matching window.

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
-- The crystal rises and falls this many studs, and turns this fast (radians per second)
local CRYSTAL_BOB = 0.35
local CRYSTAL_BOB_SPEED = 0.9
local CRYSTAL_TURN_SPEED = 0.3
-- How much the runes fade at the low point of their breath
local RUNE_DEPTH = 0.3

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
	local crystalHome = if crystal and crystal:IsA("BasePart") then crystal.CFrame else nil
	local crystalPieces, runes, wisps, glows = {}, {}, {}, {}
	for _, item in nexus:GetDescendants() do
		if item:IsA("BasePart") then
			if item:GetAttribute("Crystal") and crystalHome then
				table.insert(crystalPieces, { part = item, offset = crystalHome:ToObjectSpace(item.CFrame) })
			elseif item:GetAttribute("Pulse") then
				table.insert(runes, { part = item, phase = item:GetAttribute("Pulse") :: number, base = item.Transparency })
			elseif typeof(item:GetAttribute("Swirl")) == "number" then
				-- Wisps circle the middle of their gate's portal
				local portal = item.Parent and item.Parent:FindFirstChild("PortalSurface")
				if portal and portal:IsA("BasePart") then
					local pivot = portal.CFrame * CFrame.new(0, 0, -0.15)
					table.insert(wisps, { part = item, pivot = pivot, offset = pivot:ToObjectSpace(item.CFrame), speed = item:GetAttribute("Swirl") :: number })
				end
			elseif typeof(item:GetAttribute("Glow")) == "number" then
				table.insert(glows, { part = item, base = item:GetAttribute("Glow") :: number, phase = math.random() * 6 })
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
		if not camera or camera.CFrame.Position.Magnitude > ANIMATE_RANGE then
			return
		end
		local time = os.clock()
		if crystalHome then
			local pivot = CFrame.new(crystalHome.Position + Vector3.new(0, math.sin(time * CRYSTAL_BOB_SPEED) * CRYSTAL_BOB, 0))
				* CFrame.Angles(0, time * CRYSTAL_TURN_SPEED, 0)
				* crystalHome.Rotation
			for _, piece in crystalPieces do
				piece.part.CFrame = pivot * piece.offset
			end
		end
		for _, rune in runes do
			rune.part.Transparency = rune.base + RUNE_DEPTH * (math.sin(time * 1.3 + rune.phase) + 1) / 2
		end
		for _, wisp in wisps do
			wisp.part.CFrame = wisp.pivot * CFrame.Angles(0, 0, time * wisp.speed) * wisp.offset
		end
		for _, glow in glows do
			glow.part.Transparency = glow.base + 0.06 * math.sin(time * 0.9 + glow.phase)
		end
	end)
end

return WorldFxController
