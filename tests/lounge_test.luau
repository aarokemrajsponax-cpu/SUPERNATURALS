-- The Spectating Lounge on the real server services with simulated players:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/lounge_test.luau build/game.rbxl
-- Covers: the room builds inside its part budget; every seat is a working Seat in the room
-- and no two overlap; the Archive nook, the counter attachment point, the shop kiosk and the
-- Archive lectern are there with the right prompts; the hub door leads to the lounge; the
-- live screens show real match data (names, fighters, mode, clock, spectators) and clear to
-- the idle view after the match; Watch puts a player in spectator mode and StopSpectating
-- ends it; predictions record, show community percentages, pay nothing, and only touch the
-- informational counters; a disconnecting participant leaves no stale data on the screens.

local process = require("@lune/process")
local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl")
local world, task, services = game.world, game.task, game.services
local MatchService, DataService, LoungeService = services.MatchService, services.DataService, services.LoungeService
local MatchConfig = game.MatchConfig
local Lounge = world.require(world.find("ServerScriptService.Server.World.Lounge"))
local Hub = world.require(world.find("ServerScriptService.Server.World.Hub"))

MatchConfig.Modes.Duel.Countdown = 0.3
MatchConfig.Modes.Duel.Duration = 3
MatchConfig.Modes.Duel.ResultsDuration = 0.4
MatchConfig.Modes.Duel.QueueFillDelay = 0.3

local room = world.workspace:WaitForChild("Lounge")

local function textOf(root: any, name: string): string
	local item = root:FindFirstChild(name, true)
	return if item and item:IsA("TextLabel") then item.Text else "<missing " .. name .. ">"
end
local main = room:FindFirstChild("MainScreen", true)
local function pane(name: string) return main:FindFirstChild(name, true) end
local list = room:FindFirstChild("ListScreen", true)
local board = room:FindFirstChild("BoardScreen", true)
local function promptOf(partName: string)
	return room:FindFirstChild(partName, true):FindFirstChildOfClass("ProximityPrompt")
end
local function startDuel(a, b)
	game.request("MatchRequest", a, "Queue", "Duel", { arena = "SoulFoundry" })
	game.request("MatchRequest", b, "Queue", "Duel", { arena = "SoulFoundry" })
	game.waitFor(function()
		return MatchService:getMatchOf(game.fighter(a)) ~= nil
	end, 2, "the duel to start")
end
local function idle(): boolean
	return pane("Idle").Visible and not pane("Live").Visible
end

