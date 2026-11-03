-- Jeffery's dialogue: a character panel at the bottom of the screen. His portrait (a
-- ViewportFrame holding a copy of his model) stands on the left, a large dialogue panel sits
-- on the right with a typewriter effect, a CONTINUE button, a Skip button and progress dots.
--
-- Also here: the rig that animates a copy of Jeffery's model (idle hover bob, head turns,
-- blinking, gestures while talking, facial expressions). The world copy and the portrait copy
-- use the same rig. In the world his face is the SurfaceGui built by World/Jeffery; in the
-- portrait (SurfaceGuis do not draw inside a ViewportFrame) the face is drawn with neon parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Audio = require(ReplicatedStorage.Shared.Config.Audio)
local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local make = Components.make
local Colors = Theme.Colors

local DialoguePanel = {}

DialoguePanel.Config = {
	-- Characters revealed per second
	TypeSpeed = 48,
	Size = Vector2.new(980, 196),
	PortraitSize = Vector2.new(200, 236),
	TextSize = 20,
}

-- The rig -------------------------------------------------------------------------------------

export type Rig = {
	model: Model,
	step: (time: number, dt: number) -> (),
	setFace: (name: string) -> (),
	setTalking: (talking: boolean) -> (),
	gesture: () -> (),
	setBase: (cf: CFrame) -> (),
	face: string,
	talking: boolean,
}

-- portrait = true draws the face with parts (for a ViewportFrame). `base` is where the model
-- stands; the rig keeps it there and adds the bob.
function DialoguePanel.rig(model: Model, portrait: boolean): Rig
	local root = model.PrimaryPart :: BasePart
	local base = model:GetPivot()
	local head = model:FindFirstChild("Head") :: Model?
	local arms = { model:FindFirstChild("ArmL") :: Model?, model:FindFirstChild("ArmR") :: Model? }
	local local_ = {} :: { [Model]: CFrame }
	for _, sub in { head, arms[1], arms[2] } do
		if sub then
			local_[sub] = base:ToObjectSpace(sub:GetPivot())
		end
	end
	local screen = head and head:FindFirstChild("Screen") :: BasePart?
	local gui = screen and screen:FindFirstChildOfClass("SurfaceGui")
	local seed = math.random() * 10

	local rig = { model = model, face = "happy", talking = false } :: any
	local blinkAt = os.clock() + 2
	local blinkUntil = 0
	local gestureUntil = 0
	local mouthScale = 1

	-- Portrait face parts
	local parts: { [string]: Part } = {}
	if portrait and screen then
		if gui then
			gui:Destroy()
			gui = nil
		end
		for _, name in { "EyeL", "EyeR", "Mouth" } do
			local p = Instance.new("Part")
			p.Name = name
			p.Anchored = true
			p.CanCollide = false
			p.Material = Enum.Material.Neon
			p.Color = Tutorial.FaceColor
			p.Size = Vector3.new(0.3, 0.3, 0.05)
			p.Parent = head
			parts[name] = p
		end
	end

	local function layout(blink: number)
		local face = Tutorial.Faces[rig.face] or Tutorial.Faces.happy
		local eyeW, eyeH, eyeY, eyeTilt, eyeRound = table.unpack(face.eye)
		local mouthW, mouthH, mouthY, mouthTilt, mouthRound = table.unpack(face.mouth)
		eyeH *= blink
		mouthH *= mouthScale
		if gui then
			local function put(frame: Frame, x: number, y: number, w: number, h: number, tilt: number, round: boolean)
				frame.AnchorPoint = Vector2.new(0.5, 0.5)
				frame.Position = UDim2.fromScale(x, y + h / 2)
				frame.Size = UDim2.fromScale(w, h)
				frame.Rotation = tilt
				local corner = frame:FindFirstChildOfClass("UICorner")
				if corner then
					corner.CornerRadius = if round then UDim.new(0.5, 0) else UDim.new(0.2, 0)
				end
			end
			put(gui:FindFirstChild("EyeL") :: Frame, 0.3, eyeY, eyeW, eyeH, eyeTilt, eyeRound)
			put(gui:FindFirstChild("EyeR") :: Frame, 0.7, eyeY, eyeW, eyeH, -eyeTilt, eyeRound)
			put(gui:FindFirstChild("Mouth") :: Frame, 0.5, mouthY, mouthW, mouthH, mouthTilt, mouthRound)
		elseif screen and parts.EyeL then
			local size = screen.Size
			local function put(part: Part, x: number, y: number, w: number, h: number, tilt: number)
				part.Size = Vector3.new(math.max(w * size.X, 0.05), math.max(h * size.Y, 0.05), 0.05)
				part.CFrame = screen.CFrame
					* CFrame.new((x - 0.5) * size.X, (0.5 - (y + h / 2)) * size.Y, -size.Z / 2 - 0.03)
					* CFrame.Angles(0, 0, -math.rad(tilt))
			end
			put(parts.EyeL, 0.3, eyeY, eyeW, eyeH, eyeTilt)
			put(parts.EyeR, 0.7, eyeY, eyeW, eyeH, -eyeTilt)
			put(parts.Mouth, 0.5, mouthY, mouthW, mouthH, mouthTilt)
		end
	end

	function rig.setFace(name: string)
		if Tutorial.Faces[name] then
			rig.face = name
		end
	end
	function rig.setTalking(talking: boolean)
		rig.talking = talking
	end
	function rig.setBase(cf: CFrame)
		base = cf
	end
	function rig.gesture()
		gestureUntil = os.clock() + 0.9
	end

	function rig.step(time: number, _dt: number)
		local t = time + seed
		local bob = math.sin(t * 1.6) * 0.18
		local rootCF = base * CFrame.new(0, bob, 0)
		model:PivotTo(rootCF)
		-- Head: slow look around, a nod while talking
		if head then
			local yaw = math.sin(t * 0.55) * 0.35 + math.sin(t * 1.3) * 0.06
			local pitch = math.sin(t * 0.9) * 0.05
			if rig.talking then
				pitch += math.sin(t * 7) * 0.05
				yaw *= 0.4
			end
			head:PivotTo(rootCF * local_[head] * CFrame.Angles(pitch, yaw, 0))
		end
		-- Arms: sway; wave about when talking or gesturing
		local active = rig.talking or time < gestureUntil
		for index, arm in arms do
			if arm then
				local side = if index == 1 then -1 else 1
				local swing = math.sin(t * 1.2 + index) * 0.06
				local raise = 0
				if active then
					raise = (0.5 + 0.35 * math.sin(t * 4 + index * 2)) * (if index == 2 then 1 else 0.5)
				end
				arm:PivotTo(rootCF * local_[arm] * CFrame.Angles(-raise + swing, 0, side * 0.08))
			end
		end
		-- Blink, and a talking mouth
		local clock = os.clock()
		if clock >= blinkAt then
			blinkUntil = clock + 0.12
			blinkAt = clock + 2 + math.random() * 3
		end
		mouthScale = if rig.talking then 0.6 + 0.8 * math.abs(math.sin(t * 11)) else 1
		layout(if clock < blinkUntil then 0.12 else 1)
	end

	layout(1)
	return rig :: Rig
