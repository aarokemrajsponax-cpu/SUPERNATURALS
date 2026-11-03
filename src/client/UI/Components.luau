-- Building blocks for every interface, in the "imperial codex meets precision
-- instrument" system (docs/ArtDirection.md section 6): warm graphite plates with
-- a 1 px bronze hairline and square corners, ivory text, one bronze-gold accent,
-- drawn line icons (UI/Icons) and no emoji anywhere.
--
-- Every control that can be pressed draws the same seven states (Theme.state):
--   default   hairline frame
--   hover     frame brightens, background +3% (120 ms)
--   pressed   scale 0.98 (80 ms)
--   selected  2 px bronze bar on the leading edge, bronze frame, ivory title
--   focused   2 px ivory outline outside the frame (gamepad selection)
--   disabled  45% opacity, plus the reason in text where there is room
--   locked    a drawn lock and the requirement or exact price
--
-- API (older screens keep using make, corner, stroke, padding, panel, label,
-- button and bar exactly as before; label and button without a Variant still
-- scale their text):
--   make(class, props, children)      corner(radius)  stroke(color, thickness, alpha)
--   padding(top, right?, bottom?, left?)              panel(props)  divider(props)
--   accentLine(props)                 list(parent, gap, props)      grid(parent, cell, gap)
--   scroll(props)                     text(props)     label(text, props)
--   icon(name, size, color)           iconTile(icon, size, color)   badge(text, color)
--   chip(text, props)                 keycap(text, props)           price(parent, price, props)
--   button(text, props, onClick)      setDisabled(control, on, reason?)  setLocked(control, on, text?)
--   isDisabled(control)               interactive(button, render)   surface(button, options)
--   card(props) -> frame, card        tabs(parent, specs, onSelect) segmented(parent, options, value, onChange, props)
--   bar(props, color)                 progress(props, color)        toggle(label, value, onChange, props)
--   slider(label, min, max, step, value, onChange, props)            row(props) -> row, control
--   section(parent, title, props)     window(props) -> frame, body, parts
--   fade(root, show, info, done)      formatNumber(n)   textWidth(text, size, face)   snap(...)
--   tween(instance, info, goal)       apply(instance, info?, goal)

local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local Components = {}

local Colors = Theme.Colors
local Faces = Theme.Faces
local Motion = Theme.Motion
local Space = Theme.Space

-- Attributes that mark a control as disabled or locked (checked before clicks run)
local DISABLED = "SNDisabled"
local LOCKED = "SNLocked"
local REASON = "SNReason"
-- A content item's own transparency, remembered while the control is dimmed
local BASE_ALPHA = "SNBaseAlpha"

local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local created = TweenService:Create(instance, info, goal)
	created:Play()
	return created
end
Components.tween = tween

-- Tweens to the goal, or sets it straight away when info is nil (the first
-- look is in place at once, before any caller recolors the control)
local function apply(instance: Instance, info: TweenInfo?, goal: { [string]: any })
	if info then
		tween(instance, info, goal)
	else
		for key, value in goal do
			(instance :: any)[key] = value
		end
	end
end
Components.apply = apply

-- Creates an instance, sets properties, and parents children (a list or a map)
function Components.make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	for key, value in (props or {}) :: { [string]: any } do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	for _, child in (children or {}) :: { Instance } do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local make = Components.make

function Components.corner(radius: UDim?): UICorner
	return make("UICorner", { CornerRadius = radius or Theme.Corner })
end

-- A hairline: bronze, 1 px, at the panel transparency unless told otherwise
function Components.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return make("UIStroke", {
		Color = color or Colors.Bronze,
		Thickness = thickness or 1,
		Transparency = transparency or Theme.Glass.StrokeTransparency,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- padding(all) / padding(vertical, horizontal) / padding(top, right, bottom, left)
function Components.padding(top: number, right: number?, bottom: number?, left: number?): UIPadding
	local r = right or top
	local b = bottom or top
	local l = left or r
	return make("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingBottom = UDim.new(0, b),
		PaddingLeft = UDim.new(0, l),
		PaddingRight = UDim.new(0, r),
	})
end

local corner = Components.corner
local stroke = Components.stroke
local padding = Components.padding

-- Swaps a legacy Enum font for the matching Builder Sans face, in place
local function upgradeFont(merged: { [string]: any })
	local font = merged.Font
	if typeof(font) == "EnumItem" then
		local face = Theme.FaceForFont[font.Name]
		if face then
			merged.Font = nil
			if merged.FontFace == nil then
				merged.FontFace = face
			end
		end
	end
end

local function faceFor(weight: any): Font
	if typeof(weight) == "Font" then
		return weight
	end
	return (Faces :: any)[weight] or Faces.Medium
end

local function colorFor(color: any, fallback: Color3): Color3
	if typeof(color) == "Color3" then
		return color
	end
	return (Colors :: any)[color] or fallback
end

-- Kept for older screens: a near-flat neutral shade (lit from above). The new
-- system is flat; nothing here adds colour.
local function glassGradient(): UIGradient
	return make("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(232, 230, 226)),
		Rotation = 90,
	})
end
Components.glassGradient = glassGradient

-- The gamepad outline for older controls that set it as their SelectionImageObject:
-- 2 px ivory, 3 px outside the frame, square
local selectionImage = make("Frame", {
	Name = "SNSelection",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 6, 1, 6),
	Position = UDim2.fromOffset(-3, -3),
}, {
	make("UICorner", { CornerRadius = UDim.new(0, 3) }),
	make("UIStroke", { Color = Colors.Text, Thickness = 2, Transparency = 0 }),
})
Components.selectionImage = selectionImage

-- Controls built here draw their own focus ring, so Roblox draws nothing
local noSelection = make("Frame", {
	Name = "SNNoSelection",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
})
Components.noSelection = noSelection

-- Text measuring (TextService, with the Enum font closest to each face)
local MEASURE_FONT = {
	Regular = "BuilderSans",
	Medium = "BuilderSansMedium",
	SemiBold = "BuilderSansMedium",
	Bold = "BuilderSansBold",
	ExtraBold = "BuilderSansExtraBold",
	Heavy = "BuilderSansExtraBold",
}
local function measureFont(face: Font?): Enum.Font
	if face then
		local family = face.Family
		if string.find(family, "Accanthis", 1, true) then
			return Enum.Font.Bodoni
		elseif string.find(family, "RobotoMono", 1, true) then
			return Enum.Font.RobotoMono
		end
		local name = MEASURE_FONT[face.Weight.Name]
		local ok, font = pcall(function()
			return (Enum.Font :: any)[name or "BuilderSans"]
		end)
		if ok and font then
			return font
		end
	end
	return Enum.Font.GothamMedium
end

-- Width of one line of text in pixels
function Components.textWidth(text: string, size: number, face: Font?): number
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, size, measureFont(face), Vector2.new(10000, 10000))
	end)
	return if ok and typeof(bounds) == "Vector2" then bounds.X else #text * size * 0.5
end

-- Panels -------------------------------------------------------------------------

-- A flat graphite plate with a bronze hairline and square corners
function Components.panel(props: { [string]: any }?): Frame
	local merged = {
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = Theme.Glass.Panel,
		BorderSizePixel = 0,
		-- Catch clicks, so clicking a panel's background doesn't throw a punch
		Active = true,
	}
	for key, value in (props or {}) :: { [string]: any } do
		merged[key] = value
	end
	return make("Frame", merged, {
		corner(),
		stroke(Colors.Bronze, 1, Theme.Glass.StrokeTransparency),
	})
end

-- Text ---------------------------------------------------------------------------------

-- Legacy label: text scaled to fit, capped at MaxTextSize (default 32)
function Components.label(text: string, props: { [string]: any }?): TextLabel
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		Text = text,
		FontFace = Faces.Medium,
		TextColor3 = Colors.Text,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
	}
	-- MaxTextSize isn't a TextLabel property; it goes on a size constraint
	local maxTextSize = 32
	for key, value in (props or {}) :: { [string]: any } do
		if key == "MaxTextSize" then
			maxTextSize = value
		elseif key == "Font" then
			merged.FontFace = nil
			merged.Font = value
		else
			merged[key] = value
		end
	end
	upgradeFont(merged)
	return make("TextLabel", merged, {
		make("UITextSizeConstraint", { MaxTextSize = maxTextSize, MinTextSize = 14 }),
	})
end

type Style = { size: number, face: Font, color: string, caps: boolean, lineHeight: number }

-- A type style by role ("body", "overline"...) or legacy name ("Body", "Micro"...)
local function styleFor(name: any): Style
	if typeof(name) == "string" then
		local legacy = Theme.TextStyles[name]
		if legacy then
			return { size = legacy.size, face = faceFor(legacy.face), color = legacy.color, caps = false, lineHeight = 1.2 }
		end
		local role = Theme.Roles[name]
		if role then
			return { size = role.size, face = role.face, color = role.color, caps = role.caps, lineHeight = role.lineHeight }
		end
	end
	local body = Theme.TextStyles.Body
	return { size = body.size, face = faceFor(body.face), color = body.color, caps = false, lineHeight = 1.25 }
