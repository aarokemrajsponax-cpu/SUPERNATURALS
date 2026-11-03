-- Gives every fighter its power: which of the eight, which degree, which
-- abilities are equipped, plus the power's resource (grit, fuel, corruption...),
-- ultimate charge, cooldowns and look. Players choose in the Powers screen;
-- the choice is checked here (premium ownership, degree unlocks, loadout rules),
-- saved to their profile, and LOCKED for the whole of a match: no changes of
-- power, degree or loadout mid-fight, paid or otherwise.
--
-- It also owns the rules that keep the lobby, training and combat apart
-- (docs/specs/SelectionContract.md):
--   * combatContext: THE check every combat entry point asks. Combat works in a
--     running fight, in the training hall and for the owner's showcase mode; the
--     lobby refuses it. CombatService:canAct, AbilityService and
--     MatchService:isCombatAllowed all end here, so a client can't go around it.
--   * Selection: one confirm step (Confirm, Select, or a Queue that carries a
--     selection) that never charges. Phase fees (Config/Selection) are paid only when
--     evolving mid-match (PowerService:evolve). Browsing, quotes and snapshots never charge.
--   * Training trials: any power and degree for free, never saved, and gone when
--     the player leaves the hall or queues.
--   * The extra ability slot (mastery level, or the all-powers pass; free for the owner).
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
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Selection = require(ReplicatedStorage.Shared.Config.Selection)
local MatchFlow = require(ReplicatedStorage.Shared.Match.MatchFlow)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local AbilityKit = require(script.Parent.Parent.Combat.AbilityKit)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PowerRequest = Remotes:WaitForChild("PowerRequest") :: RemoteEvent
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent
local MatchEvent = Remotes:WaitForChild("MatchEvent") :: RemoteEvent
local CombatEvent = Remotes:WaitForChild("CombatEvent") :: RemoteEvent

local Attribute = Protocol.Attribute
local Action = Protocol.PowerAction
local Code = Protocol.SelectionCode
local Context = Protocol.CombatContext
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
	-- A Training (or showcase) trial: any power and degree for free, never saved, dropped
	-- when the player leaves the hall, queues or enters a match
	training: boolean,
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
	published: { [string]: any },
	-- Phase meter (0 to Selection.Phase.MeterMax), earned in combat, emptied on evolving
	meter: number,
	-- Server time a transformation ends (0 when none is under way)
	transformUntil: number,
	-- True once the fighter evolved away from the phase they were equipped at
	evolved: boolean,
}

local modules: { [string]: any } = {}
-- Players in a match: their power, degree and loadout as they were when it started
local locked: { [Player]: { power: string, degree: number, loadout: { string }, phase: number? } } = {}
local keyCounter = 0
-- Owners with showcase mode on, and when each player last saw the lobby notice
local showcase: { [Player]: boolean } = {}
local noticeAt: { [Player]: number } = {}

-- What combatContext answers. Shared and frozen, so asking costs nothing (abilities ask
-- on every step of a cast).
local VERDICTS = {
	MatchOn = table.freeze({ context = Context.Match, allowed = true }),
	-- Countdown and results screens: in a match, but not fighting
	MatchOff = table.freeze({ context = Context.Match, allowed = false, reason = "unavailable" }),
	Npc = table.freeze({ context = Context.Npc, allowed = true }),
	Training = table.freeze({ context = Context.Training, allowed = true }),
	Showcase = table.freeze({ context = Context.Showcase, allowed = true }),
	Lobby = table.freeze({ context = Context.Lobby, allowed = false, reason = Protocol.RejectReason.Lobby }),
}

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
			-- The all-powers extra ability slot: every loadout gets one more slot, so say so
			if passKey == Selection.ExtraSlot.PassKey then
				toast(player, "Extra ability slot unlocked on every power.", "success")
				self:_sendSnapshot(player)
			end
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
		showcase[player] = nil
		noticeAt[player] = nil
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

-- The refusal for a premium power that isn't owned, in Duel and Free-for-All. It names no Robux
-- amount: Robux prices are regional and only Roblox knows the player's (the Fighter Showcase
-- shows the live price from GetProductInfoAsync). Gems are the game's own currency.
local function premiumRefusal(def): string
	local premium = def.premium
	local gems = if premium and premium.gems then ` with Robux or {premium.gems} Gems` else " with Robux"
	return `{def.name} is a premium power. Try it in Training or CPU Practice, or unlock it in the Fighter Showcase{gems}.`
end

-- The saved selection: what stays equipped until the player switches (the default fighter
-- until their profile loads)
function PowerService:_selected(player: Player): { power: string, degree: number }
	local profile = self:_profile(player)
	local selected = profile and profile.selected
	local powerId = Powers.Default
	local degree = 1
	if selected and typeof(selected.power) == "string" and Powers.get(selected.power) then
		powerId = selected.power
		if typeof(selected.degree) == "number" then
			degree = math.clamp(math.floor(selected.degree), 1, math.max(1, Powers.degreeCount(powerId)))
		end
	end
	return { power = powerId, degree = degree }
end

-- MatchService asks before queueing: premium powers need to be owned in PvP. A Training trial
-- is never what goes into a match, so it is judged by the saved selection instead.
function PowerService:queueCheck(player: Player, modeName: string): (boolean, string?)
	if not RANKED_MODES[modeName] then
		return true, nil
	end
	local fighter = self.characters:getByPlayer(player)
	local runtime = fighter and fighter.power
	if runtime and not runtime.training then
		if runtime.trial then
			return false, premiumRefusal(runtime.def)
		end
		return true, nil
	end
	local selected = self:_selected(player)
	local def = Powers.get(selected.power)
	if def and def.premium and not self:owns(player, selected.power) then
		return false, premiumRefusal(def)
	end
	return true, nil
end

-- Locks a player's power for the length of a match (MatchService calls these). Showcase
-- mode and Training trials never go into a match: they end here.
function PowerService:lock(player: Player)
	self:_setShowcase(player, false)
	local fighter = self.characters:getByPlayer(player)
	if fighter and fighter.power and fighter.power.training then
		self:_endTrial(player)
	end
	local runtime = fighter and fighter.power
	if runtime then
		-- Every match starts in Phase 1, whatever degree was picked before it
		if runtime.degree ~= 1 and fighter and self.characters:isAlive(fighter) then
			self:equip(fighter, runtime.id, 1, self:_fitLoadout(fighter, runtime.id, 1, runtime.loadout), { trial = runtime.trial })
			runtime = fighter.power
			runtime.evolved = true -- match end puts the saved selection back
		end
		locked[player] = { power = runtime.id, degree = 1, loadout = table.clone(runtime.loadout), phase = runtime.degree }
	end
