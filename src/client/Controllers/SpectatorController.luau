-- Spectator mode: watch a match from the lounge (or a gallery) without fighting.
-- The server decides who spectates (MatchService, Event.Spectating { matchId, fighters, mode });
-- this controller owns the camera while it lasts, the control bar and the Watch window data.
--
--   Camera modes: Follow A, Follow B, Overview, Cinematic (a slow orbit). Following a fighter
--   who is concealed (the Ghost's veil, the owner's invisibility) never uses their exact
--   position: the camera holds the last view it had while they were visible and the bar says
--   so. Overview and Cinematic use an anchor that only moves while every fighter is visible.
--   Exit: the bar's Exit button (always visible), Backspace or gamepad B. The camera is
--   restored exactly (type, subject, CFrame, field of view) whether the player pressed Exit,
--   the server ended the match, or a fighter left (a vanished fighter only switches the view
--   to the overview).
--
-- Also the single listener for Matches (to the Watch window) and PredictionResult (a plain
-- informational toast: predictions never pay anything).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Components = require(script.Parent.Parent.UI.Components)
local Shell = require(script.Parent.Parent.UI.Shell)
local Theme = require(script.Parent.Parent.UI.Theme)
local WatchWindow = require(script.Parent.Parent.UI.WatchWindow)

local Attribute = Protocol.Attribute
local Colors = Theme.Colors
local make = Components.make

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchEvent = Remotes:WaitForChild("MatchEvent") :: RemoteEvent
local MatchRequest = Remotes:WaitForChild("MatchRequest") :: RemoteEvent
local Event = Protocol.MatchEvent

local player = Players.LocalPlayer

local SpectatorController = {}

local BIND_NAME = "SNSpectatorCamera"
local EXIT_ACTION = "SNSpectatorExit"
local SMOOTHING = 7
local FOLLOW_BACK, FOLLOW_UP, FOLLOW_AHEAD = 14, 6, 5

export type Modes = "FollowA" | "FollowB" | "Overview" | "Cinematic"
SpectatorController.Modes = { "FollowA", "FollowB", "Overview", "Cinematic" }

type Saved = { cameraType: Enum.CameraType, subject: Instance?, cframe: CFrame, fov: number }
type State = {
	matchId: string,
	fighters: { Model },
	label: string,
	mode: Modes,
	saved: Saved,
	anchor: Vector3?,
	focus: { [number]: Vector3 },
	away: { [number]: Vector3 },
	gone: { [number]: boolean },
	names: { string },
	time: number,
	note: string,
}

