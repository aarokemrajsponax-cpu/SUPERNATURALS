-- How Syntax looks: precise, clean and readable. Emerald markup and white text
-- on dark glass: selection brackets that snap onto targets, thin pen-stroke
-- lines, square ripples, monospace code fragments, holographic panels with
-- live countdowns, and the rule being changed written over the field in big
-- letters. Programme LATTICE's sigil (a grid of dots) runs through her bigger
-- moves. Degree 1 is small and local; Degree 2 adds runtime panels; Degree 3
-- adds the large lattice halo and arena-scale structures.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Attribute = Protocol.Attribute

local Syntax = {}
local fx = {}
Syntax.fx = fx
Syntax.projectiles = {}
Syntax.predict = {}

local rgb = Color3.fromRGB
-- One signature pair (emerald markup, white text) over a dark glass neutral
local EMERALD = rgb(38, 226, 168)
local TEAL = rgb(30, 150, 140)
local WHITE = rgb(232, 255, 246)
local GLASS = rgb(10, 30, 34)
local INK = rgb(6, 20, 22)
local MONO = Enum.Font.RobotoMono
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local GEAR = "SNSyntaxGear"
local FORWARD = CFrame.Angles(0, math.rad(90), 0)

-- Code fragments that drift off her effects (the station, read as text)
local TOKENS = { "0x0E", "};", "fix()", "!=", "door[14]", "ok", "::", "ret", "0110", "[i]", "typo", "set", "nil", "ln 47", "sync", "=>" }
-- What her gear's screens scroll through
local LINES = {
	"> read station.txt",
	"> door[14] = OPEN",
	"> fix typo @ 0x0E",
	"> lattice.sync()",
	"> gravity: 1.0 ok",
	"> rule.check() ok",
	"> trace ln 47",
	"> scan: 2 subjects",
	"> mark.queue = []",
	"> cache clear",
}

-- Small, safe readers (effect data comes from the network) ----------------------------

local function num(value: any, default: number): number
	return if typeof(value) == "number" and value == value and math.abs(value) < 1e6 then value else default
end

local function vec(value: any): Vector3?
	if typeof(value) == "Vector3" and value.X == value.X and value.Y == value.Y and value.Z == value.Z then
		return value
	end
	return nil
end

local function frameOf(value: any): CFrame?
	return if typeof(value) == "CFrame" then value else nil
end

local function modelOf(value: any): Model?
	return if typeof(value) == "Instance" and value:IsA("Model") then value else nil
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function flat(vector: Vector3): Vector3
	local level = Vector3.new(vector.X, 0, vector.Z)
	return if level.Magnitude > 1e-3 then level.Unit else Vector3.new(0, 0, -1)
end

local function hand(kit): Vector3
	return if kit.root then (kit.root.CFrame * CFrame.new(1.1, 0.7, -1.6)).Position else Vector3.zero
end

local function cameraPosition(): Vector3
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else Vector3.new(0, 10, 20)
end

local function key(time: number, value: number)
	return NumberSequenceKeypoint.new(time, value)
end

