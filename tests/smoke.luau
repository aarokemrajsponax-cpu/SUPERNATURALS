-- Runs real game code against the stand-in engine (tests/smoke/Engine.luau):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke.luau build/game.rbxl
-- Covers: arenas, every holiday's decorations, the interface components, the
-- Shell with every window (opened, every button pressed), toasts, confirms,
-- modes and screen sizes, the HUD and match HUD, the owner panel, every admin
-- event's visuals, and the client's combat-event handling. Any invalid
-- property, wrong value type or runtime error fails.

local process = require("@lune/process")

local Engine = require("./smoke/Engine")

local placePath = process.args[1] or "build/game.rbxl"
local world = Engine.load(placePath)
local game = world.game
local task = Engine.task
local roblox = require("@lune/roblox") :: any
local Vector3, CFrame, Color3 = roblox.Vector3, Engine.CFrame, roblox.Color3

local passed, failed = 0, 0
local function check(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("ok   " .. name)
	else
		failed += 1
		print("FAIL " .. name)
		print("     " .. tostring(err))
	end
end

local function count(root, className: string): number
	local total = 0
	for _, item in root:GetDescendants() do
		if item:IsA(className) then
			total += 1
		end
	end
	return total
end

-- Server: arenas ----------------------------------------------------------------------
local services = {}
check("ArenaService builds the training ground and arenas", function()
	local ArenaService = world.require(world.find("ServerScriptService.Server.Services.ArenaService"))
	services.ArenaService = ArenaService
	ArenaService:Init(services)
	ArenaService:Start()
	local first = ArenaService:reserve()
	local second = ArenaService:reserve()
	assert(first and second and first ~= second, "two arenas for two matches")
	assert(#first.spawns == 4, "four spawns")
	ArenaService:release(first)
	assert(ArenaService:reserve() == first, "released arenas are reused")
	assert(ArenaService:isOutOfBounds(first, first.center + Vector3.new(0, -50, 0)), "falling is out of bounds")
	assert(not ArenaService:isOutOfBounds(first, first.center + Vector3.new(0, 3, 0)), "the middle is in bounds")
	print(`     arenas: {count(world.workspace.Arenas, "BasePart")} parts, training ground: {count(world.workspace.TrainingGround, "BasePart")} parts`)
end)

-- Server: seasonal decorations --------------------------------------------------------------
check("the Nexus lobby builds: plaza, gates with prompts, statues, spawn", function()
	local Nexus = world.require(world.find("ServerScriptService.Server.World.Nexus"))
	local folder = world.Instance.new("Folder")
	folder.Name = "NexusTest"
	local spawn = Nexus.build(folder)
	assert(spawn and spawn:IsA("SpawnLocation") and spawn.Enabled, "a spawn on the dais")
	local prompts = 0
	for _, item in folder:GetDescendants() do
		if item:IsA("ProximityPrompt") then
			prompts += 1
			assert(typeof(item:GetAttribute("Action")) == "string", "every gate says what it does")
			assert(item.KeyboardKeyCode ~= roblox.Enum.KeyCode.E and item.KeyboardKeyCode ~= roblox.Enum.KeyCode.F, "gate keys don't clash with combat keys")
		end
	end
	assert(prompts == #Nexus.Gates, `one prompt per gate ({prompts})`)
	local statues = 0
	for _, child in folder:GetChildren() do
		if string.sub(child.Name, 1, 7) == "Statue_" then
			statues += 1
		end
	end
	assert(statues == 8, "eight statues, one per power")
	local parts = count(folder, "BasePart")
	assert(parts < 1600, `lobby part budget ({parts})`)
	print(`     nexus: {parts} parts`)
	folder:Destroy()
end)

check("every holiday's decorations build without errors", function()
	local SeasonalDecor = world.require(world.find("ServerScriptService.Server.SeasonalDecor"))
	for _, id in { "Halloween", "Thanksgiving", "Christmas", "NewYears", "Valentines", "StPatricks", "Easter" } do
		SeasonalDecor.build(id)
		local folder = world.workspace:FindFirstChild("SeasonalDecor")
		assert(folder, id .. " made no folder")
		local parts = count(folder, "BasePart")
		assert(parts > 20, `{id} only made {parts} parts`)
		print(`     {id}: {parts} parts`)
		SeasonalDecor.clear()
	end
end)

-- Client: UI ----------------------------------------------------------------------------------
local screen = world.Instance.new("ScreenGui")
screen.Parent = world.localPlayer.PlayerGui

check("HUD builds and updates", function()
	local Hud = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.UI.Hud"))
	local Input = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Controllers.InputController"))
	local hud = Hud.build(screen, Input.Bindings, function()
		return "keyboard"
	end, function()
		return 50
	end)
	hud.update()
	assert(hud.abilityRow and hud.abilityRow:IsA("Frame"), "the HUD returns an empty ability row")
	assert(hud.abilityRow:FindFirstChildOfClass("UIListLayout"), "the ability row lays buttons out in a row")
	assert(hud.abilityRow.Size.X.Offset >= 6 * 64, "the ability row has room for six 64px buttons")
end)

local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
local Vector2, UDim2 = roblox.Vector2, roblox.UDim2

local function press(button)
	Engine.signalOf(button, "Activated"):Fire()
end

local function findNamed(root, name: string)
	for _, item in root:GetDescendants() do
		if item.Name == name then
			return item
		end
	end
	return nil
end

local function findText(root, text: string)
	for _, item in root:GetDescendants() do
		if (item:IsA("TextLabel") or item:IsA("TextButton")) and item.Text == text then
			return item
		end
	end
	return nil
end

local function sentSince(start: number, remote: string, first: any?)
	local found = {}
	for index = start + 1, #Engine.sent do
		local entry = Engine.sent[index]
		if entry.remote == remote and (first == nil or entry.args[1] == first) then
			table.insert(found, entry)
		end
	end
	return found
end

-- Every non-scaled text must wrap, cut off with "…" or grow to fit, and every
-- control a finger can press must be at least 44 tall
local function auditLayout(root, label: string)
	local loose, small = {}, {}
	for _, item in root:GetDescendants() do
		if (item:IsA("TextLabel") or item:IsA("TextButton")) and item.Text ~= "" and not item.TextScaled then
			local fits = item.TextWrapped or item.TextTruncate ~= roblox.Enum.TextTruncate.None or item.AutomaticSize ~= roblox.Enum.AutomaticSize.None
			-- Short fixed glyphs in fixed boxes (icons, +, ✕, key hints, digits) are sized for their box
			if not fits and utf8.len(item.Text) > 3 then
				table.insert(loose, item:GetFullName() .. ` "{item.Text}"`)
			end
		end
		if item:IsA("GuiButton") and item.Selectable and item.Size.Y.Scale == 0 and item.Size.Y.Offset < 44 then
			table.insert(small, item:GetFullName() .. " " .. tostring(item.Size.Y.Offset))
		end
	end
	assert(#loose == 0, `{label}: text that can overflow its box:\n       ` .. table.concat(loose, "\n       "))
	assert(#small == 0, `{label}: touch targets under 44px:\n       ` .. table.concat(small, "\n       "))
end

check("components: numbers, prices and every building block", function()
	local Components = world.require(world.find(CLIENT .. "UI.Components"))
	local Theme = world.require(world.find(CLIENT .. "UI.Theme"))
	local f = Components.formatNumber
	for input, expected in { [0] = "0", [999] = "999", [1000] = "1,000", [6666] = "6,666", [9999] = "9,999", [12000] = "12,000", [1234567] = "1,234,567", [-1500] = "-1,500", [12.6] = "13" } do
		assert(f(input) == expected, `formatNumber({input}) = {f(input)}, expected {expected}`)
	end
	assert(f(0 / 0) == "0" and f(math.huge) == "0", "NaN and infinity show as 0")

	local holder = world.Instance.new("Frame")
	holder.Parent = screen
	-- Robux prices from the owner: Corruption 6,666, Syntax 9,999, Admin 12,000
	for robux, text in { [6666] = "R$ 6,666", [9999] = "R$ 9,999", [12000] = "R$ 12,000" } do
		local price = Components.price(holder, { robux = robux })
		assert(findText(price, text), "price shows " .. text)
	end
	local mixed = Components.price(holder, { money = 1500, gems = 40 })
	assert(findText(mixed, "💵 1,500") and findText(mixed, "💎 40"), "money and gems prices")
	assert(findText(Components.price(holder, {}), "FREE"), "an empty price is free")

	for _, style in { "Micro", "Caption", "Body", "Label", "Heading", "Title", "Display" } do
		local label = Components.text({ Text = style, Style = style, Parent = holder })
		assert(label.TextSize == Theme.TextStyles[style].size, style .. " uses its fixed size")
		assert(label.TextTruncate == roblox.Enum.TextTruncate.AtEnd, "single lines cut off with …")
	end
	local paragraph = Components.text({ Text = "A long paragraph", Wrap = true, Parent = holder })
	assert(paragraph.TextWrapped and paragraph.AutomaticSize == roblox.Enum.AutomaticSize.Y, "paragraphs wrap and grow")
	-- Older callers: TextScaled labels and buttons, legacy fonts upgraded to Builder Sans
	local legacy = Components.label("Old", { Font = Theme.Fonts.Title, MaxTextSize = 20, Parent = holder })
	assert(legacy.TextScaled and legacy.FontFace.Weight == roblox.Enum.FontWeight.ExtraBold, "legacy labels still scale, in Builder Sans")
	local clicks = 0
	for _, variant in { "Primary", "Secondary", "Ghost", "Danger", "Gold" } do
		local button = Components.button(variant, { Variant = variant, Parent = holder }, function()
			clicks += 1
		end)
		assert(button.Selectable and not button.TextScaled, variant .. " buttons are fixed-size and selectable")
		Engine.signalOf(button, "MouseEnter"):Fire()
		Engine.signalOf(button, "SelectionGained"):Fire()
		Engine.signalOf(button, "InputBegan"):Fire({ UserInputType = roblox.Enum.UserInputType.MouseButton1, KeyCode = roblox.Enum.KeyCode.Unknown })
		Engine.signalOf(button, "InputEnded"):Fire({ UserInputType = roblox.Enum.UserInputType.MouseButton1, KeyCode = roblox.Enum.KeyCode.Unknown })
		Engine.signalOf(button, "MouseLeave"):Fire()
		press(button)
		Components.setDisabled(button, true)
		Engine.signalOf(button, "Attribute:SNDisabled"):Fire()
		press(button)
		Components.setDisabled(button, false)
		Engine.signalOf(button, "Attribute:SNDisabled"):Fire()
	end
	assert(clicks == 5, `disabled buttons ignore clicks ({clicks} clicks)`)
	local old = Components.button("Legacy", { Accent = Theme.Colors.Danger, Parent = holder })
	assert(old.TextScaled and old:FindFirstChildOfClass("UITextSizeConstraint"), "legacy buttons still scale")

	local tile = Components.iconTile("⚔️", 40, Theme.Colors.Purple)
	assert(tile.Size.X.Offset == 40, "icon tiles are fixed size")
	local frame, body, parts = Components.window({ Title = "Test", Icon = "🧪", Parent = holder })
	assert(frame and body and parts.close and parts.title.Text == "TEST", "window chrome")
	local picked
	local cardFrame, card = Components.card({ Icon = "🎯", Title = "Card", Body = "Body", Badge = "NEW", Parent = holder, onClick = function()
		picked = true
	end })
	press(cardFrame)
	card.setSelected(true)
	card.setDisabled(true)
	picked = false
	press(cardFrame)
	assert(card.isSelected() and card.isDisabled() and picked == false, "cards select and disable")
	local chosen = {}
	local tabs = Components.tabs(holder, { { id = "a", label = "One", icon = "1️⃣" }, { id = "b", label = "Two" } }, function(id)
		table.insert(chosen, id)
	end)
	press(findNamed(tabs.frame, "Tab_b"))
	assert(tabs.current() == "b" and chosen[1] == "a" and chosen[2] == "b", "tabs select")
	local scroll = Components.scroll({ Padding = 8, Parent = holder })
	Components.list(scroll, 8)
	Components.grid(holder, Vector2.new(100, 60), 8)
	local _, setProgress = Components.progress({ Label = "XP", Value = "0 / 100", Parent = holder }, Theme.Colors.Gold)
	setProgress(0.5, "50 / 100")
	local toggled
	local toggleRow, setToggle = Components.toggle("Shake", true, function(value)
		toggled = value
	end, { Description = "Shake the camera", Parent = holder })
	press(toggleRow)
	assert(toggled == false, "toggles flip")
	setToggle(true)
	local slid
	local slider = Components.slider("Volume", 0, 1, 0.05, 0.5, function(value)
		slid = value
	end, { Format = function(v)
		return `{math.floor(v * 100 + 0.5)}%`
	end, Parent = holder })
	press(findNamed(slider, "Plus"))
	assert(slid == 0.55, `slider + steps up (got {slid})`)
	press(findNamed(slider, "Minus"))
	press(findNamed(slider, "Minus"))
	assert(slid == 0.45, `slider − steps down (got {slid})`)
	assert(findText(slider, "45%"), "slider shows its value")
	Components.badge("OWNED", Theme.Colors.Success).Parent = holder
	Components.divider({ Parent = holder })
	task.wait(0.1)
	holder:Destroy()
end)

check("interface: shell, play and settings windows, toasts, confirms, modes, screen sizes", function()
	local errorsBefore = #Engine.errors
	local Input = world.require(world.find(CLIENT .. "Controllers.InputController"))
	local deviceKind = "keyboard"
	local fakeInput = {
		Bindings = Input.Bindings,
		device = function()
			return deviceKind
		end,
	}
	local UIController = world.require(world.find(CLIENT .. "Controllers.UIController"))
	local Abilities = world.require(world.find(CLIENT .. "Controllers.AbilityController"))
	Abilities:Init({ PowerFxController = { predict = function() end }, InputController = fakeInput })
	UIController:Init({
		InputController = fakeInput,
		AbilityController = Abilities,
		EffectsController = {
			currentGuard = function()
				return 50
			end,
		},
	})
	UIController:Start()
	local Shell = world.require(world.find(CLIENT .. "UI.Shell"))
	local Settings = world.require(world.find(CLIENT .. "Settings"))
	local gui = world.localPlayer.PlayerGui:FindFirstChild("SNInterface")
	assert(gui, "the interface ScreenGui exists")
	local scales = 0
	for _, child in gui:GetChildren() do
		if child:IsA("UIScale") then
			scales += 1
		end
	end
	assert(scales == 1, `one UIScale for the whole interface (found {scales})`)
	local uiScale = gui:FindFirstChildOfClass("UIScale")
	assert(math.abs(uiScale.Scale - 1) < 1e-6, "1280x720 is scale 1")
	assert(findNamed(gui, "Nav_Play") and findNamed(gui, "Nav_Settings"), "dock has Play and Settings")
	assert(UIController.hud and UIController.hud.abilityRow, "other controllers can reach the HUD's ability row")

	-- Profile: wallet, power, the not-saving banner and server toasts
	local dataEvent = world.find("ReplicatedStorage.Remotes.DataEvent")
	local function fireData(kind, data)
		Engine.signalOf(dataEvent, "OnClientEvent"):Fire(kind, data)
	end
	fireData("Profile", {
		currencies = { money = 12000, gems = 6666 },
		selected = { power = "StrongDude", degree = 1 },
		settings = { cameraShake = true, uiScale = 1 },
	})
	local wallet = findNamed(gui, "Wallet")
	assert(findText(wallet, "12,000") and findText(wallet, "6,666"), "wallet shows money and gems with separators")
	assert(findText(gui, "⚡ Strong Dude  ·  Degree 1"), "player card shows the selected power")
	fireData("Profile", { currencies = { money = 12500, gems = 6666 }, selected = { power = "StrongDude", degree = 2 } })
	Engine.step(game, 60, 0.05)
	assert(findText(wallet, "12,500"), "wallet counts up to the new balance")
	fireData("Persistence", { saving = false })
	assert(findNamed(gui, "SavingBanner").Visible, "banner shows when progress isn't saved")
	assert(findText(gui, "Progress isn't being saved right now (Studio without API access)"), "banner text")
	fireData("Persistence", { saving = true })
	assert(not findNamed(gui, "SavingBanner").Visible, "banner hides when saving works")
	fireData("Toast", { text = "Welcome to SUPERNATURALS!", kind = "success" })
	assert(findText(gui, "Welcome to SUPERNATURALS!"), "server toasts appear")

	-- Play window
	local start = #Engine.sent
	press(findNamed(gui, "Nav_Play"))
	assert(Shell.isOpen("Play") and Shell.isOpen(), "dock opens Play")
	local play = findNamed(gui, "Window_Play")
	assert(play and play.Visible, "Play window is visible")
	task.wait(0.05)
	for _, id in { "FreeForAll", "Practice", "Training", "Duel" } do
		press(findNamed(play, "Mode_" .. id))
	end
	assert(findText(play, "DUEL") and findText(play, "3:00") and findText(play, "Sudden death (1:00)"), "details show the Duel rules from the config")
	assert(findNamed(play, "MatchOptions"), "a slot is reserved for arena and CPU options")
	press(findNamed(play, "Action"))
	assert(#sentSince(start, "MatchRequest", "Queue") == 1 and sentSince(start, "MatchRequest", "Queue")[1].args[2] == "Duel", "Find a duel queues for Duel")
	assert(not Shell.isOpen(), "queueing closes the window")

	-- Queue pill: shows, counts, cancels
	local matchEvent = world.find("ReplicatedStorage.Remotes.MatchEvent")
	local function fireMatch(kind, data)
		Engine.signalOf(matchEvent, "OnClientEvent"):Fire(kind, data)
	end
	fireMatch("Queue", { mode = "Duel", displayName = "Duel", queued = 1, needed = 2, max = 2 })
	local pill = findNamed(gui, "QueuePill")
	assert(pill.Visible, "queue pill shows")
	Engine.step(game, 10, 0.05)
	assert(findText(pill, "1/2 fighters"), "queue pill shows the count")
	fireMatch("Queue", { mode = "FreeForAll", displayName = "Free-for-All", queued = 3, needed = 3, max = 4, startsAt = 1010 })
	Engine.step(game, 4, 0.05)
	task.wait(1.1)
	start = #Engine.sent
	press(findNamed(pill, "Cancel"))
	assert(#sentSince(start, "MatchRequest", "LeaveQueue") == 1, "Cancel leaves the queue")
	-- While queued for Duel the Play window offers Cancel search instead
	fireMatch("Queue", { mode = "Duel", displayName = "Duel", queued = 1, needed = 2, max = 2 })
	Shell.open("Play", { mode = "Duel" })
	assert(findNamed(play, "CancelSearch").Visible and not findNamed(play, "Action").Visible, "searching shows Cancel search")
	fireMatch("Queue", nil)
	assert(findNamed(play, "Action").Visible, "Cancel search goes away when the queue ends")
	task.wait(0.7)
	press(findNamed(play, "Mode_Training"))
	start = #Engine.sent
	press(findNamed(play, "Action"))
	local travel = sentSince(start, "MatchRequest", "Travel")
	assert(#travel == 1 and travel[1].args[2] == "Training", "Go to training travels there")
	task.wait(0.7)
	Shell.open("Play")
	start = #Engine.sent
	press(findNamed(play, "Spawn"))
	travel = sentSince(start, "MatchRequest", "Travel")
	assert(#travel == 1 and travel[1].args[2] == "Lobby", "Back to spawn travels to the lobby")
	task.wait(0.2)
	assert(pill.Visible == false, "pill hides after the queue ends")

	-- Settings window: every toggle and slider writes through Settings
	Shell.open("Settings")
	local settings = findNamed(gui, "Window_Settings")
	assert(Shell.isOpen("Settings") and settings, "Settings opens")
	for _, key in { "cameraShake", "reducedEffects", "intenseEffects", "damageNumbers" } do
		local before = Settings.get(key)
		press(findNamed(settings, "Toggle_" .. key))
		assert(Settings.get(key) == not before, key .. " toggles")
	end
	press(findNamed(findNamed(settings, "Slider_musicVolume"), "Minus"))
	assert(math.abs(Settings.get("musicVolume") - 0.45) < 1e-6, "music volume steps down")
	press(findNamed(findNamed(settings, "Slider_sfxVolume"), "Plus"))
	assert(math.abs(Settings.get("sfxVolume") - 0.85) < 1e-6, "sound volume steps up")
	press(findNamed(findNamed(settings, "Slider_cameraSensitivity"), "Plus"))
	assert(math.abs(Settings.get("cameraSensitivity") - 1.1) < 1e-6, "camera sensitivity is stored")
	press(findNamed(findNamed(settings, "Slider_uiScale"), "Plus"))
	assert(math.abs(Settings.get("uiScale") - 1.05) < 1e-6, "interface size steps up")
	assert(math.abs(uiScale.Scale - 1.05) < 1e-6, `interface size rescales everything ({uiScale.Scale})`)
	Settings.set("uiScale", 1)
	-- A value arriving from elsewhere shows in the open window
	Settings.set("musicVolume", 0.2)
	assert(findText(findNamed(settings, "Slider_musicVolume"), "20%"), "settings window follows Settings.changed")
	auditLayout(settings, "Settings window")
	auditLayout(play, "Play window")
	press(findNamed(settings, "Close"))
	assert(not Shell.isOpen(), "✕ closes the window")

	-- Lazily built extra windows, update ticks, a window that fails to build
	local ticks, opened, closed = 0, nil, false
	Shell.registerWindow("Probe", {
		title = "Probe",
		icon = "🧪",
		order = 50,
		nav = false,
		size = Vector2.new(500, 300),
		build = function(body, api)
			assert(api.close and api.toast and api.confirm and api.open, "windows get the api")
			return {
				onOpen = function(args)
					opened = args
				end,
				onClose = function()
					closed = true
				end,
				update = function()
					ticks += 1
				end,
			}
		end,
	})
	assert(not findNamed(gui, "Window_Probe"), "windows build lazily")
	assert(not findNamed(gui, "Nav_Probe"), "nav = false keeps it out of the dock")
	Shell.open("Probe", { from = "test" })
	Engine.step(game, 10, 0.05)
	assert(opened and opened.from == "test" and ticks > 0, "onOpen gets args and update ticks")
	Shell.open("Play")
	assert(closed and Shell.isOpen("Play") and not Shell.isOpen("Probe"), "opening another window closes the first")
	Shell.toggle("Play")
	assert(not Shell.isOpen(), "toggle closes")
	Shell.registerWindow("Broken", { title = "Broken", icon = "💥", order = 60, nav = false, build = function()
		error("intentional test failure")
	end })
	Shell.open("Broken")
	assert(not Shell.isOpen(), "a window that fails to build doesn't open")

	-- Nav badges
	Shell.setNavBadge("Play", "!")
	local badge = findNamed(findNamed(gui, "Nav_Play"), "Badge")
	assert(badge.Visible and findText(badge, "!"), "nav badge shows")
	Shell.setNavBadge("Play", nil)
	assert(not badge.Visible, "nav badge clears")

	-- Toasts: every kind, only the newest few stay
	for _, kind in { "info", "success", "error", "reward", "bogus" } do
		Shell.toast("Toast " .. kind, kind)
	end
	local toastCount = 0
	for _, child in findNamed(gui, "Stack"):GetChildren() do
		if child:IsA("Frame") then
			toastCount += 1
		end
	end
	assert(toastCount <= 4, `at most four toasts at once ({toastCount})`)

	-- Confirm: price shown first, confirm and cancel both work
	local result
	Shell.confirm({ title = "Unlock Admin Powers?", body = "Opens the Roblox purchase prompt.", price = { robux = 12000 }, onConfirm = function()
		result = "yes"
	end, onCancel = function()
		result = "no"
	end })
	local modal = findNamed(gui, "ShellModal")
	assert(findText(modal, "R$ 12,000"), "confirm shows the Robux price")
	auditLayout(modal, "Confirm dialog")
	press(findNamed(modal, "ConfirmDim"):FindFirstChild("Dialog"):FindFirstChild("Buttons"):FindFirstChild("Confirm"))
	assert(result == "yes", "Buy confirms")
	Shell.confirm({ title = "Kick everyone?", danger = true, onConfirm = function()
		result = "kicked"
	end, onCancel = function()
		result = "kept"
	end })
	task.wait(0.05)
	local dialogs = {}
	for _, child in modal:GetChildren() do
		if child.Name == "ConfirmDim" then
			table.insert(dialogs, child)
		end
	end
	press(dialogs[#dialogs]:FindFirstChild("Dialog"):FindFirstChild("Buttons"):FindFirstChild("Cancel"))
	assert(result == "kept", "Cancel cancels")
	Shell.confirm({ title = "Replace me", price = { gems = 50 }, onConfirm = function() end, onCancel = function()
		result = "replaced"
	end })
	Shell.confirm({ title = "Newer", onConfirm = function() end })
	assert(result == "replaced", "a new confirm cancels the old one")
	Shell.setMode("Match")
	assert(result == "replaced", "entering a match cancels the open confirm")

	-- Modes
	assert(not findNamed(gui, "Dock").Visible and findNamed(gui, "SmallBar").Visible, "Match hides the dock, small top bar")
	Shell.open("Play")
	assert(not Shell.isOpen("Play"), "no lobby windows during a match")
	Shell.open("Settings")
	assert(Shell.isOpen("Settings"), "settings still open from the match top bar")
	Shell.close()
	Shell.setMode("Cinematic")
	assert(gui.Enabled == false, "Cinematic hides everything")
	Shell.setMode("Editor")
	assert(gui.Enabled and not findNamed(gui, "Dock").Visible and findNamed(gui, "Wallet").Visible, "Editor hides the dock")
	Shell.setMode("Spectate")
	Shell.setMode("Lobby")
	assert(findNamed(gui, "Dock").Visible and findNamed(gui, "PlayerCard").Visible, "Lobby shows the dock and top bar")

	-- Screen sizes: phone (compact dock), small tablet, 4K, and back
	local camera = world.camera
	for _, size in { Vector2.new(844, 390), Vector2.new(1024, 768), Vector2.new(3840, 2160), Vector2.new(1280, 720) } do
		camera.ViewportSize = size
		Engine.signalOf(camera, "Property:ViewportSize"):Fire()
		local expected = math.clamp(math.min(size.X / 1280, size.Y / 720), 0.62, 1.25)
		assert(math.abs(uiScale.Scale - expected) < 1e-6, `scale at {size.X}x{size.Y} is {uiScale.Scale}, expected {expected}`)
		Shell.open("Play")
		local window = findNamed(gui, "Window_Play")
		local usableHeight = (size.Y - 58) / uiScale.Scale
		assert(window.Size.Y.Offset <= usableHeight, `the window fits the screen at {size.X}x{size.Y}`)
		if size.X == 844 then
			assert(findNamed(findNamed(gui, "Nav_Play"), "Label").Visible == false, "phones get an icons-only dock")
		end
		Shell.close()
	end

	-- Gamepad: opening a window selects its first control
	deviceKind = "gamepad"
	Shell.open("Settings")
	local selected = world.game:GetService("GuiService").SelectedObject
	assert(selected and selected:IsDescendantOf(findNamed(gui, "Window_Settings")), "gamepad selection starts inside the window")
	deviceKind = "keyboard"
	Shell.close()

	-- The match flow through the real event handlers
	fireMatch("Notice", { text = "All arenas are busy. Try again in a moment." })
	assert(findText(gui, "All arenas are busy. Try again in a moment."), "lobby notices become toasts")
	local snapshot = {
		id = "m",
		mode = "Duel",
		modeName = "Duel",
		arena = "Proving Grounds",
		phase = "Countdown",
		phaseEndsAt = 1005,
		participants = {
			{ id = "Player:1", name = "Tester", score = 0, knockouts = 0, left = false, npc = false },
			{ id = "Player:2", name = "AVeryLongDisplayNameThatMustBeCut", score = 0, knockouts = 0, left = false, npc = false },
		},
	}
	fireMatch("State", snapshot)
	assert(Shell.getMode() == "Match", "a match switches the shell to Match mode")
	Engine.step(game, 5, 0.05)
	local active = table.clone(snapshot)
	active.phase = "Active"
	active.phaseEndsAt = 1180
	fireMatch("State", active)
	fireMatch("Knockout", { victim = "AVeryLongDisplayNameThatMustBeCut", credited = "Tester" })
	fireMatch("Notice", { text = "SUDDEN DEATH! Next knockout wins." })
	assert(findNamed(gui, "Notice").Visible, "in-match notices show in the middle")
	Engine.step(game, 5, 0.05)
	fireMatch("Results", {
		reason = "TimeUp",
		draw = false,
		winners = { "Tester" },
		winnerIds = { "Player:1" },
		ranking = {
			{ id = "Player:1", name = "Tester", score = 1, knockouts = 1, deaths = 0, left = false },
			{ id = "Player:2", name = "AVeryLongDisplayNameThatMustBeCut", score = -1, knockouts = 0, deaths = 1, left = true },
		},
		returnsAt = 1200,
	})
	Engine.step(game, 5, 0.05)
	assert(findText(gui, "VICTORY") and findText(gui, "🏆  Winner: Tester"), "results banner")
	auditLayout(findNamed(gui, "Results"), "Results")
	auditLayout(findNamed(gui, "MatchTop"), "Match top bar")
	start = #Engine.sent
	press(findNamed(findNamed(gui, "Results"), "Back"))
	assert(#sentSince(start, "MatchRequest", "ReturnToLobby") == 1, "Back to lobby asks the server")
	fireMatch("Ended", nil)
	assert(Shell.getMode() == "Lobby" and findNamed(gui, "Dock").Visible, "the end of a match brings the lobby back")

	-- Whole-interface layout audit, then nothing may have errored in scheduled code
	task.wait(0.3)
	Engine.step(game, 5, 0.05)
	auditLayout(findNamed(gui, "ShellChrome"), "Top bar and dock")
	auditLayout(findNamed(gui, "Hud"), "HUD")
	local newErrors = #Engine.errors - errorsBefore
	-- The intentionally broken window's error is caught by the Shell, not scheduled code
	assert(newErrors == 0, `{newErrors} errors in scheduled code:\n` .. table.concat(Engine.errors, "\n", errorsBefore + 1))
	print(`     interface: {count(gui, "TextButton")} buttons, {count(gui, "TextLabel")} labels`)
end)

check("powers window, ability bar and defense prompts", function()
	local errorsBefore = #Engine.errors
	local Shell = world.require(world.find(CLIENT .. "UI.Shell"))
	local gui = world.localPlayer.PlayerGui:FindFirstChild("SNInterface")
	local dataEvent = world.find("ReplicatedStorage.Remotes.DataEvent")
	Engine.signalOf(dataEvent, "OnClientEvent"):Fire("Profile", {
		currencies = { money = 5000, gems = 120 },
		selected = { power = "StrongDude", degree = 1 },
		powers = { StrongDude = { xp = 500, abilities = { Heave = true } } },
		loadouts = {},
		passes = {},
		settings = {},
	})
	Shell.open("Powers")
	assert(Shell.isOpen("Powers"), "the Powers window opens")
	local window = findNamed(gui, "PowerList")
	assert(window, "the power list exists")
	-- Every power card, every degree, every equip button, then save and use
	local start = #Engine.sent
	local cardsPressed = 0
	for _, card in window:GetChildren() do
		if card:IsA("TextButton") then
			press(card)
			cardsPressed += 1
			-- Each degree tab (the panel rebuilds after every press, so look again each time)
			for degree = 1, 3 do
				local detail = findNamed(gui, "PowerDetail")
				for _, button in detail:GetDescendants() do
					if button:IsA("TextButton") and string.find(button.Text, `{degree}  ·`, 1, true) then
						press(button)
						break
					end
				end
				auditLayout(findNamed(gui, "PowerDetail"), "Powers detail")
			end
			auditLayout(findNamed(gui, "PowerActions"), "Powers actions")
		end
	end
	assert(cardsPressed >= 1, "power cards exist")
	-- Back to Strong Dude: equip an owned extra ability, save, use
	for _, card in window:GetChildren() do
		if card:IsA("TextButton") and findText(card, "Strong Dude") then
			press(card)
		end
	end
	local detail = findNamed(gui, "PowerDetail")
	local removeButton = nil
	for _, button in detail:GetDescendants() do
		if button:IsA("TextButton") and button.Text == "REMOVE" then
			removeButton = button
			break
		end
	end
	assert(removeButton, "equipped abilities can be removed")
	press(removeButton)
	detail = findNamed(gui, "PowerDetail")
	local equip = nil
	for _, button in detail:GetDescendants() do
		if button:IsA("TextButton") and button.Text == "EQUIP" then
			equip = button
			break
		end
	end
	assert(equip, "owned abilities can be equipped")
	press(equip)
	press(findText(gui, "SAVE LOADOUT"))
	local saved = sentSince(start, "PowerRequest", "SetLoadout")
	assert(#saved >= 1, "saving sends the loadout")
	press(findText(gui, "USE THIS POWER") or findText(gui, "✓  IN USE"))
	auditLayout(findNamed(gui, "PowerList"), "Power list")
	Shell.close()

	-- Ability bar from the character's attributes
	local character = world.localPlayer.Character
	if not character then
		character = Engine.character("Tester")
		character.Parent = world.workspace
		world.localPlayer.Character = character
	end
	character:SetAttribute("SNPower", "StrongDude")
	character:SetAttribute("SNDegree", 1)
	character:SetAttribute("SNLoadout", "Groundbreaker,TitanGrip,MeteorCharge")
	character:SetAttribute("SNRes", 12)
	character:SetAttribute("SNResMax", 100)
	character:SetAttribute("SNUlt", 100)
	character:SetAttribute("SNCD_TitanGrip", world.workspace:GetServerTimeNow() + 5)
	Engine.step(game, 4, 0.05)
	task.wait(0.1)
	Engine.step(game, 4, 0.05)
	assert(findNamed(gui, "Ability_Groundbreaker") and findNamed(gui, "Ability_WorldBreaker"), "ability buttons and the ultimate")
	assert(findText(gui, "READY"), "a full ultimate says READY")
	assert(findText(gui, "GRIT  12/100"), "the resource meter")
	auditLayout(findNamed(gui, "AbilityBar"), "Ability bar")

	-- Defense prompts: each kind shows, takes a press, and shows a result
	local Defense = world.require(world.find(CLIENT .. "Controllers.DefenseController"))
	Defense:Init({ InputController = { device = function()
		return "keyboard"
	end } })
	Defense:Start()
	local defenseEvent = world.find("ReplicatedStorage.Remotes.DefenseEvent")
	local now = world.workspace:GetServerTimeNow()
	local cues = {
		{ id = "p1", kind = "Prompt", opensAt = now, closesAt = now + 0.6, impactAt = now + 0.6, label = "Groundbreaker" },
		{ id = "t1", kind = "Timing", opensAt = now, closesAt = now + 1, impactAt = now + 0.9, perfectWindow = 0.07, goodWindow = 0.17, label = "World Breaker" },
		{ id = "m1", kind = "Mash", opensAt = now, closesAt = now + 1.4, impactAt = now + 1.4, presses = 6, label = "Titan Grip" },
		{ id = "r1", kind = "Redirect", opensAt = now, closesAt = now + 0.6, impactAt = now + 0.6, label = "Slash Wave" },
	}
	for _, cue in cues do
		Engine.signalOf(defenseEvent, "OnClientEvent"):Fire("Cue", cue)
	end
	Engine.step(game, 3, 0.05)
	local prompts = world.localPlayer.PlayerGui:FindFirstChild("SNDefense")
	assert(prompts and findNamed(prompts, "Timing") and findNamed(prompts, "Mash"), "prompt cards show")
	auditLayout(prompts, "Defense prompts")
	start = #Engine.sent
	press(findNamed(prompts, "Mash"))
	press(findNamed(prompts, "Mash"))
	press(findNamed(prompts, "Timing"))
	press(findNamed(prompts, "Redirect"))
	assert(#sentSince(start, "DefenseInput") == 4, "presses go to the server")
	assert(findText(prompts, "2 / 6"), "mash progress counts presses")
	Engine.signalOf(defenseEvent, "OnClientEvent"):Fire("Result", { id = "t1", kind = "Timing", result = "Perfect" })
	Engine.signalOf(defenseEvent, "OnClientEvent"):Fire("Result", { id = "m1", kind = "Mash", result = "Escaped" })
	Engine.signalOf(defenseEvent, "OnClientEvent"):Fire("Clear", { id = "r1" })
	Engine.signalOf(defenseEvent, "OnClientEvent"):Fire("Result", { id = "p1", kind = "Prompt", result = "Failed" })
	Engine.step(game, 3, 0.05)
	assert(findText(prompts, "PERFECT!") and findText(prompts, "BROKE FREE!"), "results show")
	task.wait(0.8)
	Engine.step(game, 3, 0.05)
	assert(#Engine.errors == errorsBefore, "no errors:\n" .. table.concat(Engine.errors, "\n", errorsBefore + 1))
end)

check("match HUD: countdown, fight, knockouts, results, clear", function()
	local MatchHud = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.UI.MatchHud"))
	local hud = MatchHud.build(screen, function() end)
	local snapshot = {
		id = "m",
		mode = "Duel",
		modeName = "Duel",
		arena = "Proving Grounds",
		phase = "Countdown",
		phaseEndsAt = 1005,
		participants = {
			{ id = "Player:0", name = "Tester", score = 0, knockouts = 0, left = false, npc = false },
			{ id = "Npc:1", name = "Sparring Dummy", score = 0, knockouts = 0, left = false, npc = true },
		},
	}
	hud.setState(snapshot)
	hud.update()
	local active = table.clone(snapshot)
	active.phase = "Active"
	active.phaseEndsAt = 1180
	hud.setState(active)
	hud.update()
	hud.addKnockout({ victim = "Sparring Dummy", credited = "Tester" })
	hud.addKnockout({ victim = "Tester" })
	local sudden = table.clone(active)
	sudden.phase = "SuddenDeath"
	hud.setState(sudden)
	hud.update()
	hud.showResults({
		reason = "TimeUp",
		draw = false,
		winners = { "Tester" },
		winnerIds = { "Player:0" },
		ranking = {
			{ id = "Player:0", name = "Tester", score = 1, knockouts = 1, deaths = 0, left = false },
			{ id = "Npc:1", name = "Sparring Dummy", score = -1, knockouts = 0, deaths = 1, left = false },
		},
		returnsAt = 1200,
	})
	hud.update()
	hud.clear()
end)

check("owner panel builds, opens, and every tab renders", function()
	local OwnerPanel = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.UI.OwnerPanel"))
	local sent = {}
	OwnerPanel.build(screen, function(action, first, second)
		table.insert(sent, { action, first, second })
	end)
	OwnerPanel.setOpen(true)
	Engine.step(game, 3)
	OwnerPanel.toggle()
	local window = screen:FindFirstChild("OwnerPanel")
	assert(window, "panel window exists")
	local buttons = count(window, "TextButton")
	assert(buttons > 40, `only {buttons} buttons in the owner panel`)
	-- Press every button once (danger buttons need two presses, which also works)
	for _, item in window:GetDescendants() do
		if item:IsA("TextButton") then
			Engine.signalOf(item, "Activated"):Fire()
		end
	end
	print(`     owner panel: {buttons} buttons, {#sent} requests sent by pressing them`)
	assert(#sent > 20, "pressing the buttons sends requests")
end)

-- Client: effects ---------------------------------------------------------------------------
check("every admin event's visuals start, animate and stop", function()
	local AdminEvents = world.require(world.find("ReplicatedStorage.Shared.Config.AdminEvents"))
	local folder = world.find("StarterPlayer.StarterPlayerScripts.Client.Effects.AdminEvents")
	for _, id in AdminEvents.Order do
		local handlers = {}
		local running = true
		local context = {
			def = AdminEvents.Events[id],
			center = Vector3.new(0, 0, 0),
			startedAt = 1000,
			endsAt = 1030,
			running = function()
				return running
			end,
			on = function(kind, handler)
				handlers[kind] = handler
			end,
			shake = function() end,
		}
		local stop = world.require(folder:FindFirstChild(id))(context)
		Engine.step(game, 5)
		for kind, handler in handlers do
			local now = 1000
			handler({ position = Vector3.new(3, 0, 4), impactAt = now + 0.01, size = 4 })
			if kind then
				task.wait(0.05)
			end
		end
		Engine.step(game, 5)
		assert(typeof(stop) == "function", id .. " must return a stop function")
		running = false
		stop()
		Engine.step(game, 2)
	end
	task.wait(0.2)
end)

check("Vfx helpers all run", function()
	local Vfx = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Effects.Vfx"))
	local model = world.Instance.new("Model")
	local root = world.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = model
	local arm = world.Instance.new("Part")
	arm.Name = "RightUpperArm"
	arm.Parent = model
	model.Parent = world.workspace
	Vfx.sparks(Vector3.zero, Color3.new(1, 1, 1), 10)
	Vfx.shockwave(Vector3.zero, Color3.new(1, 0, 0), 1, 5, 0.2)
	Vfx.groundRing(Vector3.zero, Color3.new(1, 0, 0), 1, 5, 0.2)
	Vfx.slash(CFrame.new(), Color3.new(1, 1, 1), 4, 25, 0.1)
	Vfx.popup(Vector3.zero, "12", Color3.new(1, 1, 1), 1)
	Vfx.flash(model, Color3.new(1, 1, 1))
	Vfx.afterimage(model, Color3.new(0, 1, 1))
	Vfx.telegraph(root, Color3.new(1, 0, 0), 0.3)
	for _, name in { "LightSwing", "HeavySwing", "Hit", "HeavyHit", "Block", "Parry", "GuardBreak", "Dodge", "Countdown" } do
		Vfx.sound(name, root)
	end
	task.wait(0.1)
end)

check("client combat effects handle every server event", function()
	local controllers = {}
	for _, name in { "CameraController", "EffectsController", "AdminEffectsController" } do
		controllers[name] = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Controllers." .. name))
	end
	for _, controller in controllers do
		if controller.Init then
			controller:Init(controllers)
		end
	end
	for _, controller in controllers do
		if controller.Start then
			task.spawn(controller.Start, controller)
		end
	end
	task.wait(0.05)

	-- Two fighters in the world
	local function fighter(name: string, x: number)
		local model = world.Instance.new("Model")
		model.Name = name
		local root = world.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = CFrame.new(x, 3, 0)
		root.Parent = model
		local head = world.Instance.new("Part")
		head.Name = "Head"
		head.Parent = model
		local humanoid = world.Instance.new("Humanoid")
		humanoid.Parent = model
		model:SetAttribute("DisplayName", name)
		model:SetAttribute("Guard", 60)
		model:SetAttribute("GuardUpdatedAt", 999)
		model.Parent = world.workspace
		world.services.CollectionService:AddTag(model, "SNFighter")
		return model
	end
	local a = fighter("Alpha", 0)
	local b = fighter("Bravo", 4)
	b:SetAttribute("Blocking", true)
	Engine.signalOf(b, "Attribute:Blocking"):Fire()

	local combatEvent = world.find("ReplicatedStorage.Remotes.CombatEvent")
	local fire = function(kind, data)
		Engine.signalOf(combatEvent, "OnClientEvent"):Fire(kind, data)
	end
	for step = 1, 4 do
		fire("Attack", { attacker = a, kind = "Light", step = step, startup = 0.1, active = 0.1 })
	end
	fire("Attack", { attacker = a, kind = "Heavy", step = 1, startup = 0.5, active = 0.14 })
	for _, result in { "Hit", "Blocked", "GuardBreak", "Parried", "Invulnerable" } do
		fire("Hit", { attacker = a, victim = b, result = result, damage = 7, position = Vector3.new(4, 3, 0), heavy = result == "Hit", finisher = true, comboCapped = false })
	end
	fire("Dodge", { fighter = b, direction = Vector3.new(1, 0, 0) })
	fire("Hit", { attacker = "junk", victim = 5, result = "Hit" }) -- malformed data is ignored
	Engine.step(game, 10)
	task.wait(0.4)

	-- Admin visuals for everyone: announcement, an event, ice, auras
	local adminEvent = world.find("ReplicatedStorage.Remotes.AdminEvent")
	Engine.signalOf(adminEvent, "OnClientEvent"):Fire("Announce", { text = "Hello everyone!", from = "Owner" })
	local replicated = game:GetService("ReplicatedStorage")
	replicated:SetAttribute("AdminEventCenter", Vector3.zero)
	replicated:SetAttribute("AdminEventStartedAt", 1000)
	replicated:SetAttribute("AdminEventEndsAt", 1030)
	replicated:SetAttribute("AdminEvent", "MeteorShower")
	replicated:SetAttribute("AdminEventRun", "MeteorShower#1")
	Engine.signalOf(replicated, "Attribute:AdminEventRun"):Fire()
	Engine.signalOf(adminEvent, "OnClientEvent"):Fire("Meteor", { position = Vector3.new(2, 0, 2), impactAt = 1000, size = 4 })
	Engine.step(game, 5)
	replicated:SetAttribute("AdminEvent", "")
	replicated:SetAttribute("AdminEventRun", "")
	Engine.signalOf(replicated, "Attribute:AdminEventRun"):Fire()
	a:SetAttribute("SNIced", true)
	Engine.signalOf(a, "Attribute:SNIced"):Fire()
	a:SetAttribute("SNIced", nil)
	Engine.signalOf(a, "Attribute:SNIced"):Fire()
	task.wait(0.3)
end)

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
