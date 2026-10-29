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
| Shoot | Left mouse |
| Reload | R |
| Pause and options | Esc (during a wave) |
| Back to the bench after death | R or the button |

**Phones and tablets (temporary testing controls):** turn the device sideways and tap the game.
On-screen controls appear after the first touch. The left thumb drives a floating stick (push to
the edge to sprint), dragging anywhere else looks around, and the buttons fire, reload (R), jump,
and pause (II).

Options in the pause menu: mouse sensitivity, field of view, camera recoil, damage numbers, volume.
The pause menu's **Abandon wave** returns to the bench, keeping kill credits but paying no bonus.

## The loop

The game opens on **the bench**. Buy core tuning levels (damage, fire rate, magazine, reload speed)
with credits, pick a wave, and press Start. Kills pay credits immediately; clearing a wave pays a
bonus and unlocks the next. Dying keeps the credits you earned. Progress saves at the bench to
`user://save.json`; the bench's **Reset progress** button (press twice) wipes it. A playtest log is
written to `user://playtest_log.txt`. On Linux `user://` is `~/.local/share/godot/app_userdata/One Gun, Infinite Upgrades/`.

## Automated smoke test

Checks the item model, the stats functions, the save file and the wave data, then drives the real
game scene through the bench, movement, shooting, killing, reloading, pausing, touch controls, a
full wave, a purchase, death and retry, replay and abandon:

```
godot --headless --path . res://tests/smoke_test.tscn
```

It prints PASS/FAIL per check and exits with code 1 if anything failed. It checks logic only; it does
not replace playing the game.

A screenshot tour saves pictures of the bench, a wave, the cleared banner and the death screen
(needs a display; `xvfb-run` works):

```
xvfb-run godot --path . --rendering-driver opengl3 res://tests/screenshot_tour.tscn -- out_dir=/tmp/shots
```

## Project layout

```
assets/      placeholder audio and textures (named placeholder_*)
data/        tunable resources: weapon base stats, core tuning, slots, affixes, enemies, waves
scenes/      main scene, arena, player, pistol, enemies, UI (HUD, bench, pause menu)
scripts/     GDScript by responsibility (player, weapons, enemies, game, progression, ui, effects)
tests/       headless smoke test and the screenshot tour
```
