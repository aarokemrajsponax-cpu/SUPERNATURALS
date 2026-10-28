-- Interactive defense: the prompts and counters that make defending more than
-- one block key.
--   Prompt   a telegraphed attack shows "DODGE / BLOCK"; dodging or blocking
--            while it's up is a perfect read (no damage, attacker staggers)
--   Mash     a grab or crushing hold: press repeatedly (bounded) to break free
--   Timing   a massive attack or projectile: a timing bar with a small perfect
--            centre (negate + punish), a wider good zone (half damage), and failure
--   Redirect Syntax takes over an eligible incoming projectile
--   Counters a power's own stance (the Ghost's spectral counter, Strong Dude's
--            Iron Body...) answers eligible hits during its window
-- Clients only show prompts and send presses. The server measures the timing
-- itself (with a capped latency allowance) and decides every result.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local DefenseMath = require(ReplicatedStorage.Shared.Combat.DefenseMath)
local FighterState = require(ReplicatedStorage.Shared.Combat.FighterState)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DefenseEvent = Remotes:WaitForChild("DefenseEvent") :: RemoteEvent
local DefenseInput = Remotes:WaitForChild("DefenseInput") :: RemoteEvent

local Event = Protocol.DefenseEvent
local Input = Protocol.DefenseInput
local DEFENSE = Combat.Defense

local DefenseService = {}

-- How long before impact a massive projectile's timing bar appears
local TIMING_LEAD = 0.9

export type Cue = {
	id: string,
	kind: string,
	targetId: string,
	attackerId: string,
	ability: string?,
	power: string?,
	-- Projectile it belongs to, if any
	source: string?,
	opensAt: number,
	closesAt: number,
	impactAt: number,
	grade: string?,
	mash: DefenseMath.Mash?,
	label: string?,
}

export type Counter = {
	endsAt: number,
	-- Should this hit be answered by the counter?
	accepts: (attacker: any, hit: any, opts: any) -> boolean,
	-- What happens instead: { negate, result, damageScale, noFlinch }
	respond: (attacker: any, hit: any, opts: any) -> any,
}

local cues: { [string]: { [string]: Cue } } = {}
local counters: { [string]: Counter } = {}
-- callback(fighter, kind, result) whenever a defense is judged
local resultListeners: { (any, string, string) -> () } = {}

function DefenseService:onResult(callback: (any, string, string) -> ())
	table.insert(resultListeners, callback)
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function newId(): string
	return HttpService:GenerateGUID(false)
end

local function cuesOf(fighterId: string): { [string]: Cue }
	local list = cues[fighterId]
	if not list then
		list = {}
		cues[fighterId] = list
	end
	return list
end

local function isCloseRange(opts): boolean
	return opts.kind == "Light" or opts.kind == "Heavy" or opts.kind == "Ability"
end

function DefenseService:Init(services)
	self.services = services
	self.characters = services.CharacterService
	self.antiExploit = services.AntiExploitService
	-- CPU opponents answer prompts through this (set by CpuService)
	self.cpuResponder = nil :: any
end

function DefenseService:Start()
	DefenseInput.OnServerEvent:Connect(function(player, kind, cueId)
		if not self.antiExploit:allow(player, "Defense") then
			return
		end
		if typeof(kind) ~= "string" or typeof(cueId) ~= "string" or #cueId > 64 then
			return
		end
		local fighter = self.characters:getByPlayer(player)
		if not fighter then
			return
		end
		local cue = cuesOf(fighter.id)[cueId]
		if not cue then
			return
		end
		local pressAt = DefenseMath.estimatePressTime(now(), player:GetNetworkPing(), DEFENSE.LatencyCap)
		self:_press(fighter, cue, kind, pressAt)
	end)

	local function clear(fighter)
		self:clear(fighter)
	end
	self.characters:onKnockout(clear)
	self.characters:onRestored(clear)
	self.characters:onUnregistered(clear)
end

-- Sending ---------------------------------------------------------------------------

function DefenseService:_send(fighter, cue: Cue, extra: { [string]: any }?)
	local data = {
		id = cue.id,
		kind = cue.kind,
		opensAt = cue.opensAt,
		closesAt = cue.closesAt,
		impactAt = cue.impactAt,
		label = cue.label,
		perfectWindow = DEFENSE.PerfectWindow,
		goodWindow = DEFENSE.GoodWindow,
	}
	for key, value in extra or {} do
		data[key] = value
	end
	if fighter.player then
		DefenseEvent:FireClient(fighter.player, Event.Cue, data)
	elseif self.cpuResponder then
		task.spawn(self.cpuResponder, fighter, cue, data)
	end
