-- The Admin Abuse v2 / Overlord preset catalogue. Data only: each preset is a recipe of
-- reusable effect modules (src/server/Events/Effects) with parameters. Adding an event is
-- one entry here, never a new script.
--
-- A preset has: id, name, category, level (1 subtle .. 4 extravagant), description,
-- duration (default seconds), tags, excludes (tags it refuses to run beside), effects
-- ({ effect, params }), onConflict ("reject" or "replace"), ownerOnly, eventMode (true when
-- an effect changes gameplay; such presets only run in explicit event mode).
-- Colours are { r, g, b } arrays. Two presets may never share an effect set with near
-- identical settings (tests/overlord_test.luau enforces it; colours do not count).
--
-- Sound: no authorised audio asset ids exist yet, so presets carry no audio.

local EventPresets = {}

EventPresets.Categories = {
	{ id = "World", name = "World transformations" },
	{ id = "Player", name = "Player effects" },
	{ id = "Environment", name = "Gravity and environment" },
	{ id = "Spectacle", name = "Spectacle and celebration" },
	{ id = "Owner", name = "Owner exclusive" },
	{ id = "Thanksgiving", name = "Thanksgiving collection" },
	{ id = "Christmas", name = "Christmas collection" },
}

local DEFAULT_DURATION = { 300, 600, 900, 1200 }
local GAMEPLAY = { Gravity = true, Speed = true }

local list = {}

local function add(id, name, category, level, description, effects, extra)
	extra = extra or {}
	local converted = {}
	local gameplay = false
	for _, entry in effects do
		table.insert(converted, { effect = entry[1], params = entry[2] or {} })
		if GAMEPLAY[entry[1]] then
			gameplay = true
		end
	end
	table.insert(list, {
		id = id,
		name = name,
		category = category,
		level = level,
		description = description,
		duration = extra.duration or DEFAULT_DURATION[level],
		tags = extra.tags or {},
		excludes = extra.excludes or {},
		effects = converted,
		onConflict = extra.onConflict or "reject",
		ownerOnly = category == "Owner",
		eventMode = gameplay,
	})
end

local GOLD, AMBER, WHITE = { 255, 200, 80 }, { 255, 150, 50 }, { 255, 255, 255 }
local ICE, GREEN, RED, CYAN, PINK, VIOLET = { 170, 225, 255 }, { 60, 200, 110 }, { 230, 50, 60 }, { 90, 230, 255 }, { 255, 110, 190 }, { 160, 110, 255 }

