# Tests

These run outside Roblox with [Lune](https://github.com/lune-org/lune) (and
[Rojo](https://rojo.space) to build the place). Run them from the repository root.

| Command | What it checks |
|---|---|
| `lune run tests/run.luau` | Unit tests for the pure combat and match rules (`tests/*.spec.luau`) |
| `rojo build default.project.json -o build/game.rbxl` | Builds the place file the next three use |
| `lune run tests/place_check.luau build/game.rbxl` | Every script and remote exists, and every `require` points at a real module |
| `lune run tests/smoke.luau build/game.rbxl` | Runs arenas, holiday decorations, every UI screen, every admin event's visuals and the client's combat effects |
| `lune run tests/integration.luau build/game.rbxl` | Runs the real server services with simulated players: a full duel with scoring and respawns, a forfeit, practice vs a dummy, junk requests, and the owner panel |

`tests/smoke/Engine.luau` is a small stand-in for the Roblox engine. Lune gives
real Instances with Roblox's real property list (a misspelled property or wrong
value type errors just like in Roblox); the stand-in adds the events, methods
and services Lune doesn't have.

These tests can't replace playing in Studio: physics, animation, rendering,
networking and the real engine timing are not simulated. See
`docs/Milestone1.md` for the in-Studio test plan.
