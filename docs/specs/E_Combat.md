# Task E — Fighting System v2: fight like a real fight

The owner: "imagine you are fighting in real life, so there are so many things you can do, block
and have; think about that and execute it to the best of the best of your ability in game."

Today every fighter has: a 4-hit Light chain (M1), a Heavy (E), Block (hold F) with a parry window
and a guard meter, a Dodge (Q) with invulnerability, combo limits, knockback, launches. Powers add
abilities on top (1-5, R) and may replace Light/Heavy with their own basic attacks
(`basic = { Light = ..., Heavy = ... }`). Read the current code before changing it:
src/shared/Combat/FighterState.luau, HitResolver.luau, Hitbox.luau, src/shared/Config/Combat.luau,
src/server/Services/CombatService.luau, CharacterService.luau, CpuService.luau,
src/client/Controllers/CombatController.luau, InputController.luau, CameraController.luau,
EffectsController.luau, src/client/Effects/Poser.luau, src/client/UI/Hud.luau, and
tests/FighterState.spec.luau, tests/integration.luau.

v2 adds what a real fighter can do, while staying readable, fair and server-authoritative.
Two agents build it at the same time: E1 (server + shared rules + CPU + tests) and E2 (client:
controls, animation, camera, feel, HUD). The CONTRACT below is fixed so both can work in parallel.
Keep every existing API and behaviour working (powers and tests rely on them); extend, don't break.

## The moveset (what players can do)
Strikes
- Light string (M1): jab, cross, hook, finisher kick (the existing 4 steps; give them distinct
  names and animations). Combo damage scaling: each hit after the 3rd in a combo deals 8% less
  (floor 50%), so long combos stay fair.
- Heavy (E): tap = the existing heavy. HOLD = charge (up to Combat.Heavy.Charge.Max seconds; walk
  slows; a visible charge glow); release to swing: more damage and guard damage; a full charge
  breaks guard. Feint: press Block during a heavy's wind-up or charge to cancel it (stamina cost,
  short cooldown) — the mind game of real fights.
- Directional variants (from movement input relative to the camera/lock target):
  back + Heavy = Launcher (uppercut that launches); while sprinting: Light = Rush Strike (lunging
  punch, more reach and knockback), Heavy = Shoulder Charge (knocks down; big guard damage).
- Aerial: in the air, Light = Air Kick; Heavy = Slam (dives down; overhead: extra guard damage).
  Juggles: a launched opponent can be hit by aerials up to Combat.Air.JuggleLimit times.
- Sweep (C): low spin kick, fast, short, knocks down a standing opponent; jumping avoids it;
  blockable.
Grappling
- Grab (G; gamepad L1+X; touch button): short range, beats Block, loses to strikes (slower
  startup, whiff is punishable). On connect the victim is held briefly, then thrown forward (or
  backward if the attacker holds back), with damage and knockback. Throwing someone into a wall
  causes a Wall Splat. Throw tech: the victim presses Grab (or Light) inside Combat.Grab.TechWindow
  after being grabbed: both break apart, no damage ("TECH"). This basic grab is separate from
  power grabs (DefenseService.grab with mash escapes) and must not change them.
- Props: Grab near a light throwable (tag Protocol.Tag.Throwable, Weight 1) with no enemy in reach
  picks it up (slower walk, no blocking); Light throws it at the aim; Grab again drops it.
  Strong Dude keeps his own Heave for heavier props.
Defense
- Block (hold F) stays; parry stays (tap right before a hit). After a parry, your next Light
  inside Combat.Riposte.Window is a Riposte (bonus damage).
