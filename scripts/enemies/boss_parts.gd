class_name BossParts
extends RefCounted
## Pieces the late bosses share (the Sentinel and the Core Guardian): rotating shield arcs and a
## low laser sweep. Both drive nodes that are part of the boss's scene, so an attack builds
## nothing; they only move, turn, scale and show or hide them, and write no material parameter.


## Shield panels on a pivot that turns around the boss. Each panel is a StaticBody3D on the shield
## layer (4) in group "shields", as the shield bearer's: every player ray and round stops on it.
class Arcs:
	extends RefCounted
	const SHIELD_LAYER := 8
	var pivot: Node3D
	var panels: Array[StaticBody3D] = []
	## Radians a second.
	var speed := 1.2
	var raised := true

	func _init(arc_pivot: Node3D) -> void:
		pivot = arc_pivot
		for child in pivot.get_children():
			if child is StaticBody3D:
				panels.append(child)

	func tick(delta: float) -> void:
		if raised:
			pivot.rotation.y = wrapf(pivot.rotation.y + speed * delta, -PI, PI)

	func set_raised(value: bool) -> void:
		raised = value
		pivot.visible = value
		for panel in panels:
			var layer := SHIELD_LAYER if value else 0
			if panel.collision_layer != layer:
				panel.collision_layer = layer


## A beam at shin height that telegraphs (a dim line where it starts) and then turns once around
## the boss. A grounded player it passes over takes the hit once per sweep; a jump clears it, and
## cover between the boss and the player blocks it.
class Sweep:
	extends RefCounted
	var pivot: Node3D
	var warning: Node3D
	var beam: Node3D
	var length := 18.0
	var telegraph := 1.2
	var duration := 2.4
	var damage := 24.0
	## A player whose feet are this far above the boss's are over the beam.
	var escape_height := 0.55
	## The beam's height above the boss's feet. The pivot is top_level, so the boss turning to
	## face the player does not turn the beam.
	var height := 0.35
	var age := 0.0
	var active := false
	var hit_this_sweep := false
	var _start_angle := 0.0
	var _last_angle := 0.0

	func _init(sweep_pivot: Node3D) -> void:
		pivot = sweep_pivot
		warning = pivot.get_node("Warning")
		beam = pivot.get_node("Beam")
		hide()

	func start(towards: Vector3, from: Vector3) -> void:
		var offset := towards - from
		_start_angle = atan2(-offset.x, -offset.z)
		_last_angle = 0.0
		age = 0.0
		active = true
		hit_this_sweep = false
		pivot.visible = true
		warning.visible = true
		beam.visible = false
		pivot.global_position = from + Vector3.UP * height
		pivot.rotation.y = _start_angle
		pivot.scale = Vector3(1.0, 1.0, length)

	func is_firing() -> bool:
		return active and age >= telegraph

	## Advances the sweep; returns true on the frame it hits `player`. `boss` gives the centre.
	func tick(delta: float, boss: Enemy, player: Player) -> bool:
		if not active:
			return false
		pivot.global_position = boss.global_position + Vector3.UP * height
		var was_firing := is_firing()
		age += delta
		if age >= telegraph + duration:
			hide()
			return false
		if not is_firing():
			return false
		if not was_firing:
			warning.visible = false
			beam.visible = true
		var swept := clampf((age - telegraph) / duration, 0.0, 1.0) * TAU
		var from_angle := _last_angle
		_last_angle = swept
		pivot.rotation.y = _start_angle + swept
		if hit_this_sweep or player == null or not is_instance_valid(player) or player.is_dead:
			return false
		var offset := player.global_position - boss.global_position
		if Vector2(offset.x, offset.z).length() > length or offset.y > escape_height:
			return false
		var player_angle := wrapf(atan2(-offset.x, -offset.z) - _start_angle, 0.0, TAU)
		if player_angle < from_angle or player_angle > swept:
			return false
		if not boss.has_line_of_sight():
			return false
		hit_this_sweep = true
		return true

	func hide() -> void:
		active = false
		age = 0.0
		pivot.visible = false
