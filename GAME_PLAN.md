# One Gun, Infinite Upgrades: Game Plan

Single-player incremental arena FPS. One weak pistol, waves of robots, credits buy permanent
upgrades until the pistol is absurdly strong. Built in Godot 4.3 (GDScript).

## Agreed scope (initial release)

- One compact graybox arena, one pistol, four enemy types (chaser, shooter, heavy, boss).
- One currency (credits): per-kill rewards plus wave-completion bonuses.
- Repeatable upgrades: damage, fire rate, magazine, reload; later crit chance and crit damage.
- Milestone mods: automatic receiver, penetrating rounds, multishot; two mod slots.
- 20 authored waves, milestone bosses, basic endless mode after wave 20.
- Death ends the attempt but keeps credits and upgrades. Retrying is free.
- Out of scope: multiplayer, open world, extra arenas or guns, loot, crafting, skill trees,
  prestige, offline income, procedural maps, physical bullets, story.

## Milestone status

| Milestone | Status |
| --- | --- |
| 1. Shooting prototype | Built, automated checks pass. **Waiting for Jacob's playtest feedback.** |
| 2. Incremental prototype | Not started |
| 3. Vertical slice | Not started |
| 4. Small first release | Not started |

## Decisions

- **Engine:** Godot 4 with GDScript. Developed and checked against Godot 4.3 stable.
- **Restart = reload the main scene.** No enemy, effect, or weapon state can leak into the next attempt.
  Persistent data (settings now, progression in Milestone 2) lives outside the scene.
- **Weapon stats are derived, never mutated.** `WeaponBaseStats` (data/weapons/pistol_base.tres) holds
  authored values and limits; `WeaponStats.compute(base, upgrade_levels)` builds effective stats.
  Combat and upgrade previews must both use `compute()`.
- **Enemy stats are data.** `EnemyDefinition` resources (data/enemies/) hold health, speed, damage, range,
  telegraph and cooldown times.
- **Physics layers:** 1 world, 2 player, 3 enemies. Shots hit world and enemies.
- **Navigation:** the arena bakes its navmesh from static colliders at load, so edits to the layout
  never leave a stale navmesh.
- **Firing input** is buffered for 0.12 s so a click just before the gun is ready still fires.
- **Melee is dodgeable:** chasers stop, glow orange for 0.45 s, then hit only if you are still within reach.
  Chasers (3.6 m/s) are slower than walking (6 m/s).
- **Spawning** (Milestone 1 test spawner): max 4 alive, never at a spawn point within 10 m of the player.
  Authored waves replace it in Milestone 2.
- **Settings** (sensitivity, FOV, camera recoil, damage numbers, volume) save to `user://settings.cfg`;
  bad or missing values fall back to defaults.
- All art and audio are generated placeholders, named `placeholder_*`.

## Starting tuning values (not balance)

- Pistol: 10 damage, 4 shots/s, 10-round magazine, 1.4 s reload. Limits: 15 shots/s, 0.3 s reload.
- Chaser: 40 health (4 shots), 3.6 m/s, 12 damage per hit, 1.7 m reach, 0.9 s cooldown.
- Player: 100 health, walk 6 m/s, sprint 9 m/s.

## Known issues

- Not yet played by a person. Automated checks cover logic, and screenshots from a software renderer
  confirmed the scene, HUD, muzzle flash, pause menu and death screen draw. Feel (recoil, sound,
  movement) is unverified.
- The gun model can clip into walls when standing right against them.
- Placeholder sounds are synthesized and rough.
- Low walls are 1.5 m high and cannot be jumped onto, by design, so enemies can always reach the player.
- Running the smoke test headless prints harmless `mesh_get_surface_count` errors from Godot's dummy
  renderer, plus a leak warning at exit.

## Next concrete step

Jacob playtests Milestone 1 and reports how shooting, movement and the chaser feel.
Then start Milestone 2: credits, intermission, upgrade terminal, four upgrades, five waves, save/load.
