-- Invite friends: Roblox's own invite prompt (SocialService), opened from the Play window.
-- Checks CanSendGameInviteAsync first (in pcall), then PromptGameInvite with a short message.
-- Config/Community.InviteMessageId (a Notification string made in Creator Hub) is only used
-- when the owner sets it. Nothing here can break play: every call is protected.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Community = require(ReplicatedStorage.Shared.Config.Community)

local InviteController = {}

local player = Players.LocalPlayer
local lastPrompt = 0
local busy = false

function InviteController:Init(controllers)
	self.controllers = controllers
end

-- Whether Roblox allows this player to send an invite right now
function InviteController:canInvite(): boolean
	local ok, allowed = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	return ok and allowed == true
end

-- Opens the invite prompt. Returns "opened", "unavailable" (Roblox says not now) or "busy".
function InviteController:invite(): string
	if busy or os.clock() - lastPrompt < Community.InviteCooldown then
		return "busy"
	end
	busy = true
	local result = "unavailable"
	if self:canInvite() then
		local ok = pcall(function()
			local options = Instance.new("ExperienceInviteOptions")
			options.PromptMessage = Community.InvitePrompt
			if Community.InviteMessageId ~= "" then
				options.InviteMessageId = Community.InviteMessageId
			end
			SocialService:PromptGameInvite(player, options)
		end)
		if ok then
			result = "opened"
			lastPrompt = os.clock()
		end
	end
	busy = false
	return result
end

return InviteController
