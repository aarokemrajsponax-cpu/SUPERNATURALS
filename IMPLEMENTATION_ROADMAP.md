# Implementation roadmap and traceability

Status labels (from P.S. 11.0): COMPLETE AND TESTED · IMPLEMENTED BUT NOT FULLY TESTED ·
PARTIALLY IMPLEMENTED · OWNER ACTION REQUIRED · NOT IMPLEMENTED · BLOCKED. "Batch n" says when
it is scheduled. Updated 3 November 2026. Tests run in Lune with the stand-in engine; nothing
here has been verified in a live Roblox server yet (see `PROJECT_STATUS.md`).

## Batches (directive priority order)
1. **Release blockers (P0):** statues; enclosed hub with no grass and working doors; lobby,
   training and phase rules; interface and selection screens; shop, receipt audit, dynamic
   prices, regional-pricing gate, `FINAL_OWNER_HANDOFF.md`; Thanksgiving switch-over.
2. **Core experience (P1):** combat targeting, lower energy costs and configurable balance,
   flight for the three premium fighters, Admin chat commands; Jeffery (character, dialogue,
   first-time tutorial, hints, practice fights, How to Play); the facility wings (battleground
   concourse with about 20 chambers and spectator galleries, Training Studio, Jeffery's Base,
   Spectating Lounge with refreshments, prediction board and Founders' Archive, Master Shop,
   Player Base Street with bases and basement vaults); the premium fighter overhaul.
3. **Live systems:** Owner Control Center v2 (cross-server events, 200+ preset library,
   custom event creator, scheduler, broadcasts, summoning, emergency restore, audit log);
   live meme calendar, brainrot content in batches, Meme Vault; sound manager and manifest;
   Jeffery's knowledge base and optional AI provider.
4. **Polish and proof:** visual audits, performance, accessibility, mastery, achievements,
   rivalries, leaderboards, analytics, final QA and the handoff.

