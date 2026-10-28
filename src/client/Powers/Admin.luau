-- How Admin Powers looks: WARDEN, the station's command protocol, given a body.
-- Every command is spoken out loud as a line of terminal text in the world
-- (";freeze Bob", then the station's answer), and the station obeys with its
-- own hardware: gold doorways for teleports, lock-on brackets and padlocks,
-- security walls with grid lines, containment cells, a lockdown ring with
-- alarm beacons, gravity sigils on the floor, and at the end a giant gold
-- hammer. Gold and crimson on warm white, clean and exact, never rainbow.
-- Persistent look: gold cuffs and a rotating sigil on the back, epaulettes
-- from Degree 2 and a crown of light from Degree 3.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Admin = {}

local rgb = Color3.fromRGB
local GOLD = rgb(236, 188, 86)
local GOLD_DEEP = rgb(190, 138, 50)
local CRIMSON = rgb(168, 32, 48)
local CRIMSON_HOT = rgb(222, 70, 76)
local WHITE = rgb(250, 243, 228)
local FROST = rgb(226, 236, 240)
local GRAPHITE = rgb(46, 48, 54)
local STEEL = rgb(112, 116, 124)
local INK = rgb(20, 18, 16)
local DUST = rgb(150, 144, 136)

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local UP = Vector3.new(0, 1, 0)

-- Data checks (effects must never break on odd data) --------------------------------------

local function vec(value: any): Vector3?
	if typeof(value) == "Vector3" and value.X == value.X and value.Y == value.Y and value.Z == value.Z and value.Magnitude < 1e6 then
		return value
	end
	return nil
end

local function num(value: any, fallback: number): number
	if typeof(value) == "number" and value == value and math.abs(value) < 1e5 then
		return value
	end
	return fallback
end

local function modelOf(value: any): Model?
	if typeof(value) == "Instance" and value:IsA("Model") and value.Parent then
		return value
	end
	return nil
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function flatUnit(value: Vector3?): Vector3?
	if not value then
		return nil
	end
	local flat = Vector3.new(value.X, 0, value.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else nil
end

local function feetOf(root: BasePart?): Vector3?
	return if root then root.Position - Vector3.new(0, 2.9, 0) else nil
end

local function easeOut(a: number): number
	local inverse = 1 - math.clamp(a, 0, 1)
	return 1 - inverse * inverse * inverse
end

local function easeIn(a: number): number
	local t = math.clamp(a, 0, 1)
	return t * t
end

local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local function escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- Every-frame animation with a hard end. step(t, dt) returns false to stop early.
local function animate(life: number, step: (number, number) -> boolean?, cleanup: (() -> ())?): () -> ()
	local started = os.clock()
	local connection: RBXScriptConnection? = nil
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		if connection then
			connection:Disconnect()
		end
		if cleanup then
			local ok, err = pcall(cleanup)
			if not ok then
				warn("[Admin fx] cleanup failed: " .. tostring(err))
			end
		end
	end
	connection = RunService.Heartbeat:Connect(function(dt)
		local t = os.clock() - started
		if t >= life then
			finish()
			return
		end
		local ok, keep = pcall(step, t, dt)
		if not ok or keep == false then
			finish()
		end
	end)
	task.delay(life + 0.15, finish)
	return finish
end

-- Groups of effect parts placed relative to a moving base -----------------------------------

local Group = {}
Group.__index = Group

local function newGroup(kit)
	return setmetatable({ kit = kit, items = {}, base = CFrame.identity, scale = 1 }, Group)
end

function Group:add(offset: CFrame, props: { [string]: any }): BasePart
	local part = self.kit.Vfx.part(props)
	table.insert(self.items, { part = part, position = offset.Position, rotation = offset.Rotation, transparency = props.Transparency or 0 })
	part.CFrame = self.base * offset
	return part
end

function Group:place(base: CFrame, scale: number?)
	self.base = base
	local s = scale or 1
	for _, item in self.items do
		if item.part.Parent then
			item.part.CFrame = base * CFrame.new(item.position * s) * item.rotation
		end
	end
end

function Group:alpha(value: number)
	local a = math.clamp(value, 0, 1)
	for _, item in self.items do
		item.part.Transparency = 1 - (1 - item.transparency) * a
	end
end

function Group:fade(duration: number)
	for _, item in self.items do
		if item.part.Parent then
			self.kit.Vfx.fade(item.part, duration, { Transparency = 1 })
		end
	end
	table.clear(self.items)
end

function Group:destroy()
	for _, item in self.items do
		item.part:Destroy()
	end
	table.clear(self.items)
end

local function segmentsFor(kit, count: number): number
	return if kit.Vfx.reduced() then math.max(8, math.floor(count * 0.55)) else count
end

-- A flat ring lying in the group's XZ plane, made of short pieces. `gap` (0..1)
-- turns it into a dashed ring.
local function addRing(group, radius: number, y: number, width: number, color: Color3, transparency: number, count: number, gap: number?)
	local pieces = segmentsFor(group.kit, count)
	local length = 2 * math.pi * radius / pieces * (1 - (gap or 0.06))
	for index = 0, pieces - 1 do
		local angle = (index + 0.5) / pieces * math.pi * 2
		group:add(CFrame.Angles(0, angle, 0) * CFrame.new(0, y, -radius), {
			Size = Vector3.new(length, 0.05, width),
			Color = color,
			Transparency = transparency,
		})
	end
end

-- Short radial marks around a ring
local function addTicks(group, radius: number, y: number, count: number, length: number, color: Color3, transparency: number)
	for index = 0, count - 1 do
		local angle = index / count * math.pi * 2
		group:add(CFrame.Angles(0, angle, 0) * CFrame.new(0, y, -radius), {
			Size = Vector3.new(0.12, 0.05, length),
			Color = color,
			Transparency = transparency,
		})
	end
end

-- Command text: a terminal line in the world --------------------------------------------------

-- "> ;freeze Bob" typed out above someone, then the station's answer under it.
-- opts: { color, resultColor, life, offset, scale, resultDelay }
local function commandText(kit, at: any, command: string, result: string?, opts: { [string]: any }?)
	local options = opts or {}
	local anchor: BasePart
	if typeof(at) == "Instance" and at:IsA("BasePart") then
		anchor = kit.Vfx.part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = at.CFrame })
	else
		local position = vec(at)
		if not position then
			return
		end
		anchor = kit.Vfx.part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(position) })
	end
	local life = num(options.life, 1.6)
	local scale = num(options.scale, 1)
	local color = options.color or GOLD
	local text = string.sub(command, 1, 40)
	local gui = Instance.new("BillboardGui")
	gui.Name = "SNAdminCommand"
	gui.Size = UDim2.fromScale(math.clamp(#text * 0.4 + 1.8, 3.2, 14) * scale, (if result then 1.7 else 0.95) * scale)
	gui.StudsOffsetWorldSpace = options.offset or Vector3.new(0, 3.8, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	gui.Adornee = if typeof(at) == "Instance" then at else anchor
	local panel = Instance.new("Frame")
	panel.BackgroundColor3 = INK
	panel.BackgroundTransparency = 0.3
	panel.BorderSizePixel = 0
	panel.Size = UDim2.fromScale(1, 1)
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = 0.35
	stroke.Thickness = 1
	stroke.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = panel
	local line = Instance.new("TextLabel")
	line.BackgroundTransparency = 1
	line.Size = UDim2.fromScale(1, if result then 0.55 else 1)
	line.Font = Enum.Font.Code
	line.RichText = true
	line.TextScaled = true
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextColor3 = color
	line.Text = `<font color="{hex(CRIMSON_HOT)}">&gt;</font> {escape(text)}`
	line.MaxVisibleGraphemes = 0
	line.Parent = panel
	local answer: TextLabel? = nil
	if result then
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0, 0.58)
		label.Size = UDim2.fromScale(1, 0.42)
		label.Font = Enum.Font.Code
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = options.resultColor or WHITE
		label.Text = string.sub(result, 1, 40)
		label.TextTransparency = 1
		label.Parent = panel
		answer = label
	end
	gui.Parent = anchor
	-- Typed out fast, the answer a beat later, then it lifts away and fades
	local length = #text + 2
	local typing = math.min(0.22, length * 0.018)
	local resultAt = num(options.resultDelay, typing + 0.08)
	animate(life, function(t)
		line.MaxVisibleGraphemes = math.floor(math.clamp(t / typing, 0, 1) * length + 0.5)
		if answer and t >= resultAt then
			answer.TextTransparency = 0
		end
		local fadeFrom = life * 0.65
		if t > fadeFrom then
			local a = (t - fadeFrom) / (life - fadeFrom)
			line.TextTransparency = a
			if answer then
				answer.TextTransparency = a
			end
			panel.BackgroundTransparency = 0.3 + 0.7 * a
			stroke.Transparency = 0.35 + 0.65 * a
			gui.StudsOffsetWorldSpace = (options.offset or Vector3.new(0, 3.8, 0)) + UP * (a * 0.8)
		end
		return true
	end)
	Debris:AddItem(anchor, life + 0.3)
end

-- A big stamped word (the Ban Hammer's verdict)
local function stamp(kit, position: Vector3, text: string, color: Color3, life: number)
	local anchor = kit.Vfx.part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(position) })
	local gui = Instance.new("BillboardGui")
	gui.Name = "SNAdminStamp"
	gui.Size = UDim2.fromScale(#text * 0.9, 2.4)
	gui.LightInfluence = 0
	gui.MaxDistance = 200
	gui.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1.5, 1.5)
	label.Font = Enum.Font.Code
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = GOLD
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	gui.Parent = anchor
	-- Slams in from oversized, holds, then fades
	animate(life, function(t)
		local a = easeOut(t / 0.12)
		label.Size = UDim2.fromScale(1.5 - 0.5 * a, 1.5 - 0.5 * a)
		if t > life * 0.6 then
			local fade = (t - life * 0.6) / (life * 0.4)
			label.TextTransparency = fade
			label.TextStrokeTransparency = 0.2 + 0.8 * fade
		end
		return true
	end)
	Debris:AddItem(anchor, life + 0.3)
end

-- Lock-on brackets and markers ------------------------------------------------------------------

-- Four crimson corner brackets closing in on a target for `duration`
local function reticle(kit, target: Model?, duration: number, color: Color3?)
	local root = rootOf(target)
	if not root then
		return
	end
	local tint = color or CRIMSON_HOT
	local gui = Instance.new("BillboardGui")
	gui.Name = "SNAdminReticle"
	gui.Size = UDim2.fromScale(7, 8)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.MaxDistance = 160
	gui.Adornee = root
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local bars = {}
	for _, corner in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		for _, horizontal in { true, false } do
			local bar = Instance.new("Frame")
			bar.BorderSizePixel = 0
			bar.BackgroundColor3 = tint
			bar.AnchorPoint = corner
			bar.Position = UDim2.fromScale(corner.X, corner.Y)
			bar.Size = if horizontal then UDim2.new(0.22, 0, 0, 3) else UDim2.new(0, 3, 0.18, 0)
			bar.Parent = frame
			table.insert(bars, bar)
		end
	end
	gui.Parent = kit.Vfx.part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = root.CFrame })
	local life = math.max(0.2, duration) + 0.25
	animate(life, function(t)
		if not root.Parent then
			return false
		end
		local close = easeOut(t / math.max(0.1, duration))
		local size = 1.45 - 0.45 * close
		frame.Size = UDim2.fromScale(size, size)
		local fade = if t > duration then (t - duration) / 0.25 else 0
		for _, bar in bars do
			bar.BackgroundTransparency = math.clamp(fade, 0, 1)
		end
		return true
	end, function()
		gui:Destroy()
	end)
end

-- A gold-and-crimson floor sigil that grows in and turns. Returns stop().
-- opts: { color, accent, inner, ticks, spin, grow }
local function floorSigil(kit, center: Vector3, radius: number, life: number, opts: { [string]: any }?): () -> ()
	local options = opts or {}
	local outer = newGroup(kit)
	addRing(outer, radius, 0.08, 0.24, options.color or GOLD, 0.1, 30)
	addTicks(outer, radius - 0.55, 0.08, options.ticks or 12, 0.7, options.accent or CRIMSON_HOT, 0.15)
	local inner = newGroup(kit)
	addRing(inner, radius * (options.inner or 0.64), 0.09, 0.14, options.color or GOLD, 0.35, 22, 0.4)
	local spin = num(options.spin, 0.5)
	local grow = num(options.grow, 0.25)
	local base = CFrame.new(center)
	return animate(life, function(t)
		local s = 0.35 + 0.65 * easeOut(t / grow)
		outer:place(base * CFrame.Angles(0, t * spin, 0), s)
		inner:place(base * CFrame.Angles(0, -t * spin * 1.6, 0), s)
		local fade = if t > life - 0.3 then (life - t) / 0.3 else 1
		outer:alpha(fade)
		inner:alpha(fade)
		return true
	end, function()
		outer:fade(0.2)
		inner:fade(0.2)
	end)
