-- The interactive defense cards: what the player sees when a defense prompt
-- arrives. Each card is compact, sits low and centred, and is fully readable
-- at a glance: what to do, which button, and how much time is left.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local Colors = Theme.Colors
local make = Components.make

local DefensePrompt = {}
DefensePrompt.__index = DefensePrompt

local rgb = Color3.fromRGB
local FAIL_ZONE = rgb(120, 34, 46)
local GOOD_ZONE = rgb(240, 170, 60)
local PERFECT_ZONE = rgb(120, 255, 170)

local RESULTS = {
	Perfect = { text = "PERFECT!", color = Colors.Gold },
	Good = { text = "GOOD", color = Colors.Cyan },
	Escaped = { text = "BROKE FREE!", color = Colors.Success },
	Countered = { text = "REROUTED!", color = PERFECT_ZONE },
	Failed = { text = "MISSED", color = Colors.Danger },
}

local HINTS = {
	Prompt = { keyboard = "Q  dodge   ·   F  block", gamepad = "B  dodge   ·   L1  block", touch = "Use Dodge or Block" },
	Timing = { keyboard = "Press  F  in the centre", gamepad = "Press  L1  in the centre", touch = "Tap in the centre" },
	Mash = { keyboard = "Mash  SPACE  or  F", gamepad = "Mash  A  or  L1", touch = "Tap quickly!" },
	Redirect = { keyboard = "Press  F  to take it over", gamepad = "Press  L1  to take it over", touch = "Tap to take it over" },
}

local TITLES = {
	Prompt = "DODGE OR BLOCK",
	Timing = "TIME IT",
	Mash = "BREAK FREE!",
	Redirect = "REROUTE",
}

local ICONS = { Prompt = "⚠️", Timing = "🎯", Mash = "✊", Redirect = "↩️" }

local function text(props: { [string]: any }): TextLabel
	local label = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = props.Font or Theme.Fonts.Heading,
		TextColor3 = props.TextColor3 or Colors.Text,
		TextSize = props.TextSize or 16,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = props.Text or "",
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		ZIndex = props.ZIndex or 3,
		Parent = props.Parent,
	})
	return label
end

function DefensePrompt.new(gui: ScreenGui, onPress: (kind: string, id: string) -> ())
	local self = setmetatable({}, DefensePrompt)
	self.onPress = onPress
	self.cards = {}
	self.holder = make("Frame", {
		Name = "DefensePrompts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.64, 0),
		Size = UDim2.fromOffset(440, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		make("UIListLayout", {
			Padding = UDim.new(0, 8),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	return self
end

-- Builds the card for one cue
function DefensePrompt:show(data)
	self:hide(data.id)
	local kind = data.kind
	local height = if kind == "Timing" then 96 elseif kind == "Mash" then 92 else 70
	local card = make("TextButton", {
		Name = kind,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(if kind == "Timing" then 440 else 380, height),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.08,
		LayoutOrder = math.floor((data.impactAt or 0) * 10) % 100000,
		Parent = self.holder,
	}, {
		Components.corner(UDim.new(0, 14)),
		make("UIStroke", { Color = Colors.Gold, Thickness = 2, Transparency = 0.15 }),
		make("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(190, 195, 220)), Rotation = 90 }),
		make("UIScale", { Name = "Pop", Scale = 0.85 }),
	})
	local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
	local pop = card:FindFirstChild("Pop") :: UIScale
	TweenService:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	-- Icon tile, title and the button hint
	local tile = make("Frame", {
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.fromOffset(12, 12),
		BackgroundColor3 = Colors.PanelLight,
		ZIndex = 2,
		Parent = card,
	}, { Components.corner(UDim.new(0, 10)) })
	text({ Text = ICONS[kind] or "!", Size = UDim2.fromScale(1, 1), TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, Parent = tile })
	local title = text({
		Text = TITLES[kind] or kind,
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextColor3 = Colors.Gold,
		Position = UDim2.fromOffset(66, 10),
		Size = UDim2.new(1, -78, 0, 26),
		Parent = card,
	})
	local hint = text({
		Text = "",
		Font = Theme.Fonts.Body,
		TextSize = 14,
		TextColor3 = Colors.TextDim,
		Position = UDim2.fromOffset(66, 36),
		Size = UDim2.new(1, -78, 0, 18),
		Parent = card,
	})
	if typeof(data.label) == "string" and data.label ~= "" and kind ~= "Mash" then
		text({
			Text = string.upper(data.label),
			Font = Theme.Fonts.Heading,
			TextSize = 12,
			TextColor3 = Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 14),
			Size = UDim2.fromOffset(150, 16),
			Parent = card,
		})
	end

	local entry = {
		data = data,
		kind = kind,
		card = card,
		stroke = stroke,
		title = title,
		hint = hint,
		presses = 0,
		done = false,
	}

	if kind == "Timing" then
		-- Fail zone, good zone and a narrow perfect centre; the marker slides across
		local track = make("Frame", {
			Size = UDim2.new(1, -28, 0, 22),
			Position = UDim2.new(0, 14, 1, -32),
			BackgroundColor3 = FAIL_ZONE,
			ZIndex = 2,
			ClipsDescendants = true,
			Parent = card,
		}, { Components.corner(UDim.new(0, 6)) })
		local halfSpan = math.max(0.3, (data.impactAt or 0) - (data.opensAt or 0))
		local good = math.clamp((data.goodWindow or 0.17) / halfSpan, 0.02, 0.9)
		local perfect = math.clamp((data.perfectWindow or 0.07) / halfSpan, 0.01, good)
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(good, 1),
			BackgroundColor3 = GOOD_ZONE,
			ZIndex = 2,
			Parent = track,
		})
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(perfect, 1),
			BackgroundColor3 = PERFECT_ZONE,
			ZIndex = 3,
			Parent = track,
		})
		local marker = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(0, 4, 1, 6),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 5,
			Parent = track,
		}, { make("UIStroke", { Color = Colors.Gold, Thickness = 2 }) })
		entry.halfSpan = halfSpan
		entry.marker = marker
		entry.track = track
	else
		local bar = make("Frame", {
			Size = UDim2.new(1, -28, 0, 6),
			Position = UDim2.new(0, 14, 1, -14),
			BackgroundColor3 = Colors.Background,
			ZIndex = 2,
			Parent = card,
		}, { Components.corner(UDim.new(0, 3)) })
		entry.fill = make("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = if kind == "Mash" then Colors.Success else Colors.Gold,
			ZIndex = 3,
			Parent = bar,
		}, { Components.corner(UDim.new(0, 3)) })
		if kind == "Mash" then
			entry.required = math.max(1, tonumber(data.presses) or 1)
			entry.fill.Size = UDim2.fromScale(0, 1)
			entry.counter = text({
				Text = `0 / {entry.required}`,
				Font = Theme.Fonts.Numbers,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -14, 0, 14),
				Size = UDim2.fromOffset(80, 20),
				Parent = card,
			})
		end
	end

	card.Activated:Connect(function()
		if not entry.done and kind ~= "Prompt" then
			self.onPress(kind, data.id)
		end
	end)
	self.cards[data.id] = entry
