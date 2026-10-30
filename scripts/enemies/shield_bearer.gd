class_name ShieldBearer
extends Enemy
## Melee enemy behind a frontal shield (plan: Shield bearer, first seen in wave 11). The shield is
## a body on the shield layer (4) in group "shields": every player ray and round stops on it, with
## no pierce and no bounce, so it also covers whatever walks behind it. It lowers the shield to
## attack: the swing's telegraph is the window to hit the bearer from the front. Flanking, blast
## splash and chains reach it with the shield up. Enemy bolts and bodies pass the shield.

enum Phase { CHASE, LOWER, WINDUP, RECOVER, RAISE }

const LOWER_TIME := 0.2
const RAISE_TIME := 0.35
## Extra reach when the windup ends, as for the chaser: a player who backs off escapes.
const ATTACK_GRACE := 0.5
const SHIELD_LAYER := 8
const SHIELD_UP_POSITION := Vector3(0.0, 1.0, -0.75)
const SHIELD_DOWN_POSITION := Vector3(0.0, 0.35, -0.7)
## How far the lowered shield tips forward, in radians.
const SHIELD_DOWN_TILT := -1.25

var phase := Phase.CHASE
var _phase_time := 0.0
## 1 with the shield up, 0 when it is down; drives the shield's pose.
var _raised := 1.0
var shield_up: bool:
	get:
		return _shield.collision_layer != 0

@onready var _shield: StaticBody3D = $Shield
@onready var _attack_sound: AudioStreamPlayer3D = $AttackSound


func _reset_behaviour() -> void:
	phase = Phase.CHASE
	_phase_time = 0.0
	_set_raised(1.0)


func _behave(delta: float) -> void:
	_phase_time += delta
	match phase:
		Phase.CHASE:
			if not target_alive():
				_set_horizontal_velocity(Vector3.ZERO)
				return
			if _distance_to_target() <= definition.attack_range:
				_enter(Phase.LOWER)
				_set_horizontal_velocity(Vector3.ZERO)
				return
			_chase_target(delta)
		Phase.LOWER:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			_set_raised(1.0 - clampf(_phase_time / LOWER_TIME, 0.0, 1.0))
			if _phase_time >= LOWER_TIME:
				_enter(Phase.WINDUP)
		Phase.WINDUP:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			if _phase_time >= definition.attack_windup:
				_strike()
		Phase.RECOVER:
			_set_horizontal_velocity(Vector3.ZERO)
			if _phase_time >= definition.attack_cooldown:
				_enter(Phase.RAISE)
		Phase.RAISE:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			_set_raised(clampf(_phase_time / RAISE_TIME, 0.0, 1.0))
			if _phase_time >= RAISE_TIME:
				_enter(Phase.CHASE)


func _strike() -> void:
	_attack_sound.play()
	if target_alive() and _distance_to_target() <= definition.attack_range + ATTACK_GRACE:
		target.take_damage(definition.attack_damage)
	_enter(Phase.RECOVER)


## Poses the shield between down (0) and up (1). It blocks only when fully up; the layer is written
## only when that changes.
func _set_raised(value: float) -> void:
	_raised = value
	_shield.position = SHIELD_DOWN_POSITION.lerp(SHIELD_UP_POSITION, value)
	_shield.rotation = Vector3(lerpf(SHIELD_DOWN_TILT, 0.0, value), 0.0, 0.0)
	var layer := SHIELD_LAYER if value >= 1.0 else 0
	if _shield.collision_layer != layer:
		_shield.collision_layer = layer


func _on_death() -> void:
	_shield.collision_layer = 0


func _visual_scale() -> float:
	if phase == Phase.WINDUP:
		return 1.0 + 0.12 * clampf(_phase_time / definition.attack_windup, 0.0, 1.0)
	return 1.0


func _visual_glow() -> Color:
	if phase == Phase.WINDUP:
		var progress := clampf(_phase_time / definition.attack_windup, 0.0, 1.0)
		return Color(1.0, 0.45, 0.0) * (0.5 + 1.5 * progress)
	return Color.BLACK


func _enter(new_phase: Phase) -> void:
	phase = new_phase
	_phase_time = 0.0