end

-- Doorways: the station opening a door for a teleport ----------------------------------------------

-- A gold door frame standing at `floor`, opening upward, then folding to a line
local function doorway(kit, floor: Vector3, facing: Vector3, life: number)
	local frame = CFrame.lookAt(floor, floor + facing)
	local width, height = 3, 6.2
	local door = newGroup(kit)
	local left = door:add(CFrame.new(-width / 2, 0, 0), { Size = Vector3.new(0.16, 0.1, 0.16), Color = GOLD, Transparency = 0 })
	local right = door:add(CFrame.new(width / 2, 0, 0), { Size = Vector3.new(0.16, 0.1, 0.16), Color = GOLD, Transparency = 0 })
	local lintel = door:add(CFrame.new(0, 0, 0), { Size = Vector3.new(width + 0.16, 0.16, 0.16), Color = GOLD, Transparency = 0 })
	local sill = door:add(CFrame.new(0, 0.05, 0), { Size = Vector3.new(width + 0.4, 0.06, 0.5), Color = CRIMSON, Transparency = 0.1 })
	local field = door:add(CFrame.new(0, 0, 0), { Size = Vector3.new(width - 0.2, 0.1, 0.04), Color = WHITE, Transparency = 0.72 })
	local light = kit.Vfx.glow(field, GOLD, 10, 1.2, life)
	local _ = light
	animate(life, function(t)
		-- Opens fast, holds, then closes to a bright line
		local open = easeOut(t / 0.14)
		local closing = math.clamp((t - (life - 0.18)) / 0.18, 0, 1)
		local h = math.max(0.1, height * open * (1 - closing * 0.95))
		local w = width * (1 - closing * 0.9)
		left.Size = Vector3.new(0.16, h, 0.16)
		right.Size = Vector3.new(0.16, h, 0.16)
		left.CFrame = frame * CFrame.new(-w / 2, h / 2, 0)
		right.CFrame = frame * CFrame.new(w / 2, h / 2, 0)
		lintel.Size = Vector3.new(w + 0.16, 0.16, 0.16)
		lintel.CFrame = frame * CFrame.new(0, h, 0)
		sill.CFrame = frame * CFrame.new(0, 0.05, 0)
		field.Size = Vector3.new(math.max(0.05, w - 0.2), h, 0.04)
		field.CFrame = frame * CFrame.new(0, h / 2, 0)
		field.Transparency = 0.72 - 0.4 * closing
		return true
	end, function()
		door:fade(0.12)
	end)
end

-- Padlocks: gold body, crimson keyhole, a shackle that clicks shut ------------------------------------

local function padlock(kit, scale: number?)
	local s = scale or 1
	local body = newGroup(kit)
	body:add(CFrame.new(0, 0, 0), { Size = Vector3.new(1.1, 0.9, 0.4) * s, Color = GOLD, Material = Enum.Material.Metal, Transparency = 0 })
	body:add(CFrame.new(0, 0, -0.21 * s), { Size = Vector3.new(0.92, 0.72, 0.04) * s, Color = GOLD_DEEP, Transparency = 0.2 })
	body:add(CFrame.new(0, 0.08 * s, -0.24 * s), { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.24 * s, Color = CRIMSON_HOT, Transparency = 0 })
	body:add(CFrame.new(0, -0.1 * s, -0.24 * s), { Size = Vector3.new(0.1, 0.26, 0.04) * s, Color = CRIMSON_HOT, Transparency = 0 })
	local shackle = newGroup(kit)
	shackle:add(CFrame.new(-0.33 * s, 0.68 * s, 0), { Size = Vector3.new(0.14, 0.5, 0.14) * s, Color = STEEL, Material = Enum.Material.Metal, Transparency = 0 })
	shackle:add(CFrame.new(0.33 * s, 0.68 * s, 0), { Size = Vector3.new(0.14, 0.5, 0.14) * s, Color = STEEL, Material = Enum.Material.Metal, Transparency = 0 })
	shackle:add(CFrame.new(0, 0.93 * s, 0), { Size = Vector3.new(0.8, 0.14, 0.14) * s, Color = STEEL, Material = Enum.Material.Metal, Transparency = 0 })
	local lock = { body = body, shackle = shackle, open = 1 }
	-- open: 0 (shut) to 1 (raised)
	function lock.place(cframe: CFrame)
		body:place(cframe)
		shackle:place(cframe * CFrame.new(0, lock.open * 0.32 * s, 0))
	end
	function lock.alpha(value: number)
		body:alpha(value)
		shackle:alpha(value)
	end
	function lock.fade(duration: number)
		body:fade(duration)
		shackle:fade(duration)
	end
	return lock
end

-- Server-built constructs fade in here, on this screen only (the server's parts
-- never change, so local transparency is safe). Lower parts first, like a shutter.
local function reveal(kit, model: any, duration: number, order: ((BasePart) -> number)?)
	local target = modelOf(model)
	if not target then
		return
	end
	local parts = {}
	for _, item in target:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(parts, { part = item, goal = item.Transparency, key = if order then order(item) else item.Position.Y })
			item.Transparency = 1
		end
	end
	if #parts == 0 then
		return
	end
	local low, high = math.huge, -math.huge
	for _, entry in parts do
		low = math.min(low, entry.key)
		high = math.max(high, entry.key)
	end
	local spread = math.max(0.01, high - low)
	animate(duration + 0.1, function(t)
		for _, entry in parts do
			if entry.part.Parent then
				local delay = (entry.key - low) / spread * duration * 0.6
				local a = easeOut((t - delay) / (duration * 0.4))
				entry.part.Transparency = 1 - (1 - entry.goal) * a
			end
		end
		return true
	end, function()
		for _, entry in parts do
			if entry.part.Parent then
				entry.part.Transparency = entry.goal
			end
		end
	end)
end

-- Fragments that drift and fade (walls, cells and fields breaking up)
local function fragments(kit, center: Vector3, spread: Vector3, count: number, color: Color3, speed: number)
	local pieces = if kit.Vfx.reduced() then math.ceil(count / 3) else count
	for _ = 1, pieces do
		local offset = Vector3.new((math.random() - 0.5) * spread.X, (math.random() - 0.5) * spread.Y, (math.random() - 0.5) * spread.Z)
		local part = kit.Vfx.part({
			Size = Vector3.new(0.12 + math.random() * 0.3, 0.06, 0.12 + math.random() * 0.3),
			CFrame = CFrame.new(center + offset) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Color = color,
			Transparency = 0.15,
		})
		local drift = (offset.Magnitude > 0.01 and offset.Unit or UP) * speed * (0.4 + math.random() * 0.6) + UP * speed * 0.3
		TweenService:Create(part, TweenInfo.new(0.7 + math.random() * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(center + offset + drift) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Transparency = 1,
		}):Play()
		Debris:AddItem(part, 1.3)
	end
end

local function glints(kit, position: Vector3, color: Color3, count: number, speed: number)
	kit.Vfx.burst(position, {
		colors = ColorSequence.new(WHITE, color),
		texture = SPARKLE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		transparency = NumberSequence.new(0, 1),
		lifetime = NumberRange.new(0.4, 0.9),
		speed = NumberRange.new(speed * 0.5, speed),
		drag = 4,
		count = count,
	})
end

local function dust(kit, position: Vector3, radius: number, count: number)
	kit.Vfx.burst(position + UP * 0.4, {
		color = DUST,
		lightEmission = 0,
		texture = SMOKE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.5) }),
		transparency = NumberSequence.new(0.45, 1),
		lifetime = NumberRange.new(0.6, 1.2),
		speed = NumberRange.new(radius * 0.8, radius * 1.6),
		spread = Vector2.new(5, 180),
		drag = 5,
		count = count,
	})
end

-- Poses ----------------------------------------------------------------------------------------

