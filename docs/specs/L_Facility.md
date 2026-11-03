# Task L — Meridian Station: everything indoors, a sci-fi research facility

The owner's latest direction (binding):
- "Everything must be indoors. You can keep the fields and stuff but all must be indoors. Give
  four nice walls around."
- "Push that science and sci-fi vibe: these powers used to be experiments that led to here."
- "A lounge that looks cozy, peak, nice, beautiful and aesthetic."
- "A book players can read with a long, mysterious story."
- "Absolutely peak quality graphics... nice, catchy, addictive, aesthetic, yet players understand
  how to play very quickly."
- "Text readable, everything lined up."
- "Don't make it look AI-generated; make it look like a multi-million-dollar studio made it."
ART.md is the visual standard. Read it all, including "The bar: AAA fidelity".

## The world (lore bible: use these names exactly)
A thing fell into a remote valley decades ago: a luminous crystal the researchers called THE
LANTERN. The Meridian Institute built MERIDIAN STATION around it: a sealed complex. At its heart is
THE GARDEN, an enormous enclosed habitat hall where a whole valley (grass, trees, a pond) was grown
indoors under a steel-and-glass roof to keep test subjects calm. Eight research programmes exposed
volunteers to the Lantern's light; each produced one of the game's powers:
  ATLAS = Strong Dude, VEIL = The Ghost, CHIMERA = Animal Shapeshifter, FURNACE = Machine Master,
  ECLIPSE = Corruption, LATTICE = Syntax, WARDEN = Admin Powers (the station's own command
  protocol), and The Grandmaster was never a programme: the station's old groundskeeper, who
  trained in the Garden at dawn and refused the light. The ECLIPSE test caused THE CASCADE; the
  station sealed itself and went quiet for years. AJKR (the game's owner) found it, restored the
  power, and opened it as the place where people come to borrow the powers' "echoes" and fight in
  the old test chambers. The full story is in src/shared/Content/Archive.luau (another agent may be
  writing the book UI; the text exists).

## What you build (you own these files)
src/server/World/Nexus.luau, src/server/Services/WorldService.luau,
src/client/Controllers/WorldFxController.luau, the Lighting section of default.project.json, plus
additive Engine shims. You may update tests/smoke.luau's Nexus check only (part budget, statue
check) with small edits.

1. THE GARDEN, the lobby, rebuilt as one huge indoor hall.
   - **Envelope:** about 360 x 360 studs, walls 70-90 high, four real walls all around. The walls
     are layered: a concrete plinth, ribbed metal panels, a glass observation gallery strip,
     service catwalks with railings, pipes and cable trays, and big structural columns.
   - **Roof:** a steel truss lattice over glass panes, so daylight still falls in and casts
     beautiful lattice shadows. Use Future lighting. Add a few suspended light rigs and hanging
     signage.
   - **Inside:** keep the natural valley. Terrain grass, the pond with reeds, the trees and the
     paths, but sized to fit inside: hills become gentle mounds, and the far mountains become a
     painted-looking "habitat backdrop" or are removed. Terrain must not poke through the walls.
     The current Nexus plaza, monument and gates move inside, recomposed.
   - **The Lantern containment** at the centre replaces the crystal monument: the crystal floats
     in a containment ring with clamps, emitters, cabling to floor ports, hazard markings, a
     railing and a soft light. It is the hero object; make it stunning and believable.
   - **Eight exhibits** replace the statues. Each is a containment pod with a holographic figure
     in the power's colours and a plaque: the programme codename large ("PROGRAMME ATLAS") and the
     power name smaller ("Strong Dude"). The Grandmaster's pod is empty and unlit, with worn
     training wraps and a placard reading "NOT A SUBJECT". His figure stands outside the pod in a
     calm stance.
     - Keep the child names "Statue_<PowerId>" for all eight; tests/smoke expects them.
   - **The five gates** become bulkhead doors set into the walls, with frames, status lights and
     clean signage. The ids, actions and prompts stay as they are.

     | Gate id | Sign text |
     | --- | --- |
     | Battle | TEST CHAMBERS |
     | Training | TRAINING WING |
     | Homes | RESIDENTIAL WING |
     | Market | COMMISSARY |
     | Watch | OBSERVATION DECK |

     You may move gate angles and positions to fit the walls if WorldFxController and the
     tests still work.
   - **Sci-fi life:** holographic wayfinding signs (SurfaceGui, Builder Sans or Michroma/Jura
     for sci-fi labels, readable), status screens with slowly scrolling readouts, small
     maintenance drones parked on charging pads, sample crates, lab benches along one wall,
     warning stripes, "MERIDIAN INSTITUTE" emblems, sector numbers, and a few signs of the
     Cascade (scorched panels near one corner, a sealed door marked 09). It should feel
     restored, not ruined: AJKR fixed it up. Clean, premium, lived-in.
