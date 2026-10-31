extends TestCase
## Milestone 4 crafting table checks: recipe conservation (no craft-and-dismantle loop makes
## parts), craft gates and determinism, reroll rules and its rising price, and the bench's craft
## tab driving both.


func run_unit() -> void:
	Progression.reset()
	_test_conservation()
	_test_craft()
	_test_reroll()
	Progression.reset()


func run_scene(game: Node) -> void:
	await _test_craft_tab(game)


func _test_conservation() -> void:
	# Per part: dismantling a crafted item never returns as much of any part as its recipe took, and
	# never returns a part the recipe did not take, so no loop of the two can turn parts into more.
	var ok := true
	for rarity in Crafting.CRAFT_COSTS.size():
		var cost := Crafting.craft_cost(rarity)
		var back := Crafting.dismantle_value(rarity)
		for part in back:
			ok = ok and cost.has(part) and int(back[part]) < int(cost[part])
	check(ok and not Crafting.is_craftable_rarity(Items.Rarity.LEGENDARY), "every recipe costs more of each part than dismantling its result returns; Legendaries are not crafted")
	# The same over the real progression: craft and dismantle until blocked, from a large stock.
	Progression.reset()
	for part in Items.PART_IDS:
		Progression.data["parts"][part] = 60
	Progression.record_wave_cleared(5, 0, 1.0)
	var start: Dictionary = Progression.parts().duplicate()
	var never_grew := true
	var loops := 0
	for rarity in Crafting.CRAFT_COSTS.size():
		for i in 40:
			var before: Dictionary = Progression.parts().duplicate()
			var item := Progression.craft(&"long_barrel", rarity)
			if item.is_empty():
				break
			Progression.dismantle(int(item["uid"]))
			loops += 1
			for part in Items.PART_IDS:
				never_grew = never_grew and int(Progression.parts()[part]) <= int(before[part])
	var lost := 0
	for part in Items.PART_IDS:
		lost += int(start[part]) - int(Progression.parts()[part])
	check(never_grew and loops > 20 and lost > 0, "%d craft-then-dismantle loops never raise any part and lose %d in all" % [loops, lost])
	Progression.reset()


func _test_craft() -> void:
	Progression.reset()
	check(Progression.craft_block_reason(&"long_barrel", Items.Rarity.COMMON).begins_with("Needs"), "a craft without parts names what it needs")
	check(Progression.craft(&"long_barrel", Items.Rarity.COMMON).is_empty() and Progression.inventory().is_empty(), "a blocked craft changes nothing")
	Progression.data["parts"]["scrap"] = 10
	Progression.data["parts"]["alloy"] = 10
	check(Progression.craft_block_reason(&"splitter", Items.Rarity.COMMON) != "", "a base in a locked slot cannot be crafted (%s)" % Progression.craft_block_reason(&"splitter", Items.Rarity.COMMON))
	check(Progression.craft_block_reason(&"automatic", Items.Rarity.COMMON) != "", "a gated base waits for its gate")
	check(Progression.craft_block_reason(&"standard_barrel", Items.Rarity.COMMON) != "", "defaults are not crafted")
	check(Progression.craft_block_reason(&"long_barrel", Items.Rarity.LEGENDARY) != "", "Legendaries are not crafted")
	var item := Progression.craft(&"long_barrel", Items.Rarity.UNCOMMON)
	check(not item.is_empty() and item["base"] == "long_barrel" and int(item["rarity"]) == Items.Rarity.UNCOMMON and item["affixes"].size() == Items.AFFIX_COUNT[Items.Rarity.UNCOMMON] and Items.is_valid(item),
		"a craft always returns the chosen base at the chosen rarity with rolled affixes")
	check(Progression.parts()["scrap"] == 6 and Progression.parts()["alloy"] == 8 and Progression.inventory().size() == 1 and int(Progression.data["records"]["crafted"]) == 1,
		"the craft paid its recipe (4 Scrap, 2 Alloy) and the item is in the inventory")
	Progression.record_wave_cleared(5, 0, 1.0)
	check(Progression.craft_block_reason(&"splitter", Items.Rarity.COMMON) == "" and Progression.craft_block_reason(&"explosive_rounds", Items.Rarity.COMMON) == "",
		"muzzle and ammo bases craft once the Warden opens their slots")
	# Crafting draws from the persisted loot stream: the same seed crafts the same affixes.
	var rolls := []
	for attempt in 2:
		Progression.reset()
		Progression.data["seed"] = 777
		Progression.loot_rng.seed = 777
		Progression.data["parts"]["alloy"] = 10
		Progression.data["parts"]["circuits"] = 10
		rolls.append(Progression.craft(&"penetrator_barrel", Items.Rarity.RARE)["affixes"])
	check(rolls[0] == rolls[1], "crafting is seeded by the save's loot stream")
	# A full inventory and tray block the craft instead of losing the item.
	Progression.reset()
	Progression.data["parts"]["scrap"] = 100
	for i in Progression.INVENTORY_SIZE:
		Progression.data["inventory"].append(Items.make(&"long_barrel"))
	for i in Progression.OVERFLOW_SIZE:
		Progression.data["overflow"].append(Items.make(&"long_barrel"))
	check(Progression.craft_block_reason(&"long_barrel", Items.Rarity.COMMON) == "Inventory and tray are full", "a full inventory and tray block crafting")
	Progression.reset()