-- A. World transformations -------------------------------------------------------------
local W = "World"
add("w_golden_world", "Golden World", W, 2, "The whole station bathed in low golden light under a gilded sky.", { { "LightingTheme", { theme = "golden" } }, { "SkyTheme", { sky = "golden" } } })
add("w_neon_takeover", "Neon Takeover", W, 3, "Saturated cyan and magenta light with a neon haze over every surface.", { { "LightingTheme", { theme = "neon" } }, { "Atmosphere", { mood = "neon_haze", density = 0.4 } } })
add("w_cosmic_atmosphere", "Cosmic Atmosphere", W, 3, "A violet cosmic sky, deep ambient light and a thin void haze.", { { "LightingTheme", { theme = "cosmic" } }, { "SkyTheme", { sky = "cosmic" } }, { "Atmosphere", { mood = "void", density = 0.2 } } })
add("w_starfield", "Starfield", W, 2, "A dark facility under thousands of stars.", { { "SkyTheme", { sky = "starfield" } }, { "LightingTheme", { theme = "dark_facility", intensity = 0.8 } } })
add("w_aurora_sky", "Aurora Sky", W, 2, "Green and violet aurora light over a cold night.", { { "LightingTheme", { theme = "aurora" } }, { "SkyTheme", { sky = "aurora" } } })
add("w_glowing_facility", "Glowing Facility", W, 3, "Cyan holographic light, a soft glow and a lattice of light beams.", { { "LightingTheme", { theme = "holo" } }, { "Atmosphere", { mood = "glow", density = 0.25 } }, { "Structure", { kind = "lattice", count = 4, scale = 1.2, height = 0, color = CYAN } } })
add("w_dark_experiment", "Dark Experimental Facility", W, 2, "Power rationed: dim light and heavy fog in the lower halls.", { { "LightingTheme", { theme = "dark_facility" } }, { "Atmosphere", { mood = "dense_fog", density = 0.5 } } })
add("w_digital_distortion", "Digital Reality Distortion", W, 3, "Falling data glyphs in a holographic haze.", { { "LightingTheme", { theme = "holo", intensity = 0.7 } }, { "Weather", { kind = "data", rate = 45, wind = 0, size = 0.5, color = { 80, 255, 160 } } }, { "Atmosphere", { mood = "neon_haze", density = 0.3 } } })
add("w_holographic_world", "Holographic World", W, 3, "A giant globe hologram over a holo-lit station.", { { "LightingTheme", { theme = "holo", intensity = 1.2 } }, { "Hologram", { shape = "globe", scale = 2, height = 50, color = CYAN } } })
add("w_floating_energy", "Floating Energy Structures", W, 3, "Orbs of energy circle high over the lobby in a golden glow.", { { "Structure", { kind = "orbit", count = 14, scale = 1.4, height = 40, color = GOLD } }, { "Atmosphere", { mood = "glow", density = 0.3 } } })
add("w_celestial_sky", "Celestial Sky", W, 2, "A huge moon and clear air.", { { "SkyTheme", { sky = "celestial" } }, { "Atmosphere", { mood = "clear", density = 0.15 } } })
add("w_meteor_spectacle", "Meteor Shower Spectacle", W, 3, "Streaking meteors across a dark sky.", { { "Weather", { kind = "meteors", rate = 18, wind = 6, size = 1.2, color = { 255, 190, 120 } } }, { "SkyTheme", { sky = "midnight" } }, { "LightingTheme", { theme = "dark_facility", intensity = 1.1 } } })
add("w_floating_islands", "Floating Islands Showcase", W, 3, "Metal and light islands drift over the lobby at dawn.", { { "Structure", { kind = "islands", count = 8, scale = 1.3, height = 45, color = { 120, 230, 170 } } }, { "SkyTheme", { sky = "dawn" } }, { "Atmosphere", { mood = "clear", density = 0.1 } } })
add("w_massive_holo_install", "Massive Holographic Installation", W, 4, "A double helix of light above a ring of pillars.", { { "Hologram", { shape = "helix", scale = 2.4, height = 55, color = VIOLET } }, { "Structure", { kind = "pillars", count = 10, scale = 1.5, height = 0, color = VIOLET } } })
add("w_glowing_architecture", "Glowing Architecture", W, 3, "Light pillars and a great arch under a bright sunburst.", { { "Structure", { kind = "pillars", count = 8, scale = 1.2, height = 0, color = GOLD } }, { "Structure", { kind = "arch", count = 16, scale = 1.3, height = 4, color = GOLD } }, { "LightingTheme", { theme = "sunburst" } } })
add("w_rainbow_facility", "Rainbow Facility", W, 2, "Pastel rainbow light and a ring of beads.", { { "LightingTheme", { theme = "rainbow" } }, { "Structure", { kind = "ring", count = 32, scale = 1.2, height = 20, color = PINK } } })
add("w_monochrome", "Monochrome World", W, 1, "All colour drained to grey with a light haze.", { { "LightingTheme", { theme = "mono" } }, { "Atmosphere", { mood = "hazy", density = 0.3 } } })
add("w_ethereal", "Ethereal Atmosphere", W, 2, "Pale glowing light and drifting sparkles.", { { "LightingTheme", { theme = "ethereal" } }, { "Atmosphere", { mood = "glow", density = 0.35 } }, { "Weather", { kind = "sparkles", rate = 25, wind = 2, size = 0.3, color = { 230, 235, 255 } } } })
add("w_time_dawn", "Dawn", W, 1, "The station at first light.", { { "SkyTheme", { sky = "dawn" } } })
add("w_time_noon", "High Noon", W, 1, "Clear midday sun.", { { "SkyTheme", { sky = "noon" } } })
add("w_time_dusk", "Dusk", W, 1, "A long amber evening.", { { "SkyTheme", { sky = "dusk" } } })
add("w_time_midnight", "Midnight", W, 1, "Deep night with a thin void haze.", { { "SkyTheme", { sky = "midnight" } }, { "Atmosphere", { mood = "void", density = 0.15 } } })
add("w_eclipse", "Total Eclipse", W, 3, "The moon crosses the sun and the light turns red.", { { "SkyTheme", { sky = "eclipse" } }, { "LightingTheme", { theme = "crimson" } } })
add("w_studio_theme", "Owner Studio Theme", W, 2, "A clean bright stage with clear air: tint it with the colour control.", { { "LightingTheme", { theme = "stadium" } }, { "SkyTheme", { sky = "noon", clockTime = 15 } }, { "Atmosphere", { mood = "clear", density = 0.05 } } })

