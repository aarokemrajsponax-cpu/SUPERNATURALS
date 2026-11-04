-- The shape of a player's saved profile: its defaults, upgrades from older
-- versions, repairs of missing or wrongly typed values, the safe copy the
-- client is allowed to see, and the settings sanitizer. Pure logic with no
-- services, so it's unit tested in Lune (tests/Data.spec.luau).
--
-- Everything in a profile must survive the DataStore's JSON: dictionary keys
-- are strings, arrays are proper sequences, numbers are finite.

local Schema = {}

-- The book's document ids, so saved lore progress only keeps ids that exist
local Archive = require(script.Parent.Parent.Content.Archive)
local LORE_FILES: { [string]: boolean } = {}
local LORE_DOCUMENTS: { [string]: boolean } = {}
for id in Archive.Files do
	LORE_FILES[id] = true
	LORE_DOCUMENTS[id] = true
end
for _, chapter in Archive.Chapters do
	LORE_DOCUMENTS[chapter.id] = true
end

local Homes = require(script.Parent.Parent.Config.Homes)
local Calendars = require(script.Parent.Parent.Config.Calendars)
local Wheel = require(script.Parent.Parent.Config.Wheel)

-- Bump this when the shape changes, and add a MIGRATIONS step below
Schema.VERSION = 1