end

function PowerService:unlock(player: Player)
	locked[player] = nil
	-- The match is over: back to the saved selection (Phase 1 unless they saved a higher degree)
	local fighter = self.characters:getByPlayer(player)
	local runtime = fighter and fighter.power
	if fighter and runtime and self.characters:isAlive(fighter) then
		if runtime.evolved then
			self:_equipForPlayer(fighter)
		end
	end
end

function PowerService:isLocked(player: Player): boolean
	return locked[player] ~= nil
end

-- The power, degree and loadout a player is locked into for their current match
function PowerService:lockedSelection(player: Player): { power: string, degree: number, loadout: { string } }?
	return locked[player]
end

-- Combat context -------------------------------------------------------------------------------

function PowerService:_isOwner(player: Player): boolean
	local owner = self.services.OwnerService
	return owner ~= nil and owner:isOwner(player) == true
end

-- Is this owner's showcase mode on?
function PowerService:isShowcase(player: Player): boolean
	return showcase[player] == true
end

-- THE combat check. Where does this fighter stand, and does combat work there right now?
-- Answers with a shared read-only { context, allowed, reason? }:
--   Match     only while the fight is on (the countdown and results screens are in a match
--             but don't allow it; reason "unavailable", as it always was)
--   Npc       training dummies and CPU opponents, which the server runs
--   Training  standing in the training hall, however they got there
--   Showcase  the owner, with showcase mode on
--   Lobby     everywhere else; reason Protocol.RejectReason.Lobby
-- Everything that starts or continues combat asks this: CombatService:canAct (every basic
-- action and every ability) and MatchService:isCombatAllowed (long casts ask again at each
-- step). There is no second copy of the rule, and the client's opinion is never used.
function PowerService:combatContext(fighter)
	local match = self.services.MatchService:getMatchOf(fighter)
	if match then
		return if match.flow ~= nil and MatchFlow.isFighting(match.flow) then VERDICTS.MatchOn else VERDICTS.MatchOff
	end
	if fighter.npc then
		return VERDICTS.Npc
	end
	local player = fighter.player
	if not player then
		return VERDICTS.Lobby
	end
	if Selection.inTrainingZone(fighter.root.CFrame.Position) then
		return VERDICTS.Training
	end
	if showcase[player] and self:_isOwner(player) then
		return VERDICTS.Showcase
	end
	return VERDICTS.Lobby
end

-- A calm notice that combat is off in the lobby, at most one every few seconds per player.
-- The request handlers call it when the combat check said "lobby"; blocking is refused quietly.
function PowerService:noteLobbyRefusal(player: Player, action: string?)
	if not player.Parent or (action ~= nil and Selection.QuietActions[action]) then
		return
	end
	local time = now()
	local last = noticeAt[player]
	if last and time - last < Selection.NoticeCooldown then
		return
	end
	noticeAt[player] = time
	MatchEvent:FireClient(player, Protocol.MatchEvent.Notice, { text = Selection.Text.LobbyLocked })
end

-- Keeps the context attribute clients read current, and drops a Training trial the moment
-- its player leaves the hall (or the owner turns showcase off)
function PowerService:_watchContext(fighter)
	local verdict = self:combatContext(fighter)
	local model = fighter.model
	if model:GetAttribute(Attribute.CombatContext) ~= verdict.context then
		model:SetAttribute(Attribute.CombatContext, verdict.context)
	end
	local runtime = fighter.power
	if runtime and runtime.training and verdict.context ~= Context.Training and verdict.context ~= Context.Showcase then
		self:_endTrial(fighter.player :: Player, true)
	elseif runtime and runtime.evolved and not runtime.training and verdict.context == Context.Lobby and not locked[fighter.player :: Player] then
		-- Left the training hall evolved: back to the saved selection
		self:_equipForPlayer(fighter)
	end
end

-- Showcase mode: the owner's powers work in the lobby (and hurt no one: only dummies and
-- running matches take damage). Server state only; the owner check is repeated on every use.
function PowerService:_setShowcase(player: Player, on: boolean)
	local was = showcase[player] == true
	showcase[player] = if on then true else nil
	if player.Parent and was ~= on then
		player:SetAttribute(Attribute.Showcase, if on then true else nil)
	end
end

-- The extra ability slot ------------------------------------------------------------------------

-- Does this player own the all-powers extra slot pass? Monetization may not have the pass yet
-- (another file adds it, and its id stays 0 until the owner makes it), so nothing here assumes it.
function PowerService:_hasSlotPass(player: Player): boolean
	local purchases = self.services.PurchaseService
	if not purchases then
		return false
	end
	local ok, owns = pcall(purchases.ownsPass, purchases, player, Selection.ExtraSlot.PassKey)
	return ok and owns == true
end

-- Does this power have the extra slot for this player? Earned at a mastery level, or from the
-- all-powers pass; the owner has it everywhere (nothing is written for that).
function PowerService:hasExtraSlot(player: Player, powerId: string): boolean
	if self:_isOwner(player) then
		return true
	end
	local xp = powerData(self:_profile(player), powerId).xp
	if Powers.masteryLevel(if typeof(xp) == "number" then xp else 0) >= Selection.ExtraSlot.MasteryLevel then
		return true
	end
	return self:_hasSlotPass(player)
end

local function totalSlots(base: number, extra: boolean): number
	if not extra then
		return base
	end
	local cap = math.max(base, Selection.ExtraSlot.MaxTotal)
	return math.min(base + Selection.ExtraSlot.Count, cap)
end

-- Loadout slots this player has for a power and degree: the degree's own plus the extra slot
function PowerService:slotsFor(player: Player, powerId: string, degree: number): number
	local degreeDef = Powers.degree(powerId, degree)
	if not degreeDef then
		return 0
	end
	return totalSlots(degreeDef.slots, self:hasExtraSlot(player, powerId))
end

