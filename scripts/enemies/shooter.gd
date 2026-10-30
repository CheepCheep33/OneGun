class_name Shooter
extends Enemy
## Ranged enemy: fires one slow visible bolt the player can sidestep, after a telegraph of growing
## glow (plan: Shooter, first seen in wave 4). It opens fire from max_fire_range the moment it has
## line of sight, aiming worse the further away it is (spread_near_degrees at preferred_range,
## spread_far_degrees at max_fire_range), and keeps walking in between shots until it holds at
## preferred_range. It never fires without line of sight. Bolts are simulated projectiles from the
## shared pool.

enum Phase { APPROACH, HOLD, AIM, RECOVER }

## Standing further out than this past the preferred range sends it walking in again.
const RANGE_SLACK := 3.0
const RECOVER_TIME := 0.35
const BOLT_COLOR := Color(1.0, 0.55, 0.15)

var phase := Phase.APPROACH
var _phase_time := 0.0
var _cooldown_left := 0.0
## Aim scatter; seedable so a test can reproduce a volley.
var _rng := RandomNumberGenerator.new()

@onready var _eye: Node3D = $Visual/Eye
@onready var _fire_sound: AudioStreamPlayer3D = $AttackSound


## The aim error at `distance` for `definition`, in degrees: the near value at preferred_range or
## closer, the far value at max_fire_range or beyond, linear between.
static func spread_degrees_at(definition: EnemyDefinition, distance: float) -> float:
	var span := definition.max_fire_range - definition.preferred_range
	if span <= 0.001:
		return definition.spread_far_degrees if distance > definition.preferred_range else definition.spread_near_degrees
	var t := clampf((distance - definition.preferred_range) / span, 0.0, 1.0)
	return lerpf(definition.spread_near_degrees, definition.spread_far_degrees, t)


## `direction` turned by a random angle up to `spread_degrees`, even over the cone's area.
static func scatter(direction: Vector3, spread_degrees: float, rng: RandomNumberGenerator) -> Vector3:
	if spread_degrees <= 0.0:
		return direction
	var angle := deg_to_rad(spread_degrees) * sqrt(rng.randf())
	var around := rng.randf() * TAU
	var right := direction.cross(Vector3.UP)
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var up := right.cross(direction).normalized()
	return (direction + (right * cos(around) + up * sin(around)) * tan(angle)).normalized()


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
			elif _cooldown_left <= 0.0 and distance <= definition.max_fire_range and has_line_of_sight():
				# Still closing in, but it can see the player: stop and take the long shot.
				_enter(Phase.AIM)
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
			if _phase_time >= RECOVER_TIME:
				_enter(Phase.HOLD if distance <= definition.preferred_range + RANGE_SLACK else Phase.APPROACH)


func _fire() -> void:
	_cooldown_left = definition.attack_cooldown
	_enter(Phase.RECOVER)
	var pool := ProjectilePool.current
	if pool == null or not target_alive():
		return
	var origin := _eye.global_position
	var aim := target.global_position + Vector3.UP * 1.0
	var direction := scatter((aim - origin).normalized(), spread_degrees_at(definition, _distance_to_target()), _rng)
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
