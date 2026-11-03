-- The pattern every dangerous or wide button follows: show what will happen and the scope in a
-- Shell.confirm, send the request only after the owner agrees, then say plainly what came back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Shell = require(script.Parent.Parent.Shell)
local Messages = require(script.Parent.Messages)
local Net = require(script.Parent.Net)

local Action = Protocol.OverlordAction

local Actions = {}

-- True when any preset in the entries only runs in event mode
function Actions.needsEventMode(entries: { any }): boolean
	local catalogue = Net.catalogue
	for _, entry in entries do
		local preset = catalogue and catalogue.byId[entry.preset]
		if preset and preset.eventMode then
			return true
		end
	end
	return false
end

function Actions.nameOf(presetId: string): string
	local preset = Net.catalogue and Net.catalogue.byId[presetId]
	return if preset then preset.name else presetId
end

-- Reports a result as a toast and returns the sentence and whether it worked
function Actions.report(result: any, okText: string): (string, boolean)
	local ok = typeof(result) == "table" and result.ok == true
	local text = if ok then okText else Messages.explain(result)
	Shell.toast(text, if ok then "success" else "error")
	return text, ok
end

-- Confirm, then send. options: title, body, confirmText, danger, action, payload, okText,
-- scoped (adds the scope line to the dialog), done(text, ok, result)
function Actions.confirmAndSend(options: any)
	Shell.confirm({
		title = options.title,
		body = options.body,
		confirmText = options.confirmText or "Confirm",
		danger = options.danger,
		onConfirm = function()
			Net.request(options.action, options.payload, function(result)
				local text, ok = Actions.report(result, options.okText)
				if options.done then
					options.done(text, ok, result)
				end
			end)
		end,
	})
end

-- Activates entries ({ preset, overrides? }) on the chosen scope after a confirmation
function Actions.activate(entries: { any }, label: string, detail: string?, done: ((string, boolean, any) -> ())?)
	local scope, why = Net.scopeValue()
	if not scope then
		local text = Messages.explain({ code = why })
		Shell.toast(text, "error")
		if done then
			done(text, false, nil)
		end
		return
	end
	local eventMode = Actions.needsEventMode(entries)
	local lines = { `Scope: {Net.scopeText()}.` }
	if detail and detail ~= "" then
		table.insert(lines, 1, detail)
	end
	if eventMode then
		table.insert(lines, "This changes gameplay, so it runs in event mode.")
	end
	Actions.confirmAndSend({
		title = `Activate {label}?`,
		body = table.concat(lines, "\n"),
		confirmText = "Activate",
		action = Action.Activate,
		payload = { entries = entries, scope = scope, eventMode = if eventMode then true else nil },
		okText = `{label} is running ({Net.scopeText()}).`,
		done = function(text, ok, result)
			if ok then
				for _, entry in entries do
					Net.touchRecent(entry.preset)
				end
				Net.request(Action.State)
			end
			if done then
				done(text, ok, result)
			end
		end,
	})
end

-- Sends a scoped command (Stop, StopAll, RestoreEnvironment ...) after a confirmation
function Actions.scoped(action: string, title: string, body: string, okText: string, danger: boolean?, extra: { [string]: any }?, done: ((string, boolean, any) -> ())?)
	local scope, why = Net.scopeValue()
	if not scope then
		Shell.toast(Messages.explain({ code = why }), "error")
		return
	end
	local payload = { scope = scope }
	for key, value in extra or {} do
		payload[key] = value
	end
	Actions.confirmAndSend({
		title = title,
		body = `{body}\nScope: {Net.scopeText()}.`,
		confirmText = "Confirm",
		danger = danger,
		action = action,
		payload = payload,
		okText = `{okText} ({Net.scopeText()}).`,
		done = function(text, ok, result)
			if ok then
				Net.request(Action.State)
			end
			if done then
				done(text, ok, result)
			end
		end,
	})
end


return Actions
