-- Community like goals (CommunityService), simulated players:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/community_goals_test.luau build/game.rbxl
-- Only the owner (by UserId) can set the count; bad values are refused; a reached goal is given
-- once per player, also to a player who joins later; lowering the count takes nothing back; a
-- notice goes to everyone when a goal is reached; Jeffery's reminder fires once, after the third
-- finished match, and never mentions a personal reward.

local process = require("@lune/process")
local World = require("./smoke/World")

local api = World.start(process.args[1] or "build/game.rbxl")
local Engine, task = api.Engine, api.task
local world, services, check = api.world, api.services, api.check
local Data, Community, Overlord = services.DataService, services.CommunityService, services.OverlordService
local Config = world.require(world.find("ReplicatedStorage.Shared.Config.Community"))
local Cosmetics = world.require(world.find("ReplicatedStorage.Shared.Config.Cosmetics"))
local Knowledge = world.require(world.find("ReplicatedStorage.Shared.Config.JefferyKnowledge"))
local OWNER_ID = 8722595934
api.flatGround(0)

local function joined(name, userId)
	local player = api.join(name, userId)
	api.waitFor(function()
		return Data:get(player) ~= nil
	end, 5, name .. "'s profile")
	task.wait(0.4)
	return player
end
local function owns(player, id)
	return Data:get(player).cosmetics.owned[id] == true
end
local function gems(player)
	return Data:get(player).currencies.gems
end
local function claimed(player, id)
	return Data:get(player).community.goals[id] == true
end
local function set(player, likes)
	local result = Overlord:handle(player, "GoalsSet", { likes = likes })
	task.wait(0.4)
	return result
end

local owner = joined("AJKR", OWNER_ID)
local alice = joined("Alice", 7001)
local gemsBefore = gems(alice)

