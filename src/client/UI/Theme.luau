-- The look of every interface in one place, from docs/ArtDirection.md section 7
-- ("next-generation facility software", v3): deep navy glass panels with a 1 px
-- cool-grey hairline and 6 px corners, soft cool-white text, warm amber for the
-- one primary action, electric cyan for selection, focus and live information,
-- red only for danger. Type (owner request, 4 November 2026: bolder, a little bigger,
-- like polished game text): Builder Sans SemiBold/Bold for everything you read,
-- ExtraBold/Heavy for headings, RobotoMono Bold for numbers. Michroma is kept only for
-- very large hero titles (results headline, countdown). An 8 px grid.
-- Sizes are design pixels at 1280x720; the Shell's single UIScale fits them to
-- the screen, so 18 here is 18 real pixels at 720p. Floors: body 17 to 18, small labels
-- 15 to 16, buttons 17 to 19 bold, titles clearly larger.
--
-- Older code still reads the legacy names (Colors.Cyan, Colors.Gold, Colors.Bronze,
-- TextSize.Micro, Fonts.Title, PillCorner...). They stay, mapped onto the v3
-- palette and type scale, so every screen inherits the look without a rewrite.

local rgb = Color3.fromRGB

local Theme = {}

local NAVY = rgb(14, 22, 36)
local AMBER = rgb(232, 162, 74)
local CYAN = rgb(63, 214, 232)
local STEEL = rgb(138, 146, 156)
local STEEL_LIGHT = rgb(184, 192, 202)

Theme.Colors = {
	-- Surfaces, darkest to lightest (deep navy, never pure black)
	Ink = rgb(6, 10, 18),
	Background = rgb(10, 16, 27),
	Panel = NAVY,
	PanelLight = rgb(20, 30, 47),
	PanelHover = rgb(29, 42, 64),
	Raised = rgb(24, 36, 56),
	-- A selected plate: navy with a trace of cyan
	Selected = rgb(21, 48, 64),
	-- The 1 px hairline every frame uses (brushed steel, drawn at Glass.StrokeTransparency)
	Stroke = STEEL,
	Steel = STEEL,
	SteelLight = STEEL_LIGHT,
	-- Copper and bronze: warm metal accents for artwork, never for frames
	Copper = rgb(184, 115, 63),
	Bronze = STEEL,
	BronzeLight = STEEL_LIGHT,
	-- The one primary action (amber)
	Accent = AMBER,
	AccentHover = rgb(244, 182, 100),
	AccentDeep = rgb(196, 134, 52),
	-- Selection, focus and live information (cyan, used sparingly)
	Cyan = CYAN,
	CyanDeep = rgb(34, 154, 176),
	-- Text: primary, secondary, tertiary (contrast on a panel: about 14:1, 10:1, 7:1)
	Text = rgb(232, 238, 244),
	TextDim = rgb(196, 206, 220),
	TextMuted = rgb(158, 170, 188),
	-- Dark text on the amber primary button
	TextOnLight = rgb(14, 20, 30),
	-- Status
	Danger = rgb(229, 88, 76),
	DangerDeep = rgb(168, 56, 48),
	Success = rgb(95, 196, 138),
	Warning = rgb(240, 182, 82),
	Health = rgb(95, 196, 138),
	HealthLow = rgb(229, 88, 76),
	Guard = rgb(110, 172, 220),
	Stamina = rgb(232, 190, 104),
	-- Currencies: a coin in soft gold, a gem in pale crystal, Robux in white
	Money = rgb(222, 184, 100),
	Gems = rgb(150, 214, 238),
	Robux = rgb(232, 238, 244),
	-- Premium and ranking gold (a lighter yellow than the amber action colour)
	Gold = rgb(244, 200, 110),
	GoldDeep = rgb(200, 150, 60),

	-- Wayfinding colours (ArtDirection 2): thin marks and mode accents only
	Combat = rgb(224, 122, 58),
	Training = CYAN,
	Social = rgb(242, 230, 208),
	Personal = rgb(95, 196, 138),
	Special = rgb(142, 123, 224),
	Expansion = rgb(224, 106, 106),

	-- Legacy names (older screens)
	Purple = rgb(142, 123, 224),
	PurpleDeep = rgb(104, 88, 190),
	Pink = rgb(224, 106, 106),
}

