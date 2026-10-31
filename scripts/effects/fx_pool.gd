class_name FxPool
extends Node3D
## The pool behind Fx: tracers, impact sparks, damage numbers, death bursts, death sounds, the
## Warden's slam ring and explosive blasts are fixed sets of nodes with shared meshes and materials, shown and hidden
## instead of created and freed. One pool lives under the running scene (Fx makes it on first use)
## and ages every active effect in one _process. This exists for the browser build: every
## allocation, mesh upload and first-use shader compile there lands on the single main thread and
## shows as a hitch, so a wave of fire must not allocate (tests/cases/perf_cases.gd fails if it
## does). warm_up() builds every pool to its cap and draws one of everything below the floor at the
## first bench so the shaders compile before combat, with the muzzle light on and then off, because
## a material touched by a point light for the first time compiles a second, lit shader variant.
##
## Damage numbers and the drops' name tags are 2D labels, placed where their world position
## projects each frame, drawn inside the HUD's canvas layer (a layer of their own would make the
## renderer grow its canvas buffers mid-wave). A Label3D would rebuild its mesh and material on
## every change, including each frame of a fade, which is a GPU allocation per number per frame.

const TRACER_TIME := 0.07
const IMPACT_TIME := 0.12
const NUMBER_TIME := 0.6
const NUMBER_FADE_START := 0.35
## World metres a damage number drifts up over its life.
const NUMBER_RISE := 0.7
const NUMBER_FONT_SIZE := 22
const KILL_FONT_SIZE := 30
const NUMBER_OUTLINE := 6
const NUMBER_COLOR := Color(1.0, 0.95, 0.75)
const KILL_COLOR := Color(1.0, 0.55, 0.3)
## Weak-point hits: the kill size (so no new glyph size enters the font atlas), in yellow.
const WEAK_COLOR := Color(1.0, 0.9, 0.2)
const LABEL_FONT_SIZE := 16
const LABEL_OUTLINE := 5
const BURST_LIFETIME := 0.7
const RING_START_SCALE := 0.3
const RING_ALPHA := 0.85
const BLAST_TIME := 0.22
## Added onto the scene, so overlapping blasts read as a bright flash rather than an orange wall.
const BLAST_COLOR := Color(1.0, 0.5, 0.15, 0.22)
const MAX_TRACERS := 24
const MAX_IMPACTS := 24
const MAX_NUMBERS := 24
const MAX_BURSTS := 8
const MAX_SOUNDS := 8
const MAX_RINGS := 2
const MAX_BLASTS := 8
## Name tags that follow a node (floor drops); as many as the game's drop reserve.
const MAX_LABELS := 12
const TRACER_COLOR := Color(1.0, 0.9, 0.55, 0.7)
const IMPACT_COLOR := Color(1.0, 0.85, 0.5)
## Where warm-up draws its samples: just under the floor in front of the camera, inside the view
## but hidden by the floor's depth.
const WARM_UP_DEPTH := -0.7
const WARM_UP_DISTANCE := 4.0
## Frames the warm-up draws its samples with the muzzle light on, then with it off.
const WARM_UP_LIT_FRAMES := 2
const WARM_UP_UNLIT_FRAMES := 2
## Enemy scenes to warm up besides the ones the wave data names (side-area enemies, a boss before
## its wave exists). The waves themselves are read by warm_up_scene_paths().
const EXTRA_WARM_UP_SCENES: Array[String] = []
## Used when no wave data loads at all.
const FALLBACK_WARM_UP_SCENES: Array[String] = ["res://scenes/enemies/chaser.tscn"]


class Entry:
	## A Node3D for every pool but the numbers and labels, whose node is a 2D Label on the canvas.
	var node: Node
	var age := 0.0
	var life := 1.0
	var active := false
	## Numbers: the world position the label follows. Labels: the offset from their owner.
	var anchor := Vector3.ZERO
	## Labels: the node they follow.
	var owner: Node3D
	## Rings and blasts: the radius to grow to.
	var size := 1.0


