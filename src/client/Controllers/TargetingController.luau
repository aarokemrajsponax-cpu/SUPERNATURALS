-- Aiming for abilities with a `targeting` mode (see Shared/Powers/StrongDude.luau):
--   point      a ground spot within range; the area radius is drawn there
--   teleport   a landing spot; shown red when something solid is in the way
--   direction  fires toward the cursor at once (click-to-direct); touch can drag to aim
-- Pressing a point or teleport ability enters targeting mode: a ground ring at
-- the cursor's hit point, a faint range circle around the player, and a red
-- ring when the spot is no good. Confirm with left click, the ability's own key
-- or (gamepad) RT; cancel with right click, Esc or gamepad B. Touch: hold the
-- ability button and drag to aim, release to cast, drag back onto the button to
-- cancel; a plain tap casts straight ahead. Settings.quickCast skips the mode
-- (cast at the cursor immediately). The server still clamps and validates the
-- point; nothing here is trusted.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Settings = require(script.Parent.Parent.Settings)
local Vfx = require(script.Parent.Parent.Effects.Vfx)

local player = Players.LocalPlayer
local settings = Combat.Targeting

local TargetingController = {}

local ACTION = "SNTargetingInput"
local STEP = "SNTargeting"
local VALID_COLOR = Color3.fromRGB(190, 240, 255)
local INVALID_COLOR = Color3.fromRGB(255, 90, 90)
local TAP_DISTANCE = 14
-- Gamepad reticle speed, studs per second at full stick
local RETICLE_SPEED = 38

