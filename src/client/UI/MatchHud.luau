-- Everything shown during a match: the timer pill and a score card per
-- fighter at the top, the knockout feed on the right (newest on top), the big
-- countdown numbers in the middle, and the results panel at the end.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local Colors = Theme.Colors
local Space = Theme.Space
local Motion = Theme.Motion
local make = Components.make

local player = Players.LocalPlayer
local myId = "Player:" .. player.UserId

local MatchHud = {}

local REASONS = {
	TimeUp = "Time's up!",
	SuddenDeath = "Decided in sudden death",
	Draw = "Nobody could break the tie",
	Forfeit = "A fighter left the match",
}

local SCORE_CARD = Vector2.new(152, 52)
local FEED_WIDTH = 320
local FEED_MAX = 5
local FEED_SECONDS = 5
local RESULTS_WIDTH = 560
-- Results table columns, measured from the right edge
local COLUMN_WIDTH = 60
local COLUMNS = { "SCORE", "KO", "DOWN" }
local RANK_COLORS = {
	Color3.fromRGB(255, 205, 90),
	Color3.fromRGB(200, 210, 230),
	Color3.fromRGB(222, 150, 96),
}

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function clearChildren(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function glass(props: { [string]: any }): Frame
	local merged: { [string]: any } = {
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.14,
		BorderSizePixel = 0,
	}
	for key, value in props do
		merged[key] = value
	end
	return make("Frame", merged, {
		Components.corner(Theme.SmallCorner),
		Components.glassGradient(),
	})
end

function MatchHud.build(parent: Instance, onReturn: () -> ())
	-- Top: timer pill and score cards ----------------------------------------------------
	local top = make("Frame", {
		Name = "MatchTop",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Space.M),
		Size = UDim2.fromOffset(SCORE_CARD.X * 4 + Space.S * 3, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})
	Components.list(top, Space.S, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	local timerPill = glass({ Name = "Timer", LayoutOrder = 1, Size = UDim2.fromOffset(240, 66), Parent = top })
	local timerStroke = Components.stroke(Colors.Stroke, 1.5, 0.6)
	timerStroke.Parent = timerPill
	;(timerPill:FindFirstChildOfClass("UICorner") :: UICorner).CornerRadius = UDim.new(0, 14)
	local modeLabel = Components.text({
		Name = "Mode",
		Style = "Micro",
		AlignX = "Center",
		Position = UDim2.fromOffset(Space.M, 7),
		Size = UDim2.new(1, -Space.M * 2, 0, 16),
		Parent = timerPill,
	})
	local timer = Components.text({
		Name = "Clock",
		Text = "0:00",
		Style = "Title",
		Weight = "Heavy",
		TextSize = 30,
		AlignX = "Center",
		Position = UDim2.fromOffset(Space.S, 24),
		Size = UDim2.new(1, -Space.S * 2, 0, 36),
		Parent = timerPill,
	})
	local scores = make("Frame", {
		Name = "Scores",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, SCORE_CARD.Y),
		BackgroundTransparency = 1,
		Parent = top,
	})
	Components.list(scores, Space.S, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})

	-- Big countdown in the middle -------------------------------------------------------
	local countdown = Components.text({
		Name = "Countdown",
		Style = "Display",
		Weight = "Heavy",
		TextSize = Theme.TextSize.Countdown,
		AlignX = "Center",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(560, 160),
		TextTruncate = Enum.TextTruncate.None,
		Visible = false,
		Parent = parent,
	})
	local countdownGradient = make("UIGradient", {
		Color = ColorSequence.new(Colors.Cyan, Colors.Purple),
		Rotation = 90,
		Parent = countdown,
	})
	make("UIStroke", { Color = Colors.Ink, Thickness = 4, Transparency = 0.25, Parent = countdown })
	local countdownScale = make("UIScale", { Parent = countdown })

	local function pop(text: string, gradient: ColorSequence)
		countdown.Visible = true
		countdown.Text = text
		countdownGradient.Color = gradient
		countdown.TextTransparency = 1
		countdownScale.Scale = 1.6
		TweenService:Create(countdownScale, Motion.Pop, { Scale = 1 }):Play()
		TweenService:Create(countdown, Motion.Fast, { TextTransparency = 0 }):Play()
	end

	-- Knockout feed, right side, newest on top ---------------------------------------------
	local feed = make("Frame", {
		Name = "Feed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Space.M, 0, Space.M),
		Size = UDim2.fromOffset(FEED_WIDTH, 220),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Components.list(feed, Space.XS + 2, { HorizontalAlignment = Enum.HorizontalAlignment.Right })

	-- Results --------------------------------------------------------------------------------
	local dim = make("Frame", {
		Name = "Results",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		-- Clicks stay on the results screen
		Active = true,
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	})
	local card = make("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(RESULTS_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = Theme.Glass.Window,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 21,
		Parent = dim,
	}, {
		Components.corner(Theme.Corner),
		Components.glassGradient(),
		Components.padding(Space.XL),
	})
	local cardStroke = Components.stroke(Colors.Stroke, 1.5, 0.5)
	cardStroke.Parent = card
	Components.list(card, Space.M, { HorizontalAlignment = Enum.HorizontalAlignment.Center })

	local headline = Components.text({
		Name = "Headline",
		Text = "VICTORY",
		Style = "Display",
		Weight = "Heavy",
		TextSize = Theme.TextSize.Hero,
		AlignX = "Center",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 64),
		Parent = card,
	})
	local headlineGradient = make("UIGradient", { Rotation = 90, Parent = headline })
	local reason = Components.text({ Name = "Reason", Style = "Body", Color = Colors.TextDim, AlignX = "Center", LayoutOrder = 2, Parent = card })
	local winnerLine = Components.text({ Name = "Winner", Style = "Label", Color = Colors.Gold, AlignX = "Center", LayoutOrder = 3, Parent = card })
	Components.accentLine({ LayoutOrder = 4, Parent = card })

	-- Column headers line up with the row numbers below
	local headerRow = make("Frame", { Name = "Columns", LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Parent = card })
	Components.padding(0, Space.M, 0, Space.M).Parent = headerRow
	Components.text({ Text = "FIGHTER", Style = "Micro", Color = Colors.TextMuted, Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -40 - COLUMN_WIDTH * 3, 1, 0), Parent = headerRow })
	for index, name in COLUMNS do
		Components.text({
			Text = name,
			Style = "Micro",
			Color = Colors.TextMuted,
			AlignX = "Right",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -COLUMN_WIDTH * (#COLUMNS - index), 0, 0),
			Size = UDim2.new(0, COLUMN_WIDTH, 1, 0),
			Parent = headerRow,
		})
	end
	local rows = make("Frame", {
		Name = "Rows",
		LayoutOrder = 6,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = card,
	})
	Components.list(rows, Space.XS + 2)
	local returnLabel = Components.text({ Name = "Returning", Style = "Caption", AlignX = "Center", LayoutOrder = 7, Parent = card })
	Components.button("BACK TO LOBBY", {
		Name = "Back",
		Variant = "Primary",
		LayoutOrder = 8,
		Size = UDim2.new(1, 0, 0, 48),
		TextSize = Theme.TextSize.Heading,
		Parent = card,
	}, onReturn)
	local cardScale = make("UIScale", { Parent = card })

	local state: any = nil
	local results: any = nil
	local lastCount: number? = nil
	-- Newest knockout first: each entry gets a lower LayoutOrder than the last
	local feedOrder = 0

	local function scoreCard(order: number, entry)
		local mine = entry.id == myId
		local box = glass({
			Name = "Score",
			LayoutOrder = order,
			Size = UDim2.fromOffset(SCORE_CARD.X, SCORE_CARD.Y),
			BackgroundColor3 = if mine then Colors.PanelLight else Colors.Panel,
			Parent = scores,
		})
		local outline = Components.stroke(if mine then Colors.Cyan else Colors.Stroke, 1.5, if mine then 0.1 else 0.7)
		outline.Parent = box
		make("Frame", {
			Name = "Strip",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.new(0, 3, 1, -18),
			BackgroundColor3 = if mine then Colors.Cyan elseif entry.npc then Colors.TextMuted else Colors.Purple,
			BorderSizePixel = 0,
			Parent = box,
		}, { Components.corner(Theme.PillCorner) })
		local alpha = if entry.left then 0.55 else 0
		Components.text({
			Name = "Name",
			Text = entry.name,
			Style = "Caption",
			Weight = "Bold",
			Color = if mine then Colors.Text else Colors.TextDim,
			TextTransparency = alpha,
			Position = UDim2.fromOffset(16, 8),
			Size = UDim2.new(1, -16 - 56, 0, 18),
			Parent = box,
		})
		Components.text({
			Name = "Detail",
			Text = if entry.left then "LEFT" else `{entry.knockouts or 0} KO`,
			Style = "Micro",
			Color = Colors.TextMuted,
			TextTransparency = alpha,
			Position = UDim2.fromOffset(16, 27),
			Size = UDim2.new(1, -16 - 56, 0, 16),
			Parent = box,
		})
		Components.text({
			Name = "Points",
			Text = tostring(entry.score),
			Style = "Title",
			Weight = "Heavy",
			AlignX = "Right",
			Color = if entry.score < 0 then Colors.Danger elseif entry.score > 0 then Colors.Gold else Colors.Text,
			TextTransparency = alpha,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -Space.M, 0.5, 0),
			Size = UDim2.fromOffset(52, 32),
			Parent = box,
		})
	end

	local function setState(snapshot)
		local previous = state
		state = snapshot
		top.Visible = true
		modeLabel.Text = string.upper(`{snapshot.modeName}  ·  {snapshot.arena}`)
		clearChildren(scores)
		for order, entry in snapshot.participants do
			scoreCard(order, entry)
		end
		local count = #snapshot.participants
		top.Size = UDim2.fromOffset(math.max(240, count * SCORE_CARD.X + (count - 1) * Space.S), 0)
		if previous and previous.phase == "Countdown" and snapshot.phase == "Active" then
			pop("FIGHT!", ColorSequence.new(Color3.fromRGB(255, 236, 160), Colors.Gold))
			task.delay(0.9, function()
				if countdown.Text == "FIGHT!" then
					TweenService:Create(countdown, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
				end
			end)
		end
	end

	local function addKnockout(data)
		feedOrder -= 1
		local entry = glass({
			Name = "Knockout",
			LayoutOrder = feedOrder,
			Size = UDim2.fromOffset(0, 34),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = feed,
		})
		Components.stroke(Colors.Stroke, 1, 0.75).Parent = entry
		Components.padding(0, Space.M, 0, Space.M).Parent = entry
		Components.list(entry, Space.S, {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		})
		local function piece(order: number, text: string, color: Color3, weight: string)
			Components.text({
				LayoutOrder = order,
				Text = text,
				Style = "Caption",
				Weight = weight,
				Color = color,
				Size = UDim2.fromScale(0, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				TextTruncate = Enum.TextTruncate.None,
				Parent = entry,
			})
		end
		local victim = tostring(data.victim)
		if data.credited then
			local credited = tostring(data.credited)
			piece(1, credited, if credited == player.DisplayName then Colors.Cyan else Colors.Text, "Bold")
			piece(2, "⚔", Colors.Gold, "Bold")
			piece(3, victim, if victim == player.DisplayName then Colors.Cyan else Colors.TextDim, "SemiBold")
		else
			piece(1, "💀", Colors.Danger, "Bold")
			piece(2, victim, Colors.Text, "Bold")
			piece(3, "was knocked out", Colors.TextDim, "Medium")
		end
		Components.fade(entry, true, Motion.Normal)
		task.delay(FEED_SECONDS - 0.5, function()
			if entry.Parent then
				Components.fade(entry, false, TweenInfo.new(0.5), function()
					entry:Destroy()
				end)
			end
		end)
		local items = {}
		for _, child in feed:GetChildren() do
			if child:IsA("GuiObject") then
				table.insert(items, child)
			end
		end
		if #items > FEED_MAX then
			table.sort(items, function(a, b)
				return a.LayoutOrder > b.LayoutOrder
			end)
			items[1]:Destroy()
		end
	end

	local function resultRow(rank: number, entry)
		local mine = entry.id == myId
		local row = make("Frame", {
			Name = "Row",
			LayoutOrder = rank,
			Size = UDim2.new(1, 0, 0, 42),
			BackgroundColor3 = if mine then Colors.Cyan else Colors.PanelLight,
			BackgroundTransparency = if mine then 0.82 else 0.45,
			BorderSizePixel = 0,
			Parent = rows,
		}, {
			Components.corner(Theme.SmallCorner),
			Components.stroke(if mine then Colors.Cyan else Colors.Stroke, 1, if mine then 0.3 else 0.85),
			Components.padding(0, Space.M, 0, Space.M),
		})
		local medal = RANK_COLORS[rank] or Colors.TextMuted
		local badge = make("Frame", {
			Name = "Rank",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = medal,
			BackgroundTransparency = if rank <= 3 then 0 else 0.7,
			BorderSizePixel = 0,
			Parent = row,
		}, { Components.corner(Theme.TinyCorner) })
		Components.text({
			Text = tostring(rank),
			Style = "Label",
			Weight = "Heavy",
			Color = if rank <= 3 then Colors.TextOnLight else Colors.Text,
			AlignX = "Center",
			Size = UDim2.fromScale(1, 1),
			Parent = badge,
		})
		Components.text({
			Name = "Name",
			Text = if entry.left then `{entry.name}  (left)` else entry.name,
			Style = "Label",
			Color = if entry.left then Colors.TextMuted else Colors.Text,
			Position = UDim2.fromOffset(40, 0),
			Size = UDim2.new(1, -40 - COLUMN_WIDTH * 3, 1, 0),
			Parent = row,
		})
		for index, value in { entry.score, entry.knockouts, entry.deaths } do
			Components.text({
				Text = tostring(value),
				Style = "Label",
				Weight = "ExtraBold",
				Color = if index == 1 and value < 0 then Colors.Danger elseif index == 1 then Colors.Gold else Colors.Text,
				AlignX = "Right",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -COLUMN_WIDTH * (#COLUMNS - index), 0, 0),
				Size = UDim2.new(0, COLUMN_WIDTH, 1, 0),
				Parent = row,
			})
		end
	end

	local function showResults(data)
		results = data
		local won = table.find(data.winnerIds, myId) ~= nil
		local accent
		if data.draw and won then
			headline.Text = "DRAW"
			headlineGradient.Color = ColorSequence.new(Color3.fromRGB(190, 245, 255), Colors.Cyan)
			accent = Colors.Cyan
		elseif won then
			headline.Text = "VICTORY"
			headlineGradient.Color = ColorSequence.new(Color3.fromRGB(255, 240, 180), Colors.Gold)
			accent = Colors.Gold
		else
			headline.Text = "DEFEAT"
			headlineGradient.Color = ColorSequence.new(Color3.fromRGB(255, 170, 180), Colors.Danger)
			accent = Colors.Danger
		end
		cardStroke.Color = accent
		reason.Text = REASONS[data.reason] or ""
		local winners = if typeof(data.winners) == "table" then data.winners else {}
		winnerLine.Visible = #winners > 0 and not data.draw
		winnerLine.Text = if #winners > 1 then "🏆  Winners: " .. table.concat(winners, ", ") else "🏆  Winner: " .. tostring(winners[1] or "")
		clearChildren(rows)
		for rank, entry in data.ranking do
			resultRow(rank, entry)
		end
		dim.Visible = true
		countdown.Visible = false
		cardScale.Scale = 0.9
		TweenService:Create(cardScale, Motion.Pop, { Scale = 1 }):Play()
		Components.fade(card, true, Motion.Slow)
	end

	local function clear()
		state = nil
		results = nil
		lastCount = nil
		top.Visible = false
		countdown.Visible = false
		dim.Visible = false
		clearChildren(feed)
	end

	local function update()
		if results then
			local seconds = math.max(0, math.ceil(results.returnsAt - workspace:GetServerTimeNow()))
			returnLabel.Text = `Back to the lobby in {seconds}s`
		end
		if not state then
			return
		end
		local remaining = state.phaseEndsAt - workspace:GetServerTimeNow()
		if state.phase == "Countdown" then
			timer.Text = "GET READY"
			timer.TextSize = Theme.TextSize.Heading
			timer.TextColor3 = Colors.Text
			timerStroke.Color = Colors.Stroke
			local count = math.max(1, math.ceil(remaining))
			if remaining <= 0 then
				countdown.Visible = false
			elseif count ~= lastCount then
				lastCount = count
				pop(tostring(count), ColorSequence.new(Colors.Cyan, Colors.Purple))
			end
		elseif state.phase == "Active" then
			timer.Text = formatTime(remaining)
			timer.TextSize = 30
			local urgent = remaining <= 10
			timer.TextColor3 = if urgent then Colors.Danger else Colors.Text
			timerStroke.Color = if urgent then Colors.Danger else Colors.Stroke
		elseif state.phase == "SuddenDeath" then
			timer.Text = "SUDDEN DEATH  " .. formatTime(remaining)
			timer.TextSize = Theme.TextSize.Heading
			timer.TextColor3 = Colors.Danger
			timerStroke.Color = Colors.Danger
		else
			timer.Text = "MATCH OVER"
			timer.TextSize = Theme.TextSize.Heading
			timer.TextColor3 = Colors.TextDim
			timerStroke.Color = Colors.Stroke
		end
	end

	return {
		setState = setState,
		addKnockout = addKnockout,
		showResults = showResults,
		clear = clear,
		update = update,
	}
end

return MatchHud
