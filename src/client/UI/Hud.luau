-- The player's own status at the bottom centre of the screen, from the top:
--   ability row   the ability bar (up to 6 buttons, 64x64) goes here
--   vitals        a navy plate: name and health numbers, the health bar, then guard
--                 and stamina side by side (stamina turns amber when low and red
--                 with WINDED when it runs out)
--   controls      a neat row of key caps for keyboard or gamepad, each with what
--                 it does and a small cooldown sweep (hidden on touch, where the
--                 touch buttons show them)
-- Plus, away from the strip: a charge meter under the crosshair while a heavy
-- charges, and corner brackets over the lock-on target.
-- Everything sits on the 8 px grid and follows Theme. Nothing here catches clicks,
-- so clicking near the HUD still attacks.

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
local CAP_CELL = 56
local CAP_HEIGHT = 28
local CELL_HEIGHT = 50
-- On touch the HUD moves left a little to leave room for the button cluster
local TOUCH_SHIFT = -48
-- Health turns red below this fraction; stamina turns amber below this one
local LOW_HEALTH = 0.3
local LOW_STAMINA = 0.25
local CHARGE_COLOR = Colors.Accent

Hud.Layout = {
	width = WIDTH,
	touchShift = TOUCH_SHIFT,
	-- Height on touch (ability row, gap, vitals) and the gap under it, in design px
	touchHeight = ABILITY_SIZE + Space.S + VITALS_HEIGHT,
	bottom = Space.L,
}

type Chip = { frame: Frame, cap: Frame, key: TextLabel, sweep: (number) -> (), outline: UIStroke, binding: any }

-- A navy plate that doesn't catch input
local function glass(props: { [string]: any }): Frame
	local merged: { [string]: any } = {
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = Theme.Glass.Panel,
		BorderSizePixel = 0,
		Active = false,
	}
	for key, value in props do
		merged[key] = value
	end
	return make("Frame", merged, {
		Components.corner(Theme.SmallCorner),
		Components.stroke(Colors.Stroke, 1, 0.6),
	})
end

