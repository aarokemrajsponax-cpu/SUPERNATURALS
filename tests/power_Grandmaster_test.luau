-- The Grandmaster end to end with simulated players:
--   rojo build default.project.json -o build/grandmaster.rbxl
--   lune run tests/power_Grandmaster_test.luau build/grandmaster.rbxl
-- Two players equip the power and duel: the Iron Fist chain (with Twin Dragon
-- Fists' second impact and the finisher's cue), every technique at every
-- degree it exists at, the combo limit, counter success and failure (grabs and
-- unblockable hits pass through), diminishing returns, the meters, the
-- ultimate's dodgeable opener and target rules, junk requests, unlocks, the
-- cosmetic pass, respawn and match-end cleanup, a CPU using the power, and
-- every client effect at every degree (and in the celestial style).

local process = require("@lune/process")
local fs = require("@lune/fs")

local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/grandmaster.rbxl")
local task, Vector3, CFrame = game.task, game.Vector3, game.CFrame
local services, check, request = game.services, game.check, game.request
local world, Engine = game.world, game.Engine
local FighterState = world.require(world.find("ReplicatedStorage.Shared.Combat.FighterState"))
local Protocol = world.require(world.find("ReplicatedStorage.Shared.Protocol"))
local Powers = world.require(world.find("ReplicatedStorage.Shared.Powers"))
local Attribute = Protocol.Attribute
local DEF = Powers.get("Grandmaster")

game.flatGround(0)

local function now(): number
	return world.workspace:GetServerTimeNow()
end

local alice, bob
local match: any = nil

local function aimAt(from, to)
	return { direction = (to.root.Position - from.root.Position).Unit, point = to.root.Position }
end

-- Clear cooldowns, fill Chi, end any swing or stun, so tests don't wait
local function ready(fighter)
	-- The stand-in duel is short: keep it running while these checks go on
	if match and match.flow.phase == "Active" then
		match.flow.phaseEndsAt = math.max(match.flow.phaseEndsAt, now() + 60)
	end
	local runtime = fighter.power
	runtime.resource = runtime.resourceMax
	table.clear(runtime.cooldowns)
	fighter.state.attack = nil
	fighter.state.stunUntil = -math.huge
	fighter.state.comboCount = 0
	fighter.state.lastHitAt = -math.huge
	fighter.state.invulnerableUntil = -math.huge
	fighter.state.protectedUntil = -math.huge
	fighter.state.guard = fighter.combat.Block.MaxGuard
	fighter.state.blockingSince = nil
	services.StatusService:clearAll(fighter)
	services.CharacterService:refresh(fighter)
end

-- Face to face in the middle of the duel's arena (walls never come between them)
local function faceOff(a, b, gap: number)
	local current = match and services.MatchService:getMatchOf(a)
	if current and current == match and match.arena and match.arena.center then
		a.root.CFrame = CFrame.new(match.arena.center + Vector3.new(-gap / 2, 4, 0))
	end
	game.faceOff(a, b, gap)
end

-- Turned away from the opponent (so a technique whiffs without leaving the arena)
local function turnAway(a, b)
	faceOff(a, b, 6)
	local position = a.root.Position
	a.root.CFrame = CFrame.lookAt(position, position + (position - b.root.Position))
	Engine.syncPositions(world.workspace)
end

local function heal(fighter)
	fighter.humanoid.Health = fighter.humanoid.MaxHealth
end

local function equip(fighter, degree: number, loadout: { string }?)
	services.PowerService:equip(fighter, "Grandmaster", degree, loadout or Powers.defaultLoadout("Grandmaster", degree))
	ready(fighter)
end

local function use(player, abilityId: string, from, to)
	local mark = game.mark()
	local aim = aimAt(from, to)
	if from.root.CFrame.LookVector:Dot(aim.direction) < 0 then
		-- Turned away on purpose: aim the way they face
		aim = { direction = from.root.CFrame.LookVector }
	end
	request("AbilityRequest", player, abilityId, aim)
	if process.env.GM_DEBUG then
		for _, entry in game.sentSince(mark, "AbilityEvent", "Rejected", player) do
			print("DEBUG rejected", abilityId, entry.reason)
		end
	end
end

local function hitsSince(mark: number, filter: (any) -> boolean): { any }
	local list = {}
	for _, entry in game.sentSince(mark, "CombatEvent", "Hit") do
		if filter(entry) then
			table.insert(list, entry)
		end
	end
	return list
end

local function fxSince(mark: number, name: string): { any }
	local list = {}
	for _, entry in game.sentSince(mark, "AbilityEvent", "Fx") do
		if entry.power == "Grandmaster" and entry.fx == name then
			table.insert(list, entry)
		end
	end
	return list
end

local function rejection(mark: number, player, abilityId: string): string?
	for _, entry in game.sentSince(mark, "AbilityEvent", "Rejected", player) do
		if entry.ability == abilityId then
			return entry.reason
		end
	end
	return nil
end

-- Definition and client coverage --------------------------------------------------------------

