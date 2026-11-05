-- The base panel: the owner's controls for their own base (opened from the panel pad in the home,
-- which makes BaseService send BaseEvent.Panel with open = true). One scrolling column so it also
-- fits a phone. The window only asks: BaseService checks ownership, the pass, charges and limits.
--   Who can come in (Friends, Open house, Just me), invite friends (Roblox's own prompt),
--   music style, party mode, the Base Effects Pack effects, Fireworks Show charges,
--   visitors and hearts, and the game room bests.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Homes = require(ReplicatedStorage.Shared.Config.Homes)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Components = require(script.Parent.Components)
local Shell = require(script.Parent.Shell)
local Theme = require(script.Parent.Theme)

local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make
local Action = Protocol.BaseAction

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BaseRequest = Remotes:WaitForChild("BaseRequest") :: RemoteEvent
local BaseEvent = Remotes:WaitForChild("BaseEvent") :: RemoteEvent

local BaseWindow = {}

local state: any = nil
local redraw: (() -> ())? = nil

local function send(action: string, first: any?, second: any?)
	BaseRequest:FireServer(action, first, second)
	-- Ask for the new numbers once the server has acted
	task.delay(0.4, function()
		BaseRequest:FireServer(Action.Panel)
	end)
end

local function card(parent: Instance, name: string, order: number, heading: string, note: string?): Frame
	local frame = Components.panel({
		Name = name, BackgroundColor3 = Colors.PanelLight, BackgroundTransparency = 0, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = parent,
	})
	make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = frame })
	Components.list(frame, 8)
	Components.text({ Name = "Heading", Text = heading, Style = "Heading", LayoutOrder = 1, Parent = frame })
	if note then
		Components.text({ Name = "Note", Text = note, Style = "Body", Color = Colors.TextDim, Wrap = true, LayoutOrder = 2, Parent = frame })
	end
	return frame
end

