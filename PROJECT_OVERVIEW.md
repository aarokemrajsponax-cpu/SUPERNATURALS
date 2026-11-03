# SUPERNATURALS: project overview

A premium sci-fi superpower fighting game for Roblox, set in a futuristic research facility
that once studied extraordinary abilities and now trains, tests and shows them, with live
seasonal events, internet-humour takeovers and an owner (AJKR) who can run them across servers.

## Pillars
1. **Combat** that feels great: Fighting System v2 (light/heavy strings, grabs, sweeps,
   aerials, stamina, counters, clashes), eight distinct powers with phases that evolve during
   a match, interactive defense prompts, CPU opponents.
2. **A world worth exploring:** the central hub with the Lantern and eight statues, wings for
   battlegrounds, training, the lounge, the shop and player bases.
3. **Understanding:** Jeffery the robot guide, contextual tips, How to Play, practice fights.
4. **A living game:** seasonal calendar, owner-run events, meme takeovers, the Archive story.
5. **Fair value:** premium fighters and cosmetics bought through Roblox's own flows, regional
   pricing kept on, nothing random for sale, the core game free.

## Map of the code
- `src/server/Services/`: CombatService, AbilityService, DefenseService, DamageService,
  StatusService, ProjectileService, ConstructService, CharacterService, MatchService,
  ArenaService, CpuService, DummyService, PowerService, ProgressionService, CurrencyService,
  DataService, PurchaseService, OwnerService, AdminEventService, LoreService, ReplayService,
  WorldService, AntiExploitService.
- `src/server/World/`: Nexus (hub), Statues. `src/server/Arenas/`: arena builders.
  `src/server/SeasonalDecor/`: holiday dressing. `src/server/Powers/`: server ability logic.
- `src/shared/`: Protocol, Config (Combat, Match, Rewards, Monetization, Selection,
  AdminEvents, Audio, Replay), Powers (definitions), Seasons (calendar), Content (Archive).
- `src/client/`: Controllers (Input, Combat, Camera, Effects, Ability, Defense, UI, Owner,
  AdminEffects, PowerFx, WorldFx), UI (Theme, Components, Shell, Icons, windows, HUD),
  Effects (Vfx, Poser), Powers (visuals).
- `tests/`: unit specs, end-to-end tests on a stand-in engine, client smoke tests.
- `tools/preview`: offline 3D renderer used to judge the world without Studio.
- `docs/`: ArtDirection (binding), DesignResearch, specs (build specs), requirements.

## Where to look
Rules: `CLAUDE.md`. Requirements: `MASTER_REQUIREMENTS.md`. Decisions: `DECISIONS.md`.
Plan and traceability: `IMPLEMENTATION_ROADMAP.md`. Status: `PROJECT_STATUS.md`.
Owner launch checklist: `FINAL_OWNER_HANDOFF.md` (being written in batch 1).
