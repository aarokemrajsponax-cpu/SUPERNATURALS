-- JEFFERY, the facility's assistant robot, built from parts (no meshes, no asset ids).
-- He hovers beside the JEFFERY'S BASE door. Smooth ivory body, a graphite head with a
-- digital face screen (a SurfaceGui with two eyes and a mouth, set by Tutorial.Faces), glowing
-- cyan details, a small octagon insignia on the chest and a nameplate reading JEFFERY.
--
-- Model layout (front is -Z): Root (anchored, the pivot), Head (Model: Shell, Screen, Ears,
-- Antenna), ArmL and ArmR (Models whose PrimaryPart is the shoulder), plus body parts.
-- The client animates the sub-models (bob, head turns, gestures); this file only builds.
-- Attribute "Face" on the model holds the expression the server built him with.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)

local Jeffery = {}

local IVORY = Color3.fromRGB(226, 230, 234)
local GRAPHITE = Color3.fromRGB(34, 38, 46)
local SCREEN = Color3.fromRGB(8, 12, 20)
local STEEL = Color3.fromRGB(138, 146, 156)
local AMBER = Color3.fromRGB(232, 166, 74)

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props or {} do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function glow(parent: Instance, name: string, size: Vector3, cframe: CFrame, shape: Enum.PartType?): Part
	return part(parent, name, size, cframe, Tutorial.FaceColor, {
		Material = Enum.Material.Neon,
		Shape = shape or Enum.PartType.Block,
	})
end

-- Draws a face on the screen's SurfaceGui instantly (the client tweens its own copy)
function Jeffery.applyFace(gui: SurfaceGui, name: string)
	local face = Tutorial.Faces[name] or Tutorial.Faces.happy
	local eyeW, eyeH, eyeY, eyeTilt, eyeRound = table.unpack(face.eye)
	local mouthW, mouthH, mouthY, mouthTilt, mouthRound = table.unpack(face.mouth)
	local function place(frame: Frame, x: number, y: number, w: number, h: number, tilt: number, round: boolean)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(x, y + h / 2)
		frame.Size = UDim2.fromScale(w, h)
		frame.Rotation = tilt
		local corner = frame:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = if round then UDim.new(0.5, 0) else UDim.new(0.2, 0)
		end
	end
	place(gui.EyeL :: Frame, 0.3, eyeY, eyeW, eyeH, eyeTilt, eyeRound)
	place(gui.EyeR :: Frame, 0.7, eyeY, eyeW, eyeH, -eyeTilt, eyeRound)
	place(gui.Mouth :: Frame, 0.5, mouthY, mouthW, mouthH, mouthTilt, mouthRound)
	gui:SetAttribute("Face", name)
end

local function faceGui(screen: Part)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.AlwaysOnTop = false
	gui.Parent = screen
	for _, name in { "EyeL", "EyeR", "Mouth" } do
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.BackgroundColor3 = Tutorial.FaceColor
		frame.BorderSizePixel = 0
		frame.Parent = gui
		local corner = Instance.new("UICorner")
		corner.Parent = frame
	end
	Jeffery.applyFace(gui, "happy")
	return gui
end

-- A text plate: dark slab with letters drawn on a SurfaceGui
local function plate(parent: Instance, name: string, size: Vector3, cframe: CFrame, text: string, textSize: number): Part
	local slab = part(parent, name, size, cframe, GRAPHITE, { Material = Enum.Material.Metal })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Parent = slab
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(232, 238, 244)
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextScaled = true
	label.Parent = gui
	return slab
end

-- The octagon insignia: two squares, one turned 45 degrees, in a ring
local function insignia(slab: Part)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Insignia"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Parent = slab
	for _, turn in { 0, 45 } do
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromScale(0.42, 0.42 * slab.Size.X / slab.Size.Y)
		frame.Rotation = turn
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Color = Tutorial.FaceColor
		stroke.Thickness = 2
		stroke.Parent = frame
	end
end