local registered = false
local function registerPoses(Poser)
	if registered then
		return
	end
	registered = true
	Poser.register("AdminPoint", { RightShoulder = { 92, 0, -4 }, RightElbow = { 4, 0, 0 }, LeftShoulder = { 12, 0, 12 }, Torso = { -4, 22, 0 }, Neck = { 0, -14, 0 } })
	Poser.register("AdminRaise", { RightShoulder = { 150, 0, -30 }, LeftShoulder = { 150, 0, 30 }, RightElbow = { 10, 0, 0 }, LeftElbow = { 10, 0, 0 }, Torso = { -12, 0, 0 }, Neck = { -12, 0, 0 } })
	Poser.register("AdminPush", { RightShoulder = { 88, 0, -12 }, LeftShoulder = { 88, 0, 12 }, RightElbow = { 6, 0, 0 }, LeftElbow = { 6, 0, 0 }, Torso = { -6, 0, 0 } })
	Poser.register("AdminFloat", {
		RightShoulder = { 22, 0, -42 },
		LeftShoulder = { 22, 0, 42 },
		RightElbow = { 14, 0, 0 },
		LeftElbow = { 14, 0, 0 },
		Torso = { -6, 0, 0 },
		RightHip = { 10, 0, 0 },
		LeftHip = { -6, 0, 0 },
		RightKnee = { -14, 0, 0 },
		LeftKnee = { -34, 0, 0 },
	})
	Poser.register("AdminHammerHold", { RightShoulder = { 172, 0, -12 }, LeftShoulder = { 172, 0, 12 }, RightElbow = { 28, 0, 0 }, LeftElbow = { 28, 0, 0 }, Torso = { -22, 0, 0 }, Neck = { -14, 0, 0 } })
	if not Poser.registerSequence then
		return
	end
	-- A command: the hand draws back to the shoulder, then points, then settles
	Poser.registerSequence("AdminCommand", {
		{ t = 0.24, pose = { RightShoulder = { 34, 0, -26 }, RightElbow = { 96, 0, 0 }, LeftShoulder = { 20, 0, 16 }, LeftElbow = { 40, 0, 0 }, Torso = { 4, -18, 0 }, Neck = { 0, 10, 0 } }, easing = "Out" },
		{ t = 0.4, pose = { RightShoulder = { 92, 0, -4 }, RightElbow = { 4, 0, 0 }, LeftShoulder = { 12, 0, 12 }, LeftElbow = { 20, 0, 0 }, Torso = { -4, 22, 0 }, Neck = { 0, -14, 0 } }, easing = "Snap" },
		{ t = 0.5, pose = { RightShoulder = { 90, 0, -4 }, RightElbow = { 6, 0, 0 }, LeftShoulder = { 12, 0, 12 }, LeftElbow = { 20, 0, 0 }, Torso = { -3, 20, 0 }, Neck = { 0, -12, 0 } } },
		{ t = 0.85, pose = { RightShoulder = { 30, 0, -8 }, RightElbow = { 24, 0, 0 }, Torso = { 0, 6, 0 } }, easing = "InOut" },
	}, { startup = 0.4, active = 0.1, recovery = 0.35, upper = true })
	-- Both palms push out (fling)
	Poser.registerSequence("AdminShove", {
		{ t = 0.26, pose = { RightShoulder = { 40, 0, -20 }, LeftShoulder = { 40, 0, 20 }, RightElbow = { 100, 0, 0 }, LeftElbow = { 100, 0, 0 }, Torso = { 8, 0, 0 }, RightHip = { 14, 0, 0 }, RightKnee = { -18, 0, 0 } }, easing = "Out" },
		{ t = 0.4, pose = { RightShoulder = { 88, 0, -12 }, LeftShoulder = { 88, 0, 12 }, RightElbow = { 6, 0, 0 }, LeftElbow = { 6, 0, 0 }, Torso = { -6, 0, 0 }, LeftHip = { -12, 0, 0 } }, easing = "Snap" },
		{ t = 0.9, pose = { RightShoulder = { 30, 0, -10 }, LeftShoulder = { 30, 0, 10 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 20, 0, 0 } }, easing = "InOut" },
	}, { startup = 0.4, active = 0.05, recovery = 0.45 })
	-- Walls and rings: knees soften, then both arms sweep up as the station answers
	Poser.registerSequence("AdminSummon", {
		{ t = 0.22, pose = { RightShoulder = { 30, 0, -36 }, LeftShoulder = { 30, 0, 36 }, RightElbow = { 72, 0, 0 }, LeftElbow = { 72, 0, 0 }, Torso = { 10, 0, 0 }, Root = { 0, 0, 0, 0, -0.25, 0 }, RightHip = { 18, 0, 0 }, LeftHip = { 18, 0, 0 }, RightKnee = { -26, 0, 0 }, LeftKnee = { -26, 0, 0 } }, easing = "Out" },
		{ t = 0.4, pose = { RightShoulder = { 150, 0, -30 }, LeftShoulder = { 150, 0, 30 }, RightElbow = { 10, 0, 0 }, LeftElbow = { 10, 0, 0 }, Torso = { -12, 0, 0 }, Neck = { -12, 0, 0 } }, easing = "Snap" },
		{ t = 0.5, pose = { RightShoulder = { 146, 0, -32 }, LeftShoulder = { 146, 0, 32 }, RightElbow = { 12, 0, 0 }, LeftElbow = { 12, 0, 0 }, Torso = { -10, 0, 0 }, Neck = { -10, 0, 0 } } },
		{ t = 0.9, pose = { RightShoulder = { 20, 0, -10 }, LeftShoulder = { 20, 0, 10 } }, easing = "InOut" },
	}, { startup = 0.4, active = 0.1, recovery = 0.4 })
	-- Teleport: a quick dip, then standing tall on the far side
	Poser.registerSequence("AdminBlink", {
		{ t = 0.1, pose = { Torso = { 18, 0, 0 }, Root = { 0, 0, 0, 0, -0.4, 0 }, RightShoulder = { -20, 0, 22 }, LeftShoulder = { -20, 0, -22 }, RightHip = { 26, 0, 0 }, LeftHip = { 26, 0, 0 }, RightKnee = { -40, 0, 0 }, LeftKnee = { -40, 0, 0 } }, easing = "Out" },
		{ t = 0.2, pose = { Torso = { -8, 0, 0 }, RightShoulder = { 24, 0, -30 }, LeftShoulder = { 24, 0, 30 }, Neck = { -6, 0, 0 } }, easing = "Back" },
		{ t = 0.45, pose = {}, easing = "InOut" },
	}, { startup = 0.15, active = 0.05, recovery = 0.25 })
	-- The Ban Hammer: hands high through the leap, cocked back, then the slam
	Poser.registerSequence("AdminHammer", {
		{ t = 0.3, pose = { RightShoulder = { 170, 0, -12 }, LeftShoulder = { 170, 0, 12 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, Torso = { -20, 0, 0 }, Neck = { -14, 0, 0 }, RightHip = { -10, 0, 0 }, LeftHip = { 30, 0, 0 }, LeftKnee = { -50, 0, 0 } }, easing = "Out" },
		{ t = 1.42, pose = { RightShoulder = { 178, 0, -10 }, LeftShoulder = { 178, 0, 10 }, RightElbow = { 40, 0, 0 }, LeftElbow = { 40, 0, 0 }, Torso = { -30, 0, 0 }, Neck = { -18, 0, 0 }, RightHip = { -14, 0, 0 }, LeftHip = { 34, 0, 0 }, LeftKnee = { -56, 0, 0 } }, easing = "InOut" },
		{ t = 1.56, pose = { RightShoulder = { 70, 0, -8 }, LeftShoulder = { 70, 0, 8 }, RightElbow = { 4, 0, 0 }, LeftElbow = { 4, 0, 0 }, Torso = { 36, 0, 0 }, Neck = { 12, 0, 0 }, Root = { 0, 0, 0, 0, -0.45, 0 }, RightHip = { 42, 0, 0 }, LeftHip = { -12, 0, 0 }, RightKnee = { -62, 0, 0 } }, easing = "Snap" },
		{ t = 1.8, pose = { RightShoulder = { 66, 0, -8 }, LeftShoulder = { 66, 0, 8 }, Torso = { 32, 0, 0 }, Neck = { 10, 0, 0 }, Root = { 0, 0, 0, 0, -0.4, 0 }, RightHip = { 38, 0, 0 }, RightKnee = { -56, 0, 0 } } },
		{ t = 2.5, pose = {}, easing = "InOut" },
	}, { startup = 1.5, active = 0.15, recovery = 0.9 })
end

-- Which move each ability's cast plays (and the fallback pose without sequences)
local CAST = {
	Teleport = { "AdminBlink", "AdminRaise" },
	FreezeCommand = { "AdminCommand", "AdminPoint" },
	ForceField = { "AdminSummon", "AdminRaise" },
	SpeedCommand = { "AdminCommand", "AdminPoint" },
	Fly = { "AdminSummon", "AdminRaise" },
	Clone = { "AdminBlink", "AdminPoint" },
	Barrier = { "AdminSummon", "AdminRaise" },
	Jail = { "AdminCommand", "AdminPoint" },
	GravityCommand = { "AdminCommand", "AdminPoint" },
	Fling = { "AdminShove", "AdminPush" },
	ArenaBarrier = { "AdminSummon", "AdminRaise" },
	GravityField = { "AdminCommand", "AdminPoint" },
	TeleportSequence = { "AdminBlink", "AdminPoint" },
	AreaCommand = { "AdminSummon", "AdminRaise" },
	BanHammer = { "AdminHammer", "AdminHammerHold" },
}

local function castPose(kit, abilityId: string)
	local model = kit.model
	local entry = CAST[abilityId]
	if not model or not entry then
		return
	end
	local Poser = kit.Poser
	registerPoses(Poser)
	local def = kit.ability(abilityId)
	local startup = num(kit.data.startup, if def then def.startup or 0.2 else 0.2)
	local active = num(kit.data.active, if def then def.active or 0.05 else 0.05)
	local recovery = if def then def.recovery or 0.3 else 0.3
	if Poser.sequence and Poser.Sequences and Poser.Sequences[entry[1]] then
		Poser.sequence(model, entry[1], 1, { timing = { startup = startup, active = active, recovery = recovery } })
	else
		Poser.play(model, entry[2], math.min(0.15, startup * 0.5), math.max(0.1, startup + active), 0.25)
	end
	-- A small gold glint in the commanding hand
	local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		kit.Vfx.glow(hand, GOLD, 6, 1.2, math.max(0.3, startup + 0.1))
	end
end

Admin.predict = {}
for abilityId in CAST do
	Admin.predict[abilityId] = function(kit)
		castPose(kit, abilityId)
	end
end

function Admin.onCast(kit)
	local abilityId = kit.data.ability
	if typeof(abilityId) == "string" then
		castPose(kit, abilityId)
	end
end

local fx = {}
Admin.fx = fx

-- Shared command moments -------------------------------------------------------------------------

local function commandLine(kit, data, result: string?, opts: { [string]: any }?)
	local command = if typeof(data.command) == "string" then data.command else ";cmd"
	local target = modelOf(data.target)
	local text = if target and typeof(data.name) == "string" then `{command} {data.name}` else command
	if kit.root then
		commandText(kit, kit.root, text, result, opts)
	end
end

function fx.CommandFizzle(kit)
	local data = kit.data
	local reason = if data.reason == "Lost" then "TARGET LOST" else "NO TARGET"
	commandLine(kit, data, reason, { resultColor = CRIMSON_HOT, life = 1.3, resultDelay = 0.15 })
	if kit.root then
		kit.Vfx.groundRing((feetOf(kit.root) :: Vector3) + UP * 0.1, STEEL, 1, 4, 0.3)
	end
	local target = modelOf(data.target)
	if rootOf(target) then
		kit.Vfx.flash(target :: Model, STEEL, 0.15)
	end
end

-- The command reaches its target: a bright line of light and a packet riding it
function fx.CommandExecute(kit)
	local data = kit.data
	local target = modelOf(data.target)
	local targetRoot = rootOf(target)
	local from = vec(data.from) or (if kit.root then kit.root.Position else nil)
	local to = if targetRoot then targetRoot.Position else vec(data.to)
	if not from or not to then
		return
	end
	local hand = kit.model and (kit.model:FindFirstChild("RightHand") or kit.model:FindFirstChild("Right Arm"))
	local start = if hand and hand:IsA("BasePart") then hand.Position else from + UP * 0.8
	kit.Vfx.beam(start, to, GOLD, 0.14, 0.22)
	kit.Vfx.beam(start, to, WHITE, 0.05, 0.12)
	local packet = kit.Vfx.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, CFrame = CFrame.new(start), Color = WHITE, Transparency = 0 })
	animate(0.12, function(t)
		packet.CFrame = CFrame.new(start:Lerp(to, easeIn(t / 0.1)))
		return true
	end, function()
		packet:Destroy()
	end)
	task.delay(0.09, function()
		glints(kit, to, GOLD, 10, 14)
	end)
	kit.Vfx.sound("LightSwing", start)
end

-- Blocked, dodged or parried: the station refuses
function fx.CommandDenied(kit)
	local data = kit.data
	if kit.root then
		commandText(kit, kit.root, "DENIED", nil, { color = CRIMSON_HOT, life = 1, offset = Vector3.new(0, 4.9, 0), scale = 0.8 })
	end
	local targetRoot = rootOf(modelOf(data.target))
	if targetRoot then
		kit.Vfx.ring(CFrame.new(targetRoot.Position), 2.2, CRIMSON_HOT, 0.12, 0.3, 3.2)
	end
	kit.Vfx.sound("Block", if kit.root then kit.root.Position else Vector3.zero)
end

-- Degree 1 ----------------------------------------------------------------------------------------

function fx.TeleportOpen(kit)
	local data = kit.data
	local from, to = vec(data.from), vec(data.to)
	if not from or not to then
		return
	end
	local duration = math.clamp(num(data.duration, 0.15), 0.05, 1)
	local facing = flatUnit(to - from) or Vector3.new(0, 0, -1)
	doorway(kit, from - UP * 2.95, facing, duration + 0.2)
	doorway(kit, to - UP * 2.95, facing, duration + 0.45)
	floorSigil(kit, to - UP * 2.9, 2.2, duration + 0.5, { ticks = 8, spin = 1.6, grow = 0.12 })
	if kit.root then
		commandText(kit, kit.root, ";tp", nil, { life = 1.1 })
	end
	kit.Vfx.glow(to, GOLD, 12, 1.4, duration + 0.3)
end

function fx.TeleportArrive(kit)
	local data = kit.data
	local from, to = vec(data.from), vec(data.to)
	if not from or not to then
		return
	end
	local model = kit.model
	if model then
		kit.Vfx.ghostAt(model, CFrame.new(from) * (if kit.root then kit.root.CFrame.Rotation else CFrame.identity), GOLD, 0.4)
		kit.Vfx.flash(model, WHITE, 0.2)
	end
	-- The route lights up along the floor and fades from the start
	local floorFrom, floorTo = from - UP * 2.85, to - UP * 2.85
	local length = (floorTo - floorFrom).Magnitude
	local dashes = math.clamp(math.floor(length / 2), 1, if kit.Vfx.reduced() then 6 else 12)
	for index = 1, dashes do
		local a = (index - 0.5) / dashes
		local point = floorFrom:Lerp(floorTo, a)
		local dash = kit.Vfx.part({
			Size = Vector3.new(0.18, 0.05, math.min(1.2, length / dashes * 0.6)),
			CFrame = CFrame.lookAt(point, point + (floorTo - floorFrom)),
			Color = GOLD,
			Transparency = 0.2,
		})
		kit.Vfx.fade(dash, 0.25 + a * 0.35, { Transparency = 1 })
	end
	glints(kit, from, GOLD, 12, 10)
	glints(kit, to, WHITE, 16, 14)
	kit.Vfx.shockwave(to - UP * 2.6, GOLD, 1, 6, 0.3)
	kit.Vfx.sound("Dodge", to)
	if kit.isLocal then
		kit.shake(0.4, 0.12)
	end
end

function fx.TeleportFail(kit)
	local position = vec(kit.data.position) or (if kit.root then kit.root.Position else nil)
	if not position then
		return
	end
	commandText(kit, position, ";tp", "NO SAFE SPOT", { resultColor = CRIMSON_HOT, life = 1.2 })
	kit.Vfx.groundRing(position - UP * 2.8, CRIMSON, 1, 4, 0.35)
	kit.Vfx.sound("Block", position)
end

function fx.FreezeCast(kit)
	local data = kit.data
	local duration = math.clamp(num(data.duration, 0.45), 0.1, 2)
	commandLine(kit, data, nil, { life = duration + 0.9 })
	local target = modelOf(data.target)
	reticle(kit, target, duration)
	local root = rootOf(target)
	if root then
		floorSigil(kit, (feetOf(root) :: Vector3) + UP * 0.05, 2.6, duration + 0.2, { color = CRIMSON_HOT, accent = GOLD, spin = 2, grow = duration })
	end
