# Task H — How to Play, interactive lessons, first-time guidance

Master prompt §22 (training and how-to-play), §31 (accessibility). Read master_prompt.md ~1171-1199.
The game now has Fighting System v2 (E_Combat.md: grab/throw, sweep, aerials, sprint strikes,
charged heavy, feint, directional dodges, stamina, knockdowns/tech, breakfall, lock-on, taunt),
seven powers with degrees and loadouts, interactive defense prompts (dodge/block prompts, timing
bars, grab mash escapes, Syntax redirects), ultimates, scoring, CPU practice, a training ground
with dummies, personal bases, a shop, progress and daily challenges.

## Already there
- Protocol.ProgressAction: StartLesson(lessonId), StopLesson, Welcome — Welcome is handled by
  ProgressionService (sets profile.tutorial.welcomed); StartLesson/StopLesson are not handled yet.
- profile.tutorial = { done = {[lessonId] = true}, welcomed }.
- Training ground (ArenaService: trainingSpawn, trainingDummySpots; DummyService dummies and a
  sparring CPU), MatchAction.Travel("Training").
- InputController.Bindings (labels/keys per device; the v2 agent added the new moves) and the
  HUD's control hint strip. Read the final control list from InputController and E_Combat.md.

## You own
- src/server/Services/TutorialService.luau — lessons that run in the training ground: each lesson
  has steps with a server-checked goal using real game events (CombatService:onHit with result
  tags, DefenseService:onResult, AbilityService:onUsed, CharacterService events, the fighter's
  state: e.g. "Block 3 hits" counts real Blocked outcomes against you from a lesson dummy that
  attacks on a slow, readable rhythm). StartLesson travels the player to the training ground if
  needed, spawns that player's own lesson dummy/CPU at a free spot (cleaned up on stop, finish,
  leave, death, joining a queue), sends step progress, and on finishing marks
  tutorial.done[lessonId] and pays a one-time reward (Money; a few Gems for the full set) through
  CurrencyService — once per lesson, server-decided. Lessons (keep each short, 3-5 steps):
  Moving & stamina (sprint, dodge in each direction), Striking (light string, charged heavy,
  launcher), Defending (block, parry, perfect dodge), Grappling (grab, throw into a wall, throw
  tech), Getting up (sweep someone, tech roll, breakfall), Prompts (dodge/block prompt, a timing
  bar, a grab mash escape), Your power (use each equipped ability once, then the ultimate:
  charge is boosted during the lesson), Scoring & winning (explains points; ends with a 1-minute
  CPU practice). Add to Bootstrap ORDER after ProgressionService (one-line edit allowed).
  Handle ProgressAction StartLesson/StopLesson (validate ids, rate limit "Progress").
- src/shared/Config/Lessons.luau — lesson definitions (ids, names, short text per step, goals,
  rewards) shared with the client.
- src/client/UI/LearnWindow.luau — Shell window "Learn" (How to Play): sections Controls (the
  real bindings for the current device, generated from InputController.Bindings: keyboard,
  gamepad and touch tabs; clear key caps drawn as boxes, not emoji), Combat basics (short
  illustrated cards: the rock-paper-scissors of strikes beat grabs beat blocks beat strikes,
  counters and punishes, stamina, knockdowns), Defense prompts (how each prompt looks and which
  input answers it on each device), Powers & degrees & loadouts, Scoring, Your base, and a
  Lessons list (status done/not done, reward, Start button). Revisit any time.
- src/client/Controllers/TutorialController.luau — the in-world lesson HUD: a compact objective
  card (step text, progress "2 / 3", the relevant key cap for the current device), a subtle
  world marker over the lesson dummy, step-complete feedback, lesson-complete card with the
  reward, Stop button. Also the first-time Welcome card for new players (profile.tutorial.welcomed
  false): short, friendly, three choices: Quick lessons, Jump into the Battle Gate, Explore; and
  low-key guidance: a soft arrow/marker toward the Training Hall gate for players with no lessons
  done (dismissable, never blocking). Add to the client Bootstrap ORDER (one line). Register the
  Learn window in UIController (one line).
