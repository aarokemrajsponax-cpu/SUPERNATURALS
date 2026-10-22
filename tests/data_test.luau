-- Runs the saved-data services for real (DataService, CurrencyService,
-- PurchaseService) against the stand-in DataStore and Marketplace in
-- tests/smoke/Engine.luau, with simulated players:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/data_test.luau build/game.rbxl
-- Covers loading and saving, rejoining, autosave, save failures (including
-- the final save and unsaveable values), session locks held or abandoned by
-- other servers, temporary errors vs. DataStores being unavailable,
-- newer-version data, Robux receipts (granted once, never unsaved), game
-- passes, spending, settings, and saving everyone when the server closes.
-- Waits are shortened so it runs in seconds.

local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local Engine = require("./smoke/Engine")

local world = Engine.load(process.args[1] or "build/game.rbxl")
local task = Engine.task
local Decision = roblox.Enum.ProductPurchaseDecision

local passed, failed = 0, 0
local function check(name: string, fn: () -> ())
	local before = #Engine.errors
	local ok, err = pcall(fn)
	if ok and #Engine.errors > before then
		ok, err = false, "errors were thrown inside the game code (see above)"
	end
	if ok then
		passed += 1
		print("ok   " .. name)
	else
		failed += 1
		print("FAIL " .. name)
		print("     " .. tostring(err))
	end
end

local function find(path)
	return world.find(path)
end

local function waitUntil(condition: () -> boolean, timeout: number, label: string)
	local started = os.clock()
	while not condition() do
		if os.clock() - started > timeout then
			error("timed out waiting for " .. label, 2)
		end
		task.wait(0.02)
	end
end

-- Shorten every wait, and put one pass and one product on sale ---------------------------
local Schema = world.require(find("ReplicatedStorage.Shared.Data.Schema"))
local Config = Schema.Config
Config.AutosaveInterval = 0.4
Config.RetryBaseDelay = 0.02
Config.RetryMaxDelay = 0.05
Config.LeaveSaveDelay = 0.05
Config.LoadAttempts = 5
Config.CloseTimeout = 5
Config.WaitTimeout = 3

local Monetization = world.require(find("ReplicatedStorage.Shared.Config.Monetization"))
local CORRUPTION_PASS = 1111
local GEMS_PRODUCT = 2222
Monetization.Passes.CorruptionPower.id = CORRUPTION_PASS
Monetization.Products.GemsMedium.id = GEMS_PRODUCT
Monetization.PromptCooldown = 0
Monetization.OwnershipCheckAttempts = 2
Engine.marketplace.prices[CORRUPTION_PASS] = Monetization.Passes.CorruptionPower.robux
Engine.marketplace.prices[GEMS_PRODUCT] = Monetization.Products.GemsMedium.robux

-- Every DataStore call yields a little, like the real one
Engine.dataStores.latency = 0.01
local stores = Engine.dataStores
local STORE = Config.StoreName
local function keyOf(userId: number): string
	return Config.KeyPrefix .. userId
end
local function record(userId: number)
	return Engine.readStore(STORE, keyOf(userId))
end
local function savedMoney(userId: number): number?
	local saved = record(userId)
	return saved and saved.data and saved.data.currencies.money
end

-- Start the services the way Bootstrap does --------------------------------------------------
local ORDER = { "AntiExploitService", "DataService", "CurrencyService", "PurchaseService" }
local services = {}
for _, name in ORDER do
	services[name] = world.require(find("ServerScriptService.Server.Services." .. name))
end
for _, name in ORDER do
	if services[name].Init then
		services[name]:Init(services)
	end
end
for _, name in ORDER do
	if services[name].Start then
		Engine.gameTask.spawn(services[name].Start, services[name])
	end
end
task.wait(0.1)

local Data = services.DataService
local Currency = services.CurrencyService
local Purchases = services.PurchaseService
local AntiExploit = services.AntiExploitService

