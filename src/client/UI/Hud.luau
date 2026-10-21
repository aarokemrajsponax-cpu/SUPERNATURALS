-- The player's own status at the bottom centre of the screen, from the top:
--   ability row   empty for now; the ability bar (up to 6 buttons, 64x64) goes here
--   vitals        name, health bar with the number inside, guard bar
--   actions       Light, Heavy, Block and Dodge with key hints for keyboard or
--                 gamepad and a cooldown sweep (hidden on touch, where Roblox's
--                 own touch buttons show them)
-- Nothing here catches clicks, so clicking near the HUD still attacks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local CHIP_WIDTH = 106
local CHIP_HEIGHT = 44
-- Health turns red below this fraction
local LOW_HEALTH = 0.3

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
	local vitals = glass({
		Name = "Vitals",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 70),
		Parent = frame,
	})
	local vitalsStroke = Components.stroke(Colors.Stroke, 1, 0.75)
	vitalsStroke.Parent = vitals
	Components.padding(Space.S, Space.M, Space.S, Space.M).Parent = vitals
	local nameLabel = Components.text({
		Name = "PlayerName",
		Text = player.DisplayName,
		Style = "Label",
		Size = UDim2.new(1, -90, 0, 18),
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
		Size = UDim2.fromOffset(86, 18),
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
	local guardBar, setGuard = Components.bar({
		Name = "Guard",
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 6),
		Parent = vitals,
	}, Colors.Guard)
	local _ = guardBar

	-- Actions ----------------------------------------------------------------------------
	local row = make("Frame", {
		Name = "Actions",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, CHIP_HEIGHT),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	Components.list(row, Space.S, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})

	local chips: { [string]: Chip } = {}
	for order, binding in bindings do
		local chip = glass({
			Name = binding.name,
			LayoutOrder = order,
			Size = UDim2.fromOffset(CHIP_WIDTH, CHIP_HEIGHT),
			ClipsDescendants = true,
			Parent = row,
		})
		local outline = Components.stroke(Colors.Stroke, 1, 0.7)
		outline.Parent = chip
		local keyBox = make("Frame", {
			Name = "Key",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 7, 0.5, 0),
			Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = Colors.Cyan,
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			Parent = chip,
		}, { Components.corner(Theme.TinyCorner), Components.stroke(Colors.Cyan, 1, 0.35) })
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
			Style = "Caption",
			Weight = "Bold",
			Color = Colors.Text,
			Position = UDim2.fromOffset(44, 0),
			Size = UDim2.new(1, -50, 1, 0),
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
		if not character or not humanoid then
			return
		end
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

		local kind = device()
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
			local share = math.clamp(remaining / (if spec then math.max(0.1, spec.length(profile)) else 1), 0, 1)
			chip.cooldown.Size = UDim2.fromScale(share, 1)
			chip.timer.Visible = remaining > 0.05
			if remaining > 0.05 then
				chip.timer.Text = string.format("%.1f", remaining)
			end
		end
		local blockChip = chips.SNBlock
		if blockChip then
			local isBlocking = character:GetAttribute(Attribute.Blocking) == true
			blockChip.outline.Color = if isBlocking then Colors.Guard else Colors.Stroke
			blockChip.outline.Transparency = if isBlocking then 0 else 0.7
		end
	end

	return { frame = frame, update = update, abilityRow = abilityRow }
end

return Hud
