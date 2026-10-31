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
| 3. Gunsmith, loot and projectiles | Merged (PR #3). Its playtest questions were never answered; they are carried into the Milestone 4 gate below. |
| 4. Crafting and the Scrapyard | Built, automated checks and both performance gates pass, Reforge simulation hits its targets. **Waiting for Jacob's playtest** (questions under "Next concrete step"). |
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
- **Enemies:** shooter (wave 4: opens fire from 18 m the moment it has line of sight, with 8
  degrees of aim error out there falling to 1.5 at the 11 m it walks in to and holds; telegraphs,
  fires a 16 m/s bolt; never fires without line of sight), swarm drone (wave 7: 12 health, flies
  at head height, counts half in the alive cap), the Warden boss (wave 5: 450 health, charge and
  ground slam, boss bar), on a shared `Enemy` base class. Ten authored waves.
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
  pooled effects, enemy and projectile reserves built behind the first bench, shader warm-up,
  web-specific render defaults, video options with an FPS readout, and the performance gate in
  the smoke test. See "Performance budget" below.

## What Milestone 4 contains

Scope as Jacob chose it on 30 Oct ("craft and reroll", the approved plan's row): refine, fuse and
transmute stay in Milestone 5.

- **Crafting table** (the bench's second tab, `scripts/progression/crafting.gd`): craft any
  unlocked non-default base at Common, Uncommon, Rare or Epic for parts (3 Scrap; 4 Scrap and 2
  Alloy; 5 Alloy and 2 Circuits; 5 Circuits and 2 Cores), affixes rolled from the save's loot
  stream; reroll one affix of the selected item (inventory, tray or fitted) while the others stay,
  for 2 of the part one rarity down and 1 of its own, times one plus the rerolls that item has had.
  Every recipe costs more of each part than dismantling its result returns, so no craft-and-
  dismantle loop makes parts (checked). Legendaries are not crafted.
- **Muzzle and ammo bases** (both slots open at the Warden, as before): Splitter (three rays in a
  4 degree cone, 125% of a shot between them, -30% range), Overpressure (+12% damage, +60%
  recoil), Explosive rounds (simulated shells, 60% on the hit and 60% to every robot within 2.5 m,
  blasts never crit or proc, -15% fire rate, -25% range) and Ricochet rounds (two bounces, -10%
  damage), all on the shared projectile system and `ShotPipeline`. The bench's readouts count the
  Splitter's spread: up close all three rays land, at 10 m about 40% do.
- **Epics:** bosses drop an Epic on their first clear (a Rare on replay); heavies (20%) and
  shield bearers (15%) roll a Rare before the normal table, capped at Uncommon on replays. The
  Precise affix (weak-point damage) now drops.
- **Heavy** (waves 8 to 15): 160 health, slow, a hard telegraphed swing, flat armour 4 a hit
  (scaled with the wave like health; at least a quarter of every hit lands), and a glowing core on
  its back that takes double damage and ignores armour.
- **Shield bearer** (waves 11 to 15): a frontal shield on its own physics layer (4) that stops
  every player ray and round, pierce and bounces included, and covers whatever walks behind it.
  It lowers the shield to swing, which is the window from the front; flanking, blasts and chains
  reach it any time.
- **The Foreman** (wave 10 boss, 700 health, armour 2): keeps its distance and fires a fanned
  three-bolt volley; glows cyan and calls in three swarm drones (at most six alive; they pay
  credits but drop nothing, sit outside the wave's count and cap, and fall with it); glows orange
  and lays a molten pool where the player stood: a ring grows for 1.2 s, then the floor burns
  grounded players for 6 s (a jump or a step out avoids it). Three pools are part of its scene and
  reused.
- **Waves 11 to 15** (Shield wall, Heavy industry, Cover fire, Escort, Full shift) with the full
  roster; heavies join waves 8 and 9; wave 10 is the Foreman's.
- **Scrapyard** (`scenes/areas/scrapyard.tscn`, opens after wave 5): an authored yard of three
  lanes split by rows of wrecks (lined up for Penetrator) with twelve scrap cores on them. Robots
  come in rising numbers on the wave runner from `data/areas/scrapyard_spawns.tres`, scaled like
  the next wave. After 90 s the south door opens; its pad extracts with the cores carried: 2 Scrap
  each, plus an Alloy per 3 and a Circuit per 8, a Rare every extraction and a salvage log the
  first time. Death or leaving loses the cores; kill credits and picked-up drops stay, and kills
  drop like a replay.
- **Save file** version 4 (Scrapyard record, crafting records, each item's reroll count),
  migrating from 1, 2 and 3.
- **Checks:** `crafting_cases.gd` (conservation, gates, determinism, reroll rules, the craft tab),
  `roster_cases.gd` (armour and weak point, the shield against rays, rounds and blasts, explosive
  splash, the Foreman's summons and pools, and the plan's dangerous combinations: Splitter plus
  chain-on-crit arcs once into each robot per shot, never twice; a Ricochet plus Penetrator round
  re-strikes a line after bouncing but lands at most pierce plus one hits, inside the pipeline's
  cap of six), `scrapyard_cases.gd` (gate, payout, a run with pickup, extraction and death, the
  version 3 migration), and a Milestone 4 round in the performance case.

## Performance budget (standing rule)

Jacob's rule from 30 Oct 2026: every milestone and every thread keeps stutter and lag in check;
no change may cost frame rate. The browser build is the target: one thread, no shader cache, a
GPU the browser chooses, and scripts and physics roughly three times slower than native. These
are the rules the code follows and the checks that hold them.

**Rules.**
- Nothing is allocated during combat. Effects, projectiles, enemies, drops, sounds and HUD notes
  come from pools and reserves built behind the first bench (`FxPool`, `ProjectilePool`, the
  `WaveRunner` enemy reserve, the game's drop reserve, the HUD's note labels). A new effect goes
  into `FxPool` with a cap; a new enemy is covered by the reserve and the shader warm-up as soon
  as a wave names it; anything else that can appear mid-wave (a drop kind, a telegraph, a status
  effect) is pooled or pre-built the same way.
- Every material a wave can show is drawn behind the first bench (`FxPool.warm_up`), both lit by
  the pistol's muzzle light and unlit, so no shader compiles mid-wave. The Compatibility
  renderer compiles a second, lit variant of a material's shader the first time a point light
  touches it; before 30 Oct the muzzle light did that mid-shot, which was the stutter when
  shooting (a cold shader cache, as every browser session has, froze the first shot for 1.5 s
  and the first hit on an enemy for 0.8 s under llvmpipe). Enemy scenes get the warm-up from the
  wave data; a new effect or drop is added to `warm_up` by hand; a side area gets
  `Fx.warm_up_lighting` when it loads.
- World-space text is 2D: damage numbers and drop names are canvas labels inside the HUD's layer,
  placed where their world position projects each frame. A `Label3D` rebuilds its mesh and its
  material on every change (each frame of a fade included), which is a GPU allocation per number
  per frame. Every text size the HUD shows during play is drawn once at the bench
  (`Hud.warm_up_text`), so no font atlas page is built at the first pickup, boss or banner.
- A material parameter is a buffer upload: write it only when the value changes (enemy glow).
- Game logic (process callbacks plus one physics step) for twice the wave cap with automatic
  fire and enemy bolts stays under 4 ms a frame natively, about a quarter of a 60 Hz frame,
  which leaves the browser's slower scripts and its rendering the rest. Measured at 1.5 to
  1.7 ms on 30 Oct; the probe below shows where it goes.
- Web render defaults stay light (glow off, MSAA off, one 2048 shadow split, a render scale that
  follows the device pixel ratio); anything heavier is a pause-menu option.
- Every milestone's playtest asks for the FPS readout (pause menu, Show FPS): the average and
  the worst frame in a busy wave on Jacob's machine and browser. A worse reading than the
  previous milestone blocks the merge until the cause is fixed.

**Checks** (`tests/cases/perf_cases.gd`, part of the smoke test, in CI on every push):
- A second busy combat round (16 enemies, automatic fire, 90 enemy bolts, 16 deaths) adds no
  nodes, no orphan nodes and no resources (meshes, materials, shapes) compared with the first,
  and at most 8 plain objects (the engine keeps a few lazily). A per-shot, per-bolt, per-hit or
  per-death allocation shows up as a count that grows by tens or hundreds.
- Every spawn of that round comes from the enemy reserve (nothing built), and the reserve holds
  what the waves can have alive at once plus each boss's adds (56 nodes for waves 1 to 15). Sixteen
  drops over two batches come from the drop reserve and build no node, mesh or material.
- A Milestone 4 round, twice: Splitter plus Explosive on automatic into heavies and shield bearers
  (three shells a pull, a blast each), the Foreman calling in drones and laying pools, every
  death. The second round adds no node, orphan or resource (864 nodes, 257 resources both times on
  30 Oct). It found a real bug on the way: a dead enemy's deferred trip to the reserve could park
  a node twice, so two later spawns shared one node; `WaveRunner._recycle` now refuses that.
- Game logic for that round stays under the budget, scaled to the test machine's speed by a
  calibration loop so a slow CI runner does not fail it and a fast one does not loosen it.
- The warm-up drew every enemy scene the waves use, with the muzzle light on; damage numbers are
  2D labels.

**GPU gate** (`tests/gpu_gate.sh`, in CI on every push): the headless test cannot see shader
compiles or uploads, so this runs `tests/gpu_probe.tscn` with a real renderer (Mesa's llvmpipe
under Xvfb, shader cache off, the way a browser pays every session) through a script of
first-time events after the warm-up: first shot, first hit, damage numbers, deaths, drops, a
pickup, a shooter's bolt, the Warden, an explosive shell and its blast, a Splitter shot, a heavy
and a weak-point hit, a shield bearer and a shot on its shield, the Foreman, its summon and its
molten pools, a reload, each repeated once, then a crowd under automatic fire, and finally the
Scrapyard's door opening and a core pickup. It fails when an event's worst frame is more than 40 ms (or 0.8 of the idle median) over
that event's median, which under llvmpipe is a shader compile or an upload (a timing failure is
retried once and must repeat), or when a repeated event allocates any GPU buffer or texture
memory. Before the fix the first shot read 1546 ms against an idle frame of 52, the first hit
795, the first drop 109 and the first bolt 153; after it every event is within 10 ms of idle and
every repeat allocates nothing. With Milestone 4 (30 Oct, llvmpipe, idle median 38 ms) the worst
first-time frame is 20 ms over its median (the second molten pool), and the first blast's 3.8 KB of
buffers is the only first-time allocation; its repeat allocates nothing.

**Tools.** `godot --headless --path . res://tests/perf_probe.tscn` prints the game-logic cost of
one frame for a dozen arena loads (empty arena, frozen crowd, walking crowd, no nav agents, no
enemy-to-enemy collision, drones, shooters, fire). `-- case=perf` after the smoke test's scene
path runs the performance case alone. Readings on 30 Oct: empty arena 0.6 ms, 8 chasers 0.9 ms,
16 chasers 1.2 ms, 16 chasers with automatic fire and bolts 1.4 ms; nearly all of it is the
physics step (`move_and_slide` for each enemy and the player), process callbacks are under
0.1 ms. A spawn from the reserve costs 0.1 to 0.3 ms where building the scene cost 1 to 8 ms.
The GPU probe (`xvfb-run -a -s "-screen 0 640x360x24" godot --path . --rendering-driver opengl3
--resolution 640x360 res://tests/gpu_probe.tscn`, with `MESA_SHADER_CACHE_DISABLE=true` to see
compiles at their true cost) prints, per first-time event after the warm-up, the worst and median
frame and the GPU memory it allocated; `-- light_range=0.001` switches the muzzle light off to
tell its share apart. A worst frame far over the event's median is a compile or an upload.

**Next levers**, by what Jacob's readout shows. GPU-bound (low average that improves with Render
scale): a lower web render scale default, simpler enemy meshes, no directional shadow on the
web. CPU-bound (low average that Render scale does not help): move enemies on alternate physics
ticks with interpolated visuals, or drop enemy-to-enemy collision (about 0.2 of the 1.2 ms for 16
chasers). Hitches (a fine average with worst-frame spikes): something still allocates or
compiles; the performance case's counts point at it.

## Reforge simulation: what it says

Three consecutive resets after a first run, with the real stats function, cost curves, loot
tables, inventory rules and crafting table, a greedy buyer (most sustained damage per second per
credit), and the plan's budget for the systems not built yet (skills about 1.3x damage after a
run, kept gear refined one mark per run, Forge nodes bought with two tokens per Reforge). Waves 1
to 15 are the authored data; 16 to 20 repeat 11 to 15 (the wave-tier step already makes them
tougher and better paid) with Warden stand-ins for the Sentinel at 15 and the Core Guardian at 20.
At every bench the simulated player dismantles the spares it can compare and rerolls a fitted
affix that adds under 2% of its damage per second, up to three rerolls a bench. Armour is
modelled per hit, shield bearers as 2 s of extra engagement each.

| Tier | Shots to kill a chaser, wave 1 | By wave 5 | Recover previous damage per second | Minutes to next Reforge |
| --- | --- | --- | --- | --- |
| 0 (first run) | 4 | 2 | - | 108 |
| 1 | 5 | 1 | 8.9 min | 76 |
| 2 | 5 | 1 | 8.6 min | 75 |
| 3 | 4 | 1 | 8.3 min | 74 |

Targets: 5 to 7 shots at wave 1 of tier 1 (later tiers 3 to 7), recovery under 10 minutes, 60
to 90 minutes to the next Reforge, first run 100 to 120. All hit. What Milestone 4 changed and
what to know:

- **Kept gear is now above the plan's budget.** Two more slots with affixes, Epics, Explosive's
  1.2x on a single target and rerolls take the first run's gear to +67% damage (the plan budgets
  about 1.6x), and tier 1 opens at 5 shots, the bottom of its band. Three tuning changes got it
  there, each a real value: Overpressure trades recoil only (+12% damage; it was +20% damage and
  -8% fire rate, stronger than the Long barrel); waves 11 to 15 pay 230 to 340 bonuses; and the
  readouts count the Splitter's spread (all three rays were assumed to land at 10 m, which made it
  the best gun in the simulation by a wide margin). The plan's levers if tier 1 drops to 4 again:
  the kept-gear share (refine in Milestone 5, Reforge rules in 7), the tier step, Forge grants.
