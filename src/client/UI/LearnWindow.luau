-- HOW TO PLAY (Shell window "Learn", opened from JEFFERY'S BASE and the dock). Short sections:
-- the lobby, training, fighters and phases, purchases and currency, abilities and targeting,
-- movement, matches, progression. Each shows the real controls for the chosen device
-- (keyboard, gamepad or touch), read from InputController.Bindings. Two buttons: talk to
-- Jeffery again (replays his welcome) and Replay tutorial (starts the guided path again).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local Components = require(script.Parent.Components)
local Shell = require(script.Parent.Shell)
local Theme = require(script.Parent.Theme)
local InputController = require(script.Parent.Parent.Controllers.InputController)

local make = Components.make
local Colors = Theme.Colors

local LearnWindow = {}

-- Each section: id, title, body (short, for complete beginners), keys (binding names or extra key
-- names, shown as key caps for the chosen device). The guided tour only covers the first steps;
-- everything else is here.
LearnWindow.Sections = {
	{
		id = "about", title = "What is SUPERNATURALS?",
		body = "A superpower fighting game. Pick a fighter with its own power, train, then fight other players or the computer. Win to earn Money, Gems and new things for your Locker.",
		keys = {},
	},
	{
		id = "moving", title = "Moving and the camera",
		body = "Walk with the move keys, jump, and hold sprint to run. To look around: hold the right mouse button and move the mouse on a PC, drag the screen on a phone, or use the right stick on a gamepad.",
		keys = { "move", "jump", "SNSprint", "camera" },
	},
	{
		id = "fighting", title = "Attacks, block and dodge",
		body = "A light attack is quick. A heavy attack is slower and hits harder. Hold block to take much less damage. Dodge to roll past a hit. Grab beats a block, and sweep knocks a standing fighter down.",
		keys = { "SNLight", "SNHeavy", "SNBlock", "SNDodge", "SNGrab", "SNSweep" },
	},
	{
		id = "abilities", title = "Abilities and the ultimate",
		body = "Abilities 1 to 3 are on the bar at the bottom. They use energy, then recharge. Your ultimate is the big move: it charges as you fight and a bar shows when it is ready. Lock on to aim at the nearest enemy.",
		keys = { "ability", "ultimate", "SNLock" },
	},
	{
		id = "phases", title = "Phases",
		body = "Phases are stronger forms. The phase meter fills while you fight. When it is full, press the evolve key to transform. Phase 1 is open, later phases unlock as you use a fighter, and training lets you try every phase for free.",
		keys = { "SNEvolve" },
	},
	{
		id = "fighters", title = "Changing fighters",
		body = "Tap your player card at the top, or the FIGHTERS button. Pick a fighter, then a phase. You can change before a match, not during one. Premium fighters are unlocked in the shop.",
		keys = {},
	},
	{
		id = "places", title = "Where to go",
		body = "You start in the lobby, where fighting is off. The doors lead to the Training Studio, the Test Chambers, the Master Shop, the Calibration Chamber for fighters, the Spectating Lounge, Player Base Street and my own door, Jeffery's Base.",
		keys = {},
	},
	{
		id = "training", title = "Training",
		body = "Walk through the TRAINING STUDIO door to practice on dummies. Every fighter and every phase is free there, and nothing is saved. Practice with Jeffery is a real fight against me, also free.",
		keys = {},
	},
	{
		id = "matches", title = "Fighting for real",
		body = "Walk through the TEST CHAMBERS door or press PLAY, then pick a mode: Duel, Free-for-All, or CPU Practice against the computer. The most knockouts when time runs out wins.",
		keys = { "SNTaunt" },
	},
	{
		id = "money", title = "Money and Gems",
		body = "Money comes from matches and daily challenges. Gems come from your first win each day, fighter level ups and some challenges. Every shop price is shown before you confirm, and nothing is a mystery box.",
		keys = {},
	},
	{
		id = "extras", title = "Gifts, Locker and season pass",
		body = "GIFTS is the gift calendar with something new each day you visit. The LOCKER holds your titles, looks and achievements. The season pass is a 30 tier track of cosmetics you earn by playing.",
		keys = {},
	},
	{
		id = "help", title = "Need help?",
		body = "Press Ask Jeffery and type a question. Replay tutorial shows the guided tour again. For a rude player, press Esc and choose Report in the Roblox menu.",
		keys = {},
	},
}

LearnWindow.Devices = {
	{ id = "keyboard", label = "Keyboard" },
	{ id = "gamepad", label = "Gamepad" },
	{ id = "touch", label = "Touch" },
}

local function controller()
	local module = require(script.Parent.Parent.Controllers.JefferyController)
	return module.instance
end

-- The key text and its label for one entry, on a device
function LearnWindow.keyFor(key: string, device: string): (string, string)
	for _, binding in InputController.Bindings do
		if binding.name == key then
			local text = if device == "gamepad" then binding.padText elseif device == "touch" then (binding.touchLabel or binding.label) else binding.keyText
			return text, binding.label
		end
	end
	local extra = Tutorial.ExtraKeys[key]
	local label = ({ move = "Move", jump = "Jump", camera = "Camera", ability = "Abilities", ultimate = "Ultimate" })[key] or key
	return (extra and (extra[device] or extra.keyboard)) or key, label
end

local function build(body: Frame)
	local device = "keyboard"
	local instance = controller()
	if instance and instance.input and instance.input.device then
		device = instance.input.device()
	end

	local column = Components.scroll({ Name = "LearnColumn", Padding = 2, Parent = body })
	Components.list(column, Theme.Space.L)

	-- Top: device tabs, then Jeffery's buttons in a row that wraps on narrow screens
	local top = make("Frame", {
		Name = "Top", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 0, Parent = column,
	}, { make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local tabs = Components.segmented(nil, LearnWindow.Devices, device, function(id)
		device = id
		LearnWindow.refresh()
	end, { Name = "DeviceTabs", Size = UDim2.new(0, 340, 0, 44), LayoutOrder = 1, Parent = top })
	local buttons = make("Frame", {
		Name = "Buttons", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2, Parent = top,
	}, { make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}) })
	local ask = Components.button("Ask Jeffery", {
		Name = "AskButton", Variant = "Primary", KeepCase = true, LayoutOrder = 1, Size = UDim2.fromOffset(170, 44), Parent = buttons,
	}, function()
		Shell.open("AskJeffery")
	end)
	local practice = Components.button("Practice with Jeffery", {
		Name = "PracticeButton", Variant = "Secondary", KeepCase = true, LayoutOrder = 2, Size = UDim2.fromOffset(210, 44), Parent = buttons,
	}, function()
		local ok, module = pcall(require, script.Parent.Parent.Controllers.PracticeController)
		if ok and module.instance then
			Shell.close()
			module.instance:openWindow()
		end
	end)
	local replay = Components.button("Replay tutorial", {
		Name = "ReplayButton", Variant = "Secondary", KeepCase = true, LayoutOrder = 3, Size = UDim2.fromOffset(170, 44), Parent = buttons,
	}, function()
		local c = controller()
		if c then
			Shell.close()
			c:replayTutorial()
		end
	end)
	local _ = { tabs, ask, replay, practice }

	local cards: { [string]: Frame } = {}
	for order, section in LearnWindow.Sections do
		local card = make("Frame", {
			Name = "Section_" .. section.id, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Colors.PanelLight, BackgroundTransparency = 0.3,
			BorderSizePixel = 0, Parent = column,
		}, { Components.corner(), Components.stroke(Colors.Stroke, 1, 0.7), Components.padding(16, 16, 16, 16) })
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })
		Components.text({ Name = "Heading", Text = section.title, Style = "Heading", LayoutOrder = 1, Parent = card })
		Components.text({ Name = "Body", Text = section.body, Style = "Body", Wrap = true, Color = Colors.TextDim, LayoutOrder = 2, Parent = card })
		if #section.keys > 0 then
			local row = make("Frame", {
				Name = "Controls", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1, Parent = card,
			}, { make("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, 16),
				VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
			}) })
			cards[section.id] = row
		end
	end

	function LearnWindow.refresh()
		for _, section in LearnWindow.Sections do
			local row = cards[section.id]
			if row then
				for _, child in row:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
				for order, key in section.keys do
					local text, label = LearnWindow.keyFor(key, device)
					local item = make("Frame", {
						Name = "Control_" .. key, LayoutOrder = order, Size = UDim2.fromOffset(0, 32),
						AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Parent = row,
					}, { make("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
						VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
					}) })
					Components.keycap(text, { LayoutOrder = 1, Parent = item })
					Components.text({
						Name = "Label", Text = label, Style = "Caption", LayoutOrder = 2,
						Size = UDim2.fromOffset(Components.textWidth(label, 14) + 8, 24), Parent = item,
					})
				end
			end
		end
	end
	LearnWindow.refresh()

	return {
		onOpen = function()
			local c = controller()
			if c and c.input and c.input.device then
				device = c.input.device()
				tabs.set(device, false)
				LearnWindow.refresh()
			end
		end,
	}
end

function LearnWindow.register()
	-- The chat panel opened by the Ask Jeffery button and by Jeffery's prompt in the hall
	require(script.Parent.AskJefferyWindow).register()
	Shell.registerWindow("Learn", {
		title = "How to Play",
		label = "LEARN",
		icon = "learn",
		order = 6,
		build = build,
	})
end

return LearnWindow
