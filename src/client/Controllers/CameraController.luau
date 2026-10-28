-- The camera: impact feedback (shake, a directional kick, a field-of-view
-- punch) and lock-on.
--
-- Lock-on (Z / middle mouse, R3, the touch Lock button) frames you over the
-- shoulder with the target in view, turns your character to face them so
-- movement strafes, and pulls in off walls. Tap again to switch target when
-- several are near (or flick the right stick / drag with the right mouse
-- button), hold to let go; with Settings.lockOnMode = "hold" it lasts while the
-- button is held. Roblox's own camera keeps running underneath: lock-on writes
-- the camera after it each frame, and blends in and out so nothing snaps.
-- It pauses (and never touches the camera) while the camera is Scriptable
-- (cinematics, results screens) and in the Shell's Editor and Cinematic modes.
-- Shake, kick and punch respect the player's Screen Shake setting.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Settings = require(script.Parent.Parent.Settings)
local Shell = require(script.Parent.Parent.UI.Shell)

local Attribute = Protocol.Attribute
local player = Players.LocalPlayer

local CameraController = {}

local BASE_FOV = 70
-- Lock-on framing and limits (studs, seconds)
local LOCK = {
	Range = 60,
	ReleaseRange = 85,
	-- Other enemies this close count for switching
	SwitchRange = 50,
	DistanceMin = 11,
	DistanceMax = 17,
	-- Over the right shoulder, and above it
	Shoulder = 2.4,
	Height = 2.4,
	-- How quickly the camera follows (higher is tighter)
	Follow = 9,
	-- How far off a wall the camera stays when pulled in
	WallGap = 0.7,
	BlendIn = 0.25,
	BlendOut = 0.35,
	-- How fast the character turns to face the target (degrees per second)
	TurnRate = 900,
	-- Holding the button this long while locked lets go (toggle mode)
	HoldToRelease = 0.4,
}

local shakeUntil = 0
local shakeStrength = 0
-- The kick: a small rotation that springs back (degrees and degrees/second)
local kickAngle = Vector2.zero
local kickVelocity = Vector2.zero
-- The wobble added last frame. Roblox's camera scripts build each frame from the
-- previous camera CFrame, so the wobble is removed before they run, or it would
-- slowly turn the view for good.
local lastOffset = CFrame.identity

local lockTarget: Model? = nil
-- 0..1 how much lock-on owns the camera (eases in and out)
local lockBlend = 0
local lockCFrame: CFrame? = nil
local lockLook = Vector3.new(0, 0, -1)
-- Last frame's lock state, for blending out after release
local releasing = false
local pressToken = 0
local pressedAt = 0
local pressAcquired = false
local stickCentered = true
local mouseSwipe = 0
local mouseSwipeAt = 0

local lockChanged = Instance.new("BindableEvent")
-- Fires with (target: Model?) when lock-on starts, switches or ends
CameraController.lockChanged = lockChanged.Event

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function alive(model: Model?): boolean
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and model ~= nil and model.Parent ~= nil
end

