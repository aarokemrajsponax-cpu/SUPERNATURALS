-- Nameplates: one quiet BillboardGui over every player's head. The display name, the worn
-- title under it and a thin strip in the colors of the worn plate style. Text sits straight on
-- the world with a thin dark outline (UI_Craft_Pass rule 4), no box. What a player wears is read
-- from the Player attributes CosmeticService keeps (Protocol.Attribute.Title and Plate).
-- Mastery is not replicated to other clients, so no mastery badge is drawn.
-- The owner's crown plate (AdminEffectsController) is separate and keeps working.
--
-- This controller also shows the status moments the server sends on Remotes.StatusEvent:
-- Moment = one short system line in the chat for everyone (display names only, written by the
-- server), Earned = the earner's own on-screen moment (a Michroma headline with a thin outline,
-- no box, then it fades).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Components = require(script.Parent.Parent.UI.Components)
local Theme = require(script.Parent.Parent.UI.Theme)

local make = Components.make
local Attribute = Protocol.Attribute
local Colors = Theme.Colors

local NameplateController = {}

NameplateController.MaxDistance = 60

local localPlayer = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local plates: { [Player]: BillboardGui } = {}
local connections: { [Player]: { RBXScriptConnection } } = {}

local DEFAULT_STRIP = Colors.Steel

-- Colors in a cosmetic are { r, g, b } in 0..255 (or 0..1)
local function toColor(value: any): Color3?
	if typeof(value) == "Color3" then
		return value
	end
	if typeof(value) ~= "table" then
		return nil
	end
	local r, g, b = value[1], value[2], value[3]
	if typeof(r) ~= "number" or typeof(g) ~= "number" or typeof(b) ~= "number" then
		return nil
	end
	if r > 1 or g > 1 or b > 1 then
		return Color3.fromRGB(r, g, b)
	end
	return Color3.new(r, g, b)
end

function NameplateController.stripColors(plateId: string?): { Color3 }
	local list = {}
	local item = if plateId and plateId ~= "" then Cosmetics.get(plateId) else nil
	if item and typeof(item.colors) == "table" then
		for _, entry in item.colors do
			local color = toColor(entry)
			if color then
				table.insert(list, color)
			end
		end
	end
	if #list == 0 then
		list[1] = DEFAULT_STRIP
	end
	return list
end

local function stroke(label: TextLabel)
	make("UIStroke", {
		Thickness = 2,
		Color = Colors.Ink,
		Transparency = 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = label,
	})
end

