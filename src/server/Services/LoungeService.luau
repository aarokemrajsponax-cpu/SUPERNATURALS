-- The Spectating Lounge's live side: builds World/Lounge, keeps its screens true, and wires
-- the Watch and Pick prompts to MatchService. The screens are redrawn only when
-- MatchService:onChanged fires (a match starts, changes state or ends, a spectator comes or
-- goes, a prediction is made), plus one coarse 5 second chain that runs only while a match
-- is live or a recent result is still shown, so clocks and "recent" ages never go stale.
-- Predictions are free and informational (owner rule): nothing here pays or awards anything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lounge = require(script.Parent.Parent.World.Lounge)
local LoungeConfig = require(ReplicatedStorage.Shared.Config.Lounge)
local Wheel = require(ReplicatedStorage.Shared.Config.Wheel)

local LoungeService = {}

-- How long finished matches stay listed, and how long the board shows a winner
local RECENT_SECONDS = 600
local RECENT_COUNT = 3
local RESULT_SECONDS = 45
local TICK_SECONDS = 5
local IDLE_CYCLE_SECONDS = 8

local built: Lounge.Built? = nil
local recent: { { text: string, at: number } } = {}
local lastResult: any = nil
local boardMatchId: string? = nil
local boardFighters: { string } = {}
local lastMatches: { any } = {}
local ticking = false
-- Quick Draw (the games table): phase "idle" | "lobby" | "ready" | "wait" | "go" | "result"
local game_ = { phase = "idle", slots = {} :: { [number]: Player? }, token = 0, goAt = 0, message = {} :: { [number]: string }, falseStart = {} :: { [number]: boolean } }

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
	self.currency = services.CurrencyService
	self.data = services.DataService
	-- Replaceable in tests: seconds clock, random source, UTC clock
	self.clock = os.clock
	self.random = Random.new(os.time() % 2147483647)
	self.utc = os.time
end

function LoungeService:Start()
	local ok, result = pcall(Lounge.build, workspace, {
		watch = function(player: Player, index: number)
			self:_watch(player, index)
		end,
		predict = function(player: Player, side: number)
			self:_predict(player, side)
		end,
		game = function(player: Player, slot: number)
			self:gameBuzz(player, slot)
		end,
	})
	if not ok then
		warn(`[LoungeService] the lounge did not build: {result}`)
		return
	end
	built = result
	Players.PlayerRemoving:Connect(function(player)
		self:_gameLeft(player)
	end)
	self:_gameShow()
	-- The idle screens move slowly through the fighter roster
	task.spawn(function()
		while built do
			task.wait(IDLE_CYCLE_SECONDS)
			pcall(built.cycle)
		end
	end)
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

-- Quick Draw --------------------------------------------------------------------------------------------

local function nameOf(player: Player?): string
	return if player then player.DisplayName else ""
end

-- Pushes the table state to the room's text, prompts and lamp
function LoungeService:_gameShow()
	if not built then
		return
	end
	local g = game_
	local status, action, object, enabled = {}, {}, {}, {}
	local lamp = "idle"
	for slot = 1, 2 do
		local other = g.slots[3 - slot]
		local mine = g.slots[slot]
		local text = ""
		if g.phase == "idle" or g.phase == "lobby" then
			text = if mine then `{nameOf(mine)} is ready` else "Quick Draw: press Play to take this seat"
			if mine and not other then
				text = `{nameOf(mine)} is waiting for an opponent`
			end
			action[slot] = if mine then "Leave" else "Play"
			object[slot] = "Quick Draw"
			enabled[slot] = true
		elseif g.phase == "ready" then
			text = "Get ready"
			action[slot], object[slot], enabled[slot] = "Buzz", "", false
			lamp = "wait"
		elseif g.phase == "wait" then
			text = "Wait for green"
			action[slot], object[slot], enabled[slot] = "Buzz", "Wait for green", true
			lamp = "wait"
		elseif g.phase == "go" then
			text = "NOW"
			action[slot], object[slot], enabled[slot] = "Buzz", "Now", true
			lamp = "go"
		else
			text = g.message[slot] or ""
			action[slot], object[slot], enabled[slot] = "Buzz", "", false
			lamp = "done"
		end
		status[slot] = text
	end
	built.setGame({ status = status, action = action, object = object, enabled = enabled, lamp = lamp })
end

function LoungeService:_gameReset()
	game_.phase = "idle"
	game_.slots = {}
	game_.message = {}
	game_.falseStart = {}
	game_.token += 1
	self:_gameShow()
end

