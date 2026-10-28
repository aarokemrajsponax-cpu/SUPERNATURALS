-- Names shared by the server and client: remote actions, event kinds,
-- attributes and tags. Keeping them in one place stops typos from silently
-- breaking communication.

local Protocol = {}

-- Client -> server, through Remotes.CombatRequest
Protocol.CombatAction = {
	Light = "Light",
	Heavy = "Heavy",
	BlockStart = "BlockStart", -- payload "Held" when re-raised automatically (no parry)
	BlockEnd = "BlockEnd",
	Dodge = "Dodge",
	-- Fighting System v2. Light/Heavy/Dodge/Grab/Sweep may carry { dir = Vector3 }
	-- (flat movement intent in world space, magnitude <= 1). Heavy with
	-- { dir, charge = true } starts a charge that HeavyRelease swings. The server
	-- picks the move from the fighter's state (air, sprint, back input, downed,
	-- launched, carrying, grabbed).
	HeavyRelease = "HeavyRelease",
	Feint = "Feint",
	Grab = "Grab",
	Sweep = "Sweep",
	SprintStart = "SprintStart",
	SprintEnd = "SprintEnd",
	Taunt = "Taunt",
}

-- Server -> clients, through Remotes.CombatEvent
Protocol.CombatEvent = {
	-- move: Jab, Cross, Hook, FinisherKick, Heavy, ChargedHeavy, Launcher, RushStrike,
	-- ShoulderCharge, AirKick, Slam, Sweep, Grab, PropThrow; charge 0..1 (charged heavies)
	Attack = "Attack", -- { attacker: Model, kind: string, step: number, startup: number, active: number, recovery: number, move: string, charge: number? }
	-- tags: { counter, punish, riposte, wallSplat, knockdown, launch, airborne, otg } (absent = false).
	-- result "Clash" (damage 0) is sent each way alongside a Clash event.
	Hit = "Hit", -- { attacker: Model, victim: Model, result: string, damage: number, position: Vector3, heavy: boolean, finisher: boolean, move: string?, tags: {}, direction: Vector3 }
	-- style: "Side" | "Back" | "Forward"; speed and duration are what the dodge moves at
	Dodge = "Dodge", -- { fighter: Model, direction: Vector3, style: string, speed: number, duration: number, invulnerable: number }
	Rejected = "Rejected", -- { action: string, reason: string } (only to the requesting player)
	Clash = "Clash", -- { a: Model, b: Model, position: Vector3 }
	-- Hold: direction is where the throw will go. Whiff without a victim = the grab
	-- missed; Whiff with a victim = the hold broke before the throw (holder hit or gone)
	Grab = "Grab", -- { attacker: Model, victim: Model?, phase: "Hold" | "Throw" | "Tech" | "Whiff", direction: Vector3? }
	-- motion: Charge, Feint, Knockdown, GetUp, TechRoll, Breakfall, Taunt, TauntDone, Winded,
	-- Recovered, PickUp, Drop, PerfectDodge, DodgeCancel, SprintStart, SprintEnd
	-- (PerfectDodge also has attacker: Model; PickUp and Drop have prop: string)
	Motion = "Motion", -- { fighter: Model, motion: string, direction: Vector3?, duration: number? }
}

-- Client -> server, through Remotes.MatchRequest
Protocol.MatchAction = {
	Queue = "Queue", -- (modeName, options: { arena: string?, cpuPower: string?, cpuDifficulty: string? }?)
	LeaveQueue = "LeaveQueue",
	Travel = "Travel", -- ("Lobby" | "Training" | "Base")
	ReturnToLobby = "ReturnToLobby",
	Rematch = "Rematch", -- vote to play again from the results screen
	ListMatches = "ListMatches", -- ask for the matches you can watch
	Spectate = "Spectate", -- (matchId)
	StopSpectating = "StopSpectating",
	Predict = "Predict", -- (matchId, fighterId) free spectator prediction, no stakes
}

-- Server -> clients, through Remotes.MatchEvent
Protocol.MatchEvent = {
	Queue = "Queue", -- { mode: string, queued: number, needed: number, startsAt: number? } or nil when not queued
	State = "State", -- match snapshot, see MatchService.snapshot
	Knockout = "Knockout", -- { victim: string, credited: string? } (display names)
	Results = "Results", -- { reason, draw, winners: {string}, ranking: {{name, score, knockouts, deaths}} }
	Ended = "Ended",
	Notice = "Notice", -- { text: string }
	Matches = "Matches", -- { { id, mode, arena, phase, names: {string} } } watchable matches
	Spectating = "Spectating", -- { matchId, fighters: { Model } } or nil when you stop
	Highlight = "Highlight", -- recorded final moments, see ReplayService
	Rematch = "Rematch", -- { votes: number, needed: number }
}

