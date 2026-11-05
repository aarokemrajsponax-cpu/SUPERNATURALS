-- The Lounge refreshments counter (P.S. 13.0 section 3, DECISIONS 23, Config/Refreshments).
-- Drinks and snacks cost earned Money only (never Robux, never Gems). Each gives a harmless look for a
-- few minutes (a soft glow, a spark trail, a one-line emote) and, for some, a small boost to Money and
-- experience from matches in casual modes (Free-for-All, CPU Practice). Nothing here applies in Duel,
-- ranked-style play, or to any combat stat, and nothing is kept: effects end on their own.
--
-- Server rules: the item must exist, the player must be past the cooldown, the same item cannot be
-- bought while it is running, only one effect runs at a time (a new one replaces the old; nothing
-- stacks), and the price is taken with CurrencyService before anything is given.
-- Requests: Remotes.LoungeRequest (RefreshmentsState, BuyRefreshment). Replies: DataEvent Lounge.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Refreshments)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local RateLimiter = require(ReplicatedStorage.Shared.Utility.RateLimiter)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local RefreshmentService = {}

local limiter = RateLimiter.new(2, 5)
-- [player] = { item, endsAt, token }
local active: { [Player]: any } = {}
local lastBuy: { [Player]: number } = {}

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function toast(player: Player, text: string, kind: string)
	if player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Toast, { text = text, kind = kind })
	end
end

function RefreshmentService:Init(services)
	self.services = services
	self.data = services.DataService
	self.currency = services.CurrencyService
	-- Seconds for cooldowns and effects (replaceable in tests)
	self.clock = os.clock
end

function RefreshmentService:Start()
	local progression = self.services.ProgressionService
	if progression then
		progression:addRewardModifier(function(player: Player, match: any)
			local boost = self:boostFor(player, match and match.modeName)
			if boost > 0 then
				return 1 + boost, "Refreshment"
			end
			return nil, nil
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		active[player] = nil
		lastBuy[player] = nil
		RateLimiter.forget(limiter, player)
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local effect = active[player]
			if effect and effect.endsAt > self.clock() then
				task.defer(function()
					self:_dress(player, character, effect.item)
				end)
			end
		end)
	end)
	local request = Remotes:FindFirstChild("LoungeRequest")
	if request then
		request.OnServerEvent:Connect(function(player, action, itemId)
			if action ~= Protocol.LoungeAction.RefreshmentsState and action ~= Protocol.LoungeAction.BuyRefreshment then
				return
			end
			if not RateLimiter.allow(limiter, player, os.clock()) then
				return
			end
			if action == Protocol.LoungeAction.RefreshmentsState then
				self:_send(player)
			else
				self:buy(player, itemId)
			end
		end)
	end
end

-- The running effect, if it has not ended
function RefreshmentService:current(player: Player): any?
	local effect = active[player]
	if effect and effect.endsAt > self.clock() then
		return effect
	end
	active[player] = nil
	return nil
end

-- The fraction added to this match's Money and experience: 0 in Duel and any mode not on the list,
-- and never more than Config.MaxBoost
function RefreshmentService:boostFor(player: Player, modeName: any): number
	if typeof(modeName) ~= "string" or not Config.BoostModes[modeName] then
		return 0
	end
	local effect = self:current(player)
	if not effect then
		return 0
	end
	return math.clamp(effect.item.boost, 0, Config.MaxBoost)
end

function RefreshmentService:state(player: Player): any
	local effect = self:current(player)
	local now = self.clock()
	local last = lastBuy[player]
	return {
		kind = "Refreshments",
		cooldownLeft = if last then math.max(0, math.ceil(Config.Cooldown - (now - last))) else 0,
		active = if effect then { id = effect.item.id, name = effect.item.name, left = math.max(1, math.ceil(effect.endsAt - now)), boost = effect.item.boost } else nil,
	}
end

