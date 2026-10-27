-- Shows what the server says happened in combat, for every fighter: the moves
-- (keyframed sequences timed to the server's startup/active/recovery), hit
-- reactions by direction and weight, blocks, parries, guard breaks, clashes,
-- grabs and throws, knockdowns and tech rolls, dodges, taunts, plus block
-- shields and the health bars over other fighters. The local player's own moves
-- are previewed the moment they press (CombatController calls predict*), and the
-- server's echo is skipped unless it decided something else.
--
-- Feel comes first and works with every visual effect turned off: hitstop
-- (both fighters' poses pause 40-90 ms, longer for bigger hits), a directional
-- camera kick scaled by the hit (Screen Shake setting), and sound. Sparks, rings
-- and short callouts (COUNTER, PUNISH, WALL SPLAT, CLASH, TECH, PARRY) go on top.
-- A perfect dodge slows the action and tints the dodger's own screen.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Poser = require(script.Parent.Parent.Effects.Poser)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Settings = require(script.Parent.Parent.Settings)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CombatEvent = Remotes:WaitForChild("CombatEvent") :: RemoteEvent

local Attribute = Protocol.Attribute
local Event = Protocol.CombatEvent
local Colors = Theme.Colors

local player = Players.LocalPlayer

local EffectsController = {}

local SLASH_COLOR = Color3.fromRGB(220, 245, 255)
local HEAVY_COLOR = Color3.fromRGB(255, 140, 60)
local CHARGE_COLOR = Color3.fromRGB(255, 196, 112)
local SPARK_COLOR = Color3.fromRGB(255, 230, 150)
local DUST_COLOR = Color3.fromRGB(176, 166, 150)

-- How each server move looks and lands. weight drives hitstop, camera kick and
-- spark size; slash = { radius, tilt, height } for the swing arc (nil = none).
local MOVES = {
	Jab = { kind = "Light", weight = 1, slash = { 3.6, 0, 0.6 } },
	Cross = { kind = "Light", weight = 1.2, slash = { 4, 10, 0.6 } },
	Hook = { kind = "Light", weight = 1.4, slash = { 4.4, 30, 0.6 } },
	FinisherKick = { kind = "Light", weight = 2, slash = { 5, -8, -0.4 }, heavySound = true },
	Heavy = { kind = "Heavy", weight = 2.4, slash = { 5.6, 20, 0.8 }, heavySound = true, telegraph = true },
	ChargedHeavy = { kind = "Heavy", weight = 3, slash = { 6.4, 15, 0.8 }, heavySound = true },
	Launcher = { kind = "Heavy", weight = 2.2, slash = { 5, 85, 0.4 }, heavySound = true, telegraph = true },
	RushStrike = { kind = "Light", weight = 1.8, slash = { 4.6, 5, 0.4 } },
	ShoulderCharge = { kind = "Heavy", weight = 2.6, heavySound = true, telegraph = true },
	AirKick = { kind = "Light", weight = 1.2, slash = { 4.4, -15, -0.2 } },
	Slam = { kind = "Heavy", weight = 2.8, heavySound = true },
	Sweep = { kind = "Sweep", weight = 1.6 },
	Grab = { kind = "Grab", weight = 1 },
	Throw = { kind = "Grab", weight = 2.4 },
	PropThrow = { kind = "Light", weight = 1.5, heavySound = true },
}
local LIGHT_BY_STEP = { "Jab", "Cross", "Hook", "FinisherKick" }

-- The local player's previews, by attack kind, so the server's echo can be skipped
local predicted: { [string]: { family: string, at: number } } = {}
local lastPrediction: { name: string, at: number }? = nil
-- Per fighter (weak keys: cosmetic memory only)
local tauntCount: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local downedPose: { [Model]: string } = setmetatable({}, { __mode = "k" }) :: any
local grabHolds: { [Model]: { back: boolean } } = setmetatable({}, { __mode = "k" }) :: any
local chargeFx: { [Model]: { Instance } } = {}

local shields: { [Model]: BasePart } = {}
local overheads: { [Model]: { gui: BillboardGui, setHealth: (number, Color3?) -> (), setGuard: (number, Color3?) -> (), status: TextLabel } } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isModel(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Model")
end

local function isLocal(model: Model?): boolean
	return model ~= nil and model == player.Character
end

local function number(value: any, default: number): number
	return if typeof(value) == "number" and value == value and math.abs(value) < 1e6 then value else default
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Guard right now, worked out the same way as the server does
local function currentGuard(model: Model): number
	local guard = model:GetAttribute(Attribute.Guard) or Combat.Block.MaxGuard
	local updatedAt = model:GetAttribute(Attribute.GuardUpdatedAt) or 0
	local regen = now() - updatedAt - Combat.Block.GuardRegenDelay
	if updatedAt > 0 and regen > 0 then
		guard = math.min(Combat.Block.MaxGuard, guard + regen * Combat.Block.GuardRegenRate)
	end
	return guard
end
EffectsController.currentGuard = currentGuard

-- Which way a push moves a fighter, in their own terms: "Front" = hit from the
-- front (pushed back), "Back" = hit from behind, "Left"/"Right" = pushed that way
local function pushSide(model: Model, direction: any): string
	local root = rootOf(model)
	if not root or typeof(direction) ~= "Vector3" or flat(direction).Magnitude < 0.01 then
		return "Front"
	end
	local localDirection = root.CFrame:VectorToObjectSpace(flat(direction).Unit)
	if localDirection.Z > 0.5 then
		return "Front"
	elseif localDirection.Z < -0.5 then
		return "Back"
	end
	return if localDirection.X < 0 then "Left" else "Right"
end

-- Heavier and special hits pause longer (40-90 ms)
local function hitstopFor(weight: number, tags: { [string]: any }): number
	local extra = if tags.counter or tags.wallSplat or tags.punish then 0.02 else 0
	return math.clamp(0.03 + weight * 0.02 + extra, 0.04, 0.09)
end

function EffectsController:Init(controllers)
	self.camera = controllers.CameraController
end

function EffectsController:Start()
	CombatEvent.OnClientEvent:Connect(function(kind, data)
		if typeof(data) ~= "table" then
			return
		end
		if kind == Event.Attack then
			self:_onAttack(data)
		elseif kind == Event.Hit then
			self:_onHit(data)
		elseif kind == Event.Dodge then
			self:_onDodge(data)
		elseif kind == Event.Clash then
			self:_onClash(data)
		elseif kind == Event.Grab then
			self:_onGrab(data)
		elseif kind == Event.Motion then
			self:_onMotion(data)
		end
	end)

	for _, model in CollectionService:GetTagged(Protocol.Tag.Fighter) do
		self:_watchFighter(model)
	end
	CollectionService:GetInstanceAddedSignal(Protocol.Tag.Fighter):Connect(function(model)
		self:_watchFighter(model)
	end)

	RunService.RenderStepped:Connect(function()
		for model, shield in shields do
			local root = rootOf(model)
			if root and model.Parent then
				shield.CFrame = root.CFrame * CFrame.new(0, 0.4, -1.7)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.1)
			self:_updateOverheads()
		end
	end)
end

-- Camera feedback when the local player is part of it
function EffectsController:_feel(involved: boolean, direction: any, strength: number, heavy: boolean)
	if not involved or not self.camera then
		return
	end
	self.camera:kick(if typeof(direction) == "Vector3" then direction else nil, strength)
	if heavy then
		self.camera:shake(strength * 0.6, 0.25)
		self.camera:punch(math.min(6, strength * 2))
	end
end

-- Callouts -------------------------------------------------------------------------------
-- Short tags in the design system's style (dark glass, a thin accent stroke and
-- bar, heavy caps) that stack over a fighter, newest at the bottom.

local stacks: { [Instance]: { gui: BillboardGui, list: Frame, order: number } } = {}

function EffectsController:callout(target: Model | Vector3, text: string, color: Color3)
	local key: Instance
	local adornee: Instance?
	if typeof(target) == "Vector3" then
		local anchor = Vfx.part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(target) })
		Debris:AddItem(anchor, 1.6)
		key, adornee = anchor, anchor
	else
		key = target
		adornee = target:FindFirstChild("Head") or rootOf(target)
	end
	if not adornee then
		return
	end
	local stack = stacks[key]
	if not stack or not stack.gui.Parent then
		local gui = Components.make("BillboardGui", {
			Name = "SNCallouts",
			Size = UDim2.fromOffset(240, 112),
			StudsOffsetWorldSpace = Vector3.new(0, if typeof(target) == "Vector3" then 1 else 2.4, 0),
			AlwaysOnTop = true,
			LightInfluence = 0,
			MaxDistance = 140,
			ResetOnSpawn = false,
			Adornee = adornee,
			Parent = workspace.CurrentCamera,
		})
		local list = Components.make("Frame", {
			Name = "Stack",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = gui,
		})
		Components.list(list, 6, {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		})
		stack = { gui = gui, list = list, order = 0 }
		stacks[key] = stack
	end
	stack.order += 1
	local tag = Components.make("Frame", {
		Name = "Callout",
		LayoutOrder = stack.order,
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Parent = stack.list,
	})
	Components.corner(Theme.TinyCorner).Parent = tag
	local stroke = Components.stroke(color, 1.5, 0.15)
	stroke.Parent = tag
	Components.padding(0, 12, 0, 10).Parent = tag
	Components.list(tag, 8, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
	local bar = Components.make("Frame", {
		Name = "Accent",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(3, 16),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = tag,
	})
	local label = Components.text({
		Name = "Text",
		Text = text,
		LayoutOrder = 2,
		Weight = "Heavy",
		TextSize = 17,
		Color = color,
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.None,
		Parent = tag,
	})
	local scale = Components.make("UIScale", { Scale = 0.6, Parent = tag })
	TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.8, function()
		local out = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(tag, out, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, out, { Transparency = 1 }):Play()
		TweenService:Create(bar, out, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, out, { TextTransparency = 1 }):Play()
		TweenService:Create(scale, out, { Scale = 0.9 }):Play()
		task.delay(0.27, function()
			tag:Destroy()
			if stacks[key] == stack and #stack.list:GetChildren() <= 1 then
				stack.gui:Destroy()
				stacks[key] = nil
			end
		end)
	end)