end
Components.styleFor = styleFor

local TEXT_KEYS = { Style = true, Weight = true, Color = true, Wrap = true, AlignX = true, AlignY = true, Caps = true, Track = true, Text = true, Lines = true }
local ALIGN_X = { Left = Enum.TextXAlignment.Left, Center = Enum.TextXAlignment.Center, Right = Enum.TextXAlignment.Right }
local ALIGN_Y = { Top = Enum.TextYAlignment.Top, Center = Enum.TextYAlignment.Center, Bottom = Enum.TextYAlignment.Bottom }

-- A fixed-size label from the type scale.
--   Style = a role: "display" | "title" | "heading" | "body" | "small" | "caption" | "overline"
--           | "label" | "strong" | "number" | "mono" | "hero" | "countdown"
--           or a legacy name: "Micro" | "Caption" | "Body" | "Label" | "Heading" | "Title" | "Display"
--   Weight = a Theme.Faces name or a Font; Color = Color3 or a Theme.Colors name
--   Wrap = true for paragraphs (wraps and grows downward); otherwise one line cut with "…"
--   Lines = n: wrap but keep exactly n lines (cut with "…")
--   Caps = true for capitals (roles like "overline" are always capitals);
--   Track = true for display tracking (Theme.track: hair spaces between letters)
--   AlignX = "Left" | "Center" | "Right"; AlignY = "Top" | "Center" | "Bottom"
-- Any other key is set on the TextLabel as a property.
function Components.text(props: { [string]: any }?): TextLabel
	local given = props or {}
	local style = styleFor(given.Style or "Body")
	local size = given.TextSize or style.size
	local lines = given.Lines
	local wrap = given.Wrap == true or typeof(lines) == "number"
	local content = if typeof(given.Text) == "string" then given.Text else ""
	if given.Track then
		content = Theme.track(content)
	elseif given.Caps or style.caps then
		content = string.upper(content)
	end
	local lineBox = math.ceil(size * style.lineHeight)
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = content,
		FontFace = faceFor(given.Weight or style.face),
		TextSize = size,
		TextColor3 = colorFor(given.Color, (Colors :: any)[style.color] or Colors.Text),
		TextXAlignment = ALIGN_X[given.AlignX or "Left"] or given.AlignX,
		TextYAlignment = ALIGN_Y[given.AlignY or (if wrap then "Top" else "Center")] or given.AlignY,
		TextWrapped = wrap,
		LineHeight = if wrap then style.lineHeight else 1,
		TextTruncate = if wrap and typeof(lines) ~= "number" then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		Size = if typeof(lines) == "number"
			then UDim2.new(1, 0, 0, lineBox * lines + 2)
			elseif wrap then UDim2.fromScale(1, 0)
			else UDim2.new(1, 0, 0, math.max(size + 6, lineBox + 2)),
		AutomaticSize = if wrap and typeof(lines) ~= "number" then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
	}
	for key, value in given do
		if not TEXT_KEYS[key] then
			merged[key] = value
		end
	end
	upgradeFont(merged)
	return make("TextLabel", merged)
end

-- Numbers ------------------------------------------------------------------------------

-- 12000 -> "12,000" (rounded to a whole number; NaN and infinity show as "0")
function Components.formatNumber(n: number): string
	if typeof(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return "0"
	end
	local rounded = math.floor(math.abs(n) + 0.5)
	local digits = string.format("%d", rounded)
	local out = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	if n < 0 and rounded ~= 0 then
		out = "-" .. out
	end
	return out
end

local formatNumber = Components.formatNumber

-- Icons -------------------------------------------------------------------------------------

-- A drawn line icon (any name, alias or emoji; unknown ones draw the facet)
function Components.icon(name: any, size: number?, color: Color3?): Frame
	return Icons.make(Icons.resolve(name), size or 20, color or Colors.TextDim)
end

-- Content opacity --------------------------------------------------------------------------

-- Fades the readable content of a control (text, images, icon ink) to `opacity`
-- of its own transparency; opacity 1 puts every value back exactly
local function fadeContent(root: Instance, opacity: number)
	local items = root:GetDescendants()
	table.insert(items, root)
	for _, item in items do
		local prop: string? = nil
		if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
			prop = "TextTransparency"
		elseif item:IsA("ImageLabel") or item:IsA("ImageButton") then
			prop = "ImageTransparency"
		elseif item.Name == "Ink" then
			prop = if item:IsA("UIStroke") then "Transparency" elseif item:IsA("GuiObject") then "BackgroundTransparency" else nil
		end
		if prop then
			local base = item:GetAttribute(BASE_ALPHA)
			if opacity < 1 then
				if typeof(base) ~= "number" then
					base = (item :: any)[prop]
					item:SetAttribute(BASE_ALPHA, base)
				end
				if (base :: number) < 1 then
					(item :: any)[prop] = Theme.fadeAlpha(base :: number, opacity)
				end
			elseif typeof(base) == "number" then
				(item :: any)[prop] = base
				item:SetAttribute(BASE_ALPHA, nil)
			end
		end
	end
end
Components.fadeContent = fadeContent

-- Interaction states ---------------------------------------------------------------------

export type State = {
	hovered: boolean,
	pressed: boolean,
	selected: boolean,
	focused: boolean,
	disabled: boolean,
	locked: boolean,
}
export type Look = {
	render: (state: State, instant: boolean?) -> (),
}

-- Refreshers by control, so setDisabled/setLocked repaint at once
local refreshers: { [Instance]: (instant: boolean?) -> () } = setmetatable({}, { __mode = "k" }) :: any
local selectors: { [Instance]: (selected: boolean) -> () } = setmetatable({}, { __mode = "k" }) :: any

local function isPress(input: InputObject): boolean
	local kind = input.UserInputType
	return kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA
end

-- Wires hover (mouse), focus (gamepad selection), press, and the disabled and
-- locked flags to a render function. Returns the state table and a refresh function.
local function interactive(button: GuiButton, render: (state: State, instant: boolean?) -> ())
	local state: State = {
		hovered = false,
		pressed = false,
		selected = false,
		focused = false,
		disabled = button:GetAttribute(DISABLED) == true,
		locked = button:GetAttribute(LOCKED) == true,
	}
	local function refresh(instant: boolean?)
		render(state, instant)
	end
	button.MouseEnter:Connect(function()
		state.hovered = true
		refresh()
	end)
	button.MouseLeave:Connect(function()
		state.hovered = false
		state.pressed = false
		refresh()
	end)
	button.SelectionGained:Connect(function()
		state.focused = true
		refresh()
	end)
	button.SelectionLost:Connect(function()
		state.focused = false
		state.pressed = false
		refresh()
	end)
	button.InputBegan:Connect(function(input: InputObject)
		if isPress(input) and not state.disabled then
			state.pressed = true
			refresh()
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		if isPress(input) then
			state.pressed = false
			refresh()
		end
	end)
	-- Components.setDisabled / setLocked flip these attributes
	local function readFlags()
		state.disabled = button:GetAttribute(DISABLED) == true
		state.locked = button:GetAttribute(LOCKED) == true
		if state.disabled then
			state.pressed = false
		end
		refresh()
	end
	button:GetAttributeChangedSignal(DISABLED):Connect(readFlags)
	button:GetAttributeChangedSignal(LOCKED):Connect(readFlags)
	refreshers[button] = function(instant: boolean?)
		state.disabled = button:GetAttribute(DISABLED) == true
		state.locked = button:GetAttribute(LOCKED) == true
		refresh(instant)
	end
	refresh(true)
	return state, refresh
end
Components.interactive = interactive

-- Turns a control on or off (45% opacity, no hover, clicks ignored). An
-- optional reason is kept on the control for screens that show it.
function Components.setDisabled(control: GuiButton, disabled: boolean, reason: string?)
	control:SetAttribute(DISABLED, if disabled then true else nil)
	control:SetAttribute(REASON, if disabled and typeof(reason) == "string" then reason else nil)
	control.Selectable = not disabled
	local refresh = refreshers[control]
	if refresh then
		refresh()
	end
end

function Components.isDisabled(control: GuiButton): boolean
	return control:GetAttribute(DISABLED) == true
end

-- Why a control is disabled (set with setDisabled), if it says
function Components.reasonOf(control: GuiButton): string?
	local reason = control:GetAttribute(REASON)
	return if typeof(reason) == "string" then reason else nil
end

-- Marks a control locked (a drawn lock; clicks still run, so they can explain or sell)
function Components.setLocked(control: GuiButton, locked: boolean, requirement: string?)
	control:SetAttribute(LOCKED, if locked then true else nil)
	if requirement ~= nil then
		control:SetAttribute(REASON, if locked then requirement else nil)
	end
	local refresh = refreshers[control]
	if refresh then
		refresh()
	end
end

export type Surface = {
	frame: GuiObject,
	stroke: UIStroke,
	bar: Frame,
	ring: Frame,
	scale: UIScale,
	lock: Frame?,
	title: TextLabel?,
	render: (state: State, instant: boolean?) -> (),
}

-- Adds the pieces a framed control draws its seven states with: the hairline,
-- the 2 px bronze bar on the leading edge, the focus ring outside the frame and
-- the press scale. options: Edge = "left" | "bottom" | "top" (where the bar sits),
-- Title (a TextLabel that turns ivory when hovered or selected), Lock (a drawn
-- lock is shown while locked; a Vector2/UDim2 position or true for the default),
-- Flat (no fill until hovered), Fill/FillAlpha (resting background).
function Components.surface(frame: GuiObject, options: { [string]: any }?): Surface
	local given = options or {}
	local edge = given.Edge or "left"
	local outline = frame:FindFirstChild("Hairline") :: UIStroke?
	if not outline then
		outline = stroke(Colors.Bronze, 1, Theme.States.default.strokeAlpha)
		;(outline :: UIStroke).Name = "Hairline"
		;(outline :: UIStroke).Parent = frame
	end
	local bar = make("Frame", {
		Name = "Bar",
		BackgroundColor3 = Colors.Accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = frame.ZIndex + 1,
		AnchorPoint = if edge == "bottom" then Vector2.new(0, 1) else Vector2.zero,
		Position = if edge == "bottom" then UDim2.fromScale(0, 1) else UDim2.new(),
		Size = if edge == "left" then UDim2.new(0, 2, 1, 0) else UDim2.new(1, 0, 0, 2),
		Parent = frame,
	})
	local ring = make("Frame", {
		Name = "FocusRing",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-4, -4),
		Size = UDim2.new(1, 8, 1, 8),
		Visible = false,
		ZIndex = frame.ZIndex + 2,
		Parent = frame,
	}, {
		make("UICorner", { CornerRadius = UDim.new(0, 3) }),
		make("UIStroke", { Color = Colors.Text, Thickness = 2, Transparency = 0 }),
	})
	local scale = frame:FindFirstChild("PressScale") :: UIScale?
	if not scale then
		scale = make("UIScale", { Name = "PressScale", Parent = frame })
	end
	local lock: Frame? = nil
	if given.Lock then
		local lockIcon = Icons.make("lock", 16, Colors.TextMuted)
		lockIcon.Name = "Lock"
		lockIcon.AnchorPoint = Vector2.new(1, 0.5)
		lockIcon.Position = if typeof(given.Lock) == "UDim2" then given.Lock else UDim2.new(1, -Space.L, 0.5, 0)
		lockIcon.Visible = false
		lockIcon.ZIndex = frame.ZIndex + 1
		lockIcon.Parent = frame
		lock = lockIcon
	end
	local flat = given.Flat == true
	local noFrame = given.NoFrame == true
	local hoverAlpha: number? = given.HoverAlpha or (if flat then 0.55 else nil)
	if noFrame then
		(outline :: UIStroke).Transparency = 1
	end
	local restFill: Color3? = given.Fill
	local restAlpha: number? = given.FillAlpha
	local wasDimmed = false
	local surface: Surface
	surface = {
		frame = frame,
		stroke = outline :: UIStroke,
		bar = bar,
		ring = ring,
		scale = scale :: UIScale,
		lock = lock,
		title = given.Title,
		render = function(state: State, instant: boolean?)
			local info = if instant then nil else Motion.Fast
			local look = Theme.state(state)
			local fill = look.fill
			local fillAlpha = look.fillAlpha
			if look == Theme.States.default or look == Theme.States.locked then
				if restFill then
					fill = restFill
				end
				if restAlpha then
					fillAlpha = restAlpha
				elseif flat then
					fillAlpha = 1
				end
			elseif flat and look == Theme.States.disabled then
				fillAlpha = 1
			elseif hoverAlpha and not state.selected then
				fillAlpha = hoverAlpha
			end
			apply(frame, info, { BackgroundColor3 = fill, BackgroundTransparency = fillAlpha })
			local strokeAlpha = look.strokeAlpha
			if flat and (look == Theme.States.default or look == Theme.States.locked or look == Theme.States.disabled) then
				strokeAlpha = 1
			end
			if not noFrame then
				apply(surface.stroke, info, { Color = look.stroke, Transparency = strokeAlpha })
			end
			apply(bar, info, { BackgroundTransparency = if state.selected and not state.disabled then 0 else 1 })
			ring.Visible = state.focused and not state.disabled
			apply(surface.scale, if instant then nil else Motion.Press, { Scale = if state.pressed and not state.disabled then 0.98 else 1 })
			if surface.title then
				apply(surface.title, info, { TextColor3 = if state.selected or state.hovered or state.focused then Colors.Text else look.text })
			end
			if lock then
				lock.Visible = state.locked
			end
			if state.disabled ~= wasDimmed then
				wasDimmed = state.disabled
				fadeContent(frame, if state.disabled then look.opacity else 1)
			end
		end,
	}
	return surface
