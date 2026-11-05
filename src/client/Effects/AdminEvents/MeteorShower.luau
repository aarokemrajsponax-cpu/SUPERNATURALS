-- Meteor Shower: a smouldering red sky, falling embers, and blazing meteors
-- that streak down onto glowing warning circles and explode into rock and fire.

local Debris = game:GetService("Debris")

local Common = require(script.Parent.Common)
local Vfx = require(script.Parent.Parent.Vfx)

local FIRE = Color3.fromRGB(255, 120, 40)
local HOT = Color3.fromRGB(255, 220, 120)

local function warningCircle(position: Vector3, radius: number, duration: number)
	local ring = Common.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 2, 2),
		CFrame = CFrame.new(position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 60, 40),
		Transparency = 0.15,
	})
	Common.tween(ring, duration, { Size = Vector3.new(0.1, radius * 2, radius * 2), Transparency = 0.45 }, Enum.EasingStyle.Sine)
	Debris:AddItem(ring, duration)
end

local function meteor(context, data)
	local now = workspace:GetServerTimeNow()
	local travel = math.max(0.25, data.impactAt - now)
	local target: Vector3 = data.position
	local size: number = data.size
	warningCircle(target, context.def.radius, travel)

	local start = target + Vector3.new((math.random() - 0.5) * 120, 220, (math.random() - 0.5) * 120)
	local rock = Common.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * size,
		CFrame = CFrame.new(start),
		Color = Color3.fromRGB(60, 40, 35),
		Material = Enum.Material.Basalt,
	})
	local shell = Common.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * size * 1.35,
		CFrame = CFrame.new(start),
		Color = FIRE,
		Transparency = 0.35,
	})
	local fire = Instance.new("ParticleEmitter")
	fire.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, HOT),
		ColorSequenceKeypoint.new(0.4, FIRE),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 20, 10)),
	})
	fire.LightEmission = 1
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.9), NumberSequenceKeypoint.new(1, 0) })
	fire.Transparency = NumberSequence.new(0.1, 1)
	fire.Lifetime = NumberRange.new(0.5, 0.9)
	fire.Rate = if Common.reduced() then 30 else 90
	fire.Speed = NumberRange.new(1, 4)
	fire.SpreadAngle = Vector2.new(25, 25)
	fire.Parent = rock
	local light = Instance.new("PointLight")
	light.Color = FIRE
	light.Range = 40
	light.Brightness = 4
	light.Parent = rock

	Common.tween(rock, travel, { CFrame = CFrame.new(target) }, Enum.EasingStyle.Linear)
	local fall = Common.tween(shell, travel, { CFrame = CFrame.new(target) }, Enum.EasingStyle.Linear)
	fall.Completed:Once(function()
		rock:Destroy()
		shell:Destroy()
		if not context.running() then
			return
		end
		Vfx.shockwave(target, FIRE, 2, context.def.radius * 2.2, 0.45)
		Vfx.groundRing(target + Vector3.new(0, 0.1, 0), FIRE, 2, context.def.radius * 3, 0.6)
		Vfx.sparks(target + Vector3.new(0, 1, 0), HOT, 40, 45)
		Vfx.sound("HeavyHit", target)
		-- Chunks of rock flying out
		for _ = 1, if Common.reduced() then 3 else 9 do
			local chunk = Common.part({
				Size = Vector3.one * (0.6 + math.random() * 1.2),
				CFrame = CFrame.new(target + Vector3.new(0, 1.5, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
				Color = Color3.fromRGB(70, 50, 45),
				Material = Enum.Material.Basalt,
				Anchored = false,
			})
			local angle = math.random() * math.pi * 2
			chunk.AssemblyLinearVelocity = Vector3.new(math.cos(angle) * 30, 35 + math.random() * 30, math.sin(angle) * 30)
			Debris:AddItem(chunk, 2.5)
		end
		-- A scorch mark that cools down
		local scorch = Common.part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.06, context.def.radius * 1.4, context.def.radius * 1.4),
			CFrame = CFrame.new(target + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 90, 30),
			Transparency = 0.1,
		})
		Common.tween(scorch, 1.2, { Color = Color3.fromRGB(30, 20, 20) })
		task.delay(1.2, function()
			Common.fadeOut(scorch, 3, { Transparency = 1 })
		end)
		local camera = workspace.CurrentCamera
		local distance = (camera.CFrame.Position - target).Magnitude
		if distance < 60 then
			context.shake(2.5 * (1 - distance / 60) + 0.4, 0.35)
		end
	end)
end

return function(context)
	local _, ungrade = Common.colorGrade({ TintColor = Color3.fromRGB(255, 215, 195), Contrast = 0.12, Saturation = 0.15 })
	local restoreLight = Common.lighting({ ClockTime = 18.2, Brightness = 1.6 }, 3)
	local stopEmbers = Common.sheet({
		color = ColorSequence.new(HOT, FIRE),
		rate = 60,
		size = NumberSequence.new(0.18, 0),
		speed = NumberRange.new(4, 8),
		lifetime = NumberRange.new(6, 9),
		height = 45,
		lightEmission = 1,
		acceleration = Vector3.new(2, 0, 1),
	})
	context.on("Meteor", function(data)
		meteor(context, data)
	end)
	return function()
		ungrade()
		restoreLight()
		stopEmbers()
	end
end