-- Concealed (the Ghost's veil) or the owner's invisibility: not a target
local function hidden(model: Model): boolean
	if serverNow() < (model:GetAttribute(Attribute.StatusPrefix .. "Concealed") or 0) then
		return true
	end
	local owner = Players:GetPlayerFromCharacter(model)
	return owner ~= nil and owner:GetAttribute(Attribute.Invisible) == true
end

local function validTarget(model: Model?, range: number): boolean
	if not model or model == player.Character or not alive(model) or hidden(model) then
		return false
	end
	local mine, theirs = rootOf(player.Character), rootOf(model)
	return mine ~= nil and theirs ~= nil and (theirs.Position - mine.Position).Magnitude <= range
end

-- Lock-on waits while something else owns the camera
local function paused(): boolean
	local camera = workspace.CurrentCamera
	if not camera or camera.CameraType == Enum.CameraType.Scriptable then
		return true
	end
	local mode = Shell.getMode()
	return mode == "Editor" or mode == "Cinematic"
end

-- Fighters worth locking onto, best first: close to where the camera looks, then near
local function candidates(range: number): { Model }
	local camera = workspace.CurrentCamera
	local mine = rootOf(player.Character)
	if not camera or not mine then
		return {}
	end
	local scored = {}
	for _, model in CollectionService:GetTagged(Protocol.Tag.Fighter) do
		if model:IsA("Model") and validTarget(model, range) then
			local root = rootOf(model) :: BasePart
			local offset = root.Position - camera.CFrame.Position
			local facing = if offset.Magnitude > 0.01 then camera.CFrame.LookVector:Dot(offset.Unit) else 1
			local distance = (root.Position - mine.Position).Magnitude
			-- Behind the camera only counts when it's right next to you
			if facing > 0.1 or distance < 12 then
				table.insert(scored, { model = model, score = distance * (1 + 2.5 * (1 - facing)) })
			end
		end
	end
	table.sort(scored, function(a, b)
		return a.score < b.score
	end)
	local list = {}
	for _, entry in scored do
		table.insert(list, entry.model)
	end
	return list
end

local function setTarget(target: Model?)
	if target == lockTarget then
		return
	end
	local had = lockTarget ~= nil
	lockTarget = target
	if target and not had then
		releasing = false
		lockCFrame = nil
	elseif not target and had then
		releasing = true
		-- Give the character its normal turning back
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and serverNow() >= ((player.Character :: Model):GetAttribute(Attribute.BusyUntil) or 0) then
			humanoid.AutoRotate = true
		end
	end
	lockChanged:Fire(target)
end

function CameraController:Start()
	RunService:BindToRenderStep("SNCameraUnshake", Enum.RenderPriority.Camera.Value - 1, function()
		if lastOffset ~= CFrame.identity then
			local camera = workspace.CurrentCamera
			camera.CFrame *= lastOffset:Inverse()
			lastOffset = CFrame.identity
		end
	end)
	RunService:BindToRenderStep("SNCameraLock", Enum.RenderPriority.Camera.Value + 1, function(dt)
		self:_updateLock(dt)
	end)
	RunService:BindToRenderStep("SNCameraShake", Enum.RenderPriority.Camera.Value + 2, function(dt)
		self:_applyShake(dt)
	end)

	-- Switching targets with a flick of the right stick, or a right-drag of the mouse
	UserInputService.InputChanged:Connect(function(input)
		if not lockTarget then
			return
		end
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local x = input.Position.X
			if stickCentered and math.abs(x) > 0.75 then
				stickCentered = false
				self:switchTarget(if x > 0 then 1 else -1)
			elseif math.abs(x) < 0.35 then
				stickCentered = true
			end
		elseif input.UserInputType == Enum.UserInputType.MouseMovement and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
			local time = os.clock()
			if time - mouseSwipeAt > 0.25 then
				mouseSwipe = 0
			end
			mouseSwipeAt = time
			mouseSwipe += input.Delta.X
			if math.abs(mouseSwipe) > 140 then
				self:switchTarget(if mouseSwipe > 0 then 1 else -1)
				mouseSwipe = 0
			end
		end
	end)

	player.CharacterAdded:Connect(function()
		setTarget(nil)
	end)
end

-- Lock-on -------------------------------------------------------------------------------

function CameraController:getLockTarget(): Model?
	return if lockTarget and not paused() then lockTarget else nil
end

function CameraController:isLocked(): boolean
	return lockTarget ~= nil
end

-- Locks onto the best target in view. Returns whether one was found.
function CameraController:lock(): boolean
	if paused() or not alive(player.Character) then
		return false
	end
	local target = candidates(LOCK.Range)[1]
	if target then
		setTarget(target)
		return true
	end
	return false
end

function CameraController:unlock()
	setTarget(nil)
end

-- Moves the lock to another nearby enemy: side = -1 (left), 1 (right) or 0 (the
-- next best). Returns false when there's nobody else.
function CameraController:switchTarget(side: number?): boolean
	local current = lockTarget
	local camera = workspace.CurrentCamera
	if not current or not camera then
		return false
	end
	local others = {}
	for _, model in candidates(LOCK.SwitchRange) do
		if model ~= current then
			table.insert(others, model)
		end
	end
	if #others == 0 then
		return false
	end
	local pick = others[1]
	if side and side ~= 0 then
		-- The closest one on that side of the current target, as seen from the camera
		local currentRoot = rootOf(current)
		local right = camera.CFrame.RightVector
		local best, bestScore = nil, math.huge
		for _, model in others do
			local root = rootOf(model)
			if root and currentRoot then
				local across = (root.Position - currentRoot.Position):Dot(right) * side
				if across > 0.5 and across < bestScore then
					best, bestScore = model, across
				end
			end
		end
		if not best then
			return false
		end
		pick = best
	end
	setTarget(pick)
	return true
end

-- The lock-on button. Toggle mode: press to lock; while locked, a tap switches
-- target (or lets go when nobody else is near) and a hold lets go. Hold mode:
-- locked while the button is down.
function CameraController:lockInput(began: boolean)
	if Settings.get("lockOnMode") == "hold" then
		if began then
			self:lock()
		else
			self:unlock()
		end
		return
	end
	pressToken += 1
	local token = pressToken
	if began then
		pressedAt = os.clock()
		pressAcquired = false
		if not lockTarget then
			pressAcquired = self:lock()
		else
			-- Still held after a moment: let go right away
			task.delay(LOCK.HoldToRelease, function()
				if token == pressToken and lockTarget then
					pressToken += 1
					self:unlock()
				end
			end)
		end
	elseif lockTarget and not pressAcquired and os.clock() - pressedAt < LOCK.HoldToRelease then
		if not self:switchTarget(0) then
			self:unlock()
		end
	end
end

-- Where the character should face while locked (flat, unit), or nil
function CameraController:lockDirection(): Vector3?
	local mine, theirs = rootOf(player.Character), rootOf(lockTarget)
	if not mine or not theirs or paused() then
		return nil
	end
	local flat = Vector3.new(theirs.Position.X - mine.Position.X, 0, theirs.Position.Z - mine.Position.Z)
	return if flat.Magnitude > 0.2 then flat.Unit else nil
end

-- Keeps the camera from ending up inside a wall between `from` and `to`
local function pullIn(from: Vector3, to: Vector3, ignore: { Instance }): Vector3
	local offset = to - from
	if offset.Magnitude < 0.05 then
		return to
	end
	rayParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(from, offset, rayParams)
	if hit then
		return hit.Position - offset.Unit * LOCK.WallGap
	end
	return to
end

function CameraController:_updateLock(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	-- Targets that die, leave, hide or get too far are let go
	if lockTarget and not validTarget(lockTarget, LOCK.ReleaseRange) then
		setTarget(nil)
	end
	if lockTarget and not alive(player.Character) then
		setTarget(nil)
	end
	if paused() then
		-- Leave the camera alone; resume blending in afterwards
		lockBlend = 0
		lockCFrame = nil
		return
	end
	local active = lockTarget ~= nil
	local goal = if active then 1 else 0
	local rate = dt / (if active then LOCK.BlendIn else LOCK.BlendOut)
	lockBlend = math.clamp(lockBlend + (if goal > lockBlend then rate else -rate), 0, 1)
	if lockBlend <= 0 then
		releasing = false
		lockCFrame = nil
		return
	end

	local character = player.Character
	local mine = rootOf(character)
	if not character or not mine then
		return
	end
	local theirs = rootOf(lockTarget)
	local pivot = mine.Position + Vector3.new(0, 1.6, 0)
	local aim = if theirs then theirs.Position + Vector3.new(0, 0.6, 0) else pivot + lockLook * 10
	local flat = Vector3.new(aim.X - pivot.X, 0, aim.Z - pivot.Z)
	if flat.Magnitude > 0.5 then
		lockLook = flat.Unit
	end
	local separation = flat.Magnitude
	local right = lockLook:Cross(Vector3.yAxis)
	local distance = math.clamp(8 + separation * 0.3, LOCK.DistanceMin, LOCK.DistanceMax)
	local desired = pivot - lockLook * distance + Vector3.yAxis * (LOCK.Height + separation * 0.03) + right * LOCK.Shoulder
	-- Look between the two, weighted toward the target so both stay in frame
	local focus = pivot:Lerp(aim, if separation > 4 then 0.6 else 0.4)
	local want = CFrame.lookAt(desired, focus)
	local follow = 1 - math.exp(-LOCK.Follow * dt)
	local current = lockCFrame or camera.CFrame
	local smoothed = current:Lerp(want, follow)
	lockCFrame = smoothed

	-- Walls: pull in instantly (from the shoulder), ease back out with the smoothing
	local ignore: { Instance } = { character, camera }
	if lockTarget then
		table.insert(ignore, lockTarget)
	end
	local shoulder = pivot + right * (LOCK.Shoulder * 0.5)
	local safe = pullIn(shoulder, smoothed.Position, ignore)
	local final = CFrame.lookAt(safe, safe + smoothed.LookVector)

	local blend = lockBlend * lockBlend * (3 - 2 * lockBlend)
	camera.CFrame = camera.CFrame:Lerp(final, blend)
	camera.Focus = CFrame.new(focus)

	-- Face the target and strafe, except mid-swing (no turning during an attack)
	if active and theirs then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if humanoid.AutoRotate then
				humanoid.AutoRotate = false
			end
			local busy = serverNow() < (character:GetAttribute(Attribute.BusyUntil) or 0)
				or serverNow() < (character:GetAttribute(Attribute.DownedUntil) or 0)
			if not busy then
				local look = mine.CFrame.LookVector
				local flatLook = Vector3.new(look.X, 0, look.Z)
				if flatLook.Magnitude > 0.01 then
					local angle = math.atan2(flatLook.Unit:Cross(lockLook).Y, flatLook.Unit:Dot(lockLook))
					local step = math.rad(LOCK.TurnRate) * dt
					local turn = math.clamp(angle, -step, step)
					if math.abs(turn) > 1e-4 then
						mine.CFrame = CFrame.new(mine.Position) * CFrame.Angles(0, turn, 0) * mine.CFrame.Rotation
					end
				end
			end
		end
	end
end

-- Impact feedback -------------------------------------------------------------------------

function CameraController:_applyShake(dt: number)
	local camera = workspace.CurrentCamera
	if not camera or camera.CameraType == Enum.CameraType.Scriptable then
		kickAngle, kickVelocity = Vector2.zero, Vector2.zero
		return
	end
	-- The kick springs back (stiff and well damped: a jolt, not a wobble)
	local step = math.min(dt, 1 / 30)
	local acceleration = -kickAngle * 260 - kickVelocity * 26
	kickVelocity += acceleration * step
	kickAngle += kickVelocity * step
	if kickAngle.Magnitude < 0.01 and kickVelocity.Magnitude < 0.05 then
		kickAngle, kickVelocity = Vector2.zero, Vector2.zero
	end
	local offset = CFrame.Angles(math.rad(kickAngle.X), math.rad(kickAngle.Y), 0)

	local remaining = shakeUntil - os.clock()
	if remaining > 0 then
		local strength = shakeStrength * math.min(1, remaining * 6)
		local t = os.clock() * 40
		offset *= CFrame.Angles(
			math.rad(math.noise(t, 0) * strength),
			math.rad(math.noise(0, t) * strength),
			math.rad(math.noise(t, t) * strength * 0.5)
		)
	end
	if offset ~= CFrame.identity then
		camera.CFrame *= offset
		lastOffset = offset
	end
end

-- strength is in degrees of wobble; overlapping shakes keep the strongest
function CameraController:shake(strength: number, duration: number)
	if not Settings.get("cameraShake") then
		return
	end
	local time = os.clock()
	if time >= shakeUntil then
		shakeStrength = 0
	end
	shakeStrength = math.max(shakeStrength, strength)
	shakeUntil = math.max(shakeUntil, time + duration)
end

-- A directional jolt: the view is knocked along `direction` (world space, the
-- way the hit pushes) by about `strength` degrees, and springs back
function CameraController:kick(direction: Vector3?, strength: number)
	if not Settings.get("cameraShake") then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local side, up = 0, 0.6
	if direction and direction.Magnitude > 1e-3 then
		local unit = direction.Unit
		side = -unit:Dot(camera.CFrame.RightVector)
		up = 0.45 + math.max(0, -unit:Dot(camera.CFrame.LookVector)) * 0.4
	end
	kickVelocity += Vector2.new(up, side * 0.8) * strength * 24
end

function CameraController:punch(amount: number)
	if not Settings.get("cameraShake") then
		return
	end
	local camera = workspace.CurrentCamera
	camera.FieldOfView = BASE_FOV + amount
	TweenService:Create(camera, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = BASE_FOV,
	}):Play()
end

CameraController.LockSettings = LOCK

return CameraController
