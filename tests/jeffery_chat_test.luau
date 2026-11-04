-- Ask Jeffery (JefferyChatService) with simulated players and a fake provider:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/jeffery_chat_test.luau build/game.rbxl
-- The knowledge base answers instantly (60+ entries, each finds itself); the AI provider is OFF by
-- default and never contacted; limits (input length, cooldown, daily and hourly AI budgets);
-- filter failures refuse; a fake HTTP provider: the request is built as specified, text blocks are
-- joined, and a refusal, HTTP errors, a thrown call, bad JSON, empty text, a timeout and a
-- missing secret all fall back to the knowledge base; the key never leaves the server; and
-- nothing is ever granted (currency, items and titles are untouched).

local process = require("@lune/process")
local World = require("./smoke/World")
local Engine = require("./smoke/Engine")

local api = World.start(process.args[1] or "build/game.rbxl")
local task = api.task
local world, services, check = api.world, api.services, api.check
local Chat, Data, Currency = services.JefferyChatService, services.DataService, services.CurrencyService
local Config = world.require(world.find("ReplicatedStorage.Shared.Config.JefferyChat"))
local Knowledge = world.require(world.find("ReplicatedStorage.Shared.Config.JefferyKnowledge"))
local Protocol = world.require(world.find("ReplicatedStorage.Shared.Protocol"))

local player = api.join("Chatty", 950)
api.waitFor(function()
	return Data:get(player) ~= nil
end, 5, "Chatty's profile")

-- A controllable clock for the cooldown and the daily and hourly limits
local fakeNow, fakeUtc = 1000, 1_800_000_000
Chat.clock = function()
	return fakeNow
end
Chat.utcTime = function()
	return fakeUtc
end
local http = Engine.newHttpService()
local filter = Engine.newTextService()
Chat.http, Chat.textService = http, filter

local function ask(text, who)
	fakeNow += 7
	return Chat:ask(who or player, text)
end
local function snapshot()
	local profile = Data:get(player)
	local owned = 0
	for _ in profile.cosmetics.owned do
		owned += 1
	end
	return { money = Currency:balance(player, "money"), gems = Currency:balance(player, "gems"), owned = owned, title = profile.cosmetics.equipped.title }
end
local before = snapshot()

local function textBlock(text)
	return { status = 200, body = { stop_reason = "end_turn", content = { { type = "text", text = text } } } }
end
local ODD = "Pirates and dragons and wizards sail a submarine across the deep blue ocean"

