# Task B — Build one power completely (definition, server behaviour, visuals, tests)

Read CONVENTIONS.md first (same folder), then the master prompt section for YOUR power
(master_prompt.md, Part III/IV, plus Part V §14 for its defense identity and Part VIII §29
for its visual identity). Rules there are binding: exactly one power (never split into
extra characters), three degrees that expand (not replace) the identity, every effect
bounded with counterplay, damage only from explicit server-validated hits.

## The framework you build on (already written and tested — READ these files first)
Reference implementation: Strong Dude. Read all three files before writing anything:
- src/shared/Powers/StrongDude.luau   — the definition format (every field is documented at the top)
- src/server/Powers/StrongDude.luau   — server behaviour using the AbilityKit `ctx`
- src/client/Powers/StrongDude.luau   — visuals using the client `kit`
Framework (read to know the exact APIs; don't rewrite them):
- src/shared/Powers/init.luau          — registry, loadout rules, degree unlocks, combatProfile, basicFor
- src/shared/Config/Combat.luau        — shared combat numbers, Statuses (with max durations), Defense, Projectiles
- src/server/Combat/AbilityKit.luau    — ctx helpers: waitActive/wait/alive/finish/extendRecovery/onCleanup/own,
                                         resource/spend/gain/refund, fx/lastingFx, enemies/inArc/inSphere/inBox/
                                         alongLine/nearestEnemy/lineOfSight, hit/hitAll/telegraph, push/dash/stopDash/
                                         teleport (validated safe spot), status/hasStatus/clearStatus, projectile, zone,
                                         construct, openCounter, grab
- src/server/Services/PowerService.luau — equip/setForm/resetFighter, resources, ultimate charge, cooldowns,
                                         hooks it calls on your server module (onEquip, onReset, tick, onHit, onHurt,
                                         modifyIncoming, onDodge, appearance, canUse), readyRedirect (def.redirect = true)
- src/server/Services/AbilityService.luau — how requests are validated before your handler runs; def.instant
- src/server/Services/CombatService.luau  — applyHit pipeline (everything that damages goes through it)
- src/server/Services/StatusService.luau  — statuses (Slow/Haste magnitude = speed multiplier, Shield magnitude =
                                         HP absorbed, Armor magnitude = damage reduction, Concealed magnitude = transparency,
                                         Gravity magnitude = share of gravity felt, Burn magnitude = damage per tick,
                                         Trapped data = { center, radius }, Mark/Sealed/Transformed are markers)
- src/server/Services/ProjectileService.luau — projectile spec (visual, speed, gravity, radius, lifetime, range, hit,
                                         tags, pierce, redirectable, interceptable, defense="Timing", explode, homing,
                                         data, onHit, onEnd); :nearby(position, radius, filter) and :finish(p, "Intercepted")
                                         for interceptions; :redirect(p, newOwner, direction)
- src/server/Services/ConstructService.luau — barriers/cages/devices (real parts; lifetime, health, caps)
- src/server/Services/DefenseService.luau — prompts/timing/mash/redirect/counters; telegraph(attacker, targets, def, impactAt)
- src/client/Powers/init.luau          — the client `kit` (model, root, colors, degree, form, data, Vfx, Poser,
                                         shake, keep, ability, attribute, isLocal)
- src/client/Controllers/PowerFxController.luau — how fx/projectiles/appearance/predict/onCast are called
- src/client/Effects/Vfx.luau          — effects library: sparks, shockwave, groundRing, slash, popup, flash,
                                         afterimage, telegraph, sound, beam, lightning, cone, ring, cracks, debris,
                                         orb, glow, burst, ghostAt, text3d, screenFlash, part, fade, reduced, intense
- src/client/Effects/Poser.luau        — poses (Poser.play/hold/release/register); add your own with Poser.register
- tests/powers_test.luau + tests/smoke/World.luau — how to run abilities end to end in tests

Basic attacks: a power (or a degree, or a form) can replace Light/Heavy with its own ability via
`basic = { Light = "AbilityId", Heavy = "AbilityId" }` (ability marked `basicOnly = true`, with its own
short cooldown acting as fire rate). Shapeshifter forms put `basic` inside `form = { ... }`.

## You own (create these; nobody else touches them)
- src/shared/Powers/<PowerId>.luau     definition (same format as StrongDude; ids listed below)
- src/server/Powers/<PowerId>.luau     server behaviour: `abilities = { [id] = function(ctx) end }` + optional hooks
- src/client/Powers/<PowerId>.luau     visuals: fx, projectiles, appearance, predict, onCast
- tests/power_<PowerId>_test.luau      end-to-end test (copy the structure of tests/powers_test.luau)
You MAY make small, additive changes to framework files if your power truly needs a capability
that doesn't exist (e.g. a new helper on AbilityKit, a new status in Combat.Statuses, an Engine
shim). Rules for that: add new functions/entries only, never change existing behaviour or
signatures, keep them generic (useful to any power), put a comment saying what needs it, and
list every such change in your report. Another agent is building a different power at the
same time and may also add things — re-read a file right before editing it, and keep edits small.