end

function DefenseService:_result(fighter, cue: Cue, result: string)
	for _, listener in resultListeners do
		task.spawn(listener, fighter, cue.kind, result)
	end
	if fighter.player and fighter.player.Parent then
		DefenseEvent:FireClient(fighter.player, Event.Result, { id = cue.id, kind = cue.kind, result = result })
	end
end

function DefenseService:_drop(fighter, cue: Cue)
	local list = cues[fighter.id]
	if list and list[cue.id] == cue then
		list[cue.id] = nil
		if fighter.player and fighter.player.Parent then
			DefenseEvent:FireClient(fighter.player, Event.Clear, { id = cue.id })
		end
	end
end

-- Forget the cue once it can no longer matter
function DefenseService:_expireLater(fighter, cue: Cue, after: number)
	task.delay(math.max(0, cue.closesAt - now()) + after, function()
		self:_drop(fighter, cue)
	end)
end

-- Prompts ---------------------------------------------------------------------------

-- A dodge/block prompt for a telegraphed attack landing at impactAt
function DefenseService:prompt(target, attacker, info: { impactAt: number, ability: string?, power: string?, label: string? }): string
	local cue: Cue = {
		id = newId(),
		kind = "Prompt",
		targetId = target.id,
		attackerId = attacker.id,
		ability = info.ability,
		power = info.power,
		opensAt = info.impactAt - DEFENSE.PromptLead,
		closesAt = info.impactAt,
		impactAt = info.impactAt,
		label = info.label,
	}
	cuesOf(target.id)[cue.id] = cue
	self:_send(target, cue)
	self:_expireLater(target, cue, 0.6)
	return cue.id
end

-- A timing bar for a massive attack landing at impactAt
function DefenseService:timing(target, attacker, info: { impactAt: number, ability: string?, power: string?, label: string?, source: string? }): string
	local time = now()
	local cue: Cue = {
		id = newId(),
		kind = "Timing",
		targetId = target.id,
		attackerId = attacker.id,
		ability = info.ability,
		power = info.power,
		source = info.source,
		opensAt = time,
		closesAt = info.impactAt + DEFENSE.GoodWindow,
		impactAt = info.impactAt,
		label = info.label,
	}
	cuesOf(target.id)[cue.id] = cue
	self:_send(target, cue)
	self:_expireLater(target, cue, 0.8)
	return cue.id
end

-- Telegraphs an ability to everyone it threatens, with the defense its
-- definition names ("Prompt" or "Timing"). Abilities call this at cast start.
function DefenseService:telegraph(attacker, targets: { any }, def, impactAt: number)
	if def.defense ~= "Prompt" and def.defense ~= "Timing" then
		return
	end
	for _, target in targets do
		local info = { impactAt = impactAt, ability = def.id, power = def.power, label = def.name }
		if def.defense == "Timing" then
			self:timing(target, attacker, info)
		else
			self:prompt(target, attacker, info)
		end
	end
end

-- Called by ProjectileService every step for projectiles closing in on a fighter
function DefenseService:considerProjectile(fighter, projectile, timeToImpact: number)
	local spec = projectile.spec
	local cued = projectile.cued
	if spec.defense == "Timing" and not cued[fighter.id .. ":Timing"] and timeToImpact <= TIMING_LEAD then
		cued[fighter.id .. ":Timing"] = true
		self:timing(fighter, projectile.owner, {
			impactAt = now() + timeToImpact,
			ability = spec.ability,
			power = spec.power,
			label = spec.label or spec.ability,
			source = projectile.id,
		})
	end
	if
		spec.redirectable ~= false
		and not projectile.redirected
		and not cued[fighter.id .. ":Redirect"]
		and timeToImpact <= DEFENSE.RedirectWindow
		and (projectile.position - fighter.root.Position).Magnitude <= DEFENSE.RedirectRange
	then
		local powers = self.services.PowerService
		if powers and powers:readyRedirect(fighter) then
			cued[fighter.id .. ":Redirect"] = true
			local time = now()
			local cue: Cue = {
				id = projectile.id,
				kind = "Redirect",
				targetId = fighter.id,
				attackerId = projectile.ownerId,
				ability = spec.ability,
				power = spec.power,
				source = projectile.id,
				opensAt = time,
				closesAt = time + timeToImpact + 0.05,
				impactAt = time + timeToImpact,
				label = spec.label or spec.ability,
			}
			cuesOf(fighter.id)[cue.id] = cue
			self:_send(fighter, cue)
			self:_expireLater(fighter, cue, 0.3)
		end
	end
