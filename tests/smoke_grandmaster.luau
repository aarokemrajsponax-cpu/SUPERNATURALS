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

-- The Fighter Showcase picks a phase with a segmented control named PhaseTabs
local function phaseSegments(detail): { any }
	local list = {}
	local tabs = detail:FindFirstChild("PhaseTabs", true)
	if tabs then
		for _, item in tabs:GetDescendants() do
			if item:IsA("TextButton") and string.match(item.Name, "^Segment_%d+$") then
				table.insert(list, item)
			end
		end
	end
	table.sort(list, function(a, b)
		return tonumber(string.match(a.Name, "%d+")) < tonumber(string.match(b.Name, "%d+"))
	end)
	return list
end

-- Does any label under root contain this text?
local function containsText(root, fragment: string): boolean
	if not root then
		return false
	end
	for _, item in root:GetDescendants() do
		if (item:IsA("TextLabel") or item:IsA("TextButton")) and string.find(item.Text, fragment, 1, true) then
			return true
		end
	end
	return false
end

local function pickFighter(gui, name: string)
	local list = t.findNamed(gui, "PowerList")
	for _, item in list:GetDescendants() do
		if item:IsA("TextButton") and t.findText(item, name) then
			t.press(item)
			return true
		end
	end
	local label = t.findText(list, name)
	if label then
		t.press(label.Parent)
		return true
	end
	return false
end

t.check("the Fighter Showcase shows the Grandmaster's four phases; the style pass is in the shop", function()
	local ui = t.startUI(PROFILE)
	local gui, Shell = ui.gui, ui.Shell
	for _, size in { { 1920, 1080 }, { 667, 375 } } do
		t.setScreen(size[1], size[2])
		Shell.open("Powers")
		assert(Shell.isOpen("Powers"), "the Fighter Showcase opens")
		assert(pickFighter(gui, "The Grandmaster"), "The Grandmaster is listed")
		local segments = phaseSegments(t.findNamed(gui, "PowerDetail"))
		assert(#segments == 4, "four phase tabs: " .. #segments)
		for phase = 1, 4 do
			t.press(phaseSegments(t.findNamed(gui, "PowerDetail"))[phase])
			local card = t.findNamed(gui, "PhaseCard")
			assert(containsText(card, `Phase {phase}:`), "the card shows Phase " .. phase)
			t.auditLayout(t.findNamed(gui, "PowerDetail"), `Showcase detail, phase {phase}`)
		end
		assert(containsText(t.findNamed(gui, "PhaseCard"), "Ascendant Dragon"), "Phase 4 is named")
		t.auditLayout(t.findNamed(gui, "PowerActions"), "Showcase actions")
		-- A three-phase power shows three tabs
		assert(pickFighter(gui, "Strong Dude"), "Strong Dude is listed")
		local strong = phaseSegments(t.findNamed(gui, "PowerDetail"))
		assert(#strong == 3, "three phase tabs for Strong Dude: " .. #strong)
		Shell.close()
	end
	t.setScreen(1920, 1080)
	-- Celestial Dragon Style is sold in the Master Shop, not on the fighter
	Shell.open("Shop", "Cosmetics")
	assert(Shell.isOpen("Shop"), "the shop opens on Cosmetics")
	assert(containsText(gui, "Celestial Dragon Style"), "the Grandmaster style pass is listed in the shop")
	Shell.close()
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