- **Recovery depends on the crafting table.** Without the simulated rerolls, tier 1 recovered in
  10.8 minutes: the first run's late waves buy far more core levels than before, and gear fire-rate
  penalties add to the gap because percentages sum. Banked parts spent on rerolls early in tier 1
  close it, so a player who ignores the table will feel the next tier drag.
- **Minutes are anchored, not predicted.** Real combat runs slower than kill arithmetic, so a
  single pace multiplier (`COMBAT_PACE` 3.0) plus 20 minutes of side content per tier and
  first-run learning time are fitted to the plan's 100 to 120 minute first run. Shots to kill
  and recovery do not depend on that knob; the Reforge minutes do. Refit it from the
  `wave_cleared` seconds in the playtest log once real runs exist.
- **The plan's Forge node changed** (Milestone 3 finding). "10 free damage levels" one-shots
  wave 1 from tier 2 on, because a damage level is worth 2.5x more each tier. The simulated node
  ("Head start") grants one starting damage level per Reforge tier beyond the first, per rank.

The gun still reaches one shot per chaser by wave 5 of every later tier, because the buyer spends
every credit on damage per second. A person buys worse and dies more; both move recovery up and
the wave 5 number toward the plan's 3.

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
  `drops = false` so they never roll (`lingering` still; `precise` drops from Milestone 4). Each
  item also counts its rerolls, which set the next reroll's price.
