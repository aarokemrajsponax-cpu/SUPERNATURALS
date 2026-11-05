-- Purchase safety, end to end on the real server services (stand-in engine):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/shop_test.luau build/game.rbxl
-- A repeated receipt never grants twice; a player whose data hasn't loaded gets
-- NotProcessedYet and the grant lands after it loads; bad receipts are refused;
-- Gem unlocks are refused when short; owned passes aren't re-sold; items without
-- an id never open a purchase window; a "purchased" event without ownership grants nothing.
-- Real Robux purchases and Creator Hub cannot be exercised here (see FINAL_OWNER_HANDOFF.md).

local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local World = require("./smoke/World")

local CORRUPTION_PASS, GEMS_PRODUCT = 5111, 5222
local game = World.start(process.args[1] or "build/game.rbxl", function(setup)
	-- Ids must be set before the services start (PurchaseService maps them in Init)
	local Monetization = setup.world.require(setup.world.find("ReplicatedStorage.Shared.Config.Monetization"))
	Monetization.Passes.CorruptionPower.id = CORRUPTION_PASS
	Monetization.Products.GemsMedium.id = GEMS_PRODUCT
end)
local task, services, check, request = game.task, game.services, game.check, game.request
local world, Engine = game.world, game.Engine
local Decision = roblox.Enum.ProductPurchaseDecision

local function find(path)
	return world.find(path)
end
local Monetization = world.require(find("ReplicatedStorage.Shared.Config.Monetization"))
local Schema = world.require(find("ReplicatedStorage.Shared.Data.Schema"))
local Protocol = world.require(find("ReplicatedStorage.Shared.Protocol"))
local Powers = world.require(find("ReplicatedStorage.Shared.Powers"))

Monetization.PromptCooldown = 0
Monetization.OwnershipCheckAttempts = 2
Schema.Config.RetryBaseDelay = 0.02

local Data, Purchases, Currency = services.DataService, services.PurchaseService, services.CurrencyService
local market = Engine.marketplace

local function gems(player)
	return Data:get(player).currencies.gems
end
local function receipt(userId, id, extra)
	local r = { PlayerId = userId, ProductId = GEMS_PRODUCT, PurchaseId = id, CurrencyType = roblox.Enum.CurrencyType.Robux, CurrencySpent = 199 }
	for k, v in extra or {} do
		r[k] = v
	end
	return r
end
local function waitUntil(condition, timeout, label)
	game.waitFor(condition, timeout, label)
end

-- A player who is in the server but whose data hasn't started loading (PlayerAdded not seen yet)
Schema.Config.WaitTimeout = 0.1
local PlayersService = world.services.Players
local cara = world.Instance.new("Player")
cara.Name = "Cara"
cara.DisplayName = "Cara"
cara.UserId = 7001
cara.Parent = world.game:GetService("Players")
table.insert(Engine.players, cara)
check("a receipt for a player whose data hasn't loaded returns NotProcessedYet, then lands after load", function()
	assert(Data:get(cara) == nil, "profile should still be loading")
	assert(Engine.deliverReceipt(receipt(7001, "late-1")) == Decision.NotProcessedYet, "not processed yet")
	Schema.Config.WaitTimeout = 3
	PlayersService.PlayerAdded:Fire(cara)
	waitUntil(function()
		return Data:get(cara) ~= nil
	end, 5, "Cara's profile")
	local before = gems(cara)
	assert(Engine.deliverReceipt(receipt(7001, "late-1")) == Decision.PurchaseGranted, "granted on Roblox's retry")
	assert(gems(cara) == before + Monetization.Products.GemsMedium.gems, "reward comes from the product, not the Robux spent")
end)

check("a repeated receipt never grants twice", function()
	local before = gems(cara)
	for _ = 1, 3 do
		assert(Engine.deliverReceipt(receipt(7001, "late-1")) == Decision.PurchaseGranted, "acknowledged again")
	end
	assert(gems(cara) == before, "no extra gems")
	local first = Engine.deliverReceipt(receipt(7001, "dup-2"))
	local second = Engine.deliverReceipt(receipt(7001, "dup-2"))
	assert(first == Decision.PurchaseGranted and second == Decision.PurchaseGranted, "both acknowledged")
	assert(gems(cara) == before + Monetization.Products.GemsMedium.gems, "granted exactly once")
end)