-- B. Global player effects -------------------------------------------------------------
local B = "Player"
add("p_glow_aura", "Glowing Aura", B, 1, "A soft glow around every participant.", { { "Aura", { style = "glow", size = 1, color = GOLD } } })
add("p_energy_trails", "Energy Trails", B, 2, "Animated energy streams behind moving players.", { { "Trail", { style = "energy", length = 1.2, color = CYAN } } })
add("p_particle_trails", "Particle Trails", B, 1, "Beautiful particle trails.", { { "Trail", { style = "particles", length = 1, color = PINK } } })
add("p_holo_outline", "Holographic Outlines", B, 2, "A cyan holographic outline on each fighter.", { { "Aura", { style = "outline", size = 1, color = CYAN } } })
add("p_floating_symbols", "Floating Symbols", B, 1, "Small symbols orbit over each head.", { { "Halo", { style = "symbols", color = VIOLET } } })
add("p_event_titles", "Event Titles", B, 1, "A gold overhead title for every participant.", { { "Title", { text = "Event Guest", style = "gold", color = GOLD } } })
add("p_cosmic_particles", "Cosmic Particle Aura", B, 3, "Star dust swirls around each player.", { { "Aura", { style = "cosmic", size = 1.4, color = VIOLET } } })
add("p_energy_rings", "Animated Energy Rings", B, 2, "Rings of light spin around each fighter.", { { "Aura", { style = "rings", size = 1.2, color = CYAN } } })
add("p_halos", "Radiant Halos", B, 1, "A bright halo above each head.", { { "Halo", { style = "halo", color = { 255, 240, 170 } } } })
add("p_floating_platforms", "Personal Floating Platforms", B, 2, "Small glowing discs hover near the lobby floor.", { { "Structure", { kind = "islands", count = 3, scale = 0.6, height = 4, color = CYAN } } })
add("p_appearance_theme", "Temporary Appearance Theme", B, 3, "A static crackle, a crown and a royal title.", { { "Aura", { style = "static", size = 1, color = { 255, 230, 120 } } }, { "Halo", { style = "crown", color = GOLD } }, { "Title", { text = "Royal Guard", style = "royal", color = GOLD } } })
add("p_spawn_spectacle", "Spectacular Spawn", B, 2, "Players arrive in a burst of star dust.", { { "Arrival", { style = "stardust", color = { 200, 220, 255 } } } })
add("p_victory_celebration", "Victory Celebration", B, 2, "Streamers and a shockwave at every spawn.", { { "Confetti", { shape = "streamers", rate = 25, color = PINK } }, { "Arrival", { style = "shockwave", color = GOLD } } })
add("p_entrance_portal", "Portal Entrance", B, 2, "Players step out of a portal.", { { "Arrival", { style = "portal", color = VIOLET } } })
add("p_companions", "Floating Companions", B, 2, "A small orb follows each participant.", { { "Companion", { kind = "orb", color = CYAN } } })
add("p_nameplate_theme", "Themed Nameplates", B, 1, "Frosted titles with a star above.", { { "Title", { text = "Frost Division", style = "frost", color = ICE } }, { "Halo", { style = "star", color = ICE } } })
add("p_orbit_halos", "Orbiting Halos", B, 2, "Rings circle each head.", { { "Halo", { style = "orbit_rings", color = CYAN } } })
add("p_light_emission", "Controlled Light Emission", B, 2, "A warm flame-like glow that casts light.", { { "Aura", { style = "flame", size = 0.9, color = AMBER } } })
add("p_footprints", "Light Footprints", B, 1, "Footprints of light follow each step.", { { "Trail", { style = "footprints", length = 1, color = WHITE } } })
add("p_event_exclusive", "Event Exclusive Look", B, 3, "A festive aura, a spark companion and a neon title.", { { "Aura", { style = "festive", size = 1.1, color = PINK } }, { "Companion", { kind = "spark", color = PINK } }, { "Title", { text = "Event Exclusive", style = "neon", color = PINK } } })
add("p_comet_trail", "Comet Trail", B, 2, "A bright comet tail.", { { "Trail", { style = "comet", length = 1.6, color = { 255, 240, 200 } } } })
add("p_ribbon_trail", "Ribbon Trail", B, 1, "A flowing ribbon behind each player.", { { "Trail", { style = "ribbon", length = 1.4, color = GREEN } } })
add("p_pixel_drone", "Pixel Trail and Drone", B, 2, "Pixel blocks trail behind, a drone hovers near.", { { "Trail", { style = "pixels", length = 1, color = { 80, 255, 160 } } }, { "Companion", { kind = "drone", color = { 80, 255, 160 } } } })

-- C. Gravity and environment modifiers -------------------------------------------------
local C = "Environment"
add("e_low_gravity", "Low Gravity Showcase", C, 2, "Gravity at 40 percent in event mode.", { { "Gravity", { scale = 0.4 } } })
add("e_zero_gravity", "Zero Gravity Arena", C, 4, "Near-zero gravity under a void haze.", { { "Gravity", { scale = 0.08 } }, { "Atmosphere", { mood = "void", density = 0.3 } } })
add("e_floating_platforms", "Floating Platform Event", C, 3, "Light gravity and platforms to jump between.", { { "Gravity", { scale = 0.5 } }, { "Structure", { kind = "islands", count = 8, scale = 1.2, height = 12, color = CYAN } } })
add("e_slow_motion", "Slow Motion Showcase", C, 2, "Everyone moves at half speed in event mode.", { { "Speed", { multiplier = 0.5 } } })
add("e_fast_paced", "Fast Paced Movement", C, 2, "Movement at 1.8 times speed in event mode.", { { "Speed", { multiplier = 1.8 } } })
add("e_dust_wind", "Atmospheric Wind", C, 1, "Gusting ash and dust.", { { "Weather", { kind = "ash", rate = 30, wind = 18, size = 0.3, color = { 190, 180, 170 } } } })
add("e_snow", "Snow Environment", C, 2, "Steady snow and cold air.", { { "Weather", { kind = "snow", rate = 40, wind = 3, size = 0.3, color = WHITE } }, { "Atmosphere", { mood = "icy", density = 0.3 } } })
add("e_autumn_wind", "Autumn Wind", C, 1, "Leaves blow across the lobby.", { { "Weather", { kind = "leaves", rate = 28, wind = -12, size = 0.6, color = AMBER } } })
add("e_gentle_rain", "Gentle Rain", C, 1, "Light rain.", { { "Weather", { kind = "rain", rate = 25, wind = 1, size = 0.2, color = { 170, 190, 220 } } } })
add("e_sparkling_snowfall", "Sparkling Snowfall", C, 2, "Glittering flakes in frost light.", { { "Weather", { kind = "sparkles", rate = 35, wind = 0, size = 0.2, color = ICE } }, { "LightingTheme", { theme = "frost" } } })
add("e_cosmic_environment", "Cosmic Environment", C, 3, "Meteors fall slowly through reduced gravity.", { { "Weather", { kind = "meteors", rate = 10, wind = 0, size = 1, color = VIOLET } }, { "Gravity", { scale = 0.6 } } })
add("e_floating_decor", "Floating Decorative Objects", C, 2, "Bubbles and drifting orbs.", { { "Structure", { kind = "orbit", count = 10, scale = 1, height = 15, color = CYAN } }, { "Weather", { kind = "bubbles", rate = 15, wind = 1, size = 0.8, color = CYAN } } })
add("e_ember_lighting", "Ember Lighting Change", C, 1, "Warm ember light.", { { "LightingTheme", { theme = "ember" } } })
add("e_themed_arena", "Themed Arena Transformation", C, 3, "A lattice arena, dim light and lighter gravity.", { { "Structure", { kind = "lattice", count = 5, scale = 1.4, height = 0, color = { 255, 90, 60 } } }, { "LightingTheme", { theme = "dark_facility", intensity = 1.2 } }, { "Gravity", { scale = 0.7 } } })
add("e_moon_jump", "Moon Jump", C, 3, "A quarter gravity and a slight speed up.", { { "Gravity", { scale = 0.25 } }, { "Speed", { multiplier = 1.2 } } })
add("e_heavy_world", "Heavy World", C, 3, "Heavy gravity and slower movement.", { { "Gravity", { scale = 1.4 } }, { "Speed", { multiplier = 0.8 } } })

