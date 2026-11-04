-- Builds the interface and keeps it in sync with the server: the Shell (top
-- bar, dock, windows, toasts) with the Play and Settings windows, the HUD,
-- the queue pill, the match HUD and results, and server notices.
-- Other controllers reach the pieces through UIController.shell / .hud / .play.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Components = require(script.Parent.Parent.UI.Components)
local Shell = require(script.Parent.Parent.UI.Shell)
local Hud = require(script.Parent.Parent.UI.Hud)
local PlayWindow = require(script.Parent.Parent.UI.PlayWindow)
local SettingsWindow = require(script.Parent.Parent.UI.SettingsWindow)
local MatchHud = require(script.Parent.Parent.UI.MatchHud)
local AbilityBar = require(script.Parent.Parent.UI.AbilityBar)
local CombatView = require(script.Parent.Parent.UI.CombatView)
local PowersWindow = require(script.Parent.Parent.UI.PowersWindow)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchRequest = Remotes:WaitForChild("MatchRequest") :: RemoteEvent
local MatchEvent = Remotes:WaitForChild("MatchEvent") :: RemoteEvent

local Event = Protocol.MatchEvent

local player = Players.LocalPlayer

local UIController = {}

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
	require(script.Parent.Parent.UI.ShopWindow).register()
	require(script.Parent.Parent.UI.SeasonPassWindow).register()
	require(script.Parent.Parent.UI.CalendarWindow).register()
	SettingsWindow.register()
	require(script.Parent.Parent.UI.ArchiveWindow).register()
	require(script.Parent.Parent.UI.LearnWindow).register()
	require(script.Parent.Parent.UI.LockerWindow).register()
	require(script.Parent.Parent.UI.WatchWindow).register()
	require(script.Parent.Parent.UI.WheelWindow).register() -- also registers the Refreshments window
	require(script.Parent.Parent.UI.PracticeWindow).register()

	local hud = Hud.build(gui, self.input.Bindings, self.input.device, self.effects.currentGuard)
	local abilityBar = AbilityBar.build(hud.abilityRow, self.abilities, self.input.device)
	local matchHud = MatchHud.build(gui, function()
		MatchRequest:FireServer(Protocol.MatchAction.ReturnToLobby)
	end)
	self.shell = Shell
	self.hud = hud
	self.play = play
	self.matchHud = matchHud

	-- Notices: an announcement in the middle during fights (MatchHud.announce), a toast otherwise

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
		elseif kind == Event.Spectating and data == nil then
			-- A spectator's watching ended (match over, Exit or a fighter left): back to the lobby look
			if inMatch then
				inMatch = false
				matchHud.clear()
				Shell.setMode("Lobby")
			end
		elseif kind == Event.Ended then
			inMatch = false
			matchHud.clear()
			Shell.setMode("Lobby")
		elseif kind == Event.Notice and typeof(data) == "table" and typeof(data.text) == "string" then
			if inMatch then
				matchHud.announce(data.text)
			else
				Shell.toast(data.text, "info")
			end
		end
	end)

	-- Where the player stands decides what the screen shows (UI/CombatView reads the server's
	-- context): the combat HUD only in a fight or in training, and the fight layout (no dock,
	-- wallet or player card) in a match and in the Training Studio.
	local combatActive = false
	local function syncContext()
		local character = player.Character
		local mode = Shell.getMode()
		local active = CombatView.active(character, mode)
		if active ~= combatActive then
			combatActive = active
			hud.setCombat(active)
		end
		if mode == "Lobby" or mode == "Training" then
			local want = if CombatView.practising(character) then "Training" else "Lobby"
			if want ~= mode then
				Shell.setMode(want)
			end
		end
	end
	self.syncContext = syncContext
	syncContext()

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 1 / 20 then
			return
		end
		elapsed = 0
		syncContext()
		-- Nothing below the lobby essentials runs while the combat interface is away
		if combatActive then
			hud.update()
			abilityBar.update()
		end
		play.update()
		if inMatch then
			matchHud.update()
		end
	end)
end

return UIController
