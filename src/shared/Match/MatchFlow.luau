-- The life of one match: countdown, fight, sudden death, results, end.
-- Pure logic driven by timestamps; the server calls tick() regularly and acts on
-- the events it returns.

local Scoreboard = require(script.Parent.Parent.Combat.Scoreboard)

local MatchFlow = {}

export type Result = {
	reason: string, -- "TimeUp" | "SuddenDeath" | "Draw" | "Forfeit" | "Abandoned"
	winners: { string },
	draw: boolean,
	ranking: { Scoreboard.Entry },
}

export type Event = {
	kind: string, -- "Begin" | "SuddenDeath" | "Knockout" | "Finish" | "Ended"
	victim: string?,
	credited: string?,
	tied: { string }?,
	result: Result?,
}

export type Flow = {
	mode: any,
	phase: string, -- "Countdown" | "Active" | "SuddenDeath" | "Results" | "Ended"
	phaseEndsAt: number,
	board: Scoreboard.Board,
	result: Result?,
}

function MatchFlow.new(mode, ids: { string }, now: number): Flow
	return {
		mode = mode,
		phase = "Countdown",
		phaseEndsAt = now + mode.Countdown,
		board = Scoreboard.new(ids, mode.ScoreFloor),
		result = nil,
	}
end

function MatchFlow.isFighting(flow: Flow): boolean
	return flow.phase == "Active" or flow.phase == "SuddenDeath"
end

local function finish(flow: Flow, events: { Event }, reason: string, winners: { string }, draw: boolean, now: number)
	flow.phase = "Results"
	flow.phaseEndsAt = now + flow.mode.ResultsDuration
	local result: Result = {
		reason = reason,
		winners = winners,
		draw = draw,
		ranking = Scoreboard.ranking(flow.board),
	}
	flow.result = result
	table.insert(events, { kind = "Finish", result = result })
end

local function timeUp(flow: Flow, events: { Event }, now: number)
	local leaders = Scoreboard.leaders(flow.board)
	if #leaders == 1 then
		finish(flow, events, "TimeUp", leaders, false, now)
	elseif flow.mode.TieRule == "SuddenDeath" and flow.mode.SuddenDeathDuration > 0 then
		flow.phase = "SuddenDeath"
		flow.phaseEndsAt = now + flow.mode.SuddenDeathDuration
		table.insert(events, { kind = "SuddenDeath", tied = leaders })
	else
		finish(flow, events, "Draw", leaders, true, now)
	end
end

function MatchFlow.tick(flow: Flow, now: number): { Event }
	local events = {}
	if now < flow.phaseEndsAt then
		return events
	end
	if flow.phase == "Countdown" then
		flow.phase = "Active"
		flow.phaseEndsAt = now + flow.mode.Duration
		table.insert(events, { kind = "Begin" })
	elseif flow.phase == "Active" then
		timeUp(flow, events, now)
	elseif flow.phase == "SuddenDeath" then
		local leaders = Scoreboard.leaders(flow.board)
		if #leaders == 1 then
			finish(flow, events, "SuddenDeath", leaders, false, now)
		else
			finish(flow, events, "Draw", leaders, true, now)
		end
	elseif flow.phase == "Results" then
		flow.phase = "Ended"
		table.insert(events, { kind = "Ended" })
	end
	return events
end

-- Knockouts only count while fighting. In sudden death, the first knockout
-- that leaves a single leader wins.
function MatchFlow.knockout(flow: Flow, victimId: string, creditedId: string?, now: number): { Event }
	local events = {}
	if not MatchFlow.isFighting(flow) or not Scoreboard.has(flow.board, victimId) then
		return events
	end
	local credited = Scoreboard.recordKnockout(flow.board, victimId, creditedId)
	table.insert(events, { kind = "Knockout", victim = victimId, credited = credited })
	if flow.phase == "SuddenDeath" then
		local leaders = Scoreboard.leaders(flow.board)
		if #leaders == 1 then
			finish(flow, events, "SuddenDeath", leaders, false, now)
		end
	end
	return events
end

-- A participant left. If only one fighter remains, they win by forfeit.
function MatchFlow.leave(flow: Flow, id: string, now: number): { Event }
	local events = {}
	if not Scoreboard.has(flow.board, id) then
		return events
	end
	Scoreboard.markLeft(flow.board, id)
	if flow.phase == "Results" or flow.phase == "Ended" then
		return events
	end
	local remaining = Scoreboard.remaining(flow.board)
	if #remaining <= 1 then
		finish(flow, events, "Forfeit", remaining, #remaining == 0, now)
	elseif flow.phase == "SuddenDeath" then
		-- A tied leader leaving can leave a single leader: they win
		local leaders = Scoreboard.leaders(flow.board)
		if #leaders == 1 then
			finish(flow, events, "SuddenDeath", leaders, false, now)
		end
	end
	return events
end

-- Ends the match straight away (for example, when no real players are left)
function MatchFlow.abort(flow: Flow): { Event }
	if flow.phase == "Ended" then
		return {}
	end
	flow.phase = "Ended"
	return { { kind = "Ended" } }
end

return MatchFlow
