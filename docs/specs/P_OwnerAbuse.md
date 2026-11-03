# Task P — The owner control center and Admin Abuse v2

The owner (AJKR, Roblox user id 8722595934, username XxxXxxX_77797) wants:
- "An extraordinary Admin Abuse system... a spectacular live-event system that makes an entire
  server feel as though the laws of reality have broken."
- "A genuinely useful owner control center... ONLY for me."

## Already there (read the parts you need)
- src/server/OwnerConfig.luau: user id only. Owner access is decided ONLY by
  OwnerService:isOwner(player), meaning ownerIds[player.UserId]. Never by name, display name,
  client attribute or anything the client sends.
- src/server/Services/OwnerService.luau: AdminRequest handling, player actions (Heal, KnockOut,
  Fling, Freeze, Bring, GoTo, Giant, Tiny, Speed, auras, Kick, Ban this server), self toggles,
  announcements (TextService filtered), timed effects.
- src/server/Services/AdminEventService.luau + src/shared/Config/AdminEvents.luau + client
  src/client/Controllers/AdminEffectsController.luau: 9 events (MeteorShower, BlackHole,
  Thunderstorm, IceAge, Galaxy, DiscoInferno, LowGravity, GiantParty, PartyTime). They only push
  lobby players and leave matches alone.
- src/client/UI/OwnerPanel.luau (637 lines) + src/client/Controllers/OwnerController.luau. This
  is the current panel. It uses emoji icons; replace them.
- DataService/CurrencyService (Schema.Config.MaxCurrency = 1e9), PowerService (owns/unlock),
  ProgressionService, MatchService (matches, endAll), AntiExploitService rate limits.
- The world is now Meridian Station (ART.md "Setting"; L_Facility.md). The Garden is the lobby
  hall, and WARDEN is the station's command AI. Events should feel like the station's reality
  breaking.

## Part 1: Admin Abuse v2, the event framework (you own AdminEventService, AdminEvents config,
## AdminEffectsController; rewrite or extend them, keeping every existing event working)
- **A data-driven event framework.** Each event in config declares:
  - id, name, description, category (Spectacle, Physics, Entity, Glitch, Transformation,
    RuleChange, Boss, Chaos);
  - duration (default and min/max);
  - intensity levels (1-3, each scaling its parameters);
  - scope: "Garden" (lobby only, the default), "Everyone outside matches", or "Server" for
    cosmetic-only parts that touch match players;
  - affected-player filter: all, random N, specific players, or everyone except the owner;
  - cooldown;
  - compatibility (which events can stack);
  - a performance budget (max parts, particles and lights the event may create);
  - phases: intro (announcement, alarm or light change), main, finale, cleanup;
  - rewards for taking part (optional, small, through CurrencyService, once per event per player).

  Adding an event must mean a config entry plus a server phase module and a client visual module
  under src/server/AdminEvents/<Id>.luau and src/client/AdminEvents/<Id>.luau. No core rewrite.
- **Scheduler.** Start now, start in N seconds, a repeating rotation, or a queue. Combos: two or
  three compatible events at once, as "Chaos" presets. A server-wide cap stops two heavy events
  running at the same time.
- **Safety (mandatory):**
  - Every event fully restores what it changed: lighting, gravity, walk speed, character scale,
    terrain, parts, sounds and attributes, even if it errors, the owner leaves, or the server
    is shutting down.
  - Nothing is saved to player data except optional small rewards.
  - Players in a running match are never moved, damaged or slowed by lobby-scope events.
  - No one stays stuck: unfreeze, unscale, put back inside the Garden if out of bounds.
  - A hard stop ("Stop everything") that cleans all events within 1 second.
  - A watchdog ends any event past its max duration.
