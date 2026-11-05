-- The owner's event control, second part: announcements, the event scheduler and the custom
-- event creator, on the same fakes as overlord_test (fake MessagingService, MemoryStore,
-- DataStore, TextService filter), with several OverlordService instances as separate servers:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/overlord_ext_test.luau build/game.rbxl

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl")
local world, Engine, services = game.world, game.Engine, game.services

local function load(path: string)
	return world.require(world.find(path))
end
local Protocol = load("ReplicatedStorage.Shared.Protocol")
local OverlordService = load("ServerScriptService.Server.Services.OverlordService")

local OWNER_ID = 8722595934
local T = 1000000
local cloud = Engine.newCloud()
local filter = Engine.newTextService()
local function setTime(t: number)
	T = t
	cloud.time = t
end
setTime(T)

local dataStores = Engine.services.DataStoreService
local STORES = { "OverlordSchedule", "OverlordCustoms", "OverlordCombos" }
local function resetStores()
	for _, name in STORES do
		Engine.writeStore(name, "owner", nil)
	end
end

-- One fake server: an OverlordService instance with its own core, cluster and client signal
local function makeServer(job: string, options: any?)
	options = options or {}
	local Color3 = roblox.Color3
	local lighting = world.Instance.new("Lighting")
	lighting.Ambient = Color3.fromRGB(70, 70, 70)
	lighting.OutdoorAmbient = Color3.fromRGB(100, 100, 110)
	lighting.Brightness = 2
	lighting.ColorShift_Top = Color3.fromRGB(0, 0, 0)
	lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	lighting.ExposureCompensation = 0
	lighting.ClockTime = 14
	local views = cloud:server(job)
	local deps = {
		lighting = lighting,
		workspace = { Gravity = 196.2 },
		replicated = world.Instance.new("Folder"),
		fxRoot = world.Instance.new("Folder"),
		worldRoot = world.Instance.new("Folder"),
		players = function() return {} end,
		owners = function() return {} end,
		inMatch = function() return false end,
		matchActive = function() return false end,
		center = function() return roblox.Vector3.new(0, 10, 0) end,
		onCharacter = function() return { Disconnect = function() end } end,
		clock = function() return T end,
		jobId = job,
		costCap = options.costCap,
	}
	local counter = 0
	local instance = setmetatable({ owner = services.OwnerService, services = services }, { __index = OverlordService })
	local fired = {}
	instance.signal = {
		FireAllClients = function(_, ...)
			table.insert(fired, { ... })
		end,
	}
	instance:setup(deps, {
		messaging = views.MessagingService,
		memory = views.MemoryStoreService,
		auditStore = dataStores:GetDataStore("OverlordAudit"),
		comboStore = dataStores:GetDataStore("OverlordCombos"),
		customStore = dataStores:GetDataStore("OverlordCustoms"),
		scheduleStore = dataStores:GetDataStore("OverlordSchedule"),
		textService = filter,
		teleport = views.TeleportService,
		wait = function() end,
		isTest = false,
		randomId = function()
			counter += 1
			return `{job}{T}x{counter}`
		end,
	})
	instance.cluster:Start()
	return { service = instance, core = instance.core, cluster = instance.cluster, fired = fired, job = job }
end

local me = game.join("ExtOwner", OWNER_ID)
local fake = game.join("ExtLookalike", 999777)
fake.Name = "XxxXxxX_77797"

local function run(server, action: string, payload: any)
	return server.service:handle(me, action, payload)
end
local function advance(seconds: number)
	setTime(T + seconds)
end
local function presetIds(result): { [string]: boolean }
	local out = {}
	for _, preset in result.data.presets do
		out[preset.id] = true
	end
	return out
end
local function clearEvents(...)
	for _, server in { ... } do
		server.core:stopAll()
	end
end

local A = makeServer("job-A")
local B = makeServer("job-B")