check("CurrencySpent doesn't change the reward", function()
	local before = gems(cara)
	assert(Engine.deliverReceipt(receipt(7001, "regional-3", { CurrencySpent = 90 })) == Decision.PurchaseGranted)
	assert(gems(cara) == before + Monetization.Products.GemsMedium.gems, "a regional price gives the same reward")
end)

check("bad receipts are refused and grant nothing", function()
	local before = gems(cara)
	local bad = {
		"junk",
		{},
		receipt(7001, ""),
		receipt(7001, nil),
		receipt(7001, "b1", { ProductId = 0 }),
		receipt(7001, "b2", { ProductId = 99999 }),
		receipt(7001, "b3", { PlayerId = -4 }),
		receipt(7001, "b4", { PlayerId = "7001" }),
		receipt(9999999, "b5"),
		receipt(7001, "b6", { CurrencySpent = -1 }),
		receipt(7001, "b7", { CurrencySpent = "199" }),
		receipt(7001, "b8", { CurrencySpent = 0 / 0 }),
		receipt(7001, "b9", { CurrencyType = 12345 }),
	}
	for index, r in bad do
		assert(Engine.deliverReceipt(r) == Decision.NotProcessedYet, "bad receipt " .. index .. " must not be granted")
	end
	assert(gems(cara) == before, "nothing granted")
end)

check("Gem items are refused when the player is short", function()
	local corruption = Powers.get("Corruption")
	local have = gems(cara)
	assert(have < corruption.premium.gems, "test needs a short balance")
	request("PowerRequest", cara, Protocol.PowerAction.UnlockPower, "Corruption")
	task.wait(0.2)
	assert(not services.PowerService:owns(cara, "Corruption"), "not unlocked")
	assert(gems(cara) == have, "no Gems taken")
end)

check("unconfigured ids never open a purchase window", function()
	local start = #market.prompts
	request("ShopRequest", cara, Protocol.ShopAction.PromptPass, "ExtraAbilitySlot")
	request("ShopRequest", cara, Protocol.ShopAction.PromptPass, "CelestialDragonStyle")
	request("ShopRequest", cara, Protocol.ShopAction.PromptPass, "AdminPower")
	request("ShopRequest", cara, Protocol.ShopAction.PromptProduct, "GemsSmall")
	request("ShopRequest", cara, Protocol.ShopAction.PromptProduct, "NoSuchProduct")
	request("ShopRequest", cara, Protocol.ShopAction.PromptPass, "NoSuchPass")
	request("ShopRequest", cara, Protocol.ShopAction.PromptPass, 42)
	request("ShopRequest", cara, 7, "GemsMedium")
	task.wait(0.1)
	assert(#market.prompts == start, "no window for an id of 0, an unknown key or junk")
end)

check("a configured pass opens Roblox's window once; an owned pass is not sold again", function()
	local start = #market.prompts
	request("ShopRequest", cara, Protocol.ShopAction.PromptPass, "CorruptionPower")
	task.wait(0.1)
	assert(#market.prompts == start + 1 and market.prompts[start + 1].id == CORRUPTION_PASS, "prompted")
	Engine.buyPass(cara, CORRUPTION_PASS)
	task.wait(0.2)
	assert(Purchases:ownsPass(cara, "CorruptionPower"), "owned after Roblox confirms")
	request("ShopRequest", cara, Protocol.ShopAction.PromptPass, "CorruptionPower")
	task.wait(0.1)
	assert(#market.prompts == start + 1, "not offered again")
end)

check("a purchase event without ownership grants nothing", function()
	local dan = game.join("Dan", 7002)
	waitUntil(function()
		return Data:get(dan) ~= nil
	end, 5, "Dan's profile")
	Engine.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(dan, CORRUPTION_PASS, true)
	task.wait(0.3)
	assert(not Purchases:ownsPass(dan, "CorruptionPower"), "a client or event claim is not ownership")
end)

check("a developer product prompts for a player and the pass key list includes the extra slot", function()
	local start = #market.prompts
	request("ShopRequest", cara, Protocol.ShopAction.PromptProduct, "GemsMedium")
	task.wait(0.1)
	assert(#market.prompts == start + 1 and market.prompts[start + 1].id == GEMS_PRODUCT, "prompted")
	assert(Monetization.Passes.ExtraAbilitySlot and Monetization.Passes.ExtraAbilitySlot.id == 0, "extra slot pass exists, unset")
end)

local failed = game.finish()
game.stop()
process.exit(if failed > 0 then 1 else 0)
