-- Client smoke test for the status layer (UI/LockerWindow, Controllers/NameplateController):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke_status.luau build/game.rbxl
-- The Locker opens from the dock at 1280x720 and 667x375 on both tabs and passes the layout
-- audit (no emoji or em dash, text 14 px or more), lists owned and locked cosmetics with their
-- "how" line, sends Wear and Take off requests, and shows achievement progress bars. A nameplate
-- shows the display name, the worn title and the plate colors; the earner's moment and the
-- server chat line are accepted only when they are plain short text.

local process = require("@lune/process")
local Client = require("./smoke/Client")

local t = Client.load(process.args[1])
local Engine, task = t.Engine, t.task

local Cosmetics = t.shared("Config.Cosmetics")
local Achievements = t.shared("Config.Achievements")
Cosmetics.add("plate_smoke_test", { kind = "plate", name = "Smoke Plate", colors = { { 232, 162, 74 }, { 63, 214, 232 } }, source = "season", how = "Reach tier 5 of the season pass." })

local ui = t.startUI({
	currencies = { money = 12000, gems = 6666 },
	selected = { power = "StrongDude", degree = 1 },
	settings = { cameraShake = true, uiScale = 1 },
	passes = {},
	stats = { wins = 7, matches = 20, knockouts = 30, bestStreak = 3, playSeconds = 1800 },
	powers = { Ghost = { xp = 750 } },
	lore = { found = { ajkr_first_entry = true } },
	cosmetics = {
		owned = { title_recruit = true, title_founding = true, plate_smoke_test = true },
		equipped = { title = "title_recruit" },
	},
	achievements = { done = { win_1 = true }, progress = { cleanWins = 4 } },
})
local Shell, gui = ui.Shell, ui.gui

local function badText(root): { string }
	local found = {}
	for _, item in root:GetDescendants() do
		if item:IsA("TextLabel") or item:IsA("TextButton") then
			for _, code in utf8.codes(item.Text) do
				if code == 0x2014 or code >= 0x1F000 or (code >= 0x2600 and code <= 0x27BF) or code == 0x2B50 or code == 0xFE0F then
					table.insert(found, `{item:GetFullName()} "{item.Text}"`)
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
local function window()
	return t.findNamed(gui, "Window_Locker")
end
local function tab(id: string)
	local button = t.findNamed(window(), "Segment_" .. id) or t.findNamed(window(), id)
	if not button then
		for _, item in window():GetDescendants() do
			if item:IsA("TextButton") and string.lower(string.gsub(item.Text, utf8.char(0x200A), "")) == id then
				button = item
			end
		end
	end
	assert(button, "tab " .. id)
	t.press(button)
	task.wait(0.08)
end

t.check("the Locker is in the dock once and opens", function()
	assert(Shell.hasWindow("Locker"), "registered")
	local dock = t.findNamed(gui, "Dock")
	local count = 0
	for _, item in dock:GetChildren() do
		if item:IsA("TextButton") and string.find(item.Name, "Locker", 1, true) then
			count += 1
		end
	end
	assert(count == 1, "one dock item, got " .. count)
	Shell.open("Locker")
	assert(Shell.isOpen("Locker") and window(), "opens")
	Shell.close()
end)

