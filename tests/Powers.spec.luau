local Powers = Harness.load("Shared/Powers")
local Combat = Harness.load("Shared/Config/Combat")

local KINDS = {
	Melee = true, Area = true, Grab = true, Dash = true, Projectile = true, Throw = true, Counter = true,
	Zone = true, Buff = true, Teleport = true, Form = true, Construct = true, Ultimate = true,
}
local TAGS = { Melee = true, Small = true, Heavy = true, Area = true, Grab = true, Projectile = true, Massive = true }

return function(t)
	t.test("there are exactly seven powers, in the selection order", function()
		t.equal(#Powers.Order, 7, "count")
		for _, id in Powers.Order do
			t.truthy(Powers.get(id), "definition for " .. id)
		end
	end)

	t.test("every power is complete: three degrees, valid abilities, an ultimate", function()
		for _, id in Powers.Order do
			local def = Powers.get(id)
			if def then
				t.equal(def.id, id, id .. " id")
				t.equal(#def.degrees, 3, id .. " degrees")
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
				for degree = 1, 3 do
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
			for degree = 1, 3 do
				local ok, reason = Powers.validateLoadout(id, degree, Powers.defaultLoadout(id, degree), {})
				t.equal(ok, true, `{id} degree {degree} default ({tostring(reason)})`)
			end
		end
	end)

	t.test("higher degrees keep everything lower degrees could equip", function()
		for _, id in Powers.Order do
			for degree = 2, 3 do
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
		for _, id in { "StrongDude", "Ghost", "Shapeshifter", "MachineMaster" } do
			local def = Powers.get(id)
			if def then
				t.equal(def.premium, nil, id .. " is free")
			end
		end
	end)
end