-- Powers.validateLoadout with this player's slot count (and the owner's, or a Training trial's,
-- every ability unlocked). Returns (ok, reason, cleaned list). The slot limit is the server's
-- own: a client that sends more abilities than it has slots is refused.
function PowerService:validateLoadout(player: Player, powerId: string, degree: number, list: any, everything: boolean?): (boolean, string?, { string }?)
	local degreeDef = Powers.degree(powerId, degree)
	if not degreeDef then
		return false, "Unknown power or degree.", nil
	end
	if typeof(list) ~= "table" then
		return false, "That loadout isn't valid.", nil
	end
	local data = powerData(self:_profile(player), powerId)
	if everything or self:_isOwner(player) then
		local abilities = {}
		for abilityId in Powers.get(powerId).abilities do
			abilities[abilityId] = true
		end
		data = { xp = data.xp, degrees = data.degrees, owned = data.owned, abilities = abilities }
	end
	local base = degreeDef.slots
	local slots = totalSlots(base, self:hasExtraSlot(player, powerId))
	-- A plain list and no longer than the slots (a huge junk table is never walked)
	local length = #list
	local keys = 0
	for _ in list do
		keys += 1
		if keys > slots + 1 then
			break
		end
	end
	if keys ~= length then
		return false, "That loadout isn't valid.", nil
	end
	if length > slots then
		return false, `This degree has {slots} ability slots.`, nil
	end
	if length <= base then
		return Powers.validateLoadout(powerId, degree, list, data)
	end
	-- The extra slot is in use: the base slots go through the shared rules, then each extra
	-- ability must pass them alone and not repeat one already equipped
	local head = table.move(list, 1, base, 1, {})
	local ok, reason, cleaned = Powers.validateLoadout(powerId, degree, head, data)
	if not ok or not cleaned then
		return false, reason, nil
	end
	for index = base + 1, length do
		local abilityId = list[index]
		if typeof(abilityId) == "string" and table.find(cleaned, abilityId) then
			return false, "Each ability can only be equipped once.", nil
		end
		local single, why = Powers.validateLoadout(powerId, degree, { abilityId }, data)
		if not single then
			return false, why, nil
		end
		table.insert(cleaned, abilityId)
	end
	return true, nil, cleaned
end

-- Selection: prices, the confirm step and training trials --------------------------------------

local function formatMoney(amount: number): string
	local text = tostring(math.floor(amount))
	local grouped = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return (string.gsub(grouped, "^,", "")) .. " Money"
end

local function validId(id: any): boolean
	return typeof(id) == "number" and id > 0 and id % 1 == 0
end

local function newResult(action: string, ok: boolean, code: string, message: string, extra: { [string]: any }?): { [string]: any }
	local result: { [string]: any } = { action = action, ok = ok, code = code, message = message, charged = 0 }
	if extra then
		for key, value in extra do
			result[key] = value
		end
	end
	return result
end

function PowerService:_money(player: Player): number
	local profile = self:_profile(player)
	return if profile then profile.currencies.money or 0 else 0
end

-- Tells the player what a request did (Protocol.DataEvent.SelectionResult). Their balance
-- after the request is added.
function PowerService:_reply(player: Player, result: { [string]: any })
	if player.Parent then
		result.money = self:_money(player)
		DataEvent:FireClient(player, Protocol.DataEvent.SelectionResult, result)
	end
end

-- The facts about a player that every price and status decision needs, read once
function PowerService:_view(player: Player)
	local profile = self:_profile(player)
	local currencies = if profile then profile.currencies else nil
	local matches = self.services.MatchService
	return {
		profile = profile,
		owner = self:_isOwner(player),
		inMatch = locked[player] ~= nil,
		queued = matches ~= nil and matches:isQueued(player),
		money = if currencies then currencies.money or 0 else 0,
		gems = if currencies then currencies.gems or 0 else 0,
		selected = self:_selected(player),
	}
end

-- What selecting this degree would do for this player right now: whether it would be accepted
-- (and the code and plain reason if not), what it costs, and what it would charge. The confirm
-- step, quotes and the snapshot all use this one function, so a screen can never promise
-- something the server then refuses. `opts.mode` is the mode being entered (the ranked
-- ownership rule); `opts.requeue` is a Queue request, which replaces any queue they are in.
function PowerService:_decide(player: Player, view, powerId: string, degree: number, opts: { mode: string?, requeue: boolean? }?)
	local def = Powers.get(powerId)
	local degreeDef = def.degrees[degree]
	local owned = self:owns(player, powerId)
	local trialOnly = def.premium ~= nil and not owned
	local price = Selection.priceFor(powerId, degree, def.premium ~= nil)
	local equipped = view.selected.power == powerId and view.selected.degree == degree
	local unlocked = view.owner or Powers.degreeUnlocked(powerId, degree, powerData(view.profile, powerId))
	-- The pre-match confirm chooses fighter and loadout and never charges. `price` is the
	-- phase fee: what evolving into this degree costs mid-fight (see Selection.Prices).
	local charge = 0
	local verdict = {
		ok = true,
		code = Code.Ok,
		message = "",
		price = price,
		charge = charge,
		trialOnly = trialOnly,
		unlocked = unlocked,
		equipped = equipped,
		canAfford = view.money >= charge,
	}
	local function refuse(code: string, message: string)
		verdict.ok = false
		verdict.code = code
		verdict.message = message
	end
	if view.inMatch then
		refuse(Code.InMatch, "Your power and degree are locked until the fight ends.")
	elseif view.queued and not equipped and not (opts and opts.requeue) then
		refuse(Code.Queued, "Leave the queue to change your fighter or degree.")
	elseif not unlocked then
		local mastery = if degreeDef.unlock then degreeDef.unlock.mastery else nil
		refuse(Code.DegreeLocked, `{degreeDef.name} is locked. Reach mastery level {mastery or "?"} or unlock it.`)
	elseif trialOnly and opts and opts.mode and RANKED_MODES[opts.mode] then
		refuse(Code.NotOwned, premiumRefusal(def))
	elseif not verdict.canAfford then
		refuse(Code.CantAfford, `{degreeDef.name} costs {formatMoney(charge)} to select. You have {formatMoney(view.money)}.`)
	end
	return verdict
end

-- One degree as screens see it (the snapshot lists these; a quote is one of them)
function PowerService:_entry(player: Player, view, powerId: string, degree: number, hasSlot: boolean)
	local degreeDef = Powers.get(powerId).degrees[degree]
	local verdict = self:_decide(player, view, powerId, degree, nil)
	return {
		degree = degree,
		name = degreeDef.name,
		price = verdict.price,
		fee = if self:_isOwner(player) then 0 else verdict.price,
		feeAffordable = self:_isOwner(player) or view.money >= verdict.price,
		charge = verdict.charge,
		unlocked = verdict.unlocked,
		unlockLevel = if degreeDef.unlock then degreeDef.unlock.mastery else nil,
		unlockMoney = if degreeDef.unlock then degreeDef.unlock.money else nil,
		equipped = verdict.equipped,
		trialOnly = verdict.trialOnly,
		canAfford = verdict.canAfford,
		baseSlots = degreeDef.slots,
		slots = totalSlots(degreeDef.slots, hasSlot),
		code = verdict.code,
	}, verdict
end

