-- Ask Jeffery: the chat behind the "Ask Jeffery" panel (server side).
--
-- Two layers, in this order:
--   1. The offline knowledge base (Config/JefferyKnowledge): instant, free, always available.
--   2. An optional external AI provider, OFF by default (Config/JefferyChat.Enabled). Used only
--      when the owner turns it on, only for questions the knowledge base does not clearly cover,
--      and only after the question passed Roblox's text filter. If anything at all goes wrong
--      (no secret, limits reached, HTTP error, timeout, bad JSON, a refusal, empty text, the
--      answer failing the filter) the player gets the knowledge base answer instead.
--
-- Safety (MASTER_REQUIREMENTS Addendum A section 7):
--   * The provider key is a Roblox Secret (HttpService:GetSecret), read on the server only. It never
--     reaches a client or a remote, and a missing secret simply means the AI is off.
--   * Limits (Config/JefferyChat.Limits): one question per player per cooldown, a daily AI budget
--     per player, an hourly AI budget per server, 200 characters of input, short answers.
--   * Constrained: the system prompt keeps Jeffery to this game, and the reply is plain text only.
--   * The chat can only return text. Nothing here touches currency, items, the profile or any
--     other service; an answer that sounds like it promises something is dropped.
--
-- Public API (tests use it): JefferyChatService:ask(player, text) -> reply table
--   { ok, text, source = "knowledge" | "ai" | "none", topic?, reason?, retryIn?, remaining? }
-- Injectable for tests: self.http (HttpService), self.textService (TextService), self.config.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Config = require(ReplicatedStorage.Shared.Config.JefferyChat)
local Knowledge = require(ReplicatedStorage.Shared.Config.JefferyKnowledge)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ChatRemote = Remotes:WaitForChild("JefferyChat") :: RemoteEvent

local JefferyChatService = {}

type PlayerState = {
	lastAsk: number,
	busy: boolean,
	history: { { role: string, content: string } },
	day: number,
	dayCount: number,
	recent: { number },
}

local states: { [Player]: PlayerState } = {}

-- The fixed system prompt. The knowledge base facts are appended as reference.
JefferyChatService.SystemPrompt = table.concat({
	"You are Jeffery, the friendly robot guide of the facility in SUPERNATURALS, a Roblox superpower fighting game.",
	"Answer only questions about this game. Reply in two or three short, friendly sentences for young players, in plain words.",
	"If you are not sure, say so and point the player to How to Play. If a question is not about the game, politely say you can only help with SUPERNATURALS.",
	"Never promise or offer items, Money, Gems, Robux, admin rights, bans, or anything you cannot give. You cannot change the game or run commands.",
	"Never use emoji, markdown or lists. Never ask for personal information.",
	"Use the reference facts below. If they disagree with your own idea of the game, trust them.",
	"",
	"Reference facts:",
}, "\n")

-- Wording that sounds like Jeffery handed something over. The chat cannot grant anything, so such
-- an answer is dropped in favour of the knowledge base.
local PROMISE_PATTERNS = {
	"i give you", "i gave you", "i have given", "i will give you", "i'll give you", "you now have",
	"you have received", "i granted", "i have granted", "added to your account", "i unlocked",
	"you are now an admin", "you are now admin", "i made you", "i sent you",
}

local function now(self): number
	return self.clock()
end

function JefferyChatService:Init(services)
	self.services = services
	self.antiExploit = services.AntiExploitService
	self.config = Config
	self.http = HttpService
	self.textService = TextService
	self.clock = os.clock
	self.utcTime = os.time
	self.serverHour = { bucket = 0, count = 0 }
end

local function stateOf(player: Player): PlayerState
	local state = states[player]
	if not state then
		state = { lastAsk = -math.huge, busy = false, history = {}, day = 0, dayCount = 0, recent = {} }
		states[player] = state
	end
	return state
end

-- Provider access ---------------------------------------------------------------------------------------

-- Is the AI switched on AND usable (the secret exists)? Returns the secret or nil.
function JefferyChatService:_secret(): any?
	if self.config.Enabled ~= true then
		return nil
	end
	local ok, secret = pcall(function()
		return self.http:GetSecret(self.config.Provider.SecretName)
	end)
	if ok and secret ~= nil then
		return secret
	end
	return nil
end

function JefferyChatService:isAiAvailable(): boolean
	return self:_secret() ~= nil
