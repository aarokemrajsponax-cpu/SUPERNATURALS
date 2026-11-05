-- Client smoke test for the Master Shop (UI/ShopWindow, PriceFetcher):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke_shop.luau build/game.rbxl
-- Every category and card at 1280x720 and 667x375 with auditLayout, "Available soon" for ids
-- of 0, prices that come only from Roblox (never a number written in the code), "Price
-- unavailable" when Roblox can't answer, owned and short-of-Gems states, one action per card,
-- and the requests the buttons send.

local process = require("@lune/process")
local Client = require("./smoke/Client")

local t = Client.load(process.args[1])
local task, Engine = t.task, t.Engine
local market = Engine.marketplace

local Monetization = t.shared("Config.Monetization")
local PriceFetcher = t.client("PriceFetcher")
local ShopWindow = t.client("UI.ShopWindow")

local ui = t.startUI({
	currencies = { money = 12000, gems = 6666 },
	selected = { power = "StrongDude", degree = 1 },
	settings = { cameraShake = true, uiScale = 1 },
	passes = {},
})
local Shell, gui = ui.Shell, ui.gui

local function settle()
	task.wait(0.08)
end
local function window()
	return t.findNamed(gui, "Window_Shop")
end
local function category(id: string)
	local button = t.findNamed(window(), "Rail_" .. id)
	assert(button, "rail button " .. id)
	t.press(button)
	settle()
end
local function cards()
	local list = {}
	for _, item in window():GetDescendants() do
		if string.sub(item.Name, 1, 5) == "Card_" and item:IsA("GuiObject") then
			table.insert(list, item)
		end
	end
	return list
end
local function textOf(root, name)
	local label = t.findNamed(root, name)
	return label and label.Text
end
local function robuxTexts()
	local found = {}
	for _, item in window():GetDescendants() do
		if (item:IsA("TextLabel") or item:IsA("TextButton")) and string.find(item.Text, "R$", 1, true) then
			table.insert(found, item.Text)
		end
	end
	return found
end

local itemsByCategory = {}
for _, item in ShopWindow.items() do
	itemsByCategory[item.category] = (itemsByCategory[item.category] or 0) + 1
end

t.check("the Master Shop window is registered and opens", function()
	assert(Shell.hasWindow("Shop"), "Shop registered (the Master Shop door opens Window:Market)")
	Shell.open("Shop")
	settle()
	assert(Shell.isOpen("Shop") and window(), "open")
	assert(#ShopWindow.Categories >= 4, "a category rail")
end)

t.check("ids of 0 show Available soon, never a price, and cannot be bought", function()
	PriceFetcher.clear()
	for _, c in ShopWindow.Categories do
		category(c.id)
		local list = cards()
		assert(#list == (itemsByCategory[c.id] or 0) and #list > 0, c.id .. " lists its items")
	end
	category("Gems")
	assert(#robuxTexts() == 0, "no Robux amount while nothing is on sale")
	for _, card in cards() do
		local action = t.findNamed(card, "Action")
		assert(action and action.Text == "Available soon", "card says Available soon: " .. card.Name)
		assert(textOf(card, "Price") == "Available soon", "price line says Available soon")
	end
	category("Upgrades")
	assert(textOf(cards()[1], "Name") == "Extra Ability Slot", "the Extra Ability Slot pass is listed")
end)

t.check("prices come from Roblox only, and Buy asks the server", function()
	Monetization.Products.GemsMedium.id = 6222
	Monetization.Passes.ExtraAbilitySlot.id = 6333
	-- Prices nobody wrote in the code, so any match proves they were read live
	market.prices[6222] = 137
	market.prices[6333] = 1234
	PriceFetcher.clear()
	category("Gems")
	task.wait(0.3)
	category("Gems")
	local seen = robuxTexts()
	assert(#seen == 1 and seen[1] == "R$ 137", "live price shown: " .. table.concat(seen, ","))
	for _, text in seen do
		for _, key in Monetization.ProductOrder do
			assert(text ~= "R$ " .. tostring(Monetization.Products[key].robux) or Monetization.Products[key].robux == 137, "not a configured price")
		end
	end
	local start = #Engine.sent
	for _, card in cards() do
		if string.find(card.Name, "GemsMedium", 1, true) then
			local action = t.findNamed(card, "Action")
			assert(action.Text == "Buy", "Buy")
			t.press(action)
		end
	end
	local sent = t.sentSince(start, "ShopRequest", "PromptProduct")
	assert(#sent == 1 and sent[1].args[2] == "GemsMedium", "one PromptProduct request")
	category("Upgrades")
	task.wait(0.3)
	category("Upgrades")
	assert(robuxTexts()[1] == "R$ 1,234", "pass price formatted: " .. tostring(robuxTexts()[1]))
end)

t.check("Roblox failing to answer shows Price unavailable", function()
	Monetization.Products.GemsMedium.id = 6444
	market.prices[6444] = 99
	market.infoFailures = 1
	PriceFetcher.clear()
	category("Gems")
	task.wait(0.3)
	category("Gems")
	local found = false
	for _, card in cards() do
		if string.find(card.Name, "GemsMedium", 1, true) then
			found = true
			assert(textOf(card, "Price") == "Price unavailable", "no invented price: " .. tostring(textOf(card, "Price")))
			assert(t.findNamed(card, "Action").Text == "Check again", "retry, not Buy")
		end
	end
	assert(found)
end)

t.check("Gem unlocks: affordable, short and owned states", function()
	category("GemPowers")
	local list = cards()
	assert(#list == 3, "three premium powers")
	local start = #Engine.sent
	local first = t.findNamed(list[1], "Action")
	assert(first.Text == "Unlock", "affordable with 6666 Gems")
	t.press(first)
	assert(#t.sentSince(start, "PowerRequest", "UnlockPower") == 1, "asks the server to unlock")
	t.fire("DataEvent", "Profile", { currencies = { money = 0, gems = 100 }, selected = { power = "StrongDude", degree = 1 }, settings = { uiScale = 1 }, passes = { SyntaxPower = true } })
	settle()
	category("GemPowers")
	local texts = {}
	for _, card in cards() do
		table.insert(texts, t.findNamed(card, "Action").Text)
	end
	assert(string.find(texts[1], "Need", 1, true), "short: " .. texts[1])
	assert(texts[2] == "Owned", "owned: " .. texts[2])
	local before = #Engine.sent
	t.press(t.findNamed(cards()[1], "Action"))
	t.press(t.findNamed(cards()[2], "Action"))
	assert(#t.sentSince(before, "PowerRequest") == 0, "disabled buttons send nothing")
end)

t.check("no text in the shop contains an emoji or an em dash", function()
	for _, c in ShopWindow.Categories do
		category(c.id)
		for _, item in window():GetDescendants() do
			if item:IsA("TextLabel") or item:IsA("TextButton") then
				assert(not string.find(item.Text, "\u{2014}", 1, true), "em dash in: " .. item.Text)
			end
		end
	end
end)

for _, size in { { 1280, 720 }, { 667, 375 } } do
	t.check(`layout at {size[1]}x{size[2]}: every category and card`, function()
		t.setScreen(size[1], size[2])
		Shell.open("Shop")
		settle()
		for _, c in ShopWindow.Categories do
			category(c.id)
			assert(#cards() > 0, c.id .. " has cards")
			t.auditLayout(window(), `Shop {c.id} {size[1]}x{size[2]}`)
		end
	end)
end
t.setScreen(1280, 720)

t.finish()
