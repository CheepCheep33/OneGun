class_name Items
extends RefCounted
## The item data model. An item instance is a small Dictionary so it saves as plain JSON:
##   { "base": "long_barrel", "rarity": 2, "affixes": [{"id": "sharp", "roll": 0.73}], "mark": 1,
##     "locked": false, "uid": 17 }
## Base and affix ids resolve to resources in data/attachments/ and data/affixes/. Milestone 2
## ships the model with tests and no items; Milestone 3 adds the bases, drops and the gunsmith.

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
	}


## Every numeric modifier an item contributes: the base's mark-scaled modifiers plus its affixes.
static func modifiers_of(item: Dictionary) -> Array[StatModifier]:
	var result: Array[StatModifier] = []
	var base := get_attachment(item["base"])
	if base == null:
		return result
	result.append_array(base.modifiers_at_mark(int(item.get("mark", MIN_MARK))))
	for affix in item.get("affixes", []):
		var definition := get_affix(affix["id"])
		if definition:
			result.append(definition.modifier_for(int(item.get("rarity", 0)), float(affix.get("roll", 0.5))))
	return result


static func display_name(item: Dictionary) -> String:
	var base := get_attachment(item["base"])
	var name := base.display_name if base else String(item["base"])
	return "%s %s" % [name, mark_numeral(int(item.get("mark", MIN_MARK)))]


static func mark_numeral(mark: int) -> String:
	return ["I", "II", "III", "IV", "V"][clampi(mark, MIN_MARK, MAX_MARK) - 1]


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


static func get_slots() -> Array[SlotDefinition]:
	if _slots.is_empty():
		for slot_id in SLOT_IDS:
			var path := SLOT_DIR + String(slot_id) + ".tres"
			var slot := load(path) as SlotDefinition if ResourceLoader.exists(path) else null
			if slot:
				_slots.append(slot)
		_slots.sort_custom(func(a: SlotDefinition, b: SlotDefinition) -> bool: return a.sort_order < b.sort_order)
	return _slots


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
