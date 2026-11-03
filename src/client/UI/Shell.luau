-- The app frame every lobby screen lives in (v3, docs/ArtDirection.md section 7):
--   top bar   player card (avatar, name, power) on the left, Money and Gems on the right
--   dock      vertical navigation on the left, one item per registered window
--   windows   one open at a time, built the first time they open; opening one dims
--             and blurs the world (a BlurEffect the Shell owns and always restores)
--   toasts    short messages stacked top-right that fade on their own
--   confirm   a modal "are you sure?" that shows the price before anything is bought
-- It also owns the interface's single UIScale, so the whole interface fits
-- phones, tablets, monitors and TVs. Modes hide whatever shouldn't cover a fight.
-- Every control here draws the same seven states through Components.surface.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Icons = require(script.Parent.Icons)
local Profile = require(script.Parent.Parent.Profile)
local Settings = require(script.Parent.Parent.Settings)

local Colors = Theme.Colors
local Space = Theme.Space
local Motion = Theme.Motion
local make = Components.make
local tween = Components.tween
local apply = Components.apply

local player = Players.LocalPlayer

local Shell = {}

-- Layout, in design pixels (the UIScale turns them into screen pixels)
local EDGE = 12
local TOP_BAR = 52
local BANNER = 30
local BANNER_WIDTH = 640
local DOCK_ITEM_WIDTH = 88
local DOCK_ITEM_MAX_HEIGHT = 64
local DOCK_COMPACT = 48
local DOCK_PADDING = 8
local DOCK_GAP = 6
local WALLET_PILL = 190
local PLAYER_CARD = 260
local STATUS_WIDTH = 420
local TOAST_WIDTH = 320
local MAX_TOASTS = 4
local TOAST_SECONDS = 3.5
local MIN_WINDOW = Vector2.new(360, 260)
-- In fights toasts start below the knockout feed
local MATCH_TOAST_TOP = 236
-- Below this many screen points the dock shows icons only
local COMPACT_WIDTH = 900
local COMPACT_HEIGHT = 500
local BACKDROP_ALPHA = 0.55
-- How strongly an open window blurs the world behind it, and a confirm dialog on top of that
local BLUR_WINDOW = 14
local BLUR_MODAL = 20
local BLUR_NAME = "SNShellBlur"
local BACK_ACTION = "SNShellBack"
local DEFAULT_SAVING_MESSAGE = "Progress isn't being saved right now (Studio without API access)"
-- Shown where a number has not arrived yet
local NO_VALUE = "-"

-- What each mode shows
type ModeLook = { dock: boolean, topBar: "full" | "small" | "none", windows: boolean, hidden: boolean }
local MODES: { [string]: ModeLook } = {
	Lobby = { dock = true, topBar = "full", windows = true, hidden = false },
	Match = { dock = false, topBar = "small", windows = false, hidden = false },
	Editor = { dock = false, topBar = "full", windows = true, hidden = false },
	Spectate = { dock = false, topBar = "small", windows = true, hidden = false },
	Cinematic = { dock = false, topBar = "none", windows = false, hidden = true },
}

export type WindowApi = {
	close: () -> (),
	toast: (text: string, kind: string?) -> (),
	confirm: (options: ConfirmOptions) -> (),
	open: (id: string, args: any?) -> (),
}

export type WindowHandlers = {
	onOpen: ((args: any?) -> ())?,
	onClose: (() -> ())?,
	update: ((dt: number) -> ())?,
	-- Optional: the control a gamepad should select first
	focus: (() -> GuiObject?)?,
}

export type WindowSpec = {
	title: string,
	icon: string,
	order: number,
	nav: boolean?,
	-- Short dock label (defaults to the title in capitals)
	label: string?,
	size: Vector2?,
	accent: Color3?,
	build: (body: Frame, api: WindowApi) -> WindowHandlers?,
}

export type ConfirmOptions = {
	title: string,
	body: string?,
	confirmText: string?,
	cancelText: string?,
	price: { money: number?, gems: number?, robux: number? }?,
	danger: boolean?,
	icon: string?,
	onConfirm: () -> (),
	onCancel: (() -> ())?,
}

type Entry = {
	id: string,
	spec: WindowSpec,
	frame: Frame?,
	body: Frame?,
	parts: any,
	handlers: WindowHandlers,
	fade: Components.Fade?,
	nav: { button: TextButton, refresh: () -> (), tile: Frame, label: TextLabel, badge: Frame, badgeText: TextLabel }?,
}

local initialized = false
local gui: ScreenGui
local deps: { input: any? } = {}
local uiScale: UIScale
local layers: { [string]: GuiObject } = {}
local registry: { [string]: Entry } = {}
local badges: { [string]: string? } = {}
local powerNames: { [string]: string } = {}
local openId: string? = nil
local mode = "Lobby"
local compact = false

-- Pieces built in init
local playerCard: Frame
local avatar: ImageLabel
local avatarInitial: TextLabel
local powerText: TextLabel
local powerIcon: Frame? = nil
local wallet: Frame
local smallBar: Frame
local gearButton: TextButton
local banner: Frame
local bannerText: TextLabel
local dock: Frame
local dockList: Frame
local backdrop: TextButton
local toastStack: Frame
local statusSlot: Frame

