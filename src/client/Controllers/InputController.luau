-- Binds combat controls for every device:
--   Keyboard & mouse: Left click = Light, E = Heavy, F (hold) = Block, Q = Dodge
--   Gamepad:          X = Light, Y = Heavy, L1 (hold) = Block, B = Dodge
--   Touch:            on-screen buttons next to the jump button
-- The bindings and labels live in BINDINGS so the HUD can show them.

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local InputController = {}

InputController.Bindings = {
	{
		name = "SNLight",
		label = "Light",
		inputs = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonX },
		keyText = "M1",
		padText = "X",
		touchPosition = UDim2.new(1, -205, 1, -115),
	},
	{
		name = "SNHeavy",
		label = "Heavy",
		inputs = { Enum.KeyCode.E, Enum.KeyCode.ButtonY },
		keyText = "E",
		padText = "Y",
		touchPosition = UDim2.new(1, -150, 1, -175),
	},
	{
		name = "SNBlock",
		label = "Block",
		inputs = { Enum.KeyCode.F, Enum.KeyCode.ButtonL1 },
		keyText = "F",
		padText = "L1",
		touchPosition = UDim2.new(1, -270, 1, -70),
	},
	{
		name = "SNDodge",
		label = "Dodge",
		inputs = { Enum.KeyCode.Q, Enum.KeyCode.ButtonB },
		keyText = "Q",
		padText = "B",
		touchPosition = UDim2.new(1, -80, 1, -205),
	},
}

function InputController:Init(controllers)
	self.combat = controllers.CombatController
end

function InputController:Start()
	local combat = self.combat
	local handlers = {
		SNLight = function(state)
			if state == Enum.UserInputState.Begin then
				combat:light()
			end
		end,
		SNHeavy = function(state)
			if state == Enum.UserInputState.Begin then
				combat:heavy()
			end
		end,
		SNBlock = function(state)
			if state == Enum.UserInputState.Begin then
				combat:setBlocking(true)
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				combat:setBlocking(false)
			end
		end,
		SNDodge = function(state)
			if state == Enum.UserInputState.Begin then
				combat:dodge()
			end
		end,
	}

	for _, binding in InputController.Bindings do
		local handler = handlers[binding.name]
		ContextActionService:BindAction(binding.name, function(_, state, input)
			-- Let clicks through to buttons and the 3D world as normal
			handler(state)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				return Enum.ContextActionResult.Pass
			end
			return Enum.ContextActionResult.Sink
		end, true, table.unpack(binding.inputs))
		ContextActionService:SetTitle(binding.name, binding.label)
		ContextActionService:SetPosition(binding.name, binding.touchPosition)
	end

	-- Releasing block if the window loses focus mid-hold
	UserInputService.WindowFocusReleased:Connect(function()
		combat:setBlocking(false)
	end)
end

-- "keyboard", "gamepad" or "touch", for showing the right button hints
function InputController.device(): string
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "touch"
	elseif string.find(last.Name, "Gamepad") then
		return "gamepad"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "touch"
	end
	return "keyboard"
end

return InputController
