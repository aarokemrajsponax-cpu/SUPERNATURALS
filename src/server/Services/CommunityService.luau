-- Community rewards: referrals, the group title and the friends bonus. Server authority only.
--
-- Referrals (Roblox's own system): on join the server reads player:GetJoinData().ReferredByPlayerId.
-- It is stored ONCE in profile.community.referredBy, and only for a brand-new profile (first
-- session, community.firstJoin still 0). Never for the player's own id, never for a returning
-- player. The reward is paid when the newcomer reaches the milestone: Jeffery's tour finished AND
-- one practice round (TutorialService and PracticeService tell this service). Then, once:
--   * the newcomer gets the title "Brought In" (CosmeticService) and referralDone is set;
--   * the inviter is credited exactly once per newcomer. If the inviter is in this server they get
--     the title "Recruiter" and recruits + 1 now; otherwise a pending credit waits in a DataStore
--     keyed by the inviter's UserId (it stores newcomer ids, never a bare counter, so a repeat
--     cannot pay twice) and is claimed the next time the inviter joins any server.
--   * at most Community.Referral.DailyCapPerInviter credits per inviter per UTC day.
-- Group: when Community.GroupId > 0 the title "Facility Member" is granted once to group members.
-- Friends: a ProgressionService reward modifier adds Community.FriendsBonus while a Roblox friend
-- is in the same server (friend checks are done on join and cached; the modifier never yields).
-- Logs carry UserIds only.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Community = require(ReplicatedStorage.Shared.Config.Community)
local RateLimiter = require(ReplicatedStorage.Shared.Utility.RateLimiter)

local CommunityService = {}

local TITLE_MEMBER = "title_member"
local TITLE_RECRUITER = "title_recruiter"
local TITLE_BROUGHT_IN = "title_brought_in"

local store: DataStore? = nil
local friendCache: { [string]: boolean } = {}
local friendPending: { [string]: boolean } = {}
local busy: { [Player]: boolean } = {}
local limiter = RateLimiter.new(0.5, 3)

local function log(text: string)
	print("[Community] " .. text)
end

local function pairKey(a: number, b: number): string
	return if a < b then `{a}:{b}` else `{b}:{a}`
end

local function dayKey(): string
	return os.date("!%Y-%j") :: string
end

function CommunityService:Init(services)
	self.services = services
	self.data = services.DataService
end

