# FINAL OWNER HANDOFF (P.S. 11.0)

For AJKR. Written 3 November 2026. Honest limits first: **Claude could not run a real Robux purchase, could not open Creator Hub, and could not join a live Roblox experience.** Everything marked "Tested" below was tested in the offline stand-in engine (Lune), which fakes MarketplaceService. No behaviour of Roblox's own APIs has been verified live, and neither Dynamic Price Check mode has been run.

Status labels used: COMPLETE AND TESTED. / IMPLEMENTED BUT NOT FULLY TESTED. / PARTIALLY IMPLEMENTED. / OWNER ACTION REQUIRED. / NOT IMPLEMENTED. / BLOCKED.

Code map: receipts and passes `src/server/Services/PurchaseService.luau`; price levels `src/server/Services/PriceLevelService.luau`; transfer gate `src/server/Transfers/TransferPolicy.luau`; live prices `src/client/PriceFetcher.luau`; shop `src/client/UI/ShopWindow.luau`; catalogue and ids `src/shared/Config/Monetization.luau`. Tests: `tests/shop_test.luau`, `tests/pricing_test.luau`, `tests/smoke_shop.luau`, `tests/data_test.luau`.

## 0. AJKR's to-do list, shortest path (updated 3 November 2026, evening)

Everything else is done in code. Where a step says "paste the id", you can instead send Claude
the ids in chat and Claude will paste them, test and push.

**Before launch (about 45 minutes)**
1. Studio, Game Settings, Security: turn on "Enable Studio Access to API Services", then publish.
2. Creator Hub, Monetization, Developer Products: create these 10, turn **Managed Pricing** on for
   each (regional prices), and paste each id into `src/shared/Config/Monetization.luau`:
   Pouch of Gems (100 Gems, 49 R$), Chest of Gems (450 Gems, 199 R$), Vault of Gems (1,100 Gems,
   449 R$), Hoard of Gems (2,600 Gems, 999 R$), Treasury of Gems (7,000 Gems, 2,499 R$),
   Season Premium (499 R$), Season Tier Skip (49 R$), Corruption Trial (49 R$), Syntax Trial (49 R$),
   Admin Powers Trial (49 R$). Prices are suggestions; descriptions are
   the `benefit` text in Monetization.luau.
3. Creator Hub, Monetization, Passes: create these 7 (Managed Pricing is already on for passes)
   and paste each id: Corruption (6,666 R$), Syntax (9,999 R$), Admin Powers (12,000 R$),
   Extra Ability Slot, Celestial Dragon Style, VIP (299 R$), Founders Collection (799 R$).
4. Upload the icon and thumbnails from `marketing/` (README there says which goes where).
5. Play once in a live server: finish Jeffery's tour, play a match, buy one product in Studio's
   free test purchase, rejoin and check everything saved. Press P to open the Control Center.

**After launch**
6. When the game has been live one day: Creator Hub, the game, Engagement, Referral Rewards, Add
   Reward Details (name it after the Recruiter title), Save, Publish.
7. Optional: make a Roblox group and paste its id into `Community.GroupId`
   (`src/shared/Config/Community.luau`); members get the Facility Member title.
8. Optional: add Discord and other links on the experience page (they cannot be rewarded in-game).
9. Optional: Engagement, Notifications: an invite message containing {experienceName}; paste its id
   into `Community.InviteMessageId`.
10. Optional: Private servers (Creator Hub, Access) at a small monthly price.
11. Optional: listen to the 62 public music uploads in `docs/specs/Audio_verified.md` (tier B) and
    say which to add; the 52 licensed tracks already play by area.

**Decisions only you can make**
- The new directive says seven fighters; the game has eight (the Animal Shapeshifter too). Keep it?
- It says four battlegrounds; there are five designs. Keep five?
- Extra Ability Slot pass: keep it in ranked Duels, or casual modes only (fairer)?
- More AI key art needs Higgsfield credits (0.92 left, not enough for one image).