end

-- Frozen: a white-gold lattice shell, a closed padlock overhead, a frost glow
function fx.FreezeLock(kit)
	local data = kit.data
	local target = modelOf(data.target)
	local root = rootOf(target)
	if not target or not root then
		return
	end
	local duration = math.clamp(num(data.duration, 1.2), 0.1, 3)
	if kit.Poser.freeze then
		kit.Poser.freeze(target, duration)
	end
	local shell = newGroup(kit)
	local bars = if kit.Vfx.reduced() then 4 else 6
	for index = 0, bars - 1 do
		local angle = index / bars * math.pi * 2 + math.pi / bars
		shell:add(CFrame.Angles(0, angle, 0) * CFrame.new(0, -0.2, -1.7), { Size = Vector3.new(0.07, 5.4, 0.07), Color = FROST, Transparency = 0.25 })
	end
	for _, y in { -2.6, -0.2, 2.2 } do
		addRing(shell, 1.7, y, 0.07, GOLD, 0.3, 12)
	end
	local lock = padlock(kit, 0.9)
	lock.open = 1
	local highlight = Instance.new("Highlight")
	highlight.FillColor = FROST
	highlight.FillTransparency = 0.65
	highlight.OutlineColor = GOLD
	highlight.OutlineTransparency = 0.2
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = target
	commandText(kit, root, "LOCKED", nil, { color = WHITE, life = math.min(1.4, duration + 0.4), offset = Vector3.new(0, 5.2, 0), scale = 0.75 })
	kit.Vfx.sound("Block", root)
	local stopped = false
	local stop = animate(duration + 0.2, function(t)
		if not root.Parent then
			return false
		end
		local base = CFrame.new(root.Position)
		shell:place(base * CFrame.Angles(0, t * 0.3, 0), 0.8 + 0.2 * easeOut(t / 0.12))
		-- The shackle clicks shut right away
		lock.open = 1 - easeIn(t / 0.1)
		lock.place(CFrame.new(root.Position + UP * (4.1 + math.sin(t * 3) * 0.08)) * CFrame.Angles(0, t * 0.8, 0))
		return true
	end, function()
		stopped = true
		highlight:Destroy()
		local center = root.Position
		shell:destroy()
		lock.fade(0.3)
		fragments(kit, center, Vector3.new(3, 5, 3), 14, FROST, 4)
		glints(kit, center + UP * 2, GOLD, 8, 6)
	end)
	kit.keep(function()
		if not stopped then
			stop()
		end
	end)
end

-- The classic force field, in gold: a living hex sphere that follows Admin
function fx.ForceField(kit)
	local root = kit.root
	if not root then
		return
	end
	local data = kit.data
	local duration = math.clamp(num(data.duration, 3), 0.1, 8)
	local window = math.clamp(num(data.window, 0.5), 0, 2)
	local sphere = kit.Vfx.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 7, CFrame = root.CFrame, Color = GOLD, Material = Enum.Material.ForceField, Transparency = 0 })
	local core = kit.Vfx.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 6.6, CFrame = root.CFrame, Color = WHITE, Transparency = 0.94 })
	local rim = newGroup(kit)
	addRing(rim, 3.3, 0, 0.12, CRIMSON_HOT, 0.1, 24)
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 9
	light.Brightness = 0.8
	light.Parent = core
	commandText(kit, root, ";ff", "FIELD UP", { life = 1.3 })
	kit.Vfx.sound("Parry", root)
	local stopped = false
	local stop = animate(duration + 0.3, function(t)
		if not root.Parent then
			return false
		end
		local appear = easeOut(t / 0.15)
		local breathe = 1 + math.sin(t * 4) * 0.02
		local size = 7 * (0.6 + 0.4 * appear) * breathe
		sphere.Size = Vector3.one * size
		core.Size = Vector3.one * size * 0.94
		sphere.CFrame = root.CFrame
		core.CFrame = root.CFrame
		-- The counter window reads as a bright crimson band sweeping the sphere
		if t < window then
			rim:place(root.CFrame * CFrame.new(0, -2.6 + 5.2 * (t / math.max(0.05, window)), 0), size / 7)
			rim:alpha(1)
		else
			rim:alpha(0)
		end
		return true
	end, function()
		stopped = true
		local position = sphere.Position
		rim:destroy()
		kit.Vfx.fade(sphere, 0.25, { Size = sphere.Size * 1.25, Transparency = 1 })
		kit.Vfx.fade(core, 0.2, { Transparency = 1 })
		glints(kit, position, GOLD, 14, 10)
	end)
	kit.keep(function()
		if not stopped then
			stop()
		end
	end)
end

function fx.ForceFieldRepel(kit)
	local position = vec(kit.data.position) or (if kit.root then kit.root.Position else nil)
	if not position then
		return
	end
	local targetRoot = rootOf(modelOf(kit.data.target))
	local toward = if targetRoot then flatUnit(targetRoot.Position - position) else nil
	kit.Vfx.shockwave(position, GOLD, 4, 11, 0.3)
	kit.Vfx.ring(CFrame.lookAt(position, position + (toward or Vector3.new(0, 0, -1))), 2.5, WHITE, 0.2, 0.3, 6)
	glints(kit, position + (toward or Vector3.zero) * 3, GOLD, 22, 24)
	kit.Vfx.glow(position, GOLD, 14, 3, 0.15)
	kit.Vfx.sound("Parry", position)
	kit.shake(1.2, 0.2, position)
end

-- Speed: gold trails at the heels and chevrons stamped on the floor
function fx.SpeedUp(kit)
	local root = kit.root
	if not root then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 4), 0.1, 8)
	local low = Instance.new("Attachment")
	low.Name = "SNAdminSpeedLow"
	low.Position = Vector3.new(0, -2.6, 0.3)
	low.Parent = root
	local high = Instance.new("Attachment")
	high.Name = "SNAdminSpeedHigh"
	high.Position = Vector3.new(0, -1.6, 0.3)
	high.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = low
	trail.Attachment1 = high
	trail.Color = ColorSequence.new(GOLD, CRIMSON)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.25
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = root
	commandText(kit, root, ";speed", "OK", { life = 1.2 })
	glints(kit, root.Position - UP * 2.5, GOLD, 10, 8)
	local last = root.Position
	local stopped = false
	local stop = animate(duration, function(t)
		if not root.Parent then
			return false
		end
		-- A chevron every couple of studs travelled
		if (root.Position - last).Magnitude > 3 and not kit.Vfx.reduced() then
			local direction = flatUnit(root.Position - last) or Vector3.new(0, 0, -1)
			last = root.Position
			local floor = root.Position - UP * 2.9
			for _, side in { -1, 1 } do
				local arm = kit.Vfx.part({
					Size = Vector3.new(0.12, 0.05, 0.9),
					CFrame = CFrame.lookAt(floor, floor + direction) * CFrame.new(side * 0.32, 0, 0) * CFrame.Angles(0, side * math.rad(40), 0),
					Color = GOLD,
					Transparency = 0.25,
				})
				kit.Vfx.fade(arm, 0.5, { Transparency = 1 })
			end
		end
		local _ = t
		return true
	end, function()
		stopped = true
		trail.Enabled = false
		Debris:AddItem(trail, 0.4)
		Debris:AddItem(low, 0.4)
		Debris:AddItem(high, 0.4)
	end)
	kit.keep(function()
		if not stopped then
			stop()
		end
	end)
end

function fx.FlyWindup(kit)
	local root = kit.root
	if not root then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 0.2), 0.05, 1)
	commandText(kit, root, ";fly", "GRAVITY 0.2", { life = 1.4 })
	local floor = feetOf(root) :: Vector3
	kit.Vfx.groundRing(floor + UP * 0.1, GOLD, 6, 2, duration)
	glints(kit, floor, WHITE, 10, 6)
end

-- Flight: a turning sigil disc under the feet and light falling away beneath
function fx.Flight(kit)
	local root = kit.root
	local model = kit.model
	if not root or not model then
		return
	end
	registerPoses(kit.Poser)
	local duration = math.clamp(num(kit.data.duration, 3), 0.1, 8)
	local disc = newGroup(kit)
	addRing(disc, 1.6, 0, 0.14, GOLD, 0.1, 18)
	addRing(disc, 1.05, 0, 0.08, WHITE, 0.3, 12, 0.45)
	addTicks(disc, 1.6, 0, 4, 0.6, CRIMSON_HOT, 0.1)
	local anchor = Instance.new("Attachment")
	anchor.Name = "SNAdminFlight"
	anchor.Position = Vector3.new(0, -3, 0)
	anchor.Parent = root
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = SPARKLE
	motes.Color = ColorSequence.new(WHITE, GOLD)
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	motes.Transparency = NumberSequence.new(0.1, 1)
	motes.Lifetime = NumberRange.new(0.4, 0.7)
	motes.Speed = NumberRange.new(4, 7)
	motes.EmissionDirection = Enum.NormalId.Bottom
	motes.SpreadAngle = Vector2.new(20, 20)
	motes.Rate = if kit.Vfx.reduced() then 6 else 18
	motes.Parent = anchor
	kit.Poser.hold(model, "AdminFloat")
	local stopped = false
	local stop = animate(duration, function(t)
		if not root.Parent then
			return false
		end
		disc:place(CFrame.new(root.Position - UP * 3.05) * CFrame.Angles(0, t * 1.4, 0), 0.6 + 0.4 * easeOut(t / 0.2))
		return true
	end, function()
		stopped = true
		kit.Poser.release(model, "AdminFloat")
		motes.Enabled = false
		Debris:AddItem(anchor, 0.8)
		disc:fade(0.25)
	end)
	kit.keep(function()
		if not stopped then
			stop()
		end
	end)
end

-- The decoy: a projected copy of Admin that runs ahead, legs and arms swinging,
-- then deletes itself in a gold scan
local LIMB_SWING = {
	LeftUpperLeg = 1,
	LeftLowerLeg = 1,
	LeftFoot = 1,
	["Left Leg"] = 1,
	RightUpperLeg = -1,
	RightLowerLeg = -1,
	RightFoot = -1,
	["Right Leg"] = -1,
	LeftUpperArm = -0.7,
	LeftLowerArm = -0.7,
	LeftHand = -0.7,
	["Left Arm"] = -0.7,
	RightUpperArm = 0.7,
	RightLowerArm = 0.7,
	RightHand = 0.7,
	["Right Arm"] = 0.7,
}
local HINGE_PART = {
	LeftUpperLeg = "LeftUpperLeg",
	LeftLowerLeg = "LeftUpperLeg",
	LeftFoot = "LeftUpperLeg",
	RightUpperLeg = "RightUpperLeg",
	RightLowerLeg = "RightUpperLeg",
	RightFoot = "RightUpperLeg",
	LeftUpperArm = "LeftUpperArm",
	LeftLowerArm = "LeftUpperArm",
	LeftHand = "LeftUpperArm",
	RightUpperArm = "RightUpperArm",
	RightLowerArm = "RightUpperArm",
	RightHand = "RightUpperArm",
}