local active: { [string]: any }? = nil
local folder: Folder? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function myRoot(): (BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Pure rules, shared with the tests ---------------------------------------------------

-- Pulls a wanted point back to the ability's reach around `origin` (flat distance)
function TargetingController.clampToRange(origin: Vector3, wanted: Vector3, range: number): (Vector3, boolean)
	local offset = flat(wanted - origin)
	if offset.Magnitude <= range or offset.Magnitude < 1e-4 then
		return wanted, false
	end
	local limited = origin + offset.Unit * range
	return Vector3.new(limited.X, wanted.Y, limited.Z), true
end

-- How far an ability reaches and how big the area it affects is
function TargetingController.shapeOf(def: any): (number, number)
	local range = def.range or def.reach or settings.DefaultRange
	local radius = def.radius or 0
	if def.targeting == "teleport" then
		radius = 3
	elseif def.targeting == "point" and radius < 2 then
		radius = 3
	end
	return range, radius
end

-- Indicator parts -----------------------------------------------------------------------

local function newDisc(name: string, pixelsPerStud: number, thickness: number): (Part, Frame, UIStroke)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(2, 0.1, 2)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.Parent = part
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = VALID_COLOR
	frame.BackgroundTransparency = 0.88
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = VALID_COLOR
	stroke.Parent = frame
	return part, frame, stroke
end

local function buildIndicator(state)
	local container = Instance.new("Folder")
	container.Name = "SNTargeting"
	container.Parent = workspace
	folder = container
	local rangeDisc, rangeFill, rangeStroke = newDisc("Range", 10, 2)
	rangeFill.BackgroundTransparency = 0.96
	rangeStroke.Transparency = 0.55
	rangeDisc.Parent = container
	local reticle, reticleFill, reticleStroke = newDisc("Reticle", 20, 4)
	reticle.Parent = container
	local line = Instance.new("Part")
	line.Name = "Line"
	line.Anchored = true
	line.CanCollide = false
	line.CanQuery = false
	line.CanTouch = false
	line.CastShadow = false
	line.Material = Enum.Material.Neon
	line.Transparency = 0.5
	line.Size = Vector3.new(0.15, 0.15, 1)
	line.Parent = container
	state.parts = {
		range = rangeDisc, rangeStroke = rangeStroke, rangeFill = rangeFill,
		reticle = reticle, reticleStroke = reticleStroke, reticleFill = reticleFill, line = line,
	}
end

local function setValidLook(state, valid: boolean)
	local color = if valid then state.color else INVALID_COLOR
	local parts = state.parts
	parts.reticleStroke.Color = color
	parts.reticleFill.BackgroundColor3 = color
	parts.reticleFill.BackgroundTransparency = if valid then 0.86 else 0.6
	parts.line.Color = color
	parts.rangeStroke.Color = state.color
end

local function destroyIndicator()
	if folder then
		folder:Destroy()
		folder = nil
	end
end

-- Where the cursor points on the ground -------------------------------------------------

local function filterList(): { Instance }
	local list: { Instance } = {}
	if player.Character then
		table.insert(list, player.Character)
	end
	if folder then
		table.insert(list, folder)
	end
	for _, name in { "SNEffects", "SNLocalDebris" } do
		local extra = workspace:FindFirstChild(name)
		if extra then
			table.insert(list, extra)
		end
	end
	return list
end

local function groundBelow(point: Vector3): Vector3?
	local result = workspace:Raycast(point + Vector3.new(0, 30, 0), Vector3.new(0, -120, 0), rayParams)
	return if result then result.Position else nil
end

local function groundAtScreen(position: Vector2): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ViewportPointToRay(position.X, position.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	if not result then
		return nil
	end
	return groundBelow(result.Position) or result.Position
end

local function defaultPoint(root: BasePart, range: number): Vector3
	local ahead = root.Position + (flat(root.CFrame.LookVector).Unit * math.min(range, range * 0.65 + 4))
	return groundBelow(ahead) or ahead
end

local function landingBlocked(point: Vector3): boolean
	local stand = point + Vector3.new(0, settings.LandingHeight, 0.0)
	local parts = workspace:GetPartBoundsInBox(CFrame.new(stand + Vector3.new(0, 0.3, 0)), settings.LandingBox, overlapParams)
	return #parts > 0
end

-- Starting, updating and ending ---------------------------------------------------------

local function unbindInput()
	ContextActionService:UnbindAction(ACTION)
	RunService:UnbindFromRenderStep(STEP)
end

function TargetingController:isActive(): boolean
	return active ~= nil
end

function TargetingController:cancel(silent: boolean?)
	local state = active
	if not state then
		return
	end
	active = nil
	unbindInput()
	destroyIndicator()
	if not silent then
		Vfx.sound("TargetCancel", (myRoot() or workspace.CurrentCamera) :: any)
	end
end

local function confirmEffects(state, point: Vector3)
	Vfx.ring(CFrame.new(point + Vector3.new(0, 0.25, 0)) * CFrame.Angles(math.pi / 2, 0, 0), math.max(2, state.radius), state.color, 0.25, 0.45, math.max(2, state.radius) * 1.3)
	Vfx.sound("TargetConfirm", point)
end

function TargetingController:confirm()
	local state = active
	if not state or not state.valid or not state.point then
		return
	end
	local root = myRoot()
	if not root then
		self:cancel(true)
		return
	end
	local point = state.point
	local toPoint = flat(point - root.Position)
	local direction = if toPoint.Magnitude > 1 then toPoint.Unit else flat(root.CFrame.LookVector)
	local onConfirm = state.onConfirm
	confirmEffects(state, point)
	self:cancel(true)
	onConfirm({ direction = direction, point = point })
end

-- Moves the reticle and recolours it; runs every frame while aiming
function TargetingController:_update(dt: number)
	local state = active
	if not state then
		return
	end
	local root, humanoid = myRoot()
	if not root or not humanoid then
		self:cancel(true)
		return
	end
	rayParams.FilterDescendantsInstances = filterList()
	overlapParams.FilterDescendantsInstances = filterList()
	local origin = root.Position
	local wanted: Vector3? = nil

	if state.touch then
		local touch = state.touch
		local position = Vector2.new(touch.input.Position.X, touch.input.Position.Y)
		touch.position = position
		if (position - touch.start).Magnitude > TAP_DISTANCE then
			touch.dragged = true
		end
		if touch.dragged then
			wanted = groundAtScreen(position)
		else
			wanted = defaultPoint(root, state.range)
		end
	elseif state.device == "gamepad" then
		local stick = Vector3.zero
		for _, gamepadState in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if gamepadState.KeyCode == Enum.KeyCode.Thumbstick2 then
				stick = gamepadState.Position
			end
		end
		local camera = workspace.CurrentCamera
		if camera and (math.abs(stick.X) > 0.12 or math.abs(stick.Y) > 0.12) then
			local right = flat(camera.CFrame.RightVector)
			local forward = flat(camera.CFrame.LookVector)
			if right.Magnitude > 0.01 and forward.Magnitude > 0.01 then
				state.reticle += (right.Unit * stick.X + forward.Unit * stick.Y) * RETICLE_SPEED * dt
			end
		end
		local limited = TargetingController.clampToRange(origin, state.reticle, state.range)
		state.reticle = Vector3.new(limited.X, origin.Y, limited.Z)
		wanted = groundBelow(state.reticle)
	else
		local mouse = UserInputService:GetMouseLocation()
		wanted = groundAtScreen(mouse)
	end

	local point: Vector3? = nil
	local valid = false
	if wanted then
		point = TargetingController.clampToRange(origin, wanted, state.range)
		if point ~= wanted then
			point = groundBelow(point) or point
		end
		valid = true
		if state.mode == "teleport" and point and landingBlocked(point) then
			valid = false
		end
	end
	state.point = point
	state.valid = valid

	local parts = state.parts
	parts.range.Size = Vector3.new(state.range * 2, 0.1, state.range * 2)
	parts.range.CFrame = CFrame.new(origin - Vector3.new(0, 2.9, 0))
	if point then
		local size = state.radius * 2
		parts.reticle.Size = Vector3.new(size, 0.1, size)
		parts.reticle.CFrame = CFrame.new(point + Vector3.new(0, 0.15, 0))
		local from = origin - Vector3.new(0, 2.5, 0)
		local length = (point - from).Magnitude
		parts.line.Size = Vector3.new(0.15, 0.15, math.max(0.1, length))
		parts.line.CFrame = CFrame.lookAt(from, point) * CFrame.new(0, 0, -length / 2)
		parts.line.Transparency = 0.55
	else
		parts.reticle.CFrame = CFrame.new(origin + Vector3.new(0, -500, 0))
		parts.line.Transparency = 1
	end
	setValidLook(state, valid)
end

local function colorOf(def: any): Color3
	local powerDef = Powers.get(def.power)
	local accent = powerDef and powerDef.colors and powerDef.colors.accent
	return if typeof(accent) == "Color3" then accent else VALID_COLOR
end

local function startState(entry, onConfirm, device: string)
	local def = entry.def
	local range, radius = TargetingController.shapeOf(def)
	local root = myRoot()
	local state = {
		entry = entry,
		mode = def.targeting,
		range = range,
		radius = radius,
		color = colorOf(def),
		onConfirm = onConfirm,
		device = device,
		valid = false,
		point = nil,
		reticle = if root then defaultPoint(root, range) else Vector3.zero,
	}
	return state
end

local function bindInput(self, state)
	local inputs: { any } = {
		Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2,
		Enum.KeyCode.Escape, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonR2, Enum.KeyCode.Thumbstick2,
	}
	-- The ability's own key confirms too
	local abilities = self.abilities
	if abilities and abilities.Bindings then
		for _, binding in abilities.Bindings do
			if binding.slot == state.entry.slot then
				for _, input in binding.inputs do
					if not table.find(inputs, input) then
						table.insert(inputs, input)
					end
				end
			end
		end
	end
	ContextActionService:BindActionAtPriority(ACTION, function(_, inputState, input)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			return Enum.ContextActionResult.Sink
		end
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			self:cancel()
		else
			self:confirm()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 10, table.unpack(inputs))
	RunService:BindToRenderStep(STEP, Enum.RenderPriority.Camera.Value + 3, function(dt)
		self:_update(dt)
	end)
end

-- Enters targeting mode for a point or teleport ability. onConfirm(aim) gets
-- { direction, point }. Pressing another ability replaces the current aim.
function TargetingController:begin(entry, onConfirm: (any) -> ()): boolean
	self:cancel(true)
	local device = if self.input and self.input.device then self.input.device() else "keyboard"
	local state = startState(entry, onConfirm, device)
	active = state
	buildIndicator(state)
	bindInput(self, state)
	self:_update(0)
	return true
end

-- Quick cast: the aim for the cursor right now, without entering the mode. Nil when
-- there is no ground under the cursor.
function TargetingController:quickAim(entry): { direction: Vector3, point: Vector3 }?
	local root = myRoot()
	if not root then
		return nil
	end
	rayParams.FilterDescendantsInstances = filterList()
	local range = TargetingController.shapeOf(entry.def)
	local device = if self.input and self.input.device then self.input.device() else "keyboard"
	local wanted
	if device == "keyboard" then
		wanted = groundAtScreen(UserInputService:GetMouseLocation())
	end
	wanted = wanted or defaultPoint(root, range)
	local point = TargetingController.clampToRange(root.Position, wanted, range)
	local toPoint = flat(point - root.Position)
	local direction = if toPoint.Magnitude > 1 then toPoint.Unit else flat(root.CFrame.LookVector)
	confirmEffects({ radius = select(2, TargetingController.shapeOf(entry.def)), color = colorOf(entry.def) }, point)
	return { direction = direction, point = point }
end

-- Touch: called when a finger lands on an ability button. Returns true when the
-- ability is a targeted one (the tap handler should then do nothing).
function TargetingController:touchBegin(entry, input: InputObject, button: GuiObject, onConfirm: (any) -> ()): boolean
	local def = entry.def
	local mode = def.targeting
	if not mode then
		return false
	end
	self:cancel(true)
	local state = startState(entry, onConfirm, "touch")
	local position = Vector2.new(input.Position.X, input.Position.Y)
	state.touch = { input = input, button = button, start = position, position = position, dragged = false }
	active = state
	buildIndicator(state)
	RunService:BindToRenderStep(STEP, Enum.RenderPriority.Camera.Value + 3, function(dt)
		self:_update(dt)
	end)
	self:_update(0)

	local ended
	ended = UserInputService.InputEnded:Connect(function(object)
		if object ~= input then
			return
		end
		ended:Disconnect()
		local current = active
		if current ~= state then
			return
		end
		local touch = state.touch
		-- Dragged back onto the button: cancel
		local inset = GuiService:GetGuiInset()
		local gui = button:FindFirstAncestorWhichIsA("ScreenGui")
		local shift = if gui and gui.IgnoreGuiInset then Vector2.zero else inset
		local at = touch.position - shift
		local low, high = button.AbsolutePosition - Vector2.new(6, 6), button.AbsolutePosition + button.AbsoluteSize + Vector2.new(6, 6)
		local overButton = at.X >= low.X and at.X <= high.X and at.Y >= low.Y and at.Y <= high.Y
		if touch.dragged and overButton then
			self:cancel()
			return
		end
		if not touch.dragged then
			-- A plain tap casts straight ahead
			state.valid = state.point ~= nil
		end
		self:confirm()
	end)
	return true
end

function TargetingController:Init(controllers)
	self.abilities = controllers.AbilityController
	self.input = controllers.InputController
end

function TargetingController:Start()
	-- Dying or being knocked out of action ends aiming
	player.CharacterRemoving:Connect(function()
		self:cancel(true)
	end)
end

-- Is quick cast on? Off by default.
function TargetingController.quickCastOn(): boolean
	local value = Settings.get("quickCast")
	if typeof(value) == "boolean" then
		return value
	end
	return settings.QuickCastDefault
end

return TargetingController
