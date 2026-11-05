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

-- Community like goals. The server cannot read the game's like count, so the owner types it in
-- under OWNER, Community goals. When the count reaches a goal EVERY player gets its reward,
-- whether or not they liked the game, including players who join later. Nothing is given to an
-- individual for liking (Roblox gives a game no way to see who liked it). Lowering the count
-- later never takes a reward back. reward = { kind = "title" | "aura", cosmetic = id } or
-- { kind = "gems", amount = n }. text finishes the sentence "everyone gets ...".
Community.LikeGoals = {
	{ id = "likes_1000", likes = 1000, reward = { kind = "title", cosmetic = "title_supporter" }, text = "the Supporter title" },
	{ id = "likes_5000", likes = 5000, reward = { kind = "gems", amount = 150 }, text = "150 Gems" },
	{ id = "likes_25000", likes = 25000, reward = { kind = "aura", cosmetic = "aura_crowd_glow" }, text = "the Crowd Glow aura" },
}

Community.LikeStore = {
	StoreName = "SN_CommunityLikes_v1",
	Key = "count",
	Topic = "SN_CommunityLikes",
	MaxLikes = 1e9,
	Attempts = 3,
	-- Seconds between two saves by the owner
	SetGap = 3,
	-- Jeffery's one-time reminder comes after this many finished matches
	ReminderAfterMatches = 3,
	ReminderText = "A like on the game page helps us reach the next community goal. When a goal is reached, every player gets its reward, whether they liked the game or not.",
}

return Community
