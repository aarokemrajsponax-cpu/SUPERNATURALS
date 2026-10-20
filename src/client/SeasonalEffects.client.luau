-- Seasonal Sync (player side): weather, floating sprites, fireworks, animated
-- decorations and a welcome banner for whichever holiday the server switched on.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Seasons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Seasons"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local rng = Random.new()
local Tags = Seasons.Tags

local function keypoints(points: { { number } }): NumberSequence
	local list = {}
	for _, point in points do
		table.insert(list, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(list)
end

-- Invisible, client-only part for effects to live in
local function effectPart(size: Vector3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	return part
end

-- Weather: snow, glitter, embers... from a big sheet of particles that follows the camera
local function startWeather(weather)
	local sheet = effectPart(Vector3.new(90, 1, 90))
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(weather.color, weather.color2 or weather.color)
	emitter.LightEmission = weather.lightEmission or 0
	emitter.Size = keypoints({ { 0, weather.size }, { 1, weather.size * 0.6 } })
	emitter.Transparency = keypoints({ { 0, 1 }, { 0.12, 0.1 }, { 0.85, 0.2 }, { 1, 1 } })
	emitter.Rate = weather.rate
	local lifetime = weather.lifetime or 8
	emitter.Lifetime = NumberRange.new(lifetime, lifetime * 1.4)
	emitter.Speed = NumberRange.new(weather.speed * 0.7, weather.speed * 1.3)
	emitter.SpreadAngle = Vector2.new(15, 15)
	emitter.EmissionDirection = if weather.rise then Enum.NormalId.Top else Enum.NormalId.Bottom
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.Acceleration = Vector3.new(0.5, 0, 0.3)
	emitter.Parent = sheet
	sheet.Parent = camera

	local height = if weather.rise then -6 else 35
	local connection = RunService.RenderStepped:Connect(function()
		sheet.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, height, 0))
	end)
	return function()
		connection:Disconnect()
		sheet:Destroy()
	end
end

-- Sprites: emoji that drift around the player (leaves, hearts, bats...)
local SPRITE_AREA = 45

