-- Announcement center (the owner's side): write the text, pick banner or toast, how long it
-- shows, and send it with the chosen scope. The display every player sees is AnnounceDisplay.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local Actions = require(script.Parent.Actions)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)

local Action = Protocol.OverlordAction
local Colors = Theme.Colors

local Announce = {}

local MAX_CHARS = 160
local SECONDS = { 3, 4, 5, 6, 8, 10, 12, 15 }

function Announce.build(page: Frame, _ctx: any)
	local scroll = Kit.page(page)
	Kit.heading(scroll, "Announcement center", 1)
	Kit.para(scroll, "A banner sits under the top bar for everyone on the targeted servers. A toast is a short message at the screen edge. Text goes through the Roblox filter and you can send one every ten seconds.", 2)
	local card = Kit.card(scroll, 3, { Name = "Composer" })
	local counter
	local box = Kit.input(card, { Name = "Message", Placeholder = "Write the announcement", MaxLen = MAX_CHARS, Multi = true, LayoutOrder = 1 }, function(text)
		counter.Text = `{utf8.len(text) or #text} of {MAX_CHARS} characters`
	end)
	counter = Components.text({ Name = "Counter", Text = `0 of {MAX_CHARS} characters`, Style = "mono", LayoutOrder = 2, Parent = card })

	local style = "banner"
	local seconds = 6
	local styleRow = Kit.flow(card, 3, 8)
	local styleButtons: { [string]: TextButton } = {}
	local function paintStyle()
		for id, button in styleButtons do
			Components.setSelected(button, id == style)
		end
	end
	for _, option in { { "banner", "Banner" }, { "toast", "Toast" } } do
		styleButtons[option[1]] = Kit.button(styleRow, option[2], "Ghost", function()
			style = option[1]
			paintStyle()
		end, { Name = "Style_" .. option[1] })
	end
	paintStyle()
	Kit.stepper(card, "Shows for", SECONDS, seconds, Kit.seconds, function(value)
		seconds = value
	end, { Name = "Seconds", LayoutOrder = 4 })
	local scopeLine = Kit.caption(card, "", 5)
	local function paintScope()
		scopeLine.Text = `Scope: {Net.scopeText()}`
	end
	Net.on("scope", paintScope)
	paintScope()
	local feedback = Components.text({ Name = "Feedback", Text = "", Style = "body", Wrap = true, LayoutOrder = 7, Parent = card })
	Kit.button(card, "Send announcement", "Primary", function()
		local text = box.Text
		if not string.match(text, "%S") then
			feedback.Text = "Write something first."
			feedback.TextColor3 = Colors.Danger
			return
		end
		local scope, why = Net.scopeValue()
		if not scope then
			feedback.Text = Net.Messages.explain({ code = why })
			feedback.TextColor3 = Colors.Danger
			return
		end
		Actions.confirmAndSend({
			title = "Send this announcement?",
			body = `"{text}"\nShown as a {style} for {Kit.seconds(seconds)}.\nScope: {Net.scopeText()}.`,
			confirmText = "Send",
			action = Action.Announce,
			payload = { text = text, style = style, seconds = seconds, scope = scope },
			okText = "Announcement sent.",
			done = function(sentence, ok)
				feedback.Text = sentence
				feedback.TextColor3 = if ok then Colors.Success else Colors.Danger
				if ok then
					box.Text = ""
				end
			end,
		})
	end, { Name = "Send", LayoutOrder = 6 })
	return { show = paintScope }
end

return Announce