end

-- Attacks ---------------------------------------------------------------------------------

-- The sequence a move plays: a heavy released out of a charge swings from the coil
local function sequenceFor(model: Model, move: string, fromCharge: boolean?): string
	if (move == "Heavy" or move == "ChargedHeavy") and (fromCharge or Poser.playing(model) == "ChargeHold") then
		return "ChargedStrike"
	end
	return Poser.MoveSequence[move] or "Jab"
end

-- Heavy and a charged heavy are the same swing for skipping the server's echo
local function family(sequence: string): string
	return if sequence == "ChargedStrike" then "Heavy" else sequence
end

local function moveOf(data): string
	if typeof(data.move) == "string" and MOVES[data.move] then
		return data.move
	end
	if data.kind == "Heavy" then
		return "Heavy"
	elseif data.kind == "Sweep" or data.kind == "Grab" then
		return data.kind
	end
	return LIGHT_BY_STEP[math.clamp(math.floor(number(data.step, 1)), 1, 4)]
end

local function handPart(model: Model): BasePart?
	local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm") or rootOf(model)
	return if hand and hand:IsA("BasePart") then hand else nil
end

-- The charge glow at the fist: grows while held, gone on release, feint or hit
function EffectsController:_chargeGlow(model: Model, on: boolean, duration: number?)
	local existing = chargeFx[model]
	if existing then
		for _, item in existing do
			item:Destroy()
		end
		chargeFx[model] = nil
	end
	if not on then
		return
	end
	local hand = handPart(model)
	if not hand then
		return
	end
	local length = duration or Combat.Heavy.Charge.Max
	local attachment = Instance.new("Attachment")
	attachment.Name = "SNChargeGlow"
	attachment.Parent = hand
	local light = Instance.new("PointLight")
	light.Color = CHARGE_COLOR
	light.Range = 5
	light.Brightness = 0.4
	light.Shadows = false
	light.Parent = attachment
	TweenService:Create(light, TweenInfo.new(length, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Range = 11, Brightness = 2.2 }):Play()
	local items: { Instance } = { attachment }
	if not Vfx.reduced() then
		local motes = Instance.new("ParticleEmitter")
		motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		motes.Color = ColorSequence.new(Color3.new(1, 1, 1), CHARGE_COLOR)
		motes.LightEmission = 0.8
		motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		motes.Lifetime = NumberRange.new(0.25, 0.45)
		motes.Speed = NumberRange.new(-2.5, -1)
		motes.SpreadAngle = Vector2.new(180, 180)
		motes.Drag = 4
		motes.Rate = 18
		motes.Parent = attachment
		TweenService:Create(motes, TweenInfo.new(length), { Rate = 45 }):Play()
	end
	chargeFx[model] = items
	-- Never outlives the longest possible charge
	Debris:AddItem(attachment, length + 1)
