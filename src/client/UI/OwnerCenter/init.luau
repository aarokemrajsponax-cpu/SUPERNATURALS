-- The owner's Control Center: one Shell window ("OwnerCenter") with a grouped section list on
-- the left, the section in the middle and a status strip along the bottom (owner, this server,
-- scope selector, sync state). It only sends requests; the server decides who is the owner and
-- re-validates every action. Registered only for the owner (OwnerController).
--   OwnerCenter.register({ sendAdmin = function(action, a, b) end })
--   OwnerCenter.toggle() / OwnerCenter.open(sectionId?)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Shell = require(script.Parent.Shell)
local Announce = require(script.Announce)
local CatalogueView = require(script.CatalogueView)
local CommunityGoals = require(script.CommunityGoals)
local Custom = require(script.Custom)
local Dashboard = require(script.Dashboard)
local History = require(script.History)
local Kit = require(script.Kit)
local Monitor = require(script.Monitor)
local Net = require(script.Net)
local Personal = require(script.Personal)
local Presets = require(script.Presets)
local Scheduler = require(script.Scheduler)

local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make

local OwnerCenter = {}

local WINDOW_ID = "OwnerCenter"
local NAV_WIDTH = 248
local STRIP = 52
local REFRESH_SECONDS = 10

local function catalogue(config: any)
	return function(page: Frame, ctx: any)
		return CatalogueView.build(page, ctx, config)
	end
end

local function set(...: string): { [string]: boolean }
	local out = {}
	for _, id in { ... } do
		out[id] = true
	end
	return out
end

-- Every collection that is not one of the everyday categories counts as a holiday collection
local EVERYDAY = set("World", "Player", "Environment", "Spectacle", "Owner", "Custom")
local HOLIDAYS = setmetatable({}, {
	__index = function(_, category)
		return EVERYDAY[category] == nil
	end,
})

-- The sections, in the order the list shows them
OwnerCenter.Groups = {
	{
		title = "Overview",
		items = {
			{ id = "dashboard", name = "Dashboard", build = Dashboard.build },
			{ id = "monitor", name = "Server monitor", build = Monitor.buildMonitor },
			{ id = "history", name = "Command history", build = History.buildHistory },
		},
	},
	{
		title = "Events",
		items = {
			{ id = "abuse", name = "Admin abuse events", build = catalogue({ title = "Admin abuse events", intro = "Large spectacles and owner-only events. Search, favourite, preview on this server, then activate with the scope below.", categories = set("Spectacle", "Owner", "Custom") }) },
			{ id = "world", name = "World manipulation", build = catalogue({ title = "World manipulation", intro = "Change the look of the whole station: light, sky, weather, structures, gravity and environment.", categories = set("World", "Environment") }) },
			{ id = "player", name = "Player effects", build = catalogue({ title = "Player effects", intro = "Visual and movement effects on the players.", categories = set("Player") }) },
			{ id = "seasonal", name = "Seasonal event center", build = catalogue({ title = "Seasonal event center", intro = "Events for the current season come first. Switch the season itself under Global server control.", categories = HOLIDAYS, current = function()
				local Seasons = require(ReplicatedStorage.Shared.Seasons)
				local ok, id = pcall(function()
					return Seasons.getActiveId() or Seasons.getCurrentId()
				end)
				return if ok then id else nil
			end }) },
			{ id = "holiday", name = "Holiday effects library", build = catalogue({ title = "Holiday effects library", intro = "Every holiday collection. Filter by collection, then preview or activate.", categories = HOLIDAYS }) },
			{ id = "presets", name = "Saved presets", build = Presets.build },
			{ id = "custom", name = "Custom event creator", build = Custom.build },
			{ id = "scheduler", name = "Event scheduler", build = Scheduler.build },
		},
	},
	{
		title = "Control",
		items = {
			{ id = "control", name = "Global server control", build = Monitor.buildControl },
			{ id = "god", name = "God powers", build = Personal.buildGod },
			{ id = "fighters", name = "Fighter and degree control", build = Personal.buildFighters },
			{ id = "summon", name = "Summoning and teleportation", build = Personal.buildSummon },
			{ id = "announce", name = "Announcement center", build = Announce.build },
			{ id = "goals", name = "Community goals", build = CommunityGoals.build },
			{ id = "emergency", name = "Emergency restore", build = History.buildEmergency },
		},
	},
}

local registered = false
local options: { sendAdmin: (string, any?, any?) -> () } = { sendAdmin = function() end }

