class_name SpawnGroup
extends Resource
## One timed group inside a wave: `count` enemies of one type, one every `interval` seconds,
## starting `start_delay` seconds after the wave begins.

@export var enemy_scene: PackedScene
@export var definition: EnemyDefinition
@export var count := 4
@export var interval := 1.5
@export var start_delay := 0.0
