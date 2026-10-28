-- Runs the Animal Shapeshifter end to end with simulated players:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/power_Shapeshifter_test.luau build/game.rbxl
-- Two players fight Shapeshifter against Shapeshifter in a duel. Every form is
-- used at every degree it exists at (Wolf, Spectral Wolf, Hawk, Eagle, Storm
-- Eagle, Bear, Dire Bear, Mythic Bear, Cheetah, Panther, Crocodile, Phoenix):
-- the change and the change back, the form's stats (speed, health, armour,
-- target size, glide), its Light and Heavy replacing the basic attacks, and
-- each Heavy's real effect. Also: Primal costs, drain and the forced change
-- back at 0, the shared switch cooldown, a transition hit out of the air,
-- Primal Ascendancy at every degree (timing bar, perfect timing), a knockout
-- and a match ending mid-form, junk requests, a Shapeshifter CPU, and every
-- client body and effect (with the veil and owner invisibility respected).

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl", function(setup)
	-- One long duel for the whole test
	setup.MatchConfig.Modes.Duel.Duration = 900
end)
local task, Vector3, CFrame = game.task, game.Vector3, game.CFrame
local services, check, request = game.services, game.check, game.request
local world, Engine = game.world, game.Engine
local FighterState = world.require(world.find("ReplicatedStorage.Shared.Combat.FighterState"))
local Protocol = world.require(world.find("ReplicatedStorage.Shared.Protocol"))
local Powers = world.require(world.find("ReplicatedStorage.Shared.Powers"))
local Attribute = Protocol.Attribute
local ID = "Shapeshifter"
local DEF = Powers.get(ID)

game.flatGround(0)

local function now(): number
	return world.workspace:GetServerTimeNow()
end

local alice, bob
local arena

local function A()
	return game.fighter(alice)
end
local function B()
	return game.fighter(bob)
end

local function ability(id: string, degree: number)
	return Powers.abilityFor(ID, id, degree)
end

local function aimAt(from, to)
	return { direction = (to.root.Position - from.root.Position).Unit, point = to.root.Position }
end

local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1e-3)
end

-- Full health and Primal, nothing cooling down, a clean state (the form stays)
local function ready(fighter)
	local runtime = fighter.power
	runtime.resource = runtime.resourceMax
	table.clear(runtime.cooldowns)
	runtime.data.biteStep = nil
	local state = fighter.state
	state.attack = nil
	state.stunUntil = -math.huge
	state.comboCount = 0
	state.blockingSince = nil
	state.lightStep = 0
	state.lightReadyAt = -math.huge
	state.heavyReadyAt = -math.huge
	state.dodgeReadyAt = -math.huge
	state.dodgeUntil = -math.huge
	state.invulnerableUntil = -math.huge
	state.protectedUntil = -math.huge
	services.StatusService:clearAll(fighter)
	fighter.humanoid.Health = fighter.humanoid.MaxHealth
	for _, child in fighter.root:GetChildren() do
		if child.Name == "SNDash" or child.Name == "SNKnockback" then
			child:Destroy()
		end
	end
	services.CharacterService:refresh(fighter)
end

local function equip(fighter, degree: number, loadout: { string }?)
	services.PowerService:equip(fighter, ID, degree, loadout or Powers.defaultLoadout(ID, degree))
	ready(fighter)
end

-- Alice on the left facing Bob, `gap` studs apart, in the middle of the arena
local function stage(gap: number)
	local a, b = A(), B()
	local center = arena.center
	local posA = center + Vector3.new(-gap / 2, 3, 0)
	local posB = center + Vector3.new(gap / 2, 3, 0)
	a.root.CFrame = CFrame.lookAt(posA, posB)
	b.root.CFrame = CFrame.lookAt(posB, posA)
	Engine.syncPositions(world.workspace)
	return a, b
end

local function hitsSince(mark: number, attacker, victim, abilityId: string?)
	local list = {}
	for _, hit in game.sentSince(mark, "CombatEvent", "Hit") do
		if hit.attacker == attacker.model and hit.victim == victim.model and (abilityId == nil or hit.ability == abilityId) then
			table.insert(list, hit)
		end
	end
	return list
end

local function fxSince(mark: number, name: string, fighter)
	local list = {}
	for _, entry in game.sentSince(mark, "AbilityEvent", "Fx") do
		if entry.fx == name and (fighter == nil or entry.fighter == fighter.model) then
			table.insert(list, entry.data)
		end
	end
	return list
end

local function castsSince(mark: number, fighter, abilityId: string)
	local list = {}
	for _, cast in game.sentSince(mark, "AbilityEvent", "Cast") do
		if cast.fighter == fighter.model and cast.ability == abilityId then
			table.insert(list, cast)
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

local function cuesFor(mark: number, player, kind: string)
	local list = {}
	for _, cue in game.sentSince(mark, "DefenseEvent", "Cue", player) do
		if cue.kind == kind then
			table.insert(list, cue)
		end
	end
	return list
end

local function cooldownSet(fighter, abilityId: string): number
	return (fighter.model:GetAttribute(Attribute.CooldownPrefix .. abilityId) or 0) - now()
end

local function statusFrom(target, statusId: string, source)
	local status = services.StatusService:get(target, statusId)
	return status ~= nil and (source == nil or status.sourceId == source.id), status
end

-- Presses a form's key and waits for the transition to finish
local function shift(player, fighter, formId: string)
	local def = ability(formId, fighter.power.degree)
	request("AbilityRequest", player, formId, {})
	task.wait(def.startup + def.active + def.recovery + 0.15)
end

-- Expected combat numbers for a fighter in a form at a degree
local function profileOf(degree: number, formId: string?)
	return Powers.combatProfile(ID, degree, formId)
end

-- Definition -----------------------------------------------------------------------------------

