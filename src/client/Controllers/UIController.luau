-- Builds the interface and keeps it in sync with the server: the HUD, the
-- fight menu and queue, the match HUD and results, notices, and settings.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Components = require(script.Parent.Parent.UI.Components)
local Theme = require(script.Parent.Parent.UI.Theme)
local Hud = require(script.Parent.Parent.UI.Hud)
local Menu = require(script.Parent.Parent.UI.Menu)
local MatchHud = require(script.Parent.Parent.UI.MatchHud)
local SettingsPanel = require(script.Parent.Parent.UI.SettingsPanel)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchRequest = Remotes:WaitForChild("MatchRequest") :: RemoteEvent
local MatchEvent = Remotes:WaitForChild("MatchEvent") :: RemoteEvent

local Action = Protocol.MatchAction
local Event = Protocol.MatchEvent

local player = Players.LocalPlayer

local UIController = {}

function UIController:Init(controllers)
	self.input = controllers.InputController
	self.effects = controllers.EffectsController
end

function UIController:Start()
	local gui = Components.make("ScreenGui", {
		Name = "SNInterface",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	-- Scale everything to the screen so it fits phones and big monitors alike
	local scale = Components.make("UIScale", { Parent = gui })
	local function rescale()
		local viewport = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.6, 1.2)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()

	local hud = Hud.build(gui, self.input.Bindings, self.input.device, self.effects.currentGuard)
	local menu = Menu.build(gui, {
		queue = function(modeName)
			MatchRequest:FireServer(Action.Queue, modeName)
		end,
		leaveQueue = function()
			MatchRequest:FireServer(Action.LeaveQueue)
		end,
		travel = function(destination)
			MatchRequest:FireServer(Action.Travel, destination)
		end,
	})
	local matchHud = MatchHud.build(gui, function()
		MatchRequest:FireServer(Action.ReturnToLobby)
	end)
	SettingsPanel.build(gui)

	-- Short notices in the middle of the screen
	local notice = Components.label("", {
		Name = "Notice",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.24),
		Size = UDim2.fromOffset(600, 40),
		Font = Theme.Fonts.Heading,
		TextColor3 = Theme.Colors.Gold,
		TextStrokeTransparency = 0.3,
		TextTransparency = 1,
		MaxTextSize = 26,
		Parent = gui,
	})
	local noticeToken = 0
	local function showNotice(text: string)
		noticeToken += 1
		local token = noticeToken
		notice.Text = text
		notice.TextTransparency = 0
		task.delay(2.5, function()
			if token == noticeToken then
				TweenService:Create(notice, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			end
		end)
	end

	local inMatch = false
	MatchEvent.OnClientEvent:Connect(function(kind, data)
		if kind == Event.Queue then
			menu.setQueue(if typeof(data) == "table" then data else nil)
		elseif kind == Event.State and typeof(data) == "table" then
			inMatch = true
			menu.setQueue(nil)
			menu.setAllowed(false)
			matchHud.setState(data)
		elseif kind == Event.Knockout and typeof(data) == "table" then
			matchHud.addKnockout(data)
		elseif kind == Event.Results and typeof(data) == "table" then
			matchHud.showResults(data)
		elseif kind == Event.Ended then
			inMatch = false
			matchHud.clear()
			menu.setAllowed(true)
		elseif kind == Event.Notice and typeof(data) == "table" and typeof(data.text) == "string" then
			showNotice(data.text)
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 1 / 20 then
			return
		end
		elapsed = 0
		hud.update()
		menu.update()
		if inMatch then
			matchHud.update()
		end
	end)
end

return UIController
