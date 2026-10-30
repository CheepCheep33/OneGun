class_name WaveRunner
extends Node
## Runs one authored wave at a time: spawns its groups at marked points away from the player,
## holds the alive cap (drones count as half), pays kill credits the moment an enemy dies, and
## reports the clear. Boss waves announce their boss for the HUD bar.
##
## Enemy nodes are recycled: a dead enemy leaves the arena and waits in a reserve, and a spawn takes
## one from there before it builds a new node, because instantiating a scene mid-wave is a hitch on
## the web build. warm_up() fills the reserve at the first bench with as many of each enemy as the
## authored waves can have alive at once, plus the adds a boss can call in.
##
## A boss's adds (the Foreman's drones) come from the same reserve. They pay kill credits but do not
## count toward the wave or its alive cap, and they fall with the boss.

signal enemy_killed(enemy: Enemy, credits: int)
## The number of enemies left to kill changed (spawned-but-alive plus not-yet-spawned).
signal remaining_changed(remaining: int, total: int)
signal wave_cleared(wave: WaveDefinition, duration: float)
signal boss_spawned(enemy: Enemy)

const WAVE_DIR := "res://data/waves/"
const WAVE_COUNT := 15
## Most nodes of one enemy scene kept in the reserve.
const RESERVE_CAP := 16
## Enemies readied per frame while the reserve fills behind the first bench.
const WARM_UP_PER_FRAME := 2

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
## Scene path -> ready-made enemy nodes outside the tree, by warm_up() and recycling.
var _reserve: Dictionary = {}
## Nodes instantiated by spawn_at because the reserve had none (the gate expects zero in a wave).
var reserve_misses := 0
var _warming_up := false

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


## Fills the reserve, a few enemies a frame, with as many of each scene as any authored wave can
## have alive at once (RESERVE_CAP at most). Each one enters the tree once so its _ready work
## (material, groups, physics and navigation registration) is paid here, behind the bench. Called
## at every bench, so a node lost to the cap or freed outright is replaced before the next wave.
func warm_up() -> void:
	if _warming_up:
		return
	_warming_up = true
	var wanted := reserve_targets()
	for path in wanted:
		var scene: PackedScene = load(path)
		if scene == null:
			continue
		var pool: Array = _reserve.get(path, [])
		var readied := 0
		while pool.size() < int(wanted[path]):
			var enemy: Enemy = scene.instantiate()
			enemy.target = _player
			_container.add_child(enemy)
			enemy.is_alive = false
			_container.remove_child(enemy)
			pool.append(enemy)
			_reserve[path] = pool
			readied += 1
			if readied % WARM_UP_PER_FRAME == 0:
				await get_tree().process_frame
				if not is_inside_tree():
					break
	_warming_up = false


## The reserve lives outside the tree, so it is freed by hand when the runner goes.
func _exit_tree() -> void:
	for path in _reserve:
		for enemy in _reserve[path]:
			if is_instance_valid(enemy):
				enemy.free()
	_reserve.clear()


## How many of each enemy scene the authored waves can have alive at once: per wave, each group's
## count or the alive cap in its share, summed per scene, plus a summoning boss's max_summons of
## its add scene; the most over all waves, capped.
static func reserve_targets() -> Dictionary:
	var wanted := {}
	for wave in all_waves():
		var per_scene := {}
		for group in wave.groups:
			if group.enemy_scene == null:
				continue
			var share := group.definition.counts_as if group.definition else 1.0
			var at_once := mini(group.count, ceili(wave.max_alive / maxf(share, 0.01)))
			per_scene[group.enemy_scene.resource_path] = int(per_scene.get(group.enemy_scene.resource_path, 0)) + at_once
			if group.definition and group.definition.summon_scene != null and group.definition.max_summons > 0:
				var add_path := group.definition.summon_scene.resource_path
				per_scene[add_path] = int(per_scene.get(add_path, 0)) + group.definition.max_summons
		for path in per_scene:
			wanted[path] = mini(maxi(int(wanted.get(path, 0)), int(per_scene[path])), RESERVE_CAP)
	return wanted


## Ready-made nodes waiting for a scene (all scenes when the path is empty).
func reserved_count(scene_path := "") -> int:
	var count := 0
	for path in _reserve:
		if scene_path == "" or path == scene_path:
			for enemy in _reserve[path]:
				if is_instance_valid(enemy):
					count += 1
	return count


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


## Takes every enemy out of the arena, back into the reserve.
func clear_enemies() -> void:
	for enemy in _container.get_children():
		if enemy is Enemy:
			enemy.is_alive = false
			_recycle(enemy)
		else:
			_container.remove_child(enemy)
			enemy.queue_free()


## Living enemies, each weighted by its definition's share of the cap (drones count as half). A
## boss's adds are outside the cap.
func active_weight() -> float:
	var weight := 0.0
	for enemy in _container.get_children():
		if enemy is Enemy and enemy.is_alive and not enemy.summoned:
			weight += enemy.definition.counts_as
	return weight


