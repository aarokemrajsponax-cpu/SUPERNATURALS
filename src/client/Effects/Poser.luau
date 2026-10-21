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
}

-- The resting C0 of each joint and which poses are held are stored as (local)
-- attributes on the instances themselves: Roblox can recycle the Lua object for
-- an Instance, so tables keyed by Instances may forget them. Active tweens and
-- tokens only need to live while a pose is playing (their closures keep them).
local BASE_ATTRIBUTE = "SNBaseC0"
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

local function base(motor: Motor6D): CFrame
	local original = motor:GetAttribute(BASE_ATTRIBUTE)
	if typeof(original) ~= "CFrame" then
		original = motor.C0
		motor:SetAttribute(BASE_ATTRIBUTE, original)
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
