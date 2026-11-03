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
8. **Facility layout** (owner answer, 3 Nov): a blend of the proposal (octagonal central hub
   with the statues and the Lantern) and the generated blueprint, with touches of the sketch.
   Wings: a Battlegrounds concourse with about **20 battleground chambers** (servers are big;
   each chamber has an environment theme and its own spectator gallery), the Training Studio,
   Jeffery's Base, the Spectating Lounge with the Master Shop behind it, Player Base Street
   and reserved expansion rooms. Chambers are built on demand and streamed, so 20 stay cheap.
9. **The Vault is per player**, in the basement of each personal base (owner answer): mostly
   a trophy and collection vault (achievements, mastery, titles, cosmetics), a small secret
   lore section unlocked by discoveries, and a premium-fighter display. AJKR's own vault also
   holds the Owner Control Center. The Meme Vault archive shares the basement, reached by a
   low-key luxury lift (owner note in 25.7).
11. **Reference images** are kept in the session scratchpad, not the repo, because most are
    screenshots of other studios' games. The roadmap's reference audit describes each one.

## Characters and fighters
12. **Jeffery** is the guide robot's only name (owner correction). Nameplate: JEFFERY.
13. **"Ninja" = The Ghost** (the katana fighter); confirmed by the owner.
14. **Phases transform during a match** (owner answer, 3 Nov), for every fighter. A power's
    degrees are its phases. Every match starts in Phase 1; a player who has unlocked a higher
    degree can evolve mid-fight once the Phase meter (earned through combat) is full, paying
    that phase's fee in Money (earned currency, never Gems or Robux). Fees are shown before
    confirming, charged only on the transformation, and last for that match. Training: free
    and instant. Owner: free. Premium fighters also need their one-time Robux unlock. This
    replaces the earlier "pay once when switching degree before a match" design and satisfies
    section 14 (exact price, temporary, affordability shown, charged only on confirm).
15. **Lobby rule.** Combat powers are disabled in the lobby on the server. They work in
    matches and in training (free trials of every power and degree) and for the owner in
    showcase mode.
16. **Degree pricing** is the phase fee in item 14. Before a match the player chooses fighter
    and loadout; each phase's fee, unlock state and affordability are shown there and in the
    showcase.

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
24. **Interface craft pass (owner, 3 Nov: "looks too AI generated").** Rules in
    `docs/specs/UI_Craft_Pass.md`: solid surfaces where text sits over interface, one outer
    edge with a light top lip, tight 4 px corners, no outlines on cards inside windows, Title
    or sentence case for titles and copy (capitals only for tiny labels), nothing truncated,
    thin dark outlines on text over the 3D world instead of boxes.
25. **Hub doors are numbered 01 to 08** on their signs (round the hall from the entrance),
    as facility wayfinding. The sealed door beside the Training Studio is 09, which gives the
    Archive's door 09 note its meaning. Sign names use one size; long names wrap.
26. **Statue plaques** read like museum plaques: the codename spaced between two fine rules
    in the power's colour, a small first word ("THE", "ANIMAL") above long names, the name
    engraved, rivets in the corners.
27. **No Robux amount in player-facing text** except where the live, regional price from
    Roblox is shown. Config keeps the intended Creator Hub prices for the owner's handoff.