-- Builds the plate for one player (does not parent it)
function NameplateController.build(target: Player, adornee: Instance?): BillboardGui
	local title = target:GetAttribute(Attribute.Title)
	title = if typeof(title) == "string" then title else ""
	local plate = target:GetAttribute(Attribute.Plate)
	plate = if typeof(plate) == "string" then plate else ""

	local hasTitle = title ~= ""
	local gui = make("BillboardGui", {
		Name = "SNNameplate",
		Size = UDim2.fromOffset(280, if hasTitle then 64 else 40),
		StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0),
		MaxDistance = NameplateController.MaxDistance,
		LightInfluence = 0,
		AlwaysOnTop = false,
		Adornee = adornee,
	})
	local column = make("Frame", {
		Name = "Column",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 1),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- Each line sits in its own holder so its dark drop-shadow copy can sit just behind it
	local nameHolder = make("Frame", {
		Name = "NameHolder",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Parent = column,
	})
	local nameLabel = make("TextLabel", {
		Name = "Name",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		FontFace = Theme.Faces.ExtraBold,
		Text = target.DisplayName,
		TextColor3 = Colors.Text,
		TextSize = 22,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = nameHolder,
	})
	stroke(nameLabel)
	Components.dropShadow(nameLabel, 2, 0.4)

	if hasTitle then
		local titleHolder = make("Frame", {
			Name = "TitleHolder",
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			Parent = column,
		})
		local titleLabel = make("TextLabel", {
			Name = "Title",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			FontFace = Theme.Faces.Bold,
			Text = title,
			TextColor3 = Colors.Text,
			TextSize = 16,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = titleHolder,
		})
		stroke(titleLabel)
		Components.dropShadow(titleLabel, 1, 0.45)
	end

	local colors = NameplateController.stripColors(plate)
	local strip = make("Frame", {
		Name = "Strip",
		LayoutOrder = 3,
		Size = UDim2.fromOffset(112, 3),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = column,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for index, color in colors do
		make("Frame", {
			Name = "Band" .. index,
			LayoutOrder = index,
			Size = UDim2.new(1 / #colors, 0, 1, 0),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = strip,
		})
	end
	return gui
end

local function remove(target: Player)
	local gui = plates[target]
	if gui then
		gui:Destroy()
		plates[target] = nil
	end
end

local function refresh(target: Player)
	remove(target)
	local character = target.Character
	local head = character and character:FindFirstChild("Head")
	local container = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
	if not head or not container or target.Parent == nil then
		return
	end
	local gui = NameplateController.build(target, head)
	gui.Parent = container
	plates[target] = gui
end
NameplateController.refresh = refresh

local function watch(target: Player)
	local list = {}
	connections[target] = list
	local pending = false
	local function later()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			refresh(target)
		end)
	end
	table.insert(list, target.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 5)
		later()
	end))
	table.insert(list, target.CharacterRemoving:Connect(function()
		remove(target)
	end))
	for _, name in { Attribute.Title, Attribute.Plate } do
		table.insert(list, target:GetAttributeChangedSignal(name):Connect(later))
	end
	table.insert(list, target:GetPropertyChangedSignal("DisplayName"):Connect(later))
	if target.Character then
		later()
	end
end

-- Status moments --------------------------------------------------------------------------------

local MAX_LINE = 140
local MOMENT_SECONDS = 3.2
local momentQueue: { { headline: string, sub: string? } } = {}
local momentBusy = false
local momentGui: ScreenGui? = nil

-- One system line in the chat. Returns true when a chat channel took it.
function NameplateController.chatLine(text: any): boolean
	if typeof(text) ~= "string" or text == "" or #text > MAX_LINE then
		return false
	end
	local ok, shown = pcall(function()
		local service = game:GetService("TextChatService")
		local channels = service:FindFirstChild("TextChannels")
		local channel = channels and channels:FindFirstChild("RBXSystem")
		if channel and channel:IsA("TextChannel") then
			channel:DisplaySystemMessage(text)
			return true
		end
		return false
	end)
	return ok and shown == true
end

local function momentRoot(): ScreenGui?
	if momentGui and momentGui.Parent then
		return momentGui
	end
	local container = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
	if not container then
		return nil
	end
	momentGui = make("ScreenGui", { Name = "SNStatusMoment", ResetOnSpawn = false, DisplayOrder = 30, IgnoreGuiInset = true, Parent = container })
	return momentGui
end

local function playMoment(entry: { headline: string, sub: string? }, done: () -> ())
	local root = momentRoot()
	if not root then
		done()
		return
	end
	local holder = make("Frame", {
		Name = "Moment",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.17),
		Size = UDim2.fromOffset(720, 100),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local headline = Components.text({
		Name = "Headline", Text = entry.headline, Style = "display", TextSize = 34, AlignX = "Center",
		Size = UDim2.new(1, 0, 0, 46), TextTransparency = 1, Parent = holder,
	})
	make("UIStroke", { Thickness = 1.5, Color = Colors.Ink, Transparency = 0.35, Parent = headline })
	local dash = make("Frame", {
		Name = "Dash", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 54), Size = UDim2.fromOffset(52, 3),
		BackgroundColor3 = Colors.Accent, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = holder,
	})
	local sub = if entry.sub and entry.sub ~= "" then Components.text({
		Name = "Sub", Text = entry.sub, Style = "body", Color = Colors.Text, AlignX = "Center",
		Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 28), TextTransparency = 1, Parent = holder,
	}) else nil
	if sub then
		make("UIStroke", { Thickness = 1.5, Color = Colors.Ink, Transparency = 0.35, Parent = sub })
	end
	local fadeIn = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeOut = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(headline, fadeIn, { TextTransparency = 0 }):Play()
	TweenService:Create(dash, fadeIn, { BackgroundTransparency = 0 }):Play()
	if sub then
		TweenService:Create(sub, fadeIn, { TextTransparency = 0 }):Play()
	end
	task.delay(MOMENT_SECONDS, function()
		TweenService:Create(headline, fadeOut, { TextTransparency = 1 }):Play()
		TweenService:Create(dash, fadeOut, { BackgroundTransparency = 1 }):Play()
		if sub then
			TweenService:Create(sub, fadeOut, { TextTransparency = 1 }):Play()
		end
		task.delay(0.7, function()
			holder:Destroy()
			done()
		end)
	end)
end

local function nextMoment()
	local entry = table.remove(momentQueue, 1)
	if not entry then
		momentBusy = false
		return
	end
	momentBusy = true
	playMoment(entry, nextMoment)
end

-- The earner's own moment; at most three wait in line
function NameplateController.showMoment(headline: any, sub: any?): boolean
	if typeof(headline) ~= "string" or headline == "" or #headline > 60 then
		return false
	end
	if #momentQueue >= 3 then
		return false
	end
	table.insert(momentQueue, { headline = headline, sub = if typeof(sub) == "string" and #sub <= MAX_LINE then sub else nil })
	if not momentBusy then
		nextMoment()
	end
	return true
end

function NameplateController:Init(controllers)
	self.controllers = controllers
end

function NameplateController:Start()
	for _, target in Players:GetPlayers() do
		watch(target)
	end
	Players.PlayerAdded:Connect(watch)
	local events = Remotes:WaitForChild("StatusEvent", 10)
	if events then
		(events :: RemoteEvent).OnClientEvent:Connect(function(kind, payload)
			if typeof(payload) ~= "table" then
				return
			end
			if kind == Protocol.StatusEvent.Moment then
				NameplateController.chatLine(payload.text)
			elseif kind == Protocol.StatusEvent.Earned then
				NameplateController.showMoment(payload.headline, payload.sub)
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(target)
		remove(target)
		for _, connection in connections[target] or {} do
			connection:Disconnect()
		end
		connections[target] = nil
	end)
end

-- For tests: the plate currently drawn for a player
function NameplateController.plateOf(target: Player): BillboardGui?
	return plates[target]
end

return NameplateController
