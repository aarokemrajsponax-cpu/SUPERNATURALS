# Task G — Shop, cosmetics, progress and challenges

Master prompt §23-28 (currencies, earning, shop and cosmetic economy, premium powers, victory
presentations, ethical monetization). Read master_prompt.md lines ~1200-1311.

## Already there (read what you need)
- src/server/Services/DataService.luau (get/update/onLoaded/onChanged/sendView), CurrencyService
  (balance/canAfford/spend(player, price, reason)/add(player, amounts, reason),
  CurrencyService.describe(amounts)), PurchaseService (game passes for premium powers;
  developer products through promptProduct(player, key) + idempotent ProcessReceipt; gem packs in
  src/shared/Config/Monetization.luau Products; passes in Passes; ids are 0 until the owner
  creates them in Studio — prompting with id 0 must show a clear "not set up yet" notice instead
  of failing).
- Profile (src/shared/Data/Schema.luau): cosmetics = { owned = {[id]=true}, equipped =
  {[slot]=id} } with Schema.CosmeticSlots = { "aura", "victory", "knockout", "title", "trail" };
  stats, powers[powerId].xp (mastery), daily = { day, progress, claimed, loginStreak }.
- Protocol.ShopAction (Buy(itemId), Equip(slot, itemId?), PromptProduct(productKey)) on
  Remotes.ShopRequest — NOT handled by anything yet: you write the handler. Rate-limit channel
  "Shop" exists in AntiExploitService. Protocol.ProgressAction.ClaimChallenge is handled by
  ProgressionService (src/server/Services/ProgressionService.luau: today(), daily challenges from
  RewardMath.dailyFor(day), Rewards config). Profile.get() on the client has the safe view.
- Client: design system (Theme, Components, Shell), Profile.luau, PowersWindow.luau as an example
  of a big polished window. The Nexus has a Market gate (opens Window:Shop) — register your
  window with id "Shop".
- Another agent builds the victory scene and reads your catalog: Cosmetics.Victory[id] =
  { name, pose = string, fx = string? } and Cosmetics.Knockout[id] = { name, fx = string }. Keep
  those field names. Another agent builds the base furniture shop inside the Base window; don't
  sell furniture here (you may add a "Furniture" tab that just opens the Base window).

## You own (create/edit only these, plus additive Engine shims)
- src/shared/Config/Cosmetics.luau — the catalog: Auras (~8: soft particle auras in tasteful
  colours, a few premium), Trails (~6), Titles (~10 text titles shown over the head, some earned
  only: e.g. "Undefeated" for a 10 win streak, "Master of X" at mastery 10 — earned ones can't be
  bought), Victory poses (~8 distinct presentations: pose + effect), Knockout effects (~6: what
  plays where your opponent goes down). Each: id, name, slot, price ({ money } or { gems }) or
  earned = { stat, value } or default = true, rarity (Common/Rare/Epic/Legendary), short
  description. Prices balanced against Rewards (a match pays ~40-100 Money): commons 500-1,500
  Money, rares 2,500-5,000, epics gems 150-400, legendaries gems 600-1,200. A free default per
  slot. No fake discounts, no timers, no "limited" pressure.
- src/server/Services/ShopService.luau — handles ShopRequest: Buy (known id, not owned, buyable,
  CurrencyService:spend, then owned; result toast), Equip (owned or default, slot matches; nil =
  unequip), PromptProduct (known product key -> PurchaseService:promptProduct). Unlocks earned
  cosmetics when their stat condition is met (on profile change / match end) with a toast.
  Applies equipped cosmetics to the player's character: attributes on the character model
  (SNAura, SNTrail, SNTitle) for clients to render. Cosmetics show in matches too, but must never
  hide hitboxes or tells: keep auras subtle and close to the body, trails short, and nothing that
  looks like a power effect. Knockout effects: on CharacterService:onKnockout(victim, credited),
  tell clients to play the credited player's equipped knockout effect at the victim's position
  (a new Remotes event is NOT needed: use Remotes.CombatEvent with a new kind "KnockoutFx" added
  to Protocol.CombatEvent — additive one-line edit allowed). Add ShopService to Bootstrap ORDER
  after ProgressionService (one-line edit allowed).
