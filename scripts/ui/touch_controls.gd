class_name TouchControls
extends CanvasLayer
## Temporary on-screen controls for testing on phones and tablets. Hidden until the first touch.
## Left thumb: floating stick to move (push to the edge to sprint). Drag elsewhere to look.
## Buttons: fire (dragging from it also looks), reload, jump, pause.

signal activated
signal pause_requested

const REFERENCE_HEIGHT := 720.0
const STICK_RADIUS := 80.0
## Share of the screen width, from the left, where a touch starts the move stick.
const STICK_ZONE := 0.45
const SPRINT_THRESHOLD := 0.9
## Touch drags turn this much faster than the same distance of mouse movement.
const LOOK_SCALE := 2.5
const BUTTON_HIT_SLOP := 1.15

var active := false
## Cleared while the player is dead so the death screen gets the taps.
var enabled := true

var _player: Player
var _touches := {} # finger index -> role: &"move", &"look", or a button name
## Last position of each finger. Look deltas are computed from this rather than the event's
## `relative`: Godot 4.3's web build pairs touches by list order instead of finger, so with two
## fingers down `relative` can be measured from the other finger and the view jumps.
var _last_positions := {}
var _stick_center := Vector2.ZERO
var _stick_vector := Vector2.ZERO
var _stick_radius := STICK_RADIUS
var _scale := 1.0
var _buttons := {} # name -> { center, radius, label }

@onready var _canvas: Control = $Canvas


func setup(player: Player) -> void:
	_player = player


func _ready() -> void:
	visible = false
	_canvas.draw.connect(_draw_controls)
	get_viewport().size_changed.connect(_layout)
	_layout()


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		release_all()
	visible = active and enabled


## Lets go of every held control, e.g. when pausing, since the matching touch-up may never arrive.
func release_all() -> void:
	for role in _touches.values():
		if role == &"jump":
			Input.action_release("jump")
	_touches.clear()
	_last_positions.clear()
	_set_stick(Vector2.ZERO)
	_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_touch_down(event.index, event.position)
		else:
			_on_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position)


func _on_touch_down(index: int, position: Vector2) -> void:
	if not active:
		active = true
		visible = enabled
		activated.emit()
	if not enabled:
		return
	_last_positions[index] = position
	for button: StringName in _buttons:
		var data: Dictionary = _buttons[button]
		if position.distance_to(data.center) <= data.radius * BUTTON_HIT_SLOP:
			_touches[index] = button
			_press(button)
			_canvas.queue_redraw()
			return
	var screen := get_viewport().get_visible_rect().size
	if position.x < screen.x * STICK_ZONE and not _touches.values().has(&"move"):
		_touches[index] = &"move"
		_stick_center = position
		_set_stick(Vector2.ZERO)
	else:
		_touches[index] = &"look"
	_canvas.queue_redraw()


func _on_touch_up(index: int) -> void:
	var role: StringName = _touches.get(index, &"")
	_touches.erase(index)
	_last_positions.erase(index)
	if role == &"move":
		_set_stick(Vector2.ZERO)
	elif role == &"jump":
		Input.action_release("jump")
	_canvas.queue_redraw()


func _on_drag(index: int, position: Vector2) -> void:
	if not enabled or _player == null:
		return
	var relative: Vector2 = position - _last_positions.get(index, position)
	_last_positions[index] = position
	match _touches.get(index, &""):
		&"move":
			_set_stick((position - _stick_center).limit_length(_stick_radius) / _stick_radius)
			_canvas.queue_redraw()
		&"look", &"fire":
			_player.look(relative * LOOK_SCALE / _scale)


func _press(button: StringName) -> void:
	match button:
		&"fire":
			_player.pistol.request_fire()
		&"reload":
			_player.pistol.request_reload()
		&"jump":
			Input.action_press("jump")
		&"pause":
			pause_requested.emit()


func _set_stick(value: Vector2) -> void:
	_stick_vector = value
	_set_action("move_left", -value.x)
	_set_action("move_right", value.x)
	_set_action("move_forward", -value.y)
	_set_action("move_back", value.y)
	_set_action("sprint", 1.0 if value.length() >= SPRINT_THRESHOLD else 0.0)


func _set_action(action: StringName, strength: float) -> void:
	if strength > 0.05:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	_scale = minf(screen.x, screen.y) / REFERENCE_HEIGHT
	_stick_radius = STICK_RADIUS * _scale
	_buttons = {
		&"fire": {center = screen - Vector2(150, 160) * _scale, radius = 78.0 * _scale, label = "FIRE"},
		&"reload": {center = screen - Vector2(300, 90) * _scale, radius = 46.0 * _scale, label = "R"},
		&"jump": {center = screen - Vector2(110, 330) * _scale, radius = 50.0 * _scale, label = "JUMP"},
		&"pause": {center = Vector2(screen.x / 2.0, 52.0 * _scale), radius = 32.0 * _scale, label = "II"},
	}
	_canvas.queue_redraw()


func _draw_controls() -> void:
	var font := ThemeDB.fallback_font
	var screen := get_viewport().get_visible_rect().size
	var moving := _touches.values().has(&"move")
	# While idle, show a faint stick where the left thumb usually rests.
	var center := _stick_center if moving else Vector2(170.0 * _scale, screen.y - 170.0 * _scale)
	_canvas.draw_circle(center, _stick_radius, Color(1, 1, 1, 0.12 if moving else 0.06))
	_canvas.draw_arc(center, _stick_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.45 if moving else 0.25), 2.0, true)
	_canvas.draw_circle(center + _stick_vector * _stick_radius, _stick_radius * 0.42, Color(1, 1, 1, 0.5 if moving else 0.2))
	for button: StringName in _buttons:
		var data: Dictionary = _buttons[button]
		var held := _touches.values().has(button)
		_canvas.draw_circle(data.center, data.radius, Color(1, 1, 1, 0.3 if held else 0.12))
		_canvas.draw_arc(data.center, data.radius, 0.0, TAU, 48, Color(1, 1, 1, 0.6), 2.0, true)
		var font_size := int(22 * _scale)
		var text: String = data.label
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		_canvas.draw_string(font, data.center + Vector2(-text_size.x / 2.0, font_size * 0.35), text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(1, 1, 1, 0.85))