-- D. Spectacle and celebration ---------------------------------------------------------
local D = "Spectacle"
add("s_massive_fireworks", "Massive Fireworks", D, 4, "Big peony bursts every second.", { { "Fireworks", { pattern = "peony", interval = 1, size = 1.8, color = GOLD } } })
add("s_worldwide_celebration", "Worldwide Celebration", D, 4, "Ring bursts, confetti and a banner.", { { "Fireworks", { pattern = "ring", interval = 1.5, size = 1.2, color = CYAN } }, { "Confetti", { shape = "squares", rate = 35, color = PINK } }, { "Banner", { text = "Worldwide celebration at Meridian Station", style = "gold" } } })
add("s_golden_sky", "Golden Sky Event", D, 3, "A golden sky, sunburst light and rising sparkles.", { { "SkyTheme", { sky = "golden", clockTime = 17.5 } }, { "Weather", { kind = "sparkles", rate = 20, wind = 0, size = 0.3, color = GOLD } }, { "LightingTheme", { theme = "sunburst", intensity = 1.2 } } })
add("s_grand_entrance", "Grand Entrance", D, 4, "A golden gate, a giant crown and a banner.", { { "Arrival", { style = "golden_gate", color = GOLD } }, { "Hologram", { shape = "crown", scale = 2.2, height = 45, color = GOLD } }, { "Banner", { text = "A grand entrance", style = "gold" } } })
add("s_giant_hologram", "Giant Hologram", D, 3, "A huge emblem over the lobby.", { { "Hologram", { shape = "emblem", scale = 2.8, height = 55, color = CYAN } } })
add("s_stadium_takeover", "Stadium Lighting Takeover", D, 3, "Floodlights, clear air and star bursts.", { { "LightingTheme", { theme = "stadium" } }, { "Atmosphere", { mood = "clear", density = 0.1 } }, { "Fireworks", { pattern = "star", interval = 3, size = 1, color = WHITE } } })
add("s_cosmic_celebration", "Cosmic Celebration", D, 4, "Spiral fireworks under a cosmic sky.", { { "SkyTheme", { sky = "cosmic" } }, { "Fireworks", { pattern = "spiral", interval = 2, size = 1.5, color = VIOLET } } })
add("s_energy_display", "Massive Decorative Energy Display", D, 4, "A ring, pillars and a star of light.", { { "Structure", { kind = "ring", count = 40, scale = 1.6, height = 25, color = CYAN } }, { "Structure", { kind = "pillars", count = 12, scale = 1.6, height = 0, color = CYAN } }, { "Hologram", { shape = "star", scale = 2, height = 60, color = CYAN } } })
add("s_confetti", "Confetti Celebration", D, 2, "Streamers fall on everyone.", { { "Confetti", { shape = "streamers", rate = 50, color = PINK } } })
add("s_spawn_showcase", "Spawn Showcase", D, 3, "Lightning arrivals under a star halo.", { { "Arrival", { style = "lightning", color = { 200, 230, 255 } } }, { "Halo", { style = "star", color = { 200, 230, 255 } } } })
add("s_countdown", "Special Countdown", D, 2, "A clock hologram and an alert banner.", { { "Hologram", { shape = "clock", scale = 2, height = 40, color = RED } }, { "Banner", { text = "Countdown to the main event", style = "alert" } } })
add("s_giant_centerpiece", "Giant Centerpiece", D, 3, "An obelisk crowned with a globe, in festive light.", { { "Structure", { kind = "obelisk", count = 4, scale = 1.6, height = 0, color = GOLD } }, { "Hologram", { shape = "globe", scale = 1.6, height = 60, color = GOLD } }, { "LightingTheme", { theme = "festive" } } })
add("s_grand_opening", "Grand Opening", D, 4, "Finale fireworks, petals and a banner.", { { "Fireworks", { pattern = "finale", interval = 1.2, size = 1.6, color = GOLD } }, { "Confetti", { shape = "petals", rate = 30, color = PINK } }, { "Banner", { text = "Grand opening", style = "gold" } } })
add("s_server_celebration", "Server-wide Celebration", D, 2, "A banner, confetti and a soft aura for all.", { { "Banner", { text = "Everyone is invited to celebrate", style = "plain" } }, { "Confetti", { shape = "squares", rate = 25, color = GOLD } }, { "Aura", { style = "glow", size = 0.9, color = GOLD } } })
add("s_legendary_arrival", "Legendary Arrival", D, 4, "A shockwave, a gold title and willow fireworks.", { { "Arrival", { style = "shockwave", color = GOLD } }, { "Aura", { style = "energy", size = 1.6, color = GOLD } }, { "Title", { text = "Legend", style = "gold", color = GOLD } }, { "Fireworks", { pattern = "willow", interval = 2, size = 1.4, color = GOLD } } })
add("s_heart_fireworks", "Heart Fireworks", D, 3, "Heart-shaped bursts.", { { "Fireworks", { pattern = "heart", interval = 2, size = 1.3, color = PINK } } })
add("s_crossette", "Crossette Barrage", D, 3, "Splitting crossette bursts.", { { "Fireworks", { pattern = "crossette", interval = 0.8, size = 1.1, color = AMBER } } })

