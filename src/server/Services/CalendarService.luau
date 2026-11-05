-- Holiday login calendars (Config/Calendars). The server clock decides which calendar runs and
-- which day is today. A claim is checked (a calendar is running, the day exists, it is today or
-- within CatchUpDays, it was not claimed before), written to the profile and saved, and only
-- then are the rewards handed out: Money and Gems through CurrencyService, cosmetics through
-- CosmeticService, fighter trial tickets through PowerService. Attendance milestones and the
-- perfect prize are marked in the same save, so they are given once and never again.
--
--   CalendarService:state(player, now?)             what the window shows (also sent on join)
--   CalendarService:claim(player, day?, now?): (boolean, string?)   day defaults to today
--
-- Client requests: Remotes.ShopRequest with ShopAction.ClaimGift (day) and ShopAction.GiftState;
-- replies and state come back on DataEvent as Protocol.DataEvent.Calendar. Rate limited.
-- Nothing here is random or for sale, and no reward changes a stat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Calendars = require(ReplicatedStorage.Shared.Config.Calendars)
local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local RateLimiter = require(ReplicatedStorage.Shared.Utility.RateLimiter)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local CalendarService = {}

local limiter = RateLimiter.new(1, 4)
-- Players with a claim in progress (a claim waits for the save), so one cannot start twice
local busy: { [Player]: boolean } = {}

local function toast(player: Player, text: string, kind: string)
	if player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Toast, { text = text, kind = kind })
	end
end

function CalendarService:Init(services)
	self.services = services
	self.data = services.DataService
	self.currency = services.CurrencyService
	self.cosmetics = services.CosmeticService
	self.powers = services.PowerService
	self.achievements = services.AchievementService
end

function CalendarService:Start()
	self.data:onLoaded(function(player)
		self:_send(player)
	end)
	local request = Remotes:FindFirstChild("ShopRequest")
	if request then
		request.OnServerEvent:Connect(function(player, action, day)
			if action ~= Protocol.ShopAction.ClaimGift and action ~= Protocol.ShopAction.GiftState then
				return
			end
			if not RateLimiter.allow(limiter, player, os.clock()) then
				return
			end
			if action == Protocol.ShopAction.GiftState then
				self:_send(player)
				return
			end
			local ok, reason = self:claim(player, day)
			if not ok and reason then
				toast(player, reason, "error")
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		RateLimiter.forget(limiter, player)
		busy[player] = nil
	end)
end

-- State -----------------------------------------------------------------------------------------

local function entryOf(profile, calendarId: string)
	local entry = profile.calendars[calendarId]
	if not entry then
		entry = { claimed = {}, perfect = false, milestones = {} }
	end
	return entry
end

-- What a window needs, all from the server clock and the saved profile
function CalendarService:state(player: Player, now: number?)
	local profile = self.data:get(player)
	if not profile then
		return nil
	end
	local time = now or os.time()
	local calendar, today = Calendars.current(time)
	local state: { [string]: any } = {
		kind = "State",
		serverNow = time,
		catchUp = Calendars.CatchUpDays,
	}
	if calendar then
		local entry = entryOf(profile, calendar.id)
		state.calendar = calendar.id
		state.today = today
		state.claimed = table.clone(entry.claimed)
		state.count = Calendars.countClaimed(entry.claimed)
		state.perfect = entry.perfect == true
		state.milestones = table.clone(entry.milestones)
		state.nextDayAt = if today < calendar.days then Calendars.dayStart(calendar, today + 1) else nil
	else
		local upcoming = Calendars.nextAfter(time)
		state.nextId = if upcoming then upcoming.id else nil
		state.nextStartsAt = if upcoming then upcoming.startsAt else nil
	end
	return state
end

function CalendarService:_send(player: Player)
	local state = self:state(player)
	if state and player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Calendar, state)
	end
end

-- Claiming --------------------------------------------------------------------------------------

local function nameOfCosmetic(id: string): string
	local item = Cosmetics.get(id)
	return if item then item.name else id
end

