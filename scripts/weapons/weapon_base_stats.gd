class_name WeaponBaseStats
extends Resource
## Authored starting values and hard limits for a weapon.
## Never modified at runtime: effective values always come from WeaponStats.compute().
## All numbers are tuning values, not final balance.

@export var damage := 10.0
## Shots per second.
@export var fire_rate := 4.0
@export var magazine_size := 10
## Seconds from starting a reload to a full magazine.
@export var reload_time := 1.4
@export var max_range := 150.0
## Degrees the camera kicks up per shot (scaled by the player's camera recoil setting).
@export var recoil_kick_degrees := 1.2

@export_group("Limits")
@export var max_fire_rate := 15.0
@export var min_reload_time := 0.3
