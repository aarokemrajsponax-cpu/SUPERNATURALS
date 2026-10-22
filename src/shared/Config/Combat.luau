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
		{ Move = "Jab", Damage = 5, Startup = 0.1, Active = 0.1, Recovery = 0.2, Range = 5.5, Arc = 100, Hitstun = 0.5, Knockback = 8, GuardDamage = 8 },
		{ Move = "Cross", Damage = 5, Startup = 0.1, Active = 0.1, Recovery = 0.2, Range = 5.5, Arc = 100, Hitstun = 0.5, Knockback = 8, GuardDamage = 8 },
		{ Move = "Hook", Damage = 6, Startup = 0.12, Active = 0.1, Recovery = 0.22, Range = 5.5, Arc = 100, Hitstun = 0.55, Knockback = 10, GuardDamage = 10 },
		-- The finisher launches, which ends the string
		{ Move = "FinisherKick", Damage = 9, Startup = 0.16, Active = 0.12, Recovery = 0.45, Range = 6, Arc = 110, Hitstun = 0.7, Knockback = 55, Launch = 20, GuardDamage = 15, Finisher = true },
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
	Move = "Heavy",
	-- Hold Heavy to charge it (release to swing). Bonuses grow with the charge;
	-- a full charge breaks any guard and knocks down.
	Charge = {
		-- Held shorter than this is just a tap
		Min = 0.3,
		-- A full charge; it swings by itself here
		Max = 1.2,
		-- Extra damage and guard damage at full charge (shares of the heavy's own)
		DamageBonus = 0.75,
		GuardDamageBonus = 1.0,
		MoveSpeed = 5,
		-- Swing time left after letting go (the charge was the wind-up)
		ReleaseStartup = 0.18,
	},
}

-- Cancelling a heavy's wind-up or charge with Block: the mind game
Combat.Feint = {
	-- Can't act for this long after a feint
	Recovery = 0.25,
	-- Time before the next feint
	Cooldown = 1.2,
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
	-- Dodges cost stamina; this short gap only stops button mashing
	Cooldown = 0.4,
	-- Dodging this close before a hit would land is a perfect dodge...
	PerfectWindow = 0.12,
	-- ...which leaves the attacker open this much longer
	PerfectPunish = 0.5,
	-- By input relative to facing: sideways, backwards (or no input), forwards
	Directions = {
		Side = { Speed = 62, Duration = 0.18, Invulnerable = 0.22 },
		Back = { Speed = 66, Duration = 0.2, Invulnerable = 0.22 },
		-- Closes distance, but is invulnerable for less of it
		Forward = { Speed = 78, Duration = 0.18, Invulnerable = 0.1 },
	},
}

-- Stamina: dodges, sprinting and the other movement tricks spend it. At 0 the
-- fighter is winded (no dodging or sprinting, blocking costs more guard) until
-- it climbs back to WindedRecover.
Combat.Stamina = {
	Max = 100,
	-- Per second, once RegenDelay has passed since stamina was last spent
	Regen = 30,
	RegenDelay = 0.8,
	WindedRecover = 35,
	-- Guard damage taken while winded, as a multiple
	WindedGuardMultiplier = 1.5,
	Costs = {
		Dodge = 20,
		SprintPerSecond = 12,
		DodgeCancel = 18,
		Feint = 15,
		Charge = 10,
		TechRoll = 15,
		Breakfall = 20,
		Grab = 10,
	},
}

Combat.Sprint = {
	Speed = 25,
	-- Needed to start sprinting
	MinStamina = 15,
}

-- Light while sprinting (Rush Strike) and Heavy while sprinting (Shoulder Charge).
-- Lunge: forward speed during the wind-up and swing.
Combat.Running = {
	Light = { Move = "RushStrike", Damage = 8, Startup = 0.14, Active = 0.14, Recovery = 0.3, Range = 7.5, Arc = 90, Hitstun = 0.55, Knockback = 45, GuardDamage = 15, Lunge = 40 },
	Heavy = { Move = "ShoulderCharge", Damage = 12, Startup = 0.22, Active = 0.2, Recovery = 0.4, WhiffRecovery = 0.85, Range = 6.5, Arc = 100, Hitstun = 0.8, Knockback = 60, Launch = 10, GuardDamage = 60, Knockdown = true, Lunge = 55, Finisher = true },
}

