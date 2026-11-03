-- The event core for one server. It owns the list of running events and everything they
-- changed, and nothing else: no networking (see Cluster), no remotes (see OverlordService).
-- All world access goes through `deps`, so a test can run several of these side by side.
--
--   local core = Overlord.new(deps)
--   core:activate(actor, { { preset = "w_golden_world", overrides = { duration = 60 } } }, opts)
--   core:stop(eventId) / core:stopAll() / core:returnToDefault()
--   core:tick()  -- call about once a second: ends events whose time is up
--
-- Reasons returned on refusal are short codes ("not_owner", "channel_conflict:lighting:x") plus
-- a plain sentence from Overlord.explain.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventPresets = require(ReplicatedStorage.Shared.Config.EventPresets)
local Params = require(script.Parent.Params)
local Registry = require(script.Parent.Registry)

local Overlord = {}
Overlord.__index = Overlord

Overlord.MAX_ENTRIES = 8
Overlord.COST_CAP = 160

local LIGHTING_PROPS = { "Ambient", "OutdoorAmbient", "Brightness", "ColorShift_Top", "ColorShift_Bottom", "ExposureCompensation", "ClockTime" }

local GROUPS = {
	environment = { environment = true, structure = true },
	effects = { player = true, spectacle = true },
	players = { player = true, gameplay = true },
}

function Overlord.explain(code: string): string
	local head = string.match(code, "^[^:]+") or code
	local text = {
		not_owner = "Only the owner can do that.",
		bad_request = "The request was malformed.",
		unknown_preset = "That preset does not exist.",
		too_many_entries = "Too many presets in one activation.",
		event_mode_required = "That preset changes gameplay, so it only runs in event mode.",
		match_in_progress = "A match is running, so gameplay changes are held back.",
		incompatible_tags = "Those presets do not belong together.",
		entries_conflict = "Two of the chosen presets use the same effect channel.",
		channel_conflict = "Something already running uses the same effect channel.",
		performance_cap = "That would go over the performance limit for this server.",
		effect_failed = "An effect failed to start, so everything was rolled back.",
		bad_params = "A setting was out of range.",
		unknown_event = "No such running event.",
		rate_limited = "Too many commands too quickly. Wait a moment.",
		bad_scope = "That server selection is not valid.",
		global_sync_failed = "The command could not be shared with other servers, so it is not reported as successful.",
		payload_too_large = "That combination is too large to send to other servers.",
		unknown_server = "That server is not registered right now.",
		teleport_failed = "The teleport did not start.",
		store_failed = "Saving failed. Try again.",
		expired = "That command is out of date.",
		bad_command = "The command was malformed.",
		filter_failed = "Roblox's text filter could not check that text, so nothing was sent.",
		text_filtered = "Roblox's text filter changed that text, so it was refused. Reword it.",
		not_pending = "Only pending items can be cancelled.",
		bad_time = "The time must be between one minute and 30 days from now.",
		schedule_full = "The schedule is full of pending items. Cancel some first.",
		unknown_item = "No such item.",
		custom_limit = "The limit of saved custom events is reached. Delete one first.",
		too_many_effects = "A custom event holds 1 to 6 effects.",
		unknown_effect = "That effect does not exist.",
	}
	return text[head] or code
end

function Overlord.new(deps)
	local self = setmetatable({}, Overlord)
	self.deps = deps
	self.presets = deps.presets or EventPresets
	self.active = {} :: { any } -- events in start order
	self.byId = {} :: { [string]: any }
	self.eventMode = false
	self.counter = 0
	self.baseline = nil
	self.fxCount = 0
	self.ctx = self:_makeContext()
	return self
end

function Overlord:now(): number
	return self.deps.clock()
end

function Overlord:_makeContext()
	local deps = self.deps
	local core = self
	local ctx = {
		lighting = deps.lighting,
		workspace = deps.workspace,
		replicated = deps.replicated,
		worldRoot = deps.worldRoot,
		players = deps.players,
		owners = deps.owners,
		inMatch = deps.inMatch,
		matchActive = deps.matchActive,
		center = deps.center,
		onCharacter = deps.onCharacter,
	}
	-- Publishes a record the clients draw. Returns the function that removes it.
	function ctx.publish(effectId: string, params: { [string]: any })
		local schema = Registry.effects[effectId].params
		local record = Instance.new("Folder")
		core.fxCount += 1
		record.Name = `{effectId}_{core.fxCount}`
		record:SetAttribute("Effect", effectId)
		record:SetAttribute("StartedAt", core:now())
		for name, spec in schema do
			local value = params[name]
			if spec.type == "color" then
				value = Color3.fromRGB(value[1], value[2], value[3])
			end
			record:SetAttribute(name, value)
		end
		record.Parent = deps.fxRoot
		return function()
			record:Destroy()
		end
	end
	return ctx
end

-- Validates one entry against the catalogue. Returns a plan or nil, code.
function Overlord:_plan(actor, entry): (any?, string?)
	if type(entry) ~= "table" or type(entry.preset) ~= "string" then
		return nil, "bad_request"
	end
	local preset = self.presets.ById[entry.preset]
	if not preset then
		return nil, "unknown_preset"
	end
	return self:planPreset(actor, preset, entry.overrides)
