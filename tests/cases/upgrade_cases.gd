extends TestCase
## Milestone 5 crafting checks: refine (marks, prices, the Sentinel's gate for IV and V), fuse
## (three into one of the next rarity, partners chosen and consumed) with value conservation,
## transmute (Epic plus Legendary core into the base's Legendary), the Legendaries themselves, the
## Tinkerer discount, and the bench's craft tab driving all three.


func run_unit() -> void:
	Progression.reset()
	_test_refine()
	_test_fuse()
	_test_conservation()
	_test_transmute()
	_test_discount()
	Progression.reset()


func run_scene(game: Node) -> void:
	await _test_upgrade_buttons(game)


func _test_refine() -> void:
	Progression.reset()
	var item := Items.make(&"long_barrel", Items.Rarity.RARE)
	Progression.add_item(item, "test")
	var uid := int(item["uid"])
	check(Progression.refine_block_reason(uid).begins_with("Needs 500 credits"), "mark II asks for credits (%s)" % Progression.refine_block_reason(uid))
	Progression.add_credits(500)
	check(Progression.refine_block_reason(uid).begins_with("Needs"), "and parts (%s)" % Progression.refine_block_reason(uid))
	Progression.data["parts"]["alloy"] = 3
	check(Progression.refine(uid) and int(item["mark"]) == 2 and Progression.credits == 0 and int(Progression.parts()["alloy"]) == 0,
		"refining to mark II pays 500 credits and 3 Alloy")
	Progression.add_credits(100000)
	for part in Items.PART_IDS:
		Progression.data["parts"][part] = 50
	check(Progression.refine(uid) and int(item["mark"]) == 3, "mark III costs more")
	check(Progression.refine_block_reason(uid).begins_with("Marks IV and V open"), "marks IV and V wait for the Sentinel")
	Progression.record_wave_cleared(15, 0, 1.0)
	check(Progression.refine(uid) and Progression.refine(uid) and int(item["mark"]) == 5, "after wave 15 an item refines to mark V")
	check(Progression.refine_block_reason(uid) == "Already mark V" and not Progression.refine(uid), "mark V is the top")
	var before := WeaponStats.build(Progression.PISTOL_BASE, {}, {"barrel": Items.make(&"long_barrel", Items.Rarity.RARE)})
	var after := WeaponStats.build(Progression.PISTOL_BASE, {}, {"barrel": item})
	check(after.damage > before.damage, "a refined item's base effect is stronger in the shared stats (%.1f → %.1f)" % [before.damage, after.damage])
	check(int(Progression.data["records"]["refined"]) == 4, "refines are recorded")
	Progression.reset()


func _test_fuse() -> void:
	Progression.reset()
	var keep := Items.make(&"long_barrel", Items.Rarity.UNCOMMON, [{"id": "sharp", "roll": 0.2}], 3)
	var low := Items.make(&"penetrator_barrel", Items.Rarity.UNCOMMON, [], 1)
	var mid := Items.make(&"long_barrel", Items.Rarity.UNCOMMON, [], 2)
	var high := Items.make(&"long_barrel", Items.Rarity.UNCOMMON, [], 4)
	var other_slot := Items.make(&"extended_magazine", Items.Rarity.UNCOMMON)
	var other_rarity := Items.make(&"long_barrel", Items.Rarity.RARE)
	var locked := Items.make(&"long_barrel", Items.Rarity.UNCOMMON)
	for entry in [keep, low, mid, high, other_slot, other_rarity, locked]:
		Progression.add_item(entry, "test")
	Progression.set_locked(int(locked["uid"]), true)
	var partners := Progression.fuse_partners(int(keep["uid"]))
	check(partners.size() == 2 and partners[0] == low and partners[1] == mid,
		"fuse takes the two lowest-mark unlocked items of the same slot and rarity")
	check(Progression.fuse_block_reason(int(keep["uid"])).begins_with("Needs"), "fuse also costs parts (%s)" % Progression.fuse_block_reason(int(keep["uid"])))
	Progression.data["parts"]["alloy"] = Crafting.FUSE_OWN_PARTS
	var fused := Progression.fuse(int(keep["uid"]))
	check(fused == keep and int(keep["rarity"]) == Items.Rarity.RARE and int(keep["mark"]) == 3 and keep["affixes"].size() == Items.AFFIX_COUNT[Items.Rarity.RARE],
		"the kept item becomes a Rare with its base and mark and fresh affixes for its rarity")
	check(Progression.locate(int(low["uid"])).is_empty() and Progression.locate(int(mid["uid"])).is_empty()
		and not Progression.locate(int(high["uid"])).is_empty() and not Progression.locate(int(locked["uid"])).is_empty(),
		"the two partners are used up; the rest stay")
	check(int(Progression.parts()["alloy"]) == 0, "the fuse took its parts")
	var epic := Items.make(&"long_barrel", Items.Rarity.EPIC)
	Progression.add_item(epic, "test")
	check(Progression.fuse_block_reason(int(epic["uid"])) == "Only Commons, Uncommons and Rares fuse", "Epics do not fuse")
	Progression.reset()


