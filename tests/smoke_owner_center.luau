-- Client smoke test for the owner's Control Center (src/client/UI/OwnerCenter):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke_owner_center.luau build/game.rbxl
-- A stand-in server answers the OverlordRequest remote with fixtures (230 presets). Checks: a
-- non-owner gets no window but still sees announcements; the owner opens the Control Center
-- with P; every section builds and passes the layout audit at 1280x720 and 667x375; search
-- filters the catalogue; Activate sends the right payload with the chosen scope after a confirm;
-- refusal codes become plain sentences; Announce, ScheduleAdd and CustomSave send the right shapes.

local process = require("@lune/process")
local Client = require("./smoke/Client")

local t = Client.load(process.args[1])
local Engine = t.Engine
local roblox = t.roblox
local Enum = roblox.Enum

local ui = t.startUI({
	currencies = { money = 12000, gems = 6666 },
	selected = { power = "StrongDude", degree = 1 },
	powers = { StrongDude = { xp = 500 } },
	loadouts = {},
	passes = {},
	settings = {},
})
local Shell, gui = ui.Shell, ui.gui
local player = t.world.localPlayer
local uis = t.world.game:GetService("UserInputService")

-- Fixtures ---------------------------------------------------------------------------------

local CATEGORIES = {
	{ id = "World", name = "World transformations" },
	{ id = "Player", name = "Player effects" },
	{ id = "Environment", name = "Gravity and environment" },
	{ id = "Spectacle", name = "Spectacle and celebration" },
	{ id = "Owner", name = "Owner exclusive" },
	{ id = "Thanksgiving", name = "Thanksgiving collection" },
	{ id = "Christmas", name = "Christmas collection" },
}
local presets = {}
for i = 1, 230 do
	local category = CATEGORIES[(i - 1) % #CATEGORIES + 1].id
	table.insert(presets, {
		id = `p_{i}`,
		name = `Preset number {i}`,
		category = category,
		level = (i % 4) + 1,
		description = `Plain description of preset {i} in {category}.`,
		duration = 300,
		tags = { "light", if i % 2 == 0 then "even" else "odd" },
		effects = if i % 3 == 0 then { "LightingTheme", "Weather" } else { "LightingTheme" },
		eventMode = false,
		ownerOnly = category == "Owner",
		onConflict = "reject",
	})
end
presets[1].name = "Golden World"
presets[1].description = "The whole station bathed in low golden light."
presets[1].tags = { "golden", "light" }
presets[1].effects = { "LightingTheme", "Weather" }
table.insert(presets, { id = "p_flip", name = "Gravity Flip", category = "Environment", level = 3, description = "Gravity points up.", duration = 120, tags = { "gravity" }, effects = { "LightingTheme" }, eventMode = true, ownerOnly = false, onConflict = "reject" })

local EFFECTS = {
	LightingTheme = { name = "LightingTheme", description = "Changes the light.", group = "environment", params = { theme = { type = "enum", options = { "golden", "neon" }, default = "golden" } } },
	Weather = { name = "Weather", description = "Falling particles.", group = "spectacle", params = {
		kind = { type = "enum", options = { "rain", "snow" }, default = "rain" },
		rate = { type = "number", min = 5, max = 100, default = 30, scales = true },
		color = { type = "color", default = { 255, 255, 255 } },
	} },
}

local fixtures = {
	Catalogue = function()
		return { ok = true, data = { categories = CATEGORIES, presets = presets, effects = EFFECTS, costCap = 160 } }
	end,
	State = function()
		return { ok = true, data = { jobId = "abcdef1234567890", eventMode = false, active = { { id = "ev1", preset = "p_1", name = "Golden World", startedAt = os.time(), endsAt = os.time() + 240, origin = "here" } }, lastSync = os.time(), syncOk = true } }
	end,
	Servers = function()
		return { ok = true, data = {
			{ jobId = "abcdef1234567890", players = 4, presets = 1, events = { "ev1" }, lastSync = os.time(), heartbeat = os.time(), test = false, current = true },
			{ jobId = "zzzz9999yyyy", players = 7, presets = 0, events = {}, lastSync = os.time() - 30, heartbeat = os.time() - 5, test = true, current = false },
		} }
	end,
	Audit = function()
		return { ok = true, data = { entries = {
			{ t = os.time() - 90, by = 1, action = "remote:activate", scope = "here", presets = { "p_1" }, outcome = "applied" },
			{ t = os.time() - 30, by = 1, action = "remote:activate", scope = "all", presets = { "p_2" }, outcome = "refused", reason = "performance_cap" },
		} } }
	end,
	ListCombos = function()
		return { ok = true, data = { { id = "combo_1", name = "Evening show", entries = { { preset = "p_1" }, { preset = "p_2" } } } } }
	end,
	SaveCombo = function(payload)
		return { ok = true, data = { { id = "combo_1", name = "Evening show", entries = { { preset = "p_1" }, { preset = "p_2" } } }, { id = payload.id, name = payload.name, entries = payload.entries } } }
	end,
	DeleteCombo = function()
		return { ok = true, data = {} }
	end,
	CustomList = function()
		return { ok = true, data = { items = {} } }
	end,
	ScheduleList = function()
		return { ok = true, data = { items = { { id = "s1", at = os.time() + 3600, label = "Friday show", scope = "here", status = "pending" } } } }
	end,
	CustomSave = function()
		return { ok = true, data = { id = "custom_abc", items = { { id = "custom_abc", name = "Mine", description = "", duration = 300, level = 2, effects = {} } } } }
	end,
}
local overrides = {} -- one-shot answers by action

local servedIndex = #Engine.sent
-- Answers every OverlordRequest the interface has sent (and the ones those answers cause)
local function serve()
	while servedIndex < #Engine.sent do
		servedIndex += 1
		local entry = Engine.sent[servedIndex]
		if entry.remote == "OverlordRequest" then
			local id, action = entry.args[1], entry.args[2]
			local answer = overrides[action]
			overrides[action] = nil
			if answer == nil then
				local make = fixtures[action]
				answer = if make then make(entry.args[3]) else { ok = true, data = {} }
			end
			t.fire("OverlordEvent", "Result", id, answer)
		end
	end
	Engine.task.wait(0.03)
end

local function lastRequest(action: string, since: number?)
	local found = nil
	for index = (since or 0) + 1, #Engine.sent do
		local entry = Engine.sent[index]
		if entry.remote == "OverlordRequest" and entry.args[2] == action then
			found = entry
		end
	end
	return found
end

local function badText(root): { string }
	local found = {}
	for _, item in root:GetDescendants() do
		if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
			for _, code in utf8.codes(item.Text) do
				if code == 0x2014 or code >= 0x1F000 or (code >= 0x2600 and code <= 0x27BF) or code == 0x2B50 or code == 0xFE0F then
					table.insert(found, `{item:GetFullName()} "{item.Text}"`)
					break
				end
			end
		end
	end
	return found
end

local function smallText(root): { string }
	local found = {}
	for _, item in root:GetDescendants() do
		if (item:IsA("TextLabel") or item:IsA("TextButton")) and item.Text ~= "" and not item.TextScaled and item.TextSize < 14 then
			table.insert(found, `{item:GetFullName()} {item.TextSize}`)
		end
	end
	return found
end

-- The stand-in engine does not fire Text change signals when a test types
local function setText(box, text: string)
	box.Text = text
	Engine.signalOf(box, "Property:Text"):Fire()
	Engine.task.wait(0.03)
end

local function pressKey(key)
	Engine.signalOf(uis, "InputBegan"):Fire({ KeyCode = key, UserInputType = Enum.UserInputType.Keyboard }, false)
	Engine.task.wait(0.05)
end

local function confirmDialog()
	local dialog = t.findNamed(gui, "Dialog")
	assert(dialog, "a confirmation dialog is open")
	local body = t.findNamed(dialog, "Body")
	local text = body and body.Text or ""
	t.press(t.findNamed(dialog, "Confirm"))
	Engine.task.wait(0.1)
	return text
end

local function press(root, name: string)
	local button = t.findNamed(root, name)
	assert(button, "found " .. name)
	t.press(button)
	serve()
	return button
end

local function labelContaining(root, text: string)
	for _, item in root:GetDescendants() do
		if (item:IsA("TextLabel") or item:IsA("TextButton")) and string.find(item.Text, text, 1, true) then
			return item
		end
	end
	return nil
end

-- Non-owner ---------------------------------------------------------------------------------

local OwnerController = t.client("Controllers.OwnerController")
OwnerController:Start()
Engine.task.wait(0.1)

t.check("a non-owner gets no Control Center", function()
	assert(not Shell.hasWindow("OwnerCenter"), "no window for a non-owner")
	local before = #Engine.sent
	pressKey(Enum.KeyCode.P)
	assert(not Shell.isOpen("OwnerCenter"), "P opens nothing")
	assert(#t.sentSince(before, "OverlordRequest") == 0, "and sends nothing")
end)

t.check("an announcement broadcast shows on a non-owner client (banner and toast)", function()
	t.fire("OverlordEvent", "Announce", { text = "Server restart in five minutes", style = "banner", seconds = 5 })
	Engine.task.wait(0.05)
	local banner = t.findNamed(player.PlayerGui, "Banner")
	assert(banner and banner.Visible, "the banner is visible")
	assert(t.findText(banner, "Server restart in five minutes"), "with the sentence")
	t.fire("OverlordEvent", "Announce", { text = "Short toast message", style = "toast", seconds = 4 })
	Engine.task.wait(0.05)
	assert(t.findText(gui, "Short toast message"), "the toast shows")
	-- Junk is ignored
	t.fire("OverlordEvent", "Announce", { text = 42 })
	t.fire("OverlordEvent", "Announce", "nonsense")
	t.fire("OverlordEvent", "Announce", { text = "   " })
end)

-- Owner ---------------------------------------------------------------------------------------

player:SetAttribute("SNIsOwner", true)
-- The stand-in engine does not fire attribute signals by itself
Engine.signalOf(player, "Attribute:SNIsOwner"):Fire()
Engine.task.wait(0.2)

t.check("the owner opens the Control Center with P", function()
	assert(Shell.hasWindow("OwnerCenter"), "the window is registered for the owner")
	pressKey(Enum.KeyCode.P)
	assert(Shell.isOpen("OwnerCenter"), "P opens it")
	serve()
	local window = t.findNamed(gui, "Window_OwnerCenter")
	assert(window, "the window frame exists")
	assert(t.findNamed(window, "StatusStrip"), "the status strip exists")
	assert(t.findNamed(window, "Segment_here") and t.findNamed(window, "Segment_all") and t.findNamed(window, "Segment_test") and t.findNamed(window, "Segment_jobs"), "the scope selector has four options")
	local dock = t.findNamed(gui, "Dock")
	assert(dock and t.findNamed(dock, "Nav_OwnerCenter"), "the owner has an OWNER button in the dock (owner request, 4 Nov)")
end)

local OwnerCenter = t.client("UI.OwnerCenter")
local window = t.findNamed(gui, "Window_OwnerCenter")

t.check("the section list has the groups and all 17 sections", function()
	local expected = { "dashboard", "monitor", "history", "abuse", "world", "player", "seasonal", "holiday", "presets", "custom", "scheduler", "control", "god", "fighters", "summon", "announce", "emergency" }
	local count = 0
	for _, group in OwnerCenter.Groups do
		assert(t.findNamed(window, "Group_" .. group.title), "group " .. group.title)
		count += #group.items
	end
	assert(count == 17, "17 sections, got " .. count)
	for _, id in expected do
		assert(t.findNamed(window, "Nav_" .. id), "nav item " .. id)
	end
end)

t.check("the window is not the old panel", function()
	assert(not t.findNamed(player.PlayerGui, "SNOwner"), "the old owner panel is not built")
end)

local SECTIONS = { "dashboard", "monitor", "history", "abuse", "world", "player", "seasonal", "holiday", "presets", "custom", "scheduler", "control", "god", "fighters", "summon", "announce", "emergency" }
for _, size in { { 1280, 720 }, { 667, 375 } } do
	t.check(`every section builds and passes the audit at {size[1]}x{size[2]}`, function()
		t.setScreen(size[1], size[2])
		for _, id in SECTIONS do
			press(window, "Nav_" .. id)
			local page = t.findNamed(window, "Section_" .. id)
			assert(page and page.Visible, id .. " shows")
			assert(not t.findNamed(page, "BuildError"), id .. " built without an error")
			t.auditLayout(page, `{id} at {size[1]}x{size[2]}`)
			local bad = badText(page)
			assert(#bad == 0, `{id}: emoji or em dash:\n  ` .. table.concat(bad, "\n  "))
			local small = smallText(page)
			assert(#small == 0, `{id}: text under 14 px:\n  ` .. table.concat(small, "\n  "))
		end
		t.auditLayout(t.findNamed(window, "StatusStrip"), "status strip")
		t.auditLayout(t.findNamed(window, "Sections"), "section list")
	end)
end
t.setScreen(1280, 720)

t.check("the dashboard shows the server, players, the running event and recent actions", function()
	press(window, "Nav_dashboard")
	local page = t.findNamed(window, "Section_dashboard")
	assert(t.findText(page, "abcdef12"), "short job id")
	assert(t.findNamed(page, "Event_ev1"), "the running event with a Stop button")
	assert(t.findNamed(t.findNamed(page, "Event_ev1"), "Stop"), "Stop button")
	assert(labelContaining(page, "Remote:activate") == nil, "audit actions are readable")
	assert(labelContaining(page, "Activate: refused"), "recent actions listed")
	local total = labelContaining(t.findNamed(page, "Network"), "11")
	assert(total, "total players across servers is 11")
end)

t.check("the server monitor lists servers with the test flag and a Summon button", function()
	press(window, "Nav_monitor")
	local page = t.findNamed(window, "Section_monitor")
	assert(t.findNamed(page, "Server_abcdef1234567890") and t.findNamed(page, "Server_zzzz9999yyyy"), "both servers")
	assert(t.findText(t.findNamed(page, "Server_zzzz9999yyyy"), "TEST"), "test badge")
	assert(not t.findNamed(t.findNamed(page, "Server_abcdef1234567890"), "Summon"), "no Summon for this server")
end)

-- Catalogue ---------------------------------------------------------------------------------

local function cardsIn(page)
	local list = {}
	for _, item in t.findNamed(page, "Cards"):GetChildren() do
		if string.sub(item.Name, 1, 5) == "Card_" then
			table.insert(list, item)
		end
	end
	return list
end

t.check("the catalogue is paged and search filters it", function()
	press(window, "Nav_world")
	local page = t.findNamed(window, "Section_world")
	local all = #cardsIn(page)
	assert(all == 40, "first page is 40 cards, got " .. all)
	assert(t.findNamed(page, "ShowMore"), "a Show more button")
	press(page, "ShowMore")
	assert(#cardsIn(page) == 67, "Show more adds the rest (World and Environment: 67), got " .. #cardsIn(page))
	local search = t.findNamed(page, "Search")
	setText(search, "golden")
	Engine.task.wait(0.05)
	local filtered = cardsIn(page)
	assert(#filtered == 1 and filtered[1].Name == "Card_p_1", "search finds Golden World, got " .. #filtered)
	setText(search, "zzzzz nothing")
	Engine.task.wait(0.05)
	assert(#cardsIn(page) == 0 and labelContaining(page, "Nothing matches"), "an empty search says so")
	setText(search, "")
	Engine.task.wait(0.05)
	-- Only World and Environment presets live here
	for _, card in cardsIn(page) do
		assert(card.Name ~= "Card_p_2", "Player presets are not in World manipulation")
	end
end)

t.check("favourites and recent work for the session", function()
	local page = t.findNamed(window, "Section_world")
	local first = cardsIn(page)[1]
	press(first, "Fav")
	press(page, "Filter_fav")
	assert(#cardsIn(page) == 1, "one favourite listed")
	press(page, "Filter_recent")
	assert(#cardsIn(page) == 0, "nothing recent yet")
	press(page, "Filter_all")
end)

t.check("Activate asks to confirm, shows the scope and sends the right payload", function()
	press(window, "Nav_world")
	local page = t.findNamed(window, "Section_world")
	press(t.findNamed(page, "Card_p_1"), "Fav")
	press(page, "Card_p_1")
	local detail = t.findNamed(page, "DetailScroll")
	assert(labelContaining(detail, "Golden World"), "detail shows the name")
	assert(labelContaining(detail, "LEVEL"), "level chip")
	assert(t.findNamed(detail, "Intensity") and t.findNamed(detail, "Swatch_Gold"), "intensity and colour controls where the preset allows")
	-- change duration one step up and intensity one step up, pick gold
	press(t.findNamed(detail, "Duration"), "Plus")
	press(t.findNamed(detail, "Intensity"), "Plus")
	press(detail, "Swatch_Gold")
	local before = #Engine.sent
	press(detail, "Activate")
	assert(lastRequest("Activate", before) == nil, "nothing is sent before confirming")
	local body = confirmDialog()
	assert(string.find(body, "Scope: This server", 1, true), "the dialog shows the scope: " .. body)
	serve()
	local sent = lastRequest("Activate", before)
	assert(sent, "Activate was sent")
	local payload = sent.args[3]
	assert(payload.scope.k == "here", "scope here")
	assert(#payload.entries == 1 and payload.entries[1].preset == "p_1", "one entry for the preset")
	local o = payload.entries[1].overrides
	assert(o and o.duration == 600 and o.intensity == 1.25 and o.color[1] == 255 and o.color[2] == 200 and o.color[3] == 80, "overrides carry duration, intensity and colour")
	assert(payload.eventMode == nil, "not event mode")
	assert(labelContaining(detail, "is running"), "success feedback shows")
	press(page, "Filter_recent")
	assert(#cardsIn(page) == 1, "the activated preset is now in Recently used")
	press(page, "Filter_all")
end)

t.check("the scope selector changes what Activate sends", function()
	local page = t.findNamed(window, "Section_world")
	press(window, "Segment_all")
	press(page, "Card_p_1")
	local detail = t.findNamed(page, "DetailScroll")
	local before = #Engine.sent
	press(detail, "Activate")
	local body = confirmDialog()
	assert(string.find(body, "Scope: All servers", 1, true), "dialog says all servers: " .. body)
	serve()
	assert(lastRequest("Activate", before).args[3].scope.k == "all", "scope all")
	-- Pick servers with nothing picked is refused on the client with a sentence
	press(window, "Segment_jobs")
	before = #Engine.sent
	press(detail, "Activate")
	assert(not t.findNamed(gui, "Dialog"), "no dialog without picked servers")
	assert(lastRequest("Activate", before) == nil, "nothing sent")
	assert(labelContaining(gui, "Pick at least one server"), "a readable toast")
	-- Pick one in the monitor
	press(window, "Nav_monitor")
	press(t.findNamed(t.findNamed(window, "Section_monitor"), "Server_zzzz9999yyyy"), "Pick")
	press(window, "Nav_world")
	before = #Engine.sent
	press(detail, "Activate")
	confirmDialog()
	serve()
	local scope = lastRequest("Activate", before).args[3].scope
	assert(scope.k == "jobs" and scope.j[1] == "zzzz9999yyyy", "picked servers scope")
	press(window, "Segment_test")
	before = #Engine.sent
	press(detail, "Activate")
	confirmDialog()
	serve()
	assert(lastRequest("Activate", before).args[3].scope.k == "test", "scope test")
	press(window, "Segment_here")
end)

t.check("event-mode presets send eventMode and say so", function()
	local page = t.findNamed(window, "Section_world")
	setText(t.findNamed(page, "Search"), "gravity")
	Engine.task.wait(0.05)
	press(page, "Card_p_flip")
	setText(t.findNamed(page, "Search"), "")
	local detail = t.findNamed(page, "DetailScroll")
	local before = #Engine.sent
	press(detail, "Activate")
	local body = confirmDialog()
	assert(string.find(body, "event mode", 1, true), "dialog mentions event mode")
	serve()
	assert(lastRequest("Activate", before).args[3].eventMode == true, "eventMode sent")
end)

t.check("a refusal code becomes a plain sentence", function()
	local page = t.findNamed(window, "Section_world")
	press(page, "Card_p_1")
	local detail = t.findNamed(page, "DetailScroll")
	overrides.Activate = { ok = false, code = "channel_conflict:lighting:w_neon_takeover", message = "raw" }
	press(detail, "Activate")
	confirmDialog()
	serve()
	local line = labelContaining(detail, "lighting channel")
	assert(line and not string.find(line.Text, "channel_conflict", 1, true), "plain sentence, not the code")
	assert(string.find(line.Text, "Stop it first", 1, true), line.Text)
	overrides.Activate = { ok = false, code = "performance_cap" }
	press(detail, "Activate")
	confirmDialog()
	serve()
	assert(labelContaining(detail, "effect budget"), "performance cap sentence")
	overrides.Activate = { ok = false, code = "something_new", message = "The server says no." }
	press(detail, "Activate")
	confirmDialog()
	serve()
	assert(labelContaining(detail, "The server says no."), "unknown codes use the server message")
end)

t.check("Preview sends the chosen seconds for this server", function()
	local page = t.findNamed(window, "Section_world")
	local detail = t.findNamed(page, "DetailScroll")
	press(t.findNamed(detail, "PreviewLength"), "Plus")
	local before = #Engine.sent
	press(detail, "Preview")
	local sent = lastRequest("Preview", before)
	assert(sent and sent.args[3].preset == "p_1" and sent.args[3].seconds == 15, "Preview { preset, seconds = 15 }")
end)

t.check("seasonal and holiday sections only list holiday collections", function()
	press(window, "Nav_holiday")
	local page = t.findNamed(window, "Section_holiday")
	assert(t.findNamed(page, "Filter_Thanksgiving") and t.findNamed(page, "Filter_Christmas"), "collection filters")
	press(page, "Filter_Christmas")
	local cards = cardsIn(page)
	assert(#cards > 0, "Christmas presets listed")
	for _, card in cards do
		local id = tonumber(string.sub(card.Name, 8))
		assert(id and (id - 1) % 7 == 6, "only Christmas: " .. card.Name)
	end
end)

-- Saved presets, custom, scheduler, announcements -------------------------------------------------

t.check("saved presets: add to selection, save a combination, run and delete one", function()
	press(window, "Nav_world")
	local world = t.findNamed(window, "Section_world")
	assert(t.findNamed(world, "Card_p_1"), "world card p_1 is listed")
	press(world, "Card_p_1")
	assert(t.findNamed(world, "DetailScroll"), "detail scroll")
	press(t.findNamed(world, "DetailScroll"), "AddToSelection")
	press(window, "Nav_presets")
	local page = t.findNamed(window, "Section_presets")
	serve()
	assert(t.findNamed(page, "Combo_combo_1"), "the saved combination is listed")
	setText(t.findNamed(page, "ComboName"), "My show")
	local before = #Engine.sent
	press(page, "SaveCombo")
	local sent = lastRequest("SaveCombo", before)
	assert(sent, "SaveCombo sent")
	local payload = sent.args[3]
	assert(payload.name == "My show" and #payload.entries == 1 and payload.entries[1].preset == "p_1" and string.match(payload.id, "^combo_[%w]+$"), "SaveCombo { id, name, entries }")
	before = #Engine.sent
	-- (the fixture's SaveCombo answer keeps combo_1 and adds the new one)
	press(t.findNamed(page, "Combo_combo_1"), "Run")
	confirmDialog()
	serve()
	local run = lastRequest("Activate", before)
	assert(run and #run.args[3].entries == 2 and run.args[3].entries[2].preset == "p_2", "running a combination activates its entries")
	before = #Engine.sent
	press(t.findNamed(page, "Combo_combo_1"), "Delete")
	confirmDialog()
	serve()
	assert(lastRequest("DeleteCombo", before).args[3].id == "combo_1", "DeleteCombo { id }")
end)

t.check("Announce sends text, style, seconds and scope after a confirm", function()
	press(window, "Nav_announce")
	local page = t.findNamed(window, "Section_announce")
	local box = t.findNamed(page, "Message")
	setText(box, "Event night starts now")
	assert(t.findText(page, "22 of 160 characters"), "character count")
	press(page, "Style_toast")
	press(t.findNamed(page, "Seconds"), "Plus")
	local before = #Engine.sent
	press(page, "Send")
	assert(lastRequest("Announce", before) == nil, "confirm first")
	local body = confirmDialog()
	assert(string.find(body, "Event night starts now", 1, true) and string.find(body, "Scope: This server", 1, true), body)
	serve()
	local payload = lastRequest("Announce", before).args[3]
	assert(payload.text == "Event night starts now" and payload.style == "toast" and payload.seconds == 8 and payload.scope.k == "here", "Announce { text, style, seconds, scope }")
	setText(box, string.rep("x", 400))
	assert(utf8.len(box.Text) == 160, "text is capped at 160")
	setText(box, "")
	before = #Engine.sent
	press(page, "Send")
	assert(lastRequest("Announce", before) == nil and labelContaining(page, "Write something first"), "empty text is refused locally")
end)

t.check("ScheduleAdd sends unix seconds, label, entries and scope; cancel works", function()
	press(window, "Nav_scheduler")
	local page = t.findNamed(window, "Section_scheduler")
	assert(t.findNamed(page, "Item_s1"), "the pending item is listed")
	press(page, "Choice_p_1")
	local soon = os.time() + 7200
	local stamp = os.date("!%Y-%m-%d %H:%M", soon)
	setText(t.findNamed(page, "Date"), string.sub(stamp, 1, 10))
	setText(t.findNamed(page, "Time"), string.sub(stamp, 12, 16))
	setText(t.findNamed(page, "Label"), "Late show")
	local before = #Engine.sent
	press(page, "Schedule")
	local sent = lastRequest("ScheduleAdd", before)
	assert(sent, "ScheduleAdd sent")
	local payload = sent.args[3]
	assert(math.abs(payload.at - soon) < 60, `at is unix seconds near the chosen time ({payload.at} vs {soon})`)
	assert(payload.label == "Late show" and payload.entries[1].preset == "p_1" and payload.scope.k == "here" and payload.combo == nil, "label, entries, scope")
	-- A saved combination goes as combo = id
	press(page, "Kind_combo")
	press(page, "Choice_combo_1")
	before = #Engine.sent
	press(page, "Schedule")
	local combo = lastRequest("ScheduleAdd", before).args[3]
	assert(combo.combo == "combo_1" and combo.entries == nil, "combo schedule sends the combo id")
	-- Bad input is refused locally
	setText(t.findNamed(page, "Date"), "tomorrow")
	before = #Engine.sent
	press(page, "Schedule")
	assert(lastRequest("ScheduleAdd", before) == nil and labelContaining(page, "formats shown"), "bad date refused")
	before = #Engine.sent
	press(t.findNamed(page, "Item_s1"), "Cancel")
	assert(lastRequest("ScheduleCancel", before).args[3].id == "s1", "ScheduleCancel { id }")
end)

t.check("CustomSave sends name, description, duration and the chosen effects with settings", function()
	press(window, "Nav_custom")
	local page = t.findNamed(window, "Section_custom")
	setText(t.findNamed(page, "EventName"), "Mine")
	setText(t.findNamed(page, "EventDescription"), "A test event")
	press(page, "AddEffect")
	press(page, "Pick_Weather")
	press(page, "Choose")
	assert(t.findNamed(page, "Slot_1"), "the effect is added")
	local slot = t.findNamed(page, "Slot_1")
	assert(t.findNamed(slot, "Param_rate") and t.findNamed(slot, "Param_kind") and t.findNamed(slot, "Param_color"), "controls for number, enum and colour settings")
	press(t.findNamed(slot, "Param_rate"), "Plus")
	press(t.findNamed(slot, "Param_kind"), "Plus")
	press(slot, "Swatch_Cyan")
	press(t.findNamed(page, "Duration"), "Plus")
	local before = #Engine.sent
	press(page, "Save")
	local payload = lastRequest("CustomSave", before).args[3]
	assert(payload.name == "Mine" and payload.description == "A test event" and payload.duration == 600, "name, description, duration")
	assert(#payload.effects == 1 and payload.effects[1].effect == "Weather", "one effect")
	local params = payload.effects[1].params
	assert(params.kind == "snow" and params.rate > 30 and params.color[1] == 90 and params.color[3] == 255, "settings carry the owner's choices")
	assert(labelContaining(page, "Saved Mine."), "success is shown")
	-- Empty and over-long forms are refused locally
	setText(t.findNamed(page, "EventName"), "")
	before = #Engine.sent
	press(page, "Save")
	assert(lastRequest("CustomSave", before) == nil and labelContaining(page, "Give the event a name"), "name required")
	-- At most six effects
	for _ = 1, 8 do
		press(page, "AddEffect")
		if t.findNamed(page, "Pick_Weather") then
			press(page, "Choose")
		end
	end
	local slots = 0
	for _, item in t.findNamed(page, "Slots"):GetChildren() do
		if string.sub(item.Name, 1, 5) == "Slot_" then
			slots += 1
		end
	end
	assert(slots <= 6, "no more than six effects, got " .. slots)
end)

t.check("god powers, fighters, summoning and emergency restore send the right requests", function()
	local before = #Engine.sent
	press(window, "Nav_god")
	press(t.findNamed(window, "Section_god"), "Toggle_Fly")
	local fly = t.sentSince(before, "AdminRequest", "SelfToggle")
	assert(#fly == 1 and fly[1].args[2] == "Fly" and fly[1].args[3] == true, "SelfToggle Fly on")

	press(window, "Nav_fighters")
	local fighters = t.findNamed(window, "Section_fighters")
	before = #Engine.sent
	press(fighters, "Equip_Ghost_2")
	local select = t.sentSince(before, "PowerRequest", "Select")
	assert(#select == 1 and select[1].args[2] == "Ghost" and select[1].args[3] == 2, "Select Ghost phase 2")
	press(fighters, "OpenShowcase")
	assert(Shell.isOpen("Powers"), "Fighter Showcase opens")
	Shell.open("OwnerCenter")
	assert(Shell.isOpen("OwnerCenter"), "back to the Control Center")

	press(window, "Nav_summon")
	local summon = t.findNamed(window, "Section_summon")
	before = #Engine.sent
	press(t.findNamed(summon, "Server_zzzz9999yyyy"), "Summon")
	confirmDialog()
	serve()
	assert(lastRequest("Summon", before).args[3].jobId == "zzzz9999yyyy", "Summon { jobId }")

	press(window, "Nav_emergency")
	local emergency = t.findNamed(window, "Section_emergency")
	for _, id in { "StopAll", "RestoreEnvironment", "ClearEffects", "RestorePlayers", "ReturnToDefault" } do
		before = #Engine.sent
		press(t.findNamed(emergency, "Restore_" .. id), id)
		assert(lastRequest(id, before) == nil, id .. " waits for the confirm")
		local body = confirmDialog()
		assert(string.find(body, "Scope: This server", 1, true), id .. " dialog shows the scope")
		serve()
		local sent = lastRequest(id, before)
		assert(sent and sent.args[3].scope.k == "here", id .. " sends { scope }")
	end
	press(window, "Segment_all")
	before = #Engine.sent
	press(t.findNamed(emergency, "Restore_StopAll"), "StopAll")
	confirmDialog()
	serve()
	assert(lastRequest("StopAll", before).args[3].scope.k == "all", "scope all reaches StopAll")
	press(window, "Segment_here")
end)

t.check("command history lists the audit log with readable results", function()
	press(window, "Nav_history")
	local page = t.findNamed(window, "Section_history")
	assert(labelContaining(page, "Activate"), "actions listed")
	assert(labelContaining(page, "effect budget"), "a refusal reason is a sentence")
end)

t.check("closing the window stops its refresh loop", function()
	Shell.close()
	assert(not Shell.isOpen("OwnerCenter"), "closed")
end)

t.finish()
