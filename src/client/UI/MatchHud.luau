-- Everything shown during a match: a fighting-game top bar (the clock in Michroma, the mode
-- and arena as a small line, one light entry per fighter), the knockout feed on the right
-- (newest on top), announcements and the big countdown numbers in the middle, and the
-- results panel at the end. Text over the world has a thin dark outline instead of a box;
-- no emoji, no gradients.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Icons = require(script.Parent.Icons)

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

local SCORE_CARD = Vector2.new(176, 48)
local CLOCK_SIZE = 34
local NOTICE_HOLD = 3
local FEED_WIDTH = 320
local FEED_MAX = 5
local FEED_SECONDS = 5
local RESULTS_WIDTH = 560
-- Results table columns, measured from the right edge
local COLUMN_WIDTH = 60
local COLUMNS = { "SCORE", "KO", "DOWN" }
local RANK_COLORS = {
	Colors.Gold,
	Colors.SteelLight,
	Colors.Copper,
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
		BackgroundTransparency = Theme.Glass.Panel,
		BorderSizePixel = 0,
	}
	for key, value in props do
		merged[key] = value
	end
	return make("Frame", merged, {
		Components.corner(Theme.SmallCorner),
	})
end

-- A thin dark outline on text that sits over the 3D world (instead of a box behind it)
local function outlineText(label: TextLabel, thickness: number?): UIStroke
	return make("UIStroke", { Color = Colors.Ink, Thickness = thickness or 1.5, Transparency = 0.35, Parent = label })
end

