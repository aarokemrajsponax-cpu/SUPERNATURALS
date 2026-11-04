-- Jeffery's dialogue: a character panel at the bottom of the screen. His portrait (a
-- ViewportFrame holding a copy of his model) stands on the left, a large dialogue panel sits
-- on the right with a typewriter effect, a Continue button, a quiet Skip button and progress dots.
-- panel.onVisibility(open) is called when a conversation starts and ends (the HUD fades with it).
--
-- say(lines, options): face, title, skippable, skipLabel, onDone (the last line was acknowledged or
-- auto-closed), onSkip (the player pressed Skip), onTalking(bool), autoClose (seconds after the last
-- line finishes typing before the panel closes by itself), choices { { id, label } } with
-- onChoice(id) (the last line shows these buttons instead of Continue and Skip).
-- A new say() replaces the current conversation silently, and hide() closes it silently: neither
-- calls onDone or onSkip, so a replaced line can never fire the old line's callback.
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
	-- Largest size of the panel; it narrows to the screen width minus SideMargin on each side
	-- (SideMargin keeps it clear of the dock on the left) and sits Bottom px above the screen edge
	Size = Vector2.new(980, 196),
	SideMargin = 132,
	Bottom = 24,
	PortraitSize = Vector2.new(188, 172),
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
	onVisibility: ((open: boolean) -> ())?,
}