function RefreshmentService:_send(player: Player)
	if player.Parent and self.data:get(player) then
		DataEvent:FireClient(player, Protocol.DataEvent.Lounge, self:state(player))
	end
end

-- Buys one item. Returns (ok, text).
function RefreshmentService:buy(player: Player, itemId: any): (boolean, string)
	local function reply(ok: boolean, text: string)
		toast(player, text, if ok then "success" else "info")
		if player.Parent then
			DataEvent:FireClient(player, Protocol.DataEvent.Lounge, { kind = "Bought", ok = ok, text = text })
		end
		self:_send(player)
		return ok, text
	end
	local item = Config.byId(itemId)
	if not item then
		return reply(false, "That is not on the menu.")
	end
	if not self.data:get(player) then
		return reply(false, "Your data is still loading.")
	end
	local now = self.clock()
	local last = lastBuy[player]
	if last and now - last < Config.Cooldown then
		return reply(false, `The counter needs a moment. Try again in {math.ceil(Config.Cooldown - (now - last))} seconds.`)
	end
	local effect = self:current(player)
	if effect and effect.item.id == item.id then
		return reply(false, `You already have the {item.name}. It fades on its own.`)
	end
	if not self.currency:spend(player, { money = item.price }, `Refreshment {item.id}`) then
		return reply(false, `You need {item.price} Money for the {item.name}.`)
	end
	lastBuy[player] = now
	local token = {}
	active[player] = { item = item, endsAt = now + math.min(item.seconds, Config.MaxSeconds), token = token }
	self.data:update(player, function(profile)
		profile.lounge.refreshments = math.min(1e9, profile.lounge.refreshments + 1)
	end)
	local character = player.Character
	if character then
		self:_dress(player, character, item)
	end
	task.delay(math.min(item.seconds, Config.MaxSeconds) + 0.5, function()
		local running = active[player]
		if running and running.token == token then
			active[player] = nil
			self:_undress(player.Character)
			if player.Parent then
				toast(player, `The {item.name} has worn off.`, "info")
				self:_send(player)
			end
		end
	end)
	local boostText = if item.boost > 0 then ` Casual matches pay {math.floor(item.boost * 100 + 0.5)}% more Money and experience while it lasts.` else ""
	return reply(true, `{item.name}: {item.emote}.{boostText}`)
end

-- Soft look on the character: a glow, a spark trail and a short line overhead. Looks only.
function RefreshmentService:_undress(character: Model?)
	if not character then
		return
	end
	local found = {}
	for _, child in character:GetDescendants() do
		if child:GetAttribute("RefreshmentFx") then
			table.insert(found, child)
		end
	end
	for _, child in found do
		pcall(child.Destroy, child)
	end
end

function RefreshmentService:_dress(player: Player, character: Model, item: any)
	self:_undress(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local glow = Instance.new("PointLight")
	glow.Color = rgb(item.glow)
	glow.Brightness = 0.8
	glow.Range = 10
	glow:SetAttribute("RefreshmentFx", true)
	glow.Parent = root
	local trail = Instance.new("ParticleEmitter")
	trail.Color = ColorSequence.new(rgb(item.sparkle))
	trail.Rate = 6
	trail.Lifetime = NumberRange.new(0.8, 1.4)
	trail.Speed = NumberRange.new(0.5, 1.5)
	trail.SpreadAngle = Vector2.new(180, 180)
	trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	trail.LightEmission = 0.7
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail:SetAttribute("RefreshmentFx", true)
	trail.Parent = root
	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromOffset(220, 28)
	label.StudsOffset = Vector3.new(0, 4.2, 0)
	label.AlwaysOnTop = false
	label:SetAttribute("RefreshmentFx", true)
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = item.emote
	text.TextSize = 16
	text.Font = Enum.Font.BuilderSansBold
	text.TextColor3 = rgb(item.sparkle)
	text.TextStrokeTransparency = 0.5
	text.Parent = label
	label.Parent = root
	task.delay(4, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

return RefreshmentService