end

-- Plays a move on a fighter with its sound and swing arc, timed to `timing`
function EffectsController:_playAttack(model: Model, move: string, timing: { number }, delay: number, fromCharge: boolean?)
	local info = MOVES[move] or MOVES.Jab
	local function run()
		local root = rootOf(model)
		if not root or not model.Parent then
			return
		end
		local sequence = sequenceFor(model, move, fromCharge)
		self:_chargeGlow(model, false)
		Poser.sequence(model, sequence, 1, { timing = { startup = timing[1], active = timing[2], recovery = timing[3] } })
		local startup = timing[1]
		if info.telegraph and startup >= 0.25 then
			Vfx.telegraph(root, Colors.Danger, startup)
		end
		-- The whoosh lands just before contact
		task.delay(math.max(0, startup - 0.06), function()
			if root.Parent then
				Vfx.sound(if info.heavySound then "HeavySwing" else "LightSwing", root)
			end
		end)
		task.delay(startup, function()
			if not root.Parent then
				return
			end
			local slash = info.slash
			if slash then
				Vfx.slash(root.CFrame * CFrame.new(0, slash[3], 0), if info.kind == "Heavy" then HEAVY_COLOR else SLASH_COLOR, slash[1], slash[2], if info.kind == "Heavy" then 0.2 else 0.12)
			elseif move == "Sweep" then
				Vfx.groundRing(root.Position - Vector3.new(0, 2.6, 0), DUST_COLOR, 2, 9, 0.3)
			end
		end)
		if move == "Slam" then
			-- The landing: a ring of dust and a thud
			task.delay(startup + timing[2], function()
				if root.Parent then
					Vfx.groundRing(root.Position - Vector3.new(0, 2.8, 0), DUST_COLOR, 2, 12, 0.4)
					Vfx.sound("HeavyHit", root)
				end
			end)
		end
	end
	if delay > 0 then
		task.delay(delay, run)
	else
		run()
	end
end

local function timingOf(def): { number }
	return { number(def.Startup, 0.1), number(def.Active, 0.1), number(def.Recovery, 0.2) }
end

-- Called by CombatController the moment the player presses, so their own
-- character reacts with no network delay. opts.charge: how full a released charge was.
function EffectsController:predictMove(model: Model, move: string, def, delay: number, opts: { [string]: any }?)
	local info = MOVES[move] or MOVES.Jab
	local fromCharge = (move == "Heavy" or move == "ChargedHeavy") and Poser.playing(model) == "ChargeHold"
	local sequence = sequenceFor(model, move, fromCharge)
	predicted[info.kind] = { family = family(sequence), at = os.clock() + delay }
	lastPrediction = { name = sequence, at = os.clock() }
	self:_playAttack(model, move, timingOf(def), delay, fromCharge)
	local _ = opts
end

-- Older callers: kind "Light" with a chain step, or "Heavy"
function EffectsController:predictAttack(model: Model, kind: string, step: number, def, delay: number)
	local move = if kind == "Heavy" then "Heavy" else (def.Move or LIGHT_BY_STEP[math.clamp(step, 1, 4)])
	self:predictMove(model, move, def, delay)
end

function EffectsController:predictCharge(model: Model, duration: number)
	predicted.Charge = { family = "ChargeHold", at = os.clock() }
	lastPrediction = { name = "ChargeHold", at = os.clock() }
	Poser.sequence(model, "ChargeHold", 1, { holdFor = duration + 0.4 })
	self:_chargeGlow(model, true, duration)
	local root = rootOf(model)
	if root then
		Vfx.sound("HeavySwing", root)
	end
