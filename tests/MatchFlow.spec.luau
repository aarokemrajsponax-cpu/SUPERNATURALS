local MatchFlow = Harness.load("Shared/Match/MatchFlow")
local Scoreboard = Harness.load("Shared/Combat/Scoreboard")
local MatchConfig = Harness.load("Shared/Config/Match")

local Duel = MatchConfig.Modes.Duel

local function kinds(events)
	local list = {}
	for _, event in events do
		table.insert(list, event.kind)
	end
	return table.concat(list, ",")
end

return function(t)
	local function startedDuel()
		local flow = MatchFlow.new(Duel, { "A", "B" }, 0)
		local events = MatchFlow.tick(flow, Duel.Countdown)
		return flow, events
	end

	t.test("countdown, then the fight begins", function()
		local flow = MatchFlow.new(Duel, { "A", "B" }, 0)
		t.equal(flow.phase, "Countdown", "starts counting down")
		t.equal(#MatchFlow.tick(flow, Duel.Countdown - 0.1), 0, "nothing before the countdown ends")
		t.equal(kinds(MatchFlow.tick(flow, Duel.Countdown)), "Begin", "begins")
		t.equal(flow.phase, "Active", "fighting")
	end)

	t.test("knockouts during the countdown don't count", function()
		local flow = MatchFlow.new(Duel, { "A", "B" }, 0)
		t.equal(#MatchFlow.knockout(flow, "A", "B", 1), 0, "ignored")
		t.equal(flow.board.entries.A.score, 0, "no score change")
	end)

	t.test("a knockout: +1 for the winner, -1 for the loser", function()
		local flow = startedDuel()
		local events = MatchFlow.knockout(flow, "B", "A", 20)
		t.equal(kinds(events), "Knockout", "event")
		t.equal(events[1].credited, "A", "credited")
		t.equal(flow.board.entries.A.score, 1, "A score")
		t.equal(flow.board.entries.B.score, -1, "B score")
	end)

	t.test("an uncredited knockout only costs the victim", function()
		local flow = startedDuel()
		local events = MatchFlow.knockout(flow, "B", nil, 20)
		t.equal(events[1].credited, nil, "no credit")
		t.equal(flow.board.entries.A.score, 0, "A unchanged")
		t.equal(flow.board.entries.B.score, -1, "B lost a point")
	end)

	t.test("you can't earn a point by knocking yourself out", function()
		local flow = startedDuel()
		MatchFlow.knockout(flow, "A", "A", 20)
		t.equal(flow.board.entries.A.score, -1, "self knockout is just -1")
	end)

	t.test("knockout credit to someone outside the match is ignored", function()
		local flow = startedDuel()
		local events = MatchFlow.knockout(flow, "B", "Stranger", 20)
		t.equal(events[1].credited, nil, "not credited")
	end)

	t.test("time up: the highest score wins", function()
		local flow = startedDuel()
		MatchFlow.knockout(flow, "B", "A", 20)
		local events = MatchFlow.tick(flow, Duel.Countdown + Duel.Duration)
		t.equal(kinds(events), "Finish", "finished")
		local result = events[1].result
		t.equal(result.reason, "TimeUp", "reason")
		t.equal(result.winners[1], "A", "A wins")
		t.equal(#result.winners, 1, "one winner")
		t.equal(result.draw, false, "not a draw")
		t.equal(result.ranking[1].id, "A", "ranked first")
	end)

	t.test("a tie goes to sudden death; the next knockout wins", function()
		local flow = startedDuel()
		local events = MatchFlow.tick(flow, Duel.Countdown + Duel.Duration)
		t.equal(kinds(events), "SuddenDeath", "sudden death")
		t.equal(flow.phase, "SuddenDeath", "phase")
		local ko = MatchFlow.knockout(flow, "A", "B", Duel.Countdown + Duel.Duration + 5)
		t.equal(kinds(ko), "Knockout,Finish", "knockout ends it")
		t.equal(ko[2].result.winners[1], "B", "B wins")
		t.equal(ko[2].result.reason, "SuddenDeath", "reason")
	end)

	t.test("sudden death: a tied leader leaving hands the win to the other leader", function()
		local ffa = MatchConfig.Modes.FreeForAll
		local flow = MatchFlow.new(ffa, { "A", "B", "C" }, 0)
		MatchFlow.tick(flow, ffa.Countdown)
		MatchFlow.knockout(flow, "C", "A", 10)
		MatchFlow.knockout(flow, "C", "B", 20)
		MatchFlow.tick(flow, ffa.Countdown + ffa.Duration)
		t.equal(flow.phase, "SuddenDeath", "A and B tied")
		local events = MatchFlow.leave(flow, "B", ffa.Countdown + ffa.Duration + 5)
		t.equal(kinds(events), "Finish", "decided")
		t.equal(events[1].result.winners[1], "A", "A wins")
		t.equal(events[1].result.draw, false, "not a draw")
	end)

	t.test("sudden death running out with a single leader is a win, not a draw", function()
		local flow = startedDuel()
		local timeUp = Duel.Countdown + Duel.Duration
		MatchFlow.tick(flow, timeUp)
		-- Force a lead without a knockout event (e.g. scores changed by a leave in FFA)
		flow.board.entries.A.score = 1
		local events = MatchFlow.tick(flow, timeUp + Duel.SuddenDeathDuration)
		t.equal(events[1].result.draw, false, "a win")
		t.equal(events[1].result.winners[1], "A", "A wins")
	end)

	t.test("sudden death that runs out is a draw", function()
		local flow = startedDuel()
		local timeUp = Duel.Countdown + Duel.Duration
		MatchFlow.tick(flow, timeUp)
		local events = MatchFlow.tick(flow, timeUp + Duel.SuddenDeathDuration)
		t.equal(kinds(events), "Finish", "finished")
		t.equal(events[1].result.draw, true, "draw")
		t.equal(#events[1].result.winners, 2, "both share it")
	end)

	t.test("a tie with the Draw rule ends immediately as a draw", function()
		local mode = table.clone(Duel)
		mode.TieRule = "Draw"
		local flow = MatchFlow.new(mode, { "A", "B" }, 0)
		MatchFlow.tick(flow, mode.Countdown)
		local events = MatchFlow.tick(flow, mode.Countdown + mode.Duration)
		t.equal(events[1].result.draw, true, "draw")
	end)

	t.test("results, then the match ends", function()
		local flow = startedDuel()
		MatchFlow.knockout(flow, "B", "A", 20)
		local finishAt = Duel.Countdown + Duel.Duration
		MatchFlow.tick(flow, finishAt)
		t.equal(flow.phase, "Results", "showing results")
		t.equal(#MatchFlow.knockout(flow, "A", "B", finishAt + 1), 0, "knockouts after the end don't count")
		t.equal(kinds(MatchFlow.tick(flow, finishAt + Duel.ResultsDuration)), "Ended", "ended")
		t.equal(#MatchFlow.tick(flow, finishAt + 1000), 0, "nothing after the end")
	end)

	t.test("a player leaving a duel gives the other a forfeit win", function()
		local flow = startedDuel()
		local events = MatchFlow.leave(flow, "B", 30)
		t.equal(kinds(events), "Finish", "finished")
		t.equal(events[1].result.reason, "Forfeit", "forfeit")
		t.equal(events[1].result.winners[1], "A", "A wins")
		t.equal(events[1].result.ranking[1].id, "A", "the leaver is ranked last")
	end)

	t.test("leaving during the countdown also ends the match", function()
		local flow = MatchFlow.new(Duel, { "A", "B" }, 0)
		local events = MatchFlow.leave(flow, "A", 1)
		t.equal(events[1].result.winners[1], "B", "B wins")
	end)

	t.test("free-for-all continues when one of four leaves", function()
		local ffa = MatchConfig.Modes.FreeForAll
		local flow = MatchFlow.new(ffa, { "A", "B", "C", "D" }, 0)
		MatchFlow.tick(flow, ffa.Countdown)
		t.equal(#MatchFlow.leave(flow, "D", 20), 0, "match goes on")
		MatchFlow.knockout(flow, "B", "A", 30)
		MatchFlow.knockout(flow, "C", "A", 40)
		local events = MatchFlow.tick(flow, ffa.Countdown + ffa.Duration)
		t.equal(events[1].result.winners[1], "A", "A wins")
		local leaders = Scoreboard.leaders(flow.board)
		t.equal(leaders[1], "A", "leader")
	end)

	t.test("a player who left can't be credited and isn't a leader", function()
		local ffa = MatchConfig.Modes.FreeForAll
		local flow = MatchFlow.new(ffa, { "A", "B", "C" }, 0)
		MatchFlow.tick(flow, ffa.Countdown)
		MatchFlow.knockout(flow, "B", "C", 20)
		MatchFlow.leave(flow, "C", 21)
		local events = MatchFlow.knockout(flow, "A", "C", 22)
		t.equal(events[1].credited, nil, "no credit to someone who left")
		-- A and B were both knocked out once (-1 each); C left, so C can't lead
		local leaders = Scoreboard.leaders(flow.board)
		t.equal(#leaders, 2, "A and B tie for the lead")
		t.equal(table.find(leaders, "C"), nil, "C isn't a leader")
	end)

	t.test("abort ends the match at once", function()
		local flow = startedDuel()
		t.equal(kinds(MatchFlow.abort(flow)), "Ended", "ended")
		t.equal(#MatchFlow.abort(flow), 0, "only once")
	end)

	t.test("score floor stops scores dropping below it", function()
		local board = Scoreboard.new({ "A", "B" }, 0)
		Scoreboard.recordKnockout(board, "A", "B")
		t.equal(board.entries.A.score, 0, "floored at 0")
		t.equal(board.entries.B.score, 1, "B scored")
	end)

	t.test("ranking breaks ties on knockouts, then deaths", function()
		local board = Scoreboard.new({ "A", "B", "C" })
		Scoreboard.recordKnockout(board, "C", "B") -- B +1, C -1
		Scoreboard.recordKnockout(board, "B", "A") -- A +1, B 0
		local ranking = Scoreboard.ranking(board)
		t.equal(ranking[1].id, "A", "A first (1 point)")
		t.equal(ranking[2].id, "B", "B second (0 points)")
		t.equal(ranking[3].id, "C", "C last")
	end)
end
