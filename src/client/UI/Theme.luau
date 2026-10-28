-- The look of every interface in one place, from docs/ArtDirection.md section 6
-- ("imperial codex meets precision instrument"): warm graphite panels with a
-- 1 px bronze hairline, square corners, ivory text, one bronze-gold accent,
-- Accanthis capitals for display type, Builder Sans for everything you read,
-- RobotoMono for timers and technical numbers, and an 8 px grid.
-- Sizes are design pixels at 1280x720; the Shell's single UIScale fits them to
-- the screen, so 14 here is 14 real pixels at 720p and never smaller.
--
-- Older code still reads the legacy names (Colors.Cyan, TextSize.Micro,
-- Fonts.Title, PillCorner...). They stay, mapped onto the new palette and type
-- scale, so every screen inherits the new look without being rewritten.

local rgb = Color3.fromRGB

local Theme = {}

local GRAPHITE = rgb(26, 24, 20)
local ACCENT = rgb(201, 164, 92)
local BRONZE = rgb(140, 106, 63)

Theme.Colors = {
	-- Surfaces, darkest to lightest (warm graphite, never pure black)
	Ink = rgb(15, 14, 11),
	Background = rgb(21, 20, 15),
	Panel = GRAPHITE,
	PanelLight = rgb(33, 31, 26),
	PanelHover = rgb(41, 38, 31),
	Raised = rgb(38, 35, 29),
	-- The 1 px bronze hairline every frame uses (at Glass.StrokeTransparency)
	Stroke = BRONZE,
	Bronze = BRONZE,
	BronzeLight = rgb(181, 139, 79),
	-- The single accent: selection, focus and the one primary action per screen
	Accent = ACCENT,
	AccentHover = rgb(214, 180, 112),
	AccentDeep = rgb(176, 142, 76),
	-- Rare gold leaf and the cool Meridian instrument light
	GoldLeaf = rgb(217, 178, 95),
	Meridian = rgb(221, 235, 255),
	Lapis = rgb(31, 43, 74),
	-- Text: primary, secondary, tertiary (the minimum for text, about 5:1 on a panel)
	Text = rgb(237, 230, 214),
	TextDim = rgb(185, 176, 160),
	TextMuted = rgb(142, 134, 118),
	-- Dark text on the bronze-gold primary button
	TextOnLight = rgb(23, 21, 16),
	-- Status
	Danger = rgb(192, 83, 63),
	DangerDeep = rgb(158, 67, 50),
	Success = rgb(111, 162, 135),
	Warning = rgb(208, 143, 71),
	Health = rgb(111, 162, 135),
	HealthLow = rgb(192, 83, 63),
	Guard = rgb(143, 163, 184),
	-- Currencies: drawn coin in bronze-gold, drawn gem in pale crystal, Robux in ivory
	Money = rgb(210, 178, 110),
	Gems = rgb(169, 195, 214),
	Robux = rgb(237, 230, 214),

	-- Legacy names (older screens): every old accent folds into the bronze family
	Cyan = ACCENT,
	CyanDeep = rgb(176, 142, 76),
	Purple = rgb(181, 139, 79),
	PurpleDeep = BRONZE,
	Pink = rgb(194, 122, 90),
	Gold = ACCENT,
	GoldDeep = rgb(176, 142, 76),
}

local SANS = "rbxasset://fonts/families/BuilderSans.json"
-- Accanthis ADF Std is the family behind Enum.Font.Bodoni
local DISPLAY = "rbxasset://fonts/families/AccanthisADFStd.json"
local MONO = "rbxasset://fonts/families/RobotoMono.json"

local function face(family: string, weight: Enum.FontWeight): Font
	return Font.new(family, weight, Enum.FontStyle.Normal)
end

-- Builder Sans in every weight the interface uses, plus the display and mono faces.
-- Nothing lighter than Regular: thin weights break up on dark panels.
Theme.Faces = {
	Heavy = face(SANS, Enum.FontWeight.Heavy),
	ExtraBold = face(SANS, Enum.FontWeight.ExtraBold),
	Bold = face(SANS, Enum.FontWeight.Bold),
	SemiBold = face(SANS, Enum.FontWeight.SemiBold),
	Medium = face(SANS, Enum.FontWeight.Medium),
	Regular = face(SANS, Enum.FontWeight.Regular),
	Display = face(DISPLAY, Enum.FontWeight.Regular),
	DisplayBold = face(DISPLAY, Enum.FontWeight.Bold),
	Mono = face(MONO, Enum.FontWeight.Medium),
	MonoBold = face(MONO, Enum.FontWeight.Bold),
}

