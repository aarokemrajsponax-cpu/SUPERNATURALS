# Selection contract: lobby, training, match, phases (evolving)

For the interface agent. Server code: `PowerService` (rules, prices, snapshot), guards in
`CombatService:canAct` and `AbilityService`, queue hook in `MatchService`. Numbers live in
`src/shared/Config/Selection.luau`; names in `src/shared/Protocol.luau`. The server decides
everything; a screen only asks and shows. Screens may `require` Selection for prices and wording.

## Rules

- **Lobby**: no attacks, heavies, feints, grabs, sweeps, blocking, abilities or ultimates. Dodge, sprint
  and taunt still work. **Training** (the hall) and **matches** (while the fight is on) allow combat.
  The **owner** can turn on showcase mode: powers work anywhere and hurt no one. One server check
  (`PowerService:combatContext`) answers for every entry point.
- **Training is free.** `Trial` equips any power and degree (all abilities unlocked, no ownership,
  nothing charged). It never touches the saved selection. It ends on leaving the hall, queueing or a match.
- **Match selection**: fighter and loadout are picked when entering a match, in one confirm step, and it
  **never charges**. The saved selection stays equipped until the player switches (`stays = true`).
  A premium power the player does not own is a **trial only** (Practice and Training); Duel and
  Free-for-All refuse it (`NOT_OWNED`).
- **Phases** (DECISIONS 14): a power's degrees are its phases. **Every match starts in Phase 1**, whatever degree
  was saved. A player who has unlocked a higher degree (existing mastery or `UnlockDegree` rules) can evolve
  mid-fight once the Phase meter is full, paying that phase's fee in Money. The fee is charged once, only when the
  transformation happens; a refused request takes nothing. The phase lasts for the match (a new life keeps it, with an
  empty meter). At match end the fighter returns to the saved selection, not evolved. The meter fills from combat (hits
  dealt and taken; numbers in `Selection.Phase`) and empties on evolving and on a new life.
- **Training**: Evolve is free, instant (no meter), and resets when the hall is left. **Owner**: free, no unlock needed.
  **CPUs** evolve for free when their meter fills, up to `Selection.Phase.CpuMaxPhase` (2, Hard 3).
- **Transformation window**: `Selection.Phase.TransformTime` (0.8 s) of hyper-armour (3 hits) and no meter gain; one
  transformation at a time.
