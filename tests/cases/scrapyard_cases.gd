extends TestCase
## Milestone 4 Scrapyard checks: the gate, the extraction payout and its records, the version 3
## save's migration, and a run in the running game (cores, the door, extraction, death).


func run_unit() -> void:
	Progression.reset()
	_test_rules()
	_test_migration()
	Progression.reset()


func run_scene(game: Node) -> void:
	await _test_run(game)


func _test_rules() -> void:
	Progression.reset()
	for wave in [1, 2, 3, 4]:
		Progression.record_wave_cleared(wave, 0, 1.0)
	check(not Progression.is_area_open("scrapyard"), "the Scrapyard is closed before the Warden")
	Progression.record_wave_cleared(5, 0, 1.0)
	check(Progression.is_area_open("scrapyard"), "clearing wave 5 opens the Scrapyard")
	check(Progression.scrapyard_parts(0).is_empty(), "extracting with nothing pays no parts")
	var parts := Progression.scrapyard_parts(9)
	check(parts == {"scrap": 18, "alloy": 3, "circuits": 1}, "nine cores pay 18 Scrap, 3 Alloy and 1 Circuit (%s)" % Crafting.describe_cost(parts))
	var first := Progression.record_scrapyard_extraction(9, 80.0)
	check(first["first"] and int(first["reward"].get("rarity", -1)) == Items.Rarity.RARE and Progression.inventory().size() == 1,
		"the first extraction pays a Rare")
	check(Progression.parts()["scrap"] == 18 and Progression.parts()["alloy"] == 3 and Progression.parts()["circuits"] == 1, "the carried cores become parts")
	check(Progression.data["story_flags"].has(Progression.SCRAPYARD_LOG_FLAG), "the first extraction finds the yard's log")
	var second := Progression.record_scrapyard_extraction(2, 95.0)
	check(not second["first"] and int(second["reward"].get("rarity", -1)) == Items.Rarity.RARE and Progression.inventory().size() == 2,
		"every extraction pays a Rare, not only the first")
	var state := Progression.scrapyard_state()
	check(int(state["extractions"]) == 2 and int(state["best_cores"]) == 9, "extractions and the best haul are recorded")
	check(Progression.data["story_flags"].count(Progression.SCRAPYARD_LOG_FLAG) == 1, "the log is found once")
	Progression.reset()


func _test_migration() -> void:
	var v3 := SaveFile.fresh()
	v3["version"] = 3
	v3.erase("areas")
	v3["records"].erase("crafted")
	v3["records"].erase("rerolled")
	var item := Items.make(&"long_barrel", Items.Rarity.UNCOMMON, [{"id": "sharp", "roll": 0.5}])
	item.erase("rerolls")
	v3["inventory"] = [item]
	var migrated := SaveFile.migrate(v3)
	check(migrated["version"] == SaveFile.VERSION and int(migrated["areas"]["scrapyard"]["extractions"]) == 0
		and int(migrated["records"]["crafted"]) == 0 and int(migrated["records"]["rerolled"]) == 0,
		"a Milestone 3 save migrates to version %d with empty Scrapyard and crafting records" % SaveFile.VERSION)
	check(migrated["inventory"].size() == 1 and int(migrated["inventory"][0].get("rerolls", -1)) == 0, "its items gain a reroll count of zero")


func _test_run(game: Node) -> void:
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	for wave in [1, 2, 3, 4, 5]:
		Progression.record_wave_cleared(wave, 0, 1.0)
	var bench: Bench = game.bench
	bench.open()
	check(not bench._area_buttons["scrapyard"].disabled, "the bench offers the Scrapyard after the Warden")
	game.enter_area("scrapyard")
	await physics_frames(3)
	var yard: Node3D = game.arena
	check(game.state == game.State.AREA and game.current_area == "scrapyard" and yard.get_spawn_points().size() == 5,
		"entering loads the Scrapyard with its spawn points")
	check(yard.running and game.wave_runner.running and yard.cores_left() == 12, "the salvage run starts with twelve cores on the wrecks")
	check(int(Progression.scrapyard_state()["runs"]) == 1, "the run is counted")
	check("Salvage" in game.hud._wave_progress_label.text, "the HUD shows the run's status (%s)" % game.hud._wave_progress_label.text)
	game.wave_runner.stop()
	game.wave_runner.clear_enemies()
	# Walk onto a core: it is picked up.
	var player: Player = game.player
	var core: MeshInstance3D = yard._cores[0]
	player.global_position = Vector3(core.global_position.x, player.global_position.y, core.global_position.z)
	await physics_frames(2)
	check(yard.carried == 1 and not core.visible and yard.cores_left() == 11, "walking over a core picks it up")
	# The door stays shut until the clock runs out; the pad does nothing before then.
	player.global_position = Vector3(yard._pad.global_position.x, player.global_position.y, yard._pad.global_position.z)
	await physics_frames(2)
	check(not yard.door_open and game.state == game.State.AREA, "the pad does nothing while the door is shut")
	yard.elapsed = yard.RUN_SECONDS - 0.01
	await physics_frames(3)
	check(game.state == game.State.CLEARED and yard.extracted_once, "the door opens at the end of the clock and the pad extracts")
	check(int(Progression.scrapyard_state()["extractions"]) == 1 and Progression.parts()["scrap"] == Progression.SCRAP_PER_CORE,
		"extraction pays the carried core as parts")
	check(Progression.inventory().size() == 1 and int(Progression.inventory()[0]["rarity"]) == Items.Rarity.RARE, "extraction pays a Rare")
	check(game.hud._banner.visible and game.hud._banner_title.text == "EXTRACTED" and "Rare" in game.hud._banner_detail.text,
		"the extraction banner shows the haul (%s)" % game.hud._banner_detail.text.replace("\n", " / "))
	await seconds(game.CLEARED_BANNER_TIME + 2.0)
	check(game.state == game.State.BENCH and game.current_area == "", "the bench opens after the banner, back in the arena")
	# A second run, ended by death: the carried cores are lost.
	game.enter_area("scrapyard")
	await physics_frames(3)
	yard = game.arena
	game.wave_runner.stop()
	game.wave_runner.clear_enemies()
	player = game.player
	core = yard._cores[1]
	player.global_position = Vector3(core.global_position.x, player.global_position.y, core.global_position.z)
	await physics_frames(2)
	var scrap: int = Progression.parts()["scrap"]
	check(yard.carried == 1, "a core is carried on the second run")
	player.take_damage(10000.0)
	await physics_frames(3)
	check(game.state == game.State.DEAD and Progression.parts()["scrap"] == scrap and int(Progression.scrapyard_state()["extractions"]) == 1,
		"dying in the yard loses the carried cores")
	check(game.hud._death_panel.visible and "Scrapyard" in game.hud._death_summary.text, "the death screen names the yard (%s)" % game.hud._death_summary.text.replace("\n", " / "))
	game.open_bench()
	await physics_frames(3)
	check(game.current_area == "" and game.arena.get_spawn_points().size() == 5, "leaving the dead run swaps the main arena back")
	Progression.reset()
	bench.refresh()
	await physics_frames(1)
	# Leave wave 1 running with its spawns stopped, as the case before this one did.
	game.start_wave(1)
	await physics_frames(3)
	game.wave_runner.stop()
