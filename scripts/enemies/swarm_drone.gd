class_name SwarmDrone
extends Enemy
## Fast, fragile flier that comes in groups (plan: Swarm drone, first seen in wave 7). Hovers at
## head height, dives in for a short zap, then backs off before coming again. Counts as half an
## enemy toward the alive cap (definition.counts_as).

enum Phase { APPROACH, ZAP, BACK_OFF }

const BOB_SPEED := 7.0
const BOB_AMOUNT := 0.12
const BACK_OFF_TIME := 0.7
const ZAP_GRACE := 0.4
const ZAP_COLOR := Color(0.4, 0.9, 1.0)

var phase := Phase.APPROACH
var _phase_time := 0.0
var _bob_time := 0.0
var _back_off_direction := Vector3.ZERO

@onready var _zap_sound: AudioStreamPlayer3D = $AttackSound


func _reset_behaviour() -> void:
	phase = Phase.APPROACH
	_phase_time = 0.0
	_bob_time = randf() * TAU
	_back_off_direction = Vector3.ZERO


func _behave(delta: float) -> void:
	_phase_time += delta
	if not target_alive():
		_set_horizontal_velocity(Vector3.ZERO)
		return
	match phase:
		Phase.APPROACH:
			if _distance_to_target() <= definition.attack_range:
				_enter(Phase.ZAP)
				_set_horizontal_velocity(Vector3.ZERO)
				return
			_chase_target(delta)
		Phase.ZAP:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			if _phase_time >= definition.attack_windup:
				_zap_sound.play()
				if _distance_to_target() <= definition.attack_range + ZAP_GRACE:
					target.take_damage(definition.attack_damage)
				_back_off_direction = -_to_target().normalized()
				_enter(Phase.BACK_OFF)
		Phase.BACK_OFF:
			_set_horizontal_velocity(_back_off_direction * definition.move_speed * 0.8)
			_face(-_back_off_direction)
			if _phase_time >= maxf(BACK_OFF_TIME, definition.attack_cooldown):
				_enter(Phase.APPROACH)


func _visual_tick(delta: float) -> void:
	_bob_time += delta * BOB_SPEED
	_visual.position.y = definition.hover_height + sin(_bob_time) * BOB_AMOUNT - definition.hover_height * 0.0


func _visual_glow() -> Color:
	if phase == Phase.ZAP:
		return ZAP_COLOR * (0.5 + 2.0 * clampf(_phase_time / definition.attack_windup, 0.0, 1.0))
	return Color.BLACK


func _enter(new_phase: Phase) -> void:
	phase = new_phase
	_phase_time = 0.0