local function tween(instance: Instance, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	TweenService:Create(instance, info, goal):Play()
end

-- Runs step(elapsed) every frame until it returns false or `limit` seconds pass.
-- Returns stop(). Errors stop it instead of spamming.
local function animate(limit: number, step: (number) -> boolean?): () -> ()
	local started = os.clock()
	local running = true
	local connection
	local function stop()
		if running then
			running = false
			connection:Disconnect()
		end
	end
	connection = RunService.Heartbeat:Connect(function()
		if not running then
			return
		end
		local elapsed = os.clock() - started
		if elapsed > limit then
			stop()
			return
		end
		local ok, result = pcall(step, elapsed)
		if not ok or result == false then
			stop()
		end
	end)
	return stop
end

-- Building blocks --------------------------------------------------------------------------

local function piece(kit, props: { [string]: any }): BasePart
	return kit.Vfx.part(props)
end

-- Fades a piece out and removes it
local function retire(kit, part: BasePart?, duration: number, goal: { [string]: any }?)
	if not part or not part.Parent then
		return
	end
	local final = goal or {}
	final.Transparency = 1
	kit.Vfx.fade(part, duration, final)
end

local function retireAll(kit, parts: { any }, duration: number)
	for _, part in parts do
		retire(kit, part, duration)
	end
end

-- A thin precise line that stays until removed
local function bar(kit, from: Vector3, to: Vector3, width: number, color: Color3, transparency: number?): BasePart?
	local length = (to - from).Magnitude
	if length < 0.02 then
		return nil
	end
	return piece(kit, {
		Size = Vector3.new(width, width, length),
		CFrame = CFrame.lookAt((from + to) / 2, to),
		Color = color,
		Transparency = transparency or 0.1,
	})
end

local function placeBar(part: BasePart, from: Vector3, to: Vector3, width: number)
	local length = math.max(0.02, (to - from).Magnitude)
	part.Size = Vector3.new(width, width, length)
	part.CFrame = CFrame.lookAt((from + to) / 2, if (to - from).Magnitude > 0.01 then to else from + Vector3.new(0, 0, -0.01))
end

-- A square of four thin bars around `cframe` (its look vector is the square's axis).
-- With growTo it expands and fades: her ripple.
local function square(kit, cframe: CFrame, half: number, thickness: number, color: Color3, duration: number, growTo: number?)
	local parts = {}
	for index = 0, 3 do
		local turn = cframe * CFrame.Angles(0, 0, index * math.pi / 2)
		local part = piece(kit, {
			Size = Vector3.new(half * 2 + thickness, thickness, thickness),
			CFrame = turn * CFrame.new(0, half, 0),
			Color = color,
			Transparency = 0.05,
		})
		local goal: { [string]: any } = { Transparency = 1 }
		if growTo then
			goal.CFrame = turn * CFrame.new(0, growTo, 0)
			goal.Size = Vector3.new(growTo * 2, thickness * 0.4, thickness * 0.4)
		end
		kit.Vfx.fade(part, duration, goal)
		table.insert(parts, part)
	end
	return parts
end

-- A square lying on the ground at `position`
local function groundSquare(kit, position: Vector3, half: number, color: Color3, duration: number, growTo: number?, spin: number?)
	local frame = CFrame.new(position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, spin or 0, 0) * CFrame.Angles(math.rad(90), 0, 0)
	return square(kit, frame, half, 0.08, color, duration, growTo)
end

-- A circle of segments flat on the ground that stays until removed (dashed skips every other)
local function circle(kit, center: Vector3, radius: number, color: Color3, thickness: number, transparency: number, dashed: boolean?): { BasePart }
	local parts = {}
	local segments = math.clamp(math.floor(radius * 2.4), 16, 40)
	if kit.Vfx.reduced() then
		segments = math.max(12, math.floor(segments * 0.6))
	end
	for index = 0, segments - 1 do
		if not dashed or index % 2 == 0 then
			local angle = index / segments * math.pi * 2
			local at = center + Vector3.new(math.cos(angle) * radius, 0.07, math.sin(angle) * radius)
			local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			table.insert(parts, piece(kit, {
				Size = Vector3.new(thickness, 0.05, 2 * math.pi * radius / segments * (if dashed then 0.7 else 1.04)),
				CFrame = CFrame.lookAt(at, at + tangent),
				Color = color,
				Transparency = transparency,
			}))
		end
	end
	return parts
end

-- A floating code fragment that drifts and fades
local function fragment(kit, position: Vector3, text: string, color: Color3, size: number, life: number, drift: Vector3)
	local anchor = piece(kit, { Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(position) })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(#text * 0.36 * size + 0.3, 0.6 * size)
	gui.LightInfluence = 0
	gui.MaxDistance = 110
	gui.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = MONO
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 1
	label.TextTransparency = 0.05
	label.Parent = gui
	gui.Parent = anchor
	tween(anchor, life, { CFrame = CFrame.new(position + drift) })
	task.delay(life * 0.45, function()
		if label.Parent then
			tween(label, life * 0.55, { TextTransparency = 1 })
		end
	end)
	Debris:AddItem(anchor, life + 0.1)
end

-- A handful of fragments around a point (fewer with reduced effects)
local function fragments(kit, position: Vector3, count: number, spread: number, color: Color3, life: number, rise: number?)
	local total = if kit.Vfx.reduced() then math.min(2, count) else count
	for _ = 1, total do
		local offset = Vector3.new(math.random() - 0.5, math.random() * 0.6, math.random() - 0.5) * spread
		local drift = Vector3.new((math.random() - 0.5) * 1.5, rise or 1.6, (math.random() - 0.5) * 1.5)
		fragment(kit, position + offset, TOKENS[math.random(1, #TOKENS)], color, 0.55 + math.random() * 0.3, life * (0.75 + math.random() * 0.5), drift)
	end
end

-- Small bright square flecks thrown outward (her sparks are square, not round)
local function flecks(kit, position: Vector3, color: Color3, count: number, speed: number)
	kit.Vfx.burst(position, {
		color = color,
		texture = SPARKLE,
		size = NumberSequence.new({ key(0, 0.35), key(1, 0) }),
		transparency = NumberSequence.new({ key(0, 0), key(0.7, 0.3), key(1, 1) }),
		lifetime = NumberRange.new(0.25, 0.6),
		speed = NumberRange.new(speed * 0.4, speed),
		drag = 6,
		count = count,
	})
end

-- A text tag floating over a part, on a dark glass plate with a thin emerald edge.
-- Returns the label (so countdowns can update it).
local function tag(adornee: BasePart, text: string, width: number, height: number, offset: Vector3, color: Color3?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(width, height)
	gui.StudsOffsetWorldSpace = offset
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Adornee = adornee
	local plate = Instance.new("Frame")
	plate.BackgroundColor3 = GLASS
	plate.BackgroundTransparency = 0.3
	plate.BorderSizePixel = 0
	plate.Size = UDim2.fromScale(1, 1)
	plate.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or EMERALD
	stroke.Thickness = 1.5
	stroke.Transparency = 0.1
	stroke.Parent = plate
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 6, 0, 2)
	label.Size = UDim2.new(1, -12, 1, -4)
	label.Font = MONO
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = plate
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 42
	limit.Parent = label
	gui.Parent = adornee
	return label
end

-- An invisible anchor part to hang tags and lights on
local function anchorAt(kit, position: Vector3): BasePart
	return piece(kit, { Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(position) })
end

-- A holographic panel: a sheet of glass with a framed screen (title bar + monospace
-- text). Unfolds from a line. Returns { part, title, body, close(duration) }.
local function panel(kit, cframe: CFrame, width: number, height: number, title: string, body: string)
	local sheet = piece(kit, {
		Size = Vector3.new(width, 0.05, 0.04),
		CFrame = cframe,
		Color = EMERALD,
		Material = Enum.Material.Glass,
		Transparency = 0.9,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Adornee = sheet
	local screen = Instance.new("Frame")
	screen.BackgroundColor3 = GLASS
	screen.BackgroundTransparency = 0.25
	screen.BorderSizePixel = 0
	screen.ClipsDescendants = true
	screen.Size = UDim2.fromScale(1, 1)
	screen.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = EMERALD
	stroke.Thickness = 2
	stroke.Parent = screen
	local header = Instance.new("TextLabel")
	header.BackgroundColor3 = EMERALD
	header.BackgroundTransparency = 0.1
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, 16)
	header.Font = MONO
	header.Text = "  " .. title
	header.TextSize = 12
	header.TextColor3 = INK
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextTruncate = Enum.TextTruncate.AtEnd
	header.Parent = screen
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Position = UDim2.new(0, 8, 0, 20)
	text.Size = UDim2.new(1, -16, 1, -24)
	text.Font = MONO
	text.Text = body
	text.TextSize = 13
	text.TextColor3 = WHITE
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.Parent = screen
	gui.Parent = sheet
	-- Unfold: a line that opens into a screen
	tween(sheet, 0.16, { Size = Vector3.new(width, height, 0.04) })
	local closed = false
	local result = { part = sheet, title = header, body = text }
	function result.close(duration: number)
		if closed or not sheet.Parent then
			return
		end
		closed = true
		tween(sheet, duration, { Size = Vector3.new(width, 0.05, 0.04), Transparency = 1 })
		tween(screen, duration, { BackgroundTransparency = 1 })
		tween(stroke, duration, { Transparency = 1 })
		tween(header, duration, { BackgroundTransparency = 1, TextTransparency = 1 })
		tween(text, duration, { TextTransparency = 1 })
		Debris:AddItem(sheet, duration + 0.05)
	end
	return result
end

-- Corner brackets (a selection marquee) facing the viewer, around `center`
local BRACKET_CORNERS = { { -1, 1 }, { 1, 1 }, { 1, -1 }, { -1, -1 } }
local function makeBrackets(kit, color: Color3, thickness: number): { BasePart }
	local parts = {}
	for _ = 1, 8 do
		table.insert(parts, piece(kit, { Size = Vector3.new(thickness, thickness, 1), Color = color, Transparency = 0.05 }))
	end
	return parts
end

local function placeBrackets(parts: { BasePart }, center: Vector3, width: number, height: number, arm: number, thickness: number)
	local facing = CFrame.lookAt(center, center + flat(cameraPosition() - center))
	for index, corner in BRACKET_CORNERS do
		local x, y = corner[1] * width / 2, corner[2] * height / 2
		local cornerAt = facing * CFrame.new(x, y, 0)
		local across = parts[index * 2 - 1]
		local down = parts[index * 2]
		across.Size = Vector3.new(arm, thickness, thickness)
		across.CFrame = cornerAt * CFrame.new(-corner[1] * arm / 2, 0, 0)
		down.Size = Vector3.new(thickness, arm, thickness)
		down.CFrame = cornerAt * CFrame.new(0, -corner[2] * arm / 2, 0)
	end
end

-- A one-off marquee that snaps in around a point, holds, then opens and fades
local function snapMarquee(kit, center: Vector3, size: number, color: Color3, hold: number)
	local parts = makeBrackets(kit, color, 0.07)
	local stop = animate(hold + 0.5, function(elapsed)
		local snap = math.clamp(elapsed / 0.14, 0, 1)
		local open = math.clamp((elapsed - hold) / 0.35, 0, 1)
		local scale = (2 - snap) + open * 0.6
		placeBrackets(parts, center, size * scale, size * scale, size * 0.3, 0.07)
		if open > 0 then
			for _, part in parts do
				part.Transparency = 0.05 + open * 0.95
			end
		end
		return true
	end)
	task.delay(hold + 0.55, function()
		stop()
		for _, part in parts do
			part:Destroy()
		end
	end)
end

-- The LATTICE sigil: a grid of dots on the ground, lighting in a wave from the centre
local function dotGrid(kit, center: Vector3, spacing: number, count: number, color: Color3, life: number)
	local n = if kit.Vfx.reduced() then math.min(count, 3) else count
	local half = (n - 1) / 2
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			local offset = Vector3.new((i - half) * spacing, 0.07, (j - half) * spacing)
			local delay = offset.Magnitude / math.max(1, spacing * n) * 0.35
			task.delay(delay, function()
				local dot = piece(kit, { Size = Vector3.new(0.32, 0.05, 0.32), CFrame = CFrame.new(center + offset), Color = color, Transparency = 0.15 })
				kit.Vfx.fade(dot, life, { Size = Vector3.new(0.1, 0.05, 0.1) })
			end)
		end
	end
end

-- A small lock-on reticle that follows a model for `duration` with a countdown
local function followReticle(kit, target: Model, duration: number, caption: string, color: Color3)
	local root = rootOf(target)
	if not root then
		return
	end
	local parts = makeBrackets(kit, color, 0.08)
	local diamond = {}
	for _ = 1, 4 do
		table.insert(diamond, piece(kit, { Size = Vector3.new(0.06, 0.06, 1.2), Color = WHITE, Transparency = 0.25 }))
	end
	local anchor = anchorAt(kit, root.Position + Vector3.new(0, 3.6, 0))
	local label = tag(anchor, caption, 3.4, 0.7, Vector3.zero, color)
	local endsAt = kit.now() + duration
	local stopped = false
	local stop
	local function cleanup()
		if stopped then
			return
		end
		stopped = true
		stop()
		-- Opens wide and fades: released
		for _, part in parts do
			retire(kit, part, 0.3)
		end
		retireAll(kit, diamond, 0.2)
		anchor:Destroy()
	end
	stop = animate(duration + 0.2, function(elapsed)
		if not root.Parent then
			cleanup()
			return false
		end
		local center = root.Position + Vector3.new(0, 0.4, 0)
		local snap = math.clamp(elapsed / 0.16, 0, 1)
		local breathe = 1 + math.sin(elapsed * 5) * 0.03
		local scale = (2.2 - snap * 1.2) * breathe
		placeBrackets(parts, center, 3.4 * scale, 5.4 * scale, 0.9, 0.08)
		-- A thin diamond turning around the chest
		local spin = CFrame.lookAt(center, center + flat(cameraPosition() - center)) * CFrame.Angles(0, 0, elapsed * 1.6)
		for index, part in diamond do
			local turn = spin * CFrame.Angles(0, 0, index * math.pi / 2)
			part.CFrame = turn * CFrame.new(0.55, 0.55, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, 0) * CFrame.Angles(math.rad(45), 0, 0)
		end
		anchor.CFrame = CFrame.new(root.Position + Vector3.new(0, 3.6, 0))
		label.Text = string.format("%s %.1f", caption, math.max(0, endsAt - kit.now()))
		return true
	end)
	kit.keep(cleanup)
	task.delay(duration + 0.1, cleanup)
end

-- Poses -----------------------------------------------------------------------------------

local Poser = require(script.Parent.Parent.Effects.Poser)

-- Right arm out, aiming; left hand near the chest as if on a panel
Poser.register("SyntaxPoint", { RightShoulder = { 88, 0, 4 }, RightElbow = { 6, 0, 0 }, LeftShoulder = { 38, 0, -28 }, LeftElbow = { 85, 0, 0 }, Torso = { 0, -14, 0 }, Neck = { 0, 10, 0 } })
-- Both forearms up at chest height, fingers on an invisible keyboard
Poser.register("SyntaxType", { RightShoulder = { 46, 0, 14 }, RightElbow = { 72, 0, 0 }, LeftShoulder = { 46, 0, -14 }, LeftElbow = { 72, 0, 0 }, Neck = { -14, 0, 0 }, Torso = { 5, 0, 0 } })
-- The pen drawn back across the body, then the stroke out
Poser.register("SyntaxDrawBack", { RightShoulder = { 70, 0, -62 }, RightElbow = { 40, 0, 0 }, Torso = { 0, 24, 0 }, LeftShoulder = { 20, 0, -20 } })
Poser.register("SyntaxStroke", { RightShoulder = { 82, 0, 48 }, RightElbow = { 4, 0, 0 }, Torso = { 0, -26, 0 }, LeftShoulder = { 25, 0, -30 } })
-- Left palm out: a screen held up
Poser.register("SyntaxGuard", { LeftShoulder = { 92, 0, 12 }, LeftElbow = { 28, 0, 0 }, RightShoulder = { 30, 0, 24 }, RightElbow = { 50, 0, 0 }, Torso = { 0, 12, 0 } })
-- Arms raised and open: taking the system
Poser.register("SyntaxRaise", { RightShoulder = { 150, 0, 32 }, LeftShoulder = { 150, 0, -32 }, RightElbow = { 12, 0, 0 }, LeftElbow = { 12, 0, 0 }, Torso = { -8, 0, 0 }, Neck = { -22, 0, 0 } })
-- Both hands brought down: execute
Poser.register("SyntaxExecute", { RightShoulder = { 70, 0, 18 }, LeftShoulder = { 70, 0, -18 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, Torso = { 14, 0, 0 }, Neck = { 10, 0, 0 } })

-- Keyframed versions where the animation engine supports them (anticipation, strike, follow-through)
local SEQUENCES = Poser.registerSequence ~= nil and Poser.sequence ~= nil
if SEQUENCES then
	Poser.registerSequence("SyntaxStrikeSeq", {
		{ 0, { RightShoulder = { 60, 0, -40 }, RightElbow = { 50, 0, 0 }, Torso = { 0, 14, 0 } }, "Out" },
		{ 0.42, { RightShoulder = { 72, 0, -66 }, RightElbow = { 36, 0, 0 }, Torso = { 0, 26, 0 }, LeftShoulder = { 20, 0, -20 } }, "InOut" },
		{ 0.56, { RightShoulder = { 84, 0, 52 }, RightElbow = { 2, 0, 0 }, Torso = { 0, -28, 0 }, LeftShoulder = { 25, 0, -30 } }, "Snap" },
		{ 0.86, { RightShoulder = { 70, 0, 40 }, RightElbow = { 10, 0, 0 }, Torso = { 0, -18, 0 } }, "Out" },
	}, { startup = 0.5, active = 0.06, recovery = 0.3, upper = true })
	Poser.registerSequence("SyntaxOverrideSeq", {
		{ 0, { RightShoulder = { 60, 0, 20 }, LeftShoulder = { 60, 0, -20 }, RightElbow = { 60, 0, 0 }, LeftElbow = { 60, 0, 0 }, Neck = { -10, 0, 0 } }, "Out" },
		{ 1.1, { RightShoulder = { 152, 0, 34 }, LeftShoulder = { 152, 0, -34 }, RightElbow = { 10, 0, 0 }, LeftElbow = { 10, 0, 0 }, Torso = { -10, 0, 0 }, Neck = { -24, 0, 0 } }, "InOut" },
		{ 1.3, { RightShoulder = { 160, 0, 36 }, LeftShoulder = { 160, 0, -36 }, Torso = { -12, 0, 0 }, Neck = { -26, 0, 0 } }, "Linear" },
		{ 1.42, { RightShoulder = { 66, 0, 16 }, LeftShoulder = { 66, 0, -16 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, Torso = { 16, 0, 0 }, Neck = { 12, 0, 0 } }, "Snap" },
		{ 2.2, { RightShoulder = { 40, 0, 10 }, LeftShoulder = { 40, 0, -10 }, Torso = { 6, 0, 0 } }, "Out" },
	}, { startup = 1.3, active = 0.2, recovery = 0.8 })
end

local function pose(kit, name: string, inTime: number, hold: number, outTime: number)
	local model = kit.model
	if model and model.Parent then
		kit.Poser.play(model, name, inTime, hold, outTime)
	end
end

-- A keyframed move when available, timed to the real phases; otherwise the pose pair
local function sequenceOr(kit, name: string, fallback: { { any } }, timing: { number }?)
	local model = kit.model
	if not model or not model.Parent then
		return
	end
	if SEQUENCES and Poser.Sequences and Poser.Sequences[name] then
		kit.Poser.sequence(model, name, 1, if timing then { timing = timing } else nil)
		return
	end
	for _, step in fallback do
		if step[2] <= 0 then
			pose(kit, step[1], step[3], step[4], step[5])
		else
			task.delay(step[2], pose, kit, step[1], step[3], step[4], step[5])
		end
	end
end

-- A small "compile" flash at her hand: a bracket and a fleck of light
local function compile(kit, size: number)
	if not kit.root then
		return
	end
	local at = hand(kit)
	local look = kit.root.CFrame.LookVector
	square(kit, CFrame.lookAt(at, at + look), 0.25 * size, 0.05, WHITE, 0.18, 0.6 * size)
	kit.Vfx.glow(at, EMERALD, 6 * size, 1.5, 0.15)
end

local function windup(kit, name: string, startup: number)
	pose(kit, name, math.min(0.12, startup * 0.5 + 0.04), math.max(0.08, startup), 0.2)
end

Syntax.predict = {
	Keystroke = function(kit)
		pose(kit, "SyntaxPoint", 0.05, 0.12, 0.15)
	end,
	Strikethrough = function(kit)
		local startup = num(kit.data.startup, 0.5)
		sequenceOr(kit, "SyntaxStrikeSeq", { { "SyntaxDrawBack", 0, 0.12, math.max(0.05, startup - 0.12), 0.05 }, { "SyntaxStroke", startup, 0.05, 0.2, 0.25 } }, { startup, num(kit.data.active, 0.06), 0.3 })
	end,
	TargetLock = function(kit)
		windup(kit, "SyntaxPoint", num(kit.data.startup, 0.12))
	end,
	CodeBolt = function(kit)
		windup(kit, "SyntaxPoint", num(kit.data.startup, 0.2))
		compile(kit, 1)
	end,
	HoloBarrier = function(kit)
		windup(kit, "SyntaxGuard", num(kit.data.startup, 0.15))
	end,
	PacketReroute = function(kit)
		windup(kit, "SyntaxGuard", 0.4)
	end,
	Interface = function(kit)
		windup(kit, "SyntaxType", num(kit.data.startup, 0.4))
	end,
	CommandZone = function(kit)
		windup(kit, "SyntaxType", num(kit.data.startup, 0.3))
	end,
	ConfinementField = function(kit)
		windup(kit, "SyntaxPoint", num(kit.data.startup, 0.45))
	end,
	ObjectOverride = function(kit)
		windup(kit, "SyntaxType", num(kit.data.startup, 0.35))
	end,
	ExecuteChain = function(kit)
		windup(kit, "SyntaxType", num(kit.data.startup, 0.3) + 0.9)
	end,
	RuleRewrite = function(kit)
		windup(kit, "SyntaxRaise", num(kit.data.startup, 0.45))
	end,
	Reconstruct = function(kit)
		windup(kit, "SyntaxGuard", num(kit.data.startup, 0.3))
	end,
	MovementOverride = function(kit)
		windup(kit, "SyntaxStroke", num(kit.data.startup, 0.35))
	end,
	SystemOverride = function(kit)
		local startup = num(kit.data.startup, 1.3)
		sequenceOr(kit, "SyntaxOverrideSeq", { { "SyntaxRaise", 0, 0.3, math.max(0.1, startup - 0.3), 0.05 }, { "SyntaxExecute", startup, 0.06, 0.4, 0.4 } }, { startup, num(kit.data.active, 0.2), 0.8 })
	end,
}

-- Other players see the same wind-ups (the local player already predicted theirs)
function Syntax.onCast(kit)
	local ability = kit.data.ability
	local predict = typeof(ability) == "string" and Syntax.predict[ability]
	if predict then
		predict(kit)
	end
end

-- Target Lock ---------------------------------------------------------------------------------

function fx.Lock(kit)
	local target = modelOf(kit.data.target)
	local root = rootOf(target)
	if not target or not root then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 5), 0.5, 10)
	-- A thin cursor line from her hand (or the pinned point) to the target
	local from = vec(kit.data.from) or hand(kit)
	kit.Vfx.beam(from, root.Position, WHITE, 0.05, 0.3)
	followReticle(kit, target, duration, "LOCK", EMERALD)
	flecks(kit, root.Position, WHITE, 8, 10)
	kit.Vfx.sound("Parry", root.Position)
end

function fx.Reveal(kit)
	local target = modelOf(kit.data.target)
	local root = rootOf(target)
	if not root then
		return
	end
	-- A scanline runs down the body: whatever was hidden is drawn again
	local top = root.Position + Vector3.new(0, 3, 0)
	local plane = piece(kit, { Size = Vector3.new(4.4, 0.05, 2.6), CFrame = CFrame.new(top), Color = WHITE, Transparency = 0.2 })
	kit.Vfx.fade(plane, 0.35, { CFrame = CFrame.new(root.Position - Vector3.new(0, 3, 0)) })
	snapMarquee(kit, root.Position, 4, WHITE, 0.4)
	fragment(kit, root.Position + Vector3.new(0, 3.2, 0), "visible = true", WHITE, 0.8, 1, Vector3.new(0, 1, 0))
end

function fx.Pin(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 4.5), 1, 10)
	local parts = {}
	-- A surveyor's mark: crosshair, square and a thin post with its coordinates
	table.insert(parts, bar(kit, position + Vector3.new(-radius, 0.08, 0), position + Vector3.new(radius, 0.08, 0), 0.06, WHITE, 0.2))
	table.insert(parts, bar(kit, position + Vector3.new(0, 0.08, -radius), position + Vector3.new(0, 0.08, radius), 0.06, WHITE, 0.2))
	table.insert(parts, bar(kit, position, position + Vector3.new(0, 3, 0), 0.05, EMERALD, 0.15))
	local frame = {}
	for _ = 1, 4 do
		table.insert(frame, piece(kit, { Size = Vector3.new(radius * 0.7, 0.05, 0.07), Color = EMERALD, Transparency = 0.15 }))
	end
	local anchor = anchorAt(kit, position + Vector3.new(0, 3.5, 0))
	tag(anchor, string.format("PIN %.0f, %.0f", position.X, position.Z), 3.6, 0.6, Vector3.zero)
	groundSquare(kit, position, radius * 0.2, WHITE, 0.3, radius)
	local stop = animate(num(kit.data.duration, 6) + 0.2, function(elapsed)
		local spin = CFrame.new(position + Vector3.new(0, 0.09, 0)) * CFrame.Angles(0, elapsed * 0.6, 0)
		for index, part in frame do
			-- Four corner ticks of a slowly turning square
			local turn = spin * CFrame.Angles(0, index * math.pi / 2, 0)
			part.CFrame = turn * CFrame.new(0, 0, -radius) * CFrame.new(radius * 0.65, 0, 0)
		end
		return true
	end)
	kit.keep(function()
		stop()
		retireAll(kit, parts, 0.25)
		retireAll(kit, frame, 0.25)
		anchor:Destroy()
	end)
end

-- Strikethrough ------------------------------------------------------------------------------

local strikeMarks: { [Instance]: () -> () } = setmetatable({}, { __mode = "k" }) :: any

function fx.StrikeMark(kit)
	local origin, direction = vec(kit.data.origin), vec(kit.data.direction)
	if not origin or not direction then
		return
	end
	local dir = flat(direction)
	local length = math.clamp(num(kit.data.length, 60), 1, 90)
	local width = math.clamp(num(kit.data.width, 2.6), 0.5, 6)
	local duration = math.clamp(num(kit.data.duration, 0.5), 0.1, 2)
	local floor = origin - Vector3.new(0, 2.85, 0)
	local side = dir:Cross(Vector3.yAxis)
	-- The pen stroke: a white core with two faint edges marking the width
	local core = piece(kit, { Size = Vector3.new(0.08, 0.05, 0.05), Color = WHITE, Transparency = 0.05 })
	local edges = {
		piece(kit, { Size = Vector3.new(0.05, 0.05, 0.05), Color = EMERALD, Transparency = 0.45 }),
		piece(kit, { Size = Vector3.new(0.05, 0.05, 0.05), Color = EMERALD, Transparency = 0.45 }),
	}
	local nib = piece(kit, { Size = Vector3.new(0.3, 0.3, 0.3), Color = WHITE, Transparency = 0 })
	local ticks = {}
	local endAnchor = anchorAt(kit, floor + dir * length + Vector3.new(0, 2.2, 0))
	local label = tag(endAnchor, "strike()", 2.6, 0.55, Vector3.zero)
	local stopped = false
	local stop
	local function cleanup(fast: boolean?)
		if stopped then
			return
		end
		stopped = true
		stop()
		local time = if fast then 0.12 else 0.2
		retire(kit, core, time)
		retireAll(kit, edges, time)
		retire(kit, nib, 0.1)
		retireAll(kit, ticks, time)
		endAnchor:Destroy()
	end
	stop = animate(duration + 0.3, function(elapsed)
		-- Drawn in the first third of the wind-up, then it brightens toward the delete
		local drawn = math.clamp(elapsed / (duration * 0.35), 0, 1)
		local reach = length * drawn
		local a, b = floor + Vector3.new(0, 0.1, 0), floor + dir * reach + Vector3.new(0, 0.1, 0)
		placeBar(core, a, b, 0.08)
		placeBar(edges[1], a + side * width / 2, b + side * width / 2, 0.05)
		placeBar(edges[2], a - side * width / 2, b - side * width / 2, 0.05)
		nib.CFrame = CFrame.new(b + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, elapsed * 8, math.rad(45))
		-- Tick marks every 4 studs as the pen passes them
		while #ticks < math.floor(reach / 4) and #ticks < 22 do
			local at = floor + dir * ((#ticks + 1) * 4) + Vector3.new(0, 0.1, 0)
			table.insert(ticks, bar(kit, at - side * 0.35, at + side * 0.35, 0.05, EMERALD, 0.3) :: BasePart)
		end
		local heat = math.clamp((elapsed - duration * 0.5) / (duration * 0.5), 0, 1)
		core.Size = Vector3.new(0.08 + heat * 0.12, 0.05 + heat * 0.05, core.Size.Z)
		for _, edge in edges do
			edge.Transparency = 0.45 - heat * 0.3
		end
		label.TextColor3 = WHITE:Lerp(EMERALD, heat)
		return true
	end)
	if kit.model then
		strikeMarks[kit.model] = cleanup
	end
	task.delay(duration + 0.15, cleanup)
end

function fx.StrikeCancel(kit)
	local cleanup = kit.model and strikeMarks[kit.model]
	if cleanup then
		strikeMarks[kit.model] = nil
		cleanup(true)
	end
end

function fx.Strike(kit)
	local origin, direction = vec(kit.data.origin), vec(kit.data.direction)
	if not origin or not direction then
		return
	end
	local dir = flat(direction)
	local length = math.clamp(num(kit.data.length, 60), 1, 90)
	local width = math.clamp(num(kit.data.width, 2.6), 0.5, 6)
	local from = origin + Vector3.new(0, 0.3, 0)
	local to = from + dir * length
	-- Impact: a bright deleting bar along the whole line, thinning to nothing
	local slash = piece(kit, { Size = Vector3.new(width * 0.5, 0.18, length), CFrame = CFrame.lookAt((from + to) / 2, to), Color = WHITE, Transparency = 0 })
	kit.Vfx.fade(slash, 0.3, { Size = Vector3.new(0.04, 0.04, length) })
	local glow = piece(kit, { Size = Vector3.new(width, 0.5, length), CFrame = CFrame.lookAt((from + to) / 2, to), Color = EMERALD, Material = Enum.Material.ForceField, Transparency = 0.3 })
	kit.Vfx.fade(glow, 0.4, { Size = Vector3.new(width * 0.2, 0.1, length) })
	-- Dissipation: the line is erased from the start, leaving deleted characters
	local steps = if kit.Vfx.reduced() then 3 else 7
	for index = 1, steps do
		local at = from:Lerp(to, (index - 0.5) / steps)
		task.delay(index * 0.03, function()
			flecks(kit, at, if index % 2 == 0 then WHITE else EMERALD, 5, 12)
			if index % 2 == 1 then
				fragment(kit, at + Vector3.new(0, 0.5, 0), "del", EMERALD, 0.6, 0.7, Vector3.new(0, 1.2, 0))
			end
		end)
	end
	local scar = bar(kit, origin - Vector3.new(0, 2.8, 0), origin - Vector3.new(0, 2.8, 0) + dir * length, 0.12, EMERALD, 0.2)
	retire(kit, scar, 0.9)
	kit.Vfx.glow(from + dir * math.min(length, 6), WHITE, 14, 2.5, 0.15)
	kit.Vfx.sound("HeavySwing", from)
	kit.shake(0.7, 0.15, from)
	if kit.model then
		pose(kit, "SyntaxStroke", 0.04, 0.15, 0.3)
	end
end

-- Holo Barrier, walls, sentries --------------------------------------------------------------

function fx.Barrier(kit)
	local frame = frameOf(kit.data.cframe)
	if not frame then
		return
	end
	local width = math.clamp(num(kit.data.width, 10), 1, 30)
	local height = math.clamp(num(kit.data.height, 7), 1, 20)
	local wall = kit.data.wall == true
	local restored = kit.data.restored == true
	local duration = math.clamp(num(kit.data.duration, 3), 0.2, 12)
	local endsAt = kit.now() + duration
	local base = frame * CFrame.new(0, -height / 2, 0)
	local edge = if restored then WHITE else EMERALD
	local parts = {}
	-- Frame: four crisp edges
	local corners = {
		frame * CFrame.new(-width / 2, -height / 2, 0),
		frame * CFrame.new(width / 2, -height / 2, 0),
		frame * CFrame.new(width / 2, height / 2, 0),
		frame * CFrame.new(-width / 2, height / 2, 0),
	}
	for index = 1, 4 do
		local a, b = corners[index].Position, corners[index % 4 + 1].Position
		table.insert(parts, bar(kit, a, b, if wall then 0.16 else 0.1, edge, 0.05) :: BasePart)
	end
	-- Inner grid: verticals rise out of the floor, then the horizontals light
	local verticals = {}
	local spacing = if kit.Vfx.reduced() then 3 else 2
	local columns = math.max(1, math.floor(width / spacing))
	for index = 1, columns - 1 do
		local x = -width / 2 + index * width / columns
		local line = piece(kit, { Size = Vector3.new(0.05, 0.05, 0.05), CFrame = base * CFrame.new(x, 0, 0), Color = EMERALD, Transparency = 0.5 })
		table.insert(verticals, { part = line, x = x })
		table.insert(parts, line)
	end
	local rows = math.max(1, math.floor(height / spacing))
	for index = 1, rows - 1 do
		local y = -height / 2 + index * height / rows
		local line = bar(kit, (frame * CFrame.new(-width / 2, y, 0)).Position, (frame * CFrame.new(width / 2, y, 0)).Position, 0.04, TEAL, 0.65)
		if line then
			line.Transparency = 1
			task.delay(0.2 + index * 0.03, function()
				if line.Parent then
					tween(line, 0.15, { Transparency = 0.65 })
				end
			end)
			table.insert(parts, line)
		end
	end
	local anchor = anchorAt(kit, (frame * CFrame.new(0, height / 2 + 0.9, 0)).Position)
	local name = if wall then "firewall" elseif restored then "barrier (restored)" else "barrier.hold()"
	local label = tag(anchor, name, 4.2, 0.65, Vector3.zero, edge)
	flecks(kit, base.Position, EMERALD, 10, 14)
	kit.Vfx.glow(frame.Position, EMERALD, width, 1.2, 0.25)
	kit.Vfx.sound("Block", frame.Position)
	local stop = animate(duration + 0.2, function(elapsed)
		local rise = math.clamp(elapsed / 0.2, 0, 1)
		for _, entry in verticals do
			local bottom = (base * CFrame.new(entry.x, 0, 0)).Position
			local top = (base * CFrame.new(entry.x, height * rise, 0)).Position
			placeBar(entry.part, bottom, top, 0.05)
		end
		label.Text = string.format("%s  %.1fs", name, math.max(0, endsAt - kit.now()))
		return true
	end)
	kit.keep(function()
		stop()
		-- Collapses back into the floor
		for _, part in parts do
			retire(kit, part, 0.25, { CFrame = part.CFrame * CFrame.new(0, -0.6, 0) })
		end
		anchor:Destroy()
	end)
end

function fx.BarrierEnd(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local width = math.clamp(num(kit.data.width, 10), 1, 30)
	local height = math.clamp(num(kit.data.height, 7), 1, 20)
	if kit.data.reason == "Broken" then
		-- Shattered: square shards fly off and the integrity readout hits zero
		local count = if kit.Vfx.reduced() then 4 else 10
		for _ = 1, count do
			local offset = Vector3.new((math.random() - 0.5) * width, (math.random() - 0.5) * height, 0)
			local shard = piece(kit, { Size = Vector3.new(0.5, 0.5, 0.05), CFrame = CFrame.new(position + offset) * CFrame.Angles(math.random() * 3, math.random() * 3, 0), Color = if math.random() < 0.5 then WHITE else EMERALD, Transparency = 0.1 })
			kit.Vfx.fade(shard, 0.5, { CFrame = shard.CFrame + offset.Unit * 3 + Vector3.new(0, -1, 0), Size = Vector3.new(0.1, 0.1, 0.05) })
		end
		fragment(kit, position + Vector3.new(0, height / 2 + 0.6, 0), "integrity 0", WHITE, 0.8, 1, Vector3.new(0, 1, 0))
		kit.Vfx.glow(position, WHITE, width, 2, 0.15)
		kit.Vfx.sound("GuardBreak", position)
	else
		fragments(kit, position, 3, width * 0.4, EMERALD, 0.9, 1.2)
	end
end

function fx.Sentry(kit)
	local head = vec(kit.data.position)
	if not head then
		return
	end
	local link = vec(kit.data.link)
	local restored = kit.data.restored == true
	local duration = math.clamp(num(kit.data.duration, 5), 0.2, 12)
	local endsAt = kit.now() + duration
	local parts = {}
	-- A wireframe cube turning around the head, with a white core
	local edges = {}
	for _ = 1, 12 do
		local edgePart = piece(kit, { Size = Vector3.new(0.07, 0.07, 2.4), Color = if restored then WHITE else EMERALD, Transparency = 0.05 })
		table.insert(edges, edgePart)
		table.insert(parts, edgePart)
	end
	local core = piece(kit, { Size = Vector3.new(0.6, 0.6, 0.6), CFrame = CFrame.new(head), Color = WHITE, Transparency = 0 })
	table.insert(parts, core)
	local light = Instance.new("PointLight")
	light.Color = EMERALD
	light.Range = 10
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = core
	local linkBar = if link then bar(kit, link, head, 0.06, EMERALD, 0.3) else nil
	if linkBar then
		table.insert(parts, linkBar)
	end
	local anchor = anchorAt(kit, head + Vector3.new(0, 2.4, 0))
	local name = if link then "override > sentry" else "sentry.new()"
	local label = tag(anchor, name, 3.8, 0.6, Vector3.zero)
	local cubeEdges = {}
	for _, axis in { "x", "y", "z" } do
		for _, a in { -1, 1 } do
			for _, b in { -1, 1 } do
				table.insert(cubeEdges, { axis = axis, a = a, b = b })
			end
		end
	end
	flecks(kit, head, EMERALD, 10, 12)
	local stop = animate(duration + 0.2, function(elapsed)
		local unfold = math.clamp(elapsed / 0.2, 0, 1)
		local half = 1.2 * unfold
		local spin = CFrame.new(head) * CFrame.Angles(0, elapsed * 1.2, 0) * CFrame.Angles(math.rad(35), 0, math.rad(45))
		for index, spec in cubeEdges do
			local offset
			if spec.axis == "x" then
				offset = CFrame.new(0, spec.a * half, spec.b * half) * FORWARD
			elseif spec.axis == "y" then
				offset = CFrame.new(spec.a * half, 0, spec.b * half) * CFrame.Angles(math.rad(90), 0, 0)
			else
				offset = CFrame.new(spec.a * half, spec.b * half, 0)
			end
			local edgePart = edges[index]
			edgePart.Size = Vector3.new(0.07, 0.07, math.max(0.05, half * 2))
			edgePart.CFrame = spin * offset
		end
		core.CFrame = CFrame.new(head) * CFrame.Angles(elapsed * 2, elapsed * 3, 0)
		label.Text = string.format("%s  %.1fs", name, math.max(0, endsAt - kit.now()))
		return true
	end)
	kit.keep(function()
		stop()
		retireAll(kit, parts, 0.25)
		anchor:Destroy()
	end)
end

function fx.SentryEnd(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	if kit.data.reason == "Broken" then
		square(kit, CFrame.lookAt(position, cameraPosition()), 0.6, 0.08, WHITE, 0.3, 2.4)
		flecks(kit, position, WHITE, 14, 18)
		kit.Vfx.sound("GuardBreak", position)
	end
	fragments(kit, position, 2, 1.5, EMERALD, 0.8, 1)
end

-- Packet Reroute ------------------------------------------------------------------------------

function fx.RerouteOpen(kit)
	local root = kit.root
	if not root then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 13), 2, 20)
	local duration = math.clamp(num(kit.data.duration, 0.65), 0.1, 2)
	-- A square of firewall light around her, turning, with arrows riding its edges
	local frame = {}
	for _ = 1, 4 do
		table.insert(frame, piece(kit, { Size = Vector3.new(0.06, 0.06, radius * 1.4), Color = EMERALD, Transparency = 0.25 }))
	end
	local arrows = {}
	for index = 1, 4 do
		local anchor = anchorAt(kit, root.Position)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromScale(1.6, 0.8)
		gui.LightInfluence = 0
		gui.Adornee = anchor
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Font = MONO
		text.Text = if index % 2 == 0 then "<-" else "->"
		text.TextScaled = true
		text.TextColor3 = WHITE
		text.Parent = gui
		gui.Parent = anchor
		table.insert(arrows, anchor)
	end
	pose(kit, "SyntaxGuard", 0.06, duration, 0.2)
	local stop = animate(duration + 0.1, function(elapsed)
		local open = math.clamp(elapsed / 0.12, 0, 1)
		local size = radius * 0.7 * (0.4 + open * 0.6)
		local center = root.Position
		local spin = CFrame.new(center) * CFrame.Angles(0, elapsed * 2.4, 0)
		for index, part in frame do
			local turn = spin * CFrame.Angles(0, index * math.pi / 2, 0)
			part.Size = Vector3.new(0.06, 0.06, size * 2)
			part.CFrame = turn * CFrame.new(size, 0, 0)
		end
		for index, anchor in arrows do
			local turn = spin * CFrame.Angles(0, index * math.pi / 2 + elapsed * 1.5, 0)
			anchor.CFrame = turn * CFrame.new(size, 0.6, 0)
		end
		return true
	end)
	task.delay(duration, function()
		stop()
		retireAll(kit, frame, 0.2)
		for _, anchor in arrows do
			anchor:Destroy()
		end
	end)
end

-- One projectile taken over: a marquee snaps onto it and a dashed route draws back to its sender
local function rerouted(kit, from: Vector3, to: Vector3?)
	snapMarquee(kit, from, 2, WHITE, 0.25)
	flecks(kit, from, EMERALD, 10, 14)
	kit.Vfx.glow(from, WHITE, 8, 2, 0.15)
	if to then
		local count = math.clamp(math.floor((to - from).Magnitude / 3), 2, 10)
		for index = 0, count - 1, 2 do
			local a = from:Lerp(to, index / count)
			local b = from:Lerp(to, (index + 1) / count)
			task.delay(index * 0.02, function()
				kit.Vfx.beam(a, b, EMERALD, 0.05, 0.45)
			end)
		end
	end
	fragment(kit, from + Vector3.new(0, 1.2, 0), "dst = src", WHITE, 0.75, 0.9, Vector3.new(0, 1, 0))
	kit.Vfx.sound("Parry", from)
end

function fx.Reroute(kit)
	local from = vec(kit.data.from)
	if from then
		rerouted(kit, from, vec(kit.data.to))
	end
end

-- The passive Redirect prompt succeeded (PowerService.commitRedirect)
function fx.PacketReroute(kit)
	if not kit.root then
		return
	end
	pose(kit, "SyntaxGuard", 0.04, 0.2, 0.25)
	local at = hand(kit)
	square(kit, CFrame.lookAt(at, cameraPosition()), 0.3, 0.05, WHITE, 0.25, 1.6)
	kit.Vfx.glow(at, EMERALD, 10, 2, 0.2)
	fragment(kit, at + Vector3.new(0, 1, 0), "reroute ok", EMERALD, 0.75, 0.9, Vector3.new(0, 1, 0))
end

function fx.RerouteMiss(kit)
	if kit.root then
		fragment(kit, kit.root.Position + Vector3.new(0, 3, 0), "0 packets", TEAL, 0.7, 0.8, Vector3.new(0, 0.8, 0))
	end
end

-- Interface and Object Override ---------------------------------------------------------------

local INTERFACE_LABELS = {
	Pylon = "PYLON > discharge()",
	Node = "NODE > pulse(slow)",
	Vent = "VENT > purge()",
	Spawn = "node.new()",
}
local OVERRIDE_LABELS = {
	Pylon = "PYLON > override(sentry)",
	Node = "NODE > override(sentry)",
	Vent = "VENT > override(wall)",
	Spawn = "sentry.new()",
}

function fx.InterfaceLink(kit)
	local from, to = vec(kit.data.from), vec(kit.data.to)
	if not from or not to then
		return
	end
	local kind = if typeof(kit.data.kind) == "string" then kit.data.kind else "Spawn"
	local labels = if kit.data.override then OVERRIDE_LABELS else INTERFACE_LABELS
	local text = labels[kind] or labels.Spawn
	local duration = math.clamp(num(kit.data.duration, 0.4), 0.1, 2)
	-- The cursor travels out along a thin line, then a marquee selects the object
	local line = piece(kit, { Size = Vector3.new(0.05, 0.05, 0.05), Color = WHITE, Transparency = 0.15 })
	local cursor = piece(kit, { Size = Vector3.new(0.35, 0.35, 0.05), Color = WHITE, Transparency = 0 })
	local anchor = anchorAt(kit, to + Vector3.new(0, 3.2, 0))
	local label = tag(anchor, text, #text * 0.2 + 1, 0.6, Vector3.zero)
	label.TextTransparency = 1
	local selected = false
	local stop = animate(duration + 0.3, function(elapsed)
		local travel = math.clamp(elapsed / 0.2, 0, 1)
		local head = from:Lerp(to, travel)
		placeBar(line, from, head, 0.05)
		cursor.CFrame = CFrame.lookAt(head, cameraPosition()) * CFrame.Angles(0, 0, math.rad(45))
		if travel >= 1 and not selected then
			selected = true
			snapMarquee(kit, to, 3.4, EMERALD, math.max(0.2, duration - 0.2))
			tween(label, 0.12, { TextTransparency = 0 })
			flecks(kit, to, EMERALD, 8, 10)
		end
		return true
	end)
	task.delay(duration + 0.1, function()
		stop()
		retire(kit, line, 0.2)
		retire(kit, cursor, 0.15)
		anchor:Destroy()
	end)
	kit.Vfx.sound("LightSwing", from)
end

-- A data node, or an arena node taken over: a floating diamond pulsing over a ring
local function nodeLook(kit, title: string)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 10), 1, 24)
	local duration = math.clamp(num(kit.data.duration, 3), 0.2, 10)
	local endsAt = kit.now() + duration
	local ring = circle(kit, position, radius, EMERALD, 0.08, 0.45, true)
	local diamond = piece(kit, { Size = Vector3.new(0.9, 0.9, 0.9), Color = WHITE, Transparency = 0.05 })
	local shell = piece(kit, { Size = Vector3.new(1.6, 1.6, 1.6), Color = EMERALD, Material = Enum.Material.ForceField, Transparency = 0.2 })
	local anchor = anchorAt(kit, position + Vector3.new(0, 3.6, 0))
	local label = tag(anchor, title, 4, 0.6, Vector3.zero)
	local stop = animate(duration + 0.2, function(elapsed)
		local bob = math.sin(elapsed * 2.2) * 0.15
		local frame = CFrame.new(position + Vector3.new(0, 1.6 + bob, 0)) * CFrame.Angles(0, elapsed * 1.4, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45))
		diamond.CFrame = frame
		shell.CFrame = frame * CFrame.Angles(0, elapsed * -2, 0)
		label.Text = string.format("%s  %.1fs", title, math.max(0, endsAt - kit.now()))
		return true
	end)
	kit.keep(function()
		stop()
		retireAll(kit, ring, 0.3)
		retire(kit, diamond, 0.2)
		retire(kit, shell, 0.2)
		anchor:Destroy()
	end)
end

function fx.DataNode(kit)
	nodeLook(kit, "node.pulse(slow)")
end

function fx.NodeOverride(kit)
	nodeLook(kit, "NODE > pulse(slow)")
end

function fx.Pulse(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 10), 1, 24)
	-- A square ripple out to the edge, and a soft flash of the dot grid
	groundSquare(kit, position, 0.6, WHITE, 0.45, radius * 0.72, math.random() * math.pi)
	groundSquare(kit, position, 0.4, EMERALD, 0.6, radius * 0.6, math.random() * math.pi)
	kit.Vfx.glow(position + Vector3.new(0, 1.5, 0), EMERALD, radius * 1.2, 1.2, 0.3)
	kit.Vfx.sound("Dodge", position)
end

function fx.PylonCharge(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 0.4), 0.1, 2)
	-- Rings close in on the pylon while thin aim lines settle on its targets
	for index = 1, 3 do
		task.delay((index - 1) * duration * 0.25, function()
			square(kit, CFrame.lookAt(position, cameraPosition()), 2.6, 0.06, EMERALD, duration * 0.6, 0.3)
		end)
	end
	if typeof(kit.data.targets) == "table" then
		for _, model in kit.data.targets do
			local root = rootOf(modelOf(model))
			if root then
				local line = bar(kit, position, root.Position, 0.04, WHITE, 0.4)
				retire(kit, line, duration)
			end
		end
	end
	kit.Vfx.glow(position, EMERALD, 14, 1, duration)
end

function fx.PylonFire(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	if typeof(kit.data.targets) == "table" then
		for _, at in kit.data.targets do
			local point = vec(at)
			if point then
				-- A precise beam: white core inside an emerald sleeve, thinning out
				kit.Vfx.beam(position, point, WHITE, 0.22, 0.25)
				kit.Vfx.beam(position, point, EMERALD, 0.6, 0.35, Enum.Material.ForceField)
				square(kit, CFrame.lookAt(point, cameraPosition()), 0.5, 0.08, WHITE, 0.3, 2.2)
				flecks(kit, point, EMERALD, 10, 16)
			end
		end
	end
	kit.Vfx.glow(position, WHITE, 18, 3, 0.15)
	kit.Vfx.sound("Hit", position)
	kit.shake(0.8, 0.15, position)
end

function fx.VentCharge(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 8), 1, 20)
	local duration = math.clamp(num(kit.data.duration, 0.4), 0.1, 2)
	local ring = circle(kit, position, radius, WHITE, 0.08, 0.3)
	local anchor = anchorAt(kit, position + Vector3.new(0, 4, 0))
	tag(anchor, "VENT > purge()", 3.6, 0.6, Vector3.zero)
	groundSquare(kit, position, radius, EMERALD, duration, 0.5)
	task.delay(duration, function()
		retireAll(kit, ring, 0.15)
		anchor:Destroy()
	end)
end

function fx.VentBlast(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 8), 1, 20)
	-- A column of streaks shooting up, a ring out across the floor
	local streaks = if kit.Vfx.reduced() then 4 else 10
	for _ = 1, streaks do
		local offset = Vector3.new((math.random() - 0.5) * radius, 0, (math.random() - 0.5) * radius)
		local streak = piece(kit, { Size = Vector3.new(0.08, 1.5, 0.08), CFrame = CFrame.new(position + offset + Vector3.new(0, 0.8, 0)), Color = if math.random() < 0.4 then WHITE else EMERALD, Transparency = 0.05 })
		kit.Vfx.fade(streak, 0.45, { CFrame = CFrame.new(position + offset + Vector3.new(0, 9 + math.random() * 4, 0)), Size = Vector3.new(0.03, 4, 0.03) })
	end
	kit.Vfx.burst(position + Vector3.new(0, 0.5, 0), {
		color = EMERALD,
		texture = SPARKLE,
		size = NumberSequence.new({ key(0, 0.5), key(1, 0) }),
		lifetime = NumberRange.new(0.4, 0.9),
		speed = NumberRange.new(18, 34),
		spread = Vector2.new(18, 18),
		acceleration = Vector3.new(0, -12, 0),
		count = 24,
	})
	groundSquare(kit, position, 0.6, WHITE, 0.4, radius)
	kit.Vfx.glow(position + Vector3.new(0, 2, 0), EMERALD, radius * 2, 2.5, 0.2)
	kit.Vfx.sound("HeavyHit", position)
	kit.shake(1.2, 0.2, position)
end

-- Command Zone -------------------------------------------------------------------------------

function fx.CommandZone(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 9), 1, 24)
	local endsAt = num(kit.data.endsAt, kit.now() + num(kit.data.duration, 4))
	local total = math.max(0.1, endsAt - kit.now())
	local ring = circle(kit, position, radius, EMERALD, 0.12, 0.15)
	local inner = circle(kit, position, radius * 0.82, TEAL, 0.06, 0.5, true)
	-- The countdown hangs over the zone in big digits; a bar under it empties
	local anchor = anchorAt(kit, position + Vector3.new(0, 6.5, 0))
	local digits = tag(anchor, "EXEC 4", 4.4, 1.4, Vector3.zero)
	local track = piece(kit, { Size = Vector3.new(radius * 1.2, 0.08, 0.08), CFrame = CFrame.new(position + Vector3.new(0, 5.4, 0)), Color = TEAL, Transparency = 0.5 })
	local fill = piece(kit, { Size = Vector3.new(radius * 1.2, 0.12, 0.12), CFrame = CFrame.new(position + Vector3.new(0, 5.4, 0)), Color = WHITE, Transparency = 0.05 })
	-- Two runtime panels at the edge, facing out
	local panels = {}
	if kit.degree >= 2 then
		for _, side in { -1, 1 } do
			local at = position + Vector3.new(side * radius, 2.6, 0)
			local sheet = panel(kit, CFrame.lookAt(at, at + Vector3.new(side, 0, 0)), 3.2, 1.8, "cmd_zone", string.format("while t > 0:\n  slow(%.2f)\non 0: distort()", 0.65))
			table.insert(panels, sheet)
		end
	end
	groundSquare(kit, position, 0.5, WHITE, 0.35, radius)
	local stop = animate(total + 0.3, function(elapsed)
		local left = math.max(0, endsAt - kit.now())
		digits.Text = string.format("EXEC %d", math.ceil(left - 1e-3))
		local share = math.clamp(left / total, 0, 1)
		local width = math.max(0.02, radius * 1.2 * share)
		fill.Size = Vector3.new(width, 0.12, 0.12)
		fill.CFrame = CFrame.new(position + Vector3.new(-radius * 0.6 + width / 2, 5.4, 0))
		-- The last second goes white and urgent
		if left <= 1 then
			digits.TextColor3 = if math.floor(elapsed * 8) % 2 == 0 then WHITE else EMERALD
		end
		for index, part in inner do
			local angle = (index / #inner) * math.pi * 2 + elapsed * 0.5
			local at = position + Vector3.new(math.cos(angle) * radius * 0.82, 0.07, math.sin(angle) * radius * 0.82)
			part.CFrame = CFrame.lookAt(at, at + Vector3.new(-math.sin(angle), 0, math.cos(angle)))
		end
		return true
	end)
	kit.keep(function()
		stop()
		retireAll(kit, ring, 0.3)
		retireAll(kit, inner, 0.3)
		retire(kit, track, 0.2)
		retire(kit, fill, 0.2)
		for _, sheet in panels do
			sheet.close(0.2)
		end
		anchor:Destroy()
	end)
end

function fx.CommandExecute(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 9), 1, 24)
	-- The ring snaps shut on the centre, then a square shockwave goes out
	local ring = circle(kit, position, radius, WHITE, 0.14, 0.05)
	for _, part in ring do
		kit.Vfx.fade(part, 0.18, { CFrame = CFrame.new(position:Lerp(part.Position, 0.15)) * part.CFrame.Rotation })
	end
	task.delay(0.16, function()
		groundSquare(kit, position, 0.6, WHITE, 0.4, radius * 0.8)
		groundSquare(kit, position, 0.6, EMERALD, 0.55, radius)
		flecks(kit, position + Vector3.new(0, 1, 0), EMERALD, 16, 20)
		kit.Vfx.glow(position + Vector3.new(0, 2, 0), WHITE, radius * 2, 2.5, 0.15)
		fragment(kit, position + Vector3.new(0, 3, 0), if num(kit.data.count, 0) > 0 then "exec: hit" else "exec: 0", WHITE, 0.9, 1, Vector3.new(0, 1.2, 0))
		kit.Vfx.sound("HeavyHit", position)
		kit.shake(0.8, 0.15, position)
	end)
end

-- Confinement Field ---------------------------------------------------------------------------

-- Bars standing around a circle (the cell's walls)
local function cellBars(kit, position: Vector3, radius: number, height: number, color: Color3, transparency: number): { BasePart }
	local parts = {}
	local count = if kit.Vfx.reduced() then 8 else 14
	for index = 0, count - 1 do
		local angle = index / count * math.pi * 2
		local at = position + Vector3.new(math.cos(angle) * radius, height / 2, math.sin(angle) * radius)
		table.insert(parts, piece(kit, { Size = Vector3.new(0.08, height, 0.08), CFrame = CFrame.new(at), Color = color, Transparency = transparency }))
	end
	return parts
end

function fx.CellClosing(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 5), 1, 12)
	local duration = math.clamp(num(kit.data.duration, 0.45), 0.1, 2)
	-- Four panels slide in from twice the radius: the walls closing
	local walls = {}
	for index = 0, 3 do
		local angle = index * math.pi / 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local start = position + out * radius * 2 + Vector3.new(0, 2.5, 0)
		local wall = piece(kit, { Size = Vector3.new(radius * 1.3, 5, 0.06), CFrame = CFrame.lookAt(start, start + out), Color = EMERALD, Material = Enum.Material.ForceField, Transparency = 0.35 })
		local finish = position + out * radius + Vector3.new(0, 2.5, 0)
		tween(wall, duration, { CFrame = CFrame.lookAt(finish, finish + out) }, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
		table.insert(walls, wall)
	end
	local ring = circle(kit, position, radius, WHITE, 0.08, 0.2, true)
	local anchor = anchorAt(kit, position + Vector3.new(0, 6, 0))
	tag(anchor, "confine()", 3, 0.6, Vector3.zero)
	task.delay(duration + 0.05, function()
		retireAll(kit, walls, 0.15)
		retireAll(kit, ring, 0.15)
		anchor:Destroy()
	end)
end

function fx.CellCancel(kit)
	local position = vec(kit.data.position)
	if position then
		fragment(kit, position + Vector3.new(0, 3, 0), "aborted", TEAL, 0.7, 0.8, Vector3.new(0, 0.8, 0))
	end
end

function fx.CellMiss(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 5), 1, 12)
	groundSquare(kit, position, radius, TEAL, 0.4, radius * 0.2)
	fragment(kit, position + Vector3.new(0, 3, 0), "null", TEAL, 0.7, 0.8, Vector3.new(0, 0.8, 0))
end

function fx.Cell(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 5), 1, 12)
	local endsAt = num(kit.data.endsAt, kit.now() + num(kit.data.duration, 2.5))
	local bars = cellBars(kit, position, radius, 6, EMERALD, 0.1)
	local top = circle(kit, position + Vector3.new(0, 6, 0), radius, WHITE, 0.08, 0.15)
	local bottom = circle(kit, position, radius, EMERALD, 0.1, 0.1)
	local anchor = anchorAt(kit, position + Vector3.new(0, 7.2, 0))
	local label = tag(anchor, "CONFINED", 4.6, 0.7, Vector3.zero)
	kit.Vfx.glow(position + Vector3.new(0, 3, 0), EMERALD, radius * 2, 1.4, 0.3)
	kit.Vfx.sound("Block", position)
	local stop = animate(math.max(0.1, endsAt - kit.now()) + 0.3, function(elapsed)
		-- The bars hum: a faint brightness running round the cell
		for index, part in bars do
			part.Transparency = 0.1 + 0.25 * (0.5 + 0.5 * math.sin(elapsed * 6 + index))
		end
		label.Text = string.format("CONFINED %.1fs  mash", math.max(0, endsAt - kit.now()))
		return true
	end)
	kit.keep(function()
		stop()
		retireAll(kit, bars, 0.25)
		retireAll(kit, top, 0.25)
		retireAll(kit, bottom, 0.25)
		anchor:Destroy()
	end)
end

function fx.CellBreak(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 5), 1, 12)
	-- Broken out: the bars fly outward and the cell flashes white
	for _, part in cellBars(kit, position, radius, 6, WHITE, 0.05) do
		local out = flat(part.Position - position)
		kit.Vfx.fade(part, 0.4, { CFrame = part.CFrame + out * 4, Size = Vector3.new(0.04, 2, 0.04) })
	end
	kit.Vfx.glow(position + Vector3.new(0, 3, 0), WHITE, radius * 2, 2.5, 0.15)
	fragment(kit, position + Vector3.new(0, 4, 0), "break", WHITE, 0.8, 0.8, Vector3.new(0, 1, 0))
	kit.Vfx.sound("GuardBreak", position)
