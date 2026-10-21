-- Turns the player's combat inputs into requests to the server, and shows
-- their own swings and dodges straight away so controls feel instant. The
-- server still decides everything; if it refuses, only the cosmetic preview
-- happened.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Poser = require(script.Parent.Parent.Effects.Poser)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CombatRequest = Remotes:WaitForChild("CombatRequest") :: RemoteEvent

local Action = Protocol.CombatAction
local Attribute = Protocol.Attribute

local player = Players.LocalPlayer

local CombatController = {}

-- Local copies of the server's timing, used only for the instant preview
local chainStep = 0
local chainUntil = 0
local lightReadyAt = 0
local busyUntil = 0
local dodgeReadyAt = 0
local blocking = false

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function myCharacter(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return character, humanoid, root
	end
	return nil, nil, nil
end

-- Stunned, knocked out or frozen for a countdown: the server sets walk speed to 0
local function attributeTime(character: Model, name: string): number
	local value = character:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function canAct(character: Model, humanoid: Humanoid): boolean
	return humanoid.WalkSpeed > 0 and serverNow() >= attributeTime(character, Attribute.StunnedUntil)
end

-- Attacks go where the camera looks, not wherever you happened to be walking
local function faceCamera(root: BasePart)
	local look = workspace.CurrentCamera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
	end
end

function CombatController:Init(controllers)
	self.effects = controllers.EffectsController
end

function CombatController:Start()
	player.CharacterAdded:Connect(function()
		chainStep, chainUntil, lightReadyAt, busyUntil, dodgeReadyAt = 0, 0, 0, 0, 0
		blocking = false
	end)

	-- Holding block through a stun (or a swing) raises it again once you can,
	-- without a parry window
	task.spawn(function()
		while true do
			task.wait(0.2)
			local character, humanoid = myCharacter()
			if blocking and character and humanoid and canAct(character, humanoid)
				and os.clock() >= busyUntil
				and character:GetAttribute(Attribute.Blocking) ~= true
			then
				CombatRequest:FireServer(Action.BlockStart, "Held")
			end
		end
	end)
end

function CombatController:light()
	local character, humanoid, root = myCharacter()
	if not character or not humanoid or not root or not canAct(character, humanoid) then
		return
	end
	faceCamera(root)
	CombatRequest:FireServer(Action.Light)

	-- Preview the swing (also covers a press buffered near the end of a swing)
	local time = os.clock()
	if time < busyUntil - Combat.InputBuffer or time < lightReadyAt then
		return
	end
	local steps = Combat.Light.Steps
	local start = math.max(time, busyUntil)
	if start > chainUntil or chainStep >= #steps then
		chainStep = 0
	end
	chainStep += 1
	local def = steps[chainStep]
	busyUntil = start + def.Startup + def.Active + def.Recovery
	chainUntil = busyUntil + Combat.Light.ChainWindow
	if chainStep == #steps then
		lightReadyAt = busyUntil + Combat.Light.ChainCooldown
	end
	self.effects:predictAttack(character, "Light", chainStep, def, start - time)
end

function CombatController:heavy()
	local character, humanoid, root = myCharacter()
	if not character or not humanoid or not root or not canAct(character, humanoid) then
		return
	end
	local time = os.clock()
	if time < busyUntil or serverNow() < attributeTime(character, Attribute.HeavyReadyAt) then
		return
	end
	faceCamera(root)
	CombatRequest:FireServer(Action.Heavy)
	local def = Combat.Heavy
	busyUntil = time + def.Startup + def.Active + def.Recovery
	chainStep = 0
	self.effects:predictAttack(character, "Heavy", 1, def, 0)
end

function CombatController:setBlocking(on: boolean)
	if on == blocking then
		return
	end
	blocking = on
	CombatRequest:FireServer(if on then Action.BlockStart else Action.BlockEnd)
	local character = player.Character
	if on then
		Poser.hold(character, "Block")
	else
		Poser.release(character, "Block")
	end
end

function CombatController:dodge()
	local character, humanoid, root = myCharacter()
	if not character or not humanoid or not root or not canAct(character, humanoid) then
		return
	end
	local time = os.clock()
	if time < busyUntil or time < dodgeReadyAt or serverNow() < attributeTime(character, Attribute.DodgeReadyAt) then
		return
	end
	dodgeReadyAt = time + Combat.Dodge.Cooldown

	-- Dash where you're moving; standing still dashes backwards
	local moving = humanoid.MoveDirection
	local direction = Vector3.new(moving.X, 0, moving.Z)
	if direction.Magnitude < 0.1 then
		direction = -Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	if direction.Magnitude < 0.1 then
		return
	end
	direction = direction.Unit

	-- This client simulates its own character, so it moves it right away
	local attachment = Instance.new("Attachment")
	attachment.Name = "SNDodge"
	attachment.Parent = root
	local mover = Instance.new("LinearVelocity")
	mover.Name = "SNDodge"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * Combat.Dodge.Speed
	mover.MaxForce = math.huge
	mover.Parent = root
	Debris:AddItem(mover, Combat.Dodge.Duration)
	Debris:AddItem(attachment, Combat.Dodge.Duration)

	CombatRequest:FireServer(Action.Dodge, direction)
	if blocking then
		blocking = false
		Poser.release(character, "Block")
	end
	self.effects:predictDodge(character)
end

return CombatController
