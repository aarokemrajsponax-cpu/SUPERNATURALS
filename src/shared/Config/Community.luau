-- Community settings: the group reward, the friends bonus, invite prompts and Roblox referral
-- rewards. Used by CommunityService (server) and InviteController (client). Balance and
-- wording live here, not in code. No emoji, no em dashes.

local Community = {}

-- The Roblox group players can join for the "Facility Member" title. The owner pastes the real
-- group id here. 0 means the group reward is off and nothing about it is shown.
Community.GroupId = 0

-- Extra Money and experience on a paid match while a Roblox friend is in the same server
-- (0.2 = 20 percent). ProgressionService caps the total of all bonuses.
Community.FriendsBonus = 0.2
Community.FriendsLabel = "Playing with a friend"

-- Invite prompt (Roblox's own friend picker). The owner can create a Notification string in
-- Creator Hub (Engagement, Notifications, containing {experienceName}) and paste its id here.
-- "" means no custom message.
Community.InvitePrompt = "Come train with me at the facility"
Community.InviteMessageId = ""
Community.InviteCooldown = 3 -- seconds between prompts on the client

-- Referral rewards: for a player who joined through someone's invite (Roblox ReferredByPlayerId).
Community.Referral = {
	-- The new player must finish Jeffery's tour AND one practice round (this many seconds long at least)
	MinPracticeSeconds = 15,
	-- At most this many recruit credits per inviter per UTC day (extra newcomers still get their own title)
	DailyCapPerInviter = 10,
	-- DataStore holding credits for inviters who were not in the server
	StoreName = "SN_ReferralCredits_v1",
	-- Remember at most this many newcomer ids per inviter (for the once-per-newcomer check)
	MaxRemembered = 300,
	-- Retries for a failed DataStore call
	Attempts = 3,
}

return Community
