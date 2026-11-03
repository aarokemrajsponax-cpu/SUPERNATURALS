-- Draws the owner's event effects on this client. Each renderer takes the published record
-- (a Folder under ReplicatedStorage.OverlordFx, parameters as attributes) and returns a
-- cleanup function. Everything is local, capped, and removed when the record disappears.
-- Respects the "Reduced effects" setting (fewer particles, no firework debris).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Settings = require(script.Parent.Parent.Settings)

local Visuals = {}

local function reduced(): boolean
	return Settings.get("reducedEffects") == true
end

local function sheetFolder(): Folder
	local camera = workspace.CurrentCamera
	local folder = camera:FindFirstChild("SNOverlord")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SNOverlord"
		folder.Parent = camera
	end
	return folder
end

-- Runs setup(character, player) for every participant's character now and later; the cleanup
-- it returns runs when the character goes away or the effect stops
local function perCharacter(ownerOnly: boolean, setup: (Model, Player) -> (() -> ())?): () -> ()
	local cleanups: { [Model]: () -> () } = {}
	local connections = {}
	local stopped = false
	local function eligible(player: Player): boolean
		if player:GetAttribute("EventOptOut") == true then
			return false
		end
		return not ownerOnly or player:GetAttribute("SNIsOwner") == true
	end
	local function attach(player: Player, character: Model)
		if stopped or cleanups[character] or not eligible(player) then
			return
		end
		task.spawn(function()
			if not character:WaitForChild("HumanoidRootPart", 5) or stopped then
				return
			end
			local cleanup = setup(character, player)
			cleanups[character] = cleanup or function() end
		end)
	end
	local function watch(player: Player)
		table.insert(connections, player.CharacterAdded:Connect(function(character)
			attach(player, character)
		end))
		table.insert(connections, player.CharacterRemoving:Connect(function(character)
			local cleanup = cleanups[character]
			cleanups[character] = nil
			if cleanup then
				cleanup()
			end
		end))
		if player.Character then
			attach(player, player.Character)
		end
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(watch))
	return function()
		stopped = true
		for _, connection in connections do
			connection:Disconnect()
		end
		for _, cleanup in cleanups do
			cleanup()
		end
		table.clear(cleanups)
	end
end

local function emitter(parent: Instance, color: Color3, rate: number, props: { [string]: any }?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Rate = if reduced() then rate * 0.4 else rate
	e.LightEmission = 0.6
	e.Lifetime = NumberRange.new(1, 2)
	e.Speed = NumberRange.new(1, 3)
	e.Size = NumberSequence.new(0.3)
	e.Transparency = NumberSequence.new(0, 1)
	for key, value in props or {} do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

-- A part that rides above the camera, for sheets of weather or confetti
local function cameraSheet(height: number, size: number): (Part, () -> ())
	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
	part.Transparency = 1
	part.Size = Vector3.new(size, 1, size)
	part.Parent = sheetFolder()
	local connection = RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if camera then
			part.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, height, 0))
		end
	end)
	return part, function()
		connection:Disconnect()
		part:Destroy()
	end
end

local function colorOf(record: Instance, name: string?): Color3
	local value = record:GetAttribute(name or "color")
	return if typeof(value) == "Color3" then value else Color3.new(1, 1, 1)
end

local function attachmentOn(character: Model, offset: Vector3): Attachment
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local a = Instance.new("Attachment")
	a.Position = offset
	a.Parent = root
	return a
end

local R = {}

