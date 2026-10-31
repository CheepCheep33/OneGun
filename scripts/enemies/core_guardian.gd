class_name CoreGuardian
extends Enemy
## The wave 20 boss (plan: Core Guardian): the work order itself. It fights in four phases, one
## per regular behaviour, by health: the Warden's swing and ground slam (above 75%), the shooter's
## volley from range (above 50%), the Foreman's drones with a slower volley (above 25%), and the
## Sentinel's shield arcs and laser sweep with the swing (the rest). Its armour is heavy and its
## core is shut while it fights; crossing a phase line makes it stop and vent for VENT_TIME, the
## core opens (glows) and hits on it ignore the armour (EnemyDefinition weak point). Its first kill
## drops the run's Legendary (first_kill_legendary). Every telegraph is part of the scene.

signal phase_changed(index: int)

enum Phase { CHASE, SWING, SLAM, HOLD, VOLLEY, SUMMON, SWEEP, RECOVER, VENT }

const PHASE_LINES := [0.75, 0.5, 0.25]
const VENT_TIME := 4.5
const ATTACK_GRACE := 0.6
const RECOVER_TIME := 0.6
const SLAM_COOLDOWN := 8.0
const SLAM_TELEGRAPH := 1.2
const SLAM_RADIUS := 6.0
const SLAM_DAMAGE := 30.0
const SLAM_RANGE := 7.0
const SLAM_ESCAPE_HEIGHT := 1.0
const VOLLEY_BOLTS := 5
const VOLLEY_FAN_DEGREES := 7.0
const VOLLEY_COOLDOWN := 2.4
const SUMMON_COOLDOWN := 12.0
const SUMMON_TELEGRAPH := 1.2
const SUMMON_COUNT := 3
const SWEEP_COOLDOWN := 9.0
const SWEEP_DAMAGE := 28.0
const ARC_SPEED := 1.6
const SWING_COLOR := Color(1.0, 0.45, 0.0)
const SLAM_COLOR := Color(1.0, 0.6, 0.1)
const BOLT_COLOR := Color(1.0, 0.75, 0.2)
const SUMMON_COLOR := Color(0.35, 0.85, 0.95)
const SWEEP_COLOR := Color(1.0, 0.12, 0.1)
const VENT_COLOR := Color(0.4, 0.9, 1.0)

## 0 to 3: which behaviour it fights with.
var fight_phase := 0
var phase := Phase.CHASE
var arcs: BossParts.Arcs
var sweep: BossParts.Sweep
var _phase_time := 0.0
var _slam_cooldown := 4.0
var _volley_cooldown := 1.5
var _summon_cooldown := 2.0
var _sweep_cooldown := 3.0
var _rng := RandomNumberGenerator.new()

@onready var _eye: Node3D = $Visual/Eye
@onready var _ring: MeshInstance3D = $Ring
@onready var _core_open: Node3D = $Visual/CoreOpen
@onready var _core_shut: Node3D = $Visual/CoreShut
@onready var _attack_sound: AudioStreamPlayer3D = $AttackSound


func _ready() -> void:
	arcs = BossParts.Arcs.new($Arcs)
	arcs.speed = ARC_SPEED
	sweep = BossParts.Sweep.new($Sweep)
	sweep.damage = SWEEP_DAMAGE
	super()


func _reset_behaviour() -> void:
	fight_phase = 0
	phase = Phase.CHASE
	_phase_time = 0.0
	_slam_cooldown = 4.0
	_volley_cooldown = 1.5
	_summon_cooldown = 2.0
	_sweep_cooldown = 3.0
	_ring.visible = false
	arcs.set_raised(false)
	sweep.hide()
	_set_core_open(false)


## The phase its health puts it in (0 to 3).
func phase_for_health() -> int:
	var fraction := health_fraction()
	var index := 0
	for line in PHASE_LINES:
		if fraction <= line:
			index += 1
	return index


func is_venting() -> bool:
	return phase == Phase.VENT


func _weak_point_open() -> bool:
	return is_venting()


func _physics_process(delta: float) -> void:
	super(delta)
	if not is_alive:
		return
	arcs.tick(delta * (0.0 if stun_left > 0.0 else 1.0))
	if sweep.tick(delta, self, target):
		target.take_damage(sweep.damage, global_position)


