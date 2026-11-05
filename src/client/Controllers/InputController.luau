-- Binds combat controls for every device:
--   Keyboard & mouse: Left click Light, E Heavy (hold to charge), F Block (hold),
--                     Q Dodge, G Grab, C Sweep, Left Shift Sprint (hold),
--                     Z or middle mouse Lock-on, V Taunt
--   Gamepad:          X Light, Y Heavy (hold to charge), L1 Block (hold), B Dodge,
--                     L1+X Grab, L1+Y Sweep, L3 Sprint (toggle), R3 Lock-on,
--                     View/Select Taunt (abilities keep R1/R2/L2 and the D-pad)
--   Touch:            an arch of round buttons over the bottom-right thumb area (a big
--                     attack button beside Roblox's jump button, the other actions and the
--                     ability buttons on rings around it; see UI/TouchArch). Shown only in
--                     fights and training (UI/CombatView).
-- Bindings (with their key hints) live in Bindings so the HUD can show them.
-- Feinting is Block pressed during your own heavy's wind-up: the server decides.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Selection = require(ReplicatedStorage.Shared.Config.Selection)
local Theme = require(script.Parent.Parent.UI.Theme)
local Shell = require(script.Parent.Parent.UI.Shell)
local TouchArch = require(script.Parent.Parent.UI.TouchArch)
local CombatView = require(script.Parent.Parent.UI.CombatView)

local Colors = Theme.Colors
local Faces = Theme.Faces
local player = Players.LocalPlayer

local InputController = {}

local KeyCode = Enum.KeyCode
local InputType = Enum.UserInputType

-- touch = true puts the action in the touch arch (UI/TouchArch decides where);
-- hint = false keeps it out of the HUD's hint strip. Grab and sweep are chords on the gamepad's
-- block button (L1+X, L1+Y), so their pads list is empty.
InputController.Bindings = {
	{ name = "SNLight", label = "Light", keys = { InputType.MouseButton1 }, pads = { KeyCode.ButtonX }, keyText = "M1", padText = "X", touch = true },
	{ name = "SNHeavy", label = "Heavy", keys = { KeyCode.E }, pads = { KeyCode.ButtonY }, keyText = "E", padText = "Y", touch = true },
	{ name = "SNBlock", label = "Block", keys = { KeyCode.F }, pads = { KeyCode.ButtonL1 }, keyText = "F", padText = "L1", touch = true },
	{ name = "SNDodge", label = "Dodge", keys = { KeyCode.Q }, pads = { KeyCode.ButtonB }, keyText = "Q", padText = "B", touch = true },
	-- Gamepad grab and sweep are chords on the block button (handled in Light and Heavy)
	{ name = "SNGrab", label = "Grab", keys = { KeyCode.G }, pads = {}, keyText = "G", padText = "L1+X", touch = true },
	{ name = "SNSweep", label = "Sweep", keys = { KeyCode.C }, pads = {}, keyText = "C", padText = "L1+Y", touch = true },
	{ name = "SNSprint", label = "Sprint", touchLabel = "Run", keys = { KeyCode.LeftShift }, pads = { KeyCode.ButtonL3 }, keyText = "Shift", padText = "L3", touch = true },
	{ name = "SNLock", label = "Lock", keys = { KeyCode.Z, InputType.MouseButton3 }, pads = { KeyCode.ButtonR3 }, keyText = "Z", padText = "R3", touch = true },
	-- Evolve into the next phase once the Phase meter is full (the server decides; Start is the only free pad button)
	{ name = "SNEvolve", label = "Evolve", keys = { KeyCode.T }, pads = { KeyCode.ButtonStart }, keyText = "T", padText = "Start", touch = true },
	{ name = "SNTaunt", label = "Taunt", keys = { KeyCode.V }, pads = { KeyCode.ButtonSelect }, keyText = "V", padText = "View", hint = false },
}
-- Older code reads binding.inputs
for _, binding in InputController.Bindings do
	local inputs = table.clone(binding.keys)
	for _, input in binding.pads do
		table.insert(inputs, input)
	end
	binding.inputs = inputs
