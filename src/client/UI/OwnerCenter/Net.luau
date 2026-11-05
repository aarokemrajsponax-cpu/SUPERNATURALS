-- The Control Center's link to the server: one request in flight per action, the cached data
-- every screen reads (catalogue, state, servers, audit, combos, customs, schedule), the chosen
-- scope, and the owner's session-only picks (favourites, recent, the selection tray).
-- Nothing here is trusted by the server: every request is validated there again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Messages = require(script.Parent.Messages)

local Action = Protocol.OverlordAction
local Signal = Protocol.OverlordSignal

local Net = {}

local TIMEOUT = 12
local MAX_RECENT = 12
local MAX_SELECTION = 8

Net.catalogue = nil :: any
Net.state = nil :: any
Net.servers = {} :: { any }
Net.serversAt = nil :: number?
Net.audit = {} :: { any }
Net.combos = {} :: { any }
Net.customs = {} :: { any }
Net.schedule = {} :: { any }
Net.lastHeard = nil :: number?
-- Session only: gone when the player leaves
Net.favourites = {} :: { [string]: boolean }
Net.recent = {} :: { string }
Net.selection = {} :: { any }

Net.scopeId = "here"
Net.picked = {} :: { [string]: boolean }

local listeners: { [string]: { (...any) -> () } } = {}
local pending: { [number]: { action: string, callback: ((any) -> ())? } } = {}
local inflight: { [string]: number } = {}
local nextId = 0
local request: RemoteEvent? = nil
local started = false

function Net.on(event: string, callback: (...any) -> ())
	listeners[event] = listeners[event] or {}
	table.insert(listeners[event], callback)
end

local function emit(event: string, ...)
	for _, callback in listeners[event] or {} do
		task.spawn(callback, ...)
	end
end
Net.emit = emit

-- Cached data ------------------------------------------------------------------------------

local function indexCatalogue(data: any)
	local list = if typeof(data.presets) == "table" then data.presets else {}
	local byId, names = {}, {}
	for _, category in data.categories or {} do
		names[category.id] = category.name
	end
	for _, preset in list do
		byId[preset.id] = preset
		local tags = if typeof(preset.tags) == "table" then table.concat(preset.tags, " ") else ""
		local effects = if typeof(preset.effects) == "table" then table.concat(preset.effects, " ") else ""
		preset.haystack = string.lower(`{preset.name} {preset.description} {preset.category} {names[preset.category] or ""} {tags} {effects}`)
	end
	data.byId = byId
	data.categoryNames = names
	data.effects = if typeof(data.effects) == "table" then data.effects else {}
	return data
end

local function listOf(data: any): { any }
	if typeof(data) ~= "table" then
		return {}
	end
	if typeof(data.items) == "table" then
		return data.items
	end
	return data
end

local function store(action: string, result: any)
	local data = result.data
	if action == Action.Catalogue and typeof(data) == "table" then
		Net.catalogue = indexCatalogue(data)
		emit("catalogue")
	elseif action == Action.State and typeof(data) == "table" then
		Net.state = data
		emit("state")
	elseif action == Action.Servers then
		Net.servers = listOf(data)
		Net.serversAt = os.time()
		emit("servers")
	elseif action == Action.Audit then
		local entries = if typeof(data) == "table" and typeof(data.entries) == "table" then data.entries else {}
		local newestFirst = {}
		for index = #entries, 1, -1 do
			table.insert(newestFirst, entries[index])
		end
		Net.audit = newestFirst
		emit("audit")
	elseif action == Action.ListCombos or action == Action.SaveCombo or action == Action.DeleteCombo then
		Net.combos = listOf(data)
		emit("combos")
	elseif action == Action.CustomList or action == Action.CustomSave or action == Action.CustomDelete then
		if typeof(data) == "table" and typeof(data.items) == "table" then
			Net.customs = data.items
			emit("customs")
		end
	elseif action == Action.ScheduleList then
		Net.schedule = listOf(data)
		emit("schedule")
	end
end

-- Requests ---------------------------------------------------------------------------------

local function onEvent(kind: any, first: any, second: any)
	if kind == Signal.Result then
		local entry = pending[first]
		if not entry then
			return
		end
		pending[first] = nil
		if inflight[entry.action] == first then
			inflight[entry.action] = nil
		end
		local result = if typeof(second) == "table" then second else { ok = false, code = "bad_request" }
		Net.lastHeard = os.clock()
		if result.ok then
			store(entry.action, result)
		end
		if entry.callback then
			entry.callback(result)
		end
	elseif kind == Signal.State and typeof(first) == "table" then
		Net.lastHeard = os.clock()
		Net.state = first
		emit("state")
	end