function fx.CloneDecoy(kit)
	local data = kit.data
	local model, root = kit.model, kit.root
	local from, to = vec(data.from), vec(data.to)
	if not model or not root or not from or not to then
		return
	end
	local run = math.clamp(num(data.run, 1.8), 0.3, 4)
	local direction = flatUnit(to - from) or flatUnit(vec(data.direction)) or Vector3.new(0, 0, -1)
	local rotation = CFrame.lookAt(Vector3.zero, direction).Rotation
	local pieces = {}
	for _, limb in model:GetDescendants() do
		local accessory = limb:FindFirstAncestorWhichIsA("Accessory")
		if limb:IsA("BasePart") and limb.Name ~= "HumanoidRootPart" and (limb.Parent == model or accessory) and string.sub(limb.Name, 1, 2) ~= "SN" then
			local copy = limb:Clone()
			for _, child in copy:GetChildren() do
				if not child:IsA("DataModelMesh") then
					child:Destroy()
				end
			end
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanQuery = false
			copy.CanTouch = false
			copy.CastShadow = false
			copy.Transparency = math.max(limb.Transparency, 0)
			copy.Parent = kit.Vfx.part({ Transparency = 1, Size = Vector3.one * 0.2 }).Parent
			local hingeName = HINGE_PART[limb.Name]
			local hingePart = hingeName and model:FindFirstChild(hingeName)
			local hinge = CFrame.identity
			if hingePart and hingePart:IsA("BasePart") then
				hinge = CFrame.new((root.CFrame:Inverse() * hingePart.CFrame * CFrame.new(0, hingePart.Size.Y / 2, 0)).Position)
			elseif LIMB_SWING[limb.Name] then
				hinge = CFrame.new((root.CFrame:Inverse() * limb.CFrame * CFrame.new(0, limb.Size.Y / 2, 0)).Position)
			end
			table.insert(pieces, { part = copy, offset = root.CFrame:Inverse() * limb.CFrame, swing = LIMB_SWING[limb.Name] or 0, hinge = hinge })
		end
	end
	if #pieces == 0 then
		return
	end
	local scanline = kit.Vfx.part({ Size = Vector3.new(3, 0.08, 1.4), CFrame = CFrame.new(from), Color = GOLD, Transparency = 1 })
	commandText(kit, root, ";clone", "DECOY OUT", { life = 1.2 })
	glints(kit, from, GOLD, 12, 8)
	local life = run + 0.45
	animate(life, function(t)
		local a = math.clamp(t / run, 0, 1)
		local travel = 1 - (1 - a) * (1 - a) * 0.15 - (1 - a) * 0.85 * (1 - a)
		local position = from:Lerp(to, math.clamp(travel, 0, 1))
		local stride = math.sin(t * 15)
		local base = CFrame.new(position + UP * math.abs(math.cos(t * 15)) * 0.25) * rotation * CFrame.Angles(math.rad(-8), 0, 0)
		local dissolve = math.clamp((t - run) / 0.45, 0, 1)
		-- A faint gold flicker now and then: the only tell
		local flicker = if math.floor(t * 6) % 7 == 0 then 0.35 else 0
		for _, piece in pieces do
			if piece.part.Parent then
				local swing = CFrame.Angles(math.rad(36 * stride * piece.swing * (1 - a * 0.6)), 0, 0)
				piece.part.CFrame = base * piece.hinge * swing * piece.hinge:Inverse() * piece.offset
				piece.part.Transparency = math.clamp(flicker + dissolve, 0, 1)
			end
		end
		if dissolve > 0 then
			scanline.Transparency = 0.1 + 0.9 * dissolve
			scanline.CFrame = CFrame.new(position + UP * (3 - 6 * dissolve)) * rotation
		end
		return true
	end, function()
		for _, piece in pieces do
			piece.part:Destroy()
		end
		scanline:Destroy()
		glints(kit, to, GOLD, 16, 8)
	end)
end

-- Admin's own fade while the decoy runs: a little gold shimmer, then back in view
function fx.CloneFade(kit)
	local root = kit.root
	if not root then
		return
	end
	local anchor = Instance.new("Attachment")
	anchor.Name = "SNAdminShimmer"
	anchor.Parent = root
	local shimmer = Instance.new("ParticleEmitter")
	shimmer.Texture = SPARKLE
	shimmer.Color = ColorSequence.new(GOLD)
	shimmer.LightEmission = 1
	shimmer.LightInfluence = 0
	shimmer.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
	shimmer.Transparency = NumberSequence.new(0.3, 1)
	shimmer.Lifetime = NumberRange.new(0.3, 0.6)
	shimmer.Speed = NumberRange.new(0.5, 1.5)
	shimmer.SpreadAngle = Vector2.new(180, 180)
	shimmer.Rate = if kit.Vfx.reduced() then 3 else 8
	shimmer.Parent = anchor
	kit.keep(function()
		shimmer.Enabled = false
		Debris:AddItem(anchor, 0.7)
		if root.Parent then
			glints(kit, root.Position, GOLD, 8, 5)
		end
	end)
end

-- Degree 2 ------------------------------------------------------------------------------------------

-- Where a wall will rise: a gold line on the floor and a flickering outline
function fx.BarrierCast(kit)
	local data = kit.data
	local base = vec(data.position)
	local facing = flatUnit(vec(data.direction))
	if not base or not facing then
		return
	end
	local width = math.clamp(num(data.width, 12), 1, 40)
	local height = math.clamp(num(data.height, 8), 1, 20)
	local duration = math.clamp(num(data.duration, 0.3), 0.05, 2)
	local frame = CFrame.lookAt(base, base + facing)
	local outline = newGroup(kit)
	outline:add(CFrame.new(0, 0.06, 0), { Size = Vector3.new(width, 0.05, 0.3), Color = GOLD, Transparency = 0 })
	for _, side in { -1, 1 } do
		outline:add(CFrame.new(side * width / 2, height / 2, 0), { Size = Vector3.new(0.08, height, 0.08), Color = GOLD, Transparency = 0.5 })
		outline:add(CFrame.new(side * (width / 2 - 0.4), 0.07, 0), { Size = Vector3.new(0.8, 0.06, 0.5), Color = CRIMSON_HOT, Transparency = 0 })
	end
	outline:add(CFrame.new(0, height, 0), { Size = Vector3.new(width, 0.08, 0.08), Color = GOLD, Transparency = 0.5 })
	if kit.root then
		commandText(kit, kit.root, ";wall", nil, { life = duration + 0.8 })
	end
	animate(duration + 0.1, function(t)
		outline:place(frame)
		outline:alpha(if math.floor(t * 20) % 3 == 0 then 0.5 else 1)
		return true
	end, function()
		outline:fade(0.12)
	end)
end

function fx.BarrierUp(kit)
	local data = kit.data
	local base = vec(data.position)
	local facing = flatUnit(vec(data.direction))
	if not base or not facing then
		return
	end
	local width = math.clamp(num(data.width, 12), 1, 40)
	local height = math.clamp(num(data.height, 8), 1, 20)
	reveal(kit, data.model, 0.3)
	-- A scan line runs up the new wall
	local frame = CFrame.lookAt(base, base + facing)
	local scan = kit.Vfx.part({ Size = Vector3.new(width, 0.18, 0.5), CFrame = frame, Color = WHITE, Transparency = 0 })
	animate(0.3, function(t)
		scan.CFrame = frame * CFrame.new(0, height * easeOut(t / 0.28), 0)
		scan.Transparency = t / 0.3
		return true
	end, function()
		scan:Destroy()
	end)
	for _, side in { -1, 1 } do
		local post = (frame * CFrame.new(side * width / 2, 0.4, 0)).Position
		kit.Vfx.sparks(post, GOLD, 10, 16)
	end
	dust(kit, base, width * 0.25, 12)
	kit.Vfx.glow(base + UP * height * 0.5, GOLD, width, 1.5, 0.3)
	kit.Vfx.sound("HeavyHit", base)
	kit.shake(0.8, 0.18, base)
	if kit.root then
		commandText(kit, kit.root, ";wall", "SEALED", { life = 1.2, offset = Vector3.new(0, 4.9, 0), scale = 0.8 })
	end
end

function fx.BarrierDown(kit)
	local data = kit.data
	local center = vec(data.position)
	local facing = flatUnit(vec(data.direction)) or Vector3.new(0, 0, -1)
	if not center then
		return
	end
	local width = math.clamp(num(data.width, 12), 1, 40)
	local height = math.clamp(num(data.height, 8), 1, 20)
	local frame = CFrame.lookAt(center, center + facing)
	if data.reason == "Broken" then
		-- Shot apart: glass and grid fly
		kit.Vfx.debris(center, if kit.Vfx.reduced() then 4 else 10, WHITE, Enum.Material.Glass, 30)
		fragments(kit, center, Vector3.new(width, height, 1), 22, GOLD, 6)
		kit.Vfx.sound("GuardBreak", center)
		kit.shake(0.8, 0.2, center)
	else
		-- Retracts: a line sweeps down and the grid lets go of the light
		local scan = kit.Vfx.part({ Size = Vector3.new(width, 0.14, 0.4), CFrame = frame * CFrame.new(0, height / 2, 0), Color = GOLD, Transparency = 0.1 })
		animate(0.35, function(t)
			scan.CFrame = frame * CFrame.new(0, height / 2 - height * easeIn(t / 0.35), 0)
			return true
		end, function()
			scan:Destroy()
		end)
		fragments(kit, center, Vector3.new(width, height, 0.4), 12, GOLD, 2)
	end
end

function fx.JailCast(kit)
	local data = kit.data
	local duration = math.clamp(num(data.duration, 0.5), 0.1, 2)
	commandLine(kit, data, nil, { life = duration + 0.9 })
	local target = modelOf(data.target)
	reticle(kit, target, duration)
	local root = rootOf(target)
	if root then
		local floor = feetOf(root) :: Vector3
		local ring = newGroup(kit)
		addRing(ring, 3.5, 0.08, 0.16, CRIMSON_HOT, 0.05, 16, 0.3)
		local lock = padlock(kit, 1.1)
		animate(duration + 0.15, function(t)
			ring:place(CFrame.new(floor) * CFrame.Angles(0, -t * 1.2, 0), 1.6 - 0.6 * easeOut(t / duration))
			lock.place(CFrame.new(root.Position + UP * 4.4) * CFrame.Angles(0, t * 2, 0))
			lock.alpha(easeOut(t / 0.2))
			return true
		end, function()
			ring:fade(0.1)
			lock.fade(0.1)
		end)
	end
end

-- The cell closes: bars drop from above, the lock clicks, the floor ring pulses
function fx.JailLock(kit)
	local data = kit.data
	local floor = vec(data.position)
	if not floor then
		return
	end
	local radius = math.clamp(num(data.radius, 3.5), 1, 10)
	local height = math.clamp(num(data.height, 6.5), 1, 12)
	local duration = math.clamp(num(data.duration, 3), 0.1, 6)
	reveal(kit, data.model, 0.12, function(part)
		return -part.Position.Y
	end)
	local drops = newGroup(kit)
	local bars = if kit.Vfx.reduced() then 4 else 8
	for index = 0, bars - 1 do
		local angle = index / bars * math.pi * 2
		drops:add(CFrame.new(math.cos(angle) * radius, height / 2, math.sin(angle) * radius), { Size = Vector3.new(0.3, height, 0.3), Color = GOLD, Transparency = 0.2 })
	end
	animate(0.2, function(t)
		drops:place(CFrame.new(floor + UP * (height * (1 - easeIn(t / 0.12)))))
		drops:alpha(1 - math.clamp((t - 0.12) / 0.08, 0, 1))
		return true
	end, function()
		drops:destroy()
	end)
	task.delay(0.12, function()
		dust(kit, floor, radius, 14)
		kit.Vfx.groundRing(floor + UP * 0.12, CRIMSON_HOT, radius * 2, radius * 2.6, 0.35)
		kit.Vfx.sparks(floor + UP * 0.3, GOLD, 16, 18)
		kit.Vfx.sound("Block", floor)
		kit.shake(1, 0.2, floor)
	end)
	commandText(kit, floor + UP * 1, ";jail", "CONTAINED", { life = 1.5, offset = Vector3.new(0, height + 0.6, 0) })
	-- The padlock hangs over the cell until it opens
	local lock = padlock(kit, 1.3)
	local stopped = false
	local stop = animate(duration + 0.2, function(t)
		lock.open = 1 - easeIn((t - 0.12) / 0.1)
		lock.place(CFrame.new(floor + UP * (height + 1.4 + math.sin(t * 2.4) * 0.12)) * CFrame.Angles(0, t * 0.9, 0))
		return true
	end, function()
		stopped = true
		lock.open = 1
		lock.place(CFrame.new(floor + UP * (height + 1.6)))
		lock.fade(0.35)
	end)
	kit.keep(function()
		if not stopped then
			stop()
		end
	end)
end

function fx.JailOpen(kit)
	local data = kit.data
	local floor = vec(data.position)
	if not floor then
		return
	end
	local radius = math.clamp(num(data.radius, 3.5), 1, 10)
	local height = math.clamp(num(data.height, 6.5), 1, 12)
	local center = floor + UP * height / 2
	if data.reason == "Escaped" or data.reason == "Broken" then
		-- Broken out: bars burst outward
		fragments(kit, center, Vector3.new(radius * 2, height, radius * 2), 24, STEEL, 9)
		kit.Vfx.shockwave(center, CRIMSON_HOT, 2, radius * 3, 0.3)
		kit.Vfx.sound("GuardBreak", center)
		kit.shake(1, 0.2, center)
		commandText(kit, center, "CELL BREACHED", nil, { color = CRIMSON_HOT, life = 1.1, offset = Vector3.new(0, height / 2 + 1, 0), scale = 0.8 })
	else
		fragments(kit, center, Vector3.new(radius * 2, height, radius * 2), 10, GOLD, 2)
		kit.Vfx.groundRing(floor + UP * 0.1, GOLD, radius * 2.4, radius * 1.2, 0.4)
	end
