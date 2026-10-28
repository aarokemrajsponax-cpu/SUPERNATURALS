-- Gives every fighter its power: which of the eight, which degree, which
-- abilities are equipped, plus the power's resource (grit, fuel, corruption...),
-- ultimate charge, cooldowns and look. Players choose in the Powers screen;
-- the choice is checked here (premium ownership, degree unlocks, loadout rules),
-- saved to their profile, and LOCKED for the whole of a match: no changes of
-- power, degree or loadout mid-fight, paid or otherwise.
--
-- Power-specific behaviour lives in Server/Powers/<PowerId>.luau; this service
-- calls its hooks (init, onEquip, tick, onHit, onHurt, modifyIncoming, onDodge,
-- appearance) and the ability handlers through AbilityService.
--
-- Degrees: most powers have three, a power can declare its own count
-- (`degreeCount`, The Grandmaster has four); every check here uses Powers.validDegree.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local AbilityKit = require(script.Parent.Parent.Combat.AbilityKit)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PowerRequest = Remotes:WaitForChild("PowerRequest") :: RemoteEvent
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local Attribute = Protocol.Attribute
local Action = Protocol.PowerAction
local ULTIMATE = Combat.Ultimate

local PowerService = {}

-- After escaping a grab the grabber staggers this long
PowerService.EscapeStun = Combat.Defense.EscapeStun

local TICK = 0.1
-- Modes where premium powers must be owned (trials are fine everywhere else)
local RANKED_MODES = { Duel = true, FreeForAll = true }

export type Runtime = {
	id: string,
	def: any,
	degree: number,
	loadout: { string },
	ultimate: string?,
	-- "Trial": a premium power being tried in training or CPU practice
	trial: boolean,
	cooldowns: { [string]: number },
	resource: number,
	resourceMax: number,
	ult: number,
	form: string,
	-- Free space for the power's own state (the Ghost's drawn katana, a held prop...)
	data: { [string]: any },
	-- Things to stop when the fighter is reset or knocked out
	handles: { () -> () },
	module: any,
	appearanceCleanup: (() -> ())?,
	published: { [string]: number },
}

local modules: { [string]: any } = {}
-- Players in a match: their power, degree and loadout as they were when it started
local locked: { [Player]: { power: string, degree: number, loadout: { string } } } = {}
local keyCounter = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function toast(player: Player?, text: string, kind: string?)
	if player and player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Toast, { text = text, kind = kind or "info" })
	end
end

function PowerService:Init(services)
	self.services = services
	self.characters = services.CharacterService
	self.antiExploit = services.AntiExploitService
	AbilityKit.init(services)
	local folder = script.Parent.Parent:FindFirstChild("Powers")
	for _, powerId in Powers.Order do
		local module = folder and folder:FindFirstChild(powerId)
		if module then
			modules[powerId] = require(module) :: any
			-- Optional: a power module that needs services of its own (defense results, purchases)
			local loaded = modules[powerId]
			if typeof(loaded) == "table" and typeof(loaded.init) == "function" then
				loaded.init(services)
			end
		end
	end
end

