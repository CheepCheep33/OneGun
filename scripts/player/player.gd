class_name Player
extends CharacterBody3D
## First-person movement, mouse look, camera recoil, and health. The Survivor tree's effects
## (more health and speed, plating, healing per kill, dash, Phoenix) and Marksman's Bullet Time
## arrive through apply_skills() at the start of every encounter, from Progression.player_effects().

signal health_changed(current: float, maximum: float)
signal damaged(amount: float)
signal died
## Phoenix saved the player from a lethal hit (the HUD flashes it).
signal phoenix_triggered
signal bullet_time_changed(active: bool)

## Radians of rotation per pixel of mouse movement at sensitivity 1.0.
const MOUSE_RADIANS_PER_PIXEL := 0.0022
const MAX_PITCH := deg_to_rad(89.0)
## Mouse motion is ignored this long after the mouse is captured. Browsers can report one huge jump
## when pointer lock engages, which would otherwise snap the view.
const CAPTURE_SETTLE_TIME := 0.1
## Dash (Survivor): double-tap a direction within DASH_TAP_WINDOW to move at DASH_SPEED for
## DASH_TIME, then wait DASH_COOLDOWN.
const DASH_TAP_WINDOW := 0.25
const DASH_SPEED := 22.0
const DASH_TIME := 0.16
const DASH_COOLDOWN := 2.0
## Plating never takes more than this share of a hit.
const PLATING_MAX_SHARE := 0.75
## Phoenix: seconds of invulnerability after a lethal hit is survived.
const PHOENIX_TIME := 2.0
## Bullet Time: reloading under this health fraction slows time to BULLET_TIME_SCALE for
## BULLET_TIME_SECONDS of real time, once per wave.
const BULLET_TIME_HEALTH := 0.3
const BULLET_TIME_SCALE := 0.4
const BULLET_TIME_SECONDS := 2.0
## The Shield emitter covers hits from within this angle of where the player faces.
const SHIELD_HALF_ANGLE := deg_to_rad(70.0)

@export var walk_speed := 6.0
@export var sprint_speed := 9.0
@export var jump_velocity := 5.0
@export var ground_acceleration := 60.0
@export var air_acceleration := 12.0
@export var max_health := 100.0
@export var base_max_health := 100.0
## How quickly camera recoil settles back to the aim point (per second).
@export var recoil_recovery := 10.0

var health := 0.0
var is_dead := false

var _pitch := 0.0
var _recoil_pitch := 0.0
var _capture_settle_left := 0.0
var _mouse_input_enabled := true
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _head_rest_position: Vector3
var _death_tween: Tween
## Skill effects for this encounter (Progression.player_effects()).
var effects: Dictionary = {}
var phoenix_ready := false
var _invulnerable_left := 0.0
var _bullet_time_used := false
var _bullet_time_until := 0
var _dash_left := 0.0
var _dash_cooldown := 0.0
var _dash_direction := Vector3.ZERO
var _last_tap_action := &""
var _last_tap_time := -1.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var pistol: Pistol = $Head/Camera3D/Pistol
@onready var _hurt_sound: AudioStreamPlayer = $HurtSound


func _ready() -> void:
	health = max_health
	_head_rest_position = head.position
	pistol.setup(camera, get_rid())
	pistol.fired.connect(_on_pistol_fired)
	pistol.reload_started.connect(_on_reload_started)
	Settings.changed.connect(_apply_settings)
	_apply_settings()


func _unhandled_input(event: InputEvent) -> void:
	if is_dead or not _mouse_input_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion and _capture_settle_left <= 0.0:
		look(event.relative)
	elif event is InputEventKey and event.pressed and not event.echo:
		for action in [&"move_forward", &"move_back", &"move_left", &"move_right"]:
			if event.is_action(action):
				_on_direction_tap(action)
				break


## Turns the view by a screen-space movement in pixels, scaled by the sensitivity setting.
func look(relative: Vector2) -> void:
	if is_dead:
		return
	var radians_per_pixel := MOUSE_RADIANS_PER_PIXEL * Settings.mouse_sensitivity
	rotate_y(-relative.x * radians_per_pixel)
	_pitch = clampf(_pitch - relative.y * radians_per_pixel, -MAX_PITCH, MAX_PITCH)
	_apply_pitch()


func _process(delta: float) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_capture_settle_left = maxf(_capture_settle_left - delta, 0.0)
	else:
		_capture_settle_left = CAPTURE_SETTLE_TIME
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, 1.0 - exp(-recoil_recovery * delta))
	_apply_pitch()
	if _bullet_time_until > 0 and Time.get_ticks_msec() >= _bullet_time_until:
		end_bullet_time()


func _physics_process(delta: float) -> void:
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var target := Vector3.ZERO
	if not is_dead:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
		speed *= 1.0 + float(effects.get("move_speed", 0.0))
		target = global_basis * Vector3(input.x, 0.0, input.y) * speed
	if _dash_left > 0.0 and not is_dead:
		_dash_left -= delta
		velocity.x = _dash_direction.x * DASH_SPEED
		velocity.z = _dash_direction.z * DASH_SPEED
		move_and_slide()
		return
	var acceleration := ground_acceleration if is_on_floor() else air_acceleration
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2(target.x, target.z), acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	move_and_slide()


## Turned off in touch mode so taps and drags, which browsers also report as mouse input, don't
## shoot or turn the view a second time.
func set_mouse_input_enabled(value: bool) -> void:
	_mouse_input_enabled = value
	pistol.mouse_input_enabled = value


