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
--     Announce          payload { text (1-160 chars), style = "banner"|"toast", seconds? (3-15, default 6), scope }
--                       Filtered with TextService (refused with filter_failed when it cannot be, nothing sent),
--                       at most 1 per 10 s. Every targeted server fires every client
--                       Remotes.OverlordEvent ("Announce", { text, style, seconds }).
--                       -> data = { text (filtered), style, seconds, sync, receivedBy? }
--     ScheduleAdd       payload { at (unix seconds, now+60 .. now+30 days), label (1-40, filtered),
--                                 entries (as Activate) | combo = saved combo id, scope, eventMode? }
--                       Validated like Activate (unknown preset, conflicts, cost cap) -> data = { id }
--     ScheduleList      -> data = { items = { { id, at, label, scope, status = "pending"|"done"|"missed"|"cancelled", ranAt?, ranBy? } } }
--     ScheduleCancel    payload { id } (pending items only)
--                       Every server checks every 30 s; one server claims each due item (MemoryStore claim) and
--                       runs it exactly as Activate with the stored scope ("here" = the claiming server). An item
--                       more than 10 minutes late that nobody ran, or whose run was refused, becomes "missed".
--     CustomSave        payload { id? (custom_..., to replace), name (1-40), description? (0-140), duration? (10-21600, default 300),
--                                 effects = { { effect, params } } (1-6) }  -> data = { id, items }
--                       Same rules as a preset (effect allowlist, parameter ranges refused when out of range,
--                       one effect per channel, cost cap). Name, description and text parameters pass the filter.
--     CustomList        -> data = { items = { { id, name, description, duration, level, effects } } }
--     CustomDelete      payload { id } -> data = { items }
--                       Customs appear in Catalogue under category "Custom" (id "custom_<short id>") and are accepted
--                       wherever a preset id is (Activate, Preview, ScheduleAdd, SaveCombo). Catalogue.effects[name] =
--                       { name, description, params = { [param] = { type, min?, max?, options?, default, maxLen?, scales? } }, group, gameplay, ownerOnly, channels? }
--   Scope = { k = "here" } | { k = "all" } | { k = "test" } | { k = "jobs", j = { jobId, ... } }
--   Codes on refusal: not_owner, bad_request, bad_scope, rate_limited, unknown_preset,
--   event_mode_required, match_in_progress, incompatible_tags:<a>:<b>, channel_conflict:<channel>:<preset>,
--   entries_conflict:<channel>, performance_cap, bad_params:<why>, global_sync_failed, payload_too_large,
--   filter_failed, text_filtered, bad_time, schedule_full, unknown_item, not_pending, custom_limit, too_many_effects, unknown_effect.
--   A global command whose sync failed everywhere is reported as NOT ok (code global_sync_failed);
--   it may still be running on this server. Use Servers + receivedBy to see which servers have it.

local Lighting = game:GetService("Lighting")
local MessagingService = game:GetService("MessagingService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TextService = game:GetService("TextService")

local EventPresets = require(ReplicatedStorage.Shared.Config.EventPresets)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Cluster = require(script.Parent.Parent.Events.Cluster)
local Overlord = require(script.Parent.Parent.Events.Overlord)
local Params = require(script.Parent.Parent.Events.Params)
local Registry = require(script.Parent.Parent.Events.Registry)

local Action = Protocol.OverlordAction
local Signal = Protocol.OverlordSignal

local OverlordService = {}

local MAX_COMBOS = 50
local MAX_CUSTOMS = 50
local MAX_SCHEDULE = 100
local ANNOUNCE_GAP = 10 -- seconds between announcements
local SCHEDULE_CHECK = 30
local SCHEDULE_LATE = 600 -- a pending item this late is "missed"
local SCHEDULE_MIN = 60
local SCHEDULE_MAX = 30 * 86400
local CLAIM_SECONDS = 1800
local CUSTOMS_REFRESH = 300

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
		customStore = DataStoreService:GetDataStore("OverlordCustoms"),
		scheduleStore = DataStoreService:GetDataStore("OverlordSchedule"),
		textService = TextService,
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
		while self.running do
			task.wait(1)
			local ok, err = pcall(self._housekeeping, self)
			if not ok then
				warn(`[Overlord] schedule check failed: {err}`)
			end
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
	-- The preset book: the shipped catalogue plus the owner's saved customs (rebuilt in place,
	-- so the core's reference stays valid)
	self.book = { Categories = {}, List = {}, ById = {} }
	deps.presets = self.book
	self:_applyCustoms({})
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
		announce = function(text, style, seconds)
			self:_deliverAnnounce(text, style, seconds)
		end,
		reloadCustoms = function()
			self:_loadCustoms()
		end,
	})
	self.comboStore = cloud.comboStore
	self.customStore = cloud.customStore
	self.scheduleStore = cloud.scheduleStore
	self.textService = cloud.textService
	self.memory = cloud.memory
	self.randomIdFn = cloud.randomId
	self.teleport = cloud.teleport
	self.lastAnnounce = {} :: { [number]: number }
	self.lastScheduleCheck = 0
	self.lastCustomsLoad = deps.clock()
	self:_loadCustoms()
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