function MatchHud.build(parent: Instance, onReturn: () -> ())
	-- Top: clock, mode line and one entry per fighter ------------------------------------
	local top = make("Frame", {
		Name = "MatchTop",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Space.S),
		Size = UDim2.fromOffset(SCORE_CARD.X * 4 + Space.S * 3, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})
	Components.list(top, 2, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	local timerPill = make("Frame", { Name = "Timer", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 1, Parent = top })
	local timer = Components.text({
		Name = "Clock",
		Text = "0:00",
		Style = "display",
		TextSize = CLOCK_SIZE,
		AlignX = "Center",
		Size = UDim2.new(1, 0, 0, 42),
		Parent = timerPill,
	})
	outlineText(timer, 2)
	local modeLabel = Components.text({
		Name = "Mode",
		Style = "caption",
		Color = Colors.TextDim,
		AlignX = "Center",
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = timerPill,
	})
	outlineText(modeLabel, 1.5)
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
		Style = "countdown",
		TextSize = Theme.TextSize.Countdown,
		AlignX = "Center",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(560, 160),
		TextTruncate = Enum.TextTruncate.None,
		Visible = false,
		Parent = parent,
	})
	make("UIStroke", { Color = Colors.Ink, Thickness = 4, Transparency = 0.35, Parent = countdown })
	local countdownScale = make("UIScale", { Parent = countdown })

	local function pop(text: string, color: Color3)
		countdown.Visible = true
		countdown.Text = text
		countdown.TextColor3 = color
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
		Components.padding(Space.XL),
	})
	local cardStroke = Components.stroke(Colors.Stroke, 1, 0.4)
	cardStroke.Parent = card
	Components.list(card, Space.M, { HorizontalAlignment = Enum.HorizontalAlignment.Center })

	local headline = Components.text({
		Name = "Headline",
		Text = Theme.track("Victory"),
		Style = "hero",
		TextSize = Theme.TextSize.Hero,
		AlignX = "Center",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 64),
		Parent = card,
	})
	local reason = Components.text({ Name = "Reason", Style = "Body", Color = Colors.TextDim, AlignX = "Center", LayoutOrder = 2, Parent = card })
	local winnerLine = Components.text({ Name = "Winner", Style = "strong", Color = Colors.Gold, AlignX = "Center", LayoutOrder = 3, Parent = card })
	Components.accentLine({ LayoutOrder = 4, Parent = card })

	-- Column headers line up with the row numbers below
	local headerRow = make("Frame", { Name = "Columns", LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Parent = card })
	Components.padding(0, Space.M, 0, Space.M).Parent = headerRow
	Components.text({ Text = "FIGHTER", Style = "overline", Color = Colors.TextMuted, Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -40 - COLUMN_WIDTH * 3, 1, 0), Parent = headerRow })
	for index, name in COLUMNS do
		Components.text({
			Text = name,
			Style = "overline",
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
	local returnLabel = Components.text({ Name = "Returning", Style = "caption", AlignX = "Center", LayoutOrder = 7, Parent = card })
	Components.button("BACK TO LOBBY", {
		Name = "Back",
		Variant = "Primary",
		LayoutOrder = 8,
		Size = UDim2.new(1, 0, 0, 48),
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
		local gone = entry.left == true
		-- Tone only: no outline. Yours is lighter with a cyan bar; a fighter who left is dimmed
		local box = make("Frame", {
			Name = "Score",
			LayoutOrder = order,
			Size = UDim2.fromOffset(SCORE_CARD.X, SCORE_CARD.Y),
			BackgroundColor3 = if mine then Colors.Selected else Colors.Panel,
			BackgroundTransparency = if gone then 0.75 elseif mine then 0.1 else 0.35,
			BorderSizePixel = 0,
			Parent = scores,
		}, { Components.corner(Theme.SmallCorner) })
		if mine then
			make("Frame", {
				Name = "You",
				Size = UDim2.new(0, 3, 1, 0),
				BackgroundColor3 = Colors.Cyan,
				BorderSizePixel = 0,
				Parent = box,
			}, { Components.corner(Theme.TinyCorner) })
		end
		local alpha = if gone then 0.55 else 0
		Components.text({
			Name = "Name",
			Text = entry.name,
			Style = "label",
			Weight = "Bold",
			TextSize = 15,
			Color = if mine then Colors.Text else Colors.TextDim,
			TextTransparency = alpha,
			Position = UDim2.fromOffset(14, 5),
			Size = UDim2.new(1, -14 - 52, 0, 20),
			Parent = box,
		})
		Components.text({
			Name = "Detail",
			Text = if gone then "Left" else `{entry.knockouts or 0} KO`,
			Style = "caption",
			Color = Colors.TextMuted,
			TextTransparency = alpha,
			Position = UDim2.fromOffset(14, 25),
			Size = UDim2.new(1, -14 - 52, 0, 18),
			Parent = box,
		})
		Components.text({
			Name = "Points",
			Text = tostring(entry.score),
			Style = "number",
			TextSize = 22,
			AlignX = "Right",
			Color = if entry.score < 0 then Colors.Danger elseif entry.score > 0 then Colors.Gold else Colors.Text,
			TextTransparency = alpha,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -Space.M, 0.5, 0),
			Size = UDim2.fromOffset(46, 30),
			Parent = box,
		})
	end

	local function setState(snapshot)
		local previous = state
		state = snapshot
		top.Visible = true
		modeLabel.Text = `{snapshot.modeName}  ·  {snapshot.arena}`
		clearChildren(scores)
		for order, entry in snapshot.participants do
			scoreCard(order, entry)
		end
		local count = #snapshot.participants
		top.Size = UDim2.fromOffset(math.max(320, count * SCORE_CARD.X + (count - 1) * Space.S), 0)
		if previous and previous.phase == "Countdown" and snapshot.phase == "Active" then
			pop("FIGHT!", Colors.AccentHover)
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
		local function iconPiece(order: number, name: string, color: Color3)
			local drawn = Components.icon(name, 16, color)
			drawn.LayoutOrder = order
			drawn.Parent = entry
		end
		local victim = tostring(data.victim)
		if data.credited then
			local credited = tostring(data.credited)
			piece(1, credited, if credited == player.DisplayName then Colors.Cyan else Colors.Text, "Bold")
			iconPiece(2, "swords", Colors.Accent)
			piece(3, victim, if victim == player.DisplayName then Colors.Cyan else Colors.TextDim, "SemiBold")
		else
			iconPiece(1, "skull", Colors.Danger)
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
			headline.Text = Theme.track("Draw")
			accent = Colors.Cyan
		elseif won then
			headline.Text = Theme.track("Victory")
			accent = Colors.Gold
		else
			headline.Text = Theme.track("Defeat")
			accent = Colors.Danger
		end
		headline.TextColor3 = accent
		cardStroke.Color = accent
		reason.Text = REASONS[data.reason] or ""
		local winners = if typeof(data.winners) == "table" then data.winners else {}
		winnerLine.Visible = #winners > 0 and not data.draw
		winnerLine.Text = if #winners > 1 then "Winners: " .. table.concat(winners, ", ") else "Winner: " .. tostring(winners[1] or "")
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

	-- Announcements: a headline in Michroma capitals with a thin dark outline, a short
	-- sentence-case line under it and fine rules either side. "SUDDEN DEATH! Next knockout
	-- wins." splits into headline and line at the first "! " or ". ".
	local noticeToken = 0
	local notice = make("Frame", {
		Name = "Announcement",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(640, 100),
		BackgroundTransparency = 1,
		Active = false,
		Visible = false,
		Parent = parent,
	})
	local noticeHead = Components.text({
		Name = "Headline",
		Style = "display",
		TextSize = 30,
		AlignX = "Center",
		Size = UDim2.new(1, 0, 0, 40),
		Parent = notice,
	})
	outlineText(noticeHead, 2)
	local noticeSub = Components.text({
		Name = "Subtitle",
		Style = "strong",
		Weight = "Medium",
		TextSize = 18,
		Color = Colors.Text,
		AlignX = "Center",
		Position = UDim2.fromOffset(0, 44),
		Lines = 2,
		Parent = notice,
	})
	outlineText(noticeSub, 1.5)
	local rules = {}
	for _, side in { -1, 1 } do
		table.insert(rules, make("Frame", {
			Name = "Rule",
			AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5),
			Size = UDim2.fromOffset(72, 1),
			BackgroundColor3 = Colors.Text,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Parent = notice,
		}))
	end
	local noticeScale = make("UIScale", { Parent = notice })

	local function announce(text: string, color: Color3?)
		noticeToken += 1
		local token = noticeToken
		local head, sub = string.match(text, "^(.-)[!%.]%s+(.+)$")
		if not head then
			head, sub = string.gsub(text, "[!%.]$", ""), ""
		end
		-- Only a short phrase is a headline; a long notice reads as a plain line
		if utf8.len(head) == nil or utf8.len(head) > 24 then
			head, sub = "", text
		end
		noticeSub.Position = UDim2.fromOffset(0, if head == "" then 8 else 44)
		local tracked = Theme.track(head)
		noticeHead.Text = tracked
		noticeHead.TextColor3 = color or (if string.find(head, "^SUDDEN DEATH") then Colors.Danger else Colors.Text)
		noticeSub.Text = sub
		local half = Components.textWidth(tracked, 30, Theme.Faces.Display) * 0.6 + Space.L
		rules[1].Position = UDim2.new(0.5, -half, 0, 20)
		rules[2].Position = UDim2.new(0.5, half, 0, 20)
		for _, rule in rules do
			rule.Visible = head ~= "" and half * 2 < 600
		end
		-- On a short screen the scoreboard reaches further down, so the notice drops below it
		local camera = workspace.CurrentCamera
		local short = camera ~= nil and camera.ViewportSize.Y < 500
		notice.Position = UDim2.fromScale(0.5, if short then 0.42 else 0.3)
		notice.Visible = true
		noticeScale.Scale = 0.92
		TweenService:Create(noticeScale, Motion.Pop, { Scale = 1 }):Play()
		Components.fade(notice, true, Motion.Normal)
		task.delay(NOTICE_HOLD, function()
			if token == noticeToken then
				Components.fade(notice, false, TweenInfo.new(0.4), function()
					if token == noticeToken then
						notice.Visible = false
					end
				end)
			end
		end)
	end

	local function clear()
		state = nil
		results = nil
		lastCount = nil
		top.Visible = false
		countdown.Visible = false
		notice.Visible = false
		noticeToken += 1
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
		local info = `{state.modeName}  ·  {state.arena}`
		if state.phase == "Countdown" then
			timer.Text = Theme.track("Get ready")
			timer.TextSize = 24
			timer.TextColor3 = Colors.Text
			modeLabel.Text = info
			local count = math.max(1, math.ceil(remaining))
			if remaining <= 0 then
				countdown.Visible = false
			elseif count ~= lastCount then
				lastCount = count
				pop(tostring(count), Colors.Text)
			end
		elseif state.phase == "Active" then
			timer.Text = formatTime(remaining)
			timer.TextSize = CLOCK_SIZE
			timer.TextColor3 = if remaining <= 10 then Colors.Danger else Colors.Text
			modeLabel.Text = info
		elseif state.phase == "SuddenDeath" then
			timer.Text = formatTime(remaining)
			timer.TextSize = CLOCK_SIZE
			timer.TextColor3 = Colors.Danger
			modeLabel.Text = `Sudden death  ·  {state.arena}`
		else
			timer.Text = Theme.track("Match over")
			timer.TextSize = 24
			timer.TextColor3 = Colors.TextDim
			modeLabel.Text = info
		end
	end

	return {
		setState = setState,
		addKnockout = addKnockout,
		showResults = showResults,
		clear = clear,
		update = update,
		announce = announce,
	}
end

return MatchHud
