class_name EnemySpawner
extends Node
## Milestone 1 test spawner: keeps up to `max_active` chasers in the arena, spawning at marked points
## away from the player. Authored waves replace this in Milestone 2.

signal enemy_killed(enemy: Chaser)

@export var enemy_scene: PackedScene
@export var enemy_definition: EnemyDefinition
@export var container_path: NodePath
@export var max_active := 4
@export var spawn_interval := 2.0
@export var first_spawn_delay := 2.5
## Spawn points closer than this to the player are skipped.
@export var min_player_distance := 10.0
## A spawn point with a living enemy this close is treated as occupied.
@export var occupied_radius := 1.5

var _player: Player
var _arena: Node
var _running := false
var _timer := 0.0

@onready var _container: Node3D = get_node(container_path)


func setup(player: Player, arena: Node) -> void:
	_player = player
	_arena = arena


func start() -> void:
	_running = true
	_timer = first_spawn_delay


func stop() -> void:
	_running = false


func active_count() -> int:
	var count := 0
	for enemy in _container.get_children():
		if enemy is Chaser and enemy.is_alive:
			count += 1
	return count


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = spawn_interval
	if active_count() >= max_active:
		return
	var point := _pick_spawn_point()
	if point:
		spawn_at(point.global_position)


func spawn_at(position: Vector3) -> Chaser:
	var enemy: Chaser = enemy_scene.instantiate()
	enemy.definition = enemy_definition
	enemy.target = _player
	_container.add_child(enemy)
	enemy.global_position = position
	enemy.died.connect(_on_enemy_died)
	return enemy


func _pick_spawn_point() -> Marker3D:
	var valid: Array[Marker3D] = []
	for point: Marker3D in _arena.get_spawn_points():
		if _player and point.global_position.distance_to(_player.global_position) < min_player_distance:
			continue
		if _is_occupied(point.global_position):
			continue
		valid.append(point)
	return valid.pick_random() if not valid.is_empty() else null


func _is_occupied(position: Vector3) -> bool:
	for enemy in _container.get_children():
		if enemy is Node3D and enemy.global_position.distance_to(position) < occupied_radius:
			return true
	return false


func _on_enemy_died(enemy: Chaser) -> void:
	enemy_killed.emit(enemy)
