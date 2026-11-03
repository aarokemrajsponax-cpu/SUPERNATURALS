# Task Q — Anomalies: the brainrot and trend system

The owner: "Bring internet culture and brainrot into the game... a real game system: rotating
memes, viral-inspired encounters, temporary effects, event content, humorous NPCs, emotes,
cosmetics, unusual abilities, surprises... funny, unexpected, memorable... keep the main game
recognizable... an owner-controlled trend and event system... expandable so I can introduce the
next trend without rebuilding the game... only use assets we have rights to: original
recreations, no copyrighted songs, ripped videos, unlicensed characters."

## Research done (Oct 2026), use it
- "Verity": a Minecraft horror ARG/web series by YouTuber ThatMob (first episode May 2026) about
  a smiley-face personal assistant that turns evil. A fan song, "It's Me, It's Verity" by
  Horror Skunx (July 2026), went viral with endless remixes; variants like "Falsity". Peak
  meme activity was Aug-Sep 2026.
  - Both the character and the song belong to their creators: DON'T use the name, the design or
    the song.
  - DO make an original homage that fits our lore. WARDEN, our station AI, gets a malfunction:
    "ASSISTANT MODE". It switches to a relentlessly cheerful smiley-face persona on every
    screen, says upbeat helper lines that slowly go wrong, and its smiley face appears in odd
    places (a smiley pattern in the grass, on a drone, behind you in a mirror).
- "Bomboclat Wallahi": a comedy skit clip (ethnic and religious subject matter, plus a Jamaican
  Patois profanity). It is NOT appropriate for a Roblox audience and would trip moderation. Don't
  use it. No track by "TR3N TR3N" with that name was found.
- The Italian Brainrot wave (Tralalero Tralala, Bombardiro Crocodilo...) and "Steal a
  Brainrot" still dominate Roblox brainrot. Those characters have murky ownership claims: don't
  copy them.
  - DO capture the formula in ORIGINAL creatures: absurd hybrid objects and animals with
    confident sing-song names, deadpan presentation and a short catchphrase.

## Lore fit
Brainrot fits the story perfectly: the Lantern makes echoes of what it hears, and the station
has been listening to the internet since AJKR plugged it back in. So "ANOMALIES" are echoes that
came out wrong: the Lantern's misunderstandings of human memes. WARDEN logs them deadpan
("ANOMALY 017: a shark wearing sneakers. It is singing. I did not ask it to.").
This keeps the main game's identity: anomalies are framed, catalogued and contained by the
station, never random clip-art.

