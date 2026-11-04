-- BaseService: Player Base Street, personal bases and the basement Vault
-- (MASTER_REQUIREMENTS section 6 and P.S. 19.0 point 4; DECISIONS.md 8, 9).
--
-- * The street (World/BaseStreet) is built once. A base (World/BaseHome: home plus vault) is
--   built for each player once their profile has loaded and destroyed when they leave, so
--   bases exist only for present players. The street door of a free slot is dark and off.
-- * Doors: your own door always opens. Another player's door opens only for that player's
--   Roblox friends, checked HERE on the server (Player:IsFriendsWith in a pcall, cached for
--   Homes.FriendCacheSeconds), otherwise a polite "Friends only" notice. The client never says
--   who is a friend. In-world prompts carry no Action attribute: this service listens to their
--   Triggered events itself and checks distance, rate limit and the match state.
-- * The display wall and vault render the player's REAL profile (wins, mastery per fighter,
--   titles, cosmetics, owned premium fighters). Rendering is event driven (DataService
--   onChanged), never per frame.
-- * Personalisation (profile.base.theme and profile.base.show) is changed only through the
--   validated requests BaseAction.Decor and BaseAction.Toggle (or the matching pads in the home)
--   and only for your own base.
-- * The vault lift works for the owner of that base only. The secret Archive alcove opens when
--   LoreService:foundCount reaches every Archive file. The command console exists only in a
--   base whose owner passes OwnerService:isOwner; its prompt re-checks that and then sends
--   BaseEvent.OpenConsole. The owner panel's own server checks stay the authority.
-- * BaseService.friendCheck(player, userId) can be replaced by tests.
-- Visitors are returned to the street when the owner leaves.
-- * Hosting (DECISIONS 62): hosting.access ("Friends" default, "Everyone", "Nobody") is checked on
--   every entry; narrowing it sends visitors who are no longer allowed back to the street. The
--   owner can ask a visitor inside the base to leave. The visitors board lists the last 8 visitors
--   by Roblox display name; each visitor gives one heart per base per UTC day. The first time each
--   UTC day a Roblox friend has stayed 60 seconds the owner earns a small Money host bonus
--   (presence tick, once per day, so re-entering cannot farm it).
-- * The jukebox style, party mode, Base Effects Pack looks (pass checked here) and the Fireworks
--   Show (saved charges, launched by the owner) are all requests validated here; the look is built
--   by World/BaseHome and World/GameRoom. The game room's activities live in GameRoomService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Homes = require(ReplicatedStorage.Shared.Config.Homes)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Archive = require(ReplicatedStorage.Shared.Content.Archive)
local BaseStreet = require(script.Parent.Parent.World.BaseStreet)
local BaseHome = require(script.Parent.Parent.World.BaseHome)

local BaseService = {}

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BaseRequest = Remotes:WaitForChild("BaseRequest") :: RemoteEvent
local BaseEvent = Remotes:WaitForChild("BaseEvent") :: RemoteEvent

local Action = Protocol.BaseAction

type Base = {
	player: Player,
	slot: number,
	origin: Vector3,
	built: BaseHome.Built,
	ownerBase: boolean,
	party: boolean?,
	animated: boolean?,
	applied: string?,
	showing: boolean?,
}

local bases: { [Player]: Base } = {}
local slots: { [number]: Player } = {}
local street: BaseStreet.Built
local services: any = {}
local friendCache: { [string]: { value: boolean, at: number } } = {}
-- Visitors who were asked to leave: ["visitorId:ownerId"] = clock time they may return
local barred: { [string]: number } = {}
local lastAsk: { [Player]: number } = {}
-- Where each visitor has been standing: [Player] = { owner = Player, since = clock }
local presence: { [Player]: { owner: Player, since: number } } = {}
local fireworkColors = { Color3.fromRGB(255, 96, 96), Color3.fromRGB(255, 200, 80), Color3.fromRGB(110, 220, 160), Color3.fromRGB(110, 170, 255), Color3.fromRGB(220, 130, 255) }

-- Roblox display name, falling back to the account name
function BaseService.shownName(player: Player): string
	return if player.DisplayName ~= "" then player.DisplayName else player.Name
end

