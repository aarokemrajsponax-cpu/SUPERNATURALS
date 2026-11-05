-- Client smoke test for the Season pass window and the shop's Season pass category:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke_seasonpass.luau build/game.rbxl
-- The track (30 tiers, free and premium rows), points, claim buttons that only ask the server,
-- the premium and tier-skip offers (Available soon at id 0, live prices otherwise), the season's
-- real end date as plain text with no countdown, and the shop's listings for the two new passes.

local process = require("@lune/process")
local Client = require("./smoke/Client")

local t = Client.load(process.args[1])
local task, Engine = t.task, t.Engine
local market = Engine.marketplace

local Monetization = t.shared("Config.Monetization")
local SeasonPass = t.shared("Config.SeasonPass")
local Cosmetics = t.shared("Config.Cosmetics")
local PriceFetcher = t.client("PriceFetcher")
local ShopWindow = t.client("UI.ShopWindow")

-- The pass is running whatever day the test is run
local season = SeasonPass.Seasons[1]
season.startsAt = os.time() - 3600
season.endsAt = os.time() + 86400 * 9

local function profile(extra)
	local view = {
		currencies = { money = 0, gems = 0 },
		selected = { power = "StrongDude", degree = 1 },
		settings = { cameraShake = true, uiScale = 1 },
		passes = {},
		pass = { season = season.id, points = 0, premium = false, claimed = {} },
	}
	for k, v in extra or {} do
		view[k] = v
	end
	return view
end

local ui = t.startUI(profile({ pass = { season = season.id, points = 750, premium = false, claimed = { f1 = true } } }))
local Shell, gui = ui.Shell, ui.gui

local function settle()
	task.wait(0.1)
end
local function window()
	return t.findNamed(gui, "Window_SeasonPass")
end
local function allText(root)
	local texts = {}
	for _, item in root:GetDescendants() do
		if item:IsA("TextLabel") or item:IsA("TextButton") then
			table.insert(texts, item.Text)
		end
	end
	return texts
end
local function cell(track, tier)
	return t.findNamed(window(), `Cell_{track}_{tier}`)
end

t.check("the Season pass window is registered, in the dock, and opens", function()
	assert(Shell.hasWindow("SeasonPass"), "registered")
	Shell.open("SeasonPass")
	settle()
	assert(Shell.isOpen("SeasonPass") and window(), "open")
end)

t.check("the track shows 30 tiers in a free row and a premium row, with the right states", function()
	for tier = 1, 30 do
		assert(cell("free", tier) and cell("premium", tier), "tier " .. tier)
	end
	-- 750 points = tier 7; tier 1 already claimed
	assert(t.findNamed(cell("free", 1), "Status").Text == "Claimed", "claimed")
	assert(t.findNamed(cell("free", 2), "Claim"), "tier 2 can be claimed")
	assert(t.findNamed(cell("free", 7), "Claim"), "tier 7 can be claimed")
	assert(t.findNamed(cell("free", 8), "Status").Text == "Tier 8", "tier 8 not reached")
	assert(t.findNamed(cell("premium", 3), "Status").Text == "Premium only", "premium is locked")
	assert(not t.findNamed(cell("premium", 3), "Claim"), "no claim on a locked premium tier")
	assert(t.findNamed(cell("free", 3), "Name").Text == Cosmetics.get(SeasonPass.Free[3].cosmetic).name, "cosmetic name")
	assert(t.findNamed(cell("free", 2), "Name").Text == "100 Money", "money tier")
end)

t.check("points and the season's end date are plain text, with no countdown or pressure", function()
	local joined = table.concat(allText(window()), "\n")
	assert(string.find(joined, "Tier 7 of 30. 750 points, 50 to tier 8.", 1, true), "points line")
	assert(string.find(joined, season.endText, 1, true), "real end date")
	for _, word in { "hurry", "last chance", "limited", "expires", "only today", "countdown", "left!", "\u{2014}" } do
		assert(not string.find(string.lower(joined), word, 1, true), "pressure wording: " .. word)
	end
end)