## `source` is where the hit came from (a bolt's path), for the Shield emitter's frontal cover;
## a hit with no source (melee) counts as from the front. `over_time` marks damage dealt a little
## every frame (molten floors): neither plating nor the shield applies to it.
func take_damage(amount: float, source := Vector3.INF, over_time := false) -> void:
	if is_dead or amount <= 0.0 or _invulnerable_left > 0.0:
		return
	if not over_time and pistol.is_shield_up() and _is_from_front(source):
		amount *= 1.0 - Pistol.RELOAD_SHIELD_REDUCTION
	var plating := float(effects.get("plating", 0.0))
	if plating > 0.0 and not over_time:
		amount = maxf(amount - plating, amount * (1.0 - PLATING_MAX_SHARE))
	if amount >= health and phoenix_ready:
		# Phoenix: once per wave, a lethal hit leaves 1 health and a moment of invulnerability.
		phoenix_ready = false
		amount = health - 1.0
		_invulnerable_left = PHOENIX_TIME
		phoenix_triggered.emit()
	health = maxf(health - amount, 0.0)
	pistol.player_health_fraction = health / max_health
	health_changed.emit(health, max_health)
	damaged.emit(amount)
	_hurt_sound.play()
	if health <= 0.0:
		_die()


func heal(amount: float) -> void:
	if is_dead or amount <= 0.0 or health >= max_health:
		return
	health = minf(health + amount, max_health)
	pistol.player_health_fraction = health / max_health
	health_changed.emit(health, max_health)


## A robot died: Second Wind heals (the game calls this for every kill).
func notify_kill() -> void:
	heal(float(effects.get("heal_per_kill", 0.0)))


## Skill effects for the coming encounter: max health, speed, plating, healing, dash, Phoenix.
func apply_skills(new_effects: Dictionary) -> void:
	effects = new_effects
	max_health = base_max_health + float(effects.get("max_health", 0.0))


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


func _is_from_front(source: Vector3) -> bool:
	if source == Vector3.INF:
		return true
	var to_source := source - global_position
	to_source.y = 0.0
	var forward := -global_basis.z
	forward.y = 0.0
	if to_source.length_squared() < 0.0001:
		return true
	return forward.normalized().angle_to(to_source.normalized()) <= SHIELD_HALF_ANGLE


func _on_direction_tap(action: StringName) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if action == _last_tap_action and now - _last_tap_time <= DASH_TAP_WINDOW:
		_last_tap_action = &""
		dash(action)
		return
	_last_tap_action = action
	_last_tap_time = now


## Dashes toward a movement action's direction (Survivor's Dash). False when not taken or recharging.
func dash(action: StringName) -> bool:
	if is_dead or float(effects.get("dash", 0.0)) <= 0.0 or _dash_cooldown > 0.0:
		return false
	var local := {&"move_forward": Vector3.FORWARD, &"move_back": Vector3.BACK,
		&"move_left": Vector3.LEFT, &"move_right": Vector3.RIGHT}.get(action, Vector3.FORWARD) as Vector3
	_dash_direction = (global_basis * local).normalized()
	_dash_left = DASH_TIME
	_dash_cooldown = DASH_COOLDOWN
	return true


## Bullet Time (Marksman capstone): reloading under BULLET_TIME_HEALTH slows the whole game for a
## couple of real seconds, once per wave.
func _on_reload_started(_duration: float) -> void:
	if is_dead or _bullet_time_used or pistol.stats.extra_percent("bullet_time") <= 0.0:
		return
	if health / max_health >= BULLET_TIME_HEALTH:
		return
	_bullet_time_used = true
	_bullet_time_until = Time.get_ticks_msec() + roundi(BULLET_TIME_SECONDS * 1000.0)
	Engine.time_scale = BULLET_TIME_SCALE
	bullet_time_changed.emit(true)


func end_bullet_time() -> void:
	if _bullet_time_until == 0:
		return
	_bullet_time_until = 0
	Engine.time_scale = 1.0
	bullet_time_changed.emit(false)


func _die() -> void:
	is_dead = true
	end_bullet_time()
	pistol.enabled = false
	pistol.visible = false
	_death_tween = create_tween().set_parallel()
	_death_tween.tween_property(head, "position:y", 0.6, 0.5).set_ease(Tween.EASE_IN)
	_death_tween.tween_property(head, "rotation:z", deg_to_rad(15.0), 0.5)
	died.emit()


## Puts the player back at a start transform at full health with the gun ready, for the next wave.
func revive(start: Transform3D) -> void:
	if _death_tween:
		_death_tween.kill()
	is_dead = false
	health = max_health
	end_bullet_time()
	_bullet_time_used = false
	phoenix_ready = float(effects.get("phoenix", 0.0)) > 0.0
	_invulnerable_left = 0.0
	_dash_left = 0.0
	_dash_cooldown = 0.0
	pistol.player_health_fraction = 1.0
	velocity = Vector3.ZERO
	global_transform = start
	head.position = _head_rest_position
	head.rotation = Vector3.ZERO
	_pitch = 0.0
	_recoil_pitch = 0.0
	pistol.enabled = true
	pistol.visible = true
	health_changed.emit(health, max_health)


func _on_pistol_fired(kick_degrees: float) -> void:
	_recoil_pitch += deg_to_rad(kick_degrees) * Settings.camera_recoil


func _apply_pitch() -> void:
	head.rotation.x = clampf(_pitch + _recoil_pitch, -MAX_PITCH, MAX_PITCH)


func _apply_settings() -> void:
	camera.fov = Settings.field_of_view