local SANS = "rbxasset://fonts/families/BuilderSans.json"
-- Michroma has one weight (Regular); it is thin and wide, so it is for hero titles only
local DISPLAY = "rbxasset://fonts/families/Michroma.json"
local MONO = "rbxasset://fonts/families/RobotoMono.json"

local function face(family: string, weight: Enum.FontWeight): Font
	return Font.new(family, weight, Enum.FontStyle.Normal)
end

-- Builder Sans in every weight the interface uses, plus the hero and mono faces.
-- Nothing a player reads quickly is lighter than SemiBold: Regular and Medium are kept as
-- names (older code asks for them) but are drawn SemiBold, so thin text cannot come back.
local SEMIBOLD = face(SANS, Enum.FontWeight.SemiBold)
Theme.Faces = {
	Heavy = face(SANS, Enum.FontWeight.Heavy),
	ExtraBold = face(SANS, Enum.FontWeight.ExtraBold),
	Bold = face(SANS, Enum.FontWeight.Bold),
	SemiBold = SEMIBOLD,
	Medium = SEMIBOLD,
	Regular = SEMIBOLD,
	Display = face(DISPLAY, Enum.FontWeight.Regular),
	DisplayBold = face(DISPLAY, Enum.FontWeight.Regular),
	Mono = face(MONO, Enum.FontWeight.Bold),
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
	GothamBlack = Theme.Faces.ExtraBold,
	GothamBold = Theme.Faces.Bold,
	GothamMedium = Theme.Faces.SemiBold,
	Gotham = Theme.Faces.SemiBold,
	Michroma = Theme.Faces.ExtraBold,
	Bodoni = Theme.Faces.ExtraBold,
	RobotoMono = Theme.Faces.Mono,
	Code = Theme.Faces.Mono,
}

-- The type scale (ArtDirection 7). Each role: face, size, line height, whether
-- it is set in capitals, and the default colour name.
export type TypeRole = { face: Font, size: number, lineHeight: number, caps: boolean, color: string }

local ROLES: { [string]: TypeRole } = {
	-- Results headline (very large, so the wide Michroma still reads)
	hero = { face = Theme.Faces.Display, size = 48, lineHeight = 1.1, caps = true, color = "Text" },
	-- The match countdown (a single digit)
	countdown = { face = Theme.Faces.Display, size = 120, lineHeight = 1, caps = false, color = "Text" },
	-- Fighter names on a stage, big headings
	display = { face = Theme.Faces.Heavy, size = 34, lineHeight = 1.1, caps = true, color = "Text" },
	-- Window and dialog titles (short capitals)
	title = { face = Theme.Faces.ExtraBold, size = 26, lineHeight = 1.1, caps = true, color = "Text" },
	-- Section titles inside a screen
	heading = { face = Theme.Faces.ExtraBold, size = 24, lineHeight = 1.15, caps = false, color = "Text" },
	subheading = { face = Theme.Faces.Bold, size = 20, lineHeight = 1.2, caps = false, color = "Text" },
	-- Names in lists and rows
	strong = { face = Theme.Faces.Bold, size = 18, lineHeight = 1.2, caps = false, color = "Text" },
	-- Descriptions (keep lines to 60 to 80 characters)
	body = { face = Theme.Faces.SemiBold, size = 18, lineHeight = 1.35, caps = false, color = "TextDim" },
	small = { face = Theme.Faces.SemiBold, size = 16, lineHeight = 1.3, caps = false, color = "TextDim" },
	-- The absolute minimum for a small label, never smaller
	caption = { face = Theme.Faces.SemiBold, size = 15, lineHeight = 1.25, caps = false, color = "TextMuted" },
	label = { face = Theme.Faces.Bold, size = 16, lineHeight = 1.2, caps = false, color = "Text" },
	-- Small capitals above a section ("DOSSIER", "LOADOUT")
	overline = { face = Theme.Faces.Bold, size = 15, lineHeight = 1.1, caps = true, color = "TextMuted" },
	-- Button labels (capitals only when 12 characters or fewer)
	button = { face = Theme.Faces.Bold, size = 18, lineHeight = 1.1, caps = false, color = "Text" },
	-- Readouts (counts, prices, cooldowns)
	number = { face = Theme.Faces.MonoBold, size = 18, lineHeight = 1.1, caps = false, color = "Text" },
	-- Timers and technical values
	mono = { face = Theme.Faces.MonoBold, size = 16, lineHeight = 1.1, caps = false, color = "TextDim" },
}
Theme.Roles = ROLES

