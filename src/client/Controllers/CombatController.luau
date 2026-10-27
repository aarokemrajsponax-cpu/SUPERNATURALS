-- Turns the player's combat inputs into requests to the server, and shows
-- their own moves straight away so controls feel instant. The server still
-- decides everything (which move a press becomes, whether it lands, every
-- state); if it refuses, the cosmetic preview is undone.
--
-- Every press that has a direction sends { dir = flat Humanoid.MoveDirection },
-- so the server can tell sprint strikes, the Launcher (back + Heavy) and the
-- dodge direction apart. Heavy is held to charge (HeavyRelease on let go; a short
-- press is a normal heavy). Block during your own heavy's wind-up is a feint.

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
local Event = Protocol.CombatEvent

local player = Players.LocalPlayer

local CombatController = {}

-- Local copies of the server's timing, used only for the instant preview
local chainStep = 0
local chainUntil = 0
local lightReadyAt = 0
local busyUntil = 0
local dodgeReadyAt = 0
local grabReadyAt = 0
local sweepReadyAt = 0
local tauntReadyAt = 0
local feintReadyAt = 0
-- The end of a heavy's wind-up (Block before then is a feint)
local heavyWindupUntil = 0
local blocking = false
-- The charge being held: { startedAt, profile } (nil when not charging)
local charge: { startedAt: number, profile: any }? = nil
local heavyHeld = false
local lastHeavyCharged = false
-- Sprint: what the player asks for (held key or toggled stick)
local sprintWanted = false
local sprintToggle = false
local sprintSentAt = 0
local stillSince = 0
-- The last swing, for dodge-cancelling a light that landed
local lastSwing = { kind = "", activeEnd = 0, lunge = false }
local lightLandedAt = -math.huge
-- A basic grab caught us: Light/Grab presses go to the server as a tech
local grabbedUntil = 0
-- The current self-driven dodge (so the server's numbers can correct it)
local dodgeMover: LinearVelocity? = nil
local dodgeEndsAt = 0

-- Names the server gives light steps when a power's chain doesn't name them
local LIGHT_MOVES = { "Jab", "Cross", "Hook" }

-- When something was refused for lack of stamina (the HUD flashes the bar)
CombatController.lastWindedReject = -math.huge

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

local function attributeTime(character: Model, name: string): number
	local value = character:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

-- Stunned, knocked out or frozen for a countdown: the server sets walk speed to 0
local function canAct(character: Model, humanoid: Humanoid): boolean
	return humanoid.WalkSpeed > 0 and serverNow() >= attributeTime(character, Attribute.StunnedUntil)
end

-- Still finishing a swing or dodge according to the server (this includes the
-- longer recovery after a missed heavy, which the client can't predict)
local function serverBusy(character: Model, leeway: number?): boolean
	return serverNow() < attributeTime(character, Attribute.BusyUntil) - (leeway or 0)
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Movement intent: where the stick or WASD points, in world space (camera relative)
local function moveIntent(humanoid: Humanoid): Vector3
	local intent = flat(humanoid.MoveDirection)
	if intent.Magnitude > 1 then
		intent = intent.Unit
	end
	return intent
end

local function winded(character: Model): boolean
	return character:GetAttribute(Attribute.Winded) == true
end

local function inAir(humanoid: Humanoid, root: BasePart): boolean
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
		return true
	end
	return humanoid.FloorMaterial == Enum.Material.Air and math.abs(root.AssemblyLinearVelocity.Y) > 4
end

-- Sprinting (as the server has it) and actually moving
local function running(character: Model, root: BasePart, intent: Vector3): boolean
	if character:GetAttribute(Attribute.Sprinting) ~= true then
		return false
	end
	return flat(root.AssemblyLinearVelocity).Magnitude >= 8 or intent.Magnitude >= 0.5
end

function CombatController:Init(controllers)
	self.effects = controllers.EffectsController
	self.abilities = controllers.AbilityController
	self.powerFx = controllers.PowerFxController
	self.camera = controllers.CameraController
end

-- Attacks go where the camera looks (or at the lock-on target), not wherever you
-- happened to be walking. Turning off auto-rotate straight away keeps that facing
-- until the server's own setting (no turning mid-attack) arrives.
function CombatController:_face(root: BasePart, humanoid: Humanoid)
	local direction = self.camera and self.camera:lockDirection()
	if not direction then
		direction = flat(workspace.CurrentCamera.CFrame.LookVector)
	end
	if direction.Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + direction.Unit)
		humanoid.AutoRotate = false
	end
end

local function removeDodgeMover(root: BasePart?)
	dodgeMover = nil
	if not root then
		return
	end
	for _, child in root:GetChildren() do
		if child.Name == "SNDodge" then
			child:Destroy()
		end
	end
end

-- Moves this client's own character for a dodge (the server doesn't move players)
local function moveDodge(root: BasePart, direction: Vector3, speed: number, duration: number)
	removeDodgeMover(root)
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
	mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * speed
	mover.MaxForce = math.huge
	mover.Parent = root
	Debris:AddItem(mover, duration)
	Debris:AddItem(attachment, duration)
	dodgeMover = mover
	dodgeEndsAt = os.clock() + duration
