extends TestCase
## Loot checks (Milestones 3 and 4): drop rates from a seeded stream, item rolling, the inventory
## and overflow tray rules, unlock gates, the version 4 save and its migration from version 2.

const KILLS := 60000


func run_unit() -> void:
	Progression.reset()
	_test_drop_rates()
	_test_item_rolling()
	_test_unlock_gates()
	_test_inventory_rules()
	_test_equip_and_dismantle()
	_test_save_round_trip()
	_test_loot_stream_persists()
	_test_range_record()
	Progression.reset()


func _test_drop_rates() -> void:
	var chaser: EnemyDefinition = load("res://data/enemies/chaser.tres")
	var drone: EnemyDefinition = load("res://data/enemies/swarm_drone.tres")
	var warden: EnemyDefinition = load("res://data/enemies/warden.tres")
	var bases := Progression.droppable_bases()
	check(bases.size() == 6, "six bases can drop at the start: long, penetrator and short barrels, extended, fast-mag and drum (%d)" % bases.size())
	var generator := TestCase.rng(77)
	var counts := [0, 0, 0, 0, 0]
	for i in KILLS:
		var item := Loot.roll_kill_drop(chaser, bases, generator)
		if not item.is_empty():
			counts[int(item["rarity"])] += 1
	var common_rate: float = counts[0] / float(KILLS)
	var uncommon_rate: float = counts[1] / float(KILLS)
	check(absf(common_rate - Loot.COMMON_CHANCE) < Loot.COMMON_CHANCE * 0.1, "Commons drop about 1 in 12 kills (1 in %.1f)" % (1.0 / maxf(common_rate, 0.0001)))
	check(absf(uncommon_rate - Loot.UNCOMMON_CHANCE) < Loot.UNCOMMON_CHANCE * 0.15, "Uncommons drop about 1 in 50 kills (1 in %.1f)" % (1.0 / maxf(uncommon_rate, 0.0001)))
	check(counts[2] == 0 and counts[3] == 0 and counts[4] == 0, "light enemies never drop above Uncommon")
	var drone_drops := 0
	for i in KILLS:
		if not Loot.roll_kill_drop(drone, bases, generator).is_empty():
			drone_drops += 1
	var expected_drone := Loot.any_drop_chance(drone.loot_weight) * KILLS
	check(absf(drone_drops - expected_drone) < expected_drone * 0.12, "swarm drones drop half as often (%d of %d)" % [drone_drops, KILLS])
	var boss_ok := true
	for i in 50:
		var first := Loot.roll_kill_drop(warden, bases, generator, false)
		var replay := Loot.roll_kill_drop(warden, bases, generator, true)
		boss_ok = boss_ok and int(first.get("rarity", -1)) == Items.Rarity.EPIC and int(replay.get("rarity", -1)) == Items.Rarity.RARE
	check(boss_ok, "a boss drops an Epic on its first clear and a Rare on a replay")
	var heavy: EnemyDefinition = load("res://data/enemies/heavy.tres")
	var heavy_counts := [0, 0, 0, 0, 0]
	for i in 4000:
		var item := Loot.roll_kill_drop(heavy, bases, generator)
		if not item.is_empty():
			heavy_counts[int(item["rarity"])] += 1
	var rare_rate: float = heavy_counts[2] / 4000.0
	check(absf(rare_rate - heavy.rare_chance) < heavy.rare_chance * 0.2 and heavy_counts[3] == 0,
		"heavies drop a Rare about %d%% of the time and never an Epic (%.1f%%)" % [roundi(heavy.rare_chance * 100.0), rare_rate * 100.0])
	var heavy_replay := true
	for i in 400:
		heavy_replay = heavy_replay and int(Loot.roll_kill_drop(heavy, bases, generator, true).get("rarity", 0)) <= Items.Rarity.UNCOMMON
	check(heavy_replay, "replayed waves cap a heavy's drop at Uncommon")
	check(Loot.roll_kill_drop(chaser, [] as Array[AttachmentDefinition], generator).is_empty(), "nothing drops when no base is unlocked")


