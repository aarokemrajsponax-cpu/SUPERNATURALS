-- Holiday login calendars: one gift to claim on each UTC day of a holiday, with rewards that
-- grow with the number of days a player claimed and one exclusive prize for claiming every day.
--
-- The rules, in one place and shown to players as written here:
--   * One gift per UTC day. A day can be claimed on its own date, or up to CatchUpDays later,
--     so one missed day does not end a run (the owner can set CatchUpDays to 0 for strict).
--   * Milestones pay out by the number of days claimed (any days), so everyone is rewarded
--     for what they attended.
--   * Claiming every day pays the perfect set: never sold, never offered again.
--   * No gift is random, nothing is sold here, and nothing changes a stat. A premium fighter
--     trial ticket is 24 hours of full use of that fighter in every mode.
--
-- Profile data: profile.calendars[id] = { claimed = { [dayKey] = true }, perfect = bool,
-- milestones = { [countKey] = true } }. dayKey is the day number as text ("1".."26").
--
-- Pure data and date arithmetic (no services), so Schema and the tests can use it.

local Calendars = {}

local DAY = 86400
Calendars.DAY = DAY

-- A missed day can still be claimed this many days later (0 = strict, one chance per day)
Calendars.CatchUpDays = 1

-- Fighters a calendar may hand out as trial tickets (premium powers only)
Calendars.TrialPowers = { Corruption = true, Syntax = true, Admin = true }
Calendars.TrialHours = 24

-- Calendar ids, in the order they run
Calendars.Order = { "harvest_2026", "advent_2026" }

Calendars.List = {} :: { [string]: any }

local function money(day: number, days: number, low: number, high: number): number
	local t = if days > 1 then (day - 1) / (days - 1) else 1
	return math.floor((low + (high - low) * (t ^ 1.25)) / 25 + 0.5) * 25
end

-- spec: { id, name, short, startsAt, days, overrides = { [day] = { gems, cosmetic, trial } },
--         milestones = { { count, money, cosmetic } }, perfect = { name, cosmetics, ... } }
local function build(spec)
	local calendar = {
		id = spec.id,
		name = spec.name,
		short = spec.short,
		holiday = spec.holiday,
		startsAt = spec.startsAt,
		days = spec.days,
		gifts = {},
		milestones = spec.milestones,
		perfect = spec.perfect,
	}
	for day = 1, spec.days do
		local gift = { money = money(day, spec.days, 100, 600) }
		for key, value in spec.overrides[day] or {} do
			gift[key] = value
		end
		calendar.gifts[day] = gift
	end
	Calendars.List[spec.id] = calendar
end

-- Thanksgiving: 5 to 26 November 2026, 22 gifts, the last on Thanksgiving Day
build({
	id = "harvest_2026",
	name = "Harvest Calendar",
	short = "Harvest",
	holiday = "Thanksgiving",
	startsAt = 1793836800, -- 5 Nov 2026 00:00 UTC
	days = 22,
	overrides = {
		[2] = { gems = 10 },
		[4] = { cosmetic = "cal_hv_plate_gourd" },
		[6] = { trial = "Corruption" },
		[8] = { gems = 15 },
		[9] = { cosmetic = "cal_hv_title_table" },
		[11] = { cosmetic = "cal_hv_plate_cornice" },
		[13] = { trial = "Syntax" },
		[15] = { gems = 20 },
		[17] = { cosmetic = "cal_hv_ko_husk" },
		[19] = { cosmetic = "cal_hv_aura_hearth" },
		[20] = { trial = "Admin" },
		[22] = { gems = 25, cosmetic = "cal_hv_title_thanks" },
	},
	milestones = {
		{ count = 5, money = 300, cosmetic = "cal_hv_ms_title_guest" },
		{ count = 10, money = 500, cosmetic = "cal_hv_ms_plate_long_table" },
		{ count = 15, money = 800, cosmetic = "cal_hv_ms_ko_cider" },
		{ count = 20, money = 1200, cosmetic = "cal_hv_ms_aura_window" },
	},
	perfect = {
		title = "Perfect Harvest",
		cosmetics = { "cal_hv_perfect_aura", "cal_hv_perfect_ko", "cal_hv_perfect_title" },
	},
})

-- Christmas: 1 to 25 December 2026, 25 gifts, the last on Christmas Day
build({
	id = "advent_2026",
	name = "Advent Calendar",
	short = "Advent",
	holiday = "Christmas",
	startsAt = 1796083200, -- 1 Dec 2026 00:00 UTC
	days = 25,
	overrides = {
		[3] = { cosmetic = "cal_ad_plate_frost" },
		[5] = { gems = 10 },
		[8] = { trial = "Corruption" },
		[10] = { cosmetic = "cal_ad_title_lamplighter" },
		[12] = { gems = 15 },
		[14] = { cosmetic = "cal_ad_plate_evergreen" },
		[16] = { trial = "Syntax" },
		[18] = { cosmetic = "cal_ad_ko_snowfall" },
		[20] = { gems = 20 },
		[21] = { cosmetic = "cal_ad_aura_candle" },
		[24] = { trial = "Admin" },
		[25] = { gems = 25, cosmetic = "cal_ad_title_midwinter" },
	},
	milestones = {
		{ count = 5, money = 300, cosmetic = "cal_ad_ms_title_keeper" },
		{ count = 10, money = 500, cosmetic = "cal_ad_ms_plate_ribbon" },
		{ count = 15, money = 800, cosmetic = "cal_ad_ms_ko_sleigh" },
		{ count = 20, money = 1200, cosmetic = "cal_ad_ms_aura_garland" },
	},
	perfect = {
		title = "Perfect Advent",
		cosmetics = { "cal_ad_perfect_aura", "cal_ad_perfect_ko", "cal_ad_perfect_title" },
	},
})

