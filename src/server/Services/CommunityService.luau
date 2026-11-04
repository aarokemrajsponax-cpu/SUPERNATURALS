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
-- Community like goals (Config/Community.LikeGoals): the owner types the game's like count into
-- OWNER, Community goals (the server cannot read it). It is stored in a DataStore, published to
-- every server through MessagingService, and each server grants every reached goal once to every
-- player, joined or joining later (profile.community.goals). Nothing is given to a player for
-- liking; lowering the count never takes anything back. Jeffery says one reminder after the third
-- finished match (profile.community.likeNote) that likes help reach the goals.
-- Logs carry UserIds only.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Community = require(ReplicatedStorage.Shared.Config.Community)
local RateLimiter = require(ReplicatedStorage.Shared.Utility.RateLimiter)
local CommunityBoard = require(script.Parent.Parent.World.CommunityBoard)

local CommunityService = {}

local TITLE_MEMBER = "title_member"
local TITLE_RECRUITER = "title_recruiter"
local TITLE_BROUGHT_IN = "title_brought_in"

local store: DataStore? = nil
local friendCache: { [string]: boolean } = {}
local friendPending: { [string]: boolean } = {}
local busy: { [Player]: boolean } = {}
local limiter = RateLimiter.new(0.5, 3)
local likeStore: DataStore? = nil
local likeState = { likes = 0, setAt = 0 }
local likeLoaded = false
local announcedGoals: { [string]: boolean } = {}
local goalBusy: { [Player]: boolean } = {}
local setLimiter = RateLimiter.new(1 / Community.LikeStore.SetGap, 1)

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

	self:_likeStart()
	self.data:onLoaded(function(player)
		self:_onJoin(player)
		self:_grantGoals(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		goalBusy[player] = nil
		RateLimiter.forget(limiter, player)
		RateLimiter.forget(setLimiter, player)
		local id = tostring(player.UserId)
		for key in friendCache do
			local a, b = string.match(key, "^(%d+):(%d+)$")
			if a == id or b == id then
				friendCache[key] = nil
			end
		end
		task.defer(function()
			self:publishFriendBonus()
		end)
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
	self:publishFriendBonus()
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

-- Tells every client whether it has the friend bonus right now (Player attribute
-- Protocol.Attribute.FriendBonus, in percent), so the player card can show a chip. Only
-- writes when the value changes. Display only: the bonus itself is the reward modifier.
function CommunityService:publishFriendBonus()
	local percent = math.floor(Community.FriendsBonus * 100 + 0.5)
	for _, player in Players:GetPlayers() do
		local want = if percent > 0 and self:hasFriendHere(player) then percent else nil
		if player:GetAttribute(Protocol.Attribute.FriendBonus) ~= want then
			player:SetAttribute(Protocol.Attribute.FriendBonus, want)
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

-- Community like goals ---------------------------------------------------------------------

local function goalReached(goal, likes: number): boolean
	return likes >= goal.likes
end

local function commas(n: number): string
	local out = tostring(math.floor(n))
	while true do
		local replaced, count = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		out = replaced
		if count == 0 then
			break
		end
	end
	return out
end
CommunityService.commas = commas

local function dataEvent(): RemoteEvent?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	return remotes and remotes:FindFirstChild("DataEvent") :: any
end

function CommunityService:_toastAll(text: string)
	local remote = dataEvent()
	if remote then
		remote:FireAllClients(Protocol.DataEvent.Toast, { text = text, kind = "reward" })
	end
end

function CommunityService:_likeStart()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Community.LikeStore.StoreName)
	end)
	if ok then
		likeStore = result
	else
		warn("[Community] the like count cannot be saved or read: " .. tostring(result))
	end
	pcall(function()
		MessagingService:SubscribeAsync(Community.LikeStore.Topic, function(message)
			local likes, setAt = self:_cleanState(message and message.Data)
			if likes then
				self:_applyLikes(likes, setAt)
			end
		end)
	end)
	task.spawn(function()
		local dataStore = likeStore
		for attempt = 1, Community.LikeStore.Attempts do
			if not dataStore then
				break
			end
			local fine, value = pcall(function()
				return dataStore:GetAsync(Community.LikeStore.Key)
			end)
			if fine then
				local likes, setAt = self:_cleanState(value)
				if likes then
					self:_applyLikes(likes, setAt, true)
				end
				break
			end
			task.wait(0.5 * attempt)
		end
		if not likeLoaded then
			likeLoaded = true
			self:_refreshBoard()
		end
	end)
end

-- A stored or received value -> (likes, setAt), or nil when it is not a valid count
function CommunityService:_cleanState(value: any): (number?, number)
	if typeof(value) ~= "table" then
		return nil, 0
	end
	local likes, setAt = value.likes, value.setAt
	if typeof(likes) ~= "number" or likes ~= likes or likes % 1 ~= 0 or likes < 0 or likes > Community.LikeStore.MaxLikes then
		return nil, 0
	end
	if typeof(setAt) ~= "number" or setAt ~= setAt or setAt < 0 or setAt > 1e11 then
		setAt = 0
	end
	return likes, math.floor(setAt)