func _test_item_rolling() -> void:
	var generator := TestCase.rng(5)
	var long_barrel := Items.get_attachment(&"long_barrel")
	var ok := true
	for rarity in range(Items.Rarity.COMMON, Items.Rarity.LEGENDARY + 1):
		for i in 40:
			var item := Loot.make_item(long_barrel, rarity, generator)
			var ids := []
			for affix in item["affixes"]:
				ok = ok and not ids.has(affix["id"]) and Items.get_affix(affix["id"]).drops
				ok = ok and float(affix["roll"]) >= 0.0 and float(affix["roll"]) <= 1.0
				ids.append(affix["id"])
			ok = ok and item["affixes"].size() == Items.AFFIX_COUNT[rarity] and item["mark"] == Items.MIN_MARK and Items.is_valid(item)
	check(ok, "rolled items carry the rarity's affix count, distinct pool affixes, rolls in [0, 1] and mark I")
	var first := Loot.make_item(long_barrel, Items.Rarity.RARE, TestCase.rng(99))
	var second := Loot.make_item(long_barrel, Items.Rarity.RARE, TestCase.rng(99))
	check(first["affixes"] == second["affixes"], "the same seed rolls the same affixes")


func _test_unlock_gates() -> void:
	Progression.reset()
	check(Progression.is_slot_open(&"receiver") and Progression.is_slot_open(&"barrel") and Progression.is_slot_open(&"magazine"), "receiver, barrel and magazine are open from the first intermission")
	check(not Progression.is_slot_open(&"muzzle") and not Progression.is_slot_open(&"optic"), "muzzle and optic stay locked")
	var automatic := Items.get_attachment(&"automatic")
	var long_barrel := Items.get_attachment(&"long_barrel")
	check(Progression.is_base_unlocked(long_barrel) and not Progression.is_base_unlocked(automatic), "bases without a gate open with their slot; Automatic waits for the Warden")
	check(not Progression.is_area_open("firing_range"), "the Firing Range is closed before wave 2")
	Progression.record_wave_cleared(1, 0, 1.0)
	Progression.record_wave_cleared(2, 0, 1.0)
	check(Progression.is_area_open("firing_range"), "clearing wave 2 opens the Firing Range")
	for wave in [3, 4, 5]:
		Progression.record_wave_cleared(wave, 0, 1.0)
	check(Progression.is_base_unlocked(automatic) and Progression.droppable_bases().size() == 16, "clearing wave 5 unlocks Automatic and it joins the drop pool with the muzzle and ammo bases (%d)" % Progression.droppable_bases().size())
	check(Progression.is_slot_open(&"muzzle") and Progression.is_slot_open(&"ammo") and Progression.droppable_bases(&"muzzle").size() == 3 and Progression.droppable_bases(&"ammo").size() == 6,
		"the muzzle and ammo slots open at the Warden with three and six bases")
	check(Progression.droppable_bases(&"receiver").size() == 1 and Progression.droppable_bases(&"receiver")[0].id == &"automatic", "the drop pool can be limited to one slot")
	Progression.reset()


