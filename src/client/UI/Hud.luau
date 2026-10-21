-- The player's own status at the bottom of the screen: health, guard, and the
-- four combat actions with their buttons and cooldowns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local Attribute = Protocol.Attribute
local Colors = Theme.Colors
local make = Components.make

local player = Players.LocalPlayer

local Hud = {}

type Chip = { frame: Frame, key: TextLabel, cooldown: Frame, binding: any }

function Hud.build(parent: Instance, bindings: { any }, device: () -> string, currentGuard: (Model) -> number)
	local frame = make("Frame", {
		Name = "Hud",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(440, 106),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	local nameLabel = Components.label(player.DisplayName, {
		Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.Fonts.Heading,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.5,
		MaxTextSize = 16,
		Parent = frame,
	})

	local healthBar, setHealth = Components.bar({
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 20),
		Parent = frame,
	}, Colors.Health)
	make("UIStroke", { Color = Colors.Background, Thickness = 2, Transparency = 0.2, Parent = healthBar })
	local healthText = Components.label("100", {
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.fromOffset(0, 0),
		Font = Theme.Fonts.Numbers,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.4,
		ZIndex = 3,
		MaxTextSize = 15,
		Parent = healthBar,
	})

	local _, setGuard = Components.bar({
		Size = UDim2.new(1, 0, 0, 7),
		Position = UDim2.fromOffset(0, 44),
		Parent = frame,
	}, Colors.Guard)

	local row = make("Frame", {
		Name = "Actions",
		Size = UDim2.new(1, 0, 0, 46),
		Position = UDim2.fromOffset(0, 58),
		BackgroundTransparency = 1,
		Parent = frame,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local chips: { [string]: Chip } = {}
	for order, binding in bindings do
		local chip = Components.panel({
			Name = binding.name,
			LayoutOrder = order,
			Size = UDim2.new(0, 102, 1, 0),
			Parent = row,
		})
		local keyBox = make("Frame", {
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.fromOffset(8, 8),
			BackgroundColor3 = Colors.PanelLight,
			Parent = chip,
		}, { Components.corner(UDim.new(0, 6)), Components.stroke(Colors.Cyan, 1, 0.3) })
		local key = Components.label(binding.keyText, {
			Font = Theme.Fonts.Numbers,
			TextColor3 = Colors.Cyan,
			MaxTextSize = 14,
			Parent = keyBox,
		})
		Components.label(string.upper(binding.label), {
			Size = UDim2.new(1, -48, 1, 0),
			Position = UDim2.fromOffset(44, 0),
			Font = Theme.Fonts.Heading,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 14,
			Parent = chip,
		})
		local cooldown = make("Frame", {
			Name = "Cooldown",
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			ZIndex = 5,
			Parent = chip,
		}, { Components.corner() })
		chips[binding.name] = { frame = chip, key = key, cooldown = cooldown, binding = binding }
	end

	local cooldowns = {
		SNHeavy = { attribute = Attribute.HeavyReadyAt, length = Combat.Heavy.Cooldown },
		SNDodge = { attribute = Attribute.DodgeReadyAt, length = Combat.Dodge.Cooldown },
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
		setHealth(fraction, if fraction < 0.3 then Colors.HealthLow else Colors.Health)
		healthText.Text = tostring(math.ceil(humanoid.Health))
		setGuard(currentGuard(character) / Combat.Block.MaxGuard)

		local kind = device()
		row.Visible = kind ~= "touch"
		local time = workspace:GetServerTimeNow()
		for name, chip in chips do
			chip.key.Text = if kind == "gamepad" then chip.binding.padText else chip.binding.keyText
			local spec = cooldowns[name]
			local remaining = if spec then (character:GetAttribute(spec.attribute) or 0) - time else 0
			chip.cooldown.Size = UDim2.fromScale(math.clamp(remaining / (if spec then spec.length else 1), 0, 1), 1)
		end
		local blockChip = chips.SNBlock
		if blockChip then
			local stroke = blockChip.frame:FindFirstChildOfClass("UIStroke")
			if stroke then
				local isBlocking = character:GetAttribute(Attribute.Blocking) == true
				stroke.Color = if isBlocking then Colors.Guard else Colors.Cyan
				stroke.Transparency = if isBlocking then 0 else 0.55
			end
		end
	end

	return { frame = frame, update = update }
end

return Hud
