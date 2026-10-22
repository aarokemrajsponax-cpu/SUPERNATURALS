-- How The Grandmaster looks: a plain fighter in linen and ink whose energy
-- grows with mastery. Disciple is restrained (cloth, dust, sharp whooshes, no
-- glow). Adept adds a jade sash and a subtle aura on successful counters.
-- Grandmaster adds motion trails, air distortion on heavy strikes and a faint
-- aura. Ascendant Dragon adds golden-white and jade energy at the hands and
-- feet, a ready stance when idle, dragon-shaped trails on finishers and the
-- full Heaven-Splitting Dragon. Celestial Dragon Style (a cosmetic pass)
-- swaps the palette to star-silver and gold, adds aura colours, an alternate
-- stance and victory pose, and a star dragon on the ultimate. Looks only.
--
-- Animation is posed with Poser (joint rotations), keyed in short sequences:
-- anticipation, strike, follow-through. Real animation ids can replace each
-- named pose later (see POSES below for the list that needs replacing).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Settings = require(script.Parent.Parent.Settings)

local Attribute = Protocol.Attribute

local Grandmaster = {}

local rgb = Color3.fromRGB
local LINEN = rgb(232, 224, 205)
local DUST = rgb(196, 186, 166)
local INK = rgb(44, 54, 52)
local JADE = rgb(86, 186, 148)
local JADE_LIGHT = rgb(186, 236, 212)
local GOLD_WHITE = rgb(250, 232, 186)
-- Celestial Dragon Style
local AZURE = rgb(132, 168, 228)
local STAR_GOLD = rgb(236, 206, 132)
local NIGHT = rgb(38, 44, 66)
local STAR_SILVER = rgb(214, 224, 244)

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local STYLE_PASS = "CelestialDragonStyle"