- **The loot stream is seeded** per save and its state is stored in the save as a string (JSON
  would mangle a 64-bit state as a double), so a reload continues the same sequence.
- **Slot gates:** the plan's answer (receiver, barrel, magazine open from the start) replaces
  Milestone 2's wave 3 gate. Burst is gated by the wave 10 clear until the Foundry exists (a later milestone).
- **Rarity:** bosses drop an Epic on first clear and a Rare on replay; armoured enemies roll a
  Rare first (heavy 20%, shield bearer 15%); replays cap everything else at Uncommon. Crafting
  reaches Epic; Legendaries wait for transmute (Milestone 5).
- **Armour is flat per hit** (`EnemyDefinition.armor`, scaled with the wave like health), and at
  least a quarter of every hit lands, so a weak build is slowed but never stopped. Weak points are
  a sphere in the enemy's own space; a hit there doubles after crits (times the Precise affix)
  and ignores armour. Blasts and chains are never weak-point hits.
- **Shields are bodies on their own layer** (4, "shields"), so enemies, enemy bolts and line of
  sight ignore them, and only the player's rays and rounds (mask 1, 3 and 4) stop on them. A round
  that stops on a shield never bounces; an Explosive round still bursts there.
- **Explosive rounds burst where they stop**: an enemy they cannot pierce, the world or a shield.
  The blast reaches every living enemy (and Firing Range dummy) whose centre is within the radius
  plus half a metre, once, with no crit, weak point or proc.
