-- Building blocks for every interface, so every window, card, button, bar and
-- label looks and behaves the same: glass panels, fixed type sizes from the
-- Theme, hover/press/selected/disabled states, gamepad selection and 44px
-- touch targets.
--
-- Older code uses make, corner, stroke, padding, panel, label, button and bar
-- (label and button with TextScaled + MaxTextSize); those keep working.
-- New code uses text() and the newer components below with fixed text sizes.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local Components = {}

local Colors = Theme.Colors
local Faces = Theme.Faces
local Motion = Theme.Motion
local Space = Theme.Space

-- Attribute that marks a control as disabled (checked before running clicks)
local DISABLED = "SNDisabled"

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

function Components.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return make("UIStroke", {
		Color = color or Colors.Cyan,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.4,
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

-- Swaps a legacy Enum font for the matching Builder Sans weight, in place
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

-- The soft top-to-bottom shading every glass surface uses
local function glassGradient(): UIGradient
	return make("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 202, 228)),
		Rotation = 90,
	})
end
Components.glassGradient = glassGradient

-- One shared rounded cyan outline drawn around whatever the gamepad selects
local selectionImage = make("Frame", {
	Name = "SNSelection",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 8, 1, 8),
	Position = UDim2.fromOffset(-4, -4),
}, {
	make("UICorner", { CornerRadius = UDim.new(0, 12) }),
	make("UIStroke", { Color = Colors.Cyan, Thickness = 2.5, Transparency = 0 }),
})
Components.selectionImage = selectionImage

-- Panels -------------------------------------------------------------------------

-- A dark glass panel with rounded corners, a thin light outline and a subtle gradient
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
		stroke(Colors.Stroke, 1.5, Theme.Glass.StrokeTransparency),
		glassGradient(),
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
		make("UITextSizeConstraint", { MaxTextSize = maxTextSize }),
	})
end

local TEXT_KEYS = { Style = true, Weight = true, Color = true, Wrap = true, AlignX = true, AlignY = true }
local ALIGN_X = { Left = Enum.TextXAlignment.Left, Center = Enum.TextXAlignment.Center, Right = Enum.TextXAlignment.Right }
local ALIGN_Y = { Top = Enum.TextYAlignment.Top, Center = Enum.TextYAlignment.Center, Bottom = Enum.TextYAlignment.Bottom }

-- A fixed-size label from the type scale.
--   Style = "Micro" | "Caption" | "Body" | "Label" | "Heading" | "Title" | "Display" (default "Body")
--   Weight = a Theme.Faces name or a Font; Color = Color3 or a Theme.Colors name
--   Wrap = true for paragraphs (wraps and grows downward); otherwise one line cut with "…"
--   AlignX = "Left" | "Center" | "Right"; AlignY = "Top" | "Center" | "Bottom"
-- Any other key is set on the TextLabel as a property.
function Components.text(props: { [string]: any }?): TextLabel
	local given = props or {}
	local style = Theme.TextStyles[given.Style or "Body"] or Theme.TextStyles.Body
	local size = given.TextSize or style.size
	local wrap = given.Wrap == true
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		FontFace = faceFor(given.Weight or style.face),
		TextSize = size,
		TextColor3 = colorFor(given.Color, (Colors :: any)[style.color]),
		TextXAlignment = ALIGN_X[given.AlignX or "Left"] or given.AlignX,
		TextYAlignment = ALIGN_Y[given.AlignY or "Center"] or given.AlignY,
		TextWrapped = wrap,
		TextTruncate = if wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		Size = if wrap then UDim2.fromScale(1, 0) else UDim2.new(1, 0, 0, size + 6),
		AutomaticSize = if wrap then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
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

-- Interaction states ---------------------------------------------------------------------

export type Look = {
	render: (state: { hovered: boolean, pressed: boolean, selected: boolean, disabled: boolean }, instant: boolean?) -> (),
}