end

-- Buttons ---------------------------------------------------------------------------------

local BUTTON_KEYS = { Accent = true, Variant = true, Disabled = true, Icon = true, IconSize = true, Locked = true, KeepCase = true, Reason = true }

-- Places a drawn icon just left of a button's centred label (or in the middle
-- when there's no label; at the left edge for left-aligned labels)
local function placeIcon(button: TextButton, icon: Frame, size: number, gap: number)
	local function place()
		local text = button.Text
		local pad = button:FindFirstChild("LabelPadding") :: UIPadding?
		if text == "" then
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			if pad then
				pad.PaddingLeft = UDim.new(0, 0)
			end
			return
		end
		if button.TextXAlignment == Enum.TextXAlignment.Left then
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, Space.L, 0.5, 0)
			if pad then
				pad.PaddingLeft = UDim.new(0, Space.L + size + gap)
			end
			return
		end
		-- The label is centred in the padded area; the pair (icon + gap + label) is centred in the button
		local width = Components.textWidth(text, button.TextSize, button.FontFace)
		local room = button.AbsoluteSize.X - Space.M * 2 - size - gap
		if room > 0 then
			width = math.min(width, room)
		end
		local shift = (size + gap) / 2
		if pad then
			pad.PaddingLeft = UDim.new(0, Space.M + size + gap)
		end
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0.5, shift - width / 2 - gap - size, 0.5, 0)
	end
	button:GetPropertyChangedSignal("Text"):Connect(place)
	place()
end