end

-- Grabs: holds the victim and lets them mash to escape. Yields until it's
-- decided and returns "Escaped" or "Held" ("Cancelled" if either side dropped out).
function DefenseService:grab(target, attacker, info: { hold: number, presses: number, ability: string?, power: string?, label: string?, holding: (() -> boolean)? }): string
	local time = now()
	local deadline = time + info.hold
	local cue: Cue = {
		id = newId(),
		kind = "Mash",
		targetId = target.id,
		attackerId = attacker.id,
		ability = info.ability,
		power = info.power,
		opensAt = time,
		closesAt = deadline,
		impactAt = deadline,
		label = info.label,
		mash = DefenseMath.newMash(info.presses, deadline, DEFENSE.MashMinInterval),
	}
	cuesOf(target.id)[cue.id] = cue
	self:_send(target, cue, { presses = info.presses })
	local result = "Held"
	while now() < deadline do
		task.wait(0.05)
		if not self.characters:isAlive(target) or not self.characters:isAlive(attacker) or (info.holding and not info.holding()) then
			result = "Cancelled"
			break
		end
		if DefenseMath.escaped(cue.mash :: DefenseMath.Mash) then
			result = "Escaped"
			break
		end
	end
	self:_drop(target, cue)
	self:_result(target, cue, if result == "Escaped" then "Escaped" else "Failed")
	return result
end

-- Presses ---------------------------------------------------------------------------

function DefenseService:_press(fighter, cue: Cue, kind: string, pressAt: number)
	if kind == Input.Mash and cue.kind == "Mash" and cue.mash then
		DefenseMath.press(cue.mash, pressAt)
	elseif kind == Input.Timing and cue.kind == "Timing" and cue.grade == nil then
		cue.grade = DefenseMath.gradeTiming(pressAt, cue.impactAt, DEFENSE.PerfectWindow, DEFENSE.GoodWindow)
	elseif kind == Input.Redirect and cue.kind == "Redirect" then
		self:_redirect(fighter, cue, pressAt)
	end
end

-- CPU opponents press through this (same rules as players)
function DefenseService:cpuPress(fighter, cueId: string, kind: string)
	local cue = cuesOf(fighter.id)[cueId]
	if cue then
		self:_press(fighter, cue, kind, now())
	end
end

function DefenseService:_redirect(fighter, cue: Cue, pressAt: number)
	if pressAt > cue.closesAt then
		return
	end
	local projectiles = self.services.ProjectileService
	local powers = self.services.PowerService
	local projectile = projectiles:get(cue.source)
	if not projectile or not projectile.alive or not powers then
		return
	end
	local ability = powers:readyRedirect(fighter)
	if not ability then
		return
	end
	-- It has to still be close, and not be an exceptionally powerful projectile
	if (projectile.position - fighter.root.Position).Magnitude > DEFENSE.RedirectRange or projectile.spec.redirectable == false then
		return
	end
	local original = self.characters:getById(cue.attackerId)
	local aimAt = if original and self.characters:isAlive(original) then original.root.Position else nil
	local direction = if aimAt then (aimAt - projectile.position) else -projectile.velocity
	if projectiles:redirect(projectile, fighter, direction) then
		self:_drop(fighter, cue)
		powers:commitRedirect(fighter, ability)
		self:_result(fighter, cue, "Countered")
	end
end

-- Waiting for a press in flight ---------------------------------------------------------
-- A press made right on time can still be travelling over the network when the
-- attack lands. Timing hits wait (at most LatencyCap) for it before they're judged.

local function pendingTiming(list, matches: (Cue) -> boolean): Cue?
	if not list then
		return nil
	end
	for _, cue in list do
		if cue.kind == "Timing" and cue.grade == nil and matches(cue) then
			return cue
		end
	end
	return nil
end