## 3.1 Developer Products inventory

All ids are in `src/shared/Config/Monetization.luau` (`Products`). The reward is fixed by the product, never by Robux spent, so regional prices do not change what a player gets. Receipt handler for all five: the single `ProcessReceipt` in PurchaseService. Duplicate protection (same PurchaseId twice grants once) is tested in `shop_test` and `data_test`.

| Product | Product ID | Intended Reward | Dynamic Price | Managed Pricing | Receipt Handler | Status |
|---|---|---|---|---|---|---|
| GemsSmall "Pouch of Gems" | 0: OWNER ACTION REQUIRED — CREATE PRODUCT AND PROVIDE ID | 100 Gems | Implemented (GetProductInfoAsync, Product), tested offline only | OWNER ACTION REQUIRED (off by default for products) | Implemented, tested offline | OWNER ACTION REQUIRED |
| GemsMedium "Chest of Gems" | 0: OWNER ACTION REQUIRED — CREATE PRODUCT AND PROVIDE ID | 450 Gems | same | same | same | OWNER ACTION REQUIRED |
| GemsLarge "Vault of Gems" | 0: OWNER ACTION REQUIRED — CREATE PRODUCT AND PROVIDE ID | 1,100 Gems | same | same | same | OWNER ACTION REQUIRED |
| GemsHuge "Hoard of Gems" | 0: OWNER ACTION REQUIRED — CREATE PRODUCT AND PROVIDE ID | 2,600 Gems | same | same | same | OWNER ACTION REQUIRED |
| GemsMassive "Treasury of Gems" | 0: OWNER ACTION REQUIRED — CREATE PRODUCT AND PROVIDE ID | 7,000 Gems | same | same | same | OWNER ACTION REQUIRED |

### Season pass products (new, cosmetic economy)

Both are developer products handled by the same `ProcessReceipt`, idempotent by PurchaseId, granted only after the profile save succeeds (a failed save is rolled back and Roblox retries). Both keep id 0 in code, show "Available soon" and can never be prompted until you paste the id. The shop shows Roblox's live price; the "Recommended price" column is only a suggestion for you to type into Creator Hub (it is `recommended` in `Monetization.luau`, never shown to players).

| Product | Product ID | Gives | Recommended price | Creator Hub name and description |
|---|---|---|---|---|
| SeasonPremium "Season Premium" | 0: OWNER ACTION REQUIRED, paste over `Products.SeasonPremium.id` | Unlocks the premium cosmetic track of the current season only (one cosmetic at each of 30 tiers). No Money, Gems or power. A new season needs a new purchase. | 499 R$ | Name "Season Premium". Description: the `benefit` text in `Monetization.luau`. |
| SeasonTierSkip "Season Tier Skip" | 0: OWNER ACTION REQUIRED, paste over `Products.SeasonTierSkip.id` | Adds one tier (100 points) to the current season pass, never past tier 30. Can be bought repeatedly; every tier is also free to earn. | 49 R$ | Name "Season Tier Skip". Description: the `benefit` text in `Monetization.luau`. |

Season pass details: season "harvest_2026" (Harvest Week) runs 1 November 2026 00:00 UTC to 30 November 2026 23:59:59 UTC (`Config/SeasonPass.luau`). To start another season add an entry to `SeasonPass.Seasons`; every player's pass then resets by itself, and cosmetics already claimed are kept. Nothing random is sold; tier skip is the only paid way to move up and tiers can always be earned for free. No countdown or "last chance" wording appears anywhere.

### Fighter trial products (new, holiday calendars)

