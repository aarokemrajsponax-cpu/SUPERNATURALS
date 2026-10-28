local RateLimiter = Harness.load("Shared/Utility/RateLimiter")
local Calendar = Harness.load("Shared/Seasons/Calendar")

return function(t)
	t.test("rate limiter allows a burst, then refills over time", function()
		local limiter = RateLimiter.new(10, 3)
		t.equal(RateLimiter.allow(limiter, "p", 0), true, "1")
		t.equal(RateLimiter.allow(limiter, "p", 0), true, "2")
		t.equal(RateLimiter.allow(limiter, "p", 0), true, "3")
		t.equal(RateLimiter.allow(limiter, "p", 0), false, "burst used up")
		t.equal(RateLimiter.allow(limiter, "p", 0.1), true, "refilled one token after 0.1s")
		t.equal(RateLimiter.allow(limiter, "other", 0), true, "keys are separate")
		RateLimiter.forget(limiter, "p")
		t.equal(RateLimiter.allow(limiter, "p", 0.1), true, "forgotten keys start full")
	end)

	t.test("rate limiter ignores clocks that go backwards", function()
		local limiter = RateLimiter.new(1, 1)
		RateLimiter.allow(limiter, "p", 10)
		t.equal(RateLimiter.allow(limiter, "p", 5), false, "no refill from a backwards clock")
	end)

	t.test("calendar: weekdays, Easter and Thanksgiving", function()
		t.equal(Calendar.weekday(2026, 10, 20), 2, "2026-10-20 is a Tuesday")
		t.equal(Calendar.weekday(2000, 1, 1), 6, "2000-01-01 is a Saturday")
		local easters = { [2024] = 331, [2025] = 420, [2026] = 405, [2027] = 328, [2038] = 425, [2285] = 322 }
		for year, monthDay in easters do
			local month, day = Calendar.easter(year)
			t.equal(month * 100 + day, monthDay, "Easter " .. year)
		end
		t.equal(Calendar.thanksgiving(2026), 26, "Thanksgiving 2026")
		t.equal(Calendar.thanksgiving(2027), 25, "Thanksgiving 2027")
	end)

	t.test("calendar: holiday seasons", function()
		local cases = {
			{ 2026, 10, 20, "Halloween" },
			{ 2026, 11, 2, "Thanksgiving" },
			{ 2026, 11, 30, nil },
			{ 2026, 12, 25, "Christmas" },
			{ 2026, 12, 31, "NewYears" },
			{ 2027, 1, 2, "NewYears" },
			{ 2027, 1, 3, nil },
			{ 2027, 2, 14, "Valentines" },
			{ 2027, 3, 17, "StPatricks" },
			{ 2027, 3, 21, "Easter" },
			{ 2026, 7, 4, nil },
		}
		for _, case in cases do
			t.equal(Calendar.seasonFor(case[1], case[2], case[3]), case[4], `{case[1]}-{case[2]}-{case[3]}`)
		end
	end)
end
