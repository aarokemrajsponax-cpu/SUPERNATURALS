-- ASK JEFFERY (Shell window "AskJeffery", opened from Jeffery's prompt in the hall and from the
-- Ask Jeffery button in How to Play). A player types a question and Jeffery answers in his voice.
--
-- The server (JefferyChatService) does all the work: it answers from the offline knowledge base and,
-- only when the owner turned it on, from an external AI. This window only sends text and shows text.
-- Nothing a player types or Jeffery answers can start a game action. Plain text only (no rich text).
-- If the server does not answer in time, the shared knowledge base answers here instead, so the
-- panel keeps working. Messages are kept for the session so reopening the window keeps the talk.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local ChatConfig = require(ReplicatedStorage.Shared.Config.JefferyChat)
local Knowledge = require(ReplicatedStorage.Shared.Config.JefferyKnowledge)
local Components = require(script.Parent.Components)
local Shell = require(script.Parent.Shell)
local Theme = require(script.Parent.Theme)

local make = Components.make
local Colors = Theme.Colors

local AskJeffery = {}

AskJeffery.Config = {
	-- Seconds to wait for the server before the local knowledge base answers
	AnswerTimeout = 8,
}

type Message = { from: string, text: string, source: string? }

local messages: { Message } = {}
local nextId = 0
local waitingId: number? = nil
local lockedUntil = 0
local ui: { [string]: any }? = nil
local remote: RemoteEvent? = nil

local GREETING = "Hi, I am Jeffery. Ask me about controls, fighters, phases, places, the shop or gifts. I can only talk, so I cannot give out items."

local function addBubble(message: Message)
	if not ui then
		return
	end
	local list = ui.list
	local mine = message.from == "you"
	local row = make("Frame", {
		Name = "Msg_" .. (#list:GetChildren()), LayoutOrder = #list:GetChildren(),
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = list,
	})
	local bubble = make("Frame", {
		Name = "Bubble", AnchorPoint = Vector2.new(if mine then 1 else 0, 0), Position = UDim2.fromScale(if mine then 1 else 0, 0),
		Size = UDim2.new(0.84, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = if mine then Colors.PanelHover else Colors.PanelLight, BackgroundTransparency = 0.1,
		BorderSizePixel = 0, Parent = row,
	}, { Components.corner(), Components.stroke(if mine then Colors.Stroke else Colors.Cyan, 1, 0.6), Components.padding(10, 12, 10, 12) })
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bubble })
	Components.text({
		Name = "Who", Text = if mine then "You" else "Jeffery", Style = "Caption", Weight = "Bold",
		Color = if mine then Colors.TextDim else Colors.Cyan, LayoutOrder = 1, Parent = bubble,
	})
	local body = Components.text({
		Name = "Body", Text = message.text, Style = "Body", Wrap = true, LayoutOrder = 2, Parent = bubble,
	})
	body.RichText = false
	local scroll = ui.scroll
	task.defer(function()
		if scroll.Parent then
			scroll.CanvasPosition = Vector2.new(0, 1e6)
		end
	end)
end

local function setStatus(text: string)
	if ui then
		ui.status.Text = text
	end
end

local function setBusy(busy: boolean)
	if not ui then
		return
	end
	Components.setDisabled(ui.send, busy, if busy then "Wait for Jeffery" else nil)
end

local function push(message: Message)
	table.insert(messages, message)
	while #messages > 40 do
		table.remove(messages, 1)
	end
	addBubble(message)
end

local function finishAnswer(text: string, source: string?)
	waitingId = nil
	setBusy(false)
	setStatus("Jeffery answers questions about the game. He cannot give items or Money.")
	push({ from = "jeffery", text = text, source = source })
end

