# One Gun, Infinite Upgrades (working title)

Single-player incremental arena FPS made with Godot 4. See [GAME_PLAN.md](GAME_PLAN.md) for scope,
milestone status and design decisions.

## Running the game

1. Install [Godot 4.3 or newer (standard build)](https://godotengine.org/download). No .NET build or
   plugins are needed.
2. Open Godot, click **Import**, and select this folder's `project.godot`.
3. The first import takes a few seconds. Press **F5** (or the Play button) to run.

### In a browser

Every push deploys a web build to Cloudflare Pages (`.github/workflows/web.yml`). `main` goes to the
production URL and other branches get a preview URL, shown in the workflow log and in the Cloudflare
dashboard under Workers & Pages → onegun. Click the game once to lock the mouse.

The workflow needs two repository secrets: `CLOUDFLARE_API_TOKEN` (with Cloudflare Pages: Edit) and
`CLOUDFLARE_ACCOUNT_ID`.

## Controls

| Action | Input |
| --- | --- |
| Move | W A S D |
| Sprint | Shift |
| Jump | Space |
| Shoot (hold with an Automatic receiver) | Left mouse |
| Reload | R |
| Pause and options | Esc (during a wave or in the Firing Range) |
| Back to the bench after death | R or the button |
| Pick up a drop | Walk over its beam |

**Phones and tablets (temporary testing controls):** turn the device sideways and tap the game.
On-screen controls appear after the first touch. The left thumb drives a floating stick (push to
the edge to sprint), dragging anywhere else looks around, and the buttons fire, reload (R), jump,
and pause (II).

Options in the pause menu: mouse sensitivity, field of view, camera recoil, damage numbers, volume,
render scale (the 3D view's share of the window's pixels; lower it if the frame rate is low),
shadows, glow, and an FPS readout that shows the average and the worst frame of each half second.
In a browser the defaults are already lighter: render scale matches the page's pixels on high-DPI
screens, glow is off, and anti-aliasing is off.
The pause menu's **Abandon wave** (or **Leave the range**) returns to the bench, keeping kill
credits and collected loot but paying no bonus.

## The loop

The game opens on **the bench**. Buy core tuning levels (damage, fire rate, magazine, reload speed)
with credits, fit attachments in the **gunsmith**, pick a wave, and press Start. Kills pay credits
immediately and sometimes drop an attachment (a beam on the floor); clearing a wave pays a bonus,
one Uncommon attachment, and unlocks the next. Dying keeps the credits and the loot you picked up;
loot still on the floor is lost. The Warden waits at wave 5 and opens two more slots.

Click an inventory item at the bench to see what it would change before equipping it. The inventory
holds 40 items; extras land in an overflow tray until you move or dismantle them. Dismantling pays
parts for the crafting table that comes in Milestone 4. The **Firing Range** (opens after wave 2)
has dummies with live damage readouts and a timed gallery that pays one Uncommon.

Progress saves at the bench to `user://save.json`; the bench's **Reset progress** button (press
twice) wipes it. A playtest log is written to `user://playtest_log.txt`. On Linux `user://` is
`~/.local/share/godot/app_userdata/One Gun, Infinite Upgrades/`.

## Automated checks

**Smoke test.** Checks the item model, the stats functions, the loot tables and inventory rules, the
save file and the wave data, then drives the real game scene: the bench and gunsmith, movement,
shooting, fire modes, pierce and projectiles, the shooter, drones and the Warden, drops, the Firing
Range, death and retry, replay and abandon. Case scripts live in `tests/cases/`.

```
godot --headless --path . res://tests/smoke_test.tscn
```

It prints PASS/FAIL per check and exits with code 1 if anything failed. It checks logic only; it does
not replace playing the game. It resets the save in `user://`, so back yours up first. Add
`-- case=perf` (or another case file's name) after the scene path to run one case on its own.

**Performance gate.** One of the cases (`tests/cases/perf_cases.gd`) holds the standing rule that no
milestone may cost frame rate: a second busy combat round must add no nodes, orphan nodes or
resources and at most a handful of plain objects, every spawn must come from the enemy reserve, the
shader warm-up must cover every enemy the waves use, and game logic for twice the wave cap must stay
under 4 ms a frame (scaled to the machine's speed). GAME_PLAN.md, "Performance budget", has the
reasoning. To see where a frame's time goes by arena load:

```
godot --headless --path . res://tests/perf_probe.tscn
```

**Reforge simulation.** The plan's prototype gate: a first run and three consecutive Reforges with
the real stats function, cost curves and loot tables and a scripted buyer. Prints a table of shots
to kill, recovery minutes and minutes per tier, and exits with code 1 if a target is missed. The
modelled assumptions are named constants at the top of `tests/reforge_sim.gd`.

```
godot --headless --path . res://tests/reforge_sim.tscn
```

**Screenshot tour.** Saves pictures of the bench, the gunsmith compare view, a wave with a shooter
and a drop, the Warden, the cleared banner, the Firing Range, the overflow tray and the death screen
(needs a display; `xvfb-run` works):

```
xvfb-run godot --path . --rendering-driver opengl3 res://tests/screenshot_tour.tscn -- out_dir=/tmp/shots
```

CI runs the smoke test (with the performance gate) and the Reforge simulation on every push before
exporting the web build.

## Project layout

```
assets/      placeholder audio and textures (named placeholder_*)
data/        tunable resources: weapon base stats, core tuning, attachment bases and slots, affixes, enemies, waves
scenes/      main scene, arena, side areas, player, pistol, enemies, UI (HUD, bench, pause menu)
scripts/     GDScript by responsibility (player, weapons, projectiles, enemies, areas, game, progression, ui, effects)
tests/       smoke test driver and cases, the Reforge simulation, the performance probe, the screenshot tour
```
