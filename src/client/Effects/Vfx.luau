-- Visual and sound effects, all created locally on this client and cleaned up
-- automatically: sparks, shockwaves, slash arcs, damage numbers, flashes,
-- afterimages and sounds. Built from parts and particles, so no uploaded assets
-- are needed.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Audio = require(ReplicatedStorage.Shared.Config.Audio)
local Settings = require(script.Parent.Parent.Settings)

local Vfx = {}

local folder: Folder? = nil

local function container(): Instance
	if folder and folder.Parent then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "SNEffects"
	newFolder.Parent = workspace.CurrentCamera
	folder = newFolder
	return newFolder
end

local function reduced(): boolean
	return Settings.get("reducedEffects") == true
end

local function effectPart(props: { [string]: any }): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	for key, value in props do
		if key ~= "Size" and key ~= "CFrame" then
			(part :: any)[key] = value
		end
	end
	part.Size = props.Size or Vector3.one
	part.CFrame = props.CFrame or CFrame.new()
	part.Parent = container()
	return part
end

local function fade(instance: Instance, duration: number, goal: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(instance, duration + 0.05)
end

-- A burst of glowing sparks
function Vfx.sparks(position: Vector3, color: Color3, count: number, speed: number?)
	local anchor = effectPart({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(position) })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0, 0.4)
	emitter.Lifetime = NumberRange.new(0.18, 0.4)
	local base = speed or 22
	emitter.Speed = NumberRange.new(base * 0.6, base * 1.3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 6
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(if reduced() then math.ceil(count / 3) else count)
	Debris:AddItem(anchor, 1)
end

-- An expanding glowing bubble (impacts, parries)
function Vfx.shockwave(position: Vector3, color: Color3, fromSize: number, toSize: number, duration: number)
	if reduced() and toSize > 8 then
		toSize *= 0.6
	end
	local bubble = effectPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * fromSize,
		CFrame = CFrame.new(position),
		Color = color,
		Material = Enum.Material.ForceField,
		Transparency = 0,
	})
	fade(bubble, duration, { Size = Vector3.one * toSize, Transparency = 1 })
end

-- A flat ring of light expanding across the ground
function Vfx.groundRing(position: Vector3, color: Color3, fromSize: number, toSize: number, duration: number)
	local ring = effectPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, fromSize, fromSize),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = 0.2,
	})
	fade(ring, duration, { Size = Vector3.new(0.15, toSize, toSize), Transparency = 1 })
end

-- A curved swoosh in front of a fighter. `tilt` rotates the arc (0 = flat,
-- 90 = vertical). `radius` is how far the arc reaches.
function Vfx.slash(origin: CFrame, color: Color3, radius: number, tilt: number, duration: number)
	local segments = if reduced() then 4 else 7
	local spread = math.rad(110)
	local frame = origin * CFrame.Angles(0, 0, math.rad(tilt))
	for i = 0, segments - 1 do
		local angle = -spread / 2 + spread * (i + 0.5) / segments
		local direction = CFrame.Angles(0, angle, 0)
		local length = radius * spread / segments * 1.15
		local thickness = 0.25 * (1 - math.abs(angle) / spread)
		local piece = effectPart({
			Size = Vector3.new(length, 0.08 + thickness, 0.12),
			CFrame = frame * direction * CFrame.new(0, 0, -radius) ,
			Color = color,
			Transparency = 0.15,
		})
		fade(piece, duration, { Transparency = 1, Size = Vector3.new(length * 1.2, 0.02, 0.02) })
	end
end

-- Floating text that rises and fades (damage numbers, BLOCK, PARRY!)
function Vfx.popup(position: Vector3, text: string, color: Color3, scale: number?)
	local size = scale or 1
	local anchor = effectPart({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(position) })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(4 * size, 1.6 * size)
	gui.StudsOffsetWorldSpace = Vector3.new(math.random(-10, 10) / 10, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	gui.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.2
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = anchor

	local rise = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, rise, { StudsOffsetWorldSpace = gui.StudsOffsetWorldSpace + Vector3.new(0, 2.5, 0) }):Play()
	task.delay(0.35, function()
		local out = TweenInfo.new(0.45)
		TweenService:Create(label, out, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, out, { Transparency = 1 }):Play()
	end)
	Debris:AddItem(anchor, 0.9)
