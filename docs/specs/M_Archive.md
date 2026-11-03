# Task M — The Meridian Archive: the lore book and recovered files

The owner wants a book in the cozy Lounge where players "read and indulge in a super long yet
engaging story... mysterious... make players think... text looks good, readable, everything lined
up... make it look like a multi-million-dollar studio made it." The story is already written:
src/shared/Content/Archive.luau (read its header for the data format; do not rewrite the story
text; you may fix a typo). You build how it is read and found. L_Facility.md explains the world.

## Already there / being built
- Another agent is rebuilding the lobby as Meridian Station (src/server/World/Nexus.luau). It
  places:
  - a lectern in the Lounge with a ProximityPrompt carrying attribute
    Action = "Window:Archive";
  - 10 recovered-file objects tagged "SNLoreTerminal" with attribute LoreId = <file id>, each
    with a prompt carrying Action = "Lore:<file id>".

  WorldFxController routes those: "Window:Archive" opens the Shell window "Archive";
  "Lore:<id>" calls Remotes.ProgressRequest:FireServer("FindLore", id). Don't edit those files.
  If they aren't there yet when you test, create the prompts in your test setup.
- Profile (src/shared/Data/Schema.luau), DataService (get/update), CurrencyService (add),
  ProgressionService (handles ProgressRequest ClaimChallenge/Welcome), Protocol.ProgressAction,
  Shell/Components/Theme, Profile.luau on the client.

## You own
- src/server/Services/LoreService.luau handles ProgressAction "FindLore" (id) and "ReadLore"
  (documentId).
  - Validate everything: rate limit through AntiExploitService "Progress"; the id must be
    Archive.isFile(id); a tagged SNLoreTerminal with that LoreId must exist within 14 studs of
    the player's character root; the profile must be loaded.
  - On a first find: set profile.lore.found[id] = true and pay 25 Money. Finding all 10 also
    pays 100 Gems and a toast: "Every file recovered. The Archive is complete."
  - Send DataEvent.Toast "Recovered file added to the Archive: <title>".
  - ReadLore marks profile.lore.read[documentId] = true. That covers chapters and found files,
    with ids validated, and drives "new" badges.
  - Add LoreService to the Bootstrap ORDER after ProgressionService (one-line edit).
  - ProgressionService already handles other ProgressRequest actions. Make sure both services
    can listen without stepping on each other: each ignores actions that aren't its own.
- Protocol.ProgressAction: add FindLore = "FindLore" and ReadLore = "ReadLore". These are small
  additive edits.
- src/shared/Data/Schema.luau: add lore = { found = {}, read = {} } as an additive change with a
  default, repair/sanitise it (only known string ids, booleans), bump VERSION with a migration
  step if the schema requires it, and keep tests/Data.spec.luau and tests/data_test.luau passing.
- src/client/UI/ArchiveWindow.luau, the Shell window "Archive". It must feel like a beautiful
  physical book. Register it in src/client/Controllers/UIController.luau (one line).
  - **Desktop:** an open book spread. A leather cover edge, paper pages with a subtle gradient
    and a soft gutter shadow, page numbers, and a ribbon bookmark. Previous/next page arrows,
    plus keyboard (arrows, Q/E), gamepad (LB/RB) and swipe on touch. On phone (667x375) show a
    single page.
  - **Table of contents page:** the chapters, then a "Recovered Files" section. Found files show
    a "new" badge until read; unfound files show only their `hint` in faded italics, with a lock
    mark drawn from UI shapes (no emoji). Show progress "4 of 10 recovered".
  - **Typesetting by kind**, with fonts verified against Lune's Enum.Font (or Font.fromName),
    falling back to Builder Sans:
    - letter: a handwritten face (Kalam or PatrickHand) on cream paper;
    - journal: Merriweather on faintly lined paper with dated headings;
    - memo: typewriter (SpecialElite) on off-white, with a red "MERIDIAN INSTITUTE" stamp;
    - dossier: a file-folder look, Michroma/Jura headings, Merriweather body, a paperclip;
    - log: RobotoMono on a dark terminal panel (amber or green text) with scanlines;
    - transcript: speaker names in small caps, RobotoMono stage directions;
    - report: typewriter with a red classification stamp;
    - note: a handwritten face on a yellowed slip.
  - **Readability:** about 60-75 characters per line, comfortable line height, strong contrast,
    nothing touching page edges, and long documents flowing across pages. Measure with
    TextService:GetTextSize and split paragraphs onto pages, or use a scrolling page with a
    "continues" marker. Choose whichever looks best and stays aligned.
  - **Inline markup:** {{redacted}} becomes a solid black bar the width of the hidden words
    (RichText <mark> or overlaid frames), with the words themselves never readable. *italic*
    becomes <i>. Escape any other RichText characters.
  - **Figures:** implement EVERY entry in Archive.Figures in its style:
    - pencil: grey hand-drawn-looking strokes on paper, slightly irregular;
    - blueprint: white and cyan lines on a blue grid with tiny labels;
    - photo: a grainy composed image with a vignette, as a ViewportFrame scene or layered
      frames/gradients;
    - terminal: monospace art;
    - viewport: a slowly turning 3D crystal.

    Each sits in a frame with its caption below in small italics. They must look intentional
    and crafted, like illustrations in a real game's codex.
  - **Page turn:** a short, smooth animation (a page sliding/folding with a shadow) and a soft
    paper sound if a sound helper exists (otherwise silent). Opening the book gently blurs the
    world behind if the Shell supports it.
  - **Memory:** remember the last page per player (Settings or profile.lore.read). Send ReadLore
    when a document is first shown.
  - No emoji anywhere; drawn icons only (src/client/UI/Icons.luau if present, else simple
    shapes).
- tests/lore_test.luau (tests/smoke/World.luau):
  - FindLore with a junk id, an unknown id, too far away, and no tagged terminal: all refused.
  - Valid: found and paid once; a second find pays nothing.
  - All 10 found: the gems are paid once.
  - ReadLore: validated.
  - Persistence across leave and rejoin (see tests/data_test.luau).
- tests/smoke_archive.luau (tests/smoke/Client.luau):
  - Open the window and page through every chapter and every found file.
  - Every figure builds.
  - Redaction never shows the hidden words in any TextLabel.Text without the black-bar
    treatment. Assert the plain words aren't visible text.
  - The lock/hint state for unfound files.
  - auditLayout at 1280x720 and 667x375.
  - Keyboard/gamepad page turning.
  - No game-code errors.

Look at your pages: adapt the UI renderer in the scratchpad (preview/dump.luau + render.py; read
their headers) to draw the Archive window, and iterate until each page type looks like a real
book. Outputs under scratchpad/archive/. Follow CONVENTIONS.md and ART.md. Run: unit tests,
rojo build (build/archive.rbxl), place_check, smoke.luau, your two tests, data_test.luau,
integration.luau. Report real results and your render paths.
