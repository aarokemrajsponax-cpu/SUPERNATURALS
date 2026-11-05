-- The Lounge wheel (DECISIONS 41). Every prize, its chance and its text live here, and this one
-- table is what the server draws from and what the wheel and the Wheel window show, so the odds
-- on screen are the odds in the draw.
--
-- Rules (binding):
--   * Chances are whole percentages and add up to exactly 100 (tests/wheel_test checks it).
--   * Prizes are Money, small Gem amounts, 24 hour trials of the premium fighters, and
--     cosmetics that only the wheel gives (Config/Cosmetics, "Wheel" section). A cosmetic the
--     player already owns is paid as DuplicateMoney instead, and the window says so.
--   * One free spin per UTC day for everyone. Paid spins come from the developer products
--     LoungeSpin and LoungeSpin5 (Config/Monetization) and are never shown to a player Roblox
--     marks as restricted for paid random items (WheelService).
--   * Nothing here is a countdown, a "last chance" or a pressure line.

local Wheel = {}

-- Seconds in the day the free spin resets on (UTC midnight)
Wheel.DaySeconds = 86400

-- What a duplicate cosmetic is paid as, stated on the wheel and in the window
Wheel.DuplicateMoney = 600

-- Gems paid for each held paid spin when Roblox says paid random items are restricted for the player
-- (matches the shop rate for the 25 R$ product). Only used after a successful policy answer.
Wheel.CreditGems = 50

-- Most paid spins a player can hold at once (a safety limit; the window says how many are held)
Wheel.MaxCredits = 50

-- Last results kept in the profile and shown in the window
Wheel.HistoryKept = 5

-- The server draws from the prizes in this order. kind: "money" | "gems" | "trial" | "cosmetic".
-- percent: the chance of one spin landing here, in whole percent.
Wheel.Prizes = {
	{ id = "money200", mark = "200", kind = "money", amount = 200, percent = 24, label = "200 Money", short = "200" },
	{ id = "money500", mark = "500", kind = "money", amount = 500, percent = 20, label = "500 Money", short = "500" },
	{ id = "money1000", mark = "1K", kind = "money", amount = 1000, percent = 11, label = "1,000 Money", short = "1,000" },
	{ id = "money2500", mark = "2.5K", kind = "money", amount = 2500, percent = 4, label = "2,500 Money", short = "2,500" },
	{ id = "gems10", mark = "10", symbol = "gem", kind = "gems", amount = 10, percent = 12, label = "10 Gems", short = "10 Gem" },
	{ id = "gems30", mark = "30", symbol = "gem", kind = "gems", amount = 30, percent = 5, label = "30 Gems", short = "30 Gem" },
	{ id = "trialCorruption", board = "Corruption trial", mark = "C", kind = "trial", power = "Corruption", hours = 24, percent = 4, label = "Corruption trial, 24 hours", short = "Corrupt" },
	{ id = "trialSyntax", board = "Syntax trial", mark = "S", kind = "trial", power = "Syntax", hours = 24, percent = 4, label = "Syntax trial, 24 hours", short = "Syntax" },
	{ id = "trialAdmin", board = "Admin trial", mark = "A", kind = "trial", power = "Admin", hours = 24, percent = 4, label = "Admin Powers trial, 24 hours", short = "Admin" },
	{ id = "cosmeticLantern", board = "Lantern Ring aura", mark = "", symbol = "ring", kind = "cosmetic", cosmetic = "wheel_aura_lantern", percent = 4, label = "Lantern Ring aura", short = "Aura" },
	{ id = "cosmeticSpotlight", board = "Spotlight Burst", mark = "", symbol = "burst", kind = "cosmetic", cosmetic = "wheel_ko_spotlight", percent = 4, label = "Spotlight Burst knockout effect", short = "Burst" },
	{ id = "cosmeticMarquee", board = "Marquee nameplate", mark = "", symbol = "plate", kind = "cosmetic", cosmetic = "wheel_plate_marquee", percent = 4, label = "Marquee nameplate", short = "Plate" },
}

-- On the wheel itself each wedge shows only `mark` (short upright text) and `symbol` ("gem", "ring",
-- "burst", "plate"); the chances are on the legend board beside the wheel and in the Wheel window.
-- Segment colours on the physical wheel and in the window, by prize kind (display only)
Wheel.KindColors = {
	money = { 214, 150, 70 },
	gems = { 63, 214, 232 },
	trial = { 150, 120, 220 },
	cosmetic = { 226, 184, 84 },
}

-- The rules text shown with the odds, before any spin or purchase
Wheel.RulesText = "Every prize and its chance is listed here. Each spin is drawn on the server and is independent of the last. Owned cosmetics are paid as Money instead."
Wheel.FreeText = "One free spin every day for everyone."
Wheel.PaidText = "Paid spins are optional and cost Robux. Prizes are the same for free and paid spins."

function Wheel.total(): number
	local sum = 0
	for _, prize in Wheel.Prizes do
		sum += prize.percent
	end
	return sum
end

function Wheel.byId(id: string): (any, number?)
	for index, prize in Wheel.Prizes do
		if prize.id == id then
			return prize, index
		end
	end
	return nil, nil
end

-- The prize for a roll from 0 up to (not including) 100: walks the table in order
function Wheel.pick(roll: number): (any, number)
	local edge = 0
	for index, prize in Wheel.Prizes do
		edge += prize.percent
		if roll < edge then
			return prize, index
		end
	end
	local last = #Wheel.Prizes
	return Wheel.Prizes[last], last
end

-- The UTC day number a time falls in
function Wheel.dayOf(time: number): number
	return math.floor(time / Wheel.DaySeconds)
end

-- Odds as plain lines for the window and the wheel's sign: "Money 200: 24%"
function Wheel.oddsLines(): { string }
	local lines = {}
	for _, prize in Wheel.Prizes do
		table.insert(lines, `{prize.label}: {prize.percent}%`)
	end
	return lines
end

return Wheel
