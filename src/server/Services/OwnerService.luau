-- The owner panel's server side. Only the accounts in OwnerConfig may use it;
-- every request is checked here, so opening the panel with an exploit does
-- nothing. Covers admin-abuse events, actions on players, the owner's own
-- toggles (fly, immunity, invisibility, crown) and server controls
-- (announcements, time of day, seasons, ending matches).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local AdminEvents = require(ReplicatedStorage.Shared.Config.AdminEvents)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Seasons = require(ReplicatedStorage.Shared.Seasons)
local OwnerConfig = require(script.Parent.Parent.OwnerConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AdminRequest = Remotes:WaitForChild("AdminRequest") :: RemoteEvent
local AdminEvent = Remotes:WaitForChild("AdminEvent") :: RemoteEvent

local Action = Protocol.AdminAction
local Attribute = Protocol.Attribute
local Signal = Protocol.AdminSignal
local Settings = AdminEvents.ActionSettings

local OwnerService = {}

local ownerIds: { [number]: boolean } = {}
local ownerNames: { [string]: boolean } = {}
local bannedIds: { [number]: boolean } = {}
-- Timers and hidden-part transparency are stored as attributes on the
-- instances themselves (Roblox can recycle the Lua object for an Instance, so a
-- table keyed by Instances could forget them)
local TIMER_PREFIX = "SNTimer_"
local HIDDEN_ATTRIBUTE = "SNVisibleTransparency"
local timerCount = 0

local VALID_PLAYER_ACTIONS = {}
for _, action in AdminEvents.PlayerActions do
	VALID_PLAYER_ACTIONS[action.id] = true
end

local AURAS = {
	AuraGold = "Gold",
	AuraRainbow = "Rainbow",
	AuraVoid = "Void",
	AuraFrost = "Frost",
}

local MAX_ANNOUNCEMENT = 200

function OwnerService:Init(services)
	self.services = services
	self.characters = services.CharacterService
	self.damage = services.DamageService
	self.events = services.AdminEventService
	self.antiExploit = services.AntiExploitService
	for _, name in OwnerConfig.Usernames do
		ownerNames[string.lower(name)] = true
	end
	for _, id in OwnerConfig.UserIds do
		ownerIds[id] = true
	end
	if OwnerConfig.IncludeGameCreator and game.CreatorType == Enum.CreatorType.User and game.CreatorId > 0 then
		ownerIds[game.CreatorId] = true
	end
end

function OwnerService:Start()
	-- Turn usernames into user ids so a renamed account keeps the panel
	task.spawn(function()
		for _, name in OwnerConfig.Usernames do
			local ok, id = pcall(Players.GetUserIdFromNameAsync, Players, name)
			if ok and typeof(id) == "number" then
				ownerIds[id] = true
			end
		end
		for _, player in Players:GetPlayers() do
			self:_refreshOwner(player)
		end
	end)

	local function onPlayer(player: Player)
		if bannedIds[player.UserId] then
			player:Kick("You were banned from this server by the owner.")
			return
		end
		self:_refreshOwner(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	-- Invisibility survives respawning
	self.characters:onSpawned(function(fighter)
		local player = fighter.player
		if player and player:GetAttribute(Attribute.Invisible) then
			task.defer(self._setInvisible, self, fighter.model, true)
		end
	end)

	AdminRequest.OnServerEvent:Connect(function(player, action, first, second)
		if not self.antiExploit:allow(player, "Admin") then
			return
		end
		if not self:isOwner(player) then
			self.antiExploit:flag(player, "tried to use the owner panel")
			return
		end
		if typeof(action) ~= "string" then
			return
		end
		local ok, err = pcall(self._handle, self, player, action, first, second)
		if not ok then
			warn(`[Owner] {action} failed: {err}`)
		end
	end)
end

function OwnerService:isOwner(player: Player): boolean
	return ownerIds[player.UserId] == true or ownerNames[string.lower(player.Name)] == true
end

function OwnerService:_refreshOwner(player: Player)
	if self:isOwner(player) and player:GetAttribute(Attribute.IsOwner) ~= true then
		player:SetAttribute(Attribute.IsOwner, true)
		player:SetAttribute(Attribute.Crown, true)
	end
end

function OwnerService:_notify(player: Player, text: string)
	ReplicatedStorage.Remotes.MatchEvent:FireClient(player, Protocol.MatchEvent.Notice, { text = text })
end

function OwnerService:_handle(owner: Player, action: string, first: any, second: any)
	if action == Action.StartEvent then
		if typeof(first) == "string" and AdminEvents.Events[first] then
			self.events:start(first, owner)
		end
	elseif action == Action.StopEvent then
		self.events:stop()
	elseif action == Action.PlayerAction then
		if typeof(second) == "string" and VALID_PLAYER_ACTIONS[second] then
			self:_playerAction(owner, first, second)
		end
	elseif action == Action.SelfToggle then
		if typeof(first) == "string" and typeof(second) == "boolean" then
			self:_selfToggle(owner, first, second)
		end
	elseif action == Action.Announce then
		if typeof(first) == "string" then
			self:_announce(owner, first)
		end
	elseif action == Action.SetTime then
		for _, option in AdminEvents.TimesOfDay do
			if option.id == first then
				Lighting.ClockTime = option.clockTime
			end
		end
	elseif action == Action.SetSeason then
		if first == "Auto" then
			ReplicatedStorage:SetAttribute(Attribute.SeasonOverride, nil)
		elseif typeof(first) == "string" and Seasons.Themes[first] then
			ReplicatedStorage:SetAttribute(Attribute.SeasonOverride, first)
		end
	elseif action == Action.EndMatches then
		self.services.MatchService:endAll()
		self:_notify(owner, "All matches ended.")
	end
end

-- Player actions ---------------------------------------------------------------------

local function targetsOf(owner: Player, target: any): { Player }
	if target == "All" then
		return Players:GetPlayers()
	elseif target == "Others" then
		local list = {}
		for _, player in Players:GetPlayers() do
			if player ~= owner then
				table.insert(list, player)
			end
		end
		return list
	elseif typeof(target) == "number" then
		local player = Players:GetPlayerByUserId(target)
		return if player then { player } else {}
	end
	return {}
end

-- Runs `undo` after `seconds`, unless a newer timer of the same kind on the
-- same character replaced it (or it was cancelled)
function OwnerService:_timed(model: Model, kind: string, seconds: number, undo: () -> ())
	timerCount += 1
	local token = timerCount
	model:SetAttribute(TIMER_PREFIX .. kind, token)
	task.delay(seconds, function()
		if model:GetAttribute(TIMER_PREFIX .. kind) == token then
			model:SetAttribute(TIMER_PREFIX .. kind, nil)
			pcall(undo)
		end
	end)
end

function OwnerService:_cancelTimer(model: Model, kind: string)
	model:SetAttribute(TIMER_PREFIX .. kind, nil)
end

function OwnerService:_playerAction(owner: Player, target: any, actionId: string)
	local players = targetsOf(owner, target)
	local ownerFighter = self.characters:getByPlayer(owner)

	if actionId == "GoTo" then
		local destination = players[1]
		local fighter = destination and self.characters:getByPlayer(destination)
		if fighter and ownerFighter and destination ~= owner and self.characters:isAlive(fighter) then
			self.characters:teleport(ownerFighter, fighter.root.CFrame * CFrame.new(0, 0, 5))
		end
		return
	end

	for index, player in players do
		local fighter = self.characters:getByPlayer(player)
		local alive = fighter ~= nil and self.characters:isAlive(fighter)

		if actionId == "Kick" or actionId == "Ban" then
			if player ~= owner and not self:isOwner(player) then
				if actionId == "Ban" then
					bannedIds[player.UserId] = true
				end
				player:Kick(if actionId == "Ban" then "You were banned from this server by the owner." else "You were removed from this server by the owner.")
			end
		elseif AURAS[actionId] then
			player:SetAttribute(Attribute.Aura, AURAS[actionId])
		elseif actionId == "AuraNone" then
			player:SetAttribute(Attribute.Aura, nil)
		elseif fighter and alive then
			self:_fighterAction(owner, ownerFighter, fighter, actionId, index, #players)
		end
	end
end

function OwnerService:_fighterAction(owner: Player, ownerFighter, fighter, actionId: string, index: number, count: number)
	local humanoid = fighter.humanoid
	local model = fighter.model
	local root = fighter.root

	if actionId == "Heal" then
		humanoid.Health = humanoid.MaxHealth
	elseif actionId == "KnockOut" then
		humanoid.Health = 0
	elseif actionId == "Fling" then
		local angle = math.random() * math.pi * 2
		self.damage:push(fighter, Vector3.new(math.cos(angle), 0, math.sin(angle)), Settings.FlingSpeed, Settings.FlingLift, 0.35)
	elseif actionId == "Freeze" then
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = true
		model:SetAttribute(Attribute.Iced, true)
		self:_timed(model, "Freeze", Settings.FreezeTime, function()
			if root.Parent then
				root.Anchored = false
			end
			if model.Parent then
				model:SetAttribute(Attribute.Iced, nil)
			end
		end)
	elseif actionId == "Bring" then
		if ownerFighter and fighter ~= ownerFighter and self.characters:isAlive(ownerFighter) then
			-- Spread several players in a semicircle in front of the owner
			local spread = if count > 1 then (index / count - 0.5) * math.pi else 0
			local offset = CFrame.Angles(0, spread, 0) * CFrame.new(0, 0, -6)
			local destination = ownerFighter.root.CFrame * offset
			self.characters:teleport(fighter, CFrame.lookAt(destination.Position, ownerFighter.root.Position))
		end
	elseif actionId == "Giant" or actionId == "Tiny" or actionId == "NormalSize" then
		local scale = if actionId == "Giant" then Settings.GiantScale elseif actionId == "Tiny" then Settings.TinyScale else 1
		pcall(model.ScaleTo, model, scale)
		if scale ~= 1 then
			self:_timed(model, "Size", Settings.SizeTime, function()
				if model.Parent then
					model:ScaleTo(1)
				end
			end)
		else
			self:_cancelTimer(model, "Size")
		end
	elseif actionId == "Speed" then
		fighter.moveBoost = Settings.SpeedMultiplier
		self.characters:refresh(fighter)
		self:_timed(model, "Speed", Settings.SpeedTime, function()
			fighter.moveBoost = 1
			self.characters:refresh(fighter)
		end)
	end
end

-- The owner's own toggles ------------------------------------------------------------

function OwnerService:_selfToggle(owner: Player, toggle: string, on: boolean)
	if toggle == "Fly" then
		owner:SetAttribute(Attribute.CanFly, if on then true else nil)
	elseif toggle == "Immune" then
		owner:SetAttribute(Attribute.Immune, if on then true else nil)
	elseif toggle == "Crown" then
		owner:SetAttribute(Attribute.Crown, on)
	elseif toggle == "Invisible" then
		owner:SetAttribute(Attribute.Invisible, if on then true else nil)
		local fighter = self.characters:getByPlayer(owner)
		if fighter then
			self:_setInvisible(fighter.model, on)
		end
	end
end

function OwnerService:_setInvisible(model: Model, on: boolean)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") or item:IsA("Decal") then
			local saved = item:GetAttribute(HIDDEN_ATTRIBUTE)
			if on then
				if saved == nil then
					item:SetAttribute(HIDDEN_ATTRIBUTE, item.Transparency)
				end
				item.Transparency = 1
			elseif typeof(saved) == "number" then
				item.Transparency = saved
				item:SetAttribute(HIDDEN_ATTRIBUTE, nil)
			end
		end
	end
end

-- Announcements go through Roblox's text filter like any other player text
function OwnerService:_announce(owner: Player, text: string)
	text = string.sub(string.gsub(text, "^%s+", ""), 1, MAX_ANNOUNCEMENT)
	if text == "" then
		return
	end
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(text, owner.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		self:_notify(owner, "Couldn't send that announcement (text filter unavailable). Try again.")
		return
	end
	AdminEvent:FireAllClients(Signal.Announce, { text = filtered, from = owner.DisplayName })
end

return OwnerService