-- Client -> server, through Remotes.AbilityRequest: (abilityId, aim: { direction: Vector3?, point: Vector3? }?)
-- The ultimate is requested with its own ability id. Shapeshifter forms are abilities too.

-- Server -> clients, through Remotes.AbilityEvent
Protocol.AbilityEvent = {
	Fx = "Fx", -- { fighter: Model, power: string, fx: string, data: {} } something to draw
	Cast = "Cast", -- { fighter: Model, power: string, ability: string, startup: number } an ability started
	ProjectileSpawn = "ProjectileSpawn", -- see ProjectileService
	ProjectileUpdate = "ProjectileUpdate", -- redirected or changed course
	ProjectileEnd = "ProjectileEnd", -- { id, position, hit: boolean }
	Rejected = "Rejected", -- { ability: string, reason: string } (only to the caster)
}

-- Server -> one client, through Remotes.DefenseEvent
Protocol.DefenseEvent = {
	Cue = "Cue", -- { id, kind: "Prompt" | "Mash" | "Timing" | "Redirect", opensAt, closesAt, ... }
	Result = "Result", -- { id, kind, result: "Perfect" | "Good" | "Escaped" | "Failed" | "Countered" }
	Clear = "Clear", -- { id } the cue no longer applies
}

-- Client -> server, through Remotes.DefenseInput: (kind, cueId)
Protocol.DefenseInput = {
	Mash = "Mash",
	Timing = "Timing",
	Redirect = "Redirect",
}

-- Client -> server, through Remotes.PowerRequest (only outside an active fight)
Protocol.PowerAction = {
	Select = "Select", -- (powerId, degree)
	SetLoadout = "SetLoadout", -- (powerId, degree, { abilityId })
	UnlockAbility = "UnlockAbility", -- (powerId, abilityId) pays the listed Money/Gems price
	UnlockDegree = "UnlockDegree", -- (powerId, degree) pays the listed Money price
	UnlockPower = "UnlockPower", -- (powerId) premium power through the Gems path
	PromptPass = "PromptPass", -- (powerId) opens the Roblox purchase prompt for its game pass
}

-- Server -> one client, through Remotes.DataEvent
Protocol.DataEvent = {
	Profile = "Profile", -- the player's saved data (safe copy), sent on join and after changes
	Persistence = "Persistence", -- { saving: boolean, message: string? } false when progress can't be saved
	Reward = "Reward", -- { money, gems, xp, lines: { { label, money?, gems?, xp? } } } after a match
	Toast = "Toast", -- { text, kind: "info" | "success" | "error" | "reward" }
}

-- Client -> server, through Remotes.ShopRequest
Protocol.ShopAction = {
	Buy = "Buy", -- (itemId)
	Equip = "Equip", -- (slot, itemId?)
	PromptProduct = "PromptProduct", -- (productKey) Robux developer product (e.g. a gem pack)
}

-- Client -> server, through Remotes.BaseRequest
Protocol.BaseAction = {
	Save = "Save", -- (layout: { { item, x, z, r, c, m } }) replaces the whole furniture layout
	SetStyle = "SetStyle", -- ("floor" | "wall" | "lighting", styleId)
	SetAccess = "SetAccess", -- ("Everyone" | "Friends" | "Nobody")
	Visit = "Visit", -- (userId)
	Home = "Home",
	Upgrade = "Upgrade", -- buy more furniture capacity
	Buy = "Buy", -- (furnitureId | "Style:<kind>:<id>", count?) pays the listed price
}

-- Server -> clients, through Remotes.BaseEvent
Protocol.BaseEvent = {
	Result = "Result", -- { ok: boolean, message: string } (to the requester)
	Plots = "Plots", -- { { index, userId, name, access } } who lives where
}

-- Client -> server, through Remotes.ProgressRequest
Protocol.ProgressAction = {
	ClaimChallenge = "ClaimChallenge", -- (challengeId)
	StartLesson = "StartLesson", -- (lessonId) tutorial lesson in the training ground
	StopLesson = "StopLesson",
	Welcome = "Welcome", -- the new-player welcome was seen
	FindLore = "FindLore", -- (fileId) a recovered file was picked up (LoreService)
	ReadLore = "ReadLore", -- (documentId, page?) a book document was shown (LoreService)
	SeenHint = "SeenHint", -- (hintId) a one-time hint was shown; remembered in tutorial.done (ReplayService)
}

-- Client -> server, through Remotes.SettingsRequest: (settings table, sanitized on the server)

-- Client -> server, through Remotes.AdminRequest (owner only; checked on the server)
Protocol.AdminAction = {
	StartEvent = "StartEvent", -- (eventId)
	StopEvent = "StopEvent",
	PlayerAction = "PlayerAction", -- (userId | "All" | "Others", actionId)
	SelfToggle = "SelfToggle", -- ("Fly" | "Immune" | "Invisible" | "Crown", on)
	Announce = "Announce", -- (text)
	SetTime = "SetTime", -- (timeOfDayId)
	SetSeason = "SetSeason", -- (seasonId | "Auto")
	EndMatches = "EndMatches",
}

