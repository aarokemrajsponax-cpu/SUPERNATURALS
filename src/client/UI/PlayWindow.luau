-- The Play window: how to fight. Mode cards on the left (Duel, Free-for-All,
-- Practice vs CPU, Training ground), the selected mode's rules on the right
-- with the button that queues or travels. Also owns the "searching" pill in
-- the top bar while you wait in a queue (it stays when the window closes).
-- Rules come from Shared/Config/Match; only icons and wording live here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MatchConfig = require(ReplicatedStorage.Shared.Config.Match)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Shell = require(script.Parent.Shell)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchRequest = Remotes:WaitForChild("MatchRequest") :: RemoteEvent

local Action = Protocol.MatchAction
local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make

local PlayWindow = {}

local TRAINING = "Training"
-- Ignore repeat presses for this long (the server rate-limits requests too)
local PRESS_COOLDOWN = 0.6

-- Per-choice look (the match rules themselves come from the config)
local LOOK = {
	Duel = { icon = "⚔️", accent = Colors.Cyan, tag = "1V1", action = "⚔  FIND A DUEL", subtitle = "Ranked by knockouts" },
	FreeForAll = { icon = "👥", accent = Colors.Purple, tag = "3-4 FIGHTERS", action = "👥  FIND A MATCH", subtitle = "Everyone for themselves" },
	Practice = { icon = "🤖", accent = Colors.Cyan, tag = "VS CPU", action = "🤖  START PRACTICE", subtitle = "Learn the controls" },
	Training = { icon = "🎯", accent = Colors.Purple, tag = "FREE ROAM", action = "🎯  GO TO TRAINING", subtitle = "No timer, no score" },
}

local TRAINING_INFO = {
	DisplayName = "Training Ground",
	Description = "Hit sparring dummies and try every move. Nothing is at stake and there's no timer.",
}

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- The four rule tiles for a choice, worded from the config
local function rulesFor(id: string): { { label: string, value: string } }
	if id == TRAINING then
		return {
			{ label = "PLAYERS", value = "Just you" },
			{ label = "TIME", value = "No limit" },
			{ label = "SCORE", value = "Not counted" },
			{ label = "WHERE", value = "Training ground" },
		}
	end
	local mode = MatchConfig.Modes[id]
	local players
	if (mode.Dummies or 0) > 0 and mode.MaxPlayers == 1 then
		players = "You vs CPU"
	elseif mode.MinPlayers == mode.MaxPlayers then
		players = `{mode.MaxPlayers} fighters`
	else
		players = `{mode.MinPlayers}-{mode.MaxPlayers} fighters`
	end
	local tie = if mode.TieRule == "SuddenDeath"
		then `Sudden death ({formatTime(mode.SuddenDeathDuration)})`
		else "Ends in a draw"
	return {
		{ label = "PLAYERS", value = players },
		{ label = "MATCH TIME", value = formatTime(mode.Duration) },
		{ label = "IF TIED", value = tie },
		{ label = "COUNTDOWN", value = `{mode.Countdown} seconds` },
	}
end

-- One line on how the match starts
local function startNote(id: string): string
	if id == TRAINING then
		return "Travel there any time outside a match."
	end
	local mode = MatchConfig.Modes[id]
	if (mode.Dummies or 0) > 0 then
		return "Starts right away against a sparring dummy."
	elseif mode.QueueFillDelay then
		return `Starts {mode.QueueFillDelay}s after {mode.MinPlayers} fighters join, so one more can hop in.`
	end
	return "Starts as soon as an opponent is found."
end

local function choices(): { string }
	local list = table.clone(MatchConfig.ModeOrder)
	table.insert(list, TRAINING)
	return list
end

local function infoFor(id: string): { DisplayName: string, Description: string }
	return if id == TRAINING then TRAINING_INFO else MatchConfig.Modes[id]
end

-- The queue pill ----------------------------------------------------------------------------

local function buildPill(parent: Instance, onCancel: () -> ())
	local holder = make("Frame", {
		Name = "QueuePill",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})
	local pill = Components.panel({
		Name = "Pill",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.1,
		Parent = holder,
	})
	pill.ClipsDescendants = false
	local outline = pill:FindFirstChildOfClass("UIStroke") :: UIStroke
	outline.Color = Colors.Cyan
	outline.Transparency = 0.35
	-- A spinning ring
	local spinner = make("Frame", {
		Name = "Spinner",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Space.L, 0.5, 0),
		Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1,
		Parent = pill,
	}, { Components.corner(Theme.PillCorner) })
	local ring = Components.stroke(Colors.Cyan, 3, 0)
	ring.Parent = spinner
	local ringGradient = make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.6, 0.85),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = ring,
	})
	local title = Components.text({
		Name = "Title",
		Style = "Label",
		Position = UDim2.fromOffset(52, 7),
		Size = UDim2.new(1, -52 - 112, 0, 22),
		Parent = pill,
	})
	local detail = Components.text({
		Name = "Detail",
		Style = "Caption",
		Color = Colors.Cyan,
		Position = UDim2.fromOffset(52, 28),
		Size = UDim2.new(1, -52 - 112, 0, 18),
		Parent = pill,
	})
	Components.button("Cancel", {
		Name = "Cancel",
		Variant = "Danger",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(100, 44),
		Parent = pill,
	}, onCancel)
	return holder, pill, title, detail, ringGradient