end

-- Same rule as the server's FighterState.dodgeStyle
local function dodgeStyle(look: Vector3, intent: Vector3): string
	if intent.Magnitude < 0.3 or look.Magnitude < 1e-4 then
		return "Back"
	end
	local along = intent.Unit:Dot(look.Unit)
	if along > 0.5 then
		return "Forward"
	elseif along < -0.5 then
		return "Back"
	end
	return "Side"
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

local function noteWinded()
	CombatController.lastWindedReject = os.clock()
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
	self:_face(root, humanoid)
	local payload = {}
	local aim = if self.abilities then self.abilities:aim() else nil
	if typeof(aim) == "table" then
		for key, value in aim do
			payload[key] = value
		end
	end
	payload.dir = moveIntent(humanoid)
	CombatRequest:FireServer(if kind == "Light" then Action.Light else Action.Heavy, payload)
	Poser.release(character, "Block")
	if self.powerFx then
		self.powerFx:predict(character, powerId, override)
	end
	return true
end

function CombatController:Start()
	player.CharacterAdded:Connect(function()
		chainStep, chainUntil, lightReadyAt, busyUntil, dodgeReadyAt = 0, 0, 0, 0, 0
		grabReadyAt, sweepReadyAt, tauntReadyAt, feintReadyAt, heavyWindupUntil = 0, 0, 0, 0, 0
		blocking, charge, heavyHeld, grabbedUntil = false, nil, false, 0
		sprintWanted, sprintToggle = false, false
		dodgeMover = nil
	end)

	-- Keep the server's block (and sprint) in step with the buttons: holding block
	-- through a stun (or a swing) raises it again once you can, without a parry
	-- window, and a block the server still has up after you let go is released
	task.spawn(function()
		while true do
			task.wait(0.2)
			self:_keepInStep()
		end
	end)

	CombatEvent.OnClientEvent:Connect(function(kind, data)
		if typeof(data) ~= "table" then
			return
		end
		if kind == Event.Rejected then
			self:_onRejected(data)
		elseif kind == Event.Dodge then
			self:_onDodge(data)
		elseif kind == Event.Motion then
			self:_onMotion(data)
		elseif kind == Event.Hit then
			self:_onHit(data)
		elseif kind == Event.Grab then
			self:_onGrab(data)
		elseif kind == Event.Clash then
			if data.a == player.Character or data.b == player.Character then
				self:_dropCharge()
			end
		end
	end)
end

function CombatController:_keepInStep()
	local character, humanoid, root = myCharacter()
	if not character or not humanoid or not root then
		return
	end
	local serverBlocking = character:GetAttribute(Attribute.Blocking) == true
	local free = canAct(character, humanoid) and os.clock() >= busyUntil and not serverBusy(character)
	if blocking and not serverBlocking and free and charge == nil then
		CombatRequest:FireServer(Action.BlockStart, "Held")
		Poser.hold(character, "Block")
	elseif not blocking and serverBlocking then
		CombatRequest:FireServer(Action.BlockEnd)
	end
	-- A swing turns auto-rotate off; turn it back on once nothing is playing
	-- (lock-on keeps it off to face the target)
	local locked = self.camera ~= nil and self.camera:isLocked()
	if free and not humanoid.AutoRotate and not locked then
		humanoid.AutoRotate = true
	end

	-- Sprint: a toggled sprint ends when you stop moving; a held one comes back
	-- by itself once there's stamina again
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	if moving then
		stillSince = os.clock()
	end
	if sprintToggle and not moving and os.clock() - stillSince > 0.6 then
		self:setSprinting(false)
	end
	local sprinting = character:GetAttribute(Attribute.Sprinting) == true
	if sprintWanted and not sprinting and moving and os.clock() - sprintSentAt > 0.8 and self:_canSprint(character) then
		sprintSentAt = os.clock()
		CombatRequest:FireServer(Action.SprintStart)
	end
