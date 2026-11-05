-- Cosmetics: the one place that gives, checks and shows titles, nameplate styles, auras and
-- knockout effects (registry: Shared/Config/Cosmetics). Looks only, never stats.
--
--   CosmeticService:grant(player, id, source): boolean   unknown id or already owned -> false
--   CosmeticService:owns(player, id): boolean
--   CosmeticService:equip(player, slot, id): (boolean, string?)   id "" takes the slot's item off
--   CosmeticService:onGranted(callback(player, id, source))
--
-- What a player wears is mirrored onto the Player as attributes (Protocol.Attribute.Title,
-- Plate, CosmeticAura, Knockout) so nameplates and effects can read it on every client.
-- Players who join before Cosmetics.FounderUntil get the Founding Recruit title once,
-- whatever they think of the game.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local RateLimiter = require(ReplicatedStorage.Shared.Utility.RateLimiter)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local Attribute = Protocol.Attribute

local CosmeticService = {}

local KIND_LABEL = {
	title = "New title",
	plate = "New nameplate style",
	aura = "New aura",
	knockout = "New knockout effect",
}

local SLOT_ATTRIBUTE = {
	title = Attribute.Title,
	plate = Attribute.Plate,
	aura = Attribute.CosmeticAura,
	knockout = Attribute.Knockout,
}

local limiter = RateLimiter.new(2, 5)
local grantedCallbacks: { (Player, string, string) -> () } = {}

function CosmeticService:Init(services)
	self.services = services
	self.data = services.DataService
end

function CosmeticService:Start()
	self.data:onLoaded(function(player, profile)
		self:_founding(player, profile)
		self:_mirror(player)
	end)
	self.data:onChanged(function(player)
		self:_mirror(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		RateLimiter.forget(limiter, player)
	end)
	local request = Remotes:FindFirstChild("CosmeticRequest")
	if request then
		request.OnServerEvent:Connect(function(player, action, slot, id)
			self:_onRequest(player, action, slot, id)
		end)
	end
end

local function toast(player: Player, text: string, kind: string)
	if player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Toast, { text = text, kind = kind })
	end
end

-- Public API -----------------------------------------------------------------------------------

function CosmeticService:owns(player: Player, id: string): boolean
	local profile = self.data:get(player)
	return profile ~= nil and typeof(id) == "string" and profile.cosmetics.owned[id] == true
end

-- Gives a cosmetic. `source` is only for logs and listeners ("achievement", "referral"...).
-- Returns true only when this call added it.
function CosmeticService:grant(player: Player, id: string, source: string?): boolean
	local item = Cosmetics.get(id)
	if not item or not self.data:get(player) then
		return false
	end
	local added = false
	local ok = self.data:update(player, function(profile)
		if profile.cosmetics.owned[id] == true then
			return
		end
		profile.cosmetics.owned[id] = true
		-- An empty slot wears its first item, so a new title shows at once. The founder title is
		-- the exception: the tour's Recruit title is the first one a new player wears.
		if profile.cosmetics.equipped[item.kind] == nil and source ~= "founder" then
			profile.cosmetics.equipped[item.kind] = id
		end
		added = true
	end)
	if not (ok and added) then
		return false
	end
	self:_mirror(player)
	toast(player, `{KIND_LABEL[item.kind] or "New item"}: {item.name}`, "reward")
	for _, callback in grantedCallbacks do
		task.spawn(function()
			local fine, err = pcall(callback, player, id, source or "")
			if not fine then
				warn("[Cosmetic] a grant listener failed: " .. tostring(err))
			end
		end)
	end
	return true
end

-- Wears an owned item in its slot, or takes the slot's item off with "". Returns (ok, reason).
function CosmeticService:equip(player: Player, slot: any, id: any): (boolean, string?)
	if typeof(slot) ~= "string" or not table.find(Cosmetics.Slots, slot) then
		return false, "Unknown slot."
	end
	if typeof(id) ~= "string" or #id > 48 then
		return false, "Unknown item."
	end
	local profile = self.data:get(player)
	if not profile then
		return false, "Your data is still loading."
	end
	if id ~= "" then
		if not Cosmetics.fits(slot, id) then
			return false, "That item does not go there."
		end
		if profile.cosmetics.owned[id] ~= true then
			return false, "You do not own that yet."
		end
	end
	local ok = self.data:update(player, function(saved)
		if id == "" then
			saved.cosmetics.equipped[slot] = nil
		else
			saved.cosmetics.equipped[slot] = id
		end
	end)
	if not ok then
		return false, "Could not save that."
	end
	self:_mirror(player)
	return true, nil
end

function CosmeticService:onGranted(callback: (Player, string, string) -> ())
	table.insert(grantedCallbacks, callback)
end

-- Internals ------------------------------------------------------------------------------------

function CosmeticService:_onRequest(player: Player, action: any, slot: any, id: any)
	if action ~= Protocol.CosmeticAction.Equip then
		return
	end
	if not RateLimiter.allow(limiter, player, os.clock()) then
		return
	end
	local ok, reason = self:equip(player, slot, id)
	if not ok and reason then
		toast(player, reason, "error")
	end
end

-- Founding Recruit: once, for accounts first seen before the cutoff
function CosmeticService:_founding(player: Player, profile)
	if profile.cosmetics.owned.title_founding == true or os.time() > Cosmetics.FounderUntil then
		return
	end
	if profile.meta.sessions > 1 then
		return
	end
	self:grant(player, "title_founding", "founder")
end

-- Copies what the player wears onto their Player attributes (only changed ones are written)
function CosmeticService:_mirror(player: Player)
	local profile = self.data:get(player)
	if not profile or player.Parent == nil then
		return
	end
	for _, slot in Cosmetics.Slots do
		local id = profile.cosmetics.equipped[slot]
		local item = if typeof(id) == "string" and profile.cosmetics.owned[id] == true and Cosmetics.fits(slot, id) then Cosmetics.get(id) else nil
		local value = ""
		if item then
			value = if slot == "title" then (item.text or item.name) else item.id
		end
		if player:GetAttribute(SLOT_ATTRIBUTE[slot]) ~= value then
			player:SetAttribute(SLOT_ATTRIBUTE[slot], value)
		end
	end
end

return CosmeticService
