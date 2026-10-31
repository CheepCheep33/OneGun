extends TestCase
## Milestone 5 side areas and story: the Foundry (gate, one attempt per intermission, the heat
## strips, the clear's rewards and the untouched Epic), the Signal Tower (ten floors with their
## rules, the loadout pad's gunsmith-only bench, Climb, Charge at floor 5, the top's rewards and
## the Legendary core once per tier), the story (VERA at the bench, logs on banners, the story
## tab) and the version 5 save migration.


func run_unit() -> void:
	Progression.reset()
	_test_area_rules()
	_test_story_rules()
	_test_migration()
	Progression.reset()


func run_scene(game: Node) -> void:
	await _test_foundry(game)
	await _test_tower(game)
	await _test_story_bench(game)


func _test_area_rules() -> void:
	Progression.reset()
	check(not Progression.is_area_open("foundry") and not Progression.is_area_open("signal_tower"), "the Foundry and the Signal Tower start closed")
	Progression.record_wave_cleared(10, 0, 1.0)
	check(Progression.is_area_open("foundry") and Progression.area_block_reason("foundry") == "", "the Foreman's wave opens the Foundry")
	Progression.record_foundry_run()
	check(Progression.area_block_reason("foundry").begins_with("One attempt"), "an attempt spends the Foundry until a wave is played")
	Progression.refresh_intermission()
	check(Progression.area_block_reason("foundry") == "", "playing a wave refreshes it")
	var burst := Items.get_attachment(&"burst")
	check(not Progression.is_base_unlocked(burst), "Burst waits for the Foundry")
	var first := Progression.record_foundry_clear(false, 60.0)
	var got_burst := false
	for item in first["rewards"]:
		got_burst = got_burst or item.get("base", "") == "burst"
	check(first["first"] and got_burst and Progression.is_base_unlocked(burst), "the first clear pays the Burst receiver and opens it")
	check(int(Progression.parts()["cores"]) == Progression.FOUNDRY_CORES, "every clear pays cores")
	var epics := func() -> int:
		var count := 0
		for item in Progression.inventory():
			if int(item.get("rarity", 0)) == Items.Rarity.EPIC:
				count += 1
		return count
	check(epics.call() == 0, "a run with damage pays no Epic")
	Progression.record_foundry_clear(true, 50.0)
	check(epics.call() == 1 and int(Progression.foundry_state()["perfect"]) == 1, "an untouched run pays an Epic")
	check(Progression.has_seen_story("log_foundry_1") and Progression.has_seen_story("log_foundry_perfect"), "the Foundry's logs are found")
	# The tower: Charge at floor 5 once, the top's Epic and Overflow, a Legendary core once a tier.
	Progression.record_wave_cleared(15, 0, 1.0)
	check(Progression.is_area_open("signal_tower"), "the Sentinel's wave opens the Signal Tower")
	check(Progression.record_tower_floor(4).is_empty() and not Progression.has_unlock("signal_tower"), "floor 4 pays nothing")
	var charge := Progression.record_tower_floor(5)
	check(charge.size() == 1 and charge[0].get("base", "") == "charge" and Progression.is_base_unlocked(Items.get_attachment(&"charge")),
		"floor 5 cleared the first time opens the Charge receiver and pays one")
	check(Progression.record_tower_floor(5).is_empty(), "only the first time")
	var top := Progression.record_tower_top(300.0)
	check(int(top["parts"].get("legendary_cores", 0)) == 1 and Progression.has_unlock("signal_tower_top") and top["rewards"].size() == 2,
		"the top pays an Epic, the Overflow magazine and a Legendary core")
	var again := Progression.record_tower_top(280.0)
	check(not again["legendary_core"] and again["rewards"].size() == 1, "the Legendary core is once per Reforge tier")
	Progression.data["tier"] = 1
	check(Progression.record_tower_top(260.0)["legendary_core"], "a new tier pays it again")
	Progression.reset()