type Counter = { pill: Frame, amount: TextLabel, plus: TextButton, outline: UIStroke, color: Color3, shown: number, target: number, kind: string, ready: boolean }
local counters: { Counter } = {}

local api: WindowApi

-- Helpers ------------------------------------------------------------------------------

local function usingGamepad(): boolean
	local input = deps.input
	return input ~= nil and typeof(input.device) == "function" and input.device() == "gamepad"
end

local function firstControl(root: Instance): GuiObject?
	for _, item in root:GetDescendants() do
		if item:IsA("GuiButton") and item.Selectable and item.Visible then
			return item
		end
	end
	return nil
end

local function focus(target: GuiObject?)
	if target and usingGamepad() then
		GuiService.SelectedObject = target
	end
end

-- Clear the gamepad selection if it's inside something that's going away
local function releaseFocus(root: Instance)
	if not usingGamepad() then
		return
	end
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(root) then
		GuiService.SelectedObject = nil
	end
end

local function sortedEntries(): { Entry }
	local list = {}
	for _, entry in registry do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		if a.spec.order == b.spec.order then
			return a.id < b.id
		end
		return a.spec.order < b.spec.order
	end)
	return list
end

local function powerLabel(view: { [string]: any }?): (string, string?)
	local selected = view and view.selected
	local id = if typeof(selected) == "table" then selected.power else nil
	if typeof(id) ~= "string" or id == "" then
		return (if view then "No power selected" else "Loading..."), nil
	end
	local name = powerNames[id] or (string.gsub(id, "(%l)(%u)", "%1 %2"))
	local degree = selected.degree
	if typeof(degree) == "number" then
		return `{name}  ·  Degree {degree}`, id
	end
	return name, id
end

-- Back button (gamepad B / Escape) ----------------------------------------------------------

local confirmState: { close: (confirmed: boolean) -> () }? = nil
local backBound = false

local function syncBackBinding()
	local wanted = openId ~= nil or confirmState ~= nil
	if wanted == backBound then
		return
	end
	backBound = wanted
	if wanted then
		ContextActionService:BindAction(BACK_ACTION, function(_, state)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			if confirmState then
				confirmState.close(false)
			elseif openId then
				Shell.close()
			else
				return Enum.ContextActionResult.Pass
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)
	else
		ContextActionService:UnbindAction(BACK_ACTION)
	end
end

-- Layout ----------------------------------------------------------------------------------

local function navEntries(): { Entry }
	local list = {}
	for _, entry in sortedEntries() do
		if entry.spec.nav ~= false then
			table.insert(list, entry)
		end
	end
	return list
end

