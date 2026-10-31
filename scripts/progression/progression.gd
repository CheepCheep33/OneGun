extends Node
## Everything that outlives a wave, autoloaded as `Progression`: credits, core tuning levels,
## wave progress, the inventory, overflow tray and equipped build, crafting parts, the seeded loot
## stream, and the save file. Rewards commit the moment they are earned; the bench is the only
## place that writes the save.

signal credits_changed(credits: int)
signal core_level_changed(id: StringName, level: int)
signal progress_changed
## The inventory, overflow tray, equipped build or parts changed.
signal inventory_changed
## An item arrived. `destination` is "inventory", "overflow", "dismantled" (both full, turned to
## parts) or "bumped" (it took a lesser item's place in the tray).
signal item_received(item: Dictionary, destination: String)
## Experience crossed into a new player level (one skill point each).
signal level_up(level: int)
signal skills_changed

const PISTOL_BASE := preload("res://data/weapons/pistol_base.tres")
## Per-kill credits and enemy health step up by this much per wave tier (5 waves each).
const TIER_STEP := 1.6
const REFORGE_INCOME_STEP := 4.0
const WAVES_PER_TIER := 5
const INVENTORY_SIZE := 40
const OVERFLOW_SIZE := 20
## Side areas and the wave whose first clear opens them (the Scrapyard opens when the Warden falls).
const AREA_GATES := {"firing_range": 2, "scrapyard": 5, "foundry": 10, "signal_tower": 15}
## Marks IV and V open when the Sentinel falls (plan: Sentinel unlocks mark IV and V).
const HIGH_MARK_WAVE := 15
const LOW_MARK_CAP := 3
## Scrapyard extraction: parts per scrap core carried out, and a Rare every time (plan: Scrapyard).
const SCRAP_PER_CORE := 2
const CORES_PER_ALLOY := 3
const CORES_PER_CIRCUIT := 8
const SCRAPYARD_LOG_FLAG := "log_scrapyard_1"

var data: Dictionary = SaveFile.fresh()
## True when a save existed when the game started, so the bench can greet a returning player.
var loaded_from_disk := false
## Seeded from the save so a bug report with a seed reproduces its drops (plan: determinism).
var loot_rng := RandomNumberGenerator.new()
var _purchases_this_session := 0


func _ready() -> void:
	SaveFile.probe_storage()
	load_from_disk()


# ------------------------------------------------------------------ credits

var credits: int:
	get:
		return int(data["credits"])


func add_credits(amount: int, source := "") -> void:
	if amount <= 0:
		return
	data["credits"] = credits + amount
	data["records"]["credits_earned"] = int(data["records"]["credits_earned"]) + amount
	credits_changed.emit(credits)
	if not source.is_empty():
		PlaytestLog.event("credits", {"amount": amount, "source": source, "total": credits})


func can_afford(cost: int) -> bool:
	return credits >= cost


# ------------------------------------------------------------------ core tuning

func core_level(id: StringName) -> int:
	return int(data["core_levels"].get(String(id), 0))


func core_levels() -> Dictionary:
	return data["core_levels"]


func core_cost(id: StringName) -> int:
	var tuning := CoreTuning.get_definition(id)
	return tuning.cost_at(core_level(id)) if tuning else 0


func can_buy_core(id: StringName) -> bool:
	var tuning := CoreTuning.get_definition(id)
	return tuning != null and not tuning.is_maxed(core_level(id)) and can_afford(core_cost(id))


## Spends credits on one level. Returns false (and changes nothing) when it cannot be bought.
func buy_core(id: StringName) -> bool:
	if not can_buy_core(id):
		return false
	var cost := core_cost(id)
	data["credits"] = credits - cost
	data["core_levels"][String(id)] = core_level(id) + 1
	_purchases_this_session += 1
	PlaytestLog.event("purchase", {"stat": id, "level": core_level(id), "cost": cost, "left": credits,
		"first_of_session": _purchases_this_session == 1})
	credits_changed.emit(credits)
	core_level_changed.emit(id, core_level(id))
	return true


# ------------------------------------------------------------------ build

var tier: int:
	get:
		return int(data["tier"])


## The current build stats: the single source of truth for combat, the bench and the HUD.
func build_stats() -> WeaponStats:
	return WeaponStats.build(PISTOL_BASE, data["core_levels"], data["equipped"], data["skills"], {}, tier)


## Build stats with one more level of a core stat, for the bench preview.
func preview_core(id: StringName) -> WeaponStats:
	var levels: Dictionary = data["core_levels"].duplicate()
	levels[String(id)] = core_level(id) + 1
	return WeaponStats.build(PISTOL_BASE, levels, data["equipped"], data["skills"], {}, tier)


## Build stats with `item` in its slot (or the slot emptied when item is null), for the compare view.
func preview_equipped(slot: StringName, item: Variant) -> WeaponStats:
	var equipped: Dictionary = data["equipped"].duplicate()
	if item is Dictionary:
		equipped[String(slot)] = item
	else:
		equipped.erase(String(slot))
	return WeaponStats.build(PISTOL_BASE, data["core_levels"], equipped, data["skills"], {}, tier)


