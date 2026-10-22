-- The shape of a player's saved profile: its defaults, upgrades from older
-- versions, repairs of missing or wrongly typed values, the safe copy the
-- client is allowed to see, and the settings sanitizer. Pure logic with no
-- services, so it's unit tested in Lune (tests/Data.spec.luau).
--
-- Everything in a profile must survive the DataStore's JSON: dictionary keys
-- are strings, arrays are proper sequences, numbers are finite.

local Schema = {}

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
Schema.CosmeticSlots = { "aura", "victory", "knockout", "title", "trail" }

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
}

-- Saved data the client never sees
local PRIVATE = { receipts = true, rewardLog = true, meta = true }

export type Settings = { [string]: boolean | number }
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
	base: { floor: string, wall: string, lighting: string, access: string, capacity: number, items: { BaseItem } },
	daily: { day: number, progress: { [string]: number }, claimed: { [string]: boolean }, loginStreak: number },
	tutorial: { done: { [string]: boolean }, welcomed: boolean },
	settings: Settings,
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
	},
	powers = {},
	loadouts = {},
	selected = { power = "StrongDude", degree = 1 },
	cosmetics = { owned = {}, equipped = {} },
	furniture = { owned = {} },
	base = { floor = "Oak", wall = "Plaster", lighting = "Warm", access = "Everyone", capacity = 1, items = {} },
	daily = { day = 0, progress = {}, claimed = {}, loginStreak = 0 },
	tutorial = { done = {}, welcomed = false },
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

	profile.settings = Schema.sanitizeSettings(source.settings, nil)
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
