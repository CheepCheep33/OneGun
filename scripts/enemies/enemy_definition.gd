class_name EnemyDefinition
extends Resource
## Tunable stats for one enemy type (data/enemies/). Tuning values, not final balance.

@export var id: StringName = &"chaser"
@export var display_name := "Enemy"
@export var max_health := 40.0
@export var move_speed := 3.6
## Damage of the melee strike, the bolt or the zap, before any boss special attack.
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

@export_group("Role")
## Share of the wave's alive cap this enemy takes (drones count as half).
@export var counts_as := 1.0
## Scales the per-kill drop chances (fragile swarm enemies drop less each).
@export var loot_weight := 1.0
## Bosses get a HUD health bar, drop guaranteed loot straight into the inventory and double the wave bonus.
@export var is_boss := false

@export_group("Movement")
## Flying enemies ignore gravity and hover; their hitbox sits at hover_height.
@export var flying := false
@export var hover_height := 0.0

@export_group("Ranged")
## Ranged enemies keep their distance and fire simulated bolts.
@export var ranged := false
## Where it stops and holds once it can see the player.
@export var preferred_range := 11.0
## Closer than this they back away while facing the player.
@export var retreat_range := 6.0
## Furthest it fires from, with line of sight, while still walking in to its preferred range. Equal
## to preferred_range it only fires once it has arrived.
@export var max_fire_range := 11.0
## Aim error, as the half-angle in degrees of the cone its bolts leave in: this much at
## preferred_range or closer, spread_far_degrees at max_fire_range, growing with distance between.
@export var spread_near_degrees := 0.0
@export var spread_far_degrees := 0.0
@export var projectile_speed := 16.0
@export var projectile_lifetime := 4.0
