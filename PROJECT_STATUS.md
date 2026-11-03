# Project status (checkpoint)

**Updated:** 3 November 2026, 23:30 UTC. Branch `claude/friendly-turing-1hh9nu`.
Tests run in Lune on a stand-in engine; nothing has been verified in a live Roblox server.

## Batch 1 (release blockers): what landed today
| Item | State | Evidence |
|---|---|---|
| Statues on every plinth | Done | statues_test 10/10; renders checked (faceted, readable; sculpted meshes would be the next step up) |
| Enclosed futuristic hub, no grass, eight working doors, Thanksgiving from 1 Nov | Done (Thanksgiving restyle still old-style) | smoke 12/12, integration 12/12 |
| Archive's ten hidden files placed and picked up | Done (pickup never worked before) | lore_test 8/8, smoke lobby check |
| Lobby lock, free training trials, owner showcase | Done | phase_test, integration |
| Phases evolve during a match for a Money fee | Done | phase_test 15/15 |
| Combat HUD, owner nameplate, custom prompts (interface v3) | Done | smoke_combat 11/11, renders |
| Fighter Showcase, pre-match flow, Settings, permanent unlock actions | Done; 667x375 containment not re-rendered | smoke_ui |
| Master Shop, hardened receipts, regional price levels, live prices | Done | shop_test 9/9, pricing_test 9/9, smoke_shop 8/8 |
| FINAL_OWNER_HANDOFF.md | Done | file at repo root |
| Spectator predictions pay nothing | Done | |
| Jeffery, first-time tutorial, hints, How to Play | In progress | |
| Corruption, Shapeshifter, Syntax, Admin power tests | In progress | |

## Afternoon, 3 November: owner feedback "looks too AI generated"
| Item | State | Evidence |
|---|---|---|
| Faithful preview renders (real fonts, sign text laid out on its face, rotated icons, 3D views in the interface) | Done | tools/uipreview, tools/preview, tools/fonts |
| Craft pass rules (`docs/specs/UI_Craft_Pass.md`): solid windows, one edge with a lip, 4 px corners, sentence case | Done | Theme, Components |
| Jeffery's dialogue: opaque card, HUD fades while he talks, portrait setting, name tab, sentence case | Done | smoke_learn 9/9, smoke_ui, tutorial_test 10/10, renders |
| Play window: no truncated text, cards without boxes, one Cancel | Done | smoke_ui, smoke, renders |
| Match HUD: fighting-game top bar, outlined announcements, key caps under slots, quiet key hints, toasts that never cover windows | Done | smoke_combat 11/11, renders |
| Statue plaques (codename between rules, engraved name, rivets) and numbered door signs 01 to 08 | Done | statues_test 10/10, renders |
| Season welcome card restyled; emoji sprites retired; Thanksgiving lighting warmed | Done | |
| Thanksgiving "Harvest Week": facility vitrines, banners, sign, warm drift (no farm props) | Done | smoke 12/12, renders |
| Owner Control Center server: cross-server announcements (text filtered), scheduler, custom event creator | Done on fakes | overlord_ext_test 10/10 |
| Owner Control Center screens (17 sections, P key or the vault console) | Done | smoke_owner_center 24/24 |
| Achievements (36), titles, nameplates, server-wide moments, Wins and Best streak boards, Locker | Done | status_test 18/18, smoke_status 7/7 |
| Referral rewards, invites, friends bonus, group title, analytics | Done (offline) | community_test 13/13 |
| Season pass, VIP, Founders Collection, auras, knockout effects | Done (offline) | seasonpass_test 19/19 |
| Holiday gift calendars (Thanksgiving, Christmas), fighter trials, trial products | Done (offline) | calendar_test 20/20, smoke_calendar 10/10 |
| Licensed music by area (52 verified tracks) | Done; playback to hear in Studio | |
| Settings: Quick cast toggle; lock-on and quick cast now actually save | Done | unit 117/117 |
| No Robux amount in player text outside live regional prices | Done | phase, data, shop tests |

## Known defects
- Grandmaster power test fails a different timing check each run under heavy machine load;
  to re-check on a quiet machine.
- Every product and pass id is 0 until the owner creates them (see FINAL_OWNER_HANDOFF.md).

## Next, in order
1. Live checks by the owner: purchases, saves on rejoin, owner events across two servers.
2. Premium fighter overhaul (P.S. 3.0): phase identities, transformation sequences, ultimates,
   effects and sound for Corruption, Syntax and Admin; flight for the three; the Admin
   fighter's small set of in-match commands (never real admin rights).
3. Spectating Lounge refreshments counter (P.S. 13.0), Master Shop room, Jeffery in the lounge.
4. Live meme calendar, brainrot content and the Meme Vault (section 25).
5. Sound manager and manifest (P.S. 7.0; audio ids need the owner's verification).
6. Mastery, achievements, rivals and leaderboards (P.S. 15, 19); cinematic camera (P.S. 9.0).
7. Polish: base sofa and rug colours, lounge floor, Founders' Archive illustrations (owner art).

Done since the last checkpoint: click-to-target and aimed abilities with lower costs and faster
regeneration (targeting_test 10/10), battleground concourse with 20 themed chambers, Training
Studio with practice fights against Jeffery (practice_test 14/14), Spectating Lounge with the free
prediction board, Player Base Street with homes and basement vaults.

## Usage notes
A 5-hour window has supported roughly 30 to 90 minutes of three or four Sonnet agents. Narrow
agents finish; wide ones stall. The lead session reviews renders and runs the full suite.