-- Does the pass behind a premium power sell yet (its id is set)?
local function passOnSale(passKey: string?): boolean
	local passes = Monetization.Passes
	local pass = if passKey and typeof(passes) == "table" then passes[passKey] else nil
	return typeof(pass) == "table" and validId(pass.id)
end

-- Everything a selection screen needs, in one table (Protocol.DataEvent.Selection)
function PowerService:snapshot(player: Player)
	local view = self:_view(player)
	local fighter = self.characters:getByPlayer(player)
	local verdict = if fighter then self:combatContext(fighter) else VERDICTS.Lobby
	local profile = view.profile
	local runtime = fighter and fighter.power
	local training = runtime ~= nil and runtime.training
	local trialContext = verdict.context == Context.Training or verdict.context == Context.Showcase
	local selected = view.selected
	local selectedDef = Powers.get(selected.power)

	local passes = Monetization.Passes
	local slotPass = if typeof(passes) == "table" then passes[Selection.ExtraSlot.PassKey] else nil
	local snapshot = {
		context = verdict.context,
		combat = verdict.allowed,
		canTrial = trialContext and not view.inMatch and not view.queued,
		locked = view.inMatch,
		queued = view.queued,
		owner = view.owner,
		showcase = showcase[player] == true,
		money = view.money,
		gems = view.gems,
		currency = Selection.Currency,
		stays = true,
		equipped = {
			power = selected.power,
			degree = selected.degree,
			loadout = self:_savedLoadout(player, selected.power, selected.degree),
			trialOnly = selectedDef.premium ~= nil and not self:owns(player, selected.power),
		},
		trial = if training and runtime then { power = runtime.id, degree = runtime.degree, loadout = table.clone(runtime.loadout) } else nil,
		extraSlot = {
			masteryLevel = Selection.ExtraSlot.MasteryLevel,
			max = Selection.ExtraSlot.MaxTotal,
			hasPass = view.owner or self:_hasSlotPass(player),
			pass = if typeof(slotPass) == "table"
				then {
					key = Selection.ExtraSlot.PassKey,
					name = slotPass.name,
					benefit = slotPass.benefit,
					onSale = validId(slotPass.id),
				}
				else nil,
		},
		powers = {},
	}
	for _, powerId in Powers.Order do
		local def = Powers.get(powerId)
		if def then
			local hasSlot = self:hasExtraSlot(player, powerId)
			local degrees = {}
			for degree = 1, Powers.degreeCount(powerId) do
				table.insert(degrees, (self:_entry(player, view, powerId, degree, hasSlot)))
			end
			local xp = powerData(profile, powerId).xp
			snapshot.powers[powerId] = {
				id = powerId,
				name = def.name,
				premium = def.premium ~= nil,
				owned = self:owns(player, powerId),
				level = Powers.masteryLevel(if typeof(xp) == "number" then xp else 0),
				extraSlot = hasSlot,
				unlock = if def.premium
					then {
						passKey = def.premium.pass,
						gems = def.premium.gems,
						onSale = passOnSale(def.premium.pass),
					}
					else nil,
				degrees = degrees,
			}
		end
	end
	return snapshot
end

function PowerService:_sendSnapshot(player: Player)
	if player.Parent and self:_profile(player) then
		DataEvent:FireClient(player, Protocol.DataEvent.Selection, self:snapshot(player))
	end
end

-- Does this look like a real power, degree and (optional) loadout? Junk is flagged and refused.
local function wellFormed(powerId: any, degree: any, loadout: any): boolean
	return typeof(powerId) == "string"
		and Powers.get(powerId) ~= nil
		and Powers.validDegree(powerId, degree)
		and (loadout == nil or typeof(loadout) == "table")
end

-- A read-only price and status for one selection. Never charges, never changes anything.
function PowerService:_quote(player: Player, powerId: any, degree: any, loadout: any)
	if not wellFormed(powerId, degree, loadout) then
		self.antiExploit:flag(player, "junk selection quote")
		self:_reply(player, newResult("Quote", false, Code.BadRequest, "That power doesn't exist."))
		return
	end
	local view = self:_view(player)
	local entry, verdict = self:_entry(player, view, powerId, degree, self:hasExtraSlot(player, powerId))
	entry.power = powerId
	entry.message = verdict.message
	entry.stays = true
	entry.money = view.money
	if loadout ~= nil then
		local ok, reason, cleaned = self:validateLoadout(player, powerId, degree, loadout)
		entry.loadoutOk = ok
		entry.loadoutMessage = reason
		entry.loadout = cleaned
	end
	DataEvent:FireClient(player, Protocol.DataEvent.SelectionQuote, entry)
end