-- A button. props.Variant = "Primary" | "Secondary" | "Ghost" | "Danger" | "Gold"
-- gives a fixed-size label (Builder Sans Bold 16, in capitals when 12 characters
-- or fewer, unless KeepCase); without a Variant (older code) the text scales to
-- fit like before. props.Icon draws a line icon beside the label (or alone when
-- the text is ""); props.Accent sets the hairline colour; props.Locked shows a
-- lock (clicks still run). Clicks are ignored while disabled (setDisabled).
function Components.button(text: string, props: { [string]: any }?, onClick: (() -> ())?): TextButton
	local given = props or {}
	local legacy = given.Variant == nil and given.TextSize == nil and given.Icon == nil
	local variant = Theme.Variants[given.Variant or "Secondary"] or Theme.Variants.Secondary
	local label = if typeof(text) == "string" then text else ""
	if not legacy and not given.KeepCase and (utf8.len(label) or #label) <= 12 then
		label = string.upper(label)
	end
	local merged: { [string]: any } = {
		BackgroundColor3 = variant.fill,
		BackgroundTransparency = variant.fillAlpha or 0,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Selectable = true,
		SelectionImageObject = noSelection,
		Text = label,
		FontFace = Faces.Bold,
		TextColor3 = variant.text,
		Size = UDim2.new(1, 0, 0, Theme.Size.Control),
	}
	if legacy then
		merged.TextScaled = true
		merged.SelectionImageObject = selectionImage
	else
		merged.TextSize = Theme.TextSize.Label
		merged.TextTruncate = Enum.TextTruncate.AtEnd
	end
	local accent = variant.stroke
	local strokeAlpha = variant.strokeAlpha
	for key, value in given do
		if key == "Accent" then
			accent = value
			strokeAlpha = math.min(strokeAlpha, 0.5)
		elseif key == "Font" then
			merged.FontFace = nil
			merged.Font = value
		elseif not BUTTON_KEYS[key] then
			merged[key] = value
		end
	end
	upgradeFont(merged)
	local outline = stroke(accent, 1, strokeAlpha)
	outline.Name = "Hairline"
	local labelPadding = padding(0, Space.M, 0, Space.M)
	labelPadding.Name = "LabelPadding"
	local children: { Instance } = { corner(Theme.SmallCorner), outline, labelPadding }
	if legacy then
		table.insert(children, make("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 14 }))
	end
	local button = make("TextButton", merged, children)

	local iconFrame: Frame? = nil
	if given.Icon then
		local size = given.IconSize or (if label == "" then 20 else 16)
		iconFrame = Icons.make(Icons.resolve(given.Icon), size, merged.TextColor3)
		local frame = iconFrame :: Frame
		frame.ZIndex = button.ZIndex + 1
		frame.Parent = button
		placeIcon(button, frame, size, Space.S)
	end
	local lockIcon: Frame? = nil

	-- The focus ring and leading bar (selected) every control shares
	local ring = make("Frame", {
		Name = "FocusRing",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-4, -4),
		Size = UDim2.new(1, 8, 1, 8),
		Visible = false,
		ZIndex = button.ZIndex + 2,
		Parent = button,
	}, {
		make("UICorner", { CornerRadius = UDim.new(0, 3) }),
		make("UIStroke", { Color = Colors.Text, Thickness = 2, Transparency = 0 }),
	})
	local bar = make("Frame", {
		Name = "Bar",
		Size = UDim2.new(0, 2, 1, 0),
		BackgroundColor3 = Colors.Accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = button.ZIndex + 1,
		Parent = button,
	})
	local pressScale = make("UIScale", { Name = "PressScale", Parent = button })

	-- Leaving the button tweens back to the colours it was created with
	local restFill = merged.BackgroundColor3
	local restAlpha = merged.BackgroundTransparency
	local restText = merged.TextColor3
	local custom = restFill ~= variant.fill
	local wasDimmed = false
	local buttonState, refreshButton = interactive(button, function(state, instant)
		local info = if instant then nil else Motion.Fast
		if state.locked and not lockIcon then
			local lock = Icons.make("lock", 16, restText)
			lock.Name = "Lock"
			lock.AnchorPoint = Vector2.new(0, 0.5)
			lock.Position = UDim2.new(0, Space.M, 0.5, 0)
			lock.ZIndex = button.ZIndex + 1
			lock.Parent = button
			lockIcon = lock
		end
		if lockIcon then
			lockIcon.Visible = state.locked
			labelPadding.PaddingLeft = UDim.new(0, if state.locked then Space.M + 24 else Space.M)
		end
		ring.Visible = state.focused and not state.disabled
		apply(bar, info, { BackgroundTransparency = if state.selected and not state.disabled then 0 else 1 })
		apply(pressScale, if instant then nil else Motion.Press, { Scale = if state.pressed and not state.disabled then 0.98 else 1 })
		if state.disabled ~= wasDimmed then
			wasDimmed = state.disabled
			fadeContent(button, if state.disabled then Theme.States.disabled.opacity else 1)
		end
		if state.disabled then
			apply(button, info, { BackgroundColor3 = restFill, BackgroundTransparency = Theme.fadeAlpha(restAlpha, Theme.States.disabled.opacity) })
			apply(outline, info, { Transparency = Theme.fadeAlpha(strokeAlpha, Theme.States.disabled.opacity) })
			return
		end
		local active = state.hovered or state.focused or state.pressed
		if not active and not state.selected then
			apply(button, info, { BackgroundColor3 = restFill, BackgroundTransparency = restAlpha, TextColor3 = restText })
			apply(outline, info, { Color = accent, Transparency = strokeAlpha })
			if iconFrame then
				Icons.tint(iconFrame, restText)
			end
			return
		end
		local fill = if state.pressed then variant.press else variant.hover
		if custom then
			-- Custom-coloured legacy buttons just brighten (or darken when pressed)
			fill = if state.pressed then restFill:Lerp(Color3.new(0, 0, 0), 0.12) else restFill:Lerp(Color3.new(1, 1, 1), 0.06)
		end
		local textColor = variant.hoverText or restText
		apply(button, info, {
			BackgroundColor3 = fill,
			BackgroundTransparency = if variant.hoverAlpha then variant.hoverAlpha else restAlpha,
			TextColor3 = textColor,
		})
		apply(outline, info, {
			Color = if state.selected then Colors.Accent elseif custom then accent else (if variant.stroke == Colors.Bronze then Colors.BronzeLight else accent),
			Transparency = if state.selected then 0 else variant.hoverStrokeAlpha or 0.1,
		})
		if iconFrame then
			Icons.tint(iconFrame, textColor)
		end
	end)
	selectors[button] = function(selected: boolean)
		buttonState.selected = selected
		refreshButton()
	end
	button.Activated:Connect(function()
		if onClick and not button:GetAttribute(DISABLED) then
			onClick()
		end
	end)
	if given.Locked then
		Components.setLocked(button, true, if typeof(given.Locked) == "string" then given.Locked else nil)
	end
	if given.Disabled then
		Components.setDisabled(button, true, given.Reason)
	end
	return button
end

-- A button's selected look (a toggle such as COMPARE): bronze frame and bar
function Components.setSelected(control: GuiButton, selected: boolean)
	control:SetAttribute("SNSelected", if selected then true else nil)
	local select = selectors[control]
	if select then
		select(selected)
	end
end

-- Icons, badges, chips ------------------------------------------------------------------------

-- A drawn icon inside a fixed square bezel, so icons always line up. `icon` is
-- an icon name, an alias or an emoji (resolved by Icons), or an ability table.
function Components.iconTile(icon: any, size: number?, color: Color3?): Frame
	local px = size or Theme.Size.IconTile
	local tint = color or Colors.Accent
	local name = if typeof(icon) == "table" then Icons.forAbility(icon) else Icons.resolve(icon)
	local tile = make("Frame", {
		Name = "IconTile",
		Size = UDim2.fromOffset(px, px),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, {
		corner(Theme.SmallCorner),
		stroke(tint, 1, 0.6),
	})
	local drawn = Icons.make(name, math.floor(px * 0.6 + 0.5), tint)
	drawn.AnchorPoint = Vector2.new(0.5, 0.5)
	drawn.Position = UDim2.fromScale(0.5, 0.5)
	drawn.Parent = tile
	return tile
end

-- A small capitals tag: "NEW", "OWNED", "LOCKED", "PREMIUM" (tinted, square)
function Components.badge(text: string, color: Color3?): Frame
	local tint = color or Colors.Accent
	local chip = make("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = tint,
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
	}, {
		corner(Theme.TinyCorner),
		stroke(tint, 1, 0.45),
		padding(0, Space.S, 0, Space.S),
	})
	Components.text({
		Name = "Text",
		Text = string.upper(text),
		Style = "overline",
		Color = tint:Lerp(Colors.Text, 0.35),
		AlignX = "Center",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.None,
		Parent = chip,
	})
	return chip
end

-- An outlined tag for roles and properties ("BRUISER", "CLOSE RANGE").
-- props: Color (text and hairline), Icon (a drawn icon before the text), and frame properties.
function Components.chip(text: string, props: { [string]: any }?): Frame
	local given = props or {}
	local tint = given.Color or Colors.TextDim
	local merged: { [string]: any } = {
		Name = "Chip",
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
	}
	for key, value in given do
		if key ~= "Color" and key ~= "Icon" then
			merged[key] = value
		end
	end
	local chip = make("Frame", merged, {
		corner(Theme.TinyCorner),
		stroke(Colors.Bronze, 1, 0.5),
		padding(0, Space.S + 2, 0, Space.S + 2),
	})
	Components.list(chip, 6, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
	if given.Icon then
		local drawn = Icons.make(Icons.resolve(given.Icon), 14, tint)
		drawn.LayoutOrder = 1
		drawn.Parent = chip
	end
	Components.text({
		Name = "Text",
		Text = string.upper(text),
		Style = "overline",
		Color = tint,
		LayoutOrder = 2,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.None,
		Parent = chip,
	})
	return chip
end

-- A key cap for input hints ("E", "Shift", "LB"): bronze-framed, Builder Sans Bold
function Components.keycap(text: string, props: { [string]: any }?): Frame
	local merged: { [string]: any } = {
		Name = "Keycap",
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
	}
	for key, value in (props or {}) :: { [string]: any } do
		merged[key] = value
	end
	local cap = make("Frame", merged, {
		corner(Theme.SmallCorner),
		stroke(Colors.BronzeLight, 1, 0.25),
		padding(0, Space.S, 0, Space.S),
		make("UISizeConstraint", { MinSize = Vector2.new(merged.Size.Y.Offset, 0) }),
	})
	Components.text({
		Name = "Key",
		Text = text,
		Style = "Label",
		Weight = "Bold",
		TextSize = 14,
		Color = Colors.Text,
		AlignX = "Center",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.None,
		Parent = cap,
	})
	return cap
end

-- A thin horizontal hairline
function Components.divider(props: { [string]: any }?): Frame
	local merged: { [string]: any } = {
		Name = "Divider",
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Colors.Bronze,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
	}
	for key, value in (props or {}) :: { [string]: any } do
		merged[key] = value
	end
	return make("Frame", merged)
end

-- The codex rule under headers: a bronze hairline with a short accent tick at
-- its start (the line is centred in whatever height the frame is given)
function Components.accentLine(props: { [string]: any }?): Frame
	local merged: { [string]: any } = {
		Name = "AccentLine",
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}
	for key, value in (props or {}) :: { [string]: any } do
		merged[key] = value
	end
	local frame = make("Frame", merged)
	make("Frame", {
		Name = "Rule",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Colors.Bronze,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = frame.ZIndex,
		Parent = frame,
	})
	make("Frame", {
		Name = "Tick",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(32, 2),
		BackgroundColor3 = Colors.Accent,
		BorderSizePixel = 0,
		ZIndex = frame.ZIndex,
		Parent = frame,
	})
	return frame
end

-- Layouts -----------------------------------------------------------------------------------

-- A vertical list layout (props can override, e.g. FillDirection)
function Components.list(parent: Instance, gap: number?, props: { [string]: any }?): UIListLayout
	local merged: { [string]: any } = {
		Padding = UDim.new(0, gap or Space.S),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Vertical,
		Parent = parent,
	}
	for key, value in (props or {}) :: { [string]: any } do
		merged[key] = value
	end
	return make("UIListLayout", merged)
end

-- A grid layout with fixed cells
function Components.grid(parent: Instance, cellSize: Vector2 | UDim2, gap: number?): UIGridLayout
	local cell = if typeof(cellSize) == "Vector2" then UDim2.fromOffset(cellSize.X, cellSize.Y) else cellSize
	return make("UIGridLayout", {
		CellSize = cell,
		CellPadding = UDim2.fromOffset(gap or Space.L, gap or Space.L),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

-- A scrolling area that grows with its content, with a thin bronze scrollbar.
-- props.Padding (number) pads the content; other keys are properties.
function Components.scroll(props: { [string]: any }?): ScrollingFrame
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Colors.BronzeLight,
		ScrollBarImageTransparency = 0.3,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		Selectable = false,
	}
	local pad = 0
	for key, value in (props or {}) :: { [string]: any } do
		if key == "Padding" then
			pad = value
		else
			merged[key] = value
		end
	end
	local frame = make("ScrollingFrame", merged)
	-- Room on the right so the scrollbar never touches the content
	make("UIPadding", {
		PaddingTop = UDim.new(0, pad),
		PaddingBottom = UDim.new(0, pad),
		PaddingLeft = UDim.new(0, pad),
		PaddingRight = UDim.new(0, pad + 8),
		Parent = frame,
	})
	return frame
end

-- Windows -----------------------------------------------------------------------------------

export type WindowParts = {
	panel: Frame,
	header: Frame,
	title: TextLabel,
	icon: Frame,
	close: TextButton,
	scale: UIScale,
	-- A slot in the header between the title and the close button (tabs, toggles)
	actions: Frame,
	-- The rule under the header
	rule: Frame,
}

-- Registration marks at a plate's four corners (the instrument detail)
local function cornerMarks(parent: GuiObject, length: number, color: Color3, alpha: number)
	for _, spec in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local sx, sy = spec[1], spec[2]
		make("Frame", {
			Name = "Mark",
			AnchorPoint = Vector2.new(sx, sy),
			Position = UDim2.new(sx, if sx == 0 then -1 else 1, sy, if sy == 0 then -1 else 1),
			Size = UDim2.fromOffset(length, 2),
			BackgroundColor3 = color,
			BackgroundTransparency = alpha,
			BorderSizePixel = 0,
			ZIndex = parent.ZIndex + 1,
			Parent = parent,
		})
		make("Frame", {
			Name = "Mark",
			AnchorPoint = Vector2.new(sx, sy),
			Position = UDim2.new(sx, if sx == 0 then -1 else 1, sy, if sy == 0 then -1 else 1),
			Size = UDim2.fromOffset(2, length),
			BackgroundColor3 = color,
			BackgroundTransparency = alpha,
			BorderSizePixel = 0,
			ZIndex = parent.ZIndex + 1,
			Parent = parent,
		})
	end
end
Components.cornerMarks = cornerMarks

-- Standard window chrome: a soft shadow, the graphite plate with its hairline
-- and corner marks, and a header with a drawn icon and the title in tracked
-- Accanthis capitals on the left, a header slot and the close button on the
-- right, and the codex rule under it. props: Title, Icon, Size (Vector2 or
-- UDim2), Accent, onClose, Padding (body padding, default 24), plus
-- Name/Position/AnchorPoint/Visible/ZIndex/Parent.
-- Returns (frame, body, parts); fill `body`.
function Components.window(props: { [string]: any }): (Frame, Frame, WindowParts)
	local size = props.Size or Theme.Size.DefaultWindow
	local frame = make("Frame", {
		Name = props.Name or "Window",
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = props.Position or UDim2.fromScale(0.5, 0.5),
		Size = if typeof(size) == "Vector2" then UDim2.fromOffset(size.X, size.Y) else size,
		BackgroundTransparency = 1,
		Visible = if props.Visible == nil then true else props.Visible,
		ZIndex = props.ZIndex or 1,
	})
	local scale = make("UIScale", { Parent = frame })

	-- A soft, low shadow so the plate sits above the blurred world
	for index, spec in { { grow = 40, drop = 16, alpha = 0.86, round = 24 }, { grow = 12, drop = 6, alpha = 0.7, round = 8 } } do
		make("Frame", {
			Name = "Shadow" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, spec.drop),
			Size = UDim2.new(1, spec.grow, 1, spec.grow),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = spec.alpha,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = frame,
		}, { corner(UDim.new(0, spec.round)) })
	end

	local panel = make("Frame", {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = Theme.Glass.Window,
		BorderSizePixel = 0,
		Active = true,
		ClipsDescendants = false,
		ZIndex = 2,
		Parent = frame,
	}, {
		corner(Theme.Corner),
		stroke(Colors.Bronze, 1, 0.5),
	})
	cornerMarks(panel, 14, Colors.BronzeLight, 0.15)

	local headerHeight = props.HeaderHeight or 64
	local pad = props.Padding or Theme.Grid.Pad
	local header = make("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, headerHeight),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = panel,
	}, { padding(0, Space.M, 0, Theme.Grid.Pad) })
	local icon = Icons.make(Icons.resolve(props.Icon or "facet"), 20, props.Accent or Colors.Accent)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(0, 0.5)
	icon.ZIndex = 2
	icon.Parent = header
	local title = Components.text({
		Name = "Title",
		Text = props.Title or "",
		Track = true,
		Style = "title",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 32, 0.5, 1),
		Size = UDim2.new(0.6, -32, 0, 36),
		ZIndex = 2,
		Parent = header,
	})
	local close = Components.button("", {
		Name = "Close",
		Variant = "Ghost",
		Icon = "cross",
		IconSize = 18,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(44, 44),
		ZIndex = 2,
		Parent = header,
	}, function()
		if props.onClose then
			props.onClose()
		end
	end)
	local actions = make("Frame", {
		Name = "HeaderActions",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(44 + Space.M), 0.5, 0),
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = header,
	})
	Components.list(actions, Space.S, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local rule = Components.accentLine({
		Position = UDim2.fromOffset(Theme.Grid.Pad, headerHeight),
		Size = UDim2.new(1, -Theme.Grid.Pad * 2, 0, 2),
		ZIndex = 2,
		Parent = panel,
	})

	local body = make("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, headerHeight + 2),
		Size = UDim2.new(1, 0, 1, -(headerHeight + 2)),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = panel,
	}, { padding(pad - Space.S, pad, pad, pad) })

	if props.Parent then
		frame.Parent = props.Parent
	end
	return frame, body, { panel = panel, header = header, title = title, icon = icon, close = close, scale = scale, actions = actions, rule = rule }
