class_name Items
extends RefCounted
## The item data model. An item instance is a small Dictionary so it saves as plain JSON:
##   { "base": "long_barrel", "rarity": 2, "affixes": [{"id": "sharp", "roll": 0.73}], "mark": 1,
##     "locked": false, "uid": 17, "rerolls": 0 }
## `rerolls` counts the crafting table's affix rerolls on this item, which raise its next price.
## Base and affix ids resolve to resources in data/attachments/ and data/affixes/. The base
## decides what the attachment does; affixes decide how well (plan: Loot rarity).

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS := [
	Color(0.75, 0.75, 0.75), Color(0.45, 0.85, 0.45), Color(0.4, 0.6, 1.0),
	Color(0.75, 0.45, 0.95), Color(1.0, 0.6, 0.2),
]
## Affix slots per rarity. Legendaries add a hand-authored unique effect on top.
const AFFIX_COUNT := [0, 1, 2, 3, 3]
const MAX_MARK := 5
const MIN_MARK := 1
## Every gunsmith slot, in bench order. The Relic slot stays hidden until Reforge 3.
const SLOT_IDS: Array[StringName] = [
	&"receiver", &"barrel", &"muzzle", &"magazine", &"ammo", &"optic", &"underbarrel",
]
const SLOT_GLYPHS := {
	"receiver": "RC", "barrel": "BA", "muzzle": "MZ", "magazine": "MG", "ammo": "AM", "optic": "OP",
	"underbarrel": "UB",
}
## Every authored base, in catalogue order. Listed explicitly so exported builds never have to
## scan a directory.
const BASE_IDS: Array[StringName] = [
	&"semi_auto", &"automatic", &"burst",
	&"standard_barrel", &"long_barrel", &"penetrator_barrel",
	&"standard_magazine", &"extended_magazine", &"fast_magazine",
	&"open_muzzle", &"splitter", &"overpressure",
	&"standard_rounds", &"explosive_rounds", &"ricochet_rounds",
	&"charge", &"short_barrel", &"compensator", &"drum", &"overflow",
	&"incendiary", &"cryo", &"shock", &"hollow_point",
	&"iron_sights", &"reflex", &"scanner", &"rangefinder",
	&"no_underbarrel", &"grip", &"laser", &"launcher", &"shield_emitter",
]
const AFFIX_IDS: Array[StringName] = [
	&"sharp", &"rapid", &"deep", &"quick", &"keen", &"brutal", &"piercing", &"thrifty", &"arcing",
	&"lingering", &"precise",
]
## Crafting parts, one per rarity, returned by dismantling and spent at the crafting table
## (plan: Crafting; see Crafting for the recipes).
const PART_IDS: Array[String] = ["scrap", "alloy", "circuits", "cores", "legendary_cores"]
const PART_NAMES := {
	"scrap": "Scrap", "alloy": "Alloy", "circuits": "Circuits", "cores": "Cores", "legendary_cores": "Legendary cores",
}

const ATTACHMENT_DIR := "res://data/attachments/"
const AFFIX_DIR := "res://data/affixes/"
const SLOT_DIR := "res://data/attachments/slots/"

## In-memory definitions take priority over data files, so tests can register their own bases.
static var _attachments: Dictionary = {}
static var _affixes: Dictionary = {}
static var _slots: Array[SlotDefinition] = []
static var _next_uid := 1


static func make(base_id: StringName, rarity := Rarity.COMMON, affixes: Array = [], mark := MIN_MARK) -> Dictionary:
	var item := {
		"base": String(base_id),
		"rarity": clampi(rarity, Rarity.COMMON, Rarity.LEGENDARY),
		"affixes": [],
		"mark": clampi(mark, MIN_MARK, MAX_MARK),
		"locked": false,
		"uid": _next_uid,
		"rerolls": 0,
	}
	_next_uid += 1
	for affix in affixes:
		if affix is Dictionary and affix.has("id"):
			item["affixes"].append({"id": String(affix["id"]), "roll": clampf(float(affix.get("roll", 0.5)), 0.0, 1.0)})
	return item