-- The one confirm step. Checks everything first, so a refusal changes nothing and charges
-- nothing; then charges the degree's price once, only when this switches to a different
-- priced degree; then saves and equips. Re-confirming the saved selection, or only
-- changing its loadout, is free. opts.action names the request for the reply ("Confirm",
-- "Select" or "Queue"); opts.mode is the mode being entered; opts.toast also toasts the
-- message (the old Select did). Returns (result, receipt); the receipt lets a Queue that
-- could not start undo the switch (revertConfirm).
function PowerService:confirmSelection(player: Player, powerId: any, degree: any, loadout: any, opts: { action: string, mode: string?, requeue: boolean?, toast: boolean? })
	local action = opts.action
	local function refuse(code: string, message: string, extra: { [string]: any }?)
		local result = newResult(action, false, code, message, extra)
		result.mode = opts.mode
		self:_reply(player, result)
		if opts.toast then
			toast(player, message, "error")
		end
		return result, nil
	end

	if not self:_profile(player) then
		return refuse(Code.Loading, "Your data is still loading. Try again in a moment.")
	end
	if not wellFormed(powerId, degree, loadout) then
		self.antiExploit:flag(player, "junk selection request")
		return refuse(Code.BadRequest, "That power doesn't exist.")
	end
	local def = Powers.get(powerId)
	local view = self:_view(player)
	local verdict = self:_decide(player, view, powerId, degree, { mode = opts.mode, requeue = opts.requeue })
	local extra = { power = powerId, degree = degree, price = verdict.price }
	if not verdict.ok then
		return refuse(verdict.code, verdict.message, extra)
	end

	-- The loadout is checked before any money moves
	local list: { string }
	if loadout ~= nil then
		local ok, reason, cleaned = self:validateLoadout(player, powerId, degree, loadout)
		if not ok or not cleaned then
			return refuse(Code.BadLoadout, reason or "That loadout isn't valid.", extra)
		end
		list = cleaned
	else
		list = self:_savedLoadout(player, powerId, degree)
	end

	-- Charge, then save. Nothing between these two steps can wait, so two quick
	-- confirms can't both be charged for one switch.
	local charged = 0
	if verdict.charge > 0 then
		local paid = self.services.CurrencyService:spend(player, { money = verdict.charge }, `selection:{powerId}/{degree}`)
		if not paid then
			return refuse(Code.CantAfford, `{def.degrees[degree].name} costs {formatMoney(verdict.charge)} to select. You have {formatMoney(self:_money(player))}.`, extra)
		end
		charged = verdict.charge
	end
	local profile = self:_profile(player)
	local previous = view.selected
	local oldLoadouts = profile.loadouts[powerId]
	local oldList = if oldLoadouts and oldLoadouts[tostring(degree)] then table.clone(oldLoadouts[tostring(degree)]) else nil
	local saved = self.services.DataService:update(player, function(data)
		data.selected = { power = powerId, degree = degree }
		if loadout ~= nil then
			data.loadouts[powerId] = data.loadouts[powerId] or {}
			data.loadouts[powerId][tostring(degree)] = list
		end
	end)
	if not saved then
		if charged > 0 then
			self.services.CurrencyService:add(player, { money = charged }, "selection refund")
		end
		return refuse(Code.Loading, "Your data is still loading. Try again in a moment.", extra)
	end

	local fighter = self.characters:getByPlayer(player)
	if fighter and self.characters:isAlive(fighter) then
		self:equip(fighter, powerId, degree, list, { trial = verdict.trialOnly })
	end
	local switched = previous.power ~= powerId or previous.degree ~= degree
	local message = `Now using {def.name}, {def.degrees[degree].name}`
	if verdict.trialOnly then
		message ..= " (trial: Training and CPU Practice only)"
	end
	message ..= "."
	if charged > 0 then
		message ..= ` Paid {formatMoney(charged)}.`
	end
	local result = newResult(action, true, Code.Ok, message, {
		power = powerId,
		degree = degree,
		loadout = list,
		price = verdict.price,
		charged = charged,
		switched = switched,
		persists = true,
		trialOnly = verdict.trialOnly,
		mode = opts.mode,
		slots = self:slotsFor(player, powerId, degree),
	})
	self:_reply(player, result)
	self:_sendSnapshot(player)
	if opts.toast then
		toast(player, message, "success")
	end
	local receipt = {
		power = powerId,
		degree = degree,
		charged = charged,
		previous = previous,
		loadoutChanged = loadout ~= nil,
		previousLoadout = oldList,
	}
	return result, receipt
end

-- Undoes a confirm: the old selection and loadout back, the charge refunded. Used when the
-- Queue request that carried the selection could not start a match (every arena was busy),
-- so a player is never charged for a match that did not happen.
function PowerService:revertConfirm(player: Player, receipt)
	if typeof(receipt) ~= "table" or not self:_profile(player) then
		return
	end
	self.services.DataService:update(player, function(data)
		data.selected = { power = receipt.previous.power, degree = receipt.previous.degree }
		if receipt.loadoutChanged then
			local byDegree = data.loadouts[receipt.power]
			if byDegree then
				byDegree[tostring(receipt.degree)] = receipt.previousLoadout
			end
		end
	end)
	if receipt.charged > 0 then
		self.services.CurrencyService:add(player, { money = receipt.charged }, "selection refund")
	end
	local fighter = self.characters:getByPlayer(player)
	if fighter and self.characters:isAlive(fighter) and not locked[player] then
		self:_equipForPlayer(fighter)
	end
	self:_sendSnapshot(player)
end

-- MatchService calls this first for every Queue request. A Training trial never goes into a
-- match, so it ends. A selection carried in options.selection is confirmed here (charged once).
-- Then the usual rule: a premium power that is only being tried can't enter Duel or
-- Free-for-All. Returns (ok, reason, receipt).
function PowerService:prepareQueue(player: Player, modeName: string, options: any): (boolean, string?, any)
	self:_endTrial(player, false)
	local selection = if typeof(options) == "table" then options.selection else nil
	local receipt = nil
	if selection ~= nil then
		if typeof(selection) ~= "table" then
			self.antiExploit:flag(player, "junk queue selection")
			local result = newResult("Queue", false, Code.BadRequest, "That selection isn't valid.", { mode = modeName })
			self:_reply(player, result)
			return false, result.message, nil
		end
		local result, made = self:confirmSelection(player, selection.power, selection.degree, selection.loadout, {
			action = "Queue",
			mode = modeName,
			requeue = true,
		})
		if not result.ok then
			return false, result.message, nil
		end
		receipt = made
	end
	local allowed, reason = self:queueCheck(player, modeName)
	if not allowed then
		if receipt then
			self:revertConfirm(player, receipt)
		end
		self:_reply(player, newResult("Queue", false, Code.NotOwned, reason or "", { mode = modeName }))
		return false, reason, nil
	end
	return true, nil, receipt
end

-- Training trials ------------------------------------------------------------------------------