# ------------------------------------------------------------------ waves

var highest_cleared_wave: int:
	get:
		return int(data["waves"]["highest_cleared"])


func is_wave_cleared(wave: int) -> bool:
	return data["waves"]["first_clears"].has(wave)


## The wave the player should play next: the first uncleared one.
func next_wave() -> int:
	return highest_cleared_wave + 1


## True when the wave can be started: every wave up to the next uncleared one.
func is_wave_available(wave: int) -> bool:
	return wave >= 1 and wave <= next_wave()


static func tier_of_wave(wave: int) -> int:
	return maxi(wave - 1, 0) / WAVES_PER_TIER


## Multiplier for enemy health at a wave, from the wave tier and Reforge tier.
func reward_multiplier(wave: int) -> float:
	return pow(TIER_STEP, tier_of_wave(wave)) * pow(WeaponStats.REFORGE_STEP, tier)


## Multiplier for per-kill credits: the wave tier, and a Reforge step a little steeper than the
## enemies' (REFORGE_INCOME_STEP), so the first waves after a Reforge buy back the core levels in
## about ten minutes now that a first run is twenty waves long (Reforge simulation, Milestone 5).
func income_multiplier(wave: int) -> float:
	return pow(TIER_STEP, tier_of_wave(wave)) * bonus_multiplier()


## Completion bonuses scale with the Reforge tier only, by the same step as kill income.
func bonus_multiplier() -> float:
	return pow(REFORGE_INCOME_STEP, tier)


func record_kill(credits_paid: int) -> void:
	data["records"]["kills"] = int(data["records"]["kills"]) + 1
	add_credits(credits_paid)
	add_xp(credits_paid)


## Pays the completion bonus and marks the wave. Pays the same on replay (the plan's replay rule).
## Returns whether it was a first clear, which decides the guaranteed loot.
func record_wave_cleared(wave: int, bonus: int, duration: float) -> bool:
	var first := not is_wave_cleared(wave)
	if first:
		data["waves"]["first_clears"].append(wave)
		data["waves"]["highest_cleared"] = maxi(highest_cleared_wave, wave)
	data["records"]["waves_cleared"] = int(data["records"]["waves_cleared"]) + 1
	add_credits(bonus, "wave_%d_bonus" % wave)
	add_xp(bonus)
	PlaytestLog.event("wave_cleared", {"wave": wave, "first": first, "seconds": "%.1f" % duration, "bonus": bonus})
	progress_changed.emit()
	return first


func record_death(wave: int, duration: float) -> void:
	data["records"]["deaths"] = int(data["records"]["deaths"]) + 1
	PlaytestLog.event("death", {"wave": wave, "seconds": "%.1f" % duration, "credits_kept": credits})
	progress_changed.emit()


# ------------------------------------------------------------------ unlocks

# ------------------------------------------------------------------ experience and skills

var xp: int:
	get:
		return int(data["xp"])


func player_level() -> int:
	return Skills.level_for_xp(xp)


## Experience comes with every credit earned from kills and clears (plan: experience from kills
## and clears), so it scales with the wave like credits do.
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	var before := player_level()
	data["xp"] = xp + amount
	var after := player_level()
	if after > before:
		PlaytestLog.event("level_up", {"level": after})
		level_up.emit(after)


## One bonus skill point per boss, the first time it falls. Returns true the first time.
func record_boss_kill(boss_id: StringName) -> bool:
	if data["boss_kills"].has(String(boss_id)):
		return false
	data["boss_kills"].append(String(boss_id))
	skills_changed.emit()
	return true


func skill_points_total() -> int:
	return player_level() - 1 + data["boss_kills"].size()


func skill_points_available() -> int:
	return skill_points_total() - Skills.spent(data["skills"])


func has_skill(id: StringName) -> bool:
	return int(data["skills"].get(String(id), 0)) > 0


func skill_block_reason(id: StringName) -> String:
	return Skills.block_reason(id, data["skills"], skill_points_available())


func take_skill(id: StringName) -> bool:
	if skill_block_reason(id) != "":
		return false
	data["skills"][String(id)] = 1
	PlaytestLog.event("skill", {"id": String(id), "points_left": skill_points_available()})
	skills_changed.emit()
	return true


## Free respec (plan: respec is free at the bench).
func respec_skills() -> void:
	if data["skills"].is_empty():
		return
	data["skills"].clear()
	PlaytestLog.event("respec", {})
	skills_changed.emit()


func player_effects() -> Dictionary:
	return Skills.player_effects(data["skills"])


# ------------------------------------------------------------------ unlocks

## Progression unlocks set by side-area clears: "foundry" (Burst), "signal_tower" (Charge),
## "signal_tower_top" (Overflow).
func has_unlock(flag: String) -> bool:
	return flag == "" or data["unlocks"].has(flag)