func _test_conservation() -> void:
	# By part value (each part worth three of the one below): a fuse's result never dismantles to
	# more than its three inputs plus its price, so fuse-and-dismantle cannot make parts.
	var ok := true
	for rarity in range(Items.Rarity.COMMON, Crafting.FUSABLE_MAX_RARITY + 1):
		var inputs := Crafting.value_of(Crafting.dismantle_value(rarity)) * 3 + Crafting.value_of(Crafting.fuse_cost(rarity))
		var output := Crafting.value_of(Crafting.dismantle_value(rarity + 1))
		ok = ok and output < inputs
	check(ok, "fusing then dismantling always loses part value")


func _test_transmute() -> void:
	Progression.reset()
	var epic := Items.make(&"long_barrel", Items.Rarity.EPIC, [{"id": "sharp", "roll": 0.9}], 2)
	var plain := Items.make(&"penetrator_barrel", Items.Rarity.EPIC)
	var rare := Items.make(&"long_barrel", Items.Rarity.RARE)
	for entry in [epic, plain, rare]:
		Progression.add_item(entry, "test")
	check(Progression.transmute_block_reason(int(rare["uid"])).begins_with("Transmute turns an Epic"), "only Epics transmute")
	check(Progression.transmute_block_reason(int(plain["uid"])).ends_with("has no Legendary"), "a base without a unique cannot")
	check(Progression.transmute_block_reason(int(epic["uid"])).begins_with("Needs"), "transmute needs a Legendary core")
	Progression.data["parts"]["legendary_cores"] = 1
	check(Progression.transmute(int(epic["uid"])) and int(epic["rarity"]) == Items.Rarity.LEGENDARY and int(epic["mark"]) == 2
		and epic["affixes"].size() == 1 and int(Progression.parts()["legendary_cores"]) == 0,
		"a Legendary core turns the Epic into its Legendary, affixes and mark kept")
	check(Items.display_name(epic).begins_with("Stillwater (Long barrel)"), "the Legendary shows its unique name (%s)" % Items.display_name(epic))
	var stats := WeaponStats.build(Progression.PISTOL_BASE, {}, {"barrel": epic})
	check(stats.pierce() >= 1 and bool(stats.behaviours.get("slow_on_pierce", false)), "Stillwater pierces and slows through the shared stats")
	# Every Legendary changes its base's build in some way the Epic does not.
	var same := PackedStringArray()
	for base in Items.legendary_bases():
		var as_epic := WeaponStats.build(Progression.PISTOL_BASE, {}, {String(base.slot): Items.make(base.id, Items.Rarity.EPIC)})
		var as_legendary := WeaponStats.build(Progression.PISTOL_BASE, {}, {String(base.slot): Items.make(base.id, Items.Rarity.LEGENDARY)})
		var differs := str(as_epic.behaviours) != str(as_legendary.behaviours) or str(as_epic.extra) != str(as_legendary.extra) \
			or not is_equal_approx(as_epic.damage, as_legendary.damage) or not is_equal_approx(as_epic.max_range, as_legendary.max_range)
		if not differs or base.legendary_name == "" or base.legendary_description == "":
			same.append(String(base.id))
	check(same.is_empty(), "all six Legendaries have a name, a description and an effect of their own (%s)" % ", ".join(same))
	Progression.reset()


func _test_discount() -> void:
	Progression.reset()
	var full := Progression.craft_cost(Items.Rarity.RARE)
	Progression.data["xp"] = 1000000
	for id in ["rapid_cycle", "extended_feed", "quick_hands", "status_mastery", "scavenger", "tinkerer"]:
		Progression.take_skill(StringName(id))
	var discounted := Progression.craft_cost(Items.Rarity.RARE)
	check(Crafting.value_of(discounted) < Crafting.value_of(full), "Tinkerer makes crafting cheaper (%s → %s)" % [Crafting.describe_cost(full), Crafting.describe_cost(discounted)])
	Progression.reset()


func _test_upgrade_buttons(game: Node) -> void:
	var bench: Bench = game.bench
	Progression.reset()
	var item := Items.make(&"long_barrel", Items.Rarity.EPIC)
	Progression.add_item(item, "test")
	Progression.data["parts"]["legendary_cores"] = 1
	Progression.data["parts"]["alloy"] = 3
	Progression.add_credits(500)
	bench.open()
	bench.show_tab("craft")
	bench.select_item(int(item["uid"]))
	check(bench._refine_button.visible and not bench._refine_button.disabled and "mark II" in bench._refine_button.text,
		"the craft tab offers refining the selected item (%s)" % bench._refine_button.text)
	check(bench._fuse_button.disabled and "Only Commons" in bench._fuse_button.text, "fuse explains why it cannot (%s)" % bench._fuse_button.text)
	check(not bench._transmute_button.disabled and "Stillwater" in bench._transmute_button.text, "transmute names the Legendary (%s)" % bench._transmute_button.text)
	bench._refine_button.pressed.emit()
	check(int(item["mark"]) == 2, "the refine button refines")
	bench._transmute_button.pressed.emit()
	check(int(item["rarity"]) == Items.Rarity.LEGENDARY and "Stillwater" in bench.craft_message, "the transmute button transmutes (%s)" % bench.craft_message)
	bench.show_tab("core")
	bench.craft_message = ""
	Progression.reset()
	bench.refresh()
