-- Loads, keeps and saves every player's profile (money, gems, powers,
-- loadouts, base, settings...). A profile is locked to one server at a time,
-- so two servers can never overwrite each other's progress. Every DataStore
-- call retries with backoff. If saving can't work at all (Studio without API
-- access, an outage) the game still runs on an unsaved copy, the player is
-- told, and that copy is never written over their real data.
--
-- The saved record is { data = profile, lock = { jobId, session, at } };
-- `lock` is nil when no server has the profile open.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Schema = require(ReplicatedStorage.Shared.Data.Schema)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent
local SettingsRequest = Remotes:WaitForChild("SettingsRequest") :: RemoteEvent

local Config = Schema.Config

local DataService = {}

-- What the player is told when their progress isn't being saved. The HUD
-- shows these on one line in a 640 px banner, so each stays under ~70 characters.
local MESSAGES = {
	Studio = "Studio test: saving is off. Turn on Studio API access to save.",
	Unavailable = "Saving is down on this server. Progress here is temporary.",
	Locked = "Your save is still open on another server. Rejoin in a minute.",
	Failed = "Your save couldn't load, so progress isn't saved. Rejoin to retry.",
	Newer = "This server is out of date and can't save. Rejoin to update.",
	Lost = "Your save was opened on another server. Rejoin to keep saving.",
}

type Session = {
	id: string,
	userId: number,
	key: string,
	player: Player,
	profile: Schema.Profile?,
	-- Saving is allowed (false for unsaved copies, newer-version data and lost locks)
	persistent: boolean,
	dirty: boolean,
	loading: boolean,
	saving: boolean,
	leaving: boolean,
	releasing: boolean,
	released: boolean,
	-- The lock was removed by the final save; nothing more may be written
	lockReleased: boolean,
	-- os.clock() of the last successful save (or the load)
	lastSavedAt: number,
	-- os.clock() up to which play time has been added to stats.playSeconds
	playCountedAt: number,
	lastViewAt: number,
	viewQueued: boolean,
}

local JOB_ID = game.JobId

local sessions: { [number]: Session } = {}
local loadedCallbacks: { (Player, Schema.Profile) -> () } = {}
local changedCallbacks: { (Player, Schema.Profile) -> () } = {}
local sessionCount = 0
local store: DataStore? = nil
-- Set when DataStores can't be used on this server at all: the message players get
local unavailable: string? = nil
local closing = false

-- Helpers --------------------------------------------------------------------------------

local function backoff(attempt: number): number
	return math.min(Config.RetryMaxDelay, Config.RetryBaseDelay * 2 ^ (attempt - 1))
end

-- Errors meaning this server may not use DataStores at all, so retrying won't
-- help. Only Studio gets these; a live server never gives up on saving, and
-- the common transient "502: API Services rejected request" must not match.
local function isAccessError(message: string): boolean
	if not RunService:IsStudio() then
		return false
	end
	for _, pattern in { "StudioAccessToApisNotAllowed", "Studio access to APIs", "API access", "must publish" } do
		if string.find(message, pattern, 1, true) then
			return true
		end
	end
	return false
end

local function unavailableMessage(): string
	return if RunService:IsStudio() then MESSAGES.Studio else MESSAGES.Unavailable
end

-- DataStore requests of the kind we use that this server may still make right now
local function budget(): number
	local ok, value = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end)
	return if ok and typeof(value) == "number" then value else math.huge
end

local function waitForBudget(maxWait: number)
	local started = os.clock()
	while budget() < 1 and os.clock() - started < maxWait do
		task.wait(0.5)
	end
end

local function newLock(session: Session)
	return { jobId = JOB_ID, session = session.id, at = os.time() }
end

local function ownsLock(lock: any, session: Session): boolean
	return typeof(lock) == "table" and lock.jobId == JOB_ID and lock.session == session.id
end

-- A lock another server still holds: it refreshed it recently enough to be alive.
-- (A lock from this server belongs to an earlier session of the same user that
-- couldn't finish; it's safe to take.)
local function heldElsewhere(lock: any): boolean
	if typeof(lock) ~= "table" or lock.jobId == JOB_ID then
		return false
	end
	local at = lock.at
	if typeof(at) ~= "number" or at ~= at then
		return false
	end
	return os.time() - at < Config.LockTimeout
end

local function sessionOf(player: Player): Session?
	local session = sessions[player.UserId]
	if session and session.player == player then
		return session
	end
	return nil
end

local function snapshotSessions(): { Session }
	local list = {}
	for _, session in sessions do
		table.insert(list, session)
	end
	return list
end

local function tellPersistence(player: Player, saving: boolean, message: string?)
	if player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Persistence, { saving = saving, message = message })
	end
end