end

-- Validates one preset object (catalogue or custom) with optional owner overrides: effect
-- allowlist, parameter rules, channels and cost. Returns a plan or nil, code.
function Overlord:planPreset(actor, preset, rawOverrides): (any?, string?)
	if preset.ownerOnly and not actor.isOwner then
		return nil, "not_owner"
	end
	local overrides, why = Params.cleanOverrides(rawOverrides)
	if not overrides then
		return nil, "bad_params:" .. tostring(why)
	end
	local effects, channels, cost = {}, {}, 0
	for _, spec in preset.effects do
		local effect = Registry.effects[spec.effect]
		if not effect then
			return nil, "unknown_preset"
		end
		if effect.ownerOnly and not actor.isOwner then
			return nil, "not_owner"
		end
		local clean, reason = Params.clean(effect.params, spec.params, overrides.intensity, overrides.color)
		if not clean then
			return nil, "bad_params:" .. tostring(reason)
		end
		local own = Registry.channelsOf(effect, clean)
		table.insert(effects, { module = effect, params = clean, channels = own })
		for _, channel in own do
			channels[channel] = true
		end
		cost += Registry.costOf(effect, clean)
	end
	local duration = overrides.duration
	if duration == nil then
		duration = preset.duration
	end
	return { preset = preset, effects = effects, channels = channels, cost = cost, duration = duration }
end

local function tagsClash(a, b): boolean
	for _, excluded in a.excludes do
		if table.find(b.tags, excluded) then
			return true
		end
	end
	return false
end

-- Activates one or several presets together, all or nothing.
-- actor: { userId = number, isOwner = boolean }
-- opts: { eventMode = boolean?, eventId = string?, startedAt = number?, origin = "local"|"global", scope = table?,
--         dryRun = boolean? }  dryRun runs every check against an empty server (no match or running-event
--         checks) and starts nothing: how a scheduled event is validated when it is added.
-- Returns true, { ids = { string }, replaced = { string } } or false, code
function Overlord:activate(actor, entries, opts)
	opts = opts or {}
	if type(actor) ~= "table" or actor.isOwner ~= true then
		return false, "not_owner"
	end
	if type(entries) ~= "table" or #entries == 0 then
		return false, "bad_request"
	end
	if #entries > Overlord.MAX_ENTRIES then
		return false, "too_many_entries"
	end
	local plans = {}
	for _, entry in entries do
		local plan, code = self:_plan(actor, entry)
		if not plan then
			return false, code
		end
		table.insert(plans, plan)
	end

	local dryRun = opts.dryRun == true
	local running = if dryRun then {} else self.active
	local wantsGameplay = false
	for _, plan in plans do
		if plan.preset.eventMode then
			wantsGameplay = true
			if not (opts.eventMode or (self.eventMode and not dryRun)) then
				return false, "event_mode_required"
			end
			for _, effect in plan.effects do
				if effect.module.id == "Gravity" and not dryRun and self.deps.matchActive() then
					return false, "match_in_progress"
				end
			end
		end
	end

	-- Tags and channels, between the new presets and against what already runs
	local claimed = {}
	local replace = {}
	for i, plan in plans do
		for j = 1, i - 1 do
			if tagsClash(plan.preset, plans[j].preset) or tagsClash(plans[j].preset, plan.preset) then
				return false, `incompatible_tags:{plan.preset.id}:{plans[j].preset.id}`
			end
		end
		for _, event in running do
			if tagsClash(plan.preset, event.preset) or tagsClash(event.preset, plan.preset) then
				return false, `incompatible_tags:{plan.preset.id}:{event.preset.id}`
			end
		end
		for channel in plan.channels do
			if claimed[channel] then
				return false, `entries_conflict:{channel}`
			end
			claimed[channel] = true
			for _, event in running do
				if event.channels[channel] then
					if plan.preset.onConflict == "replace" then
						replace[event.id] = event
					else
						return false, `channel_conflict:{channel}:{event.preset.id}`
					end
				end
			end
		end
	end
	local total = 0
	for _, plan in plans do
		total += plan.cost
	end
	for _, event in running do
		if not replace[event.id] then
			total += event.cost
		end
	end
	if total > (self.deps.costCap or Overlord.COST_CAP) then
		return false, "performance_cap"
	end

	if dryRun then
		return true, { ids = {}, replaced = {} }
	end

	-- Go. First clear what is being replaced.
	local replaced = {}
	for id in replace do
		table.insert(replaced, id)
		self:stop(id)
	end
	if #self.active == 0 then
		self.baseline = self:_captureBaseline()
	end
	local startedAt = opts.startedAt or self:now()
	self.counter += 1
	local base = opts.eventId or `{self.deps.jobId or "local"}-{self.counter}`
	local started = {}
	local ids = {}
	for index, plan in plans do
		local event = {
			id = if #plans == 1 and opts.eventId then base else `{base}.{index}`,
			preset = plan.preset,
			startedAt = startedAt,
			endsAt = if plan.duration > 0 then startedAt + plan.duration else nil,
			origin = opts.origin or "local",
			scope = opts.scope,
			by = actor.userId,
			channels = plan.channels,
			cost = plan.cost,
			stops = {},
			groups = {},
		}
		for _, effect in plan.effects do
			local ok, stopFn = pcall(effect.module.start, self.ctx, effect.params)
			if not ok then
				warn(`[Overlord] {effect.module.id} failed to start: {stopFn}`)
				for _, prior in event.stops do
					pcall(prior.stop)
				end
				for k = #started, 1, -1 do
					self:_stopEvent(started[k])
				end
				if #self.active == 0 then
					self.baseline = nil
				end
				return false, "effect_failed:" .. effect.module.id
			end
			table.insert(event.stops, { stop = stopFn, group = effect.module.group, id = effect.module.id })
		end
		table.insert(started, event)
		table.insert(ids, event.id)
		self.byId[event.id] = event
		table.insert(self.active, event)
	end
	if wantsGameplay then
		self.eventMode = true
	end
	return true, { ids = ids, replaced = replaced }