- **Boss adds** come from the wave runner's reserve (the boss's `summon_scene`, `max_summons`
  reserved alongside the waves' own), carry a `summoned` flag that keeps them out of the wave's
  count, alive cap and loot, and are dismissed (no credits) when the boss dies.
- **Side areas can have spawns:** an area scene with `encounter_wave()` runs that schedule on the
  wave runner when the player has control, scaled like the next wave; its kills drop like a replay
  and its status line replaces the wave counter.
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
- **Save format:** JSON with a version number; 1, 2 and 3 migrate to 4. An unknown version or
  unreadable file starts fresh and keeps `user://save.backup.json`. A storage probe at start
  falls back to in-memory saves with a bench warning.
- **Physics layers:** 1 world, 2 player, 3 enemies (Firing Range targets sit on 3 too), 4 shields.
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
  measured in a browser from here; Jacob's readout decides. The same day the pass became the
  standing rule above: death sounds and the slam ring joined the pool, every pool is built to
  its cap at warm-up, enemies are recycled through a reserve instead of instantiated per spawn,
  and the performance case guards all of it.
- **Tests are split into cases** (`tests/cases/`): stats, loot, combat, bench, crafting, roster,
  scrapyard, effects, perf. The smoke test driver runs their unit checks before the scene and
  their scene checks on the running game; `-- case=<name>` runs one case alone and
  `-- case=a+b` several in order. A scene case leaves wave 1 started with its spawns stopped, as
  the next case expects.
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
  (crit chance), Brutal (crit damage), Piercing, Thrifty (ammo refund), Arcing (chain on crit),
  Precise (weak-point damage).