- **Owner**: every power, degree, ability and slot, fee 0, no ownership records written.
- **Extra ability slot**: +1 loadout slot per power, earned at mastery level `Selection.ExtraSlot.MasteryLevel`
  or for every power by the game pass `Monetization.Passes.ExtraAbilitySlot` (may not exist yet; `pass` is
  nil then and nothing can be bought). Never more than `Selection.ExtraSlot.MaxTotal` slots (6: the ability bar's keys).

## Requests (client to server)

`Remotes.PowerRequest` (`Protocol.PowerAction`, 3 per second, burst 6). `loadout` is an array of ability ids.

| Action | Arguments | Does |
|---|---|---|
| `State` | none | Replies `DataEvent.Selection`. Ask when a screen opens. |
| `Quote` | powerId, degree, loadout? | Replies `DataEvent.SelectionQuote`. Read-only. |
| `Confirm` | powerId, degree, loadout? | The confirm step (fighter and loadout; never charges). Replies `SelectionResult` then `Selection`. |
| `Evolve` | none (any argument is `BAD_REQUEST`) | Next phase, mid-fight. Replies `SelectionResult` with `action = "Evolve"`, `degree` (new), `from`, `charged`. |
| `Select` | powerId, degree | Old name for `Confirm` without a loadout. Same prices. |
| `SetLoadout` | powerId, degree, loadout | Saves a loadout (no price). Respects the slot count. Replies `SelectionResult`. |
| `Trial` | powerId, degree, loadout? | Training or showcase only. Free, not saved. |
| `EndTrial` | none | Back to the saved selection. |
| `SetShowcase` | on: boolean | Owner only. |
| `PromptPass` | powerId, `"ExtraSlot"` | Opens the extra-slot pass purchase (toast "not on sale yet" while its id is 0). |

Entering a match: `MatchRequest` `Queue(modeName, { arena?, cpuPower?, cpuDifficulty?, selection? })`
with `selection = { power, degree, loadout? }` is the same confirm step followed by the queue. Refused
selection: not queued, a `SelectionResult` (`action = "Queue"`) and a `MatchEvent.Notice`.
A failed solo start (all arenas busy) undoes the switch. The match itself still starts in Phase 1. No `selection`: the saved one is used.
Changes are refused while queued (`QUEUED`) or in a match (`IN_MATCH`); leave the queue first.

## Events (server to client), `Remotes.DataEvent`

**`Selection`** (snapshot):

```
context  "Lobby" | "Training" | "Match" | "Showcase"      combat  boolean (powers work right now)
canTrial boolean   locked boolean (in a match)   queued boolean   owner boolean   showcase boolean
money, gems   currency = "money"   stays = true
equipped = { power, degree, loadout, trialOnly }          the saved selection
trial    = { power, degree, loadout }?                    the Training trial in use
extraSlot = { masteryLevel, max, hasPass, pass = { key, name, benefit, robux?, onSale }? }
powers[powerId] = { id, name, premium, owned, level, extraSlot,
    unlock = { passKey, robux, gems, onSale }?,           premium only
    degrees = { { degree, name, price, charge, unlocked, unlockLevel?, unlockMoney?, equipped,
                  trialOnly, canAfford, baseSlots, slots, code } } }
```

`price` is the phase fee (Money to evolve into that degree); `fee` is the same for this player (0 for the owner);
`feeAffordable` is whether their Money covers it. `charge` is what Confirm would take: always 0 now, and
`canAfford` is always true. Show the fee next to each phase on the loadout screen.
`code` is what Confirm would answer now. `unlocked` is the degree itself (mastery level or the existing
`UnlockDegree` Money price), separate from the selection price. Re-ask `State` after any profile change.

**`SelectionQuote`**: one degree entry (fields as above) plus `power`, `message`, `money`, and when a
loadout was sent `loadoutOk`, `loadoutMessage`.

**`SelectionResult`**: `{ action, ok, code, message, power?, degree?, loadout?, charged, price?, switched?,
persists?, trialOnly?, mode?, showcase?, slots?, money }`. `charged` is the Money this request took.
`persists` is false for a Training trial. `message` is plain text, safe to show.

Also: the combat remotes send `Rejected` with `reason = "lobby"`, plus a calm `MatchEvent.Notice` at most every
5 seconds. Fighter models carry attribute `SNCombatContext` (`Protocol.CombatContext`); skip predicted
attack animations unless it is `Match`, `Training` or `Showcase`. Players carry `SNShowcase` while it is on.

## Phase attributes and events

Character attributes (`Protocol.Attribute`): `SNPhaseMeter` (0 to 100), `SNPhaseNo` (current phase = degree, 1 to 4),
`SNPhaseFee` and `SNPhaseNext` (Money fee and name of the next phase this player has unlocked; absent when
there is none, 0 when free), `SNTransformUntil` (server time the transformation window ends, absent otherwise).
`SNPhase` is unchanged: it is a power's own visual stage (0 to 1), not this.
`CombatEvent.Transform` to everyone: `{ fighter: Model, power, from, to, duration }`. The client plays a burst in the
power's colour (`EffectsController:_onTransform`); per-fighter cinematics come later.
Client input: key T, gamepad Start, touch button, all sending `PowerRequest "Evolve"`.

## Codes (`Protocol.SelectionCode`)

`OK` accepted. `BAD_REQUEST` junk or forged arguments. `LOADING` profile not ready. `DEGREE_LOCKED` reach the
mastery level or pay the unlock. `NOT_OWNED` Duel and Free-for-All need the premium power. `CANT_AFFORD` nothing
taken. `IN_MATCH` locked until it ends. `QUEUED` leave the queue first. `NOT_IN_TRAINING` Trial outside the hall.
`NOT_OWNER` showcase is owner only. Evolve adds `NOT_FIGHTING` (not in a running match or Training),
`METER_NOT_FULL`, `MAX_PHASE`, `TRANSFORMING`; it also answers `DEGREE_LOCKED`, `NOT_OWNED`, `CANT_AFFORD`, `BAD_REQUEST`, `LOADING`. `BAD_LOADOUT` invalid, duplicated, locked, or too many for the slots.

## Phase fees (Money, per evolution)

Standard fighters: phase 2: 20, phase 3: 30, phase 4 (Grandmaster): 38. Corruption 25 / 38, Syntax 30 / 45,
Admin 35 / 50 (plus their one-time Robux unlock). A typical match pays about 75 Money, so a fee is a quarter to a half of
one. Reasoning is in the comment above `Selection.Prices`. No Robux product grants Money (all are Gems).

## What the interface must still do

Loadout screen: choose fighter and loadout, show each phase's fee, unlock state and affordability (`fee`, `feeAffordable`),
say that matches start in Phase 1; send `Queue` with `selection`; use `Trial` inside the hall; read `SNCombatContext`;
show the extra slot and its pass. In the fight: style `UI/PhaseMeter` (functional placeholder), a "meter full" cue,
the per-fighter transformation cinematic, and `SelectionResult` with `action = "Evolve"` (the server already toasts refusals).
