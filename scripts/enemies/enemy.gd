class_name Enemy
extends CharacterBody3D
## The one base enemy (plan: Enemies). Owns health, the spawn-in, hit flash and stagger, death and
## loot hooks, gravity, navigation helpers and the target. Types (Chaser, Shooter, SwarmDrone,
## Warden) are scenes with their own `_behave` step, `_reset_behaviour` and telegraph colours.
## Nodes are recycled by the wave runner, so every bit of state lives in reset(). Armour and weak
## points come from the definition: armour takes a flat amount off every hit (at least a quarter
## of the hit still lands), a weak-point hit ignores it. Status effects and enemy affixes land here
## in later milestones.

signal died(enemy: Enemy)
## Emitted on every death, by the player or the fall limit, once the node can leave the arena.
## The wave runner recycles it into its reserve (no node is built or freed mid-wave).
signal retired(enemy: Enemy)
signal health_changed(current: float, maximum: float)
## A boss asks the wave runner for adds (the Foreman's drones); see EnemyDefinition.summon_scene.
signal summon_requested(enemy: Enemy, count: int)

const SPAWN_TIME := 0.6
const REPATH_INTERVAL := 0.2
const HIT_FLASH_TIME := 0.08
const STAGGER_TIME := 0.15
const STAGGER_SPEED_SCALE := 0.35
const FALL_LIMIT := -20.0
## Shots check line of sight against world geometry only.
const WORLD_MASK := 1
## Armour never takes more than this share of a hit.
const ARMOR_MAX_SHARE := 0.75

@export var definition: EnemyDefinition
@export var death_sound: AudioStream

var target: Player
## Set by the wave runner before the enemy enters the tree: wave tier and Reforge tier scaling.
var health_scale := 1.0
var health := 0.0
var max_health: float:
	get:
		return definition.max_health * health_scale
var is_alive := true
var is_spawning := true
## Set by the wave runner on a boss's adds: they pay credits but do not count toward the wave.
var summoned := false
## What the last take_hit actually removed, after armour, for damage numbers.
var last_damage_taken := 0.0

var _spawn_time := 0.0
var _hit_flash_left := 0.0
var _stagger_left := 0.0
var _repath_left := 0.0
var _material: StandardMaterial3D
## The emission last sent to the material: a material parameter is a buffer upload in the
## renderer, so it is only written when the glow changes.
var _last_glow := Color.BLACK
## One reusable line-of-sight query (built per call it would be an allocation per tick per shooter).
var _los_query := PhysicsRayQueryParameters3D.new()
## The scene's collision layer and mask, restored when a recycled enemy is reset.
var _base_collision_layer := 0
var _base_collision_mask := 0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _visual: Node3D = $Visual
@onready var _body: MeshInstance3D = $Visual/Body
@onready var _agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")


func _ready() -> void:
	add_to_group("enemies")
	_base_collision_layer = collision_layer
	_base_collision_mask = collision_mask
	# Each enemy gets its own material so hit flashes don't light up every robot.
	_material = _body.get_active_material(0).duplicate()
	_body.set_surface_override_material(0, _material)
	_los_query.collision_mask = WORLD_MASK
	_los_query.exclude = [get_rid()]
	reset()


## The starting state for a fresh or recycled node: full health, spawning in, collisions on, the
## behaviour at its first phase. The wave runner calls this after it puts the enemy in the arena,
## with `definition`, `health_scale` and `target` already set.
func reset() -> void:
	is_alive = true
	is_spawning = true
	_spawn_time = 0.0
	_hit_flash_left = 0.0
	_stagger_left = 0.0
	_repath_left = 0.0
	velocity = Vector3.ZERO
	collision_layer = _base_collision_layer
	collision_mask = _base_collision_mask
	health = max_health
	_visual.scale = Vector3.ONE * 0.2
	_set_glow(Color.BLACK)
	_reset_behaviour()
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	_hit_flash_left = maxf(_hit_flash_left - delta, 0.0)
	_stagger_left = maxf(_stagger_left - delta, 0.0)
	if not definition.flying and not is_on_floor():
		velocity.y -= _gravity * delta
	if is_spawning:
		_spawn_time += delta
		_set_horizontal_velocity(Vector3.ZERO)
		if _spawn_time >= SPAWN_TIME:
			is_spawning = false
			_on_spawned()
	else:
		_behave(delta)
	move_and_slide()
	if global_position.y < FALL_LIMIT:
		_die(Vector3.ZERO, false)


func _process(delta: float) -> void:
	if not is_alive:
		return
	var visual_scale := _visual_scale()
	if is_spawning:
		visual_scale *= lerpf(0.2, 1.0, clampf(_spawn_time / SPAWN_TIME, 0.0, 1.0))
	var glow := _visual_glow()
	if _hit_flash_left > 0.0:
		glow = Color(1.0, 1.0, 1.0) * 2.5
	_visual.scale = Vector3.ONE * visual_scale
	_set_glow(glow)
	_visual_tick(delta)


