-- Community goals (the owner's side): the server cannot read the game's like count, so the owner
-- looks at the game page now and then and types the number here. Every player gets each goal's
-- reward once the count reaches it, whether or not they liked the game. Lowering the number
-- later never takes a reward back. The server checks the owner and the number again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local Actions = require(script.Parent.Actions)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)

local Action = Protocol.OverlordAction
local Colors = Theme.Colors

local CommunityGoals = {}

local function commas(n: number): string
	local out = tostring(math.floor(n))
	while true do
		local replaced, count = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		out = replaced
		if count == 0 then
			break
		end
	end
	return out
end

-- "1,200" or " 640 " -> 1200, 640; anything else -> nil
function CommunityGoals.parse(text: string): number?
	local digits = string.gsub(text, "[%s,]", "")
	if digits == "" or not string.match(digits, "^%d+$") or #digits > 10 then
		return nil
	end
	return tonumber(digits)
end

function CommunityGoals.build(page: Frame, _ctx: any)
	local scroll = Kit.page(page)
	Kit.heading(scroll, "Community goals", 1)
	Kit.para(scroll, "Roblox does not tell the game its like count, so enter it here from the game page. At each goal every player gets the reward, liked or not.", 2)

	local status = Kit.card(scroll, 3, { Name = "Status" })
	local countLine = Components.text({ Name = "Count", Text = "Loading", Style = "subheading", Wrap = true, LayoutOrder = 1, Parent = status })
	local dateLine = Kit.caption(status, "", 2)
	local list = Kit.stack(status, 3, "Goals", 6)

	local form = Kit.card(scroll, 4, { Name = "Form" })
	Kit.caption(form, "Current likes on the game page. Lowering the number later never takes a reward back.", 1)
	local box = Kit.input(form, { Name = "Likes", Placeholder = "For example 640", MaxLen = 13, LayoutOrder = 2 })
	local feedback = Components.text({ Name = "Feedback", Text = "", Style = "body", Wrap = true, LayoutOrder = 4, Parent = form })

	local function render(view: any)
		if typeof(view) ~= "table" then
			return
		end
		Kit.clear(list)
		if view.setAt and view.setAt > 0 then
			countLine.Text = `Reported count: {commas(view.likes)} likes`
			dateLine.Text = `Set {Kit.localTime(view.setAt)} ({Kit.ago(view.setAt)})`
		else
			countLine.Text = "No count entered yet"
			dateLine.Text = "Players see this on the board near the entrance."
		end
		for index, goal in view.goals or {} do
			local line = `{commas(goal.likes)} likes: everyone gets {goal.text}`
			local row = Components.text({
				Name = "Goal_" .. tostring(goal.id),
				Text = `{line}. {if goal.reached then "Reached" else "Not reached"}`,
				Style = "body",
				Color = if goal.reached then Colors.Success else Colors.Text,
				Wrap = true,
				LayoutOrder = index,
				Parent = list,
			})
			local _ = row
		end
	end

	local function load()
		Net.request(Action.GoalsState, nil, function(result)
			if typeof(result) == "table" and result.ok then
				render(result.data)
			else
				countLine.Text = "Could not load the count"
				dateLine.Text = Net.Messages.explain(result)
			end
		end)
	end

	Kit.button(form, "Save count", "Primary", function()
		local value = CommunityGoals.parse(box.Text)
		if not value or value > 1e9 then
			feedback.Text = Net.Messages.explain({ code = "bad_likes" })
			feedback.TextColor3 = Colors.Danger
			return
		end
		Actions.confirmAndSend({
			title = "Save the like count?",
			body = `Set the count to {commas(value)} likes. Every goal at or below it is given to every player, once.`,
			confirmText = "Save",
			action = Action.GoalsSet,
			payload = { likes = value },
			okText = "Like count saved.",
			done = function(sentence, ok, result)
				feedback.Text = sentence
				feedback.TextColor3 = if ok then Colors.Success else Colors.Danger
				if ok then
					render(result.data)
					box.Text = ""
				end
			end,
		})
	end, { Name = "Save", LayoutOrder = 3, Size = UDim2.fromOffset(180, Theme.Size.Control) })

	load()
	return { show = load }
end

return CommunityGoals