## Requirements for every power
- Definition passes tests/Powers.spec.luau (run `$T/lune run tests/run.luau`): 3 degrees, slots,
  free default loadout per degree (use `freeFrom` for abilities that come with a degree),
  ultimate on every degree (scaled by degreeScaling), every ability in abilityOrder, valid kinds/tags,
  `ai = { range, use }` on abilities and `ai = { preferredRange, aggression }` on the power (CPU
  opponents will use these), text that's short, clear and fits a card (name ≤ 20 chars,
  description ≤ 160 chars, plain English, says what it does and how to counter it).
- Every ability: real server handler using ctx (validated targets, line of sight where it
  matters, ctx:telegraph for anything with defense = "Prompt"/"Timing", statuses within caps,
  everything temporary ends on its own and through ctx:own/onCleanup), and real visuals.
- Resource: a power-specific resource with a clear name, max, regen (and drains/gains that
  fit the fantasy); costs on abilities; the strongest moves can't be sustained.
- Counterplay: readable wind-ups (telegraph), recovery after big moves, nothing unblockable
  AND undodgeable unless it has a long tell; no infinite loops; no permanent states.
- Defense identity from the master prompt §14 for your power (counter window, interception,
  form-based response, etc.) implemented through ctx:openCounter / DefenseService / projectiles.
- Visual identity from §29: distinct look you can recognise at a glance. Build effects from
  parts/particles/beams/trails (no uploaded assets). Respect kit.Vfx.reduced() (fewer particles)
  and Vfx.intense() (screen flashes only when on). Persistent appearance per degree via
  `appearance(kit)` that returns a cleanup (and works for the local player, other players and CPUs).
- Performance: bounded particle counts, no per-frame server loops per ability beyond
  what's needed (task.wait loops with sensible steps), everything cleaned up.
