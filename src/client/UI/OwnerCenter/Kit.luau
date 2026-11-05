-- Small building blocks shared by the Control Center sections, made from Components and Theme
-- (craft pass rules: solid tone-separated cards, Michroma only for headings, Builder Sans for
-- the rest, numbers and ids in the mono face, 14 px minimum, wrapped text that grows).

local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)

local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make

local Kit = {}

-- A scrolling column that fills its parent; children go in with LayoutOrder
function Kit.page(parent: Instance): ScrollingFrame
	local scroll = Components.scroll({ Name = "Page", Parent = parent })
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.None
	Components.list(scroll, Space.M)
	Components.padding(0, Space.M, Space.M, 0).Parent = scroll
	return scroll
end

-- A section heading: the one place besides the window title that uses the display face
function Kit.heading(parent: Instance, text: string, order: number?): TextLabel
	return Components.text({ Name = "Heading", Text = text, Style = "title", Wrap = true, LayoutOrder = order or 0, Parent = parent })
end

function Kit.subheading(parent: Instance, text: string, order: number?): TextLabel
	return Components.text({ Name = "Subheading", Text = text, Style = "subheading", Wrap = true, LayoutOrder = order or 0, Parent = parent })
end

function Kit.para(parent: Instance, text: string, order: number?, color: Color3?): TextLabel
	return Components.text({ Name = "Para", Text = text, Style = "body", Wrap = true, Color = color, LayoutOrder = order or 0, Parent = parent })
end

function Kit.caption(parent: Instance, text: string, order: number?, color: Color3?): TextLabel
	return Components.text({ Name = "Caption", Text = text, Style = "caption", Wrap = true, Color = color, LayoutOrder = order or 0, Parent = parent })
end

-- A tone-separated card that grows with its content
function Kit.card(parent: Instance, order: number?, props: { [string]: any }?): Frame
	local merged: { [string]: any } = {
		Name = "Card",
		LayoutOrder = order or 0,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Parent = parent,
	}
	for key, value in props or {} do
		merged[key] = value
	end
	local card = make("Frame", merged, { Components.corner(Theme.SmallCorner), Components.padding(Space.M) })
	Components.list(card, Space.S)
	return card
end