## True when the dictionary is a well-formed item whose base and affixes all resolve.
## Unknown ids are reported through push_warning so a save with retired items loads without crashing.
static func is_valid(item: Variant) -> bool:
	if not (item is Dictionary):
		return false
	if not (item.get("base") is String) or get_attachment(item["base"]) == null:
		push_warning("Dropping item with unknown base '%s'." % str(item.get("base")))
		return false
	var rarity: Variant = item.get("rarity", -1)
	if not (rarity is int or rarity is float) or int(rarity) < Rarity.COMMON or int(rarity) > Rarity.LEGENDARY:
		return false
	var mark: Variant = item.get("mark", 0)
	if not (mark is int or mark is float) or int(mark) < MIN_MARK or int(mark) > MAX_MARK:
		return false
	if not (item.get("affixes", []) is Array):
		return false
	for affix in item["affixes"]:
		if not (affix is Dictionary) or get_affix(str(affix.get("id", ""))) == null:
			push_warning("Dropping item '%s' with unknown affix '%s'." % [item["base"], str(affix.get("id", "") if affix is Dictionary else affix)])
			return false
	return true


## Normalises a loaded item: int types, clamped ranges, a fresh uid when missing.
static func normalize(item: Dictionary) -> Dictionary:
	var affixes: Array = []
	for affix in item.get("affixes", []):
		affixes.append({"id": String(affix["id"]), "roll": clampf(float(affix.get("roll", 0.5)), 0.0, 1.0)})
	var uid := int(item.get("uid", 0))
	if uid <= 0:
		uid = _next_uid
	_next_uid = maxi(_next_uid, uid + 1)
	return {
		"base": String(item["base"]),
		"rarity": clampi(int(item["rarity"]), Rarity.COMMON, Rarity.LEGENDARY),
		"affixes": affixes,
		"mark": clampi(int(item.get("mark", MIN_MARK)), MIN_MARK, MAX_MARK),
		"locked": bool(item.get("locked", false)),
		"uid": uid,
		"rerolls": maxi(int(item.get("rerolls", 0)), 0),
	}


## Every numeric modifier an item contributes: the base's mark-scaled modifiers plus its affixes.
static func modifiers_of(item: Dictionary) -> Array[StatModifier]:
	var result: Array[StatModifier] = []
	var base := get_attachment(item["base"])
	if base == null:
		return result
	result.append_array(base.modifiers_at_mark(int(item.get("mark", MIN_MARK)), is_legendary(item)))
	for affix in item.get("affixes", []):
		var definition := get_affix(affix["id"])
		if definition:
			result.append(definition.modifier_for(int(item.get("rarity", 0)), float(affix.get("roll", 0.5))))
	return result


static func display_name(item: Dictionary) -> String:
	var base := get_attachment(item["base"])
	var name := base.display_name if base else String(item["base"])
	if base and is_legendary(item):
		name = "%s (%s)" % [base.legendary_name, base.display_name]
	return "%s %s" % [name, mark_numeral(int(item.get("mark", MIN_MARK)))]


## True for a Legendary of a base that has a unique: its unique's modifiers and behaviours apply.
static func is_legendary(item: Dictionary) -> bool:
	if int(item.get("rarity", 0)) != Rarity.LEGENDARY:
		return false
	var base := get_attachment(item.get("base", ""))
	return base != null and base.has_legendary()


## The bases that have a Legendary unique, in catalogue order (the Core Guardian's first-kill drop
## and transmute pick from these).
static func legendary_bases() -> Array[AttachmentDefinition]:
	var result: Array[AttachmentDefinition] = []
	for definition in all_attachments():
		if definition.has_legendary():
			result.append(definition)
	return result