-- Poses ------------------------------------------------------------------------------
-- Placeholder animation keys (each one is a single key of a multi-key move).
-- Replace with uploaded animations by name when they exist.
local POSES = {
	GMGuard = { RightShoulder = { 70, 0, -30 }, RightElbow = { 100, 0, 0 }, LeftShoulder = { 85, 0, 25 }, LeftElbow = { 70, 0, 0 }, Torso = { 6, 20, 0 }, RightHip = { 15, 0, 8 }, LeftHip = { -10, 0, -6 } },
	GMCelestialStance = { RightShoulder = { 150, 0, -30 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 80, 0, 10 }, LeftElbow = { 90, 0, 0 }, Torso = { -6, 10, 0 }, LeftHip = { 55, 0, 0 } },
	GMVictory = { RightShoulder = { 75, 0, -25 }, LeftShoulder = { 75, 0, 25 }, RightElbow = { 80, 0, 0 }, LeftElbow = { 80, 0, 0 }, Torso = { 25, 0, 0 }, Neck = { 15, 0, 0 } },
	GMCelestialVictory = { RightShoulder = { 165, 0, -15 }, LeftShoulder = { 60, 0, -70 }, RightElbow = { 10, 0, 0 }, Torso = { -10, 0, 0 }, Neck = { -18, 0, 0 }, RightHip = { 75, 0, 0 } },
	-- The Iron Fist
	GMOpeningLoad = { RightShoulder = { 40, 0, -20 }, RightElbow = { 120, 0, 0 }, LeftShoulder = { 80, 0, 20 }, LeftElbow = { 80, 0, 0 }, Torso = { 0, -15, 0 } },
	GMOpening = { RightShoulder = { 92, 0, -4 }, RightElbow = { 4, 0, 0 }, LeftShoulder = { 60, 0, 20 }, LeftElbow = { 110, 0, 0 }, Torso = { 4, 28, 0 } },
	GMTwinLeft = { LeftShoulder = { 92, 0, 4 }, LeftElbow = { 4, 0, 0 }, RightShoulder = { 60, 0, -20 }, RightElbow = { 110, 0, 0 }, Torso = { 4, -26, 0 } },
	GMTwinRight = { RightShoulder = { 94, 0, -6 }, RightElbow = { 2, 0, 0 }, LeftShoulder = { 55, 0, 25 }, LeftElbow = { 115, 0, 0 }, Torso = { 6, 32, 0 } },
	GMPalmLoad = { RightShoulder = { -10, 0, 25 }, RightElbow = { 120, 0, 0 }, LeftShoulder = { 70, 0, 15 }, Torso = { 18, -10, 0 }, RightHip = { 25, 0, 0 } },
	GMRisingPalm = { RightShoulder = { 165, 0, -8 }, RightElbow = { 15, 0, 0 }, LeftShoulder = { 20, 0, 30 }, Torso = { -14, 18, 0 }, Neck = { -12, 0, 0 }, RightHip = { -5, 0, 0 } },
	GMKickLoad = { Torso = { 0, -50, 0 }, RightHip = { 20, 0, 10 }, RightShoulder = { 40, 0, 60 }, LeftShoulder = { 40, 0, -60 } },
	GMWhirlwind = { RightHip = { 85, 0, 35 }, LeftHip = { -8, 0, 0 }, Torso = { -18, 70, 0 }, RightShoulder = { 20, 0, 80 }, LeftShoulder = { 30, 0, -75 }, Neck = { 0, -25, 0 } },
	GMPalmWindup = { RightShoulder = { 20, 0, 40 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 90, 0, 10 }, LeftElbow = { 20, 0, 0 }, Torso = { 10, -40, 0 }, LeftHip = { 20, 0, 0 } },
	GMPalmStrike = { RightShoulder = { 95, 0, -2 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { -30, 0, 25 }, LeftElbow = { 40, 0, 0 }, Torso = { -8, 40, 0 }, RightHip = { -15, 0, 0 }, LeftHip = { 30, 0, 0 } },
	-- Techniques
	GMStep = { Torso = { 18, 0, 0 }, RightShoulder = { -35, 0, 15 }, LeftShoulder = { -35, 0, -15 }, RightHip = { 30, 0, 0 }, LeftHip = { -20, 0, 0 } },
	GMClawRight = { RightShoulder = { 70, 0, -10 }, RightElbow = { 25, 0, 0 }, LeftShoulder = { 50, 0, 20 }, LeftElbow = { 100, 0, 0 }, Torso = { 18, 25, 0 }, RightHip = { 20, 0, 0 } },
	GMClawLeft = { LeftShoulder = { 70, 0, 10 }, LeftElbow = { 25, 0, 0 }, RightShoulder = { 50, 0, -20 }, RightElbow = { 100, 0, 0 }, Torso = { 18, -25, 0 }, LeftHip = { 20, 0, 0 } },
	GMThrustTell = { RightShoulder = { -20, 0, 20 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { -20, 0, -20 }, LeftElbow = { 110, 0, 0 }, Torso = { 12, 0, 0 }, RightHip = { 30, 0, 0 }, LeftHip = { -15, 0, 0 } },
	GMThrust = { RightShoulder = { 92, 0, -12 }, LeftShoulder = { 92, 0, 12 }, RightElbow = { 0, 0, 0 }, LeftElbow = { 0, 0, 0 }, Torso = { 10, 0, 0 }, RightHip = { -10, 0, 0 }, LeftHip = { 35, 0, 0 } },
	GMCrane = { RightShoulder = { 60, 0, 70 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 95, 0, -20 }, LeftElbow = { 45, 0, 0 }, Torso = { -4, 15, 0 }, RightHip = { 80, 0, 0 }, Neck = { -5, 0, 0 } },
	GMCraneRedirect = { Torso = { 0, -55, 0 }, LeftShoulder = { 100, 0, 60 }, LeftElbow = { 20, 0, 0 }, RightShoulder = { 80, 0, -30 }, RightElbow = { 60, 0, 0 }, LeftHip = { 20, 0, 0 }, RightHip = { 0, 0, 0 } },
	GMShoulderLoad = { Torso = { 20, -35, 0 }, RightShoulder = { 30, 0, 10 }, LeftShoulder = { -20, 0, -20 }, RightHip = { 35, 0, 0 }, LeftHip = { -10, 0, 0 } },
	GMShoulderCheck = { Torso = { 25, -70, 0 }, LeftShoulder = { -10, 0, -40 }, RightShoulder = { 40, 0, 25 }, LeftHip = { 35, 0, 0 }, RightHip = { -20, 0, 0 } },
	GMSweepLoad = { Torso = { 35, 0, 0 }, RightHip = { 70, 0, 10 }, LeftHip = { 60, 0, -10 }, RightShoulder = { 30, 0, 40 }, LeftShoulder = { 30, 0, -40 } },
	GMSweep = { Torso = { 40, 90, 0 }, LeftHip = { 80, 0, -70 }, RightHip = { 90, 0, 10 }, RightShoulder = { 20, 0, 70 }, LeftShoulder = { 60, 0, -30 } },
	GMElbow = { RightShoulder = { 90, 0, 60 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 60, 0, 20 }, Torso = { 0, 45, 0 } },
	GMKnee = { RightHip = { 110, 0, 0 }, Torso = { 18, 0, 0 }, RightShoulder = { 60, 0, 30 }, LeftShoulder = { 60, 0, -30 } },
	GMSpin = { LeftHip = { 85, 0, -35 }, RightHip = { -8, 0, 0 }, Torso = { -15, -70, 0 }, RightShoulder = { 30, 0, 75 }, LeftShoulder = { 20, 0, -80 }, Neck = { 0, 25, 0 } },
	GMFocus = { RightShoulder = { 60, 0, -40 }, LeftShoulder = { 60, 0, 40 }, RightElbow = { 90, 0, 0 }, LeftElbow = { 90, 0, 0 }, Torso = { -4, 0, 0 }, Neck = { 6, 0, 0 }, RightHip = { 20, 0, 15 }, LeftHip = { 20, 0, -15 } },
	GMUltStance = { RightShoulder = { -15, 0, 15 }, RightElbow = { 115, 0, 0 }, LeftShoulder = { 90, 0, 10 }, LeftElbow = { 10, 0, 0 }, Torso = { 10, -30, 0 }, RightHip = { 30, 0, 25 }, LeftHip = { 30, 0, -25 }, Neck = { 5, 25, 0 } },
	-- Hit reactions (one per strike type)
	GMReactLight = { Neck = { -18, 0, 0 }, Torso = { -8, 0, 0 } },
	GMReactHeavy = { Torso = { 28, 0, 0 }, Neck = { 20, 0, 0 }, RightShoulder = { 30, 0, 30 }, LeftShoulder = { 30, 0, -30 } },
	GMReactLaunch = { Torso = { -30, 0, 0 }, Neck = { -30, 0, 0 }, RightShoulder = { 140, 0, 40 }, LeftShoulder = { 140, 0, -40 }, RightHip = { 25, 0, 0 } },
	GMReactCounter = { Torso = { 15, -40, 0 }, Neck = { 10, 20, 0 }, RightShoulder = { -20, 0, 50 }, LeftShoulder = { 60, 0, -20 } },
	GMKnockdown = { Torso = { -55, 0, 0 }, RightHip = { 50, 0, 0 }, LeftHip = { 40, 0, 0 }, RightShoulder = { 60, 0, 60 }, LeftShoulder = { 60, 0, -60 }, Neck = { -15, 0, 0 } },
}
Grandmaster.Poses = POSES

local registered = false
local function registerPoses(Poser)
	if registered then
		return
	end
	registered = true
	for name, pose in POSES do
		Poser.register(name, pose)
	end
end

-- The Iron Fist: anticipation key, strike key per step (played on top of the
-- default swing so the chain reads as kung fu, not generic punches)
local CHAIN = {
	{ load = "GMOpeningLoad", strike = "GMOpening", kind = "Punch" },
	{ load = "GMTwinLeft", strike = "GMTwinRight", kind = "Punch" },
	{ load = "GMPalmLoad", strike = "GMRisingPalm", kind = "Palm" },
	{ load = "GMKickLoad", strike = "GMWhirlwind", kind = "Kick" },
}

local STRIKE_POSES = { Punch = "GMTwinRight", Elbow = "GMElbow", Palm = "GMRisingPalm", Knee = "GMKnee", Kick = "GMWhirlwind", Spin = "GMSpin" }

-- Helpers ---------------------------------------------------------------------------

local function celestial(kit): boolean
	-- Delayed effects can outlive the model; a destroyed model just reads as the standard look
	local ok, style = pcall(kit.attribute, Attribute.Style)
	return ok and style == STYLE_PASS
end

-- energy: the glow colour, core: its hot centre, dust: cloth and air
local function palette(kit): { energy: Color3, core: Color3, dust: Color3 }
	if celestial(kit) then
		return { energy = AZURE, core = STAR_GOLD, dust = STAR_SILVER }
	elseif kit.degree >= 4 then
		return { energy = JADE, core = GOLD_WHITE, dust = LINEN }
	elseif kit.degree >= 2 then
		return { energy = JADE, core = JADE_LIGHT, dust = LINEN }
	end
	return { energy = LINEN, core = LINEN, dust = DUST }
end

local function part(model: Model?, names: { string }): BasePart?
	if not model then
		return nil
	end
	for _, name in names do
		local found = model:FindFirstChild(name)
		if found and found:IsA("BasePart") then
			return found
		end
	end
	return nil
end

local function handsOf(model: Model): { BasePart }
	local list = {}
	for _, names in { { "RightHand", "Right Arm" }, { "LeftHand", "Left Arm" } } do
		local found = part(model, names)
		if found then
			table.insert(list, found)
		end
	end
	return list
end

local function feetOf(model: Model): { BasePart }
	local list = {}
	for _, names in { { "RightFoot", "Right Leg" }, { "LeftFoot", "Left Leg" } } do
		local found = part(model, names)
		if found then
			table.insert(list, found)
		end
	end
	return list
end

local function rootOf(model: Instance?): BasePart?
	local root = if model then model:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function modelOf(value: any): Model?
	return if typeof(value) == "Instance" and value:IsA("Model") then value else nil
end

-- Layered sound: a body impact plus a whoosh or ring, pitched per strike
local SOUNDS = {
	Punch = { { "rbxasset://sounds/action_jump_land.mp3", 0.55, 1.9 }, { "rbxasset://sounds/swordslash.wav", 0.18, 2.5 } },
	Palm = { { "rbxasset://sounds/action_jump_land.mp3", 0.75, 1.15 }, { "rbxasset://sounds/swordlunge.wav", 0.2, 1.6 } },
	Kick = { { "rbxasset://sounds/action_jump_land.mp3", 0.85, 1.0 }, { "rbxasset://sounds/swordlunge.wav", 0.35, 1.25 } },
	Whoosh = { { "rbxasset://sounds/swordslash.wav", 0.22, 1.9 } },
	Counter = { { "rbxasset://sounds/unsheath.wav", 0.6, 1.55 }, { "rbxasset://sounds/action_jump_land.mp3", 0.5, 1.6 } },
	Heavy = { { "rbxasset://sounds/action_jump_land.mp3", 1, 0.75 }, { "rbxasset://sounds/swordlunge.wav", 0.4, 0.8 } },
	Dragon = { { "rbxasset://sounds/action_jump_land.mp3", 1, 0.55 }, { "rbxasset://sounds/swordlunge.wav", 0.5, 0.6 }, { "rbxasset://sounds/unsheath.wav", 0.35, 0.7 } },
	Step = { { "rbxasset://sounds/swordslash.wav", 0.16, 2.8 } },
	Stance = { { "rbxasset://sounds/unsheath.wav", 0.25, 0.85 } },
}

local function play(name: string, at: Vector3 | Instance)
	local layers = SOUNDS[name]
	if not layers then
		return
	end
	local volume = Settings.get("sfxVolume")
	local scale = if typeof(volume) == "number" then volume else 1
	local holder: Instance = if typeof(at) == "Instance" then at else workspace.CurrentCamera
	local anchor: BasePart? = nil
	if typeof(at) == "Vector3" then
		local made = Instance.new("Part")
		made.Anchored = true
		made.CanCollide = false
		made.CanQuery = false
		made.CanTouch = false
		made.Transparency = 1
		made.Size = Vector3.one * 0.2
		made.CFrame = CFrame.new(at)
		made.Parent = workspace.CurrentCamera
		anchor = made
		holder = made
		Debris:AddItem(made, 3)
	end
	for _, layer in layers do
		local sound = Instance.new("Sound")
		sound.SoundId = layer[1]
		sound.Volume = layer[2] * scale
		sound.PlaybackSpeed = layer[3] * (0.96 + math.random() * 0.08)
		sound.RollOffMaxDistance = 110
		sound.Parent = holder
		if not anchor then
			Debris:AddItem(sound, 3)
		end
		sound:Play()
	end
end

-- Plays poses one after another: { { pose, at, inTime, hold } }, then eases out
local function sequence(kit, model: Model?, keys: { { any } }, outTime: number?)
	if not model then
		return
	end
	registerPoses(kit.Poser)
	for index, key in keys do
		local poseName, at, inTime, hold = key[1], key[2], key[3], key[4]
		local last = index == #keys
		local function run()
			if model.Parent then
				kit.Poser.play(model, poseName, inTime, hold, if last then (outTime or 0.25) else 0.2)
			end
		end
		if at <= 0 then
			run()
		else
			task.delay(at, run)
		end
	end
end

local function react(kit, victim: Model?, poseName: string, hold: number)
	if victim then
		registerPoses(kit.Poser)
		kit.Poser.play(victim, poseName, 0.04, hold, 0.3)
	end
end

-- A small, sharp impact: a flash of sparks, a puff of air and dust, a thin ring
local function impact(kit, position: Vector3, strength: number, direction: Vector3?)
	local colors = palette(kit)
	local Vfx = kit.Vfx
	local energized = kit.degree >= 2 or celestial(kit)
	Vfx.sparks(position, colors.core, math.floor(4 + strength * 4), 18 + strength * 10)
	Vfx.burst(position, {
		color = colors.dust,
		lightEmission = 0,
		texture = SMOKE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6 + strength * 0.3), NumberSequenceKeypoint.new(1, 1.8 + strength) }),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		lifetime = NumberRange.new(0.35, 0.6),
		speed = NumberRange.new(3, 6 + strength * 3),
		drag = 6,
		count = math.floor(4 + strength * 3),
	})
	local frame = if direction and direction.Magnitude > 0.1 then CFrame.lookAt(position, position + direction) else CFrame.new(position)
	Vfx.ring(frame, 0.6 + strength * 0.4, if energized then colors.energy else colors.dust, 0.12, 0.18, 1.6 + strength * 1.2)
	if energized and strength >= 2 then
		Vfx.glow(position, colors.energy, 6 + strength * 3, 1 + strength * 0.4, 0.14)
	end
