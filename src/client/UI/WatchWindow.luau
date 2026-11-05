-- The Watch window (Window:Watch): live matches you can spectate, with Watch and Exit, and a
-- free prediction card per match. Opened by the lounge prompts, the lounge's own screens and
-- anything else that sends Window:Watch. Data comes from the server's Matches event (the
-- SpectatorController hands it to setMatches); the window asks for a fresh list when it opens
-- and every few seconds while it stays open, never per frame.
--
-- Predictions are free and informational (owner rule): no stakes, no rewards of any kind. The
-- card shows the community percentages, your own pick, and your own totals from the profile
-- (stats.predictions, stats.predictionsCorrect).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Components = require(script.Parent.Components)
local Shell = require(script.Parent.Shell)
local Theme = require(script.Parent.Theme)
local Profile = require(script.Parent.Parent.Profile)

local Colors = Theme.Colors
local make = Components.make

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchRequest = Remotes:WaitForChild("MatchRequest") :: RemoteEvent

local WatchWindow = {}

local POLL_SECONDS = 3

local matches: { any } = {}
local spectating = false
local column: GuiObject? = nil
local shownAt = 0

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function nameOf(entry: any, index: number): string
	local fighter = entry.fighters and entry.fighters[index]
	return if fighter then fighter.name else "Fighter"
end

local function card(parent: Instance, name: string, order: number): Frame
	local item = make("Frame", {
		Name = name, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.PanelLight, BackgroundTransparency = 0.3, BorderSizePixel = 0, Parent = parent,
	}, { Components.corner(), Components.stroke(Colors.Stroke, 1, 0.7), Components.padding(16, 16, 16, 16) })
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = item })
	return item
end

local function buttonRow(parent: Instance, order: number): Frame
	return make("Frame", {
		Name = "Buttons", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, Parent = parent,
	}, { make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
	}) })
end

-- The player's own totals: informational only
function WatchWindow.statsText(): string
	local profile = Profile.get()
	local stats = profile and profile.stats
	local total = if stats then stats.predictions or 0 else 0
	local correct = if stats then stats.predictionsCorrect or 0 else 0
	if total == 0 then
		return "You have not made a prediction yet."
	end
	return `Your predictions: {total} made, {correct} correct, {math.floor(100 * correct / total + 0.5)}% accuracy.`
end