func add_unlock(flag: String) -> bool:
	if flag == "" or data["unlocks"].has(flag):
		return false
	data["unlocks"].append(flag)
	progress_changed.emit()
	return true


## A slot is open once its gate wave has been cleared (0 = open from the start).
func is_slot_open(slot_id: StringName) -> bool:
	var slot := Items.get_slot(slot_id)
	return slot != null and (slot.unlock_wave <= 0 or is_wave_cleared(slot.unlock_wave))


## A base is unlocked once its slot is open and its own gate wave (if any) has been cleared.
func is_base_unlocked(base: AttachmentDefinition) -> bool:
	if base == null or not is_slot_open(base.slot):
		return false
	if not has_unlock(base.unlock_flag):
		return false
	return base.unlock_wave <= 0 or is_wave_cleared(base.unlock_wave)


## The bases loot can roll right now: non-default, unlocked, optionally limited to one slot.
func droppable_bases(slot: StringName = &"") -> Array[AttachmentDefinition]:
	var result: Array[AttachmentDefinition] = []
	for base in Items.all_attachments():
		if base.is_default or (slot != &"" and base.slot != slot):
			continue
		if is_base_unlocked(base):
			result.append(base)
	return result


func is_area_open(area_id: String) -> bool:
	return AREA_GATES.has(area_id) and is_wave_cleared(int(AREA_GATES[area_id]))


## Why an open area cannot be entered right now ("" when it can): the Foundry's one attempt per
## intermission.
func area_block_reason(area_id: String) -> String:
	if not is_area_open(area_id):
		return "Opens when wave %d is cleared" % int(AREA_GATES.get(area_id, 0))
	if area_id == "foundry" and is_foundry_spent():
		return "One attempt per intermission: play a wave first"
	return ""


# ------------------------------------------------------------------ inventory

func inventory() -> Array:
	return data["inventory"]


func overflow() -> Array:
	return data["overflow"]


func equipped() -> Dictionary:
	return data["equipped"]


func equipped_in(slot_id: StringName) -> Variant:
	return data["equipped"].get(String(slot_id))


func parts() -> Dictionary:
	return data["parts"]


func has_overflow() -> bool:
	return not data["overflow"].is_empty()


## Where an item lives: {"where": "inventory" | "overflow" | "equipped", "list", "index", "item"},
## or an empty dictionary.
func locate(uid: int) -> Dictionary:
	for list_name in ["inventory", "overflow"]:
		var index := Items.find_by_uid(data[list_name], uid)
		if index >= 0:
			return {"where": list_name, "list": data[list_name], "index": index, "item": data[list_name][index]}
	for slot in data["equipped"]:
		if int(data["equipped"][slot].get("uid", -1)) == uid:
			return {"where": "equipped", "list": null, "index": -1, "item": data["equipped"][slot], "slot": slot}
	return {}


## Takes a dropped or granted item in (plan: Inventory). Returns where it went.
func add_item(item: Dictionary, source := "") -> String:
	var destination := "inventory"
	if data["inventory"].size() < INVENTORY_SIZE:
		data["inventory"].append(item)
	elif data["overflow"].size() < OVERFLOW_SIZE:
		data["overflow"].append(item)
		destination = "overflow"
	else:
		# Both full: Commons and Uncommons become parts; rarer drops bump the oldest lesser item.
		var victim := _bump_candidate(int(item.get("rarity", 0)))
		if int(item.get("rarity", 0)) > Items.Rarity.UNCOMMON and victim >= 0:
			_add_parts(Items.parts_for_rarity(int(data["overflow"][victim].get("rarity", 0))))
			data["overflow"].remove_at(victim)
			data["overflow"].append(item)
			destination = "bumped"
		else:
			_add_parts(Items.parts_for_rarity(int(item.get("rarity", 0))))
			data["records"]["dismantled"] = int(data["records"]["dismantled"]) + 1
			destination = "dismantled"
	if destination != "dismantled":
		data["records"]["pickups"] = int(data["records"]["pickups"]) + 1
	PlaytestLog.event("item", {"base": item.get("base", ""), "rarity": item.get("rarity", 0),
		"to": destination, "source": source})
	inventory_changed.emit()
	item_received.emit(item, destination)
	return destination


## Index of the oldest unlocked tray item of the lowest rarity below `rarity`, or -1.
func _bump_candidate(rarity: int) -> int:
	var best := -1
	for i in data["overflow"].size():
		var candidate: Dictionary = data["overflow"][i]
		if bool(candidate.get("locked", false)) or int(candidate.get("rarity", 0)) >= rarity:
			continue
		if best < 0 or int(candidate.get("rarity", 0)) < int(data["overflow"][best].get("rarity", 0)):
			best = i
	return best


