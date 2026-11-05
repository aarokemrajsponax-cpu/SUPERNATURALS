# Task D — Personal bases: a beautiful second home with furniture building

Read CONVENTIONS.md first (same folder) and master_prompt.md Part VI §20 (Personal base:
layout, furniture customization, personalization, social features) and §34-36 (persistence,
cleanup, separate states). Milestone 7 acceptance: "A player's saved base remains correct
after leaving and rejoining." The base is a core system, not a menu: it must look finished,
cosy and premium — warm lighting, real-looking materials, trim, windows, plants — and the
furniture must look like furniture (built from parts with care), not grey blocks.

## Already there (read before writing)
- src/server/Services/DataService.luau, src/shared/Data/Schema.luau: profile.base =
  { floor, wall, lighting, access ("Everyone" | "Friends" | "Nobody"), capacity, items = {
  { i = itemId, x, z, r = 0..3, c = colorIndex, m = materialIndex } } }, profile.furniture.owned
  [itemId] = count, profile.cosmetics.owned, profile.stats (wins etc.), profile.powers.
  DataService:get/update/onLoaded; CurrencyService:spend/add/canAfford; Schema.BaseAccess.
- src/shared/Protocol.luau: BaseAction (Save, SetStyle, SetAccess, Visit, Home, Upgrade, Buy)
  and BaseEvent (Result, Plots); Remotes.BaseRequest / BaseEvent exist. Rate-limit channel
  "Base" exists in AntiExploitService.
- Client design system: src/client/UI/Theme.luau, Components.luau (text, button with Variant,
  card, tabs, scroll, grid, list, price, badge, toggle, slider, iconTile, progress...),
  Shell.luau (registerWindow, open/close, toast, confirm with price, setMode("Editor")).
  Look at src/client/UI/PlayWindow.luau and PowersWindow.luau as examples. The smoke test's
  auditLayout (tests/smoke.luau) requires every text to wrap/truncate and touch targets ≥ 44px.
- src/client/Profile.luau: Profile.get(), Profile.changed, Profile.currency(kind).
- Owner panel/admin code is unrelated; don't touch it.

## You own (create/edit only these, plus additive Engine shims and README rows)
- src/shared/Config/Base.luau — plot layout (8 plots in a row far from the hub, e.g.
  centred around (0, 0, -600) with 140-stud spacing; each plot an island/terrace with the house),
  interior bounds, grid (1 stud), capacity levels and upgrade prices, styles (floors, walls,
  lighting moods) with prices (a few free defaults), the starter furniture every new player gets.
- src/shared/Config/Furniture.luau — catalog of ~28 items across categories (Seating, Tables,
  Lighting, Decor, Plants, Displays, Fun, Premium): id, name, category, price ({ money } or
  { gems } for premium decorations), footprint (x, z studs), height, layer ("Floor" items like
  rugs may sit under others; everything else may not overlap), recolourable palette index list,
  allowed materials, description. Include a power-statue display stand, a trophy case, a
  bookshelf, sofa, armchair, coffee table, bed, lamp, ceiling-free floor lamp, potted plants,
  rugs, a fireplace, an arcade cabinet, an aquarium, neon sign, bean bag, gaming desk, crystal
  pillar, fountain, banner, etc.
- src/shared/Base/FurnitureModels.luau — builds each item's model from parts (used by the
  server for placed furniture and by the client for the placement preview, so they match).
  Quality matters: proportions, bevel-ish edges via wedges/cylinders, legs, cushions, lamp
  shades with PointLights, glass with transparency, leaves from several green spheres, etc.
- src/shared/Base/Layout.luau — pure validation shared by server and client: rotated
  footprints, inside-bounds, overlap rules, grid snapping, capacity, ownership counts.
  Return clear reasons ("That spot overlaps the sofa.").
