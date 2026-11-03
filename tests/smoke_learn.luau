-- Client smoke test for Jeffery's dialogue panel, the How to Play window and the hint toast:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke_learn.luau build/game.rbxl
-- The dialogue panel types, continues, skips and shows progress dots; every How to Play
-- section and device tab shows the right key caps; the Replay buttons reach Jeffery; a hint
-- waits while combat is active and shows when it is quiet; hints off drops them; all at
-- 1280x720 and 667x375 with auditLayout.

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
		assert(t.findNamed(window, "ReplayButton") and t.findNamed(window, "TalkButton"), "buttons")
		-- Gamepad caps come from the bindings
		local text, name = LearnWindow.keyFor("SNBlock", "gamepad")
		assert(text == "L1" and name == "Block", "gamepad block " .. tostring(text))
		assert(LearnWindow.keyFor("SNSprint", "touch") == "Run", "touch sprint label")
		Shell.close()
	end)
end

t.check("Replay tutorial and Talk to Jeffery reach Jeffery", function()
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
	t.press(t.findNamed(t.findNamed(gui, "Window_Learn"), "TalkButton"))
	task.wait(0.1)
	assert(panelFrame().Visible, "welcome dialogue replayed")
	Controller.panel.hide()
end)

t.check("tutorial card follows server state and shows device key caps", function()
	t.fire("DataEvent", "Tutorial", { active = true, index = 7, total = 13, step = "attack", event = "step", done = {} })
	task.wait(0.1)
	local card = t.findNamed(gui, "TutorialCard")
	assert(card.Visible, "card visible")
	assert(t.findNamed(card, "Count").Text == "7 / 13", "count")
	assert(t.findNamed(card, "Key_SNLight"), "attack key cap")
	assert(panelFrame().Visible, "step lines shown")
	t.auditLayout(card, "tutorial card")
	Controller.panel.hide()
	t.fire("DataEvent", "Tutorial", { active = false, event = "exit", done = {} })
	task.wait(0.1)
	assert(not card.Visible, "card hidden after exit")
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
