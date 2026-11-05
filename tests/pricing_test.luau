-- Regional price level protection (P.S. 11.0), on the real PriceLevelService and TransferPolicy:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/pricing_test.luau build/game.rbxl
-- Fetch at join (validated, session only, never saved), the trade and gift rule tables, fresh
-- lookups at every decision, denial on any API failure or missing entry, client-supplied
-- levels ignored, messages that never reveal a level, and the transaction lock.
-- The game has no trading or gifting yet; this tests the gate they will use.

local process = require("@lune/process")
local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl")
local task, services, check = game.task, game.services, game.check
local world, Engine = game.world, game.Engine
local market = Engine.marketplace

local Policy = world.require(world.find("ServerScriptService.Server.Transfers.TransferPolicy"))
local Protocol = world.require(world.find("ReplicatedStorage.Shared.Protocol"))

local function setLevels(map)
	table.clear(market.priceLevels)
	for id, level in map do
		market.priceLevels[id] = level
	end
end
local function calls()
	return #market.priceLevelCalls
end
local function reset()
	setLevels({})
	market.priceLevelFailures = 0
	market.priceLevelOverride = nil
end

check("join: the level is fetched, validated and kept in memory only", function()
	setLevels({ [8001] = 640 })
	local before = calls()
	local p = game.join("Ann", 8001)
	assert(calls() > before, "GetUsersPriceLevelsAsync called at join")
	assert(services.PriceLevelService:joinLevel(p) == 640, "level kept for the session")
	task.wait(0.3)
	services.DataService:saveNow(p)
	local blob = ""
	for _, store in Engine.dataStores.saved do
		for _, value in store do
			blob ..= tostring(value)
		end
	end
	assert(not string.find(blob, "640", 1, true) and not string.find(blob, "riceLevel", 1, true), "never saved to a DataStore")
	game.leave(p)
	assert(services.PriceLevelService:joinLevel(p) == nil, "forgotten on leave")
end)

check("join: an API failure or a malformed reply stores nothing and does not break the join", function()
	market.priceLevelFailures = 1
	local p = game.join("Bo", 8002)
	assert(services.PriceLevelService:joinLevel(p) == nil, "no level after a failure")
	assert(services.DataService:get(p) ~= nil, "player still joined")
	for name, reply in {
		wrongUser = { { UserId = 1, PriceLevel = 500 } },
		zero = { { UserId = 8003, PriceLevel = 0 } },
		over = { { UserId = 8003, PriceLevel = 1001 } },
		fractional = { { UserId = 8003, PriceLevel = 500.5 } },
		stringLevel = { { UserId = 8003, PriceLevel = "500" } },
		empty = {},
		notATable = 5,
	} do
		market.priceLevelOverride = function()
			return reply
		end
		local q = game.join("Cy" .. name, 8003)
		assert(services.PriceLevelService:joinLevel(q) == nil, name .. " must not be stored")
		game.leave(q)
	end
	reset()
end)

check("trade rule table: only equal levels trade", function()
	local rows = { { 1000, 1000, true }, { 750, 750, true }, { 500, 1000, false }, { 1000, 500, false }, { 1, 1000, false }, { 1, 1, true } }
	for _, row in rows do
		setLevels({ [9001] = row[1], [9002] = row[2] })
		local d = Policy.canTrade(9001, 9002)
		assert(d.allowed == row[3], `trade {row[1]} vs {row[2]} expected {row[3]}`)
		if not d.allowed then
			assert(d.message == Policy.Messages.TradeDiffers, "friendly message")
			assert(not string.find(d.message, "%d"), "no level in the message")
		end
	end
end)

check("gift rule table: sender level must be at least the recipient's", function()
	local rows = { { 1000, 1000, true }, { 1000, 500, true }, { 750, 500, true }, { 500, 750, false }, { 500, 1000, false } }
	for _, row in rows do
		setLevels({ [9001] = row[1], [9002] = row[2] })
		local d = Policy.canGift(9001, 9002)
		assert(d.allowed == row[3], `gift {row[1]} to {row[2]} expected {row[3]}`)
		if not d.allowed then
			assert(not string.find(d.message, "%d"), "no level in the message")
		end
	end
end)

check("an offline recipient is supported by UserId alone", function()
	setLevels({ [9001] = 800, [424242] = 400 })
	assert(Policy.canGift(9001, 424242).allowed, "sender above an offline recipient")
	assert(not Policy.canGift(424242, 9001).allowed, "and not the other way")
end)

check("every decision looks the levels up again", function()
	setLevels({ [9001] = 1000, [9002] = 1000 })
	local start = calls()
	assert(Policy.canTrade(9001, 9002).allowed)
	setLevels({ [9001] = 1000, [9002] = 500 })
	assert(not Policy.canTrade(9001, 9002).allowed, "a level that changed since the last check is honoured")
	assert(Policy.canGift(9001, 9002).allowed)
	assert(calls() == start + 3, "one fresh lookup per decision")
	-- the level saved at join is never consulted
	setLevels({ [8001] = 640 })
	local p = game.join("Dee", 8001)
	setLevels({ [8001] = 100, [9002] = 900 })
	assert(not Policy.canGift(8001, 9002).allowed, "fresh 100 vs 900 blocks despite a stored 640")
	game.leave(p)
end)

