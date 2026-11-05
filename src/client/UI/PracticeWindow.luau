-- Jeffery's practice fights (Shell window "Practice"): pick Beginner, Intermediate, Advanced or
-- Custom, the sparring environment and hints, then start. While a round runs it shows Restart and
-- Exit. Opened from the Training Studio console, from Jeffery's platform and from How to Play.
-- Nothing here is saved or at stake. The server does everything; this only sends the request.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Practice = require(ReplicatedStorage.Shared.Config.Practice)
local Components = require(script.Parent.Components)
local Shell = require(script.Parent.Shell)
local Theme = require(script.Parent.Theme)

local make = Components.make
local Colors = Theme.Colors

local PracticeWindow = {}

local function controller()
	return require(script.Parent.Parent.Controllers.PracticeController).instance
end

local function options(ids: { any }, labels: { [any]: string }?): { any }
	local list = {}
	for _, id in ids do
		table.insert(list, { id = tostring(id), label = if labels and labels[id] then labels[id] else tostring(id) })
	end
	return list
end

local function build(body: Frame)
	local c = controller()
	local choice = {
		mode = (c and c.recommended) or "Beginner",
		theme = "Studio", hints = true, difficulty = "Normal", behavior = "Balanced", duration = 90, abilities = true,
	}
	local column = Components.scroll({ Name = "PracticeColumn", Padding = 2, Parent = body })
	Components.list(column, Theme.Space.M)

	Components.text({
		Name = "Intro", Text = "Practice a real fight against Jeffery. Every power and phase is free here, and nothing is saved or at stake. Leave or restart whenever you like.",
		Style = "Body", Wrap = true, Color = Colors.TextDim, LayoutOrder = 1, Parent = column,
	})

	local modeLabels = {}
	for _, id in Practice.ModeOrder do
		modeLabels[id] = Practice.Modes[id].label
	end
	local summary
	local customCard
	local function refresh()
		summary.Text = Practice.Modes[choice.mode].summary
		customCard.Visible = choice.mode == "Custom"
	end
	Components.text({ Name = "ModeHeading", Text = "Mode", Style = "Heading", LayoutOrder = 2, Parent = column })
	local modeTabs = Components.segmented(nil, options(Practice.ModeOrder, modeLabels), choice.mode, function(id)
		choice.mode = id
		if id ~= "Custom" then
			choice.hints = Practice.Modes[id].hints
		end
		refresh()
	end, { Name = "ModeTabs", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3, Parent = column })
	summary = Components.text({ Name = "ModeSummary", Text = "", Style = "Body", Wrap = true, LayoutOrder = 4, Parent = column })

	customCard = make("Frame", {
		Name = "CustomCard", LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.PanelLight, BackgroundTransparency = 0.3, BorderSizePixel = 0, Parent = column,
	}, { Components.corner(), Components.stroke(Colors.Stroke, 1, 0.7), Components.padding(16, 16, 16, 16) })
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = customCard })
	local function row(order: number, title: string, ids: { any }, key: string, labels: { [any]: string }?)
		Components.text({ Name = key .. "Title", Text = title, Style = "Caption", Color = Colors.TextDim, LayoutOrder = order * 2 - 1, Parent = customCard })
		Components.segmented(nil, options(ids, labels), tostring(choice[key]), function(id)
			choice[key] = if key == "duration" then tonumber(id) else id
		end, { Name = key .. "Tabs", Size = UDim2.new(1, 0, 0, 40), LayoutOrder = order * 2, Parent = customCard })
	end
	row(1, "Difficulty", Practice.CustomChoices.difficulty, "difficulty")
	row(2, "Behaviour", Practice.CustomChoices.behavior, "behavior")
	row(3, "Length in seconds", Practice.CustomChoices.duration, "duration")
	local abilityToggle = Components.toggle("Jeffery may use abilities", choice.abilities, function(on)
		choice.abilities = on
	end, { Name = "AbilitiesToggle", LayoutOrder = 8, Size = UDim2.new(1, 0, 0, 40), Parent = customCard })
	local _ = abilityToggle

	Components.text({ Name = "ThemeHeading", Text = "Environment", Style = "Heading", LayoutOrder = 6, Parent = column })
	local themeLabels = {}
	for _, id in Practice.ThemeOrder do
		themeLabels[id] = Practice.Themes[id].name
	end
	local firstThemes, secondThemes = {}, {}
	for index, id in Practice.ThemeOrder do
		table.insert(if index <= 3 then firstThemes else secondThemes, id)
	end
	local tabsA, tabsB
	tabsA = Components.segmented(nil, options(firstThemes, themeLabels), choice.theme, function(id)
		choice.theme = id
		tabsB.set("", false)
	end, { Name = "ThemeTabsA", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 7, Parent = column })
	tabsB = Components.segmented(nil, options(secondThemes, themeLabels), "", function(id)
		choice.theme = id
		tabsA.set("", false)
	end, { Name = "ThemeTabsB", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 8, Parent = column })
	Components.toggle("Jeffery's hints during the fight", choice.hints, function(on)
		choice.hints = on
	end, { Name = "HintsToggle", LayoutOrder = 9, Size = UDim2.new(1, 0, 0, 40), Parent = column })

	local actions = make("Frame", { Name = "Actions", LayoutOrder = 10, Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, Parent = column })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = actions })
	Components.button("Start practice fight", {
		Name = "StartButton", Variant = "Primary", KeepCase = true, Size = UDim2.fromOffset(240, 48), LayoutOrder = 1, Parent = actions,
	}, function()
		local instance = controller()
		if instance then
			instance:start(choice.mode, {
				theme = choice.theme, hints = choice.hints, difficulty = choice.difficulty, behavior = choice.behavior,
				duration = choice.duration, abilities = choice.abilities,
			})
			Shell.close()
		end
	end)
	Components.button("Restart", {
		Name = "RestartButton", Variant = "Secondary", KeepCase = true, Size = UDim2.fromOffset(140, 48), LayoutOrder = 2, Parent = actions,
	}, function()
		local instance = controller()
		if instance then
			instance:restart()
			Shell.close()
		end
	end)
	Components.button("Exit practice", {
		Name = "ExitButton", Variant = "Danger", KeepCase = true, Size = UDim2.fromOffset(160, 48), LayoutOrder = 3, Parent = actions,
	}, function()
		local instance = controller()
		if instance then
			instance:stop()
			Shell.close()
		end
	end)
	Components.text({
		Name = "Note", Text = "Practice fights run in the Training Studio. If you are elsewhere, the button below takes you there first.",
		Style = "Caption", Wrap = true, Color = Colors.TextDim, LayoutOrder = 11, Parent = column,
	})
	Components.button("Go to the Training Studio", {
		Name = "TravelButton", Variant = "Secondary", KeepCase = true, Size = UDim2.fromOffset(240, 44), LayoutOrder = 12, Parent = column,
	}, function()
		local instance = controller()
		if instance then
			instance:travel()
			Shell.close()
		end
	end)
	refresh()

	return {
		onOpen = function()
			local instance = controller()
			if instance and instance.recommended and Practice.Modes[instance.recommended] then
				choice.mode = instance.recommended
				modeTabs.set(choice.mode, false)
				refresh()
			end
		end,
	}
end

function PracticeWindow.register()
	Shell.registerWindow("Practice", {
		title = "Practice with Jeffery",
		label = "PRACTICE",
		icon = "learn",
		order = 7,
		nav = false,
		build = build,
	})
end

return PracticeWindow