-- Sends a question. Returns false when nothing was sent (empty, too long or still waiting).
function AskJeffery.ask(text: string): boolean
	local limit = ChatConfig.Limits.MaxInput
	text = string.gsub(text, "^%s*(.-)%s*$", "%1")
	if text == "" then
		setStatus(ChatConfig.Text.Empty)
		return false
	end
	if (utf8.len(text) or #text) > limit then
		setStatus(ChatConfig.Text.TooLong)
		return false
	end
	if waitingId then
		setStatus(ChatConfig.Text.Busy)
		return false
	end
	local left = lockedUntil - os.clock()
	if left > 0 then
		setStatus(string.format(ChatConfig.Text.Wait, math.ceil(left)))
		return false
	end
	nextId += 1
	local id = nextId
	waitingId = id
	lockedUntil = os.clock() + ChatConfig.Limits.CooldownSeconds
	push({ from = "you", text = text })
	setBusy(true)
	setStatus("Jeffery is thinking...")
	if ui then
		ui.box.Text = ""
	end
	if remote then
		remote:FireServer(Protocol.JefferyChat.Ask, text, id)
	end
	-- The knowledge base is shared: if the server stays quiet, answer from it here
	task.delay(AskJeffery.Config.AnswerTimeout, function()
		if waitingId == id then
			local entry = Knowledge.match(text)
			finishAnswer(if entry then entry.answer else ChatConfig.Text.Unknown, "knowledge")
		end
	end)
	return true
end

function AskJeffery.onAnswer(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.text) ~= "string" then
		return
	end
	local id = payload.id
	if waitingId and (id == nil or id == waitingId) then
		-- A server refusal (cooldown, too long) does not start our own cooldown
		if payload.reason == "cooldown" or payload.reason == "busy" or payload.reason == "too_long" or payload.reason == "empty" then
			lockedUntil = os.clock() + (tonumber(payload.retryIn) or 0)
		end
		finishAnswer(payload.text, if typeof(payload.source) == "string" then payload.source else nil)
	end
end

function AskJeffery.messages(): { Message }
	return messages
end

local function howToPlay()
	Shell.open("Learn")
end

local function build(body: Frame)
	local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local compact = view.Y < 500

	local header = make("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, Parent = body })
	local status = Components.text({
		Name = "AskStatus", Text = "Jeffery answers questions about the game. He cannot give items or Money.",
		Style = "Caption", Color = Colors.TextDim, Wrap = true, Lines = 2,
		Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, -176, 0, 44), Parent = header,
	})
	Components.button("How to Play", {
		Name = "HowToPlayButton", Variant = "Secondary", KeepCase = true, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(164, 44), Parent = header,
	}, howToPlay)

	local inputHeight = 48
	local chipsHeight = if compact then 0 else 48
	local reserved = 52 + inputHeight + 8 + (if compact then 0 else chipsHeight + 8)

	local scroll = Components.scroll({
		Name = "AskMessages", Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -reserved), Padding = 2, Parent = body,
	})
	local list = make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })

	local chips = make("ScrollingFrame", {
		Name = "AskChips", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -(inputHeight + 8)),
		Size = UDim2.new(1, 0, 0, chipsHeight), BackgroundTransparency = 1, BorderSizePixel = 0,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0, Visible = not compact, Parent = body,
	}, { make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
	}) })
	for order, question in Knowledge.Suggestions do
		Components.button(question, {
			Name = "Suggest_" .. order, Variant = "Secondary", KeepCase = true, LayoutOrder = order,
			Size = UDim2.fromOffset(Components.textWidth(question, 16) * 1.25 + 40, 44), Parent = chips,
		}, function()
			AskJeffery.ask(question)
		end)
	end

	local inputRow = make("Frame", {
		Name = "InputRow", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, inputHeight), BackgroundTransparency = 1, Parent = body,
	})
	local box = make("TextBox", {
		Name = "AskInput", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, -124, 1, 0),
		BackgroundColor3 = Colors.Background, TextColor3 = Colors.Text, PlaceholderText = "Type your question for Jeffery",
		PlaceholderColor3 = Colors.TextDim, ClearTextOnFocus = false, Text = "", Font = Theme.Fonts.Body, TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ClipsDescendants = true,
		Parent = inputRow,
	}, { Components.corner(Theme.SmallCorner), Components.stroke(Colors.Cyan, 1, 0.5), Components.padding(0, 12, 0, 12) })
	local send = Components.button("Send", {
		Name = "AskSend", Variant = "Primary", KeepCase = true, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(116, inputHeight), Parent = inputRow,
	}, function()
		AskJeffery.ask(box.Text)
	end)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			AskJeffery.ask(box.Text)
		end
	end)
	-- Never more than the allowed number of characters
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local limit = ChatConfig.Limits.MaxInput
		if (utf8.len(box.Text) or #box.Text) > limit then
			local cut = utf8.offset(box.Text, limit + 1)
			box.Text = string.sub(box.Text, 1, (cut or (#box.Text + 1)) - 1)
		end
	end)

	ui = { list = scroll, scroll = scroll, box = box, send = send, status = status, chips = chips }
	local _ = list
	if #messages == 0 then
		table.insert(messages, { from = "jeffery", text = GREETING })
	end
	for _, message in messages do
		addBubble(message)
	end
	setBusy(waitingId ~= nil)

	return {
		onOpen = function()
			if ui then
				ui.scroll.CanvasPosition = Vector2.new(0, 1e6)
			end
		end,
	}
end

function AskJeffery.register()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	remote = folder and (folder:FindFirstChild("JefferyChat") or folder:WaitForChild("JefferyChat", 5)) or nil
	if remote and not AskJeffery._connected then
		AskJeffery._connected = true
		(remote :: RemoteEvent).OnClientEvent:Connect(function(kind, payload)
			if kind == Protocol.JefferyChat.Answer then
				AskJeffery.onAnswer(payload)
			end
		end)
	end
	Shell.registerWindow("AskJeffery", {
		title = "Ask Jeffery",
		label = "ASK",
		icon = "learn",
		order = 7,
		nav = false,
		build = build,
	})
end

return AskJeffery
