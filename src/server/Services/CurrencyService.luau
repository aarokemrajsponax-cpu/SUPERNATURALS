-- Money and Gems. Every balance change in the game goes through here: amounts
-- must be whole, finite and non-negative, spending checks and deducts in one
-- step (so a price can never be paid twice or overdrawn), and balances are
-- capped. Clients never send amounts; services decide them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Schema = require(ReplicatedStorage.Shared.Data.Schema)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local Config = Schema.Config

local CurrencyService = {}

export type Amounts = { money: number?, gems: number? }
export type Options = {
	-- true for an automatic message ("+450 Gems"), or the text to show
	toast: (boolean | string)?,
}

local KINDS = { "money", "gems" }
local LABELS = { money = "Money", gems = "Gems" }

-- "12,500"
local function formatNumber(value: number): string
	local text = tostring(math.floor(value))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return (string.gsub(formatted, "^(-?),", "%1"))
end

-- "1,200 Money and 5 Gems"
local function describe(amounts: { [string]: number }): string
	local parts = {}
	for _, kind in KINDS do
		if amounts[kind] > 0 then
			table.insert(parts, `{formatNumber(amounts[kind])} {LABELS[kind]}`)
		end
	end
	return table.concat(parts, " and ")
end

-- { money, gems } with both filled in, or nil when the table has unknown keys
-- or an amount that isn't a whole number from 0 to the cap
local function clean(amounts: any): { [string]: number }?
	if typeof(amounts) ~= "table" then
		return nil
	end
	local result = { money = 0, gems = 0 }
	for key, value in amounts do
		if result[key] == nil then
			return nil
		end
		if typeof(value) ~= "number" or value ~= value or value < 0 or value > Config.MaxCurrency or value ~= math.floor(value) then
			return nil
		end
		result[key] = value
	end
	return result
end

local function reasonText(reason: any): string
	return if typeof(reason) == "string" and reason ~= "" then reason else "unknown"
end

function CurrencyService:Init(services)
	self.data = services.DataService
end

function CurrencyService:_toast(player: Player, option: (boolean | string)?, automatic: string, kind: string)
	if not option or not player.Parent then
		return
	end
	local text = if typeof(option) == "string" then option else automatic
	DataEvent:FireClient(player, Protocol.DataEvent.Toast, { text = text, kind = kind })
end

-- The player's balance of "money" or "gems" (0 before their profile loads)
function CurrencyService:balance(player: Player, kind: string): number
	local profile = self.data:get(player)
	if not profile or not LABELS[kind] then
		return 0
	end
	return profile.currencies[kind] or 0
end

-- Whether the player can pay `price` ({ money?, gems? }); false for invalid prices
function CurrencyService:canAfford(player: Player, price: Amounts): boolean
	local amounts = clean(price)
	local profile = self.data:get(player)
	if not amounts or not profile then
		return false
	end
	for _, kind in KINDS do
		if (profile.currencies[kind] or 0) < amounts[kind] then
			return false
		end
	end
	return true
end

-- Takes `price` from the player's balances if they can pay all of it.
-- Returns true when paid; nothing changes otherwise.
function CurrencyService:spend(player: Player, price: Amounts, reason: string, opts: Options?): boolean
	local amounts = clean(price)
	if not amounts then
		warn(`[Currency] refused an invalid price for {player.Name} ({reasonText(reason)})`)
		return false
	end
	if not self:canAfford(player, amounts) then
		return false
	end
	local paid = false
	self.data:update(player, function(profile)
		-- Checked again inside the change, which can't be interrupted
		for _, kind in KINDS do
			if profile.currencies[kind] < amounts[kind] then
				return
			end
		end
		for _, kind in KINDS do
			profile.currencies[kind] -= amounts[kind]
		end
		paid = true
	end)
	if paid then
		local spent = describe(amounts)
		if spent ~= "" then
			self:_toast(player, opts and opts.toast, `Spent {spent}`, "info")
		end
	end
	return paid
end

-- Gives the player `amounts` ({ money?, gems? }). Balances stop at the cap.
-- Returns false for invalid amounts or a profile that isn't loaded.
function CurrencyService:add(player: Player, amounts: Amounts, reason: string, opts: Options?): boolean
	local grant = clean(amounts)
	if not grant then
		warn(`[Currency] refused an invalid grant for {player.Name} ({reasonText(reason)})`)
		return false
	end
	local added = self.data:update(player, function(profile)
		for _, kind in KINDS do
			profile.currencies[kind] = math.min(Config.MaxCurrency, profile.currencies[kind] + grant[kind])
		end
	end)
	if not added then
		return false
	end
	for _, kind in KINDS do
		if grant[kind] >= Config.BigGrant[kind] then
			print(`[Currency] {player.Name} ({player.UserId}) received {formatNumber(grant[kind])} {kind}: {reasonText(reason)}`)
		end
	end
	local text = describe(grant)
	if text ~= "" then
		self:_toast(player, opts and opts.toast, `+{text}`, "reward")
	end
	return true
end

-- "1,200 Money and 5 Gems", for messages
function CurrencyService.describe(amounts: Amounts): string
	local amountsClean = clean(amounts)
	return if amountsClean then describe(amountsClean) else ""
end

return CurrencyService
