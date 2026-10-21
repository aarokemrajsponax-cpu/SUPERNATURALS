-- Small building blocks for interfaces, so every panel, button and bar looks
-- and behaves the same.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Components = {}

local Colors = Theme.Colors

-- Creates an instance, sets properties, and parents children (a list or a map)
function Components.make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	for key, value in (props or {}) :: { [string]: any } do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	for _, child in (children or {}) :: { Instance } do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Components.corner(radius: UDim?): UICorner
	return Components.make("UICorner", { CornerRadius = radius or Theme.Corner })
end

function Components.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Components.make("UIStroke", {
		Color = color or Colors.Cyan,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Components.padding(pixels: number): UIPadding
	local amount = UDim.new(0, pixels)
	return Components.make("UIPadding", {
		PaddingTop = amount,
		PaddingBottom = amount,
		PaddingLeft = amount,
		PaddingRight = amount,
	})
end

-- A dark panel with rounded corners, a soft neon outline and a subtle gradient
function Components.panel(props: { [string]: any }?): Frame
	local merged = {
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		-- Catch clicks, so clicking a panel's background doesn't throw a punch
		Active = true,
	}
	for key, value in (props or {}) :: { [string]: any } do
		merged[key] = value
	end
	return Components.make("Frame", merged, {
		Components.corner(),
		Components.stroke(Colors.Cyan, 1.5, 0.55),
		Components.make("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 205, 230)),
			Rotation = 90,
		}),
	})
end

function Components.label(text: string, props: { [string]: any }?): TextLabel
	local merged = {
		BackgroundTransparency = 1,
		Text = text,
		Font = Theme.Fonts.Body,
		TextColor3 = Colors.Text,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
	}
	-- MaxTextSize isn't a TextLabel property; it goes on a size constraint
	local maxTextSize = 32
	for key, value in (props or {}) :: { [string]: any } do
		if key == "MaxTextSize" then
			maxTextSize = value
		else
			merged[key] = value
		end
	end
	return Components.make("TextLabel", merged, {
		Components.make("UITextSizeConstraint", { MaxTextSize = maxTextSize }),
	})
end

-- A button that lifts on hover and dips on press
function Components.button(text: string, props: { [string]: any }?, onClick: (() -> ())?): TextButton
	local merged = {
		BackgroundColor3 = Colors.PanelLight,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = text,
		Font = Theme.Fonts.Heading,
		TextColor3 = Colors.Text,
		TextScaled = true,
		Size = UDim2.new(1, 0, 0, 44),
	}
	local accent = Colors.Cyan
	for key, value in (props or {}) :: { [string]: any } do
		if key == "Accent" then
			accent = value
		else
			merged[key] = value
		end
	end
	local stroke = Components.stroke(accent, 1.5, 0.5)
	local button = Components.make("TextButton", merged, {
		Components.corner(Theme.SmallCorner),
		stroke,
		Components.make("UITextSizeConstraint", { MaxTextSize = 20 }),
		Components.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
	})
	local base = merged.BackgroundColor3
	local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, info, { BackgroundColor3 = Colors.PanelHover }):Play()
		TweenService:Create(stroke, info, { Transparency = 0 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, info, { BackgroundColor3 = base }):Play()
		TweenService:Create(stroke, info, { Transparency = 0.5 }):Play()
	end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

-- A horizontal fill bar. Returns the frame and a function set(fraction, color?)
function Components.bar(props: { [string]: any }?, fillColor: Color3): (Frame, (number, Color3?) -> ())
	local merged = {
		BackgroundColor3 = Colors.Background,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}
	for key, value in (props or {}) :: { [string]: any } do
		merged[key] = value
	end
	local fill = Components.make("Frame", {
		Name = "Fill",
		BackgroundColor3 = fillColor,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, {
		Components.corner(UDim.new(0, 6)),
		Components.make("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)),
			Rotation = 90,
		}),
	})
	local frame = Components.make("Frame", merged, { Components.corner(UDim.new(0, 6)), fill })
	local current = 1
	local function set(fraction: number, color: Color3?)
		fraction = math.clamp(fraction, 0, 1)
		if math.abs(fraction - current) > 0.001 then
			current = fraction
			TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(fraction, 1) }):Play()
		end
		if color then
			fill.BackgroundColor3 = color
		end
	end
	return frame, set
end

return Components
