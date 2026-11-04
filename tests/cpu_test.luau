-- CPU opponents' decisions, with fixed seeds:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/cpu_test.luau build/game.rbxl
-- Difficulty tiers, blocking and dodging telegraphed heavies and ability wind-ups, spacing by
-- fighter, combo strings, ability range and cooldown use, the ultimate, human reaction delays,
-- repeatable randomness, and a live Hard CPU chaining a string.

local process = require("@lune/process")
local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl")
local task, Vector3, world, services, check = game.task, game.Vector3, game.world, game.services, game.check
local CpuBrain = world.require(world.find("ReplicatedStorage.Shared.Combat.CpuBrain"))
local FighterState = world.require(world.find("ReplicatedStorage.Shared.Combat.FighterState"))
local Powers = world.require(world.find("ReplicatedStorage.Shared.Powers"))
local Combat = world.require(world.find("ReplicatedStorage.Shared.Config.Combat"))
local CpuService = services.CpuService
local D = CpuService.Difficulties
game.flatGround(0)

local POWERS = { "StrongDude", "Ghost", "Shapeshifter", "MachineMaster", "Corruption", "Syntax", "Admin", "Grandmaster" }

check("difficulty tiers are ordered: Easy forgiving, Normal fair, Hard sharp", function()
	assert(D.Easy.reaction > D.Normal.reaction and D.Normal.reaction > D.Hard.reaction, "reaction")
	for _, key in { "blockChance", "dodgeChance", "readChance", "comboMax", "comboMin", "punishChance", "abilityRate", "ultSmart", "heavyFinish" } do
		assert(D.Easy[key] <= D.Normal[key] and D.Normal[key] <= D.Hard[key], key .. " rises with difficulty")
	end
	assert(D.Easy.abilityGap > D.Normal.abilityGap and D.Normal.abilityGap > D.Hard.abilityGap, "ability pacing")
	-- Hard is beatable: it never reads or defends everything
	assert(D.Hard.blockChance < 1 and D.Hard.dodgeChance < 1 and D.Hard.readChance < 1, "Hard is not perfect")
	assert(D.Hard.reaction >= 0.15, "Hard reacts like a human, not a frame")
end)

check("reaction delays are human: never under 0.12 s, Hard faster than Normal faster than Easy", function()
	local means = {}
	for _, name in { "Easy", "Normal", "Hard" } do
		local rng, total, lowest = CpuBrain.newRng(7), 0, math.huge
		for _ = 1, 300 do
			local delay = CpuBrain.reactionDelay(D[name], rng)
			total += delay
			lowest = math.min(lowest, delay)
		end
		assert(lowest >= 0.12, name .. " lowest " .. lowest)
		means[name] = total / 300
	end
	assert(means.Hard < means.Normal and means.Normal < means.Easy, "ordered")
	assert(means.Hard > 0.15, "Hard mean " .. means.Hard)
end)

check("the same seed gives the same choices; different seeds differ", function()
	local function run(seed)
		local rng, out = CpuBrain.newRng(seed), {}
		for _ = 1, 40 do
			table.insert(out, CpuBrain.defenseChoice(D.Normal, "Heavy", rng))
			table.insert(out, (CpuBrain.newCombo(D.Hard, rng)))
		end
		return table.concat(out, ",")
	end
	assert(run(11) == run(11), "repeatable")
	assert(run(11) ~= run(12), "seeds differ")
end)

local function rate(difficulty, kind, seed, trials)
	local rng, defended, dodged = CpuBrain.newRng(seed), 0, 0
	for _ = 1, trials do
		local choice = CpuBrain.defenseChoice(difficulty, kind, rng)
		if choice ~= "None" then
			defended += 1
		end
		if choice == "Dodge" then
			dodged += 1
		end
	end
	return defended / trials, dodged / trials
end

check("Hard blocks or dodges telegraphed heavies and ability wind-ups far more than Easy", function()
	for _, kind in { "Heavy", "Ability" } do
		local easy, easyDodge = rate(D.Easy, kind, 101, 600)
		local normal = rate(D.Normal, kind, 101, 600)
		local hard, hardDodge = rate(D.Hard, kind, 101, 600)
		assert(hard > normal and normal > easy, `{kind}: {easy} < {normal} < {hard}`)
		assert(hard - easy > 0.35, `{kind}: Hard {hard} vs Easy {easy}`)
		assert(hardDodge > easyDodge, kind .. " dodges")
		assert(hard < 0.97, kind .. ": Hard can still be hit, " .. hard)
		assert(easy < 0.5, kind .. ": Easy misses a lot, " .. easy)
	end
end)

