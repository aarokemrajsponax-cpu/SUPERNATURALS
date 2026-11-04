-- Client smoke test for Jeffery's dialogue panel, the How to Play window and the hint toast:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke_learn.luau build/game.rbxl
-- The dialogue panel types, continues, skips, shows progress dots and choices; every How to Play
-- section and device tab shows the right key caps; the tour stays in sync (the client says ready
-- once, a step's lines come before the server is told to watch, a replaced line fires nothing,
-- Skip tour exits instead of advancing, the camera and the floor arrows start after the lines, a
-- window opening over a line pauses it); Jeffery stays at his post; the finish offers "tell me
-- more" and then the welcome gift; the Ask Jeffery panel sends, shows answers and falls back to
-- the shared notes; a hint waits while combat is active and shows when it is quiet; hints off
-- drops them; at 1280x720 and 667x375 with auditLayout.

local process = require("@lune/process")
local Client = require("./smoke/Client")

local t = Client.load(process.args[1])
local task, Engine, roblox = t.task, t.Engine, t.roblox

local Tutorial = t.shared("Config.Tutorial")
local Protocol = t.shared("Protocol")
local LearnWindow = t.client("UI.LearnWindow")
local Settings = t.client("Settings")
local Input = t.client("Controllers.InputController")

local ui = t.startUI()
local Shell, gui = ui.Shell, ui.gui
local fakeInput = { Bindings = Input.Bindings, device = function() return "keyboard" end }
local function Components_isDisabled(button)
	return t.client("UI.Components").isDisabled(button)
end

-- A stand-in Jeffery model in the world, built by the real server builder
local model
t.check("Jeffery builds from parts with a face, nameplate and insignia", function()
	local build = t.world.require(t.world.find("ServerScriptService.Server.World.Jeffery"))
	model = build.model()
	assert(model.PrimaryPart, "primary part")
	for _, name in { "Head", "ArmL", "ArmR", "Nameplate", "ChestPanel" } do
		assert(model:FindFirstChild(name, true), name)
	end
	local gui3 = model.Head.Screen.Face
	for _, face in Tutorial.FaceNames do
		build.applyFace(gui3, face)
		assert(gui3:GetAttribute("Face") == face, face)
	end
	local plate = model.Nameplate.SurfaceGui.TextLabel
	assert(plate.Text == "JEFFERY", "nameplate text")
	model.Parent = t.game:GetService("Workspace")
end)

local Controller = t.client("Controllers.JefferyController")
Controller.Config.ReadyWait = 0.5
Controller:Init({ InputController = fakeInput })
Controller:Start()
task.wait(0.2)

local function panelFrame()
	return t.findNamed(gui, "JefferyDialogue")
end

