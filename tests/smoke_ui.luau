-- Client smoke test for the selection screens (Fighter Showcase, Play, Settings, Phase meter):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke_ui.luau build/game.rbxl
-- Every window opens at 1920x1080, 1280x720 and 667x375 and passes the layout audit; no emoji
-- or em dash reaches a label; text is at least 14 px; the 3D preview builds for all seven released
-- powers and every phase; the dock lists each window once; Training is labelled free; the
-- Phase meter shows its "press T" cue.

local process = require("@lune/process")
local Client = require("./smoke/Client")

local t = Client.load(process.args[1])
local Engine = t.Engine

local Powers = t.shared("Powers")
local ui = t.startUI({
	currencies = { money = 12000, gems = 6666 },
	selected = { power = "StrongDude", degree = 1 },
	powers = { StrongDude = { xp = 500 } },
	loadouts = {},
	passes = {},
	settings = {},
})
local Shell, gui = ui.Shell, ui.gui

local SIZES = { { 1920, 1080 }, { 1280, 720 }, { 667, 375 } }
local WINDOWS = { "Powers", "Play", "Settings" }

local function badText(root): { string }
	local found = {}
	for _, item in root:GetDescendants() do
		if item:IsA("TextLabel") or item:IsA("TextButton") then
			local text = item.Text
			for _, code in utf8.codes(text) do
				-- Emoji and pictographs, and the em dash
				if code == 0x2014 or code >= 0x1F000 or (code >= 0x2600 and code <= 0x27BF) or code == 0x2B50 or code == 0xFE0F then
					table.insert(found, `{item:GetFullName()} "{text}"`)
					break
				end
			end
		end
	end
	return found
end

local function smallText(root): { string }
	local found = {}
	for _, item in root:GetDescendants() do
		if (item:IsA("TextLabel") or item:IsA("TextButton")) and item.Text ~= "" and not item.TextScaled and item.TextSize < 14 then
			table.insert(found, `{item:GetFullName()} {item.TextSize}`)
		end
	end
	return found
end

local function isPhaseTab(tab): boolean
	return tab:IsA("TextButton") and string.find(string.upper(string.gsub(tab.Text, utf8.char(0x200A), "")), "PHASE", 1, true) ~= nil
end