function LoungeService:_gameLeft(player: Player)
	local g = game_
	for slot = 1, 2 do
		if g.slots[slot] == player then
			if g.phase == "wait" or g.phase == "go" or g.phase == "ready" then
				self:_gameFinish(3 - slot, "The other player left.")
			else
				self:_gameReset()
			end
			return
		end
	end
end

-- Money paid by the table today for this player, with the daily cap applied. Returns the amount paid.
function LoungeService:_gamePay(player: Player, amount: number): number
	local profile = self.data and self.data:get(player)
	if not profile or amount <= 0 then
		return 0
	end
	local today = Wheel.dayOf(self.utc())
	local paid = 0
	self.data:update(player, function(p)
		if p.lounge.gameDay ~= today then
			p.lounge.gameDay = today
			p.lounge.gameEarned = 0
		end
		paid = math.max(0, math.min(amount, LoungeConfig.QuickDraw.DailyCap - p.lounge.gameEarned))
		p.lounge.gameEarned += paid
	end)
	if paid > 0 then
		self.currency:add(player, { money = paid }, "Lounge Quick Draw")
	end
	return paid
end

-- slot: the winner's seat. text: why.
function LoungeService:_gameFinish(winnerSlot: number?, why: string)
	local g = game_
	local cfg = LoungeConfig.QuickDraw
	g.phase = "result"
	g.token += 1
	local token = g.token
	for slot = 1, 2 do
		local player = g.slots[slot]
		local won = winnerSlot == slot
		local paid = 0
		-- Money goes only when two different players really played
		if player and g.slots[3 - slot] and g.slots[3 - slot] ~= player then
			paid = self:_gamePay(player, if won then cfg.WinMoney else cfg.PlayMoney)
		end
		local line = if won then "You win" else "Not this time"
		g.message[slot] = `{line}. {why}{if paid > 0 then ` +{paid} Money` else ""}`
	end
	self:_gameShow()
	task.delay(cfg.ResultSeconds, function()
		if game_.token == token then
			self:_gameReset()
		end
	end)
end

function LoungeService:_gameStartRound()
	local g = game_
	local cfg = LoungeConfig.QuickDraw
	g.phase = "ready"
	g.token += 1
	g.falseStart = {}
	local token = g.token
	self:_gameShow()
	task.delay(cfg.ReadySeconds, function()
		if game_.token ~= token then
			return
		end
		game_.phase = "wait"
		game_.token += 1
		local waitToken = game_.token
		self:_gameShow()
		task.delay(cfg.MinWait + self.random:NextNumber() * (cfg.MaxWait - cfg.MinWait), function()
			if game_.token ~= waitToken then
				return
			end
			game_.phase = "go"
			game_.goAt = self.clock()
			game_.token += 1
			local goToken = game_.token
			self:_gameShow()
			task.delay(cfg.GoSeconds, function()
				if game_.token == goToken and game_.phase == "go" then
					self:_gameFinish(nil, "Nobody buzzed.")
				end
			end)
		end)
	end)
end

-- A player pressed the buzzer at `slot`. Joins, leaves or buzzes depending on the table's state.
function LoungeService:gameBuzz(player: Player, slot: number)
	if slot ~= 1 and slot ~= 2 then
		return
	end
	local g = game_
	local cfg = LoungeConfig.QuickDraw
	if g.slots[slot] ~= nil and g.slots[slot] ~= player and (g.phase == "idle" or g.phase == "lobby") then
		self.matches:_notice(player, "That seat is taken.")
		return
	end
	if g.phase == "idle" or g.phase == "lobby" then
		if g.slots[slot] == player then
			self:_gameReset()
			return
		end
		if g.slots[3 - slot] == player then
			self.matches:_notice(player, "You are already at the table.")
			return
		end
		g.slots[slot] = player
		g.phase = "lobby"
		g.token += 1
		local token = g.token
		if g.slots[1] and g.slots[2] then
			self:_gameStartRound()
		else
			self:_gameShow()
			task.delay(cfg.LobbySeconds, function()
				if game_.token == token and game_.phase == "lobby" then
					self:_gameReset()
				end
			end)
		end
		return
	end
	-- A buzz needs the player to hold one of the two seats
	if g.slots[slot] ~= player then
		return
	end
	if g.phase == "wait" then
		-- Too early: the other player wins the round
		g.falseStart[slot] = true
		self:_gameFinish(3 - slot, "False start.")
	elseif g.phase == "go" then
		local ms = math.floor((self.clock() - g.goAt) * 1000 + 0.5)
		self:_gameFinish(slot, `{ms} ms.`)
	end
end

function LoungeService:gameState()
	return game_
end

return LoungeService
