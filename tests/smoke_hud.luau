-- Client smoke test for when and how the combat interface appears:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke_hud.luau build/game.rbxl
-- The HUD is hidden in the lobby and shown in a match and in training (the server's context
-- attribute is the one source of truth); a fight hides the dock, the wallet and the player card;
-- the touch arch fits without overlap on phones and tablets; the gamepad has a button for every
-- action; the player card changes fighters (and says no during a match); the friend chip shows
-- only while a friend is here.

local process = require("@lune/process")
local Client = require("./smoke/Client")

local t = Client.load(process.args[1])
local Engine, world, roblox = t.Engine, t.world, t.roblox
local Instance, Vector3, Vector2, CFrame, Enum = world.Instance, roblox.Vector3, roblox.Vector2, roblox.CFrame, roblox.Enum
local workspace = world.workspace

local UserInputService = t.game:GetService("UserInputService")
UserInputService.TouchEnabled = false
UserInputService.KeyboardEnabled = true

local Protocol = t.shared("Protocol")
local Powers = t.shared("Powers")
local Attribute = Protocol.Attribute

local function step(frames: number)
	Engine.step(t.game, frames, 1 / 30)
end
-- Lets the 20 Hz interface tick and the fades finish
local function settle()
	for _ = 1, 3 do
		step(4)
		t.task.wait(0.08)
	end
	step(2)
end

-- A fighter for the local player
local me = Instance.new("Model")
me.Name = "Me"
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(2, 2, 1)
root.CFrame = CFrame.new(0, 3, 0)
root.Parent = me
local humanoid = Instance.new("Humanoid")
humanoid.RigType = Enum.HumanoidRigType.R15
humanoid.Parent = me
me.PrimaryPart = root
me.Parent = workspace
Engine.syncPositions(me)
world.localPlayer.Character = me
table.insert(Engine.players, world.localPlayer)

local function loadout(powerId: string, degree: number)
	me:SetAttribute(Attribute.Power, powerId)
	me:SetAttribute(Attribute.Degree, degree)
	me:SetAttribute(Attribute.Loadout, table.concat(Powers.defaultLoadout(powerId, degree), ","))
end
loadout("StrongDude", 1)

local function context(name: string?)
	me:SetAttribute(Attribute.CombatContext, name)
end
context("Lobby")

-- The real controllers
local controllers = {
	AbilityController = {
		aim = function()
			return { direction = Vector3.new(0, 0, -1) }
		end,
	},
	PowerFxController = { predict = function() end },
}
local NAMES = { "CameraController", "EffectsController", "CombatController", "InputController" }
for _, name in NAMES do
	controllers[name] = t.client("Controllers." .. name)
end
for _, name in NAMES do
	local controller = controllers[name]
	if controller.Init then
		controller:Init(controllers)
	end
end
for _, name in NAMES do
	t.task.spawn(controllers[name].Start, controllers[name])
end
t.task.wait(0.1)
local Input = controllers.InputController

local ui = t.startUI()
local Shell, gui, UIController = ui.Shell, ui.gui, ui.UIController
local TouchArch = t.client("UI.TouchArch")
local hud = UIController.hud

local function visible(root_)
	return root_ ~= nil and root_.Visible
end

-- The lobby ---------------------------------------------------------------------------------

t.check("lobby: no combat HUD, no ability buttons, only the lobby essentials", function()
	ui.device("keyboard")
	t.setScreen(1280, 720)
	settle()
	assert(Shell.getMode() == "Lobby", "lobby mode")
	assert(not hud.isShown(), "the HUD is away in the lobby")
	assert(not visible(t.findNamed(gui, "Hud")), "the HUD frame is hidden")
	assert(visible(t.findNamed(gui, "Dock")), "the dock shows")
	assert(visible(t.findNamed(gui, "PlayerCard")) and visible(t.findNamed(gui, "Wallet")), "player card and wallet show")
end)

t.check("lobby: the touch buttons stay away too", function()
	Engine.lastInputType = Enum.UserInputType.Touch
	ui.device("touch")
	settle()
	local touch = world.localPlayer.PlayerGui:FindFirstChild("SNTouchControls")
	assert(touch and not touch.Enabled, "no thumb buttons in the lobby")
	Engine.lastInputType = Enum.UserInputType.Keyboard
	ui.device("keyboard")
end)

-- A match and training ----------------------------------------------------------------------

