class_name CoreTuningDefinition
extends Resource
## One purchasable core tuning stat (damage, fire rate, magazine, reload...). Authored in
## data/core_tuning/. Core tuning only changes numbers, never behaviour, so it is always safe to buy.
## Prices rise geometrically: cost(level) = base_cost * cost_growth ^ level. Tuning values, not balance.

@export var id: StringName = &"damage"
@export var display_name := "Damage"
@export_multiline var description := ""
## The stat key this tuning changes (see WeaponStats.STAT_KEYS).
@export var stat: StringName = &"damage"
## Added to the stat per level, before percentages.
@export var flat_per_level := 0.0
## Fraction added to the stat's percentage sum per level (0.06 = +6 percent per level).
@export var percent_per_level := 0.0
@export var base_cost := 20
@export var cost_growth := 1.15
## 0 means no level cap; the stat's own limits (fire rate cap, reload floor) still apply.
@export var max_level := 0
## Order in the bench list.
@export var sort_order := 0


func cost_at(level: int) -> int:
	return maxi(1, roundi(base_cost * pow(cost_growth, maxi(level, 0))))


func is_maxed(level: int) -> bool:
	return max_level > 0 and level >= max_level


func modifier_for(level: int) -> StatModifier:
	return StatModifier.make(stat, flat_per_level * level, percent_per_level * level)
