-- The owner's event system (Admin Abuse v2 / Overlord), with fake MessagingService,
-- MemoryStoreService, DataStoreService and TeleportService:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/overlord_test.luau build/game.rbxl
-- Covers: non-owners refused for every action; the catalogue validates (100+ presets, unique,
-- known effects, no colour-swap duplicates); activation restores everything on stop (every
-- preset); combining and conflicts; publishing to a second server; a new server catching up;
-- a dropped message recovered by reconciliation; duplicate and expired commands; emergency
-- restore; the audit log. Live multi-server behaviour still needs owner testing (DECISIONS 22).

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl")
local world, Engine, services = game.world, game.Engine, game.services

local function load(path: string)
	return world.require(world.find(path))
end
local EventPresets = load("ReplicatedStorage.Shared.Config.EventPresets")
local Protocol = load("ReplicatedStorage.Shared.Protocol")
local Overlord = load("ServerScriptService.Server.Events.Overlord")
local Cluster = load("ServerScriptService.Server.Events.Cluster")
local Registry = load("ServerScriptService.Server.Events.Registry")
local Params = load("ServerScriptService.Server.Events.Params")

local OWNER_ID = 8722595934
local T = 1000
local cloud = Engine.newCloud()
local function setTime(t: number)
	T = t
	cloud.time = t
end

-- One fake server: own lighting, gravity, effect folders and players, shared cloud
local function makeServer(job: string, options: any?)
	options = options or {}
	local lighting = world.Instance.new("Lighting")
	local Color3 = roblox.Color3
	lighting.Ambient = Color3.fromRGB(70, 70, 70)
	lighting.OutdoorAmbient = Color3.fromRGB(100, 100, 110)
	lighting.Brightness = 2
	lighting.ColorShift_Top = Color3.fromRGB(0, 0, 0)
	lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	lighting.ExposureCompensation = 0
	lighting.ClockTime = 14
	local replicated = world.Instance.new("Folder")
	local views = cloud:server(job)
	local gravity = { Gravity = 196.2 }
	local deps = {
		lighting = lighting,
		workspace = gravity,
		replicated = replicated,
		fxRoot = world.Instance.new("Folder"),
		worldRoot = world.Instance.new("Folder"),
		players = function() return {} end,
		owners = function() return {} end,
		inMatch = function() return false end,
		matchActive = function() return options.matchActive == true end,
		center = function() return roblox.Vector3.new(0, 10, 0) end,
		onCharacter = function() return { Disconnect = function() end } end,
		clock = function() return T end,
		jobId = job,
		costCap = options.costCap,
	}
	local core = Overlord.new(deps)
	local counter = 0
	local cluster = Cluster.new(core, {
		messaging = views.MessagingService,
		memory = views.MemoryStoreService,
		auditStore = Engine.services.DataStoreService:GetDataStore("OverlordAudit"),
		clock = deps.clock,
		wait = function() end,
		jobId = job,
		isTest = options.isTest,
		isOwnerId = function(id) return services.OwnerService:isOwnerId(id) end,
		playerCount = function() return 3 end,
		randomId = function()
			counter += 1
			return `{job}{T}x{counter}`
		end,
	})
	return { core = core, cluster = cluster, deps = deps, lighting = lighting, gravity = gravity, views = views }
end

local owner = { userId = OWNER_ID, isOwner = true }
local stranger = { userId = 12345, isOwner = false }

local function snapshot(server)
	local out = {}
	for _, name in { "Ambient", "OutdoorAmbient", "Brightness", "ColorShift_Top", "ColorShift_Bottom", "ExposureCompensation", "ClockTime" } do
		out[name] = server.lighting[name]
	end
	out.gravity = server.gravity.Gravity
	out.children = #server.lighting:GetChildren()
	out.fx = #server.deps.fxRoot:GetChildren()
	out.world = #server.deps.worldRoot:GetChildren()
	out.season = server.deps.replicated:GetAttribute("SeasonOverride")
	return out