check("Shapeshifter's definition: forms, Primal, evolutions by degree, loadouts, card text", function()
	assert(DEF, "definition")
	assert(Powers.degreeCount(ID) == 3 and #DEF.degrees == 3, "three degrees")
	assert(DEF.resource.id == "Primal" and DEF.resource.max == 100 and DEF.resource.start == 60, "Primal 100, starts at 60")
	assert(DEF.ai and DEF.ai.preferredRange and DEF.ai.aggression, "CPU hints for the power")
	assert(#DEF.name <= 20 and #DEF.description <= 160, "power card text fits")
	local slots = { 3, 4, 5 }
	for degree = 1, 3 do
		local degreeDef = DEF.degrees[degree]
		assert(degreeDef.slots == slots[degree], `degree {degree} slots`)
		assert(degreeDef.ultimate == "PrimalAscendancy", "the ultimate on every degree")
		local ok, reason = Powers.validateLoadout(ID, degree, Powers.defaultLoadout(ID, degree), {})
		assert(ok, `degree {degree} default loadout: {reason}`)
	end
	for abilityId, base in DEF.abilities do
		for degree = base.minDegree or 1, 3 do
			local def = ability(abilityId, degree)
			assert(utf8.len(def.name) <= 20, `{abilityId} name fits: {def.name}`)
			assert(utf8.len(def.description) <= 160, `{abilityId} description fits ({utf8.len(def.description)})`)
			assert(not string.find(def.description, "\u{2014}"), `{abilityId}: no em dashes`)
			assert(def.ai and def.ai.range and def.ai.use, `{abilityId} has CPU hints`)
			if def.kind == "Form" then
				assert(def.form.animal and def.form.drain > 0 and def.form.stats and def.form.basic, `{abilityId} form table`)
				assert(def.form.basic.Light and def.form.basic.Heavy, `{abilityId} replaces Light and Heavy`)
				for _, basicId in { def.form.basic.Light, def.form.basic.Heavy } do
					assert(ability(basicId, degree).basicOnly, `{basicId} is an animal attack`)
				end
				assert((def.cost or 0) > 0 and def.cooldown > 0, `{abilityId} costs Primal and shares a switch cooldown`)
			end
		end
	end
	-- Forms evolve under the same id
	local names = {
		WolfForm = { "Wolf", "Wolf", "Spectral Wolf" },
		HawkForm = { "Hawk", "Eagle", "Storm Eagle" },
		BearForm = { "Bear", "Dire Bear", "Mythic Bear" },
		CheetahForm = { "Cheetah", "Panther", "Panther" },
	}
	for formId, list in names do
		for degree = 1, 3 do
			assert(ability(formId, degree).name == list[degree], `{formId} at degree {degree} is {list[degree]}`)
		end
	end
	assert(ability("CrocodileForm", 2) and DEF.abilities.CrocodileForm.minDegree == 2, "the crocodile from Degree 2")
	assert(DEF.abilities.PhoenixForm.minDegree == 3, "the phoenix at Degree 3")
	-- Degree 1: pick three of four forms, the cheetah bought; it's free from Degree 2
	local available = Powers.available(ID, 1)
	assert(#available == 4 and table.find(available, "CheetahForm"), "four forms to choose from at Degree 1")
	assert(DEF.abilities.CheetahForm.price.money > 0 and DEF.abilities.CheetahForm.freeFrom == 2, "the cheetah has a price at Degree 1")
	assert(#Powers.available(ID, 2) == 5 and #Powers.available(ID, 3) == 6, "five forms at Degree 2, six at Degree 3")
	-- Form stats come through the combat profile at the right degree
	assert(profileOf(1, "BearForm").MaxHealth == 140 and profileOf(2, "BearForm").MaxHealth == 150 and profileOf(3, "BearForm").MaxHealth == 160, "bear health by degree")
	assert(profileOf(1, "WolfForm").Movement.WalkSpeed == 22 and profileOf(3, "WolfForm").Movement.WalkSpeed == 24, "wolf speed by degree")
	assert(profileOf(1, "WolfForm").Dodge.Invulnerable > profileOf(1).Dodge.Invulnerable, "fast forms evade longer")
	assert(profileOf(1, "BearForm").DamageTaken < 1 and profileOf(1, "PhoenixForm").DamageTaken > 1, "heavy forms brace, the phoenix is fragile")
	assert(profileOf(2, "HawkForm").Movement.JumpHeight > profileOf(1).Movement.JumpHeight, "aerial forms jump higher")
	assert(Powers.basicFor(ID, 1, "WolfForm", "Light") == "WolfBite" and Powers.basicFor(ID, 1, "", "Light") == nil, "basics change only in a form")
end)

check("every effect the server sends has a client drawing, and every animal has a body", function()
	local ClientPowers = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Powers"))
	local client = ClientPowers.module(ID)
	assert(client and client.fx and client.appearance and client.build, "client module loads")
	local source = fs.readFile("src/server/Powers/Shapeshifter.luau")
	local names = {}
	for name in string.gmatch(source, ':fx%("(%w+)"') do
		names[name] = true
	end
	for name in string.gmatch(source, 'lastingFx%("(%w+)"') do
		names[name] = true
	end
	local count = 0
	for name in names do
		count += 1
		assert(client.fx[name], "no client effect for " .. name)
	end
	assert(count >= 25, "found the server's effects: " .. count)
	for abilityId, base in DEF.abilities do
		if base.kind == "Form" then
			for degree = base.minDegree or 1, 3 do
				local animal = ability(abilityId, degree).form.animal
				assert(client.Animals[animal], `a body for {animal}`)
			end
		end
		if not base.basicOnly then
			assert(client.predict[abilityId], "an instant wind-up for " .. abilityId)
		end
	end
end)

-- In the duel ----------------------------------------------------------------------------------

check("two players equip Shapeshifter and start a duel in human form", function()
	alice = game.join("Alice")
	bob = game.join("Bob")
	game.waitFor(function()
		return A() ~= nil and A().power ~= nil and B() ~= nil and B().power ~= nil
	end, 2, "powers to be equipped")
	equip(A(), 1)
	equip(B(), 1)
	request("MatchRequest", alice, "Queue", "Duel")
	request("MatchRequest", bob, "Queue", "Duel")
	local match
	game.waitFor(function()
		match = services.MatchService:getMatchOf(A())
		return match ~= nil and match.flow.phase == "Active"
	end, 4, "the duel to begin")
	arena = match.arena
	task.wait(0.2)
	for _, fighter in { A(), B() } do
		assert(fighter.power.id == ID, "Shapeshifter")
		assert(fighter.power.form == "" and fighter.model:GetAttribute(Attribute.Form) == "", "human form")
		assert(fighter.humanoid.MaxHealth == 100 and fighter.combat.TargetRadius == 1.5, "human stats")
		assert(fighter.model:GetAttribute(Attribute.ResourceMax) == 100, "Primal maximum")
		assert(fighter.power.resource >= 59, "Primal starts at 60: " .. fighter.power.resource)
	end
end)

check("Wolf: the change costs Primal, applies the wolf's stats, and every form waits for the switch", function()
	local a, b = stage(4)
	ready(a)
	ready(b)
	local def = ability("WolfForm", 1)
	a.power.resource = 60
	local mark = game.mark()
	request("AbilityRequest", alice, "WolfForm", {})
	task.wait(0.1)
	-- Mid-transition: still human, the change is on its way
	assert(a.power.form == "" and a.power.data.transition ~= nil, "transition under way")
	assert(#fxSince(mark, "ShiftBegin", a) == 1, "the wind-up shows")
	task.wait(def.startup + def.active + def.recovery + 0.1)
	assert(a.power.form == "WolfForm" and a.model:GetAttribute(Attribute.Form) == "WolfForm", "a wolf")
	assert(#fxSince(mark, "Shift", a) == 1, "the change shows")
	assert(a.power.resource < 60 - def.cost + 1 and a.power.resource > 60 - def.cost - 4, "the change cost Primal: " .. a.power.resource)
	local profile = profileOf(1, "WolfForm")
	assert(a.combat == profile, "the wolf's combat profile")
	assert(a.combat.TargetRadius == 1.8, "the wolf's hitbox")
	assert(near(a.humanoid.WalkSpeed, 22), "wolf speed: " .. a.humanoid.WalkSpeed)
	assert(a.humanoid.MaxHealth == 100, "wolf health")
	assert(statusFrom(a, "Transformed", a), "marked as transformed")
	-- The switch cooldown covers every form
	assert(cooldownSet(a, "HawkForm") > 1 and cooldownSet(a, "BearForm") > 1, "every form waits for the switch")
	mark = game.mark()
	request("AbilityRequest", alice, "HawkForm", {})
	request("AbilityRequest", alice, "WolfForm", {})
	task.wait(0.15)
	assert(rejection(mark, alice, "HawkForm") == "cooldown", "no instant switch: " .. tostring(rejection(mark, alice, "HawkForm")))
	assert(rejection(mark, alice, "WolfForm") == "cooldown", "no instant change back")
	assert(a.power.form == "WolfForm", "still a wolf")
end)

check("Wolf: Light is a bite combo, Heavy is a pounce-bite (and stays a tap)", function()
	local a, b = stage(4)
	ready(a)
	ready(b)
	local bite = ability("WolfBite", 1)
	local mark = game.mark()
	for _ = 1, 3 do
		request("CombatRequest", alice, "Light", aimAt(a, b))
		task.wait(bite.cooldown + 0.08)
	end
	task.wait(0.2)
	local casts = castsSince(mark, a, "WolfBite")
	assert(#casts == 3 and casts[1].basic == "Light", "Light became the wolf's bite: " .. #casts)
	local hits = hitsSince(mark, a, b, "WolfBite")
	assert(#hits == 3, "three bites landed: " .. #hits)
	assert(near(hits[1].damage, bite.damage) and near(hits[3].damage, bite.chain.damage), `the third bite tears harder ({hits[1].damage}, {hits[3].damage})`)
	assert(#castsSince(mark, a, "Jab") == 0, "no human punches")
	ready(a)
	ready(b)
	a, b = stage(4)
	mark = game.mark()
	local payload = aimAt(a, b)
	payload.charge = true
	request("CombatRequest", alice, "Heavy", payload)
	task.wait(0.05)
	request("CombatRequest", alice, "HeavyRelease")
	local pounce = ability("WolfPounce", 1)
	task.wait(pounce.startup + pounce.active + 0.3)
	assert(#castsSince(mark, a, "WolfPounce") == 1, "Heavy became the pounce, a tap even when held")
	local landed = hitsSince(mark, a, b, "WolfPounce")
	assert(#landed == 1 and near(landed[1].damage, pounce.damage), "the pounce-bite landed")
	assert(#fxSince(mark, "Pounce", a) == 1 and #fxSince(mark, "PounceBite", a) == 1, "pounce effects")
end)

check("Primal drains while transformed (no regeneration) and runs dry into a forced change back", function()
	local a = A()
	ready(a)
	assert(a.power.form == "WolfForm", "still a wolf")
	local drain = ability("WolfForm", 1).form.drain
	a.power.resource = 50
	task.wait(1)
	local spent = 50 - a.power.resource
	assert(spent > drain * 0.6 and spent < drain * 1.6, `drains about {drain} a second: {spent}`)
	local mark = game.mark()
	a.power.resource = 0.4
	game.waitFor(function()
		return a.power.form == ""
	end, 1, "the forced change back")
	local revert = fxSince(mark, "Unshift", a)[1]
	assert(revert and revert.reason == "Exhausted", "out of Primal")
	assert(a.model:GetAttribute(Attribute.Form) == "" and a.combat == profileOf(1), "human again")
	assert(not statusFrom(a, "Transformed"), "no longer marked as transformed")
	assert(cooldownSet(a, "WolfForm") > DEF.shifting.exhaustedCooldown - 0.6, "a longer wait after running dry")
	-- Human form refills
	local before = a.power.resource
	task.wait(0.6)
	assert(a.power.resource > before, "Primal regenerates in human form")
end)

check("changing back by pressing the form again is free and restores the human numbers", function()
	local a = A()
	ready(a)
	shift(alice, a, "BearForm")
	assert(a.power.form == "BearForm" and a.humanoid.MaxHealth == 140, "a bear (140 health)")
	assert(a.combat.DamageTaken == 0.8 and a.combat.TargetRadius == 2.6, "armour and a big hitbox")
	table.clear(a.power.cooldowns)
	a.power.resource = 5
	local mark = game.mark()
	request("AbilityRequest", alice, "BearForm", {})
	task.wait(0.4)
	assert(a.power.form == "", "pressed again: human")
	assert(rejection(mark, alice, "BearForm") == nil, "allowed with almost no Primal")
	assert(a.power.resource >= 4.5, "changing back costs nothing: " .. a.power.resource)
	assert(a.humanoid.MaxHealth == 100 and a.combat == profileOf(1), "human numbers back")
	assert(#fxSince(mark, "Unshift", a) == 1, "the change back shows")
end)

check("a transition hit out of the air leaves a valid state and refunds part of the cost", function()
	local a, b = stage(3)
	ready(a)
	ready(b)
	a.power.resource = 60
	local def = ability("BearForm", 1)
	local mark = game.mark()
	local pressedAt = os.clock()
	request("AbilityRequest", alice, "BearForm", {})
	task.wait(0.05)
	request("CombatRequest", bob, "Light", aimAt(b, a))
	task.wait(def.startup + 0.4)
	assert(a.power.form == "" and a.model:GetAttribute(Attribute.Form) == "", "still human")
	assert(a.power.data.transition == nil, "no transition left hanging")
	assert(a.combat == profileOf(1), "human numbers")
	assert(#fxSince(mark, "ShiftBroken", a) == 1 and #fxSince(mark, "Shift", a) == 0, "the change broke")
	-- Paid: the cost less the refund, less what human-form regeneration and being hit gave back
	local paid = 60 - a.power.resource
	local expected = def.cost * (1 - DEF.shifting.interruptRefund) - DEF.resource.regen * (os.clock() - pressedAt) - DEF.resource.gainOnHurt
	assert(near(paid, expected, 1.2), `half the cost came back: paid {paid}, expected about {expected}`)
	assert(cooldownSet(a, "BearForm") <= DEF.shifting.interruptCooldown + 0.05, "can try again soon")
	local jab = hitsSince(mark, b, a)[1]
	assert(jab and near(jab.damage, b.combat.Light.Steps[1].Damage * DEF.shifting.transitionDamage, 0.05), "the transition is a vulnerable moment: " .. tostring(jab and jab.damage))
	assert(not FighterState.isAttacking(a.state, now()), "not stuck mid-cast")
	-- Hit while changing from one animal to another: stays the first animal
	ready(a)
	ready(b)
	shift(alice, a, "WolfForm")
	assert(a.power.form == "WolfForm", "a wolf first")
	ready(a)
	ready(b)
	a, b = stage(3)
	mark = game.mark()
	request("AbilityRequest", alice, "HawkForm", {})
	task.wait(0.05)
	request("CombatRequest", bob, "Light", aimAt(b, a))
	task.wait(0.6)
	assert(a.power.form == "WolfForm" and a.combat == profileOf(1, "WolfForm"), "still the wolf, with the wolf's numbers")
	assert(statusFrom(a, "Transformed", a), "still transformed")
	assert(not statusFrom(a, "Gravity", a), "no hawk glide")
	ready(a)
	shift(alice, a, "WolfForm")
	assert(a.power.form == "", "back to human")
end)

-- What each form's Light and Heavy must do (gap: how far apart to stand)
local ATTACKS = {
	WolfForm = { gap = 4 },
	HawkForm = { gap = 4 },
	BearForm = { gap = 5 },
	CheetahForm = { gap = 4 },
	CrocodileForm = { gap = 4 },
	PhoenixForm = { gap = 4 },
}

local function heavyEffect(formId: string, degree: number, mark: number, a, b, def)
	if formId == "WolfForm" and degree >= 3 then
		assert(statusFrom(b, "Mark", a), "Spirit Pounce marks the target")
		assert(#fxSince(mark, "SpiritWolf", a) == 1, "a spirit wolf hounds them")
	elseif formId == "HawkForm" then
		assert(#fxSince(mark, "DiveImpact", a) == 1, "the dive lands")
		if degree >= 3 then
			assert(#cuesFor(mark, bob, "Prompt") >= 1, "the thunder dive is telegraphed")
		end
	elseif formId == "BearForm" then
		assert(#fxSince(mark, "Slam", a) == 1, "the slam lands")
		if degree >= 3 then
			assert(#cuesFor(mark, bob, "Prompt") >= 1, "the rune quake is telegraphed")
		end
	elseif formId == "CheetahForm" then
		assert(statusFrom(a, "Haste", a), "a rush of haste after the burst")
		if degree >= 2 then
			assert(statusFrom(b, "Slow", a), "the panther's pounce slows its prey")
		end
	elseif formId == "CrocodileForm" then
		assert(#fxSince(mark, "RollCatch", a) == 1 and #fxSince(mark, "RollFinish", a) == 1, "caught and rolled")
		assert(#cuesFor(mark, bob, "Mash") >= 1, "the victim could mash to break free")
	elseif formId == "PhoenixForm" then
		assert(statusFrom(b, "Burn", a), "the nova burns")
		assert(#cuesFor(mark, bob, "Prompt") >= 1, "the nova is telegraphed")
	end
	assert(def ~= nil, "")
end

check("every form at every degree: the change, its stats, its Light and Heavy, and the change back", function()
	for degree = 1, 3 do
		for _, formId in Powers.available(ID, degree) do
			local form = ability(formId, degree)
			if form.kind == "Form" then
				equip(A(), degree, { formId })
				equip(B(), 1)
				local a, b = stage(ATTACKS[formId].gap)
				local mark = game.mark()
				shift(alice, a, formId)
				local label = `{form.name} (Degree {degree})`
				assert(a.power.form == formId, label .. ": transformed")
				assert(#castsSince(mark, a, formId) == 1, label .. ": cast once")
				-- Stats
				local profile = profileOf(degree, formId)
				local stats = form.form.stats
				assert(a.combat == profile, label .. ": profile")
				assert(a.humanoid.MaxHealth == (stats.MaxHealth or 100), label .. ": health " .. a.humanoid.MaxHealth)
				assert(a.combat.TargetRadius == (stats.TargetRadius or 1.5), label .. ": hitbox")
				assert(a.combat.DamageTaken == (stats.DamageTaken or 1), label .. ": armour")
				assert(near(a.humanoid.WalkSpeed, profile.Movement.WalkSpeed), label .. ": speed " .. a.humanoid.WalkSpeed)
				assert(near(a.humanoid.JumpHeight, profile.Movement.JumpHeight), label .. ": jump " .. a.humanoid.JumpHeight)
				if form.form.gravity then
					local ok, gravity = statusFrom(a, "Gravity", a)
					assert(ok and near(gravity.magnitude, form.form.gravity), label .. ": glides")
				end
				-- Light
				ready(a)
				ready(b)
				a, b = stage(ATTACKS[formId].gap)
				local light = ability(form.form.basic.Light, degree)
				mark = game.mark()
				request("CombatRequest", alice, "Light", aimAt(a, b))
				task.wait(light.startup + light.active + 0.25)
				assert(#castsSince(mark, a, light.id) == 1, label .. ": Light is " .. light.name)
				local lightHits = hitsSince(mark, a, b, light.id)
				assert(#lightHits == 1 and near(lightHits[1].damage, light.damage), `{label}: {light.name} landed ({#lightHits})`)
				if light.burn then
					assert(statusFrom(b, "Burn", a), label .. ": burning talons")
				end
				-- Heavy
				ready(a)
				ready(b)
				a, b = stage(ATTACKS[formId].gap)
				local heavy = ability(form.form.basic.Heavy, degree)
				mark = game.mark()
				local resource = a.power.resource
				request("CombatRequest", alice, "Heavy", aimAt(a, b))
				task.wait(heavy.startup + heavy.active + (heavy.hold or 0) + 0.4)
				assert(#castsSince(mark, a, heavy.id) == 1, label .. ": Heavy is " .. heavy.name)
				local heavyHits = hitsSince(mark, a, b, heavy.id)
				assert(#heavyHits >= 1, `{label}: {heavy.name} landed`)
				-- (landing it feeds back a little Primal)
				assert(resource - a.power.resource >= (heavy.cost or 0) - DEF.resource.gainOnHit * #heavyHits - 0.01, label .. ": the signature move costs Primal")
				heavyEffect(formId, degree, mark, a, b, heavy)
				-- And back
				ready(a)
				shift(alice, a, formId)
				assert(a.power.form == "" and a.combat == profileOf(degree), label .. ": changed back")
				assert(a.humanoid.MaxHealth == 100, label .. ": human health")
			end
		end
	end
end)

check("Mythic Bear's shockwave rolls past the slam, and a jump clears it", function()
	equip(A(), 3)
	equip(B(), 1)
	local a, b = stage(15)
	shift(alice, a, "BearForm")
	ready(a)
	ready(b)
	local slam = ability("BearSlam", 3)
	local mark = game.mark()
	request("CombatRequest", alice, "Heavy", aimAt(a, b))
	task.wait(slam.startup + 0.5)
	local hits = hitsSince(mark, a, b, "BearSlam")
	assert(#hits == 1 and near(hits[1].damage, slam.shockwave.damage), "the shockwave caught Bob outside the slam: " .. #hits)
	-- Jumping clears it
	ready(a)
	ready(b)
	a, b = stage(15)
	b.root.CFrame += Vector3.new(0, 9, 0)
	Engine.syncPositions(world.workspace)
	mark = game.mark()
	request("CombatRequest", alice, "Heavy", aimAt(a, b))
	task.wait(slam.startup + 0.5)
	assert(#hitsSince(mark, a, b, "BearSlam") == 0, "a jump clears the shockwave")
	ready(a)
	shift(alice, a, "BearForm")
end)

check("Primal Ascendancy at every degree: spirits, a timing bar, the apex beast's strike", function()
	for degree = 1, 3 do
		equip(A(), degree)
		equip(B(), 1)
		local a, b = stage(9)
		if degree == 3 then
			-- Usable mid-form; the form stays
			shift(alice, a, "BearForm")
			ready(a)
		end
		local def = ability("PrimalAscendancy", degree)
		a.power.ult = 100
		local mark = game.mark()
		request("AbilityRequest", alice, "PrimalAscendancy", aimAt(a, b))
		task.wait(0.15)
		assert(a.power.ult < 5, "charge spent")
		local windup = fxSince(mark, "AscendWindup", a)[1]
		assert(windup and #windup.spirits == 3 and windup.apex, "animal spirits and an apex beast")
		local cue
		game.waitFor(function()
			cue = cuesFor(mark, bob, "Timing")[1]
			return cue ~= nil
		end, def.startup + 1, "Bob's timing bar")
		task.wait(math.max(0, cue.impactAt - now()) + 0.5)
		local hits = hitsSince(mark, a, b, "PrimalAscendancy")
		assert(#hits == 1 and near(hits[1].damage, def.damage), `degree {degree}: the strike landed for {def.damage}`)
		assert(#fxSince(mark, "AscendStrike", a) == 1, "the beast crashes down")
		if def.burn then
			assert(statusFrom(b, "Burn", a), "phoenix fire at Degree 3")
		end
		if degree == 3 then
			assert(a.power.form == "BearForm", "still a bear afterwards")
			ready(a)
			shift(alice, a, "BearForm")
		end
		task.wait(def.recovery)
	end
	-- Perfect timing negates it
	equip(A(), 2)
	local a, b = stage(9)
	ready(b)
	a.power.ult = 100
	local mark = game.mark()
	request("AbilityRequest", alice, "PrimalAscendancy", aimAt(a, b))
	local cue
	game.waitFor(function()
		cue = cuesFor(mark, bob, "Timing")[1]
		return cue ~= nil
	end, 3, "Bob's timing bar")
	task.wait(math.max(0, cue.impactAt - now() + 0.025))
	request("DefenseInput", bob, "Timing", cue.id)
	task.wait(0.6)
	local result = game.lastSent("DefenseEvent", "Result", bob)
	assert(result and result.result == "Perfect", "perfect: " .. tostring(result and result.result))
	for _, hit in hitsSince(mark, a, b, "PrimalAscendancy") do
		assert(hit.damage < ability("PrimalAscendancy", 2).damage, "negated")
	end
	task.wait(1)
end)

-- Edge cases -------------------------------------------------------------------------------------

check("junk and out-of-place requests are refused and break nothing", function()
	equip(A(), 1)
	local a = A()
	local mark = game.mark()
	request("AbilityRequest", alice, "WolfBite", {}) -- an animal attack, not a slot
	request("AbilityRequest", alice, "PhoenixForm", {}) -- Degree 3 only
	request("AbilityRequest", alice, "PhantomVeil", {}) -- another power's
	request("AbilityRequest", alice, 42, {})
	request("AbilityRequest", alice, "HawkForm", { direction = Vector3.new(0 / 0, 0, 0), point = "nope" })
	task.wait(0.15)
	assert(rejection(mark, alice, "WolfBite") == "not equipped", "basic-only: " .. tostring(rejection(mark, alice, "WolfBite")))
	assert(rejection(mark, alice, "PhoenixForm") == "not equipped", "not in the loadout")
	assert(rejection(mark, alice, "PhantomVeil") == "unknown", "another power's")
	task.wait(0.6)
	assert(a.power.form == "HawkForm", "junk aim on a form still changes form safely")
	-- In a form, junk basic payloads
	ready(a)
	request("CombatRequest", alice, "Light", { direction = Vector3.new(math.huge, 0, 0), point = "x" })
	request("CombatRequest", alice, "Heavy", "junk")
	task.wait(0.6)
	-- Spamming a form key changes form once
	ready(a)
	shift(alice, a, "HawkForm")
	assert(a.power.form == "", "human")
	ready(a)
	mark = game.mark()
	for _ = 1, 30 do
		request("AbilityRequest", alice, "WolfForm", {})
	end
	task.wait(0.8)
	assert(#castsSince(mark, a, "WolfForm") == 1, "one change from a burst of presses")
	assert(a.power.form == "WolfForm", "a wolf")
	-- No Primal, no change
	ready(a)
	shift(alice, a, "WolfForm")
	ready(a)
	a.power.resource = 3
	mark = game.mark()
	request("AbilityRequest", alice, "BearForm", {})
	task.wait(0.15)
	assert(rejection(mark, alice, "BearForm") == "resource", "not enough Primal")
	assert(a.power.form == "", "still human")
end)

check("§38: a knockout mid-form (and mid-transition) always changes back", function()
	equip(A(), 2)
	equip(B(), 1)
	local a = stage(10)
	shift(alice, a, "HawkForm")
	assert(a.power.form == "HawkForm" and statusFrom(a, "Gravity", a), "an eagle, gliding")
	a.humanoid.Health = 0
	game.waitFor(function()
		return a.power.form == ""
	end, 1, "the knockout to change Alice back")
	assert(a.model:GetAttribute(Attribute.Form) == "", "the body changes back")
	game.waitFor(function()
		local fresh = A()
		return fresh ~= nil and fresh ~= a and fresh.power ~= nil
	end, 5, "Alice to respawn")
	local fresh = A()
	assert(fresh.power.id == ID and fresh.power.form == "", "a human on the new life")
	assert(fresh.model:GetAttribute(Attribute.Form) == "", "no form on the new body")
	assert(not statusFrom(fresh, "Gravity") and not statusFrom(fresh, "Transformed"), "no glide or form marker")
	assert(fresh.combat.TargetRadius == 1.5, "human hitbox")
	-- Knocked out halfway through a transition
	ready(fresh)
	request("AbilityRequest", alice, "BearForm", {})
	task.wait(0.1)
	fresh.humanoid.Health = 0
	task.wait(0.6)
	assert(fresh.power.form == "", "the transition never finished")
	game.waitFor(function()
		local again = A()
		return again ~= nil and again ~= fresh and again.power ~= nil
	end, 5, "Alice to respawn again")
	assert(A().power.form == "" and A().power.data.transition == nil, "clean on the next life")
	task.wait(1.6)
end)

check("§38: the match ending mid-form leaves nothing behind", function()
	equip(A(), 3)
	equip(B(), 3)
	local a, b = stage(10)
	shift(alice, a, "PhoenixForm")
	shift(bob, b, "WolfForm")
	assert(a.power.form == "PhoenixForm" and b.power.form == "WolfForm", "both transformed")
	assert(statusFrom(a, "Gravity", a), "the phoenix glides")
	services.MatchService:endAll()
	task.wait(1.5)
	assert(services.MatchService:getMatchOf(A()) == nil, "match over")
	for _, fighter in { A(), B() } do
		assert(fighter.power.form == "", "changed back")
		assert(fighter.model:GetAttribute(Attribute.Form) == "", "body changed back")
		assert(fighter.combat.TargetRadius == 1.5 and fighter.humanoid.MaxHealth == 100, "human numbers")
		for name in fighter.model:GetAttributes() do
			assert(string.sub(name, 1, 4) ~= "SNS_", "status left: " .. name)
		end
		assert(fighter.power.data.transition == nil and fighter.power.data.formSince == nil, "power state reset")
		assert(fighter.root:FindFirstChild("SNDash") == nil, "no dash left")
	end
end)

check("a Shapeshifter CPU changes form and fights as an animal", function()
	local me = A()
	ready(me)
	request("MatchRequest", alice, "Queue", "Practice", { cpuPower = ID, cpuDegree = 3, cpuDifficulty = "Hard" })
	local practice
	game.waitFor(function()
		practice = services.MatchService:getMatchOf(A())
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
	end, 4, "the CPU Shapeshifter")
	assert(cpu.power.id == ID and cpu.power.degree == 3, "a Degree 3 Shapeshifter")
	me = A()
	local mark = game.mark()
	local started = os.clock()
	local changed, animalAttack = nil, nil
	while os.clock() - started < 16 and not (changed and animalAttack) do
		game.faceOff(cpu, me, 5)
		me.humanoid.Health = me.humanoid.MaxHealth
		task.wait(0.25)
		for _, cast in game.sentSince(mark, "AbilityEvent", "Cast") do
			if cast.fighter == cpu.model then
				local def = ability(cast.ability, 3)
				if def and def.kind == "Form" then
					changed = changed or cast.ability
				elseif def and def.basicOnly then
					animalAttack = animalAttack or cast.ability
				end
			end
		end
	end
	assert(changed, "the CPU changed form")
	assert(animalAttack, "the CPU attacked as an animal")
	services.MatchService:endAll()
	task.wait(1)
	assert(cpu.power == nil or cpu.power.form == "" or not cpu.model.Parent, "the CPU is human (or gone) after the match")
end)

-- Client visuals -----------------------------------------------------------------------------------

check("every animal's body, movement, transformations and effects run on the client", function()
	local ClientPowers = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Powers"))
	local Settings = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Settings"))
	local client = ClientPowers.module(ID)

	local function rig(name: string)
		local model = world.Instance.new("Model")
		model.Name = name
		for _, spec in {
			{ "HumanoidRootPart", Vector3.new(2, 2, 1) },
			{ "UpperTorso", Vector3.new(2, 1.6, 1) },
			{ "Head", Vector3.new(1.2, 1.2, 1.2) },
			{ "LeftLowerArm", Vector3.new(1, 1.2, 1) },
			{ "RightUpperLeg", Vector3.new(1, 1.6, 1) },
		} do
			local part = world.Instance.new("Part")
			part.Name = spec[1]
			part.Size = spec[2]
			part.CFrame = CFrame.new(0, 3, 0)
			part.Transparency = if spec[1] == "HumanoidRootPart" then 1 else 0
			part.Parent = model
		end
		local face = world.Instance.new("Decal")
		face.Name = "face"
		face.Parent = model:FindFirstChild("Head")
		local hat = world.Instance.new("Accessory")
		local handle = world.Instance.new("Part")
		handle.Name = "Handle"
		handle.Parent = hat
		hat.Parent = model
		local humanoid = world.Instance.new("Humanoid")
		humanoid.HipHeight = 2
		humanoid.Parent = model
		model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
		model:SetAttribute(Attribute.Power, ID)
		model.Parent = world.workspace
		return model
	end

	local function countParts(folder: Instance): number
		local total = 0
		for _, item in folder:GetDescendants() do
			if item:IsA("BasePart") then
				total += 1
			end
		end
		return total
	end

	for _, reduced in { false, true } do
		Settings.values.reducedEffects = reduced
		for degree = 1, 3 do
			-- Human form: the pelt and, with degree, the claw necklace and arm marks
			local human = rig("Human" .. degree)
			human:SetAttribute(Attribute.Degree, degree)
			human:SetAttribute(Attribute.Form, "")
			local cleanup = client.appearance(ClientPowers.kit(human, ID, {}))
			assert(typeof(cleanup) == "function", "human look returns a cleanup")
			local look = human:FindFirstChild("SNShapeLook")
			assert(look and countParts(look) >= 7, "the pelt mantle")
			if degree >= 2 then
				assert(countParts(look) >= 13, "claw necklace from Degree 2")
			end
			cleanup()
			assert(human:FindFirstChild("SNShapeLook") == nil, "human look removed")
			human:Destroy()

			for _, formId in Powers.available(ID, degree) do
				local form = ability(formId, degree)
				if form.kind == "Form" then
					local model = rig(formId .. degree)
					local torso = model:FindFirstChild("UpperTorso")
					local head = model:FindFirstChild("Head")
					local root = model:FindFirstChild("HumanoidRootPart")
					model:SetAttribute(Attribute.Degree, degree)
					model:SetAttribute(Attribute.Form, formId)
					client.fx.Shift(ClientPowers.kit(model, ID, { form = formId, animal = form.form.animal }))
					local remove = client.appearance(ClientPowers.kit(model, ID, {}))
					local animal = model:FindFirstChild("SNShapeAnimal")
					assert(animal, `{form.name}: a body`)
					assert(countParts(animal) >= 30, `{form.name}: a detailed body ({countParts(animal)} parts)`)
					local welds = 0
					for _, item in animal:GetDescendants() do
						if item:IsA("Weld") then
							welds += 1
						end
					end
					assert(welds == countParts(animal), `{form.name}: every piece welded to the skeleton`)
					assert(torso.Transparency == 1 and head.Transparency == 1, `{form.name}: the human body is hidden`)
					assert(torso:GetAttribute("SNShapeSaved") == 0, "its own transparency saved under the power's name")
					assert((head:FindFirstChild("face") :: any).Transparency == 1, "the face is hidden")
					assert((model:FindFirstChild("Handle", true) :: any).Transparency == 1, "accessories are hidden")
					assert(root.Transparency == 1 and root:GetAttribute("SNShapeSaved") == nil, "the root is left alone")
					-- Running, jumping, attacking: the skeleton animates
					for step = 1, 12 do
						root.CFrame = root.CFrame + Vector3.new(0.5, if step > 8 then 0.4 else 0, 0)
						Engine.syncPositions(model)
						Engine.step(world.game, 1, 1 / 30)
					end
					for abilityId, predict in client.predict do
						predict(ClientPowers.kit(model, ID, { ability = abilityId, startup = 0.2, active = 0.1, predicted = true }))
					end
					for _, basicId in { form.form.basic.Light, form.form.basic.Heavy } do
						client.onCast(ClientPowers.kit(model, ID, { ability = basicId, startup = 0.2, active = 0.1, basic = "Light" }))
						Engine.step(world.game, 4, 1 / 30)
					end
					-- The veil (Concealed) changes the body's transparency on the server while hidden
					torso.Transparency = 0.85
					Engine.signalOf(torso, "Property:Transparency"):Fire()
					assert(torso.Transparency == 1 and near(torso:GetAttribute("SNShapeSaved") or 0, 0.85, 1e-4), "the veil's value is kept, the body stays hidden")
					-- The owner panel's invisibility marks parts it hides
					head:SetAttribute("SNVisibleTransparency", 0)
					remove()
					task.wait(0.3)
					assert(model:FindFirstChild("SNShapeAnimal") == nil, `{form.name}: the body is removed`)
					assert(near(torso.Transparency, 0.85, 1e-4) and torso:GetAttribute("SNShapeSaved") == nil, "the veil's transparency is restored")
					assert(head.Transparency == 1, "the owner's invisibility is respected")
					assert((head:FindFirstChild("face") :: any).Transparency == 0, "the face is back")
					model:Destroy()
				end
			end
		end
	end
	Settings.values.reducedEffects = false

	-- Every effect with real data, then junk
	local model = rig("Effects")
	local target = rig("Target")
	target:FindFirstChild("HumanoidRootPart").CFrame = CFrame.new(4, 3, 0)
	for degree = 1, 3 do
		for _, formId in { "WolfForm", "HawkForm", "BearForm", "" } do
			model:SetAttribute(Attribute.Degree, degree)
			model:SetAttribute(Attribute.Form, formId)
			local remove = client.appearance(ClientPowers.kit(model, ID, {}))
			local position = Vector3.new(3, 0, 0)
			local data = {
				ShiftBegin = { form = "WolfForm", animal = "Wolf", duration = 0.3 },
				Shift = { form = "BearForm", animal = "MythicBear" },
				ShiftBroken = { form = "BearForm" },
				Unshift = { form = "HawkForm", animal = "StormEagle", reason = "Exhausted" },
				Bite = { step = 3, finisher = true, duration = 0.1 },
				PounceCrouch = { duration = 0.2 },
				Pounce = { duration = 0.2, direction = Vector3.new(1, 0, 0) },
				PounceBite = { target = target, spirit = true },
				SpiritWolf = { target = target, duration = 0.4, key = "spirit" .. degree },
				Talon = { duration = 0.1, airborne = true },
				DiveWindup = { duration = 0.2, lightning = true },
				Dive = { duration = 0.2, direction = Vector3.new(1, 0, 0), lightning = true },
				DiveImpact = { position = position, radius = 7, lightning = true },
				Maul = { side = -1, duration = 0.18 },
				SlamRear = { duration = 0.3, runes = true },
				Slam = { position = position, radius = 8, shockwave = 15 },
				Swipe = { duration = 0.08 },
				BurstCrouch = { duration = 0.1, pounce = true },
				Burst = { duration = 0.2, direction = Vector3.new(1, 0, 0), pounce = true },
				BurstHit = { target = target, pounce = true },
				Snap = { duration = 0.2 },
				JawsOpen = { duration = 0.2 },
				JawsWhiff = {},
				RollCatch = { target = target, hold = 0.3 },
				RollBroken = { target = target },
				RollFinish = { target = target },
				Cinder = { duration = 0.1 },
				NovaRise = { duration = 0.2 },
				Nova = { position = position, radius = 10 },
				AscendWindup = { duration = 0.4, spirits = { "SpectralWolf", "StormEagle", "MythicBear" }, apex = "MythicBear", range = 20 },
				AscendFizzle = {},
				AscendStrike = { origin = position, direction = Vector3.new(1, 0, 0), range = 20, arc = 110, apex = "MythicBear", fire = true },
			}
			for name, handler in client.fx do
				handler(ClientPowers.kit(model, ID, data[name] or {}))
				-- Junk data never breaks an effect
				handler(ClientPowers.kit(model, ID, { position = "x", target = 4, duration = "y", direction = Vector3.zero, spirits = "z", apex = 5, radius = 0 / 0 }))
			end
			client.fx.AscendStrike(ClientPowers.kit(model, ID, data.AscendStrike))
			Engine.step(world.game, 20, 1 / 30)
			task.wait(0.05)
			if remove then
				remove()
			end
		end
	end
	-- Free-standing bodies in every pose (spirits, previews)
	for animalId in client.Animals do
		for _, pose in { "Bite", "Maul", "Crouch", "Leap", "Rear", "Slam", "Roll", "Flinch", "Howl", "Gape", "Talon", "Dive", "Rise", "Nova", "Snap" } do
			local spirit = client.build(animalId, { mode = "Anchored", frame = CFrame.new(0, 3, 10), parent = world.workspace, ghost = roblox.Color3.new(1, 0.7, 0.3) })
			client.still(spirit, pose, 0.4, 12, pose == "Dive")
			spirit:destroy()
		end
	end
	task.wait(1)
	model:Destroy()
	target:Destroy()
end)

process.exit(if game.finish() == 0 then 0 else 1)