## Fits an item from the inventory or tray into its slot. The item it replaces takes its place.
func equip(uid: int) -> bool:
	var found := locate(uid)
	if found.is_empty() or found["where"] == "equipped":
		return false
	var item: Dictionary = found["item"]
	var base := Items.get_attachment(item.get("base", ""))
	if base == null or not is_base_unlocked(base):
		return false
	var slot := String(base.slot)
	var list: Array = found["list"]
	list.remove_at(found["index"])
	var previous: Variant = data["equipped"].get(slot)
	if previous is Dictionary:
		list.insert(found["index"], previous)
	data["equipped"][slot] = item
	PlaytestLog.event("equip", {"slot": slot, "base": item.get("base", ""), "rarity": item.get("rarity", 0)})
	inventory_changed.emit()
	return true


## Puts the slot's attachment back in the inventory (or the tray). False when both are full.
func unequip(slot_id: StringName) -> bool:
	var slot := String(slot_id)
	var item: Variant = data["equipped"].get(slot)
	if not (item is Dictionary):
		return false
	if data["inventory"].size() < INVENTORY_SIZE:
		data["inventory"].append(item)
	elif data["overflow"].size() < OVERFLOW_SIZE:
		data["overflow"].append(item)
	else:
		return false
	data["equipped"].erase(slot)
	PlaytestLog.event("unequip", {"slot": slot, "base": item.get("base", "")})
	inventory_changed.emit()
	return true


func set_locked(uid: int, value: bool) -> bool:
	var found := locate(uid)
	if found.is_empty():
		return false
	found["item"]["locked"] = value
	inventory_changed.emit()
	return true


## Turns an unlocked, unequipped item into parts.
func dismantle(uid: int) -> bool:
	var found := locate(uid)
	if found.is_empty() or found["where"] == "equipped" or bool(found["item"].get("locked", false)):
		return false
	var item: Dictionary = found["item"]
	found["list"].remove_at(found["index"])
	_add_parts(Items.parts_for_rarity(int(item.get("rarity", 0))))
	data["records"]["dismantled"] = int(data["records"]["dismantled"]) + 1
	PlaytestLog.event("dismantle", {"base": item.get("base", ""), "rarity": item.get("rarity", 0)})
	inventory_changed.emit()
	return true


## The one-click tidy: every unlocked Common in the inventory and tray becomes Scrap.
func dismantle_unlocked_commons() -> int:
	var count := 0
	for list_name in ["inventory", "overflow"]:
		var kept := []
		for item in data[list_name]:
			if int(item.get("rarity", 0)) == Items.Rarity.COMMON and not bool(item.get("locked", false)):
				_add_parts(Items.parts_for_rarity(Items.Rarity.COMMON))
				count += 1
			else:
				kept.append(item)
		data[list_name].assign(kept)
	if count > 0:
		data["records"]["dismantled"] = int(data["records"]["dismantled"]) + count
		PlaytestLog.event("dismantle_commons", {"count": count})
		inventory_changed.emit()
	return count


## Moves a tray item into the inventory when there is room.
func move_to_inventory(uid: int) -> bool:
	var index := Items.find_by_uid(data["overflow"], uid)
	if index < 0 or data["inventory"].size() >= INVENTORY_SIZE:
		return false
	data["inventory"].append(data["overflow"][index])
	data["overflow"].remove_at(index)
	inventory_changed.emit()
	return true


# ------------------------------------------------------------------ crafting table

## Why a craft cannot happen right now, or "" when it can: the base must be a non-default one whose
## slot and gate are open, the rarity craftable, the parts there and the inventory or tray not full.
func craft_block_reason(base_id: StringName, rarity: int) -> String:
	var base := Items.get_attachment(base_id)
	if base == null or base.is_default:
		return "Pick a base"
	if not is_slot_open(base.slot):
		var slot := Items.get_slot(base.slot)
		return slot.gate_text if slot else "Slot locked"
	if not is_base_unlocked(base):
		return base.gate_text
	if not Crafting.is_craftable_rarity(rarity):
		return "Legendaries come from a Legendary core"
	if data["inventory"].size() >= INVENTORY_SIZE and data["overflow"].size() >= OVERFLOW_SIZE:
		return "Inventory and tray are full"
	if not Crafting.can_afford(data["parts"], craft_cost(rarity)):
		return "Needs " + Crafting.describe_cost(craft_cost(rarity))
	return ""


## The crafting table's prices after the Tinkerer skill.
func craft_cost(rarity: int) -> Dictionary:
	return Crafting.discounted(Crafting.craft_cost(rarity), craft_discount())


func reroll_cost(item: Dictionary) -> Dictionary:
	return Crafting.discounted(Crafting.reroll_cost(item), craft_discount())


func craft_discount() -> float:
	return float(player_effects().get("craft_discount", 0.0))


## Makes the chosen base at the chosen rarity with rolled affixes from the loot stream and pays its
## parts (plan: Craft). Returns the item, or an empty dictionary (and changes nothing) when blocked.
func craft(base_id: StringName, rarity: int) -> Dictionary:
	if craft_block_reason(base_id, rarity) != "":
		return {}
	var cost := craft_cost(rarity)
	Crafting.pay(data["parts"], cost)
	var item := Loot.make_item(Items.get_attachment(base_id), rarity, loot_rng)
	_store_loot_state()
	data["records"]["crafted"] = int(data["records"]["crafted"]) + 1
	PlaytestLog.event("craft", {"base": String(base_id), "rarity": rarity, "cost": Crafting.describe_cost(cost)})
	add_item(item, "craft")
	return item


