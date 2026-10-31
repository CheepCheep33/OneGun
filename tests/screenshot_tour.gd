extends Node
## Drives the real game through the bench, waves, the Warden, the Firing Range, the cleared banner
## and the death screen, saving a screenshot of each. Needs a window (use xvfb-run headlessly):
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
		SaveFile.in_memory = true # never touch a developer's real save
		Progression.data = SaveFile.fresh()
		Progression._restore_loot_state()
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

		# A returning player: a few waves cleared, drops in the inventory, one fitted.
		Progression.add_credits(140)
		for wave in [1, 2, 3]:
			Progression.record_wave_cleared(wave, 0, 42.0)
		var long_barrel := Items.make(&"long_barrel", Items.Rarity.UNCOMMON, [{"id": "sharp", "roll": 0.8}])
		Progression.add_item(long_barrel, "tour")
		Progression.equip(int(long_barrel["uid"]))
		Progression.add_item(Items.make(&"fast_magazine"), "tour")
		Progression.add_item(Items.make(&"penetrator_barrel", Items.Rarity.RARE, [{"id": "rapid", "roll": 0.5}, {"id": "keen", "roll": 0.9}]), "tour")
		Progression.add_item(Items.make(&"extended_magazine", Items.Rarity.UNCOMMON, [{"id": "quick", "roll": 0.3}]), "tour")
		game.bench.open()
		await _frames(3)
		game.bench.select_item(int(Progression.inventory()[1]["uid"]))
		await _frames(2)
		await _shot("02_bench_gunsmith_compare")

		# Wave 4: shooters and a floor drop with its beam, with the FPS readout on.
		Settings.set_value(&"show_fps", true)
		game.start_wave(4)
		await _frames(5)
		await _seconds(7.0)
		var shooter: Enemy = game.wave_runner.spawn_at(game.player.global_position + -game.player.global_basis.z * 9.0 + Vector3.RIGHT * 2.0,
			load("res://data/enemies/shooter.tres"), load("res://scenes/enemies/shooter.tscn"))
		game._spawn_drop(Items.make(&"long_barrel", Items.Rarity.UNCOMMON, [{"id": "sharp", "roll": 0.5}]),
			game.player.global_position + -game.player.global_basis.z * 4.0 + Vector3.LEFT * 1.5)
		await _seconds(1.2)
		if is_instance_valid(shooter) and shooter.is_alive:
			shooter._enter(Shooter.Phase.AIM)
		game.player.pistol.request_fire()
		await _frames(2)
		await _shot("03_wave_4_shooter_and_drop")

		# The Warden with its boss bar and slam ring.
		game.open_bench()
		await _frames(2)
		Progression.record_wave_cleared(4, 0, 30.0)
		game.start_wave(5)
		await _frames(5)
		var warden: Enemy = game.wave_runner.spawn_at(game.player.global_position + -game.player.global_basis.z * 6.0,
			load("res://data/enemies/warden.tres"), load("res://scenes/enemies/warden.tscn"))
		await _seconds(Enemy.SPAWN_TIME + 0.2)
		warden.take_hit(120.0, warden.global_position, Vector3.FORWARD)
		warden._charge_cooldown = 99.0
		warden._slam_cooldown = 0.0
		warden._enter(Warden.Phase.SLAM_TELEGRAPH)
		warden._ring.visible = true
		await _seconds(0.6)
		await _shot("04_warden_slam_telegraph")

		game.wave_runner.stop()
		game.wave_runner.clear_enemies()
		game.hud.hide_boss()
		await _frames(2)
		game.hud.show_wave_cleared(5, 240, true, long_barrel)
		await _frames(3)
		await _shot("05_wave_cleared_banner")
		game.hud._banner.visible = false

		# The Firing Range: dummies with readouts and the gallery plates.
		game.open_bench()
		await _frames(2)
		game.enter_area("firing_range")
		await _frames(6)
		game.player.pistol.request_fire()
		await _frames(3)
		await _shot("06_firing_range")

		Settings.set_value(&"show_fps", false)
		game.pause()
		await _frames(3)
		await _shot("07_pause_in_range")
		game.abandon_wave()
		await _frames(4)

		# The overflow tray after a lucky run.
		for i in Progression.INVENTORY_SIZE + 3:
			Progression.add_item(Items.make(&"fast_magazine"), "tour")
		game.bench.open()
		await _frames(3)
		await _shot("08_bench_overflow_tray")

		game.start_wave(2)
		await _frames(5)
		game.player.take_damage(10000.0)
		await _frames(3)
		await _shot("09_death_screen")

		# Milestone 4: the crafting table with a Rare selected for a reroll.
		game.open_bench()
		await _frames(2)
		for part in ["scrap", "alloy", "circuits", "cores"]:
			Progression.data["parts"][part] = 12
		var rare := Items.make(&"splitter", Items.Rarity.RARE, [{"id": "sharp", "roll": 0.6}, {"id": "deep", "roll": 0.2}, {"id": "arcing", "roll": 0.7}])
		Progression.data["inventory"].clear()
		Progression.data["overflow"].clear()
		Progression.add_item(rare, "tour")
		game.bench.open()
		game.bench.show_tab("craft")
		game.bench.select_item(int(rare["uid"]))
		await _frames(3)
		await _shot("10_bench_crafting_table")

		# Wave 11's roster: heavies and shield bearers, Splitter and Explosive shells in the air.
		for wave in range(1, 11):
			Progression.record_wave_cleared(wave, 0, 30.0)
		game.start_wave(11)
		await _frames(5)
		game.wave_runner.stop()
		var ahead: Vector3 = -game.player.global_basis.z
		for spot in [[7.0, -2.5, "heavy"], [6.0, 1.5, "shield_bearer"], [9.0, 3.5, "heavy"], [8.0, -0.5, "shield_bearer"]]:
			game.wave_runner.spawn_at(game.player.global_position + ahead * spot[0] + Vector3.RIGHT * spot[1],
				load("res://data/enemies/%s.tres" % spot[2]), load("res://scenes/enemies/%s.tscn" % spot[2]))
		await _seconds(Enemy.SPAWN_TIME + 0.6)
		var shells := {"muzzle": Items.make(&"splitter"), "ammo": Items.make(&"explosive_rounds")}
		game.player.pistol.apply_build(WeaponStats.build(Progression.PISTOL_BASE, Progression.core_levels(), shells), shells)
		game.player.pistol.request_fire()
		await _frames(6)
		await _shot("11_heavies_and_shield_bearers")

		# The Foreman: a summon telegraph, a molten pool warning and one burning.
		game.wave_runner.clear_enemies()
		game.projectiles.clear_all()
		await _frames(2)
		var foreman: Foreman = game.wave_runner.spawn_at(game.player.global_position + ahead * 10.0,
			load("res://data/enemies/foreman.tres"), load("res://scenes/enemies/foreman.tscn"))
		await _seconds(Enemy.SPAWN_TIME + 0.2)
		foreman._volley_cooldown = 99.0
		foreman._pool_cooldown = 99.0
		foreman.lay_pool(game.player.global_position + ahead * 4.0 + Vector3.RIGHT * 2.5)
		await _seconds(Foreman.POOL_WARNING + 0.3)
		foreman.lay_pool(game.player.global_position + ahead * 5.0 + Vector3.LEFT * 2.5)
		foreman._summon_cooldown = 0.0
		await _seconds(0.7)
		await _shot("12_foreman_pools_and_summon")
		game.wave_runner.clear_enemies()

		# The Scrapyard: wrecks in rows, scrap cores, the sealed door; then the extraction banner.
		game.open_bench()
		await _frames(2)
		Progression.record_wave_cleared(5, 0, 30.0)
		game.enter_area("scrapyard")
		await _seconds(2.0)
		await _shot("13_scrapyard")
		var yard: Node3D = game.arena
		yard.elapsed = yard.RUN_SECONDS
		await _frames(3)
		game.player.global_position = Vector3(yard._pad.global_position.x, game.player.global_position.y, yard._pad.global_position.z)
		await _frames(6)
		await _shot("14_scrapyard_extracted")

		# Milestone 5: the skills tab with points to spend and a few nodes taken.
		game.open_bench()
		await _frames(2)
		Progression.add_xp(6000)
		Progression.take_skill(&"steady_hands")
		Progression.take_skill(&"deadeye")
		Progression.take_skill(&"toughness")
		game.bench.open()
		game.bench.show_tab("skills")
		game.bench._show_skill_detail(&"deadeye")
		await _frames(3)
		await _shot("15_bench_skills")

		# The craft tab's refine, fuse and transmute on an Epic with a Legendary.
		var epic := Items.make(&"long_barrel", Items.Rarity.EPIC, [{"id": "sharp", "roll": 0.7}, {"id": "deep", "roll": 0.4}])
		Progression.add_item(epic, "tour")
		Progression.data["parts"]["legendary_cores"] = 1
		Progression.add_credits(2000)
		game.bench.open()
		game.bench.show_tab("craft")
		game.bench.select_item(int(epic["uid"]))
		await _frames(3)
		game.bench._tab_views["craft"].scroll_vertical = 10000 # down to the upgrade section
		await _frames(2)
		await _shot("16_bench_refine_fuse_transmute")
		game.bench.show_tab("story")
		Progression.fire_story("wave_5")
		Progression.fire_story("log_scrapyard_1")
		game.bench.refresh()
		await _frames(3)
		await _shot("17_bench_story_log")

		# Wave 13's turrets, aiming, with the Scanner marking them.
		for wave in range(1, 16):
			Progression.record_wave_cleared(wave, 0, 30.0)
		var scanner := {"optic": Items.make(&"scanner")}
		game.start_wave(13)
		await _frames(5)
		game.wave_runner.stop()
		game.wave_runner.clear_enemies()
		game.player.pistol.apply_build(WeaponStats.build(Progression.PISTOL_BASE, Progression.core_levels(), scanner), scanner)
		ahead = -game.player.global_basis.z
		var turrets: Array = []
		for spot in [[8.0, -3.0], [8.0, 3.0]]:
			turrets.append(game.wave_runner.spawn_at(game.player.global_position + ahead * spot[0] + Vector3.RIGHT * spot[1],
				load("res://data/enemies/turret.tres"), load("res://scenes/enemies/turret.tscn")))
		await _seconds(Enemy.SPAWN_TIME + 0.2)
		for turret in turrets:
			turret._cooldown_left = 0.0
		await _seconds(0.8)
		await _shot("18_turrets_aiming_scanner")

		# The Sentinel: its intro card, shield arcs and the sweep's warning line.
		game.wave_runner.clear_enemies()
		game.projectiles.clear_all()
		game.player.health = 1.0e9
		var sentinel: Sentinel = game.wave_runner.spawn_at(game.player.global_position + ahead * 9.0,
			load("res://data/enemies/sentinel.tres"), load("res://scenes/enemies/sentinel.tscn"))
		await _seconds(Enemy.SPAWN_TIME + 0.2)
		sentinel.set_physics_process(false)
		sentinel.sweep.start(game.player.global_position, sentinel.global_position)
		for i in 30:
			sentinel.sweep.tick(1.0 / 60.0, sentinel, game.player)
		await _frames(2)
		await _shot("19_sentinel_arcs_and_sweep")

		# The Core Guardian venting: the core open between phases.
		sentinel.set_physics_process(true)
		game.wave_runner.clear_enemies()
		game.hud.hide_story()
		var guardian: CoreGuardian = game.wave_runner.spawn_at(game.player.global_position + ahead * 10.0,
			load("res://data/enemies/core_guardian.tres"), load("res://scenes/enemies/core_guardian.tscn"))
		await _seconds(Enemy.SPAWN_TIME + 0.2)
		guardian._start_vent()
		await _seconds(0.4)
		await _shot("20_core_guardian_venting")
		game.wave_runner.clear_enemies()
		game.projectiles.clear_all()

		# The Foundry with its heat strips, and the Signal Tower's pad between floors.
		game.open_bench()
		await _frames(2)
		game.enter_area("foundry")
		await _seconds(2.0)
		var foundry: Node3D = game.arena
		foundry.elapsed = 3.5 # the first strip molten, the second warning
		await _frames(4)
		await _shot("21_foundry_heat_strips")
		game.open_bench()
		await _frames(2)
		game.enter_area("signal_tower")
		await _seconds(2.0)
		game.wave_runner.stop()
		game.wave_runner.clear_enemies()
		game.arena._set_pad(true)
		await _frames(3)
		await _shot("22_signal_tower_pad")
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
