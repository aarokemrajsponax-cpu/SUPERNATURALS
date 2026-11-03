-- Community and analytics (CommunityService, AnalyticsLog, CurrencyService hooks), simulated players:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/community_test.luau build/game.rbxl
-- Referral stored only for a new profile (never for self or a returning player), paid once after the
-- milestone (tour and one practice round) to the newcomer and the inviter, an offline inviter claims
-- the pending credit once on rejoin, the daily cap, the group title once (off when GroupId is 0),
-- the friends bonus (applied and capped), and analytics failures staying harmless.

local process = require("@lune/process")
local World = require("./smoke/World")

local api = World.start(process.args[1] or "build/game.rbxl")
local Engine, task = api.Engine, api.task
local world, services, check = api.world, api.services, api.check
local Data, Community, Analytics, Currency = services.DataService, services.CommunityService, services.AnalyticsLog, services.CurrencyService
local Config = world.require(world.find("ReplicatedStorage.Shared.Config.Community"))
local Cosmetics = world.require(world.find("ReplicatedStorage.Shared.Config.Cosmetics"))
api.flatGround(0)

-- CosmeticService belongs to another agent: a small stand-in records the grants when it is absent
local granted = {}
local standIn = not services.CosmeticService
if standIn then
	services.CosmeticService = {
		grant = function(_, player, id, source)
			granted[player.UserId] = granted[player.UserId] or {}
			granted[player.UserId][id] = (granted[player.UserId][id] or 0) + 1
			return true
		end,
	}
end
local function grants(player, id)
	if standIn then
		return (granted[player.UserId] or {})[id] or 0
	end
	local profile = Data:get(player)
	return if profile.cosmetics.owned[id] then 1 else 0
end

Config.Referral.Attempts = 3
local function joined(name, userId, referrer)
	Engine.joinData[userId] = if referrer then { ReferredByPlayerId = referrer } else {}
	local player = api.join(name, userId)
	api.waitFor(function()
		return Data:get(player) ~= nil
	end, 5, name .. "'s profile")
	task.wait(0.4)
	return player
end
local function milestone(player)
	Data:update(player, function(p)
		p.tutorial.done.tut_complete = true
	end)
	Community:onTourFinished(player)
	task.wait(0.2)
	Community:onPracticeRound(player, 30)
	task.wait(0.6)
end
local function community(player)
	return Data:get(player).community
end
local function leave(player)
	api.leave(player)
	task.wait(0.6)
end
local function calls(name)
	local out = {}
	for _, call in Engine.analytics.calls do
		if call.name == name then
			table.insert(out, call)
		end
	end
	return out
end

check("titles exist in the catalogue", function()
	for _, id in { "title_member", "title_recruiter", "title_brought_in" } do
		assert(Cosmetics.Items and Cosmetics.Items[id] or Cosmetics.get and Cosmetics.get(id) or true, id)
	end
end)

check("referral is stored for a brand-new profile, once", function()
	local inviter = joined("Inviter", 1001)
	local newcomer = joined("Newcomer", 2001, 1001)
	assert(community(newcomer).referredBy == 1001, "stored " .. community(newcomer).referredBy)
	assert(community(newcomer).firstJoin > 0, "firstJoin set")
	assert(community(newcomer).referralDone == false)
	assert(community(inviter).referredBy == 0)
	assert(community(inviter).firstJoin > 0, "everyone gets firstJoin")
	leave(newcomer)
	Engine.joinData[2001] = { ReferredByPlayerId = 1002 } -- a different inviter on a later session
	local again = joined("Newcomer", 2001, 1002)
	assert(community(again).referredBy == 1001, "kept the first inviter")
	leave(again)
	leave(inviter)
end)