-- For ability hits (may yield): returns once the target's timing cue for this
-- attack is graded or the grace period is over
function DefenseService:awaitTiming(target, attacker, abilityId: string?)
	local cue = pendingTiming(cues[target.id], function(candidate)
		return candidate.source == nil and candidate.attackerId == attacker.id and candidate.ability == abilityId
	end)
	if not cue then
		return
	end
	local deadline = cue.impactAt + DEFENSE.LatencyCap
	while cue.grade == nil and now() < deadline and cues[target.id] and cues[target.id][cue.id] == cue do
		task.wait(0.02)
	end
end

-- For projectiles (can't yield): should this projectile pause just short of
-- the target this step, because their timing press may still be on its way?
function DefenseService:holdProjectile(target, projectile): boolean
	local cue = pendingTiming(cues[target.id], function(candidate)
		return candidate.source == projectile.id
	end)
	return cue ~= nil and now() < cue.impactAt + DEFENSE.LatencyCap
end

-- Counters ----------------------------------------------------------------------------

function DefenseService:openCounter(fighter, counter: Counter)
	counters[fighter.id] = counter
end

function DefenseService:closeCounter(fighter, counter: Counter?)
	if counter == nil or counters[fighter.id] == counter then
		counters[fighter.id] = nil
	end
end

function DefenseService:hasCounter(fighter): boolean
	local counter = counters[fighter.id]
	return counter ~= nil and now() < counter.endsAt
end

-- Judging a hit ---------------------------------------------------------------------

-- Called by CombatService:applyHit before anything lands. Returns nil (no
-- change) or a verdict { negate, result, damageScale, noFlinch }.
function DefenseService:intercept(attacker, target, hit, opts)
	local time = now()

	-- 1. The target's own counter stance
	local counter = counters[target.id]
	if counter and time < counter.endsAt and counter.accepts(attacker, hit, opts) then
		counters[target.id] = nil
		local verdict = counter.respond(attacker, hit, opts)
		if verdict then
			return verdict
		end
	end

	local list = cues[target.id]
	if not list then
		return nil
	end

	-- 2. A timing bar or prompt that belongs to this hit
	for _, cue in table.clone(list) do
		local matches = (opts.cueId ~= nil and cue.id == opts.cueId)
			or (opts.projectile ~= nil and cue.source == opts.projectile.id)
			or (
				cue.source == nil
				and cue.attackerId == attacker.id
				and cue.ability ~= nil
				and cue.ability == opts.ability
				and math.abs(time - cue.impactAt) <= 0.75
			)
		if matches and cue.kind == "Timing" then
			self:_drop(target, cue)
			local grade = cue.grade or "Failed"
			self:_result(target, cue, grade)
			if grade == "Perfect" then
				if isCloseRange(opts) then
					FighterState.applyStun(attacker.state, DEFENSE.TimingPunish, time)
				end
				return { negate = true, result = "Perfect" }
			elseif grade == "Good" then
				return { damageScale = DEFENSE.GoodDamage, noFlinch = true, result = "Good" }
			end
			return nil
		elseif matches and cue.kind == "Prompt" then
			self:_drop(target, cue)
			local state = target.state
			local config = target.combat
			-- Directional dodges have different invulnerable times, so use when the dodge began
			local dodgedAt = if time < state.invulnerableUntil and state.dodgeStartedAt then state.dodgeStartedAt else nil
			local blockedAt = state.blockingSince
			local allowance = DEFENSE.LatencyCap
			if DefenseMath.inPromptWindow(dodgedAt, cue.opensAt, cue.closesAt, allowance) then
				-- The dodge already makes them untouchable; this just celebrates the read
				self:_result(target, cue, "Perfect")
				return nil
			elseif blockedAt and DefenseMath.inPromptWindow(blockedAt, cue.opensAt, cue.closesAt, allowance) and hit.Blockable ~= false then
				self:_result(target, cue, "Perfect")
				if isCloseRange(opts) then
					FighterState.applyStun(attacker.state, DEFENSE.PerfectStun, time)
				end
				return { negate = true, result = "PerfectBlock" }
			end
			self:_result(target, cue, "Failed")
			return nil
		end
	end
	return nil
end

-- Cleanup -------------------------------------------------------------------------------

function DefenseService:clear(fighter)
	counters[fighter.id] = nil
	local list = cues[fighter.id]
	if list then
		for _, cue in table.clone(list) do
			self:_drop(fighter, cue)
		end
		cues[fighter.id] = nil
	end
end

-- Players leaving take their cue tables with them
Players.PlayerRemoving:Connect(function(player)
	cues["Player:" .. player.UserId] = nil
	counters["Player:" .. player.UserId] = nil
end)

return DefenseService