end

-- Air distortion around a heavy strike (Degree III+): a glassy bubble that swells and vanishes
local function distortion(kit, position: Vector3, size: number)
	if kit.degree < 3 or kit.Vfx.reduced() then
		return
	end
	local bubble = kit.Vfx.part({
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Glass,
		Transparency = 0.82,
		Color = rgb(225, 235, 232),
		Reflectance = 0.1,
		Size = Vector3.one * (size * 0.4),
		CFrame = CFrame.new(position),
	})
	TweenService:Create(bubble, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * size }):Play()
	kit.Vfx.fade(bubble, 0.28, { Transparency = 1 })
end

-- A tapered trail on a limb for a moment (stronger from Degree III)
local function limbTrail(kit, limb: BasePart?, duration: number)
	if not limb or kit.Vfx.reduced() then
		return
	end
	local colors = palette(kit)
	local strong = kit.degree >= 3
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, limb.Size.Y * 0.35, 0)
	a0.Parent = limb
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -limb.Size.Y * 0.45, 0)
	a1.Parent = limb
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(colors.core, colors.energy)
	trail.LightEmission = if strong then 0.8 else 0.2
	trail.LightInfluence = if strong then 0.2 else 1
	trail.Lifetime = if strong then 0.22 else 0.12
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, if strong then 0.25 else 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) })
	trail.FaceCamera = true
	trail.Parent = limb
	Debris:AddItem(trail, duration + 0.3)
	Debris:AddItem(a0, duration + 0.3)
	Debris:AddItem(a1, duration + 0.3)
	task.delay(duration, function()
		-- The limb (and the trail with it) may already be gone
		pcall(function()
			trail.Enabled = false
		end)
	end)
end

-- A dragon-shaped ribbon of energy: segments along a rising curve, head first,
-- each fading on its own (Degree IV finishers and the ultimate)
local function dragonTrail(kit, origin: Vector3, direction: Vector3, length: number, height: number, scale: number)
	if kit.Vfx.reduced() then
		return
	end
	local colors = palette(kit)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.05 then
		return
	end
	flat = flat.Unit
	local side = flat:Cross(Vector3.yAxis)
	local count = 14
	local points = {}
	for index = 0, count do
		local t = index / count
		local sway = math.sin(t * math.pi * 2.2) * 1.6 * scale
		points[index] = origin + flat * (t * length) + side * sway + Vector3.new(0, math.sin(t * math.pi * 0.5) * height, 0)
	end
	task.spawn(function()
		for index = 1, count do
			local from, to = points[index - 1], points[index]
			local t = index / count
			-- Thick body tapering to a thin tail behind the head
			local width = (0.25 + (1 - math.abs(t - 0.75) * 1.2) * 0.75) * scale
			local segment = kit.Vfx.part({
				Material = Enum.Material.Neon,
				Color = if index >= count - 1 then colors.core else colors.energy,
				Transparency = 0.35,
				Size = Vector3.new(width, width * 0.7, (to - from).Magnitude + 0.3),
				CFrame = CFrame.lookAt((from + to) / 2, to),
			})
			kit.Vfx.fade(segment, 0.45 + t * 0.25, { Transparency = 1, Size = segment.Size * 0.4 })
			task.wait(0.012)
		end
		-- The head: a brighter wedge with two swept horns
		local head = points[count]
		local facing = CFrame.lookAt(head, head + (points[count] - points[count - 1]))
		local snout = kit.Vfx.part({
			Shape = Enum.PartType.Ball,
			Color = colors.core,
			Transparency = 0.2,
			Size = Vector3.one * 1.1 * scale,
			CFrame = facing,
		})
		kit.Vfx.fade(snout, 0.5, { Transparency = 1, Size = snout.Size * 1.8 })
		for _, sideSign in { -1, 1 } do
			local horn = kit.Vfx.part({
				Color = colors.core,
				Transparency = 0.3,
				Size = Vector3.new(0.12, 0.12, 1.3) * scale,
				CFrame = facing * CFrame.new(0.35 * sideSign * scale, 0.4 * scale, 0.5 * scale) * CFrame.Angles(math.rad(25), math.rad(-20 * sideSign), 0),
			})
			kit.Vfx.fade(horn, 0.45, { Transparency = 1 })
		end
	end)
end

-- Freeze-frame on both fighters for a moment (purely visual hit-stop)
local function hitStop(models: { Model? }, duration: number)
	local paused = {}
	for _, model in models do
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local ok, tracks = pcall(function()
				return animator:GetPlayingAnimationTracks()
			end)
			if ok and typeof(tracks) == "table" then
				for _, track in tracks do
					pcall(function()
						track:AdjustSpeed(0)
					end)
					table.insert(paused, track)
				end
			end
		end
	end
	if #paused > 0 then
		task.delay(duration, function()
			for _, track in paused do
				pcall(function()
					track:AdjustSpeed(1)
				end)
			end
		end)
	end
