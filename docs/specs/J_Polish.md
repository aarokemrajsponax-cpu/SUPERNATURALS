# Task J — Interface-wide polish: drawn icons, copy, consistency, sound, loading screen

Master prompt §29 (visual quality standards), §30 (animation and sound: "Do not assume an asset ID
exists... create an appropriate placeholder or asset specification... replaceable"), §31
(accessibility). ART.md is the standard. The owner wants every piece and pixel good and nothing
that looks AI-generated. Many windows were built by different agents: make them one product.

## You own
- src/client/UI/Icons.luau — a library of drawn vector icons built from GuiObjects (Frames,
  UICorner, UIStroke, rotated bars, UIGradient; ImageLabel only with no image), crisp at 16-64 px,
  tinted by a colour: Icons.make(name, size, color) -> Frame, Icons.has(name). At least: play,
  fight, swords, shield, target, ghost, paw, gear, cog, bolt, fire, code, crown, hammer, home,
  shop, bag, gem, coin, trophy, star, chart, book, eye, user, users, lock, unlock, check, cross,
  plus, minus, arrow-left/right/up/down, refresh, clock, heart, skull, flag, camera, music,
  volume, gamepad, keyboard, touch, info, warning. Distinct silhouettes, consistent stroke
  weight and corner radius, centred in their box.
- Replace every emoji and pictographic glyph in player-facing UI with Icons or plain text:
  Shell dock/nav icons, Components.iconTile, window headers, status overheads (Combat.Statuses
  `icon` fields are emoji: add an `iconName` per status in Config/Combat.luau's Statuses table
  (additive) and use it in the client), toasts, the owner panel, defense prompts, HUD, wallet
  (Money/Gems symbols drawn as coin/gem icons), every window built by other agents (Powers,
  Play, Settings, Base, Shop, Progress, Watch, Results, Learn, MatchHud, AbilityBar). Search the
  whole client and shared code for non-ASCII characters in strings (`grep -nP "[^\x00-\x7F]"`)
  and decide each one (keep "…" truncation marks and the "×" multiplication sign if used well).
- Copy pass over every player-facing string (UI, toasts, notices from the server, ability names
  and descriptions in the power definitions' text fields, Config text like challenges and lesson
  text): remove em/en dashes (reword), fix tone (natural, specific, short), consistent
  capitalisation (buttons ALL CAPS or Title Case per the design system, sentences in sentence
  case), consistent terms (Money, Gems, Degree, Mastery, Loadout, Ultimate), no "epic"/"unleash"
  filler, at most one exclamation mark per screen. You may edit strings in any file for this
  (strings only; don't change logic you don't own); list the files.
- Consistency pass across windows: same header layout, close button, tab style, paddings (8-px
  grid), corner radii, stroke colours, disabled/loading/selected/error states, empty states
  ("No matches right now. Check back in a minute."), focus/selection for gamepad (Selectable,
  NextSelection paths sensible, the Shell's gamepad navigation works in every window).
- Layout pass at 667x375 (phone), 1024x768 (tablet), 1280x720 and 1920x1080 for every window and
  the combat HUD + touch controls + ability bar together: nothing overlaps, nothing covers combat
  information, text fits. Use the UI renderer (scratchpad/preview: dump.luau + render.py) to SEE
  each screen and fix what looks off.
- src/shared/Config/Audio.luau + src/client/Controllers/SoundController.luau — a data-driven sound
  layer: categories (ui click/hover/confirm/error, hit light/heavy/block/parry/counter/wall splat,
  whoosh, dodge, grab, knockdown, knockout, countdown beeps, round start, victory sting, defeat
  sting, reward tick, level up, purchase), volume from Settings (sfxVolume, musicVolume), pitch
  variation, a cap on simultaneous sounds, music per area (lobby, arena, base, results) with
  crossfades. Use only ids that are certain to exist: built-in rbxasset://sounds/... files that
  ship with every Roblox client and are already used in this codebase (check Config/Audio.luau
  and grep for rbxasset), otherwise nil (silent) — never invent asset ids. Wire the existing
  events (CombatEvent, MatchEvent, DataEvent, Shell clicks) to it.
- docs/Assets.md — the asset specification for the owner: every sound slot and music track (what
  it should sound like, length, where it plays), every animation that would benefit from a real
  Animation asset later (the procedural Poser sequences are the placeholders), with the config
  key to paste an id into. Clear and short.
- A loading screen: src/first/LoadingScreen.client.luau mapped to ReplicatedFirst in
  default.project.json (additive): the game's name set in a clean title treatment, a subtle
  animated background in the game's palette, rotating real tips (from the Learn content / combat
  rules), a progress bar on ContentProvider queue size, fades out when the client is ready; skips
  instantly in Studio test when ready; removes Roblox's default loading screen
  (ReplicatedFirst:RemoveDefaultLoadingScreen()).
- tests/smoke_polish.luau — every icon builds at 16/32/64 px without errors; no emoji or em dash
  in any player-facing string the smoke run can reach (scan every TextLabel/TextButton text in
  every window after opening them); every window opens at all four screen sizes and passes
  auditLayout; SoundController plays every category without errors and respects volume 0; the
  loading screen runs and removes itself.

Follow CONVENTIONS.md and ART.md. Run: unit tests, rojo build (own output), place_check, smoke.luau
and every tests/smoke_*.luau, integration.luau. Report real results.
