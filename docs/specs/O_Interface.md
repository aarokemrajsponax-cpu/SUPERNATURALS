# Task O — Interface identity overhaul: the Meridian Institute design language

The owner: "The current interface, particularly the selection screens, feels too artificial,
generic, and visually corny... I want an unmistakably intentional visual identity: futuristic,
premium, cinematic, immersive, detailed and beautiful. Every screen should look like it belongs
to the same universe... Eliminate random gradients, excessive neon, giant glowing buttons,
clutter, meaningless particles, generic cards... Do not mistake 'futuristic' for blue lights
everywhere... Players should be able to preview characters and powers, inspect information,
compare choices, and understand exactly what they are selecting... polished transitions that
connect menus to gameplay... present important selections as immersive in-world experiences."
ART.md (all sections) and J_Polish.md (icons, copy pass, sound, loading screen) are part of this
task: do J_Polish.md's work as well.

## The design language (write it down first as docs/ArtDirection.md, then apply it everywhere)
"Meridian Institute": the interface is the station's own software, restored by AJKR.
- Palette: near-black graphite panels (not pure black), warm off-white text, one neutral steel
  accent for structure, ONE signal colour per context (each power's own colour in its screens;
  amber for warnings, red for danger). Glow only on the single most important live element.
- Typography: a display face for titles (Michroma or Jura, uppercase, generous tracking, used
  sparingly), Builder Sans for everything else (clear sizes: Display, Title, Heading, Body,
  Caption, Label), RobotoMono for numbers and technical readouts. Verify fonts exist in Lune's
  Enum.Font / Font.fromName.
- Structure: thin 1-px rules, corner brackets on focal panels, small technical annotations
  ("PRG-ATLAS / D2 / CLR 04"), an 8-px grid, consistent radii (sharp or 2-4 px, not bubbly),
  real hierarchy (one primary action per screen).
- Motion: purposeful easing (Quint out for entrances, 0.18-0.35 s), staggered list reveals,
  hover/press/selected states on every control, no bouncing for its own sake.
- Iconography: drawn icons (Icons.luau, J_Polish.md), one stroke weight, no emoji anywhere.
- Sound: soft UI ticks/confirms through the sound layer (J_Polish.md).

## Rebuild every major screen in it (you own src/client/UI/* windows and Theme/Components/Shell,
## except windows another agent is building right now: ArchiveWindow (Archive agent) and any
## Base/Shop/Season/Results/Watch/Learn/Anomaly windows that don't exist yet — for those, just
## make Theme/Components produce the new look so they inherit it)
- Theme.luau + Components.luau + Shell.luau: the new tokens and building blocks (panel with
  bracket corners, section header with annotation, stat bar, comparison bars, rarity tag,
  price tag with currency icon, key-cap hint, tabs, segmented control, list row, empty state,
  loading skeleton, toast styles). Keep existing APIs working (other windows call them).
- POWER SELECTION (PowersWindow.luau) becomes the CALIBRATION interface:
  - left: the 8 programmes as a tidy list of programme plates (codename, power name, a small
    drawn sigil, owned/locked/premium state with exact price);
  - centre: a live 3D preview of YOUR character wearing that power's degree appearance in a
    ViewportFrame (clone your character, apply the power client module's appearance(kit) to the
    clone; rotate by drag; idle animation) with the power's ambient effect; degree tabs (3 or 4)
    that update the preview;
  - right: identity (one-line fantasy, role tags like "Close range / Heavy / Low mobility"),
    stat bars (Damage, Range, Mobility, Defense, Difficulty) derived from definitions/config,
    resource name, defense identity, the loadout slots and ability list with ability preview
    (a short animated diagram of the hit area: arc, line, circle, projectile path, drawn in UI)
    and exact cost/cooldown/damage; a "Compare" mode putting two powers side by side.
  - Opening it from the station's Calibration Chamber (the lobby agent adds a prompt with
    Action "Window:Powers" and a CFrameValue "PreviewCamera"): if that exists, move the camera
    smoothly into the chamber (Scriptable, restored on close) for an in-world feel.
- PLAY (PlayWindow.luau): mode cards that look like mission briefings, the arena picker as
  chamber dossiers (name, number, a drawn floor plan thumbnail), queue state with an elegant
  progress indicator; Training and CPU Practice clearly separated from PvP.
- SETTINGS, HUD (only visual tokens: the combat agent owns Hud.luau logic; coordinate by
  changing Theme/Components, not Hud.luau, unless the combat work is committed), MatchHud,
  AbilityBar, DefensePrompt, the owner panel (another agent may rebuild it: leave OwnerPanel.luau
  alone), toasts, confirms, the dock/navigation (bottom or side rail with drawn icons and labels).
- LOADING SCREEN and FIRST JOIN: J_Polish.md's loading screen, then a short cinematic camera
  glide over the Garden to the spawn (skippable, only on the first join of a session), then the
  welcome card (the Learn agent builds the card; you provide the glide in a small
  IntroController that respects a "skip intro" setting).