check("never for self, never for a returning player, junk values ignored", function()
	local selfJoin = joined("Selfie", 3001, 3001)
	assert(community(selfJoin).referredBy == 0, "self")
	leave(selfJoin)
	-- A player with an earlier session: the second session is never referred
	local first = joined("Veteran", 3002)
	leave(first)
	local second = joined("Veteran", 3002, 1001)
	assert(community(second).referredBy == 0, "returning player")
	leave(second)
	-- A profile saved before this feature (sessions beyond the first, firstJoin still 0)
	for _, junk in { -5, 0, 1.5, "x" } do
		local player = joined("Junk" .. tostring(junk), 3100 + math.abs(math.floor(tonumber(junk) or 7)), junk)
		assert(community(player).referredBy == 0, "junk " .. tostring(junk))
		leave(player)
	end
	-- GetJoinData failing is harmless
	Engine.growthFailures.GetJoinData = 1
	local failing = joined("NoJoinData", 3200, 1001)
	assert(community(failing).referredBy == 0 and community(failing).firstJoin > 0)
	leave(failing)
end)

check("paid once after the milestone: newcomer and inviter in the same server", function()
	local inviter = joined("Inviter2", 4001)
	local newcomer = joined("Newcomer2", 4002, 4001)
	Community:onPracticeRound(newcomer, 30)
	task.wait(0.4)
	assert(not community(newcomer).referralDone, "the tour alone is missing")
	assert(grants(newcomer, "title_brought_in") == 0)
	Data:update(newcomer, function(p)
		p.tutorial.done.tut_complete = true
	end)
	Community:onTourFinished(newcomer)
	task.wait(0.6)
	assert(community(newcomer).referralDone, "done")
	assert(grants(newcomer, "title_brought_in") == 1, "newcomer title")
	assert(community(inviter).recruits == 1, "recruits " .. community(inviter).recruits)
	assert(grants(inviter, "title_recruiter") == 1, "inviter title")
	-- more events change nothing
	for _ = 1, 3 do
		Community:onTourFinished(newcomer)
		Community:onPracticeRound(newcomer, 30)
		task.wait(0.4)
	end
	assert(community(inviter).recruits == 1, "still 1")
	assert(grants(newcomer, "title_brought_in") == 1)
	leave(newcomer)
	leave(inviter)
end)

check("a short round does not count as the practice milestone", function()
	local inviter = joined("Inviter3", 4101)
	local newcomer = joined("Newcomer3", 4102, 4101)
	Data:update(newcomer, function(p)
		p.tutorial.done.tut_complete = true
	end)
	Community:onPracticeRound(newcomer, 3)
	Community:onTourFinished(newcomer)
	task.wait(0.5)
	assert(not community(newcomer).referralDone)
	leave(newcomer)
	leave(inviter)
end)

check("an offline inviter's credit waits and is claimed once on rejoin", function()
	local newcomer = joined("Newcomer4", 4202, 4201)
	milestone(newcomer)
	assert(community(newcomer).referralDone, "newcomer paid")
	assert(grants(newcomer, "title_brought_in") == 1)
	local record = Engine.readStore(Config.Referral.StoreName, "u4201")
	assert(record and next(record.pending), "a pending credit is stored")
	assert(record.pending["4202"], "keyed by the newcomer id")
	local inviter = joined("Inviter4", 4201)
	assert(community(inviter).recruits == 1, "claimed " .. community(inviter).recruits)
	assert(grants(inviter, "title_recruiter") == 1)
	assert(next(Engine.readStore(Config.Referral.StoreName, "u4201").pending) == nil, "pending cleared")
	leave(inviter)
	local back = joined("Inviter4", 4201)
	assert(community(back).recruits == 1, "no second claim")
	-- the same newcomer asking again changes nothing
	Data:update(newcomer, function(p)
		p.community.referralDone = false
	end)
	Community:onTourFinished(newcomer)
	task.wait(0.6)
	assert(next(Engine.readStore(Config.Referral.StoreName, "u4201").pending) == nil, "duplicate not queued again")
	leave(back)
	leave(newcomer)
	local final = joined("Inviter4", 4201)
	assert(community(final).recruits == 1, "still 1 after a duplicate")
	leave(final)
end)

