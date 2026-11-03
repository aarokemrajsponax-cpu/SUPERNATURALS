-- Server monitor and Global server control. Both read the live server list; the control page
-- adds the scope explanation, the picked servers and the world settings for this server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminEvents = require(ReplicatedStorage.Shared.Config.AdminEvents)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Seasons = require(ReplicatedStorage.Shared.Seasons)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local Shell = require(script.Parent.Parent.Shell)
local Actions = require(script.Parent.Actions)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local ServerList = require(script.Parent.ServerList)

local Action = Protocol.OverlordAction
local AdminAction = Protocol.AdminAction
local Colors = Theme.Colors

local Monitor = {}

function Monitor.buildMonitor(page: Frame, ctx: any)
	local scroll = Kit.page(page)
	Kit.heading(scroll, "Server monitor", 1)
	Kit.para(scroll, "Every server of this game that reports in. Pick servers here to use the Pick servers scope in the strip below.", 2)
	ServerList.build(scroll, { order = 3, pick = true })
	return {
		show = function()
			Net.request(Action.Servers)
		end,
		tick = nil,
	}
end

local SCOPE_HELP = {
	here = "Commands run only on the server you are in.",
	all = "Commands go to every live server of this game. Servers that cannot be reached are listed in the answer.",
	test = "Commands go only to servers flagged as test servers.",
	jobs = "Commands go only to the servers you picked in the Server monitor.",
}

function Monitor.buildControl(page: Frame, ctx: any)
	local scroll = Kit.page(page)
	Kit.heading(scroll, "Global server control", 1)
	local scopeCard = Kit.card(scroll, 2, { Name = "ScopeCard" })
	Kit.subheading(scopeCard, "Scope", 1)
	local scopeLine = Kit.para(scopeCard, "", 2)
	scopeLine.Name = "ScopeHelp"
	local scopeButtons = Kit.flow(scopeCard, 3, 8)
	local options = { { "here", "This server" }, { "all", "All servers" }, { "test", "Test servers" }, { "jobs", "Pick servers" } }
	local scopeControls: { [string]: TextButton } = {}
	for _, option in options do
		scopeControls[option[1]] = Kit.button(scopeButtons, option[2], "Ghost", function()
			Net.setScope(option[1])
		end, { Name = "Scope_" .. option[1] })
	end
	local function paintScope()
		for id, button in scopeControls do
			Components.setSelected(button, id == Net.scopeId)
		end
		local text = SCOPE_HELP[Net.scopeId]
		if Net.scopeId == "jobs" then
			text ..= ` {#Net.pickedList()} picked.`
		end
		scopeLine.Text = text
	end
	Net.on("scope", paintScope)
	paintScope()

	local running = Kit.card(scroll, 3, { Name = "Running" })
	Kit.subheading(running, "Events", 1)
	local buttons = Kit.flow(running, 2, 8)
	Kit.button(buttons, "Stop all events", "Danger", function()
		Actions.scoped(Action.StopAll, "Stop every event?", "Every running event ends.", "All events stopped", true)
	end, { Name = "StopAll" })
	Kit.button(buttons, "Return to default", "Secondary", function()
		Actions.scoped(Action.ReturnToDefault, "Return to default?", "Events stop and the world goes back to its normal state.", "Back to default", true)
	end, { Name = "ReturnToDefault" })

	-- Settings that only apply to the server the owner is in (the old panel's controls)
	local world = Kit.card(scroll, 4, { Name = "World" })
	Kit.subheading(world, "This server only", 1)
	Kit.caption(world, "Time of day, season and ending matches are not sent to other servers.", 2)
	Kit.caption(world, "Time of day", 3)
	local times = Kit.flow(world, 4, 8)
	for _, option in AdminEvents.TimesOfDay do
		local label = string.gsub(option.label, "^[^%w]+", "")
		Kit.button(times, label, "Secondary", function()
			ctx.sendAdmin(AdminAction.SetTime, option.id)
			Shell.toast(`Time of day set: {label}.`, "success")
		end, { Name = "Time_" .. option.id })
	end
	Kit.caption(world, "Season", 5)
	local seasons = Kit.flow(world, 6, 8)
	Kit.button(seasons, "Automatic", "Secondary", function()
		ctx.sendAdmin(AdminAction.SetSeason, "Auto")
		Shell.toast("Season follows the calendar.", "success")
	end, { Name = "Season_Auto" })
	local names = {}
	for id in Seasons.Themes do
		table.insert(names, id)
	end
	table.sort(names)
	for _, id in names do
		Kit.button(seasons, Seasons.Themes[id].name, "Secondary", function()
			ctx.sendAdmin(AdminAction.SetSeason, id)
			Shell.toast(`Season set to {Seasons.Themes[id].name}.`, "success")
		end, { Name = "Season_" .. id })
	end
	Kit.button(world, "End all matches", "Danger", function()
		Shell.confirm({
			title = "End every match?",
			body = "All matches on this server end now.",
			danger = true,
			confirmText = "End matches",
			onConfirm = function()
				ctx.sendAdmin(AdminAction.EndMatches)
				Shell.toast("Ending all matches on this server.", "success")
			end,
		})
	end, { Name = "EndMatches", LayoutOrder = 7 })
	return { show = paintScope }
end

return Monitor
