-- The owner panel: a glowing glass window with four tabs.
--   EVENTS   launch admin abuse for the whole lobby
--   PLAYERS  pick a player (or everyone) and do things to them
--   ME       fly, immunity, invisibility, crown, auras
--   SERVER   announcements, time of day, seasons, ending matches
-- It only sends requests; the server checks that you really are the owner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AdminEvents = require(ReplicatedStorage.Shared.Config.AdminEvents)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Seasons = require(ReplicatedStorage.Shared.Seasons)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local Action = Protocol.AdminAction
local Attribute = Protocol.Attribute
local Colors = Theme.Colors
local make = Components.make

local player = Players.LocalPlayer

local GOLD = Color3.fromRGB(255, 205, 90)
local GOLD_DARK = Color3.fromRGB(120, 80, 20)

local OwnerPanel = {}
-- Filled in by build()
OwnerPanel.setOpen = function(_: boolean) end
OwnerPanel.toggle = function() end

type Send = (action: string, first: any?, second: any?) -> ()

local function sectionTitle(parent: Instance, order: number, text: string)
	return Components.label(text, {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 22),
		Font = Theme.Fonts.Title,
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		Parent = parent,
	})
end

-- A button that needs a second click within 3 seconds (for kicks and bans)
local function confirmButton(text: string, props, onConfirm: () -> ())
	local armedUntil = 0
	local button
	button = Components.button(text, props, function()
		if os.clock() < armedUntil then
			armedUntil = 0
			button.Text = text
			onConfirm()
		else
			armedUntil = os.clock() + 3
			button.Text = "Click again to confirm"
			task.delay(3, function()
				if os.clock() >= armedUntil then
					button.Text = text
				end
			end)
		end
	end)
	return button
end

local function scrolling(parent: Instance, props)
	local frame = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = GOLD,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	})
	for key, value in props do
		(frame :: any)[key] = value
	end
	return frame
end

-- Events tab -------------------------------------------------------------------------------
local function buildEvents(page: Frame, send: Send)
	local grid = scrolling(page, { Size = UDim2.new(1, 0, 1, -56) })
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(236, 132),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), Parent = grid })

	for order, id in AdminEvents.Order do
		local def = AdminEvents.Events[id]
		local card = make("Frame", {
			LayoutOrder = order,
			BackgroundColor3 = Color3.new(1, 1, 1),
			Active = true,
			Parent = grid,
		}, {
			Components.corner(),
			make("UIGradient", { Color = ColorSequence.new(def.colors[1], def.colors[2]), Rotation = 35 }),
			make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, Transparency = 0.6 }),
		})
		local scale = make("UIScale", { Parent = card })
		Components.label(def.icon, { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(10, 8), MaxTextSize = 32, Parent = card })
		Components.label(def.name, {
			Size = UDim2.new(1, -60, 0, 24),
			Position = UDim2.fromOffset(54, 10),
			Font = Theme.Fonts.Title,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextStrokeTransparency = 0.6,
			MaxTextSize = 17,
			Parent = card,
		})
		Components.label(`{def.duration}s`, {
			Size = UDim2.new(1, -60, 0, 14),
			Position = UDim2.fromOffset(54, 34),
			Font = Theme.Fonts.Heading,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTransparency = 0.25,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 12,
			Parent = card,
		})
		Components.label(def.description, {
			Size = UDim2.new(1, -20, 0, 34),
			Position = UDim2.fromOffset(10, 52),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextStrokeTransparency = 0.7,
			MaxTextSize = 13,
			Parent = card,
		})
		local launch = Components.button("▶  ACTIVATE", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -10, 1, -10),
			Size = UDim2.fromOffset(120, 32),
			BackgroundColor3 = Color3.fromRGB(20, 20, 30),
			Accent = Color3.new(1, 1, 1),
			Parent = card,
		}, function()
			send(Action.StartEvent, id)
		end)
		launch.ZIndex = 2
		card.MouseEnter:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.15), { Scale = 1.04 }):Play()
		end)
		card.MouseLeave:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.15), { Scale = 1 }):Play()
		end)
	end

	-- What's running right now
	local bar = Components.panel({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 46),
		Parent = page,
	})
	local status = Components.label("No event running", {
		Size = UDim2.new(1, -150, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		Font = Theme.Fonts.Heading,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 15,
		Parent = bar,
	})
	Components.button("■  STOP EVENT", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(130, 32),
		Accent = Colors.Danger,
		Parent = bar,
	}, function()
		send(Action.StopEvent)
	end)
	return function()
		local id = ReplicatedStorage:GetAttribute(Attribute.AdminEvent)
		local def = typeof(id) == "string" and AdminEvents.Events[id]
		if def then
			local endsAt = ReplicatedStorage:GetAttribute(Attribute.AdminEventEndsAt) or 0
			status.Text = `🔴 LIVE: {def.icon} {def.name}  ·  {math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))}s left`
		else
			status.Text = "No event running · pick one above"
		end
	end
