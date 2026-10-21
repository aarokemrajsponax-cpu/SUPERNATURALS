-- Who can open the owner panel. Server-only: clients never see this file.
-- Usernames are checked against Player.Name (the real, unique Roblox username,
-- not the display name), and are also converted to user ids at startup so the
-- panel keeps working if the account is renamed later.

return {
	Usernames = { "XxxXxxX_77797" },
	-- Add user ids here too if you like (most reliable)
	UserIds = {} :: { number },
	-- The account that owns this game always gets the panel
	IncludeGameCreator = true,
}
