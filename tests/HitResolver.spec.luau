local FighterState = Harness.load("Shared/Combat/FighterState")
local HitResolver = Harness.load("Shared/Combat/HitResolver")
local Hitbox = Harness.load("Shared/Combat/Hitbox")
local Config = Harness.load("Shared/Config/Combat")

return function(t)
	-- Attacker at the origin facing -Z; defender 4 studs in front facing the attacker
	local function sides(now)
		local attacker = {
			id = "A",
			state = FighterState.new("A", Config, now),
			position = Vector3.new(0, 0, 0),
			look = Vector3.new(0, 0, -1),
		}
		local defender = {
			id = "D",
			state = FighterState.new("D", Config, now),
			position = Vector3.new(0, 0, -4),
			look = Vector3.new(0, 0, 1),
		}
		return attacker, defender
	end

	local light = Config.Light.Steps[1]

	t.test("a clean hit deals full damage and stuns", function()
		local a, d = sides(0)
		local result = HitResolver.resolve(light, Config, a, d, 1)
		t.equal(result.result, "Hit", "result")
		t.equal(result.damage, light.Damage, "damage")
		HitResolver.apply(result, Config, a, d, 1)
		t.equal(FighterState.isStunned(d.state, 1.1), true, "defender stunned")
		t.equal(d.state.lastAttackerId, "A", "credit recorded")
	end)

	t.test("a front block reduces damage and costs guard", function()
		local a, d = sides(0)
		FighterState.startBlock(d.state, 0)
		local now = 2 -- well past the parry window
		local result = HitResolver.resolve(light, Config, a, d, now)
		t.equal(result.result, "Blocked", "result")
		t.near(result.damage, light.Damage * Config.Block.DamageMultiplier, 1e-9, "chip damage")
		HitResolver.apply(result, Config, a, d, now)
		t.near(FighterState.guardAt(d.state, Config, now), Config.Block.MaxGuard - light.GuardDamage, 1e-9, "guard spent")
		t.equal(FighterState.isStunned(d.state, now + 0.01), false, "blocking isn't stunned")
		t.equal(FighterState.isBlocking(d.state), true, "still blocking")
	end)

	t.test("unblockable attacks go through a front block", function()
		local a, d = sides(0)
		FighterState.startBlock(d.state, 0)
		local unblockable = table.clone(light)
		unblockable.Blockable = false
		local result = HitResolver.resolve(unblockable, Config, a, d, 2)
		t.equal(result.result, "Hit", "lands through the block")
	end)

	t.test("blocking doesn't stop attacks from behind", function()
		local a, d = sides(0)
		d.look = Vector3.new(0, 0, -1) -- facing away from the attacker
		FighterState.startBlock(d.state, 0)
		local result = HitResolver.resolve(light, Config, a, d, 2)
		t.equal(result.result, "Hit", "back attack lands")
	end)

	t.test("raising block right before the hit parries and stuns the attacker", function()
		local a, d = sides(0)
		local attack = FighterState.startHeavy(a.state, Config, 0)
		FighterState.startBlock(d.state, 0.45)
		local result = HitResolver.resolve(Config.Heavy, Config, a, d, attack.activeAt)
		t.equal(result.result, "Parried", "result")
		HitResolver.apply(result, Config, a, d, attack.activeAt)
		t.equal(FighterState.isStunned(a.state, attack.activeAt + 0.5), true, "attacker left open")
		t.equal(FighterState.isCurrent(a.state, attack.token), false, "attacker's attack cancelled")
		t.equal(d.state.lastAttackerId, nil, "a parry gives no knockout credit")
	end)

	t.test("enough guard damage breaks the guard", function()
		local a, d = sides(0)
		FighterState.startBlock(d.state, 0)
		local now = 2
		local first = HitResolver.resolve(Config.Heavy, Config, a, d, now)
		HitResolver.apply(first, Config, a, d, now)
		t.equal(first.result, "Blocked", "first heavy is blocked")
		local second = HitResolver.resolve(Config.Heavy, Config, a, d, now + 0.1)
		t.equal(second.result, "GuardBreak", "second heavy breaks guard")
		HitResolver.apply(second, Config, a, d, now + 0.1)
		t.equal(FighterState.isBlocking(d.state), false, "block dropped")
		t.equal(FighterState.isStunned(d.state, now + 0.2), true, "guard break stun")
	end)

	t.test("invulnerable fighters (dodging, spawn protection) take nothing", function()
		local a, d = sides(0)
		FighterState.startDodge(d.state, Config, 1)
		local result = HitResolver.resolve(Config.Heavy, Config, a, d, 1.1)
		t.equal(result.result, "Invulnerable", "dodged")
		HitResolver.apply(result, Config, a, d, 1.1)
		t.equal(d.state.lastAttackerId, nil, "no credit for a dodged attack")
	end)

	t.test("hits past the combo limit stop stunning", function()
		local a, d = sides(0)
		local now = 1
		local last
		for _ = 1, Config.MaxComboHits + 1 do
			last = HitResolver.resolve(light, Config, a, d, now)
			HitResolver.apply(last, Config, a, d, now)
			now += 0.3
		end
		t.equal(last.comboCapped, true, "capped")
		t.equal(last.hitstun, 0, "no stun past the cap")
		t.truthy(last.knockback >= 45, "pushed clear")
	end)

	t.test("blocked damage can never knock out", function()
		local blocked = { result = "Blocked", damage = 10 }
		t.equal(HitResolver.damageToDeal(blocked, 3), 2, "leaves 1 health")
		t.equal(HitResolver.damageToDeal(blocked, 1), 0, "nothing at 1 health")
		local hit = { result = "Hit", damage = 10 }
		t.equal(HitResolver.damageToDeal(hit, 3), 10, "clean hits can finish")
	end)

	t.test("hitbox: range, arc, height and point blank", function()
		local reach = {
			range = 5,
			arc = 90,
			verticalReach = Config.VerticalReach,
			targetRadius = 1,
			pointBlank = 2,
		}
		local origin = Vector3.new(0, 0, 0)
		local look = Vector3.new(0, 0, -1)
		t.equal(Hitbox.inArc(origin, look, Vector3.new(0, 0, -5.5), reach), true, "in front, in range")
		t.equal(Hitbox.inArc(origin, look, Vector3.new(0, 0, -6.5), reach), false, "too far")
		t.equal(Hitbox.inArc(origin, look, Vector3.new(0, 0, 4), reach), false, "behind")
		t.equal(Hitbox.inArc(origin, look, Vector3.new(0, 0, 1.5), reach), true, "behind but point blank")
		t.equal(Hitbox.inArc(origin, look, Vector3.new(3, 0, -3), reach), true, "45 degrees is inside a 90 degree arc")
		t.equal(Hitbox.inArc(origin, look, Vector3.new(4, 0, -1), reach), false, "outside the arc")
		t.equal(Hitbox.inArc(origin, look, Vector3.new(0, 8, -3), reach), false, "too high")
		t.equal(Hitbox.isInFront(origin, look, Vector3.new(0, 0, -3), 140), true, "front")
		t.equal(Hitbox.isInFront(origin, look, Vector3.new(0, 0, 3), 140), false, "back")
		t.equal(Hitbox.flatDirection(Vector3.new(0, 5, 0)), nil, "vertical has no flat direction")
	end)

	-- Fighting System v2 ---------------------------------------------------------------

	local heavy = Config.Heavy

	t.test("combo scaling: full damage for the first hits, then less each hit, never below the floor", function()
		local scaling = Config.ComboScaling
		for combo = 1, scaling.From do
			t.equal(HitResolver.comboScale(Config, combo), 1, "hit " .. combo)
		end
		t.near(HitResolver.comboScale(Config, scaling.From + 1), 1 - scaling.PerHit, 1e-9, "first scaled hit")
		t.equal(HitResolver.comboScale(Config, 50), scaling.Min, "floor")
		local a, d = sides(0)
		local now = 1
		for _ = 1, scaling.From do
			HitResolver.apply(HitResolver.resolve(light, Config, a, d, now, { basic = true }), Config, a, d, now)
			now += 0.1
		end
		local scaled = HitResolver.resolve(light, Config, a, d, now, { basic = true })
		t.near(scaled.damage, light.Damage * (1 - scaling.PerHit), 1e-9, "the 4th basic hit is scaled")
		local ability = HitResolver.resolve(light, Config, a, d, now, nil)
		t.equal(ability.damage, light.Damage, "non-basic hits aren't scaled")
	end)

	t.test("counter hit: striking a wind-up deals more and stuns longer", function()
		local a, d = sides(0)
		FighterState.startHeavy(d.state, Config, 1)
		local result = HitResolver.resolve(light, Config, a, d, 1.1, { melee = true })
		t.equal(result.tags.counter, true, "counter tag")
		t.near(result.damage, light.Damage * Config.Counter.DamageMultiplier, 1e-9, "counter damage")
		t.near(result.hitstun, light.Hitstun + Config.Counter.ExtraHitstun, 1e-9, "counter stun")
		local ranged = HitResolver.resolve(light, Config, a, d, 1.1, nil)
		t.equal(ranged.tags.counter, nil, "only close-range strikes counter")
	end)

	t.test("punish: striking a whiff's recovery deals more", function()
		local a, d = sides(0)
		local swing = FighterState.startHeavy(d.state, Config, 1) :: any
		FighterState.endActive(d.state, Config, swing.token, false)
		local at = swing.activeEnd + 0.1
		local result = HitResolver.resolve(light, Config, a, d, at, { melee = true })
		t.equal(result.tags.punish, true, "punish tag")
		t.near(result.damage, light.Damage * Config.Punish.DamageMultiplier, 1e-9, "punish damage")
		local landedSides = { sides(0) }
		local la, ld = landedSides[1], landedSides[2]
		local hitSwing = FighterState.startHeavy(ld.state, Config, 1) :: any
		FighterState.endActive(ld.state, Config, hitSwing.token, true)
		local fair = HitResolver.resolve(light, Config, la, ld, hitSwing.activeEnd + 0.1, { melee = true })
		t.equal(fair.tags.punish, nil, "a move that landed isn't punished")
	end)

	t.test("taunting leaves you open to anything (a counter hit)", function()
		local a, d = sides(0)
		FighterState.startTaunt(d.state, Config, 1)
		local result = HitResolver.resolve(light, Config, a, d, 1.2, nil)
		t.equal(result.tags.counter, true, "even a projectile counters a taunt")
	end)

	t.test("parry then riposte: the defender's next light deals bonus damage", function()
		local a, d = sides(0)
		FighterState.startBlock(d.state, 1)
		local parried = HitResolver.resolve(light, Config, a, d, 1.05)
		t.equal(parried.result, "Parried", "parried")
		HitResolver.apply(parried, Config, a, d, 1.05)
		t.truthy(d.state.riposteUntil > 1.05, "riposte window open")
		FighterState.endBlock(d.state, Config, 1.1)
		local riposte = FighterState.startLight(d.state, Config, 1.2) :: any
		t.equal(riposte.riposte, true, "the light is a riposte")
		local result = HitResolver.resolve(light, Config, d, a, 1.3, { riposte = true })
		t.equal(result.tags.riposte, true, "riposte tag")
		t.near(result.damage, light.Damage * Config.Riposte.DamageMultiplier, 1e-9, "riposte damage")
	end)

	t.test("knockdown attacks knock down; a downed fighter takes one weak hit, no stun", function()
		local a, d = sides(0)
		local sweep = Config.Sweep
		local result = HitResolver.resolve(sweep, Config, a, d, 1, { melee = true, basic = true })
		t.equal(result.tags.knockdown, true, "knockdown tag")
		HitResolver.apply(result, Config, a, d, 1)
		t.equal(FighterState.isDowned(d.state, 1.1), true, "downed")
		local otg = HitResolver.resolve(light, Config, a, d, 1.2, { melee = true })
		t.equal(otg.tags.otg, true, "otg tag")
		t.near(otg.damage, light.Damage * Config.Knockdown.OTGDamageMultiplier, 1e-9, "reduced")
		t.equal(otg.hitstun, 0, "no stun")
		t.equal(otg.knockback, 0, "no push")
		HitResolver.apply(otg, Config, a, d, 1.2)
		t.equal(HitResolver.resolve(light, Config, a, d, 1.25).result, "Invulnerable", "no second hit")
	end)

	t.test("launches start a juggle; past the juggle limit hits stop stunning", function()
		local a, d = sides(0)
		local launcher = Config.Launcher
		local up = HitResolver.resolve(launcher, Config, a, d, 1)
		t.equal(up.tags.launch, true, "launch tag")
		HitResolver.apply(up, Config, a, d, 1)
		t.equal(FighterState.isAirborne(d.state, 1.1), true, "airborne")
		local now = 1.1
		for hit = 1, Config.Air.JuggleLimit do
			local kick = HitResolver.resolve(Config.Air.Light, Config, a, d, now)
			t.equal(kick.tags.airborne, true, "airborne tag " .. hit)
			t.equal(kick.juggleCapped, false, "juggle hit " .. hit)
			HitResolver.apply(kick, Config, a, d, now)
			now += 0.1
		end
		local capped = HitResolver.resolve(Config.Air.Light, Config, a, d, now)
		t.equal(capped.juggleCapped, true, "capped")
		t.equal(capped.hitstun, 0, "no stun past the limit")
		t.equal(capped.launch, 0, "no relaunch")
	end)

	t.test("guard: a full charge breaks any guard; winded guards take more", function()
		local a, d = sides(0)
		FighterState.startBlock(d.state, 0)
		local full = table.clone(heavy)
		full.GuardBreak = true
		full.GuardDamage = 1
		t.equal(HitResolver.resolve(full, Config, a, d, 2).result, "GuardBreak", "breaks a full guard")
		local w1, w2 = sides(0)
		FighterState.startBlock(w2.state, 0)
		w2.state.winded = true
		w2.state.stamina = 0
		w2.state.staminaSettledAt = 2
		local winded = HitResolver.resolve(light, Config, w1, w2, 2)
		t.near(winded.guardDamage, light.GuardDamage * Config.Stamina.WindedGuardMultiplier, 1e-9, "winded guard damage")
	end)

	t.test("clashes: two basic strikes meeting at the same moment", function()
		local _, d = sides(0)
		local swing = FighterState.startLight(d.state, Config, 1) :: any
		t.equal(HitResolver.clashes(swing, Config, swing.activeAt - Config.Clash.Window * 0.5), true, "just before it lands")
		t.equal(HitResolver.clashes(swing, Config, swing.activeAt - Config.Clash.Window - 0.05), false, "too early")
		t.equal(HitResolver.clashes(swing, Config, swing.activeEnd + 0.01), false, "after it's over")
		local _, s = sides(0)
		local sweep = FighterState.startSweep(s.state, Config, 1) :: any
		t.equal(HitResolver.clashes(sweep, Config, sweep.activeAt), false, "low attacks don't clash")
		t.equal(HitResolver.clashes(nil, Config, 1), false, "nothing to clash with")
	end)
end
