-- Client smoke test for Fighting System v2 (controls, animation, feel, camera, HUD):
--   lune run tests/smoke_combat.luau build/e2.rbxl
-- Runs the real client controllers on two jointed R15 rigs. Every CombatEvent
-- kind and field is fired, every binding pressed (keyboard, gamepad chords,
-- touch), every registered sequence played to the end (it must move the joints
-- and leave them back at rest), hitstop and the camera kick are checked, and the
-- HUD and touch cluster are laid out at 1280x720 and 667x375.

local process = require("@lune/process")

local Client = require("./smoke/Client")

local t = Client.load(process.args[1] or "build/e2.rbxl")
local Engine, world, roblox = t.Engine, t.world, t.roblox
local game = t.game
local Instance, Vector3, Vector2, CFrame, Enum = world.Instance, roblox.Vector3, roblox.Vector2, roblox.CFrame, roblox.Enum

local workspace = world.workspace
-- Properties the stand-in engine has no defaults for
local UserInputService = game:GetService("UserInputService")
UserInputService.TouchEnabled = false
UserInputService.KeyboardEnabled = true
local CollectionService = world.services.CollectionService
local Lighting = game:GetService("Lighting")

local function step(frames: number, dt: number?)
	Engine.step(game, frames, dt or 1 / 30)
end

