-- Drawn line icons for the whole interface (ArtDirection 6: 2 px strokes,
-- square caps, centred in their box, no emoji anywhere). Each icon is drawn on
-- a 24-unit grid from plain GuiObjects: bars (rotated Frames), rings and boxes
-- (Frames with a UIStroke), and discs. They stay crisp from 16 to 64 px and take
-- one colour, so they tint with their context.
--   Icons.make(name, size, color?) -> Frame      Icons.has(name) -> boolean
--   Icons.resolve(nameOrEmoji) -> name           Icons.tint(icon, color, alpha?)
--   Icons.sigil(powerId) -> name                 Icons.forAbility(ability) -> name
-- Unknown names (and any emoji older code passes) draw the facet lozenge, so
-- no screen ever shows an emoji or a missing glyph.

local Icons = {}

local UNITS = 24
-- Painted pieces carry this name so tint() finds them
local INK = "Ink"

-- An op is { kind, ...numbers } in grid units (path centrelines):
--   "l"  x1 y1 x2 y2            a line with square caps
--   "p"  x1 y1 x2 y2 ...        an open polyline (square caps at both ends)
--   "q"  x1 y1 x2 y2 ...        a closed polyline
--   "r"  x y w h [rotation]     an outlined box
--   "f"  x y w h [rotation]     a filled box
--   "c"  cx cy r                a ring
--   "d"  cx cy r                a filled disc
--   "a"  cx cy r from to        an arc in degrees (0 = right, 90 = down)
--   "h"  x y angle [length]     an arrowhead whose tip is at x, y pointing at angle
type Op = { any }

local function arrow(x: number, y: number, angle: number, length: number?): Op
	return { "h", x, y, angle, length or 4.5 }
end

