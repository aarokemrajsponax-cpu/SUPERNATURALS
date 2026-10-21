-- Giant Party: a jungle-green colour grade, confetti cannons, and the ground
-- shaking under every giant's footsteps.

local Players = game:GetService("Players")

local Common = require(script.Parent.Common)
local Vfx = require(script.Parent.Parent.Vfx)

local GREEN = Color3.fromRGB(140, 255, 110)

return function(context)
	local _, ungrade = Common.colorGrade({ TintColor = Color3.fromRGB(235, 255, 225), Saturation = 0.25, Contrast = 0.08 })
	local running = true

	task.spawn(function()
		local tick = 0
		while running and context.running() do
			task.wait(0.6)
			tick += 1
			-- Stomps under big characters
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and root.Size.Y > 3 and root.AssemblyLinearVelocity.Magnitude > 4 then
					local ground = Common.ground(root.Position)
					Vfx.groundRing(ground + Vector3.new(0, 0.1, 0), GREEN, 3, 18, 0.5)
					if player == Players.LocalPlayer then
						context.shake(0.8, 0.2)
					end
				end
			end
			-- Confetti cannons around the lobby
			if tick % 3 == 0 then
				local angle = math.random() * math.pi * 2
				local spot = context.center + Vector3.new(math.cos(angle) * 30, 2, math.sin(angle) * 30)
				Common.confetti(spot, 60)
			end
		end
	end)

	return function()
		running = false
		ungrade()
	end
end
