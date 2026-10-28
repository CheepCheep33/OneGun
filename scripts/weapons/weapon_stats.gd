class_name WeaponStats
extends RefCounted
## Effective weapon stats, derived from base values plus purchased upgrade levels.
## Combat and UI previews must both call compute() so they always agree;
## never edit a WeaponStats in place when something is purchased, compute a new one.

var damage: float
var fire_rate: float
var magazine_size: int
var reload_time: float
var max_range: float
var recoil_kick_degrees: float


static func compute(base: WeaponBaseStats, _upgrade_levels: Dictionary = {}) -> WeaponStats:
	# Milestone 2 adds per-level upgrade effects here, before the limits are applied.
	var stats := WeaponStats.new()
	stats.damage = maxf(base.damage, 0.0)
	stats.fire_rate = clampf(base.fire_rate, 0.1, base.max_fire_rate)
	stats.magazine_size = maxi(base.magazine_size, 1)
	stats.reload_time = maxf(base.reload_time, base.min_reload_time)
	stats.max_range = base.max_range
	stats.recoil_kick_degrees = base.recoil_kick_degrees
	return stats


func seconds_between_shots() -> float:
	return 1.0 / fire_rate
