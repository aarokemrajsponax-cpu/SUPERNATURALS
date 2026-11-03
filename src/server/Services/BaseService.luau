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
}

local bases: { [Player]: Base } = {}
local slots: { [number]: Player } = {}
local street: BaseStreet.Built
local services: any = {}
local friendCache: { [string]: { value: boolean, at: number } } = {}

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
		if def then
			local saved = profile.powers[id]
			local xp = if saved then saved.xp else 0
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
			if math.abs(offset.X) < 40 and math.abs(offset.Z) < 30 and offset.Y > -Homes.VaultDrop - 10 and offset.Y < 30 then
				notice(other, player.Name .. " has left, so their base closed.")
				self:_teleport(other, street.spawn)
			end
		end
	end
	base.built.model:Destroy()
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
	if ownerPlayer ~= player and not self:isFriend(player, ownerPlayer) then
		notice(player, "Friends only. " .. ownerPlayer.Name .. "'s base opens for their Roblox friends.")
		return false
	end
	return self:_teleport(player, base.built.entry)
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
	end
end

return BaseService