## Build (you own these)
- **src/shared/Config/Anomalies.luau**, the content framework, all data:
  - **Anomalies:** each has id, name, catchphrase, rarity (Common, Uncommon, Rare, Mythic), a
    model recipe (part-built: body parts, colours, accessories, idle bob/spin/waddle style), a
    voice line (TextChatService bubble or an on-screen subtitle; no audio unless an
    rbxasset/permitted id exists), behaviour (wander, follow the nearest player, flee, dance,
    sing, multiply), a reward when caught or "documented", and a WARDEN log line.
  - Ship 14+ original anomalies, all funny and memorable. Examples to refine:
    - Sharkini Sneakerini (a shark in sneakers that moonwalks away)
    - Toastmaster Supreme (a toaster that launches toast at people's heads, harmlessly)
    - Capybara Lattebara (a capybara balancing a latte, unbothered)
    - Brick Floppa (a brick with cat ears, staring)
    - Mr. Wobbles (a jelly cube that copies your emotes)
    - Goose of Infinite Paperwork (a goose that steals your hat and files it)
    - Fridge Rizz (a fridge whose door opens to reveal a tiny disco)
    - Grandpa Pixel (a low-poly old man who only says "back in my day we had 8 bits")
    - Bananaphone Bandit (a banana on a phone call it won't end)
    - Sir Mops-a-Lot (a mop knight)
    - Lil' Lantern (a tiny crystal with a face who thinks it's the real Lantern)
    - Cubey (a smiley cube that is WARDEN's Assistant Mode mascot)
  - **Events (trends):** each has id, name, theme colours, duration, a spawn table of which
    anomalies appear and how often, Garden modifiers (screens, music cue, colour grade tweak,
    decorations), an emote unlock, a title unlock, a limited collection, and community goals
    (catch N anomalies server-wide together: a server-wide progress bar with a reward for all).
    Ship 3 events:
    - **ASSISTANT MODE:** the WARDEN smiley homage.
    - **THE GREAT NONSENSE:** an absurd-hybrid creature outbreak.
    - **VIBE CHECK:** a dance-off where anomalies judge your emotes.
  - **Emotes:** 8 original emotes (Poser sequences, if registerSequence exists, otherwise
    poses): the Lattebara Sip, the Sneaker Moonwalk, the Wobble, the Paperwork Shuffle, the
    Brick Stare, the Floss-adjacent "Calibration Wave", the Victory Toast, and a "WARDEN, Are You
    Okay" shrug. Unlockable from events, collections or the season pass.
  - **Titles** and collectible cosmetics from anomalies (hats/badges built from parts).
- **src/server/Services/AnomalyService.luau** (add it to the Bootstrap ORDER):
  - Spawns anomalies in the Garden only, never in arenas or matches. Use a rare ambient spawn
    rate (a few per hour per server, tunable), with more during an active event.
  - Players "document" (catch) one by walking up and using its ProximityPrompt ("Document"),
    with a short fun reaction. The first catch of each kind adds it to their Anomaly Codex
    (profile.anomalies, additive Schema with sanitise) and pays a small reward. Rarity drives
    the reward and the spawn chance.
  - Anomalies despawn after a while; everything is cleaned up; spawns are capped.
  - Events are scheduled by the owner (start, stop, schedule with start/end times, intensity,
    spawn multiplier, reward multiplier) through a small API OwnerService can call:
    AnomalyService:startEvent(id, opts), :stopEvent(), :status(), :setAmbient(rate). Add those
    actions to the owner panel's Live ops section (or document them for the owner-panel agent if
    it's not your file).
  - Config can mark an event "auto" with a date range so the next trend ships as data only.
  - Server validates everything (prompt distance, cooldowns, no farming: one catch per anomaly
    instance per player).
- **src/client/Controllers/AnomalyController.luau** and **src/client/UI/AnomalyCodexWindow.luau**:
  - The models' idle motion and catchphrase bubbles, the catch reaction, the event's Garden
    modifiers (fully reverted after).
  - The Codex window: a grid of silhouettes for undiscovered entries and full cards for found
    ones (name, catchphrase, rarity, WARDEN log line, model preview in a ViewportFrame).
  - Emote wheel integration: if an emote menu exists, add to it; otherwise build a small emote
    wheel bound to B / DPad and a touch button.
  - Designed per ART.md (the Codex looks like a WARDEN containment database, not clip-art).
- **Tests:**
  - tests/anomaly_test.luau: spawns capped and Garden-only; catch validation (distance, one per
    instance); rewards once; event start/stop/schedule and auto date range; cleanup; the
    community goal pays everyone once; persistence; junk requests.
  - tests/smoke_anomalies.luau: every anomaly model builds and animates; Codex states;
    auditLayout at 1280x720 and 667x375.
- **Render** every anomaly in a row with the preview renderer (`setup` scene). They should look
  charming and well-made, readable silhouettes, not lumps.

Follow CONVENTIONS.md and ART.md. Keep it tasteful and kid-appropriate: no profanity, no real
people, no ethnic or religious jokes, no copyrighted characters, songs or logos.
Run: unit tests, rojo build (build/anomaly.rbxl), place_check, smoke.luau, your two tests,
data_test.luau, integration.luau. Report real results and render paths.
