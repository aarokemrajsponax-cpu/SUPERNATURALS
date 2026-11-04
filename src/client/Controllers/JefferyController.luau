-- Jeffery on the client: animates the robot standing in the hub, shows his dialogue panel,
-- runs the tutorial card, and delivers contextual hints.
--
-- The server (TutorialService) decides what counts as progress. This controller only shows what
-- it is told: DataEvent "Tutorial" (state) and "Hint". It sends TutorialReady (once it runs and
-- Jeffery is in the world), TutorialLine (the step's lines are finished, so the server starts
-- watching), CONTINUE for the welcome step, "camera turned" for the camera step, Exit and Replay.
-- Hints wait in a queue until combat is quiet and are dropped when the Hints setting is off.
--
-- Jeffery stays at his post in the hall. During the tour he turns to face the player and waves, and
-- pointing is done with floor arrows and a light beam along the hub's Guides waypoints; he never
-- follows or hovers beside the player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local Components = require(script.Parent.Parent.UI.Components)
local DialoguePanel = require(script.Parent.Parent.UI.DialoguePanel)
local Shell = require(script.Parent.Parent.UI.Shell)
local Theme = require(script.Parent.Parent.UI.Theme)
local Settings = require(script.Parent.Parent.Settings)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent
local CombatEvent = Remotes:WaitForChild("CombatEvent") :: RemoteEvent
local ProgressRequest = Remotes:WaitForChild("ProgressRequest") :: RemoteEvent

local make = Components.make
local Colors = Theme.Colors
local player = Players.LocalPlayer

local JefferyController = {}

JefferyController.Config = {
	-- Combat is "active" for this long after the last hit or swing involving you
	QuietSeconds = 5,
	HintSeconds = 7,
	-- The world copy only animates when you are this close (studs)
	AnimateRange = 160,
	-- He turns to face you when you are this close (studs) during the tour
	FaceRange = 90,
	-- A pause between finishing one step and Jeffery starting the next, so the tick is seen first
	StepGap = 0.9,
	-- Floor arrows: spacing (studs) and how many are shown ahead of the player
	ArrowSpacing = 6,
	ArrowCount = 7,
	-- How long the client waits for the world (Jeffery, the character, no open window) before saying ready
	ReadyWait = 20,
}

local state = { active = false, step = nil :: string?, index = 0, total = #Tutorial.Steps, replay = false, armed = false }
local tourToken = 0
local lastCombat = -math.huge
local hintQueue: { { id: string, text: string, face: string } } = {}
local hintCard: Frame? = nil
local hintUntil = 0
local openWindows: { [string]: boolean } = {}

-- Key caps for the current device --------------------------------------------------------

local function deviceName(self): string
	return if self.input and self.input.device then self.input.device() else "keyboard"
end

-- The text for one `keys` entry of a step on a device
function JefferyController.keyText(bindings: { any }, key: string, device: string): string
	for _, binding in bindings do
		if binding.name == key then
			if device == "gamepad" then
				return binding.padText
			elseif device == "touch" then
				return binding.touchLabel or binding.label
			end
			return binding.keyText
		end
	end
	local extra = Tutorial.ExtraKeys[key]
	return if extra then extra[device] or extra.keyboard else key
end

-- Safety for hints ---------------------------------------------------------------------------

function JefferyController:_combatQuiet(): boolean
	if Shell.getMode() == "Match" or Shell.getMode() == "Cinematic" then
		return false
	end
	local character = player.Character
	if character and character:GetAttribute(Protocol.Attribute.CombatContext) == "Match" then
		return false
	end
	return os.clock() - lastCombat >= JefferyController.Config.QuietSeconds
end

-- Hints --------------------------------------------------------------------------------------

function JefferyController:queueHint(hint: { id: string, text: string, face: string })
	if Settings.get("hints") == false then
		return
	end
	table.insert(hintQueue, hint)
end

function JefferyController:_showHint(hint)
	if hintCard then
		hintCard:Destroy()
	end
	local card = make("Frame", {
		Name = "JefferyHint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 88),
		Size = UDim2.fromOffset(520, 76),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		ZIndex = 15,
		Parent = self.gui,
	}, { Components.corner(), Components.stroke(Colors.Cyan, 1, 0.5) })
	Components.text({
		Name = "Eyebrow", Text = "Jeffery", Style = "label", Weight = "Bold", Color = Colors.Cyan,
		Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 18), ZIndex = 16, Parent = card,
	})
	Components.text({
		Name = "Text", Text = hint.text, Style = "Body", Wrap = true, Lines = 2,
		Position = UDim2.fromOffset(16, 28), Size = UDim2.new(1, -32, 0, 44), ZIndex = 16, Parent = card,
	})
	hintCard = card
	hintUntil = os.clock() + JefferyController.Config.HintSeconds
	self.lastHint = hint
