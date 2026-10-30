class_name TargetDummy
extends StaticBody3D
## A Firing Range target. Sits on the enemy physics layer so the pistol's rays hit it, never dies,
## and shows a live readout of the last hit and damage per second. Roles: "dummy" (readout),
## "start" (begins the gallery), "choose" (picks the gallery reward slot), "gallery" (pops up
## during a run and vanishes when hit).

signal struck(dummy: TargetDummy, damage: float)

const DPS_WINDOW := 3.0
const FLASH_TIME := 0.08

@export var role := "dummy"
## For "choose" plates: the gunsmith slot the gallery reward comes from.
@export var slot_choice: StringName = &""
@export var label_text := ""
@export var size := Vector3(0.9, 1.8, 0.3)
@export var color := Color(0.75, 0.75, 0.78)

var hits := 0
var total_damage := 0.0
var _recent: Array = [] # [time, damage]
var _flash_left := 0.0
var _material: StandardMaterial3D
var _readout: Label3D
var _highlight := false


func _ready() -> void:
	collision_layer = 4 # enemies: the pistol's hit mask
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3.UP * size.y * 0.5
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	_material.emission_enabled = true
	_material.emission = Color.BLACK
	mesh.material_override = _material
	mesh.position = Vector3.UP * size.y * 0.5
	add_child(mesh)
	_readout = Label3D.new()
	_readout.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_readout.fixed_size = true
	_readout.pixel_size = 0.0009
	_readout.font_size = 34
	_readout.outline_size = 10
	_readout.position = Vector3.UP * (size.y + 0.45)
	add_child(_readout)
	_refresh_readout()


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_material.emission = color * 0.6 if _highlight else Color.BLACK
	if role == "dummy" and not _recent.is_empty():
		_refresh_readout()


## Called by the shot pipeline. Returns true for pop-up targets so the hit marker reads as a kill.
func take_hit(damage: float, _point: Vector3, _direction: Vector3) -> bool:
	hits += 1
	total_damage += damage
	_recent.append([Time.get_ticks_msec() / 1000.0, damage])
	_material.emission = Color.WHITE * 2.0
	_flash_left = FLASH_TIME
	struck.emit(self, damage)
	if role == "gallery":
		visible = false
		collision_layer = 0
		return true
	_refresh_readout()
	return false


func set_highlight(value: bool) -> void:
	_highlight = value
	_material.emission = color * 0.6 if value else Color.BLACK


func damage_per_second() -> float:
	var now := Time.get_ticks_msec() / 1000.0
	var sum := 0.0
	var kept := []
	for entry in _recent:
		if now - entry[0] <= DPS_WINDOW:
			sum += entry[1]
			kept.append(entry)
	_recent = kept
	return sum / DPS_WINDOW


func _refresh_readout() -> void:
	match role:
		"dummy":
			var last := float(_recent.back()[1]) if not _recent.is_empty() else 0.0
			_readout.text = "%s\nlast %d  ·  %d /s" % [label_text, roundi(last), roundi(damage_per_second())]
		_:
			_readout.text = label_text
