-- The Lounge wheel (DECISIONS 41, Config/Wheel). One free spin a day for everyone; optional paid spins
-- from the developer products LoungeSpin and LoungeSpin5 (PurchaseService adds the credits).
--
-- Rules this file keeps:
--   * The result is drawn here, on the server, with a Random seeded per server, from the same table the
--     wheel and the Wheel window show. It is saved to the profile before the client is told.
--   * A player Roblox marks as restricted for paid random items (PolicyService, checked in pcall; an error
--     counts as restricted) never gets paid spins: the products are refused and the state hides them.
--   * A cosmetic the player owns, a trial of a fighter they own or one that is not released yet is paid
--     as Config/Wheel.DuplicateMoney instead, and the reply says so.
--   * The spin credit (or the free day) and the prize are written in one change and saved together; a
--     failed save is rolled back and nothing is lost or given twice.
-- Requests: Remotes.LoungeRequest (WheelState, SpinFree, SpinPaid). Replies: DataEvent Lounge.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Wheel = require(ReplicatedStorage.Shared.Config.Wheel)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Schema = require(ReplicatedStorage.Shared.Data.Schema)
local RateLimiter = require(ReplicatedStorage.Shared.Utility.RateLimiter)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local WheelService = {}

local limiter = RateLimiter.new(2, 5)
local busy: { [Player]: boolean } = {}
-- Whether Roblox allows paid random items for a player: true = restricted. Unknown until asked.
local restricted: { [Player]: boolean } = {}
-- True only when Roblox answered successfully and said "restricted" (an error is not an answer)
local answeredRestricted: { [Player]: boolean } = {}
local settling: { [Player]: boolean } = {}
local asking: { [Player]: boolean } = {}

-- Seeded per server: the clock, this server's id and a coarse timer
local function seed(): number
	local total = 0
	for _, byte in { string.byte(tostring(game.JobId), 1, 32) } do
		total = (total * 31 + byte) % 2147483647
	end
	return (os.time() * 1000 + math.floor(os.clock() * 1000) + total) % 2147483647
end
WheelService.random = Random.new(seed())

local function toast(player: Player, text: string, kind: string)
	if player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Toast, { text = text, kind = kind })
	end
end

function WheelService:Init(services)
	self.services = services
	self.data = services.DataService
	self.currency = services.CurrencyService
	self.powers = services.PowerService
	self.cosmetics = services.CosmeticService
	self.antiExploit = services.AntiExploitService
	-- Replaceable in tests: returns Roblox's policy table for the player (may error)
	self.policy = function(player: Player): any
		return game:GetService("PolicyService"):GetPolicyInfoForPlayerAsync(player)
	end
	-- Now, as os.time() (replaceable in tests)
	self.clock = os.time
end