end

function EffectsController:cancelCharge(model: Model)
	self:_chargeGlow(model, false)
	if Poser.playing(model) == "ChargeHold" then
		Poser.stop(model)
	end
end

function EffectsController:predictFeint(model: Model)
	predicted.Feint = { family = "Feint", at = os.clock() }
	self:_chargeGlow(model, false)
	Poser.sequence(model, "Feint")
	local root = rootOf(model)
	if root then
		Vfx.sound("Dodge", root)
	end
end

function EffectsController:predictTaunt(model: Model, duration: number)
	predicted.Taunt = { family = "Taunt", at = os.clock() }
	lastPrediction = { name = self:_taunt(model, duration), at = os.clock() }
end

-- Undoes a preview the server refused (only if it's still what's playing)
function EffectsController:cancelPrediction(model: Model)
	local last = lastPrediction
	if last and os.clock() - last.at < 2 and Poser.playing(model) == last.name then
		Poser.stop(model)
		if last.name == "ChargeHold" then
			self:_chargeGlow(model, false)
		end
	end
	lastPrediction = nil
end

function EffectsController:_onAttack(data)
	local model = data.attacker
	if not isModel(model) then
		return
	end
	local move = moveOf(data)
	local info = MOVES[move] or MOVES.Jab
	if isLocal(model) then
		local preview = predicted[info.kind]
		if preview and math.abs(os.clock() - preview.at) < 0.6 and preview.family == family(sequenceFor(model, move)) then
			return
		end
	end
	self:_playAttack(model, move, { number(data.startup, 0.1), number(data.active, 0.1), number(data.recovery, 0.2) }, 0)
end

-- Hits -------------------------------------------------------------------------------------

-- The victim's body reaction to a clean hit
local function react(victim: Model, data, weight: number, tags)
	if tags.knockdown then
		-- The Knockdown motion plays the fall (it may arrive just before or after)
		return
	end
	local side = pushSide(victim, data.direction)
	if tags.wallSplat then
		Poser.sequence(victim, "WallSplat", 0.8 / math.max(0.4, Combat.WallSplat.Stun))
	elseif tags.launch or tags.airborne then
		Poser.sequence(victim, "Launched")
	elseif side == "Back" then
		Poser.sequence(victim, "FlinchBack")
	elseif side == "Left" or side == "Right" then
		Poser.sequence(victim, "FlinchSide", if weight >= 2 then 0.85 else 1, { mirror = side == "Right" })
	elseif weight >= 2 or data.heavy then
		Poser.sequence(victim, "HitHeavy")
	else
		Poser.sequence(victim, "FlinchFront")
	end
end

