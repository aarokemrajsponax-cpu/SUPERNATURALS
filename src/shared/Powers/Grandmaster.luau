-- THE GRANDMASTER: a master of kung fu whose body is the weapon. Fast, light
-- strings, perfect-timing counters, evasive footwork and short cinematic
-- finishers. Four degrees (Disciple, Adept, Grandmaster, Ascendant Dragon) of
-- the same fighter: each adds techniques and upgrades the old ones.
--
-- Same ability fields as StrongDude.luau. Extra fields this power reads:
--   degreeCount                   this power has four degrees (the framework default is three)
--   resource.gainOnDefense        Chi for a successful defense (parry, counter, perfect step)
--   meters                        Focus (Degree III+) and Perfect Form (Degree IV) tuning
--   ironFist                      extra numbers for the basic chain (Twin Dragon Fists' second
--                                 impact, the dodge-to-counter palm, finisher hit-stop)
--   whiffRecovery                 extra recovery when a committed technique hits nothing
--   beats                         the timed impacts of a sequence (Hundred Fists, the ultimate)
--   cosmetic                      the optional Celestial Dragon Style pass (looks only)

local rgb = Color3.fromRGB

return {
	id = "Grandmaster",
	name = "The Grandmaster",
	icon = "🐉",
	tagline = "Master kung fu",
	description = "A martial arts master. Quick strings, perfect counters and footwork that slips past attacks. Every big technique has a tell you can read and punish.",
	style = "Duelist · close range",
	difficulty = 4,
	degreeCount = 4,
	-- Jade and golden-white energy over a plain ink-and-linen fighter
	colors = { primary = rgb(86, 186, 148), secondary = rgb(44, 54, 52), accent = rgb(250, 232, 186) },

	resource = {
		id = "Chi",
		name = "Chi",
		max = 100,
		start = 60,
		-- Per second
		regen = 6,
		gainOnHit = 3,
		gainOnHurt = 0,
		gainOnDefense = 8,
		color = rgb(110, 205, 165),
	},

	-- Degree III's Focus and Degree IV's Perfect Form (both 0 to 100)
	meters = {
		Focus = {
			minDegree = 3,
			max = 100,
			onLight = 4,
			onAbility = 6,
			onDefense = 20,
			-- Seconds without a landed hit or a defense before it fades, and how fast
			idleAfter = 4,
			decay = 4,
		},
		PerfectForm = {
			minDegree = 4,
			max = 100,
			-- Landed hits only build it while the streak holds (no whiff, no damage taken)
			onHit = 5,
			onDefense = 15,
			onDamaged = -22,
			onWhiff = -18,
			-- Losing momentum: no hit or defense for this long drains it
			idleAfter = 3.5,
			decay = 9,
			-- At full meter techniques deal this much more damage (scales from 0)
			damageBonus = 0.12,
			-- Extra ultimate charge per landed hit at full meter
			ultimateBonus = 0.6,
		},
	},

	-- The Iron Fist chain's extras (the steps themselves are stats.Light below)
	ironFist = {
		-- Twin Dragon Fists: the second fist lands this long after the first
		twinDelay = 0.09,
		twin = { damage = 3, hitstun = 0.45, knockback = 6, guardDamage = 6 },
		-- A perfect Dragon's Step opens a short window; the next landed hit adds this palm
		counterPalm = { damage = 6, hitstun = 0.55, knockback = 22, launch = 6, guardDamage = 15 },
		-- Freeze-frame on the Whirlwind Kick (client only)
		hitStop = 0.07,
	},

	-- Changes to Config/Combat for this power (every degree)
	stats = {
		MaxHealth = 100,
		Movement = { WalkSpeed = 17, AttackingSpeed = 8 },
		Light = {
			-- Quicker and lighter than the default chain; the kick ends it
			ChainWindow = 0.55,
			ChainCooldown = 0.6,
			Steps = {
				-- Opening Strike: a fast straight punch
				{ Damage = 4, Startup = 0.08, Active = 0.08, Recovery = 0.16, Range = 5.5, Arc = 90, Hitstun = 0.42, Knockback = 6, GuardDamage = 7 },
				-- Twin Dragon Fists: two alternating punches (the second lands through ironFist.twin)
				{ Damage = 3, Startup = 0.09, Active = 0.1, Recovery = 0.18, Range = 5.5, Arc = 90, Hitstun = 0.45, Knockback = 4, GuardDamage = 6 },
				-- Rising Palm: an upward palm that pops them off their feet
				{ Damage = 5, Startup = 0.11, Active = 0.1, Recovery = 0.22, Range = 5.5, Arc = 95, Hitstun = 0.6, Knockback = 4, Launch = 20, GuardDamage = 9 },
				-- Whirlwind Kick: a spinning kick that knocks them back and ends the chain
				{ Damage = 8, Startup = 0.15, Active = 0.12, Recovery = 0.42, Range = 6.5, Arc = 140, Hitstun = 0.7, Knockback = 62, Launch = 14, GuardDamage = 14, Finisher = true },
			},
		},
		-- Heavy: a rooted palm strike with a real wind-up
		Heavy = { Damage = 14, Startup = 0.42, Active = 0.12, Recovery = 0.4, Range = 6.5, Arc = 80, Hitstun = 0.85, Knockback = 70, Launch = 16, GuardDamage = 45, Cooldown = 2.5 },
	},

	degrees = {
		{
			name = "Disciple",
			description = "The fundamentals: the Iron Fist chain, Dragon's Step and Tiger Claw. Clean, fast and close.",
			slots = 2,
			default = { "DragonsStep", "TigerClaw" },
			ultimate = "HeavenSplittingDragon",
			unlock = nil,
		},
		{
			name = "Adept",
			description = "Defensive timing: Crane's Reversal and Iron Mountain, smoother strings and a longer opening after a perfect step.",
			slots = 4,
			default = { "DragonsStep", "TigerClaw", "CranesReversal", "IronMountain" },
			ultimate = "HeavenSplittingDragon",
			unlock = { mastery = 3, money = 1500 },
		},
		{
			name = "Grandmaster",
			description = "Sweeping Dragon, Hundred Fists and the Focus meter. Build it with clean hits and good defense, then spend it.",
			slots = 5,
			default = { "DragonsStep", "TigerClaw", "CranesReversal", "SweepingDragon", "HundredFists" },
			ultimate = "HeavenSplittingDragon",
			unlock = { mastery = 8, money = 6000 },
			stats = { MaxHealth = 105 },
		},
		{
			name = "Ascendant Dragon",
			description = "Enhanced techniques, Dragon's Answer after a perfect read, the Perfect Form meter and the full Heaven-Splitting Dragon.",
			slots = 6,
			-- Dragon's Answer sits on a numbered key; slot 6 is tap-only until a sixth key binding exists
			default = { "DragonsStep", "TigerClaw", "CranesReversal", "DragonsAnswer", "HundredFists", "SweepingDragon" },
			ultimate = "HeavenSplittingDragon",
			unlock = { mastery = 14, money = 15000 },
			stats = { MaxHealth = 110 },
		},
	},

	abilityOrder = { "DragonsStep", "TigerClaw", "CranesReversal", "IronMountain", "SweepingDragon", "HundredFists", "FocusState", "DragonsAnswer", "HeavenSplittingDragon" },

	abilities = {
		DragonsStep = {
			name = "Dragon's Step",
			icon = "💨",
			description = "A short burst that slips through attacks. Step through a hit at the right moment and your next strike adds a counter palm.",
			kind = "Dash",
			minDegree = 1,
			cooldown = 3.5,
			cost = 12,
			startup = 0.04,
			active = 0.2,
			recovery = 0.18,
			moveSpeed = 0,
			speed = 60,
			-- Untouchable for this long from the start of the burst
			evade = 0.18,
			-- How long the opening lasts after a perfect step
			opening = 1.2,
			-- An attack within this range that is winding up or swinging counts as "near"
			readRange = 10,
			tags = {},
			degreeScaling = {
				[2] = { opening = 1.6 },
				[3] = { speed = 64 },
				[4] = { speed = 68, evade = 0.22, opening = 2 },
			},
			ai = { range = 12, use = "Escape" },
		},
		TigerClaw = {
			name = "Tiger Claw",
			icon = "🐯",
			description = "Two quick body strikes, then a telegraphed palm thrust that crushes guards. Block or dodge the thrust when it flashes.",
			kind = "Melee",
			minDegree = 1,
			cooldown = 7,
			cost = 18,
			startup = 0.14,
			active = 0.62,
			recovery = 0.38,
			whiffRecovery = 0.35,
			moveSpeed = 4,
			range = 6,
			arc = 80,
			strikeGap = 0.11,
			strike = { damage = 3, hitstun = 0.45, knockback = 3, guardDamage = 18 },
			-- The palm's tell after the second strike
			thrustTell = 0.32,
			damage = 10,
			hitstun = 0.7,
			knockback = 40,
			launch = 6,
			guardDamage = 45,
			tags = { "Melee" },
			defense = "Prompt",
			degreeScaling = {
				[2] = { damage = 11 },
				[3] = { damage = 12, guardDamage = 50 },
				[4] = { damage = 13, guardDamage = 60, knockback = 48 },
			},
			ai = { range = 5, use = "Engage" },
		},
		CranesReversal = {
			name = "Crane's Reversal",
			icon = "🪶",
			description = "A short counter stance. A strike that lands in it is redirected and answered. Grabs and unblockable moves go through, and a miss leaves you open.",
			kind = "Counter",
			minDegree = 2,
			cooldown = 9,
			cost = 15,
			startup = 0.03,
			active = 0.45,
			recovery = 0.22,
			-- Extra recovery when nothing struck the stance
			whiffRecovery = 0.5,
			moveSpeed = 0,
			counterRange = 8,
			-- The answer: a palm and a finishing strike
			first = { damage = 5, hitstun = 0.5, knockback = 4, guardDamage = 0 },
			damage = 9,
			hitstun = 0.7,
			knockback = 55,
			launch = 14,
			-- The attacker is caught off balance this long
			stagger = 0.45,
			tags = {},
			degreeScaling = {
				[3] = { active = 0.5, damage = 10 },
				[4] = { active = 0.55, damage = 12, knockback = 65 },
			},
			ai = { range = 6, use = "Defend" },
		},
		IronMountain = {
			name = "Iron Mountain",
			icon = "⛰️",
			description = "A readable wind-up, a shoulder check, then a heavy palm that sends them flying. You can't turn once it starts and a miss is punishable.",
			kind = "Melee",
			minDegree = 2,
			cooldown = 9,
			cost = 24,
			startup = 0.42,
			active = 0.36,
			recovery = 0.45,
			whiffRecovery = 0.65,
			moveSpeed = 0,
			-- Committed: no turning once it starts
			autoRotate = false,
			armor = 1,
			lunge = 32,
			range = 6,
			arc = 70,
			shoulder = { damage = 6, hitstun = 0.5, knockback = 0, guardDamage = 30 },
			palmDelay = 0.18,
			damage = 14,
			hitstun = 0.85,
			knockback = 85,
			launch = 20,
			guardDamage = 55,
			tags = { "Melee", "Heavy" },
			defense = "Prompt",
			degreeScaling = {
				[3] = { damage = 15 },
				[4] = { damage = 17, knockback = 100, guardDamage = 65 },
			},
			ai = { range = 6, use = "Engage" },
		},
		SweepingDragon = {
			name = "Sweeping Dragon",
			icon = "🌀",
			description = "A low spinning sweep that knocks down everyone close. Jump over it or dodge. A fighter it floors can't be swept again for a few seconds.",
			kind = "Area",
			minDegree = 3,
			cooldown = 10,
			cost = 22,
			startup = 0.3,
			active = 0.14,
			recovery = 0.42,
			moveSpeed = 0,
			radius = 8,
			-- Fighters this high off the ground jump clear of it
			jumpClearance = 2.6,
			damage = 8,
			-- The knockdown (a long stun on the floor) and the immunity after it
			hitstun = 0.95,
			knockback = 14,
			launch = 4,
			guardDamage = 25,
			knockdownImmunity = 4,
			-- Without the knockdown (immune targets): a short stagger
			immuneHitstun = 0.3,
			tags = { "Area" },
			defense = "Prompt",
			degreeScaling = {
				[4] = { radius = 10, damage = 10 },
			},
			ai = { range = 7, use = "Defend" },
		},
		HundredFists = {
			name = "Hundred Fists",
			icon = "👊",
			description = "Needs a clean opening jab. If it lands, a rapid flurry ends in a launching palm. Hitting him before the jab connects stops it.",
			kind = "Melee",
			minDegree = 3,
			cooldown = 14,
			cost = 32,
			startup = 0.2,
			active = 0.95,
			recovery = 0.5,
			whiffRecovery = 0.55,
			moveSpeed = 0,
			range = 6,
			arc = 70,
			opener = { damage = 4, hitstun = 0.5, knockback = 0, guardDamage = 10 },
			-- Each beat: seconds after the jab, and its numbers
			beats = {
				{ at = 0.14, damage = 2, hitstun = 0.35, strike = "Punch" },
				{ at = 0.26, damage = 2, hitstun = 0.35, strike = "Elbow" },
				{ at = 0.38, damage = 2, hitstun = 0.35, strike = "Punch" },
				{ at = 0.5, damage = 2, hitstun = 0.35, strike = "Palm" },
			},
			finishAt = 0.68,
			damage = 9,
			hitstun = 0.8,
			knockback = 80,
			launch = 26,
			guardDamage = 30,
			tags = { "Melee" },
			degreeScaling = {
				[4] = {
					beats = {
						{ at = 0.12, damage = 2.5, hitstun = 0.35, strike = "Punch" },
						{ at = 0.23, damage = 2.5, hitstun = 0.35, strike = "Elbow" },
						{ at = 0.34, damage = 2.5, hitstun = 0.35, strike = "Punch" },
						{ at = 0.45, damage = 2.5, hitstun = 0.35, strike = "Palm" },
					},
					finishAt = 0.6,
					damage = 11,
				},
			},
			ai = { range = 5, use = "Engage" },
		},
		FocusState = {
			name = "Focus State",
			icon = "☯️",
			description = "Stillness Before the Storm. Spend a full Focus meter for quicker string recovery and sharper strikes for a few seconds. No damage resistance.",
			kind = "Buff",
			minDegree = 3,
			cooldown = 16,
			cost = 10,
			-- Focus needed (and spent)
			focusCost = 60,
			startup = 0.35,
			active = 0.05,
			recovery = 0.2,
			moveSpeed = 0,
			duration = 5,
			-- Light chain recovery and chain cooldown are multiplied by this while focused
			lightRecovery = 0.75,
			chainWindowBonus = 0.15,
			-- Chi regen multiplier while focused
			regenBoost = 1.5,
			tags = {},
			degreeScaling = {
				[4] = { duration = 6 },
			},
			ai = { range = 10, use = "Engage" },
		},
		DragonsAnswer = {
			name = "Dragon's Answer",
			icon = "🐲",
			description = "Only after a successful Crane's Reversal or a perfect Dragon's Step: close in and strike with a jade palm. Blockable.",
			kind = "Melee",
			minDegree = 4,
			cooldown = 6,
			cost = 14,
			startup = 0.1,
			active = 0.16,
			recovery = 0.32,
			moveSpeed = 0,
			-- How long after the read it can be used
			window = 2,
			reach = 12,
			lunge = 70,
			range = 6,
			arc = 90,
			damage = 16,
			hitstun = 0.85,
			knockback = 75,
			launch = 30,
			guardDamage = 60,
			tags = { "Melee", "Heavy" },
			ai = { range = 8, use = "Finisher" },
		},
		HeavenSplittingDragon = {
			name = "Heaven-Splitting Dragon",
			icon = "🐉",
			description = "ULTIMATE. A focused stance, then an opening strike. If it lands, a short flurry ends in a dragon palm. Dodge or block the opener to avoid it all.",
			kind = "Ultimate",
			minDegree = 1,
			cooldown = 2,
			-- The stance and the opening strike's tell
			startup = 0.5,
			active = 1.1,
			recovery = 0.6,
			moveSpeed = 0,
			armor = 0,
			range = 7,
			arc = 70,
			-- Charge given back when the opener is dodged or blocked
			whiffRefund = 0.25,
			-- Nobody can be hit by this ultimate again for this long
			repeatImmunity = 8,
			opener = { damage = 6, hitstun = 0.6, knockback = 0, guardDamage = 30 },
			beats = {
				{ at = 0.16, damage = 4, hitstun = 0.4, strike = "Punch" },
				{ at = 0.32, damage = 4, hitstun = 0.4, strike = "Knee" },
				{ at = 0.48, damage = 4, hitstun = 0.4, strike = "Kick" },
			},
			finishAt = 0.7,
			-- Presentation: the full cinematic (Degree IV only)
			cinematic = false,
			damage = 14,
			hitstun = 1.0,
			knockback = 110,
			launch = 42,
			guardDamage = 60,
			tags = { "Melee", "Heavy" },
			defense = "Prompt",
			degreeScaling = {
				[2] = { damage = 16, opener = { damage = 7, hitstun = 0.6, knockback = 0, guardDamage = 30 } },
				[3] = { damage = 18 },
				[4] = {
					startup = 0.55,
					active = 1.45,
					cinematic = true,
					beats = {
						{ at = 0.14, damage = 3.5, hitstun = 0.4, strike = "Punch" },
						{ at = 0.28, damage = 3.5, hitstun = 0.4, strike = "Elbow" },
						{ at = 0.42, damage = 3.5, hitstun = 0.4, strike = "Knee" },
						{ at = 0.58, damage = 4, hitstun = 0.45, strike = "Kick" },
						{ at = 0.76, damage = 4, hitstun = 0.45, strike = "Spin" },
					},
					finishAt = 1.0,
					damage = 20,
					knockback = 130,
					launch = 50,
				},
			},
			ai = { range = 6, use = "Finisher" },
		},
	},

	-- Optional premium cosmetics (game pass in Config/Monetization). Changes looks only.
	cosmetic = {
		pass = "CelestialDragonStyle",
		name = "Celestial Dragon Style",
		benefit = "Cosmetic only: a celestial stance and victory pose, star-silver impacts, extra aura colours and a dragon-themed ultimate. No stat changes.",
		colors = { primary = rgb(132, 168, 228), secondary = rgb(38, 44, 66), accent = rgb(236, 206, 132) },
	},

	ai = { preferredRange = 5, aggression = 0.7 },
}
