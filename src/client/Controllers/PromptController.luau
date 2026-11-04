-- One look for every ProximityPrompt: a slim navy plate floating by the object with
-- a key cap, the action, the object's name and (for held prompts) a ring that fills
-- while the key is held. Every prompt is switched to Style Custom on the client, so
-- the engine hands drawing to PromptShown / PromptHidden and the default bubble
-- never appears. Prompts keep all their server-set properties and triggers.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Components = require(script.Parent.Parent.UI.Components)
local Theme = require(script.Parent.Parent.UI.Theme)

local Colors = Theme.Colors

local PromptController = {}

type Shown = { gui: BillboardGui, destroy: () -> (), connections: { RBXScriptConnection } }
local shown: { [ProximityPrompt]: Shown } = {}

local GAMEPAD_NAMES = {
	ButtonA = "A",
	ButtonB = "B",
	ButtonX = "X",
	ButtonY = "Y",
	ButtonL1 = "LB",
	ButtonR1 = "RB",
	ButtonL2 = "LT",
	ButtonR2 = "RT",
}

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "Tap"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return GAMEPAD_NAMES[prompt.GamepadKeyCode.Name] or prompt.GamepadKeyCode.Name
	end
	local ok, text = pcall(function()
		return UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
	end)
	if ok and typeof(text) == "string" and text ~= "" then
		return text
	end
	return if prompt.KeyboardKeyCode == Enum.KeyCode.Unknown then "E" else prompt.KeyboardKeyCode.Name
end

local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any })
	TweenService:Create(instance, info, goal):Play()
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if shown[prompt] then
		return
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local held = prompt.HoldDuration > 0
	local action = if prompt.ActionText ~= "" then prompt.ActionText else "Use"
	local width = math.clamp(Components.textWidth(action, 20) + 112, 170, 340)

	local gui = Instance.new("BillboardGui")
	gui.Name = "SNPrompt"
	gui.Active = true
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Size = UDim2.fromOffset(width, if prompt.ObjectText ~= "" then 76 else 56)
	gui.StudsOffset = Vector3.new(0, 0, 0)
	gui.SizeOffset = Vector2.new(0, 0)
	gui.Adornee = if prompt.Parent and prompt.Parent:IsA("Attachment") or prompt.Parent and prompt.Parent:IsA("BasePart") then prompt.Parent else nil
	gui.MaxDistance = math.max(prompt.MaxActivationDistance + 4, 12)

	local plate = Components.panel({
		Name = "Plate",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.1,
		Parent = gui,
	})
	local scale = Instance.new("UIScale")
	scale.Scale = 0.92
	scale.Parent = plate
	plate.BackgroundTransparency = 1

	-- Key cap with the hold ring around it
	local ringHolder = Instance.new("Frame")
	ringHolder.Name = "KeyArea"
	ringHolder.AnchorPoint = Vector2.new(0, 0.5)
	ringHolder.Position = UDim2.new(0, 8, 0.5, 0)
	ringHolder.Size = UDim2.fromOffset(40, 40)
	ringHolder.BackgroundTransparency = 1
	ringHolder.Parent = plate
	local cap = Components.keycap(keyText(prompt, inputType), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Height = 32,
		Parent = ringHolder,
	})
	cap.AutomaticSize = Enum.AutomaticSize.None
	cap.Size = UDim2.fromOffset(32, 32)
	local setRing = function(_: number) end
	if held then
		local ring, set = Components.ring({
			Size = UDim2.fromOffset(40, 40),
			Thickness = 3,
			Color = Colors.Cyan,
			Track = Colors.Stroke,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Parent = ringHolder,
		})
		ring.Size = UDim2.fromOffset(40, 40)
		setRing = set
	end

	local textArea = Instance.new("Frame")
	textArea.Name = "Text"
	textArea.BackgroundTransparency = 1
	textArea.Position = UDim2.fromOffset(56, 0)
	textArea.Size = UDim2.new(1, -64, 1, 0)
	textArea.Parent = plate
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = textArea
	Components.text({
		Name = "Action",
		Text = action,
		Style = "body",
		Weight = "SemiBold",
		TextSize = 18,
		Color = Colors.Text,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = textArea,
	})
	if prompt.ObjectText ~= "" then
		Components.text({
			Name = "Object",
			Text = prompt.ObjectText,
			Style = "caption",
			TextSize = 16,
			Color = Colors.TextDim,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 22),
			Parent = textArea,
		})
	end

	local connections: { RBXScriptConnection } = {}
	-- Touch and mouse can press the plate itself: forward it as the prompt's input
	do
		local button = Instance.new("TextButton")
		button.Name = "Press"
		button.BackgroundTransparency = 1
		button.Text = ""
		button.Size = UDim2.fromScale(1, 1)
		button.ZIndex = 10
		button.Parent = plate
		table.insert(connections, button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldBegin()
			end
		end))
		table.insert(connections, button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldEnd()
			end
		end))
	end

	-- The ring and a brief press
	local stroke = plate:FindFirstChildOfClass("UIStroke")
	table.insert(connections, ProximityPromptService.PromptButtonHoldBegan:Connect(function(which)
		if which ~= prompt then
			return
		end
		tween(scale, Theme.Motion.Press, { Scale = 0.96 })
		if stroke then
			stroke.Color = Colors.Cyan
		end
		if held then
			local started = os.clock()
			task.spawn(function()
				while shown[prompt] and os.clock() - started < prompt.HoldDuration + 0.1 do
					setRing(math.clamp((os.clock() - started) / prompt.HoldDuration, 0, 1))
					task.wait()
				end
			end)
		end
	end))
	table.insert(connections, ProximityPromptService.PromptButtonHoldEnded:Connect(function(which)
		if which ~= prompt then
			return
		end
		setRing(0)
		tween(scale, Theme.Motion.Fast, { Scale = 1 })
		if stroke then
			stroke.Color = Colors.Stroke
		end
	end))
	table.insert(connections, prompt.Triggered:Connect(function()
		setRing(0)
	end))

	gui.Parent = playerGui
	tween(scale, Theme.Motion.Normal, { Scale = 1 })
	tween(plate, Theme.Motion.Normal, { BackgroundTransparency = 0.1 })

	shown[prompt] = {
		gui = gui,
		connections = connections,
		destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			tween(scale, Theme.Motion.In, { Scale = 0.92 })
			tween(plate, Theme.Motion.In, { BackgroundTransparency = 1 })
			task.delay(0.16, function()
				gui:Destroy()
			end)
		end,
	}
end

local function hide(prompt: ProximityPrompt)
	local entry = shown[prompt]
	if entry then
		shown[prompt] = nil
		entry.destroy()
	end
end

local function adopt(instance: Instance)
	if instance:IsA("ProximityPrompt") and instance.Style ~= Enum.ProximityPromptStyle.Custom then
		instance.Style = Enum.ProximityPromptStyle.Custom
	end
end

function PromptController:Start()
	ProximityPromptService.PromptShown:Connect(show)
	ProximityPromptService.PromptHidden:Connect(hide)
	workspace.DescendantAdded:Connect(adopt)
	for _, instance in workspace:GetDescendants() do
		adopt(instance)
	end
end

return PromptController
