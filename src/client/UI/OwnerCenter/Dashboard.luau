-- Dashboard: who is signed in, this server, players across servers, what is running (with Stop),
-- the season, recent actions and quick buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Seasons = require(ReplicatedStorage.Shared.Seasons)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local Actions = require(script.Parent.Actions)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)

local Action = Protocol.OverlordAction
local Colors = Theme.Colors

local Dashboard = {}

local function seasonName(): string
	local ok, id = pcall(function()
		return Seasons.getActiveId() or Seasons.getCurrentId()
	end)
	local theme = ok and id and Seasons.Themes[id]
	return if theme then theme.name else "No season right now"
end

function Dashboard.build(page: Frame, ctx: any)
	local scroll = Kit.page(page)
	Kit.heading(scroll, "Dashboard", 1)
	local columns = Kit.columns(scroll, 2, 2)
	local leftColumn, rightColumn = columns[1], columns[2]

	-- Identity and servers
	local identity = Kit.card(leftColumn, 1, { Name = "Identity" })
	Kit.subheading(identity, "Signed in", 1)
	local player = Players.LocalPlayer
	Kit.pair(identity, "Owner", player.DisplayName, 2)
	Kit.pair(identity, "Account", player.Name, 3)
	Kit.pair(identity, "Season", seasonName(), 4).Name = "SeasonValue"

	local network = Kit.card(leftColumn, 2, { Name = "Network" })
	Kit.subheading(network, "Servers", 1)
	local thisServer = Kit.pair(network, "This server", "...", 2, true)
	local playersHere = Kit.pair(network, "Players here", "0", 3, true)
	local total = Kit.pair(network, "Players on all servers", "...", 4, true)
	local serverCount = Kit.pair(network, "Servers listed", "...", 5, true)
	local syncLine = Kit.pair(network, "Sync", "Waiting for the server", 6)

	-- Active events
	local activeCard = Kit.card(rightColumn, 1, { Name = "Active" })
	Kit.subheading(activeCard, "Running now", 1)
	local activeList = Kit.stack(activeCard, 2, "ActiveList")

	local recentCard = Kit.card(rightColumn, 2, { Name = "Recent" })
	Kit.subheading(recentCard, "Recent actions", 1)
	local recentList = Kit.stack(recentCard, 2, "RecentList")

	local quick = Kit.card(scroll, 3, { Name = "Quick" })
	Kit.subheading(quick, "Quick commands", 1)
	local row = Kit.flow(quick, 2, 8)
	Kit.button(row, "Browse events", "Primary", function()
		ctx.openSection("abuse")
	end, { Name = "QuickEvents" })
	Kit.button(row, "Send an announcement", "Secondary", function()
		ctx.openSection("announce")
	end, { Name = "QuickAnnounce" })
	Kit.button(row, "Server monitor", "Secondary", function()
		ctx.openSection("monitor")
	end, { Name = "QuickMonitor" })
	Kit.button(row, "Stop all events", "Danger", function()
		Actions.scoped(Action.StopAll, "Stop every event?", "Every running event ends.", "All events stopped", true)
	end, { Name = "QuickStopAll" })

	local function renderActive()
		Kit.clear(activeList)
		local state = Net.state
		local active = if state and typeof(state.active) == "table" then state.active else {}
		if #active == 0 then
			Kit.empty(activeList, "Nothing is running on this server.", 1)
			return
		end
		for index, event in active do
			local card = Kit.card(activeList, index, { Name = "Event_" .. tostring(event.id), BackgroundColor3 = Colors.Raised })
			Components.text({ Name = "Name", Text = event.name or event.preset or "Event", Style = "strong", Wrap = true, Parent = card, LayoutOrder = 1 })
			local left = if typeof(event.endsAt) == "number" then Kit.seconds(event.endsAt - os.time()) .. " left" else "No end time"
			Components.text({ Name = "TimeLeft", Text = left, Style = "number", LayoutOrder = 2, Parent = card, Size = UDim2.new(1, 0, 0, 22) })
			Kit.button(card, "Stop", "Secondary", function()
				Actions.scoped(Action.Stop, `Stop {event.name or "this event"}?`, "The event ends now.", "Event stopped", false, { target = event.id })
			end, { Name = "Stop", LayoutOrder = 3 })
		end
	end

	local function renderRecent()
		Kit.clear(recentList)
		if #Net.audit == 0 then
			Kit.empty(recentList, "No actions logged yet.", 1)
			return
		end
		for index = 1, math.min(5, #Net.audit) do
			local entry = Net.audit[index]
			local line = Components.text({
				Name = "Entry",
				Text = `{Kit.actionName(entry.action)}: {entry.outcome or "no result"}, {Net.describeScope(entry.scope)}`,
				Style = "small",
				Wrap = true,
				LayoutOrder = index,
				Parent = recentList,
			})
			local _ = line
		end
	end

	local function renderNumbers()
		local state = Net.state
		thisServer.Text = if state and state.jobId then Kit.shortId(state.jobId) else "unknown"
		playersHere.Text = tostring(#Players:GetPlayers())
		local sum, listed = 0, 0
		for _, server in Net.servers do
			sum += tonumber(server.players) or 0
			listed += 1
		end
		total.Text = if Net.serversAt then tostring(sum) else "..."
		serverCount.Text = if Net.serversAt then tostring(listed) else "..."
		if not state then
			syncLine.Text = "Waiting for the server"
		elseif state.syncOk == false then
			syncLine.Text = "Other servers not reached"
			syncLine.TextColor3 = Colors.Warning
		else
			syncLine.Text = "Connected, " .. Kit.ago(state.lastSync)
			syncLine.TextColor3 = Colors.Text
		end
	end

	local function renderAll()
		renderNumbers()
		renderActive()
		renderRecent()
	end
	Net.on("state", renderAll)
	Net.on("servers", renderNumbers)
	Net.on("audit", renderRecent)
	renderAll()

	return {
		show = function()
			Net.refreshLive()
			Net.loadAudit()
			renderAll()
		end,
		tick = function()
			-- Counts down the time left every second
			renderActive()
			playersHere.Text = tostring(#Players:GetPlayers())
		end,
	}
end

return Dashboard
