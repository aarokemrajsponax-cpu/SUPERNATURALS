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

-- Each section: id, title, body (short), keys (binding names or extra key names).
LearnWindow.Sections = {
	{
		id = "lobby", title = "The lobby",
		body = "The lobby is the hall you spawn in. Fighting is off here, so it is safe to look around. The doors lead everywhere: Test Chambers for fights, Training Studio for practice, Master Shop, Calibration Chamber for fighters, Spectating Lounge and Player Base Street.",
		keys = { "move", "SNDodge" },
	},
	{
		id = "training", title = "Training",
		body = "Training is free. Every fighter and every phase can be tried on the dummies. Nothing you do there is saved or charged, so experiment.",
		keys = { "SNLight", "SNHeavy", "SNBlock", "SNDodge" },
	},
	{
		id = "fighters", title = "Fighters and phases",
		body = "Open the Calibration Chamber or the Fighters button. Pick a fighter, then a phase. Phase 1 is open and later phases unlock as you play. In a match, fill the phase meter and evolve.",
		keys = { "SNEvolve" },
	},
	{
		id = "money", title = "Purchases and currency",
		body = "Money comes from matches and daily challenges. Gems are the premium currency. Every price is shown before you confirm, and nothing is a mystery box.",
		keys = {},
	},
	{
		id = "abilities", title = "Abilities and targeting",
		body = "Your abilities sit on the bar at the bottom. Press the number, or tap the button. Lock on to the nearest enemy to aim at it, and watch your stamina.",
		keys = { "ability", "SNLock", "SNGrab" },
	},
	{
		id = "movement", title = "Movement",
		body = "Walk, jump and sprint to get around. A dodge is a quick burst that also avoids hits. Sprinting and dodging use stamina.",
		keys = { "move", "jump", "SNSprint", "SNDodge", "camera" },
	},
	{
		id = "matches", title = "Matches",
		body = "Pick a mode in the Test Chambers. Practice against the computer is a safe start. Matches begin in Phase 1, and the last fighter standing or the best score wins.",
		keys = { "SNBlock", "SNTaunt" },
	},
	{
		id = "progress", title = "Progression",
		body = "Matches pay Money and experience. Each fighter levels up with use and unlocks abilities and phases. Daily challenges, events and the Archive give you more to chase.",
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
	local label = ({ move = "Move", jump = "Jump", camera = "Camera", ability = "Abilities" })[key] or key
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

	-- Top row: device tabs and Jeffery's buttons
	local top = make("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 0, Parent = column })
	local tabs = Components.segmented(nil, LearnWindow.Devices, device, function(id)
		device = id
		LearnWindow.refresh()
	end, { Name = "DeviceTabs", Size = UDim2.new(0, 340, 0, 44), Parent = top })
	local talk = Components.button("Talk to Jeffery", {
		Name = "TalkButton", Variant = "Secondary", KeepCase = true, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -176, 0, 0), Size = UDim2.fromOffset(180, 44), Parent = top,
	}, function()
		local c = controller()
		if c then
			Shell.close()
			c:replayDialogue()
		end
	end)
	local replay = Components.button("Replay tutorial", {
		Name = "ReplayButton", Variant = "Primary", KeepCase = true, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(170, 44), Parent = top,
	}, function()
		local c = controller()
		if c then
			Shell.close()
			c:replayTutorial()
		end
	end)
	local _ = { tabs, talk, replay }

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
	Shell.registerWindow("Learn", {
		title = "How to Play",
		label = "LEARN",
		icon = "learn",
		order = 6,
		build = build,
	})
end

return LearnWindow
