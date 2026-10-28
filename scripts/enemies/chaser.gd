class_name Chaser
extends CharacterBody3D
## Melee enemy: walks to the player along the navmesh, telegraphs, then strikes at close range.

signal died(enemy: Chaser)

enum State { SPAWNING, CHASE, WINDUP, RECOVER, DEAD }

const SPAWN_TIME := 0.6
const REPATH_INTERVAL := 0.2
const HIT_FLASH_TIME := 0.08
const STAGGER_TIME := 0.15
const STAGGER_SPEED_SCALE := 0.35
## Extra reach when the windup ends, so a player standing still is always hit
## but one who backs off during the telegraph escapes.
const ATTACK_GRACE := 0.5
const FALL_LIMIT := -20.0

@export var definition: EnemyDefinition
@export var death_sound: AudioStream

var target: Player
var health := 0.0
var state := State.SPAWNING
var is_alive: bool:
	get:
		return state != State.DEAD

var _state_time := 0.0
var _repath_left := 0.0
var _hit_flash_left := 0.0
var _stagger_left := 0.0
var _material: StandardMaterial3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _visual: Node3D = $Visual
@onready var _body: MeshInstance3D = $Visual/Body
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _attack_sound: AudioStreamPlayer3D = $AttackSound


func _ready() -> void:
	health = definition.max_health
	# Each enemy gets its own material so hit flashes don't light up every chaser.
	_material = _body.get_active_material(0).duplicate()
	_body.set_surface_override_material(0, _material)
	_visual.scale = Vector3.ONE * 0.2


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_state_time += delta
	_hit_flash_left = maxf(_hit_flash_left - delta, 0.0)
	_stagger_left = maxf(_stagger_left - delta, 0.0)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	match state:
		State.SPAWNING:
			_set_horizontal_velocity(Vector3.ZERO)
			if _state_time >= SPAWN_TIME:
				_enter(State.CHASE)
		State.CHASE:
			_chase(delta)
		State.WINDUP:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			if _state_time >= definition.attack_windup:
				_strike()
		State.RECOVER:
			_set_horizontal_velocity(Vector3.ZERO)
			if _state_time >= definition.attack_cooldown:
				_enter(State.CHASE)
	move_and_slide()
	if global_position.y < FALL_LIMIT:
		_die(Vector3.ZERO, false)


func _process(_delta: float) -> void:
	if state == State.DEAD:
		return
	var visual_scale := 1.0
	var glow := Color.BLACK
	match state:
		State.SPAWNING:
			visual_scale = lerpf(0.2, 1.0, clampf(_state_time / SPAWN_TIME, 0.0, 1.0))
		State.WINDUP:
			var progress := clampf(_state_time / definition.attack_windup, 0.0, 1.0)
			visual_scale = 1.0 + 0.15 * progress
			glow = Color(1.0, 0.45, 0.0) * (0.5 + 1.5 * progress)
	if _hit_flash_left > 0.0:
		glow = Color(1.0, 1.0, 1.0) * 2.5
	_visual.scale = Vector3.ONE * visual_scale
	_material.emission = glow


## Called by hitscan weapons. Returns true when this hit killed the enemy.
func take_hit(damage: float, _point: Vector3, direction: Vector3) -> bool:
	if state == State.DEAD:
		return false
	health -= damage
	_hit_flash_left = HIT_FLASH_TIME
	_stagger_left = STAGGER_TIME
	if health <= 0.0:
		_die(direction, true)
		return true
	return false


func _chase(delta: float) -> void:
	if target == null or target.is_dead:
		_set_horizontal_velocity(Vector3.ZERO)
		return
	var to_target := _to_target()
	if to_target.length() <= definition.attack_range:
		_enter(State.WINDUP)
		_set_horizontal_velocity(Vector3.ZERO)
		return
	_repath_left -= delta
	if _repath_left <= 0.0:
		_repath_left = REPATH_INTERVAL
		_agent.target_position = target.global_position
	var direction := _agent.get_next_path_position() - global_position
	direction.y = 0.0
	if direction.length() < 0.05:
		direction = to_target # No path yet (navmesh still syncing): head straight for the player.
	var speed := definition.move_speed * (STAGGER_SPEED_SCALE if _stagger_left > 0.0 else 1.0)
	_set_horizontal_velocity(direction.normalized() * speed)
	_face(direction)


func _strike() -> void:
	_attack_sound.play()
	if target != null and not target.is_dead and _to_target().length() <= definition.attack_range + ATTACK_GRACE:
		target.take_damage(definition.attack_damage)
	_enter(State.RECOVER)


func _die(direction: Vector3, killed_by_player: bool) -> void:
	state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	var center := global_position + Vector3.UP * 0.9
	Fx.burst(self, center + direction * 0.2, definition.color)
	if death_sound:
		Fx.sound_at(self, death_sound, center)
	if killed_by_player:
		died.emit(self)
	queue_free()


func _enter(new_state: State) -> void:
	state = new_state
	_state_time = 0.0


func _to_target() -> Vector3:
	if target == null:
		return Vector3.ZERO
	var offset := target.global_position - global_position
	offset.y = 0.0
	return offset


func _face(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		rotation.y = atan2(-direction.x, -direction.z)


func _set_horizontal_velocity(value: Vector3) -> void:
	velocity.x = value.x
	velocity.z = value.z
