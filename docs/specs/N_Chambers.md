# Task N — Enclose the arenas as Meridian Station's Test Chambers

The owner: "Everything must be indoors... give four nice walls around... science and sci-fi vibe."
Read ART.md (including "Setting: Meridian Station"), L_Facility.md (the world) and C_Arenas.md
(the arena contract). The five arenas and the training hall exist (src/server/Arenas/*,
ArenaService.luau) and pass tests/smoke_arenas.luau. Make each one an indoor TEST CHAMBER of the
station without losing its identity: in the fiction, the chamber's environment systems
simulate the theme (Ruined Fortress = "Chamber 3, historical simulation"; Digital Grid =
"Chamber 6, LATTICE data space"; Corrupted Wastes = "Chamber 5 annex, ECLIPSE residue, sealed
and stabilised"; Soul Foundry = "Chamber 4, FURNACE works"; Proving Grounds = "Chamber 1").
- Four real walls and a ceiling around each arena's slot: chamber walls with panels, a
  plinth, an observation window strip with a lit control room behind glass, a big chamber
  number and name stencilled/lit, emitters and light rigs in the ceiling (or a glass ceiling
  section where the theme wants sky: a "sky projection" panel array with a soft gradient
  glow), doors with status lights. Replace or fold in the open-air terrain scenery so nothing
  reads as outdoors (themed backdrops can be large wall-mounted environment panels, sculpted
  set pieces or terrain *inside* the walls).
- Keep the gameplay contract and every smoke_arenas.luau check (floor, barriers, spawns,
  throwables, interaction points, sign, no unanchored parts, no scripts, terrain inside the
  slot box). Raise the part budget to 560 per arena (update Config Arena.PartBudget and the
  smoke check). The chamber walls are good wall-splat surfaces; keep a clear fighting space.
- The TRAINING WING (Arenas/TrainingHall.luau): an indoor training room of the station
  (sparring mats, racks, target boards, observation window, MERIDIAN markings), enclosed,
  consistent with where the Garden's Training Wing door leads. Coordinate with the current
  Nexus.luau: read where the Training Wing door is and where ArenaService places the hall.
- Lighting inside chambers: motivated (ceiling rigs, wall strips), a few hero lights with
  shadows, readable floor.
You own src/server/Arenas/*, src/server/Services/ArenaService.luau, the Arena section of
src/shared/Config/Match.luau and tests/smoke_arenas.luau. Render each chamber (scene arena:<id>,
plus a setup scene that clears terrain first: scratchpad/world_arenas/setup_template.luau) and the
training wing from inside at eye level, from the control-room window, and overview with the
ceiling hidden if needed (you may add a "hide ceiling" option to your own setup script). Run unit
tests, rojo build (build/chambers.rbxl), place_check, smoke.luau, smoke_arenas.luau,
integration.luau (alone), powers_test.luau, combat_test.luau. Report render paths.