-- Replaceable in tests
BaseService.now = os.time
BaseService.clock = os.clock
function BaseService.today(): number
	return BaseService.now() // 86400
end

-- A saved Fireworks Show charge (PurchaseService adds one per purchase; capped)
function BaseService.addFireworkCharges(data: any, count: number)
	data.hosting.fireworks = math.min(Homes.FireworksMaxCharges, data.hosting.fireworks + count)
end

-- Replaceable in tests; Roblox's call can fail or yield, so it runs in a pcall
BaseService.friendCheck = function(player: Player, userId: number): boolean
	local ok, result = pcall(function()
		return player:IsFriendsWith(userId)
	end)
	return ok and result == true
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function notice(player: Player, text: string)
	BaseEvent:FireClient(player, Protocol.BaseEvent.Result, { ok = false, message = text })
	Remotes.MatchEvent:FireClient(player, Protocol.MatchEvent.Notice, { text = text })
end

local function readable(id: string): string
	return Homes.titleName(id)
end

-- The numbers the boards show, from the real profile ----------------------------------------------

function BaseService:viewOf(player: Player, profile: any): any
	local thresholds = Powers.Mastery.Thresholds
	local mastery, premiumOwned, premiumTotal = {}, {}, 0
	for _, id in Powers.Order do
		local def = Powers.get(id)
		if def and Powers.isReleased(id) then
			local saved = profile.powers[id]
			-- A power can have a record (bought, or a trial) before it has any experience
			local xp = if saved and typeof(saved.xp) == "number" then saved.xp else 0
			local level = Powers.masteryLevel(xp)
			local nextXp = Powers.nextLevelXp(xp)
			local progress = if nextXp then (xp - thresholds[level]) / (nextXp - thresholds[level]) else 1
			local color = def.colors and def.colors.primary or Color3.new(1, 1, 1)
			table.insert(mastery, { id = id, name = def.name, level = level, progress = math.clamp(progress, 0, 1), color = color })
			if Powers.isPremium(id) then
				premiumTotal += 1
				local owns = false
				if services.PowerService and services.PowerService.owns then
					local ok, result = pcall(services.PowerService.owns, services.PowerService, player, id)
					owns = ok and result == true
				else
					owns = saved ~= nil and saved.owned == true
				end
				if owns then
					table.insert(premiumOwned, { id = id, name = def.name, color = color })
				end
			end
		end
	end
	local titles, cosmetics = {}, {}
	for id in profile.cosmetics.owned do
		if string.sub(id, 1, 6) == "title_" then
			table.insert(titles, readable(id))
		else
			table.insert(cosmetics, readable(id))
		end
	end
	table.sort(titles)
	table.sort(cosmetics)
	local equipped = profile.cosmetics.equipped.title
	return {
		name = player.Name,
		wins = profile.stats.wins,
		matches = profile.stats.matches,
		bestStreak = profile.stats.bestStreak,
		title = if equipped and profile.cosmetics.owned[equipped] then readable(equipped) else "None",
		mastery = mastery,
		titles = titles,
		cosmetics = cosmetics,
		premiumOwned = premiumOwned,
		premiumTotal = premiumTotal,
		show = profile.base.show,
		theme = profile.base.theme,
	}
end

-- Lifecycle ---------------------------------------------------------------------------------------

function BaseService:Init(all)
	services = all
	self.data = all.DataService
	self.characters = all.CharacterService
	self.arenas = all.ArenaService
	self.owner = all.OwnerService
	self.lore = all.LoreService
	self.antiExploit = all.AntiExploitService
end

function BaseService:Start()
	street = BaseStreet.build(workspace)
	self.street = street
	street.returnPrompt.Triggered:Connect(function(player)
		if self:_allow(player, street.returnPrompt.Parent :: BasePart) then
			self:_teleport(player, self.arenas:lobbySpawn())
		end
	end)
	for slot, door in street.doors do
		door.prompt.Triggered:Connect(function(player)
			if self:_allow(player, door.prompt.Parent :: BasePart) then
				self:_useDoor(player, slot)
			end
		end)
	end

	self.data:onLoaded(function(player)
		self:_create(player)
	end)
	self.data:onChanged(function(player)
		self:_refresh(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:_remove(player)
	end)
	local purchases = services.PurchaseService
	if purchases and purchases.onPassGranted then
		purchases:onPassGranted(function(player, key)
			if key == Homes.EffectsPass then
				self:_applyHosting(player)
				self:pushPanel(player)
			end
		end)
	end
	task.spawn(function()
		while true do
			task.wait(Homes.PresenceTick)
			self:_presenceTick()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Homes.PartyTick)
			self:_animate()
		end
	end)
	BaseRequest.OnServerEvent:Connect(function(player, action, first, second)
		if typeof(action) ~= "string" then
			return
		end
		if not self.antiExploit:allow(player, "Base") then
			return
		end
		self:_handle(player, action, first, second)
	end)