end

function CombatController:_canSprint(character: Model): boolean
	if winded(character) then
		return false
	end
	local stamina = character:GetAttribute(Attribute.Stamina)
	return typeof(stamina) ~= "number" or stamina >= Combat.Sprint.MinStamina
end

-- The server's answers ---------------------------------------------------------------

-- When the server refuses something, undo the instant preview of it
function CombatController:_onRejected(data)
	local action, reason = data.action, data.reason
	local character, humanoid = myCharacter()
	if reason == "winded" then
		noteWinded()
	end
	if action == Action.Dodge then
		removeDodgeMover(character and character:FindFirstChild("HumanoidRootPart") :: BasePart?)
		dodgeReadyAt = 0
		busyUntil = 0
		if self.effects and character then
			self.effects:cancelPrediction(character)
		end
	elseif action == Action.Light or action == Action.Heavy or action == Action.Grab or action == Action.Sweep or action == Action.Taunt then
		-- "busy" just means the press landed mid-swing; the swing still plays
		if reason == "busy" or reason == "buffered" then
			return
		end
		if action == Action.Heavy then
			self:_dropCharge()
			-- Out of stamina to charge: throw a plain heavy instead, if still held
			if reason == "winded" and lastHeavyCharged and heavyHeld and character and humanoid then
				lastHeavyCharged = false
				CombatRequest:FireServer(Action.Heavy, { dir = moveIntent(humanoid) })
				local heavy = profileOf(character).Heavy
				busyUntil = os.clock() + heavy.Startup + heavy.Active + heavy.Recovery
				heavyWindupUntil = os.clock() + heavy.Startup
				self.effects:predictMove(character, "Heavy", heavy, 0)
				return
			end
		elseif action == Action.Grab then
			grabReadyAt = 0
		elseif action == Action.Sweep then
			sweepReadyAt = 0
		elseif action == Action.Taunt then
			tauntReadyAt = 0
		end
		busyUntil = 0
		chainStep = 0
		lightReadyAt = 0
		heavyWindupUntil = 0
		if character and humanoid then
			if self.effects then
				self.effects:cancelPrediction(character)
			end
			if canAct(character, humanoid) and not serverBusy(character) and not (self.camera and self.camera:isLocked()) then
				humanoid.AutoRotate = true
			end
		end
	elseif action == Action.SprintStart then
		-- Held sprint retries by itself when there's stamina again
		sprintSentAt = os.clock()
	end
end

-- The server's dodge: its direction and speed win over the prediction
function CombatController:_onDodge(data)
	local character = player.Character
	if data.fighter ~= character or not character then
		return
	end
	local direction, speed = data.direction, data.speed
	if typeof(direction) ~= "Vector3" or typeof(speed) ~= "number" then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local flatDirection = flat(direction)
	if flatDirection.Magnitude < 0.01 then
		return
	end
	flatDirection = flatDirection.Unit
	if dodgeMover and dodgeMover.Parent and os.clock() < dodgeEndsAt then
		dodgeMover.PlaneVelocity = Vector2.new(flatDirection.X, flatDirection.Z) * speed
	elseif os.clock() > dodgeEndsAt + 0.3 then
		-- Not previewed (it was thought to be on cooldown): move now for what's left
		local duration = if typeof(data.duration) == "number" then math.clamp(data.duration, 0.05, 0.4) else 0.18
		moveDodge(root, flatDirection, speed, duration)
	end
end

function CombatController:_dropCharge()
	if charge then
		charge = nil
		local character = player.Character
		if character and self.effects then
			self.effects:cancelCharge(character)
		end
	end
end

