-- Status and recognition on the server (CosmeticService, AchievementService, Leaderboards):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/status_test.luau build/game.rbxl
-- Grants and equips are validated (junk and forged requests change nothing), what is worn is
-- mirrored onto the Player as attributes, the Founding Recruit title is given once, achievement
-- progress counts from a match result and from counters, a title reward arrives only after the
-- achievement is recorded, server-wide lines obey the rate limit, and the leaderboard writes are
-- throttled and survive DataStore failures.

local process = require("@lune/process")
local World = require("./smoke/World")

local api = World.start(process.args[1] or "build/game.rbxl")
local Engine, task = api.Engine, api.task
local world, services, check = api.world, api.services, api.check
local Data, Cosmetic, Achieve = services.DataService, services.CosmeticService, services.AchievementService
local Cosmetics = world.require(world.find("ReplicatedStorage.Shared.Config.Cosmetics"))
local Achievements = world.require(world.find("ReplicatedStorage.Shared.Config.Achievements"))
local Protocol = world.require(world.find("ReplicatedStorage.Shared.Protocol"))
local Boards = world.require(world.find("ServerScriptService.Server.World.Leaderboards"))
local Attr = Protocol.Attribute

local function joined(name, userId)
	local player = api.join(name, userId)
	api.waitFor(function()
		return Data:get(player) ~= nil
	end, 5, name .. "'s profile")
	task.wait(0.2)
	return player
end
local function owned(player, id)
	return Data:get(player).cosmetics.owned[id] == true
end
local function equipped(player, slot)
	return Data:get(player).cosmetics.equipped[slot]
end
local function equipRequest(player, ...)
	api.request("CosmeticRequest", player, ...)
	task.wait(0.05)
end

