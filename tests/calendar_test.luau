-- Holiday gift calendars and fighter trials, end to end on the real server services (stand-in engine):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/calendar_test.luau build/game.rbxl
-- Claims on the right days, the catch-up window, double claims refused, milestones and the
-- perfect prize once, rewards only after the save, trials that allow Duel and expire (never
-- mid-match), trial products idempotent by PurchaseId, and schema repair of junk.

local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local World = require("./smoke/World")

local TRIAL_IDS = { TrialCorruption = 5701, TrialSyntax = 5702, TrialAdmin = 5703 }
local game = World.start(process.args[1] or "build/game.rbxl", function(setup)
	local Monetization = setup.world.require(setup.world.find("ReplicatedStorage.Shared.Config.Monetization"))
	for key, id in TRIAL_IDS do
		Monetization.Products[key].id = id
	end
end)
local task, services, check, request = game.task, game.services, game.check, game.request
local world, Engine = game.world, game.Engine
local Decision = roblox.Enum.ProductPurchaseDecision

local function find(path)
	return world.find(path)
end
local Calendars = world.require(find("ReplicatedStorage.Shared.Config.Calendars"))
local Cosmetics = world.require(find("ReplicatedStorage.Shared.Config.Cosmetics"))
local Monetization = world.require(find("ReplicatedStorage.Shared.Config.Monetization"))
local Protocol = world.require(find("ReplicatedStorage.Shared.Protocol"))
local Schema = world.require(find("ReplicatedStorage.Shared.Data.Schema"))
local Powers = world.require(find("ReplicatedStorage.Shared.Powers"))

Monetization.PromptCooldown = 0
local Data, Calendar, Power, Currency = services.DataService, services.CalendarService, services.PowerService, services.CurrencyService
local harvest, advent = Calendars.List.harvest_2026, Calendars.List.advent_2026

local function waitProfile(player)
	game.waitFor(function()
		return Data:get(player) ~= nil
	end, 5, "profile")
end
local function join(name, userId)
	local player = game.join(name, userId)
	waitProfile(player)
	return player
end
-- A time inside day `day` of a calendar
local function at(calendar, day, offset)
	return calendar.startsAt + (day - 1) * 86400 + (offset or 3600)
end
local function owned(player, id)
	return Data:get(player).cosmetics.owned[id] == true
end
local function entry(player, calendar)
	return Data:get(player).calendars[calendar.id]
end

-- Config ------------------------------------------------------------------------------------