local WEATHER = {
	leaves = { speed = 4, accel = Vector3.new(0, -2, 0), spin = 90 },
	snow = { speed = 5, accel = Vector3.new(0, -1, 0), spin = 10 },
	rain = { speed = 60, accel = Vector3.new(0, -20, 0), spin = 0 },
	petals = { speed = 3, accel = Vector3.new(0, -1, 0), spin = 120 },
	sparkles = { speed = 2, accel = Vector3.new(0, 0.5, 0), spin = 0 },
	meteors = { speed = 90, accel = Vector3.new(0, -40, 0), spin = 0 },
	embers = { speed = 2, accel = Vector3.new(0, 3, 0), spin = 30 },
	ash = { speed = 3, accel = Vector3.new(0, -1, 0), spin = 20 },
	data = { speed = 8, accel = Vector3.new(0, -10, 0), spin = 0 },
	bubbles = { speed = 2, accel = Vector3.new(0, 2, 0), spin = 0 },
}
function R.Weather(record)
	local style = WEATHER[record:GetAttribute("kind")] or WEATHER.snow
	local part, cleanup = cameraSheet(40, 90)
	local wind = record:GetAttribute("wind") or 0
	local e = emitter(part, colorOf(record), record:GetAttribute("rate") or 30, {
		Size = NumberSequence.new(record:GetAttribute("size") or 0.4),
		Lifetime = NumberRange.new(4, 7),
		Speed = NumberRange.new(style.speed, style.speed * 1.5),
		EmissionDirection = Enum.NormalId.Bottom,
		Acceleration = style.accel + Vector3.new(wind, 0, 0),
		RotSpeed = NumberRange.new(-style.spin, style.spin),
		SpreadAngle = Vector2.new(30, 30),
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	e.Rate = (if reduced() then 0.4 else 1) * (record:GetAttribute("rate") or 30) * 4
	return cleanup
end

local AURA_RATE = { glow = 12, energy = 25, rings = 10, outline = 6, cosmic = 30, festive = 20, flame = 28, static = 18 }
function R.Aura(record)
	local style = record:GetAttribute("style") or "glow"
	local size = record:GetAttribute("size") or 1
	local color = colorOf(record)
	return perCharacter(record:GetAttribute("ownerOnly") == true, function(character)
		local a = attachmentOn(character, Vector3.zero)
		local e = emitter(a, color, AURA_RATE[style] or 12, {
			Size = NumberSequence.new(0.4 * size),
			Speed = NumberRange.new(if style == "flame" then 3 else 1, 3),
			SpreadAngle = Vector2.new(180, 180),
		})
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 8 * size
		light.Brightness = 1
		light.Parent = a
		local highlight
		if style == "outline" then
			highlight = Instance.new("Highlight")
			highlight.FillTransparency = 1
			highlight.OutlineColor = color
			highlight.Parent = character
		end
		return function()
			e:Destroy()
			light:Destroy()
			a:Destroy()
			if highlight then
				highlight:Destroy()
			end
		end
	end)
end

function R.Trail(record)
	local style = record:GetAttribute("style") or "energy"
	local length = record:GetAttribute("length") or 1
	local color = colorOf(record)
	return perCharacter(false, function(character)
		local a0 = attachmentOn(character, Vector3.new(0, 1, 0))
		local a1 = attachmentOn(character, Vector3.new(0, -1, 0))
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Color = ColorSequence.new(color)
		trail.Lifetime = 0.6 * length
		trail.LightEmission = if style == "pixels" then 0 else 0.7
		trail.Transparency = NumberSequence.new(0, 1)
		trail.Parent = a0
		local sparks = if style == "particles" or style == "footprints" or style == "pixels" then emitter(a1, color, 15) else nil
		return function()
			trail:Destroy()
			if sparks then
				sparks:Destroy()
			end
			a0:Destroy()
			a1:Destroy()
		end
	end)
end

function R.Halo(record)
	local color = colorOf(record)
	local style = record:GetAttribute("style") or "halo"
	return perCharacter(false, function(character)
		local head = character:FindFirstChild("Head")
		if not head then
			return nil
		end
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.2, 2.6, 2.6)
		ring.Material = Enum.Material.Neon
		ring.Color = color
		ring.Transparency = 0.2
		ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.Massless = false, false, false, true
		ring.Name = "SNHalo_" .. style
		local weld = Instance.new("Weld")
		weld.Part0 = head
		weld.Part1 = ring
		weld.C0 = CFrame.new(0, 1.8, 0) * CFrame.Angles(0, 0, math.rad(90))
		weld.Parent = ring
		ring.Parent = character
		local angle = 0
		local spin = RunService.Heartbeat:Connect(function(dt)
			angle += dt * (if style == "orbit_rings" then 3 else 1)
			weld.C0 = CFrame.new(0, 1.8, 0) * CFrame.Angles(0, angle, math.rad(90))
		end)
		return function()
			spin:Disconnect()
			ring:Destroy()
		end
	end)
end

function R.Title(record)
	local text = record:GetAttribute("text") or ""
	local color = colorOf(record)
	return perCharacter(false, function(character)
		local head = character:FindFirstChild("Head")
		if not head then
			return nil
		end
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(240, 28)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
		gui.AlwaysOnTop = false
		gui.Name = "SNOverlordTitle"
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.4
		label.Font = Enum.Font.GothamBold
		label.TextSize = 18
		label.Parent = gui
		gui.Parent = head
		return function()
			gui:Destroy()
		end
	end)
end

function R.Companion(record)
	local color = colorOf(record)
	return perCharacter(false, function(character)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
		local orb = Instance.new("Part")
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(1, 1, 1)
		orb.Material = Enum.Material.Neon
		orb.Color = color
		orb.Anchored, orb.CanCollide, orb.CanQuery, orb.CanTouch = true, false, false, false
		orb.Parent = sheetFolder()
		local t = 0
		local follow = RunService.RenderStepped:Connect(function(dt)
			t += dt
			orb.Position = root.Position + Vector3.new(math.cos(t * 1.5) * 3, 3 + math.sin(t * 3) * 0.4, math.sin(t * 1.5) * 3)
		end)
		return function()
			follow:Disconnect()
			orb:Destroy()
		end
	end)
end

function R.Confetti(record)
	local part, cleanup = cameraSheet(30, 70)
	local e = emitter(part, colorOf(record), (record:GetAttribute("rate") or 30) * 3, {
		Lifetime = NumberRange.new(4, 6),
		Speed = NumberRange.new(2, 6),
		EmissionDirection = Enum.NormalId.Bottom,
		Acceleration = Vector3.new(0, -4, 0),
		RotSpeed = NumberRange.new(-200, 200),
		SpreadAngle = Vector2.new(25, 25),
		Size = NumberSequence.new(0.5),
		Shape = Enum.ParticleEmitterShape.Box,
	})
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 120)),
		ColorSequenceKeypoint.new(0.5, colorOf(record)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 200, 255)),
	})
	return cleanup