## Called by hitscan rays, projectiles, chains and blasts. Returns true when this hit killed the
## enemy. Armour takes its share unless the hit landed on a weak point.
func take_hit(damage: float, _point: Vector3, direction: Vector3, weak_point := false) -> bool:
	last_damage_taken = 0.0
	if not is_alive:
		return false
	if not weak_point and definition.armor > 0.0:
		damage = maxf(damage - definition.armor * health_scale, damage * (1.0 - ARMOR_MAX_SHARE))
	last_damage_taken = damage
	health -= damage
	_hit_flash_left = HIT_FLASH_TIME
	_stagger_left = STAGGER_TIME
	health_changed.emit(maxf(health, 0.0), max_health)
	if health <= 0.0:
		_die(direction, true)
		return true
	return false


## True when a hit at `point` (world space) lands on the definition's weak point, a sphere in the
## enemy's own space (the heavy's core on its back).
func is_weak_point(point: Vector3) -> bool:
	if definition == null or definition.weak_point_radius <= 0.0:
		return false
	return to_local(point).distance_to(definition.weak_point_offset) <= definition.weak_point_radius


## Takes the enemy out without a kill: no credits, no drop, a burst where it was (a boss's adds
## when the boss falls or the wave clears).
func dismiss() -> void:
	if not is_alive:
		return
	_die(Vector3.ZERO, false)


## Cuts every sound this enemy is playing; the death sound is the pool's, so it carries on. A node
## leaving the arena must not keep a paused playback alive in the reserve.
func silence() -> void:
	for child in get_children():
		if child is AudioStreamPlayer3D:
			child.stop()


func _set_glow(glow: Color) -> void:
	if glow != _last_glow:
		_last_glow = glow
		_material.emission = glow


## Where the death burst and loot appear.
func center() -> Vector3:
	return global_position + Vector3.UP * (definition.hover_height if definition.flying else 0.9)


# ------------------------------------------------------------------ hooks for enemy types

## One physics step of behaviour once spawned. Set the horizontal velocity; the base moves.
func _behave(_delta: float) -> void:
	pass


func _on_spawned() -> void:
	pass


## Back to the first phase with cooldowns at their opening values; runs on every (re)spawn.
func _reset_behaviour() -> void:
	pass


func _visual_scale() -> float:
	return 1.0


func _visual_glow() -> Color:
	return Color.BLACK


func _visual_tick(_delta: float) -> void:
	pass


## Runs once as the enemy dies, before it leaves the arena: hide telegraphs, drop shields.
func _on_death() -> void:
	pass


# ------------------------------------------------------------------ helpers

func target_alive() -> bool:
	return target != null and is_instance_valid(target) and not target.is_dead


func _to_target() -> Vector3:
	if not target_alive():
		return Vector3.ZERO
	var offset := target.global_position - global_position
	offset.y = 0.0
	return offset


func _distance_to_target() -> float:
	return _to_target().length() if target_alive() else INF


func _face(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		rotation.y = atan2(-direction.x, -direction.z)


func _set_horizontal_velocity(value: Vector3) -> void:
	velocity.x = value.x
	velocity.z = value.z


## Speed after stagger from a recent hit.
func _speed_scale() -> float:
	return STAGGER_SPEED_SCALE if _stagger_left > 0.0 else 1.0


## Direction of the next step along the navmesh toward the target (straight line while the path
## is still being computed). Zero when there is no target.
func _path_direction(delta: float) -> Vector3:
	if not target_alive():
		return Vector3.ZERO
	var to_target := _to_target()
	if _agent == null:
		return to_target.normalized()
	_repath_left -= delta
	if _repath_left <= 0.0:
		_repath_left = REPATH_INTERVAL
		_agent.target_position = target.global_position
	var direction := _agent.get_next_path_position() - global_position
	direction.y = 0.0
	if direction.length() < 0.05:
		direction = to_target # No path yet (navmesh still syncing): head straight for the player.
	return direction.normalized()


## Walks toward the target along the navmesh at the definition's speed and faces the way it goes.
func _chase_target(delta: float, speed_scale := 1.0) -> void:
	var direction := _path_direction(delta)
	_set_horizontal_velocity(direction * definition.move_speed * _speed_scale() * speed_scale)
	_face(direction)


## True when nothing of the world stands between this enemy's eyes and the player's chest.
func has_line_of_sight() -> bool:
	if not target_alive():
		return false
	_los_query.from = global_position + Vector3.UP * (definition.hover_height if definition.flying else 1.3)
	_los_query.to = target.global_position + Vector3.UP * 1.0
	return get_world_3d().direct_space_state.intersect_ray(_los_query).is_empty()


func _die(direction: Vector3, killed_by_player: bool) -> void:
	is_alive = false
	collision_layer = 0
	collision_mask = 0
	_on_death()
	var at := center()
	Fx.burst(self, at + direction * 0.2, definition.color)
	if death_sound:
		Fx.sound_at(self, death_sound, at)
	if killed_by_player:
		died.emit(self)
	retired.emit(self)
