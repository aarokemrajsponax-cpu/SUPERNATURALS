-- Party Time: fireworks bursting all over the sky, confetti showers,
-- balloons floating up from the lobby, and the world cycling through the rainbow.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Common = require(script.Parent.Common)

local function balloon(position: Vector3)
	local color = Common.Rainbow[math.random(1, #Common.Rainbow)]
	local body = Common.part({
		Size = Vector3.new(2, 2.5, 2),
		CFrame = CFrame.new(position),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.25,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	local string_ = Common.part({
		Size = Vector3.new(0.05, 3, 0.05),
		CFrame = CFrame.new(position - Vector3.new(0, 2.7, 0)),
		Color = Color3.new(1, 1, 1),
		Material = Enum.Material.SmoothPlastic,
	})
	local rise = 60 + math.random() * 40
	local duration = 8 + math.random() * 4
	local drift = Vector3.new((math.random() - 0.5) * 20, rise, (math.random() - 0.5) * 20)
	Common.tween(body, duration, { CFrame = CFrame.new(position + drift) }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
	Common.tween(string_, duration, { CFrame = CFrame.new(position + drift - Vector3.new(0, 2.7, 0)) }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
	Debris:AddItem(body, duration)
	Debris:AddItem(string_, duration)
end

return function(context)
	local center = context.center
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "SNParty"
	grade.Saturation = 0.35
	grade.Parent = Lighting
	local restoreLight = Common.lighting({ ClockTime = 20.5, Brightness = 1 }, 2)

	local running = true
	task.spawn(function()
		local tick = 0
		while running and context.running() do
			task.wait(0.4)
			tick += 1
			local angle = math.random() * math.pi * 2
			local distance = 20 + math.random() * 60
			local launch = Common.ground(center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance))
			Common.firework(launch, 55 + math.random() * 35)
			if tick % 2 == 0 then
				Common.confetti(center + Vector3.new((math.random() - 0.5) * 60, 25, (math.random() - 0.5) * 60), 40)
			end
			if tick % 2 == 1 and not Common.reduced() then
				local spot = center + Vector3.new((math.random() - 0.5) * 50, 2, (math.random() - 0.5) * 50)
				balloon(Common.ground(spot) + Vector3.new(0, 3, 0))
			end
		end
	end)

	local connection = RunService.RenderStepped:Connect(function()
		grade.TintColor = Color3.new(1, 1, 1):Lerp(Common.hue(0), 0.2)
	end)

	return function()
		running = false
		connection:Disconnect()
		restoreLight()
		Common.tween(grade, 1.5, { Saturation = 0, TintColor = Color3.new(1, 1, 1) })
		Debris:AddItem(grade, 1.6)
	end
end