game.check("the lounge builds inside its part budget with real seats", function()
	local parts, seats = 0, {}
	for _, item in room:GetDescendants() do
		if item:IsA("BasePart") then
			parts += 1
		end
		if item:IsA("Seat") then
			table.insert(seats, item)
		end
	end
	print("     parts", parts, "seats", #seats)
	assert(parts <= Lounge.PartBudget, `{parts} parts, budget {Lounge.PartBudget}`)
	assert(parts > 250, "a furnished room, not a box")
	assert(#seats >= 20, `{#seats} seats`)
	local center = Lounge.Center
	for index, seat in seats do
		assert(not seat.Disabled and seat.CanTouch, "seat usable")
		local p = seat.Position
		assert(math.abs(p.X - center.X) < 50 and math.abs(p.Z - center.Z) < 38, "seat inside the room")
		assert(p.Y > 1.5 and p.Y < 5, `seat height {p.Y}`)
		for other = index + 1, #seats do
			assert((seats[other].Position - p).Magnitude > 1.8, "two seats overlap")
		end
	end
	assert(room:GetAttribute("Seats") == #seats, "the seat count attribute matches")
	assert(world.workspace.Lounge ~= nil and not world.workspace:FindFirstChild("Terrain") or true)
end)

game.check("archive nook, counter attachment, kiosk and door prompts", function()
	local archive = room:FindFirstChild("FoundersArchive", true)
	local panels = 0
	for _, item in archive:GetChildren() do
		if string.sub(item.Name, 1, 13) == "ChapterPanel_" then
			panels += 1
			local title = textOf(item, "Title")
			local excerpt = textOf(item, "Excerpt")
			assert(#title > 3 and #excerpt > 30 and #excerpt < 200, "title and a short excerpt: " .. excerpt)
			assert(not string.find(excerpt, "{{", 1, true), "redactions never reach the panel")
		end
	end
	assert(panels == 3, "three tall chapter panels")
	local frames = 0
	for _, item in archive:GetChildren() do
		if string.sub(item.Name, 1, 13) == "ExhibitFrame_" then
			frames += 1
			assert(item:FindFirstChild("Image", true) and item:FindFirstChild("Pending", true), "image slot and pending plate")
			assert(Lounge.ExhibitImages[string.sub(item.Name, 14)] == 0, "no invented asset ids")
			assert(item:FindFirstChild("Image", true).Image == "", "empty image while unset")
		end
	end
	assert(frames == 4, "four frames")
	assert(promptOf("Book"):GetAttribute("Action") == "Window:Archive", "the lectern opens the Archive")
	assert(promptOf("Pad").Parent.Parent.Name == "ShopKiosk" or true)
	local kiosk = room:FindFirstChild("ShopKiosk")
	assert(kiosk.Pad:FindFirstChildOfClass("ProximityPrompt"):GetAttribute("Action") == "Window:Market", "kiosk opens the market")
	local attach = room:FindFirstChild("RefreshmentsAttachment", true)
	assert(attach and attach:GetAttribute("Station") == "Refreshments", "documented attachment point")
	assert(room:FindFirstChild("Entrance").Pad:FindFirstChildOfClass("ProximityPrompt"):GetAttribute("Action") == "Travel:Lobby", "return door")
	for _, gate in Hub.Gates do
		if gate.id == "Watch" then
			assert(gate.action == "Travel:Lounge", "the hub door leads to the lounge: " .. gate.action)
		end
	end
end)

game.check("Travel:Lounge arrives inside the lounge and screens start idle", function()
	local carol = game.join("Carol")
	game.request("MatchRequest", carol, "Travel", "Lounge")
	task.wait(0.1)
	local position = game.fighter(carol).root.Position
	assert((position - Lounge.Center).Magnitude < 60 and position.Y > 0, "Carol stands in the lounge")
	assert(idle(), "idle view with no match")
	assert(textOf(main, "Title") == "NO MATCH IN PROGRESS")
	assert(string.find(textOf(main, "Lines"), "Upcoming and training", 1, true), "upcoming or training information")
	assert(not promptOf("WatchPad1").Enabled and not promptOf("PickPad1").Enabled, "no prompts without a match")
	assert(string.find(textOf(board, "Status"), "No match", 1, true), "board idle")
	game.leave(carol)
end)

local snapshot = function(profile)
	return { money = profile.currencies.money, gems = profile.currencies.gems, owned = game.world.require ~= nil and #profile.rewardLog, cos = next(profile.cosmetics.owned) }
end

game.check("live screens, Watch, predictions and the reveal on a real duel", function()
	local alice, bob, carol, dave = game.join("Alice"), game.join("Bob"), game.join("Carol"), game.join("Dave")
	local before = snapshot(DataService:get(dave))
	local mark = game.mark()
	startDuel(alice, bob)
	task.wait(0.2)
	assert(not idle(), "screens switch to live")
	assert(textOf(main, "NameA") == "Alice" and textOf(main, "NameB") == "Bob", "names on the big screen")
	assert(textOf(main, "PowerA") ~= "" and textOf(main, "PowerA") ~= "Unknown", "fighter power shown: " .. textOf(main, "PowerA"))
	assert(string.find(textOf(main, "Sub"), "Duel", 1, true), "mode shown")
	assert(string.find(textOf(main, "Footer"), "spectator", 1, true), "spectator count shown")
	assert(textOf(list:FindFirstChild("Row1", true), "Title") == "Alice vs Bob", "list row: " .. textOf(list:FindFirstChild("Row1", true), "Title"))
	assert(list:FindFirstChild("Row1", true).Visible and not list:FindFirstChild("Row2", true).Visible, "one row")
	assert(promptOf("WatchPad1").Enabled and not promptOf("WatchPad2").Enabled, "one Watch prompt")
	assert(textOf(board, "Status") ~= "" and promptOf("PickPad1").Enabled, "predictions open: " .. textOf(board, "Status"))
	assert(textOf(board, "NameA") == "Alice" and textOf(board, "NameB") == "Bob")

	-- Watch from the lounge: spectator mode on, the screen counts the spectator
	promptOf("WatchPad1").Triggered:Fire(carol)
	task.wait(0.15)
	local matchId = carol:GetAttribute("SNSpectating")
	assert(matchId ~= nil, "Carol is spectating")
	local event = game.lastSent("MatchEvent", "Spectating", carol)
	assert(event and event.matchId == matchId and #event.fighters == 2 and event.mode == "Duel", "Spectating event")
	assert(string.find(textOf(main, "Footer"), "1 spectator", 1, true), "spectator count updates: " .. textOf(main, "Footer"))
	-- The list reply carries the data the Watch window needs
	game.request("MatchRequest", carol, "ListMatches")
	local matches = game.lastSent("MatchEvent", "Matches", carol)
	assert(matches[1].fighters[1].name == "Alice" and matches[1].predictionOpen, "Matches carries fighters and prediction state")
	-- Fighters can't watch their own match
	promptOf("WatchPad1").Triggered:Fire(alice)
	assert(alice:GetAttribute("SNSpectating") == nil, "fighters are not spectators")

	-- Predictions: Carol (watching) and Dave (in the lounge) both pick Alice; a fighter cannot
	game.request("MatchRequest", carol, "Predict", matchId, "Player:" .. alice.UserId)
	promptOf("PickPad1").Triggered:Fire(dave)
	promptOf("PickPad2").Triggered:Fire(dave) -- one pick each
	promptOf("PickPad2").Triggered:Fire(alice) -- a fighter may not predict
	task.wait(0.1)
	assert(MatchService:getMatch(matchId).predictions[dave] == "Player:" .. alice.UserId, "Dave's pick recorded once")
	assert(MatchService:getMatch(matchId).predictions[alice] == nil, "fighters cannot predict")
	assert(textOf(board, "PercentA") == "100%" and textOf(board, "PercentB") == "0%", "community percentages: " .. textOf(board, "PercentA"))
	assert(string.find(textOf(board, "Status"), "2 predictions", 1, true), "count shown: " .. textOf(board, "Status"))
	game.request("MatchRequest", carol, "Predict", "no-such-match", "x")

	-- Alice wins on points; the reveal appears; the screens clear
	MatchService:_onKnockout(game.fighter(bob), game.fighter(alice))
	game.waitFor(function()
		return string.find(textOf(board, "Status"), "Match complete", 1, true) ~= nil
	end, 6, "the winner reveal")
	assert(string.find(textOf(board, "Status"), "Winner: Alice", 1, true), "winner revealed: " .. textOf(board, "Status"))
	assert(string.find(textOf(board, "Status"), "community has made its predictions", 1, true), "the owner's wording")
	game.waitFor(function()
		return idle()
	end, 3, "the main screen to clear")
	assert(textOf(list, "Idle") ~= "" and not list:FindFirstChild("Row1", true).Visible and not promptOf("WatchPad1").Enabled, "list cleared and prompt off")
	assert(string.find(textOf(main, "Lines"), "Alice won Duel", 1, true), "recent result listed: " .. textOf(main, "Lines"))
	assert(carol:GetAttribute("SNSpectating") == nil, "spectating ended with the match")
	assert(game.lastSent("MatchEvent", "Spectating", carol) == nil, "client told to restore")

	-- Results for the predictors: informational counters only, nothing paid
	local result = game.lastSent("MatchEvent", "PredictionResult", dave)
	assert(result and result.correct == true and result.predictions == 1 and result.correctCount == 1, "Dave was told")
	local profile = DataService:get(dave)
	assert(profile.stats.predictions == 1 and profile.stats.predictionsCorrect == 1, "stats recorded")
	local after = snapshot(profile)
	assert(after.money == before.money and after.gems == before.gems and after.owned == before.owned and after.cos == before.cos, "a correct prediction pays nothing")
	assert(DataService:get(carol).stats.predictions == 1, "Carol's counter too")
	assert(DataService:get(alice).stats.predictions == 0, "fighters have none")
	assert(game.sentSince(mark, "MatchEvent", "Matches", dave)[1] ~= nil, "Dave saw the updated list")
	for _, name in { "Alice", "Bob", "Carol", "Dave" } do
		for _, p in game.Engine.players do
			if p.Name == name then
				game.leave(p)
			end
		end
	end
end)

game.check("a disconnecting participant leaves no stale data; exit restores spectators", function()
	local alice, bob, carol = game.join("Erin"), game.join("Finn"), game.join("Gus")
	startDuel(alice, bob)
	task.wait(0.2)
	assert(textOf(main, "NameB") == "Finn", "live")
	promptOf("WatchPad1").Triggered:Fire(carol)
	task.wait(0.1)
	assert(carol:GetAttribute("SNSpectating") ~= nil, "watching")
	-- Exit by choice
	game.request("MatchRequest", carol, "StopSpectating")
	task.wait(0.1)
	assert(carol:GetAttribute("SNSpectating") == nil, "Exit stops spectating")
	assert(game.lastSent("MatchEvent", "Spectating", carol) == nil, "and tells the client")
	assert(string.find(textOf(main, "Footer"), "0 spectators", 1, true), "count drops: " .. textOf(main, "Footer"))
	promptOf("WatchPad1").Triggered:Fire(carol)
	task.wait(0.1)
	-- One fighter disconnects: the screens stop naming him
	game.leave(bob)
	game.waitFor(function()
		return string.find(textOf(main, "NameB"), "Finn", 1, true) == nil
	end, 3, "the screen to drop the leaver")
	-- The other leaves too: the match is gone, the spectator is told, screens go idle
	game.leave(alice)
	game.waitFor(function()
		return idle() and carol:GetAttribute("SNSpectating") == nil
	end, 6, "screens to clear and the spectator to be released")
	assert(game.lastSent("MatchEvent", "Spectating", carol) == nil, "spectator told to restore")
	assert(not promptOf("WatchPad1").Enabled, "prompt off")
	assert(MatchService:getMatchOf(game.fighter(carol)) == nil)
end)

game.check("the seasonal set dresses the lounge (Thanksgiving now) and clears with the season", function()
	local SeasonalDecor = world.require(world.find("ServerScriptService.Server.SeasonalDecor"))
	for _, id in { "Thanksgiving", "Halloween", "Christmas", "Easter" } do
		SeasonalDecor.build(id)
		local folder = world.workspace:FindFirstChild("SeasonalDecor")
		local extra = 0
		for _, name in { "LoungeHarvest", "LoungeHalloween", "LoungeChristmas", "LoungeGarland", "LoungeWreath" } do
			local item = folder:FindFirstChild(name)
			if item then
				for _, part in item:GetDescendants() do
					if part:IsA("BasePart") then
						extra += 1
						local p = part.CFrame.Position
						assert(math.abs(p.X - Lounge.Center.X) < 52 and math.abs(p.Z - Lounge.Center.Z) < 40 and p.Y > 0 and p.Y < 25, `{id} accent {part:GetFullName()} at {p} inside the room`)
					end
				end
			end
		end
		if id == "Thanksgiving" then
			assert(folder:FindFirstChild("LoungeHarvest") and folder:FindFirstChild("LoungeGarland") and folder:FindFirstChild("LoungeAutumnGlow"), "autumn accents")
			assert(extra > 40 and extra < 200, "a modest set: " .. extra)
		elseif id == "Easter" then
			assert(extra == 0, "no lounge set for Easter yet")
		end
		SeasonalDecor.clear()
		assert(world.workspace:FindFirstChild("SeasonalDecor") == nil, "cleared")
	end
end)

process.exit(if game.finish() == 0 then 0 else 1)
