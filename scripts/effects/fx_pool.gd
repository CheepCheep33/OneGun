class_name FxPool
extends Node3D
## The pool behind Fx: tracers, impact sparks, damage numbers, death bursts, death sounds and the
## Warden's slam ring are fixed sets of nodes with shared meshes and materials, shown and hidden
## instead of created and freed. One pool lives under the running scene (Fx makes it on first use)
## and ages every active effect in one _process. This exists for the browser build: every
## allocation, mesh upload and first-use shader compile there lands on the single main thread and
## shows as a hitch, so a wave of fire must not allocate (tests/cases/perf_cases.gd fails if it
## does). warm_up() builds every pool to its cap and draws one of everything below the floor at the
## first bench so the shaders compile before combat.

const TRACER_TIME := 0.07
const IMPACT_TIME := 0.12
const NUMBER_TIME := 0.6
const NUMBER_FADE_START := 0.35
const NUMBER_RISE := 0.7
const BURST_LIFETIME := 0.7
const RING_START_SCALE := 0.3
const RING_ALPHA := 0.85
const MAX_TRACERS := 24
const MAX_IMPACTS := 24
const MAX_NUMBERS := 24
const MAX_BURSTS := 8
const MAX_SOUNDS := 8
const MAX_RINGS := 2
const TRACER_COLOR := Color(1.0, 0.9, 0.55, 0.7)
const IMPACT_COLOR := Color(1.0, 0.85, 0.5)
## Where warm-up draws its samples: just under the floor in front of the camera, inside the view
## but hidden by the floor's depth.
const WARM_UP_DEPTH := -0.7
const WARM_UP_DISTANCE := 4.0
## Enemy scenes to warm up besides the ones the wave data names (side-area enemies, a boss before
## its wave exists). The waves themselves are read by warm_up_scene_paths().
const EXTRA_WARM_UP_SCENES: Array[String] = []
## Used when no wave data loads at all.
const FALLBACK_WARM_UP_SCENES: Array[String] = ["res://scenes/enemies/chaser.tscn"]


class Entry:
	var node: Node3D
	var age := 0.0
	var life := 1.0
	var active := false
	var start_y := 0.0
	## Rings: the radius to grow to.
	var size := 1.0


var warmed_up := false
## The enemy scenes the warm-up drew, for the performance gate.
var warmed_scenes: Array[String] = []

var _tracer_mesh := BoxMesh.new()
var _tracer_material := StandardMaterial3D.new()
var _impact_mesh := SphereMesh.new()
var _impact_material := StandardMaterial3D.new()
var _burst_mesh := BoxMesh.new()
var _ring_mesh := TorusMesh.new()
var _tracers: Array[Entry] = []
var _impacts: Array[Entry] = []
var _numbers: Array[Entry] = []
var _bursts: Array[Entry] = []
var _sounds: Array[Entry] = []
var _rings: Array[Entry] = []


func _ready() -> void:
	name = "FxPool"
	_tracer_mesh.size = Vector3(0.015, 0.015, 1.0)
	_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_material.albedo_color = TRACER_COLOR
	_tracer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_impact_mesh.radius = 0.06
	_impact_mesh.height = 0.12
	_impact_mesh.radial_segments = 8
	_impact_mesh.rings = 4
	_impact_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_impact_material.albedo_color = IMPACT_COLOR
	_burst_mesh.size = Vector3.ONE * 0.14
	var burst_material := StandardMaterial3D.new()
	burst_material.vertex_color_use_as_albedo = true
	_burst_mesh.material = burst_material
	_ring_mesh.inner_radius = 0.82
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 32
	_ring_mesh.ring_segments = 6


## Every enemy scene the authored waves spawn, plus EXTRA_WARM_UP_SCENES, in a stable order. A new
## enemy added to a wave is warmed up without touching this file.
static func warm_up_scene_paths() -> Array[String]:
	var paths: Array[String] = []
	for wave in WaveRunner.all_waves():
		for group in wave.groups:
			if group.enemy_scene != null and not paths.has(group.enemy_scene.resource_path):
				paths.append(group.enemy_scene.resource_path)
	for path in EXTRA_WARM_UP_SCENES:
		if not paths.has(path):
			paths.append(path)
	if paths.is_empty():
		paths.assign(FALLBACK_WARM_UP_SCENES)
	return paths


