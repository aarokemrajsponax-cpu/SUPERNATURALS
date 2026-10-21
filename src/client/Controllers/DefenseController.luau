-- Shows the interactive defense prompts the server sends and turns presses
-- into DefenseInput. The prompts sit low in the middle of the screen, below the
-- character, so they never hide the attack itself.
--   Prompt   "DODGE or BLOCK" with a shrinking timer: use your normal Dodge/Block
--   Timing   a bar with a marker sliding to the centre: press Block (F / L1) or tap
--   Mash     "BREAK FREE!": press Space, F, A or L1 (or tap) quickly
--   Redirect "REROUTE": press Block (F / L1) or tap to take the projectile over
-- Presses are only reports: the server judges the timing with its own clock.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local DefensePrompt = require(script.Parent.Parent.UI.DefensePrompt)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DefenseEvent = Remotes:WaitForChild("DefenseEvent") :: RemoteEvent
local DefenseInput = Remotes:WaitForChild("DefenseInput") :: RemoteEvent

local Event = Protocol.DefenseEvent
local Input = Protocol.DefenseInput
local player = Players.LocalPlayer

local DefenseController = {}

local ACTION = "SNDefensePress"
-- Keys that answer each prompt (touch players tap the prompt itself)
local KEYS = {
	Timing = { Enum.KeyCode.F, Enum.KeyCode.ButtonL1 },
	Redirect = { Enum.KeyCode.F, Enum.KeyCode.ButtonL1 },
	Mash = { Enum.KeyCode.Space, Enum.KeyCode.F, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonL1 },
}

local active: { [string]: any } = {}

function DefenseController:Init(controllers)
	self.input = controllers.InputController
end

function DefenseController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SNDefense"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function rescale()
		local viewport = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.7, 1.2)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()
	self.prompt = DefensePrompt.new(gui, function(kind: string, id: string)
		self:_press(kind, id)
	end)

	DefenseEvent.OnClientEvent:Connect(function(kind, data)
		if typeof(data) ~= "table" or typeof(data.id) ~= "string" then
			return
		end
		if kind == Event.Cue then
			self:_cue(data)
		elseif kind == Event.Result then
			self.prompt:result(data.id, data.kind, data.result)
			self:_forget(data.id)
		elseif kind == Event.Clear then
			self.prompt:hide(data.id)
			self:_forget(data.id)
		end
	end)

	RunService.RenderStepped:Connect(function()
		self.prompt:update(workspace:GetServerTimeNow(), self.input and self.input.device() or "keyboard")
	end)

	player.CharacterAdded:Connect(function()
		for id in active do
			self.prompt:hide(id)
		end
		table.clear(active)
		self:_rebind()
	end)
end

function DefenseController:_cue(data)
	if typeof(data.kind) ~= "string" then
		return
	end
	active[data.id] = data
	self.prompt:show(data)
	self:_rebind()
end

function DefenseController:_forget(id: string)
	if active[id] then
		active[id] = nil
		self:_rebind()
	end
end

-- The press keys only belong to the prompt while one is showing (so F still
-- blocks normally the rest of the time)
function DefenseController:_rebind()
	ContextActionService:UnbindAction(ACTION)
	local keys = {}
	for _, cue in active do
		for _, key in KEYS[cue.kind] or {} do
			if not table.find(keys, key) then
				table.insert(keys, key)
			end
		end
	end
	if #keys == 0 then
		return
	end
	ContextActionService:BindActionAtPriority(ACTION, function(_, state)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		-- The most urgent prompt gets the press
		local best = nil
		for _, cue in active do
			if KEYS[cue.kind] and (best == nil or (cue.impactAt or 0) < (best.impactAt or 0)) then
				best = cue
			end
		end
		if best then
			self:_press(best.kind, best.id)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 10, table.unpack(keys))
end

function DefenseController:_press(kind: string, id: string)
	local cue = active[id]
	if not cue then
		return
	end
	local input = if kind == "Mash" then Input.Mash elseif kind == "Timing" then Input.Timing elseif kind == "Redirect" then Input.Redirect else nil
	if not input then
		return
	end
	DefenseInput:FireServer(input, id)
	self.prompt:pressed(id, workspace:GetServerTimeNow())
	-- A timing bar or redirect takes one press; the server answers with the result
	if kind ~= "Mash" then
		cue.kind = "Answered"
		self:_rebind()
	end
end

return DefenseController
