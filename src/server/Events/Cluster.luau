-- Cross-server control for the owner's events.
--
--   MessagingService  topic "OverlordV1": compact commands, best effort.
--   MemoryStore       "OverlordActive": the global events that should be running now (expiring).
--                     "OverlordServers": heartbeat per server (job id, players, events, last sync).
--   DataStore         the audit log (see Audit).
--
-- Every server subscribes, validates each command (shape, allowlisted action, owner by
-- UserId, expiry, replay) and applies it to its own Overlord core. Messages can be lost, so
-- every server also reads the MemoryStore on start and every RECONCILE_EVERY seconds and
-- starts or stops what differs. Nothing here runs code from a message: a command is data
-- naming a preset id and validated numbers.

local Audit = require(script.Parent.Audit)

local Cluster = {}
Cluster.__index = Cluster

Cluster.TOPIC = "OverlordV1"
Cluster.RECONCILE_EVERY = 30
Cluster.HEARTBEAT_EVERY = 20
Cluster.COMMAND_TTL = 60 -- seconds a command stays valid after it was sent
Cluster.MAX_BYTES = 900 -- Roblox allows 1 KB per message
Cluster.MAX_RATE = 12 -- commands per RATE_WINDOW seconds
Cluster.RATE_WINDOW = 10
Cluster.MAX_STATE_TTL = 3888000 -- MemoryStore's 45 day limit

local ACTIONS = { activate = true, stop = true, stopAll = true, restoreEnvironment = true, clearEffects = true, restorePlayers = true, returnToDefault = true }
local MAX_SEEN = 500

local function size(value: any): number
	local kind = type(value)
	if kind == "string" then
		return #value + 2
	elseif kind == "table" then
		local total = 2
		for k, v in value do
			total += size(k) + size(v) + 1
		end
		return total
	end
	return 8
end
Cluster.size = size

local function validId(value: any): boolean
	return type(value) == "string" and #value >= 4 and #value <= 64 and string.find(value, "^[%w%-_%.]+$") ~= nil
end

-- deps: messaging, memory, auditStore, clock, wait, jobId, isTest, isOwnerId(userId), playerCount(), randomId()
function Cluster.new(core, deps)
	local self = setmetatable({}, Cluster)
	self.core = core
	self.deps = deps
	self.audit = Audit.new(deps.auditStore, deps.clock, deps.wait)
	self.seen = {} :: { [string]: number } -- command id -> expiry
	self.seenOrder = {} :: { string }
	self.applied = {} :: { [string]: any } -- global command id -> { ids, appliedAt, origin }
	self.rate = {} :: { [number]: { number } }
	self.lastReconcile = 0
	self.lastHeartbeat = 0
	self.lastSync = nil :: number?
	self.syncOk = true
	self.connection = nil
	return self
end

function Cluster:now(): number
	return self.deps.clock()
end

function Cluster:_retry(label: string, fn: () -> any): (boolean, any)
	local result
	for attempt = 1, 3 do
		local ok, value = pcall(fn)
		if ok then
			return true, value
		end
		result = value
		if attempt < 3 then
			self.deps.wait(0.5 * 2 ^ (attempt - 1))
		end
	end
	warn(`[Overlord] {label} failed after retries: {result}`)
	return false, result
end

function Cluster:_activeMap()
	return self.deps.memory:GetSortedMap("OverlordActive")
end

function Cluster:_serverMap()
	return self.deps.memory:GetSortedMap("OverlordServers")
end

-- Start: subscribe, then read what is already active so a new server joins the event
function Cluster:Start()
	local ok, connection = self:_retry("subscribe", function()
		return self.deps.messaging:SubscribeAsync(Cluster.TOPIC, function(message)
			self:_onMessage(message.Data)
		end)
	end)
	if ok then
		self.connection = connection
	end
	self:reconcile()
	self:heartbeat()
end

function Cluster:Stop()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	pcall(function()
		self:_serverMap():RemoveAsync(self.deps.jobId)
	end)
end

-- Call about once a second
function Cluster:tick()
	local now = self:now()
	self.core:tick()
	if now - self.lastHeartbeat >= Cluster.HEARTBEAT_EVERY then
		self:heartbeat()
	end
	if now - self.lastReconcile >= Cluster.RECONCILE_EVERY then
		self:reconcile()
	end
end

-- Does a command's scope include this server?
function Cluster:appliesHere(scope: any): boolean
	if type(scope) ~= "table" then
		return false
	end
	if scope.k == "all" or scope.k == "here" then
		return true
	elseif scope.k == "jobs" then
		return type(scope.j) == "table" and table.find(scope.j, self.deps.jobId) ~= nil
	elseif scope.k == "test" then
		return self.deps.isTest == true
	end
	return false