end

function BaseService:baseOf(player: Player): Base?
	return bases[player]
end

function BaseService:slotOwner(slot: number): Player?
	return slots[slot]
end

function BaseService:_create(player: Player)
	if bases[player] or player.Parent == nil then
		return
	end
	local slot
	for index = 1, Homes.Slots do
		if not slots[index] then
			slot = index
			break
		end
	end
	if not slot then
		warn("[Base] all base slots are taken; no base for " .. player.Name)
		return
	end
	local origin = Homes.BaseOrigin + Vector3.new((slot - 1) * Homes.SlotSpacing, 0, 0)
	local ownerBase = self.owner ~= nil and self.owner:isOwner(player)
	local built = BaseHome.build(workspace, origin, { name = player.Name, userId = player.UserId, slot = slot }, ownerBase)
	local base: Base = { player = player, slot = slot, origin = origin, built = built, ownerBase = ownerBase }
	bases[player] = base
	slots[slot] = player
	street.setDoor(slot, player.Name)
	for key, prompt in built.prompts do
		prompt.Triggered:Connect(function(who)
			if self:_allow(who, prompt.Parent :: BasePart) then
				self:_promptUsed(who, base, key)
			end
		end)
	end
	self:_refresh(player)
	self:_applyHosting(player)
	player:SetAttribute("InBaseOf", 0)
end

function BaseService:_remove(player: Player)
	local base = bases[player]
	if not base then
		return
	end
	bases[player] = nil
	slots[base.slot] = nil
	street.setDoor(base.slot, nil)
	-- Anyone still inside goes back to the street first
	for _, other in Players:GetPlayers() do
		local root = rootOf(other)
		if other ~= player and root then
			local offset = root.Position - base.origin
			if math.abs(offset.X) < 40 and offset.Z > Homes.InsideZMin and offset.Z < Homes.InsideZMax and offset.Y > -Homes.VaultDrop - 10 and offset.Y < 30 then
				notice(other, player.Name .. " has left, so their base closed.")
				self:_teleport(other, street.spawn)
			end
		end
	end
	base.built.model:Destroy()
	lastAsk[player] = nil
	for visitor, entry in presence do
		if entry.owner == player then
			presence[visitor] = nil
		end
	end
end

function BaseService:_refresh(player: Player)
	local base = bases[player]
	local profile = self.data:get(player)
	if not base or not profile then
		return
	end
	base.built.render(self:viewOf(player, profile))
	local total = #Archive.FileOrder
	local found = self.lore:foundCount(player)
	base.built.setAlcove(found >= total, found, total)
end

-- Doors, lifts and pads -----------------------------------------------------------------------------

-- The server's own checks for any prompt press: rate limit, near the prompt, a living fighter
function BaseService:_allow(player: Player, part: BasePart?): boolean
	if not self.antiExploit:allow(player, "Base") then
		return false
	end
	local root = rootOf(player)
	if not root or not part then
		return false
	end
	if (root.Position - part.Position).Magnitude > Homes.PromptReach + 8 then
		self.antiExploit:flag(player, "used a base prompt from far away")
		return false
	end
	return true
end

function BaseService:_inMatch(player: Player): boolean
	local fighter = self.characters:getByPlayer(player)
	return fighter ~= nil and services.MatchService ~= nil and services.MatchService:getMatchOf(fighter) ~= nil
end

function BaseService:_teleport(player: Player, destination: CFrame): boolean
	if self:_inMatch(player) then
		notice(player, "You can't use bases during a match.")
		return false
	end
	local fighter = self.characters:getByPlayer(player)
	if not fighter or not self.characters:isAlive(fighter) then
		return false
	end
	self.characters:teleport(fighter, destination)
	return true
