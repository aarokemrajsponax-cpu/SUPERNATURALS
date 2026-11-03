-- The twenty battleground chambers, their galleries and the concourse, against the real
-- server services:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/chambers_test.luau build/game.rbxl
-- Covers: nothing stands until a match reserves a chamber; 20 concurrent reservations work
-- and the 21st is refused (nil) without errors; themes are honoured; every chamber is
-- sealed (four walls, a ceiling), has a gallery with a window, seating, a spawn and a
-- return prompt, and stays inside the part budget; releasing tears everything down; the
-- concourse has 20 gates with Watch prompts and status screens; a real duel shows IN MATCH
-- on its gate with names and mode, a spectator is taken to the gallery by the Watch hook
-- and brought back by the return prompt.

local process = require("@lune/process")

local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl")
local world, task, services = game.world, game.task, game.services
local ArenaService = services.ArenaService
local MatchConfig = game.MatchConfig
local CHAMBERS = ArenaService.Chambers

local function descendants(root, name: string, className: string?)
	local found = {}
	for _, item in root:GetDescendants() do
		if item.Name == name and (className == nil or item:IsA(className)) then
			table.insert(found, item)
		end
	end
	return found
end

local function count(root, prefix: string): number
	local total = 0
	for _, item in root:GetDescendants() do
		if string.sub(item.Name, 1, #prefix) == prefix then
			total += 1
		end
	end
	return total
end

local function textOf(root, name: string): string
	for _, item in root:GetDescendants() do
		if item.Name == name and item:IsA("TextLabel") then
			return item.Text
		end
	end
	return ""
end

game.check("nothing stands until a match reserves a chamber; the concourse is built", function()
	assert(#world.workspace.Arenas:GetChildren() == 0, "no chamber yet")
	assert(ArenaService:activeCount() == 0, "none active")
	local concourse = world.workspace:FindFirstChild("Concourse")
	assert(concourse, "a Concourse model")
	for number = 1, CHAMBERS.Count do
		local tag = string.format("%02d", number)
		assert(concourse:FindFirstChild("Gate" .. tag, true), "gate " .. tag)
		assert(concourse:FindFirstChild("GateScreen" .. tag, true), "status screen " .. tag)
	end
	local parts, prompts = 0, 0
	for _, item in concourse:GetDescendants() do
		if item:IsA("BasePart") then
			parts += 1
			assert(item.Anchored, item.Name .. " anchored")
		elseif item:IsA("ProximityPrompt") then
			prompts += 1
		end
	end
	local Concourse = world.require(world.find("ServerScriptService.Server.World.Concourse"))
	assert(parts <= Concourse.PartBudget, `{parts} concourse parts (budget {Concourse.PartBudget})`)
	assert(prompts == 22, `{prompts} prompts: 20 Watch, find a fight, return to hub`)
	assert((Concourse.Center - game.Vector3.zero).Magnitude > 400, "far from the hub")
	print(`     concourse: {parts} parts`)
	assert(textOf(concourse, "State") == "FREE", "gates start FREE")
end)

local reserved = {}
game.check("20 concurrent reservations work and the 21st is refused", function()
	local order = MatchConfig.ArenaOrder
	for number = 1, CHAMBERS.Count do
		local theme = order[(number - 1) % #order + 1]
		local arena = ArenaService:reserve(theme)
		assert(arena, `chamber {number} reserved`)
		assert(arena.slot == number and arena.id == theme, `slot {number} holds {theme}, got {arena.id}`)
		table.insert(reserved, arena)
	end
	assert(ArenaService:activeCount() == CHAMBERS.Count, "twenty active")
	assert(ArenaService:reserve("DigitalGrid") == nil, "the 21st is refused")
	assert(ArenaService:reserve() == nil, "and a random one too")
	assert(ArenaService:activeCount() == CHAMBERS.Count, "still twenty")
	local centers = {}
	for _, arena in reserved do
		local key = `{arena.center.X},{arena.center.Z}`
		assert(not centers[key], "distinct centre " .. key)
		centers[key] = true
		assert(arena.center.X >= 800, "well away from the hub and the concourse")
	end
	assert(#world.workspace.Arenas:GetChildren() == CHAMBERS.Count, "twenty models")
end)

game.check("every chamber is sealed, themed, within budget and has a gallery", function()
	for _, arena in reserved do
		local model = arena.model
		assert(string.find(model.Name, arena.id, 1, true), "model named for its theme: " .. model.Name)
		assert(#descendants(model, "ShellWall", "BasePart") >= 6, "walls")
		assert(#descendants(model, "Ceiling", "BasePart") == 1, "a ceiling")
		-- Walls reach the ceiling on every side: check the roof sits at WallHeight
		local ceiling = descendants(model, "Ceiling", "BasePart")[1]
		local underside = ceiling.CFrame.Position.Y - ceiling.Size.Y / 2
		assert(math.abs(underside - (arena.floorY + MatchConfig.Arena.WallHeight)) < 0.01, "ceiling at wall height")
		local glass = descendants(model, "GalleryGlass", "BasePart")[1]
		assert(glass and glass.CanCollide and glass.Transparency > 0.5 and glass.Transparency < 0.9, "a collidable glass window")
		assert(#descendants(model, "FrontSeat", "BasePart") >= 1 and #descendants(model, "RearSeat", "BasePart") >= 1, "seating")
		assert(#descendants(model, "ReturnPrompt", "ProximityPrompt") == 1, "a return prompt")
		assert(#descendants(model, "ReturnTerminal", "BasePart") == 1, "a return terminal")
		assert(arena.gallerySpawn, "a gallery spawn")
		local deck = descendants(model, "GalleryDeck", "BasePart")[1]
		assert(arena.gallerySpawn.Position.Y > deck.CFrame.Position.Y and arena.gallerySpawn.Position.Y < arena.floorY + 24, "spawn stands in the gallery")
		assert((arena.gallerySpawn.Position - arena.center).Magnitude > 55, "the gallery is outside the fighting floor")
		assert(#arena.spawns == 4, "four fighter spawns")
		local parts = 0
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") then
				parts += 1
				assert(item.Anchored, item.Name .. " anchored")
			end
		end
		assert(parts <= CHAMBERS.PartBudget, `{arena.id}: {parts} parts`)
	end
end)

game.check("the concourse shows twenty busy gates with Watch prompts", function()
	local concourse = world.workspace.Concourse
	local busy = 0
	for _, item in concourse:GetDescendants() do
		if item:IsA("ProximityPrompt") and item.ActionText == "Watch" and item.Enabled then
			busy += 1
		end
	end
	assert(busy == CHAMBERS.Count, `{busy} Watch prompts enabled`)
	assert(textOf(concourse, "State") == "IN MATCH", "gates read IN MATCH")
end)

game.check("releasing tears every chamber down with no leftovers", function()
	for _, arena in reserved do
		ArenaService:release(arena)
		assert(arena.model == nil and arena.gallerySpawn == nil and not arena.inUse, "released")
	end
	table.clear(reserved)
	assert(#world.workspace.Arenas:GetChildren() == 0, "nothing left in the Arenas folder")
	assert(ArenaService:activeCount() == 0, "none active")
	ArenaService:release(ArenaService:getChamber(1)) -- releasing twice is harmless
	assert(ArenaService:reserve("RuinedFortress").slot == 1, "number 1 is free again")
	ArenaService:release(ArenaService:getChamber(1))
	local concourse = world.workspace.Concourse
	for _, item in concourse:GetDescendants() do
		if item:IsA("ProximityPrompt") and item.ActionText == "Watch" then
			assert(not item.Enabled, "no Watch prompt on a free gate")
		end
	end
	assert(textOf(concourse, "Count") == "20 of 20", "summary says all free")
end)

game.check("a real duel fills its gate; a spectator is taken to the gallery and back", function()
	local alice, bob, carol = game.join("Alice"), game.join("Bob"), game.join("Carol")
	game.request("MatchRequest", alice, "Queue", "Duel", { arena = "SoulFoundry" })
	game.request("MatchRequest", bob, "Queue", "Duel", { arena = "SoulFoundry" })
	game.waitFor(function()
		return services.MatchService:getMatchOf(game.fighter(alice)) ~= nil
	end, 2, "the duel to start")
	local arena = ArenaService:getChamber(1)
	assert(arena.inUse and arena.id == "SoulFoundry", "chamber 1 holds the Soul Foundry")
	local concourse = world.workspace.Concourse
	local screen = concourse:FindFirstChild("GateScreen01", true)
	assert(textOf(screen, "State") == "IN MATCH", "gate 01 reads IN MATCH")
	-- Names arrive with the next one-second refresh (or when the fight begins)
	game.waitFor(function()
		return string.find(textOf(screen, "People"), "Alice", 1, true) ~= nil
	end, 3, "the gate to name the fighters")
	assert(string.find(textOf(screen, "Detail"), "Duel", 1, true), "and the mode")
	assert(textOf(concourse, "Count") == "19 of 20", "summary counts one busy")

	-- Watch
	ArenaService:watchChamber(carol, 1)
	task.wait(0.1)
	local position = game.fighter(carol).root.Position
	assert((position - arena.gallerySpawn.Position).Magnitude < 4, "Carol stands in the gallery")
	assert(carol:GetAttribute("SNSpectating") ~= nil, "and is spectating the match")
	-- A fighter can't use Watch
	local before = game.fighter(alice).root.Position
	ArenaService:watchChamber(alice, 1)
	assert((game.fighter(alice).root.Position - before).Magnitude < 1, "fighters stay in the fight")
	-- A free gate does nothing
	ArenaService:watchChamber(carol, 7)
	assert((game.fighter(carol).root.Position - arena.gallerySpawn.Position).Magnitude < 4, "free gate ignored")

	-- Return
	local prompt = descendants(arena.model, "ReturnPrompt", "ProximityPrompt")[1]
	prompt.Triggered:Fire(carol)
	task.wait(0.1)
	assert(carol:GetAttribute("SNSpectating") == nil, "Carol stopped spectating")
	local back = game.fighter(carol).root.Position
	assert((back - world.workspace.Concourse:FindFirstChild("Floor").CFrame.Position).Magnitude < 130, "Carol is back in the concourse")

	-- The hub door's destination
	game.request("MatchRequest", carol, "Travel", "Lobby")
	task.wait(0.1)
	game.request("MatchRequest", carol, "Travel", "Concourse")
	task.wait(0.1)
	assert((game.fighter(carol).root.Position - ArenaService:concourseSpawn().Position).Magnitude < 12, "Travel:Concourse lands at the concourse entrance")

	services.MatchService:endAll()
	game.waitFor(function()
		return ArenaService:activeCount() == 0
	end, 4, "the chamber to be released")
	assert(#world.workspace.Arenas:GetChildren() == 0, "the chamber is gone after the match")
end)

process.exit(if game.finish() == 0 then 0 else 1)