for _, size in { { 1280, 720 }, { 667, 375 } } do
	t.setScreen(size[1], size[2])
	local label = `{size[1]}x{size[2]}`

	t.check("dialogue panel types, continues and ends " .. label, function()
		local done, skipped = false, false
		Controller.panel.say({ "First line is here.", "Second line follows.", "Third." }, {
			face = "excited", onDone = function() done = true end, onSkip = function() skipped = true end,
		})
		assert(panelFrame().Visible, "panel visible")
		local s = Controller.panel.state()
		assert(s.typing and s.index == 1 and s.total == 3, "typing line 1")
		t.auditLayout(panelFrame(), "dialogue " .. label)
		local dots = 0
		for _, d in t.findNamed(panelFrame(), "Dots"):GetChildren() do
			if d:IsA("Frame") then dots += 1 end
		end
		assert(dots == 3, "three progress dots, got " .. dots)
		t.press(t.findNamed(panelFrame(), "Continue"))
		assert(not Controller.panel.state().typing, "first press finishes the line")
		assert(t.findNamed(panelFrame(), "Line").MaxVisibleGraphemes == -1, "full text shown")
		t.press(t.findNamed(panelFrame(), "Continue"))
		assert(Controller.panel.state().index == 2, "second line")
		task.wait(1.5)
		assert(not Controller.panel.state().typing, "typewriter finishes by itself")
		for _ = 1, 6 do
			Controller.panel.press()
		end
		assert(done and not skipped and not panelFrame().Visible, "ended with onDone")
		Controller.panel.say({ "Skip me." }, { onSkip = function() skipped = true end })
		t.press(t.findNamed(panelFrame(), "Skip"))
		assert(skipped and not panelFrame().Visible, "skip works")
	end)

	t.check("every How to Play section and device tab " .. label, function()
		Shell.open("Learn")
		task.wait(0.1)
		local window = t.findNamed(gui, "Window_Learn")
		assert(window, "window")
		for _, device in { "keyboard", "gamepad", "touch" } do
			t.press(t.findNamed(window, "Segment_" .. device) or t.findNamed(window, device) or t.findText(window, ({ keyboard = "Keyboard", gamepad = "Gamepad", touch = "Touch" })[device]))
			task.wait(0.05)
			for _, section in LearnWindow.Sections do
				local card = t.findNamed(window, "Section_" .. section.id)
				assert(card, "section " .. section.id)
				assert(t.findNamed(card, "Body").Text ~= "", "body " .. section.id)
				if #section.keys > 0 then
					assert(t.findNamed(card, "Controls"), "controls " .. section.id)
					assert(#t.findNamed(card, "Controls"):GetChildren() >= #section.keys, "keys " .. section.id .. " " .. device)
				end
			end
			t.auditLayout(window, `learn {device} {label}`)
		end
		assert(t.findNamed(window, "ReplayButton") and t.findNamed(window, "AskButton"), "buttons")
		-- Gamepad caps come from the bindings
		local text, name = LearnWindow.keyFor("SNBlock", "gamepad")
		assert(text == "L1" and name == "Block", "gamepad block " .. tostring(text))
		assert(LearnWindow.keyFor("SNSprint", "touch") == "Run", "touch sprint label")
		Shell.close()
	end)
end

t.check("Replay tutorial reaches the server; Ask Jeffery opens the chat panel", function()
	Shell.open("Learn")
	task.wait(0.1)
	local window = t.findNamed(gui, "Window_Learn")
	local mark = #Engine.sent
	t.press(t.findNamed(window, "ReplayButton"))
	task.wait(0.1)
	local sent = t.sentSince(mark, "ProgressRequest", Protocol.ProgressAction.TutorialReplay)
	assert(#sent >= 1, "replay request sent")
	Shell.open("Learn")
	task.wait(0.1)
	t.press(t.findNamed(t.findNamed(gui, "Window_Learn"), "AskButton"))
	task.wait(0.2)
	assert(Shell.isOpen("AskJeffery") and t.findNamed(gui, "Window_AskJeffery"), "the Ask Jeffery window opened from How to Play")
	Shell.close()
end)

-- The tour in sync --------------------------------------------------------------------------------------
local function press(times)
	for _ = 1, times or 8 do
		if Controller.panel.isOpen() then
			Controller.panel.press()
		end
	end
end
local function sentOf(mark, action, argument)
	local found = {}
	for _, entry in t.sentSince(mark, "ProgressRequest", action) do
		if argument == nil or entry.args[2] == argument then
			table.insert(found, entry)
		end
	end
	return found
end
local function tutorial(payload)
	payload.done = payload.done or {}
	t.fire("DataEvent", "Tutorial", payload)
end

t.check("the client says ready once, after Jeffery and the character exist", function()
	local ready = 0
	for _, entry in t.sentSince(0, "ProgressRequest", Protocol.ProgressAction.TutorialReady) do
		ready += 1
	end
	assert(ready == 1, "one TutorialReady, got " .. ready)
end)

t.check("Jeffery stays at his post: no companion, he turns to face the player but never moves", function()
	local home = model:GetPivot().Position
	tutorial({ active = true, index = 2, total = 8, step = "move", event = "step" })
	task.wait(1.4)
	for _ = 1, 20 do
		task.wait(0.1)
	end
	assert(not t.game:GetService("Workspace"):FindFirstChild("JefferyCompanion"), "no companion copy")
	assert((model:GetPivot().Position - home).Magnitude < 1, "Jeffery did not move from his post")
	assert(Controller.companion == nil and Controller._setCompanion == nil, "the companion code is gone")
	Controller.panel.hide()
	tutorial({ active = false, event = "exit" })
	task.wait(0.1)
end)

t.check("a step waits for its condition: the line first, the server told when it ends, then the goal", function()
	local mark = #Engine.sent
	tutorial({ active = true, index = 5, total = 8, step = "attack", event = "step" })
	local card = t.findNamed(gui, "TutorialCard")
	assert(card.Visible and t.findNamed(card, "Count").Text == "5 / 8", "card shows the step")
	assert(t.findNamed(card, "Key_SNLight"), "attack key cap")
	assert(t.findNamed(card, "Eyebrow").Text ~= "" and not Controller:getState().armed, "listening, not armed")
	assert(not panelFrame().Visible, "Jeffery waits a beat after the last step before the next line")
	task.wait(1.4)
	assert(panelFrame().Visible, "the lines are shown")
	assert(#sentOf(mark, Protocol.ProgressAction.TutorialLine) == 0, "the server is not told before the lines end")
	assert(#t.sentSince(mark, "ProgressRequest", Protocol.ProgressAction.TutorialAck) == 0, "no ack for an action step")
	press(10)
	assert(not panelFrame().Visible, "lines over")
	local lines = sentOf(mark, Protocol.ProgressAction.TutorialLine, "attack")
	assert(#lines == 1, "the server was told the lines ended, once")
	assert(Controller:getState().armed, "armed")
	t.auditLayout(card, "tutorial card")
	-- A new step replaces a line silently: no skip, no exit, no ack from the old line
	tutorial({ active = true, index = 6, total = 8, step = "block", event = "step" })
	task.wait(1.4)
	assert(panelFrame().Visible, "block lines shown")
	local exits = #sentOf(mark, Protocol.ProgressAction.TutorialExit)
	tutorial({ active = true, index = 7, total = 8, step = "dodge", event = "step" })
	task.wait(1.4)
	assert(#sentOf(mark, Protocol.ProgressAction.TutorialExit) == exits, "a replaced line fires no skip")
	assert(#sentOf(mark, Protocol.ProgressAction.TutorialLine, "block") == 0, "an unfinished line is never reported as finished")
	Controller.panel.hide()
	assert(#sentOf(mark, Protocol.ProgressAction.TutorialLine, "dodge") == 0, "hide() is silent too")
	tutorial({ active = false, event = "exit" })
	task.wait(0.1)
end)

t.check("an action step's panel closes by itself after the line so the player can act", function()
	local mark = #Engine.sent
	tutorial({ active = true, index = 7, total = 8, step = "dodge", event = "step" })
	task.wait(1.4)
	assert(panelFrame().Visible, "line shown")
	task.wait(3)
	Controller.panel.finishLine()
	task.wait(Tutorial.AutoCloseSeconds + 0.6)
	assert(not panelFrame().Visible, "closed itself")
	assert(#sentOf(mark, Protocol.ProgressAction.TutorialLine, "dodge") == 1, "and told the server")
	tutorial({ active = false, event = "exit" })
	task.wait(0.1)
end)

t.check("the welcome step: CONTINUE is sent only when the lines end; Skip tour leaves the tour (no ack)", function()
	local mark = #Engine.sent
	tutorial({ active = true, index = 1, total = 8, step = "welcome", event = "start" })
	task.wait(0.6)
	assert(panelFrame().Visible, "welcome shown")
	assert(#sentOf(mark, Protocol.ProgressAction.TutorialAck) == 0, "no ack while talking")
	assert(t.findNamed(panelFrame(), "Skip").Text == "Skip tour", "the button says what it does")
	press(10)
	assert(#sentOf(mark, Protocol.ProgressAction.TutorialAck, "welcome") == 1, "ack at the end of the lines")
	tutorial({ active = true, index = 1, total = 8, step = "welcome", event = "start" })
	task.wait(0.6)
	local acks = #sentOf(mark, Protocol.ProgressAction.TutorialAck)
	t.press(t.findNamed(panelFrame(), "Skip"))
	assert(#sentOf(mark, Protocol.ProgressAction.TutorialAck) == acks, "skipping does not advance a step")
	assert(#sentOf(mark, Protocol.ProgressAction.TutorialExit) == 1, "skipping asks to exit the tour")
	tutorial({ active = false, event = "exit" })
	task.wait(0.1)
end)

t.check("a window opening over a line puts the line away and says it again afterwards", function()
	tutorial({ active = true, index = 2, total = 8, step = "move", event = "step" })
	task.wait(1.4)
	assert(panelFrame().Visible, "line shown")
	Shell.open("Learn")
	task.wait(1.0)
	assert(not panelFrame().Visible, "no line under a window")
	Shell.close()
	task.wait(1.0)
	assert(panelFrame().Visible, "the line returns")
	Controller.panel.hide()
	tutorial({ active = false, event = "exit" })
	task.wait(0.1)
end)

t.check("the camera step watches the camera only after the lines; the guide appears only then", function()
	local mark = #Engine.sent
	local workspace = t.game:GetService("Workspace")
	local camera = workspace.CurrentCamera
	tutorial({ active = true, index = 3, total = 8, step = "camera", event = "step" })
	task.wait(1.4)
	camera.CFrame = camera.CFrame * Engine.CFrame.Angles(0, math.rad(90), 0)
	task.wait(0.3)
	assert(#sentOf(mark, Protocol.ProgressAction.TutorialAck) == 0, "turning the camera during the lines counts for nothing")
	press(10)
	task.wait(0.2)
	assert(#sentOf(mark, Protocol.ProgressAction.TutorialAck) == 0, "not yet: it measures from the end of the lines")
	camera.CFrame = camera.CFrame * Engine.CFrame.Angles(0, math.rad(60), 0)
	task.wait(0.8)
	assert(#sentOf(mark, Protocol.ProgressAction.TutorialAck, "camera") == 1, "turned: reported once")
	task.wait(0.3)
	assert(#sentOf(mark, Protocol.ProgressAction.TutorialAck, "camera") == 1, "and only once")
	tutorial({ active = false, event = "exit" })
	task.wait(0.1)
end)

t.check("floor arrows and a light beam point to the door only once the lines are over", function()
	local workspace = t.game:GetService("Workspace")
	local guides = roblox.Instance.new("Folder")
	guides.Name = "Guides"
	local list = roblox.Instance.new("Folder")
	list.Name = "Training"
	list.Parent = guides
	for index, x in { 10, 40, 80 } do
		local part = roblox.Instance.new("Part")
		part.Name = tostring(index)
		part.Position = roblox.Vector3.new(x, 0.2, 0)
		part.Parent = list
	end
	guides.Parent = workspace
	tutorial({ active = true, index = 4, total = 8, step = "training", event = "step" })
	task.wait(1.4)
	assert(panelFrame().Visible and not workspace:FindFirstChild("JefferyGuide"), "no pointer while Jeffery is talking")
	press(10)
	task.wait(0.3)
	local guide = workspace:FindFirstChild("JefferyGuide")
	assert(guide and guide:FindFirstChild("Beam"), "the beam appears when the lines end")
	tutorial({ active = true, index = 5, total = 8, step = "attack", event = "step" })
	assert(not workspace:FindFirstChild("JefferyGuide"), "the pointer goes when the step is done")
	tutorial({ active = false, event = "exit" })
	Controller.panel.hide()
	guides:Destroy()
	task.wait(0.1)
end)

for _, size in { { 1280, 720 }, { 667, 375 } } do
	t.setScreen(size[1], size[2])
	t.check(`the finish: choices, the optional more talk, then the welcome gift {size[1]}x{size[2]}`, function()
		local mark = #Engine.sent
		tutorial({ active = false, event = "complete", rewarded = true, gift = { money = 250, title = "Recruit", founding = true } })
		task.wait(0.4)
		assert(panelFrame().Visible, "outro shown")
		assert(not t.findNamed(gui, "WelcomeGift"), "the gift waits for the talk")
		for _ = 1, 4 do
			Controller.panel.finishLine()
			if not Controller.panel.state().choices then
				Controller.panel.press()
			end
		end
		task.wait(0.3)
		local more, gift = t.findNamed(panelFrame(), "Choice_more"), t.findNamed(panelFrame(), "Choice_gift")
		assert(more and gift and Controller.panel.state().choices, "two choices on the last line")
		assert(not t.findNamed(panelFrame(), "Continue").Visible, "no Continue next to the choices")
		t.auditLayout(panelFrame(), "outro choices")
		-- Tell me more plays the topics; "That is enough" goes to the gift
		t.press(more)
		task.wait(0.4)
		assert(panelFrame().Visible and t.findNamed(panelFrame(), "Skip").Text == "That is enough", "more topics")
		assert(not t.findNamed(gui, "WelcomeGift"), "no gift in the middle of the talk")
		t.press(t.findNamed(panelFrame(), "Skip"))
		task.wait(0.3)
		local card = t.findNamed(gui, "WelcomeGift")
		assert(card and not panelFrame().Visible, "the gift moment replaces the panel")
		assert(t.findNamed(card, "Title").Text == "WELCOME GIFT", "title")
		local labels = {}
		for _, item in t.findNamed(card, "Items"):GetChildren() do
			if item:IsA("Frame") then
				table.insert(labels, t.findNamed(item, "Label").Text)
			end
		end
		assert(table.concat(labels, "|") == "Recruit title|250 Money|Founding Recruit title", "what was given: " .. table.concat(labels, "|"))
		assert(t.findNamed(card, "Like").Text == "If you enjoy SUPERNATURALS, a like on the game page helps us grow.", "the voluntary line")
		assert(not string.find(string.lower(t.findNamed(card, "Intro").Text), "like"), "the gift itself does not mention liking")
		t.auditLayout(card, "gift card")
		t.press(t.findNamed(card, "GiftDone"))
		assert(not t.findNamed(gui, "WelcomeGift"), "closed")
		assert(#t.sentSince(mark, "ProgressRequest", Protocol.ProgressAction.TutorialExit) == 0, "nothing was sent to the server")
	end)
end

t.check("a replayed tour ends without a gift", function()
	tutorial({ active = false, event = "complete", rewarded = false, gift = { money = 250, title = "Recruit", founding = false } })
	task.wait(0.4)
	for _ = 1, 3 do
		Controller.panel.finishLine()
		if not Controller.panel.state().choices then
			Controller.panel.press()
		end
	end
	local done = t.findNamed(panelFrame(), "Choice_gift")
	assert(done and t.findNamed(done, "Label") == nil and done.Text == "Done", "second choice reads Done")
	t.press(done)
	task.wait(0.3)
	assert(not t.findNamed(gui, "WelcomeGift"), "no gift card on a replay")
	assert(panelFrame().Visible, "a closing line instead")
	Controller.panel.hide()
end)

-- Ask Jeffery -------------------------------------------------------------------------------------------
local Ask = t.client("UI.AskJefferyWindow")
for _, size in { { 1280, 720 }, { 667, 375 } } do
	t.setScreen(size[1], size[2])
	local label = `{size[1]}x{size[2]}`
	t.check("Ask Jeffery: type, send, get an answer; limits and fallbacks " .. label, function()
		task.wait(6.2)
		Controller:openChat()
		task.wait(0.2)
		local window = t.findNamed(gui, "Window_AskJeffery")
		assert(window and Shell.isOpen("AskJeffery"), "window open")
		local box, send = t.findNamed(window, "AskInput"), t.findNamed(window, "AskSend")
		assert(box and send and t.findNamed(window, "AskMessages") and t.findNamed(window, "HowToPlayButton"), "parts")
		t.auditLayout(window, "ask " .. label)
		local mark = #Engine.sent
		box.Text = string.rep("x", 260)
		Engine.signalOf(box, "Property:Text"):Fire()
		task.wait(0.1)
		assert(#box.Text == 200, "input is cut at 200 characters: " .. #box.Text)
		box.Text = "How do I dodge?"
		t.press(send)
		task.wait(0.2)
		local asked = t.sentSince(mark, "JefferyChat", Protocol.JefferyChat.Ask)
		assert(#asked == 1 and asked[1].args[2] == "How do I dodge?" and type(asked[1].args[3]) == "number", "question sent with an id")
		assert(Components_isDisabled(send), "Send waits while Jeffery thinks")
		t.press(send)
		assert(#t.sentSince(mark, "JefferyChat", Protocol.JefferyChat.Ask) == 1, "a second send while waiting does nothing")
		t.fire("JefferyChat", "Answer", { id = asked[1].args[3], ok = true, text = "Press Q to dodge.", source = "knowledge" })
		task.wait(0.2)
		assert(not Components_isDisabled(send), "ready again")
		local texts = {}
		for _, item in t.findNamed(window, "AskMessages"):GetDescendants() do
			if item.Name == "Body" then
				table.insert(texts, item.Text)
			end
		end
		assert(texts[#texts] == "Press Q to dodge." and texts[#texts - 1] == "How do I dodge?", "both bubbles shown")
		-- Plain text only
		local last
		for _, item in t.findNamed(window, "AskMessages"):GetDescendants() do
			if item.Name == "Body" then
				last = item
			end
		end
		assert(last.RichText == false, "no rich text")
		t.auditLayout(window, "ask after talk " .. label)
		Shell.close()
	end)
end

t.check("Ask Jeffery: a quiet server gets the local notes; suggestions send; empty and long are refused", function()
	Ask.Config.AnswerTimeout = 0.3
	Controller:openChat()
	task.wait(0.2)
	local window = t.findNamed(gui, "Window_AskJeffery")
	local mark = #Engine.sent
	t.setScreen(1280, 720)
	Shell.close()
	Controller:openChat()
	task.wait(0.2)
	window = t.findNamed(gui, "Window_AskJeffery")
	task.wait(6.2)
	local chip = t.findNamed(window, "Suggest_2")
	assert(chip, "suggestion chips on a normal screen")
	t.press(chip)
	task.wait(0.2)
	assert(#t.sentSince(mark, "JefferyChat", Protocol.JefferyChat.Ask) == 1, "the chip sends its question")
	task.wait(0.8)
	local messages = Ask.messages()
	assert(messages[#messages].from == "jeffery" and string.find(messages[#messages].text, "meter", 1, true), "no server answer: the shared notes answered (phases)")
	task.wait(6.2)
	local sent = #t.sentSince(mark, "JefferyChat", Protocol.JefferyChat.Ask)
	assert(Ask.ask("   ") == false and Ask.ask(string.rep("y", 201)) == false, "empty and too long are not sent")
	assert(#t.sentSince(mark, "JefferyChat", Protocol.JefferyChat.Ask) == sent, "nothing went out")
	Shell.close()
end)

t.check("Ask Jeffery: Jeffery's world prompt opens the panel and How to Play is one tap away", function()
	local builder = t.world.require(t.world.find("ServerScriptService.Server.World.Jeffery"))
	local post = builder.build(roblox.Instance.new("Folder"))
	local prompt = post:FindFirstChildWhichIsA("ProximityPrompt", true)
	assert(prompt and prompt:GetAttribute("Action") == "Jeffery:Ask" and prompt.ActionText == "Ask Jeffery", "the world prompt asks")
	Controller:openChat()
	task.wait(0.2)
	t.press(t.findNamed(t.findNamed(gui, "Window_AskJeffery"), "HowToPlayButton"))
	task.wait(0.2)
	assert(Shell.isOpen("Learn"), "How to Play opened")
	Shell.close()
end)

for _, size in { { 1280, 720 }, { 667, 375 } } do
	t.setScreen(size[1], size[2])
	t.check(`hint toast waits for quiet combat, honours Hints off {size[1]}x{size[2]}`, function()
		Controller.panel.hide()
		-- Combat just happened to the local fighter: the hint must wait
		local character = t.world.localPlayer.Character
		if character then
			t.fire("CombatEvent", "Hit", { attacker = character, victim = character })
		end
		t.fire("DataEvent", "Hint", { id = "grab_suffered", text = Tutorial.Hints.grab_suffered.text, face = "warning" })
		task.wait(0.9)
		local shown = t.findNamed(gui, "JefferyHint")
		if character then
			assert(not shown, "hint held back during combat")
			Controller.Config.QuietSeconds = 0
		end
		task.wait(0.9)
		shown = t.findNamed(gui, "JefferyHint")
		assert(shown, "hint shown when quiet")
		assert(t.findNamed(shown, "Text").Text == Tutorial.Hints.grab_suffered.text, "text")
		t.auditLayout(shown, "hint")
		Settings.set("hints", false)
		t.fire("DataEvent", "Hint", { id = "x", text = "Dropped.", face = "happy" })
		task.wait(0.9)
		assert(#Controller._queue() == 0, "nothing queued with hints off")
		Settings.set("hints", true)
	end)
end

t.finish()
