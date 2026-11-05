-- Client side of the Spectating Lounge's social features:
--   * the prompts "Lounge:Wheel", "Lounge:Refreshments" and "Lounge:Invite" (the world prompts carry
--     these Actions; WorldFxController ignores kinds it does not know)
--   * DataEvent "Lounge" messages from WheelService and RefreshmentService, handed to the windows
--   * the friends board: a local label on the board by the invite kiosk that lists your Roblox friends
--     who are in the lounge now (checked every few seconds, only while you are in the lounge)
-- Nothing here grants anything; it only opens windows and shows what the server sent.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Shell = require(script.Parent.Parent.UI.Shell)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local LoungeController = {}

local FRIEND_CHECK_SECONDS = 4
local localPlayer = Players.LocalPlayer

local friendCache: { [number]: boolean } = {}
local lastText = ""

function LoungeController:Init(controllers)
	self.controllers = controllers
end

local function insideLounge(room: Model, position: Vector3): boolean
	local cf, size = room:GetBoundingBox()
	local offset = cf:PointToObjectSpace(position)
	return math.abs(offset.X) <= size.X / 2 and math.abs(offset.Z) <= size.Z / 2
end

local function isFriend(other: Player): boolean
	local cached = friendCache[other.UserId]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return localPlayer:IsFriendsWith(other.UserId)
	end)
	friendCache[other.UserId] = ok and result == true
	return friendCache[other.UserId]
end

-- Updates the board's label with friends currently in the lounge
function LoungeController:_refreshFriends()
	local room = workspace:FindFirstChild("Lounge")
	if not room then
		return
	end
	local label = room:FindFirstChild("FriendsLabel", true)
	if not label or not label:IsA("TextLabel") then
		return
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or not insideLounge(room, root.Position) then
		return
	end
	local names = {}
	for _, other in Players:GetPlayers() do
		if other ~= localPlayer and other.Character then
			local theirs = other.Character:FindFirstChild("HumanoidRootPart")
			if theirs and theirs:IsA("BasePart") and insideLounge(room, theirs.Position) and isFriend(other) then
				table.insert(names, other.DisplayName)
			end
		end
	end
	table.sort(names)
	local text
	if #names == 0 then
		text = "None of your friends are in the lounge right now. Use the kiosk to invite one."
	else
		text = "In the lounge with you: " .. table.concat(names, ", ")
	end
	if text ~= lastText then
		lastText = text
		label.Text = text
	end
end

function LoungeController:Start()
	local windows = {
		require(script.Parent.Parent.UI.WheelWindow),
		require(script.Parent.Parent.UI.RefreshmentsWindow),
	}
	DataEvent.OnClientEvent:Connect(function(kind, data)
		if kind ~= Protocol.DataEvent.Lounge then
			return
		end
		for _, window in windows do
			window.onData(data)
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local action = prompt:GetAttribute("Action")
		if typeof(action) ~= "string" then
			return
		end
		local kind, argument = string.match(action, "^(%w+):(%w+)$")
		if kind ~= "Lounge" then
			return
		end
		if argument == "Wheel" and Shell.hasWindow("Wheel") then
			Shell.open("Wheel")
		elseif argument == "Refreshments" and Shell.hasWindow("Refreshments") then
			Shell.open("Refreshments")
		elseif argument == "Invite" then
			local invites = self.controllers and self.controllers.InviteController
			local result = if invites then invites:invite() else "unavailable"
			if result == "unavailable" then
				Shell.toast("Roblox is not offering invites for your account right now.", "info")
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(FRIEND_CHECK_SECONDS)
			pcall(function()
				self:_refreshFriends()
			end)
		end
	end)
end

return LoungeController