end

local function afterimages(kit, count: number, gap: number)
	local model = kit.model
	if not model then
		return
	end
	local colors = palette(kit)
	task.spawn(function()
		for _ = 1, count do
			if not model.Parent then
				return
			end
			kit.Vfx.afterimage(model, colors.dust)
			task.wait(gap)
		end
	end)
end

-- A short, brighter aura around the fighter (counters, the focus stance)
local function auraFlare(kit, duration: number, strength: number)
	local root = kit.root
	if not root then
		return
	end
	local colors = palette(kit)
	kit.Vfx.burst(root.Position - Vector3.new(0, 1.5, 0), {
		colors = ColorSequence.new(colors.core, colors.energy),
		texture = SPARKLE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) }),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		lifetime = NumberRange.new(0.5, 0.9),
		speed = NumberRange.new(2, 4),
		spread = Vector2.new(30, 180),
		acceleration = Vector3.new(0, 5, 0),
		drag = 2,
		count = math.floor(8 * strength),
	})
	kit.Vfx.glow(root, colors.energy, 9, 0.8 * strength, duration)
end

local function targetPosition(kit, fallback: Vector3?): Vector3?
	local victim = modelOf(kit.data.target)
	local root = rootOf(victim)
	return if root then root.Position else fallback
end

local function direction(kit): Vector3
	local given = kit.data.direction
	if typeof(given) == "Vector3" and given.Magnitude > 0.1 then
		return given.Unit
	end
	return if kit.root then kit.root.CFrame.LookVector else Vector3.new(0, 0, -1)
end

-- Predicted poses (the local player sees their move the moment they press) -----------

local function windupPose(kit, poseName: string, duration: number)
	sequence(kit, kit.model, { { poseName, 0, math.min(0.12, duration * 0.6), math.max(0.05, duration) } }, 0.2)
end

Grandmaster.predict = {
	DragonsStep = function(kit)
		windupPose(kit, "GMStep", 0.2)
	end,
	TigerClaw = function(kit)
		windupPose(kit, "GMClawRight", kit.data.startup or 0.14)
	end,
	CranesReversal = function(kit)
		windupPose(kit, "GMCrane", 0.4)
	end,
	IronMountain = function(kit)
		windupPose(kit, "GMShoulderLoad", kit.data.startup or 0.4)
	end,
	SweepingDragon = function(kit)
		windupPose(kit, "GMSweepLoad", kit.data.startup or 0.3)
	end,
	HundredFists = function(kit)
		windupPose(kit, "GMOpeningLoad", kit.data.startup or 0.2)
	end,
	FocusState = function(kit)
		windupPose(kit, "GMFocus", kit.data.startup or 0.35)
	end,
	DragonsAnswer = function(kit)
		windupPose(kit, "GMPalmLoad", kit.data.startup or 0.1)
	end,
	HeavenSplittingDragon = function(kit)
		windupPose(kit, "GMUltStance", kit.data.startup or 0.5)
	end,
}

-- Every cast has its own effects below; no generic cast glow
function Grandmaster.onCast() end

local fx = {}
Grandmaster.fx = fx

-- The Iron Fist -------------------------------------------------------------------------

-- Drawn on every Grandmaster swing (from the combat event; see appearance)
local function chainSwing(kit, step: number, startup: number, active: number)
	local model = kit.model
	local key = CHAIN[step]
	if not model or not key then
		return
	end
	sequence(kit, model, {
		{ key.load, 0, math.max(0.03, startup * 0.45), startup * 0.15 },
		{ key.strike, startup * 0.6, math.max(0.03, startup * 0.4), active + 0.06 },
	}, 0.22)
	local limb = if key.kind == "Kick" then part(model, { "RightFoot", "Right Leg" }) else part(model, { "RightHand", "Right Arm" })
	limbTrail(kit, limb, startup + active)
	if step == 2 then
		limbTrail(kit, part(model, { "LeftHand", "Left Arm" }), startup + active)
	end
	task.delay(startup * 0.5, function()
		if kit.root and kit.root.Parent then
			play("Whoosh", kit.root)
		end
	end)
end
Grandmaster.chainSwing = chainSwing

function fx.IronFistImpact(kit)
	local victim = modelOf(kit.data.target)
	local position = targetPosition(kit, nil)
	if not position then
		return
	end
	local step = kit.data.step or 1
	local key = CHAIN[step] or CHAIN[1]
	local toward = if kit.root then position - kit.root.Position else nil
	if kit.data.finisher then
		-- Whirlwind Kick: hit-stop, shake, a burst of dust and a bigger ring
		hitStop({ kit.model, victim }, kit.data.hitStop or 0.07)
		impact(kit, position, 3, toward)
		distortion(kit, position, 6)
		kit.Vfx.groundRing(position - Vector3.new(0, 2.8, 0), palette(kit).dust, 1, 9, 0.4)
		play("Kick", position)
		kit.shake(1.6, 0.25, position)
		react(kit, victim, "GMReactHeavy", 0.3)
		if kit.degree >= 4 and kit.root then
			dragonTrail(kit, kit.root.Position + Vector3.new(0, -0.5, 0), toward or direction(kit), 7, 2, 0.6)
		end
	elseif step == 3 then
		impact(kit, position, 1.6, Vector3.yAxis)
		play("Palm", position)
		kit.shake(0.6, 0.12, position)
		react(kit, victim, "GMReactLaunch", 0.3)
	else
		impact(kit, position, 1, toward)
		play(key.kind, position)
		react(kit, victim, "GMReactLight", 0.08)
	end
end

function fx.TwinFist(kit)
	local position = targetPosition(kit, nil)
	if position then
		sequence(kit, kit.model, { { "GMTwinLeft", 0, 0.04, 0.08 } }, 0.15)
		impact(kit, position, 1, nil)
		play("Punch", position)
		react(kit, modelOf(kit.data.target), "GMReactLight", 0.08)
	end
end

function fx.CounterPalm(kit)
	local position = targetPosition(kit, nil)
	if position then
		sequence(kit, kit.model, { { "GMPalmStrike", 0, 0.05, 0.12 } }, 0.25)
		impact(kit, position, 2, nil)
		auraFlare(kit, 0.25, 0.6)
		play("Counter", position)
		react(kit, modelOf(kit.data.target), "GMReactCounter", 0.25)
		kit.shake(0.8, 0.15, position)
	end
end

-- Dragon's Step ---------------------------------------------------------------------------

function fx.Step(kit)
	local model = kit.model
	if not model then
		return
	end
	sequence(kit, model, { { "GMStep", 0, 0.04, kit.data.duration or 0.2 } }, 0.2)
	afterimages(kit, if kit.degree >= 3 then 3 else 2, 0.06)
	if kit.root then
		play("Step", kit.root)
		kit.Vfx.burst(kit.root.Position - Vector3.new(0, 2.8, 0), {
			color = palette(kit).dust,
			lightEmission = 0,
			texture = SMOKE,
			size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2) }),
			transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }),
			lifetime = NumberRange.new(0.3, 0.5),
			speed = NumberRange.new(2, 5),
			spread = Vector2.new(10, 180),
			drag = 5,
			count = 6,
		})
	end
	for _, foot in feetOf(model) do
		limbTrail(kit, foot, 0.2)
	end
end

