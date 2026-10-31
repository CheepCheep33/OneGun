class_name TestCase
extends RefCounted
## Base for the smoke test's case scripts (tests/cases/). The driver in tests/smoke_test.gd makes
## one of each, runs `run_unit()` before the main scene loads and `run_scene(game)` with the real
## game running, and counts every check(). Keep each case independent: leave progression as you
## found it or reset it.

## The smoke test driver: has check(), physics_frames(), seconds() and the scene tree.
var driver: Node


## Pure logic checks, before the main scene loads.
func run_unit() -> void:
	pass


## Checks that drive the running game.
func run_scene(_game: Node) -> void:
	pass


func check(condition: bool, description: String) -> void:
	driver.check(condition, description)


func physics_frames(count: int) -> void:
	await driver.physics_frames(count)


func seconds(duration: float) -> void:
	await driver.seconds(duration)


## Starts wave 1 and stops its spawns once the game has really started it. The game starts the
## wave runner from _process, which a burst of physics frames can run ahead of, so this waits for
## the runner itself: a robot spawned before then would be cleared by the late start.
func start_quiet_wave(game: Node) -> void:
	game.start_wave(1)
	for i in 30:
		await tree().process_frame
		if game.wave_runner.running:
			break
	game.wave_runner.stop()
	await physics_frames(1)


func tree() -> SceneTree:
	return driver.get_tree()


## Spawns an enemy of a definition a given distance in front of the player.
func spawn_in_front(game: Node, distance: float, definition_path := "res://data/enemies/chaser.tres",
		scene_path := "res://scenes/enemies/chaser.tscn", side := 0.0) -> Enemy:
	var player: Player = game.player
	var forward := -player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	return game.wave_runner.spawn_at(player.global_position + forward * distance + right * side,
		load(definition_path), load(scene_path))


## Makes a seeded RandomNumberGenerator so a failing check can be reproduced.
static func rng(seed_value: int) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = seed_value
	return generator
