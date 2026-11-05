# Interface craft pass (owner feedback, 3 November 2026)

The owner looked at the dialogue, Play window and match HUD renders and said they "look too AI
generated" and asked for something that looks like a person made it and sits naturally in the
game. The master prompt says the same in its own words: "Do not use generic AI-looking gradients,
random glowing borders, or overcrowded panels", "Generic stock-looking icons", "Avoid unnecessary
all-caps paragraphs", "Prevent text from clipping or overflowing ... Redesign the panel if the
text does not fit", and for Jeffery: "No awkward text placement. No generic chatbot appearance."

What made the screens read as generated:
- Every element was the same translucent navy card with the same 1 px hairline and 6 px corners,
  nested three deep (window, card, chip), so nothing led the eye.
- Capitals everywhere, one weight, one size step between title and body.
- Text that did not fit (Play mode descriptions cut off mid-sentence).
- See-through panels stacked on other panels (Jeffery's dialogue over the ability bar).
- Placeholder-looking boxes (an empty portrait frame) and repeated toasts.

## Rules for every screen touched in this pass

1. **Surfaces.** Anything holding text that sits over other interface is opaque (fill
   `Colors.Panel`, transparency 0 to 0.04). Only the outermost frame of a window or panel gets an
   edge: a 1 px `Colors.Stroke` line at about 0.6 transparency plus a 1 px lighter "lip" along the
   inside of the top edge (`Colors.PanelHover`). Cards inside a window have no outline; they are
   separated by tone (`Colors.PanelLight`) and 8 px gaps. The selected card gets a 3 px cyan bar
   on its left edge and the `Colors.Selected` fill. Corners: 4 px on windows, 3 px on controls.
2. **Type.** Michroma only for short display titles (window titles, big announcements, plaque
   names). Builder Sans for everything read: titles in Title case or sentence case, Bold, at
   least 4 px larger than the body under them; body Medium 15 to 16 px in `Colors.TextDim`,
   wrapped, never truncated. Capitals only for tiny labels (keycaps, tags, section labels).
   Numbers in RobotoMono. Minimum 14 px at 1280x720.
3. **Fit.** Every string must fit its box at 1280x720 and 667x375. If it does not, change the
   layout (move a tag under the title, let the row grow, shorten the copy), never cut it off.
4. **Text over the 3D world** (HUD, banners, kill feed) gets a thin dark `UIStroke`
   (Thickness 1.5, `Colors.Ink`, Transparency 0.35) instead of a box behind it where possible.
5. **Restraint.** One accent per element. No glow strokes, no gradients for decoration, no fake
   or meaningless text (no made-up serial numbers or status codes).
6. **Check it.** Render at 1280x720 and 667x375 and look at the image before calling it done.

## Type and gradient update (owner request, 4 November 2026)

The owner played the game and said the text was too small, hard to read and looked AI generated;
asked for bolder, slightly larger "polished digital game text", gradients on the selection
screens, and a slightly less sci-fi look. This update supersedes rule 2 and the "no gradients"
half of rule 5 above. Everything reads from `src/client/UI/Theme.luau`.

### Type rules (at 1280x720, design pixels)

- **Faces.** Builder Sans SemiBold or Bold for everything a player reads quickly. Nothing is set in
  Regular, Medium or Light: `Theme.Faces.Regular` and `.Medium` still exist as names but are drawn
  SemiBold, so old code cannot bring thin text back. Headings in ExtraBold or Heavy. Numbers,
  prices, timers and counts in RobotoMono Bold. Michroma (thin and wide) only for very large
  hero text (results headline, the match countdown, the owner's on-screen moment); never on window
  titles, section headings, chips, tags or the HUD.
- **Scale.** hero 48 (Michroma) and countdown 120; display 34 Heavy capitals (fighter names);
  title 26 ExtraBold capitals (window titles, short); heading 24 ExtraBold; subheading 20 Bold;
  strong 18 Bold (names in rows); body 18 SemiBold (line height 1.35); small 16 SemiBold;
  caption 15 SemiBold; label 16 Bold; overline 15 Bold capitals; button 18 Bold; number 18 mono
  Bold; mono 16 mono Bold. Floors: body 17 to 18, small labels 15 to 16, buttons 17 to 19 bold.
  Titles are always at least 6 px above the body under them. Tracking (hair spaces) is only for
  Michroma hero text; bold titles are plain capitals (`Theme.caps`).
- **Colour.** Reading text is `Colors.Text` or `Colors.TextDim` (196,206,220); `Colors.TextMuted`
  (158,170,188) is for tags only and still passes 7:1 on a panel. Text on a gradient card is
  `Colors.Text`.
- **Over the 3D world** (nameplates, prompts, banners, kill feed, the Showcase's "drag" hint):
  a dark `UIStroke` (`Theme.TextShadow`: 1.5 to 2 px, `Colors.Ink`) always, plus for the important
  lines a dark drop-shadow copy offset 1 to 2 px: `Components.dropShadow(label, offset, alpha)`.
  Use it only on labels that are not inside a list layout (put the label in its own holder).
- Touch targets stay 44 px; no text is clipped. When a larger size does not fit, change the
  layout, never the size back.

### Gradient rule (selection screens)

- Selection screens use **soft two-stop gradients** instead of flat fills, drawn by one helper:
  `Components.gradient(frame, colorA, colorB, rotation)` (sets the fill to white and keeps one
  `UIGradient` named `SNGradient`), and `Components.gradientFor(frame, a, b, state)` which mixes
  the two colours into the dark panel by `Theme.Gradient` (Rest 16 percent, Hover 24, Selected 32,
  Locked 8). Cards pass `Gradient = { a, b }` to `Components.surface`, `Components.card` and
  `Components.storeCard`, which then repaint it for every state.
- **What gets which colours.** Fighter cards and the Fighter Showcase header and stage: that
  fighter's `colors.primary` to `colors.secondary` from the Config. Play mode cards: the mode
  accent to the same accent darkened 55 percent. Arena choices: the arena colour. Shop cards:
  the category accent. A selected state is the same gradient brighter, **plus** the left bar
  (now 3 to 4 px, cyan).
- **Panels behind ordinary reading text stay solid** (`Colors.Panel`): windows, the dossier, the
  ability strip, tooltips, dialogue. The gradient tint is dark enough that `Colors.Text` keeps
  better than 7:1 on it.
- **Less sci-fi.** No tracked wide capitals, no glow strokes, no decorative corner marks on new
  work; colour comes from the fighter or the mode, not from cyan everywhere.

### Fighter Showcase (Fighters window)

- The preview is the fighter's own hall statue: `Statue_<PowerId>` in Workspace (built by
  `src/server/World/Statues.luau`; streaming is off, so it is always replicated). The window
  clones it, strips scripts and lights, stands it on the origin facing the camera and turns it
  slowly (about 15 degrees a second; drag turns it by hand). The camera is framed from the
  figure's height. If the hub has not replicated yet it retries for 8 seconds; only if the statue
  never appears does it fall back to the player's own character, then a plain stand-in.
- "What this fighter does": the role, the description, then one chip per ability with its key
  (slot number from the saved loadout, R for the ultimate, "+" when it is not on a key yet), the
  ability's plain description, and a looping top-down plan drawn from the ability's own numbers
  (range, radius, arc, width). The old "Show an ability" button played poses that need a rigged
  character and effects that spawn in Workspace; neither works for a statue inside a viewport,
  so it was replaced by the plan, which never depends on either.