-- A strike slipped through the step: a crisp ring and a short flash
function fx.StepRead(kit)
	local root = kit.root
	if not root then
		return
	end
	local colors = palette(kit)
	kit.Vfx.ring(CFrame.new(root.Position) * CFrame.Angles(math.rad(90), 0, 0), 1.5, colors.core, 0.1, 0.3, 4)
	play("Counter", root)
	if kit.degree >= 2 then
		auraFlare(kit, 0.3, 0.7)
	end
	if kit.isLocal then
		kit.Vfx.text3d(root.Position + Vector3.new(0, 3.5, 0), "Opening", colors.core, 1, 0.8)
	end
end

-- Tiger Claw --------------------------------------------------------------------------------

function fx.TigerWindup(kit)
	sequence(kit, kit.model, { { "GMClawLeft", 0, math.max(0.05, (kit.data.duration or 0.14) * 0.8), 0.05 } }, 0.2)
end

function fx.TigerStrike(kit)
	local model = kit.model
	if not model or not kit.root then
		return
	end
	local right = kit.data.index == 1
	sequence(kit, model, { { if right then "GMClawRight" else "GMClawLeft", 0, 0.04, 0.07 } }, 0.15)
	local origin = kit.root.CFrame * CFrame.new(if right then 0.6 else -0.6, -0.4, -2.6)
	kit.Vfx.slash(kit.root.CFrame * CFrame.new(0, -0.4, 0), palette(kit).dust, 3.2, if right then -20 else 20, 0.1)
	if kit.data.landed then
		impact(kit, origin.Position, 1, kit.root.CFrame.LookVector)
		play("Punch", origin.Position)
	else
		play("Whoosh", kit.root)
	end
end

-- The tell: both hands drawn back, a clear flash at the palms
function fx.TigerTell(kit)
	local model = kit.model
	if not model or not kit.root then
		return
	end
	local duration = kit.data.duration or 0.32
	sequence(kit, model, { { "GMThrustTell", 0, duration * 0.5, duration * 0.5 } }, 0.1)
	local colors = palette(kit)
	for _, hand in handsOf(model) do
		kit.Vfx.glow(hand, if kit.degree >= 2 then colors.energy else rgb(255, 214, 170), 7, 1.4, duration + 0.05)
	end
	kit.Vfx.telegraph(kit.root, rgb(255, 200, 150), duration)
end

function fx.TigerThrust(kit)
	local model = kit.model
	if not model or not kit.root then
		return
	end
	sequence(kit, model, { { "GMThrust", 0, 0.05, 0.18 } }, 0.3)
	local front = kit.root.Position + kit.root.CFrame.LookVector * 3
	if kit.data.landed then
		impact(kit, front, 2.2, kit.root.CFrame.LookVector)
		distortion(kit, front, 5)
		play("Palm", front)
		kit.shake(1, 0.18, front)
	else
		play("Whoosh", kit.root)
	end
	kit.Vfx.cone(CFrame.lookAt(front, front + kit.root.CFrame.LookVector), 4, 30, palette(kit).dust, 0.2)
end

-- Crane's Reversal --------------------------------------------------------------------------

function fx.CraneStance(kit)
	local duration = kit.data.duration or 0.48
	sequence(kit, kit.model, { { "GMCrane", 0, 0.06, duration } }, 0.2)
	if kit.root then
		play("Stance", kit.root)
		kit.Vfx.groundRing(kit.root.Position - Vector3.new(0, 2.9, 0), palette(kit).dust, 1, 5, duration)
	end
end

function fx.CraneCounter(kit)
	local victim = modelOf(kit.data.target)
	local position = targetPosition(kit, nil)
	sequence(kit, kit.model, { { "GMCraneRedirect", 0, 0.04, 0.12 } }, 0.2)
	if not kit.root then
		return
	end
	-- The distinctive counter: a bright ring, a ringing tone, a brief aura (Adept+)
	local colors = palette(kit)
	kit.Vfx.ring(kit.root.CFrame * CFrame.new(0, 0, -1.5), 1.2, colors.core, 0.15, 0.25, 4.5)
	kit.Vfx.flash(kit.model :: Model, colors.core, 0.15)
	play("Counter", kit.root)
	if kit.degree >= 2 then
		auraFlare(kit, 0.6, if kit.degree >= 3 then 1.4 else 1)
	end
	if position then
		impact(kit, position, 1.4, nil)
	end
	react(kit, victim, "GMReactCounter", 0.3)
	if kit.Vfx.intense() and kit.degree >= 3 and kit.isLocal then
		kit.Vfx.screenFlash(colors.core, 0.12, 0.18)
	end
end

function fx.CraneFinish(kit)
	local position = targetPosition(kit, nil)
	sequence(kit, kit.model, { { "GMPalmStrike", 0, 0.04, 0.18 } }, 0.3)
	if position then
		impact(kit, position, 2.4, nil)
		distortion(kit, position, 5)
		play("Palm", position)
		kit.shake(1.2, 0.2, position)
		react(kit, modelOf(kit.data.target), "GMReactHeavy", 0.3)
	end
end

function fx.CraneMiss(kit)
	-- Caught standing on one leg: a wobble
	if kit.model then
		kit.Poser.play(kit.model, "Stagger", 0.08, 0.3, 0.3)
	end
end

-- Iron Mountain -------------------------------------------------------------------------------

function fx.MountainWindup(kit)
	local duration = kit.data.duration or 0.42
	sequence(kit, kit.model, { { "GMShoulderLoad", 0, duration * 0.7, duration * 0.3 } }, 0.1)
	if kit.root then
		kit.Vfx.telegraph(kit.root, rgb(255, 196, 140), duration)
		play("Stance", kit.root)
	end
end

function fx.MountainCheck(kit)
	sequence(kit, kit.model, { { "GMShoulderCheck", 0, 0.05, 0.14 } }, 0.15)
	afterimages(kit, 1, 0.05)
	if kit.root then
		play("Whoosh", kit.root)
	end
end

function fx.MountainPalm(kit)
	local model = kit.model
	local root = kit.root
	if not model or not root then
		return
	end
	sequence(kit, model, { { "GMPalmStrike", 0, 0.05, 0.25 } }, 0.35)
	local front = root.Position + root.CFrame.LookVector * 3.2
	if kit.data.landed then
		impact(kit, front, 3, root.CFrame.LookVector)
		distortion(kit, front, 7)
		kit.Vfx.groundRing(front - Vector3.new(0, 2.8, 0), palette(kit).dust, 1, 10, 0.45)
		play("Heavy", front)
		kit.shake(2, 0.3, front)
	else
		play("Whoosh", root)
	end
end

-- Sweeping Dragon ------------------------------------------------------------------------------

function fx.SweepWindup(kit)
	local duration = kit.data.duration or 0.3
	sequence(kit, kit.model, { { "GMSweepLoad", 0, duration * 0.7, duration * 0.3 } }, 0.1)
	if kit.root then
		kit.Vfx.telegraph(kit.root, rgb(255, 200, 150), duration)
	end
end

function fx.Sweep(kit)
	local position = kit.data.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local radius = kit.data.radius or 8
	local colors = palette(kit)
	sequence(kit, kit.model, { { "GMSweep", 0, 0.05, 0.2 } }, 0.35)
	for _, foot in feetOf(kit.model :: Model) do
		limbTrail(kit, foot, 0.25)
	end
	-- A low arc of dust hugging the floor, then a thin ring
	kit.Vfx.groundRing(position + Vector3.new(0, 0.1, 0), colors.dust, 2, radius * 2, 0.35)
	if kit.degree >= 3 then
		kit.Vfx.groundRing(position + Vector3.new(0, 0.15, 0), colors.energy, 2, radius * 1.7, 0.28)
	end
	kit.Vfx.burst(position + Vector3.new(0, 0.4, 0), {
		color = colors.dust,
		lightEmission = 0,
		texture = SMOKE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) }),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
		lifetime = NumberRange.new(0.5, 0.9),
		speed = NumberRange.new(radius, radius * 1.6),
		spread = Vector2.new(4, 180),
		drag = 5,
		count = 14,
	})
	play("Kick", position)
	kit.shake(0.8, 0.18, position)
	if kit.degree >= 4 and kit.root then
		dragonTrail(kit, position + Vector3.new(0, 0.6, 0), kit.root.CFrame.RightVector, radius * 0.9, 0.4, 0.5)
	end
