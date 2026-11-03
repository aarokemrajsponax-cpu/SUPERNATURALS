-- Jeffery on the client: animates the robot standing in the hub, shows his dialogue panel,
-- runs the tutorial card, and delivers contextual hints.
--
-- The server (TutorialService) decides what counts as progress. This controller only shows what
-- it is told: DataEvent "Tutorial" (state) and "Hint". It sends CONTINUE for note-only steps,
-- Exit and Replay. Hints wait in a queue until combat is quiet and are dropped when the Hints
-- setting is off. During the tutorial a companion copy of Jeffery floats beside the player.

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
	CompanionOffset = Vector3.new(4, 1, 3),
}

local state = { active = false, step = nil :: string?, index = 0, total = #Tutorial.Steps, replay = false }
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
		Name = "Eyebrow", Text = "JEFFERY", Style = "Micro", Track = true, Color = Colors.Cyan,
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
			Name = "Eyebrow", Text = "TUTORIAL", Style = "Micro", Track = true, Color = Colors.Cyan,
			Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -110, 0, 18), ZIndex = 13, Parent = card,
		}),
		count = Components.text({
			Name = "Count", Text = "1 / 13", Style = "Micro", AlignX = "Right",
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
	-- Talking animates the world copy and the companion too
	merged.onTalking = function(talking: boolean)
		for _, rig in { self.worldRig, self.companionRig } do
			if rig then
				rig.setTalking(talking)
				rig.setFace(face)
			end
		end
	end
	self.panel.say(lines, merged)
end

-- Says a step's lines. Note-only steps send CONTINUE to the server when the lines end.
function JefferyController:_sayStep(stepId: string)
	local index = Tutorial.stepIndex(stepId)
	local step = index and Tutorial.Steps[index]
	if not step then
		return
	end
	local function ack()
		if step.event == "ack" and state.step == step.id then
			ProgressRequest:FireServer(Protocol.ProgressAction.TutorialAck, step.id)
		end
	end
	self:_say(step.lines, step.face, { title = "Jeffery", onDone = ack, onSkip = ack })
end

function JefferyController:_onTutorial(payload)
	if typeof(payload) ~= "table" then
		return
	end
	state.active = payload.active == true
	state.replay = payload.replay == true
	state.index = tonumber(payload.index) or 0
	state.total = tonumber(payload.total) or #Tutorial.Steps
	state.step = if typeof(payload.step) == "string" then payload.step else nil
	self:_refreshCard()
	self:_setCompanion(state.active)
	local event = payload.event
	if event == "start" or event == "step" then
		if state.step then
			self:_sayStep(state.step)
		end
	elseif event == "complete" then
		self:_say(Tutorial.Outro.lines, Tutorial.Outro.face, { title = "Jeffery", skippable = true })
		if payload.rewarded then
			Shell.toast(`Welcome reward: the title {Tutorial.Reward.title} and {Tutorial.Reward.money} Money.`, "reward")
		end
	elseif event == "exit" then
		self.panel.hide()
		Shell.toast(Tutorial.Exited.lines[1], "info")
	end
end

-- Companion --------------------------------------------------------------------------------------

function JefferyController:_setCompanion(on: boolean)
	if not on then
		if self.companion then
			self.companion:Destroy()
			self.companion, self.companionRig = nil, nil
		end
		return
	end
	if self.companion or not self.worldModel then
		return
	end
	local copy = self.worldModel:Clone()
	for _, item in copy:GetDescendants() do
		if item:IsA("ProximityPrompt") then
			item:Destroy()
		end
	end
	copy.Name = "JefferyCompanion"
	copy.Parent = workspace
	self.companion = copy
	self.companionRig = DialoguePanel.rig(copy, false)
end

function JefferyController:_stepWorld(dt: number)
	local camera = workspace.CurrentCamera
	if self.worldRig and self.worldModel then
		local close = not camera or (camera.CFrame.Position - self.worldModel:GetPivot().Position).Magnitude < JefferyController.Config.AnimateRange
		if close then
			self.worldRig.step(os.clock(), dt)
		end
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if self.companionRig and root then
		local target = root.CFrame * CFrame.new(JefferyController.Config.CompanionOffset) * CFrame.new(0, -1.4, 0)
		local current = self.companion:GetPivot()
		local goal = CFrame.lookAt(target.Position, target.Position + root.CFrame.LookVector)
		self.companionRig.setBase(current:Lerp(goal, math.min(1, dt * 4)))
		self.companionRig.step(os.clock(), dt)
	end
end

-- Replay (How to Play) ---------------------------------------------------------------------------

function JefferyController:replayDialogue()
	local step = Tutorial.Steps[1]
	self:_say(step.lines, step.face, { title = "Jeffery" })
end

function JefferyController:replayTutorial()
	ProgressRequest:FireServer(Protocol.ProgressAction.TutorialReplay)
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
	self:_buildCard()

	task.spawn(function()
		local found = workspace:WaitForChild("Jeffery", 30) or workspace:FindFirstChild("Jeffery", true)
		if found and found:IsA("Model") and found.PrimaryPart then
			self.worldModel = found
			self.worldRig = DialoguePanel.rig(found, false)
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