2. **THE LOUNGE:** a cozy room inside the Garden hall, on a raised mezzanine or along one wall,
   with big windows looking out over the valley.
   - **Room:** warm wood floor, a large rug with a border, deep sofas and armchairs with
     cushions, a low coffee table, a hearth (a modern fireplace with a real Fire or particle
     flame and warm light), and floor-to-ceiling bookshelves with varied books.
   - **Lighting and life:** plants, warm lamps (lamps with Shadows on), a coffee bar with mugs,
     a record player, and soft fairy lights.
   - **The Archive:** on a reading lectern near the hearth, a big open leather book with a soft
     spotlight. Give it a ProximityPrompt with ActionText "Read", ObjectText "The Meridian
     Archive" and attribute Action = "Window:Archive".
   - It must look like the coziest room in a AAA game.
3. **Recovered files:** place 10 small terminals or objects around the Garden, the Lounge and
   the gate areas. They should be discoverable, a little hidden, and reward exploring. Candidates:
   a dusty clipboard on a lab bench, a cracked monitor, a tape recorder, a locker, a badge on the
   floor, a note pinned to the door marked 09.
   - Each has a ProximityPrompt (ActionText "Read", HoldDuration 0.4, key T / DPadRight) with
     attribute Action = "Lore:<fileId>" and the part tagged "SNLoreTerminal" with attribute
     LoreId = fileId.
   - Use these file ids: lantern_field_note, procurement_memo, garden_irrigation,
     night_shift_07, varga_tape_12, warden_boot, badge_okafor, eclipse_cleanup, door_09_note,
     ajkr_first_entry.
   - WorldFxController routes "Lore:<id>" to Remotes.ProgressRequest:FireServer("FindLore", id),
     and "Window:Archive" opens the Shell window "Archive" if it is registered. The server side
     and the book UI belong to another agent.
4. **Guidance:** give each gate's floor approach a subtle lit guide line in the gate's colour,
   built into the floor and not glowing loudly, so new players can follow routes. Another agent
   adds animated First Steps trails later.
5. **Global look:** Lighting (in default.project.json) and post effects tuned for a bright
   interior under a glass roof.
   - Readable shadows and warm and cool contrast.
   - Atmosphere subtle indoors.
   - Clouds still visible through the roof.
   - Interior lights with Shadows on only for a few hero lights.
   - Exposure so whites don't clip.

## Constraints
- Contract from I_Nexus.md stays:
  - `Nexus.build(folder)` returns the enabled SpawnLocation, placed somewhere beautiful (facing
    the Lantern with the Lounge visible).
  - `Nexus.Gates` keeps its ids, actions and prompts, with one prompt per gate (key T).
  - The training ground (ArenaService builds it around (-90, 0, 0)) must end up INSIDE the
    station envelope or inside its own enclosed wing, reached through the Training Wing door.
    Read ArenaService.trainingSpawn and the Arenas/TrainingHall builder. If the hall must move
    or be enclosed, coordinate by placing the Garden so the hall sits inside a walled wing. Then
    tell the integrator in your report what changed.
  - The arenas (x >= 330) and personal-base plots (z <= -480) stay outside the Garden envelope:
    they are separate enclosed chambers, and another agent will enclose them.
- **Part budget:** the Nexus folder may grow to about 3,000 parts (raise the smoke check's limit
  to 3,200). Anchor everything, set CastShadow false on small decor, use low particle rates,
  and keep terrain inside the envelope.
- **Performance:** the hall is big. Use larger panels with trims rather than thousands of tiny
  parts, and put detail density where players stand.
- No emoji anywhere. No floating islands. Nothing that looks generated.

## Verify
- Render often with the preview renderer (ART.md), from several viewpoints:
  - the spawn view at eye level;
  - an overview from a high catwalk corner;
  - the Lounge interior (eye level, sitting height);
  - the Lantern close-up;
  - each gate;
  - the exhibits row.
- Write outputs under scratchpad/facility/.
- Iterate until it genuinely looks like a premium studio's hub. Be your own harshest art director.
- Run the unit tests, rojo build (build/facility.rbxl), place_check, smoke.luau, integration.luau
  (alone) and smoke_arenas.luau.
- List final render paths in your report.