- **New events.** Build at least 10, each with a strong beginning, payoff and clear end, readable
  even when chaotic, and tasteful within the game's rating:
  1. **Containment Breach:** WARDEN alarms, red rotating lights, shutters slam, the Lantern
     flares. Echo "specimens" (harmless glowing creatures) roam the Garden for players to tag
     for a reward. Ends with a lockdown-lift announcement.
  2. **Gravity Collapse:** gravity flips to low, then sideways pulses, then a slam back down
     (lobby physics only), with floating debris visuals.
  3. **The Leviathan:** a giant cinematic entity (built from parts, very large) swims slowly
     through the air above the Garden's roof glass and peers in. The camera shakes as it passes.
     Purely visual.
  4. **Reality Glitch:** the station "tears": duplicated geometry flickers, textures swap colours,
     surfaces slide, and screens show corrupted WARDEN text. Client-side visuals that fully revert.
  5. **Lantern Overload:** the Lantern goes supernova. A shockwave knocks lobby players down
     softly and a golden rain of echo shards falls (collectible for a small reward).
  6. **Mirror World:** everything goes ECLIPSE-inverted: the colour grade inverts, players'
     reflections walk beside them as dark copies (visual), and the music reverses.
  7. **Server Boss: The Warden Prime.** A cooperative boss fight in the Garden. A giant
     WARDEN-body construct with telegraphed attacks: stomps, sweeping beams, summoned drones.
     - Every lobby player can damage it through the real combat pipeline. Read
       CombatService.applyHit and how DummyService registers NPC fighters; register the boss as
       an NPC fighter with a big health pool scaled by player count.
     - Phases at 66% and 33%.
     - Rewards scale with contribution, capped.
     - It despawns cleanly on time-up or win. Show a server-wide health bar.
  8. **Rule Change Rounds:** for N minutes the lobby's rules change ("Everyone is tiny",
     "Speed x2", "Big heads", "Moon jump", "Floor is lava" (lava pushes, never kills)). Use
     announced, visible modifiers.
  9. **Blackout Rave:** lights cut, UV strobes (respect the intenseEffects setting), lasers from
     the roof, a dance-floor grid on the plaza, and everyone gets a dance emote.
  10. **Meteor Siege v2:** the existing MeteorShower upgraded with readable impact markers,
      crater decals that fade, and a finale meteor.

  Plus a secret owner-only sequence, "The Door Opens": Door 09 rumbles, the Garden darkens and
  something knocks three times. It ends in an anticlimactic gag that matches the lore's humour.
- **Presentation:** a dramatic announcement banner style shared by all events (the event name,
  WARDEN's line, a countdown), alarm and music cues where sounds exist (rbxasset built-ins only,
  else silent), and lighting shifts restored after.
- **Client visuals** respect reducedEffects and intenseEffects. Particles and parts stay capped.
- **Purchasable lobby events:** the economy agent will let players buy a few lobby events with
  developer products. Give AdminEventService:start(eventId, opts) where opts can be
  { source = "Purchase", by = player, intensity, duration }. It returns (ok, reason, startsAt)
  and queues when another event is running, so a paid event always plays (never refuse after
  payment). Announce "<DisplayName> started <Event>!" for purchases. Owner-started and purchased
  events share the queue, and the owner can always skip ahead.

## Part 2: the Owner Control Center (you own OwnerService, OwnerPanel, OwnerController and
## OwnerConfig; rebuild the panel UI in the game's design system: Theme/Components/Shell; dark
## premium Meridian Institute "command console" look; drawn icons from src/client/UI/Icons.luau
## if present, otherwise simple shapes and text; no emoji)
- **Navigation:** a left sidebar with sections, a search box at the top that filters players,
  events and actions, keyboard shortcut F10 (owner only) to open, gamepad navigable, and
  confirmations for destructive actions (Kick, Ban, Reset profile, Remove currency).