- Test: tests/power_<PowerId>_test.luau must equip your power on two players
  (`services.PowerService:equip(fighter, "<PowerId>", degree, loadout)`), and in a duel use
  EVERY ability at every degree it exists at, asserting real effects (damage dealt, status
  applied, projectile spawned/ended, teleport moved them, construct created and removed, form
  changed and reverted, cooldown and cost applied). Include the master prompt's minimum-test
  cases that concern your power (§38). Use `game.flatGround(0)` for teleports. Also confirm no
  errors were thrown (World's check() fails on game-code errors) and that ending the match
  leaves nothing behind (statuses, constructs, forms).
- Also run: unit tests, rojo build, place_check, tests/powers_test.luau, tests/smoke.luau.

## Design per power (follow it; you may refine numbers and add small details that serve the brief)

### Ghost  (id "Ghost") — THE GHOST, SPECTRAL KATANA. One power: invisibility, spectral movement,
teleportation, katana summoning, energy slashes, the grid attack all belong to it.
Resource "Spirit" (max 100, start 50, regen ~5/s, gain on hit). Stats: MaxHealth ~90, WalkSpeed 18,
fast katana Light chain (Instant Draw: the katana appears in his hand the moment he attacks — no
equip delay — and vanishes a few seconds after he stops; keep a "drawn until" in runtime.data and set
the Phase attribute so the client shows/hides the katana), longer reach than fists, slightly weaker
guard, better dodge (shorter cooldown).
- D1 Phantom Blade: PhantomVeil (Concealed ~2.5s, faster, broken by attacking/being hit — never
  permanent, never immune), SpectralDash (short dash with dark afterimages), InstantDraw (iaido
  quick-draw slash, fast startup), SpectralCounter (price; short counter window vs Small/Melee
  attacks only — not Grab/Massive; success = spectral evade behind the attacker + counterstrike;
  early/late = nothing; cooldown).
- D2 Shadow Step (adds): ShadowStep (short teleport to the aimed point via ctx:teleport — blocked or
  outside the arena → fails safely/refunds), SlashWave (white energy slash projectile along a visible
  trajectory), SlashFlurry (Multi-Angle Slash Flurry: several fast sweeps, each with a distinct
  trajectory, white solid-looking trails; damaging regions = the arcs, not the trails), FollowThrough
  (Momentum Continuation: usable only within ~1.2s after a slash projectile/flurry: dash behind the
  trajectory and strike; respects combo limits).
- D3 Spectral Executioner (adds): ConvergingGrid (target an area; after a readable telegraph
  (Prompt), slashes from 4+ directions cross into a grid around it; only targets still inside the
  defined radius are hit — leaving in time escapes), D3 versions: more slashes, faster chains.
- Ultimate SpectralSeverance: afterimages, multiple intersecting trajectories, final high-speed strike
  (explicit hits; "Timing" defense on the final strike), scaled per degree.
- Visuals: dark/white spectral palette (ink black, pale white, faint cyan), katana model built from
  parts (blade, guard, handle) welded to the right hand when drawn, white slash trails, afterimages.

### MachineMaster  (id "MachineMaster") — MACHINE MASTER, SOUL FIRE TECHNOLOGY. One character:
guns, blasters, machinery, soul fire, fuel reservoir, flamethrower, fireballs.
Resource "Fuel" (max 100, start 100, regen ~8/s; soul-fire channels drain per second; can't sustain
the strongest attacks). Stats: MaxHealth 100. basic = { Light = "BlasterShot" (bolt projectile,
short cooldown = fire rate), Heavy = "ChargedShot" (slower, bigger bolt) }.
- D1 Gunner: ScatterBlast (cone of pellets), ShockPulse (close-range knockback burst — the answer
  when someone gets into melee), DeflectorShield (small frontal shield construct that stops
  projectiles, limited health and duration), Intercept (price; shoots down the nearest eligible
  small projectile within range — uses ProjectileService:nearby + finish(p, "Intercepted"); costs
  fuel and cooldown; never ineligible ones: interceptable == false or Massive).
- D2 Advanced Arsenal (adds): RailShot (charged piercing beam), MissileVolley (3 homing
  mini-missiles with limited turn rate), BarrierProjector (stronger shield/interception field).
- D3 Soul Fire Arsenal (adds): back-mounted heavy fuel cell with reinforced conduits to FOUR
  dispensers/nozzles (appearance at D3). SweepingStreams (channel: blue soul fire streams swept in
  wide arcs; clearly defined damaging region (arc + range), controlled tick interval, fuel drain per
  second, readable direction, short-lived surface flame effects, recovery), PressurizedBurst (short
  concentrated close burst: staggers/creates space, recoil moves MM back; does NOT cancel every
  attack or break all defenses), SoulFireballs (four dispensers compress into fireballs that explode
  on targets/surfaces; strict lifetime), SoulforgeDevice (deploy a pulse mine / protective field;
  max 2 at once via construct limit).
- Ultimate BlueInferno: obvious activation cue, sweep soul fire through a defined region, end with a
  concentrated explosive blast ("Timing" defense on the blast), fuel requirement, clean end state.
- Soul fire is supernatural BLUE (not orange). Industrial gunmetal + cyan-blue palette. Blaster arm
  built from parts at every degree; fuel cell + conduits + 4 nozzles at D3; cold blue glow.

### Shapeshifter  (id "Shapeshifter") — ANIMAL SHAPESHIFTER (mandatory). One power, several forms.
Resource "Primal" (max 100, start 60; regenerates in human form, DRAINS while transformed; at 0
you revert). Forms are abilities with kind = "Form" and a `form = { stats = {...combat overrides...},
basic = { Light = ..., Heavy = ... }, drain = n }` table; use PowerService:setForm(fighter, formId) /
setForm(fighter, "") to change. Press a form's key in human form = transform (bounded ~0.4s
transition, vulnerable, costs Primal, shared switch cooldown so you can't flip every frame); press it
again while in that form = revert. While transformed, Light/Heavy become that animal's attacks
(Heavy = its signature move). Each form defines movement, attacks, defensive strength, hitbox
(TargetRadius), resource, duration, switching rules, vulnerability, look and sounds.
Forms evolve with degree (same ability id, degreeScaling changes name/stats/look):
- WolfForm: Wolf (fast pursuit, bite combo, Heavy = pounce-bite) → D3 Spectral Wolf (Heavy marks
  the target and a spirit wolf briefly follows them).
- HawkForm: Hawk (mobility, high jump/glide via Gravity status, Heavy = short dive) → D2 Eagle
  (better aerial control) → D3 Storm Eagle (telegraphed lightning-assisted dive, "Prompt").
- BearForm: Bear (heavy melee, damage reduction, Heavy = slam) → D2 Dire Bear → D3 Mythic Bear
  (ground impact shockwave).
- CheetahForm (price at D1): Cheetah (very fast, brief acceleration bursts) → D2 Panther (large
  feline: pounces and pursuit).
- CrocodileForm (D2+): defensive grabs (Heavy = death-roll grab, Mash escape), sturdy block.
- PhoenixForm (D3): limited aerial burst (Heavy = rise + fire nova), fragile.
Slots: D1 3 (pick 3 of 4 forms — a meaningful choice), D2 4, D3 5. Human form keeps the normal
punches. Transforming while being hit: the transition can be interrupted (cast token) and must leave
a valid state. Death/respawn/match end always reverts. Form defensive response (§14 H): fast forms
evade better (longer dodge invulnerability via stats), heavy forms brace (armor/damage reduction),
aerial forms dodge through movement.
- Ultimate PrimalAscendancy: a short sequence through animal manifestations (visual) then the apex
  form's signature attack (explicit hits, "Timing"); keep it short.
- Visuals: recognisable animal silhouettes built from parts (body, head, snout/beak, ears, legs,
  tail, wings) welded to the root while the human body is hidden (save/restore transparency;
  remember Concealed and the owner's invisibility also use transparency — use your own saved
  attribute name), smooth transformation transition (burst of fur/feathers + scale-in), form colours
  per degree (spectral blue wolf, storm eagle with lightning, mythic bear with glowing runes, phoenix
  fire). Hitbox/TargetRadius per form via stats.

### Corruption  (id "Corruption", premium = { pass = "CorruptionPower", robux = 6666, gems = 3000 })
Progressive manifestation that consumes the user's appearance and destabilises reality. NOT a
generic shadow projectile. Resource "Corruption" (0-100 meter, starts 0, slowly decays out of combat,
filled by landing hits and using abilities — not by moving; drives the visual overwrite: set the
Phase attribute 0..1 from the meter and degree). Degree 1 = corruption emerging, 2 = taking control,
3 = replacing the form. Every mechanical effect has a duration and counterplay; no indefinite stun,
no permanent loss of control, no unrestricted disabling of abilities (Sealed max 2s and only short).
- D1 Awakening: VoidStrike (short corruption strike, applies a corruption Mark), CorruptBolt (small
  projectile that marks), StaticBurst (small localized distortion: Distort for a moment), passive
  faint afterimages during fast movement (client) and the meter.
- D2 Corruption (adds): RiftBlink (short spatial blink: dissolve into black static, ctx:teleport),
  UnstableGround (zone of unstable ground: slow + ticks, defined duration), DistortionPulse (limited
  radial shockwave applying Distort: movement and ability timing), Unravel (price: detonate marks).
- D3 Absolute Corruption (adds): DistortionZone (powerful localized zone), Phantasm (afterimages
  that act as readable misdirection decoys — e.g. 2 dark clones that walk off and burst; they never
  deal unavoidable damage), Cataclysm (stronger radial strike with identifiable startup and recovery).
- Ultimate TotalSystemCorruption: the final form (duration scales by degree, e.g. 5/7/10s): void-core
  black silhouette, halo of jagged orbiting fragments, duplicated displaced outline, black energy rising,
  two luminous eye points; empowered abilities while active; then a distinct end state and recovery
  period (e.g. meter locked for a few seconds). Brief environment fractures as presentation only.
- Visuals per degree (appearance): D1 mostly normal + fine black fractures, darkened eyes, small black
  particles dissolving into static, thin afterimages; D2 blackness spreading irregularly, darker
  afterimages, distortion field; D3 nearly opaque black, fragments orbiting, black flames rising.
  Intensify with the meter (Phase) and during abilities.

### Syntax  (id "Syntax", premium = { pass = "SyntaxPower", robux = 9999, gems = 4500 })
Manipulates a fictional digital reality: precise interaction, code-like commands, interface control.
Interface elements must be readable gameplay (not a generic green hacker). Never touches anything
real (no real files/accounts/server config; only the in-game fictional domain). Resource "Processing"
(max 100, start 80, regen ~7/s).
- D1 Micro-Infrastructural Navigation: TargetLock (mark a target or point with a clear reticle; marked
  targets take bonus from Syntax's bolts and are revealed if Concealed), CodeBolt (small coded
  projectile, slight homing toward a locked target), HoloBarrier (brief holographic barrier construct),
  PacketReroute (price at D1, free from D2; `redirect = true` counter: when an eligible projectile
  approaches, the player gets a Redirect prompt; on success the server redirects it toward its
  attacker — see DefenseService.considerProjectile/_redirect; redirected projectiles can't be
  redirected again and their damage is capped; ineligible: redirectable == false (e.g. massive)).
  Also: Interface (price): interact with arena objects tagged Protocol.Tag.Interactive if any exist
  near the aim (if the arena has none, it should still do something useful and bounded, e.g. spawn a
  short-lived data node that pulses a slow).
- D2 Dynamic Code Execution (adds): CommandZone (placed zone with a visible countdown: enemies inside
  are slowed/Distorted), ConfinementField (short interface confinement: Trapped status with a
  center/radius and a visible boundary; escape condition = duration or breaking out via mash),
  ObjectOverride (temporarily alter a designated battlefield object's behaviour: e.g. turn a nearby
  arena prop into a short-lived barrier/turret; if none, build a temporary one), ExecuteChain (price:
  several modest effects in a readable combination).
- D3 Absolute Root Dominion (adds): RuleRewrite (temporarily alter ONE clearly defined rule in a
  bounded field, announced with a big holographic label, e.g. "GRAVITY = 1.8" or "SPEED = 50%"),
  Reconstruct (rebuild a designated temporary object/wall from a known state), MovementOverride (change
  movement behaviour inside a bounded field).
- Ultimate SystemOverride: takes control of a designated area, shows complex interface effects,
  clearly communicates the rule it changes and its duration (e.g. "ABILITIES LOCKED: 2s" via Sealed
  ≤ 2s inside the area), executes one coordinated strike ("Timing"), then restores everything.
- Visuals: holographic panels (SurfaceGui/BillboardGui text on neon frames), cursor reticles, code
  fragments (Vfx.text3d with monospace), precise thin lines, an emerald/teal + white palette with
  clean geometry; D3 large interface structures.

### Admin  (id "Admin", premium = { pass = "AdminPower", robux = 12000, gems = 6000 })
A playable moderator-style supernatural power: controlled authority over movement, status, effects
and the immediate battlefield. NOT a real admin role: it can never kick/ban/moderate/affect real
accounts, inventories or progression, or affect anyone outside the match. Every effect validated,
timed, with cleanup and counterplay. Command-themed names (";tp", ";freeze"...) are welcome in the
fiction. Resource "Authority" (max 100, start 60, regen ~6/s).
- D1 Moderator: Teleport (;tp short safe teleport), FreezeCommand (;freeze a target in front:
  short Freeze, "Prompt" telegraph), ForceField (;ff Shield for a few seconds), SpeedCommand
  (;speed Haste), Fly (price; short controlled flight via Gravity status + upward boost; ends on its
  own), Clone (price; a short-lived decoy that runs forward — misdirection, harmless).
- D2 Administrator (adds): Barrier (;wall temporary arena construct), Jail (;jail cage trap: Trapped
  with a visible cage construct; escape by mash or duration), GravityCommand (;gravity a target
  heavy/low for a short time), Fling (;fling: strong controlled knockback within arena bounds).
- D3 System Authority (adds): ArenaBarrier (large but bounded ring barrier for a few seconds),
  GravityField (temporary field zone), TeleportSequence (dramatic controlled teleport sequence:
  blink to up to 3 enemies and strike each — each strike an explicit hit), AreaCommand (limited
  area-wide status: e.g. ;slow all enemies within a radius briefly).
- Ultimate BanHammer: combines movement, field control and a powerful finishing knockback: leap,
  gravity field pulls in, giant hammer slam ("Timing"). Bounded, fair, telegraphed.
- Visuals: authoritative gold + white + crimson "command" motifs: floating command text, sigil rings,
  a crown/halo of light at higher degrees, clean barriers with grid lines, dramatic but readable.

## Round 2 addendum (read this; it overrides anything above that conflicts)
- Ghost and MachineMaster were mostly built by an earlier attempt that was interrupted (committed
  in 3d4effc: definition, server and client files for both, tests/power_Ghost_test.luau). For
  those two: read what exists, run the tests, and FINISH: fix every failing check (Ghost had 5:
  "Spirit starts at 50" (passive regen racing the assertion), Instant Draw ability cost, Spectral
  Dash mover, the §38 blocked-teleport test re-registering Workspace:GetPartBoundsInBox (Engine
  already implements it; set Engine hooks instead of re-registering), Spectral Severance charge),
  write tests/power_MachineMaster_test.luau if missing, then check every requirement in this spec
  and ART.md and fix what's missing or weak. Don't rewrite working code.
- Shapeshifter, Corruption, Syntax and Admin are built from scratch by their own agents.
- Another team is building Fighting System v2 at the same time (E_Combat.md: grab/throw, sweep,
  aerials, sprint strikes, charged heavy, feint, directional dodges, stamina, knockdowns, lock-on).
  Do NOT edit their files: FighterState, HitResolver, Hitbox, Config/Combat.luau (except additive
  Combat.Statuses entries), CombatService, CharacterService, CpuService, DummyService,
  CombatController, InputController, CameraController, EffectsController, Effects/Poser.luau,
  UI/Hud.luau. Your power keeps working through the existing APIs; universal v2 moves apply to
  every power automatically. If Poser.registerSequence/Poser.sequence exist when you get there,
  use them for multi-key ability animations (anticipation, strike, follow-through); otherwise use
  Poser.register/play/hold.
- Visual quality is judged against ART.md: one signature colour pair per power, three-phase
  effects (anticipation, impact, dissipation), natural-looking animation, nothing that looks
  generic or generated. Ability names and descriptions read like a real game's (no em dashes).
- Efficiency: the previous round's agents ran out of budget while reading. Use API_INDEX.md and
  targeted reads; write your files early; keep them compiling.

## Round 3 addendum: Corruption, Syntax, Admin (read this too)
The owner: "Syntax, Corruption and Admin Powers must exist as real, functional systems rather
than names displayed on a selection screen: distinctive identity, complete ability kits,
polished effects, correct damage logic, clear descriptions, working selection and activation
flows." "Make each power family recognizable before the player even reads its name." "Fire
needs to look like fire, lightning should travel and branch, energy blasts build, launch, travel
and impact, explosions communicate radius and force, energy slashes visibly cut the space they
occupy." "Ultimates may be spectacular; regular attacks must not interrupt gameplay."
- Lore (src/shared/Content/Archive.luau, read the programme files): Corruption is PROGRAMME
  ECLIPSE (the one that caused the Cascade: reflections with no source, a polite subject who
  asked every morning "is today the day"), Syntax is PROGRAMME LATTICE (Petra Lind, who reads
  reality as text and "corrects typos"), Admin Powers is PROGRAMME WARDEN (the station's own
  command protocol, which asked to be given a body). Let the kits and visuals echo that:
  Corruption = black fractures, reflections, inversion, unstable geometry; Syntax = precise
  text, corrections, rule rewrites, holographic markup; Admin = authority, commands, locks,
  doors, containment, the station obeying.
- Fighting System v2 is live (E_Combat.md / E1_report.md): every power also has universal
  grabs, sweeps, aerials, dodges and stamina. Each of the three needs its own range and movement
  profile so they don't overlap Strong Dude/Ghost/Machine Master/Grandmaster: e.g. Corruption =
  mid-range zone pressure and decay, Syntax = long-range precision and control, Admin = space
  control and authority (teleports, locks, barriers) with modest raw damage.
- Premium fairness: they're expensive passes, but must not win because they were bought; trials
  are allowed in Training and CPU Practice (existing PowerService rules). Give each a clear
  weakness the card text mentions.
- Text: names and descriptions read like a real game's (no em dashes, no emoji).
