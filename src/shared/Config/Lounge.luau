-- Lounge tuning that is not the wheel or the refreshments: the Quick Draw games table.
-- Quick Draw is a reaction duel for two seated players. A lamp turns green after a random wait; the
-- first buzz after green wins, a buzz before green is a false start and loses the round. It pays
-- earned Money only, a small amount, up to a small cap a day (UTC). No Gems, no items, no Robux.

local Lounge = {}

Lounge.QuickDraw = {
	WinMoney = 12,
	PlayMoney = 4,
	-- Most Money one player can earn from the table in a UTC day
	DailyCap = 120,
	-- A lone player who sat down is released after this long
	LobbySeconds = 45,
	-- Seconds of "get ready" after the second player sits
	ReadySeconds = 2,
	-- The wait before the lamp turns green is drawn between these (seconds)
	MinWait = 2,
	MaxWait = 5,
	-- A round nobody answers ends after this many seconds with the lamp green
	GoSeconds = 6,
	-- How long the result stays up before the table resets
	ResultSeconds = 4,
}

return Lounge