local active: State? = nil
local latestMatches: { any } = {}
local bar: Frame? = nil
local statusLabel: TextLabel? = nil
local modeButtons: { [string]: TextButton } = {}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(model: Model?): BasePart?
	if not model or not model.Parent then
		return nil
	end
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Concealed (the Ghost's veil) or the owner's invisibility: never tracked exactly
local function concealed(model: Model): boolean
	if serverNow() < (model:GetAttribute(Attribute.StatusPrefix .. "Concealed") or 0) then
		return true
	end
	local owner = Players:GetPlayerFromCharacter(model)
	return owner ~= nil and owner:GetAttribute(Attribute.Invisible) == true
end

local function flat(vector: Vector3): Vector3
	local result = Vector3.new(vector.X, 0, vector.Z)
	return if result.Magnitude > 0.01 then result.Unit else Vector3.new(0, 0, 1)
end

-- Bar ------------------------------------------------------------------------------------------

local function setStatus(text: string)
	if statusLabel and statusLabel.Text ~= text then
		statusLabel.Text = text
	end
end

local function fighterName(index: number): string
	local name = if active then active.names[index] or "Fighter" else "Fighter"
	return if #name > 12 then string.sub(name, 1, 11) .. "." else name
end

local function refreshBar()
	if not bar then
		return
	end
	local state = active
	bar.Visible = state ~= nil
	if statusLabel then
		statusLabel.Visible = state ~= nil
	end
	if not state then
		return
	end
	local function relabel(id: string, text: string, selectedMode: boolean, disabled: boolean)
		local button = modeButtons[id]
		if button then
			button.Text = text
			Components.setSelected(button, selectedMode)
			Components.setDisabled(button, disabled, if disabled then "That fighter has left" else nil)
		end
	end
	relabel("FollowA", `Follow {fighterName(1)}`, state.mode == "FollowA", state.gone[1] == true or state.fighters[1] == nil)
	relabel("FollowB", `Follow {fighterName(2)}`, state.mode == "FollowB", state.gone[2] == true or state.fighters[2] == nil)
	relabel("Overview", "Overview", state.mode == "Overview", false)
	relabel("Cinematic", "Cinematic", state.mode == "Cinematic", false)
	local text = `Watching {state.label}`
	if state.note ~= "" then
		text ..= `  |  {state.note}`
	end
	setStatus(text)
end

function SpectatorController.setMode(mode: Modes)
	local state = active
	if not state then
		return
	end
	local index = if mode == "FollowA" then 1 elseif mode == "FollowB" then 2 else 0
	if index > 0 and (state.gone[index] or not state.fighters[index]) then
		return
	end
	state.mode = mode
	state.note = ""
	refreshBar()
end

-- Camera ---------------------------------------------------------------------------------------

local function step(dt: number)
	local state = active
	local camera = workspace.CurrentCamera
	if not state or not camera then
		return
	end
	state.time += dt

	-- Who is still here, and who may be tracked
	local present: { [number]: { position: Vector3, hidden: boolean } } = {}
	local allVisible, anyVisible, sum, count = true, false, Vector3.zero, 0
	for index, model in state.fighters do
		local root = rootOf(model)
		if root then
			local hidden = concealed(model)
			present[index] = { position = root.Position, hidden = hidden }
			if hidden then
				allVisible = false
			else
				anyVisible = true
				sum += root.Position
				count += 1
			end
		elseif not state.gone[index] then
			state.gone[index] = true
			if state.mode == "FollowA" and index == 1 or state.mode == "FollowB" and index == 2 then
				state.mode = "Overview"
				state.note = "A fighter left. Showing the overview."
			end
			refreshBar()
		end
	end
	if count > 0 and (allVisible or not state.anchor) then
		state.anchor = sum / count
	end
	local anchor = state.anchor or camera.CFrame.Position

	local target: CFrame
	local index = if state.mode == "FollowA" then 1 elseif state.mode == "FollowB" then 2 else 0
	if index > 0 then
		local info = present[index]
		local other = present[3 - index]
		local note = ""
		if info and not info.hidden then
			local focus = info.position + Vector3.new(0, 2.5, 0)
			state.focus[index] = focus
			if other and not other.hidden then
				state.away[index] = flat(info.position - other.position)
			end
		elseif info then
			note = `{fighterName(index)} is concealed. Holding the last view.`
		end
		local focus = state.focus[index] or anchor
		local away = state.away[index] or Vector3.new(0, 0, 1)
		local position = focus + away * FOLLOW_BACK + Vector3.new(0, FOLLOW_UP, 0)
		target = CFrame.lookAt(position, focus - away * FOLLOW_AHEAD)
		if note ~= state.note then
			state.note = note
			refreshBar()
		end
	elseif state.mode == "Overview" then
		local spread = 0
		for _, info in present do
			if not info.hidden then
				spread = math.max(spread, (info.position - anchor).Magnitude)
			end
		end
		local distance = math.clamp(spread * 1.2 + 30, 34, 70)
		target = CFrame.lookAt(anchor + Vector3.new(0, distance * 0.75, distance), anchor + Vector3.new(0, 2, 0))
	else
		local angle = state.time * 0.18
		local radius = 30 + 5 * math.sin(state.time * 0.11)
		local height = 11 + 3 * math.sin(state.time * 0.23)
		local position = anchor + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		target = CFrame.lookAt(position, anchor + Vector3.new(0, 3, 0))
	end
	local alpha = 1 - math.exp(-SMOOTHING * dt)
	camera.CFrame = camera.CFrame:Lerp(target, alpha)
end

-- Starts (or retargets) spectating: saves the camera exactly once
function SpectatorController.begin(data: any)
	local camera = workspace.CurrentCamera
	if typeof(data) ~= "table" or typeof(data.matchId) ~= "string" or not camera then
		return
	end
	local fighters = {}
	for _, model in data.fighters or {} do
		if typeof(model) == "Instance" and model:IsA("Model") then
			table.insert(fighters, model)
		end
	end
	local saved: Saved
	local previous = active
	if previous then
		saved = previous.saved
	else
		saved = { cameraType = camera.CameraType, subject = camera.CameraSubject, cframe = camera.CFrame, fov = camera.FieldOfView }
	end
	local names = {}
	for _, model in fighters do
		table.insert(names, model.Name)
	end
	active = {
		matchId = data.matchId,
		fighters = fighters,
		label = if #names > 0 then table.concat(names, " vs ") else tostring(data.mode or "a match"),
		mode = "Overview",
		saved = saved,
		anchor = nil,
		focus = {},
		away = {},
		gone = {},
		names = names,
		time = 0,
		note = "",
	}
	WatchWindow.setSpectating(true)
	if Shell.isOpen("Watch") then
		Shell.close()
	end
	camera.CameraType = Enum.CameraType.Scriptable
	pcall(function()
		RunService:UnbindFromRenderStep(BIND_NAME)
	end)
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 3, step)
	pcall(function()
		ContextActionService:BindAction(EXIT_ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				SpectatorController.exit()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB)
	end)
	refreshBar()