end

-- Called often: shows the next hint when it is safe, hides the current one when it expires
function JefferyController:_tickHints()
	if hintCard and os.clock() >= hintUntil then
		hintCard:Destroy()
		hintCard = nil
	end
	if not hintCard and #hintQueue > 0 and self:_combatQuiet() and not self.panel.isOpen() then
		local hint = table.remove(hintQueue, 1) :: any
		if Settings.get("hints") ~= false then
			self:_showHint(hint)
		end
	end
end

-- Tutorial card ------------------------------------------------------------------------------

function JefferyController:_buildCard()
	local card = make("Frame", {
		Name = "TutorialCard",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(16, 150),
		Size = UDim2.fromOffset(300, 150),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 12,
		Parent = self.gui,
	}, { Components.corner(), Components.stroke(Colors.Stroke, 1, 0.55) })
	self.cardParts = {
		card = card,
		eyebrow = Components.text({
			Name = "Eyebrow", Text = "TOUR", Style = "Micro", Track = true, Color = Colors.Cyan,
			Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -110, 0, 18), ZIndex = 13, Parent = card,
		}),
		count = Components.text({
			Name = "Count", Text = "1 / 8", Style = "Micro", AlignX = "Right",
			Position = UDim2.new(1, -90, 0, 10), Size = UDim2.fromOffset(74, 18), ZIndex = 13, Parent = card,
		}),
		title = Components.text({
			Name = "Title", Text = "", Style = "Heading",
			Position = UDim2.fromOffset(16, 32), Size = UDim2.new(1, -32, 0, 26), ZIndex = 13, Parent = card,
		}),
		goal = Components.text({
			Name = "Goal", Text = "", Style = "Body", Wrap = true, Lines = 2,
			Position = UDim2.fromOffset(16, 60), Size = UDim2.new(1, -32, 0, 40), ZIndex = 13, Parent = card,
		}),
		keys = make("Frame", {
			Name = "Keys", Position = UDim2.fromOffset(16, 104), Size = UDim2.new(1, -120, 0, 32),
			BackgroundTransparency = 1, ZIndex = 13, Parent = card,
		}, { make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center }) }),
	}
	Components.button("Exit", {
		Name = "Exit", Variant = "Ghost", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -6),
		Size = UDim2.fromOffset(84, 44), ZIndex = 14, Parent = card,
	}, function()
		ProgressRequest:FireServer(Protocol.ProgressAction.TutorialExit)
	end)
end

function JefferyController:_refreshCard()
	local parts = self.cardParts
	local stepDef = state.step and Tutorial.Steps[Tutorial.stepIndex(state.step :: string) :: number]
	parts.card.Visible = state.active and stepDef ~= nil
	if not stepDef then
		return
	end
	parts.count.Text = `{state.index} / {state.total}`
	parts.title.Text = stepDef.title
	parts.goal.Text = stepDef.goal
	-- "LISTEN" while Jeffery is talking, "YOUR TURN" once the server is watching for the step
	parts.eyebrow.Text = Theme.track(if state.armed then "YOUR TURN" else "LISTEN")
	parts.eyebrow.TextColor3 = if state.armed then Colors.Cyan else Colors.TextMuted
	for _, child in parts.keys:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local device = deviceName(self)
	local bindings = self.input and self.input.Bindings or {}
	for order, key in stepDef.keys or {} do
		local cap = Components.keycap(JefferyController.keyText(bindings, key, device), { LayoutOrder = order, Parent = parts.keys })
		cap.Name = "Key_" .. key
	end
end

function JefferyController:_say(lines: { string }, face: string, options: { [string]: any }?)
	local merged: { [string]: any } = { face = face }
	for key, value in options or {} do
		merged[key] = value
	end
	-- Talking animates the world copy (he stays at his post and waves)
	merged.onTalking = function(talking: boolean)
		if self.worldRig then
			self.worldRig.setTalking(talking)
			self.worldRig.setFace(face)
		end
	end
	self.panel.say(lines, merged)