-- E. Owner exclusive powers (the owner only; every one of these refuses anyone else) ----------
local O = "Owner"
add("o_god_mode", "OWNER GOD MODE", O, 4, "Flight and immunity with an energy aura and a crown.", { { "OwnerShowcase", { fly = true, immune = true, crown = true } }, { "Aura", { style = "energy", size = 1.8, color = GOLD, ownerOnly = true } }, { "Halo", { style = "crown", color = GOLD } } })
add("o_supreme_authority", "SUPREME AUTHORITY", O, 4, "A royal title and a giant crown hologram.", { { "OwnerShowcase", { fly = false, immune = false, crown = true } }, { "Title", { text = "Supreme Authority", style = "royal", color = GOLD } }, { "Hologram", { shape = "crown", scale = 2.6, height = 55, color = GOLD } } })
add("o_world_creator", "WORLD CREATOR", O, 4, "Islands rise in a celestial sky as the owner steps through a portal.", { { "Structure", { kind = "islands", count = 10, scale = 1.5, height = 50, color = { 140, 240, 200 } } }, { "SkyTheme", { sky = "celestial" } }, { "LightingTheme", { theme = "cosmic", intensity = 1.1 } }, { "Arrival", { style = "portal", color = VIOLET } } })
add("o_reality_manipulator", "REALITY MANIPULATOR", O, 4, "Data rain, neon haze and weakened gravity.", { { "Gravity", { scale = 0.3 } }, { "Atmosphere", { mood = "neon_haze", density = 0.5 } }, { "Weather", { kind = "data", rate = 60, wind = 0, size = 0.6, color = { 80, 255, 160 } } } })
add("o_global_transformation", "GLOBAL TRANSFORMATION", O, 4, "Neon light, a total eclipse and sparkles.", { { "LightingTheme", { theme = "neon", intensity = 1.3 } }, { "SkyTheme", { sky = "eclipse" } }, { "Weather", { kind = "sparkles", rate = 40, wind = 0, size = 0.3, color = VIOLET } } }, { onConflict = "replace" })
add("o_cosmic_ascension", "COSMIC ASCENSION", O, 4, "A pillar of light, cosmic aura and orbiting rings.", { { "SkyTheme", { sky = "cosmic" } }, { "Aura", { style = "cosmic", size = 2, color = VIOLET, ownerOnly = true } }, { "Arrival", { style = "light_pillar", color = VIOLET } }, { "Halo", { style = "orbit_rings", color = VIOLET } } })
add("o_admin_overlord", "ADMIN OVERLORD", O, 4, "A neon title, static aura, emblem and alert banner.", { { "Title", { text = "Admin Overlord", style = "neon", color = RED }, }, { "Aura", { style = "static", size = 1.6, color = RED, ownerOnly = true } }, { "Hologram", { shape = "emblem", scale = 2.4, height = 50, color = RED } }, { "Banner", { text = "The Admin Overlord is here", style = "alert" } } })
add("o_infinite_energy", "INFINITE SHOWCASE ENERGY", O, 3, "Immunity, orbiting rings and an energy trail.", { { "OwnerShowcase", { fly = false, immune = true, crown = false } }, { "Aura", { style = "rings", size = 1.5, color = CYAN, ownerOnly = true } }, { "Trail", { style = "energy", length = 2, color = CYAN } } })
add("o_flight_master", "FLIGHT MASTER", O, 3, "Flight with a comet trail.", { { "OwnerShowcase", { fly = true, immune = false, crown = false } }, { "Trail", { style = "comet", length = 2.4, color = WHITE } } })
add("o_dimensional_travel", "DIMENSIONAL TRAVEL", O, 4, "A portal, a void haze and a great arch.", { { "Arrival", { style = "portal", color = VIOLET } }, { "Atmosphere", { mood = "void", density = 0.45 } }, { "Structure", { kind = "arch", count = 20, scale = 1.8, height = 4, color = VIOLET } } })
add("o_instant_summon", "INSTANT OWNER SUMMON", O, 3, "Lightning arrival and a banner.", { { "Arrival", { style = "lightning", color = WHITE } }, { "Banner", { text = "The owner has arrived", style = "gold" } } })
add("o_grand_entrance", "GRAND ENTRANCE", O, 4, "Golden gate, willow fireworks and star confetti.", { { "Arrival", { style = "golden_gate", color = GOLD } }, { "Fireworks", { pattern = "willow", interval = 1.5, size = 1.8, color = GOLD } }, { "Confetti", { shape = "stars", rate = 40, color = GOLD } } })
add("o_universal_aura", "UNIVERSAL AURA", O, 3, "Every participant shines with the owner's energy.", { { "Aura", { style = "energy", size = 1.3, color = CYAN } }, { "Halo", { style = "halo", color = CYAN } } })
add("o_owner_presence", "OWNER PRESENCE", O, 3, "A gold title and crown for the owner.", { { "OwnerShowcase", { fly = false, immune = false, crown = true } }, { "Title", { text = "AJKR", style = "gold", color = GOLD } }, { "Halo", { style = "crown", color = GOLD } } })
add("o_reality_reset", "REALITY RESET", O, 3, "A bright white reset of light, sky and air.", { { "LightingTheme", { theme = "sunburst", intensity = 1.5 } }, { "SkyTheme", { sky = "noon", clockTime = 12 } }, { "Atmosphere", { mood = "clear", density = 0.05 } } }, { onConflict = "replace" })
add("o_environment_override", "ENVIRONMENT OVERRIDE", O, 4, "Total darkness, void fog and falling ash.", { { "LightingTheme", { theme = "dark_facility", intensity = 0.6 } }, { "SkyTheme", { sky = "midnight", clockTime = 0 } }, { "Atmosphere", { mood = "void", density = 0.6 } }, { "Weather", { kind = "ash", rate = 50, wind = 4, size = 0.4, color = { 120, 120, 130 } } } }, { onConflict = "replace" })
add("o_global_event_control", "GLOBAL EVENT CONTROL", O, 3, "A globe, an orbit of lights and a status banner.", { { "Hologram", { shape = "globe", scale = 2.2, height = 50, color = CYAN } }, { "Structure", { kind = "orbit", count = 12, scale = 1.5, height = 30, color = CYAN } }, { "Banner", { text = "Global event control online", style = "plain" } } })
add("o_supreme_preview", "SUPREME POWER PREVIEW", O, 3, "Flame aura, a drone and a shockwave.", { { "Aura", { style = "flame", size = 1.7, color = AMBER, ownerOnly = true } }, { "Companion", { kind = "drone", color = AMBER } }, { "Arrival", { style = "shockwave", color = AMBER } } })
add("o_custom_world_effect", "CUSTOM WORLD EFFECT", O, 3, "Ember light, smoke and rising embers: a base to tint and tune.", { { "LightingTheme", { theme = "ember" } }, { "Atmosphere", { mood = "ember_smoke", density = 0.4 } }, { "Weather", { kind = "embers", rate = 45, wind = 5, size = 0.3, color = AMBER } } }, { onConflict = "replace" })
add("o_signature_spectacle", "OWNER SIGNATURE SPECTACLE", O, 4, "Finale fireworks, crown, pillars, light pillar and a royal title.", { { "Fireworks", { pattern = "finale", interval = 1, size = 2.2, color = GOLD } }, { "Hologram", { shape = "crown", scale = 3, height = 60, color = GOLD } }, { "Structure", { kind = "pillars", count = 14, scale = 1.8, height = 0, color = GOLD } }, { "Arrival", { style = "light_pillar", color = GOLD } }, { "Title", { text = "Overlord", style = "royal", color = GOLD } } })