-- Face, size and line height for a type role ("display", "title", "heading",
-- "body", "small", "caption", "label", "overline", "button", "strong", "number",
-- "mono", "hero", "countdown"). Unknown roles fall back to body.
function Theme.type(role: string): TypeRole
	return ROLES[role] or ROLES.body
end

-- Roblox has no letter spacing, so the very large Michroma hero titles in capitals get a
-- hair space (U+200A) between letters. Bold Builder Sans titles are NOT tracked (use
-- Theme.caps). Word gaps keep a normal space.
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

-- Capitals without tracking: for short titles in bold Builder Sans
function Theme.caps(text: string): string
	return string.upper(text)
end

-- Removes the tracking again (for comparing or measuring)
function Theme.untrack(text: string): string
	return (string.gsub(text, HAIR, ""))
end

-- Text sizes by legacy name. Small labels are at least 15 px, body 18 px at 720p.
Theme.TextSize = {
	Micro = 15,
	Caption = 15,
	Small = 16,
	Button = 18,
	Body = 18,
	Label = 16,
	Reading = 18,
	Heading = 24,
	Title = 28,
	Display = 34,
	Hero = 48,
	Countdown = 120,
}

-- Legacy text styles for Components.text (Style = "Micro" ... "Display").
-- New code passes a role name instead (Style = "body", "overline", ...).
Theme.TextStyles = {
	Micro = { size = 15, face = "Bold", color = "TextMuted" },
	Caption = { size = 15, face = "SemiBold", color = "TextDim" },
	Body = { size = 18, face = "SemiBold", color = "Text" },
	Label = { size = 17, face = "Bold", color = "Text" },
	Heading = { size = 24, face = "ExtraBold", color = "Text" },
	Title = { size = 28, face = "ExtraBold", color = "Text" },
	Display = { size = 34, face = "Heavy", color = "Text" },
}

-- Text over the 3D world: a dark outline always, plus a dark copy offset 1 to 2 px for the
-- important lines (Components.dropShadow reads these)
Theme.TextShadow = {
	Offset = 2,
	Transparency = 0.45,
	StrokeThickness = 1.5,
	StrokeTransparency = 0.3,
}