end

local function validScope(scope: any): boolean
	if type(scope) ~= "table" then
		return false
	end
	if scope.k == "all" or scope.k == "here" or scope.k == "test" then
		return true
	end
	if scope.k == "jobs" and type(scope.j) == "table" and #scope.j >= 1 and #scope.j <= 20 then
		for _, job in scope.j do
			if type(job) ~= "string" or #job > 64 then
				return false
			end
		end
		return true
	end
	return false
end

-- Shape and trust checks for a command, whether it came from a message or the MemoryStore.
-- Returns nil, code on refusal.
function Cluster:validate(cmd: any, fromStore: boolean?): string?
	if type(cmd) ~= "table" or cmd.v ~= 1 then
		return "bad_command"
	end
	if not validId(cmd.id) or not ACTIONS[cmd.a] or type(cmd.by) ~= "number" or type(cmd.t) ~= "number" or type(cmd.x) ~= "number" then
		return "bad_command"
	end
	if type(cmd.n) ~= "string" or #cmd.n > 32 then
		return "bad_command"
	end
	if not self.deps.isOwnerId(cmd.by) then
		return "not_owner"
	end
	if not validScope(cmd.s) then
		return "bad_scope"
	end
	if cmd.a == "activate" then
		if type(cmd.e) ~= "table" or #cmd.e < 1 or #cmd.e > 8 or type(cmd.st) ~= "number" then
			return "bad_command"
		end
	elseif cmd.a == "stop" then
		if not validId(cmd.g) then
			return "bad_command"
		end
	end
	if not fromStore then
		local now = self:now()
		if now > cmd.x then
			return "expired"
		end
		if cmd.t > now + Cluster.COMMAND_TTL then
			return "from_the_future"
		end
		if cmd.x - cmd.t > Cluster.COMMAND_TTL * 2 then
			return "bad_command"
		end
	end
	return nil
end

function Cluster:_remember(id: string, expiry: number)
	self.seen[id] = expiry
	table.insert(self.seenOrder, id)
	while #self.seenOrder > MAX_SEEN do
		self.seen[table.remove(self.seenOrder, 1)] = nil
	end
end

function Cluster:_ownerActor(userId: number)
	return { userId = userId, isOwner = self.deps.isOwnerId(userId) }
end

-- Applies a validated command to this server. Returns ok, code, info.
function Cluster:_apply(cmd: any, origin: string)
	local core = self.core
	if cmd.a == "activate" then
		local startedAt = cmd.st
		-- already over? (a late message or a reconcile of an old event)
		for _, entry in cmd.e do
			local preset = type(entry) == "table" and core.presets.ById[entry.preset]
			if preset then
				local duration = if type(entry.overrides) == "table" and entry.overrides.duration ~= nil then entry.overrides.duration else preset.duration
				if type(duration) == "number" and duration > 0 and startedAt + duration <= self:now() then
					return false, "expired"
				end
			end
		end
		local ok, result = core:activate(self:_ownerActor(cmd.by), cmd.e, {
			eventMode = cmd.ev == true,
			eventId = cmd.id,
			startedAt = startedAt,
			origin = if cmd.s.k == "here" then "local" else "global",
			scope = cmd.s,
		})
		if ok then
			self.applied[cmd.id] = { ids = result.ids, appliedAt = self:now(), origin = origin }
		end
		return ok, if ok then nil else result, if ok then result else nil
	elseif cmd.a == "stop" then
		local record = self.applied[cmd.g]
		local stopped = 0
		if record then
			for _, id in record.ids do
				if core:stop(id) then
					stopped += 1
				end
			end
			self.applied[cmd.g] = nil
		elseif core:stop(cmd.g) then
			stopped = 1
		end
		return true, nil, { stopped = stopped }
	elseif cmd.a == "stopAll" then
		local count = core:stopAll()
		table.clear(self.applied)
		return true, nil, { stopped = count }
	elseif cmd.a == "restoreEnvironment" then
		return true, nil, { stopped = core:stopGroups("environment") }
	elseif cmd.a == "clearEffects" then
		return true, nil, { stopped = core:stopGroups("effects") }
	elseif cmd.a == "restorePlayers" then
		return true, nil, { stopped = core:stopGroups("players") }
	elseif cmd.a == "returnToDefault" then
		local report = core:returnToDefault()
		table.clear(self.applied)
		return true, nil, report
	end
	return false, "bad_command"
end