function EffectsController:_onHit(data)
	local victim, attacker = data.victim, data.attacker
	if not isModel(victim) or typeof(data.position) ~= "Vector3" then
		return
	end
	if not isModel(attacker) then
		attacker = nil
	end
	local position = data.position
	local involved = isLocal(victim) or isLocal(attacker)
	local result = data.result
	local tags = if typeof(data.tags) == "table" then data.tags else {}
	local move = if typeof(data.move) == "string" and MOVES[data.move] then data.move else (if data.heavy then "Heavy" else "Jab")
	local weight = (MOVES[move] or MOVES.Jab).weight
	if data.finisher then
		weight = math.max(weight, 2)
	end
	local direction = if typeof(data.direction) == "Vector3" then data.direction else nil
	local victimSide = isLocal(victim)

	if result == "Clash" then
		-- Drawn by the Clash event
		return
	elseif result == "Hit" then
		self:_chargeGlow(victim, false)
		react(victim, data, weight, tags)
		local stop = hitstopFor(weight, tags)
		Poser.freeze(victim, stop)
		if attacker then
			Poser.freeze(attacker, stop)
		end
		local big = weight >= 2 or tags.counter or tags.wallSplat
		Vfx.flash(victim, Color3.new(1, 1, 1))
		Vfx.sparks(position, if tags.counter then Colors.Gold elseif data.heavy then HEAVY_COLOR else SPARK_COLOR, if big then 28 else 14, if big then 32 else 22)
		if Settings.get("damageNumbers") ~= false and typeof(data.damage) == "number" then
			Vfx.popup(position, tostring(math.floor(data.damage + 0.5)), if big then Colors.Gold else Colors.Text, if big then 1.3 else 1)
		end
		Vfx.sound(if weight >= 2 then "HeavyHit" else "Hit", position)
		if big then
			Vfx.shockwave(position, if tags.counter then Colors.Gold else HEAVY_COLOR, 2, 10, 0.3)
		end
		if tags.counter then
			self:callout(victim, "COUNTER", Colors.Gold)
			Vfx.ring(CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0), 2.5, Colors.Gold, 0.2, 0.3, 7)
		end
		if tags.punish then
			self:callout(victim, "PUNISH", Colors.Danger)
		end
		if tags.riposte then
			self:callout(victim, "RIPOSTE", Colors.Cyan)
		end
		if tags.wallSplat then
			self:callout(victim, "WALL SPLAT", Colors.Warning)
			local wall = position - (if direction then flat(direction).Unit else Vector3.zero) * 1.6
			Vfx.debris(wall, 8, DUST_COLOR, Enum.Material.Slate, 24)
			Vfx.shockwave(wall, DUST_COLOR, 2, 9, 0.35)
			Vfx.sound("HeavyHit", wall)
		end
		local strength = weight * 0.55 * (if victimSide then 1.3 else 1) + (if tags.counter or tags.wallSplat then 0.6 else 0)
		self:_feel(involved, direction, strength, weight >= 2.4 or tags.wallSplat == true)
		if data.armored then
			Vfx.popup(position + Vector3.new(0, 1.5, 0), "ARMOR", Color3.fromRGB(200, 200, 210), 0.8)
		end
	elseif result == "Blocked" then
		Poser.sequence(victim, "BlockImpact")
		Poser.freeze(victim, 0.035)
		if attacker then
			Poser.freeze(attacker, 0.035)
		end
		Vfx.sparks(position, Colors.Guard, 10, 18)
		Vfx.popup(position, "BLOCK", Colors.Guard, 0.8)
		Vfx.sound("Block", position)
		local shield = shields[victim]
		if shield then
			Vfx.shockwave(shield.Position, Colors.Guard, 3, 6, 0.15)
		end
		self:_feel(involved, direction, 0.4 + weight * 0.15, false)
	elseif result == "GuardBreak" then
		Poser.sequence(victim, "GuardBreak", 1.4 / math.max(0.5, Combat.Block.GuardBreakStun))
		Poser.freeze(victim, 0.08)
		if attacker then
			Poser.freeze(attacker, 0.08)
		end
		Vfx.sparks(position, Colors.Guard, 30, 34)
		Vfx.shockwave(position, Colors.Guard, 3, 12, 0.35)
		self:callout(victim, "GUARD BREAK", Colors.Danger)
		Vfx.sound("GuardBreak", position)
		self:_feel(involved, direction, 1.8, true)
	elseif result == "Parried" then
		Poser.sequence(victim, "ParryDeflect")
		if attacker then
			self:_chargeGlow(attacker, false)
			Poser.sequence(attacker, "ParriedRecoil", 1 / math.max(0.4, Combat.Block.ParryStun))
			Poser.freeze(attacker, 0.08)
			Vfx.flash(attacker, Colors.Gold, 0.3)
		end
		Poser.freeze(victim, 0.08)
		Vfx.shockwave(position, Colors.Gold, 2, 8, 0.25)
		Vfx.sparks(position, Colors.Gold, 24, 28)
		self:callout(victim, "PARRY", Colors.Gold)
		Vfx.sound("Parry", position)
		self:_feel(involved, direction, 1.2, false)
		if involved and self.camera then
			self.camera:punch(4)
		end
	elseif result == "Invulnerable" then
		Vfx.popup(position, "DODGE", Colors.TextDim, 0.8)
	elseif result == "Perfect" or result == "PerfectBlock" then
		-- A perfectly timed defense (power defense prompts): the whole attack is negated
		Vfx.shockwave(position, Colors.Gold, 2, 12, 0.35)
		Vfx.ring(CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0), 3, Colors.Gold, 0.25, 0.4, 9)
		Vfx.sparks(position, Colors.Gold, 30, 30)
		self:callout(victim, "PERFECT", Colors.Gold)
		Vfx.sound("Parry", position)
		self:_feel(involved, direction, 1.2, false)
	elseif result == "Good" then
		Vfx.sparks(position, Colors.Cyan, 14, 22)
		self:callout(victim, "GOOD", Colors.Cyan)
	elseif result == "Endured" then
		Vfx.sparks(position, Color3.fromRGB(200, 200, 210), 18, 20)
		self:callout(victim, "ENDURED", Color3.fromRGB(220, 220, 230))
	elseif result == "Countered" then
		Vfx.shockwave(position, Colors.Purple, 2, 10, 0.3)
		self:callout(victim, "COUNTERED", Colors.Purple)
		Vfx.sound("Parry", position)
	end
end

-- Clash: both strikes meet and bounce off
function EffectsController:_onClash(data)
	local a, b = data.a, data.b
	local position = if typeof(data.position) == "Vector3" then data.position else nil
	for _, model in { a, b } do
		if isModel(model) then
			self:_chargeGlow(model, false)
			Poser.sequence(model, "ClashRecoil")
			Poser.freeze(model, 0.08)
		end
	end
	if position then
		Vfx.sparks(position, Color3.fromRGB(235, 245, 255), 26, 30)
		Vfx.ring(CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)), 2, SLASH_COLOR, 0.2, 0.25, 6)
		Vfx.shockwave(position, SLASH_COLOR, 1.5, 7, 0.2)
		Vfx.sound("Parry", position)
		Vfx.sound("Block", position)
		self:callout(position + Vector3.new(0, 2, 0), "CLASH", Colors.Text)
	end
	local mine = if isLocal(a) then a elseif isLocal(b) then b else nil
	if mine then
		local other = if mine == a then b else a
		local myRoot, otherRoot = rootOf(mine), rootOf(if isModel(other) then other else nil)
		local away = if myRoot and otherRoot then flat(myRoot.Position - otherRoot.Position) else nil
		self:_feel(true, away, 1.4, false)
	end
end

-- Grabs ------------------------------------------------------------------------------------

