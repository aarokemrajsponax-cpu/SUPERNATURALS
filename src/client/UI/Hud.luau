-- The player's own status at the bottom centre of the screen, from the top:
--   ability row   the ability bar (up to 6 buttons, 64x64) goes here
--   vitals        name, health bar with the number inside, then guard and
--                 stamina side by side (stamina turns orange when low and red
--                 with WINDED when it runs out)
--   controls      a compact strip of key hints for keyboard or gamepad with
--                 cooldown sweeps (hidden on touch, where the touch buttons show them)
-- Plus, away from the strip: a charge meter under the crosshair while a heavy
-- charges, and corner brackets over the lock-on target.
-- Everything sits on the 8 px grid. Nothing here catches clicks, so clicking
-- near the HUD still attacks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local Attribute = Protocol.Attribute
local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make

local player = Players.LocalPlayer

local Hud = {}

local WIDTH = 460
local ABILITY_SIZE = 64
local ABILITY_SLOTS = 6
local VITALS_HEIGHT = 80
local CHIP_WIDTH = 52
local CHIP_HEIGHT = 44
local CHIP_GAP = 4
-- On touch the HUD moves left a little to leave room for the button cluster
local TOUCH_SHIFT = -48
-- Health turns red below this fraction; stamina turns orange below this one
local LOW_HEALTH = 0.3
local LOW_STAMINA = 0.25
local STAMINA_COLOR = Color3.fromRGB(240, 214, 140)
local CHARGE_COLOR = Color3.fromRGB(255, 196, 112)

Hud.Layout = {
	width = WIDTH,
	touchShift = TOUCH_SHIFT,
	-- Height on touch (ability row, gap, vitals) and the gap under it, in design px
	touchHeight = ABILITY_SIZE + Space.S + VITALS_HEIGHT,
	bottom = Space.L,
}

type Chip = { frame: Frame, key: TextLabel, cooldown: Frame, timer: TextLabel, outline: UIStroke, binding: any }

-- A glass chip that doesn't catch input
local function glass(props: { [string]: any }): Frame
	local merged: { [string]: any } = {
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.22,
		BorderSizePixel = 0,
	}
	for key, value in props do
		merged[key] = value
	end
	return make("Frame", merged, {
		Components.corner(Theme.SmallCorner),
		Components.glassGradient(),
	})
end