end

-- Players tab ------------------------------------------------------------------------------
local function buildPlayers(page: Frame, send: Send)
	local list = scrolling(page, { Size = UDim2.new(0, 250, 1, 0) })
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	make("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = list })

	local right = make("Frame", {
		Position = UDim2.fromOffset(264, 0),
		Size = UDim2.new(1, -264, 1, 0),
		BackgroundTransparency = 1,
		Active = true,
		Parent = page,
	})
	local selectedLabel = Components.label("", {
		Size = UDim2.new(1, 0, 0, 26),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 18,
		Parent = right,
	})
	local actions = scrolling(right, { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -34) })
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(152, 40),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = actions,
	})

	local selected: any = "Others"
	local selectedName = "Everyone but me"
	local rows: { [any]: TextButton } = {}

	local function highlight()
		selectedLabel.Text = `🎯  Target: {selectedName}`
		for key, row in rows do
			local stroke = row:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if key == selected then GOLD else Colors.Cyan
				stroke.Transparency = if key == selected then 0 else 0.5
			end
		end
	end

	for order, action in AdminEvents.PlayerActions do
		local props = {
			LayoutOrder = order,
			Accent = if action.danger then Colors.Danger else Colors.Cyan,
			Parent = actions,
		}
		local label = `{action.icon}  {action.label}`
		local function run()
			send(Action.PlayerAction, selected, action.id)
		end
		if action.danger then
			confirmButton(label, props, run)
		else
			Components.button(label, props, run)
		end
	end

	local function row(key: any, title: string, subtitle: string, userId: number?, order: number)
		local button = Components.button("", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 52),
			Parent = list,
		}, function()
			selected = key
			selectedName = title
			highlight()
		end)
		if userId then
			local image = make("ImageLabel", {
				Size = UDim2.fromOffset(40, 40),
				Position = UDim2.new(0, -4, 0.5, -20),
				BackgroundColor3 = Colors.Background,
				Parent = button,
			}, { Components.corner(UDim.new(1, 0)) })
			task.spawn(function()
				local ok, content = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
				if ok and image.Parent then
					image.Image = content
				end
			end)
		else
			Components.label(if key == "All" then "🌍" else "👥", {
				Size = UDim2.fromOffset(40, 40),
				Position = UDim2.new(0, -4, 0.5, -20),
				MaxTextSize = 26,
				Parent = button,
			})
		end
		Components.label(title, {
			Size = UDim2.new(1, -48, 0, 20),
			Position = UDim2.fromOffset(44, 7),
			Font = Theme.Fonts.Heading,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 15,
			Parent = button,
		})
		Components.label(subtitle, {
			Size = UDim2.new(1, -48, 0, 14),
			Position = UDim2.fromOffset(44, 28),
			TextColor3 = Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 12,
			Parent = button,
		})
		rows[key] = button
	end

	local function rebuild()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		table.clear(rows)
		row("All", "Everyone", "Every player in the server", nil, 1)
		row("Others", "Everyone but me", "All players except you", nil, 2)
		local everyone = Players:GetPlayers()
		table.sort(everyone, function(a, b)
			return a.DisplayName:lower() < b.DisplayName:lower()
		end)
		for index, target in everyone do
			local where = if target:GetAttribute(Attribute.MatchId) then "⚔ in a match" else "🏠 lobby"
			local you = if target == player then " (you)" else ""
			row(target.UserId, target.DisplayName .. you, `@{target.Name} · {where}`, target.UserId, 10 + index)
		end
		if typeof(selected) == "number" and not Players:GetPlayerByUserId(selected) then
			selected = "Others"
			selectedName = "Everyone but me"
		end
		highlight()
	end
	Players.PlayerAdded:Connect(rebuild)
	Players.PlayerRemoving:Connect(function()
		task.defer(rebuild)
	end)
	rebuild()
	return rebuild
end

