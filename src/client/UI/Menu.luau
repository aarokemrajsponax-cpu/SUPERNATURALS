-- The fight menu on the left (pick a mode, travel) and the "searching" pill
-- shown while waiting in a queue.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MatchConfig = require(ReplicatedStorage.Shared.Config.Match)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local Colors = Theme.Colors
local make = Components.make

local Menu = {}

local MODE_ICONS = { Duel = "⚔", FreeForAll = "👥", Practice = "🤖" }

export type Callbacks = {
	queue: (modeName: string) -> (),
	leaveQueue: () -> (),
	travel: (destination: string) -> (),
}

local function bigButton(parent: Instance, order: number, icon: string, title: string, subtitle: string, accent: Color3, onClick: () -> ())
	local button = Components.button("", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 54),
		Accent = accent,
		Parent = parent,
	}, onClick)
	Components.label(icon, {
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(0, 0, 0.5, -17),
		MaxTextSize = 26,
		Parent = button,
	})
	Components.label(title, {
		Size = UDim2.new(1, -44, 0, 22),
		Position = UDim2.fromOffset(42, 7),
		Font = Theme.Fonts.Heading,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 17,
		Parent = button,
	})
	Components.label(subtitle, {
		Size = UDim2.new(1, -44, 0, 16),
		Position = UDim2.fromOffset(42, 30),
		TextColor3 = Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 13,
		Parent = button,
	})
	return button
end

function Menu.build(parent: Instance, callbacks: Callbacks)
	local panel = Components.panel({
		Name = "FightMenu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(250, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Components.padding(14).Parent = panel
	-- The list lives in its own frame so the collapse button can sit on top of it
	local content = make("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = panel,
	}, {
		make("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local title = Components.label("SUPERNATURALS", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 30),
		Font = Theme.Fonts.Title,
		MaxTextSize = 26,
		Parent = content,
	})
	make("UIGradient", {
		Color = ColorSequence.new(Colors.Cyan, Colors.Purple),
		Parent = title,
	})
	Components.label("Choose your fight", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 16),
		TextColor3 = Colors.TextDim,
		MaxTextSize = 14,
		Parent = content,
	})

	for index, modeName in MatchConfig.ModeOrder do
		local mode = MatchConfig.Modes[modeName]
		bigButton(content, 10 + index, MODE_ICONS[modeName] or "•", string.upper(mode.DisplayName), mode.Description, Colors.Cyan, function()
			callbacks.queue(modeName)
		end)
	end

	make("Frame", {
		LayoutOrder = 20,
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Colors.Cyan,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Parent = content,
	})
	bigButton(content, 21, "🎯", "TRAINING GROUND", "Hit dummies, try your moves", Colors.Purple, function()
		callbacks.travel("Training")
	end)
	bigButton(content, 22, "🏠", "BACK TO SPAWN", "Return to the lobby", Colors.Purple, function()
		callbacks.travel("Lobby")
	end)

	-- Collapse to a small button so the menu never blocks the view
	local reopen = Components.button("☰  FIGHT", {
		Name = "OpenMenu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(110, 40),
		Visible = false,
		Parent = parent,
	})
	local collapse = Components.button("–", {
		Name = "Collapse",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 4, 0, -4),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = Colors.Panel,
		ZIndex = 3,
		Parent = panel,
	})
	local collapsed = false
	local allowed = true
	local function apply()
		panel.Visible = allowed and not collapsed
		reopen.Visible = allowed and collapsed
	end
	collapse.Activated:Connect(function()
		collapsed = true
		apply()
	end)
	reopen.Activated:Connect(function()
		collapsed = false
		apply()
	end)

	-- Queue pill ------------------------------------------------------------------
	local pill = Components.panel({
		Name = "QueuePill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(380, 48),
		Visible = false,
		Parent = parent,
	})
	local pillText = Components.label("", {
		Size = UDim2.new(1, -120, 1, 0),
		Position = UDim2.fromOffset(16, 0),
		Font = Theme.Fonts.Heading,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		Parent = pill,
	})
	Components.button("Cancel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(92, 34),
		Accent = Colors.Danger,
		Parent = pill,
	}, function()
		callbacks.leaveQueue()
	end)

	local queue: any = nil
	local dots = 0

	local function setQueue(data)
		queue = data
		pill.Visible = data ~= nil
		if data then
			pill.Position = UDim2.new(0.5, 0, 0, -50)
			TweenService:Create(pill, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 10) }):Play()
		end
	end

	local function update()
		if not queue then
			return
		end
		dots = (dots + 1) % 40
		local ellipsis = string.rep(".", math.floor(dots / 10) + 1)
		local text = `Finding {queue.displayName}{ellipsis}   {queue.queued}/{queue.max}`
		if queue.startsAt then
			local seconds = math.max(0, math.ceil(queue.startsAt - workspace:GetServerTimeNow()))
			text = `{queue.displayName}: starting in {seconds}s   {queue.queued}/{queue.max}`
		end
		pillText.Text = text
	end

	local function setAllowed(value: boolean)
		allowed = value
		apply()
	end

	return { setQueue = setQueue, setAllowed = setAllowed, update = update }
end

return Menu