local function relayout()
	if not initialized then
		return
	end
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Theme.Size.Design
	local base = math.clamp(math.min(viewport.X / Theme.Size.Design.X, viewport.Y / Theme.Size.Design.Y), Theme.Scale.Min, Theme.Scale.Max)
	local setting = Settings.get("uiScale")
	local factor = if typeof(setting) == "number" and setting == setting then math.clamp(setting, 0.5, 1.5) else 1
	local scale = base * factor
	uiScale.Scale = scale

	local inset = GuiService:GetGuiInset()
	local width = viewport.X / scale
	local height = math.max(1, viewport.Y - inset.Y) / scale
	compact = viewport.X < COMPACT_WIDTH or viewport.Y < COMPACT_HEIGHT
	local look = MODES[mode]

	-- Cinematic hides the whole interface (HUD included)
	gui.Enabled = not look.hidden

	-- Top bar
	playerCard.Visible = look.topBar == "full"
	wallet.Visible = look.topBar == "full"
	smallBar.Visible = look.topBar == "small"
	gearButton.Visible = registry.Settings ~= nil
	-- The wallet's + buttons only appear once there's a shop to open
	local hasShop = registry.Shop ~= nil
	for _, counter in counters do
		counter.plus.Visible = hasShop
		counter.amount.Size = UDim2.new(1, if hasShop then -46 - 56 else -46 - 16, 0, 24)
	end
	local top = EDGE
	if look.topBar ~= "none" then
		top += TOP_BAR + 10
	end
	banner.Visible = not Profile.saving and look.topBar == "full"
	if banner.Visible then
		banner.Position = UDim2.new(0.5, 0, 0, top)
		banner.Size = UDim2.fromOffset(math.min(BANNER_WIDTH, width - EDGE * 2), BANNER)
		top += BANNER + 8
	end

	-- Status slot (the queue pill): in the top bar row between the player card
	-- and the wallet when there's room, otherwise centred under the top bar
	local walletWidth = WALLET_PILL * 2 + Space.S
	local free = width - EDGE * 2 - PLAYER_CARD - walletWidth - 24
	if look.topBar ~= "full" then
		statusSlot.Position = UDim2.new(0.5, 0, 0, EDGE)
		statusSlot.Size = UDim2.fromOffset(math.min(STATUS_WIDTH, width - EDGE * 2 - TOP_BAR * 2), TOP_BAR)
	elseif free >= 340 then
		statusSlot.Position = UDim2.fromOffset(EDGE + PLAYER_CARD + 12 + free / 2, EDGE)
		statusSlot.Size = UDim2.fromOffset(math.min(STATUS_WIDTH, free), TOP_BAR)
	else
		statusSlot.Position = UDim2.new(0.5, 0, 0, top)
		statusSlot.Size = UDim2.fromOffset(math.min(STATUS_WIDTH, width - EDGE * 2), TOP_BAR)
	end

	-- Toasts sit on the right under the top bar (under the feed in fights)
	local toastTop = if mode == "Match" or mode == "Spectate" then math.max(top, MATCH_TOAST_TOP) else top
	toastStack.Position = UDim2.new(1, -EDGE, 0, toastTop)
	toastStack.Size = UDim2.new(0, TOAST_WIDTH, 1, -toastTop - EDGE)

	-- Dock: items shrink to fit the height; icons only on phones
	local items = navEntries()
	dock.Visible = look.dock and #items > 0
	local dockWidth = 0
	local available = height - top - EDGE
	if dock.Visible then
		local count = #items
		local fit = math.floor((available - DOCK_PADDING * 2 - (count - 1) * DOCK_GAP) / count)
		local iconsOnly = compact or fit < 56
		local itemSize = if iconsOnly
			then Vector2.new(DOCK_COMPACT, math.clamp(fit, 44, DOCK_COMPACT))
			else Vector2.new(DOCK_ITEM_WIDTH, math.min(fit, DOCK_ITEM_MAX_HEIGHT))
		for _, entry in items do
			local nav = entry.nav
			if nav then
				nav.button.Size = UDim2.fromOffset(itemSize.X, itemSize.Y)
				nav.label.Visible = not iconsOnly
				nav.tile.AnchorPoint = Vector2.new(0.5, if iconsOnly then 0.5 else 0)
				nav.tile.Position = if iconsOnly then UDim2.fromScale(0.5, 0.5) else UDim2.new(0.5, 0, 0, 9)
			end
		end
		dockWidth = itemSize.X + DOCK_PADDING * 2
		dock.Size = UDim2.fromOffset(dockWidth, 0)
		dock.Position = UDim2.fromOffset(EDGE, top + available / 2)
	end

	-- Windows: centred in the space the chrome leaves, never bigger than it
	local left = if dock.Visible then EDGE + dockWidth + 12 else EDGE
	local availableWidth = width - left - EDGE
	for _, entry in registry do
		local frame = entry.frame
		if frame then
			local wanted = entry.spec.size or Theme.Size.DefaultWindow
			local w = math.max(MIN_WINDOW.X, math.min(wanted.X, availableWidth))
			local h = math.max(MIN_WINDOW.Y, math.min(wanted.Y, available))
			frame.Size = UDim2.fromOffset(w, h)
			frame.Position = UDim2.fromOffset(left + availableWidth / 2, top + available / 2)
		end
	end
end

-- Top bar ------------------------------------------------------------------------------------

local function currencyPill(parent: Instance, order: number, kind: string, icon: string, color: Color3): Counter
	local pill = Components.panel({
		Name = kind == "money" and "Money" or "Gems",
		LayoutOrder = order,
		Size = UDim2.fromOffset(WALLET_PILL, TOP_BAR),
		BackgroundTransparency = Theme.Glass.Panel,
		Active = false,
		Parent = parent,
	})
	local outline = pill:FindFirstChildOfClass("UIStroke") :: UIStroke
	local drawn = Components.icon(icon, 22, color)
	drawn.AnchorPoint = Vector2.new(0, 0.5)
	drawn.Position = UDim2.new(0, 14, 0.5, 0)
	drawn.Parent = pill
	local amount = Components.text({
		Name = "Amount",
		Text = NO_VALUE,
		Style = "number",
		TextSize = 17,
		AlignX = "Right",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 46, 0.5, 0),
		Size = UDim2.new(1, -46 - 56, 0, 24),
		Parent = pill,
	})
	local plus = Components.button("", {
		Name = "Add",
		Variant = "Ghost",
		Icon = "plus",
		IconSize = 16,
		Accent = color,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		Parent = pill,
	}, function()
		if registry.Shop then
			Shell.open("Shop", { focus = kind })
		end
	end)
	return { pill = pill, amount = amount, plus = plus, outline = outline, color = color, shown = 0, target = 0, kind = kind, ready = false }
end

local function refreshProfile()
	local view = Profile.get()
	local text, powerId = powerLabel(view)
	powerText.Text = text
	if powerIcon then
		powerIcon:Destroy()
		powerIcon = nil
	end
	if powerId then
		local drawn = Components.icon(Icons.sigil(powerId), 14, Colors.Cyan)
		drawn.AnchorPoint = Vector2.new(0, 0.5)
		drawn.Position = UDim2.new(0, 56, 0, 36)
		drawn.Parent = playerCard
		powerIcon = drawn
	end
	powerText.Position = UDim2.fromOffset(if powerId then 76 else 56, 27)
	powerText.Size = UDim2.new(1, -(if powerId then 86 else 66), 0, 18)
	for _, counter in counters do
		if not view then
			counter.ready = false
			counter.amount.Text = NO_VALUE
		else
			local value = Profile.currency(counter.kind)
			if not counter.ready then
				-- First balance: show it straight away
				counter.ready = true
				counter.shown = value
				counter.target = value
				counter.amount.Text = Components.formatNumber(value)
			elseif value ~= counter.target then
				if value > counter.target then
					-- A gain: the pill's hairline lights in its currency colour and fades back
					counter.outline.Color = counter.color
					counter.outline.Transparency = 0.1
					tween(counter.outline, TweenInfo.new(0.9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Transparency = Theme.Glass.StrokeTransparency })
				end
				counter.target = value
			end
		end
	end
