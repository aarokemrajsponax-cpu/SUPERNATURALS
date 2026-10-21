-- Camera feedback for impacts: shake and a quick field-of-view punch.
-- Both respect the player's Screen Shake setting.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Settings = require(script.Parent.Parent.Settings)

local CameraController = {}

local shakeUntil = 0
local shakeStrength = 0
local BASE_FOV = 70

function CameraController:Start()
	RunService:BindToRenderStep("SNCameraShake", Enum.RenderPriority.Camera.Value + 1, function()
		local remaining = shakeUntil - os.clock()
		if remaining <= 0 then
			return
		end
		local camera = workspace.CurrentCamera
		local strength = shakeStrength * math.min(1, remaining * 6)
		local t = os.clock() * 40
		local offset = CFrame.Angles(
			math.rad(math.noise(t, 0) * strength),
			math.rad(math.noise(0, t) * strength),
			math.rad(math.noise(t, t) * strength * 0.5)
		)
		camera.CFrame *= offset
	end)
end

-- strength is in degrees of wobble; overlapping shakes keep the strongest
function CameraController:shake(strength: number, duration: number)
	if not Settings.get("cameraShake") then
		return
	end
	local time = os.clock()
	if time >= shakeUntil then
		shakeStrength = 0
	end
	shakeStrength = math.max(shakeStrength, strength)
	shakeUntil = math.max(shakeUntil, time + duration)
end

function CameraController:punch(amount: number)
	if not Settings.get("cameraShake") then
		return
	end
	local camera = workspace.CurrentCamera
	camera.FieldOfView = BASE_FOV + amount
	TweenService:Create(camera, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = BASE_FOV,
	}):Play()
end

return CameraController