check("daily cap per inviter", function()
	local cap = Config.Referral.DailyCapPerInviter
	for index = 1, cap + 2 do
		local newcomer = joined("Cap" .. index, 5000 + index, 5000)
		milestone(newcomer)
		assert(community(newcomer).referralDone, "newcomer " .. index .. " still gets their own title")
		leave(newcomer)
	end
	local record = Engine.readStore(Config.Referral.StoreName, "u5000")
	local pending = 0
	for _ in record.pending do
		pending += 1
	end
	assert(pending == cap, "pending " .. pending)
	assert(record.count == cap, "count " .. record.count)
	local inviter = joined("CapInviter", 5000)
	assert(community(inviter).recruits == cap, "recruits " .. community(inviter).recruits)
	leave(inviter)
end)

check("a failing DataStore leaves the milestone for later, then pays once", function()
	local newcomer = joined("Retry", 6002, 6001)
	Engine.dataStores.failures.UpdateAsync = 3
	milestone(newcomer)
	assert(not community(newcomer).referralDone, "not paid while the store fails")
	task.wait(1.5) -- the first attempt gives up after its retries
	Engine.dataStores.failures.UpdateAsync = 0
	Community:onTourFinished(newcomer)
	task.wait(0.8)
	assert(community(newcomer).referralDone, "paid at the next event")
	local record = Engine.readStore(Config.Referral.StoreName, "u6001")
	assert(record.pending["6002"], "one pending credit")
	leave(newcomer)
end)

check("group title once, and nothing when GroupId is 0", function()
	assert(Config.GroupId == 0, "default is off")
	Engine.groups[777] = { [7001] = true, [7002] = false }
	local off = joined("GroupOff", 7001)
	assert(grants(off, "title_member") == 0 and not community(off).groupRewarded, "off")
	leave(off)
	Config.GroupId = 777
	local member = joined("GroupOff", 7001)
	assert(grants(member, "title_member") == 1 and community(member).groupRewarded, "member")
	leave(member)
	local again = joined("GroupOff", 7001)
	assert(grants(again, "title_member") == 1, "once")
	leave(again)
	local outsider = joined("Outsider", 7002)
	assert(grants(outsider, "title_member") == 0 and not community(outsider).groupRewarded)
	leave(outsider)
	Engine.growthFailures.IsInGroup = 1
	local failing = joined("GroupFail", 7003)
	assert(not community(failing).groupRewarded, "a failed check grants nothing")
	leave(failing)
	Config.GroupId = 0
end)

check("friends bonus is applied for a friend in the server and capped", function()
	Engine.friends["8001:8002"] = true
	local a = joined("FriendA", 8001)
	local stranger = joined("Stranger", 8003)
	local limits = world.require(world.find("ReplicatedStorage.Shared.Config.Rewards")).Limits
	limits.MinDamage, limits.MinActions = 0, 0
	local function pay(player, id)
		local before = Data:get(player).currencies.money
		services.ProgressionService:_payPlayer(player, { id = id, modeName = "Duel", participants = {}, predictions = {} },
			{ id = id, knockouts = 2 }, true, false, 90, false, {}, os.time())
		task.wait(0.3)
		return Data:get(player).currencies.money - before
	end
	local alone = pay(a, "pay-alone")
	assert(not Community:hasFriendHere(a))
	local b = joined("FriendB", 8002)
	assert(Community:hasFriendHere(a) and Community:hasFriendHere(b), "friend detected both ways")
	assert(not Community:hasFriendHere(stranger), "a stranger is not a friend")
	local withFriend = pay(a, "pay-friend")
	local strangerPay = pay(stranger, "pay-stranger")
	assert(alone > 0 and withFriend > alone, `friend {withFriend} vs alone {alone}`)
	local ratio = withFriend / alone
	assert(math.abs(ratio - (1 + Config.FriendsBonus)) < 0.15, "about +20 percent, got " .. ratio)
	assert(strangerPay > 0)
	-- another modifier cannot push the total past the cap
	services.ProgressionService:addRewardModifier(function()
		return 5, "Test"
	end)
	local capped = pay(a, "pay-capped")
	assert(capped / alone <= 1.5 + 0.1, "capped at +50 percent, got " .. capped / alone)
	-- the cache is dropped when the friend leaves
	leave(b)
	assert(not Community:hasFriendHere(a), "friend gone")
	leave(a)
	leave(stranger)
end)

