-- The Wheel window (opened by the wheel's prompt in the Spectating Lounge, Action "Lounge:Wheel").
-- Left: a wheel that turns to the result the server drew. Right: every prize and its chance, always
-- on screen before any spin or purchase, the rules in plain words, and your last results.
-- DECISIONS 41: odds are shown as percentages that add to 100; the result comes from the server and
-- the animation only lands on it; a player Roblox marks as restricted for paid random items gets no
-- paid spin controls at all (the server sends paidAllowed = false); no countdowns, no pressure.
-- This window only asks (Remotes.LoungeRequest); WheelService decides everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Wheel = require(ReplicatedStorage.Shared.Config.Wheel)
local WheelArt = require(ReplicatedStorage.Shared.WheelArt)
local Components = require(script.Parent.Components)
local Shell = require(script.Parent.Shell)
local Theme = require(script.Parent.Theme)
local PriceFetcher = require(script.Parent.Parent.PriceFetcher)

local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LoungeRequest = Remotes:WaitForChild("LoungeRequest") :: RemoteEvent
local ShopRequest = Remotes:WaitForChild("ShopRequest") :: RemoteEvent

local WheelWindow = {}

local DISC = 300
local SPIN_SECONDS = 5

-- What the server last told us about this player's wheel
local state: any = { freeReady = true, paidAllowed = false, credits = 0, spins = 0, last = {}, products = {} }
local spinning = false
local waiting = 0
local resultText = ""
local redraw: (() -> ())? = nil
local disc: Frame? = nil
local discRotation = 0

local function kindColor(kind: string): Color3
	local c = Wheel.KindColors[kind] or { 200, 200, 200 }
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function sendSpin(kind: string)
	if spinning or waiting > 0 then
		return
	end
	waiting = 8
	resultText = ""
	LoungeRequest:FireServer(if kind == "free" then Protocol.LoungeAction.SpinFree else Protocol.LoungeAction.SpinPaid)
	if redraw then
		redraw()
	end
end

-- Turns the wheel so segment `index` ends under the pointer, somewhere inside the segment
local function land(index: number, after: () -> ())
	local wheel = disc
	if not wheel then
		after()
		return
	end
	local width = 360 / #Wheel.Prizes
	local offset = (math.random() - 0.5) * width * 0.6
	local theta = (index - 0.5) * width + offset
	local delta = 4 * 360 + ((discRotation + theta) % 360)
	discRotation -= delta
	spinning = true
	local tween = TweenService:Create(wheel, TweenInfo.new(SPIN_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Rotation = discRotation })
	tween.Completed:Connect(function()
		spinning = false
		after()
	end)
	tween:Play()
end

-- Server replies and state (LoungeController forwards DataEvent Lounge here)
function WheelWindow.onData(data: any)
	if typeof(data) ~= "table" then
		return
	end
	if data.kind == "Wheel" then
		state = data
		if not spinning and redraw then
			redraw()
		end
	elseif data.kind == "Spin" then
		waiting = 0
		if typeof(data.wheel) == "table" then
			state = data.wheel
		end
		if data.ok == true and typeof(data.index) == "number" then
			local text = tostring(data.text or "")
			land(data.index, function()
				resultText = text
				Shell.toast(text, "success")
				if redraw then
					redraw()
				end
			end)
		else
			resultText = tostring(data.text or "The spin did not happen.")
			if redraw then
				redraw()
			end
		end
		if redraw then
			redraw()
		end
	end
end

function WheelWindow.getState(): any
	return state
end

local function priceTextFor(key: string): (string, boolean)
	local product = Monetization.Products[key]
	local price = PriceFetcher.get("Product", product.id, function()
		if redraw then
			redraw()
		end
	end)
	return PriceFetcher.describe(price), price.status == "ready"
end

local function build(body: Frame, _api: any)
	local root = make("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = body })

	-- Left: the wheel, the pointer, the buttons
	-- The left column scrolls when the window is short: the wheel, then the buttons
	local left = Components.scroll({ Name = "Left", Size = UDim2.new(0, DISC + 24, 1, 0), Padding = 2, Parent = root })
	Components.list(left, Space.S)
	local stageHolder = make("Frame", { Name = "StageHolder", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, DISC + 20), BackgroundTransparency = 1, Parent = left })
	local stage = make("Frame", {
		Name = "Stage", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(DISC, DISC),
		BackgroundColor3 = Colors.PanelLight, BorderSizePixel = 0, Parent = stageHolder,
	}, { Components.corner(Theme.Round), Components.stroke(Colors.Copper, 3, 0.2) })
	local wheel = make("Frame", {
		Name = "Disc", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.96, 0.96),
		BackgroundTransparency = 1, BorderSizePixel = 0, Rotation = discRotation, Parent = stage,
	})
	disc = wheel
	WheelArt.mount(wheel, { font = Theme.Faces.ExtraBold, maxText = 40 })
	-- The pointer does not turn
	make("Frame", {
		Name = "Pointer", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = Colors.Accent, BorderSizePixel = 0, Rotation = 45, ZIndex = 5, Parent = stage,
	})

	local controls = make("Frame", {
		Name = "Controls", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = left,
	})
	Components.list(controls, Space.S)

	-- Right: odds and rules
	local right = Components.scroll({ Name = "Right", Position = UDim2.fromOffset(DISC + 40, 0), Size = UDim2.new(1, -(DISC + 40), 1, 0), Padding = 2, Parent = root })
	Components.list(right, Space.M)

	local function render()
		for _, child in controls:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for _, child in right:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local order = 0
		local function nextOrder()
			order += 1
			return order
		end

		-- Controls
		local result = Components.text({
			Name = "Result", Text = if resultText ~= "" then resultText else "Spin for a prize. Every prize and its chance is listed here.",
			Style = "Label", Lines = 3, Color = if resultText ~= "" then Colors.Gold else Colors.TextDim, LayoutOrder = nextOrder(), Parent = controls,
		})
		result.TextTruncate = Enum.TextTruncate.None
		local busy = spinning or waiting > 0
		local free = Components.button(if state.freeReady then "Free spin" else "Free spin used today", {
			Name = "FreeSpin", Variant = if state.freeReady then "Primary" else "Secondary", KeepCase = true,
			Size = UDim2.new(1, 0, 0, 44), LayoutOrder = nextOrder(), Parent = controls,
		}, function()
			sendSpin("free")
		end)
		Components.setDisabled(free, busy or not state.freeReady, if state.freeReady then nil else "Your free spin comes back tomorrow.")
		if not state.freeReady then
			Components.text({ Name = "FreeNote", Text = "Your next free spin is ready tomorrow.", Style = "Caption", LayoutOrder = nextOrder(), Parent = controls })
		end
		if state.paidAllowed then
			local held = state.credits or 0
			local paid = Components.button(`Use a paid spin ({held} held)`, {
				Name = "PaidSpin", Variant = "Secondary", KeepCase = true, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = nextOrder(), Parent = controls,
			}, function()
				sendSpin("paid")
			end)
			Components.setDisabled(paid, busy or held < 1, if held < 1 then "You have no paid spins." else nil)
			for _, key in { "LoungeSpin", "LoungeSpin5" } do
				local product = Monetization.Products[key]
				local info = state.products and state.products[key]
				local onSale = info ~= nil and info.onSale == true
				local priceText = priceTextFor(key)
				local label = `Buy {product.wheelSpins} {if product.wheelSpins == 1 then "spin" else "spins"}: {if onSale then priceText else "Available soon"}`
				local button = Components.button(label, {
					Name = "Buy_" .. key, Variant = "Secondary", KeepCase = true, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = nextOrder(), Parent = controls,
				}, function()
					ShopRequest:FireServer(Protocol.ShopAction.PromptProduct, key)
				end)
				Components.setDisabled(button, busy or not onSale, if onSale then nil else "Available soon")
			end
		end

		-- Odds
		local card = Components.panel({
			Name = "OddsCard", BackgroundColor3 = Colors.PanelLight, BackgroundTransparency = 0, Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = right,
		})
		card.Parent = right
		make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = card })
		Components.list(card, 6)
		Components.text({ Name = "Heading", Text = "Prizes and chances", Style = "Heading", LayoutOrder = 1, Parent = card })
		local index = 1
		for _, prize in Wheel.Prizes do
			index += 1
			local rowFrame = make("Frame", { Name = "Row_" .. prize.id, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = index, Parent = card })
			make("Frame", { Name = "Swatch", Position = UDim2.fromOffset(0, 6), Size = UDim2.fromOffset(6, 14), BackgroundColor3 = kindColor(prize.kind), BorderSizePixel = 0, Parent = rowFrame })
			Components.text({ Name = "Label", Text = prize.label, Style = "Body", Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -90, 1, 0), Parent = rowFrame })
			Components.text({
				Name = "Percent", Text = `{prize.percent}%`, Style = "Label", AlignX = "Right", Color = kindColor(prize.kind),
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 70, 1, 0), Parent = rowFrame,
			})
		end
		Components.divider({ LayoutOrder = index + 1, Parent = card })
		local totalRow = make("Frame", { Name = "Total", Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = index + 2, Parent = card })
		Components.text({ Name = "Label", Text = "Total", Style = "Label", Size = UDim2.new(1, -90, 1, 0), Parent = totalRow })
		Components.text({ Name = "Percent", Text = `{Wheel.total()}%`, Style = "Label", AlignX = "Right", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 70, 1, 0), Parent = totalRow })

		-- Rules
		local rules = Components.panel({
			Name = "RulesCard", BackgroundColor3 = Colors.PanelLight, BackgroundTransparency = 0, Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = right,
		})
		make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = rules })
		Components.list(rules, 6)
		Components.text({ Name = "Heading", Text = "How it works", Style = "Heading", LayoutOrder = 1, Parent = rules })
		local lines = {
			Wheel.FreeText,
			Wheel.RulesText,
			`If you already own a prize, or a fighter trial is for a fighter you own or one that is not out yet, you receive {Wheel.DuplicateMoney} Money instead.`,
			"A fighter trial gives 24 hours of full use in every mode. It does not unlock the fighter for good.",
		}
		if state.paidAllowed then
			table.insert(lines, Wheel.PaidText)
		end
		for lineIndex, line in lines do
			Components.text({ Name = "Rule" .. lineIndex, Text = line, Style = "Body", Color = Colors.TextDim, Wrap = true, LayoutOrder = lineIndex + 1, Parent = rules })
		end

		-- Recent results
		if state.last and #state.last > 0 then
			local recent = Components.panel({
				Name = "RecentCard", BackgroundColor3 = Colors.PanelLight, BackgroundTransparency = 0, Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = right,
			})
			make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = recent })
			Components.list(recent, 4)
			Components.text({ Name = "Heading", Text = `Your last results ({state.spins or 0} spins in all)`, Style = "Heading", LayoutOrder = 1, Parent = recent })
			for lastIndex, id in state.last do
				local prize = Wheel.byId(id)
				if prize then
					Components.text({ Name = "Last" .. lastIndex, Text = prize.label, Style = "Body", Color = Colors.TextDim, LayoutOrder = lastIndex + 1, Parent = recent })
				end
			end
		end
	end
	redraw = render
	render()

	return {
		onOpen = function()
			LoungeRequest:FireServer(Protocol.LoungeAction.WheelState)
			render()
		end,
		update = function(dt: number)
			if waiting > 0 then
				waiting -= dt
				if waiting <= 0 and not spinning then
					waiting = 0
					render()
				end
			end
		end,
	}
end

function WheelWindow.register()
	Shell.registerWindow("Wheel", {
		title = "Lounge Wheel",
		label = "WHEEL",
		icon = "★",
		order = 8,
		nav = false,
		size = Vector2.new(940, 600),
		accent = Colors.Copper,
		build = build,
	})
	require(script.Parent.RefreshmentsWindow).register()
end

return WheelWindow
