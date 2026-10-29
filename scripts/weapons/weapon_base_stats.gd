class_name WeaponBaseStats
extends Resource
## Authored starting values and hard limits for a weapon.
## Never modified at runtime: effective values always come from WeaponStats.build().
## All numbers are tuning values, not final balance.

@export var damage := 10.0
## Shots per second.
@export var fire_rate := 4.0
@export var magazine_size := 10
## Seconds from starting a reload to a full magazine.
@export var reload_time := 1.4
## Beyond this distance a shot lands nothing.
@export var max_range := 150.0
## Damage is full up to falloff_start, then falls linearly to falloff_floor (a fraction) at
## falloff_end. The `range` stat scales both distances, so a Long barrel pushes falloff away.
@export var falloff_start := 20.0
@export var falloff_end := 45.0
@export var falloff_floor := 0.6
## Starting critical hit chance (0 to 1). Core tuning adds to it once the basic loop works.
@export var crit_chance := 0.0
## Degrees the camera kicks up per shot (scaled by the player's camera recoil setting).
@export var recoil_kick_degrees := 1.2

@export_group("Limits")
@export var max_fire_rate := 15.0
@export var min_reload_time := 0.3
