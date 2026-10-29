class_name WaveRunner
extends Node
## Runs one authored wave at a time: spawns its groups at marked points away from the player,
## holds the alive cap, pays kill credits the moment an enemy dies, and reports the clear.
## Replaces the Milestone 1 test spawner.

signal enemy_killed(enemy: Chaser, credits: int)
## The number of enemies left to kill changed (spawned-but-alive plus not-yet-spawned).
signal remaining_changed(remaining: int, total: int)
signal wave_cleared(wave: WaveDefinition, duration: float)

const WAVE_DIR := "res://data/waves/"
const WAVE_COUNT := 5

@export var container_path: NodePath
## Spawn points closer than this to the player are skipped.
@export var min_player_distance := 10.0
## A spawn point with a living enemy this close is treated as occupied.
@export var occupied_radius := 1.5

var current: WaveDefinition
var running := false
var elapsed := 0.0
## Multiplier for enemy health and credits this wave (wave tier and Reforge tier).
var scale := 1.0

var _player: Player
var _arena: Node
## Per group: how many are still to spawn and the countdown to the next one.
var _pending: Array[int] = []
var _timers: Array[float] = []
var _spawned := 0
var _killed := 0

@onready var _container: Node3D = get_node(container_path)


static func load_wave(number: int) -> WaveDefinition:
	var path := WAVE_DIR + "wave_%02d.tres" % number
	return load(path) if ResourceLoader.exists(path) else null


static func all_waves() -> Array[WaveDefinition]:
	var waves: Array[WaveDefinition] = []
	for number in range(1, WAVE_COUNT + 1):
		var wave := load_wave(number)
		if wave:
			waves.append(wave)
	return waves


func setup(player: Player, arena: Node) -> void:
	_player = player
	_arena = arena


## Clears any leftover enemies and starts the wave. Spawning waits for the first physics tick.
func start(wave: WaveDefinition, reward_scale := 1.0) -> void:
	clear_enemies()
	current = wave
	scale = reward_scale
	elapsed = 0.0
	_spawned = 0
	_killed = 0
	_pending.clear()
	_timers.clear()
	for group in wave.groups:
		_pending.append(group.count)
		_timers.append(group.start_delay)
	running = true
	remaining_changed.emit(remaining(), wave.total_enemies())


func stop() -> void:
	running = false


func clear_enemies() -> void:
	for enemy in _container.get_children():
		_container.remove_child(enemy)
		enemy.queue_free()


func active_count() -> int:
	var count := 0
	for enemy in _container.get_children():
		if enemy is Chaser and enemy.is_alive:
			count += 1
	return count


func remaining() -> int:
	return current.total_enemies() - _killed if current else 0


func _physics_process(delta: float) -> void:
	if not running or current == null:
		return
	elapsed += delta
	for i in _pending.size():
		if _pending[i] <= 0:
			continue
		_timers[i] -= delta
		if _timers[i] > 0.0:
			continue
		if active_count() >= current.max_alive:
			continue
		var point := _pick_spawn_point()
		if point == null:
			continue
		var group := current.groups[i]
		spawn_at(point.global_position, group.definition, group.enemy_scene)
		_pending[i] -= 1
		_timers[i] = group.interval


## Spawns one enemy. Definition and scene default to the current wave's first group, so tests
## can drop an enemy in front of the player without authoring a wave.
func spawn_at(position: Vector3, definition: EnemyDefinition = null, scene: PackedScene = null) -> Chaser:
	if definition == null and current and not current.groups.is_empty():
		definition = current.groups[0].definition
	if scene == null and current and not current.groups.is_empty():
		scene = current.groups[0].enemy_scene
	if scene == null:
		scene = load("res://scenes/enemies/chaser.tscn")
	if definition == null:
		definition = load("res://data/enemies/chaser.tres")
	var enemy: Chaser = scene.instantiate()
	enemy.definition = definition
	enemy.health_scale = scale
	enemy.target = _player
	_container.add_child(enemy)
	enemy.global_position = position
	enemy.died.connect(_on_enemy_died)
	_spawned += 1
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
	var credits := maxi(roundi(enemy.definition.credit_reward * scale), 1)
	enemy_killed.emit(enemy, credits)
	if not running or current == null:
		return
	_killed += 1
	remaining_changed.emit(remaining(), current.total_enemies())
	if _killed >= current.total_enemies():
		running = false
		wave_cleared.emit(current, elapsed)