## Why affix `index` of the item cannot be rerolled now, or "".
func reroll_block_reason(uid: int, index: int) -> String:
	var found := locate(uid)
	if found.is_empty():
		return "Select an item"
	var item: Dictionary = found["item"]
	if index < 0 or index >= item.get("affixes", []).size():
		return "No such affix"
	var cost := reroll_cost(item)
	if not Crafting.can_afford(data["parts"], cost):
		return "Needs " + Crafting.describe_cost(cost)
	return ""


## Rerolls one affix of an item wherever it is (inventory, tray or fitted), keeping the others, and
## pays the item's rising reroll price (plan: Reroll). False when blocked.
func reroll_affix(uid: int, index: int) -> bool:
	if reroll_block_reason(uid, index) != "":
		return false
	var item: Dictionary = locate(uid)["item"]
	var cost := reroll_cost(item)
	var before := String(item["affixes"][index]["id"])
	if not Crafting.reroll(item, index, loot_rng):
		return false
	_store_loot_state()
	Crafting.pay(data["parts"], cost)
	data["records"]["rerolled"] = int(data["records"]["rerolled"]) + 1
	PlaytestLog.event("reroll", {"base": item.get("base", ""), "from": before, "to": item["affixes"][index]["id"],
		"cost": Crafting.describe_cost(cost)})
	inventory_changed.emit()
	return true


## The highest mark refining can reach right now: III until the Sentinel falls, then V.
func mark_cap() -> int:
	return Items.MAX_MARK if is_wave_cleared(HIGH_MARK_WAVE) else LOW_MARK_CAP


## Why the item cannot be refined now, or "".
func refine_block_reason(uid: int) -> String:
	var found := locate(uid)
	if found.is_empty():
		return "Select an item"
	var mark := int(found["item"].get("mark", Items.MIN_MARK))
	if mark >= Items.MAX_MARK:
		return "Already mark V"
	if mark >= mark_cap():
		return "Marks IV and V open when the Sentinel falls (wave 15)"
	var cost := Crafting.refine_cost(mark + 1)
	var parts := Crafting.discounted(cost["parts"], craft_discount())
	if credits < int(cost["credits"]):
		return "Needs %d credits" % int(cost["credits"])
	if not parts.is_empty() and not Crafting.can_afford(data["parts"], parts):
		return "Needs " + Crafting.describe_cost(parts)
	return ""


## Raises an item's mark by one for credits plus parts (plan: Refine). Works on fitted items too.
func refine(uid: int) -> bool:
	if refine_block_reason(uid) != "":
		return false
	var item: Dictionary = locate(uid)["item"]
	var target := int(item.get("mark", Items.MIN_MARK)) + 1
	var cost := Crafting.refine_cost(target)
	var parts := Crafting.discounted(cost["parts"], craft_discount())
	data["credits"] = credits - int(cost["credits"])
	Crafting.pay(data["parts"], parts)
	item["mark"] = target
	data["records"]["refined"] = int(data["records"]["refined"]) + 1
	PlaytestLog.event("refine", {"base": item.get("base", ""), "mark": target, "credits": int(cost["credits"])})
	credits_changed.emit(credits)
	inventory_changed.emit()
	return true


## The two items a fuse of `uid` would consume: unlocked, unfitted items of the same slot and
## rarity, lowest mark first, then oldest. Fewer than two means it cannot fuse.
func fuse_partners(uid: int) -> Array:
	var found := locate(uid)
	if found.is_empty():
		return []
	var item: Dictionary = found["item"]
	var slot := Items.slot_of(item)
	var candidates := []
	for list_name in ["inventory", "overflow"]:
		for other in data[list_name]:
			if int(other.get("uid", -1)) == uid or bool(other.get("locked", false)):
				continue
			if Items.slot_of(other) == slot and int(other.get("rarity", 0)) == int(item.get("rarity", 0)):
				candidates.append(other)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("mark", 1)) != int(b.get("mark", 1)):
			return int(a.get("mark", 1)) < int(b.get("mark", 1))
		return int(a.get("uid", 0)) < int(b.get("uid", 0)))
	return candidates.slice(0, 2)


func fuse_block_reason(uid: int) -> String:
	var found := locate(uid)
	if found.is_empty():
		return "Select an item"
	var rarity := int(found["item"].get("rarity", 0))
	if not Crafting.is_fusable_rarity(rarity):
		return "Only Commons, Uncommons and Rares fuse"
	if fuse_partners(uid).size() < 2:
		var slot := Items.get_slot(Items.slot_of(found["item"]))
		return "Needs two more unlocked %s %s items" % [Items.RARITY_NAMES[rarity], slot.display_name if slot else ""]
	var cost := Crafting.discounted(Crafting.fuse_cost(rarity), craft_discount())
	if not Crafting.can_afford(data["parts"], cost):
		return "Needs " + Crafting.describe_cost(cost)
	return ""