end

-- Count the numbers up or down smoothly
local function animateCounters(dt: number)
	for _, counter in counters do
		if counter.shown ~= counter.target then
			local gap = counter.target - counter.shown
			local stepped = counter.shown + gap * math.min(1, dt * 8)
			if math.abs(counter.target - stepped) < 1 then
				stepped = counter.target
			end
			counter.shown = stepped
			counter.amount.Text = Components.formatNumber(stepped)
		end
	end
end

local function refreshBanner()
	local message = Profile.savingMessage
	bannerText.Text = if typeof(message) == "string" and message ~= "" then message else DEFAULT_SAVING_MESSAGE
	relayout()
end

local function buildTopBar()
	local chrome = layers.chrome
	-- Player card (top left)
	playerCard = Components.panel({
		Name = "PlayerCard",
		Position = UDim2.fromOffset(EDGE, EDGE),
		Size = UDim2.fromOffset(PLAYER_CARD, TOP_BAR),
		BackgroundTransparency = Theme.Glass.Panel,
		Active = false,
		Parent = chrome,
	})
	avatar = make("ImageLabel", {
		Name = "Avatar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Colors.Raised,
		BorderSizePixel = 0,
		ScaleType = Enum.ScaleType.Crop,
		Parent = playerCard,
	}, {
		Components.corner(Theme.SmallCorner),
		Components.stroke(Colors.Stroke, 1, 0.5),
	})
	avatarInitial = Components.text({
		Text = string.upper(string.sub(player.DisplayName, 1, 1)),
		Style = "Heading",
		Weight = "Bold",
		Color = Colors.TextDim,
		AlignX = "Center",
		Size = UDim2.fromScale(1, 1),
		Parent = avatar,
	})
	Components.text({
		Name = "PlayerName",
		Text = player.DisplayName,
		Style = "strong",
		Position = UDim2.fromOffset(56, 6),
		Size = UDim2.new(1, -66, 0, 22),
		Parent = playerCard,
	})
	powerText = Components.text({
		Name = "Power",
		Text = "Loading...",
		Style = "caption",
		Color = Colors.TextDim,
		Position = UDim2.fromOffset(56, 27),
		Size = UDim2.new(1, -66, 0, 18),
		Parent = playerCard,
	})
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and typeof(content) == "string" and content ~= "" then
			avatar.Image = content
			avatarInitial.Visible = false
		end
	end)

	-- Wallet (top right)
	wallet = make("Frame", {
		Name = "Wallet",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -EDGE, 0, EDGE),
		Size = UDim2.fromOffset(WALLET_PILL * 2 + Space.S, TOP_BAR),
		BackgroundTransparency = 1,
		Parent = chrome,
	})
	Components.list(wallet, Space.S, { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right })
	counters = {
		currencyPill(wallet, 1, "money", "coin", Colors.Money),
		currencyPill(wallet, 2, "gems", "gem", Colors.Gems),
	}

	-- The small top bar for fights: just a settings button
	smallBar = make("Frame", {
		Name = "SmallBar",
		Position = UDim2.fromOffset(EDGE, EDGE),
		Size = UDim2.fromOffset(TOP_BAR, TOP_BAR),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = chrome,
	})
	gearButton = Components.button("", {
		Name = "SettingsButton",
		Variant = "Secondary",
		Icon = "gear",
		IconSize = 22,
		Size = UDim2.fromOffset(TOP_BAR - 4, TOP_BAR - 4),
		Parent = smallBar,
	}, function()
		Shell.toggle("Settings")
	end)

	-- Where short-lived status (like the queue pill) goes; positioned by relayout
	statusSlot = make("Frame", {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(STATUS_WIDTH, TOP_BAR),
		BackgroundTransparency = 1,
		Parent = chrome,
	})

	-- "Not saving" banner
	banner = make("Frame", {
		Name = "SavingBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(BANNER_WIDTH, BANNER),
		BackgroundColor3 = Colors.Warning,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Visible = false,
		Parent = chrome,
	}, {
		Components.corner(Theme.SmallCorner),
		Components.stroke(Colors.Warning, 1, 0.5),
		Components.padding(0, Space.L, 0, Space.L),
	})
	local bannerIcon = Components.icon("warning", 16, Colors.Warning)
	bannerIcon.Name = "Icon"
	bannerIcon.AnchorPoint = Vector2.new(0, 0.5)
	bannerIcon.Position = UDim2.fromScale(0, 0.5)
	bannerIcon.Parent = banner
	bannerText = Components.text({
		Name = "Message",
		Text = DEFAULT_SAVING_MESSAGE,
		Style = "caption",
		Weight = "SemiBold",
		Color = Colors.Warning,
		AlignX = "Center",
		Position = UDim2.fromOffset(24, 0),
		Size = UDim2.new(1, -24, 1, 0),
		Parent = banner,
	})