function EffectsController:_onGrab(data)
	local attacker, victim = data.attacker, data.victim
	if not isModel(attacker) then
		return
	end
	if not isModel(victim) then
		victim = nil
	end
	local phase = data.phase
	local involved = isLocal(attacker) or isLocal(victim)
	local hold = Combat.Grab.Hold
	if phase == "Hold" and victim then
		local root = rootOf(attacker)
		local back = false
		if root and typeof(data.direction) == "Vector3" then
			back = flat(data.direction):Dot(flat(root.CFrame.LookVector)) < -0.3
		end
		grabHolds[attacker] = { back = back }
		self:_chargeGlow(victim, false)
		Poser.sequence(attacker, "ClinchHold", 1, { holdFor = hold + 0.4 })
		Poser.sequence(victim, "Clinched", 1, { holdFor = hold + 0.4 })
		Poser.freeze(attacker, 0.05)
		Poser.freeze(victim, 0.05)
		local victimRoot = rootOf(victim)
		if victimRoot then
			Vfx.sound("Block", victimRoot)
		end
		self:_feel(involved, if root and victimRoot then flat(victimRoot.Position - root.Position) else nil, 0.8, false)
	elseif phase == "Throw" then
		local held = grabHolds[attacker]
		grabHolds[attacker] = nil
		Poser.sequence(attacker, if held and held.back then "ThrowBack" else "ThrowForward")
		if victim then
			Poser.sequence(victim, "Thrown")
		end
		local root = rootOf(attacker)
		if root then
			Vfx.sound("HeavySwing", root)
		end
	elseif phase == "Tech" then
		grabHolds[attacker] = nil
		Poser.sequence(attacker, "TechBreak")
		Poser.freeze(attacker, 0.06)
		local point = nil
		if victim then
			Poser.sequence(victim, "TechBreak")
			Poser.freeze(victim, 0.06)
			local a, b = rootOf(attacker), rootOf(victim)
			if a and b then
				point = (a.Position + b.Position) / 2
			end
			self:callout(victim, "TECH", Colors.Cyan)
		end
		if point then
			Vfx.sparks(point, Colors.Cyan, 16, 22)
			Vfx.shockwave(point, Colors.Cyan, 1.5, 7, 0.25)
			Vfx.sound("Parry", point)
		end
		self:_feel(involved, nil, 0.9, false)
	elseif phase == "Whiff" then
		grabHolds[attacker] = nil
		-- A broken hold lets both go; a plain miss already stumbles in the Grab move
		if victim then
			if Poser.playing(attacker) == "ClinchHold" then
				Poser.stop(attacker)
			end
			if Poser.playing(victim) == "Clinched" then
				Poser.stop(victim)
			end
		end
	end
end

-- Dodges and other movement ---------------------------------------------------------------

function EffectsController:_dodgeVisuals(model: Model, style: string?, direction: Vector3?)
	local root = rootOf(model)
	local sequence, mirror = "DodgeBack", false
	if style == "Forward" then
		sequence = "DodgeForward"
	elseif style == "Side" then
		sequence = "DodgeSide"
		if root and direction then
			mirror = root.CFrame:VectorToObjectSpace(direction).X > 0
		end
	end
	Poser.sequence(model, sequence, 1, { mirror = mirror })
	Vfx.afterimage(model, Colors.Cyan)
	if root then
		Vfx.sound("Dodge", root)
		task.delay(0.09, function()
			if model.Parent then
				Vfx.afterimage(model, Colors.Purple)
			end
		end)
	end
end

function EffectsController:predictDodge(model: Model, style: string?, direction: Vector3?)
	predicted.Dodge = { family = style or "Back", at = os.clock() }
	lastPrediction = { name = if style == "Forward" then "DodgeForward" elseif style == "Side" then "DodgeSide" else "DodgeBack", at = os.clock() }
	self:_dodgeVisuals(model, style, direction)
end

function EffectsController:_onDodge(data)
	local fighter = data.fighter
	if not isModel(fighter) then
		return
	end
	local style = if typeof(data.style) == "string" then data.style else "Back"
	local direction = if typeof(data.direction) == "Vector3" then data.direction else nil
	if isLocal(fighter) then
		local preview = predicted.Dodge
		if preview and os.clock() - preview.at < 0.6 and preview.family == style then
			return
		end
	end
	self:_dodgeVisuals(fighter, style, direction)
end

-- The next taunt for a fighter (they take turns)
function EffectsController:_taunt(model: Model, duration: number): string
	local count = (tauntCount[model] or 0) + 1
	tauntCount[model] = count
	local name = Poser.Taunts[(count - 1) % #Poser.Taunts + 1]
	Poser.sequence(model, name, 1.4 / math.max(0.3, duration))
	return name
end

-- The local player's own slow-motion moment after a perfect dodge
local perfectToken = 0
function EffectsController:_perfectDodge(attacker: Model?)
	perfectToken += 1
	local token = perfectToken
	Poser.setTimeScale(0.35, 0.42)
	if self.camera then
		self.camera:punch(-6)
	end
	local character = player.Character
	local root = rootOf(character)
	if root then
		Vfx.sound("Dodge", root)
		Vfx.sound("Parry", root)
	end
	if character then
		self:callout(character, "PERFECT", Colors.Cyan)
	end
	if attacker then
		Vfx.flash(attacker, Colors.Cyan, 0.45)
	end
	local tint = Lighting:FindFirstChild("SNPerfectDodge")
	if not tint then
		tint = Instance.new("ColorCorrectionEffect")
		tint.Name = "SNPerfectDodge"
		tint.Parent = Lighting
	end
	local effect = tint :: ColorCorrectionEffect
	local intense = Vfx.intense()
	TweenService:Create(effect, TweenInfo.new(0.06), {
		Saturation = if intense then -0.55 else -0.2,
		Contrast = if intense then 0.12 else 0.05,
		TintColor = if intense then Color3.fromRGB(205, 232, 255) else Color3.new(1, 1, 1),
	}):Play()
	task.delay(0.4, function()
		if token ~= perfectToken then
			return
		end
		TweenService:Create(effect, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Saturation = 0,
			Contrast = 0,
			TintColor = Color3.new(1, 1, 1),
		}):Play()
		task.delay(0.4, function()
			if token == perfectToken and effect.Parent then
				effect:Destroy()
			end
		end)
	end)