end

-- Execute Chain ------------------------------------------------------------------------------

-- The three command panels stacked beside her, by caster
local chains: { [Instance]: { any } } = setmetatable({}, { __mode = "k" }) :: any

local function closeChain(model: Instance?, duration: number)
	local list = model and chains[model]
	if not list then
		return
	end
	chains[model :: Instance] = nil
	for _, sheet in list do
		sheet.close(duration)
	end
end

function fx.ChainStart(kit)
	local root = kit.root
	if not root or not kit.model then
		return
	end
	closeChain(kit.model, 0.05)
	local lines = { "1  lock()", "2  slow(0.7)", "3  bolt() x3" }
	local list = {}
	for index, text in lines do
		local at = root.CFrame * CFrame.new(-2.6, 2.6 - (index - 1) * 0.75, -0.6)
		local sheet = panel(kit, CFrame.lookAt(at.Position, at.Position + root.CFrame.LookVector), 2.6, 0.62, "step " .. index, text)
		sheet.body.TextColor3 = TEAL
		table.insert(list, sheet)
	end
	chains[kit.model] = list
	local model = kit.model
	task.delay(math.clamp(num(kit.data.duration, 0.3), 0.1, 1) + 1.6, function()
		if chains[model] == list then
			closeChain(model, 0.3)
		end
	end)
	local target = rootOf(modelOf(kit.data.target))
	if target then
		kit.Vfx.beam(hand(kit), target.Position, TEAL, 0.04, 0.4)
	end