-- Until AntiExploitService has its "Settings" limit, give the test the planned one
local RateLimiter = world.require(find("ReplicatedStorage.Shared.Utility.RateLimiter"))
if not AntiExploit:allow({ Name = "probe", UserId = -1 } :: any, "Settings") then
	print('note: AntiExploitService has no "Settings" limit yet; using rate 1/s, burst 4 for this test')
	local limiter = RateLimiter.new(1, 4)
	local original = AntiExploit.allow
	AntiExploit.allow = function(self, player, channel)
		if channel == "Settings" then
			return RateLimiter.allow(limiter, player, os.clock())
		end
		return original(self, player, channel)
	end
end

local Players = world.services.Players
local remotes = find("ReplicatedStorage.Remotes")
local function request(remote: string, player, ...)
	Engine.signalOf(remotes:FindFirstChild(remote), "OnServerEvent"):Fire(player, ...)
end

local function join(name: string, userId: number)
	local player = world.Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Parent = world.game:GetService("Players")
	table.insert(Engine.players, player)
	Players.PlayerAdded:Fire(player)
	return player
end
local function leave(player)
	local index = table.find(Engine.players, player)
	if index then
		table.remove(Engine.players, index)
	end
	Players.PlayerRemoving:Fire(player)
	player.Parent = nil
end

-- DataEvent messages sent to a player (after position `since` in Engine.sent)
local function dataSent(player, kind: string, since: number?)
	local list = {}
	for index = (since or 0) + 1, #Engine.sent do
		local entry = Engine.sent[index]
		if entry.remote == "DataEvent" and entry.kind == "FireClient" and entry.args[1] == player and entry.args[2] == kind then
			table.insert(list, entry.args[3])
		end
	end
	return list