## Three items of one rarity and slot become one of the next rarity (plan: Fuse): the selected
## item keeps its base, mark and place, rolls fresh affixes at the new rarity, and its two
## partners are consumed. Returns the item, or {} when blocked.
func fuse(uid: int) -> Dictionary:
	if fuse_block_reason(uid) != "":
		return {}
	var item: Dictionary = locate(uid)["item"]
	var rarity := int(item.get("rarity", 0))
	for partner in fuse_partners(uid):
		var where := locate(int(partner["uid"]))
		where["list"].remove_at(where["index"])
	Crafting.pay(data["parts"], Crafting.discounted(Crafting.fuse_cost(rarity), craft_discount()))
	var fresh := Loot.make_item(Items.get_attachment(item["base"]), rarity + 1, loot_rng)
	_store_loot_state()
	item["rarity"] = rarity + 1
	item["affixes"] = fresh["affixes"]
	item["rerolls"] = 0
	data["records"]["fused"] = int(data["records"]["fused"]) + 1
	PlaytestLog.event("fuse", {"base": item.get("base", ""), "rarity": rarity + 1})
	inventory_changed.emit()
	return item


func transmute_block_reason(uid: int) -> String:
	var found := locate(uid)
	if found.is_empty():
		return "Select an item"
	var item: Dictionary = found["item"]
	var base := Items.get_attachment(item.get("base", ""))
	if int(item.get("rarity", 0)) != Items.Rarity.EPIC:
		return "Transmute turns an Epic into its Legendary"
	if base == null or not base.has_legendary():
		return "%s has no Legendary" % (base.display_name if base else "This base")
	if not Crafting.can_afford(data["parts"], Crafting.TRANSMUTE_COST):
		return "Needs " + Crafting.describe_cost(Crafting.TRANSMUTE_COST)
	return ""


## A Legendary core plus an Epic becomes that base's Legendary unique, affixes and mark kept
## (plan: Transmute).
func transmute(uid: int) -> bool:
	if transmute_block_reason(uid) != "":
		return false
	var item: Dictionary = locate(uid)["item"]
	Crafting.pay(data["parts"], Crafting.TRANSMUTE_COST)
	item["rarity"] = Items.Rarity.LEGENDARY
	data["records"]["transmuted"] = int(data["records"]["transmuted"]) + 1
	PlaytestLog.event("transmute", {"base": item.get("base", "")})
	inventory_changed.emit()
	return true


func _add_parts(amounts: Dictionary) -> void:
	for part in amounts:
		if data["parts"].has(part):
			data["parts"][part] = int(data["parts"][part]) + int(amounts[part])


# ------------------------------------------------------------------ loot

## Rolls one kill's drop from the seeded loot stream. Empty when nothing drops.
func roll_kill_drop(definition: EnemyDefinition, is_replay: bool) -> Dictionary:
	var luck := float(player_effects().get("loot_luck", 0.0))
	var item := Loot.roll_kill_drop(definition, droppable_bases(), loot_rng, is_replay, luck, legendary_drop_bases())
	_store_loot_state()
	if not item.is_empty():
		data["records"]["drops"] = int(data["records"]["drops"]) + 1
	return item


## Makes an item of a random droppable base (optionally of one slot) at a rarity and takes it in.
## Empty when no base can drop yet.
func grant_item(rarity: int, slot: StringName = &"", source := "grant") -> Dictionary:
	var bases := droppable_bases(slot)
	if bases.is_empty():
		return {}
	var item := Loot.make_item(Loot.pick_base(bases, loot_rng), rarity, loot_rng)
	_store_loot_state()
	data["records"]["drops"] = int(data["records"]["drops"]) + 1
	add_item(item, source)
	return item


## The bases a boss's Legendary can be: those with a unique whose slot and gate are open.
func legendary_drop_bases() -> Array[AttachmentDefinition]:
	var result: Array[AttachmentDefinition] = []
	for base in Items.legendary_bases():
		if is_base_unlocked(base):
			result.append(base)
	return result


func _store_loot_state() -> void:
	data["loot_state"] = str(loot_rng.state)


func _restore_loot_state() -> void:
	var state := String(data.get("loot_state", ""))
	if state.is_empty() or not state.is_valid_int():
		loot_rng.seed = int(data["seed"])
	else:
		loot_rng.state = state.to_int()


# ------------------------------------------------------------------ firing range

func range_state() -> Dictionary:
	return data["range"]


func set_range_slot(slot_id: StringName) -> void:
	if Items.SLOT_IDS.has(slot_id):
		data["range"]["chosen_slot"] = String(slot_id)


