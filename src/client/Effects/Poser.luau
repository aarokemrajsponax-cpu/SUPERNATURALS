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

-- Sequence driver state (declared here so the pose functions can defer to it).
-- Keyed by an id kept in an attribute on the character, for the same reason as
-- the rest poses above; each state remembers its model.
local states: { [string]: any } = {}
local stopTrack: (Model, boolean) -> ()
local KEY_ATTRIBUTE = "SNPoseKey"
local nextKey = 0

-- A stable key for a character (a copied model gets its own)
local function keyOf(character: Model): string
	local key = character:GetAttribute(KEY_ATTRIBUTE)
	if typeof(key) == "string" then
		local state = states[key]
		if state == nil or state.model == character then
			return key
		end
	end
	nextKey += 1
	key = "p" .. nextKey
	character:SetAttribute(KEY_ATTRIBUTE, key)
	return key
end
Poser.keyOf = keyOf

local function stateOf(character: Model?): any
	if not character then
		return nil
	end
	local key = character:GetAttribute(KEY_ATTRIBUTE)
	local state = if typeof(key) == "string" then states[key] else nil
	return if state and state.model == character then state else nil
end

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
	if stateOf(character) then
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
	if stateOf(character) then
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
	local state = stateOf(character)
	if not state then
		return
	end
	states[state.key] = nil
	if not settle or not character.Parent then
		return
	end
	local last = state.sequence.keys[#state.sequence.keys].pose
	for _, group in state.groups do
		local motor = group.motor
		if motor.Parent then
			local held, posedAtEnd = nil, false
			for _, joint in group.joints do
				held = held or heldAngles(character, joint)
				local angles = last[joint]
				-- A spin that ends a full turn round is back at rest
				if angles and (math.abs((angles[1] or 0) % 360) + math.abs((angles[2] or 0) % 360) + math.abs((angles[3] or 0) % 360) > 0.5 or offsetOf(angles).Magnitude > 0.01) then
					posedAtEnd = true
				end
			end
			if held then
				tweenTo(motor, posed(motor, held), 0.1)
			elseif posedAtEnd then
				tweenTo(motor, group.base, 0.15)
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

	local key = keyOf(character)
	local previous = stateOf(character)
	local state = {
		key = key,
		model = character,
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
	states[key] = state
	ensureDriver()
	local length = times[#times]
	return length / rate
end

-- Lets a move that pauses (holdAt) carry on: the charge swings, the fighter gets up
function Poser.advance(character: Model?)
	local state = stateOf(character)
	if state then
		state.released = true
	end
end

-- Ends whatever sequence plays on the character, easing back to rest
function Poser.stop(character: Model?)
	local state = stateOf(character)
	if not character or not state then
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
	local state = stateOf(character)
	return if state then state.sequence.name else nil
end

-- Hitstop: freezes the character's sequence for a moment
function Poser.freeze(character: Model?, duration: number)
	local state = stateOf(character)
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
	for key, state in states do
		any = true
		local character = state.model
		if not character.Parent then
			states[key] = nil
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

-- The move library ----------------------------------------------------------------------
-- Every combat move and reaction. Times are seconds, authored for the default
-- numbers in Config/Combat (startup/active/recovery in each info), and
-- Poser.sequence stretches them to whatever the server sends. A strike reaches
-- full extension exactly when its hitbox opens (the end of startup), overshoots
-- a little during the active frames, then recovers. Hips and shoulders lead:
-- the Root twists before the arm arrives, and the head counter-turns so the eyes
-- stay on the target.

local function merge(...: { [string]: { number } }): { [string]: { number } }
	local result = {}
	for _, pose in { ... } do
		for joint, angles in pose do
			result[joint] = angles
		end
	end
	return result
end

local function define(name: string, info: { [string]: any }, keys: { any })
	Poser.registerSequence(name, keys, info)
end

local REST = {}

-- Orthodox fighting stance: left side forward, hands up, knees soft
local GUARD = {
	Root = { 0, -12, 0, 0, -0.12, 0 },
	Torso = { -6, -8, 0 },
	Neck = { -6, 18, 0 },
	LeftShoulder = { 62, 0, 18 },
	LeftElbow = { 100, 0, 0 },
	RightShoulder = { 52, 0, -24 },
	RightElbow = { 112, 0, 0 },
	LeftHip = { 20, 0, -4 },
	LeftKnee = { -28, 0, 0 },
	RightHip = { -12, 0, 6 },
	RightKnee = { -22, 0, 0 },
}
local BLOCK = Poser.Poses.Block

-- Light string ---------------------------------------------------------------------------

-- Jab: the lead hand snaps straight out and straight back
define("Jab", { startup = 0.1, active = 0.1, recovery = 0.2, upper = true }, {
	{ 0.06, merge(GUARD, { Root = { 0, -16, 0, 0, -0.14, 0 }, Torso = { -4, -4, 0 }, LeftShoulder = { 56, 0, 22 }, LeftElbow = { 112, 0, 0 } }) },
	{ 0.1, merge(GUARD, {
		Root = { 0, -24, 0, 0, -0.16, 0 },
		Torso = { -10, -18, 0 },
		Neck = { -8, 30, 0 },
		LeftShoulder = { 90, 0, 8 },
		LeftElbow = { 4, 0, 0 },
		LeftHip = { 26, 0, -4 },
		LeftKnee = { -32, 0, 0 },
		RightHip = { -16, 0, 6 },
		RightKnee = { -18, 0, 0 },
	}), "Snap" },
	{ 0.15, merge(GUARD, { Root = { 0, -26, 0, 0, -0.16, 0 }, Torso = { -12, -22, 0 }, Neck = { -8, 32, 0 }, LeftShoulder = { 93, 0, 6 }, LeftElbow = { 0, 0, 0 } }), "Out" },
	{ 0.2, merge(GUARD, { Torso = { -8, -14, 0 }, LeftShoulder = { 82, 0, 14 }, LeftElbow = { 26, 0, 0 } }) },
	{ 0.3, GUARD },
	{ 0.4, REST },
})

-- Cross: the rear hand, thrown with the hips; the rear heel turns and the lead hand guards the chin
define("Cross", { startup = 0.1, active = 0.1, recovery = 0.2, upper = true }, {
	{ 0.06, merge(GUARD, { Root = { 0, -22, 0, 0, -0.18, 0 }, Torso = { -4, -16, 0 }, Neck = { -6, 36, 0 }, RightShoulder = { 46, 0, -20 }, RightElbow = { 122, 0, 0 } }) },
	{ 0.1, merge(GUARD, {
		Root = { 0, 16, 0, 0, -0.2, 0 },
		Torso = { -12, 26, 0 },
		Neck = { -8, -40, 0 },
		RightShoulder = { 90, 0, -12 },
		RightElbow = { 4, 0, 0 },
		LeftShoulder = { 58, 0, 30 },
		LeftElbow = { 120, 0, 0 },
		RightHip = { -4, 0, 2 },
		RightKnee = { -32, 0, 0 },
		LeftHip = { 22, 0, -4 },
		LeftKnee = { -24, 0, 0 },
	}), "Snap" },
	{ 0.15, merge(GUARD, {
		Root = { 0, 20, 0, 0, -0.2, 0 },
		Torso = { -14, 32, 0 },
		Neck = { -8, -48, 0 },
		RightShoulder = { 93, 0, -10 },
		RightElbow = { 0, 0, 0 },
		LeftShoulder = { 58, 0, 30 },
		LeftElbow = { 120, 0, 0 },
		RightKnee = { -32, 0, 0 },
	}), "Out" },
	{ 0.2, merge(GUARD, { Root = { 0, 10, 0, 0, -0.16, 0 }, Torso = { -8, 18, 0 }, Neck = { -6, -26, 0 }, RightShoulder = { 80, 0, -16 }, RightElbow = { 30, 0, 0 } }) },
	{ 0.3, GUARD },
	{ 0.4, REST },
})

-- Hook: the lead elbow lifts out to the side, then the whole torso swings it through
define("Hook", { startup = 0.12, active = 0.1, recovery = 0.22, upper = true }, {
	{ 0.07, merge(GUARD, { Root = { 0, 8, 0, 0, -0.22, 0 }, Torso = { -6, 20, 0 }, Neck = { -6, -26, 0 }, LeftShoulder = { 22, -10, -74 }, LeftElbow = { 98, 0, 0 }, LeftKnee = { -30, 0, 0 }, RightKnee = { -26, 0, 0 } }) },
	{ 0.12, merge(GUARD, {
		Root = { 0, -24, 0, 0, -0.24, 0 },
		Torso = { -10, -34, 0 },
		Neck = { -8, 52, 0 },
		LeftShoulder = { 6, -55, -82 },
		LeftElbow = { 92, 0, 0 },
		LeftHip = { 22, 0, -2 },
		LeftKnee = { -36, 0, 0 },
		RightHip = { -8, 0, 4 },
		RightKnee = { -26, 0, 0 },
	}), "Snap" },
	{ 0.17, merge(GUARD, { Root = { 0, -28, 0, 0, -0.24, 0 }, Torso = { -12, -44, 0 }, Neck = { -8, 60, 0 }, LeftShoulder = { 4, -70, -80 }, LeftElbow = { 92, 0, 0 }, LeftKnee = { -36, 0, 0 } }), "Out" },
	{ 0.22, merge(GUARD, { Root = { 0, -20, 0, 0, -0.18, 0 }, Torso = { -8, -34, 0 }, Neck = { -6, 46, 0 }, LeftShoulder = { 24, -44, -56 }, LeftElbow = { 104, 0, 0 } }) },
	{ 0.34, GUARD },
	{ 0.44, REST },
})

-- Finisher kick: a rising roundhouse. The knee chambers, the support foot pivots
-- (the whole body turns 70 degrees), the shin whips out at hip height, the arms
-- counterbalance and the torso leans away from the kick.
define("FinisherKick", { startup = 0.16, active = 0.12, recovery = 0.45 }, {
	{ 0.09, {
		Root = { 0, 26, 0, 0, -0.06, 0 },
		Torso = { 6, -12, 6 },
		Neck = { -6, -14, 0 },
		RightHip = { 70, 0, 30 },
		RightKnee = { -104, 0, 0 },
		LeftHip = { 4, 0, 0 },
		LeftKnee = { -20, 0, 0 },
		LeftShoulder = { 46, 0, 24 },
		LeftElbow = { 96, 0, 0 },
		RightShoulder = { -14, 0, 28 },
		RightElbow = { 70, 0, 0 },
	} },
	{ 0.16, {
		Root = { 0, 72, 0, 0, -0.04, 0 },
		Torso = { 18, -30, 16 },
		Neck = { -10, -42, -10 },
		RightHip = { 14, 0, 86 },
		RightKnee = { -8, 0, 0 },
		LeftHip = { -4, 0, -4 },
		LeftKnee = { -16, 0, 0 },
		LeftShoulder = { 56, 0, 34 },
		LeftElbow = { 92, 0, 0 },
		RightShoulder = { -24, 0, 48 },
		RightElbow = { 30, 0, 0 },
	}, "Snap" },
	{ 0.22, {
		Root = { 0, 92, 0, 0, -0.04, 0 },
		Torso = { 20, -34, 18 },
		Neck = { -10, -50, -12 },
		RightHip = { 12, 0, 82 },
		RightKnee = { -10, 0, 0 },
		LeftHip = { -4, 0, -4 },
		LeftKnee = { -16, 0, 0 },
		LeftShoulder = { 56, 0, 34 },
		LeftElbow = { 92, 0, 0 },
		RightShoulder = { -24, 0, 48 },
		RightElbow = { 30, 0, 0 },
	}, "Out" },
	{ 0.28, {
		Root = { 0, 70, 0, 0, -0.08, 0 },
		Torso = { 10, -24, 8 },
		Neck = { -8, -40, -6 },
		RightHip = { 50, 0, 40 },
		RightKnee = { -96, 0, 0 },
		LeftKnee = { -20, 0, 0 },
		LeftShoulder = { 50, 0, 28 },
		LeftElbow = { 96, 0, 0 },
		RightShoulder = { 10, 0, 30 },
		RightElbow = { 60, 0, 0 },
	} },
	{ 0.48, merge(GUARD, { Root = { 0, 20, 0, 0, -0.12, 0 }, Torso = { 0, -6, 0 }, Neck = { -4, -12, 0 }, RightHip = { 14, 0, 6 }, RightKnee = { -26, 0, 0 } }) },
	{ 0.73, REST },
})

-- Heavy: an overhand right. A long, readable load (hips coil, weight sinks onto
-- the rear leg, the lead hand measures), a hitch, then everything unwinds at once.
local HEAVY_LOAD = {
	Root = { 0, -32, 0, 0, -0.34, 0 },
	Torso = { -4, -30, -6 },
	Neck = { -10, 52, 4 },
	RightShoulder = { -30, 0, 50 },
	RightElbow = { 96, 0, 0 },
	LeftShoulder = { 76, 0, 24 },
	LeftElbow = { 40, 0, 0 },
	LeftHip = { 24, 0, -4 },
	LeftKnee = { -34, 0, 0 },
	RightHip = { -14, 0, 6 },
	RightKnee = { -38, 0, 0 },
}
local HEAVY_CONTACT = {
	Root = { 0, 30, 0, 0, -0.3, 0 },
	Torso = { -18, 34, 4 },
	Neck = { -6, -52, 0 },
	RightShoulder = { 102, 0, -8 },
	RightElbow = { 2, 0, 0 },
	LeftShoulder = { 32, 0, 12 },
	LeftElbow = { 112, 0, 0 },
	RightHip = { -4, 0, 2 },
	RightKnee = { -40, 0, 0 },
	LeftHip = { 28, 0, -4 },
	LeftKnee = { -28, 0, 0 },
}
local HEAVY_RECOVER = {
	Root = { 0, 10, 0, 0, -0.14, 0 },
	Torso = { -6, 10, 0 },
	Neck = { -4, -14, 0 },
	RightShoulder = { 60, 0, -20 },
	RightElbow = { 70, 0, 0 },
	LeftShoulder = { 50, 0, 16 },
	LeftElbow = { 90, 0, 0 },
	LeftKnee = { -16, 0, 0 },
	RightKnee = { -16, 0, 0 },
}
define("Heavy", { startup = 0.5, active = 0.14, recovery = 0.4, upper = true }, {
	{ 0.3, HEAVY_LOAD },
	{ 0.46, merge(HEAVY_LOAD, { Root = { 0, -36, 0, 0, -0.4, 0 }, Torso = { -2, -36, -8 }, Neck = { -10, 58, 6 }, RightShoulder = { -38, 0, 56 } }) },
	{ 0.5, HEAVY_CONTACT, "Snap" },
	{ 0.58, merge(HEAVY_CONTACT, { Root = { 0, 36, 0, 0, -0.34, 0 }, Torso = { -22, 40, 4 }, Neck = { -6, -58, 0 }, RightShoulder = { 97, 0, -14 } }), "Out" },
	{ 0.64, merge(HEAVY_CONTACT, { Torso = { -18, 36, 4 }, RightShoulder = { 92, 0, -14 }, RightElbow = { 10, 0, 0 } }) },
	{ 0.84, HEAVY_RECOVER },
	{ 1.04, REST },
})

-- Charging: a deeper coil that keeps sinking, fist cocked by the ear, shaking
-- harder the longer it's held. It pauses at full charge until the release.
local CHARGE_COIL = {
	Root = { 0, -40, 0, 0, -0.44, 0 },
	Torso = { 6, -38, -8 },
	Neck = { -14, 62, 6 },
	RightShoulder = { -44, 0, 60 },
	RightElbow = { 112, 0, 0 },
	LeftShoulder = { 80, 0, 30 },
	LeftElbow = { 30, 0, 0 },
	LeftHip = { 28, 0, -4 },
	LeftKnee = { -42, 0, 0 },
	RightHip = { -16, 0, 6 },
	RightKnee = { -46, 0, 0 },
}
define("ChargeHold", { holdAt = 1.2, tremble = 3.5, trembleRamp = 1.2 }, {
	{ 0.22, CHARGE_COIL },
	{ 1.2, merge(CHARGE_COIL, { Root = { 0, -44, 0, 0, -0.54, 0 }, Torso = { 8, -44, -10 }, Neck = { -14, 66, 8 }, RightShoulder = { -52, 0, 64 }, RightKnee = { -54, 0, 0 } }) },
	{ 1.6, REST },
})

-- Letting a charge go: the coil explodes forward (from the charge pose)
define("ChargedStrike", { startup = 0.18, active = 0.14, recovery = 0.4 }, {
	{ 0.12, merge(HEAVY_CONTACT, { Root = { 0, 14, 0, 0, -0.42, 0 }, Torso = { -18, 22, 0 }, Neck = { -8, -20, 0 }, RightShoulder = { 70, 0, -4 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 40, 0, 16 }, LeftElbow = { 100, 0, 0 } }), "In" },
	{ 0.18, merge(HEAVY_CONTACT, {
		Root = { 0, 42, 0, 0, -0.36, 0 },
		Torso = { -26, 44, 6 },
		Neck = { -6, -58, 0 },
		RightShoulder = { 98, 0, -10 },
		RightElbow = { 0, 0, 0 },
		LeftShoulder = { 20, 0, 20 },
		LeftElbow = { 120, 0, 0 },
		RightHip = { 0, 0, 0 },
		RightKnee = { -50, 0, 0 },
		LeftHip = { 34, 0, -4 },
		LeftKnee = { -36, 0, 0 },
	}), "Snap" },
	{ 0.26, merge(HEAVY_CONTACT, { Root = { 0, 48, 0, 0, -0.36, 0 }, Torso = { -30, 52, 8 }, Neck = { -6, -64, 0 }, RightShoulder = { 96, 0, -14 }, LeftShoulder = { 20, 0, 20 }, LeftElbow = { 120, 0, 0 }, RightKnee = { -50, 0, 0 } }), "Out" },
	{ 0.32, merge(HEAVY_CONTACT, { Root = { 0, 44, 0, 0, -0.34, 0 }, Torso = { -26, 46, 6 }, Neck = { -6, -56, 0 }, RightShoulder = { 92, 0, -14 }, RightElbow = { 10, 0, 0 } }) },
	{ 0.52, merge(HEAVY_RECOVER, { Root = { 0, 16, 0, 0, -0.2, 0 }, Torso = { -8, 14, 0 }, RightShoulder = { 50, 0, -16 }, RightElbow = { 80, 0, 0 } }) },
	{ 0.72, REST },
})

-- Directional, sprint and air moves -------------------------------------------------------

-- Launcher: crouch low, then drive up through the legs into an uppercut
define("Launcher", { startup = 0.28, active = 0.12, recovery = 0.4 }, {
	{ 0.2, {
		Root = { 0, -18, 0, 0, -0.58, 0 },
		Torso = { -26, -18, 0 },
		Neck = { 22, 18, 0 },
		RightShoulder = { 10, 0, 22 },
		RightElbow = { 104, 0, 0 },
		LeftShoulder = { 60, 0, 24 },
		LeftElbow = { 100, 0, 0 },
		LeftHip = { 42, 0, -4 },
		LeftKnee = { -62, 0, 0 },
		RightHip = { 14, 0, 6 },
		RightKnee = { -64, 0, 0 },
	} },
	{ 0.28, {
		Root = { 0, 22, 0, 0, 0.12, 0 },
		Torso = { 14, 24, 0 },
		Neck = { 6, -22, 0 },
		RightShoulder = { 166, 0, -10 },
		RightElbow = { 28, 0, 0 },
		LeftShoulder = { 28, 0, 12 },
		LeftElbow = { 112, 0, 0 },
		LeftHip = { 6, 0, 0 },
		LeftKnee = { -6, 0, 0 },
		RightHip = { -10, 0, 0 },
		RightKnee = { -12, 0, 0 },
	}, "Snap" },
	{ 0.34, {
		Root = { 0, 24, 0, 0, 0.18, 0 },
		Torso = { 20, 28, 0 },
		Neck = { 8, -24, 0 },
		RightShoulder = { 173, 0, -6 },
		RightElbow = { 22, 0, 0 },
		LeftShoulder = { 28, 0, 12 },
		LeftElbow = { 112, 0, 0 },
		RightHip = { -10, 0, 0 },
		RightKnee = { -10, 0, 0 },
	}, "Out" },
	{ 0.4, { Root = { 0, 20, 0, 0, 0.1, 0 }, Torso = { 16, 24, 0 }, Neck = { 6, -20, 0 }, RightShoulder = { 160, 0, -8 }, RightElbow = { 34, 0, 0 }, LeftShoulder = { 30, 0, 12 }, LeftElbow = { 108, 0, 0 } } },
	{ 0.6, { Root = { 0, 6, 0, 0, -0.12, 0 }, Torso = { 0, 8, 0 }, RightShoulder = { 80, 0, -12 }, RightElbow = { 84, 0, 0 }, LeftShoulder = { 46, 0, 16 }, LeftElbow = { 96, 0, 0 }, LeftKnee = { -14, 0, 0 }, RightKnee = { -14, 0, 0 } } },
	{ 0.8, REST },
})

-- Rush strike: running momentum poured into a long, low straight right
define("RushStrike", { startup = 0.14, active = 0.14, recovery = 0.3 }, {
	{ 0.08, {
		Root = { 0, -16, 0, 0, -0.26, 0 },
		Torso = { -28, -16, 0 },
		Neck = { 22, 16, 0 },
		RightShoulder = { -30, 0, 30 },
		RightElbow = { 92, 0, 0 },
		LeftShoulder = { 72, 0, 20 },
		LeftElbow = { 60, 0, 0 },
		LeftHip = { 40, 0, -2 },
		LeftKnee = { -50, 0, 0 },
		RightHip = { -30, 0, 4 },
		RightKnee = { -30, 0, 0 },
	} },
	{ 0.14, {
		Root = { 0, 22, 0, 0, -0.3, 0 },
		Torso = { -30, 28, 0 },
		Neck = { 24, -28, 0 },
		RightShoulder = { 100, 0, -10 },
		RightElbow = { 0, 0, 0 },
		LeftShoulder = { -30, 0, -18 },
		LeftElbow = { 84, 0, 0 },
		LeftHip = { 48, 0, -2 },
		LeftKnee = { -44, 0, 0 },
		RightHip = { -40, 0, 4 },
		RightKnee = { -20, 0, 0 },
	}, "Snap" },
	{ 0.22, {
		Root = { 0, 24, 0, 0, -0.3, 0 },
		Torso = { -34, 32, 0 },
		Neck = { 26, -30, 0 },
		RightShoulder = { 104, 0, -8 },
		LeftShoulder = { -30, 0, -18 },
		LeftElbow = { 84, 0, 0 },
		LeftHip = { 48, 0, -2 },
		LeftKnee = { -44, 0, 0 },
		RightHip = { -40, 0, 4 },
		RightKnee = { -20, 0, 0 },
	}, "Out" },
	{ 0.28, { Root = { 0, 20, 0, 0, -0.28, 0 }, Torso = { -28, 26, 0 }, Neck = { 22, -26, 0 }, RightShoulder = { 96, 0, -10 }, RightElbow = { 12, 0, 0 }, LeftShoulder = { -16, 0, -14 }, LeftElbow = { 80, 0, 0 }, LeftHip = { 40, 0, 0 }, LeftKnee = { -40, 0, 0 } } },
	{ 0.45, { Root = { 0, 8, 0, 0, -0.12, 0 }, Torso = { -10, 10, 0 }, Neck = { 8, -8, 0 }, RightShoulder = { 50, 0, -16 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 40, 0, 10 }, LeftElbow = { 90, 0, 0 } } },
	{ 0.58, REST },
})

-- Shoulder charge: turn side-on, tuck the lead shoulder, drive off the back leg
local SHOULDER = {
	Root = { 0, -62, 0, 0, -0.46, 0 },
	Torso = { -30, -24, 14 },
	Neck = { -4, 66, -10 },
	LeftShoulder = { 24, 0, 24 },
	LeftElbow = { 112, 0, 0 },
	RightShoulder = { 44, 0, -40 },
	RightElbow = { 100, 0, 0 },
	LeftHip = { 52, 0, -4 },
	LeftKnee = { -40, 0, 0 },
	RightHip = { -36, 0, 6 },
	RightKnee = { -20, 0, 0 },
}
define("ShoulderCharge", { startup = 0.22, active = 0.2, recovery = 0.4 }, {
	{ 0.14, merge(SHOULDER, { Root = { 0, -50, 0, 0, -0.4, 0 }, Torso = { -22, -20, 10 }, Neck = { -6, 62, -8 }, LeftShoulder = { 30, 0, 30 }, LeftHip = { 40, 0, -4 }, LeftKnee = { -56, 0, 0 }, RightHip = { -20, 0, 6 }, RightKnee = { -46, 0, 0 } }) },
	{ 0.22, SHOULDER, "Snap" },
	{ 0.32, merge(SHOULDER, { Torso = { -34, -26, 16 } }), "Out" },
	{ 0.42, merge(SHOULDER, { Root = { 0, -56, 0, 0, -0.4, 0 }, Torso = { -28, -22, 12 } }) },
	{ 0.62, merge(GUARD, { Root = { 0, -20, 0, 0, -0.16, 0 }, Torso = { -8, -8, 4 }, Neck = { -2, 24, 0 } }) },
	{ 0.82, REST },
})

-- Air kick: tuck both knees, then fire one leg straight out, leaning back
define("AirKick", { startup = 0.1, active = 0.12, recovery = 0.25 }, {
	{ 0.06, {
		Torso = { 14, 0, 0 },
		Neck = { -10, 0, 0 },
		RightHip = { 80, 0, 10 },
		RightKnee = { -112, 0, 0 },
		LeftHip = { 30, 0, -6 },
		LeftKnee = { -80, 0, 0 },
		RightShoulder = { 30, 0, 50 },
		LeftShoulder = { 30, 0, -50 },
		RightElbow = { 40, 0, 0 },
		LeftElbow = { 40, 0, 0 },
	} },
	{ 0.1, {
		Root = { 8, 0, 0 },
		Torso = { 24, 0, 0 },
		Neck = { -22, 0, 0 },
		RightHip = { 96, 0, 0 },
		RightKnee = { -4, 0, 0 },
		LeftHip = { 22, 0, -6 },
		LeftKnee = { -104, 0, 0 },
		RightShoulder = { -22, 0, 40 },
		LeftShoulder = { 62, 0, -28 },
		LeftElbow = { 60, 0, 0 },
		RightElbow = { 20, 0, 0 },
	}, "Snap" },
	{ 0.16, {
		Root = { 10, 0, 0 },
		Torso = { 26, 0, 0 },
		Neck = { -22, 0, 0 },
		RightHip = { 102, 0, 0 },
		LeftHip = { 22, 0, -6 },
		LeftKnee = { -104, 0, 0 },
		RightShoulder = { -22, 0, 40 },
		LeftShoulder = { 62, 0, -28 },
		LeftElbow = { 60, 0, 0 },
	}, "Out" },
	{ 0.22, { Root = { 8, 0, 0 }, Torso = { 22, 0, 0 }, Neck = { -18, 0, 0 }, RightHip = { 92, 0, 0 }, RightKnee = { -14, 0, 0 }, LeftHip = { 24, 0, -6 }, LeftKnee = { -96, 0, 0 }, RightShoulder = { -10, 0, 40 }, LeftShoulder = { 50, 0, -30 } } },
	{ 0.36, { Torso = { 6, 0, 0 }, RightHip = { 40, 0, 0 }, RightKnee = { -60, 0, 0 }, LeftHip = { 30, 0, 0 }, LeftKnee = { -60, 0, 0 }, RightShoulder = { 20, 0, 30 }, LeftShoulder = { 20, 0, -30 } } },
	{ 0.47, REST },
})

-- Slam: both fists raised overhead, knees tucked, then the whole body folds down
-- into the dive and lands in a heavy crouch
define("Slam", { startup = 0.22, active = 0.18, recovery = 0.45 }, {
	{ 0.16, {
		Root = { -8, 0, 0 },
		Torso = { 18, 0, 0 },
		Neck = { -8, 0, 0 },
		RightShoulder = { 170, 0, -14 },
		LeftShoulder = { 170, 0, 14 },
		RightElbow = { 42, 0, 0 },
		LeftElbow = { 42, 0, 0 },
		RightHip = { 52, 0, 4 },
		RightKnee = { -92, 0, 0 },
		LeftHip = { 52, 0, -4 },
		LeftKnee = { -92, 0, 0 },
	} },
	{ 0.22, {
		Root = { 10, 0, 0 },
		Torso = { -40, 0, 0 },
		Neck = { 26, 0, 0 },
		RightShoulder = { 40, 0, -22 },
		LeftShoulder = { 40, 0, 22 },
		RightElbow = { 10, 0, 0 },
		LeftElbow = { 10, 0, 0 },
		RightHip = { 24, 0, 4 },
		RightKnee = { -40, 0, 0 },
		LeftHip = { 24, 0, -4 },
		LeftKnee = { -40, 0, 0 },
	}, "Snap" },
	{ 0.3, { Root = { 10, 0, 0 }, Torso = { -46, 0, 0 }, Neck = { 28, 0, 0 }, RightShoulder = { 30, 0, -22 }, LeftShoulder = { 30, 0, 22 }, RightElbow = { 8, 0, 0 }, LeftElbow = { 8, 0, 0 }, RightHip = { 24, 0, 4 }, RightKnee = { -40, 0, 0 }, LeftHip = { 24, 0, -4 }, LeftKnee = { -40, 0, 0 } }, "Out" },
	{ 0.4, {
		Root = { 0, 0, 0, 0, -0.6, 0 },
		Torso = { -30, 0, 0 },
		Neck = { 20, 0, 0 },
		RightShoulder = { 24, 0, -20 },
		LeftShoulder = { 24, 0, 20 },
		RightHip = { 50, 0, 6 },
		RightKnee = { -76, 0, 0 },
		LeftHip = { 50, 0, -6 },
		LeftKnee = { -76, 0, 0 },
	}, "In" },
	{ 0.62, { Root = { 0, 0, 0, 0, -0.2, 0 }, Torso = { -12, 0, 0 }, Neck = { 6, 0, 0 }, RightShoulder = { 20, 0, -12 }, LeftShoulder = { 20, 0, 12 }, RightHip = { 16, 0, 0 }, LeftHip = { 16, 0, 0 }, RightKnee = { -22, 0, 0 }, LeftKnee = { -22, 0, 0 } } },
	{ 0.85, REST },
})

-- Sweep: drop onto the folded lead leg, plant a hand, and spin a full turn with
-- the rear leg straight along the floor
local SWEEP_LOW = {
	Torso = { -30, 0, -10 },
	Neck = { 20, -10, 8 },
	LeftHip = { 82, 0, -8 },
	LeftKnee = { -130, 0, 0 },
	RightHip = { 18, 0, 62 },
	RightKnee = { -6, 0, 0 },
	RightShoulder = { 24, 0, 44 },
	LeftShoulder = { 20, 0, -30 },
	LeftElbow = { 20, 0, 0 },
}
define("Sweep", { startup = 0.16, active = 0.12, recovery = 0.35 }, {
	{ 0.08, merge(SWEEP_LOW, { Root = { 0, 30, 0, 0, -1.35, 0 } }) },
	{ 0.16, merge(SWEEP_LOW, { Root = { 0, 150, 0, 0, -1.4, 0 } }), "Linear" },
	{ 0.22, merge(SWEEP_LOW, { Root = { 0, 255, 0, 0, -1.4, 0 } }), "Linear" },
	{ 0.28, merge(SWEEP_LOW, { Root = { 0, 360, 0, 0, -1.36, 0 } }), "Out" },
	{ 0.42, {
		Root = { 0, 360, 0, 0, -0.9, 0 },
		Torso = { -16, 0, 0 },
		Neck = { 10, 0, 0 },
		RightHip = { 50, 0, 20 },
		RightKnee = { -90, 0, 0 },
		LeftHip = { 60, 0, -6 },
		LeftKnee = { -100, 0, 0 },
		RightShoulder = { 30, 0, 20 },
		LeftShoulder = { 30, 0, -20 },
	} },
	{ 0.63, { Root = { 0, 360, 0 } } },
})

-- Grappling ---------------------------------------------------------------------------------

-- Grab: arms open, a short step in, both hands shoot out and clamp. A miss
-- over-reaches and stumbles (that's the punish window).
define("Grab", { startup = 0.22, active = 0.1, recovery = 0.55 }, {
	{ 0.14, {
		Root = { 0, 0, 0, 0, -0.26, 0 },
		Torso = { -14, 0, 0 },
		Neck = { 10, 0, 0 },
		RightShoulder = { 42, 0, 30 },
		LeftShoulder = { 42, 0, -30 },
		RightElbow = { 64, 0, 0 },
		LeftElbow = { 64, 0, 0 },
		LeftHip = { 26, 0, -4 },
		LeftKnee = { -36, 0, 0 },
		RightHip = { -10, 0, 4 },
		RightKnee = { -30, 0, 0 },
	} },
	{ 0.22, {
		Root = { 0, 0, 0, 0, -0.32, 0 },
		Torso = { -24, 0, 0 },
		Neck = { 18, 0, 0 },
		RightShoulder = { 92, 0, -12 },
		LeftShoulder = { 92, 0, 12 },
		RightElbow = { 22, 0, 0 },
		LeftElbow = { 22, 0, 0 },
		LeftHip = { 38, 0, -4 },
		LeftKnee = { -30, 0, 0 },
		RightHip = { -24, 0, 4 },
		RightKnee = { -14, 0, 0 },
	}, "Snap" },
	{ 0.32, {
		Root = { 0, 0, 0, 0, -0.32, 0 },
		Torso = { -26, 0, 0 },
		Neck = { 18, 0, 0 },
		RightShoulder = { 88, 0, -26 },
		LeftShoulder = { 88, 0, 26 },
		RightElbow = { 40, 0, 0 },
		LeftElbow = { 40, 0, 0 },
		LeftHip = { 38, 0, -4 },
		LeftKnee = { -30, 0, 0 },
		RightHip = { -24, 0, 4 },
		RightKnee = { -14, 0, 0 },
	}, "Out" },
	{ 0.5, {
		Root = { 0, 8, 0, 0, -0.3, 0 },
		Torso = { -30, 10, 6 },
		Neck = { 20, -8, 0 },
		RightShoulder = { 60, 0, -6 },
		LeftShoulder = { 70, 0, 10 },
		RightElbow = { 30, 0, 0 },
		LeftElbow = { 20, 0, 0 },
		LeftHip = { 44, 0, -4 },
		LeftKnee = { -40, 0, 0 },
		RightHip = { -20, 0, 4 },
		RightKnee = { -20, 0, 0 },
	} },
	{ 0.7, { Root = { 0, 0, 0, 0, -0.12, 0 }, Torso = { -10, 0, 0 }, Neck = { 6, 0, 0 }, RightShoulder = { 30, 0, -10 }, LeftShoulder = { 30, 0, 10 }, RightElbow = { 40, 0, 0 }, LeftElbow = { 40, 0, 0 } } },
	{ 0.87, REST },
})

-- Holding a caught opponent: arms locked around them, weight low, wrestling
local CLINCH = {
	Root = { 0, 0, 0, 0, -0.22, 0 },
	Torso = { -16, 0, 0 },
	Neck = { 8, 0, 0 },
	RightShoulder = { 86, 0, -38 },
	LeftShoulder = { 86, 0, 38 },
	RightElbow = { 84, 0, 0 },
	LeftElbow = { 84, 0, 0 },
	LeftHip = { 24, 0, -4 },
	LeftKnee = { -32, 0, 0 },
	RightHip = { -12, 0, 4 },
	RightKnee = { -26, 0, 0 },
}
define("ClinchHold", { holdAt = 0.5, tremble = 1.6, trembleRamp = 0.3 }, {
	{ 0.1, CLINCH, "Out" },
	{ 0.5, merge(CLINCH, { Root = { 0, 6, 0, 0, -0.26, 0 }, Torso = { -20, 6, 0 } }) },
	{ 0.8, REST },
})

-- Being held: leaning back from the pull, hands pushing at the holder's arms
local CLINCHED = {
	Root = { 0, 0, 0, 0, -0.08, 0 },
	Torso = { 14, 0, 0 },
	Neck = { -14, 0, 0 },
	RightShoulder = { 72, 0, -8 },
	LeftShoulder = { 72, 0, 8 },
	RightElbow = { 74, 0, 0 },
	LeftElbow = { 74, 0, 0 },
	RightKnee = { -18, 0, 0 },
	LeftKnee = { -18, 0, 0 },
}
define("Clinched", { holdAt = 0.5, tremble = 2.5, trembleRamp = 0.2 }, {
	{ 0.08, CLINCHED, "Snap" },
	{ 0.5, merge(CLINCHED, { Torso = { 18, -6, 4 }, Neck = { -18, 4, 0 } }) },
	{ 0.8, REST },
})

-- Throwing forward: load the hips, then a hip toss that whips the arms through
define("ThrowForward", {}, {
	{ 0.08, {
		Root = { 0, -34, 0, 0, -0.42, 0 },
		Torso = { -12, -30, 0 },
		Neck = { -4, 40, 0 },
		RightShoulder = { 60, 0, -30 },
		LeftShoulder = { 70, 0, 40 },
		RightElbow = { 90, 0, 0 },
		LeftElbow = { 80, 0, 0 },
		LeftHip = { 34, 0, -4 },
		LeftKnee = { -48, 0, 0 },
		RightHip = { -12, 0, 4 },
		RightKnee = { -44, 0, 0 },
	} },
	{ 0.18, {
		Root = { 0, 44, 0, 0, -0.3, 0 },
		Torso = { -30, 40, 0 },
		Neck = { -2, -50, 0 },
		RightShoulder = { 104, 0, 10 },
		LeftShoulder = { 56, 0, 44 },
		RightElbow = { 12, 0, 0 },
		LeftElbow = { 30, 0, 0 },
		LeftHip = { 30, 0, -4 },
		LeftKnee = { -30, 0, 0 },
		RightHip = { -24, 0, 4 },
		RightKnee = { -30, 0, 0 },
	}, "Snap" },
	{ 0.3, { Root = { 0, 52, 0, 0, -0.3, 0 }, Torso = { -34, 52, 0 }, Neck = { -2, -58, 0 }, RightShoulder = { 96, 0, 12 }, LeftShoulder = { 50, 0, 44 }, RightElbow = { 14, 0, 0 }, LeftElbow = { 30, 0, 0 }, LeftKnee = { -30, 0, 0 }, RightKnee = { -30, 0, 0 } }, "Out" },
	{ 0.46, { Root = { 0, 14, 0, 0, -0.14, 0 }, Torso = { -10, 14, 0 }, Neck = { 0, -14, 0 }, RightShoulder = { 50, 0, -10 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 40, 0, 10 }, LeftElbow = { 70, 0, 0 } } },
	{ 0.62, REST },
})

-- Throwing backward (the server turns the thrower to face the throw): a deep
-- squat, then a two-handed heave up and over
define("ThrowBack", {}, {
	{ 0.1, {
		Root = { 0, 0, 0, 0, -0.5, 0 },
		Torso = { -28, 0, 0 },
		Neck = { 16, 0, 0 },
		RightShoulder = { 30, 0, -20 },
		LeftShoulder = { 30, 0, 20 },
		RightElbow = { 40, 0, 0 },
		LeftElbow = { 40, 0, 0 },
		RightHip = { 40, 0, 8 },
		LeftHip = { 30, 0, -8 },
		RightKnee = { -56, 0, 0 },
		LeftKnee = { -50, 0, 0 },
	} },
	{ 0.22, { Root = { 0, 0, 0, 0, 0.1, 0 }, Torso = { 16, 0, 0 }, Neck = { -10, 0, 0 }, RightShoulder = { 150, 0, -10 }, LeftShoulder = { 150, 0, 10 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 20, 0, 0 } }, "Snap" },
	{ 0.34, { Root = { 0, 0, 0, 0, -0.1, 0 }, Torso = { -10, 0, 0 }, Neck = { 4, 0, 0 }, RightShoulder = { 120, 0, -10 }, LeftShoulder = { 120, 0, 10 }, RightElbow = { 14, 0, 0 }, LeftElbow = { 14, 0, 0 } }, "Out" },
	{ 0.6, REST },
})

-- Being thrown: limbs flung out, body twisting through the air
define("Thrown", {}, {
	{ 0.06, {
		Root = { -20, 0, 8 },
		Torso = { 30, 0, 10 },
		Neck = { 24, 0, 0 },
		RightShoulder = { 120, 0, 60 },
		LeftShoulder = { 120, 0, -60 },
		RightElbow = { 30, 0, 0 },
		LeftElbow = { 30, 0, 0 },
		RightHip = { 50, 0, 10 },
		LeftHip = { 30, 0, -10 },
		RightKnee = { -50, 0, 0 },
		LeftKnee = { -30, 0, 0 },
	}, "Snap" },
	{ 0.3, { Root = { -40, 0, 14 }, Torso = { 24, 0, 6 }, Neck = { 18, 0, 0 }, RightShoulder = { 140, 0, 40 }, LeftShoulder = { 100, 0, -70 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 40, 0, 0 }, RightHip = { 40, 0, 10 }, LeftHip = { 20, 0, -10 }, RightKnee = { -60, 0, 0 }, LeftKnee = { -30, 0, 0 } }, "Out" },
	{ 0.55, REST },
})

-- A teched throw: both fighters shove each other's arms off and hop back
define("TechBreak", {}, {
	{ 0.06, {
		Root = { 0, 0, 0, 0, -0.1, 0 },
		Torso = { 16, 0, 0 },
		Neck = { 10, 0, 0 },
		RightShoulder = { 92, 0, 40 },
		LeftShoulder = { 92, 0, -40 },
		RightElbow = { 16, 0, 0 },
		LeftElbow = { 16, 0, 0 },
		RightHip = { -18, 0, 4 },
		RightKnee = { -26, 0, 0 },
		LeftKnee = { -16, 0, 0 },
	}, "Snap" },
	{ 0.18, { Root = { 0, 0, 0, 0, -0.14, 0 }, Torso = { 12, 0, 0 }, Neck = { 6, 0, 0 }, RightShoulder = { 60, 0, 30 }, LeftShoulder = { 60, 0, -30 }, RightElbow = { 60, 0, 0 }, LeftElbow = { 60, 0, 0 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -18, 0, 0 } }, "Out" },
	{ 0.36, GUARD },
	{ 0.5, REST },
})

-- Throwing a carried prop: arch back with it overhead, then whip it forward
define("PropThrow", { startup = 0.08, active = 0, recovery = 0.3 }, {
	{ 0.05, { Root = { 0, 0, 0, 0, -0.12, 0 }, Torso = { 14, 0, 0 }, Neck = { -10, 0, 0 }, RightShoulder = { 176, 0, 10 }, LeftShoulder = { 176, 0, -10 }, RightElbow = { 60, 0, 0 }, LeftElbow = { 60, 0, 0 } } },
	{ 0.08, { Root = { 0, 0, 0, 0, -0.2, 0 }, Torso = { -22, 0, 0 }, Neck = { 10, 0, 0 }, RightShoulder = { 104, 0, -6 }, LeftShoulder = { 104, 0, 6 }, RightElbow = { 6, 0, 0 }, LeftElbow = { 6, 0, 0 }, LeftHip = { 24, 0, 0 }, LeftKnee = { -30, 0, 0 } }, "Snap" },
	{ 0.18, { Root = { 0, 0, 0, 0, -0.2, 0 }, Torso = { -28, 0, 0 }, Neck = { 14, 0, 0 }, RightShoulder = { 80, 0, -6 }, LeftShoulder = { 80, 0, 6 }, RightElbow = { 10, 0, 0 }, LeftElbow = { 10, 0, 0 }, LeftHip = { 24, 0, 0 }, LeftKnee = { -30, 0, 0 } }, "Out" },
	{ 0.38, REST },
})

-- Hit reactions ---------------------------------------------------------------------------

-- Hit from the front: head snaps back first, the chest follows, arms fly up
define("FlinchFront", {}, {
	{ 0.05, {
		Root = { 8, 0, 0, 0, -0.08, 0 },
		Torso = { 18, 0, 0 },
		Neck = { 24, 0, 0 },
		RightShoulder = { 32, 0, 26 },
		LeftShoulder = { 32, 0, -26 },
		RightElbow = { 54, 0, 0 },
		LeftElbow = { 54, 0, 0 },
		RightHip = { -8, 0, 0 },
		LeftHip = { 10, 0, 0 },
		RightKnee = { -14, 0, 0 },
		LeftKnee = { -10, 0, 0 },
	}, "Snap" },
	{ 0.12, { Root = { 8, 0, 0, 0, -0.08, 0 }, Torso = { 22, 0, 0 }, Neck = { 28, 0, 0 }, RightShoulder = { 30, 0, 24 }, LeftShoulder = { 30, 0, -24 }, RightElbow = { 50, 0, 0 }, LeftElbow = { 50, 0, 0 }, RightKnee = { -14, 0, 0 }, LeftKnee = { -10, 0, 0 } }, "Out" },
	{ 0.3, { Root = { 2, 0, 0, 0, -0.04, 0 }, Torso = { 8, 0, 0 }, Neck = { 6, 0, 0 }, RightShoulder = { 20, 0, 12 }, LeftShoulder = { 20, 0, -12 }, RightElbow = { 40, 0, 0 }, LeftElbow = { 40, 0, 0 } } },
	{ 0.5, REST },
})

-- Hit from behind: folds forward, arms thrown back
define("FlinchBack", {}, {
	{ 0.05, { Root = { -8, 0, 0, 0, -0.1, 0 }, Torso = { -24, 0, 0 }, Neck = { -18, 0, 0 }, RightShoulder = { -24, 0, 24 }, LeftShoulder = { -24, 0, -24 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, LeftHip = { 20, 0, 0 }, LeftKnee = { -24, 0, 0 } }, "Snap" },
	{ 0.12, { Root = { -8, 0, 0, 0, -0.1, 0 }, Torso = { -28, 0, 0 }, Neck = { -20, 0, 0 }, RightShoulder = { -26, 0, 24 }, LeftShoulder = { -26, 0, -24 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, LeftHip = { 20, 0, 0 }, LeftKnee = { -24, 0, 0 } }, "Out" },
	{ 0.3, { Torso = { -8, 0, 0 }, Neck = { -4, 0, 0 }, RightShoulder = { -6, 0, 10 }, LeftShoulder = { -6, 0, -10 } } },
	{ 0.5, REST },
})

-- Hit on the right side (pushed left): bends and twists away; mirrored for the left
define("FlinchSide", {}, {
	{ 0.05, { Root = { 0, 10, 6, 0, -0.08, 0 }, Torso = { 6, 18, 18 }, Neck = { 8, 10, 16 }, RightShoulder = { 36, 0, 44 }, RightElbow = { 50, 0, 0 }, LeftShoulder = { 10, 0, -20 }, LeftHip = { 0, 0, -10 }, RightHip = { 0, 0, 8 }, RightKnee = { -12, 0, 0 } }, "Snap" },
	{ 0.12, { Root = { 0, 12, 6, 0, -0.08, 0 }, Torso = { 6, 22, 22 }, Neck = { 8, 12, 18 }, RightShoulder = { 36, 0, 44 }, RightElbow = { 50, 0, 0 }, LeftShoulder = { 10, 0, -20 }, LeftHip = { 0, 0, -10 }, RightHip = { 0, 0, 8 }, RightKnee = { -12, 0, 0 } }, "Out" },
	{ 0.3, { Torso = { 2, 8, 6 }, Neck = { 2, 4, 4 }, RightShoulder = { 16, 0, 18 }, RightElbow = { 24, 0, 0 } } },
	{ 0.5, REST },
})

-- A heavy hit: knocked back a step, then folds over the blow
define("HitHeavy", {}, {
	{ 0.05, {
		Root = { 12, 0, 0, 0, -0.12, 0 },
		Torso = { 26, 6, 0 },
		Neck = { 30, 0, 0 },
		RightShoulder = { 50, 0, 50 },
		LeftShoulder = { 50, 0, -50 },
		RightElbow = { 40, 0, 0 },
		LeftElbow = { 40, 0, 0 },
		RightHip = { -24, 0, 6 },
		RightKnee = { -34, 0, 0 },
		LeftHip = { 16, 0, -4 },
		LeftKnee = { -14, 0, 0 },
	}, "Snap" },
	{ 0.14, { Root = { 12, 0, 0, 0, -0.12, 0 }, Torso = { 30, 8, 4 }, Neck = { 34, 0, 6 }, RightShoulder = { 54, 0, 54 }, LeftShoulder = { 54, 0, -54 }, RightElbow = { 40, 0, 0 }, LeftElbow = { 40, 0, 0 }, RightHip = { -24, 0, 6 }, RightKnee = { -34, 0, 0 } }, "Out" },
	{ 0.4, { Root = { 4, 0, 0, 0, -0.2, 0 }, Torso = { -12, 0, 0 }, Neck = { -6, 0, 0 }, RightShoulder = { 20, 0, 20 }, LeftShoulder = { 20, 0, -20 }, RightHip = { 12, 0, 0 }, LeftHip = { 16, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -24, 0, 0 } } },
	{ 0.7, { Torso = { -4, 0, 0 }, RightKnee = { -12, 0, 0 }, LeftKnee = { -12, 0, 0 } } },
	{ 0.9, REST },
})

-- Guard broken: arms blown apart, a stumble back, then a dazed sway
define("GuardBreak", {}, {
	{ 0.07, {
		Root = { 6, 0, 0, 0, -0.1, 0 },
		Torso = { 24, 0, 0 },
		Neck = { 22, 0, 0 },
		RightShoulder = { 64, 0, 72 },
		LeftShoulder = { 64, 0, -72 },
		RightElbow = { 30, 0, 0 },
		LeftElbow = { 30, 0, 0 },
		RightHip = { -22, 0, 6 },
		RightKnee = { -32, 0, 0 },
		LeftKnee = { -12, 0, 0 },
	}, "Snap" },
	{ 0.16, { Root = { 6, 0, 0, 0, -0.1, 0 }, Torso = { 28, 0, 0 }, Neck = { 24, 0, 0 }, RightShoulder = { 70, 0, 80 }, LeftShoulder = { 70, 0, -80 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, RightHip = { -22, 0, 6 }, RightKnee = { -32, 0, 0 } }, "Out" },
	{ 0.4, { Root = { 2, 6, 0, 0, -0.2, 0 }, Torso = { 12, 10, 8 }, Neck = { 10, 0, 12 }, RightShoulder = { 26, 0, 30 }, LeftShoulder = { 20, 0, -26 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 24, 0, 0 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -24, 0, 0 } } },
	{ 0.7, { Root = { 2, -6, 0, 0, -0.2, 0 }, Torso = { 14, -10, -8 }, Neck = { 14, 0, -12 }, RightShoulder = { 22, 0, 26 }, LeftShoulder = { 26, 0, -30 }, RightElbow = { 26, 0, 0 }, LeftElbow = { 30, 0, 0 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -24, 0, 0 } } },
	{ 1.0, { Root = { 0, 4, 0, 0, -0.14, 0 }, Torso = { 10, 8, 6 }, Neck = { 8, 0, 8 }, RightShoulder = { 18, 0, 20 }, LeftShoulder = { 18, 0, -20 }, RightKnee = { -16, 0, 0 }, LeftKnee = { -16, 0, 0 } } },
	{ 1.25, { Torso = { 4, 0, 0 }, Neck = { 2, 0, 0 }, RightKnee = { -10, 0, 0 }, LeftKnee = { -10, 0, 0 } } },
	{ 1.4, REST },
})

-- Parry (the defender): a sharp outward swat with the rear forearm
define("ParryDeflect", {}, {
	{ 0.05, merge(GUARD, { Root = { 0, -14, 0, 0, -0.14, 0 }, Torso = { -6, -20, 0 }, Neck = { -4, 20, 0 }, RightShoulder = { 104, 0, 44 }, RightElbow = { 88, 0, 0 }, LeftShoulder = { 70, 0, 30 }, LeftElbow = { 112, 0, 0 } }), "Snap" },
	{ 0.14, merge(GUARD, { Root = { 0, -16, 0, 0, -0.14, 0 }, Torso = { -6, -24, 0 }, Neck = { -4, 22, 0 }, RightShoulder = { 110, 0, 56 }, RightElbow = { 84, 0, 0 }, LeftShoulder = { 70, 0, 30 }, LeftElbow = { 112, 0, 0 } }), "Out" },
	{ 0.3, GUARD },
	{ 0.45, REST },
})

-- Parried (the attacker): the striking arm knocked high and wide, wide open
define("ParriedRecoil", {}, {
	{ 0.06, { Root = { 6, 16, 0, 0, -0.08, 0 }, Torso = { 20, 26, 0 }, Neck = { 18, -10, 0 }, RightShoulder = { 150, 0, 52 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 20, 0, -30 }, RightHip = { -16, 0, 4 }, RightKnee = { -26, 0, 0 } }, "Snap" },
	{ 0.18, { Root = { 6, 18, 0, 0, -0.08, 0 }, Torso = { 24, 30, 4 }, Neck = { 20, -12, 0 }, RightShoulder = { 156, 0, 58 }, RightElbow = { 26, 0, 0 }, LeftShoulder = { 20, 0, -30 }, RightHip = { -16, 0, 4 }, RightKnee = { -26, 0, 0 } }, "Out" },
	{ 0.5, { Root = { 0, 6, 0, 0, -0.1, 0 }, Torso = { 10, 10, 4 }, Neck = { 8, 0, 6 }, RightShoulder = { 50, 0, 30 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 16, 0, -16 } } },
	{ 0.8, { Torso = { 4, 0, 0 } } },
	{ 1.0, REST },
})

-- A blocked hit: the guard compresses and the body gives a little, then resets
define("BlockImpact", {}, {
	{ 0.04, merge(BLOCK, { Torso = { -2, 0, 0 }, Neck = { -2, 0, 0 }, Root = { 4, 0, 0, 0, -0.2, 0 }, RightElbow = { 124, 0, 0 }, LeftElbow = { 120, 0, 0 }, RightKnee = { -22, 0, 0 }, LeftKnee = { -26, 0, 0 } }), "Snap" },
	{ 0.16, merge(BLOCK, { Torso = { -12, 0, 0 } }), "Out" },
	{ 0.26, BLOCK },
})

-- Out of stamina: bent over, hands on knees, breathing hard
local WINDED = {
	Root = { 0, 0, 0, 0, -0.34, 0 },
	Torso = { -38, 0, 0 },
	Neck = { 30, 0, 0 },
	RightShoulder = { 48, 0, -10 },
	LeftShoulder = { 48, 0, 10 },
	RightElbow = { 14, 0, 0 },
	LeftElbow = { 14, 0, 0 },
	RightHip = { 30, 0, 6 },
	LeftHip = { 30, 0, -6 },
	RightKnee = { -34, 0, 0 },
	LeftKnee = { -34, 0, 0 },
}
define("Winded", {}, {
	{ 0.25, WINDED },
	{ 0.55, merge(WINDED, { Root = { 0, 0, 0, 0, -0.3, 0 }, Torso = { -32, 0, 0 }, Neck = { 26, 0, 0 } }) },
	{ 0.85, merge(WINDED, { Root = { 0, 0, 0, 0, -0.36, 0 }, Torso = { -40, 0, 0 } }) },
	{ 1.15, merge(WINDED, { Torso = { -33, 0, 0 }, Neck = { 27, 0, 0 } }) },
	{ 1.6, REST },
})

-- Knockdowns: fall, lie still (paused until the get-up), then get up.
-- Knocked back: tips over backwards, hits the floor, a small bounce
define("KnockdownBack", { holdAt = 0.62 }, {
	{ 0.08, { Root = { 14, 0, 0, 0, -0.1, 0 }, Torso = { 22, 0, 0 }, Neck = { 22, 0, 0 }, RightShoulder = { 72, 0, 40 }, LeftShoulder = { 72, 0, -40 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, RightHip = { 24, 0, 4 }, LeftHip = { 10, 0, -4 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -14, 0, 0 } }, "Snap" },
	{ 0.28, { Root = { 68, 0, 6, 0, -1.05, 0 }, Torso = { 10, 0, 0 }, Neck = { -14, 0, 0 }, RightShoulder = { 120, 0, 60 }, LeftShoulder = { 120, 0, -60 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 20, 0, 0 }, RightHip = { 30, 0, 6 }, LeftHip = { 20, 0, -6 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -24, 0, 0 } }, "In" },
	{ 0.36, { Root = { 94, 0, 2, 0, -1.56, 0 }, Torso = { -6, 0, 0 }, Neck = { -22, 0, 0 }, RightShoulder = { 150, 0, 80 }, LeftShoulder = { 150, 0, -80 }, RightElbow = { 10, 0, 0 }, LeftElbow = { 10, 0, 0 }, RightHip = { 14, 0, 8 }, LeftHip = { 8, 0, -8 }, RightKnee = { -10, 0, 0 }, LeftKnee = { -8, 0, 0 } }, "In" },
	{ 0.48, { Root = { 86, 0, 0, 0, -1.44, 0 }, Torso = { -4, 0, 0 }, Neck = { -6, 0, 0 }, RightShoulder = { 146, 0, 78 }, LeftShoulder = { 140, 0, -76 }, RightElbow = { 16, 0, 0 }, LeftElbow = { 20, 0, 0 }, RightHip = { 24, 0, 8 }, LeftHip = { 16, 0, -8 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -18, 0, 0 } }, "Out" },
	{ 0.62, { Root = { 90, 0, 3, 0, -1.5, 0 }, Torso = { -2, 0, 0 }, Neck = { -4, 0, 6 }, RightShoulder = { 140, 0, 74 }, LeftShoulder = { 130, 0, -70 }, RightElbow = { 24, 0, 0 }, LeftElbow = { 30, 0, 0 }, RightHip = { 16, 0, 8 }, LeftHip = { 30, 0, -6 }, RightKnee = { -20, 0, 0 }, LeftKnee = { -40, 0, 0 } } },
	-- Getting up: sit up with the knees drawn in, hands pushing the floor, rise
	{ 0.78, { Root = { 60, 0, 0, 0, -1.18, 0 }, Torso = { -34, 0, 0 }, Neck = { 12, 0, 0 }, RightShoulder = { -30, 0, 24 }, LeftShoulder = { -30, 0, -24 }, RightElbow = { 10, 0, 0 }, LeftElbow = { 10, 0, 0 }, RightHip = { 60, 0, 8 }, LeftHip = { 60, 0, -8 }, RightKnee = { -100, 0, 0 }, LeftKnee = { -100, 0, 0 } } },
	{ 0.95, { Root = { 22, 0, 0, 0, -0.72, 0 }, Torso = { -28, 0, 0 }, Neck = { 18, 0, 0 }, RightShoulder = { 20, 0, 20 }, LeftShoulder = { 20, 0, -20 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, RightHip = { 68, 0, 6 }, LeftHip = { 68, 0, -6 }, RightKnee = { -110, 0, 0 }, LeftKnee = { -110, 0, 0 } } },
	{ 1.12, { Root = { 0, 0, 0, 0, -0.2, 0 }, Torso = { -8, 0, 0 }, Neck = { 4, 0, 0 }, RightShoulder = { 30, 0, 14 }, LeftShoulder = { 30, 0, -14 }, RightElbow = { 40, 0, 0 }, LeftElbow = { 40, 0, 0 }, RightHip = { 18, 0, 0 }, LeftHip = { 18, 0, 0 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -24, 0, 0 } } },
	{ 1.26, REST },
})

-- Knocked forward: pitches onto the hands and chest, then pushes up to the knees
define("KnockdownFront", { holdAt = 0.62 }, {
	{ 0.08, { Root = { -12, 0, 0, 0, -0.1, 0 }, Torso = { -24, 0, 0 }, Neck = { -18, 0, 0 }, RightShoulder = { -30, 0, 20 }, LeftShoulder = { -30, 0, -20 }, LeftHip = { 20, 0, 0 }, LeftKnee = { -30, 0, 0 } }, "Snap" },
	{ 0.28, { Root = { -66, 0, 0, 0, -1.0, 0 }, Torso = { -6, 0, 0 }, Neck = { 20, 0, 0 }, RightShoulder = { 100, 0, 30 }, LeftShoulder = { 100, 0, -30 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, LeftHip = { 10, 0, 0 }, LeftKnee = { -20, 0, 0 } }, "In" },
	{ 0.36, { Root = { -90, 0, 0, 0, -1.5, 0 }, Neck = { 30, 0, 10 }, RightShoulder = { 150, 0, 30 }, LeftShoulder = { 150, 0, -30 }, RightElbow = { 60, 0, 0 }, LeftElbow = { 60, 0, 0 }, RightHip = { -6, 0, 4 }, LeftHip = { -6, 0, -4 } }, "In" },
	{ 0.48, { Root = { -84, 0, 0, 0, -1.42, 0 }, Neck = { 28, 0, 14 }, RightShoulder = { 154, 0, 34 }, LeftShoulder = { 146, 0, -34 }, RightElbow = { 70, 0, 0 }, LeftElbow = { 70, 0, 0 }, RightHip = { -4, 0, 4 }, LeftHip = { -4, 0, -4 } }, "Out" },
	{ 0.62, { Root = { -90, 0, 2, 0, -1.5, 0 }, Neck = { 26, 0, 20 }, RightShoulder = { 160, 0, 40 }, LeftShoulder = { 140, 0, -40 }, RightElbow = { 80, 0, 0 }, LeftElbow = { 80, 0, 0 }, RightKnee = { -20, 0, 0 } } },
	{ 0.8, { Root = { -56, 0, 0, 0, -1.2, 0 }, Torso = { -10, 0, 0 }, Neck = { 36, 0, 0 }, RightShoulder = { 60, 0, 10 }, LeftShoulder = { 60, 0, -10 }, RightHip = { 70, 0, 0 }, LeftHip = { 50, 0, 0 }, RightKnee = { -100, 0, 0 }, LeftKnee = { -90, 0, 0 } } },
	{ 0.98, { Root = { -20, 0, 0, 0, -0.7, 0 }, Torso = { -20, 0, 0 }, Neck = { 30, 0, 0 }, RightShoulder = { 20, 0, 10 }, LeftShoulder = { 20, 0, -10 }, RightHip = { 70, 0, 6 }, LeftHip = { 36, 0, -6 }, RightKnee = { -110, 0, 0 }, LeftKnee = { -70, 0, 0 } } },
	{ 1.14, { Root = { 0, 0, 0, 0, -0.2, 0 }, Torso = { -8, 0, 0 }, Neck = { 4, 0, 0 }, RightShoulder = { 30, 0, 14 }, LeftShoulder = { 30, 0, -14 }, RightElbow = { 40, 0, 0 }, LeftElbow = { 40, 0, 0 }, RightHip = { 18, 0, 0 }, LeftHip = { 18, 0, 0 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -24, 0, 0 } } },
	{ 1.28, REST },
})

-- Tech rolls: a tight tuck and a full roll, landing in a crouch
local TUCK = {
	Torso = { -30, 0, 0 },
	Neck = { -26, 0, 0 },
	RightShoulder = { 60, 0, 20 },
	LeftShoulder = { 60, 0, -20 },
	RightElbow = { 100, 0, 0 },
	LeftElbow = { 100, 0, 0 },
	RightHip = { 120, 0, 0 },
	LeftHip = { 120, 0, 0 },
	RightKnee = { -140, 0, 0 },
	LeftKnee = { -140, 0, 0 },
}
local ROLL_LAND = {
	Torso = { -20, 0, 0 },
	Neck = { 6, 0, 0 },
	RightShoulder = { 40, 0, 30 },
	LeftShoulder = { 40, 0, -30 },
	RightElbow = { 50, 0, 0 },
	LeftElbow = { 50, 0, 0 },
	RightHip = { 64, 0, 8 },
	LeftHip = { 50, 0, -8 },
	RightKnee = { -96, 0, 0 },
	LeftKnee = { -80, 0, 0 },
}
local ROLL_RISE = merge(GUARD, { Torso = { -8, 0, 0 }, Neck = { 2, 0, 0 }, RightHip = { 16, 0, 0 }, LeftHip = { 16, 0, 0 }, RightKnee = { -22, 0, 0 }, LeftKnee = { -22, 0, 0 } })
-- Backward roll (from lying on the back), pitch keeps turning through a full circle
define("TechRollBack", {}, {
	{ 0.05, merge(TUCK, { Root = { 130, 0, 0, 0, -1.3, 0 } }) },
	{ 0.12, merge(TUCK, { Root = { 215, 0, 0, 0, -1.2, 0 } }), "Linear" },
	{ 0.19, merge(TUCK, { Root = { 295, 0, 0, 0, -0.9, 0 } }), "Linear" },
	{ 0.26, merge(ROLL_LAND, { Root = { 360, 0, 0, 0, -0.55, 0 } }), "Out" },
	{ 0.4, merge(ROLL_RISE, { Root = { 360, -12, 0, 0, -0.16, 0 } }) },
	{ 0.52, { Root = { 360, 0, 0 } } },
})
-- Forward roll (from lying face down)
define("TechRollForward", {}, {
	{ 0.05, merge(TUCK, { Root = { -130, 0, 0, 0, -1.3, 0 } }) },
	{ 0.12, merge(TUCK, { Root = { -215, 0, 0, 0, -1.2, 0 } }), "Linear" },
	{ 0.19, merge(TUCK, { Root = { -295, 0, 0, 0, -0.9, 0 } }), "Linear" },
	{ 0.26, merge(ROLL_LAND, { Root = { -360, 0, 0, 0, -0.55, 0 } }), "Out" },
	{ 0.4, merge(ROLL_RISE, { Root = { -360, -12, 0, 0, -0.16, 0 } }) },
	{ 0.52, { Root = { -360, 0, 0 } } },
})
-- Kip-up: from the back, legs swing up and over and the fighter springs to the feet
define("TechKipUp", {}, {
	{ 0.06, { Root = { 120, 0, 0, 0, -1.4, 0 }, Torso = { -10, 0, 0 }, RightShoulder = { 170, 0, 20 }, LeftShoulder = { 170, 0, -20 }, RightElbow = { 120, 0, 0 }, LeftElbow = { 120, 0, 0 }, RightHip = { 120, 0, 0 }, LeftHip = { 120, 0, 0 }, RightKnee = { -60, 0, 0 }, LeftKnee = { -60, 0, 0 } } },
	{ 0.16, { Root = { 30, 0, 0, 0, -0.3, 0 }, Torso = { -10, 0, 0 }, RightShoulder = { 80, 0, 40 }, LeftShoulder = { 80, 0, -40 }, RightElbow = { 40, 0, 0 }, LeftElbow = { 40, 0, 0 }, RightHip = { 60, 0, 0 }, LeftHip = { 60, 0, 0 }, RightKnee = { -90, 0, 0 }, LeftKnee = { -90, 0, 0 } }, "Snap" },
	{ 0.26, merge(ROLL_LAND, { Root = { 0, 0, 0, 0, -0.4, 0 } }), "Out" },
	{ 0.4, merge(ROLL_RISE, { Root = { 0, -12, 0, 0, -0.14, 0 } }) },
	{ 0.52, REST },
})
-- Side roll: a log roll along the floor toward the body's left (mirrored for the right)
define("TechRollSide", {}, {
	{ 0.06, { Root = { 90, 70, 0, 0, -1.45, 0 }, RightShoulder = { 40, 0, -10 }, LeftShoulder = { 40, 0, 10 }, RightElbow = { 110, 0, 0 }, LeftElbow = { 110, 0, 0 }, RightHip = { 20, 0, 0 }, LeftHip = { 20, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -30, 0, 0 } } },
	{ 0.13, { Root = { 90, 180, 0, 0, -1.45, 0 }, RightShoulder = { 40, 0, -10 }, LeftShoulder = { 40, 0, 10 }, RightElbow = { 110, 0, 0 }, LeftElbow = { 110, 0, 0 }, RightHip = { 20, 0, 0 }, LeftHip = { 20, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -30, 0, 0 } }, "Linear" },
	{ 0.2, { Root = { 84, 290, 0, 0, -1.3, 0 }, RightShoulder = { 40, 0, -10 }, LeftShoulder = { 40, 0, 10 }, RightElbow = { 110, 0, 0 }, LeftElbow = { 110, 0, 0 }, RightHip = { 40, 0, 0 }, LeftHip = { 40, 0, 0 }, RightKnee = { -60, 0, 0 }, LeftKnee = { -60, 0, 0 } }, "Linear" },
	{ 0.28, merge(ROLL_LAND, { Root = { 30, 360, 0, 0, -0.6, 0 } }), "Out" },
	{ 0.42, merge(ROLL_RISE, { Root = { 0, 348, 0, 0, -0.15, 0 } }) },
	{ 0.52, { Root = { 0, 360, 0 } } },
})

-- Breakfall: a tucked backflip out of a juggle, landing on both feet
define("Breakfall", {}, {
	{ 0.05, merge(TUCK, { Root = { 70, 0, 0, 0, 0.1, 0 }, Torso = { -20, 0, 0 } }) },
	{ 0.12, merge(TUCK, { Root = { 180, 0, 0, 0, 0.15, 0 } }), "Linear" },
	{ 0.2, merge(TUCK, { Root = { 290, 0, 0, 0, 0.05, 0 } }), "Linear" },
	{ 0.28, { Root = { 360, 0, 0, 0, -0.3, 0 }, Torso = { -14, 0, 0 }, Neck = { 6, 0, 0 }, RightShoulder = { 60, 0, 60 }, LeftShoulder = { 60, 0, -60 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 20, 0, 0 }, RightHip = { 40, 0, 8 }, LeftHip = { 40, 0, -8 }, RightKnee = { -60, 0, 0 }, LeftKnee = { -60, 0, 0 } }, "Out" },
	{ 0.46, merge(ROLL_RISE, { Root = { 360, -12, 0, 0, -0.1, 0 } }) },
	{ 0.56, { Root = { 360, 0, 0 } } },
})

-- Launched: arched back, limbs trailing as the body rises
define("Launched", {}, {
	{ 0.06, { Root = { -10, 0, 0 }, Torso = { 30, 0, 0 }, Neck = { 26, 0, 0 }, RightShoulder = { 140, 0, 50 }, LeftShoulder = { 140, 0, -50 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 20, 0, 0 }, RightHip = { 30, 0, 8 }, LeftHip = { 14, 0, -8 }, RightKnee = { -50, 0, 0 }, LeftKnee = { -30, 0, 0 } }, "Snap" },
	{ 0.3, { Root = { -26, 0, 6 }, Torso = { 26, 0, 4 }, Neck = { 18, 0, 0 }, RightShoulder = { 120, 0, 70 }, LeftShoulder = { 110, 0, -64 }, RightElbow = { 24, 0, 0 }, LeftElbow = { 30, 0, 0 }, RightHip = { 40, 0, 10 }, LeftHip = { 24, 0, -8 }, RightKnee = { -60, 0, 0 }, LeftKnee = { -46, 0, 0 } }, "Out" },
	{ 0.6, { Root = { -12, 0, 0 }, Torso = { 14, 0, 0 }, Neck = { 8, 0, 0 }, RightShoulder = { 60, 0, 50 }, LeftShoulder = { 60, 0, -50 }, RightHip = { 30, 0, 0 }, LeftHip = { 30, 0, 0 }, RightKnee = { -50, 0, 0 }, LeftKnee = { -50, 0, 0 } } },
	{ 0.9, REST },
})

-- Wall splat: back flat against the wall, arms splayed, then a slump forward
define("WallSplat", {}, {
	{ 0.05, { Root = { -6, 0, 0, 0, 0.1, 0 }, Torso = { 18, 0, 0 }, Neck = { 30, 0, 0 }, RightShoulder = { 86, 0, 90 }, LeftShoulder = { 86, 0, -90 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, RightHip = { 4, 0, 14 }, LeftHip = { 4, 0, -14 } }, "Snap" },
	{ 0.36, { Root = { -6, 0, 0, 0, -0.24, 0 }, Torso = { 14, 0, 0 }, Neck = { 24, 0, 0 }, RightShoulder = { 80, 0, 84 }, LeftShoulder = { 80, 0, -84 }, RightElbow = { 34, 0, 0 }, LeftElbow = { 34, 0, 0 }, RightHip = { 10, 0, 14 }, LeftHip = { 10, 0, -14 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -20, 0, 0 } } },
	{ 0.6, { Root = { 0, 0, 0, 0, -0.3, 0 }, Torso = { -22, 0, 0 }, Neck = { -16, 0, 0 }, RightShoulder = { 24, 0, 26 }, LeftShoulder = { 24, 0, -26 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 20, 0, 0 }, RightHip = { 24, 0, 0 }, LeftHip = { 24, 0, 0 }, RightKnee = { -36, 0, 0 }, LeftKnee = { -36, 0, 0 } } },
	{ 0.8, REST },
})

-- Clash: both strikes bounce off each other; arms jolt back, a half-step back
define("ClashRecoil", {}, {
	{ 0.05, { Root = { 6, 0, 0, 0, -0.12, 0 }, Torso = { 18, -8, 0 }, Neck = { 14, 0, 0 }, RightShoulder = { 128, 0, 30 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 40, 0, -20 }, LeftElbow = { 80, 0, 0 }, RightHip = { -16, 0, 4 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -14, 0, 0 } }, "Snap" },
	{ 0.14, { Root = { 6, 0, 0, 0, -0.12, 0 }, Torso = { 22, -10, 0 }, Neck = { 16, 0, 0 }, RightShoulder = { 132, 0, 34 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 40, 0, -20 }, LeftElbow = { 80, 0, 0 }, RightHip = { -16, 0, 4 }, RightKnee = { -24, 0, 0 } }, "Out" },
	{ 0.3, GUARD },
	{ 0.45, REST },
})

-- Feint: the heavy's load snaps back up into a tall guard with a little dip
define("Feint", {}, {
	{ 0.07, { Root = { 0, -6, 0, 0, -0.06, 0 }, Torso = { 6, -4, 0 }, Neck = { -4, 10, 0 }, RightShoulder = { 50, 0, -26 }, RightElbow = { 118, 0, 0 }, LeftShoulder = { 64, 0, 22 }, LeftElbow = { 102, 0, 0 }, LeftHip = { 14, 0, -4 }, LeftKnee = { -18, 0, 0 }, RightHip = { -8, 0, 4 }, RightKnee = { -14, 0, 0 } }, "Snap" },
	{ 0.14, merge(GUARD, { Root = { 0, -10, 0, 0, -0.18, 0 } }), "Out" },
	{ 0.25, GUARD },
	{ 0.38, REST },
})

-- Movement ------------------------------------------------------------------------------

-- Sidestep toward the body's left (mirrored for the right): low, leaning into it
define("DodgeSide", {}, {
	{ 0.05, { Root = { 0, 0, 12, 0, -0.28, 0 }, Torso = { -8, 0, 8 }, Neck = { -4, 0, -10 }, RightShoulder = { 60, 0, -20 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 64, 0, 24 }, LeftElbow = { 104, 0, 0 }, LeftHip = { 10, 0, -26 }, LeftKnee = { -20, 0, 0 }, RightHip = { 6, 0, 10 }, RightKnee = { -34, 0, 0 } }, "Snap" },
	{ 0.16, { Root = { 0, 0, 8, 0, -0.24, 0 }, Torso = { -8, 0, 6 }, Neck = { -4, 0, -8 }, RightShoulder = { 60, 0, -20 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 64, 0, 24 }, LeftElbow = { 104, 0, 0 }, LeftHip = { 8, 0, -16 }, LeftKnee = { -24, 0, 0 }, RightHip = { 6, 0, 8 }, RightKnee = { -30, 0, 0 } }, "Out" },
	{ 0.28, GUARD },
	{ 0.38, REST },
})
-- Backstep: a hop back with the legs tucked and the guard up
define("DodgeBack", {}, {
	{ 0.05, { Root = { -8, 0, 0, 0, -0.18, 0 }, Torso = { -10, 0, 0 }, Neck = { 6, 0, 0 }, RightShoulder = { 62, 0, -22 }, RightElbow = { 112, 0, 0 }, LeftShoulder = { 66, 0, 22 }, LeftElbow = { 106, 0, 0 }, RightHip = { 34, 0, 4 }, LeftHip = { 44, 0, -4 }, RightKnee = { -50, 0, 0 }, LeftKnee = { -56, 0, 0 } }, "Snap" },
	{ 0.16, { Root = { -4, 0, 0, 0, -0.22, 0 }, Torso = { -8, 0, 0 }, Neck = { 4, 0, 0 }, RightShoulder = { 62, 0, -22 }, RightElbow = { 112, 0, 0 }, LeftShoulder = { 66, 0, 22 }, LeftElbow = { 106, 0, 0 }, RightHip = { 20, 0, 4 }, LeftHip = { 26, 0, -4 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -34, 0, 0 } }, "Out" },
	{ 0.28, GUARD },
	{ 0.38, REST },
})
-- Forward dash: chest low over the lead knee, arms swept back
define("DodgeForward", {}, {
	{ 0.05, { Root = { 0, 0, 0, 0, -0.32, 0 }, Torso = { -30, 0, 0 }, Neck = { 24, 0, 0 }, RightShoulder = { -40, 0, 20 }, LeftShoulder = { -40, 0, -20 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, LeftHip = { 40, 0, 0 }, LeftKnee = { -50, 0, 0 }, RightHip = { -24, 0, 0 }, RightKnee = { -30, 0, 0 } }, "Snap" },
	{ 0.16, { Root = { 0, 0, 0, 0, -0.32, 0 }, Torso = { -34, 0, 0 }, Neck = { 26, 0, 0 }, RightShoulder = { -44, 0, 20 }, LeftShoulder = { -44, 0, -20 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, LeftHip = { 40, 0, 0 }, LeftKnee = { -50, 0, 0 }, RightHip = { -24, 0, 0 }, RightKnee = { -30, 0, 0 } }, "Out" },
	{ 0.3, merge(GUARD, { Root = { 0, -8, 0, 0, -0.14, 0 }, Torso = { -10, 0, 0 }, Neck = { 6, 8, 0 } }) },
	{ 0.4, REST },
})

-- Taunts (Combat.Taunt.Duration long) --------------------------------------------------

-- "Come on": lead hand out, palm up, fingers curling twice, chin up
define("TauntBeckon", {}, {
	{ 0.2, merge(GUARD, { Root = { 0, -14, 0, 0, -0.08, 0 }, Neck = { 10, 16, 8 } }) },
	{ 0.45, merge(GUARD, { LeftShoulder = { 84, 10, 6 }, LeftElbow = { 20, 0, 0 }, Neck = { 14, 16, 10 } }), "Back" },
	{ 0.62, merge(GUARD, { LeftShoulder = { 84, 10, 6 }, LeftElbow = { 80, 0, 0 }, Neck = { 14, 16, 10 } }) },
	{ 0.78, merge(GUARD, { LeftShoulder = { 84, 10, 6 }, LeftElbow = { 16, 0, 0 }, Neck = { 14, 16, 10 } }) },
	{ 0.94, merge(GUARD, { LeftShoulder = { 84, 10, 6 }, LeftElbow = { 84, 0, 0 }, Neck = { 14, 16, 10 } }) },
	{ 1.1, merge(GUARD, { Neck = { 8, 18, 6 } }) },
	{ 1.4, REST },
})
-- Shrug: arms open, head tilting side to side ("is that all?")
local SHRUG = { Root = { 0, 0, 0, 0, 0.06, 0 }, Torso = { 8, 0, 0 }, Neck = { 6, 0, 14 }, RightShoulder = { 30, -30, 50 }, LeftShoulder = { 30, 30, -50 }, RightElbow = { 84, 0, 0 }, LeftElbow = { 84, 0, 0 } }
define("TauntShrug", {}, {
	{ 0.25, SHRUG, "Back" },
	{ 0.5, merge(SHRUG, { Root = { 0, 0, 0 }, Torso = { 10, 0, 0 }, Neck = { 4, 0, -12 } }) },
	{ 0.75, SHRUG },
	{ 1.05, merge(SHRUG, { Torso = { 4, 0, 0 }, RightShoulder = { 24, -20, 40 }, LeftShoulder = { 24, 20, -40 } }) },
	{ 1.4, REST },
})
-- Flex: a double biceps, squeezed twice
local FLEX = {
	Root = { 0, 0, 0, 0, -0.12, 0 },
	Torso = { 4, 0, 0 },
	Neck = { -8, 0, 0 },
	RightShoulder = { 90, 0, 92 },
	LeftShoulder = { 90, 0, -92 },
	RightElbow = { 104, 0, 0 },
	LeftElbow = { 104, 0, 0 },
	RightHip = { 6, 0, 10 },
	LeftHip = { 6, 0, -10 },
	RightKnee = { -12, 0, 0 },
	LeftKnee = { -12, 0, 0 },
}
define("TauntFlex", {}, {
	{ 0.22, FLEX, "Back" },
	{ 0.5, merge(FLEX, { Root = { 0, 0, 0, 0, -0.18, 0 }, Torso = { -6, 0, 0 }, RightElbow = { 124, 0, 0 }, LeftElbow = { 124, 0, 0 } }) },
	{ 0.8, merge(FLEX, { Torso = { 2, 0, 0 }, Neck = { -12, 0, 0 }, RightElbow = { 110, 0, 0 }, LeftElbow = { 110, 0, 0 } }) },
	{ 1.05, merge(FLEX, { Root = { 0, 0, 0, 0, -0.18, 0 }, Torso = { -6, 0, 0 }, RightElbow = { 126, 0, 0 }, LeftElbow = { 126, 0, 0 } }) },
	{ 1.4, REST },
})
Poser.Taunts = { "TauntBeckon", "TauntShrug", "TauntFlex" }

-- Which sequence plays each server move name
Poser.MoveSequence = {
	Jab = "Jab",
	Cross = "Cross",
	Hook = "Hook",
	FinisherKick = "FinisherKick",
	Heavy = "Heavy",
	ChargedHeavy = "ChargedStrike",
	Launcher = "Launcher",
	RushStrike = "RushStrike",
	ShoulderCharge = "ShoulderCharge",
	AirKick = "AirKick",
	Slam = "Slam",
	Sweep = "Sweep",
	Grab = "Grab",
	PropThrow = "PropThrow",
}

return Poser