end

function fx.Knockdown(kit)
	local victim = modelOf(kit.data.target)
	react(kit, victim, "GMKnockdown", math.max(0.2, (kit.data.duration or 0.9) - 0.35))
	local root = rootOf(victim)
	if root then
		kit.Vfx.burst(root.Position - Vector3.new(0, 2.6, 0), {
			color = DUST,
			lightEmission = 0,
			texture = SMOKE,
			size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 2.4) }),
			transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
			lifetime = NumberRange.new(0.5, 0.8),
			speed = NumberRange.new(2, 4),
			drag = 4,
			count = 8,
		})
	end
end

-- Hundred Fists and the ultimate's flurries -----------------------------------------------------

function fx.HundredWindup(kit)
	local duration = kit.data.duration or 0.2
	sequence(kit, kit.model, { { "GMOpeningLoad", 0, duration * 0.8, duration * 0.2 } }, 0.1)
	if kit.model then
		for _, hand in handsOf(kit.model) do
			limbTrail(kit, hand, duration + 0.2)
		end
	end
end

function fx.HundredWhiff(kit)
	sequence(kit, kit.model, { { "GMOpening", 0, 0.05, 0.12 } }, 0.25)
	if kit.root then
		play("Whoosh", kit.root)
	end
end

local function opener(kit, cinematic: boolean)
	local position = targetPosition(kit, nil)
	sequence(kit, kit.model, { { "GMOpening", 0, 0.04, 0.1 } }, 0.15)
	if position then
		impact(kit, position, if cinematic then 2 else 1.4, nil)
		play("Punch", position)
		react(kit, modelOf(kit.data.target), "GMReactHeavy", 0.15)
	end
end

function fx.HundredOpener(kit)
	opener(kit, false)
end

-- Fists and elbows blur together: hand trails for the whole flurry
local function flurry(kit)
	local model = kit.model
	if not model then
		return
	end
	local duration = (kit.data.finishAt or 0.7) + 0.1
	for _, hand in handsOf(model) do
		limbTrail(kit, hand, duration)
	end
	if kit.data.cinematic then
		for _, foot in feetOf(model) do
			limbTrail(kit, foot, duration)
		end
	end
end

function fx.HundredFlurry(kit)
	flurry(kit)
end

local function beat(kit, cinematic: boolean)
	local position = targetPosition(kit, nil)
	local strike = kit.data.strike or "Punch"
	local index = kit.data.index or 1
	local poseName = STRIKE_POSES[strike] or "GMTwinRight"
	if strike == "Punch" and index % 2 == 0 then
		poseName = "GMTwinLeft"
	end
	sequence(kit, kit.model, { { poseName, 0, 0.035, 0.07 } }, 0.12)
	if not position then
		return
	end
	local push = direction(kit)
	impact(kit, position, if cinematic then 1.6 else 1, push)
	if cinematic and kit.degree >= 4 then
		-- Each confirmed impact sends a directional shockwave and a flash of energy
		local colors = palette(kit)
		kit.Vfx.ring(CFrame.lookAt(position, position + push), 1, colors.energy, 0.12, 0.22, 3.5)
		kit.Vfx.glow(position, colors.core, 8, 1.4, 0.1)
	end
	play(if strike == "Kick" or strike == "Spin" or strike == "Knee" then "Kick" elseif strike == "Palm" then "Palm" else "Punch", position)
	react(kit, modelOf(kit.data.target), if index % 2 == 0 then "GMReactLight" else "GMReactCounter", 0.06)
	kit.shake(if cinematic then 0.5 else 0.3, 0.08, position)
end

function fx.HundredBeat(kit)
	beat(kit, false)
end

local function finisher(kit, cinematic: boolean)
	local victim = modelOf(kit.data.target)
	local position = targetPosition(kit, nil)
	sequence(kit, kit.model, {
		{ "GMPalmLoad", 0, 0.04, 0.02 },
		{ "GMRisingPalm", 0.06, 0.05, 0.3 },
	}, 0.4)
	if not position then
		return
	end
	local push = direction(kit)
	hitStop({ kit.model, victim }, if cinematic then 0.1 else 0.07)
	impact(kit, position, 3, Vector3.yAxis)
	distortion(kit, position, if cinematic then 9 else 6)
	play(if cinematic then "Dragon" else "Heavy", position)
	kit.shake(if cinematic then 2.6 else 1.8, if cinematic then 0.4 else 0.28, position)
	react(kit, victim, "GMReactLaunch", 0.45)
	if kit.degree >= 4 and kit.root then
		dragonTrail(kit, kit.root.Position - Vector3.new(0, 1, 0), push, 9, 6, 0.8)
	end
end

function fx.HundredFinish(kit)
	finisher(kit, false)
end

-- Focus State ------------------------------------------------------------------------------------

function fx.FocusStance(kit)
	local duration = kit.data.duration or 0.35
	sequence(kit, kit.model, { { "GMFocus", 0, duration * 0.6, duration * 0.4 + 0.15 } }, 0.3)
	if kit.root then
		play("Stance", kit.root)
		kit.Vfx.groundRing(kit.root.Position - Vector3.new(0, 2.9, 0), palette(kit).energy, 6, 1, duration)
	end
end

-- While focused: brighter aura, steady hand trails and a slow ring at the feet
function fx.Focused(kit)
	local model = kit.model
	local root = kit.root
	if not model or not root then
		return
	end
	local colors = palette(kit)
	local created = {}
	auraFlare(kit, 0.4, 1.2)
	local attachment = Instance.new("Attachment")
	attachment.Name = "SNGMFocus"
	attachment.Position = Vector3.new(0, -2.6, 0)
	attachment.Parent = root
	table.insert(created, attachment)
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = SPARKLE
	motes.Color = ColorSequence.new(colors.core, colors.energy)
	motes.LightEmission = 0.8
	motes.LightInfluence = 0
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	motes.Lifetime = NumberRange.new(0.8, 1.4)
	motes.Speed = NumberRange.new(1, 2)
	motes.SpreadAngle = Vector2.new(25, 180)
	motes.Acceleration = Vector3.new(0, 3, 0)
	motes.Drag = 1.5
	motes.Rate = if kit.Vfx.reduced() then 4 else 12
	motes.Parent = attachment
	local light = Instance.new("PointLight")
	light.Color = colors.energy
	light.Brightness = 0.6
	light.Range = 8
	light.Parent = attachment
	for _, hand in handsOf(model) do
		limbTrail(kit, hand, kit.data.duration or 5)
	end
	kit.keep(function()
		for _, item in created do
			item:Destroy()
		end
	end)
end

-- Dragon's Answer ---------------------------------------------------------------------------------

function fx.AnswerWindup(kit)
	local duration = kit.data.duration or 0.1
	sequence(kit, kit.model, { { "GMPalmLoad", 0, math.max(0.04, duration), 0.03 } }, 0.1)
	afterimages(kit, 2, 0.04)
	if kit.model then
		for _, hand in handsOf(kit.model) do
			kit.Vfx.glow(hand, palette(kit).core, 6, 1.2, duration + 0.2)
		end
	end
end

function fx.AnswerPalm(kit)
	local root = kit.root
	if not root then
		return
	end
	local push = direction(kit)
	sequence(kit, kit.model, { { "GMPalmStrike", 0, 0.04, 0.22 } }, 0.35)
	local front = root.Position + push * 3
	if kit.data.landed then
		hitStop({ kit.model }, 0.06)
		impact(kit, front, 3, push)
		distortion(kit, front, 7)
		play("Dragon", front)
		kit.shake(1.8, 0.3, front)
		dragonTrail(kit, root.Position - Vector3.new(0, 0.5, 0), push, 8, 2.5, 0.7)
	else
		play("Whoosh", root)
	end