var warmed_up := false
## The enemy scenes the warm-up drew, for the performance gate.
var warmed_scenes: Array[String] = []
## True once the warm-up drew the arena and its samples with the muzzle light on, so every lit
## shader variant the first shots would have compiled exists already.
var warmed_muzzle_light := false

var _tracer_mesh := BoxMesh.new()
var _tracer_material := StandardMaterial3D.new()
var _impact_mesh := SphereMesh.new()
var _impact_material := StandardMaterial3D.new()
var _burst_mesh := BoxMesh.new()
var _ring_mesh := TorusMesh.new()
var _blast_mesh := SphereMesh.new()
var _blast_material := StandardMaterial3D.new()
## Holds every 2D label; the first child of the HUD's layer once set_label_parent ran (drawn under
## the HUD's own items), otherwise under a canvas layer of the pool's own.
var _label_root := Control.new()
var _own_canvas: CanvasLayer
var _number_settings := LabelSettings.new()
var _kill_settings := LabelSettings.new()
var _weak_settings := LabelSettings.new()
var _label_settings := LabelSettings.new()
var _tracers: Array[Entry] = []
var _impacts: Array[Entry] = []
var _numbers: Array[Entry] = []
var _labels: Array[Entry] = []
var _bursts: Array[Entry] = []
var _sounds: Array[Entry] = []
var _rings: Array[Entry] = []
var _blasts: Array[Entry] = []


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
	_blast_mesh.radius = 1.0
	_blast_mesh.height = 2.0
	_blast_mesh.radial_segments = 16
	_blast_mesh.rings = 8
	_blast_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blast_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blast_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_blast_material.albedo_color = BLAST_COLOR
	_label_root.name = "WorldLabels"
	_label_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_own_canvas = CanvasLayer.new()
	_own_canvas.name = "Labels"
	_own_canvas.layer = 0
	add_child(_own_canvas)
	_own_canvas.add_child(_label_root)
	for settings: LabelSettings in [_number_settings, _kill_settings, _weak_settings, _label_settings]:
		settings.outline_size = NUMBER_OUTLINE
		settings.outline_color = Color(0.0, 0.0, 0.0, 0.9)
	_number_settings.font_size = NUMBER_FONT_SIZE
	_number_settings.font_color = NUMBER_COLOR
	_kill_settings.font_size = KILL_FONT_SIZE
	_kill_settings.font_color = KILL_COLOR
	_weak_settings.font_size = KILL_FONT_SIZE
	_weak_settings.font_color = WEAK_COLOR
	_label_settings.font_size = LABEL_FONT_SIZE
	_label_settings.outline_size = LABEL_OUTLINE


## Moves the labels into `parent` (the HUD's canvas layer) as its first child, so they draw over the
## world and under the HUD without a canvas layer of their own.
func set_label_parent(parent: Node) -> void:
	if parent == null or _label_root.get_parent() == parent:
		return
	_label_root.get_parent().remove_child(_label_root)
	parent.add_child(_label_root)
	parent.move_child(_label_root, 0)
	_label_root.set_anchors_preset(Control.PRESET_FULL_RECT)


## The node the 2D labels live under, for the checks.
func label_parent() -> Node:
	return _label_root.get_parent()


## Every enemy scene the authored waves spawn, plus EXTRA_WARM_UP_SCENES, in a stable order. A new
## enemy added to a wave is warmed up without touching this file.
static func warm_up_scene_paths() -> Array[String]:
	var paths: Array[String] = []
	for wave in WaveRunner.all_waves():
		for group in wave.groups:
			if group.enemy_scene != null and not paths.has(group.enemy_scene.resource_path):
				paths.append(group.enemy_scene.resource_path)
			var summon := group.definition.summon_scene if group.definition else null
			if summon != null and not paths.has(summon.resource_path):
				paths.append(summon.resource_path)
	for path in EXTRA_WARM_UP_SCENES:
		if not paths.has(path):
			paths.append(path)
	if paths.is_empty():
		paths.assign(FALLBACK_WARM_UP_SCENES)
	return paths


