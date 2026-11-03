-- Client smoke test for the Watch window and the spectator mode:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke_watch.luau build/game.rbxl
-- The Watch window lists live matches (names, mode, clock, spectators, powers) with Watch,
-- shows the free prediction card (pick, recorded, closed, community percentages, your totals),
-- sends only the documented requests, and says nothing is won; spectating shows the bar with
-- Follow A, Follow B, Overview, Cinematic and an always visible Exit; the camera is restored
-- exactly after Exit, after the server ends the match and after a fighter leaves; a
-- concealed fighter's exact position is never followed; all at 1280x720 and 667x375 with
-- auditLayout.

local process = require("@lune/process")
local Client = require("./smoke/Client")

local t = Client.load(process.args[1])
local task, roblox = t.task, t.roblox

local ui = t.startUI({
	currencies = { money = 100, gems = 1 },
	selected = { power = "StrongDude", degree = 1 },
	settings = { uiScale = 1 },
	stats = { predictions = 5, predictionsCorrect = 3 },
})
local Shell, gui = ui.Shell, ui.gui
local Controller = t.client("Controllers.SpectatorController")
Controller:Init({})
Controller:Start()
task.wait(0.1)

local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local workspace = t.game:GetService("Workspace")
local camera = t.world.camera

local function frames(count: number)
	t.Engine.step(t.game, count, 1 / 30)
end

local function fighter(name: string, position)
	local model = t.world.Instance.new("Model")
	model.Name = name
	local root = t.world.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = position
	root.Parent = model
	model.Parent = workspace
	return model, root
end

local matchList = {
	{
		id = "m1", slot = 1, mode = "Duel", arena = "Soul Foundry", phase = "Active", names = { "Alice", "Bob" }, watchers = 2,
		fighters = { { id = "Player:1", name = "Alice", power = "Strong Dude" }, { id = "Player:2", name = "Bob", power = "Ghost" } },
		fightStartedAt = workspace:GetServerTimeNow() - 75, tally = { counts = { ["Player:1"] = 2, ["Player:2"] = 1 }, total = 3 },
		predictionOpen = true,
	},
	{
		id = "m2", slot = 2, mode = "Duel", arena = "Ice Cavern", phase = "Active", names = { "Cy", "Di" }, watchers = 0,
		fighters = { { id = "Player:3", name = "Cy", power = "Syntax" }, { id = "Player:4", name = "Di", power = "Corruption" } },
		fightStartedAt = workspace:GetServerTimeNow() - 40, tally = { counts = {}, total = 0 }, predictionOpen = false,
		yours = nil,
	},
}