-- Adds whole seconds played since the last count
local function countPlayTime(session: Session)
	local profile = session.profile
	local whole = math.floor(os.clock() - session.playCountedAt)
	if profile and whole > 0 then
		profile.stats.playSeconds += whole
		session.playCountedAt += whole
	end
end

-- Lifecycle --------------------------------------------------------------------------------

function DataService:Init(services)
	self.antiExploit = services.AntiExploitService
end

function DataService:Start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.StoreName)
	end)
	if ok then
		store = result
	else
		unavailable = unavailableMessage()
		warn(`[Data] DataStores can't be used, progress won't be saved: {result}`)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(self._onPlayerAdded, self, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local session = sessionOf(player)
		if not session then
			return
		end
		session.leaving = true
		-- Give other services' leave handlers a moment to record final changes
		task.delay(Config.LeaveSaveDelay, function()
			self:_release(session)
		end)
	end)

	SettingsRequest.OnServerEvent:Connect(function(player, input)
		if not self.antiExploit:allow(player, "Settings") then
			return
		end
		if typeof(input) ~= "table" then
			self.antiExploit:flag(player, "sent settings that aren't a table")
			return
		end
		local profile = self:get(player)
		if not profile then
			return
		end
		local clean = Schema.sanitizeSettings(input, profile.settings)
		for key, value in clean do
			if profile.settings[key] ~= value then
				self:update(player, function(data)
					data.settings = clean
				end)
				return
			end
		end
	end)

	task.spawn(function()
		while not closing do
			task.wait(Config.AutosaveInterval)
			if not closing then
				self:_autosave()
			end
		end
	end)

	game:BindToClose(function()
		self:_saveAllOnClose()
	end)
end

function DataService:_onPlayerAdded(player: Player)
	local userId = player.UserId
	local previous = sessions[userId]
	if previous and previous.player == player then
		return
	end
	-- The same user rejoining this server: their last session must finish saving first
	if previous then
		task.spawn(self._release, self, previous)
		local started = os.clock()
		while sessions[userId] == previous and os.clock() - started < Config.CloseTimeout do
			task.wait(0.1)
		end
	end
	if player.Parent == nil or closing then
		return
	end
	sessionCount += 1
	local session: Session = {
		-- The counter keeps ids unique on this server even if two GUIDs ever matched
		id = HttpService:GenerateGUID(false) .. "#" .. sessionCount,
		userId = userId,
		key = Config.KeyPrefix .. userId,
		player = player,
		profile = nil,
		persistent = false,
		dirty = false,
		loading = true,
		saving = false,
		leaving = false,
		releasing = false,
		released = false,
		lockReleased = false,
		lastSavedAt = os.clock(),
		playCountedAt = os.clock(),
		lastViewAt = 0,
		viewQueued = false,
	}
	sessions[userId] = session
	local ok, err = pcall(self._load, self, session)
	session.loading = false
	if not ok then
		warn(`[Data] loading {player.Name} failed: {err}`)
	end
	if session.leaving then
		return
	end
	if not session.profile then
		-- Something went badly wrong; play on an unsaved copy rather than not at all
		session.profile = Schema.default()
		session.persistent = false
		tellPersistence(player, false, MESSAGES.Failed)
	end
	self:sendView(player)
	local profile = session.profile :: Schema.Profile
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, profile)
	end
end

-- Loads the saved profile and takes its lock. Tries again (with backoff) while
-- another server holds the lock or a request fails; falls back to an unsaved
-- copy when nothing works.
function DataService:_load(session: Session)
	local player = session.player
	local message: string? = unavailable
	local profile: Schema.Profile? = nil
	local persistent = false

	if store and not unavailable then
		local dataStore = store :: DataStore
		for attempt = 1, Config.LoadAttempts do
			waitForBudget(5)
			local outcome: string?, raw: any = nil, nil
			local ok, err = pcall(function()
				dataStore:UpdateAsync(session.key, function(stored)
					outcome, raw = nil, nil
					if stored ~= nil and (typeof(stored) ~= "table" or (stored.data ~= nil and typeof(stored.data) ~= "table")) then
						outcome = "corrupt"
						return nil
					end
					local record = stored or {}
					if heldElsewhere(record.lock) then
						outcome = "locked"
						return nil
					end
					local data = record.data
					if data and typeof(data.version) == "number" and data.version > Schema.VERSION then
						-- Never take the lock or write: a newer server owns this shape of data
						outcome, raw = "newer", data
						return nil
					end
					outcome, raw = "loaded", data
					local updated = table.clone(record)
					updated.lock = newLock(session)
					return updated, { session.userId }
				end)
			end)

			if ok and outcome == "loaded" then
				profile = Schema.migrate(raw)
				persistent = true
				break
			elseif ok and outcome == "newer" then
				profile = Schema.migrate(raw)
				message = MESSAGES.Newer
				warn(`[Data] {player.Name}'s profile is from a newer version ({raw.version}); playing without saving`)
				break
			elseif ok and outcome == "corrupt" then
				message = MESSAGES.Failed
				warn(`[Data] {player.Name}'s saved record is unreadable; playing without saving and leaving it untouched`)
				break
			elseif ok and outcome == "locked" then
				message = MESSAGES.Locked
			else
				local text = tostring(err)
				warn(`[Data] loading {player.Name} failed (try {attempt} of {Config.LoadAttempts}): {text}`)
				if isAccessError(text) then
					unavailable = unavailableMessage()
					message = unavailable
					break
				end
				message = MESSAGES.Failed
			end
			if session.leaving then
				break
			end
			if attempt < Config.LoadAttempts then
				task.wait(backoff(attempt))
			end
		end
	end

	if not profile then
		profile = Schema.default()
		if message == MESSAGES.Locked then
			warn(`[Data] {player.Name}'s profile is still open on another server; playing without saving`)
		end
	end
	local loaded = profile :: Schema.Profile
	session.persistent = persistent
	if persistent then
		loaded.meta.sessions += 1
		if loaded.meta.created == 0 then
			loaded.meta.created = os.time()
		end
		session.dirty = true
	end
	session.profile = loaded
	session.lastSavedAt = os.clock()
	session.playCountedAt = os.clock()
	if not persistent and not session.leaving then
		tellPersistence(player, false, message or MESSAGES.Failed)
	end
