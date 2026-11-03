-- The Spectating Lounge's live side: builds World/Lounge, keeps its screens true, and wires
-- the Watch and Pick prompts to MatchService. The screens are redrawn only when
-- MatchService:onChanged fires (a match starts, changes state or ends, a spectator comes or
-- goes, a prediction is made), plus one coarse 5 second chain that runs only while a match
-- is live or a recent result is still shown, so clocks and "recent" ages never go stale.
-- Predictions are free and informational (owner rule): nothing here pays or awards anything.

local Players = game:GetService("Players")

local Lounge = require(script.Parent.Parent.World.Lounge)

local LoungeService = {}

-- How long finished matches stay listed, and how long the board shows a winner
local RECENT_SECONDS = 600
local RECENT_COUNT = 3
local RESULT_SECONDS = 45
local TICK_SECONDS = 5

local built: Lounge.Built? = nil
local recent: { { text: string, at: number } } = {}
local lastResult: any = nil
local boardMatchId: string? = nil
local boardFighters: { string } = {}
local lastMatches: { any } = {}
local ticking = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function percentages(entry: any): (number, number, number)
	local counts, total = entry.tally.counts, entry.tally.total
	if total == 0 then
		return 0, 0, 0
	end
	local a = counts[entry.fighters[1].id] or 0
	local pctA = math.floor(100 * a / total + 0.5)
	return pctA, 100 - pctA, total
end

function LoungeService:Init(services)
	self.services = services
	self.matches = services.MatchService
end

function LoungeService:Start()
	local ok, result = pcall(Lounge.build, workspace, {
		watch = function(player: Player, index: number)
			self:_watch(player, index)
		end,
		predict = function(player: Player, side: number)
			self:_predict(player, side)
		end,
	})
	if not ok then
		warn(`[LoungeService] the lounge did not build: {result}`)
		return
	end
	built = result
	self.matches:onChanged(function()
		self:refresh()
	end)
	self.matches:onFinished(function(match, outcome)
		self:_record(match, outcome)
		self:refresh()
	end)
	self:refresh()
end

function LoungeService:spawnCFrame(): CFrame
	local base = if built then built.spawn else CFrame.new(Lounge.Center + Vector3.new(0, 4, 30))
	return base + Vector3.new(math.random(-4, 4), 0, math.random(-2, 2))
end

function LoungeService:getBuilt()
	return built
end

-- A finished match: a line for the recent list and the board's winner reveal
function LoungeService:_record(match: any, outcome: any)
	local names = {}
	for _, participant in match.participants do
		table.insert(names, participant.name)
	end
	local winners = {}
	for _, id in outcome.winners do
		local participant = match.byId[id]
		if participant then
			table.insert(winners, participant.name)
		end
	end
	local mode = match.mode.DisplayName
	local text
	if outcome.draw or #winners == 0 then
		text = `{table.concat(names, " and ")} drew in {mode}`
	else
		text = `{table.concat(winners, " and ")} won {mode}`
	end
	table.insert(recent, 1, { text = text, at = now() })
	while #recent > RECENT_COUNT do
		table.remove(recent)
	end
	local a, b = match.participants[1], match.participants[2]
	local entry = {
		matchLine = table.concat(names, " vs "),
		aName = a and a.name or "",
		bName = b and b.name or "",
		winners = winners,
		draw = outcome.draw or #winners == 0,
		at = now(),
		tally = self.matches:_tally(match),
		aId = a and a.id,
	}
	lastResult = entry
end

function LoungeService:_view(): any
	local time = now()
	local matches = self.matches:_watchable()
	for _, entry in matches do
		entry.elapsed = if entry.fightStartedAt then time - entry.fightStartedAt else nil
	end
	lastMatches = matches
	while #recent > 0 and time - recent[#recent].at > RECENT_SECONDS do
		table.remove(recent)
	end
	local list = {}
	for _, item in recent do
		local minutes = math.max(0, math.floor((time - item.at) / 60))
		table.insert(list, { text = `{item.text}, {if minutes < 1 then "just now" else `{minutes} min ago`}` })
	end

	-- Prediction board: an open match first, then a fresh result, then a closed live match
	local board: any = { kind = "idle", status = "No match to predict yet. Predictions open when a match starts." }
	boardMatchId, boardFighters = nil, {}
	local open, live
	for _, entry in matches do
		if #entry.fighters >= 2 then
			live = live or entry
			if entry.predictionOpen then
				open = open or entry
			end
		end
	end
	if open then
		local pctA, pctB, total = percentages(open)
		boardMatchId = open.id
		boardFighters = { open.fighters[1].id, open.fighters[2].id }
		board = {
			kind = "open",
			matchLine = "Who do you think will win?",
			aName = open.fighters[1].name,
			bName = open.fighters[2].name,
			pctA = pctA,
			pctB = pctB,
			status = if total == 0 then "Pick a fighter. Be the first to call it." else `{total} {if total == 1 then "prediction" else "predictions"} so far. Picks close 20 seconds into the fight.`,
		}
	elseif lastResult and time - lastResult.at <= RESULT_SECONDS and not (live and live.predictionOpen) then
		local result = lastResult
		local a = result.tally.counts[result.aId] or 0
		local total = result.tally.total
		local pctA = if total == 0 then 0 else math.floor(100 * a / total + 0.5)
		local winnerLine = if result.draw then "No winner: a draw." else `Winner: {table.concat(result.winners, " and ")}.`
		board = {
			kind = "result",
			matchLine = result.matchLine,
			aName = result.aName,
			bName = result.bName,
			pctA = pctA,
			pctB = if total == 0 then 0 else 100 - pctA,
			status = `Match complete. The community has made its predictions. {winnerLine}`,
		}
	elseif live then
		local pctA, pctB, total = percentages(live)
		board = {
			kind = "closed",
			matchLine = table.concat(live.names, " vs "),
			aName = live.fighters[1].name,
			bName = live.fighters[2].name,
			pctA = pctA,
			pctB = pctB,
			status = if total == 0 then "Predictions are closed for this match." else `Predictions are closed. {total} {if total == 1 then "pick" else "picks"} made.`,
		}
	end
	return {
		matches = matches,
		recent = list,
		queues = self.matches:queueSizes(),
		board = board,
	}
end

function LoungeService:refresh()
	if not built then
		return
	end
	local ok, err = pcall(function()
		built.refresh(self:_view())
	end)
	if not ok then
		warn(`[LoungeService] could not refresh the screens: {err}`)
	end
	-- One coarse chain while anything on the screens depends on the clock
	if not ticking and (#lastMatches > 0 or #recent > 0 or lastResult ~= nil) then
		ticking = true
		task.delay(TICK_SECONDS, function()
			ticking = false
			self:refresh()
		end)
	end
	if #lastMatches == 0 and lastResult and now() - lastResult.at > RESULT_SECONDS then
		lastResult = nil
	end
end

function LoungeService:_watch(player: Player, index: number)
	local entry = lastMatches[index]
	if not entry then
		self.matches:_notice(player, "That match has already ended.")
		return
	end
	self.matches:spectate(player, entry.id)
end

function LoungeService:_predict(player: Player, side: number)
	local fighterId = boardFighters[side]
	if not boardMatchId or not fighterId then
		self.matches:_notice(player, "Predictions are closed.")
		return
	end
	self.matches:predict(player, boardMatchId, fighterId)
end

return LoungeService