- src/client/Controllers/CosmeticsController.luau — renders auras/trails/titles for every
  character from the attributes (cleaned up on respawn/leave/attribute change), plays knockout
  effects; respects Settings.reducedEffects. Add to the client Bootstrap ORDER (one line).
- src/client/UI/ShopWindow.luau — Shell window "Shop" (order after Base): tabs Cosmetics (sub-tabs
  by slot with a live preview: a mannequin or the player's own character in a ViewportFrame with
  the aura/trail/title applied; victory poses play their pose), Gems (gem packs with exact Robux
  prices and what you get, buttons prompt the real purchase; never pretend it succeeded), Premium
  (Corruption 6,666 R$, Syntax 9,999 R$, Admin 12,000 R$ with their benefit text from
  Monetization.Passes; buttons open the Powers window on that power or prompt the pass), and
  Furniture (opens the Base window if it's registered). Item cards: name, rarity colour stripe,
  price with currency icon, owned/equipped state, Buy -> Shell.confirm with the price, Equip.
- src/client/UI/ProgressWindow.luau — Shell window "Progress": mastery for each of the 7 powers
  (level, XP bar to next, rewards at the next levels), daily challenges (3 cards with progress
  bars, reward, Claim button when done; resets in HH:MM), login streak (7-day row with today
  highlighted), stats (matches, wins, losses, draws, best streak, knockouts, K/D) laid out cleanly.
  Register both windows in src/client/Controllers/UIController.luau (one line each).
- src/server/Services/OwnerService.luau + src/client/UI/OwnerPanel.luau: add an owner-only
  "Testing" section: give myself Money/Gems (bounded amounts), unlock every power and degree for
  myself, own every cosmetic, reset my profile to new. Owner-only (the existing owner check:
  UserId 8722595934 / XxxXxxX_77797); never available to anyone else; logged.
- tests/shop_test.luau — end-to-end (tests/smoke/World.luau): buy with enough/not enough money,
  buy twice refused, earned-only refused, equip owned/unowned/wrong slot/junk, unequip, earned
  unlock after a stat change, attributes set on the character and kept after respawn, knockout
  effect event fired for the credited player's equipped effect, product prompt with id 0 refused
  cleanly, owner testing actions work for the owner and are refused for others, junk requests.
- tests/smoke_shop.luau — client smoke (tests/smoke/Client.luau): Shop window every tab, preview,
  buy/equip flows with confirm, Gems and Premium tabs; Progress window with fake profile data
  (challenges done/not done, claim); CosmeticsController renders and cleans up every aura/trail/
  title/knockout effect; auditLayout at 1280x720 and 667x375; no game-code errors.

Follow CONVENTIONS.md and ART.md (no emoji in the UI; tasteful effects; honest pricing copy).
Run: unit tests, rojo build (own output), place_check, smoke.luau, your two tests, data_test.luau,
integration.luau. Report real results.

## Round 3 addendum: monetization catalog, season pass and retention (overrides conflicts)
The owner wants "damn good, tempting Robux purchases" and big revenue, AND (binding) the
master prompt's rules: supported purchase flows only, server-side idempotent fulfilment,
clear prices and contents before buying, no fake discounts/timers/pressure, no wagering, nothing
that sells match points, degree changes mid-fight or an automatic win, premium powers balanced.
Make the offers genuinely attractive through quality, status and fun, not tricks. No paid random
items (no loot boxes): every purchase says exactly what you get.

### The catalog (all in src/shared/Config/Monetization.luau; ids stay 0 until the owner creates
### them; extend PurchaseService additively; keep every existing pass/product working)
Game passes (permanent):
- CorruptionPower 6,666 R$, SyntaxPower 9,999 R$, AdminPower 12,000 R$ (exist).
- CelestialDragonStyle (exists; cosmetic; price set by the owner, suggest 799).
- VIPClearance 499 R$: VIP keycard to the station's Executive Lounge (a premium room the lobby
  agent may add; until it exists, a VIP-only seating area flag), a VIP nameplate + title, an
  exclusive animated aura, +20% Money from matches, a daily 15-Gem stipend. No combat stats.
- MasteryBoost 399 R$: double power mastery XP, permanently.
- ArchitectPass 299 R$: double base furniture capacity and 6 exclusive lab-themed furniture
  pieces (the base agent reads `Monetization.hasPerk(profile, "ArchitectPass")`).
