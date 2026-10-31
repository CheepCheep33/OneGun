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


## `weak` marks a weak-point hit (the heavy's core): the number shows in its own colour.
static func damage_number(context: Node, position: Vector3, amount: float, killed: bool, weak := false) -> void:
	var pool := _pool(context)
	if pool:
		pool.damage_number(position, amount, killed, weak)


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


## A sphere that swells to `radius` and vanishes: an explosive round's blast.
static func blast(context: Node, position: Vector3, radius: float) -> void:
	var pool := _pool(context)
	if pool:
		pool.blast(position, radius)


## A frost-blue sphere that swells to `radius` and vanishes: a Cryo shatter.
static func shatter(context: Node, position: Vector3, radius: float) -> void:
	var pool := _pool(context)
	if pool:
		pool.shatter(position, radius)


## Positional sound that outlives the node that triggered it (for example a dying enemy).
static func sound_at(context: Node, stream: AudioStream, position: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var pool := _pool(context)
	if pool:
		pool.sound_at(stream, position, volume_db, pitch)


## A name tag that follows `owner` (a floor drop) until detach_label or the owner leaves the tree.
static func attach_label(context: Node, owner: Node3D, offset: Vector3, text: String, color: Color) -> void:
	var pool := _pool(context)
	if pool:
		pool.attach_label(owner, offset, text, color)


static func detach_label(context: Node, owner: Node3D) -> void:
	var pool := _pool(context)
	if pool:
		pool.detach_label(owner)


## Compiles every effect, projectile, enemy and drop shader before the first wave, lit by the gun's
## muzzle light and unlit, and puts the 2D labels under `label_parent`, the HUD's canvas layer
## (see FxPool.warm_up).
static func warm_up(context: Node, camera: Camera3D, gun: Pistol = null, label_parent: Node = null) -> void:
	var pool := _pool(context)
	if pool:
		await pool.warm_up(camera, gun, label_parent)


## Draws the current view with the muzzle light on for a couple of frames: for a freshly loaded
## area, whose materials have not met the light yet (see FxPool.warm_up_lighting).
static func warm_up_lighting(context: Node, gun: Pistol) -> void:
	var pool := _pool(context)
	if pool:
		await pool.warm_up_lighting(gun)


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
