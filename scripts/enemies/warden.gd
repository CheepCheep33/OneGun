class_name Warden
extends Enemy
## The wave 5 boss (plan: Warden): a heavy built from the chaser's swing plus two telegraphed
## specials. Charge: stops, glows red, then rushes in a straight line. Ground slam: raises up while
## an orange ring grows on the floor, then slams; anyone inside the ring who is still on the
## ground takes the hit, so jumping dodges it.

enum Phase {
	CHASE, SWING_WINDUP, SWING_RECOVER,
	CHARGE_TELEGRAPH, CHARGING, CHARGE_RECOVER,
	SLAM_TELEGRAPH, SLAM_RECOVER,
}

const ATTACK_GRACE := 0.6
const CHARGE_COOLDOWN := 7.0
const CHARGE_TELEGRAPH := 0.9
const CHARGE_SPEED := 13.0
const CHARGE_MAX_TIME := 1.4
const CHARGE_DAMAGE := 28.0
const CHARGE_HIT_RANGE := 2.2
const CHARGE_MIN_RANGE := 5.0
const CHARGE_MAX_RANGE := 16.0
const CHARGE_RECOVER := 1.0
const SLAM_COOLDOWN := 9.0
const SLAM_TELEGRAPH := 1.1
const SLAM_RADIUS := 5.5
const SLAM_DAMAGE := 30.0
## A player this far above the Warden (a jump) is out of the slam.
const SLAM_ESCAPE_HEIGHT := 1.0
const SLAM_RANGE := 7.0
const SLAM_RECOVER := 1.4
const CHARGE_COLOR := Color(1.0, 0.15, 0.1)
const SLAM_COLOR := Color(1.0, 0.6, 0.1)

var phase := Phase.CHASE
var _phase_time := 0.0
## Both specials start part-way through their cooldown so the fight opens with the swing.
var _charge_cooldown := 3.0
var _slam_cooldown := 5.5
var _charge_direction := Vector3.ZERO

@onready var _attack_sound: AudioStreamPlayer3D = $AttackSound
@onready var _ring: MeshInstance3D = $Ring


func _reset_behaviour() -> void:
	phase = Phase.CHASE
	_phase_time = 0.0
	_charge_cooldown = 3.0
	_slam_cooldown = 5.5
	_charge_direction = Vector3.ZERO
	_ring.visible = false


func _behave(delta: float) -> void:
	_phase_time += delta
	_charge_cooldown = maxf(_charge_cooldown - delta, 0.0)
	_slam_cooldown = maxf(_slam_cooldown - delta, 0.0)
	if not target_alive():
		_set_horizontal_velocity(Vector3.ZERO)
		return
	var distance := _distance_to_target()
	match phase:
		Phase.CHASE:
			if distance <= definition.attack_range:
				_enter(Phase.SWING_WINDUP)
				_set_horizontal_velocity(Vector3.ZERO)
			elif distance <= SLAM_RANGE and _slam_cooldown <= 0.0:
				_enter(Phase.SLAM_TELEGRAPH)
				_set_horizontal_velocity(Vector3.ZERO)
			elif distance >= CHARGE_MIN_RANGE and distance <= CHARGE_MAX_RANGE and _charge_cooldown <= 0.0 \
					and has_line_of_sight():
				_enter(Phase.CHARGE_TELEGRAPH)
				_set_horizontal_velocity(Vector3.ZERO)
			else:
				_chase_target(delta)
		Phase.SWING_WINDUP:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			if _phase_time >= definition.attack_windup:
				_attack_sound.play()
				if distance <= definition.attack_range + ATTACK_GRACE:
					target.take_damage(definition.attack_damage)
				_enter(Phase.SWING_RECOVER)
		Phase.SWING_RECOVER:
			_set_horizontal_velocity(Vector3.ZERO)
			if _phase_time >= definition.attack_cooldown:
				_enter(Phase.CHASE)
		Phase.CHARGE_TELEGRAPH:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			if _phase_time >= CHARGE_TELEGRAPH:
				_charge_direction = _to_target().normalized()
				_charge_cooldown = CHARGE_COOLDOWN
				_attack_sound.pitch_scale = 0.7
				_attack_sound.play()
				_enter(Phase.CHARGING)
		Phase.CHARGING:
			_set_horizontal_velocity(_charge_direction * CHARGE_SPEED)
			_face(_charge_direction)
			if distance <= CHARGE_HIT_RANGE:
				target.take_damage(CHARGE_DAMAGE)
				_enter(Phase.CHARGE_RECOVER)
			elif _phase_time >= CHARGE_MAX_TIME or _hit_wall():
				_enter(Phase.CHARGE_RECOVER)
		Phase.CHARGE_RECOVER:
			_set_horizontal_velocity(Vector3.ZERO)
			if _phase_time >= CHARGE_RECOVER:
				_enter(Phase.CHASE)
		Phase.SLAM_TELEGRAPH:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			var progress := clampf(_phase_time / SLAM_TELEGRAPH, 0.0, 1.0)
			_ring.visible = true
			var ring_scale := maxf(SLAM_RADIUS * progress, 0.2)
			_ring.scale = Vector3(ring_scale, 1.0, ring_scale)
			if _phase_time >= SLAM_TELEGRAPH:
				_slam()
		Phase.SLAM_RECOVER:
			_set_horizontal_velocity(Vector3.ZERO)
			if _phase_time >= SLAM_RECOVER:
				_enter(Phase.CHASE)