local function startSprites(sprites)
	local folder = Instance.new("Folder")
	folder.Name = "SeasonalSprites"
	folder.Parent = camera

	local items = {}
	local function respawn(item, anywhere: boolean)
		local origin = camera.CFrame.Position
		local y
		if anywhere then
			y = origin.Y + rng:NextNumber(-8, 30)
		elseif sprites.fall > 0 then
			y = origin.Y + rng:NextNumber(25, 35)
		elseif sprites.fall < 0 then
			y = origin.Y - rng:NextNumber(8, 12)
		else
			y = origin.Y + rng:NextNumber(5, 25)
		end
		item.position = Vector3.new(
			origin.X + rng:NextNumber(-SPRITE_AREA, SPRITE_AREA),
			y,
			origin.Z + rng:NextNumber(-SPRITE_AREA, SPRITE_AREA)
		)
		local heading = rng:NextNumber(0, math.pi * 2)
		item.drift = Vector3.new(math.cos(heading), 0, math.sin(heading)) * sprites.drift * rng:NextNumber(0.6, 1.2)
		item.phase = rng:NextNumber(0, math.pi * 2)
		item.spinSpeed = rng:NextNumber(-90, 90)
	end

	for _ = 1, sprites.count do
		local anchor = effectPart(Vector3.new(0.1, 0.1, 0.1))
		local gui = Instance.new("BillboardGui")
		local size = sprites.size * rng:NextNumber(0.8, 1.2)
		gui.Size = UDim2.fromScale(size, size)
		gui.LightInfluence = 0
		gui.MaxDistance = 120
		gui.Adornee = anchor
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.Text = sprites.glyphs[rng:NextInteger(1, #sprites.glyphs)]
		label.Parent = gui
		gui.Parent = anchor
		anchor.Parent = folder

		local item = { part = anchor, label = label }
		respawn(item, true)
		table.insert(items, item)
	end

	local connection = RunService.Heartbeat:Connect(function(dt)
		local origin = camera.CFrame.Position
		local t = os.clock()
		for _, item in items do
			item.position += (Vector3.new(0, -sprites.fall, 0) + item.drift) * dt
			local sway = Vector3.new(math.sin(t * 0.8 + item.phase), 0, math.cos(t * 0.6 + item.phase) * 0.5) * sprites.sway
			item.part.CFrame = CFrame.new(item.position + sway)
			if sprites.spin then
				item.label.Rotation = (t * item.spinSpeed) % 360
			end
			local offset = item.position - origin
			if offset.Y < -15 or offset.Y > 40 or math.abs(offset.X) > SPRITE_AREA + 5 or math.abs(offset.Z) > SPRITE_AREA + 5 then
				respawn(item, false)
			end
		end
	end)
	return function()
		connection:Disconnect()
		folder:Destroy()
	end
end

-- Fireworks launched around the spawn area
local FIREWORK_COLORS = {
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(255, 210, 80),
	Color3.fromRGB(80, 200, 255),
	Color3.fromRGB(170, 100, 255),
	Color3.fromRGB(120, 255, 140),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 120, 200),
}

local function launchFirework(folder: Instance)
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(25, 70)
	local start = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	local burstAt = start + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(45, 75), rng:NextNumber(-6, 6))
	local color = FIREWORK_COLORS[rng:NextInteger(1, #FIREWORK_COLORS)]
	local fade = FIREWORK_COLORS[rng:NextInteger(1, #FIREWORK_COLORS)]

	local rocket = effectPart(Vector3.new(0.4, 0.4, 0.4))
	rocket.Shape = Enum.PartType.Ball
	rocket.Transparency = 0
	rocket.Material = Enum.Material.Neon
	rocket.Color = color
	rocket.CFrame = CFrame.new(start)
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 0.2, 0)
	top.Parent = rocket
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -0.2, 0)
	bottom.Parent = rocket
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.5
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 1
	trail.Transparency = NumberSequence.new(0, 1)
	trail.Parent = rocket
	rocket.Parent = folder

	local flight = TweenService:Create(rocket, TweenInfo.new(rng:NextNumber(1.1, 1.6), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(burstAt),
	})
	flight.Completed:Once(function()
		rocket.Transparency = 1
		local burst = Instance.new("ParticleEmitter")
		burst.Color = ColorSequence.new(color, fade)
		burst.LightEmission = 1
		burst.LightInfluence = 0
		burst.Size = keypoints({ { 0, 0.8 }, { 1, 0 } })
		burst.Transparency = keypoints({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } })
		burst.Lifetime = NumberRange.new(1.2, 2)
		burst.Speed = NumberRange.new(28, 38)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Drag = 2.5
		burst.Acceleration = Vector3.new(0, -10, 0)
		burst.Rate = 0
		burst.Parent = rocket
		burst:Emit(140)

		local flash = Instance.new("PointLight")
		flash.Color = color
		flash.Range = 60
		flash.Brightness = 6
		flash.Parent = rocket
		TweenService:Create(flash, TweenInfo.new(1.2), { Brightness = 0 }):Play()
		task.delay(3, function()
			rocket:Destroy()
		end)
	end)
	flight:Play()
end

local function startFireworks()
	local running = true
	local folder = Instance.new("Folder")
	folder.Name = "Fireworks"
	folder.Parent = camera
	task.spawn(function()
		while running do
			-- Now and then, a big volley
			local count = if rng:NextNumber() < 0.15 then 4 else 1
			for _ = 1, count do
				launchFirework(folder)
			end
			task.wait(rng:NextNumber(0.6, 1.8))
		end
	end)
	return function()
		running = false
		folder:Destroy()
	end
end

-- Animates decorations the server tagged: floating, spinning, flickering, twinkling
local function startDecorAnimations()
	local bases = setmetatable({}, { __mode = "k" })
	local phases = setmetatable({}, { __mode = "k" })
	local function remember(instance, value)
		if bases[instance] == nil then
			bases[instance] = value
			phases[instance] = rng:NextNumber(0, math.pi * 2)
		end
		return bases[instance], phases[instance]
	end

	local connection = RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for _, instance in CollectionService:GetTagged(Tags.Bob) do
			if instance:IsA("PVInstance") then
				local base, phase = remember(instance, instance:GetPivot())
				instance:PivotTo(base + Vector3.new(0, math.sin(t * 1.4 + phase) * 0.6, 0))
			end
		end
		for _, instance in CollectionService:GetTagged(Tags.Spin) do
			if instance:IsA("PVInstance") then
				local base, phase = remember(instance, instance:GetPivot())
				instance:PivotTo(CFrame.new(base.Position) * CFrame.Angles(0, t * 0.7 + phase, 0) * base.Rotation)
			end
		end
		for _, light in CollectionService:GetTagged(Tags.Flicker) do
			if light:IsA("Light") then
				local base, phase = remember(light, light.Brightness)
				light.Brightness = base * (0.85 + 0.5 * math.noise(t * 4, phase))
			end
		end
		for _, part in CollectionService:GetTagged(Tags.Twinkle) do
			if part:IsA("BasePart") then
				local _, phase = remember(part, part.Transparency)
				part.Transparency = 0.7 * math.max(0, math.sin(t * 1.7 + phase * 3)) ^ 6
			end
		end
	end)
	return function()
		connection:Disconnect()
	end