local DEFS: { [string]: { Op } } = {
	-- Actions and navigation
	play = { { "q", 8, 5, 19, 12, 8, 19 } },
	fight = {
		{ "r", 5, 8, 14, 9 },
		{ "l", 9.5, 8, 9.5, 12 },
		{ "l", 14, 8, 14, 12 },
		{ "p", 5, 13.5, 11, 13.5, 11, 17 },
		{ "l", 8, 17, 8, 21 },
		{ "l", 16, 17, 16, 21 },
	},
	swords = {
		{ "l", 5, 5, 18, 18 },
		{ "l", 19, 5, 6, 18 },
		{ "l", 14, 18.5, 18.5, 14 },
		{ "l", 5.5, 14, 10, 18.5 },
		{ "f", 18, 18, 3, 3 },
		{ "f", 3, 18, 3, 3 },
	},
	shield = { { "q", 5, 4.5, 19, 4.5, 19, 12, 12, 20, 5, 12 } },
	target = { { "c", 12, 12, 8.5 }, { "c", 12, 12, 4 }, { "d", 12, 12, 1.4 } },
	ghost = {
		{ "a", 12, 10, 7, 180, 360 },
		{ "l", 5, 10, 5, 19.5 },
		{ "l", 19, 10, 19, 19.5 },
		{ "p", 5, 19.5, 8.5, 16.5, 12, 19.5, 15.5, 16.5, 19, 19.5 },
		{ "d", 9.5, 11, 1.3 },
		{ "d", 14.5, 11, 1.3 },
	},
	paw = {
		{ "d", 12, 15.5, 4.2 },
		{ "d", 6, 10.5, 2.1 },
		{ "d", 9.8, 6.5, 2.1 },
		{ "d", 14.2, 6.5, 2.1 },
		{ "d", 18, 10.5, 2.1 },
	},
	gear = {
		{ "c", 12, 12, 5.5 },
		{ "c", 12, 12, 1.8 },
		{ "f", 10.5, 2.5, 3, 3.5 },
		{ "f", 10.5, 18, 3, 3.5 },
		{ "f", 2.5, 10.5, 3.5, 3 },
		{ "f", 18, 10.5, 3.5, 3 },
		{ "f", 4.6, 4.6, 3.5, 3, 45 },
		{ "f", 15.9, 15.9, 3.5, 3, 45 },
		{ "f", 15.9, 4.6, 3.5, 3, -45 },
		{ "f", 4.6, 15.9, 3.5, 3, -45 },
	},
	cog = {
		{ "c", 12, 12, 6 },
		{ "d", 12, 12, 2 },
		{ "f", 10.5, 2.5, 3, 3.5 },
		{ "f", 10.5, 18, 3, 3.5 },
		{ "f", 3.6, 6.5, 3.5, 3, 30 },
		{ "f", 16.9, 14.5, 3.5, 3, 30 },
		{ "f", 16.9, 6.5, 3.5, 3, -30 },
		{ "f", 3.6, 14.5, 3.5, 3, -30 },
	},
	bolt = { { "q", 13.5, 3, 6, 13.5, 11.5, 13.5, 10, 21, 18, 10, 12.5, 10 } },
	fire = {
		{ "q", 12, 3, 16, 8, 18, 12.5, 17.5, 16.5, 14.5, 20, 9.5, 20, 6.5, 16.5, 6, 12.5, 8.5, 9.5, 10, 12 },
		{ "q", 12, 12, 14.5, 15.5, 12, 18.5, 9.5, 15.5 },
	},
	code = {
		{ "p", 8, 7, 3.5, 12, 8, 17 },
		{ "p", 16, 7, 20.5, 12, 16, 17 },
		{ "l", 14, 5, 10, 19 },
	},
	crown = { { "q", 4, 18.5, 4, 8, 8.5, 12.5, 12, 6, 15.5, 12.5, 20, 8, 20, 18.5 }, { "l", 4, 21, 20, 21 } },
	hammer = { { "r", 4.5, 4, 15, 6 }, { "l", 12, 10, 12, 21 } },
	home = {
		{ "p", 3, 12, 12, 4, 21, 12 },
		{ "p", 6, 10, 6, 20, 18, 20, 18, 10 },
		{ "p", 10, 20, 10, 14, 14, 14, 14, 20 },
	},
	shop = {
		{ "q", 4, 9, 5.5, 4.5, 18.5, 4.5, 20, 9 },
		{ "p", 5, 9, 5, 20, 19, 20, 19, 9 },
		{ "p", 10, 20, 10, 14, 14, 14, 14, 20 },
	},
	bag = { { "r", 4.5, 9, 15, 11.5 }, { "p", 9, 9, 9, 5.5, 15, 5.5, 15, 9 } },
	gem = {
		{ "q", 7, 5, 17, 5, 21, 10, 12, 20.5, 3, 10 },
		{ "l", 3, 10, 21, 10 },
		{ "p", 9, 10, 12, 20.5, 15, 10 },
	},
	coin = { { "c", 12, 12, 8.5 }, { "r", 9.5, 9.5, 5, 5, 45 } },
	trophy = {
		{ "q", 7, 4, 17, 4, 16, 11, 12, 14, 8, 11 },
		{ "p", 7, 6, 4, 6, 4, 9, 7.6, 11 },
		{ "p", 17, 6, 20, 6, 20, 9, 16.4, 11 },
		{ "l", 12, 14, 12, 18 },
		{ "l", 7.5, 20, 16.5, 20 },
	},
	-- The Lantern star: two squares at 45 degrees
	star = { { "r", 6, 6, 12, 12 }, { "r", 6, 6, 12, 12, 45 } },
	chart = {
		{ "p", 4, 3.5, 4, 20, 20.5, 20 },
		{ "l", 9, 20, 9, 13 },
		{ "l", 13.5, 20, 13.5, 8 },
		{ "l", 18, 20, 18, 15 },
	},
	book = {
		{ "l", 12, 6.5, 12, 20 },
		{ "p", 12, 6.5, 3.5, 5, 3.5, 18, 12, 20 },
		{ "p", 12, 6.5, 20.5, 5, 20.5, 18, 12, 20 },
	},
	eye = {
		{ "a", 12, 15.75, 9.75, 202.6, 337.4 },
		{ "a", 12, 8.25, 9.75, 22.6, 157.4 },
		{ "c", 12, 12, 3 },
		{ "d", 12, 12, 1 },
	},
	user = { { "c", 12, 8, 3.5 }, { "a", 12, 21, 7, 180, 360 } },
	users = {
		{ "c", 9.5, 8.5, 3.2 },
		{ "a", 9.5, 21, 6.5, 180, 360 },
		{ "c", 16.5, 7, 2.8 },
		{ "a", 16.5, 18.5, 5.5, 250, 360 },
	},
	lock = { { "r", 5, 11, 14, 10 }, { "a", 12, 11, 4.5, 180, 360 }, { "d", 12, 15, 1.4 }, { "l", 12, 15.5, 12, 18 } },
	unlock = {
		{ "r", 5, 11, 14, 10 },
		{ "a", 12, 8.5, 4.5, 180, 360 },
		{ "l", 16.5, 8.5, 16.5, 11 },
		{ "d", 12, 15, 1.4 },
		{ "l", 12, 15.5, 12, 18 },
	},
	check = { { "p", 4.5, 12.5, 9.5, 17.5, 19.5, 7 } },
	cross = { { "l", 6, 6, 18, 18 }, { "l", 18, 6, 6, 18 } },
	plus = { { "l", 12, 5, 12, 19 }, { "l", 5, 12, 19, 12 } },
	minus = { { "l", 5, 12, 19, 12 } },
	["arrow-left"] = { { "l", 19.5, 12, 5.5, 12 }, arrow(4.5, 12, 180, 6.5) },
	["arrow-right"] = { { "l", 4.5, 12, 18.5, 12 }, arrow(19.5, 12, 0, 6.5) },
	["arrow-up"] = { { "l", 12, 19.5, 12, 5.5 }, arrow(12, 4.5, 270, 6.5) },
	["arrow-down"] = { { "l", 12, 4.5, 12, 18.5 }, arrow(12, 19.5, 90, 6.5) },
	["chevron-left"] = { { "p", 15, 5, 8, 12, 15, 19 } },
	["chevron-right"] = { { "p", 9, 5, 16, 12, 9, 19 } },
	["chevron-up"] = { { "p", 5, 15, 12, 8, 19, 15 } },
	["chevron-down"] = { { "p", 5, 9, 12, 16, 19, 9 } },
	refresh = { { "a", 12, 12, 7.5, -40, 230 }, arrow(17.75, 7.18, -130, 4.5) },
	rotate = { { "a", 12, 13, 8.5, 200, 340 }, arrow(4.2, 10.3, 120, 4), arrow(19.8, 10.3, 60, 4), { "d", 12, 18, 1.5 } },
	clock = { { "c", 12, 12, 8.5 }, { "p", 12, 6.5, 12, 12, 16, 14.5 } },
	heart = { { "q", 12, 8, 10, 5.5, 7, 5, 4.5, 7, 4, 10, 5.5, 13, 12, 20, 18.5, 13, 20, 10, 19.5, 7, 17, 5, 14, 5.5 } },
	skull = {
		{ "a", 12, 10.5, 7.5, 160, 380 },
		{ "p", 4.95, 13.07, 8, 15.5, 8, 20, 16, 20, 16, 15.5, 19.05, 13.07 },
		{ "d", 9, 11, 1.9 },
		{ "d", 15, 11, 1.9 },
		{ "l", 12, 20, 12, 17.5 },
	},
	flag = { { "l", 6, 3, 6, 21 }, { "p", 6, 4.5, 18, 4.5, 15, 9, 18, 13.5, 6, 13.5 } },
	camera = {
		{ "r", 3, 8, 18, 12 },
		{ "p", 8, 8, 9.5, 5, 14.5, 5, 16, 8 },
		{ "c", 12, 14, 3.5 },
	},
	music = {
		{ "l", 9, 17, 9, 5 },
		{ "l", 18, 15, 18, 3 },
		{ "l", 9, 5, 18, 3 },
		{ "d", 6.7, 17.5, 2.6 },
		{ "d", 15.7, 15.5, 2.6 },
	},
	volume = {
		{ "q", 3.5, 9, 7.5, 9, 12.5, 5, 12.5, 19, 7.5, 15, 3.5, 15 },
		{ "a", 13, 12, 4, -45, 45 },
		{ "a", 13, 12, 7.5, -45, 45 },
	},
	gamepad = {
		{ "r", 3, 8, 18, 10 },
		{ "l", 6.5, 13, 10, 13 },
		{ "l", 8.25, 11.25, 8.25, 14.75 },
		{ "d", 15.5, 11.8, 1.2 },
		{ "d", 17.8, 14.2, 1.2 },
	},
	keyboard = {
		{ "r", 2.5, 6, 19, 12 },
		{ "f", 5.2, 9, 1.8, 1.8 },
		{ "f", 8.7, 9, 1.8, 1.8 },
		{ "f", 12.2, 9, 1.8, 1.8 },
		{ "f", 15.7, 9, 1.8, 1.8 },
		{ "f", 5.2, 12, 1.8, 1.8 },
		{ "f", 18.2, 12, 1.8, 1.8 },
		{ "l", 9, 15, 15, 15 },
	},
	touch = {
		{ "p", 9, 21, 9, 8.5, 10.25, 7, 11.5, 8.5, 11.5, 13, 18.5, 14.2, 18.5, 21 },
		{ "a", 10.25, 8, 5, 200, 340 },
	},
	info = { { "c", 12, 12, 9 }, { "d", 12, 7.8, 1.3 }, { "l", 12, 11, 12, 17 } },
	warning = { { "q", 12, 3.5, 21, 19.5, 3, 19.5 }, { "l", 12, 9, 12, 13.8 }, { "d", 12, 16.6, 1.3 } },
	search = { { "c", 10.5, 10.5, 6 }, { "l", 15, 15, 20.5, 20.5 } },
	compare = { { "r", 3.5, 5, 7, 14 }, { "r", 13.5, 5, 7, 14 }, { "l", 12, 2.5, 12, 21.5 } },

	-- Ability kinds (fallbacks when a power doesn't name a drawn icon)
	burst = {
		{ "d", 12, 12, 1.8 },
		{ "l", 12, 2.5, 12, 7 },
		{ "l", 12, 17, 12, 21.5 },
		{ "l", 2.5, 12, 7, 12 },
		{ "l", 17, 12, 21.5, 12 },
		{ "l", 5.3, 5.3, 8.5, 8.5 },
		{ "l", 15.5, 15.5, 18.7, 18.7 },
		{ "l", 18.7, 5.3, 15.5, 8.5 },
		{ "l", 8.5, 15.5, 5.3, 18.7 },
	},
	dash = { { "p", 5, 6, 11, 12, 5, 18 }, { "p", 12, 6, 18, 12, 12, 18 } },
	grab = {
		{ "p", 6, 11, 6, 17, 12, 21, 18, 17, 18, 8 },
		{ "l", 9, 12, 9, 4 },
		{ "l", 12, 12, 12, 3 },
		{ "l", 15, 12, 15, 4 },
	},
	projectile = { { "l", 4, 20, 17, 7 }, arrow(19, 5, -45, 6), { "l", 4, 14, 8, 10 }, { "l", 10, 20, 14, 16 } },
	throw = { { "a", 12, 21, 8.5, 200, 330 }, arrow(19.36, 16.75, 60, 4.5), { "d", 4, 18, 1.8 } },
	counter = { { "q", 5, 4.5, 19, 4.5, 19, 12, 12, 20, 5, 12 }, { "l", 15.5, 11, 9.5, 11 }, arrow(8.5, 11, 180, 4) },
	zone = { { "c", 12, 12, 8.5 }, { "d", 12, 12, 2.2 } },
	buff = { { "p", 6, 12.5, 12, 6.5, 18, 12.5 }, { "p", 6, 18.5, 12, 12.5, 18, 18.5 } },
	teleport = {
		{ "a", 12, 12, 8.5, 10, 80 },
		{ "a", 12, 12, 8.5, 100, 170 },
		{ "a", 12, 12, 8.5, 190, 260 },
		{ "a", 12, 12, 8.5, 280, 350 },
		{ "d", 12, 12, 2.2 },
	},
	construct = {
		{ "q", 12, 3, 20, 7.5, 20, 16.5, 12, 21, 4, 16.5, 4, 7.5 },
		{ "p", 4, 7.5, 12, 12, 20, 7.5 },
		{ "l", 12, 12, 12, 21 },
	},
	ultimate = { { "r", 6, 6, 12, 12 }, { "r", 6, 6, 12, 12, 45 }, { "d", 12, 12, 2 } },
	-- The facet motif: the fallback for anything unknown
	facet = { { "q", 12, 2.5, 17, 12, 12, 21.5, 7, 12 } },
	dot = { { "d", 12, 12, 3 } },

	-- Programme sigils (the registry's cover sheet, Archive "programme_sigils")
	["sigil-atlas"] = { { "l", 4, 20.5, 20, 20.5 }, { "r", 9.5, 9, 5, 9 }, { "p", 8, 6.5, 12, 3, 16, 6.5 } },
	["sigil-veil"] = { { "a", 12, 15, 8, 180, 360 }, { "l", 4, 15, 20, 15 }, { "l", 8, 19.5, 16, 19.5 } },
	["sigil-chimera"] = { { "l", 5.5, 19, 10, 5 }, { "l", 10.5, 20, 15, 6 }, { "l", 15.5, 19, 20, 5 } },
	["sigil-furnace"] = {
		{ "c", 12, 12, 7.5 },
		{ "f", 10.75, 1.5, 2.5, 3 },
		{ "f", 10.75, 19.5, 2.5, 3 },
		{ "f", 1.5, 10.75, 3, 2.5 },
		{ "f", 19.5, 10.75, 3, 2.5 },
		{ "q", 12, 7.5, 14.5, 11.5, 14, 15, 12, 16.5, 10, 15, 9.5, 11.5 },
	},
	["sigil-eclipse"] = { { "c", 12, 12, 8.5 }, { "d", 12, 12, 5.2 } },
	["sigil-lattice"] = {
		{ "d", 6, 6, 1.5 },
		{ "d", 12, 6, 1.5 },
		{ "d", 18, 6, 1.5 },
		{ "d", 6, 12, 1.5 },
		{ "d", 12, 12, 1.5 },
		{ "d", 18, 12, 1.5 },
		{ "d", 6, 18, 1.5 },
		{ "d", 12, 18, 1.5 },
		{ "d", 18, 18, 1.5 },
	},
	["sigil-warden"] = { { "q", 5, 4, 19, 4, 19, 12, 12, 20.5, 5, 12 }, { "d", 12, 10, 2.2 }, { "f", 11, 10.5, 2, 5 } },
	["sigil-grandmaster"] = { { "r", 5, 5, 14, 14 } },
}

-- Names other screens use for the same drawings
local ALIASES = {
	settings = "gear",
	close = "cross",
	add = "plus",
	powers = "facet",
	progress = "trophy",
	watch = "eye",
	learn = "book",
	archive = "book",
	base = "home",
	reward = "star",
	success = "check",
	error = "warning",
	money = "coin",
	gems = "gem",
	melee = "fight",
	area = "burst",
	form = "paw",
	buff = "buff",
	time = "clock",
	cpu = "user",
	training = "target",
	spawn = "home",
}

-- Emoji older code (and power definitions) still pass, mapped to drawings
local EMOJI: { [string]: string } = {
	["⚔️"] = "swords", ["⚔"] = "swords", ["🗡️"] = "swords", ["🗡"] = "swords", ["🔪"] = "swords",
	["🛡️"] = "shield", ["🛡"] = "shield",
	["🎯"] = "target", ["👻"] = "ghost", ["🐾"] = "paw", ["🐺"] = "paw", ["🐻"] = "paw", ["🦅"] = "paw",
	["⚙️"] = "gear", ["⚙"] = "gear", ["🔧"] = "cog", ["🛠️"] = "cog", ["🤖"] = "cog",
	["⚡"] = "bolt", ["🔥"] = "fire", ["💻"] = "code", ["⌨️"] = "keyboard",
	["👑"] = "crown", ["🔨"] = "hammer", ["🏠"] = "home", ["🛒"] = "shop", ["🎒"] = "bag",
	["💎"] = "gem", ["💵"] = "coin", ["💰"] = "coin", ["🪙"] = "coin",
	["🏆"] = "trophy", ["⭐"] = "star", ["🌟"] = "star", ["✨"] = "star", ["✦"] = "star", ["🎁"] = "star",
	["📊"] = "chart", ["📈"] = "chart", ["📖"] = "book", ["📚"] = "book", ["📜"] = "book",
	["👁️"] = "eye", ["👁"] = "eye", ["📺"] = "eye", ["👤"] = "user", ["👥"] = "users",
	["🔒"] = "lock", ["🔓"] = "unlock", ["✅"] = "check", ["✓"] = "check", ["✔"] = "check",
	["❌"] = "cross", ["✕"] = "cross", ["✖"] = "cross", ["➕"] = "plus", ["➖"] = "minus",
	["🔄"] = "refresh", ["⏱"] = "clock", ["⏱️"] = "clock", ["⏰"] = "clock", ["🕐"] = "clock",
	["❤️"] = "heart", ["💀"] = "skull", ["☠️"] = "skull", ["🚩"] = "flag", ["🏁"] = "flag",
	["📷"] = "camera", ["🎥"] = "camera", ["🎵"] = "music", ["🎶"] = "music", ["🔊"] = "volume",
	["🎮"] = "gamepad", ["👆"] = "touch", ["ℹ️"] = "info", ["💬"] = "info", ["❔"] = "info", ["❓"] = "info",
	["⚠️"] = "warning", ["⚠"] = "warning", ["💥"] = "burst", ["💢"] = "burst", ["🌊"] = "burst",
	["💨"] = "dash", ["🏃"] = "dash", ["✊"] = "fight", ["👊"] = "fight", ["🥊"] = "fight", ["💪"] = "fight",
	["🤜"] = "fight", ["✋"] = "grab", ["🤚"] = "grab", ["🫳"] = "grab", ["🪨"] = "throw", ["☄️"] = "projectile",
	["🌀"] = "teleport", ["🌐"] = "zone", ["🔮"] = "zone", ["🧱"] = "construct", ["📦"] = "construct",
	["🧪"] = "facet", ["🔁"] = "counter", ["↩️"] = "counter", ["🐉"] = "ultimate",
}

-- A power's programme sigil by power id
local SIGILS = {
	StrongDude = "sigil-atlas",
	Ghost = "sigil-veil",
	Shapeshifter = "sigil-chimera",
	MachineMaster = "sigil-furnace",
	Corruption = "sigil-eclipse",
	Syntax = "sigil-lattice",
	Admin = "sigil-warden",
	Grandmaster = "sigil-grandmaster",
}

-- An ability's drawing from its kind, when it names none
local KINDS = {
	Melee = "fight",
	Area = "burst",
	Grab = "grab",
	Dash = "dash",
	Projectile = "projectile",
	Throw = "throw",
	Counter = "counter",
	Zone = "zone",
	Buff = "buff",
	Teleport = "teleport",
	Form = "paw",
	Construct = "construct",
	Ultimate = "ultimate",
}

function Icons.has(name: string): boolean
	return typeof(name) == "string" and (DEFS[name] ~= nil or ALIASES[name] ~= nil)
end

-- The drawing for a name, an alias or an emoji (the facet when unknown)
function Icons.resolve(name: any): string
	if typeof(name) ~= "string" then
		return "facet"
	end
	if DEFS[name] then
		return name
	end
	if ALIASES[name] then
		return ALIASES[name]
	end
	local lower = string.lower(name)
	if DEFS[lower] then
		return lower
	end
	if EMOJI[name] then
		return EMOJI[name]
	end
	-- An emoji with a variation selector or a skin tone: try its first character
	for _, code in utf8.codes(name) do
		local first = EMOJI[utf8.char(code)]
		if first then
			return first
		end
		break
	end
	return "facet"
end

function Icons.sigil(powerId: string?): string
	return SIGILS[powerId or ""] or "facet"
end

-- An ability's drawing: its own iconName, its emoji mapped, or its kind
function Icons.forAbility(ability: any): string
	if typeof(ability) ~= "table" then
		return "facet"
	end
	if typeof(ability.iconName) == "string" and DEFS[ability.iconName] then
		return ability.iconName
	end
	local fromEmoji = if typeof(ability.icon) == "string" then EMOJI[ability.icon] else nil
	if fromEmoji then
		return fromEmoji
	end
	return KINDS[ability.kind] or "facet"
end

function Icons.names(): { string }
	local list = {}
	for name in DEFS do
		table.insert(list, name)
	end
	table.sort(list)
	return list
end

-- Drawing -----------------------------------------------------------------------------

local function paint(parent: Instance, props: { [string]: any }): Frame
	local frame = Instance.new("Frame")
	frame.Name = INK
	frame.BorderSizePixel = 0
	for key, value in props do
		(frame :: any)[key] = value
	end
	frame.Parent = parent
	return frame
end

-- One straight stroke from (x1, y1) to (x2, y2) in pixels. Caps extend the
-- ends by half the stroke so line ends are square; axis-aligned strokes snap
-- to whole pixels so they stay crisp.
local function bar(parent: Instance, x1: number, y1: number, x2: number, y2: number, width: number, color: Color3, capStart: boolean, capEnd: boolean)
	local dx, dy = x2 - x1, y2 - y1
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 0.01 then
		return
	end
	local ux, uy = dx / length, dy / length
	local s = if capStart then width / 2 else 0
	local e = if capEnd then width / 2 else 0
	local ax, ay = x1 - ux * s, y1 - uy * s
	local bx, by = x2 + ux * e, y2 + uy * e
	if math.abs(dx) < 0.01 or math.abs(dy) < 0.01 then
		local left = math.floor(math.min(ax, bx) - (if math.abs(dx) < 0.01 then width / 2 else 0) + 0.5)
		local top = math.floor(math.min(ay, by) - (if math.abs(dy) < 0.01 then width / 2 else 0) + 0.5)
		local right = math.floor(math.max(ax, bx) + (if math.abs(dx) < 0.01 then width / 2 else 0) + 0.5)
		local bottom = math.floor(math.max(ay, by) + (if math.abs(dy) < 0.01 then width / 2 else 0) + 0.5)
		paint(parent, {
			Position = UDim2.fromOffset(left, top),
			Size = UDim2.fromOffset(math.max(1, right - left), math.max(1, bottom - top)),
			BackgroundColor3 = color,
		})
		return
	end
	paint(parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2),
		Size = UDim2.fromOffset(length + s + e, width),
		Rotation = math.deg(math.atan2(dy, dx)),
		BackgroundColor3 = color,
	})
