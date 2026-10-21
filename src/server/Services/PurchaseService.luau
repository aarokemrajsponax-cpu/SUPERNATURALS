-- Robux purchases through Roblox's own purchase flow: game passes (premium
-- powers) and developer products (gem packs). Nothing is granted because a
-- client asked; passes come from Roblox's ownership check or its purchase
-- event, products only from ProcessReceipt. Receipts are idempotent: each
-- PurchaseId is granted once, and only reported as granted after the grant
-- is saved, so Roblox retries anything that didn't stick.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Schema = require(ReplicatedStorage.Shared.Data.Schema)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local Decision = Enum.ProductPurchaseDecision

local PurchaseService = {}

-- What Roblox said about each player's passes (only passes it answered for)
local ownership: { [number]: { [string]: boolean } } = {}
local lastPrompt: { [number]: number } = {}
-- PurchaseIds being granted right now, so a second call for one waits its turn
local processing: { [string]: boolean } = {}
local grantedCallbacks: { (Player, string) -> () } = {}
local passById: { [number]: string } = {}
local productById: { [number]: string } = {}

local function toast(player: Player, text: string, kind: string)
	if player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Toast, { text = text, kind = kind })
	end
end

local function validId(id: any): boolean
	return typeof(id) == "number" and id > 0 and id == math.floor(id)
end

-- Calls fn, retrying with a doubling wait; returns (true, result) or (false, error)
local function retry(attempts: number, fn: () -> any): (boolean, any)
	local ok, result = false, nil
	for attempt = 1, attempts do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt < attempts then
			task.wait(Schema.Config.RetryBaseDelay * 2 ^ (attempt - 1))
		end
	end
	return false, result
end

function PurchaseService:Init(services)
	self.data = services.DataService
	self.currency = services.CurrencyService
	for key, pass in Monetization.Passes do
		if validId(pass.id) then
			if passById[pass.id] then
				warn(`[Purchase] passes {passById[pass.id]} and {key} share the id {pass.id}`)
			end
			passById[pass.id] = key
		end
	end
	for key, product in Monetization.Products do
		if validId(product.id) then
			if productById[product.id] then
				warn(`[Purchase] products {productById[product.id]} and {key} share the id {product.id}`)
			end
			productById[product.id] = key
		end
	end
end

function PurchaseService:Start()
	MarketplaceService.ProcessReceipt = function(receipt)
		return self:_processReceipt(receipt)
	end

	-- Fired by Roblox on the server when a pass purchase window closes
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		local key = passById[passId]
		if key and wasPurchased == true then
			self:_recordPass(player, key)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		self:_checkPasses(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(self._checkPasses, self, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		ownership[player.UserId] = nil
		lastPrompt[player.UserId] = nil
	end)

	task.spawn(self._checkPrices, self)
end

-- Warns when a price on the Creator Dashboard differs from Monetization, so
-- the shop never shows a different price than Roblox charges
function PurchaseService:_checkPrices()
	local function check(key: string, id: number, robux: number, infoType: Enum.InfoType)
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, infoType)
		end)
		if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" and info.PriceInRobux ~= robux then
			warn(`[Purchase] {key} costs {info.PriceInRobux} Robux on Roblox but Monetization says {robux}; make them match`)
		end
	end
	for key, pass in Monetization.Passes do
		if validId(pass.id) then
			check(key, pass.id, pass.robux, Enum.InfoType.GamePass)
		end
	end
	for key, product in Monetization.Products do
		if validId(product.id) then
			check(key, product.id, product.robux, Enum.InfoType.Product)
		end
	end
end

