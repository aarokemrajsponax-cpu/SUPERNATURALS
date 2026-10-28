-- STRONG DUDE: supernatural strength. Heavy hits, grabs, throws and ground
-- shockwaves. Tough, but his big moves have readable wind-ups and recovery,
-- so opponents can dodge, bait and punish him.
--
-- Ability fields (every power file uses the same ones):
--   name, icon, description       what the selection screen shows
--   kind                          Melee | Area | Grab | Dash | Projectile | Throw | Counter
--                                 | Zone | Buff | Teleport | Form | Construct | Ultimate
--   minDegree                     first degree that can equip it
--   price                         { money = n } or { gems = n } to unlock (nil = free)
--   freeFrom                      included for free from this degree on (bought below it)
--   cooldown, cost                seconds, and how much of the power's resource it uses
--   startup, active, recovery     timing in seconds (like basic attacks)
--   moveSpeed                     walk speed while using it (0 = rooted)
--   armor                         hits it shrugs off during startup without flinching
--   damage, hitstun, knockback, launch, guardDamage, blockable, parryable
--   range, radius, arc, width, speed, lifetime   shape and reach
--   tags                          what counters and defenses can answer it:
--                                 Melee, Small, Heavy, Area, Grab, Projectile, Massive
--   defense                       the interactive defense victims get: Prompt | Timing | Mash
--   degreeScaling                 [2] / [3] = changes at Degree 2 and 3 (they stack)
--   ai                            { range = studs, use = "Engage" | "Poke" | "Escape" | "Defend" | "Finisher" }

local rgb = Color3.fromRGB