-- Wires hover (mouse or gamepad selection), press, and the disabled flag to a
-- render function. Returns the state table and a refresh function.
local function interactive(button: GuiButton, render: (state: any, instant: boolean?) -> ())
	local state = { hovered = false, pressed = false, selected = false, disabled = false }
	local function refresh(instant: boolean?)
		render(state, instant)
	end
	local function setHover(value: boolean)
		state.hovered = value
		if not value then
			state.pressed = false
		end
		refresh()
	end
	button.MouseEnter:Connect(function()
		setHover(true)
	end)
	button.MouseLeave:Connect(function()
		setHover(false)
	end)
	button.SelectionGained:Connect(function()
		setHover(true)
	end)
	button.SelectionLost:Connect(function()
		setHover(false)
	end)
	button.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA then
			state.pressed = true
			refresh()
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA then
			state.pressed = false
			refresh()
		end
	end)
	-- Components.setDisabled flips this attribute
	button:GetAttributeChangedSignal(DISABLED):Connect(function()
		state.disabled = button:GetAttribute(DISABLED) == true
		refresh()
	end)
	refresh(true)
	return state, refresh
end
Components.interactive = interactive

-- Dims every text inside `root` to at least 50% transparency, remembering the
-- original on an attribute so undimming puts it back exactly
local BASE_ALPHA = "SNTextAlpha"
local function dimTexts(root: Instance, dim: boolean)
	local items = root:GetDescendants()
	table.insert(items, root)
	for _, item in items do
		if item:IsA("TextLabel") or item:IsA("TextButton") then
			local base = item:GetAttribute(BASE_ALPHA)
			if dim then
				if base == nil then
					item:SetAttribute(BASE_ALPHA, item.TextTransparency)
				end
				item.TextTransparency = math.max(item.TextTransparency, 0.5)
			elseif typeof(base) == "number" then
				item.TextTransparency = base
				item:SetAttribute(BASE_ALPHA, nil)
			end
		end
	end
end

-- Buttons ---------------------------------------------------------------------------------

local BUTTON_KEYS = { Accent = true, Variant = true, Disabled = true }

-- A button. props.Variant = "Primary" | "Secondary" | "Ghost" | "Danger" | "Gold"
-- gives a fixed-size label (Theme Label size); without a Variant (older code)
-- the text scales to fit like before. props.Accent sets the outline color.
-- Clicks are ignored while the button is disabled (Components.setDisabled).
function Components.button(text: string, props: { [string]: any }?, onClick: (() -> ())?): TextButton
	local given = props or {}
	local legacy = given.Variant == nil and given.TextSize == nil
	local variant = Theme.Variants[given.Variant or "Secondary"] or Theme.Variants.Secondary
	local merged: { [string]: any } = {
		BackgroundColor3 = variant.fill,
		BackgroundTransparency = variant.fillAlpha or 0,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Selectable = true,
		SelectionImageObject = selectionImage,
		Text = text,
		FontFace = Faces.Bold,
		TextColor3 = variant.text,
		Size = UDim2.new(1, 0, 0, Theme.Size.Control),
	}
	if legacy then
		merged.TextScaled = true
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
	local outline = stroke(accent, 1.5, strokeAlpha)
	local children: { Instance } = {
		corner(Theme.SmallCorner),
		outline,
		padding(0, Space.M, 0, Space.M),
	}
	if legacy then
		table.insert(children, make("UITextSizeConstraint", { MaxTextSize = 20 }))
	else
		-- A soft top highlight for depth (legacy callers add their own gradients)
		table.insert(children, make("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 210, 228)),
			Rotation = 90,
		}))
	end
	local button = make("TextButton", merged, children)

	-- Leaving the button tweens back to the colors it was created with
	local restFill = merged.BackgroundColor3
	local restAlpha = merged.BackgroundTransparency
	local restText = merged.TextColor3
	local wasDisabled = false
	interactive(button, function(state, instant)
		local info = if instant then nil else Motion.Fast
		if state.disabled ~= wasDisabled then
			wasDisabled = state.disabled
			dimTexts(button, state.disabled)
		end
		if state.disabled then
			apply(button, info, { BackgroundColor3 = restFill, BackgroundTransparency = math.max(restAlpha, 0.45) })
			apply(outline, info, { Transparency = 0.85 })
			return
		end
		if not state.hovered and not state.pressed then
			apply(button, info, { BackgroundColor3 = restFill, BackgroundTransparency = restAlpha, TextColor3 = restText })
			apply(outline, info, { Transparency = strokeAlpha })
			return
		end
		local fill = if state.pressed then variant.press else variant.hover
		if legacy and merged.BackgroundColor3 ~= variant.fill then
			-- Custom-colored legacy buttons just brighten
			fill = if state.pressed then Colors.Panel else Colors.PanelHover
		end
		apply(button, info, {
			BackgroundColor3 = fill,
			BackgroundTransparency = if variant.hoverAlpha then variant.hoverAlpha else restAlpha,
			TextColor3 = variant.hoverText or restText,
		})
		apply(outline, info, { Transparency = 0 })
	end)
	button.Activated:Connect(function()
		if onClick and not button:GetAttribute(DISABLED) then
			onClick()
		end
	end)
	if given.Disabled then
		Components.setDisabled(button, true)
	end
	return button