-- Thanksgiving: a sophisticated autumn celebration inside the science facility ---------------
local T = "Thanksgiving"
local TT = { tags = { "thanksgiving", "autumn" }, excludes = { "winter" } }
local function tt(extra)
	local out = { tags = TT.tags, excludes = TT.excludes }
	for k, v in extra or {} do
		out[k] = v
	end
	return out
end
add("t_world_takeover", "Thanksgiving World Takeover", T, 4, "Amber light, a golden sky, falling leaves and the station dressed for Thanksgiving.", { { "LightingTheme", { theme = "autumn" } }, { "SkyTheme", { sky = "golden" } }, { "Weather", { kind = "leaves", rate = 35, wind = 4, size = 0.6, color = AMBER } }, { "Decor", { season = "Thanksgiving" } } }, tt({ onConflict = "replace" }))
add("t_golden_autumn_sky", "Golden Autumn Sky", T, 2, "A low golden sky and a dusty gold haze.", { { "SkyTheme", { sky = "golden", clockTime = 16.5 } }, { "Atmosphere", { mood = "dusty_gold", density = 0.35 } } }, tt())
add("t_massive_celebration", "Massive Thanksgiving Celebration", T, 4, "Peony fireworks, petals and a Thanksgiving banner.", { { "Fireworks", { pattern = "peony", interval = 2, size = 1.4, color = AMBER } }, { "Confetti", { shape = "petals", rate = 35, color = AMBER } }, { "Banner", { text = "Happy Thanksgiving from Meridian Station", style = "gold" } } }, tt())
add("t_falling_leaves", "Falling Autumn Leaves", T, 1, "Leaves drift down through the atrium.", { { "Weather", { kind = "leaves", rate = 30, wind = 2, size = 0.5, color = AMBER } } }, tt())
add("t_golden_leaf_storm", "Golden Leaf Storm", T, 3, "A gale of golden leaves in a dusty haze.", { { "Weather", { kind = "leaves", rate = 90, wind = 14, size = 0.8, color = GOLD } }, { "Atmosphere", { mood = "dusty_gold", density = 0.45 } } }, tt())
add("t_facility_decorations", "Thanksgiving Facility Decorations", T, 2, "The seasonal decoration set plus lanterns of amber light.", { { "Decor", { season = "Thanksgiving" } }, { "Structure", { kind = "lanterns", count = 14, scale = 1.1, height = 6, color = AMBER } } }, tt())
add("t_giant_tree", "Giant Thanksgiving Tree", T, 3, "A tiered tree of amber light in autumn light.", { { "Structure", { kind = "tree", count = 7, scale = 2, height = 0, color = AMBER } }, { "LightingTheme", { theme = "autumn" } } }, tt())
add("t_autumn_aura", "Autumn Energy Aura", T, 2, "An amber energy aura with particle trails.", { { "Aura", { style = "energy", size = 1.2, color = AMBER } }, { "Trail", { style = "particles", length = 1, color = AMBER } } }, tt())
add("t_pumpkin_displays", "Golden Pumpkin Displays", T, 2, "Glowing pumpkins ringed around the lobby in ember light.", { { "Structure", { kind = "pumpkins", count = 12, scale = 1.3, height = 0, color = AMBER } }, { "LightingTheme", { theme = "ember", intensity = 0.8 } } }, tt())
add("t_hologram", "Thanksgiving Hologram", T, 2, "A giant golden leaf hologram.", { { "Hologram", { shape = "leaf", scale = 2.2, height = 45, color = GOLD } } }, tt())
add("t_harvest_celebration", "Harvest Celebration", T, 3, "Petal confetti, seasonal decor and a banner.", { { "Confetti", { shape = "petals", rate = 25, color = AMBER } }, { "Decor", { season = "Thanksgiving" } }, { "Banner", { text = "Harvest celebration in the atrium", style = "plain" } } }, tt())
add("t_autumn_gravity", "Autumn Gravity Event", T, 3, "Leaves float down slowly as gravity eases in event mode.", { { "Gravity", { scale = 0.5 } }, { "Weather", { kind = "leaves", rate = 20, wind = 0, size = 0.7, color = AMBER } } }, tt())
add("t_confetti", "Thanksgiving Confetti", T, 2, "Golden star confetti.", { { "Confetti", { shape = "stars", rate = 30, color = GOLD } } }, tt())
add("t_golden_lighting", "Golden Atmospheric Lighting", T, 1, "Golden light across the station.", { { "LightingTheme", { theme = "golden", intensity = 1.1 } } }, tt())
add("t_spawn_animation", "Thanksgiving Spawn Animation", T, 2, "Players arrive through a golden gate.", { { "Arrival", { style = "golden_gate", color = AMBER } } }, tt())
add("t_harvest_arena", "Harvest Festival Arena", T, 3, "An arch of light, autumn light and quicker movement in event mode.", { { "Structure", { kind = "arch", count = 18, scale = 1.5, height = 4, color = AMBER } }, { "LightingTheme", { theme = "autumn", intensity = 1.3 } }, { "Speed", { multiplier = 1.3 } } }, tt())
add("t_floating_decorations", "Floating Autumn Decorations", T, 2, "Amber orbs float among slow leaves.", { { "Structure", { kind = "orbit", count = 10, scale = 1.2, height = 25, color = AMBER } }, { "Weather", { kind = "leaves", rate = 12, wind = 3, size = 0.5, color = AMBER } } }, tt())
add("t_warm_golden_world", "Warm Golden World", T, 2, "Autumn light with a warm glow.", { { "LightingTheme", { theme = "autumn", intensity = 0.9 } }, { "Atmosphere", { mood = "glow", density = 0.3 } } }, tt())
add("t_parade_showcase", "Thanksgiving Parade Showcase", T, 3, "Symbols overhead, leaf companions and a marshal title.", { { "Halo", { style = "symbols", color = AMBER } }, { "Companion", { kind = "leaf", color = AMBER } }, { "Title", { text = "Parade Marshal", style = "gold", color = AMBER } }, { "Confetti", { shape = "streamers", rate = 20, color = AMBER } } }, tt())
add("t_grand_harvest_finale", "Grand Harvest Finale", T, 4, "Finale fireworks, a tree of light, a star and a banner.", { { "Fireworks", { pattern = "finale", interval = 1.5, size = 1.7, color = GOLD } }, { "Structure", { kind = "tree", count = 9, scale = 2.4, height = 0, color = GOLD } }, { "Hologram", { shape = "star", scale = 2, height = 70, color = GOLD } }, { "Banner", { text = "The grand harvest finale", style = "gold" } } }, tt())