- Muzzle and ammo bases: Splitter 3 rays in 4 degrees, 125% in total, -30% range, +20% recoil;
  Overpressure +12% damage, +60% recoil; Explosive 60% direct and 60% blast in 2.5 m, -15% fire
  rate, -25% range, shells at 36 m/s with light drop; Ricochet two bounces (80% each), -10% damage.
- Crafting: craft 3 Scrap / 4 Scrap 2 Alloy / 5 Alloy 2 Circuits / 5 Circuits 2 Cores (Common to
  Epic); reroll 2 of the lower part and 1 of the item's own, times one plus its rerolls so far.
- Enemies: chaser 40 health, 5 credits; runner 20, 4; shooter 30 health, 10 bolt damage, 6
  credits; swarm drone 12 health, 5 damage, 2 credits; Warden 450 health, 22 melee, 28 charge,
  30 slam (5.5 m ring, 1.1 s telegraph), 80 credits. Heavy 160 health, armour 4, 20 melee (0.75 s
  windup), 14 credits, counts 1.5, core x2; shield bearer 70 health, 14 melee, 9 credits; the
  Foreman 700 health, armour 2, three 12-damage bolts, three drones every 14 s (six at most), a
  molten pool every 7 s (1.2 s warning, 6 s at 16 per second), 120 credits.