end

function fx.GravityCast(kit)
	local data = kit.data
	local duration = math.clamp(num(data.duration, 0.35), 0.1, 2)
	commandLine(kit, data, nil, { life = duration + 0.9 })
	local target = modelOf(data.target)
	reticle(kit, target, duration, GOLD)
	local root = rootOf(target)
	if root then
		floorSigil(kit, (feetOf(root) :: Vector3) + UP * 0.05, 2.2, duration + 0.2, { spin = -2, grow = duration })
	end
end

-- Chevrons pressing down (heavy) or drifting up (floating) around a target
local function gravityMarks(kit, root: BasePart, duration: number, downward: boolean, label: string)
	local marks = newGroup(kit)
	local count = if kit.Vfx.reduced() then 2 else 3
	for index = 1, count do
		for _, side in { -1, 1 } do
			marks:add(CFrame.new(side * 0.42, index * 0.7, 0) * CFrame.Angles(0, 0, side * math.rad(if downward then 40 else -40)), {
				Size = Vector3.new(1, 0.1, 0.1),
				Color = if index == 1 then CRIMSON_HOT else GOLD,
				Transparency = 0.15,
			})
		end
	end
	local ring = newGroup(kit)
	addRing(ring, 1.9, 0, 0.12, if downward then CRIMSON_HOT else WHITE, 0.15, 16)
	commandText(kit, root, label, nil, { color = WHITE, life = math.min(1.5, duration), offset = Vector3.new(0, 5, 0), scale = 0.7 })
	local stopped = false
	local stop = animate(duration + 0.1, function(t)
		if not root.Parent then
			return false
		end
		local cycle = (t * 1.6) % 1
		local y = if downward then 5.6 - cycle * 1.4 else 3.6 + cycle * 1.4
		marks:place(CFrame.new(root.Position + UP * (y - 3)) * CFrame.Angles(0, t * 0.6, 0))
		marks:alpha(math.sin(cycle * math.pi))
		ring:place(CFrame.new(root.Position - UP * 2.9) * CFrame.Angles(0, -t, 0), if downward then 1 - 0.1 * math.sin(t * 8) else 1)
		return true
	end, function()
		stopped = true
		marks:fade(0.2)
		ring:fade(0.2)
	end)
	kit.keep(function()
		if not stopped then
			stop()
		end
	end)
end

function fx.GravityHeavy(kit)
	local root = rootOf(modelOf(kit.data.target))
	if not root then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 3), 0.1, 6)
	gravityMarks(kit, root, duration, true, string.format("G x%.1f", num(kit.data.magnitude, 1.8)))
	dust(kit, root.Position - UP * 2.8, 2, 8)
	kit.Vfx.sound("HeavyHit", root)
end

function fx.GravityFloat(kit)
	local root = rootOf(modelOf(kit.data.target))
	if not root then
		return
	end
	local duration = math.clamp(num(kit.data.duration, 2), 0.1, 6)
	gravityMarks(kit, root, duration, false, string.format("G x%.2f", num(kit.data.magnitude, 0.25)))
	glints(kit, root.Position, WHITE, 12, 4)
end

function fx.FlingCast(kit)
	local data = kit.data
	local duration = math.clamp(num(data.duration, 0.4), 0.1, 2)
	commandLine(kit, data, nil, { life = duration + 0.9 })
	local target = modelOf(data.target)
	reticle(kit, target, duration)
	local root = rootOf(target)
	if root and kit.root then
		-- An arrow on the floor beyond them shows where they're going
		local direction = flatUnit(root.Position - kit.root.Position) or Vector3.new(0, 0, -1)
		local tip = (feetOf(root) :: Vector3) + UP * 0.06 + direction * 3
		local arrow = newGroup(kit)
		for _, side in { -1, 1 } do
			for step = 0, 1 do
				arrow:add(CFrame.new(side * 0.5, 0, step * 1.1) * CFrame.Angles(0, side * math.rad(-40), 0), { Size = Vector3.new(0.16, 0.05, 1.4), Color = if step == 0 then CRIMSON_HOT else GOLD, Transparency = 0.1 })
			end
		end
		animate(duration + 0.1, function(t)
			arrow:place(CFrame.lookAt(tip, tip + direction) * CFrame.new(0, 0, -easeOut(t / duration) * 1.5))
			return true
		end, function()
			arrow:fade(0.15)
		end)
	end
end

function fx.FlingThrow(kit)
	local root = rootOf(modelOf(kit.data.target))
	if not root then
		return
	end
	kit.Vfx.shockwave(root.Position, GOLD, 2, 8, 0.25)
	glints(kit, root.Position, CRIMSON_HOT, 18, 22)
	local low = Instance.new("Attachment")
	low.Position = Vector3.new(0, -1.2, 0)
	low.Parent = root
	local high = Instance.new("Attachment")
	high.Position = Vector3.new(0, 1.2, 0)
	high.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = low
	trail.Attachment1 = high
	trail.Color = ColorSequence.new(CRIMSON_HOT, GOLD)
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Lifetime = 0.3
	trail.LightEmission = 1
	trail.Parent = root
	Debris:AddItem(trail, 0.8)
	Debris:AddItem(low, 0.8)
	Debris:AddItem(high, 0.8)
	kit.Vfx.sound("HeavyHit", root)
	kit.shake(1.4, 0.22, root.Position)
end

-- Degree 3 --------------------------------------------------------------------------------------------

-- The lockdown ring traces itself around the floor before the walls rise
function fx.LockdownCast(kit)
	local data = kit.data
	local center = vec(data.position)
	if not center then
		return
	end
	local radius = math.clamp(num(data.radius, 18), 2, 40)
	local duration = math.clamp(num(data.duration, 0.7), 0.1, 2)
	local trace = newGroup(kit)
	addRing(trace, radius, 0.08, 0.3, GOLD, 0, 40)
	addTicks(trace, radius + 0.9, 0.08, 16, 0.9, CRIMSON_HOT, 0.1)
	addTicks(trace, radius - 0.9, 0.08, 16, 0.9, CRIMSON_HOT, 0.1)
	local items = trace.items
	if kit.root then
		commandText(kit, kit.root, ";lockdown", "SEALING", { life = duration + 1, resultDelay = duration * 0.5 })
	end
	animate(duration + 0.1, function(t)
		trace:place(CFrame.new(center))
		-- Pieces light up in order around the circle
		local reached = easeOut(t / duration)
		for index, item in items do
			local order = (index - 1) / #items
			item.part.Transparency = if order <= reached then item.transparency else 1
		end
		return true
	end, function()
		trace:fade(0.25)
	end)
	kit.Vfx.glow(center + UP * 3, CRIMSON, radius, 1, duration)
end

function fx.LockdownFizzle(kit)
	local center = vec(kit.data.position)
	if not center then
		return
	end
	local radius = math.clamp(num(kit.data.radius, 18), 2, 40)
	kit.Vfx.groundRing(center + UP * 0.1, STEEL, radius * 2, radius * 1.2, 0.4)
end

function fx.LockdownUp(kit)
	local data = kit.data
	local center = vec(data.position)
	if not center then
		return
	end
	local radius = math.clamp(num(data.radius, 18), 2, 40)
	local height = math.clamp(num(data.height, 9), 1, 20)
	local segments = math.clamp(math.floor(num(data.segments, 16)), 4, 32)
	local duration = math.clamp(num(data.duration, 4), 0.1, 8)
	-- The walls close like shutters, sweeping around the ring
	reveal(kit, data.model, 0.35, function(part)
		local offset = part.Position - center
		return (math.atan2(offset.Z, offset.X) + math.pi) / (math.pi * 2) * 10 + part.Position.Y * 0.01
	end)
	kit.Vfx.groundRing(center + UP * 0.1, GOLD, radius * 2, radius * 2.15, 0.5)
	kit.Vfx.shockwave(center + UP * 1, CRIMSON_HOT, 2, radius * 0.8, 0.4)
	kit.Vfx.screenFlash(CRIMSON, 0.25, 0.4)
	kit.Vfx.sound("HeavyHit", center)
	kit.shake(1.6, 0.3, center)
	commandText(kit, center, "ALL DOORS SEALED", nil, { color = CRIMSON_HOT, life = 1.8, offset = Vector3.new(0, height + 1.5, 0), scale = 1.3 })
	-- Alarm beacons sweep while it holds
	local sweeps = newGroup(kit)
	local step = math.pi * 2 / segments
	for index = 0, segments - 1, 4 do
		local angle = index * step
		local post = Vector3.new(math.cos(angle) * radius, height + 0.6, math.sin(angle) * radius)
		sweeps:add(CFrame.new(post), { Size = Vector3.new(2.4, 0.06, 0.5), Color = CRIMSON_HOT, Transparency = 0.45 })
	end
	local stopped = false
	local stop = animate(duration, function(t)
		for index, item in sweeps.items do
			if item.part.Parent then
				item.part.CFrame = CFrame.new(center + item.position) * CFrame.Angles(0, t * 5 + index, 0) * CFrame.new(1.1, 0, 0)
			end
		end
		return true
	end, function()
		stopped = true
		sweeps:fade(0.2)
	end)
	kit.keep(function()
		if not stopped then
			stop()
		end
	end)
end

function fx.LockdownEnd(kit)
	local data = kit.data
	local center = vec(data.position)
	if not center then
		return
	end
	local radius = math.clamp(num(data.radius, 18), 2, 40)
	local height = math.clamp(num(data.height, 9), 1, 20)
	local segments = math.clamp(math.floor(num(data.segments, 16)), 4, 32)
	local count = if kit.Vfx.reduced() then math.ceil(segments / 4) else segments
	for index = 0, count - 1 do
		local angle = (index + 0.5) / count * math.pi * 2
		local panel = center + Vector3.new(math.cos(angle) * radius, height / 2, math.sin(angle) * radius)
		fragments(kit, panel, Vector3.new(2, height, 2), 3, GOLD, 1.5)
	end
	kit.Vfx.groundRing(center + UP * 0.1, GOLD, radius * 2, radius * 2.3, 0.6)
	commandText(kit, center, "LOCKDOWN LIFTED", nil, { color = WHITE, life = 1.2, offset = Vector3.new(0, height + 1, 0) })
end

function fx.GravityFieldCast(kit)
	local data = kit.data
	local center = vec(data.position)
	if not center then
		return
	end
	local radius = math.clamp(num(data.radius, 10), 1, 30)
	local duration = math.clamp(num(data.duration, 0.45), 0.05, 2)
	floorSigil(kit, center + UP * 0.02, radius, duration + 0.15, { spin = 1, grow = duration })
	if kit.root then
		commandText(kit, kit.root, ";gravity all", nil, { life = duration + 1 })
	end
	kit.Vfx.glow(center + UP * 2, GOLD, radius, 1, duration)
end