Three developer products, one per premium fighter, handled by the same `ProcessReceipt` and the same idempotent, save-before-grant pattern as the season products (`PurchaseService:_grantTrialProduct`; a failed save is rolled back and Roblox retries). Each gives a fixed 24 hours of that fighter in every mode, including Duel and Free-for-All, exactly as if owned. Trials stack up to 7 days and never replace the unlock; a trial is not sold to a player who already owns the fighter, or who is within a day of the 7 day limit. Nothing is random. All keep id 0 in code, show "Available soon" and can never be prompted until you paste the id. They appear in the shop's Premium powers category next to each fighter's unlock, with Roblox's live price (the `recommended` value is only a suggestion for Creator Hub). The Admin trial never grants real admin rights.

| Product | Product ID | Gives | Recommended price | Creator Hub name and description |
|---|---|---|---|---|
| TrialCorruption "Corruption Trial" | 0: OWNER ACTION REQUIRED, paste over `Products.TrialCorruption.id` | 24 hours of Corruption, all three degrees, in every mode. Stacks up to 7 days. | 49 R$ | Name "Corruption Trial". Description: the `benefit` text in `Monetization.luau`. |
| TrialSyntax "Syntax Trial" | 0: OWNER ACTION REQUIRED, paste over `Products.TrialSyntax.id` | 24 hours of Syntax, all three degrees, in every mode. Stacks up to 7 days. | 49 R$ | Name "Syntax Trial". Description: the `benefit` text in `Monetization.luau`. |
| TrialAdmin "Admin Powers Trial" | 0: OWNER ACTION REQUIRED, paste over `Products.TrialAdmin.id` | 24 hours of Admin Powers, all three degrees, in every mode. Stacks up to 7 days. | 49 R$ | Name "Admin Powers Trial". Description: the `benefit` text in `Monetization.luau`. |

The same 24 hour trial tickets are also free gifts in the holiday calendars (three days of each calendar: Corruption, Syntax and Admin), so players can try every premium fighter without paying.

No other developer products exist in the code. Starter Pack is not built (no matching benefits exist in code).

## 3.2 Game Pass inventory

| Game Pass | Pass ID | Permanent Benefit | Ownership Verification | Managed Pricing | Status |
|---|---|---|---|---|---|
| CorruptionPower "Corruption" | 0: OWNER ACTION REQUIRED — CREATE PASS AND PROVIDE ID | Unlocks the Corruption power, all degrees, every mode | UserOwnsGamePassAsync, pcall, retry, session cache; purchase event only a hint, re-verified | On by default for passes: confirm in Creator Hub | OWNER ACTION REQUIRED |
| SyntaxPower "Syntax" | 0: same | Unlocks Syntax | same | same | OWNER ACTION REQUIRED |
| AdminPower "Admin Powers" | 0: same | Unlocks Admin Powers (the fighter; never grants real admin rights) | same | same | OWNER ACTION REQUIRED |
| ExtraAbilitySlot "Extra Ability Slot" (new this pass) | 0: same | One more ability slot in every loadout (cap 6); read by PowerService | same | same | OWNER ACTION REQUIRED |
| CelestialDragonStyle | 0: same | Cosmetic only: The Grandmaster's Celestial Dragon Style | same | same | OWNER ACTION REQUIRED |

### Cosmetic passes (new)

Both give looks only (no stat, damage, speed or power change). Their cosmetics are granted through CosmeticService after `UserOwnsGamePassAsync` confirms ownership (on join and after the purchase window closes), once each, and are sold nowhere else. The shop card lists every item.

| Game Pass | Pass ID | Gives (all listed on the shop card) | Recommended price | Creator Hub name |
|---|---|---|---|---|
| VIP | 0: OWNER ACTION REQUIRED, paste over `Passes.VIP.id` | VIP Gold nameplate, VIP title, and a gold name in the Spectating Lounge (the lounge name is drawn by `CosmeticFxController` from the `SNVip` player attribute). Nothing in combat. | 299 R$ | "VIP" |
| FoundersCollection "Founders Collection" | 0: OWNER ACTION REQUIRED, paste over `Passes.FoundersCollection.id` | Founders' Ring (aura), Founders' Flare (knockout effect), Founders' Brass (nameplate), Charter Patron (title). Exclusive to this pass. | 799 R$ | "Founders Collection" |

