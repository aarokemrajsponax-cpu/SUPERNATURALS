# SUPERNATURALS: rules for anyone working in this repo

Roblox superpower fighting game (Luau, Rojo 7). Owner: AJKR (Roblox user XxxXxxX_77797).
Requirements: `MASTER_REQUIREMENTS.md` (verbatim owner spec; read only the sections you need).
Decisions and interpretations: `DECISIONS.md`. Status: `PROJECT_STATUS.md`. Plan and traceability:
`IMPLEMENTATION_ROADMAP.md`. Art direction (binding): `docs/ArtDirection.md`.

## Architecture
- `src/server/Services/*`: one service per system. `Bootstrap.server.luau` ORDER list: each
  service gets `Init(services)` then `Start()`. Client controllers follow the same pattern
  (`src/client/Bootstrap.client.luau`). Add new ones with a one-line ORDER edit.
- `src/shared/Config/*`: tuning and catalogues (combat values, monetization, seasons, events).
  Balance changes go in config, not in code.
- `src/shared/Powers/<Power>.luau` (definition), `src/server/Powers/<Power>.luau` (server
  ability logic), `src/client/Powers/<Power>.luau` (visuals). Eight powers: StrongDude, Ghost
  (the katana "ninja"), Shapeshifter, MachineMaster, Corruption, Syntax, Admin (all three
  premium), Grandmaster.
- `src/shared/Protocol.luau`: every remote and action name. Server validates everything.
- UI: `src/client/UI/` (Theme, Components, Shell, windows). World: `src/server/World/`,
  `src/server/Arenas/`, `src/server/SeasonalDecor/`.

## Non-negotiables
- Server authority: never trust the client for damage, currency, purchases, unlocks, owner
  rights or progress. Validate and rate-limit every request.
- Owner access is by UserId only (`src/server/OwnerConfig.luau`, server-only). The Admin
  *fighter* never grants real admin rights.
- Never invent Roblox asset, product or pass ids. Unset ids are 0 and show "Available soon".
- Purchases: one ProcessReceipt handler (PurchaseService), idempotent by PurchaseId, grant
  only after the profile save succeeds. No paid random items, fake timers or fake scarcity.
- Player-facing text: plain and specific, no emoji, no em dashes, minimum 14 px at 1280x720.
- The guide robot is named **Jeffery** (never "Robbins" or "Jordan").
- Report real results only. Never call untested work complete.

## Tools and tests (from the repo root)
- `S=/tmp/claude-0/-home-user-SUPERNATURALS/49b12892-243d-50da-bddb-d008247b6220/scratchpad`;
  `export PATH=$S/tools:$PATH` (rojo, lune, luau-analyze). These live in the session
  scratchpad; in a new session reinstall rojo 7 and lune 0.10.
- Build: `rojo build default.project.json -o $S/build_<you>.rbxl`.
- Tests: `lune run tests/run.luau` (unit); `lune run tests/<file>.luau <place>` for
  place_check, smoke, integration, combat_test, data_test, powers_test, power_*_test, smoke_*.
  `tests/README.md` explains the stand-in engine (`tests/smoke/Engine.luau`).
- Renders: `tools/preview` (3D); UI renderer in `$S/preview`. Look at renders and judge them.

## Working style for agents (usage is strictly budgeted)
- Read file headers and grep first; read ranges with `sed -n`; never print whole large files.
- Pipe test output through `tail`/`grep`. Don't re-read what you already read.
- Edit only the files your brief names (plus additive shims in tests/smoke/Engine.luau). Keep
  public APIs stable. Other agents edit other files at the same time: never revert them.
- Never run git commands that change history or the working tree; the lead session commits.
- Save work in small compiling steps. Finish, verify, report; don't gold-plate.