function CommunityService:Start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Community.Referral.StoreName)
	end)
	if ok then
		store = result
	else
		warn("[Community] referral credits for offline inviters are unavailable: " .. tostring(result))
	end

	local progression = self.services.ProgressionService
	if progression and Community.FriendsBonus > 0 then
		progression:addRewardModifier(function(player: Player)
			if self:hasFriendHere(player) then
				return 1 + Community.FriendsBonus, Community.FriendsLabel
			end
			return nil, nil
		end)
	end

	self.data:onLoaded(function(player)
		self:_onJoin(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		RateLimiter.forget(limiter, player)
		local id = tostring(player.UserId)
		for key in friendCache do
			local a, b = string.match(key, "^(%d+):(%d+)$")
			if a == id or b == id then
				friendCache[key] = nil
			end
		end
	end)
end

-- Joining ---------------------------------------------------------------------------------

local function readReferrer(player: Player): number
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or typeof(joinData) ~= "table" then
		return 0
	end
	local id = joinData.ReferredByPlayerId
	if typeof(id) ~= "number" or id ~= id or id <= 0 or id % 1 ~= 0 or id > 1e15 then
		return 0
	end
	return id
end

function CommunityService:_onJoin(player: Player)
	-- 1. The referrer, stored once and only for a brand-new profile
	local profile = self.data:get(player)
	if not profile then
		return
	end
	if profile.community.firstJoin == 0 then
		local referrer = readReferrer(player)
		local isNew = profile.meta.sessions == 1
		local stored = 0
		self.data:update(player, function(p)
			local community = p.community
			if community.firstJoin ~= 0 then
				return
			end
			community.firstJoin = os.time()
			if isNew and referrer > 0 and referrer ~= player.UserId and community.referredBy == 0 then
				community.referredBy = referrer
				stored = referrer
			end
		end)
		if stored > 0 then
			log(`{player.UserId} joined through an invite from {stored}`)
		end
	end
	-- 2. Anything the milestone left unfinished, an offline inviter's credits, the group title
	self:_checkReferral(player)
	self:_claimPending(player)
	self:_checkGroup(player)
	self:_warmFriends(player)
end

-- The milestone ---------------------------------------------------------------------------

-- Jeffery's tour was finished (TutorialService, a real first completion)
function CommunityService:onTourFinished(player: Player)
	if limiter and not RateLimiter.allow(limiter, player, os.clock()) then
		return
	end
	task.spawn(self._checkReferral, self, player)
end

-- A practice round ended normally (PracticeService, not a restart)
function CommunityService:onPracticeRound(player: Player, seconds: number)
	if typeof(seconds) ~= "number" or seconds < Community.Referral.MinPracticeSeconds then
		return
	end
	if not RateLimiter.allow(limiter, player, os.clock()) then
		return
	end
	local profile = self.data:get(player)
	if not profile then
		return
	end
	if not profile.tutorial.done.comm_training then
		self.data:update(player, function(p)
			p.tutorial.done.comm_training = true
		end)
	end
	task.spawn(self._checkReferral, self, player)
end

function CommunityService:_checkReferral(player: Player)
	if busy[player] then
		return
	end
	local profile = self.data:get(player)
	if not profile then
		return
	end
	local community = profile.community
	local done = profile.tutorial.done
	local inviterId = community.referredBy
	if inviterId <= 0 or inviterId == player.UserId or community.referralDone then
		return
	end
	if not (done.tut_complete and done.comm_training) then
		return
	end
	busy[player] = true
	local ok, err = pcall(function()
		local online = Players:GetPlayerByUserId(inviterId)
		local result = self:_creditInviter(inviterId, player.UserId, online ~= nil)
		if result == "failed" then
			return -- tried again at the next join or milestone event
		end
		if result == "credited" and online then
			if not self:_applyRecruits(online, 1) then
				self:_addPending(inviterId, player.UserId)
			end
		end
		local cosmetics = self.services.CosmeticService
		if not cosmetics or not cosmetics:grant(player, TITLE_BROUGHT_IN, "referral") then
			return
		end
		if self.data:update(player, function(p)
			p.community.referralDone = true
		end) then
			log(`referral paid: newcomer {player.UserId}, inviter {inviterId} ({result})`)
		end
	end)
	busy[player] = nil
	if not ok then
		warn("[Community] referral check failed: " .. tostring(err))
	end
end

-- Credits the inviter once for this newcomer. Returns "credited", "duplicate", "capped" or "failed".
function CommunityService:_creditInviter(inviterId: number, newcomerId: number, inviterHere: boolean): string
	local settings = Community.Referral
	local ok, result = self:_storeUpdate(inviterId, function(old)
		local record = if typeof(old) == "table" then old else {}
		record.seen = if typeof(record.seen) == "table" then record.seen else {}
		record.pending = if typeof(record.pending) == "table" then record.pending else {}
		local id = tostring(newcomerId)
		if record.seen[id] then
			return nil, "duplicate"
		end
		local today = dayKey()
		if record.day ~= today then
			record.day = today
			record.count = 0
		end
		-- Keep the list of remembered newcomers short: forget the oldest
		local remembered = 0
		local oldestId, oldestAt = nil, math.huge
		for key, at in record.seen do
			remembered += 1
			if typeof(at) == "number" and at < oldestAt then
				oldestId, oldestAt = key, at
			end
		end
		if remembered >= settings.MaxRemembered and oldestId then
			record.seen[oldestId] = nil
		end
		record.seen[id] = os.time()
		if (record.count or 0) >= settings.DailyCapPerInviter then
			return record, "capped"
		end
		record.count = (record.count or 0) + 1
		if not inviterHere then
			record.pending[id] = os.time()
		end
		return record, "credited"
	end)
	if not ok then
		warn(`[Community] could not record the referral for inviter {inviterId}`)
		return "failed"
	end
	return result or "failed"
end

function CommunityService:_addPending(inviterId: number, newcomerId: number)
	self:_storeUpdate(inviterId, function(old)
		local record = if typeof(old) == "table" then old else {}
		record.pending = if typeof(record.pending) == "table" then record.pending else {}
		record.pending[tostring(newcomerId)] = os.time()
		return record, true
	end)
end

-- recruits + n and the Recruiter title for a player in this server
function CommunityService:_applyRecruits(inviter: Player, count: number): boolean
	if count <= 0 then
		return true
	end
	if not self.data:update(inviter, function(p)
		p.community.recruits += count
	end) then
		return false
	end
	local cosmetics = self.services.CosmeticService
	if cosmetics then
		cosmetics:grant(inviter, TITLE_RECRUITER, "referral")
	end
	log(`recruits +{count} for {inviter.UserId}`)
	return true
end

-- An inviter coming back: pending credits are taken from the store and paid once
function CommunityService:_claimPending(player: Player)
	if not store then
		return
	end
	local ok, ids = self:_storeUpdate(player.UserId, function(old)
		if typeof(old) ~= "table" or typeof(old.pending) ~= "table" or next(old.pending) == nil then
			return nil, {}
		end
		local taken = {}
		for id in old.pending do
			table.insert(taken, id)
		end
		old.pending = {}
		return old, taken
	end)
	if not ok or typeof(ids) ~= "table" or #ids == 0 then
		return
	end
	if not self:_applyRecruits(player, #ids) then
		for _, id in ids do
			self:_addPending(player.UserId, tonumber(id) or 0)
		end
	end
end

-- DataStore access with a few tries. transform(old) -> (newValue or nil, result)
function CommunityService:_storeUpdate(inviterId: number, transform: (any) -> (any, any)): (boolean, any)
	local dataStore = store
	if not dataStore then
		return false, nil
	end
	local key = "u" .. inviterId
	for attempt = 1, Community.Referral.Attempts do
		local result
		local ok = pcall(function()
			dataStore:UpdateAsync(key, function(old)
				local new, value = transform(old)
				result = value
				return new
			end)
		end)
		if ok then
			return true, result
		end
		task.wait(0.2 * attempt)
	end
	return false, nil
end

-- Group -----------------------------------------------------------------------------------

function CommunityService:_checkGroup(player: Player)
	local groupId = Community.GroupId
	if typeof(groupId) ~= "number" or groupId <= 0 then
		return
	end
	local profile = self.data:get(player)
	if not profile or profile.community.groupRewarded then
		return
	end
	local ok, member = pcall(function()
		return player:IsInGroup(groupId)
	end)
	if not ok or member ~= true then
		return
	end
	local cosmetics = self.services.CosmeticService
	if cosmetics and cosmetics:grant(player, TITLE_MEMBER, "group") then
		self.data:update(player, function(p)
			p.community.groupRewarded = true
		end)
		log(`group title for {player.UserId}`)
	end
end

-- Friends ---------------------------------------------------------------------------------

function CommunityService:_warmFriends(player: Player)
	for _, other in Players:GetPlayers() do
		if other ~= player and other.Parent then
			local key = pairKey(player.UserId, other.UserId)
			if friendCache[key] == nil and not friendPending[key] then
				friendPending[key] = true
				local ok, result = pcall(function()
					return player:IsFriendsWith(other.UserId)
				end)
				friendPending[key] = nil
				if ok and typeof(result) == "boolean" then
					friendCache[key] = result
				end
			end
		end
	end
end

-- Whether a Roblox friend of the player is in this server (cached, never yields)
function CommunityService:hasFriendHere(player: Player): boolean
	for _, other in Players:GetPlayers() do
		if other ~= player and friendCache[pairKey(player.UserId, other.UserId)] == true then
			return true
		end
	end
	return false
end

return CommunityService