end

function fx.ChainStep(kit)
	local step = math.clamp(math.floor(num(kit.data.step, 1)), 1, 3)
	local list = kit.model and chains[kit.model]
	local sheet = list and list[step]
	if sheet then
		-- The running line lights white
		sheet.body.TextColor3 = WHITE
		sheet.title.BackgroundColor3 = WHITE
	end
	local target = modelOf(kit.data.target)
	local root = rootOf(target)
	if not root then
		return
	end
	if step == 1 then
		snapMarquee(kit, root.Position, 4, EMERALD, 0.5)
		kit.Vfx.sound("Parry", root.Position)
	elseif step == 2 then
		-- Down-pointing chevrons settle on them
		for index = 1, 3 do
			task.delay(index * 0.06, function()
				local at = root.Position + Vector3.new(0, 3 - index * 0.7, 0)
				fragment(kit, at, "v", EMERALD, 1, 0.6, Vector3.new(0, -1, 0))
			end)
		end
	end
	kit.Vfx.beam(hand(kit), root.Position, WHITE, 0.04, 0.2)
end

function fx.ChainFail(kit)
	local list = kit.model and chains[kit.model]
	if list then
		for _, sheet in list do
			sheet.title.BackgroundColor3 = TEAL
		end
	end
	closeChain(kit.model, 0.25)
	if kit.root then
		fragment(kit, kit.root.Position + Vector3.new(0, 3.4, 0), "chain aborted", TEAL, 0.8, 0.9, Vector3.new(0, 1, 0))
	end