end

function DefensePrompt:hide(id: string)
	local entry = self.cards[id]
	if entry then
		self.cards[id] = nil
		entry.card:Destroy()
	end
end

-- The local press: a little feedback straight away (the result comes from the server)
function DefensePrompt:pressed(id: string, at: number)
	local entry = self.cards[id]
	if not entry then
		return
	end
	if entry.kind == "Mash" then
		entry.presses += 1
		local share = math.clamp(entry.presses / entry.required, 0, 1)
		TweenService:Create(entry.fill, TweenInfo.new(0.08), { Size = UDim2.fromScale(share, 1) }):Play()
		entry.counter.Text = `{math.min(entry.presses, entry.required)} / {entry.required}`
		local pop = entry.card:FindFirstChild("Pop") :: UIScale
		pop.Scale = 1.06
		TweenService:Create(pop, TweenInfo.new(0.1), { Scale = 1 }):Play()
	elseif entry.kind == "Timing" and entry.marker then
		-- Freeze the marker where they pressed
		entry.frozenAt = at
	end
end

function DefensePrompt:result(id: string, kind: string, result: string)
	local entry = self.cards[id]
	if not entry then
		return
	end
	entry.done = true
	local style = RESULTS[result] or RESULTS.Failed
	if kind == "Prompt" and result == "Failed" then
		-- A missed dodge/block prompt just quietly goes away
		self:hide(id)
		return
	end
	entry.title.Text = style.text
	entry.title.TextColor3 = style.color
	entry.stroke.Color = style.color
	entry.hint.Text = ""
	local pop = entry.card:FindFirstChild("Pop") :: UIScale
	pop.Scale = 1.12
	TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(0.7, function()
		if self.cards[id] == entry then
			self:hide(id)
		end
	end)
end

function DefensePrompt:update(time: number, device: string)
	for id, entry in self.cards do
		local data = entry.data
		if not entry.done then
			local hints = HINTS[entry.kind]
			entry.hint.Text = if hints then hints[device] or hints.keyboard else ""
		end
		if entry.kind == "Timing" and entry.marker then
			local at = entry.frozenAt or time
			local start = (data.impactAt or time) - entry.halfSpan
			local alpha = math.clamp((at - start) / (entry.halfSpan * 2), 0, 1)
			entry.marker.Position = UDim2.fromScale(alpha, 0.5)
			if not entry.done and time > (data.closesAt or 0) + 0.4 then
				self:hide(id)
			end
		elseif entry.fill and entry.kind ~= "Mash" then
			local opens = data.opensAt or time
			local closes = data.closesAt or time
			local remaining = math.clamp((closes - time) / math.max(0.05, closes - opens), 0, 1)
			entry.fill.Size = UDim2.fromScale(remaining, 1)
			entry.fill.BackgroundColor3 = Colors.Danger:Lerp(Colors.Gold, remaining)
			if not entry.done and time > closes + 0.3 then
				self:hide(id)
			end
		elseif entry.kind == "Mash" and not entry.done and time > (data.closesAt or 0) + 0.5 then
			self:hide(id)
		end
	end
end

return DefensePrompt