end

-- Turns a button or card on or off (50% text, no hover, clicks ignored)
function Components.setDisabled(control: GuiButton, disabled: boolean)
	control:SetAttribute(DISABLED, if disabled then true else nil)
	control.Selectable = not disabled
end

function Components.isDisabled(control: GuiButton): boolean
	return control:GetAttribute(DISABLED) == true
end

-- Icons -------------------------------------------------------------------------------------

-- An emoji inside a fixed rounded tile, so icons always line up
function Components.iconTile(icon: string, size: number?, color: Color3?): Frame
	local px = size or Theme.Size.IconTile
	local accent = color or Colors.Cyan
	return make("Frame", {
		Name = "IconTile",
		Size = UDim2.fromOffset(px, px),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
	}, {
		corner(UDim.new(0, math.max(6, math.floor(px * 0.28)))),
		stroke(accent, 1, 0.55),
		make("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 160, 190)),
			Rotation = 90,
		}),
		make("TextLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Text = icon,
			TextSize = math.floor(px * 0.56),
			FontFace = Faces.Bold,
			TextColor3 = Colors.Text,
		}),
	})
end

-- A small pill: "NEW", "OWNED", "LOCKED", "PREMIUM"
function Components.badge(text: string, color: Color3?): Frame
	local fill = color or Colors.Cyan
	local pill = make("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = fill,
		BorderSizePixel = 0,
	}, {
		corner(Theme.PillCorner),
		padding(0, Space.S, 0, Space.S),
	})
	Components.text({
		Text = string.upper(text),
		Style = "Micro",
		Weight = "ExtraBold",
		Color = Colors.TextOnLight,
		AlignX = "Center",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.None,
		Parent = pill,
	})
	return pill
end

-- A thin horizontal line
function Components.divider(props: { [string]: any }?): Frame
	local merged: { [string]: any } = {
		Name = "Divider",
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Colors.Stroke,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
	}
	for key, value in (props or {}) :: { [string]: any } do
		merged[key] = value
	end
	return make("Frame", merged)
end