local function describeParams(schema)
	local out = {}
	for name, spec in schema do
		out[name] = { type = spec.type, min = spec.min, max = spec.max, default = spec.default, options = spec.values, maxLen = spec.maxLen, scales = spec.scales }
	end
	return out
end

function OverlordService:_catalogue()
	local presets = {}
	for _, preset in self.book.List do
		table.insert(presets, summarize(preset))
	end
	local effects = {}
	for id, effect in Registry.effects do
		local channels = effect.channels
		effects[id] = { name = id, description = Registry.describe(id), params = describeParams(effect.params), group = effect.group, gameplay = effect.gameplay, ownerOnly = effect.ownerOnly, channels = if type(channels) == "table" then channels else nil }
	end
	return { categories = self.book.Categories, presets = presets, effects = effects, costCap = Overlord.COST_CAP }
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
		if type(entry) ~= "table" or type(entry.preset) ~= "string" or self.book.ById[entry.preset] == nil then
			return false
		end
	end
	return true
end

-- Custom events, announcements and the scheduler ---------------------------------------------

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = copy(v)
	end
	return out
end

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Trimmed text of 1..maxLen characters without control characters, or nil
local function cleanText(text: any, minLen: number, maxLen: number): string?
	if type(text) ~= "string" then
		return nil
	end
	text = string.match(text, "^%s*(.-)%s*$") :: string
	local length = utf8.len(text)
	if length == nil or length < minLen or length > maxLen or string.find(text, "%c") then
		return nil
	end
	return text
end