-- A message from MessagingService
function Cluster:_onMessage(data: any)
	local code = self:validate(data)
	if code then
		self.lastRefusal = code
		return
	end
	if self.seen[data.id] then
		self.duplicates = (self.duplicates or 0) + 1
		return
	end
	self:_remember(data.id, data.x)
	if not self:appliesHere(data.s) then
		return
	end
	local ok, why = self:_apply(data, "message")
	self.audit:record({ by = data.by, action = "remote:" .. data.a, scope = data.s.k, presets = self:_presetsOf(data), outcome = if ok then "applied" else "refused", reason = why, id = data.id, job = self.deps.jobId })
end

function Cluster:_presetsOf(cmd): { string }
	local out = {}
	if type(cmd.e) == "table" then
		for _, entry in cmd.e do
			if type(entry) == "table" and type(entry.preset) == "string" then
				table.insert(out, entry.preset)
			end
		end
	end
	return out
end

-- Rate limit per owner id
function Cluster:_allowRate(userId: number): boolean
	local now = self:now()
	local stamps = self.rate[userId] or {}
	self.rate[userId] = stamps
	while #stamps > 0 and now - stamps[1] > Cluster.RATE_WINDOW do
		table.remove(stamps, 1)
	end
	if #stamps >= Cluster.MAX_RATE then
		return false
	end
	table.insert(stamps, now)
	return true
end

local function scopeText(scope): string
	if scope.k == "jobs" then
		return "servers:" .. table.concat(scope.j, ",")
	end
	return scope.k
end

-- The owner issues a command. `actor` is the verified player: { userId, isOwner }.
-- Returns { ok, code?, id?, sync? = { published, stored }, applied? } and never throws.
function Cluster:issue(actor: any, action: string, payload: any, scope: any)
	local result = self:_issue(actor, action, payload, scope)
	local entry = {
		by = if type(actor) == "table" and type(actor.userId) == "number" then actor.userId else 0,
		action = tostring(action),
		scope = if validScope(scope) then scopeText(scope) else "invalid",
		presets = if type(payload) == "table" and type(payload.entries) == "table" then self:_presetsOf({ e = payload.entries }) else {},
		outcome = if result.ok then "ok" elseif result.sync == "failed" then "sync_failed" else "refused",
		reason = result.code,
		id = result.id,
		job = self.deps.jobId,
	}
	self.audit:record(entry)
	return result
end

function Cluster:_issue(actor: any, action: string, payload: any, scope: any)
	if type(actor) ~= "table" or actor.isOwner ~= true or type(actor.userId) ~= "number" then
		return { ok = false, code = "not_owner" }
	end
	if not ACTIONS[action] then
		return { ok = false, code = "bad_request" }
	end
	if not validScope(scope) then
		return { ok = false, code = "bad_scope" }
	end
	payload = payload or {}
	if type(payload) ~= "table" then
		return { ok = false, code = "bad_request" }
	end
	if not self:_allowRate(actor.userId) then
		return { ok = false, code = "rate_limited" }
	end
	local now = self:now()
	local id = self.deps.randomId()
	local cmd = {
		v = 1,
		id = id,
		n = self.deps.randomId(),
		t = now,
		x = now + Cluster.COMMAND_TTL,
		by = actor.userId,
		a = action,
		s = scope,
		e = payload.entries,
		ev = payload.eventMode == true,
		st = now,
		g = payload.target,
	}
	local code = self:validate(cmd)
	if code then
		return { ok = false, code = code }
	end
	if size(cmd) > Cluster.MAX_BYTES then
		return { ok = false, code = "payload_too_large" }
	end
	self:_remember(id, cmd.x)

	-- This server first (a refused preset must not be broadcast)
	local localResult
	if self:appliesHere(scope) then
		local ok, why, info = self:_apply(cmd, "local")
		if not ok then
			return { ok = false, code = why, id = id }
		end
		localResult = info or {}
	elseif cmd.a == "activate" then
		-- not for this server: still validate against the catalogue so junk is not broadcast
		local probe = self.core.presets
		for _, entry in cmd.e do
			if type(entry) ~= "table" or not probe.ById[entry.preset] then
				return { ok = false, code = "unknown_preset" }
			end
		end
	end

	local result = { ok = true, id = id, applied = self:appliesHere(scope), info = localResult }
	if scope.k == "here" then
		return result
	end

	-- Everyone else: state first (so a server that misses the message can recover), then the message
	local stored = true
	if action == "activate" then
		stored = self:_storeActive(cmd)
	else
		stored = self:_clearActive(cmd)
	end
	local published = self:_retry("publish", function()
		self.deps.messaging:PublishAsync(Cluster.TOPIC, cmd)
	end)
	result.sync = { published = published, stored = stored }
	if not published and not stored then
		result.ok = false
		result.code = "global_sync_failed"
		result.sync = "failed"
	elseif not published or not stored then
		result.degraded = true -- reaches other servers late, through reconciliation, or not at all
	end
	return result
