# Milestone 1 — the first playable fight

## What's in it

- **Combat (server-decided):** light attack chain (4 hits, the last one launches),
  heavy attack (big wind-up with a red warning ring, big hit, long recovery if it
  misses), block (cuts damage, drains guard), parry (block right before a hit to
  stun the attacker), guard break (enough damage breaks a block), dodge (quick
  dash with a moment of invulnerability), knockback, hitstun and a combo limit.
- **Matches:** Duel (1v1), Free-for-All (3–4 players) and Practice (vs a sparring
  dummy). Each has a 10-second countdown, a timer, +1/−1 knockout scoring, sudden
  death on a tie, forfeit if a player leaves, a results screen, and a return to the lobby.
- **Arenas:** built in code ("Proving Grounds"), one per running match, up to 6 at once.
- **Training Ground:** three dummies near spawn: Punching Bag (stands still),
  Guard Dummy (always blocks: practise heavies and guard breaks), Sparring Dummy
  (blocks sometimes). Dummies knocked away walk back to their spot.
- **UI:** health and guard bars, action buttons with cooldowns, fight menu, queue
  status, match timer and scores, knockout feed, countdown, results, settings
  (screen shake, reduced effects), name and health bars over other fighters.
- **Owner panel:** see below.

## Controls

| Action | Keyboard & mouse | Gamepad | Phone / tablet |
|---|---|---|---|
| Light attack | Left click | X | On-screen button |
| Heavy attack | E | Y | On-screen button |
| Block (hold) | F | L1 | On-screen button |
| Dodge | Q | B | On-screen button |
| Owner panel | P | — | 👑 button |
| Owner flight (when enabled) | G | — | Panel button |

Attacks go where the camera is looking.

## Testing in Roblox Studio

1. In VS Code: `Ctrl+Shift+P` → **Git: Pull**, then start Rojo (`.\rojo.exe serve`).
2. In Studio: **Plugins → Rojo → Connect** (with the game stopped).
3. **Solo test (Play):**
   - Click **🎯 TRAINING GROUND** and hit the dummies. Try heavies on the Guard Dummy until its guard breaks.
   - Click **🤖 PRACTICE**: countdown, fight the Sparring Dummy, knock it out (+1), wait for the results.
   - Press **P** to open the owner panel and try each event.
4. **Two-player test (the milestone's acceptance test):** Studio's **Test** tab →
   set **Clients and Servers** to *Local Server* with **2 players** → **Start**.
   In both player windows click **⚔ DUEL**. Fight until someone is knocked out,
   check the scores (+1 / −1), let the timer run out, and check the results.
   Then try having one player block, parry (press F just before a hit lands),
   dodge (Q), and close one window mid-match (the other should win by forfeit).

## Owner panel (only for XxxXxxX_77797)

Open it with **P** or the gold 👑 button on the right edge of the screen. The
server checks every request, so nobody else can use it.

- **EVENTS:** Meteor Shower, Black Hole, Thunderstorm, Ice Age, Galaxy Sky,
  Disco Inferno, Low Gravity, Giant Party, Party Time. Events push around, freeze
  or grow players in the lobby only. Players in a running match are left alone,
  but they still see the show.
- **PLAYERS:** pick a player, "Everyone" or "Everyone but me", then Heal, Knock
  Out, Fling, Freeze, Bring, Go To, Giant, Tiny, Normal Size, Speed Boost, auras
  (Gold, Rainbow, Void, Frost, Remove), Kick, or Ban from this server. Kick and
  ban need two clicks. "Everyone" actions skip players in a running match (auras,
  kick and ban still reach them); pick a player by name to target them anyway.
- **ME:** Fly (G toggles; Space up, Ctrl down, Shift for speed), Immune to events,
  Invisible, Crown & owner title, your own aura and speed boost.
- **SERVER:** announcements (they go through Roblox's text filter), time of day
  (or back to the season's default), force a holiday season (or Auto), end all
  matches, stop the current event.

Only XxxXxxX_77797 (user id 8722595934) gets it. To give it to more accounts,
add user ids (best, they never change) or usernames in
`src/server/OwnerConfig.luau`. Set `IncludeGameCreator = true` there if the
account or group that publishes the game should get it too.

## Where to tune things

All balance numbers are in config files, not spread across scripts:

- `src/shared/Config/Combat.luau`: damage, timings, ranges, knockback, block, parry, dodge.
- `src/shared/Config/Match.luau`: modes, countdown, match length, tie rules, arenas.
- `src/shared/Config/AdminEvents.luau`: admin event lengths and strengths, owner actions.
- `src/shared/Config/Audio.luau`: sound ids.

## Placeholders (need real assets later)

- **Animations:** poses are made by rotating joints in code
  (`src/client/Effects/Poser.luau`). Real animations made in Studio's Animation
  Editor can replace them without changing the combat system.
- **Sounds:** built-in Roblox sounds as stand-ins (`Config/Audio.luau`). Replace
  them with Creator Store sound ids.
- **Arena and lobby art:** built from parts in code. Detailed models can replace them later.

## Known limitations

- Nothing here has been run inside Roblox Studio yet. The automated tests in
  `tests/` run the real code against a stand-in engine, which covers logic,
  property names and scoring, but not physics, animation, rendering or networking.
- There are no powers or degrees yet (Milestone 2). Everyone fights with the same base moves.
- There's no data saving yet, so settings and anything else reset when you leave.
- There are no CPU opponents that fight back yet (Milestone 6). Dummies only block.
