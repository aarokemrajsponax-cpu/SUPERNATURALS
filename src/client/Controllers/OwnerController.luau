-- Owner-only client features: the owner panel (P to open), and flight
-- (G to toggle once enabled). The panel only appears if the server marked
-- this player as the owner, and the server re-checks every request anyway.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Components = require(script.Parent.Parent.UI.Components)
local OwnerPanel = require(script.Parent.Parent.UI.OwnerPanel)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AdminRequest = Remotes:WaitForChild("AdminRequest") :: RemoteEvent

local Action = Protocol.AdminAction
local Attribute = Protocol.Attribute

local player = Players.LocalPlayer

local OwnerController = {}

local FLY_SPEED = 60
local FLY_BOOST = 2.2

local built = false

local function send(action: string, first: any?, second: any?)
	AdminRequest:FireServer(action, first, second)
end

-- Flight ----------------------------------------------------------------------------------

local flight: { attachment: Attachment, mover: LinearVelocity, align: AlignOrientation, connection: RBXScriptConnection, humanoid: Humanoid }? = nil

local function stopFlying()
	local current = flight
	if not current then
		return
	end
	flight = nil
	current.connection:Disconnect()
	current.mover:Destroy()
	current.align:Destroy()
	current.attachment:Destroy()
	if current.humanoid.Parent then
		current.humanoid.PlatformStand = false
	end
end

local function startFlying()
	stopFlying()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "SNFlight"
	attachment.Parent = root
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.MaxForce = math.huge
	mover.VectorVelocity = Vector3.zero
	mover.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = math.huge
	align.Responsiveness = 40
	align.Parent = root
	humanoid.PlatformStand = true

	local connection = RunService.RenderStepped:Connect(function()
		if not root.Parent or humanoid.Health <= 0 then
			stopFlying()
			return
		end
		local camera = workspace.CurrentCamera
		local move = humanoid.MoveDirection
		local vertical = 0
		-- Typing an announcement mustn't fly you around
		local typing = UserInputService:GetFocusedTextBox() ~= nil
		local function keyDown(key: Enum.KeyCode): boolean
			return not typing and UserInputService:IsKeyDown(key)
		end
		if keyDown(Enum.KeyCode.Space) or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA) then
			vertical += 1
		end
		if keyDown(Enum.KeyCode.LeftControl) or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL2) then
			vertical -= 1
		end
		local speed = if keyDown(Enum.KeyCode.LeftShift) then FLY_SPEED * FLY_BOOST else FLY_SPEED
		-- Moving forward follows where the camera points, so you can dive and climb
		local look = camera.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		local forwardAmount = if flatLook.Magnitude > 0.01 then move:Dot(flatLook.Unit) else 0
		local velocity = move * speed + Vector3.new(0, look.Y * forwardAmount * speed + vertical * speed * 0.8, 0)
		mover.VectorVelocity = velocity
		if flatLook.Magnitude > 0.01 then
			local tilt = if move.Magnitude > 0.1 then -0.35 else 0
			align.CFrame = CFrame.lookAt(Vector3.zero, flatLook) * CFrame.Angles(tilt, 0, 0)
		end
	end)
	flight = { attachment = attachment, mover = mover, align = align, connection = connection, humanoid = humanoid }
end

local function syncFlight()
	if player:GetAttribute(Attribute.CanFly) == true then
		startFlying()
	else
		stopFlying()
	end
end

-- Panel -----------------------------------------------------------------------------------

local function build()
	if built or player:GetAttribute(Attribute.IsOwner) ~= true then
		return
	end
	built = true
	local gui = Components.make("ScreenGui", {
		Name = "SNOwner",
		ResetOnSpawn = false,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local scale = Components.make("UIScale", { Parent = gui })
	local function rescale()
		local viewport = workspace.CurrentCamera.ViewportSize
		-- Normal size on a desktop; on small screens as big as still fits the 800x520 panel
		local wanted = math.max(math.min(viewport.X / 1280, viewport.Y / 720), 0.62)
		local fits = math.min(viewport.X / 820, viewport.Y / 560)
		scale.Scale = math.clamp(math.min(wanted, fits), 0.3, 1.2)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()
	OwnerPanel.build(gui, send)
end

function OwnerController:Start()
	player:GetAttributeChangedSignal(Attribute.IsOwner):Connect(build)
	build()

	player:GetAttributeChangedSignal(Attribute.CanFly):Connect(syncFlight)
	player.CharacterAdded:Connect(function(character)
		stopFlying()
		character:WaitForChild("HumanoidRootPart", 5)
		task.wait(0.2)
		syncFlight()
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not built then
			return
		end
		if input.KeyCode == Enum.KeyCode.P then
			OwnerPanel.toggle()
		elseif input.KeyCode == Enum.KeyCode.G then
			send(Action.SelfToggle, "Fly", player:GetAttribute(Attribute.CanFly) ~= true)
		end
	end)
end

return OwnerController