func active_count() -> int:
	var count := 0
	for pool in [_tracers, _impacts, _numbers, _bursts, _sounds, _rings]:
		for entry in pool:
			if entry.active:
				count += 1
	return count


func tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.3:
		return
	var entry := _acquire(_tracers, MAX_TRACERS, _make_tracer)
	entry.life = TRACER_TIME
	var direction := (to - from) / length
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	entry.node.look_at_from_position(from.lerp(to, 0.5), to, up)
	entry.node.scale = Vector3(1.0, 1.0, length)


func impact(position: Vector3, normal: Vector3) -> void:
	var entry := _acquire(_impacts, MAX_IMPACTS, _make_impact)
	entry.life = IMPACT_TIME
	entry.node.global_position = position + normal * 0.02
	entry.node.scale = Vector3.ONE


func damage_number(position: Vector3, amount: float, killed: bool) -> void:
	var entry := _acquire(_numbers, MAX_NUMBERS, _make_number)
	entry.life = NUMBER_TIME
	var label: Label3D = entry.node
	label.text = str(roundi(amount))
	label.font_size = 64 if killed else 48
	label.modulate = Color(1.0, 0.55, 0.3) if killed else Color(1.0, 0.95, 0.75)
	label.global_position = position + Vector3(randf_range(-0.15, 0.15), 0.2, randf_range(-0.15, 0.15))
	entry.start_y = label.global_position.y


func burst(position: Vector3, color: Color) -> void:
	var entry := _acquire(_bursts, MAX_BURSTS, _make_burst)
	entry.life = BURST_LIFETIME + 0.3
	var particles: CPUParticles3D = entry.node
	particles.global_position = position
	particles.color = color
	particles.restart()


