-- One searchable catalogue used by five sections (admin abuse events, world manipulation,
-- player effects, seasonal event center, holiday effects library). The data comes from the
-- server's Catalogue once and is cached; the list is paged (40 cards, then "Show more") so
-- 200+ presets stay smooth. Favourites last for this session only.
--   config = { title, intro, categories = { [id] = true }? , collections = true? , current = fn? }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local Shell = require(script.Parent.Parent.Shell)
local Actions = require(script.Parent.Actions)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)

local Action = Protocol.OverlordAction
local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make

local CatalogueView = {}

local PAGE = 40
local DETAIL_WIDTH = 316
local DURATIONS = { 10, 30, 60, 120, 300, 600, 900, 1200, 1800, 3600, 7200, 21600 }
local INTENSITIES = { 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2 }
local PREVIEW_SECONDS = { 5, 10, 15, 20, 30 }

local function durationChoices(default: number): { number }
	local list, has = {}, false
	for _, value in DURATIONS do
		if value == default then
			has = true
		end
		table.insert(list, value)
	end
	if not has then
		table.insert(list, default)
		table.sort(list)
	end
	return list
end

-- What the preset's effects let the owner override: intensity (a "scales" number) and colour
local function overridesFor(preset: any): (boolean, boolean)
	local catalogue = Net.catalogue
	local intensity, colour = false, false
	for _, name in preset.effects or {} do
		local effect = catalogue and catalogue.effects[name]
		for _, spec in if effect then effect.params or {} else {} do
			if spec.type == "number" and spec.scales then
				intensity = true
			elseif spec.type == "color" then
				colour = true
			end
		end
	end
	return intensity, colour
end

local function matches(preset: any, words: { string }): boolean
	for _, word in words do
		if not string.find(preset.haystack or "", word, 1, true) then
			return false
		end
	end
	return true
end