end

function EffectsController:_onMotion(data)
	local fighter = data.fighter
	if not isModel(fighter) then
		return
	end
	local motion = data.motion
	local root = rootOf(fighter)
	local duration = number(data.duration, 0)
	local direction = if typeof(data.direction) == "Vector3" then data.direction else nil
	local mine = isLocal(fighter)
	local function previewed(name: string): boolean
		local preview = predicted[name]
		return mine and preview ~= nil and os.clock() - preview.at < 0.6
	end

	if motion == "Charge" then
		if not previewed("Charge") then
			Poser.sequence(fighter, "ChargeHold", 1, { holdFor = duration + 0.4 })
			self:_chargeGlow(fighter, true, duration)
		end
	elseif motion == "Feint" then
		self:_chargeGlow(fighter, false)
		if not previewed("Feint") then
			Poser.sequence(fighter, "Feint")
			if root then
				Vfx.sound("Dodge", root)
			end
		end
	elseif motion == "Knockdown" then
		self:_chargeGlow(fighter, false)
		local side = pushSide(fighter, direction)
		local pose = if side == "Back" then "Front" else "Back"
		downedPose[fighter] = pose
		Poser.sequence(fighter, "Knockdown" .. pose, 1, { holdFor = duration + 0.3 })
		task.delay(0.34, function()
			local current = rootOf(fighter)
			if current and fighter.Parent then
				Vfx.groundRing(current.Position - Vector3.new(0, 2.8, 0), DUST_COLOR, 2, 9, 0.45)
				Vfx.sound("HeavyHit", current)
			end
		end)
		if mine and self.camera then
			self.camera:kick(direction, 1.4)
		end
	elseif motion == "GetUp" then
		local playing = Poser.playing(fighter)
		if playing == "KnockdownBack" or playing == "KnockdownFront" then
			Poser.advance(fighter)
		end
	elseif motion == "TechRoll" then
		local sequence, mirror = "TechRollBack", false
		local pose = downedPose[fighter] or "Back"
		if pose == "Front" then
			sequence = "TechRollForward"
		elseif root and direction then
			local relative = root.CFrame:VectorToObjectSpace(flat(direction))
			if relative.Z < -0.5 then
				sequence = "TechKipUp"
			elseif math.abs(relative.X) > math.abs(relative.Z) then
				sequence, mirror = "TechRollSide", relative.X > 0
			end
		end
		Poser.sequence(fighter, sequence, 1, { mirror = mirror })
		Vfx.afterimage(fighter, Colors.Cyan)
		self:callout(fighter, "TECH", Colors.Cyan)
		if root then
			Vfx.sound("Dodge", root)
		end
	elseif motion == "Breakfall" then
		Poser.sequence(fighter, "Breakfall")
		Vfx.afterimage(fighter, Colors.Cyan)
		self:callout(fighter, "TECH", Colors.Cyan)
		if root then
			Vfx.sound("Dodge", root)
		end
	elseif motion == "Taunt" then
		if not previewed("Taunt") then
			self:_taunt(fighter, if duration > 0 then duration else Combat.Taunt.Duration)
		end
	elseif motion == "TauntDone" then
		if root then
			Vfx.glow(root, Colors.Gold, 8, 1.4, 0.45)
			Vfx.sparks(root.Position + Vector3.new(0, 1, 0), Colors.Gold, 10, 10)
		end
	elseif motion == "Winded" then
		if Poser.playing(fighter) == nil then
			Poser.sequence(fighter, "Winded")
		end
		self:callout(fighter, "WINDED", Colors.Warning)
	elseif motion == "PickUp" then
		if root then
			Vfx.sound("Block", root)
		end
	elseif motion == "PerfectDodge" then
		local attacker = if isModel(data.attacker) then data.attacker else nil
		if mine then
			self:_perfectDodge(attacker)
		elseif attacker then
			Vfx.flash(attacker, Colors.Cyan, 0.3)
		end
	elseif motion == "DodgeCancel" then
		Vfx.flash(fighter, Colors.Cyan, 0.15)
	elseif motion == "SprintStart" then
		if root and not Vfx.reduced() then
			Vfx.groundRing(root.Position - Vector3.new(0, 2.8, 0), DUST_COLOR, 1, 5, 0.3)
		end
	end
	-- Recovered, Drop and SprintEnd show through the HUD and the held poses
end

-- Blocking shields and overhead bars ---------------------------------------------

function EffectsController:_setShield(model: Model, on: boolean)
	local existing = shields[model]
	if on and not existing then
		local shield = Instance.new("Part")
		shield.Shape = Enum.PartType.Ball
		shield.Size = Vector3.one * 5.5
		shield.Anchored = true
		shield.CanCollide = false
		shield.CanQuery = false
		shield.CanTouch = false
		shield.CastShadow = false
		shield.Material = Enum.Material.ForceField
		shield.Color = Colors.Guard
		shield.Transparency = 0.2
		shield.Parent = workspace.CurrentCamera
		shields[model] = shield
		-- The local player's own block pose follows their button (CombatController)
		if not isLocal(model) then
			Poser.hold(model, "Block")
		end
	elseif not on and existing then
		existing:Destroy()
		shields[model] = nil
		if not isLocal(model) then
			Poser.release(model, "Block")
		end
	end
end

