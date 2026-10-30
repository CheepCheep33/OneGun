class_name Fx
extends RefCounted
## Short-lived placeholder combat effects. Every one comes from the scene's FxPool, so nothing is
## created or freed during a wave; this class only finds the pool and forwards to it.

const TRACER_COLOR := FxPool.TRACER_COLOR

static var _pool_cache: FxPool


static func tracer(context: Node, from: Vector3, to: Vector3, _color := TRACER_COLOR) -> void:
	var pool := _pool(context)
	if pool:
		pool.tracer(from, to)


## Spark where a shot hits the world.
static func impact(context: Node, position: Vector3, normal: Vector3) -> void:
	var pool := _pool(context)
	if pool:
		pool.impact(position, normal)


static func damage_number(context: Node, position: Vector3, amount: float, killed: bool) -> void:
	var pool := _pool(context)
	if pool:
		pool.damage_number(position, amount, killed)


## Burst of debris when an enemy dies.
static func burst(context: Node, position: Vector3, color: Color) -> void:
	var pool := _pool(context)
	if pool:
		pool.burst(position, color)


## A flat ring on the floor that expands to `radius` and fades: the Warden's slam.
static func ring(context: Node, position: Vector3, radius: float, color: Color, duration := 0.4) -> void:
	var pool := _pool(context)
	if pool:
		pool.ring(position, radius, color, duration)


## Positional sound that outlives the node that triggered it (for example a dying enemy).
static func sound_at(context: Node, stream: AudioStream, position: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var pool := _pool(context)
	if pool:
		pool.sound_at(stream, position, volume_db, pitch)


## Compiles every effect, projectile, enemy and drop shader before the first wave (see FxPool.warm_up).
static func warm_up(context: Node, camera: Camera3D) -> void:
	var pool := _pool(context)
	if pool:
		await pool.warm_up(camera)


## The running scene's pool, made on first use. Null when there is no scene to put it in.
static func _pool(context: Node) -> FxPool:
	if is_instance_valid(_pool_cache) and _pool_cache.is_inside_tree():
		return _pool_cache
	var root := context.get_tree().current_scene if context.is_inside_tree() else null
	if root == null:
		return null
	var existing := root.get_node_or_null("FxPool")
	if existing is FxPool:
		_pool_cache = existing
	else:
		_pool_cache = FxPool.new()
		root.add_child(_pool_cache)
	return _pool_cache
