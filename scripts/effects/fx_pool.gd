class_name FxPool
extends Node3D
## The pool behind Fx: tracers, impact sparks, damage numbers and death bursts are a fixed set of
## nodes with shared meshes and materials, shown and hidden instead of created and freed. One
## pool lives under the running scene (Fx makes it on first use) and ages every active effect in
## one _process. This exists for the browser build: every allocation, mesh upload and first-use
## shader compile there lands on the single main thread and shows as a hitch, so a wave of fire
## must not allocate. warm_up() draws one of everything below the floor at the first bench so the
## shaders compile before combat.

const TRACER_TIME := 0.07
const IMPACT_TIME := 0.12
const NUMBER_TIME := 0.6
const NUMBER_FADE_START := 0.35
const NUMBER_RISE := 0.7
const BURST_LIFETIME := 0.7
const MAX_TRACERS := 24
const MAX_IMPACTS := 24
const MAX_NUMBERS := 24
const MAX_BURSTS := 8
const TRACER_COLOR := Color(1.0, 0.9, 0.55, 0.7)
const IMPACT_COLOR := Color(1.0, 0.85, 0.5)
## Where warm-up draws its samples: just under the floor in front of the camera, inside the view
## but hidden by the floor's depth.
const WARM_UP_DEPTH := -0.7
const WARM_UP_DISTANCE := 4.0
const ENEMY_SCENES := [
	"res://scenes/enemies/chaser.tscn", "res://scenes/enemies/shooter.tscn",
	"res://scenes/enemies/swarm_drone.tscn", "res://scenes/enemies/warden.tscn",
]


class Entry:
	var node: Node3D
	var age := 0.0
	var life := 1.0
	var active := false
	var start_y := 0.0


var warmed_up := false

var _tracer_mesh := BoxMesh.new()
var _tracer_material := StandardMaterial3D.new()
var _impact_mesh := SphereMesh.new()
var _impact_material := StandardMaterial3D.new()
var _burst_mesh := BoxMesh.new()
var _tracers: Array[Entry] = []
var _impacts: Array[Entry] = []
var _numbers: Array[Entry] = []
var _bursts: Array[Entry] = []


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


func active_count() -> int:
	var count := 0
	for pool in [_tracers, _impacts, _numbers, _bursts]:
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


## Draws one of every effect, enemy and drop for a few frames so their shaders compile now, not
## in the first wave. Everything sits under the floor in front of the camera.
func warm_up(camera: Camera3D) -> void:
	if warmed_up or camera == null:
		return
	warmed_up = true
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
	var extras: Array[Node] = []
	for path in ENEMY_SCENES:
		var enemy: Node3D = load(path).instantiate()
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
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
	for pool in [_tracers, _impacts, _numbers, _bursts]:
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


func _age(entry: Entry, delta: float) -> bool:
	entry.age += delta
	return entry.age >= entry.life


## A free entry, a new one while the pool is under its cap, else the oldest active one.
func _acquire(pool: Array[Entry], cap: int, make: Callable) -> Entry:
	var oldest: Entry = null
	for entry in pool:
		if not entry.active:
			return _activate(entry)
		if oldest == null or entry.age > oldest.age:
			oldest = entry
	if pool.size() < cap:
		var entry := Entry.new()
		entry.node = make.call()
		add_child(entry.node)
		pool.append(entry)
		return _activate(entry)
	return _activate(oldest)


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