local function build(body: Frame, _api: any)
	Net.start()
	local player = Players.LocalPlayer

	local ctx: any = {
		sendAdmin = function(action: string, first: any?, second: any?)
			options.sendAdmin(action, first, second)
		end,
	}

	-- Layout ---------------------------------------------------------------------------------
	local nav = Components.scroll({ Name = "Sections", Size = UDim2.new(0, NAV_WIDTH, 1, -(STRIP + Space.S)), Parent = body })
	nav.VerticalScrollBarInset = Enum.ScrollBarInset.None
	Components.list(nav, 2)
	local content = make("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(NAV_WIDTH + Space.M, 0),
		Size = UDim2.new(1, -(NAV_WIDTH + Space.M), 1, -(STRIP + Space.S)),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = body,
	})
	local strip = make("Frame", {
		Name = "StatusStrip",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, STRIP),
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Parent = body,
	}, { Components.corner(Theme.SmallCorner), Components.padding(0, Space.M, 0, Space.M) })
	Components.list(strip, Space.M, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })

	local function stripText(name: string, order: number): TextLabel
		return Components.text({ Name = name, Text = "", Style = "small", Color = Colors.Text, LayoutOrder = order, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, TextTruncate = Enum.TextTruncate.None, Parent = strip })
	end
	local serverText = stripText("Server", 2)
	local scopeSegments = Components.segmented(strip, {
		{ id = "here", label = "This server" },
		{ id = "all", label = "All servers" },
		{ id = "test", label = "Test servers" },
		{ id = "jobs", label = "Pick servers" },
	}, Net.scopeId, function(id)
		Net.setScope(id)
	end, { Name = "Scope", Size = UDim2.fromOffset(540, 44), LayoutOrder = 3 })
	local syncText = stripText("Sync", 4)

	local function paintStrip()
		local state = Net.state
		serverText.Text = `{player.DisplayName}, server {if state and state.jobId then Kit.shortId(state.jobId) else "..."}`
		local text, color = "Waiting for the server", Colors.TextMuted
		if state then
			if state.syncOk == false then
				text, color = "Other servers not reached", Colors.Warning
			else
				text, color = "Live, " .. Kit.ago(state.lastSync), Colors.Success
			end
		end
		if Net.scopeId == "jobs" then
			text = `{#Net.pickedList()} picked. {text}`
		end
		syncText.Text = text
		syncText.TextColor3 = color
	end
	Net.on("state", paintStrip)
	Net.on("scope", function()
		scopeSegments.set(Net.scopeId)
		paintStrip()
	end)
	paintStrip()

	-- Sections ---------------------------------------------------------------------------------
	local pages: { [string]: { frame: Frame, handlers: any, error: boolean } } = {}
	local navButtons: { [string]: TextButton } = {}
	local current: string? = nil

	local function ensure(item: any)
		if pages[item.id] then
			return pages[item.id]
		end
		local frame = make("Frame", { Name = "Section_" .. item.id, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = content })
		local ok, handlers = pcall(item.build, frame, ctx)
		local entry = { frame = frame, handlers = if ok and typeof(handlers) == "table" then handlers else {}, error = not ok }
		if not ok then
			warn(`[OwnerCenter] section {item.id} failed to build: {handlers}`)
			Kit.clear(frame)
			Components.text({ Name = "BuildError", Text = "This section could not load. Close and reopen the Control Center.", Style = "body", Color = Colors.Danger, Wrap = true, Parent = frame })
		end
		pages[item.id] = entry
		return entry
	end

	local byId: { [string]: any } = {}
	local function select(id: string)
		local item = byId[id]
		if not item then
			return
		end
		current = id
		for pageId, page in pages do
			page.frame.Visible = pageId == id
		end
		for buttonId, button in navButtons do
			Components.setSelected(button, buttonId == id)
		end
		local page = ensure(item)
		page.frame.Visible = true
		if page.handlers.show then
			local ok, err = pcall(page.handlers.show)
			if not ok then
				warn(`[OwnerCenter] section {id} failed to refresh: {err}`)
			end
		end
	end
	ctx.openSection = select

	local order = 0
	for _, group in OwnerCenter.Groups do
		order += 1
		Components.text({ Name = "Group_" .. group.title, Text = group.title, Style = "overline", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 30), AlignY = "Bottom", Parent = nav })
		for _, item in group.items do
			order += 1
			byId[item.id] = item
			navButtons[item.id] = Components.button(item.name, {
				Name = "Nav_" .. item.id,
				Variant = "Ghost",
				KeepCase = true,
				LayoutOrder = order,
				Size = UDim2.new(1, -4, 0, Theme.Size.Control),
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				Parent = nav,
			}, function()
				select(item.id)
			end)
		end
	end

	-- Live refresh while open ----------------------------------------------------------------------
	local open = false
	local function loop()
		local elapsed = 0
		while open do
			task.wait(1)
			if not open then
				break
			end
			elapsed += 1
			paintStrip()
			local page = current and pages[current]
			if page and page.handlers.tick then
				page.handlers.tick()
			end
			if elapsed % REFRESH_SECONDS == 0 then
				Net.refreshLive()
			end
		end
	end

	return {
		onOpen = function(args: any?)
			Net.start()
			Net.refreshLive()
			Net.loadCatalogue()
			local wanted = if typeof(args) == "table" and typeof(args.section) == "string" then args.section else current or "dashboard"
			select(wanted)
			if not open then
				open = true
				task.spawn(loop)
			end
		end,
		onClose = function()
			open = false
		end,
	}
end

-- Registers the window. Call once, only for the owner; the server re-checks every request.
function OwnerCenter.register(opts: { sendAdmin: (string, any?, any?) -> () }?)
	if opts then
		options = opts :: any
	end
	if registered then
		return
	end
	registered = true
	Net.start()
	Shell.registerWindow(WINDOW_ID, {
		title = "Control Center",
		-- Only registered for the owner, so only the owner ever sees this dock button
		label = "OWNER",
		icon = "crown",
		order = 0,
		nav = true,
		size = Vector2.new(1120, 660),
		build = build,
	})
end

function OwnerCenter.isRegistered(): boolean
	return registered and Shell.hasWindow(WINDOW_ID)
end

function OwnerCenter.toggle()
	if Shell.hasWindow(WINDOW_ID) then
		Shell.toggle(WINDOW_ID)
	end
end

function OwnerCenter.open(section: string?)
	if Shell.hasWindow(WINDOW_ID) then
		Shell.open(WINDOW_ID, if section then { section = section } else nil)
	end
end

return OwnerCenter
