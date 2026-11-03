-- The holiday gift calendar (label GIFTS): every day of the running calendar as a card (claimed,
-- today, missed but still open, missed, future) with that day's gift, the milestone track by days
-- claimed, the perfect prize with its rule in one sentence, the next gift time in the player's
-- own time zone, and a Claim button. Outside a calendar's dates it says when the next one starts.
-- No countdown and no pressure wording: a gentle toast tells the player once per session that
-- today's gift is ready. The window only asks; CalendarService checks every claim.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Calendars = require(ReplicatedStorage.Shared.Config.Calendars)
local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Shell = require(script.Parent.Shell)
local Profile = require(script.Parent.Parent.Profile)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShopRequest = Remotes:WaitForChild("ShopRequest") :: RemoteEvent
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make

local CalendarWindow = {}

local WINDOW_ID = "Calendar"
local COLUMNS = 5
local CELL_W = 126
local CELL_H = 100
local GAP = 8
local SIDE_X = COLUMNS * (CELL_W + GAP) + 4
local TOP_H = 76

local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
local KIND_WORD = { title = "title", plate = "nameplate", aura = "aura", knockout = "knockout" }

-- Dates -----------------------------------------------------------------------------------------

-- Year, month, day (UTC) of a Unix time
local function civil(t: number): (number, number, number)
	local z = math.floor(t / 86400) + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	return if m <= 2 then y + 1 else y, m, d
end