Description text for each: the `benefit` field in `Monetization.luau`. Managed Pricing: leave on (default for passes).

Passes at id 0 show "Available soon" and can never be prompted (tested). Prices are set only on Roblox, never in code.

## 3.3 Creator Hub owner instructions

### Work Claude completed in code
Receipt handler hardening, pass re-verification, price-level fetch and transfer gate, live-price fetcher, the Master Shop window, the Extra Ability Slot entry, and the tests listed above.

### Settings AJKR must configure in Creator Hub
1. Open create.roblox.com, Creations, select the experience, Monetization.
2. Create missing Developer Products: Developer Products, Create a Developer Product. Use the names and descriptions from the table in 3.1 and 3.2 (the Benefit text in `Monetization.luau`). Upload an icon for each. Set a base price you choose (the code does not read one). Save.
3. Copy each Product ID: open the product, copy the id from its page or the URL. Paste it over `id = 0` for that key in `Monetization.Products`.
4. Create missing Game Passes: Passes, Create a Pass. Name and describe them as in 3.2, add an icon, set the price, and put them On Sale. Copy each id and paste it over `id = 0` in `Monetization.Passes`.
5. Check Managed Pricing for passes: open each pass, Pricing. It is on by default; leave it on.
6. Enable Managed Pricing for products: only after step 7 passes and the game is published with the latest code. Developer Products, select the product, Enable Managed Pricing. Roblox keeps regional prices within 70% below the default and never above.
7. Review default prices, descriptions and icons of all items. Confirm each description matches the card text in the shop.
8. Dynamic Price Check (two separate tests, run both, for each of Passes and Developer Products): item "..." menu, Dynamic Price Check, add up to five test accounts. Test A, Price pinned: set a fake Robux amount, wait a few minutes, join, open the Master Shop: every Robux price must show that fake amount. Test B, Location pinned: choose a simulated location, wait, join: prices must show that region's amounts. Fix anything that does not move, repeat, then disable the configuration.
9. Review the final shop in game: all categories, owned states, "Available soon" gone for items you set up.

### Testing AJKR must perform manually
Buy each pass and one product of each kind with a real (or test) account; confirm the reward, leave and rejoin and confirm it persists; buy a product twice and confirm two grants; cancel a purchase and confirm nothing is charged; try a pass you already own.

## 3.4 Regional pricing security audit

"Tested" means the offline stand-in engine (`tests/pricing_test.luau`), not live Roblox.

| Requirement | Implemented | Tested | Evidence |
|---|---|---|---|
| API call on player join | Yes | Offline | PriceLevelService `_fetch` on PlayerAdded; pricing_test "join" |
| Fresh trade verification | Yes (gate only; no trading exists, DECISIONS 21) | Offline | `TransferPolicy.canTrade` looks up both users each call; test counts one lookup per decision |
| Fresh gift verification | Yes (gate only) | Offline | `canGift`; test shows a stored join level of 640 is ignored for fresh 100 |
| Same-price-level trade rule | Yes | Offline | table 1000/1000, 750/750 allow; 500/1000 block |
| Sender >= recipient gift rule | Yes | Offline | table 1000>1000, 1000>500, 750>500 allow; 500>750, 500>1000 block |
| Missing API result handling | Yes | Offline | missing, wrong-user, out-of-range, fractional, string levels all deny or store nothing |
| API failure handling | Yes | Offline | pcall; denial with the retry message; join still succeeds; lock released |
| Transaction locking | Yes | Offline | `acquire`, `run`; overlap refused, release on error and denial, stale lock expires after 30 s |
| Duplicate-transfer prevention | Partially: lock stops simultaneous transfers; item removal and delivery belong to the future trade system | Offline (lock only) | pricing_test lock test |
| Offline gift recipient handling | Yes | Offline | recipient needs only a UserId |
| Client exploit resistance | Yes | Offline | no remote carries a level or exists for trade or gift; extra arguments ignored |

