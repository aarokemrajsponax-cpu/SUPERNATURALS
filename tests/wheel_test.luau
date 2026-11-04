-- The Lounge wheel (DECISIONS 41), end to end on the real server services (stand-in engine):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/wheel_test.luau build/game.rbxl
-- Odds add to 100 and match the table and what the draw really does; a free spin once a day;
-- paid spin receipts idempotent by PurchaseId (and rolled back when the save fails); a restricted
-- player (or one whose policy check errors) cannot buy, hold or see paid spins; duplicates and
-- unusable trials become the stated Money; prizes are saved before the reply and rolled back when
-- the save fails; trials are granted; the physical wheel turns to the drawn segment.

local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local World = require("./smoke/World")

local SPIN1_ID, SPIN5_ID = 5601, 5602
local game = World.start(process.args[1] or "build/game.rbxl", function(setup)
	local Monetization = setup.world.require(setup.world.find("ReplicatedStorage.Shared.Config.Monetization"))
	Monetization.Products.LoungeSpin.id = SPIN1_ID
	Monetization.Products.LoungeSpin5.id = SPIN5_ID
	Monetization.PromptCooldown = 0
end)
local task, services, check, request = game.task, game.services, game.check, game.request
local world, Engine = game.world, game.Engine
local Decision = roblox.Enum.ProductPurchaseDecision

local function find(path)
	return world.find(path)
end
local Wheel = world.require(find("ReplicatedStorage.Shared.Config.Wheel"))
local Monetization = world.require(find("ReplicatedStorage.Shared.Config.Monetization"))
local Cosmetics = world.require(find("ReplicatedStorage.Shared.Config.Cosmetics"))
local Powers = world.require(find("ReplicatedStorage.Shared.Powers"))
local Schema = world.require(find("ReplicatedStorage.Shared.Data.Schema"))
local Protocol = world.require(find("ReplicatedStorage.Shared.Protocol"))

local Data, WheelService, Purchases = services.DataService, services.WheelService, services.PurchaseService
local market = Engine.marketplace

local function profile(player)
	return Data:get(player)
end
local function money(player)
	return profile(player).currencies.money
end
local function receipt(userId, productId, id, extra)
	local r = { PlayerId = userId, ProductId = productId, PurchaseId = id, CurrencyType = roblox.Enum.CurrencyType.Robux, CurrencySpent = 25 }
	for key, value in extra or {} do
		r[key] = value
	end
	return r
end
-- A random source that returns the middle of a prize's share of the 0 to 100 line
local scripted: number? = nil
WheelService.random = {
	NextNumber = function()
		return (scripted or 50) / 100
	end,
}
local function rollFor(id)
	local edge = 0
	for _, prize in Wheel.Prizes do
		if prize.id == id then
			scripted = edge + prize.percent / 2
			return
		end
		edge += prize.percent
	end
	error("no prize " .. id)
