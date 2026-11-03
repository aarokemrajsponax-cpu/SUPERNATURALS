-- Phases: evolving mid-match (docs/specs/SelectionContract.md). Runs the real server services:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/phase_test.luau build/game.rbxl

local process = require("@lune/process")

local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl")
local task, Vector3 = game.task, game.Vector3
local services, check, request = game.services, game.check, game.request
local Protocol = game.world.require(game.world.find("ReplicatedStorage.Shared.Protocol"))
local Selection = game.world.require(game.world.find("ReplicatedStorage.Shared.Config.Selection"))
local MatchConfig = game.world.require(game.world.find("ReplicatedStorage.Shared.Config.Match"))
local OwnerConfig = game.world.require(game.world.find("ServerScriptService.Server.OwnerConfig"))
local Powers = game.world.require(game.world.find("ReplicatedStorage.Shared.Powers"))
local Attribute = Protocol.Attribute

game.flatGround(0)
for _, mode in MatchConfig.Modes do
	mode.Countdown = 0.3
	mode.Duration = 60
	mode.ResultsDuration = 0.4
end

local FEE2, FEE3 = Selection.priceFor("StrongDude", 2), Selection.priceFor("StrongDude", 3)
local alice
local function money(player)
	return services.DataService:get(player).currencies.money
end
local function setMoney(player, amount)
	services.DataService:get(player).currencies.money = amount
end
local function unlock(player, powerId, ...)
	local degrees = {}
	for _, degree in { ... } do
		degrees[tostring(degree)] = true
	end
	services.DataService:get(player).powers[powerId] = { xp = 0, degrees = degrees, abilities = {}, owned = true }
end
local function lastResult(player)
	local result = game.lastSent("DataEvent", Protocol.DataEvent.SelectionResult, player)
	return result
