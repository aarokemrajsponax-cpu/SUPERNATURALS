# UI preview (offline screen renders)

Drives the real client interface in the stand-in engine, dumps the GUI tree as JSON, and draws
it to PNG with stand-in fonts (tools/fonts). It also flags text that overflows its box.
Run everything from the repo root.

```
S=<scratch dir>; export PATH=$S/tools:$PATH            # rojo, lune
rojo build default.project.json -o $S/build.rbxl
mkdir -p $S/ui

# Lobby, Play, settings, confirm, match, prompt, results, phone states
lune run tools/uipreview/dump.luau $S/build.rbxl $S/ui 1280x720      # or 667x375
# Selected states (Play, Fighters, Settings); Jeffery dialogue; shop tabs; icon sheet
lune run tools/uipreview/dump_sel.luau     $S/build.rbxl $S/ui 1280x720
lune run tools/uipreview/jeffery_dump.luau $S/build.rbxl $S/ui 1280x720
lune run tools/uipreview/shopdump.luau     $S/build.rbxl $S/ui 1280x720
lune run tools/uipreview/icons_dump.luau   $S/build.rbxl $S/ui 64 [name,name,...]

# Draw one or all of them
python3 tools/uipreview/render.py $S/ui/lobby_play.json $S/ui/lobby_play.png
for j in $S/ui/*.json; do python3 tools/uipreview/render.py $j ${j%.json}.png; done
```

Supported: Frames, UICorner, UIStroke (borders and Contextual text outlines), UIGradient fills,
GuiObject Rotation (about the centre, children turn with it, so the drawn icons are right),
list/grid layouts, AutomaticSize, TextScaled with UITextSizeConstraint, FontFace family and
weight (Builder Sans and Gotham as Montserrat, Michroma, Roboto Mono), and ViewportFrame
contents (opaque parts, camera, Ambient, LightColor, LightDirection) through tools/preview/render3d.py.

Not drawn: images (flat blue box), gradients on text and strokes, transparent or particle
content inside viewports, SurfaceGuis in viewports, emoji (a gold square). Text widths are
close to Roblox's, not exact; Builder Sans is drawn 6 percent narrower than Montserrat.
Red boxes mark text that overflows by this approximation, so check those against the game.