end

-- Fading a whole tree ---------------------------------------------------------------------------

local FADE_PROPS = {
	{ "GuiObject", "BackgroundTransparency" },
	{ "TextLabel", "TextTransparency" },
	{ "TextButton", "TextTransparency" },
	{ "TextBox", "TextTransparency" },
	{ "ImageLabel", "ImageTransparency" },
	{ "ImageButton", "ImageTransparency" },
	{ "ScrollingFrame", "ScrollBarImageTransparency" },
	{ "UIStroke", "Transparency" },
}

export type Fade = { cancel: () -> () }

-- Fades everything inside `root` in (from invisible to how it looks now) or
-- out (to invisible, then calls done and puts every value back while hidden).
-- Returns a handle whose cancel() stops the fade and restores the real values.
function Components.fade(root: Instance, show: boolean, info: TweenInfo, done: (() -> ())?): Fade
	if root.Parent == nil then
		-- Already removed: nothing to animate
		if done then
			done()
		end
		return { cancel = function() end }
	end
	local entries = {}
	local items = root:GetDescendants()
	table.insert(items, root)
	for _, item in items do
		for _, spec in FADE_PROPS do
			if item:IsA(spec[1]) then
				local value = (item :: any)[spec[2]]
				if value < 1 then
					table.insert(entries, { item = item, prop = spec[2], value = value })
				end
			end
		end
	end
	local tweens = {}
	local finished = false
	local function restore()
		for _, entry in entries do
			-- Skip anything destroyed while fading (e.g. a list that was rebuilt)
			if entry.item.Parent ~= nil then
				(entry.item :: any)[entry.prop] = entry.value
			end
		end
	end
	for _, entry in entries do
		if show then
			(entry.item :: any)[entry.prop] = 1
		end
		table.insert(tweens, tween(entry.item, info, { [entry.prop] = if show then entry.value else 1 }))
	end
	task.delay(info.Time, function()
		if finished then
			return
		end
		finished = true
		if done then
			done()
		end
		if not show then
			restore()
		end
	end)
	return {
		cancel = function()
			if finished then
				return
			end
			finished = true
			for _, running in tweens do
				running:Cancel()
			end
			restore()
		end,
	}