-- Christmas: a futuristic winter celebration --------------------------------------------------
local X = "Christmas"
local function xx(extra)
	local out = { tags = { "christmas", "winter" }, excludes = { "autumn" } }
	for k, v in extra or {} do
		out[k] = v
	end
	return out
end
add("x_global_takeover", "Global Christmas Takeover", X, 4, "Festive light, aurora sky, snowfall and the Christmas decoration set.", { { "LightingTheme", { theme = "festive" } }, { "SkyTheme", { sky = "aurora" } }, { "Weather", { kind = "snow", rate = 40, wind = 2, size = 0.3, color = WHITE } }, { "Decor", { season = "Christmas" } } }, xx({ onConflict = "replace" }))
add("x_tree_installation", "Massive Christmas Tree Installation", X, 4, "A towering tiered tree of green light.", { { "Structure", { kind = "tree", count = 9, scale = 2.6, height = 0, color = GREEN } }, { "LightingTheme", { theme = "festive", intensity = 1.2 } } }, xx())
add("x_beautiful_snowfall", "Beautiful Snowfall", X, 1, "Calm snow through the atrium.", { { "Weather", { kind = "snow", rate = 45, wind = 1, size = 0.35, color = WHITE } } }, xx())
add("x_aurora_borealis", "Aurora Borealis", X, 3, "Aurora over an icy night.", { { "LightingTheme", { theme = "aurora", intensity = 1.2 } }, { "SkyTheme", { sky = "aurora", clockTime = 23 } }, { "Atmosphere", { mood = "icy", density = 0.3 } } }, xx())
add("x_frozen_facility", "Frozen Facility", X, 3, "Ice spires, frost light and icy air.", { { "LightingTheme", { theme = "frost" } }, { "Structure", { kind = "ice", count = 12, scale = 1.4, height = 0, color = ICE } }, { "Atmosphere", { mood = "icy", density = 0.4 } } }, xx())
add("x_lights_everywhere", "Christmas Lights Everywhere", X, 2, "Strings of lanterns in warm festive light.", { { "Structure", { kind = "lanterns", count = 24, scale = 1.2, height = 5, color = { 255, 90, 90 } } }, { "LightingTheme", { theme = "festive", intensity = 0.9 } } }, xx())
add("x_holiday_sky", "Holiday Sky Transformation", X, 2, "A celestial sky with light snow.", { { "SkyTheme", { sky = "celestial", clockTime = 20 } }, { "Weather", { kind = "snow", rate = 20, wind = 0, size = 0.25, color = WHITE } } }, xx())
add("x_holo_snowflakes", "Giant Holographic Snowflakes", X, 3, "A snowflake hologram over a standing snowflake lattice.", { { "Hologram", { shape = "snowflake", scale = 2.4, height = 55, color = ICE } }, { "Structure", { kind = "snowflake", count = 6, scale = 1.2, height = 30, color = ICE } } }, xx())
add("x_celebration", "Christmas Celebration", X, 3, "Star bursts, star confetti and a Merry Christmas banner.", { { "Fireworks", { pattern = "star", interval = 2, size = 1.3, color = RED } }, { "Confetti", { shape = "stars", rate = 30, color = GREEN } }, { "Banner", { text = "Merry Christmas from Meridian Station", style = "frost" } } }, xx())
add("x_winter_wonderland", "Winter Wonderland", X, 4, "Frost light, icy air, snow and ice spires together.", { { "LightingTheme", { theme = "frost", intensity = 1.2 } }, { "Atmosphere", { mood = "icy", density = 0.35 } }, { "Weather", { kind = "snow", rate = 50, wind = 2, size = 0.3, color = WHITE } }, { "Structure", { kind = "ice", count = 8, scale = 1.2, height = 0, color = ICE } } }, xx())
add("x_festive_auras", "Festive Energy Auras", X, 2, "Festive auras with ribbon trails.", { { "Aura", { style = "festive", size = 1.2, color = RED } }, { "Trail", { style = "ribbon", length = 1.3, color = GREEN } } }, xx())
add("x_santa_entrance", "Santa Entrance Showcase", X, 3, "A golden gate, a lantern companion and a title.", { { "Arrival", { style = "golden_gate", color = RED } }, { "Companion", { kind = "lantern", color = RED } }, { "Title", { text = "Santa Showcase", style = "gold", color = RED } } }, xx())
add("x_holiday_parade", "Holiday Parade", X, 3, "Antlers, snowflake companions and streamers.", { { "Halo", { style = "antlers", color = { 200, 150, 90 } } }, { "Companion", { kind = "snowflake", color = ICE } }, { "Confetti", { shape = "streamers", rate = 25, color = RED } }, { "Title", { text = "Parade Marshal", style = "frost", color = ICE } } }, xx())
add("x_fireworks", "Christmas Fireworks", X, 3, "Crossette fireworks in frost light.", { { "Fireworks", { pattern = "crossette", interval = 1.5, size = 1.4, color = GREEN } }, { "LightingTheme", { theme = "frost", intensity = 0.8 } } }, xx())
add("x_glowing_ice", "Glowing Ice Structures", X, 2, "Ice and glass spires glowing in cold light.", { { "Structure", { kind = "ice", count = 14, scale = 1.5, height = 0, color = CYAN } }, { "Structure", { kind = "spires", count = 8, scale = 1.2, height = 0, color = ICE } } }, xx())
add("x_snowstorm", "Snowstorm Event", X, 3, "Heavy wind-driven snow in thick fog and grey light.", { { "Weather", { kind = "snow", rate = 100, wind = 18, size = 0.4, color = WHITE } }, { "Atmosphere", { mood = "dense_fog", density = 0.6 } }, { "LightingTheme", { theme = "mono", intensity = 0.8 } } }, xx())
add("x_festive_characters", "Festive Character Effects", X, 2, "A frost title, antlers and a festive aura.", { { "Title", { text = "Festive Fighter", style = "frost", color = ICE } }, { "Halo", { style = "antlers", color = { 200, 150, 90 } } }, { "Aura", { style = "festive", size = 1, color = GREEN } } }, xx())
add("x_giant_decorations", "Giant Holiday Decorations", X, 4, "Great orbs and a ring of lights with the Christmas decoration set.", { { "Structure", { kind = "orbit", count = 16, scale = 2.4, height = 40, color = RED } }, { "Structure", { kind = "ring", count = 40, scale = 1.8, height = 18, color = GREEN } }, { "Decor", { season = "Christmas" } } }, xx())
add("x_grand_finale", "Grand Christmas Finale", X, 4, "Finale fireworks, a tree of light, a tree hologram, snow and a banner.", { { "Fireworks", { pattern = "finale", interval = 1.2, size = 1.8, color = RED } }, { "Hologram", { shape = "tree", scale = 2.4, height = 65, color = GREEN } }, { "Structure", { kind = "tree", count = 8, scale = 2.2, height = 0, color = GOLD } }, { "Weather", { kind = "snow", rate = 35, wind = 1, size = 0.3, color = WHITE } }, { "Banner", { text = "The grand Christmas finale", style = "frost" } } }, xx())
add("x_winter_gravity", "Winter Gravity Event", X, 3, "Snowflakes float down as gravity eases in event mode.", { { "Gravity", { scale = 0.6 } }, { "Weather", { kind = "snow", rate = 20, wind = 0, size = 0.5, color = WHITE } } }, xx())

EventPresets.List = list
EventPresets.ById = {}
for _, preset in list do
	EventPresets.ById[preset.id] = preset
end

return EventPresets
