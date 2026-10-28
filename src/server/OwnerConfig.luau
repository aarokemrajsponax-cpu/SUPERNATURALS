-- Who can open the owner panel. Server-only: clients never see this file.
-- Only user ids count. A user id never changes and is never reused, while a
-- username can be changed and then claimed by someone else, so names are
-- never trusted for owner access.

return {
	-- XxxXxxX_77797 (display name AJKR)
	UserIds = { 8722595934 } :: { number },
	-- When true, whichever account publishes the game also gets the panel
	IncludeGameCreator = false,
}
