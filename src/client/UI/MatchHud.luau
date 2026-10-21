-- Everything shown during a match: timer and scores at the top, the big
-- countdown, the knockout feed, and the results screen at the end.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local Colors = Theme.Colors
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

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function MatchHud.build(parent: Instance, onReturn: () -> ())
	-- Top bar: mode, timer, scores
	local top = Components.panel({
		Name = "MatchTop",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(420, 104),
		Visible = false,
		Parent = parent,
	})
	local modeLabel = Components.label("", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 6),
		TextColor3 = Colors.TextDim,
		Font = Theme.Fonts.Heading,
		MaxTextSize = 13,
		Parent = top,
	})
	local timer = Components.label("0:00", {
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 20),
		Font = Theme.Fonts.Numbers,
		MaxTextSize = 32,
		Parent = top,
	})
	local scores = make("Frame", {
		Size = UDim2.new(1, -16, 0, 38),
		Position = UDim2.fromOffset(8, 58),
		BackgroundTransparency = 1,
		Parent = top,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	})

	-- Big countdown in the middle of the screen
	local countdown = Components.label("", {
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(420, 150),
		Font = Theme.Fonts.Title,
		TextColor3 = Colors.Text,
		TextStrokeTransparency = 0.3,
		MaxTextSize = 120,
		Visible = false,
		Parent = parent,
	})
	make("UIGradient", {
		Color = ColorSequence.new(Colors.Cyan, Colors.Purple),
		Rotation = 90,
		Parent = countdown,
	})

	-- Knockout feed, top right
	local feed = make("Frame", {
		Name = "Feed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(300, 220),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		make("UIListLayout", {
			Padding = UDim.new(0, 4),
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- Results ------------------------------------------------------------------------
	local dim = make("Frame", {
		Name = "Results",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	})
	local card = Components.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(480, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 21,
		Parent = dim,
	})
	Components.padding(18).Parent = card
	local cardList = make("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local headline = Components.label("VICTORY", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 54),
		Font = Theme.Fonts.Title,
		MaxTextSize = 52,
		Parent = cardList,
	})
	local reason = Components.label("", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = Colors.TextDim,
		MaxTextSize = 16,
		Parent = cardList,
	})
	local rows = make("Frame", {
		LayoutOrder = 3,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = cardList,
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local returnLabel = Components.label("", {
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 16),
		TextColor3 = Colors.TextDim,
		MaxTextSize = 13,
		Parent = cardList,
	})
	Components.button("BACK TO LOBBY", {
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 46),
		Parent = cardList,
	}, onReturn)

	local state: any = nil
	local results: any = nil
	local lastCount: number? = nil

	local function chip(order: number, entry)
		local mine = entry.id == myId
		local box = Components.panel({
			LayoutOrder = order,
			Size = UDim2.new(0, 96, 1, 0),
			BackgroundColor3 = if mine then Colors.PanelLight else Colors.Panel,
			Parent = scores,
		})
		local stroke = box:FindFirstChildOfClass("UIStroke")
		if stroke and mine then
			stroke.Color = Colors.Cyan
			stroke.Transparency = 0
		end
		Components.label(entry.name, {
			Size = UDim2.new(1, -36, 1, 0),
			Position = UDim2.fromOffset(6, 0),
			Font = Theme.Fonts.Heading,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTransparency = if entry.left then 0.6 else 0,
			MaxTextSize = 13,
			Parent = box,
		})
		Components.label(tostring(entry.score), {
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.new(0, 30, 1, 0),
			Position = UDim2.new(1, -6, 0, 0),
			Font = Theme.Fonts.Numbers,
			TextColor3 = if entry.score < 0 then Colors.Danger else Colors.Gold,
			MaxTextSize = 18,
			Parent = box,
		})
	end

	local function setState(snapshot)
		local previous = state
		state = snapshot
		top.Visible = true
		modeLabel.Text = string.upper(`{snapshot.modeName}  ·  {snapshot.arena}`)
		for _, child in scores:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for order, entry in snapshot.participants do
			chip(order, entry)
		end
		top.Size = UDim2.fromOffset(math.max(420, #snapshot.participants * 102 + 20), 104)
		if previous and previous.phase == "Countdown" and snapshot.phase == "Active" then
			countdown.Visible = true
			countdown.Text = "FIGHT!"
			countdown.TextTransparency = 0
			countdown.Size = UDim2.fromOffset(300, 110)
			TweenService:Create(countdown, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(420, 150) }):Play()
			task.delay(0.9, function()
				if countdown.Text == "FIGHT!" then
					TweenService:Create(countdown, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
				end
			end)
		end
	end

	local function addKnockout(data)
		local text = if data.credited then `{data.credited}  ⚔  {data.victim}` else `{data.victim} was knocked out`
		local entry = Components.panel({
			Size = UDim2.fromOffset(280, 30),
			LayoutOrder = -math.floor(os.clock() * 1000),
			Parent = feed,
		})
		Components.label(text, {
			Size = UDim2.new(1, -16, 1, 0),
			Position = UDim2.fromOffset(8, 0),
			Font = Theme.Fonts.Heading,
			TextXAlignment = Enum.TextXAlignment.Right,
			MaxTextSize = 14,
			Parent = entry,
		})
		task.delay(5, function()
			entry:Destroy()
		end)
		local items = {}
		for _, child in feed:GetChildren() do
			if child:IsA("GuiObject") then
				table.insert(items, child)
			end
		end
		if #items > 5 then
			table.sort(items, function(a, b)
				return a.LayoutOrder > b.LayoutOrder
			end)
			items[1]:Destroy()
		end
	end

	local function showResults(data)
		results = data
		local won = table.find(data.winnerIds, myId) ~= nil
		if data.draw and won then
			headline.Text = "DRAW"
			headline.TextColor3 = Colors.Cyan
		elseif won then
			headline.Text = "VICTORY"
			headline.TextColor3 = Colors.Gold
		else
			headline.Text = "DEFEAT"
			headline.TextColor3 = Colors.Danger
		end
		reason.Text = REASONS[data.reason] or ""
		for _, child in rows:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for rank, entry in data.ranking do
			local row = make("Frame", {
				LayoutOrder = rank,
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundColor3 = if entry.id == myId then Colors.PanelLight else Colors.Background,
				BackgroundTransparency = 0.2,
				Parent = rows,
			}, { Components.corner(Theme.SmallCorner) })
			Components.label(`#{rank}  {entry.name}{if entry.left then "  (left)" else ""}`, {
				Size = UDim2.new(0.6, 0, 1, 0),
				Position = UDim2.fromOffset(10, 0),
				Font = Theme.Fonts.Heading,
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 15,
				Parent = row,
			})
			Components.label(`{entry.score} pts   {entry.knockouts} KO   {entry.deaths} down`, {
				AnchorPoint = Vector2.new(1, 0),
				Size = UDim2.new(0.4, -10, 1, 0),
				Position = UDim2.new(1, -10, 0, 0),
				TextColor3 = Colors.TextDim,
				TextXAlignment = Enum.TextXAlignment.Right,
				MaxTextSize = 13,
				Parent = row,
			})
		end
		dim.Visible = true
		card.Position = UDim2.fromScale(0.5, 0.6)
		TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	end

	local function clear()
		state = nil
		results = nil
		lastCount = nil
		top.Visible = false
		countdown.Visible = false
		dim.Visible = false
	end

	local function update()
		if results then
			local seconds = math.max(0, math.ceil(results.returnsAt - workspace:GetServerTimeNow()))
			returnLabel.Text = `Returning to the lobby in {seconds}s`
		end
		if not state then
			return
		end
		local remaining = state.phaseEndsAt - workspace:GetServerTimeNow()
		if state.phase == "Countdown" then
			timer.Text = "GET READY"
			timer.TextColor3 = Colors.Text
			local count = math.max(1, math.ceil(remaining))
			countdown.Visible = remaining > 0
			if count ~= lastCount then
				lastCount = count
				countdown.Text = tostring(count)
				countdown.TextTransparency = 0
				countdown.Size = UDim2.fromOffset(300, 110)
				TweenService:Create(countdown, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(420, 150) }):Play()
			end
		elseif state.phase == "Active" then
			timer.Text = formatTime(remaining)
			timer.TextColor3 = if remaining <= 10 then Colors.Danger else Colors.Text
		elseif state.phase == "SuddenDeath" then
			timer.Text = "SUDDEN DEATH  " .. formatTime(remaining)
			timer.TextColor3 = Colors.Danger
		else
			timer.Text = "MATCH OVER"
			timer.TextColor3 = Colors.TextDim
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