end

function BaseService:isFriend(player: Player, other: Player): boolean
	local low, high = math.min(player.UserId, other.UserId), math.max(player.UserId, other.UserId)
	local key = low .. ":" .. high
	local cached = friendCache[key]
	local now = os.clock()
	if cached and now - cached.at < Homes.FriendCacheSeconds then
		return cached.value
	end
	local value = BaseService.friendCheck(player, other.UserId) == true
	friendCache[key] = { value = value, at = now }
	return value
end

-- Opens a base door for `player`: own door always, a friend's door for friends only
function BaseService:enter(player: Player, ownerPlayer: Player?): boolean
	local base = if ownerPlayer then bases[ownerPlayer] else nil
	if not ownerPlayer or not base then
		notice(player, "That base is closed right now.")
		return false
	end
	if ownerPlayer ~= player then
		local allowed, reason = self:mayEnter(player, ownerPlayer)
		if not allowed then
			notice(player, reason)
			return false
		end
	end
	local moved = self:_teleport(player, base.built.entry)
	if moved and ownerPlayer ~= player then
		player:SetAttribute("InBaseOf", ownerPlayer.UserId)
		self:_recordVisitor(ownerPlayer, player)
	end
	return moved
end

-- Hosting -----------------------------------------------------------------------------------------------

function BaseService:accessOf(owner: Player): string
	local profile = self.data:get(owner)
	return if profile then profile.hosting.access else "Friends"
end

-- Whether `visitor` may come into `owner`'s base now (the owner always may). Returns the reason if not.
function BaseService:mayEnter(visitor: Player, owner: Player): (boolean, string)
	if visitor == owner then
		return true, ""
	end
	local bar = barred[visitor.UserId .. ":" .. owner.UserId]
	if bar and BaseService.clock() < bar then
		return false, owner.Name .. " asked you to leave. Try again in a little while."
	end
	local mode = self:accessOf(owner)
	if mode == "Everyone" then
		return true, ""
	elseif mode == "Nobody" then
		return false, owner.Name .. " is not having visitors right now."
	end
	if self:isFriend(visitor, owner) then
		return true, ""
	end
	return false, "Friends only. " .. owner.Name .. "'s base opens for their Roblox friends."
end

-- In the home or game room of this base (the owner-only vault is not counted)
function BaseService:isInside(player: Player, base: Base): boolean
	local root = rootOf(player)
	if not root then
		return false
	end
	local offset = root.Position - base.origin
	return math.abs(offset.X) < Homes.InsideX and offset.Z > Homes.InsideZMin and offset.Z < Homes.InsideZMax and offset.Y > -5 and offset.Y < 30
end

function BaseService:playersInside(base: Base): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if self:isInside(player, base) then
			table.insert(list, player)
		end
	end
	return list
end

function BaseService:baseAt(player: Player): Base?
	for _, base in bases do
		if self:isInside(player, base) then
			return base
		end
	end
	return nil
end

-- The owner's hosting record, with the UTC-day counters rolled over
function BaseService:_hosting(owner: Player): any?
	local profile = self.data:get(owner)
	if not profile then
		return nil
	end
	local today = BaseService.today()
	if profile.hosting.day ~= today then
		self.data:update(owner, function(data)
			data.hosting.day = today
			data.hosting.heartedToday = {}
		end)
	end
	return profile.hosting
end

function BaseService:_sendOut(player: Player, base: Base, text: string)
	notice(player, text)
	player:SetAttribute("InBaseOf", 0)
	self:_teleport(player, street.doorFront(base.slot))
end

function BaseService:setAccess(player: Player, mode: any): (boolean, string)
	local base = bases[player]
	if not base or not self.data:get(player) then
		return false, "Your base isn't ready yet."
	end
	if typeof(mode) ~= "string" or not Homes.AccessModes[mode] then
		return false, "That isn't a way to share your base."
	end
	self.data:update(player, function(data)
		data.hosting.access = mode
	end)
	-- Narrowing: anyone inside who may no longer come in goes back to the street
	for _, other in self:playersInside(base) do
		if other ~= player then
			local allowed = self:mayEnter(other, player)
			if not allowed then
				self:_sendOut(other, base, player.Name .. " changed who can visit, so you were returned to the street.")
			end
		end
	end
	self:pushPanel(player)
	return true, Homes.AccessModes[mode].label .. ": " .. Homes.AccessModes[mode].blurb