-- Every tunable number for saved data, the DataStore and currencies
Schema.Config = {
	StartingMoney = 500,
	StartingGems = 25,
	-- No balance can go above this
	MaxCurrency = 1e9,
	-- Single grants at least this big are written to the server log
	BigGrant = { money = 100000, gems = 5000 },

	-- Lengths of the bounded lists
	MaxReceipts = 200,
	MaxRewardLog = 50,
	MaxBaseItems = 400,
	MaxLoadoutSize = 8,
	-- The most degrees any power has; powers with a different count are listed in
	-- PowerDegrees (must match the power's `degreeCount`, checked by Powers.spec)
	MaxDegree = 4,
	DefaultDegrees = 3,
	PowerDegrees = { Grandmaster = 4 },
	MaxFurnitureCount = 9999,
	MaxXp = 1e9,
	MaxTextLength = 100,
	-- The Archive remembers which page of a document you were on, up to this
	MaxLorePage = 99,

	-- DataStore
	StoreName = "SupernaturalsProfiles_v1",
	KeyPrefix = "Player_",
	-- Changed profiles are saved this often (seconds)
	AutosaveInterval = 90,
	-- Unchanged profiles are still saved this often, which refreshes the session lock
	LockRefreshInterval = 300,
	-- A lock not refreshed for this long belongs to a server that died; it can be taken
	LockTimeout = 600,
	-- Tries to load a profile (waiting out another server's lock) before playing unsaved
	LoadAttempts = 6,
	-- Tries per save
	SaveAttempts = 4,
	-- Rounds of SaveAttempts for the final save when a player leaves
	ReleaseRounds = 3,
	-- Waits between tries double from the base up to the maximum (seconds)
	RetryBaseDelay = 1,
	RetryMaxDelay = 8,
	-- Autosaves wait while fewer DataStore requests than this are left in the budget,
	-- keeping some for players who are joining and leaving
	AutosaveBudgetReserve = 5,
	-- After a player leaves, other services get this long to record final changes
	LeaveSaveDelay = 1,
	-- How long the server may spend saving everyone when it shuts down (Roblox allows 30)
	CloseTimeout = 25,
	-- Default wait for DataService:waitFor
	WaitTimeout = 30,
	-- At most one profile view per player this often (seconds)
	ViewInterval = 0.25,
}

-- Equipped cosmetics go in these slots
Schema.CosmeticSlots = { "aura", "victory", "knockout", "title", "trail", "plate" }

-- Who may visit a player's base
Schema.BaseAccess = { "Everyone", "Friends", "Nobody" }

-- Comfort settings: the default of each, and the allowed range of the numbers.
-- The client's Settings module mirrors these defaults.
Schema.Settings = {
	cameraShake = { default = true },
	-- Fewer particles and smaller effects
	reducedEffects = { default = false },
	-- Full-screen flashes and colour shifts from big attacks
	intenseEffects = { default = true },
	musicVolume = { default = 0.5, min = 0, max = 1 },
	sfxVolume = { default = 0.8, min = 0, max = 1 },
	uiScale = { default = 1, min = 0.75, max = 1.25 },
	cameraSensitivity = { default = 1, min = 0.2, max = 2 },
	damageNumbers = { default = true },
	hints = { default = true },
	-- Lock-on: press to lock and tap to switch, or locked only while held
	lockOnMode = { default = "toggle", options = { "toggle", "hold" } },
	-- Aimed abilities cast at the cursor at once instead of entering aiming mode
	quickCast = { default = false },
}

-- Saved data the client never sees
local PRIVATE = { receipts = true, rewardLog = true, meta = true }

export type Settings = { [string]: boolean | number | string }
export type PowerData = {
	xp: number,
	-- Degrees beyond the first that were unlocked: { ["2"] = true }
	degrees: { [string]: boolean },
	-- Extra abilities bought for this power
	abilities: { [string]: boolean },
	-- Premium power unlocked through the Gems path
	owned: boolean,
}
export type BaseItem = { i: string, x: number, z: number, r: number, c: number, m: number }
export type Profile = {
	version: number,
	currencies: { money: number, gems: number },
	stats: { [string]: number },
	powers: { [string]: PowerData },
	-- [powerId][degree as a string] = ability ids in slot order
	loadouts: { [string]: { [string]: { string } } },
	selected: { power: string, degree: number },
	cosmetics: { owned: { [string]: boolean }, equipped: { [string]: string } },
	furniture: { owned: { [string]: number } },
	base: {
		floor: string,
		wall: string,
		lighting: string,
		access: string,
		capacity: number,
		items: { BaseItem },
		-- Decor theme id and display toggles (Config/Homes)
		theme: string,
		show: { [string]: boolean },
	},
	daily: { day: number, progress: { [string]: number }, claimed: { [string]: boolean }, loginStreak: number },
	tutorial: { done: { [string]: boolean }, welcomed: boolean },
	-- The Archive: recovered files, documents read, and where the reader left off
	lore: { found: { [string]: boolean }, read: { [string]: boolean }, last: string, page: number },
	settings: Settings,
	-- Holiday calendars (CalendarService): [calendarId] = { claimed = { [dayKey] = true }, perfect, milestones = { [countKey] = true } }
	calendars: { [string]: { claimed: { [string]: boolean }, perfect: boolean, milestones: { [string]: boolean } } },
	-- Premium fighter trials: [powerId] = os.time() the trial ends (PowerService)
	trials: { [string]: number },
	-- The Lounge wheel (WheelService): UTC day of the last free spin, paid spin credits held, total
	-- spins, and the ids of the last few prizes (newest first)
	wheel: { freeDay: number, credits: number, spins: number, last: { string } },
	-- The Lounge (LoungeService, RefreshmentService): the UTC day and Money earned that day from the
	-- games table, and how many refreshments were bought
	lounge: { gameDay: number, gameEarned: number, refreshments: number },
	-- Hosting and the game room (BaseService, GameRoom; Config/Homes): who may visit, the jukebox
	-- style, the cosmetic effects switched on, saved Fireworks Show charges, hearts received, the
	-- last visitors (Roblox names), the UTC day of the daily counters, and activity bests
	hosting: {
		access: string,
		jukebox: string,
		effects: { [string]: boolean },
		fireworks: number,
		hearts: number,
		visitors: { { id: number, name: string } },
		day: number,
		heartedToday: { [string]: boolean },
		bonusDay: number,
		bests: { [string]: number },
		playedDay: { [string]: number },
	},
	-- Last known game pass ownership by pass key (Roblox is asked again on join)
	passes: { [string]: boolean },
	-- Recent Robux PurchaseIds already granted, oldest first
	receipts: { string },
	-- os.time() of recent rewarded matches, oldest first (anti-farming)
	rewardLog: { number },
	meta: { created: number, lastSaved: number, sessions: number },
	[string]: any,
}

-- Helpers --------------------------------------------------------------------------------

local function isFinite(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- A whole number in [min, max], or `fallback` when the value isn't a usable number
local function integer(value: any, min: number, max: number, fallback: number): number
	if not isFinite(value) then
		return fallback
	end
	return math.clamp(math.floor(value), min, max)
end

local function text(value: any, fallback: string): string
	if typeof(value) == "string" and value ~= "" and #value <= Schema.Config.MaxTextLength then
		return value
	end
	return fallback
end

local function deepCopy<T>(value: T): T
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value :: any do
		copy[key] = deepCopy(item)
	end
	return copy :: any
end

-- Whether a value can be stored in a DataStore as it is (JSON: string keys or
-- a proper array, finite numbers, no functions or Instances, not too deep)
local function storable(value: any, depth: number): boolean
	local kind = typeof(value)
	if kind == "string" or kind == "boolean" then
		return true
	elseif kind == "number" then
		return isFinite(value)
	elseif kind ~= "table" or depth > 12 then
		return false
	end
	local count, stringKeys = 0, 0
	for key, item in value do
		count += 1
		if typeof(key) == "string" then
			stringKeys += 1
		elseif typeof(key) ~= "number" then
			return false
		end
		if not storable(item, depth + 1) then
			return false
		end
	end
	if stringKeys == count then
		return true
	end
	-- Otherwise it must be an array: keys 1..count with nothing else
	if stringKeys > 0 then
		return false
	end
	for index = 1, count do
		if value[index] == nil then
			return false
		end
	end
	return true
end

-- A new record holding the keys of `source` that `known` doesn't have, if they
-- can be saved. Newer versions (and fields added later) aren't thrown away.
local function extras(source: any, known: { [string]: any }): { [string]: any }
	local result = {}
	if typeof(source) == "table" then
		for key, value in source do
			if typeof(key) == "string" and known[key] == nil and storable(value, 1) then
				result[key] = deepCopy(value)
			end
		end
	end
	return result
end

local function asTable(value: any): { [any]: any }
	return if typeof(value) == "table" then value else {}
end

-- { [string]: true } keeping only string keys whose value is true
local function stringSet(value: any): { [string]: boolean }
	local result = {}
	for key, flag in asTable(value) do
		if typeof(key) == "string" and flag == true then
			result[key] = true
		end
	end
	return result
end

-- stringSet keeping only the ids listed in `known`
local function knownSet(value: any, known: { [string]: boolean }): { [string]: boolean }
	local result = {}
	for key in stringSet(value) do
		if known[key] then
			result[key] = true
		end
	end
	return result
end

-- The strings of an array, at most `limit`. `keepLast` keeps the newest end.
local function stringList(value: any, limit: number, keepLast: boolean?, unique: boolean?): { string }
	local result = {}
	local seen = {}
	for _, item in ipairs(asTable(value)) do
		if typeof(item) == "string" and item ~= "" and not (unique and seen[item]) then
			seen[item] = true
			table.insert(result, item)
		end
	end
	while #result > limit do
		table.remove(result, if keepLast then 1 else #result)
	end
	return result
end

-- The finite numbers of an array, keeping the newest `limit`
local function numberList(value: any, limit: number): { number }
	local result = {}
	for _, item in ipairs(asTable(value)) do
		if isFinite(item) then
			table.insert(result, item)
		end
	end
	while #result > limit do
		table.remove(result, 1)
	end
	return result
end

-- Defaults -------------------------------------------------------------------------------

local function defaultSettings(): Settings
	local settings = {}
	for key, rule in Schema.Settings do
		settings[key] = rule.default
	end
	return settings
end

local DEFAULT = {
	version = Schema.VERSION,
	currencies = { money = Schema.Config.StartingMoney, gems = Schema.Config.StartingGems },
	stats = {
		matches = 0,
		wins = 0,
		losses = 0,
		draws = 0,
		knockouts = 0,
		deaths = 0,
		playSeconds = 0,
		streak = 0,
		bestStreak = 0,
		-- Spectator predictions (informational only, nothing is ever paid for them)
		predictions = 0,
		predictionsCorrect = 0,
	},
	powers = {},
	loadouts = {},
	selected = { power = "StrongDude", degree = 1 },
	cosmetics = { owned = {}, equipped = {} },
	furniture = { owned = {} },
	base = { floor = "Oak", wall = "Plaster", lighting = "Warm", access = "Everyone", capacity = 1, items = {}, theme = Homes.DefaultTheme, show = {} },
	daily = { day = 0, progress = {}, claimed = {}, loginStreak = 0 },
	tutorial = { done = {}, welcomed = false },
	-- Achievements: done ids and counters toward the next ones (AchievementService)
	achievements = { done = {}, progress = {} },
	-- Community: who invited this player (Roblox's ReferredByPlayerId, once), whether the referral
	-- and group rewards were given, and how many recruits this player brought in (CommunityService)
	community = { referredBy = 0, referralDone = false, groupRewarded = false, recruits = 0, firstJoin = 0, goals = {}, likeNote = false },
	-- The cosmetic season pass: which season, points earned, premium track, claimed tiers (SeasonPassService)
	pass = { season = "", points = 0, premium = false, claimed = {} },
	lore = { found = {}, read = {}, last = "", page = 0 },
	calendars = {},
	trials = {},
	wheel = { freeDay = 0, credits = 0, spins = 0, last = {} },
	lounge = { gameDay = 0, gameEarned = 0, refreshments = 0 },
	hosting = {
		access = "Friends",
		jukebox = Homes.DefaultMusic,
		effects = {},
		fireworks = 0,
		hearts = 0,
		visitors = {},
		day = 0,
		heartedToday = {},
		bonusDay = 0,
		bests = {},
		playedDay = {},
	},
	settings = defaultSettings(),
	passes = {},
	receipts = {},
	rewardLog = {},
	meta = { created = 0, lastSaved = 0, sessions = 0 },
}

local POWER_DEFAULT = { xp = 0, degrees = {}, abilities = {}, owned = false }

-- MIGRATIONS[n] turns a version n profile into version n + 1. It gets a
-- shallow copy: replace nested tables rather than editing them in place.
-- Anything it doesn't handle is repaired from the defaults afterwards.
local MIGRATIONS: { [number]: (data: { [string]: any }) -> () } = {}

function Schema.default(): Profile
	return deepCopy(DEFAULT) :: any
end

-- Settings ---------------------------------------------------------------------------------

local function settingValue(rule, value: any): any
	if typeof(rule.default) == "boolean" then
		return if typeof(value) == "boolean" then value else nil
	end
	if rule.options then
		return if typeof(value) == "string" and table.find(rule.options, value) then value else nil
	end
	if not isFinite(value) then
		return nil
	end
	return math.clamp(value, rule.min, rule.max)
end

-- Settings built from `input` (anything a client sent), falling back to
-- `current` and then the defaults. Only known keys with the right type
-- survive, and numbers are clamped to their range.
function Schema.sanitizeSettings(input: any, current: any): Settings
	local result = {}
	for key, rule in Schema.Settings do
		local value = if typeof(input) == "table" then settingValue(rule, rawget(input, key)) else nil
		if value == nil and typeof(current) == "table" then
			value = settingValue(rule, rawget(current, key))
		end
		if value == nil then
			value = rule.default
		end
		result[key] = value
	end
	return result
end

-- Repair ------------------------------------------------------------------------------------

-- How many degrees a power has, as far as saved data is concerned
function Schema.degreesOf(powerId: string): number
	return Schema.Config.PowerDegrees[powerId] or Schema.Config.DefaultDegrees
end

-- Is `key` ("1", "2"...) one of this power's degrees?
local function isDegreeKey(powerId: string, key: string): boolean
	local degree = tonumber(key)
	return degree ~= nil and degree % 1 == 0 and degree >= 1 and degree <= Schema.degreesOf(powerId) and tostring(degree) == key
end

local function repairPowers(value: any): { [string]: PowerData }
	local result = {}
	for powerId, entry in asTable(value) do
		if typeof(powerId) == "string" and typeof(entry) == "table" then
			local power = extras(entry, POWER_DEFAULT)
			power.xp = integer(entry.xp, 0, Schema.Config.MaxXp, 0)
			power.degrees = stringSet(entry.degrees)
			-- Only degrees this power actually has
			for key in power.degrees do
				if not isDegreeKey(powerId, key) then
					power.degrees[key] = nil
				end
			end
			power.abilities = stringSet(entry.abilities)
			power.owned = entry.owned == true
			result[powerId] = power :: any
		end
	end
	return result
end

local function repairLoadouts(value: any): { [string]: { [string]: { string } } }
	local result = {}
	for powerId, byDegree in asTable(value) do
		if typeof(powerId) == "string" and typeof(byDegree) == "table" then
			local clean = {}
			for degree, list in byDegree do
				if typeof(degree) == "string" and typeof(list) == "table" and isDegreeKey(powerId, degree) then
					clean[degree] = stringList(list, Schema.Config.MaxLoadoutSize, false, true)
				end
			end
			result[powerId] = clean
		end
	end
	return result
end

local function repairBaseItems(value: any): { BaseItem }
	local result = {}
	for _, item in ipairs(asTable(value)) do
		if #result >= Schema.Config.MaxBaseItems then
			break
		end
		if typeof(item) == "table" and typeof(item.i) == "string" and isFinite(item.x) and isFinite(item.z) then
			table.insert(result, {
				i = item.i,
				x = item.x,
				z = item.z,
				r = integer(item.r, 0, 3, 0),
				c = integer(item.c, 0, 255, 1),
				m = integer(item.m, 0, 255, 1),
			})
		end
	end
	return result
end

-- A complete current-shape profile from `source`: known keys are checked and
-- replaced by their default when missing or wrongly typed; unknown keys that
-- can be saved are kept.
local function repair(source: { [any]: any }): Profile
	local config = Schema.Config
	local profile = extras(source, DEFAULT)
	profile.version = Schema.VERSION

	local currencies = asTable(source.currencies)
	profile.currencies = extras(currencies, DEFAULT.currencies)
	profile.currencies.money = integer(currencies.money, 0, config.MaxCurrency, config.StartingMoney)
	profile.currencies.gems = integer(currencies.gems, 0, config.MaxCurrency, config.StartingGems)

	local stats = asTable(source.stats)
	profile.stats = extras(stats, DEFAULT.stats)
	for key in DEFAULT.stats do
		profile.stats[key] = integer(stats[key], 0, math.huge, 0)
	end

	profile.powers = repairPowers(source.powers)
	profile.loadouts = repairLoadouts(source.loadouts)

	local selected = asTable(source.selected)
	profile.selected = extras(selected, DEFAULT.selected)
	profile.selected.power = text(selected.power, DEFAULT.selected.power)
	profile.selected.degree = integer(selected.degree, 1, config.MaxDegree, 1)

	local cosmetics = asTable(source.cosmetics)
	profile.cosmetics = extras(cosmetics, DEFAULT.cosmetics)
	profile.cosmetics.owned = stringSet(cosmetics.owned)
	local equipped = {}
	for slot, itemId in asTable(cosmetics.equipped) do
		if typeof(slot) == "string" and typeof(itemId) == "string" and itemId ~= "" then
			equipped[slot] = itemId
		end
	end
	profile.cosmetics.equipped = equipped

	local furniture = asTable(source.furniture)
	profile.furniture = extras(furniture, DEFAULT.furniture)
	local owned = {}
	for itemId, count in asTable(furniture.owned) do
		local amount = integer(count, 0, config.MaxFurnitureCount, 0)
		if typeof(itemId) == "string" and amount > 0 then
			owned[itemId] = amount
		end
	end
	profile.furniture.owned = owned

	local base = asTable(source.base)
	local defaultBase = DEFAULT.base
	profile.base = extras(base, defaultBase)
	profile.base.floor = text(base.floor, defaultBase.floor)
	profile.base.wall = text(base.wall, defaultBase.wall)
	profile.base.lighting = text(base.lighting, defaultBase.lighting)
	profile.base.access = if typeof(base.access) == "string" and table.find(Schema.BaseAccess, base.access)
		then base.access
		else defaultBase.access
	profile.base.capacity = integer(base.capacity, 1, 10000, defaultBase.capacity)
	profile.base.items = repairBaseItems(base.items)
	profile.base.theme = if typeof(base.theme) == "string" and Homes.Themes[base.theme] then base.theme else Homes.DefaultTheme
	local show = {}
	local savedShow = asTable(base.show)
	for key, rule in Homes.Toggles do
		show[key] = if typeof(savedShow[key]) == "boolean" then savedShow[key] else rule.default
	end
	profile.base.show = show

	local daily = asTable(source.daily)
	profile.daily = extras(daily, DEFAULT.daily)
	profile.daily.day = integer(daily.day, 0, math.huge, 0)
	local progress = {}
	for challengeId, amount in asTable(daily.progress) do
		if typeof(challengeId) == "string" and isFinite(amount) then
			progress[challengeId] = math.max(0, amount)
		end
	end
	profile.daily.progress = progress
	profile.daily.claimed = stringSet(daily.claimed)
	profile.daily.loginStreak = integer(daily.loginStreak, 0, math.huge, 0)

	local tutorial = asTable(source.tutorial)
	profile.tutorial = extras(tutorial, DEFAULT.tutorial)
	profile.tutorial.done = stringSet(tutorial.done)
	profile.tutorial.welcomed = tutorial.welcomed == true

	local achievements = asTable(source.achievements)
	profile.achievements = { done = stringSet(achievements.done), progress = {} }
	for key, value in asTable(achievements.progress) do
		if typeof(key) == "string" and #key <= 64 and isFinite(value) then
			profile.achievements.progress[key] = integer(value, 0, 1e9, 0)
		end
	end

	local community = asTable(source.community)
	profile.community = {
		referredBy = integer(community.referredBy, 0, 1e15, 0),
		referralDone = community.referralDone == true,
		groupRewarded = community.groupRewarded == true,
		recruits = integer(community.recruits, 0, 1e6, 0),
		firstJoin = integer(community.firstJoin, 0, 1e11, 0),
		goals = stringSet(community.goals), -- community like goals this player already received
		likeNote = community.likeNote == true, -- Jeffery's one-time like reminder was said
	}

	local pass = asTable(source.pass)
	profile.pass = {
		season = if typeof(pass.season) == "string" and #pass.season <= 40 then pass.season else "",
		points = integer(pass.points, 0, 1e9, 0),
		premium = pass.premium == true,
		claimed = stringSet(pass.claimed),
	}

	-- Calendars: known calendar ids, known day and milestone keys only
	profile.calendars = {}
	for id, entry in asTable(source.calendars) do
		local calendar = Calendars.get(id)
		if calendar then
			local saved = asTable(entry)
			local claimed, milestones = {}, {}
			for key in stringSet(saved.claimed) do
				if Calendars.validDayKey(calendar, key) then
					claimed[key] = true
				end
			end
			for key in stringSet(saved.milestones) do
				if Calendars.validMilestoneKey(calendar, key) then
					milestones[key] = true
				end
			end
			profile.calendars[id] = { claimed = claimed, perfect = saved.perfect == true, milestones = milestones }
		end
	end
	-- Fighter trials: premium fighters a calendar can hand out, end times as whole seconds
	profile.trials = {}
	for powerId, endsAt in asTable(source.trials) do
		if typeof(powerId) == "string" and Calendars.TrialPowers[powerId] and isFinite(endsAt) and endsAt > 0 then
			profile.trials[powerId] = integer(endsAt, 1, 4102444800, 1)
		end
	end

	-- The Lounge wheel: counters bounded, prize ids kept only if the wheel still has them
	local wheel = asTable(source.wheel)
	local lastPrizes = {}
	for _, id in stringList(wheel.last, Wheel.HistoryKept, false) do
		if Wheel.byId(id) then
			table.insert(lastPrizes, id)
		end
	end
	profile.wheel = {
		freeDay = integer(wheel.freeDay, 0, 1e6, 0),
		credits = integer(wheel.credits, 0, Wheel.MaxCredits, 0),
		spins = integer(wheel.spins, 0, 1e9, 0),
		last = lastPrizes,
	}
	local lounge = asTable(source.lounge)
	profile.lounge = {
		gameDay = integer(lounge.gameDay, 0, 1e6, 0),
		gameEarned = integer(lounge.gameEarned, 0, 1e6, 0),
		refreshments = integer(lounge.refreshments, 0, 1e9, 0),
	}

	-- Hosting: access reads "Friends" unless a valid mode was saved here (the old base.access
	-- field was never used and held "Everyone" in old profiles, so it is ignored)
	local hosting = asTable(source.hosting)
	local effects = {}
	for _, key in Homes.EffectOrder do
		if hosting.effects ~= nil and asTable(hosting.effects)[key] == true then
			effects[key] = true
		end
	end
	local visitors = {}
	for _, entry in ipairs(asTable(hosting.visitors)) do
		if typeof(entry) == "table" and isFinite(entry.id) and typeof(entry.name) == "string" and entry.name ~= "" and #entry.name <= 40 then
			table.insert(visitors, { id = integer(entry.id, 1, 1e15, 1), name = entry.name })
		end
	end
	while #visitors > Homes.VisitorsKept do
		table.remove(visitors, 1)
	end
	local hearted = {}
	local heartedCount = 0
	for key, flag in asTable(hosting.heartedToday) do
		if typeof(key) == "string" and #key <= 20 and flag == true and heartedCount < 200 then
			hearted[key] = true
			heartedCount += 1
		end
	end
	local bests, playedDay = {}, {}
	for _, id in Homes.ActivityOrder do
		bests[id] = integer(asTable(hosting.bests)[id], 0, 100000, 0)
		playedDay[id] = integer(asTable(hosting.playedDay)[id], 0, 1e6, 0)
	end
	profile.hosting = {
		access = if typeof(hosting.access) == "string" and Homes.AccessModes[hosting.access] then hosting.access else "Friends",
		jukebox = if typeof(hosting.jukebox) == "string" and table.find(Homes.MusicStyles, hosting.jukebox) then hosting.jukebox else Homes.DefaultMusic,
		effects = effects,
		fireworks = integer(hosting.fireworks, 0, Homes.FireworksMaxCharges, 0),
		hearts = integer(hosting.hearts, 0, 1e9, 0),
		visitors = visitors,
		day = integer(hosting.day, 0, 1e6, 0),
		heartedToday = hearted,
		bonusDay = integer(hosting.bonusDay, 0, 1e6, 0),
		bests = bests,
		playedDay = playedDay,
	}

	-- Lore: only ids the Archive has (a file must be found before it can be read)
	local lore = asTable(source.lore)
	local found = knownSet(lore.found, LORE_FILES)
	local read = {}
	for id in knownSet(lore.read, LORE_DOCUMENTS) do
		if not LORE_FILES[id] or found[id] then
			read[id] = true
		end
	end
	local last = if typeof(lore.last) == "string" and read[lore.last] then lore.last else ""
	profile.lore = {
		found = found,
		read = read,
		last = last,
		page = if last ~= "" then integer(lore.page, 0, config.MaxLorePage, 0) else 0,
	}

	profile.settings =Schema.sanitizeSettings(source.settings, nil)
	profile.passes = stringSet(source.passes)
	profile.receipts = stringList(source.receipts, config.MaxReceipts, true)
	profile.rewardLog = numberList(source.rewardLog, config.MaxRewardLog)

	local meta = asTable(source.meta)
	profile.meta = extras(meta, DEFAULT.meta)
	profile.meta.created = integer(meta.created, 0, math.huge, 0)
	profile.meta.lastSaved = integer(meta.lastSaved, 0, math.huge, 0)
	profile.meta.sessions = integer(meta.sessions, 0, math.huge, 0)

	return profile :: any
end

-- Turns whatever came out of the DataStore (nil, an older version, missing
-- keys, wrong types) into a valid current profile. The second result is true
-- when the data was saved by a newer version of the game: the profile is
-- usable for play but must never be saved, or newer progress would be lost.
function Schema.migrate(data: any): (Profile, boolean)
	local source = if typeof(data) == "table" then data else {}
	local version = if isFinite(source.version) then math.floor(source.version) else 0
	if version > Schema.VERSION then
		local profile = repair(source)
		profile.version = version
		return profile, true
	end
	local upgraded = table.clone(source)
	for step = math.max(version, 1), Schema.VERSION - 1 do
		local migrateStep = MIGRATIONS[step]
		if migrateStep then
			migrateStep(upgraded)
		end
	end
	return repair(upgraded), false
end

-- The copy sent to the client: everything except purchase receipts, the
-- reward log and bookkeeping
function Schema.view(profile: Profile): { [string]: any }
	local view = {}
	for key, value in profile do
		if not PRIVATE[key] then
			view[key] = deepCopy(value)
		end
	end
	return view
end

-- Deep copy of a profile or any part of one
Schema.copy = deepCopy

-- Whether a value can be written to a DataStore exactly as it is
function Schema.storable(value: any): boolean
	return storable(value, 1)
end

return Schema
