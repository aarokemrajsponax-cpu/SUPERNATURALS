-- Who can open the owner panel. Server-only: clients never see this file.
-- The user id is the reliable check (it never changes, even if the account is
-- renamed). The username is a backup, checked against Player.Name (the real,
-- unique Roblox username, not the display name).

return {
	-- XxxXxxX_77797 (display name AJKR)
	UserIds = { 8722595934 } :: { number },
	Usernames = { "XxxXxxX_77797" },
	-- When true, whichever account publishes the game also gets the panel
	IncludeGameCreator = false,
}