end

function BaseService:askLeave(owner: Player, userId: any): (boolean, string)
	local base = bases[owner]
	if not base then
		return false, "Your base isn't ready yet."
	end
	if typeof(userId) ~= "number" or userId ~= userId then
		return false, "Choose a visitor."
	end
	local now = BaseService.clock()
	if lastAsk[owner] and now - lastAsk[owner] < Homes.AskLeaveCooldown then
		return false, "Please wait a moment."
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target or target == owner or not self:isInside(target, base) then
		return false, "That player is not in your base."
	end
	lastAsk[owner] = now
	barred[target.UserId .. ":" .. owner.UserId] = now + Homes.AskLeaveBar
	self:_sendOut(target, base, owner.Name .. " asked you to leave.")
	return true, BaseService.shownName(target) .. " was shown out."
end

function BaseService:_recordVisitor(owner: Player, visitor: Player)
	local profile = self.data:get(owner)
	if not profile then
		return
	end
	self.data:update(owner, function(data)
		local list = data.hosting.visitors
		for i = #list, 1, -1 do
			if list[i].id == visitor.UserId then
				table.remove(list, i)
			end
		end
		table.insert(list, { id = visitor.UserId, name = string.sub(BaseService.shownName(visitor), 1, 40) })
		while #list > Homes.VisitorsKept do
			table.remove(list, 1)
		end
	end)
	self:_applyHosting(owner)
	self:pushPanel(owner)
end

function BaseService:giveHeart(player: Player, ownerUserId: any): (boolean, string)
	local base = self:baseAt(player)
	if not base then
		return false, "Stand inside a base to give a heart."
	end
	if typeof(ownerUserId) == "number" and ownerUserId ~= base.player.UserId then
		return false, "That isn't the base you are in."
	end
	local owner = base.player
	if owner == player then
		return false, "Hearts come from your visitors."
	end
	local hosting = self:_hosting(owner)
	if not hosting then
		return false, "That base is not ready."
	end
	local key = tostring(player.UserId)
	if hosting.heartedToday[key] then
		return false, "You already gave " .. BaseService.shownName(owner) .. " a heart today."
	end
	self.data:update(owner, function(data)
		data.hosting.heartedToday[key] = true
		data.hosting.hearts += 1
	end)
	self:_applyHosting(owner)
	self:pushPanel(owner)
	return true, "You gave " .. BaseService.shownName(owner) .. " a heart."
end

-- Every few seconds: who is in which base, the host bonus, the room's score board
function BaseService:_presenceTick()
	local now = BaseService.clock()
	local seen: { [Player]: boolean } = {}
	for owner, base in bases do
		local inside = self:playersInside(base)
		for _, visitor in inside do
			seen[visitor] = true
			if visitor ~= owner then
				local entry = presence[visitor]
				if not entry or entry.owner ~= owner then
					entry = { owner = owner, since = now }
					presence[visitor] = entry
				end
				visitor:SetAttribute("InBaseOf", owner.UserId)
				if now - entry.since >= Homes.HostBonusSeconds then
					self:_hostBonus(owner, visitor)
				end
			else
				owner:SetAttribute("InBaseOf", owner.UserId)
			end
		end
		if services.GameRoomService then
			services.GameRoomService:refreshBoard(base)
		end
	end
	for _, player in Players:GetPlayers() do
		if not seen[player] then
			presence[player] = nil
			if player:GetAttribute("InBaseOf") ~= 0 then
				player:SetAttribute("InBaseOf", 0)
			end
		end
	end
end

