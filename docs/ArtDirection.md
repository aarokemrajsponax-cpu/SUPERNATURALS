# SUPERNATURALS: art direction, "The Sanctum"

This is the single visual standard for the world, the statues, the effects and the interface.
Every builder follows it. When in doubt, choose restraint, scale and good light over ornament.

## 1. The idea

Imperial grandeur, restored by quiet technology.

Beneath Kestrel Valley lies a colossal hall carved by a vanished civilization: the Hall of the
Eight. When the Meridian Institute excavated under the Lantern's bowl, they found it already
standing, and in it eight colossal statues of figures wielding powers the programmes had not
yet discovered. The Lantern sits on the hall's central dais as if it had always belonged there.
(In the Archive: "It did not fall. It came home.") The Institute planted the hall's great court
with a living valley, the Garden, roofed its broken vault with steel and glass, and threaded
brass instruments and soft holographic displays through the stone. AJKR restored it all and
opened the doors.

So everything the player sees is one of two layers, always in this ratio:
- **The ancient layer (about 85%).** Monumental architecture, ivory marble, warm travertine,
  dark stone, patinated bronze, rare gold leaf, carved inscriptions in an unknown script.
  Timeless, heavy, calm.
- **The Meridian layer (about 15%).** Brass and glass instruments, thin cool-white holographic
  light, clean labels, cables run neatly along the stone. Precise and modern, never louder than
  the stone.

## 2. Architecture

- **Scale creates grandeur, not ornament.** The Garden hall is about 360 x 360 studs and
  100-120 studs high. Colonnade columns are 6-8 studs across and 45-60 tall. Doorways are
  16-24 studs high. A player (5 studs) should feel small but welcome.
- **The Meridian order.**
  - Columns are fluted shafts: a cylinder with 12-16 thin vertical strips set slightly proud.
  - Plain stepped bases and capitals: two or three chamfered discs, with a bronze ring at each.
  - A simple entablature: architrave, a frieze band with an inscription, and a cornice.
  - Use no acanthus leaves or fantasy filigree.
- **Three motifs only**, used at thresholds, capitals and focal objects, never everywhere:
  1. The Lantern star: an eight-pointed star made of two squares at 45 degrees.
  2. The facet: a long diamond lozenge, echoing the crystal.
  3. The meridian line: a thin bronze inlay running through floors and walls, linking the spaces.
     It doubles as wayfinding, because each route's line leads to its gate.
- **Depth and rhythm.** Repeat bays (column, niche, column), alternate lit and shadowed bays,
  and frame views through arches. Keep the central court open; detail gathers at the edges and
  where players stand.
- **Contact and weight.** Every element sits on a base. Every column has a plinth. Statues stand
  on stepped pedestals. Floors meet walls with a skirting band. Nothing floats except the
  Lantern, which is held in a bronze containment ring.

## 3. Materials (Roblox mapping)

| Role | Colour | Material | MaterialVariant name (optional, see section 9) |
|---|---|---|---|
| Ivory marble (statues, columns, trims) | #E8E1D3, vary ±3% per piece | Marble | SN_IvoryMarble |
| Warm travertine (walls) | #CBBBA0 | Limestone | SN_Travertine |
| Dark stone (floors, bases, inlays) | #3D3B3A to #57524C | Slate / Basalt | SN_DarkStone |
| Patinated bronze (accents, attributes) | #8C6A3F, highlight #B58B4F | Metal, Reflectance 0.05 | SN_Bronze |
| Gold leaf (rare: crowns, the dais ring, single focal details) | #D9B25F | Foil | SN_GoldLeaf |
| Lapis cloth (banners, cushions) | #1F2B4A | Fabric | none |
| Garden | natural greens, moss, water | Terrain | none |
| Meridian tech (instruments, screens) | brass #A88A55, light #DDEBFF | Metal / Glass / Neon (tiny) | none |

Coverage rules:
- Gold leaf covers at most 1% of what's visible.
- Neon is allowed only for the Lantern core, holographic hairlines and power effects.
- Never use pure white or pure black.
- Weathering is subtle: darker stone in recesses, a little moss at the foot of walls, and a
  slightly lighter worn path on the floor.