check("the knowledge base is big: 60+ entries, topics covered, plain text only", function()
	assert(#Knowledge.Entries >= 60, "entries: " .. #Knowledge.Entries)
	local topics = {}
	local ids = {}
	for _, entry in Knowledge.Entries do
		topics[entry.topic] = true
		assert(not ids[entry.id], "duplicate id " .. entry.id)
		ids[entry.id] = true
		assert(#entry.patterns >= 2 and entry.answer ~= "", entry.id)
		assert(not string.find(entry.answer, "\u{2014}") and not string.find(entry.answer, "\u{2013}"), "no dashes: " .. entry.id)
		for index = 1, #entry.answer do
			assert(string.byte(entry.answer, index) < 0xF0, "no emoji: " .. entry.id)
		end
		assert(#entry.answer <= 330, "short answer: " .. entry.id .. " " .. #entry.answer)
	end
	for _, topic in { "Controls", "Fighters", "Phases", "Places", "Shop", "Rewards", "Help", "Social", "Jeffery" } do
		assert(topics[topic], "topic " .. topic)
	end
end)

check("every entry's first pattern finds its own entry (nothing is shadowed)", function()
	for _, entry in Knowledge.Entries do
		local found = Knowledge.match(entry.patterns[1])
		assert(found and found.id == entry.id, `"{entry.patterns[1]}" found {found and found.id} instead of {entry.id}`)
	end
end)

check("natural questions reach the right answer", function()
	local cases = {
		{ "How do I move around?", "move" }, { "how do i dodge", "dodge" }, { "what are phases?", "phases" },
		{ "How do I change fighters?", "changefighter" }, { "where do i train", "train" }, { "How do I earn Gems?", "gems" },
		{ "what is the season pass", "pass" }, { "how do I block attacks", "block" }, { "does admin give real admin rights", "adminfighter" },
		{ "how can i play with friends", "invite" }, { "where is my base", "bases" }, { "how do I watch matches", "lounge" },
		{ "I am stuck and cannot move", "stuck" }, { "how do i report a hacker", "cheater" }, { "what does the ultimate do", "ultimate" },
		{ "how do I use abilities on a gamepad", "abilities" }, { "can I get free robux", "freestuff" }, { "what is the locker for", "locker" },
		{ "how do I evolve", "evolve" }, { "controls on a phone", "phone" }, { "what's the gift calendar", "gifts" },
		{ "who are you", "who" }, { "how do I do a sweep", "sweep" }, { "where do I fight other players", "fight" },
	}
	for _, case in cases do
		local entry = Knowledge.match(case[1])
		assert(entry and entry.id == case[2], `"{case[1]}" gave {entry and entry.id} not {case[2]}`)
	end
	assert(Knowledge.match("zxqv blorp flarn") == nil, "nonsense matches nothing")
end)

check("the AI provider is off by default and is never contacted", function()
	assert(Config.Enabled == false, "Enabled is false in config")
	assert(Chat:isAiAvailable() == false, "not available")
	http.secrets.ANTHROPIC_API_KEY = "sk-test-key"
	local reply = ask(ODD)
	assert(reply.ok and reply.source == "knowledge" and reply.text == Config.Text.Unknown, "unknown question answered from the notes: " .. tostring(reply.text))
	assert(#http.requests == 0, "no request when disabled, even with a secret")
	local move = ask("How do I move?")
	assert(move.ok and move.source == "knowledge" and move.topic == "Controls" and string.find(move.text, "W A S D", 1, true), "instant knowledge answer")
	assert(#http.requests == 0, "still none")
end)

check("input limits: empty, junk, too long, and the cooldown", function()
	for _, junk in { "", "   ", 42, true, {}, "\n\t" } do
		local reply = ask(junk)
		assert(reply.ok == false and (reply.reason == "empty" or reply.reason == "invalid"), "refused: " .. tostring(junk))
	end
	local long = ask(string.rep("a", Config.Limits.MaxInput + 1))
	assert(long.ok == false and long.reason == "too_long" and long.text == Config.Text.TooLong, "201 characters refused")
	local exact = ask(string.rep("a", Config.Limits.MaxInput))
	assert(exact.ok, "200 characters allowed")
	local first = ask("How do I jump?")
	assert(first.ok, "first answered")
	fakeNow += 2
	local second = Chat:ask(player, "How do I sprint?")
	assert(second.ok == false and second.reason == "cooldown" and second.retryIn >= 3 and second.retryIn <= 6, "cooldown: " .. tostring(second.retryIn))
	fakeNow += 4.5
	assert(Chat:ask(player, "How do I sprint?").ok, "allowed again after the cooldown")
end)

check("the remote works end to end, echoes the request id, drops floods, ignores junk", function()
	local mark = api.mark()
	fakeNow += 7
	api.request("JefferyChat", player, Protocol.JefferyChat.Ask, "what are phases?", 77)
	task.wait(0.3)
	local answers = api.sentSince(mark, "JefferyChat", Protocol.JefferyChat.Answer, player)
	assert(#answers == 1 and answers[1].id == 77 and answers[1].ok and answers[1].source == "knowledge", "answer with the id")
	assert(string.find(answers[1].text, "meter", 1, true), "phase answer")
	mark = api.mark()
	api.request("JefferyChat", player, "Nope", "hi", 1)
	api.request("JefferyChat", player, 42, "hi", 1)
	task.wait(0.2)
	assert(#api.sentSince(mark, "JefferyChat", Protocol.JefferyChat.Answer, player) == 0, "unknown actions are ignored")
	mark = api.mark()
	for _ = 1, 20 do
		api.request("JefferyChat", player, Protocol.JefferyChat.Ask, "hello", 5)
	end
	task.wait(0.4)
	local flood = #api.sentSince(mark, "JefferyChat", Protocol.JefferyChat.Answer, player)
	assert(flood <= 6, "at most 6 of 20 flooded requests are answered: " .. flood)
end)

-- The provider path ----------------------------------------------------------------------------------
Config.Enabled = true
Config.Limits.PerPlayerPerDay = 1000
Config.Limits.PerServerPerHour = 1000

check("with the AI on, a confident knowledge answer does not cost a call", function()
	assert(Chat:isAiAvailable(), "enabled and the secret exists")
	local reply = ask("How do I dodge?")
	assert(reply.source == "knowledge" and #http.requests == 0, "no call for a known question")
end)

check("an open question goes to the provider with exactly the specified request", function()
	table.insert(http.queue, { status = 200, body = { stop_reason = "end_turn", content = {
		{ type = "thinking", thinking = "SECRET THOUGHTS" },
		{ type = "text", text = "Pirates and dragons? Not in this facility, " },
		{ type = "text", text = "but the Training Studio is full of dummies. Ask me about it!" },
	} } })
	local reply = ask(ODD)
	assert(reply.ok and reply.source == "ai", "AI answer: " .. tostring(reply.text) .. " " .. tostring(reply.source))
	assert(reply.text == "Pirates and dragons? Not in this facility, but the Training Studio is full of dummies. Ask me about it!", "text blocks joined, thinking left out")
	assert(not string.find(reply.text, "SECRET"), "no thinking text")
	assert(#http.requests == 1, "one request")
	local request = http.requests[1]
	assert(request.Url == "https://api.anthropic.com/v1/messages" and request.Method == "POST", "url and method")
	local headers = request.Headers
	assert(headers["Content-Type"] == "application/json", "content type")
	assert(headers["x-api-key"] == "sk-test-key", "the secret object goes in x-api-key")
	assert(headers["anthropic-version"] == "2026-10-21", "version")
	assert(headers["anthropic-beta"] == "server-side-fallback-2026-07-01", "beta")
	local body = request.json
	assert(body.model == "claude-opus-5-5" and body.max_tokens == 1024, "model and tokens")
	assert(body.fallbacks == "default" and body.output_config.effort == "low", "fallbacks and effort")
	assert(body.temperature == nil and body.top_p == nil, "no temperature or top_p")
	-- The stable system text is one block with a cache marker at its end (prompt caching)
	assert(typeof(body.system) == "table" and #body.system == 1 and body.system[1].type == "text", "system is one text block")
	assert(body.system[1].cache_control and body.system[1].cache_control.type == "ephemeral", "the system block is cached")
	body.system = body.system[1].text
	assert(string.find(body.system, "You are Jeffery", 1, true) and string.find(body.system, "only questions about this game", 1, true) or string.find(body.system, "Answer only questions about this game", 1, true), "system prompt")
	assert(string.find(body.system, "never promise", 1, true) or string.find(body.system, "Never promise", 1, true), "no promises")
	assert(string.find(body.system, Knowledge.Entries[1].answer, 1, true), "knowledge facts quoted as reference")
	assert(#body.messages == #http.requests[1].json.messages and body.messages[#body.messages].role == "user" and body.messages[#body.messages].content == ODD, "last message is the question")
	assert(body.messages[1].role == "user", "starts with a user message")
	-- The key is a server secret and appears nowhere a client can see
	assert(not string.find(reply.text, "sk-test-key"), "key not in the answer")
	assert(not string.find(request.Body, "sk-test-key"), "key not in the body")
end)

check("the last few turns of this player's chat go along, and no more than the history limit", function()
	for index = 1, 5 do
		table.insert(http.queue, textBlock("Answer number " .. index .. "."))
		ask("Pirates number " .. index .. " sail a submarine across the ocean with dragons")
	end
	local body = http.requests[#http.requests].json
	assert(#body.messages <= Config.Limits.HistoryMessages + 1, "history is bounded: " .. #body.messages)
	assert(#body.messages >= 3, "earlier turns included")
	assert(body.messages[1].role == "user" and body.messages[#body.messages].role == "user", "user first and last")
	for index = 2, #body.messages do
		assert(body.messages[index].role ~= body.messages[index - 1].role, "roles alternate")
	end
end)

check("a refusal, errors, bad JSON, empty text and odd replies fall back to the knowledge base", function()
	local failures = {
		{ name = "refusal", entry = { status = 200, body = { stop_reason = "refusal", content = { { type = "text", text = "I cannot help." } } } } },
		{ name = "http 500", entry = { status = 500, body = { error = "boom" } } },
		{ name = "http 429", entry = { status = 429, body = "" } },
		{ name = "thrown", entry = { error = "HttpError: ConnectFail" } },
		{ name = "bad json", entry = { status = 200, body = "not json {" } },
		{ name = "empty text", entry = { status = 200, body = { content = { { type = "text", text = "   " } } } } },
		{ name = "no text blocks", entry = { status = 200, body = { content = { { type = "tool_use", id = "x" } } } } },
		{ name = "no content", entry = { status = 200, body = { stop_reason = "end_turn" } } },
	}
	for number, case in failures do
		table.insert(http.queue, case.entry)
		local mark = #http.requests
		local reply = ask(ODD .. " case " .. number)
		assert(#http.requests == mark + 1, case.name .. ": the provider was tried")
		assert(reply.ok and reply.source == "knowledge" and reply.text == Config.Text.Unknown, case.name .. " -> notes: " .. tostring(reply.source) .. " " .. tostring(reply.text))
	end
	-- A fallback still answers a partly matching question with the entry
	table.insert(http.queue, { status = 503, body = "" })
	local reply = ask("hmm what about the ultimate thing and all these other long words that go on and on and on")
	assert(reply.source == "knowledge" and reply.topic == "Controls", "entry answer after a failure: " .. tostring(reply.topic))
	-- A decode that throws, and an encode that throws
	table.insert(http.queue, textBlock("fine"))
	http.decodeFails = true
	local decode = ask(ODD .. " decode")
	http.decodeFails = false
	assert(decode.source == "knowledge", "decode error -> notes")
	http.encodeFails = true
	local requests = #http.requests
	local encode = ask(ODD .. " encode")
	http.encodeFails = false
	assert(encode.source == "knowledge" and #http.requests == requests, "encode error -> notes, nothing sent")
end)

check("a provider that never answers times out and the notes answer", function()
	local oldTimeout, oldClock = Config.Provider.TimeoutSeconds, Chat.clock
	Config.Provider.TimeoutSeconds = 0.4
	local base = os.clock()
	Chat.clock = function()
		return fakeNow + (os.clock() - base)
	end
	table.insert(http.queue, { status = 200, delay = 3, body = { content = { { type = "text", text = "too late" } } } })
	local started = os.clock()
	fakeNow += 7
	local reply = Chat:ask(player, ODD .. " slow")
	Chat.clock = oldClock
	fakeNow += 10
	Config.Provider.TimeoutSeconds = oldTimeout
	assert(os.clock() - started < 2.5, "did not wait for the slow provider")
	assert(reply.ok and reply.source == "knowledge", "answered from the notes: " .. tostring(reply.source) .. " " .. tostring(reply.reason))
	task.wait(3)
end)

check("filters: bad words are refused before sending, a failing filter means no AI, bad AI text is never shown", function()
	-- The player's own words fail the filter: refused politely, nothing sent
	filter.banned = { "darn" }
	local requests = #http.requests
	local rude = ask("you darn silly pirate sail a submarine across the ocean")
	assert(rude.ok and rude.source == "none" and rude.reason == "refused" and rude.text == Config.Text.Refused, "refused")
	assert(#http.requests == requests, "not sent")
	-- The filter is down: the question never leaves the server, the notes answer
	filter.fail = true
	local down = ask(ODD .. " filter down")
	assert(down.source == "knowledge" and #http.requests == requests, "no AI while the filter fails")
	filter.fail = false
	filter.failBroadcast = true
	local down2 = ask(ODD .. " broadcast down")
	assert(down2.source == "knowledge" and #http.requests == requests, "no AI while the filter errors (2)")
	filter.failBroadcast = false
	-- The AI answered with a filtered word: never shown
	table.insert(http.queue, textBlock("Well darn, that is a good question about ships."))
	local dirty = ask(ODD .. " dirty answer")
	assert(dirty.source == "knowledge" and not string.find(dirty.text, "darn"), "the filtered answer is dropped")
	filter.banned = {}
	-- The answer cannot be filtered at all
	table.insert(http.queue, textBlock("A perfectly nice answer."))
	local calls = #filter.calls
	filter.fail = false
	local original = filter.FilterStringAsync
	local count = 0
	filter.FilterStringAsync = function(self, text, userId)
		count += 1
		if count >= 2 then
			error("filter died after the question (simulated)")
		end
		return original(self, text, userId)
	end
	local late = ask(ODD .. " late filter failure")
	filter.FilterStringAsync = original
	assert(late.source == "knowledge" and calls >= 0, "answer not shown when it cannot be filtered")
end)

check("an answer that sounds like a promise is dropped; long answers are cut", function()
	table.insert(http.queue, textBlock("Sure! I will give you 5000 Gems right now."))
	local promise = ask(ODD .. " promise please")
	assert(promise.source == "knowledge" and not string.find(promise.text, "5000"), "promise dropped")
	table.insert(http.queue, textBlock(string.rep("This is a sentence about the facility. ", 40)))
	local long = ask(ODD .. " long answer")
	assert(long.source == "ai" and #long.text <= Config.Limits.MaxAnswer + 3, "cut: " .. #long.text)
	assert(string.sub(long.text, -1) == ".", "cut at a sentence end")
end)

check("the daily budget per player and the hourly budget per server only limit the AI", function()
	Config.Limits.PerPlayerPerDay = 2
	fakeUtc += 86400
	local calls = #http.requests
	for index = 1, 3 do
		table.insert(http.queue, textBlock("AI answer " .. index .. "."))
		local reply = ask(ODD .. " daily " .. index)
		if index <= 2 then
			assert(reply.source == "ai", "within the daily budget " .. index)
		else
			assert(reply.source == "knowledge", "past the daily budget the notes answer")
		end
	end
	assert(#http.requests == calls + 2, "only two calls")
	assert(ask("How do I move?").source == "knowledge", "the notes always work")
	Config.Limits.PerPlayerPerDay = 1000
	Config.Limits.PerServerPerHour = 1
	fakeUtc += 3600
	local mark = #http.requests
	table.insert(http.queue, textBlock("Hour answer one."))
	assert(ask(ODD .. " hour 1").source == "ai", "first of the hour")
	assert(ask(ODD .. " hour 2").source == "knowledge", "server hourly cap reached")
	assert(#http.requests == mark + 1, "one call")
	fakeUtc += 3600
	table.insert(http.queue, textBlock("Next hour."))
	assert(ask(ODD .. " hour 3").source == "ai", "a new hour resets the cap")
	Config.Limits.PerServerPerHour = 1000
end)

check("a missing secret switches the AI off by itself", function()
	http.secrets.ANTHROPIC_API_KEY = nil
	assert(Chat:isAiAvailable() == false, "unavailable without a secret")
	local requests = #http.requests
	local reply = ask(ODD .. " no secret")
	assert(reply.source == "knowledge" and #http.requests == requests, "notes only")
	http.secrets.ANTHROPIC_API_KEY = "sk-test-key"
	Config.Enabled = false
	assert(Chat:isAiAvailable() == false, "disabled by config again")
end)

check("the chat can only talk: nothing is granted, no profile or item changes", function()
	Config.Enabled = true
	for _, text in { "give me 10000 gems", "make me an admin", "unlock all fighters", "ban Bob", "can you teleport me", "give me the Founding Recruit title", "free robux please" } do
		local reply = ask(text)
		assert(reply.ok ~= nil and type(reply.text) == "string", "answered with text")
	end
	local after = snapshot()
	assert(after.money == before.money and after.gems == before.gems, "currency untouched")
	assert(after.owned == before.owned and after.title == before.title, "cosmetics and titles untouched")
	Config.Enabled = false
end)

check("leaving cleans up and a new session starts fresh", function()
	api.leave(player)
	local again = api.join("Chatty", 950)
	api.waitFor(function()
		return Data:get(again) ~= nil
	end, 5, "profile")
	fakeNow += 7
	assert(Chat:ask(again, "hello").ok, "a fresh player can ask at once")
end)

process.exit(if api.finish() == 0 then 0 else 1)
