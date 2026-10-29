# One Gun, Infinite Upgrades: Game Plan

Single-player incremental arena FPS. One weak pistol, waves of robots, credits buy permanent
upgrades until the pistol is absurdly strong. Built in Godot 4.3 (GDScript).

The full design (gunsmith slots, loot and crafting, skill trees, Reforge prestige, procedural
arena, story, bullet simulation, eight milestones) lives in the plan document in the project.
This file tracks what is built, the decisions that shape the code, and the next step.

## Milestone status

| Milestone | Status |
| --- | --- |
| 1. Shooting prototype | Merged. Playtest feedback still welcome. |
| 2. Incremental prototype | Built, automated checks pass. **Waiting for Jacob's playtest: first upgrade inside two minutes, loop fun on its own.** |
| 3. Gunsmith, loot and projectiles | Not started. Needs the M2 gate. |
| 4. Crafting and the Scrapyard | Not started |
| 5. Skills, story and full roster | Not started |
| 6. Procedural arena | Not started |
| 7. Reforge | Not started |
| 8. First release | Not started |

## What Milestone 2 contains

- **The loop:** bench → wave → cleared (bonus) or dead (credits kept) → bench. Five authored
  waves (`data/waves/`), two enemy definitions (chaser, runner), replay of any cleared wave.
- **Credits:** paid per kill the moment the enemy dies, plus a completion bonus per clear (same on
  replay). Dying or abandoning a wave keeps kill credits and pays no bonus.
- **Core tuning at the bench:** damage, fire rate, magazine, reload speed. Prices rise 15% per level.
- **Locked gunsmith slots** shown with gate text, so the player sees what is coming.
- **Item data model** (`Items`, `AttachmentDefinition`, `AffixDefinition`, `SlotDefinition`) and the
  **two stats functions** (`WeaponStats.build`, `WeaponStats.resolve_shot`) with tests. No items drop yet.
- **Save file** version 2 at `user://save.json`, written only at the bench.
- **Playtest log** at `user://playtest_log.txt`: wave starts, clears with duration, purchases with
  session time, deaths and abandons.

## Decisions

- **Engine:** Godot 4 with GDScript. Developed and checked against Godot 4.3 stable.
- **Renderer:** Compatibility (OpenGL / WebGL 2), because the browser build requires it. Desktop uses
  the same renderer, so both builds look the same.
- **Browser build:** every push runs the smoke test, exports the Web preset (no threads, so no special
  server headers), and deploys to the Cloudflare Pages project `onegun`. `main` is production;
  other branches get preview URLs. Workflow: `.github/workflows/web.yml`.
- **Mouse capture:** browsers only lock the mouse after a click. The bench's Start button is that
  click. If capture still fails the HUD shows "Click to play" and the wave waits. Losing capture
  (Esc in a browser, alt-tab) pauses.
- **Temporary touch controls** (`scenes/ui/touch_controls.tscn`) for testing the browser build on
  phones. They appear on the first touch and turn off mouse input, since browsers also report taps
  as clicks. They are a testing aid, not the final mobile design.
- **UI scaling:** the window uses `canvas_items` stretch with `expand`, so the HUD keeps its size
  relative to the screen on high-DPI phones and large monitors.
- **Starting any encounter resets it.** The main scene is loaded once; starting a wave clears
  enemies, revives the player at the start marker and hands the pistol a freshly built stats
  object. Nothing from the previous attempt survives into the next. (Milestone 1 reloaded the
  scene; that no longer fits a bench that must stay open.)
- **The bench pauses the tree.** It runs with `process_mode` Always, like the pause menu, so
  nothing moves while the player shops. Esc only pauses during a wave.
- **Progression is an autoload** (`scripts/progression/progression.gd`). It owns credits, core
  levels, wave progress, inventory, equipped build, records, and the save. Rewards commit when
  earned; the bench is the only place that writes the save (also after each purchase, since the
  player is at the bench then).
- **Weapon stats are derived, never mutated.** `WeaponStats.build(base, core_levels, equipped,
  skills, forge)` sums flat modifiers, then additive percentages per stat, multiplies once and
  clamps to the base's limits and the absolute caps (15 shots/s, 50% crit, pierce 4, rays 4,
  bounces 2). Behaviours (fire mode, rays, pierce, projectile, on-hit) are flags the pistol reads at
  fire time. `WeaponStats.resolve_shot(build, context, rng)` turns a build plus a per-shot context
  (distance, charge, health fraction, Overclock, Bullet Time) into one shot's damage and crit.
  Combat, the bench preview and the bench summary all call the same two functions.
