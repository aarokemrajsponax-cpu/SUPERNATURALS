# Task F — After the fight: victory scene, results, rewards, replay, spectating, rematch

Master prompt §17 (scoring), §18 (after the fight, spectators), §19 (replay and highlights),
§27 (victory presentations). Read them (master_prompt.md lines ~1002-1068 and ~1282-1299).

## Already there (read the parts you need; don't rewrite them)
- src/server/Services/MatchService.luau: matches, phases (Countdown/Active/SuddenDeath/Results/
  Ended), MatchEvent kinds (Protocol.MatchEvent: State, Notice, Results, Ended, Matches,
  Spectating, Highlight, Rematch, ...). New and already working on the server:
  MatchService:onStarted(fn(match)), :onFinished(fn(match, result)), :getMatch(id),
  :getMatchOf(fighter); match.fightStartedAt, match.spectators, match.predictions, match.rematch.
  Requests: MatchAction.Rematch (vote during Results; everyone votes -> same mode, same players,
  new match), ListMatches (-> MatchEvent.Matches list {id, mode, arena, phase, names, watchers}),
  Spectate(matchId) (-> MatchEvent.Spectating {matchId, fighters (Models), mode} or nil when it
  stops), StopSpectating, Predict(matchId, fighterId) (free, before 20 s of fight; correct = small
  Money reward). Spectators receive the same State/Notice/Results broadcasts as fighters.
- src/server/Services/ProgressionService.luau: after every match each player gets
  DataEvent.Reward { money, gems, xp, lines = { {label, money?, gems?, xp?} }, note, power,
  powerName, level, levelUp, won } (Profile.rewarded signal on the client). Also daily challenges,
  login streak (toasts), predictions. Rewards config: src/shared/Config/Rewards.luau; pure math:
  src/shared/Progression/RewardMath.luau.
- CombatService:onHit(fn(attacker, target, outcome, hit)), AbilityService:onUsed(fn(fighter,
  abilityId, def, basic)), DefenseService:onResult(fn(fighter, kind, result)),
  CharacterService:onKnockout(fn(victim, credited?)).
- Client: src/client/UI/MatchHud.luau (countdown, timer, scoreboard, kill feed, a results panel),
  Shell windows (src/client/UI/Shell.luau registerWindow/open/close/toast/confirm/setMode:
  "Cinematic" and "Spectate" modes exist), Components, Theme, Profile (Profile.rewarded),
  Effects/Vfx.luau, Effects/Poser.luau (Poser.register/play/hold/release; another agent is adding
  keyframed sequences Poser.registerSequence/Poser.sequence — use them if present, fall back to
  play/hold), CameraController.luau (owned by the combat agent: lock-on; it PAUSES whenever
  workspace.CurrentCamera.CameraType is Scriptable, so take the camera by setting Scriptable and
  give it back by restoring Custom and the humanoid subject).
