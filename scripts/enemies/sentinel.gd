class_name Sentinel
extends Enemy
## The wave 15 boss (plan: Sentinel): a shield bearer built bigger, with two telegraphed specials.
## Shield arcs: two panels turn around it all fight long and stop every player ray and round (the
## bearer's shield rules), so the player shoots through the gaps or splashes around them; below
## half health they turn faster. Laser sweep: it stops and glows red while a dim line marks where
## the beam starts, then a low beam turns once around it; jump it or put cover between you. Its
## swing follows the bearer's: wind-up, strike, recover.

enum Phase { CHASE, WINDUP, RECOVER, SWEEP }

const ATTACK_GRACE := 0.6
const ARC_SPEED := 1.1
const ARC_SPEED_ENRAGED := 1.9
const SWEEP_COOLDOWN := 10.0
const SWEEP_OPENING := 5.0
const SWEEP_RECOVER := 0.6
const SWEEP_DAMAGE := 26.0
const SWEEP_COLOR := Color(1.0, 0.12, 0.1)
const SWING_COLOR := Color(1.0, 0.45, 0.0)

var phase := Phase.CHASE
var arcs: BossParts.Arcs
var sweep: BossParts.Sweep
var _phase_time := 0.0
var _sweep_cooldown := SWEEP_OPENING

@onready var _attack_sound: AudioStreamPlayer3D = $AttackSound


func _ready() -> void:
	arcs = BossParts.Arcs.new($Arcs)
	sweep = BossParts.Sweep.new($Sweep)
	sweep.damage = SWEEP_DAMAGE
	super()


func _reset_behaviour() -> void:
	phase = Phase.CHASE
	_phase_time = 0.0
	_sweep_cooldown = SWEEP_OPENING
	arcs.set_raised(true)
	arcs.speed = ARC_SPEED
	sweep.hide()


func _physics_process(delta: float) -> void:
	super(delta)
	if not is_alive:
		return
	arcs.speed = ARC_SPEED_ENRAGED if health_fraction() < 0.5 else ARC_SPEED
	arcs.tick(delta * (0.0 if stun_left > 0.0 else 1.0))
	if sweep.tick(delta, self, target):
		target.take_damage(sweep.damage, global_position)


func _behave(delta: float) -> void:
	_phase_time += delta
	_sweep_cooldown = maxf(_sweep_cooldown - delta, 0.0)
	if not target_alive():
		_set_horizontal_velocity(Vector3.ZERO)
		return
	match phase:
		Phase.CHASE:
			if _sweep_cooldown <= 0.0 and has_line_of_sight():
				_enter(Phase.SWEEP)
				sweep.start(target.global_position, global_position)
				_attack_sound.pitch_scale = 0.6
				_attack_sound.play()
				_set_horizontal_velocity(Vector3.ZERO)
			elif _distance_to_target() <= definition.attack_range:
				_enter(Phase.WINDUP)
				_set_horizontal_velocity(Vector3.ZERO)
			else:
				_chase_target(delta)
		Phase.WINDUP:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			if _phase_time >= definition.attack_windup:
				_attack_sound.pitch_scale = 0.8
				_attack_sound.play()
				if _distance_to_target() <= definition.attack_range + ATTACK_GRACE:
					target.take_damage(definition.attack_damage, global_position)
				_enter(Phase.RECOVER)
		Phase.RECOVER:
			_set_horizontal_velocity(Vector3.ZERO)
			if _phase_time >= definition.attack_cooldown:
				_enter(Phase.CHASE)
		Phase.SWEEP:
			_set_horizontal_velocity(Vector3.ZERO)
			if not sweep.active and _phase_time >= sweep.telegraph + sweep.duration + SWEEP_RECOVER:
				_sweep_cooldown = SWEEP_COOLDOWN
				_enter(Phase.CHASE)


func _on_death() -> void:
	arcs.set_raised(false)
	sweep.hide()


func _visual_scale() -> float:
	if phase == Phase.WINDUP:
		return 1.0 + 0.1 * clampf(_phase_time / definition.attack_windup, 0.0, 1.0)
	return 1.0


func _visual_glow() -> Color:
	match phase:
		Phase.WINDUP:
			return SWING_COLOR * (0.5 + 1.5 * clampf(_phase_time / definition.attack_windup, 0.0, 1.0))
		Phase.SWEEP:
			if not sweep.is_firing():
				return SWEEP_COLOR * (0.5 + 2.0 * clampf(_phase_time / sweep.telegraph, 0.0, 1.0))
			return SWEEP_COLOR * 1.5
	return Color.BLACK


func _enter(new_phase: Phase) -> void:
	phase = new_phase
	_phase_time = 0.0