-- A short cyan-to-violet line that fades out (under headers)
function Components.accentLine(props: { [string]: any }?): Frame
	local merged: { [string]: any } = {
		Name = "AccentLine",
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}
	for key, value in (props or {}) :: { [string]: any } do
		merged[key] = value
	end
	return make("Frame", merged, {
		make("UIGradient", {
			Color = ColorSequence.new(Colors.Cyan, Colors.Purple),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.55, 0.25),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
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
		CellPadding = UDim2.fromOffset(gap or Space.M, gap or Space.M),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

-- A scrolling area that grows with its content, with a thin accent scrollbar.
-- props.Padding (number) pads the content; other keys are properties.
function Components.scroll(props: { [string]: any }?): ScrollingFrame
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Colors.Cyan,
		ScrollBarImageTransparency = 0.35,
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
		PaddingRight = UDim.new(0, pad + 6),
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
}

-- Standard window chrome: a soft shadow, a glass panel, and a header with an
-- icon tile and title on the left, a close button on the right and an accent
-- line under it. props: Title, Icon, Size (Vector2 or UDim2), Accent, onClose,
-- plus Name/Position/AnchorPoint/Visible/ZIndex/Parent.
-- Returns (frame, body, parts); fill `body`.
function Components.window(props: { [string]: any }): (Frame, Frame, WindowParts)
	local size = props.Size or Theme.Size.DefaultWindow
	local accent = props.Accent or Colors.Cyan
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

	-- Soft drop shadow: three widening, fading rounded layers under the panel
	for index, spec in { { grow = 28, drop = 10, alpha = 0.9 }, { grow = 16, drop = 6, alpha = 0.82 }, { grow = 6, drop = 3, alpha = 0.7 } } do
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
		}, { corner(UDim.new(0, 12 + spec.grow // 2)) })
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
		stroke(Colors.Stroke, 1.5, 0.68),
		glassGradient(),
	})
	-- A faint sheen across the top of the glass
	make("Frame", {
		Name = "Sheen",
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		Parent = panel,
	}, {
		corner(Theme.Corner),
		make("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.55),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	local headerHeight = Theme.Size.Header
	local header = make("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, headerHeight),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = panel,
	}, { padding(0, Space.M, 0, Space.L) })
	local icon = Components.iconTile(props.Icon or "✦", 32, accent)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(0, 0.5)
	icon.Parent = header
	local title = Components.text({
		Name = "Title",
		Text = string.upper(props.Title or ""),
		Style = "Heading",
		Weight = "ExtraBold",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 44, 0.5, 0),
		Size = UDim2.new(1, -44 - 52, 0, 26),
		Parent = header,
	})
	local close = Components.button("✕", {
		Name = "Close",
		Variant = "Ghost",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(44, 44),
		TextSize = Theme.TextSize.Heading,
		Parent = header,
	}, function()
		if props.onClose then
			props.onClose()
		end
	end)
	-- Center the ✕ exactly (no side padding on a square button)
	local closePadding = close:FindFirstChildOfClass("UIPadding")
	if closePadding then
		closePadding:Destroy()
	end
	Components.accentLine({
		Position = UDim2.fromOffset(Space.L, headerHeight),
		Size = UDim2.new(1, -Space.L * 2, 0, 2),
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
	}, { padding(Space.M, Space.L, Space.L, Space.L) })

	if props.Parent then
		frame.Parent = props.Parent
	end
	return frame, body, { panel = panel, header = header, title = title, icon = icon, close = close, scale = scale }
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
	isSelected: () -> boolean,
	isDisabled: () -> boolean,
}

local CARD_KEYS = { Accent = true, Icon = true, Title = true, Body = true, Badge = true, BadgeColor = true, onClick = true, Selected = true, Disabled = true }

-- A selectable card with hover, selected and disabled states.
-- props: Accent, onClick, Selected, Disabled, and optional standard content:
-- Icon (emoji), Title, Body (one or two lines), Badge (text) + BadgeColor.
-- Returns (frame, card) where card has setSelected/setDisabled/isSelected/isDisabled.
function Components.card(props: { [string]: any }?): (TextButton, Card)
	local given = props or {}
	local accent = given.Accent or Colors.Cyan
	local merged: { [string]: any } = {
		Name = "Card",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Selectable = true,
		SelectionImageObject = selectionImage,
		Size = UDim2.new(1, 0, 0, 76),
	}
	for key, value in given do
		if not CARD_KEYS[key] then
			merged[key] = value
		end
	end
	local outline = stroke(Colors.Stroke, 1.5, 0.78)
	local tint = make("Frame", {
		Name = "Tint",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, { corner(UDim.new(0, 10)) })
	local marker = make("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 3, 1, -24),
		BackgroundColor3 = accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, { corner(Theme.PillCorner) })
	local frame = make("TextButton", merged, {
		corner(UDim.new(0, 10)),
		outline,
		glassGradient(),
		tint,
		marker,
	})

	local iconTile: Frame? = nil
	if given.Icon or given.Title then
		local hasIcon = given.Icon ~= nil
		local textLeft = if hasIcon then 68 else Space.L
		if hasIcon then
			iconTile = Components.iconTile(given.Icon, 44, accent)
			local tile = iconTile :: Frame
			tile.AnchorPoint = Vector2.new(0.5, 0.5)
			tile.Position = UDim2.new(0, Space.M + 24, 0.5, 0)
			tile.ZIndex = 2
			tile.Parent = frame
		end
		local rightRoom = if given.Badge then 96 else Space.L
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
			Components.text({ Name = "Title", Text = given.Title, Style = "Label", LayoutOrder = 1, Parent = content })
		end
		if given.Body then
			local body = Components.text({ Name = "Body", Text = given.Body, Style = "Caption", Wrap = true, LayoutOrder = 2, Parent = content })
			-- At most two lines, so cards keep one height
			body.AutomaticSize = Enum.AutomaticSize.None
			body.Size = UDim2.new(1, 0, 0, 34)
			body.TextYAlignment = Enum.TextYAlignment.Top
			body.TextTruncate = Enum.TextTruncate.AtEnd
		end
		if given.Badge then
			local badge = Components.badge(given.Badge, given.BadgeColor or Colors.TextMuted)
			badge.AnchorPoint = Vector2.new(1, 0.5)
			badge.Position = UDim2.new(1, -Space.M, 0.5, 0)
			badge.ZIndex = 2
			badge.Parent = frame
		end
	end

	local wasDisabled = false
	local state, refresh = interactive(frame, function(current, instant)
		local info = if instant then nil else Motion.Fast
		if current.disabled ~= wasDisabled then
			wasDisabled = current.disabled
			dimTexts(frame, current.disabled)
		end
		local hovered = current.hovered and not current.disabled
		local tintAlpha = if current.selected then 0.82 elseif hovered then 0.92 else 1
		if current.pressed and not current.disabled then
			tintAlpha = 0.78
		end
		apply(tint, info, { BackgroundTransparency = tintAlpha })
		apply(marker, info, { BackgroundTransparency = if current.selected then 0 else 1 })
		apply(outline, info, {
			Color = if current.selected or hovered then accent else Colors.Stroke,
			Transparency = if current.selected then 0.05 elseif hovered then 0.35 else 0.78,
		})
		apply(frame, info, { BackgroundTransparency = if current.disabled then 0.6 else 0.25 })
		if iconTile then
			local scale = iconTile:FindFirstChildOfClass("UIScale") or make("UIScale", { Parent = iconTile })
			apply(scale, info, { Scale = if hovered and not current.pressed then 1.08 else 1 })
		end
	end)

	local card: Card
	card = {
		frame = frame,
		setSelected = function(selected: boolean)
			state.selected = selected
			refresh()
		end,
		setDisabled = function(disabled: boolean)
			state.disabled = disabled
			Components.setDisabled(frame, disabled)
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
	if given.Disabled then
		card.setDisabled(true)
	end
	return frame, card
end

-- Tabs ----------------------------------------------------------------------------------------

export type TabSpec = { id: string, label: string, icon: string? }
export type Tabs = { select: (id: string) -> (), current: () -> string?, frame: Frame }

-- A row of pill tabs. Selects the first tab right away (calling onSelect).
function Components.tabs(parent: Instance, tabs: { TabSpec }, onSelect: (id: string) -> ()): Tabs
	local row = make("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, Theme.Size.Control),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Components.list(row, Space.S, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
	local refreshers: { [string]: () -> () } = {}
	local current: string? = nil

	local function select(id: string)
		if not refreshers[id] then
			return
		end
		current = id
		for _, refresh in refreshers do
			refresh()
		end
		onSelect(id)
	end

	for order, spec in tabs do
		local text = if spec.icon then `{spec.icon}  {string.upper(spec.label)}` else string.upper(spec.label)
		local outline = stroke(Colors.Stroke, 1.5, 0.8)
		local button = make("TextButton", {
			Name = "Tab_" .. spec.id,
			LayoutOrder = order,
			AutoButtonColor = false,
			Selectable = true,
			SelectionImageObject = selectionImage,
			Size = UDim2.fromOffset(0, Theme.Size.Control),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Colors.PanelLight,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			Text = text,
			FontFace = Faces.Bold,
			TextSize = Theme.TextSize.Body,
			TextColor3 = Colors.TextDim,
			Parent = row,
		}, {
			corner(Theme.PillCorner),
			outline,
			padding(0, Space.L, 0, Space.L),
			make("UISizeConstraint", { MinSize = Vector2.new(96, Theme.Size.Control) }),
		})
		local _, refresh = interactive(button, function(state, instant)
			local info = if instant then nil else Motion.Fast
			local active = current == spec.id
			apply(button, info, {
				BackgroundColor3 = if active then Colors.Cyan elseif state.hovered then Colors.PanelHover else Colors.PanelLight,
				BackgroundTransparency = if active then 0.78 elseif state.hovered then 0.2 else 0.4,
				TextColor3 = if active or state.hovered then Colors.Text else Colors.TextDim,
			})
			apply(outline, info, {
				Color = if active then Colors.Cyan else Colors.Stroke,
				Transparency = if active then 0.1 elseif state.hovered then 0.45 else 0.8,
			})
		end)
		refreshers[spec.id] = refresh
		button.Activated:Connect(function()
			select(spec.id)
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

-- Prices ----------------------------------------------------------------------------------------

local function priceChip(parent: Instance, order: number, text: string, color: Color3, textSize: number)
	local chip = make("Frame", {
		Name = "PriceChip",
		LayoutOrder = order,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		corner(Theme.PillCorner),
		stroke(color, 1, 0.55),
		padding(0, Space.M, 0, Space.M),
	})
	Components.text({
		Text = text,
		Style = "Label",
		Weight = "ExtraBold",
		TextSize = textSize,
		Color = color,
		AlignX = "Center",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.None,
		Parent = chip,
	})
	return chip
end

-- Shows a price as chips: 💵 money, 💎 gems, R$ Robux (e.g. "R$ 6,666").
-- An empty price shows "FREE". props: Height (default 30), TextSize, and frame properties.
function Components.price(parent: Instance?, price: { money: number?, gems: number?, robux: number? }, props: { [string]: any }?): Frame
	local given = props or {}
	local height = given.Height or 30
	local textSize = given.TextSize or Theme.TextSize.Body
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
		priceChip(frame, 1, "💵 " .. formatNumber(price.money), Colors.Money, textSize)
	end
	if typeof(price.gems) == "number" and price.gems > 0 then
		any = true
		priceChip(frame, 2, "💎 " .. formatNumber(price.gems), Colors.Gems, textSize)
	end
	if typeof(price.robux) == "number" and price.robux > 0 then
		any = true
		priceChip(frame, 3, "R$ " .. formatNumber(price.robux), Colors.Robux, textSize)
	end
	if not any then
		priceChip(frame, 1, "FREE", Colors.Success, textSize)
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
	}, {
		corner(UDim.new(0, 6)),
		make("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(175, 180, 190)),
			Rotation = 90,
		}),
	})
	local frame = make("Frame", merged, { corner(UDim.new(0, 6)), fill })
	local current = 1
	local function set(fraction: number, color: Color3?)
		fraction = math.clamp(if fraction == fraction then fraction else 0, 0, 1)
		if math.abs(fraction - current) > 0.001 then
			current = fraction
			tween(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(fraction, 1) })
		end
		if color then
			fill.BackgroundColor3 = color
		end
	end
	return frame, set
end

-- A labelled bar: caption on the left, value on the right, bar underneath.
-- props: Label, Value, plus frame properties. Returns (frame, set(fraction, valueText?, color?)).
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
		Style = "Caption",
		Size = UDim2.new(0.6, 0, 0, 18),
		Parent = frame,
	})
	local valueText = Components.text({
		Name = "Value",
		Text = given.Value or "",
		Style = "Caption",
		Weight = "Bold",
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
		Size = UDim2.new(1, 0, 0, 10),
		Parent = frame,
	}, color or Colors.Cyan)
	stroke(Colors.Stroke, 1, 0.85).Parent = track
	set(0)
	return frame, function(fraction: number, text: string?, newColor: Color3?)
		set(fraction, newColor)
		if text then
			valueText.Text = text
		end
	end