function WheelService:Start()
	self.data:onLoaded(function(player)
		self:_askPolicy(player)
		self:_settle(player)
		self:_send(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		restricted[player] = nil
		answeredRestricted[player] = nil
		settling[player] = nil
		asking[player] = nil
		RateLimiter.forget(limiter, player)
	end)
	local request = Remotes:FindFirstChild("LoungeRequest")
	if request then
		request.OnServerEvent:Connect(function(player, action)
			if action ~= Protocol.LoungeAction.WheelState and action ~= Protocol.LoungeAction.SpinFree and action ~= Protocol.LoungeAction.SpinPaid then
				return
			end
			if not RateLimiter.allow(limiter, player, os.clock()) then
				return
			end
			if action == Protocol.LoungeAction.WheelState then
				self:_send(player)
			elseif action == Protocol.LoungeAction.SpinFree then
				self:spin(player, "free")
			else
				self:spin(player, "paid")
			end
		end)
	end
end

-- Roblox's answer, in pcall. Anything but an explicit "not restricted" counts as restricted.
function WheelService:_askPolicy(player: Player)
	if restricted[player] ~= nil or asking[player] then
		return
	end
	asking[player] = true
	local ok, info = pcall(self.policy, player)
	asking[player] = nil
	if not player.Parent then
		return
	end
	restricted[player] = not (ok and typeof(info) == "table" and info.ArePaidRandomItemsRestricted == false)
	answeredRestricted[player] = ok and typeof(info) == "table" and info.ArePaidRandomItemsRestricted == true
end

-- A player Roblox has said is restricted (a real answer, not an error) cannot use paid spins, so each held
-- credit is exchanged for Wheel.CreditGems Gems. The exchange is saved first, then the player is told. When
-- the policy call only errored the credits are kept and the paid controls are simply hidden.
function WheelService:_settle(player: Player)
	if not answeredRestricted[player] or settling[player] then
		return
	end
	local profile = self.data:get(player)
	if not profile or profile.wheel.credits < 1 or not self.data:isPersistent(player) then
		return
	end
	settling[player] = true
	local count = profile.wheel.credits
	local gems = count * Wheel.CreditGems
	local backup = { credits = count, gems = profile.currencies.gems }
	self.data:update(player, function(p)
		p.wheel.credits = 0
		p.currencies.gems = math.min(Schema.Config.MaxCurrency, p.currencies.gems + gems)
	end)
	if self.data:saveNow(player) then
		pcall(function()
			self.currency:_analytics(player, "Source", { money = 0, gems = gems }, "Wheel credits exchanged")
		end)
		toast(player, `Wheel spins can't be used where you play, so your {count} {if count == 1 then "spin was" else "spins were"} exchanged for {gems} Gems.`, "info")
	else
		self.data:update(player, function(p)
			p.wheel.credits = backup.credits
			p.currencies.gems = backup.gems
		end)
		warn(`[Wheel] exchanging {count} spins for {player.Name} could not be saved and was undone`)
	end
	settling[player] = nil
	self:_send(player)
end

-- May this player see and buy paid spins? False until Roblox has said yes.
function WheelService:paidAllowed(player: Player): boolean
	if restricted[player] == nil then
		self:_askPolicy(player)
	end
	return restricted[player] == false
end

-- May a spin product be sold to this player right now? (PurchaseService asks before opening Roblox's prompt)
function WheelService:canSellSpins(player: Player, count: number): (boolean, string?)
	if not self:paidAllowed(player) then
		return false, "Paid spins are not available for your account. Your free daily spin still is."
	end
	local profile = self.data:get(player)
	if not profile then
		return false, "Your data is still loading."
	end
	if profile.wheel.credits + count > Wheel.MaxCredits then
		return false, `You already hold {profile.wheel.credits} spins. Use some before buying more.`
	end
	return true, nil
end

-- Adds spin credits inside a profile change (PurchaseService, inside its receipt change)
function WheelService.addCredits(profile, count: number)
	profile.wheel.credits = math.min(Wheel.MaxCredits, profile.wheel.credits + count)
end

function WheelService:onCreditsChanged(player: Player)
	self:_settle(player)
	self:_send(player)
end

-- Has the player used today's free spin?
function WheelService:freeReady(profile): boolean
	return profile.wheel.freeDay ~= Wheel.dayOf(self.clock())
end

function WheelService:state(player: Player): any?
	local profile = self.data:get(player)
	if not profile then
		return nil
	end
	local allowed = self:paidAllowed(player)
	local products = {}
	if allowed then
		for _, key in { "LoungeSpin", "LoungeSpin5" } do
			local product = Monetization.Products[key]
			products[key] = { spins = product.wheelSpins, onSale = typeof(product.id) == "number" and product.id > 0 }
		end
	end
	return {
		kind = "Wheel",
		freeReady = self:freeReady(profile),
		paidAllowed = allowed,
		credits = if allowed then profile.wheel.credits else 0,
		spins = profile.wheel.spins,
		last = table.clone(profile.wheel.last),
		products = products,
	}
end

function WheelService:_send(player: Player)
	local state = self:state(player)
	if state and player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Lounge, state)
	end
end

-- Works out what the prize really is for this player: the prize itself, or Money in its place
function WheelService:_resolve(player: Player, profile, prize)
	local converted = false
	local reason = ""
	if prize.kind == "cosmetic" then
		if profile.cosmetics.owned[prize.cosmetic] == true then
			converted, reason = true, "You already own it"
		end
	elseif prize.kind == "trial" then
		if not Powers.isReleased(prize.power) then
			converted, reason = true, "That fighter is not out yet"
		elseif self.powers and self.powers:_ownsOutright(player, prize.power) then
			converted, reason = true, "You already own that fighter"
		end
	end
	return converted, reason
end

-- Draws one result. kind: "free" or "paid". Returns (ok, reply) where reply is what the client gets.
function WheelService:spin(player: Player, kind: string): (boolean, any)
	local function refuse(text: string)
		toast(player, text, "info")
		DataEvent:FireClient(player, Protocol.DataEvent.Lounge, { kind = "Spin", ok = false, text = text, wheel = self:state(player) })
		return false, text
	end
	if busy[player] then
		return false, "busy"
	end
	local profile = self.data:get(player)
	if not profile then
		return refuse("Your data is still loading.")
	end
	if not self.data:isPersistent(player) then
		return refuse("Spins are paused while saving is off. Rejoin to spin.")
	end
	busy[player] = true
	local ok, ranOk, reply = pcall(function()
		return self:_spin(player, profile, kind)
	end)
	busy[player] = nil
	if not ok then
		warn(`[Wheel] a spin for {player.Name} failed: {ranOk}`)
		return refuse("The wheel could not be used just now. Nothing was spent.")
	end
	if not ranOk then
		return refuse(reply)
	end
	return true, reply
end

function WheelService:_spin(player: Player, profile, kind: string): (boolean, any)
	local today = Wheel.dayOf(self.clock())
	if kind == "free" then
		if profile.wheel.freeDay == today then
			return false, "You have used today's free spin. A new one is ready tomorrow."
		end
	else
		if not self:paidAllowed(player) then
			return false, "Paid spins are not available for your account."
		end
		if profile.wheel.credits < 1 then
			return false, "You have no paid spins."
		end
	end

	-- The draw: the roll is made once, before anything is shown
	local roll = self.random:NextNumber() * 100
	local prize, index = Wheel.pick(roll)
	local converted, reason = self:_resolve(player, profile, prize)
	local money, gems = 0, 0
	if converted then
		money = Wheel.DuplicateMoney
	elseif prize.kind == "money" then
		money = prize.amount
	elseif prize.kind == "gems" then
		gems = prize.amount
	end

	local backup = {
		wheel = Schema.copy(profile.wheel),
		currencies = Schema.copy(profile.currencies),
		trials = Schema.copy(profile.trials),
		owned = Schema.copy(profile.cosmetics.owned),
		equipped = Schema.copy(profile.cosmetics.equipped),
	}
	local item = if prize.kind == "cosmetic" and not converted then Cosmetics.get(prize.cosmetic) else nil
	local function restore(p)
		p.wheel = Schema.copy(backup.wheel)
		p.currencies = Schema.copy(backup.currencies)
		p.trials = Schema.copy(backup.trials)
		p.cosmetics.owned = Schema.copy(backup.owned)
		p.cosmetics.equipped = Schema.copy(backup.equipped)
	end

	local applied = self.data:update(player, function(p)
		if kind == "free" then
			p.wheel.freeDay = today
		else
			p.wheel.credits -= 1
		end
		p.wheel.spins = math.min(1e9, p.wheel.spins + 1)
		table.insert(p.wheel.last, 1, prize.id)
		while #p.wheel.last > Wheel.HistoryKept do
			table.remove(p.wheel.last)
		end
		p.currencies.money = math.min(Schema.Config.MaxCurrency, p.currencies.money + money)
		p.currencies.gems = math.min(Schema.Config.MaxCurrency, p.currencies.gems + gems)
		if prize.kind == "trial" and not converted then
			self.powers.applyTrial(p, prize.power, prize.hours, os.time())
		elseif item then
			p.cosmetics.owned[prize.cosmetic] = true
			if p.cosmetics.equipped[item.kind] == nil then
				p.cosmetics.equipped[item.kind] = prize.cosmetic
			end
		end
	end)
	if not applied then
		return false, "Your data is still loading."
	end
	if not self.data:saveNow(player) then
		self.data:update(player, restore)
		warn(`[Wheel] a spin for {player.Name} could not be saved and was undone`)
		return false, "The spin could not be saved, so nothing was spent. Please try again."
	end

	-- Saved: now it is real. Tell the other systems, then the player.
	if money > 0 or gems > 0 then
		pcall(function()
			self.currency:_analytics(player, "Source", { money = money, gems = gems }, `Wheel {prize.id}`)
		end)
	end
	if prize.kind == "trial" and not converted then
		self.powers:onTrialChanged(player, prize.power)
	elseif item then
		pcall(function()
			self.cosmetics:_mirror(player)
		end)
	end
	local text
	if converted then
		text = `{reason}, so you receive {Wheel.DuplicateMoney} Money instead.`
	elseif prize.kind == "money" then
		text = `You won {prize.label}.`
	elseif prize.kind == "gems" then
		text = `You won {prize.label}.`
	elseif prize.kind == "trial" then
		text = `You won a {prize.label}. It starts now.`
	else
		text = `You won the {prize.label}.`
	end
	local reply = {
		kind = "Spin",
		ok = true,
		index = index,
		prizeId = prize.id,
		text = text,
		converted = converted,
		source = kind,
		wheel = self:state(player),
	}
	self:_animateWorld(index)
	if player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Lounge, reply)
	end
	return true, reply
end

-- Turns the physical wheel in the lounge to the drawn segment. The disc is one part; the landing spot
-- is somewhere inside the drawn segment, never on an edge, so nothing about it can look like a near miss.
function WheelService:_animateWorld(index: number)
	local lounge = self.services.LoungeService
	local built = lounge and lounge:getBuilt()
	local disc = built and built.wheelDisc
	if not disc or not disc.Parent then
		return
	end
	local count = #Wheel.Prizes
	local width = 360 / count
	local offset = (self.random:NextNumber() - 0.5) * width * 0.6
	-- Segment i is centred (i - 0.5) * width clockwise from the top as seen from the front; the pointer
	-- is at the top. Turning the disc counter-clockwise by that angle brings the segment to the pointer.
	local landing = (index - 0.5) * width + offset
	local previous = disc:GetAttribute("Angle") or 0
	local target = previous + 4 * 360 + ((landing - previous) % 360)
	disc:SetAttribute("Angle", target)
	local goal = built.wheelBase * CFrame.Angles(math.rad(target), 0, 0)
	local ok = pcall(function()
		TweenService:Create(disc, TweenInfo.new(5.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { CFrame = goal }):Play()
	end)
	if not ok then
		disc.CFrame = goal
	end
end

return WheelService
