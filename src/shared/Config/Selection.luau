-- Phases: a power's degrees are its phases. Every match starts in Phase 1; a player who
-- has unlocked a higher degree evolves mid-fight once the Phase meter is full, paying that
-- phase's fee in Money. The server charges these numbers and the screens show them, so the
-- price a player sees is the price they pay. Rules in short (docs/specs/SelectionContract.md
-- has the wire format):
--   * The lobby has no combat. Training and matches do; the owner's showcase mode too.
--   * Training is free: every power and degree is a trial that is never saved, and
--     evolving there is free and instant (no meter).
--   * Before a match the player chooses fighter and loadout in one confirm step. That step
--     never charges. Browsing, quotes and previews never charge either.
--   * Evolving charges the phase fee once, only when the transformation happens.

local Protocol = require(script.Parent.Parent.Protocol)
local Match = require(script.Parent.Match)

local Selection = {}

local Action = Protocol.CombatAction

-- Prices -------------------------------------------------------------------------------------

-- Phase fees are paid in Money, the currency matches pay out. Gems are never used here,
-- because Gems can be bought with Robux and a Robux-fed fee would make every evolution
-- pay-to-play (no Robux product grants Money: Config/Monetization products grant Gems only).
-- This is separate from what it costs to *unlock* a degree (mastery level or the Money price
-- in each power's definition) and from the one-time Robux unlock of a premium power.
Selection.Currency = "money"

-- Why these numbers (Config/Rewards): a Duel pays 30 for taking part and 10 per knockout,
-- plus 60 for a win. A loss with one knockout is about 40 Money, a win with two knockouts
-- about 110, so a typical match is worth about 75 (CPU Practice pays half). A fee is a
-- decision made mid-fight, so it should sting a little and never be out of reach:
-- roughly a quarter to a half of one match's income, rising with the phase.
--   phase 2   20 Money  about 27% of a match
--   phase 3   30 Money  about 40%
--   phase 4   38 Money  about 50% (only The Grandmaster has a fourth phase)
-- Phase 1 is free, so every player always has a fighter to play. Premium fighters
-- (Corruption, Syntax, Admin) pay somewhat more, 1.25x, 1.5x and 1.75x the standard fee,
-- rounded; they also need their one-time Robux unlock, and a fee is never a way to buy
-- that. The dearest evolution (Admin, phase 3: 50) is still two thirds of one match.
Selection.Prices = {
	-- Standard fighters: the fee to reach each phase, by phase number
	Standard = { 0, 20, 30, 38 },
	-- Premium fighters, by power then phase number
	Premium = {
		Corruption = { 0, 25, 38 },
		Syntax = { 0, 30, 45 },
		Admin = { 0, 35, 50 },
	},
	-- A premium power with no table of its own (a future one) pays this until it gets one
	PremiumDefault = { 0, 25, 38 },
}

-- The Phase meter: fills from combat, resets when the fighter evolves (and each life).
-- 100 is full: about 15 landed hits, or a mix of dealt and taken, so a half-minute of
-- real fighting. Evolving is a mid-fight event and not an opener.
Selection.Phase = {
	MeterMax = 100,
	HitDealt = 6, -- a hit that landed and hurt
	HitTaken = 8, -- being hurt fills it faster, so the fighter behind can turn it around
	BlockedDealt = 2, -- a blocked hit still counts a little
	-- The transformation window: the server marks the fighter, grants this many hits of
	-- hyper-armour for this many seconds, and tells every client (CombatEvent.Transform)
	TransformTime = 0.8,
	ArmorHits = 3,
	-- CPUs evolve when their meter fills, for free, up to this phase (Hard CPUs go further)
	CpuMaxPhase = { Default = 2, Hard = 3 },
}

-- The Money fee to evolve into phase (degree) `degree` of `powerId`. `premium` is the power's
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