-- Lookups and date arithmetic -----------------------------------------------------------------

function Calendars.get(id: any): any?
	return if typeof(id) == "string" then Calendars.List[id] else nil
end

function Calendars.dayKey(day: number): string
	return tostring(day)
end

function Calendars.milestoneKey(count: number): string
	return tostring(count)
end

-- Start of a calendar's last day, and the end of its whole claiming window (UTC seconds)
function Calendars.lastDayStart(calendar): number
	return calendar.startsAt + (calendar.days - 1) * DAY
end

function Calendars.endsAt(calendar): number
	return calendar.startsAt + calendar.days * DAY
end

-- When the last day can no longer be claimed (the end plus the catch-up days)
function Calendars.closesAt(calendar, catchUp: number?): number
	return Calendars.endsAt(calendar) + (if catchUp == nil then Calendars.CatchUpDays else catchUp) * DAY
end

-- Which day of the calendar `now` is (1 on the first day), or 0 before it starts. Past the last
-- day it keeps counting (days + 1 is the day after), so catch-up can be judged.
function Calendars.dayOf(calendar, now: number): number
	if now < calendar.startsAt then
		return 0
	end
	return math.floor((now - calendar.startsAt) / DAY) + 1
end

-- The calendar whose claiming window contains `now`, and today's day number within it
function Calendars.current(now: number, catchUp: number?): (any?, number)
	for _, id in Calendars.Order do
		local calendar = Calendars.List[id]
		if now >= calendar.startsAt and now < Calendars.closesAt(calendar, catchUp) then
			return calendar, Calendars.dayOf(calendar, now)
		end
	end
	return nil, 0
end

-- The next calendar that has not started yet
function Calendars.nextAfter(now: number): any?
	for _, id in Calendars.Order do
		local calendar = Calendars.List[id]
		if now < calendar.startsAt then
			return calendar
		end
	end
	return nil
end

-- UTC start of day `day` of a calendar
function Calendars.dayStart(calendar, day: number): number
	return calendar.startsAt + (day - 1) * DAY
end

-- Can day `day` be claimed at `now` (it exists, has begun, and is today or within catch-up)?
function Calendars.claimableDay(calendar, day: number, now: number, catchUp: number?): boolean
	if day < 1 or day > calendar.days or day % 1 ~= 0 then
		return false
	end
	local today = Calendars.dayOf(calendar, now)
	if today < day then
		return false
	end
	return today - day <= (if catchUp == nil then Calendars.CatchUpDays else catchUp)
end

-- How many days are in a claimed set
function Calendars.countClaimed(claimed: { [string]: boolean }?): number
	local n = 0
	for _ in claimed or {} do
		n += 1
	end
	return n
end

-- Known keys, for Schema repair
function Calendars.validDayKey(calendar, key: any): boolean
	local n = if typeof(key) == "string" then tonumber(key) else nil
	return n ~= nil and n % 1 == 0 and n >= 1 and n <= calendar.days and tostring(n) == key
end

function Calendars.validMilestoneKey(calendar, key: any): boolean
	for _, milestone in calendar.milestones do
		if tostring(milestone.count) == key then
			return true
		end
	end
	return false
end

-- Every cosmetic id a calendar can hand out
function Calendars.cosmeticIds(calendar): { string }
	local ids = {}
	for _, gift in calendar.gifts do
		if gift.cosmetic then
			table.insert(ids, gift.cosmetic)
		end
	end
	for _, milestone in calendar.milestones do
		table.insert(ids, milestone.cosmetic)
	end
	for _, id in calendar.perfect.cosmetics do
		table.insert(ids, id)
	end
	return ids
end

-- Plain text for a day's gift: "450 Money, 10 Gems, Gourd Lamp nameplate". `nameOf(cosmeticId)`
-- is supplied by the caller so this file needs no cosmetic registry.
function Calendars.describeGift(gift, nameOf: (string) -> string, powerName: ((string) -> string)?): string
	local parts = {}
	if gift.money then
		table.insert(parts, `{gift.money} Money`)
	end
	if gift.gems then
		table.insert(parts, `{gift.gems} Gems`)
	end
	if gift.cosmetic then
		table.insert(parts, nameOf(gift.cosmetic))
	end
	if gift.trial then
		table.insert(parts, `{Calendars.TrialHours} hours of {if powerName then powerName(gift.trial) else gift.trial}`)
	end
	return table.concat(parts, ", ")
end

return Calendars