-- Me tab -------------------------------------------------------------------------------------
local function buildMe(page: Frame, send: Send)
	local content = scrolling(page, { Size = UDim2.fromScale(1, 1) })
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	make("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = content })

	sectionTitle(content, 1, "POWERS")
	local toggles = {
		{ id = "Fly", attribute = Attribute.CanFly, label = "✈️  Fly", hint = "Press G to toggle · Space up · Ctrl down · Shift for speed" },
		{ id = "Immune", attribute = Attribute.Immune, label = "🛡️  Immune to events", hint = "Your own admin abuse won't push or freeze you" },
		{ id = "Invisible", attribute = Attribute.Invisible, label = "👻  Invisible", hint = "Other players can't see you" },
		{ id = "Crown", attribute = Attribute.Crown, label = "👑  Crown & owner title", hint = "Show everyone who runs this place" },
	}
	local renderers = {}
	for order, toggle in toggles do
		local holder = make("Frame", { LayoutOrder = 1 + order, Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, Parent = content })
		local button
		local function render()
			local on = player:GetAttribute(toggle.attribute) == true
			button.Text = `{toggle.label}:  {if on then "ON" else "OFF"}`
			button.TextColor3 = if on then Colors.Success else Colors.Text
		end
		button = Components.button("", { Size = UDim2.new(0, 300, 0, 40), Parent = holder }, function()
			send(Action.SelfToggle, toggle.id, player:GetAttribute(toggle.attribute) ~= true)
		end)
		Components.label(toggle.hint, {
			Size = UDim2.new(1, -316, 1, 0),
			Position = UDim2.fromOffset(312, 0),
			TextColor3 = Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			MaxTextSize = 13,
			Parent = holder,
		})
		player:GetAttributeChangedSignal(toggle.attribute):Connect(render)
		render()
		table.insert(renderers, render)
	end

	sectionTitle(content, 10, "MY LOOK")
	local auras = make("Frame", { LayoutOrder = 11, Size = UDim2.new(1, 0, 0, 92), BackgroundTransparency = 1, Parent = content })
	make("UIGridLayout", { CellSize = UDim2.fromOffset(170, 40), CellPadding = UDim2.fromOffset(8, 8), Parent = auras })
	for _, action in AdminEvents.PlayerActions do
		if string.sub(action.id, 1, 4) == "Aura" or action.id == "Speed" then
			Components.button(`{action.icon}  {action.label}`, { Parent = auras }, function()
				send(Action.PlayerAction, player.UserId, action.id)
			end)
		end
	end
end

-- Server tab -------------------------------------------------------------------------------
local function buildServer(page: Frame, send: Send)
	local content = scrolling(page, { Size = UDim2.fromScale(1, 1) })
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	make("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = content })

	sectionTitle(content, 1, "ANNOUNCEMENT")
	local row = make("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Parent = content })
	local box = make("TextBox", {
		Size = UDim2.new(1, -130, 1, 0),
		BackgroundColor3 = Colors.Background,
		TextColor3 = Colors.Text,
		PlaceholderText = "Type a message for the whole server...",
		PlaceholderColor3 = Colors.TextDim,
		ClearTextOnFocus = false,
		Text = "",
		Font = Theme.Fonts.Body,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	}, { Components.corner(Theme.SmallCorner), Components.stroke(GOLD, 1.5, 0.4), Components.padding(10) })
	local function announce()
		local text = box.Text
		if string.match(text, "%S") then
			send(Action.Announce, string.sub(text, 1, 200))
			box.Text = ""
		end
	end
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			announce()
		end
	end)
	Components.button("📣  SEND", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 120, 1, 0),
		Accent = GOLD,
		Parent = row,
	}, announce)

	local function buttonRow(order: number, items: { { label: string, onClick: () -> () } })
		local frame = make("Frame", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = content })
		make("UIGridLayout", { CellSize = UDim2.fromOffset(150, 40), CellPadding = UDim2.fromOffset(8, 8), Parent = frame })
		for _, item in items do
			Components.button(item.label, { Parent = frame }, item.onClick)
		end
	end

	sectionTitle(content, 3, "TIME OF DAY")
	local times = {}
	for _, option in AdminEvents.TimesOfDay do
		table.insert(times, {
			label = option.label,
			onClick = function()
				send(Action.SetTime, option.id)
			end,
		})
	end
	buttonRow(4, times)

	sectionTitle(content, 5, "SEASON")
	local seasons = { {
		label = "🗓️ Auto (calendar)",
		onClick = function()
			send(Action.SetSeason, "Auto")
		end,
	} }
	for id, theme in Seasons.Themes do
		table.insert(seasons, {
			label = `{theme.icon} {theme.name}`,
			onClick = function()
				send(Action.SetSeason, id)
			end,
		})
	end
	buttonRow(6, seasons)

	sectionTitle(content, 7, "MATCHES & EVENTS")
	local danger = make("Frame", { LayoutOrder = 8, Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = content })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = danger })
	confirmButton("⛔  End all matches", { Size = UDim2.fromOffset(220, 40), Accent = Colors.Danger, Parent = danger }, function()
		send(Action.EndMatches)
	end)
	Components.button("■  Stop event", { Size = UDim2.fromOffset(160, 40), Accent = Colors.Danger, Parent = danger }, function()
		send(Action.StopEvent)
	end)
