-- Jeffery's practice fights, client side. Sends the requests (start, restart, stop) and shows what
-- the server reports: a small strip while a round runs (mode, time left, Restart, Exit), Jeffery's
-- short in-fight lines, and his feedback after the round through the existing DialoguePanel
-- (JefferyController). The server decides everything; nothing here is trusted.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Practice = require(ReplicatedStorage.Shared.Config.Practice)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Selection = require(ReplicatedStorage.Shared.Config.Selection)
local Components = require(script.Parent.Parent.UI.Components)
local Shell = require(script.Parent.Parent.UI.Shell)
local Theme = require(script.Parent.Parent.UI.Theme)

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ProgressRequest = Remotes:WaitForChild("ProgressRequest") :: RemoteEvent
local MatchRequest = Remotes:WaitForChild("MatchRequest") :: RemoteEvent
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local make = Components.make
local Colors = Theme.Colors

local PracticeController = {}

function PracticeController:Init(controllers)
	self.controllers = controllers
	self.active = false
	self.recommended = nil :: string?
	PracticeController.instance = self
end

function PracticeController:start(mode: string, options: { [string]: any }?)
	ProgressRequest:FireServer(Protocol.ProgressAction.PracticeStart, mode, options)
end

function PracticeController:restart()
	ProgressRequest:FireServer(Protocol.ProgressAction.PracticeRestart)
end

function PracticeController:stop()
	ProgressRequest:FireServer(Protocol.ProgressAction.PracticeStop)
end

local function inStudio(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and Selection.inTrainingZone((root :: BasePart).Position)
end

-- From How to Play or anywhere: go to the studio first, then the window opens
function PracticeController:openWindow()
	if inStudio() then
		Shell.open("Practice")
		return
	end
	self:travel()
	task.delay(2.5, function()
		if Shell.hasWindow("Practice") then
			Shell.open("Practice")
		end
	end)
end

function PracticeController:travel()
	if not inStudio() then
		MatchRequest:FireServer(Protocol.MatchAction.Travel, "Training")
		Shell.toast("Heading to the Training Studio.", "info")
	end
end

-- The strip -------------------------------------------------------------------------------------

function PracticeController:_buildStrip()
	local strip = make("Frame", {
		Name = "PracticeStrip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(440, 44), BackgroundColor3 = Colors.Panel, BackgroundTransparency = 0.1, BorderSizePixel = 0,
		Visible = false, ZIndex = 12, Parent = self.gui,
	}, { Components.corner(), Components.stroke(Colors.Cyan, 1, 0.5) })
	self.label = Components.text({
		Name = "Label", Text = "", Style = "Body", Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(210, 44), ZIndex = 13, Parent = strip,
	})
	Components.button("Restart", {
		Name = "Restart", Variant = "Secondary", KeepCase = true, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -112, 0.5, 0), Size = UDim2.fromOffset(96, 34), ZIndex = 13, Parent = strip,
	}, function()
		self:restart()
	end)
	Components.button("Exit", {
		Name = "Exit", Variant = "Danger", KeepCase = true, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(96, 34), ZIndex = 13, Parent = strip,
	}, function()
		self:stop()
	end)
	self.strip = strip
end

function PracticeController:_updateStrip()
	local strip = self.strip
	if not strip then
		return
	end
	strip.Visible = self.active
	if self.active then
		local left = math.max(0, math.ceil((self.endsAt or 0) - workspace:GetServerTimeNow()))
		self.label.Text = string.format("%s practice   %d:%02d", self.mode or "", left // 60, left % 60)
	end
end

-- Server messages -------------------------------------------------------------------------------

function PracticeController:_onMessage(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local jeffery = self.controllers and self.controllers.JefferyController
	if payload.kind == "State" then
		self.active = payload.active == true
		self.mode = payload.mode
		self.endsAt = payload.endsAt
		self:_updateStrip()
	elseif payload.kind == "Line" and typeof(payload.text) == "string" then
		-- Short and shown straight away (the usual hint queue waits for a quiet moment, which a fight never has)
		if jeffery and jeffery._showHint then
			jeffery:_showHint({ id = tostring(payload.id), text = payload.text, face = tostring(payload.face) })
		end
	elseif payload.kind == "Result" and typeof(payload.lines) == "table" then
		self.recommended = if typeof(payload.next) == "string" and Practice.Modes[payload.next] then payload.next else nil
		if jeffery and jeffery._say then
			jeffery:_say(payload.lines, tostring(payload.face or "thinking"), {
				title = "Jeffery",
				onDone = function()
					if self.recommended then
						Shell.toast(`Jeffery suggests {self.recommended} mode. Use the console to start it.`, "info")
					end
				end,
			})
		end
	elseif payload.kind == "Refused" and typeof(payload.text) == "string" then
		Shell.toast(payload.text, "info")
	end
end

function PracticeController:Start()
	self.gui = player:WaitForChild("PlayerGui"):WaitForChild("SNInterface")
	self:_buildStrip()
	DataEvent.OnClientEvent:Connect(function(kind, payload)
		if kind == Protocol.DataEvent.Practice then
			self:_onMessage(payload)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			self:_updateStrip()
		end
	end)
end

return PracticeController