end

function CommunityService:_refreshBoard()
	CommunityBoard.update(likeState.likes, likeState.setAt, likeLoaded)
end

-- Takes a new count (from the store, a message or the owner). quiet: no notice (the first load).
function CommunityService:_applyLikes(likes: number, setAt: number, quiet: boolean?)
	if likeLoaded and setAt < likeState.setAt then
		return -- an older value arrived late
	end
	local first = not likeLoaded
	likeState = { likes = likes, setAt = setAt }
	likeLoaded = true
	self:_refreshBoard()
	for _, goal in Community.LikeGoals do
		if goalReached(goal, likes) and not announcedGoals[goal.id] then
			announcedGoals[goal.id] = true
			if not (quiet or first) then
				self:_toastAll(`Community goal reached: {commas(goal.likes)} likes. Everyone gets {goal.text}.`)
				log(`goal {goal.id} reached at {likes} likes`)
			end
		end
	end
	for _, player in Players:GetPlayers() do
		task.spawn(self._grantGoals, self, player)
	end
end

-- Gives the player every reached goal they do not have yet. Safe to call at any time.
function CommunityService:_grantGoals(player: Player)
	if goalBusy[player] or not likeLoaded then
		return
	end
	if not self.data:get(player) or not player.Parent then
		return
	end
	goalBusy[player] = true
	for _, goal in Community.LikeGoals do
		local current = self.data:get(player)
		if not current or not player.Parent then
			break
		end
		if goalReached(goal, likeState.likes) and not current.community.goals[goal.id] then
			if self:_giveReward(player, goal) then
				self.data:update(player, function(p)
					p.community.goals[goal.id] = true
				end)
				log(`goal {goal.id} given to {player.UserId}`)
			end
		end
	end
	goalBusy[player] = nil
end

function CommunityService:_giveReward(player: Player, goal): boolean
	local reward = goal.reward
	if reward.kind == "gems" then
		local currency = self.services.CurrencyService
		return currency ~= nil and currency:add(player, { gems = reward.amount }, "community goal " .. goal.id) == true
	end
	local cosmetics = self.services.CosmeticService
	if not cosmetics then
		return false
	end
	cosmetics:grant(player, reward.cosmetic, "community")
	-- grant returns false when the player already owns it, which is just as good
	return cosmetics:owns(player, reward.cosmetic)
end

-- What the Control Center shows: the count, when it was set and each goal
function CommunityService:goalsView()
	local goals = {}
	for _, goal in Community.LikeGoals do
		table.insert(goals, { id = goal.id, likes = goal.likes, text = goal.text, reached = goalReached(goal, likeState.likes) })
	end
	return { likes = likeState.likes, setAt = likeState.setAt, loaded = likeLoaded, goals = goals }
end

-- The owner enters the like count. Owner only (by UserId), an integer from 0 to MaxLikes.
-- Returns { ok, code?, data? }.
function CommunityService:setLikes(player: Player, value: any)
	local owner = self.services.OwnerService
	if not (owner and owner:isOwner(player)) then
		return { ok = false, code = "not_owner" }
	end
	if not RateLimiter.allow(setLimiter, player, os.clock()) then
		return { ok = false, code = "rate_limited" }
	end
	if typeof(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < 0 or value > Community.LikeStore.MaxLikes then
		return { ok = false, code = "bad_likes" }
	end
	local dataStore = likeStore
	if not dataStore then
		return { ok = false, code = "store_failed" }
	end
	local setAt = os.time()
	local saved = false
	for attempt = 1, Community.LikeStore.Attempts do
		local ok = pcall(function()
			dataStore:UpdateAsync(Community.LikeStore.Key, function()
				return { likes = value, setAt = setAt }
			end)
		end)
		if ok then
			saved = true
			break
		end
		task.wait(0.2 * attempt)
	end
	if not saved then
		return { ok = false, code = "store_failed" }
	end
	log(`like count set to {value} by {player.UserId}`)
	self:_applyLikes(value, setAt)
	pcall(function()
		MessagingService:PublishAsync(Community.LikeStore.Topic, { likes = value, setAt = setAt })
	end)
	return { ok = true, data = self:goalsView() }
end

-- Jeffery's one-time reminder: ProgressionService calls this after each finished match. It says
-- nothing about a personal reward. While hints are off or Jeffery is busy with the tour it
-- waits (the flag is not set) and tries again after the next match.
function CommunityService:onMatchFinished(player: Player)
	local profile = self.data:get(player)
	if not profile or profile.community.likeNote then
		return
	end
	if (profile.stats.matches or 0) < Community.LikeStore.ReminderAfterMatches then
		return
	end
	if profile.settings.hints == false then
		return
	end
	local tutorial = self.services.TutorialService
	if tutorial and tutorial:isBusy(player) then
		return
	end
	local remote = dataEvent()
	if not remote or not player.Parent then
		return
	end
	self.data:update(player, function(p)
		p.community.likeNote = true
	end)
	remote:FireClient(player, Protocol.DataEvent.Hint, { id = "like_goals", text = Community.LikeStore.ReminderText, face = "happy" })
end

return CommunityService
