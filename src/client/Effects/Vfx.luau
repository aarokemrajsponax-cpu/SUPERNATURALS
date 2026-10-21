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

function Vfx.sound(name: string, at: Vector3 | Instance)
	local spec = Audio.Sounds[name]
	if not spec then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = spec.Id
	sound.Volume = spec.Volume
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
