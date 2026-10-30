class_name Fx
extends RefCounted
## Short-lived placeholder combat effects. The frequent ones (tracers, impacts, damage numbers,
## death bursts) come from the scene's FxPool and never allocate during a wave; the rare ones
## (the Warden's ring, a sound that outlives its enemy) are made on the spot and free themselves.

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


## Compiles every effect, enemy and drop shader before the first wave (see FxPool.warm_up).
static func warm_up(context: Node, camera: Camera3D) -> void:
	var pool := _pool(context)
	if pool:
		await pool.warm_up(camera)


## A flat ring on the floor that expands to `radius` and fades: the Warden's slam.
static func ring(context: Node, position: Vector3, radius: float, color: Color, duration := 0.4) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.82
	mesh.outer_radius = 1.0
	mesh.rings = 32
	mesh.ring_segments = 6
	var material := _unshaded(Color(color.r, color.g, color.b, 0.85))
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not _add(context, node):
		return
	node.global_position = position
	node.scale = Vector3(0.3, 0.3, 0.3)
	var tween := node.create_tween().set_parallel()
	tween.tween_property(node, "scale", Vector3(radius, 0.3, radius), duration).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(node.queue_free)


## Positional sound that outlives the node that triggered it (for example a dying enemy).
static func sound_at(context: Node, stream: AudioStream, position: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.unit_size = 8.0
	if not _add(context, player):
		return
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()


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


static func _add(context: Node, node: Node) -> bool:
	var root := context.get_tree().current_scene if context.is_inside_tree() else null
	if root == null:
		node.free()
		return false
	root.add_child(node)
	return true


static func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