return {
	id = "StrongDude",
	name = "Strong Dude",
	icon = "💪",
	tagline = "Supernatural strength",
	description = "A super-strong brawler. Lift, throw, slam and smash. He can take a beating, but his big moves are slow and easy to read.",
	style = "Bruiser · close range",
	difficulty = 2,
	colors = { primary = rgb(255, 140, 50), secondary = rgb(120, 60, 30), accent = rgb(255, 220, 150) },

	resource = {
		id = "Grit",
		name = "Grit",
		max = 100,
		start = 40,
		-- Per second
		regen = 4,
		gainOnHit = 5,
		gainOnHurt = 4,
		color = rgb(255, 150, 60),
	},

	-- Changes to Config/Combat for this power (every degree)
	stats = {
		MaxHealth = 125,
		-- Share of knockback he actually feels
		KnockbackTaken = 0.85,
		Movement = { WalkSpeed = 15, AttackingSpeed = 6 },
		Light = {
			Steps = {
				{ Damage = 6, Startup = 0.13, Active = 0.1, Recovery = 0.22, Range = 5.5, Arc = 100, Hitstun = 0.5, Knockback = 10, GuardDamage = 10 },
				{ Damage = 6, Startup = 0.13, Active = 0.1, Recovery = 0.22, Range = 5.5, Arc = 100, Hitstun = 0.5, Knockback = 10, GuardDamage = 10 },
				{ Damage = 7, Startup = 0.15, Active = 0.1, Recovery = 0.25, Range = 5.5, Arc = 100, Hitstun = 0.55, Knockback = 12, GuardDamage = 12 },
				{ Damage = 11, Startup = 0.2, Active = 0.12, Recovery = 0.5, Range = 6, Arc = 110, Hitstun = 0.75, Knockback = 70, Launch = 24, GuardDamage = 20, Finisher = true },
			},
		},
		Heavy = { Damage = 20, Startup = 0.6, Knockback = 95, Launch = 28, GuardDamage = 70, Cooldown = 3 },
		Block = { DamageMultiplier = 0.1, MaxGuard = 140 },
	},

	degrees = {
		{
			name = "Powerful Strength",
			description = "Powerful punches, a sturdy guard, grabs, a stomp and throwing light objects.",
			slots = 3,
			default = { "Groundbreaker", "TitanGrip", "MeteorCharge" },
			ultimate = "WorldBreaker",
			unlock = nil,
		},
		{
			name = "Greater Strength",
			description = "Harder hits, stronger throws, heavier objects to lift, and resistance to being knocked around.",
			slots = 4,
			default = { "Groundbreaker", "TitanGrip", "MeteorCharge", "CrushingUppercut" },
			ultimate = "WorldBreaker",
			unlock = { mastery = 3, money = 1500 },
			stats = { KnockbackTaken = 0.7, MaxHealth = 130 },
		},
		{
			name = "Earthshaker",
			description = "The apex of strength: rip up arena debris, send shockwaves across the ground, hurl opponents and unleash World Breaker at full power.",
			slots = 5,
			default = { "Groundbreaker", "TitanGrip", "MeteorCharge", "CrushingUppercut", "SeismicFissure" },
			ultimate = "WorldBreaker",
			unlock = { mastery = 8, money = 6000 },
			stats = { KnockbackTaken = 0.6, MaxHealth = 135 },
		},
	},

	abilityOrder = { "Groundbreaker", "TitanGrip", "MeteorCharge", "CrushingUppercut", "QuakeStomp", "Heave", "IronBody", "SeismicFissure", "WorldBreaker" },

	abilities = {
		Groundbreaker = {
			name = "Groundbreaker",
			icon = "💥",
			description = "Slams the ground and sends a shockwave outward. Jump or dodge it.",
			kind = "Area",
			minDegree = 1,
			cooldown = 9,
			cost = 20,
			startup = 0.45,
			active = 0.1,
			recovery = 0.55,
			moveSpeed = 0,
			damage = 12,
			hitstun = 0.6,
			knockback = 45,
			launch = 30,
			guardDamage = 35,
			radius = 12,
			-- Fighters this high above the ground (jumping) are missed
			jumpClearance = 4,
			tags = { "Area", "Heavy" },
			defense = "Prompt",
			degreeScaling = {
				[2] = { damage = 15, radius = 14 },
				[3] = { damage = 18, radius = 18, knockback = 60 },
			},
			ai = { range = 10, use = "Engage" },
		},
		TitanGrip = {
			name = "Titan Grip",
			icon = "✊",
			description = "Grabs someone right in front of you and slams them. Beats blocking, but a dodge avoids it, and the victim can mash to break free.",
			kind = "Grab",
			minDegree = 1,
			cooldown = 10,
			cost = 25,
			startup = 0.25,
			active = 0.1,
			recovery = 0.45,
			moveSpeed = 0,
			range = 6,
			arc = 70,
			hold = 1.4,
			-- Button presses the victim needs during the hold to escape
			escapePresses = 6,
			damage = 14,
			hitstun = 0.8,
			knockback = 55,
			launch = 35,
			blockable = false,
			tags = { "Grab", "Melee" },
			defense = "Mash",
			degreeScaling = {
				[2] = { damage = 17, escapePresses = 7 },
				-- Earthshaker hurls them far (the arena walls still stop them)
				[3] = { damage = 20, escapePresses = 8, knockback = 130, launch = 45 },
			},
			ai = { range = 5, use = "Engage" },
		},
		MeteorCharge = {
			name = "Meteor Charge",
			icon = "☄️",
			description = "A committed charge forward that blasts away the first person it hits. Shrugs off one hit while charging, but a miss leaves you open.",
			kind = "Dash",
			minDegree = 1,
			cooldown = 8,
			cost = 20,
			startup = 0.2,
			active = 0.55,
			recovery = 0.35,
			-- Extra recovery when nothing was hit
			whiffRecovery = 0.6,
			moveSpeed = 0,
			armor = 1,
			speed = 55,
			width = 4,
			damage = 13,
			hitstun = 0.7,
			knockback = 90,
			launch = 25,
			guardDamage = 45,
			tags = { "Melee", "Heavy" },
			defense = "Prompt",
			degreeScaling = {
				[2] = { damage = 15, speed = 60 },
				[3] = { damage = 17, speed = 65, knockback = 110 },
			},
			ai = { range = 25, use = "Engage" },
		},
		CrushingUppercut = {
			name = "Crushing Uppercut",
			icon = "⬆️",
			description = "A heavy uppercut that launches the target into the air, ready for a follow-up.",
			kind = "Melee",
			minDegree = 1,
			price = { money = 600 },
			freeFrom = 2,
			cooldown = 7,
			cost = 15,
			startup = 0.3,
			active = 0.1,
			recovery = 0.4,
			moveSpeed = 4,
			range = 6,
			arc = 90,
			damage = 11,
			hitstun = 1.0,
			knockback = 8,
			launch = 55,
			guardDamage = 30,
			tags = { "Melee", "Heavy" },
			degreeScaling = {
				[2] = { damage = 13 },
				[3] = { damage = 15 },
			},
			ai = { range = 5, use = "Engage" },
		},
		QuakeStomp = {
			name = "Quake Stomp",
			icon = "🦶",
			description = "A quick stomp that staggers everyone right around you. Great for making space.",
			kind = "Area",
			minDegree = 1,
			price = { money = 400 },
			cooldown = 5,
			cost = 10,
			startup = 0.18,
			active = 0.08,
			recovery = 0.3,
			moveSpeed = 0,
			radius = 7,
			jumpClearance = 3,
			damage = 7,
			hitstun = 0.5,
			knockback = 30,
			launch = 10,
			guardDamage = 20,
			tags = { "Area", "Small" },
			degreeScaling = {
				[2] = { damage = 8, radius = 8 },
				[3] = { damage = 9, radius = 9 },
			},
			ai = { range = 6, use = "Defend" },
		},
		Heave = {
			name = "Heave",
			icon = "🪨",
			description = "Lifts the nearest throwable object and hurls it. Degree 1 lifts light objects, Degree 2 heavy ones, Earthshaker anything — or rips debris out of the ground.",
			kind = "Throw",
			minDegree = 1,
			price = { money = 800 },
			cooldown = 6,
			cost = 15,
			startup = 0.5,
			active = 0.05,
			recovery = 0.35,
			moveSpeed = 4,
			-- How far away an object can be picked up from
			reach = 10,
			-- Heaviest object class this degree can lift (1 light, 2 heavy, 3 enormous)
			maxWeight = 1,
			-- Can tear a rock out of the ground when nothing is nearby
			ripDebris = false,
			-- Per weight class: projectile damage, speed and size
			throws = {
				{ damage = 10, speed = 95, radius = 2, knockback = 40, launch = 15 },
				{ damage = 16, speed = 80, radius = 3, knockback = 70, launch = 25 },
				{ damage = 24, speed = 65, radius = 5, knockback = 100, launch = 35 },
			},
			range = 120,
			tags = { "Projectile" },
			degreeScaling = {
				[2] = { maxWeight = 2 },
				[3] = { maxWeight = 3, ripDebris = true },
			},
			ai = { range = 40, use = "Poke" },
		},
		IronBody = {
			name = "Iron Body",
			icon = "🛡️",
			description = "Brace for impact. Close-range hits during the stance only do half damage and don't flinch you — and the attacker gets grabbed and thrown.",
			kind = "Counter",
			minDegree = 2,
			price = { money = 1500 },
			cooldown = 12,
			cost = 20,
			startup = 0.05,
			active = 0.6,
			recovery = 0.3,
			moveSpeed = 0,
			-- Damage taken during the stance
			damageTaken = 0.5,
			counterRange = 7,
			damage = 12,
			hitstun = 0.8,
			knockback = 80,
			launch = 30,
			tags = {},
			ai = { range = 6, use = "Defend" },
		},
		SeismicFissure = {
			name = "Seismic Fissure",
			icon = "🌋",
			description = "Splits the ground in a straight line. The crack races forward and erupts under everyone in its path.",
			kind = "Area",
			minDegree = 3,
			cooldown = 12,
			cost = 30,
			startup = 0.5,
			active = 0.6,
			recovery = 0.5,
			moveSpeed = 0,
			range = 45,
			width = 6,
			-- How fast the crack travels
			speed = 75,
			damage = 16,
			hitstun = 0.8,
			knockback = 25,
			launch = 45,
			guardDamage = 40,
			jumpClearance = 4,
			tags = { "Area", "Heavy" },
			defense = "Prompt",
			ai = { range = 35, use = "Poke" },
		},
		WorldBreaker = {
			name = "World Breaker",
			icon = "🌍",
			description = "ULTIMATE. A long, glowing wind-up, then a punch so strong it shatters the arena floor in front of you. Perfectly timed defense negates it.",
			kind = "Ultimate",
			minDegree = 1,
			cooldown = 2,
			startup = 1.4,
			active = 0.15,
			recovery = 0.9,
			moveSpeed = 0,
			armor = 3,
			range = 22,
			arc = 70,
			damage = 30,
			hitstun = 1.2,
			knockback = 140,
			launch = 60,
			guardDamage = 200,
			blockable = false,
			tags = { "Massive", "Heavy" },
			defense = "Timing",
			degreeScaling = {
				[2] = { damage = 38, range = 24 },
				[3] = { damage = 45, range = 28, arc = 80 },
			},
			ai = { range = 14, use = "Finisher" },
		},
	},

	-- How CPU opponents play this power
	ai = { preferredRange = 6, aggression = 0.75 },
}