end

-- Dock -----------------------------------------------------------------------------------------

local function renderNavBadge(entry: Entry)
	local nav = entry.nav
	if not nav then
		return
	end
	local text = badges[entry.id]
	nav.badge.Visible = text ~= nil
	nav.badgeText.Text = text or ""
end

local function buildNavItem(entry: Entry, order: number)
	local spec = entry.spec
	local button = make("TextButton", {
		Name = "Nav_" .. entry.id,
		LayoutOrder = order,
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
		SelectionImageObject = Components.noSelection,
		Size = UDim2.fromOffset(DOCK_ITEM_WIDTH, DOCK_ITEM_MAX_HEIGHT),
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = dockList,
	}, { Components.corner(Theme.SmallCorner) })
	-- The icon sits in a fixed 28 px box so every item lines up
	local tile = make("Frame", {
		Name = "Tile",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 9),
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = button,
	})
	local drawn = Components.icon(spec.icon, 24, Colors.TextDim)
	drawn.AnchorPoint = Vector2.new(0.5, 0.5)
	drawn.Position = UDim2.fromScale(0.5, 0.5)
	drawn.ZIndex = 2
	drawn.Parent = tile
	local label = Components.text({
		Name = "Label",
		Text = spec.label or string.upper(spec.title),
		Style = "caption",
		Weight = "SemiBold",
		Color = Colors.TextDim,
		AlignX = "Center",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -6, 0, 18),
		ZIndex = 2,
		Parent = button,
	})
	local badge = make("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -2, 0, 2),
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Colors.Accent,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		Parent = tile,
	}, {
		Components.corner(Theme.PillCorner),
		Components.padding(0, 5, 0, 5),
		Components.stroke(Colors.Ink, 1.5, 0),
		make("UISizeConstraint", { MinSize = Vector2.new(18, 18) }),
	})
	local badgeText = Components.text({
		Style = "caption",
		Weight = "Bold",
		Color = Colors.TextOnLight,
		AlignX = "Center",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = 3,
		Parent = badge,
	})
	local surface = Components.surface(button, { Edge = "left", Flat = true, NoFrame = true, Title = label })
	local _, refresh = Components.interactive(button, function(state, instant)
		-- The open window's item is the selected one
		state.selected = openId == entry.id
		surface.render(state, instant)
		local color = if state.selected then Colors.Cyan elseif state.hovered or state.focused then Colors.Text else Colors.TextDim
		Icons.tint(drawn, color)
	end)
	button.Activated:Connect(function()
		Shell.toggle(entry.id)
	end)
	entry.nav = { button = button, refresh = refresh, tile = tile, label = label, badge = badge, badgeText = badgeText }
	renderNavBadge(entry)
end

local function renderDock()
	if not initialized then
		return
	end
	for _, entry in registry do
		if entry.nav then
			entry.nav.button:Destroy()
			entry.nav = nil
		end
	end
	for order, entry in navEntries() do
		buildNavItem(entry, order)
	end
end

local function refreshNav()
	for _, entry in registry do
		if entry.nav then
			entry.nav.refresh()
		end
	end
end