- Cosmetics: another agent builds the shop and src/shared/Config/Cosmetics.luau with slot
  "victory" (victory poses) and "knockout" (elimination effects). Equipped ids are in the profile
  (cosmetics.equipped.victory / .knockout, visible in Profile.get()). Contract for you:
  Cosmetics.Victory[id] = { name, pose = string (a Poser sequence or pose name), fx = string? }
  and Cosmetics.Knockout[id] = { name, fx = string }. If the module or entry is missing, use
  your own built-in default presentation (you define at least 4 distinct defaults: one per
  power family, chosen by the winner's power when nothing is equipped).

## You own (create/edit only these, plus additive Engine shims)
- src/server/Services/ReplayService.luau — bounded recording for each running match: fighter root
  CFrames at 10 Hz in a ring buffer for the last Config.Replay.Seconds (~12 s), plus key events
  (hits with result tags, knockouts with credit, abilities used, defenses Perfect/Good/Escaped,
  score changes), all with server times. When a match finishes: send MatchEvent.Highlight to its
  participants and spectators: { duration, fighters = { {id, name, model, power, color} }, frames
  = compact arrays, events = { {t, kind, a, b, text} } } kept small (cap frames and events; never
  include anything spectators shouldn't see, e.g. a Concealed Ghost's exact position while
  concealed: drop those frames or mark them hidden). Free everything on match cleanup. Also build
  a chronological match summary (key events) included with the highlight. Add to Bootstrap ORDER
  after ProgressionService (one-line edit allowed).
- src/shared/Config/Replay.luau — recording rates/limits.
- src/client/Controllers/ResultsController.luau — the victory presentation and results flow when a
  match ends (MatchEvent.Results + Profile.rewarded + MatchEvent.Highlight):
  1. Victory scene (3-5 s, skippable): Shell.setMode("Cinematic"), scripted camera orbit/push-in
     on the winner, the winner's victory pose (equipped or per-power default), confetti/light
     shafts/power-coloured effects, the winner's name in a clean title card. Draws work for
     everyone in the match and for spectators. Draws, ties and forfeits get their own wording.
  2. Results panel (Shell window or MatchHud panel — make it beautiful): placement list with
     scores, knockouts/deaths, damage, a short summary, the reward breakdown (Reward lines
     animated in, Money/Gems/XP counters, mastery bar for the power used with level-up moment),
     buttons: Rematch (shows votes "1 of 2"), Watch final moments (plays the replay), Back to lobby.
  3. Replay viewer: plays the Highlight frames with ghost copies of the fighters (simple
     part-built mannequins or clones without scripts, power-coloured), a cinematic camera that
     follows the action, a timeline with event markers (hits, knockouts), pause/scrub/exit, and the
     key-event list. Clearly labelled "Replay" (it's a reconstruction, not a video).
  Add to src/client/Bootstrap.client.luau ORDER (one-line edit allowed).
- src/client/UI/WatchWindow.luau — Shell window "Watch" (opened by the Nexus Watch gate:
  Window:Watch): list live matches (ListMatches; refresh button and auto refresh while open),
  each with mode, arena, names, phase, watchers; Watch button -> Spectate. While spectating:
  Shell.setMode("Spectate"), a spectator bar (who you're watching, switch player left/right,
  free camera toggle, Exit button that's always visible), the scoreboard, and a free prediction
  card before the cut-off ("Who wins?" with each fighter; no stakes, small reward if right).
  Spectator camera: follow the selected fighter smoothly, switch targets, never reveal concealed
  fighters (respect their transparency; don't follow a concealed fighter's exact position:
  hold the camera on the last visible spot). Register it in src/client/Controllers/UIController.luau
  (one line next to the other register calls) and handle the Spectating/Matches events.
- src/client/UI/ResultsWindow.luau (if you split the results panel out of MatchHud) and edits to
  src/client/UI/MatchHud.luau's results part (keep its countdown/timer/scoreboard/kill-feed
  behaviour and its smoke checks working).
- tests/match_test.luau — end-to-end with tests/smoke/World.luau: a duel ends -> both players get
  DataEvent.Reward with plausible amounts (winner more than loser; participation for the loser),
  stats updated (wins/losses/matches), mastery XP added to the power used; a 3-second "fight"
  pays the reduced anti-farm amount; a fifth duel vs the same opponent pays less; daily challenge
  progress counts and ClaimChallenge pays once (second claim refused, unfinished refused);
  login streak rolls on a new day (fake os.time via the DataStore fake or by editing
  profile.daily.day); spectate a running match (Spectating event, broadcasts reach the spectator,
  StopSpectating, spectator leaving); predictions (only before cut-off, correct pays, wrong
  doesn't, can't predict twice); rematch (both vote -> new match with same players; one vote ->
  nothing); Highlight sent at the end with bounded frames/events and nothing left recorded after
  cleanup; concealed frames hidden.
- tests/smoke_results.luau — client smoke (tests/smoke/Client.luau helpers): fire Results +
  Reward + Highlight events and run the victory scene, results panel (press every button),
  replay viewer (play, pause, scrub, exit), Watch window (list, watch, switch, predict, exit) at
  1280x720 and 667x375; auditLayout everything; no game-code errors.

Follow CONVENTIONS.md and ART.md (beautiful, natural, human-made; no emoji; copy that sounds like
a real game). Run: unit tests, rojo build (own output), place_check, smoke.luau, your two tests,
integration.luau. Report real results.

## Round 4 addendum: the owner's top priorities (overrides anything above that conflicts)
Read /home/user/SUPERNATURALS/docs/DesignResearch.md (sections 3, 6, 9, 10) and
/home/user/SUPERNATURALS/docs/ArtDirection.md (the Sanctum style; section 6 for the interface).
The owner: "Make the replay system a genuinely premium feature... smooth playback... clear
controls, accurate timeline, pause, resume, seeking... cinematic framing... highlight moments...
optional slow motion... clear round summaries... attractive thumbnails and well-organized
browsing... graceful handling of missing recordings... never show fake controls that do
nothing." And: "After a defeat, respond constructively... never shame... offer genuinely helpful
feedback where the data supports it, never fabricate analysis."

### Results
- The victory scene stays as specified.
- The results screen shows real match stats per player. Record them in ReplayService or
  ProgressionService tracking (the onHit/onUsed/onResult hooks already exist):
  - damage dealt and taken, hits landed, longest combo
  - blocks, parries, perfect defenses
  - grabs landed and suffered, knockouts and deaths
  - ultimate uses
- One factual tip chosen by rules from those numbers. For example, most damage taken came from
  grabs gives "Grabs beat blocking. Dodge them or strike first." Few perfect defenses on
  timing bars gives "Press right as the marker reaches the centre." If no rule fits, show no
  tip.
- Next actions:
  - Rematch, with the vote count.
  - Watch the final moments, which is the replay.
  - Practise vs CPU, which pre-selects the opponent's power if it was a CPU.
  - Back to the Lounge.
- Defeat copy is warm, short and never condescending. Never shame, never pressure, and add no
  timers urging another match.

### The replay viewer
- **Buffer:** server-recorded root CFrames at 10 Hz plus key events, about the last 15 s, sent
  as the Highlight.
- **Reconstruction:** stand-in fighters cloned from each fighter's current character (strip
  scripts; anchored; driven by interpolated frames) with their power colours, and the event
  effects replayed through the existing client effect code where safe (hit sparks, knockout
  burst).
- **Cameras:** a cinematic follow (auto-chosen subject, smooth), an orbit, a top-down tactical
  view, and a KO cam (a slow-motion push-in at each knockout). Cycle with C, LB/RB or a button.
- **Playback controls:** play/pause (Space), seek by dragging the timeline, ±2 s jumps, speeds
  0.25x/0.5x/1x/2x, and "Next highlight" (jumps to the next knockout or big hit).
- **Timeline:** markers for hits, knockouts and ultimates, with tooltips.
- **Summary:** a side panel with the round summary.
- **Exit:** Esc/B or the button returns you exactly where you were.
- **Labelling:** the viewer says "Replay (reconstruction)".
- **Browsing:** keep the last 5 highlights of this session in client memory. The Watch window
  gets a "Your replays" tab, with a thumbnail of each one's knockout moment (a ViewportFrame
  snapshot of the stand-ins), the date, the mode and the result. Say plainly in the UI that
  replays last for this session.
- **Missing data** gives a clear empty state, never fake controls.
- **Budget:** cap frames and events, keep memory small, and free everything on exit.

### Feature discovery
- After a player's first completed match, show one small, dismissible hint pointing at "Watch the
  final moments". Show it once, remembered via profile.tutorial.done.
- No other promotional interruptions.