- src/server/Services/BaseService.luau — assigns each player a plot on join (released on
  leave), builds the house (procedural, beautiful: floor in the chosen style, walls with
  baseboards/trim and windows, a door/portal back to the hub (ProximityPrompt → teleport to
  ArenaService:lobbySpawn()), warm ceiling lights or the chosen lighting mood via local
  lights, a display area with statues for each power the player has unlocked/owned (a stylised
  figure in the power's colours with its icon), and a trophy shelf showing win milestones from
  profile.stats), places saved furniture, and handles Remotes.BaseRequest:
  Save(layout) — validate EVERYTHING with Layout (types, finite numbers, known items, owned
  counts, bounds, overlaps, capacity) and only then apply + DataService:update; reject while
  the player is in a match (MatchService:getMatchOf) or not loaded; never trust the client.
  SetStyle(kind, id) — owned/free check; Buy(itemId or "Style:<kind>:<id>", count?) — price via
  CurrencyService:spend then add to profile.furniture.owned / profile.cosmetics.owned;
  SetAccess(level); Visit(userId) — permission check (Everyone / Friends via
  player:IsFriendsWithAsync in a pcall / Nobody) then teleport to that plot's entrance;
  Home — teleport to own plot; Upgrade — capacity level up for Money.
  Fire BaseEvent Result {ok, message} for every request and Plots {…} to everyone when plots
  change. Visitors can look, never edit: only the owner's requests touch their plot.
  Enforce access: every ~2 s, anyone inside a plot they may not enter is sent to the hub
  with a notice. Players in a match are never teleported by base code.
  Add BaseService to src/server/Bootstrap.server.luau's ORDER (after MatchService) — you may
  make that one-line edit.
- src/client/Controllers/BaseEditorController.luau — edit mode (only in your own base and
  never during a match): a clear top-down/orbit camera, grid overlay, ghost preview of the
  item at the cursor/centre (green = valid, red = invalid with the reason), place, select an
  existing item to move/rotate/delete, rotate (R / button), recolour (palette) and material,
  undo/redo, Cancel (discard) and Save (send the whole layout once). Works with mouse,
  touch (tap to place, buttons for actions) and gamepad (thumbstick moves the cursor, buttons
  act). While editing, combat inputs must not fire (bind your actions at high priority and
  sink them; set Shell.setMode("Editor") and back). Add it to src/client/Bootstrap.client.luau's
  ORDER — you may make that one-line edit.
- src/client/UI/BaseWindow.luau — Shell window "Base" (icon 🏠, order 3): Go home, Edit
  (enabled only when you're in your base and not in a match), Visit (players in the server
  with their access level; disabled when not allowed), Furniture shop (categories, item cards
  with price, owned count, Buy with confirm), Styles (floor/wall/lighting with previews of
  their colours, price/owned/equip), capacity bar + upgrade, access setting. Register it from
  src/client/Controllers/UIController.luau (one line next to the other register calls — you
  may make that edit).
- tests/base_test.luau — end-to-end with tests/smoke/World.luau: plots assigned; starter
  furniture; buy item (money spent, owned count); valid save applies (models built) and
  persists across leave + rejoin (same DataStore fake — see tests/data_test.luau for how
  rejoin works with the fake store); invalid saves rejected (outside bounds, overlap, not
  owned, too many, junk types, NaN); visitor can't edit another base; access Nobody blocks
  visit, Friends needs friendship, Everyone allows; access enforcement removes intruders;
  no base actions during a match; styles purchase + apply; capacity upgrade.
- tests/Layout.spec.luau — unit tests for Layout.
Also extend tests/smoke.luau to build every furniture model, open the Base window and press
its buttons, and run the editor through place/rotate/move/delete/undo/save with a fake layout
(it must pass auditLayout). Use your own build output path `-o build/base.rbxl`.
Run: unit tests, build, place_check, smoke, integration, data_test, base_test.

## Round 2 addendum (read this; it overrides anything above that conflicts)
- An earlier attempt was interrupted before writing any file. Start fresh, but work efficiently:
  use API_INDEX.md and targeted reads (sed -n ranges), and create your files early.
- Art direction is binding: ART.md. The house and its furniture must look hand-made and cosy:
  real proportions, trims, bevelled edges, warm motivated lights in lamps, plants with natural
  greens, rugs with borders, varied wood tones. Each plot sits on its own landscaped terrace
  (Terrain allowed: grass, paths, a few trees and rocks, a low stone wall) around z = -600
  (keep terrain within each plot's footprint and south of z = -480; the Nexus terrain stops there).
- Render: a plot with the starter furniture and a plot with a full showcase layout (scene `setup`
  with a setup.luau that assigns plots/places furniture via the services), from overview, inside
  eye level and top-down; plus a "catalog" render of every furniture model in a row. Iterate
  until it looks finished. List final render PNG paths in the report.
- Client checks go in tests/smoke_base.luau (tests/smoke/Client.luau helpers), not smoke.luau.
- Combat keys in v2: E, F, G, C, Q, Z, V, LeftShift, M1; editor keys must not depend on them
  while editing is off, and while editing you sink inputs at high priority as the spec says.

## Round 3 addendum: indoors (overrides anything above that conflicts)
Bases are apartments in Meridian Station's RESIDENTIAL WING (ART.md "Setting"): each plot is an
enclosed, cozy living unit with four walls and a ceiling (warm wood, soft lamps, plants, a big
interior window onto a shared indoor courtyard garden or a "window view" panel), off a clean
sci-fi corridor with a numbered door and a status light. No open-air terraces: replace terrain
landscaping with indoor planters and the shared courtyard. Keep everything else in this spec.