end

function Overlord:_stopEvent(event)
	for k = #event.stops, 1, -1 do
		local ok, err = pcall(event.stops[k].stop)
		if not ok then
			warn(`[Overlord] stopping {event.stops[k].id} failed: {err}`)
		end
	end
	event.stops = {}
	self.byId[event.id] = nil
	local index = table.find(self.active, event)
	if index then
		table.remove(self.active, index)
	end
end

function Overlord:_settle()
	local gameplay = false
	for _, event in self.active do
		for _, entry in event.stops do
			if entry.group == "gameplay" then
				gameplay = true
			end
		end
	end
	if not gameplay then
		self.eventMode = false
	end
	if #self.active == 0 then
		self.baseline = nil
	end
end

function Overlord:stop(eventId: string): boolean
	local event = self.byId[eventId]
	if not event then
		return false
	end
	self:_stopEvent(event)
	self:_settle()
	return true
end

function Overlord:stopAll(onlyOrigin: string?): number
	local count = 0
	for i = #self.active, 1, -1 do
		local event = self.active[i]
		if event and (onlyOrigin == nil or event.origin == onlyOrigin) then
			self:_stopEvent(event)
			count += 1
		end
	end
	self:_settle()
	return count
end

-- Stops only the effects in the named groups ("environment", "effects", "players"); events
-- with nothing left are removed.
function Overlord:stopGroups(name: string): number
	local groups = GROUPS[name]
	if not groups then
		return 0
	end
	local count = 0
	for i = #self.active, 1, -1 do
		local event = self.active[i]
		for k = #event.stops, 1, -1 do
			local entry = event.stops[k]
			if groups[entry.group] then
				pcall(entry.stop)
				table.remove(event.stops, k)
				count += 1
			end
		end
		if #event.stops == 0 then
			self:_stopEvent(event)
		end
	end
	self:_settle()
	return count
end

function Overlord:_captureBaseline()
	local lighting = self.deps.lighting
	local values = {}
	for _, name in LIGHTING_PROPS do
		values[name] = (lighting :: any)[name]
	end
	return { lighting = values, gravity = self.deps.workspace.Gravity, season = self.deps.replicated:GetAttribute("SeasonOverride") }
end

-- Stops everything, then forces any property that still differs from the state before the
-- first event back to it, and deletes anything left in the effect folders.
function Overlord:returnToDefault(): { restoredByForce: number }
	local baseline = self.baseline
	self:stopAll()
	local forced = 0
	if baseline then
		for name, value in baseline.lighting do
			if (self.deps.lighting :: any)[name] ~= value then
				(self.deps.lighting :: any)[name] = value
				forced += 1
			end
		end
		if self.deps.workspace.Gravity ~= baseline.gravity then
			self.deps.workspace.Gravity = baseline.gravity
			forced += 1
		end
		self.deps.replicated:SetAttribute("SeasonOverride", baseline.season)
	end
	self.deps.fxRoot:ClearAllChildren()
	self.deps.worldRoot:ClearAllChildren()
	self.eventMode = false
	return { restoredByForce = forced }
end

-- Ends events whose time is up. Returns the ids that ended.
function Overlord:tick(): { string }
	local ended = {}
	local now = self:now()
	for i = #self.active, 1, -1 do
		local event = self.active[i]
		if event and event.endsAt and now >= event.endsAt then
			table.insert(ended, event.id)
			self:_stopEvent(event)
		end
	end
	if #ended > 0 then
		self:_settle()
	end
	return ended
end

-- What is running here, in a form safe to send to the owner's screens
function Overlord:list(): { any }
	local out = {}
	for _, event in self.active do
		table.insert(out, {
			id = event.id,
			preset = event.preset.id,
			name = event.preset.name,
			startedAt = event.startedAt,
			endsAt = event.endsAt,
			origin = event.origin,
			by = event.by,
		})
	end
	return out
end

function Overlord:isActive(presetId: string): boolean
	for _, event in self.active do
		if event.preset.id == presetId then
			return true
		end
	end
	return false
end

return Overlord