-- The field: two counter-turning rings, a grid on the floor, light pressing down,
-- and pulses that travel inward
function fx.GravityField(kit)
	local data = kit.data
	local center = vec(data.center) or vec(data.position)
	if not center then
		return
	end
	local floor = center + UP * 0.04
	local radius = math.clamp(num(data.radius, 10), 1, 30)
	local duration = math.clamp(num(data.duration, 4), 0.1, 8)
	local outer = newGroup(kit)
	addRing(outer, radius, 0.06, 0.28, GOLD, 0.05, 36)
	addTicks(outer, radius - 0.7, 0.06, 12, 1, CRIMSON_HOT, 0.1)
	local inner = newGroup(kit)
	addRing(inner, radius * 0.55, 0.07, 0.16, GOLD, 0.3, 24, 0.35)
	local grid = newGroup(kit)
	local lines = if kit.Vfx.reduced() then 2 else 4
	for index = -lines, lines do
		local offset = index / (lines + 1) * radius
		local chord = 2 * math.sqrt(math.max(0, radius * radius - offset * offset)) - 0.6
		if chord > 0.5 then
			grid:add(CFrame.new(offset, 0.05, 0), { Size = Vector3.new(0.06, 0.04, chord), Color = GOLD, Transparency = 0.6 })
			grid:add(CFrame.new(0, 0.05, offset), { Size = Vector3.new(chord, 0.04, 0.06), Color = GOLD, Transparency = 0.6 })
		end
	end
	local pulse = newGroup(kit)
	addRing(pulse, radius, 0.08, 0.14, CRIMSON_HOT, 0.2, 24, 0.5)
	-- Light pressing down inside the ring
	local ceiling = kit.Vfx.part({ Size = Vector3.new(radius * 1.6, 0.2, radius * 1.6), CFrame = CFrame.new(floor + UP * 9), Transparency = 1 })
	local rain = Instance.new("ParticleEmitter")
	rain.Texture = SPARKLE
	rain.Color = ColorSequence.new(WHITE, GOLD)
	rain.LightEmission = 1
	rain.LightInfluence = 0
	rain.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0.04) })
	rain.Transparency = NumberSequence.new(0.2, 1)
	rain.Lifetime = NumberRange.new(0.35, 0.5)
	rain.Speed = NumberRange.new(16, 22)
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.SpreadAngle = Vector2.new(2, 2)
	rain.Rate = if kit.Vfx.reduced() then 10 else 34
	rain.Parent = ceiling
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = radius * 1.4
	light.Brightness = 0.7
	light.Parent = ceiling
	commandText(kit, floor + UP * 1, string.format("G x%.1f", num(data.heavy, 1.8)), nil, { color = WHITE, life = math.min(2, duration), offset = Vector3.new(0, 3.5, 0), scale = 0.9 })
	local base = CFrame.new(floor)
	local stopped = false
	local stop = animate(duration + 0.1, function(t)
		local grow = 0.4 + 0.6 * easeOut(t / 0.3)
		outer:place(base * CFrame.Angles(0, t * 0.35, 0), grow)
		inner:place(base * CFrame.Angles(0, -t * 0.7, 0), grow)
		grid:place(base, grow)
		-- A crimson pulse every 0.7 s shrinks toward the centre
		local cycle = (t / 0.7) % 1
		pulse:place(base, math.max(0.05, 1 - cycle))
		pulse:alpha(math.sin(cycle * math.pi))
		return true
	end, function()
		stopped = true
		outer:fade(0.3)
		inner:fade(0.3)
		grid:fade(0.3)
		pulse:fade(0.2)
		rain.Enabled = false
		Debris:AddItem(ceiling, 0.6)
	end)
	kit.keep(function()
		if not stopped then
			stop()
		end
	end)
end

function fx.SequenceStart(kit)
	local data = kit.data
	local duration = math.clamp(num(data.duration, 0.5), 0.1, 2)
	if kit.root then
		commandText(kit, kit.root, ";tp sequence", nil, { life = duration + 1.4 })
		floorSigil(kit, (feetOf(kit.root) :: Vector3) + UP * 0.05, 2.6, duration + 0.2, { spin = 2.4, grow = duration })
	end
	if typeof(data.targets) == "table" then
		for index, target in data.targets do
			if index > 3 then
				break
			end
			reticle(kit, modelOf(target), duration + 0.3)
		end
	end
end

function fx.SequenceBlink(kit)
	local data = kit.data
	local from, to = vec(data.from), vec(data.to)
	if not from or not to then
		return
	end
	local facing = flatUnit(to - from) or Vector3.new(0, 0, -1)
	if kit.model then
		kit.Vfx.ghostAt(kit.model, CFrame.lookAt(from, from + facing), GOLD, 0.3)
	end
	doorway(kit, to - UP * 2.95, facing, 0.3)
	kit.Vfx.beam(from, to, GOLD, 0.08, 0.2)
	glints(kit, to, WHITE, 10, 10)
	kit.Vfx.sound("Dodge", to)
end

function fx.SequenceStrike(kit)
	local data = kit.data
	local position = vec(data.position)
	if not position then
		return
	end
	local index = math.clamp(math.floor(num(data.index, 1)), 1, 3)
	local facing = if kit.root then flatUnit(position - kit.root.Position) else nil
	local frame = CFrame.lookAt(position, position + (facing or Vector3.new(0, 0, -1)))
	kit.Vfx.slash(frame, if data.landed then CRIMSON_HOT else GOLD, 3.2, (index - 2) * 40, 0.22)
	kit.Vfx.sparks(position, GOLD, if data.landed then 16 else 8, 20)
	if data.landed then
		kit.Vfx.glow(position, GOLD, 10, 2, 0.12)
		kit.shake(0.9, 0.12, position)
	end
	commandText(kit, position, `{index}/3`, nil, { color = WHITE, life = 0.7, offset = Vector3.new(0, 3.4, 0), scale = 0.6 })
	if kit.model then
		kit.Poser.play(kit.model, if index % 2 == 1 then "AdminPoint" else "AdminPush", 0.04, 0.12, 0.15)
	end
	kit.Vfx.sound("Hit", position)
end

function fx.SequenceBroken(kit)
	local position = vec(kit.data.position) or (if kit.root then kit.root.Position else nil)
	if not position then
		return
	end
	commandText(kit, position, ";tp sequence", "INTERRUPTED", { resultColor = CRIMSON_HOT, life = 1.2, resultDelay = 0.1 })
	kit.Vfx.groundRing(position - UP * 2.8, CRIMSON, 1, 4, 0.3)
end

function fx.SequenceEnd(kit)
	local position = vec(kit.data.position) or (if kit.root then kit.root.Position else nil)
	if not position then
		return
	end
	kit.Vfx.groundRing(position - UP * 2.8, GOLD, 1, 6, 0.4)
	glints(kit, position, GOLD, 10, 6)
end

function fx.AreaCast(kit)
	local data = kit.data
	local center = vec(data.position)
	if not center then
		return
	end
	local radius = math.clamp(num(data.radius, 16), 1, 40)
	local duration = math.clamp(num(data.duration, 0.55), 0.05, 2)
	floorSigil(kit, center + UP * 0.02, radius, duration + 0.15, { ticks = 16, spin = 0.8, grow = duration })
	if kit.root then
		commandText(kit, kit.root, ";slow all", nil, { life = duration + 1 })
	end
	kit.Vfx.glow(center + UP * 2, GOLD, radius, 1.2, duration)
end

function fx.AreaExecute(kit)
	local data = kit.data
	local center = vec(data.position)
	if not center then
		return
	end
	local radius = math.clamp(num(data.radius, 16), 1, 40)
	kit.Vfx.groundRing(center + UP * 0.1, GOLD, 2, radius * 2, 0.35)
	kit.Vfx.groundRing(center + UP * 0.12, CRIMSON_HOT, 2, radius * 1.6, 0.5)
	kit.Vfx.sound("Parry", center)
	local caught = 0
	if typeof(data.targets) == "table" then
		for _, target in data.targets do
			local root = rootOf(modelOf(target))
			if root then
				caught += 1
				kit.Vfx.ring(CFrame.new(root.Position - UP * 2.6) * CFrame.Angles(math.rad(90), 0, 0), 1.8, CRIMSON_HOT, 0.1, 0.5, 1.2)
				commandText(kit, root, "SLOWED", nil, { color = WHITE, life = 1, offset = Vector3.new(0, 4.6, 0), scale = 0.65 })
			end
		end
	end
	if kit.root then
		commandText(kit, kit.root, ";slow all", `{caught} AFFECTED`, { life = 1.3, resultDelay = 0.05 })
	end
	kit.shake(0.8, 0.2, center)
end

-- Ultimate: the Ban Hammer --------------------------------------------------------------------------

-- The hammer each caster's wind-up raised, handed to its slam
local hammers: { [Model]: any } = {}

-- A giant gold hammer: a handle along the group's Y axis with the head at the
-- top, crimson band, glowing white faces. Built around its grip (the origin).
local HAMMER_REACH = 7

local function buildHammer(kit)
	local hammer = newGroup(kit)
	local reach = HAMMER_REACH
	hammer:add(CFrame.new(0, reach / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), { Shape = Enum.PartType.Cylinder, Size = Vector3.new(reach + 0.6, 0.85, 0.85), Color = GRAPHITE, Material = Enum.Material.Metal, Transparency = 0 })
	for _, y in { 0.6, reach * 0.45 } do
		hammer:add(CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.05, 1.05), Color = GOLD, Material = Enum.Material.Metal, Transparency = 0 })
	end
	hammer:add(CFrame.new(0, -0.35, 0), { Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1, Color = GOLD, Material = Enum.Material.Metal, Transparency = 0 })
	-- The head lies across the swing (its long axis runs forward and back)
	local head = CFrame.new(0, reach, 0)
	hammer:add(head, { Size = Vector3.new(3.6, 3.6, 6.4), Color = GOLD, Material = Enum.Material.Metal, Transparency = 0 })
	hammer:add(head, { Size = Vector3.new(3.75, 3.75, 1.2), Color = CRIMSON, Transparency = 0 })
	for _, z in { -3.25, 3.25 } do
		hammer:add(head * CFrame.new(0, 0, z), { Size = Vector3.new(3.1, 3.1, 0.18), Color = WHITE, Transparency = 0 })
	end
	for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		hammer:add(head * CFrame.new(corner.X * 1.82, corner.Y * 1.82, 0), { Size = Vector3.new(0.1, 0.1, 6.2), Color = WHITE, Transparency = 0.1 })
	end
	return hammer
end

-- Where the hammer's grip stands, and its frame, for a ring at `floor` facing `facing`
local function hammerFrame(floor: Vector3, facing: Vector3, angle: number): CFrame
	local grip = floor - facing * HAMMER_REACH + UP * 1.8
	return CFrame.lookAt(grip, grip + facing) * CFrame.Angles(-math.rad(angle), 0, 0)
end

function fx.BanHammerWindup(kit)
	local data = kit.data
	local floor = vec(data.position)
	if not floor then
		return
	end
	local radius = math.clamp(num(data.radius, 10), 1, 30)
	local pullRadius = math.clamp(num(data.pullRadius, 18), radius, 40)
	local startup = math.clamp(num(data.startup, 1.5), 0.1, 4)
	local facing = (kit.root and flatUnit(floor - kit.root.Position)) or (kit.root and flatUnit(kit.root.CFrame.LookVector)) or Vector3.new(0, 0, -1)
	-- The verdict ring (exactly the hit radius), the pull ring, inward chevrons
	local verdict = newGroup(kit)
	addRing(verdict, radius, 0.07, 0.34, CRIMSON_HOT, 0, 40)
	addTicks(verdict, radius - 0.8, 0.07, 24, 0.9, GOLD, 0.05)
	addRing(verdict, radius * 0.5, 0.08, 0.2, GOLD, 0.2, 24)
	verdict:add(CFrame.new(0, 0.09, 0) * CFrame.Angles(0, 0, math.rad(90)), { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 1.6, 1.6), Color = GOLD, Transparency = 0.1 })
	verdict:add(CFrame.new(0, 0.09, 1.1), { Size = Vector3.new(0.9, 0.05, 1.6), Color = GOLD, Transparency = 0.1 })
	local pull = newGroup(kit)
	addRing(pull, pullRadius, 0.06, 0.16, CRIMSON, 0.35, 32, 0.55)
	local chevrons = newGroup(kit)
	local arrows = if kit.Vfx.reduced() then 4 else 8
	for index = 0, arrows - 1 do
		local angle = index / arrows * math.pi * 2
		for _, side in { -1, 1 } do
			chevrons:add(CFrame.Angles(0, angle, 0) * CFrame.new(side * 0.45, 0.07, 0) * CFrame.Angles(0, side * math.rad(40), 0), { Size = Vector3.new(0.16, 0.05, 1.3), Color = CRIMSON_HOT, Transparency = 0.15 })
		end
	end
	local hammer = buildHammer(kit)
	local slot = { hammer = hammer, floor = floor, facing = facing, angle = -10, taken = false }
	if kit.model then
		hammers[kit.model] = slot
	end
	commandText(kit, floor, ";ban", nil, { life = startup + 0.6, offset = Vector3.new(0, 9, 0), scale = 1.6 })
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = radius * 1.6
	light.Brightness = 0
	local holder = kit.Vfx.part({ Size = Vector3.one * 0.2, CFrame = CFrame.new(floor + UP * 6), Transparency = 1 })
	light.Parent = holder
	kit.Vfx.sound("HeavySwing", floor)
	local base = CFrame.new(floor)
	local stopped = false
	local stop = animate(startup + 0.3, function(t)
		local a = math.clamp(t / startup, 0, 1)
		verdict:place(base * CFrame.Angles(0, t * 0.4, 0), 0.5 + 0.5 * easeOut(t / 0.3))
		pull:place(base * CFrame.Angles(0, -t * 0.3, 0))
		-- Chevrons crawl inward from the pull ring to the verdict ring, over and over
		local cycle = (t * 1.4) % 1
		for _, item in chevrons.items do
			local along = pullRadius - (pullRadius - radius) * cycle
			item.part.CFrame = base * CFrame.new(item.position) * item.rotation * CFrame.new(0, 0, -along)
			item.part.Transparency = 0.15 + 0.85 * cycle
		end
		-- The hammer forms out of the light, then cocks back
		if not slot.taken then
			slot.angle = -10 - 32 * easeOut(a)
			hammer:place(hammerFrame(floor, facing, slot.angle) * CFrame.new(0, 2 + 3 * easeOut(a), 0))
			hammer:alpha(easeOut(t / 0.6))
		end
		light.Brightness = 1.5 * a
		return true
	end, function()
		stopped = true
		verdict:fade(0.25)
		pull:fade(0.2)
		chevrons:fade(0.15)
		holder:Destroy()
		if not slot.taken then
			hammer:fade(0.3)
			if kit.model and hammers[kit.model] == slot then
				hammers[kit.model] = nil
			end
		end
	end)
	kit.keep(function()
		if not stopped then
			stop()
		end
	end)
