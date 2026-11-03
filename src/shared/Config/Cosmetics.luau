-- Every cosmetic in one registry: titles, nameplate styles, auras and knockout effects.
-- Cosmetics are looks only. Nothing here changes damage, speed, health or any stat, and
-- nothing is ever sold or given as a random roll.
--
-- A profile owns a cosmetic when profile.cosmetics.owned[id] == true, and wears it when
-- profile.cosmetics.equipped[slot] == id (slots below). Grants go through the server only.
--
-- Fields of an item: kind ("title" | "plate" | "aura" | "knockout"), name (shown in lists),
-- text (titles: the line shown under the player's name), colors ({ { r, g, b }, ... } for
-- plates, auras and knockout effects), source (where it comes from: "tutorial", "founder", "group",
-- "referral", "achievement", "season", "shop", "owner"), how (one plain sentence telling the
-- player how to get it). Sections belong to the systems named in them: add entries only in
-- your own section, so systems built at the same time never collide.

local Cosmetics = {}

-- The wearable slots (kept in step with Schema.CosmeticSlots). "knockout" is the effect shown
-- on a knockout you score.
Cosmetics.Slots = { "title", "plate", "aura", "knockout" }

-- Players who first join before this time get the Founding Recruit title (31 Dec 2026, UTC)
Cosmetics.FounderUntil = 1798761599

Cosmetics.Items = {} :: { [string]: { [string]: any } }

local function add(id: string, item: { [string]: any })
	assert(Cosmetics.Items[id] == nil, "duplicate cosmetic " .. id)
	item.id = id
	Cosmetics.Items[id] = item
end
Cosmetics.add = add

-- Onboarding and community (TutorialService, CommunityService) ----------------------------------
add("title_recruit", { kind = "title", name = "Recruit", text = "Recruit", source = "tutorial", how = "Finish Jeffery's tour of the facility." })
add("title_founding", { kind = "title", name = "Founding Recruit", text = "Founding Recruit", source = "founder", how = "Join the facility before the end of 2026." })
add("title_member", { kind = "title", name = "Facility Member", text = "Facility Member", source = "group", how = "Join the game's Roblox group, then rejoin the game." })
add("title_recruiter", { kind = "title", name = "Recruiter", text = "Recruiter", source = "referral", how = "Invite a new player who finishes the tour and one training session." })
add("title_brought_in", { kind = "title", name = "Brought In", text = "Brought In by a Friend", source = "referral", how = "Join through a friend's invite and finish the tour and one training session." })

-- Achievements (AchievementService) -----------------------------------------------------------
add("title_veteran", { kind = "title", name = "Veteran", text = "Veteran", source = "achievement", how = "Win 50 matches." })
add("title_champion", { kind = "title", name = "Champion", text = "Champion", source = "achievement", how = "Win 250 matches." })
add("title_breaker", { kind = "title", name = "Breaker", text = "Breaker", source = "achievement", how = "Knock out 250 fighters." })
add("title_streak", { kind = "title", name = "On a Streak", text = "On a Streak", source = "achievement", how = "Win 5 matches in a row." })
add("title_unbroken", { kind = "title", name = "Unbroken", text = "Unbroken", source = "achievement", how = "Win 10 matches in a row." })
add("title_precise", { kind = "title", name = "Precise", text = "Precise", source = "achievement", how = "Win 10 matches without being knocked out." })
add("title_duelist", { kind = "title", name = "Duelist", text = "Duelist", source = "achievement", how = "Win 5 duels against other players." })
add("title_adept", { kind = "title", name = "Adept", text = "Adept", source = "achievement", how = "Reach mastery level 10 with any fighter." })
add("title_master", { kind = "title", name = "Master", text = "Master", source = "achievement", how = "Reach mastery level 20 with any fighter." })
add("title_all_rounder", { kind = "title", name = "All-Rounder", text = "All-Rounder", source = "achievement", how = "Fight a match with all eight fighters." })
add("title_trainee", { kind = "title", name = "Trainee", text = "Trainee", source = "achievement", how = "Finish 10 practice rounds with Jeffery." })
add("title_archivist", { kind = "title", name = "Archivist", text = "Archivist", source = "achievement", how = "Recover every Archive file." })
add("title_spectator", { kind = "title", name = "Spectator", text = "Spectator", source = "achievement", how = "Watch 10 matches from the Spectating Lounge." })
add("title_neighbour", { kind = "title", name = "Good Neighbour", text = "Good Neighbour", source = "achievement", how = "Visit 5 bases of other players." })
add("title_seasonal", { kind = "title", name = "Seasonal Regular", text = "Seasonal Regular", source = "achievement", how = "Play 5 matches during seasonal decorations." })

