-- Fighter and degree selection: what picking a degree costs, the extra ability
-- slot, and where the lobby ends and training begins. The server charges these
-- numbers and the screens show them, so the price a player sees is the price
-- they pay. Rules in short (docs/specs/SelectionContract.md has the wire format):
--   * The lobby has no combat. Training and matches do; the owner's showcase mode too.
--   * Training is free: every power and degree is a trial that is never saved.
--   * A fighter, degree and loadout are chosen when entering a match, in one confirm step.
--     Confirming charges once, only when it switches to a different priced degree.
--     Re-confirming the same selection, browsing and previews never charge.
--   * The saved selection stays equipped until the player switches.

local Protocol = require(script.Parent.Parent.Protocol)
local Match = require(script.Parent.Match)

local Selection = {}

local Action = Protocol.CombatAction

-- Prices -------------------------------------------------------------------------------------

-- Selection prices are paid in Money, the currency matches pay out. Gems are never used
-- here, because Gems can be bought with Robux and a Robux-fed fee would make every
-- switch pay-to-play. This is separate from what it costs to *unlock* a degree
-- (mastery level or the Money price in each power's definition) and from the one-time
-- Robux unlock of a premium power.
Selection.Currency = "money"

-- Why these numbers (Config/Rewards): a Duel pays 30 for taking part and 10 per
-- knockout, plus 60 for a win. A loss with one knockout is about 40 Money, a win with
-- two knockouts about 110, so a typical match is worth about 75. Free-for-All pays
-- 1.15x and CPU Practice 0.5x. Add three daily challenges (about 375 Money) and the
-- login streak (50 to 200) and a regular player earns roughly 1,000 to 1,500 Money a day.
--
-- A selection is paid once when the player switches, not per match, so the price is
-- a commitment, not a toll. Each tier costs a few matches of income, rising by tier,
-- and stays far below the unlock price that owns the degree for good (1,500 and 6,000
-- Money, 15,000 for the Grandmaster's fourth degree):
--   tier 2   100 Money  about 1 typical match
--   tier 3   250 Money  about 3 matches
--   tier 4   500 Money  about 6 to 7 matches (only The Grandmaster has a fourth degree)
-- Degree 1 is free, so every player always has a fighter to play.
--
-- Premium fighters (Corruption, Syntax, Admin) also need their one-time Robux unlock;
-- the selection price is separate and is never a way to buy that unlock. They have no
-- free tier, and cost a multiple of the 100 / 250 / 500 scale that follows the order of
-- their Robux prices: Corruption 1.5x, Syntax 2x, Admin 2.5x. The most expensive pick
-- (Admin, degree 3: 1,250) is about a day of play and is paid once per switch.
Selection.Prices = {
	-- Standard fighters, by degree number
	Standard = { 0, 100, 250, 500 },
	-- Premium fighters, by power then degree number
	Premium = {
		Corruption = { 150, 375, 750 },
		Syntax = { 200, 500, 1000 },
		Admin = { 250, 625, 1250 },
	},
	-- A premium power with no table of its own (a future one) pays this until it gets one
	PremiumDefault = { 150, 375, 750 },
}

-- What it costs to select `degree` of `powerId`, in Money. `premium` is the power's
-- definition having a `premium` field (pass nil to go by the price tables alone).
-- Degrees past the end of a table pay its last price; junk pays nothing because the
-- caller has already refused it.
function Selection.priceFor(powerId: string, degree: number, premium: boolean?): number
	if typeof(degree) ~= "number" or degree ~= degree or degree < 1 then
		return 0
	end
	local own = Selection.Prices.Premium[powerId]
	local list = own
	if not list then
		list = if premium == true then Selection.Prices.PremiumDefault else Selection.Prices.Standard
	end
	local index = math.min(math.floor(degree), #list)
	return list[index] or 0
end

-- The extra ability slot ------------------------------------------------------------------------

-- One more loadout slot, optional and never needed to play a power well. A power gets it
-- for free at a mastery level, or every power gets it at once from a game pass. The
-- owner has it everywhere.
Selection.ExtraSlot = {
	Count = 1,
	-- Mastery level (Powers.Mastery) of that power. Level 10 needs 6,200 XP: about 60
	-- matches at the ~100 XP a match pays, and two levels past the third degree (level 8).
	MasteryLevel = 10,
	-- Key of the all-powers pass in Config/Monetization.Passes. That file may not have
	-- it yet and its id stays 0 until the owner makes the pass; everything here copes.
	PassKey = "ExtraAbilitySlot",
	-- No loadout holds more than this, because the ability bar has keys 1 to 6. A seventh
	-- slot needs a seventh key on the bar first (and then this number raised to 7).
	MaxTotal = 6,
}

-- The lobby, training and the owner's showcase -----------------------------------------------------

-- Training is the timber hall (ArenaService builds it round Config/Match TrainingGround.Center).
-- Its plinth is 34 x 44 studs (TrainingHall HALF_X 17, HALF_Z 22); the zone adds margin so a
-- dash or a knockback near the edge doesn't end a practice move. Whoever stands in this box
-- is in training, whichever way they got there. Heights are relative to the centre.
Selection.TrainingZone = {
	HalfX = 30,
	HalfZ = 30,
	Below = 20,
	Above = 60,
}

-- Is this world position inside the training zone?
function Selection.inTrainingZone(position: Vector3): boolean
	local zone = Selection.TrainingZone
	local offset = position - Match.TrainingGround.Center
	return math.abs(offset.X) <= zone.HalfX
		and math.abs(offset.Z) <= zone.HalfZ
		and offset.Y >= -zone.Below
		and offset.Y <= zone.Above
end

-- Combat actions that still work in the lobby: movement and emotes. Everything else the
-- combat remote carries (attacks, heavies, feints, grabs, sweeps, blocking) is off there,
-- and so is every ability and ultimate. Releasing a held button always works.
Selection.LobbyActions = {
	[Action.Dodge] = true,
	[Action.SprintStart] = true,
	[Action.SprintEnd] = true,
	[Action.Taunt] = true,
}

-- Refused actions that show the player a notice. Blocking is refused quietly: a held guard
-- button would otherwise repeat the notice.
Selection.QuietActions = {
	[Action.BlockStart] = true,
}

-- At most one lobby notice this often per player (seconds), so mashing an attack stays calm
Selection.NoticeCooldown = 5

-- Plain words the server sends and screens may reuse -------------------------------------------------

Selection.Text = {
	LobbyLocked = "Combat powers are off in the lobby. Join a match or visit Training to use them.",
	Stays = "Stays equipped until you switch.",
	TrialStays = "Training trial: free, and your saved selection is not changed.",
	TrialOnly = "Not owned yet: you can use it in Training and CPU Practice only.",
	ShowcaseOn = "Showcase mode is on. Your powers work in the lobby and hurt no one.",
	ShowcaseOff = "Showcase mode is off.",
}

return Selection