-- A caption with a thin bar after it (guard, stamina)
local function meter(parent: Instance, name: string, caption: string, position: UDim2, color: Color3)
	local holder = make("Frame", {
		Name = name,
		Position = position,
		Size = UDim2.new(0.5, -Space.S / 2, 0, 18),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local label = Components.text({
		Name = "Caption",
		Text = caption,
		Style = "caption",
		Weight = "SemiBold",
		Color = Colors.TextMuted,
		Size = UDim2.new(0, 72, 1, 0),
		Parent = holder,
	})
	local bar, set = Components.bar({
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 76, 0.5, 0),
		Size = UDim2.new(1, -76, 0, 6),
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
	require(script.Parent.PhaseMeter).mount(frame)

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
	-- 8 padding, name 22, gap 4, health 12, gap 8, guard/stamina 18, 8 padding = 80
	local vitals = glass({
		Name = "Vitals",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, VITALS_HEIGHT),
		Parent = frame,
	})
	local vitalsStroke = vitals:FindFirstChildOfClass("UIStroke") :: UIStroke
	Components.padding(Space.S, Space.L - 2, Space.S, Space.L - 2).Parent = vitals
	local nameLabel = Components.text({
		Name = "PlayerName",
		Text = player.DisplayName,
		Style = "strong",
		Size = UDim2.new(1, -120, 0, 22),
		Parent = vitals,
	})
	local healthText = Components.text({
		Name = "Amount",
		Text = "100 / 100",
		Style = "number",
		AlignX = "Right",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(116, 22),
		Parent = vitals,
	})
	local healthBar, setHealth = Components.bar({
		Name = "Health",
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 12),
		Parent = vitals,
	}, Colors.Health)
	Components.stroke(Colors.Stroke, 1, 0.75).Parent = healthBar
	local _, _, _, setGuard = meter(vitals, "Guard", "GUARD", UDim2.fromOffset(0, 46), Colors.Guard)
	local _, staminaCaption, staminaBar, setStamina = meter(vitals, "Stamina", "STAMINA", UDim2.new(0.5, Space.S / 2, 0, 46), Colors.Stamina)
	local staminaStroke = Components.stroke(Colors.Danger, 1, 1)
	staminaStroke.Parent = staminaBar

	-- Controls: a row of key caps, each with what it does -------------------------------
	local hinted = {}
	for _, binding in bindings do
		if binding.hint ~= false then
			table.insert(hinted, binding)
		end
	end
	local row = make("Frame", {
		Name = "Actions",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, CELL_HEIGHT),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	Components.list(row, 0, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})

	local chips: { [string]: Chip } = {}
	for order, binding in hinted do
		local cell = make("Frame", {
			Name = binding.name,
			LayoutOrder = order,
			Size = UDim2.fromOffset(CAP_CELL, CELL_HEIGHT),
			BackgroundTransparency = 1,
			Parent = row,
		})
		-- The cap sits at the top of its cell, the label under it
		local cap = Components.keycap(binding.keyText, {
			Name = "Cap",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Height = CAP_HEIGHT,
			Parent = cell,
		})
		local outline = cap:FindFirstChildOfClass("UIStroke") :: UIStroke
		local key = cap:FindFirstChild("Key") :: TextLabel
		Components.text({
			Name = "Label",
			Text = binding.label,
			Style = "caption",
			Color = Colors.TextMuted,
			AlignX = "Center",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 18),
			Parent = cell,
		})
		-- Cooldown: a radial sweep over the cap, with the seconds left in place of the key
		local sweep, setSweep = Components.sweep({ Name = "Cooldown", Radius = 3, Transparency = 0.25, ZIndex = 5, Parent = cap })
		local _ = sweep
		chips[binding.name] = { frame = cell, cap = cap, key = key, sweep = setSweep, outline = outline, binding = binding }
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
		Style = "overline",
		Color = CHARGE_COLOR,
		AlignX = "Center",
		Size = UDim2.new(1, 0, 0, 18),
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = Colors.Ink,
		Parent = chargeFrame,
	})
	local chargeBar, setCharge = Components.bar({
		Name = "Bar",
		Position = UDim2.fromOffset(0, 22),
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
		healthText.TextColor3 = if low then Colors.HealthLow else Colors.Text
		vitalsStroke.Color = if low then Colors.HealthLow else Colors.Stroke
		vitalsStroke.Transparency = if low then 0.3 else 0.6
		local maxGuard = character:GetAttribute(Attribute.MaxGuard) or Combat.Block.MaxGuard
		setGuard(currentGuard(character) / math.max(1, maxGuard))

		-- Stamina: low turns amber, empty turns red and says so
		local stamina = character:GetAttribute(Attribute.Stamina)
		local staminaMax = character:GetAttribute(Attribute.StaminaMax)
		local maxValue = if typeof(staminaMax) == "number" and staminaMax > 0 then staminaMax else Combat.Stamina.Max
		local share = if typeof(stamina) == "number" then math.clamp(stamina / maxValue, 0, 1) else 1
		local isWinded = character:GetAttribute(Attribute.Winded) == true
		local refused = combat ~= nil and os.clock() - (combat.lastWindedReject or -math.huge) < 0.6
		local staminaColor = if isWinded then Colors.Danger elseif share < LOW_STAMINA then Colors.Warning else Colors.Stamina
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
			setCharge(level, if full then Colors.AccentHover else CHARGE_COLOR)
			chargeCaption.Text = if full then "FULL CHARGE" elseif level < minShare then "CHARGE" else "CHARGED"
			chargeCaption.TextColor3 = if full then Colors.AccentHover else CHARGE_COLOR
			chargeStroke.Color = if full then Colors.AccentHover else Colors.Ink
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
			local keyText = if kind == "gamepad" then chip.binding.padText else chip.binding.keyText
			local spec = cooldowns[name]
			local remaining = if spec then (character:GetAttribute(spec.attribute) or 0) - time else 0
			local share = math.clamp(remaining / (if spec then math.max(0.1, spec.length(profile)) else 1), 0, 1)
			if combat and not spec and combat.isReady and not combat:isReady(name) then
				share = 1
			end
			chip.sweep(share)
			-- While a move recharges the cap shows the seconds left instead of the key
			chip.key.Text = if remaining > 0.05 then string.format("%.1f", remaining) else keyText
			chip.key.TextColor3 = if remaining > 0.05 then Colors.Warning else Colors.Text
			local lit = (name == "SNBlock" and character:GetAttribute(Attribute.Blocking) == true)
				or (name == "SNSprint" and character:GetAttribute(Attribute.Sprinting) == true)
				or (name == "SNLock" and target ~= nil)
			chip.outline.Color = if lit then (if name == "SNBlock" then Colors.Guard else Colors.Cyan) else Colors.SteelLight
			chip.outline.Transparency = if lit then 0 else 0.55
		end
	end

	return { frame = frame, update = update, abilityRow = abilityRow, chargeMeter = chargeFrame, reticle = reticle }
end

return Hud