end
local function lastData(player, kind: string)
	local list = dataSent(player, kind)
	return list[#list]
end

local loadedNames = {}
Data:onLoaded(function(player)
	table.insert(loadedNames, player.Name)
end)
local grantedPasses = {}
Purchases:onPassGranted(function(player, passKey)
	table.insert(grantedPasses, player.Name .. ":" .. passKey)
end)

-- Tests ----------------------------------------------------------------------------------------

local alice
check("first join gets the starting profile, a lock and a Profile view", function()
	alice = join("Alice", 201)
	waitUntil(function()
		return Data:get(alice) ~= nil
	end, 2, "Alice's profile")
	local profile = Data:get(alice)
	assert(profile.currencies.money == Config.StartingMoney, "starting money " .. profile.currencies.money)
	assert(profile.currencies.gems == Config.StartingGems, "starting gems")
	assert(profile.meta.sessions == 1, "first session")
	assert(Data:isPersistent(alice), "saving")
	local view = lastData(alice, "Profile")
	assert(view and view.currencies.money == Config.StartingMoney, "view sent")
	assert(view.receipts == nil and view.meta == nil and view.rewardLog == nil, "view hides private data")
	local saved = record(201)
	assert(saved and saved.lock and saved.lock.jobId == Engine.jobId, "lock taken")
	waitUntil(function()
		return table.find(loadedNames, "Alice") ~= nil
	end, 1, "onLoaded")
	assert(Data:waitFor(alice, 1) == profile, "waitFor returns the loaded profile")
end)

check("updates send views at most 4 times a second, ending with the latest", function()
	task.wait(0.3)
	local before = #Engine.sent
	for _ = 1, 10 do
		assert(Data:update(alice, function(profile)
			profile.stats.wins += 1
		end), "update applied")
	end
	task.wait(0.05)
	local views = dataSent(alice, "Profile", before)
	assert(#views <= 2, `{#views} views sent at once`)
	task.wait(0.35)
	assert(lastData(alice, "Profile").stats.wins == 10, "the latest view has every change")
end)

check("a change function that errors or waits is refused", function()
	local ok = Data:update(alice, function()
		error("broken change")
	end)
	assert(ok == false, "erroring change reported")
	local waited = Data:update(alice, function()
		task.wait(0.01)
	end)
	assert(waited == false, "waiting change reported")
	assert(Data:update(Players:GetPlayers()[1], function() end) == false, "no profile, no update")
end)

check("changes survive leaving and rejoining straight away", function()
	Data:update(alice, function(profile)
		profile.currencies.money = 777
		profile.powers.Ghost = { xp = 30, degrees = { ["2"] = true }, abilities = {}, owned = false }
		profile.base.items = { { i = "Sofa", x = 3, z = 4, r = 1, c = 2, m = 1 } }
	end)
	leave(alice)
	-- Joining again at once must wait for the last session's save, not load old data
	alice = join("Alice", 201)
	waitUntil(function()
		return Data:get(alice) ~= nil
	end, 3, "Alice's second profile")
	local profile = Data:get(alice)
	assert(profile.currencies.money == 777, "money restored: " .. profile.currencies.money)
	assert(profile.powers.Ghost.xp == 30 and profile.powers.Ghost.degrees["2"], "power progress restored")
	assert(profile.base.items[1].i == "Sofa", "furniture restored")
	assert(profile.stats.wins == 10, "stats restored")
	assert(profile.meta.sessions == 2, "second session")
	assert(Data:isPersistent(alice), "saving")
end)

check("autosave writes changed profiles while the player stays", function()
	Data:update(alice, function(profile)
		profile.currencies.money = 800
	end)
	waitUntil(function()
		return savedMoney(201) == 800
	end, 2, "the autosave")
	assert(record(201).lock.jobId == Engine.jobId, "lock kept")
end)

check("a failed save keeps the changes and saves them at the next try", function()
	stores.failures.UpdateAsync = Config.SaveAttempts
	Data:update(alice, function(profile)
		profile.currencies.money = 900
	end)
	waitUntil(function()
		return (stores.failures.UpdateAsync or 0) == 0
	end, 2, "the failing save")
	task.wait(0.02)
	assert(savedMoney(201) == 800, "nothing written by the failed save")
	waitUntil(function()
		return savedMoney(201) == 900
	end, 2, "the retried save")
end)

check("saveNow writes immediately", function()
	Data:update(alice, function(profile)
		profile.currencies.money = 950
	end)
	assert(Data:saveNow(alice) == true, "saved")
	assert(savedMoney(201) == 950, "in the store")
end)

local bob
check("another server's fresh lock: plays unsaved, told why, saved data untouched", function()
	Engine.writeStore(STORE, keyOf(301), {
		data = { version = 1, currencies = { money = 4242, gems = 3 } },
		lock = { jobId = "other-server", session = "theirs", at = os.time() },
	})
	bob = join("Bob", 301)
	waitUntil(function()
		return Data:get(bob) ~= nil
	end, 3, "Bob's fallback profile")
	assert(not Data:isPersistent(bob), "not saving")
	assert(Data:get(bob).currencies.money == Config.StartingMoney, "plays on a fresh copy")
	local notice = lastData(bob, "Persistence")
	assert(notice and notice.saving == false and string.find(notice.message, "another server"), "told why")
	Data:update(bob, function(profile)
		profile.currencies.money = 1
	end)
	assert(Data:saveNow(bob) == false, "saveNow refuses")
	assert(Purchases:promptProduct(bob, "GemsMedium") == false, "no Robux products while unsaved")
	local decision = Engine.deliverReceipt({ PlayerId = 301, ProductId = GEMS_PRODUCT, PurchaseId = "bob-1", CurrencySpent = 199 })
	assert(decision == Decision.NotProcessedYet, "receipt waits until saving works")
	assert(Data:get(bob).currencies.gems == Config.StartingGems, "no gems granted unsaved")
	leave(bob)
	task.wait(0.2)
	local saved = record(301)
	assert(saved.data.currencies.money == 4242, "real data untouched")
	assert(saved.lock.jobId == "other-server", "their lock untouched")
end)

check("a lock released during the retries is picked up", function()
	Engine.writeStore(STORE, keyOf(302), {
		data = { version = 1, currencies = { money = 5151, gems = 0 } },
		lock = { jobId = "other-server", session = "theirs", at = os.time() },
	})
	local cara
	task.spawn(function()
		cara = join("Cara", 302)
	end)
	-- Once a second attempt has started, the first one found the lock
	waitUntil(function()
		local attempts = 0
		for _, call in stores.calls do
			if call.key == keyOf(302) then
				attempts += 1
			end
		end
		return attempts >= 2
	end, 1, "a second load attempt")
	-- The other server finishes saving and lets go
	Engine.writeStore(STORE, keyOf(302), { data = { version = 1, currencies = { money = 5252, gems = 0 } } })
	waitUntil(function()
		return cara ~= nil and Data:get(cara) ~= nil
	end, 3, "Cara's profile")
	assert(Data:isPersistent(cara), "saving")
	assert(Data:get(cara).currencies.money == 5252, "the other server's final save is loaded")
	leave(cara)
end)

local dave
check("a stale lock from a server that died is taken over", function()
	Engine.writeStore(STORE, keyOf(303), {
		data = { version = 1, currencies = { money = 6000, gems = 0 } },
		lock = { jobId = "dead-server", session = "gone", at = os.time() - Config.LockTimeout - 5 },
	})
	dave = join("Dave", 303)
	waitUntil(function()
		return Data:get(dave) ~= nil
	end, 2, "Dave's profile")
	assert(Data:isPersistent(dave), "saving")
	assert(Data:get(dave).currencies.money == 6000, "saved money loaded")
	assert(record(303).lock.jobId == Engine.jobId, "lock is ours now")
end)

check("if another server takes a profile over, this server stops saving it", function()
	Engine.writeStore(STORE, keyOf(303), {
		data = { version = 1, currencies = { money = 1, gems = 0 } },
		lock = { jobId = "other-server", session = "theirs", at = os.time() },
	})
	Data:update(dave, function(profile)
		profile.currencies.money = 999
	end)
	assert(Data:saveNow(dave) == false, "save refused")
	assert(not Data:isPersistent(dave), "stopped saving")
	local notice = lastData(dave, "Persistence")
	assert(notice and notice.saving == false, "player told")
	leave(dave)
	task.wait(0.2)
	assert(savedMoney(303) == 1, "the newer server's data wins")
	assert(record(303).lock.jobId == "other-server", "their lock untouched")
end)

check("every load attempt failing: unsaved session that never overwrites", function()
	Engine.writeStore(STORE, keyOf(304), { data = { version = 1, currencies = { money = 7777, gems = 0 } } })
	stores.failures.UpdateAsync = 1000
	local eve = join("Eve", 304)
	waitUntil(function()
		return Data:get(eve) ~= nil
	end, 3, "Eve's fallback profile")
	stores.failures.UpdateAsync = 0
	assert(not Data:isPersistent(eve), "not saving")
	assert(Data:get(eve).currencies.money == Config.StartingMoney, "plays on defaults")
	assert(lastData(eve, "Persistence").saving == false, "told")
	Data:update(eve, function(profile)
		profile.currencies.money = 2
	end)
	leave(eve)
	task.wait(0.2)
	assert(savedMoney(304) == 7777, "real data untouched")
	assert(record(304).lock == nil, "no lock written")
end)

check("data from a newer game version is played read-only", function()
	Engine.writeStore(STORE, keyOf(305), {
		data = { version = Schema.VERSION + 1, currencies = { money = 3000, gems = 9 }, futureThing = { on = true } },
	})
	local finn = join("Finn", 305)
	waitUntil(function()
		return Data:get(finn) ~= nil
	end, 2, "Finn's profile")
	assert(Data:get(finn).currencies.money == 3000, "progress shown")
	assert(not Data:isPersistent(finn), "not saving")
	assert(lastData(finn, "Persistence").saving == false, "told")
	Data:update(finn, function(profile)
		profile.currencies.money = 5
	end)
	leave(finn)
	task.wait(0.2)
	local saved = record(305)
	assert(saved.data.currencies.money == 3000 and saved.data.version == Schema.VERSION + 1, "newer data untouched")
	assert(saved.data.futureThing.on == true, "unknown keys untouched")
	assert(saved.lock == nil, "no lock taken")
end)

check("spending refuses more than the balance and bad amounts", function()
	Data:update(alice, function(profile)
		profile.currencies.money = 950
		profile.currencies.gems = 25
	end)
	assert(Currency:balance(alice, "money") == 950, "balance")
	assert(Currency:balance(alice, "coins") == 0, "unknown kind")
	assert(Currency:spend(alice, { money = 2000 }, "test") == false, "can't overspend")
	assert(Currency:spend(alice, { money = 100, gems = 26 }, "test") == false, "all or nothing")
	for _, bad in { { money = -5 }, { money = 1.5 }, { money = 0 / 0 }, { money = math.huge }, { coins = 5 }, "junk" } do
		assert(Currency:spend(alice, bad :: any, "test") == false, "bad price refused")
		assert(Currency:add(alice, bad :: any, "test") == false, "bad grant refused")
	end
	assert(Currency:balance(alice, "money") == 950 and Currency:balance(alice, "gems") == 25, "nothing changed")
	assert(Currency:canAfford(alice, { money = 950, gems = 25 }), "can afford exactly")
	assert(not Currency:canAfford(alice, { gems = 26 }), "can't afford more")
	local before = #Engine.sent
	assert(Currency:spend(alice, { money = 50, gems = 5 }, "test", { toast = true }), "valid spend")
	assert(Currency:balance(alice, "money") == 900 and Currency:balance(alice, "gems") == 20, "deducted")
	local toasts = dataSent(alice, "Toast", before)
	assert(#toasts == 1 and toasts[1].text == "Spent 50 Money and 5 Gems", "spend toast: " .. tostring(toasts[1] and toasts[1].text))
	assert(Currency:add(alice, { money = Config.MaxCurrency }, "test"), "huge grant allowed")
	assert(Currency:balance(alice, "money") == Config.MaxCurrency, "capped at the maximum")
	assert(#dataSent(alice, "Toast", before) == 1, "no toast unless asked")
	Data:update(alice, function(profile)
		profile.currencies.money = 900
	end)
end)

local receipt = { PlayerId = 201, ProductId = GEMS_PRODUCT, PurchaseId = "purchase-1", CurrencySpent = 199, PlaceIdWherePurchased = 0 }
check("a receipt delivered twice grants once", function()
	local gems = Currency:balance(alice, "gems")
	assert(Engine.deliverReceipt(receipt) == Decision.PurchaseGranted, "granted")
	assert(Currency:balance(alice, "gems") == gems + 450, "gems added")
	local saved = record(201)
	assert(table.find(saved.data.receipts, "purchase-1") and saved.data.currencies.gems == gems + 450, "saved with its receipt")
	assert(Engine.deliverReceipt(receipt) == Decision.PurchaseGranted, "second delivery acknowledged")
	assert(Currency:balance(alice, "gems") == gems + 450, "not granted twice")
	local toast = lastData(alice, "Toast")
	assert(toast and string.find(toast.text, "450 Gems"), "thanked")
end)

check("receipts for unknown products or absent players wait for later", function()
	assert(Engine.deliverReceipt({ PlayerId = 201, ProductId = 9999, PurchaseId = "x" }) == Decision.NotProcessedYet, "unknown product")
	assert(Engine.deliverReceipt({ PlayerId = 9999, ProductId = GEMS_PRODUCT, PurchaseId = "y" }) == Decision.NotProcessedYet, "absent player")
	assert(Engine.deliverReceipt("junk") == Decision.NotProcessedYet, "junk receipt")
end)

check("a receipt whose save fails isn't granted; the retry grants exactly once", function()
	local gems = Currency:balance(alice, "gems")
	local second = table.clone(receipt)
	second.PurchaseId = "purchase-2"
	stores.failures.UpdateAsync = 1000
	assert(Engine.deliverReceipt(second) == Decision.NotProcessedYet, "not granted while saving fails")
	stores.failures.UpdateAsync = 0
	assert(Currency:balance(alice, "gems") == gems, "grant taken back")
	assert(not table.find(Data:get(alice).receipts, "purchase-2"), "receipt not recorded")
	assert(Engine.deliverReceipt(second) == Decision.PurchaseGranted, "Roblox's retry is granted")
	assert(Engine.deliverReceipt(second) == Decision.PurchaseGranted, "and acknowledged again")
	assert(Currency:balance(alice, "gems") == gems + 450, "granted exactly once")
	assert(table.find(record(201).data.receipts, "purchase-2"), "saved")
end)

local gus
check("game passes: ownership found on join, unsold items refused, prompts opened", function()
	Engine.marketplace.owned[401] = { [CORRUPTION_PASS] = true }
	local fay = join("Fay", 401)
	waitUntil(function()
		local profile = Data:get(fay)
		return profile ~= nil and profile.passes.CorruptionPower == true
	end, 2, "Fay's pass to be recorded")
	assert(Purchases:ownsPass(fay, "CorruptionPower"), "owns the pass")
	assert(not Purchases:ownsPass(fay, "SyntaxPower"), "doesn't own another")
	assert(not Purchases:ownsPass(fay, "Nonsense"), "unknown pass")
	assert(table.find(grantedPasses, "Fay:CorruptionPower"), "PowerService would hear about it")
	local before = #Engine.sent
	assert(Purchases:promptPass(fay, "SyntaxPower") == false, "unsold pass refused")
	local toast = dataSent(fay, "Toast", before)[1]
	assert(toast and toast.text == Monetization.NotOnSaleText, "told it isn't on sale")
	assert(Purchases:promptPass(fay, "CorruptionPower") == false, "already owned")
	assert(Purchases:promptProduct(fay, "GemsSmall") == false, "unsold product refused")
	assert(Purchases:promptProduct(fay, "Nonsense") == false, "unknown product")
	assert(Purchases:promptProduct(fay, "GemsMedium") == true, "product prompt opens")
	local prompt = Engine.marketplace.prompts[#Engine.marketplace.prompts]
	assert(prompt.kind == "Product" and prompt.id == GEMS_PRODUCT and prompt.player == fay, "Roblox prompt opened")
	assert(Purchases:passForPower("Corruption") == "CorruptionPower", "power to pass")
	leave(fay)
end)

check("buying a pass in game unlocks it, saves it and reports it once", function()
	gus = join("Gus", 402)
	waitUntil(function()
		return Data:get(gus) ~= nil
	end, 2, "Gus's profile")
	task.wait(0.1)
	assert(not Purchases:ownsPass(gus, "CorruptionPower"), "not owned yet")
	assert(Purchases:promptPass(gus, "CorruptionPower") == true, "prompt opens")
	-- A purchase window closing without buying grants nothing
	world.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(gus, CORRUPTION_PASS, false)
	assert(not Purchases:ownsPass(gus, "CorruptionPower"), "cancelled purchase grants nothing")
	Engine.buyPass(gus, CORRUPTION_PASS)
	assert(Purchases:ownsPass(gus, "CorruptionPower"), "owned after buying")
	assert(Data:get(gus).passes.CorruptionPower == true, "in the profile")
	waitUntil(function()
		local saved = record(402)
		return saved and saved.data and saved.data.passes.CorruptionPower == true
	end, 2, "the pass to be saved")
	local count = 0
	for _, entry in grantedPasses do
		if entry == "Gus:CorruptionPower" then
			count += 1
		end
	end
	assert(count == 1, "reported once, got " .. count)
end)

check("a Roblox outage keeps saved pass ownership; a revoked pass is removed", function()
	leave(gus)
	Engine.marketplace.ownershipFailures = 1000
	gus = join("Gus", 402)
	waitUntil(function()
		return Data:get(gus) ~= nil
	end, 2, "Gus's profile")
	task.wait(0.2)
	Engine.marketplace.ownershipFailures = 0
	assert(Purchases:ownsPass(gus, "CorruptionPower"), "saved ownership used during the outage")
	leave(gus)
	Engine.marketplace.owned[402] = nil
	gus = join("Gus", 402)
	waitUntil(function()
		local profile = Data:get(gus)
		return profile ~= nil and profile.passes.CorruptionPower == nil
	end, 2, "the revoked pass to be removed")
	assert(not Purchases:ownsPass(gus, "CorruptionPower"), "Roblox's answer wins")
end)

check("settings requests are sanitized and rate limited", function()
	request("SettingsRequest", alice, { musicVolume = 5, uiScale = 0.1, cameraShake = false, hacked = true, sfxVolume = 0 / 0 })
	local settings = Data:get(alice).settings
	assert(settings.musicVolume == 1, "volume clamped")
	assert(settings.uiScale == 0.75, "ui scale clamped")
	assert(settings.cameraShake == false, "boolean applied")
	assert(settings.hacked == nil, "unknown key dropped")
	assert(settings.sfxVolume == 0.8, "NaN ignored")
	request("SettingsRequest", alice, "junk")
	request("SettingsRequest", alice, nil)
	for step = 1, 10 do
		request("SettingsRequest", alice, { musicVolume = step / 20 })
	end
	assert(Data:get(alice).settings.musicVolume ~= 0.5, "spam beyond the limit is dropped")
end)

-- UpdateAsync calls made so far for one player's key
local function callsFor(userId: number): number
	local count = 0
	for _, call in stores.calls do
		if call.method == "UpdateAsync" and call.key == keyOf(userId) then
			count += 1
		end
	end
	return count
end

check("a value a DataStore can't store doesn't stop saving", function()
	Data:update(alice, function(profile)
		profile.currencies.money = 1234
		profile.stats.broken = 0 / 0
	end)
	assert(Data:saveNow(alice) == true, "a repaired copy is saved")
	local saved = record(201)
	assert(saved.data.currencies.money == 1234, "progress saved")
	assert(saved.data.stats.broken == nil, "the bad value is left out")
	assert(saved.lock.jobId == Engine.jobId, "lock kept")
	Data:update(alice, function(profile)
		profile.stats.broken = nil
	end)
end)

check("a final save that fails at first is tried again before the player is forgotten", function()
	local ivy = join("Ivy", 601)
	waitUntil(function()
		return Data:get(ivy) ~= nil
	end, 2, "Ivy's profile")
	Data:update(ivy, function(profile)
		profile.currencies.money = 4444
	end)
	local before = callsFor(601)
	stores.failures.UpdateAsync = 1000
	leave(ivy)
	-- Let the whole first round of the final save fail
	local ok = pcall(waitUntil, function()
		return callsFor(601) >= before + Config.SaveAttempts
	end, 3, "the first round of the final save")
	stores.failures.UpdateAsync = 0
	assert(ok, "the final save was tried")
	waitUntil(function()
		local saved = record(601)
		return saved ~= nil and saved.lock == nil
	end, 3, "a later round to save and release the lock")
	assert(savedMoney(601) == 4444, "final changes kept")
end)

check("a temporary '502: API Services' error while loading is retried, not taken as no access", function()
	Engine.writeStore(STORE, keyOf(602), { data = { version = 1, currencies = { money = 6262, gems = 0 } } })
	stores.unavailable = "502: API Services rejected request with error. HTTP 500 (Internal Server Error)"
	-- Joining runs the load in this thread, so it goes in its own
	local jay
	task.spawn(function()
		jay = join("Jay", 602)
	end)
	local retried = pcall(waitUntil, function()
		return callsFor(602) >= 2
	end, 2, "a second load attempt")
	stores.unavailable = nil
	assert(retried, "the load was tried again")
	waitUntil(function()
		return jay ~= nil and Data:get(jay) ~= nil
	end, 3, "Jay's profile")
	assert(Data:isPersistent(jay), "saving")
	assert(Data:get(jay).currencies.money == 6262, "saved money loaded")
	leave(jay)
end)

check("DataStores unavailable (Studio without API access): unsaved, told why, nothing written", function()
	Engine.writeStore(STORE, keyOf(501), { data = { version = 1, currencies = { money = 8888, gems = 0 } } })
	stores.unavailable = "StudioAccessToApisNotAllowed: Studio access to APIs is not allowed."
	local hal = join("Hal", 501)
	waitUntil(function()
		return Data:get(hal) ~= nil
	end, 2, "Hal's profile")
	stores.unavailable = nil
	assert(not Data:isPersistent(hal), "not saving")
	local notice = lastData(hal, "Persistence")
	assert(notice and notice.saving == false and string.find(notice.message, "Studio"), "told how to turn saving on")
	Data:update(hal, function(profile)
		profile.currencies.money = 3
	end)
	leave(hal)
	task.wait(0.2)
	assert(savedMoney(501) == 8888, "real data untouched")
	assert(record(501).lock == nil, "no lock written")
end)

check("the server closing saves everyone and releases their locks", function()
	Data:update(alice, function(profile)
		profile.currencies.money = 4321
	end)
	assert(Engine.close(10), "close finished in time")
	local saved = record(201)
	assert(saved.data.currencies.money == 4321, "final changes saved")
	assert(saved.lock == nil, "Alice's lock released")
	assert(record(402).lock == nil, "Gus's lock released")
	assert(saved.data.stats.playSeconds >= 1, "play time counted: " .. saved.data.stats.playSeconds)
end)

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
