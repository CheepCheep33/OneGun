extends Control
## Center crosshair plus the hit marker that confirms a shot connected (red and larger on a kill).

const HIT_TIME := 0.15
const KILL_TIME := 0.3

var _hit_left := 0.0
var _hit_duration := HIT_TIME
var _hit_was_kill := false


func show_hit(killed: bool) -> void:
	_hit_was_kill = killed
	_hit_duration = KILL_TIME if killed else HIT_TIME
	_hit_left = _hit_duration
	queue_redraw()


func _process(delta: float) -> void:
	if _hit_left > 0.0:
		_hit_left = maxf(_hit_left - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	draw_circle(center, 3.0, Color(0, 0, 0, 0.6))
	draw_circle(center, 1.8, Color.WHITE)
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(center + direction * 6.0, center + direction * 13.0, Color(0, 0, 0, 0.6), 4.0)
		draw_line(center + direction * 6.0, center + direction * 13.0, Color.WHITE, 2.0)
	if _hit_left <= 0.0:
		return
	var alpha := _hit_left / _hit_duration
	var color := Color(1.0, 0.25, 0.2, alpha) if _hit_was_kill else Color(1, 1, 1, alpha)
	var outer := 22.0 if _hit_was_kill else 16.0
	for diagonal in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var d: Vector2 = diagonal.normalized()
		draw_line(center + d * 8.0, center + d * outer, Color(0, 0, 0, alpha * 0.6), 5.0, true)
		draw_line(center + d * 8.0, center + d * outer, color, 2.5, true)