-- Security -------------------------------------------------------------------------------
game.check("a non-owner is refused for every new action", function()
	resetStores()
	local published = #cloud.published
	local payloads = {
		Announce = { text = "hi", style = "banner", scope = { k = "all" } },
		ScheduleAdd = { at = T + 600, label = "x", entries = { { preset = "w_golden_world" } }, scope = { k = "all" } },
		ScheduleList = {},
		ScheduleCancel = { id = "sch_x" },
		CustomSave = { name = "Mine", effects = { { effect = "Weather", params = {} } } },
		CustomList = {},
		CustomDelete = { id = "custom_x" },
	}
	for _, action in { "Announce", "ScheduleAdd", "ScheduleList", "ScheduleCancel", "CustomSave", "CustomList", "CustomDelete" } do
		assert(Protocol.OverlordAction[action] == action, `{action} is in the protocol`)
		local result = A.service:handle(fake, action, payloads[action])
		assert(result.ok == false and result.code == "not_owner", `{action} was not refused: {tostring(result.code)}`)
	end
	assert(#cloud.published == published and #A.fired == 0 and #B.fired == 0, "nothing was sent")
	assert(Engine.readStore("OverlordCustoms", "owner") == nil and Engine.readStore("OverlordSchedule", "owner") == nil, "nothing was stored")
	-- a forged command from a non-owner id is dropped by every server
	local before = #B.fired
	A.cluster.deps.messaging:PublishAsync("OverlordV1", { v = 1, id = "forged0001", n = "n", t = T, x = T + 60, by = 12345, a = "announce", s = { k = "all" }, tx = "pwned", sy = "banner", sc = 6 })
	assert(#B.fired == before and B.cluster.lastRefusal == "not_owner", "forged announce refused")
end)

-- Announcements --------------------------------------------------------------------------
game.check("an announcement is filtered, delivered to every targeted server and rate limited", function()
	filter.banned = { "badword" }
	local calls = #filter.calls
	local result = run(A, "Announce", { text = "  Welcome badword fans  ", style = "banner", seconds = 8, scope = { k = "all" } })
	assert(result.ok, tostring(result.code))
	assert(result.data.text == "Welcome ####### fans", `filtered text: {result.data.text}`)
	assert(filter.calls[calls + 1].userId == OWNER_ID and filter.calls[calls + 1].text == "Welcome badword fans", "filtered as the owner, trimmed")
	for _, server in { A, B } do
		assert(#server.fired == 1, `{server.job} fired {#server.fired} times`)
		local args = server.fired[1]
		assert(args[1] == "Announce" and args[2].text == "Welcome ####### fans" and args[2].style == "banner" and args[2].seconds == 8, "client payload")
	end
	-- 1 per 10 seconds
	advance(5)
	local again = run(A, "Announce", { text = "Again", style = "toast", scope = { k = "all" } })
	assert(not again.ok and again.code == "rate_limited" and #A.fired == 1 and #B.fired == 1, "rate limited, nothing sent")
	advance(6)
	local here = run(A, "Announce", { text = "Only here", style = "toast", scope = { k = "here" } })
	assert(here.ok and here.data.seconds == 6 and #A.fired == 2 and #B.fired == 1, "default seconds, scope here stays here")
	-- a replayed message is not shown twice
	local last = cloud.published[#cloud.published - 1]
	assert(last and last.data.a == "announce", "the earlier announce was published")
	advance(11)
	local huge = run(A, "Announce", { text = "Long", style = "banner", seconds = 99, scope = { k = "all" } })
	assert(huge.ok and huge.data.seconds == 15, "seconds clamped to 15")
	B.cluster:_onMessage(cloud.published[#cloud.published].data)
	assert(#B.fired == 2 and B.cluster.duplicates and B.cluster.duplicates >= 1, "replay ignored")
end)

game.check("an announcement is refused when the filter fails, and bad input sends nothing", function()
	advance(11)
	local published, firedA, firedB = #cloud.published, #A.fired, #B.fired
	filter.fail = true
	local result = run(A, "Announce", { text = "Hello", style = "banner", scope = { k = "all" } })
	filter.fail = false
	assert(not result.ok and result.code == "filter_failed", tostring(result.code))
	advance(11)
	filter.failBroadcast = true
	local second = run(A, "Announce", { text = "Hello", style = "banner", scope = { k = "all" } })
	filter.failBroadcast = false
	assert(not second.ok and second.code == "filter_failed", tostring(second.code))
	advance(11)
	local cases = {
		{ { text = "", style = "banner", scope = { k = "all" } }, "bad_request" },
		{ { text = "   ", style = "banner", scope = { k = "all" } }, "bad_request" },
		{ { text = string.rep("a", 161), style = "banner", scope = { k = "all" } }, "bad_request" },
		{ { text = "ok", style = "popup", scope = { k = "all" } }, "bad_request" },
		{ { text = "bad\nline", style = "toast", scope = { k = "all" } }, "bad_request" },
		{ { text = "ok", style = "toast", seconds = "soon", scope = { k = "all" } }, "bad_request" },
		{ { text = "ok", style = "toast", scope = { k = "everyone" } }, "bad_scope" },
		{ { text = "ok", style = "toast" }, "bad_scope" },
		{ { text = 12, style = "toast", scope = { k = "all" } }, "bad_request" },
	}
	for index, case in cases do
		advance(11)
		local refused = run(A, "Announce", case[1])
		assert(not refused.ok and refused.code == case[2], `case {index}: {tostring(refused.code)}`)
	end
	assert(#cloud.published == published and #A.fired == firedA and #B.fired == firedB, "nothing was published or shown")
	advance(11)
	local fine = run(A, "Announce", { text = string.rep("a", 160), style = "toast", scope = { k = "all" } })
	assert(fine.ok, "160 characters are fine")
end)

-- Scheduler ------------------------------------------------------------------------------
game.check("the scheduler adds, lists and cancels, and refuses bad input", function()
	resetStores()
	local at = T + 300
	local added = run(A, "ScheduleAdd", { at = at, label = "Golden hour", entries = { { preset = "w_golden_world", overrides = { duration = 120 } } }, scope = { k = "all" } })
	assert(added.ok and type(added.data.id) == "string", tostring(added.code))
	local listed = run(B, "ScheduleList", {})
	assert(listed.ok and #listed.data.items == 1, "the other server sees it too")
	local item = listed.data.items[1]
	assert(item.id == added.data.id and item.at == at and item.label == "Golden hour" and item.status == "pending" and item.scope.k == "all" and item.ranAt == nil, "item shape")
	assert(item.entries == nil, "entries are not echoed")
	filter.banned = { "badword" }
	local filtered = run(A, "ScheduleAdd", { at = at + 10, label = "badword hour", entries = { { preset = "w_golden_world" } }, scope = { k = "all" } })
	assert(filtered.ok and run(A, "ScheduleList", {}).data.items[2].label == "####### hour", "label filtered")
	filter.banned = {}

	local cancel = run(A, "ScheduleCancel", { id = added.data.id })
	assert(cancel.ok and run(A, "ScheduleList", {}).data.items[1].status == "cancelled", "cancelled")
	assert(run(A, "ScheduleCancel", { id = added.data.id }).code == "not_pending", "cannot cancel twice")
	assert(run(A, "ScheduleCancel", { id = "sch_none" }).code == "unknown_item", "unknown id")
	assert(run(A, "ScheduleCancel", { id = 5 }).code == "bad_request", "bad id")

	local function add(patch)
		local payload = { at = T + 300, label = "Test", entries = { { preset = "w_golden_world" } }, scope = { k = "all" } }
		for k, v in patch do
			payload[k] = if v == "nil" then nil else v
		end
		return run(A, "ScheduleAdd", payload)
	end
	assert(add({ at = T + 30 }).code == "bad_time", "too soon")
	assert(add({ at = T + 59 }).code == "bad_time", "just under a minute")
	assert(add({ at = T + 31 * 86400 }).code == "bad_time", "too far")
	assert(add({ at = T - 500 }).code == "bad_time", "in the past")
	assert(add({ at = 0 / 0 }).code == "bad_time", "NaN")
	assert(add({ at = "soon" }).code == "bad_time", "text")
	assert(add({ at = T + 60 }).ok, "exactly a minute")
	assert(add({ at = T + 30 * 86400 }).ok, "exactly 30 days")
	assert(add({ entries = { { preset = "no_such_preset" } } }).code == "unknown_preset", "unknown preset")
	assert(add({ entries = { { preset = "custom_zzz" } } }).code == "unknown_preset", "unknown custom")
	assert(add({ entries = {} }).code == "bad_request" and add({ entries = "nope" }).code == "bad_request", "bad entries")
	assert(add({ entries = { { preset = "w_golden_world" }, { preset = "w_golden_world" } } }).code ~= nil, "conflict refused")
	assert(string.find(add({ entries = { { preset = "w_golden_world" }, { preset = "w_golden_world" } } }).code, "^entries_conflict") ~= nil, "same channel twice")
	assert(string.find(add({ entries = { { preset = "x_winter_gravity" } } }).code, "event_mode_required") ~= nil, "gameplay preset needs event mode")
	assert(add({ entries = { { preset = "x_winter_gravity" } }, eventMode = true }).ok, "with event mode")
	assert(string.find(add({ entries = { { preset = "w_golden_world", overrides = { duration = -1 } } } }).code, "^bad_params") ~= nil, "bad override")
	assert(add({ label = "" }).code == "bad_request" and add({ label = string.rep("x", 41) }).code == "bad_request", "label length")
	assert(add({ scope = { k = "nowhere" } }).code == "bad_scope", "scope")
	assert(add({ combo = "no_combo", entries = "nil" }).code == "unknown_item", "unknown combo")
	filter.fail = true
	assert(add({}).code == "filter_failed", "label needs the filter")
	filter.fail = false
	-- the cost cap, as Activate applies it
	local capped = makeServer("job-cap", { costCap = 1 })
	assert(string.find(capped.service:handle(me, "ScheduleAdd", { at = T + 300, label = "Heavy", entries = { { preset = "w_golden_world" } }, scope = { k = "all" } }).code, "performance_cap") ~= nil, "cost cap")
	capped.cluster:Stop()
	-- a saved combo works
	assert(run(A, "SaveCombo", { id = "combo_one", name = "Combo One", entries = { { preset = "w_golden_world" } } }).ok)
	local fromCombo = add({ combo = "combo_one", entries = "nil" })
	assert(fromCombo.ok, tostring(fromCombo.code))
end)

game.check("the schedule keeps at most 100 items and drops the oldest finished first", function()
	resetStores()
	local items = {}
	for index = 1, 100 do
		table.insert(items, { id = `sch_old{index}`, at = T + index, label = "old", scope = { k = "all" }, entries = { { preset = "w_golden_world" } }, status = if index == 1 then "pending" elseif index % 2 == 0 then "done" else "missed", by = OWNER_ID, ranAt = T })
	end
	Engine.writeStore("OverlordSchedule", "owner", items)
	local added = run(A, "ScheduleAdd", { at = T + 500, label = "New", entries = { { preset = "w_golden_world" } }, scope = { k = "all" } })
	assert(added.ok, tostring(added.code))
	local list = run(A, "ScheduleList", {}).data.items
	assert(#list == 100, `{#list} items`)
	local ids = {}
	for _, item in list do
		ids[item.id] = true
	end
	assert(ids.sch_old1 and not ids.sch_old2 and ids.sch_old3 and ids[added.data.id], "the oldest finished item (old2) went, the pending one stayed")
	-- all pending: full
	for _, item in items do
		item.status = "pending"
	end
	Engine.writeStore("OverlordSchedule", "owner", items)
	assert(run(A, "ScheduleAdd", { at = T + 500, label = "New", entries = { { preset = "w_golden_world" } }, scope = { k = "all" } }).code == "schedule_full", "full of pending items")
end)

game.check("a due item runs exactly once across two servers and a late unclaimed item becomes missed", function()
	resetStores()
	clearEvents(A, B)
	local at = T + 120
	local one = run(A, "ScheduleAdd", { at = at, label = "Once", entries = { { preset = "w_golden_world", overrides = { duration = 600 } } }, scope = { k = "all" } })
	assert(one.ok)
	-- not due yet
	assert(A.service:_scheduleTick(true) + B.service:_scheduleTick(true) == 0 and #A.core.active == 0, "nothing before its time")
	setTime(at + 1)
	local ranA = A.service:_scheduleTick(true)
	local ranB = B.service:_scheduleTick(true)
	assert(ranA + ranB == 1, `ran {ranA} + {ranB} times`)
	assert(#A.core.active == 1 and #B.core.active == 1, "running on both servers (the scope was all)")
	local item = run(B, "ScheduleList", {}).data.items[1]
	assert(item.status == "done" and item.ranAt == at + 1 and (item.ranBy == "job-A" or item.ranBy == "job-B"), "marked done")
	assert(A.service:_scheduleTick(true) + B.service:_scheduleTick(true) == 0 and #A.core.active == 1, "never again")
	-- the claim itself is exclusive, and the throttle holds
	assert(not A.service:_claim(one.data.id) and not B.service:_claim(one.data.id), "claimed already")
	local first, second = A.service:_claim("fresh_item"), B.service:_claim("fresh_item")
	assert(first ~= second, "exactly one server wins a claim")
	assert(A.service:_scheduleTick() == 0, "throttled to every 30 s")

	-- two servers racing on a stale list: only one runs
	clearEvents(A, B)
	local race = run(A, "ScheduleAdd", { at = T + 120, label = "Race", entries = { { preset = "p_glow_aura" } }, scope = { k = "all" } })
	assert(race.ok, tostring(race.code))
	setTime(T + 125)
	local stale = A.service:_readList(A.service.scheduleStore)
	local total = 0
	for _, server in { A, B } do
		local item2
		for _, candidate in stale do
			if candidate.id == race.data.id then
				item2 = candidate
			end
		end
		if server.service:_claim(item2.id) and server.service:_runScheduled(item2) then
			total += 1
		end
	end
	assert(total == 1, `raced and ran {total} times`)

	-- late and unclaimed
	clearEvents(A, B)
	local late = run(A, "ScheduleAdd", { at = T + 120, label = "Late", entries = { { preset = "w_golden_world" } }, scope = { k = "all" } })
	assert(late.ok)
	setTime(T + 120 + 601)
	assert(A.service:_scheduleTick(true) + B.service:_scheduleTick(true) == 0, "too late to run")
	local missed
	for _, entry in run(A, "ScheduleList", {}).data.items do
		if entry.id == late.data.id then
			missed = entry
		end
	end
	assert(missed and missed.status == "missed" and missed.ranAt == nil and #A.core.active == 0 and #B.core.active == 0, "missed, and not run")
	-- cancelled items never run
	clearEvents(A, B)
	local cancelled = run(A, "ScheduleAdd", { at = T + 120, label = "Never", entries = { { preset = "w_golden_world" } }, scope = { k = "all" } })
	run(A, "ScheduleCancel", { id = cancelled.data.id })
	setTime(T + 130)
	assert(A.service:_scheduleTick(true) + B.service:_scheduleTick(true) == 0 and #A.core.active == 0, "cancelled stays quiet")
	-- a refused run is reported, not hidden
	local owned = run(A, "ScheduleAdd", { at = T + 120, label = "Clash", entries = { { preset = "w_golden_world" } }, scope = { k = "here" } })
	setTime(T + 125)
	A.core:activate({ userId = OWNER_ID, isOwner = true }, { { preset = "p_glow_aura" } }, {})
	local clash = run(A, "ScheduleAdd", { at = T + 120, label = "Clash2", entries = { { preset = "p_glow_aura" } }, scope = { k = "here" } })
	assert(owned.ok and clash.ok)
	setTime(T + 200)
	A.service:_scheduleTick(true)
	for _, entry in run(A, "ScheduleList", {}).data.items do
		if entry.id == clash.data.id then
			assert(entry.status == "missed", "a run the core refused is marked missed")
		end
	end
	clearEvents(A, B)
end)

-- Custom events --------------------------------------------------------------------------
local SNOW = { effect = "Weather", params = { kind = "snow", rate = 30, wind = 1, size = 0.4, color = { 255, 255, 255 } } }
local FROST = { effect = "LightingTheme", params = { theme = "frost" } }

game.check("a custom event is validated like a preset", function()
	resetStores()
	local function save(patch)
		local payload = { name = "Cold Night", description = "Snow in frost light", effects = { SNOW, FROST } }
		for k, v in patch do
			payload[k] = if v == "nil" then nil else v
		end
		return run(A, "CustomSave", payload)
	end
	assert(save({ effects = { { effect = "RunThis", params = {} } } }).code == "unknown_effect", "unknown effect")
	assert(save({ effects = { { effect = "start", params = {} } } }).code == "unknown_effect", "no module names from outside the allowlist")
	assert(save({ effects = { { effect = "Weather", params = { rate = 99999 } } } }).code == "bad_params:bad_number:rate", "out of range is refused as presets are")
	assert(save({ effects = { { effect = "Weather", params = { rate = 0 / 0 } } } }).code == "bad_params:bad_number:rate", "NaN")
	assert(save({ effects = { { effect = "Weather", params = { evil = "x" } } } }).code == "bad_params:unknown_param:evil", "unknown parameter")
	assert(save({ effects = { { effect = "Weather", params = { kind = "tornado" } } } }).code == "bad_params:bad_enum:kind", "bad option")
	assert(save({ effects = { { effect = "Weather", params = { color = { 999, 0, 0 } } } } }).code == "bad_params:bad_color:color", "bad colour")
	assert(save({ effects = { { effect = "Weather", params = "all" } } }).code == "bad_request", "params must be a table")
	assert(save({ effects = {} }).code == "too_many_effects", "none")
	local seven = {}
	for _ = 1, 7 do
		table.insert(seven, { effect = "Confetti", params = {} })
	end
	assert(save({ effects = seven }).code == "too_many_effects", "seven effects")
	assert(save({ effects = "nil" }).code == "too_many_effects", "missing")
	assert(string.find(save({ effects = { SNOW, SNOW } }).code, "^entries_conflict:weather") ~= nil, "same channel twice")
	assert(save({ name = "" }).code == "bad_request" and save({ name = string.rep("n", 41) }).code == "bad_request" and save({ name = "<b>hi</b>" }).code == "bad_request", "name rules")
	assert(save({ description = string.rep("d", 141) }).code == "bad_request", "description length")
	assert(save({ id = "../evil" }).code == "bad_request", "id shape")
	assert(save({ id = "custom_nothere" }).code == "unknown_preset", "replacing something that does not exist")
	assert(Engine.readStore("OverlordCustoms", "owner") == nil or #Engine.readStore("OverlordCustoms", "owner") <= 1, "refusals stored nothing")
	resetStores()
	filter.banned = { "badword" }
	assert(save({ effects = { { effect = "Title", params = { text = "badword" } } } }).code == "text_filtered", "player-visible text parameters are filtered")
	filter.banned = {}
	filter.fail = true
	assert(save({}).code == "filter_failed", "no filter, no save")
	filter.fail = false
	assert(Engine.readStore("OverlordCustoms", "owner") == nil, "still nothing stored")
	local capped = makeServer("job-cap2", { costCap = 3 })
	assert(string.find(capped.service:handle(me, "CustomSave", { name = "Heavy", effects = { SNOW, FROST } }).code, "performance_cap") ~= nil, "cost cap")
	capped.cluster:Stop()
	-- out of range duration is clamped, not trusted
	filter.banned = { "badword" }
	local ok = save({ duration = 999999, name = "badword Night", description = "Cold" })
	filter.banned = {}
	assert(ok.ok, tostring(ok.code))
	local item = ok.data.items[1]
	assert(item.duration == 21600 and item.name == "####### Night" and item.description == "Cold" and #item.effects == 2, "stored filtered and clamped")
	assert(string.find(item.id, "^custom_%w+$") and #item.id <= 32, "id shape " .. item.id)
	assert(item.effects[1].params.rate ~= nil and item.effects[1].params.wind ~= nil, "defaults filled in")
	run(A, "CustomDelete", { id = item.id })
end)

game.check("a saved custom appears in the catalogue on every server, activates, and deletes", function()
	resetStores()
	clearEvents(A, B)
	local cat = run(A, "Catalogue", {})
	local effect = cat.data.effects.Weather
	assert(effect.name == "Weather" and type(effect.description) == "string" and #effect.description > 10, "effect description")
	assert(effect.params.rate.type == "number" and effect.params.rate.min and effect.params.rate.max and effect.params.rate.default, "number rules")
	assert(type(cat.data.effects.LightingTheme.params.theme.options) == "table" and cat.data.effects.LightingTheme.params.theme.default, "enum options")
	assert(cat.data.effects.Title.params.text.maxLen == 28, "string rules")
	for id, entry in cat.data.effects do
		assert(entry.name == id and #entry.description > 0, id .. " describes itself")
	end

	local saved = run(A, "CustomSave", { name = "Cold Night", description = "Snow in frost light", effects = { SNOW, FROST } })
	assert(saved.ok, tostring(saved.code))
	local id = saved.data.id
	for _, server in { A, B } do
		local catalogue = run(server, "Catalogue", {})
		assert(presetIds(catalogue)[id], `{server.job} lists the custom`)
		local category = false
		for _, c in catalogue.data.categories do
			category = category or c.id == "Custom"
		end
		assert(category, "Custom category")
		for _, preset in catalogue.data.presets do
			if preset.id == id then
				assert(preset.category == "Custom" and preset.name == "Cold Night" and #preset.effects == 2 and preset.duration == 300, "summary")
			end
		end
	end
	assert(#run(B, "CustomList", {}).data.items == 1 and run(B, "CustomList", {}).data.items[1].id == id, "list")
	-- a server that starts later loads it
	local late = makeServer("job-late")
	assert(presetIds(run(late, "Catalogue", {}))[id], "loaded from the DataStore on start")
	late.cluster:Stop()

	-- works wherever a preset id is accepted
	local preview = run(A, "Preview", { preset = id, seconds = 10 })
	assert(preview.ok and A.core:isActive(id), "preview")
	clearEvents(A)
	local active = run(A, "Activate", { entries = { { preset = id, overrides = { duration = 60 } } }, scope = { k = "all" } })
	assert(active.ok and A.core:isActive(id) and B.core:isActive(id), "activates on both servers")
	clearEvents(A, B)
	assert(run(A, "SaveCombo", { id = "combo_custom", name = "With Custom", entries = { { preset = id }, { preset = "p_glow_aura" } } }).ok, "combo")
	assert(run(A, "ScheduleAdd", { at = T + 300, label = "Custom later", entries = { { preset = id } }, scope = { k = "all" } }).ok, "schedule")

	-- replace in place
	local renamed = run(A, "CustomSave", { id = id, name = "Colder Night", effects = { FROST } })
	assert(renamed.ok and #renamed.data.items == 1 and renamed.data.items[1].name == "Colder Night", "replaced")
	for _, preset in run(B, "Catalogue", {}).data.presets do
		if preset.id == id then
			assert(preset.name == "Colder Night" and #preset.effects == 1, "other server sees the change")
		end
	end

	-- delete: gone everywhere, refused like any unknown preset
	assert(run(A, "CustomDelete", { id = "custom_nothere" }).code == "unknown_item", "unknown")
	assert(run(A, "CustomDelete", { id = id }).ok, "delete")
	for _, server in { A, B } do
		assert(not presetIds(run(server, "Catalogue", {}))[id], `{server.job} dropped it`)
		local gone = run(server, "Activate", { entries = { { preset = id } }, scope = { k = "here" } })
		assert(not gone.ok and gone.code == "unknown_preset", "unknown custom refused")
	end
	assert(#run(A, "CustomList", {}).data.items == 0, "list empty")
	local unknown = run(A, "Activate", { entries = { { preset = "custom_abcdef" } }, scope = { k = "all" } })
	assert(not unknown.ok and unknown.code == "unknown_preset", "never-saved custom refused")
end)

game.check("at most 50 customs are kept, and a missed notice is recovered by the periodic reload", function()
	resetStores()
	local items = {}
	for index = 1, 50 do
		table.insert(items, { id = `custom_s{index}`, name = `Saved {index}`, description = "", duration = 300, level = 1, effects = { SNOW } })
	end
	Engine.writeStore("OverlordCustoms", "owner", items)
	local over = run(A, "CustomSave", { name = "One too many", effects = { FROST } })
	assert(not over.ok and over.code == "custom_limit", tostring(over.code))
	assert(run(A, "CustomSave", { id = "custom_s7", name = "Renamed seven", effects = { FROST } }).ok, "replacing at the cap is fine")
	-- server B misses the notice
	cloud.dropFor["job-B"] = true
	assert(run(A, "CustomDelete", { id = "custom_s8" }).ok)
	cloud.dropFor["job-B"] = nil
	assert(presetIds(run(B, "Catalogue", {}))["custom_s8"], "B has not heard yet")
	advance(301)
	B.service:_housekeeping()
	assert(not presetIds(run(B, "Catalogue", {}))["custom_s8"] and presetIds(run(B, "Catalogue", {}))["custom_s9"], "B reloaded on its own")
	resetStores()
	A.service:_loadCustoms()
	B.service:_loadCustoms()
end)

-- Limits -----------------------------------------------------------------------------------
game.check("payload size limits hold", function()
	resetStores()
	local jobs = {}
	for index = 1, 20 do
		table.insert(jobs, string.rep("j", 60) .. index)
	end
	local entries = {}
	for _ = 1, 8 do
		table.insert(entries, { preset = "p_glow_aura", overrides = { duration = 60, intensity = 1.5, color = { 1, 2, 3 } } })
	end
	local big = run(A, "ScheduleAdd", { at = T + 300, label = "Big", entries = entries, scope = { k = "jobs", j = jobs } })
	assert(not big.ok and (big.code == "payload_too_large" or string.find(big.code, "^entries_conflict") ~= nil), tostring(big.code))
	local bigEntries = {}
	for index = 1, 9 do
		bigEntries[index] = { preset = "p_glow_aura" }
	end
	assert(run(A, "ScheduleAdd", { at = T + 300, label = "Nine", entries = bigEntries, scope = { k = "all" } }).code == "bad_request", "more than 8 entries")
	-- a message with an oversized or malformed announcement is dropped by receivers
	local before = #B.fired
	local function forge(patch)
		local cmd = { v = 1, id = "forge" .. tostring(math.random(10000, 99999)), n = "n", t = T, x = T + 60, by = OWNER_ID, a = "announce", s = { k = "all" }, tx = "hello", sy = "banner", sc = 6 }
		for k, v in patch do
			cmd[k] = v
		end
		B.cluster:_onMessage(cmd)
		return B.cluster.lastRefusal
	end
	assert(forge({ tx = string.rep("a", 641) }) == "bad_command", "text too long")
	assert(forge({ tx = string.rep("a", 161) }) == "bad_command", "161 characters")
	assert(forge({ sy = "script" }) == "bad_command", "style")
	assert(forge({ sc = 500 }) == "bad_command", "seconds")
	assert(forge({ tx = 5 }) == "bad_command", "text type")
	assert(#B.fired == before, "none shown")
	-- a custom with a long text parameter is refused by the parameter rules
	assert(string.find(run(A, "CustomSave", { name = "Long", effects = { { effect = "Title", params = { text = string.rep("t", 29) } } } }).code, "^bad_params") ~= nil, "string parameter length")
	assert(run(A, "CustomSave", { name = "Long", effects = { SNOW }, description = string.rep("d", 140) }).ok, "140 characters of description are fine")
	resetStores()
end)

process.exit(if game.finish() == 0 then 0 else 1)