end

-- Writes the profile and refreshes the lock (or removes it, with `release`).
-- Saves of one profile never overlap, so they land in order. Returns true
-- once the DataStore has the data.
function DataService:_save(session: Session, release: boolean): boolean
	while session.saving do
		task.wait(0.05)
	end
	local profile = session.profile
	if not (session.persistent and profile and store) or session.lockReleased then
		return false
	end
	local dataStore = store :: DataStore
	countPlayTime(session)
	profile.meta.lastSaved = os.time()
	-- Copied before `saving` is set, so a broken profile (a table inside
	-- itself) can't leave every later save waiting forever
	local copied, snapshot = pcall(Schema.copy, profile)
	if not copied then
		warn(`[Data] couldn't copy {session.player.Name}'s profile to save it: {snapshot}`)
		session.dirty = true
		return false
	end
	if not Schema.storable(snapshot) then
		-- Some code put a value a DataStore refuses (NaN, a sparse array, an
		-- Instance...) into the profile. Save a repaired copy rather than fail
		-- every save from now on and lose all later progress.
		warn(`[Data] {session.player.Name}'s profile holds a value a DataStore can't store; saving a repaired copy`)
		snapshot = Schema.migrate(snapshot)
	end
	session.saving = true
	-- Changes made while this save is in flight mark it dirty again
	session.dirty = false

	local outcome: string? = nil
	local ok, err = false, nil
	for attempt = 1, Config.SaveAttempts do
		outcome = nil
		ok, err = pcall(function()
			dataStore:UpdateAsync(session.key, function(stored)
				if typeof(stored) ~= "table" or not ownsLock(stored.lock, session) then
					-- Another server took the profile over: its data wins
					outcome = "lost"
					return nil
				end
				outcome = "saved"
				local record = table.clone(stored)
				record.data = snapshot
				record.lock = if release then nil else newLock(session)
				return record, { session.userId }
			end)
		end)
		if ok then
			break
		end
		warn(`[Data] saving {session.player.Name} failed (try {attempt} of {Config.SaveAttempts}): {err}`)
		if attempt < Config.SaveAttempts then
			task.wait(backoff(attempt))
		end
	end
	session.saving = false

	if ok and outcome == "saved" then
		session.lastSavedAt = os.clock()
		if release then
			session.lockReleased = true
		end
		return true
	elseif ok and outcome == "lost" then
		session.persistent = false
		warn(`[Data] {session.player.Name}'s profile was taken over by another server; this server stopped saving it`)
		tellPersistence(session.player, false, MESSAGES.Lost)
		return false
	end
	session.dirty = true
	warn(`[Data] couldn't save {session.player.Name}; will try again later`)
	return false
end

-- The final save when a player leaves (or the server closes): writes the
-- profile, removes the lock and forgets the session. Safe to call twice.
function DataService:_release(session: Session)
	session.leaving = true
	if session.releasing then
		while not session.released do
			task.wait(0.05)
		end
		return
	end
	session.releasing = true
	while session.loading do
		task.wait(0.05)
	end
	-- A failed final save would lose everything since the last autosave, so
	-- it gets a few more rounds while the server isn't shutting down
	for round = 1, Config.ReleaseRounds do
		if not (session.profile and session.persistent) or session.lockReleased then
			break
		end
		local ok, result = pcall(self._save, self, session, true)
		if not ok then
			warn(`[Data] final save for {session.player.Name} failed: {result}`)
		end
		if (ok and result) or closing or round == Config.ReleaseRounds then
			break
		end
		task.wait(Config.RetryMaxDelay)
	end
	session.released = true
	if sessions[session.userId] == session then
		sessions[session.userId] = nil
	end