func _behave(delta: float) -> void:
	_phase_time += delta
	_slam_cooldown = maxf(_slam_cooldown - delta, 0.0)
	_volley_cooldown = maxf(_volley_cooldown - delta, 0.0)
	_summon_cooldown = maxf(_summon_cooldown - delta, 0.0)
	_sweep_cooldown = maxf(_sweep_cooldown - delta, 0.0)
	if phase != Phase.VENT and phase_for_health() > fight_phase:
		_start_vent()
	if not target_alive():
		_set_horizontal_velocity(Vector3.ZERO)
		return
	var distance := _distance_to_target()
	match phase:
		Phase.VENT:
			_set_horizontal_velocity(Vector3.ZERO)
			if _phase_time >= VENT_TIME:
				_end_vent()
		Phase.CHASE, Phase.HOLD:
			if _start_special(distance):
				return
			if fight_phase == 1 or fight_phase == 2:
				_keep_range(delta, distance)
			elif distance <= definition.attack_range:
				_enter(Phase.SWING)
				_set_horizontal_velocity(Vector3.ZERO)
			else:
				_chase_target(delta)
		Phase.SWING:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			if _phase_time >= definition.attack_windup:
				_attack_sound.pitch_scale = 0.75
				_attack_sound.play()
				if distance <= definition.attack_range + ATTACK_GRACE:
					target.take_damage(definition.attack_damage, global_position)
				_enter(Phase.RECOVER)
		Phase.SLAM:
			_set_horizontal_velocity(Vector3.ZERO)
			var progress := clampf(_phase_time / SLAM_TELEGRAPH, 0.0, 1.0)
			_ring.visible = true
			var ring_scale := maxf(SLAM_RADIUS * progress, 0.2)
			_ring.scale = Vector3(ring_scale, 1.0, ring_scale)
			if _phase_time >= SLAM_TELEGRAPH:
				_slam()
		Phase.VOLLEY:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			if _phase_time >= definition.attack_windup:
				_fire_volley()
		Phase.SUMMON:
			_set_horizontal_velocity(Vector3.ZERO)
			if _phase_time >= SUMMON_TELEGRAPH:
				_summon_cooldown = SUMMON_COOLDOWN
				_attack_sound.pitch_scale = 1.4
				_attack_sound.play()
				summon_requested.emit(self, SUMMON_COUNT)
				_enter(Phase.RECOVER)
		Phase.SWEEP:
			_set_horizontal_velocity(Vector3.ZERO)
			if not sweep.active:
				_sweep_cooldown = SWEEP_COOLDOWN
				_enter(Phase.RECOVER)
		Phase.RECOVER:
			_set_horizontal_velocity(Vector3.ZERO)
			if _phase_time >= RECOVER_TIME:
				_enter(Phase.CHASE)


## Starts the phase's special when it is ready. True when it started one.
func _start_special(distance: float) -> bool:
	match fight_phase:
		0:
			if _slam_cooldown <= 0.0 and distance <= SLAM_RANGE:
				_slam_cooldown = SLAM_COOLDOWN
				_enter(Phase.SLAM)
			else:
				return false
		1, 2:
			if fight_phase == 2 and _summon_cooldown <= 0.0:
				_enter(Phase.SUMMON)
			elif _volley_cooldown <= 0.0 and distance <= definition.max_fire_range and has_line_of_sight():
				_enter(Phase.VOLLEY)
			else:
				return false
		3:
			if _sweep_cooldown <= 0.0 and has_line_of_sight():
				sweep.start(target.global_position, global_position)
				_attack_sound.pitch_scale = 0.6
				_attack_sound.play()
				_enter(Phase.SWEEP)
			else:
				return false
	_set_horizontal_velocity(Vector3.ZERO)
	return true


func _keep_range(delta: float, distance: float) -> void:
	if distance > definition.preferred_range or not has_line_of_sight():
		_chase_target(delta)
	elif distance < definition.retreat_range:
		_face(_to_target())
		_set_horizontal_velocity(-_to_target().normalized() * definition.move_speed * 0.7 * _speed_scale())
	else:
		_face(_to_target())
		_set_horizontal_velocity(Vector3.ZERO)