end

-- A banner that slides in to welcome the player to the holiday
local function showBanner(theme)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SeasonalBanner"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, -160)
	frame.Size = UDim2.new(0.9, 0, 0, 104)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.Parent = gui

	local maxSize = Instance.new("UISizeConstraint")
	maxSize.MaxSize = Vector2.new(480, 104)
	maxSize.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 20)
	corner.Parent = frame
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(theme.palette.primary, theme.palette.secondary)
	gradient.Rotation = 20
	gradient.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = theme.palette.accent
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(14, 14)
	icon.Size = UDim2.fromOffset(76, 76)
	icon.Text = theme.icon
	icon.TextScaled = true
	icon.Parent = frame

	local function text(content: string, y: number, height: number, font: Enum.Font)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.new(0, 100, 0, y)
		label.Size = UDim2.new(1, -116, 0, height)
		label.Text = content
		label.Font = font
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.new(1, 1, 1)
		local outline = Instance.new("UIStroke")
		outline.Color = Color3.new(0, 0, 0)
		outline.Transparency = 0.6
		outline.Thickness = 2
		outline.Parent = label
		label.Parent = frame
	end
	text(theme.greeting, 16, 44, Enum.Font.FredokaOne)
	text(theme.subtitle, 62, 26, Enum.Font.GothamMedium)

	gui.Parent = player:WaitForChild("PlayerGui")

	local slideIn = TweenService:Create(frame, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 16),
	})
	slideIn:Play()
	task.delay(7, function()
		local slideOut = TweenService:Create(frame, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -160),
		})
		slideOut.Completed:Once(function()
			gui:Destroy()
		end)
		slideOut:Play()
	end)
	return function()
		gui:Destroy()
	end
end

-- Switch effects whenever the server changes season
local stopFunctions = {}

local function stopAll()
	for _, stop in stopFunctions do
		stop()
	end
	table.clear(stopFunctions)
end

Seasons.observe(function(_, theme)
	stopAll()
	table.insert(stopFunctions, startDecorAnimations())
	if not theme then
		return
	end
	if theme.weather then
		table.insert(stopFunctions, startWeather(theme.weather))
	end
	if theme.sprites then
		table.insert(stopFunctions, startSprites(theme.sprites))
	end
	if theme.fireworks then
		table.insert(stopFunctions, startFireworks())
	end
	table.insert(stopFunctions, showBanner(theme))
end)
