class_name Enemy
extends CharacterBody3D
## The one base enemy (plan: Enemies). Owns health, the spawn-in, hit flash and stagger, death and
## loot hooks, gravity, navigation helpers and the target. Types (Chaser, Shooter, SwarmDrone,
## Warden) are scenes with their own `_behave` step and telegraph colours. Status effects, weak
## points and enemy affixes land here in later milestones.

signal died(enemy: Enemy)
signal health_changed(current: float, maximum: float)

const SPAWN_TIME := 0.6
const REPATH_INTERVAL := 0.2
const HIT_FLASH_TIME := 0.08
const STAGGER_TIME := 0.15
const STAGGER_SPEED_SCALE := 0.35
const FALL_LIMIT := -20.0
## Shots check line of sight against world geometry only.
const WORLD_MASK := 1

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

var _spawn_time := 0.0
var _hit_flash_left := 0.0
var _stagger_left := 0.0
var _repath_left := 0.0
var _material: StandardMaterial3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _visual: Node3D = $Visual
@onready var _body: MeshInstance3D = $Visual/Body
@onready var _agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	# Each enemy gets its own material so hit flashes don't light up every robot.
	_material = _body.get_active_material(0).duplicate()
	_body.set_surface_override_material(0, _material)
	_visual.scale = Vector3.ONE * 0.2
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
	_material.emission = glow
	_visual_tick(delta)


## Called by hitscan rays and projectiles. Returns true when this hit killed the enemy.
func take_hit(damage: float, _point: Vector3, direction: Vector3) -> bool:
	if not is_alive:
		return false
	health -= damage
	_hit_flash_left = HIT_FLASH_TIME
	_stagger_left = STAGGER_TIME
	health_changed.emit(maxf(health, 0.0), max_health)
	if health <= 0.0:
		_die(direction, true)
		return true
	return false


## Where the death burst and loot appear.
func center() -> Vector3:
	return global_position + Vector3.UP * (definition.hover_height if definition.flying else 0.9)


# ------------------------------------------------------------------ hooks for enemy types

## One physics step of behaviour once spawned. Set the horizontal velocity; the base moves.
func _behave(_delta: float) -> void:
	pass


func _on_spawned() -> void:
	pass


func _visual_scale() -> float:
	return 1.0


func _visual_glow() -> Color:
	return Color.BLACK


func _visual_tick(_delta: float) -> void:
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
	var from := global_position + Vector3.UP * (definition.hover_height if definition.flying else 1.3)
	var to := target.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _die(direction: Vector3, killed_by_player: bool) -> void:
	is_alive = false
	collision_layer = 0
	collision_mask = 0
	var at := center()
	Fx.burst(self, at + direction * 0.2, definition.color)
	if death_sound:
		Fx.sound_at(self, death_sound, at)
	if killed_by_player:
		died.emit(self)
	queue_free()
