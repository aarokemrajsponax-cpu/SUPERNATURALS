-- The look of every interface in one place: colors, fonts, text sizes,
-- spacing, corners and motion. Dark ink-navy glass with one electric cyan
-- accent, violet as the second accent, gold for currency and premium.
-- Every size here is in "design pixels" at 1280x720; the Shell's single
-- UIScale grows or shrinks the whole interface to fit the screen.

local rgb = Color3.fromRGB

local Theme = {}

Theme.Colors = {
	-- Surfaces, darkest to lightest (deep navy, never pure black)
	Ink = rgb(7, 9, 18),
	Background = rgb(11, 14, 26),
	Panel = rgb(17, 21, 38),
	PanelLight = rgb(27, 33, 56),
	PanelHover = rgb(38, 46, 76),
	Raised = rgb(31, 38, 64),
	-- Thin light outlines on glass
	Stroke = rgb(132, 150, 210),
	-- Accents
	Cyan = rgb(70, 220, 255),
	CyanDeep = rgb(24, 150, 214),
	Purple = rgb(160, 100, 255),
	PurpleDeep = rgb(104, 58, 210),
	Pink = rgb(255, 90, 190),
	-- Text (Text on Panel is about 15:1, TextDim about 7:1, TextMuted about 4.6:1)
	Text = rgb(238, 242, 255),
	TextDim = rgb(160, 171, 205),
	TextMuted = rgb(120, 131, 168),
	-- Dark text for light (cyan, gold) buttons
	TextOnLight = rgb(8, 14, 30),
	-- Status
	Health = rgb(80, 230, 140),
	HealthLow = rgb(255, 80, 90),
	Guard = rgb(90, 170, 255),
	Gold = rgb(255, 205, 90),
	GoldDeep = rgb(222, 150, 40),
	Danger = rgb(255, 75, 95),
	DangerDeep = rgb(196, 36, 66),
	Success = rgb(90, 230, 150),
	Warning = rgb(255, 176, 64),
	-- Currencies
	Money = rgb(150, 232, 110),
	Gems = rgb(90, 225, 255),
	Robux = rgb(0, 200, 120),
}

-- Legacy Enum fonts (older code passes these to Components.label/button,
-- which swaps them for the matching Builder Sans weight)
Theme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Heading = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
	Numbers = Enum.Font.GothamBlack,
}

local FAMILY = "rbxasset://fonts/families/BuilderSans.json"

local function face(weight: Enum.FontWeight): Font
	return Font.new(FAMILY, weight, Enum.FontStyle.Normal)
end

-- Builder Sans in every weight the interface uses
Theme.Faces = {
	Heavy = face(Enum.FontWeight.Heavy),
	ExtraBold = face(Enum.FontWeight.ExtraBold),
	Bold = face(Enum.FontWeight.Bold),
	SemiBold = face(Enum.FontWeight.SemiBold),
	Medium = face(Enum.FontWeight.Medium),
	Regular = face(Enum.FontWeight.Regular),
}

-- Which Builder Sans weight replaces each legacy font (by Enum.Font name)
Theme.FaceForFont = {
	GothamBlack = Theme.Faces.ExtraBold,
	GothamBold = Theme.Faces.Bold,
	GothamMedium = Theme.Faces.Medium,
	Gotham = Theme.Faces.Regular,
}

-- Fixed text sizes. Nothing uses TextScaled in new code: the global UIScale
-- does the scaling, so every screen keeps the same type hierarchy.
Theme.TextSize = {
	Micro = 12,
	Caption = 13,
	Body = 15,
	Label = 16,
	Heading = 20,
	Title = 26,
	Display = 40,
	-- Results headline and the match countdown
	Hero = 56,
	Countdown = 120,
}

-- A text style = size + weight + default color
Theme.TextStyles = {
	Micro = { size = 12, face = "Bold", color = "TextDim" },
	Caption = { size = 13, face = "Medium", color = "TextDim" },
	Body = { size = 15, face = "Regular", color = "Text" },
	Label = { size = 16, face = "Bold", color = "Text" },
	Heading = { size = 20, face = "Bold", color = "Text" },
	Title = { size = 26, face = "ExtraBold", color = "Text" },
	Display = { size = 40, face = "Heavy", color = "Text" },
}

-- Spacing scale (padding and gaps only ever use these)
Theme.Space = {
	XS = 4,
	S = 8,
	M = 12,
	L = 16,
	XL = 24,
}

-- Corners
Theme.Corner = UDim.new(0, 12)
Theme.SmallCorner = UDim.new(0, 8)
Theme.TinyCorner = UDim.new(0, 6)
Theme.PillCorner = UDim.new(1, 0)

-- Control sizes (touch targets are never shorter than 44)
Theme.Size = {
	Control = 44,
	SmallControl = 36,
	IconTile = 28,
	Header = 56,
	DefaultWindow = Vector2.new(860, 540),
	-- The design resolution the UIScale is measured against
	Design = Vector2.new(1280, 720),
}

-- Global interface scale limits (multiplied by the player's "Interface size" setting)
Theme.Scale = {
	Min = 0.62,
	Max = 1.25,
}

-- Transparency of glass surfaces
Theme.Glass = {
	Window = 0.06,
	Panel = 0.12,
	Chip = 0.18,
	StrokeTransparency = 0.72,
}

-- Motion: short and smooth; nothing bounces except celebrations
Theme.Motion = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Pop = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	In = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
}

-- Button looks: fill, fill on hover, text color, outline color and outline transparency
Theme.Variants = {
	Primary = { fill = Theme.Colors.Cyan, hover = rgb(140, 236, 255), press = Theme.Colors.CyanDeep, text = Theme.Colors.TextOnLight, stroke = rgb(200, 248, 255), strokeAlpha = 0.4 },
	Secondary = { fill = Theme.Colors.PanelLight, hover = Theme.Colors.PanelHover, press = Theme.Colors.Panel, text = Theme.Colors.Text, stroke = Theme.Colors.Cyan, strokeAlpha = 0.55 },
	Ghost = { fill = Theme.Colors.PanelLight, fillAlpha = 1, hoverAlpha = 0.4, hover = Theme.Colors.PanelHover, press = Theme.Colors.Panel, text = Theme.Colors.TextDim, hoverText = Theme.Colors.Text, stroke = Theme.Colors.Stroke, strokeAlpha = 1 },
	Danger = { fill = Theme.Colors.DangerDeep, hover = Theme.Colors.Danger, press = rgb(150, 26, 50), text = rgb(255, 255, 255), stroke = rgb(255, 150, 160), strokeAlpha = 0.5 },
	Gold = { fill = Theme.Colors.Gold, hover = rgb(255, 225, 140), press = Theme.Colors.GoldDeep, text = Theme.Colors.TextOnLight, stroke = rgb(255, 240, 200), strokeAlpha = 0.4 },
}

-- Toast looks
Theme.ToastKinds = {
	info = { color = Theme.Colors.Cyan, icon = "💬" },
	success = { color = Theme.Colors.Success, icon = "✅" },
	error = { color = Theme.Colors.Danger, icon = "⚠️" },
	reward = { color = Theme.Colors.Gold, icon = "🎁" },
}

return Theme