end

-- A small square at a joint so polyline corners close without spikes
local function joint(parent: Instance, x: number, y: number, width: number, angle: number, color: Color3)
	paint(parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(width, width),
		Rotation = angle,
		BackgroundColor3 = color,
	})
end

local function polyline(parent: Instance, points: { number }, closed: boolean, u: number, width: number, color: Color3)
	local count = #points // 2
	local function at(index: number): (number, number)
		local i = ((index - 1) % count) * 2
		return points[i + 1] * u, points[i + 2] * u
	end
	local segments = if closed then count else count - 1
	for index = 1, segments do
		local x1, y1 = at(index)
		local x2, y2 = at(index + 1)
		bar(parent, x1, y1, x2, y2, width, color, not closed and index == 1, not closed and index == segments)
	end
	-- Joints between segments
	local first = if closed then 1 else 2
	local last = if closed then count else count - 1
	for index = first, last do
		local px, py = at(index - 1 + (if index == 1 then count else 0))
		local x, y = at(index)
		local nx, ny = at(index + 1)
		local a1 = math.atan2(y - py, x - px)
		local a2 = math.atan2(ny - y, nx - x)
		joint(parent, x, y, width, math.deg((a1 + a2) / 2), color)
	end
end

local function arc(parent: Instance, cx: number, cy: number, r: number, from: number, to: number, u: number, width: number, color: Color3)
	local sweep = to - from
	local steps = math.max(3, math.ceil(math.abs(sweep) / 20))
	local points = {}
	for step = 0, steps do
		local angle = math.rad(from + sweep * step / steps)
		table.insert(points, cx + r * math.cos(angle))
		table.insert(points, cy + r * math.sin(angle))
	end
	polyline(parent, points, false, u, width, color)