end
local function spin(player, kind)
	task.wait(0.6) -- the request limiter refills over time
	local mark = game.mark()
	request("LoungeRequest", player, if kind == "paid" then Protocol.LoungeAction.SpinPaid else Protocol.LoungeAction.SpinFree)
	game.waitFor(function()
		return #game.sentSince(mark, "DataEvent", "Lounge", player) > 0
	end, 3, "a spin reply")
	local replies = game.sentSince(mark, "DataEvent", "Lounge", player)
	return replies[#replies]
end

-- Policy: three kinds of player, set before anyone joins. Errors count as restricted.
local policyMode = {}
WheelService.policy = function(player)
	local mode = policyMode[player.UserId]
	if mode == "error" then
		error("the policy service is unavailable")
	end
	return { ArePaidRandomItemsRestricted = mode == "restricted" }
end

check("the table is whole: odds add to 100 and every prize is real", function()
	assert(Wheel.total() == 100, "odds add to " .. Wheel.total())
	local seen = {}
	for _, prize in Wheel.Prizes do
		assert(not seen[prize.id], "duplicate id")
		seen[prize.id] = true
		assert(prize.percent > 0 and prize.percent == math.floor(prize.percent), "whole percent")
		if prize.kind == "cosmetic" then
			local item = Cosmetics.get(prize.cosmetic)
			assert(item and item.source == "wheel", "a wheel-exclusive cosmetic: " .. prize.cosmetic)
		elseif prize.kind == "trial" then
			assert(Powers.isPremium(prize.power) and prize.hours == 24, "a 24 hour trial of a premium fighter")
		elseif prize.kind == "money" or prize.kind == "gems" then
			assert(prize.amount > 0, "an amount")
		else
			error("unknown kind " .. prize.kind)
		end
	end
	local trials = {}
	for _, prize in Wheel.Prizes do
		if prize.kind == "trial" then
			trials[prize.power] = true
		end
	end
	assert(trials.Corruption and trials.Syntax and trials.Admin, "trials of Corruption, Syntax and Admin")
	assert(Wheel.DuplicateMoney > 0)
	assert(Monetization.Products.LoungeSpin.wheelSpins == 1 and Monetization.Products.LoungeSpin.recommended == 25)
	assert(Monetization.Products.LoungeSpin5.wheelSpins == 5 and Monetization.Products.LoungeSpin5.recommended == 99)
end)

check("the draw follows the table: a large sample lands near each stated chance", function()
	-- A small deterministic generator (Lune has no Random)
	local seed = 12345
	local function nextNumber()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local counts = {}
	local runs = 40000
	for _ = 1, runs do
		local prize = Wheel.pick(nextNumber() * 100)
		counts[prize.id] = (counts[prize.id] or 0) + 1
	end
	for _, prize in Wheel.Prizes do
		local share = 100 * (counts[prize.id] or 0) / runs
		assert(math.abs(share - prize.percent) < 1.2, `{prize.id}: stated {prize.percent}%, drawn {share}%`)
	end
	-- The edges: first and last roll
	assert(Wheel.pick(0).id == Wheel.Prizes[1].id and Wheel.pick(99.999).id == Wheel.Prizes[#Wheel.Prizes].id)
end)

policyMode[9002] = "error"
policyMode[9003] = "restricted"
local alice = game.join("Alice", 9001)
local zed = game.join("Zed", 9002)
local rex = game.join("Rex", 9003)
local function waitProfile(player)
	game.waitFor(function()
		return profile(player) ~= nil
	end, 3, "profile")
end
for _, p in { alice, zed, rex } do
	waitProfile(p)
end

check("a free spin once a day: the second is refused, tomorrow it is back", function()
	rollFor("money500")
	local before = money(alice)
	assert(WheelService:state(alice).freeReady == true)
	local reply = spin(alice, "free")
	assert(reply.kind == "Spin" and reply.ok and reply.prizeId == "money500" and reply.source == "free", "drawn on the server")
	assert(money(alice) == before + 500, "paid")
	assert(profile(alice).wheel.freeDay == Wheel.dayOf(os.time()) and profile(alice).wheel.spins == 1)
	assert(profile(alice).wheel.last[1] == "money500", "saved to the profile")
	assert(reply.wheel.freeReady == false)
	local again = spin(alice, "free")
	assert(again.ok == false and money(alice) == before + 500, "no second free spin the same day")
	local realClock = WheelService.clock
	WheelService.clock = function()
		return os.time() + 86400 + 5
	end
	assert(WheelService:state(alice).freeReady == true, "a new day, a new free spin")
	WheelService.clock = realClock
end)

check("the reply's index points at the drawn prize and the physical wheel turns to it", function()
	WheelService.clock = function()
		return os.time() + 3 * 86400
	end
	rollFor("gems30")
	local gemsBefore = profile(alice).currencies.gems
	local reply = spin(alice, "free")
	assert(reply.ok and Wheel.Prizes[reply.index].id == "gems30" and reply.prizeId == "gems30", "index matches the table")
	assert(profile(alice).currencies.gems == gemsBefore + 30)
	local built = services.LoungeService:getBuilt()
	assert(built.wheelDisc and built.wheelDisc:GetAttribute("Angle") ~= nil, "the disc was told to turn")
	local angle = built.wheelDisc:GetAttribute("Angle") % 360
	local width = 360 / #Wheel.Prizes
	local low, high = (reply.index - 1) * width, reply.index * width
	assert(angle > low + width * 0.15 and angle < high - width * 0.15, `lands inside the segment, away from its edges ({angle} in {low} to {high})`)
	WheelService.clock = os.time
end)

check("paid spin receipts are idempotent by PurchaseId and give fixed credits", function()
	local uid = alice.UserId
	assert(Engine.deliverReceipt(receipt(uid, SPIN1_ID, "ls-1")) == Decision.PurchaseGranted)
	assert(profile(alice).wheel.credits == 1, "one spin")
	for _ = 1, 3 do
		assert(Engine.deliverReceipt(receipt(uid, SPIN1_ID, "ls-1")) == Decision.PurchaseGranted)
	end
	assert(profile(alice).wheel.credits == 1, "the same PurchaseId never adds twice")
	assert(Engine.deliverReceipt(receipt(uid, SPIN5_ID, "ls-5")) == Decision.PurchaseGranted)
	assert(profile(alice).wheel.credits == 6, "five more")
	assert(Engine.deliverReceipt(receipt(uid, SPIN5_ID, "ls-5", { CurrencySpent = 1 })) == Decision.PurchaseGranted and profile(alice).wheel.credits == 6)
end)

check("a paid spin receipt whose save fails is not acknowledged and is rolled back", function()
	local cara = game.join("Cara", 9004)
	waitProfile(cara)
	policyMode[9004] = nil
	local original = Data.saveNow
	Data.saveNow = function()
		return false
	end
	local decision = Engine.deliverReceipt(receipt(9004, SPIN1_ID, "ls-fail"))
	Data.saveNow = original
	assert(decision == Decision.NotProcessedYet, "Roblox must retry")
	assert(profile(cara).wheel.credits == 0 and not table.find(profile(cara).receipts, "ls-fail"), "rolled back")
	assert(Engine.deliverReceipt(receipt(9004, SPIN1_ID, "ls-fail")) == Decision.PurchaseGranted and profile(cara).wheel.credits == 1, "the retry lands once")
	game.leave(cara)
end)

check("prizes are granted after the save, and the reply comes only once it is saved", function()
	rollFor("money1000")
	local original = Data.saveNow
	local order = {}
	local mark = game.mark()
	Data.saveNow = function(self, player)
		table.insert(order, "save")
		-- At the moment of saving, the prize and the spent credit are already in the profile
		assert(profile(alice).wheel.credits == 5, "the credit is spent in the saved change")
		table.insert(order, #game.sentSince(mark, "DataEvent", "Lounge", alice) == 0 and "no reply yet" or "reply too early")
		return original(self, player)
	end
	local before = money(alice)
	local reply = spin(alice, "paid")
	Data.saveNow = original
	assert(reply.ok and money(alice) == before + 1000 and profile(alice).wheel.credits == 5)
	assert(order[1] == "save" and order[2] == "no reply yet", "saved before the reply: " .. table.concat(order, ","))
end)

check("a spin whose save fails changes nothing", function()
	rollFor("money2500")
	local original = Data.saveNow
	Data.saveNow = function()
		return false
	end
	local before, creditsBefore, spinsBefore = money(alice), profile(alice).wheel.credits, profile(alice).wheel.spins
	local reply = spin(alice, "paid")
	Data.saveNow = original
	assert(reply.ok == false, "refused")
	assert(money(alice) == before and profile(alice).wheel.credits == creditsBefore and profile(alice).wheel.spins == spinsBefore, "rolled back")
end)

check("duplicate cosmetics become a stated Money amount", function()
	local Lantern = Wheel.byId("cosmeticLantern")
	rollFor("cosmeticLantern")
	WheelService.clock = function()
		return os.time() + 10 * 86400
	end
	local before = money(alice)
	local first = spin(alice, "free")
	assert(first.ok and first.converted == false and profile(alice).cosmetics.owned[Lantern.cosmetic] == true, "the first time the cosmetic is granted")
	assert(money(alice) == before, "no Money for a new cosmetic")
	WheelService.clock = function()
		return os.time() + 11 * 86400
	end
	local second = spin(alice, "free")
	assert(second.ok and second.converted == true, "owned: converted")
	assert(money(alice) == before + Wheel.DuplicateMoney, "paid the stated amount")
	assert(string.find(second.text, tostring(Wheel.DuplicateMoney), 1, true), "the text names the amount: " .. second.text)
	WheelService.clock = os.time
end)

check("trials are granted for fighters the player can use, and converted otherwise", function()
	for index, power in { "Corruption", "Syntax", "Admin" } do
		local id = "trial" .. power
		rollFor(id)
		WheelService.clock = function()
			return os.time() + (20 + index) * 86400
		end
		local before = money(alice)
		local reply = spin(alice, "free")
		assert(reply.ok and reply.prizeId == id)
		if Powers.isReleased(power) then
			local endsAt = profile(alice).trials[power]
			assert(not reply.converted and endsAt and endsAt > os.time() + 23 * 3600 and endsAt <= os.time() + 24 * 3600 + 5, power .. " trial of about 24 hours")
			assert(money(alice) == before)
		else
			assert(reply.converted and money(alice) == before + Wheel.DuplicateMoney, power .. " is not released: Money instead")
		end
	end
	-- A fighter the player already owns is not "tried": paid as Money
	profile(alice).powers.Syntax = { xp = 0, degrees = {}, abilities = {}, owned = true }
	WheelService.clock = function()
		return os.time() + 30 * 86400
	end
	rollFor("trialSyntax")
	local before = money(alice)
	local reply = spin(alice, "free")
	assert(reply.ok and reply.converted and money(alice) == before + Wheel.DuplicateMoney, "an owned fighter converts the trial")
	WheelService.clock = os.time
end)

check("a restricted player, and one whose policy check errors, never get paid spins", function()
	for _, player in { zed, rex } do
		assert(WheelService:paidAllowed(player) == false)
		local state = WheelService:state(player)
		assert(state.paidAllowed == false and state.credits == 0 and next(state.products) == nil, "no paid controls in the state")
		local ok, reason = WheelService:canSellSpins(player, 1)
		assert(ok == false and reason, "cannot be sold spins")
		local prompts = #market.prompts
		request("ShopRequest", player, Protocol.ShopAction.PromptProduct, "LoungeSpin")
		request("ShopRequest", player, Protocol.ShopAction.PromptProduct, "LoungeSpin5")
		task.wait(0.1)
		assert(#market.prompts == prompts, "no purchase window opens")
		-- Even with credits somehow in the profile, a paid spin is refused
		profile(player).wheel.credits = 3
		local reply = spin(player, "paid")
		assert(reply.ok == false and profile(player).wheel.credits == 3 and profile(player).wheel.spins == 0, "no paid draw")
		assert(WheelService:state(player).credits == 0, "held credits stay hidden")
		profile(player).wheel.credits = 0
	end
	-- Free spins still work for them
	rollFor("money200")
	local before = money(rex)
	local reply = spin(rex, "free")
	assert(reply.ok and money(rex) == before + 200, "the free spin is for everyone")
	-- An allowed player does get the prompt
	local prompts = #market.prompts
	request("ShopRequest", alice, Protocol.ShopAction.PromptProduct, "LoungeSpin")
	task.wait(0.1)
	assert(#market.prompts == prompts + 1, "an allowed player can buy")
end)

check("rapid duplicate requests are handled once", function()
	rollFor("money200")
	WheelService.clock = function()
		return os.time() + 40 * 86400
	end
	local before, spins = money(alice), profile(alice).wheel.spins
	request("LoungeRequest", alice, Protocol.LoungeAction.SpinFree)
	request("LoungeRequest", alice, Protocol.LoungeAction.SpinFree)
	request("LoungeRequest", alice, Protocol.LoungeAction.SpinFree)
	task.wait(0.5)
	assert(profile(alice).wheel.spins == spins + 1 and money(alice) == before + 200, "one spin")
	WheelService.clock = os.time
end)

check("the profile fields are repaired: odd values are bounded, unknown prizes dropped", function()
	local repaired = Schema.migrate({ wheel = { freeDay = "x", credits = 9999, spins = -4, last = { "nope", "money200", 7 } }, lounge = { gameEarned = 1e12, refreshments = "lots" } })
	assert(repaired.wheel.freeDay == 0 and repaired.wheel.credits == Wheel.MaxCredits and repaired.wheel.spins == 0, "bounded")
	assert(#repaired.wheel.last == 1 and repaired.wheel.last[1] == "money200", "unknown prize ids dropped")
	assert(repaired.lounge.gameEarned <= 1e6 and repaired.lounge.refreshments == 0, "lounge counters bounded")
	local fresh = Schema.default()
	assert(fresh.wheel.credits == 0 and fresh.lounge.gameDay == 0)
end)

check("Roblox says restricted: held credits become 50 Gems each, saved first, then a notice", function()
	policyMode[9005] = "restricted"
	local dan = game.join("Dan", 9005)
	waitProfile(dan)
	local gemsBefore = profile(dan).currencies.gems
	-- Credits arrive (a receipt from an earlier server), the policy says restricted
	assert(Engine.deliverReceipt(receipt(9005, SPIN5_ID, "dan-5")) == Decision.PurchaseGranted)
	local expected = 5 * Wheel.CreditGems
	assert(Wheel.CreditGems == 50, "50 Gems a spin, the shop rate for 25 R$")
	assert(profile(dan).wheel.credits == 0 and profile(dan).currencies.gems == gemsBefore + expected, "exchanged: " .. profile(dan).currencies.gems)
	local notices = {}
	for _, entry in Engine.sent do
		if entry.remote == "DataEvent" and entry.kind == "FireClient" and entry.args[1] == dan and entry.args[2] == "Toast" and string.find(entry.args[3].text, "exchanged", 1, true) then
			table.insert(notices, entry.args[3].text)
		end
	end
	assert(#notices == 1 and notices[1] == `Wheel spins can't be used where you play, so your 5 spins were exchanged for {expected} Gems.`, "the notice: " .. tostring(notices[1]))
	-- A held credit found when the player joins is exchanged too, and a failed save changes nothing
	profile(dan).wheel.credits = 2
	local original = Data.saveNow
	Data.saveNow = function()
		return false
	end
	WheelService:_settle(dan)
	Data.saveNow = original
	assert(profile(dan).wheel.credits == 2 and profile(dan).currencies.gems == gemsBefore + expected, "an unsaved exchange is undone")
	WheelService:_settle(dan)
	assert(profile(dan).wheel.credits == 0 and profile(dan).currencies.gems == gemsBefore + expected + 100, "the retry lands once")
	WheelService:_settle(dan)
	assert(profile(dan).currencies.gems == gemsBefore + expected + 100, "nothing more to exchange")
	game.leave(dan)
end)

check("the policy call errors: credits are kept and only the paid controls are hidden", function()
	-- Zed's policy call errors (see above)
	local gemsBefore = profile(zed).currencies.gems
	assert(Engine.deliverReceipt(receipt(9002, SPIN1_ID, "zed-1")) == Decision.PurchaseGranted)
	assert(profile(zed).wheel.credits == 1 and profile(zed).currencies.gems == gemsBefore, "kept, not exchanged")
	local state = WheelService:state(zed)
	assert(state.paidAllowed == false and state.credits == 0 and next(state.products) == nil, "paid controls hidden")
	WheelService:_settle(zed)
	assert(profile(zed).wheel.credits == 1 and profile(zed).currencies.gems == gemsBefore, "still kept")
	profile(zed).wheel.credits = 0
end)

check("the physical wheel shows every prize with its chance, and nothing pressures", function()
	local room = world.workspace:WaitForChild("Lounge")
	local disc = room:FindFirstChild("Disc", true)
	assert(disc, "a disc in the lounge")
	local legend = room:FindFirstChild("WheelLegend", true)
	local percents = 0
	for index, prize in Wheel.Prizes do
		local label = legend:FindFirstChild("Chance" .. index, true)
		assert(label and label.Text == `{prize.percent}%`, "the legend shows " .. prize.percent .. "%")
		percents += prize.percent
	end
	assert(percents == 100)
	local prompt = room:FindFirstChild("LoungeWheel", true):FindFirstChild("Pad"):FindFirstChildOfClass("ProximityPrompt")
	assert(prompt:GetAttribute("Action") == "Lounge:Wheel", "the pad opens the Wheel window")
	local banned = { "last chance", "hurry", "limited", "only today", "countdown", "running out", "don't miss", "expires" }
	local all = string.lower(Wheel.RulesText .. Wheel.FreeText .. Wheel.PaidText .. Monetization.Products.LoungeSpin.benefit .. Monetization.Products.LoungeSpin5.benefit)
	for _, word in banned do
		assert(not string.find(all, word, 1, true), "no pressure wording: " .. word)
	end
	assert(not string.find(all, "—", 1, true), "no em dashes")
end)

process.exit(if game.finish() == 0 then 0 else 1)
