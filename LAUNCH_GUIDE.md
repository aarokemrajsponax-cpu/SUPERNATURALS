# SUPERNATURALS launch guide (for AJKR)

Written 4 November 2026. Follow it top to bottom the first time. Steps marked **(optional)**
can wait until after launch. Anything with an id can be done by sending Claude the numbers in
chat instead: Claude pastes them, runs the tests and pushes.

---

## Part 1. One-time setup on your computer (about 20 minutes)

You need: Roblox Studio (logged in as **XxxXxxX_77797**), Visual Studio Code, GitHub Desktop
(or Git), and Rojo 7.7.1.

1. **Get the code.** In GitHub Desktop: File, Clone repository, choose
   `aarokemrajsponax-cpu/SUPERNATURALS`, pick a folder. Then switch to the branch
   `claude/friendly-turing-1hh9nu` (Current Branch menu). This branch has everything Claude built.
   Later, to get Claude's newest work: **Fetch origin**, then **Pull origin**.
2. **Install Rojo** (the tool that sends the code into Studio). Easiest: install Rokit from
   https://github.com/rojo-rbx/rokit (follow its README), then open a terminal in the project
   folder and run `rokit install`. That installs exactly Rojo 7.7.1 (pinned in `rokit.toml`).
   Check with `rojo --version`.
3. **Install the Rojo Studio plugin:** close Studio, run `rojo plugin install`, open Studio.
   You now have a **Rojo** button on the Plugins tab.
