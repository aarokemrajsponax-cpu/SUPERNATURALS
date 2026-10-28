-- Builds the interface and keeps it in sync with the server: the Shell (top
-- bar, dock, windows, toasts) with the Play and Settings windows, the HUD,
-- the queue pill, the match HUD and results, and server notices.
-- Other controllers reach the pieces through UIController.shell / .hud / .play.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Components = require(script.Parent.Parent.UI.Components)
local Theme = require(script.Parent.Parent.UI.Theme)
local Shell = require(script.Parent.Parent.UI.Shell)
local Hud = require(script.Parent.Parent.UI.Hud)
local PlayWindow = require(script.Parent.Parent.UI.PlayWindow)
local SettingsWindow = require(script.Parent.Parent.UI.SettingsWindow)
local MatchHud = require(script.Parent.Parent.UI.MatchHud)
local AbilityBar = require(script.Parent.Parent.UI.AbilityBar)
local PowersWindow = require(script.Parent.Parent.UI.PowersWindow)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchRequest = Remotes:WaitForChild("MatchRequest") :: RemoteEvent
local MatchEvent = Remotes:WaitForChild("MatchEvent") :: RemoteEvent

local Event = Protocol.MatchEvent
local Colors = Theme.Colors

local player = Players.LocalPlayer

local UIController = {}

-- How long a notice stays in the middle of the screen during a fight
local NOTICE_SECONDS = 2.5

function UIController:Init(controllers)
	self.input = controllers.InputController
	self.effects = controllers.EffectsController
	self.abilities = controllers.AbilityController
end

function UIController:Start()
	local gui = Components.make("ScreenGui", {
		Name = "SNInterface",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	-- The Shell owns the single UIScale that fits everything to the screen
	Shell.init(gui, { input = self.input })
	local play = PlayWindow.register()
	PowersWindow.register()
	SettingsWindow.register()
	require(script.Parent.Parent.UI.ArchiveWindow).register()

	local hud = Hud.build(gui, self.input.Bindings, self.input.device, self.effects.currentGuard)
	local abilityBar = AbilityBar.build(hud.abilityRow, self.abilities, self.input.device)
	local matchHud = MatchHud.build(gui, function()
		MatchRequest:FireServer(Protocol.MatchAction.ReturnToLobby)
	end)
	self.shell = Shell
	self.hud = hud
	self.play = play
	self.matchHud = matchHud

	-- Notices: a ribbon in the middle during fights, a toast otherwise
	local ribbon = Components.panel({
		Name = "Notice",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.26),
		Size = UDim2.fromOffset(0, 48),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0.12,
		Active = false,
		Visible = false,
		Parent = gui,
	})
	local ribbonStroke = ribbon:FindFirstChildOfClass("UIStroke") :: UIStroke
	ribbonStroke.Color = Colors.Gold
	ribbonStroke.Transparency = 0.3
	Components.padding(0, Theme.Space.XL, 0, Theme.Space.XL).Parent = ribbon
	local ribbonText = Components.text({
		Style = "Heading",
		Weight = "ExtraBold",
		Color = Colors.Gold,
		AlignX = "Center",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.None,
		Parent = ribbon,
	})
	local ribbonScale = Components.make("UIScale", { Parent = ribbon })
	local noticeToken = 0
	local function showRibbon(text: string)
		noticeToken += 1
		local token = noticeToken
		ribbonText.Text = text
		ribbon.Visible = true
		ribbonScale.Scale = 0.85
		TweenService:Create(ribbonScale, Theme.Motion.Pop, { Scale = 1 }):Play()
		Components.fade(ribbon, true, Theme.Motion.Normal)
		task.delay(NOTICE_SECONDS, function()
			if token == noticeToken then
				Components.fade(ribbon, false, TweenInfo.new(0.4), function()
					if token == noticeToken then
						ribbon.Visible = false
					end
				end)
			end
		end)
	end

	local inMatch = false
	MatchEvent.OnClientEvent:Connect(function(kind, data)
		if kind == Event.Queue then
			play.setQueue(if typeof(data) == "table" then data else nil)
		elseif kind == Event.State and typeof(data) == "table" then
			if not inMatch then
				inMatch = true
				Shell.setMode("Match")
			end
			play.setQueue(nil)
			matchHud.setState(data)
		elseif kind == Event.Knockout and typeof(data) == "table" then
			matchHud.addKnockout(data)
		elseif kind == Event.Results and typeof(data) == "table" then
			matchHud.showResults(data)
		elseif kind == Event.Ended then
			inMatch = false
			matchHud.clear()
			Shell.setMode("Lobby")
		elseif kind == Event.Notice and typeof(data) == "table" and typeof(data.text) == "string" then
			if inMatch then
				showRibbon(data.text)
			else
				Shell.toast(data.text, "info")
			end
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
		abilityBar.update()
		play.update()
		if inMatch then
			matchHud.update()
		end
	end)
end

return UIController
