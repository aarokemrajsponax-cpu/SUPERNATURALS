-- The final-moments replay and the after-fight numbers: how often fighters are
-- recorded, how much is kept, what goes into the Highlight a match sends when it
-- ends, and the rules that pick one factual tip for the results screen. The
-- server reads the recording limits; the client reads the viewer's settings.

local Replay = {}

-- Recording (server) ----------------------------------------------------------------

-- Fighter positions are sampled this many times a second
Replay.Rate = 10
-- How much of the end of a match is kept (a ring buffer, older samples are overwritten)
Replay.Seconds = 15
-- Recording carries on this long after the match is decided, so the replay shows
-- the knockout land instead of stopping on the blow
Replay.TailSeconds = 1.2
-- Hard caps on what one Highlight may carry
Replay.MaxFighters = 8
Replay.MaxEvents = 140
-- The match summary (whole match, key moments only)
Replay.MaxSummary = 14
-- Positions are rounded to this many studs before sending (keeps the payload small)
Replay.Precision = 0.05

-- A hit at least this big is a highlight ("big hit") on the timeline
Replay.BigHitDamage = 18

-- Per-frame flags (a bit field on every sample)
Replay.Flags = {
	-- Not visible (concealed, invisible): the sample repeats the last visible spot
	Hidden = 1,
	Blocking = 2,
	Downed = 4,
	Airborne = 8,
	-- Knocked out or not spawned: the stand-in is not drawn
	Absent = 16,
	-- Swinging or casting (BusyUntil in the future)
	Attacking = 32,
	-- Knocked out: the stand-in lies where the fighter fell
	Out = 64,
}
-- Hits and knockouts this soon after the match is decided still count (the
-- deciding blow is reported a moment after the finish)
Replay.FinishGrace = 0.5

-- Viewer (client) -------------------------------------------------------------------

-- Playback speeds offered, in order (1 is the default)
Replay.Speeds = { 0.25, 0.5, 1, 2 }
-- Seconds the jump buttons move
Replay.JumpSeconds = 2
-- The knockout camera slows time to this around each knockout
Replay.KoSlowMotion = 0.35
-- ...for this many seconds of replay time either side of the blow
Replay.KoWindow = 0.9
-- How many highlights this session keeps in memory for "Your replays"
Replay.SessionKeep = 5

-- The victory scene (client)
Replay.VictorySeconds = 4.2
-- Earliest the victory scene can be skipped (so a stray press doesn't eat it)
Replay.SkipAfter = 0.6

-- One-time hints this feature may remember in profile.tutorial.done
Replay.Hints = {
	WatchReplay = "hint:watchReplay",
}

-- The tip on the results screen --------------------------------------------------------
-- Checked in order; the first rule whose numbers fit is shown. If none fits,
-- no tip is shown. Each rule only states what the match's numbers show.
Replay.Tips = {
	-- Most of the damage you took came from grabs
	Grabs = { minGrabs = 2, damageShare = 0.4, text = "Grabs beat blocking. Dodge them or strike first." },
	-- Timing bars came up but few were perfect
	Timing = { minBars = 2, perfectShare = 0.34, text = "Press right as the marker reaches the centre." },
	-- Your guard broke more than once
	GuardBreaks = { minBreaks = 2, text = "Long blocks wear your guard down. Dodge or strike back between hits." },
	-- You took a lot of hits and blocked none of them
	NoBlocks = { minHitsTaken = 8, text = "Hold block to take less damage. Tap it just before a hit to parry." },
	-- Your ultimate was full and never used
	UnusedUltimate = { text = "Your ultimate was ready and went unused. It's worth spending before the end." },
	-- You landed plenty of hits but never more than one in a row
	NoCombos = { minHits = 6, text = "Your hits landed one at a time. Chain attacks quickly to build a combo." },
}
Replay.TipOrder = { "Grabs", "Timing", "GuardBreaks", "NoBlocks", "UnusedUltimate", "NoCombos" }

return Replay
