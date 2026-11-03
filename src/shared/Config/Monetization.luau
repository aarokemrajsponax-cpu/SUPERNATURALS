-- Every Robux purchase in the game, in one place. Prices here are what the
-- shop shows; the amount Roblox actually charges is the price set on the
-- Creator Dashboard, so keep the two the same (the server warns at startup
-- when they differ).
--
-- To put an item on sale: create the game pass or developer product on the
-- Creator Dashboard (Monetization), set its price to the `robux` value below,
-- and paste its id over the 0. Items with id 0 show "not on sale yet" and
-- can't be bought.

local Monetization = {}

-- Game passes: bought once, owned forever
Monetization.Passes = {
	CorruptionPower = {
		id = 0,
		robux = 6666,
		power = "Corruption",
		name = "Corruption",
		benefit = "Unlocks the Corruption power: all three degrees, playable in every mode.",
	},
	SyntaxPower = {
		id = 0,
		robux = 9999,
		power = "Syntax",
		name = "Syntax",
		benefit = "Unlocks the Syntax power: all three degrees, playable in every mode.",
	},
	AdminPower = {
		id = 0,
		robux = 12000,
		power = "Admin",
		name = "Admin Powers",
		benefit = "Unlocks Admin Powers: all three degrees, playable in every mode.",
	},
	-- Cosmetic only (The Grandmaster's look). The owner sets the price on the
	-- Creator Dashboard; the client reads the live price from Roblox, so robux stays nil.
	CelestialDragonStyle = {
		id = 0,
		robux = nil,
		cosmeticFor = "Grandmaster",
		name = "Celestial Dragon Style",
		benefit = "Cosmetic only: a celestial stance and victory pose, star-silver impacts, extra aura colours and a dragon-themed ultimate for The Grandmaster. No gameplay changes.",
	},
	-- All-powers upgrade: one more ability slot in every loadout (read by PowerService through
	-- Config/Selection.ExtraSlot.PassKey). The owner creates the pass and pastes its id; until
	-- then it shows "Available soon". Roblox sets the price, the shop reads it live.
	ExtraAbilitySlot = {
		id = 0,
		robux = nil,
		name = "Extra Ability Slot",
		benefit = "One more ability slot in every power's loadout, up to the limit of six on the ability bar. No extra damage or stats.",
	},
	-- Cosmetic bundles. Each lists every item it gives (ids in Config/Cosmetics); none of it
	-- touches a stat, and nothing in a bundle is random. `recommended` is only the owner's
	-- suggested Robux price for the Creator Hub: the shop shows Roblox's live price, never this.
	VIP = {
		id = 0,
		robux = nil,
		recommended = 299,
		name = "VIP",
		cosmetics = { "vip_plate", "vip_title" },
		vipName = true,
		benefit = "Cosmetic only: the VIP Gold nameplate, the VIP title and a gold name in the Spectating Lounge. Nothing changes in combat.",
	},
	FoundersCollection = {
		id = 0,
		robux = nil,
		recommended = 799,
		name = "Founders Collection",
		cosmetics = { "founders_aura", "founders_ko", "founders_plate", "founders_title" },
		benefit = "Four exclusive cosmetics, all listed: the Founders' Ring aura, the Founders' Flare knockout effect, the Founders' Brass nameplate and the Charter Patron title. Looks only.",
	},
}

-- Order passes appear in the shop
Monetization.PassOrder = { "CorruptionPower", "SyntaxPower", "AdminPower" }

-- Developer products: can be bought again and again
Monetization.Products = {
	GemsSmall = {
		id = 0,
		robux = 49,
		gems = 100,
		name = "Pouch of Gems",
		benefit = "Adds 100 Gems to your balance.",
	},
	GemsMedium = {
		id = 0,
		robux = 199,
		gems = 450,
		name = "Chest of Gems",
		benefit = "Adds 450 Gems to your balance.",
	},
	GemsLarge = {
		id = 0,
		robux = 449,
		gems = 1100,
		name = "Vault of Gems",
		benefit = "Adds 1,100 Gems to your balance.",
	},
	GemsHuge = {
		id = 0,
		robux = 999,
		gems = 2600,
		name = "Hoard of Gems",
		benefit = "Adds 2,600 Gems to your balance.",
	},
	GemsMassive = {
		id = 0,
		robux = 2499,
		gems = 7000,
		name = "Treasury of Gems",
		benefit = "Adds 7,000 Gems to your balance.",
	},
	-- Season pass (SeasonPassService, Config/SeasonPass). `recommended` is for the owner's
	-- Creator Hub list only; the shop shows Roblox's live price.
	SeasonPremium = {
		id = 0,
		robux = nil,
		recommended = 499,
		seasonPass = "premium",
		name = "Season Premium",
		benefit = "Unlocks this season's premium track: one cosmetic at every tier, 30 in all. No Money, Gems or power. Next season has its own track.",
	},
	SeasonTierSkip = {
		id = 0,
		robux = nil,
		recommended = 49,
		seasonPass = "skip",
		name = "Season Tier Skip",
		benefit = "Adds one tier of points to this season's pass, never past the last tier. Every tier can also be earned free by playing.",
	},
}

-- Order products appear in the shop
Monetization.ProductOrder = { "GemsSmall", "GemsMedium", "GemsLarge", "GemsHuge", "GemsMassive" }

-- Shown when someone tries to buy an item whose id is still 0
Monetization.NotOnSaleText = "This item isn't on sale yet"

-- Seconds between purchase prompts for one player (stops prompt spam)
Monetization.PromptCooldown = 1

-- Tries to ask Roblox whether a player owns a pass, before falling back to the
-- ownership saved in their profile
Monetization.OwnershipCheckAttempts = 3

-- The pass key that unlocks a power, if that power is sold as a pass
function Monetization.passForPower(powerId: string): string?
	for key, pass in Monetization.Passes do
		if pass.power == powerId then
			return key
		end
	end
	return nil
end

return Monetization
