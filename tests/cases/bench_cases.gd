extends TestCase
## Milestone 3 bench and Firing Range checks in the running game: the gunsmith slots, inventory
## grid and compare view, equipping through the bench, the overflow tray, and the side-area swap.


func run_scene(game: Node) -> void:
	await _test_bench_gunsmith(game)
	await _test_firing_range(game)


func _test_bench_gunsmith(game: Node) -> void:
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	var bench: Bench = game.bench
	bench.open()
	await physics_frames(1)
	var receiver: Button = bench._slot_buttons["receiver"]
	var muzzle: Button = bench._slot_buttons["muzzle"]
	var optic: Button = bench._slot_buttons["optic"]
	check("(default)" in receiver.text and "Semi-auto" in receiver.text, "an open slot shows its default (%s)" % receiver.text.replace("\n", " / "))
	check("LOCKED" in muzzle.text and "wave 5" in muzzle.text and "Warden" in muzzle.tooltip_text, "a locked slot shows its gate (%s)" % muzzle.text.replace("\n", " / "))
	check("LOCKED" in optic.text, "optic stays locked")
	check(bench._inventory_grid.get_child_count() == Progression.INVENTORY_SIZE and "0 / 40" in bench._inventory_label.text, "the inventory grid shows forty cells")
	check(not bench._tray_box.visible and bench._area_buttons["firing_range"].disabled, "no tray and a locked Firing Range for a new player")
	check(bench._equip_button.disabled and bench._dismantle_button.disabled, "detail buttons wait for a selection")
	# Grant a drop and equip it through the bench.
	var long_item := Items.make(&"long_barrel", Items.Rarity.UNCOMMON, [{"id": "sharp", "roll": 1.0}])
	Progression.add_item(long_item, "test")
	await physics_frames(1)
	check(bench._item_buttons.has(int(long_item["uid"])), "a new item gets a cell in the grid")
	var cell: Button = bench._item_buttons[int(long_item["uid"])]
	check("BA" in cell.text and "If equipped" in cell.tooltip_text and "Damage per shot" in cell.tooltip_text, "the cell's tooltip compares the item with the fitted build")
	bench.select_item(int(long_item["uid"]))
	check("Long barrel I" in bench._detail_title.text and "Sharp: +8% damage" in bench._detail_body.text, "selecting an item fills the detail panel (%s)" % bench._detail_title.text)
	check("Fire rate  4.00 /s  →  3.40 /s" in bench._compare_label.text, "the compare view shows the fire-rate cost (%s)" % bench._compare_label.text.replace("\n", " | "))
	check(not bench._equip_button.disabled and bench._equip_button.text == "Equip", "an unlocked drop can be equipped")
	bench._on_equip_pressed()
	await physics_frames(1)
	var barrel: Button = bench._slot_buttons["barrel"]
	check(Progression.equipped_in(&"barrel") != null and "Long barrel I" in barrel.text and "Uncommon" in barrel.text, "equipping updates the slot card (%s)" % barrel.text.replace("\n", " / "))
	check(bench._equip_button.text == "Unequip" and bench._dismantle_button.disabled, "the fitted item offers Unequip and cannot be dismantled")
	check("Behaviour" not in bench._compare_label.text and "If unequipped" in bench._compare_label.text, "the compare view flips to unequipping")
	check("3.40 shots/s" in bench._stats_summary.text and "40 m:" in bench._stats_summary.text, "the pistol summary uses the fitted build (%s)" % bench._stats_summary.text.split("\n")[1])
	var saved := SaveFile.load_or_fresh()
	check(saved["equipped"].has("barrel"), "equipping saves immediately")
	# Starting a wave carries the build into combat.
	game.start_wave(1)
	await physics_frames(3)
	check(is_equal_approx(game.player.pistol.stats.fire_rate, 3.4) and game.player.pistol.get_node("Model/Slide").scale.z > game.player.pistol._slide_rest_scale.z, "the pistol carries the fitted barrel into the wave and the model shows it")
	game.open_bench()
	await physics_frames(2)
	# A locked base shows why it cannot be equipped; dismantling pays parts.
	var auto_item := Items.make(&"automatic")
	Progression.add_item(auto_item, "test")
	bench.select_item(int(auto_item["uid"]))
	check(bench._equip_button.disabled and "Warden" in bench._equip_button.text, "a gated base explains its gate on the button (%s)" % bench._equip_button.text)
	bench._on_dismantle_pressed()
	await physics_frames(1)
	check(Progression.locate(int(auto_item["uid"])).is_empty() and int(Progression.parts()["scrap"]) == 1 and "SCRAP 1" in bench._parts_label.text, "dismantling from the bench pays Scrap and shows it")
	# Dismantle-all and the overflow tray.
	for i in 3:
		Progression.add_item(Items.make(&"fast_magazine"), "test")
	await physics_frames(1)
	check("(3)" in bench._dismantle_commons_button.text, "the tidy button counts unlocked Commons")
	bench._on_dismantle_commons_pressed()
	await physics_frames(1)
	check(Progression.inventory().is_empty() and int(Progression.parts()["scrap"]) == 4, "dismantle-all clears the Commons")
	for i in Progression.INVENTORY_SIZE + 2:
		Progression.add_item(Items.make(&"extended_magazine"), "test")
	bench.open()
	await physics_frames(1)
	check(bench._tray_box.visible and bench._tray_grid.get_child_count() == 2 and "2 / 20" in bench._tray_label.text, "the tray shows when it holds items")
	check(bench.selected_uid == int(Progression.overflow()[0]["uid"]) and bench._move_button.visible and bench._move_button.disabled, "the bench opens on the tray and the full inventory blocks moving")
	Progression.dismantle(int(Progression.inventory()[0]["uid"]))
	await physics_frames(1)
	check(not bench._move_button.disabled, "freeing a cell allows the move")
	bench._on_move_pressed()
	await physics_frames(1)
	check(Progression.overflow().size() == 1 and Progression.inventory().size() == Progression.INVENTORY_SIZE, "moving takes the tray item into the inventory")
	Progression.reset()
	bench.open()
	await physics_frames(1)


