-- Client smoke test for the Meridian Archive, the lore book (UI/ArchiveWindow):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke_archive.luau build/game.rbxl
-- Opens the book with five files recovered, pages through every chapter and
-- file, builds every figure, checks that redacted words never reach a label,
-- the lock and hint rows for files not found yet, the "new" marks, page turns
-- from the keyboard, the gamepad and a swipe, the reading progress sent to the
-- server, text staying inside the page margins, and the layout at 1280x720
-- and 667x375.

local process = require("@lune/process")
local Client = require("./smoke/Client")

local t = Client.load(process.args[1])
local roblox = t.roblox
local Enum = roblox.Enum
local task = t.task
local Engine = t.Engine

local Archive = t.shared("Content.Archive")
local ArchiveWindow = t.client("UI.ArchiveWindow")
ArchiveWindow.Config.ReadSpacing = 0.01

local FOUND = { "ajkr_first_entry", "lantern_field_note", "procurement_memo", "warden_boot", "eclipse_cleanup" }
local foundSet = {}
for _, id in FOUND do
	foundSet[id] = true
end

-- A chapter with real words under the redactions (the story's own redactions
-- hide only spaces), so the test can prove the words never reach the screen
local SECRETS = { "Harold", "Whitcombe", "Agnes", "Brightwater", "Cornelius", "Fairbank", "Mabel", "Orrington" }
table.insert(Archive.Chapters, {
	id = "smoke_redaction",
	title = "Redaction Check",
	kind = "memo",
	meta = "Smoke test copy for {{Agnes Brightwater}}.",
	blocks = {
		"TO: {{Cornelius Fairbank}}",
		"1. The director, {{Harold Whitcombe}}, signed it *without reading it*.",
		{ lines = { "21:58:04  Subject {{Mabel Orrington}} present." } },
	},
})

local ui = t.startUI({
	currencies = { money = 12000, gems = 6666 },
	selected = { power = "StrongDude", degree = 1 },
	settings = { cameraShake = true, uiScale = 1 },
	lore = { found = foundSet, read = { ajkr_first_entry = true }, last = "", page = 0 },
})
local Shell = ui.Shell
local gui = ui.gui

local function state()
	return ArchiveWindow.debugState()
end

local function settle()
	task.wait(0.06)
end

-- Every label text on screen, checked for the hidden words
local leaks = {}
local function scanForSecrets(where: string)
	for _, item in gui:GetDescendants() do
		if item:IsA("TextLabel") or item:IsA("TextButton") then
			for _, secret in SECRETS do
				if string.find(item.Text, secret, 1, true) then
					table.insert(leaks, `{where}: "{item.Text}"`)
				end
			end
		end
	end
end

-- Offsets of `item` inside `page` (pages are laid out with offsets only)
local function offsetIn(item, page)
	local x, y = 0, 0
	local node = item
	while node and node ~= page do
		if node:IsA("GuiObject") then
			x += node.Position.X.Offset
			y += node.Position.Y.Offset
		end
		node = node.Parent
	end
	return x, y
end

local function insideDecor(item, page)
	local node = item.Parent
	while node and node ~= page do
		local name = node.Name
		if string.sub(name, 1, 7) == "Figure_" or name == "Stamp" or name == "Bookplate" or name == "FolderTab" or name == "Terminal" or string.sub(name, 1, 6) == "Entry_" or string.sub(name, 1, 5) == "File_" or string.sub(name, 1, 7) == "Locked_" then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Text must stay inside the page with a margin, never touching an edge