-- A wrapping row of buttons
local function buttonRow(parent: Instance, order: number): Frame
	local row = make("Frame", { Name = "Buttons", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	make("UIGridLayout", { CellSize = UDim2.fromOffset(176, 44), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
	return row
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
		if not state then
			Components.text({ Name = "Waiting", Text = "Stand in your own base and use the panel pad to manage it.", Style = "Body", Wrap = true, LayoutOrder = 1, Parent = column })
			return
		end

		-- Who can come in
		local access = card(column, "Access", 1, "Who can come in", (Homes.AccessModes[state.access] or {}).blurb)
		local accessRow = buttonRow(access, 3)
		for index, mode in Homes.AccessOrder do
			local info = Homes.AccessModes[mode]
			Components.button(info.label, {
				Name = "Access_" .. mode, Variant = if state.access == mode then "Primary" else "Secondary", KeepCase = true, LayoutOrder = index, Parent = accessRow,
			}, function()
				send(Action.SetAccess, mode)
			end)
		end
		local invite = buttonRow(access, 4)
		Components.button("Invite friends", { Name = "Invite", Variant = "Secondary", KeepCase = true, Parent = invite }, function()
			pcall(function()
				SocialService:PromptGameInvite(Players.LocalPlayer)
			end)
		end)

		-- Music and party
		local music = card(column, "Music", 2, "Music and party", `Music style: {state.jukebox or Homes.DefaultMusic}. Party mode makes the game room lights and dance floor cycle for everyone here.`)
		local musicRow = buttonRow(music, 3)
		for index, style in Homes.MusicStyles do
			Components.button(if style == "SciFi" then "Sci-fi" else style, {
				Name = "Music_" .. style, Variant = if state.jukebox == style then "Primary" else "Secondary", KeepCase = true, LayoutOrder = index, Parent = musicRow,
			}, function()
				send(Action.Jukebox, style)
			end)
		end
		local partyRow = buttonRow(music, 4)
		Components.button(if state.party then "Party mode: on" else "Party mode: off", {
			Name = "Party", Variant = if state.party then "Primary" else "Secondary", KeepCase = true, Parent = partyRow,
		}, function()
			send(Action.Party, not state.party)
		end)

		-- Base Effects Pack
		local effects = card(column, "Effects", 3, "Base effects", if state.ownsEffects
			then "Switch effects on for everyone in your base. Looks only."
			else "The Base Effects Pack unlocks these looks for your base, for good. Looks only, no power.")
		for index, key in Homes.EffectOrder do
			local info = Homes.Effects[key]
			local row = make("Frame", { Name = "Effect_" .. key, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 + index, Parent = effects })
			local text = make("Frame", { Name = "Text", Size = UDim2.new(1, -170, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = row })
			Components.list(text, 2)
			Components.text({ Name = "Name", Text = info.label, Style = "strong", LayoutOrder = 1, Parent = text })
			Components.text({ Name = "Blurb", Text = info.blurb, Style = "small", Color = Colors.TextDim, Wrap = true, LayoutOrder = 2, Parent = text })
			local on = state.effects and state.effects[key] == true
			local toggle = Components.button(if on then "On" else "Off", {
				Name = "Toggle", Variant = if on then "Primary" else "Secondary", KeepCase = true,
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(150, 44), Parent = row,
			}, function()
				send(Action.Effect, key, not on)
			end)
			Components.setDisabled(toggle, not state.ownsEffects, "Needs the Base Effects Pack")
		end
		if not state.ownsEffects then
			local shopRow = buttonRow(effects, 20)
			Components.button("See it in the shop", { Name = "ShopEffects", Variant = "Primary", KeepCase = true, Parent = shopRow }, function()
				Shell.open("Shop", "Cosmetics")
			end)
		end

		-- Fireworks Show
		local charges = tonumber(state.fireworks) or 0
		local fireworks = card(column, "Fireworks", 4, "Fireworks Show", `You have {charges} {if charges == 1 then "show" else "shows"} saved. A show lasts 45 seconds and everyone in your base sees it.`)
		local fireRow = buttonRow(fireworks, 3)
		local launch = Components.button("Launch a show", { Name = "Launch", Variant = "Primary", KeepCase = true, LayoutOrder = 1, Parent = fireRow }, function()
			send(Action.Fireworks)
		end)
		Components.setDisabled(launch, charges <= 0 or state.showing == true, if state.showing then "A show is running" else "No shows saved")
		Components.button("Get a show", { Name = "BuyShow", Variant = "Secondary", KeepCase = true, LayoutOrder = 2, Parent = fireRow }, function()
			Shell.open("Shop", "Cosmetics")
		end)

		-- Visitors and hearts
		local visitors = card(column, "Visitors", 5, "Visitors", `Hearts from visitors: {tonumber(state.hearts) or 0}. A friend who stays a minute earns you a small Money bonus once a day.`)
		local here = state.here or {}
		if #here == 0 then
			Components.text({ Name = "NobodyHere", Text = "Nobody else is here right now.", Style = "Body", Color = Colors.TextDim, LayoutOrder = 3, Parent = visitors })
		end
		for index, person in here do
			local row = make("Frame", { Name = "Here_" .. tostring(person.id), Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 3 + index, Parent = visitors })
			Components.text({ Name = "Name", Text = tostring(person.name), Style = "strong", Size = UDim2.new(1, -170, 1, 0), Parent = row })
			Components.button("Ask to leave", {
				Name = "AskLeave", Variant = "Secondary", KeepCase = true, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(150, 44), Parent = row,
			}, function()
				send(Action.AskLeave, person.id)
			end)
		end
		local recent = {}
		for _, person in state.visitors or {} do
			table.insert(recent, tostring(person.name))
		end
		if #recent > 0 then
			Components.text({ Name = "Recent", Text = "Recent visitors: " .. table.concat(recent, ", "), Style = "small", Color = Colors.TextDim, Wrap = true, LayoutOrder = 30, Parent = visitors })
		end

		-- Game room bests
		local bests = state.bests or {}
		local meter = if bests.PowerMeter then tostring(bests.PowerMeter) .. " points" else "no score yet"
		local reflex = if bests.Reflex then tostring(bests.Reflex) .. " ms" else "no time yet"
		card(column, "Bests", 6, "Game room bests", `Power Meter: {meter}. Reflex: {reflex}.`)
	end
	redraw = render
	render()

	return {
		onOpen = function()
			BaseRequest:FireServer(Action.Panel)
			render()
		end,
	}
end

function BaseWindow.register()
	Shell.registerWindow("Base", {
		title = "Your base",
		label = "BASE",
		icon = "★",
		order = 10,
		nav = false,
		size = Vector2.new(820, 620),
		accent = Colors.Accent,
		build = build,
	})
	BaseEvent.OnClientEvent:Connect(function(kind, data)
		if kind ~= Protocol.BaseEvent.Panel or typeof(data) ~= "table" then
			return
		end
		state = data
		if redraw then
			redraw()
		end
		if data.open and not Shell.isOpen("Base") then
			Shell.open("Base")
		end
	end)
end

return BaseWindow