- MeridianPass (season premium track) 449 R$ per season: implemented as a game pass per season
  id in config (e.g. MeridianPassS1) so a new season = a new pass id; see Season Pass below.
Developer products (repeatable or one-time):
- Gems: GemsSmall 49, GemsMedium 199, GemsLarge 449, GemsHuge 999, GemsMassive 2,499 (exist).
- StarterPack 99 R$, one per account (server-enforced flag): 600 Gems, 5,000 Money, the
  "Founding Member" title and an aura. Honest copy: "One per account." Not shown again once
  bought.
- Boost30 49 R$ / Boost120 149 R$: 2x Money and mastery XP for 30 / 120 minutes of play time
  (server timer, stacks by extending, shown on the HUD).
- PowerDayPass 149 R$: play one chosen premium power (Corruption, Syntax or Admin) in every mode
  for 24 hours (server expiry). The player picks the power before the prompt; the price and
  power are shown. Ends cleanly between matches (never mid-fight).
- Lobby events, the "per-use Robux powers" the owner asked for, made fair: players trigger a
  spectacular event for the whole Garden that never touches matches: EventConfetti 25 R$,
  EventLowGravity 49 R$, EventBlackoutRave 99 R$, EventLanternOverload 149 R$,
  EventContainmentBreach 249 R$ (ids map to AdminEventService events; call
  AdminEventService:start(eventId, { source = "Purchase", by = player }) after the receipt is
  granted; it queues if another event runs, so a paid event always plays; announce the buyer).
  If AdminEventService:start isn't available yet, fulfil by queueing it in your own store and
  retrying; never fail a granted receipt.
- Revive/convenience items that would affect matches are NOT sold.
Also: a "Gift" option for gem packs and the Starter Pack? Roblox has no native gifting for
developer products; skip gifting.

### Season Pass (the retention + revenue engine)
- src/shared/Config/Season.luau: season id, name ("Season 1: The Door in the Hill"), start/end
  dates (owner sets), 40 tiers, XP per tier, a free track and a premium track (premium =
  MeridianPass for this season). Rewards: Money, Gems (modest), cosmetics (auras, trails,
  titles, victory poses, knockout effects, emotes, furniture), lore files (new recovered files
  that only the pass reveals are fine as FREE track items, never premium-only, so the story stays
  free). Season XP comes from matches, daily challenges, weekly missions, lessons and events.
- Weekly missions (5 a week, bigger than dailies), achievements (permanent, ~30, with titles),
  and a Prestige option per power at max mastery (resets that power's mastery for a prestige
  star and a cosmetic; optional).
- Leaderboards: global (OrderedDataStore) for wins, knockouts and season tier; shown on a big
  display in the Garden (the lobby agent places a SurfaceGui screen tagged "SNLeaderboard"; if
  none exists, show it in the Progress window).
- src/client/UI/SeasonWindow.luau: the pass track (horizontal tiers with clear free/premium
  rows, owned/locked/claimable states, preview of each reward), claim buttons, buy premium
  button with exact price, time left in the season (real end date, no fake urgency).
- Analytics (Roblox AnalyticsService): onboarding funnel steps (joined, first fight, first win,
  first power change, first purchase view), economy events (sources/sinks), progression events
  (tiers, mastery), custom events (lore files found, events triggered). Guard every call with
  pcall; never block gameplay.

### Shop presentation
The Shop window becomes the COMMISSARY (station store): sections Featured (Starter Pack while
eligible, the current season pass, one premium power), Powers (the three premium passes + Day
Pass), Boosts, Lobby Events (each with a short looping preview: a small ViewportFrame or
illustrated card, the exact price, "plays for everyone in the Garden"), Gems, Cosmetics, VIP.
Premium look per ART.md: product art built from UI and ViewportFrames, strong hierarchy,
exact prices, what you get in plain words, no fake strikethrough prices.

### Tests (add to tests/shop_test.luau or a new tests/monetization_test.luau)
Every product: receipt granted once even if ProcessReceipt is called 3 times with the same
PurchaseId; NotProcessedYet when the profile isn't loaded; StarterPack refused the second time
(and never prompted); boosts extend correctly and expire; Day Pass expires and never cuts a match;
lobby event purchase queues and plays; season XP/tier/claims (free and premium), premium claim
refused without the pass; VIP perks applied; leaderboards update; analytics calls never error.
