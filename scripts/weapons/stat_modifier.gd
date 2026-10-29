class_name StatModifier
extends Resource
## One numeric change to a weapon stat, carried by core tuning, attachments, affixes, skills and
## Forge nodes alike. WeaponStats.build() sums flats and percents per stat, then multiplies once.

## A key from WeaponStats.STAT_KEYS, or any other key: unknown keys land in WeaponStats.extra so
## later systems (status duration, weak-point damage, pierce...) can read them without a rewrite.
@export var stat: StringName = &"damage"
## Added to the base value before percentages apply.
@export var flat := 0.0
## Fraction added to the stat's percentage sum: 0.1 means +10 percent.
@export var percent := 0.0


static func make(stat_key: StringName, flat_value := 0.0, percent_value := 0.0) -> StatModifier:
	var modifier := StatModifier.new()
	modifier.stat = stat_key
	modifier.flat = flat_value
	modifier.percent = percent_value
	return modifier
