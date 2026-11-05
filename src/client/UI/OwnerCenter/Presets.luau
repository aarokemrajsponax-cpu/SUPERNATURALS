-- Saved presets: the selection tray (built from the catalogue's "Add to selection"), saving it
-- as a named combination, and running, loading or deleting saved combinations.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local Shell = require(script.Parent.Parent.Shell)
local Actions = require(script.Parent.Actions)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)

local Action = Protocol.OverlordAction
local Colors = Theme.Colors

local Presets = {}

local function newId(): string
	return string.format("combo_%x%04x", os.time() % 0xFFFFFFF, math.random(0, 0xFFFF))
end

local function namesOf(entries: { any }): string
	local names = {}
	for _, entry in entries do
		table.insert(names, Actions.nameOf(entry.preset))
	end
	return table.concat(names, ", ")
end

local function copyEntries(entries: { any }): { any }
	local out = {}
	for _, entry in entries do
		table.insert(out, { preset = entry.preset, overrides = entry.overrides })
	end
	return out
end

function Presets.build(page: Frame, ctx: any)
	local scroll = Kit.page(page)
	Kit.heading(scroll, "Saved presets", 1)
	Kit.para(scroll, "Build a selection of up to eight presets from the catalogue sections, then run it at once or save it as a named combination.", 2)

	local tray = Kit.card(scroll, 3, { Name = "Tray" })
	Kit.subheading(tray, "Current selection", 1)
	local trayList = Kit.stack(tray, 2, "TrayList")
	local nameBox = Kit.input(tray, { Name = "ComboName", Placeholder = "Name for this combination", MaxLen = 40, LayoutOrder = 3 })
	local feedback = Components.text({ Name = "Feedback", Text = "", Style = "body", Wrap = true, LayoutOrder = 5, Parent = tray })
	local buttons = Kit.flow(tray, 4, 8)

	local function say(text: string, ok: boolean)
		feedback.Text = text
		feedback.TextColor3 = if ok then Colors.Success else Colors.Danger
	end

	Kit.button(buttons, "Save combination", "Primary", function()
		if #Net.selection == 0 then
			say(Net.Messages.explain({ code = "no_selection" }), false)
			return
		end
		local name = nameBox.Text
		if not string.match(name, "%S") or string.find(name, "[^%w %-'%.]") then
			say("Give it a name of letters, numbers, spaces, hyphens, apostrophes or full stops (up to 40).", false)
			return
		end
		Net.request(Action.SaveCombo, { id = newId(), name = name, entries = copyEntries(Net.selection) }, function(result)
			local text, ok = Actions.report(result, `Saved {name}.`)
			say(text, ok)
			if ok then
				nameBox.Text = ""
			end
		end)
	end, { Name = "SaveCombo" })
	Kit.button(buttons, "Activate selection", "Secondary", function()
		if #Net.selection == 0 then
			say(Net.Messages.explain({ code = "no_selection" }), false)
			return
		end
		Actions.activate(copyEntries(Net.selection), `{#Net.selection} presets`, namesOf(Net.selection), say)
	end, { Name = "ActivateSelection" })
	Kit.button(buttons, "Clear", "Ghost", function()
		Net.clearSelection()
	end, { Name = "ClearSelection" })

	Kit.subheading(scroll, "Saved combinations", 4)
	local comboList = Kit.stack(scroll, 5, "ComboList")

	local function renderTray()
		Kit.clear(trayList)
		if #Net.selection == 0 then
			Kit.empty(trayList, "Empty. Open an events section and choose Add to selection on a preset.", 1)
			return
		end
		for index, entry in Net.selection do
			local row = Kit.flow(trayList, index, 8)
			Components.text({ Name = "Name", Text = Actions.nameOf(entry.preset), Style = "body", Color = Colors.Text, Size = UDim2.new(1, -120, 0, 44), AlignY = "Center", Parent = row })
			Kit.button(row, "Remove", "Ghost", function()
				Net.removeFromSelection(index)
			end, { Name = "Remove" })
		end
	end

	local function renderCombos()
		Kit.clear(comboList)
		if #Net.combos == 0 then
			Kit.empty(comboList, "No saved combinations yet.", 1)
			return
		end
		for index, combo in Net.combos do
			local card = Kit.card(comboList, index, { Name = "Combo_" .. tostring(combo.id) })
			Components.text({ Name = "Name", Text = tostring(combo.name), Style = "strong", Wrap = true, LayoutOrder = 1, Parent = card })
			Kit.caption(card, namesOf(combo.entries or {}), 2)
			local row = Kit.flow(card, 3, 8)
			Kit.button(row, "Activate", "Primary", function()
				Actions.activate(copyEntries(combo.entries or {}), tostring(combo.name), namesOf(combo.entries or {}), function(text, ok)
					Shell.toast(text, if ok then "success" else "error")
				end)
			end, { Name = "Run" })
			Kit.button(row, "Load into selection", "Secondary", function()
				Net.selection = copyEntries(combo.entries or {})
				Net.emit("selection")
			end, { Name = "Load" })
			Kit.button(row, "Delete", "Danger", function()
				Actions.confirmAndSend({
					title = `Delete {combo.name}?`,
					body = "The saved combination is removed. Presets themselves are not affected.",
					confirmText = "Delete",
					danger = true,
					action = Action.DeleteCombo,
					payload = { id = combo.id },
					okText = "Combination deleted.",
				})
			end, { Name = "Delete" })
		end
	end

	Net.on("selection", renderTray)
	Net.on("combos", renderCombos)
	renderTray()
	renderCombos()
	local _ = ctx
	return {
		show = function()
			Net.loadCatalogue()
			Net.request(Action.ListCombos)
			renderTray()
		end,
	}
end

return Presets