end

-- Cards ---------------------------------------------------------------------------------------

export type Card = {
	frame: TextButton,
	setSelected: (selected: boolean) -> (),
	setDisabled: (disabled: boolean) -> (),
	setLocked: (locked: boolean) -> (),
	isSelected: () -> boolean,
	isDisabled: () -> boolean,
	surface: Surface,
}

local CARD_KEYS = { Accent = true, Icon = true, Title = true, Body = true, Badge = true, BadgeColor = true, onClick = true, Selected = true, Disabled = true, Locked = true, Edge = true }

-- A selectable plate with all seven states.
-- props: Accent (the icon's colour), onClick, Selected, Disabled, Locked, and
-- optional standard content: Icon (drawn icon name or emoji), Title, Body (one
-- or two lines), Badge (text) + BadgeColor.
-- Returns (frame, card) where card has setSelected/setDisabled/setLocked/isSelected/isDisabled.
function Components.card(props: { [string]: any }?): (TextButton, Card)
	local given = props or {}
	local accent = given.Accent or Colors.Accent
	local merged: { [string]: any } = {
		Name = "Card",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Selectable = true,
		SelectionImageObject = noSelection,
		Size = UDim2.new(1, 0, 0, 76),
	}
	for key, value in given do
		if not CARD_KEYS[key] then
			merged[key] = value
		end
	end
	local frame = make("TextButton", merged, { corner(Theme.SmallCorner) })

	local titleLabel: TextLabel? = nil
	if given.Icon or given.Title then
		local hasIcon = given.Icon ~= nil
		local textLeft = if hasIcon then Space.L + 40 + Space.M else Space.L + 4
		if hasIcon then
			local tile = Components.iconTile(given.Icon, 40, accent)
			tile.AnchorPoint = Vector2.new(0, 0.5)
			tile.Position = UDim2.new(0, Space.L, 0.5, 0)
			tile.ZIndex = 2
			tile.Parent = frame
		end
		local rightRoom = if given.Badge then 112 else Space.L
		local content = make("Frame", {
			Name = "Content",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, textLeft, 0.5, 0),
			Size = UDim2.new(1, -(textLeft + rightRoom), 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = frame,
		})
		Components.list(content, 2)
		if given.Title then
			titleLabel = Components.text({ Name = "Title", Text = given.Title, Style = "strong", Color = Colors.TextDim, LayoutOrder = 1, ZIndex = 2, Parent = content })
		end
		if given.Body then
			Components.text({ Name = "Body", Text = given.Body, Style = "small", Color = Colors.TextMuted, Lines = 2, LayoutOrder = 2, ZIndex = 2, Parent = content })
		end
		if given.Badge then
			local badge = Components.badge(given.Badge, given.BadgeColor or Colors.TextMuted)
			badge.AnchorPoint = Vector2.new(1, 0.5)
			badge.Position = UDim2.new(1, -Space.L, 0.5, 0)
			badge.ZIndex = 2
			badge.Parent = frame
		end
	end

	local surface = Components.surface(frame, { Title = titleLabel, Lock = if given.Badge then UDim2.new(1, -120, 0.5, 0) else true, Edge = given.Edge })
	local state, refresh = interactive(frame, surface.render)

	local card: Card
	card = {
		frame = frame,
		surface = surface,
		setSelected = function(selected: boolean)
			state.selected = selected
			refresh()
		end,
		setDisabled = function(disabled: boolean)
			Components.setDisabled(frame, disabled)
			state.disabled = disabled
			refresh()
		end,
		setLocked = function(locked: boolean)
			Components.setLocked(frame, locked)
			state.locked = locked
			refresh()
		end,
		isSelected = function()
			return state.selected
		end,
		isDisabled = function()
			return state.disabled
		end,
	}
	frame.Activated:Connect(function()
		if given.onClick and not state.disabled then
			given.onClick()
		end
	end)
	if given.Selected then
		card.setSelected(true)
	end
	if given.Locked then
		card.setLocked(true)
	end
	if given.Disabled then
		card.setDisabled(true)
	end
	return frame, card
end

-- Tabs ----------------------------------------------------------------------------------------

export type TabSpec = { id: string, label: string, icon: string? }
export type Tabs = { select: (id: string) -> (), current: () -> string?, frame: Frame }

-- A row of text tabs on a hairline; the chosen one is ivory with a bronze
-- underline. Selects the first tab right away (calling onSelect).
function Components.tabs(parent: Instance, tabs: { TabSpec }, onSelect: (id: string) -> ()): Tabs
	local row = make("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, Theme.Size.Control),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Components.divider({ Name = "Baseline", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Parent = row })
	Components.list(row, Space.XS, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
	local refreshers_: { [string]: () -> () } = {}
	local states: { [string]: State } = {}
	local current: string? = nil

	local function select(id: string)
		if not refreshers_[id] then
			return
		end
		current = id
		for tabId, refresh in refreshers_ do
			states[tabId].selected = tabId == id
			refresh()
		end
		onSelect(id)
	end

	for order, spec in tabs do
		local drawn = if spec.icon and Icons.resolve(spec.icon) ~= "facet" then Icons.resolve(spec.icon) else nil
		local button = make("TextButton", {
			Name = "Tab_" .. spec.id,
			LayoutOrder = order,
			AutoButtonColor = false,
			Selectable = true,
			SelectionImageObject = noSelection,
			Size = UDim2.fromOffset(0, Theme.Size.Control),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Colors.PanelLight,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = string.upper(spec.label),
			FontFace = Faces.SemiBold,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Colors.TextDim,
			Parent = row,
		}, {
			corner(Theme.TinyCorner),
			padding(0, Space.L, 0, if drawn then Space.L + 24 else Space.L),
			make("UISizeConstraint", { MinSize = Vector2.new(88, Theme.Size.Control) }),
		})
		if drawn then
			local icon = Icons.make(drawn, 16, Colors.TextDim)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, Space.L, 0.5, 0)
			icon.Parent = button
		end
		-- Tabs sit on the baseline: no frame, just the underline and a faint fill on hover
		local surface = Components.surface(button, { Edge = "bottom", Flat = true, NoFrame = true, HoverAlpha = 0.7 })
		local state, refresh = interactive(button, function(state, instant)
			surface.render(state, instant)
			local info = if instant then nil else Motion.Fast
			apply(button, info, { TextColor3 = if state.selected or state.hovered or state.focused then Colors.Text else Colors.TextDim })
			local icon = button:FindFirstChild("Icon")
			if icon then
				Icons.tint(icon, if state.selected then Colors.Accent else Colors.TextDim)
			end
		end)
		states[spec.id] = state
		refreshers_[spec.id] = refresh
		button.Activated:Connect(function()
			if not state.disabled then
				select(spec.id)
			end
		end)
	end
	if tabs[1] then
		select(tabs[1].id)
	end
	return {
		select = select,
		current = function()
			return current
		end,
		frame = row,
	}
end

-- Segmented controls ------------------------------------------------------------------------

export type SegmentOption = { id: string, label: string, disabled: boolean?, locked: boolean? }
export type Segmented = {
	frame: Frame,
	set: (id: string, notify: boolean?) -> (),
	get: () -> string?,
	setDisabled: (id: string, disabled: boolean) -> (),
	buttons: { [string]: TextButton },
}

-- A row of joined options inside one hairline frame; exactly one is chosen
-- (filled, ivory, bronze underline). props: Name, Height (44), and frame properties.
function Components.segmented(parent: Instance?, options: { SegmentOption }, value: string?, onChange: (id: string) -> (), props: { [string]: any }?): Segmented
	local given = props or {}
	local height = given.Height or Theme.Size.Control
	local merged: { [string]: any } = {
		Name = "Segmented",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}
	for key, prop in given do
		if key ~= "Height" then
			merged[key] = prop
		end
	end
	local frame = make("Frame", merged, { corner(Theme.SmallCorner), stroke(Colors.Bronze, 1, 0.45) })
	local count = math.max(1, #options)
	local current: string? = value
	local buttons: { [string]: TextButton } = {}
	local states: { [string]: State } = {}
	local paint: { [string]: () -> () } = {}

	local function set(id: string, notify: boolean?)
		if not buttons[id] then
			return
		end
		current = id
		for optionId, refresh in paint do
			states[optionId].selected = optionId == id
			refresh()
		end
		if notify then
			onChange(id)
		end
	end

	for index, option in options do
		local button = make("TextButton", {
			Name = "Segment_" .. option.id,
			LayoutOrder = index,
			AutoButtonColor = false,
			Selectable = true,
			SelectionImageObject = noSelection,
			Position = UDim2.new((index - 1) / count, 0, 0, 0),
			Size = UDim2.new(1 / count, 0, 1, 0),
			BackgroundColor3 = Colors.PanelHover,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = string.upper(option.label),
			FontFace = Faces.SemiBold,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Colors.TextDim,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = frame,
		}, { padding(0, Space.S, 0, Space.S) })
		if index > 1 then
			make("Frame", {
				Name = "Separator",
				Position = UDim2.fromOffset(0, Space.S),
				Size = UDim2.new(0, 1, 1, -Space.S * 2),
				BackgroundColor3 = Colors.Bronze,
				BackgroundTransparency = 0.55,
				BorderSizePixel = 0,
				Parent = button,
			})
		end
		local surface = Components.surface(button, { Edge = "bottom", Flat = true, NoFrame = true, Lock = UDim2.new(0, Space.S + 16, 0.5, 0) })
		local state, refresh = interactive(button, function(state, instant)
			surface.render(state, instant)
			local info = if instant then nil else Motion.Fast
			if state.selected and not state.disabled then
				apply(button, info, { BackgroundColor3 = Colors.PanelHover, BackgroundTransparency = 0.05 })
			end
			apply(button, info, { TextColor3 = if state.selected then Colors.Text elseif state.hovered or state.focused then Colors.Text else Colors.TextDim })
		end)
		states[option.id] = state
		paint[option.id] = refresh
		buttons[option.id] = button
		button.Activated:Connect(function()
			if not state.disabled and current ~= option.id then
				set(option.id, true)
			end
		end)
		if option.disabled then
			Components.setDisabled(button, true)
		end
		if option.locked then
			Components.setLocked(button, true)
		end
	end
	if current and buttons[current] then
		set(current, false)
	end
	if parent then
		frame.Parent = parent
	end
	return {
		frame = frame,
		set = set,
		get = function()
			return current
		end,
		setDisabled = function(id: string, disabled: boolean)
			local button = buttons[id]
			if button then
				Components.setDisabled(button, disabled)
			end
		end,
		buttons = buttons,
	}
end

-- Prices ----------------------------------------------------------------------------------------

local function priceChip(parent: Instance, order: number, text: string, icon: string?, color: Color3, textSize: number)
	local chip = make("Frame", {
		Name = "PriceChip",
		LayoutOrder = order,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		corner(Theme.TinyCorner),
		stroke(color, 1, 0.55),
		padding(0, Space.S + 2, 0, Space.S + 2),
	})
	Components.list(chip, 6, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
	if icon then
		local drawn = Icons.make(icon, math.max(14, textSize), color)
		drawn.LayoutOrder = 1
		drawn.Parent = chip
	end
	Components.text({
		Name = "Amount",
		Text = text,
		Style = "number",
		Weight = "SemiBold",
		TextSize = textSize,
		Color = if icon then Colors.Text else color,
		AlignX = "Center",
		LayoutOrder = 2,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.None,
		Parent = chip,
	})
	return chip
end

-- Shows a price as chips: a drawn coin with Money, a drawn gem with Gems, and
-- Robux as "R$ 6,666". An empty price shows "FREE".
-- props: Height (default 30), TextSize, and frame properties.
function Components.price(parent: Instance?, price: { money: number?, gems: number?, robux: number? }, props: { [string]: any }?): Frame
	local given = props or {}
	local height = given.Height or 30
	local textSize = given.TextSize or Theme.TextSize.Small
	local merged: { [string]: any } = {
		Name = "Price",
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
	}
	for key, value in given do
		if key ~= "Height" and key ~= "TextSize" then
			merged[key] = value
		end
	end
	local frame = make("Frame", merged)
	Components.list(frame, Space.S, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
	local any = false
	if typeof(price.money) == "number" and price.money > 0 then
		any = true
		priceChip(frame, 1, formatNumber(price.money), "coin", Colors.Money, textSize)
	end
	if typeof(price.gems) == "number" and price.gems > 0 then
		any = true
		priceChip(frame, 2, formatNumber(price.gems), "gem", Colors.Gems, textSize)
	end
	if typeof(price.robux) == "number" and price.robux > 0 then
		any = true
		priceChip(frame, 3, "R$ " .. formatNumber(price.robux), nil, Colors.Robux, textSize)
	end
	if not any then
		priceChip(frame, 1, "FREE", nil, Colors.Success, textSize)
	end
	if parent then
		frame.Parent = parent
	end
	return frame
end

-- Bars --------------------------------------------------------------------------------------------

-- A horizontal fill bar. Returns the frame and a function set(fraction, color?)
function Components.bar(props: { [string]: any }?, fillColor: Color3): (Frame, (number, Color3?) -> ())
	local merged = {
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}
	for key, value in (props or {}) :: { [string]: any } do
		merged[key] = value
	end
	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = fillColor,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, { corner(Theme.TinyCorner) })
	local frame = make("Frame", merged, { corner(Theme.TinyCorner), fill })
	local current = 1
	local function set(fraction: number, color: Color3?)
		fraction = math.clamp(if fraction == fraction then fraction else 0, 0, 1)
		if math.abs(fraction - current) > 0.001 then
			current = fraction
			tween(fill, Motion.Normal, { Size = UDim2.fromScale(fraction, 1) })
		end
		if color then
			fill.BackgroundColor3 = color
		end
	end
	return frame, set
end

-- A labelled bar: capitals caption on the left, the value on the right, a fine
-- bar underneath. props: Label, Value, plus frame properties.
-- Returns (frame, set(fraction, valueText?, color?)).
function Components.progress(props: { [string]: any }?, color: Color3?): (Frame, (number, string?, Color3?) -> ())
	local given = props or {}
	local merged: { [string]: any } = {
		Name = "Progress",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
	}
	for key, value in given do
		if key ~= "Label" and key ~= "Value" then
			merged[key] = value
		end
	end
	local frame = make("Frame", merged)
	Components.text({
		Name = "Label",
		Text = given.Label or "",
		Style = "overline",
		Size = UDim2.new(0.6, 0, 0, 18),
		Parent = frame,
	})
	local valueText = Components.text({
		Name = "Value",
		Text = given.Value or "",
		Style = "number",
		TextSize = 15,
		Color = Colors.Text,
		AlignX = "Right",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.4, 0, 0, 18),
		Parent = frame,
	})
	local track, set = Components.bar({
		Name = "Track",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 6),
		Parent = frame,
	}, color or Colors.Accent)
	stroke(Colors.Bronze, 1, 0.7).Parent = track
	set(0)
	return frame, function(fraction: number, text: string?, newColor: Color3?)
		set(fraction, newColor)
		if text then
			valueText.Text = text
		end
	end
end

-- Setting rows ----------------------------------------------------------------------------------

-- Rows put their label (and an optional description) on the left and their
-- control in a fixed column on the right, so a stack of rows lines up.
local ROW_KEYS = { Description = true, Format = true, Live = true, Label = true, ControlWidth = true, Grouped = true, Flat = true, Height = true }
local CONTROL_WIDTH = 320

local function rowHeight(description: string?): number
	return if description then 68 else 56
end

local function rowText(row: GuiObject, label: string, description: string?, controlWidth: number)
	local column = make("Frame", {
		Name = "Text",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Space.L, 0.5, 0),
		Size = UDim2.new(1, -(Space.L * 3 + controlWidth), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = row.ZIndex + 1,
		Parent = row,
	})
	Components.list(column, 2)
	local title = Components.text({ Name = "Label", Text = label, Style = "strong", TextSize = 16, Color = Colors.Text, LayoutOrder = 1, ZIndex = row.ZIndex + 1, Parent = column })
	if description then
		Components.text({ Name = "Description", Text = description, Style = "small", Color = Colors.TextDim, LayoutOrder = 2, ZIndex = row.ZIndex + 1, Parent = column })
	end
	return title
end

local function rowControl(row: GuiObject, controlWidth: number): Frame
	return make("Frame", {
		Name = "Control",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -Space.L, 0.5, 0),
		Size = UDim2.new(0, controlWidth, 0, Theme.Size.Control),
		BackgroundTransparency = 1,
		ZIndex = row.ZIndex + 1,
		Parent = row,
	})
end

local function rowMerged(className: string, height: number, props: { [string]: any }?): { [string]: any }
	local merged: { [string]: any } = {
		Name = "Setting",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = if props and props.Grouped then 0 else 0.04,
		BorderSizePixel = 0,
	}
	if className == "TextButton" then
		merged.AutoButtonColor = false
		merged.Text = ""
		merged.Selectable = true
		merged.SelectionImageObject = noSelection
	end
	for key, value in (props or {}) :: { [string]: any } do
		if not ROW_KEYS[key] then
			merged[key] = value
		end
	end
	return merged
end

-- A static row with a slot for any control on the right.
-- props: Label, Description, ControlWidth (default 320), Grouped (inside a
-- section), Height, plus frame properties. Returns (row, control).
function Components.row(props: { [string]: any }?): (Frame, Frame)
	local given = props or {}
	local width = given.ControlWidth or CONTROL_WIDTH
	local row = make("Frame", rowMerged("Frame", given.Height or rowHeight(given.Description), given), {
		corner(if given.Grouped then UDim.new(0, 0) else Theme.SmallCorner),
	})
	if not given.Grouped then
		stroke(Colors.Bronze, 1, 0.62).Parent = row
	end
	rowText(row, given.Label or "", given.Description, width)
	return row, rowControl(row, width)
end

-- A titled group of rows: capitals title, then one hairline frame whose rows
-- are separated by 1 px rules. Returns (section, rows); parent rows (built with
-- Grouped = true) to `rows`.
function Components.section(parent: Instance?, title: string, props: { [string]: any }?): (Frame, Frame)
	local merged: { [string]: any } = {
		Name = "Section",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}
	for key, value in (props or {}) :: { [string]: any } do
		merged[key] = value
	end
	local section = make("Frame", merged)
	Components.list(section, Space.S)
	Components.text({ Name = "Title", Text = title, Style = "overline", Color = Colors.TextMuted, LayoutOrder = 1, Parent = section })
	local rows = make("Frame", {
		Name = "Rows",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.Bronze,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Parent = section,
	}, { corner(Theme.SmallCorner), stroke(Colors.Bronze, 1, 0.5) })
	Components.list(rows, 1)
	if parent then
		section.Parent = parent
	end
	return section, rows
end

-- Toggles and sliders -------------------------------------------------------------------------------

-- A labelled on/off row. The whole row is the hit target; the switch is a
-- square slot with a sliding block, and the state is also written (ON / OFF).
-- props: Description (a line under the label), Grouped, plus row properties.
-- Returns (row, set(value)): set() changes the look without calling onChange.
function Components.toggle(label: string, value: boolean, onChange: (boolean) -> (), props: { [string]: any }?): (TextButton, (boolean) -> ())
	local description = props and props.Description
	local grouped = props ~= nil and props.Grouped == true
	local row = make("TextButton", rowMerged("TextButton", rowHeight(description), props), {
		corner(if grouped then UDim.new(0, 0) else Theme.SmallCorner),
	})
	local title = rowText(row, label, description, 120)
	local stateText = Components.text({
		Name = "State",
		Style = "overline",
		AlignX = "Right",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(Space.L + 48 + Space.M), 0.5, 0),
		Size = UDim2.fromOffset(40, 18),
		ZIndex = row.ZIndex + 1,
		Parent = row,
	})
	local track = make("Frame", {
		Name = "Switch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -Space.L, 0.5, 0),
		Size = UDim2.fromOffset(48, 24),
		BorderSizePixel = 0,
		ZIndex = row.ZIndex + 1,
		Parent = row,
	}, { corner(Theme.SmallCorner) })
	local trackStroke = stroke(Colors.Bronze, 1, 0.4)
	trackStroke.Parent = track
	local knob = make("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(18, 18),
		BorderSizePixel = 0,
		ZIndex = row.ZIndex + 2,
		Parent = track,
	}, { corner(Theme.TinyCorner) })

	local on = value == true
	local function render(instant: boolean?)
		local info = if instant then nil else Motion.Normal
		apply(track, info, { BackgroundColor3 = if on then Colors.Accent else Colors.Ink, BackgroundTransparency = if on then 0 else 0.2 })
		apply(trackStroke, info, { Transparency = if on then 0.6 else 0.4 })
		apply(knob, info, {
			Position = if on then UDim2.new(1, -21, 0.5, 0) else UDim2.new(0, 3, 0.5, 0),
			BackgroundColor3 = if on then Colors.Ink else Colors.TextDim,
		})
		stateText.Text = if on then "ON" else "OFF"
		stateText.TextColor3 = if on then Colors.Accent else Colors.TextMuted
	end
	render(true)
	local surface = Components.surface(row, {
		Title = title,
		NoFrame = grouped,
		Fill = if grouped then Colors.PanelLight else nil,
		FillAlpha = if grouped then 0 else nil,
	})
	surface.title = nil
	interactive(row, surface.render)
	row.Activated:Connect(function()
		if row:GetAttribute(DISABLED) then
			return
		end
		on = not on
		render()
		onChange(on)
	end)
	return row, function(newValue: boolean)
		if (newValue == true) ~= on then
			on = newValue == true
			render()
		end
	end
