# SUPERNATURALS — conventions every build agent follows

Repository: /home/user/SUPERNATURALS (Roblox game, Luau, synced with Rojo 7).
The full design brief from the game's owner is at
/tmp/claude-0/-home-user-SUPERNATURALS/49b12892-243d-50da-bddb-d008247b6220/scratchpad/master_prompt.md
Read the parts relevant to your task. Its rules are binding (server authority,
no fake purchases, bounded effects, cleanup, mobile/gamepad support, readable UI).

## Layout (Rojo, see default.project.json)
- src/server  -> ServerScriptService.Server   (Bootstrap.server.luau starts Services/* in a fixed ORDER)
- src/client  -> StarterPlayer.StarterPlayerScripts.Client (Bootstrap.client.luau starts Controllers/*)
- src/shared  -> ReplicatedStorage.Shared
- src/character -> StarterCharacterScripts
- ReplicatedStorage.Remotes holds RemoteEvents declared in default.project.json

## Code style (match the existing code exactly)
- Tabs for indentation. `local X = {}` module tables, `function Service:Init(services)` / `:Start()`.
- Comments: short, plain English, explain *why*; a header comment at the top of every file
  saying what it is for. Same density as existing files (read 2-3 existing files first).
- Names: PascalCase modules/services, camelCase locals and functions, UPPER_CASE constants.
- Times are `workspace:GetServerTimeNow()` on the server for anything the client also reads.
- Every number someone might tune lives in a config module under src/shared/Config or the
  power definition files, not hardcoded in logic.
- Never trust the client: validate types (`typeof`), ranges, finite numbers, ownership,
  state, cooldowns. Rate limit remotes through AntiExploitService:allow(player, channel).
- Every temporary object (part, constraint, connection, status) has a defined end and is
  cleaned up on death, respawn, leaving, and match end.
- No placeholder/empty modules. Every file has a real job.
- Don't use deprecated APIs (BodyVelocity, BodyGyro, wait(), spawn(), delay()). Use
  LinearVelocity / AlignPosition / AlignOrientation / VectorForce, task.wait/spawn/delay.
- UI text must fit its box: use UIPadding, fixed TextSize (scaled globally by UIScale) with
  TextWrapped or TextTruncate, AutomaticSize where content varies. No text touching borders.

## Tools (already installed, use these exact paths)
T=/tmp/claude-0/-home-user-SUPERNATURALS/49b12892-243d-50da-bddb-d008247b6220/scratchpad/tools
- Syntax check one file: `$T/luau-compile --null path/to/file.luau`
- Unit tests (tests/*.spec.luau, pure modules): `cd /home/user/SUPERNATURALS && $T/lune run tests/run.luau`
- Build place: `$T/rojo build default.project.json -o build/<yourtask>.rbxl` (use YOUR OWN
  output file name, e.g. build/base.rbxl — several agents build at the same time; pass that
  path to every test command below instead of build/game.rbxl)
- Place structure check: `$T/lune run tests/place_check.luau build/game.rbxl`
- Smoke test (runs client UI + effects in a stand-in engine): `timeout 300 $T/lune run tests/smoke.luau build/game.rbxl`
- Integration test (runs real server services with fake players): `timeout 900 $T/lune run tests/integration.luau build/game.rbxl`
- Type check: `$T/rojo sourcemap default.project.json -o /tmp/sm_$$.json && $T/luau-lsp analyze --definitions=$T/globalTypes.d.luau --sourcemap=/tmp/sm_$$.json --platform=roblox src 2>&1 | grep -v "^\[INFO\]\|^\[WARN\]"`
- tests/smoke/Engine.luau is a small stand-in for the Roblox engine (Lune gives real
  Instances with real property validation; the Engine adds signals, methods, services).
  You may ADD shims there (new methods/services) but must not break existing behaviour.
  tests/harness.luau loads modules for unit specs (`Harness.load("Shared/...")`).

## Rules for working alongside other agents
- Only create/edit the files your task lists. Other agents are editing other files at the
  same time. If you need a change in a file you don't own (Protocol.luau,
  default.project.json, Bootstrap ORDER, another service), DON'T make it: list the exact
  change you need in your final report and the integrator will apply it. Exceptions are
  listed in your task.
- Do not run git commands that change state (no commit, checkout, stash, reset).
- Before finishing: syntax-check every file you touched, run the unit tests, build the
  place, run place_check, and run the tests your task names. Report the real results.
- Never claim anything was tested in Roblox Studio. You can't run Studio.

## Final report (your last message)
1. Files created/changed (one line each, what it does).
2. The public API other code should call (signatures + one line each).
3. Changes you need in files you don't own (exact text to add, and where).
4. Tests you ran and their real output summary.
5. Anything incomplete or risky.

## Round 2 rules (read these too)
- Art direction is binding: read ART.md (same folder) before making anything visible. Use the
  preview renderer it describes to look at what you build, and iterate until it looks hand-made.
- Work efficiently. Don't `cat` big files whole: use API_INDEX.md (same folder: every source file
  with its header and its functions with line numbers), `grep -n`, and `sed -n a,bp` for the
  ranges you need. Read a file fully only when you'll edit large parts of it.
- Write early and save often: create your files as soon as you know their shape and keep them
  compiling, so an interruption never loses your work. An earlier attempt at your task may have
  been interrupted: if files you own already exist, read them and continue/finish them instead of
  starting over (check `git log --oneline -5` and `git status --short`).
- Smoke tests: don't edit tests/smoke.luau (several agents work at once). Put your client checks
  in your own tests/smoke_<area>.luau using tests/smoke/Client.luau (check, finish, startUI,
  client/shared requires, press, findNamed, findText, sentSince, auditLayout, fire, setScreen).
  Run it like smoke.luau: `timeout 300 $T/lune run tests/smoke_<area>.luau build/<you>.rbxl`.
- Shared files several agents may touch (Protocol.luau, Bootstrap ORDER lists, UIController
  register lines, Engine.luau shims, Schema.luau, Combat.Statuses): only small additive edits,
  re-read right before editing, use the Edit tool (never rewrite the whole file), and list them in
  your report.
- tests/integration.luau duel timing is tight: if it fails only on timing while you're running
  tests in parallel with other agents, rerun it alone before concluding anything.
