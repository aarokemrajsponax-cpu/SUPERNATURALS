# Decisions, interpretations and resolved conflicts

Newest first within each group. "Pending" means the owner has been asked to confirm.

## Scope and process
1. **Deadline vs scope.** The 3 November directive asks for far more than one day of work.
   Work runs in batches in the directive's own priority order (release blockers first);
   `PROJECT_STATUS.md` says honestly what is finished and tested.
2. **P.S. 11.0 "focus only on regional pricing and the handoff"** applies to that task.
   The later sections (lounge, archive, facility layout, P.S. 17, P.S. 19) keep the rest of
   the directive in scope. Per P.S. 17.0 the most recent explicit instruction wins.
3. **Models (P.S. 14.0).** Most implementation runs on Sonnet agents with tight briefs; the
   lead session (Opus) does architecture, integration and review. At most four or five agents
   at once, never two on the same files.
4. **Usage meter.** The lead session cannot read `/usage`; the owner checks it and says when to
   stop at the 80% threshold.

## World and art
5. **Art direction** is now "The Facility" (`docs/ArtDirection.md` v3): a futuristic research
   complex. The eight statues and the Lantern stay as museum installations: this keeps the
   existing story canon (they predate the programmes).
6. **No grass or terrain ground indoors**; every area gets its own floor.
7. **Seasons.** Halloween content is retired for the year; the November calendar is the
   "Remember November" polar bear plus a Thanksgiving build-up (Thanksgiving 2026 is
   26 November: the fourth Thursday is computed, never hard-coded).
8. **Facility layout** (pending): proposed as an octagonal central hub with the statues and
   the Lantern, with wings for the battlegrounds and their spectator rooms, the Training
   Studio, Jeffery's Base, the Vault, the Spectating Lounge with the Master Shop behind it,
   Player Base Street and reserved expansion rooms. Built after the owner approves.
9. **The Vault's purpose** is unclear from the sketch (pending owner answer).
10. **Meme Vault** lives in the basement of each personal base, reached by a low-key luxury
    lift (owner note in 25.7).
11. **Reference images** are kept in the session scratchpad, not the repo, because most are
    screenshots of other studios' games. The roadmap's reference audit describes each one.

## Characters and fighters
12. **Jeffery** is the guide robot's only name (owner correction). Nameplate: JEFFERY.
13. **"Ninja" = The Ghost** (the katana fighter); pending confirmation.
14. **Premium "phases" = degrees** (pending). Corruption, Syntax and Admin phases 1–3 map to
    their degrees 1–3: each degree is a phase with its own kit, aura, idle, transformation and
    ultimate. No mid-fight paid escalation.
15. **Lobby rule.** Combat powers are disabled in the lobby on the server. They work in
    matches and in training (free trials of every power and degree) and for the owner in
    showcase mode.
16. **Degree pricing.** Selecting or switching to a higher degree costs in-game currency by
    tier, shown before confirming and charged only on confirmation. Premium fighters need a
    one-time Robux unlock *and* use their in-game selection price.

## Content and policy
17. **"Bomboclat Wallahi"** is built as an original reaction event under an original name. The
    phrase itself is not used: it combines a profanity with a religious oath, Roblox's text
    rules apply, and the owner asked that cultures never be the punchline.
18. **Verity and its variants** become an original smiley mascot with four moods under original
    names (the ARG characters belong to their creator). Same for the Wario/Waluigi parody
    (original names) and the sneaker mascot (no brand names). Music and choreography are
    original or licensed.
19. **Audio.** The lead session cannot listen to audio. Candidate ids are checked against
    Roblox's public asset information where possible; listening, permission checks and
    playback tests in Studio are owner tasks. Missing audio never breaks the game.
20. **AI for Jeffery.** First a curated knowledge base with searchable answers that works
    offline. An external AI provider is optional, off by default, and needs the owner's
    explicit decision (it costs money) and an API key in Roblox Secrets.
21. **Trading and gifting do not exist in the game.** Regional price levels are fetched on
    join and freshly before any future transfer through one server gate (`TransferPolicy`),
    with the owner's rules (same level to trade; sender ≥ recipient to gift). No trading
    system is added (P.S. 11.0 scope rule).
22. **Cross-server events** are tested with fakes here; live multi-server verification is an
    owner task in published servers.
23. **Refreshments** cost earned credits, work only in casual modes and training, never in
    ranked; no paid random rewards anywhere.