check("calendar config: dates, day counts, gifts, trials, cosmetics and perfect sets", function()
	assert(harvest.days == 22 and advent.days == 25, "5 to 26 November is 22 days, 1 to 25 December is 25")
	assert(harvest.startsAt == 1793836800 and advent.startsAt == 1796083200, "UTC midnight starts")
	assert(Calendars.dayStart(harvest, 22) == 1795651200 and Calendars.dayStart(advent, 25) == 1798156800, "the last days are 26 November and 25 December")
	assert(Calendars.CatchUpDays == 1, "one day of catch-up")
	for _, calendar in { harvest, advent } do
		local trials = {}
		local lastMoney = 0
		for day = 1, calendar.days do
			local gift = calendar.gifts[day]
			assert(gift.money >= 100 and gift.money <= 600, "money 100 to 600 on day " .. day)
			assert(gift.money >= lastMoney, "money never drops")
			lastMoney = gift.money
			if gift.trial then
				table.insert(trials, gift.trial)
				assert(Calendars.TrialPowers[gift.trial] and Powers.isPremium(gift.trial), "premium fighters only")
			end
			if gift.gems then
				assert(gift.gems > 0 and gift.gems <= 25, "small gem gifts")
			end
		end
		assert(calendar.gifts[calendar.days].money == 600 and calendar.gifts[1].money == 100, "100 at the start, 600 at the end")
		table.sort(trials)
		assert(table.concat(trials, ",") == "Admin,Corruption,Syntax", "one trial each for Corruption, Syntax and Admin")
		for _, id in Calendars.cosmeticIds(calendar) do
			local item = Cosmetics.get(id)
			assert(item and item.source == "calendar" and item.calendar == calendar.id, "cosmetic " .. id)
		end
		assert(#calendar.perfect.cosmetics == 3, "an aura, a knockout effect and a title")
		local kinds = {}
		for _, id in calendar.perfect.cosmetics do
			kinds[Cosmetics.get(id).kind] = true
		end
		assert(kinds.aura and kinds.knockout and kinds.title, "perfect set kinds")
	end
	assert(Cosmetics.get(harvest.perfect.cosmetics[3]).text == "Perfect Harvest" and Cosmetics.get(advent.perfect.cosmetics[3]).text == "Perfect Advent", "titles")
	-- Calendar-only: no shop pass lists a calendar cosmetic
	for _, pass in Monetization.Passes do
		for _, id in pass.cosmetics or {} do
			assert(Cosmetics.get(id).source ~= "calendar", "calendar items are never sold")
		end
	end
end)

check("which calendar runs and which day is today", function()
	assert(Calendars.current(harvest.startsAt - 1) == nil, "nothing before 5 November")
	local calendar, today = Calendars.current(at(harvest, 1))
	assert(calendar == harvest and today == 1)
	calendar, today = Calendars.current(at(harvest, 22, 86399 - 3600))
	assert(calendar == harvest and today == 22)
	calendar, today = Calendars.current(at(harvest, 23))
	assert(calendar == harvest and today == 23, "the catch-up day after the last day")
	assert(Calendars.current(at(harvest, 24)) == nil, "closed after the catch-up day")
	assert(Calendars.current(at(advent, 3)) == advent)
	assert(Calendars.nextAfter(harvest.startsAt - 5) == harvest and Calendars.nextAfter(at(harvest, 24)) == advent and Calendars.nextAfter(at(advent, 30)) == nil)
end)

-- Claims ------------------------------------------------------------------------------------

local ann = join("Ann", 9101)

check("claims need a running calendar and a day that has opened", function()
	local ok, reason = Calendar:claim(ann, 1, harvest.startsAt - 100)
	assert(not ok and string.find(reason, "No gift calendar", 1, true), "before the calendar: " .. tostring(reason))
	ok, reason = Calendar:claim(ann, 2, at(harvest, 1))
	assert(not ok and string.find(reason, "not ready", 1, true), "tomorrow's gift: " .. tostring(reason))
	for _, junk in { 0, -1, 1.5, 23, 99, "1", {}, 0 / 0, math.huge } do
		ok = Calendar:claim(ann, junk, at(harvest, 5))
		assert(not ok, "junk day refused: " .. tostring(junk))
	end
	assert(next(Data:get(ann).calendars) == nil, "nothing was written")
end)

check("a claim on the right day pays Money, writes the profile and refuses a second claim", function()
	local before = Currency:balance(ann, "money")
	local ok, reason = Calendar:claim(ann, nil, at(harvest, 1))
	assert(ok, "day 1 claimed: " .. tostring(reason))
	assert(Currency:balance(ann, "money") == before + harvest.gifts[1].money, "day 1 pays its Money")
	assert(entry(ann, harvest).claimed["1"] == true)
	local again, why = Calendar:claim(ann, 1, at(harvest, 1, 7200))
	assert(not again and string.find(why, "already claimed", 1, true), "double claim refused: " .. tostring(why))
	assert(Currency:balance(ann, "money") == before + harvest.gifts[1].money, "no second payout")
end)

check("catch-up: a missed day can be claimed the next day, not two days later", function()
	-- Day 2 missed, claimed on day 3
	local ok = Calendar:claim(ann, 2, at(harvest, 3))
	assert(ok, "day 2 on day 3 (CatchUpDays = 1)")
	-- Day 3 and day 4 skipped; on day 5 day 3 is two days late
	local late, why = Calendar:claim(ann, 3, at(harvest, 5))
	assert(not late and string.find(why, "no longer", 1, true), "two days late: " .. tostring(why))
	assert(Calendar:claim(ann, 4, at(harvest, 5)), "yesterday still works")
	assert(Calendar:claim(ann, 5, at(harvest, 5)), "today works")
	-- Strict mode
	Calendars.CatchUpDays = 0
	local strictOk = Calendar:claim(ann, 6, at(harvest, 7))
	assert(not strictOk, "strict: only its own day")
	Calendars.CatchUpDays = 1
	assert(Calendar:claim(ann, 6, at(harvest, 7)), "back to one day of catch-up")
end)

check("a milestone is given once, at the claimed-day count (not the day number)", function()
	local e = entry(ann, harvest)
	assert(Calendars.countClaimed(e.claimed) == 5, "five days claimed")
	assert(e.milestones["5"] == true and owned(ann, "cal_hv_ms_title_guest"), "the 5 day milestone")
	assert(not owned(ann, "cal_hv_ms_plate_long_table"), "10 is not reached")
	local money = Currency:balance(ann, "money")
	Calendar:claim(ann, 7, at(harvest, 7))
	assert(Currency:balance(ann, "money") == money + harvest.gifts[7].money, "no repeated milestone Money")
end)

check("a trial day gives the fighter ticket through PowerService", function()
	assert(Calendar:claim(ann, 6, at(harvest, 6)) == false, "already claimed above")
	local day = 6
	assert(harvest.gifts[day].trial == "Corruption")
	local bob = join("Bob", 9102)
	assert(Calendar:claim(bob, 6, at(harvest, 6)), "Bob claims the Corruption day")
	assert(Power:trialEndsAt(bob, "Corruption") ~= nil, "ticket running")
	local left = Power:trialEndsAt(bob, "Corruption") - os.time()
	assert(left > 23.9 * 3600 and left <= 24 * 3600, "24 hours")
	assert(Power:owns(bob, "Corruption"), "counts as owned")
	assert(not Power:owns(bob, "Syntax"), "only that fighter")
end)

check("rewards come after the save: a failed save grants nothing and loses nothing", function()
	local cat = join("Cat", 9103)
	local original = Data.saveNow
	local order = {}
	Data.saveNow = function(self, player)
		table.insert(order, "save:" .. Currency:balance(player, "money"))
		return false
	end
	local before = Currency:balance(cat, "money")
	local ok, reason = Calendar:claim(cat, 1, at(harvest, 1))
	assert(not ok and string.find(reason, "save", 1, true), "refused: " .. tostring(reason))
	assert(#order == 1 and order[1] == "save:" .. before, "the save came before any payout")
	assert(Currency:balance(cat, "money") == before, "no Money")
	assert(entry(cat, harvest) == nil or entry(cat, harvest).claimed["1"] == nil, "claim rolled back")
	Data.saveNow = function(self, player)
		table.insert(order, "save2:" .. Currency:balance(player, "money"))
		return true
	end
	order = {}
	assert(Calendar:claim(cat, 1, at(harvest, 1)), "the retry works")
	assert(order[1] == "save2:" .. before, "money still unpaid when the claim was saved: " .. tostring(order[1]))
	Data.saveNow = original
	assert(Currency:balance(cat, "money") == before + harvest.gifts[1].money)
end)

check("saving off: gifts are paused, not lost", function()
	local dan = join("Dan", 9104)
	local original = Data.isPersistent
	Data.isPersistent = function()
		return false
	end
	local ok, reason = Calendar:claim(dan, 1, at(harvest, 1))
	Data.isPersistent = original
	assert(not ok and string.find(reason, "paused", 1, true), tostring(reason))
	assert(Calendar:claim(dan, 1, at(harvest, 1)), "claims work again")
end)

check("every day claimed gives the perfect set once, and a server line", function()
	local eve = join("Eve", 9105)
	local lines = {}
	local original = services.AchievementService.announce
	services.AchievementService.announce = function(self, player, line)
		table.insert(lines, line)
		return true
	end
	for day = 1, harvest.days do
		local ok, reason = Calendar:claim(eve, day, at(harvest, day))
		assert(ok, `day {day}: {reason}`)
		if day < harvest.days then
			assert(not owned(eve, harvest.perfect.cosmetics[1]), "not perfect before the last day")
		end
	end
	services.AchievementService.announce = original
	assert(entry(eve, harvest).perfect == true, "perfect recorded")
	for _, id in harvest.perfect.cosmetics do
		assert(owned(eve, id), "perfect item " .. id)
	end
	for _, milestone in harvest.milestones do
		assert(owned(eve, milestone.cosmetic), "milestone " .. milestone.count)
	end
	assert(#lines == 1 and string.find(lines[1], "Perfect Harvest", 1, true), "one server-wide line: " .. tostring(lines[1]))
	-- Nothing more can be claimed, and nothing pays twice
	local money = Currency:balance(eve, "money")
	assert(not Calendar:claim(eve, 22, at(harvest, 22)))
	assert(Currency:balance(eve, "money") == money)
	-- Thanksgiving day itself carries its own title
	assert(owned(eve, "cal_hv_title_thanks"), "day 22 title")
	-- All three trials landed
	for _, powerId in { "Corruption", "Syntax", "Admin" } do
		assert(Power:trialEndsAt(eve, powerId) ~= nil, powerId .. " trial")
	end
end)

check("a player who missed days is still rewarded by days claimed (10 days: two milestones)", function()
	local fay = join("Fay", 9106)
	for day = 1, 20, 2 do
		assert(Calendar:claim(fay, day, at(harvest, day)), "day " .. day)
	end
	local e = entry(fay, harvest)
	assert(Calendars.countClaimed(e.claimed) == 10 and e.milestones["5"] and e.milestones["10"] and not e.milestones["15"], "5 and 10 reached")
	assert(owned(fay, "cal_hv_ms_plate_long_table") and not e.perfect and not owned(fay, harvest.perfect.cosmetics[1]), "no perfect set")
end)

check("the Advent Calendar works the same way and keeps its own record", function()
	local gus = join("Gus", 9107)
	assert(Calendar:claim(gus, 1, at(advent, 1)))
	assert(entry(gus, advent).claimed["1"] and entry(gus, harvest) == nil, "separate records")
	assert(not Calendar:claim(gus, 26, at(advent, 25)), "no day 26")
	local calendar, today = Calendars.current(at(advent, 25))
	assert(calendar == advent and today == 25)
	assert(Calendar:claim(gus, 25, at(advent, 25)), "Christmas Day is claimable on Christmas Day")
	assert(owned(gus, "cal_ad_title_midwinter"), "its title")
end)

check("the State reply and the remote: rate limited, junk ignored", function()
	local hal = join("Hal", 9108)
	local original = harvest.startsAt
	harvest.startsAt = os.time() - 5000
	local mark = game.mark()
	request("ShopRequest", hal, Protocol.ShopAction.GiftState)
	task.wait(0.05)
	local replies = game.sentSince(mark, "DataEvent", "Calendar", hal)
	assert(#replies >= 1 and replies[#replies].kind == "State" and replies[#replies].calendar == "harvest_2026" and replies[#replies].today == 1, "State sent")
	assert(replies[#replies].catchUp == 1 and replies[#replies].count == 0)
	request("ShopRequest", hal, Protocol.ShopAction.ClaimGift, "junk")
	request("ShopRequest", hal, Protocol.ShopAction.ClaimGift, {})
	request("ShopRequest", hal, Protocol.ShopAction.ClaimGift, 1.5)
	task.wait(0.05)
	assert(next(Data:get(hal).calendars) == nil, "junk claims write nothing")
	hal = join("Hal2", 9115)
	request("ShopRequest", hal, Protocol.ShopAction.ClaimGift, 1)
	task.wait(0.3)
	assert(entry(hal, harvest) and entry(hal, harvest).claimed["1"], "a real claim over the remote")
	-- Spam is dropped by the rate limiter
	local money = Currency:balance(hal, "money")
	for _ = 1, 30 do
		request("ShopRequest", hal, Protocol.ShopAction.ClaimGift, 1)
	end
	task.wait(0.2)
	assert(Currency:balance(hal, "money") == money, "no repeat payouts from spam")
	harvest.startsAt = original
end)

-- Trials --------------------------------------------------------------------------------------

check("trials: premium fighters only, stack up to 7 days, saved in the profile", function()
	local ivy = join("Ivy", 9109)
	local ok, reason = Power:grantTrial(ivy, "StrongDude", 24, "test")
	assert(not ok, "free fighters have no trials: " .. tostring(reason))
	assert(not Power:grantTrial(ivy, "Nobody", 24, "test"))
	assert(not Power:grantTrial(ivy, "Admin", 0, "test") and not Power:grantTrial(ivy, "Admin", -5, "test") and not Power:grantTrial(ivy, "Admin", "9", "test"))
	assert(Power:grantTrial(ivy, "Admin", 24, "test"))
	local first = Power:trialEndsAt(ivy, "Admin")
	assert(Data:get(ivy).trials.Admin == first, "saved in profile.trials")
	assert(Power:grantTrial(ivy, "Admin", 24, "test"))
	local second = Power:trialEndsAt(ivy, "Admin")
	assert(second - first >= 24 * 3600 - 2 and second - first <= 24 * 3600 + 2, "a second ticket stacks")
	for _ = 1, 10 do
		Power:grantTrial(ivy, "Admin", 24, "test")
	end
	assert(Power:trialEndsAt(ivy, "Admin") - os.time() <= 7 * 86400, "never more than 7 days")
	assert(Power.applyTrial({ trials = {} }, "Syntax", 24, 1000) == 1000 + 86400, "applyTrial is pure")
end)

check("a trial allows Duel and Free-for-All exactly like an owned fighter, and ends cleanly", function()
	local jo = join("Jo", 9110)
	request("PowerRequest", jo, Protocol.PowerAction.Select, "Syntax", 1)
	task.wait(0.2)
	local allowed = Power:queueCheck(jo, "Duel")
	assert(not allowed, "refused without a ticket")
	assert(Power:grantTrial(jo, "Syntax", 24, "test"))
	assert(Power:queueCheck(jo, "Duel") and Power:queueCheck(jo, "FreeForAll"), "allowed with a ticket")
	local snapshot = Power:snapshot(jo)
	assert(snapshot.powers.Syntax.owned == true and snapshot.powers.Syntax.trialEndsAt == Power:trialEndsAt(jo, "Syntax"), "the snapshot carries the end time")
	-- Expiry
	Data:update(jo, function(profile)
		profile.trials.Syntax = os.time() - 1
	end)
	assert(Power:trialEndsAt(jo, "Syntax") == nil and not Power:owns(jo, "Syntax"), "ended")
	local after, reason = Power:queueCheck(jo, "Duel")
	assert(not after and reason, "refused again after the ticket ends")
	assert(Power:queueCheck(jo, "Practice"), "Training and CPU Practice stay free")
	Power:_sweepTrials()
	assert(Data:get(jo).trials.Syntax == nil, "the sweep removes the ended ticket")
end)

check("a match that began under a trial finishes with it", function()
	local kim = join("Kim", 9111)
	assert(Power:grantTrial(kim, "Corruption", 24, "test"))
	request("PowerRequest", kim, Protocol.PowerAction.Select, "Corruption", 1)
	task.wait(0.2)
	Power:lock(kim)
	assert(Power:isLocked(kim))
	Data:update(kim, function(profile)
		profile.trials.Corruption = os.time() - 5
	end)
	assert(Power:owns(kim, "Corruption"), "still counts as owned inside the match")
	Power:_sweepTrials()
	assert(Data:get(kim).trials.Corruption ~= nil, "the sweep leaves a ticket a running match is using")
	Power:unlock(kim)
	assert(not Power:owns(kim, "Corruption"), "ended once the match is over")
	Power:_sweepTrials()
	assert(Data:get(kim).trials.Corruption == nil)
end)

-- Trial products -------------------------------------------------------------------------------

local function receipt(userId, productId, id)
	return { PlayerId = userId, ProductId = productId, PurchaseId = id, CurrencyType = roblox.Enum.CurrencyType.Robux, CurrencySpent = 49 }
end

check("trial products: fixed 24 hours, idempotent by PurchaseId, stacking, one per fighter", function()
	for key, product in { TrialCorruption = "Corruption", TrialSyntax = "Syntax", TrialAdmin = "Admin" } do
		local config = Monetization.Products[key]
		assert(config.trial.power == product and config.trial.hours == 24 and config.recommended == 49, key)
		assert(Monetization.TrialProducts[product] == key)
	end
	local lee = join("Lee", 9112)
	assert(Engine.deliverReceipt(receipt(9112, TRIAL_IDS.TrialSyntax, "trial-1")) == Decision.PurchaseGranted)
	local first = Power:trialEndsAt(lee, "Syntax")
	assert(first and first - os.time() > 23.9 * 3600, "24 hours")
	for _ = 1, 3 do
		assert(Engine.deliverReceipt(receipt(9112, TRIAL_IDS.TrialSyntax, "trial-1")) == Decision.PurchaseGranted)
	end
	assert(Power:trialEndsAt(lee, "Syntax") == first, "a repeated PurchaseId grants once")
	assert(Engine.deliverReceipt(receipt(9112, TRIAL_IDS.TrialSyntax, "trial-2")) == Decision.PurchaseGranted)
	assert(Power:trialEndsAt(lee, "Syntax") - first >= 24 * 3600 - 2, "a new purchase stacks")
	assert(Power:trialEndsAt(lee, "Corruption") == nil, "only the fighter bought")
	assert(table.find(Data:get(lee).receipts, "trial-1"), "receipt recorded")
	assert(Power:queueCheck(lee, "Duel") ~= nil)
end)

check("trial products: save-before-grant with rollback, and no sale of an owned fighter", function()
	local mia = join("Mia", 9113)
	local original = Data.saveNow
	Data.saveNow = function()
		return false
	end
	assert(Engine.deliverReceipt(receipt(9113, TRIAL_IDS.TrialAdmin, "trial-fail")) == Decision.NotProcessedYet, "an unsaved grant is not acknowledged")
	Data.saveNow = original
	assert(Data:get(mia).trials.Admin == nil and not table.find(Data:get(mia).receipts, "trial-fail"), "rolled back")
	assert(Engine.deliverReceipt(receipt(9113, TRIAL_IDS.TrialAdmin, "trial-fail")) == Decision.PurchaseGranted, "Roblox's retry works")
	assert(Power:trialEndsAt(mia, "Admin") ~= nil)
	-- A fighter already owned is not sold a trial
	Data:update(mia, function(profile)
		profile.powers.Corruption = { xp = 0, degrees = {}, abilities = {}, owned = true }
	end)
	local prompts = #Engine.marketplace.prompts
	request("ShopRequest", mia, Protocol.ShopAction.PromptProduct, "TrialCorruption")
	task.wait(0.05)
	assert(#Engine.marketplace.prompts == prompts, "no purchase window for a fighter already owned")
	request("ShopRequest", mia, Protocol.ShopAction.PromptProduct, "TrialSyntax")
	task.wait(0.05)
	assert(#Engine.marketplace.prompts == prompts + 1, "a normal prompt for a fighter not owned")
end)

check("trial products with id 0 never open a purchase window", function()
	local nan = join("Nan", 9114)
	local saved = Monetization.Products.TrialAdmin.id
	Monetization.Products.TrialAdmin.id = 0
	local prompts = #Engine.marketplace.prompts
	request("ShopRequest", nan, Protocol.ShopAction.PromptProduct, "TrialAdmin")
	task.wait(0.05)
	Monetization.Products.TrialAdmin.id = saved
	assert(#Engine.marketplace.prompts == prompts)
	for _, key in { "TrialCorruption", "TrialSyntax", "TrialAdmin" } do
		assert(Monetization.Products[key].robux == nil, "no hard-coded live price: " .. key)
	end
end)

-- Schema --------------------------------------------------------------------------------------

check("schema: defaults, and repair of junk calendars and trials", function()
	local default = Schema.default()
	assert(next(default.calendars) == nil and next(default.trials) == nil)
	local junk = Schema.default()
	junk.calendars = {
		harvest_2026 = { claimed = { ["1"] = true, ["22"] = true, ["23"] = true, ["0"] = true, ["01"] = true, x = true, ["5"] = "yes" }, perfect = "true", milestones = { ["5"] = true, ["7"] = true } },
		fake_2030 = { claimed = { ["1"] = true } },
		advent_2026 = "junk",
		[5] = {},
	}
	junk.trials = { Admin = 1.7e9 + 0.5, Syntax = -4, Corruption = 0 / 0, StrongDude = 99, Nobody = 5, Grandmaster = 5, [3] = 9 }
	local fixed = Schema.migrate(junk)
	local h = fixed.calendars.harvest_2026
	assert(h and h.claimed["1"] and h.claimed["22"] and not h.claimed["23"] and not h.claimed["0"] and not h.claimed["01"] and not h.claimed.x and not h.claimed["5"], "known day keys only")
	assert(h.perfect == false, "perfect must be a real true")
	assert(h.milestones["5"] and not h.milestones["7"], "known milestone keys only")
	assert(fixed.calendars.fake_2030 == nil and fixed.calendars[5] == nil, "unknown calendars dropped")
	assert(fixed.calendars.advent_2026 and next(fixed.calendars.advent_2026.claimed) == nil, "junk entry becomes empty")
	assert(fixed.trials.Admin == 1700000000 and fixed.trials.Syntax == nil and fixed.trials.Corruption == nil and fixed.trials.StrongDude == nil and fixed.trials.Nobody == nil, "trial times kept for premium fighters only")
	local huge = Schema.default()
	huge.trials = { Admin = 1e30, Syntax = math.huge }
	local clamped = Schema.migrate(huge)
	assert(clamped.trials.Admin == 4102444800 and clamped.trials.Syntax == nil, "clamped")
	local nilCal = Schema.migrate({ calendars = 5, trials = "x" })
	assert(next(nilCal.calendars) == nil and next(nilCal.trials) == nil, "non-tables become empty")
	assert(Schema.storable(Schema.migrate(Schema.copy(fixed))), "still storable")
	local view = Schema.view(fixed)
	assert(view.calendars and view.trials, "the client view carries both")
end)

local failed = game.finish()
game.stop()
process.exit(if failed > 0 then 1 else 0)