## Living adds called in by a boss.
func summon_count() -> int:
	var count := 0
	for enemy in _container.get_children():
		if enemy is Enemy and enemy.is_alive and enemy.summoned:
			count += 1
	return count


func active_count() -> int:
	var count := 0
	for enemy in _container.get_children():
		if enemy is Enemy and enemy.is_alive:
			count += 1
	return count


func living_enemies() -> Array[Enemy]:
	var result: Array[Enemy] = []
	for enemy in _container.get_children():
		if enemy is Enemy and enemy.is_alive:
			result.append(enemy)
	return result


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
		var group := current.groups[i]
		var weight := group.definition.counts_as if group.definition else 1.0
		if active_weight() + weight > current.max_alive + 0.001:
			continue
		var point := _pick_spawn_point()
		if point == null:
			continue
		spawn_at(point.global_position, group.definition, group.enemy_scene)
		_pending[i] -= 1
		_timers[i] = group.interval


## Spawns one enemy, from the reserve when it has one of the scene. Definition and scene default to
## the current wave's first group, so tests can drop an enemy in front of the player without
## authoring a wave.
func spawn_at(position: Vector3, definition: EnemyDefinition = null, scene: PackedScene = null) -> Enemy:
	if definition == null and current and not current.groups.is_empty():
		definition = current.groups[0].definition
	if scene == null and current and not current.groups.is_empty():
		scene = current.groups[0].enemy_scene
	if scene == null:
		scene = load("res://scenes/enemies/chaser.tscn")
	if definition == null:
		definition = load("res://data/enemies/chaser.tres")
	var enemy := _take(scene)
	enemy.definition = definition
	enemy.health_scale = scale
	enemy.target = _player
	enemy.summoned = false
	_container.add_child(enemy)
	enemy.reset()
	enemy.global_position = position
	if not enemy.died.is_connected(_on_enemy_died):
		enemy.died.connect(_on_enemy_died)
	if not enemy.retired.is_connected(_on_enemy_retired):
		enemy.retired.connect(_on_enemy_retired)
	if not enemy.summon_requested.is_connected(_on_summon_requested):
		enemy.summon_requested.connect(_on_summon_requested)
	_spawned += 1
	if definition.is_boss:
		boss_spawned.emit(enemy)
	return enemy


## A reserved node of the scene, else a new one.
func _take(scene: PackedScene) -> Enemy:
	var pool: Array = _reserve.get(scene.resource_path, [])
	while not pool.is_empty():
		var enemy: Enemy = pool.pop_back()
		if is_instance_valid(enemy):
			return enemy
	reserve_misses += 1
	return scene.instantiate()


## A dead enemy leaves the arena at the end of the frame (it may be inside its own physics step).
func _on_enemy_retired(enemy: Enemy) -> void:
	_recycle.call_deferred(enemy)


func _recycle(enemy: Enemy) -> void:
	# A deferred recycle can arrive after clear_enemies already parked the node, or after the node
	# was taken out again and is alive in the arena: either way it is not this call's to park.
	if not is_instance_valid(enemy) or enemy.is_alive:
		return
	if _reserve.get(enemy.scene_file_path, []).has(enemy):
		return
	enemy.silence()
	if enemy.get_parent() != null:
		enemy.get_parent().remove_child(enemy)
	var key := enemy.scene_file_path
	var pool: Array = _reserve.get(key, [])
	if key == "" or pool.size() >= RESERVE_CAP:
		enemy.queue_free()
		return
	pool.append(enemy)
	_reserve[key] = pool


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


## Brings in up to `count` of a boss's adds around it, never more than its max_summons alive.
func _on_summon_requested(boss: Enemy, count: int) -> void:
	var definition := boss.definition
	if definition.summon_scene == null or definition.summon_definition == null or not boss.is_alive:
		return
	var wanted := mini(count, definition.max_summons - summon_count())
	for i in wanted:
		var angle := TAU * (i + 0.5) / maxf(wanted, 1.0) + boss.rotation.y
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 2.4
		var add := spawn_at(boss.global_position + offset + Vector3.UP * 0.2, definition.summon_definition, definition.summon_scene)
		add.summoned = true


## Every living add leaves without paying (its boss fell).
func dismiss_summons() -> void:
	for enemy in _container.get_children():
		if enemy is Enemy and enemy.is_alive and enemy.summoned:
			enemy.dismiss()


func _on_enemy_died(enemy: Enemy) -> void:
	var credits := maxi(roundi(enemy.definition.credit_reward * scale), 1)
	enemy_killed.emit(enemy, credits)
	if enemy.definition.is_boss:
		dismiss_summons.call_deferred()
	if not running or current == null or enemy.summoned:
		return
	_killed += 1
	remaining_changed.emit(remaining(), current.total_enemies())
	if _killed >= current.total_enemies():
		running = false
		wave_cleared.emit(current, elapsed)
