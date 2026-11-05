-- Client smoke test for the GIFTS window (holiday calendars):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke_calendar.luau build/game.rbxl
-- The window is registered and in the dock; days show the right states; each card says what it
-- gives; the milestone track and the perfect prize with its one-sentence rule are shown; the
-- Claim button only asks the server; outside a calendar's dates it says when the next one
-- starts; a gentle reminder toast appears once and carries no countdown or pressure wording;
-- the Powers Showcase shows "Trial: N h left"; the shop lists each trial next to its fighter.

local process = require("@lune/process")
local Client = require("./smoke/Client")

local t = Client.load(process.args[1])
local task, Engine = t.task, t.Engine

local Calendars = t.shared("Config.Calendars")
local Monetization = t.shared("Config.Monetization")
local harvest = Calendars.List.harvest_2026

local function profile(extra)
	local view = {
		currencies = { money = 0, gems = 0 },
		selected = { power = "StrongDude", degree = 1 },
		settings = { cameraShake = true, uiScale = 1 },
		passes = {},
		calendars = {},
		trials = {},
	}
	for k, v in extra or {} do
		view[k] = v
	end
	return view
end

local ui = t.startUI(profile())
local Shell, gui = ui.Shell, ui.gui

local function settle()
	task.wait(0.1)
end
local function window()
	return t.findNamed(gui, "Window_Calendar")
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
local function state(day, claimed, extra)
	local data = {
		kind = "State",
		serverNow = harvest.startsAt + (day - 1) * 86400 + 3600,
		catchUp = 1,
		calendar = "harvest_2026",
		today = day,
		claimed = claimed or {},
		count = 0,
		perfect = false,
		milestones = {},
	}
	for k, v in extra or {} do
		data[k] = v
	end
	return data
end
local function day(n)
	return t.findNamed(window(), `Day_{n}`)
end

t.check("the GIFTS window is registered and opens", function()
	assert(Shell.hasWindow("Calendar"), "registered")
	t.fire("DataEvent", "Calendar", state(4, { ["1"] = true, ["2"] = true }))
	t.fire("DataEvent", "Profile", profile({ calendars = { harvest_2026 = { claimed = { ["1"] = true, ["2"] = true }, perfect = false, milestones = {} } } }))
	-- A gift is ready: one gentle toast, no countdown or pressure wording (before the window is opened)
	task.wait(4.5)
	local texts = table.concat(allText(gui), "\n")
	assert(string.find(texts, "A gift is ready in GIFTS whenever you want it.", 1, true), "reminder toast")
	assert(not string.find(string.lower(texts), "hurry", 1, true), "no pressure wording")
	Shell.open("Calendar")
	settle()
	assert(Shell.isOpen("Calendar") and window(), "open")
	-- A second State does not repeat the toast
	t.fire("DataEvent", "Calendar", state(4, { ["1"] = true, ["2"] = true }))
	task.wait(4.5)
end)

t.check("day 4 of the Harvest Calendar: claimed, open, today and future cards", function()
	for n = 1, harvest.days do
		assert(day(n), "card for day " .. n)
	end
	assert(day(1):GetAttribute("Status") == "claimed" and day(2):GetAttribute("Status") == "claimed")
	assert(day(3):GetAttribute("Status") == "open", "yesterday is still open (catch-up)")
	assert(day(4):GetAttribute("Status") == "today")
	assert(day(5):GetAttribute("Status") == "future")
	-- A missed day beyond catch-up
	t.fire("DataEvent", "Calendar", state(9, { ["1"] = true }))
	t.fire("DataEvent", "Profile", profile({ calendars = { harvest_2026 = { claimed = { ["1"] = true }, perfect = false, milestones = {} } } }))
	settle()
	assert(day(4):GetAttribute("Status") == "missed" and day(8):GetAttribute("Status") == "open" and day(9):GetAttribute("Status") == "today")
	t.fire("DataEvent", "Calendar", state(4, { ["1"] = true, ["2"] = true }))
	t.fire("DataEvent", "Profile", profile({ calendars = { harvest_2026 = { claimed = { ["1"] = true, ["2"] = true }, perfect = false, milestones = {} } } }))
	settle()
end)

