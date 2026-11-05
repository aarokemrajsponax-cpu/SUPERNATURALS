# What makes this game worth returning to: research and the decisions it drives

A short, honest summary of the evidence behind SUPERNATURALS' onboarding, feedback, results,
replays and retention design. Established findings are marked **[evidence]**, widely used
design practice **[practice]**, and our own hypotheses **[hypothesis]**. Every point ends with
what we actually build.

## 1. Competence, autonomy and relatedness predict enjoyment and returning
**[evidence]** Ryan, Rigby & Przybylski (2006), *The motivational pull of video games: A
self-determination theory approach* (Motivation and Emotion 30(4); DOI 10.1007/s11031-006-9051-8):
across four studies, players' sense of competence, autonomy and relatedness each independently
predicted enjoyment and intention to keep playing. Intuitive controls were linked to competence
and autonomy, and relatedness mattered most in multiplayer play.
**We build:**
- **Competence:** clear hit confirmation, graded defense results (Perfect/Good), lessons that end
  in a win, mastery levels per power, and a results screen that names what went well.
- **Autonomy:** eight distinct powers, loadouts, a degree choice, optional lessons, skippable
  intros, and guidance you can hide.
- **Relatedness:** the Lounge as a social space, rematch voting, spectating with free
  predictions, shared Admin Abuse moments and community goals.

## 2. Flow needs clear goals, immediate feedback and challenge matched to skill
**[evidence]** Csikszentmihalyi (1990), *Flow*; Sweetser & Wyeth (2005), *GameFlow: a model for
evaluating player enjoyment in games* (Computers in Entertainment 3(3)); Chen (2007), *Flow in
games* (Communications of the ACM 50(4)).
**We build:**
- A CPU with Easy, Normal and Hard levels, recommended by the player's record.
- One clear next objective at a time (the First Steps card).
- Combat states that always end, with readable telegraphs, so losses feel learnable.
- Anti-frustration: no ground loops and combo damage scaling.

## 3. Feedback ("juice") helps, up to a point
**[evidence]** Kao (2020), *The effects of juiciness in an action RPG* (Entertainment Computing
34). Four versions of the same game differed only in audiovisual feedback (none, medium, high,
extreme). Medium and high beat both none and extreme on player experience, motivation, playtime
and performance. Hicks et al. (2018, DiGRA; 2019, CHI PLAY) and Swink (2008), *Game Feel*,
describe how juicy feedback works. Kao and colleagues (CHI 2024) found that legible
action-to-outcome links and graded success drive the benefit.
**We build:**
- Hitstop (40-90 ms) and camera kick scaled to impact, layered hit sounds with pitch variation,
  and distinct feedback per result (hit, block, parry, counter, wall splat, clash).
- The big effects are reserved for ultimates and finishers.
- Effects, shake and flashes are capped by default. Settings for camera shake, reduced effects
  and intense effects cover the rest.
- The rule: every effect must make the cause and the outcome clearer. Extreme spectacle on every
  hit is explicitly avoided.

