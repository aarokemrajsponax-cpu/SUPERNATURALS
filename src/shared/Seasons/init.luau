-- Seasonal Sync: works out which holiday it is and holds each holiday's look.
-- The server picks the season and shares it through a ReplicatedStorage attribute,
-- so any script can ask Seasons.getActiveId() or listen for changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Calendar = require(script.Calendar)
local Config = require(script.Parent.Config)

local Seasons = {}

Seasons.Calendar = Calendar
Seasons.ATTRIBUTE = "Season"
Seasons.NONE = "None"

-- CollectionService tags the client animates on seasonal decorations
Seasons.Tags = {
	Flicker = "SeasonalFlicker", -- PointLights that flicker like candles
	Twinkle = "SeasonalTwinkle", -- Neon parts that twinkle like fairy lights
	Bob = "SeasonalBob", -- Models that float up and down
	Spin = "SeasonalSpin", -- Models that slowly turn
}

local rgb = Color3.fromRGB

Seasons.Themes = {
	Halloween = {
		name = "Halloween",
		icon = "🎃",
		greeting = "Happy Halloween!",
		subtitle = "Something spooky is in the air...",
		palette = { primary = rgb(255, 120, 20), secondary = rgb(110, 40, 170), accent = rgb(255, 220, 90) },
		lighting = {
			ClockTime = 18.9,
			Brightness = 1.6,
			Ambient = rgb(70, 40, 90),
			OutdoorAmbient = rgb(100, 70, 125),
			ColorShift_Top = rgb(255, 140, 60),
			ColorShift_Bottom = rgb(80, 30, 120),
		},
		atmosphere = {
			Density = 0.42,
			Offset = 0.25,
			Color = rgb(190, 120, 200),
			Decay = rgb(100, 50, 140),
			Glare = 0.4,
			Haze = 2,
		},
		colorCorrection = { TintColor = rgb(255, 235, 245), Saturation = 0.15, Contrast = 0.15, Brightness = 0 },
		bloom = { Intensity = 1, Size = 30, Threshold = 1.2 },
		sunRays = { Intensity = 0.12, Spread = 0.6 },
		weather = { color = rgb(255, 150, 50), color2 = rgb(170, 80, 255), rate = 25, size = 0.25, speed = 2, rise = true, lightEmission = 1 },
		sprites = { glyphs = { "🦇", "🦇", "👻" }, count = 14, fall = 0, drift = 6, sway = 3, size = 2.2 },
	},

	Thanksgiving = {
		name = "Thanksgiving",
		icon = "🦃",
		greeting = "Happy Thanksgiving!",
		subtitle = "Grab a seat at the harvest table",
		palette = { primary = rgb(205, 95, 30), secondary = rgb(130, 65, 30), accent = rgb(245, 195, 85) },
		lighting = {
			ClockTime = 16.8,
			Brightness = 2.5,
			Ambient = rgb(95, 75, 55),
			OutdoorAmbient = rgb(150, 120, 90),
			ColorShift_Top = rgb(255, 190, 120),
			ColorShift_Bottom = rgb(120, 70, 40),
		},
		atmosphere = {
			Density = 0.3,
			Offset = 0.2,
			Color = rgb(230, 190, 150),
			Decay = rgb(180, 110, 70),
			Glare = 0.5,
			Haze = 1.5,
		},
		colorCorrection = { TintColor = rgb(255, 240, 225), Saturation = 0.2, Contrast = 0.1, Brightness = 0 },
		bloom = { Intensity = 0.6, Size = 24, Threshold = 1.6 },
		sunRays = { Intensity = 0.15, Spread = 0.8 },
		weather = { color = rgb(255, 215, 150), rate = 15, size = 0.15, speed = 0.6, rise = true, lightEmission = 0.6 },
		sprites = { glyphs = { "🍂", "🍁", "🍁" }, count = 30, fall = 3, drift = 1.5, sway = 2, size = 1.6, spin = true },
	},

	Christmas = {
		name = "Christmas",
		icon = "🎄",
		greeting = "Merry Christmas!",
		subtitle = "Let it snow, let it snow, let it snow",
		palette = { primary = rgb(200, 30, 45), secondary = rgb(20, 110, 60), accent = rgb(255, 215, 120) },
		lighting = {
			ClockTime = 15.5,
			Brightness = 2.2,
			Ambient = rgb(100, 110, 130),
			OutdoorAmbient = rgb(150, 165, 190),
			ColorShift_Top = rgb(220, 235, 255),
			ColorShift_Bottom = rgb(90, 110, 150),
		},
		atmosphere = {
			Density = 0.4,
			Offset = 0.15,
			Color = rgb(210, 225, 245),
			Decay = rgb(150, 170, 200),
			Glare = 0.2,
			Haze = 2.5,
		},
		colorCorrection = { TintColor = rgb(235, 245, 255), Saturation = 0.05, Contrast = 0.1, Brightness = 0 },
		bloom = { Intensity = 0.8, Size = 28, Threshold = 1.3 },
		weather = { color = rgb(255, 255, 255), rate = 220, size = 0.3, speed = 7, lifetime = 7, lightEmission = 0.2 },
		sprites = { glyphs = { "❄️" }, count = 14, fall = 2.5, drift = 0.5, sway = 1, size = 1.3, spin = true },
	},

	NewYears = {
		name = "New Year's",
		icon = "🎆",
		greeting = "Happy New Year!",
		subtitle = "Look up for the fireworks!",
		palette = { primary = rgb(220, 180, 70), secondary = rgb(25, 25, 45), accent = rgb(240, 240, 255) },
		lighting = {
			ClockTime = 23.8,
			Brightness = 1,
			Ambient = rgb(60, 60, 90),
			OutdoorAmbient = rgb(90, 90, 130),
			ColorShift_Top = rgb(200, 200, 255),
			ColorShift_Bottom = rgb(40, 40, 80),
		},
		atmosphere = {
			Density = 0.3,
			Offset = 0.1,
			Color = rgb(120, 120, 170),
			Decay = rgb(60, 60, 110),
			Glare = 0,
			Haze = 1,
		},
		colorCorrection = { TintColor = rgb(245, 240, 255), Saturation = 0.2, Contrast = 0.2, Brightness = 0 },
		bloom = { Intensity = 1.2, Size = 40, Threshold = 1 },
		weather = { color = rgb(255, 215, 110), color2 = rgb(255, 255, 255), rate = 50, size = 0.18, speed = 3, lightEmission = 1 },
		sprites = { glyphs = { "✨", "🎊" }, count = 10, fall = 1.5, drift = 0.5, sway = 1.5, size = 1.5, spin = true },
		fireworks = true,
	},

	Valentines = {
		name = "Valentine's Day",
		icon = "💖",
		greeting = "Happy Valentine's Day!",
		subtitle = "Love is in the air",
		palette = { primary = rgb(235, 60, 110), secondary = rgb(255, 150, 190), accent = rgb(255, 240, 245) },
		lighting = {
			ClockTime = 17.3,
			Brightness = 2.2,
			Ambient = rgb(110, 70, 90),
			OutdoorAmbient = rgb(170, 120, 150),
			ColorShift_Top = rgb(255, 170, 200),
			ColorShift_Bottom = rgb(140, 60, 100),
		},
		atmosphere = {
			Density = 0.35,
			Offset = 0.2,
			Color = rgb(255, 190, 215),
			Decay = rgb(220, 120, 170),
			Glare = 0.4,
			Haze = 1.8,
		},
		colorCorrection = { TintColor = rgb(255, 235, 242), Saturation = 0.15, Contrast = 0.08, Brightness = 0 },
		bloom = { Intensity = 0.8, Size = 30, Threshold = 1.3 },
		sunRays = { Intensity = 0.1, Spread = 0.7 },
		weather = { color = rgb(255, 150, 200), color2 = rgb(255, 255, 255), rate = 40, size = 0.2, speed = 2, lightEmission = 0.8 },
		sprites = { glyphs = { "💖", "💕", "❤️", "💗" }, count = 24, fall = -1.5, drift = 0.5, sway = 1.5, size = 1.6 },
	},

	StPatricks = {
		name = "St. Patrick's Day",
		icon = "🍀",
		greeting = "Happy St. Patrick's Day!",
		subtitle = "Find the gold at the end of the rainbow",
		palette = { primary = rgb(30, 160, 70), secondary = rgb(15, 90, 45), accent = rgb(245, 200, 60) },
		lighting = {
			ClockTime = 13,
			Brightness = 3,
			Ambient = rgb(90, 110, 90),
			OutdoorAmbient = rgb(140, 170, 140),
			ColorShift_Top = rgb(240, 255, 220),
			ColorShift_Bottom = rgb(60, 110, 60),
		},
		atmosphere = {
			Density = 0.25,
			Offset = 0.1,
			Color = rgb(210, 240, 210),
			Decay = rgb(150, 200, 150),
			Glare = 0.2,
			Haze = 1,
		},
		colorCorrection = { TintColor = rgb(240, 255, 240), Saturation = 0.25, Contrast = 0.1, Brightness = 0 },
		bloom = { Intensity = 0.6, Size = 24, Threshold = 1.5 },
		sunRays = { Intensity = 0.1, Spread = 0.6 },
		weather = { color = rgb(120, 255, 140), color2 = rgb(255, 215, 80), rate = 35, size = 0.2, speed = 2, lightEmission = 1 },
		sprites = { glyphs = { "🍀", "☘️" }, count = 22, fall = 2, drift = 1, sway = 1.5, size = 1.5, spin = true },
	},

	Easter = {
		name = "Easter",
		icon = "🐰",
		greeting = "Happy Easter!",
		subtitle = "How many hidden eggs can you find?",
		palette = { primary = rgb(175, 145, 240), secondary = rgb(255, 180, 215), accent = rgb(190, 240, 210) },
		lighting = {
			ClockTime = 10,
			Brightness = 2.8,
			Ambient = rgb(110, 105, 120),
			OutdoorAmbient = rgb(170, 165, 185),
			ColorShift_Top = rgb(255, 245, 230),
			ColorShift_Bottom = rgb(150, 130, 170),
		},
		atmosphere = {
			Density = 0.25,
			Offset = 0.1,
			Color = rgb(230, 225, 245),
			Decay = rgb(200, 190, 230),
			Glare = 0.3,
			Haze = 1.2,
		},
		colorCorrection = { TintColor = rgb(255, 250, 255), Saturation = 0.2, Contrast = 0.05, Brightness = 0.02 },
		bloom = { Intensity = 0.6, Size = 24, Threshold = 1.5 },
		sunRays = { Intensity = 0.12, Spread = 0.7 },
		weather = { color = rgb(255, 245, 250), color2 = rgb(255, 200, 230), rate = 20, size = 0.15, speed = 1, rise = true, lightEmission = 0.5 },
		sprites = { glyphs = { "🌸", "🌼", "🌷" }, count = 22, fall = 1.8, drift = 1, sway = 1.8, size = 1.4, spin = true },
	},
}

-- The season the calendar says it is right now (UTC), or Config.ForceSeason when set
function Seasons.getCurrentId(): string?
	local forced = Config.ForceSeason
	if forced then
		if Seasons.Themes[forced] then
			return forced
		end
		warn(`[Seasons] Config.ForceSeason "{forced}" isn't a season. Using the real date instead.`)
	end
	local now = DateTime.now():ToUniversalTime()
	return Calendar.seasonFor(now.Year, now.Month, now.Day)
end

-- The season the server has switched on (use this from any script)
function Seasons.getActiveId(): string?
	local id = ReplicatedStorage:GetAttribute(Seasons.ATTRIBUTE)
	if id == nil or id == Seasons.NONE then
		return nil
	end
	return id
end

function Seasons.getTheme(id: string?)
	return if id then Seasons.Themes[id] else nil
end

-- Calls callback(id, theme) now and every time the season changes
function Seasons.observe(callback: (string?, any) -> ())
	local function fire()
		local id = Seasons.getActiveId()
		callback(id, Seasons.getTheme(id))
	end
	local connection = ReplicatedStorage:GetAttributeChangedSignal(Seasons.ATTRIBUTE):Connect(fire)
	fire()
	return connection
end

return Seasons