- Transitions: opening a window dims and slightly blurs the world (a BlurEffect owned by the
  Shell, tweened), panels slide from their anchor, closing reverses; match start/end use a short
  full-screen wipe in the station style.

## Verify
- Use the UI renderer (scratchpad/preview: dump.luau + render.py; read their headers; adapt it)
  to SEE every screen at 1920x1080, 1280x720 and 667x375. Iterate until it looks like a premium
  studio's UI. Be harsh: is anything generic, cluttered, misaligned, low-contrast, or glowing
  for no reason?
- tests/smoke_ui.luau (tests/smoke/Client.luau): every window opens at the 3 sizes and passes
  auditLayout; no emoji or em dash in any visible text; every Components builder runs; the
  preview builds for all 8 powers and every degree; compare mode; transitions run and restore
  the camera and blur.
- Keep tests/smoke.luau passing (update its UI expectations only where names changed, and say so).
Run: unit tests, rojo build (build/ui.rbxl), place_check, smoke.luau, smoke_ui.luau,
smoke_grandmaster.luau, smoke_arenas.luau, integration.luau. Report real results and render paths.

## Round 4: supersedes the palette and type notes above (the owner tested in Studio)
The owner photographed the current Settings, Powers and Play windows in Studio and called them
"generic, overly AI-generated, insufficiently refined, unfriendly to navigate". The new standard
is /home/user/SUPERNATURALS/docs/ArtDirection.md section 6 (and its overall "Sanctum" idea):
imperial codex meets precision instrument. Use its exact palette, type scale (Accanthis, i.e.
Enum.Font "Bodoni" family, for display/titles; Builder Sans for UI text; RobotoMono for
technical numbers; minimum 14 px), spacing (8 px grid; 24/16/32), square corners, hairline
bronze frames, single bronze accent, and the seven interaction states. Ignore the earlier
"graphite + one signal colour + Michroma" notes where they conflict.

What the screenshots showed (fix all of it):
- dark-navy translucent panels with cyan/blue accents and rounded pills: the generic dashboard
  look;
- small, low-contrast text with weak hierarchy;
- emoji icons on the ability bar, chips and window headers;
- the Roblox-default ProximityPrompt box;
- a chunky gold "👑 OWNER" billboard over the owner (src/client/Controllers/AdminEffectsController.luau,
  around line 428; restyle it per section 6; keep its behaviour);
- generic toasts.

Deliver, in order of visibility:
1. Theme, Components and Shell. Rebuild the tokens and building blocks, keeping the APIs other
   windows call.
   - Theme.type(role) gives the font, size and line height for each type role; Theme.track(text)
     produces display tracking; Theme.state(...) gives the state colours.
   - Every component implements the seven states.
2. The power selection. PowersWindow becomes the Calibration interface:
   - Left: the programme list, as plates: the codename in Accanthis, the power name, a drawn
     sigil, and the owned/locked/price state.
   - Centre: a live ViewportFrame preview of the player's character on a marble pedestal with a
     warm key light, with drag-rotate and an idle pose, showing the power's degree appearance
     (call the power's client module appearance(kit) on the clone where possible).
   - Right: the dossier, top to bottom: the fantasy line, role tags, stat bars, the resource,
     the defense identity, the loadout slots, and ability rows with exact numbers and a small
     drawn hit-area diagram.
   - Degree tabs: 3, or 4 for the Grandmaster. A Compare mode.
   - One primary action at the bottom right: EQUIP, BUY with the exact R$, or TRY IN TRAINING.
3. PlayWindow, SettingsWindow and the Shell's dock/navigation, in the same system.
   - Modes appear as briefing plates, CPU options as clear segmented controls, and the arena
     picker as chamber cards.
   - Settings use grouped rows with labels on the left and controls on the right, all aligned.
4. A custom ProximityPrompt style for every prompt in the game: Style = Custom, drawn by a small
   client module from ProximityPromptService.PromptShown/Hidden, with a hold-progress ring.
   Restyle the owner nameplate. Toasts and confirm dialogs follow the new system.
5. Icons.luau, drawn icons from J_Polish.md, and an emoji purge across src/client (and the
   player-facing text in src/shared). Fix copy where it's awkward.
6. HUD / AbilityBar / MatchHud / DefensePrompt. The combat-client agent is finishing Hud.luau
   right now. Restyle these only after its work is committed (check `git log` for the combat
   client commit). Until then, change only Theme/Components, which they use. Ability buttons
   get drawn icons from the power definitions' icon names (or Icons fallbacks) instead of emoji.
Verify with the UI renderer at 1920x1080, 1280x720 and 667x375, and judge harshly against
ArtDirection section 6 and the owner's notes (alignment, text containment, hierarchy, legibility).
Also confirm in tests that every visible text is at least 14 px at 1280x720 (scaled), that no
emoji or em dash appears, and that every window passes auditLayout.
