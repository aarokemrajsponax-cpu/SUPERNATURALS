# SUPERNATURALS: Halloween release plan

Target: publish on **31 October 2026**. Written 27 October 2026, 15:40 UTC, and kept up to date
as work lands. The rule for the deadline: a smaller, complete, polished release beats a huge,
broken one. Anything not finished and verified by 30 October moves to a post-launch update.

Important limits, stated plainly:
- Everything is built and tested outside Roblox Studio, using Rojo builds, a stand-in engine
  (Lune) and automated tests. Real physics, animation playback, networking, rendering,
  DataStores and Robux purchases can only be checked in Studio or a live server. A Studio
  playtest by the owner on 30 October is part of this plan (see the launch checklist).
- Development has been stopped several times by plan usage limits. The waves below are ordered
  so the most important things land first.

## Where the game stands (27 Oct)

| Area | State |
|---|---|
| Combat core and Fighting System v2 rules (grabs, throws, sweeps, aerials, stamina, counters, clashes) | Done on the server, 40-check test passing |
| Combat feel on the client (animations, lock-on, hitstop, stamina HUD, touch controls) | In progress |
| Matches: Duel, Free-for-All, CPU Practice, Training; scoring, sudden death, respawns, forfeits | Done, tested |
| Interactive defense (prompts, timing bars, grab escapes, redirects, counters) | Done, tested |
| Saving (session locks, retries, autosave, safe fallback), currencies, purchase receipts | Done, tested with fakes |
| Rewards, mastery, daily challenges, login streak, anti-farming, spectating, predictions, rematch (server) | Done, tested |
| Powers: Strong Dude, The Ghost, Machine Master, The Grandmaster | Done, tested |
| Powers: Animal Shapeshifter, Corruption, Syntax, Admin Powers | In progress |
| Five arenas + training hall + arena picker | Done; being enclosed as indoor test chambers next |
| Lobby | Being rebuilt as the indoor Meridian Station: the Garden, the Lounge, the Calibration Chamber, the Enhancement Bay, secret rooms |
| Story: the Meridian Archive text (12 documents + 10 hidden files) | Written; the book window is in progress |
| Interface system, Play, Powers, Settings, HUD, match HUD, owner panel v1 | Done; full visual overhaul planned |
| Shop (Commissary) and the Robux catalogue in the interface | Not started; launch-critical |
| Onboarding, lessons, first-steps guidance | Not started; launch-critical |
| Owner control center v2 and Admin Abuse v2 | Not started (v1 works) |
| Anomalies (brainrot) system and a Halloween event | Not started |
| Personal bases | Not started |
| Victory scene, results presentation, replay | Server side done; presentation not started |

## Waves (working back from 31 Oct)

### Wave 1: core foundations (27 Oct evening to 28 Oct morning)
Finish the seven builds in progress (combat client feel, Shapeshifter, Corruption, Syntax, Admin
Powers, Archive book, indoor station), merge them and get every test green.
Done when every power passes its own test, all 8 power definitions validate, and smoke,
integration, combat, data and powers tests pass on the merged build.

### Wave 2: visual transformation (28 Oct)
- The interface overhaul in one design language, the Meridian Institute: power selection with
  a live 3D preview, compare mode and ability previews, drawn icons instead of emoji, a loading
  screen, transitions, and a sound layer.
- Arenas enclosed as indoor test chambers.

Done when every window passes the layout audit at phone, tablet and desktop sizes; no emoji or
em dashes appear in player-facing text; and renders pass review.

### Wave 3: gameplay depth (28 to 29 Oct)
- Onboarding: first-steps guide trails, a lesson for every power and degree, one-time tips, the
  welcome card, and training readouts.
- The Lounge as a social second home: leaderboard screens, a jukebox spot, emote spots.
- The Archive book and secret rooms.

Done when a new player can go from joining to a first win guided only by the game.

### Wave 4: monetization and live operations (28 to 29 Oct)
- The Commissary shop with the full Robux catalogue: passes, gem packs, Starter Pack, boosts,
  Power Day Pass, purchasable lobby events, VIP, and a season pass.
- The owner control center v2 and Admin Abuse v2 (event framework, new events, server boss,
  scheduler, safe cleanup).
- Anomalies, the brainrot system, with a Halloween event for launch day.

Done when every product is fulfilled exactly once per receipt, every event cleans up, every
owner action is refused for non-owners, and all of it is tested.

### Wave 5: optimization and QA (29 to 30 Oct)
Cross-system review with fresh eyes: security of every remote, purchases (success, cancel,
repeated receipts, leaving mid-purchase), saving, cleanup, performance (part and particle
budgets, per-frame work), layout on every screen size, and copy. Fix launch-critical defects
first.

### Wave 6: release preparation (30 to 31 Oct)
- Owner Studio playtest with real DataStores and test purchases.
- Fix what it finds.
- Icons and thumbnails captured in Studio (the owner panel's photo mode).
- Description and tags.
- Creator Dashboard products created and ids pasted in.
- Publish.

## Deferred unless time allows (post-launch candidates)
In order of value:
1. Replay viewer.
2. Personal-base furniture editor (a simpler apartment may ship first).
3. Prestige and weekly missions.
4. Global leaderboards beyond the Lounge screen.
5. Extra Admin Abuse events.

## Launch-critical defect list
Kept current as issues are found:
- [ ] Shop not built: players can't buy Gems or see the catalogue (Wave 4).
- [ ] Onboarding not built (Wave 3).
- [ ] Arenas still open-air; the owner requires everything indoors (Wave 2).
- [ ] combat_test "a Hard CPU uses the new moves" failed once (randomness suspected; verify).
- [ ] Not yet run in Studio: physics, animation, network replication, real purchases, DataStores.