end

-- The tour --------------------------------------------------------------------------------------

-- Is a Shell window (shop, settings, Ask Jeffery...) in the way of a line?
local function windowOpen(): boolean
	return Shell.isOpen()
end

-- The step's lines are over: tell the server to start watching, show the goal, start the pointers
function JefferyController:_lineDone(step)
	if state.step ~= step.id or not state.active then
		return
	end
	state.armed = true
	self:_refreshCard()
	if step.event == "ack" then
		ProgressRequest:FireServer(Protocol.ProgressAction.TutorialAck, step.id)
		return
	end
	ProgressRequest:FireServer(Protocol.ProgressAction.TutorialLine, step.id)
	if step.guide then
		self:_setGuide(step.guide)
	end
	if step.event == "look" then
		self:_watchLook(step.id)
	end
end

-- Says a step's lines. The step is only "armed" (guide arrows, camera watch, the server's
-- watching) after the lines end, never while Jeffery is still talking.
function JefferyController:_sayStep(stepId: string)
	local index = Tutorial.stepIndex(stepId)
	local step = index and Tutorial.Steps[index]
	if not step then
		return
	end
	state.armed = false
	self:_setGuide(nil)
	self.lookWatch = nil
	self:_refreshCard()
	if self.worldRig then
		self.worldRig.gesture()
	end
	self:_say(step.lines, step.face, {
		title = "Jeffery",
		skipLabel = "Skip tour",
		autoClose = if step.autoClose then Tutorial.AutoCloseSeconds else nil,
		onDone = function()
			self:_lineDone(step)
		end,
		onSkip = function()
			ProgressRequest:FireServer(Protocol.ProgressAction.TutorialExit)
		end,
	})
end

-- The camera step: the client owns the camera, so it reports when it has turned far enough
function JefferyController:_watchLook(stepId: string)
	local camera = workspace.CurrentCamera
	if not camera then
		ProgressRequest:FireServer(Protocol.ProgressAction.TutorialAck, stepId)
		return
	end
	self.lookWatch = { step = stepId, start = camera.CFrame.LookVector }
end

function JefferyController:_stepLook()
	local watch = self.lookWatch
	local camera = workspace.CurrentCamera
	if not watch or not camera then
		return
	end
	if state.step ~= watch.step or not state.armed then
		self.lookWatch = nil
		return
	end
	local dot = math.clamp(watch.start:Dot(camera.CFrame.LookVector), -1, 1)
	if math.deg(math.acos(dot)) >= Tutorial.LookDegrees then
		self.lookWatch = nil
		ProgressRequest:FireServer(Protocol.ProgressAction.TutorialAck, watch.step)
	end
end

-- After the last step: the outro with a choice, the optional "tell me more" talk, then the gift
function JefferyController:_playMore(topics: { any }, index: number, finish: () -> ())
	local topic = topics[index]
	if not topic then
		finish()
		return
	end
	local function nextTopic()
		self:_playMore(topics, index + 1, finish)
	end
	self:_say(topic.lines, topic.face, { title = "Jeffery", skipLabel = "That is enough", onDone = nextTopic, onSkip = finish })
end

function JefferyController:_finishTour(rewarded: boolean, gift: any)
	local function showGift()
		if rewarded then
			self:showGift(gift)
		else
			self:_say(Tutorial.ReplayDone.lines, Tutorial.ReplayDone.face, { title = "Jeffery", skippable = false })
		end
	end
	local outro = Tutorial.Outro
	local choices = {
		outro.choices[1],
		{ id = "gift", label = if rewarded then outro.choices[2].label else "Done" },
	}
	self:_say(outro.lines, outro.face, {
		title = "Jeffery",
		skippable = false,
		choices = choices,
		onChoice = function(id)
			if id == "more" then
				self:_playMore(Tutorial.More, 1, showGift)
			else
				showGift()
			end
		end,
	})
end

