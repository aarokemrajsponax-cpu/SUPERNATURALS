-- Roblox regional price levels (Managed Pricing). On join the player's level is fetched with
-- MarketplaceService:GetUsersPriceLevelsAsync inside a pcall and validated (the returned UserId
-- must be theirs and the level a whole number from 1 to 1000). It lives in server memory only:
-- never saved to a DataStore, never sent to a client. The level is Roblox's economic pricing
-- signal, not a VPN or exploit detector.
-- Trades and gifts do not use this stored copy; they ask Transfers/TransferPolicy, which looks
-- both accounts up again at the moment of the transfer.

local Players = game:GetService("Players")

local TransferPolicy = require(script.Parent.Parent.Transfers.TransferPolicy)

local PriceLevelService = {}

PriceLevelService.transfers = TransferPolicy

-- [userId] = level, session only
local sessionLevels: { [number]: number } = {}

function PriceLevelService:_fetch(player: Player)
	local levels = TransferPolicy.fetchLevels({ player.UserId })
	if player.Parent == nil then
		return
	end
	local level = if levels then levels[player.UserId] else nil
	if level then
		sessionLevels[player.UserId] = level
	else
		-- Quiet on purpose: no level or id in the log
		warn("[PriceLevel] couldn't verify a joining player's regional price level; transfers re-check anyway")
	end
end

function PriceLevelService:Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(self._fetch, self, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(self._fetch, self, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		sessionLevels[player.UserId] = nil
	end)
end

-- The level fetched when the player joined, or nil if it wasn't verified. Server use only;
-- do not show it to players or use it to approve a transfer.
function PriceLevelService:joinLevel(player: Player): number?
	return sessionLevels[player.UserId]
end

function PriceLevelService:canTrade(a: number, b: number)
	return TransferPolicy.canTrade(a, b)
end

function PriceLevelService:canGift(senderId: number, recipientId: number)
	return TransferPolicy.canGift(senderId, recipientId)
end

return PriceLevelService
