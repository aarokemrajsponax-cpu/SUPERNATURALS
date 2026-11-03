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
