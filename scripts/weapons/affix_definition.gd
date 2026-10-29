class_name AffixDefinition
extends Resource
## One rollable affix. An item stores {id, roll} with roll in [0, 1]; the value is the roll
## lerped across the range for the item's rarity. Authored in data/affixes/. Tuning values.

@export var id: StringName = &"sharp"
@export var display_name := "Sharp"
## Stat key this affix changes (see WeaponStats.STAT_KEYS, or an extra key).
@export var stat: StringName = &"damage"
## True when the value is a percentage (0.1 = +10 percent); false when it is a flat amount.
@export var is_percent := true
## Lowest and highest value per rarity, indexed by Items.Rarity (Common has no affixes but keeps a row).
@export var min_by_rarity: Array[float] = [0.0, 0.04, 0.06, 0.08, 0.10]
@export var max_by_rarity: Array[float] = [0.0, 0.08, 0.12, 0.16, 0.20]


func value_for(rarity: int, roll: float) -> float:
	var index := clampi(rarity, 0, mini(min_by_rarity.size(), max_by_rarity.size()) - 1)
	if index < 0:
		return 0.0
	return lerpf(min_by_rarity[index], max_by_rarity[index], clampf(roll, 0.0, 1.0))


func modifier_for(rarity: int, roll: float) -> StatModifier:
	var value := value_for(rarity, roll)
	return StatModifier.make(stat, 0.0 if is_percent else value, value if is_percent else 0.0)
