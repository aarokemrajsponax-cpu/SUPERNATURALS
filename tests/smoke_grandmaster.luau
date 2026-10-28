-- Client smoke test for The Grandmaster's interface:
--   lune run tests/smoke_grandmaster.luau build/grandmaster.rbxl
-- The Powers window shows four degree buttons in a tidy grid (and three for
-- other powers), the Celestial Dragon Style panel says "Not on sale yet"
-- while its id is 0, nothing overflows on phone or desktop, and the ability
-- bar draws the Focus and Perfect Form meters next to Chi.

local process = require("@lune/process")

local Client = require("./smoke/Client")

local t = Client.load(process.args[1] or "build/grandmaster.rbxl")
local Engine, world = t.Engine, t.world

local PROFILE = {
	currencies = { money = 20000, gems = 120 },
	selected = { power = "Grandmaster", degree = 4 },
	powers = { Grandmaster = { xp = 20000, degrees = {}, abilities = {} } },
	loadouts = {},
	passes = {},
	settings = { uiScale = 1 },
}

local function degreeButtons(detail): { any }
	local list = {}
	for _, item in detail:GetDescendants() do
		if item:IsA("TextButton") and string.match(item.Text, "^[^%d]*%d  ·  ") then
			table.insert(list, item)
		end
	end
	return list
end

t.check("the Powers window lays out four degrees and the cosmetic pass", function()
	local ui = t.startUI(PROFILE)
	local gui, Shell = ui.gui, ui.Shell
	for _, size in { { 1920, 1080 }, { 667, 375 } } do
		t.setScreen(size[1], size[2])
		Shell.open("Powers")
		assert(Shell.isOpen("Powers"), "the Powers window opens")
		local list = t.findNamed(gui, "PowerList")
		local card = nil
		for _, item in list:GetDescendants() do
			if item:IsA("TextButton") and t.findText(item, "The Grandmaster") then
				card = item
				break
			end
		end
		card = card or t.findText(list, "The Grandmaster")
		assert(card, "The Grandmaster is listed")
		if card:IsA("TextButton") then
			t.press(card)
		else
			t.press(card.Parent)
		end
		local detail = t.findNamed(gui, "PowerDetail")
		local buttons = degreeButtons(detail)
		assert(#buttons == 4, "four degree buttons: " .. #buttons)
		-- Two columns, two rows, same size
		local grid = buttons[1].Parent:FindFirstChildOfClass("UIGridLayout")
		assert(grid, "a grid holds them")
		assert(grid.CellSize.X.Scale == 0.5, "two columns")
		local named = false
		for _, button in buttons do
			named = named or string.find(button.Text, "4  ·  ASCENDANT DRAGON", 1, true) ~= nil
		end
		assert(named, "degree IV is named")
		for degree = 1, 4 do
			local found = nil
			for _, button in degreeButtons(t.findNamed(gui, "PowerDetail")) do
				if string.find(button.Text, `{degree}  ·`, 1, true) then
					found = button
				end
			end
			assert(found, "degree button " .. degree)
			t.press(found)
			t.auditLayout(t.findNamed(gui, "PowerDetail"), `Powers detail, degree {degree}`)
		end
		local cosmetic = t.findNamed(gui, "CosmeticPass")
		assert(cosmetic, "the Celestial Dragon Style panel")
		local buy = t.findNamed(cosmetic, "CosmeticBuy")
		assert(buy and buy.Text == "Not on sale yet", "not on sale while the id is 0: " .. tostring(buy and buy.Text))
		local says = false
		for _, item in cosmetic:GetDescendants() do
			says = says or (item:IsA("TextLabel") and string.find(item.Text, "Cosmetic only", 1, true) ~= nil)
		end
		assert(says, "says it's cosmetic only")
		t.auditLayout(cosmetic, "Cosmetic panel")
		t.auditLayout(t.findNamed(gui, "PowerActions"), "Powers actions")
		-- Back to a three-degree power: three buttons, one row
		for _, item in list:GetDescendants() do
			if item:IsA("TextButton") and t.findText(item, "Strong Dude") then
				t.press(item)
				break
			end
		end
		local strongButtons = degreeButtons(t.findNamed(gui, "PowerDetail"))
		assert(#strongButtons == 3, "three degree buttons for Strong Dude: " .. #strongButtons)
		assert(t.findNamed(gui, "CosmeticPass") == nil, "no cosmetic panel for Strong Dude")
		Shell.close()
	end
	t.setScreen(1920, 1080)
end)

t.check("the ability bar shows Focus and Perfect Form next to Chi", function()
	local ui = t.startUI(PROFILE)
	local gui = ui.gui
	local character = world.localPlayer.Character
	if not character then
		character = Engine.character("Tester")
		character.Parent = world.workspace
		world.localPlayer.Character = character
	end
	character:SetAttribute("SNPower", "Grandmaster")
	character:SetAttribute("SNDegree", 4)
	character:SetAttribute("SNLoadout", "DragonsStep,TigerClaw,CranesReversal,SweepingDragon,HundredFists,DragonsAnswer")
	character:SetAttribute("SNRes", 60)
	character:SetAttribute("SNResMax", 100)
	character:SetAttribute("SNUlt", 40)
	character:SetAttribute("SNFocus", 45)
	character:SetAttribute("SNPerfect", 100)
	Engine.step(t.game, 4, 0.05)
	t.task.wait(0.1)
	Engine.step(t.game, 4, 0.05)
	assert(t.findNamed(gui, "Ability_DragonsAnswer") and t.findNamed(gui, "Ability_HeavenSplittingDragon"), "buttons and the ultimate")
	assert(t.findText(gui, "CHI  60/100"), "the Chi meter")
	local focus = t.findNamed(gui, "Focus")
	local form = t.findNamed(gui, "PerfectForm")
	assert(focus and focus.Visible and t.findText(focus, "FOCUS  45"), "the Focus meter")
	assert(form and form.Visible and t.findText(form, "FORM  100"), "the Perfect Form meter")
	t.auditLayout(t.findNamed(gui, "AbilityBar"), "Ability bar")
	-- Powers without the meters hide them
	character:SetAttribute("SNFocus", nil)
	character:SetAttribute("SNPerfect", nil)
	Engine.step(t.game, 4, 0.05)
	t.task.wait(0.1)
	assert(not focus.Visible and not form.Visible, "hidden without the attributes")
end)

t.finish()
