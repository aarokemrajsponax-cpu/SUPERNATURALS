-- The owner's event control: the secure remote API behind the Control Center screens, wired
-- to one Overlord core (this server's events) and one Cluster (all servers).
--
-- REMOTE API  (Remotes.OverlordRequest:FireServer(requestId, action, payload))
--   The answer arrives on Remotes.OverlordEvent as ("Result", requestId, result) with
--   result = { ok = boolean, code = string?, message = string?, data = any? }.
--   After every change the owner also gets ("State", state). Everything is owner-only,
--   checked here by UserId, whatever the client shows. Actions (Protocol.OverlordAction):
--     Catalogue         -> data = { categories, presets, effects, costCap }
--     State             -> data = { jobId, eventMode, active = { {id, preset, name, startedAt, endsAt, origin} }, lastSync, syncOk }
--     Servers           -> data = { { jobId, players, presets, events, lastSync, heartbeat, test, current } }
--     Activate          payload { entries = { { preset = id, overrides = { duration?, intensity?, color? } } },
--                                 scope = Scope, eventMode = boolean? }
--                       -> data = { id, applied, sync = { published, stored }, receivedBy = { jobId } }
--     Preview           payload { preset, seconds? (5-30) }  this server only
--     Stop              payload { target = event or command id, scope }
--     StopAll / RestoreEnvironment / ClearEffects / RestorePlayers / ReturnToDefault   payload { scope }
--     ListCombos / SaveCombo { id, name, entries } / DeleteCombo { id }
--     Audit             payload { limit? } -> data = { entries }
--     Summon            payload { jobId } -> teleports the owner to a registered server
--   Scope = { k = "here" } | { k = "all" } | { k = "test" } | { k = "jobs", j = { jobId, ... } }
--   Codes on refusal: not_owner, bad_request, bad_scope, rate_limited, unknown_preset,
--   event_mode_required, match_in_progress, incompatible_tags:<a>:<b>, channel_conflict:<channel>:<preset>,
--   entries_conflict:<channel>, performance_cap, bad_params:<why>, global_sync_failed, payload_too_large.
--   A global command whose sync failed everywhere is reported as NOT ok (code global_sync_failed);
--   it may still be running on this server. Use Servers + receivedBy to see which servers have it.

local Lighting = game:GetService("Lighting")
local MessagingService = game:GetService("MessagingService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local EventPresets = require(ReplicatedStorage.Shared.Config.EventPresets)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Cluster = require(script.Parent.Parent.Events.Cluster)
local Overlord = require(script.Parent.Parent.Events.Overlord)
local Registry = require(script.Parent.Parent.Events.Registry)

local Action = Protocol.OverlordAction
local Signal = Protocol.OverlordSignal

local OverlordService = {}

local MAX_COMBOS = 50

local function wallClock(): number
	return os.time()
end

local function randomId(): string
	return string.format("%x%08x%08x", math.floor(wallClock()), math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
end

function OverlordService:Init(services)
	self.services = services
	self.owner = services.OwnerService
	self.characters = services.CharacterService
	self.antiExploit = services.AntiExploitService
	self.events = services.AdminEventService
end

-- Builds the real dependencies. Tests call buildCore/buildCluster with fakes instead.
function OverlordService:_realDeps()
	local fxRoot = ReplicatedStorage:FindFirstChild("OverlordFx")
	if not fxRoot then
		fxRoot = Instance.new("Folder")
		fxRoot.Name = "OverlordFx"
		fxRoot.Parent = ReplicatedStorage
	end
	local worldRoot = workspace:FindFirstChild("OverlordWorld")
	if not worldRoot then
		worldRoot = Instance.new("Folder")
		worldRoot.Name = "OverlordWorld"
		worldRoot.Parent = workspace
	end
	local owner = self.owner
	local characters = self.characters
	local matches = self.services.MatchService
	local function inMatch(player)
		local fighter = characters:getByPlayer(player)
		return fighter ~= nil and matches:getMatchOf(fighter) ~= nil
	end
	return {
		lighting = Lighting,
		workspace = workspace,
		replicated = ReplicatedStorage,
		fxRoot = fxRoot,
		worldRoot = worldRoot,
		players = function()
			local list = {}
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("EventOptOut") ~= true then
					table.insert(list, player)
				end
			end
			return list
		end,
		owners = function()
			local list = {}
			for _, player in Players:GetPlayers() do
				if owner:isOwner(player) then
					table.insert(list, player)
				end
			end
			return list
		end,
		inMatch = inMatch,
		matchActive = function()
			for _, player in Players:GetPlayers() do
				if inMatch(player) then
					return true
				end
			end
			return false
		end,
		center = function()
			return self.events:_centerFor(nil)
		end,
		onCharacter = function(callback)
			local connections = {}
			local function watch(player)
				table.insert(connections, player.CharacterAdded:Connect(function()
					task.defer(callback, player)
				end))
			end
			for _, player in Players:GetPlayers() do
				watch(player)
			end
			table.insert(connections, Players.PlayerAdded:Connect(watch))
			return {
				Disconnect = function()
					for _, connection in connections do
						connection:Disconnect()
					end
				end,
			}
		end,
		clock = wallClock,
		jobId = if game.JobId ~= "" then game.JobId else "studio-" .. randomId(),
	}
end

function OverlordService:Start()
	local deps = self:_realDeps()
	self:setup(deps, {
		messaging = MessagingService,
		memory = MemoryStoreService,
		auditStore = DataStoreService:GetDataStore("OverlordAudit"),
		comboStore = DataStoreService:GetDataStore("OverlordCombos"),
		teleport = TeleportService,
		wait = task.wait,
		isTest = game.PrivateServerId ~= "",
		randomId = randomId,
	})
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	self.request = Remotes:WaitForChild("OverlordRequest")
	self.signal = Remotes:WaitForChild("OverlordEvent")
	self.request.OnServerEvent:Connect(function(player, requestId, action, payload)
		if typeof(requestId) ~= "number" or typeof(action) ~= "string" then
			return
		end
		if not self.antiExploit:allow(player, "Admin") then
			return
		end
		if not self.owner:isOwner(player) then
			self.antiExploit:flag(player, "tried to use the event control")
			self.signal:FireClient(player, Signal.Result, requestId, { ok = false, code = "not_owner", message = Overlord.explain("not_owner") })
			return
		end
		local result = self:handle(player, action, payload)
		self.signal:FireClient(player, Signal.Result, requestId, result)
		if result.ok then
			self.signal:FireClient(player, Signal.State, self:_state())
		end
	end)
	task.spawn(function()
		self.cluster:Start()
		while self.running do
			task.wait(1)
			local ok, err = pcall(self.cluster.tick, self.cluster)
			if not ok then
				warn(`[Overlord] tick failed: {err}`)
			end
		end
	end)
	pcall(function()
		game:BindToClose(function()
			self.running = false
			self.cluster:Stop()
			self.core:returnToDefault()
		end)
	end)
end

-- Creates the core and cluster from dependencies (also used by tests)
function OverlordService:setup(deps, cloud)
	self.running = true
	self.deps = deps
	local owner = self.owner
	self.core = Overlord.new(deps)
	self.cluster = Cluster.new(self.core, {
		messaging = cloud.messaging,
		memory = cloud.memory,
		auditStore = cloud.auditStore,
		clock = deps.clock,
		wait = cloud.wait,
		jobId = deps.jobId,
		isTest = cloud.isTest,
		isOwnerId = function(userId)
			return owner:isOwnerId(userId)
		end,
		playerCount = function()
			return #Players:GetPlayers()
		end,
		randomId = cloud.randomId,
	})
	self.comboStore = cloud.comboStore
	self.teleport = cloud.teleport
end

local function fail(code: string)
	return { ok = false, code = code, message = Overlord.explain(code) }
end

local function succeed(data: any)
	return { ok = true, data = data }
end

function OverlordService:_state()
	return {
		jobId = self.deps.jobId,
		eventMode = self.core.eventMode,
		active = self.core:list(),
		lastSync = self.cluster.lastSync,
		syncOk = self.cluster.syncOk,
	}
end

local function summarize(preset)
	local effects = {}
	for _, spec in preset.effects do
		table.insert(effects, spec.effect)
	end
	return { id = preset.id, name = preset.name, category = preset.category, level = preset.level, description = preset.description, duration = preset.duration, tags = preset.tags, effects = effects, eventMode = preset.eventMode, ownerOnly = preset.ownerOnly, onConflict = preset.onConflict }
end

function OverlordService:_catalogue()
	local presets = {}
	for _, preset in EventPresets.List do
		table.insert(presets, summarize(preset))
	end
	local effects = {}
	for id, effect in Registry.effects do
		local channels = effect.channels
		effects[id] = { params = effect.params, group = effect.group, gameplay = effect.gameplay, ownerOnly = effect.ownerOnly, channels = if type(channels) == "table" then channels else nil }
	end
	return { categories = EventPresets.Categories, presets = presets, effects = effects, costCap = Overlord.COST_CAP }
end

local function cleanName(name: any): string?
	if type(name) ~= "string" or #name < 1 or #name > 40 or string.find(name, "[^%w %-'%.]") then
		return nil
	end
	return name
end

function OverlordService:_combos(): { any }
	if not self.comboStore then
		return {}
	end
	local ok, value = pcall(function()
		return self.comboStore:GetAsync("owner")
	end)
	return if ok and type(value) == "table" then value else {}
end

-- Checks every entry names a real preset (the activation validates parameters again)
function OverlordService:_entriesOk(entries: any): boolean
	if type(entries) ~= "table" or #entries < 1 or #entries > Overlord.MAX_ENTRIES then
		return false
	end
	for _, entry in entries do
		if type(entry) ~= "table" or type(entry.preset) ~= "string" or EventPresets.ById[entry.preset] == nil then
			return false
		end
	end
	return true
end

-- Runs one request for `player`. Returns the result table; never throws.
function OverlordService:handle(player: Player, action: string, payload: any)
	if not self.owner:isOwner(player) then
		return fail("not_owner")
	end
	if payload ~= nil and type(payload) ~= "table" then
		return fail("bad_request")
	end
	payload = payload or {}
	local actor = { userId = player.UserId, isOwner = true }
	local cluster = self.cluster

	if action == Action.Catalogue then
		return succeed(self:_catalogue())
	elseif action == Action.State then
		return succeed(self:_state())
	elseif action == Action.Servers then
		return succeed(cluster:servers())
	elseif action == Action.Audit then
		local limit = if type(payload.limit) == "number" then payload.limit else 50
		return succeed({ entries = cluster.audit:read(limit) })
	elseif action == Action.Activate then
		local result = cluster:issue(actor, "activate", { entries = payload.entries, eventMode = payload.eventMode }, payload.scope)
		if not result.ok then
			return { ok = false, code = result.code, message = Overlord.explain(result.code or ""), data = { id = result.id } }
		end
		return succeed({ id = result.id, applied = result.applied, sync = result.sync, degraded = result.degraded, receivedBy = if payload.scope and payload.scope.k ~= "here" then cluster:receivedBy(result.id) else nil })
	elseif action == Action.Preview then
		local seconds = if type(payload.seconds) == "number" then math.clamp(payload.seconds, 5, 30) else 15
		if type(payload.preset) ~= "string" then
			return fail("bad_request")
		end
		local result = cluster:issue(actor, "activate", { entries = { { preset = payload.preset, overrides = { duration = math.floor(seconds) } } }, eventMode = payload.eventMode }, { k = "here" })
		if not result.ok then
			return fail(result.code or "bad_request")
		end
		return succeed({ id = result.id, seconds = seconds })
	elseif action == Action.Stop then
		local result = cluster:issue(actor, "stop", { target = payload.target }, payload.scope)
		return if result.ok then succeed(result) else fail(result.code or "bad_request")
	elseif action == Action.StopAll or action == Action.RestoreEnvironment or action == Action.ClearEffects or action == Action.RestorePlayers or action == Action.ReturnToDefault then
		local wire = string.lower(string.sub(action, 1, 1)) .. string.sub(action, 2)
		local result = cluster:issue(actor, wire, {}, payload.scope)
		return if result.ok then succeed(result) else fail(result.code or "bad_request")
	elseif action == Action.ListCombos then
		return succeed(self:_combos())
	elseif action == Action.SaveCombo then
		local id = payload.id
		if type(id) ~= "string" or #id < 3 or #id > 32 or string.find(id, "[^%w_%-]") or cleanName(payload.name) == nil or not self:_entriesOk(payload.entries) then
			return fail("bad_request")
		end
		local combos = self:_combos()
		local replaced = false
		for index, combo in combos do
			if combo.id == id then
				combos[index] = { id = id, name = payload.name, entries = payload.entries }
				replaced = true
			end
		end
		if not replaced then
			if #combos >= MAX_COMBOS then
				return fail("bad_request")
			end
			table.insert(combos, { id = id, name = payload.name, entries = payload.entries })
		end
		local ok = pcall(function()
			self.comboStore:SetAsync("owner", combos)
		end)
		cluster.audit:record({ by = player.UserId, action = "SaveCombo", scope = "owner", presets = {}, outcome = if ok then "ok" else "failed", id = id })
		return if ok then succeed(combos) else fail("store_failed")
	elseif action == Action.DeleteCombo then
		local combos = self:_combos()
		for index, combo in combos do
			if combo.id == payload.id then
				table.remove(combos, index)
				break
			end
		end
		local ok = pcall(function()
			self.comboStore:SetAsync("owner", combos)
		end)
		cluster.audit:record({ by = player.UserId, action = "DeleteCombo", scope = "owner", presets = {}, outcome = if ok then "ok" else "failed", id = tostring(payload.id) })
		return if ok then succeed(combos) else fail("store_failed")
	elseif action == Action.Summon then
		local target = payload.jobId
		local known = false
		for _, server in cluster:servers() do
			if server.jobId == target then
				known = true
			end
		end
		if type(target) ~= "string" or not known then
			return fail("unknown_server")
		end
		local ok = self.teleport ~= nil and pcall(function()
			self.teleport:TeleportToPlaceInstance(game.PlaceId, target, player)
		end)
		cluster.audit:record({ by = player.UserId, action = "Summon", scope = "servers:" .. target, presets = {}, outcome = if ok then "ok" else "failed", id = target })
		return if ok then succeed({ jobId = target }) else fail("teleport_failed")
	end
	return fail("bad_request")
end

return OverlordService
