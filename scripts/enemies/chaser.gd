class_name Chaser
extends Enemy
## Melee enemy: walks to the player along the navmesh, telegraphs, then strikes at close range.
## The runner is a chaser with a faster definition.

enum Phase { CHASE, WINDUP, RECOVER }

## Extra reach when the windup ends, so a player standing still is always hit
## but one who backs off during the telegraph escapes.
const ATTACK_GRACE := 0.5

var phase := Phase.CHASE
var _phase_time := 0.0

@onready var _attack_sound: AudioStreamPlayer3D = $AttackSound


func _reset_behaviour() -> void:
	phase = Phase.CHASE
	_phase_time = 0.0


func _behave(delta: float) -> void:
	_phase_time += delta
	match phase:
		Phase.CHASE:
			if not target_alive():
				_set_horizontal_velocity(Vector3.ZERO)
				return
			if _distance_to_target() <= definition.attack_range:
				_enter(Phase.WINDUP)
				_set_horizontal_velocity(Vector3.ZERO)
				return
			_chase_target(delta)
		Phase.WINDUP:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			if _phase_time >= definition.attack_windup:
				_strike()
		Phase.RECOVER:
			_set_horizontal_velocity(Vector3.ZERO)
			if _phase_time >= definition.attack_cooldown:
				_enter(Phase.CHASE)


func _strike() -> void:
	_attack_sound.play()
	if target_alive() and _distance_to_target() <= definition.attack_range + ATTACK_GRACE:
		target.take_damage(definition.attack_damage)
	_enter(Phase.RECOVER)


func _visual_scale() -> float:
	if phase == Phase.WINDUP:
		return 1.0 + 0.15 * clampf(_phase_time / definition.attack_windup, 0.0, 1.0)
	return 1.0


func _visual_glow() -> Color:
	if phase == Phase.WINDUP:
		var progress := clampf(_phase_time / definition.attack_windup, 0.0, 1.0)
		return Color(1.0, 0.45, 0.0) * (0.5 + 1.5 * progress)
	return Color.BLACK


func _enter(new_phase: Phase) -> void:
	phase = new_phase
	_phase_time = 0.0