end

-- Register --------------------------------------------------------------------------------------

export type Controller = {
	-- Queue status from MatchEvent "Queue" (nil when not queued)
	setQueue: (data: { [string]: any }?) -> (),
	-- Call often (the UIController does it 20 times a second)
	update: () -> (),
}

-- Registers the Play window with the Shell and builds the queue pill
function PlayWindow.register(): Controller
	local queue: { [string]: any }? = nil
	local lastPress = 0
	local function pressed(): boolean
		local now = os.clock()
		if now - lastPress < PRESS_COOLDOWN then
			return false
		end
		lastPress = now
		return true
	end
	local function leaveQueue()
		MatchRequest:FireServer(Action.LeaveQueue)
	end

	local onQueueChanged: (() -> ())? = nil

	Shell.registerWindow("Play", {
		title = "Play",
		label = "PLAY",
		icon = "⚔️",
		order = 1,
		build = function(body: Frame, api)
			local selected = MatchConfig.ModeOrder[1]

			-- Left: the choices
			local left = make("Frame", {
				Name = "Modes",
				Size = UDim2.new(0.44, -Space.S, 1, 0),
				BackgroundTransparency = 1,
				Parent = body,
			})
			Components.text({ Text = "CHOOSE HOW TO FIGHT", Style = "Micro", Color = Colors.TextMuted, Size = UDim2.new(1, 0, 0, 18), Parent = left })
			local list = Components.scroll({
				Name = "Cards",
				Position = UDim2.fromOffset(0, 26),
				Size = UDim2.new(1, 0, 1, -26 - Theme.Size.Control - Space.M),
				Padding = 2,
				Parent = left,
			})
			Components.list(list, Space.S)
			Components.button("🏠  Back to spawn", {
				Name = "Spawn",
				Variant = "Secondary",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Parent = left,
			}, function()
				if pressed() then
					MatchRequest:FireServer(Action.Travel, "Lobby")
					api.toast("Heading back to spawn.", "info")
					api.close()
				end
			end)

			-- Right: details of the selected choice
			local details = make("Frame", {
				Name = "Details",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0.56, -Space.S, 1, 0),
				BackgroundColor3 = Colors.Ink,
				BackgroundTransparency = 0.55,
				BorderSizePixel = 0,
				Parent = body,
			}, {
				Components.corner(Theme.Corner),
				Components.stroke(Colors.Stroke, 1, 0.82),
				Components.padding(Space.L),
			})
			local info = Components.scroll({
				Name = "Info",
				Size = UDim2.new(1, 0, 1, -(48 + Space.M)),
				Parent = details,
			})
			Components.list(info, Space.M)

			local head = make("Frame", { Name = "Head", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1, Parent = info })
			local headIcon: Frame? = nil
			local headTitle = Components.text({ Name = "Title", Style = "Title", Position = UDim2.fromOffset(70, 2), Size = UDim2.new(1, -70, 0, 32), Parent = head })
			local headSubtitle = Components.text({ Name = "Subtitle", Style = "Caption", Weight = "SemiBold", Position = UDim2.fromOffset(70, 34), Size = UDim2.new(1, -70, 0, 18), Parent = head })
			local description = Components.text({ Name = "Description", Style = "Body", Color = Colors.TextDim, Wrap = true, LayoutOrder = 2, Parent = info })

			local rules = make("Frame", {
				Name = "Rules",
				LayoutOrder = 3,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Parent = info,
			})
			Components.grid(rules, UDim2.new(0.5, -Space.S / 2, 0, 58), Space.S)
			local ruleTiles = {}
			for index = 1, 4 do
				local tile = make("Frame", {
					Name = "Rule" .. index,
					LayoutOrder = index,
					BackgroundColor3 = Colors.PanelLight,
					BackgroundTransparency = 0.35,
					BorderSizePixel = 0,
					Parent = rules,
				}, {
					Components.corner(Theme.SmallCorner),
					Components.stroke(Colors.Stroke, 1, 0.85),
					Components.padding(Space.S, Space.M, Space.S, Space.M),
				})
				local label = Components.text({ Style = "Micro", Color = Colors.TextMuted, Size = UDim2.new(1, 0, 0, 16), Parent = tile })
				local value = Components.text({ Style = "Label", Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 22), Parent = tile })
				ruleTiles[index] = { label = label, value = value }
			end
			local note = Components.text({ Name = "Note", Style = "Caption", Color = Colors.TextMuted, Wrap = true, LayoutOrder = 4, Parent = info })

			-- Reserved for the arena picker and CPU options (filled in later);
			-- empty, it takes no space
			local options = make("Frame", {
				Name = "MatchOptions",
				LayoutOrder = 5,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Parent = info,
			})
			Components.list(options, Space.S)

			local actionButton: TextButton
			local cancelButton: TextButton
			local cards: { [string]: Components.Card } = {}

			local function queuedHere(): boolean
				return queue ~= nil and queue.mode == selected
			end

			-- One primary button per state, so hover never repaints the wrong color
			local function renderAction()
				local searching = queuedHere()
				actionButton.Visible = not searching
				cancelButton.Visible = searching
				actionButton.Text = LOOK[selected].action
			end

			local function show(id: string)
				selected = id
				for cardId, card in cards do
					card.setSelected(cardId == id)
				end
				local look = LOOK[id]
				local data = infoFor(id)
				if headIcon then
					headIcon:Destroy()
				end
				local tile = Components.iconTile(look.icon, 56, look.accent)
				tile.Parent = head
				headIcon = tile
				headTitle.Text = string.upper(data.DisplayName)
				headSubtitle.Text = look.subtitle
				headSubtitle.TextColor3 = look.accent
				description.Text = data.Description
				for index, rule in rulesFor(id) do
					ruleTiles[index].label.Text = rule.label
					ruleTiles[index].value.Text = rule.value
				end
				note.Text = "ⓘ  " .. startNote(id)
				renderAction()
			end

			for order, id in choices() do
				local look = LOOK[id] or { icon = "•", accent = Colors.Cyan, tag = "" }
				local data = infoFor(id)
				local _, card = Components.card({
					Name = "Mode_" .. id,
					LayoutOrder = order,
					Size = UDim2.new(1, 0, 0, 80),
					Icon = look.icon,
					Accent = look.accent,
					Title = string.upper(data.DisplayName),
					Body = data.Description,
					Badge = look.tag,
					BadgeColor = if id == TRAINING then Colors.TextMuted else look.accent,
					Parent = list,
					onClick = function()
						show(id)
					end,
				})
				cards[id] = card
			end

			local function actionProps(name: string, variant: string)
				return {
					Name = name,
					Variant = variant,
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.fromScale(0, 1),
					Size = UDim2.new(1, 0, 0, 48),
					TextSize = Theme.TextSize.Heading,
					Parent = details,
				}
			end
			actionButton = Components.button("", actionProps("Action", "Primary"), function()
				if not pressed() then
					return
				end
				if selected == TRAINING then
					MatchRequest:FireServer(Action.Travel, "Training")
					api.toast("Heading to the training ground.", "info")
				else
					MatchRequest:FireServer(Action.Queue, selected)
				end
				api.close()
			end)
			cancelButton = Components.button("✕  CANCEL SEARCH", actionProps("CancelSearch", "Danger"), function()
				if pressed() then
					leaveQueue()
				end
			end)

			onQueueChanged = renderAction
			show(selected)

			return {
				onOpen = function(args)
					-- Shell.open("Play", { mode = "Practice" }) jumps to a choice
					if typeof(args) == "table" and typeof(args.mode) == "string" and LOOK[args.mode] then
						show(args.mode)
					end
				end,
				focus = function()
					return cards[selected] and cards[selected].frame
				end,
			}
		end,
	})

	-- The pill lives in the Shell's top bar so it stays while you walk around
	local slot = Shell.layer("status") or Shell.layer("chrome")
	assert(slot, "PlayWindow.register needs Shell.init first")
	local holder, pill, title, detail, ringGradient = buildPill(slot, function()
		if pressed() then
			leaveQueue()
		end
	end)
	local dots = 0
	local spin = 0

	local function setQueue(data: { [string]: any }?)
		local was = queue
		queue = if typeof(data) == "table" then data else nil
		if queue and not was then
			holder.Visible = true
			pill.Position = UDim2.fromOffset(0, -70)
			TweenService:Create(pill, Theme.Motion.Pop, { Position = UDim2.fromOffset(0, 0) }):Play()
		elseif not queue and was then
			local leaving = TweenService:Create(pill, Theme.Motion.In, { Position = UDim2.fromOffset(0, -70) })
			leaving.Completed:Once(function()
				if not queue then
					holder.Visible = false
				end
			end)
			leaving:Play()
		end
		if onQueueChanged then
			onQueueChanged()
		end
	end

	local function update()
		local current = queue
		if not current then
			return
		end
		spin = (spin + 18) % 360
		ringGradient.Rotation = spin
		dots = (dots + 1) % 30
		local name = if typeof(current.displayName) == "string" then current.displayName else "a match"
		local queued = tonumber(current.queued) or 0
		local max = tonumber(current.max) or tonumber(current.needed) or queued
		if typeof(current.startsAt) == "number" then
			local seconds = math.max(0, math.ceil(current.startsAt - workspace:GetServerTimeNow()))
			title.Text = `{name} starts in {seconds}s`
			detail.Text = `{queued}/{max} fighters ready`
		else
			title.Text = `Finding {name}{string.rep(".", dots // 10 + 1)}`
			detail.Text = `{queued}/{max} fighters`
		end
	end

	return { setQueue = setQueue, update = update }
end

return PlayWindow