-- Legacy Enum fonts (older code passes these to Components.label/button,
-- which swaps them for the matching face below)
Theme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Heading = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
	Numbers = Enum.Font.GothamBlack,
}

Theme.FaceForFont = {
	GothamBlack = Theme.Faces.Bold,
	GothamBold = Theme.Faces.SemiBold,
	GothamMedium = Theme.Faces.Medium,
	Gotham = Theme.Faces.Regular,
	Bodoni = Theme.Faces.Display,
	RobotoMono = Theme.Faces.Mono,
	Code = Theme.Faces.Mono,
}

-- The type scale (ArtDirection 6). Each role: face, size, line height, and
-- whether it is set in tracked capitals.
export type TypeRole = { face: Font, size: number, lineHeight: number, caps: boolean, color: string }

local ROLES: { [string]: TypeRole } = {
	-- Window titles, big headings
	display = { face = Theme.Faces.Display, size = 40, lineHeight = 1.1, caps = true, color = "Text" },
	-- Power codenames, dialog titles
	title = { face = Theme.Faces.Display, size = 28, lineHeight = 1.1, caps = false, color = "Text" },
	-- Section titles
	heading = { face = Theme.Faces.SemiBold, size = 20, lineHeight = 1.15, caps = false, color = "Text" },
	-- Descriptions (keep lines to 60-80 characters)
	body = { face = Theme.Faces.Regular, size = 17, lineHeight = 1.3, caps = false, color = "TextDim" },
	small = { face = Theme.Faces.Regular, size = 15, lineHeight = 1.25, caps = false, color = "TextDim" },
	-- The absolute minimum, never smaller
	caption = { face = Theme.Faces.Medium, size = 14, lineHeight = 1.2, caps = false, color = "TextMuted" },
	-- Small capitals above a section ("DOSSIER", "LOADOUT")
	overline = { face = Theme.Faces.SemiBold, size = 14, lineHeight = 1.1, caps = true, color = "TextMuted" },
	-- Button labels (capitals only when 12 characters or fewer)
	label = { face = Theme.Faces.Bold, size = 16, lineHeight = 1.1, caps = false, color = "Text" },
	-- Names in lists and rows
	strong = { face = Theme.Faces.SemiBold, size = 17, lineHeight = 1.2, caps = false, color = "Text" },
	-- Readouts (counts, prices)
	number = { face = Theme.Faces.Medium, size = 17, lineHeight = 1.1, caps = false, color = "Text" },
	-- Timers and technical values
	mono = { face = Theme.Faces.Mono, size = 15, lineHeight = 1.1, caps = false, color = "TextDim" },
	-- Results headline and the match countdown
	hero = { face = Theme.Faces.Display, size = 56, lineHeight = 1.05, caps = true, color = "Text" },
	countdown = { face = Theme.Faces.Display, size = 120, lineHeight = 1, caps = false, color = "Text" },
}
Theme.Roles = ROLES

-- Face, size and line height for a type role ("display", "title", "heading",
-- "body", "small", "caption", "overline", "label", "strong", "number", "mono",
-- "hero", "countdown"). Unknown roles fall back to body.
function Theme.type(role: string): TypeRole
	return ROLES[role] or ROLES.body
end

-- Roblox has no letter spacing, so short display titles in capitals get a hair
-- space (U+200A) between letters. Every tracked title goes through here so the
-- tracking is the same everywhere. Word gaps keep a normal space.
local HAIR = utf8.char(0x200A)
Theme.HairSpace = HAIR