function PowerService:Start()
	PowerRequest.OnServerEvent:Connect(function(player, action, ...)
		if not self.antiExploit:allow(player, "Power") then
			return
		end
		if typeof(action) ~= "string" then
			return
		end
		local ok, err = pcall(self._onRequest, self, player, action, ...)
		if not ok then
			warn("[Powers] request failed: " .. tostring(err))
		end
	end)

	self.characters:onSpawned(function(fighter)
		if fighter.player then
			self:_equipForPlayer(fighter)
		end
	end)
	self.characters:onKnockout(function(fighter)
		self:_stopHandles(fighter)
		if fighter.power and fighter.power.form ~= "" then
			self:setForm(fighter, "")
		end
	end)
	self.characters:onRestored(function(fighter)
		self:resetFighter(fighter)
	end)
	self.characters:onUnregistered(function(fighter)
		self:_stopHandles(fighter)
		local runtime = fighter.power
		if runtime and runtime.appearanceCleanup then
			pcall(runtime.appearanceCleanup)
			runtime.appearanceCleanup = nil
		end
	end)

	local data = self.services.DataService
	if data then
		-- When a saved profile arrives after the character, use its choice
		data:onLoaded(function(player)
			local fighter = self.characters:getByPlayer(player)
			if fighter then
				self:_equipForPlayer(fighter)
			end
		end)
	end
	local purchases = self.services.PurchaseService
	if purchases then
		purchases:onPassGranted(function(player, passKey)
			-- A cosmetic pass: redraw the fighter in its style right away
			local current = self.characters:getByPlayer(player)
			local runtime = current and current.power
			local cosmetic = runtime and runtime.def.cosmetic
			if current and cosmetic and cosmetic.pass == passKey then
				current.model:SetAttribute(Attribute.Style, passKey)
				self:_applyAppearance(current)
			end
			for powerId, def in Powers.Defs do
				if def.premium and def.premium.pass == passKey then
					toast(player, `{def.name} unlocked! It's yours in every mode.`, "success")
					local fighter = self.characters:getByPlayer(player)
					if fighter and fighter.power and fighter.power.id == powerId then
						fighter.power.trial = false
					end
				end
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		locked[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(TICK)
			self:_tick(TICK)
		end
	end)
end

-- Ownership and unlocks ---------------------------------------------------------------

local function powerData(profile, powerId: string): { [string]: any }
	local powers = profile and profile.powers
	local entry = powers and powers[powerId]
	return if typeof(entry) == "table" then entry else {}
end

function PowerService:_profile(player: Player)
	local data = self.services.DataService
	return if data then data:get(player) else nil
end

-- Does this player own a premium power outright (pass, Gems unlock, or the game's owner)?
function PowerService:owns(player: Player, powerId: string): boolean
	local def = Powers.get(powerId)
	if not def then
		return false
	end
	if not def.premium then
		return true
	end
	local owner = self.services.OwnerService
	if owner and owner:isOwner(player) then
		return true
	end
	local purchases = self.services.PurchaseService
	if purchases and def.premium.pass and purchases:ownsPass(player, def.premium.pass) then
		return true
	end
	return powerData(self:_profile(player), powerId).owned == true
end

-- Can this player use this power and degree at all? Premium powers they don't
-- own can still be tried (trial) outside ranked fights.
function PowerService:check(player: Player, powerId: string, degree: number): (boolean, string?, boolean)
	local def = Powers.get(powerId)
	if not def or not Powers.validDegree(powerId, degree) then
		return false, "That power doesn't exist.", false
	end
	local profile = self:_profile(player)
	local owner = self.services.OwnerService
	local isOwner = owner and owner:isOwner(player)
	if not isOwner and not Powers.degreeUnlocked(powerId, degree, powerData(profile, powerId)) then
		return false, `{def.degrees[degree].name} is locked. Reach mastery level {def.degrees[degree].unlock.mastery} or unlock it.`, false
	end
	local trial = not self:owns(player, powerId)
	return true, nil, trial
end

-- MatchService asks before queueing: premium powers need to be owned in PvP
function PowerService:queueCheck(player: Player, modeName: string): (boolean, string?)
	local fighter = self.characters:getByPlayer(player)
	local runtime = fighter and fighter.power
	if runtime and runtime.trial and RANKED_MODES[modeName] then
		local premium = runtime.def.premium
		local price = if premium and premium.robux then `{premium.robux} Robux` else "Robux"
		local gems = if premium and premium.gems then ` or {premium.gems} Gems` else ""
		return false, `{runtime.def.name} is a premium power. Try it in Training or CPU Practice, or unlock it ({price}{gems}).`
	end
	return true, nil
end

-- Locks a player's power for the length of a match (MatchService calls these)
function PowerService:lock(player: Player)
	local fighter = self.characters:getByPlayer(player)
	local runtime = fighter and fighter.power
	if runtime then
		locked[player] = { power = runtime.id, degree = runtime.degree, loadout = table.clone(runtime.loadout) }
	end
end

function PowerService:unlock(player: Player)
	locked[player] = nil
end

function PowerService:isLocked(player: Player): boolean
	return locked[player] ~= nil
end

-- The power, degree and loadout a player is locked into for their current match
function PowerService:lockedSelection(player: Player): { power: string, degree: number, loadout: { string } }?
	return locked[player]
end

-- Requests -------------------------------------------------------------------------------

function PowerService:_onRequest(player: Player, action: string, first: any, second: any, third: any)
	local currency = self.services.CurrencyService
	local data = self.services.DataService
	local profile = self:_profile(player)
	if not profile or not data then
		toast(player, "Your data is still loading. Try again in a moment.", "error")
		return
	end
	if typeof(first) ~= "string" or not Powers.get(first) then
		return
	end
	local powerId: string = first
	local def = Powers.get(powerId)

	if action == Action.Select or action == Action.SetLoadout then
		if locked[player] then
			toast(player, "Your power and degree are locked until the fight ends.", "error")
			return
		end
	end

	if action == Action.Select then
		local degree = second
		local ok, reason, trial = self:check(player, powerId, degree)
		if not ok then
			toast(player, reason or "You can't use that right now.", "error")
			return
		end
		data:update(player, function(saved)
			saved.selected = { power = powerId, degree = degree }
		end)
		local fighter = self.characters:getByPlayer(player)
		if fighter and self.characters:isAlive(fighter) then
			self:equip(fighter, powerId, degree, self:_savedLoadout(player, powerId, degree), { trial = trial })
		end
		local note = if trial then " (trial: Training and CPU Practice only)" else ""
		toast(player, `Now using {def.name}, {def.degrees[degree].name}{note}.`, "success")
	elseif action == Action.SetLoadout then
		local degree = second
		if not Powers.validDegree(powerId, degree) then
			return
		end
		local ok, reason, cleaned = Powers.validateLoadout(powerId, degree, third, powerData(profile, powerId))
		if not ok or not cleaned then
			toast(player, reason or "That loadout isn't valid.", "error")
			return
		end
		data:update(player, function(saved)
			saved.loadouts[powerId] = saved.loadouts[powerId] or {}
			saved.loadouts[powerId][tostring(degree)] = cleaned
		end)
		local fighter = self.characters:getByPlayer(player)
		local runtime = fighter and fighter.power
		if fighter and runtime and runtime.id == powerId and runtime.degree == degree then
			self:equip(fighter, powerId, degree, cleaned, { trial = runtime.trial })
		end
		toast(player, "Loadout saved.", "success")
	elseif action == Action.UnlockAbility then
		local abilityId = second
		local ability = typeof(abilityId) == "string" and def.abilities[abilityId]
		if not ability or not ability.price then
			return
		end
		if Powers.abilityOwned(powerId, abilityId, powerData(profile, powerId)) then
			toast(player, "You already own that ability.")
			return
		end
		if def.premium and not self:owns(player, powerId) then
			toast(player, `Unlock {def.name} first.`, "error")
			return
		end
		if not currency or not currency:spend(player, ability.price, "ability:" .. powerId .. "/" .. abilityId) then
			toast(player, "Not enough to unlock that yet.", "error")
			return
		end
		data:update(player, function(saved)
			local entry = saved.powers[powerId] or {}
			entry.abilities = entry.abilities or {}
			entry.abilities[abilityId] = true
			saved.powers[powerId] = entry
		end)
		toast(player, `{ability.name} unlocked!`, "success")
	elseif action == Action.UnlockDegree then
		local degree = second
		local degreeDef = Powers.validDegree(powerId, degree) and def.degrees[degree]
		if not degreeDef or degree < 2 or not degreeDef.unlock or not degreeDef.unlock.money then
			return
		end
		local entry = powerData(profile, powerId)
		if Powers.degreeUnlocked(powerId, degree, entry) then
			toast(player, "That degree is already unlocked.")
			return
		end
		if not Powers.degreeUnlocked(powerId, degree - 1, entry) then
			toast(player, "Unlock the degree before it first.", "error")
			return
		end
		if not currency or not currency:spend(player, { money = degreeDef.unlock.money }, "degree:" .. powerId .. "/" .. degree) then
			toast(player, "Not enough Money to unlock that degree yet.", "error")
			return
		end
		data:update(player, function(saved)
			local saveEntry = saved.powers[powerId] or {}
			saveEntry.degrees = saveEntry.degrees or {}
			saveEntry.degrees[tostring(degree)] = true
			saved.powers[powerId] = saveEntry
		end)
		toast(player, `{degreeDef.name} unlocked!`, "success")
	elseif action == Action.UnlockPower then
		local premium = def.premium
		if not premium or not premium.gems then
			return
		end
		if self:owns(player, powerId) then
			toast(player, `You already own {def.name}.`)
			return
		end
		if not currency or not currency:spend(player, { gems = premium.gems }, "power:" .. powerId) then
			toast(player, `You need {premium.gems} Gems to unlock {def.name}.`, "error")
			return
		end
		data:update(player, function(saved)
			local entry = saved.powers[powerId] or {}
			entry.owned = true
			saved.powers[powerId] = entry
		end)
		local fighter = self.characters:getByPlayer(player)
		if fighter and fighter.power and fighter.power.id == powerId then
			fighter.power.trial = false
		end
		toast(player, `{def.name} unlocked! It's yours in every mode.`, "success")
	elseif action == Action.PromptPass then
		local premium = def.premium
		local purchases = self.services.PurchaseService
		-- (powerId, "Cosmetic") buys the power's cosmetic pass (The Grandmaster's Celestial Dragon Style)
		if second == "Cosmetic" then
			if def.cosmetic and def.cosmetic.pass and purchases then
				purchases:promptPass(player, def.cosmetic.pass)
			end
		elseif premium and premium.pass and purchases then
			purchases:promptPass(player, premium.pass)
		end
	end
end

-- The loadout a player saved for a power and degree (or that degree's default)
function PowerService:_savedLoadout(player: Player, powerId: string, degree: number): { string }
	local profile = self:_profile(player)
	local saved = profile and profile.loadouts and profile.loadouts[powerId]
	local list = saved and saved[tostring(degree)]
	if list then
		local ok, _, cleaned = Powers.validateLoadout(powerId, degree, list, powerData(profile, powerId))
		if ok and cleaned then
			return cleaned
		end
	end
	return Powers.defaultLoadout(powerId, degree)
end

function PowerService:_equipForPlayer(fighter)
	local player = fighter.player :: Player
	-- In a match: exactly what they had when it started
	local held = locked[player]
	if held then
		local trial = not self:owns(player, held.power)
		self:equip(fighter, held.power, held.degree, held.loadout, { trial = trial })
		return
	end
	local profile = self:_profile(player)
	local selected = profile and profile.selected
	local powerId = if selected and typeof(selected.power) == "string" then selected.power else Powers.Default
	local degree = if selected and typeof(selected.degree) == "number" then selected.degree else 1
	-- A saved degree above this power's count (data from a four-degree power) uses its top degree
	local count = Powers.degreeCount(powerId)
	if count > 0 and degree > count then
		degree = count
	end
	local ok, reason, trial = self:check(player, powerId, degree)
	if not ok then
		-- Never switch silently: say why
		if profile then
			toast(player, `{reason} Using {Powers.get(Powers.Default).name} for now.`, "error")
		end
		powerId, degree, trial = Powers.Default, 1, false
	end
	self:equip(fighter, powerId, degree, self:_savedLoadout(player, powerId, degree), { trial = trial })
end

-- Equipping ------------------------------------------------------------------------------

-- Gives a fighter a power, degree and loadout (players go through the checks
-- above first; CPU opponents are equipped directly)
function PowerService:equip(fighter, powerId: string, degree: number, loadout: { string }, opts: { trial: boolean? }?)
	local def = Powers.get(powerId)
	if not def then
		return
	end
	self:_stopHandles(fighter)
	local previous = fighter.power
	if previous and previous.appearanceCleanup then
		pcall(previous.appearanceCleanup)
	end
	local resourceDef = def.resource
	local runtime: Runtime = {
		id = powerId,
		def = def,
		degree = degree,
		loadout = table.clone(loadout),
		ultimate = Powers.ultimateOf(powerId, degree),
		trial = opts ~= nil and opts.trial == true,
		cooldowns = {},
		resource = if resourceDef then resourceDef.start else 0,
		resourceMax = if resourceDef then resourceDef.max else 0,
		ult = 0,
		form = "",
		data = {},
		handles = {},
		module = modules[powerId],
		appearanceCleanup = nil,
		published = {},
	}
	fighter.power = runtime

	-- Clear the previous power's cooldown attributes
	local model = fighter.model
	for name in model:GetAttributes() do
		if string.sub(name, 1, #Attribute.CooldownPrefix) == Attribute.CooldownPrefix then
			model:SetAttribute(name, nil)
		end
	end
	model:SetAttribute(Attribute.Power, powerId)
	model:SetAttribute(Attribute.Degree, degree)
	model:SetAttribute(Attribute.Form, "")
	model:SetAttribute(Attribute.Loadout, table.concat(runtime.loadout, ","))
	model:SetAttribute(Attribute.ResourceMax, runtime.resourceMax)
	model:SetAttribute(Attribute.Phase, 0)
	model:SetAttribute(Attribute.Style, if self:ownsCosmetic(fighter, def) then def.cosmetic.pass else nil)
	self.characters:setCombatProfile(fighter, Powers.combatProfile(powerId, degree))
	self:_publish(fighter, true)

	local module = runtime.module
	if module and module.onEquip then
		self:_safe(module.onEquip, fighter, runtime, AbilityKit.forFighter(fighter))
	end
	self:_applyAppearance(fighter)
end

-- Does this fighter's player own their power's cosmetic pass? Cosmetics change looks only.
function PowerService:ownsCosmetic(fighter, def): boolean
	local cosmetic = def and def.cosmetic
	local purchases = self.services.PurchaseService
	if not cosmetic or not cosmetic.pass or not fighter.player or not purchases then
		return false
	end
	local ok, owns = pcall(purchases.ownsPass, purchases, fighter.player, cosmetic.pass)
	return ok and owns == true
end

function PowerService:_applyAppearance(fighter)
	local runtime = fighter.power
	if not runtime then
		return
	end
	if runtime.appearanceCleanup then
		pcall(runtime.appearanceCleanup)
		runtime.appearanceCleanup = nil
	end
	local module = runtime.module
	if module and module.appearance then
		local ok, cleanup = pcall(module.appearance, fighter, runtime, AbilityKit.forFighter(fighter))
		if ok and typeof(cleanup) == "function" then
			runtime.appearanceCleanup = cleanup
		elseif not ok then
			warn(`[Powers] {runtime.id} appearance failed: {cleanup}`)
		end
	end
end

-- Shapeshifter forms (and any power that changes shape): new combat numbers and look
function PowerService:setForm(fighter, formId: string)
	local runtime = fighter.power
	if not runtime or runtime.form == formId then
		return
	end
	runtime.form = formId
	fighter.model:SetAttribute(Attribute.Form, formId)
	self.characters:setCombatProfile(fighter, Powers.combatProfile(runtime.id, runtime.degree, if formId ~= "" then formId else nil))
	self:_applyAppearance(fighter)
end

-- Back to a fresh start for a new life or a new match: resource, charge,
-- cooldowns, forms; everything the power left in the world is removed
function PowerService:resetFighter(fighter)
	local runtime = fighter.power
	self:_stopHandles(fighter)
	local services = self.services
	if services.ProjectileService then
		services.ProjectileService:clearOwner(fighter)
	end
	if services.ConstructService then
		services.ConstructService:clearOwner(fighter)
	end
	if not runtime then
		return
	end
	if runtime.form ~= "" then
		self:setForm(fighter, "")
	end
	runtime.cooldowns = {}
	local model = fighter.model
	for name in model:GetAttributes() do
		if string.sub(name, 1, #Attribute.CooldownPrefix) == Attribute.CooldownPrefix then
			model:SetAttribute(name, nil)
		end
	end
	local resourceDef = runtime.def.resource
	runtime.resource = if resourceDef then resourceDef.start else 0
	runtime.ult = 0
	runtime.data = {}
	model:SetAttribute(Attribute.Phase, 0)
	self:_publish(fighter, true)
	local module = runtime.module
	if module and module.onReset then
		self:_safe(module.onReset, fighter, runtime, AbilityKit.forFighter(fighter))
	end
end

function PowerService:_stopHandles(fighter)
	local runtime = fighter.power
	if not runtime then
		return
	end
	local handles = runtime.handles
	runtime.handles = {}
	for _, stop in handles do
		local ok, err = pcall(stop)
		if not ok then
			warn("[Powers] couldn't stop an effect: " .. tostring(err))
		end
	end
end

function PowerService:_safe(callback, ...)
	local ok, err = pcall(callback, ...)
	if not ok then
		warn("[Powers] hook failed: " .. tostring(err))
	end
end

-- Resources, charge and cooldowns ---------------------------------------------------------

function PowerService:resource(fighter): number
	return if fighter.power then fighter.power.resource else 0
end

function PowerService:spend(fighter, amount: number): boolean
	local runtime = fighter.power
	if not runtime or amount < 0 then
		return false
	end
	if runtime.resource + 1e-6 < amount then
		return false
	end
	runtime.resource -= amount
	self:_publish(fighter, false)
	return true
end

function PowerService:gain(fighter, amount: number)
	local runtime = fighter.power
	if runtime and amount > 0 then
		runtime.resource = math.min(runtime.resourceMax, runtime.resource + amount)
		self:_publish(fighter, false)
	end
end

function PowerService:addUltimate(fighter, amount: number)
	local runtime = fighter.power
	if runtime and amount > 0 and runtime.ultimate then
		runtime.ult = math.min(ULTIMATE.Max, runtime.ult + amount)
		self:_publish(fighter, false)
	end
end

function PowerService:setCooldown(fighter, abilityId: string, readyAt: number)
	local runtime = fighter.power
	if runtime then
		runtime.cooldowns[abilityId] = readyAt
		fighter.model:SetAttribute(Attribute.CooldownPrefix .. abilityId, readyAt)
	end
end

-- Cooldown length for this fighter right now (Distort makes abilities recharge slower)
function PowerService:cooldownFor(fighter, def): number
	local statuses = self.services.StatusService
	local length = def.cooldown or 0
	if statuses and statuses:has(fighter, "Distort") then
		length *= 1.3
	end
	return length
end

-- Gives back part of an ability's cost and cooldown (it couldn't happen)
function PowerService:refund(fighter, def, share: number)
	local runtime = fighter.power
	if not runtime then
		return
	end
	if def.cost and def.cost > 0 then
		self:gain(fighter, def.cost * share)
	end
	if def.kind == "Ultimate" then
		runtime.ult = math.min(ULTIMATE.Max, runtime.ult + ULTIMATE.Max * share)
	end
	local readyAt = runtime.cooldowns[def.id]
	if readyAt then
		local remaining = readyAt - now()
		self:setCooldown(fighter, def.id, now() + math.max(0.5, remaining * (1 - share)))
	end
	self:_publish(fighter, false)
end

-- Sends resource and charge to clients (only when the shown number changes)
function PowerService:_publish(fighter, force: boolean)
	local runtime = fighter.power
	if not runtime or not fighter.model.Parent then
		return
	end
	local resource = math.floor(runtime.resource + 0.5)
	local ult = math.floor(runtime.ult)
	local published = runtime.published
	if force or published.resource ~= resource then
		published.resource = resource
		fighter.model:SetAttribute(Attribute.Resource, resource)
	end
	if force or published.ult ~= ult then
		published.ult = ult
		fighter.model:SetAttribute(Attribute.Ultimate, ult)
	end
end

function PowerService:_tick(dt: number)
	local matchService = self.services.MatchService
	for _, fighter in self.characters:all() do
		local runtime = fighter.power
		if runtime and self.characters:isAlive(fighter) then
			local resourceDef = runtime.def.resource
			if resourceDef and resourceDef.regen and resourceDef.regen ~= 0 then
				runtime.resource = math.clamp(runtime.resource + resourceDef.regen * dt, 0, runtime.resourceMax)
			end
			local match = matchService:getMatchOf(fighter)
			if match and matchService:isCombatAllowed(fighter) and runtime.ultimate then
				runtime.ult = math.min(ULTIMATE.Max, runtime.ult + ULTIMATE.PassivePerSecond * dt)
			end
			local module = runtime.module
			if module and module.tick then
				self:_safe(module.tick, fighter, runtime, dt, AbilityKit.forFighter(fighter))
			end
			self:_publish(fighter, false)
		end
	end
end

-- Hooks CombatService calls ------------------------------------------------------------

function PowerService:modifyIncoming(target, attacker, outcome, opts)
	local runtime = target.power
	local module = runtime and runtime.module
	if module and module.modifyIncoming then
		self:_safe(module.modifyIncoming, target, attacker, outcome, opts, runtime, AbilityKit.forFighter(target))
	end
end

function PowerService:onHitResolved(attacker, target, outcome, opts)
	local dealt = outcome.dealt or 0
	local landed = outcome.result == "Hit" or outcome.result == "Blocked" or outcome.result == "GuardBreak"
	local training = target.trainingDummy and ULTIMATE.TrainingMultiplier or 1
	if dealt > 0 then
		self:addUltimate(attacker, dealt * ULTIMATE.PerDamageDealt * training)
		self:addUltimate(target, dealt * ULTIMATE.PerDamageTaken)
	end
	local attackerRuntime = attacker.power
	if attackerRuntime and landed and opts.kind ~= "Status" then
		local resourceDef = attackerRuntime.def.resource
		if resourceDef and resourceDef.gainOnHit then
			self:gain(attacker, resourceDef.gainOnHit)
		end
		local module = attackerRuntime.module
		if module and module.onHit then
			self:_safe(module.onHit, attacker, target, outcome, opts, attackerRuntime, AbilityKit.forFighter(attacker))
		end
	end
	local targetRuntime = target.power
	if targetRuntime and dealt > 0 then
		local resourceDef = targetRuntime.def.resource
		if resourceDef and resourceDef.gainOnHurt then
			self:gain(target, resourceDef.gainOnHurt)
		end
		local module = targetRuntime.module
		if module and module.onHurt then
			self:_safe(module.onHurt, target, attacker, outcome, opts, targetRuntime, AbilityKit.forFighter(target))
		end
	end
end

function PowerService:onDodged(fighter)
	local runtime = fighter.power
	local module = runtime and runtime.module
	if module and module.onDodge then
		self:_safe(module.onDodge, fighter, runtime, AbilityKit.forFighter(fighter))
	end
end

-- The ability that replaces this fighter's Light or Heavy attack, if any
function PowerService:basicOverride(fighter, kind: string): string?
	local runtime = fighter.power
	if not runtime then
		return nil
	end
	return Powers.basicFor(runtime.id, runtime.degree, runtime.form, kind)
end

-- Syntax's redirect: the equipped, charged and ready ability that can take over projectiles
function PowerService:readyRedirect(fighter)
	local runtime = fighter.power
	if not runtime then
		return nil
	end
	local statuses = self.services.StatusService
	if statuses and statuses:has(fighter, "Sealed") then
		return nil
	end
	for _, abilityId in runtime.loadout do
		local def = Powers.abilityFor(runtime.id, abilityId, runtime.degree)
		if def and def.redirect then
			local readyAt = runtime.cooldowns[abilityId] or 0
			if now() >= readyAt and runtime.resource + 1e-6 >= (def.cost or 0) then
				return def
			end
		end
	end
	return nil
end

function PowerService:commitRedirect(fighter, def)
	self:spend(fighter, def.cost or 0)
	self:setCooldown(fighter, def.id, now() + self:cooldownFor(fighter, def))
	AbilityKit.forFighter(fighter):fx(def.id, { redirected = true })
end

-- Safe teleport destinations -------------------------------------------------------------

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.RespectCanCollide = true
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

-- Where `who` may stand near `desired`: inside their arena (or a sane lobby
-- range), on solid ground, not inside a wall. Tries the spot, then steps back
-- toward where they are. nil if nowhere works (the teleport fails safely).
function PowerService:safeSpot(who, desired: Vector3, maxDistance: number?): Vector3?
	local origin = who.root.Position
	local offset = desired - origin
	if offset.X ~= offset.X or offset.Y ~= offset.Y or offset.Z ~= offset.Z then
		return nil
	end
	if maxDistance and offset.Magnitude > maxDistance then
		desired = origin + offset.Unit * maxDistance
	end
	local match = self.services.MatchService:getMatchOf(who)
	if match then
		desired = self.services.ArenaService:clampInside(match.arena, desired, 4)
	end
	local ignore: { Instance } = {}
	for _, fighter in self.characters:all() do
		table.insert(ignore, fighter.model)
	end
	for _, name in { "SNEffects", "SNLocalDebris" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	groundParams.FilterDescendantsInstances = ignore
	overlapParams.FilterDescendantsInstances = ignore
	local steps = 6
	for step = 0, steps do
		local candidate = desired:Lerp(origin, step / steps)
		local ground = workspace:Raycast(candidate + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), groundParams)
		if ground then
			local stand = ground.Position + Vector3.new(0, 3, 0)
			local blocking = workspace:GetPartBoundsInBox(CFrame.new(stand + Vector3.new(0, 0.3, 0)), Vector3.new(2, 4.4, 2), overlapParams)
			if #blocking == 0 then
				return stand
			end
		end
	end
	return nil
end

function PowerService:nextKey(): string
	keyCounter += 1
	return "k" .. keyCounter
end

return PowerService