- Wave bonuses: 25, 40, 60, 80, 120 (Warden, doubled), 110, 130, 150, 170, 220 (Foreman,
  doubled), 230, 250, 270, 290, 340.
- Scrapyard: 90 s to the door, twelve cores, 2 Scrap a core plus an Alloy per 3 and a Circuit per
  8, a Rare per extraction; spawns 30 chasers, 20 runners, 8 shooters, 3 heavies, 7 alive.
- Firing Range: dummies at 8, 12, 16, 20, 28 m; gallery of 8 targets, par 14 s.
- Player: 100 health, walk 6 m/s, sprint 9 m/s.

## Known issues

- Not played by a person since Milestone 2. Automated checks cover logic; the screenshot tour
  confirmed the gunsmith, compare view, tray, drops, shooter, Warden, Firing Range, banners, the
  crafting table, heavies and shield bearers under Explosive fire, the Foreman's pools and the
  Scrapyard draw. Feel and pacing are unverified, and the Reforge simulation's minutes are anchored
  to the plan rather than measured.
- Burst's gate stands in for the Foundry, which does not exist yet.
- Optic and underbarrel open after wave 10 but have no bases yet (Milestone 5 and later).
- Wave 15 has no boss yet: the Sentinel is Milestone 5. Waves 16 to 20 are not authored.
- The Scrapyard is authored, one layout; the plan rolls it from the chunk kit in Milestone 6.
- Kept gear runs above the plan's budget and tier 1 of the simulated Reforge opens at the bottom of
  its band (see "Reforge simulation").
- The Explosive blast is a plain additive sphere; at close range several at once wash the view
  out for a fifth of a second.
- The gun model can clip into walls when standing right against them.
- Placeholder sounds are synthesized and rough; new enemies reuse them.
- Running the smoke test headless prints harmless `mesh_get_surface_count` errors from Godot's dummy
  renderer.
- Browser frame rate is unmeasured from the container. If the FPS readout shows a low average,
  lower Render scale; if the average is fine but the worst frame spikes, something still allocates
  or compiles mid-wave. "Performance budget" lists the next levers for each case. Jacob's
  30 Oct report: much less lag, stutter left when shooting; the GPU probe found the cause (the
  muzzle light's lit shader variants compiled mid-shot) and the fix shipped with Milestone 3 on
  `main`. Whether the stutter is gone in his browser is one of the open playtest questions.
- Shooter balance after the range change is unplayed: 18 m with line of sight and up to 8
  degrees of aim error is a first guess, tuned in `data/enemies/shooter.tres`.

## Next concrete step

Jacob plays the Milestone 4 preview build and reports. The plan's gate for this milestone: does he
craft and enter the Scrapyard without being told to, and do his builds differ from run to run?
Also: does the Foreman's pool telegraph read in time, can he tell when a shield bearer's shield is
down, and does the Splitter or Explosive feel worth fitting?

Carried over from Milestone 3, still unanswered: did he reach the Warden without guidance, did he
equip a drop on purpose (and did the compare view make the choice clear), is the stutter when
shooting gone, and how do shooters feel firing from 18 m?

Every playtest: the FPS readout (pause menu, Show FPS) in a busy wave, average and worst frame,
with the device and browser. A worse reading than Milestone 3's blocks the merge.

Then Milestone 5: three skill trees, optic and underbarrel bases, Charge and Launcher, refine,
fuse and transmute, the Foundry and Signal Tower, the turret, the Sentinel (wave 15) and the Core
Guardian (wave 20), waves 16 to 20 and story chapters 1 to 4, each new enemy and effect inside the
performance budget. (The plan's dangerous-combination test names Splitter plus Shock ammo; Shock
is not built yet, so Milestone 4 tests the same one-chain-per-robot rule through the Arcing affix.)
