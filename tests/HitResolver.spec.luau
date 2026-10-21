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
end