end

-- What still works in the lobby (matches Selection.LobbyActions on the server)
local LOBBY_OK = { SNDodge = true, SNSprint = true, SNTaunt = true, SNLock = true }

-- The bound handlers by action name: (actionName, state, input) -> result
InputController.handlers = {} :: { [string]: (string, Enum.UserInputState, any) -> Enum.ContextActionResult? }

function InputController:Init(controllers)
	self.combat = controllers.CombatController
	self.camera = controllers.CameraController
end

local function began(state): boolean
	return state == Enum.UserInputState.Begin
end

local function ended(state): boolean
	return state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel
end

local function isPad(input): boolean
	return input ~= nil and typeof(input.UserInputType) == "EnumItem" and string.find(input.UserInputType.Name, "Gamepad") ~= nil
end

function InputController:Start()
	local combat = self.combat
	local camera = self.camera
	-- Gamepad chords: L1 held turns X into Grab and Y into Sweep
	local padBlockHeld = false
	local heavyFromPad = false

	local actions = {
		SNLight = function(state, input)
			if began(state) then
				if isPad(input) and padBlockHeld then
					combat:grab()
				else
					combat:light()
				end
			end
		end,
		SNHeavy = function(state, input)
			if began(state) then
				if isPad(input) and padBlockHeld then
					heavyFromPad = false
					combat:sweep()
				else
					heavyFromPad = true
					combat:heavyPress()
				end
			elseif ended(state) and heavyFromPad then
				heavyFromPad = false
				combat:heavyRelease()
			end
		end,
		SNBlock = function(state, input)
			if began(state) then
				if isPad(input) then
					padBlockHeld = true
				end
				combat:setBlocking(true)
			elseif ended(state) then
				if isPad(input) then
					padBlockHeld = false
				end
				combat:setBlocking(false)
			end
		end,
		SNDodge = function(state)
			if began(state) then
				combat:dodge()
			end
		end,
		SNGrab = function(state)
			if began(state) then
				combat:grab()
			end
		end,
		SNSweep = function(state)
			if began(state) then
				combat:sweep()
			end
		end,
		-- Held on a keyboard, a toggle on the stick click
		SNSprint = function(state, input)
			if isPad(input) then
				if began(state) then
					combat:toggleSprint()
				end
			elseif began(state) then
				combat:setSprinting(true)
			elseif ended(state) then
				combat:setSprinting(false)
			end
		end,
		SNLock = function(state)
			if camera then
				if began(state) then
					camera:lockInput(true)
				elseif ended(state) then
					camera:lockInput(false)
				end
			end
		end,
		SNTaunt = function(state)
			if began(state) then
				combat:taunt()
			end
		end,
		SNEvolve = function(state)
			if began(state) then
				local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PowerRequest") :: RemoteEvent
				remote:FireServer(Protocol.PowerAction.Evolve)
			end
		end,
	}

	for _, binding in InputController.Bindings do
		local action = actions[binding.name]
		local function handler(_, state, input)
			-- Outside a fight and training only movement and emotes work (the server refuses the rest
			-- too); letting go of something always works
			if began(state) and not LOBBY_OK[binding.name] and not CombatView.active(player.Character, Shell.getMode()) then
				if input and input.UserInputType == InputType.MouseButton1 then
					return Enum.ContextActionResult.Pass
				end
				return Enum.ContextActionResult.Sink
			end
			action(state, input)
			-- Let clicks through to buttons and the 3D world as normal
			if input and input.UserInputType == InputType.MouseButton1 then
				return Enum.ContextActionResult.Pass
			end
			return Enum.ContextActionResult.Sink
		end
		InputController.handlers[binding.name] = handler
		ContextActionService:BindAction(binding.name, handler, false, table.unpack(binding.inputs))
	end

	-- Letting go of everything held if the window loses focus mid-hold
	UserInputService.WindowFocusReleased:Connect(function()
		padBlockHeld = false
		combat:setBlocking(false)
		combat:setSprinting(false)
		if heavyFromPad then
			heavyFromPad = false
		end
		combat:heavyRelease()
	end)

	self:_buildTouch(actions)