function CombatController:_onMotion(data)
	local character = player.Character
	if not character or data.fighter ~= character then
		return
	end
	local motion = data.motion
	if motion == "Feint" then
		charge = nil
		heavyWindupUntil = 0
		busyUntil = os.clock() + (if typeof(data.duration) == "number" then data.duration else Combat.Feint.Recovery)
	elseif motion == "Knockdown" then
		self:_dropCharge()
		busyUntil = 0
		heavyWindupUntil = 0
	elseif motion == "PickUp" or motion == "Drop" then
		-- Picking a prop up instead of grabbing: hands are free to throw at once
		busyUntil = 0
	end
end

function CombatController:_onHit(data)
	local character = player.Character
	if not character then
		return
	end
	if data.victim == character and (data.result == "Hit" or data.result == "GuardBreak" or data.result == "Parried") then
		-- Getting hit cancels a charge on the server
		self:_dropCharge()
	elseif data.attacker == character and data.result == "Parried" then
		self:_dropCharge()
	end
	if data.attacker == character and data.result == "Hit" and data.kind == "Light" then
		lightLandedAt = os.clock()
	end
end

function CombatController:_onGrab(data)
	local character = player.Character
	if not character then
		return
	end
	if data.victim == character then
		if data.phase == "Hold" then
			grabbedUntil = os.clock() + Combat.Grab.Hold + 0.2
			self:_dropCharge()
		else
			grabbedUntil = 0
		end
	end
end

-- Presses -------------------------------------------------------------------------------

local function grabbedNow(): boolean
	return os.clock() < grabbedUntil
end

