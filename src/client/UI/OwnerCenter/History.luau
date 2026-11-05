-- Command history (the server's audit log, newest first) and Emergency restore.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local Actions = require(script.Parent.Actions)
local Messages = require(script.Parent.Messages)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)

local Action = Protocol.OverlordAction
local Colors = Theme.Colors

local History = {}

function History.buildHistory(page: Frame, _ctx: any)
	local scroll = Kit.page(page)
	Kit.heading(scroll, "Command history", 1)
	Kit.para(scroll, "The last actions taken from the Control Center, newest first.", 2)
	local bar = Kit.flow(scroll, 3, 8)
	Kit.button(bar, "Refresh", "Secondary", function()
		Net.loadAudit()
	end, { Name = "RefreshAudit" })
	local list = Kit.stack(scroll, 4, "AuditRows")

	local function render()
		Kit.clear(list)
		if #Net.audit == 0 then
			Kit.empty(list, "Nothing has been logged yet.", 1)
			return
		end
		for index, entry in Net.audit do
			local card = Kit.card(list, index, { Name = "Entry" })
			local refused = entry.outcome == "refused" or entry.outcome == "failed"
			local head = Kit.flow(card, 1, 8)
			Components.text({ Name = "Time", Text = if typeof(entry.t) == "number" then Kit.localTime(entry.t) else "time unknown", Style = "number", Size = UDim2.fromOffset(190, 24), Parent = head })
			Components.badge(entry.outcome or "no result", if refused then Colors.Danger else Colors.Success).Parent = head
			Components.text({ Name = "Action", Text = Kit.actionName(entry.action), Style = "strong", Wrap = true, LayoutOrder = 2, Parent = card })
			local detail = `Scope: {Net.describeScope(entry.scope)}.`
			if typeof(entry.presets) == "table" and #entry.presets > 0 then
				local names = {}
				for _, id in entry.presets do
					table.insert(names, Actions.nameOf(id))
				end
				detail ..= ` Presets: {table.concat(names, ", ")}.`
			end
			if refused and entry.reason then
				detail ..= ` {Messages.explain({ code = tostring(entry.reason) })}`
			end
			Kit.caption(card, detail, 3, Colors.TextDim)
		end
	end
	Net.on("audit", render)
	render()
	return {
		show = function()
			Net.loadAudit()
		end,
	}
end

local RESTORES = {
	{ id = "StopAll", action = Action.StopAll, name = "Stop all events", detail = "Ends every running event.", body = "Every running event ends.", ok = "All events stopped" },
	{ id = "RestoreEnvironment", action = Action.RestoreEnvironment, name = "Restore the environment", detail = "Puts lighting, sky, weather and structures back to normal.", body = "Lighting, sky, weather and structures go back to normal.", ok = "Environment restored" },
	{ id = "ClearEffects", action = Action.ClearEffects, name = "Clear visual effects", detail = "Removes every effect the events added.", body = "All event effects are removed.", ok = "Effects cleared" },
	{ id = "RestorePlayers", action = Action.RestorePlayers, name = "Restore players", detail = "Undoes size, speed and gravity changes on players.", body = "Player changes from events are undone.", ok = "Players restored" },
	{ id = "ReturnToDefault", action = Action.ReturnToDefault, name = "Return everything to default", detail = "Stops events and restores the world and players in one step.", body = "Events stop and the world and players return to normal.", ok = "Back to default" },
}

function History.buildEmergency(page: Frame, _ctx: any)
	local scroll = Kit.page(page)
	Kit.heading(scroll, "Emergency restore", 1)
	local info = Kit.para(scroll, "", 2)
	local function paint()
		info.Text = `These commands use the scope chosen in the strip below: {Net.scopeText()}. Each one asks you to confirm first.`
	end
	Net.on("scope", paint)
	paint()
	for index, item in RESTORES do
		local card = Kit.card(scroll, 2 + index, { Name = "Restore_" .. item.id })
		Components.text({ Name = "Name", Text = item.name, Style = "strong", Wrap = true, LayoutOrder = 1, Parent = card })
		Kit.caption(card, item.detail, 2)
		Kit.button(card, item.name, if item.id == "StopAll" or item.id == "ReturnToDefault" then "Danger" else "Secondary", function()
			Actions.scoped(item.action, `{item.name}?`, item.body, item.ok, true)
		end, { Name = item.id, LayoutOrder = 3 })
	end
	return { show = paint }
end

return History