How it works: at join, `GetUsersPriceLevelsAsync({UserId})` runs in a pcall; the answer is kept only if it contains that UserId with a whole PriceLevel from 1 to 1000. It lives in memory and is dropped on leave; it is never saved or sent to clients. Any future trade or gift must call `TransferPolicy.run("trade" | "gift", fromId, toId, transferFn)`. That takes a lock on both accounts, fetches both levels freshly, applies the rule, runs `transferFn` only if allowed, then releases the lock. Any failure denies with a friendly message that never shows a level. Items, ownership, recipient, restricted items and atomic delivery are the future trade system's job; not built.

## 3.5 Purchase security audit

| Area | Finding |
|---|---|
| Centralized receipt handler | One `MarketplaceService.ProcessReceipt`, set in `PurchaseService:Start`. Implemented, tested offline. |
| Product ID mapping | `productById` built from Monetization at Init; unknown or 0 ids return NotProcessedYet. Tested. |
| Receipt validation (changed) | Now refuses a missing or empty PurchaseId, bad PlayerId or ProductId, a CurrencyType other than Robux when present, and a non-numeric or negative CurrencySpent. Tested with 13 bad receipts. |
| PurchaseId deduplication | Stored in the session-locked profile (`receipts`, capped list); repeat returns PurchaseGranted with no second grant. Tested. |
| DataStore persistence | Grant, record, then `saveNow`; PurchaseGranted only if it saved, otherwise the grant is rolled back and NotProcessedYet returned. Tested in data_test. |
| Session locking | Uses DataService profiles and their lock; unsaved fallback profiles never receive purchases. Tested in data_test. |
| Unloaded profile | Returns NotProcessedYet; the retry grants after load. Tested (shop_test). |
| Retry behaviour | Roblox re-sends NotProcessedYet receipts; ownership checks retry with backoff. |
| CurrencySpent handling | Validated and not multiplied; reward comes from the product. Tested (a lower regional amount gives the same reward). Not stored for accounting: unresolved if you want revenue records. |
| Game Pass ownership | `UserOwnsGamePassAsync` with pcall and retry at join, cached for the session; a purchase event is now re-verified with the same call before anything is recorded (changed). Tested. |
| Shop prompts (new) | `ShopRequest` PromptPass and PromptProduct: rate limited, key checked on the server, id 0 never prompts, owned passes never re-sold. Tested. |
| Removed | The startup price comparison against hard-coded Robux (it would warn wrongly under regional pricing). |

Unresolved: (1) the live behaviour of ProcessReceipt, regional prices and pass checks has not been exercised on Roblox. (2) Hard-coded `robux` numbers still exist outside the shop: `Monetization.luau` fields, `src/shared/Powers/*.luau` `premium.robux`, and text built by PowerService and PowersWindow (for example "12000 Robux" in queue messages). The shop does not use them; those other screens should switch to PriceFetcher before you enable Managed Pricing on products. (3) PowersWindow still calls the deprecated `GetProductInfo`. (4) Receipt `CurrencyType` is only checked when present because the offline engine omits it.

## 3.6 Final owner action checklist

REQUIRED BEFORE PUBLICATION
1. Create the 10 Developer Products (5 Gem packs, SeasonPremium, SeasonTierSkip, TrialCorruption, TrialSyntax, TrialAdmin) and 7 Game Passes (3 powers, Extra Ability Slot, Celestial Dragon Style, VIP, Founders Collection) in 3.1 and 3.2; paste every id into `Monetization.luau`. Suggested prices for the new items are in the tables above.
2. Check each pass has Managed Pricing on; enable Managed Pricing for each product only after Dynamic Price Check passes.
3. Run both Dynamic Price Check modes (Price pinned and Location pinned) and fix anything that does not update.
4. Make real test purchases of every item; verify rewards, rejoin persistence, a cancelled purchase and an already-owned pass.
5. Replace the remaining hard-coded Robux numbers in other screens (3.5, item 2) or confirm in game that none is shown to players.