-- Claims day `day` (default: today). Returns (ok, reason). `now` is for tests.
function CalendarService:claim(player: Player, day: any?, now: number?): (boolean, string?)
	if busy[player] then
		return false, "One moment, your last claim is still saving."
	end
	local profile = self.data:get(player)
	if not profile then
		return false, "Your data is still loading."
	end
	local time = now or os.time()
	local calendar, today = Calendars.current(time)
	if not calendar then
		return false, "No gift calendar is running right now."
	end
	if day == nil then
		day = today
	end
	if typeof(day) ~= "number" or day ~= day or day % 1 ~= 0 then
		return false, "That is not a day of the calendar."
	end
	if day < 1 or day > calendar.days then
		return false, "That is not a day of the calendar."
	end
	if day > today then
		return false, "That gift is not ready yet. It opens on its own date."
	end
	if not Calendars.claimableDay(calendar, day, time) then
		return false, "That day can no longer be claimed. Gifts can be claimed on their day or the day after."
	end
	local key = Calendars.dayKey(day)
	if entryOf(profile, calendar.id).claimed[key] then
		return false, "You already claimed that gift."
	end
	if not self.data:isPersistent(player) then
		return false, "Gifts are paused while saving is off. Rejoin to claim."
	end

	busy[player] = true
	local ok, result = pcall(self._claim, self, player, calendar, day, key)
	busy[player] = nil
	if not ok then
		warn(`[Calendar] claim failed for {player.Name}: {result}`)
		return false, "Could not claim that gift. Please try again."
	end
	return result.ok, result.reason
end

function CalendarService:_claim(player: Player, calendar, day: number, key: string): { ok: boolean, reason: string? }
	local gift = calendar.gifts[day]
	local dueMilestones = {}
	local perfectDue = false
	local added = false
	self.data:update(player, function(profile)
		local entry = profile.calendars[calendar.id]
		if not entry then
			entry = { claimed = {}, perfect = false, milestones = {} }
			profile.calendars[calendar.id] = entry
		end
		if entry.claimed[key] then
			return
		end
		entry.claimed[key] = true
		added = true
		local count = Calendars.countClaimed(entry.claimed)
		for _, milestone in calendar.milestones do
			local mKey = Calendars.milestoneKey(milestone.count)
			if count >= milestone.count and not entry.milestones[mKey] then
				entry.milestones[mKey] = true
				table.insert(dueMilestones, milestone)
			end
		end
		if count >= calendar.days and not entry.perfect then
			entry.perfect = true
			perfectDue = true
		end
	end)
	if not added then
		return { ok = false, reason = "You already claimed that gift." }
	end
	if not self.data:saveNow(player) then
		-- Not saved: take the claim back so nothing is lost or given twice
		self.data:update(player, function(profile)
			local entry = profile.calendars[calendar.id]
			if entry then
				entry.claimed[key] = nil
				for _, milestone in dueMilestones do
					entry.milestones[Calendars.milestoneKey(milestone.count)] = nil
				end
				if perfectDue then
					entry.perfect = false
				end
			end
		end)
		return { ok = false, reason = "Could not save your claim. Please try again." }
	end

	-- Saved: hand out the rewards
	local lines = {}
	local money, gems = gift.money or 0, gift.gems or 0
	for _, milestone in dueMilestones do
		money += milestone.money or 0
	end
	if money > 0 or gems > 0 then
		self.currency:add(player, { money = money, gems = gems }, `Calendar {calendar.id} day {day}`, false)
		table.insert(lines, self.currency.describe({ money = money, gems = gems }))
	end
	if gift.cosmetic then
		self.cosmetics:grant(player, gift.cosmetic, "calendar")
		table.insert(lines, nameOfCosmetic(gift.cosmetic))
	end
	if gift.trial then
		local def = Powers.get(gift.trial)
		self.powers:grantTrial(player, gift.trial, Calendars.TrialHours, "calendar")
		table.insert(lines, `{Calendars.TrialHours} hours of {if def then def.name else gift.trial}`)
	end
	toast(player, `Day {day} gift: {table.concat(lines, ", ")}.`, "reward")
	for _, milestone in dueMilestones do
		self.cosmetics:grant(player, milestone.cosmetic, "calendar")
		toast(player, `{milestone.count} days claimed: {nameOfCosmetic(milestone.cosmetic)} and {milestone.money} Money.`, "reward")
	end
	if perfectDue then
		for _, id in calendar.perfect.cosmetics do
			self.cosmetics:grant(player, id, "calendar")
		end
		toast(player, `{calendar.perfect.title}: every day claimed. The exclusive set is yours.`, "reward")
		if self.achievements and self.achievements.announce then
			local name = if typeof(player.DisplayName) == "string" and player.DisplayName ~= "" then player.DisplayName else player.Name
			self.achievements:announce(player, `{name} claimed every day of the {calendar.name} and earned {calendar.perfect.title}.`)
		end
	end
	-- The grants above are in the profile; save them too (the claim itself is already safe)
	self.data:saveNow(player)

	if player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Calendar, { kind = "Claimed", calendar = calendar.id, day = day, ok = true, text = table.concat(lines, ", ") })
		self:_send(player)
	end
	return { ok = true }
end

return CalendarService