check("the definition: four degrees, Chi, AI hints, card text and every client drawing", function()
	assert(DEF.degreeCount == 4 and #DEF.degrees == 4, "four degrees")
	assert(DEF.resource.name == "Chi" and DEF.resource.max == 100 and DEF.resource.start == 60, "Chi")
	assert(DEF.ai and DEF.ai.preferredRange and DEF.ai.aggression, "power AI hints")
	for abilityId, ability in DEF.abilities do
		assert(ability.ai and ability.ai.range and ability.ai.use, abilityId .. " AI hints")
		assert(not string.find(ability.description, "\u{2014}"), abilityId .. " has no em dash")
	end
	local server = fs.readFile("src/server/Powers/Grandmaster.luau")
	local client = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Powers.Grandmaster"))
	local names = {}
	for name in string.gmatch(server, ':fx%("(%w+)"') do
		names[name] = true
	end
	for name in string.gmatch(server, ':lastingFx%("(%w+)"') do
		names[name] = true
	end
	for name in string.gmatch(server, 'fxPrefix %.%. "(%w+)"') do
		names["Hundred" .. name] = true
		names["Ult" .. name] = true
	end
	-- Effects named through chainExtra(..., "Name") calls
	for name in string.gmatch(server, '"%w+", "(%w+)"%)') do
		names[name] = true
	end
	local total = 0
	for name in names do
		total += 1
		assert(client.fx[name], "no client effect for " .. name)
	end
	assert(total >= 30, "found the effects: " .. total)
	for abilityId in DEF.abilities do
		assert(client.predict[abilityId], "instant wind-up for " .. abilityId)
	end
end)

check("two players equip The Grandmaster: health, Chi, meters only where they belong", function()
	alice = game.join("Alice")
	bob = game.join("Bob")
	local a = game.fighter(alice)
	game.waitFor(function()
		return a.power ~= nil and game.fighter(bob) ~= nil and game.fighter(bob).power ~= nil
	end, 3, "powers to be equipped")
	local b = game.fighter(bob)
	services.PowerService:equip(a, "Grandmaster", 1, Powers.defaultLoadout("Grandmaster", 1))
	assert(a.power.resource == 60, "Chi starts at 60: " .. tostring(a.power.resource))
	equip(b, 1)
	assert(a.humanoid.MaxHealth == 100, "health")
	assert(a.model:GetAttribute(Attribute.Loadout) == "DragonsStep,TigerClaw", "Disciple loadout")
	assert(a.model:GetAttribute(Attribute.Focus) == nil, "no Focus meter at Disciple")
	assert(a.model:GetAttribute(Attribute.PerfectForm) == nil, "no Perfect Form at Disciple")
	assert(a.model:GetAttribute(Attribute.Style) == nil, "standard look without the pass")
	equip(a, 3)
	assert(a.model:GetAttribute(Attribute.Focus) == 0, "Focus at Grandmaster")
	assert(a.model:GetAttribute(Attribute.PerfectForm) == nil, "no Perfect Form below Degree IV")
	equip(a, 4)
	assert(a.model:GetAttribute(Attribute.PerfectForm) == 0, "Perfect Form at Degree IV")
	assert(a.humanoid.MaxHealth == 110, "Degree IV health")
	assert(a.combat.Light.Steps[1].Startup == 0.08, "the Iron Fist chain is in the combat profile")
	equip(a, 1)
end)

check("Chi regenerates and a degree the power lacks is refused", function()
	local a = game.fighter(alice)
	a.power.resource = 10
	task.wait(1.05)
	assert(a.power.resource > 14, "Chi regenerates about 6 a second: " .. tostring(a.power.resource))
	local ok = services.PowerService:check(alice, "Grandmaster", 5)
	assert(not ok, "no degree 5")
	ok = services.PowerService:check(alice, "Grandmaster", 2.5)
	assert(not ok, "no fractional degree")
	ok = services.PowerService:check(alice, "StrongDude", 4)
	assert(not ok, "Strong Dude has no degree 4")
	ok = services.PowerService:check(alice, "Grandmaster", 4)
	assert(not ok, "degree 4 is locked without mastery")
end)

-- The duel ----------------------------------------------------------------------------------

check("a duel starts with both on The Grandmaster", function()
	request("MatchRequest", alice, "Queue", "Duel")
	request("MatchRequest", bob, "Queue", "Duel")
	game.waitFor(function()
		match = services.MatchService:getMatchOf(game.fighter(alice))
		return match ~= nil and match.flow.phase == "Active"
	end, 4, "the duel to begin")
	task.wait(0.2)
	local a, b = game.fighter(alice), game.fighter(bob)
	equip(a, 1)
	equip(b, 1)
end)

check("the Iron Fist: four steps, Twin Dragon Fists hits twice, the kick ends it with a finisher cue", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	faceOff(a, b, 3)
	ready(a)
	ready(b)
	heal(b)
	local health = b.humanoid.Health
	local mark = game.mark()
	for _ = 1, 4 do
		faceOff(a, b, 3)
		request("CombatRequest", alice, "Light")
		task.wait(0.42)
	end
	task.wait(0.5)
	local light = hitsSince(mark, function(entry)
		return entry.attacker == a.model and entry.kind == "Light"
	end)
	local twin = hitsSince(mark, function(entry)
		return entry.attacker == a.model and entry.ability == "TwinDragonFists"
	end)
	assert(#light == 4, "four chain hits: " .. #light)
	assert(#twin == 1, "the second fist of Twin Dragon Fists: " .. #twin)
	assert(b.humanoid.Health < health, "damage dealt")
	local impacts = fxSince(mark, "IronFistImpact")
	local finisher = false
	for _, entry in impacts do
		if entry.data.finisher and entry.data.step == 4 then
			finisher = true
		end
	end
	assert(finisher, "the Whirlwind Kick sends the hit-stop cue")
	-- Lighter than the default chain
	local dealt = health - b.humanoid.Health
	assert(dealt <= 25, "modest damage for the whole chain: " .. dealt)
end)

check("no infinite stun-lock: the chain ends itself, and long strings hit the combo limit", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	ready(a)
	ready(b)
	heal(b)
	-- A full chain: the kick launches them clear and the chain has a rest after it
	for _ = 1, 4 do
		faceOff(a, b, 3)
		request("CombatRequest", alice, "Light")
		task.wait(0.42)
	end
	assert(a.state.lightReadyAt > now() - 0.2 or not FighterState.isStunned(b.state, now() + 0.3), "a gap to escape after the kick")
	-- Straight into Hundred Fists (Degree III): the combo limit stops the stun partway
	equip(a, 3)
	faceOff(a, b, 3)
	local mark = game.mark()
	use(alice, "HundredFists", a, b)
	task.wait(1.4)
	local capped = hitsSince(mark, function(entry)
		return entry.victim == b.model and entry.comboCapped == true
	end)
	assert(#capped > 0, "the combo limit kicked in")
	equip(a, 1)
	heal(b)
	task.wait(0.6)
end)

check("Dragon's Step: a real dash, untouchable, Chi and cooldown; a strike through it earns a counter palm", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	faceOff(a, b, 3)
	ready(a)
	ready(b)
	local chi = a.power.resource
	local mark = game.mark()
	-- Bob swings first; Alice steps through it
	request("CombatRequest", bob, "Light")
	task.wait(0.02)
	use(alice, "DragonsStep", a, b)
	task.wait(0.08)
	local mover = a.root:FindFirstChild("SNDash")
	assert(mover ~= nil, "the dash mover exists")
	assert(FighterState.isInvulnerable(a.state, now()), "untouchable during the burst")
	task.wait(0.4)
	assert((a.model:GetAttribute(Attribute.CooldownPrefix .. "DragonsStep") or 0) > now(), "cooldown")
	assert(#fxSince(mark, "StepRead") == 1, "a perfect step was read")
	assert((a.power.data.openingUntil or 0) > now(), "the opening is open")
	assert(a.root:FindFirstChild("SNDash") == nil, "the mover is gone")
	-- The next landed hit adds the counter palm
	faceOff(a, b, 3)
	ready(b)
	local markHit = game.mark()
	request("CombatRequest", alice, "Light")
	task.wait(0.5)
	local palm = hitsSince(markHit, function(entry)
		return entry.attacker == a.model and entry.ability == "CounterPalm"
	end)
	assert(#palm == 1, "counter palm landed: " .. #palm)
	assert((a.power.data.openingUntil or 0) == 0, "the opening is used up")
	-- A step with nobody swinging is just movement, and costs its Chi
	ready(a)
	a.power.resource = 50
	local markPlain = game.mark()
	use(alice, "DragonsStep", a, b)
	task.wait(0.05)
	assert(math.abs(a.power.resource - (50 - DEF.abilities.DragonsStep.cost)) < 1, "Chi spent: " .. tostring(a.power.resource))
	task.wait(0.35)
	assert(#fxSince(markPlain, "StepRead") == 0, "no read without an attack")
	task.wait(0.4)
end)

check("Tiger Claw: two body strikes, a telegraphed palm (prompt), heavy guard pressure", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	faceOff(a, b, 3)
	ready(a)
	ready(b)
	heal(b)
	local mark = game.mark()
	use(alice, "TigerClaw", a, b)
	game.waitFor(function()
		return #game.sentSince(mark, "DefenseEvent", "Cue", bob) > 0
	end, 2, "Bob's prompt for the palm thrust")
	local cue = game.sentSince(mark, "DefenseEvent", "Cue", bob)[1]
	assert(cue.kind == "Prompt", "a block/dodge prompt")
	task.wait(1)
	local hits = hitsSince(mark, function(entry)
		return entry.attacker == a.model and entry.ability == "TigerClaw"
	end)
	assert(#hits == 3, "two strikes and the thrust: " .. #hits)
	-- Against a guard it drains a lot of it
	ready(a)
	ready(b)
	faceOff(a, b, 3)
	request("CombatRequest", bob, "BlockStart", "Held")
	task.wait(0.05)
	local guard = b.state.guard
	use(alice, "TigerClaw", a, b)
	task.wait(1.1)
	request("CombatRequest", bob, "BlockEnd")
	assert(b.state.guard < guard - 30, `guard pressure ({guard} -> {b.state.guard})`)
	-- Missing everything is punished
	ready(a)
	turnAway(a, b)
	use(alice, "TigerClaw", a, b)
	task.wait(0.95)
	assert(FighterState.isAttacking(a.state, now()), "a whiff leaves him in recovery")
	task.wait(0.8)
end)

check("Crane's Reversal (Degree II): a strike into the stance is redirected and answered", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	equip(a, 2)
	faceOff(a, b, 3)
	ready(b)
	heal(a)
	heal(b)
	local aliceHealth, bobHealth = a.humanoid.Health, b.humanoid.Health
	local chi = a.power.resource - DEF.abilities.CranesReversal.cost
	local mark = game.mark()
	use(alice, "CranesReversal", a, b)
	task.wait(0.06)
	request("CombatRequest", bob, "Light")
	task.wait(0.8)
	local countered = hitsSince(mark, function(entry)
		return entry.victim == a.model and entry.result == "Countered"
	end)
	assert(#countered == 1, "countered")
	assert(a.humanoid.Health == aliceHealth, "Alice took nothing")
	assert(b.humanoid.Health < bobHealth, "Bob was answered")
	assert(#fxSince(mark, "CraneCounter") == 1, "the counter flash")
	assert(a.power.resource >= chi + DEF.resource.gainOnDefense - 0.01, "a defense earns Chi")
	task.wait(0.4)
end)

check("Crane's Reversal: nothing comes and he's left open", function()
	local a = game.fighter(alice)
	ready(a)
	local mark = game.mark()
	use(alice, "CranesReversal", a, game.fighter(bob))
	local def = DEF.abilities.CranesReversal
	task.wait(def.startup + def.active + def.recovery + 0.05)
	assert(#fxSince(mark, "CraneMiss") == 1, "the miss shows")
	assert(FighterState.isAttacking(a.state, now()), "still recovering: the failed read is punishable")
	task.wait(def.whiffRecovery + 0.1)
	assert(not FighterState.isAttacking(a.state, now()), "recovers in the end")
end)

check("Crane's Reversal can't counter grabs or unblockable attacks", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	-- Unblockable melee straight through the stance
	ready(a)
	heal(a)
	faceOff(a, b, 3)
	use(alice, "CranesReversal", a, b)
	task.wait(0.06)
	local health = a.humanoid.Health
	local outcome = services.CombatService:applyHit(b, a, { Damage = 7, Hitstun = 0.3, Knockback = 0, Launch = 0, GuardDamage = 0, Blockable = false }, {
		kind = "Ability",
		power = "Test",
		ability = "Unblockable",
		tags = { "Melee" },
	})
	assert(outcome and outcome.result ~= "Countered", "unblockable goes through: " .. tostring(outcome and outcome.result))
	assert(a.humanoid.Health < health, "and hurts")
	task.wait(0.9)
	-- A grab
	services.PowerService:equip(b, "StrongDude", 1, { "Groundbreaker", "TitanGrip", "MeteorCharge" })
	ready(a)
	ready(b)
	faceOff(a, b, 3)
	use(alice, "CranesReversal", a, b)
	task.wait(0.03)
	use(bob, "TitanGrip", b, a)
	game.waitFor(function()
		return services.StatusService:has(a, "Grabbed")
	end, 1.5, "the grab to land through the stance")
	task.wait(2.2)
	equip(b, 1)
	equip(a, 2)
end)

check("Iron Mountain (Degree II): shoulder check, heavy palm, strong knockback; a miss is punishable", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	faceOff(a, b, 4)
	ready(a)
	ready(b)
	heal(b)
	local mark = game.mark()
	use(alice, "IronMountain", a, b)
	task.wait(1.2)
	local hits = hitsSince(mark, function(entry)
		return entry.attacker == a.model and entry.ability == "IronMountain"
	end)
	assert(#hits == 2, "shoulder and palm: " .. #hits)
	assert(#game.sentSince(mark, "DefenseEvent", "Cue", bob) > 0, "it had a readable prompt")
	assert(#fxSince(mark, "MountainPalm") == 1 and fxSince(mark, "MountainPalm")[1].data.landed, "the palm landed")
	-- Whiff
	ready(a)
	turnAway(a, b)
	local def = DEF.abilities.IronMountain
	use(alice, "IronMountain", a, b)
	task.wait(def.startup + def.active + def.recovery + 0.1)
	assert(FighterState.isAttacking(a.state, now()), "missing leaves him open longer")
	task.wait(def.whiffRecovery + 0.2)
end)

check("Sweeping Dragon (Degree III): knocks down, jumping clears it, no repeated knockdown", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	equip(a, 3)
	faceOff(a, b, 4)
	ready(b)
	heal(b)
	local mark = game.mark()
	use(alice, "SweepingDragon", a, b)
	task.wait(0.7)
	assert(#fxSince(mark, "Knockdown") == 1, "knocked down")
	assert(services.StatusService:has(b, "SureFooted"), "immune to another sweep for a while")
	-- Again right away: hit, but no second knockdown and a short stagger only
	ready(a)
	b.state.stunUntil = -math.huge
	faceOff(a, b, 4)
	local mark2 = game.mark()
	use(alice, "SweepingDragon", a, b)
	task.wait(0.7)
	local hits = hitsSince(mark2, function(entry)
		return entry.victim == b.model and entry.ability == "SweepingDragon"
	end)
	assert(#hits == 1, "still hit")
	assert(#fxSince(mark2, "Knockdown") == 0, "diminishing returns: no repeated knockdown")
	-- A jump clears it
	ready(a)
	services.StatusService:clearAll(b)
	faceOff(a, b, 4)
	b.root.CFrame = b.root.CFrame + Vector3.new(0, 5, 0)
	Engine.syncPositions(world.workspace)
	local mark3 = game.mark()
	use(alice, "SweepingDragon", a, b)
	task.wait(0.7)
	assert(#hitsSince(mark3, function(entry)
		return entry.victim == b.model
	end) == 0, "jumped over")
	b.root.CFrame = b.root.CFrame - Vector3.new(0, 5, 0)
	Engine.syncPositions(world.workspace)
end)

check("Hundred Fists (Degree III): a confirmed jab, timed beats, a launching finish", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	faceOff(a, b, 3)
	ready(a)
	ready(b)
	heal(b)
	local mark = game.mark()
	use(alice, "HundredFists", a, b)
	task.wait(0.35)
	assert(services.StatusService:has(b, "Sequenced"), "Bob is caught in the sequence")
	task.wait(1.2)
	local hits = hitsSince(mark, function(entry)
		return entry.attacker == a.model and entry.ability == "HundredFists"
	end)
	local def = Powers.abilityFor("Grandmaster", "HundredFists", 3)
	assert(#hits == #def.beats + 2, "jab, beats and finish: " .. #hits)
	assert(#fxSince(mark, "HundredFinish") == 1, "the launching finish")
	assert(not services.StatusService:has(b, "Sequenced"), "released after")
end)

check("Hundred Fists: blocked jab means no flurry; hit before the jab means nothing at all", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	faceOff(a, b, 3)
	ready(a)
	ready(b)
	request("CombatRequest", bob, "BlockStart", "Held")
	task.wait(0.05)
	local mark = game.mark()
	use(alice, "HundredFists", a, b)
	task.wait(1.2)
	request("CombatRequest", bob, "BlockEnd")
	assert(#fxSince(mark, "HundredFlurry") == 0, "no flurry off a blocked jab")
	task.wait(0.8)
	-- Interrupted during startup
	ready(a)
	ready(b)
	heal(b)
	faceOff(a, b, 3)
	local health = b.humanoid.Health
	local mark2 = game.mark()
	use(alice, "HundredFists", a, b)
	task.wait(0.03)
	services.CombatService:applyHit(b, a, { Damage = 3, Hitstun = 0.6, Knockback = 0, Launch = 0, GuardDamage = 0 }, { kind = "Ability", power = "Test", ability = "Poke", tags = { "Melee" } })
	task.wait(1)
	assert(#fxSince(mark2, "HundredOpener") == 0, "interrupted before the jab")
	assert(b.humanoid.Health == health, "Bob took nothing")
	-- Someone already in another sequence can't be targeted
	ready(a)
	faceOff(a, b, 3)
	services.StatusService:apply(b, "Sequenced", 1)
	local mark3 = game.mark()
	use(alice, "HundredFists", a, b)
	task.wait(0.1)
	assert(rejection(mark3, alice, "HundredFists") ~= nil, "refused on a target already caught")
	services.StatusService:remove(b, "Sequenced")
end)

check("Focus State (Degree III): needs Focus, quickens the chain for a while, no damage resistance", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	equip(a, 3, { "DragonsStep", "TigerClaw", "CranesReversal", "FocusState", "HundredFists" })
	local mark = game.mark()
	use(alice, "FocusState", a, b)
	task.wait(0.1)
	assert(rejection(mark, alice, "FocusState") ~= nil, "refused without Focus")
	-- Build Focus by landing hits
	faceOff(a, b, 3)
	ready(b)
	for _ = 1, 4 do
		faceOff(a, b, 3)
		request("CombatRequest", alice, "Light")
		task.wait(0.42)
	end
	task.wait(0.4)
	assert((a.power.data.focus or 0) > 0, "hits build Focus")
	assert(a.model:GetAttribute(Attribute.Focus) == math.floor(a.power.data.focus + 0.5), "Focus is published")
	a.power.data.focus = 70
	ready(a)
	local recovery = a.combat.Light.Steps[1].Recovery
	use(alice, "FocusState", a, b)
	task.wait(0.5)
	assert((a.power.data.focusedUntil or 0) > now(), "focused")
	assert(a.combat.Light.Steps[1].Recovery < recovery, "quicker string recovery")
	assert(math.abs(a.power.data.focus - 10) < 0.5, "Focus spent: " .. tostring(a.power.data.focus))
	assert((a.combat.DamageTaken or 1) == 1, "no damage resistance")
	task.wait(Powers.abilityFor("Grandmaster", "FocusState", 3).duration + 0.2)
	assert(a.combat.Light.Steps[1].Recovery == recovery, "back to normal afterwards")
end)

check("Dragon's Answer (Degree IV): only after a successful read, then a jade palm", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	equip(a, 4)
	faceOff(a, b, 3)
	ready(b)
	local mark = game.mark()
	use(alice, "DragonsAnswer", a, b)
	task.wait(0.1)
	assert(rejection(mark, alice, "DragonsAnswer") ~= nil, "refused without a read")
	-- Counter Bob, then answer
	ready(a)
	heal(b)
	faceOff(a, b, 3)
	use(alice, "CranesReversal", a, b)
	task.wait(0.06)
	request("CombatRequest", bob, "Light")
	task.wait(0.7)
	assert((a.power.data.answerUntil or 0) > now(), "the answer window opened")
	a.power.cooldowns.DragonsAnswer = 0
	a.state.attack = nil
	ready(b)
	faceOff(a, b, 5)
	local mark2 = game.mark()
	use(alice, "DragonsAnswer", a, b)
	task.wait(0.8)
	local hits = hitsSince(mark2, function(entry)
		return entry.attacker == a.model and entry.ability == "DragonsAnswer"
	end)
	assert(#hits == 1, "the answer landed: " .. #hits)
	assert(fxSince(mark2, "AnswerPalm")[1].data.landed, "drawn as a hit")
end)

check("Perfect Form (Degree IV): clean hits build it, being hit drops it, it adds damage", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	ready(a)
	ready(b)
	a.power.data.form = 0
	for _ = 1, 3 do
		faceOff(a, b, 3)
		request("CombatRequest", alice, "Light")
		task.wait(0.42)
	end
	task.wait(0.3)
	local built = a.power.data.form
	assert(built > 0, "hits build Perfect Form")
	assert(a.model:GetAttribute(Attribute.PerfectForm) == math.floor(built + 0.5), "published")
	services.CombatService:applyHit(b, a, { Damage = 3, Hitstun = 0.2, Knockback = 0, Launch = 0, GuardDamage = 0 }, { kind = "Ability", power = "Test", ability = "Poke", tags = { "Melee" } })
	assert(a.power.data.form < built, "taking damage drops it")
	-- Full meter: the same technique deals more
	ready(a)
	ready(b)
	heal(b)
	a.power.data.form = 0
	faceOff(a, b, 3)
	local health = b.humanoid.Health
	use(alice, "TigerClaw", a, b)
	task.wait(1.1)
	local plain = health - b.humanoid.Health
	ready(a)
	ready(b)
	heal(b)
	a.power.data.form = 100
	faceOff(a, b, 3)
	use(alice, "TigerClaw", a, b)
	task.wait(1.1)
	local sharp = health - b.humanoid.Health
	assert(sharp > plain, `Perfect Form adds damage ({plain} -> {sharp})`)
	assert(sharp <= plain * 1.13 + 0.5, "but only a little")
end)

-- The ultimate ------------------------------------------------------------------------------------

check("Heaven-Splitting Dragon at every degree: opener, flurry, finish; the full cinematic at IV", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	for degree = 1, 4 do
		equip(a, degree)
		ready(b)
		heal(b)
		faceOff(a, b, 3)
		a.power.ult = 100
		local health = b.humanoid.Health
		local mark = game.mark()
		use(alice, "HeavenSplittingDragon", a, b)
		game.waitFor(function()
			return #game.sentSince(mark, "DefenseEvent", "Cue", bob) > 0
		end, 1, "the opener's prompt")
		local def = Powers.abilityFor("Grandmaster", "HeavenSplittingDragon", degree)
		task.wait(def.startup + def.finishAt + 0.6)
		local hits = hitsSince(mark, function(entry)
			return entry.attacker == a.model and entry.ability == "HeavenSplittingDragon"
		end)
		assert(#hits == #def.beats + 2, `degree {degree}: opener, beats, finish ({#hits})`)
		assert(b.humanoid.Health < health, `degree {degree}: damage`)
		assert(health - b.humanoid.Health < health * 0.6, `degree {degree}: doesn't simply erase a health bar`)
		assert(a.power.ult < 50, "charge spent")
		assert(#fxSince(mark, "UltShockwave") == (if degree == 4 then 1 else 0), `degree {degree}: arena shockwave only at IV`)
		assert(fxSince(mark, "UltStance")[1].data.cinematic == (degree == 4), "cinematic flag")
		assert(services.StatusService:has(b, "UltimateGuard"), "the target can't be ultimated again for a while")
		services.StatusService:remove(b, "UltimateGuard")
		task.wait(0.6)
	end
end)

check("the ultimate needs a target in range, and its opener can be dodged (some charge comes back)", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	ready(a)
	ready(b)
	-- Nobody close: refused and the charge is kept
	faceOff(a, b, 20)
	a.power.ult = 100
	local mark = game.mark()
	use(alice, "HeavenSplittingDragon", a, b)
	task.wait(0.1)
	assert(rejection(mark, alice, "HeavenSplittingDragon") ~= nil, "refused out of range")
	assert(a.power.ult == 100, "charge kept")
	-- Bob dodges the opener
	faceOff(a, b, 3)
	heal(b)
	local health = b.humanoid.Health
	local mark2 = game.mark()
	use(alice, "HeavenSplittingDragon", a, b)
	task.wait(DEF.abilities.HeavenSplittingDragon.startup - 0.15)
	request("CombatRequest", bob, "Dodge", { direction = Vector3.new(0, 0, 1) })
	task.wait(1.2)
	assert(#fxSince(mark2, "UltFlurry") == 0, "no sequence after a dodged opener")
	assert(b.humanoid.Health == health, "Bob is untouched")
	assert(a.power.ult >= 20 and a.power.ult < 40, "a quarter of the charge back: " .. tostring(a.power.ult))
	task.wait(0.8)
end)

check("the same target can't be ultimated again right away (by anyone)", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	ready(a)
	ready(b)
	heal(b)
	faceOff(a, b, 3)
	a.power.ult = 100
	use(alice, "HeavenSplittingDragon", a, b)
	task.wait(2.6)
	assert(services.StatusService:has(b, "UltimateGuard"), "guarded")
	ready(a)
	services.StatusService:remove(b, "Sequenced")
	b.state.stunUntil = -math.huge
	faceOff(a, b, 3)
	a.power.ult = 100
	local mark = game.mark()
	use(alice, "HeavenSplittingDragon", a, b)
	task.wait(0.1)
	assert(rejection(mark, alice, "HeavenSplittingDragon") ~= nil, "refused on a guarded target")
	services.StatusService:remove(b, "UltimateGuard")
end)

-- Abuse, unlocks, cosmetics --------------------------------------------------------------------

check("junk requests are refused without errors", function()
	local a = game.fighter(alice)
	ready(a)
	a.power.ult = 0
	local mark = game.mark()
	request("AbilityRequest", alice, "HeavenSplittingDragon", {}) -- no charge
	request("AbilityRequest", alice, "Groundbreaker", {}) -- another power's
	request("AbilityRequest", alice, "TigerClaw", { direction = Vector3.new(0 / 0, 0, 0), point = "nope" })
	request("AbilityRequest", alice, "DragonsAnswer", "junk")
	request("AbilityRequest", alice, {}, {})
	for _ = 1, 30 do
		request("AbilityRequest", alice, "DragonsStep", {})
	end
	request("PowerRequest", alice, "Select", "Grandmaster", 5)
	request("PowerRequest", alice, "Select", "Grandmaster", 0 / 0)
	request("PowerRequest", alice, "SetLoadout", "Grandmaster", 4.5, { "TigerClaw" })
	request("PowerRequest", alice, "SetLoadout", "StrongDude", 4, { "Groundbreaker" })
	request("PowerRequest", alice, "UnlockDegree", "StrongDude", 4)
	request("PowerRequest", alice, "PromptPass", "Grandmaster", "Cosmetic")
	request("PowerRequest", alice, "PromptPass", "Grandmaster", 7)
	task.wait(0.5)
	assert(rejection(mark, alice, "HeavenSplittingDragon") == "charge", "no charge")
	assert(rejection(mark, alice, "Groundbreaker") == "unknown", "other power's ability")
	local a2 = game.fighter(alice)
	assert(a2.power.id == "Grandmaster", "still The Grandmaster (locked in the duel)")
	ready(a2)
end)

check("ending the match leaves nothing behind", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	ready(a)
	ready(b)
	faceOff(a, b, 3)
	equip(a, 4)
	a.power.data.focus = 80
	use(alice, "HundredFists", a, b)
	task.wait(0.3)
	services.MatchService:endAll()
	task.wait(1.4)
	local fa, fb = game.fighter(alice), game.fighter(bob)
	assert(services.MatchService:getMatchOf(fa) == nil, "match over")
	for _, fighter in { fa, fb } do
		for name in fighter.model:GetAttributes() do
			if string.sub(name, 1, 4) == "SNS_" then
				error("status left behind: " .. name)
			end
		end
		assert(not services.StatusService:has(fighter, "Sequenced"), "no sequence marker")
		assert(fighter.root:FindFirstChild("SNDash") == nil, "no movers")
	end
	assert(fa.power.data.focus == 0 and fa.power.data.form == 0, "meters reset")
	assert((fa.power.data.focusedUntil or 0) == 0, "focus over")
end)

check("a knockout mid-ultimate cleans up and respawns cleanly", function()
	local a, b = game.fighter(alice), game.fighter(bob)
	equip(a, 3, { "DragonsStep", "TigerClaw", "CranesReversal", "FocusState", "HundredFists" })
	ready(b)
	faceOff(a, b, 3)
	a.power.data.focus = 70
	use(alice, "FocusState", a, b)
	task.wait(0.5)
	assert((a.power.data.focusedUntil or 0) > now(), "focused before the knockout")
	a.humanoid.Health = 0
	game.waitFor(function()
		local fresh = game.fighter(alice)
		return fresh ~= nil and fresh ~= a and fresh.power ~= nil
	end, 4, "Alice to respawn")
	local fresh = game.fighter(alice)
	assert(not FighterState.isAttacking(fresh.state, now()), "not stuck mid-cast")
	assert(fresh.power.ult < 5, "charge starts empty")
	assert(fresh.power.resource == fresh.power.def.resource.start or fresh.power.id ~= "Grandmaster", "Chi back to its start")
end)

check("degree IV unlocks with Money after degree III, and Select then allows it", function()
	local profile = services.DataService:get(alice)
	if not profile then
		return
	end
	services.DataService:update(alice, function(data)
		data.currencies.money = 30000
		data.powers.Grandmaster = { xp = 0, degrees = {}, abilities = {}, owned = false }
	end)
	request("PowerRequest", alice, "UnlockDegree", "Grandmaster", 4)
	task.wait(0.2)
	local saved = services.DataService:get(alice).powers.Grandmaster
	assert(not (saved and saved.degrees and saved.degrees["4"]), "degree IV needs degree III first")
	request("PowerRequest", alice, "UnlockDegree", "Grandmaster", 2)
	task.wait(0.2)
	request("PowerRequest", alice, "UnlockDegree", "Grandmaster", 3)
	task.wait(0.2)
	request("PowerRequest", alice, "UnlockDegree", "Grandmaster", 4)
	task.wait(0.2)
	saved = services.DataService:get(alice).powers.Grandmaster
	assert(saved.degrees["4"] == true, "degree IV bought")
	assert(services.DataService:get(alice).currencies.money == 30000 - 1500 - 6000 - 15000, "paid the listed prices")
	local ok = services.PowerService:check(alice, "Grandmaster", 4)
	assert(ok, "degree IV can be selected")
	request("PowerRequest", alice, "Select", "Grandmaster", 4)
	task.wait(0.3)
	local a = game.fighter(alice)
	assert(a.power.id == "Grandmaster" and a.power.degree == 4, "now at Ascendant Dragon")
end)

check("Celestial Dragon Style: not on sale with id 0; owning it changes looks, never numbers", function()
	local a = game.fighter(alice)
	local mark = game.mark()
	request("PowerRequest", alice, "PromptPass", "Grandmaster", "Cosmetic")
	task.wait(0.2)
	local toast = game.lastSent("DataEvent", "Toast", alice)
	assert(toast and string.find(toast.text, "isn't on sale", 1, true), "not on sale yet: " .. tostring(toast and toast.text))
	local _ = mark
	local before = Powers.abilityFor("Grandmaster", "TigerClaw", 4).damage
	services.DataService:update(alice, function(data)
		data.passes.CelestialDragonStyle = true
	end)
	services.PowerService:equip(a, "Grandmaster", 4, Powers.defaultLoadout("Grandmaster", 4))
	assert(a.model:GetAttribute(Attribute.Style) == "CelestialDragonStyle", "the style shows on the fighter")
	assert(a.humanoid.MaxHealth == 110, "same health")
	assert(Powers.abilityFor("Grandmaster", "TigerClaw", 4).damage == before, "same numbers")
	services.DataService:update(alice, function(data)
		data.passes.CelestialDragonStyle = nil
	end)
	services.PowerService:equip(a, "Grandmaster", 4, Powers.defaultLoadout("Grandmaster", 4))
	assert(a.model:GetAttribute(Attribute.Style) == nil, "gone without the pass")
end)

-- CPU ---------------------------------------------------------------------------------------

check("a CPU Grandmaster fights with its techniques", function()
	local me = game.fighter(alice)
	ready(me)
	request("MatchRequest", alice, "Queue", "Practice", { cpuPower = "Grandmaster", cpuDegree = 3, cpuDifficulty = "Hard" })
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
				return cpu.power ~= nil
			end
		end
		return false
	end, 4, "the CPU to arrive with its power")
	assert(cpu.power.id == "Grandmaster" and cpu.power.degree == 3, "the CPU plays The Grandmaster")
	-- Degree IV for the CPU too (practice only offers up to III today)
	services.PowerService:equip(cpu, "Grandmaster", 4, Powers.defaultLoadout("Grandmaster", 4))
	me = game.fighter(alice)
	local startHealth = me.humanoid.Health
	local mark = game.mark()
	local started = os.clock()
	local casts = 0
	while os.clock() - started < 8 and casts < 2 do
		faceOff(cpu, me, 4)
		task.wait(0.2)
		casts = 0
		for _, entry in game.sentSince(mark, "AbilityEvent", "Cast") do
			if entry.fighter == cpu.model then
				casts += 1
			end
		end
	end
	assert(me.humanoid.Health < startHealth, "the CPU landed hits")
	assert(casts >= 1, "the CPU used its techniques: " .. casts)
	services.MatchService:endAll()
	task.wait(1)
end)

-- Client visuals -----------------------------------------------------------------------------

check("every effect, wind-up, chain swing and look runs at every degree, in both styles", function()
	local ClientPowers = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Powers"))
	local Settings = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Settings"))
	local client = ClientPowers.module("Grandmaster")
	assert(client, "client module loads")
	local combatEvent = world.find("ReplicatedStorage.Remotes.CombatEvent")

	local function rig(name: string)
		local model = world.Instance.new("Model")
		model.Name = name
		for _, spec in {
			{ "HumanoidRootPart", Vector3.new(2, 2, 1) },
			{ "UpperTorso", Vector3.new(2, 1.6, 1) },
			{ "LowerTorso", Vector3.new(2, 0.4, 1) },
			{ "Head", Vector3.new(1.2, 1.2, 1.2) },
			{ "RightHand", Vector3.new(0.3, 0.3, 0.3) },
			{ "LeftHand", Vector3.new(0.3, 0.3, 0.3) },
			{ "RightFoot", Vector3.new(0.4, 0.3, 0.8) },
			{ "LeftFoot", Vector3.new(0.4, 0.3, 0.8) },
		} do
			local part = world.Instance.new("Part")
			part.Name = spec[1]
			part.Size = spec[2]
			part.CFrame = CFrame.new(0, 3, 0)
			part.Parent = model
		end
		world.Instance.new("Humanoid").Parent = model
		model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
		model:SetAttribute(Attribute.Power, "Grandmaster")
		model.Parent = world.workspace
		return model
	end
	local target = rig("Target")
	target.HumanoidRootPart.CFrame = CFrame.new(4, 3, 0)
	local forward = Vector3.new(1, 0, 0)
	local data = {
		IronFistImpact = { target = target, step = 4, finisher = true, hitStop = 0.05 },
		TwinFist = { target = target },
		CounterPalm = { target = target },
		Step = { direction = forward, duration = 0.2 },
		StepRead = { target = target },
		TigerWindup = { duration = 0.14 },
		TigerStrike = { index = 1, landed = true },
		TigerTell = { duration = 0.3 },
		TigerThrust = { landed = true },
		CraneStance = { duration = 0.45 },
		CraneCounter = { target = target },
		CraneFinish = { target = target },
		CraneMiss = {},
		MountainWindup = { duration = 0.4 },
		MountainCheck = { direction = forward },
		MountainPalm = { landed = true },
		SweepWindup = { duration = 0.3 },
		Sweep = { position = Vector3.new(0, 0, 0), radius = 8 },
		Knockdown = { target = target, duration = 0.9 },
		HundredWindup = { duration = 0.2 },
		HundredWhiff = {},
		HundredOpener = { target = target },
		HundredFlurry = { target = target, finishAt = 0.6, beats = 4, direction = forward },
		HundredBeat = { target = target, index = 2, strike = "Elbow", direction = forward },
		HundredFinish = { target = target, direction = forward },
		FocusStance = { duration = 0.35 },
		Focused = { duration = 0.3, key = "focus" },
		AnswerWindup = { duration = 0.1, direction = forward },
		AnswerPalm = { landed = true, direction = forward },
		UltStance = { duration = 0.5, cinematic = true },
		UltFizzle = {},
		UltOpener = { target = target, cinematic = true },
		UltFlurry = { target = target, finishAt = 1, beats = 5, direction = forward, cinematic = true },
		UltBeat = { target = target, index = 3, strike = "Knee", direction = forward, cinematic = true },
		UltFinish = { target = target, direction = forward, cinematic = true },
		UltShockwave = { position = Vector3.new(0, 0, 0), direction = forward },
	}
	for name in client.fx do
		assert(data[name], "test data for effect " .. name)
	end
	for _, style in { false, true } do
		for _, reduced in { false, true } do
			Settings.values.reducedEffects = reduced
			for degree = 1, 4 do
				local model = rig(`GM{degree}`)
				model:SetAttribute(Attribute.Degree, degree)
				model:SetAttribute(Attribute.Style, if style then "CelestialDragonStyle" else nil)
				local cleanup = client.appearance(ClientPowers.kit(model, "Grandmaster", {}))
				assert(typeof(cleanup) == "function", "appearance returns a cleanup")
				assert(model:FindFirstChild("SNGMSash"), "the sash at every degree")
				local energy = 0
				for _, item in model:GetDescendants() do
					if item.Name == "SNGMEnergy" then
						energy += 1
					end
				end
				assert((energy > 0) == (degree >= 4), `hand and foot energy only at Degree IV (degree {degree})`)
				-- The chain draws its own keys on every swing
				for step = 1, 4 do
					Engine.signalOf(combatEvent, "OnClientEvent"):Fire("Attack", { attacker = model, kind = "Light", step = step, startup = 0.01, active = 0.02 })
				end
				Engine.signalOf(combatEvent, "OnClientEvent"):Fire("Attack", { attacker = model, kind = "Heavy", step = 1, startup = 0.01, active = 0.02 })
				for name, payload in data do
					client.fx[name](ClientPowers.kit(model, "Grandmaster", table.clone(payload)))
				end
				for _, predict in client.predict do
					predict(ClientPowers.kit(model, "Grandmaster", { startup = 0.1 }))
				end
				client.victory(ClientPowers.kit(model, "Grandmaster", {}))
				-- Buying the style mid-session redraws the look
				model:SetAttribute(Attribute.Style, if style then nil else "CelestialDragonStyle")
				Engine.signalOf(model, "Attribute:" .. Attribute.Style):Fire()
				assert(model:FindFirstChild("SNGMSash"), "redrawn after a style change")
				task.wait(0.05)
				cleanup()
				assert(model:FindFirstChild("SNGMSash") == nil, "the look is removed on cleanup")
				model:Destroy()
			end
		end
	end
	Settings.values.reducedEffects = false
	task.wait(1.5)
end)

process.exit(if game.finish() == 0 then 0 else 1)
