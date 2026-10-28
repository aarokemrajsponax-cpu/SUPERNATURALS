-- Smoke test for the themed arenas, the training hall and the arena picker:
--   lune run tests/smoke_arenas.luau build/arenas.rbxl
-- Server side: every theme builds in a slot and keeps the arena contract (flat
-- floor at floorY, invisible collidable barriers, four spawns inside, throwables
-- of weight 1, 2 and 3 with HomeCFrame, interaction points, a name sign, the
-- part budget, nothing unanchored, no scripts, terrain inside the slot), slots
-- are rebuilt for a new theme and reused for the same one, and the training
-- hall keeps its three dummy spots and throwables.
-- Client side: the Play window's arena picker lists Random and every arena,
-- remembers the choice, sends it with Queue, hides for the training ground and
-- fits on phone and desktop.

local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local Client = require("./smoke/Client")

local t = Client.load(process.args[1] or "build/arenas.rbxl")
local Engine, world = t.Engine, t.world
local Vector3 = roblox.Vector3

local MatchConfig = world.require(world.find("ReplicatedStorage.Shared.Config.Match"))
local Protocol = world.require(world.find("ReplicatedStorage.Shared.Protocol"))
local ARENA = MatchConfig.Arena
local Tags = Engine.services.CollectionService

local ArenaService
local services = {}