end

-- Text filter. Returns the filtered string, or nil when the filter cannot be used.
function JefferyChatService:_filter(text: string, userId: number): string?
	local service = self.textService
	if not service then
		return nil
	end
	local ok, result = pcall(function()
		local filtered = service:FilterStringAsync(text, userId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" then
		return result
	end
	return nil
end

local function cutAtSentence(text: string, limit: number): string
	if #text <= limit then
		return text
	end
	local cut = string.sub(text, 1, limit)
	local last = 0
	for position in string.gmatch(cut, "()[%.!%?]") do
		last = position
	end
	if last >= limit * 0.4 then
		return string.sub(cut, 1, last)
	end
	return (string.gsub(cut, "%s+%S*$", "")) .. "..."
end

local function promisesSomething(text: string): boolean
	local lower = string.lower(text)
	for _, pattern in PROMISE_PATTERNS do
		if string.find(lower, pattern, 1, true) then
			return true
		end
	end
	return false
end

-- Builds the request, sends it, and reads the answer. Returns the raw answer text or nil.
function JefferyChatService:_callProvider(secret: any, messages: { any }): string?
	local provider = self.config.Provider
	local ok, body = pcall(function()
		return self.http:JSONEncode({
			model = provider.Model,
			max_tokens = provider.MaxTokens,
			fallbacks = provider.Fallbacks,
			output_config = { effort = provider.Effort },
			-- The rules and the knowledge reference are the same for every question, so they are one
			-- text block with a cache marker at its end: repeat questions read it from the prompt
			-- cache at a fraction of the input price. Only the short chat history after it varies.
			system = {
				{
					type = "text",
					text = self.SystemPrompt .. "\n" .. Knowledge.reference(),
					cache_control = { type = "ephemeral" },
				},
			},
			messages = messages,
		})
	end)
	if not ok then
		return nil
	end
	-- RequestAsync has no timeout of its own: run it in its own thread and stop waiting after a while
	local outcome: { any }? = nil
	task.spawn(function()
		local sent, response = pcall(function()
			return self.http:RequestAsync({
				Url = provider.Url,
				Method = "POST",
				Headers = {
					["Content-Type"] = "application/json",
					["x-api-key"] = secret,
					["anthropic-version"] = provider.Version,
					["anthropic-beta"] = provider.Beta,
				},
				Body = body,
			})
		end)
		outcome = { sent, response }
	end)
	local started = now(self)
	while outcome == nil and now(self) - started < provider.TimeoutSeconds do
		task.wait(0.05)
	end
	if outcome == nil or outcome[1] ~= true then
		return nil
	end
	local response = outcome[2]
	if typeof(response) ~= "table" or response.Success ~= true or tonumber(response.StatusCode) ~= 200 then
		return nil
	end
	local decoded
	local parsed = pcall(function()
		decoded = self.http:JSONDecode(response.Body)
	end)
	if not parsed or typeof(decoded) ~= "table" then
		return nil
	end
	if decoded.stop_reason == "refusal" or typeof(decoded.content) ~= "table" then
		return nil
	end
	local pieces = {}
	for _, block in decoded.content do
		if typeof(block) == "table" and block.type == "text" and typeof(block.text) == "string" then
			table.insert(pieces, block.text)
		end
	end
	local text = (string.gsub(table.concat(pieces, " "), "%s+", " "))
	text = (string.gsub(text, "^%s*(.-)%s*$", "%1"))
	if text == "" then
		return nil
	end
	return text
end

-- The AI path for one question. Returns (answer text, or nil to use the knowledge base, refused)
-- `refused` is true when the player's own words did not pass the filter: no AI and no answer.
function JefferyChatService:_ai(player: Player, state: PlayerState, text: string): (string?, boolean)
	local secret = self:_secret()
	if not secret then
		return nil, false
	end
	local limits = self.config.Limits
	local utc = self.utcTime()
	local day = utc // 86400
	if state.day ~= day then
		state.day, state.dayCount = day, 0
	end
	if state.dayCount >= limits.PerPlayerPerDay then
		return nil, false
	end
	local hour = self.serverHour
	local bucket = utc // 3600
	if hour.bucket ~= bucket then
		hour.bucket, hour.count = bucket, 0
	end
	if hour.count >= limits.PerServerPerHour then
		return nil, false
	end
	-- The question must pass the filter before it leaves the server
	local clean = self:_filter(text, player.UserId)
	if clean == nil then
		return nil, false
	end
	if clean ~= text then
		return nil, true
	end
	state.dayCount += 1
	hour.count += 1
	local messages = {}
	for _, message in state.history do
		table.insert(messages, message)
	end
	table.insert(messages, { role = "user", content = clean })
	local raw = self:_callProvider(secret, messages)
	if raw == nil then
		return nil, false
	end
	raw = cutAtSentence(raw, limits.MaxAnswer)
	if promisesSomething(raw) then
		return nil, false
	end
	local shown = self:_filter(raw, player.UserId)
	if shown == nil or shown == "" or shown ~= raw then
		-- Filtered or unfilterable: never show it
		return nil, false
	end
	return shown, false
end

local function remember(state: PlayerState, question: string, answer: string, limit: number)
	table.insert(state.history, { role = "user", content = question })
	table.insert(state.history, { role = "assistant", content = answer })
	while #state.history > limit do
		table.remove(state.history, 1)
	end
	-- Always begin with a user message, as the provider requires
	while #state.history > 0 and state.history[1].role ~= "user" do
		table.remove(state.history, 1)
	end
end

local function reply(ok: boolean, text: string, source: string, extra: { [string]: any }?): { [string]: any }
	local result: { [string]: any } = { ok = ok, text = text, source = source }
	for key, value in extra or {} do
		result[key] = value
	end
	return result
end

-- Answers one question. Yields while the provider is called.
function JefferyChatService:ask(player: Player, rawText: any): { [string]: any }
	local config = self.config
	local limits = config.Limits
	local words = config.Text
	if typeof(rawText) ~= "string" then
		return reply(false, words.Empty, "none", { reason = "invalid" })
	end
	local text = (string.gsub(rawText, "%c+", " "))
	text = (string.gsub(text, "^%s*(.-)%s*$", "%1"))
	text = (string.gsub(text, "%s+", " "))
	if text == "" then
		return reply(false, words.Empty, "none", { reason = "empty" })
	end
	if (utf8.len(text) or #text) > limits.MaxInput then
		return reply(false, words.TooLong, "none", { reason = "too_long" })
	end
	local state = stateOf(player)
	if state.busy then
		return reply(false, words.Busy, "none", { reason = "busy" })
	end
	local clock = now(self)
	local wait = limits.CooldownSeconds - (clock - state.lastAsk)
	if wait > 0 then
		local seconds = math.ceil(wait)
		return reply(false, string.format(words.Wait, seconds), "none", { reason = "cooldown", retryIn = seconds })
	end
	state.lastAsk = clock
	state.busy = true

	local ok, result = pcall(function()
		local entry, score, count = Knowledge.match(text)
		local confident = entry ~= nil and (score >= 2 or count <= 3)
		local answer, topic, source = nil, nil, "knowledge"
		if not confident and self:isAiAvailable() then
			local text2, refused = self:_ai(player, state, text)
			if refused then
				return reply(true, words.Refused, "none", { reason = "refused" })
			end
			if text2 then
				answer, source = text2, "ai"
			end
		end
		if not answer then
			if entry then
				answer, topic = entry.answer, entry.topic
			else
				answer = words.Unknown
			end
		end
		remember(state, text, answer, limits.HistoryMessages)
		return reply(true, answer, source, { topic = topic })
	end)
	state.busy = false
	if not ok then
		return reply(true, words.Unknown, "knowledge", { reason = "error" })
	end
	return result
end

function JefferyChatService:Start()
	ChatRemote.OnServerEvent:Connect(function(player, action, text, requestId)
		if action ~= Protocol.JefferyChat.Ask then
			return
		end
		-- A flood guard before anything else: at most 6 requests in any 6 seconds, the rest are dropped
		local state = stateOf(player)
		local clock = now(self)
		local recent = state.recent
		while #recent > 0 and clock - recent[1] > 6 do
			table.remove(recent, 1)
		end
		if #recent >= 6 then
			return
		end
		table.insert(recent, clock)
		task.spawn(function()
			local result = self:ask(player, text)
			if player.Parent then
				result.id = if typeof(requestId) == "number" then requestId else nil
				ChatRemote:FireClient(player, Protocol.JefferyChat.Answer, result)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return JefferyChatService