-- Season pass (SeasonPassService) ---------------------------------------------------------------
-- Harvest Week, season "harvest_2026": copper, amber and bronze. Free-track items first, then the
-- premium track (one per tier). Which tier gives which item is in Config/SeasonPass.
do
	local COPPER = { 184, 115, 63 }
	local AMBER = { 232, 162, 74 }
	local BRONZE = { 150, 104, 52 }
	local STRAW = { 226, 198, 124 }
	local RUST = { 158, 78, 46 }
	local BRASS = { 200, 160, 70 }
	local function season(id: string, kind: string, name: string, how: string, colors: { { number } }?, text: string?)
		add(id, { kind = kind, name = name, text = text, colors = colors, source = "season", season = "harvest_2026", how = how })
	end
	local free = "Reach its tier on the free track of the Harvest Week pass by playing."
	local premium = "Unlock the premium track of the Harvest Week pass, then reach its tier by playing."

	-- Free track
	season("hv_plate_copper_ledger", "plate", "Copper Ledger", free, { COPPER, AMBER })
	season("hv_title_hand", "title", "Harvest Hand", free, nil, "Harvest Hand")
	season("hv_plate_amber_row", "plate", "Amber Row", free, { AMBER, STRAW })
	season("hv_ko_chaff", "knockout", "Chaff Burst", free, { STRAW, COPPER })
	season("hv_title_gleaner", "title", "Gleaner", free, nil, "Gleaner")
	season("hv_aura_chaff", "aura", "Drifting Chaff", free, { STRAW, AMBER })
	season("hv_plate_furrow", "plate", "Bronze Furrow", free, { BRONZE, COPPER })
	season("hv_ko_ember_toll", "knockout", "Ember Toll", free, { AMBER, RUST })
	season("hv_title_veteran", "title", "Harvest Veteran", free, nil, "Harvest Veteran")

	-- Premium track, one item for each of the 30 tiers
	season("hv_p01_plate", "plate", "Copper Seam", premium, { COPPER, BRONZE })
	season("hv_p02_title", "title", "Silo Keeper", premium, nil, "Silo Keeper")
	season("hv_p03_aura", "aura", "Amber Motes", premium, { AMBER })
	season("hv_p04_ko", "knockout", "Copper Flare", premium, { COPPER, AMBER })
	season("hv_p05_plate", "plate", "Amber Gauge", premium, { AMBER, BRASS })
	season("hv_p06_title", "title", "Gauge Reader", premium, nil, "Gauge Reader")
	season("hv_p07_aura", "aura", "Copper Dust", premium, { COPPER, STRAW })
	season("hv_p08_ko", "knockout", "Amber Shear", premium, { AMBER, STRAW })
	season("hv_p09_plate", "plate", "Bronze Latch", premium, { BRONZE, BRASS })
	season("hv_p10_title", "title", "Shift Foreman", premium, nil, "Shift Foreman")
	season("hv_p11_aura", "aura", "Kiln Embers", premium, { RUST, AMBER })
	season("hv_p12_ko", "knockout", "Scattered Grain", premium, { STRAW, BRONZE })
	season("hv_p13_plate", "plate", "Threshing Floor", premium, { STRAW, COPPER })
	season("hv_p14_title", "title", "Kiln Warden", premium, nil, "Kiln Warden")
	season("hv_p15_aura", "aura", "Straw Gold Drift", premium, { STRAW, BRASS })
	season("hv_p16_ko", "knockout", "Bronze Toll", premium, { BRONZE, BRASS })
	season("hv_p17_plate", "plate", "Kiln Glow", premium, { RUST, AMBER })
	season("hv_p18_title", "title", "Quota Met", premium, nil, "Quota Met")
	season("hv_p19_aura", "aura", "Slow Lanterns", premium, { AMBER, COPPER })
	season("hv_p20_ko", "knockout", "Kiln Burst", premium, { RUST, AMBER })
	season("hv_p21_plate", "plate", "Rust and Brass", premium, { RUST, BRASS })
	season("hv_p22_title", "title", "Copper Marshal", premium, nil, "Copper Marshal")
	season("hv_p23_aura", "aura", "Bronze Ring", premium, { BRONZE, STRAW })
	season("hv_p24_ko", "knockout", "Sheaf Split", premium, { STRAW, COPPER })
	season("hv_p25_plate", "plate", "Granary Lamp", premium, { BRASS, AMBER })
	season("hv_p26_title", "title", "Night Thresher", premium, nil, "Night Thresher")
	season("hv_p27_aura", "aura", "Ember Orchard", premium, { RUST, STRAW })
	season("hv_p28_ko", "knockout", "Last Light", premium, { AMBER, BRASS })
	season("hv_p29_plate", "plate", "Burnished Rail", premium, { BRASS, COPPER })
	season("hv_p30_title", "title", "Keeper of the Last Sheaf", premium, nil, "Keeper of the Last Sheaf")
