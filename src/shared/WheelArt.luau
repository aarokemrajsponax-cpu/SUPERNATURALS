-- Draws the wheel face as GUI frames, used by the physical wheel in the lounge (a SurfaceGui) and by the
-- Wheel window, so both show the same wheel. A full pie of coloured wedges, thin dividers, a hub, and one
-- short UPRIGHT label per wedge (never rotated, never cut off). The chances are not on the wedges: they
-- are on the legend board beside the wheel and in the window (Config/Wheel).
-- Wedges are built from rotated stacked bars (a square GUI cannot draw a wedge), covered by dividers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Wheel = require(ReplicatedStorage.Shared.Config.Wheel)

local WheelArt = {}

local RINGS = 7
local INNER = 0.07

local function tint(kind: string, index: number): Color3
	local c = Wheel.KindColors[kind] or { 200, 200, 200 }
	local base = Color3.fromRGB(c[1], c[2], c[3])
	-- Neighbours alternate between two depths so wedges read apart
	return base:Lerp(Color3.fromRGB(10, 14, 22), if index % 2 == 0 then 0.5 else 0.66)
end

local function frame(parent: Instance, name: string, props: { [string]: any }): Frame
	local item = Instance.new("Frame")
	item.Name = name
	item.BorderSizePixel = 0
	item.BackgroundTransparency = 1
	for key, value in props do
		(item :: any)[key] = value
	end
	item.Parent = parent
	return item
end

local function centered(position: Vector2, size: Vector2): { [string]: any }
	return { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(position.X, position.Y), Size = UDim2.fromScale(size.X, size.Y) }
end

local function addCorner(item: GuiObject, scale: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(scale, 0)
	corner.Parent = item
end

local function addStroke(item: GuiObject, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = item
end

-- A small mark for a wedge with a symbol, centred in `holder` (a square frame)
local function symbolIn(holder: Frame, symbol: string, color: Color3)
	if symbol == "gem" then
		local gem = frame(holder, "Gem", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.62), BackgroundTransparency = 0, BackgroundColor3 = color, Rotation = 45 })
		addStroke(gem, Color3.fromRGB(240, 250, 255), 1)
	elseif symbol == "ring" then
		local ring = frame(holder, "Ring", centered(Vector2.new(0.5, 0.5), Vector2.new(0.9, 0.9)))
		addCorner(ring, 0.5)
		addStroke(ring, color, 3)
	elseif symbol == "burst" then
		for turn = 0, 1 do
			local star = frame(holder, "Burst" .. turn, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.62), BackgroundTransparency = 0, BackgroundColor3 = color, Rotation = 45 * turn })
		end
	elseif symbol == "plate" then
		local plate = frame(holder, "Plate", centered(Vector2.new(0.5, 0.5), Vector2.new(1, 0.55)))
		addCorner(plate, 0.2)
		addStroke(plate, color, 3)
	end
end

-- options: font (Font), textColor (Color3), maxText (number)
function WheelArt.draw(parent: GuiObject, options: { [string]: any }?)
	local opts = options or {}
	local count = #Wheel.Prizes
	local step = 360 / count
	local half = math.rad(step / 2)
	-- Wedges
	for index, prize in Wheel.Prizes do
		local arm = frame(parent, "Wedge" .. index, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Rotation = (index - 0.5) * step })
		local color = tint(prize.kind, index)
		local dr = (0.5 - INNER) / RINGS
		for ring = 1, RINGS do
			local rOuter = INNER + ring * dr
			local rMid = rOuter - dr / 2
			local width = 2 * rMid * math.tan(half) + 0.012
			frame(arm, "Bar" .. ring, {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5 - rMid), Size = UDim2.fromScale(width, dr + 0.004),
				BackgroundTransparency = 0, BackgroundColor3 = color,
			})
		end
	end
	-- Dividers over the seams
	for index = 1, count do
		local arm = frame(parent, "Divider" .. index, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Rotation = (index - 1) * step })
		frame(arm, "Line", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.012, 0, 0.5, 0),
			BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(214, 170, 110),
		})
	end
	-- Upright labels
	local radius = 0.325
	for index, prize in Wheel.Prizes do
		local theta = math.rad((index - 0.5) * step)
		local x, y = 0.5 + math.sin(theta) * radius, 0.5 - math.cos(theta) * radius
		local c = Wheel.KindColors[prize.kind] or { 255, 255, 255 }
		local accent = Color3.fromRGB(c[1], c[2], c[3])
		local hasText = prize.mark ~= nil and prize.mark ~= ""
		local holder = frame(parent, "Label" .. index, centered(Vector2.new(x, y), Vector2.new(0.17, 0.15)))
		if prize.symbol then
			local box = frame(holder, "Symbol", centered(Vector2.new(0.5, if hasText then 0.22 else 0.5), Vector2.new(0.3, if hasText then 0.42 else 0.5)))
			-- Keep the symbol square whatever the holder's shape
			local ratio = Instance.new("UIAspectRatioConstraint")
			ratio.AspectRatio = if prize.symbol == "plate" then 1.7 else 1
			ratio.Parent = box
			symbolIn(box, prize.symbol, accent:Lerp(Color3.fromRGB(255, 255, 255), 0.25))
		end
		if hasText then
			local label = Instance.new("TextLabel")
			label.Name = "Mark"
			label.BackgroundTransparency = 1
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.Position = UDim2.fromScale(0.5, if prize.symbol then 0.72 else 0.5)
			label.Size = UDim2.fromScale(1, if prize.symbol then 0.52 else 0.85)
			label.Text = prize.mark
			label.TextScaled = true
			label.TextColor3 = opts.textColor or Color3.fromRGB(246, 240, 228)
			label.FontFace = opts.font or Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.TextYAlignment = Enum.TextYAlignment.Center
			local cap = Instance.new("UITextSizeConstraint")
			cap.MaxTextSize = opts.maxText or 60
			cap.MinTextSize = 8
			cap.Parent = label
			label.Parent = holder
		end
	end
	-- Hub
	local hub = frame(parent, "Hub", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.12, 0.12), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(184, 115, 63) })
	addCorner(hub, 0.5)
	addStroke(hub, Color3.fromRGB(240, 210, 150), 2)
end

-- Mounts the wheel in a square `parent`: a copper rim disc with the pie inside it (so the bars' corners
-- stay inside the rim), then draws. Returns the pie frame.
function WheelArt.mount(parent: GuiObject, options: { [string]: any }?): Frame
	local rim = frame(parent, "Rim", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(150, 104, 62) })
	addCorner(rim, 0.5)
	local pie = frame(rim, "Pie", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.93, 0.93), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(10, 14, 22) })
	addCorner(pie, 0.5)
	WheelArt.draw(pie, options)
	return pie
end

return WheelArt