end

local function snap(value: number, min: number, max: number, step: number): number
	local stepped = if step > 0 then min + math.floor((value - min) / step + 0.5) * step else value
	-- Remove float noise (0.30000000000000004)
	stepped = math.floor(stepped * 1e6 + 0.5) / 1e6
	return math.clamp(stepped, min, max)
end
Components.snap = snap

-- A labelled slider row: the label on the left; on the right a minus button, a
-- draggable track, a plus button (for gamepad and touch) and the value.
-- props: Description, Format (value -> text), Live (default true; false = only
-- call onChange when the drag ends), Grouped, plus row properties.
-- Returns (frame, set(value)): set() changes the look without calling onChange.
function Components.slider(label: string, min: number, max: number, step: number, value: number, onChange: (number) -> (), props: { [string]: any }?): (Frame, (number) -> ())
	local given = props or {}
	local format = given.Format or function(v: number)
		return string.format("%.2f", v)
	end
	local live = given.Live ~= false
	local grouped = given.Grouped == true
	local merged = rowMerged("Frame", rowHeight(given.Description), given)
	merged.Name = if given.Name then given.Name else "Slider"
	local frame = make("Frame", merged, { corner(if grouped then UDim.new(0, 0) else Theme.SmallCorner) })
	if not grouped then
		stroke(Colors.Bronze, 1, 0.62).Parent = frame
	end
	rowText(frame, label, given.Description, CONTROL_WIDTH)
	local controls = rowControl(frame, CONTROL_WIDTH)
	controls.Name = "Controls"
	local valueText = Components.text({
		Name = "Value",
		Style = "number",
		Color = Colors.Text,
		AlignX = "Right",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(56, 22),
		Parent = controls,
	})

	local current = snap(value, min, max, step)
	local fill: Frame
	local knob: Frame
	local function render()
		local fraction = if max > min then (current - min) / (max - min) else 0
		fill.Size = UDim2.fromScale(fraction, 1)
		knob.Position = UDim2.fromScale(fraction, 0.5)
		valueText.Text = format(current)
	end
	local function setValue(newValue: number, notify: boolean)
		local snapped = snap(newValue, min, max, step)
		if snapped == current then
			return
		end
		current = snapped
		render()
		if notify then
			onChange(current)
		end
	end

	local stepWidth = Theme.Size.Control
	local readout = 56 + Space.M
	local minus = Components.button("", {
		Name = "Minus",
		Variant = "Secondary",
		Icon = "minus",
		IconSize = 16,
		Size = UDim2.fromOffset(stepWidth, stepWidth),
		Parent = controls,
	}, function()
		setValue(current - step, true)
	end)
	local plus = Components.button("", {
		Name = "Plus",
		Variant = "Secondary",
		Icon = "plus",
		IconSize = 16,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -readout, 0, 0),
		Size = UDim2.fromOffset(stepWidth, stepWidth),
		Parent = controls,
	}, function()
		setValue(current + step, true)
	end)
	local _ = minus
	local _ = plus

	-- The track: a wide invisible hit area with a fine bar in the middle
	local hit = make("TextButton", {
		Name = "Track",
		AutoButtonColor = false,
		Text = "",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(stepWidth + Space.M, 0),
		Size = UDim2.new(1, -(stepWidth * 2 + Space.M * 2 + readout), 1, 0),
		Selectable = false,
		Parent = controls,
	})
	local bar = make("Frame", {
		Name = "Rail",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = hit,
	}, { corner(Theme.TinyCorner), stroke(Colors.Bronze, 1, 0.55) })
	fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = Colors.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	}, { corner(Theme.TinyCorner) })
	knob = make("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(10, 22),
		BackgroundColor3 = Colors.Text,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = bar,
	}, { corner(Theme.TinyCorner), stroke(Colors.Ink, 1, 0.2) })

	-- Dragging (mouse or touch): follow the pointer until it's released
	local function valueAt(x: number): number
		local left = bar.AbsolutePosition.X
		local width = math.max(1, bar.AbsoluteSize.X)
		return min + math.clamp((x - left) / width, 0, 1) * (max - min)
	end
	local dragging: { RBXScriptConnection }? = nil
	local function stopDrag()
		if dragging then
			for _, connection in dragging do
				connection:Disconnect()
			end
			dragging = nil
			if not live then
				onChange(current)
			end
		end
	end
	hit.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		stopDrag()
		setValue(valueAt(input.Position.X), live)
		dragging = {
			UserInputService.InputChanged:Connect(function(moved: InputObject)
				if moved.UserInputType == Enum.UserInputType.MouseMovement or moved.UserInputType == Enum.UserInputType.Touch then
					setValue(valueAt(moved.Position.X), live)
				end
			end),
			UserInputService.InputEnded:Connect(function(ended: InputObject)
				if ended.UserInputType == kind then
					stopDrag()
				end
			end),
		}
	end)
	frame.Destroying:Connect(stopDrag)
	render()
	return frame, function(newValue: number)
		setValue(newValue, false)
	end
end

return Components