func _test_story_rules() -> void:
	Progression.reset()
	var ok := true
	for wave in range(1, WaveRunner.WAVE_COUNT + 1):
		ok = ok and Story.has("wave_%d" % wave)
	for boss in ["warden", "foreman", "sentinel", "core_guardian"]:
		ok = ok and Story.has("boss_%s" % boss)
	check(ok, "every wave and boss has its story lines (chapters 1 to 4)")
	var logs := 0
	for trigger in Story.triggers():
		if Story.is_log(trigger):
			logs += 1
	check(logs >= 10, "the side areas and arena hide %d logs" % logs)
	var lines := Progression.fire_story("wave_1")
	check(not lines.is_empty() and Progression.fire_story("wave_1").is_empty(), "a trigger fires once per save")
	check(Progression.take_story_queue() == ["wave_1"] and Progression.take_story_queue().is_empty(), "the bench reads the queue once")
	check(Progression.fire_story("no_such_trigger").is_empty() and not Progression.has_seen_story("no_such_trigger"), "an unknown trigger does nothing")
	var long_line := true
	for trigger in Story.triggers():
		for line in Story.lines_for(trigger):
			long_line = long_line and String(line[1]).length() <= 220
	check(long_line, "every line fits a card (short lines, never a cutscene)")
	Progression.reset()


func _test_migration() -> void:
	var v4 := SaveFile.fresh()
	v4["version"] = 4
	for key in ["xp", "boss_kills", "unlocks", "story_queue"]:
		v4.erase(key)
	v4["areas"].erase("foundry")
	v4["areas"].erase("signal_tower")
	v4["records"]["credits_earned"] = 4321
	v4["waves"]["first_clears"] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	v4["waves"]["highest_cleared"] = 10
	v4["story_flags"] = ["scrapyard_log_1"]
	v4["skills"] = {"deadeye": 1, "no_such_skill": 1}
	var migrated := SaveFile.migrate(v4)
	check(migrated["version"] == 5 and int(migrated["xp"]) == 4321, "a Milestone 4 save migrates with experience from the credits it earned")
	check(migrated["unlocks"].has("foundry"), "a player who cleared wave 10 keeps the Burst receiver open")
	check(migrated["story_flags"] == ["log_scrapyard_1"], "the Scrapyard's log carries over as the story's first salvage log")
	check(migrated["skills"].has("deadeye") and not migrated["skills"].has("no_such_skill"), "unknown skills are dropped")
	check(int(migrated["areas"]["foundry"]["clears"]) == 0 and int(migrated["areas"]["signal_tower"]["best_floor"]) == 0,
		"the new areas start empty")


func _test_foundry(game: Node) -> void:
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	for wave in range(1, 11):
		Progression.record_wave_cleared(wave, 0, 1.0)
	var bench: Bench = game.bench
	bench.open()
	check(not bench._area_buttons["foundry"].disabled and bench._area_buttons["signal_tower"].disabled, "the bench offers the Foundry after the Foreman, not yet the tower")
	game.enter_area("foundry")
	await physics_frames(3)
	var foundry: Node3D = game.arena
	check(game.state == game.State.AREA and game.current_area == "foundry" and foundry.running and game.wave_runner.running,
		"entering loads the Foundry and starts its schedule")
	check(Progression.is_foundry_spent(), "the attempt is spent on entry")
	game.wave_runner.stop()
	game.wave_runner.clear_enemies()
	# The heat strips: stand on one while it burns.
	var player: Player = game.player
	var strip: Node3D = foundry._strips[0]
	player.global_position = Vector3(strip.global_position.x, player.global_position.y, strip.global_position.z)
	foundry.elapsed = _burn_time(foundry)
	var health := player.health
	await seconds(0.3)
	check(foundry.strip_state(0) == 2 and strip.get_node("Molten").visible and player.health < health,
		"a burning strip hurts a grounded player (%.0f → %.0f)" % [health, player.health])
	check(foundry.damaged and "damage taken" in game.hud._wave_progress_label.text, "the run is no longer untouched")
	player.global_position = game.arena.get_player_start().origin
	foundry.on_encounter_cleared(42.0)
	await physics_frames(2)
	check(game.state == game.State.CLEARED and int(Progression.foundry_state()["clears"]) == 1, "clearing the schedule ends the run")
	check(game.hud._banner.visible and game.hud._banner_title.text.begins_with("FOUNDRY CLEARED") and "Burst" in game.hud._banner_detail.text
		and "FOUNDRY LOG" in game.hud._banner_detail.text,
		"the banner shows the cores, the Burst receiver and the log (%s)" % game.hud._banner_detail.text.replace("\n", " / "))
	await seconds(game.CLEARED_BANNER_TIME + 2.5)
	check(game.state == game.State.BENCH and game.current_area == "", "the bench opens after the banner")
	bench.refresh()
	check(bench._area_buttons["foundry"].disabled and "spent" in bench._area_buttons["foundry"].text, "the Foundry waits for the next intermission")
	game.enter_area("foundry")
	await physics_frames(2)
	check(game.state == game.State.BENCH, "a spent Foundry cannot be entered")
	Progression.reset()
	bench.refresh()