local function buildDock()
	dock = Components.panel({
		Name = "Dock",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(DOCK_ITEM_WIDTH + DOCK_PADDING * 2, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = Theme.Glass.Panel,
		Active = false,
		Visible = false,
		Parent = layers.chrome,
	})
	Components.padding(DOCK_PADDING).Parent = dock
	dockList = dock
	Components.list(dock, DOCK_GAP, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
end

-- Windows -------------------------------------------------------------------------------------

local function setBackdrop(visible: boolean)
	if visible then
		backdrop.Visible = true
		tween(backdrop, Motion.Normal, { BackgroundTransparency = BACKDROP_ALPHA })
	else
		local fading = tween(backdrop, Motion.In, { BackgroundTransparency = 1 })
		fading.Completed:Once(function()
			if openId == nil then
				backdrop.Visible = false
			end
		end)
	end
end

-- The blur behind open windows: one BlurEffect the Shell owns (in the camera,
-- like the other screen effects). It is tweened up when a window or a dialog
-- opens and always back to zero when the last one closes.
local blur: BlurEffect? = nil
local blurWanted = 0

local function blurEffect(): BlurEffect?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	if blur and blur.Parent == camera then
		return blur
	end
	if blur then
		blur:Destroy()
	end
	blur = make("BlurEffect", { Name = BLUR_NAME, Size = 0, Parent = camera })
	return blur
end

local function updateBlur()
	local wanted = if confirmState then BLUR_MODAL elseif openId then BLUR_WINDOW else 0
	if Settings.get("reducedEffects") == true then
		wanted = math.floor(wanted / 2)
	end
	blurWanted = wanted
	local effect = blurEffect()
	if effect then
		tween(effect, if wanted > 0 then Motion.Slow else Motion.Normal, { Size = wanted })
	end
end

-- The blur size the Shell is heading for (0 when nothing is open)
function Shell.blurSize(): number
	return blurWanted
end

-- The Shell's BlurEffect, once it has been needed (nil before)
function Shell.blur(): BlurEffect?
	return blur
end

local function ensureBuilt(entry: Entry): boolean
	if entry.frame then
		return true
	end
	local frame, body, parts = Components.window({
		Name = "Window_" .. entry.id,
		Title = entry.spec.title,
		Icon = entry.spec.icon,
		Size = entry.spec.size or Theme.Size.DefaultWindow,
		Accent = entry.spec.accent,
		Visible = false,
		onClose = function()
			if openId == entry.id then
				Shell.close()
			end
		end,
		Parent = layers.windows,
	})
	local ok, result = pcall(entry.spec.build, body, api)
	if not ok then
		warn(`[Shell] the {entry.id} window failed to build: {result}`)
		frame:Destroy()
		Shell.toast(`Couldn't open {entry.spec.title} right now.`, "error")
		return false
	end
	entry.frame = frame
	entry.body = body
	entry.parts = parts
	entry.handlers = if typeof(result) == "table" then result else {}
	relayout()
	return true
end

local function hideWindow(entry: Entry, instant: boolean)
	local frame = entry.frame
	if not frame then
		return
	end
	if entry.fade then
		entry.fade.cancel()
		entry.fade = nil
	end
	releaseFocus(frame)
	if instant then
		frame.Visible = false
		return
	end
	tween(entry.parts.scale, Motion.In, { Scale = 0.97 })
	entry.fade = Components.fade(frame, false, Motion.In, function()
		if openId ~= entry.id then
			frame.Visible = false
		end
	end)
end

local function closeCurrent(instant: boolean)
	local id = openId
	if not id then
		return
	end
	local entry = registry[id]
	openId = nil
	if entry then
		if entry.handlers.onClose then
			entry.handlers.onClose()
		end
		hideWindow(entry, instant)
	end
	refreshNav()
end

-- Opens a registered window (closing any other); calls its onOpen(args)
function Shell.open(id: string, args: any?)
	if not initialized then
		warn("[Shell] open called before init")
		return
	end
	local entry = registry[id]
	if not entry then
		warn(`[Shell] no window called {id}`)
		return
	end
	if openId == id then
		if entry.handlers.onOpen then
			entry.handlers.onOpen(args)
		end
		return
	end
	if not MODES[mode].windows and id ~= "Settings" then
		return
	end
	closeCurrent(true)
	if not ensureBuilt(entry) then
		return
	end
	local frame = entry.frame :: Frame
	openId = id
	if entry.fade then
		entry.fade.cancel()
		entry.fade = nil
	end
	frame.Visible = true
	if entry.handlers.onOpen then
		entry.handlers.onOpen(args)
	end
	entry.parts.scale.Scale = 0.96
	tween(entry.parts.scale, Motion.Slow, { Scale = 1 })
	entry.fade = Components.fade(frame, true, Motion.Normal)
	setBackdrop(true)
	updateBlur()
	refreshNav()
	syncBackBinding()
	local target = if entry.handlers.focus then entry.handlers.focus() else nil
	focus(target or firstControl(entry.body :: Frame) or entry.parts.close)
end

-- Closes the open window (if any)
function Shell.close()
	if not openId then
		return
	end
	closeCurrent(false)
	setBackdrop(false)
	updateBlur()
	syncBackBinding()
end

function Shell.toggle(id: string)
	if openId == id then
		Shell.close()
	else
		Shell.open(id)
	end
end

-- With an id: is that window open? Without: is any window open?
function Shell.isOpen(id: string?): boolean
	if id then
		return openId == id
	end
	return openId ~= nil
end

-- Has a window with this id been registered?
function Shell.hasWindow(id: string): boolean
	return registry[id] ~= nil
end

function Shell.registerWindow(id: string, spec: WindowSpec)
	assert(typeof(id) == "string" and id ~= "", "window id must be a string")
	assert(typeof(spec) == "table" and typeof(spec.build) == "function", "window spec needs a build function")
	local existing = registry[id]
	if existing and existing.frame then
		if openId == id then
			closeCurrent(true)
		end
		existing.frame:Destroy()
	end
	registry[id] = {
		id = id,
		spec = spec,
		frame = nil,
		body = nil,
		parts = nil,
		handlers = {},
		fade = nil,
		nav = nil,
	}
	renderDock()
	relayout()
end

-- A badge on a dock item, e.g. "!" when a reward can be claimed (nil removes it)
function Shell.setNavBadge(id: string, text: string?)
	badges[id] = if typeof(text) == "string" and text ~= "" then text else nil
	local entry = registry[id]
	if entry then
		renderNavBadge(entry)
	end
end

-- Toasts ----------------------------------------------------------------------------------------

local toastOrder = 0

-- A short message top-right: "info" | "success" | "error" | "reward"
function Shell.toast(message: string, kind: string?)
	if not initialized or typeof(message) ~= "string" or message == "" then
		return
	end
	local look = Theme.ToastKinds[kind or "info"] or Theme.ToastKinds.info
	toastOrder -= 1
	local holder = make("Frame", {
		Name = "Toast",
		LayoutOrder = toastOrder,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = toastStack,
	})
	local panel = make("TextButton", {
		Name = "Panel",
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = Theme.Glass.Window,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = holder,
	}, {
		Components.corner(Theme.SmallCorner),
		Components.stroke(Colors.Stroke, 1, 0.5),
		Components.padding(Space.M, Space.L, Space.M, Space.L + 4),
	})
	make("Frame", {
		Name = "Accent",
		Position = UDim2.fromOffset(-(Space.L + 4), -Space.M),
		Size = UDim2.new(0, 3, 1, Space.M * 2),
		BackgroundColor3 = look.color,
		BorderSizePixel = 0,
		Parent = panel,
	})
	local drawn = Components.icon(look.icon, 20, look.color)
	drawn.Position = UDim2.fromOffset(0, 1)
	drawn.Parent = panel
	Components.text({
		Name = "Message",
		Text = message,
		Style = "strong",
		Weight = "Medium",
		Color = Colors.Text,
		Wrap = true,
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -32, 0, 22),
		Parent = panel,
	})

	tween(panel, Motion.Slow, { Position = UDim2.fromOffset(0, 0) })
	Components.fade(panel, true, Motion.Normal)
	local gone = false
	local function dismiss()
		-- Already gone, or pushed out of the stack by newer toasts
		if gone or holder.Parent == nil then
			return
		end
		gone = true
		tween(panel, Motion.In, { Position = UDim2.fromOffset(32, 0) })
		Components.fade(panel, false, Motion.In, function()
			holder:Destroy()
		end)
	end
	panel.Activated:Connect(dismiss)
	-- Longer messages stay a little longer
	task.delay(TOAST_SECONDS + math.min(3, #message / 40), dismiss)

	-- Only the newest few
	local stack = {}
	for _, child in toastStack:GetChildren() do
		if child:IsA("Frame") then
			table.insert(stack, child)
		end
	end
	if #stack > MAX_TOASTS then
		table.sort(stack, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		for index = 1, #stack - MAX_TOASTS do
			stack[index]:Destroy()
		end
	end
end

-- Confirm dialog -----------------------------------------------------------------------------------

-- A modal question. Shows the price (if any) before the player agrees.
function Shell.confirm(options: ConfirmOptions)
	if not initialized or typeof(options) ~= "table" then
		return
	end
	if confirmState then
		confirmState.close(false)
	end
	local modal = layers.modal
	local dim = make("TextButton", {
		Name = "ConfirmDim",
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = modal,
	})
	local dialog = make("Frame", {
		Name = "Dialog",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = Theme.Glass.Window,
		BorderSizePixel = 0,
		Active = true,
		Parent = dim,
	}, {
		Components.corner(Theme.Corner),
		Components.stroke(if options.danger then Colors.Danger else Colors.Stroke, 1, if options.danger then 0.35 else 0.5),
		Components.padding(Space.XL, Space.XL, Space.XL, Space.XL),
	})
	local dialogScale = make("UIScale", { Scale = 0.96, Parent = dialog })
	Components.list(dialog, Space.M)

	local accent = if options.danger then Colors.Danger elseif options.price then Colors.Accent else Colors.Cyan
	local header = make("Frame", {
		Name = "Header",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		Parent = dialog,
	})
	local headIcon = Components.icon(options.icon or (if options.danger then "warning" elseif options.price then "shop" else "info"), 22, accent)
	headIcon.AnchorPoint = Vector2.new(0, 0.5)
	headIcon.Position = UDim2.fromScale(0, 0.5)
	headIcon.Parent = header
	Components.text({
		Name = "Title",
		Text = options.title or "Are you sure?",
		Style = "heading",
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.new(1, -34, 1, 0),
		Parent = header,
	})
	Components.divider({ LayoutOrder = 2, Parent = dialog })
	if typeof(options.body) == "string" and options.body ~= "" then
		Components.text({ Name = "Body", Text = options.body, Style = "body", Wrap = true, LayoutOrder = 3, Parent = dialog })
	end
	if typeof(options.price) == "table" then
		local priceRow = make("Frame", {
			Name = "PriceRow",
			LayoutOrder = 4,
			Size = UDim2.new(1, 0, 0, 48),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Parent = dialog,
		}, { Components.corner(Theme.SmallCorner), Components.stroke(Colors.Stroke, 1, 0.8), Components.padding(0, Space.M, 0, Space.M) })
		Components.text({ Text = "Price", Style = "overline", Size = UDim2.new(0, 80, 1, 0), Parent = priceRow })
		Components.price(priceRow, options.price, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
		})
	end
	local buttons = make("Frame", {
		Name = "Buttons",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, Theme.Size.Control),
		BackgroundTransparency = 1,
		Parent = dialog,
	})
	local closed = false
	local function close(confirmed: boolean)
		if closed then
			return
		end
		closed = true
		if confirmState and confirmState.close == close then
			confirmState = nil
		end
		releaseFocus(dim)
		tween(dim, Motion.In, { BackgroundTransparency = 1 })
		tween(dialogScale, Motion.In, { Scale = 0.97 })
		Components.fade(dialog, false, Motion.In, function()
			dim:Destroy()
		end)
		updateBlur()
		syncBackBinding()
		if confirmed then
			options.onConfirm()
		elseif options.onCancel then
			options.onCancel()
		end
	end
	local cancelButton = Components.button(options.cancelText or "Cancel", {
		Name = "Cancel",
		Variant = "Secondary",
		Size = UDim2.new(0.5, -Space.S / 2, 1, 0),
		Parent = buttons,
	}, function()
		close(false)
	end)
	local confirmButton = Components.button(options.confirmText or (if options.price then "Buy" else "Confirm"), {
		Name = "Confirm",
		Variant = if options.danger then "Danger" else "Primary",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, -Space.S / 2, 1, 0),
		Parent = buttons,
	}, function()
		close(true)
	end)
	dim.Activated:Connect(function()
		close(false)
	end)

	confirmState = { close = close }
	tween(dim, Motion.Normal, { BackgroundTransparency = 0.4 })
	tween(dialogScale, Motion.Pop, { Scale = 1 })
	Components.fade(dialog, true, Motion.Normal)
	updateBlur()
	syncBackBinding()
	-- Purchases start on Cancel for gamepads, so a double press never buys
	focus(if options.price then cancelButton else confirmButton)
end

-- Modes ---------------------------------------------------------------------------------------------

-- "Lobby" | "Match" | "Editor" | "Spectate" | "Cinematic"
function Shell.setMode(newMode: string)
	if not MODES[newMode] then
		warn(`[Shell] unknown mode {newMode}`)
		return
	end
	mode = newMode
	if not MODES[newMode].windows then
		Shell.close()
		if confirmState then
			confirmState.close(false)
		end
	end
	relayout()
end

function Shell.getMode(): string
	return mode
end

-- The interface's current scale (design pixels -> screen pixels)
function Shell.scale(): number
	return if initialized then uiScale.Scale else 1
end

-- Layers other screens can parent overlays to: "chrome" (top bar, dock),
-- "windows", "toasts", "modal" (full screen), or "status" (a slot in the top
-- bar the size of a pill, for things like the queue status)
function Shell.layer(name: string): GuiObject?
	if name == "status" then
		return if initialized then statusSlot else nil
	end
	return layers[name]
end

-- Display names for power ids in the player card (e.g. { StrongDude = "Strong Dude" })
function Shell.setPowerNames(names: { [string]: string })
	for id, name in names do
		if typeof(id) == "string" and typeof(name) == "string" then
			powerNames[id] = name
		end
	end
	if initialized then
		refreshProfile()
	end
end

-- Setup -------------------------------------------------------------------------------------------

local function layer(name: string, zIndex: number): Frame
	return make("Frame", {
		Name = "Shell" .. name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = zIndex,
		Parent = gui,
	})
end

-- Builds the chrome inside `screen`. deps.input is the InputController (for gamepad detection).
function Shell.init(screen: ScreenGui, dependencies: { input: any? }?)
	if initialized then
		warn("[Shell] init called twice")
		return
	end
	initialized = true
	gui = screen
	deps = dependencies or {}
	api = {
		close = Shell.close,
		toast = Shell.toast,
		confirm = Shell.confirm,
		open = Shell.open,
	}
	-- The one UIScale for this ScreenGui
	uiScale = screen:FindFirstChildOfClass("UIScale") or make("UIScale", { Parent = screen })

	-- Dims the world behind an open window; clicking it closes the window
	backdrop = make("TextButton", {
		Name = "ShellBackdrop",
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = screen,
	})
	backdrop.Activated:Connect(Shell.close)
	layers.backdrop = backdrop
	layers.chrome = layer("Chrome", 6)
	layers.windows = layer("Windows", 7)
	layers.toasts = layer("Toasts", 30)
	layers.modal = layer("Modal", 40)

	toastStack = make("Frame", {
		Name = "Stack",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = layers.toasts,
	})
	Components.list(toastStack, Space.S, { HorizontalAlignment = Enum.HorizontalAlignment.Right })

	buildTopBar()
	buildDock()
	renderDock()

	-- Keep everything fitted to the screen and the player's interface size
	local cameraConnection: RBXScriptConnection? = nil
	local function watchCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
		end
		relayout()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()
	Settings.changed:Connect(function(key)
		if key == "uiScale" then
			relayout()
		end
	end)

	-- Profile: currencies, power, the saving banner and server toasts
	Profile.changed:Connect(refreshProfile)
	Profile.persistenceChanged:Connect(refreshBanner)
	Profile.toasted:Connect(function(text, kind)
		Shell.toast(text, kind)
	end)
	refreshProfile()
	refreshBanner()

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		animateCounters(dt)
		elapsed += dt
		if elapsed < 1 / 20 then
			return
		end
		local step = elapsed
		elapsed = 0
		local entry = openId and registry[openId]
		if entry and entry.handlers.update then
			entry.handlers.update(step)
		end
	end)
end

return Shell