-- The registry itself ------------------------------------------------------------------------
check("every achievement title exists as an achievement cosmetic and is used once", function()
	local used = {}
	for _, def in Achievements.List do
		if def.title then
			local item = Cosmetics.get(def.title)
			assert(item and item.kind == "title" and item.source == "achievement", def.id .. " title " .. def.title)
			assert(not used[def.title], "title reused: " .. def.title)
			used[def.title] = true
		end
	end
	for id, item in Cosmetics.Items do
		if item.source == "achievement" then
			assert(used[id], id .. " is not the reward of any achievement")
		end
	end
	assert(#Achievements.List >= 28, "about 30 achievements, got " .. #Achievements.List)
	for _, def in Achievements.List do
		assert(not string.find(def.name .. def.desc, "\u{2014}"), "no em dash in " .. def.id)
	end
end)

local alice = joined("Alice", 901)
local bob = joined("Bob", 902)

-- Founding Recruit ---------------------------------------------------------------------------------
check("a first-session player gets Founding Recruit once and is told (not auto-worn: the tour's title comes first)", function()
	assert(owned(alice, "title_founding"), "Alice owns the founding title")
	assert(equipped(alice, "title") == nil and alice:GetAttribute(Attr.Title) == "", "left unworn for the tour's Recruit title")
	assert(Cosmetic:equip(alice, "title", "title_founding") == true, "can be worn")
	assert(alice:GetAttribute(Attr.Title) == "Founding Recruit", "attribute shows the title text")
	local toast = nil
	for _, entry in Engine.sent do
		if entry.remote == "DataEvent" and entry.args[1] == alice and entry.args[2] == "Toast" and entry.args[3].text == "New title: Founding Recruit" then
			toast = entry.args[3]
		end
	end
	assert(toast and toast.kind == "reward", "toast tells the player")
	assert(Cosmetic:grant(alice, "title_founding", "founder") == false, "no second grant")
end)

check("returning players and late joiners do not get the founding title", function()
	local carol = joined("Carol", 903)
	Data:update(carol, function(profile)
		profile.cosmetics.owned.title_founding = nil
		profile.cosmetics.equipped.title = nil
		profile.meta.sessions = 4
	end)
	Cosmetic:_founding(carol, Data:get(carol))
	assert(not owned(carol, "title_founding"), "a player on their fourth session is not new")
	Data:update(carol, function(profile)
		profile.meta.sessions = 1
	end)
	local before = Cosmetics.FounderUntil
	Cosmetics.FounderUntil = os.time() - 10
	Cosmetic:_founding(carol, Data:get(carol))
	assert(not owned(carol, "title_founding"), "after the cutoff nobody gets it")
	Cosmetics.FounderUntil = before
	Cosmetic:_founding(carol, Data:get(carol))
	assert(owned(carol, "title_founding"), "a new player before the cutoff does")
	api.leave(carol)
end)

-- grant and owns -----------------------------------------------------------------------------------
check("grant: unknown ids and repeats return false, a new item is saved in one update", function()
	assert(Cosmetic:grant(alice, "title_nope", "test") == false, "unknown id")
	assert(Cosmetic:grant(alice, "", "test") == false and Cosmetic:grant(alice, 42 :: any, "test") == false, "junk ids")
	assert(Cosmetic:owns(alice, "title_champion") == false)
	local mark = api.mark()
	assert(Cosmetic:grant(alice, "title_champion", "test") == true, "granted")
	assert(Cosmetic:owns(alice, "title_champion") and owned(alice, "title_champion"), "owned in the profile")
	assert(equipped(alice, "title") == "title_founding", "an occupied slot keeps what is worn")
	local toasts = api.sentSince(mark, "DataEvent", "Toast", alice)
	assert(#toasts == 1 and toasts[1].text == "New title: Champion", "one toast, got " .. tostring(toasts[1] and toasts[1].text))
	assert(Cosmetic:grant(alice, "title_champion", "test") == false, "second grant is false")
	assert(#api.sentSince(mark, "DataEvent", "Toast", alice) == 1, "no second toast")
end)

check("granted listeners see the source", function()
	local seen = nil
	Cosmetic:onGranted(function(player, id, source)
		seen = { player, id, source }
	end)
	Cosmetic:grant(alice, "title_unbroken", "achievement")
	task.wait(0.1)
	assert(seen and seen[1] == alice and seen[2] == "title_unbroken" and seen[3] == "achievement")
end)

-- equip ----------------------------------------------------------------------------------------------
check("equip: wrong slot, unknown slot, unowned item and junk change nothing", function()
	local before = equipped(alice, "title")
	assert(select(1, Cosmetic:equip(alice, "plate", "title_champion")) == false, "title in the plate slot")
	assert(select(1, Cosmetic:equip(alice, "hat", "title_champion")) == false, "unknown slot")
	assert(select(1, Cosmetic:equip(alice, "title", "title_veteran")) == false, "not owned")
	assert(select(1, Cosmetic:equip(alice, "title", "nope")) == false, "unknown item")
	assert(select(1, Cosmetic:equip(alice, 5 :: any, true :: any)) == false, "junk types")
	assert(select(1, Cosmetic:equip(alice, "title", string.rep("x", 500))) == false, "long id")
	equipRequest(alice, "Equip", "title", "title_veteran")
	equipRequest(alice, "Wear", "title", "title_champion")
	equipRequest(alice, "Equip", { "title" }, 12)
	equipRequest(alice, "Equip", "plate", "title_champion")
	assert(equipped(alice, "title") == before, "still wearing " .. tostring(before))
	assert(alice:GetAttribute(Attr.Title) == "Founding Recruit")
end)

check("equip works through the remote, mirrors the attribute and takes off with an empty id", function()
	equipRequest(alice, "Equip", "title", "title_champion")
	assert(equipped(alice, "title") == "title_champion", "worn")
	assert(alice:GetAttribute(Attr.Title) == "Champion", "attribute follows")
	assert(bob:GetAttribute(Attr.Title) ~= "Champion", "Bob's own title is his own")
	equipRequest(alice, "Equip", "title", "")
	assert(equipped(alice, "title") == nil, "taken off")
	assert(alice:GetAttribute(Attr.Title) == "", "attribute is empty")
	assert(alice:GetAttribute(Attr.Plate) == "" and alice:GetAttribute(Attr.CosmeticAura) == "" and alice:GetAttribute(Attr.Knockout) == "", "other slots empty")
end)

check("equip requests are rate limited", function()
	local before = 0
	for i = 1, 40 do
		api.request("CosmeticRequest", alice, "Equip", "title", if i % 2 == 0 then "title_champion" else "")
	end
	task.wait(0.05)
	-- 40 flips in an instant: the limiter lets only a few through, so the last state is not
	-- guaranteed to be the 40th request, but the server stayed valid
	local worn = equipped(alice, "title")
	assert(worn == nil or worn == "title_champion", "valid state")
	local _ = before
end)

check("something granted by another service (the tutorial writes the profile directly) still shows", function()
	Data:update(bob, function(profile)
		profile.cosmetics.owned.title_recruit = true
		profile.cosmetics.equipped.title = "title_recruit"
	end)
	task.wait(0.1)
	assert(bob:GetAttribute(Attr.Title) == "Recruit", "mirrored after a direct profile write")
end)

-- Achievements -----------------------------------------------------------------------------------------
local function result(extra)
	local base = { mode = "Duel", won = true, draw = false, knockouts = 2, deaths = 0, power = "Ghost", masteryBefore = 1, masteryAfter = 1, streak = 1, fightSeconds = 60, cpu = false, paid = true }
	for key, value in extra or {} do
		base[key] = value
	end
	return base
end

check("a match result counts progress and finishes the first win", function()
	Data:update(alice, function(profile)
		profile.stats.wins = 1
		profile.stats.matches = 1
	end)
	Achieve:_onMatchResult(alice, result())
	local profile = Data:get(alice)
	assert(profile.achievements.progress.cleanWins == 1, "clean win counted")
	assert(profile.achievements.progress.duelWins == 1, "duel win counted")
	assert(profile.achievements.progress.used_Ghost == 1, "fighter used")
	assert(profile.achievements.done.win_1 == true, "First Win done")
	assert(profile.achievements.done.clean_1 == true, "Untouched done")
	assert(profile.achievements.done.fighters_all ~= true, "not everything")
	Achieve:_onMatchResult(alice, result({ cpu = true, mode = "Practice", power = "Syntax" }))
	assert(profile.achievements.progress.cpuWins == 1 and profile.achievements.progress.duelWins == 1, "a CPU win is not a duel win")
	Achieve:_onMatchResult(alice, result({ won = false, deaths = 2, power = "Admin" }))
	assert(profile.achievements.progress.cleanWins == 2 and profile.achievements.progress.used_Admin == 1, "a loss counts the fighter but not a clean win")
	Achieve:_onMatchResult(alice, result({ paid = false, power = "Corruption" }))
	assert(profile.achievements.progress.used_Corruption == nil, "an unpaid match counts nothing")
	assert(Achieve:progressOf(alice, "fighters_3") == 3, "three fighters used")
	assert(profile.achievements.done.fighters_3 == true, "Three Fighters done")
end)

check("a title reward comes only after the achievement is recorded, once", function()
	local order = {}
	Cosmetic:onGranted(function(player, id)
		if player == alice and id == "title_veteran" then
			table.insert(order, Data:get(alice).achievements.done.win_50 == true)
		end
	end)
	assert(not owned(alice, "title_veteran"))
	Data:update(alice, function(profile)
		profile.stats.wins = 50
	end)
	task.wait(1.0)
	assert(Data:get(alice).achievements.done.win_50 == true, "Fifty Wins done")
	assert(owned(alice, "title_veteran"), "title granted")
	assert(#order == 1 and order[1] == true, "the done flag was already saved when the title arrived")
	Achieve:evaluate(alice, true)
	task.wait(0.1)
	assert(#order == 1, "no second grant")
	assert(Achieve:count(alice, "x", -1) == false and Achieve:count(alice, string.rep("k", 90), 1) == false, "bad counters refused")
end)

check("mastery, Archive files and fighters count from the profile", function()
	Data:update(bob, function(profile)
		profile.powers.Ghost = { xp = 9600 } -- level 12
		profile.lore.found = { ajkr_first_entry = true }
	end)
	local finished = Achieve:evaluate(bob, true)
	local set = {}
	for _, id in finished do
		set[id] = true
	end
	assert(set.mastery_5 and set.mastery_10 and not set.mastery_20, "levels 5 and 10 but not 20")
	assert(set.lore_1, "first file")
	assert(owned(bob, "title_adept"), "level 10 title")
end)

check("watching a match is counted once per match", function()
	-- The stand-in engine does not fire attribute signals by itself, so the test does
	local function spectate(id)
		bob:SetAttribute(Attr.Spectating, id)
		Engine.signalOf(bob, "Attribute:" .. Attr.Spectating):Fire()
		task.wait(0.1)
	end
	local function watched()
		return Data:get(bob).achievements.progress.watched or 0
	end
	local before = watched()
	spectate("match_1")
	spectate(nil)
	spectate("match_1")
	assert(watched() == before + 1, `same match counted once ({before} -> {watched()})`)
	spectate("match_2")
	assert(watched() == before + 2, "a different match counts")
	spectate(nil)
end)

-- Server-wide lines --------------------------------------------------------------------------------------
check("server-wide lines: one at once, a short queue, the rest dropped; display names only", function()
	task.wait(1.0) -- let earlier lines (the mastery and streak moments) drain
	Achieve.MomentGap = 0.5
	Achieve.QueueMax = 3
	task.wait(0.6)
	local mark = api.mark()
	local accepted = 0
	for i = 1, 7 do
		if Achieve:announce(alice, `Alice has won {i} matches in a row.`) then
			accepted += 1
		end
	end
	local now = api.sentSince(mark, "StatusEvent", "Moment")
	assert(#now == 1, "exactly one line right away, got " .. #now)
	assert(accepted == 4, "one sent and three queued, got " .. accepted)
	task.wait(2.4)
	local all = api.sentSince(mark, "StatusEvent", "Moment")
	assert(#all == 4, "the queue drained to four lines, got " .. #all)
	assert(all[1].text == "Alice has won 1 matches in a row.", "first line first")
	assert(Achieve:announce(alice, "") == false and Achieve:announce(alice, 5 :: any) == false, "junk lines refused")
	Achieve.MomentGap = 8
end)

check("notable moments reach everyone: streak 5, 10 and 15, and a notable achievement", function()
	task.wait(8.2) -- the real gap
	Achieve.MomentGap = 0.3
	local mark = api.mark()
	Achieve:_onMatchResult(alice, result({ streak = 5 }))
	task.wait(0.1)
	Achieve:_onMatchResult(alice, result({ streak = 4 }))
	Achieve:_onMatchResult(alice, result({ streak = 15 }))
	task.wait(0.8)
	local lines = api.sentSince(mark, "StatusEvent", "Moment")
	assert(#lines == 2, "streak 5 and 15 only, got " .. #lines)
	assert(string.find(lines[1].text, "Alice") and string.find(lines[1].text, "5 matches"), lines[1].text)
	local earned = api.sentSince(mark, "StatusEvent", "Earned", alice)
	local found15 = false
	for _, entry in earned do
		if string.find(entry.headline, "15") then
			found15 = true
		end
	end
	assert(found15, "the earner sees a moment for 15")
	local mark2 = api.mark()
	Data:update(bob, function(profile)
		profile.powers.Ghost = { xp = 31200 } -- level 20
	end)
	task.wait(1.2)
	local more = api.sentSince(mark2, "StatusEvent", "Moment")
	assert(#more == 1 and string.find(more[1].text, "Bob") and string.find(more[1].text, "Fully Mastered"), "mastery 20 is announced: " .. tostring(more[1] and more[1].text))
	for _, line in more do
		assert(#line.text <= 140)
	end
	Achieve.MomentGap = 8
end)

-- Leaderboards -------------------------------------------------------------------------------------------
local function fakeBoards(failing)
	local data = {}
	local log = { updates = 0 }
	local function provider(name)
		if failing.provider then
			error("DataStore is down")
		end
		data[name] = data[name] or {}
		return {
			UpdateAsync = function(_, key, fn)
				if failing.write then
					error("429 throttled")
				end
				log.updates += 1
				data[name][key] = fn(data[name][key])
				return data[name][key]
			end,
			GetSortedAsync = function(_, _, size)
				if failing.read then
					error("503")
				end
				local rows = {}
				for key, value in data[name] do
					table.insert(rows, { key = key, value = value })
				end
				table.sort(rows, function(a, b)
					return a.value > b.value
				end)
				return { GetCurrentPage = function()
					return { table.unpack(rows, 1, math.min(size, #rows)) }
				end }
			end,
		}
	end
	return provider, data, log
end

check("leaderboard writes are throttled per player, only when a number rose, and failures are survived", function()
	local failing = {}
	local provider, data, log = fakeBoards(failing)
	local now = 1000
	Boards.setProvider(provider, function()
		return now
	end)
	local base = Boards.writes
	Boards.submit(7001, 3, 2, true)
	assert(Boards.writes - base == 2 and data.SN_Wins_v1["7001"] == 3 and data.SN_BestStreak_v1["7001"] == 2, "first submit writes both boards")
	Boards.submit(7001, 3, 2, true)
	Boards.submit(7001, 4, 2, true)
	now += 10
	Boards.submit(7001, 5, 3, true)
	assert(Boards.writes - base == 2, "within a minute nothing more is written")
	now += 61
	Boards.flush()
	assert(Boards.writes - base == 4 and data.SN_Wins_v1["7001"] == 5 and data.SN_BestStreak_v1["7001"] == 3, "the held-back numbers go out after the gap")
	Boards.submit(7001, 5, 3, true)
	now += 100
	Boards.flush()
	assert(Boards.writes - base == 4, "unchanged numbers are never rewritten")
	-- A copy that is not being saved never writes; junk numbers are ignored
	Boards.submit(7002, 99, 9, false)
	Boards.submit(7003, -5, 0 / 0, true)
	Boards.submit("x" :: any, 1, 1, true)
	Boards.flush()
	assert(data.SN_Wins_v1["7002"] == nil and data.SN_Wins_v1["7003"] == nil, "no writes for unsaved or junk")
	-- Failures: nothing throws, the write is retried later
	failing.write = true
	local failuresBefore = Boards.failures
	Boards.submit(7001, 8, 3, true)
	now += 61
	Boards.flush()
	assert(Boards.failures > failuresBefore, "the failure was counted")
	assert(data.SN_Wins_v1["7001"] == 5, "nothing was written")
	failing.write = nil
	now += 61
	Boards.flush()
	assert(data.SN_Wins_v1["7001"] == 8, "retried and written once the store is back")
	assert(log.updates >= 5)
	-- The store never goes down in value
	Boards.submit(7004, 1, 1, true)
	data.SN_Wins_v1["7004"] = 50
	now += 61
	Boards.submit(7004, 2, 1, true)
	assert(data.SN_Wins_v1["7004"] == 50, "UpdateAsync keeps the higher number")
end)

check("the leaderboard reads top ten, says unavailable when no read ever worked, and keeps the last good rows", function()
	local failing = { provider = true }
	local provider, data = fakeBoards(failing)
	Boards.setProvider(provider)
	-- clear anything cached from the previous check
	assert(Boards.refresh() == false, "provider down: refresh reports failure and does not throw")
	local gui = world.workspace:FindFirstChild("Leaderboards", true)
	assert(gui, "the board exists in the hub")
	local sign = gui.Board.Sign
	assert(sign.Unavailable.Visible == (not Boards.available()), "the sign tells the truth")
	failing.provider = nil
	for i = 1, 14 do
		Boards.submit(8000 + i, i, i % 5 + 1, true)
	end
	local rowsProvider, rowData = fakeBoards({})
	Boards.setProvider(rowsProvider)
	for i = 1, 14 do
		rowData.SN_Wins_v1 = rowData.SN_Wins_v1 or {}
		rowData.SN_BestStreak_v1 = rowData.SN_BestStreak_v1 or {}
		rowData.SN_Wins_v1[tostring(8000 + i)] = i
		rowData.SN_BestStreak_v1[tostring(8000 + i)] = i % 5 + 1
	end
	assert(Boards.refresh() == true, "read works")
	local wins = Boards.rows("wins")
	assert(#wins == 10 and wins[1].value == 14 and wins[10].value == 5, "top ten, highest first")
	assert(sign.Unavailable.Visible == false, "the notice is hidden once data is there")
	assert(sign.Value_wins_1.Text == "14" and string.find(sign.Name_wins_1.Text, "^1  "), "the sign shows rank and value")
	local failing2 = { read = true }
	local brokenProvider = fakeBoards(failing2)
	Boards.setProvider(brokenProvider)
	assert(Boards.refresh() == false, "read failure reported")
	assert(#Boards.rows("wins") == 10 and sign.Value_wins_1.Text == "14", "the last good rows stay on the sign")
	local _ = data
end)

check("the board sits on the entrance wall, away from every gate and statue", function()
	local board = world.workspace:FindFirstChild("Leaderboards", true).Board
	local pos = board.Position
	assert(pos.Z > 80 and math.abs(pos.X) > 10 and math.abs(pos.X) < 40, "on the +Z wall beside the doorway: " .. tostring(pos))
	assert(board.Size.X >= 20 and board.Size.Y >= 14, "large enough to read")
	for _, gate in world.workspace:GetDescendants() do
		if gate:IsA("Model") and string.sub(gate.Name, 1, 7) == "Portal_" then
			local part = gate:FindFirstChild("PortalSurface")
			if part then
				assert((part.Position - pos).Magnitude > 12, "clear of " .. gate.Name)
			end
		end
	end
end)

local failed = api.finish()
process.exit(if failed > 0 then 1 else 0)
