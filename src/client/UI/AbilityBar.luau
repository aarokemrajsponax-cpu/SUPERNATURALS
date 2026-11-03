-- The ability bar above the health bar: one button per equipped ability (a drawn
-- icon, the cost, a dark cooldown fill with the seconds left; the key cap sits under the slot), the
-- ultimate with its charge filling up, and the power's resource meter (plus a
-- power's extra meters, like The Grandmaster's Focus and Perfect Form). Buttons
-- are tappable on touch and show a short explanation when a press can't work
-- ("Not enough Grit"). No emoji: icons come from UI/Icons by ability.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Icons = require(script.Parent.Icons)

local Attribute = Protocol.Attribute
local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make

local player = Players.LocalPlayer

local AbilityBar = {}

local SIZE = 64
local ULT_SIZE = 64
local KEY_ROW = 22

type Button = {
	frame: TextButton,
	icon: Frame,
	key: TextLabel,
	keyCap: Frame,
	cost: TextLabel,
	sweep: (number) -> (),
	timer: TextLabel,
	outline: UIStroke,
	charge: Frame?,
	abilityId: string,
	def: any,
	slot: any,
}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- abilities: the AbilityController; device(): "keyboard" | "gamepad" | "touch"
function AbilityBar.build(row: Frame, abilities, device: () -> string)
	local holder = make("Frame", {
		Name = "AbilityBar",
		Size = UDim2.new(1, 0, 0, ULT_SIZE + KEY_ROW + 22),
		BackgroundTransparency = 1,
		Parent = row.Parent,
		LayoutOrder = row.LayoutOrder,
	})
	-- The bar takes the row's place in the HUD layout
	row.Size = UDim2.new(1, 0, 0, ULT_SIZE + KEY_ROW)
	row.Parent = holder
	local rowLayout = row:FindFirstChildOfClass("UIListLayout")
	if rowLayout then
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	end

	-- Resource meter under the buttons
	local meter = make("Frame", {
		Name = "Resource",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0, 300, 0, 18),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	local resourceLabel = Components.text({
		Style = "caption",
		Weight = "SemiBold",
		Color = Colors.TextDim,
		Size = UDim2.new(0, 120, 1, 0),
		Parent = meter,
	})
	local track = make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(1, -126, 0, 6),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.1,
		Parent = meter,
	}, { Components.corner(Theme.TinyCorner), Components.stroke(Colors.Stroke, 1, 0.8) })
	local fill = make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Cyan,
		BorderSizePixel = 0,
		Parent = track,
	}, { Components.corner(Theme.TinyCorner) })

	-- Extra meters some powers expose as attributes, either side of the resource
	-- meter (The Grandmaster: Focus on the left, Perfect Form on the right)
	local EXTRA_WIDTH = 130
	local function miniMeter(name: string, side: number, color: Color3)
		local frame = make("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 1),
			Position = UDim2.new(0.5, side * (150 + Space.S), 1, 0),
			Size = UDim2.new(0, EXTRA_WIDTH, 0, 18),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = holder,
		})
		local label = Components.text({
			Style = "caption",
			Weight = "SemiBold",
			Color = Colors.TextDim,
			Size = UDim2.new(0, 62, 1, 0),
			Parent = frame,
		})
		local miniTrack = make("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.new(1, -68, 0, 6),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.1,
			Parent = frame,
		}, { Components.corner(Theme.TinyCorner), Components.stroke(Colors.Stroke, 1, 0.8) })
		local miniFill = make("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = miniTrack,
		}, { Components.corner(Theme.TinyCorner) })
		return frame, label, miniFill
	end
	local extraMeters = {
		{ attribute = Attribute.Focus, title = "FOCUS", parts = table.pack(miniMeter("Focus", -1, Color3.fromRGB(150, 210, 190))) },
		{ attribute = Attribute.PerfectForm, title = "FORM", parts = table.pack(miniMeter("PerfectForm", 1, Color3.fromRGB(250, 232, 186))) },
	}

	-- A short message above the bar when a press doesn't work
	local message = Components.text({
		Style = "strong",
		Color = Colors.Warning,
		AlignX = "Center",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.new(1, 0, 0, 22),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Parent = holder,
	})
	local messageToken = 0
	local function say(text: string)
		messageToken += 1
		local token = messageToken
		message.Text = text
		message.TextTransparency = 0
		message.TextStrokeTransparency = 0.5
		task.delay(1.4, function()
			if token == messageToken then
				TweenService:Create(message, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end

	local buttons: { Button } = {}
	local signature = ""

	local function keyText(slot: any): string
		for _, binding in abilities.Bindings do
			if binding.slot == slot then
				return if device() == "gamepad" then binding.padText else binding.keyText
			end
		end
		return ""
	end

	local function buildButton(entry, order: number): Button
		local ultimate = entry.slot == "Ultimate"
		local size = SIZE
		-- One outer edge. The ultimate gets a gold edge and a gold fill that rises as it charges
		local outline = Components.stroke(if ultimate then Colors.Gold else Colors.SteelLight, 1, if ultimate then 0.35 else 0.65)
		local frame = make("TextButton", {
			Name = "Ability_" .. entry.abilityId,
			LayoutOrder = order,
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Colors.Panel,
			BackgroundTransparency = 0.04,
			BorderSizePixel = 0,
			Selectable = false,
			Parent = row,
		}, {
			Components.corner(Theme.SmallCorner),
			outline,
		})
		-- Everything that fills the tile is clipped to it; the key sits outside, under it
		local face = make("Frame", {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Active = false,
			Parent = frame,
		}, { Components.corner(Theme.SmallCorner) })
		local charge = nil
		if ultimate then
			charge = make("Frame", {
				Name = "Charge",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.fromScale(1, 0),
				BackgroundColor3 = Colors.Gold,
				BackgroundTransparency = 0.8,
				BorderSizePixel = 0,
				ZIndex = 1,
				Parent = face,
			})
		end
		-- The drawn icon sits above the middle; the cost is a quiet number under it
		local icon = Components.icon(Icons.forAbility(entry.def), 28, Colors.Text)
		icon.Name = "Icon"
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, 0, 0.5, -7)
		icon.ZIndex = 2
		icon.Parent = face
		local cost = Components.text({
			Name = "Cost",
			Text = if ultimate then "ULT" elseif (entry.def.cost or 0) > 0 then tostring(entry.def.cost) else "",
			Style = "number",
			TextSize = 14,
			Color = Colors.TextMuted,
			AlignX = "Center",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -8, 0, 16),
			ZIndex = 3,
			Parent = face,
		})
		-- Cooldown: a dark fill over the tile that drains downward, the seconds left centred
		local cooldown = make("Frame", {
			Name = "Cooldown",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.28,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 5,
			Parent = face,
		})
		local function setSweep(share: number)
			cooldown.Visible = share > 0.001
			cooldown.Size = UDim2.fromScale(1, share)
		end
		local timer = Components.text({
			Name = "Timer",
			Text = "",
			Style = "number",
			TextSize = 20,
			AlignX = "Center",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 6,
			Parent = face,
		})
		-- The key under the slot, so it never covers the icon
		local keyCap = Components.keycap(keyText(entry.slot), {
			Name = "KeyCap",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 4),
			Height = 18,
			Parent = frame,
		})
		local keyLabel = keyCap:FindFirstChild("Key") :: TextLabel
		local button: Button = {
			frame = frame,
			icon = icon,
			key = keyLabel,
			keyCap = keyCap,
			cost = cost,
			sweep = setSweep,
			timer = timer,
			outline = outline,
			charge = charge,
			abilityId = entry.abilityId,
			def = entry.def,
			slot = entry.slot,
		}
		-- Targeted abilities on touch: press and drag to aim, release to cast
		local touchTaken = false
		frame.InputBegan:Connect(function(input)
			touchTaken = false
			if input.UserInputType == Enum.UserInputType.Touch and abilities.touchBegin then
				touchTaken = abilities:touchBegin(entry.slot, input, frame)
			end
		end)
		frame.Activated:Connect(function()
			if touchTaken then
				touchTaken = false
				return
			end
			abilities:use(entry.slot)
		end)
		return button
	end

	local function rebuild()
		for _, button in buttons do
			button.frame:Destroy()
		end
		table.clear(buttons)
		for order, entry in abilities:slots() do
			table.insert(buttons, buildButton(entry, order))
		end
	end

	abilities.rejected:Connect(function(abilityId, text)
		say(text)
		for _, button in buttons do
			if button.abilityId == abilityId then
				button.outline.Color = Colors.Danger
				button.outline.Transparency = 0
				local frame = button.frame
				local origin = frame.Position
				TweenService:Create(frame, TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true), { Position = origin + UDim2.fromOffset(3, 0) }):Play()
				task.delay(0.45, function()
					if button.charge == nil then
						button.outline.Color = Colors.SteelLight
						button.outline.Transparency = 0.65
					end
				end)
			end
		end
	end)

	local function update()
		local character = player.Character
		if not character then
			holder.Visible = false
			return
		end
		-- Rebuild when the loadout, power or degree changes
		local now = `{character:GetAttribute(Attribute.Power)}/{character:GetAttribute(Attribute.Degree)}/{character:GetAttribute(Attribute.Loadout)}`
		if now ~= signature then
			signature = now
			rebuild()
		end
		holder.Visible = #buttons > 0

		local powerDef = Powers.get(character:GetAttribute(Attribute.Power))
		local resourceDef = powerDef and powerDef.resource
		local resource = character:GetAttribute(Attribute.Resource) or 0
		local resourceMax = character:GetAttribute(Attribute.ResourceMax) or 0
		meter.Visible = resourceDef ~= nil and resourceMax > 0
		if resourceDef then
			resourceLabel.Text = `{string.upper(resourceDef.name)}  {math.floor(resource)}/{resourceMax}`
			fill.BackgroundColor3 = resourceDef.color or Colors.Cyan
			fill.Size = UDim2.fromScale(math.clamp(resource / math.max(1, resourceMax), 0, 1), 1)
		end
		for _, extra in extraMeters do
			local value = character:GetAttribute(extra.attribute)
			local frame, label, extraFill = extra.parts[1], extra.parts[2], extra.parts[3]
			frame.Visible = typeof(value) == "number"
			if typeof(value) == "number" then
				label.Text = `{extra.title}  {math.floor(value)}`
				extraFill.Size = UDim2.fromScale(math.clamp(value / 100, 0, 1), 1)
			end
		end

		local time = serverNow()
		local ult = character:GetAttribute(Attribute.Ultimate) or 0
		for _, button in buttons do
			button.key.Text = keyText(button.slot)
			button.keyCap.Visible = button.key.Text ~= "" and device() ~= "touch"
			local readyAt = character:GetAttribute(Attribute.CooldownPrefix .. button.abilityId) or 0
			local remaining = readyAt - time
			local length = math.max(0.1, button.def.cooldown or 1)
			if remaining > 0 then
				button.sweep(math.clamp(remaining / length, 0, 1))
				button.timer.Text = if remaining >= 1 then tostring(math.ceil(remaining)) else string.format("%.1f", remaining)
			else
				button.sweep(0)
				button.timer.Text = ""
			end
			if button.charge then
				local share = math.clamp(ult / Combat.Ultimate.Max, 0, 1)
				button.charge.Size = UDim2.fromScale(1, share)
				local ready = share >= 1 and remaining <= 0
				button.cost.Text = if ready then "READY" else `{math.floor(share * 100)}%`
				button.cost.TextColor3 = if ready then Colors.Gold else Colors.TextMuted
				Icons.tint(button.icon, if ready then Colors.Gold else Colors.Text)
				button.outline.Color = Colors.Gold
				-- The edge firms up once it's ready; no pulse
				button.outline.Transparency = if ready then 0.05 else 0.4
			else
				local affordable = resource + 0.5 >= (button.def.cost or 0)
				Icons.tint(button.icon, if affordable then Colors.Text else Colors.TextDim)
				button.cost.TextColor3 = if affordable then Colors.TextMuted else Colors.Danger
			end
		end
	end

	return { frame = holder, update = update }
end

return AbilityBar