-- The welcome gift moment: what was given, and one voluntary line. Never tied to liking the game.
function JefferyController:showGift(gift: any)
	self.panel.hide()
	if self.giftCard then
		self.giftCard:Destroy()
	end
	gift = if typeof(gift) == "table" then gift else {}
	local text = Tutorial.Gift
	local items = {}
	if gift.title or Tutorial.Reward.title then
		table.insert(items, `{gift.title or Tutorial.Reward.title} title`)
	end
	table.insert(items, `{Components.formatNumber(gift.money or Tutorial.Reward.money)} Money`)
	if gift.founding then
		table.insert(items, `{Tutorial.Reward.foundingTitle} title`)
	end
	local card = make("Frame", {
		Name = "WelcomeGift", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(460, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.Panel, BorderSizePixel = 0, ZIndex = 40, Parent = self.gui,
	}, {
		Components.corner(), Components.stroke(Colors.Cyan, 1.5, 0.3), Components.padding(20, 20, 20, 20),
		make("UISizeConstraint", { MaxSize = Vector2.new(460, 9999) }),
		make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})
	Components.text({ Name = "Title", Text = string.upper(text.title), Style = "Heading", AlignX = "Center", Color = Colors.Cyan, LayoutOrder = 1, ZIndex = 41, Parent = card })
	Components.text({ Name = "Intro", Text = text.intro, Style = "Body", Wrap = true, AlignX = "Center", LayoutOrder = 2, ZIndex = 41, Parent = card })
	local list = make("Frame", {
		Name = "Items", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 3, ZIndex = 41, Parent = card,
	}, { make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }) })
	for order, item in items do
		local row = make("Frame", {
			Name = "Item_" .. order, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Colors.PanelLight,
			BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 41, Parent = list,
		}, { Components.corner() })
		Components.text({ Name = "Label", Text = item, Style = "Body", Weight = "Bold", AlignX = "Center", Size = UDim2.fromScale(1, 1), ZIndex = 42, Parent = row })
	end
	Components.text({ Name = "Like", Text = text.like, Style = "Caption", Wrap = true, AlignX = "Center", Color = Colors.TextDim, LayoutOrder = 4, ZIndex = 41, Parent = card })
	Components.button(text.button, {
		Name = "GiftDone", Variant = "Primary", KeepCase = true, Size = UDim2.fromOffset(180, 44), LayoutOrder = 5, ZIndex = 42, Parent = card,
	}, function()
		card:Destroy()
		if self.giftCard == card then
			self.giftCard = nil
		end
	end)
	self.giftCard = card
	if self.worldRig then
		self.worldRig.setFace(text.face)
		self.worldRig.gesture()
	end
end

