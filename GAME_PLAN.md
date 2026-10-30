# One Gun, Infinite Upgrades: Game Plan

Single-player incremental arena FPS. One weak pistol, waves of robots, credits buy permanent
upgrades until the pistol is absurdly strong. Built in Godot 4.3 (GDScript).

The full design (gunsmith slots, loot and crafting, skill trees, Reforge prestige, procedural
arena, story, bullet simulation, eight milestones) lives in the plan document in the project.
This file tracks what is built, the decisions that shape the code, and the next step.

## Milestone status

| Milestone | Status |
| --- | --- |
| 1. Shooting prototype | Merged. |
| 2. Incremental prototype | Merged. Playtest answers (first upgrade inside two minutes, loop fun on its own) still wanted. |
| 3. Gunsmith, loot and projectiles | Built, automated checks pass, Reforge simulation hits its targets. **Waiting for Jacob's playtest: does a new player reach the Warden unguided and equip a drop on purpose?** |
| 4. Crafting and the Scrapyard | Not started. The Reforge gate is passed, so it may start after the M3 playtest. |
| 5. Skills, story and full roster | Not started |
| 6. Procedural arena | Not started |
| 7. Reforge | Not started |
| 8. First release | Not started |

## What Milestone 3 contains

- **Gunsmith:** receiver, barrel and magazine slots open from the first bench; muzzle and ammo
  open when the Warden falls (wave 5); optic and underbarrel after the wave 10 clear. Nine bases
  (`data/attachments/`): Semi-auto, Automatic (wave 5), Burst (wave 10); Standard, Long and
  Penetrator barrels; Standard, Extended and Fast magazines. Each base changes the pistol model
  (slide length, barrel extension, grip height).
- **Loot:** per-kill rolls, Common 1 in 12 and Uncommon 1 in 50 (drones count half), one Uncommon
  per first clear, the Warden a Rare. Drops are beams on the floor with a label; walking over one
  picks it up, a clear collects what is left, death loses it. Affixes with rolls per rarity, marks
  I to V scale a base's upside up and its cost down by 15% a step.
- **Inventory:** 40 cells plus a 20-cell overflow tray. When both are full a new item bumps the
  oldest lesser unlocked tray item or is dismantled for parts (Common: Scrap; Uncommon: Alloy and
  Scrap; Rare: Circuits and Alloy). Lock, dismantle, dismantle all unlocked Commons, move from the
  tray. The compare view shows every stat change and the behaviour change before equipping.
- **Enemies:** shooter (wave 4: keeps 11 m, telegraphs, fires a 16 m/s bolt), swarm drone (wave 7:
  12 health, flies at head height, counts half in the alive cap), the Warden boss (wave 5: 450
  health, charge and ground slam, boss bar), on a shared `Enemy` base class. Ten authored waves.
- **Projectiles:** one pooled system (`ProjectilePool`) for enemy bolts and player ammo types:
  swept raycast per tick so nothing tunnels, 200 live rounds cap, profiles bolt, shell, ricochet,
  charge. Player rounds resolve hits through the same `ShotPipeline` as hitscan rays.
- **Interaction rules** from the plan, in `ShotPipeline` and `WeaponStats`: receiver sets shots per
  pull, muzzle sets rays, each ray pierces then bounces then stops, pierce keeps 75% per enemy and
  a bounce 80%, at most six enemy hits per ray, on-hit procs on direct hits only, ammo refund
  once per shot, chains go one hop at half damage within 6 m.
- **Firing Range** (side area, opens after wave 2): five dummies at 8 to 28 m with live readouts
  (last hit, damage per second), a loot preview wall, and an eight-target gallery with a par time
  that pays one Uncommon of a chosen slot once.
- **Save file** version 3 (inventory, tray, parts, loot stream state, range record), migrating
  from 1 and 2. If `user://` is not writable the game keeps saving in memory and says so.
- **Reforge simulation** (`tests/reforge_sim.tscn`): the plan's prototype gate, run in CI.
- **Browser performance pass** (after Jacob reported lag and stutter in the browser, 30 Oct):
  pooled effects, shader warm-up, web-specific render defaults, and video options with an FPS
  readout. See the decision below.

## Reforge simulation: what it says