-- Asks Roblox which passes the player owns, then brings the profile's saved
-- copy in line. Passes Roblox can't answer for keep their saved value.
function PurchaseService:_checkPasses(player: Player)
	local answers = {}
	for key, pass in Monetization.Passes do
		if validId(pass.id) then
			local ok, owns = retry(Monetization.OwnershipCheckAttempts, function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok then
				answers[key] = owns == true
			else
				warn(`[Purchase] couldn't check {player.Name}'s {key} pass, using their saved ownership: {owns}`)
			end
		end
	end
	if player.Parent == nil then
		return
	end
	local known = ownership[player.UserId] or {}
	ownership[player.UserId] = known
	for key, owns in answers do
		-- A purchase in this session already counts, whatever the earlier check said
		if known[key] ~= true then
			known[key] = owns
		end
	end
	local profile = self.data:waitFor(player)
	if not profile then
		return
	end
	local gained = {}
	local changed = false
	for key, owns in answers do
		local saved = profile.passes[key] == true
		if known[key] and not saved then
			table.insert(gained, key)
			changed = true
		elseif not known[key] and saved then
			changed = true
		end
	end
	if changed then
		self.data:update(player, function(data)
			for key in answers do
				data.passes[key] = if known[key] then true else nil
			end
		end)
	end
	for _, key in gained do
		self:_firePassGranted(player, key)
	end
end

function PurchaseService:_firePassGranted(player: Player, passKey: string)
	for _, callback in grantedCallbacks do
		task.spawn(callback, player, passKey)
	end
end

-- Records a pass Roblox just sold the player
function PurchaseService:_recordPass(player: Player, passKey: string)
	local known = ownership[player.UserId] or {}
	ownership[player.UserId] = known
	known[passKey] = true
	local profile = self.data:get(player)
	local isNew = not (profile and profile.passes[passKey] == true)
	self.data:update(player, function(data)
		data.passes[passKey] = true
	end)
	if isNew then
		task.spawn(function()
			self.data:saveNow(player)
		end)
		self:_firePassGranted(player, passKey)
	end
	toast(player, `{Monetization.Passes[passKey].name} unlocked! Thank you for your support.`, "success")
end

-- Whether the purchase window may open again for this player (stops prompt spam)
function PurchaseService:_promptAllowed(player: Player): boolean
	local now = os.clock()
	local last = lastPrompt[player.UserId]
	if last and now - last < Monetization.PromptCooldown then
		return false
	end
	lastPrompt[player.UserId] = now
	return true
end

function PurchaseService:_processReceipt(receipt: any): Enum.ProductPurchaseDecision
	if typeof(receipt) ~= "table" or typeof(receipt.PurchaseId) ~= "string" or typeof(receipt.PlayerId) ~= "number" then
		warn("[Purchase] ignored a malformed receipt")
		return Decision.NotProcessedYet
	end
	local productKey = productById[receipt.ProductId]
	if not productKey then
		warn(`[Purchase] receipt {receipt.PurchaseId} is for unknown product {receipt.ProductId}; add its id to Monetization`)
		return Decision.NotProcessedYet
	end
	local purchaseId = receipt.PurchaseId
	if processing[purchaseId] then
		return Decision.NotProcessedYet
	end
	processing[purchaseId] = true
	local ok, result = pcall(self._grantReceipt, self, receipt, productKey)
	processing[purchaseId] = nil
	if not ok then
		warn(`[Purchase] receipt {purchaseId} failed: {result}`)
		return Decision.NotProcessedYet
	end
	return result
end

function PurchaseService:_grantReceipt(receipt: any, productKey: string): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		-- Roblox asks again when they're next in a server
		return Decision.NotProcessedYet
	end
	local profile = self.data:waitFor(player)
	if not profile or player.Parent == nil then
		return Decision.NotProcessedYet
	end
	local purchaseId = receipt.PurchaseId
	if table.find(profile.receipts, purchaseId) then
		return Decision.PurchaseGranted
	end
	if not self.data:isPersistent(player) then
		-- Never grant into progress that can't be saved; Roblox keeps the receipt
		toast(player, "Your purchase will arrive once saving works again. Try rejoining.", "info")
		return Decision.NotProcessedYet
	end

	local product = Monetization.Products[productKey]
	local amounts = { money = product.money, gems = product.gems }
	local before = {
		money = self.currency:balance(player, "money"),
		gems = self.currency:balance(player, "gems"),
	}
	if not self.currency:add(player, amounts, "Robux " .. productKey .. " " .. purchaseId) then
		return Decision.NotProcessedYet
	end
	-- What was really added (balances stop at the cap)
	local added = {
		money = self.currency:balance(player, "money") - before.money,
		gems = self.currency:balance(player, "gems") - before.gems,
	}
	self.data:update(player, function(data)
		table.insert(data.receipts, purchaseId)
		while #data.receipts > Schema.Config.MaxReceipts do
			table.remove(data.receipts, 1)
		end
	end)

	if self.data:saveNow(player) then
		toast(player, `{product.name}: +{self.currency.describe(amounts)}. Thank you for your purchase!`, "reward")
		return Decision.PurchaseGranted
	end

	-- Not saved: take the grant back so Roblox's retry can't give it twice
	self.data:update(player, function(data)
		data.currencies.money = math.max(0, data.currencies.money - added.money)
		data.currencies.gems = math.max(0, data.currencies.gems - added.gems)
		local index = table.find(data.receipts, purchaseId)
		if index then
			table.remove(data.receipts, index)
		end
	end)
	warn(`[Purchase] receipt {purchaseId} for {player.Name} couldn't be saved; Roblox will retry it`)
	return Decision.NotProcessedYet
end

-- Public API -----------------------------------------------------------------------------------

-- Whether the player owns a pass (by its key in Monetization.Passes). Uses
-- Roblox's answer when it gave one, otherwise the ownership saved in their profile.
function PurchaseService:ownsPass(player: Player, passKey: string): boolean
	if typeof(passKey) ~= "string" or not Monetization.Passes[passKey] then
		return false
	end
	local known = ownership[player.UserId]
	if known and known[passKey] ~= nil then
		return known[passKey]
	end
	local profile = self.data:get(player)
	return profile ~= nil and profile.passes[passKey] == true
end

-- Opens Roblox's purchase window for a pass. Returns true if it opened.
function PurchaseService:promptPass(player: Player, passKey: string): boolean
	local pass = if typeof(passKey) == "string" then Monetization.Passes[passKey] else nil
	if not pass then
		return false
	end
	if not validId(pass.id) then
		toast(player, Monetization.NotOnSaleText, "error")
		return false
	end
	if self:ownsPass(player, passKey) then
		toast(player, `You already own {pass.name}.`, "info")
		return false
	end
	if not self:_promptAllowed(player) then
		return false
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	end)
	if not ok then
		warn(`[Purchase] couldn't open the {passKey} purchase for {player.Name}: {err}`)
		toast(player, "The purchase window couldn't open. Please try again.", "error")
		return false
	end
	return true
