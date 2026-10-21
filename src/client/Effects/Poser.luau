-- Placeholder animation: poses a character by rotating its joints (Motor6D.C0)
-- with tweens. It works on R15 and R6 rigs and layers on top of Roblox's
-- normal walk and idle animations. Each client poses every character locally
-- from combat events, so everyone sees the same moves.
--
-- When real animations are made, give them ids in a config and play them
-- instead; nothing else in the combat system needs to change.

local TweenService = game:GetService("TweenService")

local Poser = {}

-- Joint name -> where its Motor6D lives on each rig type: { part, motor }
local JOINTS = {
	RightShoulder = { r15 = { "RightUpperArm", "RightShoulder" }, r6 = { "Torso", "Right Shoulder" } },
	LeftShoulder = { r15 = { "LeftUpperArm", "LeftShoulder" }, r6 = { "Torso", "Left Shoulder" } },
	RightElbow = { r15 = { "RightLowerArm", "RightElbow" } },
	LeftElbow = { r15 = { "LeftLowerArm", "LeftElbow" } },
	Torso = { r15 = { "UpperTorso", "Waist" }, r6 = { "HumanoidRootPart", "RootJoint" } },
	Neck = { r15 = { "Head", "Neck" }, r6 = { "Torso", "Neck" } },
	RightHip = { r15 = { "RightUpperLeg", "RightHip" }, r6 = { "Torso", "Right Hip" } },
	LeftHip = { r15 = { "LeftUpperLeg", "LeftHip" }, r6 = { "Torso", "Left Hip" } },
}

-- Poses: joint -> { pitch, yaw, roll } in degrees, in the body's own space.
-- Pitch raises an arm forward; yaw twists (positive turns left); roll swings sideways.
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
	Block = {
		RightShoulder = { 100, 0, -25 },
		LeftShoulder = { 100, 0, 25 },
		RightElbow = { 95, 0, 0 },
		LeftElbow = { 95, 0, 0 },
		Torso = { -6, 0, 0 },
	},
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

local function findMotor(character: Model, joint: string): Motor6D?
	local spec = JOINTS[joint]
	if not spec then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local isR15 = humanoid and humanoid.RigType == Enum.HumanoidRigType.R15
	local location = if isR15 then spec.r15 else spec.r6
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

local function posed(motor: Motor6D, angles: { number }): CFrame
	local original = base(motor)
	local rotation = CFrame.Angles(math.rad(angles[1]), math.rad(angles[2]), math.rad(angles[3]))
	-- Rotate about the joint, in the parent part's space
	return CFrame.new(original.Position) * rotation * original.Rotation
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

-- Goes into a pose over `inTime`, holds it, then eases back over `outTime`
function Poser.play(character: Model?, poseName: string, inTime: number, hold: number, outTime: number)
	if not character then
		return
	end
	local pose = Poser.Poses[poseName]
	if not pose then
		return
	end
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

-- Holds a pose until released (for blocking)
function Poser.hold(character: Model?, poseName: string)
	if not character then
		return
	end
	if character:GetAttribute(HOLD_PREFIX .. poseName) then
		return
	end
	character:SetAttribute(HOLD_PREFIX .. poseName, true)
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
	local pose = Poser.Poses[poseName]
	for joint in pose or {} do
		local motor = findMotor(character, joint)
		if motor then
			tweenTo(motor, base(motor), 0.15)
		end
	end
end

return Poser