-- A caption with a thin bar after it (guard, stamina)
local function meter(parent: Instance, name: string, caption: string, position: UDim2, color: Color3)
	local holder = make("Frame", {
		Name = name,
		Position = position,
		Size = UDim2.new(0.5, -Space.S / 2, 0, 16),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local label = Components.text({
		Name = "Caption",
		Text = caption,
		Style = "Micro",
		Color = Colors.TextMuted,
		Size = UDim2.new(0, 60, 1, 0),
		Parent = holder,
	})
	local bar, set = Components.bar({
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 64, 0.5, 0),
		Size = UDim2.new(1, -64, 0, 6),
		Parent = holder,
	}, color)
	return holder, label, bar, set
end

-- Lazily: the controllers this reads live state from (charge, lock-on)
local function controller(name: string): any
	local folder = script.Parent.Parent:FindFirstChild("Controllers")
	local module = folder and folder:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

function Hud.build(parent: Instance, bindings: { any }, device: () -> string, currentGuard: (Model) -> number)
	local frame = make("Frame", {
		Name = "Hud",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Space.L),
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Components.list(frame, Space.S, { HorizontalAlignment = Enum.HorizontalAlignment.Center })

	-- The ability bar's home: centred, room for six 64x64 buttons
	local abilityRow = make("Frame", {
		Name = "AbilityRow",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(ABILITY_SLOTS * ABILITY_SIZE + (ABILITY_SLOTS - 1) * Space.S, ABILITY_SIZE),
		BackgroundTransparency = 1,
	})
	Components.list(abilityRow, Space.S, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	abilityRow.Parent = frame

	-- Vitals ---------------------------------------------------------------------------
	-- 8 padding, name 18, gap 4, health 22, gap 6, guard/stamina 16, 6 padding = 80
	local vitals = glass({
		Name = "Vitals",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, VITALS_HEIGHT),
		Parent = frame,
	})
	local vitalsStroke = Components.stroke(Colors.Stroke, 1, 0.75)
	vitalsStroke.Parent = vitals
	Components.padding(Space.S, Space.M, Space.S - 2, Space.M).Parent = vitals
	local nameLabel = Components.text({
		Name = "PlayerName",
		Text = player.DisplayName,
		Style = "Label",
		Size = UDim2.new(1, -96, 0, 18),
		Parent = vitals,
	})
	local healthCaption = Components.text({
		Name = "HealthCaption",
		Text = "HEALTH",
		Style = "Micro",
		Color = Colors.TextMuted,
		AlignX = "Right",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(88, 18),
		Parent = vitals,
	})
	local healthBar, setHealth = Components.bar({
		Name = "Health",
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = vitals,
	}, Colors.Health)
	Components.stroke(Colors.Ink, 1.5, 0.2).Parent = healthBar
	local healthText = Components.text({
		Name = "Amount",
		Text = "100",
		Style = "Label",
		Weight = "ExtraBold",
		TextSize = 15,
		AlignX = "Right",
		TextStrokeTransparency = 0.35,
		TextStrokeColor3 = Colors.Ink,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = healthBar,
	})
	Components.padding(0, Space.S, 0, Space.S).Parent = healthText
	local _, _, _, setGuard = meter(vitals, "Guard", "GUARD", UDim2.fromOffset(0, 50), Colors.Guard)
	local _, staminaCaption, staminaBar, setStamina = meter(vitals, "Stamina", "STAMINA", UDim2.new(0.5, Space.S / 2, 0, 50), STAMINA_COLOR)
	local staminaStroke = Components.stroke(Colors.Danger, 1, 1)
	staminaStroke.Parent = staminaBar

	-- Controls hint strip -------------------------------------------------------------
	local hinted = {}
	for _, binding in bindings do
		if binding.hint ~= false then
			table.insert(hinted, binding)
		end
	end
	local row = make("Frame", {
		Name = "Actions",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, CHIP_HEIGHT),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	Components.list(row, CHIP_GAP, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})

	local chips: { [string]: Chip } = {}
	for order, binding in hinted do
		local chip = glass({
			Name = binding.name,
			LayoutOrder = order,
			Size = UDim2.fromOffset(CHIP_WIDTH, CHIP_HEIGHT),
			ClipsDescendants = true,
			Parent = row,
		})
		local outline = Components.stroke(Colors.Stroke, 1, 0.7)
		outline.Parent = chip
		-- Key cap on top, action name under it
		local keyBox = make("Frame", {
			Name = "Key",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 5),
			Size = UDim2.fromOffset(CHIP_WIDTH - 8, 18),
			BackgroundColor3 = Colors.Cyan,
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			Parent = chip,
		}, { Components.corner(Theme.TinyCorner), Components.stroke(Colors.Cyan, 1, 0.4) })
		local key = Components.text({
			Text = binding.keyText,
			Style = "Micro",
			Weight = "ExtraBold",
			Color = Colors.Cyan,
			AlignX = "Center",
			Size = UDim2.fromScale(1, 1),
			Parent = keyBox,
		})
		Components.text({
			Name = "Label",
			Text = string.upper(binding.label),
			Style = "Micro",
			Weight = "Bold",
			Color = Colors.Text,
			AlignX = "Center",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -4, 0, 14),
			Parent = chip,
		})
		-- Cooldown: a dark sweep that shrinks to the left, with the seconds left
		local cooldown = make("Frame", {
			Name = "Cooldown",
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = chip,
		}, { Components.corner(Theme.SmallCorner) })
		local timer = Components.text({
			Name = "Timer",
			Style = "Label",
			Weight = "ExtraBold",
			AlignX = "Center",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 6,
			Visible = false,
			Parent = chip,
		})
		chips[binding.name] = { frame = chip, key = key, cooldown = cooldown, timer = timer, outline = outline, binding = binding }
	end

	-- Charge meter: under the crosshair while a heavy charges --------------------------
	local chargeFrame = make("Frame", {
		Name = "ChargeMeter",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, Space.XL * 2),
		Size = UDim2.fromOffset(176, 32),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})
	local chargeCaption = Components.text({
		Name = "Caption",
		Text = "CHARGE",
		Style = "Micro",
		Weight = "ExtraBold",
		Color = CHARGE_COLOR,
		AlignX = "Center",
		Size = UDim2.new(1, 0, 0, 16),
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = Colors.Ink,
		Parent = chargeFrame,
	})
	local chargeBar, setCharge = Components.bar({
		Name = "Bar",
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 8),
		Parent = chargeFrame,
	}, CHARGE_COLOR)
	local chargeStroke = Components.stroke(Colors.Ink, 1, 0.3)
	chargeStroke.Parent = chargeBar
	-- The point where a tap becomes a charge
	local chargeTick = make("Frame", {
		Name = "Tick",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(Combat.Heavy.Charge.Min / Combat.Heavy.Charge.Max, 0.5),
		Size = UDim2.new(0, 2, 1, 4),
		BackgroundColor3 = Colors.Text,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = chargeBar,
	})

	-- Lock-on reticle: corner brackets over the target ---------------------------------
	local reticleParent = parent:FindFirstAncestorOfClass("PlayerGui") or parent
	local reticle = make("BillboardGui", {
		Name = "SNLockReticle",
		Size = UDim2.fromOffset(64, 64),
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Enabled = false,
		Parent = reticleParent,
	})
	local reticleFrame = make("Frame", {
		Name = "Brackets",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(48, 48),
		BackgroundTransparency = 1,
		Parent = reticle,
	})
	local reticleScale = make("UIScale", { Parent = reticleFrame })
	for _, corner in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local anchor = Vector2.new(corner[1], corner[2])
		for _, size in { UDim2.fromOffset(12, 2), UDim2.fromOffset(2, 12) } do
			make("Frame", {
				Name = "Bracket",
				AnchorPoint = anchor,
				Position = UDim2.fromScale(corner[1], corner[2]),
				Size = size,
				BackgroundColor3 = Colors.Cyan,
				BorderSizePixel = 0,
				Parent = reticleFrame,
			})
		end
	end
	make("Frame", {
		Name = "Centre",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		Rotation = 45,
		BackgroundColor3 = Colors.Cyan,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Parent = reticleFrame,
	})
	local reticleTarget: Model? = nil

	local cooldowns = {
		SNHeavy = { attribute = Attribute.HeavyReadyAt, length = function(profile)
			return profile.Heavy.Cooldown
		end },
		SNDodge = { attribute = Attribute.DodgeReadyAt, length = function(profile)
			return profile.Dodge.Cooldown
		end },
	}

	local function update()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		frame.Visible = humanoid ~= nil
		local combat = controller("CombatController")
		local camera = controller("CameraController")

		-- Lock-on reticle
		local target = if camera and camera.getLockTarget then camera:getLockTarget() else nil
		local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
		reticle.Enabled = targetRoot ~= nil
		if targetRoot and reticle.Adornee ~= targetRoot then
			reticle.Adornee = targetRoot
		end
		if target ~= reticleTarget then
			reticleTarget = target
			if target then
				reticleScale.Scale = 1.5
				TweenService:Create(reticleScale, Theme.Motion.Pop, { Scale = 1 }):Play()
			end
		end

		if not character or not humanoid then
			chargeFrame.Visible = false
			return
		end
		local kind = device()
		frame.Position = UDim2.new(0.5, if kind == "touch" then TOUCH_SHIFT else 0, 1, -Space.L)
		nameLabel.Text = player.DisplayName
		local fraction = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 0
		local low = fraction < LOW_HEALTH
		setHealth(fraction, if low then Colors.HealthLow else Colors.Health)
		healthText.Text = `{math.max(0, math.ceil(humanoid.Health))} / {math.ceil(humanoid.MaxHealth)}`
		healthCaption.TextColor3 = if low then Colors.HealthLow else Colors.TextMuted
		vitalsStroke.Color = if low then Colors.HealthLow else Colors.Stroke
		vitalsStroke.Transparency = if low then 0.3 else 0.75
		local maxGuard = character:GetAttribute(Attribute.MaxGuard) or Combat.Block.MaxGuard
		setGuard(currentGuard(character) / math.max(1, maxGuard))

		-- Stamina: low turns orange, empty turns red and says so
		local stamina = character:GetAttribute(Attribute.Stamina)
		local staminaMax = character:GetAttribute(Attribute.StaminaMax)
		local maxValue = if typeof(staminaMax) == "number" and staminaMax > 0 then staminaMax else Combat.Stamina.Max
		local share = if typeof(stamina) == "number" then math.clamp(stamina / maxValue, 0, 1) else 1
		local isWinded = character:GetAttribute(Attribute.Winded) == true
		local refused = combat ~= nil and os.clock() - (combat.lastWindedReject or -math.huge) < 0.6
		local staminaColor = if isWinded then Colors.Danger elseif share < LOW_STAMINA then Colors.Warning else STAMINA_COLOR
		setStamina(share, staminaColor)
		staminaCaption.Text = if isWinded then "WINDED" else "STAMINA"
		staminaCaption.TextColor3 = if isWinded then Colors.Danger elseif share < LOW_STAMINA then Colors.Warning else Colors.TextMuted
		-- A refused dodge or sprint flashes the bar's outline
		staminaStroke.Transparency = if refused or isWinded then (if refused and os.clock() % 0.2 < 0.1 then 0 else 0.35) else 1

		-- Charge meter (the local preview first, then the server's charge)
		local level, minShare = nil, Combat.Heavy.Charge.Min / Combat.Heavy.Charge.Max
		if combat and combat.chargeLevel then
			level, minShare = combat:chargeLevel()
		end
		local chargeStart = character:GetAttribute(Attribute.ChargeStart)
		if level == nil and typeof(chargeStart) == "number" then
			level = math.clamp((workspace:GetServerTimeNow() - chargeStart) / Combat.Heavy.Charge.Max, 0, 1)
		end
		chargeFrame.Visible = level ~= nil
		if level then
			local full = level >= 0.999
			setCharge(level, if full then Colors.Gold else CHARGE_COLOR)
			chargeCaption.Text = if full then "FULL CHARGE" elseif level < minShare then "CHARGE" else "CHARGED"
			chargeCaption.TextColor3 = if full then Colors.Gold else CHARGE_COLOR
			chargeStroke.Color = if full then Colors.Gold else Colors.Ink
			chargeTick.Position = UDim2.fromScale(minShare, 0.5)
		end

		-- Hint strip
		row.Visible = kind ~= "touch"
		local time = workspace:GetServerTimeNow()
		local powerId = character:GetAttribute(Attribute.Power)
		local profile = Powers.combatProfile(
			if typeof(powerId) == "string" then powerId else nil,
			character:GetAttribute(Attribute.Degree),
			character:GetAttribute(Attribute.Form)
		)
		for name, chip in chips do
			chip.key.Text = if kind == "gamepad" then chip.binding.padText else chip.binding.keyText
			local spec = cooldowns[name]
			local remaining = if spec then (character:GetAttribute(spec.attribute) or 0) - time else 0
			local sweep = math.clamp(remaining / (if spec then math.max(0.1, spec.length(profile)) else 1), 0, 1)
			if combat and not spec and combat.isReady and not combat:isReady(name) then
				sweep = 1
			end
			chip.cooldown.Size = UDim2.fromScale(sweep, 1)
			chip.timer.Visible = remaining > 0.05
			if remaining > 0.05 then
				chip.timer.Text = string.format("%.1f", remaining)
			end
			local lit = (name == "SNBlock" and character:GetAttribute(Attribute.Blocking) == true)
				or (name == "SNSprint" and character:GetAttribute(Attribute.Sprinting) == true)
				or (name == "SNLock" and target ~= nil)
			chip.outline.Color = if lit then (if name == "SNBlock" then Colors.Guard else Colors.Cyan) else Colors.Stroke
			chip.outline.Transparency = if lit then 0 else 0.7
		end
	end

	return { frame = frame, update = update, abilityRow = abilityRow, chargeMeter = chargeFrame, reticle = reticle }
end

return Hud
