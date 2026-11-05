-- The release switch (Powers.Unreleased): the Animal Shapeshifter is held for a later update.
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/release_test.luau build/game.rbxl
-- A player cannot select, queue with, try, be assigned or face it as a CPU; the owner (by UserId)
-- still can; a saved profile that has it selected loads as Strong Dude; the hall shows a veiled
-- figure with the CLASSIFIED plaque. The Showcase and Play window lists are in smoke_release.luau.

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl")
local task = game.task
local services, check, request, world = game.services, game.check, game.request, game.world
local Protocol = world.require(world.find("ReplicatedStorage.Shared.Protocol"))
local Powers = world.require(world.find("ReplicatedStorage.Shared.Powers"))
local OwnerConfig = world.require(world.find("ServerScriptService.Server.OwnerConfig"))
local Statues = world.require(world.find("ServerScriptService.Server.World.Statues"))
local Action = Protocol.PowerAction
local ID = "Shapeshifter"
local MESSAGE = "The Animal Shapeshifter arrives in a later update."

game.flatGround(0)

local alice = game.join("Alice")
local owner = game.join("AJKR", OwnerConfig.UserIds[1])

local function ask(player, ...)
	task.wait(0.4) -- stay under the request rate limit
	local mark = game.mark()
	request("PowerRequest", player, ...)
	task.wait(0.05)
	local replies = game.sentSince(mark, "DataEvent", Protocol.DataEvent.SelectionResult, player)
	return replies[#replies]
end
local function count(map): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

check("the switch and helpers", function()
	assert(Powers.Unreleased[ID] == true, "Shapeshifter is held")
	assert(#Powers.Order == 8 and Powers.get(ID) ~= nil, "the definition and order stay")
	local list = Powers.released()
	assert(#list == 7 and not table.find(list, ID), "seven released")
	assert(list[1] == "StrongDude" and list[3] == "MachineMaster" and list[7] == "Grandmaster", "same order")
	assert(not Powers.isReleased(ID) and Powers.isReleased("Ghost") and not Powers.isReleased("Nope"))
end)

check("a player cannot select the Shapeshifter", function()
	for _, action in { Action.Select } do
		request("PowerRequest", alice, action, ID, 1)
	end
	task.wait(0.05)
	local reply = ask(alice, Action.Confirm, ID, 1)
	assert(reply and not reply.ok and reply.message == MESSAGE, reply and reply.message)
	assert(services.PowerService:_selected(alice).power == "StrongDude", "selection unchanged")
	assert(services.DataService:get(alice).selected.power == "StrongDude", "profile unchanged")
	local quote = ask(alice, Action.Quote, ID, 1)
	assert(quote and not quote.ok and quote.message == MESSAGE, "quote refused")
	local ok, reason = services.PowerService:check(alice, ID, 1)
	assert(not ok and reason == MESSAGE)
end)

check("a player cannot try it", function()
	local reply = ask(alice, Action.Trial, ID, 1)
	assert(reply and not reply.ok and reply.message == MESSAGE, reply and reply.message)
	local fighter = game.fighter(alice)
	assert(not (fighter.power and fighter.power.id == ID), "not equipped")
end)

check("a player cannot queue with it or face it as a CPU", function()
	local mark = game.mark()
	request("MatchRequest", alice, "Queue", "Practice", { cpuPower = ID })
	task.wait(0.1)
	assert(not services.MatchService:isQueued(alice), "no match from that request")
	assert(#game.sentSince(mark, "MatchEvent", "State", alice) == 0, "no match state sent")
	local reply = ask(alice, Action.Confirm, ID, 1)
	assert(reply and not reply.ok)
	for _ = 1, 300 do
		assert(services.MatchService:_cpuOptions({ cpuPower = "Random" }, alice).power ~= ID, "random pick")
		assert(services.MatchService:_cpuOptions({ cpuPower = ID }, alice).power ~= ID, "named pick")
	end
end)

check("the snapshot sent to a player lists seven fighters, the owner's eight", function()
	assert(count(services.PowerService:snapshot(alice).powers) == 7)
	assert(services.PowerService:snapshot(alice).powers[ID] == nil)
	assert(count(services.PowerService:snapshot(owner).powers) == 8)
end)

check("the owner can pick, try, and face it", function()
	local reply = ask(owner, Action.Confirm, ID, 1)
	assert(reply and reply.ok, reply and reply.message)
	assert(services.PowerService:_selected(owner).power == ID, "selected")
	local trial = ask(owner, Action.Trial, ID, 1)
	assert(trial == nil or trial.message ~= MESSAGE, "the trial is not refused as unreleased")
	local seen = false
	for _ = 1, 50 do
		if services.MatchService:_cpuOptions({ cpuPower = ID }, owner).power == ID then
			seen = true
			break
		end
	end
	assert(seen, "owner may choose it as the CPU")
	services.PowerService:equip(game.fighter(owner), ID, 1, Powers.defaultLoadout(ID, 1))
	assert(game.fighter(owner).power.id == ID, "equipped")
end)

check("a saved profile with it selected loads as Strong Dude", function()
	local data = services.DataService:get(alice)
	data.selected = { power = ID, degree = 2 }
	assert(services.PowerService:_selected(alice).power == "StrongDude", "selected falls back")
	local powerId, degree = services.PowerService:_resolveSelection(alice, false)
	assert(powerId == "StrongDude" and degree == 1, `resolved {powerId} {degree}`)
	services.PowerService:equip(game.fighter(alice), powerId, degree, Powers.defaultLoadout(powerId, degree))
	assert(game.fighter(alice).power.id == "StrongDude")
	-- and a real rejoin through the fighter setup
	game.leave(alice)
	alice = game.join("Alice2")
	assert(game.fighter(alice) ~= nil)
	local fresh = services.DataService:get(alice)
	fresh.selected = { power = ID, degree = 1 }
	assert(services.PowerService:_selected(alice).power == "StrongDude")
end)

check("the Fighter achievement counts seven", function()
	local Achievements = world.require(world.find("ReplicatedStorage.Shared.Config.Achievements"))
	for _, def in Achievements.List or Achievements do
		if type(def) == "table" and def.id == "fighters_all" then
			assert(def.goal == 7 and string.find(def.desc, "all seven fighters", 1, true), def.desc)
			return
		end
	end
	error("fighters_all not found")
end)

local function findStatue()
	for _, item in world.workspace:GetDescendants() do
		if item.Name == "Statue_" .. ID and item:IsA("Model") then
			return item
		end
	end
	return nil
end

local function plateTexts(model): { string }
	local texts = {}
	for _, item in model:GetDescendants() do
		if item:IsA("TextLabel") then
			table.insert(texts, item.Text)
		end
	end
	return texts
end

check("the hall has a veiled figure and the CLASSIFIED plaque on the Shapeshifter plinth", function()
	local model = Statues.build(ID, game.CFrame.new(0, 0, 0))
	assert(model:GetAttribute("Veiled") == true and model:GetAttribute("Codename") == "CLASSIFIED")
	assert(not model:GetAttribute("Fallback"), "carved, not the fallback figure")
	assert(model:FindFirstChild("Pedestal") and model:FindFirstChild("Figure") and model:FindFirstChild("Lights"))
	local cloth = 0
	for _, item in model.Figure:GetDescendants() do
		if item:IsA("BasePart") and item.Material == roblox.Enum.Material.Fabric then
			cloth += 1
		end
		assert(item.Name ~= "WolfSkull" and item.Name ~= "Pelt", "no wolf in the veiled figure")
	end
	assert(cloth >= 10, `draped cloth parts: {cloth}`)
	local texts = table.concat(plateTexts(model), "|")
	assert(string.find(texts, "TO BE REVEALED", 1, true), texts)
	assert(string.find(texts, "C L A S S", 1, true) or string.find(texts, "CLASSIFIED", 1, true), texts)
	assert(not string.find(texts, "CHIMERA", 1, true) and not string.find(texts, "ANIMAL", 1, true), "no reveal")
	local other = Statues.build("Ghost", game.CFrame.new(0, 0, 0))
	assert(other:GetAttribute("Veiled") == nil and other:GetAttribute("Codename") == "VEIL", "others are unchanged")
	local placed = findStatue()
	if placed then
		assert(placed:GetAttribute("Veiled") == true, "the built hall carries the veiled one")
	end
end)

process.exit(if game.finish() == 0 then 0 else 1)
