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
		Progression.reset()
		_test_items_model()
		_test_build_stats()
		_test_shot_function()
		_test_save_file()
		_test_wave_lint()
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		var game := await _wait_for_main()
		await _test_bench_start_state(game)
		await _test_start_wave(game)
		await _test_movement(game)
		await _test_shoot_and_kill(game)
		await _test_reload(game)
		await _test_auto_reload(game)
		await _test_pause(game)
		await _test_touch_controls(game)
		await _test_enemy_attacks(game)
		await _test_wave_runner_cap(game)
		await _test_full_wave(game)
		await _test_purchase(game)
		await _test_death_and_retry(game)
		await _test_persistence(game)
		await _test_abandon(game)
		print("\n%d checks, %d failed" % [checks, failures])
		get_tree().quit(1 if failures > 0 else 0)

	# ------------------------------------------------------------------ unit tests

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

	## A test-only attachment so the item model can be exercised before any real base exists.
	func _register_test_barrel() -> AttachmentDefinition:
		var barrel := AttachmentDefinition.new()
		barrel.id = &"test_long_barrel"
		barrel.display_name = "Test long barrel"
		barrel.slot = &"barrel"
		barrel.modifiers = [StatModifier.make(&"damage", 0.0, 0.2), StatModifier.make(&"fire_rate", 0.0, -0.1)]
		barrel.behaviours = {"pierce": 9, "ray_count": 2} # pierce 9 must be clamped to the cap.
		Items.register_attachment(barrel)
		return barrel

	func _test_items_model() -> void:
		_register_test_barrel()
		var item := Items.make(&"test_long_barrel", Items.Rarity.RARE, [{"id": "sharp", "roll": 1.0}, {"id": "deep", "roll": 0.0}], 3)
		check(Items.is_valid(item), "a well-formed item validates")
		check(item["rarity"] == Items.Rarity.RARE and item["mark"] == 3 and item["affixes"].size() == 2, "item keeps rarity, mark and affixes")
		check(Items.display_name(item) == "Test long barrel III", "item display name uses the base name and mark numeral")
		var modifiers := Items.modifiers_of(item)
		var damage_percent := 0.0
		var magazine_flat := 0.0
		for modifier in modifiers:
			if modifier.stat == &"damage":
				damage_percent += modifier.percent
			if modifier.stat == &"magazine":
				magazine_flat += modifier.flat
		# Mark III scales the base's +20% by 1 + 0.15 * 2; Sharp at Rare with a max roll adds 12%.
		check(is_equal_approx(damage_percent, 0.2 * 1.3 + 0.12), "item modifiers combine mark-scaled base and affix rolls (%.3f)" % damage_percent)
		check(is_equal_approx(magazine_flat, 2.0), "flat affix uses the rarity's low roll (%.1f rounds)" % magazine_flat)
		check(not Items.is_valid(Items.make(&"no_such_base")), "item with an unknown base is invalid")
		check(not Items.is_valid({"base": "test_long_barrel", "rarity": 2, "mark": 1, "affixes": [{"id": "bogus", "roll": 0.5}]}), "item with an unknown affix is invalid")
		check(not Items.is_valid({"base": "test_long_barrel", "rarity": 9, "mark": 1, "affixes": []}), "item with an out-of-range rarity is invalid")
		var loose := Items.normalize({"base": "test_long_barrel", "rarity": 1.0, "mark": 7, "affixes": []})
		check(loose["mark"] == Items.MAX_MARK and loose["rarity"] is int and loose["uid"] > 0, "normalize clamps the mark and assigns a uid")
		check(Items.get_slots().size() == 7, "seven gunsmith slots are defined (%d)" % Items.get_slots().size())
		check(Items.get_affix(&"sharp") != null and Items.get_affix(&"arcing") != null, "affix pool loads from data")
		check(Items.get_attachment(&"../weird") == null, "attachment lookup rejects path-like ids")

	func _test_build_stats() -> void:
		var base: WeaponBaseStats = Progression.PISTOL_BASE
		var plain := WeaponStats.build(base)
		check(plain.damage == 10.0 and plain.fire_rate == 4.0 and plain.magazine_size == 10 and is_equal_approx(plain.reload_time, 1.4), "build with no sources equals the base")
		check(plain.behaviours["fire_mode"] == "semi" and plain.behaviours["ray_count"] == 1 and plain.behaviours["pierce"] == 0, "default behaviours are semi-auto single hitscan rays")
		var levelled := WeaponStats.build(base, {"damage": 3, "fire_rate": 2, "magazine": 4, "reload": 5})
		check(is_equal_approx(levelled.damage, 16.0), "damage levels add a flat amount (%.1f)" % levelled.damage)
		check(is_equal_approx(levelled.fire_rate, 4.0 * 1.12), "fire rate levels add percentages (%.2f)" % levelled.fire_rate)
		check(levelled.magazine_size == 14, "magazine levels add rounds (%d)" % levelled.magazine_size)
		check(is_equal_approx(levelled.reload_time, 1.4 / 1.4), "reload levels divide the reload time (%.3f)" % levelled.reload_time)
		var capped := WeaponStats.build(base, {"fire_rate": 500, "reload": 500, "magazine": 50})
		check(capped.fire_rate == WeaponStats.ABSOLUTE_FIRE_RATE_CAP, "fire rate never exceeds the absolute cap (%.1f)" % capped.fire_rate)
		check(capped.reload_time == base.min_reload_time, "reload time never drops below the floor (%.2f)" % capped.reload_time)
		check(capped.magazine_size == 60, "magazine cap holds at 60 (%d)" % capped.magazine_size)
		var item := Items.make(&"test_long_barrel", Items.Rarity.UNCOMMON, [{"id": "sharp", "roll": 0.0}], 1)
		var with_item := WeaponStats.build(base, {"damage": 1}, {"barrel": item})
		# (10 + 2) * (1 + 0.20 base + 0.04 Sharp) = 14.88: flats first, percentages summed, multiplied once.
		check(is_equal_approx(with_item.damage, 12.0 * 1.24), "item percentages sum with core flats then multiply once (%.2f)" % with_item.damage)
		check(is_equal_approx(with_item.fire_rate, 4.0 * 0.9), "negative item percentages reduce a stat (%.2f)" % with_item.fire_rate)
		check(with_item.behaviours["pierce"] == WeaponStats.PIERCE_CAP and with_item.behaviours["ray_count"] == 2, "item behaviours apply and pierce is clamped to the cap")
		var crit_item := Items.make(&"test_long_barrel", Items.Rarity.LEGENDARY, [{"id": "keen", "roll": 1.0}, {"id": "brutal", "roll": 1.0}, {"id": "piercing", "roll": 1.0}], 5)
		var skills := {"modifiers": [StatModifier.make(&"crit_chance", 0.0, 0.9)]}
		var crit := WeaponStats.build(base, {}, {"barrel": crit_item}, skills)
		check(crit.crit_chance == WeaponStats.CRIT_CHANCE_CAP, "crit chance is capped at 50 percent (%.2f)" % crit.crit_chance)
		check(is_equal_approx(crit.crit_multiplier, 1.5 * 1.5), "crit damage affix scales the crit multiplier (%.2f)" % crit.crit_multiplier)
		check(crit.extra.has("extra_pierce") and is_equal_approx(crit.extra["extra_pierce"]["flat"], 2.0), "modifiers for stats the pistol does not use yet land in extra")
		check(with_item.sustained_dps() > 0.0 and with_item.shots_to_kill(40.0) == 3, "derived readouts work (%d shots to kill 40 hp)" % with_item.shots_to_kill(40.0))
		var equipped_unknown := WeaponStats.build(base, {}, {"barrel": {"base": "gone", "rarity": 0, "mark": 1, "affixes": []}})
		check(equipped_unknown.damage == 10.0, "an equipped item with an unknown base contributes nothing")
		Items.unregister(&"test_long_barrel")

	func _test_shot_function() -> void:
		var stats := WeaponStats.build(Progression.PISTOL_BASE, {"damage": 5})
		var rng := RandomNumberGenerator.new()
		var context := WeaponStats.ShotContext.new()
		var shot := WeaponStats.resolve_shot(stats, context, rng)
		check(shot.in_range and is_equal_approx(shot.damage, 20.0) and not shot.is_crit, "a plain shot deals the build damage")
		context.distance = stats.max_range + 1.0
		shot = WeaponStats.resolve_shot(stats, context, rng)
		check(not shot.in_range and shot.damage == 0.0, "a shot beyond max range lands nothing")
		context.distance = 10.0
		stats.crit_chance = 0.5
		stats.crit_multiplier = 2.0
		var crits := 0
		rng.seed = 12345
		for i in 2000:
			if WeaponStats.resolve_shot(stats, context, rng).is_crit:
				crits += 1
		check(crits > 850 and crits < 1150, "crit rolls follow the crit chance (%d of 2000)" % crits)
		rng.seed = 7
		var first := WeaponStats.resolve_shot(stats, context, rng).is_crit
		rng.seed = 7
		check(WeaponStats.resolve_shot(stats, context, rng).is_crit == first, "shot rolls are reproducible from the rng seed")
		check(is_equal_approx(WeaponStats.expected_damage(stats, context), 20.0 * 1.5), "expected damage averages the crit roll (%.1f)" % WeaponStats.expected_damage(stats, context))
		stats.behaviours["fire_mode"] = "charge"
		context.charge = 1.0
		stats.crit_chance = 0.0
		check(is_equal_approx(WeaponStats.resolve_shot(stats, context, rng).damage, 60.0), "a full charge triples the shot")
		context.charge = 0.0
		context.overclock_active = true
		stats.fire_rate = 10.0
		check(is_equal_approx(WeaponStats.resolve_shot(stats, context, rng).damage, 20.0 * 20.0 / 15.0), "Overclock surplus above the fire-rate cap becomes damage")

	func _test_save_file() -> void:
		var fresh := SaveFile.fresh()
		check(fresh["version"] == SaveFile.VERSION and fresh["credits"] == 0 and fresh["inventory"].is_empty(), "fresh save is version 2 and empty")
		_register_test_barrel()
		var data := SaveFile.fresh()
		data["credits"] = 123
		data["core_levels"] = {"damage": 4, "reload": 2}
		data["waves"] = {"highest_cleared": 3, "first_clears": [1, 2, 3]}
		data["inventory"] = [Items.make(&"test_long_barrel", Items.Rarity.RARE, [{"id": "sharp", "roll": 0.42}], 2)]
		data["equipped"] = {"barrel": Items.make(&"test_long_barrel", Items.Rarity.UNCOMMON, [{"id": "quick", "roll": 0.9}], 1)}
		data["story_flags"] = ["intro_seen"]
		check(SaveFile.save(data), "save writes to disk")
		var loaded := SaveFile.load_or_fresh()
		check(loaded["credits"] == 123 and loaded["core_levels"]["damage"] == 4 and loaded["core_levels"]["reload"] == 2, "round trip keeps credits and core levels")
		check(loaded["waves"]["highest_cleared"] == 3 and loaded["waves"]["first_clears"] == [1, 2, 3], "round trip keeps wave progress")
		check(loaded["inventory"].size() == 1 and loaded["inventory"][0]["mark"] == 2 and is_equal_approx(loaded["inventory"][0]["affixes"][0]["roll"], 0.42), "round trip keeps items with their rolled affixes")
		check(loaded["equipped"].has("barrel") and loaded["equipped"]["barrel"]["affixes"][0]["id"] == "quick", "round trip keeps the equipped build")
		check(loaded["story_flags"] == ["intro_seen"], "round trip keeps story flags")
		# Items whose base or affix no longer exists are dropped, nothing else is lost.
		data["inventory"].append({"base": "retired_base", "rarity": 1, "mark": 1, "affixes": []})
		data["inventory"].append({"base": "test_long_barrel", "rarity": 1, "mark": 1, "affixes": [{"id": "retired_affix", "roll": 0.5}]})
		data["core_levels"]["retired_stat"] = 9
		data["equipped"]["relic"] = Items.make(&"test_long_barrel")
		var cleaned := SaveFile.sanitize(data)
		check(cleaned["inventory"].size() == 1 and not cleaned["core_levels"].has("retired_stat") and not cleaned["equipped"].has("relic"), "unknown items, stats and slots are dropped on load")
		# Version 1 (the original Milestone 2 spec) migrates.
		var v1 := {"version": 1, "credits": 77, "upgrades": {"damage": 2, "magazine": 1}, "highest_wave": 2}
		var migrated := SaveFile.migrate(v1)
		check(migrated["version"] == 2 and migrated["credits"] == 77 and migrated["core_levels"]["damage"] == 2 and migrated["core_levels"]["magazine"] == 1, "version 1 save migrates its credits and levels")
		check(migrated["waves"]["highest_cleared"] == 2 and migrated["waves"]["first_clears"] == [1, 2] and migrated["inventory"].is_empty(), "version 1 save migrates its wave progress")
		# Unknown version: fresh start, backup kept.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveFile.BACKUP_PATH))
		var future := SaveFile.migrate({"version": 99, "credits": 5})
		check(future["credits"] == 0 and FileAccess.file_exists(SaveFile.BACKUP_PATH), "unknown save version starts fresh and keeps a backup")
		# Corrupt file: fresh start, backup kept.
		var file := FileAccess.open(SaveFile.PATH, FileAccess.WRITE)
		file.store_string("{ not json")
		file.close()
		check(SaveFile.load_or_fresh()["credits"] == 0, "corrupt save file starts fresh")
		SaveFile.delete()
		check(not FileAccess.file_exists(SaveFile.PATH) and SaveFile.load_or_fresh()["version"] == 2, "missing save file starts fresh")
		Items.unregister(&"test_long_barrel")
		Progression.reset()

	func _test_wave_lint() -> void:
		var waves := WaveRunner.all_waves()
		check(waves.size() == WaveRunner.WAVE_COUNT, "%d authored waves load" % waves.size())
		var ok := true
		var previous := 0
		for wave in waves:
			ok = ok and wave.number == previous + 1 and not wave.groups.is_empty() and wave.max_alive >= 1 and wave.completion_bonus > 0
			for group in wave.groups:
				ok = ok and group.enemy_scene != null and group.definition != null and group.count > 0 and group.interval > 0.0
			ok = ok and wave.total_enemies() > wave.max_alive
			previous = wave.number
		check(ok, "every wave is numbered in order, non-empty, capped and pays a bonus")
		var income := 0
		for wave in waves:
			income += wave.kill_income() + wave.completion_bonus
		var first_cost := CoreTuning.get_definition(&"damage").cost_at(0)
		check(waves[0].kill_income() + waves[0].completion_bonus >= first_cost, "wave 1 pays enough for the first damage level (%d credits vs %d)" % [waves[0].kill_income() + waves[0].completion_bonus, first_cost])
		check(income > 500, "five waves pay a meaningful total (%d credits)" % income)
		check(CoreTuning.all().size() == 4, "four core tuning stats are defined")
		var damage := CoreTuning.get_definition(&"damage")
		check(damage.cost_at(1) > damage.cost_at(0) and damage.cost_at(10) == roundi(20 * pow(1.15, 10)), "core tuning cost grows 15 percent per level")

	# ------------------------------------------------------------------ scene tests

	func _test_bench_start_state(game: Node) -> void:
		check(game.state == game.State.BENCH and get_tree().paused, "game opens on the bench with the tree paused")
		check(game.bench.visible and not game.hud.is_death_screen_visible(), "bench is visible at start")
		check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse is free while the bench is open")
		check(Progression.credits == 0 and Progression.next_wave() == 1, "new save starts with no credits at wave 1")
		check(game.bench.selected_wave == 1 and game.bench._start_button.text == "START WAVE 1", "bench selects wave 1 for a new player")
		check(game.bench._slot_grid.get_child_count() == 7, "bench shows all seven locked slots")
		var row: Dictionary = game.bench._core_rows[&"damage"]
		check(row["button"].disabled and row["button"].text == "Buy  20 c", "damage upgrade shows its cost and cannot be bought with no credits")
		check("10 dmg  →  12 dmg" in row["effect"].text, "damage row previews the next level (%s)" % row["effect"].text)
		check(FileAccess.file_exists(SaveFile.PATH), "opening the bench writes the save")
		game.start_wave(3)
		await physics_frames(2)
		check(game.state == game.State.BENCH, "a locked wave cannot be started")

	func _test_start_wave(game: Node) -> void:
		game.bench._on_start_pressed()
		await physics_frames(3)
		check(game.state == game.State.COMBAT and not get_tree().paused and not game.bench.visible, "start button closes the bench and begins combat")
		check(game.hud._wave_label.text == "WAVE 1  ·  FIRST CONTACT", "HUD names the wave (%s)" % game.hud._wave_label.text)
		check(game.wave_runner.running and game.wave_runner.current.number == 1, "wave runner starts wave 1 once the player has control")
		game.wave_runner.stop() # Keep the following tests controlled.

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
		var credits_before := Progression.credits
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
		check(Progression.credits == credits_before + definition.credit_reward, "kill pays its credits the moment the enemy dies (%d)" % Progression.credits)
		check(game.hud._credits_label.text == "CREDITS  %d" % Progression.credits, "HUD shows the credits")
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

	func _test_touch_controls(game: Node) -> void:
		var touch: TouchControls = game.touch_controls
		var player: Player = game.player
		check(not touch.visible, "touch controls hidden until the first touch")
		var screen := touch.get_viewport().get_visible_rect().size
		var stick_start := Vector2(screen.x * 0.15, screen.y * 0.7)
		_touch(0, stick_start, true)
		await physics_frames(2)
		game.wave_runner.stop() # Gaining control starts the wave; keep this test controlled.
		check(touch.active and touch.visible, "first touch shows the touch controls")
		var start := player.global_position
		var forward := -player.global_basis.z
		_drag(0, stick_start + Vector2(0, -200), Vector2(0, -200))
		await physics_frames(20)
		check(Input.is_action_pressed("sprint"), "pushing the stick to the edge sprints")
		_touch(0, stick_start + Vector2(0, -200), false)
		await physics_frames(10)
		var moved := (player.global_position - start).dot(forward)
		check(moved > 1.5, "touch stick moves the player forward (%.2f m)" % moved)
		check(not Input.is_action_pressed("move_forward") and not Input.is_action_pressed("sprint"),
			"releasing the stick stops moving")
		var yaw := player.rotation.y
		var look_start := Vector2(screen.x * 0.6, screen.y * 0.4)
		_touch(1, look_start, true)
		_drag(1, look_start + Vector2(120, 0), Vector2(120, 0))
		_touch(1, look_start + Vector2(120, 0), false)
		check(not is_equal_approx(player.rotation.y, yaw), "dragging on the right turns the view")
		# Move and look at once. Godot's web build can send `relative` measured from the other finger,
		# so give the look drag a bogus relative and check the turn follows the finger's real movement.
		_touch(0, stick_start, true)
		_drag(0, stick_start + Vector2(0, -60), Vector2(0, -60))
		_touch(1, look_start, true)
		yaw = player.rotation.y
		_drag(1, look_start + Vector2(10, 0), Vector2(900, 400))
		var turned := absf(angle_difference(yaw, player.rotation.y))
		var expected := 10.0 * TouchControls.LOOK_SCALE / touch._scale * Player.MOUSE_RADIANS_PER_PIXEL * Settings.mouse_sensitivity
		check(is_equal_approx(turned, expected), "two-finger look uses each finger's own movement (%.4f rad)" % turned)
		_touch(1, look_start + Vector2(10, 0), false)
		_touch(0, stick_start + Vector2(0, -60), false)
		await physics_frames(2)
		var ammo := player.pistol.ammo
		var fire_center: Vector2 = touch._buttons[&"fire"].center
		_touch(2, fire_center, true)
		await physics_frames(3)
		_touch(2, fire_center, false)
		check(player.pistol.ammo == ammo - 1, "fire button shoots once")
		check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "touch mode does not capture the mouse")
		_touch(3, touch._buttons[&"pause"].center, true)
		await physics_frames(2)
		check(get_tree().paused and game.pause_menu.visible, "pause button opens the pause menu")
		game.resume()
		await physics_frames(2)
		check(not get_tree().paused, "game resumes in touch mode")
		await seconds(player.pistol.stats.seconds_between_shots())

	func _touch(index: int, position: Vector2, pressed: bool) -> void:
		var event := InputEventScreenTouch.new()
		event.index = index
		event.position = position
		event.pressed = pressed
		get_viewport().push_input(event, true) # Already in viewport coordinates.

	func _drag(index: int, position: Vector2, relative: Vector2) -> void:
		var event := InputEventScreenDrag.new()
		event.index = index
		event.position = position
		event.relative = relative
		get_viewport().push_input(event, true)

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

	func _test_wave_runner_cap(game: Node) -> void:
		var runner: WaveRunner = game.wave_runner
		var wave := WaveDefinition.new()
		wave.number = 1
		wave.max_alive = 3
		var group := SpawnGroup.new()
		group.enemy_scene = load("res://scenes/enemies/chaser.tscn")
		group.definition = load("res://data/enemies/runner.tres")
		group.count = 6
		group.interval = 0.05
		group.start_delay = 0.0
		wave.groups = [group]
		runner.start(wave, 1.6)
		await seconds(0.6)
		runner.stop()
		var enemies: Array = game.get_node("Enemies").get_children()
		check(runner.active_count() == 3, "wave runner respects the alive cap (%d)" % runner.active_count())
		var min_distance := INF
		for enemy: Chaser in enemies:
			min_distance = minf(min_distance, enemy.global_position.distance_to(game.player.global_position))
		check(min_distance >= runner.min_player_distance, "no enemy spawned near the player (closest %.1f m)" % min_distance)
		var scaled: Chaser = enemies[0]
		check(is_equal_approx(scaled.health, scaled.definition.max_health * 1.6) and scaled.definition.display_name == "Runner", "tier scaling multiplies enemy health (%.0f hp runner)" % scaled.health)
		var credits_before := Progression.credits
		var reward: int = scaled.definition.credit_reward
		scaled.take_hit(10000.0, scaled.global_position, Vector3.FORWARD)
		await physics_frames(2)
		check(Progression.credits == credits_before + roundi(reward * 1.6), "tier scaling multiplies kill credits (+%d)" % (Progression.credits - credits_before))
		runner.clear_enemies()
		await physics_frames(2)
		check(game.get_node("Enemies").get_child_count() == 0, "clear_enemies empties the arena")

	## Plays the real wave 1 to the end by killing every chaser as it appears.
	func _test_full_wave(game: Node) -> void:
		game.open_bench()
		await physics_frames(2)
		check(game.state == game.State.BENCH and get_tree().paused, "open_bench returns to the bench")
		var credits_before := Progression.credits
		game.start_wave(1)
		await physics_frames(3)
		var wave: WaveDefinition = game.wave_runner.current
		check(wave != null and wave.number == 1 and game.wave_runner.running, "wave 1 restarts from the bench")
		check(game.player.health == game.player.max_health, "starting a wave restores the player")
		var cleared := [false, 0.0]
		game.wave_runner.wave_cleared.connect(func(_wave: WaveDefinition, duration: float) -> void:
			cleared[0] = true
			cleared[1] = duration, CONNECT_ONE_SHOT)
		var killed := 0
		var elapsed := 0.0
		var remaining_seen: Array = []
		game.wave_runner.remaining_changed.connect(func(remaining: int, _total: int) -> void: remaining_seen.append(remaining))
		while not cleared[0] and elapsed < 40.0:
			for enemy in game.get_node("Enemies").get_children():
				if enemy is Chaser and enemy.is_alive and enemy.state != Chaser.State.SPAWNING:
					enemy.take_hit(10000.0, enemy.global_position, Vector3.FORWARD)
					killed += 1
			await physics_frames(3)
			elapsed += 3.0 / Engine.physics_ticks_per_second
		check(cleared[0] and killed == wave.total_enemies(), "wave 1 clears after %d kills in %.1fs" % [killed, cleared[1]])
		check(remaining_seen.back() == 0 and remaining_seen.size() >= wave.total_enemies(), "HUD progress counts down to zero")
		await physics_frames(2)
		check(game.state == game.State.CLEARED and game.hud._banner.visible, "wave cleared banner shows")
		var expected := credits_before + wave.kill_income() + wave.completion_bonus
		check(Progression.credits == expected, "kills plus the completion bonus are paid once (%d credits)" % Progression.credits)
		check(Progression.is_wave_cleared(1) and Progression.next_wave() == 2, "wave 1 is marked cleared and wave 2 unlocks")
		await seconds(game.CLEARED_BANNER_TIME + 0.3)
		check(game.state == game.State.BENCH and game.bench.visible and get_tree().paused, "bench opens after the banner")
		check(game.bench.selected_wave == 2 and not game.bench._wave_buttons[1].disabled and game.bench._wave_buttons[2].disabled, "bench selects wave 2 and keeps wave 3 locked")
		var saved := SaveFile.load_or_fresh()
		check(saved["credits"] == Progression.credits and saved["waves"]["highest_cleared"] == 1, "save on disk has the new credits and wave")

	func _test_purchase(game: Node) -> void:
		var credits := Progression.credits
		var cost := Progression.core_cost(&"damage")
		check(Progression.can_buy_core(&"damage"), "damage level 1 is affordable after wave 1 (%d credits, costs %d)" % [credits, cost])
		var row: Dictionary = game.bench._core_rows[&"damage"]
		check(not row["button"].disabled, "bench enables the buy button when affordable")
		row["button"].pressed.emit()
		await physics_frames(1)
		check(Progression.credits == credits - cost and Progression.core_level(&"damage") == 1, "buying spends the credits and raises the level")
		check(Progression.core_cost(&"damage") == roundi(cost * 1.15), "next level costs more (%d)" % Progression.core_cost(&"damage"))
		check(is_equal_approx(Progression.build_stats().damage, 12.0), "build stats include the new level")
		check("Lv 1" in row["level"].text and "12 dmg  →  14 dmg" in row["effect"].text, "bench row updates after the purchase (%s)" % row["effect"].text)
		check("Damage per shot   12" in game.bench._stats_summary.text, "bench summary uses the shared stats function")
		var saved := SaveFile.load_or_fresh()
		check(saved["core_levels"]["damage"] == 1 and saved["credits"] == Progression.credits, "purchase is saved immediately")
		Progression.data["credits"] = 0
		check(not Progression.buy_core(&"fire_rate") and Progression.core_level(&"fire_rate") == 0, "cannot buy without credits")
		Progression.data["credits"] = credits - cost
		Progression.credits_changed.emit(Progression.credits)

	func _test_death_and_retry(game: Node) -> void:
		game.start_wave(2)
		await physics_frames(3)
		var player: Player = game.player
		check(game.state == game.State.COMBAT and game.wave_runner.current.number == 2, "wave 2 starts")
		check(is_equal_approx(player.pistol.stats.damage, 12.0) and player.pistol.ammo == player.pistol.stats.magazine_size, "pistol carries the bought upgrade into the wave")
		game.wave_runner.stop()
		var credits := Progression.credits
		var enemy := _spawn_in_front(game, 6.0)
		await seconds(Chaser.SPAWN_TIME + 0.1)
		enemy.take_hit(10000.0, enemy.global_position, Vector3.FORWARD)
		await physics_frames(2)
		check(Progression.credits > credits, "kills during the wave pay immediately")
		credits = Progression.credits
		player.take_damage(10000.0)
		await physics_frames(2)
		check(player.is_dead and player.health == 0.0 and game.state == game.State.DEAD, "lethal damage kills the player")
		check(game.hud.is_death_screen_visible() and "%d credits kept" % credits in game.hud._death_summary.text, "death screen shows the kept credits")
		var ammo := player.pistol.ammo
		player.pistol.request_fire()
		await physics_frames(5)
		check(player.pistol.ammo == ammo, "dead player cannot shoot")
		player.take_damage(10.0)
		check(player.health == 0.0, "damage after death is ignored")
		var reload := InputEventAction.new()
		reload.action = "reload"
		reload.pressed = true
		Input.parse_input_event(reload)
		await physics_frames(3)
		check(game.state == game.State.BENCH and game.bench.visible and not game.hud.is_death_screen_visible(), "R after death returns to the bench")
		check(Progression.credits == credits and not Progression.is_wave_cleared(2), "death keeps credits and pays no bonus")
		check(int(Progression.data["records"]["deaths"]) == 1, "death is recorded")
		game.start_wave(2)
		await physics_frames(3)
		check(not player.is_dead and player.health == player.max_health and player.pistol.enabled, "retry restores the player")
		check(game.get_node("Enemies").get_child_count() == 0 and game.kills == 0, "retry starts with a clean arena")
		game.wave_runner.stop()

	func _test_persistence(game: Node) -> void:
		game.open_bench()
		await physics_frames(2)
		var credits := Progression.credits
		Progression.data["credits"] = 999999
		Progression.load_from_disk()
		check(Progression.credits == credits and Progression.core_level(&"damage") == 1 and Progression.highest_cleared_wave == 1, "reloading the save restores credits, levels and progress")
		check(Progression.loaded_from_disk, "save is detected as existing")
		game.bench.refresh()
		check("Welcome back" in game.bench._greeting.text, "bench greets a returning player")
		game.start_wave(1)
		await physics_frames(3)
		check(game.state == game.State.COMBAT and game.wave_runner.current.number == 1, "a cleared wave can be replayed")
		game.wave_runner.stop()

	func _test_abandon(game: Node) -> void:
		game.pause()
		await physics_frames(1)
		game.pause_menu.abandon_requested.emit()
		await physics_frames(2)
		check(game.state == game.State.BENCH and game.bench.visible and not game.pause_menu.visible, "abandoning a wave returns to the bench")
		check(not Progression.is_wave_cleared(2), "abandoning pays no completion bonus")
		game.bench._on_reset_pressed()
		check(Progression.credits > 0, "first reset click only asks for confirmation")
		game.bench._on_reset_pressed()
		check(Progression.credits == 0 and Progression.highest_cleared_wave == 0 and SaveFile.load_or_fresh()["credits"] == 0, "second reset click wipes progress and the save")

	# ------------------------------------------------------------------ helpers

	func _spawn_in_front(game: Node, distance: float) -> Chaser:
		var player: Player = game.player
		var forward := -player.global_basis.z
		forward.y = 0.0
		return game.wave_runner.spawn_at(player.global_position + forward.normalized() * distance,
			load("res://data/enemies/chaser.tres"), load("res://scenes/enemies/chaser.tscn"))

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
			printerr("FAIL  ", description)