func _slam() -> void:
	_ring.visible = false
	_attack_sound.pitch_scale = 0.5
	_attack_sound.play()
	Fx.ring(self, global_position + Vector3.UP * 0.05, SLAM_RADIUS, SLAM_COLOR, 0.45)
	if target_alive() and _distance_to_target() <= SLAM_RADIUS and target.is_on_floor() \
			and absf(target.global_position.y - global_position.y) < SLAM_ESCAPE_HEIGHT:
		target.take_damage(SLAM_DAMAGE)
	_enter(Phase.RECOVER)


func _fire_volley() -> void:
	_volley_cooldown = VOLLEY_COOLDOWN * (1.5 if fight_phase == 2 else 1.0)
	_enter(Phase.RECOVER)
	var pool := ProjectilePool.current
	if pool == null or not target_alive():
		return
	var origin := _eye.global_position
	var aim := (target.global_position + Vector3.UP * 1.0 - origin).normalized()
	var spread := Shooter.spread_degrees_at(definition, _distance_to_target())
	_attack_sound.pitch_scale = randf_range(0.8, 0.9)
	_attack_sound.play()
	for i in VOLLEY_BOLTS:
		var fan := deg_to_rad(VOLLEY_FAN_DEGREES * (i - (VOLLEY_BOLTS - 1) * 0.5))
		var direction := Shooter.scatter(aim.rotated(Vector3.UP, fan), spread, _rng)
		pool.fire_enemy_bolt(self, origin, direction * definition.projectile_speed, definition.attack_damage * 0.6,
			BOLT_COLOR, definition.projectile_lifetime)


func _start_vent() -> void:
	_ring.visible = false
	sweep.hide()
	arcs.set_raised(false)
	_set_core_open(true)
	_attack_sound.pitch_scale = 1.2
	_attack_sound.play()
	_enter(Phase.VENT)


func _end_vent() -> void:
	_set_core_open(false)
	fight_phase = mini(fight_phase + 1, 3)
	arcs.set_raised(fight_phase == 3)
	_slam_cooldown = 2.0
	_volley_cooldown = 1.0
	_summon_cooldown = 1.0
	_sweep_cooldown = 2.0
	_enter(Phase.CHASE)
	phase_changed.emit(fight_phase)


func _set_core_open(value: bool) -> void:
	_core_open.visible = value
	_core_shut.visible = not value


func _on_death() -> void:
	_ring.visible = false
	arcs.set_raised(false)
	sweep.hide()


func _visual_scale() -> float:
	match phase:
		Phase.SWING:
			return 1.0 + 0.08 * clampf(_phase_time / definition.attack_windup, 0.0, 1.0)
		Phase.SLAM:
			return 1.0 + 0.15 * clampf(_phase_time / SLAM_TELEGRAPH, 0.0, 1.0)
		Phase.SUMMON:
			return 1.0 + 0.1 * clampf(_phase_time / SUMMON_TELEGRAPH, 0.0, 1.0)
		Phase.VENT:
			return 0.94
	return 1.0


func _visual_glow() -> Color:
	match phase:
		Phase.SWING:
			return SWING_COLOR * (0.5 + 1.5 * clampf(_phase_time / definition.attack_windup, 0.0, 1.0))
		Phase.SLAM:
			return SLAM_COLOR * (0.6 + 1.8 * clampf(_phase_time / SLAM_TELEGRAPH, 0.0, 1.0))
		Phase.VOLLEY:
			return BOLT_COLOR * (0.4 + 2.0 * clampf(_phase_time / definition.attack_windup, 0.0, 1.0))
		Phase.SUMMON:
			return SUMMON_COLOR * (0.5 + 2.0 * clampf(_phase_time / SUMMON_TELEGRAPH, 0.0, 1.0))
		Phase.SWEEP:
			if not sweep.is_firing():
				return SWEEP_COLOR * (0.5 + 2.0 * clampf(_phase_time / sweep.telegraph, 0.0, 1.0))
			return SWEEP_COLOR * 1.5
		Phase.VENT:
			return VENT_COLOR * 0.8
	return Color.BLACK


func _enter(new_phase: Phase) -> void:
	phase = new_phase
	_phase_time = 0.0
	if new_phase != Phase.SLAM:
		_ring.visible = false
