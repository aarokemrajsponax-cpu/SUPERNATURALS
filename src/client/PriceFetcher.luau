-- Live Robux prices for the local player, straight from Roblox. Prices differ by region
-- (Managed Pricing), so nothing in the interface may hard-code a Robux amount: the shop asks
-- here, shows what comes back, and says "Price unavailable" when Roblox can't answer.
-- Results are cached for a short time and shared by every card that asks for the same item.
-- A state is { status, robux? } with status one of:
--   "soon"        the id is 0: the owner hasn't created this item yet (shown as "Available soon")
--   "loading"     asked, waiting for Roblox
--   "ready"       robux is the price this player pays
--   "unavailable" Roblox didn't answer, or the item isn't for sale (shown as "Price unavailable")

local MarketplaceService = game:GetService("MarketplaceService")

local PriceFetcher = {}

PriceFetcher.CacheSeconds = 120
PriceFetcher.FailureSeconds = 15

export type State = { status: string, robux: number? }

local cache: { [string]: { state: State, at: number, waiting: { (State) -> () } } } = {}

local function keyOf(kind: string, id: number): string
	return `{kind}:{id}`
end

local function infoType(kind: string): Enum.InfoType
	return if kind == "GamePass" then Enum.InfoType.GamePass else Enum.InfoType.Product
end

-- Reads the price of a "GamePass" or "Product" id. onChange(state) runs once the answer is
-- in (never when the state is already final). Returns the state right now.
function PriceFetcher.get(kind: string, id: any, onChange: ((State) -> ())?): State
	if typeof(id) ~= "number" or id <= 0 or id ~= math.floor(id) then
		return { status = "soon" }
	end
	local key = keyOf(kind, id)
	local entry = cache[key]
	local now = os.clock()
	if entry then
		local ttl = if entry.state.status == "unavailable" then PriceFetcher.FailureSeconds else PriceFetcher.CacheSeconds
		if entry.state.status == "loading" then
			if onChange then
				table.insert(entry.waiting, onChange)
			end
			return entry.state
		elseif now - entry.at < ttl then
			return entry.state
		end
	end
	local fresh = { state = { status = "loading" } :: State, at = now, waiting = {} :: { (State) -> () } }
	if onChange then
		table.insert(fresh.waiting, onChange)
	end
	cache[key] = fresh
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(id, infoType(kind))
		end)
		local price = if ok and typeof(info) == "table" and info.IsForSale ~= false then info.PriceInRobux else nil
		local result: State
		if typeof(price) == "number" and price > 0 and price == price then
			result = { status = "ready", robux = price }
		else
			result = { status = "unavailable" }
		end
		fresh.state = result
		fresh.at = os.clock()
		local waiting = fresh.waiting
		fresh.waiting = {}
		for _, callback in waiting do
			task.spawn(callback, result)
		end
	end)
	return fresh.state
end

-- Forgets what was learned so the next get asks Roblox again
function PriceFetcher.refresh(kind: string, id: number)
	cache[keyOf(kind, id)] = nil
end

function PriceFetcher.clear()
	table.clear(cache)
end

-- The text a card shows for a state; the only place a Robux amount becomes text
function PriceFetcher.describe(state: State): string
	if state.status == "ready" and state.robux then
		return "R$ " .. string.gsub(tostring(math.floor(state.robux)), "^(-?%d+)(%d%d%d)", "%1,%2")
	elseif state.status == "soon" then
		return "Available soon"
	elseif state.status == "loading" then
		return "Checking price"
	end
	return "Price unavailable"
end

return PriceFetcher