- **Sections:**
  1. **Players:**
     - A searchable list with avatar thumbnails (Players:GetUserThumbnailAsync; if unavailable,
       initials), current area (Garden, match, base), power, level and ping.
     - Inspecting a player shows stats, currencies, powers owned, recent matches and flags.
     - Actions: the existing ones, plus teleport to or bring, spectate, mute their announcements
       (n/a), kick, ban for this server, a timed ban (saved), and unban.
     - Moderation actions are logged.
  2. **Economy:**
     - Grant or remove Money and Gems for any player in the server (yourself included), with
       quick buttons (+1K, +100K, +1M, +1B, MAX) and a typed amount. The owner can grant
       themselves any amount up to the data model's safe maximum.
     - Raise Schema.Config.MaxCurrency to 2^53 - 1 (9,007,199,254,740,991, the largest integer
       a Luau number holds exactly), and make sure every currency path clamps to it with no
       overflow, NaN or negatives: CurrencyService, Schema sanitise, DataStore JSON, and UI
       formatting with abbreviations (1.2K, 3.4M, 5.6B, 7.8T, 9Q) everywhere numbers show.
     - Changes go through CurrencyService (authoritative, saved), never client-side. Show each
       player's balance and the history of admin adjustments.
  3. **Powers:**
     - Unlock or lock any power and degree for any player (as a testing entitlement flag in the
       profile, separate from real purchases).
     - Equip any power and degree on yourself instantly, even in a match (owner override).
     - Tune balance live: pick a power and ability, edit damage, cooldown and cost multipliers
       for this server only (in memory, not saved, reset button), shown in a clear table.
  4. **Events:** Admin Abuse v2: categories, intensity, duration, scope, target filter,
     start/queue/schedule/rotation, Chaos presets, the live queue with skip and stop, and Stop
     everything.
  5. **Live ops:**
     - Announcements (filtered), a featured-content banner text for the Garden screens.
     - Server-wide reward drops (give every player in the server N Money/Gems once, logged and
       capped per hour).
     - Toggling the brainrot/anomaly content and trending events (another agent builds that
       system; read src/shared/Config/Anomalies.luau if it exists and call its service through
       a guarded require).
     - Scheduling daily-challenge overrides.
  6. **Diagnostics:**
     - Server uptime, players, matches running, memory (Stats:GetTotalMemoryUsageMb), heartbeat
       FPS, data persistence state (DataService.isPersistent), and the purchase receipt
       processing state.
     - The last 50 server errors and warnings, captured with ScriptContext.Error and LogService
       on the server and shown only to the owner.
     - A config check that runs the Powers validation and Monetization ids (shows which product
       ids are still 0).
  7. **Progression:** inspect and set a player's mastery per power, level, stats, daily
     progress, tutorial flags and lore files (for testing).
  8. **Audit:** every privileged action is recorded with the acting admin (user id and name),
     target, action, parameters, timestamp and result. Keep it in memory, plus a capped
     DataStore log (last 500) saved per action through a separate DataStore key. Filterable list.
- **Security (mandatory):**
  - Every AdminRequest action checks OwnerService:isOwner(player) on the server first.
  - Validate every argument (types, ranges, finite numbers, known ids, player exists), rate
    limit through AntiExploitService "Admin", and log refusals.
  - Never send owner-only data (other players' details, logs, configs) to anyone else.
  - The panel UI is created only after the server confirms owner status (the SNIsOwner
    attribute, set by the server). Hiding UI is not security: the server checks anyway.
- **Owner perks in the world:** an owner crown/title, a special entrance effect when AJKR joins
  ("WARDEN: Welcome back, Director."), and owner-only access to a VIP control room in the
  station, if the lobby has a suitable spot. If it doesn't, skip the room.

## Tests
- tests/admin_test.luau (tests/smoke/World.luau):
  - every event starts, runs, ends and leaves nothing behind (parts, lighting, gravity,
    attributes, scale, speed);
  - Stop everything cleans within 1 s, and the watchdog works;
  - match players are untouched by lobby-scope events;
  - combos respect compatibility, and the queue works for purchases;
  - the boss can be damaged by players, changes phase, rewards capped, and despawns cleanly;
  - an event errors halfway and still cleans up;
  - a non-owner calling every AdminRequest action is refused, including an account with the
    owner's name and a different id;
  - owner economy: grant to MAX and beyond clamps exactly at 2^53 - 1, remove below 0 clamps to
    0, NaN, inf and junk are refused, and it persists across leave and rejoin;
  - live tuning applies and resets;
  - audit entries are written.
- tests/smoke_owner.luau (tests/smoke/Client.luau): the panel builds only for the owner, every
  section and button runs, number formatting with huge values, and auditLayout at 1280x720 and
  667x375.
- Also keep tests/integration.luau's owner checks passing.

Follow CONVENTIONS.md and ART.md. Render a couple of events with the preview renderer (`setup`
scene calling the event's build functions) to check they look spectacular, not generic.
Run: unit tests, rojo build (build/owner.rbxl), place_check, smoke.luau, your two tests,
integration.luau (alone), data_test.luau, combat_test.luau. Report real results.