end

local function box(parent: Instance, x: number, y: number, w: number, h: number, rotation: number?, u: number, width: number, color: Color3, filled: boolean)
	local cx, cy = (x + w / 2) * u, (y + h / 2) * u
	if filled then
		local frame = paint(parent, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cy),
			Size = UDim2.fromOffset(w * u, h * u),
			Rotation = rotation or 0,
			BackgroundColor3 = color,
		})
		if not rotation or rotation == 0 then
			-- Snap to whole pixels
			frame.AnchorPoint = Vector2.zero
			frame.Position = UDim2.fromOffset(math.floor(x * u + 0.5), math.floor(y * u + 0.5))
			frame.Size = UDim2.fromOffset(math.max(1, math.floor(w * u + 0.5)), math.max(1, math.floor(h * u + 0.5)))
		end
		return
	end
	-- The stroke sits outside the frame, so shrink the frame by one stroke to
	-- centre the drawn line on the path
	local frame = paint(parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(math.max(1, w * u - width), math.max(1, h * u - width)),
		Rotation = rotation or 0,
		BackgroundTransparency = 1,
	})
	local stroke = Instance.new("UIStroke")
	stroke.Name = INK
	stroke.Color = color
	stroke.Thickness = width
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Parent = frame
end

local function ring(parent: Instance, cx: number, cy: number, r: number, u: number, width: number, color: Color3, filled: boolean)
	local diameter = if filled then r * 2 * u else math.max(1, r * 2 * u - width)
	local frame = paint(parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx * u, cy * u),
		Size = UDim2.fromOffset(diameter, diameter),
		BackgroundColor3 = color,
		BackgroundTransparency = if filled then 0 else 1,
	})
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	if not filled then
		local stroke = Instance.new("UIStroke")
		stroke.Name = INK
		stroke.Color = color
		stroke.Thickness = width
		stroke.Parent = frame
	end