end

-- Heaven-Splitting Dragon -----------------------------------------------------------------------

-- The surrounding sound dampens for a moment (local listeners near the stance)
local function hush(duration: number)
	local reverb = Instance.new("EqualizerSoundEffect")
	reverb.Name = "SNGMHush"
	reverb.HighGain = -18
	reverb.MidGain = -8
	reverb.LowGain = 0
	reverb.Priority = 5
	local applied = {}
	for _, group in game:GetService("SoundService"):GetChildren() do
		if group:IsA("SoundGroup") then
			local copy = reverb:Clone()
			copy.Parent = group
			table.insert(applied, copy)
		end
	end
	reverb:Destroy()
	task.delay(duration, function()
		for _, item in applied do
			item:Destroy()
		end
	end)
end

function fx.UltStance(kit)
	local root = kit.root
	local duration = kit.data.duration or 0.5
	local cinematic = kit.data.cinematic == true
	sequence(kit, kit.model, { { "GMUltStance", 0, duration * 0.5, duration * 0.5 } }, 0.1)
	if not root then
		return
	end
	local colors = palette(kit)
	kit.Vfx.telegraph(root, colors.core, duration)
	play("Stance", root)
	if kit.near(root.Position, 40) then
		hush(duration + 0.3)
	end
	-- Energy gathers into the hands
	if kit.model and (kit.degree >= 2 or celestial(kit)) then
		for _, hand in handsOf(kit.model) do
			kit.Vfx.glow(hand, colors.energy, if cinematic then 8 else 5, if cinematic then 1.6 else 1, duration + 0.1)
		end
	end
	kit.Vfx.groundRing(root.Position - Vector3.new(0, 2.9, 0), colors.energy, if cinematic then 14 else 9, 2, duration)
	if cinematic then
		auraFlare(kit, duration, 1.5)
	end
end

function fx.UltFizzle(kit)
	if kit.model then
		kit.Poser.play(kit.model, "Stagger", 0.06, 0.2, 0.3)
	end
	if kit.root then
		kit.Vfx.burst(kit.root.Position, {
			color = palette(kit).dust,
			lightEmission = 0,
			texture = SMOKE,
			size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) }),
			transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }),
			lifetime = NumberRange.new(0.4, 0.6),
			speed = NumberRange.new(1, 3),
			count = 6,
		})
	end
end

function fx.UltOpener(kit)
	opener(kit, kit.data.cinematic == true)
	local position = targetPosition(kit, nil)
	if position and kit.data.cinematic then
		kit.Vfx.ring(CFrame.lookAt(position, position + direction(kit)), 1.2, palette(kit).core, 0.14, 0.3, 4)
	end
end

function fx.UltFlurry(kit)
	flurry(kit)
end

function fx.UltBeat(kit)
	beat(kit, kit.data.cinematic == true)
end

-- The spectral dragon: two coils spiralling up around the target, then a head
local function spectralDragon(kit, position: Vector3)
	local colors = palette(kit)
	if kit.Vfx.reduced() then
		kit.Vfx.glow(position, colors.core, 16, 2, 0.4)
		return
	end
	task.spawn(function()
		local segments = 22
		for index = 1, segments do
			local t = index / segments
			local angle = t * math.pi * 3
			local radius = 3.2 - t * 1.6
			local point = position + Vector3.new(math.cos(angle) * radius, -2 + t * 9, math.sin(angle) * radius)
			local nextAngle = angle + 0.45
			local ahead = position + Vector3.new(math.cos(nextAngle) * radius, -2 + (t + 0.04) * 9, math.sin(nextAngle) * radius)
			local width = 0.35 + math.sin(t * math.pi) * 0.7
			local scale = if celestial(kit) then 1.15 else 1
			local segment = kit.Vfx.part({
				Material = Enum.Material.ForceField,
				Color = if t > 0.85 then colors.core else colors.energy,
				Transparency = 0.1,
				Size = Vector3.new(width, width * 0.7, 1.4) * scale,
				CFrame = CFrame.lookAt(point, ahead),
			})
			kit.Vfx.fade(segment, 0.55 + t * 0.3, { Transparency = 1 })
			if celestial(kit) and index % 4 == 0 then
				kit.Vfx.sparks(point, STAR_GOLD, 3, 6)
			end
			task.wait(0.014)
		end
		local top = position + Vector3.new(0, 7.2, 0)
		kit.Vfx.orb(top, colors.core, 0.6, 2.6, 0.45, Enum.Material.ForceField)
		kit.Vfx.glow(top, colors.energy, 18, 2.2, 0.35)
	end)
end

function fx.UltFinish(kit)
	local cinematic = kit.data.cinematic == true
	finisher(kit, cinematic)
	local position = targetPosition(kit, nil)
	if not position then
		return
	end
	local colors = palette(kit)
	if cinematic then
		spectralDragon(kit, position)
		if kit.Vfx.intense() and kit.near(position, 45) then
			kit.Vfx.screenFlash(colors.core, 0.18, 0.3)
		end
	elseif kit.degree >= 2 then
		kit.Vfx.ring(CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0), 1.5, colors.energy, 0.14, 0.35, 5)
	end
end

-- The arena reacts: one controlled shockwave across the floor (presentation only)
function fx.UltShockwave(kit)
	local position = kit.data.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local colors = palette(kit)
	kit.Vfx.groundRing(position + Vector3.new(0, 0.12, 0), colors.energy, 2, 34, 0.7)
	kit.Vfx.groundRing(position + Vector3.new(0, 0.16, 0), colors.dust, 2, 26, 0.9)
	kit.Vfx.shockwave(position + Vector3.new(0, 1.5, 0), colors.core, 3, 22, 0.5)
	kit.Vfx.burst(position + Vector3.new(0, 0.5, 0), {
		color = colors.dust,
		lightEmission = 0,
		texture = SMOKE,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) }),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		lifetime = NumberRange.new(0.8, 1.3),
		speed = NumberRange.new(14, 22),
		spread = Vector2.new(4, 180),
		drag = 4,
		count = 20,
	})
	kit.shake(1.5, 0.35, position)
end

-- Victory pose (call from the results screen): a bow, or the celestial pose
function Grandmaster.victory(kit)
	registerPoses(kit.Poser)
	if kit.model then
		kit.Poser.play(kit.model, if celestial(kit) then "GMCelestialVictory" else "GMVictory", 0.3, 1.6, 0.5)
	end
end

-- Persistent look ---------------------------------------------------------------------------------

-- The sash: a cloth belt with two tails, coloured by degree (and style)
local SASH = { LINEN, JADE, INK, GOLD_WHITE }

local function weldTo(anchor: BasePart, piece: BasePart, offset: CFrame)
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.Massless = true
	piece.CastShadow = false
	piece.Anchored = false
	piece.CFrame = anchor.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = piece
	weld.Parent = piece
end