end

-- The panel ----------------------------------------------------------------------------------

export type Panel = {
	frame: Frame,
	say: (lines: { string }, options: { [string]: any }?) -> (),
	hide: () -> (),
	isOpen: () -> boolean,
	finishLine: () -> (),
	press: () -> (),
	skip: () -> (),
	state: () -> { [string]: any },
	rig: Rig?,
	portrait: ViewportFrame,
}

-- Builds the (hidden) panel in `parent`. `modelProvider` gives a model to copy for the portrait.
function DialoguePanel.build(parent: Instance, modelProvider: (() -> Model?)?): Panel
	local config = DialoguePanel.Config
	local frame = make("Frame", {
		Name = "JefferyDialogue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(config.Size.X, config.Size.Y),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	})

	-- Dialogue panel (right of the portrait)
	local panelLeft = config.PortraitSize.X - 24
	local card = make("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0, config.Size.X - panelLeft, 1, 0),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = 20,
		Parent = frame,
	}, { Components.corner(), Components.stroke(Colors.Stroke, 1, 0.55) })

	local nameLabel = Components.text({
		Name = "Speaker", Text = "JEFFERY", Style = "Label", Track = true, Color = Colors.Cyan,
		Position = UDim2.fromOffset(150, 14), Size = UDim2.new(1, -300, 0, 22), ZIndex = 21, Parent = card,
	})
	local line = Components.text({
		Name = "Line", Text = "", TextSize = config.TextSize, Wrap = true, Color = Colors.Text,
		Position = UDim2.fromOffset(150, 44), Size = UDim2.new(1, -174, 0, 80), AutomaticSize = Enum.AutomaticSize.None,
		ZIndex = 21, Parent = card,
	})
	line.TextTruncate = Enum.TextTruncate.AtEnd
	local dots = make("Frame", {
		Name = "Dots", Position = UDim2.new(0, 150, 1, -46), Size = UDim2.fromOffset(160, 20),
		BackgroundTransparency = 1, ZIndex = 21, Parent = card,
	}, { make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center }) })

	local continueButton = Components.button("Continue", {
		Name = "Continue", Variant = "Primary", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -12),
		Size = UDim2.fromOffset(150, 44), ZIndex = 22, Parent = card,
	})
	local skipButton = Components.button("Skip", {
		Name = "Skip", Variant = "Ghost", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6),
		Size = UDim2.fromOffset(100, 44), ZIndex = 22, Parent = card,
	})

	-- Portrait
	local portrait = make("ViewportFrame", {
		Name = "Portrait", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(config.PortraitSize.X, config.PortraitSize.Y),
		BackgroundColor3 = Colors.Ink, BackgroundTransparency = 0.1, BorderSizePixel = 0,
		LightColor = Color3.fromRGB(190, 215, 235), Ambient = Color3.fromRGB(110, 124, 140), ZIndex = 23, Parent = frame,
	}, { Components.corner(), Components.stroke(Colors.Cyan, 1, 0.5) })

	local panel = { frame = frame, portrait = portrait } :: any
	local lines: { string } = {}
	local index = 0
	local options: { [string]: any } = {}
	local open = false
	local typing = false
	local token = 0
	local rigStep: RBXScriptConnection? = nil

	local function setupPortrait()
		if panel.rig or not modelProvider then
			return
		end
		local source = modelProvider()
		if not source then
			return
		end
		local copy = source:Clone()
		for _, item in copy:GetDescendants() do
			if item:IsA("ProximityPrompt") then
				item:Destroy()
			end
		end
		copy:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(180), 0))
		copy.Parent = portrait
		local camera = Instance.new("Camera")
		camera.FieldOfView = 34
		-- Bust framing: head and chest
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 6.6, 14), Vector3.new(0, 5.6, 0))
		camera.Parent = portrait
		portrait.CurrentCamera = camera
		panel.rig = DialoguePanel.rig(copy, true)
	end

	local function paintDots()
		for _, child in dots:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for i = 1, #lines do
			make("Frame", {
				Name = "Dot" .. i, Size = UDim2.fromOffset(10, 10), BorderSizePixel = 0,
				BackgroundColor3 = if i <= index then Colors.Cyan else Colors.TextMuted,
				BackgroundTransparency = if i <= index then 0 else 0.5, LayoutOrder = i, ZIndex = 22, Parent = dots,
			}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		end
	end

	local blip = Audio.Sounds and (Audio.Sounds :: any).DialogueBlip
	local function playBlip()
		if not blip or not blip.Id then
			return
		end
		local sound = Instance.new("Sound")
		sound.SoundId = blip.Id
		sound.Volume = (blip.Volume or 0.2)
		sound.PlaybackSpeed = (blip.Pitch or 1.6) + math.random() * 0.2
		sound.Parent = SoundService
		sound:Play()
		task.delay(1, function()
			sound:Destroy()
		end)
	end

	local function finishTyping()
		token += 1
		typing = false
		line.MaxVisibleGraphemes = -1
		if panel.rig then
			panel.rig.setTalking(false)
		end
		if options.onTalking then
			options.onTalking(false)
		end
		continueButton.Text = if index >= #lines then "GOT IT" else "CONTINUE"
	end

	local function showLine()
		local text = lines[index]
		line.Text = text
		paintDots()
		token += 1
		local mine = token
		typing = true
		continueButton.Text = "CONTINUE"
		if panel.rig then
			panel.rig.setTalking(true)
			panel.rig.gesture()
		end
		if options.onTalking then
			options.onTalking(true)
		end
		local total = utf8.len(text) or #text
		line.MaxVisibleGraphemes = 0
		task.spawn(function()
			local shown = 0
			local last = os.clock()
			while mine == token and shown < total do
				task.wait()
				local clock = os.clock()
				shown = math.min(total, shown + (clock - last) * config.TypeSpeed)
				last = clock
				line.MaxVisibleGraphemes = math.floor(shown)
				if math.floor(shown) % 3 == 0 then
					playBlip()
				end
			end
			if mine == token then
				finishTyping()
			end
		end)
	end

	local function close(skipped: boolean)
		if not open then
			return
		end
		open = false
		token += 1
		typing = false
		if panel.rig then
			panel.rig.setTalking(false)
		end
		if options.onTalking then
			options.onTalking(false)
		end
		frame.Visible = false
		if rigStep then
			rigStep:Disconnect()
			rigStep = nil
		end
		local callback = if skipped then options.onSkip else options.onDone
		options = {}
		if callback then
			callback()
		end
	end

	function panel.say(newLines: { string }, newOptions: { [string]: any }?)
		if open then
			close(true)
		end
		lines = newLines
		options = newOptions or {}
		index = 1
		open = true
		frame.Visible = true
		skipButton.Visible = options.skippable ~= false
		setupPortrait()
		if panel.rig then
			panel.rig.setFace(options.face or "happy")
			if not rigStep then
				local RunService = game:GetService("RunService")
				rigStep = RunService.Heartbeat:Connect(function(dt)
					panel.rig.step(os.clock(), dt)
				end)
			end
		end
		if options.title then
			nameLabel.Text = Theme.track(string.upper(options.title))
		else
			nameLabel.Text = Theme.track("JEFFERY")
		end
		showLine()
	end

	function panel.setFace(name: string)
		if panel.rig then
			panel.rig.setFace(name)
		end
	end
	function panel.finishLine()
		if typing then
			finishTyping()
		end
	end
	-- CONTINUE: finishes the line being typed, or moves to the next, or ends
	function panel.press()
		if not open then
			return
		end
		if typing then
			finishTyping()
		elseif index >= #lines then
			close(false)
		else
			index += 1
			showLine()
		end
	end
	function panel.skip()
		close(true)
	end
	function panel.hide()
		close(true)
	end
	function panel.isOpen()
		return open
	end
	function panel.state()
		return { index = index, total = #lines, typing = typing, text = lines[index], open = open }
	end

	continueButton.Activated:Connect(panel.press)
	skipButton.Activated:Connect(panel.skip)
	return panel :: Panel
end

local _ = TweenService
return DialoguePanel