func active_count() -> int:
	var count := 0
	for pool in [_tracers, _impacts, _numbers, _labels, _bursts, _sounds, _rings, _blasts]:
		for entry in pool:
			if entry.active:
				count += 1
	return count


## Every pooled node, in the 3D pools and among the labels.
func pooled_count() -> int:
	var count := 0
	for pool in [_tracers, _impacts, _numbers, _labels, _bursts, _sounds, _rings, _blasts]:
		count += pool.size()
	return count


func tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.3:
		return
	var entry := _acquire(_tracers, MAX_TRACERS, _make_tracer)
	entry.life = TRACER_TIME
	var direction := (to - from) / length
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var node: Node3D = entry.node
	node.look_at_from_position(from.lerp(to, 0.5), to, up)
	node.scale = Vector3(1.0, 1.0, length)


func impact(position: Vector3, normal: Vector3) -> void:
	var entry := _acquire(_impacts, MAX_IMPACTS, _make_impact)
	entry.life = IMPACT_TIME
	var node: Node3D = entry.node
	node.global_position = position + normal * 0.02
	node.scale = Vector3.ONE


## A number that rises from a world position and fades, drawn on the canvas under the HUD.
func damage_number(position: Vector3, amount: float, killed: bool, weak := false) -> void:
	var entry := _acquire(_numbers, MAX_NUMBERS, _make_number)
	entry.life = NUMBER_TIME
	entry.anchor = position + Vector3(randf_range(-0.15, 0.15), 0.2, randf_range(-0.15, 0.15))
	var label: Label = entry.node
	label.text = str(roundi(amount))
	label.label_settings = _weak_settings if weak else (_kill_settings if killed else _number_settings)
	label.modulate = Color.WHITE
	_place_number(entry, 0.0)


## A name tag that follows `owner` at `offset` until detach_label(owner) or the owner leaves the
## tree: the floor drops' names. One per owner; calling again replaces the text.
func attach_label(owner: Node3D, offset: Vector3, text: String, color: Color) -> void:
	if owner == null:
		return
	var entry := _label_for(owner)
	if entry == null:
		entry = _acquire(_labels, MAX_LABELS, _make_label)
	entry.life = INF
	entry.owner = owner
	entry.anchor = offset
	var label: Label = entry.node
	label.text = text
	label.label_settings = _label_settings
	label.modulate = color
	_place_label(entry)


func detach_label(owner: Node3D) -> void:
	var entry := _label_for(owner)
	if entry != null:
		entry.owner = null
		_release(entry)


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


## A sphere that swells from small to `radius` over BLAST_TIME and vanishes: an explosive round's
## blast. Scale only, so no material parameter is written per frame.
func blast(position: Vector3, radius: float) -> void:
	var entry := _acquire(_blasts, MAX_BLASTS, _make_blast)
	entry.life = BLAST_TIME
	entry.size = maxf(radius, 0.1)
	var node: Node3D = entry.node
	node.global_position = position
	node.scale = Vector3.ONE * entry.size * 0.25