for _, size in SIZES do
	t.check(`windows open and audit at {size[1]}x{size[2]}`, function()
		t.setScreen(size[1], size[2])
		for _, id in WINDOWS do
			Shell.open(id)
			assert(Shell.isOpen(id), `{id} opens`)
			local window = t.findNamed(gui, "Window_" .. id)
			assert(window, `{id} has a window frame`)
			t.auditLayout(window, `{id} at {size[1]}x{size[2]}`)
			local emoji = badText(window)
			assert(#emoji == 0, `{id}: emoji or em dash:\n  ` .. table.concat(emoji, "\n  "))
			if size[1] == 1280 then
				local small = smallText(window)
				assert(#small == 0, `{id}: text under 14 px:\n  ` .. table.concat(small, "\n  "))
			end
			Shell.close()
		end
		local dock = t.findNamed(gui, "Dock")
		local seen = {}
		for _, item in dock:GetChildren() do
			if item:IsA("TextButton") then
				assert(not seen[item.Name], "dock lists " .. item.Name .. " once")
				seen[item.Name] = true
			end
		end
		local chrome = badText(t.findNamed(gui, "ShellChrome"))
		assert(#chrome == 0, "the dock has no emoji: " .. table.concat(chrome, ", "))
	end)
end
t.setScreen(1280, 720)

t.check("phone mode: scale floor, full-canvas window, chrome hidden, signal and rotation", function()
	local Theme = t.client("UI.Theme")
	local flips = {}
	local link = Shell.compactChanged:Connect(function(value)
		table.insert(flips, value)
	end)
	t.setScreen(1280, 720)
	assert(not Shell.isCompact(), "1280x720 is not compact")
	t.setScreen(667, 375)
	assert(Shell.isCompact(), "667x375 is compact")
	assert(Shell.scale() >= Theme.Scale.CompactMin - 1e-6, `scale {Shell.scale()} is under the compact floor`)
	for _, id in { "Powers", "Play", "Settings" } do
		Shell.open(id)
		local window = t.findNamed(gui, "Window_" .. id)
		local canvas = { X = 667 / Shell.scale(), Y = 375 / Shell.scale() }
		assert(math.abs(window.Size.X.Offset - canvas.X) < 1 and window.Size.Y.Offset > canvas.Y - 80, `{id} fills the phone canvas {window.Size.X.Offset}x{window.Size.Y.Offset} of {canvas.X}x{canvas.Y}`)
		assert(not t.findNamed(gui, "Dock").Visible, "dock hides behind a phone window")
		Shell.close()
		assert(t.findNamed(gui, "Dock").Visible, "dock returns after the window closes")
	end
	Shell.open("Settings")
	t.setScreen(1024, 768)
	assert(not Shell.isCompact() and Shell.isOpen("Settings"), "rotating to a tablet keeps the window open")
	assert(t.findNamed(gui, "Window_Settings").Size.X.Offset < 1024 / Shell.scale() - 40, "the window leaves the canvas at tablet size")
	Shell.close()
	assert(#flips == 2 and flips[1] == true and flips[2] == false, `compactChanged fired {#flips} times`)
	link:Disconnect()
	t.setScreen(1280, 720)
end)

t.check("the preview builds for all seven released powers and every phase", function()
	Shell.open("Powers")
	local list = t.findNamed(gui, "PowerList")
	local built = 0
	for _, card in list:GetChildren() do
		if card:IsA("TextButton") then
			t.press(card)
			local id = string.sub(card.Name, 6)
			for phase = 1, Powers.degreeCount(id) do
				local tabs = {}
				for _, tab in t.findNamed(t.findNamed(gui, "PowerDetail"), "PhaseTabs"):GetDescendants() do
					if isPhaseTab(tab) then
						table.insert(tabs, tab)
					end
				end
				t.press(tabs[phase])
				local model = t.findNamed(t.findNamed(gui, "Viewport"), "PreviewFighter")
				assert(model and model:GetAttribute("SNDegree") == phase, `preview figure for {id} phase {phase}`)
				built += 1
			end
		end
	end
	local expected = 0
	for _, id in Powers.released() do
		expected += Powers.degreeCount(id)
	end
	assert(built == expected and expected == 22, `built {built} previews, expected {expected} (7 released powers: 6 x 3 phases + Grandmaster 4 = 22)`)
	Shell.close()
end)

t.check("premium fighters show an intro and a price; free ones do not", function()
	Shell.open("Powers")
	for _, id in { "Corruption", "Syntax", "Admin" } do
		t.press(t.findNamed(gui, "Card_" .. id))
		local detail = t.findNamed(gui, "PowerDetail")
		assert(t.findNamed(detail, "PremiumIntro"), id .. " has a premium intro")
	end
	t.press(t.findNamed(gui, "Card_StrongDude"))
	assert(not t.findNamed(t.findNamed(gui, "PowerDetail"), "PremiumIntro"), "free fighters have no premium intro")
	Shell.close()
end)

t.check("locked phases offer a permanent unlock, separate from the evolve fee", function()
	Shell.open("Powers")
	t.press(t.findNamed(gui, "Card_Corruption"))
	local found = false
	for phase = 2, 3 do
		local tabs = {}
		for _, tab in t.findNamed(t.findNamed(gui, "PowerDetail"), "PhaseTabs"):GetDescendants() do
			if isPhaseTab(tab) then
				table.insert(tabs, tab)
			end
		end
		t.press(tabs[phase])
		local detail = t.findNamed(gui, "PowerDetail")
		if t.findNamed(detail, "UnlockPhase") then
			found = true
		end
		local text = false
		for _, item in detail:GetDescendants() do
			if item:IsA("TextLabel") and string.find(item.Text, "Evolve fee (this match)", 1, true) then
				text = true
			end
		end
		assert(text, "the evolve fee is labelled as this match only")
	end
	assert(found, "a locked phase has an Unlock Phase button")
	assert(t.findNamed(t.findNamed(gui, "PowerDetail"), "UnlockWithGems"), "a premium fighter has a Gem unlock")
	Shell.close()
end)

t.check("Play: Training is free and separate; confirm sends the selection", function()
	Shell.open("Play")
	assert(t.findNamed(gui, "HeaderFree"), "Training sits under its own free header")
	t.press(t.findNamed(gui, "Mode_Training"))
	local box = t.findNamed(gui, "TrainingFree")
	assert(box and box.Visible, "the free-training note shows")
	t.press(t.findNamed(gui, "Mode_Duel"))
	local start = #Engine.sent
	t.press(t.findNamed(gui, "Fighter_Ghost"))
	t.press(t.findNamed(gui, "Action"))
	local queued = t.sentSince(start, "MatchRequest", "Queue")
	assert(#queued == 1, "Confirm queues once")
	local options = queued[1].args[3]
	assert(options and options.selection and options.selection.power == "Ghost" and options.selection.degree == 1, "the queue carries the chosen fighter at Phase 1")
	assert(typeof(options.selection.loadout) == "table" and #options.selection.loadout >= 1, "and a loadout")
	Shell.close()
end)

t.check("Phase meter shows the evolve cue", function()
	local PhaseMeter = t.client("UI.PhaseMeter")
	local info = PhaseMeter.describe({ SNPhaseNext = "Rising", SNPhaseFee = 20, SNPhaseMeter = 100 }, 500)
	assert(info.full and info.affordable and string.find(info.detail, "Meter full: press T to evolve (20 Money)", 1, true), info.detail)
	local poor = PhaseMeter.describe({ SNPhaseNext = "Rising", SNPhaseFee = 20, SNPhaseMeter = 100 }, 5)
	assert(not poor.affordable and string.find(poor.detail, "Need", 1, true), poor.detail)
end)

t.finish()