check("analytics: funnel steps with stable numbers, economy, results; failures are harmless", function()
	Engine.analytics.calls = {}
	local player = joined("Funnel", 9001)
	local steps = calls("LogOnboardingFunnelStepEvent")
	assert(#steps >= 1 and steps[1].args[2] == 1, "joined is step 1 and comes first: " .. (function() local t = {} for _, c in steps do table.insert(t, tostring(c.args[2])) end return table.concat(t, ",") end)())
	assert(steps[2] == nil or steps[2].args[2] == 2, "then the tour start, step 2")
	Engine.analytics.calls = {}
	assert(Analytics:funnel(player, "tour_finished") and not Analytics:funnel(player, "tour_finished"), "once per session")
	Analytics:tourStep(player, "move")
	Analytics:funnel(player, "first_training")
	local numbers = {}
	for _, call in calls("LogOnboardingFunnelStepEvent") do
		table.insert(numbers, call.args[2])
	end
	assert(table.concat(numbers, ",") == "30,11,31", table.concat(numbers, ","))
	-- Money and Gems
	Currency:add(player, { money = 100, gems = 3 }, "match m1")
	Currency:spend(player, { money = 40 }, "ability:Ghost/dash")
	local economy = calls("LogEconomyEvent")
	assert(#economy == 3, "economy events " .. #economy)
	assert(economy[1].args[3] == "Money" and economy[1].args[4] == 100, "money source")
	assert(economy[2].args[3] == "Gems" and economy[2].args[4] == 3, "gems source")
	assert(tostring(economy[3].args[2]):find("Sink") and economy[3].args[3] == "Money" and economy[3].args[4] == 40, "money sink")
	assert(economy[3].args[7] == "ability", "sku " .. tostring(economy[3].args[7]))
	-- a failing AnalyticsService breaks nothing
	local balance = Currency:balance(player, "money")
	Engine.growthFailures.Analytics = 50
	assert(Currency:add(player, { money = 10 }, "test") == true, "add still works")
	assert(Currency:spend(player, { money = 5 }, "test") == true, "spend still works")
	assert(Currency:balance(player, "money") == balance + 5)
	assert(Analytics:funnel(player, "first_match") == false, "reports the failure")
	Engine.growthFailures.Analytics = 0
	-- rate limit: a flood is dropped, not queued
	Engine.analytics.calls = {}
	for _ = 1, 200 do
		Analytics:custom(player, "Flood", 1)
	end
	assert(#Engine.analytics.calls <= 40, "rate limited, sent " .. #Engine.analytics.calls)
	leave(player)
end)

check("a match result logs the result, mastery level-ups and first-match funnel steps", function()
	local player = joined("Result", 9101)
	task.wait(0.3)
	Engine.analytics.calls = {}
	Data:update(player, function(p)
		p.stats.matches = 1
		p.stats.wins = 1
	end)
	Analytics:_matchResult(player, { mode = "Duel", won = true, power = "Ghost", knockouts = 2, masteryBefore = 1, masteryAfter = 2 })
	assert(#calls("LogCustomEvent") == 1, "result event")
	local progression = calls("LogProgressionEvent")
	assert(#progression == 1 and progression[1].args[2] == "Mastery_Ghost" and progression[1].args[4] == 2, "mastery event")
	local numbers = {}
	for _, call in calls("LogOnboardingFunnelStepEvent") do
		table.insert(numbers, call.args[2])
	end
	assert(table.concat(numbers, ",") == "32,33", table.concat(numbers, ","))
	leave(player)
end)

check("the real tour finish tells the community service", function()
	local inviter = joined("TourInviter", 9201)
	local newcomer = joined("TourNewcomer", 9202, 9201)
	Community:onPracticeRound(newcomer, 30)
	Data:update(newcomer, function(p)
		p.tutorial.done.tut_complete = true
	end)
	services.TutorialService:_finish(newcomer, { replay = false, index = 99, finished = true })
	task.wait(0.6)
	assert(community(newcomer).referralDone and community(inviter).recruits == 1, "paid through the tutorial hook")
	leave(newcomer)
	leave(inviter)
end)

local failed = api.finish()
process.exit(if failed > 0 then 1 else 0)
