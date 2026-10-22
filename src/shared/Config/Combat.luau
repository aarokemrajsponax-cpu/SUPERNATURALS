-- Combat balance. Every number that tunes how a fight feels lives here,
-- so balancing never means hunting through scripts.
-- Times are in seconds, distances in studs, angles in degrees.

local Combat = {}

Combat.MaxHealth = 100
Combat.RespawnTime = 3
-- Protection after respawning inside a match, so nobody gets spawn-camped
Combat.SpawnProtection = 1.5
-- A hit this recent earns the knockout, even if the victim then falls out of the arena
Combat.KnockoutCreditWindow = 8

-- Combo limits: after this many hits in a row, hits stop stunning so the victim can escape
Combat.MaxComboHits = 7
-- Time without being hit before the combo counter resets
Combat.ComboResetTime = 1.2

-- How far above or below the attacker a target can be and still get hit
Combat.VerticalReach = 5
-- Rough body radius added to every attack's range
Combat.TargetRadius = 1.5
-- Anything this close is hit regardless of facing (stops point-blank whiffs)
Combat.PointBlankRange = 2.5

Combat.Movement = {
	WalkSpeed = 16,
	JumpHeight = 7.2,
	AttackingSpeed = 7,
	BlockingSpeed = 6,
}

-- Every attack can also set:
--   Blockable = false   (goes through blocks)
--   Parryable = false   (can't be parried)
--   Cost = n            (resource it uses; powers add resources in Milestone 2)
-- Unset means blockable, parryable and free.

-- Requests arriving this close to the end of a swing are queued instead of dropped
Combat.InputBuffer = 0.15

Combat.Light = {
	-- Time after a swing finishes to continue the chain
	ChainWindow = 0.6,
	-- Rest after the final hit of the chain
	ChainCooldown = 0.7,
	Steps = {
		{ Damage = 5, Startup = 0.1, Active = 0.1, Recovery = 0.2, Range = 5.5, Arc = 100, Hitstun = 0.5, Knockback = 8, GuardDamage = 8 },
		{ Damage = 5, Startup = 0.1, Active = 0.1, Recovery = 0.2, Range = 5.5, Arc = 100, Hitstun = 0.5, Knockback = 8, GuardDamage = 8 },
		{ Damage = 6, Startup = 0.12, Active = 0.1, Recovery = 0.22, Range = 5.5, Arc = 100, Hitstun = 0.55, Knockback = 10, GuardDamage = 10 },
		-- The finisher launches, which ends the string
		{ Damage = 9, Startup = 0.16, Active = 0.12, Recovery = 0.45, Range = 6, Arc = 110, Hitstun = 0.7, Knockback = 55, Launch = 20, GuardDamage = 15, Finisher = true },
	},
}

-- Heavy attacks are rewarding when they land and punishable when they miss
Combat.Heavy = {
	Damage = 16,
	Startup = 0.5,
	Active = 0.14,
	Recovery = 0.4,
	-- Recovery used instead when the heavy hits nothing
	WhiffRecovery = 1.0,
	Range = 7,
	Arc = 90,
	Hitstun = 0.9,
	Knockback = 75,
	Launch = 24,
	GuardDamage = 55,
	Cooldown = 2.5,
	Finisher = true,
}

Combat.Block = {
	-- Share of damage that still gets through a block (chip damage never knocks out)
	DamageMultiplier = 0.15,
	-- Blocks only stop attacks coming from in front
	FrontArc = 140,
	MaxGuard = 100,
	GuardRegenDelay = 1.5,
	GuardRegenRate = 25,
	GuardBreakStun = 1.4,
	-- Guard restored after a guard break
	GuardAfterBreak = 50,
	-- Push-back when a hit is blocked, as a share of the attack's knockback
	PushbackMultiplier = 0.35,
	-- Raising your block this close before a hit lands is a parry
	ParryWindow = 0.2,
	-- Extra parry leeway for network delay
	LatencyAllowance = 0.1,
	-- How long a parried attacker is left open
	ParryStun = 1.0,
	-- Minimum time between releasing block and raising it again (stops parry spam)
	Cooldown = 0.35,
}

Combat.Dodge = {
	Speed = 70,
	Duration = 0.18,
	-- Invulnerable for this long from the start of the dodge
	Invulnerable = 0.22,
	Recovery = 0.1,
	Cooldown = 1.5,
}

-- How long knockback pushes for before gravity and friction take over
Combat.KnockbackDuration = 0.18

-- Share of damage and knockback a fighter actually takes (powers and degrees change these)
Combat.DamageTaken = 1
Combat.KnockbackTaken = 1

-- Abilities ------------------------------------------------------------------------

Combat.Abilities = {
	-- Walk speed while using an ability that doesn't set its own
	MoveSpeed = 4,
	-- A request this much early is still accepted (network delay)
	CooldownLeeway = 0.08,
	-- Most an aimed ability can reach past its own range when clamping a target point
	AimSlack = 4,
}

-- Ultimate charge: fills from fighting; the ultimate needs a full bar
Combat.Ultimate = {
	Max = 100,
	-- Charge per point of damage dealt and taken
	PerDamageDealt = 0.9,
	PerDamageTaken = 0.45,
	-- Slow passive charge per second while in a running match
	PassivePerSecond = 0.6,
	-- Training dummies charge it this much faster, so it can be practised
	TrainingMultiplier = 4,
}

-- Status effects: what each one does and the longest it can ever last, so
-- nothing can stun, slow or trap someone indefinitely
Combat.Statuses = {
	Slow = { max = 4, label = "Slowed", icon = "🐌" },
	Haste = { max = 6, label = "Hasted", icon = "💨" },
	Root = { max = 2.5, label = "Rooted", icon = "⛓️" },
	Freeze = { max = 2.5, label = "Frozen", icon = "🧊" },
	Mark = { max = 8, label = "Marked", icon = "🎯" },
	Burn = { max = 5, label = "Burning", icon = "🔥", tick = 0.5 },
	Shield = { max = 6, label = "Shielded", icon = "🛡️" },
	Armor = { max = 6, label = "Armored", icon = "🪨" },
	Concealed = { max = 4, label = "Concealed", icon = "👻" },
	Distort = { max = 4, label = "Distorted", icon = "🌀" },
	Trapped = { max = 3.5, label = "Trapped", icon = "🔒" },
	Vulnerable = { max = 4, label = "Exposed", icon = "💢" },
	Gravity = { max = 6, label = "Gravity", icon = "🪐" },
	Sealed = { max = 2, label = "Sealed", icon = "🚫" },
	Grabbed = { max = 3, label = "Grabbed", icon = "✊" },
	Transformed = { max = 30, label = "Transformed", icon = "🐾" },
	-- The Grandmaster: caught in Hundred Fists or the ultimate (nobody else's sequence can start on them)
	Sequenced = { max = 2.5, label = "Caught", icon = "🥋" },
	-- Knocked down by Sweeping Dragon recently: can't be knocked down by it again yet
	SureFooted = { max = 6, label = "Sure-footed", icon = "🦶" },
	-- Hit by Heaven-Splitting Dragon recently: no ultimate sequence can start on them
	UltimateGuard = { max = 10, label = "Recovering", icon = "✨" },
}

-- Interactive defense windows
Combat.Defense = {
	-- Dodge/block prompt: shown this long before a telegraphed attack lands
	PromptLead = 0.6,
	-- A block or dodge started inside the prompt window counts as a perfect defense
	PerfectStun = 0.5,
	-- Timing bar for massive attacks: how far from the centre (seconds) still counts
	PerfectWindow = 0.07,
	GoodWindow = 0.17,
	-- Good timing takes this share of the damage
	GoodDamage = 0.5,
	-- How long the attacker is left open after a perfect timing defense
	TimingPunish = 0.6,
	-- Grab escapes: presses faster than this apart don't count (stops macro spam)
	MashMinInterval = 1 / 14,
	-- After escaping a grab the grabber staggers for this long
	EscapeStun = 0.6,
	-- Most network delay we allow for when judging timing (seconds, one way)
	LatencyCap = 0.15,
	-- Syntax redirect: offered when an eligible projectile is this close
	RedirectRange = 22,
	RedirectWindow = 0.6,
}

Combat.Projectiles = {
	MaxPerFighter = 14,
	MaxTotal = 220,
	-- Every projectile is gone after this long, whatever it says
	MaxLifetime = 6,
	-- Redirected projectiles deal at most this much
	RedirectDamageCap = 18,
}

return Combat
