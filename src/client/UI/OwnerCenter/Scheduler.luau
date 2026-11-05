-- Event scheduler: choose a preset, a saved combination or a custom event, a date and time in
-- the owner's local time (sent as unix seconds), a label and the scope; list and cancel items.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local Actions = require(script.Parent.Actions)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)

local Action = Protocol.OverlordAction
local Colors = Theme.Colors

local Scheduler = {}

local STATUS_COLOR = { pending = Colors.Cyan, done = Colors.Success, missed = Colors.Warning, cancelled = Colors.TextMuted }

-- "2026-11-03" and "14:30" -> unix seconds in local time
function Scheduler.parse(dateText: string, timeText: string): number?
	local y, m, d = string.match(dateText, "^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
	local h, mi = string.match(timeText, "^%s*(%d%d?):(%d%d)%s*$")
	if not y or not h then
		return nil
	end
	return Kit.toUnix(tonumber(y) :: number, tonumber(m) :: number, tonumber(d) :: number, tonumber(h) :: number, tonumber(mi) :: number)
end

function Scheduler.build(page: Frame, _ctx: any)
	local scroll = Kit.page(page)
	Kit.heading(scroll, "Event scheduler", 1)
	Kit.para(scroll, "Schedule something to start by itself. Times are in your local time. Any server may run it at the time; one server claims each item.", 2)

	local form = { kind = "preset", target = nil :: string?, targetName = "" }
	local card = Kit.card(scroll, 3, { Name = "Form" })

	Kit.caption(card, "What to run", 1)
	local kindRow = Kit.flow(card, 2, 8)
	local kindButtons: { [string]: TextButton } = {}
	local pickerList
	local chosenLine
	local query = ""

	local function renderChoices()
		Kit.clear(pickerList)
		local shown = 0
		local function offer(id: string, name: string, extra: string?)
			if query ~= "" and not string.find(string.lower(name), query, 1, true) then
				return
			end
			shown += 1
			if shown > 8 then
				return
			end
			local button = Kit.button(pickerList, name, "Ghost", function()
				form.target = id
				form.targetName = name
				chosenLine.Text = `Chosen: {name}`
			end, { Name = "Choice_" .. id, LayoutOrder = shown, Size = UDim2.new(1, 0, 0, 44) })
			local _ = extra
			Components.setSelected(button, form.target == id)
		end
		if form.kind == "preset" then
			for _, preset in if Net.catalogue then Net.catalogue.presets else {} do
				if preset.category ~= "Custom" then
					offer(preset.id, preset.name)
				end
			end
		elseif form.kind == "combo" then
			for _, combo in Net.combos do
				offer(combo.id, tostring(combo.name))
			end
		else
			for _, item in Net.customs do
				offer(item.id, tostring(item.name))
			end
		end
		if shown == 0 then
			Kit.empty(pickerList, if form.kind == "preset" then "No preset matches." elseif form.kind == "combo" then "No saved combinations yet." else "No custom events yet.", 1)
		elseif shown > 8 then
			Kit.caption(pickerList, "More match. Narrow the search.", 99)
		end
	end

	for _, option in { { "preset", "Preset" }, { "combo", "Saved combination" }, { "custom", "Custom event" } } do
		kindButtons[option[1]] = Kit.button(kindRow, option[2], "Ghost", function()
			form.kind = option[1]
			form.target = nil
			chosenLine.Text = "Nothing chosen yet."
			for id, button in kindButtons do
				Components.setSelected(button, id == form.kind)
			end
			renderChoices()
		end, { Name = "Kind_" .. option[1] })
	end
	Components.setSelected(kindButtons.preset, true)
	Kit.input(card, { Name = "ChoiceSearch", Placeholder = "Search", MaxLen = 40, LayoutOrder = 3 }, function(text)
		query = string.lower(text)
		renderChoices()
	end)
	pickerList = Kit.stack(card, 4, "Choices", 4)
	chosenLine = Components.text({ Name = "Chosen", Text = "Nothing chosen yet.", Style = "label", Wrap = true, LayoutOrder = 5, Parent = card })

	Kit.caption(card, "When (your local time)", 6)
	local soon = os.time() + 3600
	local startText = Kit.localTime(soon)
	local dateBox = Kit.input(card, { Name = "Date", Placeholder = "Date as YYYY-MM-DD", Text = string.sub(startText, 1, 10), MaxLen = 10, LayoutOrder = 7 })
	local timeBox = Kit.input(card, { Name = "Time", Placeholder = "Time as HH:MM, 24 hour", Text = string.sub(startText, 12, 16), MaxLen = 5, LayoutOrder = 8 })
	local whenLine = Components.text({ Name = "When", Text = "", Style = "mono", Wrap = true, LayoutOrder = 9, Parent = card })
	local function paintWhen()
		local at = Scheduler.parse(dateBox.Text, timeBox.Text)
		whenLine.Text = if at then `Starts {Kit.localTime(at)} local time ({Kit.seconds(at - os.time())} from now)` else "Enter the date and time in the formats shown."
	end
	dateBox:GetPropertyChangedSignal("Text"):Connect(paintWhen)
	timeBox:GetPropertyChangedSignal("Text"):Connect(paintWhen)
	paintWhen()

	local labelBox = Kit.input(card, { Name = "Label", Placeholder = "Label (up to 40 characters)", MaxLen = 40, LayoutOrder = 10 })
	local scopeLine = Kit.caption(card, "", 11)
	local function paintScope()
		scopeLine.Text = `Scope: {Net.scopeText()}`
	end
	Net.on("scope", paintScope)
	paintScope()
	local feedback = Components.text({ Name = "Feedback", Text = "", Style = "body", Wrap = true, LayoutOrder = 13, Parent = card })
	local function say(text: string, ok: boolean)
		feedback.Text = text
		feedback.TextColor3 = if ok then Colors.Success else Colors.Danger
	end
	Kit.button(card, "Schedule it", "Primary", function()
		if not form.target then
			say("Choose what to run first.", false)
			return
		end
		local at = Scheduler.parse(dateBox.Text, timeBox.Text)
		if not at then
			say("Enter the date and time in the formats shown.", false)
			return
		end
		local label = labelBox.Text
		if not string.match(label, "%S") then
			label = form.targetName
		end
		local scope, why = Net.scopeValue()
		if not scope then
			say(Net.Messages.explain({ code = why }), false)
			return
		end
		local body = { at = at, label = label, scope = scope }
		if form.kind == "combo" then
			body.combo = form.target
		else
			body.entries = { { preset = form.target } }
			if Actions.needsEventMode(body.entries) then
				body.eventMode = true
			end
		end
		Net.request(Action.ScheduleAdd, body, function(result)
			local text, ok = Actions.report(result, `Scheduled {label} for {Kit.localTime(at)}.`)
			say(text, ok)
			if ok then
				Net.request(Action.ScheduleList)
			end
		end)
	end, { Name = "Schedule", LayoutOrder = 12 })

	Kit.subheading(scroll, "Scheduled items", 4)
	local list = Kit.stack(scroll, 5, "ScheduleRows")
	local function renderList()
		Kit.clear(list)
		if #Net.schedule == 0 then
			Kit.empty(list, "Nothing is scheduled.", 1)
			return
		end
		for index, item in Net.schedule do
			local row = Kit.card(list, index, { Name = "Item_" .. tostring(item.id) })
			local head = Kit.flow(row, 1, 8)
			Components.text({ Name = "At", Text = if typeof(item.at) == "number" then Kit.localTime(item.at) else "time unknown", Style = "number", Size = UDim2.fromOffset(190, 24), Parent = head })
			Components.badge(tostring(item.status or "pending"), STATUS_COLOR[item.status] or Colors.TextDim).Parent = head
			Components.text({ Name = "Label", Text = tostring(item.label or "Scheduled item"), Style = "strong", Wrap = true, LayoutOrder = 2, Parent = row })
			Kit.caption(row, `Scope: {Net.describeScope(item.scope)}`, 3)
			if item.status == "pending" then
				Kit.button(row, "Cancel", "Secondary", function()
					Net.request(Action.ScheduleCancel, { id = item.id }, function(result)
						Actions.report(result, "Cancelled.")
						Net.request(Action.ScheduleList)
					end)
				end, { Name = "Cancel", LayoutOrder = 4 })
			end
		end
	end
	Net.on("schedule", renderList)
	Net.on("combos", renderChoices)
	Net.on("customs", renderChoices)
	Net.on("catalogue", renderChoices)
	renderChoices()
	renderList()
	return {
		show = function()
			Net.loadCatalogue()
			Net.request(Action.ListCombos)
			Net.request(Action.CustomList)
			Net.request(Action.ScheduleList)
			paintScope()
		end,
	}
end

return Scheduler
