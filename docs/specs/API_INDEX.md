# SUPERNATURALS code index (generated)

One entry per source file: line count, its header comment, and its top-level functions with line numbers.
Use it to find what you need, then read only those line ranges (`sed -n 120,180p file`).

## src/shared/Protocol.luau (222 lines)
Names shared by the server and client: remote actions, event kinds, attributes and tags. Keeping them in one place stops typos from silently breaking communication.

## src/shared/Combat/DefenseMath.luau (57 lines)
The rules that judge interactive defenses: timing bars, grab escapes and dodge/block prompts. Pure functions with explicit times, so they're tested outside Roblox and the server never relies on a time the client claims.
  L10 DefenseMath.estimatePressTime(receivedAt: number, ping: number?, cap: number) | L16 DefenseMath.gradeTiming(pressAt: number, impactAt: number, perfectWindow: number, goodWindow: number) | L30 DefenseMath.newMash(required: number, deadline: number, minInterval: number) | L34 DefenseMath.press(mash: Mash, at: number) | L43 DefenseMath.escaped(mash: Mash) | L49 DefenseMath.inPromptWindow(startedAt: number?, opensAt: number, closesAt: number, allowance: number)

## src/shared/Combat/FighterState.luau (482 lines)
One fighter's combat state: attacking, blocking, dodging, stunned, knocked out. Pure logic with explicit timestamps, so the server can run it and tests can replay any situation exactly. Every timed state ends on its own: nothing here can leave a fighter stuck.
  L53 FighterState.new(id: string, config, now: number) | L62 FighterState.reset(state: State, config, now: number, protection: number?) | L91 FighterState.isStunned(state: State, now: number) | L95 FighterState.isAttacking(state: State, now: number) | L100 FighterState.isDodging(state: State, now: number) | L104 FighterState.isBlocking(state: State) | L108 FighterState.isInvulnerable(state: State, now: number) | L112 FighterState.inParryWindow(state: State, config, now: number) | L122 FighterState.isCurrent(state: State, token: number) | L127 FighterState.guardAt(state: State, config, now: number) | L137 FighterState.movement(state: State, config, now: number) | L158 FighterState.nextMovementChange(state: State, now: number) | L176 FighterState.busyUntil(state: State) | L183 FighterState.creditedAttacker(state: State, config, now: number) | L225 FighterState.startLight(state: State, config, now: number) | L260 FighterState.startHeavy(state: State, config, now: number) | L281 FighterState.startAbility(state: State, timing, now: number) | L302 FighterState.finishAbility(state: State, token: number, now: number) | L314 FighterState.extendRecovery(state: State, token: number, extra: number) | L322 FighterState.hasArmor(state: State, now: number) | L326 FighterState.useArmor(state: State) | L332 FighterState.endActive(state: State, config, token: number, landed: boolean) | L345 FighterState.finishAttack(state: State, now: number) | L355 FighterState.cancelAttack(state: State) | L366 FighterState.startBlock(state: State, now: number, canParry: boolean?) | L385 FighterState.endBlock(state: State, config, now: number) | L394 FighterState.startDodge(state: State, config, now: number) | L414 FighterState.dropProtection(state: State, now: number) | L419 FighterState.applyStun(state: State, duration: number, now: number) | L430 FighterState.damageGuard(state: State, config, amount: number, now: number) | L442 FighterState.noteAttacker(state: State, attackerId: string, now: number) | L448 FighterState.projectedCombo(state: State, config, now: number) | L455 FighterState.registerHit(state: State, config, attackerId: string, now: number) | L463 FighterState.knockOut(state: State, config, now: number) | L473 FighterState.setFrozen(state: State, frozen: boolean, config, now: number)

## src/shared/Combat/HitResolver.luau (130 lines)
Decides what happens when an attack reaches a fighter: a clean hit, a block, a guard break, a parry, or nothing (invulnerable). resolve() only looks; apply() changes the fighters' states. The server does the physical side (health, knockback) using the outcome.
  L45 HitResolver.resolve(attack, config, attacker: Side, defender: Side, now: number) | L95 HitResolver.apply(result: Outcome, config, attacker: Side, defender: Side, now: number) | L122 HitResolver.damageToDeal(result: Outcome, health: number)

## src/shared/Combat/Hitbox.luau (60 lines)
Attack geometry: who an attack can reach, and which way a fighter is facing. Pure math on Vector3s, so it behaves the same on the server and in tests.
  L11 Hitbox.flatDirection(vector: Vector3) | L28 Hitbox.inArc(origin: Vector3, look: Vector3, target: Vector3, reach: Reach) | L49 Hitbox.isInFront(position: Vector3, look: Vector3, from: Vector3, arc: number)

## src/shared/Combat/Scoreboard.luau (114 lines)
Match scores. A knockout gives the fighter who earned it +1 and the knocked-out fighter -1. Knockouts nobody earned (falling with no recent hit, resetting) only cost the victim the point.
  L21 Scoreboard.new(ids: { string }, floor: number?) | L29 Scoreboard.has(board: Board, id: string?) | L34 Scoreboard.recordKnockout(board: Board, victimId: string, creditedId: string?) | L54 Scoreboard.markLeft(board: Board, id: string) | L61 Scoreboard.remaining(board: Board) | L76 Scoreboard.ranking(board: Board) | L97 Scoreboard.leaders(board: Board)

## src/shared/Config/AdminEvents.luau (158 lines)
The owner panel's "admin abuse" events. Shared so the server (which runs each event) and every client (which draws it) agree on names and timing. Events only push around players in the lobby; anyone in a running match is left alone so fights stay fair (they...

