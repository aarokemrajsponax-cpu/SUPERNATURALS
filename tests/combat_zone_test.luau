-- Where combat is allowed (server side), with the real services:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/combat_zone_test.luau build/game.rbxl
-- An attack, a heavy, a grab and an ability are refused in the hub and anywhere social, allowed
-- in a running match and in the Training Studio; dodging and sprinting still work in the hub;
-- the character's combat context attribute (the client's single source of truth) follows.

local process = require("@lune/process")

local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl")
local task, Vector3, CFrame = game.task, game.Vector3, game.CFrame
local services, check, request = game.services, game.check, game.request
local world = game.world
local Protocol = world.require(world.find("ReplicatedStorage.Shared.Protocol"))
local MatchConfig = world.require(world.find("ReplicatedStorage.Shared.Config.Match"))
local Attribute = Protocol.Attribute

game.flatGround(0)
for _, mode in MatchConfig.Modes do
	mode.Countdown = 0.3
	mode.Duration = 60
	mode.ResultsDuration = 0.4
end

local alice
local function mine()
	return game.fighter(alice)
end
local function moveTo(position)
	local me = mine()
	me.root.CFrame = CFrame.new(position)
	game.Engine.syncPositions(world.workspace)
end
local function contextIs(name: string)
	game.waitFor(function()
		return mine().model:GetAttribute(Attribute.CombatContext) == name
	end, 3, `the {name} context`)
end

-- Sends a basic action and says why it was refused (nil when it was not)
local function basic(action: string, payload)
	task.wait(0.4)
	local mark = game.mark()
	request("CombatRequest", alice, action, payload or { dir = Vector3.new(0, 0, -1) })
	task.wait(0.1)
	for _, entry in game.sentSince(mark, "CombatEvent", "Rejected", alice) do
		if entry.action == action then
			return entry.reason
		end
	end
	return nil
end

local function abilityId()
	return mine().power.loadout[1]
end
local function cast()
	task.wait(0.4)
	local mark = game.mark()
	request("AbilityRequest", alice, abilityId(), { direction = Vector3.new(0, 0, -1), point = mine().root.Position + Vector3.new(0, 0, -20) })
	task.wait(0.15)
	for _, entry in game.sentSince(mark, "AbilityEvent", "Rejected", alice) do
		return entry.reason
	end
	return nil
end

check("the hub: attacks, heavies, grabs and abilities are refused with the lobby reason", function()
	alice = game.join("Alice")
	game.waitFor(function()
		return mine() and mine().power ~= nil
	end, 3, "a power")
	contextIs("Lobby")
	for _, action in { "Light", "Heavy", "Grab", "Sweep" } do
		assert(basic(action) == Protocol.RejectReason.Lobby, `{action} is refused in the hub`)
	end
	assert(cast() == Protocol.RejectReason.Lobby, "an ability is refused in the hub")
	local ultimate = mine().power.ultimate
	if ultimate then
		task.wait(0.4)
		local mark = game.mark()
		request("AbilityRequest", alice, ultimate, { direction = Vector3.new(0, 0, -1) })
		task.wait(0.15)
		assert(#game.sentSince(mark, "AbilityEvent", "Rejected", alice) >= 1, "the ultimate is refused in the hub")
	end
end)

check("the hub: dodging and sprinting still work, and the player is told once", function()
	assert(basic("Dodge") ~= Protocol.RejectReason.Lobby, "dodge is allowed in the hub")
	assert(basic("SprintStart") ~= Protocol.RejectReason.Lobby, "sprint is allowed in the hub")
	basic("SprintEnd")
	local mark = game.mark()
	basic("Light")
	basic("Light")
	assert(#game.sentSince(mark, "MatchEvent", "Notice", alice) <= 1, "one calm notice, not one per press")
end)

check("every social place refuses: the lounge side, the base street and a far corner", function()
	for _, spot in { Vector3.new(400, 5, 400), Vector3.new(-300, 5, 250), Vector3.new(0, 5, 150) } do
		if not MatchConfig.TrainingGround or (spot - MatchConfig.TrainingGround.Center).Magnitude > 100 then
			moveTo(spot)
			contextIs("Lobby")
			assert(basic("Light") == Protocol.RejectReason.Lobby, "Light refused at " .. tostring(spot))
			assert(cast() == Protocol.RejectReason.Lobby, "ability refused at " .. tostring(spot))
		end
	end
end)

check("the Training Studio: attacks and abilities work", function()
	moveTo(MatchConfig.TrainingGround.Center + Vector3.new(0, 4, 0))
	contextIs("Training")
	assert(basic("Light") == nil, "Light works in training")
	assert(basic("Grab") ~= Protocol.RejectReason.Lobby, "Grab is not refused as lobby in training")
	task.wait(0.8)
	assert(cast() ~= Protocol.RejectReason.Lobby, "an ability is not refused as lobby in training")
end)

check("walking out of the hall closes combat again", function()
	moveTo(Vector3.new(400, 5, 400))
	contextIs("Lobby")
	assert(basic("Light") == Protocol.RejectReason.Lobby, "refused again outside")
end)

check("a running match: attacks and abilities work, the context is Match", function()
	request("MatchRequest", alice, "Queue", "Practice", { cpuPower = "StrongDude", cpuDifficulty = "Easy" })
	game.waitFor(function()
		local state = game.lastSent("MatchEvent", "State", alice)
		return state ~= nil and state.mode == "Practice" and state.phase == "Active"
	end, 6, "practice to begin")
	contextIs("Match")
	assert(basic("Light") == nil, "Light works in a match")
	task.wait(0.8)
	assert(cast() ~= Protocol.RejectReason.Lobby, "an ability works in a match")
	services.MatchService:endAll()
	game.waitFor(function()
		return alice:GetAttribute("MatchId") == nil
	end, 6, "the match to finish")
	task.wait(0.4)
end)

check("the owner's showcase mode is the only other way in", function()
	local OwnerConfig = world.require(world.find("ServerScriptService.Server.OwnerConfig"))
	assert(OwnerConfig, "owner config present")
	-- A normal player cannot turn it on
	moveTo(Vector3.new(400, 5, 400))
	contextIs("Lobby")
	request("PowerRequest", alice, "Showcase", true)
	task.wait(0.4)
	assert(mine().model:GetAttribute(Attribute.CombatContext) == "Lobby", "a non-owner stays in the lobby context")
	assert(basic("Light") == Protocol.RejectReason.Lobby, "and cannot fight there")
end)

process.exit(if game.finish() == 0 then 0 else 1)