-- Server -> clients, through Remotes.AdminEvent
Protocol.AdminSignal = {
	Meteor = "Meteor", -- { position: Vector3, impactAt: number, size: number }
	Strike = "Strike", -- { position: Vector3, impactAt: number }
	BlackHoleBlast = "BlackHoleBlast", -- { position: Vector3 }
	Announce = "Announce", -- { text: string, from: string }
}

-- Attributes the server sets on fighter models (times use workspace:GetServerTimeNow())
Protocol.Attribute = {
	FighterId = "FighterId",
	DisplayName = "DisplayName",
	Guard = "Guard",
	MaxGuard = "MaxGuard",
	GuardUpdatedAt = "GuardUpdatedAt",
	Blocking = "Blocking",
	StunnedUntil = "StunnedUntil",
	HeavyReadyAt = "HeavyReadyAt",
	DodgeReadyAt = "DodgeReadyAt",
	-- End of the current swing or dodge (no new attack or dodge before then)
	BusyUntil = "BusyUntil",
	ProtectedUntil = "ProtectedUntil",
	-- Fighting System v2 (server sets, clients read)
	Stamina = "SNStamina",
	StaminaMax = "SNStaminaMax",
	Sprinting = "SNSprinting",
	Winded = "SNWinded",
	-- Server time the fighter gets up (0 when standing)
	DownedUntil = "SNDownedUntil",
	-- Name of the prop being carried (nil when empty-handed)
	Carrying = "SNCarrying",
	-- Server time the current heavy charge began (nil when not charging)
	ChargeStart = "SNChargeStart",
	-- Launched or being juggled
	Airborne = "SNAirborne",
	MatchId = "MatchId",
	-- Powers (on fighter models)
	Power = "SNPower",
	Degree = "SNDegree",
	-- Shapeshifter's current animal ("" when human)
	Form = "SNForm",
	-- The power's resource (fuel, grit, corruption...) and its maximum
	Resource = "SNRes",
	ResourceMax = "SNResMax",
	-- Ultimate charge, 0 to 100
	Ultimate = "SNUlt",
	-- Equipped abilities in slot order, comma separated
	Loadout = "SNLoadout",
	-- "SNCD_" .. abilityId = server time the ability is ready again
	CooldownPrefix = "SNCD_",
	-- "SNS_" .. statusId = server time the status ends (nil when it's not active)
	StatusPrefix = "SNS_",
	-- A power's visual stage (Corruption's overwrite, Machine Master's heat...), 0 to 1
	Phase = "SNPhase",
	-- The Grandmaster's extra meters (0 to 100): Focus (Degree III+) and Perfect Form (Degree IV)
	Focus = "SNFocus",
	PerfectForm = "SNPerfect",
	-- The cosmetic pass a fighter shows (its key in Monetization.Passes), nil for the standard look
	Style = "SNStyle",
	MaxHealth = "SNMaxHealth",
	-- On Player objects: which base plot is theirs, and what they're watching
	Plot = "SNPlot",
	Spectating = "SNSpectating",
	-- On a character: frozen in ice by the owner or an event
	Iced = "SNIced",
	-- On Player objects (owner panel)
	IsOwner = "SNIsOwner",
	Crown = "SNCrown",
	Aura = "SNAura",
	CanFly = "SNCanFly",
	Immune = "SNImmune",
	Invisible = "SNInvisible",
	-- On ReplicatedStorage
	AdminEvent = "AdminEvent",
	AdminEventStartedAt = "AdminEventStartedAt",
	AdminEventEndsAt = "AdminEventEndsAt",
	AdminEventCenter = "AdminEventCenter",
	-- Unique per event run ("" when none); clients restart visuals when it changes
	AdminEventRun = "AdminEventRun",
	SeasonOverride = "SeasonOverride",
	-- On Lighting: the owner's chosen time of day (nil = the season decides)
	OwnerClockTime = "SNOwnerClockTime",
	-- On Lighting: the lighting the server wants ("SNBase_" .. property), so
	-- clients can return to it after an event changed their lighting locally
	BaseLightingPrefix = "SNBase_",
}

Protocol.Tag = {
	Fighter = "SNFighter",
	-- Arena props Strong Dude can pick up and throw (attribute "Weight": 1 light, 2 heavy, 3 enormous)
	Throwable = "SNThrowable",
	-- Arena objects Syntax can take over (attribute "Interaction": what it does)
	Interactive = "SNInteractive",
	-- Temporary barriers and constructs that stop projectiles
	Construct = "SNConstruct",
}

return Protocol