Three consecutive resets after a first run, with the real stats function, cost curves, loot
tables and inventory rules, a greedy buyer (most sustained damage per second per credit), and
the plan's budget for the systems not built yet (skills about 1.3x damage after a run, kept
gear refined one mark per run, Forge nodes bought with two tokens per Reforge). Waves 11 to 20
are extrapolated from 6 to 10 with bosses at 15 and 20.

| Tier | Shots to kill a chaser, wave 1 | By wave 5 | Recover previous damage per second | Minutes to next Reforge |
| --- | --- | --- | --- | --- |
| 0 (first run) | 4 | 2 | - | 106 |
| 1 | 6 | 1 | 9.5 min | 77 |
| 2 | 6 | 1 | 9.1 min | 75 |
| 3 | 5 | 1 | 8.7 min | 73 |

Targets: 5 to 7 shots at wave 1 of tier 1 (later tiers 3 to 7), recovery under 10 minutes, 60
to 90 minutes to the next Reforge, first run 100 to 120. All hit. Two things to know:

- **Minutes are anchored, not predicted.** Real combat runs slower than kill arithmetic, so a
  single pace multiplier (`COMBAT_PACE` 3.0) plus 20 minutes of side content per tier and
  first-run learning time are fitted to the plan's 100 to 120 minute first run. Shots to kill
  and recovery do not depend on that knob; the Reforge minutes do. Refit it from the
  `wave_cleared` seconds in the playtest log once real runs exist.
- **The plan's Forge node changed.** "10 free damage levels" one-shots wave 1 from tier 2 on,
  because a damage level is worth 2.5x more each tier. The simulated node ("Head start") grants
  one starting damage level per Reforge tier beyond the first, per rank. With it, wave 1 of
  every tier stays at 5 to 7 shots. Without any tier-scaling grant, tier 2 opens at 14 shots and
  tier 3 at 33, since kept gear is percentages on a 10-damage base while health is 2.5x per
  tier. The gate's real finding: Reforge needs one source of power that scales with the tier,
  and the Head start node is the cheapest one.

Recovery sits close to its limit (8.7 to 9.5 minutes) and the gun reaches one shot per chaser
by wave 5 of every later tier, both because the buyer spends every credit on damage per second.
A person buys worse and dies more; both move recovery up and the wave 5 number toward the
plan's 3.

## Decisions

- **Engine:** Godot 4 with GDScript. Developed and checked against Godot 4.3 stable.
- **Renderer:** Compatibility (OpenGL / WebGL 2), because the browser build requires it. Desktop uses
  the same renderer, so both builds look the same.
- **Browser build:** every push runs the smoke test and the Reforge simulation, exports the Web
  preset (no threads, so no special server headers), and deploys to the Cloudflare Pages project
  `onegun`. `main` is production; other branches get preview URLs. Workflow: `.github/workflows/web.yml`.
- **Mouse capture:** browsers only lock the mouse after a click. The bench's Start button is that
  click. If capture still fails the HUD shows "Click to play" and the wave waits. Losing capture
  (Esc in a browser, alt-tab) pauses.
- **Temporary touch controls** (`scenes/ui/touch_controls.tscn`) for testing the browser build on
  phones. They appear on the first touch and turn off mouse input, since browsers also report taps
  as clicks. They are a testing aid, not the final mobile design.
- **UI scaling:** the window uses `canvas_items` stretch with `expand`, so the HUD keeps its size
  relative to the screen on high-DPI phones and large monitors.
- **Starting any encounter resets it.** The main scene is loaded once; starting a wave clears
  enemies, projectiles and floor loot, revives the player at the start marker and hands the pistol
  a freshly built stats object. Side areas swap the arena node for the area scene and swap it back.
- **The bench pauses the tree.** It runs with `process_mode` Always, like the pause menu, so
  nothing moves while the player shops. Esc only pauses during a wave or in an area.
- **Progression is an autoload** (`scripts/progression/progression.gd`). It owns credits, core
  levels, wave progress, inventory, tray, parts, equipped build, the loot stream, records, and the
  save. Rewards commit when earned; the bench writes the save (also after each purchase and equip).