## 4. Tutorials pay off in complex games, and help works best when it's timely
**[evidence]** Andersen et al. (2012), *The impact of tutorials on games of varying complexity*
(CHI 2012; over 45,000 players, three games). Tutorials raised play time by up to 29% in the
most complex game, and did not significantly help in simpler games whose mechanics can be
discovered by experimenting.
**[practice]** Just-in-time, contextual teaching, with help available on demand, is the standard
recommendation in games UX (Hodent, 2017, *The Gamer's Brain*).
**We build:** our game is complex (8 powers, defense prompts, grabs, stamina), so it gets
guidance, but delivered just in time:
- a 4-5 step First Steps card with a guide trail;
- one-time contextual tips, for example the first grab, the first timing bar, or running out of
  stamina, each shown once and remembered by the server;
- optional lessons per power and degree;
- a Learn window to revisit anything;
- nothing mandatory beyond a skippable welcome.

## 5. Curiosity comes from information gaps
**[evidence]** Loewenstein (1994), *The psychology of curiosity* (Psychological Bulletin 116(1)):
curiosity arises when people notice a gap between what they know and what they want to know.
**We build:**
- The Archive's unanswered questions: Door 09, the statues that predate the programmes, the
  groundskeeper.
- Ten hidden recovered files with hints.
- Secret rooms, and anomalies to document.
- Statue inscriptions in an unknown script.
- Landmarks visible from the spawn that invite walking over.

## 6. Cognitive load: attention is limited, so prioritise per moment
**[evidence]** Sweller (1988), *Cognitive load during problem solving* (Cognitive Science 12(2)),
and the wider cognitive load literature: extraneous information competes for the limited
working memory needed for the task.
**[myth to ignore]** The "humans have an 8-second attention span, less than a goldfish" claim
traces to a 2015 marketing report and is not supported by research. We don't design for a
mythical 3-second attention span; we design for a clear first minute.
**We build** a per-context attention budget:
- **Combat:** health, stamina, cooldowns and telegraphs only. Toasts and tips are queued until
  out of combat.
- **Exploration:** the world first, with at most one small objective card.
- **Results:** the outcome and rewards first; details on demand.
- **Shop:** item, price and what you get, nothing else animated.

Notifications are rate-limited, and a tip never repeats once dismissed.

## 7. Social play
**[evidence]** Relatedness predicts enjoyment in multiplayer contexts (Ryan, Rigby & Przybylski
2006, study 4).
**[practice]** Shared spectacle and low-stakes social activities create moments players share.
**We build:**
- Lounge seating and emote spots, and leaderboards in the world.
- Spectating with free predictions (no stakes) and rematches.
- Server-wide events with community goals.
- Visible cosmetics as player expression.

## 8. Ethical retention and monetization
**[evidence]** Zagal, Björk & Lewis (2013), *Dark patterns in the design of games* (FDG 2013):
catalogues deceptive practices such as pay-to-skip grind, false scarcity and social pressure.
**[policy]** Roblox requires purchases through its own flows. Paid random items have specific
rules (PolicyService), and we sell none.
**We build:**
- Exact prices and contents before every prompt, and no fake discounts or countdowns.
- Real season end dates only, and nothing that sells match points or degree changes mid-fight.
- Purchases fulfilled only after the server processes the receipt, once per purchase.
- Players who never pay get the whole story, all free powers and full competitive viability.
- Returning is rewarded with things to do (new challenges, events, story files), not punished
  with streak loss beyond a missed bonus.

## 9. Defeat that motivates instead of shaming
**[practice]** Learnable failure, with a clear explanation of what happened and a quick, easy
retry, keeps players engaged (Juul, 2013, *The Art of Failure*; GameFlow's feedback criteria).
**[hypothesis]** Showing one true, specific observation after a loss ("You blocked 6 of 9 heavy
attacks; 3 grabs got through your guard") helps more than generic encouragement.
**We build:**
- A results screen that states real numbers from the match: damage, hits landed, blocks,
  perfect defenses, grabs suffered, longest combo.
- One factual tip chosen from those numbers, for example: if most damage taken came from grabs,
  "Grabs beat blocking. Tap Q to dodge them or strike first."
- Rematch and practice options, and a dignified way back to the Lounge.
- We never claim to know why a player lost beyond what the numbers show.

## 10. Replays
**[practice]** Kill cams and highlight replays let players relive and understand moments.
**We build:**
- Server-recorded positions (10 Hz) and events for the last moments of each match, sent to the
  players and spectators.
- A replay viewer that rebuilds the fight with stand-in fighters, with cinematic cameras, a
  timeline with event markers, pause, seek, slow motion and highlight jumps.
- It is honestly labelled as a reconstruction, never a video.

## How we'll know it's working (respecting privacy)
These are signals, not proof. Roblox AnalyticsService funnels and custom events, guarded and
anonymous:
- onboarding step completion and time to first fight;
- the share of players who finish a first match;
- lesson starts and finishes;
- replay opens;
- Archive files found;
- return visits on later days.

None of this is used to tune pressure tactics. Qualitative feedback and playtests come first.
