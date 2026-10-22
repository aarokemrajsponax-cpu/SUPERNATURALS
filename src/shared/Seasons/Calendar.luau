-- Pure date math for working out which holiday season a date falls in.
-- No Roblox APIs here, so it can be tested outside Studio.

local Calendar = {}

-- Days since 1970-01-01 for a calendar date
function Calendar.dayNumber(year: number, month: number, day: number): number
	local y = if month <= 2 then year - 1 else year
	local era = y // 400
	local yearOfEra = y - era * 400
	local shiftedMonth = (month + 9) % 12
	local dayOfYear = (153 * shiftedMonth + 2) // 5 + day - 1
	local dayOfEra = yearOfEra * 365 + yearOfEra // 4 - yearOfEra // 100 + dayOfYear
	return era * 146097 + dayOfEra - 719468
end

-- 0 = Sunday ... 6 = Saturday
function Calendar.weekday(year: number, month: number, day: number): number
	-- 1970-01-01 was a Thursday
	return (Calendar.dayNumber(year, month, day) + 4) % 7
end

-- Easter Sunday (Western), using the Anonymous Gregorian algorithm
function Calendar.easter(year: number): (number, number)
	local a = year % 19
	local b = year // 100
	local c = year % 100
	local d = b // 4
	local e = b % 4
	local f = (b + 8) // 25
	local g = (b - f + 1) // 3
	local h = (19 * a + b - d - g + 15) % 30
	local i = c // 4
	local k = c % 4
	local l = (32 + 2 * e + 2 * i - h - k) % 7
	local m = (a + 11 * h + 22 * l) // 451
	local n = h + l - 7 * m + 114
	return n // 31, n % 31 + 1
end

-- US Thanksgiving: the fourth Thursday of November
function Calendar.thanksgiving(year: number): number
	local firstThursday = 1 + (4 - Calendar.weekday(year, 11, 1)) % 7
	return firstThursday + 21
end

local function range(year: number, startMonth: number, startDay: number, endYear: number, endMonth: number, endDay: number): (number, number)
	return Calendar.dayNumber(year, startMonth, startDay), Calendar.dayNumber(endYear, endMonth, endDay)
end

-- Each season's first and last day (inclusive) for a given year.
-- Checked in this order, so earlier entries win when two overlap.
Calendar.Windows = {
	{
		id = "NewYears",
		window = function(year: number)
			return range(year, 12, 30, year + 1, 1, 2)
		end,
	},
	{
		id = "Valentines",
		window = function(year: number)
			return range(year, 2, 7, year, 2, 15)
		end,
	},
	{
		id = "StPatricks",
		window = function(year: number)
			return range(year, 3, 10, year, 3, 18)
		end,
	},
	{
		id = "Easter",
		window = function(year: number)
			local month, day = Calendar.easter(year)
			local easter = Calendar.dayNumber(year, month, day)
			return easter - 7, easter + 1
		end,
	},
	{
		id = "Halloween",
		window = function(year: number)
			return range(year, 10, 1, year, 11, 1)
		end,
	},
	{
		id = "Thanksgiving",
		window = function(year: number)
			return range(year, 11, 2, year, 11, Calendar.thanksgiving(year) + 3)
		end,
	},
	{
		id = "Christmas",
		window = function(year: number)
			return range(year, 12, 1, year, 12, 29)
		end,
	},
}

-- Returns the season id for a date, or nil outside every holiday
function Calendar.seasonFor(year: number, month: number, day: number): string?
	local today = Calendar.dayNumber(year, month, day)
	for _, entry in Calendar.Windows do
		-- Also check last year's window, for seasons that run past New Year's Day
		for _, windowYear in { year - 1, year } do
			local first, last = entry.window(windowYear)
			if today >= first and today <= last then
				return entry.id
			end
		end
	end
	return nil
end

return Calendar