- tests/tutorial_test.luau (World.luau): every lesson starts, its dummy spawns, each goal counts
  only the real event (junk requests or client claims can't complete it), finishing pays once,
  stopping/leaving/queueing/dying cleans up, two players in lessons at once don't interfere.
- tests/smoke_learn.luau (Client.luau): Learn window every section and device tab, lesson HUD
  through a fake lesson (step events), welcome card choices, auditLayout at 1280x720 and 667x375.

Copy must sound like a real game written by people: plain, specific, friendly, short. Example:
"Grabs beat blocks. If someone turtles behind their guard, walk up and press G." No em dashes,
no emoji, at most one exclamation mark per screen. Follow CONVENTIONS.md and ART.md.
Run: unit tests, rojo build (own output), place_check, smoke.luau, your two tests,
integration.luau. Report real results.

## Owner's latest priority (overrides anything above that conflicts)
"When the player spawns in they can get a grasp of the game within a few minutes: low-key brief
quick guides and trails telling them what to do, or a tutorial for each power and degree.
Players understanding the concept is a big priority." So, on top of the lessons above:
- First Steps path for new players (and anyone with it unfinished): a short checklist of 4-5
  steps shown as a small, tidy card (Hit a training dummy -> Block and dodge -> Pick a power ->
  Win a CPU practice fight -> Visit your home), each with a small reward, server-checked. The
  current step draws a guide trail on the ground from the player to where it happens (an
  animated Beam/arrow path that follows the walkable route through the Nexus to the right gate,
  fading near the goal), plus a soft marker at the destination. Never blocks play; can be hidden
  in Settings; ends once done.
- Power Trials: one short guided lesson per power AND per degree, generated from the power
  definitions (src/shared/Powers/*: abilityOrder, degrees[n].abilities, names, descriptions,
  resource, ultimate, defense identity), so all eight powers and every degree are covered without
  hand-writing each. In the training ground against a lesson dummy: one step per ability ("Press 2:
  Quake Stomp. It hits everyone around you, so use it when they crowd you."), then the power's
  defense identity, then the ultimate (charge boosted). Starting a trial temporarily equips that
  power and degree as a trial (PowerService trial rules: premium powers are trial-only, never in
  PvP; the player's real selection is restored after). Reachable from the Powers window ("Try a
  lesson" on each power/degree) and the Learn window. Rewards once per power/degree, small.
- Contextual one-time tips (tiny toasts, each shown once, server remembers in tutorial.done):
  first time grabbed (how to escape on this device), first timing bar, first time stamina runs
  out, first knockdown (tech roll), first time in a match (how scoring works), first visit home
  (how to edit). Short, specific, device-aware key caps.

## Round 3: setting names
The world is now Meridian Station (ART.md "Setting"; L_Facility.md). Use its names in guidance:
the Garden (lobby), TEST CHAMBERS (Battle gate), TRAINING WING, RESIDENTIAL WING (Homes),
COMMISSARY (Market), OBSERVATION DECK (Watch), the Lounge and the Archive book. The First Steps
path can end with "Read the first page of the Archive in the Lounge".

## Round 4 addendum: research-informed onboarding (overrides anything above that conflicts)
Read /home/user/SUPERNATURALS/docs/DesignResearch.md (sections 1, 2, 4, 5, 6) and
/home/user/SUPERNATURALS/docs/ArtDirection.md (the world is now the Hall of the Eight: an
ancient imperial hall restored by the Meridian Institute; the interface is the "imperial codex"
style). The owner: "the first moments should make players think: this looks beautiful, I
understand what I can do, I want to see what happens next... teach players what they need when
they need it... never force experienced players through tutorials."
- The first minute:
  - The arrival is framed on the Lantern and the statues (the interface agent builds the intro
    glide).
  - Then ONE objective card: "Find the Training Wing" with the guide trail. The trail follows the
    bronze meridian inlay; use the lobby's floor guide lines if present.
  - A training dummy fight follows within the first 60-90 seconds. Use the Training Hall's dummy,
    with a lesson-style hint for M1 / E / F / Q shown only as they become relevant.
  - Then "Pick a power" in the Calibration Chamber (Action "Window:Powers").
  - Then "Win a CPU practice fight".
  - Then "Read the first page of the Archive".
- Contextual tips (one at a time, never during active combat, queued until safe, each once per
  account, server-remembered):
  - first grab suffered, first timing bar, first stamina-out, first knockdown, first match,
    first win, first premium-power card viewed
  - device-aware key caps
- Veterans: if the profile shows 3+ matches, skip First Steps automatically, with a "Show guide
  again" toggle in Settings.
- Training readouts: in the Training Wing, a damage readout over the dummy (last hit, combo
  count, DPS over 5 s) and a cooldown display for practice. These are real numbers from server
  hit events.
- Measure with guarded AnalyticsService funnel steps (joined, first objective, first fight,
  first win, first power chosen). Diagnostics only.