function JefferyController:_onTutorial(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local wasStep = state.step
	state.active = payload.active == true
	state.replay = payload.replay == true
	state.index = tonumber(payload.index) or 0
	state.total = tonumber(payload.total) or #Tutorial.Steps
	state.step = if typeof(payload.step) == "string" then payload.step else nil
	if state.step ~= wasStep or not state.active then
		state.armed = false
		-- A pointer or camera watch belongs to the step that made it
		self:_setGuide(nil)
		self.lookWatch = nil
	end
	tourToken += 1
	local token = tourToken
	self:_refreshCard()
	local event = payload.event
	if event == "start" or event == "step" then
		local stepId = state.step
		if stepId then
			-- A beat after the last step's tick, and never under an open window
			local gap = if event == "step" then JefferyController.Config.StepGap else 0.2
			task.spawn(function()
				task.wait(gap)
				while tourToken == token and windowOpen() do
					task.wait(0.3)
				end
				if tourToken == token and state.step == stepId and state.active then
					self:_sayStep(stepId)
				end
			end)
		end
	elseif event == "complete" then
		self:_setGuide(nil)
		self.lookWatch = nil
		self:_finishTour(payload.rewarded == true, payload.gift)
	elseif event == "exit" then
		self:_setGuide(nil)
		self.lookWatch = nil
		self.panel.hide()
		Shell.toast(Tutorial.Exited.lines[1], "info")
	elseif not state.active then
		self:_setGuide(nil)
		self.lookWatch = nil
	end
end

-- Floor arrows -----------------------------------------------------------------------------------

local function findGuides(): Instance?
	return workspace:FindFirstChild("Guides", true)
end

-- Shows arrows along the hub's waypoints to a destination (a Guides folder id), or nothing for nil
function JefferyController:_setGuide(destination: string?)
	if self.guideFolder then
		self.guideFolder:Destroy()
		self.guideFolder = nil
	end
	self.guide = nil
	if not destination then
		return
	end
	local guides = findGuides()
	local list = guides and guides:FindFirstChild(destination)
	if not list then
		return
	end
	local points = {}
	local children = list:GetChildren()
	table.sort(children, function(a, b)
		return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
	end)
	for _, item in children do
		if item:IsA("BasePart") then
			table.insert(points, Vector3.new(item.Position.X, 0.25, item.Position.Z))
		end
	end
	if #points == 0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "JefferyGuide"
	folder.Parent = workspace
	self.guideFolder = folder
	self.guide = { points = points, arrows = {}, beam = nil }
	-- A soft light beam over the destination, so it can be seen from across the hall
	local beam = Instance.new("Part")
	beam.Name = "Beam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = Tutorial.FaceColor
	beam.Transparency = 0.8
	beam.Size = Vector3.new(2.2, 46, 2.2)
	beam.CFrame = CFrame.new(points[#points] + Vector3.new(0, 23, 0))
	beam.Parent = folder
	self.guide.beam = beam
	self:_stepGuide(0)
end

local function chevron(folder: Folder, name: string): { Part }
	local parts = {}
	for side = -1, 1, 2 do
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = Tutorial.FaceColor
		part.Size = Vector3.new(0.5, 0.1, 2.6)
		part.Parent = folder
		table.insert(parts, part)
	end
	return parts
end

-- Lays the arrows from the player towards the destination (called often, cheap)
function JefferyController:_stepGuide(dt: number)
	local guide = self.guide
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not guide or not root or not self.guideFolder then
		return
	end
	local config = JefferyController.Config
	local here = Vector3.new(root.Position.X, 0.25, root.Position.Z)
	local points = guide.points
	-- The first waypoint still ahead of the player
	local nearest, best = 1, math.huge
	for index, point in points do
		local distance = (point - here).Magnitude
		if distance < best then
			nearest, best = index, distance
		end
	end
	local route = { here }
	for index = nearest + (if best < 10 and nearest < #points then 1 else 0), #points do
		table.insert(route, points[index])
	end
	-- Walk along the route placing an arrow every ArrowSpacing studs
	local placed = 0
	local carried = config.ArrowSpacing * 0.6
	for index = 1, #route - 1 do
		local from, to = route[index], route[index + 1]
		local segment = to - from
		local length = segment.Magnitude
		if length > 0.01 then
			local direction = segment / length
			while carried <= length and placed < config.ArrowCount do
				placed += 1
				local tip = from + direction * carried
				local arrow = guide.arrows[placed]
				if not arrow then
					arrow = chevron(self.guideFolder, "Arrow")
					guide.arrows[placed] = arrow
				end
				local base = CFrame.lookAt(tip, tip + direction)
				-- Two bars angled back from the tip make a chevron
				arrow[1].CFrame = base * CFrame.Angles(0, math.rad(35), 0) * CFrame.new(0, 0, 1.1)
				arrow[2].CFrame = base * CFrame.Angles(0, math.rad(-35), 0) * CFrame.new(0, 0, 1.1)
				-- A pulse travels along the arrows, nearest first
				local pulse = 0.35 + 0.4 * (0.5 + 0.5 * math.sin(os.clock() * 4 - placed * 0.9))
				arrow[1].Transparency, arrow[2].Transparency = pulse, pulse
				carried += config.ArrowSpacing
			end
			carried -= length
		end
	end
	for index = placed + 1, #guide.arrows do
		for _, part in guide.arrows[index] do
			part.Transparency = 1
		end
	end
	local _ = dt
end

-- Where Jeffery stands -----------------------------------------------------------------------------

function JefferyController:_stepWorld(dt: number)
	local camera = workspace.CurrentCamera
	if self.worldRig and self.worldModel then
		local close = not camera or (camera.CFrame.Position - self.worldModel:GetPivot().Position).Magnitude < JefferyController.Config.AnimateRange
		if close then
			-- He never leaves his post. During the tour (or a talk) he turns to face you.
			local home = self.home
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if home then
				local goal = home
				if root and (state.active or self.panel.isOpen()) and (root.Position - home.Position).Magnitude < JefferyController.Config.FaceRange then
					local target = Vector3.new(root.Position.X, home.Position.Y, root.Position.Z)
					if (target - home.Position).Magnitude > 0.5 then
						goal = CFrame.lookAt(home.Position, target)
					end
				end
				self.facing = (self.facing or home):Lerp(goal, math.min(1, dt * 3))
				self.worldRig.setBase(self.facing)
			end
			self.worldRig.step(os.clock(), dt)
		end
	end
	self:_stepLook()
	if self.guide then
		self:_stepGuide(dt)
	end
end

-- Replay (How to Play) ---------------------------------------------------------------------------

function JefferyController:replayTutorial()
	ProgressRequest:FireServer(Protocol.ProgressAction.TutorialReplay)
end

-- Opens the Ask Jeffery chat panel
function JefferyController:openChat()
	if Shell.hasWindow("AskJeffery") then
		self.panel.hide()
		Shell.open("AskJeffery")
	end
end

function JefferyController._queue()
	return hintQueue
end

function JefferyController:getState()
	return state
end

-- Start --------------------------------------------------------------------------------------

function JefferyController:Init(controllers)
	self.input = controllers.InputController
end

function JefferyController:Start()
	self.gui = player:WaitForChild("PlayerGui"):WaitForChild("SNInterface")
	JefferyController.instance = self
	self.panel = DialoguePanel.build(self.gui, function()
		return self.worldModel
	end)
	-- While he talks the combat HUD fades out, so nothing shows through or behind the panel
	self.panel.onVisibility = function(open: boolean)
		local folder = script.Parent
		local module = folder:FindFirstChild("UIController")
		local ok, ui = pcall(require, module)
		local hud = ok and ui and ui.hud
		if hud and hud.setFaded then
			hud.setFaded(open)
		end
	end
	self:_buildCard()

	task.spawn(function()
		local found = workspace:WaitForChild("Jeffery", 30) or workspace:FindFirstChild("Jeffery", true)
		if found and found:IsA("Model") and found.PrimaryPart then
			self.worldModel = found
			self.home = found:GetPivot()
			self.worldRig = DialoguePanel.rig(found, false)
		end
		-- Tell the server the tour may begin only once there is something to show it with: Jeffery
		-- is in the world, the character exists and no window or cinematic is covering the screen
		local waited = 0
		while waited < JefferyController.Config.ReadyWait do
			local character = player.Character
			local ready = character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil
				and Shell.getMode() ~= "Cinematic" and not windowOpen()
			if ready then
				break
			end
			task.wait(0.25)
			waited += 0.25
		end
		ProgressRequest:FireServer(Protocol.ProgressAction.TutorialReady)
	end)

	-- Jeffery's prompt in the hall opens the Ask Jeffery panel
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Action") == "Jeffery:Ask" then
			self:openChat()
		end
	end)

	DataEvent.OnClientEvent:Connect(function(kind, payload)
		if kind == Protocol.DataEvent.Tutorial then
			self:_onTutorial(payload)
		elseif kind == Protocol.DataEvent.Hint and typeof(payload) == "table" and typeof(payload.text) == "string" then
			self:queueHint({ id = tostring(payload.id), text = payload.text, face = tostring(payload.face) })
		end
	end)

	CombatEvent.OnClientEvent:Connect(function(_kind, data)
		local character = player.Character
		if typeof(data) == "table" and character and (data.attacker == character or data.victim == character or data.fighter == character) then
			lastCombat = os.clock()
		end
	end)

	Settings.changed:Connect(function(key, value)
		if key == "hints" and value == false then
			table.clear(hintQueue)
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		self:_stepWorld(dt)
	end)
	task.spawn(function()
		while true do
			task.wait(0.4)
			self:_tickHints()
			self:_stepLook()
			-- A window opened over Jeffery's line: put the line away and say it again when the window closes
			local covered = windowOpen()
			if covered and not self.covered and self.panel.isOpen() and state.active and state.step and not state.armed then
				self.resumeStep = state.step
				self.panel.hide()
			elseif not covered and self.covered and self.resumeStep then
				local stepId = self.resumeStep
				self.resumeStep = nil
				if state.active and state.step == stepId and not state.armed then
					self:_sayStep(stepId)
				end
			end
			self.covered = covered
			-- Opening fighter selection or the shop can bring a hint (the server decides)
			for windowId in Tutorial.WindowHints do
				local isOpen = Shell.isOpen(windowId)
				if isOpen and not openWindows[windowId] then
					ProgressRequest:FireServer(Protocol.ProgressAction.HintWindow, windowId)
				end
				openWindows[windowId] = isOpen
			end
		end
	end)
end

local _ = TweenService
return JefferyController
