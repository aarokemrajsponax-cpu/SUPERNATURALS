-- Small movement polish for the local client, started by CombatController:
--   * a wider view while sprinting (and a brief kick on a dodge/dash) with a short motion trail
--   * dust and a soft thud when landing from a big fall
--   * footsteps for Machine Master and Jeffery's sparring unit ("RobotStep")
--   * stopping the old movement style's animation tracks when the fighter changes style
-- Nothing here is gameplay: the server decides everything that matters. It allocates only when
-- something happens (a landing, a step, a dash), never every frame.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Audio = require(ReplicatedStorage.Shared.Config.Audio)
local Animations = require(ReplicatedStorage.Shared.Config.Animations)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Settings = require(script.Parent.Parent.Settings)
local Vfx = require(script.Parent.Parent.Effects.Vfx)

local Attribute = Protocol.Attribute
local player = Players.LocalPlayer

local MovementFeel = {}

MovementFeel.Config = {
	SprintFov = 5,
	DashFov = 4,
	-- Landing: downward speed (studs/s) from which a fall makes dust, and where it is at full strength
	LandMinSpeed = 70,
	LandFullSpeed = 140,
	LandVolume = 0.45,
	-- Footsteps: distance between steps (studs), quietest and loudest speed, hearing range
	StepStride = 4.2,
	StepVolume = 0.8,
	StepRange = 90,
	-- Fighters that make robot footsteps: power ids, and the "Look" attribute of Jeffery's unit
	RobotPowers = { MachineMaster = true },
	RobotLooks = { Jeffery = true },
}

local camera: any = nil

local function sfxScale(): number
	local volume = Settings.get("sfxVolume")
	return if typeof(volume) == "number" then volume else 1
end

-- Plays a catalogue sound at a fraction of its normal volume from a part (pooled: pass the same
-- Sound each time to avoid creating one per step)
local function softSound(name: string, parent: Instance, scale: number, pooled: Sound?): Sound?
	local spec = Audio.Sounds[name]
	if not spec then
		return nil
	end
	local sound = pooled
	if not sound then
		sound = Instance.new("Sound")
		sound.SoundId = spec.Id
		sound.RollOffMaxDistance = 90
		sound.Parent = parent
	end
	sound = sound :: Sound
	sound.Volume = spec.Volume * scale * sfxScale()
	sound.PlaybackSpeed = spec.Pitch * (0.94 + math.random() * 0.12)
	sound:Play()
	return sound
end

-- Dash trail -------------------------------------------------------------------------------

-- A thin streak behind the body for a dash or dodge
function MovementFeel.dashTrail(character: Model, duration: number, color: Color3?)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 0.9, 0)
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -1.1, 0)
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.22
	trail.MinLength = 0.1
	trail.LightEmission = 0.8
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(color or Color3.fromRGB(150, 230, 255))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) })
	top.Parent = root
	bottom.Parent = root
	trail.Parent = root
	local life = duration + 0.3
	Debris:AddItem(trail, life)
	Debris:AddItem(top, life)
	Debris:AddItem(bottom, life)
end

-- A dodge or dash from this client: a brief widening of the view and the trail
function MovementFeel.dash(character: Model, duration: number)
	if camera then
		camera:punch(MovementFeel.Config.DashFov)
	end
	MovementFeel.dashTrail(character, duration)
end

-- Landing --------------------------------------------------------------------------------

local function watchLanding(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	local config = MovementFeel.Config
	local fastest = 0
	local sampler: RBXScriptConnection? = nil
	local function stopSampling()
		if sampler then
			sampler:Disconnect()
			sampler = nil
		end
	end
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Freefall then
			fastest = 0
			if not sampler then
				-- One number compare per frame while falling, nothing else
				sampler = RunService.Heartbeat:Connect(function()
					local down = -root.AssemblyLinearVelocity.Y
					if down > fastest then
						fastest = down
					end
				end)
			end
		elseif new == Enum.HumanoidStateType.Landed then
			stopSampling()
			if fastest >= config.LandMinSpeed then
				local strength = math.clamp((fastest - config.LandMinSpeed) / (config.LandFullSpeed - config.LandMinSpeed), 0, 1)
				local feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 - 0.1, 0)
				Vfx.burst(feet, {
					color = Color3.fromRGB(190, 180, 165),
					lightEmission = 0,
					count = 8 + math.floor(strength * 10),
					speed = NumberRange.new(6, 12 + strength * 8),
					spread = Vector2.new(80, 80),
					lifetime = NumberRange.new(0.35, 0.7),
					size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8 + strength), NumberSequenceKeypoint.new(1, 2.2 + strength * 2) }),
					transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
					drag = 5,
				})
				-- Soft: a quiet thud, louder for a harder landing
				local name = if strength > 0.6 then "GroundSlam" else "Block"
				softSound(name, root, MovementFeel.Config.LandVolume * (0.4 + strength * 0.6))
				if camera and strength > 0.3 then
					camera:shake(0.4 + strength * 0.8, 0.18)
				end
			end
			fastest = 0
		elseif new ~= Enum.HumanoidStateType.Freefall then
			stopSampling()
		end
	end)
