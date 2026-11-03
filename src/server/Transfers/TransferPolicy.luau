-- The one gate every future trade or gift must pass (DECISIONS 21: the game has no trading or
-- gifting yet, this is the server-side rule set waiting for them). Rules from P.S. 11.0:
--   trade: both accounts must have exactly the same Roblox price level
--   gift:  sender level >= recipient level (the recipient may be offline; only a UserId is needed)
-- Every decision starts from a FRESH MarketplaceService:GetUsersPriceLevelsAsync call for the
-- users involved, never from the level saved at join and never from anything a client sent.
-- Any failure, missing user or malformed entry denies. The messages never reveal a level.
-- The lock helper stops two transfers touching the same account at once.

local MarketplaceService = game:GetService("MarketplaceService")

local TransferPolicy = {}

TransferPolicy.Messages = {
	TradeDiffers = "Trading between these accounts is temporarily unavailable because their regional pricing levels differ.",
	GiftBlocked = "Gifting from this account to that account is temporarily unavailable because of regional pricing.",
	Retry = "We couldn't verify these accounts right now. Nothing was changed. Please try again in a moment.",
	Busy = "One of these accounts is already in a transfer. Please try again in a moment.",
	Invalid = "That transfer isn't possible.",
}

-- Roblox price levels run from 1 to 1000
local MIN_LEVEL, MAX_LEVEL = 1, 1000
-- A lock that was never released (a crashed transfer) frees itself after this many seconds
TransferPolicy.LockSeconds = 30

-- The lookup is replaceable so tests can inject results and failures.
-- lookup(userIds) -> array of { UserId, PriceLevel } (may yield, may error)
local function robloxLookup(userIds: { number }): any
	return MarketplaceService:GetUsersPriceLevelsAsync(userIds)
end
TransferPolicy.lookup = robloxLookup

local function validUserId(id: any): boolean
	return typeof(id) == "number" and id > 0 and id == math.floor(id) and id < 2 ^ 53
end

local function validLevel(level: any): boolean
	return typeof(level) == "number" and level == math.floor(level) and level >= MIN_LEVEL and level <= MAX_LEVEL
end

-- Fresh, verified { [userId] = level } for exactly these users, or nil when anything is off.
-- Only entries whose UserId was asked for and whose PriceLevel is valid count; a missing,
-- duplicated-with-a-different-level or extra entry fails the whole lookup.
function TransferPolicy.fetchLevels(userIds: { number }): { [number]: number }?
	local asked: { [number]: boolean } = {}
	local list = {}
	for _, id in userIds do
		if not validUserId(id) then
			return nil
		end
		if not asked[id] then
			asked[id] = true
			table.insert(list, id)
		end
	end
	local ok, result = pcall(TransferPolicy.lookup, list)
	if not ok or typeof(result) ~= "table" then
		warn("[Transfer] price level lookup failed")
		return nil
	end
	local levels: { [number]: number } = {}
	for _, entry in result do
		if typeof(entry) ~= "table" or not validUserId(entry.UserId) or not validLevel(entry.PriceLevel) then
			return nil
		end
		if not asked[entry.UserId] then
			return nil
		end
		if levels[entry.UserId] ~= nil and levels[entry.UserId] ~= entry.PriceLevel then
			return nil
		end
		levels[entry.UserId] = entry.PriceLevel
	end
	for id in asked do
		if levels[id] == nil then
			return nil
		end
	end
	return levels
end

export type Decision = { allowed: boolean, message: string?, code: string }

local function deny(code: string, message: string): Decision
	return { allowed = false, code = code, message = message }
end

-- Trade: two different accounts with exactly equal levels
function TransferPolicy.canTrade(userIdA: any, userIdB: any): Decision
	if not validUserId(userIdA) or not validUserId(userIdB) or userIdA == userIdB then
		return deny("Invalid", TransferPolicy.Messages.Invalid)
	end
	local levels = TransferPolicy.fetchLevels({ userIdA, userIdB })
	if not levels then
		return deny("Unverified", TransferPolicy.Messages.Retry)
	end
	if levels[userIdA] ~= levels[userIdB] then
		return deny("LevelsDiffer", TransferPolicy.Messages.TradeDiffers)
	end
	return { allowed = true, code = "Allowed" }
end

-- Gift: sender level must be at least the recipient's; the recipient only needs a UserId
function TransferPolicy.canGift(senderId: any, recipientId: any): Decision
	if not validUserId(senderId) or not validUserId(recipientId) or senderId == recipientId then
		return deny("Invalid", TransferPolicy.Messages.Invalid)
	end
	local levels = TransferPolicy.fetchLevels({ senderId, recipientId })
	if not levels then
		return deny("Unverified", TransferPolicy.Messages.Retry)
	end
	if levels[senderId] < levels[recipientId] then
		return deny("SenderLower", TransferPolicy.Messages.GiftBlocked)
	end
	return { allowed = true, code = "Allowed" }
end

-- Transaction locks ------------------------------------------------------------------------------

local locks: { [number]: number } = {}

-- Locks every user for one transfer. Returns a release function, or nil when any of them is
-- already locked (nothing is taken then). Release is safe to call twice, and a lock that is
-- never released expires. Always release in every exit path, including failures.
function TransferPolicy.acquire(userIds: { number }, now: number?): (() -> ())?
	local clock = now or os.clock()
	for _, id in userIds do
		if not validUserId(id) then
			return nil
		end
		local until_ = locks[id]
		if until_ and until_ > clock then
			return nil
		end
	end
	local mine: { [number]: number } = {}
	for _, id in userIds do
		mine[id] = clock + TransferPolicy.LockSeconds
		locks[id] = mine[id]
	end
	local released = false
	return function()
		if released then
			return
		end
		released = true
		for id, stamp in mine do
			-- Only drop our own lock, never a newer holder's
			if locks[id] == stamp then
				locks[id] = nil
			end
		end
	end
end

function TransferPolicy.isLocked(userId: number): boolean
	local until_ = locks[userId]
	return until_ ~= nil and until_ > os.clock()
end

-- Runs transfer() while both accounts are locked, after a fresh policy check. kind is "trade" or
-- "gift". Returns (true, transferResult) or (false, Decision). The lock is released even if
-- transfer errors; an error is returned as a Retry denial so items stay where they were.
function TransferPolicy.run(kind: string, fromId: number, toId: number, transfer: () -> any): (boolean, any)
	local release = TransferPolicy.acquire({ fromId, toId })
	if not release then
		return false, deny("Busy", TransferPolicy.Messages.Busy)
	end
	local decision = if kind == "trade" then TransferPolicy.canTrade(fromId, toId) else TransferPolicy.canGift(fromId, toId)
	if not decision.allowed then
		release()
		return false, decision
	end
	local ok, result = pcall(transfer)
	release()
	if not ok then
		warn("[Transfer] a transfer errored and was not completed")
		return false, deny("Failed", TransferPolicy.Messages.Retry)
	end
	return true, result
end

return TransferPolicy
