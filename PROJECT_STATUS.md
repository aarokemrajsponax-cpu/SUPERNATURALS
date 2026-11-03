# Project status (checkpoint)

**Updated:** 3 November 2026, 12:00 UTC. Branch `claude/friendly-turing-1hh9nu`.
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

## Known defects
- Grandmaster power test fails a different timing check each run under heavy machine load;
  to re-check on a quiet machine.
- Hard-coded Robux numbers remain in PowerService messages and power definitions (not in the
  shop or showcase).
- Thanksgiving dressing builds but still uses the old styling.
- Every product and pass id is 0 until the owner creates them (see FINAL_OWNER_HANDOFF.md).

## Next (batch 2, in order)
1. Combat: click-to-target for Corruption, Syntax and Admin; aimed shots for Machine Master;
   teleport targeting and directional slashes for the Ghost; much lower energy costs and
   faster regeneration, all in config.
2. Flight for the three premium fighters; the Admin fighter's small chat-command set.
3. Facility wings: battleground concourse (about 20 themed chambers with spectator rooms),
   Training Studio, Jeffery's Base room, Spectating Lounge (screens, refreshments, free
   prediction board, Founders' Archive), Master Shop room, Player Base Street with bases and
   basement vaults.
4. Premium fighter overhaul (Corruption, Syntax, Admin phases, effects, ultimates).
Then batch 3 (Owner Control Center v2 across servers, live meme calendar and content, sound
manager, Jeffery's knowledge base) and batch 4 (polish, mastery and achievements, QA).

## Usage notes
A 5-hour window has supported roughly 30 to 90 minutes of three or four Sonnet agents. Narrow
agents finish; wide ones stall. The lead session reviews renders and runs the full suite.
