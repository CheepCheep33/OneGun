class_name LootDrop
extends Area3D
## A dropped attachment on the arena floor: a colour-coded beam so rarity reads from across the
## arena, picked up automatically when the player walks over it (plan: Loot rarity, auto pickup).
## Built in code so no scene is needed; the game auto-collects every drop left when a wave clears
## and discards them on death.

signal picked_up(drop: LootDrop)

const PICKUP_RADIUS := 1.2
const BEAM_HEIGHT := 3.2
const SPIN_SPEED := 2.2
const BOB_SPEED := 2.6

var item: Dictionary = {}
var _gem: MeshInstance3D
var _time := 0.0
var _collected := false


static func create(dropped_item: Dictionary) -> LootDrop:
	var drop := LootDrop.new()
	drop.item = dropped_item
	return drop


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # the player
	monitoring = true
	monitorable = false
	var color := Items.rarity_color(item)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICKUP_RADIUS
	shape.shape = sphere
	shape.position = Vector3.UP * 0.8
	add_child(shape)

	var beam := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.05
	cylinder.bottom_radius = 0.09
	cylinder.height = BEAM_HEIGHT
	cylinder.radial_segments = 8
	beam.mesh = cylinder
	beam.material_override = _glow(Color(color.r, color.g, color.b, 0.55))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3.UP * BEAM_HEIGHT * 0.5
	add_child(beam)

	_gem = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.28
	_gem.mesh = box
	_gem.material_override = _glow(color)
	_gem.position = Vector3.UP * 0.9
	add_child(_gem)

	var label := Label3D.new()
	label.text = "%s\n%s" % [Items.display_name(item), Items.rarity_name(item)]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0005
	label.font_size = 36
	label.outline_size = 10
	label.modulate = color
	label.position = Vector3.UP * 1.5
	add_child(label)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	_gem.rotation.y += SPIN_SPEED * delta
	_gem.rotation.x = 0.6
	_gem.position.y = 0.9 + sin(_time * BOB_SPEED) * 0.1


func _on_body_entered(body: Node3D) -> void:
	if body is Player and not body.is_dead:
		collect()


## Hands the item over and removes the drop. Also used when a cleared wave auto-collects.
func collect() -> void:
	if _collected:
		return
	_collected = true
	picked_up.emit(self)
	queue_free()


static func _glow(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