- **Weapon stats are derived, never mutated.** `WeaponStats.build(base, core_levels, equipped,
  skills, forge, tier)` sums flat modifiers, then additive percentages per stat, multiplies once and
  clamps to the base's limits and the absolute caps (15 shots/s, 50% crit, pierce 4, rays 4,
  bounces 2). Behaviours merge in slot order so the result never depends on save order.
  `WeaponStats.resolve_shot(build, context, rng)` turns a build plus a per-hit context (distance,
  charge, health fraction, Overclock, Bullet Time, pierce index, bounce index) into one hit's
  damage and crit. Combat, projectiles, the bench, the compare view, the Firing Range readouts and
  the Reforge simulation all call the same two functions.
- **Damage falls off with distance** (full to 20 m, down to 60% at 45 m by default) so the range
  stat means something; the bench shows damage at 10, 25 and 40 m.
- **Reload is bought as speed:** reload percentages divide the time. Crit chance is a fraction, so
  its modifiers add percentage points rather than multiplying.
- **Core tuning is data:** one `CoreTuningDefinition` per stat in `data/core_tuning/`. Damage per
  level is multiplied by 2.5 per Reforge tier (`scales_with_tier`), the plan's budget rule.
- **Items are small dictionaries** so they save as plain JSON: base id, rarity, affix list with
  rolls in [0, 1], mark I to V, lock flag, uid. Unknown base or affix ids are dropped on load with
  a warning, never a crash. Affixes that no system reads yet (`lingering`, `precise`) are marked
  `drops = false` so they never roll.
- **The loot stream is seeded** per save and its state is stored in the save as a string (JSON
  would mangle a 64-bit state as a double), so a reload continues the same sequence.
- **Slot gates:** the plan's answer (receiver, barrel, magazine open from the start) replaces
  Milestone 2's wave 3 gate. Burst is gated by the wave 10 clear until the Foundry exists (M4).
- **Rarity ceilings for now:** the Warden drops a Rare on first and replay kills; Epics arrive
  with the armoured enemies and crafting in Milestone 4.
- **Waves are data:** `WaveDefinition` with timed `SpawnGroup`s, an alive cap (drones count 0.5,
  the Warden 2), and a completion bonus (doubled on boss waves). Scaling: per-kill credits and
  enemy health step 1.6x per five waves, 2.5x per Reforge tier; completion bonuses step with the
  Reforge tier only.
- **Enemies share one base class** (`scripts/enemies/enemy.gd`: spawn-in, navigation, line of
  sight, hits, death, credits, drops) and differ in `_behave`. Enemy stats are `EnemyDefinition`
  resources. Runners reuse the chaser scene with their own definition.
- **Projectiles are pooled movers, not bodies.** Each tick a round raycasts the segment it would
  cross, so a 600 m/s bolt still stops at a 1 m wall. Enemy bolts hit world and player; player
  rounds hit world and enemies, pierce, bounce and proc like hitscan rays.
- **Save format:** JSON with a version number; 1 and 2 migrate to 3. An unknown version or
  unreadable file starts fresh and keeps `user://save.backup.json`. A storage probe at start
  falls back to in-memory saves with a bench warning.
- **Physics layers:** 1 world, 2 player, 3 enemies (Firing Range targets sit on 3 too).
- **Navigation:** the arena bakes its navmesh from static colliders at load.
- **Firing input** is buffered for 0.12 s so a click just before the gun is ready still fires; a
  pull during a burst or its pause is held until the gun can fire again.
- **Melee is dodgeable:** chasers stop, glow for 0.45 s, then hit only if you are still within
  reach. The Warden's slam only hits grounded players inside its ring; a jump escapes it.
- **Settings** (sensitivity, FOV, camera recoil, damage numbers, volume, render scale, shadows,
  glow, FPS readout) save to `user://settings.cfg`.
