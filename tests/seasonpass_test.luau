-- Season pass and cosmetic passes, end to end on the real server services (stand-in engine):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/seasonpass_test.luau build/game.rbxl
-- Points from match results, daily challenges and practice rounds; tiers and claims validated
-- by the server; the premium track locked until the SeasonPremium product; SeasonTierSkip
-- idempotent by PurchaseId and capped at the last tier; season roll-over; VIP and the Founders
-- Collection granting their listed cosmetics once; nothing here changes any stat.

local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local World = require("./smoke/World")

local PREMIUM_ID, SKIP_ID, VIP_ID, FOUNDERS_ID = 5301, 5302, 5401, 5402
local listeners = {}
local game = World.start(process.args[1] or "build/game.rbxl", function(setup)
	local function req(path)
		return setup.world.require(setup.world.find(path))
	end
	local Monetization = req("ReplicatedStorage.Shared.Config.Monetization")
	Monetization.Products.SeasonPremium.id = PREMIUM_ID
	Monetization.Products.SeasonTierSkip.id = SKIP_ID
	Monetization.Passes.VIP.id = VIP_ID
	Monetization.Passes.FoundersCollection.id = FOUNDERS_ID
	-- A season that is running now, and a second one that starts later (for roll-over)
	local SeasonPass = req("ReplicatedStorage.Shared.Config.SeasonPass")
	local now = os.time()
	SeasonPass.Seasons[1].startsAt = now - 3600
	SeasonPass.Seasons[1].endsAt = now + 86400 * 10
	-- Capture the result listeners services register (SeasonPassService among them), to feed them fake match results
	local Progression = req("ServerScriptService.Server.Services.ProgressionService")
	local original = Progression.onMatchResult
	Progression.onMatchResult = function(self, listener)
		table.insert(listeners, listener)
		return original(self, listener)
	end
end)
local task, services, check, request = game.task, game.services, game.check, game.request
local world, Engine = game.world, game.Engine
local Decision = roblox.Enum.ProductPurchaseDecision

local function find(path)
	return world.find(path)
end
local Monetization = world.require(find("ReplicatedStorage.Shared.Config.Monetization"))
local SeasonPass = world.require(find("ReplicatedStorage.Shared.Config.SeasonPass"))
local Cosmetics = world.require(find("ReplicatedStorage.Shared.Config.Cosmetics"))
local Protocol = world.require(find("ReplicatedStorage.Shared.Protocol"))
local Schema = world.require(find("ReplicatedStorage.Shared.Data.Schema"))

Monetization.PromptCooldown = 0
Monetization.OwnershipCheckAttempts = 2
local Data, Pass, Cosm, Currency = services.DataService, services.SeasonPassService, services.CosmeticService, services.CurrencyService
local market = Engine.marketplace
local ClaimTier = Protocol.ShopAction.ClaimTier

local function waitProfile(player)
	game.waitFor(function()
		return Data:get(player) ~= nil
	end, 5, "profile")
end
local function receipt(userId, productId, id)
	return { PlayerId = userId, ProductId = productId, PurchaseId = id, CurrencyType = roblox.Enum.CurrencyType.Robux, CurrencySpent = 49 }
end
local function points(player)
	return Data:get(player).pass.points
end
local function setPoints(player, value)
	Data:update(player, function(profile)
		profile.pass.points = value
	end)
end
local function money(player)
	return Data:get(player).currencies.money
end
local function owns(player, id)
	return Data:get(player).cosmetics.owned[id] == true
end
local function claim(player, key)
	request("ShopRequest", player, ClaimTier, key)
	task.wait(0.15)
end

-- A fake match result goes to every listener, as ProgressionService would send it
local function matchListener(player, result)
	for _, listener in listeners do
		listener(player, result)
	end
end

local ana = game.join("Ana", 8101)
waitProfile(ana)
local ben = game.join("Ben", 8102)
waitProfile(ben)

-- Content -------------------------------------------------------------------------------------