## 4. Lighting

- **Key light.** A warm afternoon sun (ClockTime about 15.2) falls through the glass vault and
  oculus in long shafts, using SunRays with indoor-subtle atmosphere.
- **Fill.** A cool, low ambient light, so the shadowed colonnades read as deep space and forms
  have contrast.
- **Focal lights.** The Lantern is the cool-white heart of the hall. Every statue is uplit from
  its pedestal by two warm SpotLights, set at 30-40 degrees from below and off-axis so the
  shadows carve the form. Shadows are on for at most 3-4 hero lights in the whole hall.
- **Warm zones.** The Lounge, the Archive lectern and lamps use pools of warm light with dark
  between them.
- **Grade.** Slightly warm highlights, neutral shadows, contrast +0.08, saturation about 0, and
  bloom only above a high threshold.

## 5. The statues ("The Eight")

These are colossal works, 28-34 studs tall (about six times a player), on stepped pedestals 8-10
studs high, set in the colonnade bays that face the Lantern.
- **Style: faceted classical.** Classical heroic proportions (about 8 heads tall), contrapposto,
  confident gesture, modelled as large planes and facets. That is deliberate: the ancient
  sculptors cut stone the way the Lantern is cut. Silhouette first, then major volumes, then
  drapery folds (wedges), then a few precise details.
- **Faces:** simplified planes (brow, nose, cheekbones, jaw), eyes as shadowed recesses, calm
  expressions. Hoods, helmets and hair are solid masses, not strands.
- **Materials:** ivory marble figures. Bronze for each figure's attribute. One gold-leaf detail
  per statue. Pedestals in dark stone with a bronze inscription band: the programme codename in
  Roman Antique capitals, and the power name below it.
- **The eight figures** (each must be recognisable from its silhouette alone, at 60 studs):
  1. **ATLAS (Strong Dude):** a braced, powerful figure lifting a fractured stone sphere above
     his head with both arms, a short draped tunic, one knee forward.
  2. **VEIL (The Ghost):** a hooded swordsman in an iaido draw, the katana half drawn across the
     body, and a long cloak whose hem breaks into drifting facets.
  3. **CHIMERA (Animal Shapeshifter):** a figure mid-transformation: a wolf-head hood, one arm
     ending in a bear's paw, a hawk landing on the raised forearm.
  4. **FURNACE (Machine Master):** a broad figure with a heavy bronze gauntlet raised, a
     fuel-cell pack and four short nozzles on the back, and a small blue soul-flame (the only
     emissive) held in the palm.
  5. **ECLIPSE (Corruption):** a veiled figure with a broken halo ring behind the head. Its
     right side has fractured away, showing a dark basalt core through the cracks. Its hands are
     open, almost gentle. Unsettling.
  6. **LATTICE (Syntax):** a robed scholar holding an armillary sphere of thin bronze rings
     with tiny glyph plates, and a geometric hem.
  7. **WARDEN (Admin Powers):** an armoured sovereign with a tall crown and a cape, both hands
     resting on the haft of a great hammer whose head stands on the plinth. The most regal
     silhouette.
  8. **THE GRANDMASTER:** an old master in a calm wide stance, one palm forward and the other
     drawn to the hip, in a simple robe and sash. He is the only figure carved with a lined,
     human face, and he looks uncannily like the station's groundskeeper. This is a lore
     mystery; leave it unexplained.
- **Budget:** about 120-200 parts per statue. CastShadow stays on for the major forms (shadows
  are what reveal sculpture) and off for small bits. Everything is anchored.
- **Replaceable:** if `ReplicatedStorage.Assets.Statues.<PowerId>` exists (a sculpted MeshPart
  model the owner imports later), use it instead of the part-built figure, on the same pedestal.

## 6. Interface ("imperial codex meets precision instrument")

