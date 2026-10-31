class_name Turret
extends Enemy
## Stationary gun emplacement (plan: Turret, first seen in wave 13). It never moves and must be
## killed to clear the wave. With line of sight it tracks the player with a thin red aim line for
## a long wind-up, locks the line for the last LOCK_TIME (the cue to step aside), then fires one
## fast, heavy bolt. Its weak point is the glowing core on top; the body is armoured. The Scanner
## optic marks it through walls (EnemyDefinition.scanner_marked) and the Rangefinder rewards
## killing it from far away. The aim line is part of the scene and only moves and scales.

enum Phase { IDLE, AIM, RECOVER }

## The aim line stops following the player this long before the shot.
const LOCK_TIME := 0.45
const RECOVER_TIME := 0.6
const BOLT_COLOR := Color(1.0, 0.2, 0.15)
const AIM_COLOR := Color(1.0, 0.15, 0.1)
## The head turns at most this fast (radians a second) while tracking.
const TURN_SPEED := 2.4

var phase := Phase.IDLE
var _phase_time := 0.0
var _cooldown_left := 0.0
var _aim_point := Vector3.ZERO

@onready var _head: Node3D = $Visual/Head
@onready var _muzzle: Node3D = $Visual/Head/Muzzle
@onready var _aim_pivot: Node3D = $AimPivot
@onready var _fire_sound: AudioStreamPlayer3D = $AttackSound


func _reset_behaviour() -> void:
	phase = Phase.IDLE
	_phase_time = 0.0
	_cooldown_left = definition.attack_cooldown * 0.5
	_aim_pivot.visible = false


func _behave(delta: float) -> void:
	_phase_time += delta
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_set_horizontal_velocity(Vector3.ZERO)
	if not target_alive():
		_enter(Phase.IDLE)
		return
	match phase:
		Phase.IDLE:
			_turn_head(delta)
			if _cooldown_left <= 0.0 and _distance_to_target() <= definition.max_fire_range and has_line_of_sight():
				_enter(Phase.AIM)
				_aim_pivot.visible = true
		Phase.AIM:
			if _phase_time < definition.attack_windup - LOCK_TIME:
				_aim_point = target.global_position + Vector3.UP * 1.0
				_turn_head(delta)
			_place_aim_line()
			if _phase_time >= definition.attack_windup:
				_fire()
		Phase.RECOVER:
			if _phase_time >= RECOVER_TIME:
				_enter(Phase.IDLE)


## Turns the body toward the player, no faster than TURN_SPEED.
func _turn_head(delta: float) -> void:
	var to := _to_target()
	if to.length_squared() < 0.0001:
		return
	var wanted := atan2(-to.x, -to.z)
	rotation.y = rotate_toward(rotation.y, wanted, TURN_SPEED * delta * _speed_scale_for_turn())
	_head.rotation.x = 0.0


## A stunned turret stops turning; slows slow the turn. Stagger does not stop a turret.
func _speed_scale_for_turn() -> float:
	if stun_left > 0.0:
		return 0.0
	return (1.0 - slow_share) * speed_modifier


func _place_aim_line() -> void:
	var origin := _muzzle.global_position
	var offset := _aim_point - origin
	var length := offset.length()
	if length < 0.01:
		return
	_aim_pivot.global_position = origin
	_aim_pivot.look_at(_aim_point, Vector3.UP if absf(offset.normalized().y) < 0.99 else Vector3.FORWARD)
	_aim_pivot.scale = Vector3(1.0, 1.0, length)


func _fire() -> void:
	_cooldown_left = definition.attack_cooldown
	_aim_pivot.visible = false
	_enter(Phase.RECOVER)
	var pool := ProjectilePool.current
	if pool == null:
		return
	var origin := _muzzle.global_position
	var direction := (_aim_point - origin).normalized()
	_fire_sound.pitch_scale = randf_range(0.6, 0.7)
	_fire_sound.play()
	pool.fire_enemy_bolt(self, origin, direction * definition.projectile_speed, definition.attack_damage,
		BOLT_COLOR, definition.projectile_lifetime, float(ProjectilePool.PROFILES["heavy_bolt"]["radius"]))


func _on_death() -> void:
	_aim_pivot.visible = false


func _visual_glow() -> Color:
	if phase == Phase.AIM:
		var progress := clampf(_phase_time / definition.attack_windup, 0.0, 1.0)
		return AIM_COLOR * (0.3 + 2.2 * progress)
	return Color.BLACK


func _enter(new_phase: Phase) -> void:
	phase = new_phase
	_phase_time = 0.0