local function buildSash(kit, created: { Instance })
	local model = kit.model :: Model
	local waist = part(model, { "LowerTorso", "Torso" })
	if not waist then
		return
	end
	local isR6 = waist.Name == "Torso"
	local color = if celestial(kit) then NIGHT else SASH[math.clamp(kit.degree, 1, 4)]
	local trim = if celestial(kit) then STAR_GOLD elseif kit.degree == 3 then JADE else nil
	local height = if isR6 then -waist.Size.Y * 0.35 else 0
	local belt = Instance.new("Part")
	belt.Name = "SNGMSash"
	belt.Material = Enum.Material.Fabric
	belt.Color = color
	belt.Size = Vector3.new(waist.Size.X + 0.12, 0.32, waist.Size.Z + 0.12)
	weldTo(waist, belt, CFrame.new(0, height, 0))
	belt.Parent = model
	table.insert(created, belt)
	-- Knot and tails hanging at the left hip, slightly uneven like real cloth
	for index, spec in { { 0.95, -4 }, { 0.75, 7 } } do
		local tail = Instance.new("Part")
		tail.Name = "SNGMSashTail"
		tail.Material = Enum.Material.Fabric
		tail.Color = color
		tail.Size = Vector3.new(0.22, spec[1], 0.08)
		weldTo(waist, tail, CFrame.new(-waist.Size.X * 0.32 + index * 0.16, height - spec[1] / 2 - 0.05, -waist.Size.Z / 2 - 0.08) * CFrame.Angles(0, 0, math.rad(spec[2])))
		tail.Parent = model
		table.insert(created, tail)
		if trim then
			local edge = Instance.new("Part")
			edge.Name = "SNGMSashTrim"
			edge.Material = Enum.Material.Fabric
			edge.Color = trim
			edge.Size = Vector3.new(0.23, 0.07, 0.09)
			weldTo(tail, edge, CFrame.new(0, -spec[1] / 2 + 0.05, 0))
			edge.Parent = model
			table.insert(created, edge)
		end
	end
end

-- Energy at the hands and feet (Ascendant Dragon), or the aura (Grandmaster / celestial)
local function energyAt(kit, limb: BasePart, created: { Instance }, rate: number, withLight: boolean)
	local colors = palette(kit)
	local attachment = Instance.new("Attachment")
	attachment.Name = "SNGMEnergy"
	attachment.Parent = limb
	table.insert(created, attachment)
	local wisps = Instance.new("ParticleEmitter")
	wisps.Texture = SPARKLE
	wisps.Color = ColorSequence.new(colors.core, colors.energy)
	wisps.LightEmission = 0.9
	wisps.LightInfluence = 0
	wisps.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14), NumberSequenceKeypoint.new(1, 0) })
	wisps.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	wisps.Lifetime = NumberRange.new(0.4, 0.8)
	wisps.Speed = NumberRange.new(0.4, 1.2)
	wisps.SpreadAngle = Vector2.new(180, 180)
	wisps.Acceleration = Vector3.new(0, 2, 0)
	wisps.Drag = 2
	wisps.Rate = if kit.Vfx.reduced() then math.max(1, math.floor(rate / 3)) else rate
	wisps.Parent = attachment
	if withLight then
		local light = Instance.new("PointLight")
		light.Color = colors.energy
		light.Brightness = 0.6
		light.Range = 5
		light.Shadows = false
		light.Parent = attachment
	end
end

local function buildAura(kit, created: { Instance })
	local root = kit.root
	if not root then
		return
	end
	local colors = palette(kit)
	local attachment = Instance.new("Attachment")
	attachment.Name = "SNGMAura"
	attachment.Position = Vector3.new(0, -2.7, 0)
	attachment.Parent = root
	table.insert(created, attachment)
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = SMOKE
	-- Celestial style carries two extra aura colours that drift through each mote's life
	motes.Color = if celestial(kit)
		then ColorSequence.new({ ColorSequenceKeypoint.new(0, AZURE), ColorSequenceKeypoint.new(0.5, STAR_SILVER), ColorSequenceKeypoint.new(1, STAR_GOLD) })
		else ColorSequence.new(colors.energy, colors.core)
	motes.LightEmission = 0.5
	motes.LightInfluence = 0.3
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.4, 0.9), NumberSequenceKeypoint.new(1, 0.2) })
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.82), NumberSequenceKeypoint.new(1, 1) })
	motes.Lifetime = NumberRange.new(1.2, 1.8)
	motes.Speed = NumberRange.new(0.5, 1)
	motes.SpreadAngle = Vector2.new(60, 180)
	motes.Acceleration = Vector3.new(0, 1.6, 0)
	motes.Drag = 1
	motes.Rotation = NumberRange.new(0, 360)
	motes.RotSpeed = NumberRange.new(-20, 20)
	motes.Rate = if kit.Vfx.reduced() then 1 else 3
	motes.Parent = attachment
end

local function buildLook(kit, model: Model): () -> ()
	registerPoses(kit.Poser)
	local created: { Instance } = {}
	local connections: { RBXScriptConnection } = {}
	local alive = true
	buildSash(kit, created)
	if kit.degree >= 3 or celestial(kit) then
		buildAura(kit, created)
	end
	if kit.degree >= 4 then
		for _, hand in handsOf(model) do
			energyAt(kit, hand, created, 5, true)
		end
		for _, foot in feetOf(model) do
			energyAt(kit, foot, created, 3, false)
		end
	end

	-- The Iron Fist and the palm strike draw their own poses on every swing
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local combatEvent = remotes and remotes:FindFirstChild("CombatEvent")
	if combatEvent and combatEvent:IsA("RemoteEvent") then
		table.insert(connections, combatEvent.OnClientEvent:Connect(function(kind, data)
			if kind ~= Protocol.CombatEvent.Attack or typeof(data) ~= "table" or data.attacker ~= model then
				return
			end
			local startup = if typeof(data.startup) == "number" then data.startup else 0.1
			local active = if typeof(data.active) == "number" then data.active else 0.1
			-- After the default swing so these keys take over its joints
			task.defer(function()
				if data.kind == "Light" then
					chainSwing(kit, if typeof(data.step) == "number" then data.step else 1, startup, active)
				elseif data.kind == "Heavy" then
					sequence(kit, model, {
						{ "GMPalmWindup", 0, startup * 0.8, startup * 0.2 },
						{ "GMPalmStrike", startup, 0.05, active + 0.15 },
					}, 0.3)
					local hand = part(model, { "RightHand", "Right Arm" })
					task.delay(startup, function()
						limbTrail(kit, hand, active + 0.1)
					end)
				end
			end)
		end))
	end

	-- Ascendant Dragon (and the celestial style) settle into a ready stance when standing still
	local stance = if celestial(kit) then "GMCelestialStance" elseif kit.degree >= 4 then "GMGuard" else nil
	if stance then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		task.spawn(function()
			local stillSince = os.clock()
			local holding = false
			while alive and model.Parent do
				local now = workspace:GetServerTimeNow()
				local busyUntil = model:GetAttribute(Attribute.BusyUntil)
				local stunnedUntil = model:GetAttribute(Attribute.StunnedUntil)
				local busy = (typeof(busyUntil) == "number" and busyUntil > now)
					or (typeof(stunnedUntil) == "number" and stunnedUntil > now)
					or model:GetAttribute(Attribute.Blocking) == true
				local readOk, moveDirection = pcall(function()
					return (humanoid :: Humanoid).MoveDirection
				end)
				local moving = humanoid ~= nil and readOk and typeof(moveDirection) == "Vector3" and moveDirection.Magnitude > 0.1
				if moving or busy then
					stillSince = os.clock()
					if holding then
						holding = false
						kit.Poser.release(model, stance)
					end
				elseif not holding and os.clock() - stillSince > 1.5 then
					holding = true
					kit.Poser.hold(model, stance)
				end
				task.wait(0.25)
			end
			if holding and model.Parent then
				kit.Poser.release(model, stance)
			end
		end)
	end

	return function()
		alive = false
		for _, connection in connections do
			connection:Disconnect()
		end
		for _, item in created do
			item:Destroy()
		end
		if stance and model.Parent then
			kit.Poser.release(model, stance)
		end
	end
end

function Grandmaster.appearance(kit)
	local model = kit.model
	if not model then
		return nil
	end
	local stop = buildLook(kit, model)
	-- Buying Celestial Dragon Style mid-session redraws the look straight away
	local styleChanged = model:GetAttributeChangedSignal(Attribute.Style):Connect(function()
		stop()
		stop = buildLook(kit, model)
	end)
	return function()
		styleChanged:Disconnect()
		stop()
	end
end

return Grandmaster
