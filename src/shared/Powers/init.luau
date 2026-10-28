-- The eight powers: where their definitions live and the rules every screen
-- and service shares about them (degree unlocks, loadouts, ability stats per
-- degree, combat stats). Each power's own numbers are in the file named after
-- it next to this one.
--
-- Definitions are data. How an ability behaves on the server is in
-- ServerScriptService.Server.Powers.<PowerId>; how it looks on screens is in
-- StarterPlayerScripts.Client.Powers.<PowerId>.

local Combat = require(script.Parent.Config.Combat)

local Powers = {}

-- Selection screen order. Exactly eight powers; combined abilities (the Ghost's
-- katana, Machine Master's soul fire) belong to their power, never their own fighter.
Powers.Order = {
	"StrongDude",
	"Ghost",
	"Shapeshifter",
	"MachineMaster",
	"Corruption",
	"Syntax",
	"Admin",
	"Grandmaster",
}

Powers.Default = "StrongDude"
-- Degrees a power has unless its definition says otherwise (`degreeCount`)
Powers.Degrees = 3
-- The most any power has (The Grandmaster's four)
Powers.MaxDegrees = 4

-- Mastery: experience earned by fighting with a power. Level n needs Thresholds[n] XP in total.
Powers.Mastery = {
	Thresholds = { 0, 150, 400, 750, 1200, 1800, 2600, 3600, 4800, 6200, 7800, 9600, 11600, 13800, 16200, 18800, 21600, 24600, 27800, 31200 },
}

local defs: { [string]: any } = {}
for _, id in Powers.Order do
	local module = script:FindFirstChild(id)
	if module then
		defs[id] = require(module) :: any
	end
end
Powers.Defs = defs

function Powers.get(powerId: string): any?
	return defs[powerId]
end

-- How many degrees this power has (0 for an unknown power)
function Powers.degreeCount(powerId: string?): number
	local def = powerId and defs[powerId]
	if not def then
		return 0
	end
	return def.degreeCount or Powers.Degrees
end

-- Is `degree` one of this power's degrees (a whole number from 1 to its count)?
function Powers.validDegree(powerId: string?, degree: any): boolean
	return typeof(degree) == "number" and degree % 1 == 0 and degree >= 1 and degree <= Powers.degreeCount(powerId)
end

function Powers.isPremium(powerId: string): boolean
	local def = defs[powerId]
	return def ~= nil and def.premium ~= nil
end

function Powers.masteryLevel(xp: number): number
	local level = 1
	for index, needed in Powers.Mastery.Thresholds do
		if xp >= needed then
			level = index
		end
	end
	return level
end

-- XP still needed for the next level (nil at the top level)
function Powers.nextLevelXp(xp: number): number?
	local level = Powers.masteryLevel(xp)
	return Powers.Mastery.Thresholds[level + 1]
end

-- Deep copy, then deep-merge `overrides` into it (arrays are replaced, not merged)
local function isArray(value: any): boolean
	return typeof(value) == "table" and #value > 0
end

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end
	return copy
end
Powers.deepCopy = deepCopy

local function merge(target: { [any]: any }, overrides: { [any]: any }?)
	if not overrides then
		return target
	end
	for key, value in overrides do
		if typeof(value) == "table" and not isArray(value) and typeof(target[key]) == "table" and not isArray(target[key]) then
			merge(target[key], value)
		else
			target[key] = deepCopy(value)
		end
	end
	return target
end
Powers.merge = merge

-- Abilities -----------------------------------------------------------------------

local abilityCache: { [string]: any } = {}

-- An ability's stats at a degree: its base numbers with that degree's changes applied
function Powers.abilityFor(powerId: string, abilityId: string, degree: number): any?
	local key = `{powerId}/{abilityId}/{degree}`
	local cached = abilityCache[key]
	if cached then
		return cached
	end
	local def = defs[powerId]
	local base = def and def.abilities[abilityId]
	if not base or not Powers.validDegree(powerId, degree) then
		return nil
	end
	local result = deepCopy(base)
	result.id = abilityId
	result.power = powerId
	result.degreeScaling = nil
	local scaling = base.degreeScaling
	if scaling then
		for step = 2, degree do
			merge(result, scaling[step])
		end
	end
	result.degree = degree
	abilityCache[key] = result
	return result
end

-- Everything this degree can equip (abilities whose minDegree it meets), in definition order
function Powers.available(powerId: string, degree: number): { string }
	local def = defs[powerId]
	if not def then
		return {}
	end
	local list = {}
	for _, abilityId in def.abilityOrder do
		local ability = def.abilities[abilityId]
		if ability and ability.kind ~= "Ultimate" and not ability.basicOnly and (ability.minDegree or 1) <= degree then
			table.insert(list, abilityId)
		end
	end
	return list
end

function Powers.degree(powerId: string, degree: number): any?
	local def = defs[powerId]
	if not def or not Powers.validDegree(powerId, degree) then
		return nil
	end
	return def.degrees[degree]
end

-- Some powers replace the basic Light/Heavy attacks with their own (Machine
-- Master's blasters, an animal form's bite). Checked form first, then degree,
-- then the power. Returns the ability id, or nil for the normal melee chain.
function Powers.basicFor(powerId: string?, degree: number?, formId: string?, kind: string): string?
	local def = powerId and defs[powerId]
	if not def then
		return nil
	end
	if formId and formId ~= "" then
		-- The form at this degree (Shapeshifter forms evolve through degreeScaling)
		local form = (if degree and Powers.validDegree(powerId :: string, degree) then Powers.abilityFor(powerId :: string, formId, degree) else nil)
			or def.abilities[formId]
		local formBasic = form and form.form and form.form.basic
		if formBasic and formBasic[kind] then
			return formBasic[kind]
		end
	end
	local degreeDef = def.degrees[degree or 1]
	if degreeDef and degreeDef.basic and degreeDef.basic[kind] then
		return degreeDef.basic[kind]
	end
	return def.basic and def.basic[kind] or nil
end

function Powers.ultimateOf(powerId: string, degree: number): string?
	local degreeDef = Powers.degree(powerId, degree)
	return degreeDef and degreeDef.ultimate
end

-- Is this ability free (at this degree), or has the player bought it? An
-- ability with `freeFrom = n` costs its price below degree n and is included from n on.
function Powers.abilityOwned(powerId: string, abilityId: string, powerData: { [string]: any }?, degree: number?): boolean
	local def = defs[powerId]
	local ability = def and def.abilities[abilityId]
	if not ability then
		return false
	end
	if ability.price == nil then
		return true
	end
	if ability.freeFrom and degree and degree >= ability.freeFrom then
		return true
	end
	local bought = powerData and powerData.abilities
	return typeof(bought) == "table" and bought[abilityId] == true
end

function Powers.defaultLoadout(powerId: string, degree: number): { string }
	local degreeDef = Powers.degree(powerId, degree)
	return if degreeDef then table.clone(degreeDef.default) else {}
end

-- Checks a loadout someone wants to equip. Returns (ok, reason, cleaned list).
-- Every degree's default loadout must pass with nothing bought.
function Powers.validateLoadout(powerId: string, degree: number, list: any, powerData: { [string]: any }?): (boolean, string?, { string }?)
	local degreeDef = Powers.degree(powerId, degree)
	if not degreeDef then
		return false, "Unknown power or degree.", nil
	end
	if typeof(list) ~= "table" then
		return false, "That loadout isn't valid.", nil
	end
	local available = {}
	for _, abilityId in Powers.available(powerId, degree) do
		available[abilityId] = true
	end
	local cleaned = {}
	local seen = {}
	for index, abilityId in list do
		if typeof(index) ~= "number" or typeof(abilityId) ~= "string" then
			return false, "That loadout isn't valid.", nil
		end
		if seen[abilityId] then
			return false, "Each ability can only be equipped once.", nil
		end
		seen[abilityId] = true
		if not available[abilityId] then
			return false, "That ability isn't part of this degree.", nil
		end
		if not Powers.abilityOwned(powerId, abilityId, powerData, degree) then
			return false, "Unlock that ability first.", nil
		end
		table.insert(cleaned, abilityId)
	end
	if #cleaned == 0 then
		return false, "Equip at least one ability.", nil
	end
	if #cleaned > degreeDef.slots then
		return false, `This degree has {degreeDef.slots} ability slots.`, nil
	end
	return true, nil, cleaned
end

-- Degree unlocks: Degree 1 is always open; higher degrees open at a mastery level
-- or by paying Money, and only in order
function Powers.degreeUnlocked(powerId: string, degree: number, powerData: { [string]: any }?): boolean
	if degree <= 1 then
		return true
	end
	if not Powers.validDegree(powerId, degree) then
		return false
	end
	local degrees = powerData and powerData.degrees
	if typeof(degrees) == "table" and degrees[tostring(degree)] == true then
		return true
	end
	local degreeDef = Powers.degree(powerId, degree)
	local xp = powerData and powerData.xp
	local level = Powers.masteryLevel(if typeof(xp) == "number" then xp else 0)
	return degreeDef ~= nil
		and degreeDef.unlock ~= nil
		and degreeDef.unlock.mastery ~= nil
		and level >= degreeDef.unlock.mastery
		and Powers.degreeUnlocked(powerId, degree - 1, powerData)
end

-- Combat stats -----------------------------------------------------------------------

local profileCache: { [string]: any } = {}

-- The combat numbers a fighter uses (Config/Combat with the power's, the degree's and
-- the current form's changes). Cached; treat the result as read-only.
function Powers.combatProfile(powerId: string?, degree: number?, formId: string?): any
	if not powerId or not defs[powerId] then
		return Combat
	end
	local level = degree or 1
	local key = `{powerId}/{level}/{formId or ""}`
	local cached = profileCache[key]
	if cached then
		return cached
	end
	local def = defs[powerId]
	local profile = deepCopy(Combat)
	merge(profile, def.stats)
	local degreeDef = if Powers.validDegree(powerId, level) then def.degrees[level] else nil
	if degreeDef then
		merge(profile, degreeDef.stats)
	end
	if formId and formId ~= "" then
		-- The form at this degree (Shapeshifter forms evolve through degreeScaling)
		local form = (if degreeDef then Powers.abilityFor(powerId, formId, level) else nil) or def.abilities[formId]
		if form and form.form then
			merge(profile, form.form.stats)
		end
	end
	profile.PowerId = powerId
	profile.Degree = level
	profile.Form = formId or ""
	profileCache[key] = profile
	return profile
end

return Powers
