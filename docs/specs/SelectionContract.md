# Selection contract: lobby, training, match, prices

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
- **Match selection**: fighter, degree and loadout are picked when entering a match, in one confirm step.
  The saved selection **stays equipped until the player switches** (`stays = true`).
- **Price** (Money): charged once, on confirm, only when the power or degree differs from the saved
  selection and the target has a price. Re-confirming the same selection, a new loadout, browsing, `State`
  and `Quote` never charge. Not enough Money: refused, nothing taken, nothing changed. Degree 1 of a
  standard fighter is free; premium fighters have their own prices. A premium power the player does not own
  is a **trial only** (Practice and Training); Duel and Free-for-All refuse it (`NOT_OWNED`) and it costs nothing.
- **Owner**: every power, degree, ability and slot, price 0, no ownership records written.
- **Extra ability slot**: +1 loadout slot per power, earned at mastery level `Selection.ExtraSlot.MasteryLevel`
  or for every power by the game pass `Monetization.Passes.ExtraAbilitySlot` (may not exist yet; `pass` is
  nil then and nothing can be bought). Never more than `Selection.ExtraSlot.MaxTotal` slots (6: the ability bar's keys).

## Requests (client to server)

`Remotes.PowerRequest` (`Protocol.PowerAction`, 3 per second, burst 6). `loadout` is an array of ability ids.

| Action | Arguments | Does |
|---|---|---|
| `State` | none | Replies `DataEvent.Selection`. Ask when a screen opens. |
| `Quote` | powerId, degree, loadout? | Replies `DataEvent.SelectionQuote`. Read-only. |
| `Confirm` | powerId, degree, loadout? | The confirm step. Replies `SelectionResult` then `Selection`. |
| `Select` | powerId, degree | Old name for `Confirm` without a loadout. Same prices. |
| `SetLoadout` | powerId, degree, loadout | Saves a loadout (no price). Respects the slot count. Replies `SelectionResult`. |
| `Trial` | powerId, degree, loadout? | Training or showcase only. Free, not saved. |
| `EndTrial` | none | Back to the saved selection. |
| `SetShowcase` | on: boolean | Owner only. |
| `PromptPass` | powerId, `"ExtraSlot"` | Opens the extra-slot pass purchase (toast "not on sale yet" while its id is 0). |

Entering a match: `MatchRequest` `Queue(modeName, { arena?, cpuPower?, cpuDifficulty?, selection? })`
with `selection = { power, degree, loadout? }` is the same confirm step followed by the queue. Refused
selection: nothing charged, not queued, a `SelectionResult` (`action = "Queue"`) and a `MatchEvent.Notice`.
A failed solo start (all arenas busy) undoes the charge and the switch. No `selection`: the saved one is used.
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

`price` is the selection price; `charge` is what Confirm would take **now** (0 when equipped already,
free, owner or trial-only). Show `charge` before the confirm button and disable it when `canAfford` is false.
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

## Codes (`Protocol.SelectionCode`)

`OK` accepted. `BAD_REQUEST` junk or forged arguments. `LOADING` profile not ready. `DEGREE_LOCKED` reach the
mastery level or pay the unlock. `NOT_OWNED` Duel and Free-for-All need the premium power. `CANT_AFFORD` nothing
taken. `IN_MATCH` locked until it ends. `QUEUED` leave the queue first. `NOT_IN_TRAINING` Trial outside the hall.
`NOT_OWNER` showcase is owner only. `BAD_LOADOUT` invalid, duplicated, locked, or too many for the slots.

## Prices (Money, per switch)

Standard fighters: degree 1 free, 2: 100, 3: 250, 4 (Grandmaster): 500. Corruption 150 / 375 / 750,
Syntax 200 / 500 / 1,000, Admin 250 / 625 / 1,250 (plus their one-time Robux unlock). Reasoning is in the
comment above `Selection.Prices`.

## What the interface must still do

Draw the confirm screen from `Selection` (cost shown before confirming, affordability, "stays equipped until
you switch", trial-only note); send `Queue` with `selection`; use `Trial` inside the hall; read `SNCombatContext`;
show the extra slot and its pass; add a seventh ability key only if `ExtraSlot.MaxTotal` is raised.
