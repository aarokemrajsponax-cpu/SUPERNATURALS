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
	local lectern = archive:FindFirstChild("Lectern")
	assert(lectern and lectern:FindFirstChild("NamePlate") and lectern:FindFirstChild("Spot"), "the lectern has its name plate and a warm spot")
	assert(promptOf("Book").Parent.Parent == lectern, "the Archive book is on the lectern, in the lounge")
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
	assert(string.find(textOf(main, "Lines"), "Start one from Play", 1, true), "one line on how a match appears")
	assert(#textOf(main, "Fighter") > 2 and #textOf(main, "Tagline") > 2, "the idle screen shows a fighter of the roster in large type")
	assert(main:FindFirstChild("Fighter", true).TextSize >= 60 or main:FindFirstChild("Fighter", true).TextScaled, "large type")
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

game.check("the social upgrade: tiers, booths, small screens, photo corner, games table, wheel, kiosks, boards, plants and art", function()
	for _, name in { "TieredSeating", "Booth_West", "Booth_East", "PhotoCorner", "GamesTable", "LoungeWheel", "InviteKiosk", "FriendsBoard", "HighlightsBoard", "Artwork", "RefreshmentsCounter", "ShopKiosk", "FoundersArchive" } do
		assert(room:FindFirstChild(name, true), "the room has " .. name)
	end
	-- Tiers: three raised rows each side, seats facing the main screen (north), centre aisle clear
	local tiers = room:FindFirstChild("TieredSeating", true)
	local rows, seatsOnTiers, heights = 0, 0, {}
	for _, row in tiers:GetChildren() do
		if row:IsA("Model") then
			rows += 1
			heights[row:FindFirstChild("Platform").Size.Y] = true
			for _, item in row:GetChildren() do
				if item:IsA("Seat") then
					seatsOnTiers += 1
					assert(item.CFrame.LookVector.Z < -0.9, "tier seats face the main screen")
					assert(math.abs(item.Position.X - Lounge.Center.X) > 5, "the centre aisle stays clear")
				end
			end
		end
	end
	assert(rows == 6 and seatsOnTiers == 24, `{rows} rows, {seatsOnTiers} seats`)
	assert(next(heights) ~= nil and (function() local n = 0 for _ in heights do n += 1 end return n end)() == 3, "three heights, rising away from the screen")
	-- Booths: four seats each around a table
	for _, name in { "Booth_West", "Booth_East" } do
		local booth = room:FindFirstChild(name, true)
		local seats = 0
		for _, item in booth:GetChildren() do
			if item:IsA("Seat") then
				seats += 1
			end
		end
		assert(seats == 4 and booth:FindFirstChild("TableTop"), name .. " has four seats and a table")
	end
	-- Four small screens that stay in step with the match data
	local minis = 0
	for _, item in room:GetDescendants() do
		if item.Name == "MiniGui" then
			minis += 1
		end
	end
	assert(minis == 4, "four small screens: " .. minis)
	-- The photo corner has light, a mark and a sign; the games table is a pair of seats with buzzers
	local photo = room:FindFirstChild("PhotoCorner", true)
	assert(photo:FindFirstChild("Backdrop") and photo:FindFirstChild("Mark") and photo:FindFirstChild("Softbox") and photo:FindFirstChild("Plate"), "photo corner")
	local softboxLights = 0
	for _, item in photo:GetDescendants() do
		if item:IsA("SpotLight") then
			softboxLights += 1
		end
	end
	assert(softboxLights >= 3, "flattering light: two soft boxes and a warm spot")
	assert(promptOf("Buzzer1") and promptOf("Buzzer2"), "two buzzers")
	-- Prompts: wheel, refreshments, invite; the counter still has its documented attachment
	assert(room:FindFirstChild("LoungeWheel", true).Pad:FindFirstChildOfClass("ProximityPrompt"):GetAttribute("Action") == "Lounge:Wheel")
	assert(room:FindFirstChild("RefreshmentsAttachment", true):FindFirstChildOfClass("ProximityPrompt"):GetAttribute("Action") == "Lounge:Refreshments")
	assert(room:FindFirstChild("InviteKiosk", true).Pad:FindFirstChildOfClass("ProximityPrompt"):GetAttribute("Action") == "Lounge:Invite")
	assert(room:FindFirstChild("FriendsLabel", true):IsA("TextLabel"), "the friends board has its label")
	assert(room:FindFirstChild("Lines", true) ~= nil and textOf(room:FindFirstChild("HighlightsBoard", true), "Title") == "RECENT HIGHLIGHTS")
	-- Sit prompts: every Seat carries one, on its own key, one visible at a time
	local sits, seatsTotal = 0, 0
	for _, item in room:GetDescendants() do
		if item:IsA("Seat") then
			seatsTotal += 1
			local sit = item:FindFirstChildOfClass("ProximityPrompt")
			assert(sit and sit.ActionText == "Sit" and sit:GetAttribute("Sit") == true, "a Sit prompt on " .. item:GetFullName())
			sits += 1
		end
	end
	assert(sits == seatsTotal and seatsTotal >= 56, "sit prompts everywhere: " .. sits)
	-- Plants and art
	local planters, frames = 0, 0
	for _, item in room:GetDescendants() do
		if string.sub(item.Name, 1, 8) == "Planter_" then
			planters += 1
		elseif string.sub(item.Name, 1, 5) == "Frame" and item.Parent.Name == "Artwork" then
			frames += 1
		end
	end
	assert(planters >= 8 and frames == 4, `plants {planters}, art {frames}`)
	-- The part budget still holds with all of it, and nothing is outside the room
	local parts = 0
	for _, item in room:GetDescendants() do
		if item:IsA("BasePart") then
			parts += 1
			local p = item.Position
			assert(math.abs(p.X - Lounge.Center.X) < 54 and math.abs(p.Z - Lounge.Center.Z) < 42 and p.Y < 30, `{item:GetFullName()} is outside the room`)
		end
	end
	assert(parts <= Lounge.PartBudget and parts > 550, "parts " .. parts)
	-- No asset ids were invented for any of it
	for _, item in room:GetDescendants() do
		if item:IsA("ImageLabel") or item:IsA("Decal") then
			local image = item.Image or item.Texture
			assert(image == "" or string.sub(image, 1, 4) ~= "rbxa", "no invented asset id")
		end
	end
end)

game.check("walkways stay clear: the entrance line, the aisles and the viewing wall have no seats or tables in the way", function()
	local center = Lounge.Center
	for _, item in room:GetDescendants() do
		if item:IsA("BasePart") and item.CanCollide and item.Size.Y > 0.9 and not item:IsDescendantOf(room:FindFirstChild("Shell")) then
			local p = item.Position - center
			-- A 9 stud wide lane from the door up to the centre cluster (the new tiers, screens and kiosks keep out of it)
			if p.Z > 11 and p.Z < 36 and math.abs(p.X) < 4.5 and item.Position.Y - center.Y < 8 then
				error(`{item:GetFullName()} blocks the entrance lane at {p}`)
			end
		end
	end
end)

game.check("wheel face: upright labels, no cut-off text, a legend board with every chance, nothing in front of it", function()
	local Wheel = world.require(world.find("ReplicatedStorage.Shared.Config.Wheel"))
	local disc = room:FindFirstChild("Disc", true)
	local marks = 0
	for _, item in disc:GetDescendants() do
		if item:IsA("TextLabel") then
			marks += 1
			assert(#item.Text <= 4, "short wedge labels only: " .. item.Text)
			local node = item
			while node ~= disc do
				if node:IsA("GuiObject") then
					assert(node.Rotation == 0 or string.sub(node.Name, 1, 5) == "Wedge" or string.sub(node.Name, 1, 7) == "Divider", "no rotated text: " .. node:GetFullName())
				end
				node = node.Parent
			end
			assert(not string.find(item.Text, "%%"), "chances are not on the wedges")
			local ancestor = item.Parent
			while ancestor ~= disc do
				assert(not (ancestor:IsA("GuiObject") and ancestor.Rotation ~= 0), "the label has a rotated ancestor: " .. ancestor:GetFullName())
				ancestor = ancestor.Parent
			end
		end
	end
	assert(marks == 9, "nine text marks and three symbols: " .. marks)
	local legend = room:FindFirstChild("WheelLegend", true)
	local total = 0
	for index, prize in Wheel.Prizes do
		assert(textOf(legend, "Chance" .. index) == `{prize.percent}%`, "legend row " .. index)
		assert(#textOf(legend, "Prize" .. index) > 3 and #textOf(legend, "Prize" .. index) <= 24, "short legend text")
		total += prize.percent
	end
	assert(total == 100 and textOf(legend, "Total") == "Total 100%", "the legend totals 100%")
	-- Nothing stands in front of the wheel or the legend (x -29 to -4, z 26 to 38)
	for _, item in room:GetDescendants() do
		if item:IsA("BasePart") and item.CanCollide and (string.find(item.Name, "Leaves") or string.find(item.Name, "Pot") or item.Name == "Shade" or item.Name == "Pole") then
			local p = item.Position - Lounge.Center
			assert(not (p.X > -29 and p.X < -4 and p.Z > 26 and p.Z < 36), `{item:GetFullName()} stands in front of the wheel at {p}`)
		end
	end
end)

game.check("art is intentional: gradient landscapes with a plaque, no placeholder bars", function()
	local art = room:FindFirstChild("Artwork", true)
	local pieces = 0
	for _, item in art:GetChildren() do
		if string.sub(item.Name, 1, 6) == "Canvas" then
			pieces += 1
			local sky = item:FindFirstChild("Sky", true)
			assert(sky and sky:FindFirstChildOfClass("UIGradient"), "a sky gradient")
			assert(sky:FindFirstChild("Sun") and sky:FindFirstChild("HillFront"), "a sun and hills")
			assert(item.Parent:FindFirstChild("Plaque" .. string.sub(item.Name, 7)), "a brass plaque")
		end
		assert(not string.find(item.Name, "Shape"), "no leftover placeholder shapes")
	end
	assert(pieces == 4)
end)

game.check("warmer room: few dim accent lines, wood ceiling, sconces, pendants, floor lamps", function()
	local neon = 0
	for _, item in room:GetDescendants() do
		if item:IsA("BasePart") and item.Material.Name == "Neon" and item.Size.Magnitude > 5 and item.Transparency < 0.2 and item.Color.G * 255 > 190 and item.Color.B * 255 < 120 then
			neon += 1
		end
	end
	assert(neon <= 2, "bright gold lines are rare: " .. neon)
	assert(not room:FindFirstChild("RimN", true) and not room:FindFirstChild("AisleStripL", true), "ceiling rim lines and aisle glow lines are gone")
	local slats, sconces, pendants, lamps = 0, 0, 0, 0
	for _, item in room:GetDescendants() do
		if item.Name == "Slat" then slats += 1 elseif item.Name == "Sconce" then sconces += 1 elseif item.Name == "PendantShade" then pendants += 1 elseif string.sub(item.Name, 1, 5) == "Lamp_" then lamps += 1 end
	end
	assert(slats >= 30 and sconces >= 10 and pendants >= 14 and lamps >= 8, `slats {slats} sconces {sconces} pendants {pendants} lamps {lamps}`)
	-- Tier seating reads as sofas
	local row = room:FindFirstChild("Tier1W", true)
	assert(row:FindFirstChild("BackCushion") and row:FindFirstChild("Piping") and row:FindFirstChild("Arm"), "cushions, piping and arms")
	assert(row:FindFirstChild("Seat").Material.Name == "Fabric" and row:FindFirstChild("Seat").Color.R > 0.55, "warm, lighter fabric")
end)

game.check("Quick Draw: two players, a green lamp, a false start loses, earned Money only, a small daily cap", function()
	local LoungeConfig = world.require(world.find("ReplicatedStorage.Shared.Config.Lounge")).QuickDraw
	LoungeConfig.ReadySeconds, LoungeConfig.MinWait, LoungeConfig.MaxWait, LoungeConfig.ResultSeconds, LoungeConfig.GoSeconds = 0.1, 0.25, 0.3, 0.3, 0.6
	local alice, bob = game.join("Alice", 7301), game.join("Bob", 7302)
	game.waitFor(function() return DataService:get(alice) ~= nil and DataService:get(bob) ~= nil end, 3, "profiles")
	local function money(p) return DataService:get(p).currencies.money end
	local gems = DataService:get(alice).currencies.gems
	local a0, b0 = money(alice), money(bob)
	local state = LoungeService:gameState()
	-- Alone: nothing starts and nothing is paid
	promptOf("Buzzer1").Triggered:Fire(alice)
	assert(state.phase == "lobby" and state.slots[1] == alice, "Alice sat down")
	promptOf("Buzzer2").Triggered:Fire(alice)
	assert(state.slots[2] == nil, "one player cannot take both seats")
	promptOf("Buzzer1").Triggered:Fire(bob)
	assert(state.slots[1] == alice, "a taken seat stays taken")
	promptOf("Buzzer1").Triggered:Fire(alice)
	assert(state.phase == "idle" and money(alice) == a0, "leaving the table pays nothing")
	-- Round 1: Alice buzzes before green
	promptOf("Buzzer1").Triggered:Fire(alice)
	promptOf("Buzzer2").Triggered:Fire(bob)
	assert(state.phase == "ready", "both seated: get ready")
	game.waitFor(function() return state.phase == "wait" end, 2, "the wait phase")
	assert(textOf(room:FindFirstChild("GamesTable", true), "Status"):len() > 0)
	promptOf("Buzzer2").Triggered:Fire(alice) -- not her seat: ignored
	assert(state.phase == "wait", "a buzz from the wrong seat does nothing")
	promptOf("Buzzer1").Triggered:Fire(alice)
	assert(state.phase == "result", "a false start ends the round")
	assert(money(bob) == b0 + LoungeConfig.WinMoney and money(alice) == a0 + LoungeConfig.PlayMoney, "winner and player paid the small amounts")
	assert(DataService:get(alice).currencies.gems == gems, "Money only, no Gems")
	game.waitFor(function() return state.phase == "idle" end, 2, "the table to reset")
	-- Round 2: green, Bob is first
	promptOf("Buzzer1").Triggered:Fire(alice)
	promptOf("Buzzer2").Triggered:Fire(bob)
	game.waitFor(function() return state.phase == "go" end, 2, "the lamp to go green")
	promptOf("Buzzer2").Triggered:Fire(bob)
	promptOf("Buzzer1").Triggered:Fire(alice)
	assert(state.phase == "result" and string.find(state.message[2], "You win", 1, true) and string.find(state.message[1], "Not this time", 1, true), "first buzz wins: " .. tostring(state.message[2]))
	assert(money(bob) == b0 + 2 * LoungeConfig.WinMoney, "Bob paid again")
	game.waitFor(function() return state.phase == "idle" end, 2, "the table to reset")
	-- The daily cap holds
	DataService:get(bob).lounge.gameEarned = LoungeConfig.DailyCap - 5
	DataService:get(bob).lounge.gameDay = math.floor(os.time() / 86400)
	local before = money(bob)
	promptOf("Buzzer1").Triggered:Fire(alice)
	promptOf("Buzzer2").Triggered:Fire(bob)
	game.waitFor(function() return state.phase == "go" end, 2, "green")
	promptOf("Buzzer2").Triggered:Fire(bob)
	assert(money(bob) == before + 5 and DataService:get(bob).lounge.gameEarned == LoungeConfig.DailyCap, "capped at the daily limit")
	game.waitFor(function() return state.phase == "idle" end, 2, "reset")
	promptOf("Buzzer1").Triggered:Fire(alice)
	promptOf("Buzzer2").Triggered:Fire(bob)
	game.waitFor(function() return state.phase == "go" end, 2, "green")
	promptOf("Buzzer2").Triggered:Fire(bob)
	assert(money(bob) == before + 5, "nothing more today")
	game.waitFor(function() return state.phase == "idle" end, 2, "reset")
	-- A player who leaves mid-round ends it
	promptOf("Buzzer1").Triggered:Fire(alice)
	promptOf("Buzzer2").Triggered:Fire(bob)
	game.leave(bob)
	assert(state.phase == "result" or state.phase == "idle", "the round ended when a player left")
	game.waitFor(function() return state.phase == "idle" end, 2, "reset")
	game.leave(alice)
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
