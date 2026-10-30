# Working in this repository

One Gun, Infinite Upgrades: a Godot 4.3 (GDScript) incremental arena FPS that ships as a browser
build. GAME_PLAN.md is the source of truth for scope, decisions and status; update it in the same
change as the code.

## Before every pull request

- `godot --headless --editor --quit --path .` imports the project and surfaces parse errors. Run
  it again after adding a `class_name` script, or the smoke test will not see it.
- `godot --headless --path . res://tests/smoke_test.tscn` must end with `0 failed`. Grep the log
  for `SCRIPT ERROR` as well; a runtime error can hide behind passing lines.
- `godot --headless --path . res://tests/reforge_sim.tscn` exits 1 on a missed plan target.
- `xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3
  res://tests/screenshot_tour.tscn -- out_dir=<dir>` draws the main screens; look at the images.
- CI (`.github/workflows/web.yml`) runs the first three and deploys a preview per branch. Never
  claim the game was played if it was not run.

## Performance is a standing rule (Jacob, 30 October 2026)

Every change keeps stutter and lag in check; the browser build is the target. The rules, budget
and measurements live in GAME_PLAN.md under "Performance budget". In short:

- Nothing allocates during combat. Effects, projectiles, enemies and sounds come from pools and
  reserves built behind the first bench (`FxPool`, `ProjectilePool`, the `WaveRunner` reserve).
  A new effect goes through `FxPool` with a cap; a new enemy is covered once a wave names it;
  anything else that can appear mid-wave is pooled or pre-built the same way.
- Every material a wave can show is drawn in `FxPool.warm_up`, so no shader compiles mid-wave.
- `tests/cases/perf_cases.gd` is the gate (node, resource and object counts across two combat
  rounds, spawns from the reserve, the 4 ms game-logic budget, warm-up coverage). It runs in
  CI. Never loosen it to get green; fix the cause. `res://tests/perf_probe.tscn` shows where a
  frame's time goes; `-- case=perf` after the smoke test's scene path runs the gate alone.
- Every playtest asks for the FPS readout (pause menu, Show FPS): average and worst frame in a
  busy wave, plus device and browser. A worse reading than the last milestone blocks the merge.

## Conventions and gotchas

- Tunables are resources under `data/` (weapon base, core tuning, attachments and slots,
  affixes, enemies, waves). Scripts sit under `scripts/` by responsibility. Tests live in
  `tests/`, cases in `tests/cases/` on the `TestCase` base class.
- Godot 4.3: the `physics_frame` signal fires before `_physics_process`, so wait two physics
  frames after a `request_fire()`; `Node3D.look_at` tilts the whole body; a ternary yields an
  untyped Array (declare `Array[RID]` first); const dictionaries are read-only; headless Godot
  sleeps about 7 ms every frame (`OS.low_processor_usage_mode_sleep_usec`) and the Performance
  time monitors hold the worst frame of the last second, so measure frame costs the way
  `perf_cases.gd` does.
- The web build has no thread support and no shader cache; every runtime allocation, mesh
  upload and first-use material is a visible hitch there.