## src/shared/Config/Audio.luau (21 lines)
Sound placeholders. These point at sounds built into Roblox (rbxasset://), so they work without uploading anything, but they are stand-ins: swap in proper combat sounds from the Creator Store by replacing the ids below. nil means silent.

## src/shared/Config/Combat.luau (191 lines)
Combat balance. Every number that tunes how a fight feels lives here, so balancing never means hunting through scripts. Times are in seconds, distances in studs, angles in degrees.

## src/shared/Config/Match.luau (72 lines)
Match rules for each mode. Times are in seconds.

## src/shared/Config/Monetization.luau (90 lines)
Every Robux purchase in the game, in one place. Prices here are what the shop shows; the amount Roblox actually charges is the price set on the Creator Dashboard, so keep the two the same (the server warns at startup when they differ).  To put an item on sa...
  L80 Monetization.passForPower(powerId: string)

## src/shared/Config/Rewards.luau (72 lines)
What fighting earns: Money, Gems and mastery XP for the power you used, plus daily challenges. Rewards are paid by the game (never wagered between players), most of them come from taking part rather than only winning, and the anti-farming rules below stop i...

## src/shared/Config/init.luau (14 lines)

## src/shared/Data/Schema.luau (521 lines)
The shape of a player's saved profile: its defaults, upgrades from older versions, repairs of missing or wrongly typed values, the safe copy the client is allowed to see, and the settings sanitizer. Pure logic with no services, so it's unit tested in Lune (...
  L298 Schema.default() | L317 Schema.sanitizeSettings(input: any, current: any) | L482 Schema.migrate(data: any) | L502 Schema.view(profile: Profile) | L516 Schema.storable(value: any)

## src/shared/Match/MatchFlow.luau (148 lines)
The life of one match: countdown, fight, sudden death, results, end. Pure logic driven by timestamps; the server calls tick() regularly and acts on the events it returns.
  L32 MatchFlow.new(mode, ids: { string }, now: number) | L42 MatchFlow.isFighting(flow: Flow) | L72 MatchFlow.tick(flow: Flow, now: number) | L99 MatchFlow.knockout(flow: Flow, victimId: string, creditedId: string?, now: number) | L116 MatchFlow.leave(flow: Flow, id: string, now: number) | L139 MatchFlow.abort(flow: Flow)

## src/shared/Powers/Ghost.luau (404 lines)
THE GHOST: spectral katana. One power: brief concealment, spectral dashes and teleports, a katana that appears in his hand the moment he attacks, energy slashes, the converging grid and Spectral Severance all belong to it. Fast and slippery, but fragile: ev...

## src/shared/Powers/MachineMaster.luau (502 lines)
MACHINE MASTER: soul fire technology. ONE character: blaster arm, guns, machinery, a fuel reservoir and supernatural BLUE soul fire. Strong at range and good at stopping projectiles, but his heaviest attacks burn fuel faster than it refills, so they can't b...

## src/shared/Powers/StrongDude.luau (357 lines)
STRONG DUDE: supernatural strength. Heavy hits, grabs, throws and ground shockwaves. Tough, but his big moves have readable wind-ups and recovery, so opponents can dodge, bait and punish him.  Ability fields (every power file uses the same ones): name, icon...

## src/shared/Powers/init.luau (300 lines)
The seven powers: where their definitions live and the rules every screen and service shares about them (degree unlocks, loadouts, ability stats per degree, combat stats). Each power's own numbers are in the file named after it next to this one.  Definition...
  L43 Powers.get(powerId: string) | L47 Powers.isPremium(powerId: string) | L52 Powers.masteryLevel(xp: number) | L63 Powers.nextLevelXp(xp: number) | L105 Powers.abilityFor(powerId: string, abilityId: string, degree: number) | L132 Powers.available(powerId: string, degree: number) | L147 Powers.degree(powerId: string, degree: number) | L155 Powers.basicFor(powerId: string?, degree: number?, formId: string?, kind: string) | L174 Powers.ultimateOf(powerId: string, degree: number) | L181 Powers.abilityOwned(powerId: string, abilityId: string, powerData: { [string]: any }?, degree: number?) | L197 Powers.defaultLoadout(powerId: string, degree: number) | L204 Powers.validateLoadout(powerId: string, degree: number, list: any, powerData: { [string]: any }?) | L245 Powers.degreeUnlocked(powerId: string, degree: number, powerData: { [string]: any }?) | L269 Powers.combatProfile(powerId: string?, degree: number?, formId: string?)

## src/shared/Progression/RewardMath.luau (136 lines)
The arithmetic behind rewards: what a match pays, which daily challenges are live today, and login streak money. Pure functions with explicit inputs (times are os.time() seconds), so the rules are tested outside Roblox.
  L11 RewardMath.dayNumber(unixTime: number) | L16 RewardMath.dailyFor(day: number) | L33 RewardMath.loginReward(streak: number) | L63 RewardMath.matchReward(input: MatchInput)

## src/shared/Seasons/Calendar.luau (116 lines)
Pure date math for working out which holiday season a date falls in. No Roblox APIs here, so it can be tested outside Studio.
  L7 Calendar.dayNumber(year: number, month: number, day: number) | L18 Calendar.weekday(year: number, month: number, day: number) | L24 Calendar.easter(year: number) | L42 Calendar.thanksgiving(year: number) | L101 Calendar.seasonFor(year: number, month: number, day: number)

## src/shared/Seasons/init.luau (273 lines)
Seasonal Sync: works out which holiday it is and holds each holiday's look. The server picks the season and shares it through a ReplicatedStorage attribute, so any script can ask Seasons.getActiveId() or listen for changes.
  L232 Seasons.getCurrentId() | L249 Seasons.getActiveId() | L257 Seasons.getTheme(id: string?) | L262 Seasons.observe(callback: (string?, any)

## src/shared/Utility/RateLimiter.luau (38 lines)
Token-bucket rate limiting: each key may act `rate` times per second on average, with short bursts up to `burst`. Used to reject remote spam.
  L12 RateLimiter.new(rate: number, burst: number) | L16 RateLimiter.allow(limiter: Limiter, key: any, now: number, cost: number?) | L33 RateLimiter.forget(limiter: Limiter, key: any)

## src/server/Bootstrap.server.luau (46 lines)
Starts every server service in a fixed order. Each service gets Init(services) to grab references to the others, then Start() to begin running.

## src/server/LuxuryCar.server.luau (126 lines)
Builds a luxury car in front of the spawn point when the game starts.

## src/server/Main.server.luau (2 lines)

## src/server/OwnerConfig.luau (13 lines)
Who can open the owner panel. Server-only: clients never see this file. The user id is the reliable check (it never changes, even if the account is renamed). The username is a backup, checked against Player.Name (the real, unique Roblox username, not the di...

## src/server/SeasonalSync.server.luau (168 lines)
Seasonal Sync: switches the game's lighting and decorations to match the current holiday, and checks every minute so live servers change over on time.

## src/server/Combat/AbilityKit.luau (617 lines)
The toolkit every power's abilities are written with. An ability handler gets a `ctx` for its cast: who's casting, the ability's numbers at the caster's degree, where they're aiming, and safe helpers for finding targets, hitting them, moving, teleporting, f...
  L32 AbilityKit.init(allServices) | L37 AbilityKit.hitFrom(spec: { [string]: any }) | L52 AbilityKit.new(fighter, runtime, def, aim, attack) | L71 AbilityKit.forFighter(fighter) | L90 AbilityKit:now() | L96 AbilityKit:alive() | L108 AbilityKit:waitUntil(time: number) | L116 AbilityKit:wait(seconds: number) | L121 AbilityKit:activeAt() | L125 AbilityKit:waitActive() | L130 AbilityKit:finish() | L138 AbilityKit:extendRecovery(seconds: number) | L146 AbilityKit:onCleanup(callback: () | L150 AbilityKit:_runCleanups() | L161 AbilityKit:own(stop: () | L170 AbilityKit:resource() | L174 AbilityKit:spend(amount: number) | L178 AbilityKit:gain(amount: number) | L183 AbilityKit:refund(share: number?) | L192 AbilityKit:fx(name: string, data: { [string]: any }?) | L203 AbilityKit:lastingFx(name: string, seconds: number, data: { [string]: any }?) | L228 AbilityKit:enemies() | L238 AbilityKit:isEnemy(target) | L242 AbilityKit:origin() | L246 AbilityKit:lineOfSight(from: Vector3, to: Vector3) | L251 AbilityKit:inArc(range: number, arc: number, origin: Vector3?, look: Vector3?) | L273 AbilityKit:inSphere(center: Vector3, radius: number, clearance: number?) | L289 AbilityKit:inBox(cframe: CFrame, size: Vector3) | L302 AbilityKit:alongLine(origin: Vector3, direction: Vector3, length: number, width: number) | L328 AbilityKit:nearestEnemy(range: number, arc: number?) | L349 AbilityKit:hit(target, spec: { [string]: any }?, extra: { [string]: any }?) | L372 AbilityKit:hitAll(targets: { any }, spec: { [string]: any }?, extra: { [string]: any }?) | L385 AbilityKit:telegraph(targets: { any }, impactAt: number) | L393 AbilityKit:push(target, direction: Vector3, horizontal: number, vertical: number, duration: number?) | L400 AbilityKit:dash(velocity: Vector3, duration: number) | L427 AbilityKit:stopDash() | L438 AbilityKit:teleport(desired: Vector3, opts: { maxDistance: number?, who: any?, facing: Vector3? }?) | L453 AbilityKit:status(target, statusId: string, duration: number, opts: { magnitude: number?, data: { [string]: any }? }?) | L462 AbilityKit:hasStatus(target, statusId: string) | L466 AbilityKit:clearStatus(target, statusId: string) | L472 AbilityKit:projectile(spec: { [string]: any }) | L485 AbilityKit:zone(spec: { [string]: any }) | L530 AbilityKit:construct(spec: { [string]: any }) | L538 AbilityKit:openCounter(duration: number, accepts: (attacker: any, hit: any, opts: any) | L551 AbilityKit:grab(target, spec: { hold: number, presses: number, offset: Vector3? })

## src/server/Powers/Ghost.luau (541 lines)
The Ghost's abilities on the server: the instant katana draw (kept in the Phase attribute so clients show or hide the blade), Phantom Veil, spectral dashes and teleports, the spectral counter, energy slashes, the slash flurry, Follow Through, the Converging...
  L109 Ghost.canUse(_, runtime, def) | L119 Ghost.tick(fighter, runtime, _, ctx) | L133 Ghost.onHit(_, _, _, _, _, ctx) | L137 Ghost.onHurt(_, _, _, _, _, ctx) | L142 Ghost.onDodge(_, _, ctx) | L148 abilities.InstantDraw(ctx) | L170 abilities.SpectralDash(ctx) | L189 abilities.PhantomVeil(ctx) | L213 abilities.SpectralCounter(ctx) | L270 abilities.ShadowStep(ctx) | L311 abilities.SlashWave(ctx) | L356 abilities.SlashFlurry(ctx) | L390 abilities.FollowThrough(ctx) | L448 abilities.ConvergingGrid(ctx) | L482 abilities.SpectralSeverance(ctx)

## src/server/Powers/MachineMaster.luau (954 lines)
Machine Master's abilities on the server: blaster bolts, a pellet cone, a shock pulse, a deflector panel and a barrier dome that stop projectiles, shooting projectiles down, a rail beam and homing missiles, and at Degree 3 the soul-fire arsenal (sweeping st...
  L149 MachineMaster.tick(fighter, runtime, dt: number) | L164 MachineMaster.canUse(_fighter, runtime, def) | L366 abilities.BlasterShot(ctx) | L385 abilities.ChargedShot(ctx) | L409 abilities.ScatterBlast(ctx) | L448 abilities.ShockPulse(ctx) | L463 abilities.DeflectorShield(ctx) | L509 abilities.Intercept(ctx) | L535 abilities.RailShot(ctx) | L578 abilities.MissileVolley(ctx) | L618 abilities.BarrierProjector(ctx) | L653 abilities.SweepingStreams(ctx) | L706 abilities.PressurizedBurst(ctx) | L744 abilities.SoulFireballs(ctx) | L813 abilities.SoulforgeDevice(ctx) | L893 abilities.BlueInferno(ctx)

## src/server/Powers/StrongDude.luau (333 lines)
Strong Dude's abilities on the server: shockwaves, grabs, a committed charge, an uppercut launcher, a stomp, throwing arena objects, the Iron Body counter stance, a travelling fissure and the World Breaker ultimate. Numbers come from Shared/Powers/StrongDud...
  L56 abilities.Groundbreaker(ctx) | L60 abilities.QuakeStomp(ctx) | L64 abilities.TitanGrip(ctx) | L98 abilities.MeteorCharge(ctx) | L137 abilities.CrushingUppercut(ctx) | L189 StrongDude.canUse(fighter, runtime, def) | L196 abilities.Heave(ctx) | L264 abilities.IronBody(ctx) | L283 abilities.SeismicFissure(ctx) | L316 abilities.WorldBreaker(ctx)

## src/server/SeasonalDecor/Build.luau (278 lines)
Building blocks shared by every holiday's decorations.
  L25 Build.part(parent: Instance, props: { [string]: any }) | L55 Build.ball(parent, diameter: number, cframe: CFrame, props) | L64 Build.cylinder(parent, height: number, diameter: number, cframe: CFrame, props) | L73 Build.ellipsoid(parent, size: Vector3, cframe: CFrame, props) | L82 Build.rod(parent, from: Vector3, to: Vector3, thickness: number, props) | L90 Build.light(part: Instance, color: Color3, range: number, brightness: number, flicker: boolean?) | L103 Build.model(parent: Instance, name: string) | L110 Build.tag(instance: Instance, tag: string) | L123 Build.groundY(x: number, z: number) | L143 Build.spot(x: number, z: number) | L153 Build.featureSpot() | L157 Build.isClear(x: number, z: number, margin: number?) | L168 Build.ring(count: number, radius: number, angleOffset: number?, margin: number?) | L184 Build.pumpkin(parent, base: CFrame, scale: number, options: { carved: boolean?, color: Color3? }?) | L234 Build.heart(parent, center: CFrame, size: number, props) | L251 Build.heartDrop(size: number) | L255 Build.present(parent, base: CFrame, size: Vector3, boxColor: Color3, ribbonColor: Color3)

## src/server/SeasonalDecor/Christmas.luau (180 lines)
Christmas: snow on the ground, a decorated tree with twinkling lights and a spinning star, presents, snowmen and candy cane lamp posts.

## src/server/SeasonalDecor/Easter.luau (125 lines)
Easter: giant painted eggs on a grassy hill, bunny statues, flower beds and little eggs hidden all over the map.

## src/server/SeasonalDecor/Halloween.luau (135 lines)
Halloween: a giant jack-o'-lantern, a little graveyard, dead trees, glowing pumpkins, purple lanterns and floating ghosts.

## src/server/SeasonalDecor/NewYears.luau (145 lines)
New Year's: a glowing countdown stage with the new year, sweeping searchlights and balloon bunches. The fireworks are launched by each player's client.

## src/server/SeasonalDecor/StPatricks.luau (117 lines)
St. Patrick's Day: a glowing rainbow with a pot of gold at each end, a giant leprechaun hat and spinning four-leaf clovers.

## src/server/SeasonalDecor/Thanksgiving.luau (148 lines)
Thanksgiving: a candle-lit harvest table, autumn trees, hay bales and a pumpkin patch.

## src/server/SeasonalDecor/Valentines.luau (84 lines)
Valentine's Day: a giant glowing heart, spinning hearts on posts, heart balloons and rose bushes.

## src/server/SeasonalDecor/init.luau (45 lines)
Builds and removes the decorations for each holiday. To add decorations for a new season, add a module next to this one and list it below.
  L20 SeasonalDecor.clear() | L27 SeasonalDecor.build(id: string)

## src/server/Services/AbilityService.luau (270 lines)
Runs abilities. A player asks (Remotes.AbilityRequest: ability id + where they're aiming); the server checks everything before anything happens: the ability belongs to the fighter's power, is equipped (or is their degree's ultimate), the degree allows it, c...
  L32 AbilityService:onUsed(callback: (any, string, any, string?) | L56 AbilityService:Init(services) | L62 AbilityService:Start() | L85 AbilityService:_aim(fighter, def, aim: any) | L111 AbilityService:_validate(fighter, abilityId: string, basic: string?) | L154 AbilityService:_flag(fighter, reason: string) | L162 AbilityService:use(fighter, abilityId: string, aim: any?, opts: { basic: string? }?) | L253 AbilityService:_scheduleFinish(fighter, attack)

## src/server/Services/AdminEventService.luau (483 lines)
Runs the owner's "admin abuse" events. The server does the physical part (pushing, pulling, freezing, low gravity, growing players) and tells every client what to draw. Only one event runs at a time, every event ends on its own, and stopping an event always...
  L51 AdminEventService:Init(services) | L58 AdminEventService:Start() | L65 AdminEventService:eligible() | L77 AdminEventService:currentId() | L82 AdminEventService:ground(position: Vector3) | L93 AdminEventService:randomSpot(spread: number) | L108 AdminEventService:blast(center: Vector3, radius: number, push: number, lift: number) | L121 AdminEventService:start(id: string, owner: Player?) | L170 AdminEventService:stop() | L186 AdminEventService:_centerFor(owner: Player?) | L207 AdminEventService:_runMeteorShower(context) | L224 AdminEventService:_runThunderstorm(context) | L237 AdminEventService:_runBlackHole(context) | L309 AdminEventService:_scheduleBlackHoleBlast(context) | L326 AdminEventService:_runIceAge(context) | L377 AdminEventService:_runLowGravity(context) | L446 AdminEventService:_runGiantParty(context)

## src/server/Services/AntiExploitService.luau (84 lines)
Guards the remotes: rate limits each player and cleans up values that came from a client before the server uses them. Clients are never trusted.
  L33 AntiExploitService:Start() | L42 AntiExploitService:allow(player: Player, channel: string) | L56 AntiExploitService:flag(player: Player, reason: string) | L69 AntiExploitService.direction(value: any)

## src/server/Services/ArenaService.luau (402 lines)
Builds the fight arenas and the training ground, hands arenas out to matches, and answers "where do I spawn?" and "is this out of bounds?". Arenas are built from parts in code; each match gets its own copy so several matches can run at once without overlapp...
  L304 ArenaService:Init() | L310 ArenaService:Start() | L317 ArenaService:reserve() | L333 ArenaService:release(arena: Arena) | L338 ArenaService:pickSpawn(arena: Arena, others: { Vector3 }) | L352 ArenaService:isOutOfBounds(arena: Arena, position: Vector3) | L363 ArenaService:clampInside(arena: Arena, position: Vector3, margin: number) | L373 ArenaService:contains(arena: Arena, position: Vector3, margin: number?) | L379 ArenaService:lobbySpawn() | L387 ArenaService:lobbyCenter() | L392 ArenaService:trainingSpawn() | L397 ArenaService:trainingDummySpots()

## src/server/Services/CharacterService.luau (406 lines)
Keeps a "fighter" record for every character that can fight: players and NPCs (training dummies, and later CPU opponents). It owns each fighter's combat state, turns that state into movement (walk speed, jumping), publishes it to clients as attributes, and ...
  L69 CharacterService:Init(services) | L74 CharacterService:Start() | L95 CharacterService:_onCharacter(player: Player, character: Model) | L147 CharacterService:register(model: Model, info: { id: string, displayName: string, player: Player?, npc: boolean?, trainingDummy: boolean? }) | L208 CharacterService:unregister(fighter: Fighter) | L230 CharacterService:onUnregistered(callback: (Fighter) | L234 CharacterService:_onDied(fighter: Fighter) | L248 CharacterService:refresh(fighter: Fighter) | L292 CharacterService:getFighter(model: Model) | L296 CharacterService:getById(id: string) | L300 CharacterService:getByPlayer(player: Player) | L304 CharacterService:all() | L312 CharacterService:isAlive(fighter: Fighter) | L323 CharacterService:onKnockout(callback: (Fighter, Fighter?) | L327 CharacterService:onSpawned(callback: (Fighter) | L332 CharacterService:setSpawnResolver(resolver: (Player) | L338 CharacterService:teleport(fighter: Fighter, destination: CFrame) | L356 CharacterService:restore(fighter: Fighter, protection: number?) | L368 CharacterService:onRestored(callback: (Fighter) | L372 CharacterService:setFrozen(fighter: Fighter, frozen: boolean) | L379 CharacterService:setCombatProfile(fighter: Fighter, profile) | L398 CharacterService:heal(fighter: Fighter, amount: number)

## src/server/Services/CombatService.luau (447 lines)
Runs attacks, blocks and dodges, and resolves every hit in the game (basic attacks, abilities, projectiles, zones, burns). Clients only *ask* (through Remotes.CombatRequest); the server checks every request against the fighter's state, times the attack itse...
  L73 CombatService:Init(services) | L84 CombatService:Start() | L109 CombatService:onHit(callback: (any, any, any, any) | L114 CombatService:canAct(fighter) | L127 CombatService:perform(fighter, action: string, payload: any?) | L180 CombatService:_dodge(fighter, payload: any?) | L204 CombatService:_runAttack(fighter, attack) | L259 CombatService:hasLineOfSight(from: Vector3, to: Vector3) | L274 CombatService:movedLegitimately(fighter, since: number) | L284 CombatService:_sweep(attacker, attack, alreadyHit: { [string]: boolean }, startedAt: Vector3) | L338 CombatService:applyHit(attacker, target, hit, opts: HitOptions)

## src/server/Services/ConstructService.luau (195 lines)
Temporary physical things powers create: barriers, walls, cages, deployed devices, interface fields. They're real parts (so they block movement and projectiles for everyone), each with a lifetime, optional health, and a cap per owner. All of an owner's cons...
  L48 ConstructService:Init(services) | L56 ConstructService:Start() | L77 ConstructService:create(owner, spec: Spec) | L140 ConstructService:destroy(construct, reason: string) | L152 ConstructService:damage(construct, amount: number) | L164 ConstructService:fromInstance(instance: Instance?) | L177 ConstructService:projectileHit(instance: Instance?, projectile) | L184 ConstructService:ofOwner(owner, name: string?) | L188 ConstructService:clearOwner(fighter)

## src/server/Services/CpuService.luau (251 lines)
CPU opponents: NPC fighters that play a power the way its definition says (preferred range, aggression, each ability's `ai` hint). They move, chain basic attacks, use abilities and ultimates, block and dodge telegraphed attacks, and answer interactive defen...
  L35 CpuService:Init(services) | L40 CpuService:Start() | L47 CpuService:run(fighter, difficultyName: string?) | L71 CpuService:stop(fighter) | L75 CpuService:_target(fighter) | L96 CpuService:_think(fighter, brain) | L205 CpuService:_respond(fighter, cue, data)

## src/server/Services/CurrencyService.luau (172 lines)
Money and Gems. Every balance change in the game goes through here: amounts must be whole, finite and non-negative, spending checks and deducts in one step (so a price can never be paid twice or overdrawn), and balances are capped. Clients never send amount...
  L68 CurrencyService:Init(services) | L72 CurrencyService:_toast(player: Player, option: (boolean | string) | L81 CurrencyService:balance(player: Player, kind: string) | L90 CurrencyService:canAfford(player: Player, price: Amounts) | L106 CurrencyService:spend(player: Player, price: Amounts, reason: string, opts: Options?) | L139 CurrencyService:add(player: Player, amounts: Amounts, reason: string, opts: Options?) | L166 CurrencyService.describe(amounts: Amounts)

## src/server/Services/DamageService.luau (71 lines)
The physical side of getting hit: losing health and being knocked back. Knockback uses a short-lived LinearVelocity on the victim's root part. The server creates it, it replicates to whoever simulates the character (the player's own client, or the server fo...
  L15 DamageService:Init(services) | L19 DamageService:damage(victim, amount: number) | L31 DamageService:push(fighter, direction: Vector3, horizontal: number, vertical: number, duration: number?) | L36 DamageService:setVelocity(fighter, velocity: Vector3, duration: number?)

## src/server/Services/DataService.luau (663 lines)
Loads, keeps and saves every player's profile (money, gems, powers, loadouts, base, settings...). A profile is locked to one server at a time, so two servers can never overwrite each other's progress. Every DataStore call retries with backoff. If saving can...
  L170 DataService:Init(services) | L174 DataService:Start() | L241 DataService:_onPlayerAdded(player: Player) | L304 DataService:_load(session: Session) | L400 DataService:_save(session: Session, release: boolean) | L477 DataService:_release(session: Session) | L510 DataService:_autosave() | L528 DataService:_saveAllOnClose() | L547 DataService:_queueView(session: Session) | L568 DataService:get(player: Player) | L574 DataService:waitFor(player: Player, timeout: number?) | L593 DataService:update(player: Player, mutator: (Schema.Profile) | L617 DataService:saveNow(player: Player) | L632 DataService:isPersistent(player: Player) | L639 DataService:onLoaded(callback: (Player, Schema.Profile) | L649 DataService:onChanged(callback: (Player, Schema.Profile) | L654 DataService:sendView(player: Player)

## src/server/Services/DefenseService.luau (514 lines)
Interactive defense: the prompts and counters that make defending more than one block key. Prompt   a telegraphed attack shows "DODGE / BLOCK"; dodging or blocking while it's up is a perfect read (no damage, attacker staggers) Mash     a grab or crushing ho...
  L66 DefenseService:onResult(callback: (any, string, string) | L91 DefenseService:Init(services) | L99 DefenseService:Start() | L129 DefenseService:_send(fighter, cue: Cue, extra: { [string]: any }?) | L150 DefenseService:_result(fighter, cue: Cue, result: string) | L159 DefenseService:_drop(fighter, cue: Cue) | L170 DefenseService:_expireLater(fighter, cue: Cue, after: number) | L179 DefenseService:prompt(target, attacker, info: { impactAt: number, ability: string?, power: string?, label: string? }) | L199 DefenseService:timing(target, attacker, info: { impactAt: number, ability: string?, power: string?, label: string?, source: string? }) | L222 DefenseService:telegraph(attacker, targets: { any }, def, impactAt: number) | L237 DefenseService:considerProjectile(fighter, projectile, timeToImpact: number) | L283 DefenseService:grab(target, attacker, info: { hold: number, presses: number, ability: string?, power: string?, label: string?, holding: (() | L320 DefenseService:_press(fighter, cue: Cue, kind: string, pressAt: number) | L331 DefenseService:cpuPress(fighter, cueId: string, kind: string) | L338 DefenseService:_redirect(fighter, cue: Cue, pressAt: number) | L384 DefenseService:awaitTiming(target, attacker, abilityId: string?) | L399 DefenseService:holdProjectile(target, projectile) | L408 DefenseService:openCounter(fighter, counter: Counter) | L412 DefenseService:closeCounter(fighter, counter: Counter?) | L418 DefenseService:hasCounter(fighter) | L427 DefenseService:intercept(attacker, target, hit, opts) | L496 DefenseService:clear(fighter)

## src/server/Services/DummyService.luau (270 lines)
NPC fighters: training dummies for practising on, and CPU opponents (whose brain is CpuService). They use the same fighter records and combat rules as players, so anything that works on a dummy works in a real fight.
  L51 DummyService:Init(services) | L58 DummyService:Start() | L85 DummyService:reserveId() | L92 DummyService:spawn(kindName: string, options: { spawnAt: () | L109 DummyService:despawn(dummy: Dummy) | L122 DummyService:_build(dummy: Dummy) | L210 DummyService:_behave(dummy: Dummy, fighter)

## src/server/Services/MatchService.luau (861 lines)
Matchmaking and match flow. Players queue for a mode; when enough are waiting, they're moved into an arena, counted down, and fight until time runs out. Knockouts score (+1 for the fighter who earned it, -1 for the one knocked out). The rules live in Shared...
  L76 MatchService:Init(services) | L87 MatchService:Start() | L147 MatchService:getMatchOf(fighter) | L152 MatchService:isCombatAllowed(fighter) | L163 MatchService:canDamage(attacker, target) | L173 MatchService:onStarted(callback: (Match) | L178 MatchService:onFinished(callback: (Match, any) | L182 MatchService:getMatch(matchId: string) | L187 MatchService:endAll() | L195 MatchService:_onRequest(player: Player, action: string, argument: any, options: any) | L292 MatchService:_stopSpectating(player: Player) | L307 MatchService:_watchable() | L345 MatchService:_rematchCount(match: Match) | L359 MatchService:_notice(player: Player, text: string) | L365 MatchService:_sendQueueStatus(modeName: string) | L381 MatchService:_joinQueue(player: Player, modeName: string) | L392 MatchService:_leaveQueues(player: Player) | L406 MatchService:_checkQueue(modeName: string) | L446 MatchService:_cpuOptions(options: any) | L472 MatchService:_startMatch(modeName: string, players: { Player }, cpu: { power: string, degree: number, difficulty: string }?) | L567 MatchService:_spawnFor(match: Match, id: string, startIndex: number?) | L583 MatchService:_update() | L621 MatchService:_holdAtSpawns(match: Match, time: number) | L638 MatchService:_handle(match: Match, events: { MatchFlow.Event }) | L673 MatchService:_onKnockout(victim, credited) | L682 MatchService:_participantLeft(match: Match, id: string) | L708 MatchService:_sendHome(match: Match, participant: Participant?) | L734 MatchService:_cleanup(match: Match) | L777 MatchService:_forEachFighter(match: Match, callback: (any) | L788 MatchService:_nameOf(match: Match, id: string) | L793 MatchService:_broadcast(match: Match, kind: string, data: any) | L809 MatchService:_results(match: Match, result: MatchFlow.Result) | L835 MatchService:_broadcastState(match: Match)

## src/server/Services/OwnerService.luau (376 lines)
The owner panel's server side. Only the accounts in OwnerConfig may use it; every request is checked here, so opening the panel with an exploit does nothing. Covers admin-abuse events, actions on players, the owner's own toggles (fly, immunity, invisibility...
  L52 OwnerService:Init(services) | L69 OwnerService:Start() | L121 OwnerService:isOwner(player: Player) | L125 OwnerService:_refreshOwner(player: Player) | L132 OwnerService:_notify(player: Player, text: string) | L136 OwnerService:_handle(owner: Player, action: string, first: any, second: any) | L199 OwnerService:_timed(model: Model, kind: string, seconds: number, undo: () | L211 OwnerService:_cancelTimer(model: Model, kind: string) | L215 OwnerService:_playerAction(owner: Player, target: any, actionId: string) | L256 OwnerService:_fighterAction(owner: Player, ownerFighter, fighter, actionId: string, index: number, count: number) | L317 OwnerService:_selfToggle(owner: Player, toggle: string, on: boolean) | L333 OwnerService:_setInvisible(model: Model, on: boolean) | L351 OwnerService:_announce(owner: Player, text: string)

## src/server/Services/PowerService.luau (835 lines)
Gives every fighter its power: which of the seven, which degree, which abilities are equipped, plus the power's resource (grit, fuel, corruption...), ultimate charge, cooldowns and look. Players choose in the Powers screen; the choice is checked here (premi...
  L74 PowerService:Init(services) | L88 PowerService:Start() | L170 PowerService:_profile(player: Player) | L176 PowerService:owns(player: Player, powerId: string) | L197 PowerService:check(player: Player, powerId: string, degree: number) | L213 PowerService:queueCheck(player: Player, modeName: string) | L226 PowerService:lock(player: Player) | L234 PowerService:unlock(player: Player) | L238 PowerService:isLocked(player: Player) | L243 PowerService:lockedSelection(player: Player) | L249 PowerService:_onRequest(player: Player, action: string, first: any, second: any, third: any) | L390 PowerService:_savedLoadout(player: Player, powerId: string, degree: number) | L403 PowerService:_equipForPlayer(fighter) | L431 PowerService:equip(fighter, powerId: string, degree: number, loadout: { string }, opts: { trial: boolean? }?) | L485 PowerService:_applyAppearance(fighter) | L506 PowerService:setForm(fighter, formId: string) | L519 PowerService:resetFighter(fighter) | L554 PowerService:_stopHandles(fighter) | L569 PowerService:_safe(callback, ...) | L578 PowerService:resource(fighter) | L582 PowerService:spend(fighter, amount: number) | L595 PowerService:gain(fighter, amount: number) | L603 PowerService:addUltimate(fighter, amount: number) | L611 PowerService:setCooldown(fighter, abilityId: string, readyAt: number) | L620 PowerService:cooldownFor(fighter, def) | L630 PowerService:refund(fighter, def, share: number) | L650 PowerService:_publish(fighter, force: boolean) | L668 PowerService:_tick(dt: number) | L692 PowerService:modifyIncoming(target, attacker, outcome, opts) | L700 PowerService:onHitResolved(attacker, target, outcome, opts) | L732 PowerService:onDodged(fighter) | L741 PowerService:basicOverride(fighter, kind: string) | L750 PowerService:readyRedirect(fighter) | L771 PowerService:commitRedirect(fighter, def) | L789 PowerService:safeSpot(who, desired: Vector3, maxDistance: number?) | L829 PowerService:nextKey()

## src/server/Services/ProgressionService.luau (350 lines)
Progression: what playing earns. After every match each player is paid Money, maybe Gems, and mastery XP for the power they used (see Config/Rewards and Shared/Progression/RewardMath), their stats are updated, and daily challenges and login streaks tick for...
  L37 ProgressionService:Init(services) | L44 ProgressionService:Start() | L117 ProgressionService:today() | L123 ProgressionService:_rollDay(player: Player, payLogin: boolean) | L149 ProgressionService:_progress(player: Player, stat: string, amount: number) | L169 ProgressionService:_claim(player: Player, challengeId: string) | L203 ProgressionService:_payMatch(match, result) | L239 ProgressionService:_payPlayer(player: Player, match, entry, won: boolean, draw: boolean, fightSeconds: number, forfeitEarly: boolean, humans, now: number)

## src/server/Services/ProjectileService.luau (429 lines)
Server-simulated projectiles: energy slashes, blaster bolts, soul-fire fireballs, thrown boulders, code packets. The server moves every projectile, checks what it touches (walls, barriers, fighters) and decides the hit; clients only draw it, predicting its ...
  L87 ProjectileService:Init(services) | L92 ProjectileService:Start() | L117 ProjectileService:spawn(owner, spec: Spec) | L165 ProjectileService:get(id: any) | L173 ProjectileService:finish(projectile, reason: string, at: Vector3?) | L192 ProjectileService:clearOwner(fighter) | L201 ProjectileService:nearby(position: Vector3, radius: number, filter: ((any) | L213 ProjectileService:redirect(projectile, newOwner, direction: Vector3) | L258 ProjectileService:_ignoreList() | L270 ProjectileService:_step(dt: number) | L401 ProjectileService:_explode(projectile, position: Vector3)

## src/server/Services/PurchaseService.luau (385 lines)
Robux purchases through Roblox's own purchase flow: game passes (premium powers) and developer products (gem packs). Nothing is granted because a client asked; passes come from Roblox's ownership check or its purchase event, products only from ProcessReceip...
  L57 PurchaseService:Init(services) | L78 PurchaseService:Start() | L107 PurchaseService:_checkPrices() | L130 PurchaseService:_checkPasses(player: Player) | L182 PurchaseService:_firePassGranted(player: Player, passKey: string) | L189 PurchaseService:_recordPass(player: Player, passKey: string) | L208 PurchaseService:_promptAllowed(player: Player) | L218 PurchaseService:_processReceipt(receipt: any) | L242 PurchaseService:_grantReceipt(receipt: any, productKey: string) | L305 PurchaseService:ownsPass(player: Player, passKey: string) | L318 PurchaseService:promptPass(player: Player, passKey: string) | L346 PurchaseService:promptProduct(player: Player, productKey: string) | L374 PurchaseService:passForPower(powerId: string) | L380 PurchaseService:onPassGranted(callback: (Player, string)

## src/server/Services/StatusService.luau (321 lines)
Status effects on fighters: slows, roots, freezes, marks, burns, shields, armor, concealment, distortion, traps, gravity changes and more. Every status has a hard maximum length (Config/Combat Statuses), ends on its own, and is cleared when its fighter is k...
  L37 StatusService:Init(services) | L42 StatusService:Start() | L66 StatusService:apply(fighter, statusId: string, duration: number, opts: { source: any?, magnitude: number?, data: { [string]: any }? }?) | L117 StatusService:remove(fighter, statusId: string) | L132 StatusService:clearAll(fighter) | L142 StatusService:has(fighter, statusId: string) | L147 StatusService:get(fighter, statusId: string) | L156 StatusService:damageTakenMultiplier(fighter) | L170 StatusService:absorb(fighter, amount: number) | L185 StatusService:_applyMovement(fighter) | L208 StatusService:_begin(fighter, status: Status) | L221 StatusService:_finish(fighter, status: Status) | L241 StatusService:_burn(fighter, status: Status) | L266 StatusService:_setConcealed(fighter, transparency: number?) | L285 StatusService:_setGravity(fighter, status: Status) | L303 StatusService:_holdInTrap(fighter, status: Status)

## src/server/Services/WorldService.luau (47 lines)
Builds the Nexus lobby when the server starts (see Server/World/Nexus.luau) and retires the template's grey baseplate and spawn, at runtime only: the place file in Studio is never changed. The gateways' prompts are handled by each player's client, which sen...
  L14 WorldService:Init(services) | L18 WorldService:Start()

## src/server/World/Nexus.luau (684 lines)
The Nexus: the lobby everyone spawns into. A round stone plaza with glowing inlaid rings, a raised dais with a floating crystal and a beam of light, statues of the seven powers, lanterns, benches, spirit trees, sky islands, and five gateways: Battle Gate (f...
  L667 Nexus.build(folder: Instance)

## src/client/Bootstrap.client.luau (36 lines)
Starts every client controller in a fixed order: Init(controllers) to grab references, then Start() to begin running.

## src/client/Main.client.luau (2 lines)

## src/client/Profile.luau (79 lines)
This client's copy of its saved data (money, gems, unlocked powers, loadouts, base, settings...). The server sends a safe copy whenever it changes; screens read it here and listen to `changed`. It's for display only: every purchase or unlock is still checke...
  L33 Profile.get() | L38 Profile.whenReady(callback: ({ [string]: any }) | L51 Profile.currency(kind: string) | L57 Profile.powerData(powerId: string)

## src/client/SeasonalEffects.client.luau (388 lines)
Seasonal Sync (player side): weather, floating sprites, fireworks, animated decorations and a welcome banner for whichever holiday the server switched on.

## src/client/Settings.luau (77 lines)
Player comfort settings. They start from the defaults below, switch to the saved values once the profile arrives, and changes are sent to the server (a second after the last change) so they're saved with the profile.
  L32 Settings.get(key: string) | L47 Settings.set(key: string, value: any)

## src/client/Controllers/AbilityController.luau (217 lines)
Turns ability presses into requests: keys 1-5 for the equipped abilities and R for the ultimate (gamepad: R1, R2, L2, D-pad up/left, D-pad down for the ultimate; touch: the ability buttons on the HUD). It works out where the player is aiming, checks the obv...
  L65 AbilityController:Init(controllers) | L70 AbilityController:Start() | L101 AbilityController:slots() | L131 AbilityController:aim() | L163 AbilityController:use(slot: any)

## src/client/Controllers/AdminEffectsController.luau (693 lines)
Draws the owner's admin abuse for everyone: running events, announcements, player auras, the owner's crown and title, and players frozen in ice. Everything here is cosmetic; the server already decided who gets pushed, frozen or grown.
  L33 AdminEffectsController:Init(controllers) | L37 AdminEffectsController:Start() | L59 AdminEffectsController:_watchEvents() | L147 AdminEffectsController:_titleCard(def) | L196 AdminEffectsController:_liveChip(def, endsAt: number) | L234 AdminEffectsController:_announcement(data) | L447 AdminEffectsController:_watchPlayers() | L621 AdminEffectsController:_watchIce()

## src/client/Controllers/CameraController.luau (70 lines)
Camera feedback for impacts: shake and a quick field-of-view punch. Both respect the player's Screen Shake setting.
  L19 CameraController:Start() | L46 CameraController:shake(strength: number, duration: number) | L58 CameraController:punch(amount: number)

## src/client/Controllers/CombatController.luau (312 lines)
Turns the player's combat inputs into requests to the server, and shows their own swings and dodges straight away so controls feel instant. The server still decides everything; if it refuses, only the cosmetic preview happened.
  L87 CombatController:Init(controllers) | L105 CombatController:_basicOverride(character: Model, root: BasePart, humanoid: Humanoid, kind: string) | L129 CombatController:Start() | L184 CombatController:light() | L221 CombatController:heavy() | L245 CombatController:setBlocking(on: boolean) | L259 CombatController:dodge()

## src/client/Controllers/DefenseController.luau (157 lines)
Shows the interactive defense prompts the server sends and turns presses into DefenseInput. The prompts sit low in the middle of the screen, below the character, so they never hide the attack itself. Prompt   "DODGE or BLOCK" with a shrinking timer: use you...
  L38 DefenseController:Init(controllers) | L42 DefenseController:Start() | L89 DefenseController:_cue(data) | L98 DefenseController:_forget(id: string) | L107 DefenseController:_rebind() | L138 DefenseController:_press(kind: string, id: string)

## src/client/Controllers/EffectsController.luau (435 lines)
Shows what the server says happened in combat: swings, hits, blocks, parries, guard breaks and dodges, plus block shields and the health bars over other fighters. Effects are cosmetic; the server already decided every outcome.
  L63 EffectsController:Init(controllers) | L67 EffectsController:Start() | L145 EffectsController:predictAttack(model: Model, kind: string, step: number, def, delay: number) | L150 EffectsController:_onAttack(data) | L163 EffectsController:_onHit(data) | L256 EffectsController:_dodgeVisuals(model: Model) | L270 EffectsController:predictDodge(model: Model) | L276 EffectsController:_setShield(model: Model, on: boolean) | L305 EffectsController:_watchFighter(model: Instance) | L336 EffectsController:_createOverhead(model: Model) | L387 EffectsController:_updateOverheads()

## src/client/Controllers/InputController.luau (112 lines)
Binds combat controls for every device: Keyboard & mouse: Left click = Light, E = Heavy, F (hold) = Block, Q = Dodge Gamepad:          X = Light, Y = Heavy, L1 (hold) = Block, B = Dodge Touch:            on-screen buttons next to the jump button The binding...
  L47 InputController:Init(controllers) | L51 InputController:Start() | L99 InputController.device()

## src/client/Controllers/OwnerController.luau (172 lines)
Owner-only client features: the owner panel (P to open), and flight (G to toggle once enabled). The panel only appears if the server marked this player as the owner, and the server re-checks every request anyway.
  L147 OwnerController:Start()

## src/client/Controllers/PowerFxController.luau (343 lines)
Draws powers for everyone: ability effects the server announces, ability wind-up poses, projectiles in flight, and each fighter's persistent power look (Machine Master's fuel cell, Corruption's spreading black, an animal form...). Everything here is cosmeti...
  L54 PowerFxController:Init(controllers) | L58 PowerFxController:Start() | L90 PowerFxController:_onFx(data) | L124 PowerFxController:_onCast(data) | L143 PowerFxController:predict(model: Model, powerId: string, abilityId: string) | L208 PowerFxController:_onProjectileSpawn(data) | L243 PowerFxController:_onProjectileUpdate(data) | L259 PowerFxController:_onProjectileEnd(data) | L269 PowerFxController:_stepProjectiles(dt: number) | L290 PowerFxController:_watchAppearance(model: Instance)

## src/client/Controllers/UIController.luau (158 lines)
Builds the interface and keeps it in sync with the server: the Shell (top bar, dock, windows, toasts) with the Play and Settings windows, the HUD, the queue pill, the match HUD and results, and server notices. Other controllers reach the pieces through UICo...
  L36 UIController:Init(controllers) | L42 UIController:Start()

## src/client/Controllers/WorldFxController.luau (102 lines)
Brings the Nexus lobby to life on this client: the crystal turns and floats, portal surfaces swirl, runes pulse and spirit fruit bob (only while the camera is nearby, to save work). Also answers the gateway prompts by sending the same requests the menus sen...
  L25 WorldFxController:Start() | L54 WorldFxController:_animate(nexus: Instance)

## src/client/Effects/Poser.luau (223 lines)
Placeholder animation: poses a character by rotating its joints (Motor6D.C0) with tweens. It works on R15 and R6 rigs and layers on top of Roblox's normal walk and idle animations. Each client poses every character locally from combat events, so everyone se...
  L84 Poser.register(name: string, pose: { [string]: { number } }) | L166 Poser.play(character: Model?, poseName: string, inTime: number, hold: number, outTime: number) | L188 Poser.hold(character: Model?, poseName: string) | L205 Poser.release(character: Model?, poseName: string)

## src/client/Effects/Vfx.luau (527 lines)
Visual and sound effects, all created locally on this client and cleaned up automatically: sparks, shockwaves, slash arcs, damage numbers, flashes, afterimages and sounds. Built from parts and particles, so no uploaded assets are needed.
  L57 Vfx.sparks(position: Vector3, color: Color3, count: number, speed: number?) | L77 Vfx.shockwave(position: Vector3, color: Color3, fromSize: number, toSize: number, duration: number) | L93 Vfx.groundRing(position: Vector3, color: Color3, fromSize: number, toSize: number, duration: number) | L106 Vfx.slash(origin: CFrame, color: Color3, radius: number, tilt: number, duration: number) | L126 Vfx.popup(position: Vector3, text: string, color: Color3, scale: number?) | L162 Vfx.flash(model: Model, color: Color3, duration: number?) | L174 Vfx.afterimage(model: Model, color: Color3) | L201 Vfx.telegraph(root: BasePart, color: Color3, duration: number) | L228 Vfx.intense() | L232 Vfx.part(props: { [string]: any }) | L252 Vfx.beam(from: Vector3, to: Vector3, color: Color3, width: number, duration: number, material: Enum.Material?) | L269 Vfx.lightning(from: Vector3, to: Vector3, color: Color3, segments: number?, duration: number?) | L284 Vfx.cone(origin: CFrame, length: number, angle: number, color: Color3, duration: number) | L300 Vfx.ring(cframe: CFrame, radius: number, color: Color3, thickness: number, duration: number, growTo: number?) | L322 Vfx.cracks(position: Vector3, radius: number, color: Color3, count: number?, duration: number?) | L351 Vfx.debris(position: Vector3, count: number, color: Color3, material: Enum.Material?, speed: number?) | L373 Vfx.orb(position: Vector3, color: Color3, fromSize: number, toSize: number, duration: number, material: Enum.Material?) | L387 Vfx.glow(at: Vector3 | BasePart, color: Color3, range: number, brightness: number, duration: number) | L406 Vfx.burst(position: Vector3, config: { [string]: any }) | L432 Vfx.ghostAt(model: Model, cframe: CFrame?, color: Color3, duration: number, material: Enum.Material?) | L465 Vfx.text3d(position: Vector3, text: string, color: Color3, size: number?, duration: number?) | L491 Vfx.screenFlash(color: Color3, strength: number, duration: number) | L504 Vfx.sound(name: string, at: Vector3 | Instance)

## src/client/Effects/AdminEvents/BlackHole.luau (135 lines)
Black Hole: a void sphere wrapped in spinning accretion rings, with light streaming into it from every direction, until it collapses and detonates in a blinding white shockwave.

## src/client/Effects/AdminEvents/Common.luau (298 lines)
Shared tools for drawing admin events on this client: temporary lighting changes that undo themselves, particle sheets that follow the camera, confetti, fireworks and ground lookups. Everything is local and cleaned up.
  L14 Common.reduced() | L19 Common.folder() | L45 Common.part(props: { [string]: any }) | L66 Common.tween(instance: Instance, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?) | L72 Common.fadeOut(instance: Instance, duration: number, goal: { [string]: any }) | L83 Common.lighting(goal: { [string]: any }, duration: number?) | L100 Common.colorGrade(props: { [string]: any }, duration: number?) | L130 Common.sheet(config: Sheet) | L168 Common.ground(position: Vector3) | L198 Common.confetti(position: Vector3, count: number, colors: { Color3 }?) | L246 Common.firework(from: Vector3, height: number, color: Color3?) | L293 Common.hue(offset: number)

## src/client/Effects/AdminEvents/DiscoInferno.luau (156 lines)
Disco Inferno: a giant mirror ball drops over spawn, covered in flickering tiles, sweeping laser beams in every colour, a light-up dance floor that changes with the beat, and the whole world pulsing through the rainbow.

## src/client/Effects/AdminEvents/Galaxy.luau (171 lines)
Galaxy Sky: night falls, a field of twinkling stars fills the sky, three rippling auroras wave overhead, planets drift past and shooting stars streak by.

## src/client/Effects/AdminEvents/GiantParty.luau (46 lines)
Giant Party: a jungle-green colour grade, confetti cannons, and the ground shaking under every giant's footsteps.

## src/client/Effects/AdminEvents/IceAge.luau (75 lines)
Ice Age: a howling blizzard, frost creeping in from the screen edges, and an icy colour grade. (Players frozen solid get their ice blocks from AdminEffectsController, which handles freezing from any source.)

## src/client/Effects/AdminEvents/LowGravity.luau (110 lines)
Low Gravity: a teal, dreamy colour grade, glowing bubbles drifting upward, and a comet trail behind every character as they bound around.

## src/client/Effects/AdminEvents/MeteorShower.luau (133 lines)
Meteor Shower: a smouldering red sky, falling embers, and blazing meteors that streak down onto glowing warning circles and explode into rock and fire.

## src/client/Effects/AdminEvents/PartyTime.luau (77 lines)
Party Time: fireworks bursting all over the sky, confetti showers, balloons floating up from the lobby, and the world cycling through the rainbow.

## src/client/Effects/AdminEvents/Thunderstorm.luau (110 lines)
Thunderstorm: the sky goes dark, rain pours, and jagged lightning bolts with forks crash down onto crackling warning circles, lighting up the world.

## src/client/Powers/Ghost.luau (1052 lines)
How the Ghost looks: ink-black mist, pale white light and a faint cyan edge. A katana built from parts (handle, guard, curved blade) sits in his right hand whenever he's attacking and fades away a few seconds after (the server's Phase attribute, plus an ins...
  L207 Ghost.onCast(kit) | L218 fx.VeilWindup(kit) | L225 fx.Veil(kit) | L237 fx.VeilBreak(kit) | L248 fx.SpectralDash(kit) | L275 fx.PhaseDodge(kit) | L286 fx.InstantDrawWindup(kit) | L298 fx.InstantDraw(kit) | L324 fx.CounterStance(kit) | L346 fx.CounterWhiff(kit) | L352 fx.CounterStrike(kit) | L375 fx.CounterEvade(kit) | L389 fx.ShadowStepMark(kit) | L412 fx.ShadowStep(kit) | L428 fx.ShadowStepFail(kit) | L436 fx.ShadowSlash(kit) | L453 fx.SlashWaveWindup(kit) | L462 fx.SlashWaveRelease(kit) | L473 Ghost.projectiles.SlashWave(kit) | L546 fx.FlurryWindup(kit) | L551 fx.FlurrySweep(kit) | L573 fx.FollowWindup(kit) | L578 fx.FollowDash(kit) | L601 fx.FollowStrike(kit) | L636 fx.GridMark(kit) | L670 fx.GridStrike(kit) | L689 fx.GridFizzle(kit) | L698 fx.SeveranceWindup(kit) | L729 fx.SeverancePass(kit) | L741 fx.SeveranceStrike(kit) | L766 fx.SeveranceFizzle(kit) | L929 Ghost.appearance(kit)

## src/client/Powers/MachineMaster.luau (1271 lines)
How Machine Master looks: industrial gunmetal machinery with cold cyan-blue energy and supernatural BLUE soul fire (never orange). A blaster arm at every degree, a shoulder missile pod and rail guides at Degree 2, and at Degree 3 the back-mounted fuel cell ...
  L288 windups.BlasterShot(kit) | L292 windups.ChargedShot(kit) | L313 windups.ScatterBlast(kit) | L319 windups.ShockPulse(kit) | L331 windups.DeflectorShield(kit) | L335 windups.Intercept(kit) | L340 windups.RailShot(kit) | L344 windups.MissileVolley(kit) | L352 windups.BarrierProjector(kit) | L357 windups.SweepingStreams(kit) | L361 windups.PressurizedBurst(kit) | L368 windups.SoulFireballs(kit) | L381 windups.SoulforgeDevice(kit) | L385 windups.BlueInferno(kit) | L391 Machine.onCast(kit) | L403 fx.ScatterFire(kit) | L417 fx.ShockPulse(kit) | L435 fx.ShieldUp(kit) | L445 fx.ShieldBlock(kit) | L458 fx.ShieldShatter(kit) | L469 fx.ShieldEnd(kit) | L476 fx.ProjectorUp(kit) | L488 fx.InterceptShot(kit) | L502 fx.InterceptMiss(kit) | L517 fx.RailCharge(kit) | L541 fx.RailFizzle(kit) | L546 fx.RailFire(kit) | L569 fx.StreamsIgnite(kit) | L586 fx.Streams(kit) | L599 fx.StreamsEnd(kit) | L613 fx.Burst(kit) | L639 fx.DevicePlaced(kit) | L654 fx.DeviceTrigger(kit) | L672 fx.DevicePulse(kit) | L683 fx.DeviceEnd(kit) | L696 fx.DeviceFail(kit) | L702 fx.InfernoIgnite(kit) | L739 fx.InfernoSweep(kit) | L752 fx.InfernoCharge(kit) | L770 fx.InfernoBlast(kit) | L790 fx.InfernoFizzle(kit) | L796 fx.InfernoEnd(kit) | L833 Machine.projectiles.Bolt(kit) | L863 Machine.projectiles.Pellet(kit) | L879 Machine.projectiles.HeavyBolt(kit) | L920 Machine.projectiles.Missile(kit) | L966 Machine.projectiles.Fireball(kit) | L1188 Machine.appearance(kit)

## src/client/Powers/StrongDude.luau (537 lines)
How Strong Dude looks: heavy, physical, earthy. Dust and rock, cracked ground, shockwaves, a glow in his fists that grows with each degree, and the huge orange-gold wind-up of World Breaker.
  L101 Strong.onCast() | L106 fx.GroundbreakerWindup(kit) | L113 fx.GroundbreakerImpact(kit) | L120 fx.StompWindup(kit) | L124 fx.StompImpact(kit) | L133 fx.GripReach(kit) | L137 fx.GripWhiff(kit) | L143 fx.GripCatch(kit) | L159 fx.GripBroken(kit) | L168 fx.GripSlam(kit) | L179 fx.ChargeWindup(kit) | L186 fx.ChargeRun(kit) | L206 fx.ChargeImpact(kit) | L215 fx.UppercutWindup(kit) | L219 fx.Uppercut(kit) | L253 fx.HeaveLift(kit) | L282 Strong.projectiles.Prop(kit) | L323 fx.IronBody(kit) | L342 fx.IronBodyCounter(kit) | L354 fx.FissureWindup(kit) | L361 fx.Fissure(kit) | L396 fx.WorldBreakerWindup(kit) | L436 fx.WorldBreakerFizzle(kit) | L442 fx.WorldBreakerImpact(kit) | L476 Strong.appearance(kit)

## src/client/Powers/init.luau (156 lines)
Finds each power's client module (how its abilities look) and builds the small `kit` every effect function gets: the caster's model and root, the power's colours and numbers, the effects library, poses, camera shake, and a way to keep long-lasting effects a...
  L33 ClientPowers.init(controllers) | L37 ClientPowers.module(powerId: string?) | L63 ClientPowers.stop(key: string) | L84 ClientPowers.kit(model: Model?, powerId: string, data: { [string]: any }?)

## src/client/UI/AbilityBar.luau (317 lines)
The ability bar above the health bar: one button per equipped ability (key hint, cost, cooldown sweep with seconds left), the ultimate with its charge filling up, and the power's resource meter. Buttons are tappable on touch and show a short explanation whe...
  L47 AbilityBar.build(row: Frame, abilities, device: ()

## src/client/UI/Components.luau (1540 lines)
Building blocks for every interface, so every window, card, button, bar and label looks and behaves the same: glass panels, fixed type sizes from the Theme, hover/press/selected/disabled states, gamepad selection and 44px touch targets.  Older code uses mak...
  L46 Components.make(className: string, props: { [string]: any }?, children: { Instance }?) | L67 Components.corner(radius: UDim?) | L71 Components.stroke(color: Color3?, thickness: number?, transparency: number?) | L81 Components.padding(top: number, right: number?, bottom: number?, left: number?) | L149 Components.panel(props: { [string]: any }?) | L170 Components.label(text: string, props: { [string]: any }?) | L207 Components.text(props: { [string]: any }?) | L238 Components.formatNumber(n: number) | L342 Components.button(text: string, props: { [string]: any }?, onClick: (() | L440 Components.setDisabled(control: GuiButton, disabled: boolean) | L445 Components.isDisabled(control: GuiButton) | L452 Components.iconTile(icon: string, size: number?, color: Color3?) | L481 Components.badge(text: string, color: Color3?) | L508 Components.divider(props: { [string]: any }?) | L523 Components.accentLine(props: { [string]: any }?) | L548 Components.list(parent: Instance, gap: number?, props: { [string]: any }?) | L562 Components.grid(parent: Instance, cellSize: Vector2 | UDim2, gap: number?) | L574 Components.scroll(props: { [string]: any }?) | L624 Components.window(props: { [string]: any }) | L767 Components.fade(root: Instance, show: boolean, info: TweenInfo, done: (() | L846 Components.card(props: { [string]: any }?) | L998 Components.tabs(parent: Instance, tabs: { TabSpec }, onSelect: (id: string) | L1109 Components.price(parent: Instance?, price: { money: number?, gems: number?, robux: number? }, props: { [string]: any }?) | L1151 Components.bar(props: { [string]: any }?, fillColor: Color3) | L1189 Components.progress(props: { [string]: any }?, color: Color3?) | L1266 Components.toggle(label: string, value: boolean, onChange: (boolean) | L1351 Components.slider(label: string, min: number, max: number, step: number, value: number, onChange: (number)

## src/client/UI/DefensePrompt.luau (324 lines)
The interactive defense cards: what the player sees when a defense prompt arrives. Each card is compact, sits low and centred, and is fully readable at a glance: what to do, which button, and how much time is left.
  L63 DefensePrompt.new(gui: ScreenGui, onPress: (kind: string, id: string) | L86 DefensePrompt:show(data) | L239 DefensePrompt:hide(id: string) | L248 DefensePrompt:pressed(id: string, at: number) | L267 DefensePrompt:result(id: string, kind: string, result: string) | L293 DefensePrompt:update(time: number, device: string)

## src/client/UI/Hud.luau (271 lines)
The player's own status at the bottom centre of the screen, from the top: ability row   empty for now; the ability bar (up to 6 buttons, 64x64) goes here vitals        name, health bar with the number inside, guard bar actions       Light, Heavy, Block and ...
  L53 Hud.build(parent: Instance, bindings: { any }, device: ()

## src/client/UI/MatchHud.luau (544 lines)
Everything shown during a match: the timer pill and a score card per fighter at the top, the knockout feed on the right (newest on top), the big countdown numbers in the middle, and the results panel at the end.
  L70 MatchHud.build(parent: Instance, onReturn: ()

## src/client/UI/OwnerPanel.luau (638 lines)
The owner panel: a glowing glass window with four tabs. EVENTS   launch admin abuse for the whole lobby PLAYERS  pick a player (or everyone) and do things to them ME       fly, immunity, invisibility, crown, auras SERVER   announcements, time of day, season...
  L479 OwnerPanel.build(parent: Instance, send: Send)

## src/client/UI/PlayWindow.luau (466 lines)
The Play window: how to fight. Mode cards on the left (Duel, Free-for-All, Practice vs CPU, Training ground), the selected mode's rules on the right with the button that queues or travels. Also owns the "searching" pill in the top bar while you wait in a qu...
  L177 PlayWindow.register()

## src/client/UI/PowersWindow.luau (663 lines)
The Powers window: choose one of the seven powers, a degree, and the abilities to take into a fight. The left column lists the powers; the right shows the chosen one: what it is and how it plays, mastery, the three degrees (and what unlocks each), every abi...
  L121 PowersWindow.register()

## src/client/UI/SettingsWindow.luau (147 lines)
The Settings window: comfort toggles on the left, audio, interface size and camera sliders on the right. Everything reads and writes through Client/Settings (which saves to the profile a second after the last change). Camera sensitivity is only stored here;...
  L67 SettingsWindow.register()

## src/client/UI/Shell.luau (1325 lines)
The app frame every lobby screen lives in: top bar   player card (avatar, name, power) on the left, Money and Gems on the right dock      vertical navigation on the left, one item per registered window windows   one open at a time, built the first time they...
  L822 Shell.open(id: string, args: any?) | L866 Shell.close() | L875 Shell.toggle(id: string) | L884 Shell.isOpen(id: string?) | L892 Shell.hasWindow(id: string) | L896 Shell.registerWindow(id: string, spec: WindowSpec) | L921 Shell.setNavBadge(id: string, text: string?) | L934 Shell.toast(message: string, kind: string?) | L1027 Shell.confirm(options: ConfirmOptions) | L1169 Shell.setMode(newMode: string) | L1184 Shell.getMode() | L1189 Shell.scale() | L1196 Shell.layer(name: string) | L1204 Shell.setPowerNames(names: { [string]: string }) | L1228 Shell.init(screen: ScreenGui, dependencies: { input: any? }?)

## src/client/UI/Theme.luau (175 lines)
The look of every interface in one place: colors, fonts, text sizes, spacing, corners and motion. Dark ink-navy glass with one electric cyan accent, violet as the second accent, gold for currency and premium. Every size here is in "design pixels" at 1280x72...

## src/character/Health.server.luau (4 lines)
Replaces Roblox's default "Health" script, which slowly regenerates health. In SUPERNATURALS, health only changes through combat (and is restored on respawn or when a match ends), so this script intentionally does nothing.

## tests/Data.spec.luau (256 lines)
Saved data: the profile's defaults, migration and repair of bad data, the client's safe view, and the settings sanitizer (Shared/Data/Schema).

## tests/Defense.spec.luau (76 lines)

## tests/FighterState.spec.luau (251 lines)

## tests/HitResolver.spec.luau (145 lines)

## tests/MatchFlow.spec.luau (209 lines)

## tests/Powers.spec.luau (158 lines)

## tests/Utility.spec.luau (54 lines)

## tests/data_test.luau (671 lines)
Runs the saved-data services for real (DataService, CurrencyService, PurchaseService) against the stand-in DataStore and Marketplace in tests/smoke/Engine.luau, with simulated players: rojo build default.project.json -o build/game.rbxl lune run tests/data_t...

## tests/harness.luau (192 lines)
Loads game modules outside Roblox, the way Roblox would load them. Modules use `require(script.Parent.Something)`; this harness fakes `script` with paths into src/, following Rojo's layout (a folder's init.luau is the folder's own module). Roblox data types...
  L102 Harness.environment(extra: { [string]: any }) | L113 loadModule(file: string, scriptRef) | L128 Harness.load(gamePath: string) | L150 Harness.runSpec(name: string, spec: (T)

## tests/integration.luau (458 lines)
Runs the real server services with simulated players, end to end: rojo build default.project.json -o build/game.rbxl lune run tests/integration.luau build/game.rbxl Two players queue for a duel, fight with real combat requests, knock each other out, respawn...

## tests/place_check.luau (149 lines)
Checks a built place file: rojo build default.project.json -o build/game.rbxl lune run tests/place_check.luau build/game.rbxl Verifies that the scripts and remotes exist with the right classes, and that every require(...) in every script points at a module ...

## tests/power_Ghost_test.luau (1035 lines)
Runs the Ghost end to end with simulated players: rojo build default.project.json -o build/game.rbxl lune run tests/power_Ghost_test.luau build/game.rbxl Two players fight Ghost against Ghost in a duel and use every ability at every degree it exists at: the...

## tests/powers_test.luau (311 lines)
Runs the power framework end to end with simulated players: rojo build default.project.json -o build/game.rbxl lune run tests/powers_test.luau build/game.rbxl Strong Dude's abilities against dummies and players, cooldowns, costs and junk requests, a grab es...

## tests/run.luau (38 lines)
Runs every tests/*.spec.luau file. From the repository root: lune run tests/run.luau Lune: https://github.com/lune-org/lune

## tests/smoke.luau (955 lines)
Runs real game code against the stand-in engine (tests/smoke/Engine.luau): rojo build default.project.json -o build/game.rbxl lune run tests/smoke.luau build/game.rbxl Covers: arenas, every holiday's decorations, the interface components, the Shell with eve...

## tests/smoke/Client.luau (190 lines)
Shared helpers for client smoke tests (tests/smoke_*.luau), so each area of the game can have its own smoke file instead of everyone editing smoke.luau: local Client = require("./smoke/Client") local t = Client.load(process.args[1]) t.check("my window build...
  L20 Client.load(placePath: string?)

## tests/smoke/Engine.luau (967 lines)
A tiny stand-in for the Roblox engine, so game code can be *run* outside Studio. Lune's roblox library gives real Instances with the real property list (setting a misspelled property or a wrong value type errors, just like Roblox); this file adds the engine...
  L60 Signal.new() | L64 Signal:Connect(callback) | L76 Signal:Once(callback) | L85 Signal:Wait() | L93 Signal:Fire(...) | L330 Engine.character(name: string) | L357 Engine.close(timeout: number?) | L512 Engine.readStore(storeName: string, key: string) | L515 Engine.writeStore(storeName: string, key: string, value) | L560 Engine.buyPass(player, passId: number) | L567 Engine.deliverReceipt(receipt) | L739 Engine.load(placePath: string) | L922 Engine.syncPositions(root) | L934 Engine.checkDeaths(root) | L952 Engine.step(game, frames: number, dt: number?)

## tests/smoke/World.luau (246 lines)
A running game for tests: loads the built place in the stand-in engine, starts every server service in Bootstrap's order, and simulates what the Roblox engine does between frames (deaths, respawns, Heartbeat). Test scripts get helpers to join players, send ...
  L12 World.start(placePath: string, configure: ((world: any)