end

-- A quick colored flash over a whole character
function Vfx.flash(model: Model, color: Color3, duration: number?)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.FillTransparency = 0.15
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = container()
	fade(highlight, duration or 0.18, { FillTransparency = 1 })
end

-- Ghostly copies of a character's body that fade out (dodges)
function Vfx.afterimage(model: Model, color: Color3)
	if reduced() then
		return
	end
	for _, limb in model:GetChildren() do
		if limb:IsA("BasePart") and limb.Name ~= "HumanoidRootPart" and limb.Transparency < 1 then
			local ghost = limb:Clone()
			ghost:ClearAllChildren()
			ghost.Anchored = true
			ghost.CanCollide = false
			ghost.CanQuery = false
			ghost.CanTouch = false
			ghost.CastShadow = false
			ghost.Massless = true
			ghost.Material = Enum.Material.ForceField
			ghost.Color = color
			ghost.Transparency = 0.1
			if ghost:IsA("MeshPart") then
				ghost.TextureID = ""
			end
			ghost.Parent = container()
			fade(ghost, 0.35, { Transparency = 1 })
		end
	end
end

-- A glow at a fighter's feet while a heavy attack winds up, so opponents can read it
function Vfx.telegraph(root: BasePart, color: Color3, duration: number)
	local ring = effectPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 2, 2),
		CFrame = CFrame.new(root.Position - Vector3.new(0, 2.9, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = 0.1,
	})
	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.12, 9, 9),
		Transparency = 0.45,
	}):Play()
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 2
	light.Parent = ring
	task.delay(duration, function()
		fade(ring, 0.15, { Transparency = 1 })
	end)
end

-- More shapes for power effects ----------------------------------------------------

Vfx.reduced = reduced

-- Full-screen flashes and colour shifts are optional (Settings: Intense flashes)
function Vfx.intense(): boolean
	return Settings.get("intenseEffects") ~= false and not reduced()
end

function Vfx.part(props: { [string]: any }): BasePart
	return effectPart(props)
end

Vfx.fade = fade

-- Loose pieces need to be simulated, which parts under the camera aren't
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

-- A glowing bar from one point to another (beams, lasers, lightning segments)
function Vfx.beam(from: Vector3, to: Vector3, color: Color3, width: number, duration: number, material: Enum.Material?)
	local length = (to - from).Magnitude
	if length < 0.05 then
		return nil
	end
	local beam = effectPart({
		Size = Vector3.new(width, width, length),
		CFrame = CFrame.lookAt((from + to) / 2, to),
		Color = color,
		Material = material or Enum.Material.Neon,
		Transparency = 0.05,
	})
	fade(beam, duration, { Transparency = 1, Size = Vector3.new(width * 0.2, width * 0.2, length) })
	return beam
end

-- Jagged lightning between two points
function Vfx.lightning(from: Vector3, to: Vector3, color: Color3, segments: number?, duration: number?)
	local count = segments or 8
	local previous = from
	for index = 1, count do
		local alpha = index / count
		local point = from:Lerp(to, alpha)
		if index < count then
			point += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2.4
		end
		Vfx.beam(previous, point, color, 0.28, duration or 0.2)
		previous = point
	end
end

-- A flat fan of light in front of `origin` (sweeps, cones, breath attacks)
function Vfx.cone(origin: CFrame, length: number, angle: number, color: Color3, duration: number)
	local pieces = if reduced() then 5 else 9
	local spread = math.rad(angle)
	for index = 0, pieces - 1 do
		local yaw = -spread / 2 + spread * (index + 0.5) / pieces
		local piece = effectPart({
			Size = Vector3.new(length * spread / pieces * 1.1, 0.15, length),
			CFrame = origin * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, -length / 2),
			Color = color,
			Transparency = 0.35,
		})
		fade(piece, duration, { Transparency = 1 })
	end