check("API failure, a missing entry or a bad reply denies with the retry message", function()
	setLevels({ [9001] = 1000, [9002] = 1000 })
	market.priceLevelFailures = 2
	local trade, gift = Policy.canTrade(9001, 9002), Policy.canGift(9001, 9002)
	assert(not trade.allowed and trade.message == Policy.Messages.Retry, "trade denied on failure")
	assert(not gift.allowed and gift.message == Policy.Messages.Retry, "gift denied on failure")
	setLevels({ [9001] = 1000, [9002] = false })
	assert(not Policy.canTrade(9001, 9002).allowed, "missing recipient entry denies a trade")
	assert(not Policy.canGift(9001, 9002).allowed, "missing recipient entry denies a gift")
	setLevels({ [9001] = false, [9002] = 1000 })
	assert(not Policy.canGift(9001, 9002).allowed, "missing sender entry denies")
	for _, reply in { { { UserId = 9001, PriceLevel = 5000 }, { UserId = 9002, PriceLevel = 1000 } }, { { UserId = 9001, PriceLevel = 1000 }, { UserId = 777, PriceLevel = 1000 } }, "x" } do
		market.priceLevelOverride = function()
			return reply
		end
		assert(not Policy.canTrade(9001, 9002).allowed, "bad reply denies")
	end
	reset()
	for _, bad in { { 0, 5 }, { -1, 5 }, { 1.5, 5 }, { "9001", 5 }, { 9001, 9001 } } do
		assert(not Policy.canTrade(bad[1], bad[2]).allowed and not Policy.canGift(bad[1], bad[2]).allowed, "invalid ids deny")
	end
end)

check("client-supplied levels are ignored and no remote carries one", function()
	setLevels({ [9001] = 500, [9002] = 1000 })
	assert(not Policy.canGift(9001, 9002, { [9001] = 1000, [9002] = 1 }).allowed, "extra arguments change nothing")
	assert(not Policy.canTrade(9001, 9002, 1000, 1000).allowed, "extra arguments change nothing")
	local p = game.join("Eve", 9003)
	p:SetAttribute("PriceLevel", 1000)
	assert(services.PriceLevelService:joinLevel(p) == 1000, "joined with the engine's default 1000, from Roblox's reply")
	game.leave(p)
	for name in Protocol do
		assert(not string.find(string.lower(name), "pricelevel"), "no protocol table accepts price levels: " .. name)
	end
	local remotes = world.find("ReplicatedStorage.Remotes")
	for _, remote in remotes:GetChildren() do
		assert(not string.find(string.lower(remote.Name), "trade") and not string.find(string.lower(remote.Name), "gift"), "no trade or gift remote exists: " .. remote.Name)
	end
end)

check("the transaction lock prevents a double transfer and always releases", function()
	setLevels({ [9001] = 1000, [9002] = 1000, [9003] = 1000 })
	local moved = 0
	local release = Policy.acquire({ 9001, 9002 })
	assert(release, "first lock taken")
	assert(Policy.acquire({ 9002, 9003 }) == nil, "overlapping transfer refused")
	assert(not Policy.isLocked(9003), "a refused lock takes nothing")
	local ok, decision = Policy.run("gift", 9001, 9003, function()
		moved += 1
	end)
	assert(not ok and decision.code == "Busy" and moved == 0, "run refuses while locked")
	release()
	release()
	local ok2 = Policy.run("gift", 9001, 9002, function()
		moved += 1
		assert(Policy.isLocked(9001) and Policy.isLocked(9002), "locked during the transfer")
		return "done"
	end)
	assert(ok2 and moved == 1, "transfer ran once")
	assert(not Policy.isLocked(9001) and not Policy.isLocked(9002), "released after")
	local ok3, d3 = Policy.run("trade", 9001, 9002, function()
		error("boom")
	end)
	assert(not ok3 and d3.message == Policy.Messages.Retry and not Policy.isLocked(9001), "an error releases the lock and moves nothing")
	setLevels({ [9001] = 500, [9002] = 1000 })
	local ok4 = Policy.run("trade", 9001, 9002, function()
		moved += 1
	end)
	assert(not ok4 and moved == 1 and not Policy.isLocked(9002), "a denied transfer never runs and releases")
	-- A forgotten lock expires, so a crash can't freeze an account
	local stale = Policy.acquire({ 9003 }, os.clock() - Policy.LockSeconds - 1)
	assert(stale and Policy.acquire({ 9003 }), "expired lock can be taken again")
end)

local failed = game.finish()
game.stop()
process.exit(if failed > 0 then 1 else 0)
