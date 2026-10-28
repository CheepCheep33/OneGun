extends Node
## Headless smoke test that drives the real main scene. Run from the project folder:
##   godot --headless --path . res://tests/smoke_test.tscn
## Prints PASS/FAIL per check and exits with code 1 if anything failed.
## This checks game logic only; it does not replace playing the game.


func _ready() -> void:
	var driver := Driver.new()
	get_tree().root.add_child.call_deferred(driver)


class Driver:
	extends Node

	var failures := 0
	var checks := 0

	func _ready() -> void:
		_run.call_deferred()

	func _run() -> void:
		await _test_settings_fallback()
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		var game := await _wait_for_main()
		await _test_initial_state(game)
		await _test_movement(game)
		await _test_shoot_and_kill(game)
		await _test_reload(game)
		await _test_auto_reload(game)
		await _test_pause(game)
		await _test_enemy_attacks(game)
		await _test_spawner(game)
		var old_game := game
		await _test_death(game)
		game.restart()
		game = await _wait_for_main(old_game)
		await _test_clean_restart(game)
		print("\n%d checks, %d failed" % [checks, failures])
		get_tree().quit(1 if failures > 0 else 0)

	# ------------------------------------------------------------------ tests

	func _test_settings_fallback() -> void:
		var cfg := ConfigFile.new()
		cfg.set_value("input", "mouse_sensitivity", "not a number")
		cfg.set_value("video", "field_of_view", 999.0)
		cfg.set_value("feedback", "show_damage_numbers", 42)
		cfg.save(Settings.SAVE_PATH)
		Settings.load_settings()
		check(Settings.mouse_sensitivity == 1.0, "wrongly typed setting falls back to default")
		check(Settings.field_of_view == Settings.FIELD_OF_VIEW_RANGE.y, "out-of-range setting is clamped")
		check(Settings.show_damage_numbers == true, "wrongly typed bool falls back to default")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.SAVE_PATH))
		Settings.field_of_view = 80.0
		Settings.load_settings()
		check(Settings.field_of_view == 80.0, "missing settings file keeps defaults")

	func _test_initial_state(game: Node) -> void:
		game.spawner.stop()
		var player: Player = game.player
		check(player.health == player.max_health, "player starts at full health")
		check(player.pistol.ammo == 10, "pistol starts with a full 10-round magazine")
		var nav_mesh: NavigationMesh = game.arena.get_node("NavigationRegion3D").navigation_mesh
		check(nav_mesh.get_polygon_count() > 0, "arena navmesh baked (%d polygons)" % nav_mesh.get_polygon_count())
		check(game.arena.get_spawn_points().size() == 5, "arena has 5 marked spawn points")
		check(player.global_position.distance_to(game.arena.get_player_start().origin) < 0.5, "player placed at PlayerStart")

	func _test_movement(game: Node) -> void:
		var player: Player = game.player
		await physics_frames(10)
		var start := player.global_position
		Input.action_press("move_left")
		await physics_frames(30)
		Input.action_release("move_left")
		await physics_frames(20)
		var moved := player.global_position - start
		check(moved.x < -1.5, "moving left moves the player (%.2f m)" % moved.x)
		Input.action_press("jump")
		await physics_frames(2)
		Input.action_release("jump")
		var peak := player.global_position.y
		for i in 30:
			await get_tree().physics_frame
			peak = maxf(peak, player.global_position.y)
		check(peak > 0.8, "jumping leaves the ground (peak %.2f m)" % peak)
		await physics_frames(60)
		check(player.is_on_floor(), "player lands again")

	func _test_shoot_and_kill(game: Node) -> void:
		var player: Player = game.player
		var hits := [0, 0]
		player.pistol.hit_landed.connect(func(killed: bool) -> void:
			hits[1 if killed else 0] += 1)
		var enemy := _spawn_in_front(game, 6.0)
		await seconds(Chaser.SPAWN_TIME + 0.1)
		var definition: EnemyDefinition = enemy.definition
		player.pistol.request_fire()
		await physics_frames(2)
		check(player.pistol.ammo == 9, "one shot uses one round")
		check(is_equal_approx(enemy.health, definition.max_health - player.pistol.stats.damage), "hitscan shot damages the chaser")
		var shots := 1
		while is_instance_valid(enemy) and enemy.is_alive and shots < 10:
			await seconds(player.pistol.stats.seconds_between_shots() + 0.02)
			player.pistol.request_fire()
			await physics_frames(2)
			shots += 1
		var expected := ceili(definition.max_health / player.pistol.stats.damage)
		check(not is_instance_valid(enemy) or not enemy.is_alive, "chaser dies after %d shots (expected %d)" % [shots, expected])
		check(hits[0] == expected - 1 and hits[1] == 1, "hit markers: %d hits + %d kill" % [hits[0], hits[1]])
		check(game.kills == 1, "kill counted once")
		await physics_frames(2)
		check(game.get_node("Enemies").get_child_count() == 0, "dead chaser removed from the scene")

	func _test_reload(game: Node) -> void:
		var pistol: Pistol = game.player.pistol
		var before := pistol.ammo
		pistol.request_reload()
		check(pistol.is_reloading, "manual reload starts (ammo %d)" % before)
		await seconds(0.2)
		pistol.request_fire()
		await physics_frames(2)
		check(pistol.ammo == before, "cannot fire while reloading")
		await seconds(pistol.stats.reload_time)
		check(not pistol.is_reloading and pistol.ammo == pistol.stats.magazine_size, "reload refills the magazine")
		pistol.request_reload()
		check(not pistol.is_reloading, "reload with a full magazine is ignored")

	func _test_auto_reload(game: Node) -> void:
		var pistol: Pistol = game.player.pistol
		for i in pistol.stats.magazine_size:
			pistol.request_fire()
			await seconds(pistol.stats.seconds_between_shots() + 0.02)
		check(pistol.ammo == 0 and pistol.is_reloading, "emptying the magazine reloads automatically")
		await seconds(pistol.stats.reload_time + 0.1)
		check(pistol.ammo == pistol.stats.magazine_size, "automatic reload refills the magazine")

	func _test_pause(game: Node) -> void:
		game.pause()
		check(get_tree().paused and game.pause_menu.visible, "pause stops the game and shows the menu")
		var pistol: Pistol = game.player.pistol
		var ammo := pistol.ammo
		pistol.request_fire()
		await seconds(0.2)
		check(pistol.ammo == ammo, "gun does not fire while paused")
		game.resume()
		await physics_frames(2)
		check(not get_tree().paused and not game.pause_menu.visible, "resume unpauses and hides the menu")
		pistol._buffered_fire = 0.0

	func _test_enemy_attacks(game: Node) -> void:
		var player: Player = game.player
		var enemy := _spawn_in_front(game, 7.0)
		var start_health := player.health
		var elapsed := 0.0
		while player.health == start_health and elapsed < 8.0:
			await get_tree().physics_frame
			elapsed += 1.0 / Engine.physics_ticks_per_second
		check(player.health == start_health - enemy.definition.attack_damage,
			"chaser walks over and hits the player (%.1fs)" % elapsed)
		enemy.queue_free()
		await physics_frames(2)

	func _test_spawner(game: Node) -> void:
		var spawner: EnemySpawner = game.spawner
		spawner.max_active = 3
		spawner.spawn_interval = 0.05
		spawner.start(game.player, game.arena)
		spawner._timer = 0.0
		await seconds(0.6)
		spawner.stop()
		var enemies: Array = game.get_node("Enemies").get_children()
		check(spawner.active_count() == 3, "spawner respects the active-enemy cap (%d)" % spawner.active_count())
		var min_distance := INF
		for enemy: Node3D in enemies:
			min_distance = minf(min_distance, enemy.global_position.distance_to(game.player.global_position))
		check(min_distance >= spawner.min_player_distance, "no enemy spawned near the player (closest %.1f m)" % min_distance)

	func _test_death(game: Node) -> void:
		var player: Player = game.player
		player.take_damage(10000.0)
		await physics_frames(2)
		check(player.is_dead and player.health == 0.0, "lethal damage kills the player")
		check(game.hud.is_death_screen_visible(), "death screen shown")
		var ammo := player.pistol.ammo
		player.pistol.request_fire()
		await physics_frames(5)
		check(player.pistol.ammo == ammo, "dead player cannot shoot")
		player.take_damage(10.0)
		check(player.health == 0.0, "damage after death is ignored")

	func _test_clean_restart(game: Node) -> void:
		var player: Player = game.player
		check(not player.is_dead and player.health == player.max_health, "restart restores health")
		check(player.pistol.ammo == player.pistol.stats.magazine_size and not player.pistol.is_reloading, "restart restores the pistol")
		check(game.get_node("Enemies").get_child_count() == 0, "restart clears enemies")
		check(game.kills == 0, "restart resets kills")
		check(not get_tree().paused, "restart leaves the game unpaused")
		check(not game.hud.is_death_screen_visible(), "restart hides the death screen")

	# ------------------------------------------------------------------ helpers

	func _spawn_in_front(game: Node, distance: float) -> Chaser:
		var player: Player = game.player
		var forward := -player.global_basis.z
		forward.y = 0.0
		return game.spawner.spawn_at(player.global_position + forward.normalized() * distance)

	func _wait_for_main(previous: Node = null) -> Node:
		for i in 300:
			await get_tree().process_frame
			var scene := get_tree().current_scene
			if scene and scene.name == "Main" and scene != previous and scene.is_node_ready():
				await physics_frames(3)
				return scene
		push_error("Main scene never loaded")
		get_tree().quit(1)
		return null

	func physics_frames(count: int) -> void:
		for i in count:
			await get_tree().physics_frame

	func seconds(duration: float) -> void:
		await get_tree().create_timer(duration, true, true).timeout

	func check(condition: bool, description: String) -> void:
		checks += 1
		if condition:
			print("PASS  ", description)
		else:
			failures += 1
			print("FAIL  ", description)
