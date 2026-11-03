-- The live server list used by Server monitor, Global server control and Summoning:
-- players, running events, last sync and heartbeat, the test flag, "Pick" for the
-- Pick servers scope, and Summon (teleports the owner there).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local Actions = require(script.Parent.Actions)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)

local Action = Protocol.OverlordAction
local Colors = Theme.Colors

local ServerList = {}

local function eventCount(server: any): number
	if typeof(server.events) == "table" then
		return #server.events
	end
	return tonumber(server.events) or 0
end

-- options: pick (show the Pick button), parent
function ServerList.build(parent: Instance, options: any)
	local summary = Kit.card(parent, options.order or 1, { Name = "ServerSummary" })
	local totalLine = Kit.pair(summary, "Players on all listed servers", "...", 1, true)
	local countLine = Kit.pair(summary, "Servers listed", "...", 2, true)
	local actions = Kit.flow(summary, 3, 8)
	Kit.button(actions, "Refresh", "Secondary", function()
		Net.request(Action.Servers)
	end, { Name = "RefreshServers" })
	local list = Kit.stack(parent, (options.order or 1) + 1, "ServerRows")

	local function render()
		local sum = 0
		for _, server in Net.servers do
			sum += tonumber(server.players) or 0
		end
		totalLine.Text = if Net.serversAt then tostring(sum) else "..."
		countLine.Text = if Net.serversAt then tostring(#Net.servers) else "..."
		Kit.clear(list)
		if #Net.servers == 0 then
			Kit.empty(list, if Net.serversAt then "No other servers are registered right now." else "Asking the server for its list.", 1)
			return
		end
		for index, server in Net.servers do
			local card = Kit.card(list, index, { Name = "Server_" .. tostring(server.jobId) })
			local head = Kit.flow(card, 1, 8)
			Components.text({ Name = "Id", Text = Kit.shortId(server.jobId), Style = "number", Size = UDim2.fromOffset(110, 24), Parent = head })
			if server.current then
				Components.badge("This server", Colors.Cyan).Parent = head
			end
			if server.test then
				Components.badge("Test", Colors.Warning).Parent = head
			end
			Kit.caption(card, `{server.players or 0} players, {eventCount(server)} events running. Last sync {Kit.ago(server.lastSync)}, heartbeat {Kit.ago(server.heartbeat)}.`, 2, Colors.TextDim)
			local buttons = Kit.flow(card, 3, 8)
			if options.pick then
				local pick = Kit.button(buttons, "Pick for scope", "Ghost", function()
					Net.togglePicked(server.jobId)
				end, { Name = "Pick" })
				Components.setSelected(pick, Net.picked[server.jobId] == true)
				if Net.picked[server.jobId] then
					pick.Text = "Picked"
				end
			end
			if not server.current then
				Kit.button(buttons, "Summon me here", "Secondary", function()
					Actions.confirmAndSend({
						title = "Teleport to this server?",
						body = `You will leave this server and join {Kit.shortId(server.jobId)}.`,
						confirmText = "Teleport",
						action = Action.Summon,
						payload = { jobId = server.jobId },
						okText = "Teleporting now.",
					})
				end, { Name = "Summon" })
			end
		end
	end

	Net.on("servers", render)
	if options.pick then
		Net.on("scope", render)
	end
	render()
	return { render = render }
end

return ServerList