end

-- Stroke width in pixels for an icon of this size (2 px at 16-24 px)
function Icons.strokeFor(size: number): number
	return math.max(2, math.floor(size / 12 + 0.5))
end

-- Builds an icon: a size x size Frame (transparent) holding the drawing
function Icons.make(name: string, size: number?, color: Color3?): Frame
	local resolved = Icons.resolve(name)
	local px = size or 24
	local tint = color or Color3.fromRGB(237, 230, 214)
	local u = px / UNITS
	local width = Icons.strokeFor(px)
	local holder = Instance.new("Frame")
	holder.Name = "Icon"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(px, px)
	holder:SetAttribute("SNIcon", resolved)
	for _, op in DEFS[resolved] do
		local kind = op[1]
		if kind == "l" then
			bar(holder, op[2] * u, op[3] * u, op[4] * u, op[5] * u, width, tint, true, true)
		elseif kind == "p" or kind == "q" then
			local points = {}
			for index = 2, #op do
				table.insert(points, op[index])
			end
			polyline(holder, points, kind == "q", u, width, tint)
		elseif kind == "r" or kind == "f" then
			box(holder, op[2], op[3], op[4], op[5], op[6], u, width, tint, kind == "f")
		elseif kind == "c" or kind == "d" then
			ring(holder, op[2], op[3], op[4], u, width, tint, kind == "d")
		elseif kind == "a" then
			arc(holder, op[2], op[3], op[4], op[5], op[6], u, width, tint)
		elseif kind == "h" then
			local x, y, angle, length = op[2] * u, op[3] * u, math.rad(op[4]), (op[5] or 4.5) * u
			for _, side in { -1, 1 } do
				local back = angle + math.pi + side * math.rad(42)
				bar(holder, x, y, x + math.cos(back) * length, y + math.sin(back) * length, width, tint, false, true)
			end
			joint(holder, x, y, width, op[4] + 45, tint)
		end
	end
	return holder
end

-- Recolours an icon (and optionally fades it: 0 = solid, 1 = invisible)
function Icons.tint(icon: Instance, color: Color3, transparency: number?)
	for _, item in icon:GetDescendants() do
		if item.Name == INK then
			if item:IsA("UIStroke") then
				item.Color = color
				if transparency then
					item.Transparency = transparency
				end
			elseif item:IsA("Frame") and item.BackgroundTransparency < 1 then
				item.BackgroundColor3 = color
				if transparency then
					item.BackgroundTransparency = transparency
				end
			end
		end
	end
end

return Icons
