extends Node3D
## Graybox combat arena. Bakes its navigation mesh on load so enemy pathing always matches the layout.

@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var _player_start: Marker3D = $PlayerStart


func _ready() -> void:
	_nav_region.bake_navigation_mesh(false)


func get_player_start() -> Transform3D:
	return _player_start.global_transform


func get_spawn_points() -> Array[Marker3D]:
	var points: Array[Marker3D] = []
	for node in get_tree().get_nodes_in_group("enemy_spawn"):
		if is_ancestor_of(node):
			points.append(node)
	return points
