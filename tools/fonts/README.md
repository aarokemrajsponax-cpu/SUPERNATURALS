# Render stand-in fonts

These fonts are used only by the offline preview renderers (`tools/preview`, `tools/uipreview`).
The game itself uses Roblox's own fonts. They are stand-ins so renders show the right letter
shapes and widths, not exact Roblox metrics.

| File | Stands in for | Licence |
| --- | --- | --- |
| `Montserrat[wght].ttf`, `Montserrat-Italic[wght].ttf` (variable, weight 100-900) | Builder Sans and Gotham | SIL Open Font License 1.1 |
| `Michroma-Regular.ttf` | Michroma | SIL Open Font License 1.1 |
| `RobotoMono[wght].ttf` (variable) | RobotoMono | SIL Open Font License 1.1 |

Any other family falls back to Montserrat Regular. The fonts are OFL licensed and may be
redistributed with this repository; they are never shipped in the game.