-- Back + Heavy: an uppercut that launches for juggles
Combat.Launcher = { Move = "Launcher", Damage = 10, Startup = 0.28, Active = 0.12, Recovery = 0.4, WhiffRecovery = 0.8, Range = 5.5, Arc = 90, Hitstun = 0.9, Knockback = 6, Launch = 48, GuardDamage = 25 }

-- In the air: Light = Air Kick, Heavy = Slam (dives down; an overhead, so it
-- chews through guard). Launched fighters can be juggled JuggleLimit times, and
-- can breakfall (Dodge) once BreakfallAfter has passed.
Combat.Air = {
	Light = { Move = "AirKick", Damage = 6, Startup = 0.1, Active = 0.12, Recovery = 0.25, Range = 6, Arc = 110, Hitstun = 0.5, Knockback = 10, Launch = 10, GuardDamage = 10 },
	Heavy = { Move = "Slam", Damage = 13, Startup = 0.22, Active = 0.18, Recovery = 0.45, WhiffRecovery = 0.8, Range = 6.5, Arc = 120, Hitstun = 0.7, Knockback = 35, GuardDamage = 45, Overhead = true, Dive = 70, Finisher = true },
	JuggleLimit = 3,
	BreakfallAfter = 0.35,
	-- A launched fighter counts as airborne for at most this long
	MaxAirborne = 1.8,
}

-- Sweep: a low spin kick. Fast and short, knocks a standing opponent down;
-- jumping avoids it; blockable.
Combat.Sweep = { Move = "Sweep", Damage = 6, Startup = 0.16, Active = 0.12, Recovery = 0.35, WhiffRecovery = 0.6, Range = 5, Arc = 200, GuardDamage = 12, Hitstun = 0.4, Knockback = 10, Knockdown = true, Low = true, Cooldown = 1.0 }

-- Grab: beats block, loses to strikes (slower to start, a whiff is punishable).
-- The victim can tech it (Grab or Light) inside TechWindow.
Combat.Grab = {
	Range = 4.5,
	Arc = 90,
	Startup = 0.22,
	Active = 0.1,
	WhiffRecovery = 0.55,
	TechWindow = 0.35,
	-- How long the victim is held before the throw
	Hold = 0.5,
	Damage = 12,
	-- Throwing backwards (holding back) deals a bit more
	BackDamage = 14,
	Knockback = 55,
	Launch = 14,
	Cooldown = 1.2,
}

-- Knocked down by sweeps, shoulder charges, full charges and throws
Combat.Knockdown = {
	Duration = 1.1,
	-- Dodge this soon after hitting the floor to tech roll away
	TechWindow = 0.35,
	TechRollDistance = 10,
	TechRollDuration = 0.25,
	-- Invulnerable for this long after getting up (or tech rolling)
	GetUpInvulnerable = 0.4,
	-- One hit on a downed fighter at most, at this share of its damage
	OTGDamageMultiplier = 0.5,
}

-- Rewards for reading the opponent
Combat.Counter = { DamageMultiplier = 1.25, ExtraHitstun = 0.25 }
Combat.Punish = { DamageMultiplier = 1.2 }
-- After a parry, the next light attack inside the window is a riposte
Combat.Riposte = { Window = 0.8, DamageMultiplier = 1.5 }
-- Two melee attacks meeting: no damage, both pushed back and briefly stunned
Combat.Clash = { Window = 0.1, Pushback = 35, Stun = 0.35 }
-- Knocked into a wall hard enough: bounce off it, extra damage and stun
Combat.WallSplat = { MinKnockback = 40, CheckDistance = 6, Damage = 5, Stun = 0.8, Bounce = 12 }
-- Taunting unhit for the whole Duration grants ultimate charge; being hit is a counter hit
Combat.Taunt = { Duration = 1.4, UltimateCharge = 8, Cooldown = 6 }
-- Carrying a light prop (Weight 1): slower walk, no blocking. Light throws it.
Combat.Carry = { WalkSpeed = 11, ThrowSpeed = 85, Damage = 10, Knockback = 35, Reach = 6, MaxDuration = 10 }
-- Basic attacks after the From-th hit of a combo deal PerHit less each (never below Min)
Combat.ComboScaling = { From = 3, PerHit = 0.08, Min = 0.5 }

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