end

-- Holiday calendars (CalendarService, Config/Calendars) ------------------------------------------
-- Given only by a calendar's daily gifts, attendance milestones or perfect prize. Never sold.
-- The perfect sets are never offered again after their calendar ends.
do
	local COPPER = { 184, 115, 63 }
	local AMBER = { 232, 162, 74 }
	local STRAW = { 226, 198, 124 }
	local RUST = { 158, 78, 46 }
	local BRASS = { 200, 160, 70 }
	local EVERGREEN = { 46, 107, 78 }
	local BERRY = { 168, 50, 62 }
	local FROST = { 190, 220, 236 }
	local CANDLE = { 244, 214, 128 }
	local SPRUCE = { 30, 70, 56 }
	local function cal(calendar: string, id: string, kind: string, name: string, how: string, colors: { { number } }?, text: string?)
		add(id, { kind = kind, name = name, text = text, colors = colors, source = "calendar", calendar = calendar, how = how })
	end
	local function harvest(id: string, kind: string, name: string, how: string, colors: { { number } }?, text: string?)
		cal("harvest_2026", id, kind, name, how, colors, text)
	end
	local function advent(id: string, kind: string, name: string, how: string, colors: { { number } }?, text: string?)
		cal("advent_2026", id, kind, name, how, colors, text)
	end

	-- Harvest Calendar (Thanksgiving, 5 to 26 November 2026)
	harvest("cal_hv_plate_gourd", "plate", "Gourd Lamp", "Day 4 gift of the Harvest Calendar.", { AMBER, RUST })
	harvest("cal_hv_title_table", "title", "Table Setter", "Day 9 gift of the Harvest Calendar.", nil, "Table Setter")
	harvest("cal_hv_plate_cornice", "plate", "Amber Cornice", "Day 11 gift of the Harvest Calendar.", { AMBER, BRASS })
	harvest("cal_hv_ko_husk", "knockout", "Husk Scatter", "Day 17 gift of the Harvest Calendar.", { STRAW, RUST })
	harvest("cal_hv_aura_hearth", "aura", "Hearth Glow", "Day 19 gift of the Harvest Calendar.", { AMBER, COPPER })
	harvest("cal_hv_title_thanks", "title", "Thanks Given", "Day 22 gift of the Harvest Calendar, Thanksgiving Day.", nil, "Thanks Given")
	harvest("cal_hv_ms_title_guest", "title", "Harvest Guest", "Claim 5 days of the Harvest Calendar.", nil, "Harvest Guest")
	harvest("cal_hv_ms_plate_long_table", "plate", "Long Table Brass", "Claim 10 days of the Harvest Calendar.", { BRASS, STRAW })
	harvest("cal_hv_ms_ko_cider", "knockout", "Cider Spark", "Claim 15 days of the Harvest Calendar.", { AMBER, STRAW })
	harvest("cal_hv_ms_aura_window", "aura", "Warm Window", "Claim 20 days of the Harvest Calendar.", { STRAW, AMBER })
	harvest("cal_hv_perfect_aura", "aura", "Perfect Harvest Halo", "Claim every day of the Harvest Calendar. Never sold, never offered again.", { AMBER, COPPER, STRAW })
	harvest("cal_hv_perfect_ko", "knockout", "Perfect Harvest Burst", "Claim every day of the Harvest Calendar. Never sold, never offered again.", { COPPER, AMBER, STRAW })
	harvest("cal_hv_perfect_title", "title", "Perfect Harvest", "Claim every day of the Harvest Calendar. Never sold, never offered again.", nil, "Perfect Harvest")

	-- Advent Calendar (Christmas, 1 to 25 December 2026)
	advent("cal_ad_plate_frost", "plate", "Frost Pane", "Day 3 gift of the Advent Calendar.", { FROST, SPRUCE })
	advent("cal_ad_title_lamplighter", "title", "Lamplighter", "Day 10 gift of the Advent Calendar.", nil, "Lamplighter")
	advent("cal_ad_plate_evergreen", "plate", "Evergreen Rail", "Day 14 gift of the Advent Calendar.", { EVERGREEN, CANDLE })
	advent("cal_ad_ko_snowfall", "knockout", "Snowfall Burst", "Day 18 gift of the Advent Calendar.", { FROST, EVERGREEN })
	advent("cal_ad_aura_candle", "aura", "Candle Ring", "Day 21 gift of the Advent Calendar.", { CANDLE, BERRY })
	advent("cal_ad_title_midwinter", "title", "Midwinter Watch", "Day 25 gift of the Advent Calendar, Christmas Day.", nil, "Midwinter Watch")
	advent("cal_ad_ms_title_keeper", "title", "Advent Keeper", "Claim 5 days of the Advent Calendar.", nil, "Advent Keeper")
	advent("cal_ad_ms_plate_ribbon", "plate", "Berry Ribbon", "Claim 10 days of the Advent Calendar.", { BERRY, CANDLE })
	advent("cal_ad_ms_ko_sleigh", "knockout", "Sleigh Bell Toll", "Claim 15 days of the Advent Calendar.", { CANDLE, FROST })
	advent("cal_ad_ms_aura_garland", "aura", "Garland Drift", "Claim 20 days of the Advent Calendar.", { EVERGREEN, BERRY })
	advent("cal_ad_perfect_aura", "aura", "Perfect Advent Halo", "Claim every day of the Advent Calendar. Never sold, never offered again.", { CANDLE, BERRY, EVERGREEN })
	advent("cal_ad_perfect_ko", "knockout", "Perfect Advent Burst", "Claim every day of the Advent Calendar. Never sold, never offered again.", { BERRY, CANDLE, FROST })
	advent("cal_ad_perfect_title", "title", "Perfect Advent", "Claim every day of the Advent Calendar. Never sold, never offered again.", nil, "Perfect Advent")