t.check("Claim sends one ClaimTier request naming the key; the server decides", function()
	local start = #Engine.sent
	t.press(t.findNamed(cell("free", 2), "Claim"))
	local sent = t.sentSince(start, "ShopRequest", "ClaimTier")
	assert(#sent == 1 and sent[1].args[2] == "f2", "ClaimTier f2")
	local before = #Engine.sent
	t.press(t.findNamed(window(), "ClaimAll"))
	task.wait(3)
	local all = t.sentSince(before, "ShopRequest", "ClaimTier")
	assert(#all == 6, "claim all asks for the six reachable rewards, got " .. #all)
end)

t.check("offers say Available soon while ids are 0, and show Roblox's price once set", function()
	PriceFetcher.clear()
	Shell.open("SeasonPass")
	settle()
	local premium = t.findNamed(window(), "Offer_Premiumtrack")
	local skip = t.findNamed(window(), "Offer_Tierskip")
	assert(premium and skip, "both offers")
	assert(t.findNamed(premium, "Price").Text == "Available soon" and t.findNamed(premium, "Action").Text == "Available soon")
	Monetization.Products.SeasonPremium.id = 7301
	Monetization.Products.SeasonTierSkip.id = 7302
	market.prices[7301] = 421
	market.prices[7302] = 37
	PriceFetcher.clear()
	Shell.open("SeasonPass")
	task.wait(0.3)
	Shell.open("SeasonPass")
	settle()
	premium = t.findNamed(window(), "Offer_Premiumtrack")
	skip = t.findNamed(window(), "Offer_Tierskip")
	assert(t.findNamed(premium, "Price").Text == "R$ 421", "premium price from Roblox: " .. t.findNamed(premium, "Price").Text)
	assert(t.findNamed(skip, "Price").Text == "R$ 37", "skip price from Roblox")
	local start = #Engine.sent
	t.press(t.findNamed(premium, "Action"))
	t.press(t.findNamed(skip, "Action"))
	local sent = t.sentSince(start, "ShopRequest", "PromptProduct")
	assert(#sent == 2 and sent[1].args[2] == "SeasonPremium" and sent[2].args[2] == "SeasonTierSkip", "prompt requests")
end)

t.check("an unlocked premium track shows Unlocked and its tiers can be claimed", function()
	t.fire("DataEvent", "Profile", profile({ pass = { season = season.id, points = 750, premium = true, claimed = {} } }))
	settle()
	assert(t.findNamed(cell("premium", 3), "Claim"), "premium tier 3 claimable")
	assert(t.findNamed(t.findNamed(window(), "Offer_Premiumtrack"), "Action").Text == "Unlocked")
end)

t.check("at the last tier the skip is not offered", function()
	t.fire("DataEvent", "Profile", profile({ pass = { season = season.id, points = SeasonPass.maxPoints(), premium = true, claimed = {} } }))
	settle()
	assert(t.findNamed(t.findNamed(window(), "Offer_Tierskip"), "Action").Text == "Last tier reached")
end)

t.check("the shop lists the Season pass category and the two new passes with exact contents", function()
	t.fire("DataEvent", "Profile", profile())
	Shell.open("Shop")
	settle()
	local shop = t.findNamed(gui, "Window_Shop")
	t.press(t.findNamed(shop, "Rail_SeasonPass"))
	settle()
	local names = {}
	for _, item in shop:GetDescendants() do
		if string.sub(item.Name, 1, 5) == "Card_" and item:IsA("GuiObject") then
			table.insert(names, t.findNamed(item, "Name").Text)
		end
	end
	assert(#names == 3, "pass card plus two products: " .. table.concat(names, ","))
	t.press(t.findNamed(shop, "Rail_Cosmetics"))
	settle()
	local found = {}
	for _, item in shop:GetDescendants() do
		if string.sub(item.Name, 1, 5) == "Card_" and item:IsA("GuiObject") then
			found[t.findNamed(item, "Name").Text] = t.findNamed(item, "Contents").Text
		end
	end
	local vip, founders = found["VIP"], found["Founders Collection"]
	assert(vip and founders, "VIP and Founders Collection are listed")
	for _, id in Monetization.Passes.VIP.cosmetics do
		assert(string.find(vip, Cosmetics.get(id).name, 1, true), "VIP lists " .. id)
	end
	for _, id in Monetization.Passes.FoundersCollection.cosmetics do
		assert(string.find(founders, Cosmetics.get(id).name, 1, true), "Founders lists " .. id)
	end
	assert(string.find(vip, "gold name", 1, true) and string.find(vip, "Looks only", 1, true))
end)

for _, size in { { 1280, 720 }, { 667, 375 } } do
	t.check(`layout at {size[1]}x{size[2]}: window and shop category`, function()
		t.setScreen(size[1], size[2])
		t.fire("DataEvent", "Profile", profile({ pass = { season = season.id, points = 750, premium = false, claimed = { f1 = true } } }))
		Shell.open("SeasonPass")
		settle()
		t.auditLayout(window(), `Season pass {size[1]}x{size[2]}`)
		Shell.open("Shop")
		settle()
		local shop = t.findNamed(gui, "Window_Shop")
		for _, id in { "SeasonPass", "Cosmetics" } do
			t.press(t.findNamed(shop, "Rail_" .. id))
			settle()
			t.auditLayout(shop, `Shop {id} {size[1]}x{size[2]}`)
		end
	end)
end
t.setScreen(1280, 720)

t.finish()