## Positional sound that outlives the node that triggered it (a dying enemy). MAX_SOUNDS at once;
## the oldest is cut when more play.
func sound_at(stream: AudioStream, position: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if stream == null:
		return
	var entry := _acquire(_sounds, MAX_SOUNDS, _make_sound)
	entry.life = INF # released when the stream ends
	var player: AudioStreamPlayer3D = entry.node
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.global_position = position
	player.play()


## A flat ring on the floor that grows to `radius` and fades: the Warden's slam.
func ring(position: Vector3, radius: float, color: Color, duration := 0.4) -> void:
	var entry := _acquire(_rings, MAX_RINGS, _make_ring)
	entry.life = duration
	entry.size = radius
	var node: MeshInstance3D = entry.node
	var material: StandardMaterial3D = node.material_override
	material.albedo_color = Color(color.r, color.g, color.b, RING_ALPHA)
	node.global_position = position
	node.scale = Vector3.ONE * RING_START_SCALE


## Builds every pool to its cap, then draws one of every effect, projectile, enemy and drop for a
## few frames so their shaders compile now, not in the first wave. Everything sits under the floor
## in front of the camera. After this, combat creates no nodes.
func warm_up(camera: Camera3D) -> void:
	if warmed_up or camera == null:
		return
	warmed_up = true
	_fill(_tracers, MAX_TRACERS, _make_tracer)
	_fill(_impacts, MAX_IMPACTS, _make_impact)
	_fill(_numbers, MAX_NUMBERS, _make_number)
	_fill(_bursts, MAX_BURSTS, _make_burst)
	_fill(_sounds, MAX_SOUNDS, _make_sound)
	_fill(_rings, MAX_RINGS, _make_ring)
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var spot := camera.global_position + forward * WARM_UP_DISTANCE
	spot.y = WARM_UP_DEPTH
	tracer(spot + Vector3(-0.5, 0.0, 0.0), spot + Vector3(0.5, 0.0, 0.0))
	impact(spot, Vector3.UP)
	damage_number(spot, 1234567890, false)
	damage_number(spot, 1234567890, true)
	burst(spot, Color.WHITE)
	ring(spot, 1.0, Color.WHITE, 0.3)
	var projectiles := ProjectilePool.current
	if projectiles != null:
		projectiles.show_warm_up_sample(spot)
	var extras: Array[Node] = []
	warmed_scenes = warm_up_scene_paths()
	for path in warmed_scenes:
		var enemy: Node3D = load(path).instantiate()
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		_show_hidden_meshes(enemy) # telegraphs such as the Warden's ring start hidden
		add_child(enemy)
		enemy.global_position = spot
		extras.append(enemy)
	var sample := Items.make(&"long_barrel", Items.Rarity.UNCOMMON)
	var drop := LootDrop.create(sample)
	drop.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(drop)
	drop.global_position = spot
	extras.append(drop)
	for i in 3:
		await get_tree().process_frame
	for extra in extras:
		if is_instance_valid(extra):
			extra.queue_free()
	if is_instance_valid(projectiles):
		projectiles.hide_warm_up_sample()
	for pool in [_tracers, _impacts, _numbers, _bursts, _sounds, _rings]:
		for entry in pool:
			_release(entry)


func _process(delta: float) -> void:
	for entry in _tracers:
		if entry.active and _age(entry, delta):
			_release(entry)
	for entry in _impacts:
		if entry.active:
			if _age(entry, delta):
				_release(entry)
			else:
				entry.node.scale = Vector3.ONE * lerpf(1.0, 0.1, entry.age / entry.life)
	for entry in _numbers:
		if entry.active:
			if _age(entry, delta):
				_release(entry)
			else:
				var t := entry.age / entry.life
				var rise := 1.0 - pow(1.0 - t, 3.0)
				entry.node.global_position.y = entry.start_y + NUMBER_RISE * rise
				var fade := clampf((entry.age - NUMBER_FADE_START) / (entry.life - NUMBER_FADE_START), 0.0, 1.0)
				entry.node.modulate.a = 1.0 - fade
	for entry in _bursts:
		if entry.active and _age(entry, delta):
			_release(entry)
	for entry in _rings:
		if entry.active:
			if _age(entry, delta):
				_release(entry)
			else:
				var t := entry.age / entry.life
				var grown := lerpf(RING_START_SCALE, entry.size, 1.0 - pow(1.0 - t, 2.0))
				entry.node.scale = Vector3(grown, RING_START_SCALE, grown)
				var material: StandardMaterial3D = entry.node.material_override
				material.albedo_color.a = RING_ALPHA * (1.0 - t)
	for entry in _sounds:
		if entry.active:
			entry.age += delta
			if not entry.node.playing:
				_release(entry)


func _age(entry: Entry, delta: float) -> bool:
	entry.age += delta
	return entry.age >= entry.life


## A free entry, a new one while the pool is under its cap (only before warm_up ran), else the
## oldest active one.
func _acquire(pool: Array[Entry], cap: int, make: Callable) -> Entry:
	var oldest: Entry = null
	for entry in pool:
		if not entry.active:
			return _activate(entry)
		if oldest == null or entry.age > oldest.age:
			oldest = entry
	if pool.size() < cap:
		return _activate(_grow(pool, make))
	return _activate(oldest)


func _fill(pool: Array[Entry], cap: int, make: Callable) -> void:
	while pool.size() < cap:
		_grow(pool, make)


func _grow(pool: Array[Entry], make: Callable) -> Entry:
	var entry := Entry.new()
	entry.node = make.call()
	entry.node.visible = false
	add_child(entry.node)
	pool.append(entry)
	return entry


func _activate(entry: Entry) -> Entry:
	entry.active = true
	entry.age = 0.0
	entry.node.visible = true
	return entry


func _release(entry: Entry) -> void:
	entry.active = false
	entry.node.visible = false
	if entry.node is CPUParticles3D:
		entry.node.emitting = false
	elif entry.node is AudioStreamPlayer3D:
		entry.node.stop()


func _show_hidden_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			child.visible = true
		_show_hidden_meshes(child)


func _make_tracer() -> Node3D:
	var node := MeshInstance3D.new()
	node.mesh = _tracer_mesh
	node.material_override = _tracer_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _make_impact() -> Node3D:
	var node := MeshInstance3D.new()
	node.mesh = _impact_mesh
	node.material_override = _impact_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _make_number() -> Node3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0006
	label.outline_size = 14
	label.render_priority = 10
	return label


func _make_burst() -> Node3D:
	var particles := CPUParticles3D.new()
	particles.mesh = _burst_mesh
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 20
	particles.lifetime = BURST_LIFETIME
	particles.direction = Vector3.UP
	particles.spread = 70.0
	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 7.0
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.2
	particles.emitting = false
	return particles


func _make_sound() -> Node3D:
	var player := AudioStreamPlayer3D.new()
	player.unit_size = 8.0
	return player


func _make_ring() -> Node3D:
	var node := MeshInstance3D.new()
	node.mesh = _ring_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 1.0, 1.0, RING_ALPHA)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