function Theme.track(text: string): string
	local upper = string.upper(text)
	local out = table.create(#upper * 2)
	local previousLetter = false
	for _, code in utf8.codes(upper) do
		local char = utf8.char(code)
		local isSpace = char == " "
		if previousLetter and not isSpace then
			table.insert(out, HAIR)
		end
		table.insert(out, char)
		previousLetter = not isSpace
	end
	return table.concat(out)
end

-- Removes the tracking again (for comparing or measuring)
function Theme.untrack(text: string): string
	return (string.gsub(text, HAIR, ""))
end

-- Text sizes by legacy name. Every visible text is at least 14 px at 720p,
-- so the old 12 and 13 px steps now sit on the 14 px caption.
Theme.TextSize = {
	Micro = 14,
	Caption = 14,
	Small = 15,
	Body = 15,
	Label = 16,
	Reading = 17,
	Heading = 20,
	Title = 28,
	Display = 40,
	Hero = 56,
	Countdown = 120,
}

-- Legacy text styles for Components.text (Style = "Micro" ... "Display").
-- New code passes a role name instead (Style = "body", "overline", ...).
Theme.TextStyles = {
	Micro = { size = 14, face = "SemiBold", color = "TextMuted" },
	Caption = { size = 14, face = "Medium", color = "TextDim" },
	Body = { size = 15, face = "Regular", color = "Text" },
	Label = { size = 16, face = "SemiBold", color = "Text" },
	Heading = { size = 20, face = "SemiBold", color = "Text" },
	Title = { size = 28, face = "Display", color = "Text" },
	Display = { size = 40, face = "Display", color = "Text" },
}

-- Spacing: an 8 px grid. Panels pad 24, gutters are 16, sections 32 apart.
-- (M = 12 is kept only for older screens.)
Theme.Space = {
	XS = 4,
	S = 8,
	M = 12,
	L = 16,
	XL = 24,
	XXL = 32,
}
Theme.Grid = {
	Unit = 8,
	Pad = 24,
	Gutter = 16,
	Section = 32,
}

-- Square corners: 2 px at most. The old pill corner is square too (no bubbly
-- pills); Round is only for things that are truly circular (the hold ring).
Theme.Corner = UDim.new(0, 2)
Theme.SmallCorner = UDim.new(0, 2)
Theme.TinyCorner = UDim.new(0, 1)
Theme.PillCorner = UDim.new(0, 2)
Theme.Round = UDim.new(1, 0)

-- Control sizes (touch targets are never shorter than 44)
Theme.Size = {
	Control = 44,
	SmallControl = 36,
	IconTile = 32,
	Header = 80,
	DefaultWindow = Vector2.new(880, 560),
	-- The design resolution the UIScale is measured against
	Design = Vector2.new(1280, 720),
}

-- Global interface scale limits (multiplied by the player's "Interface size" setting)
Theme.Scale = {
	Min = 0.62,
	Max = 1.25,
}

-- Panel opacity (92-96%) and the hairline's transparency (bronze at about 45%)
Theme.Glass = {
	Window = 0.05,
	Panel = 0.06,
	Chip = 0.08,
	StrokeTransparency = 0.55,
}

-- Motion: 120-180 ms for small feedback, 240-320 ms for panels, quint-out,
-- 30 ms list stagger. Nothing bounces (Pop is kept as a name, not a bounce).
local function quint(seconds: number, direction: Enum.EasingDirection?): TweenInfo
	return TweenInfo.new(seconds, Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out)
end
Theme.Motion = {
	Press = quint(0.08),
	Fast = quint(0.12),
	Normal = quint(0.18),
	Slow = quint(0.28),
	Pop = quint(0.28),
	In = quint(0.16, Enum.EasingDirection.In),
	Stagger = 0.03,
}

-- The seven interaction states for a framed surface (plates, rows, tabs,
-- chips, buttons). Distinct without colour alone: a frame, a leading bar, an
-- outline, opacity and a lock all differ, not just a hue.
export type StateLook = {
	fill: Color3,
	fillAlpha: number,
	stroke: Color3,
	strokeAlpha: number,
	text: Color3,
	-- The 2 px bronze bar on the leading edge (selected)
	bar: boolean,
	-- Pressed shrinks to 0.98
	scale: number,
	-- The 2 px ivory outline outside the frame (gamepad focus)
	outline: boolean,
	-- Content opacity (disabled is 45%)
	opacity: number,
	lock: boolean,
}

local Colors = Theme.Colors
local STATES: { [string]: StateLook } = {
	default = { fill = Colors.PanelLight, fillAlpha = 0.04, stroke = Colors.Bronze, strokeAlpha = 0.62, text = Colors.TextDim, bar = false, scale = 1, outline = false, opacity = 1, lock = false },
	hover = { fill = Colors.PanelHover, fillAlpha = 0.02, stroke = Colors.BronzeLight, strokeAlpha = 0.25, text = Colors.Text, bar = false, scale = 1, outline = false, opacity = 1, lock = false },
	pressed = { fill = Colors.Raised, fillAlpha = 0.02, stroke = Colors.BronzeLight, strokeAlpha = 0.2, text = Colors.Text, bar = false, scale = 0.98, outline = false, opacity = 1, lock = false },
	selected = { fill = Colors.PanelHover, fillAlpha = 0.02, stroke = Colors.Accent, strokeAlpha = 0.05, text = Colors.Text, bar = true, scale = 1, outline = false, opacity = 1, lock = false },
	focused = { fill = Colors.PanelHover, fillAlpha = 0.02, stroke = Colors.BronzeLight, strokeAlpha = 0.25, text = Colors.Text, bar = false, scale = 1, outline = true, opacity = 1, lock = false },
	disabled = { fill = Colors.PanelLight, fillAlpha = 0.04, stroke = Colors.Bronze, strokeAlpha = 0.62, text = Colors.TextDim, bar = false, scale = 1, outline = false, opacity = 0.45, lock = false },
	locked = { fill = Colors.Background, fillAlpha = 0.04, stroke = Colors.Bronze, strokeAlpha = 0.7, text = Colors.TextMuted, bar = false, scale = 1, outline = false, opacity = 1, lock = true },
}
Theme.States = STATES

-- The look of one state: "default" | "hover" | "pressed" | "selected" |
-- "focused" | "disabled" | "locked". With a flags table (hovered, pressed,
-- selected, focused, disabled, locked), the strongest one wins.
function Theme.state(state: any): StateLook
	if typeof(state) == "string" then
		return STATES[state] or STATES.default
	end
	local flags = if typeof(state) == "table" then state else {}
	if flags.disabled then
		return STATES.disabled
	elseif flags.locked and not (flags.hovered or flags.selected) then
		return STATES.locked
	elseif flags.pressed then
		return STATES.pressed
	elseif flags.selected then
		return STATES.selected
	elseif flags.focused then
		return STATES.focused
	elseif flags.hovered then
		return STATES.hover
	end
	return STATES.default
end

-- Turns a content transparency into the one for a given opacity (45% disabled)
function Theme.fadeAlpha(transparency: number, opacity: number): number
	return 1 - (1 - transparency) * opacity
end

-- Button looks: fill, fill on hover, fill when pressed, text, and the hairline
Theme.Variants = {
	Primary = { fill = Colors.Accent, hover = Colors.AccentHover, press = Colors.AccentDeep, text = Colors.TextOnLight, stroke = rgb(228, 204, 150), strokeAlpha = 0.55, hoverStrokeAlpha = 0.2 },
	Secondary = { fill = Colors.PanelLight, hover = Colors.PanelHover, press = Colors.Raised, text = Colors.Text, stroke = Colors.Bronze, strokeAlpha = 0.5, hoverStrokeAlpha = 0.1 },
	Ghost = { fill = Colors.PanelLight, fillAlpha = 1, hoverAlpha = 0.3, hover = Colors.PanelHover, press = Colors.Raised, text = Colors.TextDim, hoverText = Colors.Text, stroke = Colors.Bronze, strokeAlpha = 1, hoverStrokeAlpha = 0.45 },
	Danger = { fill = rgb(122, 52, 39), hover = rgb(140, 60, 45), press = rgb(106, 45, 34), text = Colors.Text, stroke = Colors.Danger, strokeAlpha = 0.35, hoverStrokeAlpha = 0.05 },
	Gold = { fill = Colors.Accent, hover = Colors.AccentHover, press = Colors.AccentDeep, text = Colors.TextOnLight, stroke = rgb(228, 204, 150), strokeAlpha = 0.55, hoverStrokeAlpha = 0.2 },
}

-- Toast looks: the colour of the leading bar and the drawn icon's name
Theme.ToastKinds = {
	info = { color = Colors.TextDim, icon = "info" },
	success = { color = Colors.Success, icon = "check" },
	error = { color = Colors.Danger, icon = "warning" },
	reward = { color = Colors.Accent, icon = "star" },
}

return Theme
