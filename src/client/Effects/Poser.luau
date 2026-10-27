-- Procedural animation: poses a character by rotating its joints (Motor6D.C0).
-- It works on R15 and R6 rigs and layers on top of Roblox's normal walk and
-- idle animations (those drive Motor6D.Transform, this drives C0). Each client
-- poses every character locally from combat events, so everyone sees the same
-- moves.
--
-- Two ways to animate:
--   Poses (play/hold/release): one pose tweened in and out. Powers use these.
--   Sequences (registerSequence/sequence): keyframed moves with anticipation,
--   overshoot and follow-through, timed to the server's Startup/Active/Recovery.
--   A per-frame driver blends them, so a new move always starts from wherever
--   the body is, hitstop can pause them, and they end cleanly at rest (or back
--   in a held pose such as Block).
--
-- Angles are { pitch, yaw, roll } in degrees in the parent part's space, with an
-- optional { x, y, z } offset in studs after them (used on Root to lower the hips).
-- Pitch raises an arm or leg forward (and leans the torso back); yaw twists (positive
-- turns left); roll swings sideways (positive takes a right limb outward and a left
-- limb inward, and leans the torso left).

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Poser = {}

-- Joint name -> where its Motor6D lives on each rig type: { part, motor }
local JOINTS = {
	-- The whole body below the root: hip twist, crouch, falls and spins
	Root = { r15 = { "LowerTorso", "Root" }, r6 = { "HumanoidRootPart", "RootJoint" } },
	RightShoulder = { r15 = { "RightUpperArm", "RightShoulder" }, r6 = { "Torso", "Right Shoulder" } },
	LeftShoulder = { r15 = { "LeftUpperArm", "LeftShoulder" }, r6 = { "Torso", "Left Shoulder" } },
	RightElbow = { r15 = { "RightLowerArm", "RightElbow" } },
	LeftElbow = { r15 = { "LeftLowerArm", "LeftElbow" } },
	Torso = { r15 = { "UpperTorso", "Waist" }, r6 = { "HumanoidRootPart", "RootJoint" } },
	Neck = { r15 = { "Head", "Neck" }, r6 = { "Torso", "Neck" } },
	RightHip = { r15 = { "RightUpperLeg", "RightHip" }, r6 = { "Torso", "Right Hip" } },
	LeftHip = { r15 = { "LeftUpperLeg", "LeftHip" }, r6 = { "Torso", "Left Hip" } },
	RightKnee = { r15 = { "RightLowerLeg", "RightKnee" } },
	LeftKnee = { r15 = { "LeftLowerLeg", "LeftKnee" } },
}

-- Legs fade out of upper-body moves while walking, so the walk shows through
local LEGS = { RightHip = true, LeftHip = true, RightKnee = true, LeftKnee = true, Root = true }
-- Where a charge's tremble shows
local TREMBLE = { Torso = 1, RightShoulder = 1.4, LeftShoulder = 0.8, Root = 0.5, Neck = 0.6 }
-- Root offsets are authored for a standard R15 (hip pivot 2 studs up); lying
-- down takes the pivot to about half a stud above the floor
local AUTHORED_PIVOT = 2
local LYING_HEIGHT = 0.5