4. **Open the project in VS Code:** File, Open Folder, the project folder. (The "Rojo - Roblox
   Studio Sync" extension is optional; the terminal commands below are enough.)

## Part 2. Make the place and publish it (about 10 minutes)

1. In a terminal in the project folder:
   `rojo build default.project.json -o SUPERNATURALS.rbxl`
2. Open `SUPERNATURALS.rbxl` in Studio. The world (hall, lounge, bases, chambers, Training
   Studio) is built by the game's scripts when it runs, so the place looks nearly empty in
   edit mode. That is normal. Press **Play** to see everything.
3. **File, Publish to Roblox As**: create the experience "SUPERNATURALS" (or choose your
   existing one). From now on use **File, Publish to Roblox** to update it.

## Part 3. Everyday sync (VS Code, Rojo, Studio)

1. In the project folder run `rojo serve` and leave it running.
2. In Studio: Plugins tab, **Rojo**, **Connect** (address `localhost`, port `34872`).
3. Any change to the code (yours or pulled from Claude) appears in Studio within a second.
4. To put changes live: **File, Publish to Roblox**. Players get them in new servers; to
   update everyone, Creator Hub, your experience, the "..." menu, **Shut down all servers**
   (or wait for old servers to empty).

If Rojo will not connect: make sure `rojo serve` is still running, run `rojo plugin install`
again (the plugin must match Rojo 7.7.1), and restart Studio.

## Part 4. Studio game settings (5 minutes, Home tab, Game Settings)

- **Security:** turn on **Enable Studio Access to API Services** (saving works in Studio
  tests). Leave **Allow HTTP Requests** off unless you turn on Jeffery's AI (Part 7).
- **Avatar:** Avatar type **R15** (fighters, poses and the practice dummies expect R15).
- **Places:** server size **20**.
- **Permissions:** keep the experience private until Part 8 passes, then make it public.

## Part 5. Robux items to create (Creator Hub, about 30 minutes)

Go to create.roblox.com, **Creations**, SUPERNATURALS, **Monetization**.

- **Passes:** Passes, **Create a Pass**, upload an image, enter the name and description below,
  create it, open it, **Sales**, turn on **Item for Sale**, set the price, Save. Copy its id.
  Managed (regional) pricing is on by default for passes: leave it on.
- **Developer products:** Developer Products, **Create a Developer Product**, enter the name,
  description and price, Save, copy its id, then open it and **turn on Managed Pricing**
  (regional prices; the game already reads each player's live regional price).
- Paste each id over the `id = 0` of the same item in `src/shared/Config/Monetization.luau`
  (or send the ids to Claude). Until an id is filled, the shop shows "Available soon" and
  nothing can be bought, so nothing breaks if you do them one at a time.
- Descriptions: use the item's `benefit` text from `Monetization.luau` (it is exact and honest).
  Prices are suggestions; you choose.

### Game passes (8)

| Key in Monetization.luau | Name | What it gives | Suggested price |
|---|---|---|---|
| CorruptionPower | Corruption | The Corruption fighter for good, all three phases, every mode | 6,666 R$ |
| SyntaxPower | Syntax | The Syntax fighter for good, all three phases, every mode | 9,999 R$ |
| AdminPower | Admin Powers | The Admin Powers fighter for good (never real admin rights) | 12,000 R$ |
| ExtraAbilitySlot | Extra Ability Slot | One more ability slot in every loadout, all modes | 349 R$ |
| CelestialDragonStyle | Celestial Dragon Style | Grandmaster cosmetic style, looks only | 249 R$ |
| VIP | VIP | VIP nameplate and title, gold name in the lounge, looks only | 299 R$ |
| FoundersCollection | Founders Collection | Four exclusive cosmetics (aura, knockout effect, nameplate, title) | 799 R$ |
| BaseEffectsPack | Base Effects Pack | Five looks for your own base (aurora, indoor snow, ember fireplace, light show, fireflies), looks only | 199 R$ |

### Developer products (13)

| Key | Name | What it gives | Suggested price |
|---|---|---|---|
| GemsSmall | Pouch of Gems | 100 Gems | 49 R$ |
| GemsMedium | Chest of Gems | 450 Gems | 199 R$ |
| GemsLarge | Vault of Gems | 1,100 Gems | 449 R$ |
| GemsHuge | Hoard of Gems | 2,600 Gems | 999 R$ |
| GemsMassive | Treasury of Gems | 7,000 Gems | 2,499 R$ |
| SeasonPremium | Season Premium | This season's premium cosmetic track | 499 R$ |
| SeasonTierSkip | Season Tier Skip | One season pass tier | 49 R$ |
| TrialCorruption | Corruption Trial | 24 hours of Corruption in every mode | 49 R$ |
| TrialSyntax | Syntax Trial | 24 hours of Syntax in every mode | 49 R$ |
| TrialAdmin | Admin Powers Trial | 24 hours of Admin Powers in every mode | 49 R$ |
| LoungeSpin | Lounge Wheel Spin | 1 spin on the Lounge wheel (random prize) | 25 R$ |
| LoungeSpin5 | Lounge Wheel Spins x5 | 5 spins on the Lounge wheel (random prizes) | 99 R$ |
| FireworksShow | Fireworks Show | One saved 45 second fireworks show for your base, launched from the base panel | 25 R$ |

The two wheel products are paid random items. The rule that goes with them: **the odds of every
prize are shown** (on the wheel in the lounge and in the Wheel window, as percentages that add to
100, before any spin or purchase), results are drawn on the server, and players Roblox marks as
restricted for paid random items never see or can buy them. Everyone gets one free spin a day.
Odds live in `src/shared/Config/Wheel.luau`.

Items added later (for example the lounge spin wheel) are always listed, with their exact
names, in section 0 of `FINAL_OWNER_HANDOFF.md`, which is kept current.

Images: a pass needs a square image. Simple branded icons for every item are in
`marketing/store_icons/` (use them or your own).

## Part 6. The game page (15 minutes)

- **Icon and thumbnails:** `marketing/` (its README says which file goes where).
- **Description** (suggested, edit freely):
  > Step into the facility and master extraordinary powers. Choose from seven fighters, from
  > the kinetic Strong Dude to the reality-bending Syntax, evolve through phases mid-fight,
  > and battle in five distinct battlegrounds. Train with Jeffery, watch live matches in the
  > Spectating Lounge, build your own base and earn titles and achievements. New events every
  > season.
- **Genre:** Fighting. **Devices:** Computer, Phone, Tablet (add Console after you have tested
  with a controller).
- **Maturity questionnaire** (Creator Hub requires it): answer honestly; the game has stylised
  fighting with no blood or gore.
- **Social links (optional):** Discord and others go on the game page (Creator Hub, your
  experience, Social Links). They cannot be rewarded in-game.

## Part 7. Optional features to switch on

- **Jeffery's AI chat (costs money per answer):** Jeffery always answers from his built-in
  knowledge. To let an AI answer too: (1) Game Settings, Security, **Allow HTTP Requests** on;
  (2) Creator Hub, your experience, **Secrets**: add a secret named `ANTHROPIC_API_KEY` with your
  Anthropic API key, allowed domain `api.anthropic.com`; (3) set `Enabled = true` in Jeffery's
  chat config (`src/shared/Config/JefferyChat.luau`, see its header). Limits per player and per
  server are in the same file. Cost: on the default model (Claude Opus 5.5) one answer costs
  roughly 0.5 to 1 US cent (Jeffery's fixed notes are prompt-cached), so at most about $4 per busy
  server per hour at the built-in cap. Claude Haiku 5.5 costs about 1/40 of that with simpler
  answers; the file's header says the three values to change. Set a monthly spend limit in your
  Anthropic console before switching it on.
- **Referral rewards (after the game has been live one day):** Creator Hub, your experience,
  **Engagement, Referral Rewards, Add Reward Details** (name it "Recruiter"), Save, Publish.
- **Group title:** create a Roblox group, paste its id into `GroupId` in
  `src/shared/Config/Community.luau`.
- **Invite message:** Engagement, Notifications, create a string containing `{experienceName}`,
  paste its id into `InviteMessageId` in `Community.luau`.
- **Private servers:** Creator Hub, your experience, Access/Monetization, Private Servers,
  set a monthly price.
- **Music:** 89 licensed tracks (APM, Monstercat and DistroKid uploads) play by place. The 25
  public uploads by unknown accounts in `docs/specs/Audio_verified.md` stay out because their
  rights are unknown; tell Claude if you own or license any of them.

## Part 8. Test before going public (30 minutes)

1. In Studio press **Play** (you, as the owner): finish Jeffery's tour, change fighter (click
   your player card at the top left), play a CPU fight, open **OWNER** in the dock (your
   Control Center; only you see it; the P key opens it too), open GIFTS, PASS and LOCKER.
2. Test tab, **Clients and Servers**, 2 players: start a Duel between them. (Test players are
   not you, so they have no OWNER button: that is correct.)
3. Buy something in Studio. Studio purchases are test purchases: no Robux are taken. Check the
   reward arrives and that it is there after you stop and play again.
4. **Dynamic Price Check** (Creator Hub, Monetization, Developer Products or Passes, the "..."
   menu): try "Location pinned" for a lower-priced country, join, check the shop shows the
   regional price, then turn it off.
5. Publish, join the live game from the Roblox app on your phone and on a computer, play one
   match on each, rejoin and check your progress saved.
6. With a friend: join the same server and check the "Friend bonus" chip appears.

## Part 9. Launch and the first weeks

- **Calendar:** Harvest Week dressing and the Harvest gift calendar run now (calendar
  5 to 26 November, UTC); the Harvest season pass ends 30 November; the Christmas calendar
  runs 1 to 25 December.
- **Your Control Center (OWNER button):** dashboard, events for this server or all servers,
  announcements (filtered by Roblox), a scheduler for events, a custom event maker, emergency
  restore. Try an event in "This server" before using "All servers".
- **Community goals:** check your like count on the game page now and then and enter it in
  OWNER, Community goals. At 1,000, 5,000 and 25,000 likes every player gets a reward.
- **Watch the numbers:** Creator Hub, Analytics: retention, the onboarding funnel (each step of
  Jeffery's tour), economy (Money and Gems in and out) and monetization.
- **Updates:** pull Claude's work in GitHub Desktop, `rojo serve` syncs it into Studio, test,
  Publish.

## Part 10. If something goes wrong

| Problem | Fix |
|---|---|
| The shop says "Available soon" | That item's id is still 0 in Monetization.luau |
| "Progress isn't being saved" banner in Studio | Turn on Studio Access to API Services (Part 4) |
| No OWNER button | You must be logged in as XxxXxxX_77797; multi-player test clients are not you |
| Rojo will not connect | `rojo serve` running? Re-run `rojo plugin install`, restart Studio |
| Studio shows old code after pulling | Stop and start `rojo serve`, reconnect |
| A purchase did not arrive | Check Creator Hub, Monetization, the item is on sale and the id matches; receipts retry automatically |
| Music is silent | A track can be moderated or unavailable; the game skips it. Tell Claude to swap it |
