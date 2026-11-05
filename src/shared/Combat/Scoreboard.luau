-- Match scores. A knockout gives the fighter who earned it +1 and the
-- knocked-out fighter -1. Knockouts nobody earned (falling with no recent hit,
-- resetting) only cost the victim the point.

local Scoreboard = {}

export type Entry = {
	id: string,
	score: number,
	knockouts: number,
	deaths: number,
	left: boolean,
	order: number,
}

export type Board = {
	entries: { [string]: Entry },
	floor: number?,
}

function Scoreboard.new(ids: { string }, floor: number?): Board
	local board: Board = { entries = {}, floor = floor }
	for order, id in ids do
		board.entries[id] = { id = id, score = 0, knockouts = 0, deaths = 0, left = false, order = order }
	end
	return board
end

function Scoreboard.has(board: Board, id: string?): boolean
	return id ~= nil and board.entries[id] ~= nil
end

-- Returns the id that was credited (nil if the knockout was nobody's)
function Scoreboard.recordKnockout(board: Board, victimId: string, creditedId: string?): string?
	local victim = board.entries[victimId]
	if not victim then
		return nil
	end
	victim.deaths += 1
	victim.score -= 1
	if board.floor ~= nil then
		victim.score = math.max(victim.score, board.floor)
	end

	local credited = if creditedId and creditedId ~= victimId then board.entries[creditedId] else nil
	if credited and not credited.left then
		credited.score += 1
		credited.knockouts += 1
		return credited.id
	end
	return nil
end

function Scoreboard.markLeft(board: Board, id: string)
	local entry = board.entries[id]
	if entry then
		entry.left = true
	end
end

function Scoreboard.remaining(board: Board): { string }
	local ids = {}
	for id, entry in board.entries do
		if not entry.left then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		return board.entries[a].order < board.entries[b].order
	end)
	return ids
end

-- Everyone still in the match, best first. Ties break on knockouts, then fewer
-- deaths, then who joined first, so the order is always the same.
function Scoreboard.ranking(board: Board): { Entry }
	local list = {}
	for _, entry in board.entries do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		if a.left ~= b.left then
			return not a.left
		elseif a.score ~= b.score then
			return a.score > b.score
		elseif a.knockouts ~= b.knockouts then
			return a.knockouts > b.knockouts
		elseif a.deaths ~= b.deaths then
			return a.deaths < b.deaths
		end
		return a.order < b.order
	end)
	return list
end

-- Fighters sharing the top score (only those still in the match)
function Scoreboard.leaders(board: Board): { string }
	local best = -math.huge
	for _, entry in board.entries do
		if not entry.left and entry.score > best then
			best = entry.score
		end
	end
	local ids = {}
	for _, entry in Scoreboard.ranking(board) do
		if not entry.left and entry.score == best then
			table.insert(ids, entry.id)
		end
	end
	return ids
end

return Scoreboard