function CombatController:light()
	local character, humanoid, root = myCharacter()
	if not character or not humanoid or not root then
		return
	end
	-- Caught in a grab: Light breaks it if it's in time (the server decides)
	if grabbedNow() then
		CombatRequest:FireServer(Action.Light, { dir = moveIntent(humanoid) })
		return
	end
	if not canAct(character, humanoid) or charge ~= nil then
		return
	end
	if serverBusy(character, Combat.InputBuffer) then
		return
	end
	local profile = profileOf(character)
	local intent = moveIntent(humanoid)
	local time = os.clock()

	-- Carrying a prop: Light throws it where you aim
	if character:GetAttribute(Attribute.Carrying) ~= nil then
		if time < busyUntil then
			return
		end
		self:_face(root, humanoid)
		local aim = if self.abilities then self.abilities:aim() else nil
		CombatRequest:FireServer(Action.Light, { dir = intent, aim = if typeof(aim) == "table" then aim.direction else nil })
		local throw = profile.Carry.Throw
		busyUntil = time + throw.Startup + throw.Active + throw.Recovery
		self.effects:predictMove(character, "PropThrow", throw, 0)
		return
	end
	if self:_basicOverride(character, root, humanoid, "Light") then
		return
	end
	self:_face(root, humanoid)
	CombatRequest:FireServer(Action.Light, { dir = intent })

	-- Preview the swing (also covers a press buffered near the end of a swing)
	if time < busyUntil - Combat.InputBuffer or time < lightReadyAt then
		return
	end
	local start = math.max(time, busyUntil)
	local move, def
	if inAir(humanoid, root) then
		move, def = "AirKick", profile.Air.Light
	elseif running(character, root, intent) then
		move, def = "RushStrike", profile.Running.Light
	end
	if def then
		chainStep = 0
		chainUntil = 0
	else
		local steps = profile.Light.Steps
		if start > chainUntil or chainStep >= #steps then
			chainStep = 0
		end
		chainStep += 1
		def = steps[chainStep]
		move = def.Move or (if chainStep == #steps then "FinisherKick" else LIGHT_MOVES[chainStep] or "Hook")
		if chainStep == #steps then
			lightReadyAt = start + def.Startup + def.Active + def.Recovery + profile.Light.ChainCooldown
		end
	end
	busyUntil = start + def.Startup + def.Active + def.Recovery
	chainUntil = busyUntil + profile.Light.ChainWindow
	lastSwing = { kind = "Light", activeEnd = start + def.Startup + def.Active, lunge = def.Lunge ~= nil }
	-- Attacking drops the guard; let go of the block pose so it can't cut the swing short
	Poser.release(character, "Block")
	self.effects:predictMove(character, move, def, start - time)
end

-- Heavy pressed: a directional heavy (air, sprint, back) right away, or start charging
function CombatController:heavyPress()
	heavyHeld = true
	local character, humanoid, root = myCharacter()
	if not character or not humanoid or not root or not canAct(character, humanoid) then
		return
	end
	local time = os.clock()
	if time < busyUntil or serverBusy(character) or charge ~= nil then
		return
	end
	if self:_basicOverride(character, root, humanoid, "Heavy") then
		return
	end
	if character:GetAttribute(Attribute.Carrying) ~= nil then
		return
	end
	if serverNow() < attributeTime(character, Attribute.HeavyReadyAt) then
		return
	end
	local profile = profileOf(character)
	local intent = moveIntent(humanoid)
	self:_face(root, humanoid)
	local look = flat(root.CFrame.LookVector)
	local move, def
	if inAir(humanoid, root) then
		move, def = "Slam", profile.Air.Heavy
	elseif running(character, root, intent) then
		move, def = "ShoulderCharge", profile.Running.Heavy
	elseif look.Magnitude > 0.01 and intent:Dot(look.Unit) < -0.5 then
		move, def = "Launcher", profile.Launcher
	end
	chainStep = 0
	Poser.release(character, "Block")
	lastSwing = { kind = "Heavy", activeEnd = 0, lunge = false }
	if def then
		lastHeavyCharged = false
		CombatRequest:FireServer(Action.Heavy, { dir = intent })
		busyUntil = time + def.Startup + def.Active + def.Recovery
		heavyWindupUntil = 0
		self.effects:predictMove(character, move, def, 0)
		return
	end
	local heavy = profile.Heavy
	if winded(character) then
		-- No stamina to charge: a plain heavy
		lastHeavyCharged = false
		CombatRequest:FireServer(Action.Heavy, { dir = intent })
		busyUntil = time + heavy.Startup + heavy.Active + heavy.Recovery
		heavyWindupUntil = time + heavy.Startup
		self.effects:predictMove(character, "Heavy", heavy, 0)
		return
	end
	-- Hold to charge; letting go early is a normal heavy with the same wind-up
	lastHeavyCharged = true
	CombatRequest:FireServer(Action.Heavy, { dir = intent, charge = true })
	local chargeDef = heavy.Charge
	local state = { startedAt = time, profile = profile }
	charge = state
	busyUntil = time + chargeDef.Max + chargeDef.ReleaseStartup + heavy.Active + heavy.Recovery
	heavyWindupUntil = time + chargeDef.Max
	self.effects:predictCharge(character, chargeDef.Max)
	-- A full charge swings by itself (the server does the same)
	task.delay(chargeDef.Max, function()
		if charge == state then
			self:_release(true)
		end
	end)
end

function CombatController:heavyRelease()
	heavyHeld = false
	if charge then
		self:_release(false)
	end
end

-- Kept for older callers: a tap
function CombatController:heavy()
	self:heavyPress()
	self:heavyRelease()
end

function CombatController:_release(automatic: boolean)
	local state = charge
	if not state then
		return
	end
	charge = nil
	if not automatic then
		CombatRequest:FireServer(Action.HeavyRelease)
	end
	local character = player.Character
	if not character then
		return
	end
	local heavy = state.profile.Heavy
	local chargeDef = heavy.Charge
	local time = os.clock()
	local held = time - state.startedAt
	local tapped = held < chargeDef.Min
	local startup = if tapped then math.max(chargeDef.ReleaseStartup, heavy.Startup - held) else chargeDef.ReleaseStartup
	busyUntil = time + startup + heavy.Active + heavy.Recovery
	heavyWindupUntil = time + startup
	self.effects:predictMove(character, if tapped then "Heavy" else "ChargedHeavy", {
		Startup = startup,
		Active = heavy.Active,
		Recovery = heavy.Recovery,
	}, 0, { charge = math.clamp(held / chargeDef.Max, 0, 1) })
end

function CombatController:setBlocking(on: boolean)
	if on == blocking then
		return
	end
	blocking = on
	local character = player.Character
	if on and character then
		-- Block during your own heavy's wind-up or charge: a feint (the server decides)
		local time = os.clock()
		local windingUp = charge ~= nil or time < heavyWindupUntil
		if windingUp and time >= feintReadyAt and not winded(character) then
			charge = nil
			heavyWindupUntil = 0
			feintReadyAt = time + Combat.Feint.Cooldown
			busyUntil = time + Combat.Feint.Recovery
			self.effects:predictFeint(character)
		end
	end
	CombatRequest:FireServer(if on then Action.BlockStart else Action.BlockEnd)
	if on then
		Poser.hold(character, "Block")
	else
		Poser.release(character, "Block")
	end
end

function CombatController:dodge()
	local character, humanoid, root = myCharacter()
	if not character or not humanoid or not root then
		return
	end
	local intent = moveIntent(humanoid)
	-- On the floor Dodge is a tech roll; launched, a breakfall (the server moves you)
	if serverNow() < attributeTime(character, Attribute.DownedUntil) or character:GetAttribute(Attribute.Airborne) == true then
		CombatRequest:FireServer(Action.Dodge, { dir = intent })
		return
	end
	if not canAct(character, humanoid) then
		return
	end
	if winded(character) then
		noteWinded()
		return
	end
	local time = os.clock()
	-- A light that landed can be cancelled into a dodge during its recovery
	local cancelling = time < busyUntil
		and lastSwing.kind == "Light"
		and not lastSwing.lunge
		and time >= lastSwing.activeEnd
		and time - lightLandedAt < 0.6
	if (time < busyUntil or serverBusy(character)) and not cancelling then
		return
	end
	if time < dodgeReadyAt or serverNow() < attributeTime(character, Attribute.DodgeReadyAt) then
		return
	end
	local dodge = profileOf(character).Dodge
	local look = flat(root.CFrame.LookVector)
	local style = dodgeStyle(look, intent)
	local direction
	if style == "Back" then
		direction = if intent.Magnitude >= 0.3 and look.Magnitude > 0.01 and intent.Unit:Dot(look.Unit) < -0.5 then intent.Unit else -look
	else
		direction = intent.Unit
	end
	if direction.Magnitude < 0.1 then
		return
	end
	direction = direction.Unit
	local numbers = dodge.Directions and dodge.Directions[style] or dodge
	local speed = numbers.Speed or dodge.Speed
	local duration = numbers.Duration or dodge.Duration
	dodgeReadyAt = time + dodge.Cooldown
	-- No attacking until the dodge (and its short recovery) is over
	busyUntil = time + duration + dodge.Recovery
	chainStep = 0
	moveDodge(root, direction, speed, duration)

	-- Dodging drops your block; say so explicitly in case the dodge is refused
	if blocking then
		blocking = false
		CombatRequest:FireServer(Action.BlockEnd)
		Poser.release(character, "Block")
	end
	CombatRequest:FireServer(Action.Dodge, { dir = intent })
	self.effects:predictDodge(character, style, direction)
end

-- Grab: grabs a nearby opponent (beats block), or picks up / drops a light prop,
-- or breaks a grab you're caught in
function CombatController:grab()
	local character, humanoid, root = myCharacter()
	if not character or not humanoid or not root then
		return
	end
	local intent = moveIntent(humanoid)
	if grabbedNow() or character:GetAttribute(Attribute.Carrying) ~= nil then
		CombatRequest:FireServer(Action.Grab, { dir = intent })
		return
	end
	if not canAct(character, humanoid) then
		return
	end
	local time = os.clock()
	if time < busyUntil or serverBusy(character) or time < grabReadyAt or charge ~= nil then
		return
	end
	if winded(character) then
		noteWinded()
		return
	end
	local grab = profileOf(character).Grab
	self:_face(root, humanoid)
	-- The guard drops for the grab (a held block comes back up afterwards)
	if character:GetAttribute(Attribute.Blocking) == true or blocking then
		CombatRequest:FireServer(Action.BlockEnd)
		Poser.release(character, "Block")
	end
	CombatRequest:FireServer(Action.Grab, { dir = intent })
	grabReadyAt = time + grab.Cooldown
	busyUntil = time + grab.Startup + grab.Active + grab.WhiffRecovery
	chainStep = 0
	lastSwing = { kind = "Grab", activeEnd = 0, lunge = false }
	self.effects:predictMove(character, "Grab", { Startup = grab.Startup, Active = grab.Active, Recovery = grab.WhiffRecovery }, 0)
end

function CombatController:sweep()
	local character, humanoid, root = myCharacter()
	if not character or not humanoid or not root or not canAct(character, humanoid) then
		return
	end
	local time = os.clock()
	if time < busyUntil or serverBusy(character) or time < sweepReadyAt or charge ~= nil then
		return
	end
	if character:GetAttribute(Attribute.Carrying) ~= nil then
		return
	end
	local sweep = profileOf(character).Sweep
	self:_face(root, humanoid)
	if blocking then
		CombatRequest:FireServer(Action.BlockEnd)
		Poser.release(character, "Block")
	end
	CombatRequest:FireServer(Action.Sweep, { dir = moveIntent(humanoid) })
	sweepReadyAt = time + (sweep.Cooldown or 1)
	busyUntil = time + sweep.Startup + sweep.Active + sweep.Recovery
	chainStep = 0
	lastSwing = { kind = "Sweep", activeEnd = 0, lunge = false }
	self.effects:predictMove(character, "Sweep", sweep, 0)
end

function CombatController:taunt()
	local character, humanoid = myCharacter()
	if not character or not humanoid or not canAct(character, humanoid) then
		return
	end
	local time = os.clock()
	if time < busyUntil or serverBusy(character) or time < tauntReadyAt or blocking or charge ~= nil then
		return
	end
	if character:GetAttribute(Attribute.Carrying) ~= nil then
		return
	end
	local taunt = profileOf(character).Taunt
	CombatRequest:FireServer(Action.Taunt)
	tauntReadyAt = time + taunt.Cooldown
	busyUntil = time + taunt.Duration
	self.effects:predictTaunt(character, taunt.Duration)
end

-- Sprint -------------------------------------------------------------------------------

function CombatController:setSprinting(on: boolean)
	sprintToggle = false
	if on == sprintWanted then
		return
	end
	sprintWanted = on
	self:_sendSprint(on)
end

-- The stick click (and the touch button) toggles; stopping ends a toggled sprint
function CombatController:toggleSprint()
	local on = not sprintWanted
	sprintWanted = on
	sprintToggle = on
	stillSince = os.clock()
	self:_sendSprint(on)
end

function CombatController:_sendSprint(on: boolean)
	local character = player.Character
	if not character then
		return
	end
	if on then
		if not self:_canSprint(character) then
			noteWinded()
			return
		end
		sprintSentAt = os.clock()
		CombatRequest:FireServer(Action.SprintStart)
	else
		CombatRequest:FireServer(Action.SprintEnd)
	end
end

-- State for the HUD and the touch buttons ----------------------------------------------

function CombatController:isSprinting(): boolean
	local character = player.Character
	return sprintWanted or (character ~= nil and character:GetAttribute(Attribute.Sprinting) == true)
end

function CombatController:isBlocking(): boolean
	return blocking
end

-- How full the charge being held is (0..1), and the share where it stops being a
-- tap; nil when not charging
function CombatController:chargeLevel(): (number?, number)
	local chargeDef = Combat.Heavy.Charge
	if not charge then
		return nil, chargeDef.Min / chargeDef.Max
	end
	local profileCharge = charge.profile.Heavy.Charge
	return math.clamp((os.clock() - charge.startedAt) / profileCharge.Max, 0, 1), profileCharge.Min / profileCharge.Max
end

-- Whether a binding's move is ready (cooldowns, stamina), for dimming buttons
function CombatController:isReady(name: string): boolean
	local character = player.Character
	if not character then
		return false
	end
	local time = os.clock()
	if name == "SNHeavy" then
		return serverNow() >= attributeTime(character, Attribute.HeavyReadyAt)
	elseif name == "SNDodge" then
		return not winded(character) and serverNow() >= attributeTime(character, Attribute.DodgeReadyAt) and time >= dodgeReadyAt
	elseif name == "SNGrab" then
		return time >= grabReadyAt and not winded(character)
	elseif name == "SNSweep" then
		return time >= sweepReadyAt
	elseif name == "SNSprint" then
		return self:_canSprint(character)
	end
	return true
end

return CombatController
