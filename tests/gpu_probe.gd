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
const HEAVY := "res://data/enemies/heavy.tres"
const HEAVY_SCENE := "res://scenes/enemies/heavy.tscn"
const BEARER := "res://data/enemies/shield_bearer.tres"
const BEARER_SCENE := "res://scenes/enemies/shield_bearer.tscn"
const FOREMAN := "res://data/enemies/foreman.tres"
const FOREMAN_SCENE := "res://scenes/enemies/foreman.tscn"
const TURRET := "res://data/enemies/turret.tres"
const TURRET_SCENE := "res://scenes/enemies/turret.tscn"
const SENTINEL := "res://data/enemies/sentinel.tres"
const SENTINEL_SCENE := "res://scenes/enemies/sentinel.tscn"
const GUARDIAN := "res://data/enemies/core_guardian.tres"
const GUARDIAN_SCENE := "res://scenes/enemies/core_guardian.tscn"


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
		await _milestone_4_events(pistol)
		await _milestone_5_events(pistol)
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
		await _scrapyard_events()
		await _foundry_events()
		await _tower_events()
		print("")
		get_tree().quit(0)

	## Milestone 4: Explosive shells and their blast, the Splitter, the heavy's weak point, the
	## shield bearer's shield, and the Foreman's summons and molten pool.
	func _milestone_4_events(pistol: Pistol) -> void:
		var explosive := {"ammo": Items.make(&"explosive_rounds")}
		pistol.apply_build(WeaponStats.build(Progression.PISTOL_BASE, Progression.core_levels(), explosive), explosive)
		var target := _spawn(CHASER, CHASER_SCENE, 6.0, 0.0)
		target.health = 1.0e9
		await _seconds(Enemy.SPAWN_TIME + 0.4)
		await _event("an explosive shell bursts on an enemy", 30, func() -> void: pistol.request_fire())
		await _seconds(0.6)
		await _event("a second explosive shell", 30, func() -> void: pistol.request_fire(), true)
		await _seconds(0.6)
		var splitter := {"muzzle": Items.make(&"splitter")}
		pistol.apply_build(WeaponStats.build(Progression.PISTOL_BASE, Progression.core_levels(), splitter), splitter)
		await _seconds(0.3)
		await _event("a Splitter shot (three rays)", 10, func() -> void: pistol.request_fire())
		await _seconds(0.5)
		await _event("a second Splitter shot", 10, func() -> void: pistol.request_fire(), true)
		await _seconds(0.5)
		pistol.apply_build(Progression.build_stats(), Progression.equipped())
		game.wave_runner.clear_enemies()
		await _seconds(0.3)
		# Lambdas capture locals by value, so each spawn lands in a holder array.
		var spawned: Array[Enemy] = []
		await _event("a heavy spawns from the reserve", 20, func() -> void: spawned.append(_spawn(HEAVY, HEAVY_SCENE, 7.0, 0.0)))
		var heavy: Enemy = spawned.pop_back()
		heavy.health = 1.0e9
		await _seconds(Enemy.SPAWN_TIME + 0.2)
		var core: Vector3 = heavy.to_global(heavy.definition.weak_point_offset)
		await _event("a weak-point hit (gold number)", 30, func() -> void:
			ShotPipeline.apply_hit(heavy, core, Vector3.FORWARD, pistol.stats, WeaponStats.ShotContext.new(), _shot(pistol))
			Fx.damage_number(game, core, 20.0, false, true))
		await _seconds(0.7)
		await _event("a shield bearer spawns from the reserve", 20, func() -> void: spawned.append(_spawn(BEARER, BEARER_SCENE, 6.0, 2.5)))
		var bearer: Enemy = spawned.pop_back()
		bearer.health = 1.0e9
		await _seconds(Enemy.SPAWN_TIME + 0.5)
		game.player.look_at(Vector3(bearer.global_position.x, game.player.global_position.y, bearer.global_position.z), Vector3.UP)
		await _seconds(0.2)
		await _event("a shot stops on the shield", 10, func() -> void: pistol.request_fire())
		await _seconds(0.5)
		await _event("a second shot on the shield", 10, func() -> void: pistol.request_fire(), true)
		await _seconds(0.5)
		game.wave_runner.clear_enemies()
		game.player.rotation = Vector3.ZERO
		await _seconds(0.3)
		await _event("the Foreman spawns from the reserve", 20, func() -> void: spawned.append(_spawn(FOREMAN, FOREMAN_SCENE, 12.0, 0.0)))
		var foreman: Foreman = spawned.pop_back()
		foreman.health = 1.0e9
		foreman._volley_cooldown = 99.0
		foreman._pool_cooldown = 99.0
		await _seconds(Enemy.SPAWN_TIME + 0.2)
		await _event("the Foreman calls in drones", 100, func() -> void: foreman._summon_cooldown = 0.0)
		await _event("the Foreman lays a molten pool", 110, func() -> void: foreman.lay_pool(game.player.global_position + -game.player.global_basis.z * 4.0))
		await _event("a second molten pool", 110, func() -> void: foreman.lay_pool(game.player.global_position + -game.player.global_basis.z * 4.0 + Vector3.RIGHT * 3.0), true)
		game.wave_runner.clear_enemies()
		game.projectiles.clear_all()
		await _seconds(0.5)

	## Milestone 5: the status ammo (frost, shatter, arcs, burns), a charged shot, a grenade, the
	## turret's aim line and heavy bolt with the Scanner's marker, the Sentinel's sweep, and the Core
	## Guardian's slam, vent and boss card.
	func _milestone_5_events(pistol: Pistol) -> void:
		var target := _spawn(CHASER, CHASER_SCENE, 6.0, 0.0)
		target.health = 1.0e9
		var neighbour := _spawn(CHASER, CHASER_SCENE, 6.0, 1.5)
		neighbour.health = 1.0e9
		await _seconds(Enemy.SPAWN_TIME + 0.4)
		var context := WeaponStats.ShotContext.new()
		var cryo := {"ammo": Items.make(&"cryo")}
		var cryo_stats := WeaponStats.build(Progression.PISTOL_BASE, Progression.core_levels(), cryo)
		await _event("a Cryo hit frosts an enemy", 20, func() -> void:
			ShotPipeline.apply_hit(target, target.center(), Vector3.FORWARD, cryo_stats, context, _shot(pistol)))
		await _event("a Cryo shatter", 30, func() -> void:
			target.slow_age = StatusEffects.SHATTER_AFTER + 0.1
			ShotPipeline.apply_hit(target, target.center(), Vector3.FORWARD, cryo_stats, context, _shot(pistol)))
		await _seconds(0.5)
		await _event("a second Cryo shatter", 30, func() -> void:
			ShotPipeline.apply_hit(target, target.center(), Vector3.FORWARD, cryo_stats, context, _shot(pistol))
			target.slow_age = StatusEffects.SHATTER_AFTER + 0.1
			ShotPipeline.apply_hit(target, target.center(), Vector3.FORWARD, cryo_stats, context, _shot(pistol)), true)
		var shock_stats := WeaponStats.build(Progression.PISTOL_BASE, Progression.core_levels(), {"ammo": Items.make(&"shock")})
		await _event("a Shock hit arcs and stuns", 20, func() -> void:
			ShotPipeline.apply_hit(target, target.center(), Vector3.FORWARD, shock_stats, context, _shot(pistol)))
		await _seconds(0.4)
		await _event("a second Shock arc", 20, func() -> void:
			ShotPipeline.apply_hit(target, target.center(), Vector3.FORWARD, shock_stats, context, _shot(pistol)), true)
		var burn_stats := WeaponStats.build(Progression.PISTOL_BASE, Progression.core_levels(), {"ammo": Items.make(&"incendiary")})
		await _event("an Incendiary hit sets an enemy burning", 40, func() -> void:
			ShotPipeline.apply_hit(neighbour, neighbour.center(), Vector3.FORWARD, burn_stats, context, _shot(pistol)))
		var charge := {"receiver": Items.make(&"charge")}
		pistol.apply_build(WeaponStats.build(Progression.PISTOL_BASE, Progression.core_levels(), charge), charge)
		await _seconds(0.3)
		await _event("the Charge meter fills", 40, func() -> void: pistol.request_fire())
		await _event("a charged round fires", 20, func() -> void: pistol.release_fire())
		await _seconds(0.4)
		pistol.request_fire()
		await _seconds(pistol.stats.charge_time() + 0.1)
		await _event("a second charged round", 20, func() -> void: pistol.release_fire(), true)
		var launcher := {"underbarrel": Items.make(&"launcher"), "optic": Items.make(&"scanner")}
		pistol.apply_build(WeaponStats.build(Progression.PISTOL_BASE, Progression.core_levels(), launcher), launcher)
		await _seconds(0.3)
		pistol.grenades = Pistol.GRENADE_MAX
		await _event("a Launcher grenade flies and bursts", 70, func() -> void: pistol.request_alt_fire())
		pistol._grenade_cooldown = 0.0
		await _event("a second grenade", 70, func() -> void: pistol.request_alt_fire(), true)
		game.wave_runner.clear_enemies()
		await _seconds(0.3)
		var spawned: Array[Enemy] = []
		await _event("a turret spawns, the Scanner marks it", 20, func() -> void: spawned.append(_spawn(TURRET, TURRET_SCENE, 8.0, 0.0)))
		var turret: Turret = spawned.pop_back()
		turret.health = 1.0e9
		await _seconds(Enemy.SPAWN_TIME + 0.2)
		await _event("the turret's aim line and heavy bolt", 130, func() -> void: turret._cooldown_left = 0.0)
		await _event("the turret aims and fires again", 130, func() -> void: turret._cooldown_left = 0.0, true)
		game.wave_runner.clear_enemies()
		game.projectiles.clear_all()
		game.hud.clear_scan_targets()
		pistol.apply_build(Progression.build_stats(), Progression.equipped())
		await _seconds(0.3)
		await _event("a story card shows", 20, func() -> void: game.hud.show_story("VERA", "The probe's line: a card over the arena, the way a boss's intro shows."))
		game.hud.hide_story()
		await _event("the Sentinel spawns, its card shows", 20, func() -> void: spawned.append(_spawn(SENTINEL, SENTINEL_SCENE, 10.0, 0.0)))
		var sentinel: Sentinel = spawned.pop_back()
		sentinel.health = 1.0e9
		await _seconds(Enemy.SPAWN_TIME + 0.2)
		await _event("the Sentinel's sweep: warning, then beam", 150, func() -> void:
			sentinel.sweep.start(game.player.global_position, sentinel.global_position))
		await _event("a second sweep", 150, func() -> void:
			sentinel.sweep.start(game.player.global_position, sentinel.global_position), true)
		game.wave_runner.clear_enemies()
		game.hud.hide_story()
		await _seconds(0.3)
		await _event("the Core Guardian spawns", 20, func() -> void: spawned.append(_spawn(GUARDIAN, GUARDIAN_SCENE, 12.0, 0.0)))
		var guardian: CoreGuardian = spawned.pop_back()
		guardian.health = 1.0e9
		await _seconds(Enemy.SPAWN_TIME + 0.2)
		await _event("the Guardian's slam ring", 30, func() -> void: guardian._slam())
		await _event("the Guardian vents, core open", 30, func() -> void: guardian._start_vent())
		await _event("the vent ends, core shut", 30, func() -> void: guardian._end_vent())
		await _event("the Guardian vents again", 30, func() -> void: guardian._start_vent(), true)
		game.wave_runner.clear_enemies()
		game.projectiles.clear_all()
		game.hud.hide_story()
		await _seconds(0.5)

	## The Foundry's heat strips warn and melt mid-run.
	func _foundry_events() -> void:
		Progression.add_unlock("foundry")
		for wave in range(1, 11):
			Progression.record_wave_cleared(wave, 0, 1.0)
		game.open_bench()
		await _seconds(0.3)
		game.enter_area("foundry")
		await _seconds(2.5)
		game.wave_runner.stop()
		game.wave_runner.clear_enemies()
		game.player.health = 1.0e9
		var foundry: Node3D = game.arena
		foundry.running = false # the strips change only when this probe says
		await _seconds(0.5)
		var strips: Array = foundry._strips
		await _event("a heat strip warns", 20, func() -> void: strips[0].get_node("Warning").visible = true)
		await _event("the strip melts", 20, func() -> void:
			strips[0].get_node("Warning").visible = false
			strips[0].get_node("Molten").visible = true)
		await _event("a second strip warns and melts", 20, func() -> void:
			strips[1].get_node("Warning").visible = true
			strips[1].get_node("Molten").visible = true, true)

	## The Signal Tower's pad lights between floors.
	func _tower_events() -> void:
		for wave in range(1, 16):
			Progression.record_wave_cleared(wave, 0, 1.0)
		game.open_bench()
		await _seconds(0.3)
		game.enter_area("signal_tower")
		await _seconds(2.5)
		game.wave_runner.stop()
		game.wave_runner.clear_enemies()
		game.player.health = 1.0e9
		var tower: Node3D = game.arena
		await _seconds(0.5)
		await _event("the tower's pad lights", 20, func() -> void: tower._set_pad(true))
		await _event("the pad goes dark", 20, func() -> void: tower._set_pad(false))
		await _event("the pad lights again", 20, func() -> void: tower._set_pad(true), true)

	## The Scrapyard: entering is a load at the bench, but the door opening and a core pickup happen
	## mid-run.
	func _scrapyard_events() -> void:
		for wave in [1, 2, 3, 4, 5]:
			Progression.record_wave_cleared(wave, 0, 1.0)
		game.open_bench()
		await _seconds(0.3)
		game.enter_area("scrapyard")
		await _seconds(2.5)
		game.wave_runner.stop()
		game.wave_runner.clear_enemies()
		game.player.health = 1.0e9
		var yard: Node3D = game.arena
		await _seconds(0.5)
		await _event("the Scrapyard's door opens", 20, func() -> void: yard._set_door(true))
		var core: Node3D = yard._cores[0]
		await _event("a scrap core is picked up", 10, func() -> void:
			game.player.global_position = Vector3(core.global_position.x, game.player.global_position.y, core.global_position.z))

	func _shot(pistol: Pistol) -> ShotPipeline.ShotState:
		var shot := ShotPipeline.ShotState.new()
		shot.rng = RandomNumberGenerator.new()
		shot.scene = pistol
		return shot

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
