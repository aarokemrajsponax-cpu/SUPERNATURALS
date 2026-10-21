-- Ice Age: a howling blizzard, frost creeping in from the screen edges, and an
-- icy colour grade. (Players frozen solid get their ice blocks from
-- AdminEffectsController, which handles freezing from any source.)

local Players = game:GetService("Players")

local Common = require(script.Parent.Common)

local FROST = Color3.fromRGB(200, 240, 255)

local function frostFrame(parent: Instance, anchor: Vector2, position: UDim2, size: UDim2, rotation: number)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = anchor
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = FROST
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = 1
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.5, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame
	frame.Parent = parent
	return frame
end

return function(context)
	local _, ungrade = Common.colorGrade({ TintColor = Color3.fromRGB(215, 235, 255), Saturation = -0.3, Brightness = 0.04, Contrast = 0.08 })
	local stopSnow = Common.sheet({
		color = ColorSequence.new(Color3.new(1, 1, 1)),
		rate = 320,
		size = NumberSequence.new(0.3, 0.15),
		speed = NumberRange.new(12, 18),
		lifetime = NumberRange.new(3, 4.5),
		height = 40,
		area = 150,
		lightEmission = 0.3,
		acceleration = Vector3.new(22, -2, 6),
		spread = Vector2.new(25, 25),
		rotSpeed = NumberRange.new(-120, 120),
	})

	-- Frost creeping in from the edges of the screen
	local gui = Instance.new("ScreenGui")
	gui.Name = "SNFrost"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -1
	local edges = {
		frostFrame(gui, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.25), 90),
		frostFrame(gui, Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1), UDim2.fromScale(1, 0.25), -90),
		frostFrame(gui, Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(0.2, 1), 0),
		frostFrame(gui, Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5), UDim2.fromScale(0.2, 1), 180),
	}
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, edge in edges do
		Common.tween(edge, 3, { BackgroundTransparency = 0.2 })
	end

	return function()
		ungrade()
		stopSnow()
		for _, edge in edges do
			Common.tween(edge, 1.5, { BackgroundTransparency = 1 })
		end
		task.delay(1.6, function()
			gui:Destroy()
		end)
	end
end