for _, size in { { 1280, 720 }, { 667, 375 } } do
	t.setScreen(size[1], size[2])
	local label = `{size[1]}x{size[2]}`

	t.check("Watch window with no matches " .. label, function()
		Shell.open("Watch")
		task.wait(0.1)
		t.fire("MatchEvent", "Matches", {})
		task.wait(0.05)
		local window = t.findNamed(gui, "Window_Watch")
		assert(window, "window opens")
		assert(t.findNamed(window, "EmptyCard"), "empty state")
		assert(t.findText(window, "Your predictions: 5 made, 3 correct, 60% accuracy."), "own stats from the profile")
		assert(t.findText(window, "Predictions are free and only for fun. They never cost or pay currency, items or rewards."), "no reward notice")
		t.auditLayout(window, "watch empty " .. label)
	end)

	t.check("Watch window lists matches with Watch and prediction cards " .. label, function()
		t.fire("MatchEvent", "Matches", matchList)
		task.wait(0.05)
		local window = t.findNamed(gui, "Window_Watch")
		local first, second = t.findNamed(window, "Match_m1"), t.findNamed(window, "Match_m2")
		assert(first and second, "both matches")
		assert(t.findText(first, "Alice vs Bob"), "names")
		assert(string.find(t.findNamed(first, "Detail").Text, "Duel on Soul Foundry", 1, true), "mode and arena")
		assert(string.find(t.findNamed(first, "Detail").Text, "2 watching", 1, true), "spectators")
		assert(string.find(t.findNamed(first, "Detail").Text, "elapsed", 1, true), "elapsed clock")
		assert(string.find(t.findNamed(first, "Powers").Text, "Strong Dude", 1, true), "powers")
		assert(t.findNamed(first, "PickButton1") and t.findNamed(first, "PickButton2"), "pick buttons while open")
		assert(string.find(t.findNamed(first, "Community").Text, "Alice 67%", 1, true), "community percentages: " .. t.findNamed(first, "Community").Text)
		assert(t.findNamed(second, "Closed"), "closed card when the cut-off passed")
		t.auditLayout(window, "watch list " .. label)
	end)

	t.check("Watch, Pick and Exit send only the documented requests " .. label, function()
		local window = t.findNamed(gui, "Window_Watch")
		local mark = #t.Engine.sent
		t.press(t.findNamed(t.findNamed(window, "Match_m1"), "WatchButton"))
		assert(t.sentSince(mark, "MatchRequest", "Spectate") ~= nil)
		local sent = t.Engine.sent[#t.Engine.sent]
		assert(sent.args[1] == "Spectate" and sent.args[2] == "m1", "Spectate m1")
		t.press(t.findNamed(t.findNamed(window, "Match_m1"), "PickButton2"))
		sent = t.Engine.sent[#t.Engine.sent]
		assert(sent.args[1] == "Predict" and sent.args[2] == "m1" and sent.args[3] == "Player:2", "Predict Bob")
		-- the server answers with the pick recorded
		local recorded = table.clone(matchList[1])
		recorded.yours = "Player:2"
		t.fire("MatchEvent", "Matches", { recorded, matchList[2] })
		task.wait(0.05)
		assert(t.findNamed(t.findNamed(gui, "Window_Watch"), "Pick") and not t.findNamed(t.findNamed(gui, "Window_Watch"), "PickButton1"), "recorded, no more picks")
		assert(t.findText(t.findNamed(gui, "Window_Watch"), "Your prediction has been recorded: Bob."), "recorded text")
		Shell.close()
	end)

	t.check("spectator bar, camera modes and Exit restore the camera " .. label, function()
		local a, rootA = fighter("Alice", Vector3.new(500, 5, 500))
		local b, rootB = fighter("Bob", Vector3.new(520, 5, 500))
		camera.CameraType = roblox.Enum.CameraType.Custom
		camera.CFrame = CFrame.new(1, 2, 3)
		camera.FieldOfView = 66
		t.fire("MatchEvent", "Spectating", { matchId = "m1", fighters = { a, b }, mode = "Duel" })
		task.wait(0.3)
		assert(Controller.isActive(), "spectating")
		assert(camera.CameraType == roblox.Enum.CameraType.Scriptable, "scriptable camera while spectating")
		local barFrame = t.findNamed(gui, "SpectatorBar")
		assert(barFrame and barFrame.Visible, "bar visible")
		for _, id in { "Mode_FollowA", "Mode_FollowB", "Mode_Overview", "Mode_Cinematic", "ExitButton" } do
			assert(t.findNamed(barFrame, id), id)
		end
		assert(t.findNamed(gui, "SpectatorStatus").Text ~= "", "status line")
		t.auditLayout(barFrame, "spectator bar " .. label)
		-- every mode puts the camera somewhere sensible near the fighters
		for _, mode in { "FollowA", "FollowB", "Overview", "Cinematic" } do
			t.press(t.findNamed(barFrame, "Mode_" .. mode))
			assert(Controller.currentMode() == mode, "mode " .. mode)
			frames(90)
			assert((camera.CFrame.Position - Vector3.new(510, 5, 500)).Magnitude < 90, mode .. " frames the fight")
		end
		-- Exit restores exactly
		t.press(t.findNamed(barFrame, "ExitButton"))
		assert(not Controller.isActive() and not barFrame.Visible, "bar hidden after Exit")
		assert(camera.CameraType == roblox.Enum.CameraType.Custom, "camera type restored")
		assert((camera.CFrame.Position - Vector3.new(1, 2, 3)).Magnitude < 0.01 and camera.FieldOfView == 66, "camera restored exactly")
		assert(t.Engine.sent[#t.Engine.sent].args[1] == "StopSpectating", "server told")
		a:Destroy()
		b:Destroy()
	end)

	t.check("the server ending the match restores the camera; a leaver switches to overview " .. label, function()
		local a, rootA = fighter("Alice", Vector3.new(500, 5, 500))
		local b = fighter("Bob", Vector3.new(520, 5, 500))
		camera.CameraType = roblox.Enum.CameraType.Custom
		camera.CFrame = CFrame.new(4, 5, 6)
		camera.FieldOfView = 70
		t.fire("MatchEvent", "Spectating", { matchId = "m1", fighters = { a, b }, mode = "Duel" })
		task.wait(0.1)
		t.press(t.findNamed(t.findNamed(gui, "SpectatorBar"), "Mode_FollowB"))
		frames(10)
		b:Destroy()
		frames(10)
		assert(Controller.isActive() and Controller.currentMode() == "Overview", "overview after a fighter left: " .. tostring(Controller.currentMode()))
		assert(string.find(t.findNamed(gui, "SpectatorStatus").Text, "left", 1, true), "says a fighter left")
		t.fire("MatchEvent", "Spectating", nil)
		task.wait(0.1)
		assert(not Controller.isActive() and camera.CameraType == roblox.Enum.CameraType.Custom, "restored when the match ends")
		assert((camera.CFrame.Position - Vector3.new(4, 5, 6)).Magnitude < 0.01 and camera.FieldOfView == 70, "exactly")
		a:Destroy()
	end)

	t.check("a concealed fighter's exact position is never followed " .. label, function()
		local Protocol = t.shared("Protocol")
		local a, rootA = fighter("Alice", Vector3.new(500, 5, 500))
		local b, rootB = fighter("Bob", Vector3.new(520, 5, 500))
		t.fire("MatchEvent", "Spectating", { matchId = "m1", fighters = { a, b }, mode = "Duel" })
		task.wait(0.1)
		t.press(t.findNamed(t.findNamed(gui, "SpectatorBar"), "Mode_FollowB"))
		frames(90)
		a:SetAttribute(Protocol.Attribute.StatusPrefix .. "Concealed", t.world.workspace:GetServerTimeNow() + 60)
		b:SetAttribute(Protocol.Attribute.StatusPrefix .. "Concealed", t.world.workspace:GetServerTimeNow() + 60)
		frames(15)
		local held = camera.CFrame.Position
		rootB.Position = Vector3.new(560, 5, 540)
		frames(90)
		assert((camera.CFrame.Position - held).Magnitude < 1, "the camera holds the last visible view")
		assert(string.find(t.findNamed(gui, "SpectatorStatus").Text, "concealed", 1, true), "bar says so")
		t.fire("MatchEvent", "Spectating", nil)
		task.wait(0.1)
		a:Destroy()
		b:Destroy()
	end)
end

t.finish()
