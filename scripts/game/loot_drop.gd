class_name LootDrop
extends Area3D
## A dropped attachment on the arena floor: a colour-coded beam so rarity reads from across the
## arena, picked up automatically when the player walks over it (plan: Loot rarity, auto pickup).
## Built in code so no scene is needed. The nodes are recycled by the game (a reserve filled at the
## bench, like enemies), the beam and gem meshes are shared, the materials are made once per rarity
## and the name tag is a pooled 2D label (Fx.attach_label), so a drop landing mid-wave builds and
## uploads nothing. The game auto-collects every drop left when a wave clears and discards them on
## death.

signal picked_up(drop: LootDrop)
## Emitted once the drop may leave the arena (picked up or cleared); the game recycles the node.
signal retired(drop: LootDrop)

const PICKUP_RADIUS := 1.2
const BEAM_HEIGHT := 3.2
const LABEL_HEIGHT := 1.5
const SPIN_SPEED := 2.2
const BOB_SPEED := 2.6

static var _beam_mesh: CylinderMesh
static var _gem_mesh: BoxMesh
## Rarity index -> [beam material, gem material], made once (warm_up_materials).
static var _materials: Dictionary = {}

var item: Dictionary = {}
var _beam: MeshInstance3D
var _gem: MeshInstance3D
var _time := 0.0
var _collected := false


static func create(dropped_item: Dictionary) -> LootDrop:
	var drop := LootDrop.new()
	drop.item = dropped_item
	return drop


## Every rarity's beam and gem material and the shared meshes, so the first drop of each rarity
## builds nothing. Called by the shader warm-up.
static func warm_up_materials() -> void:
	_shared_meshes()
	for rarity in Items.RARITY_COLORS.size():
		_materials_for(rarity)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # the player
	monitoring = true
	monitorable = false
	_shared_meshes()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICKUP_RADIUS
	shape.shape = sphere
	shape.position = Vector3.UP * 0.8
	add_child(shape)

	_beam = MeshInstance3D.new()
	_beam.mesh = _beam_mesh
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position = Vector3.UP * BEAM_HEIGHT * 0.5
	add_child(_beam)

	_gem = MeshInstance3D.new()
	_gem.mesh = _gem_mesh
	_gem.position = Vector3.UP * 0.9
	add_child(_gem)
	body_entered.connect(_on_body_entered)
	if not item.is_empty():
		reset(item)


func _exit_tree() -> void:
	Fx.detach_label(self, self)


## Dresses the node for `dropped_item`: rarity colours and the name. Runs for a fresh node and
## again each time a recycled one lands.
func reset(dropped_item: Dictionary) -> void:
	item = dropped_item
	_collected = false
	_time = 0.0
	var rarity := clampi(int(item.get("rarity", 0)), 0, Items.RARITY_COLORS.size() - 1)
	var materials := _materials_for(rarity)
	_beam.material_override = materials[0]
	_gem.material_override = materials[1]
	_gem.rotation = Vector3(0.6, 0.0, 0.0)
	_gem.position.y = 0.9
	if is_inside_tree():
		Fx.attach_label(self, self, Vector3.UP * LABEL_HEIGHT, "%s\n%s" % [Items.display_name(item), Items.rarity_name(item)], Items.rarity_color(item))


func _process(delta: float) -> void:
	_time += delta
	_gem.rotation.y += SPIN_SPEED * delta
	_gem.rotation.x = 0.6
	_gem.position.y = 0.9 + sin(_time * BOB_SPEED) * 0.1


func _on_body_entered(body: Node3D) -> void:
	if body is Player and not body.is_dead:
		collect()


## Hands the item over and retires the drop. Also used when a cleared wave auto-collects.
func collect() -> void:
	if _collected:
		return
	_collected = true
	picked_up.emit(self)
	retired.emit(self)


static func _shared_meshes() -> void:
	if _beam_mesh != null:
		return
	_beam_mesh = CylinderMesh.new()
	_beam_mesh.top_radius = 0.05
	_beam_mesh.bottom_radius = 0.09
	_beam_mesh.height = BEAM_HEIGHT
	_beam_mesh.radial_segments = 8
	_gem_mesh = BoxMesh.new()
	_gem_mesh.size = Vector3.ONE * 0.28


static func _materials_for(rarity: int) -> Array:
	if not _materials.has(rarity):
		var color: Color = Items.RARITY_COLORS[rarity]
		_materials[rarity] = [_glow(Color(color.r, color.g, color.b, 0.55)), _glow(color)]
	return _materials[rarity]


static func _glow(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