for _, size in { { 1280, 720 }, { 667, 375 } } do
	t.check(`both tabs audit clean at {size[1]}x{size[2]}`, function()
		t.setScreen(size[1], size[2])
		Shell.open("Locker")
		for _, id in { "cosmetics", "achievements" } do
			tab(id)
			t.auditLayout(window(), `Locker {id} at {size[1]}x{size[2]}`)
			local bad = badText(window())
			assert(#bad == 0, "emoji or em dash:\n  " .. table.concat(bad, "\n  "))
			if size[1] == 1280 then
				local small = smallText(window())
				assert(#small == 0, "text under 14 px:\n  " .. table.concat(small, "\n  "))
			end
		end
		Shell.close()
	end)
end
t.setScreen(1280, 720)

t.check("cosmetics: owned first, locked ones show how to get them, Wear and Take off send requests", function()
	Shell.open("Locker")
	tab("cosmetics")
	local w = window()
	local recruit = t.findNamed(w, "Item_title_recruit")
	local veteran = t.findNamed(w, "Item_title_veteran")
	assert(recruit and veteran, "owned and locked titles are both listed")
	assert(t.findNamed(recruit, "TakeOff") and not t.findNamed(recruit, "Wear"), "the worn title offers Take off")
	assert(t.findNamed(t.findNamed(w, "Item_title_founding"), "Wear"), "an owned title offers Wear")
	assert(t.findNamed(veteran, "Locked") and not t.findNamed(veteran, "Wear"), "a locked title is marked and cannot be worn")
	local how = t.findText(veteran, Cosmetics.get("title_veteran").how)
	assert(how, "the locked title says how to get it")
	assert(recruit.LayoutOrder < veteran.LayoutOrder, "owned before locked")
	assert(t.findNamed(w, "Item_plate_smoke_test"), "the plate section lists plate styles")
	local start = #Engine.sent
	t.press(t.findNamed(t.findNamed(w, "Item_title_founding"), "Wear"))
	local sent = t.sentSince(start, "CosmeticRequest")
	assert(#sent == 1 and sent[1].args[1] == "Equip" and sent[1].args[2] == "title" and sent[1].args[3] == "title_founding", "Wear sends slot and id")
	task.wait(0.4)
	t.press(t.findNamed(t.findNamed(w, "Item_title_recruit"), "TakeOff"))
	local off = t.sentSince(start, "CosmeticRequest")
	assert(#off == 2 and off[2].args[3] == "", "Take off sends an empty id")
	Shell.close()
end)

t.check("achievements: progress bars, counts, done marks and rewards", function()
	Shell.open("Locker")
	tab("achievements")
	local w = window()
	local first = t.findNamed(w, "Achievement_win_1")
	assert(first and t.findText(first, "Done"), "a finished achievement says Done")
	local clean = t.findNamed(w, "Achievement_clean_10")
	assert(clean and t.findText(clean, "4 / 10"), "progress counts toward the goal")
	assert(t.findNamed(clean, "Bar"), "a progress bar")
	assert(t.findText(clean, "Reward: the title Precise"), "the reward is named")
	local mastery = t.findNamed(w, "Achievement_mastery_5")
	assert(mastery and t.findText(mastery, "4 / 5"), "mastery level 4 shows toward 5")
	local hour = t.findNamed(w, "Achievement_hour_1")
	assert(hour and t.findText(hour, "30 min / 60 min"), "time shows in minutes")
	local count = 0
	for _, def in Achievements.List do
		if t.findNamed(w, "Achievement_" .. def.id) then
			count += 1
		end
	end
	assert(count == #Achievements.List, `every achievement is listed ({count})`)
	Shell.close()
end)

-- Nameplates ---------------------------------------------------------------------------------------
local Nameplates = t.client("Controllers.NameplateController")

t.check("a nameplate shows name, title and plate colors, small and readable", function()
	local player = t.world.localPlayer
	player.DisplayName = "Alice D"
	player:SetAttribute("SNTitle", "Founding Recruit")
	player:SetAttribute("SNPlate", "plate_smoke_test")
	local plate = Nameplates.build(player, nil)
	assert(plate.MaxDistance == 60, "visible to about 60 studs")
	assert(plate.Size.X.Offset <= 300 and plate.Size.Y.Offset <= 72, "quiet size (nameplates are bigger and bolder since 4 Nov, still compact)")
	local name = t.findNamed(plate, "Name")
	local title = t.findNamed(plate, "Title")
	assert(name and name.Text == "Alice D" and name.TextSize >= 20, "display name")
	assert(title and title.Text == "Founding Recruit" and title.TextSize >= 16, "title under it")
	assert(name.Parent.LayoutOrder < title.Parent.LayoutOrder, "the title line sits under the name")
	local strip = t.findNamed(plate, "Strip")
	local bands = 0
	for _, item in strip:GetChildren() do
		if item:IsA("Frame") then
			bands += 1
		end
	end
	assert(bands == 2, "two plate colors, got " .. bands)
	assert(#badText(plate) == 0, "no emoji")
	player:SetAttribute("SNTitle", "")
	player:SetAttribute("SNPlate", "")
	local bare = Nameplates.build(player, nil)
	assert(not t.findNamed(bare, "Title"), "no title line when none is worn")
	assert(#Nameplates.stripColors("") == 1, "a default strip")
	plate:Destroy()
	bare:Destroy()
end)

t.check("status moments: the earner's headline plays; junk and long text is refused", function()
	assert(Nameplates.showMoment("Five in a Row", "Win 5 matches in a row.") == true, "a moment is accepted")
	task.wait(0.1)
	local root = t.world.localPlayer.PlayerGui:FindFirstChild("SNStatusMoment")
	assert(root and t.findNamed(root, "Headline"), "the headline is on screen")
	local headline = t.findNamed(root, "Headline")
	assert(headline.TextSize >= 14 and #badText(root) == 0, "readable, plain text")
	assert(Nameplates.showMoment(5 :: any) == false and Nameplates.showMoment(string.rep("x", 200)) == false, "junk refused")
	assert(Nameplates.chatLine(5 :: any) == false and Nameplates.chatLine(string.rep("x", 400)) == false and Nameplates.chatLine("") == false, "junk chat refused")
end)

t.finish()
