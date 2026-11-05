-- The cosmetic season pass. One season at a time; each has 30 tiers and every tier can be
-- reached by playing. The free track gives a cosmetic every few tiers and small amounts of
-- Money. The premium track (a developer product, "SeasonPremium") gives one cosmetic at every
-- tier and nothing else: no Money, Gems or power. A tier skip ("SeasonTierSkip") adds one
-- tier of points, never more than the last tier, and tiers are never locked behind it.
-- Prices are not here: the shop reads them live from Roblox (PriceFetcher).
--
-- Season ids go in profile.pass.season. When a new season is current, a profile's pass is
-- reset (points, premium and claims) the next time the server looks at it.

local Cosmetics = require(script.Parent.Cosmetics)

local SeasonPass = {}

SeasonPass.TierCount = 30
-- Points to go from one tier to the next (tier n needs n * PointsPerTier in all)
SeasonPass.PointsPerTier = 100

-- Points. Only the values below earn points; nothing else does.
SeasonPass.Points = {
	-- A paid match (the same matches that pay Money; forfeits and idle matches do not count)
	Match = 25,
	-- Added when the match was won
	Win = 15,
	-- A finished practice round of at least MinTrainingSeconds, at most TrainingPerDay a day
	Training = 10,
	-- Claiming a daily challenge
	Daily = 50,
}
SeasonPass.MinTrainingSeconds = 20
SeasonPass.TrainingPerDay = 3

-- Seasons. startsAt and endsAt are UTC unix times (the end is the last second of the day).
SeasonPass.Seasons = {
	{
		id = "harvest_2026",
		name = "Harvest Week",
		blurb = "Copper, amber and bronze for the facility's harvest month.",
		startsAt = 1793491200, -- 1 November 2026, 00:00 UTC
		endsAt = 1796083199, -- 30 November 2026, 23:59:59 UTC
		endText = "30 November 2026",
	},
}

-- Free track: tier -> { money = n } or { cosmetic = id }
-- Premium track: tier -> cosmetic id (all 30 tiers)
local free: { [number]: { [string]: any } } = {}
local premium: { [number]: string } = {}

local FREE_COSMETICS = {
	[3] = "hv_plate_copper_ledger",
	[6] = "hv_title_hand",
	[9] = "hv_plate_amber_row",
	[12] = "hv_ko_chaff",
	[15] = "hv_title_gleaner",
	[18] = "hv_aura_chaff",
	[22] = "hv_plate_furrow",
	[26] = "hv_ko_ember_toll",
	[30] = "hv_title_veteran",
}
local PREMIUM_KIND = { "plate", "title", "aura", "knockout" }
local PREMIUM_SHORT = { plate = "plate", title = "title", aura = "aura", knockout = "ko" }

for tier = 1, SeasonPass.TierCount do
	if FREE_COSMETICS[tier] then
		free[tier] = { cosmetic = FREE_COSMETICS[tier] }
	else
		-- Small, and a little more later in the season
		free[tier] = { money = if tier <= 10 then 100 elseif tier <= 20 then 150 else 200 }
	end
end

-- The premium items were registered in Cosmetics in tier order: hv_p01 to hv_p30
for tier = 1, SeasonPass.TierCount do
	local found: string? = nil
	for _, kind in PREMIUM_KIND do
		local id = string.format("hv_p%02d_%s", tier, PREMIUM_SHORT[kind])
		if Cosmetics.Items[id] then
			found = id
		end
	end
	assert(found, "no premium cosmetic for tier " .. tier)
	premium[tier] = found
end

SeasonPass.Free = free
SeasonPass.Premium = premium

-- Lookups --------------------------------------------------------------------------------------

function SeasonPass.season(id: any): { [string]: any }?
	for _, season in SeasonPass.Seasons do
		if season.id == id then
			return season
		end
	end
	return nil
end

-- The season running at `now`, or nil between seasons
function SeasonPass.current(now: number): { [string]: any }?
	for _, season in SeasonPass.Seasons do
		if now >= season.startsAt and now <= season.endsAt then
			return season
		end
	end
	return nil
end

-- The season to show: the running one, else the one that ended last (or starts next)
function SeasonPass.shown(now: number): { [string]: any }
	local running = SeasonPass.current(now)
	if running then
		return running
	end
	local best = SeasonPass.Seasons[1]
	for _, season in SeasonPass.Seasons do
		if season.startsAt <= now and season.startsAt >= best.startsAt then
			best = season
		end
	end
	return best
end

function SeasonPass.maxPoints(): number
	return SeasonPass.TierCount * SeasonPass.PointsPerTier
end

-- Tiers reached with this many points (0 to TierCount)
function SeasonPass.tierOf(points: number): number
	return math.clamp(math.floor(points / SeasonPass.PointsPerTier), 0, SeasonPass.TierCount)
end

-- Key stored in profile.pass.claimed
function SeasonPass.claimKey(track: string, tier: number): string
	return (if track == "premium" then "p" else "f") .. tostring(tier)
end

-- Every cosmetic the season can give, free track first
function SeasonPass.allCosmetics(): { string }
	local list = {}
	for tier = 1, SeasonPass.TierCount do
		if free[tier].cosmetic then
			table.insert(list, free[tier].cosmetic)
		end
	end
	for tier = 1, SeasonPass.TierCount do
		table.insert(list, premium[tier])
	end
	return list
end

return SeasonPass