function CatalogueView.build(page: Frame, ctx: any, config: any)
	local view = {}
	local state = { filter = "all", query = "", shown = PAGE, selected = nil :: string?, overrides = {} :: any, previewSeconds = 10 }

	local root = make("Frame", { Name = "Catalogue", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = page })

	-- Left: one scrolling column: heading, search, filters, then the cards
	local left = Components.scroll({ Name = "Left", Size = UDim2.new(1, -(DETAIL_WIDTH + Space.M), 1, 0), Parent = root })
	left.VerticalScrollBarInset = Enum.ScrollBarInset.None
	Components.list(left, Space.S)
	local top = left
	Kit.heading(top, config.title, 1)
	Kit.para(top, config.intro, 2)
	local search = Kit.input(top, { Name = "Search", Placeholder = "Search by name, tag, effect or collection", MaxLen = 60, LayoutOrder = 3 }, function(text)
		state.query = string.lower(text)
		state.shown = PAGE
		view.refreshList()
	end)
	local chipRow = make("ScrollingFrame", {
		Name = "Filters",
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Colors.SteelLight,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.X,
		Parent = top,
	})
	Components.list(chipRow, Space.S, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Top })
	local count = Components.text({ Name = "Count", Text = "", Style = "caption", LayoutOrder = 5, Parent = top })
	local cards = make("Frame", { Name = "Cards", LayoutOrder = 6, Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = top })
	Components.list(cards, Space.S)

	-- Right: the detail of the chosen preset
	local right = make("Frame", {
		Name = "Detail",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, DETAIL_WIDTH, 1, 0),
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Parent = root,
	}, { Components.corner(Theme.SmallCorner) })
	local detail = Components.scroll({ Name = "DetailScroll", Padding = Space.M, Parent = right })
	Components.list(detail, Space.S)

	-- Filters -----------------------------------------------------------------------------

	local filterButtons: { [string]: TextButton } = {}
	local function filterOptions(): { { id: string, label: string } }
		local options = { { id = "all", label = "All" }, { id = "fav", label = "Favourites" }, { id = "recent", label = "Recently used" } }
		local catalogue = Net.catalogue
		if catalogue then
			local seen = {}
			for _, preset in catalogue.presets do
				if config.categories[preset.category] and not seen[preset.category] then
					seen[preset.category] = true
				end
			end
			for _, category in catalogue.categories or {} do
				if seen[category.id] then
					table.insert(options, { id = category.id, label = category.name })
				end
			end
			if seen.Custom then
				table.insert(options, { id = "Custom", label = "My custom events" })
			end
		end
		return options
	end

	local function paintFilters()
		for id, button in filterButtons do
			Components.setSelected(button, id == state.filter)
		end
	end

	local function buildFilters()
		for _, child in chipRow:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		filterButtons = {}
		for order, option in filterOptions() do
			local button = Kit.button(chipRow, option.label, "Ghost", function()
				state.filter = option.id
				state.shown = PAGE
				paintFilters()
				view.refreshList()
			end, { Name = "Filter_" .. option.id, LayoutOrder = order })
			filterButtons[option.id] = button
		end
		paintFilters()
	end

	-- Detail --------------------------------------------------------------------------------

	local feedback: TextLabel? = nil

	local function currentOverrides(preset: any): any
		local out = {}
		local o = state.overrides
		if o.duration and o.duration ~= preset.duration then
			out.duration = o.duration
		end
		if o.intensity and o.intensity ~= 1 then
			out.intensity = o.intensity
		end
		if o.color then
			out.color = o.color
		end
		return if next(out) then out else nil
	end

	local function say(text: string, ok: boolean)
		if feedback then
			feedback.Text = text
			feedback.TextColor3 = if ok then Colors.Success else Colors.Danger
		end
	end

	local function describeRun(preset: any): string
		local o = state.overrides
		local parts = { `Runs for {Kit.seconds(o.duration or preset.duration)}.` }
		if o.intensity and o.intensity ~= 1 then
			table.insert(parts, `Intensity {o.intensity}.`)
		end
		if o.color then
			table.insert(parts, "Custom colour.")
		end
		return `{preset.description}\n{table.concat(parts, " ")}`
	end

	local function renderDetail()
		Kit.clear(detail)
		feedback = nil
		local preset = state.selected and Net.catalogue and Net.catalogue.byId[state.selected]
		if not preset then
			Kit.empty(detail, "Choose a preset to see its details, preview it, and activate it.", 1)
			return
		end
		state.overrides = state.overrides.preset == preset.id and state.overrides or { preset = preset.id }
		local o = state.overrides
		Components.text({ Name = "Name", Text = preset.name, Style = "heading", Wrap = true, LayoutOrder = 1, Parent = detail })
		local chips = Kit.flow(detail, 2, 6)
		Components.chip(`Level {preset.level}`, { Color = Colors.Cyan, Parent = chips })
		Components.chip(Net.catalogue.categoryNames[preset.category] or preset.category, { Parent = chips })
		if preset.eventMode then
			Components.chip("Event mode", { Color = Colors.Warning, Parent = chips })
		end
		Kit.para(detail, preset.description, 3)
		if typeof(preset.tags) == "table" and #preset.tags > 0 then
			Kit.caption(detail, "Tags: " .. table.concat(preset.tags, ", "), 4)
		end
		Kit.caption(detail, "Effects: " .. table.concat(preset.effects or {}, ", "), 5)

		local allowIntensity, allowColour = overridesFor(preset)
		Kit.stepper(detail, "Duration", durationChoices(preset.duration), o.duration or preset.duration, Kit.seconds, function(value)
			o.duration = value
		end, { Name = "Duration", LayoutOrder = 6 })
		if allowIntensity then
			Kit.stepper(detail, "Intensity", INTENSITIES, o.intensity or 1, function(value)
				return string.format("%.2f", value)
			end, function(value)
				o.intensity = value
			end, { Name = "Intensity", LayoutOrder = 7 })
		end
		if allowColour then
			Kit.caption(detail, "Colour", 8)
			local swatches = Kit.swatches(detail, 9, function(rgb)
				o.color = rgb
			end)
			swatches.set(o.color)
		end

		Kit.stepper(detail, "Preview length", PREVIEW_SECONDS, state.previewSeconds, function(value)
			return `{value} s`
		end, function(value)
			state.previewSeconds = value
		end, { Name = "PreviewLength", LayoutOrder = 10 })
		local buttons = Kit.flow(detail, 11, Space.S)
		Kit.button(buttons, "Preview here", "Secondary", function()
			Net.request(Action.Preview, { preset = preset.id, seconds = state.previewSeconds }, function(result)
				local text, ok = Actions.report(result, `Previewing {preset.name} on this server for {state.previewSeconds} s.`)
				if ok then
					Net.touchRecent(preset.id)
				end
				say(text, ok)
			end)
		end, { Name = "Preview" })
		Kit.button(buttons, "Activate", "Primary", function()
			Actions.activate({ { preset = preset.id, overrides = currentOverrides(preset) } }, preset.name, describeRun(preset), function(text, ok)
				say(text, ok)
			end)
		end, { Name = "Activate" })
		local more = Kit.flow(detail, 12, Space.S)
		Kit.button(more, "Add to selection", "Ghost", function()
			local added = Net.addToSelection({ preset = preset.id, overrides = currentOverrides(preset) })
			Shell.toast(if added then `{preset.name} added. Open Saved presets to run or save the selection.` else "The selection is full (eight presets).", if added then "info" else "error")
		end, { Name = "AddToSelection" })
		Kit.button(more, if Net.favourites[preset.id] then "Remove favourite" else "Add favourite", "Ghost", function()
			Net.toggleFavourite(preset.id)
		end, { Name = "Favourite" })
		local scopeLine = Kit.caption(detail, `Scope: {Net.scopeText()}`, 13)
		scopeLine.Name = "ScopeLine"
		feedback = Components.text({ Name = "Feedback", Text = "", Style = "body", Wrap = true, LayoutOrder = 14, Parent = detail })
	end

	-- Cards ---------------------------------------------------------------------------------

	local function visiblePresets(): { any }
		local catalogue = Net.catalogue
		if not catalogue then
			return {}
		end
		local words = {}
		for word in string.gmatch(state.query, "%S+") do
			table.insert(words, word)
		end
		local list = {}
		if state.filter == "recent" then
			for _, id in Net.recent do
				local preset = catalogue.byId[id]
				if preset and config.categories[preset.category] and matches(preset, words) then
					table.insert(list, preset)
				end
			end
			return list
		end
		for _, preset in catalogue.presets do
			if config.categories[preset.category] and matches(preset, words) then
				if state.filter == "all" or preset.category == state.filter or (state.filter == "fav" and Net.favourites[preset.id]) then
					table.insert(list, preset)
				end
			end
		end
		if config.current and state.filter == "all" and state.query == "" then
			local current = config.current()
			if current then
				table.sort(list, function(a, b)
					local ac, bc = a.category == current, b.category == current
					if ac ~= bc then
						return ac
					end
					return false
				end)
			end
		end
		return list
	end

	local function addCard(preset: any, order: number)
		local selected = preset.id == state.selected
		local card = make("TextButton", {
			Name = "Card_" .. preset.id,
			LayoutOrder = order,
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.new(1, 0, 0, 44),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = if selected then Colors.Selected else Colors.PanelLight,
			BackgroundTransparency = 0.04,
			BorderSizePixel = 0,
			Selectable = true,
			Parent = cards,
		}, { Components.corner(Theme.SmallCorner) })
		local content = make("Frame", {
			Name = "Content",
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = card,
		}, { Components.padding(Space.M, Space.M, Space.M, Space.M + 4) })
		Components.list(content, 6)
		if selected then
			make("Frame", { Name = "Bar", Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = Colors.Cyan, BorderSizePixel = 0, Parent = card })
		end
		Components.text({ Name = "Name", Text = preset.name, Style = "strong", Wrap = true, Color = Colors.Text, LayoutOrder = 1, Size = UDim2.new(1, -52, 0, 0), Parent = content })
		Components.text({ Name = "Description", Text = preset.description, Style = "small", Wrap = true, LayoutOrder = 2, Parent = content })
		local chips = Kit.flow(content, 3, 6)
		Components.chip(`Level {preset.level}`, { Color = Colors.Cyan, Parent = chips })
		for index, tag in preset.tags or {} do
			if index > 3 then
				break
			end
			Components.chip(tag, { Parent = chips })
		end
		local fav = Components.button("", {
			Name = "Fav",
			Variant = "Ghost",
			Icon = "star",
			IconSize = 18,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(44, 44),
			ZIndex = 3,
			Parent = card,
		}, function()
			Net.toggleFavourite(preset.id)
		end)
		Components.setSelected(fav, Net.favourites[preset.id] == true)
		card.Activated:Connect(function()
			state.selected = preset.id
			view.refreshList()
			renderDetail()
		end)
	end

	function view.refreshList()
		Kit.clear(cards)
		local catalogue = Net.catalogue
		if not catalogue then
			Kit.empty(cards, "Loading the catalogue from the server.", 1)
			count.Text = ""
			return
		end
		local list = visiblePresets()
		count.Text = if #list == 1 then "1 preset" else `{#list} presets`
		if #list == 0 then
			local message = "Nothing matches. Clear the search or pick another filter."
			if state.filter == "fav" and state.query == "" then
				message = "No favourites yet. Add one from a preset's details. Favourites are kept for this session only."
			elseif state.filter == "recent" and state.query == "" then
				message = "Nothing used yet this session. Presets you preview or activate show up here."
			end
			Kit.empty(cards, message, 1)
			return
		end
		for index = 1, math.min(#list, state.shown) do
			addCard(list[index], index)
		end
		if #list > state.shown then
			Kit.button(cards, `Show {math.min(PAGE, #list - state.shown)} more`, "Secondary", function()
				state.shown += PAGE
				view.refreshList()
			end, { Name = "ShowMore", LayoutOrder = state.shown + 1, Size = UDim2.new(1, 0, 0, 44) })
		end
	end

	Net.on("catalogue", function()
		buildFilters()
		view.refreshList()
		renderDetail()
	end)
	Net.on("picks", function()
		view.refreshList()
		renderDetail()
	end)
	Net.on("scope", function()
		local line = detail:FindFirstChild("ScopeLine", true)
		if line then
			line.Text = `Scope: {Net.scopeText()}`
		end
	end)

	buildFilters()
	view.refreshList()
	renderDetail()
	return {
		show = function()
			Net.loadCatalogue()
		end,
	}
end


return CatalogueView
