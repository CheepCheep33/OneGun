class_name Fx
extends RefCounted
## Short-lived placeholder combat effects.
## Each effect is parented to the current scene and frees itself, so a restart clears them all.

const TRACER_COLOR := Color(1.0, 0.9, 0.55, 0.7)


static func tracer(context: Node, from: Vector3, to: Vector3, color := TRACER_COLOR) -> void:
	var length := from.distance_to(to)
	if length < 0.3:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.015, 0.015, length)
	var material := _unshaded(color)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not _add(context, node):
		return
	var direction := (to - from) / length
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	node.look_at_from_position(from.lerp(to, 0.5), to, up)
	var tween := node.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.07)
	tween.tween_callback(node.queue_free)


## Spark where a shot hits the world.
static func impact(context: Node, position: Vector3, normal: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 8
	mesh.rings = 4
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _unshaded(Color(1.0, 0.85, 0.5))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not _add(context, node):
		return
	node.global_position = position + normal * 0.02
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3.ONE * 0.1, 0.12)
	tween.tween_callback(node.queue_free)


static func damage_number(context: Node, position: Vector3, amount: float, killed: bool) -> void:
	var label := Label3D.new()
	label.text = str(roundi(amount))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0006
	label.font_size = 64 if killed else 48
	label.outline_size = 14
	label.modulate = Color(1.0, 0.55, 0.3) if killed else Color(1.0, 0.95, 0.75)
	label.render_priority = 10
	if not _add(context, label):
		return
	label.global_position = position + Vector3(randf_range(-0.15, 0.15), 0.2, randf_range(-0.15, 0.15))
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "global_position:y", label.global_position.y + 0.7, 0.6) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 0.25).set_delay(0.35)
	tween.chain().tween_callback(label.queue_free)


## Burst of debris when an enemy dies.
static func burst(context: Node, position: Vector3, color: Color) -> void:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 0.14
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.5
	cube.material = material
	var particles := CPUParticles3D.new()
	particles.mesh = cube
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 20
	particles.lifetime = 0.7
	particles.direction = Vector3.UP
	particles.spread = 70.0
	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 7.0
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.2
	if not _add(context, particles):
		return
	particles.global_position = position
	particles.emitting = true
	var tween := particles.create_tween()
	tween.tween_interval(particles.lifetime + 0.3)
	tween.tween_callback(particles.queue_free)


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