local function checkMargins(label: string)
	local s = state()
	local geo = s.geo
	local bad = {}
	for index, page in s.frames do
		for _, item in page:GetDescendants() do
			if item:IsA("TextLabel") and item.Text ~= "" and not insideDecor(item, page) then
				local x, y = offsetIn(item, page)
				local right, bottom = x + item.Size.X.Offset, y + item.Size.Y.Offset
				if x < 8 or y < 2 or right > geo.pageW - 8 or bottom > geo.pageH - 2 then
					table.insert(bad, `page {index} "{string.sub(item.Text, 1, 30)}" at {x},{y} to {right},{bottom}`)
				end
			end
		end
	end
	assert(#bad == 0, `{label}: text outside the page margins:\n       ` .. table.concat(bad, "\n       ", 1, math.min(#bad, 8)))
end

local seenDocs, seenFigures = {}, {}
local redactionBars = 0
local function record()
	local s = state()
	for offset = 0, (if s.geo.single then 0 else 1) do
		local model = s.book.pages[s.index + offset]
		if model and model.doc then
			seenDocs[model.doc.id] = true
		end
		local frame = s.frames[s.index + offset]
		if frame then
			for _, item in frame:GetDescendants() do
				if string.sub(item.Name, 1, 7) == "Figure_" then
					seenFigures[string.sub(item.Name, 8)] = true
				elseif item.Name == "Redaction" and model and model.doc and model.doc.id == "smoke_redaction" then
					redactionBars += 1
				end
			end
		end
	end
	scanForSecrets("page " .. s.index)
end

local mark = 0

t.check("the Archive window is registered and opens as a book", function()
	assert(Shell.hasWindow("Archive"), "Archive window registered")
	mark = #Engine.sent
	Shell.open("Archive")
	settle()
	assert(Shell.isOpen("Archive"), "Archive open")
	local s = state()
	assert(s and s.book, "book paginated")
	assert(#s.book.pages > 30, "a real book: " .. #s.book.pages .. " pages")
	assert(not s.geo.single, "desktop shows a spread")
	assert(t.findNamed(gui, "Book") and t.findNamed(gui, "Ribbon") and t.findNamed(gui, "Cover"), "cover, pages and ribbon")
	local blur = t.world.camera:FindFirstChild("SNArchiveBlur")
	assert(blur and blur:IsA("BlurEffect"), "the world behind blurs")
	record()
	assert(seenFigures.lantern, "the turning Lantern on the title page")
end)

t.check("contents: chapters, recovered files, progress, locks with hints, new marks", function()
	local contents = t.findNamed(gui, "Contents")
	assert(contents and contents:IsA("TextButton"), "Contents button")
	t.press(contents)
	settle()
	local s = state()
	assert(s.book.pages[s.index].kind == "contents", "the Contents button opens the contents")
	assert(t.findNamed(gui, "Entry_field_note_kestrel"), "chapter entries listed")
	-- page on to the recovered files
	for _ = 1, 4 do
		if t.findNamed(gui, "Progress") then
			break
		end
		ArchiveWindow.press(Enum.KeyCode.E)
		settle()
	end
	assert(t.findText(gui, `{#FOUND} of {#Archive.FileOrder} recovered`), "progress line")
	local seenLocked, seenFound = 0, 0
	for _ = 1, 3 do
		for _, id in Archive.FileOrder do
			local locked = t.findNamed(gui, "Locked_" .. id)
			local found = t.findNamed(gui, "File_" .. id)
			if foundSet[id] then
				assert(locked == nil, id .. " is found, so it isn't locked")
				if found then
					seenFound += 1
					local badge = t.findNamed(found, "NewBadge")
					if id == "ajkr_first_entry" then
						assert(badge == nil, "a file already read has no new mark")
					else
						assert(badge ~= nil, id .. " has a new mark until read")
					end
				end
			else
				assert(found == nil, id .. " isn't found, so it can't be opened")
				if locked then
					seenLocked += 1
					assert(t.findNamed(locked, "Lock"), id .. " has a drawn lock")
					assert(t.findText(locked, Archive.Files[id].hint), id .. " shows its hint")
					assert(t.findText(locked, Archive.Files[id].title) == nil, id .. " keeps its title hidden")
				end
			end
		end
		if seenLocked + seenFound >= #Archive.FileOrder then
			break
		end
		ArchiveWindow.press(Enum.KeyCode.E)
		settle()
	end
	assert(seenFound == #FOUND, "every found file listed: " .. seenFound)
	assert(seenLocked == #Archive.FileOrder - #FOUND, "every missing file locked: " .. seenLocked)
end)

t.check("pages through every chapter and every recovered file", function()
	local s = state()
	local guard = 0
	while guard < 400 do
		guard += 1
		record()
		local before = s.index
		ArchiveWindow.press(Enum.KeyCode.E)
		settle()
		if s.index == before then
			break
		end
	end
	for _, chapter in Archive.Chapters do
		assert(seenDocs[chapter.id], "read chapter " .. chapter.id)
	end
	for _, id in FOUND do
		assert(seenDocs[id], "read file " .. id)
	end
	for id in Archive.Files do
		if not foundSet[id] then
			assert(not seenDocs[id], "a file not found yet stays out of the book: " .. id)
		end
	end
end)

t.check("every figure builds, in the book and on its own", function()
	for id, figure in Archive.Figures do
		local frame = roblox.Instance.new("Frame")
		local built = ArchiveWindow.buildFigure(frame, id, 420, 210)
		assert(#built:GetDescendants() > 6, `{id} ({figure.style}) draws something`)
		frame:Destroy()
	end
	for id in Archive.Figures do
		local inFoundFile = false
		local inChapter = false
		for _, chapter in Archive.Chapters do
			for _, block in chapter.blocks do
				if typeof(block) == "table" and block.figure == id then
					inChapter = true
				end
			end
		end
		for fileId, file in Archive.Files do
			for _, block in file.blocks or {} do
				if typeof(block) == "table" and block.figure == id and foundSet[fileId] then
					inFoundFile = true
				end
			end
		end
		if inChapter or inFoundFile or id == "lantern" then
			assert(seenFigures[id], "figure shown in the book: " .. id)
		end
	end
end)

t.check("redacted words are black bars and never text", function()
	assert(#leaks == 0, "hidden words reached a label:\n       " .. table.concat(leaks, "\n       "))
	assert(redactionBars >= 4, "the test chapter drew its bars: " .. redactionBars)
	local lines = ArchiveWindow.setText("The director, {{Harold Whitcombe}}, signed it.", 400)
	local bars = 0
	for _, line in lines do
		bars += #line.bars
		for _, run in line.runs do
			assert(not string.find(run.rich, "Harold", 1, true) and not string.find(run.rich, "Whitcombe", 1, true), "hidden words in a run")
		end
	end
	assert(bars >= 1, "a bar for the hidden words")
	local italic = ArchiveWindow.setText("It *settled* <here> & stayed.", 400)
	local text = italic[1].runs[1].rich
	assert(string.find(text, "<i>settled</i>", 1, true), "italics: " .. text)
	assert(string.find(text, "&lt;here&gt;", 1, true) and string.find(text, "&amp;", 1, true), "rich text escaped: " .. text)
end)

t.check("reading progress goes to the server", function()
	task.wait(0.3)
	local reads = {}
	for _, entry in t.sentSince(mark, "ProgressRequest", "ReadLore") do
		reads[entry.args[2]] = entry.args[3]
	end
	assert(reads.procurement_memo ~= nil, "a newly read file is reported")
	assert(reads.before_you_read ~= nil, "a chapter is reported")
	assert(reads.ajkr_first_entry == nil, "a file read before isn't sent again")
	for id, page in reads do
		assert(typeof(page) == "number" and page >= 0 and page == math.floor(page), "page for " .. id)
	end
end)

t.check("keyboard, gamepad and swipe turn pages", function()
	local s = state()
	ArchiveWindow.press(Enum.KeyCode.Q)
	settle()
	ArchiveWindow.press(Enum.KeyCode.Q)
	settle()
	local start = s.index
	ArchiveWindow.press(Enum.KeyCode.E)
	settle()
	assert(s.index == start + 2, `E turns forward a spread ({start} -> {s.index} of {#s.book.pages})`)
	ArchiveWindow.press(Enum.KeyCode.Q)
	settle()
	assert(s.index == start, "Q turns back")
	ArchiveWindow.press(Enum.KeyCode.ButtonL1)
	settle()
	assert(s.index == start - 2, "LB turns back")
	ArchiveWindow.press(Enum.KeyCode.ButtonR1)
	settle()
	assert(s.index == start, "RB turns forward")
	ArchiveWindow.press(Enum.KeyCode.Right)
	settle()
	assert(s.index == start + 2, "the right arrow turns forward")
	ArchiveWindow.press(Enum.KeyCode.Left)
	settle()
	local area = t.findNamed(gui, "Pages")
	Engine.signalOf(area, "InputBegan"):Fire({ UserInputType = Enum.UserInputType.Touch, Position = roblox.Vector3.new(700, 300, 0) })
	Engine.signalOf(area, "InputEnded"):Fire({ UserInputType = Enum.UserInputType.Touch, Position = roblox.Vector3.new(560, 310, 0) })
	settle()
	assert(s.index == start + 2, "a swipe left turns forward")
	t.press(t.findNamed(gui, "Previous"))
	settle()
	assert(s.index == start, "the Previous button turns back")
end)

t.check("text stays inside the margins and the layout passes at 1280x720", function()
	local window = t.findNamed(gui, "Window_Archive")
	t.auditLayout(window, "Archive 1280x720")
	checkMargins("1280x720")
end)

t.check("closing remembers the page and clears the blur", function()
	local s = state()
	local position = s.position
	local before = #Engine.sent
	Shell.close()
	task.wait(0.4)
	local sent = t.sentSince(before, "ProgressRequest", "ReadLore")
	if position.id ~= "" then
		assert(#sent >= 1 and sent[#sent].args[2] == position.id, "the open page is saved on close")
	end
	assert(t.world.camera:FindFirstChild("SNArchiveBlur") == nil, "blur removed")
end)

t.check("phone: one page at a time, and the layout still passes", function()
	t.setScreen(667, 375)
	Shell.open("Archive")
	settle()
	local s = state()
	assert(s.geo.single, "one page on a phone")
	local start = s.index
	ArchiveWindow.press(Enum.KeyCode.E)
	settle()
	assert(s.index == start + 1, "a phone turns one page")
	local window = t.findNamed(gui, "Window_Archive")
	t.auditLayout(window, "Archive 667x375")
	for _ = 1, 30 do
		ArchiveWindow.press(Enum.KeyCode.E)
		settle()
		scanForSecrets("phone")
	end
	checkMargins("667x375")
	assert(#leaks == 0, "no hidden words on the phone either")
	Shell.close()
	t.setScreen(1280, 720)
end)

t.finish()