t.check("ArenaService starts: the training hall and the first arena", function()
	ArenaService = world.require(world.find("ServerScriptService.Server.Services.ArenaService"))
	services.ArenaService = ArenaService
	ArenaService:Init(services)
	ArenaService:Start()
	assert(world.workspace:FindFirstChild("Arenas"), "an Arenas folder")
	assert(world.workspace:FindFirstChild("TrainingGround"), "the training hall")
	assert(#MatchConfig.ArenaOrder == 5, "five arena themes")
	for _, id in MatchConfig.ArenaOrder do
		local entry = MatchConfig.Arenas[id]
		assert(entry and typeof(entry.name) == "string" and typeof(entry.description) == "string" and typeof(entry.color) == "Color3", id .. " has a name, description and colour")
	end
end)

-- Every check an arena of any theme must pass
local function checkContract(arena, id: string)
	local model = arena.model
	assert(arena.id == id, `theme id {arena.id}`)
	assert(arena.name == MatchConfig.Arenas[id].name, `display name {arena.name}`)
	assert(model and model.Parent == world.workspace.Arenas, "built into the Arenas folder")

	local parts, unanchored, scripts = 0, {}, 0
	local floor, barriers, signs = nil, {}, {}
	local weights = {}
	local interactions = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			parts += 1
			if not item.Anchored then
				table.insert(unanchored, item.Name)
			end
			if item.Name == "Floor" then
				floor = item
			elseif item.Name == "Barrier" then
				table.insert(barriers, item)
			end
			local weight = item:GetAttribute("Weight")
			if weight ~= nil then
				assert(Tags:HasTag(item, Protocol.Tag.Throwable), item.Name .. " is tagged Throwable")
				assert(typeof(item:GetAttribute("HomeCFrame")) == "CFrame", item.Name .. " has HomeCFrame")
				assert(#item:GetChildren() == 0, item.Name .. " carries nothing that would stay behind")
				weights[weight] = (weights[weight] or 0) + 1
			end
		elseif item:IsA("LuaSourceContainer") then
			scripts += 1
		elseif item:IsA("TextLabel") then
			table.insert(signs, item.Text)
		end
		local kind = item:GetAttribute("Interaction")
		if kind ~= nil then
			assert(kind == "Pylon" or kind == "Node" or kind == "Vent", "interaction kind " .. tostring(kind))
			assert(Tags:HasTag(item, Protocol.Tag.Interactive), item.Name .. " is tagged Interactive")
			table.insert(interactions, kind)
		end
	end
	assert(parts <= ARENA.PartBudget, `{parts} parts (budget {ARENA.PartBudget})`)
	assert(#unanchored == 0, "unanchored: " .. table.concat(unanchored, ", "))
	assert(scripts == 0, "no scripts in the arena")

	-- The floor: flat, the configured size (read positions from CFrame: the
	-- stand-in engine doesn't derive Position), centred, its top at floorY
	assert(floor, "a Floor part")
	assert(math.abs(floor.CFrame.Position.Y + floor.Size.Y / 2 - arena.floorY) < 0.01, "floor top at floorY")
	assert(math.abs(floor.Size.X - ARENA.Size.X) < 0.01 and math.abs(floor.Size.Z - ARENA.Size.Z) < 0.01, "floor is Arena.Size")
	assert((Vector3.new(floor.CFrame.Position.X, 0, floor.CFrame.Position.Z) - Vector3.new(arena.center.X, 0, arena.center.Z)).Magnitude < 0.01, "floor centred")
	assert(floor.CanCollide, "the floor collides")

	-- Invisible walls, tall and collidable (knockback splats fighters on them)
	assert(#barriers == 4, `{#barriers} barriers`)
	for _, barrier in barriers do
		assert(barrier.Transparency == 1 and barrier.CanCollide and barrier.Size.Y >= ARENA.WallHeight, "barriers are invisible, solid and tall")
	end

	-- Spawns: four, on the floor, inside the walls, facing the middle
	assert(#arena.spawns == 4, "four spawns")
	for _, spawn in arena.spawns do
		assert(ArenaService:contains(arena, spawn.Position, 4), "spawn inside the floor")
		assert(spawn.Position.Y > arena.floorY and spawn.Position.Y < arena.floorY + 6, "spawn just above the floor")
		local toCenter = (arena.center - spawn.Position) * Vector3.new(1, 0, 1)
		assert(spawn.LookVector:Dot(toCenter.Unit) > 0.95, "spawn faces the middle")
	end

	assert((weights[1] or 0) >= 2 and (weights[2] or 0) >= 1 and (weights[3] or 0) >= 1, "light, heavy and enormous throwables")
	assert(#interactions >= 2 and #interactions <= 4, `{#interactions} interaction points`)
	local named = false
	for _, text in signs do
		named = named or string.upper(text) == string.upper(arena.name)
	end
	assert(named, "a sign with the arena's name")
	return parts
end

-- Terrain each theme fills must stay inside its slot's scenery box (sideways;
-- a stud of slack for rounding)
local function checkTerrain(arena, fromOp: number)
	local low, high = arena.center + ARENA.SceneryMin, arena.center + ARENA.SceneryMax
	for index = fromOp, #Engine.terrainOps do
		local op = Engine.terrainOps[index]
		if op.material ~= roblox.Enum.Material.Air then
			local center, extent
			if op.kind == "Ball" then
				center, extent = op.center, Vector3.new(op.radius, 0, op.radius)
			else
				local size = op.size or Vector3.new(op.radius * 2, op.height, op.radius * 2)
				local frame = op.cframe
				center = frame.Position
				local function along(axis: string): number
					return math.abs(frame.RightVector[axis]) * size.X / 2 + math.abs(frame.UpVector[axis]) * size.Y / 2 + math.abs(frame.LookVector[axis]) * size.Z / 2
				end
				extent = Vector3.new(along("X"), 0, along("Z"))
			end
			local ok = center.X - extent.X >= low.X - 1 and center.X + extent.X <= high.X + 1 and center.Z - extent.Z >= low.Z - 1 and center.Z + extent.Z <= high.Z + 1
			assert(ok, `{op.kind} terrain at {center} (reach {extent}) leaves the slot`)
		end
	end
end

for _, id in MatchConfig.ArenaOrder do
	t.check(`{id} builds and keeps the arena contract`, function()
		local fromOp = #Engine.terrainOps + 1
		local arena = ArenaService:reserve(id)
		assert(arena, "a free slot")
		local ok, result = pcall(function()
			checkTerrain(arena, fromOp)
			return checkContract(arena, id)
		end)
		-- Hand the slot back whatever happened, so one failure doesn't cascade
		ArenaService:release(arena)
		assert(ok, result)
		print(`     {id}: {result} parts`)
	end)
end

t.check("slots are reused for the same theme and rebuilt for another", function()
	local first = ArenaService:reserve("DigitalGrid")
	local model = first.model
	ArenaService:release(first)
	local again = ArenaService:reserve("DigitalGrid")
	assert(again == first and again.model == model, "the same theme reuses the standing arena")
	ArenaService:release(again)
	local other = ArenaService:reserve("SoulFoundry")
	assert(other == first and other.id == "SoulFoundry" and other.model ~= model and model.Parent == nil, "another theme rebuilds the free slot")
	local second = ArenaService:reserve("SoulFoundry")
	assert(second and second ~= other and second.slot == 2, "a busy slot is never rebuilt: a second slot opens")
	assert((second.center - other.center).Magnitude == ARENA.Spacing, "slots keep their spacing")
	local random = ArenaService:reserve("Random")
	assert(random and MatchConfig.Arenas[random.id], "Random picks a real theme")
	local unknown = ArenaService:reserve("NoSuchArena")
	assert(unknown == nil or MatchConfig.Arenas[unknown.id], "unknown ids fall back to a real theme")
	for _, arena in { other, second, random, unknown } do
		if arena then
			ArenaService:release(arena)
		end
	end
end)

t.check("the training hall keeps three dummy spots and things to throw", function()
	local hall = world.workspace.TrainingGround
	local spots = ArenaService:trainingDummySpots()
	assert(#spots == 3, "three dummy spots")
	local center = MatchConfig.TrainingGround.Center
	for _, spot in spots do
		local offset = spot.Position - center
		assert(math.abs(offset.X) < 17 and math.abs(offset.Z) < 22, "spots on the hall's floor")
	end
	local throwables, parts = 0, 0
	for _, item in hall:GetDescendants() do
		if item:IsA("BasePart") then
			parts += 1
			assert(item.Anchored, item.Name .. " anchored")
			if Tags:HasTag(item, Protocol.Tag.Throwable) then
				throwables += 1
			end
		end
	end
	assert(throwables >= 3, "throwables in the hall")
	assert(parts <= ARENA.PartBudget, `{parts} parts`)
	print(`     training hall: {parts} parts`)
end)

-- Client: the arena picker ------------------------------------------------------------------

t.check("the Play window's arena picker sends the choice with Queue", function()
	local ui = t.startUI()
	local gui, Shell = ui.gui, ui.Shell
	Shell.open("Play")
	local play = t.findNamed(gui, "Window_Play")
	assert(play and play.Visible, "the Play window opens")
	t.press(t.findNamed(play, "Mode_Duel"))
	local picker = t.findNamed(play, "ArenaPicker")
	assert(picker and t.findNamed(play, "MatchOptions").Visible, "the picker shows for a duel")
	assert(t.findNamed(picker, "Arena_Random"), "a Random choice")
	for _, id in MatchConfig.ArenaOrder do
		assert(t.findNamed(picker, "Arena_" .. id), "a chip for " .. id)
		assert(t.findText(picker, MatchConfig.Arenas[id].name), "named " .. MatchConfig.Arenas[id].name)
	end
	-- Random is the default
	local start = #Engine.sent
	t.press(t.findNamed(play, "Action"))
	local sent = t.sentSince(start, "MatchRequest", "Queue")
	assert(#sent == 1 and sent[1].args[2] == "Duel" and sent[1].args[3].arena == "Random", "queues with Random by default")
	Engine.task.wait(0.7)

	Shell.open("Play")
	t.press(t.findNamed(play, "Arena_RuinedFortress"))
	assert(t.findText(play, MatchConfig.Arenas.RuinedFortress.description), "the chosen arena's description shows")
	start = #Engine.sent
	t.press(t.findNamed(play, "Action"))
	sent = t.sentSince(start, "MatchRequest", "Queue")
	assert(#sent == 1 and sent[1].args[3].arena == "RuinedFortress", "the picked arena goes with Queue")
	Engine.task.wait(0.7)

	-- Remembered next time, used for CPU practice too, hidden for training
	Shell.open("Play")
	t.press(t.findNamed(play, "Mode_Practice"))
	start = #Engine.sent
	t.press(t.findNamed(play, "Action"))
	sent = t.sentSince(start, "MatchRequest", "Queue")
	assert(#sent == 1 and sent[1].args[2] == "Practice" and sent[1].args[3].arena == "RuinedFortress", "practice uses the remembered arena")
	Engine.task.wait(0.7)
	Shell.open("Play")
	t.press(t.findNamed(play, "Mode_Training"))
	assert(not t.findNamed(play, "MatchOptions").Visible, "no arena picker for the training ground")
	t.press(t.findNamed(play, "Mode_Duel"))
	Shell.close()
end)

t.check("the picker fits on phone and desktop", function()
	local ui = t.startUI()
	local gui, Shell = ui.gui, ui.Shell
	for _, size in { { 1920, 1080 }, { 667, 375 } } do
		t.setScreen(size[1], size[2])
		Shell.open("Play")
		local play = t.findNamed(gui, "Window_Play")
		t.press(t.findNamed(play, "Mode_Duel"))
		t.auditLayout(play, `Play {size[1]}x{size[2]}`)
		Shell.close()
	end
end)

t.finish()