func _test_reroll() -> void:
	Progression.reset()
	var item := Items.make(&"long_barrel", Items.Rarity.RARE, [{"id": "sharp", "roll": 0.5}, {"id": "keen", "roll": 0.5}, {"id": "quick", "roll": 0.5}])
	Progression.add_item(item, "test")
	var uid := int(item["uid"])
	check(Crafting.reroll_cost(item) == {"alloy": 2, "circuits": 1}, "a Rare's first reroll costs 2 Alloy and 1 Circuit (%s)" % Crafting.describe_cost(Crafting.reroll_cost(item)))
	check(Progression.reroll_block_reason(uid, 1).begins_with("Needs") and not Progression.reroll_affix(uid, 1), "a reroll without parts is blocked")
	check(Progression.reroll_block_reason(uid, 5) == "No such affix", "an affix the item does not have cannot be rerolled")
	Progression.data["parts"]["alloy"] = 40
	Progression.data["parts"]["circuits"] = 40
	var kept_ok := true
	var distinct_ok := true
	var changed := 0
	for i in 30:
		var before: Array = item["affixes"].duplicate(true)
		var rerolled := Progression.reroll_affix(uid, 1)
		kept_ok = kept_ok and rerolled and item["affixes"][0] == before[0] and item["affixes"][2] == before[2]
		var ids := [item["affixes"][0]["id"], item["affixes"][1]["id"], item["affixes"][2]["id"]]
		distinct_ok = distinct_ok and ids[1] != ids[0] and ids[1] != ids[2] and Items.get_affix(ids[1]).drops
		if item["affixes"][1] != before[1]:
			changed += 1
		if Progression.reroll_block_reason(uid, 1) != "":
			break
	check(kept_ok and distinct_ok and changed > 0, "a reroll replaces only the chosen affix, never with one the item already carries")
	var rerolls := int(item["rerolls"])
	check(rerolls >= 3 and Crafting.reroll_cost(item) == {"alloy": 2 * (rerolls + 1), "circuits": rerolls + 1},
		"the price rises with every reroll of the item (%d rerolls, next %s)" % [rerolls, Crafting.describe_cost(Crafting.reroll_cost(item))])
	var spent_alloy := 40 - int(Progression.parts()["alloy"])
	check(spent_alloy == rerolls * (rerolls + 1), "the rising price was paid each time (%d Alloy for %d rerolls)" % [spent_alloy, rerolls])
	check(int(Progression.data["records"]["rerolled"]) == rerolls, "rerolls are counted")
	check(Crafting.reroll_cost(Items.make(&"long_barrel")) == {}, "a Common with no affixes has nothing to reroll")
	# The reroll count survives a save round trip.
	Progression.save()
	var loaded := SaveFile.load_or_fresh()
	check(int(loaded["inventory"][0].get("rerolls", -1)) == rerolls, "the reroll count is saved with the item")
	SaveFile.delete()
	Progression.reset()


func _test_craft_tab(game: Node) -> void:
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	var bench: Bench = game.bench
	bench.open()
	await physics_frames(1)
	check(not bench.is_craft_tab_open(), "the bench opens on core tuning")
	bench.show_tab("craft")
	await physics_frames(1)
	check(bench.is_craft_tab_open() and bench._craft_button.disabled and "Needs" in bench._craft_button.text,
		"the craft tab shows the recipe and why it is blocked (%s)" % bench._craft_button.text)
	check(bench._craft_slot_buttons["muzzle"].disabled and not bench._craft_slot_buttons["barrel"].disabled, "slots still locked are greyed on the table")
	Progression.data["parts"]["scrap"] = 7
	bench.refresh()
	await physics_frames(1)
	check(not bench._craft_button.disabled and "Common" in bench._craft_button.text, "with parts the craft button is live (%s)" % bench._craft_button.text)
	bench._on_craft_pressed()
	await physics_frames(1)
	check(Progression.inventory().size() == 1 and Progression.parts()["scrap"] == 4 and bench.selected_uid == int(Progression.inventory()[0]["uid"]),
		"crafting from the bench pays, adds the item and selects it")
	check("Crafted" in bench._craft_message_label.text, "the table says what it made (%s)" % bench._craft_message_label.text)
	# Reroll the selected item from the same tab.
	var item := Items.make(&"long_barrel", Items.Rarity.UNCOMMON, [{"id": "sharp", "roll": 0.5}])
	Progression.add_item(item, "test")
	Progression.data["parts"]["scrap"] = 10
	Progression.data["parts"]["alloy"] = 10
	bench.select_item(int(item["uid"]))
	await physics_frames(1)
	check(bench._reroll_buttons[0].visible and not bench._reroll_buttons[0].disabled and not bench._reroll_buttons[1].visible,
		"the selected item's affixes each get a reroll button")
	bench._on_reroll_pressed(0)
	await physics_frames(1)
	check(int(item["rerolls"]) == 1 and Progression.parts()["scrap"] == 8 and Progression.parts()["alloy"] == 9, "rerolling from the bench pays 2 Scrap and 1 Alloy")
	check("→" in bench._craft_message_label.text, "the table shows the old and new affix (%s)" % bench._craft_message_label.text)
	bench.show_tab("core")
	Progression.reset()
	bench.refresh()
	await physics_frames(1)
	# Leave wave 1 running with its spawns stopped, as the case before this one did.
	game.start_wave(1)
	await physics_frames(3)
	game.wave_runner.stop()
