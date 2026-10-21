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
}

-- Server -> clients, through Remotes.CombatEvent
Protocol.CombatEvent = {
	Attack = "Attack", -- { attacker: Model, kind: string, step: number, startup: number, active: number }
	Hit = "Hit", -- { attacker: Model, victim: Model, result: string, damage: number, position: Vector3, heavy: boolean, finisher: boolean }
	Dodge = "Dodge", -- { fighter: Model, direction: Vector3 }
	Rejected = "Rejected", -- { action: string, reason: string } (only to the requesting player)
}

-- Client -> server, through Remotes.MatchRequest
Protocol.MatchAction = {
	Queue = "Queue", -- (modeName)
	LeaveQueue = "LeaveQueue",
	Travel = "Travel", -- ("Lobby" | "Training")
	ReturnToLobby = "ReturnToLobby",
}

-- Server -> clients, through Remotes.MatchEvent
Protocol.MatchEvent = {
	Queue = "Queue", -- { mode: string, queued: number, needed: number, startsAt: number? } or nil when not queued
	State = "State", -- match snapshot, see MatchService.snapshot
	Knockout = "Knockout", -- { victim: string, credited: string? } (display names)
	Results = "Results", -- { reason, draw, winners: {string}, ranking: {{name, score, knockouts, deaths}} }
	Ended = "Ended",
	Notice = "Notice", -- { text: string }
}

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
	MatchId = "MatchId",
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
}

return Protocol
