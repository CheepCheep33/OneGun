extends Node
## Where GPU-side hitches come from. Runs the real renderer (never headless) and prints, for each
## first-time event after the warm-up, the worst frame it caused and the GPU buffer and texture
## memory it allocated. Shader compiles, mesh uploads and texture uploads only exist with a
## renderer, so the headless gate (tests/cases/perf_cases.gd) cannot see them; this can:
##   xvfb-run -a -s "-screen 0 640x360x24" godot --path . --rendering-driver opengl3 \
##       --resolution 640x360 res://tests/gpu_probe.tscn
## Under llvmpipe (the container's and CI's renderer) a shader compile is an LLVM build and costs
## tens to hundreds of milliseconds, so anything the warm-up missed reads as a frame many times the
## idle frame. Memory that grows across a repeated event is an allocation per event.
## Mesa's on-disk shader cache hides the cost of a compile it has seen before, so run with
## MESA_SHADER_CACHE_DISABLE=true to see what a browser pays every session: there a compile is a
## frame tens to hundreds of milliseconds over the event's own median. `-- light_range=<m>`
## overrides the muzzle light's range (0.001 switches it off) to tell its cost apart. A tool, not a
## test: it never fails; tests/gpu_gate.sh runs it and turns its figures into a gate.

const CHASER := "res://data/enemies/chaser.tres"
const CHASER_SCENE := "res://scenes/enemies/chaser.tscn"
const SHOOTER := "res://data/enemies/shooter.tres"
const SHOOTER_SCENE := "res://scenes/enemies/shooter.tscn"
const WARDEN := "res://data/enemies/warden.tres"
const WARDEN_SCENE := "res://scenes/enemies/warden.tscn"


func _ready() -> void:
	var probe := Probe.new()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("light_range="):
			probe.light_range = float(arg.trim_prefix("light_range="))
	get_tree().root.add_child.call_deferred(probe)


