-- The look of every interface: colors, fonts and sizes in one place.
-- Dark sci-fi panels with cyan and purple neon accents.

local rgb = Color3.fromRGB

local Theme = {}

Theme.Colors = {
	Background = rgb(12, 14, 22),
	Panel = rgb(20, 23, 36),
	PanelLight = rgb(32, 36, 56),
	PanelHover = rgb(42, 47, 72),
	Cyan = rgb(70, 220, 255),
	Purple = rgb(170, 90, 255),
	Pink = rgb(255, 90, 190),
	Text = rgb(236, 240, 255),
	TextDim = rgb(150, 160, 192),
	Health = rgb(80, 230, 140),
	HealthLow = rgb(255, 80, 90),
	Guard = rgb(90, 170, 255),
	Gold = rgb(255, 205, 90),
	Danger = rgb(255, 75, 95),
	Success = rgb(90, 230, 150),
}

Theme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Heading = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
	Numbers = Enum.Font.GothamBlack,
}

Theme.Corner = UDim.new(0, 12)
Theme.SmallCorner = UDim.new(0, 8)

return Theme
