class_name Crafting
extends RefCounted
## The crafting table's recipes (plan: Crafting). Milestone 4 ships craft and reroll; dismantle
## lives in Progression since Milestone 3, and refine, fuse and transmute arrive with Milestone 5.
## Every recipe is known from the start, parts gate them, and nothing fails randomly: a craft always
## returns the chosen base at the chosen rarity, a reroll always replaces the chosen affix. Pure
## functions over the item dictionaries and a RandomNumberGenerator, so the bench, Progression and
## the tests share them. Tuning values, not balance.

## Parts a craft costs, by rarity (Common to Epic). Legendaries are never crafted directly; they
## come from a Legendary core by transmute (Milestone 5). Each recipe costs more than dismantling
## its result returns, so no craft-and-dismantle loop makes parts (tests/cases/crafting_cases.gd).
const CRAFT_COSTS := [
	{"scrap": 3},
	{"scrap": 4, "alloy": 2},
	{"alloy": 5, "circuits": 2},
	{"circuits": 5, "cores": 2},
]
## A reroll costs REROLL_LOWER_PARTS of the part one rarity below the item and REROLL_OWN_PARTS of
## its own rarity's part, both times one plus the rerolls already made on that item (the plan's
## rising cost).
const REROLL_LOWER_PARTS := 2
const REROLL_OWN_PARTS := 1


static func is_craftable_rarity(rarity: int) -> bool:
	return rarity >= 0 and rarity < CRAFT_COSTS.size()


## Parts to craft one item of `rarity`; empty when that rarity cannot be crafted.
static func craft_cost(rarity: int) -> Dictionary:
	return CRAFT_COSTS[rarity].duplicate() if is_craftable_rarity(rarity) else {}


## Parts to reroll one affix of `item`; empty when it has no affix to reroll.
static func reroll_cost(item: Dictionary) -> Dictionary:
	var rarity := clampi(int(item.get("rarity", 0)), 0, Items.PART_IDS.size() - 1)
	if item.get("affixes", []).is_empty() or rarity == 0:
		return {}
	var steps := 1 + maxi(int(item.get("rerolls", 0)), 0)
	return {
		Items.PART_IDS[rarity - 1]: REROLL_LOWER_PARTS * steps,
		Items.PART_IDS[rarity]: REROLL_OWN_PARTS * steps,
	}


static func can_afford(parts: Dictionary, cost: Dictionary) -> bool:
	if cost.is_empty():
		return false
	for part in cost:
		if int(parts.get(part, 0)) < int(cost[part]):
			return false
	return true


## Takes `cost` out of `parts`. Call only after can_afford.
static func pay(parts: Dictionary, cost: Dictionary) -> void:
	for part in cost:
		parts[part] = int(parts.get(part, 0)) - int(cost[part])


## Replaces affix `index` of `item` in place with a fresh affix from the drop pool (never one the
## item already carries elsewhere; the same affix may come back with a new roll) and counts the
## reroll. Returns false when the index is out of range or the pool has nothing to offer.
static func reroll(item: Dictionary, index: int, rng: RandomNumberGenerator) -> bool:
	var affixes: Array = item.get("affixes", [])
	if index < 0 or index >= affixes.size():
		return false
	var others := []
	for i in affixes.size():
		if i != index:
			others.append(String(affixes[i]["id"]))
	var pool: Array[AffixDefinition] = []
	for definition in Items.drop_affixes():
		if not others.has(String(definition.id)):
			pool.append(definition)
	if pool.is_empty():
		return false
	var picked := pool[rng.randi_range(0, pool.size() - 1)]
	affixes[index] = {"id": String(picked.id), "roll": rng.randf()}
	item["rerolls"] = int(item.get("rerolls", 0)) + 1
	return true


## "3 Scrap, 2 Alloy".
static func describe_cost(cost: Dictionary) -> String:
	var names := PackedStringArray()
	for part in Items.PART_IDS:
		if cost.has(part):
			names.append("%d %s" % [int(cost[part]), Items.PART_NAMES[part]])
	return ", ".join(names)


## What dismantling an item of `rarity` returns, in the same units as craft_cost, for the
## conservation check and the bench text.
static func dismantle_value(rarity: int) -> Dictionary:
	return Items.parts_for_rarity(rarity)
