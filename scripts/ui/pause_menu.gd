class_name PauseMenu
extends CanvasLayer
## Pause menu with resume, abandon wave, quit, and player options. Runs while the tree is paused.

signal resume_requested
## Leave the wave and go back to the bench (kill credits kept, no completion bonus).
signal abandon_requested
signal quit_requested

@onready var _options: VBoxContainer = %Options


func _ready() -> void:
	visible = false
	%ResumeButton.pressed.connect(func() -> void: resume_requested.emit())
	%AbandonButton.pressed.connect(func() -> void: abandon_requested.emit())
	%QuitButton.pressed.connect(func() -> void: quit_requested.emit())
	_add_slider("Mouse sensitivity", &"mouse_sensitivity", Settings.MOUSE_SENSITIVITY_RANGE, 0.05, "%.2f")
	_add_slider("Field of view", &"field_of_view", Settings.FIELD_OF_VIEW_RANGE, 1.0, "%d")
	_add_slider("Camera recoil", &"camera_recoil", Settings.CAMERA_RECOIL_RANGE, 0.05, "%.2f")
	_add_slider("Volume", &"master_volume", Vector2(0.0, 1.0), 0.05, "%.2f")
	_add_toggle("Damage numbers", &"show_damage_numbers")


func open() -> void:
	visible = true
	%ResumeButton.grab_focus()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		resume_requested.emit()
		get_viewport().set_input_as_handled()


func _add_slider(label_text: String, key: StringName, value_range: Vector2, step: float, value_format: String) -> void:
	var row := _add_row(label_text)
	var slider := HSlider.new()
	slider.min_value = value_range.x
	slider.max_value = value_range.y
	slider.step = step
	slider.value = Settings.get(key)
	slider.custom_minimum_size = Vector2(200, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(48, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = value_format % slider.value
	slider.value_changed.connect(func(value: float) -> void:
		Settings.set_value(key, value)
		value_label.text = value_format % value)
	row.add_child(slider)
	row.add_child(value_label)


func _add_toggle(label_text: String, key: StringName) -> void:
	var row := _add_row(label_text)
	var check := CheckButton.new()
	check.button_pressed = Settings.get(key)
	check.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	row.add_child(check)


func _add_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(170, 0)
	row.add_child(label)
	_options.add_child(row)
	return row
