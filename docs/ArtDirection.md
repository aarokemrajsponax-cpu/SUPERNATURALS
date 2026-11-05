# SUPERNATURALS: art direction, "The Facility" (v3, 3 November 2026)

The binding visual standard for the world, statues, characters, effects and interface. It
replaces "The Sanctum" (imperial marble), following the owner's 3 November directive: a
futuristic, prestigious research complex from 2027–2028 where extraordinary abilities were
studied and are now trained, tested and shown. The statues and the Lantern stay: they are the
oldest things in the building, displayed like museum installations inside modern architecture.
When in doubt: fewer, better things; real materials; purposeful light; readable at a glance.

## 1. The idea
The Meridian Institute built this complex around something it found (the Lantern and the eight
statues). Today it is a working facility: engineered, maintained, lived in. Technology is
built into the architecture, not stuck on it. Warm light means people and comfort; cool light
means machines and energy. Spectacle is reserved for powers, events and ultimates.

## 2. Palette
| Role | Colour | Use |
|---|---|---|
| Deep navy | #0E1624 | large dark surfaces, UI backgrounds |
| Charcoal | #16181D | floors, frames |
| Graphite | #23272E | panels, furniture bases |
| Brushed steel | #8A929C | structure, trims (Metal) |
| Ceramic white | #E6E8EA | wall cladding, lab surfaces |
| Soft cool white | #E8EEF4 | UI text, light panels |
| Warm amber | #E8A24A | key light, comfort accents, primary UI action |
| Copper / bronze | #B8733F / #9C7A4E | warm metal accents, furniture details |
| Electric cyan | #3FD6E8 | technology accent, used sparingly (one per view) |

Wayfinding colours, used only as thin floor inlays, door-frame strips and signage marks (never
as room lighting): Combat amber-orange #E07A3A, Training cyan #3FD6E8, Social warm white
#F2E6D0, Personal green #5FC48A, Special violet #8E7BE0, Expansion coral #E06A6A.

## 3. Materials (Roblox)
| Surface | Material | Notes |
|---|---|---|
| Hub and corridor floors | Slate or Basalt, dark charcoal, Reflectance 0.05–0.1 | large tiles with 0.15-stud seams, inlaid metal or light strips |
| Service and training floors | DiamondPlate, Metal | grating zones, painted safety edges |
| Lounge and homes | WoodPlanks (walnut), Fabric rugs, Slate | warm and soft |
| Structure | Metal (brushed steel), Concrete | chamfered beams, ribs, columns |
| Cladding | SmoothPlastic or Marble in ceramic white; Glass | panels with reveals |
| Glass | Glass, Transparency 0.55–0.8, Reflectance 0.1–0.2 | metal mullions; never a flat clear sheet |
| Screens | SurfaceGui on SmoothPlastic, LightInfluence 0 | real content, readable text |
| Light strips | Neon, at most 0.2 studs thick | inside reveals and coves, never outlines everything |
| Energy and holograms | ForceField, Neon, Beams | powers, holograms, statue rings |
| Statues | Marble, warm ivory | on dark stone and brushed-steel plinths |
| Upholstery | Fabric (charcoal, navy, cognac leather tones) | lounge, homes |
No grass, dirt or terrain ground anywhere indoors. Every area gets its own floor treatment.
Owner add-ons (optional): MaterialVariants for polished floors and brushed metal, MeshParts
with SurfaceAppearance for hero props; code must work without them.

## 4. Architecture
- Large, purposeful volumes with layered ceilings: coffers or ribs, light coves, skylights or a
  glass roof over the hub. Ceilings are never empty planes.
- Chamfered, octagonal geometry as the house motif (from the owner's floor plan), clean
  bevels, thick structural frames, glass partitions with mullions.
- Every room has a purpose, an entrance with a lit portal frame and a sign (room name in the
  display face, wayfinding mark, short subtitle), and foreground, middle and background detail.
- Integrated technology: automatic doors, wall terminals with readable screens, access
  panels, conduits in channels, maintenance robots with jobs. No decoration without a reason.

## 5. Statues and plinths
- Eight figures, one per power, carved in warm ivory marble: proportioned human figures
  (eight-head canon), calm faces, readable silhouettes, each with one attribute that names its
  power (gauntlets, katana, wolf pelt, machine arm, cracked mask, transform-handle frame,
  command staff, martial robe). No boxes, no mannequins, no placeholder parts.
- Plinth: dark stone base, brushed-steel band, a thin light ring in the power's colour,
  engraved name plate (power name in the display face, programme codename below).
- Light: one warm spotlight from above and a cool rim light; a slow, faint holographic ring
  or motes in the power's colour is the only effect. Owner-imported meshes may replace the
  carved figures (ReplicatedStorage.Assets.Statues.<PowerId>).

## 6. Lighting
Future lighting with shadows. Warm key, cool fill, controlled contrast: dark areas keep detail,
bright areas are never blown out. Bloom subtle (Intensity about 0.35, Threshold about 1.4),
Atmosphere light, ColorCorrection gentle. Each area defines its mood: hub (warm daylight
through glass roof plus cool accents), lounge (amber coves, cyan screen glow), training
(clean cool white), battlegrounds (stadium key lights plus arena colour), homes (warm, dim).

## 7. Interface ("next-generation facility software")
- Panels: deep navy glass at low transparency (0.05–0.12), 1 px hairline strokes in cool
  grey, 6 px corner radius, generous padding on an 8 px grid. No random gradients or glows.
- Type: Michroma for short display titles only (caps, tracked); Builder Sans for all UI text
  (Body 16, Label 14, Title 20–24, minimum 14 px at 1280x720); RobotoMono for numbers.
- Colour: soft white text; amber for the one primary action; cyan for selection, focus and
  live information; red only for danger. Locked items: dimmed with a lock icon and the exact
  requirement or price.
- Every control has hover, pressed, selected, disabled and focus states, with 0.15–0.3 s
  quint-out motion. Drawn icons from `Icons.luau`, one stroke weight, no emoji.
- Different screens, different layouts: combat HUD is minimal; selection is a showcase with a
  3D preview; Jeffery's dialogue is a character panel; the owner centre is a command console.

## 8. Effects
Layer every ability: preparation, activation, main effect, impact, residue. Each power has
its own shapes and palette: Strong Dude (amber dust, ground cracks), Ghost (pale blue-white
mist, crisp slash arcs), Shapeshifter (green and earth, claw marks), Machine Master (ember
orange, steel sparks, smoke), Corruption (black, deep violet, dark red, fractures, rifts),
Syntax (electric blue, white, cyan; selection boxes, transform handles, grids), Admin (black,
gold, white, electric blue; cursors, command panels), Grandmaster (gold ink brushwork, air
rings). Big effects are reserved for ultimates. Opponents and telegraphs stay readable;
effects never fill the screen. Respect the reduced-effects and camera-shake settings.

## 9. Sound
Each space sounds different (hub hum and distant activity, lounge warm and quiet, training
clean and rhythmic, arenas loud). UI sounds are short, soft and consistent. Every power has
its own sound palette. All audio comes through one manager with volume groups.