end

function fx.BanHammerSlam(kit)
	local data = kit.data
	local floor = vec(data.position)
	if not floor then
		return
	end
	local radius = math.clamp(num(data.radius, 10), 1, 30)
	local slot = if kit.model then hammers[kit.model] else nil
	if kit.model then
		hammers[kit.model] = nil
	end
	local facing = (slot and slot.facing) or (kit.root and flatUnit(kit.root.CFrame.LookVector)) or Vector3.new(0, 0, -1)
	local hammer = slot and slot.hammer
	local fromAngle = if slot then slot.angle else -40
	if slot then
		slot.taken = true
	else
		hammer = buildHammer(kit)
	end
	-- The swing: accelerating into the floor, then a beat of weight, then light
	animate(0.75, function(t)
		local swing = easeIn(t / 0.09)
		local angle = fromAngle + (90 - fromAngle) * swing
		local lift = if slot then 5 * (1 - swing) else 0
		hammer:place(hammerFrame(floor, facing, angle) * CFrame.new(0, 2 + lift - 2 * swing, 0))
		if t > 0.35 then
			hammer:alpha(1 - (t - 0.35) / 0.4)
		end
		return true
	end, function()
		hammer:destroy()
	end)
	task.delay(0.09, function()
		local Vfx = kit.Vfx
		Vfx.groundRing(floor + UP * 0.12, GOLD, 2, radius * 2.4, 0.45)
		Vfx.groundRing(floor + UP * 0.14, CRIMSON_HOT, 2, radius * 2, 0.6)
		Vfx.shockwave(floor + UP * 1.2, GOLD, 4, radius * 1.8, 0.4)
		Vfx.cracks(floor, radius * 0.85, GOLD, if Vfx.reduced() then 6 else 12, 3)
		Vfx.debris(floor, if Vfx.reduced() then 5 else 12, STEEL, Enum.Material.Metal, 45)
		dust(kit, floor, radius, 22)
		glints(kit, floor + UP * 2, GOLD, 30, 30)
		Vfx.glow(floor + UP * 3, GOLD, radius * 2.5, 4, 0.18)
		Vfx.screenFlash(CRIMSON, 0.35, 0.35)
		Vfx.sound("HeavyHit", floor)
		Vfx.sound("GuardBreak", floor)
		kit.shake(3.2, 0.5, floor)
		stamp(kit, floor + UP * 6, "ACCESS REVOKED", CRIMSON_HOT, 1.6)
		-- Dissipation: gold embers rising slowly out of the cracks
		kit.Vfx.burst(floor + UP * 0.5, {
			colors = ColorSequence.new(GOLD, CRIMSON),
			texture = SPARKLE,
			size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
			transparency = NumberSequence.new(0.1, 1),
			lifetime = NumberRange.new(1, 1.8),
			speed = NumberRange.new(2, 5),
			spread = Vector2.new(30, 30),
			acceleration = Vector3.new(0, 3, 0),
			drag = 1,
			count = 24,
		})
	end)
end

function fx.BanHammerFizzle(kit)
	local floor = vec(kit.data.position)
	local slot = if kit.model then hammers[kit.model] else nil
	if kit.model then
		hammers[kit.model] = nil
	end
	if slot then
		slot.taken = true
		local center = slot.hammer.base.Position
		slot.hammer:fade(0.3)
		fragments(kit, center, Vector3.new(4, 8, 4), 20, GOLD, 4)
	end
	if floor then
		kit.Vfx.groundRing(floor + UP * 0.1, STEEL, 12, 4, 0.4)
		commandText(kit, floor, ";ban", "CANCELLED", { resultColor = CRIMSON_HOT, life = 1.2, offset = Vector3.new(0, 4, 0) })
	end
end

-- Persistent look ------------------------------------------------------------------------------------

local function regaliaPart(parent: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material, transparency: number, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	if shape then
		part.Shape = shape
	end
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Anchored = false
	part.Parent = parent
	return part
end

local function weldTo(part: BasePart, to: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = part
	weld.Parent = part
end

-- A hub that turns on a Weld (one C0 update a frame moves everything on it)
local function hub(parent: Instance, body: BasePart, offset: CFrame): (Part, Weld)
	local center = regaliaPart(parent, "SNAdminHub", Vector3.one * 0.2, GOLD, Enum.Material.Metal, 1)
	center.CFrame = body.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = body
	weld.Part1 = center
	weld.C0 = offset
	weld.Parent = center
	return center, weld
end

-- Ring pieces welded around a hub (in the hub's XY plane unless `flat`)
local function hubRing(parent: Instance, center: BasePart, radius: number, count: number, size: Vector3, color: Color3, material: Enum.Material, transparency: number, flat: boolean?)
	for index = 0, count - 1 do
		local angle = (index + 0.5) / count * math.pi * 2
		local piece = regaliaPart(parent, "SNAdminRing", size, color, material, transparency)
		if flat then
			piece.CFrame = center.CFrame * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius)
		else
			piece.CFrame = center.CFrame * CFrame.Angles(0, 0, angle) * CFrame.new(0, radius, 0)
		end
		weldTo(piece, center)
	end
end

function Admin.appearance(kit)
	local model = kit.model
	if not model then
		return nil
	end
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return nil
	end
	local degree = kit.degree
	local regalia = Instance.new("Model")
	regalia.Name = "SNAdminRegalia"
	regalia.Parent = model
	local connections: { RBXScriptConnection } = {}
	local spinners: { { weld: Weld, offset: CFrame, speed: number } } = {}

	-- Gold cuffs with a crimson inlay at both wrists
	for _, name in { "RightLowerArm", "LeftLowerArm", "Right Arm", "Left Arm" } do
		local limb = model:FindFirstChild(name)
		if limb and limb:IsA("BasePart") then
			local along = CFrame.new(0, -limb.Size.Y * 0.3, 0) * CFrame.Angles(0, 0, math.rad(90))
			local cuff = regaliaPart(regalia, "SNAdminCuff", Vector3.new(0.32, limb.Size.X * 1.18, limb.Size.Z * 1.18), GOLD, Enum.Material.Metal, 0, Enum.PartType.Cylinder)
			cuff.CFrame = limb.CFrame * along
			weldTo(cuff, limb)
			local inlay = regaliaPart(regalia, "SNAdminInlay", Vector3.new(0.08, limb.Size.X * 1.24, limb.Size.Z * 1.24), CRIMSON, Enum.Material.Neon, 0, Enum.PartType.Cylinder)
			inlay.CFrame = cuff.CFrame
			weldTo(inlay, limb)
		end
	end

	-- WARDEN's sigil turning behind the shoulders: a ring and a keyhole
	local back = CFrame.new(0, torso.Size.Y * 0.15, torso.Size.Z / 2 + 0.55)
	local sigil, sigilWeld = hub(regalia, torso, back)
	hubRing(regalia, sigil, 0.85, if kit.Vfx.reduced() then 8 else 12, Vector3.new(0.42, 0.08, 0.06), GOLD, Enum.Material.Neon, 0.1)
	local keyhole = regaliaPart(regalia, "SNAdminKeyhole", Vector3.new(0.05, 0.32, 0.32), CRIMSON, Enum.Material.Neon, 0, Enum.PartType.Cylinder)
	keyhole.CFrame = sigil.CFrame * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, math.rad(90), 0)
	weldTo(keyhole, sigil)
	local slot = regaliaPart(regalia, "SNAdminKeyslot", Vector3.new(0.14, 0.32, 0.05), CRIMSON, Enum.Material.Neon, 0)
	slot.CFrame = sigil.CFrame * CFrame.new(0, -0.14, 0)
	weldTo(slot, sigil)
	if degree >= 2 then
		hubRing(regalia, sigil, 1.12, 8, Vector3.new(0.08, 0.22, 0.05), CRIMSON, Enum.Material.Neon, 0.15)
	end
	table.insert(spinners, { weld = sigilWeld, offset = back, speed = 0.6 })

	-- Degree 2: gold epaulettes with a crimson edge
	if degree >= 2 then
		for _, side in { -1, 1 } do
			local plate = regaliaPart(regalia, "SNAdminEpaulette", Vector3.new(0.9, 0.18, torso.Size.Z * 0.9), GOLD, Enum.Material.Metal, 0)
			plate.CFrame = torso.CFrame * CFrame.new(side * (torso.Size.X / 2 - 0.2), torso.Size.Y / 2 + 0.08, 0) * CFrame.Angles(0, 0, side * math.rad(-12))
			weldTo(plate, torso)
			local edge = regaliaPart(regalia, "SNAdminEpauletteEdge", Vector3.new(0.92, 0.06, 0.1), CRIMSON, Enum.Material.Neon, 0)
			edge.CFrame = plate.CFrame * CFrame.new(0, -0.05, -torso.Size.Z * 0.45)
			weldTo(edge, torso)
		end
	end

	-- Degree 3: a crown of light above the head
	local head = model:FindFirstChild("Head")
	if degree >= 3 and head and head:IsA("BasePart") then
		local crownOffset = CFrame.new(0, head.Size.Y / 2 + 0.55, 0)
		local crown, crownWeld = hub(regalia, head, crownOffset)
		crown.Name = "SNAdminCrown"
		hubRing(regalia, crown, 0.72, if kit.Vfx.reduced() then 8 else 14, Vector3.new(0.34, 0.07, 0.09), GOLD, Enum.Material.Neon, 0.1, true)
		for index = 0, 4 do
			local angle = index / 5 * math.pi * 2
			local spike = regaliaPart(regalia, "SNAdminCrownPoint", Vector3.new(0.08, 0.32, 0.08), if index == 0 then CRIMSON else GOLD, Enum.Material.Neon, 0.05)
			spike.CFrame = crown.CFrame * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.16, -0.72)
			weldTo(spike, crown)
		end
		local light = Instance.new("PointLight")
		light.Color = GOLD
		light.Range = 6
		light.Brightness = 0.6
		light.Parent = crown
		if not kit.Vfx.reduced() then
			local motes = Instance.new("ParticleEmitter")
			motes.Texture = SPARKLE
			motes.Color = ColorSequence.new(GOLD)
			motes.LightEmission = 1
			motes.LightInfluence = 0
			motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) })
			motes.Transparency = NumberSequence.new(0.3, 1)
			motes.Lifetime = NumberRange.new(0.6, 1)
			motes.Speed = NumberRange.new(0.3, 0.8)
			motes.Rate = 3
			motes.Parent = crown
		end
		table.insert(spinners, { weld = crownWeld, offset = crownOffset, speed = 0.45 })
	end

	-- Base looks, so hiding and showing restores them exactly
	local looks = {}
	for _, item in regalia:GetDescendants() do
		if item:IsA("BasePart") then
			looks[item] = item.Transparency
		end
	end
	-- Hidden with the body (Concealed)
	local function follow()
		local hidden = torso.Transparency
		for part, transparency in looks do
			part.Transparency = math.max(transparency, hidden)
		end
	end
	table.insert(connections, torso:GetPropertyChangedSignal("Transparency"):Connect(follow))
	follow()

	local spin = 0
	table.insert(connections, RunService.Heartbeat:Connect(function(dt)
		spin += dt
		for _, spinner in spinners do
			if spinner.weld.Parent then
				spinner.weld.C0 = spinner.offset * CFrame.Angles(0, if spinner.offset.Y > 0.5 and spinner.offset.Z == 0 then spin * spinner.speed else 0, if spinner.offset.Z ~= 0 then spin * spinner.speed else 0)
			end
		end
	end))

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		regalia:Destroy()
	end
end

return Admin
