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
| Pause and options | Esc |
| Restart after death | R or the Restart button |

Options in the pause menu: mouse sensitivity, field of view, camera recoil, damage numbers, volume.

## Automated smoke test

Drives the real game scene through movement, shooting, killing, reloading, pausing, enemy attacks,
spawning, death and restart:

```
godot --headless --path . res://tests/smoke_test.tscn
```

It prints PASS/FAIL per check and exits with code 1 if anything failed. It checks logic only; it does
not replace playing the game.

## Project layout

```
assets/      placeholder audio and textures (named placeholder_*)
data/        tunable resources: weapon base stats, enemy definitions
scenes/      main scene, arena, player, pistol, enemies, UI
scripts/     GDScript, grouped by responsibility (player, weapons, enemies, game, ui, effects)
tests/       headless smoke test
```