local function render()
	local root = column
	if not root then
		return
	end
	for _, child in root:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- Your totals and the rule
	local top = card(root, "StatsCard", nextOrder())
	Components.text({ Name = "Heading", Text = "Watch live matches", Style = "Heading", LayoutOrder = 1, Parent = top })
	Components.text({ Name = "Stats", Text = WatchWindow.statsText(), Style = "Body", Color = Colors.TextDim, Wrap = true, LayoutOrder = 2, Parent = top })
	Components.text({
		Name = "Rule", Text = "Predictions are free and only for fun. They never cost or pay currency, items or rewards.",
		Style = "Caption", Wrap = true, LayoutOrder = 3, Parent = top,
	})
	if spectating then
		local row = buttonRow(top, 4)
		Components.button("Exit spectating", { Name = "ExitButton", Variant = "Primary", KeepCase = true, Size = UDim2.fromOffset(200, 44), Parent = row }, function()
			MatchRequest:FireServer(Protocol.MatchAction.StopSpectating)
		end)
	end

	if #matches == 0 then
		local empty = card(root, "EmptyCard", nextOrder())
		Components.text({ Name = "Heading", Text = "No matches are running right now", Style = "Heading", LayoutOrder = 1, Parent = empty })
		Components.text({
			Name = "Body", Text = "Start one from Play, or practise on dummies in the Training Studio. Matches appear here the moment they start.",
			Style = "Body", Color = Colors.TextDim, Wrap = true, LayoutOrder = 2, Parent = empty,
		})
		return
	end

	local serverNow = workspace:GetServerTimeNow()
	for _, entry in matches do
		local item = card(root, "Match_" .. entry.id, nextOrder())
		local title = table.concat(entry.names or {}, " vs ")
		Components.text({ Name = "Title", Text = title, Style = "Heading", LayoutOrder = 1, Parent = item })
		local clockText = if entry.fightStartedAt then `{clock(serverNow - entry.fightStartedAt)} elapsed` else "starting"
		Components.text({
			Name = "Detail", Text = `{entry.mode} on {entry.arena}  |  {clockText}  |  {entry.watchers or 0} watching`,
			Style = "Body", Color = Colors.TextDim, Wrap = true, LayoutOrder = 2, Parent = item,
		})
		local powers = {}
		for _, fighter in entry.fighters or {} do
			table.insert(powers, `{fighter.name}: {fighter.power}`)
		end
		Components.text({ Name = "Powers", Text = table.concat(powers, "   "), Style = "Caption", Wrap = true, LayoutOrder = 3, Parent = item })
		local actions = buttonRow(item, 4)
		Components.button("Watch", { Name = "WatchButton", Variant = "Primary", KeepCase = true, Size = UDim2.fromOffset(140, 44), LayoutOrder = 1, Parent = actions }, function()
			MatchRequest:FireServer(Protocol.MatchAction.Spectate, entry.id)
		end)

		-- Prediction card
		local fighters = entry.fighters or {}
		if #fighters >= 2 then
			local a, b = fighters[1], fighters[2]
			local tally = entry.tally or { counts = {}, total = 0 }
			local total = tally.total or 0
			local pctA = if total == 0 then 0 else math.floor(100 * (tally.counts[a.id] or 0) / total + 0.5)
			local pctB = if total == 0 then 0 else 100 - pctA
			Components.divider({ LayoutOrder = 5, Parent = item })
			if entry.yours then
				local picked = if entry.yours == a.id then a.name else b.name
				Components.text({ Name = "Pick", Text = `Your prediction has been recorded: {picked}.`, Style = "Label", Wrap = true, LayoutOrder = 6, Parent = item })
			elseif entry.predictionOpen then
				Components.text({ Name = "Question", Text = "Who do you think will win? Picks close 20 seconds into the fight.", Style = "Label", Wrap = true, LayoutOrder = 6, Parent = item })
				local picks = buttonRow(item, 7)
				for index, fighter in { a, b } do
					Components.button(`Pick {fighter.name}`, {
						Name = "PickButton" .. index, Variant = "Secondary", KeepCase = true, Size = UDim2.fromOffset(220, 44), LayoutOrder = index, Parent = picks,
					}, function()
						MatchRequest:FireServer(Protocol.MatchAction.Predict, entry.id, fighter.id)
					end)
				end
			else
				Components.text({ Name = "Closed", Text = "Predictions are closed for this match.", Style = "Label", Color = Colors.TextDim, LayoutOrder = 6, Parent = item })
			end
			local summary = if total == 0 then "No predictions yet." else `Community: {a.name} {pctA}%, {b.name} {pctB}%  ({total} {if total == 1 then "prediction" else "predictions"})`
			Components.text({ Name = "Community", Text = summary, Style = "Caption", Wrap = true, LayoutOrder = 8, Parent = item })
			local track = make("Frame", {
				Name = "CommunityBar", LayoutOrder = 9, Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = Colors.Raised, BorderSizePixel = 0, Parent = item,
			}, { Components.corner(UDim.new(0, 4)) })
			make("Frame", { Name = "FillA", Size = UDim2.fromScale(pctA / 100, 1), BackgroundColor3 = Colors.Accent, BorderSizePixel = 0, Parent = track })
		end
	end
end

-- Fresh list from the server (SpectatorController calls this on each Matches event)
function WatchWindow.setMatches(list: { any })
	matches = list
	render()
end

function WatchWindow.setSpectating(value: boolean)
	if spectating ~= value then
		spectating = value
		render()
	end
end

function WatchWindow.getMatches(): { any }
	return matches
end

local function build(body: Frame, _api: any)
	column = Components.scroll({ Name = "WatchColumn", Padding = 2, Parent = body })
	Components.list(column, Theme.Space.L)
	render()
	shownAt = 0
	return {
		onOpen = function()
			shownAt = 0
			MatchRequest:FireServer(Protocol.MatchAction.ListMatches)
			render()
		end,
		update = function(dt: number)
			shownAt += dt
			if shownAt >= POLL_SECONDS then
				shownAt = 0
				MatchRequest:FireServer(Protocol.MatchAction.ListMatches)
			end
		end,
	}
end

function WatchWindow.register()
	Shell.registerWindow("Watch", {
		title = "Watch Matches",
		label = "WATCH",
		icon = "eye",
		order = 7,
		nav = false,
		size = Vector2.new(760, 600),
		build = build,
	})
end

return WatchWindow