t.check("match: the HUD fades in and the fight layout hides the dock, wallet and player card", function()
	context("Match")
	Shell.setMode("Match")
	settle()
	assert(hud.isShown(), "the HUD is on")
	assert(visible(t.findNamed(gui, "Hud")), "the HUD frame shows")
	assert(not visible(t.findNamed(gui, "Dock")), "no dock in a fight")
	assert(not visible(t.findNamed(gui, "Wallet")), "no currency pills in a fight")
	assert(not visible(t.findNamed(gui, "PlayerCard")), "no player card in a fight")
	assert(visible(t.findNamed(gui, "SmallBar")) and visible(t.findNamed(gui, "SettingsButton")), "a settings button stays")
	assert(not visible(t.findNamed(gui, "FightersButton")), "no Fighters button in a match")
end)

t.check("match: the player card button is refused with a plain message", function()
	local opened = Shell.changeFighter()
	assert(opened == false and not Shell.isOpen("Powers"), "the Showcase stays shut during a match")
	assert(t.findText(gui, "Your fighter is locked until the match ends."), "a plain message says why")
end)

t.check("the match ends: the lobby comes back and the HUD goes", function()
	context("Lobby")
	t.fire("MatchEvent", Protocol.MatchEvent.Ended)
	settle()
	assert(Shell.getMode() == "Lobby", "lobby mode again: " .. Shell.getMode())
	assert(not hud.isShown(), "HUD away")
	assert(visible(t.findNamed(gui, "Dock")) and visible(t.findNamed(gui, "Wallet")) and visible(t.findNamed(gui, "PlayerCard")), "the lobby chrome is back")
end)

t.check("training: the HUD shows, the dock goes, and a Fighters button appears", function()
	context("Training")
	settle()
	assert(Shell.getMode() == "Training", "training layout: " .. Shell.getMode())
	assert(hud.isShown(), "the HUD is on in training")
	assert(not visible(t.findNamed(gui, "Dock")) and not visible(t.findNamed(gui, "Wallet")) and not visible(t.findNamed(gui, "PlayerCard")), "fight layout")
	assert(visible(t.findNamed(gui, "FightersButton")), "Fighters button in the Training Studio")
	t.press(t.findNamed(gui, "FightersButton"))
	assert(Shell.isOpen("Powers"), "it opens the Fighter Showcase")
	Shell.close()
	context("Npc")
	settle()
	assert(hud.isShown() and Shell.getMode() == "Training", "CPU practice counts as training")
	context("Lobby")
	settle()
	assert(Shell.getMode() == "Lobby" and not hud.isShown(), "walking out of the hall restores the lobby")
	assert(visible(t.findNamed(gui, "Dock")), "dock back")
end)

t.check("spectating and the owner showcase follow the same rule", function()
	context("Showcase")
	settle()
	assert(hud.isShown(), "showcase shows the HUD")
	assert(Shell.getMode() == "Lobby", "but keeps the lobby chrome")
	context("Lobby")
	settle()
	assert(not hud.isShown())
end)

-- Changing fighters -------------------------------------------------------------------------

t.check("the player card is a Change button that opens the Fighter Showcase", function()
	settle()
	local card = t.findNamed(gui, "PlayerCard")
	assert(visible(card), "card shows")
	local button = t.findNamed(card, "ChangeFighter")
	assert(button and button.Selectable, "the card is a selectable button")
	local chip = t.findNamed(card, "ChangeChip")
	assert(chip and t.findText(chip, "Change"), "and it says Change")
	assert(t.findText(card, "Strong Dude") or t.findText(card, "StrongDude") or t.findNamed(card, "Power"), "the current fighter is named")
	t.press(button)
	assert(Shell.isOpen("Powers"), "one tap opens the Showcase")
	Shell.close()
end)

-- The friend bonus --------------------------------------------------------------------------

t.check("the Friend bonus chip shows only while a friend is here", function()
	local chip = t.findNamed(gui, "FriendBonus")
	assert(chip and not chip.Visible, "nothing without a friend")
	world.localPlayer:SetAttribute(Attribute.FriendBonus, 20)
	Engine.signalOf(world.localPlayer, "Attribute:" .. Attribute.FriendBonus):Fire()
	settle()
	assert(chip.Visible and t.findText(chip, "Friend bonus +20%"), "the chip names the bonus")
	t.auditLayout(chip, "friend chip")
	-- It is a lobby thing: gone in a fight
	Shell.setMode("Match")
	assert(not chip.Visible, "hidden in a fight")
	Shell.setMode("Lobby")
	assert(chip.Visible, "back in the lobby")
	world.localPlayer:SetAttribute(Attribute.FriendBonus, nil)
	Engine.signalOf(world.localPlayer, "Attribute:" .. Attribute.FriendBonus):Fire()
	settle()
	assert(not chip.Visible, "gone when the friend leaves")
end)

-- The touch arch ----------------------------------------------------------------------------