end

-- Rule Rewrite ---------------------------------------------------------------------------------

function fx.RuleField(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 14), 2, 30)
	local rule = if typeof(kit.data.rule) == "string" then string.sub(kit.data.rule, 1, 24) else "RULE = ?"
	local endsAt = num(kit.data.endsAt, kit.now() + num(kit.data.duration, 5))
	local parts = {}
	-- The field's boundary: a bright edge with posts, and the sigil grid inside
	for _, part in circle(kit, position, radius, EMERALD, 0.16, 0.1) do
		table.insert(parts, part)
	end
	local posts = if kit.Vfx.reduced() then 4 else 8
	for index = 0, posts - 1 do
		local angle = index / posts * math.pi * 2
		local at = position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		table.insert(parts, bar(kit, at, at + Vector3.new(0, 7, 0), 0.07, WHITE, 0.3) :: BasePart)
	end
	dotGrid(kit, position, radius / 3, 5, EMERALD, 1.4)
	-- The rule, written over the field in big letters, with the time it has left
	local anchor = anchorAt(kit, position + Vector3.new(0, 9, 0))
	local label = tag(anchor, rule, math.max(6, #rule * 0.55), 1.8, Vector3.zero)
	label.TextColor3 = WHITE
	local timer = tag(anchor, "", 4, 0.7, Vector3.new(0, -1.5, 0))
	-- Heavier gravity reads as light falling: slow streaks drifting down
	local rain = anchorAt(kit, position + Vector3.new(0, 7, 0))
	rain.Size = Vector3.new(radius * 1.4, 0.2, radius * 1.4)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = ColorSequence.new(EMERALD)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ key(0, 0.25), key(1, 0.1) })
	emitter.Transparency = NumberSequence.new({ key(0, 1), key(0.2, 0.3), key(1, 1) })
	emitter.Lifetime = NumberRange.new(0.8, 1.2)
	emitter.Speed = NumberRange.new(6, 9)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.SpreadAngle = Vector2.new(4, 4)
	emitter.Rate = if kit.Vfx.reduced() then 6 else 22
	emitter.Parent = rain
	groundSquare(kit, position, 1, WHITE, 0.5, radius * 0.75)
	kit.Vfx.glow(position + Vector3.new(0, 3, 0), EMERALD, radius * 2, 1.5, 0.4)
	kit.Vfx.sound("HeavyHit", position)
	kit.shake(0.6, 0.2, position)
	local stop = animate(math.max(0.1, endsAt - kit.now()) + 0.3, function()
		timer.Text = string.format("reverts in %.1fs", math.max(0, endsAt - kit.now()))
		return true
	end)
	kit.keep(function()
		stop()
		emitter.Enabled = false
		retireAll(kit, parts, 0.3)
		Debris:AddItem(rain, 1.3)
		anchor:Destroy()
	end)
