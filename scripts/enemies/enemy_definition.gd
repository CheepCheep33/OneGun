class_name EnemyDefinition
extends Resource
## Tunable stats for one enemy type. Tuning values, not final balance.

@export var display_name := "Enemy"
@export var max_health := 40.0
@export var move_speed := 3.6
@export var attack_damage := 12.0
## Horizontal distance at which the enemy stops and starts its attack.
@export var attack_range := 1.7
## Telegraph time before the hit lands. The attack misses if the player has backed off by then.
@export var attack_windup := 0.45
@export var attack_cooldown := 0.9
## Credits paid the moment this enemy dies, before wave-tier scaling.
@export var credit_reward := 5
## Death burst and hit-flash tint, so enemy types stay readable.
@export var color := Color(0.85, 0.25, 0.2)