end

-- A thin ring standing or lying at `cframe` (its look vector is the ring's axis)
function Vfx.ring(cframe: CFrame, radius: number, color: Color3, thickness: number, duration: number, growTo: number?)
	local segments = if reduced() then 10 else 18
	for index = 0, segments - 1 do
		local angle = index / segments * math.pi * 2
		local length = 2 * math.pi * radius / segments * 1.1
		local piece = effectPart({
			Size = Vector3.new(length, thickness, thickness),
			CFrame = cframe * CFrame.Angles(0, 0, angle) * CFrame.new(0, radius, 0),
			Color = color,
			Transparency = 0.1,
		})
		local goal: { [string]: any } = { Transparency = 1 }
		if growTo then
			local scale = growTo / radius
			goal.CFrame = cframe * CFrame.Angles(0, 0, angle) * CFrame.new(0, growTo, 0)
			goal.Size = Vector3.new(length * scale, thickness * 0.5, thickness * 0.5)
		end
		fade(piece, duration, goal)
	end
end

-- Cracks spreading over the ground from a point, with a glowing core
function Vfx.cracks(position: Vector3, radius: number, color: Color3, count: number?, duration: number?)
	local total = count or (if reduced() then 5 else 9)
	local life = duration or 2.5
	for index = 1, total do
		local angle = (index / total) * math.pi * 2 + math.random() * 0.4
		local length = radius * (0.55 + math.random() * 0.45)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local center = position + direction * length / 2 + Vector3.new(0, 0.06, 0)
		local crack = effectPart({
			Size = Vector3.new(0.5 + math.random() * 0.4, 0.08, length),
			CFrame = CFrame.lookAt(center, center + direction),
			Color = Color3.fromRGB(25, 20, 18),
			Material = Enum.Material.Slate,
			Transparency = 0,
		})
		local glow = effectPart({
			Size = Vector3.new(0.18, 0.1, length * 0.9),
			CFrame = crack.CFrame + Vector3.new(0, 0.03, 0),
			Color = color,
			Transparency = 0.05,
		})
		task.delay(life * 0.6, function()
			fade(crack, life * 0.4, { Transparency = 1 })
			fade(glow, life * 0.4, { Transparency = 1 })
		end)
	end
end

-- Chunks of rock (or anything) flying out and falling
function Vfx.debris(position: Vector3, count: number, color: Color3, material: Enum.Material?, speed: number?)
	local total = if reduced() then math.ceil(count / 3) else count
	local force = speed or 40
	for _ = 1, total do
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.one * (0.4 + math.random() * 1.1)
		chunk.CFrame = CFrame.new(position + Vector3.new(0, 1, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		chunk.Color = color
		chunk.Material = material or Enum.Material.Slate
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CastShadow = false
		chunk.Anchored = false
		chunk.Parent = loose()
		local angle = math.random() * math.pi * 2
		chunk.AssemblyLinearVelocity = Vector3.new(math.cos(angle) * force * 0.6, force * (0.6 + math.random() * 0.6), math.sin(angle) * force * 0.6)
		fade(chunk, 1.6, { Transparency = 1 })
	end
end

-- A glowing ball that grows or shrinks (charge-ups, explosions, orbs)
function Vfx.orb(position: Vector3, color: Color3, fromSize: number, toSize: number, duration: number, material: Enum.Material?)
	local orb = effectPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * fromSize,
		CFrame = CFrame.new(position),
		Color = color,
		Material = material or Enum.Material.Neon,
		Transparency = 0.1,
	})
	fade(orb, duration, { Size = Vector3.one * toSize, Transparency = 1 })
	return orb
end

-- A short point-light pulse
function Vfx.glow(at: Vector3 | BasePart, color: Color3, range: number, brightness: number, duration: number)
	local anchor: BasePart
	if typeof(at) == "Vector3" then
		anchor = effectPart({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(at) })
		Debris:AddItem(anchor, duration + 0.1)
	else
		anchor = at
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = anchor
	fade(light, duration, { Brightness = 0 })
	return light
end

-- A one-shot burst of particles. config: color(s), size, speed, lifetime, count, spread, texture
function Vfx.burst(position: Vector3, config: { [string]: any })
	local anchor = effectPart({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(position) })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = config.colors or ColorSequence.new(config.color or Color3.new(1, 1, 1))
	emitter.LightEmission = config.lightEmission or 1
	emitter.LightInfluence = 0
	emitter.Size = config.size or NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = config.transparency or NumberSequence.new(0, 1)
	emitter.Lifetime = config.lifetime or NumberRange.new(0.4, 0.8)
	emitter.Speed = config.speed or NumberRange.new(10, 20)
	emitter.SpreadAngle = config.spread or Vector2.new(180, 180)
	emitter.Drag = config.drag or 3
	emitter.Acceleration = config.acceleration or Vector3.zero
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	if config.texture then
		emitter.Texture = config.texture
	end
	emitter.Rate = 0
	emitter.Parent = anchor
	local count = config.count or 20
	emitter:Emit(if reduced() then math.ceil(count / 3) else count)
	Debris:AddItem(anchor, 3)
end

-- A copy of a character's body at a chosen spot that fades (afterimages, decoys)
function Vfx.ghostAt(model: Model, cframe: CFrame?, color: Color3, duration: number, material: Enum.Material?)
	if reduced() and duration < 0.6 then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local offset = if cframe then cframe * root.CFrame:Inverse() else CFrame.identity
	for _, limb in model:GetChildren() do
		if limb:IsA("BasePart") and limb.Name ~= "HumanoidRootPart" then
			local ghost = limb:Clone()
			ghost:ClearAllChildren()
			ghost.Anchored = true
			ghost.CanCollide = false
			ghost.CanQuery = false
			ghost.CanTouch = false
			ghost.CastShadow = false
			ghost.Massless = true
			ghost.Material = material or Enum.Material.ForceField
			ghost.Color = color
			ghost.Transparency = 0.15
			ghost.CFrame = offset * limb.CFrame
			if ghost:IsA("MeshPart") then
				ghost.TextureID = ""
			end
			ghost.Parent = container()
			fade(ghost, duration, { Transparency = 1 })
		end
	end
end

-- Holographic text floating in the world (Syntax's code, Admin's commands)
function Vfx.text3d(position: Vector3, text: string, color: Color3, size: number?, duration: number?)
	local anchor = effectPart({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(position) })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(#text * 0.55 * (size or 1) + 1, 1.2 * (size or 1))
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = 120
	gui.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.Font = Enum.Font.Code
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.6
	label.Parent = gui
	gui.Parent = anchor
	local life = duration or 1.2
	task.delay(life * 0.6, function()
		TweenService:Create(label, TweenInfo.new(life * 0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	Debris:AddItem(anchor, life + 0.1)
end

-- A brief coloured tint over the whole screen (only if intense effects are on)
function Vfx.screenFlash(color: Color3, strength: number, duration: number)
	if not Vfx.intense() then
		return
	end
	local Lighting = game:GetService("Lighting")
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "SNFlash"
	effect.TintColor = Color3.new(1, 1, 1):Lerp(color, math.clamp(strength, 0, 1))
	effect.Brightness = 0.1 * strength
	effect.Parent = Lighting
	fade(effect, duration, { TintColor = Color3.new(1, 1, 1), Brightness = 0 })
end

function Vfx.sound(name: string, at: Vector3 | Instance)
	local spec = Audio.Sounds[name]
	if not spec then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = spec.Id
	local volume = Settings.get("sfxVolume")
	sound.Volume = spec.Volume * (if typeof(volume) == "number" then volume else 1)
	sound.PlaybackSpeed = spec.Pitch * (0.95 + math.random() * 0.1)
	sound.RollOffMaxDistance = 120
	if typeof(at) == "Vector3" then
		local anchor = effectPart({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(at) })
		sound.Parent = anchor
		Debris:AddItem(anchor, 3)
	else
		sound.Parent = at
		Debris:AddItem(sound, 3)
	end
	sound:Play()
end

return Vfx
