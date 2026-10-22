-- Shared tools for drawing admin events on this client: temporary lighting
-- changes that undo themselves, particle sheets that follow the camera,
-- confetti, fireworks and ground lookups. Everything is local and cleaned up.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Settings = require(script.Parent.Parent.Parent.Settings)

local Common = {}

function Common.reduced(): boolean
	return Settings.get("reducedEffects") == true
end

local folder: Folder? = nil
function Common.folder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "SNAdminEvent"
	newFolder.Parent = workspace.CurrentCamera
	folder = newFolder
	return newFolder
end

-- Loose pieces (rock chunks, ice shards) have to live in the workspace: parts
-- under the camera are drawn but never simulated, so they'd hang in the air.
-- Parts this client creates stay on this client.
local looseFolder: Folder? = nil
local function loose(): Folder
	if looseFolder and looseFolder.Parent then
		return looseFolder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "SNLocalDebris"
	newFolder.Parent = workspace
	looseFolder = newFolder
	return newFolder
end

function Common.part(props: { [string]: any }): BasePart
	local part = Instance.new(props.ClassName or "Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "ClassName" and key ~= "Size" and key ~= "CFrame" and key ~= "Parent" then
			(part :: any)[key] = value
		end
	end
	part.Size = props.Size or Vector3.one
	part.CFrame = props.CFrame or CFrame.new()
	part.Parent = props.Parent or if props.Anchored == false then loose() else Common.folder()
	return part
end

function Common.tween(instance: Instance, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(instance, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	tween:Play()
	return tween
end

function Common.fadeOut(instance: Instance, duration: number, goal: { [string]: any })
	Common.tween(instance, duration, goal)
	Debris:AddItem(instance, duration + 0.05)
end

-- Temporarily changes Lighting properties on this client; the returned
-- function eases them back. The server keeps the lighting the game should have
-- right now (season, owner's time of day) in "SNBase_" attributes, so the
-- event goes back to that even if it changed while the event was running.
local BASE_PREFIX = "SNBase_"

function Common.lighting(goal: { [string]: any }, duration: number?): () -> ()
	local original = {}
	for key in goal do
		original[key] = (Lighting :: any)[key]
	end
	Common.tween(Lighting, duration or 2, goal)
	return function()
		local restore = {}
		for key, value in original do
			local current = Lighting:GetAttribute(BASE_PREFIX .. key)
			restore[key] = if typeof(current) == typeof(value) then current else value
		end
		Common.tween(Lighting, 2, restore)
	end
end

-- A local colour grade for the event; returns the effect and a remover
function Common.colorGrade(props: { [string]: any }, duration: number?): (ColorCorrectionEffect, () -> ())
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "SNAdminGrade"
	effect.Parent = Lighting
	Common.tween(effect, duration or 1.5, props)
	return effect, function()
		Common.tween(effect, 1.5, { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0, Brightness = 0 })
		Debris:AddItem(effect, 1.6)
	end
end

export type Sheet = {
	color: ColorSequence,
	rate: number,
	size: NumberSequence,
	speed: NumberRange,
	lifetime: NumberRange,
	height: number,
	area: number?,
	direction: Enum.NormalId?,
	lightEmission: number?,
	transparency: NumberSequence?,
	acceleration: Vector3?,
	squash: NumberSequence?,
	orientation: Enum.ParticleOrientation?,
	spread: Vector2?,
	rotSpeed: NumberRange?,
}

-- A big flat particle sheet that hovers above (or below) the camera: rain, snow, stars, embers
function Common.sheet(config: Sheet): () -> ()
	local area = config.area or 120
	local sheet = Common.part({ Transparency = 1, Size = Vector3.new(area, 1, area) })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = config.color
	emitter.Rate = if Common.reduced() then config.rate * 0.35 else config.rate
	emitter.Size = config.size
	emitter.Speed = config.speed
	emitter.Lifetime = config.lifetime
	emitter.EmissionDirection = config.direction or Enum.NormalId.Bottom
	emitter.LightEmission = config.lightEmission or 0
	emitter.LightInfluence = if (config.lightEmission or 0) > 0.5 then 0 else 1
	emitter.Transparency = config.transparency or NumberSequence.new(0.1)
	emitter.Acceleration = config.acceleration or Vector3.zero
	emitter.SpreadAngle = config.spread or Vector2.new(8, 8)
	emitter.RotSpeed = config.rotSpeed or NumberRange.new(0)
	emitter.Rotation = NumberRange.new(0, 360)
	if config.squash then
		emitter.Squash = config.squash
	end
	if config.orientation then
		emitter.Orientation = config.orientation
	end
	emitter.Parent = sheet
	local connection = RunService.RenderStepped:Connect(function()
		sheet.CFrame = CFrame.new(workspace.CurrentCamera.CFrame.Position + Vector3.new(0, config.height, 0))
	end)
	return function()
		connection:Disconnect()
		emitter.Enabled = false
		Debris:AddItem(sheet, 4)
	end
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

function Common.ground(position: Vector3): Vector3
	local ignore: { Instance } = { Common.folder() }
	for _, player in game:GetService("Players"):GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	groundParams.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(position + Vector3.new(0, 100, 0), Vector3.new(0, -300, 0), groundParams)
	return if result then result.Position else position
end

-- Confetti: bright paper bits that flutter down, animated in one loop -------------

local RAINBOW = {
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(255, 170, 60),
	Color3.fromRGB(255, 230, 70),
	Color3.fromRGB(90, 230, 120),
	Color3.fromRGB(70, 180, 255),
	Color3.fromRGB(170, 100, 255),
	Color3.fromRGB(255, 110, 200),
}
Common.Rainbow = RAINBOW

type Bit = { part: BasePart, velocity: Vector3, spin: Vector3, rotation: CFrame, dieAt: number }
local bits: { Bit } = {}
local MAX_BITS = 350
local confettiLoop: RBXScriptConnection? = nil

function Common.confetti(position: Vector3, count: number, colors: { Color3 }?)
	local palette = colors or RAINBOW
	count = if Common.reduced() then math.ceil(count / 3) else count
	for _ = 1, count do
		if #bits >= MAX_BITS then
			break
		end
		local part = Common.part({
			Size = Vector3.new(0.35, 0.04, 0.5),
			CFrame = CFrame.new(position),
			Color = palette[math.random(1, #palette)],
			Material = Enum.Material.SmoothPlastic,
		})
		local angle = math.random() * math.pi * 2
		local outward = math.random() * 26
		table.insert(bits, {
			part = part,
			velocity = Vector3.new(math.cos(angle) * outward, 18 + math.random() * 24, math.sin(angle) * outward),
			spin = Vector3.new(math.random() * 8, math.random() * 8, math.random() * 8),
			rotation = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			dieAt = os.clock() + 4 + math.random() * 2,
		})
	end
	if not confettiLoop then
		confettiLoop = RunService.RenderStepped:Connect(function(dt)
			local time = os.clock()
			for index = #bits, 1, -1 do
				local bit = bits[index]
				if time >= bit.dieAt or not bit.part.Parent then
					bit.part:Destroy()
					table.remove(bits, index)
				else
					-- Heavy drag makes paper flutter down slowly
					bit.velocity = bit.velocity * (1 - math.min(1, 2.2 * dt)) + Vector3.new(math.sin(time * 3 + index) * 6, -22, 0) * dt
					bit.rotation = bit.rotation * CFrame.Angles(bit.spin.X * dt, bit.spin.Y * dt, bit.spin.Z * dt)
					bit.part.CFrame = CFrame.new(bit.part.Position + bit.velocity * dt) * bit.rotation
				end
			end
			if #bits == 0 and confettiLoop then
				confettiLoop:Disconnect()
				confettiLoop = nil
			end
		end)
	end
end

-- Fireworks: a rocket with a trail, then a burst of glowing sparks ----------------

function Common.firework(from: Vector3, height: number, color: Color3?)
	local tint = color or RAINBOW[math.random(1, #RAINBOW)]
	local second = RAINBOW[math.random(1, #RAINBOW)]
	local rocket = Common.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, CFrame = CFrame.new(from), Color = tint })
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 0.25, 0)
	top.Parent = rocket
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -0.25, 0)
	bottom.Parent = rocket
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.5
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(tint)
	trail.Transparency = NumberSequence.new(0, 1)
	trail.Parent = rocket
	local burstAt = from + Vector3.new((math.random() - 0.5) * 12, height, (math.random() - 0.5) * 12)
	local flight = Common.tween(rocket, 1.2 + math.random() * 0.4, { CFrame = CFrame.new(burstAt) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	flight.Completed:Once(function()
		rocket.Transparency = 1
		local burst = Instance.new("ParticleEmitter")
		burst.Color = ColorSequence.new(tint, second)
		burst.LightEmission = 1
		burst.LightInfluence = 0
		burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
		burst.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
		burst.Lifetime = NumberRange.new(1.2, 2.2)
		burst.Speed = NumberRange.new(30, 42)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Drag = 2.6
		burst.Acceleration = Vector3.new(0, -9, 0)
		burst.Rate = 0
		burst.Parent = rocket
		burst:Emit(if Common.reduced() then 50 else 150)
		local flash = Instance.new("PointLight")
		flash.Color = tint
		flash.Range = 60
		flash.Brightness = 6
		flash.Parent = rocket
		Common.tween(flash, 1.2, { Brightness = 0 })
		Debris:AddItem(rocket, 3)
	end)
end

-- Rotates a hue around the colour wheel (for rainbow cycling)
function Common.hue(offset: number): Color3
	return Color3.fromHSV((os.clock() * 0.15 + offset) % 1, 0.75, 1)
end

return Common