func _slam() -> void:
	_ring.visible = false
	_slam_cooldown = SLAM_COOLDOWN
	_attack_sound.pitch_scale = 0.55
	_attack_sound.play()
	Fx.ring(self, global_position + Vector3.UP * 0.05, SLAM_RADIUS, SLAM_COLOR, 0.45)
	# Grounded players inside the ring are hit; a jump (height, or leaving the floor) escapes it.
	if target_alive() and _distance_to_target() <= SLAM_RADIUS and target.is_on_floor() \
			and absf(target.global_position.y - global_position.y) < SLAM_ESCAPE_HEIGHT:
		target.take_damage(SLAM_DAMAGE)
	_enter(Phase.SLAM_RECOVER)


## True when the charge ran into something other than the player.
func _hit_wall() -> bool:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_collider() is Player:
			continue
		if collision.get_normal().dot(_charge_direction) < -0.5:
			return true
	return false


func _visual_scale() -> float:
	match phase:
		Phase.SWING_WINDUP:
			return 1.0 + 0.1 * clampf(_phase_time / definition.attack_windup, 0.0, 1.0)
		Phase.SLAM_TELEGRAPH:
			return 1.0 + 0.2 * clampf(_phase_time / SLAM_TELEGRAPH, 0.0, 1.0)
		Phase.CHARGE_TELEGRAPH:
			return 1.0 - 0.08 * clampf(_phase_time / CHARGE_TELEGRAPH, 0.0, 1.0)
	return 1.0


func _visual_glow() -> Color:
	match phase:
		Phase.SWING_WINDUP:
			return Color(1.0, 0.45, 0.0) * (0.5 + 1.5 * clampf(_phase_time / definition.attack_windup, 0.0, 1.0))
		Phase.CHARGE_TELEGRAPH:
			return CHARGE_COLOR * (0.6 + 2.0 * clampf(_phase_time / CHARGE_TELEGRAPH, 0.0, 1.0))
		Phase.CHARGING:
			return CHARGE_COLOR * 2.0
		Phase.SLAM_TELEGRAPH:
			return SLAM_COLOR * (0.6 + 1.8 * clampf(_phase_time / SLAM_TELEGRAPH, 0.0, 1.0))
	return Color.BLACK


func _enter(new_phase: Phase) -> void:
	phase = new_phase
	_phase_time = 0.0
	if new_phase != Phase.SLAM_TELEGRAPH:
		_ring.visible = false