## Records a gallery time. Returns {"best": bool, "reward": item or {}}: the first run under par
## grants a guaranteed Uncommon of the chosen slot (plan: Firing Range).
func record_range_time(seconds: float, par: float) -> Dictionary:
	var result := {"best": false, "reward": {}}
	var best := float(data["range"]["best_time"])
	if best <= 0.0 or seconds < best:
		data["range"]["best_time"] = seconds
		result["best"] = true
	if seconds <= par and not bool(data["range"]["par_rewarded"]):
		var reward := grant_item(Items.Rarity.UNCOMMON, StringName(String(data["range"]["chosen_slot"])), "range_par")
		if not reward.is_empty():
			data["range"]["par_rewarded"] = true
			result["reward"] = reward
	PlaytestLog.event("range_time", {"seconds": "%.2f" % seconds, "par": par, "best": result["best"]})
	progress_changed.emit()
	return result


# ------------------------------------------------------------------ scrapyard

func scrapyard_state() -> Dictionary:
	return data["areas"]["scrapyard"]


## What extracting with `cores` scrap cores pays in parts (plan: crafting parts in bulk).
static func scrapyard_parts(cores: int) -> Dictionary:
	var parts := {}
	if cores <= 0:
		return parts
	parts["scrap"] = cores * SCRAP_PER_CORE
	if cores / CORES_PER_ALLOY > 0:
		parts["alloy"] = cores / CORES_PER_ALLOY
	if cores / CORES_PER_CIRCUIT > 0:
		parts["circuits"] = cores / CORES_PER_CIRCUIT
	return parts


## Counts a run that started (for the playtest log and the bench).
func record_scrapyard_run() -> void:
	data["areas"]["scrapyard"]["runs"] = int(data["areas"]["scrapyard"]["runs"]) + 1


## A successful extraction: the carried cores become parts, a Rare is granted (every extraction),
## and the first one sets the story flag. Returns {"parts", "reward", "first"}.
func record_scrapyard_extraction(cores: int, seconds: float) -> Dictionary:
	var state: Dictionary = data["areas"]["scrapyard"]
	var first := int(state["extractions"]) == 0
	state["extractions"] = int(state["extractions"]) + 1
	state["best_cores"] = maxi(int(state["best_cores"]), cores)
	var parts := scrapyard_parts(cores)
	_add_parts(parts)
	var reward := grant_item(Items.Rarity.RARE, &"", "scrapyard_extraction")
	var extractions := int(state["extractions"])
	for log_id in ["log_scrapyard_1", "log_scrapyard_3", "log_scrapyard_6"]:
		if extractions >= int(log_id.get_slice("_", 2)):
			fire_story(log_id)
	PlaytestLog.event("scrapyard_extracted", {"cores": cores, "seconds": "%.1f" % seconds, "first": first})
	inventory_changed.emit()
	progress_changed.emit()
	return {"parts": parts, "reward": reward, "first": first}


# ------------------------------------------------------------------ foundry

## Cores paid by every Foundry clear (Epic parts: the heat room's role is the expensive recipes).
const FOUNDRY_CORES := 2
## Cores paid by the Signal Tower's top floor; the Legendary core is extra, once per tier.
const TOWER_TOP_CORES := 2
## The Signal Tower floor whose first clear opens the Charge receiver.
const TOWER_CHARGE_FLOOR := 5


func foundry_state() -> Dictionary:
	return data["areas"]["foundry"]


## One attempt per intermission (plan): the Foundry is spent from entry until a main wave starts.
func is_foundry_spent() -> bool:
	return int(data["areas"]["foundry"]["spent"]) != 0


func record_foundry_run() -> void:
	var state: Dictionary = data["areas"]["foundry"]
	state["runs"] = int(state["runs"]) + 1
	state["spent"] = 1
	progress_changed.emit()


## A main wave started: the Foundry can be attempted again at the next intermission.
func refresh_intermission() -> void:
	data["areas"]["foundry"]["spent"] = 0


## A cleared heat room: cores every time, a Rare, the Burst receiver (Rare) and its unlock on the
## first clear, an Epic on a run without damage, and the logs. Returns
## {"parts", "rewards": [items], "first", "perfect"}.
func record_foundry_clear(perfect: bool, seconds: float) -> Dictionary:
	var state: Dictionary = data["areas"]["foundry"]
	var first := int(state["clears"]) == 0
	state["clears"] = int(state["clears"]) + 1
	var parts := {"cores": FOUNDRY_CORES}
	_add_parts(parts)
	var rewards: Array = []
	if first:
		add_unlock("foundry")
		rewards.append(_grant_base(&"burst", Items.Rarity.RARE, "foundry_first_clear"))
	else:
		rewards.append(grant_item(Items.Rarity.RARE, &"", "foundry_clear"))
	if perfect:
		state["perfect"] = int(state["perfect"]) + 1
		rewards.append(grant_item(Items.Rarity.EPIC, &"", "foundry_perfect"))
		fire_story("log_foundry_perfect")
	fire_story("log_foundry_1")
	if int(state["clears"]) >= 3:
		fire_story("log_foundry_3")
	rewards = rewards.filter(func(item: Dictionary) -> bool: return not item.is_empty())
	PlaytestLog.event("foundry_cleared", {"perfect": perfect, "seconds": "%.1f" % seconds, "first": first})
	inventory_changed.emit()
	progress_changed.emit()
	return {"parts": parts, "rewards": rewards, "first": first, "perfect": perfect}