-- A plain vertical stack with no fill or padding
function Kit.stack(parent: Instance, order: number?, name: string?, gap: number?): Frame
	local stack = make("Frame", {
		Name = name or "Stack",
		LayoutOrder = order or 0,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Components.list(stack, gap or Space.S)
	return stack
end

-- A readable name for an audit action such as "remote:activate"
function Kit.actionName(action: any): string
	local text = tostring(action or "")
	text = string.gsub(text, "^remote:", "")
	text = string.gsub(text, "^reconcile:", "Scheduled ")
	text = string.gsub(text, "[_:]", " ")
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

-- A row that flows left to right and wraps
function Kit.flow(parent: Instance, order: number?, gap: number?): Frame
	local row = make("Frame", {
		Name = "Flow",
		LayoutOrder = order or 0,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Components.list(row, gap or Space.S, {
		FillDirection = Enum.FillDirection.Horizontal,
		Wraps = true,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	return row
end

-- Two or more side by side columns that each grow downward
function Kit.columns(parent: Instance, count: number, order: number?): { Frame }
	local holder = make("Frame", {
		Name = "Columns",
		LayoutOrder = order or 0,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Components.list(holder, Space.M, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Top })
	local columns = {}
	for index = 1, count do
		local column = make("Frame", {
			Name = "Column" .. index,
			LayoutOrder = index,
			Size = UDim2.new(1 / count, -Space.M * (count - 1) / count, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = holder,
		})
		Components.list(column, Space.M)
		columns[index] = column
	end
	return columns
end

-- A button sized to its text. variant: Primary | Secondary | Ghost | Danger
function Kit.button(parent: Instance, text: string, variant: string?, onClick: (() -> ())?, props: { [string]: any }?): TextButton
	local width = math.max(96, math.ceil(Components.textWidth(text, 15, Theme.Faces.Bold)) + 40)
	local merged: { [string]: any } = {
		Variant = variant or "Secondary",
		KeepCase = true,
		Size = UDim2.fromOffset(width, Theme.Size.Control),
		Parent = parent,
	}
	for key, value in props or {} do
		merged[key] = value
	end
	return Components.button(text, merged, onClick)
end

-- A text box. props: Placeholder, Text, MaxLen, Multi, Name, LayoutOrder, Size. onChange(text) on every edit.
function Kit.input(parent: Instance, props: { [string]: any }, onChange: ((string) -> ())?): TextBox
	local multi = props.Multi == true
	local maxLen = props.MaxLen
	local box = make("TextBox", {
		Name = props.Name or "Input",
		LayoutOrder = props.LayoutOrder or 0,
		Size = props.Size or UDim2.new(1, 0, 0, if multi then 92 else Theme.Size.Control),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		MultiLine = multi,
		TextWrapped = multi,
		Text = props.Text or "",
		PlaceholderText = props.Placeholder or "",
		PlaceholderColor3 = Colors.TextMuted,
		TextColor3 = Colors.Text,
		FontFace = Theme.Faces.Medium,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = if multi then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center,
		Parent = parent,
	}, {
		Components.corner(Theme.SmallCorner),
		Components.stroke(Colors.Stroke, 1, 0.45),
		Components.padding(if multi then 10 else 0, 12, if multi then 10 else 0, 12),
	})
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local text = box.Text
		if maxLen and (utf8.len(text) or #text) > maxLen then
			local cut = utf8.offset(text, maxLen + 1)
			box.Text = if cut then string.sub(text, 1, cut - 1) else string.sub(text, 1, maxLen)
			return
		end
		if onChange then
			onChange(text)
		end
	end)
	return box
end

-- A stepper over a list of values: label, minus, value, plus. Returns { frame, set, get }.
function Kit.stepper(parent: Instance, label: string, values: { any }, value: any, format: ((any) -> string)?, onChange: ((any) -> ())?, props: { [string]: any }?)
	local given = props or {}
	local index = 1
	for i, candidate in values do
		if candidate == value then
			index = i
		end
	end
	local frame = make("Frame", {
		Name = given.Name or "Stepper",
		LayoutOrder = given.LayoutOrder or 0,
		Size = UDim2.new(1, 0, 0, Theme.Size.Control),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local text = Components.text({
		Name = "Label",
		Text = label,
		Style = "label",
		Size = UDim2.new(1, -(44 * 2 + 104 + Space.S * 2), 1, 0),
		Wrap = true,
		AlignY = "Center",
		Parent = frame,
	})
	local readout
	local function show()
		readout.Text = if format then format(values[index]) else tostring(values[index])
	end
	local function step(delta: number)
		local nextIndex = math.clamp(index + delta, 1, #values)
		if nextIndex ~= index then
			index = nextIndex
			show()
			if onChange then
				onChange(values[index])
			end
		end
	end
	local plus = Components.button("", {
		Name = "Plus",
		Variant = "Secondary",
		Icon = "plus",
		IconSize = 16,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(44, 44),
		Parent = frame,
	}, function()
		step(1)
	end)
	readout = Components.text({
		Name = "Value",
		Style = "number",
		AlignX = "Center",
		AlignY = "Center",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(44 + Space.S), 0, 0),
		Size = UDim2.fromOffset(104, 44),
		Parent = frame,
	})
	local minus = Components.button("", {
		Name = "Minus",
		Variant = "Secondary",
		Icon = "minus",
		IconSize = 16,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(44 + Space.S + 104 + Space.S), 0, 0),
		Size = UDim2.fromOffset(44, 44),
		Parent = frame,
	}, function()
		step(-1)
	end)
	local _ = text
	local _ = plus
	local _ = minus
	show()
	return {
		frame = frame,
		get = function()
			return values[index]
		end,
		set = function(newValue: any)
			for i, candidate in values do
				if candidate == newValue then
					index = i
					show()
					return
				end
			end
		end,
	}
end

-- A row of colour swatches plus "Default". pick(rgb or nil) is called with { r, g, b } or nil.
Kit.PALETTE = {
	{ name = "Gold", rgb = { 255, 200, 80 } },
	{ name = "Amber", rgb = { 255, 150, 50 } },
	{ name = "Red", rgb = { 230, 50, 60 } },
	{ name = "Pink", rgb = { 255, 110, 190 } },
	{ name = "Violet", rgb = { 160, 110, 255 } },
	{ name = "Cyan", rgb = { 90, 230, 255 } },
	{ name = "Ice", rgb = { 170, 225, 255 } },
	{ name = "Green", rgb = { 60, 200, 110 } },
	{ name = "White", rgb = { 255, 255, 255 } },
}

function Kit.swatches(parent: Instance, order: number?, pick: (any?) -> ()): { frame: Frame, set: (any?) -> () }
	local row = Kit.flow(parent, order, Space.S)
	row.Name = "Swatches"
	local buttons: { [string]: TextButton } = {}
	local function mark(name: string?)
		for key, button in buttons do
			local outline = button:FindFirstChildOfClass("UIStroke")
			if outline then
				outline.Transparency = if key == (name or "Default") then 0 else 0.7
				outline.Thickness = if key == (name or "Default") then 2 else 1
			end
		end
	end
	local function add(name: string, rgb: { number }?)
		local text = if rgb then "" else "Default"
		local button = make("TextButton", {
			Name = "Swatch_" .. name,
			AutoButtonColor = false,
			Selectable = true,
			Text = text,
			FontFace = Theme.Faces.SemiBold,
			TextSize = 16,
			TextColor3 = Colors.Text,
			Size = UDim2.fromOffset(if rgb then 44 else 76, 44),
			BackgroundColor3 = if rgb then Color3.fromRGB(rgb[1], rgb[2], rgb[3]) else Colors.PanelHover,
			BorderSizePixel = 0,
			Parent = row,
		}, { Components.corner(Theme.SmallCorner), Components.stroke(Colors.Text, 1, 0.7) })
		buttons[name] = button
		button.Activated:Connect(function()
			mark(name)
			pick(rgb)
		end)
	end
	add("Default", nil)
	for _, swatch in Kit.PALETTE do
		add(swatch.name, swatch.rgb)
	end
	mark(nil)
	return {
		frame = row,
		set = function(rgb: any?)
			if not rgb then
				mark(nil)
				return
			end
			for _, swatch in Kit.PALETTE do
				if swatch.rgb[1] == rgb[1] and swatch.rgb[2] == rgb[2] and swatch.rgb[3] == rgb[3] then
					mark(swatch.name)
					return
				end
			end
			mark(nil)
		end,
	}
end

-- A label on the left and a value on the right (numbers and ids in the mono face)
function Kit.pair(parent: Instance, key: string, value: string, order: number?, mono: boolean?): TextLabel
	local row = make("Frame", {
		Name = "Pair",
		LayoutOrder = order or 0,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Components.text({ Name = "Key", Text = key, Style = "small", Size = UDim2.new(0.5, -4, 0, 22), Wrap = true, Parent = row })
	return Components.text({
		Name = "Value",
		Text = value,
		Style = if mono then "number" else "strong",
		Color = Colors.Text,
		Wrap = true,
		AlignX = "Right",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, -4, 0, 22),
		Parent = row,
	})
end

function Kit.empty(parent: Instance, text: string, order: number?): TextLabel
	return Components.text({ Name = "Empty", Text = text, Style = "body", Color = Colors.TextMuted, Wrap = true, LayoutOrder = order or 0, Parent = parent })
end

function Kit.clear(container: Instance, keep: { [string]: boolean }?)
	for _, child in container:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") and not child:IsA("UIGridLayout") and not (keep and keep[child.Name]) then
			child:Destroy()
		end
	end
end

-- Time -------------------------------------------------------------------------------------

function Kit.seconds(total: number): string
	total = math.max(0, math.floor(total + 0.5))
	if total < 60 then
		return `{total} s`
	elseif total < 3600 then
		local minutes, rest = total // 60, total % 60
		return if rest == 0 then `{minutes} min` else `{minutes} min {rest} s`
	end
	local hours, minutes = total // 3600, (total % 3600) // 60
	return if minutes == 0 then `{hours} h` else `{hours} h {minutes} min`
end

function Kit.ago(unix: any): string
	if typeof(unix) ~= "number" then
		return "never"
	end
	local diff = os.time() - unix
	if diff < 5 then
		return "just now"
	elseif diff < 120 then
		return `{diff} s ago`
	elseif diff < 7200 then
		return `{diff // 60} min ago`
	end
	return `{diff // 3600} h ago`
end

local function dateTime(): any
	local ok, value = pcall(function()
		return DateTime
	end)
	return if ok then value else nil
end

-- "2026-11-03 14:05" in the owner's local time (falls back to UTC with a suffix)
function Kit.localTime(unix: number): string
	local DT = dateTime()
	if DT then
		local ok, text = pcall(function()
			return DT.fromUnixTimestamp(unix):FormatLocalTime("YYYY-MM-DD HH:mm", "en-us")
		end)
		if ok and typeof(text) == "string" then
			return text
		end
	end
	return os.date("!%Y-%m-%d %H:%M", unix) .. " UTC"
end

-- Unix seconds for a local date and time, or nil when the numbers are not a real time
function Kit.toUnix(year: number, month: number, day: number, hour: number, minute: number): number?
	if month < 1 or month > 12 or day < 1 or day > 31 or hour < 0 or hour > 23 or minute < 0 or minute > 59 then
		return nil
	end
	local DT = dateTime()
	if DT then
		local ok, stamp = pcall(function()
			return DT.fromLocalTime(year, month, day, hour, minute).UnixTimestamp
		end)
		if ok and typeof(stamp) == "number" then
			return stamp
		end
	end
	-- No DateTime (tests): read the numbers as UTC so Kit.localTime's fallback round-trips
	local y = if month <= 2 then year - 1 else year
	local era = y // 400
	local yoe = y - era * 400
	local doy = (153 * (month + (if month > 2 then -3 else 9)) + 2) // 5 + day - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	local days = era * 146097 + doe - 719468
	return days * 86400 + hour * 3600 + minute * 60
end

function Kit.shortId(jobId: any): string
	local text = tostring(jobId or "")
	return if #text > 8 then string.sub(text, 1, 8) else text
end

return Kit