end

-- Opens Roblox's purchase window for a developer product. Returns true if it opened.
function PurchaseService:promptProduct(player: Player, productKey: string): boolean
	local product = if typeof(productKey) == "string" then Monetization.Products[productKey] else nil
	if not product then
		return false
	end
	if not validId(product.id) then
		toast(player, Monetization.NotOnSaleText, "error")
		return false
	end
	if not self.data:isPersistent(player) then
		toast(player, "Purchases are paused while saving is off. Rejoin to buy.", "error")
		return false
	end
	if not self:_promptAllowed(player) then
		return false
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, product.id)
	end)
	if not ok then
		warn(`[Purchase] couldn't open the {productKey} purchase for {player.Name}: {err}`)
		toast(player, "The purchase window couldn't open. Please try again.", "error")
		return false
	end
	return true
end

-- The pass key that unlocks a power ("Corruption" -> "CorruptionPower"), if any
function PurchaseService:passForPower(powerId: string): string?
	return Monetization.passForPower(powerId)
end

-- callback(player, passKey) when the server learns a player owns a pass their
-- profile didn't have yet (bought in this server, or elsewhere since last time)
function PurchaseService:onPassGranted(callback: (Player, string) -> ())
	table.insert(grantedCallbacks, callback)
end

return PurchaseService