-- The first time each UTC day that a Roblox friend has stayed long enough: a little Money for the host
function BaseService:_hostBonus(owner: Player, visitor: Player)
	local hosting = self:_hosting(owner)
	local today = BaseService.today()
	if not hosting or hosting.bonusDay == today or not self:isFriend(visitor, owner) then
		return
	end
	self.data:update(owner, function(data)
		data.hosting.bonusDay = today
	end)
	if services.CurrencyService then
		services.CurrencyService:add(owner, { money = Homes.HostBonusMoney }, "Host bonus")
	end
	Remotes.MatchEvent:FireClient(owner, Protocol.MatchEvent.Notice, { text = string.format("%s stayed a while. Host bonus: +%d Money.", BaseService.shownName(visitor), Homes.HostBonusMoney) })
end

-- Jukebox, party, effects, fireworks ---------------------------------------------------------------------

function BaseService:ownsEffects(player: Player): boolean
	local purchases = services.PurchaseService
	if not purchases or not purchases.ownsPass then
		return false
	end
	local ok, owns = pcall(purchases.ownsPass, purchases, player, Homes.EffectsPass)
	return ok and owns == true
end

-- Puts the saved hosting state on the base: music attribute, visitors board, owned effects
function BaseService:_applyHosting(player: Player)
	local base = bases[player]
	local profile = self.data:get(player)
	if not base or not profile then
		return
	end
	local hosting = profile.hosting
	local owns = self:ownsEffects(player)
	local parts = { hosting.jukebox, tostring(hosting.hearts), tostring(owns) }
	local names = {}
	for _, visitor in hosting.visitors do
		table.insert(names, visitor.name)
	end
	table.insert(parts, table.concat(names, ","))
	for _, key in Homes.EffectOrder do
		table.insert(parts, if owns and hosting.effects[key] then "1" else "0")
	end
	local signature = table.concat(parts, "|")
	if signature == base.applied then
		return
	end
	base.applied = signature
	base.built.model:SetAttribute("MusicStyle", hosting.jukebox)
	base.built.gameRoom.setJukebox("NOW PLAYING\n" .. hosting.jukebox)
	-- Newest visitor first on the board
	local newestFirst = {}
	for i = #names, 1, -1 do
		table.insert(newestFirst, names[i])
	end
	base.built.setVisitors(newestFirst, hosting.hearts)
	local animated = false
	for _, key in Homes.EffectOrder do
		local on = owns and hosting.effects[key] == true
		base.built.setEffect(key, on)
		if on and (key == "Aurora" or key == "LightShow") then
			animated = true
		end
	end
	base.animated = animated
end