-- "5 November 2026" (UTC date of a day's start)
local function dateText(t: number): string
	local y, m, d = civil(t)
	return `{d} {MONTHS[m]} {y}`
end

-- "9 Nov" for a day card
local function shortDate(t: number): string
	local _, m, d = civil(t)
	return `{d} {string.sub(MONTHS[m], 1, 3)}`
end

-- "Fri 6 Nov, 4:00 PM" in the player's own time zone (UTC text if the engine has no local time)
local function localText(t: number): string
	local ok, text = pcall(function()
		return DateTime.fromUnixTimestamp(t):FormatLocalTime("ddd D MMM, h:mm A", "en-us")
	end)
	if ok and typeof(text) == "string" then
		return text
	end
	local y, m, d = civil(t)
	local seconds = t % 86400
	return `{d} {string.sub(MONTHS[m], 1, 3)} {y}, {string.format("%02d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))} UTC`
end

local function serverNow(): number
	local ok, now = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return math.floor(if ok and typeof(now) == "number" then now else os.time())
end

-- Gift text ---------------------------------------------------------------------------------------

local function cosmeticName(id: string): string
	local item = Cosmetics.get(id)
	return if item then item.name else id
end

local function powerName(id: string): string
	local def = Powers.get(id)
	return if def then def.name else id
end

-- The lines a day's card shows: the Money line, then the rest as one line
local function giftLines(gift): (string, string)
	local rest = {}
	if gift.gems then
		table.insert(rest, `{gift.gems} Gems`)
	end
	if gift.cosmetic then
		local item = Cosmetics.get(gift.cosmetic)
		table.insert(rest, if item then `{item.name} ({KIND_WORD[item.kind] or item.kind})` else gift.cosmetic)
	end
	if gift.trial then
		table.insert(rest, `{powerName(gift.trial)}, {Calendars.TrialHours} h trial`)
	end
	return `{gift.money} Money`, table.concat(rest, ", ")
end

-- State ---------------------------------------------------------------------------------------------

-- The last State from the server, and how far this device's clock is from the server's
local lastState: { [string]: any }? = nil
local clockOffset = 0
local reminded = false
local redrawWindow: (() -> ())? = nil

local function now(): number
	return os.time() + clockOffset
end

-- What the window knows: the running calendar, today, and the claimed days (the saved profile
-- first, the server's last State otherwise)
local function situation()
	local calendar, today = Calendars.current(now(), if lastState and lastState.catchUp then lastState.catchUp else nil)
	local claimed, milestones = {}, {}
	local perfect = false
	if calendar then
		local view = Profile.get()
		local saved = view and typeof(view.calendars) == "table" and view.calendars[calendar.id]
		if typeof(saved) == "table" then
			claimed = if typeof(saved.claimed) == "table" then saved.claimed else {}
			milestones = if typeof(saved.milestones) == "table" then saved.milestones else {}
			perfect = saved.perfect == true
		elseif lastState and lastState.calendar == calendar.id then
			claimed = lastState.claimed or {}
			milestones = lastState.milestones or {}
			perfect = lastState.perfect == true
		end
	end
	return {
		calendar = calendar,
		today = today,
		claimed = claimed,
		milestones = milestones,
		perfect = perfect,
		count = Calendars.countClaimed(claimed),
		catchUp = if lastState and lastState.catchUp then lastState.catchUp else Calendars.CatchUpDays,
	}
end

-- Status of one day: "claimed" | "today" | "open" (missed, still claimable) | "missed" | "future"
local function dayStatus(s, day: number): string
	if s.claimed[Calendars.dayKey(day)] then
		return "claimed"
	end
	if day > s.today then
		return "future"
	end
	if day == s.today then
		return "today"
	end
	if s.today - day <= s.catchUp then
		return "open"
	end
	return "missed"
end

-- Days to claim now, oldest first
local function readyDays(s): { number }
	local list = {}
	if not s.calendar then
		return list
	end
	for day = 1, math.min(s.today, s.calendar.days) do
		local status = dayStatus(s, day)
		if status == "today" or status == "open" then
			table.insert(list, day)
		end
	end
	return list
end

local function updateBadge()
	local s = situation()
	Shell.setNavBadge(WINDOW_ID, if #readyDays(s) > 0 then "!" else nil)
end

local function request()
	ShopRequest:FireServer(Protocol.ShopAction.GiftState)
end

local function onData(kind, data)
	if kind ~= Protocol.DataEvent.Calendar or typeof(data) ~= "table" then
		return
	end
	if data.kind == "State" and typeof(data.serverNow) == "number" then
		lastState = data
		clockOffset = data.serverNow - os.time()
		updateBadge()
		-- Once per session, gently: today's gift is ready. No countdown, no deadline wording.
		if not reminded and #readyDays(situation()) > 0 then
			reminded = true
			task.delay(4, function()
				if #readyDays(situation()) > 0 and not Shell.isOpen(WINDOW_ID) then
					Shell.toast("A gift is ready in GIFTS whenever you want it.", "info")
				end
			end)
		end
	end
	if redrawWindow then
		redrawWindow()
	end
end

-- Drawing -----------------------------------------------------------------------------------------

local function swatchOf(id: string?)
	local item = id and Cosmetics.get(id)
	local colors = item and item.colors
	if typeof(colors) == "table" and #colors > 0 then
		local rgb = colors[1]
		return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	end
	return Colors.Copper
end

local STATUS_TAG = { claimed = "Claimed", today = "Today", open = "Open", missed = "Missed" }

local function buildDay(parent: Instance, s, day: number, index: number, onClaim: (number) -> ())
	local calendar = s.calendar
	local gift = calendar.gifts[day]
	local status = dayStatus(s, day)
	local col, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
	local fill = Colors.PanelLight
	if status == "today" or status == "open" then
		fill = Colors.Selected
	elseif status == "claimed" then
		fill = Colors.Panel
	end
	local clickable = status == "today" or status == "open"
	local props = {
		Name = `Day_{day}`,
		Position = UDim2.fromOffset(col * (CELL_W + GAP), row * (CELL_H + GAP)),
		Size = UDim2.fromOffset(CELL_W, CELL_H),
		BackgroundColor3 = fill,
		BorderSizePixel = 0,
		Parent = parent,
	}
	local cell
	if clickable then
		props.AutoButtonColor = false
		props.Text = ""
		cell = make("TextButton", props, { Components.corner(Theme.SmallCorner) })
		cell.Activated:Connect(function()
			onClaim(day)
		end)
	else
		cell = make("Frame", props, { Components.corner(Theme.SmallCorner) })
	end
	cell:SetAttribute("Status", status)
	if clickable then
		make("Frame", { Name = "Bar", Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = Colors.Cyan, BorderSizePixel = 0, Parent = cell })
	end
	local dim = status == "missed" or status == "future"
	local textColor = if dim then Colors.TextMuted elseif status == "claimed" then Colors.TextDim else Colors.Text
	Components.text({ Name = "Day", Text = `Day {day}`, Style = "number", TextSize = 14, Weight = "SemiBold", Color = textColor, Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(56, 20), Parent = cell })
	local tag = STATUS_TAG[status] or shortDate(Calendars.dayStart(calendar, day))
	local tagColor = Colors.TextMuted
	if status == "claimed" then
		tagColor = Colors.Success
	elseif status == "today" then
		tagColor = Colors.Cyan
	elseif status == "open" then
		tagColor = Colors.Copper
	end
	Components.text({ Name = "Tag", Text = tag, Style = "small", TextSize = 14, Color = tagColor, AlignX = "Right", Position = UDim2.new(0, 60, 0, 6), Size = UDim2.new(1, -68, 0, 20), Parent = cell })
	local moneyLine, rest = giftLines(gift)
	Components.text({ Name = "Money", Text = moneyLine, Style = "small", TextSize = 14, Weight = "SemiBold", Color = textColor, Position = UDim2.fromOffset(8, 28), Size = UDim2.new(1, -16, 0, 18), Parent = cell })
	if rest ~= "" then
		Components.text({ Name = "Gift", Text = rest, Style = "small", TextSize = 14, Color = if dim then Colors.TextMuted else Colors.TextDim, Lines = 3, Position = UDim2.fromOffset(8, 46), Size = UDim2.new(1, -16, 0, 52), Parent = cell })
	end
	if gift.cosmetic or gift.trial then
		local strip = if gift.trial then Colors.Purple else swatchOf(gift.cosmetic)
		make("Frame", { Name = "Swatch", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -5), Size = UDim2.new(1, -16, 0, 3), BackgroundColor3 = strip, BackgroundTransparency = if dim then 0.6 else 0, BorderSizePixel = 0, Parent = cell })
	end
end

local function sideHeading(parent: Instance, text: string, y: number)
	Components.text({ Name = "Heading_" .. text, Text = text, Style = "heading", TextSize = 18, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 26), Parent = parent })
end

local started = false

function CalendarWindow.register()
	if not started then
		started = true
		-- Listen from the start (not only once the window is built), so the reminder and the
		-- dock badge work before it is ever opened.
		DataEvent.OnClientEvent:Connect(onData)
		task.delay(2, request)
	end
	Shell.registerWindow(WINDOW_ID, {
		title = "Gifts",
		label = "GIFTS",
		icon = "bag",
		order = 3,
		size = Vector2.new(1040, 600),
		accent = Colors.Copper,
		build = function(body: Frame, api)
			local content = Components.scroll({ Name = "Content", Size = UDim2.fromScale(1, 1), ScrollBarThickness = 4 })
			content.Parent = body
			local page = make("Frame", { Name = "Page", Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.None, BackgroundTransparency = 1, Parent = content })

			local function claimAll(days: { number })
				task.spawn(function()
					for _, day in days do
						ShopRequest:FireServer(Protocol.ShopAction.ClaimGift, day)
						task.wait(0.4)
					end
				end)
			end

			local function draw()
				for _, child in page:GetChildren() do
					child:Destroy()
				end
				local s = situation()
				local calendar = s.calendar
				if not calendar then
					page.Size = UDim2.new(1, -8, 0, 260)
					content.CanvasSize = UDim2.fromOffset(0, 270)
					Components.text({ Name = "Title", Text = "No gift calendar is running", Style = "title", Size = UDim2.new(1, 0, 0, 30), Parent = page })
					local upcoming = Calendars.nextAfter(now())
					local line
					if upcoming then
						line = `The {upcoming.name} ({upcoming.holiday}) starts on {dateText(upcoming.startsAt)} and has one gift for each of its {upcoming.days} days. Your local start time: {localText(upcoming.startsAt)}.`
					else
						line = "The next gift calendar has not been announced yet."
					end
					Components.text({ Name = "Next", Text = line, Style = "body", Color = Colors.TextDim, Lines = 3, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, -40, 0, 70), Parent = page })
					Components.text({ Name = "Rule", Text = "Each calendar gives one gift per day. Claim a day on its date or the day after. Claiming more days earns more rewards, and claiming every day earns an exclusive set that is never sold.", Style = "small", TextSize = 15, Color = Colors.TextDim, Lines = 3, Position = UDim2.fromOffset(0, 118), Size = UDim2.new(1, -40, 0, 70), Parent = page })
					return
				end

				-- Header: name, real dates, the rule, and the claim button
				local lastDay = Calendars.dayStart(calendar, calendar.days)
				Components.text({ Name = "Title", Text = calendar.name, Style = "title", Size = UDim2.new(1, -230, 0, 30), Parent = page })
				Components.text({ Name = "Dates", Text = `{dateText(calendar.startsAt)} to {dateText(lastDay)} (UTC days). Day {calendar.days} is {calendar.holiday}.`, Style = "small", TextSize = 15, Color = Colors.TextDim, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, -230, 0, 22), Parent = page })
				local catchText = if s.catchUp > 0 then "A missed day can be claimed the day after." else "Each day can only be claimed on its own date."
				Components.text({ Name = "Rule", Text = `One gift a day. {catchText} Every claimed day counts.`, Style = "small", TextSize = 15, Color = Colors.TextDim, Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, -230, 0, 22), Parent = page })

				local ready = readyDays(s)
				local label = if #ready > 1 then `Claim {#ready} gifts` elseif #ready == 1 then `Claim day {ready[1]}` else "Nothing to claim"
				local claim = Components.button(label, {
					Name = "Claim",
					Variant = if #ready > 0 then "Primary" else "Secondary",
					KeepCase = true,
					TextSize = 16,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, 4),
					Size = UDim2.fromOffset(200, 44),
					Parent = page,
				}, function()
					claimAll(ready)
				end)
				Components.setDisabled(claim, #ready == 0)

				-- Progress and the next gift in the player's own time
				local nextLine
				if s.today < calendar.days then
					local opens = Calendars.dayStart(calendar, s.today + 1)
					nextLine = `Day {s.today + 1} opens {localText(opens)} (your time).`
				elseif s.today == calendar.days then
					nextLine = "That is the last day of this calendar."
				else
					nextLine = "The calendar has ended. A missed last day can still be claimed today."
				end
				Components.text({ Name = "Progress", Text = `Claimed {s.count} of {calendar.days} days. {nextLine}`, Style = "strong", TextSize = 16, Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, -230, 0, 24), Parent = page })

				-- The grid of days
				local gridTop = TOP_H + 38
				local grid = make("Frame", { Name = "Days", Position = UDim2.fromOffset(0, gridTop), Size = UDim2.fromOffset(COLUMNS * (CELL_W + GAP), math.ceil(calendar.days / COLUMNS) * (CELL_H + GAP)), BackgroundTransparency = 1, Parent = page })
				for day = 1, calendar.days do
					buildDay(grid, s, day, day, function(target)
						ShopRequest:FireServer(Protocol.ShopAction.ClaimGift, target)
					end)
				end
				local gridHeight = math.ceil(calendar.days / COLUMNS) * (CELL_H + GAP)

				-- Side column: the perfect prize first (the headline), then the milestones
				local side = make("Frame", { Name = "Side", Position = UDim2.fromOffset(SIDE_X, gridTop), Size = UDim2.new(1, -SIDE_X, 0, 0), AutomaticSize = Enum.AutomaticSize.None, BackgroundTransparency = 1, Parent = page })
				sideHeading(side, calendar.perfect.title, 0)
				local names = {}
				for _, id in calendar.perfect.cosmetics do
					local item = Cosmetics.get(id)
					table.insert(names, if item then `{item.name} ({KIND_WORD[item.kind] or item.kind})` else id)
				end
				local prize = make("Frame", { Name = "Perfect", Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 172), BackgroundColor3 = if s.perfect then Colors.Panel else Colors.PanelLight, BorderSizePixel = 0, Parent = side }, { Components.corner(Theme.SmallCorner) })
				make("Frame", { Name = "Bar", Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = Colors.Gold, BorderSizePixel = 0, Parent = prize })
				Components.text({ Name = "Rule", Text = `Claim all {calendar.days} gifts to earn this set. It is never sold and never offered again.`, Style = "small", TextSize = 14, Color = Colors.Text, Lines = 3, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -20, 0, 56), Parent = prize })
				Components.text({ Name = "Items", Text = table.concat(names, "\n"), Style = "small", TextSize = 14, Color = Colors.TextDim, Lines = 4, Position = UDim2.fromOffset(12, 62), Size = UDim2.new(1, -20, 0, 80), Parent = prize })
				Components.text({ Name = "State", Text = if s.perfect then "Earned" else `{s.count} of {calendar.days} days claimed`, Style = "small", TextSize = 14, Color = if s.perfect then Colors.Success else Colors.TextMuted, Position = UDim2.new(0, 12, 1, -24), Size = UDim2.new(1, -20, 0, 20), Parent = prize })
				local y = 210
				sideHeading(side, "Days claimed rewards", y)
				y += 30
				for _, milestone in calendar.milestones do
					local done = s.milestones[Calendars.milestoneKey(milestone.count)] == true
					local reached = s.count >= milestone.count
					local row = make("Frame", { Name = `Milestone_{milestone.count}`, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = if done then Colors.Panel else Colors.PanelLight, BorderSizePixel = 0, Parent = side }, { Components.corner(Theme.SmallCorner) })
					row:SetAttribute("Done", done)
					local status = if done then "Earned" elseif reached then "Reached" else `{milestone.count - s.count} more`
					Components.text({ Name = "Count", Text = `{milestone.count} days`, Style = "strong", TextSize = 15, Color = if done then Colors.TextDim else Colors.Text, Position = UDim2.fromOffset(8, 3), Size = UDim2.new(0.5, -8, 0, 22), Parent = row })
					Components.text({ Name = "Status", Text = status, Style = "small", TextSize = 14, AlignX = "Right", Color = if done then Colors.Success else Colors.TextMuted, Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.new(0.5, -8, 0, 22), Parent = row })
					Components.text({ Name = "Reward", Text = `{cosmeticName(milestone.cosmetic)} and {milestone.money} Money`, Style = "small", TextSize = 14, Color = Colors.TextDim, Position = UDim2.fromOffset(8, 25), Size = UDim2.new(1, -16, 0, 22), Parent = row })
					y += 58
				end
				side.Size = UDim2.new(1, -SIDE_X, 0, y)

				local pageHeight = gridTop + math.max(gridHeight, y) + 8
				page.Size = UDim2.new(1, -8, 0, pageHeight)
				content.CanvasSize = UDim2.fromOffset(0, pageHeight + 8)
			end

			redrawWindow = function()
				if body.Parent and Shell.isOpen(WINDOW_ID) then
					draw()
				end
				updateBadge()
			end
			Profile.changed:Connect(function()
				redrawWindow()
			end)
			draw()
			return {
				onOpen = function()
					request()
					draw()
				end,
			}
		end,
	})
end

CalendarWindow._situation = situation

return CalendarWindow