end
local function sameSnapshot(a, b): string?
	for key, value in a do
		if b[key] ~= value then
			return `{key}: {tostring(value)} became {tostring(b[key])}`
		end
	end
	return nil
end
local function activeCount(server): number
	return #server.core.active
end

-- 1. Security ------------------------------------------------------------------------------
game.check("a non-owner is refused for every action", function()
	local ownerPlayer = game.join("TheOwner", OWNER_ID)
	local fake = game.join("OwnerLookalike", 999001)
	fake.Name = "XxxXxxX_77797"
	local service = services.OverlordService
	assert(service.core and service.cluster, "the real service started")
	local count = 0
	for _, action in Protocol.OverlordAction do
		count += 1
		local result = service:handle(fake, action, { entries = { { preset = "w_golden_world" } }, scope = { k = "all" }, preset = "w_golden_world", jobId = "x", id = "abc", name = "n", target = "t" })
		assert(result.ok == false and result.code == "not_owner", `{action} was not refused: {tostring(result.code)}`)
	end
	assert(count >= 14, "all actions covered")
	assert(#service.core.active == 0 and #services.OverlordService.cluster:servers() >= 0, "nothing ran")
	-- through the real remote too
	local mark = game.mark()
	game.request("OverlordRequest", fake, 7, "Activate", { entries = { { preset = "w_golden_world" } }, scope = { k = "all" } })
	task = game.task
	game.task.wait(0.1)
	assert(#service.core.active == 0, "the remote did nothing for a stranger")
	local reply = game.lastSent("OverlordEvent", "Result", fake)
	assert(reply ~= nil or true, "reply optional")
	-- the owner is allowed
	local result = service:handle(ownerPlayer, "State", {})
	assert(result.ok, "owner may read state")
	local junk = service:handle(ownerPlayer, "NoSuchAction", {})
	assert(junk.ok == false and junk.code == "bad_request", "unknown action refused")
	local bad = service:handle(ownerPlayer, "Activate", { entries = { { preset = "no_such" } }, scope = { k = "here" } })
	assert(bad.ok == false and bad.code == "unknown_preset", "unknown preset refused: " .. tostring(bad.code))
	local lookalike = service:handle(ownerPlayer, "Activate", { entries = { { preset = "w_golden_world", overrides = { duration = -5 } } }, scope = { k = "here" } })
	assert(lookalike.ok == false, "bad duration refused")
	service.core:stopAll()
end)

-- 2. The catalogue ----------------------------------------------------------------------------
local function signature(preset)
	local ids = {}
	for _, spec in preset.effects do
		table.insert(ids, spec.effect)
	end
	table.sort(ids)
	return table.concat(ids, "+")
end
-- Near duplicate: same effect set and every non-colour setting equal (numbers within 15 percent)
local function nearDuplicate(a, b): boolean
	if signature(a) ~= signature(b) then
		return false
	end
	local used = {}
	for _, one in a.effects do
		local matched = false
		for index, two in b.effects do
			if not used[index] and two.effect == one.effect then
				local schema = Registry.effects[one.effect].params
				local same = true
				for name, spec in schema do
					local x, y = one.params[name], two.params[name]
					if x == nil then x = spec.default end
					if y == nil then y = spec.default end
					if spec.type == "number" then
						if math.abs(x - y) > 0.15 * math.max(math.abs(x), math.abs(y), 1e-6) then
							same = false
						end
					elseif spec.type ~= "color" and x ~= y then
						same = false
					end
				end
				if same then
					used[index] = true
					matched = true
					break
				end
			end
		end
		if not matched then
			return false
		end
	end
	return true
end

game.check("the catalogue validates: 100+ unique presets, known effects, no near duplicates", function()
	local list = EventPresets.List
	assert(#list >= 100, `only {#list} presets`)
	local ids, names, perCategory = {}, {}, {}
	for _, preset in list do
		assert(not ids[preset.id], "duplicate id " .. preset.id)
		ids[preset.id] = true
		assert(not names[preset.name], "duplicate name " .. preset.name)
		names[preset.name] = true
		perCategory[preset.category] = (perCategory[preset.category] or 0) + 1
		assert(preset.level >= 1 and preset.level <= 4, preset.id .. " level")
		assert(preset.duration > 0 and #preset.effects >= 1 and preset.description ~= "", preset.id .. " fields")
		assert(preset.onConflict == "reject" or preset.onConflict == "replace", preset.id .. " rule")
		local gameplay = false
		for _, spec in preset.effects do
			local effect = Registry.effects[spec.effect]
			assert(effect, `{preset.id}: effect {spec.effect} does not exist`)
			local clean, why = Params.clean(effect.params, spec.params)
			assert(clean, `{preset.id}: {spec.effect} params invalid ({tostring(why)})`)
			gameplay = gameplay or effect.gameplay
			assert(not effect.ownerOnly or preset.category == "Owner", `{preset.id}: owner effect outside the Owner category`)
		end
		assert(preset.eventMode == gameplay, preset.id .. " eventMode flag")
		for _, text in { preset.name, preset.description } do
			assert(not string.find(text, "\xE2\x80\x94") and not string.find(text, "[\xF0-\xF7]"), preset.id .. " has an em dash or emoji")
		end
		assert(preset.ownerOnly == (preset.category == "Owner"), preset.id .. " owner flag")
	end
	assert(perCategory.Thanksgiving == 20 and perCategory.Christmas == 20, "20 Thanksgiving and 20 Christmas")
	assert(perCategory.World >= 20 and perCategory.Player >= 15 and perCategory.Environment >= 12 and perCategory.Spectacle >= 12 and perCategory.Owner == 20, "categories A to E filled")
	for i = 1, #list do
		for j = i + 1, #list do
			assert(not nearDuplicate(list[i], list[j]), `near duplicates: {list[i].id} and {list[j].id}`)
		end
	end
	-- the validator itself catches a colour swap
	local clone = table.clone(list[1])
	clone.effects = {}
	for _, spec in list[1].effects do
		local params = table.clone(spec.params)
		if params.color then params.color = { 1, 2, 3 } end
		table.insert(clone.effects, { effect = spec.effect, params = params })
	end
	assert(nearDuplicate(list[1], clone), "a colour swap is detected")
	-- sci-fi, never a farm
	for _, preset in list do
		assert(not string.find(string.lower(preset.name .. preset.description), "farm"), preset.id .. " mentions a farm")
	end
end)

game.check("no effect touches inventories, ownership or progression, and nothing runs code", function()
	local folder = world.find("ServerScriptService.Server.Events")
	for _, item in folder:GetDescendants() do
		if item:IsA("ModuleScript") then
			for _, banned in { "DataService", "CurrencyService", "ProgressionService", "PowerService", "loadstring", "require(game" } do
				assert(not string.find(item.Source, banned, 1, true), `{item.Name} mentions {banned}`)
			end
		end
	end
end)

-- 3. Local activation and restore ------------------------------------------------------------
game.check("every preset starts and stops, restoring lighting and all state exactly", function()
	local server = makeServer("job-solo")
	local before = snapshot(server)
	for _, preset in EventPresets.List do
		local ok, result = server.core:activate(owner, { { preset = preset.id } }, { eventMode = true })
		assert(ok, `{preset.id} failed to start: {tostring(result)}`)
		local id = result.ids[1]
		assert(server.core.byId[id], "recorded")
		assert(server.core:stop(id), "stopped")
		local why = sameSnapshot(before, snapshot(server))
		assert(not why, `{preset.id} left a change behind ({why})`)
		assert(activeCount(server) == 0 and not server.core.eventMode, preset.id .. " left state")
	end
end)

game.check("lighting really changes while an event runs", function()
	local server = makeServer("job-look")
	local before = snapshot(server)
	local ok, result = server.core:activate(owner, { { preset = "t_world_takeover" } }, {})
	assert(ok, tostring(result))
	local during = snapshot(server)
	assert(sameSnapshot(before, during) ~= nil, "something changed")
	assert(during.season == "Thanksgiving", "season set")
	assert(during.fx >= 1 and during.world == 0, "weather record published")
	server.core:stop(result.ids[1])
	assert(sameSnapshot(before, snapshot(server)) == nil, "restored")
end)

game.check("durations expire and restore", function()
	local server = makeServer("job-time")
	local before = snapshot(server)
	setTime(2000)
	local ok = server.core:activate(owner, { { preset = "w_neon_takeover", overrides = { duration = 30 } } }, {})
	assert(ok and activeCount(server) == 1)
	setTime(2029)
	assert(#server.core:tick() == 0 and activeCount(server) == 1, "still running")
	setTime(2031)
	assert(#server.core:tick() == 1 and activeCount(server) == 0, "ended")
	assert(sameSnapshot(before, snapshot(server)) == nil, "restored after expiry")
end)

-- 4. Combining -------------------------------------------------------------------------------
game.check("compatible presets combine; conflicts are refused with a reason", function()
	local server = makeServer("job-mix")
	local ok = server.core:activate(owner, { { preset = "t_falling_leaves" }, { preset = "p_glow_aura" }, { preset = "t_golden_lighting" } }, {})
	assert(ok and activeCount(server) == 3, "three together")
	local again, code = server.core:activate(owner, { { preset = "e_gentle_rain" } }, {})
	assert(not again and string.find(code, "^channel_conflict:weather"), "weather conflict: " .. tostring(code))
	local tags, tagCode = server.core:activate(owner, { { preset = "x_holo_snowflakes" } }, {})
	assert(not tags and string.find(tagCode, "^incompatible_tags"), "autumn and winter clash: " .. tostring(tagCode))
	local both, bothCode = server.core:activate(owner, { { preset = "e_snow" }, { preset = "x_beautiful_snowfall" } }, {})
	assert(not both, "two weathers in one request: " .. tostring(bothCode))
	-- nothing half-started
	assert(activeCount(server) == 3)
	-- replace rule
	local replaced, info = server.core:activate(owner, { { preset = "o_reality_reset" } }, {})
	assert(replaced and #info.replaced == 1, "reality reset replaces the lighting event")
	server.core:stopAll()
	-- gameplay only in event mode
	local g, gCode = server.core:activate(owner, { { preset = "e_low_gravity" } }, {})
	assert(not g and gCode == "event_mode_required", tostring(gCode))
	assert(server.gravity.Gravity == 196.2, "gravity untouched")
	local g2 = server.core:activate(owner, { { preset = "e_low_gravity" } }, { eventMode = true })
	assert(g2 and math.abs(server.gravity.Gravity - 196.2 * 0.4) < 1e-6 and server.core.eventMode, "gravity lowered")
	local ongoing = server.core:activate(owner, { { preset = "e_moon_jump" } }, {})
	assert(not ongoing, "channel conflict on gravity")
	server.core:stopAll()
	assert(server.gravity.Gravity == 196.2 and not server.core.eventMode, "gravity restored, event mode off")
	-- not while a match runs
	local busy = makeServer("job-busy", { matchActive = true })
	local m, mCode = busy.core:activate(owner, { { preset = "e_low_gravity" } }, { eventMode = true })
	assert(not m and mCode == "match_in_progress", tostring(mCode))
	-- performance cap
	local small = makeServer("job-small", { costCap = 30 })
	local c, cCode = small.core:activate(owner, { { preset = "s_energy_display" } }, {})
	assert(not c and cCode == "performance_cap", tostring(cCode))
	-- non-owner and owner-only
	local n, nCode = server.core:activate(stranger, { { preset = "w_golden_world" } }, {})
	assert(not n and nCode == "not_owner")
	-- bad parameters
	local b, bCode = server.core:activate(owner, { { preset = "w_golden_world", overrides = { intensity = 99 } } }, {})
	assert(not b and string.find(bCode, "^bad_params"), tostring(bCode))
	local tinted = server.core:activate(owner, { { preset = "t_giant_tree", overrides = { color = { 10, 20, 30 }, intensity = 1.5, duration = 60 } } }, {})
	assert(tinted, "overrides accepted")
	server.core:stopAll()
end)

-- 5. Cross-server -----------------------------------------------------------------------------
local A, B, C = makeServer("job-A"), makeServer("job-B"), makeServer("job-C", { isTest = true })
for _, server in { A, B, C } do
	server.cluster:Start()
end

game.check("a published event reaches a second server, which applies it", function()
	setTime(3000)
	local result = A.cluster:issue(owner, "activate", { entries = { { preset = "t_world_takeover", overrides = { duration = 600 } } } }, { k = "all" })
	assert(result.ok and result.sync.published and result.sync.stored, "issued: " .. tostring(result.code))
	assert(A.core:isActive("t_world_takeover") and B.core:isActive("t_world_takeover") and C.core:isActive("t_world_takeover"), "all three run it")
	assert(B.deps.replicated:GetAttribute("SeasonOverride") == "Thanksgiving", "B changed its own world")
	for _, server in { A, B, C } do
		server.cluster:heartbeat()
	end
	local got = A.cluster:receivedBy(result.id)
	table.sort(got)
	assert(table.concat(got, ",") == "job-A,job-B,job-C", "receivers: " .. table.concat(got, ","))
	assert(#A.cluster:servers() == 3, "three servers registered")
	-- selected servers only
	local only = A.cluster:issue(owner, "activate", { entries = { { preset = "p_glow_aura" } } }, { k = "jobs", j = { "job-B" } })
	assert(only.ok and B.core:isActive("p_glow_aura") and not A.core:isActive("p_glow_aura") and not C.core:isActive("p_glow_aura"), "only B")
	-- the owner test server
	local test = A.cluster:issue(owner, "activate", { entries = { { preset = "p_halos" } } }, { k = "test" })
	assert(test.ok and C.core:isActive("p_halos") and not B.core:isActive("p_halos") and not A.core:isActive("p_halos"), "only the test server")
	-- stop travels too
	local stop = A.cluster:issue(owner, "stop", { target = result.id }, { k = "all" })
	assert(stop.ok and not A.core:isActive("t_world_takeover") and not B.core:isActive("t_world_takeover") and not C.core:isActive("t_world_takeover"), "stopped everywhere")
	assert(B.deps.replicated:GetAttribute("SeasonOverride") == nil, "B restored")
	A.core:stopAll(); B.core:stopAll(); C.core:stopAll()
	A.cluster:issue(owner, "stopAll", {}, { k = "all" })
end)

game.check("a new server picks up the active event from the MemoryStore", function()
	setTime(3100)
	local result = A.cluster:issue(owner, "activate", { entries = { { preset = "w_aurora_sky", overrides = { duration = 900 } }, { preset = "x_beautiful_snowfall" } } }, { k = "all" })
	assert(result.ok, tostring(result.code))
	local fresh = makeServer("job-new")
	assert(activeCount(fresh) == 0)
	fresh.cluster:Start()
	assert(fresh.core:isActive("w_aurora_sky") and fresh.core:isActive("x_beautiful_snowfall"), "new server joined the event")
	assert(fresh.lighting.ClockTime ~= 14, "its sky changed")
	-- and it ends on time there too
	setTime(3100 + 901)
	fresh.cluster:tick()
	assert(not fresh.core:isActive("w_aurora_sky"), "ended on the new server")
	A.cluster:issue(owner, "returnToDefault", {}, { k = "all" })
end)

game.check("a dropped message is recovered by reconciliation", function()
	setTime(4000)
	A.cluster:reconcile(); B.cluster:reconcile()
	cloud.dropFor["job-B"] = true
	local result = A.cluster:issue(owner, "activate", { entries = { { preset = "t_golden_leaf_storm", overrides = { duration = 900 } } } }, { k = "all" })
	assert(result.ok and A.core:isActive("t_golden_leaf_storm"), "A runs it")
	assert(not B.core:isActive("t_golden_leaf_storm"), "B missed the message")
	cloud.dropFor["job-B"] = nil
	setTime(4031)
	B.cluster:tick()
	assert(B.core:isActive("t_golden_leaf_storm"), "B caught up at its next reconcile")
	assert(B.cluster.lastSync == 4031, "sync time recorded")
	-- a missed stop is recovered as well
	cloud.dropFor["job-B"] = true
	A.cluster:issue(owner, "stop", { target = result.id }, { k = "all" })
	cloud.dropFor["job-B"] = nil
	assert(B.core:isActive("t_golden_leaf_storm"), "B missed the stop")
	setTime(4070)
	B.cluster:tick()
	assert(not B.core:isActive("t_golden_leaf_storm"), "B stopped it at the next reconcile")
	-- a failing MemoryStore is reported, not hidden
	cloud.memoryFailures = 1
	assert(B.cluster:reconcile() == false and B.cluster.syncOk == false, "failed sync flagged")
	assert(B.cluster:reconcile() == true and B.cluster.syncOk, "next one fine")
end)

game.check("failed publishing is retried; total failure is not reported as success", function()
	setTime(4200)
	cloud.publishFailures = 2
	local retried = A.cluster:issue(owner, "activate", { entries = { { preset = "p_energy_trails" } } }, { k = "all" })
	assert(retried.ok and retried.sync.published, "published on the third try")
	A.cluster:issue(owner, "stopAll", {}, { k = "all" })
	setTime(4300)
	cloud.publishFailures = 9
	cloud.memoryFailures = 9
	local failed = A.cluster:issue(owner, "activate", { entries = { { preset = "p_particle_trails" } } }, { k = "all" })
	cloud.publishFailures = 0
	cloud.memoryFailures = 0
	assert(failed.ok == false and failed.code == "global_sync_failed", "not reported ok: " .. tostring(failed.code))
	A.core:stopAll()
end)

game.check("duplicate command ids are ignored and expired commands refused", function()
	setTime(5000)
	for _, server in { A, B, C } do server.core:stopAll() end
	local cmd = { v = 1, id = "cmd-dup-0001", n = "n1", t = 5000, x = 5060, by = OWNER_ID, a = "activate", s = { k = "all" }, e = { { preset = "p_halos" } }, ev = false, st = 5000 }
	B.cluster:_onMessage(cmd)
	assert(activeCount(B) == 1, "applied once")
	B.cluster:_onMessage(table.clone(cmd))
	assert(activeCount(B) == 1 and B.cluster.duplicates == 1, "duplicate ignored")
	B.core:stopAll()
	B.cluster:_onMessage(table.clone(cmd))
	assert(activeCount(B) == 0, "a replay after stopping does not restart it")
	local old = { v = 1, id = "cmd-old-0002", n = "n2", t = 4800, x = 4860, by = OWNER_ID, a = "activate", s = { k = "all" }, e = { { preset = "p_halos" } }, ev = false, st = 4800 }
	B.cluster:_onMessage(old)
	assert(activeCount(B) == 0 and B.cluster.lastRefusal == "expired", "expired refused: " .. tostring(B.cluster.lastRefusal))
	local forged = { v = 1, id = "cmd-forged-3", n = "n3", t = 5000, x = 5060, by = 4242, a = "activate", s = { k = "all" }, e = { { preset = "p_halos" } }, ev = false, st = 5000 }
	B.cluster:_onMessage(forged)
	assert(activeCount(B) == 0 and B.cluster.lastRefusal == "not_owner", "a non-owner id is refused: " .. tostring(B.cluster.lastRefusal))
	for _, junk in { "text", 5, { v = 2 }, { v = 1, id = "x" }, { v = 1, id = "cmd-bad-0004", n = "n", t = 5000, x = 5060, by = OWNER_ID, a = "runCode", s = { k = "all" } } } do
		B.cluster:_onMessage(junk)
	end
	assert(activeCount(B) == 0, "junk ignored")
	local hostile = { v = 1, id = "cmd-hostile-5", n = "n5", t = 5000, x = 5060, by = OWNER_ID, a = "activate", s = { k = "all" }, e = { { preset = "p_halos", overrides = { duration = 1e9 } } }, ev = false, st = 5000 }
	B.cluster:_onMessage(hostile)
	assert(activeCount(B) == 0, "out-of-range parameters refused")
end)

game.check("rate limit and message size", function()
	setTime(6000)
	local refused = 0
	for _ = 1, 20 do
		local r = A.cluster:issue(owner, "restoreEnvironment", {}, { k = "here" })
		if r.code == "rate_limited" then refused += 1 end
	end
	assert(refused >= 8, `rate limit refused {refused}`)
	setTime(6100)
	local r = A.cluster:issue(owner, "restoreEnvironment", {}, { k = "here" })
	assert(r.ok, "allowed again later")
	for _, message in cloud.published do
		assert(Cluster.size(message.data) <= Cluster.MAX_BYTES, "compact payloads")
	end
end)

-- 6. Emergency controls -----------------------------------------------------------------------
game.check("emergency restore clears everything on every server", function()
	setTime(7000)
	for _, server in { A, B, C } do server.core:stopAll() end
	local baseA = snapshot(A)
	local r = A.cluster:issue(owner, "activate", { entries = { { preset = "t_golden_lighting" }, { preset = "p_glow_aura" }, { preset = "e_snow" } } }, { k = "all" })
	assert(r.ok, tostring(r.code))
	assert(activeCount(A) == 3 and activeCount(B) == 3 and activeCount(C) == 3)
	-- partial restores
	setTime(7100)
	assert(A.cluster:issue(owner, "restoreEnvironment", {}, { k = "all" }).ok)
	assert(A.core:isActive("p_glow_aura") and not A.core:isActive("t_golden_lighting") and not B.core:isActive("e_snow"), "environment restored, aura kept")
	local expected = table.clone(baseA)
	expected.fx = 1 -- the aura record is still there
	assert(sameSnapshot(expected, snapshot(A)) == nil, "lighting back: " .. tostring(sameSnapshot(expected, snapshot(A))))
	setTime(7200)
	assert(A.cluster:issue(owner, "clearEffects", {}, { k = "all" }).ok)
	assert(activeCount(A) == 0 and activeCount(B) == 0, "temporary effects cleared")
	-- gameplay + return to default
	setTime(7300)
	local g = A.cluster:issue(owner, "activate", { entries = { { preset = "e_zero_gravity" }, { preset = "x_festive_auras" } }, eventMode = true }, { k = "all" })
	assert(g.ok and A.gravity.Gravity < 20 and B.gravity.Gravity < 20 and B.core.eventMode, "gravity event on both")
	setTime(7400)
	assert(A.cluster:issue(owner, "restorePlayers", {}, { k = "all" }).ok)
	assert(A.gravity.Gravity == 196.2 and B.gravity.Gravity == 196.2 and not B.core.eventMode, "player and gameplay state restored")
	setTime(7500)
	A.cluster:issue(owner, "activate", { entries = { { preset = "o_environment_override" } } }, { k = "all" })
	B.lighting.Brightness = 99 -- something drifted
	setTime(7600)
	assert(A.cluster:issue(owner, "returnToDefault", {}, { k = "all" }).ok)
	for _, server in { A, B, C } do
		assert(activeCount(server) == 0 and #server.deps.fxRoot:GetChildren() == 0 and #server.deps.worldRoot:GetChildren() == 0, server.deps.jobId .. " is clean")
	end
	assert(sameSnapshot(baseA, snapshot(A)) == nil, "A back to default")
	assert(#A.views.MemoryStoreService:GetSortedMap("OverlordActive"):GetRangeAsync(nil, 50) == 0, "no global state left for new servers")
	-- a new server after the reset finds nothing to start
	local late = makeServer("job-late")
	late.cluster:Start()
	assert(activeCount(late) == 0, "nothing restarts")
end)

-- 7. Audit ------------------------------------------------------------------------------------
game.check("audit entries are written, bounded, and name who did what", function()
	local stored = Engine.readStore("OverlordAudit", "log")
	assert(type(stored) == "table" and #stored > 5, "entries persisted")
	local sawActivate, sawRefusal, sawRemote = false, false, false
	for _, entry in stored do
		assert(type(entry.by) == "number" and type(entry.action) == "string" and type(entry.scope) == "string" and type(entry.outcome) == "string" and type(entry.t) == "number", "entry fields")
		if entry.action == "activate" and entry.outcome == "ok" and entry.by == OWNER_ID and entry.presets[1] then sawActivate = true end
		if entry.outcome == "refused" then sawRefusal = true end
		if string.find(entry.action, "^remote:") then sawRemote = true end
	end
	assert(sawActivate and sawRefusal and sawRemote, "activation, refusal and remote entries")
	for i = 1, 260 do
		A.cluster.audit:record({ by = OWNER_ID, action = "bulk", scope = "here", presets = {}, outcome = "ok" })
	end
	assert(#Engine.readStore("OverlordAudit", "log") <= 200 and #A.cluster.audit.recent <= 200, "bounded")
	local read = services.OverlordService:handle(game.join("Owner2", OWNER_ID), "Audit", { limit = 5 })
	assert(read.ok, "owner can read the audit")
end)

game.check("combos can be saved, listed and deleted; the owner can pick a server to summon to", function()
	local service = services.OverlordService
	local me = game.join("Owner3", OWNER_ID)
	local save = service:handle(me, "SaveCombo", { id = "my_combo", name = "My Combo", entries = { { preset = "t_falling_leaves" }, { preset = "p_glow_aura" } } })
	assert(save.ok and #service:handle(me, "ListCombos", {}).data == 1, "saved")
	assert(service:handle(me, "SaveCombo", { id = "my_combo", name = "Renamed", entries = { { preset = "p_halos" } } }).ok, "renamed in place")
	assert(service:handle(me, "ListCombos", {}).data[1].name == "Renamed" and #service:handle(me, "ListCombos", {}).data == 1)
	assert(not service:handle(me, "SaveCombo", { id = "x", name = "bad<script>", entries = {} }).ok, "bad combo refused")
	assert(service:handle(me, "DeleteCombo", { id = "my_combo" }).ok and #service:handle(me, "ListCombos", {}).data == 0, "deleted")
	local catalogue = service:handle(me, "Catalogue", {})
	assert(catalogue.ok and #catalogue.data.presets >= 100 and catalogue.data.effects.Weather, "catalogue served")
	local unknown = service:handle(me, "Summon", { jobId = "no-such-server" })
	assert(not unknown.ok and unknown.code == "unknown_server")
	service.cluster:heartbeat()
	local jobs = service.cluster:servers()
	assert(#jobs >= 1, "this server is registered")
	local summon = service:handle(me, "Summon", { jobId = jobs[1].jobId })
	assert(summon.ok and #Engine.cloud.teleports == 1, "teleport requested")
	-- preview runs on this server only and restores
	local preview = service:handle(me, "Preview", { preset = "w_golden_world", seconds = 10 })
	assert(preview.ok and service.core:isActive("w_golden_world"), "preview runs")
	service.core:stopAll()
end)

process.exit(if game.finish() == 0 then 0 else 1)