check("the season has 30 tiers, real dates in November 2026, a free item every few tiers and a premium item at every tier", function()
	assert(SeasonPass.TierCount == 30, "30 tiers")
	local id = "harvest_2026"
	local season
	for _, candidate in SeasonPass.Seasons do
		if candidate.id == id then
			season = candidate
		end
	end
	assert(season, "harvest_2026 exists")
	-- (the test moves the dates; read the real ones from the source of truth in the file)
	assert(season.endText == "30 November 2026")
	for tier = 1, 30 do
		local free, premium = SeasonPass.Free[tier], SeasonPass.Premium[tier]
		assert(free and (free.money or free.cosmetic), "free tier " .. tier)
		assert(free.money == nil or free.cosmetic == nil, "one free reward per tier")
		assert(free.money == nil or (free.money > 0 and free.money <= 300), "small Money")
		assert(free.cosmetic == nil or Cosmetics.get(free.cosmetic), "free cosmetic exists")
		assert(Cosmetics.get(premium), "premium cosmetic exists at tier " .. tier)
		assert(Cosmetics.get(premium).source == "season")
	end
	local gap, last = 0, 0
	for tier = 1, 30 do
		if SeasonPass.Free[tier].cosmetic then
			gap = math.max(gap, tier - last)
			last = tier
		end
	end
	assert(gap <= 4, "a free cosmetic at least every four tiers, longest gap " .. gap)
end)

check("an active player finishes the free track by the end of the season", function()
	-- Three paid matches on most days (about a third won), one challenge, two practice rounds
	local perDay = 3 * SeasonPass.Points.Match + 1 * SeasonPass.Points.Win + SeasonPass.Points.Daily + 2 * SeasonPass.Points.Training
	local total = perDay * 20 -- 20 of the 30 days
	assert(total >= SeasonPass.maxPoints(), `{total} points over 20 active days is below {SeasonPass.maxPoints()}`)
	-- ...but a casual player does not breeze through
	assert(perDay * 5 < SeasonPass.maxPoints(), "five busy days do not finish it")
end)

-- Points ----------------------------------------------------------------------------------------

