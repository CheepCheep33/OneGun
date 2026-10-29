extends Node
## Drives the real game through the bench, a wave, the cleared banner and the death screen, saving a
## screenshot of each. Needs a window (use xvfb-run headlessly):
##   xvfb-run godot --path . --rendering-driver opengl3 res://tests/screenshot_tour.tscn -- out_dir=/tmp/shots
## A visual aid for review, not a test: it never fails.


func _ready() -> void:
	# The tour node lives under the root so it survives the scene change to the main scene.
	var tour := Tour.new()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			tour.out_dir = arg.trim_prefix("out_dir=")
	get_tree().root.add_child.call_deferred(tour)


class Tour:
	extends Node

	var out_dir := "user://screenshots"

	func _ready() -> void:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		_run.call_deferred()

	func _run() -> void:
		Progression.reset()
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		var game: Node = null
		for i in 300:
			await get_tree().process_frame
			var scene := get_tree().current_scene
			if scene and scene.name == "Main" and scene.is_node_ready():
				game = scene
				break
		await _frames(10)
		await _shot("01_bench_new_player")

		# Pretend wave 1 was cleared with some credits so the bench has something to sell.
		Progression.add_credits(36)
		Progression.record_wave_cleared(1, 25, 42.0)
		game.bench.open()
		await _frames(3)
		await _shot("02_bench_after_wave_1")

		game.start_wave(2)
		await _frames(5)
		# Let a few enemies spawn and walk in, then freeze the moment.
		await _seconds(6.0)
		game.player.pistol.request_fire()
		await _frames(2)
		await _shot("03_wave_2_combat")

		game.wave_runner.stop()
		for enemy in game.get_node("Enemies").get_children():
			if enemy is Chaser and enemy.is_alive:
				enemy.take_hit(10000.0, enemy.global_position, Vector3.FORWARD)
		await _frames(2)
		game.hud.show_wave_cleared(2, 40, true)
		await _frames(3)
		await _shot("04_wave_cleared_banner")
		game.hud._banner.visible = false

		game.player.take_damage(10000.0)
		await _frames(3)
		await _shot("05_death_screen")

		game.open_bench()
		await _frames(3)
		await _shot("06_bench_returning")
		Progression.reset()
		get_tree().quit(0)


	func _shot(name: String) -> void:
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := out_dir.path_join(name + ".png")
		var err := image.save_png(path)
		print("SHOT %s (%s)" % [path, error_string(err)])


	func _frames(count: int) -> void:
		for i in count:
			await get_tree().process_frame


	func _seconds(duration: float) -> void:
		await get_tree().create_timer(duration, true, true).timeout