-- Equips any power and degree for free, in the training hall (or for the owner's showcase).
-- Every ability is open and nothing is charged or saved: the match selection is untouched.
function PowerService:trial(player: Player, powerId: any, degree: any, loadout: any)
	local function refuse(code: string, message: string)
		self:_reply(player, newResult("Trial", false, code, message))
	end
	if not self:_profile(player) then
		return refuse(Code.Loading, "Your data is still loading. Try again in a moment.")
	end
	if not wellFormed(powerId, degree, loadout) then
		self.antiExploit:flag(player, "junk trial request")
		return refuse(Code.BadRequest, "That power doesn't exist.")
	end
	if locked[player] then
		return refuse(Code.InMatch, "Your power and degree are locked until the fight ends.")
	end
	if self.services.MatchService:isQueued(player) then
		return refuse(Code.Queued, "Leave the queue to try powers.")
	end
	local fighter = self.characters:getByPlayer(player)
	local context = fighter and self:combatContext(fighter).context
	if not fighter or not self.characters:isAlive(fighter) or (context ~= Context.Training and context ~= Context.Showcase) then
		return refuse(Code.NotInTraining, "Trials work in the training hall.")
	end
	local list: { string }
	if loadout ~= nil then
		local ok, reason, cleaned = self:validateLoadout(player, powerId, degree, loadout, true)
		if not ok or not cleaned then
			return refuse(Code.BadLoadout, reason or "That loadout isn't valid.")
		end
		list = cleaned
	else
		list = self:_savedLoadout(player, powerId, degree, true)
	end
	self:equip(fighter, powerId, degree, list, { trial = false, training = true })
	local def = Powers.get(powerId)
	self:_reply(player, newResult("Trial", true, Code.Ok, `Trying {def.name}, {def.degrees[degree].name}. {Selection.Text.TrialStays}`, {
		power = powerId,
		degree = degree,
		loadout = list,
		price = Selection.priceFor(powerId, degree, def.premium ~= nil),
		persists = false,
		slots = self:slotsFor(player, powerId, degree),
	}))
	self:_sendSnapshot(player)
end

-- Back to the saved selection. Returns whether a trial was running. `notify` tells the
-- player (leaving the hall does; queueing and starting a match do it quietly).
function PowerService:_endTrial(player: Player, notify: boolean?): boolean
	local fighter = self.characters:getByPlayer(player)
	local runtime = fighter and fighter.power
	if not fighter or not runtime or not runtime.training then
		return false
	end
	-- A fighter who is down is re-equipped from the saved selection when they respawn
	if self.characters:isAlive(fighter) then
		self:_equipForPlayer(fighter)
	end
	if notify then
		self:_reply(player, newResult("EndTrial", true, Code.Ok, "Training trial over. Back to your saved selection."))
		self:_sendSnapshot(player)
	end
	return true
end

function PowerService:_showcaseRequest(player: Player, on: any)
	local function reply(ok: boolean, code: string, message: string)
		self:_reply(player, newResult("SetShowcase", ok, code, message, { showcase = showcase[player] == true }))
	end
	if typeof(on) ~= "boolean" then
		self.antiExploit:flag(player, "junk showcase request")
		return reply(false, Code.BadRequest, "That request isn't valid.")
	end
	if not self:_isOwner(player) then
		self.antiExploit:flag(player, "tried to use showcase mode")
		return reply(false, Code.NotOwner, "Showcase mode is for the owner.")
	end
	if on and locked[player] then
		return reply(false, Code.InMatch, "Showcase mode isn't available during a match.")
	end
	self:_setShowcase(player, on)
	local fighter = self.characters:getByPlayer(player)
	if fighter then
		-- Turning it off drops a trial that was only allowed by showcase mode
		self:_watchContext(fighter)
	end
	reply(true, Code.Ok, if on then Selection.Text.ShowcaseOn else Selection.Text.ShowcaseOff)
	self:_sendSnapshot(player)
end

-- Requests -------------------------------------------------------------------------------

function PowerService:_onRequest(player: Player, action: string, first: any, second: any, third: any)
	local currency = self.services.CurrencyService
	local data = self.services.DataService
	local profile = self:_profile(player)
	local selectionAction = action == Action.State
		or action == Action.Quote
		or action == Action.Confirm
		or action == Action.Trial
		or action == Action.EndTrial
		or action == Action.SetShowcase
		or action == Action.Evolve
	if not profile or not data then
		if selectionAction then
			self:_reply(player, newResult(action, false, Code.Loading, "Your data is still loading. Try again in a moment."))
		else
			toast(player, "Your data is still loading. Try again in a moment.", "error")
		end
		return
	end

	-- Selection screens: none of these charge except Confirm, and only when it switches to a
	-- different priced degree (docs/specs/SelectionContract.md)
	if selectionAction then
		if action == Action.State then
			self:_sendSnapshot(player)
		elseif action == Action.Quote then
			self:_quote(player, first, second, third)
		elseif action == Action.Confirm then
			self:confirmSelection(player, first, second, third, { action = "Confirm" })
		elseif action == Action.Trial then
			self:trial(player, first, second, third)
		elseif action == Action.Evolve then
			self:evolve(player, first)
		elseif action == Action.EndTrial then
			if not self:_endTrial(player, true) then
				self:_reply(player, newResult("EndTrial", true, Code.Ok, "No trial is running."))
			end
		else
			self:_showcaseRequest(player, first)
		end
		return
	end

	if typeof(first) ~= "string" or not Powers.get(first) then
		return
	end
	local powerId: string = first
	local def = Powers.get(powerId)

	if action == Action.Select then
		-- The old name for Confirm without a loadout: same prices, same rules, plus the toast
		self:confirmSelection(player, powerId, second, nil, { action = "Select", toast = true })
	elseif action == Action.SetLoadout then
		self:setLoadout(player, powerId, second, third)
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

-- Phases (evolving) -------------------------------------------------------------------------

-- Does this fighter's current moment allow the Phase meter to fill? Real fights only.
function PowerService:_fillMeter(fighter, amount: number)
	local runtime = fighter.power
	if not runtime or fighter.trainingDummy or amount <= 0 then
		return
	end
	if runtime.transformUntil > now() or not self.characters:isAlive(fighter) then
		return
	end
	runtime.meter = math.min(Selection.Phase.MeterMax, runtime.meter + amount)
end

-- Keeps a fighter's current loadout through a phase change when it is still valid at the
-- new degree, then fills any slots the new degree adds from the loadout saved (or default)
-- for it, so the new abilities are on the bar. Falls back to that loadout when the old one
-- no longer fits.
function PowerService:_fitLoadout(fighter, powerId: string, degree: number, current: { string }): { string }
	local player = fighter.player
	local runtime = fighter.power
	local everything = runtime ~= nil and runtime.training == true
	local slots = Powers.degree(powerId, degree).slots
	local target: { string }
	local kept: { string }
	if player then
		slots = self:slotsFor(player, powerId, degree)
		target = self:_savedLoadout(player, powerId, degree, everything)
		local ok, _, cleaned = self:validateLoadout(player, powerId, degree, current, everything)
		kept = if ok and cleaned then cleaned else {}
	else
		target = Powers.defaultLoadout(powerId, degree)
		local available = {}
		for _, id in Powers.available(powerId, degree) do
			available[id] = true
		end
		kept = {}
		for _, id in current do
			if available[id] then
				table.insert(kept, id)
			end
		end
	end
	if #kept ~= #current then
		return target
	end
	for _, id in target do
		if #kept >= slots then
			break
		end
		if not table.find(kept, id) then
			table.insert(kept, id)
		end
	end
	return kept
end

-- The phase this fighter could evolve into next, and its fee in Money: nil when they are in
-- the top phase or have not unlocked the next one. Owners and Training evolve for free.
function PowerService:_nextPhase(fighter): (number?, number)
	local runtime = fighter.power
	if not runtime then
		return nil, 0
	end
	local nextDegree = runtime.degree + 1
	if nextDegree > Powers.degreeCount(runtime.id) then
		return nil, 0
	end
	local player = fighter.player
	local free = runtime.training
	if player then
		free = free or self:_isOwner(player)
		if not free and not Powers.degreeUnlocked(runtime.id, nextDegree, powerData(self:_profile(player), runtime.id)) then
			return nil, 0
		end
	end
	return nextDegree, if free then 0 else Selection.priceFor(runtime.id, nextDegree, runtime.def.premium ~= nil)
end

-- The transformation itself, shared by players and CPUs. Swaps the kit to the new degree's
-- abilities and stats; cooldowns, ultimate charge and resource carry over. Opens a short
-- window of hyper-armour and tells every client.
function PowerService:_transform(fighter, newDegree: number)
	local runtime = fighter.power
	local model = fighter.model
	local from = runtime.degree
	local time = now()
	local window = Selection.Phase.TransformTime
	runtime.degree = newDegree
	runtime.evolved = true
	runtime.ultimate = Powers.ultimateOf(runtime.id, newDegree)
	runtime.loadout = self:_fitLoadout(fighter, runtime.id, newDegree, runtime.loadout)
	runtime.meter = 0
	runtime.transformUntil = time + window
	model:SetAttribute(Attribute.Degree, newDegree)
	model:SetAttribute(Attribute.PhaseNumber, newDegree)
	model:SetAttribute(Attribute.Loadout, table.concat(runtime.loadout, ","))
	model:SetAttribute(Attribute.TransformUntil, runtime.transformUntil)
	self.characters:setCombatProfile(fighter, Powers.combatProfile(runtime.id, newDegree, if runtime.form ~= "" then runtime.form else nil))
	self:_applyAppearance(fighter)
	local player = fighter.player
	local held = if player then locked[player] else nil
	if held then
		held.phase = newDegree
	end
	-- Hyper-armour: the next few hits in the window do not flinch the fighter
	local state = fighter.state
	state.armorHits = math.max(state.armorHits, Selection.Phase.ArmorHits)
	state.armorUntil = math.max(state.armorUntil, runtime.transformUntil)
	local module = runtime.module
	if module and module.onPhase then
		self:_safe(module.onPhase, fighter, runtime, from, newDegree, AbilityKit.forFighter(fighter))
	end
	self:_publish(fighter, true)
	CombatEvent:FireAllClients(Protocol.CombatEvent.Transform, {
		fighter = model,
		power = runtime.id,
		from = from,
		to = newDegree,
		duration = window,
	})
	task.delay(window + 0.05, function()
		if fighter.power == runtime and runtime.transformUntil <= now() and model.Parent then
			model:SetAttribute(Attribute.TransformUntil, nil)
		end
	end)
end

-- CPUs evolve for free when their meter is full, up to a ceiling set by their difficulty
function PowerService:_cpuEvolve(fighter)
	local runtime = fighter.power
	if not runtime or runtime.meter < Selection.Phase.MeterMax or runtime.transformUntil > now() then
		return
	end
	local ceilings = Selection.Phase.CpuMaxPhase
	local difficulty = fighter.model:GetAttribute("CpuDifficulty")
	local ceiling = (typeof(difficulty) == "string" and ceilings[difficulty]) or ceilings.Default
	ceiling = math.min(math.max(ceiling, runtime.degree), Powers.degreeCount(runtime.id))
	if runtime.degree >= ceiling or not self.services.MatchService:isCombatAllowed(fighter) then
		return
	end
	self:_transform(fighter, runtime.degree + 1)
end

-- The Evolve request: the next phase, mid-fight. Checks everything first, so a refusal
-- takes nothing; then charges the fee once and transforms.
function PowerService:evolve(player: Player, junk: any)
	local function refuse(code: string, message: string)
		self:_reply(player, newResult("Evolve", false, code, message))
		toast(player, message, "error")
	end
	if junk ~= nil then
		self.antiExploit:flag(player, "junk evolve request")
		return refuse(Code.BadRequest, "That request isn't valid.")
	end
	local fighter = self.characters:getByPlayer(player)
	local runtime = fighter and fighter.power
	if not fighter or not runtime or not self.characters:isAlive(fighter) then
		return refuse(Code.NotFighting, "You can evolve during a match or in Training.")
	end
	local verdict = self:combatContext(fighter)
	local inTraining = verdict.context == Context.Training
	if not (verdict.allowed and (verdict.context == Context.Match or inTraining)) then
		return refuse(Code.NotFighting, "You can evolve during a match or in Training.")
	end
	if runtime.transformUntil > now() then
		return refuse(Code.Transforming, "You are already transforming.")
	end
	local target = runtime.degree + 1
	if target > Powers.degreeCount(runtime.id) then
		return refuse(Code.MaxPhase, "You are already in your highest phase.")
	end
	local def = runtime.def
	local owner = self:_isOwner(player)
	local free = owner or inTraining
	local degreeName = def.degrees[target].name
	if not (runtime.training or owner) and not Powers.degreeUnlocked(runtime.id, target, powerData(self:_profile(player), runtime.id)) then
		local mastery = def.degrees[target].unlock and def.degrees[target].unlock.mastery
		return refuse(Code.DegreeLocked, `{degreeName} is locked. Reach mastery level {mastery or "?"} or unlock it.`)
	end
	if def.premium and not self:owns(player, runtime.id) then
		local match = self.services.MatchService:getMatchOf(fighter)
		if not (inTraining or (match and not RANKED_MODES[match.modeName])) then
			return refuse(Code.NotOwned, premiumRefusal(def))
		end
	end
	if not inTraining and runtime.meter < Selection.Phase.MeterMax then
		return refuse(Code.MeterNotFull, "Your Phase meter is not full yet. Fight to fill it.")
	end
	local fee = if free then 0 else Selection.priceFor(runtime.id, target, def.premium ~= nil)
	if fee > 0 and self:_money(player) < fee then
		return refuse(Code.CantAfford, `{degreeName} costs {formatMoney(fee)} to evolve. You have {formatMoney(self:_money(player))}.`)
	end
	if fee > 0 and not self.services.CurrencyService:spend(player, { money = fee }, `phase:{runtime.id}/{target}`) then
		return refuse(Code.CantAfford, `{degreeName} costs {formatMoney(fee)} to evolve. You have {formatMoney(self:_money(player))}.`)
	end
	local from = runtime.degree
	local ok, err = pcall(self._transform, self, fighter, target)
	if not ok then
		warn("[Powers] evolve failed: " .. tostring(err))
		if fee > 0 then
			self.services.CurrencyService:add(player, { money = fee }, "phase refund")
		end
		return refuse(Code.BadRequest, "The transformation failed. Nothing was charged.")
	end
	local message = `Evolved into {degreeName}.`
	if fee > 0 then
		message ..= ` Paid {formatMoney(fee)}.`
	end
	self:_reply(player, newResult("Evolve", true, Code.Ok, message, {
		power = runtime.id,
		degree = target,
		from = from,
		charged = fee,
		price = fee,
	}))
end

-- Saves a loadout for a power and degree. Loadouts have no price; the number of abilities
-- must fit the player's slots (the degree's own, plus the extra slot when they have it).
function PowerService:setLoadout(player: Player, powerId: string, degree: any, list: any)
	local function reply(ok: boolean, code: string, message: string, shown: boolean)
		local extra = { power = powerId, degree = if Powers.validDegree(powerId, degree) then degree else nil }
		self:_reply(player, newResult("SetLoadout", ok, code, message, extra))
		if shown then
			toast(player, message, if ok then "success" else "error")
		end
	end
	if locked[player] then
		return reply(false, Code.InMatch, "Your power and degree are locked until the fight ends.", true)
	end
	if not Powers.validDegree(powerId, degree) then
		self.antiExploit:flag(player, "junk loadout request")
		return reply(false, Code.BadRequest, "That power doesn't exist.", false)
	end
	local ok, reason, cleaned = self:validateLoadout(player, powerId, degree, list)
	if not ok or not cleaned then
		return reply(false, Code.BadLoadout, reason or "That loadout isn't valid.", true)
	end
	self.services.DataService:update(player, function(saved)
		saved.loadouts[powerId] = saved.loadouts[powerId] or {}
		saved.loadouts[powerId][tostring(degree)] = cleaned
	end)
	local fighter = self.characters:getByPlayer(player)
	local runtime = fighter and fighter.power
	-- (A Training trial keeps its own loadout; this one applies when it ends)
	if fighter and runtime and not runtime.training and runtime.id == powerId and runtime.degree == degree then
		self:equip(fighter, powerId, degree, cleaned, { trial = runtime.trial })
	end
	reply(true, Code.Ok, "Loadout saved.", true)
	self:_sendSnapshot(player)
