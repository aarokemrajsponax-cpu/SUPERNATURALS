-- Custom event creator: build an event from one to six effects (each effect's settings come
-- from the server's catalogue: type, range, options, default), name it, save it, then preview
-- or activate it like any preset. Saved customs also appear in the catalogue sections.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local Actions = require(script.Parent.Actions)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)

local Action = Protocol.OverlordAction
local Colors = Theme.Colors

local Custom = {}

local MAX_EFFECTS = 6
local DURATIONS = { 10, 30, 60, 120, 300, 600, 900, 1200, 1800, 3600, 7200, 21600 }
local NICE = { 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 25, 50, 100, 250, 500, 1000 }

local function numberChoices(spec: any): ({ number }, number)
	local min, max = tonumber(spec.min) or 0, tonumber(spec.max) or 1
	local raw = (max - min) / 20
	local step = NICE[#NICE]
	for _, candidate in NICE do
		if candidate >= raw then
			step = candidate
			break
		end
	end
	local list, has = {}, false
	local value = min
	while value <= max + 1e-9 and #list < 60 do
		local rounded = math.floor(value / step + 0.5) * step
		table.insert(list, rounded)
		value += step
	end
	local default = tonumber(spec.default)
	if default then
		for _, existing in list do
			if math.abs(existing - default) < 1e-9 then
				has = true
			end
		end
		if not has then
			table.insert(list, default)
			table.sort(list)
		end
	end
	return list, step
end

local function formatNumber(step: number): (number) -> string
	return function(value)
		return if step < 1 then string.format("%.2f", value) else string.format("%d", value)
	end
end

-- One settings control for an effect parameter; writes into params[name] when the owner changes it
local function paramControl(parent: Instance, name: string, spec: any, params: { [string]: any }, order: number)
	local current = if params[name] ~= nil then params[name] else spec.default
	if spec.type == "number" then
		local choices, step = numberChoices(spec)
		local start = tonumber(current) or choices[1]
		local best = choices[1]
		for _, candidate in choices do
			if math.abs(candidate - start) < math.abs(best - start) then
				best = candidate
			end
		end
		Kit.stepper(parent, name, choices, best, formatNumber(step), function(value)
			params[name] = value
		end, { Name = "Param_" .. name, LayoutOrder = order })
	elseif spec.type == "enum" and typeof(spec.options) == "table" then
		Kit.stepper(parent, name, spec.options, current, tostring, function(value)
			params[name] = value
		end, { Name = "Param_" .. name, LayoutOrder = order })
	elseif spec.type == "bool" then
		Kit.stepper(parent, name, { false, true }, current == true, function(value)
			return if value then "On" else "Off"
		end, function(value)
			params[name] = value
		end, { Name = "Param_" .. name, LayoutOrder = order })
	elseif spec.type == "color" then
		local holder = Kit.stack(parent, order, "Param_" .. name, 4)
		Kit.caption(holder, name, 1)
		local swatches = Kit.swatches(holder, 2, function(rgb)
			params[name] = rgb
		end)
		swatches.set(if typeof(params[name]) == "table" then params[name] else nil)
	elseif spec.type == "string" then
		local holder = Kit.stack(parent, order, "Param_" .. name, 4)
		Kit.caption(holder, name, 1)
		Kit.input(holder, { Name = "Text_" .. name, Text = if typeof(current) == "string" then current else "", MaxLen = spec.maxLen or 40, LayoutOrder = 2 }, function(text)
			params[name] = text
		end)
	end
end

local function sortedKeys(map: { [string]: any }): { string }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

function Custom.build(page: Frame, ctx: any)
	local scroll = Kit.page(page)
	Kit.heading(scroll, "Custom event creator", 1)
	Kit.para(scroll, "Combine one to six effects into your own event. The server checks every setting again and refuses anything out of range.", 2)

	local form = { id = nil :: string?, duration = 300, slots = {} :: { any } }

	local meta = Kit.card(scroll, 3, { Name = "Details" })
	local nameBox = Kit.input(meta, { Name = "EventName", Placeholder = "Event name (up to 40 characters)", MaxLen = 40, LayoutOrder = 1 })
	local descriptionBox = Kit.input(meta, { Name = "EventDescription", Placeholder = "Short description (optional, up to 140 characters)", MaxLen = 140, Multi = true, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 72) })
	local durationStepper = Kit.stepper(meta, "Duration", DURATIONS, form.duration, Kit.seconds, function(value)
		form.duration = value
	end, { Name = "Duration", LayoutOrder = 3 })

	Kit.subheading(scroll, "Effects", 4)
	local slotsHolder = Kit.stack(scroll, 5, "Slots")
	local picker = Kit.card(scroll, 7, { Name = "Picker" })
	picker.Visible = false
	local addButton

	local feedback = Components.text({ Name = "Feedback", Text = "", Style = "body", Wrap = true, LayoutOrder = 9, Parent = scroll })
	local function say(text: string, ok: boolean)
		feedback.Text = text
		feedback.TextColor3 = if ok then Colors.Success else Colors.Danger
	end

	local function renderSlots()
		Kit.clear(slotsHolder)
		if #form.slots == 0 then
			Kit.empty(slotsHolder, "No effects yet. Add at least one.", 1)
		end
		for index, slot in form.slots do
			local effect = Net.catalogue and Net.catalogue.effects[slot.effect]
			local card = Kit.card(slotsHolder, index, { Name = "Slot_" .. index })
			Components.text({ Name = "EffectName", Text = slot.effect, Style = "strong", Wrap = true, LayoutOrder = 1, Parent = card })
			if effect and effect.description then
				Kit.caption(card, effect.description, 2)
			end
			if effect then
				for order, key in sortedKeys(effect.params or {}) do
					paramControl(card, key, effect.params[key], slot.params, 10 + order)
				end
			end
			Kit.button(card, "Remove effect", "Ghost", function()
				table.remove(form.slots, index)
				renderSlots()
			end, { Name = "RemoveEffect", LayoutOrder = 99 })
		end
		if addButton then
			addButton.Visible = #form.slots < MAX_EFFECTS
		end
	end

	-- The effect picker --------------------------------------------------------------------
	local query = ""
	local pickerList
	local function renderPicker()
		Kit.clear(pickerList)
		local effects = Net.catalogue and Net.catalogue.effects
		if not effects then
			Kit.empty(pickerList, "Loading effects from the server.", 1)
			return
		end
		local shown = 0
		for _, key in sortedKeys(effects) do
			local effect = effects[key]
			local hay = string.lower(key .. " " .. tostring(effect.description or ""))
			if string.find(hay, query, 1, true) then
				shown += 1
				if shown > 12 then
					Kit.caption(pickerList, "More effects match. Narrow the search to see them.", 100)
					break
				end
				local row = Kit.card(pickerList, shown, { Name = "Pick_" .. key, BackgroundColor3 = Colors.Raised })
				Components.text({ Name = "Name", Text = key, Style = "strong", Wrap = true, LayoutOrder = 1, Parent = row })
				Kit.caption(row, tostring(effect.description or ""), 2)
				Kit.button(row, "Add this effect", "Secondary", function()
					if #form.slots >= MAX_EFFECTS then
						say(Net.Messages.explain({ code = "too_many_effects" }), false)
						return
					end
					table.insert(form.slots, { effect = key, params = {} })
					picker.Visible = false
					renderSlots()
				end, { Name = "Choose", LayoutOrder = 3 })
			end
		end
		if shown == 0 then
			Kit.empty(pickerList, "No effect matches that search.", 1)
		end
	end
	Kit.subheading(picker, "Choose an effect", 1)
	Kit.input(picker, { Name = "EffectSearch", Placeholder = "Search effects", MaxLen = 40, LayoutOrder = 2 }, function(text)
		query = string.lower(text)
		renderPicker()
	end)
	pickerList = Kit.stack(picker, 3, "PickerList")
	Kit.button(picker, "Close", "Ghost", function()
		picker.Visible = false
	end, { Name = "ClosePicker", LayoutOrder = 4 })

	addButton = Kit.button(scroll, "Add an effect", "Secondary", function()
		Net.loadCatalogue()
		picker.Visible = true
		renderPicker()
	end, { Name = "AddEffect", LayoutOrder = 6 })

	-- Saving and running ----------------------------------------------------------------------

	local function payload(): (any?, string?)
		local name = nameBox.Text
		if not string.match(name, "%S") then
			return nil, "Give the event a name."
		end
		if #form.slots == 0 then
			return nil, "Add at least one effect."
		end
		local effects = {}
		for _, slot in form.slots do
			table.insert(effects, { effect = slot.effect, params = slot.params })
		end
		return {
			id = form.id,
			name = name,
			description = descriptionBox.Text,
			duration = form.duration,
			effects = effects,
		}
	end

	-- Saves, refreshes the catalogue so the new event is known, then calls after(id, name)
	local function save(after: ((string, string) -> ())?)
		local body, problem = payload()
		if not body then
			say(problem :: string, false)
			return
		end
		Net.request(Action.CustomSave, body, function(result)
			local text, ok = Actions.report(result, `Saved {body.name}.`)
			say(text, ok)
			if not ok then
				return
			end
			form.id = result.data and result.data.id or form.id
			Net.request(Action.Catalogue, nil, function()
				if after and form.id then
					after(form.id, body.name)
				end
			end)
		end)
	end

	local buttons = Kit.flow(scroll, 8, 8)
	Kit.button(buttons, "Save", "Primary", function()
		save(nil)
	end, { Name = "Save" })
	Kit.button(buttons, "Save and preview", "Secondary", function()
		save(function(id)
			Net.request(Action.Preview, { preset = id, seconds = 10 }, function(result)
				local text, ok = Actions.report(result, "Previewing on this server for 10 s.")
				say(text, ok)
			end)
		end)
	end, { Name = "SavePreview" })
	Kit.button(buttons, "Save and activate", "Secondary", function()
		save(function(id, name)
			Actions.activate({ { preset = id } }, name, "", say)
		end)
	end, { Name = "SaveActivate" })
	Kit.button(buttons, "Start over", "Ghost", function()
		form.id = nil
		form.slots = {}
		form.duration = 300
		nameBox.Text = ""
		descriptionBox.Text = ""
		durationStepper.set(300)
		renderSlots()
		say("", true)
	end, { Name = "Reset" })

	-- Saved customs -----------------------------------------------------------------------------
	Kit.subheading(scroll, "Your saved custom events", 10)
	local savedList = Kit.stack(scroll, 11, "SavedCustoms")
	local function renderSaved()
		Kit.clear(savedList)
		if #Net.customs == 0 then
			Kit.empty(savedList, "No custom events saved yet.", 1)
			return
		end
		for index, item in Net.customs do
			local card = Kit.card(savedList, index, { Name = "Custom_" .. tostring(item.id) })
			Components.text({ Name = "Name", Text = tostring(item.name), Style = "strong", Wrap = true, LayoutOrder = 1, Parent = card })
			Kit.caption(card, `{#(item.effects or {})} effects, {Kit.seconds(tonumber(item.duration) or 300)}. {item.description or ""}`, 2)
			local row = Kit.flow(card, 3, 8)
			Kit.button(row, "Edit", "Secondary", function()
				form.id = item.id
				form.duration = tonumber(item.duration) or 300
				form.slots = {}
				for _, spec in item.effects or {} do
					local params = {}
					for key, value in spec.params or {} do
						params[key] = value
					end
					table.insert(form.slots, { effect = spec.effect, params = params })
				end
				nameBox.Text = tostring(item.name)
				descriptionBox.Text = tostring(item.description or "")
				durationStepper.set(form.duration)
				renderSlots()
				say(`Editing {item.name}. Save replaces it.`, true)
			end, { Name = "Edit" })
			Kit.button(row, "Preview", "Secondary", function()
				Net.request(Action.Preview, { preset = item.id, seconds = 10 }, function(result)
					Actions.report(result, "Previewing on this server for 10 s.")
				end)
			end, { Name = "Preview" })
			Kit.button(row, "Activate", "Primary", function()
				Actions.activate({ { preset = item.id } }, tostring(item.name), "", nil)
			end, { Name = "Activate" })
			Kit.button(row, "Delete", "Danger", function()
				Actions.confirmAndSend({
					title = `Delete {item.name}?`,
					body = "The custom event is removed for good.",
					confirmText = "Delete",
					danger = true,
					action = Action.CustomDelete,
					payload = { id = item.id },
					okText = "Custom event deleted.",
					done = function(_, ok)
						if ok then
							Net.loadCatalogue(true)
						end
					end,
				})
			end, { Name = "Delete" })
		end
	end
	Net.on("customs", renderSaved)
	Net.on("catalogue", function()
		renderSlots()
		if picker.Visible then
			renderPicker()
		end
	end)
	renderSlots()
	renderSaved()
	local _ = ctx
	return {
		show = function()
			Net.loadCatalogue()
			Net.request(Action.CustomList)
		end,
	}
end

return Custom