-- Soft two-stop gradients for selection screens (Components.gradient, owner request 4 Nov
-- 2026). How much of the card's own colours is mixed into the dark panel in each state;
-- 1 would be the pure colour. Panels behind reading text stay solid.
Theme.Gradient = {
	Rest = 0.16,
	Hover = 0.24,
	Selected = 0.32,
	Locked = 0.08,
	Rotation = 25,
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

-- Corners: 4 px on windows and panels, 3 px on controls, 2 px on small marks (badges,
-- bars, key caps): tight, machined corners rather than soft bubbles (craft pass, 3 Nov).
-- Round is only for things that are truly circular (rings, dots).
Theme.Corner = UDim.new(0, 4)
Theme.SmallCorner = UDim.new(0, 3)
Theme.TinyCorner = UDim.new(0, 2)
Theme.PillCorner = UDim.new(0, 3)
Theme.Round = UDim.new(1, 0)

-- Control sizes (touch targets are never shorter than 44)
Theme.Size = {
	Control = 44,
	SmallControl = 36,
	IconTile = 32,
	Header = 64,
	DefaultWindow = Vector2.new(880, 560),
	-- The design resolution the UIScale is measured against
	Design = Vector2.new(1280, 720),
}

-- Global interface scale limits (multiplied by the player's "Interface size" setting)
Theme.Scale = {
	Min = 0.62,
	Max = 1.25,
	-- Phones (compact viewports) never scale below this, so 18 px text stays about 14 px
	-- on screen and a 667x375 phone gets an 834x469 design canvas
	CompactMin = 0.8,
}

-- Panel opacity and the hairline's transparency (steel at about 30%). Windows are solid:
-- nothing shows through a surface that holds text (docs/specs/UI_Craft_Pass.md).
Theme.Glass = {
	Window = 0,
	Panel = 0.03,
	Chip = 0.06,
	StrokeTransparency = 0.7,
}

-- Motion: 0.15 to 0.3 s, quint-out. Nothing bounces (Pop is a name, not a bounce).
local function quint(seconds: number, direction: Enum.EasingDirection?): TweenInfo
	return TweenInfo.new(seconds, Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out)
end
Theme.Motion = {
	Press = quint(0.1),
	Fast = quint(0.15),
	Normal = quint(0.22),
	Slow = quint(0.3),
	Pop = quint(0.3),
	In = quint(0.15, Enum.EasingDirection.In),
	Stagger = 0.03,
}

-- The seven interaction states for a framed surface (plates, rows, tabs,
-- chips, buttons). Distinct without colour alone: a leading bar, an outline,
-- opacity and a lock all differ, not just a hue.
export type StateLook = {
	fill: Color3,
	fillAlpha: number,
	stroke: Color3,
	strokeAlpha: number,
	text: Color3,
	-- The 2 px cyan bar on the leading edge (selected)
	bar: boolean,
	-- Pressed shrinks to 0.98
	scale: number,
	-- The 2 px cyan outline outside the frame (gamepad and keyboard focus)
	outline: boolean,
	-- Content opacity (disabled is 45%)
	opacity: number,
	lock: boolean,
}

local Colors = Theme.Colors
local STATES: { [string]: StateLook } = {
	default = { fill = Colors.PanelLight, fillAlpha = 0.08, stroke = Colors.Stroke, strokeAlpha = 0.72, text = Colors.TextDim, bar = false, scale = 1, outline = false, opacity = 1, lock = false },
	hover = { fill = Colors.PanelHover, fillAlpha = 0.04, stroke = Colors.SteelLight, strokeAlpha = 0.5, text = Colors.Text, bar = false, scale = 1, outline = false, opacity = 1, lock = false },
	pressed = { fill = Colors.Raised, fillAlpha = 0, stroke = Colors.SteelLight, strokeAlpha = 0.4, text = Colors.Text, bar = false, scale = 0.98, outline = false, opacity = 1, lock = false },
	selected = { fill = Colors.Selected, fillAlpha = 0.02, stroke = Colors.Cyan, strokeAlpha = 0.35, text = Colors.Text, bar = true, scale = 1, outline = false, opacity = 1, lock = false },
	focused = { fill = Colors.PanelHover, fillAlpha = 0.04, stroke = Colors.Cyan, strokeAlpha = 0.3, text = Colors.Text, bar = false, scale = 1, outline = true, opacity = 1, lock = false },
	disabled = { fill = Colors.PanelLight, fillAlpha = 0.08, stroke = Colors.Stroke, strokeAlpha = 0.72, text = Colors.TextDim, bar = false, scale = 1, outline = false, opacity = 0.45, lock = false },
	locked = { fill = Colors.Background, fillAlpha = 0.1, stroke = Colors.Stroke, strokeAlpha = 0.8, text = Colors.TextMuted, bar = false, scale = 1, outline = false, opacity = 1, lock = true },
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
	Primary = { fill = Colors.Accent, hover = Colors.AccentHover, press = Colors.AccentDeep, text = Colors.TextOnLight, stroke = Colors.AccentHover, strokeAlpha = 0.6, hoverStrokeAlpha = 0.3 },
	Secondary = { fill = Colors.PanelLight, hover = Colors.PanelHover, press = Colors.Raised, text = Colors.Text, stroke = Colors.Stroke, strokeAlpha = 0.55, hoverStrokeAlpha = 0.3 },
	Ghost = { fill = Colors.PanelLight, fillAlpha = 1, hoverAlpha = 0.4, hover = Colors.PanelHover, press = Colors.Raised, text = Colors.TextDim, hoverText = Colors.Text, stroke = Colors.Stroke, strokeAlpha = 1, hoverStrokeAlpha = 0.55 },
	Danger = { fill = rgb(112, 38, 36), hover = rgb(136, 46, 42), press = rgb(94, 30, 29), text = Colors.Text, stroke = Colors.Danger, strokeAlpha = 0.45, hoverStrokeAlpha = 0.15 },
	-- Older screens ask for Gold: it is the same one primary action
	Gold = { fill = Colors.Accent, hover = Colors.AccentHover, press = Colors.AccentDeep, text = Colors.TextOnLight, stroke = Colors.AccentHover, strokeAlpha = 0.6, hoverStrokeAlpha = 0.3 },
}

-- Toast looks: the colour of the leading bar and the drawn icon's name
Theme.ToastKinds = {
	info = { color = Colors.Cyan, icon = "info" },
	success = { color = Colors.Success, icon = "check" },
	error = { color = Colors.Danger, icon = "warning" },
	reward = { color = Colors.Accent, icon = "star" },
}

return Theme
