-- The owner panel's "admin abuse" events. Shared so the server (which runs
-- each event) and every client (which draws it) agree on names and timing.
-- Events only push around players in the lobby; anyone in a running match is
-- left alone so fights stay fair (they still see the show).

local rgb = Color3.fromRGB

local AdminEvents = {}

AdminEvents.Order = {
	"MeteorShower",
	"BlackHole",
	"Thunderstorm",
	"IceAge",
	"Galaxy",
	"DiscoInferno",
	"LowGravity",
	"GiantParty",
	"PartyTime",
}

AdminEvents.Events = {
	MeteorShower = {
		name = "Meteor Shower",
		icon = "☄️",
		description = "Flaming meteors rain down and blast players around.",
		duration = 25,
		colors = { rgb(255, 120, 40), rgb(160, 30, 20) },
		-- Seconds between meteors, warning time before impact, blast size
		interval = 0.35,
		warning = 1.6,
		radius = 11,
		push = 75,
		lift = 55,
	},
	BlackHole = {
		name = "Black Hole",
		icon = "🕳️",
		description = "A black hole drags everyone in, then explodes.",
		duration = 14,
		colors = { rgb(140, 60, 255), rgb(20, 10, 40) },
		collapseAt = 10,
		pullRange = 95,
		pullSpeed = 45,
		blast = 130,
		blastLift = 90,
	},
	Thunderstorm = {
		name = "Thunderstorm",
		icon = "⚡",
		description = "Dark skies, pouring rain and lightning strikes.",
		duration = 25,
		colors = { rgb(120, 190, 255), rgb(30, 40, 80) },
		interval = 0.6,
		warning = 0.7,
		radius = 9,
		push = 60,
		lift = 70,
	},
	IceAge = {
		name = "Ice Age",
		icon = "🧊",
		description = "A blizzard rolls in and freezes everyone solid.",
		duration = 16,
		colors = { rgb(170, 230, 255), rgb(40, 90, 160) },
		-- { freeze at, thaw at } in seconds from the start
		freezes = { { 3, 7 }, { 10, 14 } },
	},
	Galaxy = {
		name = "Galaxy Sky",
		icon = "🌌",
		description = "Night falls, auroras dance and planets drift by.",
		duration = 35,
		colors = { rgb(90, 120, 255), rgb(200, 80, 255) },
	},
	DiscoInferno = {
		name = "Disco Inferno",
		icon = "🪩",
		description = "A giant disco ball, laser beams and a light-up floor.",
		duration = 30,
		colors = { rgb(255, 60, 200), rgb(60, 220, 255) },
	},
	LowGravity = {
		name = "Low Gravity",
		icon = "🚀",
		description = "Gravity drops to a quarter. Jump to the moon.",
		duration = 30,
		colors = { rgb(120, 255, 210), rgb(30, 60, 120) },
		-- Share of normal gravity players feel
		gravity = 0.25,
	},
	GiantParty = {
		name = "Giant Party",
		icon = "🦖",
		description = "Everyone grows to three times their size.",
		duration = 20,
		colors = { rgb(120, 230, 90), rgb(30, 110, 60) },
		scale = 3,
	},
	PartyTime = {
		name = "Party Time",
		icon = "🎉",
		description = "Fireworks, confetti and rainbow skies.",
		duration = 30,
		colors = { rgb(255, 210, 60), rgb(255, 80, 140) },
	},
}

-- Owner actions on a single player (or everyone)
AdminEvents.PlayerActions = {
	{ id = "Heal", label = "Heal", icon = "💚" },
	{ id = "KnockOut", label = "Knock Out", icon = "💀" },
	{ id = "Fling", label = "Fling", icon = "🌪️" },
	{ id = "Freeze", label = "Freeze", icon = "🧊" },
	{ id = "Bring", label = "Bring", icon = "🧲" },
	{ id = "GoTo", label = "Go To", icon = "🚪" },
	{ id = "Giant", label = "Giant", icon = "🦖" },
	{ id = "Tiny", label = "Tiny", icon = "🐜" },
	{ id = "NormalSize", label = "Normal Size", icon = "📏" },
	{ id = "Speed", label = "Speed Boost", icon = "⚡" },
	{ id = "AuraGold", label = "Gold Aura", icon = "✨" },
	{ id = "AuraRainbow", label = "Rainbow Aura", icon = "🌈" },
	{ id = "AuraVoid", label = "Void Aura", icon = "🌑" },
	{ id = "AuraFrost", label = "Frost Aura", icon = "❄️" },
	{ id = "AuraNone", label = "Remove Aura", icon = "🚫" },
	{ id = "Kick", label = "Kick", icon = "👢", danger = true },
	{ id = "Ban", label = "Ban (this server)", icon = "⛔", danger = true },
}

-- Timed player effects (seconds) and their strengths
AdminEvents.ActionSettings = {
	FreezeTime = 6,
	SizeTime = 30,
	GiantScale = 3,
	TinyScale = 0.4,
	SpeedTime = 20,
	SpeedMultiplier = 2.2,
	FlingSpeed = 140,
	FlingLift = 170,
}

AdminEvents.Auras = {
	Gold = { rgb(255, 215, 90), rgb(255, 160, 40) },
	Rainbow = { rgb(255, 80, 80), rgb(80, 160, 255) },
	Void = { rgb(120, 40, 220), rgb(10, 0, 20) },
	Frost = { rgb(190, 240, 255), rgb(80, 160, 255) },
}

AdminEvents.TimesOfDay = {
	{ id = "Auto", label = "🗓️ Season default", clockTime = nil :: number? },
	{ id = "Dawn", label = "🌅 Dawn", clockTime = 6.3 },
	{ id = "Day", label = "☀️ Day", clockTime = 13 },
	{ id = "Sunset", label = "🌇 Sunset", clockTime = 17.8 },
	{ id = "Night", label = "🌙 Night", clockTime = 0 },
}

return AdminEvents