end

-- Toggles and sliders -------------------------------------------------------------------------------

local function settingRow(height: number, props: { [string]: any }?): TextButton
	local merged: { [string]: any } = {
		Name = "Setting",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Selectable = true,
		SelectionImageObject = selectionImage,
	}
	for key, value in (props or {}) :: { [string]: any } do
		if key ~= "Description" and key ~= "Format" and key ~= "Live" then
			merged[key] = value
		end
	end
	return make("TextButton", merged, {
		corner(Theme.SmallCorner),
		stroke(Colors.Stroke, 1, 0.85),
	})
end

-- A labelled on/off switch row. The whole row is the hit target.
-- props: Description (a line under the label), plus row properties.
-- Returns (row, set(value)) — set() changes the look without calling onChange.
function Components.toggle(label: string, value: boolean, onChange: (boolean) -> (), props: { [string]: any }?): (TextButton, (boolean) -> ())
	local description = props and props.Description
	local row = settingRow(if description then 64 else Theme.Size.Control + 8, props)
	local textArea = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Space.L, 0.5, 0),
		Size = UDim2.new(1, -(Space.L + 112), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = row,
	})
	Components.list(textArea, 2)
	Components.text({ Text = label, Style = "Label", LayoutOrder = 1, Parent = textArea })
	if description then
		Components.text({ Text = description, Style = "Caption", LayoutOrder = 2, Parent = textArea })
	end
	local stateText = Components.text({
		Name = "State",
		Style = "Micro",
		AlignX = "Right",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(Space.L + 54), 0.5, 0),
		Size = UDim2.fromOffset(36, 16),
		Parent = row,
	})
	local track = make("Frame", {
		Name = "Switch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -Space.L, 0.5, 0),
		Size = UDim2.fromOffset(46, 26),
		BorderSizePixel = 0,
		Parent = row,
	}, { corner(Theme.PillCorner) })
	local trackStroke = stroke(Colors.Stroke, 1, 0.6)
	trackStroke.Parent = track
	local knob = make("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(20, 20),
		BorderSizePixel = 0,
		Parent = track,
	}, { corner(Theme.PillCorner) })

	local on = value == true
	local function render(instant: boolean?)
		local info = if instant then nil else Motion.Normal
		apply(track, info, { BackgroundColor3 = if on then Colors.Cyan else Colors.Raised })
		apply(trackStroke, info, { Transparency = if on then 1 else 0.6 })
		apply(knob, info, {
			Position = if on then UDim2.new(1, -23, 0.5, 0) else UDim2.new(0, 3, 0.5, 0),
			BackgroundColor3 = if on then Color3.new(1, 1, 1) else Colors.TextDim,
		})
		stateText.Text = if on then "ON" else "OFF"
		stateText.TextColor3 = if on then Colors.Cyan else Colors.TextMuted
	end
	render(true)
	interactive(row, function(state, instant)
		local info = if instant then nil else Motion.Fast
		apply(row, info, { BackgroundTransparency = if state.hovered then 0.2 else 0.45 })
	end)
	row.Activated:Connect(function()
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

-- A labelled slider with − and + buttons (for gamepad and touch) and a
-- draggable track. props: Description, Format (value -> text),
-- Live (default true; false = only call onChange when the drag ends).
-- Returns (frame, set(value)) — set() changes the look without calling onChange.
function Components.slider(label: string, min: number, max: number, step: number, value: number, onChange: (number) -> (), props: { [string]: any }?): (Frame, (number) -> ())
	local given = props or {}
	local format = given.Format or function(v: number)
		return string.format("%.2f", v)
	end
	local live = given.Live ~= false
	local merged: { [string]: any } = {
		Name = "Slider",
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}
	for key, prop in given do
		if key ~= "Description" and key ~= "Format" and key ~= "Live" then
			merged[key] = prop
		end
	end
	local frame = make("Frame", merged, {
		corner(Theme.SmallCorner),
		stroke(Colors.Stroke, 1, 0.85),
		padding(Space.S, Space.L, Space.S, Space.L),
	})
	Components.text({ Text = label, Style = "Label", Size = UDim2.new(1, -90, 0, 22), Parent = frame })
	local valueText = Components.text({
		Name = "Value",
		Style = "Label",
		Weight = "ExtraBold",
		Color = Colors.Cyan,
		AlignX = "Right",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(86, 22),
		Parent = frame,
	})
	local controls = make("Frame", {
		Name = "Controls",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, Theme.Size.Control),
		BackgroundTransparency = 1,
		Parent = frame,
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

	local minus = Components.button("−", {
		Name = "Minus",
		Variant = "Secondary",
		Size = UDim2.fromOffset(Theme.Size.Control, Theme.Size.Control),
		TextSize = Theme.TextSize.Heading,
		Parent = controls,
	}, function()
		setValue(current - step, true)
	end)
	local plus = Components.button("+", {
		Name = "Plus",
		Variant = "Secondary",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(Theme.Size.Control, Theme.Size.Control),
		TextSize = Theme.TextSize.Heading,
		Parent = controls,
	}, function()
		setValue(current + step, true)
	end)
	for _, button in { minus, plus } do
		local pad = button:FindFirstChildOfClass("UIPadding")
		if pad then
			pad:Destroy()
		end
	end

	-- The track: a wide invisible hit area with a thin bar in the middle
	local hit = make("TextButton", {
		Name = "Track",
		AutoButtonColor = false,
		Text = "",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(Theme.Size.Control + Space.M, 0),
		Size = UDim2.new(1, -(Theme.Size.Control + Space.M) * 2, 1, 0),
		Selectable = false,
		Parent = controls,
	})
	local bar = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Parent = hit,
	}, { corner(Theme.PillCorner), stroke(Colors.Stroke, 1, 0.8) })
	fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = Colors.Cyan,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	}, {
		corner(Theme.PillCorner),
		make("UIGradient", { Color = ColorSequence.new(Colors.CyanDeep, Colors.Cyan) }),
	})
	knob = make("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = bar,
	}, { corner(Theme.PillCorner), stroke(Colors.Cyan, 2, 0) })

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

	if given.Description then
		frame.Size = UDim2.new(frame.Size.X.Scale, frame.Size.X.Offset, 0, frame.Size.Y.Offset + 18)
		Components.text({
			Text = given.Description,
			Style = "Caption",
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, 0, 0, 18),
			Parent = frame,
		})
	end
	render()
	return frame, function(newValue: number)
		setValue(newValue, false)
	end
end

return Components