-- The real _defend, with a stand-in combat service that records what the CPU presses
local function liveDefense(difficultyName, kind, seed, trials)
	local pressed = { BlockStart = 0, Dodge = 0, other = 0 }
	local combat = {}
	function combat:perform(_, action)
		if pressed[action] then
			pressed[action] += 1
		else
			pressed.other += 1
		end
		return true
	end
	local fake = setmetatable({ services = { CombatService = combat }, characters = { isAlive = function() return true end } }, { __index = CpuService })
	local function fighter(position)
		return { state = FighterState.new("x", Combat, game.world.workspace:GetServerTimeNow()), root = { Position = position }, combat = Combat }
	end
	local rng = CpuBrain.newRng(seed)
	local me, them = fighter(Vector3.new(0, 0, 0)), fighter(Vector3.new(4, 0, 0))
	for token = 1, trials do
		local brain = { difficulty = D[difficultyName], rng = rng, strafe = 1, blockingUntil = 0 }
		them.state.attack = { kind = kind, token = token, activeAt = game.world.workspace:GetServerTimeNow() + 0.45 }
		fake._defend(fake, me, brain, them, them.state.attack, 4)
		task.wait()
		-- (each trial's reaction is a delayed call; they all see the attack as still current,
		-- so keep the token current by waiting for each trial's own timer)
		task.wait(0.55)
	end
	return pressed
end

check("the live CPU presses Block or Dodge for a telegraphed heavy: Hard often, Easy rarely", function()
	local easy = liveDefense("Easy", "Heavy", 5, 24)
	local hard = liveDefense("Hard", "Heavy", 5, 24)
	local easyTotal, hardTotal = easy.BlockStart + easy.Dodge, hard.BlockStart + hard.Dodge
	assert(hardTotal >= easyTotal + 8, `Hard {hardTotal} vs Easy {easyTotal} of 24`)
	assert(hardTotal < 24, "Hard still gets hit sometimes")
	assert(hard.other == 0 and easy.other == 0, "only block and dodge")
end)

check("spacing: each fighter holds its own range (melee close, casters and shooters back off)", function()
	local ranges = {}
	for _, id in POWERS do
		local def = Powers.get(id)
		local ai = def.ai
		assert(ai and ai.preferredRange, id .. " has a preferred range")
		ranges[id] = ai.preferredRange
		local preferred = ai.preferredRange
		assert(CpuBrain.movePlan(preferred, preferred + 12) == "Approach", id .. " closes in from far")
		assert(CpuBrain.movePlan(preferred, preferred) == "Hold", id .. " holds at its range")
		if preferred > 8 then
			assert(CpuBrain.movePlan(preferred, preferred - 5) == "Retreat", id .. " backs off when crowded")
		else
			assert(CpuBrain.movePlan(preferred, preferred - 3) == "Hold", id .. " stays in a brawl")
			assert(CpuBrain.movePlan(preferred, preferred, true) == "Retreat", id .. " gives ground after a string")
		end
	end
	assert(ranges.Syntax >= 20 and ranges.StrongDude <= 8, "range differs by fighter: Syntax " .. ranges.Syntax .. ", Strong Dude " .. ranges.StrongDude)
	assert(CpuBrain.movePlan(ranges.Syntax, 8) == "Retreat" and CpuBrain.movePlan(ranges.StrongDude, 8) ~= "Retreat", "same distance, different plans")
end)

check("combos: strings get longer with difficulty, Hard ends in a heavy only when it connects", function()
	local function lengths(name, seed)
		local rng, low, high, total = CpuBrain.newRng(seed), math.huge, 0, 0
		for _ = 1, 200 do
			local length = CpuBrain.newCombo(D[name], rng)
			low, high, total = math.min(low, length), math.max(high, length), total + length
		end
		return low, high, total / 200
	end
	local eLow, eHigh, eMean = lengths("Easy", 3)
	local nLow, nHigh, nMean = lengths("Normal", 3)
	local hLow, hHigh, hMean = lengths("Hard", 3)
	assert(eHigh <= 2 and eLow >= 1, "Easy strings 1 to 2")
	assert(nLow >= 2 and nHigh <= 3, "Normal strings 2 to 3")
	assert(hLow >= 3 and hHigh <= 4, "Hard strings 3 to 4")
	assert(eMean < nMean and nMean < hMean, "longer with difficulty")
	local rng, locked, free = CpuBrain.newRng(9), 0, 0
	for _ = 1, 400 do
		if CpuBrain.wantsHeavyFinisher(D.Hard, true, rng) then
			locked += 1
		end
		if CpuBrain.wantsHeavyFinisher(D.Hard, false, rng) then
			free += 1
		end
	end
	assert(locked > free * 3, `heavy finish when it connects ({locked}) vs not ({free})`)
end)

check("abilities are used at their proper range and respect their role", function()
	for _, id in POWERS do
		local def = Powers.get(id)
		local used = 0
		for abilityId in def.abilities do
			local ability = Powers.abilityFor(id, abilityId, 3) or def.abilities[abilityId]
			local hint = ability and ability.ai
			if hint then
				used += 1
				local base = { distance = 1, healthShare = 1, targetHealthShare = 1, targetAttacking = false, targetLocked = false }
				local function ctx(patch)
					local copy = table.clone(base)
					for key, value in patch do
						copy[key] = value
					end
					return copy
				end
				assert(not CpuBrain.abilityWanted(hint, ctx({ distance = hint.range + 2, targetLocked = true, targetAttacking = true, healthShare = 0.1 })), `{id}.{abilityId} not used out of range`)
				if hint.use == "Engage" then
					assert(CpuBrain.abilityWanted(hint, ctx({ distance = hint.range * 0.8 })), `{id}.{abilityId} engages in range`)
				elseif hint.use == "Poke" then
					assert(CpuBrain.abilityWanted(hint, ctx({ distance = math.max(hint.range * 0.8, 6) })) or hint.range < 6, `{id}.{abilityId} pokes in range`)
					assert(not CpuBrain.abilityWanted(hint, ctx({ distance = 0.5 })) or hint.range < 2, `{id}.{abilityId} does not poke point blank`)
				elseif hint.use == "Escape" then
					assert(not CpuBrain.abilityWanted(hint, ctx({ distance = 3, healthShare = 0.9 })), `{id}.{abilityId} no escape when healthy`)
					assert(CpuBrain.abilityWanted(hint, ctx({ distance = 3, healthShare = 0.2 })), `{id}.{abilityId} escapes when hurt`)
				elseif hint.use == "Defend" then
					assert(not CpuBrain.abilityWanted(hint, ctx({ distance = 2, targetAttacking = false })), `{id}.{abilityId} defends only against an attack`)
					assert(CpuBrain.abilityWanted(hint, ctx({ distance = 2, targetAttacking = true })), `{id}.{abilityId} defends against an attack`)
				end
			end
		end
		assert(used > 0, id .. " has abilities with CPU hints")
	end
end)

check("an ability is not repeated while another is available", function()
	local rng = CpuBrain.newRng(21)
	for _ = 1, 100 do
		assert(CpuBrain.pickAbility({ "A", "B", "C" }, "B", rng) ~= "B", "rotates")
	end
	assert(CpuBrain.pickAbility({ "A" }, "A", rng) == "A", "uses the only one")
	assert(CpuBrain.pickAbility({}, nil, rng) == nil, "nothing to use")
end)

check("the ultimate is saved for when it will land", function()
	local rng = CpuBrain.newRng(33)
	local base = { distance = 10, range = 20, targetLocked = false, targetHealthShare = 0.9 }
	local function chance(difficulty, patch)
		local landed = 0
		for _ = 1, 400 do
			local ctx = table.clone(base)
			for key, value in patch do
				ctx[key] = value
			end
			if CpuBrain.ultimateWillLand(difficulty, ctx, rng) then
				landed += 1
			end
		end
		return landed / 400
	end
	assert(chance(D.Hard, { distance = 40 }) == 0, "never out of range")
	assert(chance(D.Hard, { targetLocked = true }) == 1, "always on a stunned or committed target")
	assert(chance(D.Hard, {}) == 0, "Hard waits on a healthy free target")
	assert(chance(D.Hard, { targetHealthShare = 0.2 }) > 0.7, "Hard finishes a hurt target")
	assert(chance(D.Easy, {}) > 0.1, "Easy fires it now and then")
end)

check("a live Hard CPU chains a string of attacks, then backs off before the next", function()
	CpuService.seed = 1234
	local alice = game.join("Sparring", 4001)
	game.request("MatchRequest", alice, "Queue", "Practice", { cpuPower = "StrongDude", cpuDegree = 1, cpuDifficulty = "Hard" })
	local practice
	game.waitFor(function()
		practice = services.MatchService:getMatchOf(game.fighter(alice))
		return practice ~= nil and practice.flow.phase == "Active"
	end, 4, "practice to begin")
	local cpu
	game.waitFor(function()
		for _, participant in practice.participants do
			if participant.dummy and participant.dummy.fighter then
				cpu = participant.dummy.fighter
				return true
			end
		end
		return false
	end, 4, "the CPU")
	local mark = game.mark()
	local me = game.fighter(alice)
	local started = os.clock()
	local longest, run, last = 0, 0, -math.huge
	local LIGHT = { Jab = true, Cross = true, Hook = true, FinisherKick = true }
	local seenAt = {}
	while os.clock() - started < 14 and longest < 3 do
		for _, participant in practice.participants do
			if participant.dummy and participant.dummy.fighter then
				cpu = participant.dummy.fighter
			end
		end
		game.faceOff(cpu, me, 3.5)
		me.humanoid.Health = me.humanoid.MaxHealth
		cpu.humanoid.Health = cpu.humanoid.MaxHealth
		-- Dodge-proof target: stay put and keep the guard down
		task.wait(0.15)
		for _, attack in game.sentSince(mark, "CombatEvent", "Attack") do
			if attack.attacker == cpu.model and not seenAt[attack] then
				seenAt[attack] = true
				local now = os.clock()
				if LIGHT[attack.move] and now - last < 1.0 then
					run += 1
				else
					run = if LIGHT[attack.move] then 1 else 0
				end
				last = now
				longest = math.max(longest, run)
			end
		end
	end
	CpuService.seed = nil
	assert(longest >= 3, "the CPU chained " .. longest .. " light attacks in a row")
end)

process.exit(if game.finish() == 0 then 0 else 1)