end

-- Longest remaining life of the command's presets, for the MemoryStore expiry
function Cluster:_ttl(cmd): number
	local ttl = 0
	for _, entry in cmd.e do
		local preset = self.core.presets.ById[entry.preset]
		local duration = if type(entry.overrides) == "table" and entry.overrides.duration ~= nil then entry.overrides.duration else preset and preset.duration or 0
		if duration == 0 then
			return Cluster.MAX_STATE_TTL
		end
		ttl = math.max(ttl, duration)
	end
	return math.clamp(math.ceil(ttl) + 5, 5, Cluster.MAX_STATE_TTL)
end

function Cluster:_storeActive(cmd): boolean
	local record = { v = 1, id = cmd.id, n = cmd.n, t = cmd.t, x = cmd.x, by = cmd.by, a = "activate", s = cmd.s, e = cmd.e, ev = cmd.ev, st = cmd.st }
	return (self:_retry("store active", function()
		self:_activeMap():SetAsync(cmd.id, record, self:_ttl(cmd))
	end))
end

-- Stop-type commands remove state so a new or lagging server does not restart it
function Cluster:_clearActive(cmd): boolean
	return (self:_retry("clear active", function()
		local map = self:_activeMap()
		if cmd.a == "stop" then
			map:RemoveAsync(cmd.g)
			return
		end
		for _, item in map:GetRangeAsync(Enum.SortDirection.Ascending, 200) do
			map:RemoveAsync(item.key)
		end
	end))
end

-- Bring this server in line with the MemoryStore
function Cluster:reconcile()
	self.lastReconcile = self:now()
	local ok, items = pcall(function()
		return self:_activeMap():GetRangeAsync(Enum.SortDirection.Ascending, 200)
	end)
	if not ok then
		self.syncOk = false
		return false
	end
	local present = {}
	for _, item in items do
		local cmd = item.value
		present[item.key] = true
		if not self.applied[item.key] and not self.seen[item.key] and self:appliesHere(cmd and cmd.s) and self:validate(cmd, true) == nil and cmd.a == "activate" then
			local applied, why = self:_apply(cmd, "reconcile")
			self:_remember(item.key, cmd.x)
			self.audit:record({ by = cmd.by, action = "reconcile:activate", scope = scopeText(cmd.s), presets = self:_presetsOf(cmd), outcome = if applied then "applied" else "refused", reason = why, id = cmd.id, job = self.deps.jobId })
		end
	end
	-- Global events that should have ended (a stop we missed): stop them here too
	local now = self:now()
	for id, record in self.applied do
		if not present[id] and record.origin ~= "local" and now - record.appliedAt > 15 then
			for _, eventId in record.ids do
				self.core:stop(eventId)
			end
			self.applied[id] = nil
		end
	end
	self.lastSync = now
	self.syncOk = true
	return true
end

function Cluster:heartbeat()
	self.lastHeartbeat = self:now()
	local presets, commands = {}, {}
	for _, event in self.core.active do
		table.insert(presets, event.preset.id)
		table.insert(commands, event.id)
	end
	pcall(function()
		self:_serverMap():SetAsync(self.deps.jobId, {
			pc = self.deps.playerCount(),
			p = presets,
			c = commands,
			sy = self.lastSync,
			hb = self.lastHeartbeat,
			ts = self.deps.isTest == true,
			em = self.core.eventMode,
		}, 75)
	end)
end

-- Live servers (from heartbeats), for the owner's server picker and "which servers have it"
function Cluster:servers(): { any }
	local out = {}
	local ok, items = pcall(function()
		return self:_serverMap():GetRangeAsync(Enum.SortDirection.Ascending, 100)
	end)
	if not ok then
		return out
	end
	for _, item in items do
		local v = item.value
		table.insert(out, { jobId = item.key, players = v.pc, presets = v.p, events = v.c, lastSync = v.sy, heartbeat = v.hb, test = v.ts, eventMode = v.em, current = item.key == self.deps.jobId })
	end
	return out
end

-- Which live servers report running the given command/event id
function Cluster:receivedBy(commandId: string): { string }
	local jobs = {}
	for _, server in self:servers() do
		for _, id in server.events or {} do
			if id == commandId or string.sub(id, 1, #commandId + 1) == commandId .. "." then
				table.insert(jobs, server.jobId)
				break
			end
		end
	end
	return jobs
end

return Cluster