end

-- Puts the camera back exactly as it was when spectating began
function SpectatorController.restore()
	local state = active
	if not state then
		return
	end
	active = nil
	pcall(function()
		RunService:UnbindFromRenderStep(BIND_NAME)
	end)
	pcall(function()
		ContextActionService:UnbindAction(EXIT_ACTION)
	end)
	local camera = workspace.CurrentCamera
	if camera then
		local saved = state.saved
		camera.CameraType = saved.cameraType
		local subject = saved.subject
		if not subject or not subject.Parent then
			local character = player.Character
			subject = character and character:FindFirstChildOfClass("Humanoid")
		end
		if subject then
			camera.CameraSubject = subject
		end
		camera.CFrame = saved.cframe
		camera.FieldOfView = saved.fov
	end
	WatchWindow.setSpectating(false)
	refreshBar()
end

-- The player chose Exit: tell the server and restore at once
function SpectatorController.exit()
	if not active then
		return
	end
	MatchRequest:FireServer(Protocol.MatchAction.StopSpectating)
	SpectatorController.restore()
end

function SpectatorController.isActive(): boolean
	return active ~= nil
end

function SpectatorController.currentMode(): string?
	return if active then active.mode else nil
end

function SpectatorController.matches(): { any }
	return latestMatches
end

-- Building the bar ----------------------------------------------------------------------------------

local function buildBar()
	local host = Shell.layer("chrome") or Shell.layer("toasts")
	if not host then
		local gui = make("ScreenGui", { Name = "SNSpectator", ResetOnSpawn = false, Parent = player:WaitForChild("PlayerGui") })
		host = make("Frame", { Name = "Host", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	end
	local panel = Components.panel({
		Name = "SpectatorBar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(640, 60), BackgroundTransparency = 0.1, Visible = false, ZIndex = 20, Parent = host,
	})
	Components.padding(8, 8, 8, 8).Parent = panel
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = panel,
	})
	local labels = { FollowA = "Follow A", FollowB = "Follow B", Overview = "Overview", Cinematic = "Cinematic" }
	for order, id in SpectatorController.Modes do
		modeButtons[id] = Components.button(labels[id], {
			Name = "Mode_" .. id, Variant = "Secondary", KeepCase = true, LayoutOrder = order, Size = UDim2.fromOffset(116, 44), Parent = panel,
		}, function()
			SpectatorController.setMode(id)
		end)
	end
	Components.button("Exit", {
		Name = "ExitButton", Variant = "Primary", KeepCase = true, LayoutOrder = 10, Size = UDim2.fromOffset(88, 44), Parent = panel,
	}, function()
		SpectatorController.exit()
	end)
	statusLabel = Components.text({
		Name = "SpectatorStatus", Style = "Label", AlignX = "Center", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -84), Size = UDim2.fromOffset(640, 24), Visible = true, Parent = host,
	})
	statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	bar = panel
	statusLabel.Visible = false
end

function SpectatorController:Init(_controllers) end

function SpectatorController:Start()
	buildBar()
	MatchEvent.OnClientEvent:Connect(function(kind, data)
		if kind == Event.Matches and typeof(data) == "table" then
			latestMatches = data
			WatchWindow.setMatches(data)
		elseif kind == Event.Spectating then
			if typeof(data) == "table" then
				SpectatorController.begin(data)
			else
				-- The server ended it: the player exited elsewhere, the match ended or a fighter left
				SpectatorController.restore()
			end
		elseif kind == Event.PredictionResult and typeof(data) == "table" then
			local total, right = data.predictions or 0, data.correctCount or 0
			local accuracy = if total > 0 then math.floor(100 * right / total + 0.5) else 0
			local verdict = if data.correct then "Your prediction was correct." else "Your prediction was not correct."
			Shell.toast(`{verdict} {right} of {total} correct ({accuracy}%).`, "info")
		end
	end)
end

return SpectatorController
