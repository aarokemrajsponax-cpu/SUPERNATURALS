# Task S — The Eight: monumental statues

The owner, after testing in Studio: "I strongly dislike the current appearance of these statues.
They need a great, fundamental improvement... monumental works of art commissioned by an
extraordinarily powerful and sophisticated civilization... start with silhouette, proportions,
posture, composition and form... make every statue feel like an intentional masterpiece... they
must look impressive within the actual game, under the game's actual lighting, from realistic
gameplay camera angles."

The current statues (in src/server/World/Nexus.luau, function `figure` and `buildStatues`):
- ~6.5 studs tall: barely bigger than a player, so they have no presence.
- Built from ~15 boxes: mannequin silhouettes, no pose, no drapery, no faces.
- Flat colour per power: they read as plastic toys, not sculpture.
- Short plinths standing in grass: no architectural setting and no light designed for them.
Throw that design away.

READ FIRST: /home/user/SUPERNATURALS/docs/ArtDirection.md (binding; section 5 is your brief:
the eight designs, scale, style "faceted classical", materials, budget, replaceability) and the
lore in src/shared/Content/Archive.luau (the "Memorandum 4: The Hall Beneath" document and the
programme files).

## Build (you own these files)
- src/server/World/Statues.luau
  - `Statues.Order = { "StrongDude", "Ghost", "Shapeshifter", "MachineMaster", "Corruption",
    "Syntax", "Admin", "Grandmaster" }`
  - `Statues.Designs[powerId] = { codename, title, ... }` for the plaques.
  - `Statues.build(powerId: string, base: CFrame, opts: { height: number? }?) -> Model`:
    - Returns a Model named "Statue_<PowerId>". `base` is the centre of the pedestal's bottom on
      the floor; the statue faces the base's LookVector (toward the Lantern).
    - Contents:
      - the stepped pedestal (dark stone, chamfered steps, a bronze inscription band with a
        SurfaceGui using Font Roman Antique: the codename large, e.g. "ATLAS", and the power name
        small, e.g. "Strong Dude");
      - the figure;
      - two warm uplight SpotLights in small bronze cups on the pedestal (Shadows off, except
        on the statues listed in `opts.heroShadows`), aimed so the face and chest catch light
        and the shadows carve the form.
    - Default figure height 30 studs, pedestal about 9.
    - If ReplicatedStorage.Assets.Statues.<PowerId> exists, clone that model instead of the
      built figure, scale it to the height and seat it on the same pedestal (the sculpted-mesh
      upgrade path).
    - Everything anchored. CanCollide on the pedestal only; the figure is CanCollide false
      except its lower body, so players can't climb onto heads.
    - CastShadow on for the major forms, off for small details.
    - MaterialVariant names from ArtDirection section 3 (SN_IvoryMarble, SN_Bronze,
      SN_GoldLeaf, SN_DarkStone) set on each part, together with its base Material.
- How to model sculpture with parts (techniques expected):
  - Build from a proportioned armature: head height h = height / 8.
  - Anatomy:
    - Torso: tapered blocks plus wedges for the pectoral and abdominal planes, with the
      ribcage and pelvis tilted opposite each other (contrapposto).
    - Limbs: chained segments (upper arm, forearm, hand; thigh, shin, foot) with slight
      tapers, using cylinders or wedges for muscle masses. Joints meet cleanly; hide seams under
      drapery or bands.
    - Hands: a palm block plus a grouped finger mass. Faces: planes as described.
  - Drapery: long hanging folds as stacked thin wedges with alternating angles, hems cut on a
    diagonal, a cloak falling from the shoulders.
  - Precision: compute CFrames from joint positions with a small helper, e.g.
    segment(from, to, thickness) builds a part spanning two points, so poses are authored as
    joint positions rather than guesses.
  - Each statue gets a deliberate pose described in ArtDirection section 5. Check it from
    front, 3/4 and side.
  - Silhouette check: each figure must be identifiable from its outline alone at 60 studs.
- Budget: about 120-200 parts per statue including the pedestal (hard cap 220).
- The current lobby is being rebuilt by another agent in src/server/World/Nexus.luau (the great
  hall). It will call `Statues.build` at eight bays around the Lantern. You don't edit
  Nexus.luau. If that agent hasn't switched to your module yet, that's fine: test standalone.

## Verify (render-driven; this is an art task)
- tests/smoke_statues.luau (tests/smoke/Client.luau or plain Engine use):
  - all 8 build;
  - names, anchored, part budget, lights present;
  - plaque text correct, no emoji;
  - the replacement path (insert a fake Assets.Statues.Ghost model and check it's used and
    seated).
- Render every statue with the preview renderer, via a `setup` scene that builds the eight in a
  row or semicircle on a dark stone floor, with the game's Lighting:
  - a 3/4 front view at eye level (camera height 5) from 35-40 studs;
  - a low angle from near the pedestal;
  - a far view at 90 studs;
  - a SILHOUETTE pass: add a `--silhouette` flag to tools/preview/render3d.py (draw every part
    flat black on a light sky) to judge readability.

  Look at every image with the Read tool, critique it like an art director (proportion,
  gesture, silhouette, the read of the attribute, light on the form), fix, and re-render. Do at
  least three iterations per statue. Put the final renders under scratchpad/statues/ and list
  them.
- Run: unit tests, rojo build (build/statues.rbxl), place_check, tests/smoke_statues.luau,
  smoke.luau.

Follow CONVENTIONS.md (economy rules: targeted reads; write early; save often). Report:
- files;
- the API;
- the part count per statue;
- render paths;
- an honest self-critique of what still falls short of "masterpiece" with parts, and what a
  sculpted mesh would add.
