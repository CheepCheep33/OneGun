class_name Shooter
extends Enemy
## Ranged enemy: keeps its distance, telegraphs with a growing glow, then fires one slow visible
## bolt the player can sidestep (plan: Shooter, first seen in wave 4). Bolts are simulated
## projectiles from the shared pool.

enum Phase { APPROACH, HOLD, AIM, RECOVER }

## Standing further out than this past the preferred range sends it walking in again.
const RANGE_SLACK := 3.0
const BOLT_COLOR := Color(1.0, 0.55, 0.15)

var phase := Phase.APPROACH
var _phase_time := 0.0
var _cooldown_left := 0.0

@onready var _eye: Node3D = $Visual/Eye
@onready var _fire_sound: AudioStreamPlayer3D = $AttackSound


func _reset_behaviour() -> void:
	phase = Phase.APPROACH
	_phase_time = 0.0
	_cooldown_left = 0.0


func _on_spawned() -> void:
	_cooldown_left = definition.attack_cooldown * 0.5


func _behave(delta: float) -> void:
	_phase_time += delta
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if not target_alive():
		_set_horizontal_velocity(Vector3.ZERO)
		return
	var distance := _distance_to_target()
	match phase:
		Phase.APPROACH:
			_chase_target(delta)
			if distance <= definition.preferred_range and has_line_of_sight():
				_enter(Phase.HOLD)
		Phase.HOLD:
			_face(_to_target())
			if distance < definition.retreat_range:
				# Back away while keeping the gun on the player.
				_set_horizontal_velocity(-_to_target().normalized() * definition.move_speed * 0.7 * _speed_scale())
			elif distance > definition.preferred_range + RANGE_SLACK or not has_line_of_sight():
				_enter(Phase.APPROACH)
				return
			else:
				_set_horizontal_velocity(Vector3.ZERO)
			if _cooldown_left <= 0.0 and has_line_of_sight():
				_enter(Phase.AIM)
		Phase.AIM:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			if _phase_time >= definition.attack_windup:
				_fire()
		Phase.RECOVER:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			if _phase_time >= 0.35:
				_enter(Phase.HOLD)


func _fire() -> void:
	_cooldown_left = definition.attack_cooldown
	_enter(Phase.RECOVER)
	var pool := ProjectilePool.current
	if pool == null or not target_alive():
		return
	var origin := _eye.global_position
	var aim := target.global_position + Vector3.UP * 1.0
	var direction := (aim - origin).normalized()
	_fire_sound.pitch_scale = randf_range(0.9, 1.1)
	_fire_sound.play()
	pool.fire_enemy_bolt(self, origin, direction * definition.projectile_speed, definition.attack_damage,
		BOLT_COLOR, definition.projectile_lifetime)


func _visual_glow() -> Color:
	if phase == Phase.AIM:
		var progress := clampf(_phase_time / definition.attack_windup, 0.0, 1.0)
		return BOLT_COLOR * (0.4 + 2.0 * progress)
	return Color.BLACK


func _enter(new_phase: Phase) -> void:
	phase = new_phase
	_phase_time = 0.0