end

-- "keyboard", "gamepad" or "touch", for showing the right button hints
function InputController.device(): string
	local last = UserInputService:GetLastInputType()
	if last == InputType.Touch then
		return "touch"
	elseif string.find(last.Name, "Gamepad") then
		return "gamepad"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "touch"
	end
	return "keyboard"
end

-- Touch -------------------------------------------------------------------------------

-- Where Roblox puts its jump button (centre, from the bottom-right corner) and how much bigger
-- the cluster is on a tablet. Matches the PlayerModule's TouchJump.
local function touchFrame(viewport: Vector2): (Vector2, number)
	local x, y = TouchArch.jumpFrame(viewport.X, viewport.Y)
	return Vector2.new(x, y), TouchArch.scale(viewport.X, viewport.Y)
end
InputController.touchFrame = touchFrame

-- The ability buttons are drawn 64 px square (AbilityBar); the arch scales them to the slot
local ABILITY_DESIGN = 64
local HOLD_ACTIONS = { SNHeavy = true, SNBlock = true, SNLock = true }

function InputController:_buildTouch(actions)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SNTouchControls"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	self.touchGui = gui

	local buttons = {}
	local active: { [any]: string } = {}
	local toggled = { SNSprint = false }

	local function makeButton(binding)
		local primary = binding.name == TouchArch.MAIN
		local button = Instance.new("TextButton")
		button.Name = "Touch" .. binding.label
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.AutoButtonColor = false
		button.Text = ""
		button.BackgroundColor3 = Colors.Panel
		button.BackgroundTransparency = 0.3
		button.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = button
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = if primary then Colors.Cyan else Colors.Stroke
		stroke.Thickness = if primary then 2 else 1.5
		stroke.Transparency = if primary then 0.25 else 0.5
		stroke.Parent = button
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.new(1, -2, 0, 18)
		label.BackgroundTransparency = 1
		label.FontFace = Faces.Bold
		-- Six letters (EVOLVE) need a smaller size to fit the smallest buttons
		label.TextSize = if primary then 16 elseif #(binding.touchLabel or binding.label) > 5 then 12 else 14
		label.TextColor3 = Colors.Text
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = string.upper(binding.touchLabel or binding.label)
		label.Parent = button
		-- Cooldown: the whole button dims until it's ready
		local scale = Instance.new("UIScale")
		scale.Parent = button
		button.Parent = gui
		buttons[binding.name] = {
			button = button,
			stroke = stroke,
			label = label,
			scale = scale,
			binding = binding,
			primary = primary,
			slot = nil,
			-- Evolve is shown only while the Phase meter is full (see _refreshTouch)
			wanted = if binding.name == "SNEvolve" then false else nil,
		}
		return button
	end

	local function press(name: string, down: boolean)
		local entry = buttons[name]
		if entry then
			entry.scale.Scale = if down then 0.92 else 1
		end
		local action = actions[name]
		if name == "SNSprint" then
			if down then
				self.combat:toggleSprint()
			end
		elseif HOLD_ACTIONS[name] then
			action(if down then Enum.UserInputState.Begin else Enum.UserInputState.End, nil)
		elseif down then
			action(Enum.UserInputState.Begin, nil)
		end
	end

	local function release(input)
		local name = active[input]
		if name then
			active[input] = nil
			press(name, false)
		end
	end

	for _, binding in InputController.Bindings do
		if binding.touch then
			local button = makeButton(binding)
			button.InputBegan:Connect(function(input)
				if input.UserInputType ~= InputType.Touch and input.UserInputType ~= InputType.MouseButton1 then
					return
				end
				if active[input] then
					return
				end
				active[input] = binding.name
				press(binding.name, true)
			end)
			button.InputEnded:Connect(release)
		end
	end
	-- A finger that slides off its button and lifts still lets go
	UserInputService.TouchEnded:Connect(release)
	self.touchButtons = buttons

	-- Places the arch: the main button, our own buttons and the ability buttons AbilityBar
	-- handed over. Runs when the screen changes size or the set of buttons changes, never per frame.
	local function layout()
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local exists = {}
		for name in buttons do
			exists[name] = true
		end
		local abilityFrames = {}
		for _, entry in TouchArch.state.abilities do
			exists[entry.name] = true
			abilityFrames[entry.name] = entry.frame
		end
		local result = TouchArch.compute(viewport.X, viewport.Y, TouchArch.items(exists))
		self.arch = result
		TouchArch.state.arch = result
		for name, entry in buttons do
			local slot = result.slots[name]
			entry.slot = slot
			entry.button.Visible = slot ~= nil and entry.wanted ~= false
			if slot then
				entry.button.Size = UDim2.fromOffset(slot.size, slot.size)
				entry.button.Position = UDim2.new(1, math.floor(slot.x + 0.5), 1, math.floor(slot.y + 0.5))
			end
		end
		for name, frame in abilityFrames do
			local slot = result.slots[name]
			frame.Visible = slot ~= nil
			if slot then
				frame.Size = UDim2.fromOffset(ABILITY_DESIGN, ABILITY_DESIGN)
				frame.Position = UDim2.new(1, math.floor(slot.x + 0.5), 1, math.floor(slot.y + 0.5))
				local scale = frame:FindFirstChild("ArchScale")
				if scale then
					scale.Scale = slot.size / ABILITY_DESIGN
				end
			end
		end
	end
	layout()
	local function watchCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
		end
		layout()
	end
	watchCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	self.layoutTouch = layout
	TouchArch.state.layer = gui
	TouchArch.state.relayout = layout

	-- Shown on touch devices while there's a fight to have; button states follow the game
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		self:_refreshTouch(toggled)
	end)