static func mark_numeral(mark: int) -> String:
	return ["I", "II", "III", "IV", "V"][clampi(mark, MIN_MARK, MAX_MARK) - 1]


static func rarity_name(item: Dictionary) -> String:
	return RARITY_NAMES[clampi(int(item.get("rarity", 0)), 0, RARITY_NAMES.size() - 1)]


static func rarity_color(item: Dictionary) -> Color:
	return RARITY_COLORS[clampi(int(item.get("rarity", 0)), 0, RARITY_COLORS.size() - 1)]


static func slot_of(item: Dictionary) -> StringName:
	var base := get_attachment(item.get("base", ""))
	return base.slot if base else &""


## "Sharp: +12% damage", one line per affix, in the item's order.
static func affix_lines(item: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for affix in item.get("affixes", []):
		var definition := get_affix(affix["id"])
		if definition:
			var modifier := definition.modifier_for(int(item.get("rarity", 0)), float(affix.get("roll", 0.5)))
			lines.append("%s: %s" % [definition.display_name, describe_modifier(modifier)])
	return lines


## Human-readable form of one modifier, with the stat's own units.
static func describe_modifier(modifier: StatModifier) -> String:
	var key := String(modifier.stat)
	var percent_text := "%+d%%" % roundi(modifier.percent * 100.0)
	match key:
		"damage":
			return "%s damage" % (percent_text if modifier.percent != 0.0 else "%+.0f" % modifier.flat)
		"fire_rate":
			return "%s fire rate" % (percent_text if modifier.percent != 0.0 else "%+.1f/s" % modifier.flat)
		"magazine":
			return "%s rounds" % (percent_text if modifier.percent != 0.0 else "%+.0f" % modifier.flat)
		"reload_speed":
			return "%s reload speed" % percent_text
		"crit_chance":
			return "%+d%% crit chance" % roundi((modifier.percent + modifier.flat) * 100.0)
		"crit_damage":
			return "%s crit damage" % percent_text
		"range":
			return "%s range" % (percent_text if modifier.percent != 0.0 else "%+.0f m" % modifier.flat)
		"recoil":
			return "%s recoil" % percent_text
		WeaponStats.EXTRA_PIERCE_KEY:
			return "%+.0f pierce" % modifier.flat
		WeaponStats.AMMO_REFUND_KEY:
			return "%d%% chance a kill refunds the round" % roundi(modifier.percent * 100.0)
		WeaponStats.CHAIN_ON_CRIT_KEY:
			return "%d%% chance a crit arcs to a nearby enemy" % roundi(modifier.percent * 100.0)
		"status_duration":
			return "%s status duration" % percent_text
		"weak_point_damage":
			return "%s weak-point damage" % percent_text
	return "%s %s" % [percent_text if modifier.percent != 0.0 else "%+.2f" % modifier.flat, key.replace("_", " ")]


## Bench order: by slot, then rarity high to low, then mark, then name.
static func sort_items(items: Array) -> Array:
	var sorted := items.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var slot_a := SLOT_IDS.find(slot_of(a))
		var slot_b := SLOT_IDS.find(slot_of(b))
		if slot_a != slot_b:
			return slot_a < slot_b
		if int(a.get("rarity", 0)) != int(b.get("rarity", 0)):
			return int(a.get("rarity", 0)) > int(b.get("rarity", 0))
		if int(a.get("mark", 1)) != int(b.get("mark", 1)):
			return int(a.get("mark", 1)) > int(b.get("mark", 1))
		if a.get("base", "") != b.get("base", ""):
			return String(a.get("base", "")) < String(b.get("base", ""))
		return int(a.get("uid", 0)) < int(b.get("uid", 0)))
	return sorted


static func find_by_uid(items: Array, uid: int) -> int:
	for i in items.size():
		if items[i] is Dictionary and int(items[i].get("uid", -1)) == uid:
			return i
	return -1


