-- Thunderstorm: the sky goes dark, rain pours, and jagged lightning bolts with
-- forks crash down onto crackling warning circles, lighting up the world.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")

local Common = require(script.Parent.Common)
local Vfx = require(script.Parent.Parent.Vfx)

local BOLT = Color3.fromRGB(200, 230, 255)
local GLOW = Color3.fromRGB(120, 190, 255)

-- A zig-zag line of glowing segments from `from` to `to`
local function bolt(from: Vector3, to: Vector3, thickness: number, segments: number, jitter: number)
	local points = { from }
	for i = 1, segments - 1 do
		local t = i / segments
		local point = from:Lerp(to, t)
		local wobble = jitter * math.sin(t * math.pi)
		table.insert(points, point + Vector3.new((math.random() - 0.5) * wobble, 0, (math.random() - 0.5) * wobble))
	end
	table.insert(points, to)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		local segment = Common.part({
			Size = Vector3.new(thickness, thickness, length),
			CFrame = CFrame.lookAt((a + b) / 2, b),
			Color = BOLT,
		})
		Common.fadeOut(segment, 0.35, { Transparency = 1, Size = Vector3.new(thickness * 0.2, thickness * 0.2, length) })
	end
	return points
end

local function strike(context, data)
	local target: Vector3 = data.position
	local warning = math.max(0.1, data.impactAt - workspace:GetServerTimeNow())

	local ring = Common.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, context.def.radius * 2, context.def.radius * 2),
		CFrame = CFrame.new(target + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = GLOW,
		Transparency = 0.6,
	})
	Common.tween(ring, warning, { Transparency = 0.1 }, Enum.EasingStyle.Bounce)
	Debris:AddItem(ring, warning)

	task.delay(warning, function()
		if not context.running() then
			return
		end
		local sky = target + Vector3.new((math.random() - 0.5) * 30, 160, (math.random() - 0.5) * 30)
		local points = bolt(sky, target, 0.6, 12, 18)
		-- Forks branching off the main bolt
		for _ = 1, if Common.reduced() then 1 else 3 do
			local from = points[math.random(3, #points - 2)]
			local to = from + Vector3.new((math.random() - 0.5) * 40, -20 - math.random() * 25, (math.random() - 0.5) * 40)
			bolt(from, to, 0.3, 5, 8)
		end
		local light = Common.part({ Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(target + Vector3.new(0, 6, 0)) })
		local point = Instance.new("PointLight")
		point.Color = BOLT
		point.Range = 60
		point.Brightness = 10
		point.Parent = light
		Common.tween(point, 0.5, { Brightness = 0 })
		Debris:AddItem(light, 0.6)

		local flash = Instance.new("ColorCorrectionEffect")
		flash.Brightness = 0.45
		flash.Parent = Lighting
		Common.fadeOut(flash, 0.3, { Brightness = 0 })

		Vfx.shockwave(target, GLOW, 2, context.def.radius * 2, 0.35)
		Vfx.groundRing(target + Vector3.new(0, 0.1, 0), BOLT, 2, context.def.radius * 2.6, 0.5)
		Vfx.sparks(target + Vector3.new(0, 1, 0), BOLT, 35, 40)
		Vfx.sound("GuardBreak", target)
		local distance = (workspace.CurrentCamera.CFrame.Position - target).Magnitude
		context.shake(if distance < 50 then 2.2 else 0.6, 0.3)
	end)
end

return function(context)
	local _, ungrade = Common.colorGrade({ TintColor = Color3.fromRGB(190, 205, 235), Saturation = -0.45, Contrast = 0.15, Brightness = -0.12 })
	local restoreLight = Common.lighting({ ClockTime = 19.5, Brightness = 0.6 }, 3)
	local stopRain = Common.sheet({
		color = ColorSequence.new(Color3.fromRGB(180, 210, 255)),
		rate = 500,
		size = NumberSequence.new(0.08),
		speed = NumberRange.new(90, 110),
		lifetime = NumberRange.new(0.9, 1.2),
		height = 70,
		area = 140,
		transparency = NumberSequence.new(0.35),
		squash = NumberSequence.new(-2.5),
		orientation = Enum.ParticleOrientation.VelocityParallel,
		acceleration = Vector3.new(6, 0, 0),
	})
	context.on("Strike", function(data)
		strike(context, data)
	end)
	return function()
		ungrade()
		restoreLight()
		stopRain()
	end
end