## Traceability
| ID | Requirement (where) | Feature | Main files | Status | Test | Open issue |
|---|---|---|---|---|---|---|
| R1 | Statues on pedestals (§2, §4) | Eight carved statues and plinths | World/Statues.luau | PARTIALLY IMPLEMENTED (batch 1 running) | statues_test | Niches were empty in Studio |
| R2 | Selection and display buttons (§4) | Interface system, HUD buttons | UI/Theme, Components, Shell, Hud, AbilityBar | PARTIALLY IMPLEMENTED | smoke, smoke_ui | Rewrite stopped half-way by the usage limit |
| R3 | Futuristic facility, no grass (§5, P.S. 8.0) | Enclosed octagonal hub | World/Nexus (or World/Hub) | PARTIALLY IMPLEMENTED (batch 1 running) | smoke (lobby), integration | Wings come in batch 2 |
| R4 | Stores and areas must work (§5) | Master Shop, every door does something | ShopWindow, PurchaseService | NOT IMPLEMENTED (batch 1) | shop_test (planned) | Market and Watch still say "opens soon" |
| R5 | Thanksgiving switch-over (§3, 25.3) | Calendar and Thanksgiving dressing | Seasons/Calendar, SeasonalDecor/Thanksgiving | PARTIALLY IMPLEMENTED (calendar exists; restyle running) | smoke (holidays) | |
| R6 | Player bases as a second home (§6, refs 5–6) | Base Street, base interiors, basement vault | (new) | NOT IMPLEMENTED (batch 2) | | |
| R7 | Battlefields (§7, refs 7–8) | About 20 themed chambers with spectator galleries | Arenas/* | NOT IMPLEMENTED (5 open arenas exist; floors pass in batch 1) | smoke_arenas | |
| R8 | Combat overhaul (§8, §17, P.S. 9.0) | Fighting System v2, client feel | Combat/Defense/Ability services, Controllers | PARTIALLY IMPLEMENTED | combat_test 40/40, smoke_combat 11/11 | Per-ability effects, camera and environment reactions to upgrade |
| R9 | Targeting (§9) | Click-to-target (Corruption, Syntax, Admin), aimed shots (Machine Master), teleport targeting and directional slashes (Ghost) | (new TargetingController, server validation) | NOT IMPLEMENTED (batch 2) | | |
| R10 | Energy and cooldowns (§10) | Lower costs, faster regen, all in config | Config/Combat, power definitions | NOT IMPLEMENTED (batch 2) | | |
| R11 | Flight and hover (§11) | Premium fighters' flight | (new) | NOT IMPLEMENTED (batch 2) | | |
| R12 | Admin chat commands (§12) | Small allowlisted command set for the Admin fighter | (new) | NOT IMPLEMENTED (batch 2) | | |
| R13 | Lobby, training, combat separation (§13) | Lobby lock, free training trials, owner showcase | PowerService (combatContext), Ability/Combat guards | IMPLEMENTED BUT NOT FULLY TESTED | lobby_rules_test | Live Studio check |
| R14 | Degree pricing, premium unlock + selection price, extra slots (§14) | Phase evolution fees during matches (DECISIONS 14) | PowerService, Config/Selection | PARTIALLY IMPLEMENTED (batch 1 running) | phase_test | Extra-slot pass needs an owner-created id |
| R15 | Selection screens, 3D previews (§15, refs 9–11) | Fighter showcase and pre-match flow | PowersWindow, PlayWindow | NOT IMPLEMENTED (batch 1) | smoke_ui | |
| R16 | Onboarding, tips, How to Play, tutorial (§16) | Jeffery-led onboarding | (new) TutorialService, Jeffery | NOT IMPLEMENTED (batch 2) | | |
| R17 | Sound (§18, P.S. 7.0) | Audio manager, manifest, placement map, volume groups | Config/Audio (basic) | PARTIALLY IMPLEMENTED (batch 3) | | Listening and rights checks are owner tasks |
| R18 | Performance, cleanup, devices (§19) | Budgets, cleanup, scaling | all | PARTIALLY IMPLEMENTED | cleanup checks in power tests | Live profiling needs Studio |
| R19 | Reference images (§20, P.S. 6.0) | Reference audit below | this file | IMPLEMENTED (audit written) | | Each reference is "addressed" only when its feature lands |
| R20 | Release acceptance tests (§22) | Full suite and Studio checklist | tests/* | PARTIALLY IMPLEMENTED | runall | Multi-server and real purchases need the owner |
| R21 | Owner access to everything (24.1) | Free fighters, degrees, slots; showcase anywhere | OwnerService, PowerService | PARTIALLY IMPLEMENTED | lobby_rules_test | Owner-exclusive powers in batch 3 |
| R22 | Owner Control Center v2 (24.2, 24.14) | Console with all sections, search, favorites | OwnerPanel (v1) | NOT IMPLEMENTED (batch 3; v1 works) | | |
| R23 | Cross-server control (24.3) | MessagingService + MemoryStore state, recovery for new servers | (new) | NOT IMPLEMENTED (batch 3) | | Live verification needs several real servers |
| R24 | 200+ event library and seasonal collections (24.4–24.7) | Effect modules plus data-driven presets | Config/AdminEvents (13 events) | NOT IMPLEMENTED (batch 3) | | |
| R25 | Custom event creator (24.8) | Builder with preview, timeline, saved presets | (new) | NOT IMPLEMENTED (batch 3) | | |
| R26 | Summoning and arrivals (24.9) | TeleportService joins, invitations, arrival effects | (new) | NOT IMPLEMENTED (batch 3) | | |
| R27 | Global broadcasts (24.10) | Announcement cards across servers | (new) | NOT IMPLEMENTED (batch 3) | | |
| R28 | Safety and emergency restore (24.12) | Stop, restore, clear | AdminEventService (v1 cleanup) | PARTIALLY IMPLEMENTED | admin events in smoke | |
| R29 | Owner security and audit (24.13) | UserId-only owner, allowlisted actions, rate limits, log | OwnerService, OwnerConfig | PARTIALLY IMPLEMENTED | integration (owner checks) | Replay protection and persistent audit in batch 3 |
| R30 | Named memes and formats (25.2) | Original homages per DECISIONS 17–18 | (new) | NOT IMPLEMENTED (batch 3) | | |
| R31 | Live meme calendar (25.3) | Monthly, weekly, daily, holidays, moving dates | Seasons/Calendar (holidays) | PARTIALLY IMPLEMENTED | | Months and meme collections in batch 3 |
| R32 | Trend management (25.4) | Owner-managed trend entries | (new) | NOT IMPLEMENTED (batch 3) | | No scraping by design |
| R33 | Owner meme and calendar control (25.5) | Calendar view, scheduling | (new) | NOT IMPLEMENTED (batch 3) | | |
| R34 | Event levels and frequency (25.6) | Ambient to global levels, combat respect, opt-outs | (new) | NOT IMPLEMENTED (batch 3) | | |
| R35 | Meme Vault (25.7) | Basement archive with luxe lift | (new) | NOT IMPLEMENTED (batch 2–3) | | |
| R36 | Content quantities (25.8) | 40 experiences, 60 variations, 20 mascots, 15 takeovers | (new) | NOT IMPLEMENTED (batch 3+) | | Built in batches; never padded |
| R37 | Jeffery (P.S. 1.0) | Robot, dialogue system, onboarding, hints, practice modes 1–4 | (new) | NOT IMPLEMENTED (batch 2) | | |
| R38 | AI layer (P.S. 1.0 §6, P.S. 2.0) | Knowledge base first, optional provider | (new) | NOT IMPLEMENTED (batch 3) | | Provider costs money: owner decision |
| R39 | Corruption three phases (P.S. 3.0 A) | Phase kits, transformations, ultimates | Powers/Corruption | PARTIALLY IMPLEMENTED (kit exists) | power_Corruption_test 15/16 | New phase concepts in batch 2 |
| R40 | Syntax three phases (P.S. 3.0 B) | Interface-tool kit, duplicates, workspace ultimate | Powers/Syntax | PARTIALLY IMPLEMENTED | power_Syntax_test 29/32 | |
| R41 | Admin command arsenal and Root Authority (P.S. 3.0 C) | 14 commands, ultimate | Powers/Admin | PARTIALLY IMPLEMENTED | power_Admin_test incomplete (hangs) | |
| R42 | Premium presentation (P.S. 3.1) | Showcase, intro sequence, phase preview | PowersWindow | NOT IMPLEMENTED (batch 1–2) | | |
| R43 | Visual quality mandate and audits (P.S. 4.0, 5.0) | ArtDirection v3, renders, audit list | docs/ArtDirection.md | PARTIALLY IMPLEMENTED | renders | Live screenshots need Studio |
| R44 | Future standard: robots, infrastructure (P.S. 8.0) | Facility robots with jobs, terminals, doors | (new) | NOT IMPLEMENTED (batch 2) | | |
| R45 | Cinematic camera, environment reactions (P.S. 9.0) | Ultimate cameras, arena reactions | CameraController (lock-on) | PARTIALLY IMPLEMENTED | | |
| R46 | Regional price levels and transfer rules (P.S. 11.0 Part 1) | PriceLevel cache, TransferPolicy gate | (new) | NOT IMPLEMENTED (batch 1) | pricing_test (planned) | Game has no trading or gifting (DECISIONS 21) |
| R47 | Dynamic prices (P.S. 11.0 1.8) | Prices fetched from Roblox, never hard-coded | (new) PricingService, ShopWindow | NOT IMPLEMENTED (batch 1) | | |
| R48 | Receipt audit (P.S. 11.0 1.9) | One idempotent ProcessReceipt | PurchaseService | IMPLEMENTED BUT NOT FULLY TESTED | data_test (fakes) | Real purchases need the owner |
| R49 | Pass ownership checks (P.S. 11.0 1.10) | UserOwnsGamePassAsync with retry | PurchaseService, PowerService | PARTIALLY IMPLEMENTED (batch 1 audit) | | |
| R50 | Dynamic Price Check (P.S. 11.0 Part 2) | Creator Hub test | none | OWNER ACTION REQUIRED | | Cannot be run from here |
| R51 | FINAL_OWNER_HANDOFF.md (P.S. 11.0 Part 3) | Owner checklist and inventories | FINAL_OWNER_HANDOFF.md | NOT IMPLEMENTED (batch 1) | | |
| R52 | Spectating Lounge (P.S. 13.0, ref 15) | Lounge, match screens, spectator cameras | Watch (server spectating exists) | PARTIALLY IMPLEMENTED (server only) | | Room and screens in batch 2 |
| R53 | Refreshments (P.S. 13.0 §3) | Earned-credit consumables, casual modes only | (new) | NOT IMPLEMENTED (batch 2) | | |
| R54 | Prediction board, no wagering (P.S. 13.0 §4) | Free predictions, community percentages, accuracy stats | MatchService, ProgressionService | PARTIALLY IMPLEMENTED (reward removed 3 Nov) | | Board and stats in batch 2 |
| R55 | Usage budget and project docs (P.S. 14.0) | Docs, model choice, checkpoints | these files | IMPLEMENTED | | Owner checks `/usage` |
| R56 | Psychology and motivation (P.S. 15.0, 19.0) | Mastery, achievements, rivalry, leaderboards, post-match feedback | ProgressionService (mastery, challenges) | PARTIALLY IMPLEMENTED (batch 4) | | |
| R57 | Value-based monetization (P.S. 15.1) | Catalogue with clear value, optional season pass | Config/Monetization | PARTIALLY IMPLEMENTED (batch 1) | | No paid randomness, no fake timers |
| R58 | Founders' Archive (P.S. 16.0) | Lounge exhibit with chapters and illustrations | ArchiveWindow, Content/Archive (canon exists) | PARTIALLY IMPLEMENTED (book exists) | lore_test 8/8, smoke_archive 10/10 | Illustrations need generation and owner upload |
| R59 | Facility layout (sketch and blueprint) | Hub plus wings per DECISIONS 8–9 | World/* | PARTIALLY IMPLEMENTED (hub running) | | |
| R60 | Traceability and verbatim spec (P.S. 17.0) | This table, MASTER_REQUIREMENTS.md | | IMPLEMENTED | | |

## Reference audit (P.S. 6.0)
Images live in the session scratchpad (`$S/references/`), not the repo (DECISIONS 11).

| # | What it shows | Qualities to carry over | Applies to | Addressed? |
|---|---|---|---|---|
| 1 | The current game in Studio: outdoor grass, colonnade with empty niches, emoji ability icons, grey key strip, gold crown OWNER tag | What to fix | Statues, HUD buttons, nameplate, floors | In progress (R1–R3) |
| 2 | The current Powers window: navy glass, blue outlines, cyan pills, tiny text | What to fix (the owner's table labels image 2 "ground and design direction"; the photo shows the selection window) | Selection screens | In progress (R15) |
| 3 | Isometric sci-fi hub: zoned stations, clear signage, a glowing centrepiece, a big GO marker | Readable zones, signage, one centrepiece | Hub layout, wayfinding | In progress (R3) |
| 4 | Sci-fi station interior: ring portals, light pylons, lab tubes, view window | Scale, ring portals, integrated light | Hub and wings | In progress (R3), wings batch 2 |
| 5 | Armory room: items on lit wall panels and pedestals | Displays for collections | Player bases and vault, Master Shop | Batch 2 |
| 6 | Sci-fi lounge: sofas, rug, bar, gear displays, screen | Comfortable tech interior | Player bases, lounge | Batch 2 |
| 7 | Gladiator training yard: marked zones, dummies, galleries around | Clear combat space, spectator galleries | Battlegrounds, Training Studio | Batch 2 |
| 8 | Characterful training dummy on a round target pad | Memorable training props | Training Studio, Jeffery's practice | Batch 2 |
| 9 | Store screen: category rail, big framed cards, clear prices | Card presentation, hierarchy | Selection and shop screens | Batch 1 (R15, R4) |
| 10 | Character select: character seated in a lived-in scene, portraits left, skins right | Selection as a scene, not a menu | Fighter showcase | Batch 1–2 (R15, R42) |
| 11 | Lobby showcase: character standing in a scene beside a gear case | Player shown with their loadout | Fighter showcase | Batch 1–2 |
| 12 | Anime fight frames: fire, portal rings, debris, blue against orange | Environment reacts, spatial effects, scale | Combat effects (P.S. 9.0) | Batch 2 |
| 13 | Anime "domain" frames: colour grade shift, floor sigils, a giant structure appears | Ultimates transform the arena | Ultimates, premium fighters | Batch 2 |
| 14 | Manga clash frames: blue against purple auras, mid-air exchange | Clashes, aerial readability, auras | Clash moments, aerial combat | Batch 2 |
| 15 | Luxury lounge: warm cove light, leather sofas, round marble table, big screen, glass ceiling | Materials, warm and cool light, comfort | Spectating Lounge (primary) and the realism standard (P.S. 5.0) | Batch 2 |
| 16 | The owner's floor plan sketch and the generated blueprint | Destinations and relationships | Facility layout | Hub in progress; wings batch 2 |

## Addendum A review (3 November 2026, evening): gaps and milestones

| Area (directive section) | What exists and works (evidence) | Most important gap |
|---|---|---|
| Hub and navigation (3) | Octagonal hall, eight numbered doors, statues, Jeffery, Archive files (smoke 12/12, statues_test, lore_test) | Vault entrance from the hall, reserved expansion doors signed as such |
| Battlegrounds (3) | Five arena designs (Proving Grounds, Corrupted Wastes, Digital Grid, Ruined Fortress, Soul Foundry), 20 chamber slots with spectator rooms (chambers_test) | Owner's count is four; per-design gameplay features to make each play differently |
| Fighters (4) | Eight fighters with phases evolving in a match, aimed abilities (all power tests, targeting_test) | Directive lists seven (no Shapeshifter): owner to confirm; premium phase identities and ultimates (P.S. 3.0) |
| Combat feel (5, 6) | Server-authoritative moveset, defense prompts, hit feedback | **No sound at all yet**: every audio id needs the owner's verification; cinematic KO camera |
| Training and onboarding (7, 16) | Jeffery's tour, Training Studio with practice fights (tutorial_test, practice_test) | Fighter-specific drills; a memorable first-minute moment |
| Social (3, 11) | Spectating Lounge, prediction board, Player Base Street and homes | Invites, referrals, friends bonus (in progress) |
| Progression (9) | Mastery, daily challenges, Archive | Achievements, titles, boards, season pass (in progress) |
| Economy (10) | One idempotent ProcessReceipt, regional price levels, live prices, Gems path | Cosmetic catalogue and season pass (in progress); every id is 0 until the owner creates it |
| Owner tools (12) | Event engine across servers, announcements, scheduler, custom creator (overlord tests) | Control Center screens (in progress) |
| Analytics (9) | None | Funnel, economy and progression events (in progress) |
| Seasonal (8) | Calendar, Harvest Week dressing, 40 holiday owner events | Winter dressing before 1 December; meme calendar (section 25) |

Milestones, in the directive's order of priority:
- **G1 (now):** status and recognition, community and referrals, analytics, cosmetic season pass;
  Control Center screens. Each with its own tests.
- **G2:** sound: a registry with only owner-verified ids (or Roblox-owned library audio checked
  through the asset API), per-fighter hit and ability sounds, music by area, fallbacks.
- **G3:** premium fighter overhaul (P.S. 3.0) and a cinematic knockout camera for ultimates.
- **G4:** battleground identities: one gameplay feature per design (hazards, cover, height).
- **G5:** winter dressing, meme calendar, Jeffery's knowledge base, mobile performance pass.