- Dodge (Q) becomes directional: sidestep left/right, backstep (back or no input), forward dash
  (closes distance, fewer invulnerable frames). Dodges cost stamina instead of a long cooldown
  (a short cooldown remains, so it can't be spammed). Perfect dodge: dodging inside
  Combat.Dodge.PerfectWindow before a hit would land leaves the attacker open a moment
  (slow-motion flash for the dodger on their own screen only).
- Dodge-cancel: after a Light lands, pressing Dodge during its recovery cancels it (stamina cost).
- Knockdowns: Sweep, Shoulder Charge, full-charge heavy finishers and throws knock down. Downed
  fighters get up after Combat.Knockdown.Duration with brief invulnerability; pressing Dodge
  within the tech window as you land = tech roll (quick roll away). At most one hit on a downed
  fighter (reduced damage), then they get up: no ground loops.
- Breakfall: when launched, pressing Dodge after Combat.Air.BreakfallAfter in the air recovers
  (stamina cost): escape juggles.
- Clash: if two melee attacks connect on each other inside Combat.Clash.Window, neither deals
  damage; both are pushed back with sparks ("CLASH").
Rewards for reading the opponent
- Counter hit: hitting someone during their attack's wind-up = "COUNTER" (more damage and stun).
- Punish: hitting someone during a whiffed move's recovery = "PUNISH" (more damage).
- Wall splat: knockback into a wall (any anchored, collidable, non-character part within
  Combat.WallSplat.CheckDistance along the knockback) = bounce off it, extra damage and stun.
Movement and stamina
- Sprint (hold LeftShift; gamepad L3 toggle; touch Sprint toggle): faster, drains stamina.
- Stamina (0-100, shown under health): dodge, sprint, dodge-cancel, feint, charge, tech roll,
  breakfall and grab cost it; it regenerates after a short delay. At 0 you're Winded: no dodge or
  sprint until it recovers to Combat.Stamina.WindedRecover, and blocking costs more guard.
- Lock-on (Z or middle mouse; gamepad R3; touch Lock button): camera frames you and the target,
  your character faces them, movement strafes; press again to release, flick the right stick or
  press Z while locked to switch targets (when several enemies are near). Purely client-side.
- Taunt (V; gamepad View/Select): a short taunt; finishing it unhit grants a little ultimate
  charge; you're open while doing it (getting hit counts as a counter hit).

Powers: universal moves (grab, sweep, aerials, sprint strikes, charge, feint, dodges, tech,
taunt) work for every power. If a power or form overrides Heavy with its own ability, Heavy stays a
tap (no charge) and the directional/air/sprint Heavy variants also use the override; Light
overrides likewise replace the Light variants. Form stats (Shapeshifter) scale universal moves
through the fighter's combat profile like other numbers.

## CONTRACT (both agents follow exactly)
Protocol.CombatAction (client -> server, Remotes.CombatRequest, (action, payload?)):
  existing: Light, Heavy, BlockStart, BlockEnd, Dodge
  payloads: Light/Heavy/Dodge/Grab/Sweep may carry `{ dir = Vector3 }` (flat movement intent in
  world space, magnitude <= 1; server validates and ignores junk). Heavy may carry
  `{ dir, charge = true }` = start charging (then HeavyRelease). Without `charge` Heavy is a tap.
  new: HeavyRelease, Feint, Grab, Sweep, SprintStart, SprintEnd, Taunt
  The server decides context from the fighter's state: Dodge while downed = tech roll, while
  launched in the air = breakfall; Light while carrying a prop = throw it; Grab while grabbed in
  the tech window = throw tech; Grab while carrying = drop; Light/Heavy in the air = aerials,
  while sprinting = sprint strikes, Heavy with back input = Launcher.
Protocol.CombatEvent (server -> clients, Remotes.CombatEvent):
  existing Attack payload gains `move: string` (Jab, Cross, Hook, FinisherKick, Heavy,
  ChargedHeavy, Launcher, RushStrike, ShoulderCharge, AirKick, Slam, Sweep, Grab, PropThrow) and
  `charge: number?` (0..1). Existing Hit payload gains `tags: { counter, punish, riposte,
  wallSplat, knockdown, launch, airborne, otg }` (booleans, absent = false) and
  `direction: Vector3`.
  new: Clash { a: Model, b: Model, position: Vector3 }
       Grab { attacker: Model, victim: Model?, phase: "Hold" | "Throw" | "Tech" | "Whiff", direction: Vector3? }
       Motion { fighter: Model, motion: string, direction: Vector3?, duration: number? }
         motion: Charge, Feint, Knockdown, GetUp, TechRoll, Breakfall, Taunt, TauntDone,
                 Winded, Recovered, PickUp, Drop, PerfectDodge, DodgeCancel, SprintStart, SprintEnd
Attributes on the character model (server sets, client reads):
  SNStamina (number), SNStaminaMax (number), SNSprinting (bool), SNWinded (bool),
  SNDownedUntil (server time), SNCarrying (string prop name or nil), SNChargeStart (server time
  or nil), SNAirborne (bool, launched/juggled)
  (Add the names to Protocol.Attribute as Stamina, StaminaMax, Sprinting, Winded, DownedUntil,
  Carrying, ChargeStart, Airborne.)
Config (src/shared/Config/Combat.luau; E1 adds, E2 reads; exact section names):
  Combat.Stamina = { Max, Regen, RegenDelay, WindedRecover, Costs = { Dodge, SprintPerSecond,
    DodgeCancel, Feint, Charge, TechRoll, Breakfall, Grab } }
  Combat.Sprint = { Speed, MinStamina }
  Combat.Dodge gains: PerfectWindow, PerfectPunish, Directions = { Side = {Speed, Duration,
    Invulnerable}, Back = {...}, Forward = {...} } (keep the existing fields)
  Combat.Heavy.Charge = { Min, Max, DamageBonus, GuardDamageBonus, MoveSpeed }
  Combat.Feint = { Recovery, Cooldown }
  Combat.Grab = { Range, Startup, Active, WhiffRecovery, TechWindow, Hold, Damage, BackDamage,
    Knockback, Cooldown }
  Combat.Sweep = { Damage, Startup, Active, Recovery, Range, Arc, GuardDamage, Hitstun }
  Combat.Knockdown = { Duration, TechWindow, TechRollDistance, GetUpInvulnerable,
    OTGDamageMultiplier }
  Combat.Air = { Light = {attack def}, Heavy = {attack def}, JuggleLimit, BreakfallAfter }
  Combat.Running = { Light = {attack def}, Heavy = {attack def} }
  Combat.Launcher = {attack def}
  Combat.Counter = { DamageMultiplier, ExtraHitstun }, Combat.Punish = { DamageMultiplier },
  Combat.Riposte = { Window, DamageMultiplier }, Combat.Clash = { Window, Pushback, Stun },
  Combat.WallSplat = { MinKnockback, CheckDistance, Damage, Stun },
  Combat.Taunt = { Duration, UltimateCharge, Cooldown }, Combat.Carry = { WalkSpeed, ThrowSpeed,
    Damage }, Combat.ComboScaling = { From, PerHit, Min }
  Attack defs use the same fields as Combat.Light.Steps entries (Damage, Startup, Active,
  Recovery, Range, Arc, Hitstun, Knockback, Launch, GuardDamage, Finisher, Blockable, Knockdown).
  Light.Steps entries gain `Move` names (Jab, Cross, Hook, FinisherKick).
Camera ownership: CameraController (E2) does lock-on and impact shake. Anything that takes the
  camera for a cinematic (victory screens, replays, spectating — another agent) sets
  workspace.CurrentCamera.CameraType = Scriptable; while it is Scriptable, lock-on pauses and
  does not touch the camera.
Gamepad: X Light, Y Heavy (hold = charge), L1 Block, B Dodge, A Jump, L1+X Grab, L1+Y Sweep,
  L3 Sprint, R3 Lock-on, View/Select Taunt (abilities keep R1/R2/L2/DPad). Keyboard: M1 Light,
  E Heavy, F Block, Q Dodge, G Grab, C Sweep, LeftShift Sprint, Z or middle mouse Lock-on, V Taunt.
  Disable Roblox's shift-lock (StarterPlayer.EnableMouseLockOption = false in
  default.project.json — E2 makes that one change) since Shift sprints and lock-on replaces it.

