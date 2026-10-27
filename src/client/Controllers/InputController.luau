-- Binds combat controls for every device:
--   Keyboard & mouse: Left click Light, E Heavy (hold to charge), F Block (hold),
--                     Q Dodge, G Grab, C Sweep, Left Shift Sprint (hold),
--                     Z or middle mouse Lock-on, V Taunt
--   Gamepad:          X Light, Y Heavy (hold to charge), L1 Block (hold), B Dodge,
--                     L1+X Grab, L1+Y Sweep, L3 Sprint (toggle), R3 Lock-on,
--                     View/Select Taunt (abilities keep R1/R2/L2 and the D-pad)
--   Touch:            a cluster of round buttons around Roblox's jump button,
--                     clear of the ability bar and the thumbstick
-- Bindings (with their key hints) live in Bindings so the HUD can show them.
-- Feinting is Block pressed during your own heavy's wind-up: the server decides.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Parent.UI.Theme)
local Shell = require(script.Parent.Parent.UI.Shell)

local Colors = Theme.Colors
local Faces = Theme.Faces
local player = Players.LocalPlayer

local InputController = {}

local KeyCode = Enum.KeyCode
local InputType = Enum.UserInputType

-- touch = { dx, dy, size } in points from the centre of Roblox's jump button
-- (scaled up on big screens); hint = false keeps it out of the HUD's hint strip
InputController.Bindings = {
	{ name = "SNLight", label = "Light", keys = { InputType.MouseButton1 }, pads = { KeyCode.ButtonX }, keyText = "M1", padText = "X", touch = { -92, 0, 78 } },
	{ name = "SNHeavy", label = "Heavy", keys = { KeyCode.E }, pads = { KeyCode.ButtonY }, keyText = "E", padText = "Y", touch = { -92, -86, 64 } },
	{ name = "SNBlock", label = "Block", keys = { KeyCode.F }, pads = { KeyCode.ButtonL1 }, keyText = "F", padText = "L1", touch = { -158, -86, 56 } },
	{ name = "SNDodge", label = "Dodge", keys = { KeyCode.Q }, pads = { KeyCode.ButtonB }, keyText = "Q", padText = "B", touch = { 0, -86, 60 } },
	-- Gamepad grab and sweep are chords on the block button (handled in Light and Heavy)
	{ name = "SNGrab", label = "Grab", keys = { KeyCode.G }, pads = {}, keyText = "G", padText = "L1+X", touch = { -158, -160, 46 } },
	{ name = "SNSweep", label = "Sweep", keys = { KeyCode.C }, pads = {}, keyText = "C", padText = "L1+Y", touch = { -102, -160, 46 } },
	{ name = "SNSprint", label = "Sprint", touchLabel = "Run", keys = { KeyCode.LeftShift }, pads = { KeyCode.ButtonL3 }, keyText = "Shift", padText = "L3", touch = { -46, -160, 46 } },
	{ name = "SNLock", label = "Lock", keys = { KeyCode.Z, InputType.MouseButton3 }, pads = { KeyCode.ButtonR3 }, keyText = "Z", padText = "R3", touch = { 10, -160, 46 } },
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
	}

	for _, binding in InputController.Bindings do
		local action = actions[binding.name]
		local function handler(_, state, input)
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

-- Where Roblox puts its jump button (centre, from the bottom-right corner) and how
-- much bigger the cluster is on a tablet. Matches the PlayerModule's TouchJump.
local function touchFrame(viewport: Vector2): (Vector2, number)
	local small = math.min(viewport.X, viewport.Y) <= 500
	if small then
		return Vector2.new(-60, -55), 1
	end
	return Vector2.new(-110, -150), 1.3
end
InputController.touchFrame = touchFrame

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
		local spec = binding.touch
		local primary = binding.name == "SNLight"
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
		label.Size = UDim2.new(1, -8, 0, 18)
		label.BackgroundTransparency = 1
		label.FontFace = Faces.Bold
		label.TextSize = if primary then 15 else (if spec[3] < 50 then 12 else 13)
		label.TextColor3 = Colors.Text
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = string.upper(binding.touchLabel or binding.label)
		label.Parent = button
		-- Cooldown: the whole button dims until it's ready
		local scale = Instance.new("UIScale")
		scale.Parent = button
		button.Parent = gui
		buttons[binding.name] = { button = button, stroke = stroke, label = label, scale = scale, binding = binding, primary = primary }
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

	local function layout()
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local jump, scale = touchFrame(viewport)
		for _, entry in buttons do
			local spec = entry.binding.touch
			local size = math.floor(spec[3] * scale + 0.5)
			entry.button.Size = UDim2.fromOffset(size, size)
			entry.button.Position = UDim2.new(1, math.floor(jump.X + spec[1] * scale + 0.5), 1, math.floor(jump.Y + spec[2] * scale + 0.5))
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
	gui.Enabled = InputController.device() == "touch"
		and humanoid ~= nil
		and humanoid.Health > 0
		and mode ~= "Editor"
		and mode ~= "Cinematic"
		and not Shell.isOpen()
	if not gui.Enabled or not character then
		return
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
