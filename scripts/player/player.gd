class_name Player
extends CharacterBody3D
## First-person movement, mouse look, camera recoil, and health.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float)
signal died

## Radians of rotation per pixel of mouse movement at sensitivity 1.0.
const MOUSE_RADIANS_PER_PIXEL := 0.0022
const MAX_PITCH := deg_to_rad(89.0)

@export var walk_speed := 6.0
@export var sprint_speed := 9.0
@export var jump_velocity := 5.0
@export var ground_acceleration := 60.0
@export var air_acceleration := 12.0
@export var max_health := 100.0
## How quickly camera recoil settles back to the aim point (per second).
@export var recoil_recovery := 10.0

var health := 0.0
var is_dead := false

var _pitch := 0.0
var _recoil_pitch := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var pistol: Pistol = $Head/Camera3D/Pistol
@onready var _hurt_sound: AudioStreamPlayer = $HurtSound


func _ready() -> void:
	health = max_health
	pistol.setup(camera, get_rid())
	pistol.fired.connect(_on_pistol_fired)
	Settings.changed.connect(_apply_settings)
	_apply_settings()


func _unhandled_input(event: InputEvent) -> void:
	if is_dead or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var radians_per_pixel := MOUSE_RADIANS_PER_PIXEL * Settings.mouse_sensitivity
		rotate_y(-event.relative.x * radians_per_pixel)
		_pitch = clampf(_pitch - event.relative.y * radians_per_pixel, -MAX_PITCH, MAX_PITCH)
		_apply_pitch()


func _process(delta: float) -> void:
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, 1.0 - exp(-recoil_recovery * delta))
	_apply_pitch()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var target := Vector3.ZERO
	if not is_dead:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
		target = global_basis * Vector3(input.x, 0.0, input.y) * speed
	var acceleration := ground_acceleration if is_on_floor() else air_acceleration
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2(target.x, target.z), acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	move_and_slide()


func take_damage(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	damaged.emit(amount)
	_hurt_sound.play()
	if health <= 0.0:
		_die()


func _die() -> void:
	is_dead = true
	pistol.enabled = false
	pistol.visible = false
	var tween := create_tween().set_parallel()
	tween.tween_property(head, "position:y", 0.6, 0.5).set_ease(Tween.EASE_IN)
	tween.tween_property(head, "rotation:z", deg_to_rad(15.0), 0.5)
	died.emit()


func _on_pistol_fired(kick_degrees: float) -> void:
	_recoil_pitch += deg_to_rad(kick_degrees) * Settings.camera_recoil


func _apply_pitch() -> void:
	head.rotation.x = clampf(_pitch + _recoil_pitch, -MAX_PITCH, MAX_PITCH)


func _apply_settings() -> void:
	camera.fov = Settings.field_of_view