## E1 — server, shared rules, CPU, tests (you own)
src/shared/Combat/FighterState.luau, HitResolver.luau, Hitbox.luau, src/shared/Config/Combat.luau
(the sections above plus existing ones), Protocol.luau (CombatAction, CombatEvent, Attribute
additions only), src/server/Services/CombatService.luau, CharacterService.luau, CpuService.luau,
DummyService.luau (sparring dummy behaviour), AntiExploitService.luau (limits), and tests:
tests/FighterState.spec.luau, tests/HitResolver.spec.luau (extend), new tests/combat_test.luau
(end-to-end with tests/smoke/World.luau: every move, every context, every rule above, junk
payloads, stamina limits, no stuck states after death/respawn/match end, CPU uses the moves).
- Pure rules in FighterState/HitResolver with explicit times (unit-tested); the service does
  physics, validation and events. Every state ends on its own (downed, carry, charge, grab hold,
  taunt, winded). Respawn, death, match end and power changes reset everything.
- Validate everything from the client: action names, payload types, finite dir with magnitude
  <= 1.01, state legality, stamina, cooldowns; never trust client timing beyond the existing
  latency allowances.
- Grab/throw moves the victim on the server (both fighters' roots), respects arena bounds
  (ArenaService:clampInside where available), and can't carry someone out of the arena.
- CPU (CpuService): uses the new options by difficulty: strafes and spaces, mixes strings with
  grabs vs blockers, sweeps, charges heavies when the player is slow, feints on Hard, techs throws
  and knockdowns sometimes (Easy rarely, Hard often), breakfalls, punishes whiffs, parries and
  dodges telegraphs (keep the existing defense responses). Keep it beatable on Easy.
- Keep powers working: AbilityKit/ctx and PowerService hooks unchanged; abilities' hits get the
  counter/punish/wall-splat rules through applyHit where it makes sense (melee and knockback
  hits), never break their own rules.

## E2 — client controls, animation, camera, feel, HUD (you own)
src/client/Controllers/InputController.luau, CombatController.luau, CameraController.luau,
EffectsController.luau, src/client/Effects/Poser.luau (keep register/play/hold/release working;
add sequences), src/client/UI/Hud.luau (stamina bar, charge meter, winded state, lock reticle),
src/client/Settings.luau (add lockOnMode "toggle" | "hold" with default), the Settings window
row for it (src/client/UI/SettingsWindow.luau), default.project.json (EnableMouseLockOption only),
and new tests/smoke_combat.luau (use tests/smoke/Client.luau helpers).
- Animation: upgrade Poser into keyframed sequences: Poser.registerSequence(name, { {t, pose,
  easing?}, ... }) and Poser.sequence(character, name, speed?) with anticipation and follow-through,
  body weight (root lowers on heavies, hips twist into punches), upper-body layering while moving,
  and procedural hit reactions (directional flinch away from the hit, stagger on guard break,
  knockdown fall/lie/get-up, tech roll, breakfall flip, grab clinch and throw for both fighters,
  sweep spin kick, air kick, slam dive, rush strike, shoulder charge, charged-heavy wind-up with a
  tremble, feint pull-back, parry deflect, block stance, winded (hands on knees), 2-3 taunts).
  Distinct poses for jab/cross/hook/finisher kick. Animations must look natural: ease in/out,
  overshoot, no robotic linear snaps; durations match the server's Startup/Active/Recovery.
  They must work on players, other players and CPUs (driven by CombatEvent), and stop cleanly.
- Feel: hitstop (40-90 ms on heavier hits: pause both fighters' poses), camera kick scaled by
  impact and the cameraShake setting, impact sparks by result (block, parry, counter, punish,
  wall splat, clash, tech), short text popups in the design system's style (no emoji).
  Perfect dodge: a brief slow-motion tint and whoosh on the dodger's own screen.
- Controls: bindings above for keyboard, gamepad and touch. Touch: a clean right-side cluster
  (Light biggest; Heavy, Block, Dodge, Grab around it; Sweep, Sprint, Lock smaller), not covering
  the ability row or joystick; 44 px minimum; works at 667x375. Send `dir` from
  Humanoid.MoveDirection (flat). Predict your own animations instantly; the server stays the judge.
- Lock-on camera: smooth, framed over the shoulder, keeps both fighters in view, never clips into
  walls badly (raycast and pull in), releases on target death/leaving/out of range, pauses while
  the camera is Scriptable (cinematics) and in the Editor/Cinematic Shell modes.
- HUD: stamina bar under health (thin, clear colour change when low/winded), charge meter near the
  crosshair/character while charging, lock-on reticle over the target, and a compact controls
  hint strip that matches the device (keyboard/gamepad/touch) — all text fits its boxes.

## Both
Follow CONVENTIONS.md and ART.md. Run: unit tests, rojo build (your own output file), place_check,
smoke.luau, your smoke/combat test, integration.luau, powers_test.luau. Report real results.