-- Builds Jeffery at the origin, floor level, facing -Z. Returns the model (not parented).
function Jeffery.model(): Model
	local model = Instance.new("Model")
	model.Name = "Jeffery"
	local at = function(x: number, y: number, z: number)
		return CFrame.new(x, y, z)
	end

	local root = part(model, "Root", Vector3.new(1, 1, 1), at(0, 1.4, 0), IVORY, { Transparency = 1 })
	model.PrimaryPart = root

	-- Hover base: a dark disc, a glowing ring and a soft light underneath
	part(model, "HoverDisc", Vector3.new(0.5, 3.2, 3.2), at(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)), GRAPHITE, {
		Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal,
	})
	glow(model, "HoverRing", Vector3.new(0.2, 3.5, 3.5), at(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder).Transparency = 0.15
	local light = Instance.new("PointLight")
	light.Color = Tutorial.FaceColor
	light.Range = 10
	light.Brightness = 1.2
	light.Parent = model.HoverRing

	-- Body: a smooth egg, a waist band, the chest panel and a core
	part(model, "Torso", Vector3.new(3.6, 4.2, 3.4), at(0, 3.9, 0), IVORY, { Shape = Enum.PartType.Ball })
	part(model, "Waist", Vector3.new(3.1, 0.35, 3.1), at(0, 2.5, 0), STEEL, {
		Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal,
	}).CFrame = at(0, 2.5, 0) * CFrame.Angles(0, 0, math.rad(90))
	model.Waist.Size = Vector3.new(0.3, 3.0, 3.0)
	local panel = part(model, "ChestPanel", Vector3.new(2.0, 1.5, 0.25), at(0, 4.2, -1.62) * CFrame.Angles(math.rad(-8), 0, 0), GRAPHITE, {
		Material = Enum.Material.Metal,
	})
	insignia(panel)
	glow(model, "Core", Vector3.new(0.5, 0.5, 0.2), at(0, 3.0, -1.55), Enum.PartType.Ball)
	local nameplate = plate(model, "Nameplate", Vector3.new(2.4, 0.55, 0.15), at(0, 3.35, -1.65) * CFrame.Angles(math.rad(-6), 0, 0), "JEFFERY", 26)
	nameplate:SetAttribute("Nameplate", true)

	-- Neck and head
	part(model, "Neck", Vector3.new(0.5, 1.0, 1.0), at(0, 5.9, 0) * CFrame.Angles(0, 0, math.rad(90)), STEEL, {
		Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal,
	})
	local head = Instance.new("Model")
	head.Name = "Head"
	head.Parent = model
	local shell = part(head, "Shell", Vector3.new(3.9, 2.9, 3.3), at(0, 7.1, 0), GRAPHITE, {
		Shape = Enum.PartType.Ball, Material = Enum.Material.Metal,
	})
	head.PrimaryPart = shell
	local screen = part(head, "Screen", Vector3.new(2.9, 1.8, 0.12), at(0, 7.15, -1.52) * CFrame.Angles(math.rad(-3), 0, 0), SCREEN, {
		Material = Enum.Material.Glass,
	})
	faceGui(screen)
	for _, side in { -1, 1 } do
		glow(head, side < 0 and "EarL" or "EarR", Vector3.new(0.5, 1.1, 1.1), at(side * 1.9, 7.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
	end
	part(head, "AntennaStem", Vector3.new(0.12, 0.9, 0.12), at(0.8, 8.8, 0.2), STEEL, { Material = Enum.Material.Metal })
	glow(head, "AntennaTip", Vector3.new(0.4, 0.4, 0.4), at(0.8, 9.35, 0.2), Enum.PartType.Ball)
	part(head, "Visor", Vector3.new(3.1, 0.12, 0.5), at(0, 8.15, -1.2) * CFrame.Angles(math.rad(-18), 0, 0), AMBER, { Material = Enum.Material.Metal })

	-- Arms: a shoulder ball (the pivot), an upper arm and a hand. Rest pose hangs slightly forward.
	for _, side in { -1, 1 } do
		local arm = Instance.new("Model")
		arm.Name = if side < 0 then "ArmL" else "ArmR"
		arm.Parent = model
		local shoulder = part(arm, "Shoulder", Vector3.new(0.9, 0.9, 0.9), at(side * 2.15, 4.9, 0), STEEL, {
			Shape = Enum.PartType.Ball, Material = Enum.Material.Metal,
		})
		arm.PrimaryPart = shoulder
		part(arm, "Upper", Vector3.new(1.9, 0.6, 0.6), at(side * 2.35, 3.95, -0.2), IVORY, { Shape = Enum.PartType.Cylinder }).CFrame =
			at(side * 2.35, 3.95, -0.2) * CFrame.Angles(0, 0, math.rad(90 - side * 6))
		part(arm, "Hand", Vector3.new(0.9, 0.9, 0.9), at(side * 2.5, 2.9, -0.35), GRAPHITE, {
			Shape = Enum.PartType.Ball, Material = Enum.Material.Metal,
		})
		glow(arm, "Cuff", Vector3.new(0.15, 0.75, 0.75), at(side * 2.45, 3.1, -0.3) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
	end
	model:SetAttribute("Face", "happy")
	return model
end

-- Places Jeffery beside the JEFFERY'S BASE door and gives him a "Talk" prompt
function Jeffery.build(folder: Instance): Model
	local Hub = require(script.Parent.Hub)
	local entry
	for _, gate in Hub.Gates do
		if gate.id == "Learn" then
			entry = gate
		end
	end
	local model = Jeffery.model()
	local origin = entry.position + entry.facing * 7 + entry.facing:Cross(Vector3.yAxis) * 11
	-- The model faces -Z; look towards the hub, turned a little towards the door
	local look = (entry.facing * 5 - entry.facing:Cross(Vector3.yAxis) * 4)
	model:PivotTo(CFrame.lookAt(origin + Vector3.new(0, 0.2, 0), origin + Vector3.new(0, 0.2, 0) + look) * CFrame.new(0, -1.4, 0))
	model:SetAttribute("Home", origin)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "JEFFERY"
	prompt.ActionText = "Talk to Jeffery"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	-- Same keys as the hub's doors; E and F are combat keys
	prompt.KeyboardKeyCode = Enum.KeyCode.T
	prompt.GamepadKeyCode = Enum.KeyCode.DPadRight
	prompt:SetAttribute("Action", "Window:Learn")
	prompt.Parent = model:FindFirstChild("Torso")
	model.Parent = folder
	return model
end

return Jeffery
