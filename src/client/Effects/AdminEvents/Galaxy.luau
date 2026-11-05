-- Galaxy Sky: night falls, a field of twinkling stars fills the sky, three
-- rippling auroras wave overhead, planets drift past and shooting stars streak by.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Common = require(script.Parent.Common)

local AURORAS = {
	{ Color3.fromRGB(80, 255, 200), Color3.fromRGB(80, 150, 255), Color3.fromRGB(200, 90, 255) },
	{ Color3.fromRGB(255, 90, 200), Color3.fromRGB(160, 90, 255), Color3.fromRGB(80, 200, 255) },
	{ Color3.fromRGB(120, 255, 140), Color3.fromRGB(60, 220, 255), Color3.fromRGB(120, 120, 255) },
}

local PLANETS = {
	{ size = 70, color = Color3.fromRGB(230, 140, 90), ring = true, distance = 620, height = 260, speed = 0.02, phase = 0 },
	{ size = 110, color = Color3.fromRGB(90, 130, 230), ring = false, distance = 820, height = 340, speed = -0.012, phase = 2.2 },
	{ size = 40, color = Color3.fromRGB(200, 200, 215), ring = false, distance = 520, height = 200, speed = 0.03, phase = 4.1 },
}

local function auroraColors(colors: { Color3 }): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors[1]),
		ColorSequenceKeypoint.new(0.5, colors[2]),
		ColorSequenceKeypoint.new(1, colors[3]),
	})
end

return function(context)
	local center = context.center
	local restoreLight = Common.lighting({ ClockTime = 0.2, Brightness = 0.8, OutdoorAmbient = Color3.fromRGB(80, 70, 140) }, 3)
	local _, ungrade = Common.colorGrade({ TintColor = Color3.fromRGB(215, 205, 255), Saturation = 0.35, Contrast = 0.1 })

	local stopStars = Common.sheet({
		color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 200, 255)),
		rate = 90,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		speed = NumberRange.new(0.3, 1),
		lifetime = NumberRange.new(5, 9),
		height = 120,
		area = 500,
		lightEmission = 1,
		direction = Enum.NormalId.Top,
	})

	local parts: { BasePart } = {}
	local function add(part: BasePart): BasePart
		table.insert(parts, part)
		return part
	end

	-- Auroras: wide glowing beams that ripple
	local auroras = {}
	for index, colors in AURORAS do
		local anchor = add(Common.part({ Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(center) }))
		local a0 = Instance.new("Attachment")
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.Parent = anchor
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = auroraColors(colors)
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.55),
			NumberSequenceKeypoint.new(0.8, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Width0 = 70
		beam.Width1 = 70
		beam.Segments = 40
		beam.FaceCamera = false
		beam.Parent = anchor
		table.insert(auroras, { a0 = a0, a1 = a1, beam = beam, offset = index * 2.1, height = 150 + index * 25 })
	end

	-- Planets drifting in a slow orbit around the lobby
	local planets = {}
	for _, spec in PLANETS do
		local body = add(Common.part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * spec.size,
			Color = spec.color,
			Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.new(center + Vector3.new(spec.distance, spec.height, 0)),
		}))
		local glow = add(Common.part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * spec.size * 1.12,
			Color = spec.color,
			Material = Enum.Material.ForceField,
			CFrame = body.CFrame,
		}))
		local ring = nil
		if spec.ring then
			ring = add(Common.part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.5, spec.size * 2.1, spec.size * 2.1),
				Color = Color3.fromRGB(240, 210, 160),
				Transparency = 0.45,
				CFrame = body.CFrame,
			}))
		end
		table.insert(planets, { spec = spec, body = body, glow = glow, ring = ring })
	end

	local time = 0
	local nextShootingStar = 1
	local connection = RunService.RenderStepped:Connect(function(dt)
		time += dt
		for _, aurora in auroras do
			local wave = time * 0.4 + aurora.offset
			aurora.a0.WorldPosition = center + Vector3.new(-260, aurora.height + math.sin(wave) * 12, -120 + aurora.offset * 40)
			aurora.a1.WorldPosition = center + Vector3.new(260, aurora.height + math.cos(wave) * 12, -60 + aurora.offset * 30)
			aurora.beam.CurveSize0 = 120 * math.sin(wave * 1.3)
			aurora.beam.CurveSize1 = -120 * math.cos(wave * 0.9)
		end
		for _, planet in planets do
			local spec = planet.spec
			local angle = spec.phase + time * spec.speed
			local position = center + Vector3.new(math.cos(angle) * spec.distance, spec.height, math.sin(angle) * spec.distance)
			planet.body.CFrame = CFrame.new(position) * CFrame.Angles(0, time * 0.05, 0)
			planet.glow.CFrame = planet.body.CFrame
			if planet.ring then
				planet.ring.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(70), 0, math.rad(20))
			end
		end
		if time >= nextShootingStar then
			nextShootingStar = time + 0.8 + math.random() * 1.5
			local camera = workspace.CurrentCamera.CFrame.Position
			local from = camera + Vector3.new((math.random() - 0.5) * 300, 140 + math.random() * 60, (math.random() - 0.5) * 300)
			local heading = Vector3.new(math.random() - 0.5, -0.25, math.random() - 0.5).Unit
			local star = Common.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.2, CFrame = CFrame.new(from), Color = Color3.new(1, 1, 1) })
			local top = Instance.new("Attachment")
			top.Position = Vector3.new(0, 0.5, 0)
			top.Parent = star
			local bottom = Instance.new("Attachment")
			bottom.Position = Vector3.new(0, -0.5, 0)
			bottom.Parent = star
			local trail = Instance.new("Trail")
			trail.Attachment0 = top
			trail.Attachment1 = bottom
			trail.Lifetime = 0.6
			trail.LightEmission = 1
			trail.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 180, 255))
			trail.Transparency = NumberSequence.new(0, 1)
			trail.WidthScale = NumberSequence.new(1, 0)
			trail.FaceCamera = true
			trail.Parent = star
			Common.tween(star, 1, { CFrame = CFrame.new(from + heading * 220) }, Enum.EasingStyle.Linear)
			Debris:AddItem(star, 1.7)
		end
	end)

	return function()
		connection:Disconnect()
		restoreLight()
		ungrade()
		stopStars()
		for _, part in parts do
			Common.fadeOut(part, 1.5, { Transparency = 1 })
		end
		for _, aurora in auroras do
			Common.tween(aurora.beam, 1.5, { Width0 = 0, Width1 = 0 })
		end
	end
end