end
-- Sends Evolve and returns the reply (nil when the server sent none)
local function evolve(player, ...)
	task.wait(0.4) -- stay under the request rate limit
	local mark = game.mark()
	request("PowerRequest", player, "Evolve", ...)
	task.wait(0.05)
	local replies = game.sentSince(mark, "DataEvent", Protocol.DataEvent.SelectionResult, player)
	return replies[#replies]
end
local function startPractice(player, cpuDifficulty)
	request("MatchRequest", player, "Queue", "Practice", { cpuPower = "StrongDude", cpuDifficulty = cpuDifficulty or "Normal" })
	game.waitFor(function()
		local state = game.lastSent("MatchEvent", "State", player)
		return state ~= nil and state.mode == "Practice" and state.phase == "Active"
	end, 4, "practice to begin")
end
local function endMatch(player)
	services.MatchService:endAll()
	game.waitFor(function()
		return player:GetAttribute("MatchId") == nil
	end, 4, "the match to finish")
	task.wait(0.3)
end
local function cpuOf()
	for _, candidate in services.CharacterService:all() do
		if candidate.npc and candidate.power and not candidate.trainingDummy then
			return candidate
		end
	end
	return nil
end
local function mine()
	return game.fighter(alice)
end

check("fees are meaningful but affordable: a quarter to a half of a ~75 Money match, premium a little more", function()
	for degree = 2, 4 do
		local fee = Selection.priceFor("StrongDude", degree)
		assert(fee >= 18 and fee <= 38, `standard fee {fee}`)
	end
	assert(Selection.priceFor("StrongDude", 1) == 0, "phase 1 is free")
	for _, id in { "Corruption", "Syntax", "Admin" } do
		for degree = 2, 3 do
			assert(Selection.priceFor(id, degree, true) > Selection.priceFor("StrongDude", degree), id .. " pays more")
			assert(Selection.priceFor(id, degree, true) <= 50, id .. " stays affordable")
		end
	end
	assert(Selection.Currency == "money", "money only")
end)

check("evolving is refused outside a match or training, and takes nothing", function()
	alice = game.join("Alice")
	game.waitFor(function()
		return mine() and mine().power ~= nil
	end, 2, "a power")
	unlock(alice, "StrongDude", 2)
	setMoney(alice, 500)
	mine().power.meter = 100
	local reply = evolve(alice)
	assert(reply and not reply.ok and reply.code == "NOT_FIGHTING", "refused in the lobby: " .. tostring(reply and reply.code))
	assert(money(alice) == 500 and mine().power.degree == 1, "nothing changed")
end)

check("the pre-match confirm never charges, and a match starts in Phase 1", function()
	setMoney(alice, 500)
	-- A saved higher degree (chosen before the match, free) still starts the match in Phase 1
	request("PowerRequest", alice, "Confirm", "StrongDude", 2)
	task.wait(0.05)
	assert(lastResult(alice).charged == 0 and mine().power.degree == 2, "confirm is free")
	startPractice(alice)
	local fighter = mine()
	assert(money(alice) == 500, "nothing charged to enter: " .. money(alice))
	assert(fighter.power.degree == 1, "Phase 1, got " .. fighter.power.degree)
	assert(fighter.model:GetAttribute(Attribute.PhaseNumber) == 1, "attribute")
	assert(fighter.model:GetAttribute(Attribute.PhaseMeter) == 0, "empty meter")
	assert(fighter.model:GetAttribute(Attribute.PhaseFee) == FEE2, "next fee published")
end)

check("combat fills the Phase meter for both sides", function()
	local me, cpu = mine(), cpuOf()
	assert(cpu, "a CPU")
	local before, cpuBefore = me.power.meter, cpu.power.meter
	local tries = 0
	while me.power.meter == before and tries < 40 do
		game.faceOff(me, cpu, 3)
		request("CombatRequest", alice, "Light")
		tries += 1
		task.wait(0.25)
	end
	assert(me.power.meter > before, "dealing hits fills the meter")
	assert(cpu.power.meter > cpuBefore, "taking hits fills it too")
	assert(me.power.meter <= Selection.Phase.MeterMax, "capped")
end)

check("without a full meter evolving is refused and takes nothing", function()
	local me = mine()
	me.power.meter = 40
	local reply = evolve(alice)
	assert(reply and reply.code == "METER_NOT_FULL" and reply.charged == 0, "meter: " .. tostring(reply and reply.code))
	assert(money(alice) == 500 and me.power.degree == 1 and me.power.meter == 40, "nothing changed")
end)

check("without Money it is refused, nothing taken, meter kept", function()
	local me = mine()
	me.power.meter = 100
	setMoney(alice, FEE2 - 1)
	local reply = evolve(alice)
	assert(reply and reply.code == "CANT_AFFORD", "afford: " .. tostring(reply and reply.code))
	assert(money(alice) == FEE2 - 1 and me.power.degree == 1 and me.power.meter == 100, "nothing changed")
end)

check("a locked degree is refused", function()
	local me = mine()
	me.power.meter = 100
	setMoney(alice, 500)
	unlock(alice, "StrongDude") -- nothing above Phase 1
	local reply = evolve(alice)
	assert(reply and reply.code == "DEGREE_LOCKED", "locked: " .. tostring(reply and reply.code))
	assert(money(alice) == 500 and me.power.degree == 1, "nothing changed")
	unlock(alice, "StrongDude", 2)
end)

check("junk Evolve requests are refused without charging", function()
	local me = mine()
	me.power.meter = 100
	setMoney(alice, 500)
	for _, junk in { "StrongDude", 2, true, {}, { power = "Ghost" }, math.huge } do
		local reply = evolve(alice, junk)
		assert(reply and reply.code == "BAD_REQUEST", "junk refused: " .. tostring(reply and reply.code))
	end
	assert(money(alice) == 500 and me.power.degree == 1 and me.power.meter == 100, "nothing changed")
end)

check("evolving charges the fee exactly once, swaps the kit and keeps cooldowns, charge and loadout", function()
	local me = mine()
	me.power.meter = 100
	setMoney(alice, 500)
	me.power.ult = 42
	local ready = game.world.workspace:GetServerTimeNow() + 30
	me.power.cooldowns.TitanGrip = ready
	local mark = game.mark()
	local reply = evolve(alice)
	assert(reply and reply.ok and reply.charged == FEE2, "evolved: " .. tostring(reply and reply.code))
	assert(money(alice) == 500 - FEE2, "charged once: " .. money(alice))
	assert(me.power.degree == 2 and me.model:GetAttribute(Attribute.Degree) == 2, "Phase 2")
	assert(me.model:GetAttribute(Attribute.PhaseNumber) == 2, "phase attribute")
	assert(me.power.meter == 0 and me.model:GetAttribute(Attribute.PhaseMeter) == 0, "meter reset")
	assert(me.power.cooldowns.TitanGrip == ready, "cooldown kept")
	assert(me.power.ult == 42, "ultimate charge kept")
	assert(table.find(me.power.loadout, "Groundbreaker") and table.find(me.power.loadout, "TitanGrip"), "loadout kept")
	assert(me.humanoid.MaxHealth == game.world.require(game.world.find("ReplicatedStorage.Shared.Powers")).combatProfile("StrongDude", 2).MaxHealth, "new stats")
	assert(me.model:GetAttribute(Attribute.TransformUntil) ~= nil, "transformation window")
	assert(me.state.armorHits > 0, "hyper-armour")
	local events = game.sentSince(mark, "CombatEvent", Protocol.CombatEvent.Transform)
	assert(#events >= 1 and events[1].to == 2 and events[1].from == 1 and events[1].power == "StrongDude", "transform event")
	-- A second press in the same instant takes nothing more
	local again = evolve(alice)
	assert(again and not again.ok and money(alice) == 500 - FEE2, "no double charge")
end)

check("after the window the next phase works, the new abilities run, and the top phase is enforced", function()
	local me = mine()
	task.wait(Selection.Phase.TransformTime + 0.2)
	assert(me.model:GetAttribute(Attribute.TransformUntil) == nil, "window closed")
	me.power.meter = 100
	setMoney(alice, 500)
	local locked = evolve(alice)
	assert(locked and locked.code == "DEGREE_LOCKED", "phase 3 still locked")
	unlock(alice, "StrongDude", 2, 3)
	local reply = evolve(alice)
	assert(reply and reply.ok and reply.charged == FEE3 and money(alice) == 500 - FEE3, "phase 3 for its fee")
	assert(me.power.degree == 3, "Phase 3")
	assert(table.find(me.power.loadout, "SeismicFissure"), "the new degree's ability is on the bar: " .. table.concat(me.power.loadout, ","))
	task.wait(Selection.Phase.TransformTime + 0.2)
	-- The degree-3 ability works (a Degree 1 kit would refuse it)
	local cpu = cpuOf()
	game.faceOff(me, cpu, 8)
	me.power.resource = me.power.resourceMax
	me.power.cooldowns.SeismicFissure = 0
	me.state.attack = nil
	me.state.stunUntil = -math.huge
	services.CharacterService:refresh(me)
	request("AbilityRequest", alice, "SeismicFissure", { direction = (cpu.root.Position - me.root.Position).Unit, point = cpu.root.Position })
	task.wait(0.1)
	assert((me.power.cooldowns.SeismicFissure or 0) > 0, "the Phase 3 ability ran")
	-- No phase above the last
	me.power.meter = 100
	local before = money(alice)
	local top = evolve(alice)
	assert(top and top.code == "MAX_PHASE" and money(alice) == before and me.power.degree == 3, "top phase enforced")
end)

check("premium powers must be owned in ranked modes; a trial in Practice is fine", function()
	local me = mine()
	services.PowerService:equip(me, "Corruption", 1, Powers.defaultLoadout("Corruption", 1), { trial = true })
	services.DataService:get(alice).powers.Corruption = { xp = 0, degrees = { ["2"] = true }, abilities = {}, owned = false }
	me.power.meter = 100
	setMoney(alice, 500)
	local match = services.MatchService:getMatchOf(me)
	match.modeName = "Duel"
	local refused = evolve(alice)
	match.modeName = "Practice"
	assert(refused and refused.code == "NOT_OWNED", "ownership: " .. tostring(refused and refused.code))
	assert(money(alice) == 500 and me.power.degree == 1, "nothing changed")
	local fee = Selection.priceFor("Corruption", 2, true)
	local reply = evolve(alice)
	assert(reply and reply.ok and reply.charged == fee and money(alice) == 500 - fee, "trial evolves for the premium fee")
	assert(me.power.degree == 2, "Corruption Phase 2")
	services.PowerService:equip(me, "StrongDude", 1, Powers.defaultLoadout("StrongDude", 1), {})
end)

check("a CPU evolves for free when its meter fills, up to its ceiling", function()
	local cpu = cpuOf()
	assert(cpu.power.degree == 1, "CPU starts in Phase 1")
	local before = money(alice)
	cpu.power.meter = 100
	game.waitFor(function()
		return cpu.power.degree == 2
	end, 2, "the CPU to evolve")
	assert(cpu.power.meter == 0, "its meter reset")
	assert(money(alice) == before, "free")
	cpu.power.meter = 100
	task.wait(1.2)
	assert(cpu.power.degree == 2, "Normal CPUs stop at Phase 2")
end)

check("the owner evolves free, with no unlock", function()
	endMatch(alice)
	local owner = game.join("Owner", OwnerConfig.UserIds[1])
	setMoney(owner, 0)
	request("MatchRequest", owner, "Queue", "Practice", { cpuPower = "StrongDude", cpuDifficulty = "Easy" })
	game.waitFor(function()
		local state = game.lastSent("MatchEvent", "State", owner)
		return state ~= nil and state.mode == "Practice" and state.phase == "Active"
	end, 4, "the owner's practice")
	local fighter = game.fighter(owner)
	assert(fighter.power.degree == 1, "owner starts in Phase 1")
	fighter.power.meter = 100
	local reply = evolve(owner)
	assert(reply and reply.ok and reply.charged == 0 and fighter.power.degree == 2, "owner: " .. tostring(reply and reply.code))
	assert(money(owner) == 0, "no money moved")
	services.MatchService:endAll()
	game.waitFor(function()
		return owner:GetAttribute("MatchId") == nil
	end, 4, "owner's match to finish")
end)

check("a match end puts everyone back to the saved selection: not evolved, empty meter", function()
	local me = mine()
	assert(not services.PowerService:isLocked(alice), "unlocked")
	assert(me.power.degree == 2 and not me.power.evolved, "back to the saved selection (degree 2): " .. me.power.degree)
	assert(me.model:GetAttribute(Attribute.PhaseNumber) == 2 and me.model:GetAttribute(Attribute.PhaseMeter) == 0, "attributes")
	setMoney(alice, 500)
	me.power.meter = 100
	local reply = evolve(alice)
	assert(reply and reply.code == "NOT_FIGHTING", "no evolving in the lobby again")
end)

check("Training evolves free and instant with no meter, and leaving the hall resets", function()
	local me = mine()
	setMoney(alice, 0)
	me.root.CFrame = game.CFrame.new(MatchConfig.TrainingGround.Center + Vector3.new(0, 4, 0))
	game.Engine.syncPositions(game.world.workspace)
	game.waitFor(function()
		return me.model:GetAttribute(Attribute.CombatContext) == "Training"
	end, 2, "the training context")
	unlock(alice, "StrongDude", 2, 3)
	assert(me.power.meter == 0, "empty meter")
	local first = evolve(alice)
	assert(first and first.ok and first.charged == 0 and me.power.degree == 2, "free: " .. tostring(first and first.code))
	local second = evolve(alice)
	assert(second and second.code == "TRANSFORMING", "one transformation at a time")
	task.wait(Selection.Phase.TransformTime + 0.2)
	local third = evolve(alice)
	assert(third and third.ok and me.power.degree == 3, "instant, no meter")
	task.wait(Selection.Phase.TransformTime + 0.2)
	local top = evolve(alice)
	assert(top and top.code == "MAX_PHASE", "top phase")
	assert(money(alice) == 0, "nothing charged in training")
	me.root.CFrame = game.CFrame.new(0, 4, 0)
	game.Engine.syncPositions(game.world.workspace)
	game.waitFor(function()
		return me.power.degree == 1
	end, 2, "the reset on leaving the hall")
end)

process.exit(if game.finish() == 0 then 0 else 1)