end

-- Connects to the server's answers (once). Safe to call again.
function Net.start()
	if started then
		return
	end
	started = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	request = remotes:WaitForChild("OverlordRequest") :: RemoteEvent
	local event = remotes:WaitForChild("OverlordEvent") :: RemoteEvent
	event.OnClientEvent:Connect(onEvent)
end

-- Sends one request; callback(result) gets { ok, code?, message?, data? }. A second request of
-- the same action while one is running is answered at once with code "busy".
function Net.request(action: string, payload: any?, callback: ((any) -> ())?)
	Net.start()
	if inflight[action] then
		if callback then
			callback({ ok = false, code = "busy" })
		end
		return
	end
	nextId += 1
	local id = nextId
	inflight[action] = id
	pending[id] = { action = action, callback = callback }
	local remote = request :: RemoteEvent
	remote:FireServer(id, action, payload)
	task.delay(TIMEOUT, function()
		local entry = pending[id]
		if entry then
			pending[id] = nil
			if inflight[action] == id then
				inflight[action] = nil
			end
			if entry.callback then
				entry.callback({ ok = false, code = "timeout" })
			end
		end
	end)
end

function Net.loadCatalogue(force: boolean?)
	if Net.catalogue and not force then
		return
	end
	Net.request(Action.Catalogue)
end

function Net.refreshLive()
	Net.request(Action.State)
	Net.request(Action.Servers)
end

function Net.loadAudit()
	Net.request(Action.Audit, { limit = 60 })
end

-- Scope ------------------------------------------------------------------------------------

function Net.pickedList(): { string }
	local list = {}
	for jobId, on in Net.picked do
		if on then
			table.insert(list, jobId)
		end
	end
	table.sort(list)
	return list
end

function Net.setScope(id: string)
	if id ~= "here" and id ~= "all" and id ~= "test" and id ~= "jobs" then
		return
	end
	Net.scopeId = id
	emit("scope")
end

function Net.togglePicked(jobId: string)
	Net.picked[jobId] = if Net.picked[jobId] then nil else true
	emit("scope")
end

-- The scope table to send, or nil and a message code when "Pick servers" has nothing picked
function Net.scopeValue(): (any?, string?)
	if Net.scopeId == "all" then
		return { k = "all" }
	elseif Net.scopeId == "test" then
		return { k = "test" }
	elseif Net.scopeId == "jobs" then
		local list = Net.pickedList()
		if #list == 0 then
			return nil, "no_servers_picked"
		end
		return { k = "jobs", j = list }
	end
	return { k = "here" }
end

function Net.scopeText(): string
	if Net.scopeId == "all" then
		return "All servers"
	elseif Net.scopeId == "test" then
		return "Test servers"
	elseif Net.scopeId == "jobs" then
		local count = #Net.pickedList()
		return if count == 1 then "1 picked server" else `{count} picked servers`
	end
	return "This server"
end

-- Describes a scope table or string from the audit log or the schedule
function Net.describeScope(scope: any): string
	if typeof(scope) == "table" then
		if scope.k == "all" then
			return "All servers"
		elseif scope.k == "test" then
			return "Test servers"
		elseif scope.k == "jobs" then
			return `{#(scope.j or {})} picked servers`
		end
		return "This server"
	end
	local text = tostring(scope or "")
	if text == "here" then
		return "This server"
	elseif text == "all" then
		return "All servers"
	elseif text == "test" then
		return "Test servers"
	elseif text == "jobs" then
		return "Picked servers"
	elseif text == "owner" then
		return "Owner"
	end
	return if text == "" then "This server" else text
end

-- Session picks -----------------------------------------------------------------------------

function Net.toggleFavourite(id: string)
	Net.favourites[id] = if Net.favourites[id] then nil else true
	emit("picks")
end

function Net.touchRecent(id: string)
	for index, existing in Net.recent do
		if existing == id then
			table.remove(Net.recent, index)
			break
		end
	end
	table.insert(Net.recent, 1, id)
	while #Net.recent > MAX_RECENT do
		table.remove(Net.recent)
	end
	emit("picks")
end

-- Adds an entry { preset, overrides? } to the selection tray; false when it is full
function Net.addToSelection(entry: any): boolean
	if #Net.selection >= MAX_SELECTION then
		return false
	end
	table.insert(Net.selection, entry)
	emit("selection")
	return true
end

function Net.removeFromSelection(index: number)
	table.remove(Net.selection, index)
	emit("selection")
end

function Net.clearSelection()
	Net.selection = {}
	emit("selection")
end

Net.MAX_SELECTION = MAX_SELECTION
Net.Messages = Messages

return Net