-- Filters owner-written text for every player. Returns nil when the filter cannot be used.
function OverlordService:_filter(text: string, userId: number): string?
	local service = self.textService
	if not service then
		return nil
	end
	local ok, result = pcall(function()
		local filtered = service:FilterStringAsync(text, userId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" then
		return result
	end
	return nil
end

-- Reads a list kept under key "owner" of a DataStore
function OverlordService:_readList(store: any): { any }?
	if not store then
		return nil
	end
	local ok, value = pcall(function()
		return store:GetAsync("owner")
	end)
	if not ok then
		return nil
	end
	return if type(value) == "table" then value else {}
end

-- Changes a stored list atomically. change(list) returns an error code to cancel the write,
-- or nil to save the (mutated) list. Returns the saved list or nil, code.
function OverlordService:_updateList(store: any, change: (list: { any }) -> string?): ({ any }?, string?)
	if not store then
		return nil, "store_failed"
	end
	local code: string? = nil
	local ok, saved = pcall(function()
		return store:UpdateAsync("owner", function(old)
			code = nil
			local list = if type(old) == "table" then old else {}
			code = change(list)
			if code then
				return nil
			end
			return list
		end)
	end)
	if not ok then
		return nil, "store_failed"
	end
	if code then
		return nil, code
	end
	if type(saved) ~= "table" then
		return nil, "store_failed"
	end
	return saved, nil
end

function OverlordService:_shortId(prefix: string, taken: { any }): string
	for _ = 1, 20 do
		local raw = string.gsub(tostring((self.randomIdFn or randomId)()), "[^%w]", "")
		local id = prefix .. string.sub(raw, -10)
		local free = true
		for _, item in taken do
			if item.id == id then
				free = false
			end
		end
		if free then
			return id
		end
	end
	return prefix .. string.format("%x", math.random(0, 0x7fffffff))
end

-- Announcements -------------------------------------------------------------------------------

function OverlordService:_deliverAnnounce(text: string, style: string, seconds: number)
	if self.signal then
		self.signal:FireAllClients(Signal.Announce, { text = text, style = style, seconds = seconds })
	end
end

function OverlordService:_announce(actor: any, payload: any)
	local text = cleanText(payload.text, 1, 160)
	if text == nil or (payload.style ~= "banner" and payload.style ~= "toast") then
		return fail("bad_request")
	end
	local seconds = 6
	if payload.seconds ~= nil then
		if not isFinite(payload.seconds) then
			return fail("bad_request")
		end
		seconds = math.clamp(payload.seconds, 3, 15)
	end
	if not Cluster.validScope(payload.scope) then
		return fail("bad_scope")
	end
	local now = self.deps.clock()
	local last = self.lastAnnounce[actor.userId]
	if last and now - last < ANNOUNCE_GAP then
		return fail("rate_limited")
	end
	self.lastAnnounce[actor.userId] = now
	local filtered = self:_filter(text, actor.userId)
	if filtered == nil then
		return fail("filter_failed")
	end
	filtered = cleanText(filtered, 1, 160) :: string?
	if filtered == nil then
		return fail("text_filtered")
	end
	local result = self.cluster:issue(actor, "announce", { text = filtered, style = payload.style, seconds = seconds }, payload.scope)
	if not result.ok then
		return fail(result.code or "bad_request")
	end
	return succeed({ text = filtered, style = payload.style, seconds = seconds, id = result.id, sync = result.sync, receivedBy = nil })
end

-- Custom events -------------------------------------------------------------------------------

-- Rebuilds the preset book from the shipped catalogue plus `customs` (stored items)
function OverlordService:_applyCustoms(customs: { any })
	local book = self.book
	table.clear(book.Categories)
	table.clear(book.List)
	table.clear(book.ById)
	for _, category in EventPresets.Categories do
		table.insert(book.Categories, category)
	end
	table.insert(book.Categories, { id = "Custom", name = "Custom events" })
	for _, preset in EventPresets.List do
		table.insert(book.List, preset)
		book.ById[preset.id] = preset
	end
	self.customItems = customs
	for _, item in customs do
		local effects, gameplay = {}, false
		local valid = type(item.id) == "string" and string.find(item.id, "^custom_[%w]+$") ~= nil and type(item.effects) == "table" and #item.effects >= 1
		if valid then
			for _, spec in item.effects do
				local effect = type(spec) == "table" and Registry.effects[spec.effect]
				if not effect then
					valid = false
					break
				end
				gameplay = gameplay or effect.gameplay == true
				table.insert(effects, { effect = spec.effect, params = spec.params or {} })
			end
		end
		if valid and book.ById[item.id] == nil then
			local preset = {
				id = item.id,
				name = item.name,
				category = "Custom",
				level = item.level or 1,
				description = item.description or "",
				duration = item.duration or 300,
				tags = {},
				excludes = {},
				effects = effects,
				onConflict = "reject",
				ownerOnly = false,
				eventMode = gameplay,
			}
			table.insert(book.List, preset)
			book.ById[item.id] = preset
		end
	end
end

function OverlordService:_loadCustoms(): boolean
	self.lastCustomsLoad = self.deps.clock()
	local list = self:_readList(self.customStore)
	if list == nil then
		return false
	end
	self:_applyCustoms(list)
	return true
end

-- Validates a CustomSave payload with the preset rules. Returns a stored item or nil, code.
function OverlordService:_validateCustom(actor: any, payload: any, id: string): (any?, string?)
	local name = cleanName(payload.name)
	if name == nil then
		return nil, "bad_request"
	end
	local description = ""
	if payload.description ~= nil and payload.description ~= "" then
		local text = cleanText(payload.description, 0, 140)
		if text == nil then
			return nil, "bad_request"
		end
		description = text
	end
	local duration = 300
	if payload.duration ~= nil then
		if not isFinite(payload.duration) then
			return nil, "bad_request"
		end
		duration = math.floor(math.clamp(payload.duration, 10, 21600))
	end
	local specs = payload.effects
	if type(specs) ~= "table" or #specs < 1 or #specs > 6 then
		return nil, "too_many_effects"
	end
	local draft = {}
	for index, spec in specs do
		if type(index) ~= "number" or type(spec) ~= "table" or type(spec.effect) ~= "string" then
			return nil, "bad_request"
		end
		if Registry.effects[spec.effect] == nil then
			return nil, "unknown_effect"
		end
		if spec.params ~= nil and type(spec.params) ~= "table" then
			return nil, "bad_request"
		end
		table.insert(draft, { effect = spec.effect, params = spec.params or {} })
	end
	-- The same checks a preset gets: allowlist, parameter rules, channels, cost
	local plan, code = self.core:planPreset(actor, { id = id, ownerOnly = false, duration = duration, effects = draft }, nil)
	if not plan then
		return nil, code
	end
	local claimed = {}
	for _, effect in plan.effects do
		for _, channel in effect.channels do
			if claimed[channel] then
				return nil, `entries_conflict:{channel}`
			end
			claimed[channel] = true
		end
	end
	if plan.cost > (self.deps.costCap or Overlord.COST_CAP) then
		return nil, "performance_cap"
	end
	-- Everything players read passes the text filter
	local stored, gameplay = {}, false
	for index, effect in plan.effects do
		gameplay = gameplay or effect.module.gameplay == true
		for paramName, spec in effect.module.params do
			if spec.type == "string" then
				local value = effect.params[paramName]
				local filtered = if value == "" then "" else self:_filter(value, actor.userId)
				if filtered == nil then
					return nil, "filter_failed"
				elseif filtered ~= value then
					return nil, "text_filtered"
				end
			end
		end
		table.insert(stored, { effect = draft[index].effect, params = copy(effect.params) })
	end
	local filteredName = self:_filter(name, actor.userId)
	if filteredName == nil then
		return nil, "filter_failed"
	end
	local filteredDescription = if description == "" then "" else self:_filter(description, actor.userId)
	if filteredDescription == nil then
		return nil, "filter_failed"
	end
	if cleanText(filteredName, 1, 40) == nil then
		return nil, "text_filtered"
	end
	return { id = id, name = filteredName, description = filteredDescription, duration = duration, level = math.min(4, #stored), effects = stored }, nil
end

function OverlordService:_customSave(actor: any, payload: any)
	local list = self:_readList(self.customStore)
	if list == nil then
		return fail("store_failed")
	end
	local id = payload.id
	if id ~= nil then
		if type(id) ~= "string" or #id > 32 or string.find(id, "^custom_[%w]+$") == nil then
			return fail("bad_request")
		end
	else
		id = self:_shortId("custom_", list)
	end
	local item, code = self:_validateCustom(actor, payload, id)
	if not item then
		return fail(code or "bad_request")
	end
	local replaced = payload.id ~= nil
	local saved, why = self:_updateList(self.customStore, function(stored)
		for index, existing in stored do
			if existing.id == id then
				if not replaced then
					return "store_failed"
				end
				stored[index] = item
				return nil
			end
		end
		if replaced then
			return "unknown_preset"
		end
		if #stored >= MAX_CUSTOMS then
			return "custom_limit"
		end
		table.insert(stored, item)
		return nil
	end)
	self.cluster.audit:record({ by = actor.userId, action = "CustomSave", scope = "owner", presets = {}, outcome = if saved then "ok" else "refused", reason = why, id = id })
	if not saved then
		return fail(why or "store_failed")
	end
	self:_applyCustoms(saved)
	self.cluster:issue(actor, "customs", {}, { k = "all" })
	return succeed({ id = id, items = saved })
end

function OverlordService:_customDelete(actor: any, payload: any)
	local id = payload.id
	if type(id) ~= "string" or #id > 32 or string.find(id, "^custom_[%w]+$") == nil then
		return fail("bad_request")
	end
	local saved, why = self:_updateList(self.customStore, function(stored)
		for index, existing in stored do
			if existing.id == id then
				table.remove(stored, index)
				return nil
			end
		end
		return "unknown_item"
	end)
	self.cluster.audit:record({ by = actor.userId, action = "CustomDelete", scope = "owner", presets = {}, outcome = if saved then "ok" else "refused", reason = why, id = id })
	if not saved then
		return fail(why or "store_failed")
	end
	self:_applyCustoms(saved)
	self.cluster:issue(actor, "customs", {}, { k = "all" })
	return succeed({ items = saved })
end

-- The scheduler ---------------------------------------------------------------------------------

local FINISHED = { done = true, missed = true, cancelled = true }

function OverlordService:_scheduleAdd(actor: any, payload: any)
	local now = self.deps.clock()
	if not isFinite(payload.at) or payload.at < now + SCHEDULE_MIN or payload.at > now + SCHEDULE_MAX then
		return fail("bad_time")
	end
	local at = math.floor(payload.at)
	local label = cleanText(payload.label, 1, 40)
	if label == nil then
		return fail("bad_request")
	end
	if not Cluster.validScope(payload.scope) then
		return fail("bad_scope")
	end
	local raw = payload.entries
	if payload.combo ~= nil then
		raw = nil
		if type(payload.combo) == "string" then
			for _, combo in self:_combos() do
				if combo.id == payload.combo then
					raw = combo.entries
				end
			end
		end
		if raw == nil then
			return fail("unknown_item")
		end
	end
	if type(raw) ~= "table" or #raw < 1 or #raw > Overlord.MAX_ENTRIES then
		return fail("bad_request")
	end
	local entries = {}
	for _, entry in raw do
		if type(entry) ~= "table" or type(entry.preset) ~= "string" then
			return fail("bad_request")
		end
		local overrides, why = Params.cleanOverrides(entry.overrides)
		if not overrides then
			return fail("bad_params:" .. tostring(why))
		end
		table.insert(entries, { preset = entry.preset, overrides = if next(overrides) then overrides else nil })
	end
	local eventMode = payload.eventMode == true
	-- Exactly what Activate checks, against an empty server
	local ok, code = self.core:activate(actor, entries, { dryRun = true, eventMode = eventMode })
	if not ok then
		return fail(code or "bad_request")
	end
	if Cluster.size({ entries = entries, scope = payload.scope }) > Cluster.MAX_BYTES - 300 then
		return fail("payload_too_large")
	end
	local filtered = self:_filter(label, actor.userId)
	if filtered == nil then
		return fail("filter_failed")
	end
	if cleanText(filtered, 1, 40) == nil then
		return fail("text_filtered")
	end
	local list = self:_readList(self.scheduleStore)
	if list == nil then
		return fail("store_failed")
	end
	local id = self:_shortId("sch_", list)
	local item = { id = id, at = at, label = filtered, scope = copy(payload.scope), entries = entries, eventMode = eventMode, status = "pending", by = actor.userId, createdAt = now }
	local saved, why = self:_updateList(self.scheduleStore, function(stored)
		for _, existing in stored do
			if existing.id == id then
				return "store_failed"
			end
		end
		-- Over the cap: drop the oldest finished items first
		while #stored >= MAX_SCHEDULE do
			local oldest
			for index, existing in stored do
				if FINISHED[existing.status] and (oldest == nil or existing.at < stored[oldest].at) then
					oldest = index
				end
			end
			if oldest == nil then
				return "schedule_full"
			end
			table.remove(stored, oldest)
		end
		table.insert(stored, item)
		return nil
	end)
	self.cluster.audit:record({ by = actor.userId, action = "ScheduleAdd", scope = "owner", presets = self.cluster:_presetsOf({ e = entries }), outcome = if saved then "ok" else "refused", reason = why, id = id })
	if not saved then
		return fail(why or "store_failed")
	end
	return succeed({ id = id })
end

function OverlordService:_scheduleList()
	local list = self:_readList(self.scheduleStore)
	if list == nil then
		return fail("store_failed")
	end
	local items = {}
	for _, item in list do
		table.insert(items, { id = item.id, at = item.at, label = item.label, scope = item.scope, status = item.status, ranAt = item.ranAt, ranBy = item.ranBy })
	end
	table.sort(items, function(a, b)
		return a.at < b.at
	end)
	return succeed({ items = items })
end

function OverlordService:_scheduleCancel(actor: any, payload: any)
	local id = payload.id
	if type(id) ~= "string" or #id > 32 then
		return fail("bad_request")
	end
	local saved, why = self:_updateList(self.scheduleStore, function(stored)
		for _, item in stored do
			if item.id == id then
				if item.status ~= "pending" then
					return "not_pending"
				end
				item.status = "cancelled"
				return nil
			end
		end
		return "unknown_item"
	end)
	self.cluster.audit:record({ by = actor.userId, action = "ScheduleCancel", scope = "owner", presets = {}, outcome = if saved then "ok" else "refused", reason = why, id = id })
	if not saved then
		return fail(why or "store_failed")
	end
	return succeed({ id = id })
end

-- One server wins each claim (a MemoryStore update that only succeeds on an empty key)
function OverlordService:_claim(id: string): boolean
	if not self.memory then
		return false
	end
	local jobId = self.deps.jobId
	local ok, result = pcall(function()
		local map = self.memory:GetSortedMap("OverlordClaims")
		return map:UpdateAsync("sched_" .. id, function(old)
			if old ~= nil then
				return nil
			end
			return jobId
		end, CLAIM_SECONDS)
	end)
	return ok and result == jobId
end

-- Marks the item done (only if still pending), then runs it like Activate
function OverlordService:_runScheduled(item: any)
	local now = self.deps.clock()
	local jobId = self.deps.jobId
	local marked = false
	local saved = self:_updateList(self.scheduleStore, function(stored)
		marked = false
		for _, existing in stored do
			if existing.id == item.id then
				if existing.status ~= "pending" then
					return "not_pending"
				end
				existing.status = "done"
				existing.ranAt = now
				existing.ranBy = jobId
				marked = true
				return nil
			end
		end
		return "unknown_item"
	end)
	if not saved or not marked then
		return false
	end
	local actor = { userId = item.by, isOwner = type(item.by) == "number" and self.owner:isOwnerId(item.by) }
	local result = self.cluster:issue(actor, "activate", { entries = item.entries, eventMode = item.eventMode == true }, item.scope)
	if not result.ok then
		self:_updateList(self.scheduleStore, function(stored)
			for _, existing in stored do
				if existing.id == item.id and existing.status == "done" and existing.ranBy == jobId then
					existing.status = "missed"
					existing.reason = result.code
					return nil
				end
			end
			return "unknown_item"
		end)
	end
	return result.ok
end

-- Every server calls this about once a second; it works every SCHEDULE_CHECK seconds
-- (`force` skips the wait). Returns how many items this server ran.
function OverlordService:_scheduleTick(force: boolean?): number
	local now = self.deps.clock()
	if not force and now - self.lastScheduleCheck < SCHEDULE_CHECK then
		return 0
	end
	self.lastScheduleCheck = now
	local list = self:_readList(self.scheduleStore)
	if list == nil then
		return 0
	end
	local due, late = {}, false
	for _, item in list do
		if item.status == "pending" and type(item.at) == "number" and item.at <= now then
			if now - item.at > SCHEDULE_LATE then
				late = true
			elseif #due < 5 then
				table.insert(due, item)
			end
		end
	end
	if late then
		-- nobody ran these in time (a run marks the item done before it starts)
		self:_updateList(self.scheduleStore, function(stored)
			local changed = false
			for _, item in stored do
				if item.status == "pending" and type(item.at) == "number" and now - item.at > SCHEDULE_LATE then
					item.status = "missed"
					item.reason = "late"
					changed = true
				end
			end
			return if changed then nil else "unknown_item"
		end)
	end
	local ran = 0
	for _, item in due do
		if self:_claim(item.id) and self:_runScheduled(item) then
			ran += 1
		end
	end
	return ran
end

function OverlordService:_housekeeping()
	if not self.core then
		return
	end
	self:_scheduleTick()
	if self.deps.clock() - self.lastCustomsLoad >= CUSTOMS_REFRESH then
		self:_loadCustoms()
	end
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
	elseif action == Action.Announce then
		return self:_announce(actor, payload)
	elseif action == Action.ScheduleAdd then
		return self:_scheduleAdd(actor, payload)
	elseif action == Action.ScheduleList then
		return self:_scheduleList()
	elseif action == Action.ScheduleCancel then
		return self:_scheduleCancel(actor, payload)
	elseif action == Action.CustomSave then
		return self:_customSave(actor, payload)
	elseif action == Action.CustomList then
		return succeed({ items = self:_readList(self.customStore) or self.customItems or {} })
	elseif action == Action.CustomDelete then
		return self:_customDelete(actor, payload)
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