## Parts returned when an item of this rarity is dismantled: one of its own rarity and one of
## the rarity below. Tuning values.
static func parts_for_rarity(rarity: int) -> Dictionary:
	var index := clampi(rarity, 0, PART_IDS.size() - 1)
	var parts := {PART_IDS[index]: 1}
	if index > 0:
		parts[PART_IDS[index - 1]] = 1
	return parts


static func slot_glyph(slot: StringName) -> String:
	return SLOT_GLYPHS.get(String(slot), "??")


# ------------------------------------------------------------------ definitions

static func register_attachment(definition: AttachmentDefinition) -> void:
	_attachments[String(definition.id)] = definition


static func register_affix(definition: AffixDefinition) -> void:
	_affixes[String(definition.id)] = definition


static func unregister(id: StringName) -> void:
	_attachments.erase(String(id))
	_affixes.erase(String(id))


static func get_attachment(id: StringName) -> AttachmentDefinition:
	return _load_definition(_attachments, ATTACHMENT_DIR, id) as AttachmentDefinition


static func get_affix(id: StringName) -> AffixDefinition:
	return _load_definition(_affixes, AFFIX_DIR, id) as AffixDefinition


## Every authored base in catalogue order, plus any registered at runtime (tests).
static func all_attachments() -> Array[AttachmentDefinition]:
	var result: Array[AttachmentDefinition] = []
	var seen := {}
	for id in BASE_IDS:
		var definition := get_attachment(id)
		if definition:
			result.append(definition)
			seen[String(id)] = true
	for key in _attachments:
		if not seen.has(key) and _attachments[key] is AttachmentDefinition:
			result.append(_attachments[key])
	return result


static func bases_for_slot(slot: StringName) -> Array[AttachmentDefinition]:
	var result: Array[AttachmentDefinition] = []
	for definition in all_attachments():
		if definition.slot == slot:
			result.append(definition)
	return result


static func default_for_slot(slot: StringName) -> AttachmentDefinition:
	for definition in bases_for_slot(slot):
		if definition.is_default:
			return definition
	return null


## True when at least one non-default base exists for the slot, so the slot can hold loot.
static func slot_has_bases(slot: StringName) -> bool:
	for definition in bases_for_slot(slot):
		if not definition.is_default:
			return true
	return false


static func all_affixes() -> Array[AffixDefinition]:
	var result: Array[AffixDefinition] = []
	var seen := {}
	for id in AFFIX_IDS:
		var definition := get_affix(id)
		if definition:
			result.append(definition)
			seen[String(id)] = true
	for key in _affixes:
		if not seen.has(key) and _affixes[key] is AffixDefinition:
			result.append(_affixes[key])
	return result


## The affixes loot can roll right now.
static func drop_affixes() -> Array[AffixDefinition]:
	var result: Array[AffixDefinition] = []
	for definition in all_affixes():
		if definition.drops:
			result.append(definition)
	return result


static func get_slots() -> Array[SlotDefinition]:
	if _slots.is_empty():
		for slot_id in SLOT_IDS:
			var path := SLOT_DIR + String(slot_id) + ".tres"
			var slot := load(path) as SlotDefinition if ResourceLoader.exists(path) else null
			if slot:
				_slots.append(slot)
		_slots.sort_custom(func(a: SlotDefinition, b: SlotDefinition) -> bool: return a.sort_order < b.sort_order)
	return _slots


static func get_slot(id: StringName) -> SlotDefinition:
	for slot in get_slots():
		if slot.id == id:
			return slot
	return null


static func _load_definition(cache: Dictionary, directory: String, id: StringName) -> Resource:
	var key := String(id)
	if key.is_empty() or not key.is_valid_filename():
		return null
	if cache.has(key):
		return cache[key]
	var path := directory + key + ".tres"
	var definition: Resource = load(path) if ResourceLoader.exists(path) else null
	cache[key] = definition
	return definition