## Builds every pool to its cap, then draws one of every effect, projectile, enemy and drop for a
## few frames so their shaders compile now, not in the first wave. Everything sits under the floor
## in front of the camera. With `gun`, the first frames are drawn with its muzzle light reaching
## the whole arena, so the lit variant of every shader in view compiles too (see
## Pistol.set_warm_up_flash). `label_parent` is the HUD's canvas layer for the 2D labels. After
## this, combat creates no nodes and compiles nothing.
func warm_up(camera: Camera3D, gun: Pistol = null, new_label_parent: Node = null) -> void:
	if warmed_up or camera == null:
		return
	warmed_up = true
	set_label_parent(new_label_parent)
	_fill(_tracers, MAX_TRACERS, _make_tracer)
	_fill(_impacts, MAX_IMPACTS, _make_impact)
	_fill(_numbers, MAX_NUMBERS, _make_number)
	_fill(_labels, MAX_LABELS, _make_label)
	_fill(_bursts, MAX_BURSTS, _make_burst)
	_fill(_sounds, MAX_SOUNDS, _make_sound)
	_fill(_rings, MAX_RINGS, _make_ring)
	_fill(_blasts, MAX_BLASTS, _make_blast)
	LootDrop.warm_up_materials()
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var spot := camera.global_position + forward * WARM_UP_DISTANCE
	spot.y = WARM_UP_DEPTH
	tracer(spot + Vector3(-0.5, 0.0, 0.0), spot + Vector3(0.5, 0.0, 0.0))
	impact(spot, Vector3.UP)
	burst(spot, Color.WHITE)
	ring(spot, 1.0, Color.WHITE, 0.3)
	blast(spot, 0.4)
	for entry in _blasts:
		entry.life = INF # held for the warm-up's frames, released with the rest
	# Every digit at both sizes goes into the font atlas now; the labels draw invisibly.
	damage_number(spot, 1234567890, false)
	damage_number(spot, 1234567890, true)
	damage_number(spot, 1234567890, true, true)
	for entry in _numbers:
		if entry.active:
			(entry.node as Label).modulate = Color(1.0, 1.0, 1.0, 0.0)
	var projectiles := ProjectilePool.current
	if projectiles != null:
		projectiles.show_warm_up_sample(spot)
	var extras: Array[Node] = []
	warmed_scenes = warm_up_scene_paths()
	for path in warmed_scenes:
		var enemy: Node3D = load(path).instantiate()
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(enemy)
		enemy.global_position = spot
		# After _ready, which hides telegraphs such as the Warden's ring and the Foreman's pools.
		_show_hidden_meshes(enemy, spot)
		extras.append(enemy)
	var sample := Items.make(&"long_barrel", Items.Rarity.UNCOMMON)
	var drop := LootDrop.create(sample)
	drop.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(drop)
	drop.global_position = spot
	extras.append(drop)
	for entry in _labels:
		if entry.active:
			(entry.node as Label).modulate = Color(1.0, 1.0, 1.0, 0.0)
	if gun != null:
		gun.set_warm_up_flash(true)
		warmed_muzzle_light = true
	for i in WARM_UP_LIT_FRAMES:
		await get_tree().process_frame
	if is_instance_valid(gun):
		gun.set_warm_up_flash(false)
	for i in WARM_UP_UNLIT_FRAMES:
		await get_tree().process_frame
	for extra in extras:
		if is_instance_valid(extra):
			extra.queue_free()
	if is_instance_valid(projectiles):
		projectiles.hide_warm_up_sample()
	for pool in [_tracers, _impacts, _numbers, _labels, _bursts, _sounds, _rings, _blasts]:
		for entry in pool:
			_release(entry)


## Draws whatever is in view with the muzzle light reaching all of it for a couple of frames, then
## without: for a freshly loaded area, whose materials have not met the light yet.
func warm_up_lighting(gun: Pistol) -> void:
	if gun == null:
		return
	gun.set_warm_up_flash(true)
	for i in WARM_UP_LIT_FRAMES:
		await get_tree().process_frame
	if is_instance_valid(gun):
		gun.set_warm_up_flash(false)


