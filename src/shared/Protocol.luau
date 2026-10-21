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
	ProtectedUntil = "ProtectedUntil",
	MatchId = "MatchId",
}

Protocol.Tag = {
	Fighter = "SNFighter",
}

return Protocol