-- A jointed R15 rig (the joints Poser drives, with Roblox's usual C0s)
local function rig(name: string, position)
	local model = Instance.new("Model")
	model.Name = name
	local parts = {}
	local function part(partName: string, size, offset)
		local item = Instance.new("Part")
		item.Name = partName
		item.Size = size
		item.CFrame = CFrame.new(position + offset)
		item.Parent = model
		parts[partName] = item
		return item
	end
	part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.zero)
	part("LowerTorso", Vector3.new(2, 0.4, 1), Vector3.new(0, -0.8, 0))
	part("UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 0.2, 0))
	part("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.6, 0))
	for _, side in { "Right", "Left" } do
		local x = if side == "Right" then 1.5 else -1.5
		part(side .. "UpperArm", Vector3.new(1, 1.2, 1), Vector3.new(x, 0.4, 0))
		part(side .. "LowerArm", Vector3.new(1, 1.1, 1), Vector3.new(x, -0.6, 0))
		part(side .. "Hand", Vector3.new(1, 0.3, 1), Vector3.new(x, -1.2, 0))
		part(side .. "UpperLeg", Vector3.new(1, 1.2, 1), Vector3.new(x / 3, -1.6, 0))
		part(side .. "LowerLeg", Vector3.new(1, 1.1, 1), Vector3.new(x / 3, -2.6, 0))
	end
	local function motor(child: string, motorName: string, parent: string, c0)
		local joint = Instance.new("Motor6D")
		joint.Name = motorName
		joint.Part0 = parts[parent]
		joint.Part1 = parts[child]
		joint.C0 = c0
		joint.Parent = parts[child]
	end
	motor("LowerTorso", "Root", "HumanoidRootPart", CFrame.new(0, -1, 0))
	motor("UpperTorso", "Waist", "LowerTorso", CFrame.new(0, 0.2, 0))
	motor("Head", "Neck", "UpperTorso", CFrame.new(0, 0.8, 0))
	for _, side in { "Right", "Left" } do
		local x = if side == "Right" then 1 else -1
		motor(side .. "UpperArm", side .. "Shoulder", "UpperTorso", CFrame.new(x, 0.56, 0))
		motor(side .. "LowerArm", side .. "Elbow", side .. "UpperArm", CFrame.new(0, -0.33, 0))
		motor(side .. "UpperLeg", side .. "Hip", "LowerTorso", CFrame.new(x * 0.5, -0.2, 0))
		motor(side .. "LowerLeg", side .. "Knee", side .. "UpperLeg", CFrame.new(0, -0.4, 0))
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2
	humanoid.Parent = model
	model.PrimaryPart = parts.HumanoidRootPart
	model:SetAttribute("DisplayName", name)
	model.Parent = workspace
	-- The stand-in engine keeps Position apart from CFrame
	Engine.syncPositions(model)
	CollectionService:AddTag(model, "SNFighter")
	return model, humanoid
end

local function motors(model)
	local list = {}
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") then
			table.insert(list, item)
		end
	end
	return list
end

-- Every joint back at its saved rest C0
local function atRest(model): (boolean, string?)
	for _, joint in motors(model) do
		local rest = joint:GetAttribute("SNBaseC0")
		if typeof(rest) == "CFrame" then
			local c0 = joint.C0
			if (c0.Position - rest.Position).Magnitude > 1e-3 or c0.LookVector:Dot(rest.LookVector) < 0.9999 or c0.UpVector:Dot(rest.UpVector) < 0.9999 then
				return false, joint.Name
			end
		end
	end
	return true, nil
end

local function moved(model): boolean
	for _, joint in motors(model) do
		local rest = joint:GetAttribute("SNBaseC0")
		if typeof(rest) == "CFrame" and ((joint.C0.Position - rest.Position).Magnitude > 1e-3 or joint.C0.LookVector:Dot(rest.LookVector) < 0.999) then
			return true
		end
	end
	return false
end

local me, myHumanoid = rig("Me", Vector3.new(0, 3, 0))
local foe = rig("Foe", Vector3.new(0, 3, -8))
world.localPlayer.Character = me
table.insert(Engine.players, world.localPlayer)

-- The real controllers (stand-ins only for the ability and power-effect controllers)
local controllers = {
	AbilityController = {
		aim = function()
			return { direction = Vector3.new(0, 0, -1) }
		end,
	},
	PowerFxController = { predict = function() end },
}
for _, name in { "CameraController", "EffectsController", "CombatController", "InputController" } do
	controllers[name] = t.client("Controllers." .. name)
end
for _, name in { "CameraController", "EffectsController", "CombatController", "InputController" } do
	local controller = controllers[name]
	if controller.Init then
		controller:Init(controllers)
	end
end
for _, name in { "CameraController", "EffectsController", "CombatController", "InputController" } do
	t.task.spawn(controllers[name].Start, controllers[name])
end
t.task.wait(0.1)

local Poser = t.client("Effects.Poser")
local Settings = t.client("Settings")
local Input = controllers.InputController
local Combat = controllers.CombatController
local Camera = controllers.CameraController
local Effects = controllers.EffectsController
local combatEvent = world.find("ReplicatedStorage.Remotes.CombatEvent")
local function fire(kind: string, data)
	Engine.signalOf(combatEvent, "OnClientEvent"):Fire(kind, data)
end
-- A fresh life: the controllers forget their previews and cooldowns
local function respawn()
	Engine.signalOf(world.localPlayer, "CharacterAdded"):Fire(me)
	Poser.stop(me)
	step(2)
end

local KEY = { UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Unknown, Position = Vector3.zero }
local MOUSE = { UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown, Position = Vector3.zero }
local function pad(code)
	return { UserInputType = Enum.UserInputType.Gamepad1, KeyCode = code, Position = Vector3.zero }
end
local function press(name: string, input, hold: boolean?)
	local handler = Input.handlers[name]
	assert(handler, "binding " .. name)
	handler(name, Enum.UserInputState.Begin, input or KEY)
	if not hold then
		handler(name, Enum.UserInputState.End, input or KEY)
	end
end
local function release(name: string, input)
	Input.handlers[name](name, Enum.UserInputState.End, input or KEY)
end
local function sent(start: number, action: string)
	return t.sentSince(start, "CombatRequest", action)
end
local function assertDir(entry, label: string)
	local payload = entry.args[2]
	assert(typeof(payload) == "table" and typeof(payload.dir) == "Vector3", label .. " sends { dir = Vector3 }")
	assert(payload.dir.Y == 0 and payload.dir.Magnitude <= 1.0001, label .. " dir is flat and at most 1 long")
end

t.check("the project disables Roblox's shift lock (Shift sprints)", function()
	assert(game:GetService("StarterPlayer").EnableMouseLockOption == false, "EnableMouseLockOption = false")
end)

t.check("every registered sequence moves the body and ends cleanly at rest", function()
	local names = {}
	for name in Poser.Sequences do
		if not string.find(name, "@", 1, true) then
			table.insert(names, name)
		end
	end
	table.sort(names)
	assert(#names >= 45, "the move library: " .. #names .. " sequences")
	for _, name in names do
		for _, mirror in { false, true } do
			Poser.stop(me)
			step(1)
			t.task.wait(0.02)
			local length = Poser.sequence(me, name, 1, { mirror = mirror })
			assert(length > 0, name .. " has a length")
			local sawMovement = false
			for _ = 1, 120 do
				step(1)
				sawMovement = sawMovement or moved(me)
				if Poser.Sequences[name].info.holdAt then
					Poser.advance(me)
				end
				if Poser.playing(me) == nil then
					break
				end
			end
			assert(sawMovement, name .. " moves a joint")
			assert(Poser.playing(me) == nil, name .. " finishes")
			t.task.wait(0.03) -- moves that end posed ease home with a short tween
			local rest, joint = atRest(me)
			assert(rest, name .. (if mirror then " (mirrored)" else "") .. " leaves " .. tostring(joint) .. " off its rest pose")
		end
	end
end)

t.check("sequences stretch to the server's timing: a slow jab lands on its contact frame", function()
	Poser.stop(me)
	step(1)
	Poser.sequence(me, "Jab", 1, { timing = { startup = 0.3, active = 0.1, recovery = 0.2 } })
	for _ = 1, 6 do
		step(1, 0.05)
	end
	local shoulder = me.LeftUpperArm.LeftShoulder
	local rest = shoulder:GetAttribute("SNBaseC0")
	local expected = CFrame.Angles(math.rad(90), 0, math.rad(8)) * rest.Rotation
	assert(shoulder.C0.LookVector:Dot(expected.LookVector) > 0.995, "lead arm fully extended exactly at the end of startup")
	-- Hitstop: frozen, the pose doesn't advance
	local before = shoulder.C0
	Poser.freeze(me, 0.2)
	step(3, 0.05)
	assert(shoulder.C0 == before, "frozen during hitstop")
	t.task.wait(0.22)
	step(3, 0.05)
	assert(shoulder.C0 ~= before, "carries on after the hitstop")
	Poser.stop(me)
	step(1)
	-- Older pose API powers use still works next to sequences
	Poser.register("SmokeTestPose", { RightShoulder = { 45, 0, 0 } })
	Poser.play(me, "SmokeTestPose", 0.05, 0.05, 0.05)
	Poser.hold(me, "Block")
	assert(Poser.isHolding(me, "Block"), "hold")
	Poser.release(me, "Block")
	t.task.wait(0.1)
end)

t.check("keyboard and mouse: every binding sends the right request with a dir", function()
	respawn()
	myHumanoid.MoveDirection = Vector3.new(0, 0, -1)
	local mark = #Engine.sent
	press("SNLight", MOUSE)
	local lights = sent(mark, "Light")
	assert(#lights == 1, "Light")
	assertDir(lights[1], "Light")
	assert(Poser.playing(me) == "Jab", "the jab is previewed instantly: " .. tostring(Poser.playing(me)))

	respawn()
	mark = #Engine.sent
	press("SNHeavy", KEY, true)
	local heavies = sent(mark, "Heavy")
	assert(#heavies == 1 and heavies[1].args[2].charge == true, "holding Heavy starts a charge")
	assertDir(heavies[1], "Heavy")
	assert(Poser.playing(me) == "ChargeHold", "charge wind-up previewed")
	assert(Combat:chargeLevel() ~= nil, "charging")
	t.task.wait(0.35)
	release("SNHeavy")
	assert(#sent(mark, "HeavyRelease") == 1, "letting go sends HeavyRelease")
	assert(Poser.playing(me) == "ChargedStrike", "the release swings from the coil")
	assert(Combat:chargeLevel() == nil, "no longer charging")

	-- Back + Heavy: the Launcher (a tap, no charge)
	respawn()
	myHumanoid.MoveDirection = Vector3.new(0, 0, 1)
	mark = #Engine.sent
	press("SNHeavy")
	heavies = sent(mark, "Heavy")
	assert(#heavies == 1 and heavies[1].args[2].charge == nil, "back + Heavy is a tap")
	assert(Poser.playing(me) == "Launcher", "Launcher previewed")
	assert(#sent(mark, "HeavyRelease") == 0, "no release for a tap")

	-- Feint: Block during your own heavy's wind-up
	respawn()
	myHumanoid.MoveDirection = Vector3.new(0, 0, -1)
	mark = #Engine.sent
	press("SNHeavy", KEY, true)
	press("SNBlock", KEY, true)
	assert(#sent(mark, "BlockStart") == 1, "the feint is a BlockStart (the server decides)")
	assert(Poser.playing(me) == "Feint", "feint previewed")
	release("SNHeavy")
	release("SNBlock")
	assert(#sent(mark, "BlockEnd") == 1, "BlockEnd")
	assert(#sent(mark, "HeavyRelease") == 0, "a feinted charge isn't released")

	for _, case in { { "SNDodge", "Dodge" }, { "SNGrab", "Grab" }, { "SNSweep", "Sweep" } } do
		respawn()
		mark = #Engine.sent
		press(case[1])
		local entries = sent(mark, case[2])
		assert(#entries == 1, case[2])
		assertDir(entries[1], case[2])
	end
	-- The dodge moves this client's own character, in the move direction
	local mover = me.HumanoidRootPart:FindFirstChild("SNDodge", false)
	local found = false
	for _, child in me.HumanoidRootPart:GetChildren() do
		found = found or (child:IsA("LinearVelocity") and child.Name == "SNDodge")
	end
	local _ = mover

	respawn()
	mark = #Engine.sent
	press("SNSprint", KEY, true)
	assert(#sent(mark, "SprintStart") == 1, "Shift held: SprintStart")
	release("SNSprint")
	assert(#sent(mark, "SprintEnd") == 1, "Shift released: SprintEnd")

	respawn()
	mark = #Engine.sent
	press("SNTaunt")
	assert(#sent(mark, "Taunt") == 1, "Taunt")
	local taunt = Poser.playing(me)
	assert(taunt == "TauntBeckon" or taunt == "TauntShrug" or taunt == "TauntFlex", "a taunt plays: " .. tostring(taunt))
end)

t.check("gamepad: chords on L1, L3 toggles sprint, Y holds a charge", function()
	respawn()
	myHumanoid.MoveDirection = Vector3.new(0, 0, -1)
	local mark = #Engine.sent
	press("SNBlock", pad(Enum.KeyCode.ButtonL1), true)
	press("SNLight", pad(Enum.KeyCode.ButtonX))
	assert(#sent(mark, "Grab") == 1 and #sent(mark, "Light") == 0, "L1+X grabs")
	respawn()
	press("SNHeavy", pad(Enum.KeyCode.ButtonY), true)
	release("SNHeavy", pad(Enum.KeyCode.ButtonY))
	assert(#sent(mark, "Sweep") == 1 and #sent(mark, "Heavy") == 0, "L1+Y sweeps")
	assert(#sent(mark, "HeavyRelease") == 0, "a sweep is not a charge")
	release("SNBlock", pad(Enum.KeyCode.ButtonL1))

	respawn()
	mark = #Engine.sent
	press("SNHeavy", pad(Enum.KeyCode.ButtonY), true)
	assert(#sent(mark, "Heavy") == 1 and sent(mark, "Heavy")[1].args[2].charge == true, "Y held charges")
	release("SNHeavy", pad(Enum.KeyCode.ButtonY))
	assert(#sent(mark, "HeavyRelease") == 1, "Y released")

	respawn()
	mark = #Engine.sent
	press("SNSprint", pad(Enum.KeyCode.ButtonL3))
	assert(#sent(mark, "SprintStart") == 1 and Combat:isSprinting(), "L3 toggles sprint on")
	press("SNSprint", pad(Enum.KeyCode.ButtonL3))
	assert(#sent(mark, "SprintEnd") == 1, "and off")
	press("SNTaunt", pad(Enum.KeyCode.ButtonSelect))
	assert(#sent(mark, "Taunt") == 1, "View taunts")
end)

t.check("lock-on: Z locks the enemy in view, tap again lets go, hold mode, pauses for cinematics", function()
	respawn()
	press("SNLock", KEY)
	assert(Camera:isLocked() and Camera:getLockTarget() == foe, "locked onto the enemy")
	step(10)
	local look = workspace.CurrentCamera.CFrame.LookVector
	local toward = (foe.HumanoidRootPart.Position - workspace.CurrentCamera.CFrame.Position).Unit
	assert(look:Dot(toward) > 0.8, "the camera frames the target")
	assert(Camera:lockDirection() ~= nil, "the character faces the target")
	-- A second enemy: a tap switches to it
	local other = rig("Other", Vector3.new(6, 3, -10))
	press("SNLock", KEY)
	assert(Camera:getLockTarget() == other, "tap switches when another enemy is near")
	-- Leaves the game (the stand-in engine can't touch destroyed instances, so unparent)
	other.Parent = nil
	Engine.signalOf(other, "AncestryChanged"):Fire(other, nil)
	step(2)
	assert(Camera:getLockTarget() == foe or not Camera:isLocked(), "a target that leaves is let go")
	if Camera:isLocked() then
		press("SNLock", KEY)
	end
	assert(not Camera:isLocked(), "tap with nobody else near lets go")
	-- Cinematics own the camera
	press("SNLock", KEY)
	assert(Camera:isLocked(), "locked again")
	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	local before = workspace.CurrentCamera.CFrame
	step(5)
	assert(workspace.CurrentCamera.CFrame == before, "lock-on leaves a Scriptable camera alone")
	assert(Camera:getLockTarget() == nil, "and the reticle hides")
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	Camera:unlock()
	-- Hold mode
	Settings.set("lockOnMode", "hold")
	press("SNLock", KEY, true)
	assert(Camera:isLocked(), "hold mode: locked while held")
	release("SNLock")
	assert(not Camera:isLocked(), "hold mode: let go")
	Settings.set("lockOnMode", "toggle")
end)

t.check("every CombatEvent kind and field is handled, for the local player and others", function()
	respawn()
	-- The local player's own previews are fresh for 0.6 s (their echo is skipped)
	t.task.wait(0.7)
	local camera = workspace.CurrentCamera
	local moves = { "Jab", "Cross", "Hook", "FinisherKick", "Heavy", "ChargedHeavy", "Launcher", "RushStrike", "ShoulderCharge", "AirKick", "Slam", "Sweep", "Grab", "PropThrow" }
	for index, move in moves do
		local kind = if move == "Sweep" or move == "Grab" then move elseif table.find({ "Heavy", "ChargedHeavy", "Launcher", "ShoulderCharge", "Slam" }, move) then "Heavy" else "Light"
		for _, attacker in { foe, me } do
			fire("Attack", { attacker = attacker, kind = kind, step = math.min(index, 4), startup = 0.12, active = 0.1, recovery = 0.2, move = move, charge = if move == "ChargedHeavy" then 0.6 else nil })
			step(2)
			assert(Poser.playing(attacker) ~= nil, move .. " plays on " .. attacker.Name)
		end
	end
	-- An old-style Attack with no move still animates
	fire("Attack", { attacker = foe, kind = "Light", step = 2, startup = 0.1, active = 0.1 })
	assert(Poser.playing(foe) == "Cross", "step 2 without a move is a cross")
	-- A heavy released out of a charge swings from the coil
	fire("Motion", { fighter = foe, motion = "Charge", duration = 1.2 })
	assert(Poser.playing(foe) == "ChargeHold", "the charge wind-up")
	assert(foe.RightHand:FindFirstChild("SNChargeGlow"), "a visible charge glow at the fist")
	fire("Attack", { attacker = foe, kind = "Heavy", step = 1, startup = 0.18, active = 0.14, recovery = 0.4, move = "ChargedHeavy", charge = 1 })
	assert(Poser.playing(foe) == "ChargedStrike", "release swings from the coil")
	assert(foe.RightHand:FindFirstChild("SNChargeGlow") == nil, "the glow goes with the swing")

	-- Hits: every result, every tag, both directions
	local function hit(victim, attacker, result, tags, extra)
		local data = {
			attacker = attacker,
			victim = victim,
			result = result,
			damage = 9,
			position = victim.HumanoidRootPart.Position,
			heavy = false,
			finisher = false,
			comboCapped = false,
			move = "Cross",
			kind = "Light",
			tags = tags or {},
			direction = Vector3.new(0, 0, 1),
		}
		for key, value in extra or {} do
			data[key] = value
		end
		fire("Hit", data)
	end
	local function calloutShown(text: string): boolean
		for _, item in camera:GetDescendants() do
			if item:IsA("TextLabel") and item.Text == text then
				return true
			end
		end
		return false
	end
	for _, result in { "Hit", "Blocked", "GuardBreak", "Parried", "Invulnerable", "Clash", "Perfect", "PerfectBlock", "Good", "Endured", "Countered" } do
		hit(foe, me, result)
		hit(me, foe, result, nil, { direction = Vector3.new(1, 0, 0) })
	end
	assert(calloutShown("PARRY") and calloutShown("GUARD BREAK"), "PARRY and GUARD BREAK callouts")
	for _, tag in { "counter", "punish", "riposte", "wallSplat", "knockdown", "launch", "airborne", "otg" } do
		hit(foe, me, "Hit", { [tag] = true }, { move = "Heavy", heavy = true, finisher = true })
	end
	assert(calloutShown("COUNTER") and calloutShown("PUNISH") and calloutShown("WALL SPLAT"), "COUNTER, PUNISH and WALL SPLAT callouts")
	for _, item in camera:GetDescendants() do
		if item:IsA("TextLabel") and item.Text ~= "" then
			assert(not string.find(item.Text, "!", 1, true), "no exclamation marks in callouts: " .. item.Text)
		end
	end
	-- Directional flinches
	for _, direction in { Vector3.new(0, 0, 1), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0) } do
		hit(foe, me, "Hit", {}, { direction = direction })
		local playing = Poser.playing(foe)
		assert(playing == "FlinchFront" or playing == "FlinchBack" or playing == "FlinchSide" or playing == "FlinchSide@mirror", "a directional flinch: " .. tostring(playing))
	end

	-- Hitstop and the camera kick on a heavy the local player lands
	Poser.sequence(foe, "Heavy")
	hit(foe, me, "Hit", { counter = true }, { move = "Heavy", heavy = true })
	local victimArm = foe.RightUpperArm.RightShoulder.C0
	step(1)
	assert(foe.RightUpperArm.RightShoulder.C0 == victimArm, "hitstop holds the victim's pose")
	local before = camera.CFrame
	step(2)
	assert(camera.CFrame ~= before, "the camera kicks")
	Settings.set("cameraShake", false)
	t.task.wait(0.3)
	step(30)
	before = camera.CFrame
	hit(foe, me, "Hit", {}, { move = "Heavy", heavy = true })
	step(2)
	assert(camera.CFrame == before, "no kick with Screen Shake off")
	Settings.set("cameraShake", true)

	-- Dodges, clash, grabs
	for _, style in { "Side", "Back", "Forward" } do
		for _, fighter in { foe, me } do
			fire("Dodge", { fighter = fighter, direction = Vector3.new(1, 0, 0), style = style, speed = 62, duration = 0.18, invulnerable = 0.22 })
		end
	end
	fire("Clash", { a = me, b = foe, position = Vector3.new(0, 3, -4) })
	assert(Poser.playing(me) == "ClashRecoil" and Poser.playing(foe) == "ClashRecoil", "both recoil from a clash")
	assert(calloutShown("CLASH"), "CLASH callout")
	fire("Grab", { attacker = foe, victim = me, phase = "Hold", direction = Vector3.new(0, 0, 1) })
	assert(Poser.playing(foe) == "ClinchHold" and Poser.playing(me) == "Clinched", "the clinch for both")
	local mark = #Engine.sent
	press("SNGrab")
	assert(#sent(mark, "Grab") == 1, "Grab while held is sent as a tech")
	fire("Grab", { attacker = foe, victim = me, phase = "Tech" })
	assert(Poser.playing(foe) == "TechBreak" and calloutShown("TECH"), "TECH breaks both apart")
	fire("Grab", { attacker = me, victim = foe, phase = "Hold", direction = Vector3.new(0, 0, 1) })
	fire("Grab", { attacker = me, victim = foe, phase = "Throw", direction = Vector3.new(0, 0, 1) })
	assert(Poser.playing(me) == "ThrowBack" or Poser.playing(me) == "ThrowForward", "the throw")
	assert(Poser.playing(foe) == "Thrown", "being thrown")
	fire("Grab", { attacker = foe, phase = "Whiff" })
	fire("Grab", { attacker = foe, victim = me, phase = "Hold", direction = Vector3.new(0, 0, -1) })
	fire("Grab", { attacker = foe, victim = me, phase = "Whiff" })

	-- Motions
	for _, motion in { "Charge", "Feint", "Knockdown", "GetUp", "TechRoll", "Breakfall", "Taunt", "TauntDone", "Winded", "Recovered", "PickUp", "Drop", "DodgeCancel", "SprintStart", "SprintEnd" } do
		for _, fighter in { foe, me } do
			fire("Motion", { fighter = fighter, motion = motion, direction = Vector3.new(0, 0, 1), duration = 0.4, prop = "Crate" })
			step(1)
		end
	end
	-- Knockdown: fall, lie still until GetUp, then get up and end at rest
	Poser.stop(foe)
	fire("Motion", { fighter = foe, motion = "Knockdown", direction = Vector3.new(0, 0, 1), duration = 3 })
	assert(Poser.playing(foe) == "KnockdownBack", "knocked onto the back")
	step(40)
	assert(Poser.playing(foe) == "KnockdownBack", "lies down until the get-up")
	fire("Motion", { fighter = foe, motion = "GetUp", duration = 0.4 })
	step(40)
	assert(Poser.playing(foe) == nil and atRest(foe), "gets up and ends at rest")
	fire("Motion", { fighter = foe, motion = "Knockdown", direction = Vector3.new(0, 0, -1), duration = 1 })
	assert(Poser.playing(foe) == "KnockdownFront", "knocked onto the face")
	fire("Motion", { fighter = foe, motion = "TechRoll", direction = Vector3.new(0, 0, 1), duration = 0.25 })
	assert(Poser.playing(foe) == "TechRollForward", "tech roll from the front")

	-- Perfect dodge: slow-motion tint only on the dodger's own screen
	local tint = Lighting:FindFirstChild("SNPerfectDodge")
	if tint then
		tint:Destroy()
	end
	fire("Motion", { fighter = foe, motion = "PerfectDodge", attacker = me, duration = 0.5 })
	assert(Lighting:FindFirstChild("SNPerfectDodge") == nil, "someone else's perfect dodge doesn't tint my screen")
	fire("Motion", { fighter = me, motion = "PerfectDodge", attacker = foe, duration = 0.5 })
	assert(Lighting:FindFirstChild("SNPerfectDodge"), "my perfect dodge tints my screen")

	-- Rejections undo the previews
	for _, action in { "Light", "Heavy", "Dodge", "Grab", "Sweep", "Taunt", "SprintStart", "Feint" } do
		for _, reason in { "winded", "cooldown", "busy", "stunned", "downed", "grabbed", "carrying", "too late", "too early", "not charging", "nothing to feint" } do
			fire("Rejected", { action = action, reason = reason })
		end
	end
	-- Junk is ignored
	fire("Hit", { attacker = "junk", victim = 5, result = "Hit" })
	fire("Attack", { attacker = 7 })
	fire("Motion", { fighter = me, motion = "NoSuchMotion" })
	fire("Grab", { attacker = me, victim = "x", phase = "Throw" })
	fire("Clash", { a = 1, b = nil, position = "x" })
	fire("Dodge", { fighter = me, direction = "x" })
	fire("Motion", "not a table")
	step(30)
	t.task.wait(1.4)
	step(60)
end)

t.check("carrying a prop: the carry pose follows the attribute and Light throws", function()
	respawn()
	Poser.stop(me)
	step(1)
	me:SetAttribute("SNCarrying", "Crate")
	Engine.signalOf(me, "Attribute:SNCarrying"):Fire()
	assert(Poser.isHolding(me, "Carry"), "carry pose held")
	local mark = #Engine.sent
	press("SNLight", MOUSE)
	local throws = sent(mark, "Light")
	assert(#throws == 1 and typeof(throws[1].args[2].aim) == "Vector3", "Light while carrying sends the aim")
	assert(Poser.playing(me) == "PropThrow", "the throw plays")
	me:SetAttribute("SNCarrying", nil)
	Engine.signalOf(me, "Attribute:SNCarrying"):Fire()
	assert(not Poser.isHolding(me, "Carry"), "released")
end)

-- Interface ---------------------------------------------------------------------------------

local function rectOf(button, width: number, height: number)
	local size = button.Size.X.Offset
	local x = button.Position.X.Scale * width + button.Position.X.Offset
	local y = button.Position.Y.Scale * height + button.Position.Y.Offset
	return { x = x, y = y, r = size / 2, size = size }
end

t.check("HUD: stamina under health, charge meter, lock reticle and hint strip fit at both sizes", function()
	local ui = t.startUI({
		currencies = { money = 12000, gems = 60 },
		selected = { power = "StrongDude", degree = 1 },
		settings = { cameraShake = true, uiScale = 1 },
	})
	local gui = ui.gui
	me:SetAttribute("SNStamina", 20)
	me:SetAttribute("SNStaminaMax", 100)
	for _, size in { { 1280, 720 }, { 667, 375 } } do
		for _, kind in { "keyboard", "gamepad", "touch" } do
			ui.device(kind)
			t.setScreen(size[1], size[2])
			step(4)
			t.task.wait(0.06)
			step(2)
			local hud = t.findNamed(gui, "Hud")
			assert(hud and hud.Visible, "the HUD shows")
			assert(t.findNamed(hud, "Stamina") and t.findNamed(hud, "Guard"), "guard and stamina meters")
			t.auditLayout(hud, `HUD {kind} {size[1]}x{size[2]}`)
			local actions = t.findNamed(hud, "Actions")
			assert(actions.Visible == (kind ~= "touch"), "hint strip only off touch")
			if kind == "gamepad" then
				assert(t.findText(actions, "L1+X") and t.findText(actions, "R3"), "gamepad hints")
			elseif kind == "keyboard" then
				assert(t.findText(actions, "Shift") and t.findText(actions, "M1"), "keyboard hints")
			end
		end
	end
	-- Low and winded stamina read clearly
	me:SetAttribute("SNWinded", true)
	step(4)
	t.task.wait(0.06)
	step(2)
	assert(t.findText(gui, "WINDED"), "WINDED replaces the stamina caption")
	me:SetAttribute("SNWinded", nil)
	-- Charge meter while charging
	respawn()
	press("SNHeavy", KEY, true)
	step(4)
	t.task.wait(0.06)
	step(2)
	local meter = t.findNamed(gui, "ChargeMeter")
	assert(meter and meter.Visible, "charge meter shows while charging")
	t.auditLayout(meter, "charge meter")
	release("SNHeavy")
	step(4)
	t.task.wait(0.06)
	step(2)
	assert(not meter.Visible, "and hides after")
	-- Lock reticle over the target
	press("SNLock", KEY)
	step(4)
	t.task.wait(0.06)
	step(2)
	local reticle = world.localPlayer.PlayerGui:FindFirstChild("SNLockReticle", true)
	assert(reticle and reticle.Enabled and reticle.Adornee == foe.HumanoidRootPart, "reticle over the lock target")
	Camera:unlock()
	step(4)
	t.task.wait(0.06)
	step(2)
	assert(not reticle.Enabled, "reticle hides")
end)

t.check("touch: a tidy right-side cluster, 44 px or more, clear of the jump button and the HUD", function()
	local ui = t.startUI()
	Engine.lastInputType = Enum.UserInputType.Touch
	local Shell = t.client("UI.Shell")
	local Hud = t.client("UI.Hud")
	local touch = world.localPlayer.PlayerGui:FindFirstChild("SNTouchControls")
	assert(touch, "touch controls built")
	for _, size in { { 1280, 720 }, { 667, 375 } } do
		local width, height = size[1], size[2]
		ui.device("touch")
		t.setScreen(width, height)
		step(8)
		t.task.wait(0.12)
		step(8)
		assert(touch.Enabled, `touch controls show on touch at {width}x{height}`)
		t.auditLayout(touch, `touch controls {width}x{height}`)
		local jump, scale = Input.touchFrame(Vector2.new(width, height))
		local jumpRect = { x = width + jump.X, y = height + jump.Y, r = 35 * scale }
		local scaleUi = Shell.scale()
		local layout = Hud.Layout
		local hudLeft = width / 2 + (layout.touchShift - layout.width / 2) * scaleUi
		local hudRight = width / 2 + (layout.touchShift + layout.width / 2) * scaleUi
		local hudTop = height - (layout.bottom + layout.touchHeight) * scaleUi
		local buttons = {}
		for _, button in touch:GetChildren() do
			if button:IsA("TextButton") then
				local rect = rectOf(button, width, height)
				assert(rect.size >= 44, button.Name .. " is at least 44 px")
				assert(rect.x - rect.r >= 4 and rect.x + rect.r <= width - 4 and rect.y - rect.r >= 4 and rect.y + rect.r <= height - 4, button.Name .. " is on screen")
				local gap = (Vector2.new(rect.x, rect.y) - Vector2.new(jumpRect.x, jumpRect.y)).Magnitude - rect.r - jumpRect.r
				assert(gap >= 6, button.Name .. " clears the jump button by " .. gap)
				local overHud = rect.x + rect.r > hudLeft and rect.x - rect.r < hudRight and rect.y + rect.r > hudTop
				assert(not overHud, button.Name .. " stays off the HUD and ability bar")
				table.insert(buttons, { name = button.Name, rect = rect })
			end
		end
		assert(#buttons == 8, "eight touch buttons: " .. #buttons)
		for i = 1, #buttons do
			for j = i + 1, #buttons do
				local a, b = buttons[i].rect, buttons[j].rect
				local gap = (Vector2.new(a.x, a.y) - Vector2.new(b.x, b.y)).Magnitude - a.r - b.r
				assert(gap >= 6, `{buttons[i].name} and {buttons[j].name} overlap (gap {gap})`)
			end
		end
	end
	-- Every touch button sends its action
	respawn()
	myHumanoid.MoveDirection = Vector3.new(0, 0, -1)
	local expected = { TouchLight = "Light", TouchHeavy = "Heavy", TouchBlock = "BlockStart", TouchDodge = "Dodge", TouchGrab = "Grab", TouchSweep = "Sweep", TouchSprint = "SprintStart" }
	for name, action in expected do
		respawn()
		local button = touch:FindFirstChild(name)
		local finger = { UserInputType = Enum.UserInputType.Touch, KeyCode = Enum.KeyCode.Unknown, Position = Vector3.zero }
		local mark = #Engine.sent
		Engine.signalOf(button, "InputBegan"):Fire(finger)
		Engine.signalOf(button, "InputEnded"):Fire(finger)
		assert(#sent(mark, action) >= 1, name .. " sends " .. action)
	end
	local finger = { UserInputType = Enum.UserInputType.Touch, KeyCode = Enum.KeyCode.Unknown, Position = Vector3.zero }
	Engine.signalOf(touch:FindFirstChild("TouchLock"), "InputBegan"):Fire(finger)
	Engine.signalOf(touch:FindFirstChild("TouchLock"), "InputEnded"):Fire(finger)
	assert(Camera:isLocked(), "the Lock button locks on")
	Camera:unlock()
	-- Hidden in the editor and in cinematics
	Shell.setMode("Cinematic")
	step(8)
	t.task.wait(0.12)
	step(8)
	assert(not touch.Enabled, "hidden in Cinematic mode")
	Shell.setMode("Lobby")
	t.setScreen(1280, 720)
end)

t.check("settings: lock-on mode switches between toggle and hold", function()
	local ui = t.startUI()
	local Shell = ui.Shell
	ui.device("keyboard")
	assert(Settings.get("lockOnMode") == "toggle", "toggle by default")
	Shell.open("Settings")
	local row = t.findNamed(ui.gui, "Toggle_lockOnMode")
	assert(row, "the lock-on row")
	t.press(row)
	assert(Settings.get("lockOnMode") == "hold", "switched to hold")
	t.press(row)
	assert(Settings.get("lockOnMode") == "toggle", "back to toggle")
	for _, size in { { 1280, 720 }, { 667, 375 } } do
		t.setScreen(size[1], size[2])
		t.auditLayout(t.findNamed(ui.gui, "Window_Settings") or ui.gui, `Settings {size[1]}x{size[2]}`)
	end
	Shell.close()
	t.setScreen(1280, 720)
end)

t.finish()