local PHONES = { { 667, 375 }, { 844, 390 }, { 932, 430 } }
local TABLETS = { { 1024, 768 }, { 1194, 834 } }
local SIZES = {}
for _, size in PHONES do
	table.insert(SIZES, size)
end
for _, size in TABLETS do
	table.insert(SIZES, size)
end

-- { name, x, y, r } of every visible thumb button, in screen pixels
local function thumbButtons(touch, width: number, height: number)
	local found = {}
	for _, button in touch:GetChildren() do
		if button:IsA("TextButton") and button.Visible then
			local scale = button:FindFirstChild("ArchScale")
			local size = button.Size.X.Offset * (if scale then scale.Scale else 1)
			table.insert(found, {
				name = button.Name,
				x = width + button.Position.X.Offset,
				y = height + button.Position.Y.Offset,
				r = size / 2,
				size = size,
			})
		end
	end
	return found
end

local function gapBetween(a, b): number
	return (Vector2.new(a.x, a.y) - Vector2.new(b.x, b.y)).Magnitude - a.r - b.r
end

for _, power in { { "StrongDude", 1 }, { "Grandmaster", 4 } } do
	t.check(`touch arch: {power[1]} degree {power[2]} fits on phones and tablets without overlap`, function()
		loadout(power[1], power[2])
		context("Match")
		Shell.setMode("Match")
		Engine.lastInputType = Enum.UserInputType.Touch
		ui.device("touch")
		local touch = world.localPlayer.PlayerGui:FindFirstChild("SNTouchControls")
		assert(touch, "touch controls built")
		for _, size in SIZES do
			local width, height = size[1], size[2]
			t.setScreen(width, height)
			settle()
			assert(touch.Enabled, `thumb buttons show in a fight at {width}x{height}`)
			local list = thumbButtons(touch, width, height)
			local byName = {}
			for _, item in list do
				byName[item.name] = item
			end
			-- The brief: heavy, block, dodge, grab, three abilities and the ultimate, round a big attack button
			for _, needed in { "TouchLight", "TouchHeavy", "TouchBlock", "TouchDodge", "TouchGrab", "Ability_" .. Powers.ultimateOf(power[1], power[2]) } do
				assert(byName[needed], `{needed} is there at {width}x{height}`)
			end
			local main = byName.TouchLight
			local jumpX, jumpY, jumpSize = TouchArch.jumpFrame(width, height)
			local jump = { x = width + jumpX, y = height + jumpY, r = jumpSize / 2 }
			assert(main.size >= 80, `the main button is large: {main.size}`)
			for _, item in list do
				assert(item.size >= 56 - 0.01, `{item.name} is at least 56 px: {item.size}`)
				if item.name ~= "TouchLight" then
					assert(item.size < main.size, `{item.name} is smaller than the main button`)
				end
				assert(item.x - item.r >= 0 and item.x + item.r <= width and item.y - item.r >= 0 and item.y + item.r <= height, `{item.name} is on screen at {width}x{height}`)
				assert(item.x - item.r >= width * TouchArch.THUMBSTICK_SHARE, `{item.name} stays off the thumbstick at {width}x{height}`)
				assert(gapBetween(item, jump) >= 4, `{item.name} clears the jump button at {width}x{height}: {gapBetween(item, jump)}`)
			end
			for i = 1, #list do
				for j = i + 1, #list do
					assert(gapBetween(list[i], list[j]) >= 4, `{list[i].name} and {list[j].name} overlap at {width}x{height}: {gapBetween(list[i], list[j])}`)
				end
			end
			-- The vitals sit between the thumbstick and the arch
			local frame = hud.frame
			local scale = Shell.scale()
			local hudWidth = frame.Size.X.Offset * scale
			local hudLeft = frame.Position.X.Offset * scale - hudWidth / 2
			local hudRight = hudLeft + hudWidth
			local layout = t.client("UI.Hud").Layout
			local hudTop = height - (layout.bottom + layout.touchHeight) * scale
			assert(hudLeft >= width * TouchArch.THUMBSTICK_SHARE - 1, `the vitals clear the thumbstick at {width}x{height}: {hudLeft}`)
			for _, item in list do
				local overlapX = item.x + item.r > hudLeft and item.x - item.r < hudRight
				local overlapY = item.y + item.r > hudTop
				assert(not (overlapX and overlapY), `{item.name} stays off the vitals at {width}x{height}`)
			end
			t.auditLayout(touch, `touch buttons {width}x{height}`)
		end
		Shell.setMode("Lobby")
		context("Lobby")
		Engine.lastInputType = Enum.UserInputType.Keyboard
		ui.device("keyboard")
		t.setScreen(1280, 720)
		settle()
		assert(not world.localPlayer.PlayerGui:FindFirstChild("SNTouchControls").Enabled, "thumb buttons leave with the fight")
	end)
