-- The Refreshments menu (Action "Lounge:Refreshments", the counter in the Spectating Lounge).
-- Original drinks and snacks bought with earned Money only. Every card says exactly what it does,
-- how long it lasts and what it costs; buying asks for a confirmation first. The window only asks:
-- RefreshmentService checks the item, the price, the cooldown and the mode rules.
-- Effects are looks, and at most a small boost to Money and experience in Free-for-All and CPU
-- Practice. Never in Duels, never combat stats (Config/Refreshments).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Refreshments)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Components = require(script.Parent.Components)
local Shell = require(script.Parent.Shell)
local Theme = require(script.Parent.Theme)
local Profile = require(script.Parent.Parent.Profile)

local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LoungeRequest = Remotes:WaitForChild("LoungeRequest") :: RemoteEvent

local RefreshmentsWindow = {}

-- { id, name, endsAt (os.clock) } of the running effect, and when the cooldown ends
local active: any = nil
local cooldownEnds = 0
local lastMessage = ""
local redraw: (() -> ())? = nil
local statusLabel: TextLabel? = nil

local function tint(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function statusText(): string
	if active and active.endsAt > os.clock() then
		return `Active: {active.name}, {clock(active.endsAt - os.clock())} left.`
	end
	return "Nothing active. Drinks and snacks fade on their own."
end

function RefreshmentsWindow.onData(data: any)
	if typeof(data) ~= "table" then
		return
	end
	if data.kind == "Refreshments" then
		active = if typeof(data.active) == "table" then { id = data.active.id, name = data.active.name, endsAt = os.clock() + (data.active.left or 0) } else nil
		cooldownEnds = os.clock() + (data.cooldownLeft or 0)
		if redraw then
			redraw()
		end
	elseif data.kind == "Bought" then
		lastMessage = tostring(data.text or "")
		if redraw then
			redraw()
		end
	end
end

local function build(body: Frame, _api: any)
	local column = Components.scroll({ Name = "Column", Padding = 2, Parent = body })
	Components.list(column, Space.M)

	local function render()
		for _, child in column:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local order = 0
		local function nextOrder()
			order += 1
			return order
		end
		local profile = Profile.get()
		local money = if profile and profile.currencies then profile.currencies.money or 0 else 0
		local cooling = cooldownEnds > os.clock()

		local top = Components.panel({
			Name = "TopCard", BackgroundColor3 = Colors.PanelLight, BackgroundTransparency = 0, Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder(), Parent = column,
		})
		make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = top })
		Components.list(top, 6)
		Components.text({ Name = "Heading", Text = "Refreshments counter", Style = "Heading", LayoutOrder = 1, Parent = top })
		statusLabel = Components.text({ Name = "Status", Text = statusText(), Style = "Label", Color = Colors.Cyan, LayoutOrder = 2, Parent = top })
		Components.text({ Name = "Note", Text = Config.Notes, Style = "Body", Color = Colors.TextDim, Wrap = true, LayoutOrder = 3, Parent = top })
		Components.text({ Name = "Wallet", Text = `You have {Components.formatNumber(money)} Money.`, Style = "Caption", LayoutOrder = 4, Parent = top })
		if lastMessage ~= "" then
			Components.text({ Name = "Last", Text = lastMessage, Style = "Label", Color = Colors.Gold, Wrap = true, LayoutOrder = 5, Parent = top })
		end

		for _, item in Config.Items do
			local card = Components.panel({
				Name = "Item_" .. item.id, BackgroundColor3 = Colors.PanelLight, BackgroundTransparency = 0, Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder(), Parent = column,
			})
			make("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = card })
			local row = make("Frame", { Name = "Row", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = card })
			make("Frame", { Name = "Swatch", Size = UDim2.fromOffset(8, 72), BackgroundColor3 = tint(item.glow), BorderSizePixel = 0, Parent = row })
			local text = make("Frame", {
				Name = "Text", Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -190, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = row,
			})
			Components.list(text, 4)
			Components.text({ Name = "Name", Text = `{item.name}  ({string.lower(item.kind)})`, Style = "Heading", TextSize = 22, LayoutOrder = 1, Parent = text })
			Components.text({ Name = "Blurb", Text = item.blurb, Style = "Body", Color = Colors.TextDim, Wrap = true, LayoutOrder = 2, Parent = text })
			Components.text({ Name = "Duration", Text = `Lasts {math.floor(item.seconds / 60)} minutes`, Style = "Caption", LayoutOrder = 3, Parent = text })
			local buy = make("Frame", {
				Name = "Buy", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(150, 72), BackgroundTransparency = 1, Parent = row,
			})
			Components.price(buy, { money = item.price }, { Position = UDim2.fromOffset(0, 0) })
			local running = active ~= nil and active.id == item.id and active.endsAt > os.clock()
			local button = Components.button(if running then "Active" else "Buy", {
				Name = "BuyButton", Variant = "Primary", KeepCase = true, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(150, 40), Parent = buy,
			}, function()
				Shell.confirm({
					title = `Buy the {item.name}?`,
					body = item.blurb,
					confirmText = "Buy",
					price = { money = item.price },
					onConfirm = function()
						LoungeRequest:FireServer(Protocol.LoungeAction.BuyRefreshment, item.id)
					end,
				})
			end)
			local reason
			if running then
				reason = "You already have this one."
			elseif money < item.price then
				reason = `You need {item.price} Money.`
			elseif cooling then
				reason = "The counter needs a moment."
			end
			Components.setDisabled(button, reason ~= nil, reason)
		end
	end
	redraw = render
	render()

	local elapsed = 0
	return {
		onOpen = function()
			LoungeRequest:FireServer(Protocol.LoungeAction.RefreshmentsState)
			render()
		end,
		update = function(dt: number)
			elapsed += dt
			if elapsed >= 1 then
				elapsed = 0
				if statusLabel and statusLabel.Parent then
					statusLabel.Text = statusText()
				end
				if cooldownEnds > 0 and cooldownEnds <= os.clock() then
					cooldownEnds = 0
					render()
				end
			end
		end,
	}
end

function RefreshmentsWindow.register()
	Shell.registerWindow("Refreshments", {
		title = "Refreshments",
		label = "SNACKS",
		icon = "★",
		order = 9,
		nav = false,
		size = Vector2.new(820, 600),
		accent = Colors.Accent,
		build = build,
	})
end

return RefreshmentsWindow