func _test_firing_range(game: Node) -> void:
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	var bench: Bench = game.bench
	bench.open()
	check(bench._area_buttons["firing_range"].disabled, "the Firing Range door is locked before wave 2")
	game.enter_area("firing_range")
	await physics_frames(2)
	check(game.state == game.State.BENCH, "a locked area cannot be entered")
	Progression.record_wave_cleared(1, 0, 1.0)
	Progression.record_wave_cleared(2, 0, 1.0)
	bench.refresh()
	check(not bench._area_buttons["firing_range"].disabled and "open" in bench._area_buttons["firing_range"].text, "clearing wave 2 opens the door")
	game.enter_area("firing_range")
	await physics_frames(3)
	check(game.state == game.State.AREA and game.current_area == "firing_range" and not get_tree_paused(game), "entering swaps the arena for the range")
	check(game.arena.has_method("status_text") and game.arena.get_spawn_points().is_empty(), "the range has no spawn points")
	check(game.hud._wave_label.text == "FIRING RANGE" and "par" in game.hud._wave_progress_label.text, "the HUD names the range (%s)" % game.hud._wave_progress_label.text)
	var targets: Node3D = game.arena.get_node("Targets")
	var dummies := 0
	var start_plate: TargetDummy = null
	var choice_plate: TargetDummy = null
	for child in targets.get_children():
		if child is TargetDummy:
			match child.role:
				"dummy":
					dummies += 1
				"start":
					start_plate = child
				"choose":
					if child.slot_choice == &"receiver":
						choice_plate = child
	check(dummies == 5 and start_plate != null and choice_plate != null, "five dummies, a start plate and reward plates stand in the range")
	# Shooting a dummy shows a damage readout through the normal pipeline.
	var player: Player = game.player
	var dummy: TargetDummy = null
	for child in targets.get_children():
		if child is TargetDummy and child.role == "dummy" and child.label_text == "8 m":
			dummy = child
	player.look_at(Vector3(dummy.global_position.x, player.global_position.y, dummy.global_position.z), Vector3.UP)
	player.pistol.request_fire()
	await physics_frames(2)
	check(dummy.hits == 1 and "last 10" in dummy._readout.text, "a shot registers on the dummy's readout (%s)" % dummy._readout.text.replace("\n", " / "))
	# The gallery: choose a slot, start, hit every target fast, and claim the Uncommon once.
	choice_plate.take_hit(1.0, choice_plate.global_position, Vector3.FORWARD)
	check(Progression.range_state()["chosen_slot"] == "receiver", "shooting a reward plate chooses the slot")
	start_plate.take_hit(1.0, start_plate.global_position, Vector3.FORWARD)
	await physics_frames(1)
	check(game.arena.gallery_running and game.arena._current_target != null, "the start plate begins the gallery")
	var popped := 0
	while game.arena.gallery_running and popped < 20:
		var target: TargetDummy = game.arena._current_target
		target.take_hit(5.0, target.global_position, Vector3.FORWARD)
		popped += 1
		await physics_frames(1)
	check(popped == game.arena.TARGET_COUNT and not game.arena.gallery_running, "the gallery ends after %d targets" % game.arena.TARGET_COUNT)
	# Receiver bases are gated, so the reward falls back to nothing until the Warden; check with a barrel instead.
	check(Progression.inventory().is_empty() and not Progression.range_state()["par_rewarded"], "no receiver can drop yet, so the reward waits (nothing is faked)")
	Progression.set_range_slot(&"barrel")
	start_plate.take_hit(1.0, start_plate.global_position, Vector3.FORWARD)
	await physics_frames(1)
	popped = 0
	while game.arena.gallery_running and popped < 20:
		var target: TargetDummy = game.arena._current_target
		target.take_hit(5.0, target.global_position, Vector3.FORWARD)
		popped += 1
		await physics_frames(1)
	check(Progression.inventory().size() == 1 and Items.slot_of(Progression.inventory()[0]) == &"barrel" and int(Progression.inventory()[0]["rarity"]) == Items.Rarity.UNCOMMON, "the first run under par with an open slot pays an Uncommon of that slot")
	check(Progression.range_state()["par_rewarded"] and "reward" in game.arena.last_result, "the reward is claimed once (%s)" % game.arena.last_result)
	# Leaving returns to the bench with the main arena back in place.
	game.pause()
	await physics_frames(1)
	check(game.pause_menu.visible and game.pause_menu.get_node("%AbandonButton").text == "Leave the range", "the pause menu offers to leave the range")
	game.abandon_wave()
	await physics_frames(3)
	check(game.state == game.State.BENCH and game.current_area == "" and game.arena.get_spawn_points().size() == 5, "leaving swaps the main arena back")
	check(Progression.inventory().size() == 1, "nothing earned in the range is lost on leaving")
	Progression.reset()
	game.start_wave(1)
	await physics_frames(3)
	check(game.state == game.State.COMBAT and game.wave_runner.running, "a wave starts normally after the range")
	# Leave wave 1 running, as the driver's abandon test expects.
	game.wave_runner.stop()


static func get_tree_paused(game: Node) -> bool:
	return game.get_tree().paused