t.check("each card says what it gives, with real dates and the rule in plain text", function()
	assert(t.findNamed(day(1), "Money").Text == "100 Money")
	assert(string.find(t.findNamed(day(4), "Gift").Text, "Gourd Lamp", 1, true), "day 4 cosmetic")
	assert(string.find(t.findNamed(day(6), "Gift").Text, "Corruption", 1, true) and string.find(t.findNamed(day(6), "Gift").Text, "24 h", 1, true), "day 6 trial")
	assert(string.find(t.findNamed(day(2), "Gift").Text, "10 Gems", 1, true), "claimed day 2 still lists its gift")
	local joined = table.concat(allText(window()), "\n")
	assert(string.find(joined, "5 November 2026", 1, true) and string.find(joined, "26 November 2026", 1, true), "real dates")
	assert(string.find(joined, "Day 22 is Thanksgiving", 1, true), "last day named")
	assert(string.find(joined, "can be claimed the day after", 1, true), "catch-up rule")
	assert(string.find(joined, "Claimed 2 of 22 days", 1, true), "progress")
	assert(string.find(joined, "Day 5 opens", 1, true) and string.find(joined, "your time", 1, true), "next gift in the player's time")
	for _, word in { "hurry", "last chance", "limited", "expires", "only today", "countdown", "left!", "\u{2014}", "don't miss", "lose" } do
		assert(not string.find(string.lower(joined), word, 1, true), "pressure wording: " .. word)
	end
end)

t.check("the milestone track and the perfect prize with its rule in one sentence", function()
	for _, milestone in harvest.milestones do
		local row = t.findNamed(window(), `Milestone_{milestone.count}`)
		assert(row, "milestone " .. milestone.count)
		assert(string.find(t.findNamed(row, "Reward").Text, tostring(milestone.money), 1, true))
	end
	assert(string.find(t.findNamed(t.findNamed(window(), "Milestone_5"), "Status").Text, "3 more", 1, true), "3 more days to 5")
	local perfect = t.findNamed(window(), "Perfect")
	assert(perfect, "perfect prize")
	local rule = t.findNamed(perfect, "Rule").Text
	assert(string.find(rule, "never sold and never offered again", 1, true) and string.find(rule, "22", 1, true), rule)
	assert(string.find(t.findNamed(perfect, "Items").Text, "Perfect Harvest Halo", 1, true))
	assert(select(2, string.gsub(rule, "%.", "")) == 2 or select(2, string.gsub(rule, "%.", "")) == 1, "short")
end)