-- Builds the (hidden) panel in `parent`. `modelProvider` gives a model to copy for the portrait.
function DialoguePanel.build(parent: Instance, modelProvider: (() -> Model?)?): Panel
	local config = DialoguePanel.Config
	-- One opaque card holds everything: a dark portrait plate on the left, the text column on
	-- the right. The card has the only outer edge (a fine line plus a lighter lip along the top).
	local frame = make("Frame", {
		Name = "JefferyDialogue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -config.Bottom),
		Size = UDim2.new(1, -2 * config.SideMargin, 0, config.Size.Y),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	}, { make("UISizeConstraint", { MaxSize = Vector2.new(config.Size.X, config.Size.Y) }) })

	local card = make("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 20,
		Parent = frame,
	}, { make("UICorner", { CornerRadius = UDim.new(0, 4) }), Components.stroke(Colors.Stroke, 1, 0.6) })
	make("Frame", {
		Name = "Lip", Position = UDim2.fromOffset(4, 1), Size = UDim2.new(1, -8, 0, 1),
		BackgroundColor3 = Colors.PanelHover, BorderSizePixel = 0, ZIndex = 21, Parent = card,
	})

	-- Portrait plate: a dark panel, a soft floor disc, the model, and a name tab along the bottom
	local plate = make("Frame", {
		Name = "PortraitPlate", Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(0, config.PortraitSize.X, 1, -24),
		BackgroundColor3 = Colors.Ink, BorderSizePixel = 0, ZIndex = 21, Parent = card,
	}, { make("UICorner", { CornerRadius = UDim.new(0, 4) }) })
	local TAB_HEIGHT = 50
	local floorDisc = make("Frame", {
		Name = "Floor", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -TAB_HEIGHT - 8),
		Size = UDim2.new(0.62, 0, 0, 16), BackgroundColor3 = Colors.PanelHover, BackgroundTransparency = 0.25,
		BorderSizePixel = 0, ZIndex = 22, Parent = plate,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local portrait = make("ViewportFrame", {
		Name = "Portrait", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 1, -TAB_HEIGHT),
		BackgroundTransparency = 1, BorderSizePixel = 0,
		LightColor = Color3.fromRGB(190, 215, 235), Ambient = Color3.fromRGB(110, 124, 140), ZIndex = 23, Parent = plate,
	})
	local tab = make("Frame", {
		Name = "NameTab", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, TAB_HEIGHT), BackgroundColor3 = Colors.PanelLight, BorderSizePixel = 0,
		ZIndex = 24, Parent = plate,
	}, { make("UICorner", { CornerRadius = UDim.new(0, 4) }) })
	local nameLabel = Components.text({
		Name = "Speaker", Text = "Jeffery", Style = "label", Weight = "Bold", TextSize = 18, Color = Colors.Cyan, AlignX = "Center",
		Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 22), ZIndex = 25, Parent = tab,
	})
	local roleLabel = Components.text({
		Name = "Role", Text = "Facility guide", Style = "caption", Color = Colors.TextMuted, AlignX = "Center",
		Position = UDim2.fromOffset(0, 27), Size = UDim2.new(1, 0, 0, 18), ZIndex = 25, Parent = tab,
	})

	-- Text column
	local textLeft = config.PortraitSize.X + 12 + 18
	local line = Components.text({
		Name = "Line", Text = "", TextSize = config.TextSize, Wrap = true, Color = Colors.Text,
		Position = UDim2.fromOffset(textLeft, 16), Size = UDim2.new(1, -textLeft - 22, 0, 104), AutomaticSize = Enum.AutomaticSize.None,
		ZIndex = 21, Parent = card,
	})
	line.TextTruncate = Enum.TextTruncate.None
	line.TextYAlignment = Enum.TextYAlignment.Top
	local dots = make("Frame", {
		Name = "Dots", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, textLeft, 1, -32),
		Size = UDim2.fromOffset(160, 10), BackgroundTransparency = 1, ZIndex = 21, Parent = card,
	}, { make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center }) })

	local continueButton = Components.button("Continue", {
		Name = "Continue", Variant = "Primary", KeepCase = true, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -12),
		Size = UDim2.fromOffset(136, 44), ZIndex = 22, Parent = card,
	})
	local skipButton = Components.button("Skip", {
		Name = "Skip", Variant = "Ghost", KeepCase = true, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16 - 136 - 8, 1, -12),
		Size = UDim2.fromOffset(148, 44), ZIndex = 22, Parent = card,
	})
	-- Choice buttons (shown on the last line of a conversation that has choices)
	local choicesRow = make("Frame", {
		Name = "Choices", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -12),
		Size = UDim2.new(1, -240, 0, 44), BackgroundTransparency = 1, Visible = false, ZIndex = 22, Parent = card,
	}, { make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
	}) })

	-- Phones and small windows: the portrait shrinks and the role line goes
	local function relayout()
		local camera = workspace.CurrentCamera
		local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local small = view.X < 900 or view.Y < 500
		local scale = parent:FindFirstChildOfClass("UIScale")
		local designWidth = view.X / math.max(if scale then scale.Scale else 1, 0.01)
		local portraitWidth = if small then 112 else config.PortraitSize.X
		local margin = if small then config.SideMargin - 40 else config.SideMargin
		frame.Size = UDim2.new(1, -2 * math.min(margin, math.max(8, (designWidth - 360) / 2)), 0, config.Size.Y)
		plate.Size = UDim2.new(0, portraitWidth, 1, -24)
		roleLabel.Visible = not small
		tab.Size = UDim2.new(1, 0, 0, if small then 32 else TAB_HEIGHT)
		portrait.Size = UDim2.new(1, 0, 1, if small then -32 else -TAB_HEIGHT)
		floorDisc.Position = UDim2.new(0.5, 0, 1, (if small then -32 else -TAB_HEIGHT) - 8)
		nameLabel.Position = UDim2.fromOffset(0, if small then 5 else 6)
		local left = portraitWidth + 12 + (if small then 14 else 18)
		line.Position = UDim2.fromOffset(left, 16)
		line.Size = UDim2.new(1, -left - 22, 0, 104)
		dots.Position = UDim2.new(0, left, 1, -32)
	end
	relayout()
	do
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
		end
	end

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
				Name = "Dot" .. i, Size = UDim2.fromOffset(7, 7), BorderSizePixel = 0,
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

	local close: (skipped: boolean, silent: boolean?) -> ()

	local function showChoices()
		for _, child in choicesRow:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for order, choice in options.choices or {} do
			local width = math.max(120, Components.textWidth(choice.label, 18) + 48)
			Components.button(choice.label, {
				Name = "Choice_" .. choice.id, Variant = if order == 1 then "Primary" else "Secondary", KeepCase = true,
				Size = UDim2.fromOffset(width, 44), LayoutOrder = order, ZIndex = 23, Parent = choicesRow,
			}, function()
				local callback = options.onChoice
				close(false, true)
				if callback then
					callback(choice.id)
				end
			end)
		end
		choicesRow.Visible = true
		continueButton.Visible = false
		skipButton.Visible = false
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
		continueButton.Text = if index >= #lines then "Got it" else "Continue"
		if index >= #lines then
			if options.choices and #options.choices > 0 then
				showChoices()
			elseif typeof(options.autoClose) == "number" then
				-- Action steps: the panel gets out of the way by itself so the player can act
				local mine = token
				task.delay(options.autoClose, function()
					if open and token == mine and not typing then
						close(false)
					end
				end)
			end
		end
	end

	local function showLine()
		local text = lines[index]
		choicesRow.Visible = false
		continueButton.Visible = true
		skipButton.Visible = options.skippable ~= false
		line.Text = text
		paintDots()
		token += 1
		local mine = token
		typing = true
		continueButton.Text = "Continue"
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

	function close(skipped: boolean, silent: boolean?)
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
		if panel.onVisibility then
			panel.onVisibility(false)
		end
		if rigStep then
			rigStep:Disconnect()
			rigStep = nil
		end
		local callback = if silent then nil elseif skipped then options.onSkip else options.onDone
		options = {}
		choicesRow.Visible = false
		if callback then
			callback()
		end
	end

	function panel.say(newLines: { string }, newOptions: { [string]: any }?)
		if open then
			close(true, true)
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
		skipButton.Text = if typeof(options.skipLabel) == "string" then options.skipLabel else "Skip"
		nameLabel.Text = "Jeffery"
		relayout()
		if panel.onVisibility then
			panel.onVisibility(true)
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
	-- Continue: finishes the line being typed, or moves to the next, or ends
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
		close(true, true)
	end
	function panel.isOpen()
		return open
	end
	function panel.state()
		return { index = index, total = #lines, typing = typing, text = lines[index], open = open, choices = choicesRow.Visible }
	end

	continueButton.Activated:Connect(panel.press)
	skipButton.Activated:Connect(panel.skip)
	return panel :: Panel
end

local _ = TweenService
return DialoguePanel