check("goal ids exist, rewards are real catalogue entries, no emoji or dashes in text", function()
	assert(#Config.LikeGoals >= 3)
	local last = 0
	for _, goal in Config.LikeGoals do
		assert(goal.likes > last, "ordered")
		last = goal.likes
		assert(not string.find(goal.text, "\u{2014}") and not string.find(goal.text, "\u{2013}"), "no dashes")
		if goal.reward.kind == "gems" then
			assert(goal.reward.amount > 0)
		else
			assert(Cosmetics.get(goal.reward.cosmetic), goal.id)
		end
	end
end)

check("a non-owner cannot set the count", function()
	local result = Overlord:handle(alice, "GoalsSet", { likes = 30000 })
	assert(not result.ok and result.code == "not_owner", tostring(result.code))
	local direct = Community:setLikes(alice, 30000)
	assert(not direct.ok and direct.code == "not_owner")
	assert(Community:goalsView().likes == 0, "unchanged")
	assert(not owns(alice, "title_supporter") and gems(alice) == gemsBefore)
	assert(Engine.readStore(Config.LikeStore.StoreName, Config.LikeStore.Key) == nil, "nothing stored")
end)

check("bad values are refused", function()
	for _, bad in { -1, 1.5, 1e9 + 1, 0 / 0, math.huge, "640", true, {}, 2 ^ 53 } do
		task.wait(Config.LikeStore.SetGap + 0.1)
		local result = Overlord:handle(owner, "GoalsSet", { likes = bad })
		assert(not result.ok and result.code == "bad_likes", `{tostring(bad)} -> {tostring(result.code)}`)
	end
	assert(Community:goalsView().likes == 0, "still zero")
end)

check("the owner is rate limited", function()
	task.wait(Config.LikeStore.SetGap + 0.1)
	assert(Overlord:handle(owner, "GoalsSet", { likes = 640 }).ok, "first save")
	local again = Overlord:handle(owner, "GoalsSet", { likes = 641 })
	assert(not again.ok and again.code == "rate_limited", tostring(again.code))
	local stored = Engine.readStore(Config.LikeStore.StoreName, Config.LikeStore.Key)
	assert(stored and stored.likes == 640 and stored.setAt > 0, "stored { likes, setAt }")
	assert(Community:goalsView().likes == 640)
	assert(not owns(alice, "title_supporter"), "640 reaches nothing")
end)

check("a reached goal is given once to everyone, with a notice, and again changes nothing", function()
	task.wait(Config.LikeStore.SetGap + 0.1)
	local mark = api.mark()
	assert(Overlord:handle(owner, "GoalsSet", { likes = 1000 }).ok)
	task.wait(0.6)
	assert(owns(alice, "title_supporter") and claimed(alice, "likes_1000"), "alice")
	assert(owns(owner, "title_supporter"), "the owner is a player too")
	assert(gems(alice) == gemsBefore, "gems goal not reached")
	local notices = api.sentSince(mark, "DataEvent", "Toast")
	local found = false
	for _, notice in notices do
		if notice.text == "Community goal reached: 1,000 likes. Everyone gets the Supporter title." then
			found = true
		end
	end
	assert(found, "notice text")
	-- the same count again: no second notice, no second grant
	task.wait(Config.LikeStore.SetGap + 0.1)
	local mark2 = api.mark()
	assert(Overlord:handle(owner, "GoalsSet", { likes = 1000 }).ok)
	task.wait(0.4)
	assert(#api.sentSince(mark2, "DataEvent", "Toast") == 0, "no repeat notice")
end)

check("gems go through once and a player who joins later gets every reached goal", function()
	task.wait(Config.LikeStore.SetGap + 0.1)
	assert(Overlord:handle(owner, "GoalsSet", { likes = 5000 }).ok)
	task.wait(0.6)
	assert(gems(alice) == gemsBefore + 150, "alice gems " .. gems(alice))
	local late = joined("Late", 7002)
	assert(owns(late, "title_supporter"), "late title")
	assert(claimed(late, "likes_1000") and claimed(late, "likes_5000"), "late claims")
	assert(gems(late) >= 150, "late gems")
	local lateGems = gems(late)
	-- a rejoin does not pay again
	api.leave(late)
	task.wait(0.6)
	local back = joined("Late", 7002)
	assert(gems(back) == lateGems, `rejoin gems {gems(back)} vs {lateGems}`)
	assert(owns(back, "title_supporter"))
	api.leave(back)
	task.wait(0.4)
end)

check("lowering the count takes nothing back", function()
	task.wait(Config.LikeStore.SetGap + 0.1)
	local before = gems(alice)
	assert(Overlord:handle(owner, "GoalsSet", { likes = 10 }).ok)
	task.wait(0.5)
	assert(Community:goalsView().likes == 10)
	assert(owns(alice, "title_supporter") and claimed(alice, "likes_5000") and gems(alice) == before, "kept")
	-- raising it again does not pay twice
	task.wait(Config.LikeStore.SetGap + 0.1)
	assert(Overlord:handle(owner, "GoalsSet", { likes = 6000 }).ok)
	task.wait(0.5)
	assert(gems(alice) == before, "no second payment")
end)

check("the top goal gives the aura, and a message from another server is applied", function()
	local cloud = Engine.cloud
	local other = cloud:server("job-other")
	other.MessagingService:PublishAsync(Config.LikeStore.Topic, { likes = 26000, setAt = os.time() + 50 })
	task.wait(0.5)
	assert(Community:goalsView().likes == 26000, "applied")
	assert(owns(alice, "aura_crowd_glow"), "aura given")
	-- junk messages are ignored
	for _, junk in { { likes = -4, setAt = 1 }, { likes = "x" }, "text", { likes = 2e9, setAt = 5 } } do
		other.MessagingService:PublishAsync(Config.LikeStore.Topic, junk)
	end
	task.wait(0.4)
	assert(Community:goalsView().likes == 26000, "junk ignored")
end)

check("the Jeffery reminder fires once, after the third match, and promises nothing personal", function()
	services.TutorialService.isBusy = function()
		return false
	end
	local bob = joined("Bob", 7100)
	local mark = api.mark()
	for matches = 1, 2 do
		Data:update(bob, function(p)
			p.stats.matches = matches
		end)
		Community:onMatchFinished(bob)
	end
	task.wait(0.3)
	assert(#api.sentSince(mark, "DataEvent", "Hint", bob) == 0, "not before the third match")
	Data:update(bob, function(p)
		p.stats.matches = 3
	end)
	Community:onMatchFinished(bob)
	task.wait(0.3)
	local hints = api.sentSince(mark, "DataEvent", "Hint", bob)
	assert(#hints == 1 and hints[1].id == "like_goals", "said once, got " .. #hints)
	assert(Data:get(bob).community.likeNote, "flag saved")
	for matches = 4, 8 do
		Data:update(bob, function(p)
			p.stats.matches = matches
		end)
		Community:onMatchFinished(bob)
	end
	task.wait(0.3)
	assert(#api.sentSince(mark, "DataEvent", "Hint", bob) == 1, "never again")
	local text = string.lower(hints[1].text)
	assert(string.find(text, "every player", 1, true) and string.find(text, "community goal", 1, true), text)
	for _, banned in { "you get", "you will get", "your reward", "thank you with", "in return", "as a reward", "earn", "\u{2014}" } do
		assert(not string.find(text, banned, 1, true), "promises: " .. banned)
	end
	-- hints switched off: nothing is said and nothing is used up
	local carol = joined("Carol", 7101)
	Data:update(carol, function(p)
		p.settings.hints = false
		p.stats.matches = 5
	end)
	mark = api.mark()
	Community:onMatchFinished(carol)
	task.wait(0.2)
	assert(#api.sentSince(mark, "DataEvent", "Hint", carol) == 0 and not Data:get(carol).community.likeNote)
	api.leave(bob)
	api.leave(carol)
end)

check("Jeffery answers the question honestly", function()
	local entry
	for _, e in Knowledge.Entries do
		if e.id == "likegoals" then
			entry = e
		end
	end
	assert(entry, "entry")
	local reply = services.JefferyChatService:ask(owner, "how do I get rewards for liking the game")
	local text = string.lower(reply.text or reply.answer or "")
	assert(string.find(text, "every player", 1, true), text)
	assert(string.find(text, "nobody gets a reward just for liking", 1, true), text)
end)

check("old profiles without the new fields still load", function()
	local Schema = world.require(world.find("ReplicatedStorage.Shared.Data.Schema"))
	local profile = (Schema.migrate({ community = { referredBy = 5 } }))
	assert(next(profile.community.goals) == nil and profile.community.likeNote == false)
	local again = (Schema.migrate({ community = { goals = { likes_1000 = true, bad = 3 }, likeNote = true } }))
	assert(again.community.goals.likes_1000 and not again.community.goals.bad and again.community.likeNote)
end)

local failed = api.finish()
process.exit(if failed > 0 then 1 else 0)
