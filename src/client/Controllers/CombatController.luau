-- Turns the player's combat inputs into requests to the server, and shows
-- their own swings and dodges straight away so controls feel instant. The
-- server still decides everything; if it refuses, only the cosmetic preview
-- happened.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Poser = require(script.Parent.Parent.Effects.Poser)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CombatRequest = Remotes:WaitForChild("CombatRequest") :: RemoteEvent
local CombatEvent = Remotes:WaitForChild("CombatEvent") :: RemoteEvent

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

-- Still finishing a swing or dodge according to the server (this includes the
-- longer recovery after a missed heavy, which the client can't predict)
local function serverBusy(character: Model, leeway: number?): boolean
	return serverNow() < attributeTime(character, Attribute.BusyUntil) - (leeway or 0)
end

-- Attacks go where the camera looks, not wherever you happened to be walking.
-- Turning off auto-rotate straight away keeps that facing until the server's
-- own setting (no turning mid-attack) arrives.
local function faceCamera(root: BasePart, humanoid: Humanoid)
	local look = workspace.CurrentCamera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
		humanoid.AutoRotate = false
	end
end

local function removeDodgeMover(root: BasePart?)
	if not root then
		return
	end
	for _, child in root:GetChildren() do
		if child.Name == "SNDodge" then
			child:Destroy()
		end
	end
end

function CombatController:Init(controllers)
	self.effects = controllers.EffectsController
	self.abilities = controllers.AbilityController
	self.powerFx = controllers.PowerFxController
end

-- This fighter's combat numbers (their power, degree and form change them)
local function profileOf(character: Model)
	local powerId = character:GetAttribute(Attribute.Power)
	return Powers.combatProfile(
		if typeof(powerId) == "string" then powerId else nil,
		character:GetAttribute(Attribute.Degree),
		character:GetAttribute(Attribute.Form)
	)
end

-- Some powers replace Light/Heavy with their own move (blasters, animal bites):
-- send the aim along and show that move instead of a punch
function CombatController:_basicOverride(character: Model, root: BasePart, humanoid: Humanoid, kind: string): boolean
	local powerId = character:GetAttribute(Attribute.Power)
	local override = Powers.basicFor(
		if typeof(powerId) == "string" then powerId else nil,
		character:GetAttribute(Attribute.Degree),
		character:GetAttribute(Attribute.Form),
		kind
	)
	if not override then
		return false
	end
	local def = Powers.abilityFor(powerId, override, character:GetAttribute(Attribute.Degree) or 1)
	if def and serverNow() + Combat.Abilities.CooldownLeeway < attributeTime(character, Attribute.CooldownPrefix .. override) then
		return true
	end
	faceCamera(root, humanoid)
	CombatRequest:FireServer(if kind == "Light" then Action.Light else Action.Heavy, if self.abilities then self.abilities:aim() else nil)
	Poser.release(character, "Block")
	if self.powerFx then
		self.powerFx:predict(character, powerId, override)
	end
	return true
end

function CombatController:Start()
	player.CharacterAdded:Connect(function()
		chainStep, chainUntil, lightReadyAt, busyUntil, dodgeReadyAt = 0, 0, 0, 0, 0
		blocking = false
	end)

	-- Keep the server's block in step with the button: holding block through
	-- a stun (or a swing) raises it again once you can, without a parry
	-- window, and a block the server still has up after you let go is released
	task.spawn(function()
		while true do
			task.wait(0.2)
			local character, humanoid = myCharacter()
			if character and humanoid then
				local serverBlocking = character:GetAttribute(Attribute.Blocking) == true
				local free = canAct(character, humanoid) and os.clock() >= busyUntil and not serverBusy(character)
				if blocking and not serverBlocking and free then
					CombatRequest:FireServer(Action.BlockStart, "Held")
					Poser.hold(character, "Block")
				elseif not blocking and serverBlocking then
					CombatRequest:FireServer(Action.BlockEnd)
				end
				-- A swing turns auto-rotate off; turn it back on once nothing is playing
				if free and not humanoid.AutoRotate then
					humanoid.AutoRotate = true
				end
			end
		end
	end)

	-- When the server refuses something, undo the instant preview of it
	CombatEvent.OnClientEvent:Connect(function(kind, data)
		if kind ~= Protocol.CombatEvent.Rejected or typeof(data) ~= "table" then
			return
		end
		if data.action == Action.Dodge then
			local character = player.Character
			removeDodgeMover(character and character:FindFirstChild("HumanoidRootPart") :: BasePart?)
			dodgeReadyAt = 0
		elseif data.action == Action.Light or data.action == Action.Heavy then
			-- "busy" just means the press landed mid-swing; the swing still plays
			if data.reason == "busy" or data.reason == "buffered" then
				return
			end
			busyUntil = 0
			chainStep = 0
			lightReadyAt = 0
			local character, humanoid = myCharacter()
			if character and humanoid and canAct(character, humanoid) and not serverBusy(character) then
				humanoid.AutoRotate = true
			end
		end
	end)
end

function CombatController:light()
	local character, humanoid, root = myCharacter()
	if not character or not humanoid or not root or not canAct(character, humanoid) then
		return
	end
	if serverBusy(character, Combat.InputBuffer) then
		return
	end
	if self:_basicOverride(character, root, humanoid, "Light") then
		return
	end
	local profile = profileOf(character)
	faceCamera(root, humanoid)
	CombatRequest:FireServer(Action.Light)

	-- Preview the swing (also covers a press buffered near the end of a swing)
	local time = os.clock()
	if time < busyUntil - Combat.InputBuffer or time < lightReadyAt then
		return
	end
	local steps = profile.Light.Steps
	local start = math.max(time, busyUntil)
	if start > chainUntil or chainStep >= #steps then
		chainStep = 0
	end
	chainStep += 1
	local def = steps[chainStep]
	busyUntil = start + def.Startup + def.Active + def.Recovery
	chainUntil = busyUntil + profile.Light.ChainWindow
	if chainStep == #steps then
		lightReadyAt = busyUntil + profile.Light.ChainCooldown
	end
	-- Attacking drops the guard; let go of the block pose so it can't cut the swing short
	Poser.release(character, "Block")
	self.effects:predictAttack(character, "Light", chainStep, def, start - time)
end

function CombatController:heavy()
	local character, humanoid, root = myCharacter()
	if not character or not humanoid or not root or not canAct(character, humanoid) then
		return
	end
	local time = os.clock()
	if time < busyUntil or serverBusy(character) then
		return
	end
	if self:_basicOverride(character, root, humanoid, "Heavy") then
		return
	end
	if serverNow() < attributeTime(character, Attribute.HeavyReadyAt) then
		return
	end
	faceCamera(root, humanoid)
	CombatRequest:FireServer(Action.Heavy)
	local def = profileOf(character).Heavy
	busyUntil = time + def.Startup + def.Active + def.Recovery
	chainStep = 0
	Poser.release(character, "Block")
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
	if time < busyUntil or time < dodgeReadyAt or serverBusy(character) or serverNow() < attributeTime(character, Attribute.DodgeReadyAt) then
		return
	end
	local dodge = profileOf(character).Dodge
	dodgeReadyAt = time + dodge.Cooldown
	-- No attacking until the dodge (and its short recovery) is over
	busyUntil = math.max(busyUntil, time + dodge.Duration + dodge.Recovery)

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
	mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * dodge.Speed
	mover.MaxForce = math.huge
	mover.Parent = root
	Debris:AddItem(mover, dodge.Duration)
	Debris:AddItem(attachment, dodge.Duration)

	-- Dodging drops your block; say so explicitly in case the dodge is refused
	if blocking then
		blocking = false
		CombatRequest:FireServer(Action.BlockEnd)
		Poser.release(character, "Block")
	end
	CombatRequest:FireServer(Action.Dodge, direction)
	self.effects:predictDodge(character)
end

return CombatController