func _process(delta: float) -> void:
	for entry in _tracers:
		if entry.active and _age(entry, delta):
			_release(entry)
	for entry in _impacts:
		if entry.active:
			if _age(entry, delta):
				_release(entry)
			else:
				var node: Node3D = entry.node
				node.scale = Vector3.ONE * lerpf(1.0, 0.1, entry.age / entry.life)
	for entry in _numbers:
		if entry.active:
			if _age(entry, delta):
				_release(entry)
			else:
				var t := entry.age / entry.life
				var rise := 1.0 - pow(1.0 - t, 3.0)
				_place_number(entry, NUMBER_RISE * rise)
				var fade := clampf((entry.age - NUMBER_FADE_START) / (entry.life - NUMBER_FADE_START), 0.0, 1.0)
				var label: Label = entry.node
				label.modulate.a = 1.0 - fade
	for entry in _labels:
		if entry.active:
			if entry.owner == null or not is_instance_valid(entry.owner) or not entry.owner.is_inside_tree():
				entry.owner = null
				_release(entry)
			else:
				_place_label(entry)
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
				var node: MeshInstance3D = entry.node
				node.scale = Vector3(grown, RING_START_SCALE, grown)
				var material: StandardMaterial3D = node.material_override
				material.albedo_color.a = RING_ALPHA * (1.0 - t)
	for entry in _blasts:
		if entry.active:
			if _age(entry, delta):
				_release(entry)
			else:
				var swell := 0.25 + 0.75 * (1.0 - pow(1.0 - entry.age / entry.life, 2.0))
				var node: Node3D = entry.node
				node.scale = Vector3.ONE * entry.size * swell
	for entry in _sounds:
		if entry.active:
			entry.age += delta
			var player: AudioStreamPlayer3D = entry.node
			if not player.playing:
				_release(entry)


func _age(entry: Entry, delta: float) -> bool:
	entry.age += delta
	return entry.age >= entry.life


## Puts a number's label where its anchor, lifted by `rise`, lands on screen.
func _place_number(entry: Entry, rise: float) -> void:
	_place_at(entry.node, entry.anchor + Vector3.UP * rise)


func _place_label(entry: Entry) -> void:
	_place_at(entry.node, entry.owner.global_position + entry.anchor)


## Centres a 2D label on the screen point of `world`; hidden while that point is behind the camera.
func _place_at(label: Label, world: Vector3) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	if camera.is_position_behind(world):
		label.visible = false
		return
	label.visible = true
	label.position = camera.unproject_position(world) - label.get_minimum_size() * 0.5


func _label_for(owner: Node3D) -> Entry:
	for entry in _labels:
		if entry.active and entry.owner == owner:
			return entry
	return null


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
	_set_visible(entry, false)
	if entry.node is CanvasItem:
		_label_root.add_child(entry.node)
	else:
		add_child(entry.node)
	pool.append(entry)
	return entry


func _activate(entry: Entry) -> Entry:
	entry.active = true
	entry.age = 0.0
	_set_visible(entry, true)
	return entry


func _release(entry: Entry) -> void:
	entry.active = false
	_set_visible(entry, false)
	if entry.node is CPUParticles3D:
		entry.node.emitting = false
	elif entry.node is AudioStreamPlayer3D:
		entry.node.stop()


func _set_visible(entry: Entry, value: bool) -> void:
	if entry.node is CanvasItem:
		(entry.node as CanvasItem).visible = value
	else:
		(entry.node as Node3D).visible = value


## Shows every 3D node under `node`, telegraphs and pools included; one that does not follow its
## parent's transform (top level, or under a plain Node) is moved to `spot` with the rest.
func _show_hidden_meshes(node: Node, spot: Vector3) -> void:
	for child in node.get_children():
		if child is Node3D:
			child.visible = true
			if child.top_level or not (node is Node3D):
				child.global_position = spot
		_show_hidden_meshes(child, spot)


func _make_tracer() -> Node:
	var node := MeshInstance3D.new()
	node.mesh = _tracer_mesh
	node.material_override = _tracer_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _make_impact() -> Node:
	var node := MeshInstance3D.new()
	node.mesh = _impact_mesh
	node.material_override = _impact_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _make_number() -> Node:
	var label := Label.new()
	label.label_settings = _number_settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_label() -> Node:
	var label := Label.new()
	label.label_settings = _label_settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_burst() -> Node:
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


func _make_sound() -> Node:
	var player := AudioStreamPlayer3D.new()
	player.unit_size = 8.0
	return player


func _make_blast() -> Node:
	var node := MeshInstance3D.new()
	node.mesh = _blast_mesh
	node.material_override = _blast_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _make_ring() -> Node:
	var node := MeshInstance3D.new()
	node.mesh = _ring_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 1.0, 1.0, RING_ALPHA)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
