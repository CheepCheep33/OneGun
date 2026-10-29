class_name CoreTuning
extends RefCounted
## Loads the core tuning definitions from data/core_tuning/ once and hands them out in bench order.

const DIR := "res://data/core_tuning/"
const IDS: Array[StringName] = [&"damage", &"fire_rate", &"magazine", &"reload"]

static var _all: Array[CoreTuningDefinition] = []


static func all() -> Array[CoreTuningDefinition]:
	if _all.is_empty():
		for id in IDS:
			var path := DIR + String(id) + ".tres"
			if ResourceLoader.exists(path):
				_all.append(load(path))
		_all.sort_custom(func(a: CoreTuningDefinition, b: CoreTuningDefinition) -> bool:
			return a.sort_order < b.sort_order)
	return _all


static func get_definition(id: StringName) -> CoreTuningDefinition:
	for tuning in all():
		if tuning.id == id:
			return tuning
	return null