- **Panels:**
  - Warm graphite #15140F to #1C1A16 at 92-96% opacity, flat with no colourful gradients.
  - A 1 px bronze hairline border (#8C6A3F at about 45%).
  - Square corners, at most 2 px radius. No bubbly pills.
  - Padding 24 px, gutters 16 px, section gaps 32 px. Everything on an 8 px grid.
- **Colour:**
  - Text is ivory #EDE6D6 (primary), #B9B0A0 (secondary) or #8E8676 (tertiary, the minimum
    for text, about 5:1 on the panel).
  - The single accent is bronze-gold #C9A45C, used for selection, focus and the one primary
    action on each screen.
  - Danger is #C0533F; success is a muted jade #6FA287.
  - A power's own colour appears only inside that power's context: its portrait, sigil and
    stat fills.
- **Typography:**

  | Role | Font | Size (px, at 1080p) | Line height |
  |---|---|---|---|
  | Display: window titles, big headings, world signage | Accanthis ("Bodoni" in Enum.Font), capitals | 40 | 1.1 |
  | Title | Accanthis | 28 | 1.1 |
  | Heading (section titles) | Builder Sans SemiBold | 20 | 1.15 |
  | Body (descriptions) | Builder Sans Regular | 17 | 1.3 |
  | Small | Builder Sans | 15 | |
  | Caption (absolute minimum, never smaller) | Builder Sans Medium | 14 | |
  | Numbers and readouts | Builder Sans Medium; RobotoMono for timers and technical values | | |
  | Carved inscriptions in the world | Roman Antique capitals | | |
  | The Archive's literary text | Merriweather | | |

  - Button labels: Builder Sans Bold 16, in capitals only when 12 characters or fewer.
  - Roblox has no letter-spacing property: for short display titles in capitals, insert hair
    spaces between letters through one Theme helper, so the tracking is consistent.
  - Body copy keeps lines to 60-80 characters.
  - Never use thin weights on dark backgrounds.
- **Selection states** are distinct without colour alone:

  | State | Treatment |
  |---|---|
  | Default | hairline frame |
  | Hover | frame brightens, background +3%, 120 ms |
  | Pressed | scale 0.98, 80 ms |
  | Selected | 2 px bronze bar on the leading edge, bronze frame, ivory title |
  | Focused (gamepad) | 2 px ivory outline outside the frame |
  | Disabled | 45% opacity plus the reason in text |
  | Locked | a drawn lock icon plus the requirement or exact price chip |

- **Motion:** 120-180 ms for small feedback and 240-320 ms for panels. Quint-out easing, with
  staggered list reveals of 30 ms. Nothing bounces.
- **Icons:** drawn line icons (2 px stroke, square caps, built on an 8-point grid). No emoji
  anywhere.
- **Prompts and nameplates:**
  - ProximityPrompts use a custom style: a compact graphite plate with a bronze key cap, the
    action in Builder Sans SemiBold and the object name in small caps.
  - The owner's nameplate is a quiet bronze small-caps title above the name. No emoji, and
    nothing chunky.

## 7. Effects

Each power keeps its own signature colours. Every move has anticipation, impact and
dissipation, in that order. Spectacle is saved for ultimates and big hits. Ordinary hits stay
readable and brief.

## 8. Sound

The hall is a stone space: use SoundService ambient reverb for it, more intimate reverb in the
Lounge and an arena reverb in the chambers. Layer a quiet bed of air, distant water and
fountain, the faint hum of the Lantern and occasional birds in the Garden. UI sounds are soft
wood and metal clicks. Combat hits are layered and pitch-varied, and loud only on the big ones.

## 9. What the owner can add in Studio (optional upgrades the code already supports)

- **MaterialVariants:** Studio's Material Manager or Material Generator can create the variants
  named in section 3 (for example "polished ivory marble with faint grey veins" saved as
  SN_IvoryMarble, base material Marble). Every part that names a variant picks it up
  automatically; without them, the base materials are used.
- **Sculpted statue meshes:** import them to ReplicatedStorage.Assets.Statues.<PowerId>.
- **Audio** from the Creator Store, pasted into src/shared/Config/Audio.luau.
