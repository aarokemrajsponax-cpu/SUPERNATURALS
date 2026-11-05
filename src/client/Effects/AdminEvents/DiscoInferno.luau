-- Disco Inferno: a giant mirror ball drops over spawn, covered in flickering
-- tiles, sweeping laser beams in every colour, a light-up dance floor that
-- changes with the beat, and the whole world pulsing through the rainbow.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Common = require(script.Parent.Common)

local BEAT = 0.45
local FLOOR_TILES = 12
local TILE = 6

return function(context)
	local center = context.center
	local ballCenter = center + Vector3.new(0, 32, 0)
	local parts: { BasePart } = {}
	local function add(part: BasePart): BasePart
		table.insert(parts, part)
		return part
	end

	local restoreLight = Common.lighting({ ClockTime = 22, Brightness = 0.7 }, 2)
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "SNDisco"
	grade.Saturation = 0.5
	grade.Contrast = 0.15
	grade.Parent = Lighting

	-- The mirror ball, lowered from the sky on a cable
	local ballRadius = 6
	local ball = add(Common.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * ballRadius * 2,
		CFrame = CFrame.new(ballCenter + Vector3.new(0, 60, 0)),
		Color = Color3.fromRGB(210, 215, 225),
		Material = Enum.Material.Foil,
		Reflectance = 0.6,
	}))
	local cable = add(Common.part({
		Size = Vector3.new(0.2, 60, 0.2),
		CFrame = CFrame.new(ballCenter + Vector3.new(0, 90, 0)),
		Color = Color3.fromRGB(40, 40, 45),
		Material = Enum.Material.Metal,
	}))
	Common.tween(ball, 3, { CFrame = CFrame.new(ballCenter) }, Enum.EasingStyle.Bounce)
	Common.tween(cable, 3, { CFrame = CFrame.new(ballCenter + Vector3.new(0, 30 + ballRadius, 0)) }, Enum.EasingStyle.Bounce)

	-- Tiles on the ball (golden-spiral spread so they cover it evenly)
	local tiles = {}
	local tileCount = if Common.reduced() then 40 else 90
	local golden = math.pi * (3 - math.sqrt(5))
	for i = 0, tileCount - 1 do
		local y = 1 - (i / (tileCount - 1)) * 2
		local radius = math.sqrt(1 - y * y)
		local theta = golden * i
		local normal = Vector3.new(math.cos(theta) * radius, y, math.sin(theta) * radius)
		local tile = add(Common.part({
			Size = Vector3.new(1.1, 1.1, 0.15),
			Color = Common.Rainbow[i % #Common.Rainbow + 1],
			Transparency = 0.1,
		}))
		table.insert(tiles, { part = tile, normal = normal, phase = math.random() * 10 })
	end

	-- Lasers from the ball out across the lobby
	local lasers = {}
	local laserCount = if Common.reduced() then 4 else 8
	for i = 1, laserCount do
		local anchor = add(Common.part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(ballCenter) }))
		local from = Instance.new("Attachment")
		from.Parent = anchor
		local to = Instance.new("Attachment")
		to.Parent = anchor
		local beam = Instance.new("Beam")
		beam.Attachment0 = from
		beam.Attachment1 = to
		beam.Width0 = 0.4
		beam.Width1 = 1.6
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Transparency = NumberSequence.new(0.1, 0.6)
		beam.Parent = anchor
		table.insert(lasers, { from = from, to = to, beam = beam, offset = i / laserCount * math.pi * 2, tilt = 0.5 + (i % 3) * 0.25 })
	end

	-- The dance floor
	local floorTiles = {}
	local half = FLOOR_TILES * TILE / 2
	local floorY = Common.ground(center).Y + 0.06
	for x = 0, FLOOR_TILES - 1 do
		for z = 0, FLOOR_TILES - 1 do
			local tile = add(Common.part({
				Size = Vector3.new(TILE - 0.3, 0.1, TILE - 0.3),
				CFrame = CFrame.new(center.X - half + (x + 0.5) * TILE, floorY, center.Z - half + (z + 0.5) * TILE),
				Color = Color3.new(0, 0, 0),
				Transparency = 0.35,
			}))
			table.insert(floorTiles, tile)
		end
	end

	local glow = Instance.new("PointLight")
	glow.Range = 60
	glow.Brightness = 3
	glow.Parent = ball

	local time = 0
	local nextBeat = 0
	local connection = RunService.RenderStepped:Connect(function(dt)
		time += dt
		local spin = CFrame.Angles(0, time * 0.8, 0)
		local ballFrame = CFrame.new(ball.Position) * spin
		for _, tile in tiles do
			local outward = ballFrame:VectorToWorldSpace(tile.normal)
			local position = ball.Position + outward * (ballRadius + 0.05)
			tile.part.CFrame = CFrame.lookAt(position, position + outward)
			tile.part.Transparency = 0.05 + 0.5 * (0.5 + 0.5 * math.sin(time * 9 + tile.phase))
		end
		for index, laser in lasers do
			local angle = laser.offset + time * (if index % 2 == 0 then 0.9 else -0.7)
			local reach = Vector3.new(math.cos(angle) * 70, -32 + math.sin(time * 1.3 + index) * 10 * laser.tilt, math.sin(angle) * 70)
			laser.from.WorldPosition = ball.Position
			laser.to.WorldPosition = ball.Position + reach
			laser.beam.Color = ColorSequence.new(Common.hue(index / #lasers))
		end
		glow.Color = Common.hue(0)
		grade.TintColor = Color3.new(1, 1, 1):Lerp(Common.hue(0.5), 0.25)
		if time >= nextBeat then
			nextBeat = time + BEAT
			for _, tile in floorTiles do
				tile.Color = if math.random() < 0.55 then Common.Rainbow[math.random(1, #Common.Rainbow)] else Color3.fromRGB(20, 20, 30)
			end
		end
	end)

	return function()
		connection:Disconnect()
		restoreLight()
		Common.tween(grade, 1.5, { Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) })
		Debris:AddItem(grade, 1.6)
		for _, laser in lasers do
			laser.beam.Enabled = false
		end
		Common.tween(ball, 2, { CFrame = CFrame.new(ball.Position + Vector3.new(0, 80, 0)) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, part in parts do
			if part ~= ball then
				Common.fadeOut(part, 1, { Transparency = 1 })
			end
		end
		Debris:AddItem(ball, 2.1)
	end
end