func _test_inventory_rules() -> void:
	Progression.reset()
	var generator := TestCase.rng(3)
	var base := Items.get_attachment(&"long_barrel")
	var destinations := {}
	for i in Progression.INVENTORY_SIZE + Progression.OVERFLOW_SIZE:
		var destination := Progression.add_item(Loot.make_item(base, Items.Rarity.COMMON, generator), "test")
		destinations[destination] = int(destinations.get(destination, 0)) + 1
	check(destinations.get("inventory", 0) == Progression.INVENTORY_SIZE and destinations.get("overflow", 0) == Progression.OVERFLOW_SIZE, "drops fill the inventory, then the overflow tray")
	check(Progression.has_overflow() and Progression.overflow().size() == Progression.OVERFLOW_SIZE, "the tray holds twenty")
	var scrap_before := int(Progression.parts()["scrap"])
	var common_destination := Progression.add_item(Loot.make_item(base, Items.Rarity.COMMON, generator), "test")
	check(common_destination == "dismantled" and int(Progression.parts()["scrap"]) == scrap_before + 1, "with both full a Common becomes Scrap")
	var uncommon_destination := Progression.add_item(Loot.make_item(base, Items.Rarity.UNCOMMON, generator), "test")
	check(uncommon_destination == "dismantled" and int(Progression.parts()["alloy"]) == 1, "with both full an Uncommon becomes Alloy and Scrap")
	var oldest_uid := int(Progression.overflow()[0]["uid"])
	Progression.set_locked(oldest_uid, true)
	var rare := Loot.make_item(base, Items.Rarity.RARE, generator)
	var rare_destination := Progression.add_item(rare, "test")
	check(rare_destination == "bumped" and Progression.overflow().size() == Progression.OVERFLOW_SIZE, "a Rare bumps the oldest lesser unlocked tray item")
	check(Items.find_by_uid(Progression.overflow(), oldest_uid) == 0 and Items.find_by_uid(Progression.overflow(), int(rare["uid"])) >= 0, "locked tray items are never bumped; the Rare is kept")
	check(int(Progression.data["records"]["pickups"]) == Progression.INVENTORY_SIZE + Progression.OVERFLOW_SIZE + 1, "pickups are counted for everything kept")
	var dismantled := Progression.dismantle_unlocked_commons()
	# Sixty Commons were kept, one is locked and one was bumped out by the Rare: 58 to dismantle.
	check(dismantled == Progression.INVENTORY_SIZE + Progression.OVERFLOW_SIZE - 2 and Progression.overflow().size() == 2, "dismantle-all clears unlocked Commons from the inventory and tray (%d)" % dismantled)
	check(Progression.move_to_inventory(int(rare["uid"])) and Progression.inventory().size() == 1 and Progression.overflow().size() == 1, "a tray item can be moved into the inventory by hand")
	Progression.reset()


func _test_equip_and_dismantle() -> void:
	Progression.reset()
	var generator := TestCase.rng(4)
	var long_item := Loot.make_item(Items.get_attachment(&"long_barrel"), Items.Rarity.UNCOMMON, generator)
	var pen_item := Loot.make_item(Items.get_attachment(&"penetrator_barrel"), Items.Rarity.COMMON, generator)
	var auto_item := Loot.make_item(Items.get_attachment(&"automatic"), Items.Rarity.COMMON, generator)
	Progression.add_item(long_item)
	Progression.add_item(pen_item)
	Progression.add_item(auto_item)
	check(Progression.equip(int(long_item["uid"])), "an unlocked base equips")
	check(Progression.equipped_in(&"barrel")["uid"] == long_item["uid"] and Progression.inventory().size() == 2, "equipping moves the item out of the inventory")
	check(Progression.build_stats().fire_rate < 4.0 and Progression.build_stats().falloff_start > 20.0, "the build reflects the fitted barrel")
	check(Progression.equip(int(pen_item["uid"])) and Progression.equipped_in(&"barrel")["uid"] == pen_item["uid"], "fitting another barrel swaps it in")
	check(Items.find_by_uid(Progression.inventory(), int(long_item["uid"])) >= 0 and Progression.inventory().size() == 2, "the replaced barrel returns to the inventory")
	check(not Progression.equip(int(auto_item["uid"])) and Progression.equipped_in(&"receiver") == null, "a locked base cannot be equipped")
	check(not Progression.dismantle(int(pen_item["uid"])), "an equipped item cannot be dismantled")
	check(Progression.set_locked(int(long_item["uid"]), true) and not Progression.dismantle(int(long_item["uid"])), "a locked item cannot be dismantled")
	Progression.set_locked(int(long_item["uid"]), false)
	var preview := Progression.preview_equipped(&"barrel", long_item)
	check(preview.falloff_start > Progression.build_stats().falloff_start, "the compare preview builds with the candidate item")
	check(Progression.dismantle(int(long_item["uid"])) and int(Progression.parts()["alloy"]) == 1 and int(Progression.parts()["scrap"]) == 1, "dismantling pays the rarity's parts")
	check(Progression.unequip(&"barrel") and Progression.equipped_in(&"barrel") == null and Progression.inventory().size() == 2, "unequipping returns the item")
	check(int(Progression.data["records"]["dismantled"]) == 1, "dismantling is recorded")
	Progression.reset()