end

-- The loadout a player saved for a power and degree (or that degree's default). `everything`
-- treats every ability as unlocked, as in Training.
function PowerService:_savedLoadout(player: Player, powerId: string, degree: number, everything: boolean?): { string }
	local profile = self:_profile(player)
	local saved = profile and profile.loadouts and profile.loadouts[powerId]
	local list = saved and saved[tostring(degree)]
	if list then
		local ok, _, cleaned = self:validateLoadout(player, powerId, degree, list, everything)
		if ok and cleaned then
			return cleaned
		end
	end
	return Powers.defaultLoadout(powerId, degree)
end

-- What a player should be using from their saved selection: the power, degree, loadout and
-- whether it is only a trial (a premium power they don't own). A selection that no longer
-- works falls back to the default fighter; `announce` says why.
function PowerService:_resolveSelection(player: Player, announce: boolean): (string, number, { string }, boolean)
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
		if announce and profile then
			toast(player, `{reason} Using {Powers.get(Powers.Default).name} for now.`, "error")
		end
		powerId, degree, trial = Powers.Default, 1, false
	end
	return powerId, degree, self:_savedLoadout(player, powerId, degree), trial
end

function PowerService:_equipForPlayer(fighter)
	local player = fighter.player :: Player
	-- In a match: exactly what they had when it started
	local held = locked[player]
	if held then
		local trial = not self:owns(player, held.power)
		-- A new life keeps the phase evolved into earlier in the match
		local phase = held.phase or held.degree
		local loadout = if phase == held.degree then held.loadout else self:_fitLoadout(fighter, held.power, phase, held.loadout)
		self:equip(fighter, held.power, phase, loadout, { trial = trial })
		if phase ~= held.degree and fighter.power then
			fighter.power.evolved = true
		end
		return
	end
	local powerId, degree, loadout, trial = self:_resolveSelection(player, true)
	self:equip(fighter, powerId, degree, loadout, { trial = trial })
	self:_watchContext(fighter)
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
		training = opts ~= nil and (opts :: any).training == true,
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
		meter = 0,
		transformUntil = 0,
		evolved = false,
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
	model:SetAttribute(Attribute.PhaseNumber, degree)
	model:SetAttribute(Attribute.PhaseMeter, 0)
	model:SetAttribute(Attribute.TransformUntil, nil)
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
	runtime.meter = 0
	runtime.transformUntil = 0
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
	local meter = math.floor(runtime.meter)
	if force or published.meter ~= meter then
		published.meter = meter
		fighter.model:SetAttribute(Attribute.PhaseMeter, meter)
	end
	-- The next phase this player could evolve into, and what it costs (players only)
	if fighter.player then
		local nextDegree, fee = self:_nextPhase(fighter)
		local key = if nextDegree then `{nextDegree}:{fee}` else ""
		if force or published.nextKey ~= key then
			published.nextKey = key
			fighter.model:SetAttribute(Attribute.PhaseFee, if nextDegree then fee else nil)
			fighter.model:SetAttribute(Attribute.PhaseNext, if nextDegree then runtime.def.degrees[nextDegree].name else nil)
		end
	end
end

function PowerService:_tick(dt: number)
	local matchService = self.services.MatchService
	for _, fighter in self.characters:all() do
		local runtime = fighter.power
		if runtime and self.characters:isAlive(fighter) then
			local resourceDef = runtime.def.resource
			if resourceDef and resourceDef.regen and resourceDef.regen ~= 0 then
				runtime.resource = math.clamp(runtime.resource + Powers.scaledRegen(runtime.id, resourceDef.regen) * dt, 0, runtime.resourceMax)
			end
			local match = matchService:getMatchOf(fighter)
			if match and matchService:isCombatAllowed(fighter) and runtime.ultimate then
				runtime.ult = math.min(ULTIMATE.Max, runtime.ult + ULTIMATE.PassivePerSecond * dt)
			end
			if fighter.npc and not fighter.trainingDummy then
				self:_cpuEvolve(fighter)
			end
			local module = runtime.module
			if module and module.tick then
				self:_safe(module.tick, fighter, runtime, dt, AbilityKit.forFighter(fighter))
			end
			self:_publish(fighter, false)
			-- Keeps SNCombatContext current and ends a trial or an evolution when the hall is left
			if fighter.player then
				self:_watchContext(fighter)
			end
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
	if landed and opts.kind ~= "Status" then
		local phase = Selection.Phase
		if dealt > 0 then
			self:_fillMeter(attacker, phase.HitDealt)
			self:_fillMeter(target, phase.HitTaken)
		elseif outcome.result == "Blocked" or outcome.result == "GuardBreak" then
			self:_fillMeter(attacker, phase.BlockedDealt)
		end
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