## Makes an item of one base at a rarity with rolled affixes and takes it in.
func _grant_base(base_id: StringName, rarity: int, source: String) -> Dictionary:
	var base := Items.get_attachment(base_id)
	if base == null:
		return {}
	var item := Loot.make_item(base, rarity, loot_rng)
	_store_loot_state()
	data["records"]["drops"] = int(data["records"]["drops"]) + 1
	add_item(item, source)
	return item


# ------------------------------------------------------------------ signal tower

func tower_state() -> Dictionary:
	return data["areas"]["signal_tower"]


func record_tower_run() -> void:
	var state: Dictionary = data["areas"]["signal_tower"]
	state["runs"] = int(state["runs"]) + 1


## A tower floor cleared: the best floor, the Charge receiver at TOWER_CHARGE_FLOOR the first time,
## the logs on floors 3, 6 and 9. Returns the items it granted (empty for most floors).
func record_tower_floor(floor_number: int) -> Array:
	var state: Dictionary = data["areas"]["signal_tower"]
	state["best_floor"] = maxi(int(state["best_floor"]), floor_number)
	var rewards: Array = []
	if floor_number >= TOWER_CHARGE_FLOOR and add_unlock("signal_tower"):
		rewards.append(_grant_base(&"charge", Items.Rarity.RARE, "tower_charge"))
	if floor_number in [3, 6, 9]:
		fire_story("log_tower_%d" % floor_number)
	PlaytestLog.event("tower_floor", {"floor": floor_number})
	progress_changed.emit()
	return rewards.filter(func(item: Dictionary) -> bool: return not item.is_empty())


## The top floor: an Epic and cores every time, the Overflow magazine (Rare) the first time, a
## Legendary core once per Reforge tier, and the top log. Returns
## {"parts", "rewards": [items], "first", "legendary_core"}.
func record_tower_top(seconds: float) -> Dictionary:
	var state: Dictionary = data["areas"]["signal_tower"]
	var first := int(state["clears"]) == 0
	state["clears"] = int(state["clears"]) + 1
	var parts := {"cores": TOWER_TOP_CORES}
	var legendary_core := int(state["core_tier"]) <= tier
	if legendary_core:
		state["core_tier"] = tier + 1
		parts["legendary_cores"] = 1
	_add_parts(parts)
	var rewards: Array = [grant_item(Items.Rarity.EPIC, &"", "tower_top")]
	if add_unlock("signal_tower_top"):
		rewards.append(_grant_base(&"overflow", Items.Rarity.RARE, "tower_overflow"))
	fire_story("log_tower_top")
	PlaytestLog.event("tower_top", {"seconds": "%.1f" % seconds, "first": first, "legendary_core": legendary_core})
	inventory_changed.emit()
	progress_changed.emit()
	return {"parts": parts, "rewards": rewards.filter(func(item: Dictionary) -> bool: return not item.is_empty()),
		"first": first, "legendary_core": legendary_core}


# ------------------------------------------------------------------ story

## Fires a story trigger once per save: records it and queues it for the bench's Story tab.
## Returns its lines the first time, empty after that or when the trigger has none.
func fire_story(trigger: String) -> Array:
	if not Story.has(trigger) or data["story_flags"].has(trigger):
		return []
	data["story_flags"].append(trigger)
	data["story_queue"].append(trigger)
	PlaytestLog.event("story", {"trigger": trigger})
	return Story.lines_for(trigger)


func has_seen_story(trigger: String) -> bool:
	return data["story_flags"].has(trigger)


## Triggers fired so far, oldest first (the bench's Story tab).
func story_seen() -> Array:
	return data["story_flags"].filter(func(t: String) -> bool: return Story.has(t))


## Triggers fired since the bench last showed them; reading empties the queue.
func take_story_queue() -> Array:
	var queued: Array = data["story_queue"].duplicate()
	data["story_queue"].clear()
	return queued


# ------------------------------------------------------------------ save

func save() -> bool:
	return SaveFile.save(data)


func load_from_disk() -> void:
	loaded_from_disk = SaveFile.exists()
	data = SaveFile.load_or_fresh()
	_restore_loot_state()
	credits_changed.emit(credits)
	inventory_changed.emit()
	progress_changed.emit()


## Wipes everything and deletes the save. Used by the bench's reset button and by tests.
func reset() -> void:
	data = SaveFile.fresh()
	loaded_from_disk = false
	SaveFile.delete()
	_restore_loot_state()
	credits_changed.emit(credits)
	inventory_changed.emit()
	progress_changed.emit()
