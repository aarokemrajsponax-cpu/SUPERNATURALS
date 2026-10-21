-- Saved data: the profile's defaults, migration and repair of bad data, the
-- client's safe view, and the settings sanitizer (Shared/Data/Schema).

local Schema = Harness.load("Shared/Data/Schema")

local function count(map): number
	local total = 0
	for _ in map do
		total += 1
	end
	return total
end

return function(t)
	t.test("default profile has the full shape and starting balances", function()
		local profile = Schema.default()
		t.equal(profile.version, Schema.VERSION, "version")
		t.equal(profile.currencies.money, Schema.Config.StartingMoney, "money")
		t.equal(profile.currencies.gems, Schema.Config.StartingGems, "gems")
		for _, key in { "matches", "wins", "losses", "draws", "knockouts", "deaths", "playSeconds", "streak", "bestStreak" } do
			t.equal(profile.stats[key], 0, "stats." .. key)
		end
		t.equal(profile.selected.power, "StrongDude", "selected power")
		t.equal(profile.selected.degree, 1, "selected degree")
		t.equal(profile.base.access, "Everyone", "base access")
		t.equal(profile.base.capacity, 1, "base capacity")
		t.equal(#profile.base.items, 0, "no furniture placed")
		t.equal(profile.settings.musicVolume, 0.5, "music volume")
		t.equal(profile.settings.cameraShake, true, "camera shake")
		t.equal(profile.tutorial.welcomed, false, "not welcomed yet")
		t.equal(#profile.receipts, 0, "no receipts")
		t.equal(profile.meta.sessions, 0, "no sessions")
		t.truthy(Schema.storable(profile), "storable in a DataStore")
	end)

	t.test("default() returns a fresh copy every time", function()
		local first = Schema.default()
		first.currencies.money = 1
		first.powers.Ghost = { xp = 5 }
		first.settings.uiScale = 0.8
		local second = Schema.default()
		t.equal(second.currencies.money, Schema.Config.StartingMoney, "money untouched")
		t.equal(second.powers.Ghost, nil, "powers untouched")
		t.equal(second.settings.uiScale, 1, "settings untouched")
	end)

	t.test("migrate(nil) and junk give a default, saveable profile", function()
		for _, junk in { nil, 5, "text", true } do
			local profile, readOnly = Schema.migrate(junk)
			t.equal(readOnly, false, "not read-only for " .. tostring(junk))
			t.equal(profile.currencies.money, Schema.Config.StartingMoney, "money for " .. tostring(junk))
			t.equal(profile.version, Schema.VERSION, "version for " .. tostring(junk))
		end
	end)

	t.test("migrate fills missing keys and keeps good values", function()
		local profile, readOnly = Schema.migrate({
			version = 1,
			currencies = { money = 1234 },
			stats = { wins = 7 },
			powers = { Ghost = { xp = 40, degrees = { ["2"] = true } } },
			loadouts = { Ghost = { ["1"] = { "Phase", "Haunt" } } },
			base = { items = { { i = "Sofa", x = 4, z = -2, r = 1, c = 2, m = 3 } } },
		})
		t.equal(readOnly, false, "not read-only")
		t.equal(profile.currencies.money, 1234, "money kept")
		t.equal(profile.currencies.gems, Schema.Config.StartingGems, "gems filled")
		t.equal(profile.stats.wins, 7, "wins kept")
		t.equal(profile.stats.losses, 0, "losses filled")
		t.equal(profile.powers.Ghost.xp, 40, "xp kept")
		t.equal(profile.powers.Ghost.degrees["2"], true, "degree kept")
		t.equal(profile.powers.Ghost.owned, false, "owned filled")
		t.equal(count(profile.powers.Ghost.abilities), 0, "abilities filled")
		t.equal(profile.loadouts.Ghost["1"][2], "Haunt", "loadout kept")
		t.equal(profile.base.items[1].i, "Sofa", "furniture kept")
		t.equal(profile.base.items[1].m, 3, "furniture material kept")
		t.equal(profile.settings.sfxVolume, 0.8, "settings filled")
		t.equal(profile.daily.loginStreak, 0, "daily filled")
		t.truthy(Schema.storable(profile), "storable")
	end)

	t.test("migrate drops wrongly typed and out-of-range values", function()
		local profile = Schema.migrate({
			version = 1,
			currencies = { money = "lots", gems = -50 },
			stats = { wins = 0 / 0, knockouts = 3.7, deaths = math.huge },
			powers = { Ghost = "broken", [5] = { xp = 1 }, Shapeshifter = { xp = -3, degrees = { ["2"] = "yes", ["3"] = true } } },
			loadouts = { Ghost = { ["1"] = { "Phase", 7, "Phase", "Haunt" } }, Bad = 4 },
			selected = { power = 12, degree = 9 },
			cosmetics = { owned = { Halo = true, Junk = 1 }, equipped = { aura = "Halo", trail = false } },
			furniture = { owned = { Lamp = 3, Ghost = -1, Bed = "two" } },
			base = { access = "Hackers", capacity = 0, items = { { i = "Sofa", x = 0 / 0, z = 1 }, "junk", { i = "Lamp", x = 1, z = 2, r = 9 } } },
			daily = { day = "today", progress = { Win3 = 2, Junk = "x" }, claimed = { Win3 = true } },
			tutorial = { done = { Move = true }, welcomed = "yes" },
			settings = { musicVolume = 3, uiScale = "big", cameraShake = 1 },
			passes = { CorruptionPower = true, SyntaxPower = "yes" },
			receipts = { "a", 5, "b" },
			rewardLog = { 10, "x", 20 },
			meta = "nope",
		})
		t.equal(profile.currencies.money, Schema.Config.StartingMoney, "string money replaced")
		t.equal(profile.currencies.gems, 0, "negative gems clamped")
		t.equal(profile.stats.wins, 0, "NaN wins replaced")
		t.equal(profile.stats.knockouts, 3, "fractional knockouts floored")
		t.equal(profile.stats.deaths, 0, "infinite deaths replaced")
		t.equal(profile.powers.Ghost, nil, "broken power dropped")
		t.equal(count(profile.powers), 1, "number-keyed power dropped")
		t.equal(profile.powers.Shapeshifter.xp, 0, "negative xp clamped")
		t.equal(profile.powers.Shapeshifter.degrees["2"], nil, "non-true degree dropped")
		t.equal(profile.powers.Shapeshifter.degrees["3"], true, "true degree kept")
		local loadout = profile.loadouts.Ghost["1"]
		t.equal(#loadout, 2, "loadout drops numbers and duplicates")
		t.equal(loadout[1], "Phase", "loadout order kept")
		t.equal(loadout[2], "Haunt", "loadout second slot")
		t.equal(profile.loadouts.Bad, nil, "bad loadout dropped")
		t.equal(profile.selected.power, "StrongDude", "bad selected power replaced")
		t.equal(profile.selected.degree, Schema.Config.MaxDegree, "degree clamped")
		t.equal(profile.cosmetics.owned.Junk, nil, "non-true cosmetic dropped")
		t.equal(profile.cosmetics.owned.Halo, true, "cosmetic kept")
		t.equal(profile.cosmetics.equipped.trail, nil, "bad equip dropped")
		t.equal(profile.cosmetics.equipped.aura, "Halo", "equip kept")
		t.equal(profile.furniture.owned.Lamp, 3, "furniture count kept")
		t.equal(profile.furniture.owned.Ghost, nil, "negative count dropped")
		t.equal(profile.furniture.owned.Bed, nil, "string count dropped")
		t.equal(profile.base.access, "Everyone", "unknown access replaced")
		t.equal(profile.base.capacity, 1, "capacity clamped")
		t.equal(#profile.base.items, 1, "bad furniture placements dropped")
		t.equal(profile.base.items[1].r, 3, "rotation clamped")
		t.equal(profile.daily.day, 0, "bad day replaced")
		t.equal(profile.daily.progress.Win3, 2, "progress kept")
		t.equal(profile.daily.progress.Junk, nil, "bad progress dropped")
		t.equal(profile.tutorial.done.Move, true, "lesson kept")
		t.equal(profile.tutorial.welcomed, false, "bad welcomed replaced")
		t.equal(profile.settings.musicVolume, 1, "volume clamped")
		t.equal(profile.settings.uiScale, 1, "bad ui scale replaced")
		t.equal(profile.settings.cameraShake, true, "bad camera shake replaced")
		t.equal(profile.passes.CorruptionPower, true, "pass kept")
		t.equal(profile.passes.SyntaxPower, nil, "non-true pass dropped")
		t.equal(#profile.receipts, 2, "non-string receipt dropped")
		t.equal(#profile.rewardLog, 2, "non-number reward time dropped")
		t.equal(profile.meta.sessions, 0, "meta rebuilt")
		t.truthy(Schema.storable(profile), "storable")
	end)

	t.test("migrate keeps saveable unknown keys and drops unsaveable ones", function()
		local profile = Schema.migrate({
			version = 1,
			futureFeature = { level = 3 },
			stats = { perfectBlocks = 12 },
			broken = { [1] = 1, [3] = 3 },
			[7] = "number key",
		})
		t.equal(profile.futureFeature.level, 3, "unknown section kept")
		t.equal(profile.stats.perfectBlocks, 12, "unknown stat kept")
		t.equal(profile.broken, nil, "sparse array dropped")
		t.equal(profile[7], nil, "number key dropped")
		t.truthy(Schema.storable(profile), "storable")
	end)

	t.test("migrate trims receipts and the reward log to their newest entries", function()
		local receipts, log = {}, {}
		for index = 1, Schema.Config.MaxReceipts + 25 do
			table.insert(receipts, "r" .. index)
		end
		for index = 1, Schema.Config.MaxRewardLog + 10 do
			table.insert(log, index)
		end
		local profile = Schema.migrate({ version = 1, receipts = receipts, rewardLog = log })
		t.equal(#profile.receipts, Schema.Config.MaxReceipts, "receipts capped")
		t.equal(profile.receipts[1], "r26", "oldest receipts dropped")
		t.equal(profile.receipts[#profile.receipts], "r" .. (Schema.Config.MaxReceipts + 25), "newest receipt kept")
		t.equal(#profile.rewardLog, Schema.Config.MaxRewardLog, "reward log capped")
		t.equal(profile.rewardLog[1], 11, "oldest reward times dropped")
	end)

	t.test("migrate doesn't change the table it was given", function()
		local saved = { version = 1, currencies = { money = -5 }, stats = "junk" }
		Schema.migrate(saved)
		t.equal(saved.currencies.money, -5, "input money untouched")
		t.equal(saved.stats, "junk", "input stats untouched")
	end)

	t.test("data from a newer version is read-only and keeps its unknown keys", function()
		local profile, readOnly = Schema.migrate({
			version = Schema.VERSION + 1,
			currencies = { money = 900, gems = 4, crystals = 12 },
			newSection = { enabled = true },
		})
		t.equal(readOnly, true, "read-only")
		t.equal(profile.version, Schema.VERSION + 1, "version not downgraded")
		t.equal(profile.currencies.money, 900, "money kept")
		t.equal(profile.currencies.crystals, 12, "future currency kept")
		t.equal(profile.newSection.enabled, true, "future section kept")
		t.equal(profile.stats.wins, 0, "known keys still usable")
	end)

	t.test("view() is a deep copy without receipts, reward log or meta", function()
		local profile = Schema.default()
		table.insert(profile.receipts, "abc")
		table.insert(profile.rewardLog, 123)
		profile.meta.sessions = 4
		local view = Schema.view(profile)
		t.equal(view.receipts, nil, "no receipts")
		t.equal(view.rewardLog, nil, "no reward log")
		t.equal(view.meta, nil, "no meta")
		t.equal(view.currencies.money, profile.currencies.money, "money visible")
		t.equal(view.settings.uiScale, 1, "settings visible")
		view.currencies.money = 1
		view.settings.uiScale = 0.8
		t.equal(profile.currencies.money, Schema.Config.StartingMoney, "view is a copy (money)")
		t.equal(profile.settings.uiScale, 1, "view is a copy (settings)")
	end)

	t.test("sanitizeSettings keeps known keys, right types, clamped numbers", function()
		local current = Schema.default().settings
		local clean = Schema.sanitizeSettings({
			musicVolume = 4,
			sfxVolume = -1,
			uiScale = 0.1,
			cameraSensitivity = 9,
			cameraShake = false,
			reducedEffects = "yes",
			damageNumbers = 0,
			hacked = true,
		}, current)
		t.equal(clean.musicVolume, 1, "music clamped high")
		t.equal(clean.sfxVolume, 0, "sfx clamped low")
		t.equal(clean.uiScale, 0.75, "ui scale clamped")
		t.equal(clean.cameraSensitivity, 2, "sensitivity clamped")
		t.equal(clean.cameraShake, false, "boolean applied")
		t.equal(clean.reducedEffects, false, "wrong type keeps current")
		t.equal(clean.damageNumbers, true, "wrong type keeps current")
		t.equal(clean.hacked, nil, "unknown key dropped")
		t.equal(count(clean), count(Schema.Settings), "only known keys")
	end)

	t.test("sanitizeSettings rejects NaN and infinity and falls back to current", function()
		local current = Schema.default().settings
		current.uiScale = 1.1
		local clean = Schema.sanitizeSettings({ uiScale = 0 / 0, musicVolume = math.huge, sfxVolume = -math.huge }, current)
		t.equal(clean.uiScale, 1.1, "NaN keeps current")
		t.equal(clean.musicVolume, 0.5, "infinity keeps current")
		t.equal(clean.sfxVolume, 0.8, "negative infinity keeps current")
		local fromNothing = Schema.sanitizeSettings("junk", nil)
		t.equal(fromNothing.cameraSensitivity, 1, "defaults when there's nothing")
	end)

	t.test("storable() matches what a DataStore accepts", function()
		t.truthy(Schema.storable({ a = { "x", "y" }, b = { ["1"] = true } }), "string keys and arrays")
		t.equal(Schema.storable({ [1] = 1, [3] = 3 }), false, "sparse array")
		t.equal(Schema.storable({ [1] = 1, x = 2 }), false, "mixed keys")
		t.equal(Schema.storable({ x = 0 / 0 }), false, "NaN")
		t.equal(Schema.storable({ f = print }), false, "function")
	end)
end