class Probe:
	extends Node

	var game: Node
	var light_range := -1.0
	var _last_tick := 0

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
		if DisplayServer.get_name() == "headless":
			print("GPU PROBE needs a renderer; run it with a window (xvfb-run) and --rendering-driver opengl3.")
			get_tree().quit(1)
			return
		var pistol: Pistol = game.player.pistol
		if light_range >= 0.0:
			pistol._flash_light.omni_range = light_range
		# Let the warm-up, the enemy reserve and the first frames of the arena settle.
		await _seconds(2.5)
		game.start_wave(1)
		await _physics_frames(3)
		game.wave_runner.stop()
		game.wave_runner.clear_enemies()
		game.player.health = 1.0e9
		await _seconds(1.0)
		print("\nGPU PROBE  %s, %s, window %s, muzzle light range %.1f m" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(), DisplayServer.window_get_size(), pistol._flash_light.omni_range])
		print("Milliseconds per frame (whole frame, rendering included) and GPU memory the event allocated.")
		print("%-46s %8s %8s %8s %10s %10s" % ["event", "worst", "median", "frames", "buffers KB", "textures KB"])
		await _event("idle, nothing happening", 40, Callable(), false, "idle")
		await _event("first shot after warm-up (into the arena)", 8, func() -> void: pistol.request_fire())
		await _seconds(0.4)
		await _event("second shot", 8, func() -> void: pistol.request_fire(), true)
		await _seconds(0.4)
		var chaser := _spawn(CHASER, CHASER_SCENE, 5.0, 0.0)
		await _seconds(Enemy.SPAWN_TIME + 0.2)
		await _event("shot into an enemy (hit flash, damage number)", 8, func() -> void: pistol.request_fire())
		await _seconds(0.7)
		await _event("second hit", 8, func() -> void: pistol.request_fire(), true)
		await _seconds(0.7)
		var at: Vector3 = chaser.global_position + Vector3.UP
		await _event("twelve damage numbers rising and fading", 45, func() -> void:
			for i in 12:
				Fx.damage_number(game, at + Vector3(0.3 * i - 1.8, 0.1 * i, 0.0), 10.0 + 7 * i, i % 4 == 0))
		await _seconds(0.3)
		await _event("twelve damage numbers again", 45, func() -> void:
			for i in 12:
				Fx.damage_number(game, at + Vector3(0.3 * i - 1.8, 0.1 * i, 0.0), 10.0 + 7 * i, i % 4 == 0), true)
		await _seconds(0.3)
		await _event("the enemy dies (burst, death sound)", 12, func() -> void: chaser.take_hit(1.0e12, chaser.global_position, Vector3.FORWARD))
		await _seconds(1.0)
		var second := _spawn(CHASER, CHASER_SCENE, 5.0, 1.0)
		await _seconds(Enemy.SPAWN_TIME + 0.2)
		await _event("a second enemy dies", 12, func() -> void: second.take_hit(1.0e12, second.global_position, Vector3.FORWARD), true)
		await _seconds(1.0)
		var drop_at: Vector3 = game.player.global_position + -game.player.global_basis.z * 4.0
		drop_at.y = 0.0
		await _event("a loot drop lands", 8, func() -> void: game._spawn_drop(Items.make(&"long_barrel", Items.Rarity.UNCOMMON), drop_at))
		await _seconds(0.3)
		await _event("a second loot drop lands", 8, func() -> void: game._spawn_drop(Items.make(&"fast_magazine", Items.Rarity.RARE), drop_at + Vector3.RIGHT * 1.5), true)
		await _seconds(0.3)
		await _event("the drops are picked up", 8, func() -> void:
			for drop in game.drops.get_children():
				drop.collect(), true)
		await _seconds(0.3)
		var shooter: Shooter = _spawn(SHOOTER, SHOOTER_SCENE, 9.0, 0.0)
		shooter.health = 1.0e9
		await _seconds(Enemy.SPAWN_TIME + 0.2)
		await _event("a shooter aims and fires a bolt", 70, func() -> void: shooter._enter(Shooter.Phase.AIM))
		await _event("the shooter fires again", 70, func() -> void: shooter._enter(Shooter.Phase.AIM), true)
		game.wave_runner.clear_enemies()
		game.projectiles.clear_all()
		await _seconds(0.5)
		await _event("the Warden spawns from the reserve", 20, func() -> void: _spawn(WARDEN, WARDEN_SCENE, 10.0, 0.0))
		await _seconds(0.5)
		game.wave_runner.clear_enemies()
		await _seconds(0.3)
		await _event("the Warden spawns again", 20, func() -> void: _spawn(WARDEN, WARDEN_SCENE, 10.0, 0.0), true)
		await _seconds(0.5)
		game.wave_runner.clear_enemies()
		await _event("a reload", 12, func() -> void:
			pistol.ammo = 1
			pistol.request_reload())
		await _seconds(1.0)
		await _event("a second reload", 12, func() -> void:
			pistol.ammo = 1
			pistol.request_reload(), true)
		await _seconds(1.0)
		pistol.apply_build(Progression.build_stats(), Progression.equipped())
		var automatic := Items.make(&"automatic")
		var build := {"receiver": automatic}
		pistol.apply_build(WeaponStats.build(Progression.PISTOL_BASE, Progression.core_levels(), build), build)
		var crowd: Array[Enemy] = []
		for i in 8:
			var enemy := _spawn(CHASER, CHASER_SCENE, 4.5 + 1.2 * (i % 4), -2.0 + 1.3 * (i / 4))
			enemy.health = 1.0e9
			crowd.append(enemy)
		await _seconds(Enemy.SPAWN_TIME + 0.2)
		await _event("automatic fire into eight enemies, two seconds", 120, func() -> void: pistol.request_fire(), false, "heavy")
		pistol.release_fire()
		pistol.apply_build(Progression.build_stats(), Progression.equipped())
		game.wave_runner.clear_enemies()
		print("")
		get_tree().quit(0)

	## Runs `action`, then measures `frames` frames: the worst and median frame and the change in
	## GPU buffer and texture memory from before the action to after the frames. `repeat` marks an
	## event that happened before in this run, which must allocate nothing; `kind` is "idle" for the
	## baseline and "heavy" for a load whose frames are long by nature. The gate reads the
	## GPU_EVENT lines: label, worst, median, frames, buffer bytes, texture bytes, flags.
	func _event(label: String, frames: int, action: Callable, repeat := false, kind := "") -> void:
		await get_tree().process_frame
		var buffers_before := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)
		var textures_before := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
		_last_tick = Time.get_ticks_usec()
		if action.is_valid():
			action.call()
		var gaps: Array[float] = []
		for i in frames:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			gaps.append((now - _last_tick) / 1000.0)
			_last_tick = now
		gaps.sort()
		var buffers := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) - buffers_before
		var textures := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) - textures_before
		var flags := PackedStringArray()
		if repeat:
			flags.append("repeat")
		if kind != "":
			flags.append(kind)
		print("%-46s %8.1f %8.1f %8d %10.1f %10.1f" % [label, gaps[gaps.size() - 1], gaps[gaps.size() / 2], frames, buffers / 1024.0, textures / 1024.0])
		print("GPU_EVENT|%s|%.1f|%.1f|%d|%d|%d|%s" % [label, gaps[gaps.size() - 1], gaps[gaps.size() / 2], frames, buffers, textures, ",".join(flags)])

	func _spawn(definition_path: String, scene_path: String, distance: float, side: float) -> Enemy:
		var player: Player = game.player
		var forward := -player.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := forward.cross(Vector3.UP)
		var definition: EnemyDefinition = load(definition_path).duplicate()
		definition.loot_weight = 0.0
		return game.wave_runner.spawn_at(player.global_position + forward * distance + right * side, definition, load(scene_path))

	func _physics_frames(count: int) -> void:
		for i in count:
			await get_tree().physics_frame

	func _seconds(duration: float) -> void:
		await get_tree().create_timer(duration, true, true).timeout