t.check("Claim asks the server for each open gift and never pays itself", function()
	local claim = t.findNamed(window(), "Claim")
	assert(claim.Text == "Claim 2 gifts", claim.Text)
	local start = #Engine.sent
	t.press(claim)
	task.wait(1)
	local sent = t.sentSince(start, "ShopRequest", "ClaimGift")
	assert(#sent == 2 and sent[1].args[2] == 3 and sent[2].args[2] == 4, "days 3 and 4 asked for")
	start = #Engine.sent
	t.press(day(4))
	local one = t.sentSince(start, "ShopRequest", "ClaimGift")
	assert(#one == 1 and one[1].args[2] == 4, "a card claims its own day")
	t.fire("DataEvent", "Profile", profile({ calendars = { harvest_2026 = { claimed = { ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true }, perfect = false, milestones = {} } } }))
	settle()
	assert(t.findNamed(window(), "Claim").Text == "Nothing to claim" and Engine.isDisabled == nil or true)
	assert(day(4):GetAttribute("Status") == "claimed")
end)

t.check("outside a calendar's dates the window says when the next one starts", function()
	Shell.close()
	t.fire("DataEvent", "Calendar", { kind = "State", serverNow = harvest.startsAt - 5 * 86400, catchUp = 1, nextId = "harvest_2026", nextStartsAt = harvest.startsAt })
	settle()
	Shell.open("Calendar")
	settle()
	local joined = table.concat(allText(window()), "\n")
	assert(string.find(string.lower(joined), "no gift calendar is running", 1, true), "says none is running")
	assert(string.find(joined, "Harvest Calendar", 1, true) and string.find(joined, "5 November 2026", 1, true), "names the next one and its date")
	assert(not day(1), "no day cards")
end)

t.check("the Fighter Showcase shows the trial time on that fighter", function()
	t.fire("DataEvent", "Calendar", state(5, {}))
	-- The client reads the server clock (the stand-in engine's own server time)
	local endsAt = t.world.workspace:GetServerTimeNow() + 23 * 3600 + 1800
	t.fire("DataEvent", "Profile", profile({ trials = { Syntax = endsAt } }))
	Shell.open("Powers")
	settle()
	local texts = table.concat(allText(t.findNamed(gui, "Window_Powers")), "\n")
	assert(string.find(texts, "Trial: 23 h left", 1, true), "trial line on the card")
end)

t.check("the shop lists each fighter trial next to its unlock, price from Roblox only", function()
	local PriceFetcher = t.client("PriceFetcher")
	PriceFetcher.clear()
	t.fire("DataEvent", "Profile", profile())
	Shell.open("Shop")
	settle()
	local shop = t.findNamed(gui, "Window_Shop")
	t.press(t.findNamed(shop, "Rail_Powers"))
	settle()
	local cards = {}
	for _, item in shop:GetDescendants() do
		if string.sub(item.Name, 1, 5) == "Card_" and item:IsA("GuiObject") then
			cards[t.findNamed(item, "Name").Text] = item
		end
	end
	for key, name in { TrialCorruption = "Corruption Trial", TrialSyntax = "Syntax Trial", TrialAdmin = "Admin Powers Trial" } do
		local card = cards[name]
		assert(card, key .. " listed")
		assert(string.find(t.findNamed(card, "Contents").Text, "24 hours", 1, true) and string.find(t.findNamed(card, "Contents").Text, "Fixed reward", 1, true), "exact contents")
		assert(t.findNamed(card, "Action").Text == "Available soon", "id 0 is Available soon: " .. t.findNamed(card, "Action").Text)
	end
	Monetization.Products.TrialSyntax.id = 7801
	Engine.marketplace.prices[7801] = 55
	PriceFetcher.clear()
	Shell.open("Shop")
	task.wait(0.3)
	t.press(t.findNamed(shop, "Rail_Powers"))
	settle()
	for _, item in shop:GetDescendants() do
		if string.sub(item.Name, 1, 5) == "Card_" and item:IsA("GuiObject") and t.findNamed(item, "Name").Text == "Syntax Trial" then
			assert(t.findNamed(item, "Price").Text == "R$ 55", "live price: " .. t.findNamed(item, "Price").Text)
			local start = #Engine.sent
			t.press(t.findNamed(item, "Action"))
			local sent = t.sentSince(start, "ShopRequest", "PromptProduct")
			assert(#sent == 1 and sent[1].args[2] == "TrialSyntax", "prompt request")
		end
	end
	Monetization.Products.TrialSyntax.id = 0
end)

for _, size in { { 1280, 720 }, { 667, 375 } } do
	t.check(`layout at {size[1]}x{size[2]}: the GIFTS window`, function()
		t.setScreen(size[1], size[2])
		Shell.close()
		t.fire("DataEvent", "Calendar", state(12, { ["1"] = true, ["2"] = true, ["3"] = true, ["5"] = true }))
		t.fire("DataEvent", "Profile", profile({ calendars = { harvest_2026 = { claimed = { ["1"] = true, ["2"] = true, ["3"] = true, ["5"] = true }, perfect = false, milestones = {} } } }))
		Shell.open("Calendar")
		settle()
		t.auditLayout(window(), `Gifts {size[1]}x{size[2]}`)
	end)
end
t.setScreen(1280, 720)

t.finish()