-- Poses: joint -> { pitch, yaw, roll[, x, y, z] }.
Poser.Poses = {
	Light1 = { RightShoulder = { 90, 0, -10 }, RightElbow = { 10, 0, 0 }, Torso = { 0, 25, 0 } },
	Light2 = { LeftShoulder = { 90, 0, 10 }, LeftElbow = { 10, 0, 0 }, Torso = { 0, -25, 0 } },
	Light3 = { RightShoulder = { 95, 0, -35 }, RightElbow = { 30, 0, 0 }, Torso = { 0, 40, 0 } },
	Light4 = { RightShoulder = { 160, 0, -10 }, RightElbow = { 20, 0, 0 }, Torso = { 12, 20, 0 }, Neck = { 10, 0, 0 } },
	HeavyWindup = {
		RightShoulder = { -35, 0, 45 },
		RightElbow = { 80, 0, 0 },
		LeftShoulder = { 60, 0, 20 },
		Torso = { 8, -45, 0 },
	},
	HeavyStrike = {
		RightShoulder = { 95, 0, -5 },
		RightElbow = { 0, 0, 0 },
		LeftShoulder = { -30, 0, 15 },
		Torso = { -12, 45, 0 },
	},
	-- A high guard: forearms up in front of the face, elbows in, knees soft
	Block = {
		RightShoulder = { 72, 0, -30 },
		LeftShoulder = { 76, 0, 30 },
		RightElbow = { 116, 0, 0 },
		LeftElbow = { 112, 0, 0 },
		Torso = { -10, 0, 0 },
		Neck = { -8, 0, 0 },
		Root = { 0, 0, 0, 0, -0.14, 0 },
		RightHip = { 10, 0, 4 },
		LeftHip = { 14, 0, -4 },
		RightKnee = { -16, 0, 0 },
		LeftKnee = { -20, 0, 0 },
	},
	-- Holding a light prop overhead (it's welded above the head)
	Carry = {
		RightShoulder = { 168, 0, 14 },
		LeftShoulder = { 168, 0, -14 },
		RightElbow = { 34, 0, 0 },
		LeftElbow = { 34, 0, 0 },
		Torso = { 6, 0, 0 },
		Neck = { -6, 0, 0 },
		Root = { 0, 0, 0, 0, -0.1, 0 },
	},
	-- Sprinting: chest over the hips, chin up
	SprintLean = { Torso = { -14, 0, 0 }, Neck = { 10, 0, 0 } },
	Hurt = { Torso = { 14, 0, 0 }, Neck = { 18, 0, 0 }, RightShoulder = { 10, 0, 25 }, LeftShoulder = { 10, 0, -25 } },
	Stagger = { Torso = { 22, 10, 0 }, Neck = { 25, 0, 0 }, RightShoulder = { 40, 0, 60 }, LeftShoulder = { 40, 0, -60 } },
	Dodge = { Torso = { -15, 0, 0 }, RightShoulder = { -30, 0, 10 }, LeftShoulder = { -30, 0, -10 } },

	-- Ability poses any power can use (powers can add their own with Poser.register)
	Slam = { RightShoulder = { 170, 0, -20 }, LeftShoulder = { 170, 0, 20 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 20, 0, 0 }, Torso = { 25, 0, 0 } },
	SlamWindup = { RightShoulder = { 175, 0, -10 }, LeftShoulder = { 175, 0, 10 }, Torso = { -18, 0, 0 }, Neck = { -10, 0, 0 } },
	Reach = { RightShoulder = { 95, 0, -15 }, LeftShoulder = { 95, 0, 15 }, Torso = { 12, 0, 0 } },
	Charge = { Torso = { 28, 0, 0 }, RightShoulder = { -40, 0, 20 }, LeftShoulder = { 70, 0, 20 }, Neck = { -15, 0, 0 } },
	Uppercut = { RightShoulder = { 175, 0, -5 }, RightElbow = { 40, 0, 0 }, Torso = { -15, 25, 0 }, Neck = { -15, 0, 0 } },
	UppercutWindup = { RightShoulder = { -25, 0, 30 }, RightElbow = { 90, 0, 0 }, Torso = { 20, -25, 0 } },
	Stomp = { RightHip = { 60, 0, 0 }, Torso = { 10, 0, 0 }, RightShoulder = { 30, 0, 40 }, LeftShoulder = { 30, 0, -40 } },
	Lift = { RightShoulder = { 175, 0, -10 }, LeftShoulder = { 175, 0, 10 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, Torso = { -10, 0, 0 } },
	Throw = { RightShoulder = { 120, 0, -10 }, LeftShoulder = { 120, 0, 10 }, Torso = { 25, 0, 0 } },
	Brace = { RightShoulder = { 70, 0, -50 }, LeftShoulder = { 70, 0, 50 }, RightElbow = { 110, 0, 0 }, LeftElbow = { 110, 0, 0 }, Torso = { 12, 0, 0 }, RightHip = { 20, 0, 10 }, LeftHip = { 20, 0, -10 } },
	PowerWindup = { RightShoulder = { -50, 0, 50 }, RightElbow = { 100, 0, 0 }, LeftShoulder = { 70, 0, 30 }, Torso = { 10, -55, 0 }, Neck = { 0, 30, 0 } },
	PowerPunch = { RightShoulder = { 100, 0, -5 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { -40, 0, 20 }, Torso = { -10, 55, 0 } },
	Cast = { RightShoulder = { 95, 0, -5 }, RightElbow = { 10, 0, 0 }, Torso = { 0, 15, 0 } },
	CastBoth = { RightShoulder = { 95, 0, -20 }, LeftShoulder = { 95, 0, 20 }, Torso = { -5, 0, 0 } },
	Aim = { RightShoulder = { 90, 0, 0 }, LeftShoulder = { 80, 0, 35 }, LeftElbow = { 30, 0, 0 }, Torso = { 0, 20, 0 } },
	Recoil = { RightShoulder = { 120, 0, 0 }, LeftShoulder = { 100, 0, 35 }, Torso = { -12, 20, 0 }, Neck = { -8, 0, 0 } },
	Raise = { RightShoulder = { 160, 0, -30 }, LeftShoulder = { 160, 0, 30 }, Torso = { -12, 0, 0 }, Neck = { -20, 0, 0 } },
	Spread = { RightShoulder = { 20, 0, 80 }, LeftShoulder = { 20, 0, -80 }, Torso = { -8, 0, 0 }, Neck = { -15, 0, 0 } },
	Kneel = { Torso = { 30, 0, 0 }, RightHip = { 90, 0, 0 }, LeftHip = { -10, 0, 0 }, RightShoulder = { 20, 0, 20 }, Neck = { 10, 0, 0 } },
	SlashRight = { RightShoulder = { 100, 0, 60 }, RightElbow = { 20, 0, 0 }, Torso = { 0, -35, 0 } },
	SlashLeft = { RightShoulder = { 100, 0, -70 }, RightElbow = { 10, 0, 0 }, Torso = { 0, 40, 0 } },
	SlashUp = { RightShoulder = { 170, 0, -10 }, RightElbow = { 10, 0, 0 }, Torso = { -10, 10, 0 } },
	SlashDown = { RightShoulder = { 60, 0, -10 }, RightElbow = { 0, 0, 0 }, Torso = { 25, 15, 0 } },
	Sheathe = { RightShoulder = { 30, 0, 30 }, RightElbow = { 80, 0, 0 }, Torso = { 0, -10, 0 } },
	Victory = { RightShoulder = { 170, 0, -20 }, LeftShoulder = { 40, 0, -30 }, Torso = { -8, 0, 0 }, Neck = { -15, 0, 0 } },
}

-- Adds (or replaces) a pose, for powers with moves of their own
function Poser.register(name: string, pose: { [string]: { number } })
	Poser.Poses[name] = pose
end

-- The resting C0 of each joint and which poses are held are stored as (local)
-- attributes on the instances themselves: Roblox can recycle the Lua object for
-- an Instance, so tables keyed by Instances may forget them. Active tweens and
-- tokens only need to live while a pose is playing (their closures keep them).
local BASE_ATTRIBUTE = "SNBaseC0"
-- Character scale when the resting C0 was saved (giant/tiny effects resize joints)
local SCALE_ATTRIBUTE = "SNBaseScale"
local HOLD_PREFIX = "SNHold_"
local tweens: { [Motor6D]: Tween } = setmetatable({}, { __mode = "k" }) :: any
local tokens: { [Motor6D]: number } = setmetatable({}, { __mode = "k" }) :: any

local function isR15(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
end

local function findMotor(character: Model, joint: string, r15: boolean?): Motor6D?
	local spec = JOINTS[joint]
	if not spec then
		return nil
	end
	if r15 == nil then
		r15 = isR15(character)
	end
	local location = if r15 then spec.r15 else spec.r6
	if not location then
		return nil
	end
	local part = character:FindFirstChild(location[1])
	local motor = part and part:FindFirstChild(location[2])
	if motor and motor:IsA("Motor6D") then
		return motor
	end
	return nil
end

local function modelScale(motor: Motor6D): number
	local model = motor:FindFirstAncestorOfClass("Model")
	return if model then model:GetScale() else 1
end

local function base(motor: Motor6D): CFrame
	local original = motor:GetAttribute(BASE_ATTRIBUTE)
	local scale = modelScale(motor)
	if typeof(original) ~= "CFrame" then
		original = motor.C0
		motor:SetAttribute(BASE_ATTRIBUTE, original)
		motor:SetAttribute(SCALE_ATTRIBUTE, scale)
	else
		-- Resizing a character moves its joints; move the saved rest pose with them
		local savedScale = motor:GetAttribute(SCALE_ATTRIBUTE)
		if typeof(savedScale) == "number" and savedScale > 0 and math.abs(savedScale - scale) > 1e-3 then
			local saved = original :: CFrame
			original = CFrame.new(saved.Position * (scale / savedScale)) * saved.Rotation
			motor:SetAttribute(BASE_ATTRIBUTE, original)
			motor:SetAttribute(SCALE_ATTRIBUTE, scale)
		end
	end
	return original :: CFrame
end

local function rotationOf(angles: { number }): CFrame
	return CFrame.Angles(math.rad(angles[1] or 0), math.rad(angles[2] or 0), math.rad(angles[3] or 0))
end

local function offsetOf(angles: { number }): Vector3
	return Vector3.new(angles[4] or 0, angles[5] or 0, angles[6] or 0)
end

local function posed(motor: Motor6D, angles: { number }): CFrame
	local original = base(motor)
	-- Rotate about the joint, in the parent part's space
	return CFrame.new(original.Position + offsetOf(angles)) * rotationOf(angles) * original.Rotation
end

local function tweenTo(motor: Motor6D, target: CFrame, duration: number, style: Enum.EasingStyle?)
	local previous = tweens[motor]
	if previous then
		previous:Cancel()
	end
	local tween = TweenService:Create(motor, TweenInfo.new(math.max(duration, 0.01), style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		C0 = target,
	})
	tweens[motor] = tween
	tween:Play()
	local token = (tokens[motor] or 0) + 1
	tokens[motor] = token
	return token
end

-- Stops any pose tween on a motor and makes its pending "return to rest" moot
local function claim(motor: Motor6D)
	local previous = tweens[motor]
	if previous then
		previous:Cancel()
		tweens[motor] = nil
	end
	tokens[motor] = (tokens[motor] or 0) + 1
end

-- Sequence driver state (declared here so the pose functions can defer to it)
local states: { [Model]: any } = {}
local stopTrack: (Model, boolean) -> ()

-- Goes into a pose over `inTime`, holds it, then eases back over `outTime`
function Poser.play(character: Model?, poseName: string, inTime: number, hold: number, outTime: number)
	if not character then
		return
	end
	local pose = Poser.Poses[poseName]
	if not pose then
		return
	end
	-- A power's own pose takes the body over from a running sequence
	stopTrack(character, false)
	for joint, angles in pose do
		local motor = findMotor(character, joint)
		if motor then
			local token = tweenTo(motor, posed(motor, angles), inTime, Enum.EasingStyle.Back)
			task.delay(inTime + hold, function()
				if tokens[motor] == token and motor.Parent then
					tweenTo(motor, base(motor), outTime)
				end
			end)
		end
	end
end

-- Holds a pose until released (blocking, carrying a prop). While a sequence is
-- playing it only marks the hold; the sequence ends in it.
function Poser.hold(character: Model?, poseName: string)
	if not character then
		return
	end
	if character:GetAttribute(HOLD_PREFIX .. poseName) then
		return
	end
	character:SetAttribute(HOLD_PREFIX .. poseName, true)
	if states[character] then
		return
	end
	local pose = Poser.Poses[poseName]
	for joint, angles in pose or {} do
		local motor = findMotor(character, joint)
		if motor then
			tweenTo(motor, posed(motor, angles), 0.1)
		end
	end
end

function Poser.release(character: Model?, poseName: string)
	if not character then
		return
	end
	if not character:GetAttribute(HOLD_PREFIX .. poseName) then
		return
	end
	character:SetAttribute(HOLD_PREFIX .. poseName, nil)
	if states[character] then
		return
	end
	local pose = Poser.Poses[poseName]
	for joint in pose or {} do
		local motor = findMotor(character, joint)
		if motor then
			-- Another held pose may still own this joint
			local target = base(motor)
			for name, value in character:GetAttributes() do
				if value == true and string.sub(name, 1, #HOLD_PREFIX) == HOLD_PREFIX then
					local other = Poser.Poses[string.sub(name, #HOLD_PREFIX + 1)]
					if other and other[joint] then
						target = posed(motor, other[joint])
					end
				end
			end
			tweenTo(motor, target, 0.15)
		end
	end
end

function Poser.isHolding(character: Model?, poseName: string): boolean
	return character ~= nil and character:GetAttribute(HOLD_PREFIX .. poseName) == true
end

-- Sequences -------------------------------------------------------------------------

-- Easing for the way into a key (alpha 0..1 -> 0..1)
local EASING = {
	Linear = function(a)
		return a
	end,
	In = function(a)
		return a * a
	end,
	Out = function(a)
		return 1 - (1 - a) * (1 - a)
	end,
	InOut = function(a)
		return 0.5 - 0.5 * math.cos(math.pi * a)
	end,
	-- A strike: almost all the travel in the first third, then it settles
	Snap = function(a)
		local inverse = 1 - a
		return 1 - inverse * inverse * inverse * inverse
	end,
	-- Goes past the key and comes back (overshoot)
	Back = function(a)
		local c1 = 1.70158
		local c3 = c1 + 1
		local x = a - 1
		return 1 + c3 * x * x * x + c1 * x * x
	end,
}

Poser.Sequences = {} :: { [string]: any }

local MIRROR_NAMES = {
	RightShoulder = "LeftShoulder",
	LeftShoulder = "RightShoulder",
	RightElbow = "LeftElbow",
	LeftElbow = "RightElbow",
	RightHip = "LeftHip",
	LeftHip = "RightHip",
	RightKnee = "LeftKnee",
	LeftKnee = "RightKnee",
}

local function prepareKey(t: number, pose: { [string]: { number } }, easing: string)
	local rotations, offsets = {}, {}
	for joint, angles in pose do
		rotations[joint] = rotationOf(angles)
		offsets[joint] = offsetOf(angles)
	end
	return { t = t, pose = pose, easing = EASING[easing] or EASING.InOut, easingName = easing, rotations = rotations, offsets = offsets }
end

-- Registers a keyframed move. keys = { { t, pose, easing? }, ... } (or
-- { t = , pose = , easing = }), with t in seconds from the start. Easing is how
-- the body travels INTO that key: "InOut" (default), "In", "Out", "Snap", "Back",
-- "Linear". Joints missing from a key are at rest in it. The first key is reached
-- from wherever the body is when the move starts.
-- info (all optional):
--   startup, active, recovery: the phase lengths the keys were authored for, so
--     Poser.sequence can stretch each phase to the server's real numbers
--   holdAt: the time the move pauses at until Poser.advance (lying down, charging)
--   tremble, trembleRamp: degrees of shake that build up over trembleRamp seconds
--   upper: the legs fade out while walking (strikes thrown on the move)
function Poser.registerSequence(name: string, keys: { any }, info: { [string]: any }?)
	local list = {}
	local joints = {}
	for _, key in keys do
		local t = key.t or key[1]
		local pose = key.pose or key[2] or {}
		local easing = key.easing or key[3] or "InOut"
		assert(typeof(t) == "number" and t >= 0, "sequence keys need a time")
		for joint in pose do
			joints[joint] = true
		end
		table.insert(list, prepareKey(t, pose, easing))
	end
	assert(#list > 0, "a sequence needs at least one key")
	table.sort(list, function(a, b)
		return a.t < b.t
	end)
	local jointList = {}
	for joint in joints do
		table.insert(jointList, joint)
	end
	table.sort(jointList)
	Poser.Sequences[name] = {
		name = name,
		keys = list,
		joints = jointList,
		info = info or {},
		length = list[#list].t,
	}
end

-- The same move done with the other side of the body
local function mirrored(name: string)
	local mirrorName = name .. "@mirror"
	local existing = Poser.Sequences[mirrorName]
	if existing then
		return existing
	end
	local source = Poser.Sequences[name]
	if not source then
		return nil
	end
	local keys = {}
	for _, key in source.keys do
		local pose = {}
		for joint, angles in key.pose do
			local flipped = { angles[1] or 0, -(angles[2] or 0), -(angles[3] or 0), -(angles[4] or 0), angles[5] or 0, angles[6] or 0 }
			pose[MIRROR_NAMES[joint] or joint] = flipped
		end
		table.insert(keys, { key.t, pose, key.easingName })
	end
	Poser.registerSequence(mirrorName, keys, source.info)
	return Poser.Sequences[mirrorName]
end

-- Maps an authored key time onto the real phase lengths
local function warp(t: number, authored: { number }, real: { number }): number
	local elapsedAuthored, elapsedReal = 0, 0
	for index = 1, 3 do
		local a, r = authored[index], real[index]
		if t <= elapsedAuthored + a then
			local share = if a > 1e-6 then (t - elapsedAuthored) / a else 1
			return elapsedReal + share * r
		end
		elapsedAuthored += a
		elapsedReal += r
	end
	-- After the recovery: the tail keeps its authored length
	return elapsedReal + (t - elapsedAuthored)
end

-- Height of the hip pivot above the floor, to scale crouches and falls to the rig
local function rootScale(character: Model, rootMotor: Motor6D?, r15: boolean): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return 1
	end
	local pivot
	if r15 then
		local jointHeight = if rootMotor then base(rootMotor).Position.Y else -1
		pivot = humanoid.HipHeight + root.Size.Y / 2 + jointHeight
	else
		pivot = root.Size.Y * 1.5 * character:GetScale()
	end
	return math.clamp((pivot - LYING_HEIGHT) / (AUTHORED_PIVOT - LYING_HEIGHT), 0.3, 4)
end

-- Underlying pose for a joint when nothing plays: a held pose or rest
local function heldAngles(character: Model, joint: string): { number }?
	local found = nil
	for name, value in character:GetAttributes() do
		if value == true and string.sub(name, 1, #HOLD_PREFIX) == HOLD_PREFIX then
			local pose = Poser.Poses[string.sub(name, #HOLD_PREFIX + 1)]
			if pose and pose[joint] then
				found = pose[joint]
			end
		end
	end
	return found
end

local timeScale = 1
local timeScaleUntil = 0
local connection: RBXScriptConnection? = nil
local step: (number) -> ()

local function ensureDriver()
	if connection == nil then
		connection = RunService.RenderStepped:Connect(function(dt)
			step(dt)
		end)
	end
end

-- Ends the running sequence. settle = true puts the body back at rest (or in its
-- held poses); false leaves the joints where they are for a tween to take over.
stopTrack = function(character: Model, settle: boolean)
	local state = states[character]
	if not state then
		return
	end
	states[character] = nil
	if not settle or not character.Parent then
		return
	end
	for _, group in state.groups do
		local motor = group.motor
		if motor.Parent then
			local held = nil
			for _, joint in group.joints do
				held = held or heldAngles(character, joint)
			end
			if held then
				tweenTo(motor, posed(motor, held), 0.1)
			else
				motor.C0 = group.base
			end
		end
	end
end

-- Plays a registered sequence on a character. speed scales its playback (1 =
-- as authored). options:
--   timing = { startup, active, recovery }: stretch the phases to these lengths
--   mirror = true: use the other side of the body
--   holdFor = seconds: if the move has holdAt, let go by itself after this long
-- Returns how long the move lasts (not counting a hold).
function Poser.sequence(character: Model?, name: string, speed: number?, options: { [string]: any }?): number
	if not character or not character.Parent then
		return 0
	end
	local opts = options or {}
	local sequence = if opts.mirror then mirrored(name) else Poser.Sequences[name]
	if not sequence then
		return 0
	end
	local info = sequence.info
	local rate = math.max(0.05, speed or 1)

	-- Key times, stretched to the real phases when both are known
	local times = table.create(#sequence.keys)
	local timing = opts.timing
	local authored = if info.startup then { info.startup, info.active or 0, info.recovery or 0 } else nil
	local real = nil
	if authored and typeof(timing) == "table" then
		real = {
			math.max(0, tonumber(timing.startup or timing[1]) or authored[1]),
			math.max(0, tonumber(timing.active or timing[2]) or authored[2]),
			math.max(0, tonumber(timing.recovery or timing[3]) or authored[3]),
		}
	end
	for index, key in sequence.keys do
		times[index] = if real then warp(key.t, authored :: { number }, real) else key.t
	end
	local holdAt = if info.holdAt then (if real then warp(info.holdAt, authored :: { number }, real) else info.holdAt) else nil

	-- The joints it moves, grouped by motor (R6 drives Root and Torso with one)
	local r15 = isR15(character)
	local groups, byMotor = {}, {}
	local from = {}
	local rootMotor = nil
	for _, joint in sequence.joints do
		local motor = findMotor(character, joint, r15)
		if motor then
			if joint == "Root" then
				rootMotor = motor
			end
			local group = byMotor[motor]
			if not group then
				claim(motor)
				local rest = base(motor)
				group = { motor = motor, base = rest, joints = {} }
				byMotor[motor] = group
				table.insert(groups, group)
				-- Start from where the joint really is (mid-tween, mid-move, held)
				local current = motor.C0
				from[joint] = { rot = current.Rotation * rest.Rotation:Inverse(), off = current.Position - rest.Position }
			else
				from[joint] = { rot = CFrame.identity, off = Vector3.zero }
			end
			table.insert(group.joints, joint)
		end
	end

	local previous = states[character]
	local state = {
		sequence = sequence,
		times = times,
		holdAt = holdAt,
		holdUntil = if holdAt and opts.holdFor then os.clock() + opts.holdFor else nil,
		released = false,
		clock = 0,
		elapsed = 0,
		rate = rate,
		groups = groups,
		from = from,
		rootScale = rootScale(character, rootMotor, r15),
		legWeight = 1,
		frozenUntil = if previous then previous.frozenUntil else 0,
		seed = math.random() * 100,
	}
	-- Joints the previous move used but this one doesn't go back to rest
	if previous then
		for _, group in previous.groups do
			if not byMotor[group.motor] and group.motor.Parent then
				local held = nil
				for _, joint in group.joints do
					held = held or heldAngles(character, joint)
				end
				tweenTo(group.motor, if held then posed(group.motor, held) else group.base, 0.12)
			end
		end
	end
	states[character] = state
	ensureDriver()
	local length = times[#times]
	return length / rate
end

-- Lets a move that pauses (holdAt) carry on: the charge swings, the fighter gets up
function Poser.advance(character: Model?)
	local state = character and states[character]
	if state then
		state.released = true
	end
end

-- Ends whatever sequence plays on the character, easing back to rest
function Poser.stop(character: Model?)
	if not character then
		return
	end
	local state = states[character]
	if not state then
		return
	end
	stopTrack(character, false)
	for _, group in state.groups do
		if group.motor.Parent then
			local held = nil
			for _, joint in group.joints do
				held = held or heldAngles(character, joint)
			end
			tweenTo(group.motor, if held then posed(group.motor, held) else group.base, 0.18)
		end
	end
end

-- Name of the sequence playing on the character (nil when none)
function Poser.playing(character: Model?): string?
	local state = character and states[character]
	return if state then state.sequence.name else nil
end

-- Hitstop: freezes the character's sequence for a moment
function Poser.freeze(character: Model?, duration: number)
	local state = character and states[character]
	if state then
		state.frozenUntil = math.max(state.frozenUntil, os.clock() + duration)
	end
end

-- Slows (or speeds) every sequence on this client for a while (perfect dodge)
function Poser.setTimeScale(scale: number, duration: number)
	timeScale = math.clamp(scale, 0.05, 4)
	timeScaleUntil = os.clock() + duration
end

local function lerpAngles(a: { number }?, b: { number }?, alpha: number): (CFrame, Vector3)
	local pa = a or {}
	local pb = b or {}
	local function mix(index: number): number
		local x = pa[index] or 0
		return x + ((pb[index] or 0) - x) * alpha
	end
	return CFrame.Angles(math.rad(mix(1)), math.rad(mix(2)), math.rad(mix(3))), Vector3.new(mix(4), mix(5), mix(6))
end

local function horizontalSpeed(character: Model): number
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local velocity = root.AssemblyLinearVelocity
		return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	end
	return 0
end

step = function(dt: number)
	local now = os.clock()
	local scale = if now < timeScaleUntil then timeScale else 1
	local any = false
	for character, state in states do
		any = true
		if not character.Parent then
			states[character] = nil
			continue
		end
		if now < state.frozenUntil then
			continue
		end
		local sequence = state.sequence
		local info = sequence.info
		local advance = dt * state.rate * scale
		state.elapsed += advance
		local clock = state.clock + advance
		if state.holdAt and not state.released then
			if state.holdUntil and now >= state.holdUntil then
				state.released = true
			elseif clock > state.holdAt then
				clock = state.holdAt
			end
		end
		state.clock = clock

		local times = state.times
		local keys = sequence.keys
		local count = #keys
		if clock >= times[count] then
			stopTrack(character, true)
			continue
		end

		-- The key the body is travelling into
		local index = 1
		while index < count and times[index] < clock do
			index += 1
		end
		local key = keys[index]
		local startTime = if index == 1 then 0 else times[index - 1]
		local span = times[index] - startTime
		local alpha = if span > 1e-4 then math.clamp((clock - startTime) / span, 0, 1) else 1
		alpha = key.easing(alpha)

		-- Walking: the legs leave upper-body moves to the walk cycle
		if info.upper then
			local target = if horizontalSpeed(character) > 4 then 0.2 else 1
			state.legWeight += (target - state.legWeight) * math.min(1, dt * 10)
		end
		local tremble = 0
		if info.tremble then
			tremble = info.tremble * math.clamp(state.elapsed / (info.trembleRamp or 1), 0, 1)
		end

		for _, group in state.groups do
			local motor = group.motor
			if not motor.Parent then
				continue
			end
			local rotation, offset = CFrame.identity, Vector3.zero
			for _, joint in group.joints do
				local rot, off
				if index == 1 then
					local start = state.from[joint]
					rot = start.rot:Lerp(key.rotations[joint] or CFrame.identity, alpha)
					off = start.off:Lerp(key.offsets[joint] or Vector3.zero, alpha)
				else
					rot, off = lerpAngles(keys[index - 1].pose[joint], key.pose[joint], alpha)
				end
				if joint == "Root" then
					off *= state.rootScale
				end
				if info.upper and LEGS[joint] and state.legWeight < 0.999 then
					rot = CFrame.identity:Lerp(rot, state.legWeight)
					off *= state.legWeight
				end
				local amount = TREMBLE[joint]
				if tremble > 0 and amount then
					local t = state.elapsed * 22
					local seed = state.seed + #joint
					rot *= CFrame.Angles(
						math.rad(math.noise(t, seed, 0.5) * tremble * amount),
						math.rad(math.noise(seed, t, 1.5) * tremble * amount),
						math.rad(math.noise(0.5, seed, t) * tremble * amount * 0.6)
					)
				end
				rotation *= rot
				offset += off
			end
			motor.C0 = CFrame.new(group.base.Position + offset) * rotation * group.base.Rotation
		end
	end
	if not any and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- The move library (registered below) ------------------------------------------------

return Poser