function BaseService:setJukebox(player: Player, style: any): (boolean, string)
	local base = bases[player]
	local profile = self.data:get(player)
	if not base or not profile then
		return false, "Your base isn't ready yet."
	end
	if style == nil then
		local index = table.find(Homes.MusicStyles, profile.hosting.jukebox) or 0
		style = Homes.MusicStyles[index % #Homes.MusicStyles + 1]
	end
	if typeof(style) ~= "string" or not table.find(Homes.MusicStyles, style) then
		return false, "That music style doesn't exist."
	end
	self.data:update(player, function(data)
		data.hosting.jukebox = style
	end)
	self:_applyHosting(player)
	self:pushPanel(player)
	return true, "Jukebox: " .. style .. "."
end

function BaseService:setParty(player: Player, on: any): (boolean, string)
	local base = bases[player]
	if not base then
		return false, "Your base isn't ready yet."
	end
	if typeof(on) ~= "boolean" then
		return false, "Choose on or off."
	end
	base.party = on
	base.built.setParty(on)
	self:pushPanel(player)
	return true, if on then "Party mode is on." else "Party mode is off."
end

function BaseService:setEffect(player: Player, key: any, on: any): (boolean, string)
	local base = bases[player]
	if not base or not self.data:get(player) then
		return false, "Your base isn't ready yet."
	end
	if typeof(key) ~= "string" or not Homes.Effects[key] or typeof(on) ~= "boolean" then
		return false, "That effect doesn't exist."
	end
	if on and not self:ownsEffects(player) then
		return false, "The Base Effects Pack unlocks this."
	end
	self.data:update(player, function(data)
		data.hosting.effects[key] = if on then true else nil
	end)
	self:_applyHosting(player)
	self:pushPanel(player)
	return true, Homes.Effects[key].label .. (if on then " is on." else " is off.")
end

function BaseService:canSellFireworks(player: Player): (boolean, string?)
	local profile = self.data:get(player)
	if profile and profile.hosting.fireworks >= Homes.FireworksMaxCharges then
		return false, "You already have the most saved shows. Launch one first."
	end
	return true, nil
end

function BaseService:onChargesChanged(player: Player)
	self:pushPanel(player)
end

function BaseService:launchFireworks(player: Player): (boolean, string)
	local base = bases[player]
	local profile = self.data:get(player)
	if not base or not profile then
		return false, "Your base isn't ready yet."
	end
	if base.showing then
		return false, "A show is already running."
	end
	if profile.hosting.fireworks < 1 then
		return false, "You have no saved shows. The Fireworks Show is in the Shop."
	end
	self.data:update(player, function(data)
		data.hosting.fireworks -= 1
	end)
	base.showing = true
	base.built.model:SetAttribute("FireworksUntil", workspace:GetServerTimeNow() + Homes.FireworksSeconds)
	self:pushPanel(player)
	task.spawn(function()
		base.built.fireworks.start()
		local shots = 0
		local started = BaseService.clock()
		while BaseService.clock() - started < Homes.FireworksSeconds and bases[player] == base do
			shots += 1
			base.built.fireworks.shot(shots, fireworkColors[shots % #fireworkColors + 1])
			task.wait(Homes.FireworksShotEvery)
		end
		base.built.fireworks.stop()
		base.showing = false
		base.built.model:SetAttribute("FireworksUntil", 0)
		if bases[player] == base then
			self:pushPanel(player)
		end
	end)
	return true, "The show begins."
end

function BaseService:_animate()
	local hue = (BaseService.clock() * Homes.PartyStep / Homes.PartyTick * 0.25) % 1
	for _, base in bases do
		if base.party or base.animated then
			base.built.animate(hue)
		end
	end
end

-- The numbers the base panel shows (to the owner only)
function BaseService:panelState(player: Player): any?
	local base = bases[player]
	local profile = self.data:get(player)
	if not base or not profile then
		return nil
	end
	local hosting = self:_hosting(player) or profile.hosting
	local effects = {}
	for _, key in Homes.EffectOrder do
		effects[key] = hosting.effects[key] == true
	end
	local visitors = {}
	for i = #hosting.visitors, 1, -1 do
		table.insert(visitors, { id = hosting.visitors[i].id, name = hosting.visitors[i].name })
	end
	local here = {}
	for _, other in self:playersInside(base) do
		if other ~= player then
			table.insert(here, { id = other.UserId, name = BaseService.shownName(other) })
		end
	end
	return {
		access = hosting.access,
		jukebox = hosting.jukebox,
		party = base.party == true,
		effects = effects,
		ownsEffects = self:ownsEffects(player),
		fireworks = hosting.fireworks,
		showing = base.showing == true,
		hearts = hosting.hearts,
		visitors = visitors,
		here = here,
		bests = { PowerMeter = hosting.bests.PowerMeter, Reflex = hosting.bests.Reflex },
	}
end

function BaseService:pushPanel(player: Player, open: boolean?)
	local state = self:panelState(player)
	if state then
		state.open = open == true
		BaseEvent:FireClient(player, Protocol.BaseEvent.Panel, state)
	end
end

function BaseService:_useDoor(player: Player, slot: number)
	self:enter(player, slots[slot])
end

function BaseService:_promptUsed(player: Player, base: Base, key: string)
	local isOwnerOfBase = base.player == player
	if key == "Exit" then
		self:_teleport(player, street.doorFront(base.slot))
	elseif key == "LiftDown" then
		if not isOwnerOfBase then
			notice(player, "The lift to the Vault is for the owner of this base.")
		else
			self:_teleport(player, base.built.vaultEntry)
		end
	elseif key == "LiftUp" then
		if isOwnerOfBase then
			self:_teleport(player, base.built.entry)
		end
	elseif key == "Console" then
		if not (isOwnerOfBase and base.ownerBase and self.owner:isOwner(player)) then
			self.antiExploit:flag(player, "tried to use the vault console")
			return
		end
		BaseEvent:FireClient(player, Protocol.BaseEvent.OpenConsole, {})
	elseif key == "Panel" then
		if isOwnerOfBase then
			self:pushPanel(player, true)
		else
			notice(player, "The base panel is for the owner of this base.")
		end
	elseif key == "Heart" then
		local _, message = self:giveHeart(player, base.player.UserId)
		notice(player, message)
	elseif key == "Jukebox" then
		if isOwnerOfBase then
			local _, message = self:setJukebox(player, nil)
			notice(player, message)
		else
			notice(player, "Only the owner picks the music. Now playing: " .. (self.data:get(base.player) and self.data:get(base.player).hosting.jukebox or "") .. ".")
		end
	elseif key == "PowerMeter" or key == "Reflex" then
		if services.GameRoomService then
			services.GameRoomService:press(player, base, key)
		end
	elseif string.sub(key, 1, 3) == "Pad" then
		if not isOwnerOfBase then
			notice(player, "Only the owner can change this base.")
			return
		end
		local which = string.sub(key, 4)
		if which == "Theme" then
			self:setTheme(player, nil)
		else
			local toggle = string.lower(which)
			local profile = self.data:get(player)
			if profile and Homes.Toggles[toggle] then
				self:setToggle(player, toggle, not profile.base.show[toggle])
			end
		end
	end
end

-- Personalisation: validated, then saved in the profile ------------------------------------------------

-- themeId nil = the next theme in the list
function BaseService:setTheme(player: Player, themeId: any): (boolean, string)
	local profile = self.data:get(player)
	if not profile or not bases[player] then
		return false, "Your base isn't ready yet."
	end
	if themeId == nil then
		local index = table.find(Homes.ThemeOrder, profile.base.theme) or 0
		themeId = Homes.ThemeOrder[index % #Homes.ThemeOrder + 1]
	end
	if typeof(themeId) ~= "string" or not Homes.Themes[themeId] then
		return false, "That decor theme doesn't exist."
	end
	self.data:update(player, function(current)
		current.base.theme = themeId
	end)
	return true, "Decor set to " .. Homes.Themes[themeId].name .. "."
end

function BaseService:setToggle(player: Player, key: any, value: any): (boolean, string)
	local profile = self.data:get(player)
	if not profile or not bases[player] then
		return false, "Your base isn't ready yet."
	end
	if typeof(key) ~= "string" or not Homes.Toggles[key] or typeof(value) ~= "boolean" then
		return false, "That display setting doesn't exist."
	end
	self.data:update(player, function(current)
		current.base.show[key] = value
	end)
	return true, Homes.Toggles[key].label .. (if value then " shown." else " hidden.")
end

function BaseService:_handle(player: Player, action: string, first: any, second: any)
	local function result(ok: boolean, message: string)
		BaseEvent:FireClient(player, Protocol.BaseEvent.Result, { ok = ok, message = message })
	end
	if action == Action.Street then
		if self:_teleport(player, street.spawn) then
			result(true, "Welcome to Player Base Street.")
		end
	elseif action == Action.Home then
		local base = bases[player]
		if not base then
			result(false, "Your base isn't ready yet.")
		elseif self:_teleport(player, base.built.entry) then
			result(true, "Welcome home.")
		end
	elseif action == Action.Visit then
		if typeof(first) == "number" then
			for target, base in bases do
				if target.UserId == first then
					self:enter(player, target)
					return
				end
			end
		end
		result(false, "That base is closed right now.")
	elseif action == Action.Decor then
		result(self:setTheme(player, first or false))
	elseif action == Action.Toggle then
		result(self:setToggle(player, first, second))
	elseif action == Action.SetAccess then
		result(self:setAccess(player, first))
	elseif action == Action.AskLeave then
		result(self:askLeave(player, first))
	elseif action == Action.Heart then
		result(self:giveHeart(player, first))
	elseif action == Action.Effect then
		result(self:setEffect(player, first, second))
	elseif action == Action.Jukebox then
		result(self:setJukebox(player, if first == nil then false else first))
	elseif action == Action.Party then
		result(self:setParty(player, first))
	elseif action == Action.Fireworks then
		result(self:launchFireworks(player))
	elseif action == Action.Activity then
		local base = self:baseAt(player)
		if base and services.GameRoomService and typeof(first) == "string" then
			services.GameRoomService:press(player, base, first)
		end
	elseif action == Action.Panel then
		self:pushPanel(player)
	end
end

return BaseService