end

function fx.RuleRevert(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 14), 2, 30)
	local anchor = anchorAt(kit, position + Vector3.new(0, 9, 0))
	tag(anchor, "GRAVITY = 1.0", 7, 1.6, Vector3.zero)
	Debris:AddItem(anchor, 1)
	groundSquare(kit, position, radius * 0.7, TEAL, 0.5, 0.5)
	fragments(kit, position + Vector3.new(0, 2, 0), 3, radius, EMERALD, 1, 1.5)
end

-- Reconstruct ----------------------------------------------------------------------------------

function fx.Restore(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local text = if typeof(kit.data.label) == "string" then string.sub(kit.data.label, 1, 32) else "RESTORE"
	-- Rewind: scanlines sweep up, fragments are pulled back in
	for index = 1, 3 do
		task.delay((index - 1) * 0.08, function()
			local line = piece(kit, { Size = Vector3.new(8, 0.06, 0.06), CFrame = CFrame.lookAt(position - Vector3.new(0, 3.5, 0), cameraPosition()), Color = WHITE, Transparency = 0.1 })
			kit.Vfx.fade(line, 0.35, { CFrame = line.CFrame + Vector3.new(0, 7, 0) })
		end)
	end
	local count = if kit.Vfx.reduced() then 2 else 5
	for _ = 1, count do
		local offset = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit * 4
		fragment(kit, position + offset, TOKENS[math.random(1, #TOKENS)], EMERALD, 0.6, 0.45, -offset)
	end
	local anchor = anchorAt(kit, position + Vector3.new(0, 4.5, 0))
	tag(anchor, text, #text * 0.2 + 1, 0.65, Vector3.zero, WHITE)
	Debris:AddItem(anchor, 1.4)
	kit.Vfx.glow(position, WHITE, 12, 2, 0.3)
	kit.Vfx.sound("Parry", position)
	pose(kit, "SyntaxGuard", 0.08, 0.3, 0.3)
end

-- Move Override --------------------------------------------------------------------------------

function fx.Lane(kit)
	local frame = frameOf(kit.data.cframe)
	if not frame then
		return
	end
	local width = math.clamp(num(kit.data.width, 9), 1, 20)
	local length = math.clamp(num(kit.data.length, 28), 2, 60)
	local endsAt = num(kit.data.endsAt, kit.now() + num(kit.data.duration, 4))
	local parts = {}
	-- Two long edges and the end lines
	for _, x in { -width / 2, width / 2 } do
		table.insert(parts, bar(kit, (frame * CFrame.new(x, 0.08, length / 2)).Position, (frame * CFrame.new(x, 0.08, -length / 2)).Position, 0.1, EMERALD, 0.1) :: BasePart)
	end
	table.insert(parts, bar(kit, (frame * CFrame.new(-width / 2, 0.08, length / 2)).Position, (frame * CFrame.new(width / 2, 0.08, length / 2)).Position, 0.06, TEAL, 0.4) :: BasePart)
	-- Chevrons riding the lane toward its far end
	local chevrons = {}
	local count = if kit.Vfx.reduced() then 3 else 6
	for _ = 1, count do
		local left = piece(kit, { Size = Vector3.new(0.12, 0.05, width * 0.35), Color = WHITE, Transparency = 0.2 })
		local right = piece(kit, { Size = Vector3.new(0.12, 0.05, width * 0.35), Color = WHITE, Transparency = 0.2 })
		table.insert(chevrons, { left, right })
		table.insert(parts, left)
		table.insert(parts, right)
	end
	local anchor = anchorAt(kit, (frame * CFrame.new(0, 3.2, length / 2)).Position)
	local label = tag(anchor, "MOVE.DIR = >>", 4.4, 0.7, Vector3.zero)
	local stop = animate(math.max(0.1, endsAt - kit.now()) + 0.3, function(elapsed)
		for index, pair in chevrons do
			local along = ((elapsed * 6 + index / #chevrons * length) % length) - length / 2
			local at = frame * CFrame.new(0, 0.09, -along)
			local half = width * 0.35 / 2
			pair[1].CFrame = at * CFrame.new(-half * 0.7, 0, half * 0.7) * CFrame.Angles(0, math.rad(45), 0)
			pair[2].CFrame = at * CFrame.new(half * 0.7, 0, half * 0.7) * CFrame.Angles(0, math.rad(-45), 0)
		end
		label.Text = string.format("MOVE.DIR = >>  %.1fs", math.max(0, endsAt - kit.now()))
		return true
	end)
	kit.Vfx.sound("LightSwing", frame.Position)
	kit.keep(function()
		stop()
		retireAll(kit, parts, 0.3)
		anchor:Destroy()
	end)
end

-- System Override ------------------------------------------------------------------------------

local overrides: { [Instance]: { state: any } } = setmetatable({}, { __mode = "k" }) :: any

function fx.Override(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 15), 2, 30)
	local impactAt = num(kit.data.impactAt, kit.now() + 1.3)
	local lock = math.clamp(num(kit.data.lock, 2), 0, 2)
	local parts = {}
	local sheets = {}
	-- Anticipation: the boundary is drawn around the area, segment by segment
	local edge = circle(kit, position, radius, EMERALD, 0.18, 1)
	for index, part in edge do
		table.insert(parts, part)
		task.delay(index / #edge * 0.3, function()
			if part.Parent then
				tween(part, 0.08, { Transparency = 0.05 })
			end
		end)
	end
	local inner = circle(kit, position, radius * 0.6, TEAL, 0.07, 0.4, true)
	for _, part in inner do
		table.insert(parts, part)
	end
	dotGrid(kit, position, radius / 3.5, 7, EMERALD, 2.2)
	-- Large screens rise around the edge, facing in
	local screens = if kit.Vfx.reduced() then 3 else 6
	local scripts = {
		"override --root",
		string.format("lock(abilities, %ds)", lock),
		"route: all -> here",
		"strike.sync()",
		"restore on exit",
		"area claimed",
	}
	for index = 0, screens - 1 do
		local angle = index / screens * math.pi * 2
		local at = position + Vector3.new(math.cos(angle) * (radius + 0.5), 3.4, math.sin(angle) * (radius + 0.5))
		local sheet = panel(kit, CFrame.lookAt(at, Vector3.new(position.X, at.Y, position.Z)), 4.4, 2.4, "SYSTEM", scripts[index % #scripts + 1])
		table.insert(sheets, sheet)
	end
	-- The title over everything, and the time to impact
	local anchor = anchorAt(kit, position + Vector3.new(0, 11, 0))
	local title = tag(anchor, "SYSTEM OVERRIDE", 9, 1.7, Vector3.zero)
	local status = tag(anchor, "claiming area", 7, 0.8, Vector3.new(0, -1.6, 0))
	-- Thin lines from the screens converge on a point over the centre: gathering
	local apex = position + Vector3.new(0, 8, 0)
	local spokes = {}
	for _, sheet in sheets do
		local spoke = bar(kit, sheet.part.Position + Vector3.new(0, 1.2, 0), apex, 0.05, WHITE, 0.5)
		if spoke then
			table.insert(spokes, spoke)
			table.insert(parts, spoke)
		end
	end
	local core = piece(kit, { Size = Vector3.new(0.8, 0.8, 0.8), CFrame = CFrame.new(apex), Color = WHITE, Transparency = 0.05 })
	table.insert(parts, core)
	kit.Vfx.glow(core, EMERALD, 24, 2, 3)
	kit.Vfx.sound("HeavySwing", position)
	if kit.near(position, radius + 8) then
		kit.Vfx.screenFlash(EMERALD, 0.25, 0.6)
	end
	local state = { status = status, title = title, phase = "claim" }
	if kit.model then
		overrides[kit.model] = { state = state }
	end
	local stop = animate(num(kit.data.duration, 3) + 0.3, function(elapsed)
		local toImpact = impactAt - kit.now()
		if state.phase == "claim" or state.phase == "locked" then
			status.Text = if toImpact > 0 then string.format("%s  EXECUTE %.1f", if state.phase == "locked" then string.format("ABILITIES LOCKED: %ds", lock) else "claiming area", toImpact) else "EXECUTE"
		end
		local grow = math.clamp(elapsed / 1.2, 0, 1)
		core.Size = Vector3.one * (0.8 + grow * 1.6)
		core.CFrame = CFrame.new(apex) * CFrame.Angles(elapsed * 2, elapsed * 3, 0)
		for index, part in inner do
			local angle = (index / #inner) * math.pi * 2 - elapsed * 0.8
			local at = position + Vector3.new(math.cos(angle) * radius * 0.6, 0.07, math.sin(angle) * radius * 0.6)
			part.CFrame = CFrame.lookAt(at, at + Vector3.new(-math.sin(angle), 0, math.cos(angle)))
		end
		return true
	end)
	kit.keep(function()
		stop()
		-- Dissipation: screens lower and fold, the edge fades from the outside in
		for _, sheet in sheets do
			sheet.close(0.4)
		end
		for _, part in parts do
			retire(kit, part, 0.5)
		end
		anchor:Destroy()
		if kit.model and overrides[kit.model] and overrides[kit.model].state == state then
			overrides[kit.model] = nil
		end
	end)
end

function fx.OverrideClaim(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 15), 2, 30)
	local lock = math.clamp(num(kit.data.lock, 2), 0, 2)
	local entry = kit.model and overrides[kit.model]
	if entry then
		entry.state.phase = "locked"
	end
	-- A claim wave runs out across the floor
	groundSquare(kit, position, 1, WHITE, 0.5, radius * 0.72)
	local wave = circle(kit, position, 1, WHITE, 0.12, 0.1)
	for _, part in wave do
		local out = flat(part.Position - position)
		kit.Vfx.fade(part, 0.4, { CFrame = part.CFrame + out * (radius - 1) })
	end
	-- Everyone inside wears the rule over their head for as long as it lasts
	if typeof(kit.data.targets) == "table" then
		for _, model in kit.data.targets do
			local target = modelOf(model)
			if target then
				followReticle(kit, target, lock, "LOCKED", WHITE)
			end
		end
	end
	kit.Vfx.sound("Block", position)
end

function fx.OverrideStrike(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 15), 2, 30)
	local entry = kit.model and overrides[kit.model]
	if entry then
		entry.state.phase = "strike"
		entry.state.status.Text = "EXECUTE"
	end
	local apex = position + Vector3.new(0, 8, 0)
	-- Impact: a precise vertical beam onto every target, all at once
	if typeof(kit.data.targets) == "table" then
		for _, at in kit.data.targets do
			local point = vec(at)
			if point then
				local top = point + Vector3.new(0, 30, 0)
				kit.Vfx.beam(top, point - Vector3.new(0, 2.5, 0), WHITE, 1.1, 0.3)
				kit.Vfx.beam(top, point - Vector3.new(0, 2.5, 0), EMERALD, 2.4, 0.45, Enum.Material.ForceField)
				kit.Vfx.beam(apex, point, WHITE, 0.08, 0.25)
				groundSquare(kit, point - Vector3.new(0, 2.9, 0), 0.6, WHITE, 0.45, 5)
				flecks(kit, point, WHITE, 18, 26)
				fragments(kit, point, 3, 3, EMERALD, 1.1, 2)
			end
		end
	end
	groundSquare(kit, position, 1, EMERALD, 0.6, radius * 0.9)
	kit.Vfx.glow(position + Vector3.new(0, 4, 0), WHITE, radius * 2.5, 4, 0.2)
	kit.Vfx.sound("HeavyHit", position)
	kit.shake(2.6, 0.4, position)
	if kit.near(position, radius + 6) then
		kit.Vfx.screenFlash(WHITE, 0.4, 0.3)
	end
end

function fx.OverrideRestore(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 15), 2, 30)
	local anchor = anchorAt(kit, position + Vector3.new(0, 9, 0))
	tag(anchor, "RESTORED", 6, 1.2, Vector3.zero)
	Debris:AddItem(anchor, 1.2)
	groundSquare(kit, position, radius * 0.7, TEAL, 0.6, 0.5)
	fragments(kit, position + Vector3.new(0, 2, 0), 4, radius, EMERALD, 1.2, 1.5)
end

function fx.OverrideFizzle(kit)
	local position = vec(kit.data.position)
	if position then
		fragment(kit, position + Vector3.new(0, 6, 0), "override aborted", TEAL, 1, 1, Vector3.new(0, 1, 0))
	end
end

-- Her weakness: a close hit knocks packets out of her
function fx.Dropped(kit)
	if not kit.root then
		return
	end
	local amount = math.floor(num(kit.data.amount, 0))
	fragment(kit, kit.root.Position + Vector3.new(0, 2.6, 0), string.format("packet loss -%d", amount), TEAL, 0.7, 0.8, Vector3.new(0, -1.2, 0))
	flecks(kit, kit.root.Position, TEAL, 6, 8)
end

-- Projectiles ---------------------------------------------------------------------------------

local function trail(part: BasePart, color: Color3, width: number, lifetime: number, reduced: boolean)
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, width / 2, 0)
	top.Parent = part
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -width / 2, 0)
	bottom.Parent = part
	local streak = Instance.new("Trail")
	streak.Attachment0 = top
	streak.Attachment1 = bottom
	streak.Color = ColorSequence.new(WHITE, color)
	streak.LightEmission = 1
	streak.Lifetime = if reduced then lifetime * 0.5 else lifetime
	streak.Transparency = NumberSequence.new({ key(0, 0.1), key(1, 1) })
	streak.WidthScale = NumberSequence.new({ key(0, 1), key(1, 0.1) })
	streak.Parent = part
end

local function pointLight(parent: Instance, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = parent
end

-- The server bends homing shots toward their target; the drawing does the same so
-- it stays on top of the real one. Until a redirect changes the flight, then it follows that.
local function homingPath(kit)
	local target = modelOf(kit.data.target)
	local turn = math.rad(math.clamp(num(kit.data.turnRate, 0), 0, 720))
	local position: Vector3? = nil
	local velocity: Vector3? = nil
	local launched: Vector3? = nil
	local following = target == nil or turn <= 0
	return function(given: Vector3, givenVelocity: Vector3, dt: number): (Vector3, Vector3)
		if not launched then
			launched = givenVelocity
		elseif not following and (givenVelocity - (launched :: Vector3)).Magnitude > 1 then
			following = true
		end
		if following or not position or not velocity or dt <= 0 then
			position, velocity = given, givenVelocity
			return given, givenVelocity
		end
		local current = velocity :: Vector3
		local root = rootOf(target)
		if root and current.Magnitude > 0.1 then
			local wanted = root.Position - (position :: Vector3)
			if wanted.Magnitude > 0.5 then
				local unit = current.Unit
				local desired = wanted.Unit
				local angle = math.acos(math.clamp(unit:Dot(desired), -1, 1))
				if angle > 1e-3 then
					local t = math.min(1, turn * dt / angle)
					current = unit:Lerp(desired, t).Unit * current.Magnitude
				end
			end
		end
		velocity = current
		position = (position :: Vector3) + current * dt
		return position :: Vector3, current
	end
end

-- An impact: a square ripple facing the viewer, flecks and a short light
local function impact(kit, position: Vector3, size: number, reason: string)
	if reason == "Destroyed" then
		return
	end
	if reason == "Hit" then
		square(kit, CFrame.lookAt(position, cameraPosition()), 0.3 * size, 0.06, WHITE, 0.25, 1.4 * size)
		flecks(kit, position, EMERALD, math.floor(6 * size), 12 * size)
		kit.Vfx.glow(position, EMERALD, 6 * size, 1.5, 0.12)
	else
		square(kit, CFrame.lookAt(position, cameraPosition()), 0.2 * size, 0.05, EMERALD, 0.2, 0.8 * size)
		flecks(kit, position, TEAL, math.floor(3 * size), 8)
	end
end

-- Keystroke: a small white diamond in an emerald sleeve; brighter the farther it's meant to fly
function Syntax.projectiles.Packet(kit)
	local charge = math.clamp(num(kit.data.charge, 0.5), 0, 1)
	local core = piece(kit, { Size = Vector3.new(0.28, 0.28, 0.28), Color = WHITE, Transparency = 0 })
	local sleeve = piece(kit, { Size = Vector3.new(0.5, 0.5, 1.4 + charge * 0.6), Color = EMERALD, Material = Enum.Material.ForceField, Transparency = 0.35 - charge * 0.2 })
	trail(core, EMERALD, 0.22, 0.1, kit.Vfx.reduced())
	local path = homingPath(kit)
	local first = true
	local spin = 0
	return {
		update = function(position: Vector3, velocity: Vector3, dt: number)
			local at, motion = path(position, velocity, dt)
			spin += dt * 12
			local frame = if motion.Magnitude > 0.1 then CFrame.lookAt(at, at + motion) else CFrame.new(at)
			core.CFrame = frame * CFrame.Angles(0, 0, spin) * CFrame.Angles(math.rad(45), math.rad(45), 0)
			sleeve.CFrame = frame
			if first then
				first = false
				compile(kit, 0.6)
				kit.Vfx.sound("LightSwing", at)
			end
		end,
		finish = function(position: Vector3, reason: string)
			core:Destroy()
			sleeve:Destroy()
			impact(kit, position, 0.8 + charge * 0.4, reason)
		end,
	}
end

-- Code Bolt: a white core between two turning emerald brackets, shedding glyphs
function Syntax.projectiles.CodeBolt(kit)
	local locked = kit.data.locked == true
	local core = piece(kit, { Size = Vector3.new(0.3, 0.3, 1.6), Color = WHITE, Transparency = 0 })
	local shell = piece(kit, { Size = Vector3.new(0.8, 0.8, 2.2), Color = EMERALD, Material = Enum.Material.ForceField, Transparency = 0.2 })
	local brackets = {}
	for _ = 1, 4 do
		table.insert(brackets, piece(kit, { Size = Vector3.new(0.08, 0.5, 0.08), Color = if locked then WHITE else EMERALD, Transparency = 0.05 }))
	end
	pointLight(core, EMERALD, 9, 1.6)
	trail(core, EMERALD, 0.35, 0.16, kit.Vfx.reduced())
	local path = homingPath(kit)
	local first = true
	local age = 0
	local lastGlyph = 0
	local glyphs = 0
	local maxGlyphs = if kit.Vfx.reduced() then 3 else 10
	return {
		update = function(position: Vector3, velocity: Vector3, dt: number)
			local at, motion = path(position, velocity, dt)
			age += dt
			local frame = if motion.Magnitude > 0.1 then CFrame.lookAt(at, at + motion) else CFrame.new(at)
			core.CFrame = frame
			shell.CFrame = frame
			for index, piecePart in brackets do
				-- Four short bars turning around the core: a moving "< >"
				local turn = frame * CFrame.Angles(0, 0, age * 9 + index * math.pi / 2)
				piecePart.CFrame = turn * CFrame.new(0.55, 0, 0) * CFrame.Angles(0, 0, math.rad(30))
			end
			if age - lastGlyph > 0.06 and glyphs < maxGlyphs then
				lastGlyph = age
				glyphs += 1
				fragment(kit, at, if glyphs % 3 == 0 then "{" elseif glyphs % 3 == 1 then "01" else "}", EMERALD, 0.45, 0.35, Vector3.new(0, 0.4, 0))
			end
			if first then
				first = false
				compile(kit, 1)
				kit.Vfx.sound("LightSwing", at)
			end
		end,
		finish = function(position: Vector3, reason: string)
			core:Destroy()
			shell:Destroy()
			for _, piecePart in brackets do
				piecePart:Destroy()
			end
			impact(kit, position, 1.4, reason)
			if reason == "Hit" then
				fragment(kit, position + Vector3.new(0, 0.8, 0), "err", WHITE, 0.6, 0.6, Vector3.new(0, 1, 0))
			end
		end,
	}
end

-- A sentry's shot: a thin white dart
function Syntax.projectiles.SentryBolt(kit)
	local core = piece(kit, { Size = Vector3.new(0.16, 0.16, 1.1), Color = WHITE, Transparency = 0 })
	local glow = piece(kit, { Size = Vector3.new(0.4, 0.4, 1.4), Color = EMERALD, Material = Enum.Material.ForceField, Transparency = 0.3 })
	trail(core, EMERALD, 0.16, 0.08, kit.Vfx.reduced())
	local first = true
	return {
		update = function(position: Vector3, velocity: Vector3)
			local frame = if velocity.Magnitude > 0.1 then CFrame.lookAt(position, position + velocity) else CFrame.new(position)
			core.CFrame = frame
			glow.CFrame = frame
			if first then
				first = false
				square(kit, frame, 0.2, 0.04, WHITE, 0.15, 0.6)
			end
		end,
		finish = function(position: Vector3, reason: string)
			core:Destroy()
			glow:Destroy()
			impact(kit, position, 0.7, reason)
		end,
	}
end

-- Execute Chain's bolts: small homing packets
function Syntax.projectiles.ChainBolt(kit)
	local core = piece(kit, { Size = Vector3.new(0.24, 0.24, 1), Color = WHITE, Transparency = 0 })
	local shell = piece(kit, { Size = Vector3.new(0.55, 0.55, 1.4), Color = EMERALD, Material = Enum.Material.ForceField, Transparency = 0.25 })
	trail(core, EMERALD, 0.25, 0.12, kit.Vfx.reduced())
	local path = homingPath(kit)
	local first = true
	return {
		update = function(position: Vector3, velocity: Vector3, dt: number)
			local at, motion = path(position, velocity, dt)
			local frame = if motion.Magnitude > 0.1 then CFrame.lookAt(at, at + motion) else CFrame.new(at)
			core.CFrame = frame
			shell.CFrame = frame * CFrame.Angles(0, 0, at.Magnitude)
			if first then
				first = false
				compile(kit, 0.7)
			end
		end,
		finish = function(position: Vector3, reason: string)
			core:Destroy()
			shell:Destroy()
			impact(kit, position, 1, reason)
		end,
	}
end

-- Appearance ------------------------------------------------------------------------------------

local function firstPart(model: Model, names: { string }): BasePart?
	for _, name in names do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

-- One welded, massless, non-colliding piece of gear on `base`
local function mount(folder: Instance, base: BasePart, offset: CFrame, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Material = Enum.Material.Neon
	for name, value in props do
		if name ~= "Size" then
			(part :: any)[name] = value
		end
	end
	part.Size = props.Size or Vector3.one
	part.CFrame = base.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Name = "SNGearWeld"
	weld.Part0 = base
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	part.Parent = folder
	return part
end

-- A small screen of scrolling text mounted on the body
local function gearScreen(folder: Instance, base: BasePart, offset: CFrame, width: number, height: number, name: string): TextLabel
	local sheet = mount(folder, base, offset, { Name = name, Size = Vector3.new(width, height, 0.04), Color = EMERALD, Material = Enum.Material.Glass, Transparency = 0.9 })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.Adornee = sheet
	local screen = Instance.new("Frame")
	screen.BackgroundColor3 = GLASS
	screen.BackgroundTransparency = 0.35
	screen.BorderSizePixel = 0
	screen.ClipsDescendants = true
	screen.Size = UDim2.fromScale(1, 1)
	screen.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = EMERALD
	stroke.Thickness = 1.5
	stroke.Parent = screen
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Position = UDim2.new(0, 5, 0, 3)
	text.Size = UDim2.new(1, -10, 1, -6)
	text.Font = MONO
	text.TextSize = 10
	text.TextColor3 = WHITE
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.Text = LINES[1]
	text.Parent = screen
	gui.Parent = sheet
	return text
end

function Syntax.appearance(kit)
	local model = kit.model
	if not model then
		return nil
	end
	local old = model:FindFirstChild(GEAR)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = GEAR
	folder.Parent = model
	local degree = kit.degree
	local connections: { RBXScriptConnection } = {}
	local screens: { TextLabel } = {}
	local alive = true

	local head = firstPart(model, { "Head" })
	local torso = firstPart(model, { "UpperTorso", "Torso" })
	local rightArm = firstPart(model, { "RightLowerArm", "RightUpperArm", "Right Arm" })
	local leftArm = firstPart(model, { "LeftLowerArm", "LeftUpperArm", "Left Arm" })

	-- Every degree: a thin white visor line across the eyes and an emitter band on the right wrist
	if head then
		mount(folder, head, CFrame.new(0, 0.12, -head.Size.Z / 2 - 0.02), { Name = "SNVisor", Size = Vector3.new(head.Size.X * 0.9, 0.07, 0.04), Color = WHITE, Transparency = 0.1 })
	end
	if rightArm then
		local wrist = CFrame.new(0, -rightArm.Size.Y * 0.32, 0)
		mount(folder, rightArm, wrist, { Name = "SNWristBand", Size = Vector3.new(rightArm.Size.X * 1.08, 0.16, rightArm.Size.Z * 1.08), Color = rgb(28, 34, 38), Material = Enum.Material.Metal })
		mount(folder, rightArm, wrist * CFrame.new(0, 0, -rightArm.Size.Z * 0.55), { Name = "SNEmitter", Size = Vector3.new(0.3, 0.1, 0.05), Color = EMERALD })
	end
	-- Degree 1: a small screen floating off the left forearm
	if leftArm then
		local text = gearScreen(folder, leftArm, CFrame.new(-leftArm.Size.X / 2 - 0.35, -0.1, -0.15) * CFrame.Angles(0, math.rad(-70), 0), 0.95, 0.6, "SNWristScreen")
		table.insert(screens, text)
	end
	-- Degree 2: two runtime screens behind the shoulders and a trim line down the chest
	if degree >= 2 and torso then
		for _, side in { -1, 1 } do
			local offset = CFrame.new(side * (torso.Size.X / 2 + 0.55), torso.Size.Y * 0.45, torso.Size.Z / 2 + 0.25) * CFrame.Angles(math.rad(-10), math.rad(180 + side * 25), 0)
			table.insert(screens, gearScreen(folder, torso, offset, 0.9, 0.65, "SNShoulderScreen"))
		end
		mount(folder, torso, CFrame.new(torso.Size.X * 0.22, 0, -torso.Size.Z / 2 - 0.02), { Name = "SNTrim", Size = Vector3.new(0.06, torso.Size.Y * 0.8, 0.03), Color = EMERALD, Transparency = 0.1 })
	end
	-- Degree 3: the lattice halo behind her back, a ring of segments around a 3 by 3 grid of dots
	local halo: Part? = nil
	local haloWeld: Weld? = nil
	local haloBase = CFrame.identity
	if degree >= 3 and torso then
		haloBase = CFrame.new(0, torso.Size.Y * 0.35, torso.Size.Z / 2 + 0.9) * CFrame.Angles(0, math.rad(180), 0)
		halo = mount(folder, torso, haloBase, { Name = "SNHalo", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 })
		haloWeld = (halo :: Part):FindFirstChildOfClass("Weld")
		local segments = 12
		for index = 0, segments - 1 do
			local angle = index / segments * math.pi * 2
			local offset = CFrame.Angles(0, 0, angle) * CFrame.new(0, 1.55, 0)
			mount(folder, halo :: Part, offset, { Name = "SNHaloSegment", Size = Vector3.new(0.62, 0.07, 0.05), Color = if index % 3 == 0 then WHITE else EMERALD, Transparency = 0.05 })
		end
		for i = -1, 1 do
			for j = -1, 1 do
				mount(folder, halo :: Part, CFrame.new(i * 0.42, j * 0.42, 0), { Name = "SNHaloDot", Size = Vector3.new(0.14, 0.14, 0.05), Color = WHITE, Transparency = 0.1 })
			end
		end
		local light = Instance.new("PointLight")
		light.Color = EMERALD
		light.Range = 8
		light.Brightness = 0.8
		light.Shadows = false
		light.Parent = halo
	end

	-- The screens scroll slowly; the halo turns
	task.spawn(function()
		local line = 1
		while alive do
			line = line % #LINES + 1
			for index, text in screens do
				if text.Parent then
					local first = LINES[(line + index - 1) % #LINES + 1]
					local second = LINES[(line + index) % #LINES + 1]
					text.Text = first .. "\n" .. second
				end
			end
			task.wait(0.9)
		end
	end)
	if haloWeld then
		local weld = haloWeld :: Weld
		local started = os.clock()
		table.insert(connections, RunService.Heartbeat:Connect(function()
			if weld.Parent then
				weld.C0 = haloBase * CFrame.Angles(0, 0, (os.clock() - started) * 0.35)
			end
		end))
	end

	-- Hidden whenever the body is (concealment, invisibility)
	if torso then
		local base: { [BasePart]: number } = {}
		for _, item in folder:GetDescendants() do
			if item:IsA("BasePart") then
				base[item] = item.Transparency
			end
		end
		local body: BasePart = torso
		table.insert(connections, body:GetPropertyChangedSignal("Transparency"):Connect(function()
			for part, transparency in base do
				part.Transparency = math.max(transparency, body.Transparency)
			end
			for _, gui in folder:GetDescendants() do
				if gui:IsA("SurfaceGui") then
					gui.Enabled = body.Transparency < 0.9
				end
			end
		end))
	end

	-- The resource attribute drives the wrist emitter: dim when Processing runs low
	local emitter = folder:FindFirstChild("SNEmitter", true)
	local function refresh()
		local resource = num(kit.attribute(Attribute.Resource), 100)
		local max = math.max(1, num(kit.attribute(Attribute.ResourceMax), 100))
		if emitter and emitter:IsA("BasePart") then
			emitter.Color = TEAL:Lerp(EMERALD, math.clamp(resource / max, 0, 1))
		end
	end
	refresh()
	table.insert(connections, model:GetAttributeChangedSignal(Attribute.Resource):Connect(refresh))

	return function()
		alive = false
		for _, connection in connections do
			connection:Disconnect()
		end
		folder:Destroy()
	end
end

return Syntax