## A clock inside strip 0's burn window.
func _burn_time(foundry: Node) -> float:
	return foundry.HEAT_WARNING + 0.2


func _test_tower(game: Node) -> void:
	Progression.reset()
	for wave in range(1, 16):
		Progression.record_wave_cleared(wave, 0, 1.0)
	var bench: Bench = game.bench
	bench.open()
	check(not bench._area_buttons["signal_tower"].disabled, "the bench offers the Signal Tower after the Sentinel")
	game.enter_area("signal_tower")
	await physics_frames(3)
	var tower: Node3D = game.arena
	check(game.state == game.State.AREA and tower.floor_number == 1 and game.wave_runner.running and game.wave_runner.current == tower.floor_wave(1),
		"the climb starts on floor 1 with its schedule")
	check("Floor 1 / 10" in game.hud._wave_progress_label.text, "the HUD names the floor and its rule (%s)" % game.hud._wave_progress_label.text)
	game.wave_runner.stop()
	game.wave_runner.clear_enemies()
	# Floor 1 cleared: the pad lights; stepping onto it opens the gunsmith only.
	game._on_wave_cleared(tower.floor_wave(1), 20.0)
	await physics_frames(2)
	check(tower.pad_open and int(Progression.tower_state()["best_floor"]) == 1, "a cleared floor lights the loadout pad")
	var player: Player = game.player
	player.global_position = Vector3(tower._pad.global_position.x, player.global_position.y, tower._pad.global_position.z)
	await physics_frames(3)
	check(bench.visible and bench.pad_mode and not bench.get_node("Margin/VBox/Body/CorePanel").visible and "CLIMB TO FLOOR 2" in bench._start_button.text,
		"the pad opens the gunsmith alone, with Climb (%s)" % bench._start_button.text)
	check(game.get_tree().paused and game.state == game.State.AREA, "the climb waits on the pad")
	bench._start_button.pressed.emit()
	await physics_frames(3)
	check(not bench.visible and not game.get_tree().paused and tower.floor_number == 2 and game.wave_runner.running,
		"Climb starts floor 2")
	check(is_equal_approx(game.wave_runner.speed_modifier, 2.0), "floor 2's rule doubles robot speed")
	var enemy := spawn_in_front(game, 12.0)
	await physics_frames(1)
	check(is_equal_approx(enemy.speed_modifier, 2.0), "robots it spawns carry the rule")
	game.wave_runner.stop()
	game.wave_runner.clear_enemies()
	# Jump to the top: clearing floor 10 pays and ends the climb.
	tower.start_floor(3)
	await physics_frames(1)
	check(game.player.pistol.no_reloads and not ShotPipeline.crits_only, "floor 3's rule turns off reloads")
	tower.start_floor(4)
	await physics_frames(1)
	check(ShotPipeline.crits_only and not game.player.pistol.no_reloads, "floor 4's rule makes only crits count")
	tower.start_floor(10)
	await physics_frames(1)
	game.wave_runner.stop()
	game.wave_runner.clear_enemies()
	game._on_wave_cleared(tower.floor_wave(10), 30.0)
	await physics_frames(2)
	check(game.state == game.State.CLEARED and game.hud._banner_title.text == "TOP OF THE TOWER" and Progression.has_unlock("signal_tower_top"),
		"the top floor pays and ends the climb (%s)" % game.hud._banner_detail.text.replace("\n", " / "))
	check(int(Progression.parts()["legendary_cores"]) == 1, "the top pays a Legendary core")
	await seconds(game.CLEARED_BANNER_TIME + 2.5)
	check(game.state == game.State.BENCH and not ShotPipeline.crits_only and is_equal_approx(game.wave_runner.speed_modifier, 1.0),
		"back at the bench, no floor rule carries over")
	Progression.reset()
	bench.refresh()
	# Leave wave 1 running with its spawns stopped, as the case before this one did.
	await start_quiet_wave(game)


func _test_story_bench(game: Node) -> void:
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	var bench: Bench = game.bench
	Progression.fire_story("wave_1")
	bench.open()
	check("VERA" in bench._greeting.text, "the bench opens on VERA's line for the wave just cleared (%s)" % bench._greeting.text.left(60))
	bench.show_tab("story")
	check(bench.current_tab() == "story" and bench._story_list.get_child_count() >= 2, "the story tab lists what was said")
	bench.show_tab("core")
	Progression.reset()
	bench.refresh()
	await start_quiet_wave(game)