end

-- Sprint view ----------------------------------------------------------------------------

local function watchSprint(character: Model)
	local function update()
		if camera then
			camera:setSpeedFov(if character:GetAttribute(Attribute.Sprinting) == true then MovementFeel.Config.SprintFov else 0)
		end
	end
	character:GetAttributeChangedSignal(Attribute.Sprinting):Connect(update)
	update()
end

-- Movement style changes ----------------------------------------------------------------

-- The server swaps the ids inside Animate; stop the tracks still playing the old style so the
-- new one shows at once (Poser's combat poses are not tracks and are untouched)
local function watchStyle(character: Model)
	character:GetAttributeChangedSignal(Animations.StyleAttribute):Connect(function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		local animate = character:FindFirstChild("Animate")
		if not animator or not animate then
			return
		end
		for _, track in animator:GetPlayingAnimationTracks() do
			local animation = track.Animation
			if animation and animation:IsDescendantOf(animate) then
				track:Stop(0.05)
			end
		end
	end)
end

-- Robot footsteps -------------------------------------------------------------------------

type Walker = { model: Model, humanoid: Humanoid, root: BasePart, travelled: number, sound: Sound? }
local walkers: { Walker } = {}

local function makesRobotSteps(model: Model): boolean
	local config = MovementFeel.Config
	local power = model:GetAttribute(Attribute.Power)
	if typeof(power) == "string" and config.RobotPowers[power] then
		return true
	end
	local look = model:GetAttribute("Look")
	return typeof(look) == "string" and config.RobotLooks[look] == true
end

local function refreshWalkers()
	local keep: { Walker } = {}
	local known = {}
	for _, walker in walkers do
		if walker.model.Parent and walker.humanoid.Health > 0 and makesRobotSteps(walker.model) then
			table.insert(keep, walker)
			known[walker.model] = true
		end
	end
	for _, model in CollectionService:GetTagged(Protocol.Tag.Fighter) do
		if not known[model] and model:IsA("Model") and makesRobotSteps(model) then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart")
			if humanoid and root and root:IsA("BasePart") then
				table.insert(keep, { model = model, humanoid = humanoid, root = root, travelled = 0, sound = nil })
			end
		end
	end
	walkers = keep
end

local function stepWalkers(dt: number)
	local config = MovementFeel.Config
	local origin = if camera then workspace.CurrentCamera.CFrame.Position else nil
	for _, walker in walkers do
		local root = walker.root
		local velocity = root.AssemblyLinearVelocity
		local speed = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
		if speed > 3 and walker.humanoid.FloorMaterial ~= Enum.Material.Air then
			walker.travelled += speed * dt
			if walker.travelled >= config.StepStride then
				walker.travelled -= config.StepStride
				if not origin or (root.Position - origin).Magnitude <= config.StepRange then
					-- A run is heavier than a walk
					walker.sound = softSound("RobotStep", root, config.StepVolume * math.clamp(speed / 22, 0.5, 1), walker.sound)
				end
			end
		else
			walker.travelled = math.min(walker.travelled, config.StepStride * 0.5)
		end
	end
end

-- Start ------------------------------------------------------------------------------------

function MovementFeel.start(cameraController: any)
	camera = cameraController
	local function onCharacter(character: Model)
		task.spawn(watchLanding, character)
		watchSprint(character)
		watchStyle(character)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end

	task.spawn(function()
		while true do
			task.wait(1)
			refreshWalkers()
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		if #walkers > 0 then
			stepWalkers(dt)
		end
	end)
end

return MovementFeel