end

-- Window ------------------------------------------------------------------------------------
function OwnerPanel.build(parent: Instance, send: Send)
	local open = false
	local setOpen: (boolean) -> ()

	local toggle = Components.button("👑", {
		Name = "OwnerButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, -70),
		Size = UDim2.fromOffset(54, 54),
		BackgroundColor3 = GOLD_DARK,
		Accent = GOLD,
		Parent = parent,
	})
	make("UIGradient", { Color = ColorSequence.new(GOLD, GOLD_DARK), Rotation = 90, Parent = toggle })
	local constraint = toggle:FindFirstChildOfClass("UITextSizeConstraint")
	if constraint then
		constraint.MaxTextSize = 30
	end

	local window = make("Frame", {
		Name = "OwnerPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(800, 520),
		BackgroundColor3 = Color3.fromRGB(14, 12, 24),
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 30,
		-- Clicks on the panel stay on the panel (no swinging or camera turning)
		Active = true,
		Parent = parent,
	}, { Components.corner(UDim.new(0, 18)) })
	local windowScale = make("UIScale", { Scale = 0.9, Parent = window })
	-- An animated gold-purple-cyan border
	local border = make("UIStroke", { Thickness = 2.5, Color = Color3.new(1, 1, 1), Parent = window })
	local borderGradient = make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, GOLD),
			ColorSequenceKeypoint.new(0.5, Colors.Purple),
			ColorSequenceKeypoint.new(1, Colors.Cyan),
		}),
		Parent = border,
	})
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 160, 210)),
		Rotation = 90,
		Parent = window,
	})

	local title = Components.label("👑  OWNER PANEL", {
		Size = UDim2.new(1, -120, 0, 34),
		Position = UDim2.fromOffset(20, 14),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 28,
		Parent = window,
	})
	make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 240, 170), GOLD), Rotation = 90, Parent = title })
	Components.label(`Only {player.Name} can see this · press P to open or close`, {
		Size = UDim2.new(1, -120, 0, 16),
		Position = UDim2.fromOffset(22, 48),
		TextColor3 = Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 13,
		Parent = window,
	})
	Components.button("✕", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(38, 38),
		Accent = Colors.Danger,
		Parent = window,
	}, function()
		setOpen(false)
	end)

	-- Tabs
	local tabBar = make("Frame", {
		Position = UDim2.fromOffset(20, 74),
		Size = UDim2.new(1, -40, 0, 38),
		BackgroundTransparency = 1,
		Parent = window,
	}, { make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }) })
	local body = make("Frame", {
		Position = UDim2.fromOffset(20, 122),
		Size = UDim2.new(1, -40, 1, -138),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = window,
	})

	local pages: { [string]: Frame } = {}
	local tabButtons: { [string]: TextButton } = {}
	local tabs = { "EVENTS", "PLAYERS", "ME", "SERVER" }
	local icons = { EVENTS = "☄️", PLAYERS = "👥", ME = "😎", SERVER = "🛠️" }
	local function select(name: string)
		for key, page in pages do
			page.Visible = key == name
		end
		for key, button in tabButtons do
			local active = key == name
			button.BackgroundColor3 = if active then GOLD_DARK else Colors.PanelLight
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if active then GOLD else Colors.Cyan
				stroke.Transparency = if active then 0 else 0.5
			end
		end
	end
	for _, name in tabs do
		pages[name] = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = body })
		tabButtons[name] = Components.button(`{icons[name]}  {name}`, { Size = UDim2.fromOffset(170, 38), Parent = tabBar }, function()
			select(name)
		end)
	end

	local updateEvents = buildEvents(pages.EVENTS, send)
	local rebuildPlayers = buildPlayers(pages.PLAYERS, send)
	buildMe(pages.ME, send)
	buildServer(pages.SERVER, send)
	select("EVENTS")

	local spin = 0
	RunService.RenderStepped:Connect(function(dt)
		if not window.Visible then
			return
		end
		spin = (spin + dt * 60) % 360
		borderGradient.Rotation = spin
		updateEvents()
	end)

	function setOpen(value: boolean)
		open = value
		if open then
			rebuildPlayers()
			window.Visible = true
			windowScale.Scale = 0.85
			TweenService:Create(windowScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		else
			local closing = TweenService:Create(windowScale, TweenInfo.new(0.15), { Scale = 0.85 })
			closing.Completed:Once(function()
				if not open then
					window.Visible = false
				end
			end)
			closing:Play()
		end
	end

	OwnerPanel.setOpen = setOpen
	function OwnerPanel.toggle()
		setOpen(not open)
	end

	toggle.Activated:Connect(OwnerPanel.toggle)
end

return OwnerPanel