func _test_save_round_trip() -> void:
	Progression.reset()
	var generator := TestCase.rng(8)
	var data := SaveFile.fresh()
	data["inventory"] = [Loot.make_item(Items.get_attachment(&"long_barrel"), Items.Rarity.RARE, generator)]
	data["overflow"] = [Loot.make_item(Items.get_attachment(&"fast_magazine"), Items.Rarity.COMMON, generator)]
	data["equipped"] = {"receiver": Loot.make_item(Items.get_attachment(&"automatic"), Items.Rarity.UNCOMMON, generator)}
	data["parts"] = {"scrap": 4, "alloy": 2, "bogus": 9}
	data["loot_state"] = "123456789012345678"
	data["range"] = {"best_time": 11.5, "par_rewarded": true, "chosen_slot": "receiver"}
	data["records"]["drops"] = 7
	check(SaveFile.save(data), "version 4 save writes")
	var loaded := SaveFile.load_or_fresh()
	check(loaded["version"] == SaveFile.VERSION and loaded["inventory"].size() == 1 and loaded["overflow"].size() == 1 and loaded["equipped"].has("receiver"), "round trip keeps inventory, tray and build")
	check(loaded["parts"]["scrap"] == 4 and loaded["parts"]["alloy"] == 2 and not loaded["parts"].has("bogus"), "round trip keeps known parts and drops unknown ones")
	check(loaded["loot_state"] == "123456789012345678", "the loot stream state survives as a string")
	check(is_equal_approx(loaded["range"]["best_time"], 11.5) and loaded["range"]["par_rewarded"] == true and loaded["range"]["chosen_slot"] == "receiver", "round trip keeps the range record")
	check(loaded["records"]["drops"] == 7, "round trip keeps the new records")
	var v2 := SaveFile.fresh()
	v2["version"] = 2
	v2["credits"] = 50
	v2.erase("parts")
	v2.erase("overflow")
	v2.erase("loot_state")
	v2.erase("range")
	v2["records"] = {"kills": 3, "credits_earned": 60, "deaths": 1, "waves_cleared": 2}
	var migrated := SaveFile.migrate(v2)
	check(migrated["version"] == SaveFile.VERSION and migrated["credits"] == 50 and migrated["parts"]["scrap"] == 0 and migrated["overflow"].is_empty() and migrated["records"]["drops"] == 0, "a Milestone 2 save migrates to the current version with empty new fields")
	SaveFile.delete()
	Progression.reset()


func _test_loot_stream_persists() -> void:
	Progression.reset()
	var chaser: EnemyDefinition = load("res://data/enemies/chaser.tres")
	Progression.data["seed"] = 4242
	Progression.loot_rng.seed = 4242
	var first_run := []
	for i in 400:
		first_run.append(Progression.roll_kill_drop(chaser, false).get("base", ""))
	Progression.save()
	Progression.load_from_disk()
	var continued := []
	for i in 400:
		continued.append(Progression.roll_kill_drop(chaser, false).get("base", ""))
	Progression.reset()
	Progression.data["seed"] = 4242
	Progression.loot_rng.seed = 4242
	var replayed := []
	for i in 800:
		replayed.append(Progression.roll_kill_drop(chaser, false).get("base", ""))
	check(replayed.slice(0, 400) == first_run and replayed.slice(400) == continued, "the loot stream continues from the save exactly where it left off")
	check(int(Progression.data["records"]["drops"]) > 0, "drops are recorded")
	Progression.reset()


func _test_range_record() -> void:
	Progression.reset()
	for wave in [1, 2]:
		Progression.record_wave_cleared(wave, 0, 1.0)
	Progression.set_range_slot(&"magazine")
	var slow := Progression.record_range_time(20.0, 14.0)
	check(slow["best"] and slow["reward"].is_empty() and Progression.inventory().is_empty(), "a run over par records a best time but pays nothing")
	var fast := Progression.record_range_time(12.0, 14.0)
	var reward: Dictionary = fast["reward"]
	check(fast["best"] and not reward.is_empty() and int(reward["rarity"]) == Items.Rarity.UNCOMMON and Items.slot_of(reward) == &"magazine", "the first run under par pays an Uncommon of the chosen slot")
	var again := Progression.record_range_time(11.0, 14.0)
	check(again["best"] and again["reward"].is_empty() and Progression.inventory().size() == 1, "later runs under par only update the best time")
	check(is_equal_approx(Progression.range_state()["best_time"], 11.0) and Progression.range_state()["par_rewarded"], "the range record is kept")
	Progression.reset()
