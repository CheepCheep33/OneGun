class_name Foreman
extends Enemy
## The wave 10 boss (plan: Foreman): a shooter that calls in swarm drones and lays molten pools.
## It keeps its distance like the shooter and fires a three-bolt volley after a glowing telegraph.
## Summon: it stops and glows cyan, then the wave runner brings in drones from its reserve
## (EnemyDefinition.summon_scene, at most max_summons alive; they pay credits but drop nothing,
## do not count toward the wave and fall with the Foreman). Molten pool: it glows orange, a
## warning ring grows where the player stood, then the floor there burns grounded players for a
## few seconds; a jump or a step out avoids it. The pools are part of the scene (three, reused),
## so a cast builds nothing and the warm-up draws their materials.

enum Phase { APPROACH, HOLD, AIM, RECOVER, SUMMON, CAST }

const RANGE_SLACK := 3.0
const RECOVER_TIME := 0.5
const VOLLEY_BOLTS := 3
## Angle between the volley's bolts, on top of the definition's aim error.
const VOLLEY_FAN_DEGREES := 6.0
const SUMMON_TELEGRAPH := 1.2
const SUMMON_COUNT := 3
const SUMMON_COOLDOWN := 14.0
const CAST_TIME := 0.6
const POOL_COOLDOWN := 7.0
const POOL_WARNING := 1.2
const POOL_DURATION := 6.0
const POOL_RADIUS := 2.6
const POOL_DAMAGE_PER_SECOND := 16.0
## A player this far above the floor of a pool (a jump) is not burned.
const POOL_ESCAPE_HEIGHT := 0.6
const BOLT_COLOR := Color(1.0, 0.75, 0.2)
const SUMMON_COLOR := Color(0.35, 0.85, 0.95)
const POOL_COLOR := Color(1.0, 0.4, 0.05)


## One reusable molten pool: a warning ring that grows, then the molten disc.
class Pool:
	extends RefCounted
	var node: Node3D
	var warning: MeshInstance3D
	var molten: MeshInstance3D
	var age := 0.0
	var active := false

	func is_burning() -> bool:
		return active and age >= POOL_WARNING


var phase := Phase.APPROACH
var pools: Array[Pool] = []
var _phase_time := 0.0
var _volley_cooldown := 0.0
## Both specials start part-way through their cooldown so the fight opens with the volley.
var _summon_cooldown := 6.0
var _pool_cooldown := 3.5
var _rng := RandomNumberGenerator.new()

@onready var _eye: Node3D = $Visual/Eye
@onready var _fire_sound: AudioStreamPlayer3D = $AttackSound


func _ready() -> void:
	for node in $Pools.get_children():
		var pool := Pool.new()
		pool.node = node
		pool.warning = node.get_node("Warning")
		pool.molten = node.get_node("Molten")
		pools.append(pool)
	super()


func _reset_behaviour() -> void:
	phase = Phase.APPROACH
	_phase_time = 0.0
	_volley_cooldown = definition.attack_cooldown * 0.5
	_summon_cooldown = 6.0
	_pool_cooldown = 3.5
	_hide_pools()


func _physics_process(delta: float) -> void:
	super(delta)
	if is_alive:
		_tick_pools(delta)


func _behave(delta: float) -> void:
	_phase_time += delta
	_volley_cooldown = maxf(_volley_cooldown - delta, 0.0)
	_summon_cooldown = maxf(_summon_cooldown - delta, 0.0)
	_pool_cooldown = maxf(_pool_cooldown - delta, 0.0)
	if not target_alive():
		_set_horizontal_velocity(Vector3.ZERO)
		return
	var distance := _distance_to_target()
	match phase:
		Phase.APPROACH, Phase.HOLD:
			if _start_special(distance):
				return
			if phase == Phase.APPROACH:
				_chase_target(delta)
				if distance <= definition.preferred_range and has_line_of_sight():
					_enter(Phase.HOLD)
			else:
				_face(_to_target())
				if distance < definition.retreat_range:
					_set_horizontal_velocity(-_to_target().normalized() * definition.move_speed * 0.7 * _speed_scale())
				elif distance > definition.preferred_range + RANGE_SLACK or not has_line_of_sight():
					_enter(Phase.APPROACH)
				else:
					_set_horizontal_velocity(Vector3.ZERO)
		Phase.AIM:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			if _phase_time >= definition.attack_windup:
				_fire_volley()
		Phase.RECOVER:
			_set_horizontal_velocity(Vector3.ZERO)
			if _phase_time >= RECOVER_TIME:
				_enter(Phase.HOLD if distance <= definition.preferred_range + RANGE_SLACK else Phase.APPROACH)
		Phase.SUMMON:
			_set_horizontal_velocity(Vector3.ZERO)
			if _phase_time >= SUMMON_TELEGRAPH:
				_summon_cooldown = SUMMON_COOLDOWN
				_fire_sound.pitch_scale = 1.4
				_fire_sound.play()
				summon_requested.emit(self, SUMMON_COUNT)
				_enter(Phase.RECOVER)
		Phase.CAST:
			_set_horizontal_velocity(Vector3.ZERO)
			_face(_to_target())
			if _phase_time >= CAST_TIME:
				_pool_cooldown = POOL_COOLDOWN
				lay_pool(target.global_position)
				_enter(Phase.RECOVER)


