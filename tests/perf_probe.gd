extends Node
## Profiles game logic per frame by load, headless, so a performance regression can be pinned to a
## subsystem before anyone opens a browser:
##   godot --headless --path . res://tests/perf_probe.tscn
## Prints the game-logic cost of one 60 Hz frame (process callbacks plus one physics step, in
## milliseconds, measured the way tests/cases/perf_cases.gd measures it) for several arena loads.
## A tool, not a test: it never fails. The gate is perf_cases.gd.

const SAMPLE_SECONDS := 1.5
const CHASER := "res://data/enemies/chaser.tres"
const CHASER_SCENE := "res://scenes/enemies/chaser.tscn"
const SHOOTER := "res://data/enemies/shooter.tres"
const SHOOTER_SCENE := "res://scenes/enemies/shooter.tscn"
const DRONE := "res://data/enemies/swarm_drone.tres"
const DRONE_SCENE := "res://scenes/enemies/swarm_drone.tscn"


func _ready() -> void:
	var probe := Probe.new()
	get_tree().root.add_child.call_deferred(probe)


class Probe:
	extends Node

	var game: Node

	func _ready() -> void:
		_run.call_deferred()

	func _run() -> void:
		SaveFile.in_memory = true # never touch a developer's real save
		Progression.data = SaveFile.fresh()
		Progression._restore_loot_state()
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		for i in 300:
			await get_tree().process_frame
			var scene := get_tree().current_scene
			if scene and scene.name == "Main" and scene.is_node_ready():
				game = scene
				break
		if game == null:
			push_error("Main scene never loaded")
			get_tree().quit(1)
			return
		await _physics_frames(5)
		OS.low_processor_usage_mode_sleep_usec = 0 # headless Godot sleeps this long every frame
		var started := Time.get_ticks_usec()
		var sink := 0.0
		for i in 2000000:
			sink += sqrt(float(i)) * 0.5
		print("calibration loop: %.1f ms (sink %.0f)" % [(Time.get_ticks_usec() - started) / 1000.0, sink])
		game.start_wave(1)
		await _physics_frames(3)
		game.wave_runner.stop()
		game.wave_runner.clear_enemies()
		game.player.health = 1.0e9
		print("\nPERF PROBE  game logic per 60 Hz frame, headless (no rendering), milliseconds.")
		print("%-44s %9s %9s %9s %9s %9s" % ["load", "frame", "process", "physics", "worst ph", "worst pr"])
		# Enemies are recycled through the wave runner's reserve, so every tweak is undone after
		# its scenario (the untweak) or it would carry into the next one.
		var no_agent := func(e: Enemy) -> void: e._agent = null
		var agent_back := func(e: Enemy) -> void: e._agent = e.get_node("NavigationAgent3D")
		await _scenario("empty arena", 0, "", "", false, Callable(), Callable())
		await _scenario("16 chasers, frozen (no physics step)", 16, CHASER, CHASER_SCENE, false,
			func(e: Enemy) -> void: e.process_mode = Node.PROCESS_MODE_DISABLED,
			func(e: Enemy) -> void: e.process_mode = Node.PROCESS_MODE_INHERIT)
		await _scenario("16 chasers walking", 16, CHASER, CHASER_SCENE, false, Callable(), Callable())
		await _scenario("16 chasers, straight line (no nav agent)", 16, CHASER, CHASER_SCENE, false, no_agent, agent_back)
		await _scenario("16 chasers, no enemy-enemy collision", 16, CHASER, CHASER_SCENE, false,
			func(e: Enemy) -> void: e.collision_mask = 3,
			func(e: Enemy) -> void: e.collision_mask = 7)
		await _scenario("16 chasers, max_slides 2, no snap", 16, CHASER, CHASER_SCENE, false,
			func(e: Enemy) -> void:
				e.max_slides = 2
				e.floor_snap_length = 0.0,
			func(e: Enemy) -> void:
				e.max_slides = 6
				e.floor_snap_length = 0.1)
		await _scenario("8 chasers walking", 8, CHASER, CHASER_SCENE, false, Callable(), Callable())
		await _scenario("8 drones", 8, DRONE, DRONE_SCENE, false, Callable(), Callable())
		await _scenario("4 shooters", 4, SHOOTER, SHOOTER_SCENE, false, Callable(), Callable())
		await _scenario("8 chasers, straight line (no nav agent)", 8, CHASER, CHASER_SCENE, false, no_agent, agent_back)
		await _scenario("automatic fire + bolts, no enemies", 0, "", "", true, Callable(), Callable())
		await _scenario("16 chasers + automatic fire + bolts", 16, CHASER, CHASER_SCENE, true, Callable(), Callable())
		print("")
		get_tree().quit(0)

	func _scenario(label: String, count: int, definition_path: String, scene_path: String, fire: bool, tweak: Callable, untweak: Callable) -> void:
		var player: Player = game.player
		var pistol: Pistol = player.pistol
		var pool: ProjectilePool = game.projectiles
		player.revive(game.arena.get_player_start())
		player.health = 1.0e9
		game.state = game.State.COMBAT
		var forward := -player.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := forward.cross(Vector3.UP)
		var enemies: Array[Enemy] = []
		for i in count:
			var definition: EnemyDefinition = load(definition_path).duplicate()
			definition.loot_weight = 0.0
			var enemy: Enemy = game.wave_runner.spawn_at(player.global_position + forward * (4.5 + 1.6 * (i % 5)) + right * (-3.0 + 2.0 * (i / 5)),
				definition, load(scene_path))
			enemy.health = 1.0e9
			if tweak.is_valid():
				tweak.call(enemy)
			enemies.append(enemy)
		if fire:
			var item := Items.make(&"automatic")
			var build := {"receiver": item}
			pistol.apply_build(WeaponStats.build(Progression.PISTOL_BASE, Progression.core_levels(), build), build)
		await _seconds(Enemy.SPAWN_TIME + 0.2)
		var elapsed := 0.0
		var volley := 0.0
		var cost := preload("res://tests/cases/perf_cases.gd").FrameCost.new()
		if fire:
			pistol.request_fire()
		cost.start()
		while elapsed < SAMPLE_SECONDS:
			await get_tree().process_frame
			cost.sample()
			var delta := get_process_delta_time()
			elapsed += delta
			if fire:
				volley -= delta
				if volley <= 0.0:
					volley = 0.1
					for i in 3:
						pool.fire_enemy_bolt(null, player.global_position + Vector3(randf_range(-3.0, 3.0), 5.0, randf_range(-3.0, 3.0)), Vector3.DOWN * 20.0, 1.0, Color.RED, 1.0)
		if fire:
			pistol.release_fire()
			pistol.apply_build(Progression.build_stats(), Progression.equipped())
		var r := cost.result()
		print("%-44s %9.2f %9.2f %9.2f %9.1f %9.1f" % [label, r["frame"], r["process"], r["physics"], r["worst_physics"], r["worst_process"]])
		for enemy in enemies:
			if untweak.is_valid() and is_instance_valid(enemy):
				untweak.call(enemy)
		game.wave_runner.clear_enemies()
		pool.clear_all()
		await _physics_frames(3)

	func _physics_frames(count: int) -> void:
		for i in count:
			await get_tree().physics_frame

	func _seconds(duration: float) -> void:
		await get_tree().create_timer(duration, true, true).timeout