end

function InputController:_refreshTouch(toggled)
	local gui = self.touchGui
	if not gui then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local mode = Shell.getMode()
	local shown = InputController.device() == "touch"
		and humanoid ~= nil
		and humanoid.Health > 0
		and mode ~= "Editor"
		and mode ~= "Cinematic"
		and not Shell.isOpen()
		and CombatView.active(character, mode)
	if gui.Enabled ~= shown then
		gui.Enabled = shown
	end
	if not shown or not character then
		return
	end
	-- Evolve keeps its place in the arch (so nothing shifts mid-fight) but shows only when the
	-- Phase meter is full
	local evolve = self.touchButtons.SNEvolve
	if evolve then
		local meter = character:GetAttribute(Protocol.Attribute.PhaseMeter)
		local ready = typeof(character:GetAttribute(Protocol.Attribute.PhaseNext)) == "string"
			and typeof(meter) == "number"
			and meter >= Selection.Phase.MeterMax
		local visible = ready and evolve.slot ~= nil
		evolve.wanted = ready
		if evolve.button.Visible ~= visible then
			evolve.button.Visible = visible
		end
	end
	local combat = self.combat
	local on = {
		SNSprint = combat and combat:isSprinting() or false,
		SNLock = self.camera ~= nil and self.camera:isLocked(),
		SNBlock = combat and combat:isBlocking() or false,
	}
	toggled.SNSprint = on.SNSprint
	for name, entry in self.touchButtons do
		local lit = on[name] == true
		local ready = if combat then combat:isReady(name) else true
		entry.button.BackgroundColor3 = if lit then Colors.CyanDeep else Colors.Panel
		entry.button.BackgroundTransparency = if lit then 0.25 else (if ready then 0.3 else 0.55)
		entry.stroke.Color = if lit or entry.primary then Colors.Cyan else Colors.Stroke
		entry.stroke.Transparency = if lit then 0 else (if entry.primary then 0.25 else 0.5)
		entry.label.TextTransparency = if ready then 0 else 0.5
	end
end

return InputController
