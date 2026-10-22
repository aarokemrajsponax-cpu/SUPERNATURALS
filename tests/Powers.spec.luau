local Powers = Harness.load("Shared/Powers")
local Combat = Harness.load("Shared/Config/Combat")
local Schema = Harness.load("Shared/Data/Schema")

local KINDS = {
	Melee = true, Area = true, Grab = true, Dash = true, Projectile = true, Throw = true, Counter = true,
	Zone = true, Buff = true, Teleport = true, Form = true, Construct = true, Ultimate = true,
}
local TAGS = { Melee = true, Small = true, Heavy = true, Area = true, Grab = true, Projectile = true, Massive = true }

return function(t)
	t.test("there are exactly eight powers, in the selection order", function()
		t.equal(#Powers.Order, 8, "count")
		for _, id in Powers.Order do
			t.truthy(Powers.get(id), "definition for " .. id)
		end
	end)

	t.test("every power is complete: its degrees, valid abilities, an ultimate", function()
		for _, id in Powers.Order do
			local def = Powers.get(id)
			if def then
				t.equal(def.id, id, id .. " id")
				local count = Powers.degreeCount(id)
				t.equal(#def.degrees, count, id .. " degrees")
				t.truthy(count >= 3 and count <= Powers.MaxDegrees, id .. " degree count")
				t.truthy(def.name and def.description and def.icon, id .. " text")
				t.truthy(def.difficulty >= 1 and def.difficulty <= 5, id .. " difficulty")
				for _, abilityId in def.abilityOrder do
					local ability = def.abilities[abilityId]
					t.truthy(ability, `{id}.{abilityId} exists`)
					if ability then
						t.truthy(KINDS[ability.kind], `{id}.{abilityId} kind {tostring(ability.kind)}`)
						t.truthy(ability.name and ability.description and ability.icon, `{id}.{abilityId} text`)
						t.truthy(typeof(ability.cooldown) == "number", `{id}.{abilityId} cooldown`)
						for _, tag in ability.tags or {} do
							t.truthy(TAGS[tag], `{id}.{abilityId} tag {tag}`)
						end
						if ability.price then
							t.truthy((ability.price.money or 0) > 0 or (ability.price.gems or 0) > 0, `{id}.{abilityId} price`)
						end
					end
				end
				for abilityId in def.abilities do
					t.truthy(table.find(def.abilityOrder, abilityId), `{id}.{abilityId} listed in abilityOrder`)
				end
				for degree = 1, Powers.degreeCount(id) do
					local degreeDef = def.degrees[degree]
					local ultimate = def.abilities[degreeDef.ultimate]
					t.truthy(ultimate and ultimate.kind == "Ultimate", `{id} degree {degree} ultimate`)
					t.truthy(degreeDef.slots >= 1 and degreeDef.slots <= 6, `{id} degree {degree} slots`)
					if degree > 1 then
						t.truthy(degreeDef.unlock and degreeDef.unlock.mastery and degreeDef.unlock.money, `{id} degree {degree} unlock`)
					end
				end
			end
		end
	end)

	t.test("every degree's default loadout is valid with nothing bought", function()
		for _, id in Powers.Order do
			for degree = 1, Powers.degreeCount(id) do
				local ok, reason = Powers.validateLoadout(id, degree, Powers.defaultLoadout(id, degree), {})
				t.equal(ok, true, `{id} degree {degree} default ({tostring(reason)})`)
			end
		end
	end)

	t.test("higher degrees keep everything lower degrees could equip", function()
		for _, id in Powers.Order do
			for degree = 2, Powers.degreeCount(id) do
				local lower = Powers.available(id, degree - 1)
				local higher = Powers.available(id, degree)
				for _, abilityId in lower do
					t.truthy(table.find(higher, abilityId), `{id} {abilityId} still available at degree {degree}`)
				end
			end
		end
	end)

	t.test("loadout rules: no duplicates, no other degrees, slots, ownership", function()
		local ok = Powers.validateLoadout("StrongDude", 1, { "Groundbreaker", "Groundbreaker" }, {})
		t.equal(ok, false, "duplicates rejected")
		ok = Powers.validateLoadout("StrongDude", 1, { "SeismicFissure" }, {})
		t.equal(ok, false, "degree 3 ability rejected at degree 1")
		ok = Powers.validateLoadout("StrongDude", 1, { "Groundbreaker", "TitanGrip", "MeteorCharge", "CrushingUppercut" }, { abilities = { CrushingUppercut = true } })
		t.equal(ok, false, "too many for 3 slots")
		ok = Powers.validateLoadout("StrongDude", 1, { "CrushingUppercut" }, {})
		t.equal(ok, false, "locked ability rejected")
		local cleaned
		ok, _, cleaned = Powers.validateLoadout("StrongDude", 1, { "CrushingUppercut" }, { abilities = { CrushingUppercut = true } })
		t.equal(ok, true, "bought ability accepted")
		t.equal(cleaned and cleaned[1], "CrushingUppercut", "cleaned list")
		ok = Powers.validateLoadout("StrongDude", 1, { "WorldBreaker" }, {})
		t.equal(ok, false, "ultimates aren't slotted")
		ok = Powers.validateLoadout("StrongDude", 1, "junk", {})
		t.equal(ok, false, "junk rejected")
		ok = Powers.validateLoadout("StrongDude", 1, { [2] = "Groundbreaker", x = "y" }, {})
		t.equal(ok, false, "non-list rejected")
		ok = Powers.validateLoadout("Ghost", 1, { "Groundbreaker" }, {})
		t.equal(ok, false, "another power's ability rejected")
	end)

	t.test("degree scaling stacks and doesn't change the base definition", function()
		local d1 = Powers.abilityFor("StrongDude", "Groundbreaker", 1)
		local d3 = Powers.abilityFor("StrongDude", "Groundbreaker", 3)
		t.equal(d1.damage, 12, "degree 1")
		t.equal(d3.damage, 18, "degree 3")
		t.equal(d3.radius, 18, "degree 3 radius")
		t.equal(d3.cooldown, d1.cooldown, "unchanged fields carry over")
		t.equal(Powers.get("StrongDude").abilities.Groundbreaker.damage, 12, "definition untouched")
		t.equal(d3.id, "Groundbreaker", "id filled in")
	end)

	t.test("combat profiles merge power and degree stats over the defaults", function()
		local base = Powers.combatProfile(nil)
		t.equal(base, Combat, "no power = defaults")
		local d1 = Powers.combatProfile("StrongDude", 1)
		local d3 = Powers.combatProfile("StrongDude", 3)
		t.equal(d1.MaxHealth, 125, "power health")
		t.equal(d3.MaxHealth, 135, "degree health")
		t.equal(d1.Movement.WalkSpeed, 15, "power walk speed")
		t.equal(d1.Movement.JumpHeight, Combat.Movement.JumpHeight, "untouched values kept")
		t.equal(d1.Block.MaxGuard, 140, "block override")
		t.equal(d1.Block.ParryWindow, Combat.Block.ParryWindow, "block defaults kept")
		t.equal(#d1.Light.Steps, 4, "light chain replaced as a whole")
		t.equal(Combat.MaxHealth, 100, "defaults untouched")
	end)

	t.test("degrees unlock in order by mastery or purchase", function()
		t.equal(Powers.degreeUnlocked("StrongDude", 1, {}), true, "degree 1 open")
		t.equal(Powers.degreeUnlocked("StrongDude", 2, {}), false, "degree 2 locked")
		t.equal(Powers.degreeUnlocked("StrongDude", 2, { xp = 400 }), true, "mastery 3 opens degree 2")
		t.equal(Powers.degreeUnlocked("StrongDude", 3, { xp = 400 }), false, "degree 3 needs more")
		t.equal(Powers.degreeUnlocked("StrongDude", 2, { degrees = { ["2"] = true } }), true, "bought degree 2")
		t.equal(Powers.degreeUnlocked("StrongDude", 3, { degrees = { ["3"] = true } }), true, "bought degree 3")
		t.equal(Powers.masteryLevel(0), 1, "level 1")
		t.equal(Powers.masteryLevel(400), 3, "level 3")
		t.equal(Powers.nextLevelXp(0), 150, "next level")
	end)

	t.test("premium powers are marked with a Robux price and a Gems path", function()
		local prices = { Corruption = 6666, Syntax = 9999, Admin = 12000 }
		for id, robux in prices do
			local def = Powers.get(id)
			if def then
				t.truthy(def.premium, id .. " premium")
				t.equal(def.premium.robux, robux, id .. " price")
				t.truthy(def.premium.gems and def.premium.gems > 0, id .. " gems path")
				t.truthy(def.premium.pass, id .. " pass key")
			end
		end
		for _, id in { "StrongDude", "Ghost", "Shapeshifter", "MachineMaster", "Grandmaster" } do
			local def = Powers.get(id)
			if def then
				t.equal(def.premium, nil, id .. " is free")
			end
		end
	end)

	t.test("powers can declare their own degree count; three stays the default", function()
		t.equal(Powers.degreeCount("StrongDude"), Powers.Degrees, "default count")
		t.equal(Powers.degreeCount("Grandmaster"), 4, "four degrees")
		t.equal(Powers.degreeCount("Nobody"), 0, "unknown power")
		t.equal(Powers.validDegree("Grandmaster", 4), true, "degree 4 exists")
		t.equal(Powers.validDegree("StrongDude", 4), false, "no degree 4 for a three-degree power")
		t.equal(Powers.validDegree("Grandmaster", 2.5), false, "fractions rejected")
		t.equal(Powers.degree("StrongDude", 4), nil, "no degree 4 definition")
		t.equal(Powers.abilityFor("StrongDude", "Groundbreaker", 4), nil, "no stats at a missing degree")
		t.equal(Powers.degreeUnlocked("StrongDude", 4, { degrees = { ["4"] = true } }), false, "can't unlock a missing degree")
		local ok = Powers.validateLoadout("StrongDude", 4, { "Groundbreaker" }, {})
		t.equal(ok, false, "loadout for a missing degree rejected")
		t.equal(Powers.combatProfile("StrongDude", 4).MaxHealth, 125, "missing degree adds no stats")
		-- Saved data has to agree with the definitions about degree counts
		for _, id in Powers.Order do
			if Powers.get(id) then
				t.equal(Schema.degreesOf(id), Powers.degreeCount(id), id .. " saved-data degree count")
			end
		end
		t.truthy(Schema.Config.MaxDegree >= Powers.MaxDegrees, "saved data allows the top degree")
		local repaired = Schema.migrate({ powers = { StrongDude = { degrees = { ["2"] = true, ["4"] = true } }, Grandmaster = { degrees = { ["4"] = true, ["5"] = true } } }, loadouts = { StrongDude = { ["4"] = { "Groundbreaker" } }, Grandmaster = { ["4"] = { "TigerClaw" } } } })
		t.equal(repaired.powers.StrongDude.degrees["4"], nil, "no degree 4 for Strong Dude")
		t.equal(repaired.powers.StrongDude.degrees["2"], true, "real degree kept")
		t.equal(repaired.powers.Grandmaster.degrees["4"], true, "Grandmaster degree 4 kept")
		t.equal(repaired.powers.Grandmaster.degrees["5"], nil, "no degree 5")
		t.equal(repaired.loadouts.StrongDude["4"], nil, "loadout for a missing degree dropped")
		t.equal(repaired.loadouts.Grandmaster["4"][1], "TigerClaw", "degree 4 loadout kept")
	end)

	t.test("The Grandmaster: four degrees, free, techniques scale and stack", function()
		local def = Powers.get("Grandmaster")
		t.truthy(def, "definition")
		if not def then
			return
		end
		t.equal(def.premium, nil, "free to play")
		t.equal(def.degrees[4].unlock.mastery, 14, "degree 4 mastery")
		t.equal(def.degrees[4].unlock.money, 15000, "degree 4 money")
		t.equal(Powers.degreeUnlocked("Grandmaster", 4, { xp = 999999 }), true, "mastery opens degree 4")
		t.equal(Powers.degreeUnlocked("Grandmaster", 4, { xp = 11600 }), false, "mastery 13 isn't enough")
		t.equal(Powers.degreeUnlocked("Grandmaster", 4, { degrees = { ["4"] = true } }), true, "bought degree 4")
		local expected = {
			{ "DragonsStep", "TigerClaw" },
			{ "DragonsStep", "TigerClaw", "CranesReversal", "IronMountain" },
			{ "DragonsStep", "TigerClaw", "CranesReversal", "IronMountain", "SweepingDragon", "HundredFists", "FocusState" },
			{ "DragonsStep", "TigerClaw", "CranesReversal", "IronMountain", "SweepingDragon", "HundredFists", "FocusState", "DragonsAnswer" },
		}
		for degree, list in expected do
			local available = Powers.available("Grandmaster", degree)
			t.equal(#available, #list, `degree {degree} technique count`)
			for _, abilityId in list do
				t.truthy(table.find(available, abilityId), `{abilityId} at degree {degree}`)
			end
			t.equal(Powers.ultimateOf("Grandmaster", degree), "HeavenSplittingDragon", `ultimate at degree {degree}`)
		end
		local ult1 = Powers.abilityFor("Grandmaster", "HeavenSplittingDragon", 1)
		local ult4 = Powers.abilityFor("Grandmaster", "HeavenSplittingDragon", 4)
		t.equal(ult1.cinematic, false, "short version below degree 4")
		t.equal(ult4.cinematic, true, "full cinematic at degree 4")
		t.truthy(#ult4.beats > #ult1.beats, "more beats at degree 4")
		t.truthy(ult4.damage > ult1.damage, "ultimate scales")
		t.equal(Powers.abilityFor("Grandmaster", "HeavenSplittingDragon", 3).opener.damage, 7, "degree 2 opener carries to 3")
		t.truthy(Powers.abilityFor("Grandmaster", "DragonsStep", 4).opening > Powers.abilityFor("Grandmaster", "DragonsStep", 1).opening, "longer opening")
		local profile = Powers.combatProfile("Grandmaster", 4)
		t.equal(#profile.Light.Steps, 4, "Iron Fist chain")
		t.equal(profile.MaxHealth, 110, "degree 4 health")
		t.truthy(profile.Light.Steps[1].Startup < Combat.Light.Steps[1].Startup, "faster than the default chain")
		t.truthy(profile.Light.Steps[1].Damage < Combat.Light.Steps[1].Damage, "lighter than the default chain")
		t.truthy(profile.Light.Steps[4].Finisher, "the kick ends the chain")
		for abilityId, ability in def.abilities do
			t.truthy(utf8.len(ability.description) <= 160, `{abilityId} description fits a card`)
			t.equal(string.find(ability.description, "\u{2014}"), nil, `{abilityId} has no em dash`)
		end
	end)
end