## Picks the next attack when one is ready: summon, then pool, then volley. True when it started one.
func _start_special(distance: float) -> bool:
	if _summon_cooldown <= 0.0:
		_enter(Phase.SUMMON)
	elif _pool_cooldown <= 0.0 and has_line_of_sight():
		_enter(Phase.CAST)
	elif _volley_cooldown <= 0.0 and distance <= definition.max_fire_range and has_line_of_sight():
		_enter(Phase.AIM)
	else:
		return false
	_set_horizontal_velocity(Vector3.ZERO)
	return true


func _fire_volley() -> void:
	_volley_cooldown = definition.attack_cooldown
	_enter(Phase.RECOVER)
	var pool := ProjectilePool.current
	if pool == null or not target_alive():
		return
	var origin := _eye.global_position
	var aim := (target.global_position + Vector3.UP * 1.0 - origin).normalized()
	var spread := Shooter.spread_degrees_at(definition, _distance_to_target())
	_fire_sound.pitch_scale = randf_range(0.8, 0.9)
	_fire_sound.play()
	for i in VOLLEY_BOLTS:
		var fan := deg_to_rad(VOLLEY_FAN_DEGREES * (i - (VOLLEY_BOLTS - 1) * 0.5))
		var direction := Shooter.scatter(aim.rotated(Vector3.UP, fan), spread, _rng)
		pool.fire_enemy_bolt(self, origin, direction * definition.projectile_speed, definition.attack_damage,
			BOLT_COLOR, definition.projectile_lifetime)


## Lays a pool at `where` (on the floor): the free one, else the oldest. Public for tests.
func lay_pool(where: Vector3) -> Pool:
	var chosen: Pool = null
	for pool in pools:
		if not pool.active:
			chosen = pool
			break
		if chosen == null or pool.age > chosen.age:
			chosen = pool
	chosen.active = true
	chosen.age = 0.0
	chosen.node.global_position = Vector3(where.x, where.y + 0.03, where.z)
	chosen.node.visible = true
	chosen.warning.visible = true
	chosen.molten.visible = false
	chosen.warning.scale = Vector3.ONE * 0.3
	return chosen


## Grows each pool's warning ring, then burns a grounded player inside the molten disc. Scale and
## visibility only, so no material parameter is written.
func _tick_pools(delta: float) -> void:
	for pool in pools:
		if not pool.active:
			continue
		var was_burning := pool.is_burning()
		pool.age += delta
		if pool.age >= POOL_WARNING + POOL_DURATION:
			pool.active = false
			pool.node.visible = false
			continue
		if not pool.is_burning():
			var grown := lerpf(0.3, POOL_RADIUS, clampf(pool.age / POOL_WARNING, 0.0, 1.0))
			pool.warning.scale = Vector3(grown, 1.0, grown)
			continue
		if not was_burning:
			pool.warning.visible = false
			pool.molten.visible = true
			pool.molten.scale = Vector3(POOL_RADIUS, 1.0, POOL_RADIUS)
		if target_alive() and _player_in_pool(pool):
			target.take_damage(POOL_DAMAGE_PER_SECOND * delta, Vector3.INF, true)


func _player_in_pool(pool: Pool) -> bool:
	var offset := target.global_position - pool.node.global_position
	if Vector2(offset.x, offset.z).length() > POOL_RADIUS:
		return false
	return target.is_on_floor() and offset.y < POOL_ESCAPE_HEIGHT


func _hide_pools() -> void:
	for pool in pools:
		pool.active = false
		pool.age = 0.0
		pool.node.visible = false


func _on_death() -> void:
	_hide_pools()


func _visual_scale() -> float:
	match phase:
		Phase.SUMMON:
			return 1.0 + 0.12 * clampf(_phase_time / SUMMON_TELEGRAPH, 0.0, 1.0)
		Phase.CAST:
			return 1.0 + 0.08 * clampf(_phase_time / CAST_TIME, 0.0, 1.0)
	return 1.0


func _visual_glow() -> Color:
	match phase:
		Phase.AIM:
			return BOLT_COLOR * (0.4 + 2.0 * clampf(_phase_time / definition.attack_windup, 0.0, 1.0))
		Phase.SUMMON:
			return SUMMON_COLOR * (0.5 + 2.0 * clampf(_phase_time / SUMMON_TELEGRAPH, 0.0, 1.0))
		Phase.CAST:
			return POOL_COLOR * (0.6 + 2.0 * clampf(_phase_time / CAST_TIME, 0.0, 1.0))
	return Color.BLACK


func _enter(new_phase: Phase) -> void:
	phase = new_phase
	_phase_time = 0.0
