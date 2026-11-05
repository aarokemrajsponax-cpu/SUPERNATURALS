-- The Lounge refreshments counter (MASTER_REQUIREMENTS P.S. 13.0 section 3, DECISIONS 23).
-- Original drinks and snacks bought with earned Money only, never Robux and never Gems. Each gives
-- a harmless temporary look (a glow or a sparkle trail), a small emote line, and at most a
-- small boost to Money and experience from matches in casual modes (Free-for-All, CPU Practice).
-- It never works in Duel or ranked play, never touches damage, health, stamina or any combat
-- stat, and never lasts. A cooldown and a no-stacking rule stop it being farmed.

local Refreshments = {}

-- Modes where the experience boost may apply (names in Config/Match). Duel is competitive.
Refreshments.BoostModes = { FreeForAll = true, Practice = true }

-- Seconds before the same player may buy anything again, and the longest any effect lasts
Refreshments.Cooldown = 20
Refreshments.MaxSeconds = 600

-- Most the boost can add to a match's Money and experience, whatever is drunk
Refreshments.MaxBoost = 0.10

-- Menu order. glow: colour of the soft body glow, sparkle: trail colour (both cosmetic),
-- emote: the line shown over the head, boost: fraction added to casual match Money and experience.
Refreshments.Items = {
	{
		id = "pulse_drink", name = "Pulse Drink", kind = "Drink", price = 40, seconds = 180,
		glow = { 63, 214, 232 }, sparkle = { 150, 230, 245 }, emote = "Feeling the pulse",
		blurb = "A cold cyan fizz. Your outline glows cyan for 3 minutes.", boost = 0,
	},
	{
		id = "ember_tea", name = "Ember Tea", kind = "Drink", price = 40, seconds = 180,
		glow = { 232, 162, 74 }, sparkle = { 255, 214, 166 }, emote = "Warm and settled",
		blurb = "Smoky amber tea. A warm amber glow for 3 minutes.", boost = 0,
	},
	{
		id = "recharge_capsule", name = "Recharge Capsule", kind = "Snack", price = 90, seconds = 300,
		glow = { 130, 220, 150 }, sparkle = { 190, 255, 200 }, emote = "Recharged",
		blurb = "A green glow for 5 minutes, and 5% more Money and experience from Free-for-All and CPU Practice matches. Not in Duels.", boost = 0.05,
	},
	{
		id = "focus_bar", name = "Focus Bar", kind = "Snack", price = 120, seconds = 300,
		glow = { 150, 120, 220 }, sparkle = { 205, 185, 255 }, emote = "Locked in",
		blurb = "A violet glow for 5 minutes, and 5% more Money and experience from Free-for-All and CPU Practice matches. Not in Duels.", boost = 0.05,
	},
	{
		id = "power_smoothie", name = "Power Smoothie", kind = "Drink", price = 200, seconds = 420,
		glow = { 226, 124, 58 }, sparkle = { 255, 190, 120 }, emote = "Ready to go",
		blurb = "An orange glow and spark trail for 7 minutes, and 10% more Money and experience from Free-for-All and CPU Practice matches. Not in Duels.", boost = 0.10,
	},
	{
		id = "starlight_bites", name = "Starlight Bites", kind = "Snack", price = 60, seconds = 240,
		glow = { 226, 184, 84 }, sparkle = { 255, 240, 190 }, emote = "Sparkling",
		blurb = "Gold sparkles trail behind you for 4 minutes. Just for show.", boost = 0,
	},
}

Refreshments.Notes = "Bought with Money you earned. Effects are for show and fade on their own; the experience boost never applies in Duels and never changes fighting stats."

function Refreshments.byId(id: any): any
	if typeof(id) ~= "string" then
		return nil
	end
	for _, item in Refreshments.Items do
		if item.id == id then
			return item
		end
	end
	return nil
end

return Refreshments