- **Reload is bought as speed:** reload percentages divide the time. Crit chance is a fraction, so
  its modifiers add percentage points rather than multiplying.
- **Core tuning is data:** one `CoreTuningDefinition` per stat in `data/core_tuning/` (stat key,
  flat or percent per level, base cost, growth, level cap). Core tuning never changes behaviour.
- **Items are small dictionaries** so they save as plain JSON: base id, rarity, affix list with
  rolls in [0, 1], mark I to V, lock flag, uid. Bases (`AttachmentDefinition`) carry mark-scaled
  modifiers and behaviour flags; affixes (`AffixDefinition`, `data/affixes/`) carry a value range
  per rarity. Unknown base or affix ids are dropped on load with a warning, never a crash. Seven
  `SlotDefinition` resources (`data/attachments/slots/`) hold gate text and the unlock wave.
- **Waves are data:** `WaveDefinition` with timed `SpawnGroup`s, an alive cap, and a completion
  bonus. The wave runner owns spawning, the cap, the clear check and tier scaling (per-kill credits
  and enemy health step 1.6x per five waves; Reforge tier steps 2.5x, unused until Milestone 7).
- **Save format:** JSON with a version number. Version 1 (the original Milestone 2 spec: credits,
  upgrade levels, highest wave) migrates to 2. An unknown version or unreadable file starts fresh
  and keeps `user://save.backup.json`.
- **Enemy stats are data.** `EnemyDefinition` resources (data/enemies/) hold health, speed, damage,
  range, telegraph and cooldown times, and the credit reward.
- **Physics layers:** 1 world, 2 player, 3 enemies. Shots hit world and enemies.
- **Navigation:** the arena bakes its navmesh from static colliders at load.
- **Firing input** is buffered for 0.12 s so a click just before the gun is ready still fires.
- **Melee is dodgeable:** chasers stop, glow orange for 0.45 s, then hit only if you are still within reach.
- **Settings** (sensitivity, FOV, camera recoil, damage numbers, volume) save to `user://settings.cfg`;
  bad or missing values fall back to defaults.
- All art and audio are generated placeholders, named `placeholder_*`.

## Starting tuning values (not balance)

- Pistol: 10 damage, 4 shots/s, 10-round magazine, 1.4 s reload. Limits: 15 shots/s, 0.3 s reload.
- Core tuning per level: damage +2 (20 credits), fire rate +6% (35), magazine +1 (25, cap 50 levels),
  reload speed +8% (30). Every price grows 15% per level.
- Chaser: 40 health, 3.6 m/s, 12 damage, 1.7 m reach, 0.9 s cooldown, 5 credits.
- Runner: 20 health, 5.2 m/s, 8 damage, 1.6 m reach, 0.8 s cooldown, 4 credits. First seen in wave 3.
- Waves: 1 (5 chasers, bonus 25), 2 (8 chasers, 40), 3 (6 chasers + 6 runners, 60),
  4 (10 + 8, 80), 5 (18 chasers + 12 runners, 120). Kill income plus bonuses over five waves: 664 credits.
- Player: 100 health, walk 6 m/s, sprint 9 m/s.

## Known issues

- Not yet played by a person. Automated checks cover logic and the screenshot tour confirmed the
  bench, HUD readouts, cleared banner and death screen draw. Feel and pacing are unverified.
- The plan suggests a completion bonus of about three waves of kill income; the authored bonuses are
  closer to one wave so the first session is not flooded. A playtest decides.
- The gun model can clip into walls when standing right against them.
- Placeholder sounds are synthesized and rough.
- Running the smoke test headless prints harmless `mesh_get_surface_count` errors from Godot's dummy
  renderer, plus a leak warning at exit.

## Next concrete step

Jacob plays Milestone 2 and reports: did the first upgrade come inside two minutes, is the
credits-and-core-tuning loop fun on its own, and how do the five waves pace. Then Milestone 3:
receiver, barrel and magazine slots with two bases each, Common to Rare drops with affixes,
inventory and dismantle, shooter and swarm drone on the minimum projectile system, the Warden,
ten waves, and the Firing Range.