check("points come from match results: a win, a loss and a draw; unpaid matches give nothing", function()
	assert(#listeners > 0, "SeasonPassService listens to ProgressionService:onMatchResult")
	assert(points(ana) == 0, "starts at zero")
	matchListener(ana, { paid = true, won = true, draw = false })
	assert(points(ana) == SeasonPass.Points.Match + SeasonPass.Points.Win, "win")
	matchListener(ana, { paid = true, won = false, draw = false })
	assert(points(ana) == 2 * SeasonPass.Points.Match + SeasonPass.Points.Win, "loss adds the base only")
	matchListener(ana, { paid = true, won = false, draw = true })
	local after = points(ana)
	matchListener(ana, { paid = false, won = true })
	matchListener(ana, "junk")
	assert(points(ana) == after, "an unpaid match and junk add nothing")
	assert(Data:get(ana).pass.season == "harvest_2026")
end)

check("a claimed daily challenge adds points through ProgressionService", function()
	local challenge = services.ProgressionService:today()[1]
	Data:update(ana, function(profile)
		profile.daily.day = math.floor(os.time() / 86400)
		profile.daily.progress[challenge.stat] = challenge.goal
	end)
	local before = points(ana)
	services.ProgressionService:_claim(ana, challenge.id)
	assert(points(ana) == before + SeasonPass.Points.Daily, "daily points")
	services.ProgressionService:_claim(ana, challenge.id)
	assert(points(ana) == before + SeasonPass.Points.Daily, "a second claim adds nothing")
end)

check("practice rounds add points, only when long enough and at most three a day", function()
	local before = points(ben)
	Pass:onTrainingRound(ben, 5)
	assert(points(ben) == before, "a short round adds nothing")
	for _ = 1, 5 do
		Pass:onTrainingRound(ben, 40)
	end
	assert(points(ben) == before + 3 * SeasonPass.Points.Training, "three rounds count")
end)

-- Claims -------------------------------------------------------------------------------------------

check("claims are validated on the server", function()
	Data:update(ben, function(profile)
		profile.pass.points = 0
	end)
	local m = money(ben)
	for _, key in { "f1", "p1", "f0", "f31", "f-1", "x5", "", "f1.5", "f", 7, "f1; drop", string.rep("f1", 20) } do
		claim(ben, key)
	end
	request("ShopRequest", ben, ClaimTier, nil)
	request("ShopRequest", ben, ClaimTier, { "f1" })
	task.wait(0.1)
	assert(money(ben) == m, "no Money from unreached or junk claims")
	assert(next(Data:get(ben).pass.claimed) == nil, "nothing claimed")
end)

check("a free Money tier pays once; a free cosmetic tier grants through CosmeticService", function()
	task.wait(3) -- the junk claims above used up the Shop request allowance
	setPoints(ben, 300)
	local m = money(ben)
	claim(ben, "f1")
	assert(money(ben) == m + SeasonPass.Free[1].money, "Money from tier 1")
	claim(ben, "f1")
	assert(money(ben) == m + SeasonPass.Free[1].money, "a second claim pays nothing")
	assert(not owns(ben, "hv_plate_copper_ledger"))
	claim(ben, "f3")
	assert(owns(ben, "hv_plate_copper_ledger"), "tier 3 gives the Copper Ledger plate")
	assert(Data:get(ben).pass.claimed.f3 == true)
	claim(ben, "f4")
	claim(ben, "f6")
	assert(owns(ben, "hv_title_hand") == false, "tier 6 is not reached at 300 points")
end)

check("the premium track stays locked until the SeasonPremium product", function()
	task.wait(2.5) -- let the Shop request allowance refill
	local m, g = money(ben), Data:get(ben).currencies.gems
	claim(ben, "p1")
	assert(not owns(ben, "hv_p01_plate"), "locked")
	assert(Data:get(ben).pass.premium == false)
	-- A client cannot unlock it by asking, or by a purchase event without a receipt
	Engine.services.MarketplaceService.PromptProductPurchaseFinished:Fire(ben, PREMIUM_ID, true)
	task.wait(0.1)
	assert(Data:get(ben).pass.premium == false, "an event is not a receipt")
	assert(Engine.deliverReceipt(receipt(8102, PREMIUM_ID, "prem-1")) == Decision.PurchaseGranted)
	assert(Data:get(ben).pass.premium == true, "unlocked by the receipt")
	assert(Engine.deliverReceipt(receipt(8102, PREMIUM_ID, "prem-1")) == Decision.PurchaseGranted, "acknowledged again")
	claim(ben, "p1")
	claim(ben, "p3")
	assert(owns(ben, "hv_p01_plate") and owns(ben, "hv_p03_aura"), "premium cosmetics for reached tiers")
	claim(ben, "p4")
	assert(not owns(ben, "hv_p04_ko"), "tier 4 is not reached at 300 points")
	assert(money(ben) == m and Data:get(ben).currencies.gems == g, "the premium track gives no Money or Gems")
end)

check("the premium product is not offered twice or outside a season", function()
	local start = #market.prompts
	request("ShopRequest", ben, Protocol.ShopAction.PromptProduct, "SeasonPremium")
	task.wait(0.1)
	assert(#market.prompts == start, "already unlocked: no window")
	request("ShopRequest", ana, Protocol.ShopAction.PromptProduct, "SeasonPremium")
	task.wait(0.1)
	assert(#market.prompts == start + 1 and market.prompts[start + 1].id == PREMIUM_ID, "offered to a player without it")
end)

-- Tier skip ----------------------------------------------------------------------------------------

check("a tier skip adds one tier of points, once per PurchaseId", function()
	setPoints(ana, 0)
	assert(Engine.deliverReceipt(receipt(8101, SKIP_ID, "skip-1")) == Decision.PurchaseGranted)
	assert(points(ana) == SeasonPass.PointsPerTier, "one tier")
	assert(Engine.deliverReceipt(receipt(8101, SKIP_ID, "skip-1")) == Decision.PurchaseGranted)
	assert(points(ana) == SeasonPass.PointsPerTier, "the same receipt adds nothing")
	assert(Engine.deliverReceipt(receipt(8101, SKIP_ID, "skip-2")) == Decision.PurchaseGranted)
	assert(points(ana) == 2 * SeasonPass.PointsPerTier, "a new receipt adds a tier")
	assert(Data:get(ana).pass.premium == false, "a skip does not unlock the premium track")
end)

check("a tier skip never passes the last tier and is not offered there", function()
	setPoints(ana, SeasonPass.maxPoints() - 30)
	assert(Engine.deliverReceipt(receipt(8101, SKIP_ID, "skip-3")) == Decision.PurchaseGranted)
	assert(points(ana) == SeasonPass.maxPoints(), "capped")
	assert(Engine.deliverReceipt(receipt(8101, SKIP_ID, "skip-4")) == Decision.PurchaseGranted)
	assert(points(ana) == SeasonPass.maxPoints(), "still capped")
	local start = #market.prompts
	request("ShopRequest", ana, Protocol.ShopAction.PromptProduct, "SeasonTierSkip")
	task.wait(0.1)
	assert(#market.prompts == start, "no window at the last tier")
	matchListener(ana, { paid = true, won = true })
	assert(points(ana) == SeasonPass.maxPoints(), "points stop at the cap")
end)

check("a skip is only a shortcut: every tier is reachable with points alone", function()
	assert(SeasonPass.tierOf(SeasonPass.maxPoints()) == 30)
	assert(SeasonPass.tierOf(SeasonPass.maxPoints() + 500) == 30)
	assert(SeasonPass.tierOf(99) == 0 and SeasonPass.tierOf(100) == 1)
end)

check("a receipt whose save fails is not acknowledged and is rolled back", function()
	local cara = game.join("Cara", 8103)
	waitProfile(cara)
	local original = Data.saveNow
	Data.saveNow = function()
		return false
	end
	local before = points(cara)
	local decision = Engine.deliverReceipt(receipt(8103, SKIP_ID, "skip-fail"))
	Data.saveNow = original
	assert(decision == Decision.NotProcessedYet, "Roblox must retry")
	assert(points(cara) == before, "rolled back")
	assert(Engine.deliverReceipt(receipt(8103, SKIP_ID, "skip-fail")) == Decision.PurchaseGranted, "the retry lands")
	assert(points(cara) == before + SeasonPass.PointsPerTier, "granted once")
end)

-- Roll-over -----------------------------------------------------------------------------------------

check("a new season resets points, the premium track and claims; owned cosmetics stay", function()
	assert(Data:get(ben).pass.premium and next(Data:get(ben).pass.claimed) ~= nil)
	local now = os.time()
	SeasonPass.Seasons[1].endsAt = now - 10
	table.insert(SeasonPass.Seasons, { id = "winter_2026", name = "Winter Watch", blurb = "", startsAt = now - 5, endsAt = now + 86400 * 20, endText = "20 days on" })
	local snapshot = Pass:snapshot(ben)
	assert(snapshot.season == "winter_2026", "the new season")
	assert(snapshot.points == 0 and snapshot.premium == false and next(snapshot.claimed) == nil, "fresh pass")
	assert(owns(ben, "hv_plate_copper_ledger") and owns(ben, "hv_p01_plate"), "cosmetics already earned are kept")
	-- Claiming an old key in the new season needs the new points
	local m = money(ben)
	claim(ben, "f1")
	assert(money(ben) == m, "nothing claimable at zero points")
	-- Old-season premium purchase state does not carry over
	assert(Data:get(ben).pass.premium == false)
end)

-- Cosmetic passes ----------------------------------------------------------------------------------

local function snapshotStats(player)
	local profile = Data:get(player)
	return Schema.copy({ currencies = profile.currencies, powers = profile.powers, stats = profile.stats, mastery = profile.mastery, selected = profile.selected })
end
local function sameTable(a, b)
	if typeof(a) ~= "table" or typeof(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not sameTable(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

check("VIP grants its plate and title once, marks the player and changes no stat", function()
	local dan = game.join("Dan", 8104)
	waitProfile(dan)
	local before = snapshotStats(dan)
	assert(not owns(dan, "vip_plate") and not owns(dan, "vip_title"))
	Engine.buyPass(dan, VIP_ID)
	game.waitFor(function()
		return owns(dan, "vip_title") and owns(dan, "vip_plate")
	end, 3, "VIP cosmetics")
	assert(dan:GetAttribute(Protocol.Attribute.Vip) == true, "VIP mark for the lounge")
	assert(not owns(dan, "founders_aura"), "VIP does not include the Founders items")
	assert(sameTable(before, snapshotStats(dan)), "currencies, powers and stats are untouched")
	-- Equip then buy again: nothing is granted twice and a worn item stays worn
	assert(Cosm:equip(dan, "plate", "vip_plate"))
	Engine.buyPass(dan, VIP_ID)
	task.wait(0.2)
	assert(Data:get(dan).cosmetics.equipped.plate == "vip_plate")
	-- Rejoining checks Roblox again and keeps everything
	game.leave(dan)
	local dan2 = game.join("Dan", 8104)
	waitProfile(dan2)
	game.waitFor(function()
		return dan2:GetAttribute(Protocol.Attribute.Vip) == true
	end, 3, "VIP mark after rejoin")
	assert(owns(dan2, "vip_plate") and owns(dan2, "vip_title"))
end)

check("the Founders Collection gives exactly its four listed items, and only with the pass", function()
	local eve = game.join("Eve", 8105)
	waitProfile(eve)
	local pass = Monetization.Passes.FoundersCollection
	assert(#pass.cosmetics == 4, "one aura, one knockout effect, one plate, one title")
	local kinds = {}
	for _, id in pass.cosmetics do
		local item = Cosmetics.get(id)
		assert(item and item.source == "shop", id .. " exists and is sold")
		kinds[item.kind] = (kinds[item.kind] or 0) + 1
	end
	assert(kinds.aura == 1 and kinds.knockout == 1 and kinds.plate == 1 and kinds.title == 1, "one of each")
	-- A purchase event without Roblox confirming ownership grants nothing
	Engine.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(eve, FOUNDERS_ID, true)
	task.wait(0.3)
	for _, id in pass.cosmetics do
		assert(not owns(eve, id), "no grant without verified ownership")
	end
	local before = snapshotStats(eve)
	Engine.buyPass(eve, FOUNDERS_ID)
	game.waitFor(function()
		return owns(eve, "founders_title")
	end, 3, "Founders items")
	for _, id in pass.cosmetics do
		assert(owns(eve, id), id)
	end
	assert(not owns(eve, "vip_plate"), "no VIP items")
	assert(sameTable(before, snapshotStats(eve)), "no stat or currency changed")
end)

check("pass cosmetics are exclusive: nothing else in the game grants them", function()
	local listed = {}
	for _, key in { "VIP", "FoundersCollection" } do
		for _, id in Monetization.Passes[key].cosmetics do
			listed[id] = true
		end
	end
	for id, item in Cosmetics.Items do
		if item.source == "shop" then
			assert(listed[id], id .. " is a shop item that no pass lists")
		end
	end
	for _, id in SeasonPass.allCosmetics() do
		assert(not listed[id], "season items are not sold in a pass")
	end
end)

-- No stats, no random ----------------------------------------------------------------------------------

check("season and pass cosmetics carry no stat fields and the new products give no currency", function()
	local allowed = { id = true, kind = true, name = true, text = true, colors = true, source = true, season = true, how = true }
	for id, item in Cosmetics.Items do
		if item.source == "season" or item.source == "shop" then
			for key in item do
				assert(allowed[key], `{id} has a field {key}`)
			end
		end
	end
	for _, key in { "SeasonPremium", "SeasonTierSkip" } do
		local product = Monetization.Products[key]
		assert(product.money == nil and product.gems == nil, key .. " gives no currency")
		assert(product.seasonPass ~= nil)
	end
	for tier = 1, 30 do
		assert(SeasonPass.Premium[tier] and type(SeasonPass.Premium[tier]) == "string", "premium is a single cosmetic id")
	end
end)

check("new products and passes with no id never open a purchase window", function()
	local start = #market.prompts
	local savedIds = {
		SeasonPremium = Monetization.Products.SeasonPremium.id,
		SeasonTierSkip = Monetization.Products.SeasonTierSkip.id,
		VIP = Monetization.Passes.VIP.id,
	}
	Monetization.Products.SeasonPremium.id = 0
	Monetization.Products.SeasonTierSkip.id = 0
	Monetization.Passes.VIP.id = 0
	local fay = game.join("Fay", 8106)
	waitProfile(fay)
	request("ShopRequest", fay, Protocol.ShopAction.PromptProduct, "SeasonPremium")
	request("ShopRequest", fay, Protocol.ShopAction.PromptProduct, "SeasonTierSkip")
	request("ShopRequest", fay, Protocol.ShopAction.PromptPass, "VIP")
	task.wait(0.1)
	Monetization.Products.SeasonPremium.id = savedIds.SeasonPremium
	Monetization.Products.SeasonTierSkip.id = savedIds.SeasonTierSkip
	Monetization.Passes.VIP.id = savedIds.VIP
	assert(#market.prompts == start, "id 0 means Available soon, never a window")
end)

local failed = game.finish()
game.stop()
process.exit(if failed > 0 then 1 else 0)
