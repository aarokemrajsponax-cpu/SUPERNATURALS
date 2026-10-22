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
}

-- Order products appear in the shop
Monetization.ProductOrder = { "GemsSmall", "GemsMedium", "GemsLarge" }

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