function EffectsController:_watchFighter(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local connections = {}
	local function refreshShield()
		self:_setShield(model, model:GetAttribute(Attribute.Blocking) == true and model.Parent ~= nil)
	end
	table.insert(connections, model:GetAttributeChangedSignal(Attribute.Blocking):Connect(refreshShield))
	refreshShield()

	-- Held poses that follow the server's state: carrying a prop overhead, the
	-- sprint lean, and the charge glow (for everyone; the local player's charge
	-- is previewed on the press)
	local function holdWhile(attribute: string, pose: string)
		local function refresh()
			local on = model:GetAttribute(attribute)
			if on ~= nil and on ~= false and model.Parent then
				Poser.hold(model, pose)
			else
				Poser.release(model, pose)
			end
		end
		table.insert(connections, model:GetAttributeChangedSignal(attribute):Connect(refresh))
		refresh()
	end
	holdWhile(Attribute.Carrying, "Carry")
	holdWhile(Attribute.Sprinting, "SprintLean")
	table.insert(connections, model:GetAttributeChangedSignal(Attribute.ChargeStart):Connect(function()
		local started = model:GetAttribute(Attribute.ChargeStart)
		if started == nil then
			self:_chargeGlow(model, false)
		elseif not chargeFx[model] then
			self:_chargeGlow(model, true, math.max(0.1, Combat.Heavy.Charge.Max - (now() - started)))
		end
	end))

	if not isLocal(model) then
		self:_createOverhead(model)
	end

	table.insert(connections, model.AncestryChanged:Connect(function()
		if model:IsDescendantOf(workspace) then
			return
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		self:_setShield(model, false)
		self:_chargeGlow(model, false)
		local overhead = overheads[model]
		if overhead then
			overhead.gui:Destroy()
			overheads[model] = nil
		end
	end))
end

function EffectsController:_createOverhead(model: Model)
	if overheads[model] then
		return
	end
	local head = model:FindFirstChild("Head") or rootOf(model)
	if not head then
		return
	end
	local gui = Components.make("BillboardGui", {
		Name = "SNOverhead",
		Size = UDim2.fromOffset(150, 46),
		StudsOffset = Vector3.new(0, 2.6, 0),
		MaxDistance = 110,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Adornee = head,
	})
	local displayName = model:GetAttribute(Attribute.DisplayName)
	Components.label(if typeof(displayName) == "string" then displayName else model.Name, {
		Size = UDim2.new(1, 0, 0, 16),
		Font = Theme.Fonts.Heading,
		TextColor3 = Colors.Text,
		TextStrokeTransparency = 0.4,
		MaxTextSize = 15,
		Parent = gui,
	})
	local healthBar, setHealth = Components.bar({
		Size = UDim2.new(1, 0, 0, 9),
		Position = UDim2.fromOffset(0, 18),
		Parent = gui,
	}, Colors.Health)
	local guardBar, setGuard = Components.bar({
		Size = UDim2.new(1, 0, 0, 4),
		Position = UDim2.fromOffset(0, 29),
		Parent = gui,
	}, Colors.Guard)
	local status = Components.label("", {
		Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.fromOffset(0, 34),
		Font = Theme.Fonts.Heading,
		TextColor3 = Colors.Gold,
		TextStrokeTransparency = 0.5,
		MaxTextSize = 11,
		Parent = gui,
	})
	gui.Parent = workspace.CurrentCamera
	overheads[model] = { gui = gui, setHealth = setHealth, setGuard = setGuard, status = status }
	local _ = healthBar
	local _ = guardBar
end

function EffectsController:_updateOverheads()
	local time = now()
	for model, overhead in overheads do
		-- The owner's invisibility hides their name and bars too
		local owner = Players:GetPlayerFromCharacter(model)
		overhead.gui.Enabled = not (owner and owner:GetAttribute(Attribute.Invisible) == true)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local fraction = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 0
			overhead.setHealth(fraction, if fraction < 0.3 then Colors.HealthLow else Colors.Health)
		end
		local maxGuard = model:GetAttribute(Attribute.MaxGuard) or Combat.Block.MaxGuard
		overhead.setGuard(currentGuard(model) / math.max(1, maxGuard))
		-- Concealed fighters (the Ghost's veil) don't give themselves away with a name tag
		local concealed = time < (model:GetAttribute(Attribute.StatusPrefix .. "Concealed") or 0)
		if concealed then
			overhead.gui.Enabled = false
		end
		local text = ""
		local function active(statusId: string): boolean
			return time < (model:GetAttribute(Attribute.StatusPrefix .. statusId) or 0)
		end
		if active("Grabbed") then
			text = "GRABBED"
		elseif active("Freeze") then
			text = "FROZEN"
		elseif active("Trapped") then
			text = "TRAPPED"
		elseif time < (model:GetAttribute(Attribute.DownedUntil) or 0) then
			text = "DOWN"
		elseif time < (model:GetAttribute(Attribute.StunnedUntil) or 0) then
			text = "STUNNED"
		elseif model:GetAttribute(Attribute.Winded) == true then
			text = "WINDED"
		elseif active("Sealed") then
			text = "SEALED"
		elseif active("Root") then
			text = "ROOTED"
		elseif model:GetAttribute(Attribute.Blocking) then
			text = "GUARDING"
		elseif time < (model:GetAttribute(Attribute.ProtectedUntil) or 0) then
			text = "PROTECTED"
		elseif active("Mark") then
			text = "MARKED"
		elseif active("Slow") then
			text = "SLOWED"
		end
		overhead.status.Text = text
	end
end

return EffectsController