end

-- Shop and passes (PurchaseService) -------------------------------------------------------------
-- Sold only as the game passes in Config/Monetization, with every item listed on the shop card.
-- Nothing is random and none of it touches a stat.
do
	local GOLD = { 226, 184, 84 }
	local PALE = { 238, 220, 160 }
	local COPPER = { 184, 115, 63 }
	local function sold(id: string, kind: string, name: string, how: string, colors: { { number } }?, text: string?)
		add(id, { kind = kind, name = name, text = text, colors = colors, source = "shop", how = how })
	end
	local vip = "Included with the VIP pass."
	local founders = "Included with the Founders Collection."
	sold("vip_plate", "plate", "VIP Gold", vip, { GOLD, PALE })
	sold("vip_title", "title", "VIP", vip, nil, "VIP")
	sold("founders_aura", "aura", "Founders' Ring", founders, { GOLD, COPPER })
	sold("founders_ko", "knockout", "Founders' Flare", founders, { GOLD, PALE })
	sold("founders_plate", "plate", "Founders' Brass", founders, { COPPER, GOLD })
	sold("founders_title", "title", "Charter Patron", founders, nil, "Charter Patron")
end

-- Lookups ----------------------------------------------------------------------------------------

function Cosmetics.get(id: string?): { [string]: any }?
	return if typeof(id) == "string" then Cosmetics.Items[id] else nil
end

-- Every item of a kind, sorted by name
function Cosmetics.ofKind(kind: string): { { [string]: any } }
	local list = {}
	for _, item in Cosmetics.Items do
		if item.kind == kind then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

-- Is `slot` one of the wearable slots, and does this item go in it?
function Cosmetics.fits(slot: string, id: string): boolean
	local item = Cosmetics.Items[id]
	return item ~= nil and item.kind == slot and table.find(Cosmetics.Slots, slot) ~= nil
end

return Cosmetics