end

t.check("touch arch: pure layout keeps every slot on screen for all sizes and any number of buttons", function()
	for _, size in SIZES do
		for count = 0, 15 do
			local exists = { [TouchArch.MAIN] = true }
			for index, name in TouchArch.ORDER do
				if index <= count then
					exists[name] = true
				end
			end
			local result = TouchArch.compute(size[1], size[2], TouchArch.items(exists))
			for name, slot in result.slots do
				assert(size[1] + slot.x - slot.size / 2 >= 0 and size[1] + slot.x + slot.size / 2 <= size[1], `{name} off screen at {size[1]}x{size[2]}`)
				assert(size[2] + slot.y - slot.size / 2 >= 0 and size[2] + slot.y + slot.size / 2 <= size[2], `{name} off screen vertically at {size[1]}x{size[2]}`)
			end
		end
	end
	-- Nothing is dropped for the full set at any of these sizes
	for _, size in SIZES do
		local exists = { [TouchArch.MAIN] = true }
		for _, name in TouchArch.ORDER do
			exists[name] = true
		end
		local result = TouchArch.compute(size[1], size[2], TouchArch.items(exists))
		for _, name in { "SNHeavy", "SNBlock", "SNDodge", "SNGrab", "Ability_1", "Ability_2", "Ability_3", "Ability_Ultimate" } do
			assert(result.slots[name], `{name} always has a place at {size[1]}x{size[2]}`)
		end
	end
end)

-- Gamepad and keyboard ----------------------------------------------------------------------

t.check("gamepad: every action has a button or a chord, and hints use gamepad names", function()
	for _, binding in Input.Bindings do
		assert(#binding.pads > 0 or string.find(binding.padText, "+", 1, true), `{binding.name} has a gamepad button`)
		assert(binding.padText ~= "" and binding.padText ~= binding.keyText or binding.name == "SNEvolve", `{binding.name} has gamepad hint text`)
	end
	-- The keyboard keys are unchanged
	local keys = { SNLight = "M1", SNHeavy = "E", SNBlock = "F", SNDodge = "Q", SNGrab = "G", SNSweep = "C", SNSprint = "Shift", SNLock = "Z", SNEvolve = "T", SNTaunt = "V" }
	for _, binding in Input.Bindings do
		assert(keys[binding.name] == binding.keyText, `{binding.name} keeps its key`)
	end
	local pads = { SNLight = "X", SNHeavy = "Y", SNBlock = "L1", SNDodge = "B", SNSprint = "L3", SNLock = "R3", SNEvolve = "Start", SNTaunt = "View" }
	for _, binding in Input.Bindings do
		if pads[binding.name] then
			assert(binding.padText == pads[binding.name], `{binding.name} pad text {binding.padText}`)
		end
	end
	-- The HUD shows those names while a gamepad is in hand
	context("Training")
	loadout("StrongDude", 1)
	ui.device("gamepad")
	Engine.lastInputType = Enum.UserInputType.Gamepad1
	t.setScreen(1280, 720)
	settle()
	local actions = t.findNamed(hud.frame, "Actions")
	assert(actions and actions.Visible and t.findText(actions, "L1+X") and t.findText(actions, "R3"), "gamepad glyph names in the hint strip")
	local bar = t.findNamed(gui, "AbilityBar")
	assert(bar and (t.findText(bar, "R1") or t.findText(bar, "R2")), "and on the ability buttons")
	-- The Showcase takes the gamepad selection
	Shell.open("Powers")
	local selectable = 0
	for _, item in t.findNamed(gui, "Window_Powers"):GetDescendants() do
		if item:IsA("GuiButton") and item.Selectable then
			selectable += 1
		end
	end
	assert(selectable > 3, "windows can be navigated with the gamepad: " .. selectable)
	-- (the stand-in engine can't clear GuiService.SelectedObject, so go back to the keyboard first)
	Engine.lastInputType = Enum.UserInputType.Keyboard
	ui.device("keyboard")
	Shell.close()
	context("Lobby")
	settle()
end)

t.check("the evolve cue names the button for the device in hand", function()
	local PhaseMeter = t.client("UI.PhaseMeter")
	local attrs = { SNPhaseNext = "Rising", SNPhaseFee = 20, SNPhaseMeter = 100 }
	assert(string.find(PhaseMeter.describe(attrs, 500, "keyboard").detail, "press T", 1, true))
	assert(string.find(PhaseMeter.describe(attrs, 500, "gamepad").detail, "press Start", 1, true))
	assert(string.find(PhaseMeter.describe(attrs, 500, "touch").detail, "tap Evolve", 1, true))
end)

t.finish()