end

function DataService:_autosave()
	for _, session in snapshotSessions() do
		if session.persistent and session.profile and not session.leaving and not session.saving then
			local due = session.dirty or os.clock() - session.lastSavedAt >= Config.LockRefreshInterval
			if due then
				if budget() <= Config.AutosaveBudgetReserve then
					-- Out of requests for now; everything still dirty is saved next round
					break
				end
				local ok, err = pcall(self._save, self, session, false)
				if not ok then
					warn(`[Data] autosave for {session.player.Name} failed: {err}`)
				end
			end
		end
	end
end

function DataService:_saveAllOnClose()
	closing = true
	local pending = 0
	for _, session in snapshotSessions() do
		pending += 1
		task.spawn(function()
			pcall(self._release, self, session)
			pending -= 1
		end)
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < Config.CloseTimeout do
		task.wait(0.1)
	end
	if pending > 0 then
		warn(`[Data] the server closed before {pending} profiles finished saving`)
	end
end

function DataService:_queueView(session: Session)
	if session.viewQueued then
		return
	end
	local wait = Config.ViewInterval - (os.clock() - session.lastViewAt)
	if wait <= 0 then
		self:sendView(session.player)
		return
	end
	session.viewQueued = true
	task.delay(wait, function()
		session.viewQueued = false
		if sessionOf(session.player) == session then
			self:sendView(session.player)
		end
	end)
end

-- Public API -----------------------------------------------------------------------------------

-- The player's profile, or nil until it has loaded
function DataService:get(player: Player): Schema.Profile?
	local session = sessionOf(player)
	return session and session.profile
end

-- Waits for the player's profile to load (nil if they leave or it takes too long)
function DataService:waitFor(player: Player, timeout: number?): Schema.Profile?
	local limit = timeout or Config.WaitTimeout
	local started = os.clock()
	while true do
		local profile = self:get(player)
		if profile then
			return profile
		end
		if player.Parent == nil or os.clock() - started >= limit then
			return nil
		end
		task.wait(0.1)
	end
end

-- Changes the profile: runs `mutator(profile)`, marks it for saving and sends
-- the client a fresh view (at most 4 a second). The mutator must not yield,
-- which keeps check-then-change logic (like spending) atomic. Returns false
-- if the profile isn't loaded or the mutator failed.
function DataService:update(player: Player, mutator: (Schema.Profile) -> ()): boolean
	local session = sessionOf(player)
	local profile = session and session.profile
	if not session or not profile then
		return false
	end
	local thread = coroutine.create(mutator)
	local ok, err = coroutine.resume(thread, profile)
	if coroutine.status(thread) ~= "dead" then
		coroutine.close(thread)
		ok, err = false, "the change function yielded (update mutators must not wait)"
	end
	session.dirty = true
	if not ok then
		warn(`[Data] a profile change for {player.Name} failed: {err}`)
	end
	for _, callback in changedCallbacks do
		task.spawn(callback, player, profile)
	end
	self:_queueView(session)
	return ok
end

-- Saves right away (used after Robux grants). True once the DataStore has it.
function DataService:saveNow(player: Player): boolean
	local session = sessionOf(player)
	if not session or not session.profile then
		return false
	end
	local ok, result = pcall(self._save, self, session, false)
	if not ok then
		warn(`[Data] saving {player.Name} failed: {result}`)
		return false
	end
	return result
end

-- False when this player's progress isn't being saved (unsaved copy, newer
-- data, or another server took over)
function DataService:isPersistent(player: Player): boolean
	local session = sessionOf(player)
	return session ~= nil and session.profile ~= nil and session.persistent
end

-- callback(player, profile) once each profile has loaded (also for players
-- already loaded when this is called)
function DataService:onLoaded(callback: (Player, Schema.Profile) -> ())
	table.insert(loadedCallbacks, callback)
	for _, session in sessions do
		if session.profile and not session.loading and not session.leaving then
			task.spawn(callback, session.player, session.profile)
		end
	end
end

-- callback(player, profile) after every update (don't call update from it)
function DataService:onChanged(callback: (Player, Schema.Profile) -> ())
	table.insert(changedCallbacks, callback)
end

-- Sends the player a fresh copy of their profile now
function DataService:sendView(player: Player)
	local session = sessionOf(player)
	if session and session.profile and player.Parent then
		session.lastViewAt = os.clock()
		DataEvent:FireClient(player, Protocol.DataEvent.Profile, Schema.view(session.profile))
	end
end

return DataService
