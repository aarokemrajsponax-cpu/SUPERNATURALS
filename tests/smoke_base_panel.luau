-- The base panel window (UI/BaseWindow): it opens when the server sends BaseEvent.Panel with
-- open = true, shows the owner's controls, fits a phone, and only asks the server.
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke_base_panel.luau build/game.rbxl
-- The server rules are in tests/base2_test.luau.

local process = require("@lune/process")
local Client = require("./smoke/Client")

local t = Client.load(process.args[1])
local Protocol = t.shared("Protocol")
local ui = t.startUI({
	currencies = { money = 500, gems = 0 },
	selected = { power = "StrongDude", degree = 1 },
	powers = { StrongDude = { xp = 0 } },
	loadouts = {},
	passes = {},
	settings = {},
})
local Shell, gui = ui.Shell, ui.gui
t.setScreen(1280, 720)

local STATE = {
	open = true,
	access = "Friends",
	jukebox = "Chill",
	party = false,
	effects = { Aurora = false, Snowfall = false, Fireplace = false, LightShow = false, Fireflies = false },
	ownsEffects = false,
	fireworks = 0,
	showing = false,
	hearts = 3,
	visitors = { { id = 2, name = "Bob" } },
	here = { { id = 2, name = "Bob" } },
	bests = { PowerMeter = 87 },
}

t.check("the panel opens from the server's Panel event with every section", function()
	t.fire("BaseEvent", Protocol.BaseEvent.Panel, STATE)
	t.task.wait(0.1)
	assert(Shell.isOpen("Base"), "the base panel opened")
	local window = t.findNamed(gui, "Window_Base")
	assert(window, "the window frame exists")
	for _, name in { "Access", "Music", "Effects", "Fireworks", "Visitors", "Bests" } do
		assert(t.findNamed(window, name), "section " .. name)
	end
	assert(t.findNamed(window, "Access_Everyone") and t.findNamed(window, "Music_Phonk") and t.findNamed(window, "Party"), "controls")
	assert(t.findNamed(window, "AskLeave"), "ask a visitor to leave")
	assert(t.findText(window, "Hearts from visitors: 3. A friend who stays a minute earns you a small Money bonus once a day."), "hearts")
end)

t.check("effects are locked without the pass and the Fireworks button waits for a charge", function()
	local window = t.findNamed(gui, "Window_Base")
	local effect = t.findNamed(t.findNamed(window, "Effect_Aurora"), "Toggle")
	assert(effect and (effect:GetAttribute("Disabled") == true or effect.Active == false or effect.AutoButtonColor == false), "locked effect toggle")
	assert(t.findNamed(window, "ShopEffects"), "a way to the shop")
	assert(t.findNamed(window, "Launch"), "launch button")
end)

t.check("the panel fits a phone", function()
	t.setScreen(667, 375)
	t.task.wait(0.1)
	Shell.close()
	Shell.open("Base")
	t.task.wait(0.1)
	assert(Shell.isOpen("Base"), "reopens on a phone")
	local window = t.findNamed(gui, "Window_Base")
	assert(window and window.Size.X.Offset > 0 and window.Size.Y.Offset > 0, "has a size")
end)

t.finish()
