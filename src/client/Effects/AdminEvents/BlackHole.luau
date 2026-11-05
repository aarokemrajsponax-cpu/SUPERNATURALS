-- Black Hole: a void sphere wrapped in spinning accretion rings, with light
-- streaming into it from every direction, until it collapses and detonates in
-- a blinding white shockwave.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Common = require(script.Parent.Common)
local Vfx = require(script.Parent.Parent.Vfx)

local PURPLE = Color3.fromRGB(150, 70, 255)
local ORANGE = Color3.fromRGB(255, 140, 60)
local PINK = Color3.fromRGB(255, 80, 190)

return function(context)
	local core = context.center + Vector3.new(0, 24, 0)
	local parts: { BasePart } = {}
	local function add(part: BasePart): BasePart
		table.insert(parts, part)
		return part
	end

	local _, ungrade = Common.colorGrade({ TintColor = Color3.fromRGB(225, 205, 255), Contrast = 0.25, Saturation = -0.25, Brightness = -0.05 })
	local restoreLight = Common.lighting({ ClockTime = 21, Brightness = 1 }, 3)

	local void = add(Common.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.5,
		CFrame = CFrame.new(core),
		Color = Color3.new(0, 0, 0),
		Material = Enum.Material.SmoothPlastic,
	}))
	Common.tween(void, 2, { Size = Vector3.one * 11 }, Enum.EasingStyle.Back)
	local horizon = add(Common.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1,
		CFrame = CFrame.new(core),
		Color = PURPLE,
		Material = Enum.Material.ForceField,
	}))
	Common.tween(horizon, 2, { Size = Vector3.one * 15 }, Enum.EasingStyle.Back)

	-- Glowing accretion disks, each tilted and spinning at its own speed
	local rings = {
		{ diameter = 26, color = ORANGE, tilt = 12, speed = 1.6 },
		{ diameter = 36, color = PINK, tilt = -8, speed = -1.1 },
		{ diameter = 48, color = PURPLE, tilt = 18, speed = 0.7 },
	}
	local ringParts = {}
	for _, ring in rings do
		local part = add(Common.part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, 1, 1),
			CFrame = CFrame.new(core),
			Color = ring.color,
			Transparency = 0.35,
		}))
		Common.tween(part, 2.5, { Size = Vector3.new(0.2, ring.diameter, ring.diameter) }, Enum.EasingStyle.Back)
		table.insert(ringParts, { part = part, spec = ring })
	end
	-- Light pouring inward from a huge invisible sphere
	local intake = add(Common.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 110, CFrame = CFrame.new(core), Transparency = 1 }))
	local stream = Instance.new("ParticleEmitter")
	stream.Shape = Enum.ParticleEmitterShape.Sphere
	stream.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	stream.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	stream.Color = ColorSequence.new(Color3.new(1, 1, 1), PURPLE)
	stream.LightEmission = 1
	stream.LightInfluence = 0
	stream.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.05) })
	stream.Transparency = NumberSequence.new(0.2, 0.8)
	stream.Speed = NumberRange.new(28, 40)
	stream.Lifetime = NumberRange.new(1.3, 1.9)
	stream.Rate = if Common.reduced() then 80 else 260
	stream.Parent = intake

	local light = Instance.new("PointLight")
	light.Color = PURPLE
	light.Range = 60
	light.Brightness = 3
	light.Parent = horizon

	local spin = 0
	local connection = RunService.RenderStepped:Connect(function(dt)
		spin += dt
		for _, entry in ringParts do
			local spec = entry.spec
			entry.part.CFrame = CFrame.new(core)
				* CFrame.Angles(math.rad(spec.tilt), spin * spec.speed, 0)
				* CFrame.Angles(0, 0, math.rad(90))
		end
		horizon.Transparency = 0.15 + math.sin(spin * 6) * 0.1
	end)

	local finished = false
	local function teardown()
		if finished then
			return
		end
		finished = true
		connection:Disconnect()
		stream.Enabled = false
		for _, part in parts do
			Common.fadeOut(part, 0.4, { Transparency = 1 })
		end
		Debris:AddItem(intake, 2)
	end

	context.on("BlackHoleBlast", function()
		-- Collapse, then detonate
		Common.tween(void, 0.3, { Size = Vector3.one * 0.5 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		Common.tween(horizon, 0.3, { Size = Vector3.one * 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.3, function()
			teardown()
			local flash = Instance.new("ColorCorrectionEffect")
			flash.Brightness = 0.7
			flash.Contrast = 0.4
			flash.Parent = game:GetService("Lighting")
			Common.fadeOut(flash, 0.9, { Brightness = 0, Contrast = 0 })
			Vfx.shockwave(core, Color3.new(1, 1, 1), 4, 170, 0.9)
			Vfx.shockwave(core, PURPLE, 2, 120, 1.1)
			Vfx.groundRing(context.center + Vector3.new(0, 0.2, 0), PINK, 4, 200, 1.2)
			Vfx.sparks(core, Color3.new(1, 1, 1), 120, 80)
			Vfx.sound("GuardBreak", core)
			context.shake(4, 0.8)
		end)
	end)

	return function()
		teardown()
		ungrade()
		restoreLight()
	end
end