- **Web build performance.** The browser build runs on one thread (no SharedArrayBuffer, so no
  thread support) on whatever GPU the browser exposes, and its canvas follows the device pixel
  ratio, so a high-DPI screen renders four times the pixels. Two kinds of cost were found in the
  code: steady GPU load (glow, 4x MSAA, four-split 4096 shadows at full device resolution) and
  hitches (every shot allocated a tracer mesh, material and node; every hit a Label3D; every
  death a particle emitter with a new mesh; every projectile a new capsule; and the first use of
  each effect, enemy and drop material compiled a shader mid-wave, since the web has no shader
  cache). What changed: on the web, glow and MSAA are off and the directional shadow is one
  2048 split with hard filtering (`project.godot` `.web` overrides, the Sun's shadow mode); the
  3D view renders at `Settings.render_scale`, which on the web defaults to the inverse of the
  device pixel ratio (the HUD stays sharp; confirmed under xvfb that bilinear scaling works on
  the Compatibility renderer); tracers, impacts, damage numbers and death bursts come from
  `FxPool` with shared meshes and materials and fixed caps (24/24/24/8, oldest recycled);
  projectile capsules are cached by radius; `FxPool.warm_up` draws one of every effect, enemy
  and drop under the floor during the first bench so the shaders compile there; physics catch-up
  is capped at four steps per frame so a slow frame cannot spiral. The pause menu has Render
  scale, Shadows, Glow and Show FPS (average and worst frame per half second) so a tester can
  isolate GPU load (render scale helps) from hitches (the worst-frame number spikes). Not
  measured in a browser from here; Jacob's readout decides.
- **Tests are split into cases** (`tests/cases/`): stats, loot, combat, bench. The smoke test
  driver runs their unit checks before the scene and their scene checks on the running game.
- All art and audio are generated placeholders, named `placeholder_*`. New enemies and the loot
  reuse the existing sounds with pitch changes.

## Starting tuning values (not balance)

- Pistol: 10 damage, 4 shots/s, 10-round magazine, 1.4 s reload, falloff 20 to 45 m to 60%.
  Limits: 15 shots/s, 0.3 s reload.
- Core tuning per level: damage +2 (20 credits), fire rate +6% (35), magazine +1 (25, cap 50 levels),
  reload speed +8% (30). Every price grows 15% per level.
- Bases: Automatic -8% damage, +25% recoil; Burst +15% damage, -12% fire rate, 3-round bursts
  80 ms apart; Long barrel +15% damage, +35% range, -15% fire rate; Penetrator -10% damage,
  pierces 2; Extended magazine +50% rounds, -20% reload speed; Fast magazine +30% reload speed,
  -25% rounds. Affixes: Sharp (damage), Rapid (fire rate), Deep (rounds), Quick (reload), Keen
  (crit chance), Brutal (crit damage), Piercing, Thrifty (ammo refund), Arcing (chain on crit).
- Enemies: chaser 40 health, 5 credits; runner 20, 4; shooter 30 health, 10 bolt damage, 6
  credits; swarm drone 12 health, 5 damage, 2 credits; Warden 450 health, 22 melee, 28 charge,
  30 slam (5.5 m ring, 1.1 s telegraph), 80 credits.
- Waves 1 to 10 bonuses: 25, 40, 60, 80, 120 (Warden, doubled), 110, 130, 150, 170, 220.
- Firing Range: dummies at 8, 12, 16, 20, 28 m; gallery of 8 targets, par 14 s.
- Player: 100 health, walk 6 m/s, sprint 9 m/s.

## Known issues

- Not yet played by a person since Milestone 2. Automated checks cover logic, the screenshot tour
  confirmed the gunsmith, compare view, tray, drops, shooter, Warden, Firing Range and the banners
  draw. Feel and pacing are unverified, and the Reforge simulation's minutes are anchored to the
  plan rather than measured.
- The Foreman (wave 10 boss) and the heavy are Milestone 4; wave 10 is a full-roster wave
  without a boss, and Burst's gate stands in for the Foundry.
- Only three slots have bases. Muzzle and ammo open at wave 5 but say "no bases yet".
- The gun model can clip into walls when standing right against them.
- Placeholder sounds are synthesized and rough; new enemies reuse them.
- Running the smoke test headless prints harmless `mesh_get_surface_count` errors from Godot's dummy
  renderer, plus a leak warning at exit.
- Browser frame rate is unmeasured from the container. If the FPS readout shows a low average,
  lower Render scale; if the average is fine but the worst frame spikes, the hitches are CPU-side
  (allocation, physics, or the browser) and the pooling needs extending to whatever still allocates.

## Next concrete step

Jacob plays Milestone 3 and reports: did he reach the Warden without guidance, did he equip a
drop on purpose, and did the compare view make the choice clear. Then Milestone 4: crafting
table (refine, fuse, transmute), Scrapyard, heavy and Foreman, Epics, waves 11 to 15.