end

function R.Fireworks(record)
	local interval = record:GetAttribute("interval") or 2
	local size = record:GetAttribute("size") or 1
	local color = colorOf(record)
	local alive = true
	task.spawn(function()
		while alive do
			local camera = workspace.CurrentCamera
			if camera then
				local origin = camera.CFrame.Position + Vector3.new(math.random(-60, 60), math.random(55, 85), math.random(-60, 60))
				local count = if reduced() then 8 else 22
				for i = 1, count do
					local ball = Instance.new("Part")
					ball.Shape = Enum.PartType.Ball
					ball.Size = Vector3.new(1.2, 1.2, 1.2) * size
					ball.Material = Enum.Material.Neon
					ball.Color = color:Lerp(Color3.fromHSV(math.random(), 0.6, 1), 0.4)
					ball.Anchored, ball.CanCollide, ball.CanQuery, ball.CanTouch = true, false, false, false
					ball.Position = origin
					ball.Parent = sheetFolder()
					local a = i / count * math.pi * 2
					local target = origin + Vector3.new(math.cos(a), math.sin(a * 2) * 0.6, math.sin(a)) * 22 * size
					TweenService:Create(ball, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target, Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2) }):Play()
					Debris:AddItem(ball, 1.6)
				end
			end
			task.wait(interval)
		end
	end)
	return function()
		alive = false
	end
end

function R.Arrival(record)
	local color = colorOf(record)
	local function burst(character)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		local pillar = Instance.new("Part")
		pillar.Size = Vector3.new(4, 60, 4)
		pillar.Material = Enum.Material.Neon
		pillar.Color = color
		pillar.Transparency = 0.3
		pillar.Anchored, pillar.CanCollide, pillar.CanQuery, pillar.CanTouch = true, false, false, false
		pillar.Position = root.Position + Vector3.new(0, 28, 0)
		pillar.Parent = sheetFolder()
		TweenService:Create(pillar, TweenInfo.new(1.2), { Transparency = 1, Size = Vector3.new(0.5, 60, 0.5) }):Play()
		Debris:AddItem(pillar, 1.4)
	end
	local stop = perCharacter(false, function(character)
		burst(character)
		return nil
	end)
	return stop
end

function R.Banner(record)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SNOverlordBanner"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 56)
	label.Size = UDim2.fromOffset(640, 44)
	label.BackgroundColor3 = Color3.fromRGB(10, 14, 24)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(255, 232, 170)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.Text = record:GetAttribute("text") or ""
	label.Parent = gui
	local localPlayer = Players.LocalPlayer
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	return function()
		gui:Destroy()
	end
end

-- Starts drawing `record`. Returns a cleanup, or nil when there is no renderer for it.
function Visuals.render(record: Instance): (() -> ())?
	local renderer = R[record:GetAttribute("Effect")]
	if not renderer then
		return nil
	end
	local ok, result = pcall(renderer, record)
	if not ok then
		warn("[Overlord] could not draw " .. tostring(record:GetAttribute("Effect")) .. ": " .. tostring(result))
		return nil
	end
	return result
end

Visuals.Renderers = R

return Visuals