RECOMMENDED
1. Test a failed save during a product purchase in Studio with API access off, and confirm the player is told to rejoin.
2. Have a second account on a different region run the shop and compare prices.
3. Check the shop at phone size on a real device.

OPTIONAL FUTURE WORK
1. Starter Pack: only if you define real benefits first; none exist in code.
2. A trading or gifting system built on `TransferPolicy.run` (DECISIONS 21).
3. Store CurrencySpent per receipt for revenue accounting.

## 3.7 Final implementation status

| Feature | Status | Evidence |
|---|---|---|
| Single ProcessReceipt with validation, dedupe, save-before-grant | IMPLEMENTED BUT NOT FULLY TESTED. | Offline tests pass (shop_test 9, data_test 26); no real purchase |
| Game Pass ownership verification | IMPLEMENTED BUT NOT FULLY TESTED. | Offline tests only |
| Price level fetch at join (session only) | IMPLEMENTED BUT NOT FULLY TESTED. | pricing_test; live API behaviour unverified (the docs do not state the realm; verify the call works on the server) |
| TransferPolicy and lock | IMPLEMENTED BUT NOT FULLY TESTED. | pricing_test 9; no trading system uses it yet |
| Dynamic prices in the shop | IMPLEMENTED BUT NOT FULLY TESTED. | smoke_shop 8 incl. live, unavailable and soon states; Dynamic Price Check not run |
| Master Shop window | IMPLEMENTED BUT NOT FULLY TESTED. | smoke_shop at 1280x720 and 667x375; renders reviewed; not seen in Studio |
| Season pass (30 tiers), SeasonPremium and SeasonTierSkip products, VIP and Founders Collection passes, Season pass window and shop category, cosmetic effects | IMPLEMENTED BUT NOT FULLY TESTED. | seasonpass_test 19, smoke_seasonpass 10, smoke_cosmeticfx 6 (stand-in engine); renders reviewed at 1280x720 and 667x375; no real purchase, not seen in Studio, particles not seen |
| Dynamic Price Check, Price pinned | OWNER ACTION REQUIRED. | Not performed |
| Dynamic Price Check, Location pinned | OWNER ACTION REQUIRED. | Not performed |
| Product and pass ids, Managed Pricing for products | OWNER ACTION REQUIRED. | All ids are 0 |
| Real purchases | BLOCKED. | Needs ids and a live experience |
| Trading and gifting systems | NOT IMPLEMENTED. | Out of scope by design |
| Hard-coded Robux in non-shop screens | PARTIALLY IMPLEMENTED. | Shop is clean; see 3.5 |

## 3.8 Final report summary

What Claude completed: audited and hardened the receipt handler and pass checks, added price-level fetch at join, the trade and gift gate with locks, live Robux prices with "Available soon" and "Price unavailable" fallbacks, the Master Shop (Premium powers, Unlock with Gems, Gem packs, Upgrades, Cosmetics), the Extra Ability Slot pass entry, and three new test files; all offline tests pass.

What AJKR must do: create the products and passes, paste their ids, set up Managed Pricing, run Dynamic Price Check in both modes, and buy every item once.

What needs testing: real purchases, Dynamic Price Check (Price pinned, Location pinned), the live GetUsersPriceLevelsAsync call on the server, and the shop in Studio.

What is blocking publication: every id is 0, so nothing can be sold; the manual tests above; remaining hard-coded Robux numbers in non-shop screens.

What remains optional: VIP, Starter Pack, a trading or gifting system, per-receipt revenue records.
