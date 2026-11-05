-- GameRoomService: the Power Meter and the Reflex cabinet in a personal base's game room
-- (DECISIONS 62; Config/Homes.PowerMeter, Homes.Reflex, Homes.Activities).
--
-- The client only says "now" (a prompt press, or BaseAction.Activity with the activity id). All
-- timing is the SERVER's clock (BaseService.clock, os.clock in the game):
--   Power Meter  first press starts a run (start time and period are known to the server and sent
--                to the player so the needle can be drawn); the second press strikes. The score is
--                Homes.powerMeterScore(clock - start, period), 0 to 100. A client cannot send a score.
--   Reflex       first press starts a random wait of waitMin..waitMax seconds, then the server sends
--                "go" and notes the time. A press during the wait is a false start. The reaction is
--                (the press's arrival time - the go time) minus the player's round-trip ping (capped
--                at latencyCapMs), never below minMs, so latency does not punish a slow connection
--                and a script cannot post an impossible time.
-- One player uses a machine at a time; a run left alone ends after its timeout. A valid result
-- updates the personal best on the profile (hosting.bests) and, for the first valid play of each
-- activity per UTC day, pays a small Money reward (Homes.Activities[id].dailyMoney).
-- The room's high score board lists the people currently in the base.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Homes = require(ReplicatedStorage.Shared.Config.Homes)

local GameRoomService = {}

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BaseEvent = Remotes:WaitForChild("BaseEvent") :: RemoteEvent

local services: any = {}
-- Replaceable in tests
GameRoomService.random = Random.new()

type Run = { user: Player, token: number, start: number, state: string, goAt: number? }
-- [owner Player] = { meter = Run?, reflex = Run? }
local runs: { [Player]: { meter: Run?, reflex: Run? } } = {}
local tokenCounter = 0

function GameRoomService:Init(all)
	services = all
	self.data = all.DataService
	self.currency = all.CurrencyService
end

function GameRoomService:Start()
	Players.PlayerRemoving:Connect(function(player)
		runs[player] = nil
		for _, state in runs do
			if state.meter and state.meter.user == player then
				state.meter = nil
			end
			if state.reflex and state.reflex.user == player then
				state.reflex = nil
			end
		end
	end)
end

local function activityPrompt(base, id: string): ProximityPrompt?
	return base.built.prompts[id]
end

local function tell(player: Player, id: string, phase: string, data: any?)
	BaseEvent:FireClient(player, Protocol.BaseEvent.Activity, id, phase, data or {})
end

local function clock(): number
	return services.BaseService.clock()
end

-- Rewards and bests ---------------------------------------------------------------------------------

-- value: score (higher is better) for the Power Meter, milliseconds (lower is better) for Reflex
function GameRoomService:_record(player: Player, id: string, value: number): (boolean, number)
	local profile = self.data:get(player)
	if not profile then
		return false, 0
	end
	local best = profile.hosting.bests[id] or 0
	local improved = if id == "PowerMeter" then value > best else (best == 0 or value < best)
	local today = services.BaseService.today()
	local reward = 0
	local rule = Homes.Activities[id]
	if profile.hosting.playedDay[id] ~= today and rule and rule.dailyMoney > 0 then
		reward = rule.dailyMoney
	end
	if not improved and reward == 0 then
		return false, 0
	end
	self.data:update(player, function(data)
		if improved then
			data.hosting.bests[id] = value
		end
		if reward > 0 then
			data.hosting.playedDay[id] = today
		end
	end)
	if reward > 0 then
		self.currency:add(player, { money = reward }, "Game room " .. id)
	end
	return improved, reward
end

-- Presses ----------------------------------------------------------------------------------------------

-- `id` is "PowerMeter" or "Reflex"; `base` is the base the player is standing in
function GameRoomService:press(player: Player, base, id: string): boolean
	if id ~= "PowerMeter" and id ~= "Reflex" then
		return false
	end
	local prompt = activityPrompt(base, id)
	if not prompt or not services.BaseService:isInside(player, base) then
		return false
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local part = prompt.Parent :: BasePart
	if not root or not (root :: BasePart):IsA("BasePart") or ((root :: BasePart).Position - part.Position).Magnitude > Homes.PromptReach + 8 then
		return false
	end
	local state = runs[base.player]
	if not state then
		state = { meter = nil, reflex = nil }
		runs[base.player] = state
	end
	if id == "PowerMeter" then
		self:_pressMeter(player, base, state, prompt)
	else
		self:_pressReflex(player, base, state, prompt)
	end
	return true
end

function GameRoomService:_pressMeter(player: Player, base, state, prompt: ProximityPrompt)
	local room = base.built.gameRoom
	local run: Run? = state.meter
	local now = clock()
	if run and now - run.start > Homes.PowerMeter.timeout then
		state.meter = nil
		run = nil
	end
	if run and run.user ~= player then
		tell(player, "PowerMeter", "busy", { text = services.BaseService.shownName(run.user) .. " is using the Power Meter." })
		return
	end
	if not run then
		tokenCounter += 1
		state.meter = { user = player, token = tokenCounter, start = now, state = "run" }
		prompt.ActionText = "Strike now"
		room.setMeter(nil, "Strike!")
		tell(player, "PowerMeter", "start", { serverStart = workspace:GetServerTimeNow(), period = Homes.PowerMeter.period, timeout = Homes.PowerMeter.timeout })
		local mine = tokenCounter
		task.delay(Homes.PowerMeter.timeout + 0.2, function()
			if state.meter and state.meter.token == mine then
				state.meter = nil
				prompt.ActionText = "Start the needle"
				room.setMeter(nil, "Ready")
				tell(player, "PowerMeter", "timeout", {})
			end
		end)
		return
	end
	state.meter = nil
	prompt.ActionText = "Start the needle"
	local score = Homes.powerMeterScore(now - run.start, Homes.PowerMeter.period)
	local improved, reward = self:_record(player, "PowerMeter", score)
	room.setMeter(score, string.format("%s: %d", services.BaseService.shownName(player), score))
	tell(player, "PowerMeter", "result", { score = score, best = improved, reward = reward })
	self:refreshBoard(base)
	services.BaseService:pushPanel(player)
end

function GameRoomService:_pressReflex(player: Player, base, state, prompt: ProximityPrompt)
	local room = base.built.gameRoom
	local run: Run? = state.reflex
	local now = clock()
	if run and now - run.start > Homes.Reflex.waitMax + Homes.Reflex.timeout + 1 then
		state.reflex = nil
		run = nil
	end
	if run and run.user ~= player then
		tell(player, "Reflex", "busy", { text = services.BaseService.shownName(run.user) .. " is playing the Reflex cabinet." })
		return
	end
	if not run then
		tokenCounter += 1
		local mine = tokenCounter
		local fresh: Run = { user = player, token = mine, start = now, state = "wait" }
		state.reflex = fresh
		prompt.ActionText = "Press when it turns green"
		room.setReflex("wait", "Wait for green...")
		tell(player, "Reflex", "ready", {})
		local wait = GameRoomService.random:NextNumber(Homes.Reflex.waitMin, Homes.Reflex.waitMax)
		task.delay(wait, function()
			if state.reflex == fresh and fresh.state == "wait" then
				fresh.state = "go"
				fresh.goAt = clock()
				room.setReflex("go", "GO!")
				tell(player, "Reflex", "go", { serverTime = workspace:GetServerTimeNow() })
				task.delay(Homes.Reflex.timeout, function()
					if state.reflex == fresh then
						state.reflex = nil
						prompt.ActionText = "Start the Reflex game"
						room.setReflex("idle", "Press to start")
						tell(player, "Reflex", "timeout", {})
					end
				end)
			end
		end)
		return
	end
	state.reflex = nil
	prompt.ActionText = "Start the Reflex game"
	if run.state == "wait" then
		room.setReflex("false", "False start")
		tell(player, "Reflex", "false", {})
		task.delay(1.5, function()
			if not state.reflex then
				room.setReflex("idle", "Press to start")
			end
		end)
		return
	end
	local ping = 0
	local ok, value = pcall(function()
		return player:GetNetworkPing()
	end)
	if ok and typeof(value) == "number" and value == value and value > 0 then
		ping = value
	end
	local ms = (now - (run.goAt or now)) * 1000 - math.min(ping * 1000, Homes.Reflex.latencyCapMs)
	ms = math.floor(math.max(ms, Homes.Reflex.minMs) + 0.5)
	local improved, reward = self:_record(player, "Reflex", ms)
	room.setReflex("idle", string.format("%s: %d ms", services.BaseService.shownName(player), ms))
	tell(player, "Reflex", "result", { ms = ms, best = improved, reward = reward })
	self:refreshBoard(base)
	services.BaseService:pushPanel(player)
end

-- Scoreboard --------------------------------------------------------------------------------------------

function GameRoomService:refreshBoard(base)
	local rows = {}
	for _, player in services.BaseService:playersInside(base) do
		local profile = self.data:get(player)
		if profile then
			table.insert(rows, {
				name = services.BaseService.shownName(player),
				power = profile.hosting.bests.PowerMeter or 0,
				reflex = profile.hosting.bests.Reflex or 0,
			})
		end
	end
	table.sort(rows, function(a, b)
		if a.power ~= b.power then
			return a.power > b.power
		end
		return a.name < b.name
	end)
	local lines = {}
	for i = 1, math.min(#rows, 5) do
		local row = rows[i]
		table.insert(lines, {
			name = row.name,
			power = if row.power > 0 then tostring(row.power) else "-",
			reflex = if row.reflex > 0 then row.reflex .. " ms" else "-",
		})
	end
	base.built.gameRoom.setBoard(lines)
end

return GameRoomService
